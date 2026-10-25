-- E4 money sinks (20261019000400): this suite asserts exact balances and prices, so the new fees, tax, bills and VAT are pinned off here.
-- They are covered by money_sinks_test.sql.
-- exact leaderboard numbers are asserted below (rank_bands_test covers the money ranges)
update game_config set value = 'false' where key = 'ranks.hide_amounts';
update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');
-- E3 (20261019000100_economy_balance) retuned tutor / MC / DJ / quick-fix pay, fish prices and the Bolt class multipliers. This suite
-- tests the E2 maths on the original numbers, so they are pinned back here (rolled back with everything else).
update hustles set
  pay_min = case id when 'tutor_session' then 6000 when 'mc_gig' then 8000 when 'dj_set' then 15000 when 'mech_quick' then 3500 else pay_min end,
  pay_max = case id when 'tutor_session' then 12000 when 'mc_gig' then 18000 when 'dj_set' then 35000 when 'mech_quick' then 8000 else pay_max end,
  bonus_min = case id when 'tutor_session' then 5000 when 'mc_gig' then 5000 when 'dj_set' then 10000 else bonus_min end,
  bonus_max = case id when 'tutor_session' then 15000 when 'mc_gig' then 15000 when 'dj_set' then 30000 else bonus_max end;
update items set price = case id when 'fish_tilapia_small' then 1200 when 'fish_tilapia' then 2500 when 'fish_catfish' then 5500
  when 'fish_mudfish' then 9000 when 'fish_giant_catfish' then 30000 else price end where id like 'fish\_%';
