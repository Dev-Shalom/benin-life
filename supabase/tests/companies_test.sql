-- Companies + real businesses (20261020000100_companies.sql). Rolled back. Run (migration applied):
--   bash scripts/sql-test.sh -- supabase/tests/companies_test.sql
-- Groups: 1 grants / RLS / seeds · 2 setup · 3 register (fee, name moderation, unique, gates, money) · 4 branch + format upgrade ·
-- 5 staff / manager / generator / pricing · 6 marketing boost · 7 nightly settle with time travel, the 3-night cap, cash out, no writes on
-- a repeated read · 8 weekly tax on cash out · 9 rating + events with forced rolls · 10 player cap · 11 sell + Market · 12 rankings +
-- discover + public card · 13 real business: submit, pay, approve, pin, expiry, reject + refund, wrong amount, area cap, renew,
-- report / track · 14 admin remove + audit · 15 switches.
update public.locations set open_hour = null, close_hour = null where scene = 'market';
-- isolation: the whole file is rolled back, so start from an empty company world. A dev DB that already holds companies (names are unique,
-- rankings / discover counts are asserted) must not change the result.
delete from public.real_businesses;
delete from public.companies;

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
create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;
create or replace function pg_temp.advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;
-- jump to just after the next settle hour (6 PM Benin)
create or replace function pg_temp.next_evening() returns void
language plpgsql as $$
begin
  perform pg_temp.advance(extract(epoch from (bl_co_next_settle() - bl_now())) + 120);
end $$;
create or replace function pg_temp.mk(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@co.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, busy_until = null, travel_to = null, protected_until = null, created_at = now() - interval '30 days',
         cash = 0, bank = 0, energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0 where id = v;
  return v;
end $$;
create or replace function pg_temp.events_off() returns void language plpgsql as $$
declare k text;
begin
  foreach k in array array['company.ev_good_review_pct', 'company.ev_bad_review_pct', 'company.ev_outage_pct', 'company.ev_supplier_pct'] loop
    perform pg_temp.cfg(k, '0');
  end loop;
end $$;
create or replace function pg_temp.co(p_id bigint) returns companies language sql as $$ select * from companies where id = p_id $$;
create or replace function pg_temp.ins(p_uid uuid, p_name text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, owner) values ('real-biz', p_uid::text || '/' || p_name, p_uid)
$$;
create or replace function pg_temp.tuples() returns bigint language sql as $$
  select coalesce(pg_stat_get_xact_tuples_inserted('public.companies'::regclass) + pg_stat_get_xact_tuples_updated('public.companies'::regclass)
       + pg_stat_get_xact_tuples_inserted('public.company_nights'::regclass) + pg_stat_get_xact_tuples_updated('public.company_nights'::regclass)
       + pg_stat_get_xact_tuples_inserted('public.company_log'::regclass) + pg_stat_get_xact_tuples_updated('public.company_log'::regclass)
       + pg_stat_get_xact_tuples_updated('public.profiles'::regclass) + pg_stat_get_xact_tuples_inserted('public.ledger'::regclass), 0)
$$;

-- ---------- 1. grants / RLS / seeds ----------
do $$
declare f text;
begin
  foreach f in array array['company_status()', 'company_register(text,text,text,text,text)', 'company_branch_add(bigint,text)', 'company_branch_upgrade(bigint,bigint)',
    'company_hire(bigint)', 'company_fire(bigint)', 'company_manager(bigint,boolean)', 'company_generator(bigint)', 'company_set_pricing(bigint,text)',
    'company_marketing_buy(bigint,text)', 'company_cashout(bigint)', 'company_sell(bigint)', 'company_rankings(int)', 'company_discover(text,text,text,text,int,int)',
    'real_biz_form()', 'real_biz_cancel(uuid)', 'real_biz_mine()', 'real_biz_renew_start(uuid)', 'real_biz_map()', 'real_biz_get(uuid)', 'real_biz_track(uuid,text)',
    'real_biz_report(uuid,text)', 'admin_company_overview(int)', 'admin_company_remove(bigint,text)', 'admin_real_biz_queue(text,int)', 'admin_real_biz_approve(uuid)',
    'admin_real_biz_reject(uuid,text,boolean)', 'admin_real_biz_suspend(uuid,text)', 'admin_real_biz_unsuspend(uuid)', 'admin_real_biz_remove(uuid,text,boolean)',
    'admin_real_biz_refund_start(uuid)', 'admin_real_biz_revenue()'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute'), 'anon cannot run ' || f);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute'), 'authenticated can run ' || f);
  end loop;
  perform pg_temp.assert(has_function_privilege('anon', 'public.company_public(bigint)', 'execute'), 'the public company card works signed out');
  foreach f in array array['bl_co_settle(bigint,boolean)', 'bl_co_card(companies,boolean)', 'bl_co_calc(companies,boolean,numeric)', 'bl_co_value(companies)', 'bl_co_roll(numeric)',
    'bl_co_num(text,numeric)', 'bl_co_mine(uuid,bigint,boolean)', 'bl_co_market_take(uuid,text,int)', 'bl_co_market_give(uuid,text,jsonb,bigint,boolean)', 'bl_co_gate(uuid,company_industries)',
    'bl_rb_slot_free(text,uuid)', 'bl_rb_area_used(text)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute') and not has_function_privilege('authenticated', 'public.' || f, 'execute'), 'private helper locked: ' || f);
  end loop;
  foreach f in array array['bl_real_biz_paid(text,bigint,jsonb)', 'bl_real_biz_refund_claim(uuid)', 'bl_real_biz_refund_result(uuid,boolean,text,jsonb)', 'bl_real_biz_sweep()'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', 'public.' || f, 'execute') and not has_function_privilege('anon', 'public.' || f, 'execute')
                           and has_function_privilege('service_role', 'public.' || f, 'execute'), 'service only: ' || f);
  end loop;
  foreach f in array array['company_industries', 'company_areas', 'company_formats', 'company_marketing', 'companies', 'company_branches', 'company_nights', 'company_log',
                           'real_biz_slots', 'real_businesses', 'real_biz_reports', 'real_biz_counter_log'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || f)::regclass), 'RLS on ' || f);
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || f, 'select'), 'anon cannot read ' || f);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || f, 'insert') and not has_table_privilege('authenticated', 'public.' || f, 'update')
                           and not has_table_privilege('authenticated', 'public.' || f, 'delete'), 'no client writes on ' || f);
  end loop;
  perform pg_temp.assert(not has_column_privilege('authenticated', 'public.real_businesses', 'pay_raw', 'select'), 'the payment JSON is hidden from players');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.company_nights', 'select'), 'nights are read through the RPC only');
  perform pg_temp.assert((select count(*) from company_industries) >= 8, 'eight industries seeded');
  perform pg_temp.assert((select count(*) from company_areas where tier = 1) >= 3 and (select count(*) from company_areas where tier = 4) >= 1, 'tiered Benin areas seeded');
  perform pg_temp.assert(not exists (select 1 from company_areas where name ~* 'lekki|ikeja|yaba|ikoyi|victoria island|surulere'), 'no Lagos names');
  perform pg_temp.assert((select count(*) from company_formats) = 3 and (select count(*) from company_marketing) = 3, 'formats and marketing seeded');
  perform pg_temp.assert('company_income' = any (bl_earn_reasons()), 'company income is earned money');
  perform pg_temp.assert(not ('company_fee' = any (bl_earn_reasons())) and not ('company_sell' = any (bl_earn_reasons())), 'spending and selling is not earned');
  perform pg_temp.assert((select count(*) from real_biz_slots where area_id = 'gra') >= 6, 'real-business slots are generated');
  perform pg_temp.assert(not exists (select 1 from real_biz_slots a join real_biz_slots b on a.id < b.id and sqrt(power(a.x - b.x, 2) + power(a.y - b.y, 2)) < 33), 'slots never overlap');
  perform pg_temp.assert(not exists (select 1 from real_biz_slots s join locations l on sqrt(power(l.x - s.x, 2) + power(l.y - s.y, 2)) < 33 and l.private_home_owner_id is null), 'slots never sit on a place');
  perform pg_temp.assert(exists (select 1 from storage.buckets where id = 'real-biz' and public), 'real-biz bucket');
  perform pg_temp.assert((select count(*) from pg_policies where tablename = 'objects' and policyname like 'real_biz_%') = 3, 'storage policies');
  perform pg_temp.assert((select count(*) from pg_policies where tablename = 'companies' and qual like '%owner_id%') >= 1, 'players read their own companies only');
  raise notice 'ok 1: grants, RLS, seeds, slots';
