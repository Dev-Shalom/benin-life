-- C1 Pickpocket + jail choices (docs/CRIME.md).
-- * steal_attempt(target): a seconds-long action (busy timer, live progress in the task pill) against another real player
--   at the same PUBLIC place (never a private home, a start home, a home scene or the police station). Checks: crime.steal_enabled,
--   both not newbies (crime.steal_newbie_hours, plus the victim's start protection), victim seen recently at that place,
--   thief free (not busy / jailed / in hospital / on the road), cooldowns per thief and per victim.
--   Rows are locked in id order (both profiles) so two players stealing from each other can never deadlock.
-- * steal_finish(): after the timer the server rolls: CAUGHT with crime.steal_caught_pct (default 62 %, skill hook in
--   bl_steal_caught_pct). Not caught: 5–15 % of the victim's CASH (never bank), at least crime.steal_min and at most
--   crime.steal_max, moved atomically with ledger rows on both sides (steal_gain / steal_loss) and an alert to the victim
--   that never names the thief. Caught: nothing is taken, the victim is told "@thief tried and was caught", and a
--   jail_cases row opens for the thief (held at Police HQ).
-- * jail_cases: the server-side case (bail price, escape attempts, jail seconds, jail_until, status). The thief chooses:
--   jail_case_bail() (crime.bail_base, bank first then cash, ledger 'bail', receipt), jail_case_go_to_jail() (serve the
--   time: action.jail_max_seconds) or jail_case_escape() (CAUGHT again with crime.escape_caught_pct: jail time ×
--   crime.escape_time_mult and bail × crime.escape_bail_mult, compounding; free otherwise).
-- * police_bail() routes to jail_case_bail() while a case is open (the old cheap story bail can't skip the case price).
-- * Admin: admin_jail_cases(), admin_jail_release() (audited).
-- Idempotent; safe on a non-empty DB.

-- ---------------------------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('crime.steal_enabled', 'true', 'crime', 'Pickpocketing on',
 'C1: players can try to pick the pocket of another player standing near them at a public place. Off = no Steal button and the server refuses.', 'bool', null, null),
('crime.steal_seconds', '4', 'crime', 'Pickpocket time (seconds)',
 'C1: how long the "Picking a pocket" action takes before the server rolls the outcome.', 'number', 1, 60),
('crime.steal_range_m', '3', 'crime', 'Pickpocket reach (metres)',
 'C1: the thief must stand this close to the other player in the 3D place to see Steal (checked on the thief''s screen; the server checks same place + recently seen).', 'number', 0.5, 50),
('crime.steal_caught_pct', '62', 'crime', 'Pickpocket: chance of being caught',
 'C1: chance the police catch a pickpocket (0 = never, 100 = always). Caught = nothing stolen and the thief gets a jail case.', 'percent', 0, 100),
('crime.steal_min_pct', '5', 'crime', 'Pickpocket: smallest share taken',
 'C1: a successful pickpocket takes a random share of the victim''s CASH on hand between this and the biggest share. Bank money is never touched.', 'percent', 0, 100),
('crime.steal_max_pct', '15', 'crime', 'Pickpocket: biggest share taken',
 'C1: see the smallest share.', 'percent', 0, 100),
('crime.steal_min', '100', 'crime', 'Pickpocket: smallest amount',
 'C1: a successful pickpocket takes at least this (if the victim has it). Victims with less cash than this have an "empty pocket".', 'naira', 0, 1000000000),
('crime.steal_max', '50000', 'crime', 'Pickpocket: biggest amount',
 'C1: cap on one successful pickpocket.', 'naira', 0, 1000000000000),
('crime.steal_thief_cooldown_s', '180', 'crime', 'Pickpocket: wait between tries (seconds)',
 'C1: a player can try to steal at most once in this many real seconds (caught or not).', 'number', 0, 86400),
('crime.steal_victim_cooldown_s', '600', 'crime', 'Pickpocket: victim rest (seconds)',
 'C1: after someone''s pocket is picked, nobody can pick it again for this many real seconds.', 'number', 0, 86400),
('crime.steal_newbie_hours', '24', 'crime', 'Pickpocket: newbie protection (hours)',
 'C1: accounts younger than this can''t be pickpocketed and can''t steal. New-player protection (start.protection_real_minutes) also blocks it.', 'number', 0, 8760),
('crime.steal_seen_seconds', '180', 'crime', 'Pickpocket: victim must be seen within (seconds)',
 'C1: the victim must have been online at that place within this many real seconds.', 'number', 10, 3600),
('crime.bail_base', '20000000', 'crime', 'Bail after being caught',
 'C1: bail price when a pickpocket is caught (bank first, then cash). Each failed escape multiplies it by the escape bail multiplier.', 'naira', 0, 9000000000000000),
('crime.escape_caught_pct', '52', 'crime', 'Escape: chance of being caught again',
 'C1: chance a "Try to escape" fails. Fail = jail time and bail both multiply, and the choice comes back.', 'percent', 0, 100),
('crime.escape_time_mult', '2', 'crime', 'Escape fail: jail time multiplier',
 'C1: each failed escape multiplies the jail time by this (compounding). Base time: action.jail_max_seconds.', 'number', 1, 100),
('crime.escape_bail_mult', '2', 'crime', 'Escape fail: bail multiplier',
 'C1: each failed escape multiplies the bail price by this (compounding).', 'number', 1, 100),
('crime.case_jail_max_seconds', '86400', 'crime', 'Longest jail time for a case (seconds)',
 'C1: failed escapes can never push one case''s jail time past this.', 'number', 1, 604800)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.crime_attempts (
  id           bigserial primary key,
  kind         text not null default 'pickpocket' check (kind in ('pickpocket')),
  thief_id     uuid not null references public.profiles(id) on delete cascade,
  victim_id    uuid not null references public.profiles(id) on delete cascade,
  location_id  text not null,
  started_at   timestamptz not null,
  resolve_at   timestamptz not null,
  status       text not null default 'running'
               check (status in ('running', 'success', 'caught', 'gone', 'empty', 'missed', 'cancelled')),
  amount       bigint not null default 0 check (amount >= 0),
  caught_pct   numeric,
  resolved_at  timestamptz
);
create index if not exists crime_attempts_thief_idx on public.crime_attempts (thief_id, started_at desc);
create index if not exists crime_attempts_victim_idx on public.crime_attempts (victim_id, started_at desc);
create index if not exists crime_attempts_running_idx on public.crime_attempts (thief_id) where status = 'running';

create table if not exists public.jail_cases (
  id               bigserial primary key,
  user_id          uuid not null references public.profiles(id) on delete cascade,
  reason           text not null,
  location_id      text,
  attempt_id       bigint references public.crime_attempts(id) on delete set null,
  bail_amount      bigint not null check (bail_amount >= 0),
  escape_attempts  int not null default 0 check (escape_attempts >= 0),
  jail_seconds     int not null check (jail_seconds > 0),
  jail_until       timestamptz not null,
  decided          boolean not null default false,
  status           text not null default 'open' check (status in ('open', 'bailed', 'served', 'escaped', 'released')),
  created_at       timestamptz not null default now(),
  closed_at        timestamptz,
  released_by      uuid references auth.users(id) on delete set null
);
create unique index if not exists jail_cases_one_open_uidx on public.jail_cases (user_id) where status = 'open';
create index if not exists jail_cases_user_idx on public.jail_cases (user_id, id desc);
create index if not exists jail_cases_attempt_idx on public.jail_cases (attempt_id) where attempt_id is not null;
create index if not exists jail_cases_released_by_idx on public.jail_cases (released_by) where released_by is not null;

alter table public.crime_attempts enable row level security;
alter table public.jail_cases enable row level security;
revoke all on table public.crime_attempts from public, anon, authenticated;
revoke all on table public.jail_cases from public, anon, authenticated;
revoke all on sequence public.crime_attempts_id_seq from public, anon, authenticated;
revoke all on sequence public.jail_cases_id_seq from public, anon, authenticated;
-- attempts stay server-only (a victim must not learn who tried unless caught); players read their own cases
grant select on table public.jail_cases to authenticated;
drop policy if exists jail_cases_own on public.jail_cases;
create policy jail_cases_own on public.jail_cases for select to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_crime_bool(p_key text, p_default boolean) returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_crime_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

-- A public place where pickpocketing can happen: active, not a private player home, not a start home, not a home scene,
-- not the police station (where the jailed sit).
create or replace function public.bl_crime_public_place(p_loc text) returns boolean
language sql stable set search_path = public as $$
  select exists (
    select 1 from locations l
     where l.id = p_loc and coalesce(l.active, true)
       and l.private_home_owner_id is null
       and l.scene not like 'home%'
       and l.scene <> 'police'
       and not exists (select 1 from start_homes h where h.location_id = l.id));
$$;

-- Chance (0–100) that this pickpocket is caught.
-- SKILL HOOK: p_skill_mod is reserved for future skills/perks (e.g. a "Light fingers" skill passes +10 to lower the
-- odds by 10 points, CCTV at the place could pass a negative number). Nothing passes it yet, so it is always 0.
create or replace function public.bl_steal_caught_pct(p_thief uuid, p_victim uuid, p_skill_mod numeric default 0) returns numeric
language sql stable set search_path = public as $$
  select greatest(0, least(100, bl_crime_num('crime.steal_caught_pct', 62) - coalesce(p_skill_mod, 0)));
$$;

-- One server-side roll: true with probability p_pct / 100. Tests seed it with setseed() or force it with 0 / 100.
create or replace function public.bl_crime_roll(p_pct numeric) returns boolean
language sql volatile set search_path = public as $$
  select random() * 100 < greatest(0, least(100, coalesce(p_pct, 0)));
$$;

-- An open case whose time has passed (or whose cell was opened by something else) is "served".
create or replace function public.bl_crime_close_stale(p_uid uuid) returns void
language sql set search_path = public as $$
  update jail_cases c set status = 'served', closed_at = bl_now()
    from profiles p
   where c.user_id = p_uid and c.status = 'open' and p.id = c.user_id
     and (c.jail_until <= bl_now() or p.jailed_until is null or p.jailed_until <= bl_now());
$$;

create or replace function public.bl_crime_case_json(c jail_cases) returns jsonb
language sql stable set search_path = public as $$
  select case when c.id is null then null else jsonb_build_object(
    'id', c.id, 'status', c.status, 'decided', c.decided, 'reason', c.reason, 'bail_amount', c.bail_amount,
    'escape_attempts', c.escape_attempts, 'jail_seconds', c.jail_seconds, 'jail_until', c.jail_until,
    'created_at', c.created_at, 'location_id', c.location_id,
    'place', (select name from locations where id = c.location_id),
    'can_afford', coalesce((select p.cash + p.bank >= c.bail_amount from profiles p where p.id = c.user_id), false),
    'escape_caught_pct', bl_crime_num('crime.escape_caught_pct', 52),
    'escape_time_mult', bl_crime_num('crime.escape_time_mult', 2),
    'escape_bail_mult', bl_crime_num('crime.escape_bail_mult', 2)) end;
$$;

-- Resolve one running attempt (the server roll). Locks the attempt, then both profiles in id order.
create or replace function public.bl_steal_resolve(p_id bigint) returns jsonb
language plpgsql set search_path = public as $$
declare
  a crime_attempts;
  th profiles;
  vi profiles;
  v_now timestamptz := bl_now();
  v_place text;
  v_status text;
  v_amount bigint := 0;
  v_pct numeric;
  v_share numeric;
  v_min bigint := greatest(0, bl_crime_num('crime.steal_min', 100))::bigint;
  v_max bigint := greatest(0, bl_crime_num('crime.steal_max', 50000))::bigint;
  v_lo numeric := greatest(0, least(100, bl_crime_num('crime.steal_min_pct', 5)));
  v_hi numeric := greatest(0, least(100, bl_crime_num('crime.steal_max_pct', 15)));
  v_seen numeric := greatest(10, bl_crime_num('crime.steal_seen_seconds', 180));
  v_vcd numeric := greatest(0, bl_crime_num('crime.steal_victim_cooldown_s', 600));
  v_jail int := greatest(1, ceil(bl_crime_num('action.jail_max_seconds', 45)))::int;
  v_jail_loc text := coalesce(bl_cfg_text('crime.jail_location'), 'police_hq');
  c jail_cases;
begin
  select * into a from crime_attempts where id = p_id for update;
  if not found then
    return jsonb_build_object('status', 'none');
  end if;
  if a.status <> 'running' then
    return jsonb_build_object('status', a.status, 'already', true, 'amount', a.amount);
  end if;
  perform 1 from profiles where id in (a.thief_id, a.victim_id) order by id for update;
  select * into th from profiles where id = a.thief_id;
  select * into vi from profiles where id = a.victim_id;
  select name into v_place from locations where id = a.location_id;
  v_place := coalesce(v_place, 'this place');

  if th.location_id is distinct from a.location_id or th.travel_to is not null
     or (th.jailed_until is not null and th.jailed_until > v_now) then
    v_status := 'cancelled';
  elsif vi.banned or vi.location_id is distinct from a.location_id or vi.travel_to is not null
        or vi.last_seen < now() - make_interval(secs => v_seen::double precision) then
    v_status := 'gone';
  elsif exists (select 1 from crime_attempts x where x.victim_id = a.victim_id and x.id <> a.id and x.status = 'success'
                   and x.resolved_at > v_now - make_interval(secs => v_vcd::double precision)) then
    v_status := 'missed';
  else
    v_pct := bl_steal_caught_pct(a.thief_id, a.victim_id, 0);
    if bl_crime_roll(v_pct) then
      v_status := 'caught';
    elsif vi.cash < greatest(v_min, 1) then
      v_status := 'empty';
    else
      v_status := 'success';
      v_share := v_lo + random() * greatest(0, v_hi - v_lo);
      v_amount := floor(vi.cash * v_share / 100)::bigint;
      v_amount := least(greatest(v_amount, v_min), v_max, vi.cash);
      if v_amount <= 0 then
        v_status := 'empty';
        v_amount := 0;
      end if;
    end if;
  end if;

  if v_status = 'success' then
    perform bl_add_money(a.victim_id, 'cash', -v_amount, 'steal_loss',
                         jsonb_build_object('attempt_id', a.id, 'location', a.location_id, 'place', v_place));
    perform bl_add_money(a.thief_id, 'cash', v_amount, 'steal_gain',
                         jsonb_build_object('attempt_id', a.id, 'location', a.location_id, 'place', v_place, 'victim', vi.username));
    perform bl_event(a.victim_id, 'stolen_from', 'Someone picked your pocket',
                     'Someone picked your pocket at ' || v_place || ': −' || bl_naira(v_amount) || '. Keep your money in the bank.',
                     jsonb_build_object('amount', v_amount, 'location', a.location_id));
    perform bl_event(a.thief_id, 'steal_success', 'Pocket picked',
                     'You slipped ' || bl_naira(v_amount) || ' from @' || vi.username || '''s pocket at ' || v_place || '.',
                     jsonb_build_object('amount', v_amount, 'location', a.location_id));
  elsif v_status = 'caught' then
    perform bl_crime_close_stale(a.thief_id);
    insert into jail_cases (user_id, reason, location_id, attempt_id, bail_amount, jail_seconds, jail_until, created_at)
    values (a.thief_id, 'Caught pickpocketing at ' || v_place, a.location_id, a.id,
            greatest(0, round(bl_crime_num('crime.bail_base', 20000000)))::bigint, v_jail,
            v_now + make_interval(secs => v_jail), v_now)
    returning * into c;
    update profiles set
      jailed_until = c.jail_until, jail_reason = c.reason, wanted = least(5, wanted + 1),
      location_id = coalesce((select id from locations where id = v_jail_loc), location_id),
      travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
     where id = a.thief_id;
    perform bl_event(a.victim_id, 'pickpocket_stopped', 'Thief caught!',
                     '@' || th.username || ' tried to pick your pocket at ' || v_place || ' and was caught by the police.',
                     jsonb_build_object('thief', th.username, 'location', a.location_id));
    perform bl_event(a.thief_id, 'steal_caught', 'Police don catch you!',
                     'You were caught pickpocketing at ' || v_place || '.', jsonb_build_object('case_id', c.id));
  end if;

  update crime_attempts set status = v_status, amount = v_amount, caught_pct = v_pct, resolved_at = v_now where id = a.id;
  -- the "Picking a pocket" timer is over
  update profiles set busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
   where id = a.thief_id and busy_label = 'Picking a pocket';

  return jsonb_build_object(
    'status', v_status, 'amount', v_amount, 'victim', vi.username, 'place', v_place,
    'case', case when v_status = 'caught' then bl_crime_case_json(c) end,
    'message', case v_status
      when 'success' then 'You slipped ' || bl_naira(v_amount) || ' from @' || vi.username || '''s pocket.'
      when 'caught' then 'Police don catch you!'
      when 'empty' then '@' || vi.username || '''s pocket was empty. Nothing to take.'
      when 'gone' then '@' || vi.username || ' moved away before you could reach their pocket.'
      when 'missed' then 'Someone just picked @' || vi.username || '''s pocket. Nothing left to take.'
      else 'The pickpocket was called off.' end);
end $$;

revoke all on function public.bl_crime_bool(text, boolean) from public, anon, authenticated;
revoke all on function public.bl_crime_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_crime_public_place(text) from public, anon, authenticated;
revoke all on function public.bl_steal_caught_pct(uuid, uuid, numeric) from public, anon, authenticated;
revoke all on function public.bl_crime_roll(numeric) from public, anon, authenticated;
revoke all on function public.bl_crime_close_stale(uuid) from public, anon, authenticated;
revoke all on function public.bl_crime_case_json(jail_cases) from public, anon, authenticated;
revoke all on function public.bl_steal_resolve(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.steal_attempt(p_target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_me profiles;
  t profiles;
  v_now timestamptz := bl_now();
  v_secs numeric := greatest(1, bl_crime_num('crime.steal_seconds', 4));
  v_newbie numeric := greatest(0, bl_crime_num('crime.steal_newbie_hours', 24));
  v_seen numeric := greatest(10, bl_crime_num('crime.steal_seen_seconds', 180));
  v_tcd numeric := greatest(0, bl_crime_num('crime.steal_thief_cooldown_s', 180));
  v_vcd numeric := greatest(0, bl_crime_num('crime.steal_victim_cooldown_s', 600));
  v_last timestamptz;
  v_left int;
  v_id bigint;
  v_until timestamptz;
begin
  if not bl_crime_bool('crime.steal_enabled', false) then
    raise exception 'Pickpocketing is switched off for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  if p_target is null or p_target = v_uid then
    raise exception 'You can''t pick your own pocket.' using errcode = 'P0001', hint = 'self';
  end if;
  -- lock both players in id order (never deadlocks when two players go for each other)
  perform 1 from profiles where id in (v_uid, p_target) order by id for update;
  v_me := bl_me();
  select * into t from profiles where id = p_target;
  if not found or t.banned or not t.home_chosen then
    raise exception 'That player is not here.' using errcode = 'P0001', hint = 'not_here';
  end if;
  perform bl_crime_close_stale(v_uid);
  perform bl_assert_free(v_me);
  if v_me.created_at > v_now - make_interval(hours => 0, secs => (v_newbie * 3600)::double precision) then
    raise exception 'You are still new in Benin. Wait until your account is % hours old before you try that.', v_newbie::int
      using errcode = 'P0001', hint = 'newbie_self';
  end if;
  if t.created_at > v_now - make_interval(secs => (v_newbie * 3600)::double precision)
     or (t.protected_until is not null and t.protected_until > v_now) then
    raise exception '@% is new in town and protected. Leave am.', t.username using errcode = 'P0001', hint = 'protected';
  end if;
  if v_me.home_visit_host_id is not null or not bl_crime_public_place(v_me.location_id) then
    raise exception 'You can only try that at a public place, never inside someone''s home.' using errcode = 'P0001', hint = 'private_place';
  end if;
  if t.location_id is distinct from v_me.location_id or t.travel_to is not null
     or t.last_seen < now() - make_interval(secs => v_seen::double precision)
     or (t.jailed_until is not null and t.jailed_until > v_now)
     or (t.hospitalized_until is not null and t.hospitalized_until > v_now) then
    raise exception '@% is not here with you.', t.username using errcode = 'P0001', hint = 'not_here';
  end if;
  select max(started_at) into v_last from crime_attempts where thief_id = v_uid and status <> 'cancelled';
  if v_last is not null and v_last > v_now - make_interval(secs => v_tcd::double precision) then
    v_left := ceil(extract(epoch from v_last + make_interval(secs => v_tcd::double precision) - v_now));
    raise exception 'Cool down small. You can try again in about % sec.', v_left using errcode = 'P0001', hint = 'cooldown';
  end if;
  if exists (select 1 from crime_attempts x where x.victim_id = p_target
               and ((x.status = 'success' and x.resolved_at > v_now - make_interval(secs => v_vcd::double precision))
                    or (x.status = 'running' and x.resolve_at > v_now - interval '60 seconds'))) then
    raise exception '@% is watching their pocket now. Try someone else.', t.username using errcode = 'P0001', hint = 'victim_cooldown';
  end if;

  v_until := v_now + make_interval(secs => v_secs::double precision);
  insert into crime_attempts (thief_id, victim_id, location_id, started_at, resolve_at)
  values (v_uid, p_target, v_me.location_id, v_now, v_until)
  returning id into v_id;
  update profiles set busy_until = v_until, busy_started_at = v_now, busy_label = 'Picking a pocket', busy_needs_from = null
   where id = v_uid;
  return jsonb_build_object('attempt_id', v_id, 'busy_until', v_until, 'seconds', v_secs, 'target', t.username,
                            'message', 'Easy… you reach for @' || t.username || '''s pocket.');
end $$;
revoke all on function public.steal_attempt(uuid) from public, anon;
grant execute on function public.steal_attempt(uuid) to authenticated, service_role;

-- Roll my running pickpocket once its timer is over.
create or replace function public.steal_finish() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  a crime_attempts;
  v_left int;
begin
  perform bl_me_any();
  select * into a from crime_attempts where thief_id = v_uid and status = 'running' order by id desc limit 1;
  if not found then
    raise exception 'You are not picking any pocket right now.' using errcode = 'P0001', hint = 'no_attempt';
  end if;
  if a.resolve_at > bl_now() then
    v_left := ceil(extract(epoch from a.resolve_at - bl_now()));
    raise exception 'Hold on, about % sec more.', v_left using errcode = 'P0001', hint = 'not_yet';
  end if;
  return bl_steal_resolve(a.id);
end $$;
revoke all on function public.steal_finish() from public, anon;
grant execute on function public.steal_finish() to authenticated, service_role;

-- My crime state: the open jail case (the popup/jail screen), a running pickpocket (finished here when due), cooldown.
create or replace function public.crime_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  a crime_attempts;
  c jail_cases;
  v_res jsonb;
  v_last timestamptz;
  v_tcd numeric := greatest(0, bl_crime_num('crime.steal_thief_cooldown_s', 180));
begin
  if not exists (select 1 from profiles where id = v_uid) then
    return jsonb_build_object('case', null, 'attempt', null);
  end if;
  select * into a from crime_attempts where thief_id = v_uid and status = 'running' order by id desc limit 1;
  if found and a.resolve_at <= bl_now() then
    v_res := bl_steal_resolve(a.id);
    a := null;
  end if;
  perform bl_crime_close_stale(v_uid);
  select * into c from jail_cases where user_id = v_uid and status = 'open';
  select max(started_at) into v_last from crime_attempts where thief_id = v_uid and status <> 'cancelled';
  return jsonb_build_object(
    'case', case when c.id is not null then bl_crime_case_json(c) end,
    'attempt', case when a.id is not null then jsonb_build_object('id', a.id, 'resolve_at', a.resolve_at,
                     'target', (select username from profiles where id = a.victim_id)) end,
    'resolved', v_res,
    'cooldown_until', case when v_last is not null then v_last + make_interval(secs => v_tcd::double precision) end);
end $$;
revoke all on function public.crime_status() from public, anon;
grant execute on function public.crime_status() to authenticated, service_role;

-- Pay the case's bail (bank first, then cash). Releases at once; ledger 'bail'; receipt when it is big enough.
create or replace function public.jail_case_bail() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me();
  c jail_cases;
  v_cost bigint;
  v_from_bank bigint;
  v_from_cash bigint;
  v_rcpt jsonb;
begin
  perform bl_crime_close_stale(v_me.id);
  select * into c from jail_cases where user_id = v_me.id and status = 'open' for update;
  if not found then
    raise exception 'You have no open police case.' using errcode = 'P0001', hint = 'no_case';
  end if;
  v_cost := c.bail_amount;
  v_from_bank := least(v_me.bank, v_cost);
  v_from_cash := v_cost - v_from_bank;
  if v_from_cash > v_me.cash then
    raise exception 'Bail is % (bank first, then cash). You have % in total.', bl_naira(v_cost), bl_naira(v_me.bank + v_me.cash)
      using errcode = 'P0001', hint = 'not_enough_money';
  end if;
  if v_from_bank > 0 then
    perform bl_add_money(v_me.id, 'bank', -v_from_bank, 'bail', jsonb_build_object('case_id', c.id, 'bank_first', true));
  end if;
  if v_from_cash > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_from_cash, 'bail', jsonb_build_object('case_id', c.id, 'bank_first', true));
  end if;
  update jail_cases set status = 'bailed', decided = true, closed_at = bl_now() where id = c.id;
  update profiles set jailed_until = null, jail_reason = null, wanted = greatest(0, wanted - 1) where id = v_me.id;
  v_rcpt := bl_receipt_issue(v_me.id, 'bail', 'Bail · Police HQ', v_cost, 'Nigeria Police Force, Benin City',
                             jsonb_build_object('case_id', c.id, 'escape_attempts', c.escape_attempts));
  perform bl_event(v_me.id, 'police_release', 'You are released', 'Bail of ' || bl_naira(v_cost) || ' paid. You are free to go.',
                   jsonb_build_object('paid', v_cost, 'case_id', c.id));
  return jsonb_build_object('message', 'Bail paid. You are free to go.', 'paid', v_cost, 'bank', v_from_bank, 'cash', v_from_cash)
         || coalesce(v_rcpt, '{}'::jsonb);
end $$;
revoke all on function public.jail_case_bail() from public, anon;
grant execute on function public.jail_case_bail() to authenticated, service_role;

-- Accept the cell: serve the time (the timer already runs since the arrest). Closes the popup.
create or replace function public.jail_case_go_to_jail() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me();
  c jail_cases;
begin
  perform bl_crime_close_stale(v_me.id);
  update jail_cases set decided = true where user_id = v_me.id and status = 'open' returning * into c;
  if not found then
    raise exception 'You have no open police case.' using errcode = 'P0001', hint = 'no_case';
  end if;
  return jsonb_build_object('case', bl_crime_case_json(c), 'jail_until', c.jail_until,
                            'message', 'You sit down in the cell. Time go soon finish.');
end $$;
revoke all on function public.jail_case_go_to_jail() from public, anon;
grant execute on function public.jail_case_go_to_jail() to authenticated, service_role;

-- Try to escape: caught again (crime.escape_caught_pct) = jail time and bail multiply (compounding); else free.
create or replace function public.jail_case_escape() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me();
  c jail_cases;
  v_now timestamptz := bl_now();
  v_tm numeric := greatest(1, bl_crime_num('crime.escape_time_mult', 2));
  v_bm numeric := greatest(1, bl_crime_num('crime.escape_bail_mult', 2));
  v_cap numeric := greatest(1, bl_crime_num('crime.case_jail_max_seconds', 86400));
  v_back text;
begin
  perform bl_crime_close_stale(v_me.id);
  select * into c from jail_cases where user_id = v_me.id and status = 'open' for update;
  if not found then
    raise exception 'You have no open police case.' using errcode = 'P0001', hint = 'no_case';
  end if;
  if bl_crime_roll(bl_crime_num('crime.escape_caught_pct', 52)) then
    update jail_cases set
      escape_attempts = escape_attempts + 1,
      jail_seconds = least(v_cap, ceil(jail_seconds * v_tm))::int,
      bail_amount = least(9000000000000000::numeric, round(bail_amount * v_bm))::bigint,
      jail_until = v_now + make_interval(secs => least(v_cap, ceil(jail_seconds * v_tm))::double precision),
      decided = false
     where id = c.id
    returning * into c;
    update profiles set jailed_until = c.jail_until where id = v_me.id;
    return jsonb_build_object('escaped', false, 'case', bl_crime_case_json(c),
      'message', 'Dem catch you again! More time, and bail don rise to ' || bl_naira(c.bail_amount) || '.');
  end if;
  update jail_cases set status = 'escaped', decided = true, closed_at = v_now where id = c.id;
  -- slip back to where it happened when that place is still a public place
  v_back := case when c.location_id is not null and bl_crime_public_place(c.location_id) then c.location_id end;
  update profiles set jailed_until = null, jail_reason = null, location_id = coalesce(v_back, location_id) where id = v_me.id;
  return jsonb_build_object('escaped', true, 'location_id', coalesce(v_back, v_me.location_id), 'message', 'You escaped! Lie low small.');
end $$;
revoke all on function public.jail_case_escape() from public, anon;
grant execute on function public.jail_case_escape() to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Admin RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_jail_cases(p_status text default 'open', p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_lim int := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_status text := nullif(lower(btrim(coalesce(p_status, 'open'))), 'all');
  v_uid uuid;
begin
  perform bl_admin_guard();
  -- close cases whose time is over so the list is current
  for v_uid in select user_id from jail_cases where status = 'open' loop
    perform bl_crime_close_stale(v_uid);
  end loop;
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(bl_crime_case_json(c) || jsonb_build_object('user_id', c.user_id, 'username', p.username,
                     'closed_at', c.closed_at, 'released_by', (select username from profiles where id = c.released_by))
                     order by c.id desc)
      from (select * from jail_cases where v_status is null or status = v_status order by id desc limit v_lim) c
      join profiles p on p.id = c.user_id), '[]'::jsonb));
end $$;
revoke all on function public.admin_jail_cases(text, int) from public, anon;
grant execute on function public.admin_jail_cases(text, int) to authenticated, service_role;

create or replace function public.admin_jail_release(p_case_id bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  c jail_cases;
begin
  select * into c from jail_cases where id = p_case_id and status = 'open' for update;
  if not found then
    raise exception 'That case is not open.' using errcode = 'P0001', hint = 'not_found';
  end if;
  update jail_cases set status = 'released', decided = true, closed_at = bl_now(), released_by = v_admin where id = c.id;
  update profiles set jailed_until = null, jail_reason = null where id = c.user_id;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'jail_release', c.user_id, jsonb_build_object('case_id', c.id, 'reason', left(btrim(coalesce(p_reason, '')), 300),
                                                                 'bail_amount', c.bail_amount, 'escape_attempts', c.escape_attempts));
  perform bl_event(c.user_id, 'police_release', 'You are released', 'The Benin Life team released you from the cell.',
                   jsonb_build_object('case_id', c.id));
  return jsonb_build_object('message', 'Released.');
end $$;
revoke all on function public.admin_jail_release(bigint, text) from public, anon;
grant execute on function public.admin_jail_release(bigint, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Existing functions (guarded edits of the live definitions)
-- ---------------------------------------------------------------------------------------------
-- police_bail(): while a pickpocket case is open, bail is the case price (jail_case_bail), not the cheap story bail.
do $$
declare v_def text; v_anchor text := ' if v_me.jailed_until is null or v_me.jailed_until<=bl_now() then';
begin
  select pg_get_functiondef('public.police_bail()'::regprocedure) into v_def;
  if position('jail_case_bail' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'C1: police_bail() changed; update the pickpocket migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    ' if exists (select 1 from jail_cases where user_id = v_me.id and status = ''open'' and jail_until > bl_now()) then return jail_case_bail(); end if;'
    || chr(10) || v_anchor);
  execute v_def;
end $$;
revoke all on function public.police_bail() from public, anon;
grant execute on function public.police_bail() to authenticated, service_role;

-- bl_ledger_label(): Bank -> History lines for the new reasons.
do $$
declare v_def text; v_anchor text := '    when ''topup'' then';
begin
  select pg_get_functiondef('public.bl_ledger_label(text, jsonb)'::regprocedure) into v_def;
  if position('steal_gain' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'C1: bl_ledger_label() changed; update the pickpocket migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''steal_gain'' then return ''Pickpocketed'' || coalesce('' · '' || nullif(p_meta->>''place'', ''''), '''');' || chr(10)
    || '    when ''steal_loss'' then return ''Stolen from you'' || coalesce('' · '' || nullif(p_meta->>''place'', ''''), '''');' || chr(10)
    || '    when ''bail'' then return ''Bail'';' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

notify pgrst, 'reload schema';
