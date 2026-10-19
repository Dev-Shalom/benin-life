-- E4 money sinks (20261019000400_money_sinks.sql). Rolled back. Run (migration applied):
--   bash scripts/sql-test.sh -- supabase/tests/money_sinks_test.sql
-- Or with the migration first: bash scripts/sql-test.sh supabase/migrations/20261019000400_money_sinks.sql -- supabase/tests/money_sinks_test.sql
-- Groups: 1 grants / RLS / settings / ledger reasons never earned · 2 transfer fee (tiers, stamp duty, soft cap, preview, tips, switch off) ·
-- 3 weekly income tax (bands, receipt, owed + earnings pay first, never negative, 7-day exemption, switch) · 4 tax holiday policy ·
-- 5 bills (issued, manual pay, autopay, late fee, blocked only after the long window, business paused, never negative) ·
-- 6 VAT (included, food exempt, luxury levy, furniture, boutique) · 7 prestige (donate + board + badge + XP, city party, Chief title) ·
-- 8 money is destroyed (supply drops by exactly the sinks) · 9 Economy dashboard matches the ledger · 10 nothing negative.
-- Time travel with bl.test_offset_seconds. Markets / shops are pinned open.
update public.locations set open_hour = null, close_hour = null where id in ('bronze_tech_hub', 'benin_city_mall', 'mama_osas_buka', 'ighodalo_cars', 'oba_market');

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
create or replace function pg_temp.bank(p_uid uuid) returns bigint language sql as $$ select bank from profiles where id = p_uid $$;
create or replace function pg_temp.cash(p_uid uuid) returns bigint language sql as $$ select cash from profiles where id = p_uid $$;
create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;
create or replace function pg_temp.advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;
-- jump to a given moment (seconds from the real now)
create or replace function pg_temp.travel_to(p_at timestamptz) returns void
language plpgsql as $$
begin
  perform set_config('bl.test_offset_seconds', extract(epoch from p_at - now())::text, true);
end $$;
create or replace function pg_temp.mk(p_name text, p_age_days int default 30) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@sinks.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, busy_until = null, travel_to = null, protected_until = null, created_at = bl_now() - make_interval(days => p_age_days),
         cash = 0, bank = 0, energy = 100, hunger = 100, hygiene = 100, fun = 50, social = 100, health = 100, stress = 0, bladder = 0,
         needs_updated_at = bl_now(), jailed_until = null, hospitalized_until = null where id = v;
  return v;
end $$;
create or replace function pg_temp.at(p_uid uuid, p_loc text) returns void
language sql as $$ update profiles set location_id = p_loc, travel_to = null, busy_until = null, busy_label = null, last_seen = bl_now() where id = p_uid $$;
create or replace function pg_temp.ledger_sum(p_uid uuid, p_reason text) returns bigint
language sql as $$ select coalesce(sum(delta), 0)::bigint from ledger where user_id = p_uid and reason = p_reason $$;
-- every player's cash + bank among the test users
create or replace function pg_temp.pocket(p_ids uuid[]) returns bigint
language sql as $$ select coalesce(sum(cash + bank), 0)::bigint from profiles where id = any (p_ids) $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  -- keep the earlier E4-independent behaviour while we turn on the pieces we test, one at a time
  perform pg_temp.cfg('economy.transfer_fees_enabled', 'true');
  perform pg_temp.cfg('economy.tax_enabled', 'true');
  perform pg_temp.cfg('economy.bills_enabled', 'true');
  perform pg_temp.cfg('economy.vat_enabled', 'true');
  perform pg_temp.cfg('economy.luxury_enabled', 'true');
  perform pg_temp.cfg('economy.prestige_enabled', 'true');
  perform pg_temp.cfg('bank.transfer_fee', '50');
  perform pg_temp.cfg('bank.transfer_cooldown_real_seconds', '15');
  perform pg_temp.cfg('bank.transfer_daily_limit', '200000');
  perform pg_temp.cfg('bank.transfer_daily_count', '10');
  perform pg_temp.cfg('bank.transfer_min_account_real_minutes', '1440');
  perform pg_temp.cfg('tips.max_amount', '100000');
  perform pg_temp.cfg('tips.daily_max', '300000');
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,hustle,harvest,farm_harvest,invest_income,business_income,crew_payout,office_salary"');
end $$;

-- ---------- 1. grants / RLS / settings / reasons ----------
do $$
declare f text;
begin
  foreach f in array array['bank_transfer_quote(bigint,text)', 'tax_info()', 'bank_sinks()', 'bills_pay(bigint)', 'bills_pay_all()', 'tax_pay(bigint)', 'donate_city(bigint)',
    'donors_top(int)', 'city_party_status()', 'city_party_throw()', 'chief_titles()', 'chief_title_buy(int,text)', 'admin_economy_overview(int)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute'), 'anon cannot run ' || f);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute'), 'authenticated can run ' || f);
  end loop;
  foreach f in array array['bl_sinks_settle(uuid)', 'bl_tax_calc(bigint)', 'bl_tax_settle_week(uuid,date)', 'bl_tax_garnish(uuid,text,bigint,text)', 'bl_bills_issue(uuid,date)',
    'bl_bills_collect(uuid)', 'bl_sink_pay(uuid,bigint,text,jsonb)', 'bl_sink_take(uuid,bigint,text,jsonb)', 'bl_transfer_fee_calc(bigint,bigint,text)', 'bl_gross(text,text,bigint)',
    'bl_tax_split(text,text,bigint)', 'bl_pay_gross(uuid,bigint,bigint,text,jsonb,bigint,bigint)', 'bl_sink_blocked(uuid,text,text)', 'bl_party_join(uuid,text)',
    'bl_econ_num(text,numeric)', 'bl_econ_category(text)', 'bl_dealer_net(items,text)', 'bl_chief_title(uuid)', 'bl_donor_badge(uuid)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute')
                           and not has_function_privilege('authenticated', 'public.' || f, 'execute'), 'private helper locked: ' || f);
  end loop;
  foreach f in array array['player_bills', 'tax_records', 'city_donors', 'city_parties', 'city_party_guests', 'chief_titles'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || f)::regclass), 'RLS on ' || f);
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || f, 'select'), 'anon cannot read ' || f);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || f, 'insert') and not has_table_privilege('authenticated', 'public.' || f, 'update')
                           and not has_table_privilege('authenticated', 'public.' || f, 'delete'), 'no client writes on ' || f);
  end loop;
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.player_bills', 'select') and has_table_privilege('authenticated', 'public.tax_records', 'select'), 'bills and tax records readable (own rows by policy)');
  perform pg_temp.assert((select count(*) from pg_policies where tablename = 'player_bills' and qual like '%user_id%') >= 1, 'bills are read by their owner only');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.city_donors', 'select'), 'the donor table is read through donors_top only');
  perform pg_temp.assert((select count(*) from game_config where category = 'economy') >= 50, 'economy settings seeded');
  perform pg_temp.assert((select value from game_config where key = 'economy.vat_pct') = '7.5'::jsonb and (select value from game_config where key = 'economy.tax_band4_pct') = '15'::jsonb, 'defaults: VAT 7.5, top tax band 15');
  -- the Governor's whitelist accepts the new kind and nothing else
  perform pg_temp.assert((select kind from gov_policies where id = 'tax_holiday') = 'tax_cut' and (select active from gov_policies where id = 'tax_holiday'), 'tax holiday is on the whitelist');
  perform pg_temp.assert(pg_temp.hint_of($q$ insert into gov_policies (id, name, kind) values ('x_free', 'Free', 'free_money') $q$) <> 'ok', 'an unknown policy kind is refused');
  -- none of the new ledger reasons is ever earned, even when an admin lists them
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,tax_income,transfer_fee,stamp_duty,bill_house,bill_car,bill_business,ground_rent,vat,luxury_levy,donation,city_party,chief_title"');
  perform pg_temp.assert(bl_earn_reasons() = array['salary'], 'sink reasons are dropped from earn_reasons: ' || array_to_string(bl_earn_reasons(), ','));
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,hustle,harvest,farm_harvest,invest_income,business_income,crew_payout,office_salary"');
  perform pg_temp.assert(bl_ledger_label('tax_income', '{"week":"2026-10-12"}') like 'Income tax%' and bl_ledger_label('stamp_duty', '{}') like 'Stamp duty%'
                         and bl_ledger_label('bill_car', '{"title":"Insurance","detail":"Bicycle"}') like 'Bill:%' and bl_ledger_label('donation', '{}') like 'Donation%'
                         and bl_ledger_label('chief_title', '{"name":"Chief"}') like 'Chief title%' and bl_ledger_label('vat', '{}') = 'VAT', 'ledger labels');
  raise notice 'ok 1: grants, RLS, settings, whitelist, reasons never earned';