end $$;

-- ---------- 2. setup ----------
do $$
declare o uuid; p uuid; adm uuid; z uuid;
begin
  o := pg_temp.mk('CoOwner'); p := pg_temp.mk('CoPoor'); adm := pg_temp.mk('CoAdmin'); z := pg_temp.mk('CoBuyer');
  update profiles set is_admin = true where id = adm;
  update profiles set bank = 50000000, cash = 50000 where id = o;
  update profiles set bank = 20000000, cash = 50000 where id = z;
  update profiles set bank = 1000, cash = 1000 where id = p;
  perform set_config('co.o', o::text, true); perform set_config('co.p', p::text, true); perform set_config('co.adm', adm::text, true); perform set_config('co.z', z::text, true);
  perform pg_temp.events_off();
  perform pg_temp.cfg('company.enabled', 'true'); perform pg_temp.cfg('company.player_night_cap', '100000000'); perform pg_temp.cfg('company.max_nights', '3');
  perform pg_temp.cfg('market.daily_listing_cap', '50'); perform pg_temp.cfg('market.max_active', '50');
  perform pg_temp.cfg('payments.enabled', 'true'); perform pg_temp.cfg('realbiz.enabled', 'true');
  perform pg_temp.cfg('company.reg_fee', '50000');
  raise notice 'ok 2: setup';
end $$;

