-- Family & Love, stage 1 (docs/LOVE.md). One phone app "Family" (Link-ups, Us, Family).
--   * Players opt in ("Open to link-ups"), ask each other out, the other accepts (status talking), both send PRESET flirts (a menu,
--     never free text) that raise a shared level 0-100; at love.couple_level (30) the pair becomes a couple. Dates ("go out together")
--     at real Benin places add bond points and fun / social. Break-up with cooldowns. Reports reuse the chat block list.
--   * Server-authoritative and lazy: no cron. Decay (idle days) is applied on read (display) and on write (stored) for the pair touched only.
--   * Clients never touch the tables: every table has RLS on and no grant; everything goes through security-definer RPCs.
--   * Stage 2 (kids) can hang off love_relationships.id: see docs/LOVE.md.
-- Idempotent: tables `if not exists`, seeds `on conflict do nothing` (admin edits survive), functions `create or replace`, live functions
-- patched ONLY through a guarded replace on pg_get_functiondef (raises when the marker is missing, skips when already applied).

-- ---------------------------------------------------------------------------------------------
-- 0. Guarded patch helper (session only)
-- ---------------------------------------------------------------------------------------------
create or replace function pg_temp.love_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'family_love: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Love)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('love.enabled', 'true', 'love', 'Family & love on',
 'Master switch for the Family app. Off = nobody can ask out, flirt, go on dates or be listed. Existing couples are kept and come back when it is switched on.', 'bool', null, null),
('love.min_account_days', '2', 'love', 'Account age to link up (days)',
 'A player can ask, and be listed in Link-ups, only after their account is this many days old (stops brand-new throw-away accounts).', 'number', 0, 365),
('love.max_partners', '1', 'love', 'Most partners at once',
 'How many people one player can be with at the same time. Talking and couple both count. 1 = one partner only.', 'number', 1, 5),
('love.asks_per_day', '5', 'love', 'Asks per day',
 'How many times one player can ask somebody out in 24 hours (withdrawn, declined and expired asks count).', 'number', 1, 50),
('love.decline_cooldown_days', '3', 'love', 'Wait after a decline (days)',
 'After somebody says no, the asker cannot ask that same person again for this many days. The asker only ever sees "No reply".', 'number', 0, 60),
('love.ask_expire_hours', '48', 'love', 'An ask waits for (hours)',
 'A pending ask disappears after this many hours with no answer.', 'number', 1, 720),
('love.flirt_daily_cap', '20', 'love', 'Level a pair can gain a day',
 'Most level points one pair can earn in one game day, flirts and dates together. Stops people grinding to couple in minutes.', 'number', 1, 100),
('love.flirt_cooldown_minutes', '20', 'love', 'Wait between flirts (minutes)',
 'After sending a flirt, the same player has to wait this long before sending another one.', 'number', 0, 1440),
('love.decay_after_days', '3', 'love', 'Level starts falling after (idle days)',
 'If the pair does no flirt and no date for this many days, the level begins to drop.', 'number', 0, 60),
('love.decay_per_day', '2', 'love', 'Level lost per idle day',
 'Points lost for each idle day after the grace days. A couple never falls below the couple level (they stay a couple); a talking pair can fall to 0.', 'number', 0, 50),
('love.couple_level', '30', 'love', 'Level where they become a couple',
 'When the shared level reaches this, status flips from talking to couple and both get an alert. The level keeps counting up to 100 as "bond".', 'number', 5, 100),
('love.date_invite_expire_minutes', '30', 'love', 'A date invite waits for (minutes)',
 'The partner has this long to accept a date invite (and be at the place).', 'number', 1, 1440),
('love.breakup_cooldown_days', '3', 'love', 'After a break-up: not each other (days)',
 'After a break-up, the two cannot ask each other out again for this many days.', 'number', 0, 90),
('love.breakup_global_cooldown_hours', '24', 'love', 'After a break-up: not anyone (hours)',
 'After a break-up, both players cannot ask anybody out for this many hours.', 'number', 0, 720),
('love.list_size', '30', 'love', 'Link-ups list page size',
 'How many players one page of the Link-ups list shows (at most 50).', 'number', 5, 50),
('love.online_minutes', '10', 'love', 'Online recently means (minutes)',
 'The "Online now" filter in Link-ups lists players seen in the last this many minutes.', 'number', 1, 1440),
('love.poll_seconds', '45', 'love', 'Family app refresh (seconds)',
 'How often the open Family app asks the server for news. It never polls while closed, while the tab is hidden or when the player is away.', 'number', 20, 300),
('love.report_daily_cap', '5', 'love', 'Reports per player per day',
 'Stops report spam. Reports are listed in Admin -> Love.', 'number', 1, 50)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Profile flags
-- ---------------------------------------------------------------------------------------------
alter table public.profiles add column if not exists love_open boolean not null default false;
alter table public.profiles add column if not exists show_relationship boolean not null default true;
create index if not exists profiles_love_open_idx on public.profiles (last_seen desc nulls last, id) where love_open;

-- ---------------------------------------------------------------------------------------------
-- 3. Tables
-- ---------------------------------------------------------------------------------------------
-- A relationship between two players. user_a < user_b always (one row per pair at a time). Stage 2 children reference id.
create table if not exists public.love_relationships (
  id               bigserial primary key,
  user_a           uuid not null references public.profiles(id) on delete cascade,
  user_b           uuid not null references public.profiles(id) on delete cascade,
  asked_by         uuid not null,
  status           text not null default 'talking' check (status in ('talking', 'couple', 'ended')),
  level            integer not null default 0 check (level between 0 and 100),
  started_at       timestamptz not null default now(),
  couple_at        timestamptz,
  ended_at         timestamptz,
  ended_by         uuid,
  last_activity_at timestamptz not null default now(),
  decay_days       integer not null default 0 check (decay_days >= 0),
  check (user_a < user_b)
);
create unique index if not exists love_rel_pair_live on public.love_relationships (user_a, user_b) where status <> 'ended';
create index if not exists love_rel_a_live on public.love_relationships (user_a) where status <> 'ended';
create index if not exists love_rel_b_live on public.love_relationships (user_b) where status <> 'ended';
create index if not exists love_rel_a_ended on public.love_relationships (user_a, ended_at desc) where status = 'ended';
create index if not exists love_rel_b_ended on public.love_relationships (user_b, ended_at desc) where status = 'ended';

create table if not exists public.love_asks (
  id              bigserial primary key,
  from_user       uuid not null references public.profiles(id) on delete cascade,
  to_user         uuid not null references public.profiles(id) on delete cascade,
  status          text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired', 'withdrawn')),
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null,
  responded_at    timestamptz,
  relationship_id bigint references public.love_relationships(id) on delete set null,
  check (from_user <> to_user)
);
create unique index if not exists love_asks_one_pending on public.love_asks (from_user, to_user) where status = 'pending';
create index if not exists love_asks_incoming on public.love_asks (to_user, expires_at desc) where status = 'pending';
create index if not exists love_asks_from on public.love_asks (from_user, created_at desc);
create index if not exists love_asks_declined on public.love_asks (from_user, to_user, responded_at desc) where status = 'declined';

-- The flirt menu (admin data, PG-rated, never free text).
create table if not exists public.love_flirts (
  id        text primary key,
  text      text not null check (char_length(text) between 3 and 120),
  icon      text not null default '💞' check (char_length(icon) between 1 and 8),
  points    integer not null default 3 check (points between 0 and 30),
  cost      bigint not null default 0 check (cost >= 0),
  min_level integer not null default 0 check (min_level between 0 and 100),
  active    boolean not null default true,
  sort      integer not null default 0
);

-- Dates: go out together at a real place.
create table if not exists public.love_dates (
  id            text primary key,
  name          text not null check (char_length(name) between 3 and 60),
  icon          text not null default '💞' check (char_length(icon) between 1 and 8),
  place_id      text references public.locations(id) on update cascade on delete set null,
  cost_each     bigint not null default 0 check (cost_each >= 0),
  fun_gain      integer not null default 0 check (fun_gain between 0 and 100),
  social_gain   integer not null default 0 check (social_gain between 0 and 100),
  bond_points   integer not null default 2 check (bond_points between 0 and 30),
  cooldown_hours integer not null default 6 check (cooldown_hours between 0 and 720),
  min_status    text not null default 'talking' check (min_status in ('talking', 'couple')),
  active        boolean not null default true,
  sort          integer not null default 0
);

