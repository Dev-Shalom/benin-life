-- D2 Link-ups (20261012001700_linkups.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/linkups_test.sql
-- Time moves with bl.test_offset_seconds; rolls are pinned with bl.test_rand (bl_rand).
-- Groups: 1 grants / anon / helpers private / no player targets · 2 prices + config + adult NPCs · 3 preference + who is out
-- · 4 Buy drinks: refusals, charge + ledger, timer, can't stop, roll no / yes, cooldown, attraction charm · 5 dinner + hotel
-- need a yes, effects, spark · 6 morning after: cash missing (share, cap, ledger) or fine · 7 weekend getaway needs Big Boy,
-- hype · 8 relationship: enough dates = partner, partner never robs you, partner finds out → break-up + mood hit + cold ex
-- · 9 zone cards + status JSON · 10 RLS / admin · 11 no way to target another player.
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

create or replace function pg_temp.advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

-- free, at a place, online, neutral needs
create or replace function pg_temp.at(p_uid uuid, p_loc text default null) returns void
language sql as $$
  update profiles set location_id = coalesce(p_loc, home_location_id), travel_to = null, travel_mode = null, travel_started_at = null,
                      travel_arrives_at = null, busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = now(), rent_due_at = null,
                      hunger = 50, energy = 50, hygiene = 50, fun = 50, social = 50, stress = 50, health = 80, bladder = 50,
                      needs_updated_at = bl_now()
   where id = p_uid;
$$;

-- run an action to the end with a pinned roll
create or replace function pg_temp.run(p_uid uuid, p_action text, p_npc text, p_rand text) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.login(p_uid);
  perform set_config('bl.test_rand', '', true);
  v := linkup_start(p_action, p_npc);
  perform pg_temp.advance((v->>'seconds')::numeric + 1);
  perform set_config('bl.test_rand', p_rand, true);
  v := linkup_finish();
  perform set_config('bl.test_rand', '', true);
  return v;
end $$;

create or replace function pg_temp.here1(p_uid uuid, p_loc text) returns text
language sql as $$ select id from bl_linkup_here(p_uid, p_loc) limit 1; $$;

-- ---------- setup ----------
do $$
declare
  adm uuid := pg_temp.new_user('d2_admin@lu.bl');
  a uuid := pg_temp.new_user('d2_a@lu.bl');
  b uuid := pg_temp.new_user('d2_b@lu.bl');
  c uuid := pg_temp.new_user('d2_c@lu.bl');
  u uuid;
  i int := 0;
begin
  perform set_config('d2.adm', adm::text, true); perform set_config('d2.a', a::text, true);
  perform set_config('d2.b', b::text, true); perform set_config('d2.c', c::text, true);
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  foreach u in array array[adm, a, b, c] loop
    i := i + 1;
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    perform pg_temp.login(u);
    perform create_profile_v2('D2_P' || i, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home('ekenwan_face_me');
    perform pg_temp.at(u);
  end loop;
  update profiles set is_admin = true where id = adm;
  update profiles set created_at = now() - interval '30 days', protected_until = null, cash = 0, bank = 0, street_cred = 0
   where id in (adm, a, b, c);
  -- clubs open at any hour here (the "closed" refusal sets its own hours)
  update locations set open_hour = null, close_hour = null where scene = 'club';
  update linkup_npcs set pickiness = 0, active = true;
  update linkup_actions set active = true;
  perform pg_temp.cfg('linkup.enabled', 'true');
  perform pg_temp.cfg('linkup.drinks_yes_pct', '45');
  perform pg_temp.cfg('linkup.npcs_per_place', '4');
  perform pg_temp.cfg('linkup.robbed_pct', '10');
  perform pg_temp.cfg('linkup.robbed_share_pct', '30');
  perform pg_temp.cfg('linkup.robbed_cap', '100000');
  perform pg_temp.cfg('linkup.caught_pct', '35');
  perform pg_temp.cfg('linkup.steady_dinners', '3');
  perform pg_temp.cfg('linkup.steady_spark', '60');
  perform pg_temp.cfg('linkup.yes_minutes', '120');
  perform pg_temp.cfg('linkup.no_cooldown_seconds', '120');
  perform pg_temp.cfg('places.hours_enabled', 'true');
end $$;

-- ---------- 1. grants ----------
do $$
declare v_rpc text;
begin
  foreach v_rpc in array array['linkup_status()', 'linkup_set_pref(text)', 'linkup_start(text,text)', 'linkup_finish()',
                               'linkup_morning_seen(bigint)', 'admin_linkup_player(uuid)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'auth may ' || v_rpc);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v_rpc)::regprocedure), 'secdef ' || v_rpc);
  end loop;
  foreach v_rpc in array array['bl_linkup_num(text,numeric)', 'bl_linkup_row(uuid,boolean)', 'bl_linkup_here(uuid,text)',
                               'bl_linkup_yes_pct(uuid,text)', 'bl_linkup_partner(uuid)', 'bl_linkup_current(uuid)',
                               'bl_linkup_card(uuid,linkup_actions,text)', 'bl_linkup_resolve(bigint)', 'bl_linkup_want(uuid)',
                               'bl_linkup_night()', 'bl_linkup_on()'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'helper private ' || v_rpc);
  end loop;
  perform pg_temp.assert(not has_table_privilege('anon', 'public.linkup_people', 'select'), 'anon no rows');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.linkup_people', 'update')
                         and not has_table_privilege('authenticated', 'public.linkup_people', 'insert')
                         and not has_table_privilege('authenticated', 'public.linkup_runs', 'insert')
                         and not has_table_privilege('authenticated', 'public.linkup_players', 'update'), 'no client writes');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.linkup_actions', 'update')
                         and not has_table_privilege('authenticated', 'public.linkup_npcs', 'update'), 'catalogues read-only');
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.linkup_npcs', 'select'), 'npcs readable');
  raise notice 'ok 1: grants / helpers private';
end $$;

set local role anon;
do $$
begin
  perform pg_temp.assert(pg_temp.hint_of('select linkup_status()') <> 'ok', 'anon refused status');
  perform pg_temp.assert(pg_temp.hint_of('select linkup_start(''drinks'', ''ivie'')') <> 'ok', 'anon refused start');
end $$;
reset role;

-- ---------- 2. prices + config + adults ----------
do $$
begin
  perform pg_temp.assert((select price from linkup_actions where id = 'drinks') = 10000, 'drinks 10k');
  perform pg_temp.assert((select price from linkup_actions where id = 'dinner') = 30000, 'dinner 30k');
  perform pg_temp.assert((select price from linkup_actions where id = 'short_time') = 15000, 'short time 15k');
  perform pg_temp.assert((select price from linkup_actions where id = 'overnight') = 45000, 'overnight 45k');
  perform pg_temp.assert((select price from linkup_actions where id = 'getaway') = 350000, 'getaway 350k');
  perform pg_temp.assert((select min_rank from linkup_actions where id = 'getaway') = 'big_boy', 'getaway Big Boy+');
  perform pg_temp.assert((select bool_and(needs_yes) from linkup_actions where id <> 'drinks')
                         and not (select needs_yes from linkup_actions where id = 'drinks'), 'everything but drinks needs a yes');
  perform pg_temp.assert((select bool_and(morning) from linkup_actions where kind = 'hotel')
                         and not (select bool_or(morning) from linkup_actions where kind <> 'hotel'), 'morning after only for the hotel');
  perform pg_temp.assert(bl_linkup_num('linkup.robbed_pct', 0) = 10, 'robbed 10 %');
  perform pg_temp.assert((select count(*) from linkup_npcs) >= 12, 'a pool of NPCs');
  perform pg_temp.assert((select min(age) >= 21 and max(age) <= 40 from linkup_npcs), 'ages 21-40');
  perform pg_temp.assert(pg_temp.hint_of('insert into linkup_npcs (id, name, gender, age) values (''teen'', ''X'', ''woman'', 17)') <> 'ok', 'no minors (check)');
  perform pg_temp.assert(pg_temp.hint_of('insert into linkup_npcs (id, name, gender, age) values (''old'', ''X'', ''man'', 41)') <> 'ok', 'age cap 40');
  perform pg_temp.assert((select count(distinct gender) from linkup_npcs) = 2, 'men and women');
  perform pg_temp.assert((select note from shrine_services where id = 'attraction') not like '%coming soon%', 'attraction note updated');
  raise notice 'ok 2: prices / config / adults only';
end $$;

-- ---------- 3. preference + who is out ----------
do $$
declare a uuid := current_setting('d2.a')::uuid; v jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.assert(bl_linkup_want(a) = 'anyone', 'default anyone');
  perform pg_temp.assert(pg_temp.hint_of('select linkup_set_pref(''aliens'')') = 'bad_pref', 'bad pref');
  v := linkup_set_pref('women');
  perform pg_temp.assert(bl_linkup_want(a) = 'women', 'women saved');
  perform pg_temp.assert((select bool_and(gender = 'woman') from bl_linkup_here(a, 'club_360')), 'only women out for me');
  perform pg_temp.assert((select count(*) from bl_linkup_here(a, 'club_360')) = 4, '4 per club');
  perform linkup_set_pref('men');
  perform pg_temp.assert((select bool_and(gender = 'man') from bl_linkup_here(a, 'club_360')), 'only men');
  perform linkup_set_pref('anyone');
  perform pg_temp.assert((select array_agg(id order by id) from bl_linkup_here(a, 'club_360'))
                         = (select array_agg(id order by id) from bl_linkup_here(a, 'club_360')), 'stable pick');
  perform pg_temp.assert((select count(*) from bl_linkup_here(a, 'protea_hotel')) = 0, 'nobody out at a hotel bar (clubs only)');
  raise notice 'ok 3: preference + who is out';
end $$;

-- ---------- 4. Buy drinks ----------
do $$
declare a uuid := current_setting('d2.a')::uuid; v jsonb; n text; h int; cash0 bigint;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'club_360');
  n := pg_temp.here1(a, 'club_360');
  perform set_config('d2.npc', n, true);
  update profiles set cash = 5000 where id = a;
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''drinks'', %L)', n)) = 'not_enough_money', 'broke');
  update profiles set cash = 100000 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select linkup_start(''drinks'', null)') = 'no_npc', 'pick someone');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''drinks'', %L)',
    (select id from linkup_npcs where id not in (select id from bl_linkup_here(a, 'club_360')) limit 1))) = 'not_here', 'not out tonight');
  perform pg_temp.assert(pg_temp.hint_of('select linkup_start(''drinks'', ''nobody'')') = 'not_here', 'unknown npc');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''short_time'', %L)', n)) = 'wrong_place', 'no hotel in a club');
  perform pg_temp.at(a, 'protea_hotel');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''drinks'', %L)', n)) = 'wrong_place', 'drinks only at clubs');
  perform pg_temp.at(a, 'club_360');
  -- closed club
  h := ((bl_game_clock()->>'hour')::int + 2) % 24;
  update locations set open_hour = h, close_hour = (h + 1) % 24 where id = 'club_360';
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''drinks'', %L)', n)) = 'closed', 'closed club');
  update locations set open_hour = null, close_hour = null where id = 'club_360';
  -- switched off
  perform pg_temp.cfg('linkup.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''drinks'', %L)', n)) = 'disabled', 'switch');
  perform pg_temp.cfg('linkup.enabled', 'true');

  -- base odds: 45 (pickiness 0, hygiene 50, no cred, no rank, no spark)
  perform pg_temp.assert((bl_linkup_yes_pct(a, n)->>'pct')::numeric = 45, 'base 45 %');
  v := linkup_start('drinks', n);
  perform pg_temp.assert((v->>'yes_pct')::numeric = 45 and (v->>'seconds')::int = 8, 'start: 45 %, 8 s');
  perform pg_temp.assert((select cash from profiles where id = a) = 90000, 'paid 10k');
  perform pg_temp.assert((select bl_ledger_label(reason, meta) from ledger where user_id = a order by id desc limit 1)
                         = 'Link-up: Buy drinks for someone · ' || (select name from linkup_npcs where id = n), 'ledger label');
  perform pg_temp.assert((select busy_label from profiles where id = a) = 'Link-up: Buy drinks for someone', 'busy label');
  perform pg_temp.assert(pg_temp.hint_of('select activity_stop()') = 'not_stoppable', 'can''t stop');
  perform pg_temp.assert(pg_temp.hint_of('select linkup_finish()') = 'not_yet', 'not yet');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''drinks'', %L)', n)) = 'busy', 'one at a time');
  perform pg_temp.advance(9);
  perform set_config('bl.test_rand', '0.5', true);
  v := linkup_finish();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(v->>'status' = 'no', '0.50 vs 45 % = no');
  perform pg_temp.assert((select busy_until from profiles where id = a) is null, 'free again');
  perform pg_temp.assert((select fun from profiles where id = a) > 50, 'still had a drink (+fun)');
  perform pg_temp.assert((select spark from linkup_people where user_id = a and npc_id = n) = 0, 'no spark on a no');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''drinks'', %L)', n)) = 'cooldown', 'cooldown after a no');
  perform pg_temp.advance(121);

  -- attraction charm +20: same roll now says yes
  insert into player_charms (user_id, kind, expires_at, data) values (a, 'attraction', bl_now() + interval '5 days', '{"value": 20}');
  perform pg_temp.assert((bl_linkup_yes_pct(a, n)->>'charm')::numeric = 20 and (bl_linkup_yes_pct(a, n)->>'pct')::numeric = 65, 'charm 45 → 65');
  v := pg_temp.run(a, 'drinks', n, '0.5');
  perform pg_temp.assert(v->>'status' = 'yes', '0.50 vs 65 % = yes');
  perform pg_temp.assert((select yes_until > bl_now() + interval '119 minutes' and spark = 10 and drinks = 2 and yeses = 1
                            from linkup_people where user_id = a and npc_id = n), 'yes lasts 120 min, spark 10');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'linkup_yes'), 'yes event');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''drinks'', %L)', n)) = 'already_yes', 'already said yes');
  -- other odds pieces
  update profiles set hygiene = 80, street_cred = 37 where id = a;
  perform pg_temp.assert((bl_linkup_yes_pct(a, n)->>'looks')::numeric = 5 and (bl_linkup_yes_pct(a, n)->>'cred')::numeric = 3
                         and (bl_linkup_yes_pct(a, n)->>'spark')::numeric = 2, 'fresh +5, cred +3, spark 10 → +2');
  update profiles set hygiene = 10 where id = a;
  perform pg_temp.assert((bl_linkup_yes_pct(a, n)->>'looks')::numeric = -15, 'rough −15');
  insert into yahoo_players (user_id, total_earned) values (a, 10000000) on conflict (user_id) do update set total_earned = 10000000;
  perform pg_temp.assert((bl_linkup_yes_pct(a, n)->>'rank')::numeric = 6, 'Big Boy = 2 steps × 3');
  update linkup_npcs set pickiness = 50 where id = n;
  update profiles set hygiene = 80 where id = a;
  perform pg_temp.assert((bl_linkup_yes_pct(a, n)->>'pct')::numeric = 95, 'cap 95');
  update linkup_npcs set pickiness = -50 where id = n;
  update profiles set hygiene = 10, street_cred = 0 where id = a;
  delete from player_charms where user_id = a;
  update yahoo_players set total_earned = 0 where user_id = a;
  perform pg_temp.assert((bl_linkup_yes_pct(a, n)->>'pct')::numeric = 5, 'floor 5');
  update linkup_npcs set pickiness = 0 where id = n;
  update profiles set hygiene = 50 where id = a;
  raise notice 'ok 4: buy drinks (refusals, charge, roll, cooldown, charm)';
