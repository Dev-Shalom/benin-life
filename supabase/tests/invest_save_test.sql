-- I1 Invest & Save (20261014000200_invest_save.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/invest_save_test.sql
-- Time moves with bl.test_offset_seconds; rolls are pinned with bl.test_rand (bl_rand). One invest day = year_days*86400/365 s.
-- Groups: 1 grants / anon / helpers private · 2 setup · 3 savings accrual (time travel, partial / full withdraw, year_days) ·
-- 4 SafeLock early break loses interest, matured pays · 5 fixed deposit + T-bill rules · 6 bond (wobble band, coupon, sell) ·
-- 7 stocks (deterministic series, buy / sell with 0.5 % fee, whole shares, dividends) · 8 farm harvest + risk events + re-invest ·
-- 9 transport / POS / flat (daily income, breakdown, vacancy, sell back) · 10 land (breakdown, community %, levy pay / walk,
-- cooldown, unlimited plots, sell minus agent fee) · 11 crypto fractional · 12 refusals (insufficient bank, min / max, cash
-- is not used) · 13 receipts + ledger labels + overview · 14 RLS + anon · 15 concurrency / double spend · 16 admin tables.
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

-- advance by invest days
create or replace function pg_temp.advance_days(p_days numeric) returns void
language plpgsql as $$
begin
  perform pg_temp.advance(p_days * bl_inv_day());
end $$;

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.rand(p_val text) returns void
language sql as $$ select set_config('bl.test_rand', p_val, true); $$;

create or replace function pg_temp.bank(p_uid uuid) returns bigint
language sql as $$ select bank from profiles where id = p_uid; $$;

create or replace function pg_temp.setbank(p_uid uuid, p_amt bigint) returns void
language sql as $$ update profiles set bank = p_amt where id = p_uid; $$;

create or replace function pg_temp.at(p_uid uuid) returns void
language sql as $$
  update profiles set location_id = home_location_id, travel_to = null, travel_mode = null, travel_started_at = null,
                      travel_arrives_at = null, busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = now(), rent_due_at = null
   where id = p_uid;
$$;

create or replace function pg_temp.pos(p_uid uuid, p_ref text) returns invest_positions
language sql as $$ select * from invest_positions where user_id = p_uid and ref_id = p_ref order by id desc limit 1; $$;

create or replace function pg_temp.label_count(p_uid uuid, p_label text) returns int
language sql as $$ select count(*)::int from ledger where user_id = p_uid and account = 'bank' and bl_ledger_label(reason, meta) = p_label; $$;

-- ---------- 1. grants ----------
do $$
declare v_rpc text;
begin
  foreach v_rpc in array array['invest_overview()', 'invest_market_series(text,int,int)', 'invest_buy(text,bigint)', 'invest_withdraw(bigint,bigint)',
    'invest_collect(bigint,boolean)', 'invest_market_buy(text,numeric)', 'invest_market_sell(text,numeric)', 'invest_land_quote(text,int)',
    'invest_land_buy(text,int)', 'invest_land_levy(bigint,boolean)', 'invest_land_sell(text,int)'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'auth may ' || v_rpc);
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon may not ' || v_rpc);
  end loop;
  perform pg_temp.assert(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'bl\_inv\_%'
       and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))), 'bl_inv_* private');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.invest_positions', 'insert')
                         and not has_table_privilege('authenticated', 'public.invest_positions', 'update')
                         and not has_table_privilege('authenticated', 'public.invest_positions', 'delete'), 'no position writes');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.invest_prices', 'insert')
                         and not has_table_privilege('authenticated', 'public.invest_markets', 'update')
                         and not has_table_privilege('authenticated', 'public.invest_products', 'update'), 'catalogues read-only');
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.invest_prices', 'select')
                         and has_table_privilege('authenticated', 'public.invest_markets', 'select'), 'market tables readable');
  perform pg_temp.assert((select count(*) from invest_products) >= 23 and (select count(*) from invest_markets) >= 17, 'seeded');
  perform pg_temp.assert((select count(*) from game_config where category = 'invest') >= 6, 'invest settings');
  raise notice 'ok 1: grants / helpers private';
end $$;

-- ---------- 2. setup ----------
do $$
declare
  adm uuid := pg_temp.new_user('i1_admin@ii.bl');
  a uuid := pg_temp.new_user('i1_a@ii.bl');
  b uuid := pg_temp.new_user('i1_b@ii.bl');
  u uuid; i int := 0;