end $$;

-- ---------- 2. transfer fee ----------
do $$
declare a uuid; b uuid; r jsonb; q jsonb; p0 bigint; ids uuid[];
begin
  a := pg_temp.mk('SnkA'); b := pg_temp.mk('SnkB');
  ids := array[a, b];
  perform set_config('ms.a', a::text, true); perform set_config('ms.b', b::text, true);
  update profiles set bank = 1000000 where id = a;
  perform pg_temp.login(a);
  -- the maths (marginal tiers 1 % to 50k, 2 % to 500k, 3 % above; min fee 10; stamp duty 50 from 10k)
  perform pg_temp.assert((bl_transfer_fee_calc(5000, 0)->>'fee')::int = 50 and (bl_transfer_fee_calc(5000, 0)->>'stamp_duty')::int = 0, 'N5,000: N50 fee, no stamp duty (the old 1 %)');
  perform pg_temp.assert((bl_transfer_fee_calc(100, 0)->>'fee')::int = 10, 'tiny transfers pay the N10 minimum');
  perform pg_temp.assert((bl_transfer_fee_calc(10000, 0)->>'tier_fee')::int = 100 and (bl_transfer_fee_calc(10000, 0)->>'stamp_duty')::int = 50
                         and (bl_transfer_fee_calc(10000, 0)->>'fee')::int = 150, 'N10,000: N100 + N50 stamp duty');
  perform pg_temp.assert((bl_transfer_fee_calc(9999, 0)->>'stamp_duty')::int = 0, 'N9,999: no stamp duty');
  perform pg_temp.assert((bl_transfer_fee_calc(60000, 0)->>'tier_fee')::int = 700, 'N60,000: 1 % of 50k + 2 % of 10k = N700');
  perform pg_temp.cfg('economy.fee_soft_cap', '0');
  perform pg_temp.assert((bl_transfer_fee_calc(600000, 0)->>'tier_fee')::int = 500 + 9000 + 3000, 'N600,000: 500 + 9,000 + 3,000 (3 % above N500k)');
  perform pg_temp.cfg('economy.fee_soft_cap', '100000');
  perform pg_temp.assert((bl_transfer_fee_calc(600000, 0)->>'tier_fee')::int = 2 * 12500 and (bl_transfer_fee_calc(600000, 0)->>'doubled')::boolean, 'a transfer that itself passes the soft cap pays double');
  -- the preview equals what is charged
  q := bank_transfer_quote(60000);
  perform pg_temp.assert((q->>'fee')::int = 750 and (q->>'tier_fee')::int = 700 and (q->>'stamp_duty')::int = 50 and (q->>'total')::int = 60750 and not (q->>'doubled')::boolean,
                         'quote: ' || q::text);
  perform pg_temp.assert((q->>'left_before_soft_cap')::int = 100000, 'quote shows how much is left before the fee doubles');
  p0 := pg_temp.pocket(ids);
  r := bank_transfer('SnkB', 60000, 'big one');
  perform pg_temp.assert((r->>'fee')::int = 750 and pg_temp.bank(a) = 1000000 - 60750 and pg_temp.bank(b) = 60000, 'sender pays 60,000 + 750: ' || pg_temp.bank(a));
  perform pg_temp.assert(pg_temp.ledger_sum(a, 'transfer_fee') = -700 and pg_temp.ledger_sum(a, 'stamp_duty') = -50, 'ledger: transfer_fee -700 and stamp_duty -50');
  perform pg_temp.assert(pg_temp.pocket(ids) = p0 - 750, 'the fee is destroyed, not paid to anybody: supply down by exactly 750');
  -- soft cap: 60k sent; 30k more is still under 100k (fee 300 + 50), then 20k tips it over and the percentage fee doubles
  perform pg_temp.advance(16);
  q := bank_transfer_quote(30000);
  perform pg_temp.assert((q->>'fee')::int = 350 and not (q->>'doubled')::boolean, 'under the soft cap: 300 + 50, got ' || q::text);
  r := bank_transfer('SnkB', 30000);
  perform pg_temp.assert((r->>'fee')::int = 350, 'second transfer fee 350');
  perform pg_temp.advance(16);
  q := bank_transfer_quote(20000);
  perform pg_temp.assert((q->>'doubled')::boolean and (q->>'tier_fee')::int = 400 and (q->>'fee')::int = 450, 'past the soft cap the percentage fee doubles (200 -> 400), stamp duty stays 50: ' || q::text);
  r := bank_transfer('SnkB', 20000);
  perform pg_temp.assert((r->>'fee')::int = 450, 'doubled fee charged: ' || r::text);
  perform pg_temp.assert(pg_temp.ledger_sum(a, 'transfer_fee') = -700 - 300 - 400 and pg_temp.ledger_sum(a, 'stamp_duty') = -150, 'ledger totals after three transfers');
  -- not enough for amount + fee
  update profiles set bank = 20000 where id = a;
  perform pg_temp.advance(16);
  perform pg_temp.assert(pg_temp.hint_of($q$ select bank_transfer('SnkB', 20000) $q$) = 'not_enough_bank', 'amount + fee must fit in the bank');
  perform pg_temp.assert(pg_temp.bank(a) = 20000, 'a refused transfer costs nothing');
  -- tips pay the fee too (N1,000: 1 % = 10, minimum 10; no stamp duty under N10k)
  update profiles set bank = 50000, cash = 0 where id = a;
  q := bank_transfer_quote(1000, 'tip');
  perform pg_temp.assert((q->>'fee')::int = 10 and (q->>'kind') = 'tip', 'tip quote ' || q::text);
  p0 := pg_temp.pocket(ids);
  perform tip_player('SnkB', 1000, 'thanks');
  perform pg_temp.assert(pg_temp.bank(a) = 50000 - 1000 - 10, 'tip costs 1,000 + 10 fee: ' || pg_temp.bank(a));
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'transfer_fee' and delta = -10 and (meta->>'tip')::boolean), 'tip fee row');
  perform pg_temp.assert(pg_temp.pocket(ids) = p0 - 10, 'tip fee destroyed');
  update profiles set bank = 1000, cash = 5 where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$ select tip_player('SnkB', 1000) $q$) = 'not_enough_money', 'a tip must cover the fee too');
  -- bank_info exposes the rules for the app
  perform pg_temp.assert((bank_info()->'transfer'->'fee_rules'->>'enabled')::boolean and (bank_info()->'transfer'->'fee_rules'->>'stamp_duty')::int = 50, 'bank_info carries fee_rules');
  -- switched off: the old flat fee, free tips
  perform pg_temp.cfg('economy.transfer_fees_enabled', 'false');
  perform pg_temp.assert((bl_transfer_fee_calc(60000, 0)->>'fee')::int = 50 and not (bl_transfer_fee_calc(60000, 0)->>'tiered')::boolean and (bl_transfer_fee_calc(1000, 0, 'tip')->>'fee')::int = 0,
                         'switch off = flat bank.transfer_fee and free tips');
  perform pg_temp.cfg('economy.transfer_fees_enabled', 'true');
  raise notice 'ok 2: tiered fee, stamp duty, soft cap, preview, tips, switch';