end $$;

-- ---------- 5. dinner + hotel need a yes ----------
do $$
declare a uuid := current_setting('d2.a')::uuid; b uuid := current_setting('d2.b')::uuid; n text := current_setting('d2.npc'); v jsonb;
begin
  -- b never got a yes
  perform pg_temp.login(b);
  perform pg_temp.at(b, 'protea_hotel');
  update profiles set cash = 100000 where id = b;
  perform pg_temp.assert(pg_temp.hint_of('select linkup_start(''short_time'', null)') = 'needs_yes', 'hotel needs a link-up');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''overnight'', %L)', n)) = 'needs_yes', 'hotel needs THEIR yes');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''dinner'', %L)', n)) = 'needs_yes', 'dinner needs a yes');
  perform pg_temp.assert((select cash from profiles where id = b) = 100000, 'nothing charged');

  -- a has a yes: dinner at the hotel restaurant
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'protea_hotel');
  update profiles set cash = 100000 where id = a;
  v := pg_temp.run(a, 'dinner', null, '0.5');
  perform pg_temp.assert(v->>'status' = 'done' and v->'npc'->>'id' = n, 'dinner with the current link-up');
  perform pg_temp.assert((select cash from profiles where id = a) = 70000, 'dinner 30k');
  perform pg_temp.assert((select social from profiles where id = a) > 80 and (select fun from profiles where id = a) > 70, '+social +fun');
  perform pg_temp.assert((select spark = 25 and dinners = 1 from linkup_people where user_id = a and npc_id = n), 'spark +15');
  perform pg_temp.assert(v->'morning' = 'null'::jsonb or v->'morning' is null, 'no morning after a dinner');
  -- also at the mall food court
  perform pg_temp.at(a, 'benin_city_mall');
  perform pg_temp.assert((select 'mall' = any (scenes) from linkup_actions where id = 'dinner'), 'mall dinner');
  raise notice 'ok 5: dinner + hotel need a yes, effects, spark';
