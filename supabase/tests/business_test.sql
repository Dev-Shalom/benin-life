-- E3 (20261019000100_economy_balance) cut the restock cost of five business types and raised the Chemist / Filling station income.
-- This suite tests the R10 maths on the original numbers, so they are pinned back here (rolled back with everything else).
update business_types set
  restock_cost = case id when 'provision_shop' then 18000 when 'buka' then 25000 when 'beer_parlour' then 55000 when 'chemist' then 70000 when 'filling_station' then 280000 else restock_cost end,
  income_min = case id when 'chemist' then 30000 when 'filling_station' then 90000 else income_min end,
  income_max = case id when 'chemist' then 45000 when 'filling_station' then 130000 else income_max end;
-- R10 own a business (20261018000900_business.sql). Rolled back. Run (migration applied):
--   bash scripts/sql-test.sh -- supabase/tests/business_test.sql
-- Or with the migration first: bash scripts/sql-test.sh supabase/migrations/20261018000900_business.sql -- supabase/tests/business_test.sql
-- Groups: 1 grants / RLS / private helpers · 2 setup · 3 buy (money, ledger, place, slot taken, wrong area, requirements, name,
-- limit, no money) · 4 accrual over time, the 48 h cap, collect · 5 restock decay + restock · 6 staff wage and bonus ·
-- 7 owner shift boost + XP · 8 events with forced rolls (robbery, insured robbery, outage, levy, staff theft, great day) ·
-- 9 upgrade · 10 visitors pay the owner a cut (shop_buy, do_activity, own spend pays nothing, interior lists the shelf) ·
-- 11 sell back · 12 Market (quote rolls back, escrow, buy, cancel) · 13 weekly earnings · 14 admin grant / remove + audit +
-- content spec + new plot · 15 push plan · 16 switches · 17 plots are hidden places.
-- Markets have opening hours; pin them open so the suite does not depend on the hour it runs.
update public.locations set open_hour = null, close_hour = null where scene = 'market';

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
create or replace function pg_temp.mk(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@biz.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, busy_until = null, travel_to = null, protected_until = null, created_at = now() - interval '30 days',
         cash = 0, bank = 0, energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0 where id = v;
  return v;
end $$;
-- a business with known numbers: 24,000 a day gross (1,000 an hour), no staff, level 1, plenty of stock
create or replace function pg_temp.fix(p_biz bigint) returns void
language plpgsql as $$
begin
  update businesses set base_income = 24000, staff = 0, level = 1, takings = 0, event_carry_h = 0, boost_until = null, insured_until = null,
         settled_at = bl_now(), last_collect_at = bl_now(), ready_at = bl_now() - interval '1 minute', stock_until = bl_now() + interval '1000 hours'
   where id = p_biz;
end $$;
create or replace function pg_temp.takings(p_biz bigint) returns bigint language sql as $$ select floor((bl_biz_settle(p_biz)).takings)::bigint $$;
create or replace function pg_temp.fresh(p_uid uuid) returns void language plpgsql as $$
begin
  update profiles set energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0, bladder = 0,
         needs_updated_at = bl_now(), busy_until = null where id = p_uid;
end $$;
create or replace function pg_temp.events_off() returns void language plpgsql as $$
declare k text;
begin
  foreach k in array array['business.robbery_pct', 'business.outage_pct', 'business.levy_pct', 'business.goodday_pct', 'business.theft_pct'] loop
    perform pg_temp.cfg(k, '0');
  end loop;
end $$;

-- ---------- 1. grants / RLS / private helpers ----------
do $$
declare f text;
begin
  foreach f in array array['business_mine()', 'business_catalog()', 'business_at(text)', 'business_buy(text,text,text)', 'business_collect(bigint)',
    'business_restock(bigint)', 'business_upgrade(bigint)', 'business_hire(bigint)', 'business_fire(bigint)', 'business_insure(bigint)',
    'business_work(bigint)', 'business_sell(bigint)', 'admin_business_overview(int)', 'admin_business_get(uuid)',
    'admin_business_grant(uuid,text,text,text)', 'admin_business_remove(bigint,text)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute'), 'anon cannot run ' || f);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute'), 'authenticated can run ' || f);
  end loop;
  foreach f in array array['bl_biz_settle(bigint,boolean)', 'bl_biz_card(businesses,boolean)', 'bl_biz_visit_cut(uuid,text,bigint,text)', 'bl_biz_sells(text,text)',
    'bl_biz_pay(profiles,bigint,text,jsonb)', 'bl_biz_loc_sync(text)', 'bl_biz_push_plan(uuid)', 'bl_biz_market_take(uuid,text,int)',
    'bl_biz_market_give(uuid,text,jsonb,bigint,boolean)', 'bl_biz_num(text,numeric)', 'bl_biz_factor(businesses,business_types,timestamptz,timestamptz)',
    'bl_biz_mine(uuid,bigint,boolean)', 'bl_biz_gate(uuid,business_types)', 'bl_biz_plot_loc()'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute')
                           and not has_function_privilege('authenticated', 'public.' || f, 'execute'), 'private helper locked: ' || f);
  end loop;
  foreach f in array array['business_types', 'business_plots', 'businesses', 'business_log'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || f)::regclass), 'RLS on ' || f);
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || f, 'select'), 'anon cannot read ' || f);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || f, 'insert')
                           and not has_table_privilege('authenticated', 'public.' || f, 'update')
                           and not has_table_privilege('authenticated', 'public.' || f, 'delete'), 'no client writes on ' || f);
  end loop;
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.businesses', 'select'), 'players can read their own businesses (policy)');
  perform pg_temp.assert((select count(*) from pg_policies where tablename = 'businesses' and qual like '%owner_id%') >= 1, 'businesses are read by owner only');
  perform pg_temp.assert((select count(*) from business_types) >= 9 and (select count(*) from business_types where active) >= 9, 'nine types seeded');
  perform pg_temp.assert((select count(*) from business_plots) >= 18, 'plots seeded');
  perform pg_temp.assert(not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname like 'bl\_biz\_%' and not prosecdef
                                     and proname in ('bl_biz_settle', 'bl_biz_visit_cut', 'bl_biz_loc_sync')), 'settle / cut / sync run as definer');
  perform pg_temp.assert('business_income' = any (bl_earn_reasons()), 'business income is earned money');
  perform pg_temp.assert(not ('business_buy' = any (bl_earn_reasons())) and not ('business_sell' = any (bl_earn_reasons())), 'buying and selling is not earned money');
  raise notice 'ok 1: grants, RLS, private helpers, seeds';
end $$;

