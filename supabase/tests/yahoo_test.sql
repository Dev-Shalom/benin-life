-- 20261014000500 made Yahoo fairer (lower catch chances, laptop seized 35 %, half the balance taken). This file pins
-- the original Y1 numbers so its maths stays exact; group 14 at the end covers the fairer busts. Rolled back.
update yahoo_jobs set caught_pct = case id when 'chat_client' then 20 when 'romance_job' then 25 when 'big_job' then 35 when 'cash_out' then 32 else caught_pct end;
update game_config set value = '100' where key in ('yahoo.seize_laptop_pct', 'yahoo.confiscate_pct');
-- R3 skills (20261017000400) gate the Big job and cut the EFCC chance; this suite tests the Y1 maths with skills off (skills_test.sql covers them)
update game_config set value = 'false' where key = 'skills.enabled';
-- Y1 Yahoo lifestyle (20261012001600_yahoo.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/yahoo_test.sql
-- Time moves with bl.test_offset_seconds; rolls are pinned with bl.test_rand (bl_rand).
-- Groups: 1 grants / anon / helpers private · 2 prices + specs + jobs + ranks + config · 3 refusals (no laptop, wrong place,
-- no MiFi, no desk, weak laptop, switch) · 4 passes (MiFi / desk, cash then bank, stacking, ledger) · 5 odds per job with
-- laptop + charm modifiers · 6 a job pays into the dirty balance (timer, can't stop, not_yet, ledger) · 7 cooldowns ·
-- 8 cash out converts (partial / all / refusals) · 9 EFCC caught → efcc case, laptop seized, dirty confiscated, bail N50M,
-- escape 55 % (fail doubles, vanishing 30 %), EFCC receipt · 10 ranks + badge + VIP booth + hype · 11 Big job with a mid
-- laptop, payout bonus, speed · 12 any laptop counts for tech jobs · 13 RLS.
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

create or replace function pg_temp.qty(p_uid uuid, p_item text) returns int
language sql as $$ select coalesce((select qty from inventory where user_id = p_uid and item_id = p_item), 0); $$;

-- free, at home (or another place), online
create or replace function pg_temp.at(p_uid uuid, p_loc text default null) returns void
language sql as $$
  update profiles set location_id = coalesce(p_loc, home_location_id), travel_to = null, travel_mode = null, travel_started_at = null,
                      travel_arrives_at = null, busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = now(), rent_due_at = null
   where id = p_uid;
$$;

-- only this laptop in the bag
create or replace function pg_temp.laptop(p_uid uuid, p_item text) returns void
language plpgsql as $$
begin
  delete from inventory where user_id = p_uid and item_id in (select item_id from laptop_specs);
  if p_item is not null then perform bl_give_item(p_uid, p_item, 1); end if;
end $$;

-- run a job to the end with a pinned roll
create or replace function pg_temp.run(p_uid uuid, p_job text, p_rand text, p_amount bigint default null) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.login(p_uid);
  perform set_config('bl.test_rand', '', true);
  v := yahoo_job_start(p_job, p_amount);
  perform pg_temp.advance((v->>'seconds')::numeric + 1);
  perform set_config('bl.test_rand', p_rand, true);
  v := yahoo_finish();
  perform set_config('bl.test_rand', '', true);
  return v;
end $$;

create or replace function pg_temp.job(p_id text) returns yahoo_jobs
language sql as $$ select * from yahoo_jobs where id = p_id; $$;

-- ---------- setup ----------
do $$
declare
  adm uuid := pg_temp.new_user('y1_admin@yy.bl');
  a uuid := pg_temp.new_user('y1_a@yy.bl');
  b uuid := pg_temp.new_user('y1_b@yy.bl');
  c uuid := pg_temp.new_user('y1_c@yy.bl');
  u uuid;
  i int := 0;
begin
  perform set_config('y1.adm', adm::text, true); perform set_config('y1.a', a::text, true);
  perform set_config('y1.b', b::text, true); perform set_config('y1.c', c::text, true);
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  foreach u in array array[adm, a, b, c] loop
    i := i + 1;
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    perform pg_temp.login(u);
    perform create_profile_v2('Y1_P' || i, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home('ekenwan_face_me');
    perform pg_temp.at(u);
    perform bl_yahoo_row(u);
  end loop;
  update profiles set is_admin = true where id = adm;
  update profiles set created_at = now() - interval '30 days', protected_until = null, cash = 0, bank = 0 where id in (adm, a, b, c);
  delete from inventory where user_id in (adm, a, b, c);
  perform pg_temp.cfg('yahoo.enabled', 'true');
  perform pg_temp.cfg('yahoo.bail_base', '50000000');
  perform pg_temp.cfg('yahoo.escape_caught_pct', '55');
  perform pg_temp.cfg('yahoo.caught_floor_pct', '5');
  perform pg_temp.cfg('yahoo.cafe_locations', '"wifi_joint"');
  perform pg_temp.cfg('crime.escape_caught_pct', '52');
  perform pg_temp.cfg('crime.escape_time_mult', '2');
  perform pg_temp.cfg('crime.escape_bail_mult', '2');
  perform pg_temp.cfg('receipts.enabled', 'true');
  perform pg_temp.cfg('receipts.min_amount', '500000');
  perform pg_temp.cfg('club.weekend_price_mult', '1');
  update yahoo_jobs set active = true;
end $$;

-- ---------- 1. grants ----------
do $$
declare v_rpc text;
begin
  foreach v_rpc in array array['yahoo_status()', 'yahoo_buy_pass(text)', 'yahoo_job_start(text,bigint)', 'yahoo_finish()',
                               'admin_yahoo_player(uuid)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'auth may ' || v_rpc);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v_rpc)::regprocedure), 'secdef ' || v_rpc);
  end loop;
  foreach v_rpc in array array['bl_yahoo_num(text,numeric)', 'bl_yahoo_row(uuid,boolean)', 'bl_yahoo_laptop(uuid)', 'bl_yahoo_rank(uuid)',
                               'bl_yahoo_rank_at_least(uuid,text)', 'bl_yahoo_rank_public(uuid)', 'bl_yahoo_assert_rank(uuid,text)',
                               'bl_yahoo_caught_pct(uuid,yahoo_jobs,jsonb)', 'bl_yahoo_seconds(yahoo_jobs,jsonb)', 'bl_yahoo_where(profiles)',
                               'bl_yahoo_dirty(uuid,bigint,text,jsonb)', 'bl_yahoo_hype_amount(uuid,bigint)', 'bl_yahoo_resolve(bigint)',
                               'bl_escape_pct_peek(uuid)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'helper private ' || v_rpc);
  end loop;
  perform pg_temp.assert(not has_table_privilege('anon', 'public.yahoo_players', 'select'), 'anon no yahoo rows');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.yahoo_players', 'update')
                         and not has_table_privilege('authenticated', 'public.yahoo_players', 'insert'), 'no client writes');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.yahoo_runs', 'select'), 'runs server-only');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.yahoo_jobs', 'update')
                         and not has_table_privilege('authenticated', 'public.laptop_specs', 'update'), 'catalogues read-only');
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.laptop_specs', 'select'), 'specs readable');
  raise notice 'ok 1: grants / helpers private';
end $$;

-- anon is refused
set local role anon;
do $$
begin
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_status()') <> 'ok', 'anon refused yahoo_status');
end $$;
reset role;

-- ---------- 2. prices + specs ----------
do $$
begin
  perform pg_temp.assert((select price from items where id = 'iphone_18') = 2400000, 'iPhone 18 2.4M');
  perform pg_temp.assert((select name from items where id = 'iphone_18') = 'iPhone 18 (Burgundy)', 'iPhone name');
  perform pg_temp.assert((select count(*) from items where name ilike 'iphone%') = 1, 'only one iPhone');
  perform pg_temp.assert((select price from items where id = 'thinkpad_t480') = 280000, 'thinkpad');
  perform pg_temp.assert((select price from items where id = 'elitebook_840') = 330000, 'elitebook');
  perform pg_temp.assert((select price from items where id = 'dell_xps_13') = 1100000, 'xps');
  perform pg_temp.assert((select price from items where id = 'macbook_air_m4') = 1850000, 'mba');
  perform pg_temp.assert((select price from items where id = 'macbook_pro_m4') = 4350000, 'mbp');
  perform pg_temp.assert((select category from items where id = 'laptop') = 'laptop', 'old laptop in Laptops');
  perform pg_temp.assert((select tier from laptop_specs where item_id = 'laptop') = 0
                         and (select min(tier) from laptop_specs) = 0, 'old laptop weakest');
  perform pg_temp.assert((select count(*) from laptop_specs) = 6, '6 laptops');
  perform pg_temp.assert((select (seconds, pay_min, pay_max, caught_pct) = (20, 5000::bigint, 50000::bigint, 20::numeric) from yahoo_jobs where id = 'chat_client'), 'chat');
  perform pg_temp.assert((select (seconds, pay_min, pay_max, caught_pct) = (40, 50000::bigint, 400000::bigint, 25::numeric) from yahoo_jobs where id = 'romance_job'), 'romance');
  perform pg_temp.assert((select (seconds, pay_min, pay_max, caught_pct) = (60, 500000::bigint, 3000000::bigint, 35::numeric) from yahoo_jobs where id = 'big_job'), 'big');
  perform pg_temp.assert((select (seconds, caught_pct, kind) = (15, 32::numeric, 'cashout') from yahoo_jobs where id = 'cash_out'), 'cash out');
  perform pg_temp.assert(bl_yahoo_num('yahoo.mifi_price', 0) = 50000 and bl_yahoo_num('yahoo.mifi_days', 0) = 7, 'mifi 50k/week');
  perform pg_temp.assert(bl_yahoo_num('yahoo.desk_price', 0) = 5000 and bl_yahoo_num('yahoo.desk_hours', 0) = 24, 'desk 5k/day');
  perform pg_temp.assert(bl_yahoo_num('yahoo.bail_base', 0) = 50000000, 'bail 50M');
  perform pg_temp.assert(bl_yahoo_num('yahoo.escape_caught_pct', 0) = 55, 'escape 55');
  perform pg_temp.assert((select 'wifi_joint' = any (sold_at) from items where id = 'thinkpad_t480'), 'laptops at the cafe');
  raise notice 'ok 2: prices / specs / jobs / config';
end $$;

-- ---------- 3. refusals ----------
do $$
declare a uuid := current_setting('y1.a')::uuid;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a);
  perform pg_temp.laptop(a, null);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'no_laptop', 'laptop required');
  perform pg_temp.laptop(a, 'laptop');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'no_mifi', 'home needs mifi');
  perform pg_temp.at(a, 'wifi_joint');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'no_desk', 'cafe needs desk');
  perform pg_temp.at(a, 'oba_market');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'wrong_place', 'not at a market');
  update yahoo_players set mifi_until = bl_now() + interval '1 day' where user_id = a;
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'wrong_place', 'mifi only at home');
  perform pg_temp.at(a);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''big_job'')') = 'laptop_too_weak', 'tokunbo laptop: no big job');
  perform pg_temp.laptop(a, 'elitebook_840');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''big_job'')') = 'laptop_too_weak', 'elitebook: no big job');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''cash_out'')') = 'nothing_to_cash', 'nothing to cash: ' || pg_temp.hint_of('select yahoo_job_start(''cash_out'')'));
  perform pg_temp.cfg('yahoo.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'disabled', 'switch');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_buy_pass(''mifi'')') = 'disabled', 'switch pass');
  perform pg_temp.cfg('yahoo.enabled', 'true');
  update profiles set busy_until = bl_now() + interval '1 minute', busy_label = 'x' where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') <> 'ok', 'busy refused');
  perform pg_temp.at(a);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''nope'')') = 'bad_job', 'unknown job');
  update yahoo_players set mifi_until = null where user_id = a;
  raise notice 'ok 3: refusals';
