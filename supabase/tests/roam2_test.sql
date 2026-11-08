-- Free roam, phase 2 (20261119000100_roam2.sql, docs/ROAM.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/roam2_test.sql
-- Groups: 1 settings · 2 whole city + inactive airport · 3 mode switching + ownership · 4 driving anti-teleport (roam_enter in the car)
-- · 5 fuel validation and clamps · 6 damage clamps · 7 rate limits · 8 arrival side effects (robbery with mode car, no fare)
-- · 9 out of fuel (push / mechanic) · 10 hail a keke · 11 structure and grants.
-- Time is pinned with bl.test_offset_seconds (bl_now()); rent and bills are switched off where money totals are asserted.
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

create temp table r2_u (name text primary key, id uuid);

do $$
declare v uuid; w uuid;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  v := pg_temp.new_user('r2_a@roam.bl');
  perform pg_temp.login(v);
  perform create_profile_v2('R2_a', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  insert into r2_u values ('a', v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  w := pg_temp.new_user('r2_b@roam.bl');
  perform pg_temp.login(w);
  perform create_profile_v2('R2_b', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  insert into r2_u values ('b', w);
  perform pg_temp.login(v);
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_offset_seconds',
    (mod((12 * 3600 - ((bl_game_clock(bl_now()) ->> 'hour')::int * 3600 + (bl_game_clock(bl_now()) ->> 'minute')::int * 60) + 86400)::numeric, 86400))::text, true);
  perform pg_temp.assert((bl_game_clock(bl_now()) ->> 'hour')::int = 12, 'test setup: the clock is pinned to noon');
  -- money totals: no rent or bills falling due, no street robbery unless a test asks for it
  update game_config set value = '0' where key = 'crime.npc_max_pct';
  -- a player-owned car with a known tank
  insert into inventory (user_id, item_id, qty) values (v, 'kia_rio_used', 1) on conflict (user_id, item_id) do update set qty = 1;
  insert into vehicle_state (user_id, item_id, fuel_l, cond) values (v, 'kia_rio_used', 40, 100) on conflict (user_id, item_id) do update set fuel_l = 40, cond = 100;
  update profiles set cash = 500000 where id = v;
end $$;

create or replace function pg_temp.at(p_uid uuid, p_place text) returns void
language plpgsql as $$
begin
  update profiles set location_id = p_place, travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
         busy_until = null, jailed_until = null, hospitalized_until = null where id = p_uid;
end $$;

-- ---------- 1. settings ----------
do $$
declare n int;
begin
  perform pg_temp.assert((select count(*) from game_config where key like 'roam.%') = 33, 'thirty-three roam settings (12 + 18 + 3)');
  select count(*) into n from game_config where key like 'roam.%'
     and (category <> 'roam' or coalesce(label, '') = '' or coalesce(description, '') = '' or (kind in ('number', 'naira', 'percent') and (min is null or max is null)));
  perform pg_temp.assert(n = 0, 'every roam setting is in category roam with a label, a description and a range (' || n || ' without)');
  perform pg_temp.assert((select count(*) from game_config where key like 'roam.%' and (label ilike '%lagos%' or description ilike '%lagos%')) = 0, 'no "Lagos" in the settings text');
  perform pg_temp.assert(bl_cfg_bool('roam.area.all') and bl_cfg_bool('roam.drive.enabled') and bl_cfg_bool('roam.keke.enabled'), 'whole city, driving and keke on by default');
  perform pg_temp.assert(bl_cfg('roam.drive.max_speed_mps') = 24 and bl_cfg('roam.chunk.m') = 120 and bl_cfg('roam.chunk.load_m') = 200 and bl_cfg('roam.drive.fuel_scale') = 8, 'defaults');
end $$;

-- ---------- 2. the whole city, the closed airport ----------
do $$
declare a uuid := (select id from r2_u where name = 'a'); r jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.assert(bl_roam_in_area('uniben') and bl_roam_in_area('ramat_park') and bl_roam_in_area('benin_airport') and bl_roam_in_area('national_museum'), 'every place is in the area now');
  perform pg_temp.assert(not bl_roam_in_area('no_such_place'), 'an unknown id never is');
  perform pg_temp.at(a, 'uniben');
  r := roam_start('uniben');
  perform pg_temp.assert((r ->> 'ok')::boolean and (r ->> 'all')::boolean and (r ->> 'drive')::boolean and (r ->> 'keke')::boolean and (r ->> 'load_m')::numeric = 200, 'start at a far place works and carries the hints');
  -- the airport is inactive: roam_enter refuses it with travel's own words, however long you walked
  perform pg_temp.adv(3000);
  r := roam_enter('benin_airport');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'inactive' and r ->> 'message' like '%under construction%', 'the airport is refused: under construction');
  perform pg_temp.assert((select location_id from profiles where id = a) = 'uniben', 'nobody moves');
  -- the walk across town needs the time at walking pace
  r := roam_start('uniben');
  r := roam_enter('oba_market');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'far', 'UNIBEN to Oba Market on foot at once: far');
  -- limiting the areas is still a setting
  perform pg_temp.setc('roam.area.all', 'false');
  perform pg_temp.assert(not bl_roam_in_area('uniben') and bl_roam_in_area('national_museum'), 'roam.area.all off: only the box');
  perform pg_temp.setc('roam.area.all', 'true');
end $$;

-- ---------- 3. mode switching and ownership ----------
do $$
declare a uuid := (select id from r2_u where name = 'a'); b uuid := (select id from r2_u where name = 'b'); r jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'uniben');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('car')$q$) = 'no_session' or pg_temp.hint_of($q$select roam_set_mode('car')$q$) = 'ok', 'set_mode needs a session');
  r := roam_start('uniben');
  perform pg_temp.assert((select mode from roam_sessions where user_id = a) = 'walk', 'a fresh walk is on foot');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('hoverboard')$q$) = 'bad_mode', 'unknown mode refused');
  r := roam_set_mode('car');
  perform pg_temp.assert((r ->> 'ok')::boolean and r ->> 'mode' = 'car' and r ->> 'item' = 'kia_rio_used' and (r ->> 'fuel_l')::numeric = 40, 'into the car: item and tank');
  perform pg_temp.assert((select mode from roam_sessions where user_id = a) = 'car' and (select vehicle from roam_sessions where user_id = a) = 'kia_rio_used', 'the session knows');
  -- someone else''s or an unowned vehicle
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('car', 'gwagon_g63')$q$) = 'not_owned', 'a vehicle you do not own: refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('car', 'bread')$q$) = 'not_owned', 'a non-vehicle item: refused');
  -- out again, leaving the car somewhere (clamped to the map)
  r := roam_set_mode('walk', null, 1500, -20, 1.5);
  perform pg_temp.assert((select mode from roam_sessions where user_id = a) = 'walk' and (select car_x from roam_sessions where user_id = a) = 1000 and (select car_y from roam_sessions where user_id = a) = 0, 'getting out records where the car was left, clamped to the map');
  r := roam_car_info();
  perform pg_temp.assert((r ->> 'has_car')::boolean and r ->> 'item' = 'kia_rio_used' and (r ->> 'car_x')::numeric = 1000 and r ->> 'mode' = 'walk', 'roam_car_info');
  -- condition 0: will not start; empty tank: will not start
  update vehicle_state set cond = 0 where user_id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('car')$q$) = 'wont_start', 'condition 0: will not start');
  update vehicle_state set cond = 80, fuel_l = 0 where user_id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('car')$q$) = 'no_fuel', 'empty tank: will not start');
  update vehicle_state set fuel_l = 40 where user_id = a;
  -- no vehicle at all
  perform pg_temp.login(b);
  perform pg_temp.at(b, 'uniben');
  r := roam_start('uniben');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('car')$q$) = 'not_owned', 'no vehicle: not_owned');
  perform pg_temp.assert(not (roam_car_info() ->> 'has_car')::boolean, 'roam_car_info: no car');
  -- the switch
  perform pg_temp.login(a);
  r := roam_start('uniben');
  perform pg_temp.setc('roam.drive.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('car')$q$) = 'off', 'driving switched off: refused');
  perform pg_temp.setc('roam.drive.enabled', 'true');
  r := roam_leave();
  perform pg_temp.assert((select mode from roam_sessions where user_id = a) = 'walk', 'leave puts the player back on foot');
end $$;

-- ---------- 4. driving anti-teleport ----------
do $$
declare a uuid := (select id from r2_u where name = 'a'); r jsonb; d numeric; need numeric; ax numeric; ay numeric; bx numeric; b_y numeric;
begin
  perform pg_temp.login(a);
  update vehicle_state set fuel_l = 40, cond = 100 where user_id = a;
  perform pg_temp.at(a, 'national_museum');
  perform pg_temp.adv(5000);
  r := roam_start('national_museum');
  r := roam_set_mode('car');
  select x, y into ax, ay from locations where id = 'national_museum';
  select x, y into bx, b_y from locations where id = 'oba_market';
  d := sqrt((ax - bx) ^ 2 + (ay - b_y) ^ 2);
  need := greatest(bl_cfg('roam.min_enter_s'), greatest(0, d - bl_cfg('roam.door_slack_m')) / bl_cfg('roam.drive.max_speed_mps'));
  -- by car it is faster than walking, but never instant
  r := roam_enter('oba_market');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'far', 'pulling up at once: far (time or distance)');
  perform pg_temp.adv(need + 1);
  r := roam_enter('oba_market');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'far' and r ->> 'message' like '%driven that far%', 'time is up but nothing was driven: keep driving');
  -- drive it: a checkpoint reports the distance (capped by speed x elapsed + slack)
  r := roam_drive_report(jsonb_build_object('dist_m', d));
  perform pg_temp.assert((r ->> 'ok')::boolean and (r ->> 'dist_m')::numeric <= bl_cfg('roam.drive.max_speed_mps') * (need + 1) + bl_cfg('roam.drive.slack_m') + 0.1, 'the claimed distance is capped by max speed x elapsed (+ slack): ' || (r ->> 'dist_m'));
  -- give it real time: report in steps at believable speed
  perform pg_temp.adv(1000);
  r := roam_drive_report(jsonb_build_object('dist_m', d));
  perform pg_temp.assert((r ->> 'ok')::boolean and (select drive_m from roam_sessions where user_id = a) >= d * 0.6, 'a long drive later the distance is credited');
  r := roam_enter('oba_market');
  perform pg_temp.assert((r ->> 'ok')::boolean and r ->> 'location' = 'oba_market', 'now the car pulls up at Oba Market');
  perform pg_temp.assert((select location_id from profiles where id = a) = 'oba_market', 'the player is at Oba Market');
  perform pg_temp.assert((select mode from roam_sessions where user_id = a) = 'walk' and (select car_place from roam_sessions where user_id = a) = 'oba_market' and (select drive_m from roam_sessions where user_id = a) = 0,
    'the car is left at the place, the player on foot, the distance counter restarts');
  -- the drive pace is a setting
  r := roam_start('oba_market');
  r := roam_set_mode('car');
  perform pg_temp.setc('roam.drive.max_speed_mps', '1');
  perform pg_temp.setc('roam.drive.min_report_pct', '0');
  perform pg_temp.adv(30);
  r := roam_enter('national_museum');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'far', 'a slow drive pace needs more time');
  perform pg_temp.setc('roam.drive.max_speed_mps', '24');
  perform pg_temp.setc('roam.drive.min_report_pct', '60');
  -- a report outside a car session means nothing
  r := roam_set_mode('walk');
  r := roam_drive_report(jsonb_build_object('dist_m', 500));
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'reason' = 'not_driving', 'a checkpoint on foot is ignored');
end $$;