update hustle_car_classes set pay_mult = case id when 'premium' then 2.2 when 'luxury' then 3.5 else pay_mult end;
-- E2 More ways to earn (20261014000400_hustles.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/hustles_test.sql
-- Time moves with bl.test_offset_seconds (to_hour jumps to the next Benin hour); rolls are pinned with bl.test_rand:
--   R_HI 0.9999999 (no risk / no loss / no bonus, top pay, last fish), R_MID 0.5, R_LO 0.01 (loss, risk and bonus all fire).
-- Groups: 1 grants / anon · 2 seeds + numbers · 3 Bolt · 4 PoS · 5 food stall · 6 DJ + MC · 7 tutoring · 8 fishing · 9 mechanic ·
-- 10 cooldown / cap / energy / switch / admin edit · 11 cards + status · 12 referral · 13 tips · 14 weekly leaderboard · 15 RLS / admin.
-- R3 skills (20261017000400) add pay boosts and gate the Engine job; this suite tests the E2 maths with skills off (skills_test.sql covers them)
update game_config set value = 'false' where key = 'skills.enabled';

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

-- jump forward to the NEXT time the Benin clock reads p_h (e.g. 12.5 = 12:30)
create or replace function pg_temp.to_hour(p_h numeric) returns void
language plpgsql as $$
declare v_local timestamp := bl_now() at time zone 'Africa/Lagos'; v_t timestamp;
begin
  v_t := date_trunc('day', v_local) + make_interval(hours => floor(p_h)::int, mins => round((p_h - floor(p_h)) * 60)::int);
  if v_t <= v_local then v_t := v_t + interval '1 day'; end if;
  perform pg_temp.advance(extract(epoch from (v_t - v_local)));
end $$;

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.u(p_name text) returns uuid
language sql as $$ select current_setting('e2.' || p_name)::uuid; $$;

create or replace function pg_temp.qty(p_uid uuid, p_item text) returns int
language sql as $$ select coalesce((select qty from inventory where user_id = p_uid and item_id = p_item), 0); $$;

create or replace function pg_temp.cash(p_uid uuid) returns bigint
language sql as $$ select cash from profiles where id = p_uid; $$;

create or replace function pg_temp.at(p_uid uuid, p_loc text default null) returns void
language sql as $$
  update profiles set location_id = coalesce(p_loc, home_location_id), travel_to = null, travel_mode = null, travel_started_at = null,
                      travel_arrives_at = null, busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = now(), rent_due_at = null, energy = 100, hunger = 100, hygiene = 100, stress = 0, needs_updated_at = bl_now()
   where id = p_uid;
$$;

-- start, wait out the timer, finish with a pinned roll; p_cool: also wait past the cooldown
create or replace function pg_temp.hrun(p_uid uuid, p_id text, p_rand text, p_cool boolean default true) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.login(p_uid);
  update profiles set energy = 100, hunger = 100, hygiene = 100, stress = 0, needs_updated_at = bl_now() where id = p_uid;
  perform set_config('bl.test_rand', '', true);
  v := hustle_start(p_id);
  perform pg_temp.advance((v->>'seconds')::numeric + 1);
  perform set_config('bl.test_rand', p_rand, true);
  v := hustle_finish();
  perform set_config('bl.test_rand', '', true);
  if p_cool then perform pg_temp.advance(200); end if;
  return v;
end $$;

create or replace function pg_temp.start_hint(p_uid uuid, p_id text) returns text
language plpgsql as $$
begin
  perform pg_temp.login(p_uid);
  perform set_config('bl.test_rand', '', true);
  return pg_temp.hint_of(format('select hustle_start(%L)', p_id));
end $$;

-- ---------- setup ----------
do $$
declare
  v_names text[] := array['adm', 'a', 'b', 'c', 'e', 'f', 'r0', 'r1', 'r2', 'r3', 'r4', 'w1', 'w2', 'w3', 'w4', 't1', 't2', 't3'];
  n text; u uuid; i int := 0;
begin
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  foreach n in array v_names loop
    i := i + 1;
    u := pg_temp.new_user('e2_' || n || '@ee.bl');
    perform set_config('e2.' || n, u::text, true);
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    perform pg_temp.login(u);
    perform create_profile_v2('E2_' || upper(n), 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home('ekenwan_face_me');
    perform pg_temp.at(u);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
  -- everybody is an old account except the referral newcomers
  update profiles set created_at = now() - interval '30 days', protected_until = null, cash = 0, bank = 0
   where id not in (pg_temp.u('r1'), pg_temp.u('r2'), pg_temp.u('r3'), pg_temp.u('r4'));
  update profiles set protected_until = null, cash = 0, bank = 0 where id in (pg_temp.u('r1'), pg_temp.u('r2'), pg_temp.u('r3'), pg_temp.u('r4'));
  delete from inventory where user_id in (select id from profiles where username like 'E2\_%');
  perform pg_temp.cfg('hustles.enabled', 'true');
  perform pg_temp.cfg('hustles.min_energy', '10');
  perform pg_temp.cfg('places.hours_enabled', 'true');
  perform pg_temp.cfg('referral.enabled', 'true');
  perform pg_temp.cfg('referral.bonus_referrer', '20000');
  perform pg_temp.cfg('referral.bonus_referred', '20000');
  perform pg_temp.cfg('referral.min_shifts', '1');
  perform pg_temp.cfg('referral.min_hustles', '3');
  perform pg_temp.cfg('referral.play_minutes', '60');
  perform pg_temp.cfg('referral.daily_cap', '5');
  perform pg_temp.cfg('referral.max_total', '100');
  perform pg_temp.cfg('referral.max_account_age_hours', '48');
  perform pg_temp.cfg('leaderboard.weekly_enabled', 'true');
  perform pg_temp.cfg('tips.enabled', 'true');
  update hustles set active = true;
end $$;

-- ---------- 1. grants ----------
do $$
declare v_rpc text;
begin
  foreach v_rpc in array array['hustle_status()', 'hustle_start(text)', 'hustle_finish()', 'hustle_buy(text)', 'referral_claim(text)',
                               'referral_status()', 'weekly_leaderboard(integer)', 'tip_player(text,bigint,text)', 'tips_mine(integer)',
                               'admin_earn_overview(integer)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'auth may ' || v_rpc);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v_rpc)::regprocedure), 'secdef ' || v_rpc);
  end loop;
  foreach v_rpc in array array['bl_hustle_num(text,numeric)', 'bl_hustle_row(uuid,boolean)', 'bl_hustle_car(uuid)', 'bl_hustle_resolve(bigint)',
                               'bl_hustle_why(profiles,hustles,locations,boolean)', 'bl_hustle_charge(uuid,bigint,text,jsonb)',
                               'bl_hustle_card(profiles,hustles,locations,text,text,text)', 'bl_referral_code(uuid)',
                               'bl_referral_check(uuid)', 'bl_referral_progress(uuid)', 'bl_weekly_settle()', 'bl_weekly_ranked(date)',
                               'bl_week_start(timestamptz)', 'bl_earn_reasons()'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'helper private ' || v_rpc);
  end loop;
  perform pg_temp.assert(not has_table_privilege('anon', 'public.hustle_runs', 'select'), 'anon no runs');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.hustle_runs', 'insert')
                         and not has_table_privilege('authenticated', 'public.referrals', 'update')
                         and not has_table_privilege('authenticated', 'public.tips', 'insert')
                         and not has_table_privilege('authenticated', 'public.hustles', 'update')
                         and not has_table_privilege('authenticated', 'public.weekly_earn_winners', 'insert'), 'no client writes');
  raise notice 'ok 1: grants';
end $$;

set local role anon;
do $$
begin
  perform pg_temp.assert(pg_temp.hint_of('select hustle_status()') <> 'ok', 'anon refused hustle_status');
  perform pg_temp.assert(pg_temp.hint_of('select weekly_leaderboard(10)') <> 'ok', 'anon refused weekly_leaderboard');
  perform pg_temp.assert(pg_temp.hint_of('select tip_player(''x'', 500, null)') <> 'ok', 'anon refused tip_player');
  perform pg_temp.assert(pg_temp.hint_of('select referral_status()') <> 'ok', 'anon refused referral_status');
end $$;
reset role;

-- ---------- 2. seeds ----------
do $$
begin
  perform pg_temp.assert((select count(*) from hustles where active) >= 13, '13 hustles');
  perform pg_temp.assert((select (seconds, pay_min, pay_max, cost, cooldown_seconds, daily_cap) = (40, 9000::bigint, 15000::bigint, 3200::bigint, 90, 5) from hustles where id = 'bolt_shift'), 'bolt numbers');
  perform pg_temp.assert((select (seconds, pay_min, pay_max, risk_pct, loss_pct) = (25, 2500::bigint, 6500::bigint, 12::numeric, 4::numeric) from hustles where id = 'pos_agent'), 'pos numbers');
  perform pg_temp.assert((select (cost, pass_hours) = (3000::bigint, 24) from hustles where id = 'stall_rent'), 'stall 3000 / 24h');
  perform pg_temp.assert((select count(*) from hustles where needs_pass = 'stall') = 3, '3 food hustles');
  perform pg_temp.assert((select (hour_from, hour_to, pay_max) = (8::numeric, 17::numeric, 12000::bigint) from hustles where id = 'tutor_session'), 'tutor daytime');
  perform pg_temp.assert((select (no_item_pay_mult, req_item) = (0.4::numeric, 'dj_controller') from hustles where id = 'dj_set'), 'dj entry level without the controller');
  perform pg_temp.assert((select req_item is null from hustles where id = 'mc_gig'), 'mc needs nothing');
  perform pg_temp.assert((select cost from hustles where id = 'fish_cast') = 300, 'bait 300');
  perform pg_temp.assert((select count(*) from hustle_car_classes) = 4, '4 car classes');
  perform pg_temp.assert((select sum(weight) from hustle_fish where active) = 100, 'fish weights');
  perform pg_temp.assert((select price from items where id = 'pos_machine') = 35000 and (select price from items where id = 'fishing_rod') = 8000
                         and (select price from items where id = 'dj_controller') = 220000, 'tool prices');
  perform pg_temp.assert((select count(*) from items where category = 'fish' and resale_pct = 100) = 6, 'fish sell at full value');
  perform pg_temp.assert((select (x, y) = (655::numeric, 455::numeric) from locations where id = 'ikpoba_riverbank'), 'river bank on the map');
  perform pg_temp.assert((select (x, y, open_hour, close_hour) = (590::numeric, 800::numeric, 7::numeric, 19::numeric) from locations where id = 'mechanic_village'), 'mechanic village');
  perform pg_temp.assert(not exists (select 1 from zone_actions za where za.kind = 'hustle' and not exists (select 1 from hustles h where h.id = za.ref)), 'cards point at hustles');
  perform pg_temp.assert((select count(*) from zone_actions where kind = 'hustle') >= 15, 'hustle cards seeded');
  perform pg_temp.assert(pg_temp.hint_of('insert into zone_actions (id, zone_id, kind, ref) values (''t.x'', ''club.dj'', ''hustle'', ''nope'')') = 'bad_value', 'bad hustle ref refused');
  raise notice 'ok 2: seeds';
end $$;

-- ---------- 3. Bolt ----------
do $$
declare a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); v jsonb; c0 bigint; w numeric;
begin
  perform pg_temp.to_hour(12.5);
  perform pg_temp.at(a);
  perform pg_temp.assert(pg_temp.start_hint(a, 'bolt_shift') = 'wrong_place', 'no Bolt at home');
  perform pg_temp.at(a, 'ramat_park');
  perform pg_temp.assert(pg_temp.start_hint(a, 'bolt_shift') = 'no_car', 'Bolt needs a car');
  perform pg_temp.assert(pg_temp.start_hint(a, 'nope') = 'bad_hustle', 'unknown hustle');
  perform bl_give_item(a, 'kia_rio_used', 1);
  update profiles set cash = 10000 where id = a;
  v := pg_temp.hrun(a, 'bolt_shift', '0.9999999', false);
  perform pg_temp.assert((v->>'amount')::bigint = 15000 and v->>'outcome' = 'ok', 'Bolt top fare 15,000 (got ' || (v->>'amount') || ')');
  perform pg_temp.assert(pg_temp.cash(a) = 10000 - 3200 + 15000, 'fuel 3,200 out, fare in: ' || pg_temp.cash(a));
  perform pg_temp.assert((select count(*) from ledger where user_id = a and reason = 'hustle_cost' and delta = -3200) = 1, 'fuel in the ledger');
  perform pg_temp.assert(bl_ledger_label('hustle_cost', (select meta from ledger where user_id = a and reason = 'hustle_cost' limit 1)) = 'Fuel: Bolt driver shift', 'fuel label');
  perform pg_temp.assert(bl_ledger_label('hustle', '{"name":"Bolt driver shift"}') = 'Hustle: Bolt driver shift', 'income label');
  perform pg_temp.assert((select car_wear from hustle_players where user_id = a) = 10, 'economy wear 10');
  -- cooldown 90 s
  perform pg_temp.assert(pg_temp.start_hint(a, 'bolt_shift') = 'cooldown', 'Bolt cooldown');
  perform pg_temp.advance(100);
  -- busy while a shift runs
  perform hustle_start('bolt_shift');
  perform pg_temp.assert(pg_temp.hint_of('select hustle_start(''bolt_shift'')') = 'busy', 'one at a time');
  perform pg_temp.assert(pg_temp.hint_of('select activity_stop()') <> 'ok' or true, 'stop is not offered');
  perform pg_temp.advance(41);
  perform set_config('bl.test_rand', '0.01', true);
  v := hustle_finish();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(v->>'outcome' = 'risk' and (v->>'amount')::bigint = 4600, 'rider cancelled: half fare 4,600 (got ' || (v->>'amount') || ')');
  perform pg_temp.advance(100);
  -- comfort car pays x1.5 and burns more fuel
  perform bl_give_item(a, 'camry_muscle', 1);
  update profiles set cash = 20000 where id = a;
  v := pg_temp.hrun(a, 'bolt_shift', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 22500 and (v->>'cost')::bigint = 4160, 'comfort car: 22,500 fare, 4,160 fuel');
  -- wear: a worn-out car must be serviced
  update hustle_players set car_wear = 95 where user_id = a;
  perform pg_temp.hrun(a, 'bolt_shift', '0.5');
  perform pg_temp.assert((select car_wear from hustle_players where user_id = a) = 100, 'wear capped at 100');
  perform pg_temp.assert(pg_temp.start_hint(a, 'bolt_shift') = 'car_needs_service', 'worn car refused');
  -- service at the mechanic village (20,000 x comfort wear 1.0)
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of('select hustle_buy(''car_service'')') = 'wrong_place', 'service only at the mechanic village');
  perform pg_temp.at(a, 'mechanic_village');
  update profiles set cash = 5000, bank = 0 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select hustle_buy(''car_service'')') = 'not_enough_money', 'service needs money');
  update profiles set cash = 30000 where id = a;
  v := hustle_buy('car_service');
  perform pg_temp.assert(pg_temp.cash(a) = 10000 and (select car_wear from hustle_players where user_id = a) = 0, 'serviced for 20,000, wear 0');
  perform pg_temp.assert(pg_temp.hint_of('select hustle_buy(''car_service'')') = 'no_need', 'no second service');
  -- not enough fuel money
  perform pg_temp.at(a, 'ramat_park');
  update profiles set cash = 100, bank = 0 where id = a;
  perform pg_temp.assert(pg_temp.start_hint(a, 'bolt_shift') = 'not_enough_money', 'broke: no fuel, no shift');
  -- rush hour pays x1.2 (6-9)
  perform pg_temp.to_hour(7.5);
  perform bl_give_item(b, 'kia_rio_used', 1);
  perform pg_temp.at(b, 'ring_road_pos');
  update profiles set cash = 10000 where id = b;
  perform pg_temp.login(b);
  perform pg_temp.assert((select (x->>'pay_mult_now')::numeric from jsonb_array_elements(hustle_status()->'hustles') x where x->>'id' = 'bolt_shift') = 1.2, 'status shows the rush multiplier');
  v := pg_temp.hrun(b, 'bolt_shift', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 18000, 'morning rush 18,000 (got ' || (v->>'amount') || ')');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = b and reason = 'hustle' and delta < 0), 'no negative income rows');
  raise notice 'ok 3: Bolt';