end $$;

-- ---------- 4. passes ----------
do $$
declare a uuid := current_setting('y1.a')::uuid; v jsonb; v_until timestamptz;
begin
  perform pg_temp.login(a);
  update profiles set cash = 30000, bank = 40000 where id = a;
  v := yahoo_buy_pass('mifi');
  perform pg_temp.assert((select cash from profiles where id = a) = 0 and (select bank from profiles where id = a) = 20000, 'cash first then bank');
  select mifi_until into v_until from yahoo_players where user_id = a;
  perform pg_temp.assert(abs(extract(epoch from v_until - bl_now()) - 7 * 86400) < 5, 'mifi 7 days');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_buy_pass(''mifi'')') = 'not_enough_money', 'too poor');
  update profiles set cash = 60000 where id = a;
  perform yahoo_buy_pass('mifi');
  perform pg_temp.assert(abs(extract(epoch from (select mifi_until from yahoo_players where user_id = a) - bl_now()) - 14 * 86400) < 5, 'mifi stacks');
  perform yahoo_buy_pass('desk');
  perform pg_temp.assert(abs(extract(epoch from (select desk_until from yahoo_players where user_id = a) - bl_now()) - 86400) < 5, 'desk 1 day');
  perform pg_temp.assert((select cash from profiles where id = a) = 5000, 'desk 5k');
  perform pg_temp.assert((select bl_ledger_label(reason, meta) from ledger where user_id = a order by id desc limit 1) = 'Yahoo: Cybercafe desk', 'desk label');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and bl_ledger_label(reason, meta) = 'Yahoo: MiFi + data bundle'), 'mifi label');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_buy_pass(''x'')') = 'bad_pass', 'bad pass');
  update profiles set cash = 0, bank = 0 where id = a;
  raise notice 'ok 4: passes';