end $$;

-- ---------- 3. weekly income tax ----------
do $$
declare t uuid; w date; r jsonb; owed0 bigint; b0 bigint; wk date;
begin
  perform pg_temp.cfg('economy.bills_enabled', 'false');   -- isolate the tax
  t := pg_temp.mk('SnkTax');
  perform set_config('ms.t', t::text, true);
  perform pg_temp.login(t);
  wk := bl_week_start();
  -- bands: 500k free, 5 % to 5M, 10 % to 50M, 15 % above
  perform pg_temp.assert(bl_tax_calc(500000) = 0 and bl_tax_calc(400000) = 0, 'the first N500k a week is tax free');
  perform pg_temp.assert(bl_tax_calc(1500000) = 50000, 'N1.5M: 5 % of N1M = 50,000');
  perform pg_temp.assert(bl_tax_calc(6000000) = 225000 + 100000, 'N6M: 5 % of 4.5M + 10 % of 1M = 325,000');
  perform pg_temp.assert(bl_tax_calc(60000000) = 225000 + 4500000 + 1500000, 'N60M: 225,000 + 4,500,000 + 1,500,000');
  -- earn N6M this week (salary: an earn reason), jump to just after next Monday, read the Bank
  perform bl_add_money(t, 'bank', 6000000, 'salary', '{}');
  perform bl_add_money(t, 'bank', 2000000, 'market_sale', '{}');   -- market money is not earned
  b0 := pg_temp.bank(t);
  perform pg_temp.assert((tax_info()->'week'->>'earned')::bigint = 6000000 and (tax_info()->'week'->>'est_tax')::bigint = 325000, 'the tax card shows this week so far: ' || tax_info()::text);
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '1 hour');
  r := bank_sinks();
  perform pg_temp.assert(pg_temp.ledger_sum(t, 'tax_income') = -325000 and pg_temp.bank(t) = b0 - 325000, 'tax of 325,000 taken from the bank: ' || pg_temp.ledger_sum(t, 'tax_income'));
  perform pg_temp.assert((select tax = 325000 and paid = 325000 and earned = 6000000 and not exempt from tax_records where user_id = t and week_start = wk), 'tax record');
  perform pg_temp.assert(exists (select 1 from events where user_id = t and kind = 'tax_paid' and title = 'Edo State Internal Revenue' and body like 'You paid ₦325,000 tax this week%'), 'the receipt alert');
  perform pg_temp.assert((select tax_owed from profiles where id = t) = 0, 'nothing owed when paid in full');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = t and reason = 'tax_income' and delta > 0), 'tax rows are only ever debits');
  -- settled once: reading again charges nothing more
  perform bank_sinks();
  perform pg_temp.assert(pg_temp.ledger_sum(t, 'tax_income') = -325000, 'a week is settled once');
  -- cannot pay: pay what is there, the rest is tax owed, never negative
  wk := bl_week_start();
  perform bl_add_money(t, 'bank', 6000000, 'hustle', '{}');
  update profiles set bank = 0, cash = 1000 where id = t;
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '1 hour');
  r := bank_sinks();
  perform pg_temp.assert((select tax_owed from profiles where id = t) = 324000 and pg_temp.cash(t) = 0 and pg_temp.bank(t) = 0, 'paid 1,000, owes 324,000: ' || (select tax_owed from profiles where id = t));
  perform pg_temp.assert((r->>'owed')::bigint = 324000 and (r->'tax'->>'owed')::bigint = 324000, 'the Bank app shows the tax owed');
  perform pg_temp.assert(exists (select 1 from events where user_id = t and kind = 'tax_paid' and body like '%still owe ₦324,000%'), 'the receipt says what is still owed');
  -- future earnings pay it first (an earn reason), market money does not
  perform bl_add_money(t, 'bank', 100000, 'market_sale', '{}');
  perform pg_temp.assert(pg_temp.bank(t) = 100000 and (select tax_owed from profiles where id = t) = 324000, 'non-earnings do not pay tax owed');
  perform bl_add_money(t, 'bank', 200000, 'salary', '{}');
  perform pg_temp.assert(pg_temp.bank(t) = 100000 and (select tax_owed from profiles where id = t) = 124000, 'a 200,000 salary goes to tax owed first: ' || pg_temp.bank(t));
  perform pg_temp.assert(exists (select 1 from ledger where user_id = t and reason = 'tax_income' and delta = -200000 and (meta->>'garnish')::boolean), 'garnish row');
  perform bl_add_money(t, 'bank', 500000, 'salary', '{}');
  perform pg_temp.assert((select tax_owed from profiles where id = t) = 0 and pg_temp.bank(t) = 100000 + 500000 - 124000, 'the rest of the salary is yours: ' || pg_temp.bank(t));
  -- pay by hand
  update profiles set tax_owed = 5000, bank = 2000, cash = 1000 where id = t;
  r := tax_pay();
  perform pg_temp.assert((r->>'paid')::int = 3000 and (r->>'owed')::int = 2000 and pg_temp.bank(t) = 0 and pg_temp.cash(t) = 0, 'pay what you have, never negative: ' || r::text);
  perform pg_temp.assert(pg_temp.hint_of($q$ select tax_pay() $q$) = 'not_enough_money', 'nothing left to pay with');
  update profiles set tax_owed = 0 where id = t;
  perform pg_temp.assert(pg_temp.hint_of($q$ select tax_pay() $q$) = 'no_tax_owed', 'no tax owed');
  raise notice 'ok 3: tax bands, receipt, owed, earnings pay first, never negative';
end $$;

