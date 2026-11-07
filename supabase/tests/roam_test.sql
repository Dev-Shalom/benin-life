-- Free roam, phase 1 (20261118000100_roam.sql, docs/ROAM.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/roam_test.sql
-- Groups: 1 settings · 2 roam_start checks · 3 roam_enter (session, area, anti-teleport timing) · 4 rate limit · 5 switches ·
-- 6 leave / session lifetime / isolation between players · 7 structure and grants.
-- Time is pinned with bl.test_offset_seconds (bl_now()), so every timing below is exact.
create or replace function pg_temp.adv(p_secs double precision) returns void
language plpgsql as $$
begin
  perform set_config('bl.test_offset_seconds',
    (coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::double precision, 0) + p_secs)::text, true);
end $$;

create or replace function pg_temp.setc(p_key text, p_val jsonb) returns void
language sql as $$ update game_config set value = p_val where key = p_key $$;

-- the outcome of a statement as 'ok' or its hint (or the message when there is no hint)
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

create temp table rm_u (name text primary key, id uuid);

do $$
declare v uuid; w uuid;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  v := pg_temp.new_user('rm_a@roam.bl');
  perform pg_temp.login(v);
  perform create_profile_v2('RM_a', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  insert into rm_u values ('a', v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  w := pg_temp.new_user('rm_b@roam.bl');
  perform pg_temp.login(w);
  perform create_profile_v2('RM_b', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  insert into rm_u values ('b', w);
  perform pg_temp.login(v);
end $$;

-- put the player at a place, free to move, nothing running
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
  perform pg_temp.assert((select count(*) from game_config where key like 'roam.%') = 12, 'twelve roam settings seeded');
  select count(*) into n from game_config where key like 'roam.%'
     and (category <> 'roam' or coalesce(label, '') = '' or coalesce(description, '') = '' or (kind in ('number', 'naira', 'percent') and (min is null or max is null)));
  perform pg_temp.assert(n = 0, 'every roam setting is in category roam with a label, a description and a range (' || n || ' without)');
  perform pg_temp.assert((select count(*) from game_config where key like 'roam.%' and (label ilike '%lagos%' or description ilike '%lagos%')) = 0, 'no "Lagos" in the settings text');
  perform pg_temp.assert((select kind from game_config where key = 'roam.enabled') = 'bool' and (select kind from game_config where key = 'roam.area.enabled') = 'bool', 'the switches are bools');
  perform pg_temp.assert(bl_cfg('roam.max_speed_mps') = 6.5 and bl_cfg('roam.area.x0') = 395 and bl_cfg('roam.area.y1') = 645 and bl_cfg('roam.rate.max_calls') = 20, 'defaults');
  perform pg_temp.assert(bl_cfg_bool('roam.enabled') and bl_cfg_bool('roam.area.enabled'), 'on by default');
  -- the area really holds the phase 1 places and not the far ones
  perform pg_temp.assert(bl_roam_in_area('national_museum') and bl_roam_in_area('oba_market') and bl_roam_in_area('ring_road_pos') and bl_roam_in_area('oba_palace')
    and bl_roam_in_area('police_hq') and bl_roam_in_area('mama_osas_buka') and bl_roam_in_area('igun_street') and bl_roam_in_area('sapele_pos'),
    'the King''s Square places are in the area');
  perform pg_temp.assert(not bl_roam_in_area('uniben') and not bl_roam_in_area('ramat_park') and not bl_roam_in_area('no_such_place'), 'far places and unknown ids are outside');
  perform pg_temp.assert(not bl_roam_in_area('mission_rd_flats'), 'an inactive place is never in the area');
end $$;

-- ---------- 2. roam_start ----------
do $$
declare a uuid := (select id from rm_u where name = 'a'); r jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'national_museum');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_start('oba_market')$q$) = 'not_here', 'start at a place you are not at: not_here');
  perform pg_temp.at(a, 'uniben');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_start('uniben')$q$) = 'outside', 'start at a place outside the area: outside');
  perform pg_temp.at(a, 'national_museum');
  update profiles set travel_to = 'oba_market', travel_mode = 'keke', travel_started_at = bl_now(), travel_arrives_at = bl_now() + interval '60 seconds' where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_start('national_museum')$q$) = 'traveling', 'start while travelling is refused');
  perform pg_temp.at(a, 'national_museum');
  update profiles set busy_until = bl_now() + interval '60 seconds', busy_label = 'Cooking' where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_start('national_museum')$q$) = 'busy', 'start while busy is refused');
  perform pg_temp.at(a, 'national_museum');
  perform pg_temp.assert(not exists (select 1 from roam_sessions where user_id = a), 'the refusals left no session');
  r := roam_start('national_museum');
  perform pg_temp.assert((r ->> 'ok')::boolean and r ->> 'place' = 'national_museum', 'start at the museum');
  perform pg_temp.assert((select place from roam_sessions where user_id = a) = 'national_museum', 'the session is recorded');
  perform pg_temp.assert((select count(*) from roam_sessions where user_id = a) = 1, 'one session per player');
  -- starting again replaces the session (a new anchor), never adds a row
  perform pg_temp.adv(5);
  r := roam_start('national_museum');
  perform pg_temp.assert((select count(*) from roam_sessions where user_id = a) = 1 and (select anchor_at from roam_sessions where user_id = a) = bl_now(), 'start again: one row, new anchor');
