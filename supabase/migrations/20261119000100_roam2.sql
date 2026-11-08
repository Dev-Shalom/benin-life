-- Free roam, phase 2 (docs/ROAM.md): the whole city, your own car, hail a keke.
--   * Area: any active place (or your own home) is a roam place. roam.area.all off brings back the phase 1 box.
--   * Mode: roam_set_mode('walk'|'car', vehicle) records whether the player is on foot or in their own vehicle (ownership, condition
--     and fuel are checked on the server). roam_enter's anti-teleport uses the mode: walking pace on foot, driving pace in the car.
--     Arriving by car applies the same arrival side effects as travel (VIP announce, street robbery roll with mode car) and no fare.
--   * Driving: roam_drive_report(dist, hits...) is the ONLY way fuel burns and damage lands. The distance since the last
--     checkpoint is capped by max drive speed x elapsed time, the fuel burn follows that distance, hit counts are capped per report,
--     per minute and by elapsed time, reports are rate limited. A car must have been driven about the distance before it can pull
--     up at a place (roam.drive.min_report_pct).
--   * Out of fuel: roam_dry_choose('push'|'mechanic') like the drive scene's stranded card (settings drive.dry.*).
--   * Keke: roam_hail_keke(dest) is a guarded wrapper round travel_start(dest, 'keke'): normal fare, normal trip, no new money logic.
--   * roam_car_info() tells the client what the player drives (tank, condition) and where the car was left.
-- No profiles DDL, no triggers, no foreign keys, no loops over players. Live functions are patched by guarded single replace through
-- the unique helper pg_temp.roam2_patch. Idempotent.

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (category roam = "Free roam")
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('roam.area.all', 'true', 'roam', 'Whole city open', 'On = every active place (and your own home) can be walked to and entered in free roam. Off = only the box below (the phase 1 area round King''s Square). Inactive places such as the airport stay refused either way.', 'bool', null, null),
('roam.drive.enabled', 'true', 'roam', 'Drive your own vehicle in free roam', 'Off = the Get my car button disappears and roam_set_mode refuses the car.', 'bool', null, null),
('roam.drive.max_speed_mps', '24', 'roam', 'Driving: fastest speed (metres a second)', 'Used for the anti-teleport check when a player pulls up at a place in their own vehicle, and to cap the distance one fuel checkpoint may claim. 24 m/s is about 86 km/h; the car in the street tops out below this.', 'number', 5, 60),
('roam.drive.fuel_scale', '8', 'roam', 'Fuel: street kilometres burn this many real kilometres', 'Free roam streets are compact. The litres per kilometre of the vehicle (Drive settings, drive.fuel.lpk_*) are multiplied by this, so a tank lasts a believable number of crossings of the city.', 'number', 0.1, 100),
('roam.drive.report_gap_s', '3', 'roam', 'Driving: shortest gap between fuel/damage checkpoints (seconds)', 'A checkpoint sooner than this after the last one is ignored (the client sends it again later).', 'number', 0.5, 120),
('roam.drive.max_reports_min', '24', 'roam', 'Driving: checkpoints a minute', 'Rate limit on roam_drive_report per player.', 'number', 1, 600),
('roam.drive.slack_m', '40', 'roam', 'Driving: free metres a checkpoint may claim', 'On top of max speed x elapsed time, to cover jitter between the phone and the server clock.', 'number', 0, 500),
('roam.drive.max_hits_report', '6', 'roam', 'Damage: most hits one checkpoint may carry', 'Light and hard hits together. More is cut off.', 'number', 1, 100),
('roam.drive.min_s_per_hit', '1.2', 'roam', 'Damage: shortest time between two hits (seconds)', 'Hits are also capped by the time since the last checkpoint divided by this.', 'number', 0.1, 60),
('roam.drive.damage_light', '1.2', 'roam', 'Damage: a light bump (condition points)', 'A scrape or a slow knock against a wall, pole or parked car.', 'number', 0, 50),
('roam.drive.damage_hard', '4.5', 'roam', 'Damage: a hard crash (condition points)', 'A fast hit. Wet roads add the drive.rain.damage_mult on top.', 'number', 0, 100),
('roam.drive.max_damage_report', '15', 'roam', 'Damage: most one checkpoint may take (condition points)', 'Clamp per report.', 'number', 0, 100),
('roam.drive.max_damage_min', '30', 'roam', 'Damage: most a player may take in a minute (condition points)', 'Clamp per rolling minute.', 'number', 0, 100),
('roam.drive.min_report_pct', '60', 'roam', 'Pulling up at a place: share of the distance that must have been driven', 'Free roam positions are cosmetic, so to enter a place by car the server wants about this much of the straight-line distance to have been reported through fuel checkpoints. 0 = no check.', 'percent', 0, 100),
('roam.car.ready_s', '4', 'roam', 'Get my car: seconds before it is at the kerb', 'The client shows a short walk to the car; the server refuses the car before this has passed after a mechanic call-out.', 'number', 0, 120),
('roam.keke.enabled', 'true', 'roam', 'Hail a keke in free roam', 'Off = the Hail keke button disappears and roam_hail_keke is refused. The normal travel and the map are unaffected.', 'bool', null, null),
('roam.chunk.m', '120', 'roam', 'Streaming: chunk size (metres) - hint for clients', 'The 3D street is built in square chunks of about this size (clients clamp it to 80-200).', 'number', 80, 200),
('roam.chunk.load_m', '200', 'roam', 'Streaming: load radius (metres) - hint for clients', 'Chunks closer than this to the player are built; farther ones are removed. Low graphics shrinks it. Must be larger than the fastest speed times the build time of a chunk.', 'number', 100, 400)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. The session table gets the mode and the car (own table, not profiles)
-- ---------------------------------------------------------------------------------------------
alter table public.roam_sessions add column if not exists mode text not null default 'walk';
alter table public.roam_sessions add column if not exists vehicle text;
alter table public.roam_sessions add column if not exists mode_at timestamptz;
alter table public.roam_sessions add column if not exists drive_m numeric not null default 0;
alter table public.roam_sessions add column if not exists last_report_at timestamptz;
alter table public.roam_sessions add column if not exists rep_win_start timestamptz;
alter table public.roam_sessions add column if not exists rep_win_n int not null default 0;
alter table public.roam_sessions add column if not exists dmg_win_start timestamptz;
alter table public.roam_sessions add column if not exists dmg_win numeric not null default 0;
alter table public.roam_sessions add column if not exists car_place text;
alter table public.roam_sessions add column if not exists car_x numeric;
alter table public.roam_sessions add column if not exists car_y numeric;
alter table public.roam_sessions add column if not exists car_a numeric;
alter table public.roam_sessions add column if not exists car_ready_at timestamptz;

