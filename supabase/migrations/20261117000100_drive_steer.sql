-- Drive scene 3 (docs/DRIVE.md): steer your own car, fuel, damage and repair, rain and night.
--   * Steering: the player's own car / motorcycle / bicycle can be steered in the 3D drive (lanes, brake, speed up). The server's arrival
--     time stays the schedule. The client only REPORTS counts (clean overtakes, tight gaps, hits, off-road moments) through
--     drive_report(); the server clamps every number (per report, per trip, by elapsed time, rate limit) and turns them into a small
--     time saving, a small time loss and car damage. Players who never touch the controls arrive exactly as before.
--   * Fuel: vehicle_state (user_id + item, no profiles change) keeps the tank and the condition of each own vehicle. travel_start burns
--     fuel by distance (tank size and litres per km per vehicle class are settings). A tank that cannot cover the trip dries out
--     mid-trip: a stranded card (push / call a mechanic / hitch a keke) rolled on the server through the existing road-event cards.
--     Refuel at a filling station pump (the existing stations, bl_fuel_price) or from petrol in the bag (the existing fuel items).
--   * Damage and repair: condition 0..100 per vehicle. Hits, potholes and the ambush damage from road events wear it down; low
--     condition slows the trip a little and burns more fuel; at 0 the vehicle will not start (a keke or walking always works).
--     Repair at the Mechanic Village (existing place) or call a mechanic (dearer), price tied to the damage.
--   * Weather: a deterministic server-seeded daily rain window (chance, hours, salt, on/off, force-rain are settings). Rain makes
--     trips a little slower and a little riskier. Night is the player's clock (client).
-- Patches live functions by guarded replace (unique pg_temp helper). No profiles DDL, no triggers or foreign keys, no loops over players.
-- Idempotent.

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (category drive)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('drive.steer.enabled', 'true', 'drive', 'Steer your own vehicle', 'On = the player can steer their own car, motorcycle or bicycle in the 3D drive (lanes, brake, speed up). Off = auto-drive only, drive_report is refused.', 'bool', null, null),
('drive.steer.max_save_pct', '12', 'drive', 'Steering: most time saved (% of the trip)', 'Overtaking and threading gaps can shave at most this share of the trip length off the server arrival time.', 'percent', 0, 50),
('drive.steer.max_save_s', '20', 'drive', 'Steering: most seconds saved on one trip', 'Hard cap in seconds, next to the percent cap (the smaller one counts).', 'number', 0, 300),
('drive.steer.s_per_pass', '1.2', 'drive', 'Steering: seconds saved per clean overtake', 'Each slow vehicle passed without a bump.', 'number', 0, 30),
('drive.steer.s_per_gap', '0.6', 'drive', 'Steering: seconds saved per tight gap', 'Threading a close gap between two vehicles.', 'number', 0, 30),
('drive.steer.max_passes', '10', 'drive', 'Steering: most overtakes counted per trip', 'Reports above this are ignored.', 'number', 0, 100),
('drive.steer.max_gaps', '8', 'drive', 'Steering: most tight gaps counted per trip', 'Reports above this are ignored.', 'number', 0, 100),
('drive.steer.min_s_per_pass', '6', 'drive', 'Steering: shortest time between two overtakes (seconds)', 'A report cannot claim more overtakes than the elapsed driving time allows at this pace.', 'number', 1, 120),
('drive.steer.hit_delay_s', '2.5', 'drive', 'Steering: seconds lost per hit', 'Clipping traffic costs time.', 'number', 0, 60),
('drive.steer.offroad_delay_s', '1.5', 'drive', 'Steering: seconds lost per off-road moment', 'Running off the road costs time.', 'number', 0, 60),
('drive.steer.max_lost_s', '15', 'drive', 'Steering: most seconds lost on one trip', 'Hits and off-road moments together never add more than this.', 'number', 0, 300),
('drive.steer.max_hits', '5', 'drive', 'Steering: most hits counted per trip', 'Reports above this are ignored.', 'number', 0, 100),
('drive.steer.max_offroad', '6', 'drive', 'Steering: most off-road moments counted per trip', 'Reports above this are ignored.', 'number', 0, 100),
('drive.steer.min_s_per_hit', '3', 'drive', 'Steering: shortest time between two hits (seconds)', 'A report cannot claim more hits or off-road moments than the elapsed time allows at this pace.', 'number', 1, 120),
('drive.steer.damage_hit', '6', 'drive', 'Steering: condition lost per hit', 'Points of vehicle condition (0 to 100). Rain multiplies it.', 'number', 0, 100),
('drive.steer.damage_offroad', '2', 'drive', 'Steering: condition lost per off-road moment', 'Points of vehicle condition (0 to 100).', 'number', 0, 100),
('drive.steer.max_damage', '25', 'drive', 'Steering: most condition lost on one trip', 'Hits, off-road moments and a rain skid together never take more than this.', 'number', 0, 100),
('drive.steer.report_gap_s', '5', 'drive', 'Steering: shortest gap between reports (seconds)', 'Rate limit on drive_report.', 'number', 0, 600),
('drive.steer.max_reports', '12', 'drive', 'Steering: most reports per trip', 'Rate limit on drive_report.', 'number', 1, 200),

('drive.damage.enabled', 'true', 'drive', 'Vehicle damage on', 'Off = nothing wears a vehicle down (hits, potholes, ambushes) and a damaged vehicle drives as normal.', 'bool', null, null),
('drive.damage.ambush', '12', 'drive', 'Damage: failed escape from area boys', 'Condition points lost (own vehicle only).', 'number', 0, 100),
('drive.damage.pothole', '6', 'drive', 'Damage: failed shortcut (potholes)', 'Condition points lost (own vehicle only).', 'number', 0, 100),
('drive.damage.low_warning', '35', 'drive', 'Damage: warning light below (condition)', 'The dashboard shows a warning light and the vehicle smokes below this.', 'number', 0, 100),
('drive.damage.slow_below', '50', 'drive', 'Damage: slower and thirstier below (condition)', 'Under this condition the trip takes longer and the fuel burns faster, more the lower it gets.', 'number', 1, 100),
('drive.damage.slow_pct', '25', 'drive', 'Damage: trip time added at condition 0 (%)', 'A badly damaged vehicle is slower. Scales from 0 at the threshold to this at condition 0.', 'percent', 0, 200),
('drive.damage.fuel_pct', '40', 'drive', 'Damage: extra fuel burn at condition 0 (%)', 'Scales from 0 at the threshold to this at condition 0.', 'percent', 0, 300),