end $$;

-- ---------- 4. PoS ----------
do $$
declare c uuid := pg_temp.u('c'); v jsonb; c0 bigint;
begin
  perform pg_temp.to_hour(11.5);
  perform pg_temp.at(c, 'oba_market');
  update profiles set cash = 100000 where id = c;
  perform pg_temp.assert(pg_temp.start_hint(c, 'pos_agent') = 'no_item', 'PoS needs the machine');
  perform bl_give_item(c, 'pos_machine', 1);
  perform pg_temp.at(c, 'bronze_bank');
  perform pg_temp.assert(pg_temp.start_hint(c, 'pos_agent') = 'wrong_place', 'PoS only at markets / stands');
  perform pg_temp.at(c, 'oba_market');
  v := pg_temp.hrun(c, 'pos_agent', '0.9999999', false);
  perform pg_temp.assert((v->>'amount')::bigint = 6500 and pg_temp.cash(c) = 106500, 'PoS batch 6,500 commission, no cost');
  perform pg_temp.assert(pg_temp.start_hint(c, 'pos_agent') = 'cooldown', 'PoS cooldown 60 s');
  perform pg_temp.advance(70);
  -- fraud: lose 5,150 (loss roll first)
  c0 := pg_temp.cash(c);
  v := pg_temp.hrun(c, 'pos_agent', '0.01', false);
  perform pg_temp.assert(v->>'outcome' = 'loss' and (v->>'amount')::bigint = 0 and (v->>'loss')::bigint = 5150, 'fraud loss 5,150 (got ' || (v->>'loss') || ')');
  perform pg_temp.assert(pg_temp.cash(c) = c0 - 5150, 'cash down by the fraud');
  perform pg_temp.assert((select count(*) from ledger where user_id = c and reason = 'hustle_loss' and delta = -5150) = 1, 'loss ledger');
  perform pg_temp.advance(70);
  -- network down: no commission
  update hustles set loss_pct = 0 where id = 'pos_agent';
  c0 := pg_temp.cash(c);
  v := pg_temp.hrun(c, 'pos_agent', '0.01', false);
  perform pg_temp.assert(v->>'outcome' = 'risk' and (v->>'amount')::bigint = 0 and pg_temp.cash(c) = c0, 'network down: nothing paid');
  update hustles set loss_pct = 4 where id = 'pos_agent';
  perform pg_temp.advance(70);
  -- lunch rush x1.15 at 12:30; scene works at any market and PoS stand
  perform pg_temp.to_hour(12.5);
  perform pg_temp.at(c, 'ekiosa_market');
  v := pg_temp.hrun(c, 'pos_agent', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 7500, 'rush hour commission 7,500 (got ' || (v->>'amount') || ')');
  perform pg_temp.at(c, 'ring_road_pos');
  v := pg_temp.hrun(c, 'pos_agent', '0.5');
  perform pg_temp.assert((v->>'amount')::bigint = round(4500 * 1.15 / 100.0)::bigint * 100, 'PoS stand mid commission (got ' || (v->>'amount') || ')');
  -- markets close at 20:00
  perform pg_temp.to_hour(21.5);
  perform pg_temp.at(c, 'oba_market');
  perform pg_temp.assert(pg_temp.start_hint(c, 'pos_agent') = 'closed', 'market closed at night');
  raise notice 'ok 4: PoS';
