-- Power cuts (docs/POWER.md): NEPA takes light by area, generators with fuel, inverters, batteries and solar.
--   1. Outages by area: every area has outage_pct (share of time the light is off). The server decides it from a hash of
--      area + cycle + a salt, so everybody in an area gets the SAME cut. No cron, no per-player rows per cut.
--      City-wide blackouts: admin starts / ends one (audited), or a rare random one per day (off by default).
--   2. power_status(): the one cheap read. It settles the player's own backup LAZILY from the last settle to now
--      (fuel burn, battery drain / recharge, solar by day) in exact segments, so nothing is counted twice.
--   3. Generators = the existing generator furniture (gen_tiger, gen_firman, gen_soundproof): tank + burn per gear table.
--      Fuel items (petrol, diesel, cans) are poured in with power_refuel. The player turns the generator on and off.
--   4. Inverter and solar = existing furniture (inverter_small, inverter_solar, solar_panels), the Solar and inverter
--      house upgrade, and two new buyable battery pieces. The inverter takes over by itself.
--   5. Effects while a home has no light (do_activity patched with guarded replaces): TV refused, bonuses shrink, rest is poorer.
--   6. Fuel price moves a little each Benin day, scarcity events (admin or rare random) raise it and dry some stations
--      (bl_shop_price + shop_buy patched with guarded replaces). Stations themselves are in 20261104000200_fuel_market.sql.
-- No profiles DDL, no foreign keys to profiles, nothing loops over players. Idempotent: tables `if not exists`, seeds
-- `on conflict do nothing`, functions `create or replace`, live functions patched only through a guarded replace (pg_temp.pw_patch).

create or replace function pg_temp.pw_patch(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n <> 1 then raise exception 'power: % : marker found % times: %', p_sig, v_n, left(p_marker, 90); end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Power cuts). All with label, description, min and max.
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('power.enabled', 'true', 'power', 'Power cuts on',
 'Master switch. Off = the light never goes (every home is lit), the HUD chip hides and the generator and inverter are just furniture with comfort bonuses.', 'bool', null, null),
('power.salt', '"benin"', 'power', 'Outage shuffle word',
 'Part of the hash that decides when each area loses light. Change it to reshuffle every outage in the city at once.', 'text', null, null),
('power.cut_min_minutes', '15', 'power', 'Shortest cut (real minutes)',
 'A normal area cut lasts between this and the longest cut. Real minutes, so a cut is long enough to feel and short enough not to annoy.', 'minutes', 5, 240),
('power.cut_max_minutes', '60', 'power', 'Longest cut (real minutes)',
 'See above. Note: an area can never be off for more than about (shortest + longest) / 2 divided by its outage %, and the cycle is never shorter than the longest cut, so keep the area % under 60.', 'minutes', 5, 240),
('power.outage_pct.gra', '8', 'power', 'Outage % - GRA', 'Roughly the share of time the light is off in GRA (the best-served estates). 8 = about 2 hours a day.', 'percent', 0, 60),
('power.outage_pct.ugbowo', '20', 'power', 'Outage % - Ugbowo', 'Share of time the light is off round UNIBEN and UBTH.', 'percent', 0, 60),
('power.outage_pct.uselu', '22', 'power', 'Outage % - Uselu', 'Share of time the light is off in Uselu.', 'percent', 0, 60),
('power.outage_pct.sapele', '25', 'power', 'Outage % - Sapele Road', 'Share of time the light is off along Sapele Road.', 'percent', 0, 60),
('power.outage_pct.airport', '22', 'power', 'Outage % - Airport Road', 'Share of time the light is off along Airport Road.', 'percent', 0, 60),
('power.outage_pct.ikpoba', '30', 'power', 'Outage % - Ikpoba Hill', 'Share of time the light is off on Ikpoba Hill.', 'percent', 0, 60),
('power.outage_pct.new_benin', '28', 'power', 'Outage % - New Benin', 'Share of time the light is off in New Benin (Mission Road).', 'percent', 0, 60),
('power.outage_pct.ring_road', '25', 'power', 'Outage % - Ring Road', 'Share of time the light is off round Ring Road.', 'percent', 0, 60),
('power.outage_pct.okhoro', '33', 'power', 'Outage % - Okhoro', 'Share of time the light is off in Okhoro.', 'percent', 0, 60),
('power.outage_pct.ekenwan', '40', 'power', 'Outage % - Ekenwan', 'Share of time the light is off along Ekenwan Road (the worst served).', 'percent', 0, 60),
('power.outage_pct.aduwawa', '38', 'power', 'Outage % - Aduwawa', 'Share of time the light is off out at Aduwawa.', 'percent', 0, 60),
('power.blackout_max_hours', '12', 'power', 'Longest admin blackout (real hours)', 'The Blackout control in Admin -> Power refuses anything longer.', 'number', 0.1, 72),
('power.random_blackout_chance_pct', '0', 'power', 'Random city-wide blackout: chance per day (%)',
 'Each real day (UTC) has this chance of one city-wide blackout at a random time. 0 = never (default). Keep it tiny: 2 means about one every 50 days.', 'percent', 0, 100),
('power.random_blackout_minutes', '90', 'power', 'Random blackout length (real minutes)', 'How long a random city-wide blackout lasts.', 'minutes', 5, 1440),
('power.speed_mult', '2', 'power', 'Use speed (fuel and battery)',
 'Fast-forward for fuel burn, battery drain and charging, because a real cut lasts only 15-60 minutes. 2 = a tank or battery empties twice as fast as the table says. 1 = as listed.', 'number', 0.1, 20),
('power.mains_charge_kw', '0.5', 'power', 'Inverter charge from the mains (kW)', 'How fast batteries fill while NEPA is on (before the speed multiplier). Slow on purpose.', 'number', 0.05, 10),
('power.load_base_kw', '0.25', 'power', 'Home base load (kW)', 'Lights, charging and standby. Every placed appliance (fan, TV, fridge, AC...) adds its own load from Content -> Power gear.', 'number', 0, 10),
('power.sun_start_hour', '7', 'power', 'Solar day starts (Benin hour)', 'Panels charge between this hour and the end hour, strongest at midday.', 'number', 0, 12),
('power.sun_end_hour', '18', 'power', 'Solar day ends (Benin hour)', 'See above.', 'number', 13, 24),
('power.batt_start_pct', '50', 'power', 'New battery starts at (%)', 'A battery you have just bought or first seen starts this full.', 'percent', 0, 100),
('power.settle_gap_seconds', '5', 'power', 'Settle at most every (seconds)', 'power_status and the activity checks reuse the last settle if it is younger than this. Keeps polling cheap.', 'number', 0, 120),
('power.poll_seconds', '60', 'power', 'App polls every (seconds)', 'How often the open game asks for the power state (plus right after a power action).', 'number', 20, 600),
('power.bad_fuel_pct', '25', 'power', 'Black-market fuel: chance a pour is adulterated (%)', 'Grey petrol or diesel poured into a generator may be bad: the generator burns more fuel for a while.', 'percent', 0, 100),
('power.bad_fuel_minutes', '45', 'power', 'Bad fuel lasts (real minutes)', 'How long a bad batch makes the generator run rough, unless it is repaired first.', 'minutes', 1, 1440),
('power.bad_fuel_burn_mult', '1.6', 'power', 'Bad fuel: burn multiplier', 'While the generator runs rough it burns this many times the fuel.', 'number', 1, 5),
('power.repair_cost', '25000', 'power', 'Generator repair cost', 'Paying a mechanic clears a fault at once (ledger Generator repair, a sink).', 'naira', 0, 5000000),
('power.gen_noise_stress', '4', 'power', 'Generator noise: stress added', 'Sleeping or napping with a noisy generator running adds this much stress. Soundproof generators and a generator house add none. 0 = off.', 'number', 0, 20),
('power.effects_enabled', 'true', 'power', 'No-light effects on', 'Off = a home without light behaves as before (no refusals, no smaller bonuses).', 'bool', null, null),
('power.needs_light_activities', '"watch_tv"', 'power', 'Activities that need light', 'Comma-separated home activities refused while the home has no light ("No light").', 'text', null, null),
('power.dark_rest_pct', '85', 'power', 'Dark and hot: rest recovers (%)', 'Sleep and nap energy while the home has no light. 100 = no penalty.', 'percent', 0, 100),
('power.dark_bonus_pct', '25', 'power', 'No light: furniture bonus kept (%)', 'Fans, ACs, fridges and other piece bonuses shrink to this share while the home has no light. 0 = none.', 'percent', 0, 100),
('power.petrol_price', '1050', 'power', 'Petrol price a litre', 'Base price in naira before the daily move and scarcity. Real 2026 Benin is about 900 to 1,200.', 'naira', 100, 20000),
('power.diesel_price', '1250', 'power', 'Diesel price a litre', 'Base price in naira before the daily move and scarcity.', 'naira', 100, 20000),
('power.fuel_daily_pct', '6', 'power', 'Fuel price: daily move (%)', 'The price moves by up to this much each Benin day (the same for everybody, fixed by the date).', 'percent', 0, 50),
('power.can_discount_pct', '2', 'power', 'Jerrycan discount (%)', 'Buying a full can is this much cheaper than the same litres.', 'percent', 0, 30),
('power.scarcity_price_mult', '1.6', 'power', 'Fuel scarcity: price multiplier', 'During a scarcity event every station price is multiplied by this.', 'number', 1, 10),
('power.scarcity_dry_pct', '35', 'power', 'Fuel scarcity: stations dry (%)', 'During a scarcity event this share of stations has no fuel at all that day (fixed by date and station).', 'percent', 0, 100),
('power.queue_seconds', '0', 'power', 'Queue at the pump (real seconds), normal days', 'How long the player is busy queueing when buying fuel on a normal day.', 'number', 0, 300),
('power.queue_seconds_scarce', '25', 'power', 'Queue at the pump (real seconds), scarcity', 'The same during a fuel scarcity event.', 'number', 0, 600),
('power.scarcity_default_hours', '8', 'power', 'Admin scarcity length (real hours)', 'The default for the Start scarcity button in Admin -> Power.', 'number', 0.1, 72),
('power.random_scarcity_chance_pct', '2', 'power', 'Random fuel scarcity: chance per day (%)', 'Each real day (UTC) has this chance of a fuel scarcity at a random time. 0 = never.', 'percent', 0, 100),
('power.random_scarcity_hours', '10', 'power', 'Random scarcity length (real hours)', 'How long a random fuel scarcity lasts.', 'number', 0.1, 72)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.power_areas (
  id    text primary key check (id ~ '^[a-z0-9_]{2,24}$'),
  name  text not null,
  homes text[] not null default '{}',     -- start_homes ids that sit in this area (a property home uses its own area)
  blurb text not null default '',
  sort  int not null default 100,
  active boolean not null default true
);

