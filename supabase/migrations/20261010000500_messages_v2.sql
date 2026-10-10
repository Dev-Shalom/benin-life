-- M4 Messages v2 (docs/CHAT.md "M4", docs/SOCIAL.md). Idempotent.
-- 1. Streaks: one row per friend pair per WAT day; each side is marked when that player messages the other
--    (trigger on player_messages) and both sides when a house visit is admitted (trigger on player_house_invites).
--    social_streak(p_user) = consecutive WAT days where both sides were active, ending today or yesterday.
-- 2. social_friends: adds last_voice / last_deleted so the list can preview "Voice note" / "This message was deleted".
-- 3. Admin news keys news.latest_title / news.latest_body for the pinned "Benin Life team" card.
-- Read receipts already exist (player_messages.read_at set by social_mark_messages_read, live via Realtime UPDATE).

-- 1. streak days ---------------------------------------------------------------------------------------------
create table if not exists public.social_streak_days (
  user_a   uuid not null references public.profiles(id) on delete cascade,
  user_b   uuid not null references public.profiles(id) on delete cascade,
  day      date not null,
  a_active boolean not null default false,
  b_active boolean not null default false,
  primary key (user_a, user_b, day),
  check (user_a < user_b)
);
alter table public.social_streak_days enable row level security;
revoke all on public.social_streak_days from anon, authenticated;

/** WAT calendar day of a timestamp. */
create or replace function public.bl_wat_day(p_at timestamptz)
returns date language sql immutable set search_path = public as $$
  select (p_at at time zone 'Africa/Lagos')::date
$$;
revoke all on function public.bl_wat_day(timestamptz) from public, anon, authenticated;

