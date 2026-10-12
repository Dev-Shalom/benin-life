-- C1 pickpocket + jail choices (20261012001200_pickpocket_jail.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/pickpocket_test.sql
-- Time moves with bl.test_offset_seconds; rolls are pinned with bl.test_rand (bl_rand) or forced via the pct configs.
-- Groups: 1 grants / anon / helpers private · 2 odds · 3 refusals (switch, self, newbie both ways, protection, private home,
-- police station, not same place, stale victim, busy) · 4 success (cash only, share, cap, min, empty, ledger labels, alerts,
-- timer) · 5 cooldowns · 6 caught opens a case · 7 bail · 8 go to jail + served · 9 escape success / fail compounding +
-- police_bail routing · 10 concurrent double steal · 11 admin list / release / audit · 12 RLS.
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

-- put the four players back at Oba Market, free, online
create or replace function pg_temp.reset_players() returns void
language plpgsql as $$
begin
  update profiles set location_id = 'oba_market', travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
                      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, protected_until = null,
                      home_visit_host_id = null, last_seen = now(), rent_due_at = null
   where id in (current_setting('c1.t')::uuid, current_setting('c1.v')::uuid, current_setting('c1.t2')::uuid, current_setting('c1.adm')::uuid);
end $$;

-- start + finish one pickpocket as p_thief on p_victim (time jumps past the timer)
create or replace function pg_temp.steal(p_thief uuid, p_victim uuid) returns jsonb
language plpgsql as $$
begin
  perform pg_temp.login(p_thief);
  perform steal_attempt(p_victim);
  perform pg_temp.advance(10);
  update profiles set last_seen = now() where id = p_victim;
  return steal_finish();
end $$;

-- ---------- setup ----------
do $$
declare
  adm uuid := pg_temp.new_user('c1_admin@pp.bl');
  t uuid := pg_temp.new_user('c1_thief@pp.bl');
  v uuid := pg_temp.new_user('c1_victim@pp.bl');
  t2 uuid := pg_temp.new_user('c1_thief2@pp.bl');
  n uuid := pg_temp.new_user('c1_newbie@pp.bl');
begin
  perform set_config('c1.adm', adm::text, true); perform set_config('c1.t', t::text, true);
  perform set_config('c1.v', v::text, true); perform set_config('c1.t2', t2::text, true); perform set_config('c1.n', n::text, true);
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(adm);
  perform create_profile_v2('C1_Admin', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set is_admin = true where id = adm;
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(t);
  perform create_profile_v2('C1_Thief', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(v);
  perform create_profile_v2('C1_Victim', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(t2);
  perform create_profile_v2('C1_Thief2', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(n);
  perform create_profile_v2('C1_Newbie', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set created_at = now() - interval '30 days' where id in (adm, t, v, t2);
  update profiles set location_id = 'oba_market', last_seen = now(), protected_until = null where id = n;
  perform pg_temp.reset_players();
  update profiles set cash = 0, bank = 0 where id in (t, t2);
  update profiles set cash = 100000, bank = 5000000 where id = v;
  perform pg_temp.cfg('crime.steal_enabled', 'true');
  perform pg_temp.cfg('crime.steal_caught_pct', '62');
  perform pg_temp.cfg('crime.escape_caught_pct', '52');
  perform pg_temp.cfg('crime.bail_base', '20000000');
  perform pg_temp.cfg('action.jail_max_seconds', '45');
  perform pg_temp.cfg('receipts.enabled', 'true');
  perform pg_temp.cfg('receipts.min_amount', '500000');
end $$;

-- ---------- 1. grants ----------
do $$
declare v_rpc text;
begin
  foreach v_rpc in array array['steal_attempt(uuid)', 'steal_finish()', 'crime_status()', 'jail_case_bail()', 'jail_case_go_to_jail()',
                               'jail_case_escape()', 'admin_jail_cases(text,integer)', 'admin_jail_release(bigint,text)', 'police_bail()'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'auth may ' || v_rpc);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v_rpc)::regprocedure), 'secdef ' || v_rpc);
  end loop;
  foreach v_rpc in array array['bl_crime_bool(text,boolean)', 'bl_crime_num(text,numeric)', 'bl_crime_public_place(text)',
                               'bl_steal_caught_pct(uuid,uuid,numeric)', 'bl_crime_roll(numeric)', 'bl_crime_close_stale(uuid)',
                               'bl_crime_case_json(jail_cases)', 'bl_steal_resolve(bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'helper private ' || v_rpc);
  end loop;
  perform pg_temp.assert(not has_table_privilege('anon', 'public.jail_cases', 'select'), 'anon no cases');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.crime_attempts', 'select'), 'attempts server-only');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.jail_cases', 'insert')
                         and not has_table_privilege('authenticated', 'public.jail_cases', 'update'), 'no case writes');
  raise notice 'ok 1: grants / anon refused / helpers private';
end $$;

-- anon really refused (role switch)
set local role anon;
do $$
begin
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', current_setting('c1.v'))) like '%permission denied%', 'anon steal refused');
  perform pg_temp.assert(pg_temp.hint_of('select jail_case_escape()') like '%permission denied%', 'anon escape refused');
end $$;
reset role;

-- ---------- 2. odds ----------
do $$
declare n int := 0; i int;
begin
  perform setseed(0.42);
  for i in 1..4000 loop
    if bl_crime_roll(62) then n := n + 1; end if;
  end loop;
  perform pg_temp.assert(n between 2360 and 2600, 'about 62% caught: ' || n);
  perform pg_temp.assert(bl_steal_caught_pct(null, null) = 62, 'default pct');
  perform pg_temp.assert(bl_steal_caught_pct(null, null, 10) = 52, 'skill hook lowers odds');
  perform pg_temp.assert(bl_steal_caught_pct(null, null, 500) = 0 and bl_steal_caught_pct(null, null, -500) = 100, 'clamped');
  perform pg_temp.assert(not bl_crime_roll(0) and bl_crime_roll(100), 'forced 0 / 100');
  perform set_config('bl.test_rand', '0.61', true);
  perform pg_temp.assert(bl_crime_roll(62), 'pinned 0.61 < 62%');
  perform set_config('bl.test_rand', '0.62', true);
  perform pg_temp.assert(not bl_crime_roll(62), 'pinned 0.62 not < 62%');
  perform set_config('bl.test_rand', '', true);
  raise notice 'ok 2: odds (seeded %/4000, skill hook, forced)', n;
end $$;

-- ---------- 3. refusals ----------
do $$
declare t uuid := current_setting('c1.t'); v uuid := current_setting('c1.v'); n uuid := current_setting('c1.n');
        v_home text;
begin
  perform pg_temp.login(t);
  perform pg_temp.cfg('crime.steal_enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'disabled', 'switch off');
  perform pg_temp.cfg('crime.steal_enabled', 'true');
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', t)) = 'self', 'self');
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', n)) = 'protected', 'newbie target');
  perform pg_temp.login(n);
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'newbie_self', 'newbie thief');
  perform pg_temp.login(t);
  update profiles set protected_until = bl_now() + interval '1 hour' where id = v;
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'protected', 'start protection');
  perform pg_temp.reset_players();
  -- inside a private home (the thief's own home, victim visiting)
  select home_location_id into v_home from profiles where id = t;
  perform pg_temp.assert((select private_home_owner_id from locations where id = v_home) = t, 'private home fixture');
  update profiles set location_id = v_home where id in (t, v);
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'private_place', 'private home refused');
  -- police station
  update profiles set location_id = 'police_hq' where id in (t, v);
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'private_place', 'police station refused');
  perform pg_temp.reset_players();
  update profiles set location_id = 'uselu_market' where id = v;
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'not_here', 'not same place');
  perform pg_temp.reset_players();
  update profiles set last_seen = now() - interval '10 minutes' where id = v;
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'not_here', 'victim offline');
  perform pg_temp.reset_players();
  update profiles set travel_to = 'uselu_market' where id = v;
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'not_here', 'victim on the road');
  perform pg_temp.reset_players();
  update profiles set busy_until = bl_now() + interval '1 minute', busy_label = 'Eating' where id = t;
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'busy', 'thief busy');
  perform pg_temp.reset_players();
  update profiles set travel_to = 'uselu_market' where id = t;
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'traveling', 'thief travelling');
  perform pg_temp.reset_players();
  update profiles set jailed_until = bl_now() + interval '1 minute' where id = t;
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'jailed', 'thief jailed');
  perform pg_temp.reset_players();
  perform pg_temp.assert(not exists (select 1 from crime_attempts where thief_id in (t, n)), 'no attempts recorded');
  raise notice 'ok 3: refusals';
