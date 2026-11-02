-- Drive scene 2 (docs/DRIVE.md): trips take a real amount of time and the bus is called "ECTS Bus".
--   * Trip length grows with the real route distance: real_seconds = clamp(base + per_km * km * mode factor, min, max).
--     Short hops are short, cross-town trips are long. Walk, keke, bus, drop, car, motorcycle and bicycle keep their own pace
--     through a per-mode factor. Server-owned: the quote returns real_seconds and travel_start stores the arrival time from it, so the
--     3D drive (which draws the trip from the start and arrival timestamps) always ends exactly when the server says.
--   * Master switch drive.travel.real_time_enabled: off = the old timings (game minutes, short-mode cap action.travel_max_seconds).
--     While it is on, the old cap does NOT clip the trip; drive.travel.max_seconds is the one cap.
--   * "ECTS Green Bus" is now "ECTS Bus" in the travel options.
-- Patches the live bl_travel_quote(profiles, text) by guarded replace (unique pg_temp helper). No profiles DDL, no triggers, no loops over players.

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('drive.travel.real_time_enabled', 'true', 'drive', 'Trip time grows with distance', 'On = every trip lasts base + seconds per km x distance x the mode factor (between the shortest and longest below), so cross-town trips feel long and short hops are short. Off = the old short trip times.', 'bool', null, null),
('drive.travel.base_seconds', '15', 'drive', 'Trip time: base seconds', 'Every trip takes at least this much before distance is added (getting going, parking).', 'number', 0, 300),
('drive.travel.seconds_per_km', '7.5', 'drive', 'Trip time: seconds per km', 'Real seconds added for each km of the route, for a car. Other modes multiply it by their factor below.', 'number', 0, 120),
('drive.travel.min_seconds', '25', 'drive', 'Trip time: shortest trip (seconds)', 'No trip is shorter than this while real trip time is on.', 'number', 1, 600),
('drive.travel.max_seconds', '150', 'drive', 'Trip time: longest trip (seconds)', 'No trip is longer than this while real trip time is on. It replaces the old cap (action.travel_max_seconds) for as long as the switch is on.', 'number', 5, 1800),
('drive.travel.f_walk', '3', 'drive', 'Trip time factor: walking', 'Times the seconds per km. Walking is slow.', 'number', 0.1, 20),
('drive.travel.f_keke', '1.3', 'drive', 'Trip time factor: keke', 'Times the seconds per km.', 'number', 0.1, 20),
('drive.travel.f_bus', '1.6', 'drive', 'Trip time factor: ECTS Bus', 'Times the seconds per km. The bus stops on the way, so it is slower than a car.', 'number', 0.1, 20),
('drive.travel.f_drop', '1.1', 'drive', 'Trip time factor: drop (ride-hail)', 'Times the seconds per km.', 'number', 0.1, 20),
('drive.travel.f_car', '1', 'drive', 'Trip time factor: your own car', 'Times the seconds per km. 1 = the reference pace.', 'number', 0.1, 20),
('drive.travel.f_motorcycle', '0.85', 'drive', 'Trip time factor: your motorcycle', 'Times the seconds per km. Bikes slip through the go-slow.', 'number', 0.1, 20),
('drive.travel.f_bicycle', '1.8', 'drive', 'Trip time factor: your bicycle', 'Times the seconds per km.', 'number', 0.1, 20)
on conflict (key) do nothing;

-- guarded single replace of the live function: finds the marker exactly once, skips when already patched
create or replace function pg_temp.drv2_patch(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n <> 1 then raise exception 'drive_realtime: % : marker found % times: %', p_sig, v_n, left(p_marker, 90); end if;
  execute replace(v_def, p_marker, p_new);
end $$;

select pg_temp.drv2_patch('public.bl_travel_quote(public.profiles, text)', 'drive.travel.real_time_enabled',
$m$    if v_short then
      v_rs := least(v_rs, greatest(bl_cfg('action.travel_max_seconds'), v_minrs));
    end if;$m$,
$m$    if bl_cfg_bool('drive.travel.real_time_enabled') then
      -- drive 2: the trip lasts as long as the real route (the old short-mode cap does not apply)
      v_rs := greatest(bl_cfg('drive.travel.min_seconds'), least(bl_cfg('drive.travel.max_seconds'),
                bl_cfg('drive.travel.base_seconds') + bl_cfg('drive.travel.seconds_per_km') * v_km * bl_cfg('drive.travel.f_' || v_key)));
    elsif v_short then
      v_rs := least(v_rs, greatest(bl_cfg('action.travel_max_seconds'), v_minrs));
    end if;$m$);

select pg_temp.drv2_patch('public.bl_travel_quote(public.profiles, text)', '''ECTS Bus''',
  '''ECTS Green Bus''', '''ECTS Bus''');

notify pgrst, 'reload schema';