-- grace period + switch + holiday
do $$
declare n uuid; wk date; g uuid; v_mult numeric;
begin
  perform pg_temp.cfg('economy.bills_enabled', 'false');
  perform pg_temp.travel_to(now());
  perform set_config('bl.test_offset_seconds', '', true);
  n := pg_temp.mk('SnkNew', 30);
  perform pg_temp.login(n);
  wk := bl_week_start();
  -- the account is only 2 days old when the week ends: exempt
  update profiles set created_at = bl_week_from(wk + 7) - interval '2 days' where id = n;
  perform bl_add_money(n, 'bank', 6000000, 'salary', '{}');
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '1 hour');
  perform bank_sinks();
  perform pg_temp.assert(pg_temp.ledger_sum(n, 'tax_income') = 0 and (select exempt and tax = 0 and earned = 6000000 from tax_records where user_id = n and week_start = wk), 'new players pay no tax in their first days');
  perform pg_temp.assert((tax_info()->>'exempt_now')::boolean = false or true, 'tax_info runs');
  -- switch off: nothing is taxed
  perform set_config('bl.test_offset_seconds', '', true);
  n := pg_temp.mk('SnkOff', 30);
  perform pg_temp.login(n);
  wk := bl_week_start();
  perform pg_temp.cfg('economy.tax_enabled', 'false');
  perform bl_add_money(n, 'bank', 6000000, 'salary', '{}');
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '1 hour');
  perform bank_sinks();
  perform pg_temp.assert(pg_temp.ledger_sum(n, 'tax_income') = 0 and not exists (select 1 from tax_records where user_id = n), 'tax switch off: no tax');
  perform pg_temp.cfg('economy.tax_enabled', 'true');

  -- ---------- 4. the Governor's tax holiday ----------
  perform set_config('bl.test_offset_seconds', '', true);
  perform pg_temp.assert(bl_pol_tax_mult() = 1, 'no policy: full rates');
  g := pg_temp.mk('SnkGov');
  insert into office_holders (office_id, user_id, status, term_start, term_end, paid_through, policy_id)
  values ('governor', g, 'active', bl_now() - interval '1 day', bl_now() + interval '10 days', bl_now(), 'tax_holiday');
  perform pg_temp.assert(bl_pol_tax_mult() = 0.5, 'Tax holiday cuts the rates by half for the term');
  perform pg_temp.assert(bl_tax_calc(6000000) = 162500, 'N6M under the holiday: 162,500 instead of 325,000');
  perform pg_temp.login(g);
  perform pg_temp.assert((tax_info()->'holiday'->>'cut_pct')::int = 50 and (tax_info()->'bands'->1->>'eff_pct')::numeric = 2.5, 'Benin Votes / Bank show the holiday and the cut rate: ' || tax_info()::text);
  -- it applies on settle
  n := pg_temp.mk('SnkHol', 30);
  perform pg_temp.login(n);
  wk := bl_week_start();
  perform bl_add_money(n, 'bank', 6000000, 'salary', '{}');
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '1 hour');
  perform bank_sinks();
  perform pg_temp.assert(pg_temp.ledger_sum(n, 'tax_income') = -162500 and (select holiday from tax_records where user_id = n and week_start = wk), 'holiday rates applied on settle');
  perform pg_temp.assert(exists (select 1 from events where user_id = n and kind = 'tax_paid' and body like '%tax holiday%'), 'the receipt mentions the holiday');
  update office_holders set status = 'ended' where office_id = 'governor' and user_id = g;
  perform pg_temp.assert(bl_pol_tax_mult() = 1, 'term over: full rates again');
  perform set_config('bl.test_offset_seconds', '', true);
  perform pg_temp.cfg('economy.bills_enabled', 'true');
  raise notice 'ok 3b/4: exemption, tax switch, tax holiday policy';
end $$;