-- ---------------------------------------------------------------------------------------------
-- 3. Patches to the phase 1 functions (guarded single replace, unique helper name)
-- ---------------------------------------------------------------------------------------------
create or replace function pg_temp.roam2_patch(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n <> 1 then raise exception 'roam2: % : marker found % times: %', p_sig, v_n, left(p_marker, 90); end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- the area: any place when roam.area.all is on
select pg_temp.roam2_patch('public.bl_roam_in_area(text)', 'roam.area.all) or l.x',
$m$and l.x between bl_cfg('roam.area.x0') and bl_cfg('roam.area.x1')$m$,
$m$and (bl_cfg_bool('roam.area.all') or l.x between bl_cfg('roam.area.x0') and bl_cfg('roam.area.x1'))$m$);
select pg_temp.roam2_patch('public.bl_roam_in_area(text)', 'roam.area.all) or l.y',
$m$and l.y between bl_cfg('roam.area.y0') and bl_cfg('roam.area.y1'));$m$,
$m$and (bl_cfg_bool('roam.area.all') or l.y between bl_cfg('roam.area.y0') and bl_cfg('roam.area.y1')));$m$);

-- roam_start: a fresh walk is on foot; the answer carries the client hints
select pg_temp.roam2_patch('public.roam_start(text)', 'set mode = ''walk''',
$m$  update profiles set last_seen = v_now where id = v_me.id;$m$,
$m$  update roam_sessions set mode = 'walk', vehicle = null, mode_at = v_now, drive_m = 0, last_report_at = null where user_id = v_me.id;
  update profiles set last_seen = v_now where id = v_me.id;$m$);
