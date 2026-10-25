-- Family & Love, stage 2: kids (docs/LOVE.md, "Stage 2: kids"). A couple can try for a baby, expect it for a few real days, name it, and look
-- after it together until it grows up. Everything is server-authoritative, lazy and cheap:
--   * No cron per child. Each need is stored as value + timestamp and computed analytically on read (value - rate * elapsed, per life stage).
--   * kids_children.next_alert_at (indexed) is the moment the sweep should look at a child again: the first need crossing the alert level,
--     a birth, growing up, a name deadline, sickness or the relatives deadline. bl_kids_alert_sweep() takes at most kids.sweep_batch due rows
--     (for update skip locked) and is called from bl_push_tick(), the one scheduler the push pipeline already has (Edge Function player-push).
--   * Clients never touch the tables: RLS on, no grants. Every action is a security-definer RPC. Private helpers bl_kids_* are revoked.
-- Idempotent: tables `if not exists`, seeds `on conflict do nothing` (admin edits survive), functions `create or replace`, live functions patched
-- ONLY through a guarded replace on pg_get_functiondef (raises when the marker is missing, skips when already applied).

-- ---------------------------------------------------------------------------------------------
-- 0. Guarded patch helper (session only)
-- ---------------------------------------------------------------------------------------------
create or replace function pg_temp.kd_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'family_kids: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Kids)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('kids.enabled', 'true', 'kids', 'Kids on',
 'Master switch. Off = no new babies, no care actions, no alerts, and every child''s clock is frozen. When you switch it back on the clocks carry on from where they stopped (nobody is punished for the pause).', 'bool', null, null),
('kids.min_couple_days', '2', 'kids', 'Days as a couple before a baby',
 'A couple must have been a couple (not just talking) for this many real days before one of them can propose a baby.', 'number', 0, 365),
('kids.max_children_per_couple', '3', 'kids', 'Most children per couple',
 'How many children (expected, at home or with relatives) one couple can have at the same time. Grown-up children do not count.', 'number', 1, 10),
('kids.max_children_per_player', '5', 'kids', 'Most children per player',
 'How many children one player can look after at once, across all their partners. Grown-up children do not count.', 'number', 1, 20),
('kids.invite_expire_hours', '24', 'kids', 'A baby invite waits for (hours)',
 'The partner has this long to say yes. Both partners must agree.', 'number', 1, 720),
('kids.invite_cooldown_hours', '6', 'kids', 'Wait between baby invites (hours)',
 'After one partner proposes, the same partner cannot propose again for this long (stops nagging).', 'number', 0, 168),
('kids.try_cost_each', '5000', 'kids', 'Baby plans cost (each partner)',
 'Naira each partner pays when the invite is accepted. A money sink: the ledger reason kid_try is never counted as earnings.', 'naira', 0, 10000000),
('kids.pregnancy_days', '3', 'kids', 'Days of "expecting a baby"',
 'Real days between a yes and the baby arriving. The birth happens on its own at the due time (the next alert sweep or the first time a parent opens the app).', 'number', 0, 30),
('kids.name_grace_hours', '24', 'kids', 'Time to name the baby (hours)',
 'After the birth the parents have this long to name the baby. After that the game picks a name from Content -> Baby names.', 'number', 0, 720),
('kids.grow_days', '21', 'kids', 'Days until grown up',
 'Real days from birth until the child grows up and moves out. The parents get a Proud parent badge (cosmetic only: no money, no XP). The earlier stages (Baby, Toddler, Child, Teen) are in Content -> Child stages.', 'number', 1, 365),
('kids.start_need', '80', 'kids', 'Needs at birth (0-100)',
 'Every need (hunger, sleep, fun, health, love) starts here when the baby arrives.', 'number', 1, 100),
('kids.alert_below', '30', 'kids', 'Needs-attention level (0-100)',
 'A child "needs you" when any need falls under this. That is when the app shows "needs you!" and both parents get an alert.', 'number', 1, 100),
('kids.alert_cooldown_hours', '3', 'kids', 'Wait between alerts for one child (hours)',
 'The game alerts both parents about the same child at most once in this time.', 'number', 1, 72),
('kids.max_alerts_unanswered', '4', 'kids', 'Alerts before it goes quiet',
 'If nobody looks after the child, the game stops alerting after this many alerts in a row. The next care action starts the count again.', 'number', 1, 20),
('kids.quiet_enabled', 'false', 'kids', 'Quiet hours on',
 'On = no needs-attention alerts and pushes between the quiet hours below (Benin time). They are sent when the quiet hours end.', 'bool', null, null),
('kids.quiet_from_hour', '22', 'kids', 'Quiet hours start (hour, 0-23)',
 'First hour of the quiet period, in game clock time.', 'number', 0, 23),
('kids.quiet_to_hour', '6', 'kids', 'Quiet hours end (hour, 0-23)',
 'The hour the quiet period ends, in game clock time.', 'number', 0, 23),
('kids.sweep_batch', '200', 'kids', 'Children the alert sweep handles at once',
 'Each minute the sweep looks at most this many children whose time has come. Keeps the server light.', 'number', 10, 2000),
('kids.neglect_hours', '24', 'kids', 'Hours at zero before a child falls sick',
 'If any need stays at 0 this long, the child is sick. Medicine and a cuddle make them better.', 'number', 1, 720),
('kids.sick_grace_hours', '6', 'kids', 'Safe time after getting better (hours)',
 'After a child recovers they cannot fall sick again for this long, so the parents have time to feed and rest them.', 'number', 0, 168),
('kids.removal_days', '7', 'kids', 'Days of no care before relatives step in',
 'If neither parent does any care action for this many days, relatives take the child in for a while. No one is ever harmed.', 'number', 1, 90),
('kids.reclaim_cost', '10000', 'kids', 'Cost to bring a child home',
 'Naira the parent pays to bring the child back from relatives (once). A money sink: the ledger reason kid_reclaim is never earnings. A second time with relatives is for good.', 'naira', 0, 10000000),
('kids.reclaim_wait_hours', '12', 'kids', 'Wait before bringing a child home (hours)',
 'The child stays with relatives at least this long.', 'number', 0, 720),
('kids.reclaim_need', '60', 'kids', 'Needs when a child comes home (0-100)',
 'All needs are set to this when a parent brings the child back from relatives.', 'number', 1, 100),
('kids.care_max', '90', 'kids', 'Already fine at (0-100)',
 'A care action is refused (and costs nothing) when that need is already this high.', 'number', 1, 100),
('kids.medicine_below', '60', 'kids', 'Medicine works under health (0-100)',
 'Medicine only works when health is under this level or the child is sick.', 'number', 1, 100),
('kids.feed_restore', '50', 'kids', 'Feeding gives hunger',
 'Points of hunger one feeding restores.', 'number', 1, 100),
('kids.sleep_restore', '50', 'kids', 'Bedtime gives sleep',
 'Points of sleep one bedtime restores.', 'number', 1, 100),
('kids.play_restore', '40', 'kids', 'Playing gives fun',
 'Points of fun one play restores.', 'number', 1, 100),
('kids.medicine_restore', '60', 'kids', 'Medicine gives health',
 'Points of health one dose restores.', 'number', 1, 100),
('kids.cuddle_restore', '40', 'kids', 'A cuddle gives love',
 'Points of love one cuddle restores.', 'number', 1, 100),
('kids.feed_cost', '400', 'kids', 'Feeding cost',
 'Naira one feeding costs. A money sink (ledger kid_care), never earnings. 0 = free.', 'naira', 0, 1000000),
('kids.medicine_cost', '1500', 'kids', 'Medicine cost',
 'Naira one dose of medicine costs. A money sink (ledger kid_care), never earnings. 0 = free.', 'naira', 0, 1000000),
('kids.feed_cooldown_minutes', '10', 'kids', 'Wait between feedings (minutes)',
 'Per child, shared by both parents.', 'minutes', 0, 1440),
('kids.sleep_cooldown_minutes', '30', 'kids', 'Wait between bedtimes (minutes)',
 'Per child, shared by both parents. Free, so it takes presence.', 'minutes', 0, 1440),
('kids.play_cooldown_minutes', '30', 'kids', 'Wait between play times (minutes)',
 'Per child, shared by both parents. Free, so it takes presence.', 'minutes', 0, 1440),
('kids.medicine_cooldown_minutes', '60', 'kids', 'Wait between medicine doses (minutes)',
 'Per child, shared by both parents.', 'minutes', 0, 1440),
('kids.cuddle_cooldown_minutes', '30', 'kids', 'Wait between cuddles (minutes)',
 'Per child, shared by both parents. Free, so it takes presence.', 'minutes', 0, 1440),
('kids.poll_seconds', '45', 'kids', 'Family app refresh for kids (seconds)',
 'How often the open phone asks the server about the children (for the red dot and the needs bars). It never polls while the phone is closed, the tab is hidden or the player is away.', 'number', 20, 300)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
-- Life stages (Content -> Child stages). rate_* = need points lost per real hour while the child is in that stage.
create table if not exists public.kids_stages (
  id          text primary key,
  name        text not null check (char_length(name) between 2 and 24),
  emoji       text not null default '👶' check (char_length(emoji) between 1 and 8),
  from_days   integer not null default 0 check (from_days between 0 and 365),
  rate_hunger numeric not null default 2 check (rate_hunger between 0 and 50),
  rate_sleep  numeric not null default 1.5 check (rate_sleep between 0 and 50),
  rate_fun    numeric not null default 1.5 check (rate_fun between 0 and 50),
  rate_health numeric not null default 0.4 check (rate_health between 0 and 50),
  rate_love   numeric not null default 1.5 check (rate_love between 0 and 50),
  sort        integer not null default 0,
  active      boolean not null default true
);