end $$;

-- ---------- 5. odds ----------
do $$
declare a uuid := current_setting('y1.a')::uuid; s jsonb; v_lap jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.laptop(a, 'laptop');
  v_lap := bl_yahoo_laptop(a);
  perform pg_temp.assert(bl_yahoo_caught_pct(a, pg_temp.job('chat_client'), v_lap) = 20, 'chat 20');
  perform pg_temp.assert(bl_yahoo_caught_pct(a, pg_temp.job('romance_job'), v_lap) = 25, 'romance 25');
  perform pg_temp.assert(bl_yahoo_caught_pct(a, pg_temp.job('big_job'), v_lap) = 35, 'big 35');
  perform pg_temp.assert(bl_yahoo_caught_pct(a, pg_temp.job('cash_out'), v_lap) = 32, 'cash out 32');
  perform pg_temp.laptop(a, 'macbook_pro_m4');
  v_lap := bl_yahoo_laptop(a);
  perform pg_temp.assert(v_lap->>'item_id' = 'macbook_pro_m4', 'best laptop');
  perform pg_temp.assert(bl_yahoo_caught_pct(a, pg_temp.job('big_job'), v_lap) = 27, 'MBP -8 pts');
  -- EFCC blindfold -15, road opener does nothing, bad luck +10
  insert into player_charms (user_id, kind, expires_at, data) values (a, 'efcc_blindfold', bl_now() + interval '1 day', '{"value": 15}');
  insert into player_charms (user_id, kind, expires_at, data) values (a, 'road_opener', bl_now() + interval '1 day', '{"value": 20}');
  perform pg_temp.assert(bl_yahoo_caught_pct(a, pg_temp.job('big_job'), v_lap) = 12, 'blindfold -15');
  perform pg_temp.assert(bl_yahoo_caught_pct(a, pg_temp.job('chat_client'), v_lap) = 5, 'floor 5');
  insert into player_charms (user_id, kind, expires_at, data) values (a, 'bad_luck', bl_now() + interval '1 day', '{"value": 1, "caught_pts": 10}');
  perform pg_temp.assert(bl_yahoo_caught_pct(a, pg_temp.job('big_job'), v_lap) = 22, 'bad luck +10');
  perform pg_temp.cfg('yahoo.caught_floor_pct', '0');
  perform pg_temp.assert(bl_yahoo_caught_pct(a, pg_temp.job('chat_client'), v_lap) = 7, 'no floor: 20-8-15+10');
  perform pg_temp.cfg('yahoo.caught_floor_pct', '5');
  delete from player_charms where user_id = a;
  s := yahoo_status();
  perform pg_temp.assert((select (x->>'caught_pct')::numeric from jsonb_array_elements(s->'jobs') x where x->>'id' = 'chat_client') = 12, 'status shows odds');
  perform pg_temp.assert((select (x->>'seconds')::int from jsonb_array_elements(s->'jobs') x where x->>'id' = 'chat_client') = 14, 'MBP 30% faster');
  perform pg_temp.assert((select (x->>'pay_max')::numeric from jsonb_array_elements(s->'jobs') x where x->>'id' = 'chat_client') = 65000, 'MBP +30% pay');
  raise notice 'ok 5: odds with laptops + charms';
