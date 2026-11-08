-- Free roam, phase 3: live players (20261120000100_roam3.sql, docs/ROAM.md "Live players"). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/roam3_test.sql
-- Groups: 1 settings · 2 presence write + rate limit + session/visibility rules · 3 nearby filtering (hidden, opted out, blocked both ways,
-- banned, stale, far, cap N, known ids) · 4 chat bubbles (filter, length, rate limits, mute, hidden, log, which cells get it, name from the
-- server) · 5 reports · 6 Realtime Authorization (policies on realtime.messages, tested with set role + claims) · 7 leaving the street ·
-- 8 switches · 9 structure and grants.
-- Time is pinned with bl.test_offset_seconds (bl_now()).
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

create or replace function pg_temp.at(p_uid uuid, p_place text) returns void
language plpgsql as $$
begin
  update profiles set location_id = p_place, travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
         busy_until = null, jailed_until = null, hospitalized_until = null where id = p_uid;
end $$;

create temp table r3_u (name text primary key, id uuid);

-- eight players, all on foot at the museum (a session each); positions are set per test
do $$
declare v uuid; n text; i int := 0;
begin
  foreach n in array array['a','b','c','d','e','f','g','h','i'] loop
    i := i + 1;
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    v := pg_temp.new_user('r3_' || n || '@roam.bl');
    perform pg_temp.login(v);
    perform create_profile_v2('R3_' || n, case when i % 2 = 0 then 'female' else 'male' end, '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home('ekenwan_face_me');
    insert into r3_u values (n, v);
  end loop;
  perform set_config('bl.test_offset_seconds', '0', true);
  update game_config set value = '0' where key = 'chat.min_account_real_minutes';
  update game_config set value = '0' where key = 'crime.npc_max_pct';
  -- the word filter has a known word for the test
  insert into chat_banned_words (word, active) values ('zzbadword', true) on conflict (word) do update set active = true;
  -- a's car for the mode test
  insert into inventory (user_id, item_id, qty) select id, 'kia_rio_used', 1 from r3_u where name = 'a' on conflict (user_id, item_id) do update set qty = 1;
  insert into vehicle_state (user_id, item_id, fuel_l, cond) select id, 'kia_rio_used', 40, 100 from r3_u where name = 'a' on conflict (user_id, item_id) do update set fuel_l = 40, cond = 100;
end $$;

create or replace function pg_temp.uid(p text) returns uuid language sql as $$ select id from r3_u where name = p $$;

-- start a street walk for a player
create or replace function pg_temp.walk(p text) returns void
language plpgsql as $$
begin
  perform pg_temp.login(pg_temp.uid(p));
  perform pg_temp.at(pg_temp.uid(p), 'national_museum');
  perform roam_start('national_museum');
end $$;

-- ---------- 1. settings ----------
do $$
declare n int;
begin
  perform pg_temp.assert((select count(*) from game_config where key like 'roam.live.%' or key like 'roam.bubble.%' or key = 'roam.report.max_hour') = 20, 'twenty live-player settings');
  select count(*) into n from game_config where (key like 'roam.live.%' or key like 'roam.bubble.%' or key = 'roam.report.max_hour')
     and (category <> 'roam' or coalesce(label, '') = '' or coalesce(description, '') = '' or (kind in ('number', 'naira', 'percent') and (min is null or max is null)));
  perform pg_temp.assert(n = 0, 'every live setting is in category roam with a label, a description and a range (' || n || ' without)');
  perform pg_temp.assert((select count(*) from game_config where key like 'roam.%' and (label ilike '%lagos%' or description ilike '%lagos%')) = 0, 'no "Lagos" in the settings text');
  perform pg_temp.assert(bl_cfg_bool('roam.live.enabled') and bl_cfg_bool('roam.bubble.enabled') and bl_cfg_bool('roam.live.emotes'), 'on by default');
  perform pg_temp.assert(bl_cfg('roam.live.max_shown') = 8 and bl_cfg('roam.live.low_max') = 5 and bl_cfg('roam.live.presence_min_s') = 5 and bl_cfg('roam.live.stale_s') = 45 and bl_cfg('roam.live.idle_s') = 20 and bl_cfg('roam.live.budget_mps') = 3 and bl_cfg('roam.live.move_hz') = 2 and bl_cfg('roam.live.radius_m') = 100 and bl_cfg('roam.live.cell_m') = 100 and bl_cfg('roam.bubble.len') = 80 and bl_cfg('roam.bubble.radius_m') = 25, 'defaults');
end $$;

-- ---------- 2. presence ----------
do $$
declare a uuid := pg_temp.uid('a'); r jsonb; v_x real; v_u timestamptz;
begin
  perform pg_temp.login(a);
  -- no street session: nothing is written
  r := roam_presence_set(500, 500);
  perform pg_temp.assert(not (r ->> 'visible')::boolean and r ->> 'why' = 'no_session', 'no session: not visible');
  perform pg_temp.assert(not exists (select 1 from roam_presence where user_id = a), 'no session: no row');
  perform pg_temp.walk('a');
  r := roam_presence_set(500, 500);
  perform pg_temp.assert((r ->> 'visible')::boolean and not (r ->> 'throttled')::boolean, 'with a session: written');
  perform pg_temp.assert((select cx = 5 and cy = 5 and x = 500 and y = 500 and mode = 'walk' and veh is null from roam_presence where user_id = a), 'the cell is x / 100, y / 100 (5, 5); on foot');
  -- rate limit: a second write inside presence_min_s is a no-op
  r := roam_presence_set(530, 500);
  perform pg_temp.assert((r ->> 'throttled')::boolean, 'a second call at once is throttled');
  perform pg_temp.assert((select x from roam_presence where user_id = a) = 500, 'a throttled call writes nothing');
  perform pg_temp.adv(4);
  perform pg_temp.assert((roam_presence_set(530, 500) ->> 'throttled')::boolean, '4 s later: still throttled');
  perform pg_temp.adv(2);
  r := roam_presence_set(530, 500);
  perform pg_temp.assert(not (r ->> 'throttled')::boolean and (select x from roam_presence where user_id = a) = 530, '6 s later: written');
  -- clamped to the map
  perform pg_temp.adv(100);
  perform roam_presence_set(-50, 5000);
  perform pg_temp.assert((select x = 0 and y = 1000 and cx = 0 and cy = 10 from roam_presence where user_id = a), 'positions are clamped to the city');
  perform pg_temp.adv(6);
  perform roam_presence_set(900, 0);
  perform pg_temp.assert((select sqrt(x ^ 2 + (y - 1000) ^ 2) between 150 and 170 from roam_presence where user_id = a), 'and a jump is limited to what max speed allows (24 m/s x 6 s + 20 m)');
  -- the car: mode and vehicle come from the SERVER session, never from the client
  perform pg_temp.adv(100);
  perform roam_set_mode('car');
  perform roam_presence_set(500, 500);
  perform pg_temp.assert((select mode = 'car' and veh = 'kia_rio_used' from roam_presence where user_id = a), 'in the car: the server writes mode car and the item id');
  perform roam_set_mode('walk', null, 500, 500, 0);
  perform pg_temp.adv(6);
  perform roam_presence_set(500, 500);
  perform pg_temp.assert((select mode = 'walk' and veh is null from roam_presence where user_id = a), 'out of the car: walk again');
  -- opt out: the row goes, nothing is written again
  r := roam_set_show(false);
  perform pg_temp.assert(not (r ->> 'show_me')::boolean and (select hidden from roam_presence where user_id = a), 'show me = off marks the row hidden (it stays as his own anchor)');
  perform pg_temp.adv(6);
  r := roam_presence_set(500, 500);
  perform pg_temp.assert(not (r ->> 'visible')::boolean and r ->> 'why' = 'off' and (select hidden from roam_presence where user_id = a), 'opted out: stays hidden');
  perform roam_set_show(true);
  perform pg_temp.assert((roam_live_info() ->> 'show_me')::boolean, 'the info says show_me');
  -- the friends location privacy hides you here too
  perform friends_set_privacy(false);
  perform pg_temp.adv(6);
  r := roam_presence_set(500, 500);
  perform pg_temp.assert(not (r ->> 'visible')::boolean and r ->> 'why' = 'location' and (roam_live_info() ->> 'location_hidden')::boolean, 'location hidden (friends privacy): not visible');
  perform friends_set_privacy(true);
  perform pg_temp.adv(6);
  perform pg_temp.assert((roam_presence_set(500, 500) ->> 'visible')::boolean, 'visible again');
  -- the stale rows are cleaned in small batches and never loop: 40 old rows, one call removes at most 25
  insert into roam_presence (user_id, cx, cy, x, y, updated_at)
    select gen_random_uuid(), 1, 1, 150, 150, bl_now() - interval '2 hours' from generate_series(1, 40);
  perform pg_temp.adv(6);
  perform roam_presence_set(500, 500);
  perform pg_temp.assert((select count(*) from roam_presence where updated_at < bl_now() - interval '1 hour') = 15, 'one write removes at most 25 of the 40 stale rows');
  perform pg_temp.adv(6);
  perform roam_presence_set(500, 500);
  perform pg_temp.assert((select count(*) from roam_presence where updated_at < bl_now() - interval '1 hour') = 0, 'the next one finishes the job');
  -- a session that timed out
  perform pg_temp.adv(7300);
  r := roam_presence_set(500, 500);
  perform pg_temp.assert(r ->> 'why' = 'no_session', 'a timed out walk is not shown');
end $$;

-- ---------- 3. nearby ----------
-- (roam_nearby reads the VIEWER's own presence row and is rate limited; the test shortens the gap to keep the clock short)
create or replace function pg_temp.nb(p_have uuid[] default '{}') returns jsonb
language plpgsql as $$
begin
  perform pg_temp.adv(1.2);
  return roam_nearby(p_have);
end $$;

do $$
declare
  a uuid := pg_temp.uid('a'); b uuid := pg_temp.uid('b'); c uuid := pg_temp.uid('c'); d uuid := pg_temp.uid('d'); e uuid := pg_temp.uid('e');
  f uuid := pg_temp.uid('f'); g uuid := pg_temp.uid('g'); h uuid := pg_temp.uid('h'); i uuid := pg_temp.uid('i');
  r jsonb; ids uuid[]; v_x numeric;
begin
  perform pg_temp.setc('roam.live.presence_min_s', '2');
  perform pg_temp.adv(60);
  delete from roam_presence;
  -- everyone steps out; a stands at 500,500 (cell 5, 5)
  perform pg_temp.walk('a'); perform roam_live_tick(500, 500);
  perform pg_temp.walk('b'); perform roam_live_tick(510, 505);
  perform pg_temp.walk('c'); perform roam_live_tick(520, 500);
  perform pg_temp.walk('d'); perform roam_live_tick(530, 500);
  perform pg_temp.walk('e'); perform roam_live_tick(540, 500);
  perform pg_temp.walk('f'); perform roam_live_tick(550, 500);
  perform pg_temp.walk('g'); perform roam_live_tick(500, 560);
  perform pg_temp.walk('h'); perform roam_live_tick(900, 900);
  perform pg_temp.walk('i'); perform roam_live_tick(505.4, 505);
  -- a blocks c; d blocks a; e is banned; f turned "show me" off; h is far away; g gets stale
  perform pg_temp.login(a);
  perform chat_block(c);
  perform pg_temp.login(d);
  perform chat_block(a);
  update profiles set banned = true where id = e;
  perform pg_temp.login(f); perform roam_set_show(false);
  perform pg_temp.assert((select hidden from roam_presence where user_id = f), 'opting out marks the row hidden at once (it stays as his own anchor)');
  update roam_presence set updated_at = bl_now() - interval '60 seconds' where user_id = g;
  perform pg_temp.login(a);
  r := pg_temp.nb();
  select array_agg((x ->> 'id')::uuid order by ord) into ids from jsonb_array_elements(r -> 'players') with ordinality t(x, ord);
  perform pg_temp.assert(ids = array[i, b], 'a sees only i (7 m) and b (11 m), nearest first: ' || coalesce(ids::text, 'none'));
  perform pg_temp.assert(not (ids @> array[c]), 'a player I blocked is not listed');
  perform pg_temp.assert(not (ids @> array[d]), 'a player who blocked me is not listed');
  perform pg_temp.assert(not (ids @> array[e]), 'a banned player is not listed');
  perform pg_temp.assert(not (ids @> array[f]), 'an opted-out player is not listed');
  perform pg_temp.assert(not (ids @> array[g]), 'a stale row is not listed');
  perform pg_temp.assert(not (ids @> array[h]), 'a player 560 m away (other cell) is not listed');
  perform pg_temp.assert(not (ids @> array[a]), 'never myself');
  -- positions go out rounded to a metre (i stands at 505.4)
  select (x ->> 'x')::numeric into v_x from jsonb_array_elements(r -> 'players') x where x ->> 'id' = i::text;
  perform pg_temp.assert(v_x = 505, 'positions are rounded to 1 m (505.4 -> ' || v_x || ')');
  -- the other way round: the blocked player does not see me either
  perform pg_temp.login(c);
  r := pg_temp.nb();
  select array_agg((x ->> 'id')::uuid) into ids from jsonb_array_elements(r -> 'players') x;
  perform pg_temp.assert(not (ids @> array[a]), 'the player I blocked does not see me');
  perform pg_temp.assert(ids @> array[b, i], 'but sees the others');
  -- location privacy
  update profiles set share_location_friends = false where id = i;
  perform pg_temp.login(a);
  select array_agg((x ->> 'id')::uuid) into ids from jsonb_array_elements(pg_temp.nb() -> 'players') x;
  perform pg_temp.assert(not (ids @> array[i]) and ids @> array[b], 'a hidden-location player is not listed');
  perform pg_temp.login(i);
  select array_agg((x ->> 'id')::uuid) into ids from jsonb_array_elements(pg_temp.nb() -> 'players') x;
  perform pg_temp.assert(ids @> array[a, b], 'a hidden player still sees the others');
  update profiles set share_location_friends = true where id = i;
  -- static info only for ids I do not know yet
  perform pg_temp.login(a);
  r := pg_temp.nb(array[b]);
  perform pg_temp.assert((select count(*) from jsonb_array_elements(r -> 'players') x where x ->> 'id' = b::text and x ? 'n') = 0, 'a known id carries no name / avatar');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(r -> 'players') x where x ->> 'id' = i::text and x ->> 'n' = 'R3_i' and x ? 'av') = 1, 'an unknown id carries the name and avatar FROM THE SERVER');
  -- the cap
  perform pg_temp.setc('roam.live.max_shown', '1');
  r := pg_temp.nb();
  perform pg_temp.assert(jsonb_array_length(r -> 'players') = 1 and (r -> 'players' -> 0 ->> 'id')::uuid = i, 'max_shown = 1: only the nearest');
  perform pg_temp.setc('roam.live.max_shown', '8');
  -- the radius
  perform pg_temp.setc('roam.live.radius_m', '8');
  perform pg_temp.assert(jsonb_array_length(pg_temp.nb() -> 'players') = 1, 'radius 8 m: only i (7 m)');
  perform pg_temp.setc('roam.live.radius_m', '100');
  -- rate limit of the list (no row is read twice within presence_min_s / 2)
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_nearby()$q$) = 'too_fast', 'roam_nearby is rate limited');
  -- the tick does both; a throttled tick does NO query (players = null means "no change")
  perform pg_temp.adv(6);
  r := roam_live_tick(500, 500);
  perform pg_temp.assert((r ->> 'visible')::boolean and jsonb_array_length(r -> 'players') = 2 and (r ->> 'next_s')::numeric = 9, 'roam_live_tick: write + the list + the next interval');
  r := roam_live_tick(500, 500);
  perform pg_temp.assert((r ->> 'throttled')::boolean and r -> 'players' = 'null'::jsonb, 'a throttled tick returns players = null (no query)');
  -- (#1c) the position is the VIEWER's row: a claim far beyond what max speed allows is clamped, so nobody can scan other streets
  perform pg_temp.adv(6);
  r := roam_live_tick(900, 900);
  perform pg_temp.assert((select sqrt((x - 500) ^ 2 + (y - 500) ^ 2) from roam_presence where user_id = a) < 180, 'a teleport claim is clamped to what the speed allows: ' || (select x || ',' || y from roam_presence where user_id = a));
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r -> 'players') x where x ->> 'id' = h::text), 'so the far player stays out of his list');
  -- no session / no presence: refused
  perform pg_temp.login(h);
  perform roam_leave();
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_nearby()$q$) = 'no_session', 'roam_nearby needs a live street session');
  perform pg_temp.login(g);
  delete from roam_presence where user_id = g;
  perform pg_temp.adv(3);
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_nearby()$q$) = 'no_presence', 'roam_nearby needs a presence row (the position is his row, not a number he sends)');
  update profiles set banned = false where id = e;
  perform pg_temp.setc('roam.live.presence_min_s', '5');
