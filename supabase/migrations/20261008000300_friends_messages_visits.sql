-- Player social: accepted friendships, private text/voice messages, and host-controlled house visits.
-- All writes go through security-definer RPCs. There are deliberately no admin settings for these features.

-- ---------------------------------------------------------------------
-- 1. Friendship, conversations, messages, and home invitations
-- ---------------------------------------------------------------------
create table if not exists public.player_friendships (
  user_a       uuid not null references public.profiles(id) on delete cascade,
  user_b       uuid not null references public.profiles(id) on delete cascade,
  status       text not null check (status in ('pending', 'accepted')),
  requested_by uuid not null references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b),
  check (requested_by = user_a or requested_by = user_b)
);
create index if not exists player_friendships_inbox_idx
  on public.player_friendships (user_a, user_b, created_at desc) where status = 'pending';
create index if not exists player_friendships_outbox_idx
  on public.player_friendships (requested_by, created_at desc) where status = 'pending';

create table if not exists public.player_conversations (
  id              bigserial primary key,
  user_a           uuid not null references public.profiles(id) on delete cascade,
  user_b           uuid not null references public.profiles(id) on delete cascade,
  created_at       timestamptz not null default now(),
  last_message_at  timestamptz not null default now(),
  unique (user_a, user_b),
  check (user_a < user_b)
);
create index if not exists player_conversations_user_a_idx on public.player_conversations (user_a, last_message_at desc);
create index if not exists player_conversations_user_b_idx on public.player_conversations (user_b, last_message_at desc);

create table if not exists public.player_messages (
  id              bigserial primary key,
  conversation_id bigint not null references public.player_conversations(id) on delete cascade,
  sender_id       uuid not null references public.profiles(id) on delete cascade,
  body            text,
  audio_path      text,
  audio_mime      text,
  created_at      timestamptz not null default now(),
  read_at         timestamptz,
  check (
    (body is not null and char_length(body) between 1 and 2000 and audio_path is null and audio_mime is null)
    or (body is null and audio_path is not null and audio_mime is not null)
  )
);
create index if not exists player_messages_conversation_idx on public.player_messages (conversation_id, id desc);
create index if not exists player_messages_unread_idx on public.player_messages (conversation_id, sender_id, id desc) where read_at is null;
create unique index if not exists player_messages_audio_path_idx on public.player_messages (audio_path) where audio_path is not null;