-- ---------- 5. bills ----------
do $$
declare u uuid; wk date; b0 bigint; n int; r jsonb; v_house bigint; v_biz bigint; q jsonb; v_bill bigint; v_total bigint; v_ids bigint[];
begin
  perform pg_temp.cfg('economy.tax_enabled', 'false');
  perform pg_temp.cfg('rent.enabled', 'false');   -- rent is the old bill; the house bill is the new one
  perform set_config('bl.test_offset_seconds', '', true);
  u := pg_temp.mk('SnkBill', 30);
  perform set_config('ms.u', u::text, true);
  perform pg_temp.login(u);
  update profiles set weekly_rent = 1500, bank = 500000, cash = 20000 where id = u;
  perform bl_give_item(u, 'bicycle', 1);
  insert into businesses (owner_id, plot_id, type_id, name, base_income, ready_at, settled_at, last_collect_at, stock_until)
  values (u, 'biz_uselu_1', 'provision_shop', 'Oga Shop', 24000, bl_now() - interval '1 day', bl_now(), bl_now(), bl_now() + interval '1000 hours');
  insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at) values (u, 'land_ugbowo', 'land', 2, 12000000, bl_now(), bl_now());
  wk := bl_week_start();
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '1 hour');
  r := bank_sinks();
  select count(*) into n from player_bills where user_id = u and status = 'open';
  perform pg_temp.assert(n = 4, 'house, car, business and land bills issued: ' || n);
  perform pg_temp.assert((select amount from player_bills where user_id = u and kind = 'house') = 450, 'house: 30 % of the N1,500 rent = 450 (no upgrades)');
  perform pg_temp.assert((select amount from player_bills where user_id = u and kind = 'car' and ref = 'bicycle') = round(180000 * 0.5 / 100 / 10) * 10, 'car: 0.5 % of the car price');
  perform pg_temp.assert((select amount from player_bills where user_id = u and kind = 'business') = (round(bl_biz_value((select b from businesses b where b.owner_id = u)) * 0.5 / 100 / 10) * 10)::bigint, 'business: 0.5 % of its value');
  perform pg_temp.assert((select amount from player_bills where user_id = u and kind = 'land') = 12000, 'land: ground rent 0.1 % of N12M');
  perform pg_temp.assert((select min(due_at) from player_bills where user_id = u) = bl_week_from(wk + 7) + interval '3 days', 'due 3 days after the Monday boundary');
  perform pg_temp.assert(exists (select 1 from events where user_id = u and kind = 'bills_issued'), 'an alert says new bills are in');
  perform pg_temp.assert(jsonb_array_length(r->'bills') = 4 and (r->>'open_total')::bigint = (select sum(amount) from player_bills where user_id = u), 'Bank > Bills lists them with the open total');
  -- the same week is billed once
  perform bank_sinks();
  select count(*) into n from player_bills where user_id = u;
  perform pg_temp.assert(n = 4, 'billed once per week');
  -- pay one by hand
  select id into v_bill from player_bills where user_id = u and kind = 'car';
  b0 := pg_temp.bank(u);
  r := bills_pay(v_bill);
  perform pg_temp.assert((select status from player_bills where id = v_bill) = 'paid' and pg_temp.bank(u) = b0 - 900 and pg_temp.ledger_sum(u, 'bill_car') = -900, 'car bill paid by hand: ' || r::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select bills_pay(%s)', v_bill)) = 'already_paid', 'a bill is paid once');
  -- on the due date the rest are paid from the bank
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '3 days 1 hour');
  perform bank_sinks();
  perform pg_temp.assert(not exists (select 1 from player_bills where user_id = u and status = 'open'), 'autopay paid the rest on the due date');
  perform pg_temp.assert(pg_temp.ledger_sum(u, 'bill_house') = -450 and pg_temp.ledger_sum(u, 'ground_rent') = -12000 and pg_temp.ledger_sum(u, 'bill_business') < 0, 'ledger: bill_house, ground_rent, bill_business');
  perform pg_temp.assert(exists (select 1 from events where user_id = u and kind = 'bills_paid'), 'alert: bills paid');

  -- broke player: late fee, then (only after 14 days) the car stops and the business earns nothing; never negative; never seized
  perform pg_temp.cfg('economy.bills_autopay', 'true');
  update profiles set bank = 0, cash = 0, bills_next_due = null where id = u;
  wk := bl_week_start();
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '1 hour');
  perform bank_sinks();
  perform pg_temp.assert((select count(*) from player_bills where user_id = u and status = 'open') = 4, 'next week: four new open bills');
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '3 days 1 hour');
  r := bank_sinks();
  perform pg_temp.assert((select count(*) from player_bills where user_id = u and status = 'open' and late_fee > 0) = 4, 'unpaid on the due date: late fee added');
  perform pg_temp.assert((select late_fee from player_bills where user_id = u and kind = 'house' and status = 'open') = 45, 'late fee = 10 % (45 on 450)');
  perform pg_temp.assert(exists (select 1 from events where user_id = u and kind = 'bills_late'), 'alert: overdue');
  perform pg_temp.assert(pg_temp.bank(u) = 0 and pg_temp.cash(u) = 0, 'a poor player is never taken below zero');
  perform pg_temp.assert(not bl_sink_blocked(u, 'car', 'bicycle') and not bl_sink_blocked(u, 'business', (select id::text from businesses where owner_id = u)), 'not blocked yet: only a late fee');
  perform pg_temp.assert(exists (select 1 from inventory where user_id = u and item_id = 'bicycle' and qty > 0), 'nothing is seized');
  -- the car still drives (ride option allowed) before the long window
  q := bl_travel_quote((select p from profiles p where p.id = u), 'oba_market');
  perform pg_temp.assert((select (o->>'allowed')::boolean from jsonb_array_elements(q->'options') o where o->>'mode' = 'car'), 'the bicycle can still ride before 14 days overdue');
  -- a business with takings: accrues while not blocked
  perform pg_temp.assert((select floor((bl_biz_settle(id)).takings) from businesses where owner_id = u) >= 0, 'business settles');
  -- 14 days after the due date: blocked
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '3 days' + interval '14 days 1 hour');
  perform pg_temp.assert(bl_sink_blocked(u, 'car', 'bicycle') and bl_sink_any_blocked(u, 'car'), 'blocked only after the long overdue window');
  q := bl_travel_quote((select p from profiles p where p.id = u), 'oba_market');
  perform pg_temp.assert(not (select (o->>'allowed')::boolean from jsonb_array_elements(q->'options') o where o->>'mode' in ('car', 'bicycle')), 'the car cannot drive: ' || q::text);
  perform pg_temp.assert((select o->>'reason' from jsonb_array_elements(q->'options') o where o->>'mode' = 'car') like '%Bank, Bills%', 'the reason points to the Bank app');
  update businesses set takings = 0, event_carry_h = 0, settled_at = bl_now(), last_collect_at = bl_now(), ready_at = bl_now() - interval '1 minute', stock_until = bl_now() + interval '1000 hours' where owner_id = u;
  perform pg_temp.advance(3600 * 5);
  perform pg_temp.assert((select floor((bl_biz_settle(id)).takings) from businesses where owner_id = u) = 0, 'an overdue business bill pauses its income');
  perform pg_temp.assert(exists (select 1 from businesses where owner_id = u), 'the business is not seized');
  -- pay up: unblocked, income flows again
  update profiles set bank = 1000000 where id = u;
  perform bills_pay_all();
  perform pg_temp.assert(not exists (select 1 from player_bills where user_id = u and status = 'open' and due_at <= bl_now()), 'paid in full');
  perform pg_temp.assert(not bl_sink_blocked(u, 'car', 'bicycle'), 'unblocked after paying');
  perform pg_temp.assert(pg_temp.ledger_sum(u, 'bill_house') <= -450 - 495, 'the late fee is part of what was paid (450 + 495)');
  update businesses set takings = 0, event_carry_h = 0, settled_at = bl_now(), last_collect_at = bl_now(), ready_at = bl_now() - interval '1 minute', stock_until = bl_now() + interval '1000 hours' where owner_id = u;
  perform pg_temp.advance(3600 * 5);
  perform pg_temp.assert((select floor((bl_biz_settle(id)).takings) from businesses where owner_id = u) > 0, 'income flows again after paying');
  -- grace: a new account gets no bills
  perform set_config('bl.test_offset_seconds', '', true);
  u := pg_temp.mk('SnkNoob', 2);
  perform pg_temp.login(u);
  wk := bl_week_start();
  update profiles set weekly_rent = 1500, created_at = bl_week_from(wk + 7) - interval '2 days' where id = u;
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '1 hour');
  perform bank_sinks();
  perform pg_temp.assert(not exists (select 1 from player_bills where user_id = u), 'new players get no bills in their first 7 days');
  -- switch off
  perform set_config('bl.test_offset_seconds', '', true);
  u := pg_temp.mk('SnkNoBills', 30);
  perform pg_temp.login(u);
  update profiles set weekly_rent = 1500 where id = u;
  perform pg_temp.cfg('economy.bills_enabled', 'false');
  wk := bl_week_start();
  perform pg_temp.travel_to(bl_week_from(wk + 7) + interval '1 hour');
  perform bank_sinks();
  perform pg_temp.assert(not exists (select 1 from player_bills where user_id = u), 'bills switch off: no bills');
  perform pg_temp.cfg('economy.bills_enabled', 'true');
  perform set_config('bl.test_offset_seconds', '', true);
  raise notice 'ok 5: bills accrue, are paid, late fee, blocked only after the long window, grace, switch';
end $$;