select pg_temp.roam2_patch('public.roam_start(text)', '''max_drive_mps''',
$m$'ttl_s', bl_cfg('roam.session_ttl_s'))$m$,
$m$'ttl_s', bl_cfg('roam.session_ttl_s'),
    'all', bl_cfg_bool('roam.area.all'), 'drive', bl_cfg_bool('roam.drive.enabled'), 'keke', bl_cfg_bool('roam.keke.enabled'),
    'max_drive_mps', bl_cfg('roam.drive.max_speed_mps'), 'chunk_m', bl_cfg('roam.chunk.m'), 'load_m', bl_cfg('roam.chunk.load_m'))$m$);

-- roam_enter: pace by mode, the distance a car must have reported, street risk by mode, the car is left at the place
select pg_temp.roam2_patch('public.roam_enter(text)', 'roam.drive.max_speed_mps',
$m$/ bl_cfg('roam.max_speed_mps'));$m$,
$m$/ case when s.mode = 'car' then bl_cfg('roam.drive.max_speed_mps') else bl_cfg('roam.max_speed_mps') end);$m$);
select pg_temp.roam2_patch('public.roam_enter(text)', 'roam.drive.min_report_pct',
$m$    if v_el < v_need then$m$,
$m$    if s.mode = 'car' and s.drive_m < greatest(0, v_dist - bl_cfg('roam.door_slack_m')) * bl_cfg('roam.drive.min_report_pct') / 100.0 then
      update roam_sessions set win_start = v_ws, win_n = v_n where user_id = v_me.id;
      return jsonb_build_object('ok', false, 'hint', 'far', 'message', 'You have not driven that far yet. Keep driving.');
    end if;
    if v_el < v_need then$m$);
select pg_temp.roam2_patch('public.roam_enter(text)', 'case when s.mode = ''car'' then ''car'' else ''walk'' end',
$m$bl_roll_street_robbery(v_me.id, p_place, 'walk', 1)$m$,
$m$bl_roll_street_robbery(v_me.id, p_place, case when s.mode = 'car' then 'car' else 'walk' end, 1)$m$);
select pg_temp.roam2_patch('public.roam_enter(text)', 'car_place = case',
$m$update roam_sessions set place = p_place, anchor_at = v_now, enters = enters + 1, win_start = v_ws, win_n = v_n$m$,
$m$update roam_sessions set place = p_place, anchor_at = v_now, enters = enters + 1, win_start = v_ws, win_n = v_n,
         car_place = case when s.mode = 'car' then p_place else car_place end, car_x = case when s.mode = 'car' then null else car_x end,
         car_y = case when s.mode = 'car' then null else car_y end, mode = 'walk', vehicle = null, drive_m = 0$m$);

-- roam_leave: back on foot
select pg_temp.roam2_patch('public.roam_leave()', 'mode = ''walk''',
$m$update roam_sessions set ended = true where user_id = v_me.id;$m$,
$m$update roam_sessions set ended = true, mode = 'walk', vehicle = null where user_id = v_me.id;$m$);

-- ---------------------------------------------------------------------------------------------
-- 4. Helpers
-- ---------------------------------------------------------------------------------------------
-- the player's live session or an error (no session / timed out / moved on)
create or replace function public.bl_roam_session(p_me public.profiles) returns public.roam_sessions
language plpgsql volatile set search_path = public as $$
declare s roam_sessions;
begin
  select * into s from roam_sessions where user_id = p_me.id for update;
  if not found or s.ended then
    raise exception 'Step out into the street first.' using errcode = 'P0001', hint = 'no_session';
  end if;
  if bl_now() - s.started_at > make_interval(secs => bl_cfg('roam.session_ttl_s')) then
    raise exception 'Your walk timed out. Step out again.' using errcode = 'P0001', hint = 'no_session';
  end if;
  if p_me.location_id is distinct from s.place then
    raise exception 'You moved on since you stepped out. Step out again.' using errcode = 'P0001', hint = 'no_session';
  end if;
  return s;
end $$;