-- What happened between the two: flirts, dates, milestones. Newest first in the app.
create table if not exists public.love_log (
  id         bigserial primary key,
  rel_id     bigint not null references public.love_relationships(id) on delete cascade,
  kind       text not null check (kind in ('started', 'flirt', 'date', 'couple', 'ended')),
  actor_id   uuid,
  ref_id     text,
  text       text not null default '',
  icon       text,
  points     integer not null default 0,
  day        bigint,
  created_at timestamptz not null default now()
);
create index if not exists love_log_rel on public.love_log (rel_id, id desc);
create index if not exists love_log_day on public.love_log (rel_id, day);
create index if not exists love_log_kind on public.love_log (rel_id, kind, id desc);

create table if not exists public.love_date_invites (
  id           bigserial primary key,
  rel_id       bigint not null references public.love_relationships(id) on delete cascade,
  date_id      text not null references public.love_dates(id) on update cascade on delete cascade,
  from_user    uuid not null references public.profiles(id) on delete cascade,
  to_user      uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired', 'cancelled')),
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  responded_at timestamptz
);
create unique index if not exists love_invites_one_pending on public.love_date_invites (rel_id) where status = 'pending';

create table if not exists public.love_reports (
  id          bigserial primary key,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_id uuid not null references public.profiles(id) on delete cascade,
  rel_id      bigint references public.love_relationships(id) on delete set null,
  reason      text not null default '' check (char_length(reason) <= 300),
  status      text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at  timestamptz not null default now(),
  handled_by  uuid,
  handled_at  timestamptz,
  check (reporter_id <> reported_id)
);
create index if not exists love_reports_status on public.love_reports (status, created_at desc);
create index if not exists love_reports_reporter on public.love_reports (reporter_id, created_at desc);