create table if not exists public.player_house_invites (
  id               bigserial primary key,
  host_id          uuid not null references public.profiles(id) on delete cascade,
  guest_id         uuid not null references public.profiles(id) on delete cascade,
  home_location_id text not null references public.locations(id),
  status           text not null check (status in ('invited', 'knocking', 'admitted', 'declined', 'cancelled', 'expired')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  expires_at       timestamptz not null,
  check (host_id <> guest_id)
);
create unique index if not exists player_house_invites_active_pair_idx
  on public.player_house_invites (host_id, guest_id) where status in ('invited', 'knocking');
create index if not exists player_house_invites_guest_idx
  on public.player_house_invites (guest_id, created_at desc) where status in ('invited', 'knocking');
create index if not exists player_house_invites_host_idx
  on public.player_house_invites (host_id, created_at desc) where status in ('invited', 'knocking');

alter table public.profiles add column if not exists home_visit_host_id uuid references public.profiles(id) on delete set null;
alter table public.profiles add column if not exists home_visit_original_housing_id text;
alter table public.locations add column if not exists private_home_owner_id uuid references public.profiles(id) on delete cascade;
create unique index if not exists locations_private_home_owner_idx
  on public.locations (private_home_owner_id) where private_home_owner_id is not null;

-- Homes used to share one map location per housing type. Give every current player their own
-- location record and hide it from the public map. An admitted guest sees it through profile RLS.
do $$
declare
  p record;
  v_home public.locations;
  v_private_id text;
begin
  for p in select id, username, location_id, home_location_id, travel_to
             from public.profiles where home_chosen and home_location_id is not null
  loop
    v_private_id := 'home_' || replace(p.id::text, '-', '');
    if not exists (select 1 from public.locations where private_home_owner_id = p.id) then
      select * into v_home from public.locations where id = p.home_location_id;
      if not found then continue; end if;
      v_home.id := v_private_id;
      v_home.name := p.username || '''s Home';
      v_home.active := false;
      v_home.private_home_owner_id := p.id;
      insert into public.locations select (v_home).* on conflict (id) do nothing;
    else
      select id into v_private_id from public.locations where private_home_owner_id = p.id;
    end if;
    update public.profiles
       set home_location_id = v_private_id,
           location_id = case when location_id = p.home_location_id then v_private_id else location_id end,
           travel_to = case when travel_to = p.home_location_id then v_private_id else travel_to end
     where id = p.id;
  end loop;
  -- These rows are templates referenced by start_homes, not public destinations.
  update public.locations l set active = false
   where l.id in (select h.location_id from public.start_homes h);
  -- Any trip already headed for a now-private shared template is cancelled; it cannot land there.
  update public.profiles prof
     set travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null
   where prof.travel_to in (select h.location_id from public.start_homes h)
     and (not prof.home_chosen or prof.travel_to is distinct from prof.home_location_id);
end $$;

create or replace function public.bl_social_can_view_private_home(p_location text, p_owner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_owner is not null and (
    auth.uid() = p_owner
    or exists (select 1 from public.profiles p
                where p.id = auth.uid() and p.location_id = p_location
                  and p.home_visit_host_id = p_owner)
  )
$$;
revoke all on function public.bl_social_can_view_private_home(text, uuid) from public;
grant execute on function public.bl_social_can_view_private_home(text, uuid) to anon, authenticated;

drop policy if exists locations_read on public.locations;
create policy locations_read on public.locations for select to anon, authenticated
  using ((private_home_owner_id is null and coalesce(active, true))
      or public.bl_social_can_view_private_home(id, private_home_owner_id));

create or replace function public.bl_location(p_id text) returns public.locations
language plpgsql stable set search_path = public as $$
declare v public.locations;
begin
  select * into v from public.locations where id = p_id;
  if not found then
    raise exception 'That place no dey for map o.' using errcode = 'P0001';
  end if;
  if v.private_home_owner_id is not null
     and not public.bl_social_can_view_private_home(v.id, v.private_home_owner_id) then
    raise exception 'That home is private. Ask the host to invite you.' using errcode = 'P0001', hint = 'private_home';
  end if;
  return v;
end $$;

create or replace function public.players_here(p_location text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_home_owner uuid;
begin
  select private_home_owner_id into v_home_owner from public.locations where id = p_location;
  if v_home_owner is not null and not public.bl_social_can_view_private_home(p_location, v_home_owner) then
    raise exception 'That home is private. Ask the host to invite you.' using errcode = 'P0001', hint = 'private_home';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar,
                                        'street_cred', p.street_cred, 'last_seen', p.last_seen)
                     order by p.last_seen desc)
    from (select * from public.profiles
          where location_id = p_location and id <> v_uid and not banned and travel_to is null and home_chosen
            and last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)
          order by last_seen desc limit 50) p
  ), '[]'::jsonb);
end $$;

-- Keep the shared start-home rows as catalogue templates, then assign the player a private instance.
create or replace function public.choose_start_home(p_home text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.profiles := bl_me_any();
  h public.start_homes;
  v_loc public.locations;
  v_private public.locations;
  v_private_id text := 'home_' || replace(v_me.id::text, '-', '');
  v_now timestamptz := bl_now();
  v_need numeric := bl_cfg('start.need_level');
  v_cash bigint;
  v_bank bigint;
  v_due timestamptz;
  v_body text;
begin
  if v_me.home_chosen then
    raise exception 'You have already moved in. Your first home is chosen.' using errcode = 'P0001', hint = 'home_already_chosen';
  end if;
  select * into h from public.start_homes where id = lower(trim(coalesce(p_home, ''))) and active;
  if not found then
    raise exception 'That home is not on the list. Pick one of the options.' using errcode = 'P0001', hint = 'bad_home';
  end if;
  if not bl_home_allowed(h, v_me.origin) then
    raise exception '%', coalesce(nullif(h.locked_quip, ''), 'That home is not available for you. Pick another one.')
      using errcode = 'P0001', hint = 'home_locked';
  end if;
  v_loc := bl_location(h.location_id);
  select * into v_private from public.locations where private_home_owner_id = v_me.id;
  if not found then
    v_private := v_loc;
    v_private.id := v_private_id;
    v_private.name := v_me.username || '''s Home';
    v_private.active := false;
    v_private.private_home_owner_id := v_me.id;
    insert into public.locations select (v_private).*;
  else
    v_private_id := v_private.id;
  end if;
  v_cash := bl_start_cash(v_me.origin, h.id);
  v_bank := greatest(0, bl_origin_num(v_me.origin, 'start_bank'))::bigint;
  v_due := bl_rent_due_after(v_now, bl_cfg('rent.first_due_grace_game_days'));

  update public.profiles set
    home_chosen = true, start_home = h.id,
    location_id = v_private_id, home_location_id = v_private_id, housing_id = h.housing_id,
    weekly_rent = h.weekly_rent, rent_due_at = v_due, rent_owed = 0,
    hunger = v_need, energy = v_need, hygiene = v_need, fun = v_need, social = v_need,
    health = bl_cfg('start.health'), stress = bl_cfg('start.stress'), needs_updated_at = v_now,
    protected_until = v_now + make_interval(mins => bl_cfg('start.protection_real_minutes')::int),
    last_seen = v_now
  where id = v_me.id;

  if v_cash > 0 then
    perform bl_add_money(v_me.id, 'cash', v_cash, 'start_bonus', jsonb_build_object('origin', v_me.origin, 'home', h.id));
  end if;
  if v_bank > 0 then
    perform bl_add_money(v_me.id, 'bank', v_bank, 'start_bonus', jsonb_build_object('origin', v_me.origin, 'home', h.id));
  end if;
  perform bl_give_origin_items(v_me.id, v_me.origin);

  v_body := bl_welcome_text(v_me.origin, v_me.username, v_loc.name, v_cash, v_bank);
  if h.weekly_rent > 0 then v_body := v_body || ' Rent is ' || bl_naira(h.weekly_rent) || ' a week.'; end if;
  perform bl_event(v_me.id, 'welcome', 'Welcome to Benin!', v_body, jsonb_build_object('origin', v_me.origin, 'home', h.id));
  return get_my_state() || jsonb_build_object('message', 'Welcome to your new home: ' || h.name
                                                        || case when h.district <> '' then ', ' || h.district else '' end || '!');
end $$;

alter table public.player_friendships enable row level security;
alter table public.player_conversations enable row level security;
alter table public.player_messages enable row level security;
alter table public.player_house_invites enable row level security;

revoke all on public.player_friendships, public.player_conversations, public.player_messages, public.player_house_invites
  from anon, authenticated;
revoke all on sequence public.player_conversations_id_seq, public.player_messages_id_seq, public.player_house_invites_id_seq
  from anon, authenticated;
grant select on public.player_messages to authenticated;

-- ---------------------------------------------------------------------
-- 2. Private voice storage (no app-level recording-duration cap)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('player-voice', 'player-voice', false, null,
        array['audio/webm', 'audio/mp4', 'audio/ogg', 'audio/mpeg', 'audio/aac', 'audio/wav']::text[])
on conflict (id) do update set
  name = excluded.name,
  public = false,
  file_size_limit = null,
  allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------
-- 3. Server-side authorization helpers
-- ---------------------------------------------------------------------
create or replace function public.bl_social_blocked(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.chat_blocks b
                  where (b.blocker_id = p_a and b.blocked_id = p_b)
                     or (b.blocker_id = p_b and b.blocked_id = p_a))
$$;

create or replace function public.bl_social_can_use_conversation(p_conversation_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (
    select 1
      from public.player_conversations c
      join public.player_friendships f on f.user_a = c.user_a and f.user_b = c.user_b and f.status = 'accepted'
     where c.id = p_conversation_id
       and auth.uid() in (c.user_a, c.user_b)
       and not public.bl_social_blocked(c.user_a, c.user_b)
  )
$$;

revoke all on function public.bl_social_blocked(uuid, uuid) from public, anon, authenticated;
revoke all on function public.bl_social_can_use_conversation(bigint) from public, anon;
grant execute on function public.bl_social_can_use_conversation(bigint) to authenticated;

drop policy if exists player_messages_friend_read on public.player_messages;
create policy player_messages_friend_read on public.player_messages for select to authenticated
  using (public.bl_social_can_use_conversation(conversation_id));

drop policy if exists player_voice_friend_read on storage.objects;
create policy player_voice_friend_read on storage.objects for select to authenticated
  using (
    bucket_id = 'player-voice'
    and (storage.foldername(name))[1] ~ '^[0-9]+$'
    and public.bl_social_can_use_conversation(((storage.foldername(name))[1])::bigint)
  );

drop policy if exists player_voice_friend_upload on storage.objects;
create policy player_voice_friend_upload on storage.objects for insert to authenticated
  with check (
    bucket_id = 'player-voice'
    and (storage.foldername(name))[1] ~ '^[0-9]+$'
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.bl_social_can_use_conversation(((storage.foldername(name))[1])::bigint)
  );

drop policy if exists player_voice_orphan_cleanup on storage.objects;
create policy player_voice_orphan_cleanup on storage.objects for delete to authenticated
  using (
    bucket_id = 'player-voice'
    and (storage.foldername(name))[1] ~ '^[0-9]+$'
    and (storage.foldername(name))[2] = auth.uid()::text
    and not exists (select 1 from public.player_messages m where m.audio_path = storage.objects.name)
  );

-- Realtime sends only messages visible under the accepted-friend RLS policy.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'player_messages') then
    alter publication supabase_realtime add table public.player_messages;
  end if;
end $$;

-- A guest keeps the host's room layout while inside; restore their own layout when they leave.
create or replace function public.bl_social_restore_home_layout() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_host_home text;
begin
  if old.home_visit_host_id is null or new.location_id is not distinct from old.location_id then
    return new;
  end if;
  select home_location_id into v_host_home from public.profiles where id = old.home_visit_host_id;
  if new.location_id is distinct from v_host_home then
    new.housing_id := old.home_visit_original_housing_id;
    new.home_visit_host_id := null;
    new.home_visit_original_housing_id := null;
  end if;
  return new;
end $$;
revoke all on function public.bl_social_restore_home_layout() from public, anon, authenticated;
drop trigger if exists social_restore_home_layout on public.profiles;
create trigger social_restore_home_layout before update of location_id on public.profiles
  for each row execute function public.bl_social_restore_home_layout();

-- ---------------------------------------------------------------------
-- 4. Friend requests and search
-- ---------------------------------------------------------------------
create or replace function public.social_search_players(p_query text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_query text := lower(btrim(coalesce(p_query, '')));
begin
  if length(v_query) < 3 then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar)
                     order by lower(p.username))
      from (select id, username, avatar from public.profiles
             where id <> v_uid and not banned and lower(username) like v_query || '%'
               and not public.bl_social_blocked(v_uid, id)
             order by lower(username) limit 25) p
  ), '[]'::jsonb);