-- ---------- 5. fuel validation ----------
do $$
declare a uuid := (select id from r2_u where name = 'a'); r jsonb; f0 numeric; lpk numeric;
begin
  perform pg_temp.login(a);
  update vehicle_state set fuel_l = 40, cond = 100 where user_id = a;
  perform pg_temp.at(a, 'national_museum');
  r := roam_start('national_museum');
  r := roam_set_mode('car');
  perform pg_temp.adv(10);
  lpk := bl_cfg('drive.fuel.lpk_car');
  r := roam_drive_report(jsonb_build_object('dist_m', 100));
  perform pg_temp.assert((r ->> 'ok')::boolean and (r ->> 'dist_m')::numeric = 100, 'a believable 100 m after 10 s is credited in full');
  perform pg_temp.assert(abs((r ->> 'burned_l')::numeric - 100 / 1000.0 * bl_cfg('roam.drive.fuel_scale') * lpk) < 0.002, 'the burn is distance x fuel_scale x litres per km (' || (r ->> 'burned_l') || ')');
  perform pg_temp.assert(abs((select fuel_l from vehicle_state where user_id = a) - (40 - (r ->> 'burned_l')::numeric)) < 0.001, 'the tank fell by exactly that');
  -- a lie: 50 km claimed after 5 s -> capped to 24 x 5 + 40
  perform pg_temp.adv(5);
  f0 := (select fuel_l from vehicle_state where user_id = a);
  r := roam_drive_report(jsonb_build_object('dist_m', 50000));
  perform pg_temp.assert((r ->> 'dist_m')::numeric <= 24 * 5 + 20 + 0.1 and (r ->> 'dist_m')::numeric >= 24 * 5 + 20 - 0.1, 'a huge claim is cut to max speed x elapsed + slack scaled by elapsed time (got ' || (r ->> 'dist_m') || ')');
  perform pg_temp.assert(f0 - (select fuel_l from vehicle_state where user_id = a) < 0.5, 'and the burn follows the capped distance');
  -- junk: negative, text, missing
  perform pg_temp.adv(5);
  r := roam_drive_report(jsonb_build_object('dist_m', -300));
  perform pg_temp.assert((r ->> 'ok')::boolean and (r ->> 'dist_m')::numeric = 0 and (r ->> 'burned_l')::numeric = 0, 'a negative distance is 0');
  perform pg_temp.adv(5);
  r := roam_drive_report(jsonb_build_object('dist_m', 'lots'));
  perform pg_temp.assert((r ->> 'ok')::boolean and (r ->> 'dist_m')::numeric = 0, 'a text distance is 0');
  perform pg_temp.adv(5);
  r := roam_drive_report('{}'::jsonb);
  perform pg_temp.assert((r ->> 'ok')::boolean and (r ->> 'dist_m')::numeric = 0, 'an empty report is 0');
  -- wear burns more
  perform pg_temp.adv(10);
  update vehicle_state set cond = 10, fuel_l = 40 where user_id = a;
  r := roam_drive_report(jsonb_build_object('dist_m', 100));
  perform pg_temp.assert((r ->> 'burned_l')::numeric > 100 / 1000.0 * bl_cfg('roam.drive.fuel_scale') * lpk * 1.05, 'a worn car burns more');
  update vehicle_state set cond = 100 where user_id = a;
  -- the tank cannot go below 0, and says so
  perform pg_temp.adv(10);
  update vehicle_state set fuel_l = 0.05 where user_id = a;
  r := roam_drive_report(jsonb_build_object('dist_m', 200));
  perform pg_temp.assert((r ->> 'fuel_l')::numeric = 0 and (r ->> 'empty')::boolean and (select fuel_l from vehicle_state where user_id = a) = 0, 'the tank bottoms out at 0 and the report says empty');
  -- a bicycle burns nothing
  insert into inventory (user_id, item_id, qty) values (a, 'bicycle', 1) on conflict (user_id, item_id) do update set qty = 1;
  r := roam_set_mode('walk');
  r := roam_set_mode('car', 'bicycle');
  perform pg_temp.adv(10);
  r := roam_drive_report(jsonb_build_object('dist_m', 100));
  perform pg_temp.assert((r ->> 'burned_l')::numeric = 0 and not (r ->> 'empty')::boolean, 'a bicycle needs no fuel');
  delete from inventory where user_id = a and item_id = 'bicycle';