-- RLS on, no policies, no grants: clients use the RPCs only.
do $$
declare t text;
begin
  foreach t in array array['love_relationships', 'love_asks', 'love_flirts', 'love_dates', 'love_log', 'love_date_invites', 'love_reports'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
  revoke all on sequence public.love_relationships_id_seq, public.love_asks_id_seq, public.love_log_id_seq,
    public.love_date_invites_id_seq, public.love_reports_id_seq from public, anon, authenticated;
end $$;

-- Admin-edited text goes through the chat banned-words list (a masked word means the text is refused).
create or replace function public.bl_love_text_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'love_flirts' then
    if bl_chat_mask(new.text) <> new.text then
      raise exception 'Keep the flirt line clean: it has a banned word.' using errcode = 'P0001', hint = 'blocked_text';
    end if;
  else
    if bl_chat_mask(new.name) <> new.name then
      raise exception 'Keep the date name clean: it has a banned word.' using errcode = 'P0001', hint = 'blocked_text';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists love_flirts_guard on public.love_flirts;
create trigger love_flirts_guard before insert or update of text on public.love_flirts for each row execute function public.bl_love_text_guard();
drop trigger if exists love_dates_guard on public.love_dates;
create trigger love_dates_guard before insert or update of name on public.love_dates for each row execute function public.bl_love_text_guard();

-- ---------------------------------------------------------------------------------------------
-- 4. Seeds: flirt lines and dates (real Benin places that exist in `locations`)
-- ---------------------------------------------------------------------------------------------
insert into public.love_flirts (id, text, icon, points, cost, min_level, sort) values
('wave',       'Hey you! Abeg, how your day dey go?',                              '👋', 2, 0,    0,  10),
('smile',      'You dey smile like person wey sabi cook jollof well.',            '😊', 2, 0,    0,  20),
('compliment', 'Wahala! You fine reach say sun dey shame.',                       '✨', 3, 200,  0,  30),
('gist',       'I no fit sleep. Na your gist dey enter my head.',                 '💬', 3, 300,  0,  40),
('airtime',    'I don send small airtime make we gist tonight.',                  '📱', 4, 500,  0,  50),
('zobo',       'I buy cold zobo for you. Sweet like you.',                        '🍹', 4, 800,  0,  60),
('song',       'Na this song remind me of you. Listen am well.',                  '🎵', 5, 1500, 3,  70),
('heart',      'My heart dey go gbam gbam when you show face.',                   '💓', 5, 1000, 5,  80),
('pepper_rice','One day na me go carry you chop pepper rice, no dull.',           '🍛', 6, 2000, 8,  90),
('flowers',    'Flowers for the sweetest person for Benin City.',                 '💐', 6, 3000, 10, 100),
('gift',       'Small something for you. E no big, but na love.',                 '🎁', 7, 5000, 12, 110),
('love_note',  'You be my person. For real, no be joke.',                         '💌', 8, 6000, 15, 120)
on conflict (id) do nothing;

insert into public.love_dates (id, name, icon, place_id, cost_each, fun_gain, social_gain, bond_points, cooldown_hours, min_status, sort) values
('suya_oba',    'Suya at Oba Market',                    '🍢', 'oba_market',       3000,  8,  10, 3,  6,  'talking', 10),
('ring_walk',   'Evening walk on Ring Road',             '🌆', 'ring_road_pos',    500,   6,  8,  2,  4,  'talking', 20),
('palace_walk', 'Stroll by the Oba''s Palace',           '🏛️', 'oba_palace',       1000,  6,  8,  3,  8,  'talking', 30),
('emotan_photo','Photos at the Emotan Statue',           '📸', 'emotan_statue',    500,   7,  8,  2,  6,  'talking', 40),
('museum',      'Benin National Museum tour',            '🏺', 'national_museum',  1500,  9,  8,  3,  12, 'talking', 50),
('buka_date',   'Pepper rice at Mama Osas Buka',         '🍛', 'mama_osas_buka',   2500,  8,  10, 3,  8,  'talking', 60),
('mall_date',   'Ice cream and window shopping',         '🍦', 'benin_city_mall',  5000,  12, 10, 4,  12, 'talking', 70),
('cinema',      'Movie night at Kada Plaza',             '🎬', 'kada_plaza',       6000,  18, 10, 5,  12, 'talking', 80),
('zoo_picnic',  'Picnic at Ogba Zoo & Nature Park',      '🧺', 'ogba_zoo',         4000,  20, 14, 6,  24, 'talking', 90),
('video_call',  'Late-night video call',                 '📱', null,               300,   4,  8,  1,  3,  'talking', 100),
('lounge_night','Cocktails at Kingdom Lounge, GRA',      '🍸', 'kingdom_lounge',   15000, 25, 18, 6,  24, 'couple',  110),
('getaway',     'Weekend getaway, hotel on Emotan Road', '🏨', 'protea_hotel',     50000, 40, 30, 10, 72, 'couple',  120)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 5. Private helpers (revoked from clients at the end)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_love_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(bl_cfg_bool('love.enabled'), true)
$$;

create or replace function public.bl_love_num(p_key text, p_def numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_def)
$$;

create or replace function public.bl_love_day() returns bigint
language sql stable security definer set search_path = public as $$
  select (bl_game_clock(bl_now())->>'day')::bigint
$$;

-- "about 12 min", "about 3 hours", "about 2 days"
create or replace function public.bl_love_wait_text(p_seconds numeric) returns text
language sql immutable set search_path = public as $$
  select case when p_seconds >= 172800 then 'about ' || ceil(p_seconds / 86400)::int || ' days'
              when p_seconds >= 7200 then 'about ' || ceil(p_seconds / 3600)::int || ' hours'
              when p_seconds >= 3600 then 'about 1 hour'
              when p_seconds > 60 then 'about ' || ceil(p_seconds / 60)::int || ' min'
              else 'a minute' end
$$;

create or replace function public.bl_love_partner_count(p_uid uuid) returns integer
language sql stable security definer set search_path = public as $$
  select (select count(*) from love_relationships where user_a = p_uid and status <> 'ended')::int
       + (select count(*) from love_relationships where user_b = p_uid and status <> 'ended')::int
$$;

-- idle days past the grace period
create or replace function public.bl_love_due_days(r public.love_relationships) returns integer
language sql stable security definer set search_path = public as $$
  select greatest(0, floor(extract(epoch from (bl_now() - r.last_activity_at)) / 86400)::int - bl_love_num('love.decay_after_days', 3)::int)
$$;

-- The level after lazy decay (pure: nothing is written). A couple never falls under the couple level.
create or replace function public.bl_love_level_now(r public.love_relationships) returns integer
language sql stable security definer set search_path = public as $$
  select case when r.status = 'ended' then r.level
              else greatest(case when r.status = 'couple' then least(r.level, bl_love_num('love.couple_level', 30)::int) else 0 end,
                            r.level - greatest(0, bl_love_due_days(r) - r.decay_days) * bl_love_num('love.decay_per_day', 2)::int) end
$$;

-- Apply the decay to the stored row (call with the row locked). Only the pair being touched.
create or replace function public.bl_love_settle(r public.love_relationships) returns public.love_relationships
language plpgsql security definer set search_path = public as $$
declare v_due int := bl_love_due_days(r); v_lvl int := bl_love_level_now(r);
begin
  if r.status = 'ended' or v_due <= r.decay_days then return r; end if;
  update love_relationships set level = v_lvl, decay_days = v_due where id = r.id returning * into r;
  return r;
end $$;

-- Alert + push (the existing 'friends' push category).
create or replace function public.bl_love_notify(p_to uuid, p_kind text, p_title text, p_body text, p_url text, p_actor uuid,
                                                  p_data jsonb default '{}'::jsonb, p_group text default null, p_many text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform bl_event(p_to, p_kind, p_title, p_body, coalesce(p_data, '{}'::jsonb));
  perform bl_push_enqueue(p_to, 'friends', p_kind, p_title, p_body, p_url, p_actor, p_group, null, null, false, p_many);
end $$;

-- Why can't this player ask anybody out right now? null = they can. {"code","msg"}.
create or replace function public.bl_love_ask_block(p_me public.profiles) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_cd timestamptz; v_n int; v_cap int := bl_love_num('love.asks_per_day', 5)::int; v_days numeric := bl_love_num('love.min_account_days', 2);
begin
  if not bl_love_on() then
    return jsonb_build_object('code', 'off', 'msg', 'Family and love is switched off for now.');
  end if;
  if not p_me.love_open then
    return jsonb_build_object('code', 'not_open', 'msg', 'Switch on "Open to link-ups" first.');
  end if;
  if p_me.created_at > bl_now() - make_interval(days => v_days::int) then
    return jsonb_build_object('code', 'too_new', 'msg', 'Your account is too new for link-ups. Come back in a day or two.');
  end if;
  if bl_love_partner_count(p_me.id) >= bl_love_num('love.max_partners', 1)::int then
    return jsonb_build_object('code', 'taken', 'msg', 'You are already with somebody. End that first if you want to ask someone new.');
  end if;
  select max(r.ended_at) into v_cd from love_relationships r
   where r.status = 'ended' and (r.user_a = p_me.id or r.user_b = p_me.id)
     and r.ended_at > bl_now() - make_interval(hours => bl_love_num('love.breakup_global_cooldown_hours', 24)::int);
  if v_cd is not null then
    return jsonb_build_object('code', 'cooldown_global', 'msg', 'Give your heart a small break. You can ask again in '
      || bl_love_wait_text(extract(epoch from (v_cd + make_interval(hours => bl_love_num('love.breakup_global_cooldown_hours', 24)::int) - bl_now()))) || '.');
  end if;
  select count(*) into v_n from love_asks a where a.from_user = p_me.id and a.created_at > bl_now() - interval '24 hours';
  if v_n >= v_cap then
    return jsonb_build_object('code', 'daily_cap', 'msg', 'You have used all ' || v_cap || ' asks for today. Try again tomorrow.');
  end if;
  return null;
end $$;

-- The relationship the caller means (locked + settled). p_rel null = their only one.
create or replace function public.bl_love_lock_rel(p_uid uuid, p_rel bigint) returns public.love_relationships
language plpgsql security definer set search_path = public as $$
declare r public.love_relationships; n int;
begin
  if p_rel is null then
    n := bl_love_partner_count(p_uid);
    if n = 0 then
      raise exception 'You are not linked up with anybody yet.' using errcode = 'P0001', hint = 'no_relationship';
    end if;
    if n > 1 then
      raise exception 'Pick which one you mean.' using errcode = 'P0001', hint = 'pick_one';
    end if;
    select * into r from love_relationships where status <> 'ended' and (user_a = p_uid or user_b = p_uid) for update;
  else
    select * into r from love_relationships where id = p_rel and status <> 'ended' and p_uid in (user_a, user_b) for update;
  end if;
  if not found then
    raise exception 'That link-up is not active any more.' using errcode = 'P0001', hint = 'no_relationship';
  end if;
  return bl_love_settle(r);
end $$;

-- Add level points (daily cap shared by flirts and dates), log it, flip to couple at the couple level, alert both. Row locked + settled.
create or replace function public.bl_love_gain(r public.love_relationships, p_points integer, p_kind text, p_actor uuid, p_ref text,
                                               p_text text, p_icon text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_day   bigint := bl_love_day();
  v_cap   int := bl_love_num('love.flirt_daily_cap', 20)::int;
  v_used  int;
  v_room  int;
  v_gain  int;
  v_new   int;
  v_flip  boolean := false;
  v_other uuid := case when r.user_a = p_actor then r.user_b else r.user_a end;
  v_an    text; v_on text;
begin
  select coalesce(sum(points), 0)::int into v_used from love_log where rel_id = r.id and day = v_day;
  v_room := greatest(0, v_cap - v_used);
  v_gain := greatest(0, least(p_points, v_room, 100 - r.level));
  v_new := r.level + v_gain;
  if r.status = 'talking' and v_new >= bl_love_num('love.couple_level', 30)::int then v_flip := true; end if;
  update love_relationships
     set level = v_new, last_activity_at = bl_now(), decay_days = 0,
         status = case when v_flip then 'couple' else status end,
         couple_at = case when v_flip then bl_now() else couple_at end
   where id = r.id;
  insert into love_log (rel_id, kind, actor_id, ref_id, text, icon, points, day, created_at)
  values (r.id, p_kind, p_actor, p_ref, p_text, p_icon, v_gain, v_day, bl_now());
  if v_flip then
    insert into love_log (rel_id, kind, actor_id, text, icon, points, day, created_at)
    values (r.id, 'couple', null, 'You are now a couple', '💞', 0, v_day, bl_now());
    select username into v_an from profiles where id = p_actor;
    select username into v_on from profiles where id = v_other;
    perform bl_love_notify(p_actor, 'love_couple', 'You are now a couple 💞', 'You and @' || coalesce(v_on, 'your partner') || ' are officially together. See it in the Family app.',
                           '/play?go=family:family', null, jsonb_build_object('rel', r.id, 'partner', v_other));
    perform bl_love_notify(v_other, 'love_couple', 'You are now a couple 💞', 'You and @' || coalesce(v_an, 'your partner') || ' are officially together. See it in the Family app.',
                           '/play?go=family:family', p_actor, jsonb_build_object('rel', r.id, 'partner', p_actor));
  end if;
  return jsonb_build_object('gained', v_gain, 'asked', p_points, 'level', v_new, 'room_before', v_room, 'capped', v_gain < p_points,
                            'couple_now', v_flip);
end $$;

-- What a profile shows about the relationship (null when the player hides it or is single).
create or replace function public.bl_love_public(p_uid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('status', r.status, 'partner', jsonb_build_object('id', o.id, 'username', o.username))
    from profiles me
    join love_relationships r on r.status <> 'ended' and p_uid in (r.user_a, r.user_b)
    join profiles o on o.id = case when r.user_a = p_uid then r.user_b else r.user_a end
   where me.id = p_uid and me.show_relationship and bl_love_on() and not o.banned
   order by r.started_at limit 1
$$;

-- ---------------------------------------------------------------------------------------------
-- 6. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.love_set_open(p_open boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  if not exists (select 1 from profiles where id = v_uid) then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  update profiles set love_open = coalesce(p_open, false) where id = v_uid;
  if not coalesce(p_open, false) then
    -- closing the door: pending asks to me are gone, and so are the ones I sent
    update love_asks set status = 'expired', responded_at = bl_now() where to_user = v_uid and status = 'pending';
    update love_asks set status = 'withdrawn', responded_at = bl_now() where from_user = v_uid and status = 'pending';
  end if;
  return jsonb_build_object('open', coalesce(p_open, false),
    'message', case when coalesce(p_open, false) then 'You are open to link-ups. Other players can see you in Link-ups.' else 'You are hidden from Link-ups now.' end);
end $$;

create or replace function public.love_set_show_relationship(p_show boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  update profiles set show_relationship = coalesce(p_show, true) where id = v_uid;
  return jsonb_build_object('show', coalesce(p_show, true),
    'message', case when coalesce(p_show, true) then 'Your relationship shows on your profile.' else 'Your relationship is hidden on your profile.' end);
end $$;

-- One read for the whole app: me, incoming / outgoing asks, my relationships with log, the flirt and date menus.
create or replace function public.love_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid     uuid := bl_require_uid();
  v_me      profiles;
  v_now     timestamptz := bl_now();
  v_day     bigint := bl_love_day();
  v_cap     int := bl_love_num('love.flirt_daily_cap', 20)::int;
  v_cdm     numeric := bl_love_num('love.flirt_cooldown_minutes', 20);
  v_asks_n  int;
  v_in      jsonb; v_out jsonb; v_rels jsonb := '[]'::jsonb; v_flirts jsonb; v_dates jsonb;
  r         public.love_relationships;
  v_pid     uuid; v_pname text; v_pav jsonb;
  v_lvl     int; v_lastf timestamptz; v_cd numeric; v_room int; v_dcd jsonb; v_log jsonb; v_inv jsonb; v_hist jsonb;
  v_block   jsonb;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  select count(*) into v_asks_n from love_asks a where a.from_user = v_uid and a.created_at > v_now - interval '24 hours';
  v_block := bl_love_ask_block(v_me);

  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'created_at', a.created_at, 'expires_at', a.expires_at,
           'from', jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar, 'street_cred', p.street_cred, 'title', bl_pol_title(p.id)))
         order by a.created_at desc), '[]'::jsonb) into v_in
    from (select * from love_asks where to_user = v_uid and status = 'pending' and expires_at > v_now order by created_at desc limit 20) a
    join profiles p on p.id = a.from_user and not p.banned;

  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'created_at', a.created_at, 'expires_at', a.expires_at,
           'state', case when a.status = 'pending' and a.expires_at > v_now then 'pending' else 'noreply' end,
           'to', jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar))
         order by a.created_at desc), '[]'::jsonb) into v_out
    from (select * from love_asks
           where from_user = v_uid and created_at > v_now - interval '7 days'
             and (status in ('declined', 'expired') or (status = 'pending'))
           order by created_at desc limit 20) a
    join profiles p on p.id = a.to_user and not p.banned;

  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'text', f.text, 'icon', f.icon, 'points', f.points, 'cost', f.cost, 'min_level', f.min_level)
                            order by f.sort, f.id), '[]'::jsonb) into v_flirts
    from love_flirts f where f.active;

  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'icon', d.icon, 'place_id', d.place_id, 'place_name', l.name,
           'cost_each', d.cost_each, 'fun_gain', d.fun_gain, 'social_gain', d.social_gain, 'bond_points', d.bond_points,
           'cooldown_hours', d.cooldown_hours, 'min_status', d.min_status,
           'me_here', d.place_id is null or (v_me.location_id = d.place_id and v_me.travel_to is null))
         order by d.sort, d.id), '[]'::jsonb) into v_dates
    from love_dates d left join locations l on l.id = d.place_id where d.active;

  for r in select * from love_relationships where status <> 'ended' and (user_a = v_uid or user_b = v_uid) order by started_at limit 5 loop
    v_pid := case when r.user_a = v_uid then r.user_b else r.user_a end;
    select username, avatar into v_pname, v_pav from profiles where id = v_pid;
    v_lvl := bl_love_level_now(r);
    select max(created_at) into v_lastf from love_log where rel_id = r.id and kind = 'flirt' and actor_id = v_uid;
    v_cd := case when v_lastf is null then 0 else greatest(0, ceil(extract(epoch from (v_lastf + make_interval(secs => (v_cdm * 60)::double precision) - v_now)))) end;
    v_room := greatest(0, v_cap - (select coalesce(sum(points), 0)::int from love_log where rel_id = r.id and day = v_day));
    select coalesce(jsonb_object_agg(d.id, greatest(0, ceil(extract(epoch from (x.last + make_interval(hours => d.cooldown_hours) - v_now))))), '{}'::jsonb) into v_dcd
      from love_dates d
      join lateral (select max(created_at) as last from love_log l where l.rel_id = r.id and l.kind = 'date' and l.ref_id = d.id) x on x.last is not null
     where d.active and x.last + make_interval(hours => d.cooldown_hours) > v_now;
    select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'kind', g.kind, 'mine', g.actor_id = v_uid, 'text', g.text, 'icon', g.icon,
             'points', g.points, 'created_at', g.created_at) order by g.id desc), '[]'::jsonb) into v_log
      from (select * from love_log where rel_id = r.id order by id desc limit 15) g;
    select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'text', g.text, 'icon', g.icon, 'points', g.points, 'created_at', g.created_at) order by g.id desc), '[]'::jsonb) into v_hist
      from (select * from love_log where rel_id = r.id and kind = 'date' order by id desc limit 5) g;
    select jsonb_build_object('id', i.id, 'date_id', i.date_id, 'mine', i.from_user = v_uid, 'expires_at', i.expires_at) into v_inv
      from love_date_invites i where i.rel_id = r.id and i.status = 'pending' and i.expires_at > v_now;
    v_rels := v_rels || jsonb_build_object(
      'id', r.id, 'status', r.status, 'level', v_lvl, 'started_at', r.started_at, 'couple_at', r.couple_at,
      'last_activity_at', r.last_activity_at,
      'days_together', floor(extract(epoch from (v_now - coalesce(r.couple_at, r.started_at))) / 86400)::int,
      'partner', jsonb_build_object('id', v_pid, 'username', v_pname, 'avatar', v_pav),
      'flirt_cooldown_seconds', v_cd, 'daily_room', v_room, 'date_cooldowns', v_dcd,
      'log', v_log, 'recent_dates', v_hist, 'invite', v_inv);
  end loop;

  return jsonb_build_object(
    'enabled', bl_love_on(),
    'poll_seconds', greatest(20, bl_love_num('love.poll_seconds', 45)),
    'couple_level', bl_love_num('love.couple_level', 30),
    'max_partners', bl_love_num('love.max_partners', 1),
    'rules', jsonb_build_object('breakup_days', bl_love_num('love.breakup_cooldown_days', 3), 'breakup_hours', bl_love_num('love.breakup_global_cooldown_hours', 24),
                                'ask_expire_hours', bl_love_num('love.ask_expire_hours', 48), 'decay_after_days', bl_love_num('love.decay_after_days', 3),
                                'decay_per_day', bl_love_num('love.decay_per_day', 2), 'date_expire_minutes', bl_love_num('love.date_invite_expire_minutes', 30),
                                'flirt_cooldown_minutes', bl_love_num('love.flirt_cooldown_minutes', 20), 'daily_cap', bl_love_num('love.flirt_daily_cap', 20)),
    'me', jsonb_build_object('open', v_me.love_open, 'show_relationship', v_me.show_relationship,
                             'asks_left', greatest(0, bl_love_num('love.asks_per_day', 5)::int - v_asks_n),
                             'asks_cap', bl_love_num('love.asks_per_day', 5)::int,
                             'ask_block', v_block,
                             'min_account_days', bl_love_num('love.min_account_days', 2)),
    'incoming', v_in, 'outgoing', v_out, 'relationships', v_rels, 'flirts', v_flirts, 'dates', v_dates);
