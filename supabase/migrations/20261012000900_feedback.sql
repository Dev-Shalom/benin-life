-- S1-D in-game suggestion box (docs/ADMIN.md "Feedback").
-- Players send a Suggestion / Bug / Review (1-5 stars for reviews, 1000 chars) from the phone's Feedback app or
-- Sim sheet -> Settings. Stored with a username snapshot, app version, device, viewport and the place they were at.
-- Players read only their own (RLS + feedback_mine); admins read all (Admin -> Feedback), set a status
-- (new / planned / done / ignored) and reply; a reply shows in the player's Feedback app and sends an in-game alert.
-- Each new entry creates an admin_notifications row (push to the owner via admin-push).
-- Idempotent.

create table if not exists public.feedback (
  id          bigserial primary key,
  user_id     uuid references auth.users(id) on delete cascade,
  username    text not null,
  kind        text not null check (kind in ('suggestion', 'bug', 'review')),
  rating      smallint check (rating between 1 and 5),
  body        text not null check (char_length(body) between 1 and 1000),
  status      text not null default 'new' check (status in ('new', 'planned', 'done', 'ignored')),
  reply       text check (reply is null or char_length(reply) <= 1000),
  replied_at  timestamptz,
  replied_by  uuid references auth.users(id) on delete set null,
  app_version text,
  device      text,
  viewport    text,
  location_id text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists feedback_user_idx on public.feedback (user_id, created_at desc);
create index if not exists feedback_status_idx on public.feedback (status, created_at desc);
create index if not exists feedback_kind_idx on public.feedback (kind, created_at desc);
create index if not exists feedback_replied_by_idx on public.feedback (replied_by) where replied_by is not null;

alter table public.feedback enable row level security;
revoke all on table public.feedback from anon, authenticated;
grant select on table public.feedback to authenticated;
drop policy if exists feedback_own on public.feedback;
create policy feedback_own on public.feedback for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists feedback_admin on public.feedback;
create policy feedback_admin on public.feedback for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin and not p.banned));

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('feedback.enabled', 'true', 'admin', 'Feedback box open',
 'S1: players can send suggestions, bug reports and reviews from the phone (Feedback app). Off = the app says it is closed.', 'bool', null, null),
('feedback.per_day', '5', 'admin', 'Feedback per player per day',
 'S1: most feedback messages one player can send in 24 hours.', 'number', 1, 50)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- Player side