-- ---------- 6. VAT and the luxury levy ----------
do $$
declare s uuid; r jsonb; c0 bigint; l jsonb; it jsonb; f_price bigint; fid text; w_id text; w_price bigint; t0 bigint;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform pg_temp.cfg('economy.tax_enabled', 'false');
  perform pg_temp.cfg('economy.bills_enabled', 'false');
  s := pg_temp.mk('SnkShop', 30);
  perform set_config('ms.s', s::text, true);
  perform pg_temp.login(s);
  update profiles set cash = 5000000, bank = 0 where id = s;
  -- rates and prices
  perform pg_temp.assert(bl_gross('item', 'laptop', 45000) = 48375, 'a N45,000 laptop is N48,375 with 7.5 % VAT');
  perform pg_temp.assert(bl_gross('item', 'food', 600) = 600 and bl_gross('item', 'hygiene', 300) = 300 and bl_gross('item', 'offering', 7800) = 7800, 'food and basic needs are VAT free');
  perform pg_temp.assert(bl_gross('item', 'laptop', 1100000) = 1100000 + 82500 + 55000, 'a N1.1M laptop: VAT + 5 % luxury levy');
  perform pg_temp.assert(bl_gross('item', 'laptop', 330000) = 330000 + 24750, 'a mid laptop under N1M has no luxury levy');
  perform pg_temp.assert(bl_gross('item', 'vehicle', 1000000) = 1000000 + 75000 + 50000 and bl_gross('item', 'gadget', 1000) = 1000 + 75 + 50, 'cars and status gadgets pay the luxury levy');
  perform pg_temp.assert(bl_tax_split('item', 'laptop', 1237500) = array[82500, 55000]::bigint[], 'the split of a gross price: ' || bl_tax_split('item', 'laptop', 1237500)::text);
  -- the shop shows the VAT-inclusive price and says so
  perform pg_temp.at(s, 'bronze_tech_hub');
  l := shop_list('bronze_tech_hub');
  select x into it from jsonb_array_elements(l->'items') x where x->>'id' = 'laptop';
  perform pg_temp.assert((it->>'price')::bigint = 48375 and (it->>'vat_pct')::numeric = 7.5 and (it->>'lux_pct')::numeric = 0, 'shop_list shows N48,375 incl. VAT: ' || it::text);
  select x into it from jsonb_array_elements(l->'items') x where x->>'id' = 'dell_xps_13';
  perform pg_temp.assert((it->>'price')::bigint = 1237500 and (it->>'lux_pct')::numeric = 5, 'the XPS carries the luxury levy: ' || it::text);
  c0 := pg_temp.cash(s);
  r := shop_buy('laptop', 1);
  perform pg_temp.assert(pg_temp.cash(s) = c0 - 48375 and (r->>'spent')::bigint = 48375, 'the price shown is the price paid');
  perform pg_temp.assert(pg_temp.ledger_sum(s, 'shop') = -45000 and pg_temp.ledger_sum(s, 'vat') = -3375, 'ledger: shop -45,000 and vat -3,375');
  perform pg_temp.assert(r->>'message' like '%incl. VAT ₦3,375%', 'the message says incl. VAT: ' || (r->>'message'));
  c0 := pg_temp.cash(s);
  r := shop_buy('dell_xps_13', 1);
  perform pg_temp.assert(pg_temp.cash(s) = c0 - 1237500 and pg_temp.ledger_sum(s, 'luxury_levy') = -55000 and pg_temp.ledger_sum(s, 'vat') = -3375 - 82500, 'luxury levy row: ' || pg_temp.ledger_sum(s, 'luxury_levy'));
  -- food has no VAT
  perform pg_temp.at(s, 'oba_market');
  l := shop_list('oba_market');
  select x into it from jsonb_array_elements(l->'items') x where x->>'id' = 'roll_and_soda';
  perform pg_temp.assert((it->>'price')::bigint = 600 and (it->>'vat_pct')::numeric = 0, 'food shows no VAT: ' || it::text);
  c0 := pg_temp.cash(s);
  r := shop_buy('roll_and_soda', 2);
  perform pg_temp.assert(pg_temp.cash(s) = c0 - 1200 and pg_temp.ledger_sum(s, 'vat') = -3375 - 82500, 'food bought without VAT');
  -- a car: bank first, VAT + luxury in their own rows, the dealer price is the gross
  perform pg_temp.at(s, 'ighodalo_cars');
  update profiles set cash = 100000, bank = 400000 where id = s;
  l := shop_list('ighodalo_cars');
  select x into it from jsonb_array_elements(l->'items') x where x->>'id' = 'bicycle';
  perform pg_temp.assert((it->>'price')::bigint = bl_gross('item', 'vehicle', bl_dealer_net((select i from items i where i.id = 'bicycle'), 'ighodalo_cars')), 'car price is the gross dealer price: ' || it::text);
  c0 := pg_temp.bank(s) + pg_temp.cash(s);
  r := shop_buy('bicycle', 1);
  perform pg_temp.assert(pg_temp.bank(s) + pg_temp.cash(s) = c0 - (it->>'price')::bigint and (r->>'spent')::bigint = (it->>'price')::bigint, 'car paid at the displayed price');
  perform pg_temp.assert(pg_temp.ledger_sum(s, 'car_purchase') + pg_temp.ledger_sum(s, 'luxury_levy') + pg_temp.ledger_sum(s, 'vat') = -(it->>'price')::bigint - 55000 - 3375 - 82500 + 0, 'car rows add up to the gross price');
  -- furniture: VAT in the catalogue price
  select id, price into fid, f_price from furniture where active and buyable and price between 4000 and 20000 order by price limit 1;
  perform pg_temp.at(s, 'ekenwan_room');
  update profiles set cash = 100000, bank = 0 where id = s;
  c0 := pg_temp.cash(s);
  t0 := pg_temp.ledger_sum(s, 'furniture') + pg_temp.ledger_sum(s, 'vat');
  r := furniture_buy(fid);
  perform pg_temp.assert(pg_temp.cash(s) = c0 - bl_gross('furniture', 'x', f_price) and (r->>'spent')::bigint = bl_gross('furniture', 'x', f_price), 'furniture paid with VAT: ' || r::text);
  perform pg_temp.assert(pg_temp.ledger_sum(s, 'furniture') + pg_temp.ledger_sum(s, 'vat') - t0 = -bl_gross('furniture', 'x', f_price) and pg_temp.ledger_sum(s, 'furniture') = -f_price, 'furniture rows: net + VAT');
  -- boutique: VAT in the price
  select id, price into w_id, w_price from wardrobe_items where active and price between 5000 and 100000 and gender is null order by price limit 1;
  update profiles set cash = 200000, bank = 0 where id = s;
  c0 := pg_temp.cash(s);
  r := wardrobe_buy(w_id);
  perform pg_temp.assert(pg_temp.cash(s) = c0 - bl_gross('wardrobe', 'x', w_price) and (r->>'paid')::bigint = bl_gross('wardrobe', 'x', w_price), 'boutique paid with VAT: ' || r::text);
  -- switches
  perform pg_temp.cfg('economy.luxury_enabled', 'false');
  perform pg_temp.assert(bl_gross('item', 'laptop', 1100000) = 1100000 + 82500, 'luxury switch off: VAT only');
  perform pg_temp.cfg('economy.vat_enabled', 'false');
  perform pg_temp.assert(bl_gross('item', 'laptop', 45000) = 45000 and bl_gross('item', 'vehicle', 1000000) = 1000000, 'VAT switch off: the old prices');
  perform pg_temp.cfg('economy.vat_enabled', 'true');
  perform pg_temp.cfg('economy.luxury_enabled', 'true');
  raise notice 'ok 6: VAT included, food exempt, luxury levy, furniture, boutique, switches';
end $$;