end $$;

-- ---------- 4. success ----------
do $$
declare t uuid := current_setting('c1.t'); v uuid := current_setting('c1.v');
        r jsonb; p profiles; amt bigint; n int;
begin
  perform pg_temp.cfg('crime.steal_caught_pct', '0');
  perform pg_temp.login(t);
  r := steal_attempt(v);
  select * into p from profiles where id = t;
  perform pg_temp.assert(p.busy_label = 'Picking a pocket' and p.busy_until = (r->>'busy_until')::timestamptz
                         and p.busy_until = bl_now() + interval '4 seconds', 'timer 4 s ' || r::text);
  perform pg_temp.assert(pg_temp.hint_of('select steal_finish()') = 'not_yet', 'not before the timer');
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'busy', 'busy while stealing');
  perform pg_temp.advance(5);
  update profiles set last_seen = now() where id = v;
  r := steal_finish();
  amt := (r->>'amount')::bigint;
  perform pg_temp.assert(r->>'status' = 'success', 'success ' || r::text);
  perform pg_temp.assert(amt between 5000 and 15000, '5–15% of 100k cash: ' || amt);
  perform pg_temp.assert((select cash from profiles where id = v) = 100000 - amt and (select bank from profiles where id = v) = 5000000,
                         'victim cash only, bank untouched');
  perform pg_temp.assert((select cash from profiles where id = t) = amt, 'thief got it');
  perform pg_temp.assert((select busy_until from profiles where id = t) is null, 'timer cleared');
  perform pg_temp.assert(bl_ledger_label('steal_gain', (select meta from ledger where user_id = t and reason = 'steal_gain' order by id desc limit 1))
                         = 'Pickpocketed · Oba Market', 'thief label');
  perform pg_temp.assert(bl_ledger_label('steal_loss', (select meta from ledger where user_id = v and reason = 'steal_loss' order by id desc limit 1))
                         = 'Stolen from you · Oba Market', 'victim label');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'steal_loss' and delta = -amt and account = 'cash'), 'victim ledger');
  select count(*) into n from events where user_id = v and kind = 'stolen_from' and body like '%Oba Market%' and body not like '%C1_Thief%';
  perform pg_temp.assert(n = 1, 'victim alert without the thief name');
  perform pg_temp.assert(pg_temp.hint_of('select steal_finish()') = 'no_attempt', 'double finish');

  -- cap: rich victim -> ₦50,000 at most; pinned roll 0.99 (not caught at 62%) -> share 14.9%
  perform pg_temp.cfg('crime.steal_caught_pct', '62');
  perform set_config('bl.test_rand', '0.99', true);
  update profiles set cash = 10000000 where id = v;
  perform pg_temp.advance(1000);
  r := pg_temp.steal(t, v);
  perform pg_temp.assert(r->>'status' = 'success' and (r->>'amount')::bigint = 50000, 'capped at 50k ' || r::text);
  -- min: 5% of ₦1,000 = 50 -> ₦100 (roll 0.99 -> 14.9% = 149 -> pin 0.63 for 5%+6.3% = 113 ... use min_pct=max_pct=5)
  perform pg_temp.cfg('crime.steal_max_pct', '5');
  update profiles set cash = 1000 where id = v;
  perform pg_temp.advance(1000);
  r := pg_temp.steal(t, v);
  perform pg_temp.assert(r->>'status' = 'success' and (r->>'amount')::bigint = 100, 'min 100 ' || r::text);
  perform pg_temp.cfg('crime.steal_max_pct', '15');
  -- empty pocket
  update profiles set cash = 50 where id = v;
  perform pg_temp.advance(1000);
  r := pg_temp.steal(t, v);
  perform pg_temp.assert(r->>'status' = 'empty' and (select cash from profiles where id = v) = 50, 'empty pocket ' || r::text);
  -- victim walked away during the timer
  update profiles set cash = 100000 where id = v;
  perform pg_temp.advance(1000);
  perform pg_temp.login(t);
  perform steal_attempt(v);
  update profiles set location_id = 'uselu_market' where id = v;
  perform pg_temp.advance(10);
  r := steal_finish();
  perform pg_temp.assert(r->>'status' = 'gone' and (select cash from profiles where id = v) = 100000, 'gone ' || r::text);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.reset_players();
  raise notice 'ok 4: success (cash only, share, cap, min, empty, gone, ledger, alert)';