end $$;

-- Link-ups: opted-in players, newest activity first. filter = all | here | online. Paged (<= 50 a page).
create or replace function public.love_candidates(p_filter text default 'all', p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_me    profiles;
  v_now   timestamptz := bl_now();
  v_size  int := least(50, greatest(1, bl_love_num('love.list_size', 30)::int));
  v_off   int := greatest(0, least(coalesce(p_offset, 0), 5000));
  v_f     text := case when p_filter in ('here', 'online') then p_filter else 'all' end;
  v_min   int := bl_love_num('love.min_account_days', 2)::int;
  v_max   int := bl_love_num('love.max_partners', 1)::int;
  v_dec   int := bl_love_num('love.decline_cooldown_days', 3)::int;
  v_brk   int := bl_love_num('love.breakup_cooldown_days', 3)::int;
  v_onl   numeric := bl_love_num('love.online_minutes', 10);
  v_rows  jsonb;
  v_n     int;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if not bl_love_on() then
    return jsonb_build_object('enabled', false, 'rows', '[]'::jsonb, 'has_more', false, 'filter', v_f);
  end if;
  if not v_me.love_open then
    return jsonb_build_object('enabled', true, 'rows', '[]'::jsonb, 'has_more', false, 'filter', v_f, 'closed', true);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id, 'username', x.username, 'avatar', x.avatar, 'street_cred', x.street_cred,
           'title', bl_pol_title(x.id), 'crew', bl_crew_badge(x.id),
           'online', x.last_seen is not null and x.last_seen > v_now - make_interval(secs => (v_onl * 60)::double precision),
           'here', x.location_id = v_me.location_id and x.travel_to is null and v_me.travel_to is null,
           'state', case
              when exists (select 1 from love_asks a where a.from_user = v_uid and a.to_user = x.id and a.status = 'pending' and a.expires_at > v_now) then 'pending'
              when exists (select 1 from love_asks a where a.from_user = x.id and a.to_user = v_uid and a.status = 'pending' and a.expires_at > v_now) then 'incoming'
              when exists (select 1 from love_asks a where a.from_user = v_uid and a.to_user = x.id and a.status = 'declined' and a.responded_at > v_now - make_interval(days => v_dec)) then 'later'
              when exists (select 1 from love_relationships r where r.status = 'ended' and r.ended_at > v_now - make_interval(days => v_brk)
                              and r.user_a = least(v_uid, x.id) and r.user_b = greatest(v_uid, x.id)) then 'later'
              else 'ask' end) order by x.rn) filter (where x.rn <= v_size), '[]'::jsonb),
         count(*)
    into v_rows, v_n
    from (select q.*, row_number() over (order by q.last_seen desc nulls last, q.id) as rn
            from (select p.id, p.username, p.avatar, p.street_cred, p.last_seen, p.location_id, p.travel_to
                    from profiles p
                   where p.love_open and not p.banned and p.home_chosen and p.id <> v_uid
                     and p.created_at <= v_now - make_interval(days => v_min)
                     and (v_f = 'all'
                          or (v_f = 'here' and p.location_id = v_me.location_id and p.travel_to is null and v_me.travel_to is null)
                          or (v_f = 'online' and p.last_seen > v_now - make_interval(secs => (v_onl * 60)::double precision)))
                     and not bl_social_blocked(v_uid, p.id)
                     and bl_love_partner_count(p.id) < v_max
                   order by p.last_seen desc nulls last, p.id
                   offset v_off limit v_size + 1) q) x;
  return jsonb_build_object('enabled', true, 'rows', v_rows, 'has_more', v_n > v_size, 'filter', v_f, 'offset', v_off, 'page', v_size);