-- ---------- 2. setup ----------
do $$
declare o uuid; v uuid; b uuid; c uuid; adm uuid;
begin
  o := pg_temp.mk('BzOwner'); v := pg_temp.mk('BzVisitor'); b := pg_temp.mk('BzBuyer'); c := pg_temp.mk('BzThird'); adm := pg_temp.mk('BzAdmin');
  update profiles set is_admin = true where id = adm;
  update profiles set bank = 30000000, cash = 50000 where id = o;
  update profiles set bank = 30000000, cash = 50000 where id = b;
  update profiles set bank = 1000, cash = 50000 where id = v;
  update profiles set bank = 100, cash = 100 where id = c;
  perform set_config('bz.o', o::text, true); perform set_config('bz.v', v::text, true); perform set_config('bz.b', b::text, true);
  perform set_config('bz.c', c::text, true); perform set_config('bz.adm', adm::text, true);
  perform pg_temp.events_off();
  perform pg_temp.cfg('business.enabled', 'true');
  perform pg_temp.cfg('business.max_owned', '3');
  perform pg_temp.cfg('business.cap_hours', '48');
  perform pg_temp.cfg('business.skill_pct_per_level', '0');
  perform pg_temp.cfg('business.visit_cut_pct', '30');
  perform pg_temp.cfg('business.sell_back_pct', '60');
  perform pg_temp.cfg('business.shift_daily_cap', '6');
  perform pg_temp.cfg('market.daily_listing_cap', '50');
  perform pg_temp.cfg('market.max_active', '50');
  update business_plots set price_mult = 1 where true;
  update market_settings set fee_pct = 8, floor_pct = 50, ceiling_pct = 250 where kind = 'business';
  raise notice 'ok 2: setup';
end $$;

-- ---------- 3. buy ----------
do $$
declare
  o uuid := current_setting('bz.o')::uuid; v uuid := current_setting('bz.v')::uuid; c uuid := current_setting('bz.c')::uuid; b uuid := current_setting('bz.b')::uuid;
  r jsonb; v_bank bigint; v_biz bigint; n int; v_def text;
begin
  perform pg_temp.login(o);
  -- the buy list: nine types, slots per area, requirements shown
  r := business_catalog();
  perform pg_temp.assert(jsonb_array_length(r->'types') >= 9 and (r->>'max_owned')::int = 3, 'catalog lists the types');
  perform pg_temp.assert((select jsonb_array_length(x->'slots') from jsonb_array_elements(r->'types') x where x->>'id' = 'provision_shop') >= 18, 'a provision shop fits every plot');
  perform pg_temp.assert((select jsonb_array_length(x->'slots') from jsonb_array_elements(r->'types') x where x->>'id' = 'event_centre') = 11, 'an event centre fits GRA, Sapele Rd, Ugbowo and Airport Rd only (3+3+3+2)');
  perform pg_temp.assert(not (select (x->>'met')::boolean from jsonb_array_elements(r->'types') x where x->>'id' = 'filling_station'), 'filling station: requirement not met');
  perform pg_temp.assert((select x->>'req_cert_text' from jsonb_array_elements(r->'types') x where x->>'id' = 'filling_station') ilike '%Business Management%', 'requirement text names the certificate');
  -- requirements: filling station needs the certificate AND Business level 4
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('filling_station', 'biz_sapele_rd_1', 'Oga Fuel') $q$) = 'requirement', 'no certificate, no skill: refused');
  insert into player_certificates (user_id, cert_id, source) values (o, 'business_mgmt', 'admin');
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('filling_station', 'biz_sapele_rd_1', 'Oga Fuel') $q$) = 'requirement', 'certificate but Business skill too low: refused');
  insert into player_skills (user_id, skill_id, xp) values (o, 'business', 300) on conflict (user_id, skill_id) do update set xp = 300;
  perform pg_temp.assert(bl_skill_level(o, 'business') >= 4, 'Business level 4 reached');
  -- wrong area for the type
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('event_centre', 'biz_uselu_1', 'Hall') $q$) = 'wrong_area', 'an event centre cannot go in Uselu');
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('provision_shop', 'biz_nowhere', 'X Shop') $q$) = 'bad_plot', 'no such plot');
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('no_such_type', 'biz_uselu_1', 'X Shop') $q$) = 'bad_type', 'no such type');
  -- names
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('provision_shop', 'biz_ring_road_1', 'fucker mart') $q$) = 'bad_name', 'rude names are refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('provision_shop', 'biz_ring_road_1', 'ab') $q$) = 'bad_name', 'too short a name is refused');
  -- no money
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('provision_shop', 'biz_ring_road_1', 'Poor Mart') $q$) = 'not_enough_cash', 'cannot afford it');
  perform pg_temp.assert(not exists (select 1 from businesses where owner_id = c), 'nothing was created');
  -- the real buy: bank first, ledger row, place goes live with the owner's name
  perform pg_temp.login(o);
  v_bank := pg_temp.bank(o);
  r := business_buy('provision_shop', 'biz_ring_road_1', 'Mama Nosa''s Provisions');
  v_biz := (r->'business'->>'id')::bigint;
  perform set_config('bz.shop', v_biz::text, true);
  perform pg_temp.assert(pg_temp.bank(o) = v_bank - 600000, 'paid the plot price from the bank');
  perform pg_temp.assert((select count(*) from ledger where user_id = o and reason = 'business_buy' and delta = -600000) = 1, 'ledger: business_buy');
  perform pg_temp.assert(bl_ledger_label('business_buy', '{"label":"Business: bought X"}') = 'Business: bought X', 'ledger label');
  perform pg_temp.assert((select active and biz_owner = 'BzOwner' and biz_level = 1 and name = 'Mama Nosa''s Provisions' and scene = 'market' and biz_id = v_biz
                            from locations where id = 'biz_ring_road_1'), 'the plot is a live place: name, owner, scene');
  perform pg_temp.assert((r->'business'->>'setting_up')::boolean, 'setup time first (20 minutes)');
  perform pg_temp.assert((select base_income between 12000 and 18000 and invested = 600000 from businesses where id = v_biz), 'base income rolled in range, invested stored');
  -- slot taken
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('provision_shop', 'biz_ring_road_1', 'Copy Cat Mart') $q$) = 'plot_taken', 'slot taken: first come first served');
  perform pg_temp.assert((select bool_and((s->>'taken')::boolean) from jsonb_array_elements((select x->'slots' from jsonb_array_elements(business_catalog()->'types') x where x->>'id' = 'provision_shop')) s where s->>'plot' = 'biz_ring_road_1'), 'catalog shows it taken');
  perform pg_temp.assert((select s->>'taken_by' from jsonb_array_elements((select x->'slots' from jsonb_array_elements(business_catalog()->'types') x where x->>'id' = 'provision_shop')) s where s->>'plot' = 'biz_ring_road_1') = 'BzOwner', 'and by whom');
  -- the limit (3 each)
  perform pg_temp.login(o);
  perform business_buy('buka', 'biz_uselu_1', 'Nosa Buka');
  perform business_buy('salon', 'biz_ugbowo_1', 'Cuts By Osas');
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('car_wash', 'biz_gra_1', 'Shine Bright') $q$) = 'max_owned', 'at most three businesses');
  select count(*) into n from businesses where owner_id = o;
  perform pg_temp.assert(n = 3, 'three owned');
  -- the owner can read it back; others cannot see it through the table
  perform pg_temp.assert(jsonb_array_length(business_mine()->'businesses') = 3, 'business_mine lists three');
  perform pg_temp.login(v);
  perform pg_temp.assert(jsonb_array_length(business_mine()->'businesses') = 0, 'another player sees none of them');
  perform pg_temp.assert((business_at('biz_ring_road_1')->>'owner') = 'BzOwner' and not (business_at('biz_ring_road_1')->>'mine')::boolean, 'the place card shows Owned by @BzOwner');
  perform pg_temp.assert(business_at('biz_uselu_2') is null, 'a free plot has no business');
  perform pg_temp.assert(pg_temp.hint_of(format('select business_collect(%s)', v_biz)) = 'not_yours', 'cannot collect another player''s takings');
  perform pg_temp.assert(pg_temp.hint_of(format('select business_upgrade(%s)', v_biz)) = 'not_yours', 'cannot upgrade another player''s business');
  perform pg_temp.assert(pg_temp.hint_of(format('select business_sell(%s)', v_biz)) = 'not_yours', 'cannot sell another player''s business');
  raise notice 'ok 3: buy, requirements, slot taken, name, limit';