create table if not exists public.power_gear (
  id        text primary key,             -- furniture id, house upgrade id or item id
  kind      text not null check (kind in ('generator','inverter','solar','battery','genhouse','appliance','fuel')),
  source    text not null default 'furniture' check (source in ('furniture','upgrade','item')),
  name      text not null default '',
  tank_l    numeric not null default 0 check (tank_l >= 0),      -- generator: tank in litres
  burn_lph  numeric not null default 0 check (burn_lph >= 0),    -- generator: litres an hour (before the speed multiplier)
  fuel      text check (fuel in ('petrol','diesel')),             -- generator: its fuel; fuel item: what it is
  soundproof boolean not null default false,
  noise     int not null default 0,
  kva       numeric not null default 0 check (kva >= 0),         -- inverter size (it exists when > 0)
  kwh       numeric not null default 0 check (kwh >= 0),         -- battery capacity added (usable kWh)
  solar_kw  numeric not null default 0 check (solar_kw >= 0),    -- panels added
  load_kw   numeric not null default 0 check (load_kw >= 0),     -- appliance: draw while placed
  litres    numeric not null default 0 check (litres >= 0),      -- fuel item: litres in one
  grey      boolean not null default false,                       -- fuel item: black-market fuel
  sort      int not null default 100,
  active    boolean not null default true
);

create table if not exists public.power_events (
  id         bigint generated always as identity primary key,
  kind       text not null check (kind in ('blackout','scarcity')),
  started_at timestamptz not null,
  ends_at    timestamptz not null,        -- the real end: "End now" moves it to now
  started_by uuid,
  note       text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists power_events_kind_end_idx on public.power_events (kind, ends_at);
create index if not exists power_events_kind_start_idx on public.power_events (kind, started_at);

-- one row per player who has a backup or ever had a notice. Keyed by user id, no foreign key to profiles.
create table if not exists public.player_power (
  user_id        uuid primary key,
  settled_at     timestamptz not null default now(),
  gen_on         boolean not null default false,
  fuel_l         numeric not null default 0 check (fuel_l >= 0),
  gen_id         text,
  gen_on_since   timestamptz,
  gen_empty_at   timestamptz,
  gen_fault_until timestamptz,
  gen_burn_mult  numeric not null default 1,
  batt_kwh       numeric not null default 0 check (batt_kwh >= 0),
  cap_seen       numeric not null default 0,
  batt_health    numeric not null default 100,
  batt_empty_at  timestamptz,
  load_kw        numeric not null default 0.25,
  ack_cut        text,
  ack_cut_until  timestamptz,
  ack_back       text,
  ack_fuel       timestamptz,
  ack_batt       timestamptz,
  push_key       text,
  push_batt_key  text,
  bm_told        boolean not null default false,
  updated_at     timestamptz not null default now()
);

alter table public.power_areas   enable row level security;
alter table public.power_gear    enable row level security;
alter table public.power_events  enable row level security;
alter table public.player_power  enable row level security;
revoke all on public.power_areas, public.power_gear, public.power_events, public.player_power from public, anon, authenticated;
grant select on public.power_areas, public.power_gear to authenticated;
grant select on public.player_power to authenticated;
drop policy if exists power_areas_read on public.power_areas;
create policy power_areas_read on public.power_areas for select to authenticated using (true);
drop policy if exists power_gear_read on public.power_gear;
create policy power_gear_read on public.power_gear for select to authenticated using (true);
drop policy if exists player_power_own on public.player_power;
create policy player_power_own on public.player_power for select to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------
-- 3. Seeds (admin edits survive: on conflict do nothing)
-- ---------------------------------------------------------------------------------------------
insert into public.power_areas (id, name, homes, blurb, sort) values
('gra',        'GRA',          '{gra_duplex}',           'Government Reserved Area: the best-served estates.', 10),
('ugbowo',     'Ugbowo',       '{uniben_hostel}',        'Round UNIBEN and UBTH.', 20),
('uselu',      'Uselu',        '{uselu_self_contain}',   'Off Lagos Road, close to the campus.', 30),
('sapele',     'Sapele Road',  '{}',                     'The busy spine road of Benin.', 40),
('airport',    'Airport Road', '{}',                     'Estates and layouts round the airport.', 50),
('ikpoba',     'Ikpoba Hill',  '{}',                     'Hill side of town.', 60),
('new_benin',  'New Benin',    '{mission_rd_mini_flat}', 'Mission Road and the market side.', 70),
('ring_road',  'Ring Road',    '{}',                     'The ring round the old city.', 80),
('okhoro',     'Okhoro',       '{}',                     'Okhoro quarters.', 90),
('ekenwan',    'Ekenwan',      '{ekenwan_face_me}',      'Ekenwan Road: the worst served.', 100),
('aduwawa',    'Aduwawa',      '{aduwawa_face_me}',      'Out east past Ramat Park.', 110)
on conflict (id) do nothing;

-- two new battery pieces (they look like the inverter box in 3D: no 3D art is added)
insert into public.furniture (id, name, emoji, kind, slot, activities, rest_pct, color, description, sort, active, price, tier, category, w, d, solid, placement, max_qty, bonus, buyable, tradeable)
values
('battery_tubular', '200Ah tubular battery', '🔋', 'inverter_small', 'none', '{}', 100, '', 'Adds 1.2 kWh to your inverter. Buy up to six.', 861, true, 340000, 'mid', 'utility', 0.45, 0.35, true, 'in', 6, '{}', true, true),
('battery_lithium', '5kWh lithium battery', '🔋', 'inverter_small', 'none', '{}', 100, '', 'Adds 5 kWh to your inverter. Light, long life, dear.', 862, true, 1700000, 'nepo', 'utility', 0.50, 0.30, true, 'in', 4, '{}', true, true)
on conflict (id) do nothing;

insert into public.power_gear (id, kind, source, name, tank_l, burn_lph, fuel, soundproof, noise, kva, kwh, solar_kw, sort) values
('gen_tiger',      'generator', 'furniture', 'Tiger gen',                5,   0.9, 'petrol', false, 6, 0, 0,   0,   10),
('gen_firman',     'generator', 'furniture', 'Firman 2.8KVA gen',       15,   1.5, 'petrol', false, 4, 0, 0,   0,   20),
('gen_soundproof', 'generator', 'furniture', 'Soundproof diesel gen',  100,   6.0, 'diesel', true,  0, 0, 0,   0,   30),
('inverter_small', 'inverter',  'furniture', '1.5KVA inverter',          0,   0,   null,     false, 0, 1.5, 1.2, 0,   40),
('inverter_solar', 'inverter',  'furniture', '3.5KVA solar inverter',    0,   0,   null,     false, 0, 3.5, 3.6, 0.5, 50),
('solar_panels',   'solar',     'furniture', 'Solar panels',             0,   0,   null,     false, 0, 0,   0,   1.5, 60),
('battery_tubular','battery',   'furniture', '200Ah tubular battery',    0,   0,   null,     false, 0, 0,   1.2, 0,   70),
('battery_lithium','battery',   'furniture', '5kWh lithium battery',     0,   0,   null,     false, 0, 0,   5,   0,   80),
('solar_system',   'inverter',  'upgrade',   'Solar and inverter system',0,   0,   null,     false, 0, 3.5, 4.8, 2,   90),
('gen_house',      'genhouse',  'upgrade',   'Generator house',          0,   0,   null,     true,  0, 0, 0,   0,   100)
on conflict (id) do nothing;

insert into public.power_gear (id, kind, source, name, fuel, litres, grey, sort) values
('petrol',      'fuel', 'item', 'Petrol (1 litre)',            'petrol', 1,  false, 200),
('petrol_can',  'fuel', 'item', 'Petrol jerrycan (5 litres)',  'petrol', 5,  false, 201),
('diesel',      'fuel', 'item', 'Diesel (1 litre)',            'diesel', 1,  false, 202),
('diesel_can',  'fuel', 'item', 'Diesel jerrycan (20 litres)', 'diesel', 20, false, 203),
('petrol_bm',   'fuel', 'item', 'Grey petrol (1 litre)',       'petrol', 1,  true,  204),
('diesel_bm',   'fuel', 'item', 'Grey diesel (1 litre)',       'diesel', 1,  true,  205)
on conflict (id) do nothing;

insert into public.power_gear (id, kind, source, name, load_kw, sort)
select v.id, 'appliance', 'furniture', f.name, v.kw, 300
  from (values ('fan_ceiling', 0.07), ('fan_standing', 0.06), ('fan_rechargeable', 0.02), ('ac_split', 1.2), ('ac_standing', 2.0), ('ac_inverter', 0.8),
               ('fridge', 0.15), ('fridge_bar', 0.08), ('fridge_sbs', 0.25), ('freezer_chest', 0.2), ('tv_small', 0.05), ('tv', 0.08), ('tv_43', 0.1),
               ('tv_55', 0.15), ('tv_65', 0.2), ('tv_75', 0.25), ('washing_machine', 0.5), ('water_heater', 1.5), ('microwave', 0.6), ('chandelier', 0.2),
               ('lamp_floor', 0.02), ('lamp_bedside', 0.01), ('speaker_tower', 0.1), ('speaker_bt', 0.01), ('radio', 0.01)) as v(id, kw)
  join public.furniture f on f.id = v.id
on conflict (id) do nothing;

-- fuel items (the shelf is the filling stations, see 20261104000200_fuel_market.sql; the price comes from bl_fuel_price)
insert into public.items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort, tradeable)
values
('petrol',     'Petrol (1 litre)',            'fuel', 1050,  'Pour it into your generator from the Power sheet.', '{}', '{}', false, 0, '⛽', 900, false),
('petrol_can', 'Petrol jerrycan (5 litres)',  'fuel', 5150,  'Five litres. Pour it into your generator from the Power sheet.', '{}', '{}', false, 0, '🛢️', 901, false),
('diesel',     'Diesel (1 litre)',            'fuel', 1250,  'For the big diesel generator.', '{}', '{}', false, 0, '⛽', 902, false),
('diesel_can', 'Diesel jerrycan (20 litres)', 'fuel', 24500, 'Twenty litres of diesel.', '{}', '{}', false, 0, '🛢️', 903, false),
('petrol_bm',  'Grey petrol (1 litre)',       'fuel', 850,   'No receipt, no questions. It may be adulterated.', '{}', '{}', false, 0, '⛽', 904, false),
('diesel_bm',  'Grey diesel (1 litre)',       'fuel', 1000,  'No receipt, no questions. It may be adulterated.', '{}', '{}', false, 0, '⛽', 905, false)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Small helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_power_h(p_key text) returns double precision
language sql immutable set search_path = public as $$
  select (('x' || substr(md5(p_key), 1, 8))::bit(32)::bigint)::double precision / 4294967296.0