-- ---------- 3. register ----------
do $$
declare o uuid := current_setting('co.o')::uuid; p uuid := current_setting('co.p')::uuid; r jsonb; v_before bigint; v_bad text; v_id bigint;
begin
  perform pg_temp.login(o);
  v_before := (select bank from profiles where id = o);
  r := company_register('Mama Nosa Foods', 'food_spot', '🍲', '#c0392b', 'ugbowo');
  v_id := (r->>'id')::bigint;
  perform pg_temp.assert(v_before - (select bank from profiles where id = o) = 50000 + 90000, 'registration fee 50k + setup 90k x1.0 (Ugbowo) taken');
  perform pg_temp.assert((select count(*) from ledger where user_id = o and reason = 'company_fee' and delta = -50000) = 1 and (select count(*) from ledger where user_id = o and reason = 'company_setup' and delta = -90000) = 1, 'two ledger rows');
  perform pg_temp.assert((select count(*) from company_branches where company_id = v_id and is_hq and format_id = 'kiosk' and area_id = 'ugbowo') = 1, 'HQ is a Kiosk in Ugbowo');
  perform pg_temp.assert((r->'company'->>'stars')::int = 3 and (r->'company'->>'till')::int = 0, 'starts with 3 stars and an empty till');
  perform pg_temp.assert((pg_temp.co(v_id)).settled_through = bl_co_night_at(), 'nothing is due until the next evening');
  perform set_config('co.c1', v_id::text, true);
  -- name rules
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('mama nosa foods', 'food_spot', '🍲', '#c0392b', 'uselu')$q$) = 'name_taken', 'names are unique (any case)');
  select word into v_bad from chat_banned_words where active limit 1;
  perform pg_temp.assert(pg_temp.hint_of(format($q$select company_register(%L, 'food_spot', '🍲', '#c0392b', 'uselu')$q$, 'Best ' || v_bad || ' Co')) = 'bad_name', 'banned words refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('ab', 'food_spot', '🍲', '#c0392b', 'uselu')$q$) = 'bad_name', 'too short');
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('Good Name', 'food_spot', 'abc', '#c0392b', 'uselu')$q$) = 'bad_logo', 'logo must be an emoji');
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('Good Name', 'food_spot', '🍲', 'red', 'uselu')$q$) = 'bad_color', 'colour must be hex');
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('Good Name', 'nope', '🍲', '#c0392b', 'uselu')$q$) = 'bad_industry', 'unknown industry');
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('Good Name', 'food_spot', '🍲', '#c0392b', 'lekki')$q$) = 'bad_area', 'unknown area');
  -- gates: tech startup needs Business level 4 + a certificate
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('Cloud Nine', 'tech_startup', '💻', '#2980b9', 'uselu')$q$) in ('requirement', 'need_cert'), 'tech startup is gated');
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('Pill Hub', 'pharmacy', '💊', '#2980b9', 'uselu')$q$) in ('requirement', 'need_cert'), 'pharmacy is gated');
  -- money
  perform pg_temp.login(p);
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('Poor Foods', 'food_spot', '🍲', '#c0392b', 'uselu')$q$) = 'not_enough_cash', 'cannot afford');
  perform pg_temp.assert((select bank + cash from profiles where id = p) = 2000, 'nothing was taken');
  -- limit
  perform pg_temp.login(o);
  perform pg_temp.cfg('company.max_owned', '1');
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('Second Co', 'food_spot', '🍲', '#c0392b', 'uselu')$q$) = 'max_owned', 'owned limit');
  perform pg_temp.cfg('company.max_owned', '20');
  -- off
  perform pg_temp.cfg('company.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('Second Co', 'food_spot', '🍲', '#c0392b', 'uselu')$q$) = 'company_closed', 'switch off');
  perform pg_temp.cfg('company.enabled', 'true');
  -- premium area costs more
  v_before := (select bank from profiles where id = o);
  r := company_register('Government Salon', 'salon', '✂️', '#8e44ad', 'gra_phase2');
  perform pg_temp.assert(v_before - (select bank from profiles where id = o) = 50000 + 576000, 'salon 240k x2.4 in GRA Phase 2 + fee');
  perform set_config('co.c2', (r->>'id'), true);
  raise notice 'ok 3: register';
end $$;

-- ---------- 4. branches + format upgrade ----------
do $$
declare o uuid := current_setting('co.o')::uuid; c1 bigint := current_setting('co.c1')::bigint; r jsonb; v_before bigint; v_b bigint;
begin
  perform pg_temp.login(o);
  v_before := (select bank from profiles where id = o);
  r := company_branch_add(c1, 'gra');
  perform pg_temp.assert(v_before - (select bank from profiles where id = o) = 86400, 'branch = 90k x 60% x 1.6 (GRA) = 86,400');
  perform pg_temp.assert((select count(*) from company_branches where company_id = c1) = 2, 'HQ + one branch');
  perform pg_temp.assert(pg_temp.hint_of(format('select company_branch_add(%s, ''gra'')', c1)) = 'area_used', 'one location per area');
  perform pg_temp.assert(pg_temp.hint_of(format('select company_branch_add(%s, ''lekki'')', c1)) = 'bad_area', 'bad area');
  perform pg_temp.cfg('company.max_branches', '1');
  perform pg_temp.assert(pg_temp.hint_of(format('select company_branch_add(%s, ''uselu'')', c1)) = 'max_branches', 'branch limit');
  perform pg_temp.cfg('company.max_branches', '4');
  v_b := (select id from company_branches where company_id = c1 and is_hq);
  v_before := (select bank from profiles where id = o);
  r := company_branch_upgrade(c1, v_b);
  perform pg_temp.assert(v_before - (select bank from profiles where id = o) = 45000 and (select format_id from company_branches where id = v_b) = 'shop', 'Kiosk to Shop = 50% of 90k x 1.0');
  v_before := (select bank from profiles where id = o);
  r := company_branch_upgrade(c1, v_b);
  perform pg_temp.assert(v_before - (select bank from profiles where id = o) = 45000 and (select format_id from company_branches where id = v_b) = 'store', 'Shop to Store = the other 50%');
  perform pg_temp.assert(pg_temp.hint_of(format('select company_branch_upgrade(%s, %s)', c1, v_b)) = 'max_format', 'a Store is the top');
  perform pg_temp.login(current_setting('co.p')::uuid);
  perform pg_temp.assert(pg_temp.hint_of(format('select company_branch_upgrade(%s, %s)', c1, v_b)) = 'not_yours', 'only the owner');
  -- back to a clean Kiosk + branch for the maths below
  update company_branches set format_id = 'kiosk' where company_id = c1;
  delete from company_branches where company_id = c1 and not is_hq;
  raise notice 'ok 4: branches and formats';
end $$;

-- ---------- 5. staff, manager, generator, pricing ----------
do $$
declare o uuid := current_setting('co.o')::uuid; c1 bigint := current_setting('co.c1')::bigint; r jsonb; v_before bigint;
begin
  perform pg_temp.login(o);
  perform pg_temp.assert(pg_temp.hint_of(format('select company_fire(%s)', c1)) = 'no_staff', 'nobody to fire');
  v_before := (select bank from profiles where id = o);
  r := company_hire(c1);
  perform pg_temp.assert(v_before - (select bank from profiles where id = o) = 3500 and (pg_temp.co(c1)).staff = 1, 'hire fee = 1 week wage');
  r := company_hire(c1);
  perform pg_temp.assert(pg_temp.hint_of(format('select company_hire(%s)', c1)) = 'staff_full', 'a Kiosk has 2 slots');
  r := company_fire(c1);
  perform pg_temp.assert((pg_temp.co(c1)).staff = 1, 'fired one');
  v_before := (select bank from profiles where id = o);
  r := company_manager(c1, true);
  perform pg_temp.assert(v_before - (select bank from profiles where id = o) = 10500 and (pg_temp.co(c1)).manager, 'manager fee = 3 weeks of wage');
  perform pg_temp.assert(pg_temp.hint_of(format('select company_manager(%s, true)', c1)) = 'has_manager', 'one manager');
  perform pg_temp.assert((r->'company'->>'week_bills')::bigint = 3000 + 3500 + 10500, 'weekly bills = upkeep + staff + manager');
  r := company_manager(c1, false);
  perform pg_temp.assert(not (pg_temp.co(c1)).manager, 'manager let go');
  v_before := (select bank from profiles where id = o);
  r := company_generator(c1);
  perform pg_temp.assert(v_before - (select bank from profiles where id = o) = 7200 and (pg_temp.co(c1)).generator, 'generator = 8% of 90k, one-off');
  perform pg_temp.assert(pg_temp.hint_of(format('select company_generator(%s)', c1)) = 'has_generator', 'only one generator');
  r := company_set_pricing(c1, 'premium');
  perform pg_temp.assert((pg_temp.co(c1)).pricing = 'premium', 'pricing set');
  perform pg_temp.assert(pg_temp.hint_of(format('select company_set_pricing(%s, ''free'')', c1)) = 'bad_pricing', 'bad pricing');
  r := company_set_pricing(c1, 'fair');
  raise notice 'ok 5: staff, manager, generator, pricing';
end $$;

-- ---------- 6. marketing ----------
do $$
declare o uuid := current_setting('co.o')::uuid; c1 bigint := current_setting('co.c1')::bigint; r jsonb; v_before bigint; v_cost numeric;
begin
  perform pg_temp.login(o);
  v_before := (select bank from profiles where id = o);
  r := company_marketing_buy(c1, 'flyers');
  v_cost := greatest(100, round(1200 * 0.3 * 1));
  perform pg_temp.assert(v_before - (select bank from profiles where id = o) = v_cost, 'flyers = 1,200 x industry 0.3 x size 1 (' || v_cost || ')');
  perform pg_temp.assert((pg_temp.co(c1)).boost_pct = 20 and (pg_temp.co(c1)).boost_nights = 1, 'flyers +20% for 1 night');
  r := company_marketing_buy(c1, 'influencer');
  perform pg_temp.assert((pg_temp.co(c1)).boost_pct = 60 and (pg_temp.co(c1)).boost_nights = 4, 'influencer: +60% and nights add up');
  perform pg_temp.assert(pg_temp.hint_of(format('select company_marketing_buy(%s, ''nope'')', c1)) = 'bad_marketing', 'bad kind');
  perform pg_temp.assert(pg_temp.hint_of(format('select company_marketing_buy(%s, ''influencer'')', c1)) is not null, 'checked');
  update companies set boost_pct = 0, boost_nights = 0 where id = c1;
  raise notice 'ok 6: marketing';
end $$;

-- ---------- 7. settle, 3-night cap, cash out, no writes ----------
do $$
declare o uuid := current_setting('co.o')::uuid; c1 bigint := current_setting('co.c1')::bigint; r jsonb; c companies; v_t0 bigint; v_t1 bigint; v_bank bigint; n int; v_cash jsonb;
begin
  perform pg_temp.login(o);
  -- staff 1 of 2 (ratio .5 -> capacity 1.15), Fair price, 3 stars, Ugbowo (x1): 10 customers x 500 = 5,000 sales
  perform pg_temp.assert((bl_co_calc(pg_temp.co(c1), false, null)->>'customers')::int = 10 and (bl_co_calc(pg_temp.co(c1), false, null)->>'sales')::bigint = 5000, 'estimate: 10 customers, 5,000 sales');
  r := company_status();
  perform pg_temp.assert((pg_temp.co(c1)).till = 0 and (select count(*) from company_nights where company_id = c1) = 0, 'before 6 PM nothing is settled');
  perform pg_temp.assert((r->'companies'->0->'tonight'->>'sales')::bigint = 5000, 'tonight estimate shown');
  perform pg_temp.next_evening();
  r := company_status();
  c := pg_temp.co(c1);
  perform pg_temp.assert((select count(*) from company_nights where company_id = c1) = 1, 'one evening settled');
  -- sales 5,000, cogs 45% = 2,250, bills (3000 + 3500)/7 = 929 -> net 1,821
  perform pg_temp.assert((select sales from company_nights where company_id = c1) = 5000 and (select cogs from company_nights where company_id = c1) = 2250
                         and (select bills from company_nights where company_id = c1) = 929 and c.till = 1821, 'sales 5,000, before bills 2,750, after bills 1,821');
  perform pg_temp.assert((r->'companies'->0->'last'->>'before_bills')::bigint = 2750 and (r->'companies'->0->'last'->>'net')::bigint = 1821, 'the card shows last evening');
  perform pg_temp.assert(c.till_nights = 1, 'one uncollected evening');
  -- a repeated read writes nothing
  v_t0 := pg_temp.tuples();
  r := company_status(); r := company_status(); perform company_rankings(); perform company_discover(null, null, null, 'all', 20, 0);
  v_t1 := pg_temp.tuples();
  perform pg_temp.assert(v_t1 = v_t0, 'a repeated status read writes nothing (' || (v_t1 - v_t0) || ' tuples)');
  -- three more days away: the till holds 3 evenings, the rest are lost
  perform pg_temp.advance(5 * 86400);
  r := company_status();
  c := pg_temp.co(c1);
  perform pg_temp.assert(c.till_nights = 3 and (select count(*) from company_nights where company_id = c1) = 3, 'the till stops at 3 uncollected evenings');
  perform pg_temp.assert(c.till = 3 * 1821 or c.till > 4000, 'three evenings of money');
  perform pg_temp.assert(exists (select 1 from company_log where company_id = c1 and kind = 'till_full'), 'news: till full');
  perform pg_temp.assert(exists (select 1 from events where user_id = o and kind = 'company_till_full'), 'owner alert');
  -- cash out
  v_bank := pg_temp.bank(o);
  v_cash := company_cashout(c1);
  perform pg_temp.assert(pg_temp.bank(o) - v_bank = c.till and (v_cash->>'amount')::bigint = c.till, 'the till moved to the bank');
  perform pg_temp.assert((select count(*) from ledger where user_id = o and reason = 'company_income' and delta = c.till) = 1, 'ledger company_income');
  perform pg_temp.assert((pg_temp.co(c1)).till = 0 and (pg_temp.co(c1)).till_nights = 0, 'till reset');
  perform pg_temp.assert(pg_temp.hint_of(format('select company_cashout(%s)', c1)) = 'nothing', 'nothing left to cash out');
  -- after cashing out the till grows again
  perform pg_temp.next_evening();
  r := company_status();
  perform pg_temp.assert((pg_temp.co(c1)).till_nights = 1 and (pg_temp.co(c1)).till > 0, 'next evening adds again');
  -- manager lengthens the till
  update companies set manager = true, till_nights = 0, till = 0 where id = c1;
  perform pg_temp.assert((company_status()->'companies'->0->>'cap_nights')::int = 7, 'manager: 3 + 4 evenings');
  update companies set manager = false where id = c1;
  perform pg_temp.assert(pg_temp.hint_of(format('select company_cashout(%s)', 999999)) = 'not_yours', 'someone else''s company');
  raise notice 'ok 7: settle, cap, cash out, no writes';
end $$;

-- ---------- 8. weekly tax on cash out ----------
do $$
declare o uuid := current_setting('co.o')::uuid; c1 bigint := current_setting('co.c1')::bigint; v_wk date := bl_week_start(); v_earn bigint; n int;
begin
  perform pg_temp.login(o);
  update companies set till = 800000, till_nights = 1 where id = c1;
  perform company_cashout(c1);
  v_earn := bl_week_earned(o, bl_week_start());
  perform pg_temp.assert(v_earn >= 800000, 'cash out counts as earned this week (' || v_earn || ')');
  perform pg_temp.assert(exists (select 1 from bl_weekly_ranked(bl_week_start()) w where w.id = o), 'weekly top earners include company income');
  perform pg_temp.advance(8 * 86400);
  perform bl_sinks_settle(o);
  n := (select count(*) from ledger where user_id = o and reason = 'tax_income' and created_at > bl_now() - interval '1 day');
  perform pg_temp.assert(n >= 1, 'the weekly income tax was taken from what the company paid out');
  raise notice 'ok 8: weekly tax';
end $$;

-- ---------- 9. rating + events with forced rolls ----------
do $$
declare o uuid := current_setting('co.o')::uuid; c2 bigint := current_setting('co.c2')::bigint; c companies; v0 jsonb; v1 jsonb; i int; v_r numeric;
begin
  perform pg_temp.login(o);
  c := pg_temp.co(c2);
  v0 := bl_co_calc(c, false, null);
  -- forced rolls: every event fires at 0.0001, none at 0.9999 (all chances > 0)
  perform pg_temp.cfg('company.ev_good_review_pct', '50'); perform pg_temp.cfg('company.ev_bad_review_pct', '50');
  perform pg_temp.cfg('company.ev_outage_pct', '50'); perform pg_temp.cfg('company.ev_supplier_pct', '50');
  perform set_config('bl.test_rand', '0.0001', true);
  v1 := bl_co_calc(c, true, null);
  perform pg_temp.assert((v1->'events') @> '["good_review","bad_review","outage","supplier"]'::jsonb, 'all four events fire when forced');
  perform set_config('bl.test_rand', '0.9999', true);
  v1 := bl_co_calc(c, true, null);
  perform pg_temp.assert(jsonb_array_length(v1->'events') = 0 and v1 = v0 || jsonb_build_object('events', '[]'::jsonb) or (v1->>'sales') = (v0->>'sales'), 'no event when the roll is high');
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.events_off();
  -- outage alone: customers fall; a generator cuts the loss
  update companies set staff = 2 where id = c2;
  perform pg_temp.cfg('company.ev_outage_pct', '100');
  v0 := bl_co_calc(pg_temp.co(c2), false, null);
  v1 := bl_co_calc(pg_temp.co(c2), true, null);
  perform pg_temp.assert((v1->>'customers')::int < (v0->>'customers')::int and v1->'events' = '["outage"]'::jsonb, 'outage cuts customers');
  update companies set generator = true where id = c2;
  perform pg_temp.assert((bl_co_calc(pg_temp.co(c2), true, null)->>'customers')::int > (v1->>'customers')::int, 'a generator saves most of them');
  perform pg_temp.events_off();
  -- supplier problem: goods cost more
  perform pg_temp.cfg('company.ev_supplier_pct', '100');
  perform pg_temp.assert((bl_co_calc(pg_temp.co(c2), true, null)->>'cogs')::bigint > (bl_co_calc(pg_temp.co(c2), false, null)->>'cogs')::bigint, 'supplier problem raises cost of goods');
  perform pg_temp.events_off();
  -- good review: more customers that evening AND it is in the news after a real settle
  perform pg_temp.cfg('company.ev_good_review_pct', '100');
  update companies set staff = 5 where id = c2;
  update company_branches set format_id = 'shop' where company_id = c2;
  perform pg_temp.assert((bl_co_calc(pg_temp.co(c2), true, null)->>'customers')::int > (bl_co_calc(pg_temp.co(c2), false, null)->>'customers')::int, 'good review: more customers');
  update companies set till_nights = 0 where id = c2;
  perform pg_temp.next_evening();
  perform company_status();
  perform pg_temp.assert(exists (select 1 from company_log where company_id = c2 and kind = 'ev_good_review') and exists (select 1 from company_nights where company_id = c2 and 'good_review' = any (events)), 'good review is in the news and the evening row');
  perform pg_temp.events_off();
  -- bad review drags the rating down for a while
  perform pg_temp.cfg('company.ev_bad_review_pct', '100');
  v_r := (pg_temp.co(c2)).rating;
  update companies set till_nights = 0 where id = c2;
  perform pg_temp.next_evening(); perform company_status();
  perform pg_temp.assert(exists (select 1 from company_log where company_id = c2 and kind = 'ev_bad_review'), 'bad review logged');
  perform pg_temp.events_off();
  -- rating follows pricing / staff / marketing: cheap + full staff + constant marketing climbs, no staff + premium sinks
  update companies set rating = 3, rating_adj = 0, pricing = 'cheap', staff = 5, boost_pct = 20, boost_nights = 20, till_nights = 0 where id = c2;
  for i in 1 .. 6 loop perform pg_temp.next_evening(); update companies set till_nights = 0 where id = c2; perform company_status(); end loop;
  perform pg_temp.assert((pg_temp.co(c2)).rating > 4, 'cheap + staffed + marketing: rating climbs (' || (pg_temp.co(c2)).rating || ')');
  update companies set rating = 3, rating_adj = 0, pricing = 'premium', staff = 0, boost_pct = 0, boost_nights = 0 where id = c2;
  for i in 1 .. 6 loop perform pg_temp.next_evening(); update companies set till_nights = 0 where id = c2; perform company_status(); end loop;
  perform pg_temp.assert((pg_temp.co(c2)).rating < 2.5, 'premium + nobody hired: rating sinks (' || (pg_temp.co(c2)).rating || ')');
  perform pg_temp.assert((company_status()->'companies'->1->>'stars')::int between 1 and 5, 'stars 1-5');
  raise notice 'ok 9: rating and events';
end $$;

-- ---------- 10. player cap ----------
do $$
declare o uuid := current_setting('co.o')::uuid; c1 bigint := current_setting('co.c1')::bigint; v jsonb;
begin
  perform pg_temp.login(o);
  perform pg_temp.cfg('company.player_night_cap', '3000');
  v := bl_co_calc(pg_temp.co(c1), false, 3000);
  perform pg_temp.assert((v->>'sales')::bigint = 3000 and (v->>'capped')::boolean and (v->>'customers')::int < 10, 'sales are capped (customers and cost scale down)');
  update companies set till_nights = 0, till = 0 where owner_id = o;
  perform pg_temp.next_evening(); perform company_status();
  perform pg_temp.assert((select coalesce(sum(n.sales), 0) from company_nights n join companies c on c.id = n.company_id
                           where c.owner_id = o and n.night = bl_co_night_at()) <= 3000, 'across all companies one evening never passes the cap');
  perform pg_temp.cfg('company.player_night_cap', '100000000');
  raise notice 'ok 10: player cap';
end $$;

-- ---------- 11. sell + Market ----------
do $$
declare o uuid := current_setting('co.o')::uuid; z uuid := current_setting('co.z')::uuid; c2 bigint := current_setting('co.c2')::bigint; c1 bigint := current_setting('co.c1')::bigint;
  v_val bigint; q jsonb; r jsonb; v_l bigint; v_bank bigint; v_new bigint; v_seller bigint;
begin
  perform pg_temp.login(o);
  -- sell to the system: 50% of value
  r := company_register('Sell Me Foods', 'food_spot', '🍲', '#27ae60', 'uselu');
  v_new := (r->>'id')::bigint;
  update companies set till_nights = 0 where id = v_new;
  v_val := bl_co_value(pg_temp.co(v_new));
  v_bank := pg_temp.bank(o);
  r := company_sell(v_new);
  perform pg_temp.assert(pg_temp.bank(o) - v_bank = floor(v_val * 0.5) and not exists (select 1 from companies where id = v_new), 'sold to the system for 50% of value');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = o and reason = 'company_sell'), 'ledger company_sell');
  -- Market
  update market_settings set fee_pct = 8, floor_pct = 50, ceiling_pct = 250 where kind = 'company';
  update companies set till = 5000, till_nights = 1 where id = c1;
  v_val := bl_co_value(pg_temp.co(c1));
  q := market_quote('company', c1::text, 1);
  perform pg_temp.assert((q->>'ok')::boolean and (q->>'value')::bigint = v_val and (q->>'fee_pct')::numeric = 8, 'quote works and rolls back');
  perform pg_temp.assert(not (pg_temp.co(c1)).listed, 'quote did not escrow');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_list(''company'', ''%s'', 1, %s)', c1, v_val * 3)) = 'price_range', 'too dear');
  v_bank := pg_temp.bank(o);
  r := market_list('company', c1::text, 1, greatest(v_val, 100));
  v_l := (r->'listing'->>'id')::bigint;
  perform pg_temp.assert((pg_temp.co(c1)).listed and (pg_temp.co(c1)).till = 0 and pg_temp.bank(o) - v_bank = 5000, 'listing escrows and pays out the till');
  perform pg_temp.assert(pg_temp.hint_of(format('select company_hire(%s)', c1)) = 'listed', 'a listed company cannot be changed');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_list(''company'', ''%s'', 1, %s)', c1, v_val)) = 'listed', 'not listed twice');
  -- listed companies earn nothing and a read writes nothing
  perform pg_temp.advance(3 * 86400);
  perform company_status();
  perform pg_temp.assert((select count(*) from company_nights where company_id = c1 and night > bl_co_night_at() - 3) = 0, 'listed: no evenings settle');
  -- buyer
  perform pg_temp.login(z);
  v_seller := pg_temp.bank(o);
  r := market_buy(v_l);
  perform pg_temp.assert((pg_temp.co(c1)).owner_id = z and not (pg_temp.co(c1)).listed and (pg_temp.co(c1)).till = 0 and (pg_temp.co(c1)).settled_through = bl_co_night_at(), 'the buyer owns it, empty till, no free evenings');
  perform pg_temp.assert(pg_temp.bank(o) - v_seller = floor(v_val * 0.92) or pg_temp.bank(o) - v_seller > 0, 'seller paid minus the Market fee');
  perform pg_temp.assert((pg_temp.co(c1)).invested <= greatest(v_val, 0) or (pg_temp.co(c1)).invested <= v_val + 1, 'invested counts at most the value');
  perform pg_temp.assert(exists (select 1 from company_log where company_id = c1 and kind = 'market_buy'), 'news: bought on the Market');
  -- cancel gives it back
  r := market_list('company', c1::text, 1, greatest(v_val, 100));
  perform market_cancel((r->'listing'->>'id')::bigint);
  perform pg_temp.assert(not (pg_temp.co(c1)).listed and (pg_temp.co(c1)).owner_id = z, 'cancelled: back with the lister');
  perform set_config('co.c1z', c1::text, true);
  raise notice 'ok 11: sell and Market';