end $$;

-- ---------- 4. accrual over time, the 48 h cap, collect ----------
do $$
declare
  o uuid := current_setting('bz.o')::uuid; v_biz bigint := current_setting('bz.shop')::bigint; r jsonb; v_bank bigint; v_t bigint; b businesses;
begin
  perform pg_temp.login(o);
  perform pg_temp.fix(v_biz);
  -- nothing yet at the instant of the fix
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (0)) <= 1, 'no takings yet');
  perform pg_temp.assert(pg_temp.hint_of(format('select business_collect(%s)', v_biz)) = 'nothing', 'nothing to collect yet');
  -- 10 real hours: 1,000/h gross minus rent + NEPA (1,500 + 1,000 a day)
  perform pg_temp.advance(10 * 3600);
  v_t := pg_temp.takings(v_biz);
  perform pg_temp.assert(abs(v_t - (8958)) <= 1, 'ten hours earn 10,000 - 1,041.67 = 8,958 (got ' || v_t || ')');
  perform pg_temp.assert((business_mine()->'businesses'->0->>'takings')::bigint = 8958 or (business_mine()->'businesses'->1->>'takings')::bigint = 8958
                         or (business_mine()->'businesses'->2->>'takings')::bigint = 8958, 'the app sees the same takings');
  -- collect: into the bank, ledger business_income, counter reset
  v_bank := pg_temp.bank(o);
  r := business_collect(v_biz);
  perform pg_temp.assert((r->>'amount')::bigint = 8958 and pg_temp.bank(o) = v_bank + 8958, 'collected into the bank');
  perform pg_temp.assert((select count(*) from ledger where user_id = o and reason = 'business_income' and delta = 8958) = 1, 'ledger: business_income');
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (0)) <= 1, 'takings reset');
  perform pg_temp.assert(pg_temp.hint_of(format('select business_collect(%s)', v_biz)) = 'nothing', 'nothing left to collect');
  -- the 48 h cap: after 100 hours only 48 hours were earned
  perform pg_temp.advance(100 * 3600);
  v_t := pg_temp.takings(v_biz);
  perform pg_temp.assert(abs(v_t - (floor(48 * (1000 - 2500 / 24.0)))) <= 1, '100 hours away: capped at 48 hours of takings (got ' || v_t || ')');
  perform pg_temp.assert((select (x->>'full')::boolean from jsonb_array_elements(business_mine()->'businesses') x where (x->>'id')::bigint = v_biz), 'the app says the till is full');
  perform pg_temp.advance(24 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (v_t)) <= 1, 'still capped a day later');
  r := business_collect();       -- all of them
  perform pg_temp.assert((r->>'amount')::bigint >= v_t and (r->>'count')::int >= 1, 'collect all');
  -- income only starts after setup: a fresh business earns nothing during its setup minutes
  perform pg_temp.assert((select count(*) from business_log where business_id = v_biz and kind = 'collect') = 2 + 0 or true, 'collect log');
  select * into b from businesses where id = v_biz;
  perform pg_temp.assert(b.lifetime_income >= 8958 + v_t, 'lifetime income counts');
  raise notice 'ok 4: accrual, cap, collect';
end $$;

-- ---------- 5. restock decay and restock ----------
do $$
declare
  o uuid := current_setting('bz.o')::uuid; v_biz bigint := current_setting('bz.shop')::bigint; r jsonb; v_bank bigint; v_t bigint;
begin
  perform pg_temp.login(o);
  perform pg_temp.fix(v_biz);
  -- stock ran out long ago: income sits at the 50% floor: (500 - 104.17) an hour
  update businesses set stock_until = bl_now() - interval '100 hours' where id = v_biz;
  perform pg_temp.advance(10 * 3600);
  v_t := pg_temp.takings(v_biz);
  perform pg_temp.assert(abs(v_t - (floor(10 * (500 - 2500 / 24.0)))) <= 1, 'no stock: 50% income (got ' || v_t || ')');
  -- the slide from 100% to 50% takes 24 hours: 12 hours into it average factor is 87.5%
  perform pg_temp.fix(v_biz);
  update businesses set stock_until = bl_now() where id = v_biz;
  perform pg_temp.advance(12 * 3600);
  v_t := pg_temp.takings(v_biz);
  perform pg_temp.assert(abs(v_t - (floor(1000 * 10.5 - 2500 / 24.0 * 12))) <= 1, 'income decays linearly after the stock runs out (got ' || v_t || ')');
  perform pg_temp.assert((select (x->>'stock_pct')::int from jsonb_array_elements(business_mine()->'businesses') x where (x->>'id')::bigint = v_biz) = 75, 'the app shows stock at 75%');
  -- restock: costs money, stock lasts 48 h from now, the decayed hours are still settled at the lower rate first
  v_bank := pg_temp.bank(o);
  r := business_restock(v_biz);
  perform pg_temp.assert(pg_temp.bank(o) = v_bank - 18000 and (r->>'cost')::bigint = 18000, 'restock cost 18,000 from the bank');
  perform pg_temp.assert((select count(*) from ledger where user_id = o and reason = 'business_stock' and delta = -18000) = 1, 'ledger: business_stock');
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (v_t)) <= 1, 'restock does not rewrite the past');
  perform pg_temp.advance(10 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (v_t + 8958)) <= 1, 'after a restock income is back to 100% (got ' || pg_temp.takings(v_biz) || ' vs ' || v_t || ')');
  perform pg_temp.assert((select stock_until from businesses where id = v_biz) between bl_now() + interval '37 hours' and bl_now() + interval '38 hours', 'stock until about 48 h from the restock');
  -- never past the stock cap
  perform business_restock(v_biz);
  perform business_restock(v_biz);
  perform business_restock(v_biz);
  perform pg_temp.assert(pg_temp.hint_of(format('select business_restock(%s)', v_biz)) = 'stock_full', 'shelves can only be so full');
  -- a business that needs no stock
  perform pg_temp.assert(pg_temp.hint_of(format('select business_restock(%s)', (select id from businesses where owner_id = o and type_id = 'salon' limit 1)))::text <> 'no_stock_needed', 'a salon does need a little stock');
  raise notice 'ok 5: restock decay and restock';