end $$;

-- ---------- 5. cooldowns ----------
do $$
declare t uuid := current_setting('c1.t'); v uuid := current_setting('c1.v'); t2 uuid := current_setting('c1.t2'); r jsonb;
begin
  perform pg_temp.cfg('crime.steal_caught_pct', '0');
  perform pg_temp.advance(1000);
  r := pg_temp.steal(t, v);
  perform pg_temp.assert(r->>'status' = 'success', 'fresh steal');
  perform pg_temp.login(t);
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', t2)) = 'cooldown', 'thief cooldown (3 min)');
  perform pg_temp.login(t2);
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'victim_cooldown', 'victim cooldown (10 min)');
  perform pg_temp.advance(200);           -- thief may go again, victim still resting
  perform pg_temp.login(t);
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'victim_cooldown', 'victim still resting');
  perform pg_temp.advance(600);
  update profiles set last_seen = now() where id = v;
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'ok', 'after both cooldowns');
  perform pg_temp.advance(10);
  perform steal_finish();
  perform pg_temp.reset_players();
  raise notice 'ok 5: cooldowns';
end $$;

-- ---------- 6. caught opens a case ----------
do $$
declare t uuid := current_setting('c1.t'); v uuid := current_setting('c1.v');
        r jsonb; c jail_cases; v_cash bigint; s jsonb;