$$;

create or replace function public.bl_power_num(p_key text, p_def numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from public.game_config where key = p_key), p_def)
$$;

create or replace function public.bl_power_on() returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from public.game_config where key = 'power.enabled'), true)
$$;

create or replace function public.bl_power_salt() returns text
language sql stable set search_path = public as $$
  select coalesce((select value #>> '{}' from public.game_config where key = 'power.salt'), 'benin')
$$;

-- ---------------------------------------------------------------------------------------------
-- 5. Mains: is the light on in an area at an instant? (pure, no writes)
--    Each area has a cycle of  mean_cut / outage%  seconds. Every cycle holds exactly one cut whose length (min..max) and
--    place inside the cycle come from a hash of area + cycle number + salt. Long run share of time off = outage%.
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_power_area_scan(p_area text, p_t double precision,
  out off boolean, out nxt double precision, out since double precision)
language plpgsql stable set search_path = public as $$
declare
  v_pct numeric := bl_power_num('power.outage_pct.' || p_area, 0);
  v_min numeric := greatest(1, bl_power_num('power.cut_min_minutes', 15)) * 60;
  v_max numeric;
  v_cyc double precision; v_phase double precision; v_salt text := bl_power_salt();
  v_k bigint; kk bigint; s double precision; e double precision; d double precision;
begin
  off := false; nxt := null; since := null;
  v_max := greatest(v_min, bl_power_num('power.cut_max_minutes', 60) * 60);
  if v_pct <= 0 then return; end if;
  if v_pct >= 100 then off := true; since := floor(p_t / 86400) * 86400; return; end if;
  v_cyc := greatest(v_max, ((v_min + v_max) / 2) * 100 / v_pct);
  v_phase := floor(bl_power_h(p_area || ':phase:' || v_salt) * v_cyc);
  v_k := floor((p_t + v_phase) / v_cyc);
  for kk in v_k .. v_k + 1 loop
    d := v_min + bl_power_h(p_area || ':' || kk || ':d:' || v_salt) * (v_max - v_min);
    s := kk * v_cyc - v_phase + bl_power_h(p_area || ':' || kk || ':o:' || v_salt) * (v_cyc - d);
    e := s + d;
    if s <= p_t and p_t < e then off := true; since := s; end if;
    if s > p_t and (nxt is null or s < nxt) then nxt := s; end if;
    if e > p_t and (nxt is null or e < nxt) then nxt := e; end if;
  end loop;
end $$;

-- city-wide events (kind blackout or scarcity): admin rows plus the optional rare random one per day
create or replace function public.bl_power_event_scan(p_kind text, p_t double precision,
  out active boolean, out nxt double precision, out since double precision, out ends double precision)
language plpgsql stable set search_path = public as $$
declare
  v_ts timestamptz := to_timestamp(p_t);
  v_chance numeric; v_dur double precision; v_salt text := bl_power_salt();
  d bigint; dd bigint; s double precision; e double precision; x double precision;
begin
  active := false; nxt := null; since := null; ends := null;
  select extract(epoch from started_at), extract(epoch from ends_at) into s, e
    from power_events where kind = p_kind and started_at <= v_ts and ends_at > v_ts order by started_at limit 1;
  if found then active := true; since := s; ends := e; end if;
  select min(z) into x from (
    select extract(epoch from started_at) z from power_events where kind = p_kind and started_at > v_ts and started_at < v_ts + interval '3 days'
    union all
    select extract(epoch from ends_at) z from power_events where kind = p_kind and ends_at > v_ts and started_at <= v_ts) q;
  nxt := x;
  if p_kind = 'blackout' then
    v_chance := bl_power_num('power.random_blackout_chance_pct', 0);
    v_dur := bl_power_num('power.random_blackout_minutes', 90) * 60;
  else
    v_chance := bl_power_num('power.random_scarcity_chance_pct', 0);
    v_dur := bl_power_num('power.random_scarcity_hours', 10) * 3600;
  end if;
  v_dur := least(86000, greatest(60, v_dur));
  if v_chance > 0 then
    d := floor(p_t / 86400);
    for dd in d .. d + 1 loop
      if bl_power_h(p_kind || ':rd:' || dd || ':' || v_salt) * 100 < v_chance then
        s := dd * 86400 + bl_power_h(p_kind || ':ro:' || dd || ':' || v_salt) * (86400 - v_dur);
        e := s + v_dur;
        if s <= p_t and p_t < e then active := true; since := coalesce(since, s); ends := greatest(coalesce(ends, e), e); end if;
        if s > p_t and (nxt is null or s < nxt) then nxt := s; end if;
        if e > p_t and (nxt is null or e < nxt) then nxt := e; end if;
      end if;
    end loop;
  end if;
end $$;

create or replace function public.bl_power_mains(p_area text, p_t double precision,
  out mains_on boolean, out nxt double precision, out city boolean, out since double precision)
language plpgsql stable set search_path = public as $$
declare a record; b record;
begin
  mains_on := true; nxt := null; city := false; since := null;
  if not bl_power_on() then return; end if;
  select * into a from bl_power_area_scan(p_area, p_t);
  select * into b from bl_power_event_scan('blackout', p_t);
  city := coalesce(b.active, false);
  mains_on := not (coalesce(a.off, false) or city);
  since := case when city then b.since else a.since end;
  nxt := case when a.nxt is null then b.nxt when b.nxt is null then a.nxt else least(a.nxt, b.nxt) end;
end $$;

-- when does the light flip (off -> on, or on -> off)? null when it never does inside the look-ahead
create or replace function public.bl_power_flip_at(p_area text, p_t double precision) returns timestamptz
language plpgsql stable set search_path = public as $$
declare cur boolean; x double precision := p_t; n double precision; i int := 0;
begin
  cur := (bl_power_mains(p_area, p_t)).mains_on;
  while i < 14 loop
    i := i + 1;
    n := (bl_power_mains(p_area, x)).nxt;
    if n is null then return null; end if;
    x := n + 0.001;
    if (bl_power_mains(p_area, x)).mains_on <> cur then return to_timestamp(n); end if;
  end loop;
  return null;
end $$;

-- which area is this player's home in? Property homes carry their own area; city homes map through power_areas.homes.
create or replace function public.bl_power_area_of(p_uid uuid) returns text
language sql stable set search_path = public as $$
  select coalesce(
    (select pr.area from public.player_residence r join public.properties pr on pr.id = r.property_id
      where r.user_id = p_uid and exists (select 1 from public.power_areas a where a.id = pr.area)),
    (select a.id from public.profiles p join public.power_areas a on p.start_home = any (a.homes) where p.id = p_uid order by a.sort limit 1),
    'new_benin')
$$;

create or replace function public.bl_power_area_name(p_area text) returns text
language sql stable set search_path = public as $$
  select coalesce((select name from public.power_areas where id = p_area), initcap(replace(p_area, '_', ' ')))
$$;

-- ---------------------------------------------------------------------------------------------
-- 6. Gear and load of a home
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_power_gear(p_uid uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  gen public.power_gear; g record;
  v_inv boolean := false; v_cap numeric := 0; v_solar numeric := 0; v_kva numeric := 0; v_gh boolean := false;
begin
  select pg.* into gen from public.power_gear pg
    join public.player_furniture pf on pf.furniture_id = pg.id and pf.user_id = p_uid and pf.qty > 0
   where pg.source = 'furniture' and pg.kind = 'generator' and pg.active order by pg.tank_l desc, pg.id limit 1;
  for g in
    select pg.kind, pg.kva, pg.kwh, pg.solar_kw, coalesce(pf.qty, 1) as q
      from public.power_gear pg
      left join public.player_furniture pf on pg.source = 'furniture' and pf.furniture_id = pg.id and pf.user_id = p_uid
      left join public.player_house_upgrades pu on pg.source = 'upgrade' and pu.upgrade_id = pg.id and pu.user_id = p_uid and pu.done_at is not null
     where pg.active and pg.kind in ('inverter', 'solar', 'battery', 'genhouse')
       and ((pg.source = 'furniture' and pf.qty > 0) or (pg.source = 'upgrade' and pu.upgrade_id is not null)) loop
    if g.kind = 'genhouse' then v_gh := true; continue; end if;
    if g.kva > 0 then v_inv := true; end if;
    v_kva := v_kva + g.kva * g.q;
    v_cap := v_cap + g.kwh * g.q;
    v_solar := v_solar + g.solar_kw * g.q;
  end loop;
  if not v_inv then v_cap := 0; v_solar := 0; end if;
  return jsonb_build_object('gen_id', gen.id, 'gen_name', gen.name, 'gen_tank', gen.tank_l, 'gen_burn', gen.burn_lph, 'gen_fuel', gen.fuel,
    'gen_soundproof', coalesce(gen.soundproof, false) or v_gh, 'gen_noise', coalesce(gen.noise, 0), 'genhouse', v_gh,
    'inv', v_inv, 'cap_kwh', v_cap, 'solar_kw', v_solar, 'kva', v_kva);
end $$;

create or replace function public.bl_power_load(p_uid uuid) returns numeric
language sql stable set search_path = public as $$
  select bl_power_num('power.load_base_kw', 0.25) + coalesce((
    select sum(g.load_kw) from public.player_house_furniture hf
      join public.power_gear g on g.id = bl_furniture_id_of(hf.furniture_key) and g.kind = 'appliance' and g.active
     where hf.owner_id = p_uid and not hf.stored), 0)
$$;

-- ---------------------------------------------------------------------------------------------
-- 7. Lazy settle of one player's backup (pure calc over a row, then save)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_power_blank(p_uid uuid, p_at timestamptz) returns public.player_power
language plpgsql stable set search_path = public as $$
declare r public.player_power;
begin
  select * into r from json_populate_record(null::public.player_power, json_build_object(
    'user_id', p_uid, 'settled_at', p_at, 'gen_on', false, 'fuel_l', 0, 'gen_burn_mult', 1, 'batt_kwh', 0, 'cap_seen', 0,
    'batt_health', 100, 'load_kw', bl_power_num('power.load_base_kw', 0.25), 'bm_told', false, 'updated_at', p_at));
  return r;
end $$;

create or replace function public.bl_power_calc(p_area text, p_gear jsonb, p_row public.player_power, p_at timestamptz, p_load numeric)
returns public.player_power
language plpgsql stable set search_path = public as $$
declare
  r public.player_power := p_row;
  v_speed numeric := greatest(0.01, bl_power_num('power.speed_mult', 2));
  v_charge numeric := bl_power_num('power.mains_charge_kw', 0.5);
  v_sun0 numeric := bl_power_num('power.sun_start_hour', 7);
  v_sun1 numeric := greatest(bl_power_num('power.sun_end_hour', 18), bl_power_num('power.sun_start_hour', 7) + 1);
  v_start numeric := bl_power_num('power.batt_start_pct', 50);
  v_tz text := bl_clock_tz();
  v_raw numeric := coalesce((p_gear ->> 'cap_kwh')::numeric, 0);
  v_cap numeric;
  v_solar numeric := coalesce((p_gear ->> 'solar_kw')::numeric, 0);
  v_tank numeric := (p_gear ->> 'gen_tank')::numeric;
  v_burn numeric := coalesce((p_gear ->> 'gen_burn')::numeric, 0);
  v_has_gen boolean := (p_gear ->> 'gen_id') is not null;
  at_e double precision := extract(epoch from p_at);
  t double precision; t_end double precision; dt numeric; i int := 0;
  m record; gen_run boolean; burn numeric; fault boolean; sunh int; sun numeric; net numeric; b0 numeric; fe double precision;
begin
  -- the home changed (new battery, generator sold, ...)
  v_cap := v_raw * coalesce(r.batt_health, 100) / 100;
  if v_raw > coalesce(r.cap_seen, 0) then
    r.batt_kwh := coalesce(r.batt_kwh, 0) + (v_raw - coalesce(r.cap_seen, 0)) * v_start / 100 * coalesce(r.batt_health, 100) / 100;
  end if;
  r.cap_seen := v_raw;
  r.batt_kwh := least(coalesce(r.batt_kwh, 0), v_cap);
  if not v_has_gen then
    r.gen_on := false; r.gen_id := null;
  else
    r.gen_id := p_gear ->> 'gen_id';
    r.fuel_l := least(r.fuel_l, v_tank);
  end if;
  r.load_kw := p_load;
  if r.settled_at is null then r.settled_at := p_at; end if;
  t := greatest(extract(epoch from r.settled_at), at_e - 86400);
  while t < at_e - 0.0005 and i < 400 loop
    i := i + 1;
    select * into m from bl_power_mains(p_area, t);
    t_end := at_e;
    if m.nxt is not null and m.nxt > t then t_end := least(t_end, m.nxt); end if;
    t_end := least(t_end, (floor(t / 3600) + 1) * 3600);
    gen_run := r.gen_on and r.fuel_l > 0 and v_has_gen;
    burn := 0;
    if gen_run then
      fault := r.gen_fault_until is not null and extract(epoch from r.gen_fault_until) > t;
      burn := v_burn * case when fault then r.gen_burn_mult else 1 end * v_speed;
      if burn > 0 then t_end := least(t_end, t + r.fuel_l / burn * 3600); end if;
      if fault then t_end := least(t_end, extract(epoch from r.gen_fault_until)); end if;
    end if;
    if t_end <= t then t_end := least(at_e, t + 1); end if;
    dt := (t_end - t) / 3600.0;
    if gen_run and burn > 0 then
      r.fuel_l := r.fuel_l - burn * dt;
      if r.fuel_l <= 0.0001 then r.fuel_l := 0; r.gen_on := false; r.gen_empty_at := to_timestamp(t_end); end if;
    end if;
    if v_cap > 0 then
      sunh := extract(hour from (to_timestamp(t) at time zone v_tz))::int;
      sun := case when sunh >= v_sun0 and sunh < v_sun1 then sin(pi() * (sunh + 0.5 - v_sun0) / (v_sun1 - v_sun0)) else 0 end;
      if m.mains_on then net := v_charge + v_solar * sun;
      elsif gen_run then net := v_solar * sun;
      else net := v_solar * sun - p_load;
      end if;
      net := net * v_speed;
      b0 := r.batt_kwh;
      r.batt_kwh := greatest(0, least(v_cap, b0 + net * dt));
      if net < 0 and b0 > 0 and r.batt_kwh <= 0.00001 then
        r.batt_empty_at := to_timestamp(t + least(dt, b0 / (-net)) * 3600);
      end if;
    end if;
    t := t_end;
  end loop;
  r.settled_at := p_at;
  return r;
end $$;

create or replace function public.bl_power_save(r public.player_power) returns void
language sql volatile set search_path = public as $$
  insert into public.player_power (user_id, settled_at, gen_on, fuel_l, gen_id, gen_on_since, gen_empty_at, gen_fault_until, gen_burn_mult, batt_kwh, cap_seen,
                                   batt_health, batt_empty_at, load_kw, ack_cut, ack_cut_until, ack_back, ack_fuel, ack_batt, push_key, push_batt_key, bm_told, updated_at)
  values (r.user_id, r.settled_at, r.gen_on, r.fuel_l, r.gen_id, r.gen_on_since, r.gen_empty_at, r.gen_fault_until, r.gen_burn_mult, r.batt_kwh, r.cap_seen,
          r.batt_health, r.batt_empty_at, r.load_kw, r.ack_cut, r.ack_cut_until, r.ack_back, r.ack_fuel, r.ack_batt, r.push_key, r.push_batt_key, r.bm_told, now())
  on conflict (user_id) do update set settled_at = excluded.settled_at, gen_on = excluded.gen_on, fuel_l = excluded.fuel_l, gen_id = excluded.gen_id,
    gen_on_since = excluded.gen_on_since, gen_empty_at = excluded.gen_empty_at, gen_fault_until = excluded.gen_fault_until, gen_burn_mult = excluded.gen_burn_mult,
    batt_kwh = excluded.batt_kwh, cap_seen = excluded.cap_seen, batt_health = excluded.batt_health, batt_empty_at = excluded.batt_empty_at,
    load_kw = excluded.load_kw, ack_cut = excluded.ack_cut, ack_cut_until = excluded.ack_cut_until, ack_back = excluded.ack_back, ack_fuel = excluded.ack_fuel,
    ack_batt = excluded.ack_batt, push_key = excluded.push_key, push_batt_key = excluded.push_batt_key, bm_told = excluded.bm_told, updated_at = now()
$$;

-- the player's own row, settled to now. A player with no backup and no notices has no row: a blank one is returned and not saved.
create or replace function public.bl_power_settle(p_uid uuid, p_force boolean default false) returns public.player_power
language plpgsql volatile set search_path = public as $$
declare
  r public.player_power; v_gear jsonb; v_now timestamptz := bl_now(); v_found boolean;
  v_gap numeric := bl_power_num('power.settle_gap_seconds', 5);
begin
  select * into r from public.player_power where user_id = p_uid for update;
  v_found := found;
  v_gear := bl_power_gear(p_uid);
  if not v_found then
    if (v_gear ->> 'gen_id') is null and not (v_gear ->> 'inv')::boolean then
      return bl_power_blank(p_uid, v_now);
    end if;
    r := bl_power_blank(p_uid, v_now);
  elsif not p_force and r.settled_at > v_now - make_interval(secs => v_gap::double precision) and r.settled_at <= v_now then
    return r;
  end if;
  r := bl_power_calc(bl_power_area_of(p_uid), v_gear, r, v_now, bl_power_load(p_uid));
  perform bl_power_save(r);
  return r;
end $$;

-- the same for somebody else's home (a visitor sees the host's light), never saved
create or replace function public.bl_power_peek(p_owner uuid) returns public.player_power
language plpgsql stable set search_path = public as $$
declare r public.player_power; v_now timestamptz := bl_now();
begin
  select * into r from public.player_power where user_id = p_owner;
  if not found then r := bl_power_blank(p_owner, v_now); end if;
  return bl_power_calc(bl_power_area_of(p_owner), bl_power_gear(p_owner), r, v_now, r.load_kw);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. The state as the client sees it
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_power_view(p_owner uuid, r public.player_power, p_visit boolean) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_now timestamptz := bl_now(); t double precision := extract(epoch from v_now);
  v_area text := bl_power_area_of(p_owner); m record; v_gear jsonb := bl_power_gear(p_owner);
  v_speed numeric := greatest(0.01, bl_power_num('power.speed_mult', 2));
  v_tz text := bl_clock_tz(); v_sun0 numeric := bl_power_num('power.sun_start_hour', 7);
  v_sun1 numeric := greatest(bl_power_num('power.sun_end_hour', 18), bl_power_num('power.sun_start_hour', 7) + 1);
  v_cap numeric := coalesce((v_gear ->> 'cap_kwh')::numeric, 0) * coalesce(r.batt_health, 100) / 100;
  v_solar numeric := coalesce((v_gear ->> 'solar_kw')::numeric, 0);
  v_has_gen boolean := (v_gear ->> 'gen_id') is not null; v_inv boolean := coalesce((v_gear ->> 'inv')::boolean, false);
  sunh int; sun numeric; solar_now numeric; v_fault boolean; v_burn numeric; v_gen_run boolean; v_batt_ok boolean;
  v_source text; v_lit boolean; v_hours numeric; v_gen_hours numeric; v_batt_hours numeric; v_kind text; v_until timestamptz;
  v_load numeric := coalesce(r.load_kw, bl_power_num('power.load_base_kw', 0.25)); v_kinds jsonb := '[]'::jsonb; v_pct numeric;
  v_ev record;
begin
  select * into m from bl_power_mains(v_area, t);
  v_until := bl_power_flip_at(v_area, t);
  sunh := extract(hour from (v_now at time zone v_tz))::int;
  sun := case when sunh >= v_sun0 and sunh < v_sun1 then sin(pi() * (sunh + 0.5 - v_sun0) / (v_sun1 - v_sun0)) else 0 end;
  solar_now := v_solar * sun;
  v_fault := r.gen_fault_until is not null and r.gen_fault_until > v_now;
  v_burn := coalesce((v_gear ->> 'gen_burn')::numeric, 0) * case when v_fault then r.gen_burn_mult else 1 end * v_speed;
  v_gen_run := v_has_gen and r.gen_on and r.fuel_l > 0;
  v_batt_ok := v_inv and v_cap > 0 and r.batt_kwh > 0.0001;
  v_pct := case when v_cap > 0 then round(r.batt_kwh / v_cap * 100) else 0 end;
  if m.mains_on then v_source := 'mains'; v_lit := true;
  elsif v_gen_run then v_source := 'generator'; v_lit := true;
  elsif v_batt_ok then v_source := case when solar_now >= v_load and solar_now > 0 then 'solar' else 'battery' end; v_lit := true;
  else v_source := 'none'; v_lit := false;
  end if;
  v_gen_hours := case when v_has_gen and v_burn > 0 then r.fuel_l / v_burn end;
  v_batt_hours := case when v_batt_ok and (v_load - solar_now) * v_speed > 0 then r.batt_kwh / ((v_load - solar_now) * v_speed) end;
  v_hours := case v_source when 'generator' then v_gen_hours when 'battery' then v_batt_hours else null end;
  if v_has_gen then v_kinds := v_kinds || '["generator"]'::jsonb; end if;
  if v_inv then v_kinds := v_kinds || '["inverter"]'::jsonb; end if;
  if v_inv and v_solar > 0 then v_kinds := v_kinds || '["solar"]'::jsonb; end if;
  v_kind := case when v_inv and v_solar > 0 then 'solar' when v_inv then 'inverter' when v_has_gen then 'generator' else 'none' end;
  select * into v_ev from bl_power_event_scan('blackout', t);
  return jsonb_build_object(
    'enabled', true, 'visiting', p_visit,
    'area', jsonb_build_object('id', v_area, 'name', bl_power_area_name(v_area), 'outage_pct', bl_power_num('power.outage_pct.' || v_area, 0)),
    'mains', case when m.mains_on then 'on' else 'off' end, 'until', v_until, 'city', coalesce(m.city, false),
    'cut_key', case when m.mains_on then null when m.city then 'city:' || floor(m.since)::bigint else v_area || ':' || floor(m.since)::bigint end,
    'source', v_source, 'lit', v_lit, 'hours_left', case when v_hours is null then null else round(v_hours, 2) end,
    'load_kw', round(v_load, 2),
    'backup', jsonb_build_object('kind', v_kind, 'kinds', v_kinds,
      'generator', case when v_has_gen then jsonb_build_object('id', v_gear ->> 'gen_id', 'name', v_gear ->> 'gen_name', 'on', r.gen_on, 'running', v_gen_run,
          'fuel_l', round(r.fuel_l, 2), 'tank_l', (v_gear ->> 'gen_tank')::numeric, 'fuel', v_gear ->> 'gen_fuel',
          'burn_lph', round(v_burn, 2), 'hours_left', case when v_gen_hours is null then null else round(v_gen_hours, 2) end,
          'soundproof', (v_gear ->> 'gen_soundproof')::boolean, 'noisy', r.gen_on and not (v_gear ->> 'gen_soundproof')::boolean,
          'fault_until', case when v_fault then r.gen_fault_until end, 'faulty', v_fault, 'empty', r.fuel_l <= 0.0001) end,
      'inverter', case when v_inv then jsonb_build_object('kva', (v_gear ->> 'kva')::numeric, 'kwh', round(r.batt_kwh, 2), 'cap_kwh', round(v_cap, 2),
          'pct', v_pct, 'hours_left', case when v_batt_hours is null then null else round(v_batt_hours, 2) end, 'solar_kw', v_solar,
          'solar_now_kw', round(solar_now, 2), 'solar_covers', solar_now >= v_load and solar_now > 0, 'empty', r.batt_kwh <= 0.0001,
          'health', coalesce(r.batt_health, 100)) end),
    'fuel_l', round(coalesce(r.fuel_l, 0), 2), 'battery_pct', v_pct,
    'blackout', case when v_ev.active then jsonb_build_object('ends', to_timestamp(v_ev.ends)) end);
end $$;

-- fuel the player carries (poured in with power_refuel)
create or replace function public.bl_power_bag(p_uid uuid) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('item', g.id, 'name', it.name, 'qty', i.qty, 'litres', g.litres, 'fuel', g.fuel, 'grey', g.grey, 'icon', it.icon)
                           order by g.sort), '[]'::jsonb)
    from public.inventory i join public.power_gear g on g.id = i.item_id and g.kind = 'fuel' join public.items it on it.id = i.item_id
   where i.user_id = p_uid and i.qty > 0