end $$;

-- ---------- 6. morning after ----------
do $$
declare a uuid := current_setting('d2.a')::uuid; n text := current_setting('d2.npc'); v jsonb; r bigint;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'golden_tulip');
  update profiles set cash = 200000 where id = a;
  v := pg_temp.run(a, 'short_time', n, '0.05');
  perform pg_temp.assert(v->>'status' = 'done' and (v->'morning'->>'robbed')::boolean, 'robbed on a 0.05 roll (10 %)');
  -- 200,000 − 15,000 = 185,000; 30 % = 55,500
  perform pg_temp.assert((v->'morning'->>'robbed_amount')::bigint = 55500, 'share of cash: 55,500');
  perform pg_temp.assert((select cash from profiles where id = a) = 185000 - 55500, 'cash gone');
  perform pg_temp.assert((select bl_ledger_label(reason, meta) from ledger where user_id = a order by id desc limit 1) = 'Link-up gone wrong', 'ledger');
  perform pg_temp.assert((select stress from profiles where id = a) < 50 and (select fun from profiles where id = a) > 50, '+fun −stress');
  perform pg_temp.assert((select yes_until is null and nights = 1 from linkup_people where user_id = a and npc_id = n), 'the yes is used up');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''overnight'', %L)', n)) = 'needs_yes', 'new night = new yes');
  -- the popup stays until seen
  r := (linkup_status()->'morning'->>'run_id')::bigint;
  perform pg_temp.assert(r = (v->>'run_id')::bigint, 'morning popup pending');
  perform pg_temp.assert((linkup_morning_seen(r)->>'seen')::boolean and linkup_status()->'morning' = 'null'::jsonb, 'seen');
  -- cap
  update linkup_people set yes_until = bl_now() + interval '1 hour' where user_id = a and npc_id = n;
  update profiles set cash = 2000000 where id = a;
  v := pg_temp.run(a, 'overnight', n, '0.05');
  perform pg_temp.assert((v->'morning'->>'robbed_amount')::bigint = 100000, 'capped at 100k');
  perform pg_temp.assert((select energy from profiles where id = a) > 80, 'overnight: bigger boost (energy)');
  -- a fine morning
  update linkup_people set yes_until = bl_now() + interval '1 hour' where user_id = a and npc_id = n;
  update profiles set cash = 100000 where id = a;
  v := pg_temp.run(a, 'short_time', n, '0.5');
  perform pg_temp.assert(not (v->'morning'->>'robbed')::boolean and (select cash from profiles where id = a) = 85000, 'fine morning');
  raise notice 'ok 6: morning after (missing cash share + cap + ledger, fine morning)';