begin
  perform pg_temp.cfg('crime.steal_caught_pct', '100');
  perform pg_temp.advance(1000);
  select cash into v_cash from profiles where id = v;
  r := pg_temp.steal(t, v);
  perform pg_temp.assert(r->>'status' = 'caught' and (r->'case'->>'bail_amount')::bigint = 20000000, 'caught ' || r::text);
  select * into c from jail_cases where user_id = t and status = 'open';
  perform pg_temp.assert(c.id is not null and c.bail_amount = 20000000 and c.jail_seconds = 45 and not c.decided
                         and c.escape_attempts = 0 and c.jail_until = bl_now() + interval '45 seconds', 'case row');
  perform pg_temp.assert((select jailed_until from profiles where id = t) = c.jail_until
                         and (select location_id from profiles where id = t) = 'police_hq', 'thief held at Police HQ');
  perform pg_temp.assert((select cash from profiles where id = v) = v_cash, 'nothing stolen');
  perform pg_temp.assert(exists (select 1 from events where user_id = v and kind = 'pickpocket_stopped' and body like '@C1_Thief tried%'), 'victim told who');
  s := crime_status();
  perform pg_temp.assert((s->'case'->>'id')::bigint = c.id and (s->'case'->>'decided')::boolean = false
                         and (s->'case'->>'can_afford')::boolean = false, 'popup state survives reload ' || s::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'jailed', 'no acting while caught');
  raise notice 'ok 6: caught opens a case';
end $$;

-- ---------- 7. bail ----------
do $$
declare t uuid := current_setting('c1.t'); r jsonb; c jail_cases;
begin
  perform pg_temp.login(t);
  update profiles set bank = 1000, cash = 1000 where id = t;
  perform pg_temp.assert(pg_temp.hint_of('select jail_case_bail()') = 'not_enough_money', 'cannot afford');
  update profiles set bank = 15000000, cash = 6000000 where id = t;
  r := jail_case_bail();
  perform pg_temp.assert((r->>'paid')::bigint = 20000000 and (r->>'bank')::bigint = 15000000 and (r->>'cash')::bigint = 5000000, 'bank first ' || r::text);
  perform pg_temp.assert(r ? 'receipt' and (r->'receipt'->>'amount')::bigint = 20000000, 'receipt issued');
  perform pg_temp.assert((select bank from profiles where id = t) = 0 and (select cash from profiles where id = t) = 1000000, 'charged');
  perform pg_temp.assert((select jailed_until from profiles where id = t) is null, 'free');
  select * into c from jail_cases where user_id = t order by id desc limit 1;
  perform pg_temp.assert(c.status = 'bailed' and c.closed_at is not null, 'case bailed');
  perform pg_temp.assert((select count(*) from ledger where user_id = t and reason = 'bail') = 2
                         and bl_ledger_label('bail', '{}') = 'Bail', 'ledger Bail');
  perform pg_temp.assert(pg_temp.hint_of('select jail_case_bail()') = 'no_case', 'no case after bail');
  perform pg_temp.reset_players();
  raise notice 'ok 7: bail';