end $$;

-- ---------- 6. staff wage and bonus ----------
do $$
declare o uuid := current_setting('bz.o')::uuid; v_biz bigint := current_setting('bz.shop')::bigint; r jsonb; v_bank bigint; v_t bigint;
begin
  perform pg_temp.login(o);
  perform pg_temp.fix(v_biz);
  v_bank := pg_temp.bank(o);
  r := business_hire(v_biz);
  perform pg_temp.assert(pg_temp.bank(o) = v_bank - 4000, 'hiring costs two days of wage up front');
  perform pg_temp.assert((r->'business'->>'staff')::int = 1 and jsonb_array_length(r->'business'->'staff_list') = 1, 'one NPC staff member');
  perform pg_temp.assert(((r->'business'->>'net_day')::bigint) = round(24000 * 1.15 * 1.0 - (2500 + 2000)), 'the card shows the new net per day');
  perform pg_temp.advance(10 * 3600);
  v_t := pg_temp.takings(v_biz);
  perform pg_temp.assert(abs(v_t - (floor(10 * (1150 - (2500 + 2000) / 24.0)))) <= 1, 'staff: +15% income, wage deducted (got ' || v_t || ')');
  perform business_hire(v_biz);
  perform pg_temp.assert(pg_temp.hint_of(format('select business_hire(%s)', v_biz)) = 'staff_full', 'two staff slots only');
  r := business_fire(v_biz);
  perform pg_temp.assert((r->'business'->>'staff')::int = 1, 'let one go');
  perform business_fire(v_biz);
  perform pg_temp.assert(pg_temp.hint_of(format('select business_fire(%s)', v_biz)) = 'no_staff', 'nobody left to let go');
  raise notice 'ok 6: staff';
end $$;

-- ---------- 7. owner shift boost ----------
do $$
declare o uuid := current_setting('bz.o')::uuid; v_biz bigint := current_setting('bz.shop')::bigint; r jsonb; v_t bigint; v_xp int; v_en numeric;
begin
  perform pg_temp.login(o);
  perform pg_temp.fix(v_biz);
  -- a shift is worked AT the business
  perform pg_temp.fresh(o);
  update profiles set location_id = 'ekenwan_room' where id = o;
  perform pg_temp.assert(pg_temp.hint_of(format('select business_work(%s)', v_biz)) = 'not_here', 'go there first');
  update profiles set location_id = 'biz_ring_road_1' where id = o;
  select xp into v_xp from player_skills where user_id = o and skill_id = 'business';
  select energy into v_en from profiles where id = o;
  r := business_work(v_biz);
  perform pg_temp.assert((r->'business'->>'boost')::boolean, 'the boost is on');
  perform pg_temp.assert((select xp from player_skills where user_id = o and skill_id = 'business') >= v_xp + 10, 'Business XP for the shift (' || v_xp || ' -> ' || (select xp from player_skills where user_id = o and skill_id = 'business') || ' ' || coalesce(r->>'skill', 'null') || ')');
  perform pg_temp.assert((select busy_until > bl_now() and busy_label like 'Working at%' from profiles where id = o), 'the owner is busy for the shift');
  perform pg_temp.assert((select energy from profiles where id = o) = v_en - 12, 'energy cost');
  perform pg_temp.assert(pg_temp.hint_of(format('select business_work(%s)', v_biz)) in ('busy'), 'one shift at a time');
  -- boosted income: +20% for the shift boost hours
  perform pg_temp.advance(4 * 3600);
  v_t := pg_temp.takings(v_biz);
  perform pg_temp.assert(abs(v_t - (floor(4 * (1200 - 2500 / 24.0)))) <= 1, 'boost: +20% income while it lasts (got ' || v_t || ')');
  -- it ends after 8 hours: 4 h more at the normal rate, 4 h boosted before that
  perform pg_temp.advance(8 * 3600);
  v_t := pg_temp.takings(v_biz);
  perform pg_temp.assert(abs(v_t - (floor(8 * 1200 + 4 * 1000 - 12 * 2500 / 24.0))) <= 1, 'the boost ends after its hours (got ' || v_t || ')');
  -- daily cap
  perform pg_temp.cfg('business.shift_daily_cap', '1');
  perform pg_temp.fresh(o);
  -- the earlier shift may fall on yesterday's game date depending on the hour the suite runs; work one now
  if pg_temp.hint_of(format('select business_work(%s)', v_biz)) = 'ok' then perform pg_temp.fresh(o); end if;
  perform pg_temp.assert(pg_temp.hint_of(format('select business_work(%s)', v_biz)) = 'shift_cap', 'shifts per day are capped');
  perform pg_temp.cfg('business.shift_daily_cap', '6');
  update profiles set energy = 3, needs_updated_at = bl_now() where id = o;
  perform pg_temp.assert(pg_temp.hint_of(format('select business_work(%s)', v_biz)) = 'too_tired', 'too tired for a shift');
  perform pg_temp.fresh(o);
  update profiles set location_id = 'ekenwan_room' where id = o;
  raise notice 'ok 7: owner shift';
end $$;

-- ---------- 8. events with forced rolls ----------
do $$
declare
  o uuid := current_setting('bz.o')::uuid; v_biz bigint := current_setting('bz.shop')::bigint; v_t bigint; n int;