end $$;

-- ---------- 7. weekend getaway ----------
do $$
declare a uuid := current_setting('d2.a')::uuid; n text := current_setting('d2.npc'); v jsonb; cred0 int;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'protea_hotel');
  update linkup_people set yes_until = bl_now() + interval '1 hour' where user_id = a and npc_id = n;
  update profiles set cash = 400000 where id = a;
  update yahoo_players set total_earned = 1000000 where user_id = a;  -- G-boy only
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''getaway'', %L)', n)) = 'yahoo_rank', 'getaway needs Big Boy');
  update yahoo_players set total_earned = 10000000 where user_id = a;
  select street_cred into cred0 from profiles where id = a;
  v := pg_temp.run(a, 'getaway', n, '0.5');
  perform pg_temp.assert(v->>'status' = 'done', 'getaway done');
  perform pg_temp.assert((select cash from profiles where id = a) = 50000, 'getaway 350k');
  perform pg_temp.assert((select street_cred from profiles where id = a) = cred0 + 6, 'hype +6 street cred');
  perform pg_temp.assert((select fun from profiles where id = a) >= 99 and (select stress from profiles where id = a) <= 1, 'big boost');
  raise notice 'ok 7: weekend getaway (Big Boy+, hype)';
end $$;

-- ---------- 8. relationship ----------
do $$
declare c uuid := current_setting('d2.c')::uuid; v jsonb; y text; z text; s jsonb;
begin
  perform pg_temp.login(c);
  perform pg_temp.at(c, 'protea_hotel');
  select id into y from linkup_npcs where gender = 'woman' order by sort limit 1;
  select id into z from linkup_npcs where gender = 'man' order by sort limit 1;
  insert into linkup_people (user_id, npc_id, spark, dinners, yes_until) values (c, y, 50, 2, bl_now() + interval '1 hour');
  update profiles set cash = 500000 where id = c;
  v := pg_temp.run(c, 'dinner', y, '0.5');
  perform pg_temp.assert((v->>'new_partner')::boolean, '3 dinners + spark 65 = an item');
  perform pg_temp.assert((select steady from linkup_people where user_id = c and npc_id = y), 'partner flag');
  perform pg_temp.assert(exists (select 1 from events where user_id = c and kind = 'linkup_partner'), 'partner event');
  s := linkup_status();
  perform pg_temp.assert(s->'partner'->>'id' = y, 'status partner');
  -- the partner needs no drinks and never robs you
  update linkup_people set yes_until = null where user_id = c and npc_id = y;
  v := pg_temp.run(c, 'short_time', y, '0.01');
  perform pg_temp.assert(not (v->'morning'->>'robbed')::boolean and not (v->'morning'->>'caught')::boolean
                         and (v->'morning'->>'with_partner')::boolean, 'partner: no yes needed, never robbed, nothing to find out');
  -- a night with someone else: 0.20 → not robbed (10 %), partner finds out (35 %)
  insert into linkup_people (user_id, npc_id, yes_until) values (c, z, bl_now() + interval '1 hour');
  update profiles set fun = 50, social = 50, stress = 50 where id = c;
  v := pg_temp.run(c, 'short_time', z, '0.2');
  perform pg_temp.assert(not (v->'morning'->>'robbed')::boolean and (v->'morning'->>'caught')::boolean, 'partner found out');
  perform pg_temp.assert(v->'morning'->'ex'->>'id' = y, 'ex named');
  perform pg_temp.assert((select not steady and ended_at is not null and cold_until > bl_now() from linkup_people where user_id = c and npc_id = y), 'it''s over');
  perform pg_temp.assert((select spark from linkup_people where user_id = c and npc_id = y) <= 30, 'spark lost');
  perform pg_temp.assert((select breakups from linkup_players where user_id = c) = 1, 'break-up counted');
  -- short time gives +30 fun / −25 stress; the break-up −30 fun / −25 social / +30 stress
  perform pg_temp.assert((select social from profiles where id = c) < 30 and (select stress from profiles where id = c) > 50, 'mood hit');
  perform pg_temp.assert(exists (select 1 from events where user_id = c and kind = 'linkup_breakup'), 'break-up event');
  perform pg_temp.assert(linkup_status()->'partner' = 'null'::jsonb, 'no partner now');
  -- no partner, no risk of being found out
  update linkup_people set yes_until = bl_now() + interval '1 hour' where user_id = c and npc_id = z;
  v := pg_temp.run(c, 'short_time', z, '0.2');
  perform pg_temp.assert(not (v->'morning'->>'caught')::boolean, 'single: nobody to find out');
  -- the ex is cold at the club
  update profiles set location_id = 'club_360' where id = c;
  if exists (select 1 from bl_linkup_here(c, 'club_360') where id = y) then
    perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''drinks'', %L)', y)) = 'cold', 'ex won''t talk to you');
  end if;
  raise notice 'ok 8: relationship (partner, never robbed by partner, found out → break-up)';