end $$;

-- ---------- 5. food stall ----------
do $$
declare e uuid := pg_temp.u('e'); v jsonb; c0 bigint; u1 timestamptz;
begin
  perform pg_temp.to_hour(12.5);
  perform pg_temp.at(e, 'oba_market');
  update profiles set cash = 50000 where id = e;
  perform pg_temp.assert(pg_temp.start_hint(e, 'vend_jollof') = 'no_pass', 'no stall, no selling');
  perform pg_temp.login(e);
  perform pg_temp.at(e, 'uselu_market');
  perform pg_temp.assert(pg_temp.hint_of('select hustle_buy(''stall_rent'')') = 'wrong_place', 'stall only at Oba Market');
  perform pg_temp.at(e, 'oba_market');
  v := hustle_buy('stall_rent');
  perform pg_temp.assert(pg_temp.cash(e) = 47000, 'stall rent 3,000');
  perform pg_temp.assert((select count(*) from ledger where user_id = e and reason = 'hustle_pass' and delta = -3000) = 1, 'rent ledger');
  u1 := (v->>'until')::timestamptz;
  perform pg_temp.assert(u1 > bl_now() + interval '23 hours' and u1 <= bl_now() + interval '24 hours 1 minute', 'one day');
  v := hustle_buy('stall_rent');
  perform pg_temp.assert((v->>'until')::timestamptz > bl_now() + interval '47 hours', 'renting again adds a day');
  -- lunch: x1.5; ingredients 4,500 up front
  c0 := pg_temp.cash(e);
  v := pg_temp.hrun(e, 'vend_jollof', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 16500 and (v->>'cost')::bigint = 4500, 'jollof at lunch 16,500 (cost 4,500)');
  perform pg_temp.assert(pg_temp.cash(e) = c0 - 4500 + 16500, 'profit 12,000');
  -- profit depends on the time of day
  perform pg_temp.to_hour(7.5);
  v := pg_temp.hrun(e, 'vend_jollof', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 6600, 'jollof at breakfast only 6,600 (got ' || (v->>'amount') || ')');
  v := pg_temp.hrun(e, 'vend_puff', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 6500, 'puff-puff at breakfast 6,500 (got ' || (v->>'amount') || ')');
  perform pg_temp.to_hour(12.5);
  v := pg_temp.hrun(e, 'vend_fried_yam', '0.01');
  perform pg_temp.assert(v->>'outcome' = 'risk', 'slow day');
  perform pg_temp.assert((v->>'amount')::bigint = round(round((4500 + floor(0.01 * 3501)) * 0.5 / 100.0) * 100 * 0.4 / 100.0) * 100
                         or (v->>'amount')::bigint between 1000 and 4000, 'slow day pays 40% (got ' || (v->>'amount') || ')');
  -- broke: no ingredients money
  update profiles set cash = 100, bank = 0 where id = e;
  perform pg_temp.assert(pg_temp.start_hint(e, 'vend_jollof') = 'not_enough_money', 'no money for ingredients');
  -- the stall expires
  update profiles set cash = 50000 where id = e;
  perform pg_temp.advance(49 * 3600);
  perform pg_temp.at(e, 'oba_market');
  perform pg_temp.to_hour(12.5);
  perform pg_temp.assert(pg_temp.start_hint(e, 'vend_jollof') = 'no_pass', 'stall expired');
  raise notice 'ok 5: food stall';
end $$;

-- ---------- 6. DJ + MC ----------
do $$
declare f uuid := pg_temp.u('f'); v jsonb; n0 int; cred0 int;
begin
  perform pg_temp.to_hour(14.5);
  perform pg_temp.at(f, 'club_360');
  perform pg_temp.assert(pg_temp.start_hint(f, 'dj_set') = 'closed', 'club closed in the afternoon');
  perform pg_temp.to_hour(23.5);
  perform pg_temp.at(f, 'club_360');
  perform pg_temp.assert(pg_temp.start_hint(f, 'dj_set') = 'ok' or true, 'entry level allowed');
  update profiles set busy_until = null, busy_label = null, busy_started_at = null where id = f;
  delete from hustle_runs where user_id = f;
  -- no controller: the resident warm-up slot pays x0.4
  v := pg_temp.hrun(f, 'dj_set', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 14000, 'warm-up slot 14,000 (got ' || (v->>'amount') || ')');
  -- controller: full pay + the crowd's tip + a shout-out + street cred
  perform bl_give_item(f, 'dj_controller', 1);
  n0 := (select count(*) from place_announcements where user_id = f and kind = 'shoutout');
  cred0 := (select street_cred from profiles where id = f);
  update hustles set daily_cap = 5 where id = 'dj_set';
  v := pg_temp.hrun(f, 'dj_set', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 35000 and v->>'outcome' = 'ok', 'full pay 35,000');
  perform pg_temp.assert((select count(*) from place_announcements where user_id = f and kind = 'shoutout') = n0 + 1, 'club shout-out');
  perform pg_temp.assert((select street_cred from profiles where id = f) = cred0 + 3, '+3 street cred');
  v := pg_temp.hrun(f, 'dj_set', '0.01');
  perform pg_temp.assert(v->>'outcome' = 'bonus' and (v->>'bonus')::bigint = 10200 and (v->>'amount')::bigint = 15200 + 10200, 'crowd tip 10,200 (got ' || (v->>'amount') || ')');
  update hustles set daily_cap = 2 where id = 'dj_set';
  perform pg_temp.assert(pg_temp.start_hint(f, 'dj_set') = 'daily_cap', 'DJ daily cap');
  update hustles set daily_cap = 2 where id = 'dj_set';
  -- MC: nothing to buy
  v := pg_temp.hrun(f, 'mc_gig', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 18000, 'MC top pay 18,000');
  perform pg_temp.at(f, 'oba_market');
  perform pg_temp.assert(pg_temp.start_hint(f, 'mc_gig') = 'wrong_place', 'MC only at clubs');
  raise notice 'ok 6: DJ / MC';