('drive.fuel.enabled', 'true', 'drive', 'Fuel gauge on', 'Off = own vehicles use no fuel and never run dry.', 'bool', null, null),
('drive.fuel.start_pct', '80', 'drive', 'Fuel: tank level of a vehicle first driven (%)', 'A vehicle the server has not seen yet starts at this level.', 'percent', 0, 100),
('drive.fuel.km_scale', '5', 'drive', 'Fuel: real km per map km', 'The map is compressed, so a map km burns this many real km of fuel.', 'number', 0.1, 50),
('drive.fuel.tank_car', '45', 'drive', 'Fuel: tank, car (litres)', 'Sedans and every car that is not listed below.', 'number', 1, 500),
('drive.fuel.tank_suv', '70', 'drive', 'Fuel: tank, SUV (litres)', 'RX350, G-Wagon, Escalade, GLE, Urus.', 'number', 1, 500),
('drive.fuel.tank_pickup', '65', 'drive', 'Fuel: tank, pickup (litres)', 'Hilux, Cybertruck.', 'number', 1, 500),
('drive.fuel.tank_motorcycle', '12', 'drive', 'Fuel: tank, motorcycle (litres)', 'Okada-style bikes.', 'number', 1, 100),
('drive.fuel.lpk_car', '0.11', 'drive', 'Fuel: litres per km, car', 'Per real km (see the scale above).', 'number', 0, 5),
('drive.fuel.lpk_suv', '0.16', 'drive', 'Fuel: litres per km, SUV', 'Per real km.', 'number', 0, 5),
('drive.fuel.lpk_pickup', '0.14', 'drive', 'Fuel: litres per km, pickup', 'Per real km.', 'number', 0, 5),
('drive.fuel.lpk_motorcycle', '0.035', 'drive', 'Fuel: litres per km, motorcycle', 'Per real km.', 'number', 0, 5),
('drive.fuel.bad_fuel_damage', '6', 'drive', 'Fuel: grey petrol damage', 'Condition lost when grey (black-market) petrol turns out to be bad (the chance is power.bad_fuel_pct).', 'number', 0, 100),

('drive.dry.push_s', '25', 'drive', 'Out of fuel, push: seconds lost', 'You push the vehicle to the next pump or until a friend helps.', 'number', 0, 600),
('drive.dry.push_fail_pct', '20', 'drive', 'Out of fuel, push: chance it goes badly (%)', 'A bad push adds more time and stress.', 'percent', 0, 100),
('drive.dry.push_fail_s', '15', 'drive', 'Out of fuel, bad push: extra seconds', 'Added on top of the push time.', 'number', 0, 600),
('drive.dry.push_stress', '5', 'drive', 'Out of fuel, push: stress added', 'Pushing a car in the sun.', 'number', 0, 100),
('drive.dry.mechanic_cost', '12000', 'drive', 'Out of fuel, mechanic: price', 'He brings a can and charges for the trouble.', 'naira', 0, 100000000),
('drive.dry.mechanic_wait_min_s', '8', 'drive', 'Out of fuel, mechanic: shortest wait (seconds)', 'The wait is rolled between the two.', 'number', 0, 600),
('drive.dry.mechanic_wait_max_s', '22', 'drive', 'Out of fuel, mechanic: longest wait (seconds)', 'The wait is rolled between the two.', 'number', 0, 600),
('drive.dry.mechanic_litres', '6', 'drive', 'Out of fuel, mechanic: litres he puts in', 'Enough to reach the next pump.', 'number', 0, 100),
('drive.dry.keke_cost', '3000', 'drive', 'Out of fuel, hitch a keke: price', 'You leave the vehicle and ride on.', 'naira', 0, 100000000),
('drive.dry.keke_s', '40', 'drive', 'Out of fuel, hitch a keke: seconds lost', 'You arrive later.', 'number', 0, 600),

('drive.repair.per_point', '900', 'drive', 'Repair: price per condition point', 'Times the vehicle class multiplier below. A vehicle at 60 condition owes 40 points.', 'naira', 0, 10000000),
('drive.repair.min_fee', '2000', 'drive', 'Repair: smallest bill', 'Any repair costs at least this.', 'naira', 0, 10000000),
('drive.repair.callout_on', 'true', 'drive', 'Repair: call a mechanic to you', 'On = a vehicle can also be repaired away from the Mechanic Village, at the call-out price.', 'bool', null, null),
('drive.repair.callout_mult', '1.6', 'drive', 'Repair: call-out price multiplier', 'Times the Mechanic Village price.', 'number', 1, 20),
('drive.repair.mult_suv', '1.6', 'drive', 'Repair: SUV price multiplier', 'Times the per-point price.', 'number', 0, 20),
('drive.repair.mult_pickup', '1.4', 'drive', 'Repair: pickup price multiplier', 'Times the per-point price.', 'number', 0, 20),
('drive.repair.mult_motorcycle', '0.4', 'drive', 'Repair: motorcycle price multiplier', 'Times the per-point price.', 'number', 0, 20),
('drive.repair.mult_bicycle', '0.1', 'drive', 'Repair: bicycle price multiplier', 'Times the per-point price.', 'number', 0, 20),

('drive.weather.enabled', 'true', 'drive', 'Weather on (rain)', 'Off = it never rains on the road.', 'bool', null, null),
('drive.weather.force_rain', 'false', 'drive', 'Weather: make it rain now', 'On = rain all day for everybody (for testing and events).', 'bool', null, null),
('drive.weather.rain_day_pct', '30', 'drive', 'Weather: chance a Benin day has rain (%)', 'Fixed by the date and the salt, the same for everybody.', 'percent', 0, 100),
('drive.weather.rain_min_h', '2', 'drive', 'Weather: shortest rain (hours)', 'The rain window of a rainy day.', 'number', 0.25, 24),
('drive.weather.rain_max_h', '4', 'drive', 'Weather: longest rain (hours)', 'The rain window of a rainy day.', 'number', 0.25, 24),
('drive.weather.salt', '7', 'drive', 'Weather: schedule salt', 'Change it to reshuffle which days and hours rain.', 'number', 0, 100000),
('drive.rain.time_mult', '1.1', 'drive', 'Rain: trip time multiplier', 'Every road trip (not walking) takes this much longer in the rain. Quoted and used by travel_start.', 'number', 1, 3),
('drive.rain.damage_mult', '1.5', 'drive', 'Rain: damage multiplier', 'Hits and off-road moments hurt this much more on a wet road.', 'number', 1, 10),
('drive.rain.skid_pct', '6', 'drive', 'Rain: chance of a skid on a trip (%)', 'Rolled once per trip when steering reports in.', 'percent', 0, 100),
('drive.rain.skid_damage', '3', 'drive', 'Rain: skid damage', 'Condition points lost in a skid.', 'number', 0, 100)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables: vehicle state (tank and condition) and the trip state (read only through the RPCs)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.vehicle_state (
  user_id    uuid not null,
  item_id    text not null,
  fuel_l     numeric not null default 0 check (fuel_l >= 0),
  cond       numeric not null default 100 check (cond between 0 and 100),
  updated_at timestamptz not null default now(),
  primary key (user_id, item_id)
);
alter table public.vehicle_state enable row level security;
revoke all on public.vehicle_state from anon, authenticated;