end $$;

-- ---------- 9. zone cards + status ----------
do $$
declare a uuid := current_setting('d2.a')::uuid; v jsonb; s jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'club_360');
  v := place_interior('club_360');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v->'zones') z, jsonb_array_elements(z->'actions') x
                                  where x->>'kind' = 'linkup' and x->>'ref' = 'drinks' and (x->>'cost')::bigint = 10000
                                    and (x->'linkup'->>'here')::int = 4), 'club bar: Buy drinks card');
  v := place_interior('protea_hotel');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(v->'zones') z, jsonb_array_elements(z->'actions') x
                           where x->>'kind' = 'linkup') = 4, 'hotel: dinner + 3 suite cards');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v->'zones') z, jsonb_array_elements(z->'actions') x
                                  where x->>'ref' = 'short_time' and x->'linkup'->>'needs' = 'yes'), 'needs a yes shown');
  v := place_interior('benin_city_mall');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v->'zones') z, jsonb_array_elements(z->'actions') x
                                  where x->>'kind' = 'linkup' and x->>'ref' = 'dinner'), 'mall food court dinner');
  s := linkup_status();
  perform pg_temp.assert(jsonb_array_length(s->'here') = 4 and jsonb_array_length(s->'actions') = 5, 'status here + actions');
  perform pg_temp.assert(jsonb_array_length(s->'people') >= 1 and jsonb_array_length(s->'history') >= 1, 'people + history');
  perform pg_temp.assert((s->'here'->0->'yes_pct'->>'pct') is not null, 'odds per person');
  raise notice 'ok 9: zone cards + status';