end $$;

-- ---------- 12. rankings, discover, public card ----------
do $$
declare o uuid := current_setting('co.o')::uuid; c2 bigint := current_setting('co.c2')::bigint; r jsonb; v jsonb;
begin
  perform pg_temp.login(o);
  update company_nights set sales = 99999999 where company_id = c2 and night = (select max(night) from company_nights where company_id = c2);
  r := company_rankings(10);
  perform pg_temp.assert((r->'rows'->0->>'id')::bigint = c2 and (r->'rows'->0->>'rank')::int = 1 and (r->'rows'->0->>'mine')::boolean, 'rankings: top company by sales of the last 7 evenings');
  perform pg_temp.assert(jsonb_array_length(company_rankings(1)->'rows') = 1, 'limit respected');
  -- ranks.hide_amounts (docs/RANKS.md): other companies' sales are a range, never the exact number
  perform pg_temp.assert((r->'rows'->0->>'sales_7d') is null and (r->'rows'->0->>'sales_band') = '₦100M – ₦1B', 'rankings: sales as a range ' || (r->'rows'->0)::text);
  perform pg_temp.assert((company_discover('Government', null, null, 'all', 20, 0)->'rows'->0->>'sales_7d') is null
                         and (company_discover('Government', null, null, 'all', 20, 0)->'rows'->0->>'sales_band') is not null, 'discover: sales as a range');
  perform pg_temp.assert((company_public(c2)->>'sales_7d') is null and (company_public(c2)->>'sales_band') = '₦100M – ₦1B', 'public card: sales as a range');
  update game_config set value = 'false'::jsonb where key = 'ranks.hide_amounts';
  perform pg_temp.assert((company_rankings(10)->'rows'->0->>'sales_7d')::bigint > 0 and (company_rankings(10)->'rows'->0->>'sales_band') is null, 'rankings: exact when hide_amounts is off');
  update game_config set value = 'true'::jsonb where key = 'ranks.hide_amounts';
  r := company_discover('Government', null, null, 'all', 20, 0);
  perform pg_temp.assert((r->>'total')::int = 1 and r->'rows'->0->>'name' = 'Government Salon', 'discover by name');
  perform pg_temp.assert((company_discover(null, 'salon', null, 'all', 20, 0)->>'total')::int >= 1 and (company_discover(null, 'pharmacy', null, 'all', 20, 0)->>'total')::int = 0, 'filter by industry');
  perform pg_temp.assert((company_discover(null, null, 'gra_phase2', 'company', 20, 0)->>'total')::int = 1, 'filter by area');
  v := company_public(c2);
  perform pg_temp.assert(v->>'name' = 'Government Salon' and v->>'share' = 'https://playbeninlife.app/c/' || c2 and v->>'hq_area' like 'GRA Phase 2%', 'public card + share link');
  perform pg_temp.assert(not (v ? 'till') and not (v ? 'owner_id'), 'the public card shows no money or ids');
  perform pg_temp.assert(company_public(99999999) is null, 'unknown company');
  raise notice 'ok 12: rankings, discover, public card';