end $$;

-- ---------- 6. damage clamps ----------
do $$
declare a uuid := (select id from r2_u where name = 'a'); r jsonb; c0 numeric;
begin
  perform pg_temp.login(a);
  perform pg_temp.setc('roam.rate.max_calls', '100');
  update vehicle_state set fuel_l = 40, cond = 100 where user_id = a and item_id = 'kia_rio_used';
  perform pg_temp.at(a, 'national_museum');
  perform pg_temp.adv(100);
  r := roam_start('national_museum');
  r := roam_set_mode('car');
  perform pg_temp.adv(30);
  r := roam_drive_report(jsonb_build_object('hard', 1, 'light', 2));
  perform pg_temp.assert(abs((r ->> 'damage')::numeric - (bl_cfg('roam.drive.damage_hard') + 2 * bl_cfg('roam.drive.damage_light'))) < 0.11 and (r ->> 'cond')::numeric = round(100 - (r ->> 'damage')::numeric), 'a hard hit and two light ones: priced by the settings');
  -- a flood of hits is cut: at most max_hits_report, and at most max_damage_report points
  perform pg_temp.adv(60);
  update vehicle_state set cond = 100 where user_id = a;
  r := roam_drive_report(jsonb_build_object('hard', 500, 'light', 500));
  perform pg_temp.assert((r ->> 'damage')::numeric <= bl_cfg('roam.drive.max_damage_report') + 0.01, 'one report takes at most max_damage_report (' || (r ->> 'damage') || ')');
  perform pg_temp.assert((r ->> 'damage')::numeric <= bl_cfg('roam.drive.max_hits_report') * bl_cfg('roam.drive.damage_hard') + 0.01, 'and at most max_hits_report hard hits');
  -- the hits are cut by the time too: a report 4 s after the last one can carry at most 4/1.2 + 1 = 4 hits
  perform pg_temp.adv(4);
  update vehicle_state set cond = 100 where user_id = a;
  perform pg_temp.setc('roam.drive.max_hits_report', '100');
  perform pg_temp.setc('roam.drive.max_damage_report', '100');
  perform pg_temp.setc('roam.drive.max_damage_min', '1000');
  r := roam_drive_report(jsonb_build_object('hard', 100));
  perform pg_temp.assert((r ->> 'damage')::numeric <= 4 * bl_cfg('roam.drive.damage_hard') + 0.01, 'hits are capped by elapsed time (got ' || (r ->> 'damage') || ')');
  -- the per-minute cap
  perform pg_temp.setc('roam.drive.max_damage_min', '30');
  perform pg_temp.adv(60);
  update vehicle_state set cond = 100 where user_id = a;
  r := roam_drive_report(jsonb_build_object('hard', 100));
  c0 := (r ->> 'damage')::numeric;
  perform pg_temp.adv(30);
  r := roam_drive_report(jsonb_build_object('hard', 100));
  perform pg_temp.assert(c0 + (r ->> 'damage')::numeric <= 30.01, 'two big reports inside one minute stay under max_damage_min (' || c0 || ' + ' || (r ->> 'damage') || ')');
  perform pg_temp.adv(40);
  r := roam_drive_report(jsonb_build_object('hard', 100));
  perform pg_temp.assert((r ->> 'damage')::numeric > 0, 'a new minute: damage lands again');
  -- condition floors at 0, not below
  perform pg_temp.setc('roam.drive.max_damage_min', '1000');
  update vehicle_state set cond = 3 where user_id = a;
  perform pg_temp.adv(60);
  r := roam_drive_report(jsonb_build_object('hard', 6));
  perform pg_temp.assert((r ->> 'cond')::numeric = 0 and (r ->> 'wont_start')::boolean, 'condition bottoms at 0 and then the car will not start');
  perform pg_temp.assert(not exists (select 1 from vehicle_state where cond < 0 or fuel_l < 0), 'never negative');
  -- damage switched off
  update vehicle_state set cond = 100 where user_id = a;
  perform pg_temp.setc('drive.damage.enabled', 'false');
  perform pg_temp.adv(60);
  r := roam_drive_report(jsonb_build_object('hard', 6));
  perform pg_temp.assert((r ->> 'damage')::numeric = 0, 'drive.damage.enabled off: no damage');
  perform pg_temp.setc('drive.damage.enabled', 'true');
  perform pg_temp.setc('roam.drive.max_hits_report', '6');
  perform pg_temp.setc('roam.drive.max_damage_report', '15');
  perform pg_temp.setc('roam.drive.max_damage_min', '30');