end $$;

create or replace function public.social_friend_status(p_user uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_a uuid; v_b uuid; v_friend public.player_friendships;
begin
  if p_user is null or p_user = v_uid then return 'self'; end if;
  if public.bl_social_blocked(v_uid, p_user) then return 'blocked'; end if;
  v_a := least(v_uid, p_user); v_b := greatest(v_uid, p_user);
  select * into v_friend from public.player_friendships where user_a = v_a and user_b = v_b;
  if not found then return 'none'; end if;
  if v_friend.status = 'accepted' then return 'friend'; end if;
  return case when v_friend.requested_by = v_uid then 'outgoing' else 'incoming' end;
end $$;

create or replace function public.social_add_friend(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_a uuid; v_b uuid;
  v_me public.profiles; v_other public.profiles; v_friend public.player_friendships;
begin
  select * into v_me from public.profiles where id = v_uid;
  select * into v_other from public.profiles where id = p_user;
  if p_user is null or p_user = v_uid then raise exception 'You already have yourself, my friend.' using errcode = 'P0001', hint = 'self'; end if;
  if v_me.id is null or v_other.id is null or v_other.banned then raise exception 'That player is not available.' using errcode = 'P0001', hint = 'not_found'; end if;
  if v_me.banned then raise exception 'This account cannot send friend requests.' using errcode = 'P0001', hint = 'banned'; end if;
  if public.bl_social_blocked(v_uid, p_user) then raise exception 'You cannot add this player while either of you has blocked the other.' using errcode = 'P0001', hint = 'blocked'; end if;
  v_a := least(v_uid, p_user); v_b := greatest(v_uid, p_user);
  select * into v_friend from public.player_friendships where user_a = v_a and user_b = v_b for update;
  if found then
    if v_friend.status = 'accepted' then return jsonb_build_object('status', 'friend', 'message', 'You are already friends.'); end if;
    return jsonb_build_object('status', case when v_friend.requested_by = v_uid then 'outgoing' else 'incoming' end,
                              'message', case when v_friend.requested_by = v_uid then 'Friend request already sent.' else 'They already sent you a request.' end);
  end if;
  insert into public.player_friendships (user_a, user_b, status, requested_by, created_at, updated_at)
  values (v_a, v_b, 'pending', v_uid, bl_now(), bl_now());
  perform public.bl_event(p_user, 'friend_request', 'Friend request from @' || v_me.username,
                          '@' || v_me.username || ' wants to add you as a friend.', jsonb_build_object('user_id', v_uid));
  return jsonb_build_object('status', 'outgoing', 'message', 'Friend request sent to @' || v_other.username || '.');
end $$;

create or replace function public.social_friend_requests() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', other.id, 'username', other.username, 'avatar', other.avatar,
                                        'direction', case when f.requested_by = v_uid then 'outgoing' else 'incoming' end,
                                        'created_at', f.created_at)
                     order by f.created_at desc)
      from public.player_friendships f
      join public.profiles other on other.id = case when f.user_a = v_uid then f.user_b else f.user_a end
     where f.status = 'pending' and v_uid in (f.user_a, f.user_b)
       and not public.bl_social_blocked(v_uid, other.id)
  ), '[]'::jsonb);