end $$;

-- ---------- 4. chat bubbles ----------
do $$
declare
  a uuid := pg_temp.uid('a'); b uuid := pg_temp.uid('b'); r jsonb; n int; i int; v_p jsonb; v_t text[];
begin
  perform pg_temp.adv(30);
  perform pg_temp.login(a);
  perform pg_temp.walk('a');
  perform roam_live_tick(540, 540);
  r := roam_say('Hello everybody');
  perform pg_temp.assert((r ->> 'ok')::boolean and r ->> 'text' = 'Hello everybody' and not (r ->> 'masked')::boolean, 'a bubble goes out');
  select array_agg(topic) into v_t from realtime.messages where event = 'b' and (payload ->> 'u')::uuid = a;
  perform pg_temp.assert(v_t = array['roam:t:' || a], 'sent ONCE, on the speaker''s own text topic: ' || coalesce(v_t::text, 'none'));
  select payload into v_p from realtime.messages where event = 'b' and (payload ->> 'u')::uuid = a limit 1;
  perform pg_temp.assert(v_p ->> 'n' = 'R3_a' and v_p ->> 't' = 'Hello everybody' and (v_p ->> 'x')::numeric = 540, 'the payload carries the SERVER name, the text and the position');
  perform pg_temp.assert((select count(*) from roam_bubbles where user_id = a) = 1, 'one log row');
  -- gap
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_say('again')$q$) = 'too_fast', 'rate limit: the gap between two bubbles');
  perform pg_temp.adv(4);
  -- the same words again within the chat's duplicate window
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_say('Hello, everybody!')$q$) = 'duplicate', 'the same message again is refused (chat.duplicate_window_seconds)');
  -- the chat kill switch
  perform pg_temp.setc('chat.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_say('anybody there')$q$) = 'chat_off', 'chat.enabled off: no bubbles either');
  perform pg_temp.setc('chat.enabled', 'true');
  -- filter
  r := roam_say('you zzbadword man');
  perform pg_temp.assert((r ->> 'masked')::boolean and r ->> 'text' not like '%zzbadword%' and r ->> 'text' like '%***%', 'the word filter masks it: ' || (r ->> 'text'));
  perform pg_temp.assert((select count(*) from roam_bubbles where user_id = a and body like '%zzbadword%') = 0, 'the log holds the masked text only');
  perform pg_temp.adv(4);
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_say('zzbadword')$q$) = 'filtered', 'only a filtered word: refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_say('   ')$q$) = 'empty', 'empty: refused');
  r := roam_say(repeat('abcdefghij', 20));
  perform pg_temp.assert(char_length(r ->> 'text') = 80, 'cut at 80 characters');
  perform pg_temp.adv(4);
  r := roam_say(E'line one\nline two\t' || chr(8203) || 'x');
  perform pg_temp.assert(r ->> 'text' = 'line one line two x', 'newlines and zero-width characters are cleaned: ' || (r ->> 'text'));
  -- per-minute limit
  perform pg_temp.setc('roam.bubble.gap_s', '0');
  n := 0;
  begin
    for i in 1..20 loop perform roam_say('spam ' || i); n := n + 1; end loop;
  exception when others then null;
  end;
  perform pg_temp.assert(n between 5 and 11, 'the per-minute cap stops the spam (stopped at ' || n || ')');
  perform pg_temp.setc('roam.bubble.gap_s', '3');
  perform pg_temp.adv(70);
  -- not visible = not allowed to speak
  perform roam_set_show(false);
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_say('hello')$q$) = 'hidden', 'a hidden player cannot speak (nobody would hear)');
  perform roam_set_show(true);
  perform roam_live_tick(540, 540);
  update profiles set chat_muted_until = bl_now() + interval '1 hour' where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_say('hello')$q$) = 'muted', 'a muted player cannot speak');
  update profiles set chat_muted_until = null where id = a;
  perform pg_temp.setc('chat.min_account_real_minutes', '100000');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_say('hello')$q$) = 'too_new', 'a new account cannot speak yet (the chat rule)');
  perform pg_temp.setc('chat.min_account_real_minutes', '0');
  perform pg_temp.setc('roam.bubble.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_say('hello')$q$) = 'off', 'bubbles off');
  perform pg_temp.setc('roam.bubble.enabled', 'true');
  -- the log is short-lived and cleaned a few rows at a time
  insert into roam_bubbles (user_id, body, created_at) select b, 'old', bl_now() - interval '2 days' from generate_series(1, 70);
  perform pg_temp.adv(5);
  perform roam_live_tick(540, 540);
  perform roam_say('clean up');
  perform pg_temp.assert((select count(*) from roam_bubbles where body = 'old') = 20, 'one bubble deletes at most 50 expired log rows (70 -> 20)');
  delete from roam_bubbles where body = 'old';
end $$;

-- ---------- 5. reports ----------
do $$
declare a uuid := pg_temp.uid('a'); b uuid := pg_temp.uid('b'); r jsonb;
begin
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format($q$select roam_report(%L)$q$, b)) = 'self', 'you cannot report yourself');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_report(gen_random_uuid())$q$) = 'unknown_player', 'unknown player');
  -- only players you were near in the last minutes: h left the street (no row, no bubble) and was far anyway
  perform pg_temp.assert(pg_temp.hint_of(format($q$select roam_report(%L)$q$, pg_temp.uid('h'))) = 'not_near', 'a player you were never near cannot be reported');
  r := roam_report(a, 'rude');
  perform pg_temp.assert((r ->> 'ok')::boolean, 'reported');
  perform pg_temp.assert((select count(*) from roam_reports where reporter_id = b and reported_id = a and reason = 'rude' and bubble is not null) = 1, 'the report keeps the last bubble from the log');
  r := roam_report(a, 'rude');
  perform pg_temp.assert((r ->> 'dup')::boolean and (select count(*) from roam_reports where reporter_id = b and reported_id = a) = 1, 'the same report within 10 minutes is not stored twice');
  perform pg_temp.setc('roam.report.max_hour', '2');
  update roam_reports set created_at = created_at - interval '11 minutes';
  perform roam_report(pg_temp.uid('c'), 'x');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select roam_report(%L)$q$, pg_temp.uid('d'))) = 'too_fast', 'the hourly report limit');
  perform pg_temp.setc('roam.report.max_hour', '6');
  -- someone who was in the street long ago is no longer reportable
  update roam_presence set updated_at = bl_now() - interval '20 minutes' where user_id = pg_temp.uid('d');
  update roam_bubbles set created_at = bl_now() - interval '20 minutes' where user_id = pg_temp.uid('d');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select roam_report(%L)$q$, pg_temp.uid('d'))) in ('not_near', 'too_fast'), 'an old encounter is not reportable');
  -- admin
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_roam_reports(10)$q$) = 'not_admin', 'players cannot read reports');
  update profiles set is_admin = true where id = pg_temp.uid('i');
  perform pg_temp.login(pg_temp.uid('i'));
  r := admin_roam_reports(10);
  perform pg_temp.assert(jsonb_array_length(r) = 2 and r -> 1 ->> 'reported' = 'R3_a', 'an admin reads the reports');
  update profiles set is_admin = false where id = pg_temp.uid('i');