begin
  perform set_config('i1.adm', adm::text, true); perform set_config('i1.a', a::text, true); perform set_config('i1.b', b::text, true);
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  foreach u in array array[adm, a, b] loop
    i := i + 1;
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    perform pg_temp.login(u);
    perform create_profile_v2('I1_P' || i, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home('ekenwan_face_me');
    perform pg_temp.at(u);
  end loop;
  update profiles set is_admin = true where id = adm;
  update profiles set created_at = now() - interval '30 days', protected_until = null, cash = 1000000, bank = 0 where id in (adm, a, b);
  update profiles set bank = 5000000000 where id = a;
  perform pg_temp.cfg('invest.enabled', 'true');
  perform pg_temp.cfg('invest.year_days', '30');
  perform pg_temp.cfg('invest.land_deal_minutes', '10');
  perform pg_temp.cfg('invest.land_walk_cooldown_seconds', '30');
  perform pg_temp.cfg('receipts.enabled', 'true');
  perform pg_temp.cfg('receipts.min_amount', '500000');
  raise notice 'ok 2: setup';
end $$;

-- ---------- 3. savings accrual ----------
do $$
declare
  a uuid := current_setting('i1.a')::uuid; r jsonb; p invest_positions; v_b0 bigint; o jsonb; v_exp bigint;
begin
  perform pg_temp.login(a);
  v_b0 := pg_temp.bank(a);
  r := invest_buy('bronze_savings', 10000);
  perform pg_temp.assert(pg_temp.bank(a) = v_b0 - 10000, 'savings debited from bank, not cash');
  perform pg_temp.assert((select cash from profiles where id = a) = 1000000, 'cash untouched');
  -- half a game year (15 real days) at 10% = 5%
  perform pg_temp.advance(15 * 86400);
  p := pg_temp.pos(a, 'bronze_savings');
  v_exp := floor(10000 * 10.0 / 100 * 0.5);
  o := bl_inv_calc(p);
  perform pg_temp.assert((o->>'value')::bigint = 10000 + v_exp, 'half a year = 5% interest: ' || (o->>'value'));
  perform pg_temp.assert((o->>'exit_value')::bigint = (o->>'value')::bigint, 'withdraw any time, no penalty');
  -- partial withdraw takes interest first
  v_b0 := pg_temp.bank(a);
  r := invest_withdraw(p.id, 300);
  perform pg_temp.assert(pg_temp.bank(a) = v_b0 + 300 and (r->>'payout')::bigint = 300, 'partial withdraw paid');
  p := pg_temp.pos(a, 'bronze_savings');
  perform pg_temp.assert(p.qty = 10000 and p.accrued = v_exp - 300, 'interest taken first, principal intact');
  -- deposit more: interest so far is banked into accrued, then grows on the bigger base
  r := invest_buy('bronze_savings', 10000);
  p := pg_temp.pos(a, 'bronze_savings');
  perform pg_temp.assert(p.qty = 20000 and p.accrued = v_exp - 300, 'second deposit keeps accrued');
  perform pg_temp.advance(30 * 86400);
  o := bl_inv_calc(pg_temp.pos(a, 'bronze_savings'));
  perform pg_temp.assert((o->>'value')::bigint = 20000 + (v_exp - 300) + 2000, 'a full year on 20,000 at 10% = 2,000: ' || (o->>'value'));
  -- everything out
  v_b0 := pg_temp.bank(a);
  r := invest_withdraw(p.id, null);
  perform pg_temp.assert(pg_temp.bank(a) = v_b0 + (o->>'value')::bigint, 'full withdraw');
  perform pg_temp.assert(not exists (select 1 from invest_positions where id = p.id), 'position closed');
  -- game year is configurable: 3 real days per year = 10x faster
  perform pg_temp.cfg('invest.year_days', '3');
  r := invest_buy('bronze_savings', 100000);
  perform pg_temp.advance(3 * 86400);
  o := bl_inv_calc(pg_temp.pos(a, 'bronze_savings'));
  perform pg_temp.assert((o->>'value')::bigint = 110000, 'year_days=3: one year in 3 real days = 110,000: ' || (o->>'value'));
  r := invest_withdraw((o->>'id')::bigint, null);
  perform pg_temp.cfg('invest.year_days', '30');
  raise notice 'ok 3: savings accrual';
end $$;

-- ---------- 4. SafeLock ----------
do $$
declare
  a uuid := current_setting('i1.a')::uuid; r jsonb; p invest_positions; v_b0 bigint; o jsonb; v_day numeric := 30 * 86400 / 365.0; v_int bigint;
begin
  perform pg_temp.login(a);
  v_b0 := pg_temp.bank(a);
  r := invest_buy('safelock_30', 100000);
  p := pg_temp.pos(a, 'safelock_30');
  perform pg_temp.assert(p.matures_at is not null and abs(extract(epoch from p.matures_at - p.opened_at) - 30 * v_day) < 1, 'lock term 30 invest days');
  -- 10 invest days in: interest has accrued on paper but breaking early loses ALL of it
  perform pg_temp.advance_days(10);
  o := bl_inv_calc(p);
  v_int := floor(100000 * 18.0 / 100 * 10 * v_day / (30 * 86400));
  perform pg_temp.assert((o->>'value')::bigint = 100000 + v_int and (o->>'locked')::boolean, 'value shows accrued interest, locked');
  perform pg_temp.assert((o->>'exit_value')::bigint = 100000 and (o->>'forfeit')::bigint = v_int, 'break early = principal only');
  r := invest_withdraw(p.id);
  perform pg_temp.assert((r->>'payout')::bigint = 100000 and (r->>'forfeited')::bigint = v_int and (r->>'forfeited')::bigint > 0, 'early break pays principal, interest lost');
  perform pg_temp.assert(pg_temp.bank(a) = v_b0, 'bank back to start (no interest)');
  perform pg_temp.assert(pg_temp.label_count(a, 'Save: broke SafeLock 30 days') = 1, 'ledger label early break');
  -- full term: interest paid
  r := invest_buy('safelock_90', 200000);
  p := pg_temp.pos(a, 'safelock_90');
  perform pg_temp.advance_days(91);
  o := bl_inv_calc(p);
  v_int := floor(200000 * 22.0 / 100 * 90 * v_day / (30 * 86400));
  perform pg_temp.assert((o->>'matured')::boolean and (o->>'exit_value')::bigint = 200000 + v_int, 'matured SafeLock pays interest: ' || (o->>'exit_value'));
  v_b0 := pg_temp.bank(a);
  r := invest_withdraw(p.id);
  perform pg_temp.assert(pg_temp.bank(a) = v_b0 + 200000 + v_int, 'matured payout in bank');
  -- interest stops at maturity: leaving it longer earns nothing more
  r := invest_buy('safelock_7', 50000);
  p := pg_temp.pos(a, 'safelock_7');
  perform pg_temp.advance_days(300);
  perform pg_temp.assert((bl_inv_calc(p)->>'exit_value')::bigint = 50000 + floor(50000 * 15.0 / 100 * 7 * v_day / (30 * 86400)), 'interest capped at the term');
  r := invest_withdraw(p.id);
  raise notice 'ok 4: SafeLock';
end $$;

-- ---------- 5. fixed deposit + treasury bills ----------
do $$
declare
  a uuid := current_setting('i1.a')::uuid; r jsonb; p invest_positions; o jsonb; v_day numeric := 30 * 86400 / 365.0; v_int bigint; v_val bigint; v_fee bigint;
begin
  perform pg_temp.login(a);
  -- fixed deposit 30 d 16%: early exit loses interest
  r := invest_buy('fd_30', 100000);
  p := pg_temp.pos(a, 'fd_30');
  perform pg_temp.advance_days(15);
  r := invest_withdraw(p.id);
  perform pg_temp.assert((r->>'payout')::bigint = 100000 and (r->>'forfeited')::bigint > 0, 'FD early exit: principal only');
  r := invest_buy('fd_90', 100000);
  p := pg_temp.pos(a, 'fd_90');
  perform pg_temp.advance_days(90);
  r := invest_withdraw(p.id);
  perform pg_temp.assert((r->>'payout')::bigint = 100000 + floor(100000 * 19.0 / 100 * 90 * v_day / (30 * 86400)), 'FD 90 d matured pays 19%');
  -- T-bill 91 d 16%: early sell = interest so far minus 2 % fee
  r := invest_buy('tbill_91', 1000000);
  p := pg_temp.pos(a, 'tbill_91');
  perform pg_temp.assert((r->'position'->>'cost')::bigint = 1000000, 'tbill cost');
  perform pg_temp.advance_days(40);
  o := bl_inv_calc(p);
  v_int := floor(1000000 * 16.0 / 100 * 40 * v_day / (30 * 86400));
  v_val := 1000000 + v_int; v_fee := ceil(v_val * 0.02);
  perform pg_temp.assert((o->>'exit_fee')::bigint = v_fee and (o->>'exit_value')::bigint = v_val - v_fee, 'early sell: accrued interest minus 2% fee');
  r := invest_withdraw(p.id);
  perform pg_temp.assert((r->>'payout')::bigint = v_val - v_fee and (r->>'fee')::bigint = v_fee, 'tbill early payout');
  -- 182 d at 17.75 and 364 d at 21.85 at maturity, no fee
  r := invest_buy('tbill_182', 500000);
  p := pg_temp.pos(a, 'tbill_182');
  perform pg_temp.advance_days(182);
  r := invest_withdraw(p.id);
  perform pg_temp.assert((r->>'payout')::bigint = 500000 + floor(500000 * 17.75 / 100 * 182 * v_day / (30 * 86400)) and (r->>'fee')::bigint = 0, 'tbill 182 matured, no fee');
  r := invest_buy('tbill_364', 500000);
  p := pg_temp.pos(a, 'tbill_364');
  perform pg_temp.advance_days(364);
  r := invest_withdraw(p.id);
  perform pg_temp.assert((r->>'payout')::bigint = 500000 + floor(500000 * 21.85 / 100 * 364 * v_day / (30 * 86400)), 'tbill 364 matured at 21.85%');
  -- rates seeded as specified
  perform pg_temp.assert((select array_agg(rate_pct order by term_days) from invest_products where id in ('safelock_7', 'safelock_30', 'safelock_90')) = array[15, 18, 22]::numeric[], 'SafeLock rates');
  perform pg_temp.assert((select rate_pct from invest_products where id = 'mmf') = 18 and (select rate_pct from invest_products where id = 'fgn_bond') = 19, 'mmf + bond rates');
  raise notice 'ok 5: FD / T-bills';
end $$;

-- ---------- 6. bond ----------
do $$
declare
  a uuid := current_setting('i1.a')::uuid; r jsonb; p invest_positions; o jsonb; v_min numeric; v_max numeric; v_b0 bigint;
begin
  perform pg_temp.login(a);
  r := invest_buy('fgn_bond', 100000);
  p := pg_temp.pos(a, 'fgn_bond');
  perform pg_temp.assert(p.qty between 96000 and 104000, 'face value near the amount paid (price within 3%): ' || p.qty);
  perform pg_temp.advance(20 * 86400);
  perform bl_inv_price('fgn_bond');
  select min(price), max(price) into v_min, v_max from invest_prices where market_id = 'fgn_bond' and step >= floor(extract(epoch from bl_now() - interval '20 days') / 3600);
  perform pg_temp.assert(v_min >= 97 and v_max <= 103 and v_max > v_min, 'bond price wobbles inside +-3%: ' || v_min || '..' || v_max);
  -- coupon: a game year after buying, the value includes ~19% of face
  perform pg_temp.advance(10 * 86400);
  o := bl_inv_calc(pg_temp.pos(a, 'fgn_bond'));
  perform pg_temp.assert((o->>'value')::bigint > 100000 * 1.1, 'coupon accrues on face value: ' || (o->>'value'));
  -- partial then full sale
  v_b0 := pg_temp.bank(a);
  r := invest_withdraw(p.id, 20000);
  perform pg_temp.assert(pg_temp.bank(a) = v_b0 + 20000, 'partial bond sale');
  r := invest_withdraw(p.id, null);
  perform pg_temp.assert(not exists (select 1 from invest_positions where id = p.id), 'bond closed');
  raise notice 'ok 6: bond';
end $$;

-- ---------- 7. stocks ----------
do $$
declare
  a uuid := current_setting('i1.a')::uuid; r jsonb; p invest_positions; v_price numeric; v_gross bigint; v_fee bigint; v_b0 bigint; v_step bigint;
  v_before jsonb; v_after jsonb; v_ps numeric; v_down int;
begin
  perform pg_temp.login(a);
  -- deterministic series: delete the tail and extend again = identical rows
  perform bl_inv_price('stk_okomu');
  perform pg_temp.advance(3 * 86400);
  perform bl_inv_price('stk_okomu');
  select jsonb_agg(price order by step) into v_before from invest_prices where market_id = 'stk_okomu' and step > (select max(step) - 40 from invest_prices where market_id = 'stk_okomu');
  select max(step) - 20 into v_step from invest_prices where market_id = 'stk_okomu';
  delete from invest_prices where market_id = 'stk_okomu' and step > v_step;
  perform bl_inv_price('stk_okomu');
  select jsonb_agg(price order by step) into v_after from invest_prices where market_id = 'stk_okomu' and step > (select max(step) - 40 from invest_prices where market_id = 'stk_okomu');
  perform pg_temp.assert(v_before = v_after and jsonb_array_length(v_after) = 40, 'series is deterministic (re-generated tail identical)');
  -- prices go both ways
  perform bl_inv_price('stk_presco');
  select count(*) into v_down from invest_prices p1 join invest_prices p2 on p2.market_id = p1.market_id and p2.step = p1.step + 1
   where p1.market_id = 'stk_presco' and p2.price < p1.price;
  perform pg_temp.assert(v_down > 20, 'stock prices fall as well as rise: ' || v_down);
  -- buy 10 shares (2.7 -> 2: whole shares only)
  r := invest_market_buy('stk_okomu', 2.7);
  perform pg_temp.assert((r->>'qty')::numeric = 2, 'whole shares only');
  v_price := bl_inv_price('stk_okomu');
  r := invest_market_buy('stk_okomu', 8);
  v_gross := ceil(8 * v_price)::bigint; v_fee := ceil(v_gross * 0.005)::bigint;
  perform pg_temp.assert((r->>'gross')::bigint = v_gross and (r->>'fee')::bigint = v_fee and (r->>'price')::numeric = v_price, 'cost = price x qty + 0.5% fee');
  p := pg_temp.pos(a, 'stk_okomu');
  perform pg_temp.assert(p.qty = 10, 'ten shares held');
  perform pg_temp.assert(pg_temp.label_count(a, 'Invest: broker fee · Okomu Oil') = 2, 'broker fee ledger rows');
  perform pg_temp.assert(pg_temp.label_count(a, 'Invest: NGX Okomu Oil ×8') = 1, 'buy ledger label');
  -- time passes, price moves; sell 4
  perform pg_temp.advance(2 * 86400);
  v_price := bl_inv_price('stk_okomu');
  v_b0 := pg_temp.bank(a);
  r := invest_market_sell('stk_okomu', 4);
  v_gross := floor(4 * v_price)::bigint; v_fee := ceil(v_gross * 0.005)::bigint;
  perform pg_temp.assert((r->>'payout')::bigint = v_gross - v_fee and pg_temp.bank(a) >= v_b0 + v_gross - v_fee, 'sell payout = price x qty - fee (plus any dividend)');
  p := pg_temp.pos(a, 'stk_okomu');
  perform pg_temp.assert(p.qty = 6, 'six left');
  perform pg_temp.assert(pg_temp.hint_of('select invest_market_sell(''stk_okomu'', 7)') = 'bad_amount', 'cannot sell more than held');
  -- dividends: force one on the next few steps
  update invest_markets set dividend_chance_pct = 100, dividend_yield_pct = 3 where id = 'stk_okomu';
  v_b0 := pg_temp.bank(a);
  perform pg_temp.advance(3 * 3600);
  perform bl_inv_price('stk_okomu');
  perform invest_overview();
  select coalesce(sum(per_share), 0) into v_ps from invest_dividends where market_id = 'stk_okomu' and to_timestamp(step::double precision * 3600) > bl_now() - interval '4 hours';
  perform pg_temp.assert(v_ps > 0, 'dividends were generated');
  perform pg_temp.assert(pg_temp.bank(a) > v_b0 and (select count(*) from ledger where user_id = a and reason = 'invest_income' and bl_ledger_label(reason, meta) = 'Dividend: Okomu Oil') >= 1, 'holder was paid a dividend');
  -- second visit pays nothing twice
  v_b0 := pg_temp.bank(a);
  perform invest_overview();
  perform pg_temp.assert(pg_temp.bank(a) = v_b0, 'dividend not paid twice');
  update invest_markets set dividend_chance_pct = 0.25 where id = 'stk_okomu';
  r := invest_market_sell('stk_okomu', null);
  perform pg_temp.assert(not exists (select 1 from invest_positions where user_id = a and ref_id = 'stk_okomu'), 'sold out');
  raise notice 'ok 7: stocks';
end $$;

-- ---------- 8. farm ----------
do $$
declare
  a uuid := current_setting('i1.a')::uuid; r jsonb; p invest_positions; o jsonb; v_b0 bigint; v_gain numeric; v_gross bigint;
begin
  perform pg_temp.login(a);
  -- min gain roll
  perform pg_temp.rand('0');
  r := invest_buy('farm_poultry', 2);
  p := pg_temp.pos(a, 'farm_poultry');
  perform pg_temp.assert(p.cost = 300000 and (p.state->>'gain_pct')::numeric = 25, 'two units cost 300,000, gain rolled at the low end');
  -- sell back early at 80 %
  perform pg_temp.advance_days(10);
  o := bl_inv_calc(p);
  perform pg_temp.assert((o->>'exit_value')::bigint = 240000 and not (o->>'ready')::boolean, 'early sell-back at a discount');
  perform pg_temp.assert(pg_temp.hint_of(format('select invest_collect(%s)', p.id)) = 'not_ready', 'cannot harvest before the cycle ends');
  v_b0 := pg_temp.bank(a);
  r := invest_withdraw(p.id);
  perform pg_temp.assert(pg_temp.bank(a) = v_b0 + 240000, 'sold back for 240,000 (a loss)');
  -- good harvest: no risk events
  perform pg_temp.rand('1');
  r := invest_buy('farm_poultry', 2);
  p := pg_temp.pos(a, 'farm_poultry');
  v_gain := (p.state->>'gain_pct')::numeric;
  perform pg_temp.assert(v_gain between 25 and 35, 'gain between 25 and 35');
  perform pg_temp.advance_days(151);
  o := bl_inv_calc(p);
  perform pg_temp.assert((o->>'ready')::boolean, 'ready after the cycle');
  perform pg_temp.assert(pg_temp.hint_of(format('select invest_withdraw(%s)', p.id)) = 'ready', 'must harvest before selling a ready farm');
  perform pg_temp.rand('0.9999');
  v_b0 := pg_temp.bank(a);
  r := invest_collect(p.id);
  v_gross := floor(300000 * (1 + v_gain / 100));
  perform pg_temp.assert((r->>'payout')::bigint = v_gross and jsonb_array_length(r->'events') = 0 and pg_temp.bank(a) = v_b0 + v_gross, 'harvest pays cost x (1 + gain)');
  perform pg_temp.assert(not exists (select 1 from invest_positions where id = p.id), 'lot closed after harvest');
  perform pg_temp.assert(pg_temp.label_count(a, 'Harvest: poultry unit') = 1, 'harvest ledger label');
  -- bad harvest: bird flu (60 %) + theft (30 %) both hit => payout x 0.4 x 0.7
  perform pg_temp.rand('0');
  r := invest_buy('farm_poultry', 2);
  p := pg_temp.pos(a, 'farm_poultry');
  v_gain := (p.state->>'gain_pct')::numeric;
  perform pg_temp.advance_days(151);
  perform pg_temp.rand('0.0001');
  v_b0 := pg_temp.bank(a);
  r := invest_collect(p.id);
  v_gross := floor(300000 * (1 + v_gain / 100));
  perform pg_temp.assert(jsonb_array_length(r->'events') = 2, 'both risk events fired');
  perform pg_temp.assert((r->>'payout')::bigint = floor(v_gross * 0.4 * 0.7) and (r->>'payout')::bigint < 300000 and (r->>'profit')::bigint < 0, 'real loss: ' || (r->>'payout'));
  perform pg_temp.assert(pg_temp.bank(a) = v_b0 + (r->>'payout')::bigint, 'bank got the reduced payout');
  -- re-invest: capital stays in, only the profit comes out, new cycle
  perform pg_temp.rand('0');
  r := invest_buy('farm_cassava', 1);
  p := pg_temp.pos(a, 'farm_cassava');
  perform pg_temp.advance_days(271);
  perform pg_temp.rand('0.9999');
  v_b0 := pg_temp.bank(a);
  r := invest_collect(p.id, true);
  perform pg_temp.assert((r->>'reinvested')::boolean and pg_temp.bank(a) = v_b0 + floor(250000 * 1.30) - 250000, 'profit paid out, capital stays');
  p := pg_temp.pos(a, 'farm_cassava');
  perform pg_temp.assert(p.cost = 250000 and p.matures_at > bl_now() and (p.state->>'cycle')::int = 2, 'second cycle started');
  perform pg_temp.rand('1');
  r := invest_withdraw(p.id);
  perform pg_temp.rand('');
  raise notice 'ok 8: farms';
end $$;

-- ---------- 9. transport / POS / flat ----------
do $$
declare
  a uuid := current_setting('i1.a')::uuid; r jsonb; p invest_positions; o jsonb; v_b0 bigint; v_f numeric; v_before bigint;
begin
  perform pg_temp.login(a);
  perform pg_temp.rand('1');
  -- keke: daily income accrues, no events
  r := invest_buy('transport_keke', 1);
  p := pg_temp.pos(a, 'transport_keke');
  perform pg_temp.assert(p.cost = 2400000, 'keke price');
  o := bl_inv_calc(p);
  perform pg_temp.assert((o->>'exit_value')::bigint = floor(2400000 * 0.88), 'sell back at a depreciated price right away (88%)');
  perform pg_temp.advance_days(5.2);
  perform invest_overview();
  p := pg_temp.pos(a, 'transport_keke');
  perform pg_temp.assert(p.accrued = 5 * 3800, 'five days of income: ' || p.accrued);
  v_b0 := pg_temp.bank(a);
  r := invest_collect(p.id);
  perform pg_temp.assert((r->>'payout')::bigint = 19000 and pg_temp.bank(a) = v_b0 + 19000, 'collect daily income');
  perform pg_temp.assert(pg_temp.hint_of(format('select invest_collect(%s)', p.id)) = 'nothing', 'nothing more to collect');
  -- breakdown: a day with both events (repair 3.5 % of the price, police = that day's income lost)
  perform pg_temp.rand('0.0001');
  perform pg_temp.advance_days(1.2);
  perform invest_overview();
  p := pg_temp.pos(a, 'transport_keke');
  perform pg_temp.assert(p.accrued = 3800 - floor(2400000 * 0.035) - 3800, 'breakdown cost hit the keke: ' || p.accrued);
  perform pg_temp.assert((select count(*) from invest_log where user_id = a and kind = 'event') >= 2, 'events logged');
  perform pg_temp.assert((select count(*) from events where user_id = a and kind = 'invest') >= 1, 'player told');
  perform pg_temp.assert(pg_temp.hint_of(format('select invest_collect(%s)', p.id)) = 'nothing', 'negative balance: nothing to collect');
  -- value falls with repairs; selling returns resale + (negative) accrued
  perform pg_temp.rand('1');
  o := bl_inv_calc(p);
  perform pg_temp.assert((o->>'exit_value')::bigint < floor(2400000 * 0.88), 'repair bill reduces what you get');
  v_b0 := pg_temp.bank(a);
  r := invest_withdraw(p.id);
  perform pg_temp.assert(pg_temp.bank(a) - v_b0 = (r->>'payout')::bigint and (r->>'payout')::bigint > 0, 'sold');
  -- POS: fraud loss
  r := invest_buy('pos_stand', 2);
  p := pg_temp.pos(a, 'pos_stand');
  perform pg_temp.assert(p.cost = 900000, 'two POS stands');
  perform pg_temp.rand('0.0001');
  perform pg_temp.advance_days(1.2);
  perform invest_overview();
  p := pg_temp.pos(a, 'pos_stand');
  perform pg_temp.assert(p.accrued = 1200 - floor(900000 * 0.08) - 1200, 'POS fraud loses 8% of the cost and the network day: ' || p.accrued);
  perform pg_temp.rand('1');
  r := invest_withdraw(p.id);
  -- flat: price follows the property index, vacancy stops the rent
  r := invest_buy('flat_room', 1);
  p := pg_temp.pos(a, 'flat_room');
  v_f := bl_inv_price('property_index') / 1000;
  perform pg_temp.assert(p.cost = ceil(6000000 * v_f), 'flat price follows the index: ' || p.cost);
  perform pg_temp.rand('0.0001');
  perform pg_temp.advance_days(1.2);
  perform invest_overview();
  p := pg_temp.pos(a, 'flat_room');
  perform pg_temp.assert((p.state->>'vacant_until') is not null and (p.state->>'vacant_until')::timestamptz > bl_now(), 'vacancy month started');
  perform pg_temp.assert(p.accrued = 3200 - floor(p.cost * 0.04), 'rent that day minus repair: ' || p.accrued);
  v_before := p.accrued;
  perform pg_temp.rand('1');
  perform pg_temp.advance_days(10);
  perform invest_overview();
  p := pg_temp.pos(a, 'flat_room');
  perform pg_temp.assert(p.accrued = v_before, 'no rent while empty');
  perform pg_temp.advance_days(40);
  perform invest_overview();
  p := pg_temp.pos(a, 'flat_room');
  perform pg_temp.assert(p.accrued > v_before + 3200 * 5, 'rent comes back after the vacancy: ' || p.accrued);
  o := bl_inv_calc(p);
  perform pg_temp.assert((o->>'exit_fee')::bigint > 0, '3% agent fee on sale');
  r := invest_withdraw(p.id);
  perform pg_temp.assert((r->>'payout')::bigint > 0, 'flat sold');
  perform pg_temp.rand('');
  raise notice 'ok 9: transport / POS / flat';
end $$;

-- ---------- 10. land ----------
do $$
declare
  a uuid := current_setting('i1.a')::uuid; r jsonb; q jsonb; p invest_positions; v_b0 bigint; v_pp bigint; v_sub bigint; v_ag bigint; v_cm bigint; v_id bigint; v_levy bigint; i int;
begin
  perform pg_temp.login(a);
  perform pg_temp.rand('0.9999');
  q := invest_land_quote('land_ugbowo', 2);
  v_pp := bl_inv_price('land_ugbowo')::bigint;
  v_sub := v_pp * 2; v_ag := ceil(v_sub * 0.05); v_cm := ceil(v_sub * 0.07);
  perform pg_temp.assert((q->>'plot_price')::bigint = v_pp and (q->>'agent_fee')::bigint = v_ag and (q->>'community')::bigint = v_cm
                         and (q->>'total')::bigint = v_sub + v_ag + v_cm, 'quote breakdown: ' || q::text);
  perform pg_temp.assert((select community_pct from invest_markets where id = 'land_ekenwan') > (select community_pct from invest_markets where id = 'land_gra'), 'rougher areas ask for more');
  -- buy with no levy
  v_b0 := pg_temp.bank(a);
  r := invest_land_buy('land_ugbowo', 2);
  perform pg_temp.assert(r->>'status' = 'done' and (r->>'total')::bigint = v_sub + v_ag + v_cm and (r->>'levy')::bigint = 0, 'bought without a levy');
  perform pg_temp.assert(pg_temp.bank(a) = v_b0 - (v_sub + v_ag + v_cm), 'bank debited exactly the total');
  perform pg_temp.assert(r->'receipt'->>'kind' = 'invest', 'big buy issues a receipt');
  perform pg_temp.assert(pg_temp.label_count(a, 'Land: community settlement · Ugbowo') = 1 and pg_temp.label_count(a, 'Land: agent fee · Ugbowo') = 1
                         and pg_temp.label_count(a, 'Land: 2 plots · Ugbowo') = 1, 'three ledger rows with labels');
  p := pg_temp.pos(a, 'land_ugbowo');
  perform pg_temp.assert(p.qty = 2 and p.cost = v_sub + v_ag + v_cm, 'two plots, cost basis incl. fees');
  -- levy: pay it
  perform pg_temp.rand('0.0001');
  v_b0 := pg_temp.bank(a);
  r := invest_land_buy('land_sapele', 1);
  perform pg_temp.assert(r->>'status' = 'levy' and (r->>'levy')::bigint > 0, 'levy demanded: ' || r::text);
  perform pg_temp.assert(pg_temp.bank(a) = v_b0, 'nothing charged until the levy is settled');
  v_id := (r->>'deal_id')::bigint; v_levy := (r->>'levy')::bigint;
  perform pg_temp.assert(pg_temp.hint_of('select invest_land_buy(''land_sapele'', 1)') = 'pending', 'one open deal at a time');
  perform pg_temp.rand('0.9999');
  r := invest_land_levy(v_id, true);
  perform pg_temp.assert(r->>'status' = 'done' and (r->>'levy')::bigint = v_levy, 'levy paid, deal done');
  perform pg_temp.assert(pg_temp.bank(a) = v_b0 - (r->>'total')::bigint, 'plot + agent + community + levy debited');
  perform pg_temp.assert((r->>'total')::bigint = (r->>'subtotal')::bigint + (r->>'agent_fee')::bigint + (r->>'community')::bigint + v_levy, 'total adds up');
  perform pg_temp.assert(pg_temp.label_count(a, 'Land: development levy · Sapele Rd') = 1, 'levy ledger row');
  -- levy: walk away loses nothing, then a short wait
  perform pg_temp.rand('0.0001');
  v_b0 := pg_temp.bank(a);
  r := invest_land_buy('land_okhoro', 1);
  perform pg_temp.assert(r->>'status' = 'levy', 'levy again');
  r := invest_land_levy((r->>'deal_id')::bigint, false);
  perform pg_temp.assert(r->>'status' = 'walked' and pg_temp.bank(a) = v_b0, 'walked away: nothing lost');
  perform pg_temp.assert(not exists (select 1 from invest_positions where user_id = a and ref_id = 'land_okhoro'), 'no plot');
  perform pg_temp.rand('0.9999');
  perform pg_temp.assert(pg_temp.hint_of('select invest_land_buy(''land_okhoro'', 1)') = 'cooldown', 'short wait after walking away');
  perform pg_temp.advance(31);
  r := invest_land_buy('land_okhoro', 1);
  perform pg_temp.assert(r->>'status' = 'done', 'deal after the wait');
  -- deal expiry
  perform pg_temp.rand('0.0001');
  r := invest_land_buy('land_ekenwan', 1);
  v_id := (r->>'deal_id')::bigint;
  perform pg_temp.advance(11 * 60);
  perform pg_temp.assert(pg_temp.hint_of(format('select invest_land_levy(%s, true)', v_id)) = 'expired', 'cold deal refused');
  perform pg_temp.rand('0.9999');
  -- unlimited plots
  perform pg_temp.setbank(a, 900000000000);
  for i in 1 .. 4 loop
    r := invest_land_buy('land_ekenwan', 100);
  end loop;
  p := pg_temp.pos(a, 'land_ekenwan');
  perform pg_temp.assert(p.qty = 400, 'unlimited plots (400 held): ' || p.qty);
  perform pg_temp.assert(pg_temp.hint_of('select invest_land_quote(''land_ekenwan'', 101)') = 'bad_amount', 'per-deal cap');
  -- sell minus agent fee
  perform pg_temp.advance(3 * 86400);
  v_pp := bl_inv_price('land_ugbowo')::bigint;
  v_b0 := pg_temp.bank(a);
  r := invest_land_sell('land_ugbowo', 1);
  perform pg_temp.assert((r->>'gross')::bigint = v_pp and (r->>'agent_fee')::bigint = ceil(v_pp * 0.05) and (r->>'payout')::bigint = v_pp - ceil(v_pp * 0.05), 'sale = price - agent fee');
  perform pg_temp.assert(pg_temp.bank(a) = v_b0 + (r->>'payout')::bigint, 'bank credited');
  perform pg_temp.assert(pg_temp.label_count(a, 'Land: agent fee (sale) · Ugbowo') = 1 and pg_temp.label_count(a, 'Land: sold 1 plot · Ugbowo') = 1, 'sale ledger labels');
  perform pg_temp.assert(pg_temp.hint_of('select invest_land_sell(''land_ugbowo'', 5)') = 'bad_amount', 'cannot sell more plots than owned');
  r := invest_land_sell('land_ugbowo', 1);
  perform pg_temp.assert(not exists (select 1 from invest_positions where user_id = a and ref_id = 'land_ugbowo'), 'all plots sold');
  perform pg_temp.assert((select min(drift_pct_year) from invest_markets where kind = 'land') >= 20 and (select max(drift_pct_year) from invest_markets where kind = 'land') <= 35, 'land growth 20-35%');
  perform pg_temp.rand('');
  raise notice 'ok 10: land';
end $$;

-- ---------- 11. crypto ----------
do $$
declare
  a uuid := current_setting('i1.a')::uuid; r jsonb; p invest_positions; v_price numeric; v_gross bigint; v_fee bigint; v_q numeric; v_b0 bigint; v_min numeric; v_max numeric;
begin
  perform pg_temp.login(a);
  v_price := bl_inv_price('crypto_btc');
  v_b0 := pg_temp.bank(a);
  r := invest_market_buy('crypto_btc', 0.001234567891);
  v_q := 0.00123456;
  v_gross := ceil(v_q * v_price)::bigint; v_fee := ceil(v_gross * 0.008)::bigint;
  perform pg_temp.assert((r->>'qty')::numeric = v_q and (r->>'gross')::bigint = v_gross and (r->>'fee')::bigint = v_fee, 'fractional buy to 8 decimals, 0.8% fee');
  perform pg_temp.assert(pg_temp.bank(a) = v_b0 - v_gross - v_fee, 'bank debited');
  p := pg_temp.pos(a, 'crypto_btc');
  perform pg_temp.assert(p.qty = v_q, 'fractional holding');
  perform pg_temp.advance(5 * 86400);
  v_price := bl_inv_price('crypto_btc');
  r := invest_market_sell('crypto_btc', 0.0006);
  perform pg_temp.assert((r->>'gross')::bigint = floor(0.0006 * v_price) and (r->>'qty')::numeric = 0.0006, 'partial sell at the new price');
  perform pg_temp.assert(pg_temp.hint_of('select invest_market_sell(''crypto_btc'', 1)') = 'bad_amount', 'cannot sell more than held');
  perform pg_temp.assert(pg_temp.hint_of('select invest_market_buy(''crypto_btc'', 0.0000001)') = 'bad_amount', 'min size');
  -- own trend: swings a lot
  perform pg_temp.advance(25 * 86400);
  perform bl_inv_price('crypto_btc');
  select min(price), max(price) into v_min, v_max from invest_prices where market_id = 'crypto_btc';
  perform pg_temp.assert(v_max / v_min > 1.05, 'BTC moves a lot: ' || v_min || ' .. ' || v_max);
  r := invest_market_sell('crypto_btc');
  r := invest_market_buy('crypto_usdt', 10);
  perform pg_temp.assert((r->>'qty')::numeric = 10, 'usdt');
  r := invest_market_sell('crypto_usdt');
  raise notice 'ok 11: crypto';
end $$;

-- ---------- 12. refusals ----------
do $$
declare
  b uuid := current_setting('i1.b')::uuid; a uuid := current_setting('i1.a')::uuid;
begin
  perform pg_temp.login(b);
  perform pg_temp.assert((select cash from profiles where id = b) = 1000000 and pg_temp.bank(b) = 0, 'b has cash but no bank');
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''bronze_savings'', 5000)') = 'not_enough_bank', 'cash is not used: bank money only');
  perform pg_temp.assert(pg_temp.hint_of('select invest_market_buy(''stk_gtco'', 10)') = 'not_enough_bank', 'stock refused, bank empty');
  perform pg_temp.assert(pg_temp.hint_of('select invest_land_buy(''land_gra'', 1)') = 'not_enough_bank', 'land refused, bank empty');
  perform pg_temp.setbank(b, 100);
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''bronze_savings'', 100)') = 'bad_amount', 'below the minimum');
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''bronze_savings'', 0)') = 'bad_amount', 'zero refused');
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''bronze_savings'', -5)') = 'bad_amount', 'negative refused');
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''bronze_savings'', null)') = 'bad_amount', 'null refused');
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''nope'', 1000)') = 'bad_product', 'unknown product');
  perform pg_temp.setbank(b, 5000000);
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''farm_poultry'', 101)') = 'bad_amount', 'above the unit maximum');
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''tbill_91'', 10000)') = 'bad_amount', 'T-bill minimum 50,000');
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''bronze_savings'', 9000000000000000000)') <> 'ok', 'huge amount refused');
  perform pg_temp.assert(pg_temp.bank(b) = 5000000, 'refusals moved no money');
  perform pg_temp.assert(pg_temp.hint_of('select invest_withdraw(999999999, 100)') = 'bad_position', 'unknown holding');
  -- another player's holding is not mine
  perform pg_temp.login(a);
  perform invest_buy('bronze_savings', 1000);
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select invest_withdraw(%s, 100)', (select id from invest_positions where user_id = a limit 1))) = 'bad_position', 'cannot touch someone else''s holding');
  -- switch off: no new money in, still can take out
  perform pg_temp.login(a);
  perform pg_temp.cfg('invest.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''bronze_savings'', 1000)') = 'closed', 'switch refuses buys');
  perform invest_withdraw((select id from invest_positions where user_id = a and ref_id = 'bronze_savings'), null);
  perform pg_temp.cfg('invest.enabled', 'true');
  -- jailed players can't use the phone bank
  update profiles set jailed_until = bl_now() + interval '1 hour' where id = b;
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''bronze_savings'', 1000)') = 'jailed', 'jailed refused');
  update profiles set jailed_until = null where id = b;
  raise notice 'ok 12: refusals';