create table if not exists public.drive_trip (
  user_id        uuid primary key,
  trip_key       text,
  mode           text,
  item_id        text,
  rain           boolean not null default false,
  km             numeric not null default 0,
  fuel_before    numeric not null default 0,
  need_l         numeric not null default 0,
  dry_prog       numeric,
  dry_done       boolean not null default false,
  skid_rolled    boolean not null default false,
  steer_reports  int not null default 0,
  steer_last_at  timestamptz,
  steer_passes   int not null default 0,
  steer_gaps     int not null default 0,
  steer_hits     int not null default 0,
  steer_offroad  int not null default 0,
  steer_saved_s  numeric not null default 0,
  steer_lost_s   numeric not null default 0,
  steer_damage   numeric not null default 0
);
alter table public.drive_trip enable row level security;
revoke all on public.drive_trip from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------------------------
-- vehicle class of an item id (the same buckets as the client's vehicleFor)
create or replace function public.bl_vehicle_class(p_item text) returns text
language sql immutable set search_path = public as $$
  select case
    when p_item = 'bicycle' then 'bicycle'
    when p_item = 'bajaj_boxer' then 'motorcycle'
    when p_item in ('gwagon_g63', 'gle63_coupe', 'lambo_urus', 'escalade', 'lexus_rx350') then 'suv'
    when p_item in ('tesla_cybertruck', 'hilux_new') then 'pickup'
    else 'car' end
$$;

create or replace function public.bl_vehicle_tank(p_class text) returns numeric
language sql stable set search_path = public as $$
  select case p_class when 'bicycle' then 0 else bl_cfg('drive.fuel.tank_' || p_class) end
$$;

-- condition -> factor on trip time / fuel burn (0 at or above the threshold, 1 at condition 0)
create or replace function public.bl_drive_wear(p_cond numeric) returns numeric
language sql stable set search_path = public as $$
  select case when not bl_cfg_bool('drive.damage.enabled') then 0
              else greatest(0, least(1, (bl_cfg('drive.damage.slow_below') - p_cond) / greatest(1, bl_cfg('drive.damage.slow_below')))) end
$$;

-- the state row of a vehicle (created on first sight: start level of the tank, condition 100)
create or replace function public.bl_vehicle_row(p_uid uuid, p_item text) returns public.vehicle_state
language plpgsql volatile set search_path = public as $$
declare r vehicle_state; v_tank numeric := bl_vehicle_tank(bl_vehicle_class(p_item));
begin
  insert into vehicle_state (user_id, item_id, fuel_l, cond, updated_at)
  values (p_uid, p_item, round(v_tank * bl_cfg('drive.fuel.start_pct') / 100.0, 2), 100, bl_now())
  on conflict (user_id, item_id) do nothing;
  select * into r from vehicle_state where user_id = p_uid and item_id = p_item for update;
  return r;
end $$;

-- read-only view of the same (defaults when no row yet)
create or replace function public.bl_vehicle_peek(p_uid uuid, p_item text) returns public.vehicle_state
language sql stable set search_path = public as $$
  select coalesce((select v from vehicle_state v where v.user_id = p_uid and v.item_id = p_item),
                  row(p_uid, p_item, round(bl_vehicle_tank(bl_vehicle_class(p_item)) * bl_cfg('drive.fuel.start_pct') / 100.0, 2), 100, bl_now())::vehicle_state)
$$;

-- wear a vehicle down; only while the player is on a trip in their own vehicle (mode car). Returns the new condition or null.
create or replace function public.bl_vehicle_damage(p_uid uuid, p_pts numeric) returns numeric
language plpgsql volatile set search_path = public as $$
declare v_item text; r vehicle_state; v_mode text;
begin
  if p_pts is null or p_pts <= 0 or not bl_cfg_bool('drive.damage.enabled') then return null; end if;
  select travel_mode into v_mode from profiles where id = p_uid;
  if v_mode is distinct from 'car' then return null; end if;
  v_item := bl_driving_item(p_uid);
  if v_item is null then return null; end if;
  r := bl_vehicle_row(p_uid, v_item);
  update vehicle_state set cond = greatest(0, cond - p_pts), updated_at = bl_now() where user_id = p_uid and item_id = v_item
    returning cond into r.cond;
  return r.cond;
end $$;

-- the daily rain window: a deterministic schedule from the date and the salt (same for everybody)
create or replace function public.bl_drive_weather(p_at timestamptz default null) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_t     timestamptz := coalesce(p_at, bl_now());
  v_loc   timestamp := v_t at time zone bl_clock_tz();
  v_day   text := to_char(v_loc, 'YYYY-MM-DD');
  v_hr    numeric := extract(hour from v_loc) + extract(minute from v_loc) / 60.0;
  v_salt  text := bl_cfg('drive.weather.salt')::text;
  v_on    boolean := bl_cfg_bool('drive.weather.enabled');
  v_force boolean := bl_cfg_bool('drive.weather.force_rain');
  v_rday  boolean;
  v_start numeric;
  v_len   numeric;
  v_rain  boolean;
begin
  v_rday := bl_power_h(v_day || ':drvrain:' || v_salt) * 100 < bl_cfg('drive.weather.rain_day_pct');
  v_start := 5 + floor(bl_power_h(v_day || ':drvstart:' || v_salt) * 14);
  v_len := bl_cfg('drive.weather.rain_min_h')
           + bl_power_h(v_day || ':drvlen:' || v_salt) * greatest(0, bl_cfg('drive.weather.rain_max_h') - bl_cfg('drive.weather.rain_min_h'));
  v_rain := v_on and (v_force or (v_rday and v_hr >= v_start and v_hr < v_start + v_len));
  return jsonb_build_object('enabled', v_on, 'rain', v_rain, 'forced', v_on and v_force,
    'rain_today', v_on and (v_force or v_rday),
    'start_hour', case when v_rday then v_start end, 'end_hour', case when v_rday then round(v_start + v_len, 1) end,
    'hour', round(v_hr, 2));
end $$;

-- factor on trip time: rain (all road modes) and a worn own vehicle (mode car)
create or replace function public.bl_drive_time_mult(p_uid uuid, p_mode text, p_ride text, p_at timestamptz default null) returns numeric
language plpgsql stable set search_path = public as $$
declare v numeric := 1; v_item text; v_cond numeric;
begin
  if p_mode is distinct from 'walk' and coalesce((bl_drive_weather(p_at) ->> 'rain')::boolean, false) then
    v := v * bl_cfg('drive.rain.time_mult');
  end if;
  if p_mode = 'car' and p_ride is not null and bl_cfg_bool('drive.damage.enabled') then
    v_item := bl_driving_item(p_uid);
    if v_item is not null then
      v_cond := (bl_vehicle_peek(p_uid, v_item)).cond;
      v := v * (1 + bl_drive_wear(v_cond) * bl_cfg('drive.damage.slow_pct') / 100.0);
    end if;
  end if;
  return v;
end $$;

-- is the vehicle the player drives at condition 0 (it will not start)?
create or replace function public.bl_drive_wont_start(p_uid uuid) returns boolean
language plpgsql stable set search_path = public as $$
declare v_item text;
begin
  if not bl_cfg_bool('drive.damage.enabled') then return false; end if;
  v_item := bl_driving_item(p_uid);
  return v_item is not null and (bl_vehicle_peek(p_uid, v_item)).cond <= 0;
end $$;

-- litres a trip of p_km map km burns for this vehicle (before the tank is looked at)
create or replace function public.bl_drive_need_l(p_item text, p_km numeric, p_cond numeric, p_rain boolean default false) returns numeric
language sql stable set search_path = public as $$
  select case when bl_vehicle_class(p_item) = 'bicycle' or not bl_cfg_bool('drive.fuel.enabled') then 0
    else round(p_km * bl_cfg('drive.fuel.km_scale') * bl_cfg('drive.fuel.lpk_' || bl_vehicle_class(p_item))
               * (1 + bl_drive_wear(p_cond) * bl_cfg('drive.damage.fuel_pct') / 100.0), 2) end
$$;

-- number out of a stats object: a JSON number, floored, 0 .. 1000 (anything else is 0)
create or replace function public.bl_drive_stat(p jsonb, k text) returns numeric
language sql immutable set search_path = public as $$
  select case when jsonb_typeof(p -> k) = 'number' then greatest(0, least(1000, floor((p ->> k)::numeric))) else 0 end
$$;

-- repair price of a vehicle at a condition (Mechanic Village price; the call-out multiplier is applied by the caller)
create or replace function public.bl_vehicle_repair_cost(p_item text, p_cond numeric) returns bigint
language sql stable set search_path = public as $$
  select case when p_cond >= 100 then 0 else
    greatest(bl_cfg('drive.repair.min_fee'),
      ceil((100 - p_cond) * bl_cfg('drive.repair.per_point')
           * case bl_vehicle_class(p_item) when 'car' then 1 else bl_cfg('drive.repair.mult_' || bl_vehicle_class(p_item)) end / 10.0) * 10)::bigint end
$$;

-- travel_start calls this: remember the trip, burn the fuel, and work out where the tank runs dry
create or replace function public.bl_drive_trip_begin(p_me public.profiles, p_dest text, p_mode text, p_now timestamptz, p_arr timestamptz) returns void
language plpgsql volatile set search_path = public as $$
declare
  v_item text; v_cls text; v_km numeric := 0; r vehicle_state; v_need numeric := 0; v_dry numeric; v_rain boolean;
begin
  v_rain := coalesce((bl_drive_weather(p_now) ->> 'rain')::boolean, false);
  if p_mode = 'car' then
    v_item := bl_driving_item(p_me.id);
    v_cls := bl_vehicle_class(v_item);
    v_km := bl_distance_km(p_me.location_id, p_dest);
    if v_item is not null and v_cls <> 'bicycle' and bl_cfg_bool('drive.fuel.enabled') then
      r := bl_vehicle_row(p_me.id, v_item);
      v_need := bl_drive_need_l(v_item, v_km, r.cond, v_rain);
      if v_need > r.fuel_l then
        v_dry := greatest(0.15, least(0.8, r.fuel_l / greatest(v_need, 0.01)));
      end if;
      update vehicle_state set fuel_l = greatest(0, fuel_l - v_need), updated_at = p_now where user_id = p_me.id and item_id = v_item;
    end if;
  end if;
  insert into drive_trip (user_id, trip_key, mode, item_id, rain, km, fuel_before, need_l, dry_prog)
  values (p_me.id, p_now::text, p_mode, v_item, v_rain, v_km, coalesce(r.fuel_l, 0), v_need, v_dry)
  on conflict (user_id) do update set trip_key = excluded.trip_key, mode = excluded.mode, item_id = excluded.item_id, rain = excluded.rain,
    km = excluded.km, fuel_before = excluded.fuel_before, need_l = excluded.need_l, dry_prog = excluded.dry_prog, dry_done = false,
    skid_rolled = false, steer_reports = 0, steer_last_at = null, steer_passes = 0, steer_gaps = 0, steer_hits = 0, steer_offroad = 0,
    steer_saved_s = 0, steer_lost_s = 0, steer_damage = 0;
end $$;

-- the out-of-fuel card answered: push, call a mechanic, or hitch a keke (all rolled and applied here)
create or replace function public.bl_drive_dry_choose(p_me public.profiles, p_choice text) returns jsonb
language plpgsql volatile set search_path = public as $$
declare
  v_now   timestamptz := bl_now();
  v_item  text;
  v_cash  bigint := p_me.cash;
  v_cost  bigint := 0;
  v_delay int := 0;
  v_stress numeric := 0;
  v_msg   text;
  v_tone  text := 'warn';
  v_fuel  numeric := 0;
  v_arr   timestamptz;
begin
  v_item := (select item_id from drive_trip where user_id = p_me.id);
  if p_choice = 'push' then
    v_delay := bl_cfg('drive.dry.push_s')::int;
    v_stress := bl_cfg('drive.dry.push_stress');
    if bl_rand() * 100 < bl_cfg('drive.dry.push_fail_pct') then
      v_delay := v_delay + bl_cfg('drive.dry.push_fail_s')::int; v_stress := v_stress * 1.6; v_tone := 'bad';
      v_msg := 'You push and push. A tyre drags and your back aches. It takes a long time, but you roll on.';
    else
      v_msg := 'You and two strangers push the car to the next pump. Tiring, but you are moving again.';
    end if;
  elsif p_choice = 'mechanic' then
    v_cost := bl_cfg('drive.dry.mechanic_cost')::bigint;
    if v_cost > v_cash then
      raise exception 'The mechanic wants % and you no get am. Push the car or hitch a keke.', bl_naira(v_cost) using errcode = 'P0001', hint = 'not_enough_cash';
    end if;
    v_delay := round(bl_cfg('drive.dry.mechanic_wait_min_s') + bl_rand() * greatest(0, bl_cfg('drive.dry.mechanic_wait_max_s') - bl_cfg('drive.dry.mechanic_wait_min_s')))::int;
    v_fuel := bl_cfg('drive.dry.mechanic_litres');
    v_msg := 'The mechanic arrives on a bike with a can, charges ' || bl_naira(v_cost) || ' and gets you going.';
  elsif p_choice = 'keke' then
    v_cost := bl_cfg('drive.dry.keke_cost')::bigint;
    if v_cost > v_cash then
      raise exception 'The keke man wants % and you no get am. Push the car or call a mechanic.', bl_naira(v_cost) using errcode = 'P0001', hint = 'not_enough_cash';
    end if;
    v_delay := bl_cfg('drive.dry.keke_s')::int;
    v_msg := 'You leave the car by the roadside and hop in a keke for ' || bl_naira(v_cost) || '. You arrive later than planned.';
  else
    raise exception 'That choice is not on the card.' using errcode = 'P0001', hint = 'bad_choice';
  end if;
  if v_cost > 0 then
    perform bl_add_money(p_me.id, 'cash', -v_cost, 'vehicle_' || p_choice, jsonb_build_object('item', v_item));
  end if;
  if v_item is not null and v_fuel > 0 then
    update vehicle_state set fuel_l = least(bl_vehicle_tank(bl_vehicle_class(v_item)), v_fuel), updated_at = v_now
     where user_id = p_me.id and item_id = v_item;
  end if;
  if v_stress <> 0 then
    perform bl_adjust_needs(p_me.id, jsonb_build_object('stress', v_stress));
  end if;
  v_arr := greatest(p_me.travel_arrives_at, v_now) + make_interval(secs => v_delay);
  update profiles set travel_arrives_at = v_arr where id = p_me.id;
  update drive_state set pending = null, pending_at = null where user_id = p_me.id;
  return jsonb_build_object('message', v_msg, 'tone', v_tone, 'kind', 'dry', 'choice', p_choice,
                            'cash_delta', -v_cost, 'delay_s', v_delay, 'arrives_at', v_arr);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. Patches to the live functions (guarded single replace, unique helper name)
-- ---------------------------------------------------------------------------------------------
create or replace function pg_temp.drv3_patch(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n <> 1 then raise exception 'drive_steer: % : marker found % times: %', p_sig, v_n, left(p_marker, 90); end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- trip quote: rain and a worn vehicle make the trip longer; a vehicle at condition 0 will not start
select pg_temp.drv3_patch('public.bl_travel_quote(public.profiles, text)', 'bl_drive_time_mult',
$m$    v_rs := round(v_rs, 1);$m$,
$m$    v_rs := round(v_rs * bl_drive_time_mult(p_me.id, m, v_ride, v_now), 1);$m$);

select pg_temp.drv3_patch('public.bl_travel_quote(public.profiles, text)', 'bl_drive_wont_start',
$m$    elsif v_cost > p_me.cash then$m$,
$m$    elsif m = 'car' and bl_drive_wont_start(p_me.id) then
      v_allowed := false;
      v_reason := 'Your vehicle is too damaged to start. Repair it at the Mechanic Village, or take a keke for now.';
    elsif v_cost > p_me.cash then$m$);

-- travel_start: remember the trip, burn the fuel
select pg_temp.drv3_patch('public.travel_start(text, text)', 'bl_drive_trip_begin',
$m$  select name into v_name from locations where id = p_dest;$m$,
$m$  perform bl_drive_trip_begin(v_me, p_dest, p_mode, v_now, v_arr);
  select name into v_name from locations where id = p_dest;$m$);

-- the out-of-fuel card
select pg_temp.drv3_patch('public.bl_drive_card(text, bigint)', '''dry''',
$m$  elsif p_kind = 'goslow' then$m$,
$m$  elsif p_kind = 'dry' then
    return jsonb_build_object('kind', 'dry', 'title', 'Out of fuel',
      'body', 'The engine coughs and dies. The needle sits on empty and you roll to a stop by the roadside.',
      'choices', jsonb_build_array(
        jsonb_build_object('id', 'push',     'label', 'Push the car', 'hint', 'Free, but it costs time and sweat.'),
        jsonb_build_object('id', 'mechanic', 'label', 'Call a mechanic ' || bl_naira(bl_cfg('drive.dry.mechanic_cost')), 'hint', 'He brings a can. You wait for him.'),
        jsonb_build_object('id', 'keke',     'label', 'Hitch a keke ' || bl_naira(bl_cfg('drive.dry.keke_cost')), 'hint', 'Cheaper, but you arrive later.')));
  elsif p_kind = 'goslow' then$m$);

-- road event roll: a tank that ran dry beats every other limit
select pg_temp.drv3_patch('public.drive_event_roll()', 'drive 3: the tank',
$m$  -- a card still waiting (a reload): show it again until it expires$m$,
$m$  -- drive 3: the tank ran dry mid-trip (worked out at travel_start): the stranded card, whatever the other limits say
  if s.pending is null and bl_cfg_bool('drive.fuel.enabled') and exists (
       select 1 from drive_trip t where t.user_id = v_me.id and t.trip_key = v_key and t.dry_prog is not null and not t.dry_done
          and extract(epoch from v_now - v_me.travel_started_at) >= t.dry_prog * extract(epoch from v_me.travel_arrives_at - v_me.travel_started_at)) then
    update drive_trip set dry_done = true where user_id = v_me.id;
    update drive_state set day_key = s.day_key, events_today = s.events_today, trip_key = s.trip_key, trip_events = s.trip_events,
           trip_delay_s = s.trip_delay_s, pending = jsonb_build_object('kind', 'dry', 'amount', 0), pending_at = v_now where user_id = v_me.id;
    return jsonb_build_object('event', bl_drive_card('dry', 0));
  end if;

  -- a card still waiting (a reload): show it again until it expires$m$);

-- road event choose: the dry card is answered by bl_drive_dry_choose, ambush and potholes wear the vehicle
select pg_temp.drv3_patch('public.drive_event_choose(text)', 'bl_drive_dry_choose',
$m$  v_kind := s.pending->>'kind';$m$,
$m$  v_kind := s.pending->>'kind';
  if v_kind = 'dry' then
    return bl_drive_dry_choose(v_me, p_choice);
  end if;$m$);

select pg_temp.drv3_patch('public.drive_event_choose(text)', 'v_dmg    numeric',
$m$  v_fine   bigint;$m$,
$m$  v_fine   bigint;
  v_dmg    numeric := 0;$m$);

select pg_temp.drv3_patch('public.drive_event_choose(text)', 'drive.damage.ambush',
$m$v_hp := -bl_cfg('drive.ambush.fail_health');$m$,
$m$v_hp := -bl_cfg('drive.ambush.fail_health'); v_dmg := bl_cfg('drive.damage.ambush');$m$);

select pg_temp.drv3_patch('public.drive_event_choose(text)', 'drive.damage.pothole',
$m$v_stress := bl_cfg('drive.goslow.stress');$m$,
$m$v_stress := bl_cfg('drive.goslow.stress'); v_dmg := bl_cfg('drive.damage.pothole');$m$);

select pg_temp.drv3_patch('public.drive_event_choose(text)', 'bl_vehicle_damage',
$m$  if v_loss > 0 then$m$,
$m$  if v_dmg > 0 then
    perform bl_vehicle_damage(v_me.id, v_dmg);
  end if;
  if v_loss > 0 then$m$);

-- ---------------------------------------------------------------------------------------------
-- 5. RPCs
-- ---------------------------------------------------------------------------------------------
-- the weather the road has right now (anybody signed in may ask)
create or replace function public.drive_weather() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform bl_require_uid();
  return bl_drive_weather();
end $$;

-- the player's vehicles with tank and condition, the mechanic and the pump they stand at, petrol in the bag
create or replace function public.vehicle_status() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me     profiles := bl_me();
  v_drv    text := bl_driving_item(v_me.id);
  v_cars   jsonb;
  v_loc    locations;
  v_station jsonb := null;
  v_bag    numeric;
  v_trip   drive_trip;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', it.id, 'name', it.name, 'class', bl_vehicle_class(it.id), 'driving', it.id = v_drv,
      'fuel_l', round(vs.fuel_l, 1), 'tank_l', bl_vehicle_tank(bl_vehicle_class(it.id)), 'cond', round(vs.cond),
      'lpk', round(bl_drive_need_l(it.id, 1.0 / greatest(bl_cfg('drive.fuel.km_scale'), 0.1), vs.cond), 3),
      'repair_cost', bl_vehicle_repair_cost(it.id, vs.cond),
      'callout_cost', ceil(bl_vehicle_repair_cost(it.id, vs.cond) * bl_cfg('drive.repair.callout_mult') / 10.0) * 10)
      order by (it.id = v_drv) desc, it.price desc, it.id), '[]'::jsonb)
    into v_cars
    from inventory i join items it on it.id = i.item_id
    cross join lateral bl_vehicle_peek(v_me.id, it.id) vs
   where i.user_id = v_me.id and i.qty > 0 and it.category = 'vehicle';
  select * into v_loc from locations where id = v_me.location_id;
  if found and v_loc.id like 'fs\_%' then
    v_station := jsonb_build_object('id', v_loc.id, 'name', v_loc.name, 'dry', bl_fuel_dry(v_loc.id),
                                    'price', bl_fuel_price((select i from items i where i.id = 'petrol'), v_loc.id));
  end if;
  select coalesce(sum(i.qty * g.litres), 0) into v_bag
    from inventory i join power_gear g on g.id = i.item_id and g.kind = 'fuel' and g.fuel = 'petrol' and g.active
   where i.user_id = v_me.id and i.qty > 0;
  select * into v_trip from drive_trip where user_id = v_me.id;
  return jsonb_build_object(
    'fuel_on', bl_cfg_bool('drive.fuel.enabled'), 'damage_on', bl_cfg_bool('drive.damage.enabled'),
    'steer_on', bl_cfg_bool('drive.steer.enabled'), 'callout_on', bl_cfg_bool('drive.repair.callout_on'),
    'driving', v_drv, 'cars', v_cars,
    'at_mechanic', v_me.location_id = 'mechanic_village', 'station', v_station, 'bag_l', v_bag,
    'cash', v_me.cash, 'bank', v_me.bank, 'traveling', v_me.travel_to is not null,
    'trip', case when v_trip.user_id is not null and v_me.travel_to is not null and v_trip.trip_key = v_me.travel_started_at::text
                 then jsonb_build_object('item', v_trip.item_id, 'fuel_before', round(v_trip.fuel_before, 2), 'need_l', v_trip.need_l,
                                         'dry_prog', v_trip.dry_prog, 'dry_done', v_trip.dry_done, 'rain', v_trip.rain,
                                         'saved_s', round(v_trip.steer_saved_s, 1), 'lost_s', round(v_trip.steer_lost_s, 1)) end,
    'weather', bl_drive_weather());