end $$;

-- ---------- 7. rate limits ----------
do $$
declare a uuid := (select id from r2_u where name = 'a'); r jsonb; i int;
begin
  perform pg_temp.login(a);
  update vehicle_state set fuel_l = 40, cond = 100 where user_id = a and item_id = 'kia_rio_used';
  perform pg_temp.at(a, 'national_museum');
  perform pg_temp.adv(5000);
  r := roam_start('national_museum');
  r := roam_set_mode('car');
  perform pg_temp.adv(10);
  r := roam_drive_report(jsonb_build_object('dist_m', 50));
  perform pg_temp.assert((r ->> 'ok')::boolean, 'first checkpoint');
  r := roam_drive_report(jsonb_build_object('dist_m', 50));
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'reason' = 'too_soon', 'a second one at once: too_soon, nothing applied');
  perform pg_temp.adv(3.1);
  r := roam_drive_report(jsonb_build_object('dist_m', 50));
  perform pg_temp.assert((r ->> 'ok')::boolean, 'after the gap it counts');
  -- per minute
  perform pg_temp.setc('roam.drive.max_reports_min', '3');
  perform pg_temp.adv(61);
  for i in 1..3 loop
    perform pg_temp.adv(3.1);
    r := roam_drive_report(jsonb_build_object('dist_m', 10));
    perform pg_temp.assert((r ->> 'ok')::boolean, 'report ' || i || ' of 3 in the minute');
  end loop;
  perform pg_temp.adv(3.1);
  r := roam_drive_report(jsonb_build_object('dist_m', 10));
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'reason' = 'rate', 'the fourth inside the minute: rate');
  perform pg_temp.adv(61);
  r := roam_drive_report(jsonb_build_object('dist_m', 10));
  perform pg_temp.assert((r ->> 'ok')::boolean, 'a new minute');
  perform pg_temp.setc('roam.drive.max_reports_min', '24');
  -- set_mode counts against the roam_start / roam_enter window
  perform pg_temp.setc('roam.rate.max_calls', '5');
  perform pg_temp.adv(100);
  r := roam_start('national_museum');                      -- 1
  r := roam_set_mode('car');                               -- 2
  r := roam_set_mode('walk');                              -- getting out is free (never counted, never refused)
  r := roam_set_mode('car');                               -- 3
  r := roam_set_mode('walk');
  r := roam_set_mode('car');                               -- 4
  r := roam_set_mode('walk');
  r := roam_set_mode('car');                               -- 5
  r := roam_set_mode('walk');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('car')$q$) = 'rate', 'the sixth counted call in the window: rate');
  perform pg_temp.setc('roam.rate.max_calls', '20');
  perform pg_temp.adv(100);