end $$;

-- ---------- 13. receipts + ledger labels + overview ----------
do $$
declare
  a uuid := current_setting('i1.a')::uuid; b uuid := current_setting('i1.b')::uuid; r jsonb; o jsonb; h jsonb;
begin
  perform pg_temp.login(b);
  r := invest_buy('bronze_savings', 100000);
  perform pg_temp.assert(not (r ? 'receipt'), 'no receipt under the receipts minimum');
  r := invest_buy('tbill_91', 600000);
  perform pg_temp.assert(r->'receipt'->>'kind' = 'invest' and (r->'receipt'->>'amount')::bigint = 600000, 'receipt for a big buy');
  perform pg_temp.assert(exists (select 1 from receipts where user_id = b and kind = 'invest'), 'receipt stored');
  o := invest_overview();
  perform pg_temp.assert(jsonb_array_length(o->'products') >= 23 and jsonb_array_length(o->'markets') >= 17 and jsonb_array_length(o->'positions') = 2, 'overview shape');
  perform pg_temp.assert((o->'summary'->>'invested')::bigint = 700000 and (o->'summary'->>'value')::bigint >= 700000, 'summary invested / value');
  perform pg_temp.assert((o->'summary'->>'profit')::bigint = (o->'summary'->>'value')::bigint - (o->'summary'->>'invested')::bigint + (o->'summary'->>'realized')::bigint, 'profit = value - invested + realized');
  perform pg_temp.assert(jsonb_array_length((select m->'spark' from jsonb_array_elements(o->'markets') m where m->>'id' = 'stk_mtnn')) >= 8, 'sparklines');
  r := invest_market_series('crypto_btc', 60, 48);
  perform pg_temp.assert(jsonb_array_length(r->'points') between 8 and 80 and (r->>'price')::numeric > 0, 'market series');
  h := bank_history(60);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(h) x where x->>'label' = 'Invest: Treasury bill 91 days'), 'bank history label Invest: Treasury bill');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(h) x where x->>'label' = 'Save: Bronze Savings'), 'bank history label Save');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and bl_ledger_label(reason, meta) like 'Land: community settlement%'), 'land community label');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and bl_ledger_label(reason, meta) like 'Harvest:%'), 'harvest label');
  raise notice 'ok 13: receipts / labels / overview';