end $$;

-- ---------- 8. go to jail + served ----------
do $$
declare t uuid := current_setting('c1.t'); v uuid := current_setting('c1.v'); r jsonb; c jail_cases; v_until timestamptz;
begin
  perform pg_temp.advance(1000);
  r := pg_temp.steal(t, v);
  perform pg_temp.assert(r->>'status' = 'caught', 'caught again');
  select jail_until into v_until from jail_cases where user_id = t and status = 'open';
  perform pg_temp.advance(5);
  r := jail_case_go_to_jail();
  select * into c from jail_cases where user_id = t and status = 'open';
  perform pg_temp.assert(c.decided and c.jail_until = v_until and (select jailed_until from profiles where id = t) = v_until, 'serving the time');
  perform pg_temp.assert((crime_status()->'case'->>'decided')::boolean, 'popup closed');
  perform pg_temp.advance(50);
  perform pg_temp.assert(crime_status()->'case' = 'null'::jsonb, 'served: no open case');
  perform pg_temp.assert((select status from jail_cases where id = c.id) = 'served', 'status served');
  perform pg_temp.reset_players();
  raise notice 'ok 8: go to jail + served';
end $$;

-- ---------- 9. escape ----------
do $$
declare t uuid := current_setting('c1.t'); v uuid := current_setting('c1.v'); r jsonb; c jail_cases;
begin
  -- success
  perform pg_temp.advance(1000);
  perform pg_temp.steal(t, v);
  perform pg_temp.cfg('crime.escape_caught_pct', '0');
  r := jail_case_escape();
  perform pg_temp.assert((r->>'escaped')::boolean, 'escaped ' || r::text);
  perform pg_temp.assert((select jailed_until from profiles where id = t) is null
                         and (select location_id from profiles where id = t) = 'oba_market', 'free, back at the market');
  perform pg_temp.assert((select status from jail_cases where user_id = t order by id desc limit 1) = 'escaped', 'case escaped');
  -- fail compounds
  perform pg_temp.reset_players();
  perform pg_temp.advance(1000);
  perform pg_temp.steal(t, v);
  perform pg_temp.cfg('crime.escape_caught_pct', '100');
  perform jail_case_go_to_jail();
  r := jail_case_escape();
  select * into c from jail_cases where user_id = t and status = 'open';
  perform pg_temp.assert(not (r->>'escaped')::boolean and c.bail_amount = 40000000 and c.jail_seconds = 90 and c.escape_attempts = 1
                         and not c.decided and c.jail_until = bl_now() + interval '90 seconds', 'fail 1 doubles ' || r::text);
  perform pg_temp.assert((select jailed_until from profiles where id = t) = c.jail_until, 'cell extended');
  r := jail_case_escape();
  select * into c from jail_cases where user_id = t and status = 'open';
  perform pg_temp.assert(c.bail_amount = 80000000 and c.jail_seconds = 180 and c.escape_attempts = 2, 'fail 2 compounds');
  -- police_bail routes to the case price (no cheap ₦5,000 way out)
  update profiles set bank = 0, cash = 100000 where id = t;
  perform pg_temp.assert(pg_temp.hint_of('select police_bail()') = 'not_enough_money', 'police_bail asks the case price');
  update profiles set bank = 80000000 where id = t;
  r := police_bail();
  perform pg_temp.assert((r->>'paid')::bigint = 80000000 and (select status from jail_cases where id = c.id) = 'bailed', 'police_bail paid case ' || r::text);
  update profiles set cash = 0, bank = 0 where id = t;
  perform pg_temp.cfg('crime.escape_caught_pct', '52');
  perform pg_temp.reset_players();
  raise notice 'ok 9: escape success / fail compounds / police_bail routed';
end $$;