end $$;

-- ---------- 8. arrival side effects: street robbery with mode car, no fare ----------
do $$
declare a uuid := (select id from r2_u where name = 'a'); r jsonb; cash0 bigint; n0 int;
begin
  perform pg_temp.login(a);
  update vehicle_state set fuel_l = 40, cond = 100 where user_id = a and item_id = 'kia_rio_used';
  perform pg_temp.at(a, 'national_museum');
  perform pg_temp.adv(5000);
  r := roam_start('national_museum');
  r := roam_set_mode('car');
  perform pg_temp.adv(60);
  r := roam_drive_report(jsonb_build_object('dist_m', 2000));
  perform pg_temp.adv(3.5);
  r := roam_drive_report(jsonb_build_object('dist_m', 2000));
  cash0 := (select cash from profiles where id = a);
  r := roam_enter('oba_palace');
  perform pg_temp.assert((r ->> 'ok')::boolean, 'pulled up at the palace');
  perform pg_temp.assert((select cash from profiles where id = a) = cash0 and not exists (select 1 from ledger where user_id = a and reason = 'travel'), 'no fare for pulling up by your own car');
  -- the robbery roll runs with mode car: walking is made harmless and the car a sure thing, so a robbery proves the mode
  perform pg_temp.setc('crime.npc_max_pct', '100');
  perform pg_temp.setc('crime.npc_base_pct', '100');
  perform pg_temp.setc('crime.mode_mult_walk', '0');
  perform pg_temp.setc('crime.mode_mult_car', '5');
  update profiles set cash = 100000, protected_until = null where id = a;
  n0 := (select count(*) from ledger where user_id = a and reason = 'street_robbery');
  r := roam_start('oba_palace');
  r := roam_set_mode('car');
  perform pg_temp.adv(40);
  r := roam_drive_report(jsonb_build_object('dist_m', 300));
  perform pg_temp.adv(3.5);
  r := roam_drive_report(jsonb_build_object('dist_m', 300));
  r := roam_enter('national_museum');
  perform pg_temp.assert((r ->> 'ok')::boolean and r ? 'robbed', 'pulled up at the museum and robbed: the roll ran with mode car');
  perform pg_temp.assert((select count(*) from ledger where user_id = a and reason = 'street_robbery') = n0 + 1, 'one robbery in the ledger');
  -- on foot the same setup is harmless (mode walk has multiplier 0)
  update profiles set cash = 100000 where id = a;
  r := roam_start('national_museum');
  perform pg_temp.adv(60);
  r := roam_enter('oba_palace');
  perform pg_temp.assert((r ->> 'ok')::boolean and not (r ? 'robbed'), 'on foot with walking made harmless: no robbery');
  perform pg_temp.setc('crime.npc_max_pct', '0');
  perform pg_temp.setc('crime.npc_base_pct', '0');
  perform pg_temp.setc('crime.mode_mult_walk', '1.4');
  perform pg_temp.setc('crime.mode_mult_car', '0.6');