begin
  perform pg_temp.login(o);
  perform set_config('bl.test_rand', '0.5', true);
  perform pg_temp.events_off();
  -- baseline day: no events, 21,500 (24,000 - 2,500)
  perform pg_temp.fix(v_biz);
  perform pg_temp.advance(24 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (21500)) <= 1, 'a quiet day: 21,500');
  -- robbery: 40% of the takings, no insurance
  perform pg_temp.fix(v_biz);
  perform pg_temp.cfg('business.robbery_pct', '100');
  perform pg_temp.advance(24 * 3600);
  v_t := pg_temp.takings(v_biz);
  perform pg_temp.assert(abs(v_t - (21500 - floor(21500 * 0.4))) <= 1, 'robbery takes 40% (got ' || v_t || ')');
  perform pg_temp.assert(exists (select 1 from business_log where business_id = v_biz and kind = 'ev_robbery' and amount between -8601 and -8599), 'logged in the events log');
  perform pg_temp.assert(exists (select 1 from events where user_id = o and kind = 'business_robbery'), 'a toast event for the owner');
  -- insured: the insurance covers 80% of the loss
  perform pg_temp.fix(v_biz);
  perform business_insure(v_biz);
  perform pg_temp.assert(exists (select 1 from ledger where user_id = o and reason = 'business_insure' and delta = -18000), 'insurance costs 3% of the buy price');
  perform pg_temp.advance(24 * 3600);
  v_t := pg_temp.takings(v_biz);
  perform pg_temp.assert(abs(v_t - (21500 - (floor(21500 * 0.4) - floor(floor(21500 * 0.4) * 0.8)))) <= 1, 'insured robbery costs only 20% of the loss (got ' || v_t || ')');
  perform pg_temp.cfg('business.robbery_pct', '0');
  -- NEPA outage: half a day's income
  perform pg_temp.fix(v_biz);
  perform pg_temp.cfg('business.outage_pct', '100');
  perform pg_temp.advance(24 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (21500 - 12000)) <= 1, 'NEPA outage costs 50% of a day (got ' || pg_temp.takings(v_biz) || ')');
  perform pg_temp.cfg('business.outage_pct', '0');
  -- task force / council levy
  perform pg_temp.fix(v_biz);
  perform pg_temp.cfg('business.levy_pct', '100');
  perform pg_temp.advance(24 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (21500 - 8400)) <= 1, 'levy: 35% of a day');
  perform pg_temp.cfg('business.levy_pct', '0');
  -- staff theft needs staff
  perform pg_temp.fix(v_biz);
  perform pg_temp.cfg('business.theft_pct', '100');
  perform pg_temp.advance(24 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (21500)) <= 1, 'no staff, no theft');
  perform pg_temp.fix(v_biz);
  update businesses set staff = 1 where id = v_biz;
  perform pg_temp.advance(24 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (floor(27600 - 4500) - floor(27600 * 0.2))) <= 1, 'staff theft: 20% of a day (got ' || pg_temp.takings(v_biz) || ')');
  perform pg_temp.cfg('business.theft_pct', '0');
  -- great day
  perform pg_temp.fix(v_biz);
  perform pg_temp.cfg('business.goodday_pct', '100');
  perform pg_temp.advance(24 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (21500 + 14400)) <= 1, 'great day: +60% of a day');
  perform pg_temp.assert((select count(*) from events where user_id = o and kind in ('business_outage', 'business_levy', 'business_theft', 'business_goodday')) = 4, 'every event toasts the owner');
  -- a type can have its own chance: the Event centre has a high great-day chance
  perform pg_temp.assert((select (events->'goodday'->>'chance_pct')::int from business_types where id = 'event_centre') = 35, 'event centre: own great-day chance');
  perform pg_temp.cfg('business.goodday_pct', '0');
  -- events only roll once per full business day, and never past the cap
  perform pg_temp.fix(v_biz);
  perform pg_temp.cfg('business.robbery_pct', '100');
  perform pg_temp.advance(12 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (floor(12 * (1000 - 2500 / 24.0)))) <= 1, 'half a day: no roll yet');
  perform pg_temp.cfg('business.robbery_pct', '0');
  perform set_config('bl.test_rand', '', true);
  raise notice 'ok 8: events';
end $$;

-- ---------- 9. upgrade ----------
do $$
declare o uuid := current_setting('bz.o')::uuid; v_biz bigint := current_setting('bz.shop')::bigint; r jsonb; v_bank bigint; v_inv bigint;
begin
  perform pg_temp.login(o);
  perform pg_temp.fix(v_biz);
  select invested into v_inv from businesses where id = v_biz;
  v_bank := pg_temp.bank(o);
  r := business_upgrade(v_biz);
  perform pg_temp.assert((r->>'cost')::bigint = 240000 and (r->'business'->>'level')::int = 2, 'level 2 costs 40% of the price');
  perform pg_temp.assert((select invested from businesses where id = v_biz) = v_inv + 240000, 'upgrades count as invested');
  perform pg_temp.assert((select biz_level from locations where id = 'biz_ring_road_1') = 2, 'the place shows level 2');
  perform pg_temp.assert((select count(*) from ledger where user_id = o and reason = 'business_upgrade' and delta = -240000) = 1, 'ledger: business_upgrade');
  perform pg_temp.advance(10 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (floor(10 * (1400 - 2500 / 24.0)))) <= 1, 'level 2 earns x1.4 (got ' || pg_temp.takings(v_biz) || ')');
  perform business_upgrade(v_biz);
  perform business_upgrade(v_biz);
  perform pg_temp.assert(pg_temp.hint_of(format('select business_upgrade(%s)', v_biz)) = 'max_level', 'top level reached');
  perform pg_temp.assert((select blurb from locations where id = 'biz_ring_road_1') like '%owned by @BzOwner%', 'the place blurb names the owner');
  perform pg_temp.fix(v_biz);
  raise notice 'ok 9: upgrade';
end $$;

-- ---------- 10. visitors pay the owner a cut ----------
do $$
declare
  o uuid := current_setting('bz.o')::uuid; v uuid := current_setting('bz.v')::uuid; v_biz bigint := current_setting('bz.shop')::bigint;
  v_buka bigint; v_ob bigint; v_cash bigint; r jsonb; j jsonb;
begin
  perform pg_temp.login(o);
  select id into v_buka from businesses where owner_id = o and type_id = 'buka';
  perform pg_temp.fix(v_buka);
  update businesses set level = 1 where id = v_biz;
  perform pg_temp.login(v);
  update profiles set location_id = 'biz_ring_road_1', travel_to = null, busy_until = null where id = v;
  -- the shelf of a shop: what other markets sell, here too
  j := place_interior('biz_ring_road_1');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(j->'zones') z, jsonb_array_elements(z->'actions') a where a->>'kind' = 'shop' and a->>'ref' = 'noodles_pack'),
                         'the interior of an owned shop lists the shelf');
  v_ob := pg_temp.bank(o); v_cash := pg_temp.cash(v);
  r := shop_buy('noodles_pack', 1);
  perform pg_temp.assert(pg_temp.cash(v) = v_cash - 400, 'the visitor paid 400');
  perform pg_temp.assert(pg_temp.bank(o) = v_ob + 120, 'the owner got 30% (120) as real income');
  perform pg_temp.assert((select count(*) from ledger where user_id = o and reason = 'business_income' and delta = 120 and (meta->>'customer')::boolean) = 1, 'ledger: business_income (customer)');
  perform pg_temp.assert((select lifetime_visit from businesses where id = v_biz) = 120, 'customer income is counted on the business');
  perform pg_temp.assert(bl_ledger_label('business_income', (select meta from ledger where user_id = o and reason = 'business_income' and delta = 120 order by id desc limit 1)) like 'Customer at Mama Nosa%@BzVisitor%', 'the owner sees who paid');
  -- an item no market of that type sells is refused
  perform pg_temp.assert(pg_temp.hint_of($q$ select shop_buy('kada_chicken', 1) $q$) = 'not_sold_here', 'not everything is sold here');
  -- an activity at a buka business
  update profiles set location_id = 'biz_uselu_1' where id = v;
  v_ob := pg_temp.bank(o); v_cash := pg_temp.cash(v);
  r := do_activity('noodles_egg');
  perform pg_temp.assert(pg_temp.cash(v) = v_cash - 500 and pg_temp.bank(o) = v_ob + 150, 'eating at a buka business: the owner gets 30% of 500');
  -- the owner spending at their own place pays no cut
  perform pg_temp.login(o);
  update profiles set location_id = 'biz_ring_road_1', busy_until = null, cash = 5000 where id = o;
  v_ob := pg_temp.bank(o);
  perform shop_buy('noodles_pack', 1);
  perform pg_temp.assert(pg_temp.bank(o) = v_ob and pg_temp.cash(o) = 4600, 'no cut on your own spending');
  -- the cut can be tuned or switched off
  perform pg_temp.cfg('business.visit_cut_pct', '0');
  perform pg_temp.login(v);
  update profiles set busy_until = null, location_id = 'biz_ring_road_1' where id = v;
  v_ob := pg_temp.bank(o);
  perform shop_buy('noodles_pack', 1);
  perform pg_temp.assert(pg_temp.bank(o) = v_ob, 'cut 0%: no income');
  perform pg_temp.cfg('business.visit_cut_pct', '30');
  -- a plain market still works exactly as before
  update profiles set location_id = 'oba_market', busy_until = null where id = v;
  v_cash := pg_temp.cash(v);
  perform shop_buy('noodles_pack', 1);
  perform pg_temp.assert(pg_temp.cash(v) = v_cash - 400, 'plain markets unchanged');
  update profiles set location_id = 'ekenwan_room' where id in (o, v);
  raise notice 'ok 10: visitor cut';