-- ---------- 7. prestige ----------
do $$
declare d uuid; g uuid; late uuid; r jsonb; p0 bigint; xp0 int; xp1 int; ids uuid[];
begin
  perform set_config('bl.test_offset_seconds', '', true);
  d := pg_temp.mk('SnkDonor', 30); g := pg_temp.mk('SnkGuest', 30); late := pg_temp.mk('SnkLate', 30);
  ids := array[d, g, late];
  perform pg_temp.login(d);
  update profiles set bank = 400000000, cash = 1000 where id = d;
  -- donate: destroyed, board, badge, Charisma XP
  perform pg_temp.assert(pg_temp.hint_of($q$ select donate_city(5000) $q$) = 'too_small', 'a donation has a minimum');
  xp0 := coalesce((select xp from player_skills where user_id = d and skill_id = 'charisma'), 0);
  p0 := pg_temp.pocket(array[d]);
  r := donate_city(1000000);
  perform pg_temp.assert(pg_temp.pocket(array[d]) = p0 - 1000000 and pg_temp.ledger_sum(d, 'donation') = -1000000, 'the donation leaves the game for good');
  xp1 := coalesce((select xp from player_skills where user_id = d and skill_id = 'charisma'), 0);
  perform pg_temp.assert(xp1 - xp0 = 10, 'Charisma XP: 1M / 100k = 10, got ' || (xp1 - xp0));
  perform pg_temp.assert(r->>'badge' = 'Benefactor' and bl_donor_badge(d) = 'Benefactor', 'badge for N1M: ' || r::text);
  perform donate_city(10000000);
  perform pg_temp.assert(bl_donor_badge(d) = 'Philanthropist', 'badge climbs with the total');
  perform pg_temp.login(g);
  r := donors_top(20);
  perform pg_temp.assert((r->'rows'->0->>'username') = 'SnkDonor' and (r->'rows'->0->>'total')::bigint = 11000000 and (r->'rows'->0->>'badge') = 'Philanthropist', 'the Benin Philanthropists board: ' || r::text);
  perform pg_temp.assert((get_public_profile(d)->>'donor') = 'Philanthropist', 'the badge shows on the public profile');

  raise notice 'ok 7a: donate, board, badge, XP';
end $$;

-- a city party
do $$
declare d uuid; g uuid; late uuid; r jsonb; p0 bigint; f0 numeric; v_loc text := 'mama_osas_buka'; m0 bigint;
begin
  select id into d from profiles where username = 'SnkDonor'; select id into g from profiles where username = 'SnkGuest'; select id into late from profiles where username = 'SnkLate';
  delete from city_party_guests; delete from city_parties;
  update profiles set fun = 50, bank = 400000000, cash = 1000 where id in (d, g, late);
  update profiles set location_id = v_loc, last_seen = bl_now() where id in (d, g);
  update profiles set location_id = 'oba_market', last_seen = bl_now() where id = late;
  perform pg_temp.login(d);
  update locations set open_hour = null, close_hour = null where id = v_loc;
  m0 := pg_temp.pocket(array[d]);
  r := city_party_status();
  perform pg_temp.assert((r->'here'->>'ok')::boolean and (r->>'cost')::bigint = 20000000, 'party status says go: ' || r::text);
  r := city_party_throw();
  perform pg_temp.assert(pg_temp.pocket(array[d]) = m0 - 20000000 and pg_temp.ledger_sum(d, 'city_party') = -20000000, 'the party money is destroyed');
  perform pg_temp.assert(exists (select 1 from broadcasts where kind = 'message' and title like '%City party%' and style = 'celebration' and audience = 'everyone'), 'an announcement to everyone');
  perform pg_temp.assert((select fun from profiles where id = g) = 90 and (select fun from profiles where id = d) = 90, 'everyone in the venue gets Fun +40');
  perform pg_temp.assert((select fun from profiles where id = late) = 50, 'a player somewhere else gets nothing');
  perform pg_temp.assert(exists (select 1 from events where user_id = g and kind = 'city_party'), 'guest alert');
  perform pg_temp.assert(pg_temp.hint_of($q$ select city_party_throw() $q$) = 'party_on', 'one party at a time per venue');
  -- somebody walks in during the party: boosted once by their next call
  update profiles set location_id = v_loc where id = late;
  perform pg_temp.login(late);
  perform bank_sinks();
  perform pg_temp.assert((select fun from profiles where id = late) = 90, 'arriving during the party: Fun +40 on the next call');
  perform bank_sinks();
  perform pg_temp.assert((select fun from profiles where id = late) = 90 and (select guests from city_parties order by id desc limit 1) = 3, 'once per player; 3 guests');
  -- after it ends: nothing, and the host waits
  perform pg_temp.advance(3600);
  update profiles set fun = 50 where id = g;
  perform pg_temp.login(g);
  perform bank_sinks();
  perform pg_temp.assert((select fun from profiles where id = g) <= 50, 'party over: no boost');
  perform pg_temp.login(d);
  perform pg_temp.assert(pg_temp.hint_of($q$ select city_party_throw() $q$) = 'cooldown', 'the host rests before the next party');
  -- wrong venue
  perform pg_temp.cfg('economy.party_cooldown_minutes', '0');
  update profiles set location_id = 'oba_market' where id = d;
  perform pg_temp.assert(pg_temp.hint_of($q$ select city_party_throw() $q$) = 'bad_venue', 'a market is no party venue');
  perform pg_temp.cfg('economy.party_cooldown_minutes', '720');
  raise notice 'ok 7a2: city party';
end $$;

do $$
declare d uuid; c uuid; r jsonb; p0 bigint; m0 bigint;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  c := pg_temp.mk('SnkChief', 30);
  perform pg_temp.login(c);
  update profiles set bank = 300000000, cash = 0 where id = c;
  r := chief_titles();
  perform pg_temp.assert(jsonb_array_length(r->'tiers') = 3 and (r->'tiers'->0->>'price')::bigint = 10000000 and (r->'tiers'->2->>'price')::bigint = 200000000
                         and jsonb_array_length(r->'wards') >= 8, 'three tiers (10M / 50M / 200M) and the wards: ' || r::text);
  perform pg_temp.assert(pg_temp.hint_of($q$ select chief_title_buy(1, 'nowhere') $q$) = 'bad_ward', 'pick a real area');
  perform pg_temp.assert(pg_temp.hint_of($q$ select chief_title_buy(9, 'uselu') $q$) = 'bad_tier', 'pick a listed title');
  m0 := pg_temp.pocket(array[c]);
  r := chief_title_buy(1, 'uselu');
  perform pg_temp.assert(pg_temp.pocket(array[c]) = m0 - 10000000 and pg_temp.ledger_sum(c, 'chief_title') = -10000000, 'the title price is destroyed');
  perform pg_temp.assert(bl_pol_title(c) = 'Chief' and bl_chief_title(c) = 'Chief' and r->>'message' like '%Chief SnkChief of Uselu%', 'the badge next to the name: ' || r::text);
  perform pg_temp.assert((get_public_profile(c)->>'title') = 'Chief' and (get_public_profile(c)->>'chief_of') = 'Uselu', 'public profile carries title and "of"');
  perform pg_temp.assert(pg_temp.hint_of($q$ select chief_title_buy(1, 'uselu') $q$) = 'already_owned', 'cannot buy the same title twice');
  -- upgrade pays the difference
  m0 := pg_temp.pocket(array[c]);
  r := chief_title_buy(2, 'ring_road');
  perform pg_temp.assert(pg_temp.pocket(array[c]) = m0 - 40000000 and bl_pol_title(c) = 'High Chief', 'upgrade pays the difference (40M): ' || (m0 - pg_temp.pocket(array[c])));
  perform pg_temp.assert(pg_temp.hint_of($q$ select chief_title_buy(1, 'uselu') $q$) = 'already_owned', 'no downgrade');
  -- a poor player
  update profiles set bank = 1000 where id = c;
  perform pg_temp.assert(pg_temp.hint_of($q$ select chief_title_buy(3, 'uselu') $q$) = 'not_enough_money', 'cannot afford: refused, nothing taken');
  perform pg_temp.assert(pg_temp.bank(c) = 1000, 'a refused title costs nothing');
  -- an elected office title wins the slot
  insert into office_holders (office_id, user_id, status, term_start, term_end, paid_through) values ('governor', c, 'active', bl_now() - interval '1 day', bl_now() + interval '10 days', bl_now());
  perform pg_temp.assert(bl_pol_title(c) = (select title from offices where id = 'governor'), 'an office title wins the badge slot');
  update office_holders set status = 'ended' where user_id = c and office_id = 'governor';
  perform pg_temp.assert(bl_pol_title(c) = 'High Chief', 'the Chief title is back after the term');
  -- switch
  perform pg_temp.cfg('economy.prestige_enabled', 'false');
  perform pg_temp.assert(bl_pol_title(c) is null and pg_temp.hint_of($q$ select donate_city(20000) $q$) = 'disabled', 'prestige switch off');
  perform pg_temp.cfg('economy.prestige_enabled', 'true');
  raise notice 'ok 7b: Chief titles';