end $$;

-- before a trip by own vehicle: does the tank cover it, will it start?
create or replace function public.vehicle_trip_check(p_dest text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  v_item text := bl_driving_item(v_me.id);
  v_cls  text;
  r      vehicle_state;
  v_km   numeric;
  v_need numeric;
  v_rain boolean := coalesce((bl_drive_weather() ->> 'rain')::boolean, false);
  v_bag  numeric;
  v_station jsonb := null;
  v_loc  locations;
begin
  if v_item is null then return jsonb_build_object('applies', false); end if;
  v_cls := bl_vehicle_class(v_item);
  r := bl_vehicle_peek(v_me.id, v_item);
  v_km := bl_distance_km(v_me.location_id, p_dest);
  v_need := bl_drive_need_l(v_item, v_km, r.cond, v_rain);
  select coalesce(sum(i.qty * g.litres), 0) into v_bag
    from inventory i join power_gear g on g.id = i.item_id and g.kind = 'fuel' and g.fuel = 'petrol' and g.active
   where i.user_id = v_me.id and i.qty > 0;
  select * into v_loc from locations where id = v_me.location_id;
  if found and v_loc.id like 'fs\_%' then
    v_station := jsonb_build_object('id', v_loc.id, 'name', v_loc.name, 'dry', bl_fuel_dry(v_loc.id),
                                    'price', bl_fuel_price((select i from items i where i.id = 'petrol'), v_loc.id));
  end if;
  return jsonb_build_object('applies', v_cls <> 'bicycle' and bl_cfg_bool('drive.fuel.enabled'), 'item', v_item,
    'class', v_cls, 'fuel_l', round(r.fuel_l, 1), 'tank_l', bl_vehicle_tank(v_cls), 'need_l', v_need,
    'short_l', greatest(0, round(v_need - r.fuel_l, 1)), 'enough', r.fuel_l >= v_need or v_cls = 'bicycle' or not bl_cfg_bool('drive.fuel.enabled'),
    'cond', round(r.cond), 'wont_start', bl_cfg_bool('drive.damage.enabled') and r.cond <= 0,
    'bag_l', v_bag, 'station', v_station, 'km', v_km);
end $$;

-- refuel the vehicle the player drives: 'pump' (at a filling station, litres, paid at the pump price) or a petrol item from the bag
create or replace function public.vehicle_refuel(p_source text, p_qty numeric default 1) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  v_item text := bl_driving_item(v_me.id);
  v_cls  text;
  r      vehicle_state;
  v_tank numeric;
  v_free numeric;
  v_l    numeric;
  v_price bigint;
  v_cost bigint := 0;
  v_loc  locations;
  g      power_gear;
  v_units int;
  v_have int;
  v_msg  text;
  v_bad  boolean := false;
begin
  perform bl_assert_free(v_me);
  if not bl_cfg_bool('drive.fuel.enabled') then
    raise exception 'Fuel is not needed right now.' using errcode = 'P0001', hint = 'off';
  end if;
  if v_item is null then
    raise exception 'You don''t have a vehicle to fill.' using errcode = 'P0001', hint = 'no_vehicle';
  end if;
  v_cls := bl_vehicle_class(v_item);
  if v_cls = 'bicycle' then
    raise exception 'A bicycle does not need fuel.' using errcode = 'P0001', hint = 'bicycle';
  end if;
  if p_qty is null or p_qty <= 0 or p_qty > 500 then
    raise exception 'Pick how much.' using errcode = 'P0001', hint = 'bad_qty';
  end if;
  r := bl_vehicle_row(v_me.id, v_item);
  v_tank := bl_vehicle_tank(v_cls);
  v_free := v_tank - r.fuel_l;
  if v_free < 0.5 then
    raise exception 'The tank is full (% of % litres).', round(r.fuel_l, 1), v_tank using errcode = 'P0001', hint = 'tank_full';
  end if;
  if p_source = 'pump' then
    select * into v_loc from locations where id = v_me.location_id;
    if not found or v_loc.id not like 'fs\_%' then
      raise exception 'Go to a filling station to use the pump.' using errcode = 'P0001', hint = 'not_at_station';
    end if;
    if bl_fuel_dry(v_loc.id) then
      raise exception '% no get fuel today. Try another station.', v_loc.name using errcode = 'P0001', hint = 'station_dry';
    end if;
    v_l := least(floor(p_qty), floor(v_free));
    if v_l < 1 then v_l := least(p_qty, v_free); end if;
    v_price := bl_fuel_price((select i from items i where i.id = 'petrol'), v_loc.id);
    v_cost := ceil(v_l * v_price)::bigint;
    if v_cost > v_me.cash then
      raise exception 'Not enough cash. % litres at % a litre is %.', v_l, bl_naira(v_price), bl_naira(v_cost) using errcode = 'P0001', hint = 'not_enough_cash';
    end if;
    perform bl_add_money(v_me.id, 'cash', -v_cost, 'vehicle_fuel', jsonb_build_object('item', v_item, 'litres', v_l, 'station', v_loc.id));
    v_msg := 'The attendant fills ' || v_l || ' litres for ' || bl_naira(v_cost) || '.';
  else
    select * into g from power_gear where id = p_source and kind = 'fuel' and fuel = 'petrol' and active;
    if not found then
      raise exception 'That is not petrol.' using errcode = 'P0001', hint = 'not_fuel';
    end if;
    v_have := coalesce((select qty from inventory where user_id = v_me.id and item_id = g.id), 0);
    if v_have < 1 then
      raise exception 'You don''t have any of that. Buy fuel at a filling station.' using errcode = 'P0001', hint = 'no_fuel_item';
    end if;
    v_units := least(greatest(1, floor(p_qty)::int), v_have, floor(v_free / g.litres)::int);
    if v_units < 1 then
      raise exception 'The tank is nearly full. Keep the can for later.' using errcode = 'P0001', hint = 'tank_full';
    end if;
    perform bl_give_item(v_me.id, g.id, -v_units);
    v_l := v_units * g.litres;
    v_msg := 'You poured ' || v_l || ' litres from your bag.';
    if g.grey and bl_rand() * 100 < bl_cfg('power.bad_fuel_pct') then
      v_bad := true;
      update vehicle_state set cond = greatest(0, cond - bl_cfg('drive.fuel.bad_fuel_damage')) where user_id = v_me.id and item_id = v_item;
      v_msg := v_msg || ' Eh! That fuel dey bad: the engine coughs. It cost the car some condition.';
    end if;
  end if;
  update vehicle_state set fuel_l = least(v_tank, fuel_l + v_l), updated_at = bl_now() where user_id = v_me.id and item_id = v_item
    returning fuel_l into r.fuel_l;
  return jsonb_build_object('message', v_msg, 'litres', v_l, 'cost', v_cost, 'fuel_l', round(r.fuel_l, 1), 'tank_l', v_tank, 'bad_batch', v_bad,
                            'item', v_item);
end $$;

-- repair a vehicle: at the Mechanic Village, or called to you (dearer). Price tied to the damage.
create or replace function public.vehicle_repair(p_item text default null, p_callout boolean default false) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  v_item text := coalesce(p_item, bl_driving_item(v_me.id));
  r      vehicle_state;
  v_cost bigint;
  v_bank bigint;
  v_cash bigint;
  v_name text;
begin
  perform bl_assert_free(v_me);
  if not bl_cfg_bool('drive.damage.enabled') then
    raise exception 'Nothing needs repair right now.' using errcode = 'P0001', hint = 'off';
  end if;
  select it.name into v_name from items it join inventory i on i.item_id = it.id
   where it.id = v_item and it.category = 'vehicle' and i.user_id = v_me.id and i.qty > 0;
  if not found then
    raise exception 'You do not own that vehicle.' using errcode = 'P0001', hint = 'not_owned';
  end if;
  r := bl_vehicle_row(v_me.id, v_item);
  if r.cond >= 100 then
    raise exception 'Your % is in perfect shape.', v_name using errcode = 'P0001', hint = 'nothing_to_fix';
  end if;
  if p_callout then
    if not bl_cfg_bool('drive.repair.callout_on') then
      raise exception 'No mechanic will come out to you right now. Go to the Mechanic Village on Sapele Road.' using errcode = 'P0001', hint = 'callout_off';
    end if;
  elsif v_me.location_id is distinct from 'mechanic_village' then
    raise exception 'Go to the Mechanic Village on Sapele Road, or call a mechanic to come to you.' using errcode = 'P0001', hint = 'not_at_mechanic';
  end if;
  v_cost := bl_vehicle_repair_cost(v_item, r.cond);
  if p_callout then v_cost := (ceil(v_cost * bl_cfg('drive.repair.callout_mult') / 10.0) * 10)::bigint; end if;
  v_bank := least(greatest(v_me.bank, 0), v_cost);
  v_cash := v_cost - v_bank;
  if v_cash > v_me.cash then
    raise exception 'The repair costs % and you have % (bank % + cash %).', bl_naira(v_cost), bl_naira(v_me.bank + v_me.cash),
      bl_naira(v_me.bank), bl_naira(v_me.cash) using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  if v_bank > 0 then
    perform bl_add_money(v_me.id, 'bank', -v_bank, 'vehicle_repair', jsonb_build_object('item', v_item, 'callout', p_callout));
  end if;
  if v_cash > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_cash, 'vehicle_repair', jsonb_build_object('item', v_item, 'callout', p_callout));
  end if;
  update vehicle_state set cond = 100, updated_at = bl_now() where user_id = v_me.id and item_id = v_item;
  return jsonb_build_object('message', 'Your ' || v_name || ' is fixed for ' || bl_naira(v_cost) || '. Good as new.', 'cost', v_cost, 'cond', 100,
                            'callout', p_callout, 'item', v_item);