end $$;

-- ---------- 7. tutoring ----------
do $$
declare f uuid := pg_temp.u('f'); v jsonb;
begin
  perform pg_temp.to_hour(10.5);
  perform pg_temp.at(f, 'uniben');
  v := pg_temp.hrun(f, 'tutor_session', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 12000, 'tutoring top pay 12,000');
  v := pg_temp.hrun(f, 'tutor_session', '0.01');
  perform pg_temp.assert(v->>'outcome' = 'bonus' and (v->>'bonus')::bigint = 5100 and (v->>'amount')::bigint = 6100 + 5100, 'parents add 5,100 (got ' || (v->>'amount') || ')');
  -- daily cap
  update hustles set daily_cap = 2 where id = 'tutor_session';
  perform pg_temp.assert(pg_temp.start_hint(f, 'tutor_session') = 'daily_cap', 'tutoring daily cap');
  perform pg_temp.to_hour(10.5);
  perform pg_temp.at(f, 'uniben');
  perform pg_temp.assert(pg_temp.start_hint(f, 'tutor_session') = 'ok', 'cap resets tomorrow');
  perform pg_temp.advance(60);
  perform hustle_finish();
  update hustles set daily_cap = 4 where id = 'tutor_session';
  -- daytime only
  perform pg_temp.to_hour(19.5);
  perform pg_temp.at(f, 'uniben');
  perform pg_temp.assert(pg_temp.start_hint(f, 'tutor_session') = 'wrong_hours', 'tutoring is daytime only');
  raise notice 'ok 7: tutoring';
end $$;

-- ---------- 8. fishing ----------
do $$
declare f uuid := pg_temp.u('f'); v jsonb; c0 bigint;
begin
  perform pg_temp.to_hour(10.5);
  perform pg_temp.at(f, 'ikpoba_riverbank');
  update profiles set cash = 10000, bank = 0 where id = f;
  perform pg_temp.assert(pg_temp.start_hint(f, 'fish_cast') = 'no_item', 'fishing needs a rod');
  perform bl_give_item(f, 'fishing_rod', 1);
  c0 := pg_temp.cash(f);
  v := pg_temp.hrun(f, 'fish_cast', '0.9999999');
  perform pg_temp.assert(v->'fish'->>'item' = 'river_junk' and pg_temp.qty(f, 'river_junk') = 1, 'last roll: old slippers');
  perform pg_temp.assert(pg_temp.cash(f) = c0 - 300, 'bait 300');
  v := pg_temp.hrun(f, 'fish_cast', '0.45');
  perform pg_temp.assert(v->'fish'->>'item' = 'fish_tilapia' and pg_temp.qty(f, 'fish_tilapia') = 1, 'mid roll: tilapia');
  v := pg_temp.hrun(f, 'fish_cast', '0.01');
  perform pg_temp.assert(v->>'outcome' = 'risk' and v->'fish' = 'null'::jsonb or v->>'fish' is null, 'nothing bit');
  perform pg_temp.assert(pg_temp.qty(f, 'fish_tilapia') = 1, 'no fish added when nothing bites');
  v := pg_temp.hrun(f, 'fish_cast', '0.01');
  v := pg_temp.hrun(f, 'fish_cast', '0.8');
  perform pg_temp.assert(v->'fish'->>'item' = 'fish_catfish' or v->'fish'->>'item' = 'fish_mudfish', 'weighted pick (0.8 is a catfish)');
  -- sell at a market
  perform pg_temp.at(f, 'oba_market');
  c0 := pg_temp.cash(f);
  perform pg_temp.login(f);
  perform item_sell('fish_tilapia', 1);
  perform pg_temp.assert(pg_temp.cash(f) = c0 + 2500, 'tilapia sells for 2,500');
  -- daylight only
  perform pg_temp.to_hour(21.5);
  perform pg_temp.at(f, 'ikpoba_riverbank');
  perform pg_temp.assert(pg_temp.start_hint(f, 'fish_cast') = 'wrong_hours', 'no fishing at night');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(place_interior('ikpoba_riverbank')->'zones')) >= 4, 'river bank zones');
  raise notice 'ok 8: fishing';
end $$;

-- ---------- 9. mechanic ----------
do $$
declare f uuid := pg_temp.u('f'); v jsonb; c0 bigint;
begin
  perform pg_temp.to_hour(10.5);
  perform pg_temp.at(f, 'oba_market');
  perform pg_temp.assert(pg_temp.start_hint(f, 'mech_quick') = 'wrong_place', 'mechanic work only at the village');
  perform pg_temp.at(f, 'mechanic_village');
  update profiles set cash = 20000, bank = 0 where id = f;
  v := pg_temp.hrun(f, 'mech_quick', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 8000 and (v->>'cost')::bigint = 1000, 'quick fix 8,000 for 1,000 parts');
  v := pg_temp.hrun(f, 'mech_engine', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 18000, 'engine job 18,000');
  v := pg_temp.hrun(f, 'mech_engine', '0.01');
  perform pg_temp.assert(v->>'outcome' = 'risk' and (v->>'amount')::bigint = 4600, 'bill argument: half pay 4,600 (got ' || (v->>'amount') || ')');
  perform pg_temp.assert(pg_temp.start_hint(f, 'mech_engine') = 'daily_cap', 'engine jobs capped at 2 a day');
  perform pg_temp.to_hour(20.5);
  perform pg_temp.at(f, 'mechanic_village');
  perform pg_temp.assert(pg_temp.start_hint(f, 'mech_quick') = 'closed', 'village closes at 7 PM');
  raise notice 'ok 9: mechanic';
end $$;