end $$;

-- ---------- 3. roam_enter ----------
do $$
declare a uuid := (select id from rm_u where name = 'a'); r jsonb; d numeric; need numeric; ax numeric; ay numeric; bx numeric; b_y numeric;
begin
  perform pg_temp.login(a);
  -- no session: refused
  delete from roam_sessions where user_id = a;
  perform pg_temp.at(a, 'national_museum');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_enter('oba_market')$q$) = 'no_session', 'enter without a session: no_session');
  r := roam_start('national_museum');
  -- the same place is always allowed (no walking)
  r := roam_enter('national_museum');
  perform pg_temp.assert((r ->> 'ok')::boolean and (select location_id from profiles where id = a) = 'national_museum', 'going back into the place you stepped out of');
  -- a far door at once: refused, the player stays put
  r := roam_start('national_museum');
  r := roam_enter('oba_market');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'far' and (r ->> 'wait_s')::numeric > 0, 'teleport to Oba Market: refused (far)');
  perform pg_temp.assert((select location_id from profiles where id = a) = 'national_museum', 'a refused enter does not move the player');
  -- the exact need: distance minus the slack at the maximum pace, never less than min_enter_s
  select x, y into ax, ay from locations where id = 'national_museum';
  select x, y into bx, b_y from locations where id = 'oba_market';
  d := sqrt((ax - bx) ^ 2 + (ay - b_y) ^ 2);
  need := greatest(bl_cfg('roam.min_enter_s'), greatest(0, d - bl_cfg('roam.door_slack_m')) / bl_cfg('roam.max_speed_mps'));
  perform pg_temp.assert(need between 8 and 9.5, 'the walk to Oba Market needs about 8.6 s at 6.5 m/s (got ' || round(need, 2) || ')');
  perform pg_temp.adv(need - 0.6);
  r := roam_enter('oba_market');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'far', 'just before the time: still refused');
  perform pg_temp.adv(1.2);
  r := roam_enter('oba_market');
  perform pg_temp.assert((r ->> 'ok')::boolean and r ->> 'location' = 'oba_market', 'just after the time: you walk in');
  perform pg_temp.assert((select location_id from profiles where id = a) = 'oba_market', 'the player is now at Oba Market');
  perform pg_temp.assert((select place from roam_sessions where user_id = a) = 'oba_market' and (select anchor_at from roam_sessions where user_id = a) = bl_now(), 'the session follows the player (new anchor)');
  -- a place outside the area is refused whatever the time
  r := roam_start('oba_market');
  perform pg_temp.adv(600);
  r := roam_enter('uniben');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'outside' and (select location_id from profiles where id = a) = 'oba_market', 'a place outside the area is refused');
  r := roam_enter('no_such_place');
  perform pg_temp.assert(not (r ->> 'ok')::boolean, 'an unknown place is refused');
  -- a neighbour needs at least min_enter_s
  perform pg_temp.setc('roam.min_enter_s', '3');
  perform pg_temp.setc('roam.door_slack_m', '100');
  r := roam_start('oba_market');
  r := roam_enter('oba_palace');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'far', 'even a near door needs the minimum time');
  perform pg_temp.adv(3.1);
  r := roam_enter('oba_palace');
  perform pg_temp.assert((r ->> 'ok')::boolean and (select location_id from profiles where id = a) = 'oba_palace', 'after the minimum time the near door opens');
  perform pg_temp.setc('roam.door_slack_m', '15');
  -- a faster player pace is a setting: 30 m/s makes the far trip near instant (but never below the minimum)
  perform pg_temp.setc('roam.max_speed_mps', '30');
  perform pg_temp.setc('roam.min_enter_s', '1.5');
  r := roam_start('oba_palace');
  perform pg_temp.adv(4);
  r := roam_enter('police_hq');
  perform pg_temp.assert((r ->> 'ok')::boolean, 'a higher max speed shortens the wait');
  perform pg_temp.setc('roam.max_speed_mps', '6.5');
  -- a slower pace needs longer
  perform pg_temp.setc('roam.max_speed_mps', '1');
  r := roam_start('police_hq');
  perform pg_temp.adv(10);
  r := roam_enter('national_museum');
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'far', 'a slower max speed needs more time');
  perform pg_temp.setc('roam.max_speed_mps', '6.5');
  -- busy / travelling / jailed players cannot walk in either
  r := roam_start('police_hq');
  perform pg_temp.adv(60);
  update profiles set busy_until = bl_now() + interval '60 seconds', busy_label = 'Cooking' where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_enter('national_museum')$q$) = 'busy', 'enter while busy is refused');
  update profiles set busy_until = null where id = a;
  update profiles set jailed_until = bl_now() + interval '60 seconds' where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_enter('national_museum')$q$) = 'jailed', 'enter while jailed is refused');
  update profiles set jailed_until = null where id = a;