-- The names the game picks when nobody names the baby in time (Content -> Baby names).
create table if not exists public.kids_auto_names (
  name   text primary key check (name ~ '^[[:alpha:]]{3,16}$'),
  active boolean not null default true
);

-- One row per baby: status 'expecting' is the pregnancy (same id becomes the child's id on birth).
create table if not exists public.kids_children (
  id               bigserial primary key,
  rel_id           bigint references public.love_relationships(id) on delete set null,
  parent_a         uuid references public.profiles(id) on delete set null,
  parent_b         uuid references public.profiles(id) on delete set null,
  proposed_by      uuid,
  status           text not null default 'expecting' check (status in ('expecting', 'home', 'with_relatives', 'grown', 'gone')),
  gone_reason      text check (gone_reason in ('relatives', 'admin', 'no_parents', 'cancelled')),
  name             text check (name is null or name ~ '^[[:alpha:]]{3,16}$'),
  gender           text check (gender in ('boy', 'girl')),
  named_by         uuid,
  auto_named       boolean not null default false,
  conceived_at     timestamptz not null default now(),
  due_at           timestamptz not null,
  born_at          timestamptz,
  grown_at         timestamptz,
  hunger           numeric not null default 80 check (hunger between 0 and 100),
  hunger_at        timestamptz,
  sleep            numeric not null default 80 check (sleep between 0 and 100),
  sleep_at         timestamptz,
  fun              numeric not null default 80 check (fun between 0 and 100),
  fun_at           timestamptz,
  health           numeric not null default 80 check (health between 0 and 100),
  health_at        timestamptz,
  love             numeric not null default 80 check (love between 0 and 100),
  love_at          timestamptz,
  last_care_at     timestamptz,
  last_alert_at    timestamptz,
  alerts_unanswered integer not null default 0 check (alerts_unanswered >= 0),
  next_alert_at    timestamptz,
  sick_since       timestamptz,
  sick_med         boolean not null default false,
  sick_cuddle      boolean not null default false,
  cured_at         timestamptz,
  removals         integer not null default 0 check (removals >= 0),
  reclaims         integer not null default 0 check (reclaims >= 0),
  relatives_at     timestamptz,
  created_at       timestamptz not null default now(),
  check (parent_a is null or parent_b is null or parent_a <> parent_b)
);
create index if not exists kids_children_a on public.kids_children (parent_a, status);
create index if not exists kids_children_b on public.kids_children (parent_b, status);
create index if not exists kids_children_rel on public.kids_children (rel_id) where rel_id is not null;
-- the sweep finds due children with this index: no scan
create index if not exists kids_children_due on public.kids_children (next_alert_at) where next_alert_at is not null;
-- one pregnancy at a time per couple
create unique index if not exists kids_one_expecting on public.kids_children (parent_a, parent_b) where status = 'expecting' and parent_a is not null and parent_b is not null;

create table if not exists public.kids_invites (
  id           bigserial primary key,
  rel_id       bigint not null references public.love_relationships(id) on delete cascade,
  from_user    uuid not null references public.profiles(id) on delete cascade,
  to_user      uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired', 'withdrawn', 'cancelled')),
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  responded_at timestamptz,
  child_id     bigint references public.kids_children(id) on delete set null,
  check (from_user <> to_user)
);
create unique index if not exists kids_invites_one_pending on public.kids_invites (rel_id) where status = 'pending';
create index if not exists kids_invites_to on public.kids_invites (to_user, created_at desc);
create index if not exists kids_invites_from on public.kids_invites (from_user, created_at desc);

-- Who looked after the child, and when (both parents see each other's care).
create table if not exists public.kids_care_log (
  id         bigserial primary key,
  child_id   bigint not null references public.kids_children(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete set null,
  action     text not null check (action in ('feed', 'sleep', 'play', 'medicine', 'cuddle')),
  cost       bigint not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists kids_care_child on public.kids_care_log (child_id, id desc);
create index if not exists kids_care_child_action on public.kids_care_log (child_id, action, id desc);

-- When the kill switch is off, the time it went off (clocks are shifted by the pause when it comes back).
create table if not exists public.kids_pause (
  id        integer primary key default 1 check (id = 1),
  paused_at timestamptz
);

do $$
declare t text;
begin
  foreach t in array array['kids_stages', 'kids_auto_names', 'kids_children', 'kids_invites', 'kids_care_log', 'kids_pause'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
  revoke all on sequence public.kids_children_id_seq, public.kids_invites_id_seq, public.kids_care_log_id_seq from public, anon, authenticated;
end $$;

-- Admin-edited text goes through the chat banned-words list.
create or replace function public.bl_kids_text_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'kids_auto_names' then
    if bl_chat_mask(new.name) <> new.name then
      raise exception 'Keep the name clean: it has a banned word.' using errcode = 'P0001', hint = 'blocked_text';
    end if;
  else
    if bl_chat_mask(new.name) <> new.name then
      raise exception 'Keep the stage name clean: it has a banned word.' using errcode = 'P0001', hint = 'blocked_text';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists kids_names_guard on public.kids_auto_names;
create trigger kids_names_guard before insert or update of name on public.kids_auto_names for each row execute function public.bl_kids_text_guard();
drop trigger if exists kids_stages_guard on public.kids_stages;
create trigger kids_stages_guard before insert or update of name on public.kids_stages for each row execute function public.bl_kids_text_guard();

-- ---------------------------------------------------------------------------------------------
-- 3. Seeds
-- ---------------------------------------------------------------------------------------------
insert into public.kids_stages (id, name, emoji, from_days, rate_hunger, rate_sleep, rate_fun, rate_health, rate_love, sort) values
('baby',    'Baby',    '👶', 0,  3.0, 2.0, 1.5, 0.5, 2.0, 10),
('toddler', 'Toddler', '🧒', 3,  2.5, 1.8, 2.0, 0.4, 1.6, 20),
('child',   'Child',   '🧒', 8,  2.0, 1.5, 2.0, 0.3, 1.2, 30),
('teen',    'Teen',    '🧑', 14, 1.5, 1.2, 1.8, 0.3, 1.0, 40)
on conflict (id) do nothing;

insert into public.kids_auto_names (name) values
('Osaze'), ('Eghosa'), ('Osasu'), ('Osas'), ('Ehizele'), ('Efosa'), ('Ewemade'), ('Idia'), ('Itohan'), ('Ize'), ('Uyi'), ('Aisosa'),
('Nosa'), ('Ehi'), ('Oghogho'), ('Osagie'), ('Esosa'), ('Izoduwa'), ('Omosede'), ('Eseosa'), ('Ogie'), ('Ewaen'), ('Osayi'), ('Iyobosa')
on conflict (name) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers (revoked from clients at the end)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(bl_cfg_bool('kids.enabled'), true)
$$;

-- new babies need kids AND love (existing families are kept when love is off, like couples)
create or replace function public.bl_kids_can_start() returns boolean
language sql stable security definer set search_path = public as $$
  select bl_kids_on() and bl_love_on()
$$;

create or replace function public.bl_kids_needs() returns text[]
language sql immutable set search_path = public as $$
  select array['hunger', 'sleep', 'fun', 'health', 'love']
$$;

-- needs-attention wording
create or replace function public.bl_kids_reason(p_need text) returns text
language sql immutable set search_path = public as $$
  select case p_need when 'hunger' then 'hungry' when 'sleep' then 'sleepy' when 'fun' then 'bored' when 'health' then 'unwell' else 'wanting a cuddle' end
$$;

create or replace function public.bl_kids_label(c public.kids_children) returns text
language sql immutable set search_path = public as $$
  select coalesce(c.name, 'Your baby')
$$;

-- Total points the need loses between t0 and t1, summing each life stage's rate over the time spent in it.
create or replace function public.bl_kids_drain(c public.kids_children, p_need text, t0 timestamptz, t1 timestamptz) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare s record; v_total numeric := 0; v_a timestamptz; v_b timestamptz;
begin
  if t0 is null or t1 <= t0 or c.born_at is null then return 0; end if;
  for s in
    select row_number() over (order by k.from_days) as rn, k.from_days, lead(k.from_days) over (order by k.from_days) as nxt,
           coalesce((to_jsonb(k) ->> ('rate_' || p_need))::numeric, 0) as rate
      from kids_stages k where k.active order by k.from_days
  loop
    v_a := case when s.rn = 1 then t0 else greatest(t0, c.born_at + s.from_days * interval '1 day') end;
    v_b := case when s.nxt is null then t1 else least(t1, c.born_at + s.nxt * interval '1 day') end;
    if v_b > v_a then v_total := v_total + s.rate * extract(epoch from (v_b - v_a)) / 3600; end if;
  end loop;
  return v_total;
end $$;

-- The need now (0-100), computed from its stored value and time. Nothing is written.
create or replace function public.bl_kids_val(c public.kids_children, p_need text, p_at timestamptz default null) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare v numeric := (to_jsonb(c) ->> p_need)::numeric; t0 timestamptz := (to_jsonb(c) ->> (p_need || '_at'))::timestamptz;
begin
  if c.status not in ('home', 'with_relatives') or t0 is null then return v; end if;
  return greatest(0, least(100, v - bl_kids_drain(c, p_need, t0, coalesce(p_at, bl_now()))));
end $$;

-- When the need falls under p_level (strictly: one second after it touches the level). Null = never. The stored value alone decides this.
create or replace function public.bl_kids_cross(c public.kids_children, p_need text, p_level numeric) returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare
  v numeric := (to_jsonb(c) ->> p_need)::numeric; t0 timestamptz := (to_jsonb(c) ->> (p_need || '_at'))::timestamptz;
  v_rem numeric; s record; v_a timestamptz; v_b timestamptz; v_cap numeric;
begin
  if t0 is null or c.born_at is null then return null; end if;
  if v < p_level then return t0; end if;
  v_rem := v - p_level;
  for s in
    select row_number() over (order by k.from_days) as rn, k.from_days, lead(k.from_days) over (order by k.from_days) as nxt,
           coalesce((to_jsonb(k) ->> ('rate_' || p_need))::numeric, 0) as rate
      from kids_stages k where k.active order by k.from_days
  loop
    v_a := case when s.rn = 1 then t0 else greatest(t0, c.born_at + s.from_days * interval '1 day') end;
    v_b := case when s.nxt is null then 'infinity'::timestamptz else c.born_at + s.nxt * interval '1 day' end;
    if v_b <= v_a or s.rate <= 0 then continue; end if;
    if v_b = 'infinity'::timestamptz then
      return v_a + ((v_rem / s.rate)::double precision) * interval '1 hour' + interval '1 second';
    end if;
    v_cap := s.rate * extract(epoch from (v_b - v_a)) / 3600;
    if v_cap >= v_rem then
      return v_a + ((v_rem / s.rate)::double precision) * interval '1 hour' + interval '1 second';
    end if;
    v_rem := v_rem - v_cap;
  end loop;
  return null;
end $$;

-- Needs that are under the alert level right now (lowest first); a sick child always counts as unwell.
create or replace function public.bl_kids_needy(c public.kids_children, p_at timestamptz default null) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare n text; v numeric; v_lvl numeric := bl_love_num('kids.alert_below', 30); v_out text[] := '{}'; v_rows jsonb := '[]'::jsonb;
begin
  if c.status <> 'home' then return v_out; end if;
  foreach n in array bl_kids_needs() loop
    v := bl_kids_val(c, n, p_at);
    if v < v_lvl then v_rows := v_rows || jsonb_build_object('n', n, 'v', v); end if;
  end loop;
  if c.sick_since is not null and not exists (select 1 from jsonb_array_elements(v_rows) x where x ->> 'n' = 'health') then
    v_rows := v_rows || jsonb_build_object('n', 'health', 'v', 0);
  end if;
  select coalesce(array_agg(x ->> 'n' order by (x ->> 'v')::numeric, x ->> 'n'), '{}') into v_out from jsonb_array_elements(v_rows) x;
  return v_out;
end $$;

-- When a healthy child will fall sick (a need at 0 for kids.neglect_hours). Null when already sick or never.
create or replace function public.bl_kids_sick_at(c public.kids_children) returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare n text; t timestamptz; v_best timestamptz;
begin
  if c.status <> 'home' or c.sick_since is not null then return null; end if;
  foreach n in array bl_kids_needs() loop
    t := bl_kids_cross(c, n, 0);
    if t is not null and (v_best is null or t < v_best) then v_best := t; end if;
  end loop;
  if v_best is null then return null; end if;
  v_best := v_best + make_interval(secs => (bl_love_num('kids.neglect_hours', 24) * 3600)::double precision);
  if c.cured_at is not null then
    v_best := greatest(v_best, c.cured_at + make_interval(secs => (bl_love_num('kids.sick_grace_hours', 6) * 3600)::double precision));
  end if;
  return v_best;
end $$;

-- Quiet hours (Benin clock): an alert time inside them moves to the moment they end.
create or replace function public.bl_kids_quiet_shift(p_at timestamptz) returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare v_tz text := bl_clock_tz(); v_from int := bl_love_num('kids.quiet_from_hour', 22)::int; v_to int := bl_love_num('kids.quiet_to_hour', 6)::int;
        v_l timestamp; v_h int; v_in boolean; v_end timestamp;
begin
  if not coalesce(bl_cfg_bool('kids.quiet_enabled'), false) or v_from = v_to then return p_at; end if;
  v_l := p_at at time zone v_tz;
  v_h := extract(hour from v_l)::int;
  v_in := case when v_from < v_to then v_h >= v_from and v_h < v_to else v_h >= v_from or v_h < v_to end;
  if not v_in then return p_at; end if;
  v_end := date_trunc('day', v_l) + make_interval(hours => v_to);
  if v_end <= v_l then v_end := v_end + interval '1 day'; end if;
  return v_end at time zone v_tz;
end $$;

-- The next moment the sweep must look at this child (the next_alert_at column).
create or replace function public.bl_kids_next(c public.kids_children) returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare
  v_best timestamptz; v_t timestamptz; v_x timestamptz; n text;
  v_below numeric := bl_love_num('kids.alert_below', 30);
begin
  if c.status = 'expecting' then return c.due_at; end if;
  if c.status = 'with_relatives' then
    return case when c.name is null and c.born_at is not null then c.born_at + make_interval(hours => bl_love_num('kids.name_grace_hours', 24)::int) end;
  end if;
  if c.status <> 'home' then return null; end if;
  v_best := c.born_at + make_interval(days => bl_love_num('kids.grow_days', 21)::int);
  v_best := least(v_best, c.last_care_at + make_interval(days => bl_love_num('kids.removal_days', 7)::int));
  v_best := least(v_best, bl_kids_sick_at(c));
  if c.name is null then v_best := least(v_best, c.born_at + make_interval(hours => bl_love_num('kids.name_grace_hours', 24)::int)); end if;
  if c.alerts_unanswered < bl_love_num('kids.max_alerts_unanswered', 4)::int then
    v_t := null;
    foreach n in array bl_kids_needs() loop
      v_x := bl_kids_cross(c, n, v_below);
      if v_x is not null and (v_t is null or v_x < v_t) then v_t := v_x; end if;
    end loop;
    if c.sick_since is not null then v_t := least(coalesce(v_t, c.sick_since), c.sick_since); end if;
    if v_t is not null then
      if c.last_alert_at is not null then
        v_t := greatest(v_t, c.last_alert_at + make_interval(secs => (bl_love_num('kids.alert_cooldown_hours', 3) * 3600)::double precision));
      end if;
      v_best := least(v_best, bl_kids_quiet_shift(v_t));
    end if;
  end if;
  return v_best;
end $$;

-- Alert + push (the existing 'friends' push category; one push per child and kind per hour at most).
create or replace function public.bl_kids_notify(p_to uuid, p_kind text, p_title text, p_body text, p_child bigint, p_data jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_to is null then return; end if;
  perform bl_event(p_to, p_kind, p_title, p_body, coalesce(p_data, '{}'::jsonb) || jsonb_build_object('child', p_child));
  perform bl_push_enqueue(p_to, 'friends', p_kind, p_title, p_body, '/play?go=family:family', null, null, null,
                          'kids:' || p_child || ':' || p_kind || ':' || floor(extract(epoch from bl_now()) / 3600)::bigint, false, null);
end $$;

create or replace function public.bl_kids_notify_both(c public.kids_children, p_kind text, p_title text, p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform bl_kids_notify(c.parent_a, p_kind, p_title, p_body, c.id);
  perform bl_kids_notify(c.parent_b, p_kind, p_title, p_body, c.id);
end $$;

-- Who may propose a baby: null = they can; {"code","msg"} = why not. `r` is the couple's row (settled).
create or replace function public.bl_kids_eligibility(r public.love_relationships) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_days numeric := bl_love_num('kids.min_couple_days', 2); v_since numeric; v_n int; u uuid; v_cap int;
begin
  if not bl_kids_can_start() then
    return jsonb_build_object('code', 'off', 'msg', 'Babies are resting for now. Check back soon.');
  end if;
  if r.status <> 'couple' then
    return jsonb_build_object('code', 'not_couple', 'msg', 'Only a couple can have a baby. Keep building your bond first.');
  end if;
  v_since := extract(epoch from (bl_now() - coalesce(r.couple_at, r.started_at))) / 86400;
  if v_since < v_days then
    return jsonb_build_object('code', 'too_soon', 'msg', 'You need to be a couple for ' || v_days::int || ' days first. About '
      || bl_love_wait_text((v_days - v_since) * 86400) || ' to go.');
  end if;
  if exists (select 1 from kids_children k where k.parent_a = r.user_a and k.parent_b = r.user_b and k.status = 'expecting') then
    return jsonb_build_object('code', 'expecting', 'msg', 'You are already expecting a little one.');
  end if;
  select count(*) into v_n from kids_children k where k.parent_a = r.user_a and k.parent_b = r.user_b and k.status in ('expecting', 'home', 'with_relatives');
  if v_n >= bl_love_num('kids.max_children_per_couple', 3)::int then
    return jsonb_build_object('code', 'pair_cap', 'msg', 'Your family is full for now: ' || v_n || ' children at the same time is the limit.');
  end if;
  v_cap := bl_love_num('kids.max_children_per_player', 5)::int;
  foreach u in array array[r.user_a, r.user_b] loop
    select (select count(*) from kids_children k where k.parent_a = u and k.status in ('expecting', 'home', 'with_relatives'))
         + (select count(*) from kids_children k where k.parent_b = u and k.status in ('expecting', 'home', 'with_relatives')) into v_n;
    if v_n >= v_cap then
      return jsonb_build_object('code', 'player_cap', 'msg', 'One of you already looks after ' || v_cap || ' children, which is the most for one person.');
    end if;
  end loop;
  return null;
end $$;

-- What a care action does right now for this child: {"ok","code","msg","wait","cost"}.
create or replace function public.bl_kids_can(c public.kids_children, p_action text, p_at timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_now timestamptz := coalesce(p_at, bl_now());
  v_need text := case p_action when 'feed' then 'hunger' when 'sleep' then 'sleep' when 'play' then 'fun' when 'medicine' then 'health' when 'cuddle' then 'love' end;
  v_cost bigint := case p_action when 'feed' then bl_love_num('kids.feed_cost', 400)::bigint when 'medicine' then bl_love_num('kids.medicine_cost', 1500)::bigint else 0 end;
  v_cd numeric := bl_love_num('kids.' || p_action || '_cooldown_minutes', 30) * 60;
  v_last timestamptz; v_wait numeric; v_val numeric; v_nm text := bl_kids_label(c);
begin
  if v_need is null then return jsonb_build_object('ok', false, 'code', 'bad_action', 'msg', 'Pick feed, sleep, play, medicine or cuddle.', 'wait', 0, 'cost', 0); end if;
  if c.status <> 'home' then
    return jsonb_build_object('ok', false, 'code', 'not_home', 'wait', 0, 'cost', v_cost,
      'msg', case c.status when 'expecting' then 'The baby has not arrived yet.' when 'with_relatives' then v_nm || ' is with relatives right now.'
                           when 'grown' then v_nm || ' has grown up and moved out.' else v_nm || ' is not here any more.' end);
  end if;
  select created_at into v_last from kids_care_log where child_id = c.id and action = p_action order by id desc limit 1;
  if v_last is not null then
    v_wait := extract(epoch from (v_last + make_interval(secs => v_cd::double precision) - v_now));
    if v_wait > 0 then
      return jsonb_build_object('ok', false, 'code', 'cooldown', 'wait', ceil(v_wait), 'cost', v_cost,
                                'msg', 'Easy. You can do that again in ' || bl_love_wait_text(v_wait) || '.');
    end if;
  end if;
  v_val := bl_kids_val(c, v_need, v_now);
  if p_action = 'medicine' then
    if c.sick_since is null and v_val >= bl_love_num('kids.medicine_below', 60) then
      return jsonb_build_object('ok', false, 'code', 'not_needed', 'wait', 0, 'cost', v_cost, 'msg', v_nm || ' is not unwell. Medicine is only for a child who needs it.');
    end if;
  elsif v_val >= bl_love_num('kids.care_max', 90) then
    return jsonb_build_object('ok', false, 'code', 'not_needed', 'wait', 0, 'cost', v_cost,
      'msg', v_nm || case p_action when 'feed' then ' is full for now.' when 'sleep' then ' is not sleepy now.' when 'play' then ' has had enough play for now.' else ' has had lots of love just now.' end);
  end if;
  return jsonb_build_object('ok', true, 'code', 'ok', 'wait', 0, 'cost', v_cost, 'msg', '');
end $$;

-- Apply everything whose time has come (birth, auto-name, sickness, relatives, growing up) in the order it happened. Locks the row.
-- Returns the row after the changes. Alerts are NOT sent here (bl_kids_process does that).
create or replace function public.bl_kids_settle(p_id bigint) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare
  c public.kids_children; v_now timestamptz := bl_now(); v_i int := 0;
  v_grow timestamptz; v_rem timestamptz; v_sick timestamptz; v_nm timestamptz; v_best timestamptz; v_kind text;
  v_start numeric := bl_love_num('kids.start_need', 80);
  v_pick text; v_nm_txt text; v_next timestamptz;
begin
  select * into c from kids_children where id = p_id for update;
  if not found then return null; end if;
  if not bl_kids_on() then return c; end if;
  loop
    v_i := v_i + 1;
    exit when v_i > 8;
    if c.status = 'expecting' then
      exit when c.due_at > v_now;
      update kids_children set status = 'home', born_at = v_now,
             hunger = v_start, hunger_at = v_now, sleep = v_start, sleep_at = v_now, fun = v_start, fun_at = v_now,
             health = v_start, health_at = v_now, love = v_start, love_at = v_now,
             last_care_at = v_now, last_alert_at = null, alerts_unanswered = 0
       where id = c.id returning * into c;
      perform bl_kids_notify_both(c, 'kids_born', 'Your baby is here! 👶', 'Come and name them. Open Family to meet your little one.');
      continue;
    elsif c.status = 'home' then
      v_grow := c.born_at + make_interval(days => bl_love_num('kids.grow_days', 21)::int);
      v_rem := c.last_care_at + make_interval(days => bl_love_num('kids.removal_days', 7)::int);
      v_sick := bl_kids_sick_at(c);
      v_nm := case when c.name is null then c.born_at + make_interval(hours => bl_love_num('kids.name_grace_hours', 24)::int) end;
    elsif c.status = 'with_relatives' then
      v_grow := null; v_rem := null; v_sick := null;
      v_nm := case when c.name is null then c.born_at + make_interval(hours => bl_love_num('kids.name_grace_hours', 24)::int) end;
    else
      exit;
    end if;
    -- the earliest thing that is due
    v_best := null; v_kind := null;
    if v_nm is not null and v_nm <= v_now then v_best := v_nm; v_kind := 'name'; end if;
    if v_sick is not null and v_sick <= v_now and (v_best is null or v_sick < v_best) then v_best := v_sick; v_kind := 'sick'; end if;
    if v_rem is not null and v_rem <= v_now and (v_best is null or v_rem < v_best) then v_best := v_rem; v_kind := 'removal'; end if;
    if v_grow is not null and v_grow <= v_now and (v_best is null or v_grow < v_best) then v_best := v_grow; v_kind := 'grow'; end if;
    exit when v_kind is null;

    if v_kind = 'name' then
      select n.name into v_pick from kids_auto_names n where n.active order by random() limit 1;
      v_pick := coalesce(v_pick, 'Osaze');
      update kids_children set name = v_pick, gender = case when random() < 0.5 then 'boy' else 'girl' end, auto_named = true, named_by = null
       where id = c.id and name is null returning * into c;
      perform bl_kids_notify_both(c, 'kids_named', '👶 Your baby is now called ' || v_pick,
                                  'Nobody picked a name in time, so the game chose one. Give ' || v_pick || ' lots of love.');
    elsif v_kind = 'sick' then
      update kids_children set sick_since = v_best, sick_med = false, sick_cuddle = false where id = c.id returning * into c;
      perform bl_kids_notify_both(c, 'kids_sick', '🤒 ' || bl_kids_label(c) || ' is unwell',
                                  'A need ran empty for too long. Give medicine and a cuddle to help them feel better.');
    elsif v_kind = 'removal' then
      v_nm_txt := bl_kids_label(c);
      if c.removals + 1 >= 2 then
        update kids_children set status = 'gone', gone_reason = 'relatives', removals = c.removals + 1, relatives_at = v_best, sick_since = null, next_alert_at = null
         where id = c.id returning * into c;
        perform bl_kids_notify_both(c, 'kids_gone', v_nm_txt || ' now lives with relatives 💛',
                                    'Nobody could look after them for a long time, so relatives are raising ' || v_nm_txt || ' for good. Take your time, and be there for any next little one.');
      else
        update kids_children set status = 'with_relatives', removals = c.removals + 1, relatives_at = v_best, sick_since = null, sick_med = false, sick_cuddle = false
         where id = c.id returning * into c;
        perform bl_kids_notify_both(c, 'kids_relatives', v_nm_txt || ' is staying with relatives for now 💛',
                                    'Nobody could look after them for ' || bl_love_num('kids.removal_days', 7)::int || ' days, so relatives took them in. You can bring ' || v_nm_txt || ' home from Family.');
      end if;
    else
      v_nm_txt := bl_kids_label(c);
      update kids_children set status = 'grown', grown_at = v_best, sick_since = null, next_alert_at = null where id = c.id returning * into c;
      perform bl_kids_notify_both(c, 'kids_grown', '🎓 ' || v_nm_txt || ' has grown up!',
                                  v_nm_txt || ' is moving out with a keepsake from you both. You are now a Proud parent 🏅');
    end if;
  end loop;
  v_next := bl_kids_next(c);
  if c.next_alert_at is distinct from v_next then
    update kids_children set next_alert_at = v_next where id = c.id returning * into c;
  end if;
  return c;
end $$;

-- Settle one child and, when asked, send the needs-attention alert to both parents. Used by the sweep.
create or replace function public.bl_kids_process(p_id bigint, p_alert boolean default true) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare
  c public.kids_children; v_now timestamptz := bl_now(); v_needy text[]; v_why text; v_next timestamptz;
  v_cd interval := make_interval(secs => (bl_love_num('kids.alert_cooldown_hours', 3) * 3600)::double precision);
begin
  c := bl_kids_settle(p_id);
  if c.id is null then return c; end if;
  if p_alert and c.status = 'home' and bl_kids_on() then
    v_needy := bl_kids_needy(c, v_now);
    if cardinality(v_needy) > 0
       and c.alerts_unanswered < bl_love_num('kids.max_alerts_unanswered', 4)::int
       and (c.last_alert_at is null or c.last_alert_at + v_cd <= v_now)
       and bl_kids_quiet_shift(v_now) = v_now then
      v_why := bl_kids_reason(v_needy[1]);
      perform bl_kids_notify_both(c, 'kids_needs', '🍼 ' || bl_kids_label(c) || ' needs attention: ' || v_why,
                                  'Go and take care of them.');
      update kids_children set last_alert_at = v_now, alerts_unanswered = alerts_unanswered + 1 where id = c.id returning * into c;
    end if;
  end if;
  v_next := bl_kids_next(c);
  if c.next_alert_at is distinct from v_next then
    update kids_children set next_alert_at = v_next where id = c.id returning * into c;
  end if;
  return c;
end $$;

-- THE SWEEP. Called from bl_push_tick() (about once a minute). Takes at most kids.sweep_batch children whose time has come
-- (index kids_children_due, for update skip locked: two sweeps never take the same child, nothing is scanned) and never raises.
create or replace function public.bl_kids_alert_sweep() returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_ids bigint[]; v_id bigint; v_n int := 0;
  v_batch int := greatest(1, bl_love_num('kids.sweep_batch', 200)::int);
begin
  if not bl_kids_on() then return 0; end if;
  select coalesce(array_agg(x.id), '{}') into v_ids from (
    select k.id from kids_children k where k.next_alert_at <= bl_now() order by k.next_alert_at limit v_batch for update skip locked
  ) x;
  foreach v_id in array v_ids loop
    begin
      perform bl_kids_process(v_id, true);
      v_n := v_n + 1;
    exception when others then
      null;   -- one bad row must not stop the others
    end;
  end loop;
  return v_n;
exception when others then
  return 0;
end $$;

-- A parent's proud-parent count for a public profile (only when they show their relationship).
create or replace function public.bl_kids_proud(p_uid uuid) returns integer
language sql stable security definer set search_path = public as $$
  select case when bl_kids_on() and exists (select 1 from profiles p where p.id = p_uid and p.show_relationship)
              then (select count(*) from kids_children k where k.parent_a = p_uid and k.status = 'grown')::int
                 + (select count(*) from kids_children k where k.parent_b = p_uid and k.status = 'grown')::int
              else 0 end
$$;

-- One child as the app shows it.
create or replace function public.bl_kids_child_json(c public.kids_children, p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_now timestamptz := bl_now(); v_age int; s public.kids_stages; v_needs jsonb := '{}'::jsonb; v_acts jsonb := '{}'::jsonb; n text; a text;
  v_other uuid := case when c.parent_a = p_uid then c.parent_b else c.parent_a end; v_pn text; v_pav jsonb; v_log jsonb; v_needy text[];
  v_can jsonb; v_cds jsonb := '{}'::jsonb; v_rel jsonb := null; v_grace timestamptz; v_removal timestamptz; v_wait numeric;
begin
  if c.born_at is not null then
    v_age := floor(extract(epoch from (v_now - c.born_at)) / 86400)::int;
    select * into s from kids_stages k where k.active and k.from_days <= v_age order by k.from_days desc limit 1;
    if not found then select * into s from kids_stages k where k.active order by k.from_days limit 1; end if;
  end if;
  if v_other is not null then select username, avatar into v_pn, v_pav from profiles where id = v_other; end if;
  if c.status in ('home', 'with_relatives') then
    foreach n in array bl_kids_needs() loop
      v_needs := v_needs || jsonb_build_object(n, floor(bl_kids_val(c, n, v_now))::int);
    end loop;
  end if;
  if c.status = 'home' then
    v_needy := bl_kids_needy(c, v_now);
    foreach a in array array['feed', 'sleep', 'play', 'medicine', 'cuddle'] loop
      v_can := bl_kids_can(c, a, v_now);
      v_acts := v_acts || jsonb_build_object(a, v_can);
    end loop;
    v_removal := c.last_care_at + make_interval(days => bl_love_num('kids.removal_days', 7)::int);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'action', g.action, 'mine', g.user_id = p_uid, 'who', coalesce(pr.username, 'a parent'), 'created_at', g.created_at) order by g.id desc), '[]'::jsonb)
    into v_log from (select * from kids_care_log where child_id = c.id order by id desc limit 8) g left join profiles pr on pr.id = g.user_id;
  if c.status = 'with_relatives' then
    v_wait := greatest(0, ceil(extract(epoch from (c.relatives_at + make_interval(hours => bl_love_num('kids.reclaim_wait_hours', 12)::int) - v_now))));
    v_rel := jsonb_build_object('since', c.relatives_at, 'removals', c.removals, 'can_reclaim', c.reclaims < 1 and v_wait <= 0, 'wait_seconds', v_wait,
                                'used', c.reclaims >= 1, 'cost', bl_love_num('kids.reclaim_cost', 10000)::bigint);
  end if;
  v_grace := case when c.name is null and c.born_at is not null then c.born_at + make_interval(hours => bl_love_num('kids.name_grace_hours', 24)::int) end;
  return jsonb_build_object(
    'id', c.id, 'rel_id', c.rel_id, 'status', c.status, 'name', c.name, 'gender', c.gender, 'auto_named', c.auto_named,
    'named_by_me', c.named_by = p_uid, 'name_due_at', v_grace,
    'conceived_at', c.conceived_at, 'due_at', c.due_at, 'born_at', c.born_at, 'grown_at', c.grown_at,
    'age_days', v_age, 'stage', case when s.id is null then null else jsonb_build_object('id', s.id, 'name', s.name, 'emoji', s.emoji) end,
    'needs', v_needs, 'needy', coalesce(to_jsonb(v_needy), '[]'::jsonb), 'sick', c.sick_since is not null,
    'sick_med', c.sick_med, 'sick_cuddle', c.sick_cuddle,
    'actions', v_acts, 'removal_at', v_removal,
    'partner', case when v_other is null then null else jsonb_build_object('id', v_other, 'username', v_pn, 'avatar', v_pav) end,
    'log', v_log, 'relatives', v_rel);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Triggers: a parent leaving (new life / deleted account), and the kill switch pause
-- ---------------------------------------------------------------------------------------------
-- A child never disappears with one parent: the other parent keeps them; with no parent left relatives take over.
create or replace function public.bl_kids_parent_left() returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.kids_children; v_other uuid;
begin
  for c in select * from kids_children k where (k.parent_a = old.id or k.parent_b = old.id) and k.status in ('expecting', 'home', 'with_relatives') for update loop
    v_other := case when c.parent_a = old.id then c.parent_b else c.parent_a end;
    if v_other is null then
      update kids_children set status = 'gone', gone_reason = 'no_parents', next_alert_at = null, parent_a = null, parent_b = null where id = c.id;
    elsif c.status = 'expecting' then
      update kids_children set status = 'gone', gone_reason = 'cancelled', next_alert_at = null, parent_a = null, parent_b = null where id = c.id;
      perform bl_kids_notify(v_other, 'kids_cancelled', 'Your baby plans are cancelled',
                             'The other parent started a new life, so the expected baby will not arrive. You can try again with somebody new, when you are ready.', c.id);
    else
      update kids_children set parent_a = case when parent_a = old.id then null else parent_a end,
                               parent_b = case when parent_b = old.id then null else parent_b end where id = c.id;
      perform bl_kids_notify(v_other, 'kids_handover', bl_kids_label(c) || ' is in your care now 💛',
                             'The other parent started a new life, so you are looking after ' || bl_kids_label(c) || ' on your own. They count on you.', c.id);
    end if;
  end loop;
  return old;
end $$;
drop trigger if exists kids_parent_left on public.profiles;
create trigger kids_parent_left before delete on public.profiles for each row execute function public.bl_kids_parent_left();

-- Kill switch: remember when it went off; when it comes back, push every running clock forward by the pause.
create or replace function public.bl_kids_switch() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_off boolean := not coalesce((new.value #>> '{}')::boolean, true); v_at timestamptz; v_d interval;
begin
  if v_off then
    insert into kids_pause (id, paused_at) values (1, bl_now()) on conflict (id) do update set paused_at = coalesce(kids_pause.paused_at, excluded.paused_at);
    return new;
  end if;
  select paused_at into v_at from kids_pause where id = 1;
  if v_at is null then return new; end if;
  v_d := greatest(interval '0', bl_now() - v_at);
  update kids_children set
    due_at = due_at + v_d, born_at = born_at + v_d, last_care_at = last_care_at + v_d, last_alert_at = last_alert_at + v_d,
    relatives_at = relatives_at + v_d, sick_since = sick_since + v_d, cured_at = cured_at + v_d,
    hunger_at = hunger_at + v_d, sleep_at = sleep_at + v_d, fun_at = fun_at + v_d, health_at = health_at + v_d, love_at = love_at + v_d,
    next_alert_at = next_alert_at + v_d
   where status in ('expecting', 'home', 'with_relatives');
  update kids_invites set expires_at = expires_at + v_d where status = 'pending';
  update kids_pause set paused_at = null where id = 1;
  return new;
end $$;
drop trigger if exists kids_switch on public.game_config;
create trigger kids_switch after update of value on public.game_config for each row
  when (new.key = 'kids.enabled' and new.value is distinct from old.value) execute function public.bl_kids_switch();

-- ---------------------------------------------------------------------------------------------
-- 6. Player RPCs
-- ---------------------------------------------------------------------------------------------
-- ONE cheap read for the app and the Family icon dot. Settles only MY children whose time has come (indexed, at most 20).
create or replace function public.kids_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_now  timestamptz := bl_now();
  c      public.kids_children;
  r      public.love_relationships;
  v_kids jsonb := '[]'::jsonb; v_cpl jsonb := '[]'::jsonb; v_in jsonb; v_out jsonb; v_grown jsonb; v_att int := 0; v_proud int;
  v_el jsonb; v_pid uuid; v_pn text; v_pav jsonb; v_j jsonb; v_cost bigint := bl_love_num('kids.try_cost_each', 5000)::bigint;
  v_days numeric := bl_love_num('kids.min_couple_days', 2); v_last timestamptz;
begin
  if not exists (select 1 from profiles where id = v_uid) then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if not bl_kids_on() then
    return jsonb_build_object('enabled', false, 'attention', 0, 'poll_seconds', 60, 'children', '[]'::jsonb, 'couples', '[]'::jsonb,
                              'incoming', '[]'::jsonb, 'outgoing', '[]'::jsonb, 'grown', '[]'::jsonb, 'proud', 0);
  end if;
  -- lazy: only my children whose clock has run out
  for c in
    select * from (
      select * from kids_children k where k.parent_a = v_uid and k.status in ('expecting', 'home', 'with_relatives') and k.next_alert_at <= v_now
      union all
      select * from kids_children k where k.parent_b = v_uid and k.status in ('expecting', 'home', 'with_relatives') and k.next_alert_at <= v_now
    ) x order by id limit 20
  loop
    perform bl_kids_settle(c.id);
  end loop;

  for c in
    select * from (
      select * from kids_children k where k.parent_a = v_uid and k.status in ('expecting', 'home', 'with_relatives')
      union all
      select * from kids_children k where k.parent_b = v_uid and k.status in ('expecting', 'home', 'with_relatives')
    ) x order by id limit 20
  loop
    v_j := bl_kids_child_json(c, v_uid);
    if jsonb_array_length(v_j -> 'needy') > 0 then v_att := v_att + 1; end if;
    if c.status = 'expecting' then
      v_j := v_j || jsonb_build_object('proposed_by_me', c.proposed_by = v_uid);
    end if;
    v_kids := v_kids || v_j;
  end loop;

  for r in select * from love_relationships l where l.status = 'couple' and (l.user_a = v_uid or l.user_b = v_uid) order by l.id limit 3 loop
    v_pid := case when r.user_a = v_uid then r.user_b else r.user_a end;
    select username, avatar into v_pn, v_pav from profiles where id = v_pid;
    v_el := bl_kids_eligibility(r);
    select max(i.created_at) into v_last from kids_invites i where i.rel_id = r.id and i.from_user = v_uid;
    v_cpl := v_cpl || jsonb_build_object(
      'rel_id', r.id, 'partner', jsonb_build_object('id', v_pid, 'username', v_pn, 'avatar', v_pav),
      'couple_days', floor(extract(epoch from (v_now - coalesce(r.couple_at, r.started_at))) / 86400)::int,
      'min_days', v_days, 'can_try', v_el is null, 'why', v_el,
      'invite_wait_seconds', case when v_last is null then 0 else greatest(0, ceil(extract(epoch from (v_last + make_interval(secs => (bl_love_num('kids.invite_cooldown_hours', 6) * 3600)::double precision) - v_now)))) end);
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'rel_id', i.rel_id, 'expires_at', i.expires_at,
           'from', jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar)) order by i.id desc), '[]'::jsonb) into v_in
    from (select * from kids_invites where to_user = v_uid and status = 'pending' and expires_at > v_now order by id desc limit 5) i
    join profiles p on p.id = i.from_user;
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'rel_id', i.rel_id, 'expires_at', i.expires_at,
           'state', case when i.status = 'pending' then 'pending' when i.status = 'declined' then 'declined' else 'noreply' end,
           'to', jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar)) order by i.id desc), '[]'::jsonb) into v_out
    from (select * from kids_invites
           where from_user = v_uid and ((status = 'pending' and expires_at > v_now) or (status in ('declined', 'expired') and created_at > v_now - interval '24 hours')
                                          or (status = 'pending' and expires_at <= v_now and created_at > v_now - interval '48 hours'))
           order by id desc limit 5) i
    join profiles p on p.id = i.to_user;
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'gender', g.gender, 'grown_at', g.grown_at) order by g.grown_at desc), '[]'::jsonb) into v_grown
    from (select * from (select * from kids_children k where k.parent_a = v_uid and k.status = 'grown'
                         union all select * from kids_children k where k.parent_b = v_uid and k.status = 'grown') y order by grown_at desc limit 10) g;
  select count(*) into v_proud from (select 1 from kids_children k where k.parent_a = v_uid and k.status = 'grown'
                                     union all select 1 from kids_children k where k.parent_b = v_uid and k.status = 'grown') z;

  return jsonb_build_object(
    'enabled', true, 'can_start', bl_kids_can_start(),
    'poll_seconds', greatest(20, bl_love_num('kids.poll_seconds', 45)),
    'attention', v_att, 'children', v_kids, 'couples', v_cpl, 'incoming', v_in, 'outgoing', v_out, 'grown', v_grown, 'proud', v_proud,
    'rules', jsonb_build_object(
      'try_cost_each', v_cost, 'pregnancy_days', bl_love_num('kids.pregnancy_days', 3), 'min_couple_days', v_days,
      'invite_expire_hours', bl_love_num('kids.invite_expire_hours', 24), 'grow_days', bl_love_num('kids.grow_days', 21),
      'alert_below', bl_love_num('kids.alert_below', 30), 'name_grace_hours', bl_love_num('kids.name_grace_hours', 24),
      'removal_days', bl_love_num('kids.removal_days', 7), 'neglect_hours', bl_love_num('kids.neglect_hours', 24),
      'reclaim_cost', bl_love_num('kids.reclaim_cost', 10000)::bigint, 'reclaim_wait_hours', bl_love_num('kids.reclaim_wait_hours', 12),
      'feed_cost', bl_love_num('kids.feed_cost', 400)::bigint, 'medicine_cost', bl_love_num('kids.medicine_cost', 1500)::bigint,
      'max_per_couple', bl_love_num('kids.max_children_per_couple', 3), 'max_per_player', bl_love_num('kids.max_children_per_player', 5)));