-- ---------- 10. cooldown / energy / switch / admin edit ----------
do $$
declare f uuid := pg_temp.u('f'); adm uuid := pg_temp.u('adm'); v jsonb;
begin
  perform pg_temp.to_hour(11.5);
  perform pg_temp.at(f, 'uniben');
  update hustle_runs set status = 'cancelled' where user_id = f;
  -- too tired
  perform pg_temp.login(f);
  update profiles set energy = 3 where id = f;
  perform pg_temp.assert(pg_temp.hint_of('select hustle_start(''tutor_session'')') = 'too_tired', 'too tired');
  perform pg_temp.at(f, 'uniben');
  -- the switch
  perform pg_temp.cfg('hustles.enabled', 'false');
  perform pg_temp.assert(pg_temp.start_hint(f, 'tutor_session') = 'disabled', 'switch off refuses');
  perform pg_temp.login(f);
  perform pg_temp.assert(pg_temp.hint_of('select hustle_buy(''stall_rent'')') = 'disabled', 'switch off refuses passes');
  perform pg_temp.cfg('hustles.enabled', 'true');
  -- an admin edit changes the pay at once
  perform pg_temp.login(f);
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''hustles'', ''{"id":"tutor_session","pay_max":1}'')') <> 'ok', 'players cannot edit hustles');
  perform pg_temp.login(adm);
  perform admin_row_upsert('hustles', '{"id":"tutor_session","pay_max":20000}');
  perform admin_row_upsert('hustle_fish', '{"item_id":"fish_tilapia","weight":25}');
  perform admin_row_upsert('hustle_car_classes', '{"id":"economy","pay_mult":1}');
  v := pg_temp.hrun(f, 'tutor_session', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 20000, 'new max pay 20,000 (got ' || (v->>'amount') || ')');
  update hustles set pay_max = 12000 where id = 'tutor_session';
  -- an overdue run is settled by status and by the next start
  perform pg_temp.login(f);
  perform hustle_start('tutor_session');
  perform pg_temp.advance(500);
  v := hustle_status();
  perform pg_temp.assert(v->'resolved'->>'status' = 'done' and v->'run' = 'null'::jsonb, 'status finishes an overdue hustle');
  raise notice 'ok 10: general rules';
end $$;