end $$;

create or replace function public.social_respond_friend(p_user uuid, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_a uuid := least(v_uid, p_user); v_b uuid := greatest(v_uid, p_user);
        v_me public.profiles; v_other public.profiles; v_friend public.player_friendships;
begin
  if p_user is null or p_user = v_uid then raise exception 'That request is not valid.' using errcode = 'P0001', hint = 'bad_request'; end if;
  select * into v_me from public.profiles where id = v_uid;
  select * into v_other from public.profiles where id = p_user;
  select * into v_friend from public.player_friendships where user_a = v_a and user_b = v_b for update;
  if not found or v_friend.status <> 'pending' or v_friend.requested_by = v_uid then
    raise exception 'That friend request is no longer waiting.' using errcode = 'P0001', hint = 'not_pending';
  end if;
  if public.bl_social_blocked(v_uid, p_user) then raise exception 'Unblock each other before accepting this request.' using errcode = 'P0001', hint = 'blocked'; end if;
  if p_accept then
    update public.player_friendships set status = 'accepted', updated_at = bl_now()
     where user_a = v_a and user_b = v_b;
    perform public.bl_event(p_user, 'friend_accepted', '@' || v_me.username || ' accepted your request',
                            'You can now message each other and send house invites.', jsonb_build_object('user_id', v_uid));
    return jsonb_build_object('status', 'friend', 'message', 'You and @' || v_other.username || ' are friends now.');
  end if;
  delete from public.player_friendships where user_a = v_a and user_b = v_b;
  perform public.bl_event(p_user, 'friend_declined', 'Friend request declined',
                          '@' || v_me.username || ' is not accepting new requests right now.', jsonb_build_object('user_id', v_uid));
  return jsonb_build_object('status', 'none', 'message', 'Friend request declined.');
end $$;

create or replace function public.social_cancel_friend_request(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_a uuid := least(v_uid, p_user); v_b uuid := greatest(v_uid, p_user);
begin
  delete from public.player_friendships
   where user_a = v_a and user_b = v_b and status = 'pending' and requested_by = v_uid;
  if not found then raise exception 'That request is no longer waiting.' using errcode = 'P0001', hint = 'not_pending'; end if;
  return jsonb_build_object('status', 'none', 'message', 'Friend request cancelled.');
end $$;

create or replace function public.social_friends() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', other.id, 'username', other.username, 'avatar', other.avatar,
      'at_home', other.location_id = other.home_location_id,
      'last_seen', other.last_seen, 'conversation_id', c.id,
      'last_message', m.body, 'last_message_at', m.created_at, 'last_sender_id', m.sender_id,
      'unread', coalesce(unread.n, 0)
    ) order by coalesce(m.created_at, f.created_at) desc, lower(other.username))
      from public.player_friendships f
      join public.profiles other on other.id = case when f.user_a = v_uid then f.user_b else f.user_a end
      left join public.player_conversations c on c.user_a = f.user_a and c.user_b = f.user_b
      left join lateral (select pm.body, pm.created_at, pm.sender_id
                           from public.player_messages pm where pm.conversation_id = c.id
                          order by pm.id desc limit 1) m on true
      left join lateral (select count(*)::int as n from public.player_messages pm
                          where pm.conversation_id = c.id and pm.sender_id = other.id and pm.read_at is null) unread on true
     where f.status = 'accepted' and v_uid in (f.user_a, f.user_b)
       and not public.bl_social_blocked(v_uid, other.id)
  ), '[]'::jsonb);