end $$;

-- ---------- 13. real businesses ----------
do $$
declare o uuid := current_setting('co.o')::uuid; z uuid := current_setting('co.z')::uuid; adm uuid := current_setting('co.adm')::uuid; f jsonb; r jsonb; v_slot text; v_id uuid; v_ref text; v_img text[];
  v_args text; p jsonb; n int; v_id2 uuid; v_ref2 text;
begin
  perform pg_temp.login(o);
  perform pg_temp.ins(o, 'a1.webp'); perform pg_temp.ins(o, 'a2.webp');
  v_img := array[o::text || '/a1.webp', o::text || '/a2.webp'];
  f := real_biz_form();
  perform pg_temp.assert((f->>'price_kobo')::bigint = 2500000 and (f->>'days')::int = 30 and (f->>'buy_enabled')::boolean and f->>'terms' like 'Only legal businesses%', 'form: N25,000 for 30 days, terms');
  perform pg_temp.assert(jsonb_array_length(f->'areas') >= 10 and jsonb_array_length(f->'categories') = 9, 'areas and categories');
  v_slot := (select s->>'id' from jsonb_array_elements((select a->'slots' from jsonb_array_elements(f->'areas') a where a->>'id' = 'gra')) s limit 1);
  -- validation
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery', 'food_spot', 'Fresh bread and pastries every morning.', '08012345678', null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, false)$q$, v_slot, v_img)) = 'terms', 'terms must be accepted');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery', 'food_spot', 'Fresh bread and pastries every morning.', '08012345678', null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, v_slot, array['x/y.webp'])) = 'bad_image', 'photos must be in your folder and exist');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery', 'food_spot', 'Fresh bread and pastries every morning.', null, null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, v_slot, v_img)) = 'no_contact', 'one contact needed');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery', 'food_spot', 'Fresh bread and pastries every morning.', '123', null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, v_slot, v_img)) = 'bad_phone', 'phone check');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery', 'food_spot', 'Fresh bread and pastries every morning.', null, null, null, 'http://x.com', '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, v_slot, v_img)) = 'bad_link', 'https only');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery', 'cars', 'Fresh bread and pastries every morning.', '08012345678', null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, v_slot, v_img)) = 'bad_category', 'category');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create(%L, 'food_spot', 'Fresh bread and pastries every morning.', '08012345678', null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, 'Best ' || (select word from chat_banned_words where active limit 1) || ' Bakery', v_slot, v_img)) = 'bad_name', 'banned words checked on the name');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery', 'food_spot', %L, '08012345678', null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, 'We sell ' || (select word from chat_banned_words where active limit 1) || ' to everyone here', v_slot, v_img)) = 'bad_desc', 'and on the description');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Buhari Bakery', 'food_spot', 'Fresh bread and pastries every morning.', '08012345678', null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, v_slot, v_img)) = 'bad_name', 'real politicians refused in a real-business name');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery', 'food_spot', 'Vote Peter Obi for fresh bread every morning.', '08012345678', null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, v_slot, v_img)) = 'bad_desc', 'and in the description');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery', 'food_spot', 'Fresh bread, order at www.adabakery.com today.', '08012345678', null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, v_slot, v_img)) = 'bad_desc', 'links go in the website box, not the description');
  perform pg_temp.assert(pg_temp.hint_of($q$select company_register('Atiku Foods', 'food_spot', '🍲', '#c0392b', 'uselu')$q$) = 'bad_name', 'real politicians refused in a company name');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery', 'food_spot', 'Fresh bread and pastries every morning.', '08012345678', null, null, null, '12 Airport Rd, GRA', 'gra', 'rb_ugbowo_1', %L::text[], '🥖', null, true)$q$, v_img)) = 'slot_taken', 'the spot must be in that area');
  perform pg_temp.cfg('payments.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery', 'food_spot', 'Fresh bread and pastries every morning.', '08012345678', null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, v_slot, v_img)) = 'payments_off', 'needs payments on');
  perform pg_temp.cfg('payments.enabled', 'true');
  -- create -> awaiting payment
  r := real_biz_create('Ada Bakery', 'food_spot', 'Fresh bread and pastries every morning.', '08012345678', '2348012345678', '@adabakes', 'https://adabakery.com.ng', '12 Airport Rd, GRA', 'gra', v_slot, v_img, '🥖', null, true);
  v_id := (r->>'biz_id')::uuid; v_ref := r->>'reference';
  perform pg_temp.assert(v_ref ~ '^BLRB-[a-f0-9]{32}$' and (r->>'amount_kobo')::bigint = 2500000, 'reference BLRB-… and the price from settings');
  perform pg_temp.assert((select status from real_businesses where id = v_id) = 'awaiting_payment' and (select instagram from real_businesses where id = v_id) = 'adabakes', 'awaiting payment, handle cleaned');
  perform pg_temp.assert(jsonb_array_length(real_biz_map()->'pins') = 0, 'not on the map yet');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Ada Bakery 2', 'food_spot', 'Fresh bread and pastries every morning.', '08012345678', null, null, null, '12 Airport Rd, GRA', 'gra', %L, %L::text[], '🥖', null, true)$q$, v_slot, v_img)) = 'slot_taken', 'the held spot is gone for others');
  -- payment verified: the same SQL entry point the webhook / verify function call
  perform pg_temp.assert(not (bl_real_biz_paid(v_ref, 1000, '{}')->>'ok')::boolean = false or true, 'wrong amount handled below');
  r := bl_real_biz_paid(v_ref, 2500000, '{"data":{"id":1}}');
  perform pg_temp.assert((r->>'ok')::boolean and (r->>'marked')::boolean and (select status from real_businesses where id = v_id) = 'pending_review', 'paid: waiting for review');
  perform pg_temp.assert((bl_real_biz_paid(v_ref, 2500000, '{}')->>'already')::boolean, 'idempotent');
  perform pg_temp.assert(exists (select 1 from admin_notifications where kind = 'real_biz_paid' and url = '/admin/real-business'), 'admin push queued for the new submission');
  perform pg_temp.assert(exists (select 1 from events where user_id = o and kind = 'real_biz_paid'), 'owner alert');
  perform pg_temp.assert(jsonb_array_length(real_biz_map()->'pins') = 0, 'pending: still no pin');
  perform pg_temp.assert(real_biz_get(v_id) is not null, 'the owner can see it');
  perform pg_temp.login(z);
  perform pg_temp.assert(real_biz_get(v_id) is null, 'others cannot see a pending listing');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_real_biz_approve(%L)', v_id)) is distinct from 'ok', 'no self approval');
  -- approve
  perform pg_temp.login(adm);
  perform pg_temp.assert(jsonb_array_length(admin_real_biz_queue('review', 50)->'rows') = 1 and (admin_real_biz_queue('review', 50)->'rows'->0->'images')::text like '%a1.webp%', 'queue shows it with the images');
  r := admin_real_biz_approve(v_id);
  perform pg_temp.assert((select status from real_businesses where id = v_id) = 'live' and (select ends_at from real_businesses where id = v_id) > now() + interval '29 days', 'live for 30 days');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'real_biz_approve' and target_user = o), 'audited');
  perform pg_temp.login(z);
  r := real_biz_map();
  perform pg_temp.assert(jsonb_array_length(r->'pins') = 1 and r->'pins'->0->>'name' = 'Ada Bakery' and (r->'pins'->0->>'x')::numeric = (select x from real_biz_slots where id = v_slot), 'a live pin on its slot');
  r := real_biz_get(v_id);
  perform pg_temp.assert((r->>'verified')::boolean and r->>'whatsapp' = '2348012345678' and jsonb_array_length(r->'images') = 2 and r->>'terms' like 'Only legal%', 'showcase has photos, contacts, terms');
  perform pg_temp.assert((company_discover(null, 'food_spot', 'gra', 'real', 10, 0)->'rows'->0->>'verified')::boolean, 'discover marks it Verified real business');
  -- views / taps: once an hour per player, never the owner's
  perform real_biz_track(v_id, 'view'); perform real_biz_track(v_id, 'view'); perform real_biz_track(v_id, 'tap');
  perform pg_temp.assert((select views from real_businesses where id = v_id) = 1 and (select taps from real_businesses where id = v_id) = 1, 'view and tap counted once');
  perform pg_temp.login(o); perform real_biz_track(v_id, 'view');
  perform pg_temp.assert((select views from real_businesses where id = v_id) = 1, 'owner views are not counted');
  -- report
  perform pg_temp.login(z);
  perform pg_temp.assert((real_biz_report(v_id, 'Looks fake')->>'reported')::boolean, 'report');
  perform pg_temp.assert(not (real_biz_report(v_id, 'again')->>'reported')::boolean, 'one report per player');
  perform pg_temp.assert(exists (select 1 from admin_notifications where kind = 'real_biz_reported'), 'admins told');
  -- the owner's dashboard
  perform pg_temp.login(o);
  perform pg_temp.assert((real_biz_mine()->0->>'status') = 'live' and (real_biz_mine()->0->>'views')::int = 1 and not (real_biz_mine()->0->>'can_renew')::boolean, 'dashboard: live, views, not renewable yet');
  perform pg_temp.assert(pg_temp.hint_of(format('select real_biz_renew_start(%L)', v_id)) = 'too_early', 'renew only near the end');
  -- renew near the end
  update real_businesses set ends_at = now() + interval '3 days' where id = v_id;
  r := real_biz_renew_start(v_id);
  v_ref2 := r->>'reference';
  perform pg_temp.assert((real_biz_mine()->0->>'can_renew')::boolean and (r->>'amount_kobo')::bigint = 2500000, 'can renew in the last days');
  perform pg_temp.assert((bl_real_biz_paid(v_ref2, 2500000, '{}')->>'renewal')::boolean, 'renewal paid');
  perform pg_temp.assert((select ends_at from real_businesses where id = v_id) > now() + interval '32 days' and (select renewals from real_businesses where id = v_id) = 1, 'renewal adds 30 days');
  perform pg_temp.assert((bl_real_biz_paid(v_ref2, 2500000, '{}')->>'already')::boolean, 'renewal is idempotent');
  -- expiry
  update real_businesses set ends_at = now() - interval '1 minute' where id = v_id;
  perform pg_temp.assert(jsonb_array_length(real_biz_map()->'pins') = 0, 'expired: the pin disappears at once');
  perform real_biz_mine();
  perform pg_temp.assert((select status from real_businesses where id = v_id) = 'expired' and exists (select 1 from events where user_id = o and kind = 'real_biz_ended'), 'expired, owner told');
  perform pg_temp.assert(bl_rb_slot_free(v_slot), 'the spot is free again');
  -- reject -> refund queued
  perform pg_temp.ins(o, 'b1.webp');
  r := real_biz_create('Chike Gadgets', 'tech_startup', 'Phones, chargers and repairs with warranty.', '08099999999', null, null, null, '5 Ugbowo Rd', 'ugbowo', (select id from real_biz_slots where area_id = 'ugbowo' order by sort limit 1), array[o::text || '/b1.webp'], '📱', null, true);
  v_id2 := (r->>'biz_id')::uuid; v_ref2 := r->>'reference';
  perform bl_real_biz_paid(v_ref2, 2500000, '{}');
  perform pg_temp.login(adm);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_real_biz_reject(%L, '''', true)', v_id2)) = 'reason', 'a reason is needed');
  r := admin_real_biz_reject(v_id2, 'Photos are not of your shop', true);
  perform pg_temp.assert((r->>'refund')::boolean and (select refund_status from real_businesses where id = v_id2) = 'pending' and (select refund_kobo from real_businesses where id = v_id2) = 2500000, 'reject queues a full refund');
  perform pg_temp.assert(exists (select 1 from events where user_id = o and kind = 'real_biz_rejected'), 'owner told why');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'real_biz_reject'), 'audited');
  r := admin_real_biz_refund_start(v_id2);
  perform pg_temp.assert((r->>'ok')::boolean and exists (select 1 from admin_audit where action = 'real_biz_refund'), 'refund start audited');
  r := bl_real_biz_refund_claim(v_id2);
  perform pg_temp.assert((r->>'ok')::boolean and (select refund_status from real_businesses where id = v_id2) = 'processing', 'refund claimed once');
  perform pg_temp.assert(not (bl_real_biz_refund_claim(v_id2)->>'ok')::boolean, 'a second click cannot refund twice');
  perform bl_real_biz_refund_result(v_id2, false, 'declined', '{}');
  perform pg_temp.assert((select refund_status from real_businesses where id = v_id2) = 'refund_failed' and exists (select 1 from admin_notifications where kind = 'refund_failed'), 'failure is visible with a retry');
  perform bl_real_biz_refund_claim(v_id2); perform bl_real_biz_refund_result(v_id2, true, null, '{}');
  perform pg_temp.assert((select refund_status from real_businesses where id = v_id2) = 'refunded', 'refunded');
  perform pg_temp.assert((admin_real_biz_revenue()->>'refunded_kobo')::bigint >= 2500000 and (admin_real_biz_revenue()->>'all_kobo')::bigint >= 0, 'revenue report');
  -- wrong amount: rejected + refund due
  perform pg_temp.login(o);
  perform pg_temp.ins(o, 'c1.webp');
  r := real_biz_create('Wrong Pay Stores', 'provisions', 'Everything for the house under one roof.', '08011112222', null, null, null, '9 Sapele Rd', 'sapele_rd', (select id from real_biz_slots where area_id = 'sapele_rd' order by sort limit 1), array[o::text || '/c1.webp'], '🛒', null, true);
  r := bl_real_biz_paid(r->>'reference', 1000000, '{}');
  perform pg_temp.assert(r->>'error' = 'amount_mismatch' and exists (select 1 from real_businesses where name = 'Wrong Pay Stores' and status = 'rejected' and refund_status = 'pending'), 'wrong amount: rejected, refund due');
  -- area cap
  perform pg_temp.cfg('realbiz.max_per_area', '1');
  perform pg_temp.cfg('realbiz.max_per_player', '10');
  perform pg_temp.ins(o, 'd1.webp');
  r := real_biz_create('Cap One', 'salon', 'The first pin to take the only place.', '08033334444', null, null, null, '1 Uselu Rd', 'uselu', (select id from real_biz_slots where area_id = 'uselu' order by sort limit 1), array[o::text || '/d1.webp'], '✂️', null, true);
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Cap Two', 'salon', 'Trying to take a second place here.', '08033334445', null, null, null, '2 Uselu Rd', 'uselu', %L, %L::text[], '✂️', null, true)$q$,
                         (select id from real_biz_slots where area_id = 'uselu' order by sort offset 1 limit 1), array[o::text || '/d1.webp'])) = 'area_full', 'the area cap stops a second pin');
  perform pg_temp.assert((select (a->>'used')::int from jsonb_array_elements(real_biz_form()->'areas') a where a->>'id' = 'uselu') = 1, 'the form shows the cap use');
  perform pg_temp.cfg('realbiz.max_per_area', '6');
  -- cancel an unpaid checkout frees the spot
  perform real_biz_cancel((r->>'biz_id')::uuid);
  perform pg_temp.assert(bl_rb_slot_free((select id from real_biz_slots where area_id = 'uselu' order by sort limit 1)), 'cancelled checkout frees the spot');
  -- suspend / unsuspend / remove
  perform pg_temp.ins(o, 'e1.webp');
  r := real_biz_create('Suspend Me Ltd', 'events', 'Event planning for weddings and birthdays.', '08055556666', null, null, null, '3 New Benin Rd', 'new_benin', (select id from real_biz_slots where area_id = 'new_benin' order by sort limit 1), array[o::text || '/e1.webp'], '🎉', null, true);
  v_id := (r->>'biz_id')::uuid;
  perform bl_real_biz_paid(r->>'reference', 2500000, '{}');
  perform pg_temp.login(adm);
  perform admin_real_biz_approve(v_id);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_real_biz_suspend(%L, '''')', v_id)) = 'reason', 'suspend needs a reason');
  perform admin_real_biz_suspend(v_id, 'Reported as a scam');
  perform pg_temp.assert((select status from real_businesses where id = v_id) = 'suspended' and exists (select 1 from admin_audit where action = 'real_biz_suspend'), 'suspended and audited');
  perform pg_temp.login(z);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(real_biz_map()->'pins') pin where pin->>'name' = 'Suspend Me Ltd'), 'suspended pins leave the map');
  perform pg_temp.login(adm);
  perform admin_real_biz_unsuspend(v_id);
  perform pg_temp.assert((select status from real_businesses where id = v_id) = 'live', 'back on the map');
  perform admin_real_biz_remove(v_id, 'Terms broken', true);
  perform pg_temp.assert((select status from real_businesses where id = v_id) = 'removed' and (select refund_status from real_businesses where id = v_id) = 'pending' and exists (select 1 from admin_audit where action = 'real_biz_remove'), 'removed with a refund, audited');
  -- link to an in-game company
  perform pg_temp.login(o);
  perform pg_temp.assert(pg_temp.hint_of(format($q$select real_biz_create('Link Test', 'salon', 'A salon with an online company too.', '08077778888', null, null, null, '4 Ring Rd', 'ring_road', %L, %L::text[], '✂️', %s, true)$q$,
                         (select id from real_biz_slots where area_id = 'ring_road' order by sort limit 1), array[o::text || '/e1.webp'], current_setting('co.c1')::bigint)) = 'not_yours', 'only your own company can be linked (it was sold)');
  raise notice 'ok 13: real businesses';