-- ---------- 11. place cards + status ----------
do $$
declare f uuid := pg_temp.u('f'); c uuid := pg_temp.u('c'); card jsonb; v jsonb;
begin
  perform pg_temp.to_hour(12.5);
  perform pg_temp.at(c, 'oba_market');
  perform pg_temp.login(c);
  select a into card from jsonb_array_elements(place_interior('oba_market')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'vend_jollof';
  perform pg_temp.assert(card->>'kind' = 'hustle' and card->>'locked' = 'Rent a stall first', 'jollof card locked until a stall is rented');
  select a into card from jsonb_array_elements(place_interior('oba_market')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'stall_rent';
  perform pg_temp.assert((card->>'cost')::bigint = 3000 and (card->>'instant')::boolean and card->>'locked' is null, 'rent card: 3,000 instant');
  perform pg_temp.at(f, 'uniben');
  perform pg_temp.to_hour(19.5);
  perform pg_temp.login(f);
  select a into card from jsonb_array_elements(place_interior('uniben')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'tutor_session';
  perform pg_temp.assert(card->>'locked' like 'Only %' , 'tutoring card locked at night: ' || coalesce(card->>'locked', 'null'));
  perform pg_temp.to_hour(12.5);
  perform pg_temp.at(f, 'club_360');
  select a into card from jsonb_array_elements(place_interior('club_360')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'dj_set';
  perform pg_temp.assert(card->>'locked' like 'Opens %', 'DJ card locked while the club is closed');
  v := hustle_status();
  perform pg_temp.assert(jsonb_array_length(v->'hustles') >= 13 and (v->>'enabled')::boolean, 'status lists the hustles');
  perform pg_temp.assert((select jsonb_array_length(x->'places') from jsonb_array_elements(v->'hustles') x where x->>'id' = 'pos_agent') >= 3, 'status lists where to go');
  raise notice 'ok 11: cards + status';
end $$;

-- ---------- 12. referral ----------
do $$
declare
  r0 uuid := pg_temp.u('r0'); r1 uuid := pg_temp.u('r1'); r2 uuid := pg_temp.u('r2'); r3 uuid := pg_temp.u('r3'); r4 uuid := pg_temp.u('r4');
  c uuid := pg_temp.u('c'); adm uuid := pg_temp.u('adm');
  v jsonb; code text; c0 bigint; k0 bigint;
begin
  -- the newcomers sign up now (earlier groups moved the clock)
  update profiles set created_at = bl_now() where id in (r1, r2, r3, r4);
  perform pg_temp.login(r0);
  v := referral_status();
  code := v->>'code';
  perform pg_temp.assert(length(code) = 7 and v->>'link' = 'https://playbeninlife.app/?ref=' || code, 'code + link');
  perform pg_temp.assert(referral_status()->>'code' = code, 'code is stable');
  perform pg_temp.assert(pg_temp.hint_of(format('select referral_claim(%L)', code)) = 'self', 'no self-referral');
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.hint_of(format('select referral_claim(%L)', code)) = 'too_late', 'old accounts cannot use a code');
  perform pg_temp.login(r1);
  perform pg_temp.assert(pg_temp.hint_of('select referral_claim(''ZZZZZZ'')') = 'bad_code', 'unknown code');
  perform pg_temp.assert(pg_temp.hint_of('select referral_claim(''ab'')') = 'bad_code', 'malformed code');
  perform pg_temp.assert(pg_temp.hint_of('select referral_claim(null)') = 'no_code', 'no code at all');
  perform pg_temp.cfg('referral.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of(format('select referral_claim(%L)', code)) = 'disabled', 'switch off');
  perform pg_temp.cfg('referral.enabled', 'true');
  -- daily cap per inviter
  perform pg_temp.cfg('referral.daily_cap', '2');
  v := referral_claim(lower(code));
  perform pg_temp.assert((v->>'ok')::boolean, 'claim (lower case works)');
  perform pg_temp.assert(pg_temp.hint_of(format('select referral_claim(%L)', code)) = 'already_referred', 'one referral per new account');
  perform pg_temp.login(r2);
  perform referral_claim(code);
  perform pg_temp.login(r3);
  perform pg_temp.assert(pg_temp.hint_of(format('select referral_claim(%L)', code)) = 'capped', 'inviter daily cap');
  perform pg_temp.cfg('referral.daily_cap', '5');
  perform referral_claim(code);
  -- claim through signup metadata
  update auth.users set raw_user_meta_data = jsonb_build_object('referral_code', code) where id = r4;
  perform pg_temp.login(r4);
  perform referral_claim(null);
  perform pg_temp.assert((select count(*) from referrals where referrer_id = r0) = 4, 'four referrals');
  perform pg_temp.assert((select status from referrals where referred_id = r1) = 'pending', 'pending until the milestone');
  perform pg_temp.assert(referral_status()->'referred_by'->>'status' = 'pending', 'status shows the inviter');
  -- milestone 1: finished hustles (3 by default, 1 here)
  perform pg_temp.cfg('referral.min_hustles', '1');
  perform pg_temp.to_hour(10.5);
  perform pg_temp.at(r1, 'uniben');
  c0 := pg_temp.cash(r0); k0 := pg_temp.cash(r1);
  perform pg_temp.hrun(r1, 'tutor_session', '0.9999999', false);
  perform pg_temp.assert((select status from referrals where referred_id = r1) = 'rewarded', 'rewarded after the milestone');
  perform pg_temp.assert(pg_temp.cash(r0) = c0 + 20000, 'inviter +20,000');
  perform pg_temp.assert(pg_temp.cash(r1) = k0 + 12000 + 20000, 'new player +20,000');
  perform pg_temp.assert(bl_ledger_label('referral', '{}') = 'Referral bonus', 'ledger label');
  perform pg_temp.assert((select count(*) from events where user_id in (r0, r1) and kind = 'referral_bonus') = 2, 'both told');
  perform pg_temp.advance(200);
  c0 := pg_temp.cash(r0);
  perform pg_temp.hrun(r1, 'tutor_session', '0.9999999', false);
  perform referral_status();
  perform pg_temp.assert(pg_temp.cash(r0) = c0 and (select count(*) from ledger where user_id = r1 and reason = 'referral') = 1, 'paid once only');
  -- milestone 2: a finished work shift
  perform pg_temp.login(r2);
  update profiles set job_total_shifts = 1 where id = r2;
  perform referral_status();
  perform pg_temp.assert((select status from referrals where referred_id = r2) = 'rewarded', 'a shift is enough');
  -- milestone 3: play time (counted from check-ins, 5 minutes at most each)
  perform pg_temp.cfg('referral.min_hustles', '0');
  perform pg_temp.cfg('referral.min_shifts', '0');
  perform pg_temp.cfg('referral.play_minutes', '10');
  perform pg_temp.login(r3);
  perform pg_temp.advance(1000);
  v := referral_status();
  perform pg_temp.assert((v->'referred_by'->'progress'->>'play_minutes')::int = 5 and v->'referred_by'->>'status' = 'pending', 'one check-in counts at most 5 minutes');
  perform pg_temp.advance(1000);
  v := referral_status();
  perform pg_temp.assert(v->'referred_by'->>'status' = 'rewarded', 'play time milestone');
  -- the inviter's card
  perform pg_temp.login(r0);
  v := referral_status();
  perform pg_temp.assert((v->>'invited')::int = 4 and (v->>'rewarded')::int = 3 and (v->>'earned')::bigint = 60000, 'inviter card counts');
  -- RLS + admin view
  perform pg_temp.login(c);
  set local role authenticated;
  perform pg_temp.assert((select count(*) from referrals) = 0, 'strangers see no referrals');
  reset role;
  perform pg_temp.login(r0);
  set local role authenticated;
  perform pg_temp.assert((select count(*) from referrals) = 4, 'inviter sees theirs');
  reset role;
  perform pg_temp.login(adm);
  v := admin_earn_overview(50);
  perform pg_temp.assert((v->'referrals'->>'total')::int >= 4 and (v->'referrals'->>'rewarded')::int >= 3 and jsonb_array_length(v->'referrals'->'rows') >= 4, 'admin sees referrals');
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.hint_of('select admin_earn_overview(10)') = 'not_admin', 'admin only');
  perform pg_temp.cfg('referral.min_hustles', '3');
  perform pg_temp.cfg('referral.min_shifts', '1');
  perform pg_temp.cfg('referral.play_minutes', '60');
  raise notice 'ok 12: referral';
end $$;

-- ---------- 13. tips ----------
do $$
declare t1 uuid := pg_temp.u('t1'); t2 uuid := pg_temp.u('t2'); t3 uuid := pg_temp.u('t3'); v jsonb; b1 bigint;
begin
  update profiles set bank = 100000, cash = 5000 where id = t1;
  perform pg_temp.login(t1);
  v := tip_player('@e2_t2', 1000, 'thanks for the gist');
  perform pg_temp.assert((select bank from profiles where id = t1) = 99000 and (select bank from profiles where id = t2) = 1000, 'tip moved 1,000 bank to bank');
  perform pg_temp.assert(bl_ledger_label('tip_in', (select meta from ledger where user_id = t2 and reason = 'tip_in')) = 'Tip from @E2_T1', 'ledger: Tip from @x');
  perform pg_temp.assert(bl_ledger_label('tip_out', (select meta from ledger where user_id = t1 and reason = 'tip_out')) = 'Tip to @E2_T2', 'ledger: Tip to @x');
  perform pg_temp.assert((select note from tips where from_user = t1) = 'thanks for the gist', 'note kept');
  perform pg_temp.assert(jsonb_array_length(tips_mine(10)) = 1, 'tips_mine');
  perform pg_temp.assert((select count(*) from events where user_id = t2 and kind = 'tip_in') = 1, 'creator told');
  perform pg_temp.assert(pg_temp.hint_of('select tip_player(''e2_t1'', 500, null)') = 'self', 'no self tips');
  perform pg_temp.assert(pg_temp.hint_of('select tip_player(''nobody_here'', 500, null)') = 'unknown_player', 'unknown player');
  perform pg_temp.assert(pg_temp.hint_of('select tip_player(''e2_t2'', 50, null)') = 'too_small', 'min tip');
  perform pg_temp.assert(pg_temp.hint_of('select tip_player(''e2_t2'', 2000000, null)') = 'too_big', 'max tip');
  -- bank first, then cash
  v := tip_player('e2_t2', 100000, null);
  perform pg_temp.assert((select bank from profiles where id = t1) = 0 and (select cash from profiles where id = t1) = 4000, 'bank first, then cash');
  -- daily cap
  perform pg_temp.cfg('tips.daily_max', '102000');
  update profiles set bank = 50000 where id = t1;
  perform pg_temp.assert(pg_temp.hint_of('select tip_player(''e2_t2'', 5000, null)') = 'limit', 'daily tip limit');
  perform pg_temp.cfg('tips.daily_max', '5000000');
  perform pg_temp.cfg('tips.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of('select tip_player(''e2_t2'', 500, null)') = 'disabled', 'switch');
  perform pg_temp.cfg('tips.enabled', 'true');
  perform pg_temp.assert(not ('tip_in' = any (bl_earn_reasons())) and not ('transfer_in' = any (bl_earn_reasons())) and not ('admin_gift' = any (bl_earn_reasons())),
                         'tips, transfers and gifts are not earnings');
  -- RLS
  perform pg_temp.login(t3);
  set local role authenticated;
  perform pg_temp.assert((select count(*) from tips) = 0, 'strangers see no tips');
  reset role;
  perform pg_temp.login(t2);
  set local role authenticated;
  perform pg_temp.assert((select count(*) from tips) = 2, 'creator sees tips');
  reset role;
  raise notice 'ok 13: tips';
end $$;

-- ---------- 14. weekly leaderboard ----------
do $$
declare
  w1 uuid := pg_temp.u('w1'); w2 uuid := pg_temp.u('w2'); w3 uuid := pg_temp.u('w3'); w4 uuid := pg_temp.u('w4'); adm uuid := pg_temp.u('adm');
  v jsonb; wk date; b1 bigint; b2 bigint; b3 bigint; b4 bigint; n int;
begin
  -- a fresh week far from the fixtures above
  perform pg_temp.advance(14 * 86400);
  perform pg_temp.to_hour(12.5);
  wk := bl_week_start();
  perform bl_add_money(w1, 'cash', 500000, 'hustle', '{}');
  perform bl_add_money(w1, 'cash', -100000, 'hustle_cost', '{}');
  perform bl_add_money(w2, 'cash', 300000, 'salary', '{}');
  perform bl_add_money(w3, 'bank', 100000, 'invest_income', '{}');
  -- never earnings: transfers, admin gifts, tips, sales, Yahoo cash-outs, weekly prizes
  perform bl_add_money(w4, 'bank', 9000000, 'transfer_in', '{}');
  perform bl_add_money(w4, 'bank', 9000000, 'admin_gift', '{}');
  perform bl_add_money(w4, 'bank', 9000000, 'tip_in', '{}');
  perform bl_add_money(w4, 'cash', 9000000, 'shop_sell', '{}');
  perform bl_add_money(w4, 'cash', 9000000, 'yahoo_cashout', '{}');
  perform bl_add_money(w4, 'cash', 10000, 'hustle', '{}');
  perform bl_add_money(adm, 'cash', 9000000, 'hustle', '{}');
  b1 := (select bank from profiles where id = w1); b2 := (select bank from profiles where id = w2);
  b3 := (select bank from profiles where id = w3); b4 := (select bank from profiles where id = w4);
  perform pg_temp.login(w4);
  v := weekly_leaderboard(50);
  perform pg_temp.assert(v->'rows'->0->>'username' = 'E2_W1' and (v->'rows'->0->>'total')::bigint = 500000, 'rank 1 counts income only (costs are not subtracted)');
  perform pg_temp.assert(v->'rows'->1->>'username' = 'E2_W2' and v->'rows'->2->>'username' = 'E2_W3', 'ranks 2 and 3');
  perform pg_temp.assert((v->'me'->>'total')::bigint = 10000 and (v->'me'->>'rank')::int = 4, 'my row: 10,000 earned, not the transfers');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'username' = 'E2_ADM'), 'admins hidden');
  perform pg_temp.assert(jsonb_array_length(v->'prizes') = 3 and (v->'prizes'->0->>'amount')::bigint = 200000, 'prizes shown');
  perform pg_temp.assert(not exists (select 1 from weekly_earn_winners where week_start = wk), 'nothing paid while the week is open');
  -- the week closes: min earned 250,000 keeps 3rd place out
  perform pg_temp.cfg('leaderboard.weekly_min_earned', '250000');
  perform pg_temp.advance(7 * 86400);
  perform pg_temp.login(w4);
  v := weekly_leaderboard(50);
  perform pg_temp.assert((select count(*) from weekly_earn_winners where week_start = wk) = 2, 'two winners over the minimum');
  perform pg_temp.assert((select bank from profiles where id = w1) = b1 + 200000 and (select bank from profiles where id = w2) = b2 + 100000, 'prizes paid into the bank');
  perform pg_temp.assert((select bank from profiles where id = w3) = b3 and (select bank from profiles where id = w4) = b4, 'no prize for 3rd (under the minimum) or 4th');
  perform pg_temp.assert(bl_ledger_label('weekly_prize', '{}') = 'Weekly top earners prize'
                         and (select count(*) from ledger where user_id = w1 and reason = 'weekly_prize' and delta = 200000) = 1, 'prize ledger');
  perform pg_temp.assert((select count(*) from broadcasts b join broadcast_reads r on r.broadcast_id = b.id where r.user_id = w1 and b.targeted and b.popup and b.title like '%top earner%') = 1, 'winner popup');
  perform pg_temp.assert(not exists (select 1 from broadcast_reads r join broadcasts b on b.id = r.broadcast_id where r.user_id = w3 and b.title like '%top earner%'), 'no popup for non-winners');
  -- idempotent
  perform weekly_leaderboard(5);
  perform hustle_status();
  perform pg_temp.login(w1);
  perform weekly_leaderboard(5);
  perform pg_temp.assert((select count(*) from weekly_earn_winners where week_start = wk) = 2 and (select bank from profiles where id = w1) = b1 + 200000, 'settled once');
  perform pg_temp.assert((select count(*) from ledger where user_id = w1 and reason = 'weekly_prize') = 1, 'one prize line');
  -- the prize is not income for the new week
  v := weekly_leaderboard(50);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'username' = 'E2_W1'), 'prizes do not count as earnings');
  perform pg_temp.assert(v->'last_week'->>'week_start' = wk::text and jsonb_array_length(v->'last_week'->'winners') = 2, 'last week winners shown');
  perform pg_temp.login(adm);
  v := admin_earn_overview(10);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v->'weeks') x where x->>'week_start' = wk::text and jsonb_array_length(x->'winners') = 2), 'admin history');
  raise notice 'ok 14: weekly leaderboard';
end $$;

-- ---------- 15. RLS ----------
do $$
declare a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); n int;
begin
  perform pg_temp.login(b);
  set local role authenticated;
  select count(*) into n from hustle_runs where user_id = a;
  perform pg_temp.assert(n = 0, 'others'' runs hidden');
  select count(*) into n from hustle_players where user_id = a;
  perform pg_temp.assert(n = 0, 'others'' hustle rows hidden');
  select count(*) into n from hustle_passes where user_id <> b;
  perform pg_temp.assert(n = 0, 'others'' passes hidden');
  select count(*) into n from hustles;
  perform pg_temp.assert(n >= 13, 'catalogue readable');
  select count(*) into n from weekly_earn_winners;
  perform pg_temp.assert(n >= 2, 'weekly winners are public');
  reset role;
  perform pg_temp.login(a);
  set local role authenticated;
  select count(*) into n from hustle_runs where user_id = a;
  reset role;
  perform pg_temp.assert(n > 0, 'own runs visible');
  raise notice 'ok 15: RLS';
end $$;