end $$;

create or replace function public.social_remove_friend(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_a uuid := least(v_uid, p_user); v_b uuid := greatest(v_uid, p_user);
        v_other public.profiles;
begin
  if p_user is null or p_user = v_uid then raise exception 'That player is not in your friends list.' using errcode = 'P0001'; end if;
  select * into v_other from public.profiles where id = p_user;
  delete from public.player_friendships where user_a = v_a and user_b = v_b and status = 'accepted';
  if not found then raise exception 'That friendship is no longer active.' using errcode = 'P0001', hint = 'not_friend'; end if;
  update public.player_house_invites set status = 'cancelled', updated_at = bl_now()
   where host_id in (v_uid, p_user) and guest_id in (v_uid, p_user) and status in ('invited', 'knocking');
  return jsonb_build_object('message', 'You removed @' || coalesce(v_other.username, 'player') || ' from your friends.');
end $$;

-- ---------------------------------------------------------------------
-- 5. Private conversations and voice notes
-- ---------------------------------------------------------------------
create or replace function public.social_open_conversation(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_a uuid := least(v_uid, p_user); v_b uuid := greatest(v_uid, p_user);
        v_conversation public.player_conversations;
begin
  if p_user is null or p_user = v_uid then raise exception 'Choose another player.' using errcode = 'P0001', hint = 'bad_friend'; end if;
  if not exists (select 1 from public.player_friendships f where f.user_a = v_a and f.user_b = v_b and f.status = 'accepted') then
    raise exception 'Accept each other''s friend request before messaging.' using errcode = 'P0001', hint = 'not_friend';
  end if;
  if public.bl_social_blocked(v_uid, p_user) then raise exception 'You cannot message while either of you has blocked the other.' using errcode = 'P0001', hint = 'blocked'; end if;
  insert into public.player_conversations (user_a, user_b, created_at, last_message_at)
  values (v_a, v_b, bl_now(), bl_now())
  on conflict (user_a, user_b) do update set last_message_at = public.player_conversations.last_message_at
  returning * into v_conversation;
  return jsonb_build_object('id', v_conversation.id, 'friend_id', p_user);
end $$;

create or replace function public.social_message_history(p_conversation_id bigint, p_before bigint default null, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  if not public.bl_social_can_use_conversation(p_conversation_id) then
    raise exception 'That conversation is not available.' using errcode = 'P0001', hint = 'not_friend';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', page.id, 'conversation_id', page.conversation_id, 'sender_id', page.sender_id,
      'sender_username', sender.username, 'body', page.body, 'audio_path', page.audio_path,
      'audio_mime', page.audio_mime, 'created_at', page.created_at, 'read_at', page.read_at,
      'mine', page.sender_id = v_uid
    ) order by page.id)
    from (
      select m.* from public.player_messages m
       where m.conversation_id = p_conversation_id and (p_before is null or m.id < p_before)
       order by m.id desc limit v_limit
    ) page
    join public.profiles sender on sender.id = page.sender_id
  ), '[]'::jsonb);
end $$;