end $$;

-- ---------- 10. RLS / admin ----------
do $$
declare a uuid := current_setting('d2.a')::uuid; b uuid := current_setting('d2.b')::uuid; n int; m int; k int;
begin
  perform pg_temp.login(b);
  set local role authenticated;
  select count(*) into n from linkup_people where user_id = a;
  select count(*) into m from linkup_runs where user_id = a;
  select count(*) into k from linkup_players where user_id = a;
  reset role;
  perform pg_temp.assert(n = 0 and m = 0 and k = 0, 'can''t see other players'' link-ups');
  perform pg_temp.login(a);
  set local role authenticated;
  select count(*) into n from linkup_people where user_id = a;
  select count(*) into m from linkup_runs where user_id = a;
  reset role;
  perform pg_temp.assert(n >= 1 and m >= 1, 'own rows visible');
  perform pg_temp.login(current_setting('d2.adm')::uuid);
  perform pg_temp.assert(jsonb_array_length(admin_linkup_player(a)->'runs') > 0, 'admin view');
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_linkup_player(%L)', a)) <> 'ok', 'non-admin refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_morning_seen(%s)', (select max(id) from linkup_runs where user_id = a))) = 'ok'
                         and not (select morning_seen from linkup_runs where id = (select max(id) from linkup_runs where user_id = a and morning is not null)), 'can''t mark someone else''s popup');
  raise notice 'ok 10: RLS / admin';