end $$;

-- ---------- 6. a job pays into the dirty balance ----------
do $$
declare a uuid := current_setting('y1.a')::uuid; v jsonb; r jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a);
  perform pg_temp.laptop(a, 'laptop');
  update profiles set cash = 1000 where id = a;
  v := yahoo_job_start('chat_client');
  perform pg_temp.assert((v->>'seconds')::int = 20, '20 s');
  perform pg_temp.assert((select busy_label from profiles where id = a) = 'Yahoo: Chat a client', 'busy label');
  perform pg_temp.assert(pg_temp.hint_of('select activity_stop()') = 'not_stoppable', 'can''t stop');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_finish()') = 'not_yet', 'not yet');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''romance_job'')') <> 'ok', 'one job at a time');
  perform pg_temp.advance(21);
  perform set_config('bl.test_rand', '0.99', true);
  r := yahoo_finish();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(r->>'status' = 'paid', 'paid');
  perform pg_temp.assert((r->>'amount')::bigint between 5000 and 50000, 'chat pay range ' || (r->>'amount'));
  perform pg_temp.assert((r->>'amount')::bigint = 49600, 'rand .99 -> 49,600 (rounded to 100)');
  perform pg_temp.assert((select dirty from yahoo_players where user_id = a) = 49600, 'dirty balance');
  perform pg_temp.assert((select total_earned from yahoo_players where user_id = a) = 49600, 'earned');
  perform pg_temp.assert((select cash from profiles where id = a) = 1000, 'cash untouched');
  perform pg_temp.assert((select busy_label from profiles where id = a) is null, 'busy cleared');
  perform pg_temp.assert((select bl_yahoo_ledger_label(reason, meta) from yahoo_ledger where user_id = a order by id desc limit 1) = 'Yahoo: client paid · Chat a client', 'yahoo ledger');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_finish()') = 'no_run', 'nothing left');
  -- a job whose time ran out while away is finished by yahoo_status
  perform pg_temp.advance(60);
  perform yahoo_job_start('romance_job');
  perform pg_temp.advance(41);
  perform set_config('bl.test_rand', '0.5', true);
  r := yahoo_status();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(r->'resolved'->>'status' = 'paid' and r->'run' = 'null'::jsonb, 'status resolves');
  perform pg_temp.assert((r->'resolved'->>'amount')::bigint between 50000 and 400000, 'romance range');
  raise notice 'ok 6: job → dirty balance';