-- ---------------------------------------------------------------------------------------------
create or replace function public.feedback_submit(p_kind text, p_body text, p_rating int default null, p_meta jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_kind text := lower(btrim(coalesce(p_kind, '')));
  v_body text := btrim(coalesce(p_body, ''));
  v_max  int := greatest(1, coalesce((select (value #>> '{}')::int from game_config where key = 'feedback.per_day'), 5));
  v_meta jsonb := case when jsonb_typeof(p_meta) = 'object' then p_meta else '{}'::jsonb end;
  p      profiles;
  v_id   bigint;
  v_label text;
begin
  if coalesce((select (value #>> '{}')::boolean from game_config where key = 'feedback.enabled'), true) is not true then
    raise exception 'The feedback box is closed for now. Try again later.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into p from profiles where id = v_uid;
  if not found then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if p.banned then
    raise exception 'This account has been banned.' using errcode = 'P0001', hint = 'banned';
  end if;
  if v_kind not in ('suggestion', 'bug', 'review') then
    raise exception 'Pick Suggestion, Bug or Review.' using errcode = 'P0001', hint = 'bad_kind';
  end if;
  if char_length(v_body) < 3 then
    raise exception 'Write a little more so we understand.' using errcode = 'P0001', hint = 'too_short';
  end if;
  if char_length(v_body) > 1000 then
    raise exception 'Keep it under 1000 characters.' using errcode = 'P0001', hint = 'too_long';
  end if;
  if v_kind = 'review' and (p_rating is null or p_rating not between 1 and 5) then
    raise exception 'Tap the stars to rate the game (1 to 5).' using errcode = 'P0001', hint = 'rating';
  end if;
  if p_rating is not null and p_rating not between 1 and 5 then
    raise exception 'Stars go from 1 to 5.' using errcode = 'P0001', hint = 'rating';
  end if;
  -- serialize one player's submits so two taps can't both pass the daily count
  perform pg_advisory_xact_lock(hashtextextended('feedback:' || v_uid::text, 0));
  if (select count(*) from feedback where user_id = v_uid and created_at > now() - interval '24 hours') >= v_max then
    raise exception 'You don send plenty feedback today. Thank you! Try again tomorrow.' using errcode = 'P0001', hint = 'rate_limit';
  end if;

  insert into feedback (user_id, username, kind, rating, body, app_version, device, viewport, location_id)
  values (v_uid, p.username, v_kind, case when v_kind = 'review' then p_rating else null end, v_body,
          left(nullif(btrim(v_meta->>'app_version'), ''), 60), left(nullif(btrim(v_meta->>'device'), ''), 300),
          left(nullif(btrim(v_meta->>'viewport'), ''), 30),
          case when p.travel_to is null then p.location_id end)
  returning id into v_id;

  v_label := case v_kind when 'bug' then 'bug report' when 'review' then 'review' else 'suggestion' end;
  perform bl_admin_notify('feedback',
    'New ' || v_label || ' from @' || p.username || case when v_kind = 'review' then ' (' || p_rating || '★)' else '' end,
    left(v_body, 200), jsonb_build_object('feedback_id', v_id, 'kind', v_kind), '/admin/feedback');

  return jsonb_build_object('id', v_id, 'message', 'Thank you! The Benin Life team go read am.',
    'left_today', greatest(0, v_max - (select count(*) from feedback where user_id = v_uid and created_at > now() - interval '24 hours')));
end $$;
revoke all on function public.feedback_submit(text, text, int, jsonb) from public, anon;
grant execute on function public.feedback_submit(text, text, int, jsonb) to authenticated, service_role;

create or replace function public.feedback_mine() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_max int := greatest(1, coalesce((select (value #>> '{}')::int from game_config where key = 'feedback.per_day'), 5));
begin
  return jsonb_build_object(
    'enabled', coalesce((select (value #>> '{}')::boolean from game_config where key = 'feedback.enabled'), true),
    'left_today', greatest(0, v_max - (select count(*) from feedback where user_id = v_uid and created_at > now() - interval '24 hours')),
    'per_day', v_max,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'rating', f.rating, 'body', f.body,
                                                          'status', f.status, 'reply', f.reply, 'replied_at', f.replied_at,
                                                          'created_at', f.created_at) order by f.id desc)
                        from (select * from feedback where user_id = v_uid order by id desc limit 50) f), '[]'::jsonb));
end $$;
revoke all on function public.feedback_mine() from public, anon;
grant execute on function public.feedback_mine() to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Admin side
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_feedback_list(p_kind text default null, p_status text default null, p_limit int default 100)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_kind text := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  v_status text := nullif(lower(btrim(coalesce(p_status, ''))), '');
  v_lim int := least(greatest(coalesce(p_limit, 100), 1), 300);
begin
  perform bl_admin_guard();
  if v_kind = 'all' then v_kind := null; end if;
  if v_status = 'all' then v_status := null; end if;
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', f.id, 'user_id', f.user_id, 'username', f.username, 'kind', f.kind, 'rating', f.rating, 'body', f.body,
                 'status', f.status, 'reply', f.reply, 'replied_at', f.replied_at, 'app_version', f.app_version,
                 'device', f.device, 'viewport', f.viewport, 'location_id', f.location_id,
                 'location_name', (select l.name from locations l where l.id = f.location_id), 'created_at', f.created_at)
               order by f.id desc)
        from (select * from feedback
               where (v_kind is null or kind = v_kind) and (v_status is null or status = v_status)
               order by id desc limit v_lim) f), '[]'::jsonb),
    'stats', jsonb_build_object(
      'total', (select count(*) from feedback),
      'new', (select count(*) from feedback where status = 'new'),
      'reviews', (select count(*) from feedback where kind = 'review' and rating is not null),
      'avg_rating', (select round(avg(rating)::numeric, 2) from feedback where kind = 'review' and rating is not null),
      'by_kind', coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from feedback group by kind) k), '{}'::jsonb),
      'by_status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from feedback group by status) s), '{}'::jsonb)));
end $$;
revoke all on function public.admin_feedback_list(text, text, int) from public, anon;
grant execute on function public.admin_feedback_list(text, text, int) to authenticated, service_role;

create or replace function public.admin_feedback_update(p_id bigint, p_status text default null, p_reply text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  v_status text := nullif(lower(btrim(coalesce(p_status, ''))), '');
  v_reply text := nullif(btrim(coalesce(p_reply, '')), '');
  f feedback;
  v_new_reply boolean;
begin
  select * into f from feedback where id = p_id for update;
  if not found then
    raise exception 'That feedback no longer exists.' using errcode = 'P0001', hint = 'not_found';
  end if;
  if v_status is not null and v_status not in ('new', 'planned', 'done', 'ignored') then
    raise exception 'Unknown status.' using errcode = 'P0001', hint = 'bad_status';
  end if;
  if v_reply is not null and char_length(v_reply) > 1000 then
    raise exception 'Keep the reply under 1000 characters.' using errcode = 'P0001', hint = 'too_long';
  end if;
  v_new_reply := v_reply is not null and v_reply is distinct from f.reply;
  update feedback
     set status = coalesce(v_status, status),
         reply = case when v_new_reply then v_reply else reply end,
         replied_at = case when v_new_reply then now() else replied_at end,
         replied_by = case when v_new_reply then v_admin else replied_by end,
         updated_at = now()
   where id = p_id
  returning * into f;
  if v_new_reply and f.user_id is not null and exists (select 1 from profiles where id = f.user_id) then
    insert into events (user_id, kind, title, body, data)
    values (f.user_id, 'feedback_reply', 'The Benin Life team replied',
            left(v_reply, 200), jsonb_build_object('feedback_id', f.id));
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'feedback_update', f.user_id,
          jsonb_build_object('feedback_id', f.id, 'status', f.status, 'replied', v_new_reply));
  return jsonb_build_object('message', case when v_new_reply then 'Reply sent. The player gets an alert.' else 'Saved.' end,
                            'id', f.id, 'status', f.status, 'reply', f.reply, 'replied_at', f.replied_at);
end $$;
revoke all on function public.admin_feedback_update(bigint, text, text) from public, anon;
grant execute on function public.admin_feedback_update(bigint, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