/** Mark p_actor active with p_other on p_day (both sides when p_both). */
create or replace function public.bl_streak_mark(p_actor uuid, p_other uuid, p_day date, p_both boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_a uuid := least(p_actor, p_other); v_b uuid := greatest(p_actor, p_other);
        v_ma boolean := p_both or p_actor = v_a; v_mb boolean := p_both or p_actor = v_b;
begin
  if p_actor is null or p_other is null or p_actor = p_other then return; end if;
  insert into public.social_streak_days as s (user_a, user_b, day, a_active, b_active)
  values (v_a, v_b, p_day, v_ma, v_mb)
  on conflict (user_a, user_b, day) do update
    set a_active = s.a_active or excluded.a_active, b_active = s.b_active or excluded.b_active
  where (excluded.a_active and not s.a_active) or (excluded.b_active and not s.b_active);
end $$;
revoke all on function public.bl_streak_mark(uuid, uuid, date, boolean) from public, anon, authenticated;

create or replace function public.bl_streak_on_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare c public.player_conversations;
begin
  select * into c from public.player_conversations where id = new.conversation_id;
  if found then
    perform public.bl_streak_mark(new.sender_id, case when c.user_a = new.sender_id then c.user_b else c.user_a end,
                                  public.bl_wat_day(new.created_at));
  end if;
  return null;
end $$;
drop trigger if exists player_messages_streak on public.player_messages;
create trigger player_messages_streak after insert on public.player_messages
  for each row execute function public.bl_streak_on_message();
revoke all on function public.bl_streak_on_message() from public, anon, authenticated;

create or replace function public.bl_streak_on_visit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'admitted' and old.status is distinct from 'admitted' then
    perform public.bl_streak_mark(new.host_id, new.guest_id, public.bl_wat_day(public.bl_now()), true);
  end if;
  return null;
end $$;
drop trigger if exists player_house_invites_streak on public.player_house_invites;
create trigger player_house_invites_streak after update of status on public.player_house_invites
  for each row execute function public.bl_streak_on_visit();
revoke all on function public.bl_streak_on_visit() from public, anon, authenticated;

-- backfill the last 60 days of messages (safe to repeat: marks only turn on)
do $$
declare r record;
begin
  for r in
    select distinct m.sender_id, case when c.user_a = m.sender_id then c.user_b else c.user_a end as other,
           public.bl_wat_day(m.created_at) as day
      from public.player_messages m join public.player_conversations c on c.id = m.conversation_id
     where m.created_at >= now() - interval '60 days'
  loop
    perform public.bl_streak_mark(r.sender_id, r.other, r.day);
  end loop;
end $$;

/** {streak, today_me, today_them, best_day} for the caller and p_user. Only the two participants can read it. */
create or replace function public.social_streak(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_a uuid; v_b uuid;
        v_today date := public.bl_wat_day(public.bl_now()); v_latest date; v_streak int := 0;
        v_me boolean := false; v_them boolean := false;
begin
  if p_user is null or p_user = v_uid then
    raise exception 'Pick someone else.' using errcode = 'P0001', hint = 'bad_user';
  end if;
  v_a := least(v_uid, p_user); v_b := greatest(v_uid, p_user);
  select case when v_uid = v_a then a_active else b_active end, case when v_uid = v_a then b_active else a_active end
    into v_me, v_them
    from public.social_streak_days where user_a = v_a and user_b = v_b and day = v_today;
  select max(day) into v_latest from public.social_streak_days
   where user_a = v_a and user_b = v_b and a_active and b_active and day <= v_today;
  if v_latest is not null and v_latest >= v_today - 1 then
    select count(*) into v_streak from (
      select day, row_number() over (order by day desc) as rn
        from public.social_streak_days
       where user_a = v_a and user_b = v_b and a_active and b_active and day <= v_latest and day > v_latest - 1000
    ) x where x.day = v_latest - (x.rn::int - 1);
  end if;
  return jsonb_build_object('streak', v_streak, 'today_me', coalesce(v_me, false), 'today_them', coalesce(v_them, false),
                            'last_day', v_latest, 'today', v_today);
end $$;
revoke all on function public.social_streak(uuid) from public, anon;
grant execute on function public.social_streak(uuid) to authenticated, service_role;

-- 2. social_friends with preview flags ------------------------------------------------------------------------
create or replace function public.social_friends()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_uid uuid := bl_require_uid();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', other.id, 'username', other.username, 'avatar', other.avatar,
      'at_home', other.location_id = other.home_location_id,
      'last_seen', other.last_seen, 'conversation_id', c.id,
      'last_message', m.body, 'last_message_at', m.created_at, 'last_sender_id', m.sender_id,
      'last_voice', m.audio_path is not null, 'last_deleted', m.deleted_at is not null,
      'unread', coalesce(unread.n, 0)
    ) order by coalesce(m.created_at, f.created_at) desc, lower(other.username))
      from public.player_friendships f
      join public.profiles other on other.id = case when f.user_a = v_uid then f.user_b else f.user_a end
      left join public.player_conversations c on c.user_a = f.user_a and c.user_b = f.user_b
      left join lateral (select pm.body, pm.created_at, pm.sender_id, pm.audio_path, pm.deleted_at
                           from public.player_messages pm where pm.conversation_id = c.id
                          order by pm.id desc limit 1) m on true
      left join lateral (select count(*)::int as n from public.player_messages pm
                          where pm.conversation_id = c.id and pm.sender_id = other.id and pm.read_at is null) unread on true
     where f.status = 'accepted' and v_uid in (f.user_a, f.user_b)
       and not public.bl_social_blocked(v_uid, other.id)
  ), '[]'::jsonb);
end $function$;
revoke all on function public.social_friends() from public, anon;
grant execute on function public.social_friends() to authenticated, service_role;

-- 3. admin news ---------------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('news.latest_title', '"Welcome to Benin Life"', 'news', 'Team news: title',
 'M4: title of the pinned "Benin Life team" card at the top of Phone -> Messages. Empty = card hidden.', 'text', null, null),
('news.latest_body', '"Make friends, start a streak and visit each other''s homes. Tap Message someone to find a player by @username."', 'news', 'Team news: message',
 'M4: full text shown when a player opens the "Benin Life team" card in Messages.', 'text', null, null)
on conflict (key) do nothing;

notify pgrst, 'reload schema';