end $$;

-- ---------- 14. RLS + anon ----------
do $$
declare a uuid := current_setting('i1.a')::uuid; b uuid := current_setting('i1.b')::uuid; n int; m int; k int;
begin
  perform pg_temp.login(a);
  perform invest_buy('mmf', 5000);
  perform pg_temp.login(b);
  set local role authenticated;
  select count(*) into n from invest_positions where user_id = a;
  select count(*) into m from invest_log where user_id = a;
  select count(*) into k from invest_land_deals where user_id = a;
  reset role;
  perform pg_temp.assert(n = 0 and m = 0 and k = 0, 'cannot read another player''s holdings, log or deals');
  set local role authenticated;
  select count(*) into n from invest_positions where user_id = b;
  select count(*) into m from invest_prices;
  select count(*) into k from invest_markets;
  perform pg_temp.assert(pg_temp.hint_of('insert into invest_positions (user_id, ref_id, kind, opened_at, last_at) values (''' || b || ''', ''x'', ''savings'', now(), now())') <> 'ok', 'no client insert');
  reset role;
  perform pg_temp.assert(n >= 1 and m > 100 and k >= 17, 'own rows + shared market tables readable');
end $$;
set local role anon;
do $$
begin
  perform pg_temp.assert(pg_temp.hint_of('select invest_overview()') like '%permission denied%', 'anon overview refused');
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''mmf'', 1000)') like '%permission denied%', 'anon buy refused');
  perform pg_temp.assert(pg_temp.hint_of('select count(*) from invest_positions') <> 'ok', 'anon table refused');
end $$;
reset role;
do $$ begin raise notice 'ok 14: RLS / anon'; end $$;

-- ---------- 15. concurrency / double spend ----------
do $$
declare
  b uuid := current_setting('i1.b')::uuid; v_def text; v_name text; n int;
begin
  perform pg_temp.login(b);
  perform pg_temp.setbank(b, 10000);
  perform invest_buy('bronze_savings', 7000);
  perform pg_temp.assert(pg_temp.hint_of('select invest_buy(''bronze_savings'', 7000)') = 'not_enough_bank', 'second spend refused');
  perform pg_temp.assert(pg_temp.bank(b) = 3000, 'bank never below zero: ' || pg_temp.bank(b));
  -- every mutating RPC takes the player row lock (bl_me() = select ... for update) and money only moves through bl_add_money
  v_def := pg_get_functiondef('public.bl_me_any()'::regprocedure);
  perform pg_temp.assert(position('for update' in lower(v_def)) > 0, 'bl_me locks the profile row (FOR UPDATE)');
  foreach v_name in array array['invest_buy', 'invest_withdraw', 'invest_collect', 'invest_market_buy', 'invest_market_sell', 'invest_land_buy', 'invest_land_levy', 'invest_land_sell'] loop
    v_def := lower(pg_get_functiondef(('public.' || v_name)::regproc));
    perform pg_temp.assert(position('bl_me()' in v_def) > 0, v_name || ' takes the player lock');
    perform pg_temp.assert(v_name = 'invest_land_buy' or position('for update' in v_def) > 0, v_name || ' locks its rows');
  end loop;
  perform pg_temp.assert(not exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                          where ns.nspname = 'public' and (p.proname like 'invest\_%' or p.proname like 'bl\_inv\_%')
                            and position('update profiles' in lower(pg_get_functiondef(p.oid))) > 0), 'no direct profile updates');
  perform pg_temp.assert(pg_temp.hint_of('insert into invest_positions (user_id, ref_id, kind, opened_at, last_at) values (''' || b || ''', ''bronze_savings'', ''savings'', now(), now())') <> 'ok', 'pooled positions unique per player');
  select count(*) into n from invest_positions where user_id = b and ref_id = 'bronze_savings';
  perform pg_temp.assert(n = 1, 'one savings row');
  raise notice 'ok 15: concurrency safety';
end $$;

-- ---------- 16. admin tables ----------
do $$
declare adm uuid := current_setting('i1.adm')::uuid; b uuid := current_setting('i1.b')::uuid; r jsonb;
begin
  perform pg_temp.login(adm);
  r := admin_row_upsert('invest_products', '{"id":"bronze_savings","rate_pct":12}'::jsonb);
  perform pg_temp.assert((select rate_pct from invest_products where id = 'bronze_savings') = 12, 'admin edits a rate');
  r := admin_row_upsert('invest_markets', '{"id":"land_gra","community_pct":6,"levy_chance_pct":50}'::jsonb);
  perform pg_temp.assert((select community_pct from invest_markets where id = 'land_gra') = 6, 'admin edits a land area');
  r := admin_row_upsert('invest_products', '{"id":"farm_test","kind":"farm","name":"Test farm","unit_price":1000,"cycle_days":10,"gain_min_pct":25,"gain_max_pct":40,"events":{"flood":{"label":"Flood","chance_pct":10,"loss_of":"cycle","loss_pct":50}}}'::jsonb);
  perform pg_temp.assert(exists (select 1 from invest_products where id = 'farm_test'), 'admin adds a product');
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''invest_markets'', ''{"id":"new_one","name":"x"}''::jsonb)') <> 'ok', 'markets cannot be inserted');
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''invest_products'', ''{"id":"mmf","rate_pct":99}''::jsonb)') <> 'ok', 'non-admin refused');
  raise notice 'ok 16: admin tables';
end $$;