end $$;

-- ---------- 4. rate limit ----------
do $$
declare a uuid := (select id from rm_u where name = 'a'); r jsonb; i int;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'national_museum');
  perform pg_temp.adv(5000);
  perform pg_temp.setc('roam.rate.max_calls', '4');
  perform pg_temp.setc('roam.rate.window_s', '60');
  r := roam_start('national_museum');                     -- call 1
  r := roam_enter('oba_market');                          -- call 2 (far, refused but counted)
  r := roam_enter('oba_market');                          -- call 3
  r := roam_enter('oba_market');                          -- call 4
  perform pg_temp.assert(r ->> 'hint' = 'far', 'calls 2 to 4 are refused as far');
  r := roam_enter('oba_market');                          -- call 5: over the limit
  perform pg_temp.assert(not (r ->> 'ok')::boolean and r ->> 'hint' = 'rate', 'the fifth call in the window is rate limited');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_start('national_museum')$q$) = 'rate', 'start is rate limited too');
  perform pg_temp.adv(61);
  r := roam_start('national_museum');
  perform pg_temp.assert((r ->> 'ok')::boolean, 'a new window: allowed again');
  perform pg_temp.assert((select win_n from roam_sessions where user_id = a) = 1, 'the counter restarted');
  perform pg_temp.setc('roam.rate.max_calls', '20');
end $$;