end $$;

-- ---------- 9. out of fuel ----------
do $$
declare a uuid := (select id from r2_u where name = 'a'); r jsonb; cash0 bigint;
begin
  perform pg_temp.login(a);
  update profiles set cash = 500000 where id = a;
  perform pg_temp.at(a, 'national_museum');
  perform pg_temp.adv(5000);
  r := roam_start('national_museum');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_dry_choose('push')$q$) = 'not_dry', 'a tank with fuel: not dry');
  update vehicle_state set fuel_l = 0, cond = 90 where user_id = a and item_id = 'kia_rio_used';
  perform pg_temp.setc('drive.dry.push_fail_pct', '0');
  r := roam_dry_choose('push');
  perform pg_temp.assert((r ->> 'ok')::boolean and (r ->> 'wait_s')::int = bl_cfg('drive.dry.push_s')::int and (r ->> 'cash_delta')::bigint = 0, 'push: free, takes the push time');
  update vehicle_state set fuel_l = 0 where user_id = a and item_id = 'kia_rio_used';
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_dry_choose('swim')$q$) = 'bad_choice', 'only the choices on the card');
  cash0 := (select cash from profiles where id = a);
  r := roam_dry_choose('mechanic');
  perform pg_temp.assert((r ->> 'ok')::boolean and (select cash from profiles where id = a) = cash0 - bl_cfg('drive.dry.mechanic_cost')::bigint, 'mechanic: paid');
  perform pg_temp.assert((select fuel_l from vehicle_state where user_id = a and item_id = 'kia_rio_used') = bl_cfg('drive.dry.mechanic_litres'), 'and he puts in the litres');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('car')$q$) = 'busy', 'but the car is busy while he works');
  perform pg_temp.adv(600);
  r := roam_set_mode('car');
  perform pg_temp.assert((r ->> 'ok')::boolean, 'after the wait it starts');
  r := roam_set_mode('walk');
  update vehicle_state set fuel_l = 0 where user_id = a;
  update profiles set cash = 10 where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_dry_choose('mechanic')$q$) = 'not_enough_cash', 'no cash for the mechanic: refused, push is still free');
  update profiles set cash = 500000 where id = a;
  update vehicle_state set fuel_l = 40 where user_id = a;
end $$;

-- ---------- 10. hail a keke ----------
do $$
declare a uuid := (select id from r2_u where name = 'a'); r jsonb; cash0 bigint; k1 text; k2 text;
begin
  select id into k1 from locations where keke_ok and active order by id limit 1;
  select id into k2 from locations where keke_ok and active and id <> k1 order by id desc limit 1;
  perform pg_temp.login(a);
  update profiles set cash = 500000 where id = a;
  perform pg_temp.at(a, k1);
  perform pg_temp.adv(5000);
  r := roam_start(k1);
  r := roam_set_mode('car');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_hail_keke('oba_market')$q$) = 'in_car', 'not from inside your car');
  r := roam_set_mode('walk');
  perform pg_temp.setc('roam.keke.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_hail_keke('oba_market')$q$) = 'off', 'switched off: refused');
  perform pg_temp.setc('roam.keke.enabled', 'true');
  cash0 := (select cash from profiles where id = a);
  r := roam_hail_keke(k2);
  perform pg_temp.assert((select travel_to from profiles where id = a) = k2 and (select travel_mode from profiles where id = a) = 'keke', 'a normal keke trip started');
  perform pg_temp.assert((select cash from profiles where id = a) < cash0, 'at the normal fare');
  perform pg_temp.assert((select ended from roam_sessions where user_id = a), 'the street walk is over until the trip ends');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_hail_keke('oba_market')$q$) <> 'ok', 'cannot hail while travelling');
  -- the airport is not a destination (travel refuses it)
  update profiles set travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null, location_id = k1 where id = a;
  r := roam_start(k1);
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_hail_keke('benin_airport')$q$) <> 'ok', 'the closed airport cannot be hailed to');
end $$;