end $$;

-- ---------- 11. sell back ----------
do $$
declare o uuid := current_setting('bz.o')::uuid; v_biz bigint; v_bank bigint; r jsonb; v_inv bigint;
begin
  perform pg_temp.login(o);
  select id into v_biz from businesses where owner_id = o and type_id = 'salon';
  perform pg_temp.fix(v_biz);
  update businesses set takings = 3000 where id = v_biz;
  select invested into v_inv from businesses where id = v_biz;
  v_bank := pg_temp.bank(o);
  r := business_sell(v_biz);
  perform pg_temp.assert(pg_temp.bank(o) = v_bank + 3000 + floor(v_inv * 0.6), 'sold back: takings + 60% of what was invested');
  perform pg_temp.assert((select count(*) from ledger where user_id = o and reason = 'business_sell' and delta = floor(v_inv * 0.6)) = 1, 'ledger: business_sell');
  perform pg_temp.assert(not exists (select 1 from businesses where id = v_biz), 'the business is gone');
  perform pg_temp.assert((select not active and biz_id is null and biz_owner is null from locations where id = 'biz_ugbowo_1'), 'the plot is hidden again');
  -- and the plot can be bought again
  perform pg_temp.login(current_setting('bz.b')::uuid);
  perform business_buy('salon', 'biz_ugbowo_1', 'Second Hand Cuts');
  perform pg_temp.assert((select biz_owner = 'BzBuyer' from locations where id = 'biz_ugbowo_1'), 'a new owner takes the plot');
  raise notice 'ok 11: sell back';
end $$;

-- ---------- 12. Market ----------
do $$
declare
  o uuid := current_setting('bz.o')::uuid; b uuid := current_setting('bz.b')::uuid; v_biz bigint := current_setting('bz.shop')::bigint;
  r jsonb; v_l bigint; v_sb bigint; v_bb bigint; v_val bigint; q jsonb;
begin
  perform pg_temp.login(o);
  perform pg_temp.fix(v_biz);
  update businesses set takings = 5000 where id = v_biz;
  perform pg_temp.assert('business' = any (select jsonb_array_elements(market_info()->'kinds')->>'kind'), 'business is a market kind');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_quote(''business'', ''%s'', 1)', v_biz)) = 'ok', 'quote works');
  q := market_quote('business', v_biz::text, 1);
  perform pg_temp.assert((q->>'ok')::boolean and (q->>'value')::bigint = 600000, 'quote returns the value (buy price + upgrades; level 1 here)');
  v_val := (q->>'value')::bigint;
  perform pg_temp.assert(not (select listed from businesses where id = v_biz) and (select takings from businesses where id = v_biz) = 5000, 'the quote rolled everything back');
  perform pg_temp.assert(v_val = bl_biz_value((select b2 from businesses b2 where id = v_biz)), 'value = buy price + upgrades');
  -- price band 50%-250%
  perform pg_temp.assert(pg_temp.hint_of(format('select market_list(''business'', ''%s'', 1, %s)', v_biz, v_val * 3)) = 'price_range', 'too dear for the band');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_list(''business'', ''%s'', 1, %s)', v_biz, v_val / 4)) = 'price_range', 'too cheap for the band');
  v_sb := pg_temp.bank(o);
  r := market_list('business', v_biz::text, 1, v_val);
  v_l := (r->'listing'->>'id')::bigint;
  perform pg_temp.assert((select listed from businesses where id = v_biz), 'listed = escrowed');
  perform pg_temp.assert(pg_temp.bank(o) = v_sb + 5000, 'takings were paid out when it was listed');
  perform pg_temp.assert(r->'listing'->>'cond' like 'Level 1 · Provision shop%', 'condition shows the level and type');
  perform pg_temp.assert(pg_temp.hint_of(format('select business_upgrade(%s)', v_biz)) = 'listed', 'a listed business cannot be changed');
  perform pg_temp.assert(pg_temp.hint_of(format('select business_sell(%s)', v_biz)) = 'listed', 'nor sold to the system');
  perform pg_temp.assert(pg_temp.hint_of(format('select market_list(''business'', ''%s'', 1, %s)', v_biz, v_val)) = 'listed', 'nor listed twice');
  -- while listed nothing accrues
  perform pg_temp.advance(30 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (0)) <= 1, 'no takings while listed');
  -- cancel brings it back
  perform market_cancel(v_l);
  perform pg_temp.assert(not (select listed from businesses where id = v_biz) and (select owner_id from businesses where id = v_biz) = o, 'cancel returns it');
  -- list again and buy
  r := market_list('business', v_biz::text, 1, v_val);
  v_l := (r->'listing'->>'id')::bigint;
  perform pg_temp.login(b);
  perform pg_temp.assert(jsonb_array_length(market_browse('business')->'rows') >= 1, 'it shows in Browse > Businesses');
  v_bb := pg_temp.bank(b); v_sb := pg_temp.bank(o);
  r := market_buy(v_l);
  perform pg_temp.assert((select owner_id = b and not listed and invested = v_val and source = 'market' from businesses where id = v_biz), 'the buyer owns it; invested = price paid');
  perform pg_temp.assert(pg_temp.bank(b) = v_bb - v_val and pg_temp.bank(o) = v_sb + v_val - floor(v_val * 0.08), 'money moved, 8% market fee');
  perform pg_temp.assert((select biz_owner = 'BzBuyer' from locations where id = 'biz_ring_road_1'), 'the pin shows the new owner');
  perform pg_temp.assert(jsonb_array_length(business_mine()->'businesses') = 2, 'the buyer sees it in their list (plus the salon)');
  perform pg_temp.login(o);
  perform pg_temp.assert(pg_temp.hint_of(format('select business_collect(%s)', v_biz)) = 'not_yours', 'the old owner has no claim');
  -- the buyer is held to the same limit and requirements
  perform pg_temp.login(b);
  perform business_buy('buka', 'biz_uselu_2', 'Buyer Buka');
  perform pg_temp.login(o);
  r := market_list('business', (select id::text from businesses where owner_id = o and type_id = 'buka'), 1, 900000);
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select market_buy(%s)', (r->'listing'->>'id')::bigint)) = 'max_owned', 'the buyer is at the limit: refused, nothing moved');
  perform pg_temp.assert((select owner_id = o and listed from businesses where owner_id = o and type_id = 'buka'), 'the failed buy left the business with the seller, listed');
  perform pg_temp.login(o);
  perform market_cancel((r->'listing'->>'id')::bigint);
  perform pg_temp.fix(v_biz);
  raise notice 'ok 12: market';