-- ---------- 5. switches ----------
do $$
declare a uuid := (select id from rm_u where name = 'a'); r jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'national_museum');
  r := roam_start('national_museum');
  perform pg_temp.setc('roam.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_start('national_museum')$q$) = 'off', 'master switch off: start refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_enter('national_museum')$q$) = 'off', 'master switch off: enter refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_leave()$q$) = 'ok', 'leaving still works with the switch off');
  perform pg_temp.assert((select location_id from profiles where id = a) = 'national_museum', 'nobody is moved or stuck when it is off');
  perform pg_temp.setc('roam.enabled', 'true');
  perform pg_temp.setc('roam.area.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_start('national_museum')$q$) = 'off', 'area switch off: start refused');
  perform pg_temp.setc('roam.area.enabled', 'true');
  r := roam_start('national_museum');
  perform pg_temp.assert((r ->> 'ok')::boolean, 'both on again: start works');
  -- shrinking the box takes places out of it
  perform pg_temp.setc('roam.area.x1', '470');
  perform pg_temp.assert(not bl_roam_in_area('ring_road_pos') and bl_roam_in_area('oba_market'), 'the box edge is a setting');
  perform pg_temp.setc('roam.area.x1', '610');
end $$;

-- ---------- 6. leave, session lifetime, other players ----------
do $$
declare a uuid := (select id from rm_u where name = 'a'); b uuid := (select id from rm_u where name = 'b'); r jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'national_museum');
  r := roam_start('national_museum');
  r := roam_leave();
  perform pg_temp.assert((r ->> 'ok')::boolean and not exists (select 1 from roam_sessions where user_id = a), 'leave removes the session');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_enter('oba_market')$q$) = 'no_session', 'enter after leave: no_session');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_leave()$q$) = 'ok', 'leaving twice is fine');
  -- the session expires
  r := roam_start('national_museum');
  perform pg_temp.setc('roam.session_ttl_s', '300');
  perform pg_temp.adv(301);
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_enter('national_museum')$q$) = 'no_session', 'an old session is refused');
  perform pg_temp.setc('roam.session_ttl_s', '7200');
  -- the player moved on by other means: the session is stale
  r := roam_start('national_museum');
  update profiles set location_id = 'oba_market' where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_enter('oba_palace')$q$) = 'no_session', 'a session from another place is stale');
  -- another player cannot use my session
  perform pg_temp.at(a, 'national_museum');
  r := roam_start('national_museum');
  perform pg_temp.login(b);
  perform pg_temp.at(b, 'national_museum');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_enter('national_museum')$q$) = 'no_session', 'player b has no session of his own');
  perform pg_temp.login(a);
  perform pg_temp.assert((select count(*) from roam_sessions) = 1, 'sessions are per player');
end $$;

-- ---------- 7. structure and grants ----------
do $$
begin
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.roam_sessions'::regclass), 'roam_sessions has RLS on');
  perform pg_temp.assert((select count(*) from pg_policies where tablename = 'roam_sessions') = 0, 'and no policies');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.roam_sessions', 'select') and not has_table_privilege('anon', 'public.roam_sessions', 'select'), 'no table grants');
  perform pg_temp.assert(not exists (select 1 from information_schema.columns where table_name = 'profiles' and column_name like 'roam%'), 'no roam column on profiles');
  perform pg_temp.assert(not exists (select 1 from pg_trigger where tgrelid = 'public.roam_sessions'::regclass and not tgisinternal), 'no triggers on roam_sessions');
  perform pg_temp.assert(not exists (select 1 from pg_constraint where conrelid = 'public.roam_sessions'::regclass and contype = 'f'), 'no foreign keys on roam_sessions');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.roam_start(text)', 'execute') and has_function_privilege('authenticated', 'public.roam_enter(text)', 'execute')
    and has_function_privilege('authenticated', 'public.roam_leave()', 'execute'), 'players can call the three RPCs');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.roam_start(text)', 'execute') and not has_function_privilege('anon', 'public.roam_enter(text)', 'execute')
    and not has_function_privilege('anon', 'public.roam_leave()', 'execute'), 'anon cannot');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_roam_gate()', 'execute') and not has_function_privilege('authenticated', 'public.bl_roam_in_area(text)', 'execute'), 'helpers are private');
  perform pg_temp.assert((select provolatile from pg_proc where oid = 'public.roam_start(text)'::regprocedure) = 'v'
    and (select provolatile from pg_proc where oid = 'public.roam_enter(text)'::regprocedure) = 'v', 'the RPCs that call bl_me() are volatile');
  raise notice 'ROAM TEST OK';
end $$;