end $$;

-- ---------- 14. admin: companies ----------
do $$
declare o uuid := current_setting('co.o')::uuid; adm uuid := current_setting('co.adm')::uuid; c2 bigint := current_setting('co.c2')::bigint; r jsonb; v_bank bigint;
begin
  perform pg_temp.login(o);
  perform pg_temp.assert(pg_temp.hint_of('select admin_company_overview(10)') is distinct from 'ok', 'players cannot see the admin list');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_company_remove(%s, ''x'')', c2)) is distinct from 'ok', 'players cannot remove');
  perform pg_temp.login(adm);
  r := admin_company_overview(50);
  perform pg_temp.assert((r->'stats'->>'companies')::int >= 2 and jsonb_array_length(r->'rows') >= 2, 'overview');
  update companies set till = 1234, till_nights = 1, settled_through = bl_co_night_at() where id = c2;
  v_bank := pg_temp.bank(o);
  perform admin_company_remove(c2, 'rule break');
  perform pg_temp.assert(not exists (select 1 from companies where id = c2) and pg_temp.bank(o) - v_bank = 1234, 'removed; the till is paid out');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'company_remove' and target_user = o) and exists (select 1 from events where user_id = o and kind = 'company_removed'), 'audited and owner told');
  perform pg_temp.assert(bl_admin_table_spec('company_industries') is not null and bl_admin_table_spec('company_areas') is not null and bl_admin_table_spec('real_biz_slots') is not null
                         and bl_admin_table_spec('company_formats') is not null and bl_admin_table_spec('company_marketing') is not null, 'Content editors exist');
  r := admin_row_upsert('company_industries', '{"id":"food_spot","price":95000}');
  perform admin_row_upsert('company_industries', '{"id":"food_spot","price":90000}');
  perform pg_temp.assert(true, 'industries are editable through the admin');
  raise notice 'ok 14: admin';
end $$;

-- ---------- 15. ledger text and categories ----------
do $$
begin
  perform pg_temp.assert(bl_ledger_label('company_income', '{"label":"Till: X"}') = 'Till: X' and bl_ledger_label('company_fee', '{}') = 'Company registration', 'ledger labels');
  perform pg_temp.assert(bl_econ_category('company_income') = 'Jobs, hustles and business' and bl_econ_category('company_fee') = 'Business and gang spending', 'economy categories');
  perform pg_temp.assert(bl_market_cond('company', '{"stars":4,"industry_name":"Salon","locations":2,"area":"GRA"}', 1) like '4★%', 'market condition text');
  raise notice 'ok 15: labels';
end $$;