end $$;

-- ---------- 7. cooldowns ----------
do $$
declare a uuid := current_setting('y1.a')::uuid;
begin
  perform pg_temp.login(a);
  perform pg_temp.advance(200);
  perform pg_temp.run(a, 'chat_client', '0.99');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'cooldown', 'chat cooldown');
  perform pg_temp.advance(10);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'ok', 'after 30 s');
  perform pg_temp.advance(21);
  perform set_config('bl.test_rand', '0.99', true);
  perform yahoo_finish();
  perform set_config('bl.test_rand', '', true);
  update yahoo_jobs set cooldown_seconds = 1000 where id = 'chat_client';
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'cooldown', 'admin cooldown');
  update yahoo_jobs set cooldown_seconds = 30 where id = 'chat_client';
  raise notice 'ok 7: cooldowns';
end $$;

-- ---------- 8. cash out ----------
do $$
declare a uuid := current_setting('y1.a')::uuid; d bigint; r jsonb; c0 bigint;
begin
  perform pg_temp.login(a);
  perform pg_temp.advance(100);
  d := (select dirty from yahoo_players where user_id = a);
  c0 := (select cash from profiles where id = a);
  perform pg_temp.assert(pg_temp.hint_of(format('select yahoo_job_start(''cash_out'', %s)', d + 1)) = 'too_much', 'too much');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''cash_out'', 10)') = 'too_small', 'too small');
  r := pg_temp.run(a, 'cash_out', '0.99', 20000);
  perform pg_temp.assert(r->>'status' = 'cashed' and (r->>'amount')::bigint = 20000, 'partial cash out');
  perform pg_temp.assert((select dirty from yahoo_players where user_id = a) = d - 20000, 'dirty down');
  perform pg_temp.assert((select cash from profiles where id = a) = c0 + 20000, 'cash up');
  perform pg_temp.assert((select bl_ledger_label(reason, meta) from ledger where user_id = a order by id desc limit 1) = 'Cash out', 'ledger Cash out');
  perform pg_temp.assert((select bl_yahoo_ledger_label(reason, meta) from yahoo_ledger where user_id = a order by id desc limit 1) = 'Cash out', 'yahoo ledger Cash out');
  perform pg_temp.advance(61);
  r := pg_temp.run(a, 'cash_out', '0.99');
  perform pg_temp.assert((select dirty from yahoo_players where user_id = a) = 0, 'all cashed');
  perform pg_temp.assert((select cash from profiles where id = a) = c0 + d, 'all in cash');
  perform pg_temp.assert((r->>'seconds') is null and (r->>'status') = 'cashed', 'cashed');
  raise notice 'ok 8: cash out';
