-- P1 Push notifications for ALL players (docs/NOTIFICATIONS.md).
-- Builds on the admin/billboard Web Push (20261012000500_billboards.sql): the same `push_subscriptions` table and the
-- same VAPID keys. New here:
--   * push_prefs      one row per player: a master switch + 5 categories (messages, money, friends, events, admin).
--                     No row = defaults (master on; messages, money and friends on; events and admin off).
--   * push_outbox     the queue. Database triggers enqueue; the `player-push` Edge Function claims and sends.
--   * bl_push_enqueue the one place that applies the rules: global + category switches, the player's prefs, "has a
--                     device", never the sender, skip a player who is active right now, one push per conversation per
--                     push.convo_window_seconds (later messages collapse into "3 new messages from @x"), hourly cap.
--   * Triggers (no existing game function is edited): DM -> player_messages, house chat -> chat_messages in a home,
--     money -> ledger (transfer_in, tip_in, admin_gift), friends/invites/weekly prize/referral -> events,
--     announcements -> broadcasts (+ broadcast_reads for targeted), club hype -> place_announcements.
--   * bl_push_tick   (service role) club events starting, recovery of stuck rows, expiry, cleanup.
--   * bl_push_claim  (service role) hands the due rows to the Edge Function once (for update skip locked).
--   * RPCs: push_state, push_prefs_set, push_subscribe, push_unsubscribe (players), admin_push_stats (admin).
--   * game_config 'push' category: global switches, category switches, rate limits.
-- Idempotent and safe on a non-empty DB. No existing function is replaced, so no grants need patching.

-- ---------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Push notifications)
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('push.enabled', 'true', 'push', 'Player push notifications on',
 'P1: master switch for pushes to players. Off = nothing is queued or sent (admin/billboard alerts to the owner are separate).', 'bool', null, null),
('push.cat_messages', 'true', 'push', 'Messages pushes',
 'P1: DMs and house chat when the player is not looking.', 'bool', null, null),
('push.cat_money', 'true', 'push', 'Money pushes',
 'P1: transfers, tips and gifts received.', 'bool', null, null),
('push.cat_friends', 'true', 'push', 'Friends and invites pushes',
 'P1: friend requests, accepted requests, house invites and knocks.', 'bool', null, null),
('push.cat_events', 'true', 'push', 'Game event pushes',
 'P1: club events starting, hype at the club you are in, weekly top-earner prize, referral bonus.', 'bool', null, null),
('push.cat_admin', 'true', 'push', 'Announcement pushes',
 'P1: Admin -> Broadcast messages (not mass gifts: those arrive as a Money push).', 'bool', null, null),
('push.events_to_all', 'true', 'push', 'Club event starts: tell everyone who opted in',
 'P1: on = every player who turned on Game events hears when a club event starts. Off = only players who bought a ticket.', 'bool', null, null),
('push.convo_window_seconds', '120', 'push', 'One push per chat every (seconds)',
 'P1: after a push for a chat, later messages in the same chat wait and arrive as one "3 new messages from @x" push once this many seconds have passed.', 'number', 0, 3600),
('push.max_per_user_hour', '20', 'push', 'Most pushes per player per hour',
 'P1: safety cap so nobody is flooded. Collapsed messages do not count twice.', 'number', 1, 500),
('push.skip_active_seconds', '20', 'push', 'Skip chat pushes if the player was active in the last (seconds)',
 'P1: a player whose game tab was open and active this recently already sees the message in the game, so no push. 0 = never skip.', 'number', 0, 600),
('push.max_age_minutes', '60', 'push', 'Drop unsent pushes older than (minutes)',
 'P1: a push that could not be sent for this long is dropped (nobody wants a 3-hour-old "new message").', 'number', 1, 1440),
('push.keep_days', '7', 'push', 'Keep the push log for (days)',
 'P1: sent / failed rows are deleted after this. Admin -> Settings -> Push notifications shows the counts.', 'number', 1, 90)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------