end $$;

-- Ask somebody out.
create or replace function public.love_ask(p_target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  t       profiles;
  v_now   timestamptz := bl_now();
  v_min   int := bl_love_num('love.min_account_days', 2)::int;
  v_blk   jsonb;
  v_id    bigint;
  v_exp   timestamptz;
  v_left  int;
begin
  if p_target is null or p_target = v_me.id then
    raise exception 'You can''t ask yourself out. Pick another player.' using errcode = 'P0001', hint = 'self';
  end if;
  v_blk := bl_love_ask_block(v_me);
  if v_blk is not null then
    raise exception '%', v_blk->>'msg' using errcode = 'P0001', hint = v_blk->>'code';
  end if;
  select * into t from profiles where id = p_target and not banned and home_chosen;
  if not found then
    raise exception 'That player is not around.' using errcode = 'P0001', hint = 'unknown_player';
  end if;
  if not t.love_open or t.created_at > v_now - make_interval(days => v_min) then
    raise exception '@% is not open to link-ups.', t.username using errcode = 'P0001', hint = 'target_closed';
  end if;
  if bl_social_blocked(v_me.id, t.id) then
    raise exception 'You can''t ask @% out.', t.username using errcode = 'P0001', hint = 'blocked';
  end if;
  if bl_love_partner_count(t.id) >= bl_love_num('love.max_partners', 1)::int then
    raise exception '@% can''t be asked out right now.', t.username using errcode = 'P0001', hint = 'unavailable';
  end if;
  if exists (select 1 from love_relationships r where r.status <> 'ended' and r.user_a = least(v_me.id, t.id) and r.user_b = greatest(v_me.id, t.id)) then
    raise exception 'You two are already together.' using errcode = 'P0001', hint = 'already_together';
  end if;
  -- stale pending asks end here (lazy expiry)
  update love_asks set status = 'expired', responded_at = v_now
   where status = 'pending' and expires_at <= v_now and ((from_user = v_me.id and to_user = t.id) or (from_user = t.id and to_user = v_me.id));
  if exists (select 1 from love_asks a where a.from_user = t.id and a.to_user = v_me.id and a.status = 'pending') then
    raise exception '@% already asked you. Check your incoming asks.', t.username using errcode = 'P0001', hint = 'they_asked';
  end if;
  if exists (select 1 from love_asks a where a.from_user = v_me.id and a.to_user = t.id and a.status = 'pending') then
    raise exception 'You already asked @%. Wait for a reply.', t.username using errcode = 'P0001', hint = 'already_asked';
  end if;
  if exists (select 1 from love_asks a where a.from_user = v_me.id and a.to_user = t.id and a.status = 'declined'
                and a.responded_at > v_now - make_interval(days => bl_love_num('love.decline_cooldown_days', 3)::int))
     or exists (select 1 from love_relationships r where r.status = 'ended' and r.user_a = least(v_me.id, t.id) and r.user_b = greatest(v_me.id, t.id)
                  and r.ended_at > v_now - make_interval(days => bl_love_num('love.breakup_cooldown_days', 3)::int)) then
    raise exception 'You can ask @% again later.', t.username using errcode = 'P0001', hint = 'later';
  end if;
  v_exp := v_now + make_interval(hours => bl_love_num('love.ask_expire_hours', 48)::int);
  insert into love_asks (from_user, to_user, status, created_at, expires_at) values (v_me.id, t.id, 'pending', v_now, v_exp) returning id into v_id;
  perform bl_love_notify(t.id, 'love_ask', '💞 @' || v_me.username || ' wants to link up', 'Open Family to say yes or no. No rush, they will wait.',
                         '/play?go=family:linkups', v_me.id, jsonb_build_object('ask', v_id, 'from', v_me.id));
  select greatest(0, bl_love_num('love.asks_per_day', 5)::int - count(*)::int) into v_left from love_asks a where a.from_user = v_me.id and a.created_at > v_now - interval '24 hours';
  return jsonb_build_object('message', 'Ask sent to @' || t.username || '. They have ' || bl_love_num('love.ask_expire_hours', 48)::int || ' hours to reply.',
                            'ask_id', v_id, 'asks_left', v_left);
end $$;

-- Accept or decline an ask. Declining is silent: the asker just sees "No reply".
create or replace function public.love_respond(p_ask bigint, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  a      love_asks;
  f      profiles;
  v_now  timestamptz := bl_now();
  v_max  int := bl_love_num('love.max_partners', 1)::int;
  v_rid  bigint;
  u      uuid;
begin
  select * into a from love_asks where id = p_ask and to_user = v_me.id for update;
  if not found then
    raise exception 'That ask is not there any more.' using errcode = 'P0001', hint = 'no_ask';
  end if;
  if a.status <> 'pending' then
    raise exception 'That ask has been answered already.' using errcode = 'P0001', hint = 'answered';
  end if;
  if a.expires_at <= v_now then
    update love_asks set status = 'expired', responded_at = v_now where id = a.id;
    -- the expiry must stick, so answer with a result and not an exception
    return jsonb_build_object('message', 'That ask has expired.', 'expired', true, 'accepted', false);
  end if;
  if not coalesce(p_accept, false) then
    update love_asks set status = 'declined', responded_at = v_now where id = a.id;
    return jsonb_build_object('message', 'Declined. They will not be told.', 'accepted', false);
  end if;
  if not bl_love_on() then
    raise exception 'Family and love is switched off for now.' using errcode = 'P0001', hint = 'off';
  end if;
  select * into f from profiles where id = a.from_user and not banned;
  if not found then
    update love_asks set status = 'expired', responded_at = v_now where id = a.id;
    return jsonb_build_object('message', 'That player is not around any more.', 'expired', true, 'accepted', false);
  end if;
  if bl_love_partner_count(v_me.id) >= v_max then
    raise exception 'You are already with somebody. End that first.' using errcode = 'P0001', hint = 'taken';
  end if;
  if bl_love_partner_count(f.id) >= v_max or bl_social_blocked(v_me.id, f.id) then
    update love_asks set status = 'expired', responded_at = v_now where id = a.id;
    return jsonb_build_object('message', '@' || f.username || ' is not available any more.', 'expired', true, 'accepted', false);
  end if;
  begin
    insert into love_relationships (user_a, user_b, asked_by, status, level, started_at, last_activity_at)
    values (least(v_me.id, f.id), greatest(v_me.id, f.id), f.id, 'talking', 0, v_now, v_now) returning id into v_rid;
  exception when unique_violation then
    raise exception 'You two are already together.' using errcode = 'P0001', hint = 'already_together';
  end;
  update love_asks set status = 'accepted', responded_at = v_now, relationship_id = v_rid where id = a.id;
  insert into love_log (rel_id, kind, actor_id, text, icon, points, day, created_at)
  values (v_rid, 'started', v_me.id, 'You started talking', '💬', 0, bl_love_day(), v_now);
  -- anybody now at their limit has no other open asks
  foreach u in array array[v_me.id, f.id] loop
    if bl_love_partner_count(u) >= v_max then
      update love_asks set status = 'expired', responded_at = v_now where status = 'pending' and (from_user = u or to_user = u);
    end if;
  end loop;
  perform bl_love_notify(f.id, 'love_accept', '💞 @' || v_me.username || ' said yes!', 'You two are talking now. Send a flirt in Family to build the bond.',
                         '/play?go=family:us', v_me.id, jsonb_build_object('rel', v_rid, 'partner', v_me.id));
  return jsonb_build_object('message', 'You and @' || f.username || ' are talking now. Send a flirt to build the bond.', 'accepted', true, 'rel', v_rid);
end $$;

-- Take back an ask I sent.
create or replace function public.love_withdraw(p_ask bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); n int;
begin
  update love_asks set status = 'withdrawn', responded_at = bl_now() where id = p_ask and from_user = v_uid and status = 'pending';
  get diagnostics n = row_count;
  if n = 0 then
    raise exception 'That ask is not waiting any more.' using errcode = 'P0001', hint = 'no_ask';
  end if;
  return jsonb_build_object('message', 'Ask withdrawn.');
end $$;

-- Send a preset flirt. Pays its price (a sink), adds points, may flip the pair to couple.
create or replace function public.love_flirt(p_rel bigint, p_flirt text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  r       love_relationships;
  fl      love_flirts;
  v_other uuid;
  v_last  timestamptz;
  v_cd    numeric := bl_love_num('love.flirt_cooldown_minutes', 20);
  v_wait  numeric;
  v_room  int;
  v_g     jsonb;
  v_msg   text;
begin
  if not bl_love_on() then
    raise exception 'Family and love is switched off for now.' using errcode = 'P0001', hint = 'off';
  end if;
  r := bl_love_lock_rel(v_me.id, p_rel);
  v_other := case when r.user_a = v_me.id then r.user_b else r.user_a end;
  select * into fl from love_flirts where id = p_flirt and active;
  if not found then
    raise exception 'Pick a line from the menu.' using errcode = 'P0001', hint = 'no_flirt';
  end if;
  if r.level < fl.min_level then
    raise exception 'That line unlocks at level %. You two are at %.', fl.min_level, r.level using errcode = 'P0001', hint = 'locked';
  end if;
  select max(created_at) into v_last from love_log where rel_id = r.id and kind = 'flirt' and actor_id = v_me.id;
  if v_last is not null then
    v_wait := extract(epoch from (v_last + make_interval(secs => (v_cd * 60)::double precision) - bl_now()));
    if v_wait > 0 then
      raise exception 'Easy now. You can flirt again in %.', bl_love_wait_text(v_wait) using errcode = 'P0001', hint = 'cooldown';
    end if;
  end if;
  v_room := greatest(0, bl_love_num('love.flirt_daily_cap', 20)::int - (select coalesce(sum(points), 0)::int from love_log where rel_id = r.id and day = bl_love_day()));
  if v_room <= 0 then
    raise exception 'You two have flirted enough for today. Come back tomorrow.' using errcode = 'P0001', hint = 'daily_cap';
  end if;
  if fl.cost > 0 then
    perform bl_sink_pay(v_me.id, fl.cost, 'love_flirt', jsonb_build_object('label', 'Flirt: ' || fl.icon || ' ' || left(fl.text, 40), 'rel', r.id, 'flirt', fl.id));
  end if;
  v_g := bl_love_gain(r, fl.points, 'flirt', v_me.id, fl.id, fl.text, fl.icon);
  perform bl_love_notify(v_other, 'love_flirt', fl.icon || ' @' || v_me.username || ': ' || fl.text, 'Reply from Family: Us.',
                         '/play?go=family:us', v_me.id, jsonb_build_object('rel', r.id, 'from', v_me.id, 'flirt', fl.id),
                         'love-' || r.id, '{n} new flirts for you');
  v_msg := case when (v_g->>'couple_now')::boolean then 'It worked. You are a couple now! 💞'
                when (v_g->>'capped')::boolean then 'Sent. Only +' || (v_g->>'gained') || ' today (daily limit).'
                else 'Sent. +' || (v_g->>'gained') || ' to your level.' end;
  return v_g || jsonb_build_object('message', v_msg, 'spent', fl.cost);
end $$;

-- Invite the partner on a date (be at its place).
create or replace function public.love_date_invite(p_date text, p_rel bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  r       love_relationships;
  d       love_dates;
  l       locations;
  v_other uuid;
  v_last  timestamptz;
  v_wait  numeric;
  v_id    bigint;
  v_exp   timestamptz;
  v_min   numeric := bl_love_num('love.date_invite_expire_minutes', 30);
begin
  if not bl_love_on() then
    raise exception 'Family and love is switched off for now.' using errcode = 'P0001', hint = 'off';
  end if;
  r := bl_love_lock_rel(v_me.id, p_rel);
  v_other := case when r.user_a = v_me.id then r.user_b else r.user_a end;
  select * into d from love_dates where id = p_date and active;
  if not found then
    raise exception 'That date is not on the list.' using errcode = 'P0001', hint = 'no_date';
  end if;
  if d.min_status = 'couple' and r.status <> 'couple' then
    raise exception 'That date is for couples. Keep flirting until you reach level %.', bl_love_num('love.couple_level', 30)::int using errcode = 'P0001', hint = 'couples_only';
  end if;
  if v_me.jailed_until is not null and v_me.jailed_until > bl_now() then
    raise exception 'You are in jail. No dates for now.' using errcode = 'P0001', hint = 'jailed';
  end if;
  if v_me.hospitalized_until is not null and v_me.hospitalized_until > bl_now() then
    raise exception 'You are in hospital. Rest first.' using errcode = 'P0001', hint = 'hospital';
  end if;
  if v_me.travel_to is not null then
    raise exception 'You are on the road. Arrive first.' using errcode = 'P0001', hint = 'travelling';
  end if;
  if d.place_id is not null and v_me.location_id is distinct from d.place_id then
    select * into l from locations where id = d.place_id;
    raise exception 'Go to % first, then invite.', l.name using errcode = 'P0001', hint = 'not_there';
  end if;
  if v_me.cash + greatest(v_me.bank, 0) < d.cost_each then
    raise exception 'Your money no reach for this date.' using errcode = 'P0001', hint = 'not_enough_money';
  end if;
  select max(created_at) into v_last from love_log where rel_id = r.id and kind = 'date' and ref_id = d.id;
  if v_last is not null then
    v_wait := extract(epoch from (v_last + make_interval(hours => d.cooldown_hours) - bl_now()));
    if v_wait > 0 then
      raise exception 'You two did that date recently. Again in %.', bl_love_wait_text(v_wait) using errcode = 'P0001', hint = 'cooldown';
    end if;
  end if;
  update love_date_invites set status = 'expired', responded_at = bl_now() where rel_id = r.id and status = 'pending' and expires_at <= bl_now();
  if exists (select 1 from love_date_invites where rel_id = r.id and status = 'pending') then
    raise exception 'A date invite is already waiting.' using errcode = 'P0001', hint = 'pending';
  end if;
  v_exp := bl_now() + make_interval(secs => (v_min * 60)::double precision);
  insert into love_date_invites (rel_id, date_id, from_user, to_user, status, created_at, expires_at)
  values (r.id, d.id, v_me.id, v_other, 'pending', bl_now(), v_exp) returning id into v_id;
  select * into l from locations where id = d.place_id;
  perform bl_love_notify(v_other, 'love_date_invite', d.icon || ' @' || v_me.username || ' invites you: ' || d.name,
                         case when d.place_id is null then 'Open Family to accept. It is on the phone.'
                              else 'Be at ' || l.name || ' and accept in Family within ' || v_min::int || ' min.' end,
                         '/play?go=family:us', v_me.id, jsonb_build_object('rel', r.id, 'invite', v_id, 'date', d.id, 'place', d.place_id));
  return jsonb_build_object('message', 'Invite sent. They have ' || v_min::int || ' minutes to accept.', 'invite_id', v_id, 'expires_at', v_exp);
end $$;

-- Accept or decline a date invite. Both must be at the place; both pay; both gain needs; the pair gains bond points.
create or replace function public.love_date_respond(p_invite bigint, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  i       love_date_invites;
  r       love_relationships;
  d       love_dates;
  o       profiles;
  l       locations;
  v_last  timestamptz;
  v_wait  numeric;
  v_g     jsonb;
  v_needs jsonb;
begin
  select * into i from love_date_invites where id = p_invite and to_user = v_me.id for update;
  if not found then
    raise exception 'That invite is not there any more.' using errcode = 'P0001', hint = 'no_invite';
  end if;
  if i.status <> 'pending' then
    raise exception 'That invite has been answered already.' using errcode = 'P0001', hint = 'answered';
  end if;
  if i.expires_at <= bl_now() then
    update love_date_invites set status = 'expired', responded_at = bl_now() where id = i.id;
    return jsonb_build_object('message', 'That invite has expired.', 'expired', true, 'accepted', false);
  end if;
  select * into o from profiles where id = i.from_user;
  if not coalesce(p_accept, false) then
    update love_date_invites set status = 'declined', responded_at = bl_now() where id = i.id;
    select * into d from love_dates where id = i.date_id;
    perform bl_love_notify(i.from_user, 'love_date', '@' || v_me.username || ' can''t make it today', coalesce(d.name, 'The date') || ' is off for now. Maybe another time.',
                           '/play?go=family:us', v_me.id, jsonb_build_object('rel', i.rel_id, 'invite', i.id, 'declined', true));
    return jsonb_build_object('message', 'Date declined.', 'accepted', false);
  end if;
  if not bl_love_on() then
    raise exception 'Family and love is switched off for now.' using errcode = 'P0001', hint = 'off';
  end if;
  select * into r from love_relationships where id = i.rel_id and status <> 'ended' for update;
  if not found then
    update love_date_invites set status = 'cancelled', responded_at = bl_now() where id = i.id;
    return jsonb_build_object('message', 'You two are not together any more.', 'expired', true, 'accepted', false);
  end if;
  r := bl_love_settle(r);
  select * into d from love_dates where id = i.date_id and active;
  if not found then
    raise exception 'That date is not on the list any more.' using errcode = 'P0001', hint = 'no_date';
  end if;
  if d.min_status = 'couple' and r.status <> 'couple' then
    raise exception 'That date is for couples only.' using errcode = 'P0001', hint = 'couples_only';
  end if;
  select max(created_at) into v_last from love_log where rel_id = r.id and kind = 'date' and ref_id = d.id;
  if v_last is not null then
    v_wait := extract(epoch from (v_last + make_interval(hours => d.cooldown_hours) - bl_now()));
    if v_wait > 0 then
      raise exception 'You two did that date recently. Again in %.', bl_love_wait_text(v_wait) using errcode = 'P0001', hint = 'cooldown';
    end if;
  end if;
  -- the partner row is locked while the money moves (all or nothing)
  select * into o from profiles where id = i.from_user for update;
  if v_me.jailed_until is not null and v_me.jailed_until > bl_now() or o.jailed_until is not null and o.jailed_until > bl_now() then
    raise exception 'One of you is in jail. No dates for now.' using errcode = 'P0001', hint = 'jailed';
  end if;
  if v_me.hospitalized_until is not null and v_me.hospitalized_until > bl_now() or o.hospitalized_until is not null and o.hospitalized_until > bl_now() then
    raise exception 'One of you is in hospital. Rest first.' using errcode = 'P0001', hint = 'hospital';
  end if;
  if v_me.travel_to is not null or o.travel_to is not null then
    raise exception 'One of you is still on the road.' using errcode = 'P0001', hint = 'travelling';
  end if;
  if d.place_id is not null then
    select * into l from locations where id = d.place_id;
    if v_me.location_id is distinct from d.place_id then
      raise exception 'Go to % first. You both have to be there.', l.name using errcode = 'P0001', hint = 'not_there';
    end if;
    if o.location_id is distinct from d.place_id then
      raise exception '@% is not at % yet. You both have to be there.', o.username, l.name using errcode = 'P0001', hint = 'partner_not_there';
    end if;
  end if;
  if v_me.cash + greatest(v_me.bank, 0) < d.cost_each then
    raise exception 'Your money no reach for this date (% each).', bl_naira(d.cost_each) using errcode = 'P0001', hint = 'not_enough_money';
  end if;
  if o.cash + greatest(o.bank, 0) < d.cost_each then
    raise exception '@% can''t cover their share of this date.', o.username using errcode = 'P0001', hint = 'partner_broke';
  end if;
  if d.cost_each > 0 then
    perform bl_sink_pay(v_me.id, d.cost_each, 'love_date', jsonb_build_object('label', 'Date: ' || d.icon || ' ' || d.name, 'rel', r.id, 'date', d.id));
    perform bl_sink_pay(o.id, d.cost_each, 'love_date', jsonb_build_object('label', 'Date: ' || d.icon || ' ' || d.name, 'rel', r.id, 'date', d.id));
  end if;
  v_needs := jsonb_build_object('fun', d.fun_gain, 'social', d.social_gain);
  perform bl_adjust_needs(v_me.id, v_needs);
  perform bl_adjust_needs(o.id, v_needs);
  v_g := bl_love_gain(r, d.bond_points, 'date', v_me.id, d.id, d.name, d.icon);
  update love_date_invites set status = 'accepted', responded_at = bl_now() where id = i.id;
  perform bl_love_notify(o.id, 'love_date', d.icon || ' You and @' || v_me.username || ': ' || d.name, 'Good time. Fun +' || d.fun_gain || ', Social +' || d.social_gain
                         || case when (v_g->>'gained')::int > 0 then ', bond +' || (v_g->>'gained') else '' end || '.',
                         '/play?go=family:us', v_me.id, jsonb_build_object('rel', r.id, 'date', d.id, 'quiet', false));
  return v_g || jsonb_build_object('message', d.icon || ' ' || d.name || ' with @' || o.username || '. Fun +' || d.fun_gain || ', Social +' || d.social_gain
                         || case when (v_g->>'gained')::int > 0 then ', bond +' || (v_g->>'gained') else ', bond capped for today' end
                         || case when (v_g->>'couple_now')::boolean then '. You are a couple now! 💞' else '.' end,
                         'accepted', true, 'spent', d.cost_each, 'fun', d.fun_gain, 'social', d.social_gain);
end $$;

-- End it. Either partner. History kept; both get cooldowns (enforced by love_ask).
create or replace function public.love_breakup(p_rel bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me_any();
  r       love_relationships;
  v_other uuid;
  v_name  text;
begin
  r := bl_love_lock_rel(v_me.id, p_rel);
  v_other := case when r.user_a = v_me.id then r.user_b else r.user_a end;
  update love_relationships set status = 'ended', ended_at = bl_now(), ended_by = v_me.id where id = r.id;
  update love_date_invites set status = 'cancelled', responded_at = bl_now() where rel_id = r.id and status = 'pending';
  insert into love_log (rel_id, kind, actor_id, text, icon, points, day, created_at)
  values (r.id, 'ended', v_me.id, 'It ended', '💔', 0, bl_love_day(), bl_now());
  select username into v_name from profiles where id = v_other;
  perform bl_love_notify(v_other, 'love_breakup', '@' || v_me.username || ' ended things', 'It happens. Take care of yourself and give your heart a little time.',
                         '/play?go=family:us', v_me.id, jsonb_build_object('rel', r.id, 'from', v_me.id));
  return jsonb_build_object('message', 'It is over with @' || coalesce(v_name, 'them') || '. Take care of yourself.', 'rel', r.id);
end $$;

-- Report a player you asked, were asked by, or are / were with. Reuse the chat block list for "block them".
create or replace function public.love_report(p_target uuid, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_why  text := left(bl_chat_clean(coalesce(p_reason, '')), 300);
  v_rel  bigint;
  v_name text;
begin
  select username into v_name from profiles where id = p_target;
  if p_target is null or p_target = v_uid or v_name is null then
    raise exception 'Pick a player to report.' using errcode = 'P0001', hint = 'bad_target';
  end if;
  if not exists (select 1 from love_asks a where (a.from_user = v_uid and a.to_user = p_target) or (a.from_user = p_target and a.to_user = v_uid))
     and not exists (select 1 from love_relationships r where r.user_a = least(v_uid, p_target) and r.user_b = greatest(v_uid, p_target)) then
    raise exception 'You can only report somebody you have linked up with.' using errcode = 'P0001', hint = 'no_link';
  end if;
  if exists (select 1 from love_reports where reporter_id = v_uid and reported_id = p_target and status = 'open') then
    raise exception 'You already reported @%. A moderator will look.', v_name using errcode = 'P0001', hint = 'already_reported';
  end if;
  if (select count(*) from love_reports where reporter_id = v_uid and created_at > bl_now() - interval '24 hours') >= bl_love_num('love.report_daily_cap', 5)::int then
    raise exception 'You have reported a lot today. A moderator will look at them.' using errcode = 'P0001', hint = 'report_cap';
  end if;
  select id into v_rel from love_relationships where user_a = least(v_uid, p_target) and user_b = greatest(v_uid, p_target) order by id desc limit 1;
  insert into love_reports (reporter_id, reported_id, rel_id, reason, created_at) values (v_uid, p_target, v_rel, v_why, bl_now());
  return jsonb_build_object('message', 'Thanks. A moderator will look at it.');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Admin
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_love_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard();
begin
  return jsonb_build_object(
    'enabled', bl_love_on(),
    'open_players', (select count(*) from profiles where love_open),
    'talking', (select count(*) from love_relationships where status = 'talking'),
    'couples', (select count(*) from love_relationships where status = 'couple'),
    'ended_7d', (select count(*) from love_relationships where status = 'ended' and ended_at > bl_now() - interval '7 days'),
    'pending_asks', (select count(*) from love_asks where status = 'pending' and expires_at > bl_now()),
    'open_reports', (select count(*) from love_reports where status = 'open'),
    'reports', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'status', x.status, 'reason', x.reason, 'created_at', x.created_at,
                 'reporter', jsonb_build_object('id', x.reporter_id, 'username', a.username),
                 'reported', jsonb_build_object('id', x.reported_id, 'username', b.username),
                 'rel_id', x.rel_id, 'rel_status', (select status from love_relationships where id = x.rel_id)) order by (x.status = 'open') desc, x.id desc)
                 from (select * from love_reports order by (status = 'open') desc, id desc limit 50) x
                 join profiles a on a.id = x.reporter_id join profiles b on b.id = x.reported_id), '[]'::jsonb));
end $$;

create or replace function public.admin_love_report_set(p_id bigint, p_status text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); n int; v_rep uuid;
begin
  if p_status not in ('reviewed', 'dismissed') then
    raise exception 'Use reviewed or dismissed.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  update love_reports set status = p_status, handled_by = v_admin, handled_at = bl_now() where id = p_id returning reported_id into v_rep;
  get diagnostics n = row_count;
  if n = 0 then
    raise exception 'That report is not there.' using errcode = 'P0001', hint = 'no_report';
  end if;
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'love_report_' || p_status, v_rep, jsonb_build_object('report', p_id));
  return jsonb_build_object('message', 'Report marked ' || p_status || '.');
end $$;

-- An admin ends a link-up (abuse). Audited; both are told, no cooldown change.
create or replace function public.admin_love_end(p_rel bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); r love_relationships;
begin
  select * into r from love_relationships where id = p_rel and status <> 'ended' for update;
  if not found then
    raise exception 'That link-up is not active.' using errcode = 'P0001', hint = 'no_relationship';
  end if;
  update love_relationships set status = 'ended', ended_at = bl_now(), ended_by = null where id = r.id;
  update love_date_invites set status = 'cancelled', responded_at = bl_now() where rel_id = r.id and status = 'pending';
  insert into love_log (rel_id, kind, actor_id, text, icon, points, day, created_at) values (r.id, 'ended', null, 'Ended by a moderator', '💔', 0, bl_love_day(), bl_now());
  perform bl_love_notify(r.user_a, 'love_breakup', 'Your link-up was ended by a moderator', 'If you think this is a mistake, use Feedback.', '/play?go=family:us', null, jsonb_build_object('rel', r.id));
  perform bl_love_notify(r.user_b, 'love_breakup', 'Your link-up was ended by a moderator', 'If you think this is a mistake, use Feedback.', '/play?go=family:us', null, jsonb_build_object('rel', r.id));
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'love_end', r.user_a, jsonb_build_object('rel', r.id, 'a', r.user_a, 'b', r.user_b, 'reason', left(coalesce(p_reason, ''), 200)));
  return jsonb_build_object('message', 'Link-up ended.');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Patches on live functions (guarded)
-- ---------------------------------------------------------------------------------------------
-- public profile: relationship ("With @name", only if the player allows it) and whether they are open to link-ups
select pg_temp.love_patch('public.get_public_profile(uuid)',
  $o$'donor', bl_donor_badge(id))$o$,
  $o$'donor', bl_donor_badge(id), 'relationship', bl_love_public(id), 'love_open', (love_open and bl_love_on()))$o$,
  $o$'relationship', bl_love_public(id)$o$);