end $$;

-- ---------- 9. EFCC caught ----------
do $$
declare a uuid := current_setting('y1.a')::uuid; r jsonb; c jail_cases; v jsonb; d bigint;
begin
  perform pg_temp.login(a);
  perform pg_temp.advance(400);
  perform pg_temp.at(a);
  perform pg_temp.laptop(a, 'elitebook_840');
  perform pg_temp.run(a, 'chat_client', '0.99');                  -- some dirty money first
  d := (select dirty from yahoo_players where user_id = a);
  perform pg_temp.assert(d > 0, 'has dirty');
  perform pg_temp.advance(100);
  r := pg_temp.run(a, 'romance_job', '0.0');                      -- caught
  perform pg_temp.assert(r->>'status' = 'caught', 'caught');
  perform pg_temp.assert((r->>'seized')::bigint = d, 'seized all dirty');
  perform pg_temp.assert((select dirty from yahoo_players where user_id = a) = 0, 'dirty confiscated');
  perform pg_temp.assert(pg_temp.qty(a, 'elitebook_840') = 0, 'laptop seized');
  perform pg_temp.assert((select bl_yahoo_ledger_label(reason, meta) from yahoo_ledger where user_id = a order by id desc limit 1) = 'EFCC seized', 'EFCC seized label');
  select * into c from jail_cases where user_id = a and status = 'open';
  perform pg_temp.assert(c.kind = 'efcc' and c.bail_amount = 50000000 and c.jail_seconds = 90, 'efcc case ₦50M');
  perform pg_temp.assert(c.meta->>'laptop' = 'elitebook_840', 'case knows the laptop');
  perform pg_temp.assert((select jailed_until from profiles where id = a) = c.jail_until, 'jailed');
  perform pg_temp.assert((select location_id from profiles where id = a) = 'police_hq', 'held at HQ');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'efcc_caught'), 'player alert');
  perform pg_temp.assert(r->'case'->>'kind' = 'efcc' and (r->'case'->>'escape_caught_pct')::numeric = 55, 'popup json: efcc, escape 55');
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') <> 'ok', 'jailed can''t work');
  -- escape fails: time and bail double
  perform set_config('bl.test_rand', '0.1', true);
  v := jail_case_escape();
  perform pg_temp.assert(not (v->>'escaped')::boolean, 'escape caught (0.1 < 55%)');
  select * into c from jail_cases where id = c.id;
  perform pg_temp.assert(c.bail_amount = 100000000 and c.jail_seconds = 180, 'doubled: 180 s / ₦100M');
  -- 0.53 escapes a police case (52 %) but not an EFCC one (55 %)
  perform set_config('bl.test_rand', '0.53', true);
  v := jail_case_escape();
  perform pg_temp.assert(not (v->>'escaped')::boolean, '0.53 < 55: caught again');
  select * into c from jail_cases where id = c.id;
  perform pg_temp.assert(c.bail_amount = 200000000, '₦200M');
  -- vanishing charm still applies: 30 %
  insert into player_charms (user_id, kind, uses_left, data) values (a, 'vanishing', 3, '{"value": 30}');
  perform pg_temp.assert(bl_escape_pct_peek(a) = 30, 'vanishing 30');
  delete from player_charms where user_id = a;
  -- bail: bank first, EFCC receipt
  perform set_config('bl.test_rand', '', true);
  update profiles set bank = 200000000 where id = a;
  v := jail_case_bail();
  perform pg_temp.assert((select status from jail_cases where id = c.id) = 'bailed', 'bailed');
  perform pg_temp.assert((select item_name from receipts where user_id = a order by created_at desc limit 1) = 'Bail · EFCC', 'EFCC receipt');
  perform pg_temp.assert((select seller from receipts where user_id = a order by created_at desc limit 1) like 'EFCC%', 'EFCC seller');
  update profiles set bank = 0 where id = a;
  -- the police case still escapes at 52 %
  perform pg_temp.assert(bl_escape_pct_peek(a) = 52, 'no case: police 52');
  -- caught on a cash out: the amount is lost too
  perform pg_temp.at(a);
  perform pg_temp.laptop(a, 'laptop');
  perform pg_temp.advance(400);
  perform pg_temp.run(a, 'chat_client', '0.99');
  perform pg_temp.advance(100);
  r := pg_temp.run(a, 'cash_out', '0.0');
  perform pg_temp.assert(r->>'status' = 'caught' and (select dirty from yahoo_players where user_id = a) = 0, 'cash out caught: lost');
  perform pg_temp.assert(pg_temp.qty(a, 'laptop') = 0, 'cheap laptop seized too');
  perform pg_temp.assert((select busts from yahoo_players where user_id = a) = 2, '2 busts');
  update jail_cases set status = 'released' where user_id = a and status = 'open';
  perform pg_temp.at(a);
  raise notice 'ok 9: EFCC caught / seized / bail / escape';