$$;

-- is this player's home lit right now? (own home settles; a visited home is the host's)
create or replace function public.bl_power_lit(p_uid uuid) returns boolean
language plpgsql volatile set search_path = public as $$
declare v_host uuid; r public.player_power;
begin
  if not bl_power_on() then return true; end if;
  select home_visit_host_id into v_host from public.profiles where id = p_uid;
  if v_host is not null then
    r := bl_power_peek(v_host);
    return (bl_power_view(v_host, r, true) ->> 'lit')::boolean;
  end if;
  r := bl_power_settle(p_uid);
  return (bl_power_view(p_uid, r, false) ->> 'lit')::boolean;
end $$;

-- the black market (docs/POWER.md): unlocked by street cred or by belonging to a crew. Used by the map policy, the status whisper
-- and the market itself (20261104000200_fuel_market.sql).
create or replace function public.bl_bm_unlocked(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from public.game_config where key = 'blackmarket.enabled'), true)
     and p_uid is not null
     and (coalesce((select street_cred from public.profiles where id = p_uid), 0) >= bl_power_num('blackmarket.unlock_cred', 20)
          or (coalesce((select (value #>> '{}')::boolean from public.game_config where key = 'blackmarket.crew_unlocks'), true)
              and exists (select 1 from public.crew_members where user_id = p_uid)))
$$;

-- ---------------------------------------------------------------------------------------------
-- 9. Push (category Game events). One per outage per player, scheduled ahead when the app is open (no cron): the outage
--    is deterministic, so a push for the next cut waits in the outbox until the cut starts.
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_power_push(p_uid uuid, p_kind text, p_key text, p_title text, p_body text, p_at timestamptz) returns void
language plpgsql volatile set search_path = public as $$
declare v_id bigint;
begin
  update public.push_outbox set status = 'skipped' where user_id = p_uid and kind = p_kind and status = 'pending';
  v_id := bl_push_enqueue(p_uid, 'events', p_kind, p_title, p_body, '/play?go=power', null, null, null, p_kind || ':' || p_key, false, null);
  if v_id is not null then update public.push_outbox set send_after = greatest(p_at, now()) where id = v_id; end if;
exception when others then null;
end $$;

create or replace function public.bl_power_push_cancel(p_uid uuid, p_kind text) returns void
language sql volatile set search_path = public as $$
  update public.push_outbox set status = 'skipped' where user_id = p_uid and kind = p_kind and status = 'pending'
$$;

-- ---------------------------------------------------------------------------------------------
-- 10. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.power_status() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_host uuid; r public.player_power; v jsonb; v_notices jsonb := '[]'::jsonb;
  v_key text; v_now timestamptz := bl_now(); v_next timestamptz; v_area text; v_gen jsonb; v_inv jsonb; v_dirty boolean := false;
  v_hours numeric; v_visit boolean;
begin
  if not bl_power_on() then
    return jsonb_build_object('enabled', false, 'lit', true, 'mains', 'on', 'source', 'mains', 'backup', jsonb_build_object('kind', 'none', 'kinds', '[]'::jsonb),
                              'poll_seconds', bl_power_num('power.poll_seconds', 60));
  end if;
  select home_visit_host_id into v_host from public.profiles where id = v_uid;
  v_visit := v_host is not null;
  r := bl_power_settle(v_uid);
  if v_visit then v := bl_power_view(v_host, bl_power_peek(v_host), true);
  else v := bl_power_view(v_uid, r, false); end if;
  v_gen := nullif(v #> '{backup,generator}', 'null'::jsonb); v_inv := nullif(v #> '{backup,inverter}', 'null'::jsonb);
  v_area := v #>> '{area,id}'; v_key := v ->> 'cut_key';

  if not v_visit then
    -- notices the client turns into cards (nothing is stored until the player sees them: power_ack)
    if v ->> 'mains' = 'off' and v_key is distinct from r.ack_cut then
      v_notices := v_notices || jsonb_build_array(jsonb_build_object('kind',
        case when v_gen is not null and (v_gen ->> 'running')::boolean then 'outage_gen_on'
             when v ->> 'source' in ('battery', 'solar') then 'outage_inverter'
             when v_gen is not null and not (v_gen ->> 'empty')::boolean then 'outage_gen'
             when v_gen is not null then 'outage_nofuel'
             when v_inv is not null then 'outage_inverter_empty'
             else 'outage_none' end, 'key', v_key));
    elsif v ->> 'mains' = 'on' and r.ack_cut is not null and r.ack_cut is distinct from r.ack_back
          and r.ack_cut_until is not null and r.ack_cut_until > v_now - interval '10 minutes' then
      v_notices := v_notices || jsonb_build_array(jsonb_build_object('kind', case when v_gen is not null and (v_gen ->> 'on')::boolean then 'back_gen_on' else 'back' end, 'key', r.ack_cut));
    end if;
    if v_gen is not null and r.gen_empty_at is not null and r.gen_empty_at > coalesce(r.ack_fuel, '-infinity') and r.gen_empty_at > v_now - interval '30 minutes' then
      v_notices := v_notices || jsonb_build_array(jsonb_build_object('kind', 'fuel_empty', 'key', extract(epoch from r.gen_empty_at)::bigint::text));
    end if;
    if v_inv is not null and r.batt_empty_at is not null and r.batt_empty_at > coalesce(r.ack_batt, '-infinity') and r.batt_empty_at > v_now - interval '30 minutes'
       and v ->> 'mains' = 'off' then
      v_notices := v_notices || jsonb_build_array(jsonb_build_object('kind', 'battery_empty', 'key', extract(epoch from r.batt_empty_at)::bigint::text));
    end if;
    -- push: tell an opted-in player about the NEXT cut once; and when the battery will be flat during this one
    if v ->> 'mains' = 'on' and v ->> 'until' is not null then
      v_next := (v ->> 'until')::timestamptz;
      if v_next - v_now <= interval '3 hours' and r.push_key is distinct from (v_area || ':' || extract(epoch from v_next)::bigint) then
        perform bl_power_push(v_uid, 'power_cut', v_area || ':' || extract(epoch from v_next)::bigint,
          case when (v ->> 'city')::boolean then 'NEPA don take light for all of Benin' else 'NEPA don take light for ' || (v #>> '{area,name}') end,
          case when v_gen is not null then 'Open the game and turn on your generator.' when v_inv is not null then 'Your inverter go take over.' else 'You no get generator or inverter.' end, v_next);
        r.push_key := v_area || ':' || extract(epoch from v_next)::bigint; v_dirty := true;
      end if;
    elsif v ->> 'mains' = 'off' and v_inv is not null and v ->> 'source' = 'battery' and (v ->> 'hours_left') is not null
          and r.push_batt_key is distinct from v_key then
      v_hours := (v ->> 'hours_left')::numeric;
      if v ->> 'until' is null or v_now + make_interval(secs => (v_hours * 3600 * 0.9)::double precision) < (v ->> 'until')::timestamptz then
        perform bl_power_push(v_uid, 'power_batt', v_key, 'Battery low', 'Your inverter battery is almost flat. NEPA never come back yet.',
                              v_now + make_interval(secs => (v_hours * 3600 * 0.9)::double precision));
      end if;
      r.push_batt_key := v_key; v_dirty := true;
    end if;
    -- the one-off whisper about the black market
    if not r.bm_told and bl_bm_unlocked(v_uid) then
      v_notices := v_notices || jsonb_build_array(jsonb_build_object('kind', 'bm_unlocked', 'key', 'bm'));
    end if;
    if v_dirty then perform bl_power_save(r); end if;
  end if;

  return v || jsonb_build_object('notices', v_notices, 'bag', bl_power_bag(v_uid), 'poll_seconds', bl_power_num('power.poll_seconds', 60),
    'effects', bl_power_on() and coalesce((select (value #>> '{}')::boolean from game_config where key = 'power.effects_enabled'), true),
    'server_time', v_now);
end $$;

create or replace function public.power_ack(p_kind text, p_key text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); r public.player_power; v jsonb; v_until timestamptz; v_key text := left(coalesce(p_key, ''), 80);
begin
  if p_kind not in ('outage', 'back', 'fuel', 'batt', 'bm') then
    raise exception 'Unknown notice.' using errcode = 'P0001', hint = 'bad_kind';
  end if;
  select * into r from public.player_power where user_id = v_uid for update;
  if not found then r := bl_power_blank(v_uid, bl_now()); end if;
  if p_kind = 'outage' then
    r.ack_cut := v_key;
    v := bl_power_view(v_uid, r, false);
    r.ack_cut_until := coalesce((v ->> 'until')::timestamptz, bl_now() + interval '1 hour');
  elsif p_kind = 'back' then r.ack_back := v_key;
  elsif p_kind = 'bm' then r.bm_told := true;
  elsif p_kind = 'fuel' then r.ack_fuel := coalesce(to_timestamp(nullif(v_key, '')::double precision), bl_now());
  else r.ack_batt := coalesce(to_timestamp(nullif(v_key, '')::double precision), bl_now());
  end if;
  perform bl_power_save(r);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.power_gen_toggle(p_on boolean) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); r public.player_power; v jsonb; v_g jsonb; v_hours numeric;
begin
  perform bl_assert_free(bl_me());
  if not bl_power_on() then
    raise exception 'Power cuts are off right now.' using errcode = 'P0001', hint = 'power_off';
  end if;
  r := bl_power_settle(v_uid, true);
  if r.gen_id is null and (bl_power_gear(v_uid) ->> 'gen_id') is null then
    raise exception 'You no get generator. Buy one in Buy -> Outside.' using errcode = 'P0001', hint = 'no_generator';
  end if;
  select * into r from public.player_power where user_id = v_uid for update;
  if p_on and r.fuel_l <= 0.0001 then
    raise exception 'Fuel don finish. Buy fuel first.' using errcode = 'P0001', hint = 'no_fuel';
  end if;
  if p_on and not r.gen_on then
    r.gen_on := true; r.gen_on_since := bl_now(); r.gen_empty_at := null;
  elsif not p_on then
    r.gen_on := false; r.gen_on_since := null;
  end if;
  perform bl_power_save(r);
  perform bl_power_push_cancel(v_uid, 'power_fuel');
  v := bl_power_view(v_uid, r, false);
  v_g := nullif(v #> '{backup,generator}', 'null'::jsonb);
  if p_on and (v_g ->> 'hours_left') is not null then
    v_hours := (v_g ->> 'hours_left')::numeric;
    perform bl_power_push(v_uid, 'power_fuel', extract(epoch from r.gen_on_since)::bigint::text, 'Fuel don finish', 'Your generator has stopped. Buy fuel.',
                          bl_now() + make_interval(secs => (v_hours * 3600)::double precision));
  end if;
  return v || jsonb_build_object('message', case when p_on then 'Generator on. Note: it burns fuel while it runs, even when NEPA is on.' else 'Generator off.' end);
end $$;

create or replace function public.power_refuel(p_item text, p_qty int default 1) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); r public.player_power; g public.power_gear; v_gear jsonb; v_tank numeric; v_free numeric; v_units int; v_l numeric;
  v_bad boolean := false; v_msg text; v_have int; v_fuel text;
begin
  perform bl_assert_free(bl_me());
  if p_qty is null or p_qty < 1 or p_qty > 500 then
    raise exception 'Pick how many.' using errcode = 'P0001', hint = 'bad_qty';
  end if;
  select * into g from public.power_gear where id = p_item and kind = 'fuel' and active;
  if not found then raise exception 'That is not fuel.' using errcode = 'P0001', hint = 'not_fuel'; end if;
  v_gear := bl_power_gear(v_uid);
  if (v_gear ->> 'gen_id') is null then
    raise exception 'You no get generator to pour am into.' using errcode = 'P0001', hint = 'no_generator';
  end if;
  v_fuel := v_gear ->> 'gen_fuel';
  if g.fuel is distinct from v_fuel then
    raise exception 'Your generator takes %, not %.', v_fuel, g.fuel using errcode = 'P0001', hint = 'wrong_fuel';
  end if;
  r := bl_power_settle(v_uid, true);
  select * into r from public.player_power where user_id = v_uid for update;
  v_tank := (v_gear ->> 'gen_tank')::numeric;
  v_free := v_tank - r.fuel_l;
  v_units := least(p_qty, floor(v_free / g.litres)::int);
  if v_units < 1 then
    raise exception 'The tank is full (% of % litres).', round(r.fuel_l, 1), v_tank using errcode = 'P0001', hint = 'tank_full';
  end if;
  select qty into v_have from public.inventory where user_id = v_uid and item_id = g.id;
  if coalesce(v_have, 0) < v_units then
    raise exception 'You only have % of those. Buy fuel at a filling station.', coalesce(v_have, 0) using errcode = 'P0001', hint = 'no_fuel_item';
  end if;
  perform bl_give_item(v_uid, g.id, -v_units);
  v_l := v_units * g.litres;
  r.fuel_l := least(v_tank, r.fuel_l + v_l);
  r.gen_empty_at := null;
  v_msg := 'Poured ' || v_l || ' litres. Tank: ' || round(r.fuel_l, 1) || ' of ' || v_tank || ' litres.';
  if g.grey and bl_rand() * 100 < bl_power_num('power.bad_fuel_pct', 25) then
    v_bad := true;
    r.gen_fault_until := bl_now() + make_interval(mins => bl_power_num('power.bad_fuel_minutes', 45)::int);
    r.gen_burn_mult := bl_power_num('power.bad_fuel_burn_mult', 1.6);
    v_msg := v_msg || ' Eh! That fuel dey bad: the generator is coughing and will burn more fuel for a while. A mechanic can fix it.';
  end if;
  perform bl_power_save(r);
  perform bl_power_push_cancel(v_uid, 'power_fuel');
  return bl_power_view(v_uid, r, false) || jsonb_build_object('message', v_msg, 'poured', v_l, 'bad_batch', v_bad, 'bag', bl_power_bag(v_uid));
end $$;

create or replace function public.power_gen_repair() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); r public.player_power; v_cost bigint := greatest(0, round(bl_power_num('power.repair_cost', 25000)))::bigint; v_me public.profiles;
begin
  perform bl_assert_free(bl_me());
  r := bl_power_settle(v_uid, true);
  select * into r from public.player_power where user_id = v_uid for update;
  if not found or ((r.gen_fault_until is null or r.gen_fault_until <= bl_now()) and coalesce(r.batt_health, 100) >= 100) then
    raise exception 'Nothing is faulty. No mechanic needed.' using errcode = 'P0001', hint = 'no_fault';
  end if;
  select * into v_me from public.profiles where id = v_uid;
  if v_me.cash + v_me.bank < v_cost then
    raise exception 'The mechanic wants % and you no get am.', bl_naira(v_cost) using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  if v_cost > 0 then
    perform bl_add_money(v_uid, 'cash', -least(v_me.cash, v_cost), 'power_repair', jsonb_build_object('label', 'Generator repair'));
    if v_cost > v_me.cash then perform bl_add_money(v_uid, 'bank', -(v_cost - v_me.cash), 'power_repair', jsonb_build_object('label', 'Generator repair')); end if;
  end if;
  r.gen_fault_until := null; r.gen_burn_mult := 1;
  if coalesce(r.batt_health, 100) < 100 then
    r.batt_health := 100;
  end if;
  perform bl_power_save(r);
  return bl_power_view(v_uid, r, false) || jsonb_build_object('message', 'The mechanic cleaned the carburettor and checked the batteries. Everything sound again.', 'spent', v_cost);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 11. Effects while a home has no light (called from do_activity)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_power_fx_on() returns boolean
language sql stable set search_path = public as $$
  select bl_power_on() and coalesce((select (value #>> '{}')::boolean from public.game_config where key = 'power.effects_enabled'), true)
$$;

create or replace function public.bl_power_dark_furn(p_uid uuid, p_act text, p_furn jsonb) returns jsonb
language plpgsql volatile set search_path = public as $$
declare v_pct numeric; v_b jsonb;
begin
  if not bl_power_fx_on() or bl_power_lit(p_uid) then return p_furn; end if;
  if p_act = any (string_to_array(replace(coalesce(bl_cfg_text('power.needs_light_activities'), ''), ' ', ''), ',')) then
    raise exception 'No light. NEPA don take light, so you cannot do that now. Turn on your generator or wait.' using errcode = 'P0001', hint = 'no_light';
  end if;
  if jsonb_typeof(p_furn -> 'bonus') <> 'object' or p_furn -> 'bonus' = '{}'::jsonb then return p_furn; end if;
  v_pct := bl_power_num('power.dark_bonus_pct', 25);
  select coalesce(jsonb_object_agg(key, round(value::numeric * v_pct / 100, 1)), '{}'::jsonb) into v_b from jsonb_each_text(p_furn -> 'bonus');
  return p_furn || jsonb_build_object('bonus', v_b);
end $$;

create or replace function public.bl_power_house_bonus(p_uid uuid, p_act text) returns jsonb
language plpgsql volatile set search_path = public as $$
begin
  if bl_power_fx_on() and not bl_power_lit(p_uid) then return '{}'::jsonb; end if;
  return bl_house_bonus(p_uid, p_act);
end $$;

create or replace function public.bl_power_rest(p_uid uuid, p_act text, p_eff jsonb) returns jsonb
language plpgsql volatile set search_path = public as $$
declare v_eff jsonb := p_eff; v_gen jsonb; v_noise numeric;
begin
  if not bl_power_fx_on() then return p_eff; end if;
  if p_act in ('sleep', 'nap') then
    if not bl_power_lit(p_uid) then
      if coalesce((v_eff ->> 'energy')::numeric, 0) > 0 then
        v_eff := v_eff || jsonb_build_object('energy', round((v_eff ->> 'energy')::numeric * bl_power_num('power.dark_rest_pct', 85) / 100, 1));
      end if;
    else
      v_noise := bl_power_num('power.gen_noise_stress', 4);
      if v_noise > 0 and exists (select 1 from public.player_power pp where pp.user_id = p_uid and pp.gen_on and pp.fuel_l > 0) then
        v_gen := bl_power_gear(p_uid);
        if (v_gen ->> 'gen_id') is not null and not (v_gen ->> 'gen_soundproof')::boolean then
          v_eff := v_eff || jsonb_build_object('stress', coalesce((v_eff ->> 'stress')::numeric, 0) + v_noise);
        end if;
      end if;
    end if;
  end if;
  return v_eff;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 12. Fuel price and scarcity (called from bl_shop_price and shop_buy)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_fuel_scarce(p_t double precision default null) returns boolean
language sql stable set search_path = public as $$
  select coalesce((bl_power_event_scan('scarcity', coalesce(p_t, extract(epoch from bl_now())))).active, false)
$$;

-- price of one shop unit of a fuel item at a station: base a litre x litres in the unit, a daily move, scarcity
create or replace function public.bl_fuel_price(p_item public.items, p_loc text) returns bigint
language plpgsql stable set search_path = public as $$
declare g public.power_gear; v_base numeric; v_day text; v_h double precision; v_p numeric;
begin
  select * into g from public.power_gear where id = p_item.id and kind = 'fuel';
  if not found then return null; end if;
  v_base := case g.fuel when 'diesel' then bl_power_num('power.diesel_price', 1250) else bl_power_num('power.petrol_price', 1050) end;
  if g.grey then
    -- black-market fuel: cheaper on a normal day, dearer in a scarcity (the multipliers live in Admin -> Black market)
    v_base := v_base * case when bl_fuel_scarce() then bl_power_num('blackmarket.fuel_scarcity_mult', 1.9) else bl_power_num('blackmarket.fuel_mult', 0.8) end;
  end if;
  v_day := to_char(bl_now() at time zone bl_clock_tz(), 'YYYY-MM-DD');
  v_h := bl_power_h(v_day || ':fuel:' || g.fuel) * 2 - 1;                      -- -1 .. 1, same for everybody all day
  v_p := v_base * (1 + bl_power_num('power.fuel_daily_pct', 6) / 100.0 * v_h);
  if not g.grey and bl_fuel_scarce() then v_p := v_p * bl_power_num('power.scarcity_price_mult', 1.6); end if;
  if not g.grey and p_loc is not null then v_p := v_p * (1 + (bl_power_h(v_day || ':station:' || p_loc) - 0.5) * 0.04); end if;   -- +-2 % between stations
  v_p := v_p * g.litres * case when g.litres >= 5 and not g.grey then 1 - bl_power_num('power.can_discount_pct', 2) / 100.0 else 1 end;
  return greatest(10, (round(v_p / 10.0) * 10)::bigint);
end $$;

-- is this station out of fuel today? (scarcity only, fixed by date and station)
create or replace function public.bl_fuel_dry(p_loc text) returns boolean
language sql stable set search_path = public as $$
  select bl_fuel_scarce() and bl_power_h(to_char(bl_now() at time zone bl_clock_tz(), 'YYYY-MM-DD') || ':dry:' || p_loc) * 100 < bl_power_num('power.scarcity_dry_pct', 35)
$$;

-- shop_buy guard: a dry station sells no fuel; a queue keeps the player busy a few seconds
create or replace function public.bl_fuel_assert(p_uid uuid, p_loc public.locations, p_item public.items) returns void
language plpgsql volatile set search_path = public as $$
declare v_q numeric;
begin
  if p_item.category <> 'fuel' or not exists (select 1 from public.power_gear g where g.id = p_item.id and g.kind = 'fuel' and not g.grey) then return; end if;
  if bl_fuel_dry(p_loc.id) then
    raise exception '% no get fuel today. Try another station, or the yard after dark.', p_loc.name using errcode = 'P0001', hint = 'station_dry';
  end if;
  v_q := case when bl_fuel_scarce() then bl_power_num('power.queue_seconds_scarce', 25) else bl_power_num('power.queue_seconds', 0) end;
  if v_q > 0 then perform bl_set_busy_seconds(p_uid, v_q, 'Queueing for fuel'); end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 13. Admin: Blackout and scarcity controls (audited), overview
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_power_event_start(p_kind text, p_hours numeric, p_note text default '') returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_max numeric := bl_power_num('power.blackout_max_hours', 12); v_now timestamptz := bl_now(); v_id bigint; v_lim numeric;
begin
  if p_kind not in ('blackout', 'scarcity') then raise exception 'Unknown event.' using errcode = 'P0001', hint = 'bad_kind'; end if;
  v_lim := case when p_kind = 'blackout' then v_max else 72 end;
  if p_hours is null or p_hours <= 0 or p_hours > v_lim then
    raise exception 'Hours must be between 0 and %.', v_lim using errcode = 'P0001', hint = 'bad_hours';
  end if;
  update public.power_events set ends_at = v_now where kind = p_kind and started_at <= v_now and ends_at > v_now;
  insert into public.power_events (kind, started_at, ends_at, started_by, note)
  values (p_kind, v_now, v_now + make_interval(secs => (p_hours * 3600)::double precision), v_admin, left(btrim(coalesce(p_note, '')), 200)) returning id into v_id;
  insert into public.admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'power_' || p_kind || '_start', null, jsonb_build_object('hours', p_hours, 'note', left(btrim(coalesce(p_note, '')), 200), 'event', v_id));
  return jsonb_build_object('id', v_id, 'message', case p_kind when 'blackout' then 'NEPA don take light for all of Benin for ' else 'Fuel scarcity started for ' end || p_hours || ' hours.');
end $$;

create or replace function public.admin_power_event_end(p_kind text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_now timestamptz := bl_now(); n int;
begin
  if p_kind not in ('blackout', 'scarcity') then raise exception 'Unknown event.' using errcode = 'P0001', hint = 'bad_kind'; end if;
  update public.power_events set ends_at = v_now where kind = p_kind and started_at <= v_now and ends_at > v_now;
  get diagnostics n = row_count;
  insert into public.admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'power_' || p_kind || '_end', null, jsonb_build_object('ended', n));
  return jsonb_build_object('ended', n, 'message', case when n = 0 then 'Nothing was running.' else 'Ended. Light don come back.' end);
end $$;

create or replace function public.admin_power_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); t double precision := extract(epoch from bl_now());
begin
  return jsonb_build_object(
    'areas', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'outage_pct', bl_power_num('power.outage_pct.' || a.id, 0),
                         'mains', case when (bl_power_mains(a.id, t)).mains_on then 'on' else 'off' end, 'until', bl_power_flip_at(a.id, t)) order by a.sort)
                         from power_areas a where a.active), '[]'::jsonb),
    'blackout', (select to_jsonb(e) - 'started_by' from power_events e where kind = 'blackout' and started_at <= bl_now() and ends_at > bl_now() order by started_at desc limit 1),
    'scarcity', (select to_jsonb(e) - 'started_by' from power_events e where kind = 'scarcity' and started_at <= bl_now() and ends_at > bl_now() order by started_at desc limit 1),
    'random_blackout_now', (bl_power_event_scan('blackout', t)).active and not exists (select 1 from power_events where kind = 'blackout' and started_at <= bl_now() and ends_at > bl_now()),
    'random_scarcity_now', (bl_power_event_scan('scarcity', t)).active and not exists (select 1 from power_events where kind = 'scarcity' and started_at <= bl_now() and ends_at > bl_now()),
    'recent', coalesce((select jsonb_agg(x order by x.started_at desc) from (select e.id, e.kind, e.started_at, e.ends_at, e.note from power_events e order by e.started_at desc limit 10) x), '[]'::jsonb),
    'generators_on', (select count(*) from player_power where gen_on),
    'with_backup', (select count(*) from player_power where gen_id is not null or cap_seen > 0),
    'petrol_today', bl_fuel_price((select i from items i where i.id = 'petrol'), null),
    'diesel_today', bl_fuel_price((select i from items i where i.id = 'diesel'), null));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 14. Patches to live functions (guarded)
-- ---------------------------------------------------------------------------------------------
-- do_activity: no light means no TV, smaller furniture bonuses, poorer rest; generator noise
select pg_temp.pw_patch('public.do_activity(text)', 'bl_power_dark_furn',
  $o$  if a.home_only and jsonb_typeof(v_furn->'bonus') = 'object' and v_furn->'bonus' <> '{}'::jsonb then$o$,
  $o$  if a.home_only then v_furn := bl_power_dark_furn(v_me.id, a.id, v_furn); end if; -- power cuts
  if a.home_only and jsonb_typeof(v_furn->'bonus') = 'object' and v_furn->'bonus' <> '{}'::jsonb then$o$);
select pg_temp.pw_patch('public.do_activity(text)', 'bl_power_house_bonus',
  $o$  if a.home_only and bl_house_bonus(v_me.id, a.id) <> '{}'::jsonb then
    v_eff := v_eff || bl_effects_add(bl_need_effects(v_eff), bl_need_effects(bl_house_bonus(v_me.id, a.id)));
  end if;$o$,
  $o$  if a.home_only and bl_power_house_bonus(v_me.id, a.id) <> '{}'::jsonb then
    v_eff := v_eff || bl_effects_add(bl_need_effects(v_eff), bl_need_effects(bl_power_house_bonus(v_me.id, a.id)));
  end if;
  if a.home_only then v_eff := bl_power_rest(v_me.id, a.id, v_eff); end if; -- power cuts: dark rest, generator noise$o$);

-- shop_buy: fuel guard (dry station, queue)
select pg_temp.pw_patch('public.shop_buy(text, integer)', 'bl_fuel_assert',
  $o$  perform bl_lounge_assert(v_me.id, l, it.id); /* R7 lounge */$o$,
  $o$  perform bl_lounge_assert(v_me.id, l, it.id); /* R7 lounge */
  perform bl_fuel_assert(v_me.id, l, it); -- power cuts: dry station, queue$o$);

-- bl_shop_price: fuel is priced by bl_fuel_price (daily move, scarcity)
select pg_temp.pw_patch('public.bl_shop_price(public.items, text)', 'bl_fuel_price',
  $o$  if p_item.category = 'ingredient' then return bl_cook_price(p_item, p_location, null); end if;$o$,
  $o$  if p_item.category = 'ingredient' then return bl_cook_price(p_item, p_location, null); end if;
  if p_item.category = 'fuel' then return bl_fuel_price(p_item, p_location); end if; -- power cuts$o$);

-- admin Content editor: Power gear, Power areas
select pg_temp.pw_patch('public.bl_admin_table_spec(text)', 'when ''power_gear'' then',
  E'when ''house_upgrades'' then',
  E'when ''power_gear'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"kind":"text","source":"text","name":"text","tank_l":"num","burn_lph":"num","fuel":"text_null","soundproof":"bool","noise":"int","kva":"num","kwh":"num","solar_kw":"num","load_kw":"num","litres":"num","grey":"bool","sort":"int","active":"bool"}}''\n    when ''power_areas'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","homes":"arr","blurb":"text","sort":"int","active":"bool"}}''\n    when ''house_upgrades'' then');

select pg_temp.pw_patch('public.bl_ledger_label(text, jsonb)', 'power_repair',
  $o$    when 'rent' then return case when (p_meta->>'settle')::boolean then 'Rent paid (owed)' else 'Rent' end;$o$,
  $o$    when 'power_repair' then return 'Generator repair';
    when 'blackmarket' then return coalesce(nullif(p_meta->>'label', ''), 'Black market');
    when 'rent' then return case when (p_meta->>'settle')::boolean then 'Rent paid (owed)' else 'Rent' end;$o$);

-- ---------------------------------------------------------------------------------------------
-- 15. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and (proname like 'bl\_power\_%' or proname like 'bl\_fuel\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and proname in ('power_status', 'power_ack', 'power_gen_toggle', 'power_refuel', 'power_gen_repair') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and proname in ('admin_power_event_start', 'admin_power_event_end', 'admin_power_overview') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
end $$;

notify pgrst, 'reload schema';