create table if not exists public.push_prefs (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  master     boolean not null default true,
  messages   boolean not null default true,
  money      boolean not null default true,
  friends    boolean not null default true,
  events     boolean not null default false,
  admin      boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.push_prefs enable row level security;
revoke all on table public.push_prefs from public, anon, authenticated;
grant select on table public.push_prefs to authenticated;
grant select, insert, update, delete on table public.push_prefs to service_role;
drop policy if exists push_prefs_own on public.push_prefs;
create policy push_prefs_own on public.push_prefs for select to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.push_outbox (
  id          bigserial primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  category    text not null check (category in ('messages', 'money', 'friends', 'events', 'admin')),
  kind        text not null,
  title       text not null,
  body        text not null default '',
  url         text not null default '/play',
  tag         text,
  group_key   text,
  dedupe_key  text,
  who         text,
  count       int not null default 1,
  status      text not null default 'pending' check (status in ('pending', 'sending', 'sent', 'failed', 'skipped')),
  attempts    int not null default 0,
  error       text,
  created_at  timestamptz not null default now(),
  send_after  timestamptz not null default now(),
  claimed_at  timestamptz,
  sent_at     timestamptz
);
create index if not exists push_outbox_due_idx on public.push_outbox (send_after) where status = 'pending';
create index if not exists push_outbox_group_idx on public.push_outbox (user_id, group_key, id desc) where group_key is not null;
create index if not exists push_outbox_user_hour_idx on public.push_outbox (user_id, created_at desc);
create index if not exists push_outbox_status_idx on public.push_outbox (status, created_at desc);
create unique index if not exists push_outbox_dedupe_uidx on public.push_outbox (user_id, dedupe_key) where dedupe_key is not null;
alter table public.push_outbox enable row level security;
revoke all on table public.push_outbox from public, anon, authenticated;
revoke all on sequence public.push_outbox_id_seq from public, anon, authenticated;
grant select, update, delete on table public.push_outbox to service_role;

-- ---------------------------------------------------------------------
-- 3. Private helpers (revoked from clients at the end)
-- ---------------------------------------------------------------------
-- Does this player want this category? (no row = the defaults)
create or replace function public.bl_push_wants(p_user uuid, p_cat text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select p.master and case p_cat when 'messages' then p.messages when 'money' then p.money when 'friends' then p.friends
                                    when 'events' then p.events when 'admin' then p.admin else false end
       from push_prefs p where p.user_id = p_user),
    p_cat in ('messages', 'money', 'friends'))
$$;

-- "first 60 chars" of a message, on one line.
create or replace function public.bl_push_preview(p_text text, p_len int default 60) returns text
language sql immutable set search_path = public as $$
  select case when char_length(t) > p_len then left(t, p_len) || '…' else t end
    from (select btrim(regexp_replace(coalesce(p_text, ''), '\s+', ' ', 'g')) as t) x
$$;