end $$;

-- ---------- 8. money is destroyed ----------
do $$
declare ids uuid[] := array[pg_temp.mk('SnkM1'), pg_temp.mk('SnkM2')]; p0 bigint; r jsonb; s uuid;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform pg_temp.login(ids[1]);
  update profiles set bank = 500000 where id = ids[1];
  p0 := pg_temp.pocket(ids);
  r := bank_transfer('SnkM2', 80000);
  perform pg_temp.assert(pg_temp.pocket(ids) = p0 - (r->>'fee')::bigint and (r->>'fee')::bigint > 0, 'a transfer moves the amount and destroys the fee');
  -- every sink reason is a pure debit in the ledger: no matching credit anywhere
  perform pg_temp.assert(not exists (select 1 from ledger where reason in ('tax_income', 'transfer_fee', 'stamp_duty', 'bill_house', 'bill_car', 'bill_business', 'ground_rent', 'vat', 'luxury_levy', 'donation', 'city_party', 'chief_title') and delta > 0),
                         'no sink reason ever credits a player');
  raise notice 'ok 8: sinks destroy money';
end $$;

-- ---------- 9. Economy dashboard ----------
do $$
declare adm uuid; r jsonb; v_created bigint; v_destroyed bigint; v_int text[] := bl_econ_list('economy.internal_reasons', ''); v_sum bigint; v_from timestamptz; v_u uuid;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform pg_temp.cfg('economy.tax_enabled', 'true');
  perform pg_temp.cfg('economy.bills_enabled', 'true');
  perform pg_temp.cfg('rent.enabled', 'true');
  adm := pg_temp.mk('SnkAdmin', 30);
  update profiles set is_admin = true where id = adm;
  v_u := pg_temp.mk('SnkNormal', 30);
  perform pg_temp.login(v_u);
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_economy_overview(14) $q$) <> 'ok', 'players cannot open the dashboard');
  update profiles set bank = 5000 where id = v_u;
  perform bl_sink_take(v_u, 500, 'tax_income', '{}');   -- one tax row dated today (the earlier groups time-travelled)
  perform bl_sink_take(v_u, 100, 'transfer_fee', '{}');
  perform pg_temp.login(adm);
  r := admin_economy_overview(14);
  v_from := ((bl_now() at time zone 'Africa/Lagos')::date - 13)::timestamp at time zone 'Africa/Lagos';
  select coalesce(sum(l.delta) filter (where l.delta > 0), 0), coalesce(-sum(l.delta) filter (where l.delta < 0), 0) into v_created, v_destroyed
    from ledger l join profiles p on p.id = l.user_id where l.created_at >= v_from and l.created_at < v_from + interval '14 days' and not p.is_admin and l.reason <> all (v_int);
  perform pg_temp.assert((r->'window'->>'created')::bigint = v_created and (r->'window'->>'destroyed')::bigint = v_destroyed, 'created / destroyed match the ledger: ' || (r->'window')::text || ' vs ' || v_created || '/' || v_destroyed);
  perform pg_temp.assert((select sum((x->>'created')::bigint) from jsonb_array_elements(r->'series') x) = v_created and (select sum((x->>'destroyed')::bigint) from jsonb_array_elements(r->'series') x) = v_destroyed
                         and jsonb_array_length(r->'series') = 14, '14 daily rows add up to the window');
  perform pg_temp.assert((select sum((x->>'created')::bigint) from jsonb_array_elements(r->'categories') x) = v_created, 'categories add up too');
  select coalesce(sum(cash + bank), 0) into v_sum from profiles where not is_admin;
  perform pg_temp.assert((r->'supply'->>'cash')::bigint + (r->'supply'->>'bank')::bigint = v_sum, 'cash + bank match the profiles');
  perform pg_temp.assert((r->'supply'->>'total')::bigint = (r->'supply'->>'cash')::bigint + (r->'supply'->>'bank')::bigint + (r->'supply'->>'yahoo')::bigint + (r->'supply'->>'gangs')::bigint + (r->'supply'->>'business')::bigint,
                         'total = cash + bank + yahoo + gangs + business');
  perform pg_temp.assert((r->'supply'->>'yahoo')::bigint = (select coalesce(sum(y.dirty), 0) from yahoo_players y join profiles p on p.id = y.user_id where not p.is_admin), 'yahoo balance counted');
  perform pg_temp.assert((r->'tax'->>'collected_total')::bigint = (select coalesce(-sum(l.delta), 0) from ledger l join profiles p on p.id = l.user_id where l.reason = 'tax_income' and l.delta < 0 and not p.is_admin), 'tax collected matches the ledger');
  perform pg_temp.assert((r->'tax'->>'collected_total')::bigint >= 325000 + 162500, 'the tax test rows are in');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(r->'categories') x where x->>'category' = 'Income tax' and (x->>'destroyed')::bigint > 0), 'Income tax shows as a sink category');
  perform pg_temp.assert(jsonb_array_length(r->'holders') <= 20 and jsonb_array_length(r->'holders') >= 5
                         and (select bool_and((a->>'total')::bigint >= (b->>'total')::bigint) from jsonb_array_elements(r->'holders') with ordinality a(a, i) join jsonb_array_elements(r->'holders') with ordinality b(b, j) on j = i + 1), 'top holders: at most 20, richest first');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r->'holders') x where x->>'username' = 'SnkAdmin'), 'admins are not holders');
  perform pg_temp.assert(r->'inflation' ? 'growth_pct' and r->'inflation' ? 'state' and (r->'inflation'->>'supply_start')::bigint = (r->'supply'->>'total')::bigint - ((r->'window'->>'net')::bigint), 'inflation: growth of the supply over the window');
  perform pg_temp.assert((r->'switches'->>'tax')::boolean and (r->'tax'->>'bills_open_total') is not null and (r->'tax'->>'vat_window')::bigint >= 0, 'dashboard carries switches and sink totals');
  perform pg_temp.assert(jsonb_array_length(admin_economy_overview(1)->'series') = 1, 'one-day window');
  raise notice 'ok 9: dashboard matches the ledger';
end $$;

-- ---------- 10. nothing negative ----------
do $$
begin
  perform pg_temp.assert(not exists (select 1 from profiles where cash < 0 or bank < 0 or tax_owed < 0), 'no balance, bank or tax owed below zero');
  perform pg_temp.assert(not exists (select 1 from player_bills where amount <= 0 or late_fee < 0), 'no bill below zero');
  raise notice 'ok 10: nothing negative';
  raise notice 'money_sinks_test: all groups passed';
end $$;