create or replace function public.social_mark_messages_read(p_conversation_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_count int;
begin
  if not public.bl_social_can_use_conversation(p_conversation_id) then
    raise exception 'That conversation is not available.' using errcode = 'P0001', hint = 'not_friend';
  end if;
  update public.player_messages set read_at = bl_now()
   where conversation_id = p_conversation_id and sender_id <> v_uid and read_at is null;
  get diagnostics v_count = row_count;
  return jsonb_build_object('read', v_count);
end $$;

create or replace function public.social_send_message(
  p_conversation_id bigint,
  p_body text default null,
  p_audio_path text default null,
  p_audio_mime text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_conversation public.player_conversations;
  v_sender public.profiles; v_recipient public.profiles; v_body text := nullif(btrim(coalesce(p_body, '')), '');
  v_message public.player_messages; v_path text := nullif(btrim(coalesce(p_audio_path, '')), '');
  v_mime text := lower(split_part(coalesce(p_audio_mime, ''), ';', 1));
begin
  select * into v_conversation from public.player_conversations where id = p_conversation_id;
  if not found or not public.bl_social_can_use_conversation(p_conversation_id) then
    raise exception 'That conversation is not available.' using errcode = 'P0001', hint = 'not_friend';
  end if;
  select * into v_sender from public.profiles where id = v_uid for update;
  select * into v_recipient from public.profiles where id = case when v_conversation.user_a = v_uid then v_conversation.user_b else v_conversation.user_a end;
  if v_sender.banned or v_recipient.banned then raise exception 'This conversation is not available.' using errcode = 'P0001', hint = 'banned'; end if;
  if (v_body is null) = (v_path is null) then
    raise exception 'Send text or one voice note at a time.' using errcode = 'P0001', hint = 'bad_message';
  end if;
  if v_body is not null then
    if char_length(v_body) > 2000 then raise exception 'That message is too long.' using errcode = 'P0001', hint = 'too_long'; end if;
    insert into public.player_messages (conversation_id, sender_id, body, created_at)
    values (p_conversation_id, v_uid, v_body, bl_now()) returning * into v_message;
  else
    if v_mime not in ('audio/webm', 'audio/mp4', 'audio/ogg', 'audio/mpeg', 'audio/aac', 'audio/wav') then
      raise exception 'This voice format is not supported on this device.' using errcode = 'P0001', hint = 'bad_audio';
    end if;
    if v_path !~ ('^' || p_conversation_id::text || '/' || v_uid::text || '/[A-Za-z0-9_-]+[.](webm|mp4|ogg|mp3|aac|wav)$') then
      raise exception 'That voice note is not valid.' using errcode = 'P0001', hint = 'bad_audio';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'player-voice' and o.name = v_path) then
      raise exception 'Voice upload did not finish. Please try again.' using errcode = 'P0001', hint = 'audio_missing';
    end if;
    insert into public.player_messages (conversation_id, sender_id, audio_path, audio_mime, created_at)
    values (p_conversation_id, v_uid, v_path, v_mime, bl_now()) returning * into v_message;
  end if;
  update public.player_conversations set last_message_at = bl_now() where id = p_conversation_id;
  perform public.bl_event(v_recipient.id, 'private_message', 'Message from @' || v_sender.username,
                          case when v_body is null then 'You received a voice message.' else left(v_body, 160) end,
                          jsonb_build_object('conversation_id', p_conversation_id, 'sender_id', v_uid));
  return jsonb_build_object('id', v_message.id, 'conversation_id', p_conversation_id, 'sender_id', v_uid,
                            'sender_username', v_sender.username, 'body', v_message.body,
                            'audio_path', v_message.audio_path, 'audio_mime', v_message.audio_mime,
                            'created_at', v_message.created_at, 'read_at', v_message.read_at, 'mine', true);
end $$;

-- ---------------------------------------------------------------------
-- 6. House invitations and door knocks
-- ---------------------------------------------------------------------
create or replace function public.social_send_house_invite(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_host public.profiles; v_guest public.profiles; v_invite public.player_house_invites; v_home_name text;
begin
  if p_user is null or p_user = v_uid then raise exception 'Choose a friend to invite.' using errcode = 'P0001', hint = 'bad_guest'; end if;
  select * into v_host from public.profiles where id = v_uid for update;
  select * into v_guest from public.profiles where id = p_user;
  if not v_host.home_chosen or v_host.home_location_id is null then raise exception 'Choose your home before inviting guests.' using errcode = 'P0001', hint = 'no_home'; end if;
  if v_host.banned or v_guest.id is null or v_guest.banned then raise exception 'That player is not available.' using errcode = 'P0001', hint = 'not_available'; end if;
  if not exists (select 1 from public.player_friendships f where f.user_a = least(v_uid, p_user) and f.user_b = greatest(v_uid, p_user) and f.status = 'accepted')
     or public.bl_social_blocked(v_uid, p_user) then
    raise exception 'You can invite friends only.' using errcode = 'P0001', hint = 'not_friend';
  end if;
  if v_guest.location_id = v_host.home_location_id then raise exception '@% is already at your home.', v_guest.username using errcode = 'P0001', hint = 'already_home'; end if;
  update public.player_house_invites set status = 'expired', updated_at = bl_now()
   where host_id = v_uid and guest_id = p_user and status in ('invited', 'knocking') and expires_at <= bl_now();
  if exists (select 1 from public.player_house_invites where host_id = v_uid and guest_id = p_user and status in ('invited', 'knocking')) then
    raise exception 'You already have an active invite for @%.', v_guest.username using errcode = 'P0001', hint = 'invite_exists';
  end if;
  if (select count(*) from public.player_house_invites where host_id = v_uid and status in ('invited', 'knocking') and expires_at > bl_now()) >= 50 then
    raise exception 'Too many guests are already invited. Let some in or clear the waiting list first.' using errcode = 'P0001', hint = 'invite_limit';
  end if;
  select name into v_home_name from public.locations where id = v_host.home_location_id;
  insert into public.player_house_invites (host_id, guest_id, home_location_id, status, created_at, updated_at, expires_at)
  values (v_uid, p_user, v_host.home_location_id, 'invited', bl_now(), bl_now(), bl_now() + interval '24 hours')
  returning * into v_invite;
  perform public.bl_event(p_user, 'house_invite', 'House invite from @' || v_host.username,
                          '@' || v_host.username || ' invited you to ' || coalesce(v_home_name, 'their home') || '. Accept to knock at the door.',
                          jsonb_build_object('invite_id', v_invite.id, 'host_id', v_uid));
  return jsonb_build_object('id', v_invite.id, 'status', v_invite.status, 'message', 'Invite sent to @' || v_guest.username || '.');
end $$;

create or replace function public.social_house_invites() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  update public.player_house_invites set status = 'expired', updated_at = bl_now()
   where (host_id = v_uid or guest_id = v_uid) and status in ('invited', 'knocking') and expires_at <= bl_now();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', i.id, 'host_id', i.host_id, 'guest_id', i.guest_id,
      'host_username', h.username, 'guest_username', g.username,
      'home_name', l.name,
      'status', i.status, 'created_at', i.created_at, 'expires_at', i.expires_at,
      'role', case when i.host_id = v_uid then 'host' else 'guest' end
    ) order by i.created_at desc)
      from public.player_house_invites i
      join public.profiles h on h.id = i.host_id
      join public.profiles g on g.id = i.guest_id
      join public.locations l on l.id = i.home_location_id
     where (i.host_id = v_uid or i.guest_id = v_uid) and i.status in ('invited', 'knocking')
  ), '[]'::jsonb);
