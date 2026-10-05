-- Benin Life — V1-6 "Chat": one chat room per location (no global chat), plus report / block.
-- docs/CHAT.md is the spec. Safe on a non-empty DB and idempotent:
-- * tables / indexes / columns use `if not exists`; policies are dropped and re-created;
-- * config rows and seed words use `on conflict do nothing` (admin values survive a re-run);
-- * functions are `create or replace`; the realtime publication add is guarded.
--
-- Bandwidth (Lagos Life's global chat died at ~50k CCU): a message is only delivered to the players
-- subscribed to that location's filter (`location_id=eq.<id>`), INSERT events only, no polling.
-- The client loads the last `chat.recent_limit` messages once with chat_recent() and caps its list.
--
-- Read model: RLS lets a player select only visible messages of the place their profile is at,
-- minus players they blocked. Supabase Realtime `postgres_changes` checks that same policy per
-- subscriber, so a filter on another location simply delivers nothing. Writes go through RPCs only.

-- ---------------------------------------------------------------------
-- 1. Config (category `chat`; all admin-tunable)
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('chat.enabled', 'true', 'chat', 'Chat on',
 'Turn location chat on or off for everyone (off = nobody can send; old messages still show).', 'bool', null, null),
('chat.max_len', '200', 'chat', 'Longest message (characters)',
 'Messages longer than this are refused.', 'number', 10, 1000),
('chat.rate_seconds', '3', 'chat', 'Wait between messages (real seconds)',
 'Rate limit: real seconds a player must wait between two chat messages.', 'number', 0, 600),
('chat.burst_per_minute', '8', 'chat', 'Messages per minute',
 'Rate limit: the most messages one player can send in any real minute.', 'number', 1, 120),
('chat.duplicate_window_seconds', '120', 'chat', 'Repeat-message window (real seconds)',
 'A player cannot send the same message again within this many real seconds (anti-spam). 0 = off.', 'number', 0, 86400),
('chat.min_account_real_minutes', '5', 'chat', 'New accounts wait before chatting (real minutes)',
 'A brand-new Sim can only chat after this many real minutes (slows down spam accounts). 0 = no wait.', 'minutes', 0, 10080),
('chat.recent_limit', '30', 'chat', 'Messages loaded when you open chat',
 'How many recent messages a player gets when they open the chat at a place.', 'number', 5, 100),
('chat.report_hide_count', '3', 'chat', 'Reports that hide a message',
 'A message is hidden automatically once this many different players report it.', 'number', 1, 100),
('chat.retention_hours', '48', 'chat', 'Keep messages for (real hours)',
 'Older messages are deleted (a few at a time, whenever someone sends a message).', 'number', 1, 8760),
('chat.max_blocks', '200', 'chat', 'Most players one person can block',
 'Upper limit on a player''s block list.', 'number', 1, 10000)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------
-- Admin chat mute (V1-7 admin may set it); bl_chat_guard refuses while it is in the future.
alter table public.profiles add column if not exists chat_muted_until timestamptz;

create table if not exists public.chat_messages (
  id          bigserial primary key,
  location_id text not null references public.locations(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  username    text not null,                       -- snapshot (no join needed for realtime rows)
  body        text not null check (char_length(body) between 1 and 1000),
  created_at  timestamptz not null default now(),
  hidden      boolean not null default false
);
create index if not exists chat_messages_loc_idx  on public.chat_messages (location_id, id desc);
create index if not exists chat_messages_user_idx on public.chat_messages (user_id, created_at desc);
create index if not exists chat_messages_age_idx  on public.chat_messages (created_at);

create table if not exists public.chat_reports (
  id          bigserial primary key,
  message_id  bigint not null references public.chat_messages(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason      text,
  created_at  timestamptz not null default now(),
  unique (message_id, reporter_id)
);

create table if not exists public.chat_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- Profanity list (masked with *** in chat_send). Admin edits rows; `active=false` switches one off.
create table if not exists public.chat_banned_words (
  word   text primary key check (word = lower(word) and word ~ '^[a-z0-9 ]+$'),
  active boolean not null default true
);

insert into public.chat_banned_words (word) values
  -- English
  ('fuck'), ('fucking'), ('fucker'), ('motherfucker'), ('shit'), ('bullshit'), ('bitch'), ('bastard'),
  ('asshole'), ('arsehole'), ('cunt'), ('dick'), ('dickhead'), ('pussy'), ('whore'), ('slut'),
  ('nigger'), ('nigga'), ('wanker'), ('twat'),
  -- Nigerian Pidgin / Yoruba street insults that read as swearing in chat
  ('ashawo'), ('ashewo'), ('olosho'), ('oloshi'), ('oloriburuku'), ('werey'), ('toto'), ('gbola'),
  ('your mama toto'), ('ode buruku')
on conflict (word) do nothing;

alter table public.chat_messages     enable row level security;
alter table public.chat_reports      enable row level security;
alter table public.chat_blocks       enable row level security;
alter table public.chat_banned_words enable row level security;

-- Clients read; nobody writes directly (RPCs are security definer).
revoke all on public.chat_messages, public.chat_reports, public.chat_blocks, public.chat_banned_words from anon, authenticated;
grant select on public.chat_messages, public.chat_blocks to authenticated;
revoke all on sequence public.chat_messages_id_seq, public.chat_reports_id_seq from anon, authenticated;

drop policy if exists chat_messages_here on public.chat_messages;
create policy chat_messages_here on public.chat_messages for select to authenticated
  using (
    not hidden
    and location_id = (select p.location_id from public.profiles p where p.id = (select auth.uid()))
    and not exists (select 1 from public.chat_blocks b
                     where b.blocker_id = (select auth.uid()) and b.blocked_id = chat_messages.user_id)
  );

drop policy if exists chat_blocks_own on public.chat_blocks;
create policy chat_blocks_own on public.chat_blocks for select to authenticated
  using (blocker_id = (select auth.uid()));

-- Realtime (INSERT events reach subscribers that pass the select policy).
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_messages') then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. Helpers (internal)
-- ---------------------------------------------------------------------
-- Trim, turn newlines/tabs into spaces, drop other control and zero-width characters, squeeze spaces.
create or replace function public.bl_chat_clean(p_body text) returns text
language sql immutable set search_path = public as $$
  select btrim(regexp_replace(
           regexp_replace(
             regexp_replace(coalesce(p_body, ''), '[\r\n\t]+', ' ', 'g'),
             '[\x00-\x1F\x7F​-‏ -‮⁠-⁤﻿]', '', 'g'),
           ' {2,}', ' ', 'g'))
$$;

-- Mask every active banned word (whole word, any case, common endings) with asterisks.
create or replace function public.bl_chat_mask(p_body text) returns text
language plpgsql stable set search_path = public as $$
declare
  v text := p_body;
  w text;
  m text;
begin
  for w in select word from chat_banned_words where active order by length(word) desc loop
    -- words are [a-z0-9 ]; a space in the list matches any run of spaces
    loop
      m := substring(v from '(?i)\m(' || replace(w, ' ', '\s+') || '(?:s|es|ed|er|ers|ing|in|y|ty|ted)?)\M');
      exit when m is null;
      v := regexp_replace(v, '(?i)\m' || replace(w, ' ', '\s+') || '(?:s|es|ed|er|ers|ing|in|y|ty|ted)?\M',
                          repeat('*', greatest(3, char_length(m))));
    end loop;
  end loop;
  return v;
end $$;

-- Caller's profile for chat: logged in, has a Sim and a home, not banned, not muted. Locks the row
-- (so the rate limit can't be raced) but writes nothing, so no profile realtime refresh per message.
create or replace function public.bl_chat_me() returns public.profiles
language plpgsql set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v profiles;
begin
  select * into v from profiles where id = v_uid for update;
  if not found then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v.banned then
    raise exception 'This account has been banned. If this is a mistake, contact the admin.' using errcode = 'P0001', hint = 'banned';
  end if;
  if not v.home_chosen then
    raise exception 'Hold on, choose where you will live first.' using errcode = 'P0001', hint = 'no_home';
  end if;
  return v;
end $$;

-- A message row as the client sees it.
create or replace function public.bl_chat_row(m public.chat_messages, p_avatar jsonb, p_me uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('id', m.id, 'location_id', m.location_id, 'user_id', m.user_id,
                            'username', m.username, 'body', m.body, 'created_at', m.created_at,
                            'avatar', p_avatar, 'mine', m.user_id = p_me)
$$;

-- ---------------------------------------------------------------------
-- 4. RPCs
-- ---------------------------------------------------------------------
create or replace function public.chat_send(p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_chat_me();
  v_now   timestamptz := bl_now();
  v_body  text := bl_chat_clean(p_body);
  v_max   int := bl_cfg('chat.max_len')::int;
  v_rate  numeric := bl_cfg('chat.rate_seconds');
  v_burst int := bl_cfg('chat.burst_per_minute')::int;
  v_dup   numeric := bl_cfg('chat.duplicate_window_seconds');
  v_new   numeric := bl_cfg('chat.min_account_real_minutes');
  v_last  timestamptz;
  v_wait  int;
  v_n     int;
  v_masked text;
  m       chat_messages;
begin
  if not bl_cfg_bool('chat.enabled') then
    raise exception 'Chat is switched off for now. Try again later.' using errcode = 'P0001', hint = 'chat_off';
  end if;
  if v_me.chat_muted_until is not null and v_me.chat_muted_until > v_now then
    raise exception 'You can''t chat for now (muted by a moderator). Try again in about % min.',
      ceil(extract(epoch from v_me.chat_muted_until - v_now) / 60) using errcode = 'P0001', hint = 'muted';
  end if;
  if v_me.travel_to is not null then
    raise exception 'You are on the road. You can chat when you arrive.' using errcode = 'P0001', hint = 'traveling';
  end if;
  if v_me.location_id is null then
    raise exception 'You need to be at a place to chat.' using errcode = 'P0001', hint = 'not_here';
  end if;
  if v_new > 0 and v_me.created_at > v_now - make_interval(secs => (v_new * 60)::double precision) then
    raise exception 'New Sims can chat after % minutes. Look around first!',
      ceil(v_new) using errcode = 'P0001', hint = 'too_new';
  end if;
  if v_body = '' then
    raise exception 'Type a message first.' using errcode = 'P0001', hint = 'empty';
  end if;
  if char_length(v_body) > v_max then
    raise exception 'That message is too long. Keep it under % characters.', v_max using errcode = 'P0001', hint = 'too_long';
  end if;

  -- rate limits (real time)
  select max(created_at), count(*) filter (where created_at > v_now - interval '60 seconds')
    into v_last, v_n
    from chat_messages where user_id = v_me.id and created_at > v_now - interval '1 hour';
  if v_last is not null and v_rate > 0 and v_last > v_now - make_interval(secs => v_rate::double precision) then
    v_wait := greatest(1, ceil(v_rate - extract(epoch from v_now - v_last)));
    raise exception 'Slow down small. Wait % sec before your next message.', v_wait
      using errcode = 'P0001', hint = 'too_fast';
  end if;
  if v_n >= v_burst then
    raise exception 'You are sending too many messages. Take a short break.' using errcode = 'P0001', hint = 'too_fast';
  end if;
  if v_dup > 0 and exists (
      select 1 from chat_messages
       where user_id = v_me.id and created_at > v_now - make_interval(secs => v_dup::double precision)
         and lower(regexp_replace(body, '\W', '', 'g')) = lower(regexp_replace(bl_chat_mask(v_body), '\W', '', 'g'))) then
    raise exception 'You just sent that. Say something new.' using errcode = 'P0001', hint = 'duplicate';
  end if;

  v_masked := bl_chat_mask(v_body);

  -- lazy retention: a few old rows per send (no cron needed)
  delete from chat_messages where id in (
    select id from chat_messages
     where created_at < v_now - make_interval(secs => (bl_cfg('chat.retention_hours') * 3600)::double precision)
     order by created_at limit 200);

  insert into chat_messages (location_id, user_id, username, body, created_at)
  values (v_me.location_id, v_me.id, v_me.username, v_masked, v_now)
  returning * into m;

  return bl_chat_row(m, v_me.avatar, v_me.id)
         || jsonb_build_object('message', 'Sent.', 'masked', v_masked <> v_body);
end $$;

-- Last messages at the caller's current place (oldest first), minus hidden and blocked players.
create or replace function public.chat_recent(p_location text, p_limit int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v     profiles;
  v_lim int := least(greatest(coalesce(p_limit, 30), 1), bl_cfg('chat.recent_limit')::int);
begin
  select * into v from profiles where id = v_uid;
  if not found then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v.location_id is distinct from p_location or v.travel_to is not null then
    raise exception 'You can only read the chat of the place you are at.' using errcode = 'P0001', hint = 'not_here';
  end if;
  return coalesce((
    select jsonb_agg(bl_chat_row(x, p.avatar, v_uid) order by x.id)
      from (select * from chat_messages c
             where c.location_id = p_location and not c.hidden
               and not exists (select 1 from chat_blocks b where b.blocker_id = v_uid and b.blocked_id = c.user_id)
             order by c.id desc limit v_lim) x
      left join profiles p on p.id = x.user_id
  ), '[]'::jsonb);
end $$;

create or replace function public.chat_report(p_message_id bigint, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me  profiles := bl_chat_me();
  m     chat_messages;
  v_n   int;
  v_hid boolean := false;
begin
  select * into m from chat_messages where id = p_message_id for update;
  if not found then
    raise exception 'That message is gone already.' using errcode = 'P0001', hint = 'not_found';
  end if;
  if m.user_id = v_me.id then
    raise exception 'You can''t report your own message.' using errcode = 'P0001', hint = 'own_message';
  end if;
  insert into chat_reports (message_id, reporter_id, reason)
  values (m.id, v_me.id, left(nullif(bl_chat_clean(p_reason), ''), 200))
  on conflict (message_id, reporter_id) do nothing;
  select count(*) into v_n from chat_reports where message_id = m.id;
  if not m.hidden and v_n >= bl_cfg('chat.report_hide_count') then
    update chat_messages set hidden = true where id = m.id;
    v_hid := true;
  end if;
  return jsonb_build_object('message', 'Thanks. A moderator will look at it.', 'reports', v_n,
                            'hidden', m.hidden or v_hid);
end $$;

create or replace function public.chat_block(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_chat_me(); v_name text; v_n int;
begin
  if p_user is null or p_user = v_me.id then
    raise exception 'You can''t block yourself.' using errcode = 'P0001', hint = 'self';
  end if;
  select username into v_name from profiles where id = p_user;
  if v_name is null then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'unknown_player';
  end if;
  select count(*) into v_n from chat_blocks where blocker_id = v_me.id;
  if v_n >= bl_cfg('chat.max_blocks')
     and not exists (select 1 from chat_blocks where blocker_id = v_me.id and blocked_id = p_user) then
    raise exception 'Your block list is full. Unblock someone first.' using errcode = 'P0001', hint = 'limit';
  end if;
  insert into chat_blocks (blocker_id, blocked_id, created_at) values (v_me.id, p_user, bl_now())
  on conflict do nothing;
  return jsonb_build_object('message', 'You won''t see messages from @' || v_name || ' any more.',
                            'id', p_user, 'username', v_name);
end $$;

create or replace function public.chat_unblock(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_chat_me(); v_name text;
begin
  delete from chat_blocks where blocker_id = v_me.id and blocked_id = p_user;
  select username into v_name from profiles where id = p_user;
  return jsonb_build_object('message', 'Unblocked @' || coalesce(v_name, 'player') || '.', 'id', p_user);
end $$;

-- The caller's block list, newest first.
create or replace function public.chat_blocked() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar,
                                        'created_at', b.created_at) order by b.created_at desc)
      from chat_blocks b join profiles p on p.id = b.blocked_id
     where b.blocker_id = v_uid
  ), '[]'::jsonb);
end $$;

-- Admin: hide (or un-hide) a message. Logged in admin_audit.
create or replace function public.admin_chat_hide(p_message_id bigint, p_hidden boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m chat_messages;
begin
  if not bl_is_admin() then
    raise exception 'Admins only.' using errcode = 'P0001', hint = 'not_admin';
  end if;
  update chat_messages set hidden = coalesce(p_hidden, true) where id = p_message_id returning * into m;
  if not found then
    raise exception 'That message is gone already.' using errcode = 'P0001', hint = 'not_found';
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (auth.uid(), case when m.hidden then 'chat_hide' else 'chat_unhide' end, m.user_id,
          jsonb_build_object('message_id', m.id, 'location', m.location_id, 'body', m.body));
  return jsonb_build_object('message', case when m.hidden then 'Message hidden.' else 'Message visible again.' end,
                            'id', m.id, 'hidden', m.hidden);
end $$;

-- ---------------------------------------------------------------------
-- 5. Privileges
-- ---------------------------------------------------------------------
revoke execute on function public.bl_chat_clean(text)                                 from public, anon, authenticated;
revoke execute on function public.bl_chat_mask(text)                                  from public, anon, authenticated;
revoke execute on function public.bl_chat_me()                                        from public, anon, authenticated;
revoke execute on function public.bl_chat_row(public.chat_messages, jsonb, uuid)      from public, anon, authenticated;

revoke execute on function public.chat_send(text)                  from public, anon;
revoke execute on function public.chat_recent(text, int)           from public, anon;
revoke execute on function public.chat_report(bigint, text)        from public, anon;
revoke execute on function public.chat_block(uuid)                 from public, anon;
revoke execute on function public.chat_unblock(uuid)               from public, anon;
revoke execute on function public.chat_blocked()                   from public, anon;
revoke execute on function public.admin_chat_hide(bigint, boolean) from public, anon;
grant execute on function public.chat_send(text)                   to authenticated;
grant execute on function public.chat_recent(text, int)            to authenticated;
grant execute on function public.chat_report(bigint, text)         to authenticated;
grant execute on function public.chat_block(uuid)                  to authenticated;
grant execute on function public.chat_unblock(uuid)                to authenticated;
grant execute on function public.chat_blocked()                    to authenticated;
grant execute on function public.admin_chat_hide(bigint, boolean)  to authenticated;
