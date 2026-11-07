-- Drive scene 3 (20261117000100_drive_steer.sql, docs/DRIVE.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/drive3_test.sql
-- Groups: 1 settings · 2 weather schedule · 3 quote (rain, wear, will not start) · 4 fuel burn and the dry-out check · 5 dry-out outcomes ·
-- 6 refuel (pump, bag, grey fuel) · 7 repair cost and repair · 8 drive_report clamps and rate limits · 9 damage from road events ·
-- 10 skipping the controls changes nothing · 11 switches · 12 grants and RLS.
-- Times are pinned with bl.test_offset_seconds where a trip is started; chances are forced to 0 or 100 when an outcome is tested.
create or replace function pg_temp.adv(p_secs double precision) returns void
language plpgsql as $$
begin
  perform set_config('bl.test_offset_seconds',
    (coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::double precision, 0) + p_secs)::text, true);
end $$;

create or replace function pg_temp.setc(p_key text, p_val jsonb) returns void
language sql as $$ update game_config set value = p_val where key = p_key $$;

create or replace function pg_temp.hint_of(p_sql text) returns text
language plpgsql as $$
declare v_h text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  get stacked diagnostics v_h = pg_exception_hint;
  return coalesce(nullif(v_h, ''), sqlerrm);
end $$;

create or replace function pg_temp.opt(p_uid uuid, p_dest text, p_mode text) returns jsonb
language plpgsql as $$
declare q jsonb;
begin
  q := bl_travel_quote((select p from profiles p where p.id = p_uid), p_dest);
  return (select o from jsonb_array_elements(q->'options') o where o->>'mode' = p_mode);
end $$;

-- put the player (back) at their start place, no trip, no drive state, a set tank and condition for the item
create or replace function pg_temp.reset(p_uid uuid, p_item text, p_fuel numeric, p_cond numeric) returns void
language plpgsql as $$
begin
  update profiles set travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
         location_id = (select id from d3_places where kind = 'src'), cash = 5000000, bank = 0 where id = p_uid;
  delete from drive_state where user_id = p_uid;
  delete from drive_trip where user_id = p_uid;
  delete from vehicle_state where user_id = p_uid;
  if p_item is not null then
    insert into vehicle_state (user_id, item_id, fuel_l, cond) values (p_uid, p_item, p_fuel, p_cond);
  end if;
end $$;

create temp table d3_u (name text primary key, id uuid);
create temp table d3_places (kind text primary key, id text, km numeric);