end $$;

-- Propose a baby to my partner (no money moves until they accept).
create or replace function public.kids_try(p_rel bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_now   timestamptz := bl_now();
  r       public.love_relationships;
  v_el    jsonb; v_other uuid; v_id bigint; v_last timestamptz; v_wait numeric; v_name text;
  v_cost  bigint := bl_love_num('kids.try_cost_each', 5000)::bigint;
begin
  if not bl_kids_can_start() then
    raise exception 'Babies are resting for now. Check back soon.' using errcode = 'P0001', hint = 'off';
  end if;
  r := bl_love_lock_rel(v_me.id, p_rel);
  v_other := case when r.user_a = v_me.id then r.user_b else r.user_a end;
  update kids_invites set status = 'expired', responded_at = v_now where rel_id = r.id and status = 'pending' and expires_at <= v_now;
  if exists (select 1 from kids_invites i where i.rel_id = r.id and i.status = 'pending') then
    raise exception 'A baby invite is already waiting for an answer.' using errcode = 'P0001', hint = 'already_asked';
  end if;
  v_el := bl_kids_eligibility(r);
  if v_el is not null then
    raise exception '%', v_el ->> 'msg' using errcode = 'P0001', hint = v_el ->> 'code';
  end if;
  select max(i.created_at) into v_last from kids_invites i where i.rel_id = r.id and i.from_user = v_me.id;
  if v_last is not null then
    v_wait := extract(epoch from (v_last + make_interval(secs => (bl_love_num('kids.invite_cooldown_hours', 6) * 3600)::double precision) - v_now));
    if v_wait > 0 then
      raise exception 'Give them a little time. You can ask again in %.', bl_love_wait_text(v_wait) using errcode = 'P0001', hint = 'cooldown';
    end if;
  end if;
  if v_cost > 0 and (select cash + greatest(bank, 0) from profiles where id = v_me.id) < v_cost then
    raise exception 'You need % for the baby plans, and you do not have it yet.', bl_naira(v_cost) using errcode = 'P0001', hint = 'not_enough_money';
  end if;
  insert into kids_invites (rel_id, from_user, to_user, status, created_at, expires_at)
  values (r.id, v_me.id, v_other, 'pending', v_now, v_now + make_interval(hours => bl_love_num('kids.invite_expire_hours', 24)::int)) returning id into v_id;
  perform bl_event(v_other, 'kids_invite', '🍼 @' || v_me.username || ' would like to try for a baby',
                   'Open Family to say yes or not yet. You both have to agree, and there is no rush.', jsonb_build_object('invite', v_id, 'from', v_me.id));
  perform bl_push_enqueue(v_other, 'friends', 'kids_invite', '🍼 @' || v_me.username || ' would like to try for a baby',
                          'Open Family to say yes or not yet.', '/play?go=family:family', v_me.id, null, null, 'kidsinv:' || v_id, false, null);
  select username into v_name from profiles where id = v_other;
  return jsonb_build_object('message', 'Asked @' || coalesce(v_name, 'your partner') || '. They have ' || bl_love_num('kids.invite_expire_hours', 24)::int || ' hours to answer. You each pay ' || bl_naira(v_cost) || ' if they say yes.',
                            'invite_id', v_id);
end $$;

-- Answer a baby invite. Yes: both pay, and the expecting timer starts. Not yet: the asker is told gently (status "declined").
create or replace function public.kids_accept(p_invite bigint, p_accept boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_now   timestamptz := bl_now();
  i       public.kids_invites;
  r       public.love_relationships;
  v_el    jsonb; v_cost bigint := bl_love_num('kids.try_cost_each', 5000)::bigint; v_cid bigint; v_due timestamptz; v_fname text;
begin
  select * into i from kids_invites where id = p_invite and to_user = v_me.id for update;
  if not found then
    raise exception 'That invite is not there any more.' using errcode = 'P0001', hint = 'no_invite';
  end if;
  if i.status <> 'pending' then
    raise exception 'That invite has been answered already.' using errcode = 'P0001', hint = 'answered';
  end if;
  if i.expires_at <= v_now then
    update kids_invites set status = 'expired', responded_at = v_now where id = i.id;
    return jsonb_build_object('message', 'That invite has expired.', 'expired', true, 'accepted', false);
  end if;
  if not coalesce(p_accept, false) then
    update kids_invites set status = 'declined', responded_at = v_now where id = i.id;
    return jsonb_build_object('message', 'Okay. There is no rush, and nothing was charged.', 'accepted', false);
  end if;
  if not bl_kids_can_start() then
    raise exception 'Babies are resting for now. Check back soon.' using errcode = 'P0001', hint = 'off';
  end if;
  begin
    r := bl_love_lock_rel(v_me.id, i.rel_id);
  exception when others then
    update kids_invites set status = 'cancelled', responded_at = v_now where id = i.id;
    return jsonb_build_object('message', 'You two are not together any more, so that invite is gone.', 'expired', true, 'accepted', false);
  end;
  v_el := bl_kids_eligibility(r);
  if v_el is not null then
    update kids_invites set status = 'cancelled', responded_at = v_now where id = i.id;
    return jsonb_build_object('message', v_el ->> 'msg', 'expired', true, 'accepted', false, 'code', v_el ->> 'code');
  end if;
  if v_cost > 0 then
    if (select cash + greatest(bank, 0) from profiles where id = v_me.id) < v_cost then
      raise exception 'You need % for the baby plans, and you do not have it yet.', bl_naira(v_cost) using errcode = 'P0001', hint = 'not_enough_money';
    end if;
    if (select cash + greatest(bank, 0) from profiles where id = i.from_user) < v_cost then
      raise exception 'Your partner cannot cover their share of % right now. Try again a little later.', bl_naira(v_cost) using errcode = 'P0001', hint = 'partner_short';
    end if;
    perform bl_sink_pay(v_me.id, v_cost, 'kid_try', jsonb_build_object('label', 'Baby plans', 'rel', r.id));
    perform bl_sink_pay(i.from_user, v_cost, 'kid_try', jsonb_build_object('label', 'Baby plans', 'rel', r.id));
  end if;
  v_due := v_now + make_interval(secs => (bl_love_num('kids.pregnancy_days', 3) * 86400)::double precision);
  insert into kids_children (rel_id, parent_a, parent_b, proposed_by, status, conceived_at, due_at, next_alert_at, created_at)
  values (r.id, r.user_a, r.user_b, i.from_user, 'expecting', v_now, v_due, v_due, v_now) returning id into v_cid;
  update kids_invites set status = 'accepted', responded_at = v_now, child_id = v_cid where id = i.id;
  select username into v_fname from profiles where id = v_me.id;
  perform bl_event(i.from_user, 'kids_expecting', 'Expecting a little one 🍼', '@' || v_fname || ' said yes! Your baby arrives in about ' || bl_love_wait_text(extract(epoch from (v_due - v_now))) || '.',
                   jsonb_build_object('child', v_cid));
  perform bl_push_enqueue(i.from_user, 'friends', 'kids_expecting', 'Expecting a little one 🍼', '@' || v_fname || ' said yes!', '/play?go=family:family', v_me.id, null, null, 'kidsexp:' || v_cid, false, null);
  return jsonb_build_object('message', 'Expecting a little one 🍼 Your baby arrives in about ' || bl_love_wait_text(extract(epoch from (v_due - v_now))) || '.',
                            'accepted', true, 'child', v_cid, 'due_at', v_due);
end $$;

-- Take back the invite I sent.
create or replace function public.kids_withdraw(p_invite bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); n int;
begin
  update kids_invites set status = 'withdrawn', responded_at = bl_now() where id = p_invite and from_user = v_uid and status = 'pending';
  get diagnostics n = row_count;
  if n = 0 then
    raise exception 'That invite is not waiting any more.' using errcode = 'P0001', hint = 'no_invite';
  end if;
  return jsonb_build_object('message', 'Invite taken back.');
end $$;

-- Name the baby (3-16 letters, clean) and pick Boy or Girl (looks only). The first parent to name wins.
create or replace function public.kids_name(p_child bigint, p_name text, p_gender text default 'boy') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  c      public.kids_children;
  v_nm   text := btrim(coalesce(p_name, ''));
  v_g    text := lower(coalesce(p_gender, ''));
  v_other uuid; v_who text;
begin
  if not bl_kids_on() then
    raise exception 'Kids is resting for now.' using errcode = 'P0001', hint = 'off';
  end if;
  if v_nm !~ '^[[:alpha:]]{3,16}$' then
    raise exception 'A name is 3 to 16 letters, with no spaces, numbers or symbols.' using errcode = 'P0001', hint = 'bad_name';
  end if;
  if v_g not in ('boy', 'girl') then
    raise exception 'Pick Boy or Girl.' using errcode = 'P0001', hint = 'bad_gender';
  end if;
  v_nm := upper(left(v_nm, 1)) || lower(substr(v_nm, 2));
  if bl_chat_mask(v_nm) <> v_nm or bl_chat_mask(lower(v_nm)) <> lower(v_nm) then
    raise exception 'That name is not allowed. Pick a kind one.' using errcode = 'P0001', hint = 'blocked_text';
  end if;
  c := bl_kids_settle(p_child);
  if c.id is null or (c.parent_a is distinct from v_me.id and c.parent_b is distinct from v_me.id) then
    raise exception 'That child is not yours.' using errcode = 'P0001', hint = 'not_parent';
  end if;
  if c.status not in ('home', 'with_relatives') then
    raise exception 'The baby has not arrived yet.' using errcode = 'P0001', hint = 'not_born';
  end if;
  if c.name is not null then
    select username into v_who from profiles where id = c.named_by;
    raise exception '% already has a name%.', c.name, case when v_who is not null then ' (@' || v_who || ' picked it)' else '' end using errcode = 'P0001', hint = 'already_named';
  end if;
  update kids_children set name = v_nm, gender = v_g, named_by = v_me.id, auto_named = false where id = c.id returning * into c;
  v_other := case when c.parent_a = v_me.id then c.parent_b else c.parent_a end;
  perform bl_kids_notify(v_other, 'kids_named', '👶 @' || v_me.username || ' named your baby ' || v_nm, 'Say hello to ' || v_nm || ' in Family.', c.id);
  c := bl_kids_process(c.id, false);
  return jsonb_build_object('message', 'Welcome, ' || v_nm || '! 👶', 'child', c.id, 'name', v_nm);
end $$;

-- Look after a child: feed / sleep / play / medicine / cuddle. Either parent. Cooldowns per child; feed and medicine cost money (a sink).
create or replace function public.kids_care(p_child bigint, p_action text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_now   timestamptz := bl_now();
  c       public.kids_children;
  v_can   jsonb; v_need text; v_cur numeric; v_add numeric; v_cost bigint; v_cured boolean := false; v_nm text; v_msg text; v_new numeric;
begin
  if not bl_kids_on() then
    raise exception 'Kids is resting for now.' using errcode = 'P0001', hint = 'off';
  end if;
  v_need := case p_action when 'feed' then 'hunger' when 'sleep' then 'sleep' when 'play' then 'fun' when 'medicine' then 'health' when 'cuddle' then 'love' end;
  if v_need is null then
    raise exception 'Pick feed, sleep, play, medicine or cuddle.' using errcode = 'P0001', hint = 'bad_action';
  end if;
  c := bl_kids_settle(p_child);
  if c.id is null or (c.parent_a is distinct from v_me.id and c.parent_b is distinct from v_me.id) then
    raise exception 'That child is not yours to look after.' using errcode = 'P0001', hint = 'not_parent';
  end if;
  v_can := bl_kids_can(c, p_action, v_now);
  if not (v_can ->> 'ok')::boolean then
    raise exception '%', v_can ->> 'msg' using errcode = 'P0001', hint = v_can ->> 'code';
  end if;
  v_nm := bl_kids_label(c);
  v_cost := (v_can ->> 'cost')::bigint;
  if v_cost > 0 then
    perform bl_sink_pay(v_me.id, v_cost, 'kid_care', jsonb_build_object('label', case p_action when 'feed' then 'Feeding ' else 'Medicine for ' end || v_nm, 'child', c.id, 'action', p_action));
  end if;
  v_cur := bl_kids_val(c, v_need, v_now);
  v_add := bl_love_num('kids.' || case p_action when 'feed' then 'feed' when 'sleep' then 'sleep' when 'play' then 'play' when 'medicine' then 'medicine' else 'cuddle' end || '_restore', 40);
  v_new := least(100, v_cur + v_add);
  execute format('update kids_children set %I = %L, %I = %L where id = %s', v_need, v_new, v_need || '_at', v_now, c.id);
  update kids_children set last_care_at = v_now, alerts_unanswered = 0 where id = c.id;
  if c.sick_since is not null and p_action = 'medicine' then update kids_children set sick_med = true where id = c.id; end if;
  if c.sick_since is not null and p_action = 'cuddle' then update kids_children set sick_cuddle = true where id = c.id; end if;
  select * into c from kids_children where id = c.id;
  if c.sick_since is not null and c.sick_med and c.sick_cuddle then
    update kids_children set sick_since = null, sick_med = false, sick_cuddle = false, cured_at = v_now where id = c.id;
    v_cured := true;
  end if;
  insert into kids_care_log (child_id, user_id, action, cost, created_at) values (c.id, v_me.id, p_action, v_cost, v_now);
  delete from kids_care_log where child_id = c.id and id < coalesce((select id from kids_care_log where child_id = c.id order by id desc offset 40 limit 1), 0);
  c := bl_kids_process(c.id, false);
  v_msg := case p_action
    when 'feed' then 'You fed ' || v_nm || '. Tummy full 🍼'
    when 'sleep' then v_nm || ' is sleeping peacefully 😴'
    when 'play' then 'You played with ' || v_nm || '. Lots of giggles 🎈'
    when 'medicine' then 'You gave ' || v_nm || ' medicine 💊'
    else 'A big cuddle for ' || v_nm || ' 🤗' end;
  if v_cured then v_msg := v_msg || ' ' || v_nm || ' is feeling better!';
  elsif c.sick_since is not null then v_msg := v_msg || case when c.sick_med and not c.sick_cuddle then ' Now a cuddle will help too.' when c.sick_cuddle and not c.sick_med then ' Medicine will help too.' else '' end;
  end if;
  return jsonb_build_object('message', v_msg, 'spent', v_cost, 'cured', v_cured, 'child', c.id, 'need', v_need, 'value', floor(v_new)::int);
end $$;

-- Bring a child home from relatives (once). Costs money (a sink); the child must have stayed a while.
create or replace function public.kids_reclaim(p_child bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_now   timestamptz := bl_now();
  c       public.kids_children;
  v_cost  bigint := bl_love_num('kids.reclaim_cost', 10000)::bigint; v_wait numeric; v_start numeric := bl_love_num('kids.reclaim_need', 60); v_nm text;
begin
  if not bl_kids_on() then
    raise exception 'Kids is resting for now.' using errcode = 'P0001', hint = 'off';
  end if;
  c := bl_kids_settle(p_child);
  if c.id is null or (c.parent_a is distinct from v_me.id and c.parent_b is distinct from v_me.id) then
    raise exception 'That child is not yours.' using errcode = 'P0001', hint = 'not_parent';
  end if;
  if c.status <> 'with_relatives' then
    raise exception 'That child is not with relatives.' using errcode = 'P0001', hint = 'not_away';
  end if;
  if c.reclaims >= 1 then
    raise exception 'You already brought this child home once. They stay with relatives now.' using errcode = 'P0001', hint = 'used';
  end if;
  v_wait := extract(epoch from (c.relatives_at + make_interval(hours => bl_love_num('kids.reclaim_wait_hours', 12)::int) - v_now));
  if v_wait > 0 then
    raise exception 'Relatives are enjoying the visit. You can bring them home in %.', bl_love_wait_text(v_wait) using errcode = 'P0001', hint = 'cooldown';
  end if;
  v_nm := bl_kids_label(c);
  if v_cost > 0 then
    perform bl_sink_pay(v_me.id, v_cost, 'kid_reclaim', jsonb_build_object('label', 'Bringing ' || v_nm || ' home', 'child', c.id));
  end if;
  update kids_children set status = 'home', reclaims = reclaims + 1, relatives_at = null, last_care_at = v_now, last_alert_at = null, alerts_unanswered = 0,
         sick_since = null, sick_med = false, sick_cuddle = false,
         hunger = v_start, hunger_at = v_now, sleep = v_start, sleep_at = v_now, fun = v_start, fun_at = v_now, health = v_start, health_at = v_now, love = v_start, love_at = v_now
   where id = c.id returning * into c;
  perform bl_kids_notify(case when c.parent_a = v_me.id then c.parent_b else c.parent_a end, 'kids_home', v_nm || ' is back home 🏠',
                         '@' || v_me.username || ' brought ' || v_nm || ' home from relatives.', c.id);
  c := bl_kids_process(c.id, false);
  return jsonb_build_object('message', v_nm || ' is back home 🏠 Look after them well.', 'spent', v_cost, 'child', c.id);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Admin
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_kids_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard();
begin
  return jsonb_build_object(
    'enabled', bl_kids_on(),
    'expecting', (select count(*) from kids_children where status = 'expecting'),
    'home', (select count(*) from kids_children where status = 'home'),
    'with_relatives', (select count(*) from kids_children where status = 'with_relatives'),
    'needs_attention', (select count(*) from kids_children where status = 'home' and last_alert_at > bl_now() - interval '24 hours'),
    'sick', (select count(*) from kids_children where status = 'home' and sick_since is not null),
    'grown', (select count(*) from kids_children where status = 'grown'),
    'gone', (select count(*) from kids_children where status = 'gone'),
    'due_now', (select count(*) from kids_children where next_alert_at <= bl_now()),
    'children', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'status', x.status, 'born_at', x.born_at, 'due_at', x.due_at,
                 'sick', x.sick_since is not null, 'removals', x.removals,
                 'a', (select username from profiles where id = x.parent_a), 'b', (select username from profiles where id = x.parent_b)) order by x.id desc)
                 from (select * from kids_children where status in ('expecting', 'home', 'with_relatives') order by id desc limit 50) x), '[]'::jsonb));