end $$;

-- ---------- 11. never another player ----------
do $$
declare a uuid := current_setting('d2.a')::uuid; b uuid := current_setting('d2.b')::uuid;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'club_360');
  perform pg_temp.at(b, 'club_360');
  update profiles set cash = 100000 where id = a;
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''drinks'', %L)', b::text)) = 'not_here', 'a player id is not an NPC');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''drinks'', %L)', (select username from profiles where id = b))) = 'not_here', 'nor a username');
  perform pg_temp.at(a, 'protea_hotel');
  perform pg_temp.assert(pg_temp.hint_of(format('select linkup_start(''overnight'', %L)', b::text)) = 'needs_yes', 'hotel: no player either');
  -- no player-facing link-up function takes a player id; targets reference linkup_npcs only
  perform pg_temp.assert(not exists (
    select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.proname like 'linkup\_%' and 'uuid'::regtype = any (p.proargtypes::regtype[])), 'no uuid args');
  perform pg_temp.assert((select confrelid::regclass::text from pg_constraint where conrelid = 'public.linkup_people'::regclass and contype = 'f'
                           and conkey = array[(select attnum from pg_attribute where attrelid = 'public.linkup_people'::regclass and attname = 'npc_id')]::int2[]) = 'linkup_npcs',
                         'people point at NPCs');
  perform pg_temp.assert((select cash from profiles where id = a) = 100000, 'nothing charged');
  raise notice 'ok 11: never another player';
end $$;