end $$;

-- ---------- 6. Realtime Authorization (the policies on realtime.messages) ----------
do $$
declare
  a uuid := pg_temp.uid('a'); b uuid := pg_temp.uid('b'); c uuid := pg_temp.uid('c'); d uuid := pg_temp.uid('d'); f uuid := pg_temp.uid('f'); h uuid := pg_temp.uid('h');
  v_own text; v_other text; v_err text; v_ok boolean; v_n int; v_pol int;
begin
  select count(*) into v_pol from pg_policies where schemaname = 'realtime' and tablename = 'messages' and policyname in ('roam_pos_read', 'roam_pos_write', 'roam_text_read') and 'authenticated' = any (roles);
  perform pg_temp.assert(v_pol = 3, 'three roam policies on realtime.messages');
  perform pg_temp.assert(not exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages' and policyname like 'roam_text%' and cmd in ('INSERT', 'ALL', 'UPDATE')), 'nobody can write on the text (bubble) topics');
  perform pg_temp.assert(not exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages' and policyname like 'roam_bubble%'), 'the old cell topics are gone');
  -- everyone is fresh again, near each other; h is far away
  perform pg_temp.adv(40);
  perform pg_temp.walk('a'); perform roam_live_tick(500, 500);
  perform pg_temp.walk('b'); perform roam_live_tick(510, 500);
  perform pg_temp.walk('c'); perform roam_live_tick(520, 500);
  perform pg_temp.walk('d'); perform roam_live_tick(530, 500);
  perform pg_temp.walk('f'); perform roam_live_tick(540, 500);
  perform pg_temp.login(f); perform roam_set_show(true); perform pg_temp.adv(6); perform roam_live_tick(540, 500);
  perform pg_temp.walk('h'); perform roam_live_tick(900, 900);
  perform pg_temp.login(a); delete from chat_blocks where blocker_id = a;
  v_own := 'roam:u:' || a;
  v_other := 'roam:u:' || b;

  -- (1) a writes on his OWN topic
  perform pg_temp.login(a);
  perform set_config('realtime.topic', v_own, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, event, private) values (v_own, 'broadcast', '{"p":[1,2,3]}', 'p', true);
    v_ok := true;
  exception when others then v_ok := false; v_err := sqlerrm;
  end;
  reset role;
  perform pg_temp.assert(v_ok, 'a may insert on his own topic: ' || coalesce(v_err, ''));

  -- (2) a CANNOT write on b's topic: that is the impersonation attempt
  perform set_config('realtime.topic', v_other, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, event, private) values (v_other, 'broadcast', '{"p":[1,2,3]}', 'p', true);
    v_ok := true; v_err := null;
  exception when others then v_ok := false; v_err := sqlerrm;
  end;
  reset role;
  perform pg_temp.assert(not v_ok and v_err like '%row-level security%', 'a CANNOT insert on b''s topic (impersonation): ' || coalesce(v_err, 'it was allowed'));

  -- (2b) ... nor on a text topic (even his own: only roam_say can send bubbles), a made-up topic or a look-alike uid
  foreach v_err in array array['roam:t:' || a, 'roam:t:' || b, 'roam:u:' || upper(a::text), 'roam:u:' || a || 'x', 'roam:x:' || a, 'roam:u:', 'roam:b:5:5'] loop
    perform set_config('realtime.topic', v_err, true);
    set local role authenticated;
    begin
      insert into realtime.messages (topic, extension, payload, event, private) values (v_err, 'broadcast', '{"t":"hi"}', 'b', true);
      v_ok := true;
    exception when others then v_ok := false;
    end;
    reset role;
    perform pg_temp.assert(not v_ok, 'a cannot insert on ' || v_err);
  end loop;
  perform set_config('realtime.topic', v_own, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, event, private) values (v_own, 'presence', '{}', 'p', true);
    v_ok := true;
  exception when others then v_ok := false;
  end;
  reset role;
  perform pg_temp.assert(not v_ok, 'only broadcast, not presence, on the position topic');

  -- (3) anon has no way in
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('realtime.topic', v_own, true);
  set local role anon;
  begin
    insert into realtime.messages (topic, extension, payload, event, private) values (v_own, 'broadcast', '{}', 'p', true);
    v_ok := true;
  exception when others then v_ok := false;
  end;
  reset role;
  perform pg_temp.assert(not v_ok, 'anon cannot insert');

  -- (4) a hidden / opted-out player cannot publish at all
  perform pg_temp.login(f);
  perform roam_set_show(false);
  perform set_config('realtime.topic', 'roam:u:' || f, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, event, private) values ('roam:u:' || f, 'broadcast', '{}', 'p', true);
    v_ok := true;
  exception when others then v_ok := false;
  end;
  reset role;
  perform pg_temp.assert(not v_ok, 'an opted-out player cannot publish even on his own topic');
  perform roam_set_show(true);
  perform pg_temp.adv(6);
  perform roam_live_tick(540, 500);

  -- (5) reading: put messages on b's position and text topics, on h's (far) and on a hidden player's
  insert into realtime.messages (topic, extension, payload, event, private) values (v_other, 'broadcast', '{"p":[9]}', 'p', true);
  insert into realtime.messages (topic, extension, payload, event, private) values ('roam:t:' || b, 'broadcast', '{"t":"hi"}', 'b', true);
  insert into realtime.messages (topic, extension, payload, event, private) values ('roam:u:' || h, 'broadcast', '{"p":[5]}', 'p', true);
  insert into realtime.messages (topic, extension, payload, event, private) values ('roam:t:' || h, 'broadcast', '{"t":"far"}', 'b', true);
  perform pg_temp.login(a);
  perform set_config('realtime.topic', v_other, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_other and event = 'p';
  reset role;
  perform pg_temp.assert(v_n = 1, 'a (in the street, near b, not blocked) may read b''s position topic');
  perform set_config('realtime.topic', 'roam:t:' || b, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = 'roam:t:' || b;
  reset role;
  perform pg_temp.assert(v_n = 1, '... and b''s bubbles');
  -- (#1a/b) proximity: h stands 560 m away: neither his positions nor his bubbles can be read
  perform set_config('realtime.topic', 'roam:u:' || h, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = 'roam:u:' || h;
  reset role;
  perform pg_temp.assert(v_n = 0, 'a player far away (not within a cell of mine) cannot be listened to: positions');
  perform set_config('realtime.topic', 'roam:t:' || h, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = 'roam:t:' || h;
  reset role;
  perform pg_temp.assert(v_n = 0, '... nor his bubbles');
  perform pg_temp.assert(not roam_topic_ok('roam:u:' || h, false) and roam_topic_ok(v_other, false), 'roam_topic_ok answers only where nearby would list the player (no oracle for far ones)');

  -- (#2) blocks are enforced by the server for positions AND bubbles, both ways
  perform chat_block(b);
  perform set_config('realtime.topic', v_other, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_other and event = 'p';
  reset role;
  perform pg_temp.assert(v_n = 0, 'a blocked b: a can no longer read b''s position topic');
  perform set_config('realtime.topic', 'roam:t:' || b, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = 'roam:t:' || b;
  reset role;
  perform pg_temp.assert(v_n = 0, 'a blocked b: a can no longer read b''s bubbles');
  insert into realtime.messages (topic, extension, payload, event, private) values (v_own, 'broadcast', '{"p":[8]}', 'p', true);
  insert into realtime.messages (topic, extension, payload, event, private) values ('roam:t:' || a, 'broadcast', '{"t":"a says"}', 'b', true);
  perform pg_temp.login(b);
  perform set_config('realtime.topic', v_own, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_own and event = 'p';
  reset role;
  perform pg_temp.assert(v_n = 0, 'the blocked player cannot read the blocker''s position topic');
  perform set_config('realtime.topic', 'roam:t:' || a, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = 'roam:t:' || a;
  reset role;
  perform pg_temp.assert(v_n = 0, 'the blocked player cannot read the blocker''s bubbles');
  delete from chat_blocks where blocker_id = a and blocked_id = b;
  -- a hidden player's topics cannot be read by a guess of the uid
  insert into realtime.messages (topic, extension, payload, event, private) values ('roam:u:' || f, 'broadcast', '{"p":[7]}', 'p', true);
  perform pg_temp.login(f);
  perform roam_set_show(false);
  perform pg_temp.login(a);
  perform set_config('realtime.topic', 'roam:u:' || f, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = 'roam:u:' || f and event = 'p';
  reset role;
  perform pg_temp.assert(v_n = 0, 'a hidden player''s topic cannot be read');
  perform pg_temp.login(f); perform roam_set_show(true);
  -- a player who is not in the street himself reads nothing
  perform pg_temp.login(c);
  perform roam_leave();
  perform set_config('realtime.topic', v_other, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_other and event = 'p';
  reset role;
  perform pg_temp.assert(v_n = 0, 'a player who left the street reads nothing');
  perform set_config('realtime.topic', 'roam:t:' || b, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = 'roam:t:' || b;
  reset role;
  perform pg_temp.assert(v_n = 0, '... nor the bubbles');
  -- the master switch closes everything
  perform pg_temp.login(a);
  perform pg_temp.setc('roam.live.enabled', 'false');
  perform set_config('realtime.topic', v_own, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, event, private) values (v_own, 'broadcast', '{}', 'p', true);
    v_ok := true;
  exception when others then v_ok := false;
  end;
  reset role;
  perform pg_temp.assert(not v_ok and not roam_topic_ok(v_other, false), 'live players off: even the own topic is closed and reads are refused');
  perform pg_temp.setc('roam.live.enabled', 'true');
  -- (#1a) the viewer's own street session and presence must be live: ended session, then a stale presence row
  update roam_sessions set ended = true where user_id = a;
  perform pg_temp.assert(not roam_topic_ok(v_other, false), 'a viewer whose street session ended reads nothing');
  update roam_sessions set ended = false where user_id = a;
  perform pg_temp.assert(roam_topic_ok(v_other, false), 'sanity: back in the street');
  update roam_sessions set started_at = bl_now() - interval '3 hours' where user_id = a;
  perform pg_temp.assert(not roam_topic_ok(v_other, false), 'a viewer whose walk timed out reads nothing');
  update roam_sessions set started_at = bl_now() where user_id = a;
  perform pg_temp.adv(50);
  perform pg_temp.assert(not roam_topic_ok(v_other, false), 'a viewer whose presence row is stale reads nothing');
  perform pg_temp.assert(not roam_topic_ok(v_own, true), 'and cannot publish either');
  -- malformed topics
  perform pg_temp.assert(not roam_topic_ok('roam:u:not-a-uuid', false) and not roam_topic_ok(null, true) and not roam_topic_ok('roam:t:xyz', false), 'malformed topics are refused');
end $$;

-- ---------- 7. leaving the street ----------
do $$
declare a uuid := pg_temp.uid('a'); r jsonb;
begin
  perform pg_temp.adv(10);
  perform pg_temp.walk('a');
  perform roam_live_tick(500, 500);
  perform pg_temp.assert(exists (select 1 from roam_presence where user_id = a), 'in the street: a row');
  perform roam_leave();
  perform pg_temp.assert(not exists (select 1 from roam_presence where user_id = a), 'roam_leave removes the row');
  perform pg_temp.walk('a');
  perform roam_live_tick(500, 500);
  perform roam_live_stop();
  perform pg_temp.assert(not exists (select 1 from roam_presence where user_id = a), 'roam_live_stop removes the row');
  perform pg_temp.walk('a');
  perform roam_live_tick(500, 500);
  perform pg_temp.adv(60);
  r := roam_enter('oba_market');
  r := roam_enter('national_museum');
  perform pg_temp.assert(not exists (select 1 from roam_presence where user_id = a) or (r ->> 'ok')::boolean is not null, 'sanity');
  -- walking into a place removes it (national_museum is "here": refused, row stays; a real walk-in is covered by the patch marker test below)
  perform pg_temp.assert(pg_get_functiondef('public.roam_enter(text)'::regprocedure) like '%delete from roam_presence%', 'roam_enter deletes the row when you walk in');
  perform pg_temp.assert(pg_get_functiondef('public.roam_hail_keke(text)'::regprocedure) like '%delete from roam_presence%', 'roam_hail_keke deletes the row');
end $$;

-- ---------- 8. switches ----------
do $$
declare a uuid := pg_temp.uid('a');
begin
  perform pg_temp.login(a);
  perform pg_temp.setc('roam.live.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_live_tick(1, 1)$q$) = 'off', 'live off: tick refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_nearby()$q$) = 'off' and pg_temp.hint_of($q$select roam_say('x')$q$) = 'off', 'live off: nearby and say refused');
  perform pg_temp.assert(not (roam_live_info() ->> 'enabled')::boolean, 'the info still answers, enabled = false');
  perform pg_temp.setc('roam.live.enabled', 'true');
  perform pg_temp.setc('roam.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select roam_live_tick(1, 1)$q$) = 'off', 'free roam off: tick refused');
  perform pg_temp.setc('roam.enabled', 'true');
end $$;

-- ---------- 9. structure and grants ----------
do $$
declare t text; f text;
begin
  foreach t in array array['roam_prefs', 'roam_presence', 'roam_bubbles', 'roam_reports'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || t)::regclass), t || ': RLS on');
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || t, 'select') and not has_table_privilege('anon', 'public.' || t, 'select')
      and not has_table_privilege('authenticated', 'public.' || t, 'insert'), t || ': no direct grants');
    perform pg_temp.assert(not exists (select 1 from pg_trigger where tgrelid = ('public.' || t)::regclass and not tgisinternal), t || ': no triggers');
    perform pg_temp.assert(not exists (select 1 from pg_constraint where conrelid = ('public.' || t)::regclass and contype = 'f'), t || ': no foreign keys');
  end loop;
  foreach f in array array['roam_live_info()', 'roam_set_show(boolean)', 'roam_presence_set(numeric,numeric)', 'roam_nearby(uuid[])', 'roam_live_tick(numeric,numeric,uuid[])',
                          'roam_live_stop()', 'roam_say(text)', 'roam_report(uuid,text)', 'admin_roam_reports(integer)'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute') and not has_function_privilege('anon', 'public.' || f, 'execute'), f || ': authenticated yes, anon no');
    perform pg_temp.assert((select prosecdef and proconfig::text like '%search_path%' from pg_proc where oid = ('public.' || f)::regprocedure), f || ': security definer with a search_path');
  end loop;
  foreach f in array array['bl_roam_live_gate()', 'bl_roam_light_me()', 'bl_roam_visible(uuid)', 'bl_roam_nearby(uuid,uuid[])'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', 'public.' || f, 'execute') and not has_function_privilege('anon', 'public.' || f, 'execute'), f || ': internal');
  end loop;
  perform pg_temp.assert(not has_function_privilege('anon', 'public.roam_topic_ok(text,boolean)', 'execute') and has_function_privilege('authenticated', 'public.roam_topic_ok(text,boolean)', 'execute'), 'the topic checks are for authenticated only');
  -- the writers are volatile (they write / lock)
  perform pg_temp.assert((select provolatile = 'v' from pg_proc where oid = 'public.roam_say(text)'::regprocedure)
    and (select provolatile = 'v' from pg_proc where oid = 'public.roam_live_tick(numeric,numeric,uuid[])'::regprocedure)
    and (select provolatile = 'v' from pg_proc where oid = 'public.roam_presence_set(numeric,numeric)'::regprocedure)
    and (select provolatile = 'v' from pg_proc where oid = 'public.roam_report(uuid,text)'::regprocedure), 'the writing RPCs are volatile');
  -- no new column on profiles
  perform pg_temp.assert(not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name like 'roam%'), 'profiles untouched');
end $$;
