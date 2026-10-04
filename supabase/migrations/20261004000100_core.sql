-- =====================================================================
-- Benin Life — CORE schema, helpers and core RPCs            (owner: P1-DB)
-- Contract: docs/ARCHITECTURE.md §3/§4.  Reference: docs/DB_CORE.md
-- Idempotent: safe to run on a DB where it was already applied.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

create table if not exists public.locations (
  id              text primary key,
  name            text not null,
  district        text not null,
  scene           text not null,
  blurb           text not null default '',
  risk            numeric not null default 0.2 check (risk >= 0 and risk <= 1),
  night_risk_mult numeric not null default 1.5 check (night_risk_mult >= 0),
  cctv            boolean not null default false,
  keke_ok         boolean not null default false,
  congestion      numeric not null default 1.0 check (congestion > 0),
  remote_km       numeric not null default 0 check (remote_km >= 0),
  x               numeric not null,
  y               numeric not null,
  actions         text[] not null default '{}',
  sort            int not null default 0
);

create table if not exists public.game_config (
  key         text primary key,
  value       jsonb not null,
  category    text not null default 'misc',
  label       text not null default '',
  description text not null default '',
  kind        text not null default 'number'
              check (kind in ('percent','number','naira','minutes','bool','text')),
  min         numeric,
  max         numeric,
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);

create table if not exists public.profiles (
  id                 uuid primary key references auth.users(id) on delete cascade,
  username           text not null check (username ~ '^[A-Za-z0-9_]{3,20}$'),
  gender             text not null default 'male' check (gender in ('male','female')),
  avatar             jsonb not null default '{}'::jsonb,
  is_admin           boolean not null default false,
  banned             boolean not null default false,
  cash               bigint not null default 0 check (cash >= 0),
  bank               bigint not null default 0 check (bank >= 0),
  hunger             numeric not null default 80,
  energy             numeric not null default 80,
  hygiene            numeric not null default 80,
  fun                numeric not null default 80,
  social             numeric not null default 80,
  health             numeric not null default 100,
  stress             numeric not null default 10,
  needs_updated_at   timestamptz not null default now(),
  location_id        text not null references public.locations(id),
  home_location_id   text not null references public.locations(id),
  housing_id         text,
  job_id             text,
  job_level          int not null default 1,
  job_xp             int not null default 0,
  street_cred        int not null default 0,
  wanted             int not null default 0,
  travel_to          text references public.locations(id),
  travel_mode        text,
  travel_started_at  timestamptz,
  travel_arrives_at  timestamptz,
  busy_until         timestamptz,
  busy_label         text,
  jailed_until       timestamptz,
  jail_reason        text,
  hospitalized_until timestamptz,
  protected_until    timestamptz,
  charm_strength     numeric not null default 0 check (charm_strength >= 0 and charm_strength <= 1),
  charm_until        timestamptz,
  last_seen          timestamptz not null default now(),
  created_at         timestamptz not null default now()
);
create unique index if not exists profiles_username_lower_idx on public.profiles (lower(username));
create index if not exists profiles_location_seen_idx on public.profiles (location_id, last_seen desc);