-- one call counted against the per-minute window of roam_start / roam_enter; raises 'rate' when over
create or replace function public.bl_roam_count_call(p_uid uuid) returns void
language plpgsql volatile set search_path = public as $$
declare s roam_sessions; v_now timestamptz := bl_now(); v_ws timestamptz; v_n int;
begin
  select * into s from roam_sessions where user_id = p_uid for update;
  if not found then return; end if;
  if v_now - s.win_start < make_interval(secs => bl_cfg('roam.rate.window_s')) then
    v_ws := s.win_start; v_n := s.win_n + 1;
  else
    v_ws := v_now; v_n := 1;
  end if;
  update roam_sessions set win_start = v_ws, win_n = v_n where user_id = p_uid;
  if v_n > bl_cfg('roam.rate.max_calls') then
    raise exception 'Slow down a little, you are going too fast.' using errcode = 'P0001', hint = 'rate';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. RPCs (security definer, volatile: they call bl_me())
-- ---------------------------------------------------------------------------------------------
-- what the player drives, its tank and condition, and where it was left
create or replace function public.roam_car_info() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  v_item text := bl_driving_item(v_me.id);
  r      vehicle_state;
  s      roam_sessions;
  v_cls  text;
  v_name text;
begin
  select * into s from roam_sessions where user_id = v_me.id;
  if v_item is null then
    return jsonb_build_object('has_car', false, 'enabled', bl_cfg_bool('roam.drive.enabled'));
  end if;
  v_cls := bl_vehicle_class(v_item);
  r := bl_vehicle_peek(v_me.id, v_item);
  select name into v_name from items where id = v_item;
  return jsonb_build_object('has_car', true, 'enabled', bl_cfg_bool('roam.drive.enabled'), 'item', v_item, 'name', v_name, 'class', v_cls,
    'fuel_l', round(r.fuel_l, 2), 'tank_l', bl_vehicle_tank(v_cls), 'cond', round(r.cond), 'fuel_on', bl_cfg_bool('drive.fuel.enabled'),
    'wont_start', bl_cfg_bool('drive.damage.enabled') and r.cond <= 0,
    'car_place', s.car_place, 'car_x', s.car_x, 'car_y', s.car_y, 'car_a', s.car_a,
    'ready_in_s', case when s.car_ready_at is not null and s.car_ready_at > bl_now() then ceil(extract(epoch from s.car_ready_at - bl_now())) else 0 end,
    'rain', coalesce((bl_drive_weather() ->> 'rain')::boolean, false), 'mode', coalesce(s.mode, 'walk'),
    'max_drive_mps', bl_cfg('roam.drive.max_speed_mps'));
end $$;

-- walk <-> own vehicle. 'car' checks ownership, condition and fuel; 'walk' records where the vehicle was left (cosmetic).
create or replace function public.roam_set_mode(p_mode text, p_vehicle text default null, p_x numeric default null, p_y numeric default null, p_a numeric default null) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  v_now  timestamptz := bl_now();
  s      roam_sessions;
  v_item text;
  v_cls  text;
  r      vehicle_state;