end $$;

create or replace function public.social_respond_house_invite(p_invite_id bigint, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_invite public.player_house_invites; v_guest public.profiles; v_host public.profiles;
begin
  select * into v_invite from public.player_house_invites where id = p_invite_id for update;
  if not found or v_invite.guest_id <> v_uid or v_invite.status <> 'invited' or v_invite.expires_at <= bl_now() then
    raise exception 'That house invite has expired or is no longer waiting.' using errcode = 'P0001', hint = 'invite_expired';
  end if;
  select * into v_guest from public.profiles where id = v_uid;
  select * into v_host from public.profiles where id = v_invite.host_id;
  if public.bl_social_blocked(v_uid, v_invite.host_id)
     or not exists (select 1 from public.player_friendships f where f.user_a = least(v_uid, v_invite.host_id) and f.user_b = greatest(v_uid, v_invite.host_id) and f.status = 'accepted') then
    update public.player_house_invites set status = 'cancelled', updated_at = bl_now() where id = p_invite_id;
    raise exception 'This invite is no longer available.' using errcode = 'P0001', hint = 'not_friend';
  end if;
  if p_accept then
    update public.player_house_invites set status = 'knocking', updated_at = bl_now() where id = p_invite_id returning * into v_invite;
    perform public.bl_event(v_host.id, 'house_knock', '@' || v_guest.username || ' is at your door',
                            'They accepted your invite and are waiting outside. Go home to let them in.',
                            jsonb_build_object('invite_id', v_invite.id, 'guest_id', v_uid));
    return jsonb_build_object('id', v_invite.id, 'status', 'knocking', 'message', 'You are at the door. Wait for @' || v_host.username || ' to let you in.');
  end if;
  update public.player_house_invites set status = 'declined', updated_at = bl_now() where id = p_invite_id;
  perform public.bl_event(v_host.id, 'house_declined', '@' || v_guest.username || ' declined the house invite',
                          'They will not be coming over this time.', jsonb_build_object('invite_id', p_invite_id, 'guest_id', v_uid));
  return jsonb_build_object('id', p_invite_id, 'status', 'declined', 'message', 'Invite declined.');
end $$;

create or replace function public.social_cancel_house_invite(p_invite_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_invite public.player_house_invites;
begin
  update public.player_house_invites set status = 'cancelled', updated_at = bl_now()
   where id = p_invite_id and v_uid in (host_id, guest_id) and status in ('invited', 'knocking') returning * into v_invite;
  if not found then raise exception 'That invite is no longer active.' using errcode = 'P0001', hint = 'invite_expired'; end if;
  if v_invite.host_id = v_uid then
    perform public.bl_event(v_invite.guest_id, 'house_cancelled', 'House invite cancelled',
                            'The host cancelled the visit.', jsonb_build_object('invite_id', p_invite_id, 'host_id', v_uid));
  else
    perform public.bl_event(v_invite.host_id, 'house_cancelled', 'House invite cancelled',
                            'Your guest cancelled the visit.', jsonb_build_object('invite_id', p_invite_id, 'guest_id', v_uid));
  end if;
  return jsonb_build_object('id', p_invite_id, 'status', 'cancelled',
                            'message', case when v_invite.host_id = v_uid then 'House invite cancelled.' else 'You left the door.' end);
end $$;

create or replace function public.social_home_admit(p_invite_id bigint, p_admit boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_host public.profiles; v_guest public.profiles; v_invite public.player_house_invites;
begin
  select * into v_invite from public.player_house_invites where id = p_invite_id for update;
  if not found or v_invite.host_id <> v_uid or v_invite.status <> 'knocking' or v_invite.expires_at <= bl_now() then
    raise exception 'That guest is no longer waiting at your door.' using errcode = 'P0001', hint = 'knock_expired';
  end if;
  select * into v_host from public.profiles where id = v_uid for update;
  select * into v_guest from public.profiles where id = v_invite.guest_id for update;
  if p_admit then
    if v_host.location_id <> v_host.home_location_id or v_host.travel_to is not null then
      raise exception 'Go home first. Your guest is waiting at the door.' using errcode = 'P0001', hint = 'host_not_home';
    end if;
    if v_host.banned or v_guest.banned or v_guest.travel_to is not null or v_guest.home_visit_host_id is not null then
      raise exception 'Your guest cannot enter right now. Ask them to arrive and try again.' using errcode = 'P0001', hint = 'guest_unavailable';
    end if;
    if public.bl_social_blocked(v_uid, v_guest.id)
       or not exists (select 1 from public.player_friendships f where f.user_a = least(v_uid, v_guest.id) and f.user_b = greatest(v_uid, v_guest.id) and f.status = 'accepted') then
      update public.player_house_invites set status = 'cancelled', updated_at = bl_now() where id = p_invite_id;
      raise exception 'This guest is no longer your friend.' using errcode = 'P0001', hint = 'not_friend';
    end if;
    update public.profiles
       set location_id = v_host.home_location_id,
           home_visit_host_id = v_host.id,
           home_visit_original_housing_id = v_guest.housing_id,
           housing_id = v_host.housing_id
     where id = v_guest.id;
    update public.player_house_invites set status = 'admitted', updated_at = bl_now() where id = p_invite_id;
    perform public.bl_event(v_guest.id, 'house_admitted', '@' || v_host.username || ' opened the door',
                            'You are inside ' || coalesce((select name from public.locations where id = v_host.home_location_id), 'their home') || '.',
                            jsonb_build_object('invite_id', p_invite_id, 'host_id', v_uid, 'location_id', v_host.home_location_id));
    return jsonb_build_object('id', p_invite_id, 'status', 'admitted', 'message', '@' || v_guest.username || ' is inside.');
  end if;
  update public.player_house_invites set status = 'declined', updated_at = bl_now() where id = p_invite_id;
  perform public.bl_event(v_guest.id, 'house_declined', '@' || v_host.username || ' cannot let you in',
                          'The house visit was declined this time.', jsonb_build_object('invite_id', p_invite_id, 'host_id', v_uid));
  return jsonb_build_object('id', p_invite_id, 'status', 'declined', 'message', 'You turned away the guest.');
end $$;

-- ---------------------------------------------------------------------
-- 7. RPC permissions
-- ---------------------------------------------------------------------
revoke all on function public.social_search_players(text) from public, anon;
revoke all on function public.social_friend_status(uuid) from public, anon;
revoke all on function public.social_add_friend(uuid) from public, anon;
revoke all on function public.social_friend_requests() from public, anon;
revoke all on function public.social_respond_friend(uuid, boolean) from public, anon;
revoke all on function public.social_cancel_friend_request(uuid) from public, anon;
revoke all on function public.social_friends() from public, anon;
revoke all on function public.social_remove_friend(uuid) from public, anon;
revoke all on function public.social_open_conversation(uuid) from public, anon;
revoke all on function public.social_message_history(bigint, bigint, integer) from public, anon;
revoke all on function public.social_mark_messages_read(bigint) from public, anon;
revoke all on function public.social_send_message(bigint, text, text, text) from public, anon;
revoke all on function public.social_send_house_invite(uuid) from public, anon;
revoke all on function public.social_house_invites() from public, anon;
revoke all on function public.social_respond_house_invite(bigint, boolean) from public, anon;
revoke all on function public.social_cancel_house_invite(bigint) from public, anon;
revoke all on function public.social_home_admit(bigint, boolean) from public, anon;

grant execute on function public.social_search_players(text) to authenticated;
grant execute on function public.social_friend_status(uuid) to authenticated;
grant execute on function public.social_add_friend(uuid) to authenticated;
grant execute on function public.social_friend_requests() to authenticated;
grant execute on function public.social_respond_friend(uuid, boolean) to authenticated;
grant execute on function public.social_cancel_friend_request(uuid) to authenticated;
grant execute on function public.social_friends() to authenticated;
grant execute on function public.social_remove_friend(uuid) to authenticated;
grant execute on function public.social_open_conversation(uuid) to authenticated;
grant execute on function public.social_message_history(bigint, bigint, integer) to authenticated;
grant execute on function public.social_mark_messages_read(bigint) to authenticated;
grant execute on function public.social_send_message(bigint, text, text, text) to authenticated;
grant execute on function public.social_send_house_invite(uuid) to authenticated;
grant execute on function public.social_house_invites() to authenticated;
grant execute on function public.social_respond_house_invite(bigint, boolean) to authenticated;
grant execute on function public.social_cancel_house_invite(bigint) to authenticated;
grant execute on function public.social_home_admit(bigint, boolean) to authenticated;