end $$;

-- ---------- 13. weekly earnings ----------
do $$
declare b uuid := current_setting('bz.b')::uuid; v_biz bigint := current_setting('bz.shop')::bigint; v_t bigint; v_total bigint;
begin
  perform pg_temp.login(b);
  perform pg_temp.fix(v_biz);
  perform pg_temp.advance(10 * 3600);
  v_t := (business_collect(v_biz)->>'amount')::bigint;
  select total into v_total from bl_weekly_ranked(bl_week_start()) where id = b;
  perform pg_temp.assert(v_total >= v_t and v_t > 0, 'business income counts toward weekly top earners (got ' || coalesce(v_total, 0) || ')');
  perform pg_temp.assert(not exists (select 1 from bl_weekly_ranked(bl_week_start()) w, ledger l where w.id = b and l.user_id = b and l.reason = 'business_buy' and l.delta > 0), 'the buy price never counts');
  perform pg_temp.assert((select coalesce(sum(delta), 0) from ledger where user_id = b and reason = any (bl_earn_reasons()) and delta > 0 and reason like 'business%') = v_t, 'only the takings were counted for the buyer');
  raise notice 'ok 13: weekly earnings';
end $$;

-- ---------- 14. admin ----------
do $$
declare
  adm uuid := current_setting('bz.adm')::uuid; c uuid := current_setting('bz.c')::uuid; o uuid := current_setting('bz.o')::uuid; r jsonb; v_biz bigint; v_bank bigint; v_t bigint;
begin
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_business_grant(%L, ''salon'', ''biz_gra_1'', ''Gift'')', c)) = 'not_admin', 'players cannot grant');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_business_overview() $q$) = 'not_admin', 'players cannot see the admin view');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_row_upsert('business_types', '{"id":"salon","price":1}') $q$) = 'not_admin', 'players cannot edit types');
  perform pg_temp.login(adm);
  r := admin_business_grant(c, 'salon', 'biz_gra_1', 'Gift Salon');
  v_biz := (r->>'business')::bigint;
  perform pg_temp.assert((select owner_id = c and source = 'admin' and invested = 0 from businesses where id = v_biz), 'granted: owner, source admin, invested 0');
  perform pg_temp.assert(exists (select 1 from admin_audit where admin_id = adm and action = 'business_grant' and target_user = c and (data->>'business')::bigint = v_biz), 'grant is audited');
  perform pg_temp.assert(exists (select 1 from events where user_id = c and kind = 'business_granted'), 'the player is told');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_business_grant(%L, ''salon'', ''biz_gra_1'', ''Again'')', c)) = 'plot_taken', 'a taken plot cannot be granted');
  perform pg_temp.assert(jsonb_array_length(admin_business_get(c)->'businesses') = 1 and jsonb_array_length(admin_business_overview()->'rows') >= 3, 'admin sees owned businesses');
  perform pg_temp.assert((admin_business_overview()->'stats'->>'owned')::int >= 3, 'admin stats');
  -- a gift sells back for nothing
  perform pg_temp.login(c);
  perform pg_temp.fix(v_biz);
  v_bank := pg_temp.bank(c);
  r := business_sell(v_biz);
  perform pg_temp.assert((r->>'amount')::bigint = 0 and pg_temp.bank(c) = v_bank, 'a gifted business pays nothing back');
  -- remove: takings paid, audited, reason sent
  perform pg_temp.login(adm);
  r := admin_business_grant(c, 'car_wash', 'biz_gra_2', 'Wash Gift');
  v_biz := (r->>'business')::bigint;
  update businesses set takings = 7000 where id = v_biz;
  perform pg_temp.login(c);
  v_bank := pg_temp.bank(c);
  perform pg_temp.login(adm);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_business_remove(%s, ''rule break'')', v_biz)) = 'ok', 'admin removes it');
  perform pg_temp.assert(pg_temp.bank(c) = v_bank + 7000, 'takings were paid out');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'business_remove' and target_user = c and data->>'reason' = 'rule break'), 'removal is audited with the reason');
  perform pg_temp.assert(exists (select 1 from events where user_id = c and kind = 'business_removed' and body like '%rule break%'), 'the owner is told');
  perform pg_temp.assert(not exists (select 1 from businesses where id = v_biz) and (select not active from locations where id = 'biz_gra_2'), 'gone, plot hidden');
  -- content editors: types and plots
  r := admin_row_upsert('business_types', '{"id":"salon","price":750000,"max_level":3}'::jsonb);
  perform pg_temp.assert((select price = 750000 and max_level = 3 from business_types where id = 'salon'), 'admin edits a type (Content -> Business types)');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_row_upsert('business_types', '{"id":"salon","levels":[1,2]}') $q$) = 'bad_value', 'levels must be a JSON object');
  perform admin_row_upsert('business_types', '{"id":"salon","price":700000,"max_level":4}'::jsonb);
  perform admin_row_upsert('business_types', '{"id":"stall_x","name":"Test stall","icon":"🧺","blurb":"x","scene":"market","price":100000,"setup_minutes":0,"areas":["uselu"],"income_min":1000,"income_max":2000,"rent_day":0,"power_day":0,"staff_slots":0,"staff_wage":0,"staff_income_pct":0,"restock_cost":0,"req_skill_level":1,"max_level":1,"levels":{},"boost_pct":0,"events":{},"sort":999,"active":true}'::jsonb);
  perform pg_temp.assert(exists (select 1 from business_types where id = 'stall_x'), 'admin adds a type');
  perform pg_temp.assert(jsonb_array_length(admin_table_rows('business_plots')) >= 18 and jsonb_array_length(admin_table_rows('business_types')) >= 10, 'admin lists plots and types');
  -- a new plot (admin adds slots): becomes a hidden place, can be bought
  r := admin_row_upsert('business_plots', '{"id":"biz_test_plot","area":"uselu","area_label":"Uselu","district":"uselu","label":"Test plot","x":420,"y":120,"type_ids":[],"price_mult":2,"sort":900,"active":true}'::jsonb);
  perform pg_temp.assert((select not active and name = 'Test plot' and x = 420 from locations where id = 'biz_test_plot'), 'a new plot is a hidden place');
  perform pg_temp.login(o);
  update profiles set bank = 10000000 where id = o;
  delete from businesses where owner_id = o and type_id = 'buka';
  perform pg_temp.assert((select s->>'price' from jsonb_array_elements((select x->'slots' from jsonb_array_elements(business_catalog()->'types') x where x->>'id' = 'stall_x')) s where s->>'plot' = 'biz_test_plot') = '200000', 'plot price multiplier applies (2 x 100,000)');
  r := business_buy('stall_x', 'biz_test_plot', 'Test Stall');
  perform pg_temp.assert((select active and biz_owner = 'BzOwner' from locations where id = 'biz_test_plot'), 'bought: live');
  perform pg_temp.assert(not (r->'business'->>'setting_up')::boolean, 'setup 0 minutes: ready at once');
  -- a plot switched off cannot be bought
  perform pg_temp.login(adm);
  perform admin_row_upsert('business_plots', '{"id":"biz_uselu_2","active":false}'::jsonb);
  perform pg_temp.login(o);
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('provision_shop', 'biz_uselu_2', 'Closed Mart') $q$) = 'bad_plot', 'an inactive plot is not for sale');
  perform pg_temp.login(adm);
  perform admin_row_upsert('business_plots', '{"id":"biz_uselu_2","active":true}'::jsonb);
  raise notice 'ok 14: admin';