end $$;

-- ---------- 10. ranks, badge, VIP booth, hype ----------
do $$
declare b uuid := current_setting('y1.b')::uuid; a uuid := current_setting('y1.a')::uuid;
begin
  perform pg_temp.login(b);
  perform bl_yahoo_row(b);
  perform pg_temp.assert(bl_yahoo_rank(b) = 'aspirant', 'aspirant');
  perform pg_temp.assert((get_public_profile(b)->'yahoo_rank') = 'null'::jsonb, 'no badge');
  update yahoo_players set total_earned = 999999 where user_id = b;
  perform pg_temp.assert(bl_yahoo_rank(b) = 'aspirant', 'below g-boy');
  update yahoo_players set total_earned = 1000000 where user_id = b;
  perform pg_temp.assert(bl_yahoo_rank(b) = 'g_boy', 'g-boy at 1M');
  perform pg_temp.assert(get_public_profile(b)->'yahoo_rank'->>'name' = 'G-boy', 'badge');
  perform pg_temp.assert(not bl_yahoo_rank_at_least(b, 'big_boy'), 'not big boy');
  -- the VIP booth (club open for the test)
  update locations set open_hour = null, close_hour = null where id = 'club_360';
  perform pg_temp.at(b, 'club_360');
  update profiles set cash = 300000 where id = b;
  perform pg_temp.assert(pg_temp.hint_of('select do_activity(''big_boy_booth'')') = 'yahoo_rank', 'booth needs Big Boy');
  update yahoo_players set total_earned = 10000000 where user_id = b;
  perform pg_temp.assert(bl_yahoo_rank(b) = 'big_boy' and bl_yahoo_rank_at_least(b, 'big_boy'), 'big boy at 10M');
  perform pg_temp.assert(pg_temp.hint_of('select do_activity(''big_boy_booth'')') = 'ok', 'booth open for Big Boy');
  update yahoo_players set total_earned = 50000000 where user_id = b;
  perform pg_temp.assert(bl_yahoo_rank(b) = 'chairman' and bl_yahoo_rank_at_least(b, 'big_boy'), 'chairman at 50M');
  -- hype: chairman +20 %, + iPhone 10 %
  perform pg_temp.assert(bl_yahoo_hype_amount(b, 100000) = 120000, 'chairman hype');
  perform bl_give_item(b, 'iphone_18', 1);
  perform pg_temp.assert(bl_yahoo_hype_amount(b, 100000) = 130000, 'iPhone hype');
  perform pg_temp.assert(bl_yahoo_hype_amount(a, 100000) = 100000, 'aspirant no hype');
  -- rank up event from a real job
  update yahoo_players set total_earned = 999000 where user_id = a;
  perform pg_temp.at(a);
  perform pg_temp.laptop(a, 'laptop');
  update yahoo_players set mifi_until = bl_now() + interval '1 day' where user_id = a;
  perform pg_temp.advance(400);
  perform pg_temp.run(a, 'chat_client', '0.99');
  perform pg_temp.assert(bl_yahoo_rank(a) = 'g_boy' and exists (select 1 from events where user_id = a and kind = 'yahoo_rank_up'), 'rank up event');
  update profiles set cash = 0 where id in (a, b);
  raise notice 'ok 10: ranks / badge / VIP booth / hype';
end $$;

