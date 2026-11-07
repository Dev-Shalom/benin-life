-- Free roam, phase 1 (docs/ROAM.md): walk the real streets around King's Square in 3D.
--   * Server-authoritative and light: positions in the 3D street are cosmetic. The server only knows three things:
--       roam_start(place)  the player is at that place (not travelling, not busy) and steps out into the street;
--       roam_enter(place)  the player walks into a place INSIDE the phase-1 area. Allowed only with a roam session, and only when
--                          enough real time has passed since the session started (or the last enter) for the walking distance at a
--                          maximum walking / running speed (anti-teleport), then the player's location moves exactly like arriving;
--       roam_leave()       the player closes the street view.
--   * roam_sessions (user_id key, no profiles column, no foreign key, no trigger): where the walk began and when the player was last
--     known there, plus a one-minute call counter (rate limit).
--   * Every number is a setting in category "roam" (Admin -> Settings -> Free roam): master switch, area switch and box, speeds, slack,
--     session time, rate limit.
-- No profiles DDL, no triggers, no loops over players, no patches to live functions. Idempotent.

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (category roam)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('roam.enabled', 'true', 'roam', 'Free roam on', 'Master switch. Off = the Step outside / Walk the city buttons disappear and roam_start / roam_enter are refused. Nobody is moved or stuck: the normal map and travel work as before.', 'bool', null, null),
('roam.area.enabled', 'true', 'roam', 'King''s Square area open', 'Phase 1 area (Ring Road, King''s Square and the streets round it). Off = no place is open for free roam.', 'bool', null, null),
('roam.area.x0', '395', 'roam', 'Area: west edge (map x)', 'Phase 1 walkable box in map units (the same numbers as the 3D map, 0 to 1000, King''s Square is 500, 500). A place counts as inside when its map position is in the box. The 3D street is built for the default box: only change it together with the client.', 'number', 0, 1000),
('roam.area.y0', '392', 'roam', 'Area: north edge (map y)', 'North edge of the phase 1 box (map units, north is a smaller number).', 'number', 0, 1000),
('roam.area.x1', '610', 'roam', 'Area: east edge (map x)', 'East edge of the phase 1 box (map units).', 'number', 0, 1000),
('roam.area.y1', '645', 'roam', 'Area: south edge (map y)', 'South edge of the phase 1 box (map units).', 'number', 0, 1000),
('roam.max_speed_mps', '6.5', 'roam', 'Anti-teleport: fastest pace (metres a second)', 'Walking is about 2 m/s and running about 5 m/s in the street. Walking into a place must take at least the distance divided by this. Raise it if honest players get "too fast" messages.', 'number', 1, 30),
('roam.door_slack_m', '15', 'roam', 'Anti-teleport: free metres', 'Doors stand a few metres from the map marker, so this many metres of the distance are not counted.', 'number', 0, 100),
('roam.min_enter_s', '1.5', 'roam', 'Anti-teleport: shortest time before going into another place (seconds)', 'Even for a neighbouring door.', 'number', 0, 60),
('roam.session_ttl_s', '7200', 'roam', 'Walk session lasts (seconds)', 'A street walk older than this must be started again from a place.', 'number', 60, 86400),
('roam.rate.window_s', '60', 'roam', 'Rate limit: window (seconds)', 'roam_start and roam_enter calls are counted per player over this window.', 'number', 5, 3600),
('roam.rate.max_calls', '20', 'roam', 'Rate limit: calls per window', 'More than this in one window is refused with "Slow down a little".', 'number', 1, 1000)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. The session table (read only through the RPCs)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.roam_sessions (
  user_id    uuid primary key,
  place      text not null,
  started_at timestamptz not null,
  anchor_at  timestamptz not null,
  enters     int not null default 0,
  win_start  timestamptz not null,
  win_n      int not null default 0
);
alter table public.roam_sessions enable row level security;
revoke all on public.roam_sessions from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_roam_gate() returns void
language plpgsql stable set search_path = public as $$
begin
  if not bl_cfg_bool('roam.enabled') or not bl_cfg_bool('roam.area.enabled') then
    raise exception 'Walking the city is switched off for now.' using errcode = 'P0001', hint = 'off';
  end if;
end $$;

-- is this an active place whose map position is inside the phase 1 box?
create or replace function public.bl_roam_in_area(p_place text) returns boolean
language sql stable set search_path = public as $$
  select exists (
    select 1 from locations l
     where l.id = p_place and l.active
       and l.x between bl_cfg('roam.area.x0') and bl_cfg('roam.area.x1')
       and l.y between bl_cfg('roam.area.y0') and bl_cfg('roam.area.y1'));
$$;