do $$
declare v uuid; src text;
begin
  v := pg_temp.new_user('d3_a@drive.bl');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(v);
  perform create_profile_v2('D3_a', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  insert into d3_u values ('a', v);
  select location_id into src from profiles where id = v;
  insert into d3_places select 'src', src, 0;
  insert into d3_places select 'far', l.id, bl_distance_km(src, l.id) from locations l
   where l.active and l.id <> src and l.id not like 'home\_%' and bl_place_open(l) order by bl_distance_km(src, l.id) desc, l.id limit 1;
  insert into d3_places select 'near', l.id, bl_distance_km(src, l.id) from locations l
   where l.active and l.id <> src and l.id not like 'home\_%' and bl_place_open(l) order by bl_distance_km(src, l.id), l.id limit 1;
  insert into inventory (user_id, item_id, qty) values (v, 'kia_rio_used', 1) on conflict (user_id, item_id) do update set qty = 1;
  perform pg_temp.setc('rent.enabled', 'false');
  perform pg_temp.setc('drive.enabled', 'true');
  perform pg_temp.setc('drive.events_enabled', 'true');
  perform pg_temp.setc('drive.travel.real_time_enabled', 'true');
  perform pg_temp.setc('drive.travel.min_seconds', '100');   -- long enough that the steering clamps by elapsed time are testable
  perform pg_temp.setc('drive.travel.max_seconds', '150');
  perform pg_temp.setc('drive.roll_gap_s', '0');
  perform pg_temp.setc('drive.cooldown_s', '0');
  perform pg_temp.setc('drive.max_delay_s', '600');
  update profiles set needs_updated_at = bl_now() where id = v;
end $$;

-- ---------- 1. settings ----------
do $$
declare n int;
begin
  perform pg_temp.assert((select count(*) from game_config where key like any (array['drive.steer.%', 'drive.fuel.%', 'drive.dry.%', 'drive.damage.%', 'drive.repair.%', 'drive.weather.%', 'drive.rain.%'])) >= 60,
    'drive 3 settings seeded');
  select count(*) into n from game_config where key like any (array['drive.steer.%', 'drive.fuel.%', 'drive.dry.%', 'drive.damage.%', 'drive.repair.%', 'drive.weather.%', 'drive.rain.%'])
     and (category <> 'drive' or coalesce(label, '') = '' or coalesce(description, '') = '' or (kind in ('number', 'naira', 'percent') and (min is null or max is null)));
  perform pg_temp.assert(n = 0, 'every drive 3 setting is in category drive, has a label, a description and a range (' || n || ' without)');
  perform pg_temp.assert((select count(*) from game_config where key like 'drive.%' and (label ilike '%lagos%' or description ilike '%lagos%')) = 0, 'no "Lagos" in the settings text');
  perform pg_temp.assert((select kind from game_config where key = 'drive.steer.enabled') = 'bool' and (select kind from game_config where key = 'drive.fuel.enabled') = 'bool'
    and (select kind from game_config where key = 'drive.weather.enabled') = 'bool', 'the switches are bools');
  perform pg_temp.assert(bl_cfg('drive.steer.max_save_pct') = 12 and bl_cfg('drive.fuel.tank_car') = 45 and bl_cfg('drive.damage.ambush') = 12, 'defaults');
end $$;

-- ---------- 2. weather: a deterministic daily schedule ----------
do $$
declare a uuid := (select id from d3_u where name = 'a'); t1 timestamptz := timestamptz '2026-11-10 23:30:00+01'; w jsonb; w2 jsonb; rainy int := 0; h int;
begin
  perform pg_temp.login(a);
  perform pg_temp.setc('drive.weather.enabled', 'true');
  perform pg_temp.setc('drive.weather.force_rain', 'false');
  perform pg_temp.assert(bl_drive_weather(t1) = bl_drive_weather(t1), 'same instant, same weather');
  -- a day that always rains, a window as long as the day: late evening is wet
  perform pg_temp.setc('drive.weather.rain_day_pct', '100'); perform pg_temp.setc('drive.weather.rain_min_h', '24'); perform pg_temp.setc('drive.weather.rain_max_h', '24');
  perform pg_temp.assert((bl_drive_weather(t1) ->> 'rain')::boolean, 'rain day, long window: it rains at 23:30');
  perform pg_temp.assert((bl_drive_weather(timestamptz '2026-11-10 00:10:00+01') ->> 'rain')::boolean is false, 'before the window opens (start is 05:00 or later) it is dry');
  perform pg_temp.setc('drive.weather.rain_day_pct', '0');
  perform pg_temp.assert((bl_drive_weather(t1) ->> 'rain')::boolean is false, 'chance 0: never rains');
  -- the chance really picks days: 100 days at 30 % land well inside 10 .. 55 rainy days
  perform pg_temp.setc('drive.weather.rain_day_pct', '30'); perform pg_temp.setc('drive.weather.rain_min_h', '2'); perform pg_temp.setc('drive.weather.rain_max_h', '4');
  for h in 0..99 loop
    w := bl_drive_weather(timestamptz '2026-01-01 12:00:00+01' + make_interval(days => h));
    if (w ->> 'rain_today')::boolean then rainy := rainy + 1; end if;
  end loop;
  perform pg_temp.assert(rainy between 10 and 55, 'about 30 % of days are rainy (' || rainy || ' of 100)');
  w := (select x from (select bl_drive_weather(timestamptz '2026-01-01 12:00:00+01' + make_interval(days => g)) x from generate_series(0, 60) g) q where (x ->> 'rain_today')::boolean limit 1);
  perform pg_temp.assert((w ->> 'start_hour')::numeric between 5 and 19 and (w ->> 'end_hour')::numeric - (w ->> 'start_hour')::numeric between 1.99 and 4.01, 'the window starts 05 .. 19 and lasts 2 .. 4 hours');
  -- the salt reshuffles
  w := (select jsonb_agg(bl_drive_weather(timestamptz '2026-03-01 12:00:00+01' + make_interval(days => g)) -> 'rain_today') from generate_series(0, 40) g);
  perform pg_temp.setc('drive.weather.salt', '99');
  w2 := (select jsonb_agg(bl_drive_weather(timestamptz '2026-03-01 12:00:00+01' + make_interval(days => g)) -> 'rain_today') from generate_series(0, 40) g);
  perform pg_temp.assert(w <> w2, 'another salt, another schedule');
  perform pg_temp.setc('drive.weather.salt', '7');
  perform pg_temp.setc('drive.weather.force_rain', 'true');
  perform pg_temp.assert((bl_drive_weather(t1) ->> 'rain')::boolean and (drive_weather() ->> 'rain')::boolean, 'force rain: raining, also through the RPC');
  perform pg_temp.setc('drive.weather.enabled', 'false');
  perform pg_temp.assert((bl_drive_weather(t1) ->> 'rain')::boolean is false, 'weather off beats force rain');
  perform pg_temp.setc('drive.weather.force_rain', 'false');
end $$;

-- ---------- 3. the quote: rain, wear, a vehicle that will not start ----------
do $$
declare a uuid := (select id from d3_u where name = 'a'); far text := (select id from d3_places where kind = 'far'); base numeric; wet numeric; worn numeric; o jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.reset(a, 'kia_rio_used', 30, 100);
  base := (pg_temp.opt(a, far, 'car') ->> 'real_seconds')::numeric;
  perform pg_temp.setc('drive.weather.enabled', 'true'); perform pg_temp.setc('drive.weather.force_rain', 'true');
  wet := (pg_temp.opt(a, far, 'car') ->> 'real_seconds')::numeric;
  perform pg_temp.assert(abs(wet - round(base * 1.1, 1)) < 0.21, 'rain: the car trip is 10 % longer (' || base || ' -> ' || wet || ')');
  perform pg_temp.setc('drive.weather.force_rain', 'false'); perform pg_temp.setc('drive.weather.enabled', 'false');
  perform pg_temp.reset(a, 'kia_rio_used', 30, 50);
  perform pg_temp.assert((pg_temp.opt(a, far, 'car') ->> 'real_seconds')::numeric = base, 'condition at the threshold: no slowdown');
  perform pg_temp.reset(a, 'kia_rio_used', 30, 25);
  worn := (pg_temp.opt(a, far, 'car') ->> 'real_seconds')::numeric;
  perform pg_temp.assert(abs(worn - round(base * (1 + 0.5 * 0.25), 1)) < 0.21, 'condition 25 (half way): half of the 25 % (' || base || ' -> ' || worn || ')');
  perform pg_temp.reset(a, 'kia_rio_used', 30, 0);
  o := pg_temp.opt(a, far, 'car');
  perform pg_temp.assert((o ->> 'allowed')::boolean is false and o ->> 'reason' ilike '%too damaged%' and o ->> 'reason' ilike '%keke%', 'condition 0: the car will not start, with a message');
  perform pg_temp.assert(coalesce(pg_temp.opt(a, far, 'keke') ->> 'reason', '') not ilike '%damaged%' and (pg_temp.opt(a, far, 'walk') ->> 'allowed')::boolean, 'the keke and walking are never blocked by a damaged car');
  perform pg_temp.assert(pg_temp.hint_of('select travel_start(' || quote_literal(far) || ', ''car'')') <> 'ok', 'travel_start refuses a car at condition 0');
  perform pg_temp.assert(pg_temp.hint_of('select travel_start(' || quote_literal(far) || ', ''walk'')') = 'ok', 'walking still starts (never a softlock)');
  perform pg_temp.setc('drive.damage.enabled', 'false');
  perform pg_temp.reset(a, 'kia_rio_used', 30, 0);
  perform pg_temp.assert((pg_temp.opt(a, far, 'car') ->> 'allowed')::boolean and (pg_temp.opt(a, far, 'car') ->> 'real_seconds')::numeric = base, 'damage switched off: a car at 0 drives, no slowdown');
  perform pg_temp.setc('drive.damage.enabled', 'true');
end $$;

-- ---------- 4. fuel burn and the check before the trip ----------
do $$
declare a uuid := (select id from d3_u where name = 'a'); far text := (select id from d3_places where kind = 'far'); km numeric := (select km from d3_places where kind = 'far');
  want numeric; got numeric; r jsonb; tr drive_trip;
begin
  perform pg_temp.login(a);
  perform pg_temp.reset(a, 'kia_rio_used', 30, 100);
  want := round(km * 5 * 0.11, 2);
  r := vehicle_trip_check(far);
  perform pg_temp.assert((r ->> 'applies')::boolean and (r ->> 'need_l')::numeric = want and (r ->> 'enough')::boolean and (r ->> 'fuel_l')::numeric = 30, 'trip check: need ' || want || ' L, 30 L is enough');
  perform travel_start(far, 'car');
  got := (select fuel_l from vehicle_state where user_id = a and item_id = 'kia_rio_used');
  perform pg_temp.assert(abs(got - (30 - want)) < 0.011, 'the trip burned the litres: 30 - ' || want || ' (tank now ' || got || ')');
  select * into tr from drive_trip where user_id = a;
  perform pg_temp.assert(tr.dry_prog is null and tr.need_l = want and tr.fuel_before = 30 and tr.mode = 'car', 'the trip row remembers the burn, no dry-out');
  -- a worn car burns more
  perform pg_temp.reset(a, 'kia_rio_used', 30, 1);
  r := vehicle_trip_check(far);
  perform pg_temp.assert((r ->> 'need_l')::numeric > want * 1.3 and (r ->> 'need_l')::numeric <= want * 1.41, 'a nearly dead car burns about 40 % more (' || want || ' -> ' || (r ->> 'need_l') || ')');
  -- a short tank: the check says short, travel_start records where it dries out
  perform pg_temp.reset(a, 'kia_rio_used', want / 2, 100);
  r := vehicle_trip_check(far);
  perform pg_temp.assert(not (r ->> 'enough')::boolean and (r ->> 'short_l')::numeric > 0, 'trip check: the tank cannot cover it, and by how much');
  perform travel_start(far, 'car');
  select * into tr from drive_trip where user_id = a;
  perform pg_temp.assert(tr.dry_prog is not null and abs(tr.dry_prog - 0.5) < 0.02, 'half a tank: it dries out about half way (' || tr.dry_prog || ')');
  perform pg_temp.assert((select fuel_l from vehicle_state where user_id = a) = 0, 'the tank is empty after the trip');
  perform pg_temp.reset(a, 'kia_rio_used', 0, 100);
  perform travel_start(far, 'car');
  perform pg_temp.assert((select dry_prog from drive_trip where user_id = a) = 0.15, 'an empty tank dries out at 15 %');
  -- other modes burn nothing
  perform pg_temp.reset(a, 'kia_rio_used', 30, 100);
  perform travel_start(far, 'drop');
  perform pg_temp.assert((select fuel_l from vehicle_state where user_id = a) = 30 and (select dry_prog from drive_trip where user_id = a) is null, 'a drop trip burns none of your fuel');
  -- a bicycle has no tank
  perform pg_temp.reset(a, null, 0, 100);
  insert into inventory (user_id, item_id, qty) values (a, 'bicycle', 1) on conflict (user_id, item_id) do update set qty = 1;
  update inventory set qty = 0 where user_id = a and item_id = 'kia_rio_used';
  r := vehicle_trip_check(far);
  perform pg_temp.assert(r ->> 'class' = 'bicycle' and (r ->> 'need_l')::numeric = 0 and (r ->> 'enough')::boolean, 'a bicycle needs no fuel');
  perform travel_start(far, 'car');
  perform pg_temp.assert((select dry_prog from drive_trip where user_id = a) is null and (select need_l from drive_trip where user_id = a) = 0, 'a bicycle trip never dries out');
  update inventory set qty = 1 where user_id = a and item_id = 'kia_rio_used';
  update inventory set qty = 0 where user_id = a and item_id = 'bicycle';
  perform pg_temp.reset(a, null, 0, 100);
  r := vehicle_status();
  perform pg_temp.assert((r -> 'cars' -> 0 ->> 'fuel_l')::numeric = round(45 * 0.8, 1) and (r -> 'cars' -> 0 ->> 'cond')::numeric = 100, 'a vehicle the server has not seen starts at 80 % of the tank');
end $$;

-- ---------- 5. dry-out outcomes ----------
do $$
declare a uuid := (select id from d3_u where name = 'a'); far text := (select id from d3_places where kind = 'far'); tot numeric; ev jsonb; r jsonb; t0 timestamptz; cash0 bigint;
begin
  perform pg_temp.login(a);
  perform pg_temp.setc('drive.min_progress_pct', '99'); perform pg_temp.setc('drive.max_progress_pct', '99'); -- no ordinary event may appear
  perform pg_temp.setc('drive.dry.push_fail_pct', '0'); perform pg_temp.setc('drive.dry.mechanic_wait_min_s', '10'); perform pg_temp.setc('drive.dry.mechanic_wait_max_s', '10');
  perform pg_temp.reset(a, 'kia_rio_used', 1, 100);
  perform travel_start(far, 'car');
  tot := (select extract(epoch from travel_arrives_at - travel_started_at) from profiles where id = a);
  perform pg_temp.adv(tot * 0.05);
  perform pg_temp.assert((drive_event_roll() -> 'event') = 'null'::jsonb, 'before the tank runs dry there is no card');
  perform pg_temp.adv(tot * 0.9);
  ev := drive_event_roll();
  perform pg_temp.assert(ev -> 'event' ->> 'kind' = 'dry' and jsonb_array_length(ev -> 'event' -> 'choices') = 3, 'after the dry point: the stranded card with 3 choices');
  perform pg_temp.assert((select array_agg(c ->> 'id' order by c ->> 'id') from jsonb_array_elements(ev -> 'event' -> 'choices') c) = array['keke', 'mechanic', 'push'], 'push, mechanic, keke');
  perform pg_temp.assert((drive_event_roll() ->> 'resumed')::boolean, 'the card is shown again after a reload (resumed)');
  perform pg_temp.assert(pg_temp.hint_of('select drive_event_choose(''bogus'')') = 'bad_choice', 'a choice that is not on the card is refused');
  t0 := (select travel_arrives_at from profiles where id = a);
  r := drive_event_choose('push');
  perform pg_temp.assert((r ->> 'delay_s')::int = 25 and r ->> 'kind' = 'dry' and (select travel_arrives_at from profiles where id = a) >= t0 + interval '24 seconds', 'push: 25 s lost, the arrival moved');
  perform pg_temp.assert((select pending from drive_state where user_id = a) is null and (select fuel_l from vehicle_state where user_id = a) = 0, 'push: the card is gone, the tank stays empty');
  perform pg_temp.assert(pg_temp.hint_of('select drive_event_choose(''push'')') = 'no_event', 'answered once only');
  perform pg_temp.assert((drive_event_roll() -> 'event') = 'null'::jsonb, 'the dry card does not come twice on one trip');
  -- push (bad)
  perform pg_temp.setc('drive.dry.push_fail_pct', '100');
  perform pg_temp.reset(a, 'kia_rio_used', 1, 100);
  perform travel_start(far, 'car'); perform pg_temp.adv(tot * 0.95); perform drive_event_roll();
  r := drive_event_choose('push');
  perform pg_temp.assert((r ->> 'delay_s')::int = 25 + 15 and r ->> 'tone' = 'bad', 'a bad push: 25 + 15 s');
  -- mechanic
  perform pg_temp.reset(a, 'kia_rio_used', 1, 100);
  perform travel_start(far, 'car'); perform pg_temp.adv(tot * 0.95); perform drive_event_roll();
  update profiles set cash = 5000 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select drive_event_choose(''mechanic'')') = 'not_enough_cash', 'a mechanic you cannot pay: refused with a clear hint');
  perform pg_temp.assert((select pending from drive_state where user_id = a) is not null, 'the card stays so you can choose another way');
  update profiles set cash = 100000 where id = a; cash0 := 100000;
  r := drive_event_choose('mechanic');
  perform pg_temp.assert((r ->> 'cash_delta')::bigint = -12000 and (select cash from profiles where id = a) = cash0 - 12000, 'mechanic: 12,000 paid');
  perform pg_temp.assert((r ->> 'delay_s')::int = 10, 'mechanic: the wait is rolled between the min and max (10 .. 10)');
  perform pg_temp.assert((select fuel_l from vehicle_state where user_id = a) = 6, 'mechanic: 6 litres in the tank');
  -- keke
  perform pg_temp.reset(a, 'kia_rio_used', 1, 100);
  perform travel_start(far, 'car'); perform pg_temp.adv(tot * 0.95); perform drive_event_roll();
  cash0 := (select cash from profiles where id = a);
  r := drive_event_choose('keke');
  perform pg_temp.assert((r ->> 'cash_delta')::bigint = -3000 and (select cash from profiles where id = a) = cash0 - 3000 and (r ->> 'delay_s')::int = 40, 'keke: 3,000 and 40 s later');
  -- the mechanic wait is inside the range
  perform pg_temp.setc('drive.dry.mechanic_wait_min_s', '5'); perform pg_temp.setc('drive.dry.mechanic_wait_max_s', '9');
  perform pg_temp.reset(a, 'kia_rio_used', 1, 100);
  perform travel_start(far, 'car'); perform pg_temp.adv(tot * 0.95); perform drive_event_roll();
  r := drive_event_choose('mechanic');
  perform pg_temp.assert((r ->> 'delay_s')::int between 5 and 9, 'mechanic wait rolled in 5 .. 9 (' || (r ->> 'delay_s') || ')');
  -- fuel off: nothing burns, nothing dries
  perform pg_temp.setc('drive.fuel.enabled', 'false');
  perform pg_temp.reset(a, 'kia_rio_used', 1, 100);
  perform travel_start(far, 'car'); perform pg_temp.adv(tot * 0.95);
  perform pg_temp.assert((drive_event_roll() -> 'event') = 'null'::jsonb and (select fuel_l from vehicle_state where user_id = a) = 1, 'fuel off: no burn, no stranded card');
  perform pg_temp.setc('drive.fuel.enabled', 'true');
  perform pg_temp.setc('drive.min_progress_pct', '15'); perform pg_temp.setc('drive.max_progress_pct', '85');
end $$;

-- ---------- 6. refuel: pump, bag, grey petrol ----------
do $$
declare a uuid := (select id from d3_u where name = 'a'); r jsonb; price bigint; cash0 bigint; c0 numeric;
begin
  perform pg_temp.login(a);
  perform pg_temp.reset(a, 'kia_rio_used', 10, 100);
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_refuel(''pump'', 5)') = 'not_at_station', 'the pump needs a filling station');
  update profiles set location_id = 'fs_sapele' where id = a;
  r := vehicle_status();
  perform pg_temp.assert(r -> 'station' ->> 'id' = 'fs_sapele' and (r -> 'station' ->> 'price')::bigint > 0, 'status shows the station and the petrol price');
  price := (r -> 'station' ->> 'price')::bigint;
  cash0 := (select cash from profiles where id = a);
  r := vehicle_refuel('pump', 10);
  perform pg_temp.assert((r ->> 'litres')::numeric = 10 and (r ->> 'cost')::bigint = price * 10 and (select cash from profiles where id = a) = cash0 - price * 10, 'pump: 10 litres at the pump price, paid in cash');
  perform pg_temp.assert((select fuel_l from vehicle_state where user_id = a) = 20, 'pump: the tank went from 10 to 20');
  r := vehicle_refuel('pump', 500);
  perform pg_temp.assert((r ->> 'fuel_l')::numeric = 45 and (r ->> 'litres')::numeric = 25, 'pump: never more than the tank holds (45)');
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_refuel(''pump'', 5)') = 'tank_full', 'a full tank is refused');
  update vehicle_state set fuel_l = 10 where user_id = a;
  update profiles set cash = 100 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_refuel(''pump'', 20)') = 'not_enough_cash', 'no cash for the pump: refused');
  update profiles set cash = 5000000 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_refuel(''diesel'', 5)') = 'not_fuel', 'diesel is not petrol for this car');
  perform bl_give_item(a, 'petrol_can', 2);
  perform bl_give_item(a, 'petrol', 3);
  r := vehicle_status();
  perform pg_temp.assert((r ->> 'bag_l')::numeric = 13, 'status counts the petrol in the bag (2 cans + 3 litres = 13)');
  r := vehicle_refuel('petrol_can', 2);
  perform pg_temp.assert((r ->> 'litres')::numeric = 10 and (select fuel_l from vehicle_state where user_id = a) = 20 and
    coalesce((select qty from inventory where user_id = a and item_id = 'petrol_can'), 0) = 0, 'bag: two cans = 10 litres, cans used up');
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_refuel(''petrol_can'', 1)') = 'no_fuel_item', 'cannot pour a can you do not have');
  r := vehicle_refuel('petrol', 99);
  perform pg_temp.assert((r ->> 'litres')::numeric = 3 and coalesce((select qty from inventory where user_id = a and item_id = 'petrol'), 0) = 0, 'bag: pours what the bag has');
  perform bl_give_item(a, 'petrol_bm', 2);
  perform pg_temp.setc('power.bad_fuel_pct', '100');
  c0 := (select cond from vehicle_state where user_id = a);
  r := vehicle_refuel('petrol_bm', 1);
  perform pg_temp.assert((r ->> 'bad_batch')::boolean and (select cond from vehicle_state where user_id = a) = c0 - 6, 'bad grey petrol: the car loses 6 condition');
  perform pg_temp.setc('power.bad_fuel_pct', '0');
  r := vehicle_refuel('petrol_bm', 1);
  perform pg_temp.assert(not (r ->> 'bad_batch')::boolean, 'a good batch: no damage');
  perform pg_temp.reset(a, 'kia_rio_used', 10, 100);
  perform travel_start((select id from d3_places where kind = 'far'), 'drop');
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_refuel(''pump'', 5)') <> 'ok', 'no refuelling on the road');
  perform pg_temp.setc('drive.fuel.enabled', 'false');
  perform pg_temp.reset(a, 'kia_rio_used', 10, 100);
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_refuel(''pump'', 5)') = 'off', 'fuel switched off: refuel refused');
  perform pg_temp.setc('drive.fuel.enabled', 'true');
end $$;

-- ---------- 7. repair cost and repair ----------
do $$
declare a uuid := (select id from d3_u where name = 'a'); r jsonb; cash0 bigint;
begin
  perform pg_temp.login(a);
  perform pg_temp.assert(bl_vehicle_repair_cost('kia_rio_used', 100) = 0, 'a perfect car costs nothing');
  perform pg_temp.assert(bl_vehicle_repair_cost('kia_rio_used', 40) = 54000, 'car at 40: 60 points x 900 = 54,000');
  perform pg_temp.assert(bl_vehicle_repair_cost('kia_rio_used', 99) = 2000, 'a scratch costs the minimum fee (2,000)');
  perform pg_temp.assert(bl_vehicle_repair_cost('lexus_rx350', 40) = 86400 and bl_vehicle_repair_cost('hilux_new', 40) = 75600, 'SUV x1.6 and pickup x1.4');
  perform pg_temp.assert(bl_vehicle_repair_cost('bajaj_boxer', 40) = 21600 and bl_vehicle_repair_cost('bicycle', 0) = 9000, 'motorcycle x0.4, bicycle x0.1');
  perform pg_temp.assert(bl_vehicle_repair_cost('kia_rio_used', 20) > bl_vehicle_repair_cost('kia_rio_used', 60), 'more damage costs more');
  perform pg_temp.reset(a, 'kia_rio_used', 30, 40);
  r := vehicle_status();
  perform pg_temp.assert((r -> 'cars' -> 0 ->> 'repair_cost')::bigint = 54000 and (r -> 'cars' -> 0 ->> 'callout_cost')::bigint = 86400, 'status: repair 54,000, call-out x1.6 = 86,400');
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_repair()') = 'not_at_mechanic', 'away from the mechanic: go there or call one');
  cash0 := (select cash from profiles where id = a);
  r := vehicle_repair(null, true);
  perform pg_temp.assert((r ->> 'cost')::bigint = 86400 and (select cash from profiles where id = a) = cash0 - 86400 and (select cond from vehicle_state where user_id = a) = 100, 'call-out: 86,400 and the car is 100');
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_repair(null, true)') = 'nothing_to_fix', 'nothing to repair at 100');
  update vehicle_state set cond = 40 where user_id = a;
  update profiles set location_id = 'mechanic_village' where id = a;
  perform pg_temp.assert((vehicle_status() ->> 'at_mechanic')::boolean, 'status says you are at the mechanic');
  cash0 := (select cash from profiles where id = a);
  r := vehicle_repair();
  perform pg_temp.assert((r ->> 'cost')::bigint = 54000 and (select cash from profiles where id = a) = cash0 - 54000 and (select cond from vehicle_state where user_id = a) = 100, 'mechanic village: 54,000, condition 100');
  update vehicle_state set cond = 40 where user_id = a;
  update profiles set cash = 10000, bank = 50000 where id = a;
  r := vehicle_repair();
  perform pg_temp.assert((select bank from profiles where id = a) = 0 and (select cash from profiles where id = a) = 6000, 'the bank pays first, cash covers the rest');
  update vehicle_state set cond = 0 where user_id = a;
  update profiles set cash = 1000, bank = 0 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_repair()') = 'not_enough_cash', 'cannot pay: refused');
  perform pg_temp.assert((select cond from vehicle_state where user_id = a) = 0, 'condition stays 0');
  update profiles set cash = 5000000, location_id = (select id from d3_places where kind = 'src') where id = a;
  perform pg_temp.setc('drive.repair.callout_on', 'false');
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_repair(null, true)') = 'callout_off', 'call-outs off: refused');
  perform pg_temp.setc('drive.repair.callout_on', 'true');
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_repair(null, true)') = 'ok', 'a car at 0 can be repaired where it stands');
  update vehicle_state set cond = 50 where user_id = a;
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_repair(''lambo_urus'', true)') = 'not_owned', 'a vehicle you do not own');
  perform travel_start((select id from d3_places where kind = 'far'), 'drop');
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_repair(null, true)') <> 'ok', 'no repair while travelling');
  perform pg_temp.setc('drive.damage.enabled', 'false');
  perform pg_temp.reset(a, 'kia_rio_used', 30, 40);
  perform pg_temp.assert(pg_temp.hint_of('select vehicle_repair(null, true)') = 'off', 'damage off: repair refused');
  perform pg_temp.setc('drive.damage.enabled', 'true');
end $$;

-- ---------- 8. drive_report: clamps and rate limits ----------
do $$
declare a uuid := (select id from d3_u where name = 'a'); far text := (select id from d3_places where kind = 'far'); tot numeric; key text; r jsonb; arr0 timestamptz; c0 numeric; t drive_trip; arr1 timestamptz;
begin
  perform pg_temp.login(a);
  perform pg_temp.setc('drive.steer.report_gap_s', '5');
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  key := (select travel_started_at::text from profiles where id = a);
  tot := (select extract(epoch from travel_arrives_at - travel_started_at) from profiles where id = a);
  arr0 := (select travel_arrives_at from profiles where id = a);
  perform pg_temp.assert(drive_report('nonsense', '{"passes":3}') ->> 'reason' = 'no_trip', 'a report for another trip is ignored');
  perform pg_temp.assert(drive_report('2001-01-01T00:00:00Z', '{"passes":3}') ->> 'reason' = 'no_trip', 'a report with another start time is ignored');
  perform pg_temp.adv(1);
  r := drive_report(key, '{"passes":1000,"gaps":1000,"hits":1000,"offroad":1000}');
  perform pg_temp.assert((r ->> 'ok')::boolean and (r -> 'applied' ->> 'passes')::int = 0 and (r -> 'applied' ->> 'gaps')::int = 0 and (r -> 'applied' ->> 'hits')::int = 0 and (r -> 'applied' ->> 'offroad')::int = 0,
    'one second in: elapsed time allows no overtake and no hit (all clamped to 0)');
  perform pg_temp.assert((r ->> 'saved_s')::numeric = 0 and (r ->> 'damage')::numeric = 0 and (select travel_arrives_at from profiles where id = a) = arr0, 'so no time moved and no damage');
  perform pg_temp.adv(2);
  perform pg_temp.assert(drive_report(key, '{"passes":1}') ->> 'reason' = 'too_soon', 'a second report inside the gap is refused (rate limit)');
  perform pg_temp.adv(60);
  c0 := (select cond from vehicle_state where user_id = a);
  r := drive_report(key, '{"passes":1000,"gaps":1000,"hits":1000,"offroad":1000,"saved":999,"seconds":-500}');
  perform pg_temp.assert((r ->> 'ok')::boolean, 'a report 63 s in is accepted');
  perform pg_temp.assert((r -> 'applied' ->> 'passes')::int = 10 and (r -> 'applied' ->> 'gaps')::int = 8, 'passes capped at 10, gaps at 8 per trip (and by time: 63 s / 6 = 10)');
  perform pg_temp.assert((r -> 'applied' ->> 'hits')::int = 5 and (r -> 'applied' ->> 'offroad')::int = 6, 'hits capped at 5, off-road at 6');
  perform pg_temp.assert((r ->> 'damage')::numeric = 25 and (select cond from vehicle_state where user_id = a) = c0 - 25, 'damage 5x6 + 6x2 = 42 clamped to the 25 per trip, condition 100 -> 75');
  perform pg_temp.assert((r ->> 'saved_s')::numeric <= least(20, tot * 0.12) + 0.05 and (r ->> 'saved_s')::numeric > 0, 'time saved is within min(20 s, 12 % of the trip) (' || (r ->> 'saved_s') || ')');
  perform pg_temp.assert((r ->> 'lost_s')::numeric = 15, 'time lost: 5 x 2.5 + 6 x 1.5 = 21.5 clamped to 15');
  arr1 := (select travel_arrives_at from profiles where id = a);
  perform pg_temp.assert(abs(extract(epoch from arr1 - arr0) - ((r ->> 'lost_s')::numeric - (r ->> 'saved_s')::numeric)) < 0.01, 'the arrival moved by exactly lost - saved');
  perform pg_temp.assert(arr1 > bl_now() + interval '3 seconds', 'the arrival is never in the past');
  perform pg_temp.adv(6);
  r := drive_report(key, '{"passes":1000,"gaps":1000,"hits":1000,"offroad":1000}');
  perform pg_temp.assert((r -> 'applied' ->> 'passes')::int = 0 and (r -> 'applied' ->> 'hits')::int = 0 and (r ->> 'saved_s')::numeric = 0 and (r ->> 'damage')::numeric = 0, 'a second report cannot claim the same caps again');
  select * into t from drive_trip where user_id = a;
  perform pg_temp.assert(t.steer_passes <= 10 and t.steer_hits <= 5 and t.steer_damage <= 25 and t.steer_lost_s <= 15, 'the trip totals stay inside the caps');
  perform pg_temp.setc('drive.steer.max_reports', '3');
  perform pg_temp.adv(6); perform drive_report(key, '{}');
  perform pg_temp.adv(6);
  perform pg_temp.assert(drive_report(key, '{"passes":1}') ->> 'reason' = 'max_reports', 'more than max_reports per trip: refused');
  perform pg_temp.setc('drive.steer.max_reports', '12');
  -- the ISO start time the app holds is accepted too
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  perform pg_temp.adv(30);
  r := drive_report(to_char((select travel_started_at from profiles where id = a) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'), '{"passes":1}');
  perform pg_temp.assert((r ->> 'ok')::boolean and (r -> 'applied' ->> 'passes')::int = 1, 'the ISO start time (milliseconds) is the same trip');
  -- garbage never breaks anything
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  key := (select travel_started_at::text from profiles where id = a);
  perform pg_temp.adv(70);
  r := drive_report(key, '{"passes":-5,"hits":"abc","gaps":null,"offroad":[1],"extra":{"a":1}}');
  perform pg_temp.assert((r ->> 'ok')::boolean and (r ->> 'saved_s')::numeric = 0 and (r ->> 'damage')::numeric = 0, 'negative, text, null and array values count as 0');
  perform pg_temp.adv(6);
  perform pg_temp.assert((drive_report(key, null) ->> 'ok')::boolean and (drive_report(key, null) ->> 'reason') = 'too_soon', 'a null report is harmless');
  perform pg_temp.adv(6);
  perform pg_temp.assert((drive_report(key, '"hello"') ->> 'ok')::boolean, 'a non-object report is harmless');
  -- saving never lands in the past even with silly settings
  perform pg_temp.setc('drive.steer.max_save_pct', '50'); perform pg_temp.setc('drive.steer.max_save_s', '300'); perform pg_temp.setc('drive.steer.s_per_pass', '30');
  perform pg_temp.setc('drive.steer.max_passes', '100'); perform pg_temp.setc('drive.steer.min_s_per_pass', '1');
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  key := (select travel_started_at::text from profiles where id = a);
  perform pg_temp.adv(tot - 2);
  r := drive_report(key, '{"passes":100,"hits":0}');
  perform pg_temp.assert((select travel_arrives_at from profiles where id = a) >= bl_now() + interval '3 seconds' - interval '0.01 second', 'saving cannot pull the arrival closer than 3 s from now');
  perform pg_temp.setc('drive.steer.max_save_pct', '12'); perform pg_temp.setc('drive.steer.max_save_s', '20'); perform pg_temp.setc('drive.steer.s_per_pass', '1.2');
  perform pg_temp.setc('drive.steer.max_passes', '10'); perform pg_temp.setc('drive.steer.min_s_per_pass', '6');
  -- only your own vehicle
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'drop');
  key := (select travel_started_at::text from profiles where id = a);
  perform pg_temp.adv(60);
  perform pg_temp.assert(drive_report(key, '{"passes":3}') ->> 'reason' = 'no_trip', 'a drop passenger cannot report steering');
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  key := (select travel_started_at::text from profiles where id = a);
  perform pg_temp.adv(tot + 30);
  perform pg_temp.assert(drive_report(key, '{"passes":3}') ->> 'reason' = 'late', 'a report after the arrival time is refused');
  perform pg_temp.setc('drive.steer.enabled', 'false');
  perform pg_temp.assert(drive_report(key, '{"passes":3}') ->> 'reason' = 'off', 'steering off: refused');
  perform pg_temp.setc('drive.steer.enabled', 'true');
end $$;

-- ---------- 8b. rain: more damage, a skid ----------
do $$
declare a uuid := (select id from d3_u where name = 'a'); far text := (select id from d3_places where kind = 'far'); key text; r jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.setc('drive.weather.enabled', 'true'); perform pg_temp.setc('drive.weather.force_rain', 'true');
  perform pg_temp.setc('drive.rain.skid_pct', '0');
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  perform pg_temp.assert((select rain from drive_trip where user_id = a), 'the trip row remembers it is raining');
  key := (select travel_started_at::text from profiles where id = a);
  perform pg_temp.adv(40);
  r := drive_report(key, '{"hits":2}');
  perform pg_temp.assert((r ->> 'damage')::numeric = 18 and not (r ->> 'skid')::boolean, 'rain: 2 hits x 6 x 1.5 = 18');
  perform pg_temp.setc('drive.rain.skid_pct', '100');
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  key := (select travel_started_at::text from profiles where id = a);
  perform pg_temp.adv(40);
  r := drive_report(key, '{}');
  perform pg_temp.assert((r ->> 'skid')::boolean and (r ->> 'damage')::numeric = 3 and (select cond from vehicle_state where user_id = a) = 97, 'rain skid (100 %): 3 condition');
  perform pg_temp.adv(6);
  r := drive_report(key, '{}');
  perform pg_temp.assert(not (r ->> 'skid')::boolean and (r ->> 'damage')::numeric = 0, 'the skid is rolled once per trip');
  perform pg_temp.setc('drive.weather.force_rain', 'false'); perform pg_temp.setc('drive.weather.enabled', 'false');
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  key := (select travel_started_at::text from profiles where id = a);
  perform pg_temp.adv(40);
  r := drive_report(key, '{"hits":2}');
  perform pg_temp.assert((r ->> 'damage')::numeric = 12, 'dry road: 2 hits x 6 = 12');
end $$;

-- ---------- 9. damage from road events (own vehicle only) ----------
do $$
declare a uuid := (select id from d3_u where name = 'a'); far text := (select id from d3_places where kind = 'far'); r jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.setc('drive.ambush.escape_pct', '0'); perform pg_temp.setc('drive.goslow.shortcut_pct', '0');
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  insert into drive_state (user_id, trip_key, pending, pending_at) values (a, (select travel_started_at::text from profiles where id = a), '{"kind":"ambush","amount":1000}', bl_now())
    on conflict (user_id) do update set trip_key = excluded.trip_key, pending = excluded.pending, pending_at = excluded.pending_at;
  r := drive_event_choose('drive');
  perform pg_temp.assert((select cond from vehicle_state where user_id = a) = 88, 'a failed escape from area boys: 12 condition');
  update drive_state set pending = '{"kind":"goslow","amount":0}', pending_at = bl_now() where user_id = a;
  r := drive_event_choose('shortcut');
  perform pg_temp.assert((select cond from vehicle_state where user_id = a) = 82, 'a failed shortcut: 6 condition');
  update drive_state set pending = '{"kind":"ambush","amount":1000}', pending_at = bl_now() where user_id = a;
  perform pg_temp.setc('drive.ambush.escape_pct', '100');
  r := drive_event_choose('drive');
  perform pg_temp.assert((select cond from vehicle_state where user_id = a) = 82, 'a clean escape costs nothing');
  perform pg_temp.setc('drive.ambush.escape_pct', '0');
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'drop');
  insert into drive_state (user_id, trip_key, pending, pending_at) values (a, (select travel_started_at::text from profiles where id = a), '{"kind":"ambush","amount":1000}', bl_now())
    on conflict (user_id) do update set trip_key = excluded.trip_key, pending = excluded.pending, pending_at = excluded.pending_at;
  r := drive_event_choose('drive');
  perform pg_temp.assert((select cond from vehicle_state where user_id = a) = 100, 'ambushed in a drop taxi: your car is not damaged');
  perform pg_temp.setc('drive.damage.enabled', 'false');
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  insert into drive_state (user_id, trip_key, pending, pending_at) values (a, (select travel_started_at::text from profiles where id = a), '{"kind":"ambush","amount":1000}', bl_now())
    on conflict (user_id) do update set trip_key = excluded.trip_key, pending = excluded.pending, pending_at = excluded.pending_at;
  r := drive_event_choose('drive');
  perform pg_temp.assert((select cond from vehicle_state where user_id = a) = 100, 'damage off: nothing wears the car');
  perform pg_temp.setc('drive.damage.enabled', 'true');
  perform pg_temp.assert((length(pg_get_functiondef('public.drive_event_choose(text)'::regprocedure)) - length(replace(pg_get_functiondef('public.drive_event_choose(text)'::regprocedure), 'bl_vehicle_damage', ''))) / length('bl_vehicle_damage') = 1, 'drive_event_choose carries the damage patch once');
  perform pg_temp.assert((length(pg_get_functiondef('public.travel_start(text, text)'::regprocedure)) - length(replace(pg_get_functiondef('public.travel_start(text, text)'::regprocedure), 'bl_drive_trip_begin', ''))) / length('bl_drive_trip_begin') = 1, 'travel_start carries the trip patch once');
end $$;

-- ---------- 10. skipping the controls: arrive exactly as scheduled ----------
do $$
declare a uuid := (select id from d3_u where name = 'a'); far text := (select id from d3_places where kind = 'far'); arr0 timestamptz; tot numeric; r jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  arr0 := (select travel_arrives_at from profiles where id = a);
  tot := extract(epoch from arr0 - (select travel_started_at from profiles where id = a));
  perform pg_temp.adv(tot - 1);
  perform pg_temp.assert(pg_temp.hint_of('select travel_arrive()') <> 'ok', 'not arrived one second early');
  perform pg_temp.adv(2);
  r := travel_arrive();
  perform pg_temp.assert((select location_id from profiles where id = a) = far and (select travel_to from profiles where id = a) is null, 'with no report at all the player arrives at the server time');
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform pg_temp.setc('drive.steer.min_s_per_pass', '1'); perform pg_temp.setc('drive.steer.report_gap_s', '0');
  perform travel_start(far, 'car');
  perform pg_temp.adv(50);
  r := drive_report((select travel_started_at::text from profiles where id = a), '{"passes":5}');
  perform pg_temp.assert((r ->> 'saved_s')::numeric > 0, 'five clean overtakes save time');
  perform pg_temp.adv(tot - 50 - (r ->> 'saved_s')::numeric + 1);
  r := travel_arrive();
  perform pg_temp.assert((select location_id from profiles where id = a) = far, 'arrives earlier by exactly what the server granted');
  perform pg_temp.setc('drive.steer.min_s_per_pass', '6'); perform pg_temp.setc('drive.steer.report_gap_s', '5');
end $$;

-- ---------- 11. switches ----------
do $$
declare a uuid := (select id from d3_u where name = 'a'); far text := (select id from d3_places where kind = 'far'); r jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.setc('drive.enabled', 'false');
  perform pg_temp.reset(a, 'kia_rio_used', 40, 100);
  perform travel_start(far, 'car');
  perform pg_temp.adv(60);
  perform pg_temp.assert(drive_report((select travel_started_at::text from profiles where id = a), '{"passes":3}') ->> 'reason' = 'off', 'drive off: reports refused');
  perform pg_temp.setc('drive.enabled', 'true');
  r := vehicle_status();
  perform pg_temp.assert((r ->> 'fuel_on')::boolean and (r ->> 'damage_on')::boolean and (r ->> 'steer_on')::boolean, 'status carries the switches');
end $$;

-- ---------- 12. grants and RLS ----------
do $$
declare f text;
begin
  perform pg_temp.assert((select relrowsecurity from pg_class where relname = 'vehicle_state') and (select relrowsecurity from pg_class where relname = 'drive_trip'), 'RLS on for both tables');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.vehicle_state', 'select') and not has_table_privilege('anon', 'public.drive_trip', 'select'), 'no direct table access');
  foreach f in array array['drive_weather()', 'vehicle_status()', 'vehicle_trip_check(text)', 'vehicle_refuel(text, numeric)', 'vehicle_repair(text, boolean)', 'drive_report(text, jsonb)'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute') and not has_function_privilege('anon', 'public.' || f, 'execute'), f || ' is for signed-in players only');
  end loop;
  foreach f in array array['bl_vehicle_row(uuid, text)', 'bl_vehicle_damage(uuid, numeric)', 'bl_drive_trip_begin(public.profiles, text, text, timestamptz, timestamptz)', 'bl_drive_dry_choose(public.profiles, text)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', 'public.' || f, 'execute') and not has_function_privilege('anon', 'public.' || f, 'execute'), f || ' is internal');
  end loop;
  perform pg_temp.assert((select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('vehicle_status', 'vehicle_trip_check', 'vehicle_refuel', 'vehicle_repair', 'drive_report')
     and provolatile <> 'v') = 0, 'every RPC that calls bl_me() is volatile');
  perform pg_temp.assert(not exists (select 1 from pg_trigger where tgrelid = 'public.profiles'::regclass and tgname ilike '%drive%' and not tgisinternal), 'no drive trigger on profiles');
  perform pg_temp.assert(not exists (select 1 from pg_constraint where conrelid in ('public.vehicle_state'::regclass, 'public.drive_trip'::regclass) and contype = 'f'), 'no foreign keys');
end $$;