-- ---------- 10. concurrent double steal ----------
do $$
declare t uuid := current_setting('c1.t'); v uuid := current_setting('c1.v'); t2 uuid := current_setting('c1.t2');
        r1 jsonb; r2 jsonb; v_cash bigint;
begin
  perform pg_temp.cfg('crime.steal_caught_pct', '0');
  perform pg_temp.advance(1000);
  update profiles set cash = 100000 where id = v;
  perform pg_temp.login(t);
  perform steal_attempt(v);
  perform pg_temp.login(t2);
  perform pg_temp.assert(pg_temp.hint_of(format('select steal_attempt(%L::uuid)', v)) = 'victim_cooldown', 'second thief refused while one is mid-steal');
  -- the race that slipped past the start check: both running, both finish -> one success, the other finds nothing
  insert into crime_attempts (thief_id, victim_id, location_id, started_at, resolve_at)
  values (t2, v, 'oba_market', bl_now(), bl_now() + interval '4 seconds');
  update profiles set busy_until = bl_now() + interval '4 seconds', busy_label = 'Picking a pocket' where id = t2;
  perform pg_temp.advance(10);
  update profiles set last_seen = now() where id = v;
  perform pg_temp.login(t);
  r1 := steal_finish();
  perform pg_temp.login(t2);
  r2 := steal_finish();
  perform pg_temp.assert(r1->>'status' = 'success' and r2->>'status' = 'missed', 'one success only ' || r1::text || r2::text);
  v_cash := (select cash from profiles where id = v);
  perform pg_temp.assert(v_cash = 100000 - (r1->>'amount')::bigint, 'victim lost once');
  perform pg_temp.assert((select count(*) from ledger where user_id = v and reason = 'steal_loss'
                          and (meta->>'attempt_id')::bigint in (select id from crime_attempts where thief_id in (t, t2) and resolved_at = bl_now())) = 1,
                         'one victim ledger row');
  perform pg_temp.reset_players();
  raise notice 'ok 10: concurrent double steal safe';
end $$;

-- ---------- 11. admin ----------
do $$
declare t uuid := current_setting('c1.t'); v uuid := current_setting('c1.v'); adm uuid := current_setting('c1.adm');
        r jsonb; c jail_cases;
begin
  perform pg_temp.cfg('crime.steal_caught_pct', '100');
  perform pg_temp.advance(1000);
  perform pg_temp.steal(t, v);
  select * into c from jail_cases where user_id = t and status = 'open';
  perform pg_temp.assert(pg_temp.hint_of('select admin_jail_cases()') = 'not_admin', 'list refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_jail_release(%s, %L)', c.id, 'x')) = 'not_admin', 'release refused');
  perform pg_temp.login(adm);
  r := admin_jail_cases();
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(r->'rows') x where (x->>'id')::bigint = c.id and x->>'username' = 'C1_Thief'), 'listed ' || r::text);
  r := admin_jail_release(c.id, 'test release');
  perform pg_temp.assert((select status from jail_cases where id = c.id) = 'released'
                         and (select released_by from jail_cases where id = c.id) = adm
                         and (select jailed_until from profiles where id = t) is null, 'released');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'jail_release' and target_user = t and data->>'reason' = 'test release'), 'audited');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_jail_release(%s, %L)', c.id, 'x')) = 'not_found', 'twice');
  perform pg_temp.reset_players();
  raise notice 'ok 11: admin list / release / audit';
end $$;

-- ---------- 12. RLS ----------
do $$
declare t uuid := current_setting('c1.t'); v uuid := current_setting('c1.v'); n int; m int;
begin
  set local role authenticated;
  perform pg_temp.login(t);
  select count(*), count(*) filter (where user_id = t) into n, m from jail_cases;
  perform pg_temp.assert(n > 0 and n = m, 'thief reads only own cases');
  perform pg_temp.login(v);
  select count(*) into n from jail_cases;
  perform pg_temp.assert(n = 0, 'victim reads none');
  perform pg_temp.assert(pg_temp.hint_of('select count(*) from crime_attempts') <> 'ok', 'attempts hidden');
  perform pg_temp.assert(pg_temp.hint_of(format('update jail_cases set bail_amount = 1 where user_id = %L', t)) <> 'ok', 'no update');
  reset role;
  raise notice 'ok 12: RLS';
end $$;
reset role;