-- ---------- 11. Big job with a mid laptop; desk at the cafe ----------
do $$
declare c uuid := current_setting('y1.c')::uuid; r jsonb; v jsonb;
begin
  perform pg_temp.login(c);
  perform pg_temp.laptop(c, 'dell_xps_13');
  perform pg_temp.at(c, 'wifi_joint');
  update profiles set cash = 5000 where id = c;
  perform yahoo_buy_pass('desk');
  v := yahoo_job_start('big_job');
  perform pg_temp.assert((v->>'seconds')::int = 51, 'XPS 15% faster: 51 s');
  perform pg_temp.assert((v->>'caught_pct')::numeric = 31, 'XPS -4 pts');
  perform pg_temp.advance(52);
  perform set_config('bl.test_rand', '0.99', true);
  r := yahoo_finish();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(r->>'status' = 'paid', 'big job paid');
  perform pg_temp.assert((r->>'amount')::bigint between 500000 and 3450000, 'big range with +15%');
  perform pg_temp.assert((r->>'amount')::bigint > 3000000, 'bonus above base max');
  perform pg_temp.assert((select place from yahoo_runs where user_id = c order by id desc limit 1) = 'cafe', 'cafe run');
  -- desk expires
  perform pg_temp.advance(86400);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'')') = 'no_desk', 'desk expired');
  raise notice 'ok 11: big job / bonus / speed / desk';
end $$;

-- ---------- 12. any laptop counts for tech jobs ----------
do $$
declare c uuid := current_setting('y1.c')::uuid; v_me profiles;
begin
  select * into v_me from profiles where id = c;
  perform pg_temp.laptop(c, 'macbook_air_m4');
  perform pg_temp.assert((select bool_and((x->>'met')::boolean) from jsonb_array_elements(bl_career_reqs(v_me, '{"item": "laptop"}', false)) x), 'MacBook counts as a laptop');
  perform pg_temp.laptop(c, null);
  perform pg_temp.assert(not (select bool_and((x->>'met')::boolean) from jsonb_array_elements(bl_career_reqs(v_me, '{"item": "laptop"}', false)) x), 'no laptop: not met');
  raise notice 'ok 12: tech career laptop';
end $$;

-- ---------- 13. RLS ----------
do $$
declare a uuid := current_setting('y1.a')::uuid; b uuid := current_setting('y1.b')::uuid; n int; m int;
begin
  perform pg_temp.login(b);
  set local role authenticated;
  select count(*) into n from yahoo_players where user_id = a;
  select count(*) into m from yahoo_ledger where user_id = a;
  reset role;
  perform pg_temp.assert(n = 0 and m = 0, 'can''t see other players'' yahoo rows');
  perform pg_temp.login(a);
  set local role authenticated;
  select count(*) into n from yahoo_players where user_id = a;
  reset role;
  perform pg_temp.assert(n = 1, 'own row visible');
  -- admin view
  perform pg_temp.login(current_setting('y1.adm')::uuid);
  perform pg_temp.assert(jsonb_array_length(admin_yahoo_player(a)->'runs') > 0, 'admin runs');
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_yahoo_player(%L)', a)) <> 'ok', 'non-admin refused');
  raise notice 'ok 13: RLS / admin';
end $$;

-- 14 fairer busts (20261014000500): laptop seized only on its own roll, only part of the yahoo balance taken.
do $$
declare a uuid := current_setting('y1.c')::uuid; d bigint; r jsonb;
begin
  update game_config set value = '0' where key = 'yahoo.seize_laptop_pct';
  update game_config set value = '50' where key = 'yahoo.confiscate_pct';
  perform pg_temp.login(a);
  perform pg_temp.advance(4000);
  perform pg_temp.at(a);
  perform pg_temp.laptop(a, 'elitebook_840');
  perform bl_yahoo_row(a, true);
  update yahoo_players set mifi_until = bl_now() + interval '30 days' where user_id = a;
  perform pg_temp.run(a, 'chat_client', '0.99');
  d := (select dirty from yahoo_players where user_id = a);
  perform pg_temp.advance(400);
  perform pg_temp.at(a);
  r := pg_temp.run(a, 'romance_job', '0.0');
  perform pg_temp.assert(r->>'status' = 'caught', 'fair: caught');
  perform pg_temp.assert((r->>'seized')::bigint = floor(d * 0.5), 'fair: half the balance taken');
  perform pg_temp.assert((select dirty from yahoo_players where user_id = a) = d - floor(d * 0.5), 'fair: half kept');
  perform pg_temp.assert(pg_temp.qty(a, 'elitebook_840') = 1, 'fair: laptop kept when the seize roll misses');
  raise notice 'ok 14: fairer EFCC busts';
end $$;