-- ---------------------------------------------------------------------------------------------
-- 4. RPCs (security definer, volatile: they call bl_me())
-- ---------------------------------------------------------------------------------------------
create or replace function public.roam_start(p_place text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me  profiles := bl_me();
  v_now timestamptz := bl_now();
  s     roam_sessions;
  v_ws  timestamptz;
  v_n   int;
begin
  perform bl_roam_gate();
  perform bl_assert_free(v_me);
  if v_me.location_id is distinct from p_place then
    raise exception 'You are not at that place.' using errcode = 'P0001', hint = 'not_here';
  end if;
  if not bl_roam_in_area(p_place) then
    raise exception 'You can only walk the streets round King''s Square for now.' using errcode = 'P0001', hint = 'outside';
  end if;
  select * into s from roam_sessions where user_id = v_me.id for update;
  if found and v_now - s.win_start < make_interval(secs => bl_cfg('roam.rate.window_s')) then
    v_ws := s.win_start; v_n := s.win_n + 1;
  else
    v_ws := v_now; v_n := 1;
  end if;
  if v_n > bl_cfg('roam.rate.max_calls') then
    raise exception 'Slow down a little, you are going too fast.' using errcode = 'P0001', hint = 'rate';
  end if;
  insert into roam_sessions (user_id, place, started_at, anchor_at, enters, win_start, win_n)
  values (v_me.id, p_place, v_now, v_now, 0, v_ws, v_n)
  on conflict (user_id) do update
    set place = excluded.place, started_at = excluded.started_at, anchor_at = excluded.anchor_at, enters = 0,
        win_start = excluded.win_start, win_n = excluded.win_n;
  update profiles set last_seen = v_now where id = v_me.id;
  return jsonb_build_object('ok', true, 'place', p_place, 'max_speed_mps', bl_cfg('roam.max_speed_mps'),
    'ttl_s', bl_cfg('roam.session_ttl_s'));
end $$;

create or replace function public.roam_enter(p_place text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  v_now  timestamptz := bl_now();
  s      roam_sessions;
  v_ws   timestamptz;
  v_n    int;
  v_ax   numeric; v_ay numeric; v_bx numeric; v_by numeric;
  v_dist numeric; v_need numeric; v_el numeric;
  v_name text;
begin
  perform bl_roam_gate();
  perform bl_assert_free(v_me);
  select * into s from roam_sessions where user_id = v_me.id for update;
  if not found then
    raise exception 'Step out into the street first.' using errcode = 'P0001', hint = 'no_session';
  end if;
  if v_now - s.started_at > make_interval(secs => bl_cfg('roam.session_ttl_s')) then
    raise exception 'Your walk timed out. Step out again.' using errcode = 'P0001', hint = 'no_session';
  end if;
  if v_me.location_id is distinct from s.place then
    raise exception 'You moved on since you stepped out. Step out again.' using errcode = 'P0001', hint = 'no_session';
  end if;
  if v_now - s.win_start < make_interval(secs => bl_cfg('roam.rate.window_s')) then
    v_ws := s.win_start; v_n := s.win_n + 1;
  else
    v_ws := v_now; v_n := 1;
  end if;
  if v_n > bl_cfg('roam.rate.max_calls') then
    return jsonb_build_object('ok', false, 'hint', 'rate', 'message', 'Slow down a little, you are going too fast.');
  end if;
  if not bl_roam_in_area(p_place) then
    -- a refusal that is returned (not raised) keeps the call counter, so hammering a far door is rate limited too
    update roam_sessions set win_start = v_ws, win_n = v_n where user_id = v_me.id;
    return jsonb_build_object('ok', false, 'hint', 'outside', 'message', 'You can only walk into places round King''s Square for now.');
  end if;
  select name into v_name from locations where id = p_place;
  if p_place <> s.place then
    select x, y into v_ax, v_ay from locations where id = s.place;
    select x, y into v_bx, v_by from locations where id = p_place;
    v_dist := sqrt((v_ax - v_bx) ^ 2 + (v_ay - v_by) ^ 2);
    v_need := greatest(bl_cfg('roam.min_enter_s'), greatest(0, v_dist - bl_cfg('roam.door_slack_m')) / bl_cfg('roam.max_speed_mps'));
    v_el := extract(epoch from v_now - s.anchor_at);
    if v_el < v_need then
      update roam_sessions set win_start = v_ws, win_n = v_n where user_id = v_me.id;
      return jsonb_build_object('ok', false, 'hint', 'far', 'wait_s', ceil(v_need - v_el),
        'message', 'That is too far to have walked already. Keep walking, about ' || ceil(v_need - v_el) || ' more seconds.');
    end if;
    update profiles set location_id = p_place, last_seen = v_now where id = v_me.id;
    perform bl_vip_arrival(v_me.id, p_place);
  else
    update profiles set last_seen = v_now where id = v_me.id;
  end if;
  update roam_sessions set place = p_place, anchor_at = v_now, enters = enters + 1, win_start = v_ws, win_n = v_n
   where user_id = v_me.id;
  return jsonb_build_object('ok', true, 'location', p_place, 'name', v_name,
    'message', case when p_place = s.place then 'You went back in to ' || v_name || '.' else 'You walked into ' || v_name || '.' end);
end $$;

create or replace function public.roam_leave() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me();
begin
  delete from roam_sessions where user_id = v_me.id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------------------------------
revoke execute on function public.bl_roam_gate() from public, anon, authenticated;
revoke execute on function public.bl_roam_in_area(text) from public, anon, authenticated;
revoke execute on function public.roam_start(text) from public, anon;
revoke execute on function public.roam_enter(text) from public, anon;
revoke execute on function public.roam_leave() from public, anon;
grant execute on function public.roam_start(text) to authenticated;
grant execute on function public.roam_enter(text) to authenticated;
grant execute on function public.roam_leave() to authenticated;

notify pgrst, 'reload schema';