begin
  perform bl_roam_gate();
  perform bl_assert_free(v_me);
  if p_mode is null or p_mode not in ('walk', 'car') then
    raise exception 'Unknown way to get around.' using errcode = 'P0001', hint = 'bad_mode';
  end if;
  s := bl_roam_session(v_me);
  perform bl_roam_count_call(v_me.id);
  if p_mode = 'walk' then
    update roam_sessions set mode = 'walk', vehicle = null, mode_at = v_now, last_report_at = null,
           car_place = null,
           car_x = case when p_x is null then car_x else greatest(0, least(1000, p_x)) end,
           car_y = case when p_y is null then car_y else greatest(0, least(1000, p_y)) end,
           car_a = case when p_a is null then car_a else p_a end
     where user_id = v_me.id;
    return jsonb_build_object('ok', true, 'mode', 'walk');
  end if;
  if not bl_cfg_bool('roam.drive.enabled') then
    raise exception 'Driving in the street is switched off for now.' using errcode = 'P0001', hint = 'off';
  end if;
  v_item := coalesce(p_vehicle, bl_driving_item(v_me.id));
  if v_item is null or not exists (select 1 from inventory i join items it on it.id = i.item_id
                                    where i.user_id = v_me.id and i.item_id = v_item and i.qty > 0 and it.category = 'vehicle') then
    raise exception 'You do not own a vehicle to drive.' using errcode = 'P0001', hint = 'not_owned';
  end if;
  v_cls := bl_vehicle_class(v_item);
  r := bl_vehicle_row(v_me.id, v_item);
  if bl_cfg_bool('drive.damage.enabled') and r.cond <= 0 then
    raise exception 'Your vehicle is too damaged to start. Repair it at the Mechanic Village, or hail a keke for now.' using errcode = 'P0001', hint = 'wont_start';
  end if;
  if v_cls <> 'bicycle' and bl_cfg_bool('drive.fuel.enabled') and r.fuel_l <= 0.01 then
    raise exception 'The tank is empty. Call a mechanic, push it to a pump, or hail a keke.' using errcode = 'P0001', hint = 'no_fuel';
  end if;
  if s.car_ready_at is not null and s.car_ready_at > v_now then
    raise exception 'The mechanic is still working on it.' using errcode = 'P0001', hint = 'busy';
  end if;
  update roam_sessions set mode = 'car', vehicle = v_item, mode_at = v_now, last_report_at = v_now, car_place = null where user_id = v_me.id;
  return jsonb_build_object('ok', true, 'mode', 'car', 'item', v_item, 'class', v_cls, 'fuel_l', round(r.fuel_l, 2),
    'tank_l', bl_vehicle_tank(v_cls), 'cond', round(r.cond), 'max_drive_mps', bl_cfg('roam.drive.max_speed_mps'));
end $$;