end $$;

-- An admin ends a child's profile (abuse, a wrong name). Audited; both parents are told kindly.
create or replace function public.admin_kids_remove(p_child bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); c public.kids_children;
begin
  select * into c from kids_children where id = p_child and status in ('expecting', 'home', 'with_relatives') for update;
  if not found then
    raise exception 'That child is not active.' using errcode = 'P0001', hint = 'no_child';
  end if;
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = c.id;
  perform bl_kids_notify_both(c, 'kids_gone', 'A moderator ended ' || case when c.status = 'expecting' then 'your baby plans' else bl_kids_label(c) || '''s profile' end,
                              'If you think this is a mistake, use Feedback.');
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'kids_remove', coalesce(c.parent_a, c.parent_b), jsonb_build_object('child', c.id, 'name', c.name, 'a', c.parent_a, 'b', c.parent_b, 'reason', left(coalesce(p_reason, ''), 200)));
  return jsonb_build_object('message', 'Child removed.');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Patches on live functions (guarded, written against the CURRENT definitions)
-- ---------------------------------------------------------------------------------------------
-- the alert sweep rides on the push scheduler (Edge Function player-push -> bl_push_tick), no new cron
select pg_temp.kd_patch('public.bl_push_tick()',
  $o$return jsonb_build_object('events_queued', v_n, 'recovered', v_stuck, 'expired', v_old, 'deleted', v_del);$o$,
  $o$return jsonb_build_object('events_queued', v_n, 'recovered', v_stuck, 'expired', v_old, 'deleted', v_del)
         || jsonb_build_object('kids_swept', bl_kids_alert_sweep());   -- kids: needs-attention alerts and births (docs/LOVE.md)$o$,
  $o$bl_kids_alert_sweep()$o$);

-- public profile: "Proud parent" count (only when the player shows their relationship)
select pg_temp.kd_patch('public.get_public_profile(uuid)',
  $o$'love_open', (love_open and bl_love_on()))$o$,
  $o$'love_open', (love_open and bl_love_on()), 'proud_parent', bl_kids_proud(id))$o$,
  $o$'proud_parent', bl_kids_proud(id)$o$);

-- ledger: labels, never earned, Admin -> Economy category
select pg_temp.kd_patch('public.bl_ledger_label(text, jsonb)',
  $o$when 'love_date' then return coalesce(nullif(p_meta->>'label', ''), 'Date');$o$,
  $o$when 'love_date' then return coalesce(nullif(p_meta->>'label', ''), 'Date');
    when 'kid_try' then return coalesce(nullif(p_meta->>'label', ''), 'Baby plans');
    when 'kid_care' then return coalesce(nullif(p_meta->>'label', ''), 'Child care');
    when 'kid_reclaim' then return coalesce(nullif(p_meta->>'label', ''), 'Bringing a child home');$o$,
  $o$when 'kid_try' then$o$);

select pg_temp.kd_patch('public.bl_econ_category(text)',
  $o$'love_flirt', 'love_date') or p_reason like$o$,
  $o$'love_flirt', 'love_date', 'kid_try', 'kid_care', 'kid_reclaim') or p_reason like$o$,
  $o$'kid_try', 'kid_care', 'kid_reclaim'$o$);

select pg_temp.kd_patch('public.bl_earn_reasons()',
  $o$'love_flirt', 'love_date'])$o$,
  $o$'love_flirt', 'love_date', 'kid_try', 'kid_care', 'kid_reclaim'])$o$,
  $o$'kid_try', 'kid_care', 'kid_reclaim'$o$);

-- admin Content editor: Child stages and Baby names
select pg_temp.kd_patch('public.bl_admin_table_spec(text)',
  $o$when 'love_flirts' then$o$,
  E'when ''kids_stages'' then ''{"pk":["id"],"insert":true,"order":"from_days, id",\n      "cols":{"name":"text","emoji":"text","from_days":"int","rate_hunger":"num","rate_sleep":"num","rate_fun":"num","rate_health":"num","rate_love":"num","sort":"int","active":"bool"}}''\n    when ''kids_auto_names'' then ''{"pk":["name"],"insert":true,"order":"name",\n      "cols":{"active":"bool"}}''\n    when ''love_flirts'' then',
  $o$when 'kids_stages' then$o$);

-- ---------------------------------------------------------------------------------------------
-- 9. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and proname like 'bl\_kids\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  -- the sweep may be called by the service role (an optional direct Cron call), never by players
  grant execute on function public.bl_kids_alert_sweep() to service_role;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and (proname like 'kids\_%' or proname like 'admin\_kids\_%') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
end $$;

notify pgrst, 'reload schema';