end $$;

-- the client's report of a steered trip: counts only, clamped here, applied here
create or replace function public.drive_report(p_trip text, p_stats jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me     profiles := bl_me();
  v_now    timestamptz := bl_now();
  t        drive_trip;
  e        numeric;
  v_total  numeric;
  v_pass   int; v_gap int; v_hit int; v_off int;
  v_save   numeric; v_lost numeric; v_dmg numeric;
  v_cap    numeric;
  v_skid   boolean := false;
  v_arr    timestamptz;
  v_cond   numeric;
  v_msg    text;
  v_ts     timestamptz;
begin
  if not bl_cfg_bool('drive.enabled') or not bl_cfg_bool('drive.steer.enabled') then
    return jsonb_build_object('ok', false, 'reason', 'off');
  end if;
  begin
    v_ts := p_trip::timestamptz;      -- the client sends the trip's start time as the server gave it (ISO text)
  exception when others then
    v_ts := null;
  end;
  if v_me.travel_to is null or v_me.travel_mode is distinct from 'car' or v_ts is null
     or abs(extract(epoch from v_ts - v_me.travel_started_at)) > 0.01 then
    return jsonb_build_object('ok', false, 'reason', 'no_trip');
  end if;
  p_trip := v_me.travel_started_at::text;
  if v_now > v_me.travel_arrives_at then
    return jsonb_build_object('ok', false, 'reason', 'late');
  end if;
  select * into t from drive_trip where user_id = v_me.id for update;
  if not found or t.trip_key is distinct from p_trip then
    insert into drive_trip (user_id, trip_key, mode, item_id, rain) values (v_me.id, p_trip, 'car', bl_driving_item(v_me.id), false)
    on conflict (user_id) do update set trip_key = excluded.trip_key, mode = 'car', item_id = excluded.item_id, rain = false, dry_prog = null,
      dry_done = false, skid_rolled = false, steer_reports = 0, steer_last_at = null, steer_passes = 0, steer_gaps = 0, steer_hits = 0,
      steer_offroad = 0, steer_saved_s = 0, steer_lost_s = 0, steer_damage = 0;
    select * into t from drive_trip where user_id = v_me.id for update;
  end if;
  -- rate limits
  if t.steer_last_at is not null and v_now < t.steer_last_at + make_interval(secs => bl_cfg('drive.steer.report_gap_s')::double precision) then
    return jsonb_build_object('ok', false, 'reason', 'too_soon');
  end if;
  if t.steer_reports >= bl_cfg('drive.steer.max_reports') then
    return jsonb_build_object('ok', false, 'reason', 'max_reports');
  end if;
  e := greatest(0, extract(epoch from v_now - v_me.travel_started_at));
  v_total := greatest(1, extract(epoch from v_me.travel_arrives_at - v_me.travel_started_at));

  -- clamp every count: by what one trip may hold and by what the elapsed time allows
  v_pass := greatest(0, least(bl_drive_stat(p_stats, 'passes'), bl_cfg('drive.steer.max_passes') - t.steer_passes,
                              floor(e / greatest(1, bl_cfg('drive.steer.min_s_per_pass'))) - t.steer_passes))::int;
  v_gap  := greatest(0, least(bl_drive_stat(p_stats, 'gaps'), bl_cfg('drive.steer.max_gaps') - t.steer_gaps,
                              floor(e / greatest(1, bl_cfg('drive.steer.min_s_per_pass'))) - t.steer_gaps))::int;
  v_hit  := greatest(0, least(bl_drive_stat(p_stats, 'hits'), bl_cfg('drive.steer.max_hits') - t.steer_hits,
                              floor(e / greatest(1, bl_cfg('drive.steer.min_s_per_hit'))) - t.steer_hits))::int;
  v_off  := greatest(0, least(bl_drive_stat(p_stats, 'offroad'), bl_cfg('drive.steer.max_offroad') - t.steer_offroad,
                              floor(e / greatest(1, bl_cfg('drive.steer.min_s_per_hit'))) - t.steer_offroad))::int;

  -- time saved: capped by a share of the trip and by seconds, over the whole trip
  v_cap := greatest(0, least(bl_cfg('drive.steer.max_save_s'), v_total * bl_cfg('drive.steer.max_save_pct') / 100.0) - t.steer_saved_s);
  v_save := least(v_cap, v_pass * bl_cfg('drive.steer.s_per_pass') + v_gap * bl_cfg('drive.steer.s_per_gap'));
  -- time lost
  v_lost := least(greatest(0, bl_cfg('drive.steer.max_lost_s') - t.steer_lost_s),
                  v_hit * bl_cfg('drive.steer.hit_delay_s') + v_off * bl_cfg('drive.steer.offroad_delay_s'));
  -- damage (wet road hurts more), a rain skid rolled once a trip
  v_dmg := (v_hit * bl_cfg('drive.steer.damage_hit') + v_off * bl_cfg('drive.steer.damage_offroad'))
           * case when t.rain then bl_cfg('drive.rain.damage_mult') else 1 end;
  if t.rain and not t.skid_rolled then
    if bl_rand() * 100 < bl_cfg('drive.rain.skid_pct') then
      v_skid := true; v_dmg := v_dmg + bl_cfg('drive.rain.skid_damage');
    end if;
  end if;
  v_dmg := greatest(0, least(v_dmg, bl_cfg('drive.steer.max_damage') - t.steer_damage));

  -- apply: the arrival moves by lost minus saved, never earlier than 3 s from now
  v_arr := greatest(v_now + interval '3 seconds', v_me.travel_arrives_at + make_interval(secs => (v_lost - v_save)::double precision));
  if v_arr is distinct from v_me.travel_arrives_at then
    update profiles set travel_arrives_at = v_arr where id = v_me.id;
  end if;
  if v_dmg > 0 then
    v_cond := bl_vehicle_damage(v_me.id, v_dmg);
  end if;
  if v_cond is null then
    v_cond := (bl_vehicle_peek(v_me.id, coalesce(t.item_id, bl_driving_item(v_me.id)))).cond;
  end if;
  update drive_trip set steer_reports = steer_reports + 1, steer_last_at = v_now, steer_passes = steer_passes + v_pass,
         steer_gaps = steer_gaps + v_gap, steer_hits = steer_hits + v_hit, steer_offroad = steer_offroad + v_off,
         steer_saved_s = steer_saved_s + v_save, steer_lost_s = steer_lost_s + v_lost, steer_damage = steer_damage + v_dmg,
         skid_rolled = skid_rolled or t.rain
   where user_id = v_me.id;
  v_msg := case when v_skid then 'The wet road made you skid.'
                when v_save > v_lost then 'Nice driving: ' || round(v_save - v_lost, 1) || ' s saved.'
                when v_lost > v_save then 'Careful! ' || round(v_lost - v_save, 1) || ' s lost.' end;
  return jsonb_build_object('ok', true, 'saved_s', round(v_save, 1), 'lost_s', round(v_lost, 1), 'damage', round(v_dmg, 1),
    'cond', round(v_cond), 'arrives_at', v_arr, 'skid', v_skid, 'message', v_msg,
    'applied', jsonb_build_object('passes', v_pass, 'gaps', v_gap, 'hits', v_hit, 'offroad', v_off));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------------------------
revoke execute on function public.bl_vehicle_class(text) from public, anon, authenticated;
revoke execute on function public.bl_vehicle_tank(text) from public, anon, authenticated;
revoke execute on function public.bl_drive_wear(numeric) from public, anon, authenticated;
revoke execute on function public.bl_vehicle_row(uuid, text) from public, anon, authenticated;
revoke execute on function public.bl_vehicle_peek(uuid, text) from public, anon, authenticated;
revoke execute on function public.bl_vehicle_damage(uuid, numeric) from public, anon, authenticated;
revoke execute on function public.bl_drive_weather(timestamptz) from public, anon, authenticated;
revoke execute on function public.bl_drive_time_mult(uuid, text, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.bl_drive_wont_start(uuid) from public, anon, authenticated;
revoke execute on function public.bl_drive_need_l(text, numeric, numeric, boolean) from public, anon, authenticated;
revoke execute on function public.bl_drive_stat(jsonb, text) from public, anon, authenticated;
revoke execute on function public.bl_vehicle_repair_cost(text, numeric) from public, anon, authenticated;
revoke execute on function public.bl_drive_trip_begin(public.profiles, text, text, timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.bl_drive_dry_choose(public.profiles, text) from public, anon, authenticated;
revoke execute on function public.drive_weather() from public, anon;
revoke execute on function public.vehicle_status() from public, anon;
revoke execute on function public.vehicle_trip_check(text) from public, anon;
revoke execute on function public.vehicle_refuel(text, numeric) from public, anon;
revoke execute on function public.vehicle_repair(text, boolean) from public, anon;
revoke execute on function public.drive_report(text, jsonb) from public, anon;
grant execute on function public.drive_weather() to authenticated;
grant execute on function public.vehicle_status() to authenticated;
grant execute on function public.vehicle_trip_check(text) to authenticated;
grant execute on function public.vehicle_refuel(text, numeric) to authenticated;
grant execute on function public.vehicle_repair(text, boolean) to authenticated;
grant execute on function public.drive_report(text, jsonb) to authenticated;

notify pgrst, 'reload schema';