create table if not exists public.config_audit (
  id         bigserial primary key,
  admin_id   uuid references public.profiles(id) on delete set null,
  key        text not null,
  old_value  jsonb,
  new_value  jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.ledger (
  id            bigserial primary key,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  account       text not null check (account in ('cash','bank')),
  delta         bigint not null,
  balance_after bigint not null,
  reason        text not null,
  meta          jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index if not exists ledger_user_idx on public.ledger (user_id, created_at desc);
create index if not exists ledger_reason_idx on public.ledger (reason, created_at desc);

create table if not exists public.events (
  id         bigserial primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null,
  title      text not null,
  body       text not null default '',
  data       jsonb not null default '{}'::jsonb,
  read       boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists events_user_idx on public.events (user_id, id desc);

create table if not exists public.items (
  id          text primary key,
  name        text not null,
  category    text not null,
  price       bigint not null default 0 check (price >= 0),
  description text not null default '',
  effects     jsonb not null default '{}'::jsonb,
  sold_at     text[] not null default '{}',
  sellable    boolean not null default true,
  resale_pct  numeric not null default 50,
  icon        text,
  sort        int not null default 0
);

create table if not exists public.inventory (
  user_id uuid not null references public.profiles(id) on delete cascade,
  item_id text not null references public.items(id) on delete cascade,
  qty     int  not null default 1 check (qty >= 0),
  primary key (user_id, item_id)
);

create table if not exists public.activities (
  id           text primary key,
  name         text not null,
  scenes       text[] not null default '{}',
  home_only    boolean not null default false,
  cost         bigint not null default 0 check (cost >= 0),
  game_minutes int not null default 30 check (game_minutes >= 0),
  effects      jsonb not null default '{}'::jsonb,
  night_only   boolean not null default false,
  sort         int not null default 0
);

-- keep game_config.updated_at fresh on any update
create or replace function public.bl_touch_config() returns trigger
language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists game_config_touch on public.game_config;
create trigger game_config_touch before update on public.game_config
  for each row execute function public.bl_touch_config();

-- ---------------------------------------------------------------------
-- 2. RLS + grants  (clients: SELECT only; every write goes through RPCs)
-- ---------------------------------------------------------------------
alter table public.locations    enable row level security;
alter table public.game_config  enable row level security;
alter table public.profiles     enable row level security;
alter table public.config_audit enable row level security;
alter table public.ledger       enable row level security;
alter table public.events       enable row level security;
alter table public.items        enable row level security;
alter table public.inventory    enable row level security;
alter table public.activities   enable row level security;

revoke all on table public.locations, public.game_config, public.profiles, public.config_audit,
                    public.ledger, public.events, public.items, public.inventory, public.activities
  from anon, authenticated;
revoke all on sequence public.config_audit_id_seq, public.ledger_id_seq, public.events_id_seq
  from anon, authenticated;

-- public catalogs
grant select on public.locations, public.game_config, public.items, public.activities to anon, authenticated;
-- per-user tables
grant select on public.profiles, public.ledger, public.events, public.inventory, public.config_audit to authenticated;

drop policy if exists locations_read on public.locations;
create policy locations_read on public.locations for select to anon, authenticated using (true);
drop policy if exists game_config_read on public.game_config;
create policy game_config_read on public.game_config for select to anon, authenticated using (true);
drop policy if exists items_read on public.items;
create policy items_read on public.items for select to anon, authenticated using (true);
drop policy if exists activities_read on public.activities;
create policy activities_read on public.activities for select to anon, authenticated using (true);

drop policy if exists profiles_own on public.profiles;
create policy profiles_own on public.profiles for select to authenticated using (id = (select auth.uid()));
drop policy if exists ledger_own on public.ledger;
create policy ledger_own on public.ledger for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists events_own on public.events;
create policy events_own on public.events for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists inventory_own on public.inventory;
create policy inventory_own on public.inventory for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists config_audit_admin on public.config_audit;
create policy config_audit_admin on public.config_audit for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin));

-- realtime
do $$
declare t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array['profiles','events','game_config'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 3. Internal helpers (bl_*) — revoked from clients at the bottom
-- ---------------------------------------------------------------------

-- Current time; tests time-travel with: set local bl.test_offset_seconds = '600'
create or replace function public.bl_now() returns timestamptz
language sql stable set search_path = public as $$
  select now() + make_interval(secs => coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::double precision, 0));
$$;

-- Uniform [0,1); tests force rolls with: set local bl.test_rand = '0.01'
create or replace function public.bl_rand() returns double precision
language plpgsql volatile set search_path = public as $$
declare v text := current_setting('bl.test_rand', true);
begin
  if v is not null and v <> '' then return v::double precision; end if;
  return random();
end $$;

create or replace function public.bl_cfg(p_key text) returns numeric
language plpgsql stable set search_path = public as $$
declare v jsonb;
begin
  select value into v from game_config where key = p_key;
  if not found then
    raise exception 'Config "%" no dey — admin abeg check settings.', p_key using errcode = 'P0001';
  end if;
  return (v #>> '{}')::numeric;
end $$;

create or replace function public.bl_cfg_bool(p_key text) returns boolean
language plpgsql stable set search_path = public as $$
declare v jsonb;
begin
  select value into v from game_config where key = p_key;
  if not found then
    raise exception 'Config "%" no dey — admin abeg check settings.', p_key using errcode = 'P0001';
  end if;
  return (v #>> '{}')::boolean;
end $$;

create or replace function public.bl_cfg_text(p_key text) returns text
language plpgsql stable set search_path = public as $$
declare v jsonb;
begin
  select value into v from game_config where key = p_key;
  if not found then
    raise exception 'Config "%" no dey — admin abeg check settings.', p_key using errcode = 'P0001';
  end if;
  return v #>> '{}';
end $$;

-- ₦12,345
create or replace function public.bl_naira(p_amount numeric) returns text
language sql immutable set search_path = public as $$
  select '₦' || to_char(round(coalesce(p_amount, 0)), 'FM999,999,999,999,990');
$$;

-- Real seconds that p_game_minutes of status time (busy/jail/hospital) lasts
create or replace function public.bl_real_seconds(p_game_minutes numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce(p_game_minutes, 0) * public.bl_cfg('time.real_seconds_per_game_minute');
$$;

-- GameClock json at p_at (default bl_now())
create or replace function public.bl_game_clock(p_at timestamptz default null) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_at   timestamptz := coalesce(p_at, bl_now());
  v_gm   bigint;
  v_hour int;
  v_min  int;
  v_ns   int := bl_cfg('clock.night_start_hour')::int;
  v_ne   int := bl_cfg('clock.night_end_hour')::int;
begin
  -- multiply before dividing so whole real seconds map to exact game minutes (no 12.9999 -> 12)
  v_gm := floor(extract(epoch from (v_at - timestamptz '2026-01-01 00:00:00+00'))
                * bl_cfg('clock.game_minutes_per_real_minute') / 60.0
                + bl_cfg('clock.start_hour_offset') * 60)::bigint;
  v_hour := ((v_gm % 1440 + 1440) % 1440) / 60;
  v_min  := ((v_gm % 60) + 60) % 60;
  return jsonb_build_object(
    'game_minutes', v_gm,
    'day', floor(v_gm / 1440.0)::bigint + 1,
    'hour', v_hour,
    'minute', v_min,
    'is_night', case when v_ns > v_ne then (v_hour >= v_ns or v_hour < v_ne)
                     else (v_hour >= v_ns and v_hour < v_ne) end
  );
end $$;

-- auth.uid() or a Pidgin error
create or replace function public.bl_require_uid() returns uuid
language plpgsql stable set search_path = public as $$
declare v uuid := auth.uid();
begin
  if v is null then
    raise exception 'Abeg login first, my guy.' using errcode = 'P0001', hint = 'not_logged_in';
  end if;
  return v;
end $$;

create or replace function public.bl_location(p_id text) returns public.locations
language plpgsql stable set search_path = public as $$
declare v locations;
begin
  select * into v from locations where id = p_id;
  if not found then
    raise exception 'That place no dey for map o.' using errcode = 'P0001';
  end if;
  return v;
end $$;

-- Pure needs decay: returns p_row with needs decayed up to p_at (no write). Path-independent, so
-- decaying in several small steps gives the same result as one big step.
create or replace function public.bl_decay_row(p_row public.profiles, p_at timestamptz) returns public.profiles
language plpgsql stable set search_path = public as $$
declare
  v        profiles := p_row;
  v_hours  numeric;
  r_hun    numeric; r_en numeric; r_hy numeric; r_fun numeric; r_soc numeric; r_str numeric;
  r_starve numeric; v_floor numeric;
  v_zero   numeric;
  v_health numeric;
begin
  if v.id is null then return v; end if;
  v_hours := extract(epoch from (p_at - v.needs_updated_at))::numeric / 3600.0
             * bl_cfg('clock.game_minutes_per_real_minute');
  if v_hours <= 0 then return v; end if;

  r_hun := bl_cfg('needs.hunger_per_hour');   r_en  := bl_cfg('needs.energy_per_hour');
  r_hy  := bl_cfg('needs.hygiene_per_hour');  r_fun := bl_cfg('needs.fun_per_hour');
  r_soc := bl_cfg('needs.social_per_hour');   r_str := bl_cfg('needs.stress_per_hour');
  r_starve := bl_cfg('needs.starve_health_per_hour');
  v_floor  := bl_cfg('needs.starve_health_floor');

  -- game hours until hunger or energy first hits 0 -> health drains after that
  v_zero := least(case when r_hun > 0 then greatest(v.hunger, 0) / r_hun else 1e9 end,
                  case when r_en  > 0 then greatest(v.energy, 0) / r_en  else 1e9 end);
  v_health := v.health - greatest(0, v_hours - v_zero) * r_starve;
  -- starvation alone never pushes health below the floor (but never lifts it either)
  v_health := greatest(v_health, least(v.health, v_floor));

  v.hunger  := round(greatest(0, least(100, v.hunger  - r_hun * v_hours)), 4);
  v.energy  := round(greatest(0, least(100, v.energy  - r_en  * v_hours)), 4);
  v.hygiene := round(greatest(0, least(100, v.hygiene - r_hy  * v_hours)), 4);
  v.fun     := round(greatest(0, least(100, v.fun     - r_fun * v_hours)), 4);
  v.social  := round(greatest(0, least(100, v.social  - r_soc * v_hours)), 4);
  v.stress  := round(greatest(0, least(100, v.stress  + r_str * v_hours)), 4);
  v.health  := round(greatest(0, least(100, v_health)), 4);
  v.needs_updated_at := p_at;
  return v;
end $$;

-- Lazy needs decay since needs_updated_at, persisted. Locks the row. Returns the fresh row (null if no profile).
create or replace function public.bl_apply_needs(p_uid uuid) returns public.profiles
language plpgsql set search_path = public as $$
declare
  v     profiles;
  v_now timestamptz := bl_now();
begin
  select * into v from profiles where id = p_uid for update;
  if not found then return null; end if;
  if v.needs_updated_at >= v_now then return v; end if;
  v := bl_decay_row(v, v_now);
  update profiles set
    hunger = v.hunger, energy = v.energy, hygiene = v.hygiene, fun = v.fun, social = v.social,
    stress = v.stress, health = v.health, needs_updated_at = v.needs_updated_at
  where id = p_uid
  returning * into v;
  return v;
end $$;

-- Caller's profile row (locked FOR UPDATE, needs decayed). Raises if not logged in / no profile / banned.
create or replace function public.bl_me() returns public.profiles
language plpgsql set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v profiles;
begin
  select * into v from profiles where id = v_uid for update;
  if not found then
    raise exception 'You never create your person yet. Go create am first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v.banned then
    raise exception 'Dem don ban this account. If na mistake, contact admin.' using errcode = 'P0001', hint = 'banned';
  end if;
  return bl_apply_needs(v_uid);
end $$;

-- Raises if the player is jailed, hospitalised, on the road or busy.
create or replace function public.bl_assert_free(p_me public.profiles) returns void
language plpgsql stable set search_path = public as $$
declare v_now timestamptz := bl_now(); v_left int;
begin
  if p_me.jailed_until is not null and p_me.jailed_until > v_now then
    v_left := ceil(extract(epoch from p_me.jailed_until - v_now));
    raise exception 'You dey police cell o! Wait like % sec or find bail.', v_left using errcode = 'P0001', hint = 'jailed';
  end if;
  if p_me.hospitalized_until is not null and p_me.hospitalized_until > v_now then
    v_left := ceil(extract(epoch from p_me.hospitalized_until - v_now));
    raise exception 'You still dey admit for hospital. Rest small — like % sec remain.', v_left using errcode = 'P0001', hint = 'hospitalized';
  end if;
  if p_me.travel_to is not null then
    raise exception 'You still dey road o. Make you reach first.' using errcode = 'P0001', hint = 'traveling';
  end if;
  if p_me.busy_until is not null and p_me.busy_until > v_now then
    v_left := ceil(extract(epoch from p_me.busy_until - v_now));
    raise exception 'Hold on, you dey busy with "%". E go finish in like % sec.', coalesce(p_me.busy_label, 'something'), v_left
      using errcode = 'P0001', hint = 'busy';
  end if;
end $$;

-- Clamp-add needs. p_delta e.g. '{"hunger":30,"energy":-10}'. Unknown keys ignored.
create or replace function public.bl_adjust_needs(p_uid uuid, p_delta jsonb) returns void
language plpgsql set search_path = public as $$
begin
  perform bl_apply_needs(p_uid);
  update profiles set
    hunger  = greatest(0, least(100, hunger  + coalesce((p_delta->>'hunger')::numeric, 0))),
    energy  = greatest(0, least(100, energy  + coalesce((p_delta->>'energy')::numeric, 0))),
    hygiene = greatest(0, least(100, hygiene + coalesce((p_delta->>'hygiene')::numeric, 0))),
    fun     = greatest(0, least(100, fun     + coalesce((p_delta->>'fun')::numeric, 0))),
    social  = greatest(0, least(100, social  + coalesce((p_delta->>'social')::numeric, 0))),
    health  = greatest(0, least(100, health  + coalesce((p_delta->>'health')::numeric, 0))),
    stress  = greatest(0, least(100, stress  + coalesce((p_delta->>'stress')::numeric, 0)))
  where id = p_uid;
end $$;

-- The ONLY way money moves. Writes ledger; raises 'Your money no reach' if it would go negative.
create or replace function public.bl_add_money(p_uid uuid, p_account text, p_delta bigint, p_reason text,
                                               p_meta jsonb default '{}'::jsonb) returns bigint
language plpgsql set search_path = public as $$
declare v_bal bigint;
begin
  if p_account not in ('cash','bank') then
    raise exception 'Unknown money account %', p_account using errcode = 'P0001';
  end if;
  if p_delta is null then
    raise exception 'Money amount no correct.' using errcode = 'P0001';
  end if;
  if p_account = 'cash' then
    update profiles set cash = cash + p_delta where id = p_uid and cash + p_delta >= 0 returning cash into v_bal;
  else
    update profiles set bank = bank + p_delta where id = p_uid and bank + p_delta >= 0 returning bank into v_bal;
  end if;
  if not found then
    if not exists (select 1 from profiles where id = p_uid) then
      raise exception 'Dis person no dey.' using errcode = 'P0001';
    end if;
    raise exception 'Your money no reach, my guy.' using errcode = 'P0001', hint = 'insufficient_funds';
  end if;
  if p_delta <> 0 then
    insert into ledger (user_id, account, delta, balance_after, reason, meta, created_at)
    values (p_uid, p_account, p_delta, v_bal, coalesce(p_reason, 'unknown'), coalesce(p_meta, '{}'::jsonb), bl_now());
  end if;
  return v_bal;
end $$;

create or replace function public.bl_event(p_uid uuid, p_kind text, p_title text, p_body text,
                                           p_data jsonb default '{}'::jsonb) returns bigint
language plpgsql set search_path = public as $$
declare v_id bigint;
begin
  insert into events (user_id, kind, title, body, data, created_at)
  values (p_uid, p_kind, p_title, coalesce(p_body, ''), coalesce(p_data, '{}'::jsonb), bl_now())
  returning id into v_id;
  return v_id;
end $$;

-- Jail: extends any current sentence, moves player to crime.jail_location, cancels travel/busy.
create or replace function public.bl_jail(p_uid uuid, p_game_minutes int, p_reason text) returns timestamptz
language plpgsql set search_path = public as $$
declare v_until timestamptz; v_loc text := bl_cfg_text('crime.jail_location');
begin
  update profiles set
    jailed_until = greatest(coalesce(jailed_until, bl_now()), bl_now())
                   + make_interval(secs => bl_real_seconds(p_game_minutes)::double precision),
    jail_reason = p_reason,
    location_id = coalesce((select id from locations where id = v_loc), location_id),
    travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
    busy_until = null, busy_label = null
  where id = p_uid
  returning jailed_until into v_until;
  return v_until;
end $$;

-- Hospitalise: extends stay; moves player to crime.hospital_location unless already at a hospital scene.
create or replace function public.bl_hospitalize(p_uid uuid, p_game_minutes int, p_reason text) returns timestamptz
language plpgsql set search_path = public as $$
declare v_until timestamptz; v_loc text := bl_cfg_text('crime.hospital_location');
begin
  update profiles p set
    hospitalized_until = greatest(coalesce(p.hospitalized_until, bl_now()), bl_now())
                         + make_interval(secs => bl_real_seconds(p_game_minutes)::double precision),
    location_id = case when (select scene from locations where id = p.location_id) = 'hospital' then p.location_id
                       else coalesce((select id from locations where id = v_loc), p.location_id) end,
    travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
    busy_until = null, busy_label = null
  where p.id = p_uid
  returning p.hospitalized_until into v_until;
  return v_until;
end $$;

create or replace function public.bl_set_busy(p_uid uuid, p_game_minutes int, p_label text) returns timestamptz
language plpgsql set search_path = public as $$
declare v_until timestamptz;
begin
  update profiles set
    busy_until = bl_now() + make_interval(secs => bl_real_seconds(p_game_minutes)::double precision),
    busy_label = p_label
  where id = p_uid
  returning busy_until into v_until;
  return v_until;
end $$;

create or replace function public.bl_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin and not banned from profiles where id = auth.uid()), false);
$$;

-- Straight-line km between two locations (+ remote_km of each end)
create or replace function public.bl_distance_km(p_from text, p_to text) returns numeric
language sql stable set search_path = public as $$
  select round((sqrt(power(a.x - b.x, 2) + power(a.y - b.y, 2)) / 1000.0 * bl_cfg('travel.city_km_across')
                + a.remote_km + b.remote_km)::numeric, 2)
  from locations a, locations b where a.id = p_from and b.id = p_to;
$$;

-- Traffic multiplier for a trip at time p_at (walk ignores traffic — caller passes 1)
create or replace function public.bl_traffic(p_from text, p_to text, p_at timestamptz default null) returns numeric
language plpgsql stable set search_path = public as $$
declare
  a locations; b locations;
  v_hour int := (bl_game_clock(coalesce(p_at, bl_now()))->>'hour')::int;
  v numeric;
begin
  select * into a from locations where id = p_from;
  select * into b from locations where id = p_to;
  v := (coalesce(a.congestion, 1) + coalesce(b.congestion, 1)) / 2.0;
  if (v_hour >= bl_cfg('traffic.rush_am_start') and v_hour < bl_cfg('traffic.rush_am_end'))
     or (v_hour >= bl_cfg('traffic.rush_pm_start') and v_hour < bl_cfg('traffic.rush_pm_end')) then
    v := v * bl_cfg('traffic.rush_mult');
  end if;
  if not bl_cfg_bool('traffic.ramat_flyover_open')
     and (a.district in ('ikpoba_hill','aduwawa') or b.district in ('ikpoba_hill','aduwawa')) then
    v := v * bl_cfg('traffic.ramat_mult');
  end if;
  return round(v, 3);
end $$;

-- Street-robbery probability (0..1) for p_uid arriving at p_location by p_mode, ARCHITECTURE §4.
-- P2-CRIME may create-or-replace this (same signature) to keep travel_quote risk_pct in sync.
create or replace function public.bl_street_robbery_chance(p_uid uuid, p_location text, p_mode text,
                                                           p_traffic numeric, p_at timestamptz default null) returns numeric
language plpgsql stable set search_path = public as $$
declare
  v_at   timestamptz := coalesce(p_at, bl_now());
  me     profiles;
  loc    locations;
  v_p    numeric;
  v_cash numeric;
  v_mode numeric;
  v_charm numeric := 0;
begin
  select * into me from profiles where id = p_uid;
  select * into loc from locations where id = p_location;
  if me.id is null or loc.id is null then return 0; end if;
  if me.protected_until is not null and me.protected_until > v_at then return 0; end if;
  if me.cash <= 0 then return 0; end if;

  v_cash := least(bl_cfg('crime.cash_factor_max'),
                  bl_cfg('crime.cash_factor_min') + me.cash / greatest(bl_cfg('crime.cash_ref'), 1));
  v_mode := coalesce((select (value #>> '{}')::numeric from game_config where key = 'crime.mode_mult_' || p_mode), 1);
  if me.charm_strength > 0 and (me.charm_until is null or me.charm_until > v_at) then
    v_charm := least(1, me.charm_strength);
  end if;

  v_p := bl_cfg('crime.npc_base_pct') / 100.0
         * loc.risk
         * (case when (bl_game_clock(v_at)->>'is_night')::boolean
                 then loc.night_risk_mult * bl_cfg('crime.night_mult') else 1 end)
         * greatest(0, 1 + (coalesce(p_traffic, 1) - 1) * bl_cfg('crime.traffic_weight'))
         * v_cash
         * v_mode
         * (1 - v_charm);
  return greatest(0, least(v_p, bl_cfg('crime.npc_max_pct') / 100.0));
end $$;

-- Rolls an NPC street robbery. Returns null if nothing happened, else {amount, injured, health_loss, location}.
-- Takes the cash (ledger reason 'street_robbery'), maybe injures, and bl_event()s the victim.
create or replace function public.bl_roll_street_robbery(p_uid uuid, p_location text, p_mode text,
                                                         p_traffic numeric) returns jsonb
language plpgsql set search_path = public as $$
declare
  v_p      numeric := bl_street_robbery_chance(p_uid, p_location, p_mode, p_traffic, bl_now());
  v_cash   bigint;
  v_pct    numeric;
  v_amount bigint;
  v_injured boolean := false;
  v_hloss  numeric := 0;
  v_name   text;
  v_body   text;
begin
  if v_p <= 0 or bl_rand() >= v_p then return null; end if;

  select cash into v_cash from profiles where id = p_uid for update;
  v_pct := bl_cfg('crime.loss_min_pct')
           + bl_rand() * (bl_cfg('crime.loss_max_pct') - bl_cfg('crime.loss_min_pct'));
  v_amount := least(v_cash, greatest(1, floor(v_cash * v_pct / 100.0)))::bigint;
  if v_amount <= 0 then return null; end if;

  perform bl_add_money(p_uid, 'cash', -v_amount, 'street_robbery',
                       jsonb_build_object('location', p_location, 'mode', p_mode));

  if bl_rand() < bl_cfg('crime.injury_pct') / 100.0 then
    v_injured := true;
    v_hloss := round(bl_cfg('crime.injury_health_min')
                     + bl_rand() * (bl_cfg('crime.injury_health_max') - bl_cfg('crime.injury_health_min')));
  end if;
  perform bl_adjust_needs(p_uid, jsonb_build_object('health', -v_hloss, 'stress', bl_cfg('crime.robbery_stress')));

  select name into v_name from locations where id = p_location;
  v_body := 'Some boys collect ' || bl_naira(v_amount) || ' from you for ' || coalesce(v_name, p_location)
            || '. You fit report am for Police HQ.'
            || case when v_injured then ' Dem wound you small — run go UBTH or clinic sharp sharp.' else '' end;
  perform bl_event(p_uid, 'robbed', 'Omo, dem don rob you!', v_body,
                   jsonb_build_object('source', 'street', 'amount', v_amount, 'location', p_location,
                                      'mode', p_mode, 'injured', v_injured, 'health_loss', v_hloss,
                                      'at', bl_now()));
  return jsonb_build_object('amount', v_amount, 'injured', v_injured, 'health_loss', v_hloss,
                            'location', p_location);
end $$;

-- Full travel quote from p_me.location_id to p_dest.
create or replace function public.bl_travel_quote(p_me public.profiles, p_dest text) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  dst      locations := bl_location(p_dest);
  src      locations := bl_location(p_me.location_id);
  v_km     numeric;
  v_now    timestamptz := bl_now();
  v_traffic_road numeric;
  v_has_car boolean;
  v_opts   jsonb := '[]'::jsonb;
  m        text;
  v_label  text;
  v_speed  numeric; v_cost bigint; v_traffic numeric; v_gm int; v_rs numeric;
  v_allowed boolean; v_reason text;
  v_risk   numeric;
begin
  if dst.id = src.id then
    raise exception 'You don dey % already na.', dst.name using errcode = 'P0001';
  end if;
  v_km := bl_distance_km(src.id, dst.id);
  v_traffic_road := bl_traffic(src.id, dst.id, v_now);
  v_has_car := exists (select 1 from inventory i join items it on it.id = i.item_id
                       where i.user_id = p_me.id and i.qty > 0 and it.category = 'vehicle');

  foreach m in array array['walk','keke','bus','drop','car'] loop
    v_label := case m when 'walk' then 'Trek am (waka)'
                      when 'keke' then 'Keke Napep'
                      when 'bus'  then 'ECTS Green Bus'
                      when 'drop' then 'Drop (ride-hail)'
                      else 'Your own motor' end;
    v_speed := greatest(bl_cfg('travel.' || m || '.speed_kmh'), 0.1);
    v_cost  := (ceil((bl_cfg('travel.' || m || '.base_cost') + bl_cfg('travel.' || m || '.per_km') * v_km) / 10.0) * 10)::bigint;
    v_traffic := case when m = 'walk' then 1 else v_traffic_road end;
    v_gm := greatest(1, ceil(v_km / v_speed * 60 * v_traffic))::int;
    v_rs := round(greatest(bl_cfg('travel.min_real_seconds'),
                           v_gm * bl_cfg('travel.real_seconds_per_game_minute')), 1);
    v_allowed := true; v_reason := null;
    if m = 'keke' and not (src.keke_ok and dst.keke_ok) then
      v_allowed := false;
      v_reason := 'Keke no fit pass there — dem don ban keke for major road.';
    elsif m = 'car' and not v_has_car then
      v_allowed := false;
      v_reason := 'You no get motor. Buy one first, big man.';
    elsif v_cost > p_me.cash then
      v_allowed := false;
      v_reason := 'Your money no reach for this one (' || bl_naira(v_cost) || ').';
    end if;
    v_risk := round(100 * bl_street_robbery_chance(p_me.id, dst.id, m, v_traffic,
                                                   v_now + make_interval(secs => v_rs::double precision)), 1);
    v_opts := v_opts || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'mode', m, 'label', v_label, 'allowed', v_allowed, 'reason', v_reason,
      'cost', v_cost, 'game_minutes', v_gm, 'real_seconds', v_rs, 'risk_pct', v_risk)));
  end loop;

  return jsonb_build_object('dest', dst.id, 'km', v_km, 'traffic', v_traffic_road, 'options', v_opts);
end $$;

-- ---------------------------------------------------------------------
-- 4. Core RPCs
-- ---------------------------------------------------------------------

-- Read-mostly on purpose: profiles is realtime-published and the client refreshes on every profiles
-- change, so get_my_state must NOT write each call (that would echo forever). Needs decay is computed
-- in memory (persisted lazily by the next gameplay RPC via bl_me); last_seen is bumped only when it
-- is older than time.last_seen_throttle_real_seconds.
create or replace function public.get_my_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_now timestamptz := bl_now();
  v_me  profiles;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You never create your person yet. Go create am first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v_me.banned then
    raise exception 'Dem don ban this account. If na mistake, contact admin.' using errcode = 'P0001', hint = 'banned';
  end if;
  if v_me.last_seen is null
     or v_me.last_seen < v_now - make_interval(secs => bl_cfg('time.last_seen_throttle_real_seconds')::double precision) then
    update profiles set last_seen = v_now where id = v_uid returning * into v_me;
  end if;
  v_me := bl_decay_row(v_me, v_now);
  return jsonb_build_object(
    'profile', to_jsonb(v_me) - array['banned','needs_updated_at','last_seen',
                                      'travel_to','travel_mode','travel_started_at','travel_arrives_at'],
    'clock', bl_game_clock(v_now),
    'location', (select to_jsonb(l) from locations l where l.id = v_me.location_id),
    'travel', case when v_me.travel_to is null then null
                   else jsonb_build_object('to', v_me.travel_to, 'mode', v_me.travel_mode,
                                           'started_at', v_me.travel_started_at,
                                           'arrives_at', v_me.travel_arrives_at) end,
    'server_time', v_now
  );
end $$;

create or replace function public.create_profile(p_username text, p_gender text, p_avatar jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := bl_require_uid();
  v_name   text := trim(coalesce(p_username, ''));
  v_gender text := lower(trim(coalesce(p_gender, '')));
  v_avatar jsonb := coalesce(p_avatar, '{}'::jsonb);
  v_home   text := bl_cfg_text('start.home_location');
  v_now    timestamptz := bl_now();
  v_need   numeric := bl_cfg('start.need_level');
  v_cash   bigint := bl_cfg('start.cash')::bigint;
  v_bank   bigint := bl_cfg('start.bank')::bigint;
begin
  if exists (select 1 from profiles where id = v_uid) then
    raise exception 'You don already create your person. One account, one person.' using errcode = 'P0001';
  end if;
  if v_name !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'Username suppose be 3 to 20 letters, numbers or underscore (_) — no space, no funny character.'
      using errcode = 'P0001';
  end if;
  if v_gender not in ('male','female') then
    raise exception 'Pick male or female abeg.' using errcode = 'P0001';
  end if;
  if jsonb_typeof(v_avatar) <> 'object' or length(v_avatar::text) > 4000 then
    raise exception 'Your avatar data no correct. Try again.' using errcode = 'P0001';
  end if;
  if exists (select 1 from profiles where lower(username) = lower(v_name)) then
    raise exception 'Somebody don already carry "%" as username. Try another one.', v_name using errcode = 'P0001';
  end if;
  perform bl_location(v_home);

  begin
    insert into profiles (id, username, gender, avatar, cash, bank,
                          hunger, energy, hygiene, fun, social, health, stress, needs_updated_at,
                          location_id, home_location_id, housing_id,
                          protected_until, last_seen, created_at)
    values (v_uid, v_name, v_gender, v_avatar, 0, 0,
            v_need, v_need, v_need, v_need, v_need, bl_cfg('start.health'), bl_cfg('start.stress'), v_now,
            v_home, v_home, bl_cfg_text('start.housing'),
            v_now + make_interval(mins => bl_cfg('start.protection_real_minutes')::int), v_now, v_now);
  exception when unique_violation then
    raise exception 'Somebody don already carry "%" as username. Try another one.', v_name using errcode = 'P0001';
  end;

  if v_cash > 0 then perform bl_add_money(v_uid, 'cash', v_cash, 'start_bonus'); end if;
  if v_bank > 0 then perform bl_add_money(v_uid, 'bank', v_bank, 'start_bonus'); end if;
  perform bl_event(v_uid, 'welcome', 'Welcome to Benin!',
                   'Oya ' || v_name || ', you don land for Ekenwan with ' || bl_naira(v_cash)
                   || '. Find work, chop well, and no carry too much cash for night o.', '{}'::jsonb);
  return get_my_state();
end $$;

create or replace function public.update_avatar(p_avatar jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me();
begin
  if p_avatar is null or jsonb_typeof(p_avatar) <> 'object' or length(p_avatar::text) > 4000 then
    raise exception 'Your avatar data no correct. Try again.' using errcode = 'P0001';
  end if;
  update profiles set
    avatar = p_avatar,
    gender = case when p_avatar->>'gender' in ('male','female') then p_avatar->>'gender' else gender end
  where id = v_me.id;
  return jsonb_build_object('message', 'Your new look don set. You fine well well!');
end $$;

create or replace function public.travel_quote(p_dest text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me();
begin
  return bl_travel_quote(v_me, p_dest);
end $$;

create or replace function public.travel_start(p_dest text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_q     jsonb;
  v_opt   jsonb;
  v_now   timestamptz := bl_now();
  v_arr   timestamptz;
  v_name  text;
begin
  perform bl_assert_free(v_me);
  if p_mode is null or p_mode not in ('walk','keke','bus','drop','car') then
    raise exception 'That kind transport no dey for Benin.' using errcode = 'P0001';
  end if;
  v_q := bl_travel_quote(v_me, p_dest);
  select o into v_opt from jsonb_array_elements(v_q->'options') o where o->>'mode' = p_mode;
  if not (v_opt->>'allowed')::boolean then
    raise exception '%', v_opt->>'reason' using errcode = 'P0001';
  end if;
  if (v_opt->>'cost')::bigint > 0 then
    perform bl_add_money(v_me.id, 'cash', -(v_opt->>'cost')::bigint, 'travel',
                         jsonb_build_object('from', v_me.location_id, 'to', p_dest, 'mode', p_mode));
  end if;
  v_arr := v_now + make_interval(secs => (v_opt->>'real_seconds')::double precision);
  update profiles set travel_to = p_dest, travel_mode = p_mode,
                      travel_started_at = v_now, travel_arrives_at = v_arr
  where id = v_me.id;
  select name into v_name from locations where id = p_dest;
  return jsonb_build_object(
    'message', case p_mode
                 when 'walk' then 'Oya trek am! You dey waka go ' || v_name || '.'
                 when 'keke' then 'Keke don carry you go ' || v_name || '. Hold your phone well.'
                 when 'bus'  then 'You don enter ECTS bus go ' || v_name || '.'
                 when 'drop' then 'Your drop don come. E dey carry you go ' || v_name || '.'
                 else 'You don start your motor go ' || v_name || '. Drive jeje.' end,
    'arrives_at', v_arr,
    'cost', (v_opt->>'cost')::bigint,
    'game_minutes', (v_opt->>'game_minutes')::int,
    'real_seconds', (v_opt->>'real_seconds')::numeric);
end $$;

create or replace function public.travel_arrive() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me      profiles := bl_me();
  v_now     timestamptz := bl_now();
  v_from    text;
  v_dest    text;
  v_mode    text;
  v_traffic numeric;
  v_robbed  jsonb;
  v_name    text;
  v_msg     text;
begin
  if v_me.travel_to is null then
    raise exception 'You no dey travel now.' using errcode = 'P0001';
  end if;
  if v_now < v_me.travel_arrives_at then
    raise exception 'You never reach o! Like % sec remain.',
      ceil(extract(epoch from v_me.travel_arrives_at - v_now)) using errcode = 'P0001';
  end if;
  v_from := v_me.location_id; v_dest := v_me.travel_to; v_mode := v_me.travel_mode;
  v_traffic := case when v_mode = 'walk' then 1 else bl_traffic(v_from, v_dest, v_me.travel_started_at) end;

  update profiles set location_id = v_dest, travel_to = null, travel_mode = null,
                      travel_started_at = null, travel_arrives_at = null, last_seen = v_now
  where id = v_me.id;

  v_robbed := bl_roll_street_robbery(v_me.id, v_dest, v_mode, v_traffic);
  select name into v_name from locations where id = v_dest;

  if v_robbed is null then
    v_msg := 'You don reach ' || v_name || '. Welcome!';
    return jsonb_build_object('message', v_msg, 'location', v_dest);
  end if;
  v_msg := 'Omo! You reach ' || v_name || ' but some boys collect '
           || bl_naira((v_robbed->>'amount')::bigint) || ' from you. You fit report for Police.'
           || case when (v_robbed->>'injured')::boolean
                   then ' Dem wound you small — run go UBTH or clinic.' else '' end;
  return jsonb_build_object('message', v_msg, 'location', v_dest, 'robbed', v_robbed);
end $$;

create or replace function public.do_activity(p_activity text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  a       activities;
  v_scene text;
  v_until timestamptz;
begin
  perform bl_assert_free(v_me);
  select * into a from activities where id = p_activity;
  if not found then
    raise exception 'That activity no dey.' using errcode = 'P0001';
  end if;
  select scene into v_scene from locations where id = v_me.location_id;
  if not (v_scene = any(a.scenes)) then
    raise exception 'You no fit do "%" for here. Go where dem dey do am.', a.name using errcode = 'P0001';
  end if;
  if a.home_only and v_me.location_id <> v_me.home_location_id then
    raise exception 'Na for your own house you fit do "%".', a.name using errcode = 'P0001';
  end if;
  if a.night_only and not (bl_game_clock()->>'is_night')::boolean then
    raise exception '"%" na night-time thing. Come back when e don dark.', a.name using errcode = 'P0001';
  end if;
  if a.cost > 0 then
    perform bl_add_money(v_me.id, 'cash', -a.cost, 'activity', jsonb_build_object('activity', a.id));
  end if;
  perform bl_adjust_needs(v_me.id, a.effects);
  if coalesce((a.effects->>'street_cred')::int, 0) <> 0 then
    update profiles set street_cred = greatest(0, street_cred + (a.effects->>'street_cred')::int) where id = v_me.id;
  end if;
  v_until := bl_set_busy(v_me.id, a.game_minutes, a.name);
  return jsonb_build_object(
    'message', 'You don start "' || a.name || '"'
               || case when a.cost > 0 then ' — ' || bl_naira(a.cost) || ' don comot.' else '. E sweet!' end,
    'busy_until', v_until,
    'effects', a.effects);
end $$;

create or replace function public.players_here(p_location text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar,
                                        'street_cred', p.street_cred, 'last_seen', p.last_seen)
                     order by p.last_seen desc)
    from (select * from profiles
          where location_id = p_location and id <> v_uid and not banned and travel_to is null
            and last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)
          order by last_seen desc limit 50) p
  ), '[]'::jsonb);
end $$;

create or replace function public.get_public_profile(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  perform bl_require_uid();
  select jsonb_build_object('id', id, 'username', username, 'avatar', avatar, 'gender', gender,
                            'street_cred', street_cred, 'job_id', job_id, 'location_id', location_id,
                            'created_at', created_at)
    into v from profiles where id = p_id and not banned;
  if v is null then
    raise exception 'Dis person no dey.' using errcode = 'P0001';
  end if;
  return v;
end $$;

-- ---------------------------------------------------------------------
-- 5. Function privileges
-- ---------------------------------------------------------------------
-- Helpers: internal only (service_role keeps access for edge functions)
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'bl\_%' loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

-- RPCs: logged-in players only
revoke execute on function public.create_profile(text, text, jsonb) from public, anon;
revoke execute on function public.update_avatar(jsonb)            from public, anon;
revoke execute on function public.get_my_state()                  from public, anon;
revoke execute on function public.travel_quote(text)              from public, anon;
revoke execute on function public.travel_start(text, text)        from public, anon;
revoke execute on function public.travel_arrive()                 from public, anon;
revoke execute on function public.do_activity(text)               from public, anon;
revoke execute on function public.players_here(text)              from public, anon;
revoke execute on function public.get_public_profile(uuid)        from public, anon;
grant execute on function public.create_profile(text, text, jsonb) to authenticated;
grant execute on function public.update_avatar(jsonb)            to authenticated;
grant execute on function public.get_my_state()                  to authenticated;
grant execute on function public.travel_quote(text)              to authenticated;
grant execute on function public.travel_start(text, text)        to authenticated;
grant execute on function public.travel_arrive()                 to authenticated;
grant execute on function public.do_activity(text)               to authenticated;
grant execute on function public.players_here(text)              to authenticated;
grant execute on function public.get_public_profile(uuid)        to authenticated;