-- The one place every rule lives. Never raises (a push problem must never break a game action).
-- p_group  chat key: later messages collapse into one pending row and wait push.convo_window_seconds after a push.
-- p_many   title for a collapsed row, '{n}' = how many ("{n} new messages from @x").
-- p_dedupe one push per (player, key) ever (club event start).
create or replace function public.bl_push_enqueue(
  p_user uuid, p_cat text, p_kind text, p_title text, p_body text, p_url text,
  p_actor uuid default null, p_group text default null, p_who text default null,
  p_dedupe text default null, p_skip_active boolean default false, p_many text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_win    numeric;
  v_cap    int;
  v_act    numeric;
  v_pend   push_outbox;
  v_last   timestamptz;
  v_after  timestamptz := now();
  v_title  text := left(btrim(coalesce(p_title, '')), 80);
  v_body   text := left(btrim(coalesce(p_body, '')), 120);
  v_id     bigint;
begin
  if p_user is null or p_user = p_actor or v_title = '' then return null; end if;
  if not coalesce(bl_cfg_bool('push.enabled'), false) or not coalesce(bl_cfg_bool('push.cat_' || p_cat), false) then return null; end if;
  -- only players with a saved device cost anything
  if not exists (select 1 from push_subscriptions where user_id = p_user) then return null; end if;
  if not bl_push_wants(p_user, p_cat) then return null; end if;
  if exists (select 1 from profiles where id = p_user and banned) then return null; end if;
  if p_skip_active then
    v_act := coalesce(bl_cfg('push.skip_active_seconds'), 0);
    if v_act > 0 and exists (select 1 from profiles where id = p_user and last_seen > bl_now() - make_interval(secs => v_act::double precision)) then
      return null;
    end if;
  end if;

  if p_group is not null then
    v_win := greatest(0, coalesce(bl_cfg('push.convo_window_seconds'), 120));
    -- 1. a push for this chat is already waiting: fold this message into it
    select * into v_pend from push_outbox
     where user_id = p_user and group_key = p_group and status = 'pending' order by id desc limit 1 for update;
    if found then
      update push_outbox
         set count = v_pend.count + 1, body = v_body,
             title = case when p_many is not null then left(replace(p_many, '{n}', (v_pend.count + 1)::text), 80) else v_pend.title end
       where id = v_pend.id;
      return v_pend.id;
    end if;
    -- 2. one went out less than the window ago: queue this one for when the window is over
    select max(coalesce(sent_at, claimed_at, created_at)) into v_last from push_outbox
     where user_id = p_user and group_key = p_group and status in ('sending', 'sent');
    if v_last is not null and v_last + make_interval(secs => v_win::double precision) > now() then
      v_after := v_last + make_interval(secs => v_win::double precision);
    end if;
  end if;

  v_cap := greatest(1, coalesce(bl_cfg('push.max_per_user_hour'), 20))::int;
  if (select count(*) from push_outbox where user_id = p_user and created_at > now() - interval '1 hour' and status <> 'skipped') >= v_cap then
    return null;
  end if;

  insert into push_outbox (user_id, category, kind, title, body, url, tag, group_key, dedupe_key, who, send_after)
  values (p_user, p_cat, p_kind, v_title, v_body, coalesce(nullif(p_url, ''), '/play'), p_group, p_group, p_dedupe, p_who, v_after)
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing
  returning id into v_id;
  return v_id;
exception when others then
  return null;
end $$;

-- ---------------------------------------------------------------------
-- 4. Triggers (they call bl_push_enqueue and never fail the real action)
-- ---------------------------------------------------------------------
-- 4a. A DM: push the other person.
create or replace function public.bl_push_on_dm() returns trigger
language plpgsql security definer set search_path = public as $$
declare c player_conversations; v_to uuid; v_name text; v_txt text;
begin
  if new.deleted_at is not null then return null; end if;
  select * into c from player_conversations where id = new.conversation_id;
  if not found then return null; end if;
  v_to := case when c.user_a = new.sender_id then c.user_b else c.user_a end;
  if exists (select 1 from chat_blocks where blocker_id = v_to and blocked_id = new.sender_id) then return null; end if;
  select username into v_name from profiles where id = new.sender_id;
  v_txt := case when new.audio_path is not null and coalesce(new.body, '') = '' then '🎤 Voice note' else bl_push_preview(new.body, 60) end;
  perform bl_push_enqueue(v_to, 'messages', 'dm', '@' || v_name, v_txt, '/play?go=dm:' || new.conversation_id,
                          new.sender_id, 'dm:' || new.conversation_id, '@' || v_name, null, true,
                          '{n} new messages from @' || v_name);
  return null;
exception when others then
  return null;
end $$;

-- 4b. House chat: a message in a home goes to the others who are in that home right now.
create or replace function public.bl_push_on_house_chat() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; v_txt text;
begin
  if new.hidden or new.deleted_at is not null then return null; end if;
  if not exists (select 1 from locations where id = new.location_id and scene like 'home\_%') then return null; end if;
  v_txt := case when new.audio_path is not null and coalesce(new.body, '') = '' then '🎤 Voice note' else bl_push_preview(new.body, 60) end;
  for r in
    select p.id from profiles p
     where p.location_id = new.location_id and p.id <> new.user_id and not p.banned and p.travel_to is null
       and exists (select 1 from push_subscriptions s where s.user_id = p.id)
       and not exists (select 1 from chat_blocks b where b.blocker_id = p.id and b.blocked_id = new.user_id)
     limit 30
  loop
    perform bl_push_enqueue(r.id, 'messages', 'house_chat', 'House chat: @' || new.username, v_txt, '/play?go=house',
                            new.user_id, 'house:' || new.location_id, '@' || new.username, null, true,
                            '{n} new house chat messages');
  end loop;
  return null;
exception when others then
  return null;
end $$;

-- 4c. Money in: transfers, tips and gifts. (Ledger rows only exist for real money moves.)
create or replace function public.bl_push_on_money() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_from text := nullif(btrim(coalesce(new.meta->>'from_username', '')), '');
begin
  if new.delta is null or new.delta <= 0 then return null; end if;
  perform bl_push_enqueue(new.user_id, 'money',
    case new.reason when 'tip_in' then 'tip' when 'admin_gift' then 'gift' else 'transfer' end,
    case new.reason when 'tip_in' then 'You get tip 🪙' when 'admin_gift' then 'Gift from Benin Life 🎁' else 'Money don land 💰' end,
    bl_naira(new.delta) || case when new.reason = 'admin_gift' then ' don enter your ' || new.account
                                when v_from is not null then ' from @' || v_from else '' end,
    '/play?go=bank', null, null, null, null, false, null);
  return null;
exception when others then
  return null;
end $$;

-- 4d. Friends, invites, weekly prize, referral reward: the game already writes an `events` row for each.
create or replace function public.bl_push_on_event() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_who text := coalesce(substring(new.title from '@[A-Za-z0-9_]+'), 'Someone');
begin
  if new.kind = 'friend_request' then
    perform bl_push_enqueue(new.user_id, 'friends', new.kind, 'New friend request 👋', v_who || ' wan add you as friend', '/play?go=friends');
  elsif new.kind = 'friend_accepted' then
    perform bl_push_enqueue(new.user_id, 'friends', new.kind, v_who || ' accept your request 🤝', 'Una fit chat now.', '/play?go=friends');
  elsif new.kind = 'house_invite' then
    perform bl_push_enqueue(new.user_id, 'friends', new.kind, v_who || ' invite you to their house 🏠', 'Tap to accept and knock.', '/play?go=friends');
  elsif new.kind = 'house_knock' then
    perform bl_push_enqueue(new.user_id, 'friends', new.kind, v_who || ' dey your door 🚪', 'Go home make dem enter.', '/play?go=friends');
  elsif new.kind = 'weekly_prize' then
    perform bl_push_enqueue(new.user_id, 'events', new.kind, new.title, new.body, '/play?go=ranks');
  elsif new.kind = 'referral_bonus' then
    perform bl_push_enqueue(new.user_id, 'events', new.kind, new.title, new.body, '/play?go=hustles');
  end if;
  return null;
exception when others then
  return null;
end $$;

-- 4e. Admin announcements (Admin -> Broadcast). Weekly-prize broadcasts have no author and are pushed via 4d instead.
create or replace function public.bl_push_on_broadcast() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.created_by is null or new.kind <> 'message' or new.targeted or new.cancelled_at is not null then return null; end if;
  for r in select t.id from bl_broadcast_targets(new.audience, new.joined_after) t
            where exists (select 1 from push_subscriptions s where s.user_id = t.id) loop
    perform bl_push_enqueue(r.id, 'admin', 'broadcast', new.title, bl_push_preview(new.body, 100), '/play?go=alerts',
                            null, null, null, 'bc:' || new.id);
  end loop;
  return null;
exception when others then
  return null;
end $$;

-- The "online now" audience is targeted: recipients arrive as broadcast_reads rows.
create or replace function public.bl_push_on_broadcast_read() returns trigger
language plpgsql security definer set search_path = public as $$
declare b broadcasts;
begin
  select * into b from broadcasts where id = new.broadcast_id;
  if not found or b.created_by is null or b.kind <> 'message' or not b.targeted or b.cancelled_at is not null then return null; end if;
  perform bl_push_enqueue(new.user_id, 'admin', 'broadcast', b.title, bl_push_preview(b.body, 100), '/play?go=alerts',
                          null, null, null, 'bc:' || b.id);
  return null;
exception when others then
  return null;
end $$;

-- 4f. Hype in a club: the others who are in that club right now (and not looking at the game).
create or replace function public.bl_push_on_hype() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; v_place text := coalesce(nullif(new.place, ''), 'the club');
begin
  for r in
    select p.id from profiles p
     where p.location_id = new.location_id and p.id <> new.user_id and not p.banned and p.travel_to is null
       and exists (select 1 from push_subscriptions s where s.user_id = p.id)
     limit 30
  loop
    perform bl_push_enqueue(r.id, 'events', 'hype', '🔥 ' || v_place, bl_push_preview(new.text, 100), '/play?go=place:' || new.location_id,
                            new.user_id, 'hype:' || new.location_id, v_place, null, true,
                            '🔥 {n} hype moments at ' || v_place);
  end loop;
  return null;
exception when others then
  return null;
end $$;

drop trigger if exists bl_push_dm on public.player_messages;
create trigger bl_push_dm after insert on public.player_messages
  for each row execute function public.bl_push_on_dm();
drop trigger if exists bl_push_house_chat on public.chat_messages;
create trigger bl_push_house_chat after insert on public.chat_messages
  for each row execute function public.bl_push_on_house_chat();
drop trigger if exists bl_push_money on public.ledger;
create trigger bl_push_money after insert on public.ledger
  for each row when (new.reason in ('transfer_in', 'tip_in', 'admin_gift')) execute function public.bl_push_on_money();
drop trigger if exists bl_push_event on public.events;
create trigger bl_push_event after insert on public.events
  for each row when (new.kind in ('friend_request', 'friend_accepted', 'house_invite', 'house_knock', 'weekly_prize', 'referral_bonus'))
  execute function public.bl_push_on_event();
drop trigger if exists bl_push_broadcast on public.broadcasts;
create trigger bl_push_broadcast after insert on public.broadcasts
  for each row execute function public.bl_push_on_broadcast();
drop trigger if exists bl_push_broadcast_read on public.broadcast_reads;
create trigger bl_push_broadcast_read after insert on public.broadcast_reads
  for each row execute function public.bl_push_on_broadcast_read();
drop trigger if exists bl_push_hype on public.place_announcements;
create trigger bl_push_hype after insert on public.place_announcements
  for each row execute function public.bl_push_on_hype();

-- ---------------------------------------------------------------------
-- 5. Service functions for the player-push Edge Function
-- ---------------------------------------------------------------------
-- Cron-like work: club events that just started, stuck rows, expiry, cleanup. Cheap and safe to repeat.
create or replace function public.bl_push_tick() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r record; u record; v_now timestamptz := bl_now(); v_n int := 0; v_stuck int; v_old int; v_del int;
  v_age numeric := greatest(1, coalesce(bl_cfg('push.max_age_minutes'), 60));
  v_keep numeric := greatest(1, coalesce(bl_cfg('push.keep_days'), 7));
begin
  if coalesce(bl_cfg_bool('push.enabled'), false) and coalesce(bl_cfg_bool('push.cat_events'), false) then
    for r in
      select o.event_id, o.occurs_on, e.title, e.icon, l.id as loc, regexp_replace(l.name, '\s*\(.*\)\s*$', '') as place
        from bl_event_occurrences(v_now) o
        join place_events e on e.id = o.event_id and e.active
        join locations l on l.id = e.location_id and coalesce(l.active, true)
       where o.starts_at <= v_now and o.starts_at > v_now - interval '15 minutes'
    loop
      for u in
        select t.user_id as id from event_tickets t where t.event_id = r.event_id and t.occurs_on = r.occurs_on
        union
        select pp.user_id from push_prefs pp
         where coalesce(bl_cfg_bool('push.events_to_all'), false) and pp.master and pp.events
      loop
        if bl_push_enqueue(u.id, 'events', 'club_event', r.icon || ' ' || r.title || ' is starting',
                           'At ' || r.place || '. Come join!', '/play?go=place:' || r.loc, null, null, null,
                           'evt:' || r.event_id || ':' || r.occurs_on) is not null then
          v_n := v_n + 1;
        end if;
      end loop;
    end loop;
  end if;
  -- a sender that died mid-way: put the rows back (3 tries), then give up
  update push_outbox set status = case when attempts >= 3 then 'failed' else 'pending' end,
                         error = 'sender did not finish', send_after = now()
   where status = 'sending' and claimed_at < now() - interval '5 minutes';
  get diagnostics v_stuck = row_count;
  update push_outbox set status = 'skipped', error = 'too old'
   where status = 'pending' and created_at < now() - make_interval(mins => v_age::int);
  get diagnostics v_old = row_count;
  delete from push_outbox where created_at < now() - make_interval(days => v_keep::int);
  get diagnostics v_del = row_count;
  return jsonb_build_object('events_queued', v_n, 'recovered', v_stuck, 'expired', v_old, 'deleted', v_del);
end $$;

-- Hand the due rows to the sender once. Rows whose switch was turned off meanwhile are skipped, not sent.
create or replace function public.bl_push_claim(p_limit int default 100) returns setof public.push_outbox
language plpgsql security definer set search_path = public as $$
declare
  v_on  boolean := coalesce(bl_cfg_bool('push.enabled'), false);
  v_off text[] := array(select substr(g.key, 10) from game_config g
                         where g.key like 'push.cat\_%' and coalesce(g.value #>> '{}', '') <> 'true');
begin
  update push_outbox o set status = 'skipped', error = 'switched off'
   where o.status = 'pending' and o.send_after <= now()
     and (not v_on or o.category = any (v_off) or not bl_push_wants(o.user_id, o.category));
  return query
    with c as (
      select id from push_outbox where status = 'pending' and send_after <= now()
       order by id limit greatest(1, least(coalesce(p_limit, 100), 500)) for update skip locked)
    update push_outbox o set status = 'sending', claimed_at = now(), attempts = o.attempts + 1
      from c where o.id = c.id
    returning o.*;
end $$;

-- ---------------------------------------------------------------------
-- 6. Player RPCs
-- ---------------------------------------------------------------------
create or replace function public.push_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); p push_prefs;
begin
  select * into p from push_prefs where user_id = v_uid;
  return jsonb_build_object(
    'master',   coalesce(p.master, true),
    'messages', coalesce(p.messages, true),
    'money',    coalesce(p.money, true),
    'friends',  coalesce(p.friends, true),
    'events',   coalesce(p.events, false),
    'admin',    coalesce(p.admin, false),
    'devices',  (select count(*) from push_subscriptions where user_id = v_uid),
    'global',   jsonb_build_object(
      'enabled',  coalesce(bl_cfg_bool('push.enabled'), false),
      'messages', coalesce(bl_cfg_bool('push.cat_messages'), false),
      'money',    coalesce(bl_cfg_bool('push.cat_money'), false),
      'friends',  coalesce(bl_cfg_bool('push.cat_friends'), false),
      'events',   coalesce(bl_cfg_bool('push.cat_events'), false),
      'admin',    coalesce(bl_cfg_bool('push.cat_admin'), false)));
end $$;

-- Partial update: {"master": true, "messages": false, ...}. Unknown keys are refused.
create or replace function public.push_prefs_set(p_prefs jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); k text; v jsonb;
begin
  if p_prefs is null or jsonb_typeof(p_prefs) <> 'object' then
    raise exception 'Send the switches as an object.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  for k, v in select * from jsonb_each(p_prefs) loop
    if k not in ('master', 'messages', 'money', 'friends', 'events', 'admin') or jsonb_typeof(v) <> 'boolean' then
      raise exception 'Unknown notification switch "%".', k using errcode = 'P0001', hint = 'bad_value';
    end if;
  end loop;
  insert into push_prefs (user_id) values (v_uid) on conflict (user_id) do nothing;
  update push_prefs set
    master   = coalesce((p_prefs->>'master')::boolean, master),
    messages = coalesce((p_prefs->>'messages')::boolean, messages),
    money    = coalesce((p_prefs->>'money')::boolean, money),
    friends  = coalesce((p_prefs->>'friends')::boolean, friends),
    events   = coalesce((p_prefs->>'events')::boolean, events),
    admin    = coalesce((p_prefs->>'admin')::boolean, admin),
    updated_at = now()
   where user_id = v_uid;
  return push_state();
end $$;

create or replace function public.push_subscribe(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  if p_endpoint is null or p_endpoint !~ '^https://[^[:space:]]{10,}$' or length(p_endpoint) > 1000
     or coalesce(p_p256dh, '') !~ '^[A-Za-z0-9_=-]{60,120}$' or coalesce(p_auth, '') !~ '^[A-Za-z0-9_=-]{16,40}$' then
    raise exception 'That push subscription looks wrong.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  insert into push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
  values (v_uid, p_endpoint, p_p256dh, p_auth, left(coalesce(p_user_agent, ''), 200))
  on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
                                       user_agent = excluded.user_agent, fail_count = 0;
  -- at most 8 devices per player: the oldest go
  delete from push_subscriptions where user_id = v_uid and id not in
    (select id from push_subscriptions where user_id = v_uid order by id desc limit 8);
  insert into push_prefs (user_id) values (v_uid) on conflict (user_id) do nothing;
  return push_state();
end $$;

create or replace function public.push_unsubscribe(p_endpoint text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  delete from push_subscriptions where user_id = v_uid and endpoint = p_endpoint;
  return push_state();
end $$;

-- ---------------------------------------------------------------------
-- 7. Admin: how the outbox is doing
-- ---------------------------------------------------------------------
create or replace function public.admin_push_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard();
begin
  return jsonb_build_object(
    'pending',      (select count(*) from push_outbox where status in ('pending', 'sending')),
    'sent_24h',     (select count(*) from push_outbox where status = 'sent' and sent_at > now() - interval '24 hours'),
    'failed_24h',   (select count(*) from push_outbox where status = 'failed' and created_at > now() - interval '24 hours'),
    'skipped_24h',  (select count(*) from push_outbox where status = 'skipped' and created_at > now() - interval '24 hours'),
    'sent_total',   (select count(*) from push_outbox where status = 'sent'),
    'failed_total', (select count(*) from push_outbox where status = 'failed'),
    'oldest_pending_s', (select coalesce(extract(epoch from now() - min(send_after))::int, 0) from push_outbox where status = 'pending' and send_after <= now()),
    'players',      (select count(distinct user_id) from push_subscriptions),
    'devices',      (select count(*) from push_subscriptions),
    'by_category',  coalesce((select jsonb_object_agg(category, n) from
                       (select category, count(*) as n from push_outbox where status = 'sent' and sent_at > now() - interval '24 hours' group by 1) x), '{}'::jsonb),
    'last_error',   (select error from push_outbox where status = 'failed' order by id desc limit 1),
    'keep_days',    bl_cfg('push.keep_days'));
end $$;

-- ---------------------------------------------------------------------
-- 8. Grants: helpers private, RPCs for signed-in players, service functions for the service role only
-- ---------------------------------------------------------------------
revoke all on function public.bl_push_wants(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_push_preview(text, int) from public, anon, authenticated;
revoke all on function public.bl_push_enqueue(uuid, text, text, text, text, text, uuid, text, text, text, boolean, text) from public, anon, authenticated;
revoke all on function public.bl_push_on_dm() from public, anon, authenticated;
revoke all on function public.bl_push_on_house_chat() from public, anon, authenticated;
revoke all on function public.bl_push_on_money() from public, anon, authenticated;
revoke all on function public.bl_push_on_event() from public, anon, authenticated;
revoke all on function public.bl_push_on_broadcast() from public, anon, authenticated;
revoke all on function public.bl_push_on_broadcast_read() from public, anon, authenticated;
revoke all on function public.bl_push_on_hype() from public, anon, authenticated;
revoke all on function public.bl_push_tick() from public, anon, authenticated;
revoke all on function public.bl_push_claim(int) from public, anon, authenticated;
grant execute on function public.bl_push_tick() to service_role;
grant execute on function public.bl_push_claim(int) to service_role;

do $$
declare f text;
begin
  foreach f in array array['push_state()', 'push_prefs_set(jsonb)', 'push_subscribe(text,text,text,text)',
                           'push_unsubscribe(text)', 'admin_push_stats()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