-- ---------- 12. review fixes ----------
do $$
declare a uuid := (select id from r2_u where name = 'a'); r jsonb; d0 numeric; d1 numeric; need numeric; dd numeric; n0 int; v_l numeric;
begin
  perform pg_temp.login(a);
  perform pg_temp.setc('roam.rate.max_calls', '200');
  perform pg_temp.setc('roam.drive.max_reports_min', '200');
  update profiles set cash = 500000 where id = a;
  insert into inventory (user_id, item_id, qty) values (a, 'bicycle', 1), (a, 'bajaj_boxer', 1) on conflict (user_id, item_id) do update set qty = 1;
  update vehicle_state set fuel_l = 40, cond = 100 where user_id = a and item_id = 'kia_rio_used';
  perform pg_temp.at(a, 'national_museum');
  perform pg_temp.adv(5000);
  r := roam_start('national_museum');
  r := roam_set_mode('car');
  -- 12.1 an empty tank credits (almost) no distance, however many reports
  update vehicle_state set fuel_l = 0.05 where user_id = a and item_id = 'kia_rio_used';
  d0 := (select drive_m from roam_sessions where user_id = a);
  for n0 in 1..3 loop
    perform pg_temp.adv(10);
    r := roam_drive_report(jsonb_build_object('dist_m', 760));
  end loop;
  d1 := (select drive_m from roam_sessions where user_id = a);
  perform pg_temp.assert(d1 - d0 <= 0.05 / (bl_cfg('drive.fuel.lpk_car') * bl_cfg('roam.drive.fuel_scale') / 1000.0) + 6, '0.05 L of petrol is worth about 57 m, not 3 x 760 (credited ' || round(d1 - d0, 1) || ')');
  perform pg_temp.adv(10);
  d0 := (select drive_m from roam_sessions where user_id = a);
  r := roam_drive_report(jsonb_build_object('dist_m', 500));
  perform pg_temp.assert((select drive_m from roam_sessions where user_id = a) - d0 <= 3.01, 'with the tank at 0 a checkpoint credits only a few metres of roll');
  -- condition 0
  update vehicle_state set fuel_l = 40, cond = 0 where user_id = a and item_id = 'kia_rio_used';
  perform pg_temp.adv(10);
  d0 := (select drive_m from roam_sessions where user_id = a);
  r := roam_drive_report(jsonb_build_object('dist_m', 500));
  perform pg_temp.assert((select drive_m from roam_sessions where user_id = a) - d0 <= 3.01, 'condition 0 credits only a few metres');
  update vehicle_state set cond = 100 where user_id = a and item_id = 'kia_rio_used';
  -- 12.6 slack scales with the elapsed time
  perform pg_temp.adv(3.1);
  r := roam_drive_report(jsonb_build_object('dist_m', 5000));
  perform pg_temp.assert((r ->> 'dist_m')::numeric <= 24 * 3.1 + 40 * 0.31 + 0.2, 'after 3 s the slack is a third of the 10 s slack, not the flat 40 m (got ' || (r ->> 'dist_m') || ')');
  -- 12.2 per-class pace
  perform pg_temp.assert(bl_roam_speed_cap('bicycle') <= 8 and bl_roam_speed_cap('bajaj_boxer') <= 23 and bl_roam_speed_cap('kia_rio_used') = 24, 'class speed caps: bicycle, motorcycle, car');
  r := roam_set_mode('walk');
  r := roam_set_mode('car', 'bicycle');
  perform pg_temp.adv(10);
  r := roam_drive_report(jsonb_build_object('dist_m', 500));
  perform pg_temp.assert((r ->> 'dist_m')::numeric <= bl_cfg('roam.drive.max_speed_bicycle') * 10 + 40 + 0.2, 'a bicycle cannot claim car pace (got ' || (r ->> 'dist_m') || ')');
  r := roam_set_mode('walk');
  r := roam_set_mode('car', 'bajaj_boxer');
  perform pg_temp.adv(10);
  r := roam_drive_report(jsonb_build_object('dist_m', 500));
  perform pg_temp.assert((r ->> 'dist_m')::numeric <= bl_cfg('roam.drive.max_speed_motorcycle') * 10 + 40 + 0.2, 'a motorcycle is capped at its own pace (got ' || (r ->> 'dist_m') || ')');
  -- pulling up by bicycle uses the bicycle pace
  r := roam_set_mode('walk');
  r := roam_start('national_museum');
  r := roam_set_mode('car', 'bicycle');
  update roam_sessions set drive_m = 100000 where user_id = a;
  need := greatest(0, (select sqrt((l1.x - l2.x) ^ 2 + (l1.y - l2.y) ^ 2) from locations l1, locations l2 where l1.id = 'national_museum' and l2.id = 'police_hq') - bl_cfg('roam.door_slack_m'));
  perform pg_temp.adv(need / 24 + 1);
  r := roam_enter('police_hq');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'far', 'a bicycle has not had time to ride that far at car pace + 1 s');
  perform pg_temp.adv(need / bl_cfg('roam.drive.max_speed_bicycle') + 1);
  r := roam_enter('police_hq');
  perform pg_temp.assert((r ->> 'ok')::boolean, 'after distance / bicycle pace it pulls up');
  -- 12.3 remote places are quick-travel only
  perform pg_temp.assert((select remote_km from locations where id = 'iguobazuwa_farm') > 0, 'test data: the farm is remote');
  perform pg_temp.assert(not bl_roam_in_area('iguobazuwa_farm') and bl_roam_in_area('uniben'), 'remote places are not roam places');
  r := roam_start('police_hq');
  perform pg_temp.adv(3000);
  r := roam_enter('iguobazuwa_farm');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'outside', 'walking into a remote place is refused (outside)');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_hail_keke('iguobazuwa_farm')$q$) = 'outside', 'and so is hailing a keke there');
  -- 12.4 an overdue insurance bill blocks the car
  insert into player_bills (user_id, kind, ref, title, amount, period, status, due_at)
  values (a, 'car', 'kia_rio_used', 'Insurance', 1000, current_date, 'open', bl_now() - interval '400 days');
  perform pg_temp.assert(bl_sink_blocked(a, 'car', 'kia_rio_used'), 'test data: the car is blocked');
  r := roam_set_mode('walk');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('car', 'kia_rio_used')$q$) = 'blocked', 'a blocked car cannot be driven in the street');
  delete from player_bills where user_id = a;
  -- 12.5 push gets you going; mechanic respects the fuel switch; walk is always possible
  update vehicle_state set fuel_l = 0, cond = 90 where user_id = a and item_id = 'kia_rio_used';
  r := roam_set_mode('walk');
  r := roam_dry_choose('push');
  perform pg_temp.assert((r ->> 'fuel_l')::numeric > 0 and (select fuel_l from vehicle_state where user_id = a and item_id = 'kia_rio_used') > 0, 'push leaves a little petrol (a stranger helps) so the car can move again');
  perform pg_temp.assert((r ->> 'wait_s')::int >= bl_cfg('drive.dry.push_s')::int, 'and takes the push time');
  perform pg_temp.setc('drive.dry.push_fail_pct', '100');
  update vehicle_state set fuel_l = 0 where user_id = a and item_id = 'kia_rio_used';
  r := roam_dry_choose('push');
  perform pg_temp.assert((r ->> 'wait_s')::int = bl_cfg('drive.dry.push_s')::int + bl_cfg('drive.dry.push_fail_s')::int, 'a failed push takes the extra time (server side)');
  perform pg_temp.setc('drive.dry.push_fail_pct', '0');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('car')$q$) = 'busy', 'the car is not ready until the push is done');
  perform pg_temp.adv(600);
  r := roam_set_mode('car');
  perform pg_temp.assert((r ->> 'ok')::boolean, 'after the push the car starts');
  r := roam_set_mode('walk');
  update vehicle_state set fuel_l = 0 where user_id = a and item_id = 'kia_rio_used';
  perform pg_temp.setc('drive.fuel.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_dry_choose('mechanic')$q$) = 'not_dry', 'fuel switched off: nobody is dry, the mechanic is not called');
  perform pg_temp.setc('drive.fuel.enabled', 'true');
  r := roam_set_mode('car', 'bicycle');
  perform pg_temp.setc('roam.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_set_mode('walk')$q$) = 'ok', 'getting out always works, even with free roam switched off');
  perform pg_temp.assert((select mode from roam_sessions where user_id = a) = 'walk', 'and the session is on foot');
  perform pg_temp.setc('roam.enabled', 'true');
  perform pg_temp.setc('roam.rate.max_calls', '20');
  perform pg_temp.setc('roam.drive.max_reports_min', '24');
end $$;

-- ---------- 11. structure and grants ----------
do $$
begin
  perform pg_temp.assert(not exists (select 1 from information_schema.columns where table_name = 'profiles' and column_name like 'roam%'), 'still no roam column on profiles');
  perform pg_temp.assert(not exists (select 1 from pg_trigger where tgrelid = 'public.roam_sessions'::regclass and not tgisinternal), 'no triggers on roam_sessions');
  perform pg_temp.assert(not exists (select 1 from pg_constraint where conrelid = 'public.roam_sessions'::regclass and contype = 'f'), 'no foreign keys on roam_sessions');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.roam_set_mode(text, text, numeric, numeric, numeric)', 'execute')
    and has_function_privilege('authenticated', 'public.roam_drive_report(jsonb)', 'execute')
    and has_function_privilege('authenticated', 'public.roam_dry_choose(text)', 'execute')
    and has_function_privilege('authenticated', 'public.roam_hail_keke(text)', 'execute')
    and has_function_privilege('authenticated', 'public.roam_car_info()', 'execute'), 'players can call the new RPCs');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.roam_set_mode(text, text, numeric, numeric, numeric)', 'execute')
    and not has_function_privilege('anon', 'public.roam_drive_report(jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.roam_hail_keke(text)', 'execute'), 'anon cannot');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_roam_session(public.profiles)', 'execute')
    and not has_function_privilege('authenticated', 'public.bl_roam_count_call(uuid)', 'execute'), 'helpers are not callable');
  perform pg_temp.assert((select count(*) from pg_proc where oid in ('public.roam_set_mode(text,text,numeric,numeric,numeric)'::regprocedure, 'public.roam_drive_report(jsonb)'::regprocedure,
    'public.roam_dry_choose(text)'::regprocedure, 'public.roam_hail_keke(text)'::regprocedure, 'public.roam_car_info()'::regprocedure) and provolatile = 'v') = 5, 'the RPCs that call bl_me() are volatile');
  raise notice 'ROAM2 TEST OK';
end $$;