-- fuel and damage checkpoint while driving. p_stats = {dist_m, light, hard, x, y, a}; every number is clamped.
create or replace function public.roam_drive_report(p_stats jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_now   timestamptz := bl_now();
  s       roam_sessions;
  r       vehicle_state;
  v_cls   text;
  v_el    numeric;
  v_dist  numeric;
  v_max   numeric;
  v_l     numeric := 0;
  v_light numeric; v_hard numeric; v_cap numeric;
  v_dmg   numeric := 0;
  v_win   numeric;
  v_ws    timestamptz;
  v_rws   timestamptz;
  v_rn    int;
  v_fuel  numeric;
  v_cond  numeric;
  v_x numeric; v_y numeric;
begin
  perform bl_roam_gate();
  if not bl_cfg_bool('roam.drive.enabled') then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  s := bl_roam_session(v_me);
  if s.mode is distinct from 'car' or s.vehicle is null then return jsonb_build_object('ok', false, 'reason', 'not_driving'); end if;
  -- rate limits: a gap between checkpoints and a count a minute
  if s.last_report_at is not null and v_now < s.last_report_at + make_interval(secs => bl_cfg('roam.drive.report_gap_s')::double precision) then
    return jsonb_build_object('ok', false, 'reason', 'too_soon');
  end if;
  if s.rep_win_start is not null and v_now - s.rep_win_start < interval '60 seconds' then
    v_rws := s.rep_win_start; v_rn := s.rep_win_n + 1;
  else
    v_rws := v_now; v_rn := 1;
  end if;
  if v_rn > bl_cfg('roam.drive.max_reports_min') then
    return jsonb_build_object('ok', false, 'reason', 'rate');
  end if;
  v_cls := bl_vehicle_class(s.vehicle);
  r := bl_vehicle_row(v_me.id, s.vehicle);
  v_el := greatest(0, extract(epoch from v_now - coalesce(s.last_report_at, s.mode_at, v_now)));
  -- distance: a JSON number, capped by max speed x elapsed (+ slack); a dead engine rolls a few metres at most
  v_max := bl_cfg('roam.drive.max_speed_mps') * v_el + bl_cfg('roam.drive.slack_m');
  v_dist := case when jsonb_typeof(p_stats -> 'dist_m') = 'number' then greatest(0, least((p_stats ->> 'dist_m')::numeric, v_max)) else 0 end;
  -- fuel follows the capped distance
  if v_cls <> 'bicycle' and bl_cfg_bool('drive.fuel.enabled') and v_dist > 0 then
    v_l := round(v_dist / 1000.0 * bl_cfg('roam.drive.fuel_scale') * bl_cfg('drive.fuel.lpk_' || v_cls)
                 * (1 + bl_drive_wear(r.cond) * bl_cfg('drive.damage.fuel_pct') / 100.0), 3);
  end if;
  v_fuel := greatest(0, r.fuel_l - v_l);
  -- hits: counts, cut by the time that passed and the per-report cap, then by the per-minute damage cap
  v_cap := greatest(0, least(bl_cfg('roam.drive.max_hits_report'), floor(v_el / greatest(0.1, bl_cfg('roam.drive.min_s_per_hit'))) + 1));
  v_hard := case when jsonb_typeof(p_stats -> 'hard') = 'number' then greatest(0, least(1000, floor((p_stats ->> 'hard')::numeric))) else 0 end;
  v_light := case when jsonb_typeof(p_stats -> 'light') = 'number' then greatest(0, least(1000, floor((p_stats ->> 'light')::numeric))) else 0 end;
  v_hard := least(v_hard, v_cap);
  v_light := least(v_light, v_cap - v_hard);
  v_dmg := (v_light * bl_cfg('roam.drive.damage_light') + v_hard * bl_cfg('roam.drive.damage_hard'))
           * case when coalesce((bl_drive_weather() ->> 'rain')::boolean, false) then bl_cfg('drive.rain.damage_mult') else 1 end;
  if not bl_cfg_bool('drive.damage.enabled') then v_dmg := 0; end if;
  if s.dmg_win_start is not null and v_now - s.dmg_win_start < interval '60 seconds' then
    v_ws := s.dmg_win_start; v_win := s.dmg_win;
  else
    v_ws := v_now; v_win := 0;
  end if;
  v_dmg := greatest(0, least(v_dmg, bl_cfg('roam.drive.max_damage_report'), bl_cfg('roam.drive.max_damage_min') - v_win));
  v_cond := greatest(0, r.cond - v_dmg);
  update vehicle_state set fuel_l = v_fuel, cond = v_cond, updated_at = v_now where user_id = v_me.id and item_id = s.vehicle;
  v_x := case when jsonb_typeof(p_stats -> 'x') = 'number' then greatest(0, least(1000, (p_stats ->> 'x')::numeric)) end;
  v_y := case when jsonb_typeof(p_stats -> 'y') = 'number' then greatest(0, least(1000, (p_stats ->> 'y')::numeric)) end;
  update roam_sessions set last_report_at = v_now, rep_win_start = v_rws, rep_win_n = v_rn, dmg_win_start = v_ws, dmg_win = v_win + v_dmg,
         drive_m = drive_m + v_dist, car_x = coalesce(v_x, car_x), car_y = coalesce(v_y, car_y),
         car_a = case when jsonb_typeof(p_stats -> 'a') = 'number' then (p_stats ->> 'a')::numeric else car_a end
   where user_id = v_me.id;
  return jsonb_build_object('ok', true, 'dist_m', round(v_dist, 1), 'burned_l', round(v_l, 3), 'fuel_l', round(v_fuel, 2),
    'tank_l', bl_vehicle_tank(v_cls), 'cond', round(v_cond), 'damage', round(v_dmg, 1),
    'empty', v_cls <> 'bicycle' and bl_cfg_bool('drive.fuel.enabled') and v_fuel <= 0.01,
    'wont_start', bl_cfg_bool('drive.damage.enabled') and v_cond <= 0);
end $$;

-- the car is dry: push it to the kerb (free) or call a mechanic (cash, litres, a wait). The third way out is Hail keke.
create or replace function public.roam_dry_choose(p_choice text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_now   timestamptz := bl_now();
  s       roam_sessions;
  r       vehicle_state;
  v_item  text;
  v_cost  bigint := 0;
  v_wait  int := 0;
  v_l     numeric := 0;
  v_msg   text;
begin
  perform bl_roam_gate();
  perform bl_assert_free(v_me);
  s := bl_roam_session(v_me);
  perform bl_roam_count_call(v_me.id);
  v_item := coalesce(s.vehicle, bl_driving_item(v_me.id));
  if v_item is null then
    raise exception 'You do not own a vehicle.' using errcode = 'P0001', hint = 'not_owned';
  end if;
  r := bl_vehicle_row(v_me.id, v_item);
  if bl_vehicle_class(v_item) = 'bicycle' or r.fuel_l > 0.01 then
    raise exception 'The tank is not empty.' using errcode = 'P0001', hint = 'not_dry';
  end if;
  if p_choice = 'push' then
    perform bl_adjust_needs(v_me.id, jsonb_build_object('stress', bl_cfg('drive.dry.push_stress')));
    v_wait := bl_cfg('drive.dry.push_s')::int;
    v_msg := 'You and two strangers push the car to the kerb. Tiring, but it is out of the way.';
  elsif p_choice = 'mechanic' then
    v_cost := bl_cfg('drive.dry.mechanic_cost')::bigint;
    if v_cost > v_me.cash then
      raise exception 'The mechanic wants % and you no get am. Push the car or hail a keke.', bl_naira(v_cost) using errcode = 'P0001', hint = 'not_enough_cash';
    end if;
    v_wait := round(bl_cfg('drive.dry.mechanic_wait_min_s') + bl_rand() * greatest(0, bl_cfg('drive.dry.mechanic_wait_max_s') - bl_cfg('drive.dry.mechanic_wait_min_s')))::int;
    v_l := bl_cfg('drive.dry.mechanic_litres');
    perform bl_add_money(v_me.id, 'cash', -v_cost, 'vehicle_mechanic', jsonb_build_object('item', v_item, 'where', 'roam'));
    update vehicle_state set fuel_l = least(bl_vehicle_tank(bl_vehicle_class(v_item)), v_l), updated_at = v_now
     where user_id = v_me.id and item_id = v_item;
    update roam_sessions set car_ready_at = v_now + make_interval(secs => v_wait::double precision) where user_id = v_me.id;
    v_msg := 'The mechanic arrives on a bike with a can, charges ' || bl_naira(v_cost) || ' and gets you going.';
  else
    raise exception 'That choice is not on the card.' using errcode = 'P0001', hint = 'bad_choice';
  end if;
  update roam_sessions set mode = 'walk', vehicle = null, mode_at = v_now, last_report_at = null where user_id = v_me.id;
  return jsonb_build_object('ok', true, 'choice', p_choice, 'message', v_msg, 'cash_delta', -v_cost, 'wait_s', v_wait, 'fuel_l', v_l);
end $$;

-- hail a keke from the street: the normal keke trip (normal fare, normal clock), then the street opens again at the destination
create or replace function public.roam_hail_keke(p_dest text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me  profiles := bl_me();
  s     roam_sessions;
  v_res jsonb;
begin
  perform bl_roam_gate();
  if not bl_cfg_bool('roam.keke.enabled') then
    raise exception 'Hailing a keke from the street is switched off for now.' using errcode = 'P0001', hint = 'off';
  end if;
  perform bl_assert_free(v_me);
  s := bl_roam_session(v_me);
  if s.mode = 'car' then
    raise exception 'Get out of your car first.' using errcode = 'P0001', hint = 'in_car';
  end if;
  perform bl_roam_count_call(v_me.id);
  v_res := travel_start(p_dest, 'keke');
  update roam_sessions set ended = true, mode = 'walk', vehicle = null where user_id = v_me.id;
  return v_res;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------------------------
revoke execute on function public.bl_roam_session(public.profiles) from public, anon, authenticated;
revoke execute on function public.bl_roam_count_call(uuid) from public, anon, authenticated;
revoke execute on function public.roam_car_info() from public, anon;
revoke execute on function public.roam_set_mode(text, text, numeric, numeric, numeric) from public, anon;
revoke execute on function public.roam_drive_report(jsonb) from public, anon;
revoke execute on function public.roam_dry_choose(text) from public, anon;
revoke execute on function public.roam_hail_keke(text) from public, anon;
grant execute on function public.roam_car_info() to authenticated;
grant execute on function public.roam_set_mode(text, text, numeric, numeric, numeric) to authenticated;
grant execute on function public.roam_drive_report(jsonb) to authenticated;
grant execute on function public.roam_dry_choose(text) to authenticated;
grant execute on function public.roam_hail_keke(text) to authenticated;

notify pgrst, 'reload schema';