-- ledger: labels, never earned, Admin -> Economy category
select pg_temp.love_patch('public.bl_ledger_label(text, jsonb)',
  $o$when 'topup' then$o$,
  $o$when 'love_flirt' then return coalesce(nullif(p_meta->>'label', ''), 'Flirt');
    when 'love_date' then return coalesce(nullif(p_meta->>'label', ''), 'Date');
    when 'topup' then$o$,
  $o$when 'love_flirt' then$o$);

select pg_temp.love_patch('public.bl_econ_category(text)',
  $o$'linkup', 'linkup_gone_wrong')$o$,
  $o$'linkup', 'linkup_gone_wrong', 'love_flirt', 'love_date')$o$,
  $o$'love_flirt', 'love_date')$o$);

select pg_temp.love_patch('public.bl_earn_reasons()',
  $o$'chief_title', 'godfather_ticket'])$o$,
  $o$'chief_title', 'godfather_ticket', 'love_flirt', 'love_date'])$o$,
  $o$'love_flirt', 'love_date'])$o$);

-- admin Content editor: Flirt lines and Dates
select pg_temp.love_patch('public.bl_admin_table_spec(text)',
  $o$when 'skill_sources' then$o$,
  E'when ''love_flirts'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"text":"text","icon":"text","points":"int","cost":"money","min_level":"int","sort":"int","active":"bool"}}''\n    when ''love_dates'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","icon":"text","place_id":"text_null","cost_each":"money","fun_gain":"int","social_gain":"int","bond_points":"int","cooldown_hours":"int","min_status":"text","sort":"int","active":"bool"}}''\n    when ''skill_sources'' then',
  $o$when 'love_flirts' then$o$);

-- ---------------------------------------------------------------------------------------------
-- 9. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and proname like 'bl\_love\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and (proname like 'love\_%' or proname like 'admin\_love\_%') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
end $$;

notify pgrst, 'reload schema';