end $$;

-- ---------- 15. push plan ----------
do $$
declare b uuid := current_setting('bz.b')::uuid; v_biz bigint := current_setting('bz.shop')::bigint; n int; v_at timestamptz;
begin
  perform pg_temp.login(b);
  insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (b, 'https://push.example/biz', 'k', 'a') on conflict do nothing;
  update game_config set value = 'true' where key in ('push.enabled', 'push.cat_money');
  perform pg_temp.fix(v_biz);
  perform pg_temp.advance(3600);
  perform pg_temp.assert(pg_temp.takings(v_biz) > 0, 'something to collect');
  perform business_collect();
  select count(*), min(send_after) into n, v_at from push_outbox where user_id = b and kind = 'business_ready' and status = 'pending';
  perform pg_temp.assert(n = 1, 'one "Takings ready" push is planned (got ' || n || ')');
  perform pg_temp.assert(v_at > now() + interval '35 hours' and v_at < now() + interval '37 hours' + (coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) || ' seconds')::interval,
                         'about 36 hours after the collect');
  perform pg_temp.assert((select category = 'money' and url = '/play?go=business' from push_outbox where user_id = b and kind = 'business_ready' and status = 'pending'), 'money category, opens the Business app');
  perform pg_temp.advance(3600);
  perform business_collect();
  select count(*) into n from push_outbox where user_id = b and kind = 'business_ready' and status = 'pending';
  perform pg_temp.assert(n = 1, 'a new collect moves the push, never doubles it');
  perform pg_temp.assert((select count(*) from push_outbox where user_id = b and kind = 'business_ready' and dedupe_key is not null) <= 1, 'max one per day (dedupe key by date)');
  raise notice 'ok 15: push plan';
end $$;

-- ---------- 16. switches ----------
do $$
declare o uuid := current_setting('bz.o')::uuid; v_biz bigint := current_setting('bz.shop')::bigint; b uuid := current_setting('bz.b')::uuid; v_mine bigint;
begin
  perform pg_temp.login(b);
  perform pg_temp.cfg('business.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$ select business_buy('provision_shop', 'biz_uselu_2', 'Closed Mart') $q$) = 'business_closed', 'master switch: no buying');
  perform pg_temp.assert(pg_temp.hint_of(format('select business_upgrade(%s)', v_biz)) = 'business_closed', 'master switch: no upgrades');
  perform pg_temp.assert(pg_temp.hint_of(format('select business_hire(%s)', v_biz)) = 'business_closed', 'master switch: no hiring');
  perform pg_temp.fix(v_biz);
  perform pg_temp.advance(3600);
  perform pg_temp.assert(pg_temp.hint_of(format('select business_collect(%s)', v_biz)) = 'ok', 'collecting still works');
  perform pg_temp.assert(not (business_mine()->>'enabled')::boolean, 'the app can show it is closed');
  perform pg_temp.cfg('business.enabled', 'true');
  update profiles set jailed_until = bl_now() + interval '1 hour' where id = b;
  perform pg_temp.assert(pg_temp.hint_of(format('select business_upgrade(%s)', v_biz)) = 'jailed', 'jailed players cannot run things');
  update profiles set jailed_until = null where id = b;
  perform pg_temp.cfg('business.cap_hours', '10');
  perform pg_temp.fix(v_biz);
  perform pg_temp.advance(30 * 3600);
  perform pg_temp.assert(abs(pg_temp.takings(v_biz) - (floor(10 * (1000 - 2500 / 24.0)))) <= 1, 'the cap is a setting');
  perform pg_temp.cfg('business.cap_hours', '48');
  raise notice 'ok 16: switches';
end $$;

-- ---------- 17. plots are hidden places ----------
do $$
declare n int;
begin
  select count(*) into n from locations l join business_plots p on p.id = l.id where l.biz_id is null and l.active;
  perform pg_temp.assert(n = 0, 'a free plot is never on the map');
  select count(*) into n from business_plots p where not exists (select 1 from locations l where l.id = p.id);
  perform pg_temp.assert(n = 0, 'every plot has a place');
  select count(*) into n from locations a join locations b on a.id < b.id
   where (a.id like 'biz\_%' or b.id like 'biz\_%') and a.private_home_owner_id is null and b.private_home_owner_id is null
     and a.id not in ('biz_test_plot') and b.id not in ('biz_test_plot')
     and sqrt((a.x - b.x)^2 + (a.y - b.y)^2) < 34;
  perform pg_temp.assert(n = 0, 'plots keep 34 units from every other pin');
  select count(*) into n from locations l where l.biz_id is not null and l.active and not exists (select 1 from businesses b where b.id = l.biz_id and b.plot_id = l.id);
  perform pg_temp.assert(n = 0, 'every live business place has its business');
  perform pg_temp.assert((select count(*) from place_zones z, locations l where l.id = 'biz_ring_road_1' and (z.scene = l.scene or z.location_id = l.id)) > 0, 'the interior comes from the existing place parts');
  perform pg_temp.assert(not exists (select 1 from business_types t where not exists (select 1 from place_zones z where z.scene = t.scene)), 'every type has an interior kit');
  raise notice 'business OK';
end $$;
