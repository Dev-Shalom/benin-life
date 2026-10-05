-- Shops tests (V1-4): item seeds + shop locations, shop_list / shop_buy (location rule, cash, qty),
-- inventory counts, item_use effects, boost items (soap + bath), item_sell at markets, ChopNow
-- delivery markup (config-driven), laptop -> Tech requirement, rent switched on (no back-charge,
-- weekly charge with time travel, shortfall -> owed, pay_rent, sleep penalty while owing),
-- get_my_state inventory block. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/shops_test.sql
-- Rolled back at the end. Time with bl.test_offset_seconds.

create or replace function pg_temp.s_advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;

create or replace function pg_temp.s_hint(p_sql text, p_hint text) returns void
language plpgsql as $$
declare v_h text;
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
    get stacked diagnostics v_h = pg_exception_hint;
    if v_h is distinct from p_hint then
      raise exception 'TEST FAILED: [%] expected hint "%", got "%" (%)', p_sql, p_hint, v_h, sqlerrm;
    end if;
    return;
  end;
  raise exception 'TEST FAILED: [%] expected hint "%" but it succeeded', p_sql, p_hint;
end $$;

create temp table t_shops_u (name text primary key, id uuid not null) on commit drop;
create or replace function pg_temp.su(p_name text) returns uuid
language sql as $$ select id from t_shops_u where name = p_name $$;

-- new logged-in LAPO Sim living in p_home
create or replace function pg_temp.s_make(p_name text, p_home text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@shops.bl');
begin
  insert into t_shops_u values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home(p_home);
  return v;
end $$;

-- put the Sim somewhere, free, with set needs and money (no decay pending)
create or replace function pg_temp.s_at(p_uid uuid, p_loc text, p_cash bigint, p_bank bigint) returns void
language sql as $$
  update profiles set location_id = p_loc, travel_to = null, busy_until = null, busy_label = null,
                      cash = p_cash, bank = p_bank,
                      hunger = 50, energy = 50, hygiene = 10, fun = 50, social = 50, stress = 20, health = 90,
                      bladder = 80, needs_updated_at = bl_now()
   where id = p_uid;
$$;

create or replace function pg_temp.qty(p_uid uuid, p_item text) returns int
language sql as $$ select coalesce((select qty from inventory where user_id = p_uid and item_id = p_item), 0) $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  -- pin the numbers this file asserts (the live DB may hold admin-tuned values; rolled back anyway)
  update game_config set value = '10' where key = 'shop.max_qty_per_buy';
  update game_config set value = '40' where key = 'shop.delivery_markup_pct';
  update game_config set value = '200' where key = 'shop.delivery_min_fee';
  update game_config set value = '"market"' where key = 'shop.sell_scenes';
  update game_config set value = '60' where key = 'rent.owed_sleep_energy_pct';
  update game_config set value = '"sleep,nap"' where key = 'rent.owed_sleep_activities';
  update game_config set value = '4' where key = 'rent.max_catchup_weeks';
  update game_config set value = 'false' where key = 'rent.enabled';   -- group 6 switches it on
  update items set price = 300, sellable = false where id = 'puff_puff';
  update items set price = 300, sellable = true, resale_pct = 30, effects = '{"boost": {"bathe": {"hygiene": 20, "fun": 2}}}' where id = 'soap';
  update items set price = 2000, effects = '{"hunger": 50, "fun": 8}' where id = 'jollof_pack';
  update items set price = 45000 where id = 'laptop';
  update activities set effects = '{"energy": 85, "health": 5, "stress": -20}' where id = 'sleep';
  update activities set effects = '{"stress": -3, "hygiene": 60}' where id = 'bathe';
end $$;

-- ---------- 0. seeds, places, config, privileges ----------
do $$
declare r record; k text;
begin
  perform pg_temp.assert((select count(*) from items where category in ('food','drink')) >= 12, 'at least 12 food/drink items');
  perform pg_temp.assert(exists (select 1 from items where category = 'hygiene'), 'hygiene items');
  perform pg_temp.assert((select count(*) from items where id = 'laptop') = 1, 'one laptop row (no duplicate)');
  perform pg_temp.assert((select 'bronze_tech_hub' = any (sold_at) from items where id = 'laptop'), 'laptop sold at the Tech Hub');
  perform pg_temp.assert((select price from items where id = 'laptop') between 30000 and 70000, 'laptop affordable for a starter');
  perform pg_temp.assert((select name from items where id = 'tokunbo_car') = 'Tokunbo Saloon', 'car keeps its R6 name');
  perform pg_temp.assert(not (select sellable from items where id = 'tokunbo_car'), 'free starter car cannot be sold');
  -- every selling place exists and has the Shop tab; every Shop tab sells something
  for r in select it.id, s from items it, unnest(it.sold_at) s loop
    perform pg_temp.assert(exists (select 1 from locations l where l.id = r.s and 'shop' = any (l.actions)),
                           r.id || ' sold at ' || r.s || ' which has no shop tab');
  end loop;
  for r in select id from locations where 'shop' = any (actions) loop
    perform pg_temp.assert(exists (select 1 from items where r.id = any (sold_at)), 'shop tab with nothing to sell: ' || r.id);
  end loop;
  perform pg_temp.assert((select count(*) from items where (cardinality(sold_at) > 0 or id in ('laptop','tokunbo_car')) and coalesce(icon, '') = '') = 0, 'every shop item has an icon');
  foreach k in array array['shop.max_qty_per_buy','shop.delivery_markup_pct','shop.delivery_min_fee','shop.sell_scenes',
                           'rent.owed_sleep_energy_pct','rent.owed_sleep_activities'] loop
    perform pg_temp.assert(exists (select 1 from game_config where key = k and label <> '' and category <> '' and description <> ''), 'config ' || k);
  end loop;
  foreach k in array array['bl_give_item(uuid,text,integer)','bl_inventory_info(uuid)','bl_delivery_price(bigint)','bl_item(text)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', 'public.' || k, 'execute'), 'helper revoked: ' || k);
  end loop;
  foreach k in array array['shop_list(text)','shop_buy(text,integer)','item_use(text)','item_sell(text,integer)',
                           'food_menu()','food_order(text,integer)','pay_rent()'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || k, 'execute'), 'rpc granted: ' || k);
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || k, 'execute'), 'rpc not for anon: ' || k);
  end loop;
  raise notice 'ok 0: seeds, places, config, privileges';
end $$;

-- ---------- 1. shop_list + shop_buy ----------
do $$
declare v uuid := pg_temp.s_make('Shop_A', 'ekenwan_face_me'); s jsonb; it jsonb; r jsonb;
begin
  perform pg_temp.s_at(v, 'oba_market', 8000, 0);
  s := shop_list('oba_market');
  perform pg_temp.assert((s->>'here')::boolean and (s->>'sell_here')::boolean, 'here + sell_here at a market');
  select x into it from jsonb_array_elements(s->'items') x where x->>'id' = 'puff_puff';
  perform pg_temp.assert(it is not null and (it->>'price')::int = 300 and (it->>'affordable')::boolean
                         and (it->>'owned')::int = 0 and it->>'kind' = 'use', 'puff_puff listed: ' || coalesce(it::text, 'null'));
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(s->'items') x where x->>'id' = 'laptop'), 'no laptop at the market');
  perform pg_temp.assert(not (shop_list('bronze_tech_hub')->>'here')::boolean, 'not here at the Tech Hub');
  perform pg_temp.assert(shop_list()->'location'->>'id' = 'oba_market', 'defaults to where you are');

  r := shop_buy('puff_puff', 2);
  perform pg_temp.assert(r->>'message' ilike '%2 × Puff-puff%₦600%', 'buy message: ' || (r->>'message'));
  perform pg_temp.assert((select cash from profiles where id = v) = 7400, 'paid 600 cash');
  perform pg_temp.assert(pg_temp.qty(v, 'puff_puff') = 2, '2 puff-puff in the bag');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'shop' and delta = -600 and account = 'cash'
                                 and meta->>'item' = 'puff_puff'), 'shop ledger');
  perform shop_buy('puff_puff');
  perform pg_temp.assert(pg_temp.qty(v, 'puff_puff') = 3, 'stacks to 3');
  perform pg_temp.assert((shop_list()->'items' @> '[{"id":"puff_puff","owned":3}]'), 'owned count in the list');

  -- refusals
  perform pg_temp.s_hint($q$ select shop_buy('laptop') $q$, 'not_sold_here');
  perform pg_temp.s_hint($q$ select shop_buy('no_such_thing') $q$, 'no_item');
  perform pg_temp.s_hint($q$ select shop_buy('puff_puff', 0) $q$, 'bad_qty');
  perform pg_temp.s_hint($q$ select shop_buy('puff_puff', 11) $q$, 'bad_qty');
  update profiles set cash = 100 where id = v;
  perform pg_temp.s_hint($q$ select shop_buy('puff_puff') $q$, 'not_enough_cash');
  perform pg_temp.assert(not (shop_list()->'items' @> '[{"id":"puff_puff","affordable":true}]'), 'not affordable with ₦100');
  update profiles set cash = 5000, busy_until = bl_now() + interval '1 hour' where id = v;
  perform pg_temp.s_hint($q$ select shop_buy('puff_puff') $q$, 'busy');
  update profiles set busy_until = null, travel_to = 'uselu_market' where id = v;
  perform pg_temp.s_hint($q$ select shop_buy('puff_puff') $q$, 'traveling');
  update profiles set travel_to = null where id = v;
  perform pg_temp.assert(pg_temp.qty(v, 'puff_puff') = 3 and (select cash from profiles where id = v) = 5000, 'refusals change nothing');
  -- max qty is config-driven
  update game_config set value = '20' where key = 'shop.max_qty_per_buy';
  perform shop_buy('puff_puff', 11);
  update game_config set value = '10' where key = 'shop.max_qty_per_buy';
  perform pg_temp.assert(pg_temp.qty(v, 'puff_puff') = 14, 'bought 11 with a higher cap');
  raise notice 'ok 1: shop_list + shop_buy';
end $$;

-- ---------- 2. item_use ----------
do $$
declare v uuid := pg_temp.su('Shop_A'); r jsonb; me profiles;
begin
  perform pg_temp.login(v);
  delete from inventory where user_id = v;
  perform bl_give_item(v, 'puff_puff', 2);
  perform pg_temp.s_at(v, 'oba_market', 5000, 0);
  r := item_use('puff_puff');
  select * into me from profiles where id = v;
  perform pg_temp.assert(abs(me.hunger - 62) < 0.05 and abs(me.fun - 53) < 0.05, 'puff-puff: hunger +12 fun +3, got ' || me.hunger || '/' || me.fun);
  perform pg_temp.assert(r->>'message' = 'You ate Puff-puff (5 balls). 1 left.' and (r->>'left')::int = 1, 'use message: ' || (r->>'message'));
  perform pg_temp.assert(me.busy_until is null, 'eating is instant');
  perform item_use('puff_puff');
  perform pg_temp.assert(not exists (select 1 from inventory where user_id = v and item_id = 'puff_puff'), 'empty row removed');
  perform pg_temp.s_hint($q$ select item_use('puff_puff') $q$, 'no_item');
  -- drinks lower the bladder
  perform bl_give_item(v, 'pure_water', 1);
  perform item_use('pure_water');
  perform pg_temp.assert(abs((select bladder from profiles where id = v) - 72) < 0.05, 'water: bladder -8');
  -- boost and keep items are not "used"
  perform bl_give_item(v, 'soap', 1);
  perform bl_give_item(v, 'laptop', 1);
  perform pg_temp.s_hint($q$ select item_use('soap') $q$, 'use_with_activity');
  perform pg_temp.s_hint($q$ select item_use('laptop') $q$, 'not_usable');
  perform pg_temp.assert(pg_temp.qty(v, 'soap') = 1 and pg_temp.qty(v, 'laptop') = 1, 'still in the bag');
  -- busy: can't eat mid-activity
  perform bl_give_item(v, 'puff_puff', 1);
  update profiles set busy_until = bl_now() + interval '1 hour' where id = v;
  perform pg_temp.s_hint($q$ select item_use('puff_puff') $q$, 'busy');
  update profiles set busy_until = null where id = v;
  raise notice 'ok 2: item_use';
end $$;

-- ---------- 3. soap boosts the home bath ----------
do $$
declare v uuid := pg_temp.su('Shop_A'); r jsonb; me profiles;
begin
  perform pg_temp.login(v);
  perform pg_temp.s_at(v, 'ekenwan_room', 5000, 0);
  r := do_activity('bathe');                       -- hygiene 10 + 60 + 20 (soap)
  select * into me from profiles where id = v;
  perform pg_temp.assert(abs(me.hygiene - 90) < 0.05 and abs(me.fun - 52) < 0.05, 'soap bath: hygiene 90 fun +2, got ' || me.hygiene);
  perform pg_temp.assert(pg_temp.qty(v, 'soap') = 0, 'soap used up');
  perform pg_temp.assert(r->>'message' ilike '%Used: Bar of soap%' and r->'used' = '["Bar of soap"]', 'bath message: ' || (r->>'message'));
  perform pg_temp.s_at(v, 'ekenwan_room', 5000, 0);
  perform do_activity('bathe');                    -- no soap left: plain +60
  perform pg_temp.assert(abs((select hygiene from profiles where id = v) - 70) < 0.05, 'plain bath +60');
  raise notice 'ok 3: soap boost';
end $$;

-- ---------- 4. item_sell ----------
do $$
declare v uuid := pg_temp.su('Shop_A'); r jsonb;
begin
  perform pg_temp.login(v);
  perform pg_temp.s_at(v, 'oba_market', 1000, 0);
  perform shop_buy('soap', 2);                     -- 600
  r := item_sell('soap', 2);                       -- 30% of 300 = 90 each
  perform pg_temp.assert((r->>'earned')::int = 180 and (select cash from profiles where id = v) = 1000 - 600 + 180, 'sold 2 soap for 180');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'shop_sell' and delta = 180), 'sell ledger');
  perform pg_temp.assert(pg_temp.qty(v, 'soap') = 0, 'soap gone');
  perform pg_temp.s_hint($q$ select item_sell('puff_puff') $q$, 'not_sellable');
  perform pg_temp.s_hint($q$ select item_sell('laptop', 2) $q$, 'no_item');
  r := item_sell('laptop');                        -- 40% of 45,000
  perform pg_temp.assert((r->>'earned')::int = 18000, 'laptop resale 18,000, got ' || (r->>'earned'));
  perform pg_temp.s_at(v, 'bronze_tech_hub', 1000, 0);
  perform bl_give_item(v, 'soap', 1);
  perform pg_temp.s_hint($q$ select item_sell('soap') $q$, 'cant_sell_here');
  raise notice 'ok 4: item_sell';
end $$;

-- ---------- 5. ChopNow + laptop -> Tech requirement ----------
do $$
declare v uuid := pg_temp.s_make('Shop_B', 'ekenwan_face_me'); m jsonb; r jsonb; me profiles; j jsonb;
begin
  perform pg_temp.s_at(v, 'ekenwan_room', 5000, 1000);
  m := food_menu();
  perform pg_temp.assert(m->'items' @> '[{"id":"jollof_pack","shop_price":2000,"price":2800}]', 'jollof 2000 + 40% = 2800');
  perform pg_temp.assert(m->'items' @> '[{"id":"puff_puff","price":500}]', 'puff-puff 300 + min fee 200 = 500');
  perform pg_temp.assert(not (m->'items' @> '[{"id":"soap"}]') and not (m->'items' @> '[{"id":"laptop"}]'), 'menu is food and drink only');
  update profiles set busy_until = bl_now() + interval '1 hour' where id = v;   -- works while busy
  r := food_order('jollof_pack');
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.bank = 0 and me.cash = 5000 - 1800, 'paid 1000 by transfer + 1800 cash: ' || me.bank || '/' || me.cash);
  perform pg_temp.assert(pg_temp.qty(v, 'jollof_pack') = 1 and (r->>'paid')::int = 2800, 'jollof delivered');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'food_delivery' and account = 'bank' and delta = -1000), 'delivery ledger');
  perform pg_temp.s_hint($q$ select food_order('laptop') $q$, 'not_on_menu');
  perform pg_temp.s_hint($q$ select food_order('soap') $q$, 'not_on_menu');
  update profiles set cash = 100, bank = 0 where id = v;
  perform pg_temp.s_hint($q$ select food_order('jollof_pack') $q$, 'not_enough_cash');
  update profiles set jailed_until = bl_now() + interval '1 hour', cash = 9000 where id = v;
  perform pg_temp.s_hint($q$ select food_order('jollof_pack') $q$, 'jailed');
  update profiles set jailed_until = null where id = v;
  -- markup is config-driven
  update game_config set value = '100' where key = 'shop.delivery_markup_pct';
  perform pg_temp.assert(food_menu()->'items' @> '[{"id":"jollof_pack","price":4000}]', 'markup 100% -> 4000');
  update game_config set value = '40' where key = 'shop.delivery_markup_pct';

  -- laptop at the Tech Hub unlocks Junior Dev
  perform job_apply('tech');
  j := (select x from jsonb_array_elements(jobs_catalog()->'tracks') x where x->>'id' = 'tech');
  perform pg_temp.assert(j->'levels'->1->'requirements' @> '[{"key":"item","met":false}]', 'laptop missing before');
  perform pg_temp.s_at(v, 'bronze_tech_hub', 50000, 0);
  r := shop_buy('laptop');
  perform pg_temp.assert(pg_temp.qty(v, 'laptop') = 1 and (select cash from profiles where id = v) = 5000, 'laptop bought for 45,000');
  j := (select x from jsonb_array_elements(jobs_catalog()->'tracks') x where x->>'id' = 'tech');
  perform pg_temp.assert(j->'levels'->1->'requirements' @> '[{"key":"item","met":true}]', 'laptop requirement met');
  perform pg_temp.assert(get_my_state()->'career'->'job'->'next'->'requirements' @> '[{"key":"item","met":true}]', 'career block sees the laptop');
  raise notice 'ok 5: ChopNow + laptop';
end $$;

-- ---------- 6. rent on: no back-charge, weekly charge, owed, sleep penalty, pay_rent ----------
do $$
declare v uuid := pg_temp.s_make('Shop_R', 'ekenwan_face_me'); me profiles; r jsonb; s jsonb; week numeric; due timestamptz;
begin
  week := 7 * 1440 * 60 / bl_cfg('clock.game_minutes_per_real_minute');
  perform pg_temp.s_at(v, 'ekenwan_room', 8000, 0);
  update profiles set weekly_rent = 1500 where id = v;   -- pin (admins may retune start_homes)
  -- a Sim who has not played for 3 weeks while rent was off: due date stuck in the past
  update profiles set rent_due_at = bl_now() - make_interval(secs => (week * 3)::double precision) where id = v;
  -- the migration's one-time switch only flips the seeded default (an admin's choice is kept)
  update game_config set updated_by = v where key = 'rent.enabled';
  update game_config set value = 'true'::jsonb where key = 'rent.enabled' and value = 'false'::jsonb and updated_by is null;
  perform pg_temp.assert(not bl_cfg_bool('rent.enabled'), 'admin-touched value not flipped');
  update game_config set updated_by = null where key = 'rent.enabled';
  update game_config set value = 'true'::jsonb where key = 'rent.enabled' and value = 'false'::jsonb and updated_by is null;
  perform pg_temp.assert(bl_cfg_bool('rent.enabled'), 'seeded default flipped on');
  -- switching on rolled the overdue due date forward: no back-charge
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.rent_due_at > bl_now() and me.rent_due_at <= bl_now() + make_interval(secs => week::double precision),
                         'due date rolled to the next rent day');
  perform pg_temp.assert(((bl_game_clock(me.rent_due_at))->>'weekday')::int = bl_cfg('rent.due_weekday')::int, 'still a rent weekday');
  perform travel_quote('national_museum');
  perform pg_temp.assert((select cash from profiles where id = v) = 8000 and not exists (select 1 from ledger where user_id = v and reason = 'rent'),
                         'no back-charge for the weeks rent was off');
  s := get_my_state();
  perform pg_temp.assert((s->'rent'->>'enabled')::boolean and (s->'rent'->>'owed_sleep_pct')::int = 60, 'rent block');

  -- weekly charge after time travel: bank first, then cash
  due := me.rent_due_at;
  update profiles set bank = 1000 where id = v;
  perform set_config('bl.test_offset_seconds', (extract(epoch from due - now()) + 60)::text, true);
  perform travel_quote('national_museum');
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.bank = 0 and me.cash = 8000 - 500 and me.rent_owed = 0, 'rent 1500: 1000 bank + 500 cash, got ' || me.bank || '/' || me.cash);
  perform pg_temp.assert(abs(extract(epoch from me.rent_due_at - due) - week) < 1, 'next due one week later');

  -- shortfall -> owed + landlord event
  update profiles set cash = 400 where id = v;
  perform pg_temp.s_advance(week);
  perform travel_quote('national_museum');
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.cash = 0 and me.rent_owed = 1100, 'owes 1100, got ' || me.rent_owed);
  perform pg_temp.assert(exists (select 1 from events where user_id = v and kind = 'rent_owed' and body ilike '%Landlord%'), 'landlord warning');

  -- sleeping while owing: 60% of the energy, landlord message
  perform pg_temp.s_at(v, 'ekenwan_room', 0, 0);
  update profiles set energy = 10 where id = v;
  r := do_activity('sleep');
  perform pg_temp.assert(abs((select energy from profiles where id = v) - (10 + 85 * 0.6)) < 0.05,
                         'sleep energy cut to 60%, got ' || (select energy from profiles where id = v));
  perform pg_temp.assert((r->>'rent_penalty')::boolean and r->>'message' ilike '%landlord%₦1,100%', 'sleep message: ' || (r->>'message'));
  perform pg_temp.s_at(v, 'ekenwan_room', 0, 0);
  perform do_activity('bathe');                    -- only sleep/nap are hit
  perform pg_temp.assert(abs((select hygiene from profiles where id = v) - 70) < 0.05, 'bath not affected');
  -- penalty is config-driven
  update game_config set value = '100' where key = 'rent.owed_sleep_energy_pct';
  perform pg_temp.s_at(v, 'ekenwan_room', 0, 0);
  update profiles set energy = 10 where id = v;
  r := do_activity('sleep');
  perform pg_temp.assert(abs((select energy from profiles where id = v) - 95) < 0.05 and not (r->>'rent_penalty')::boolean, '100% = no penalty');
  update game_config set value = '60' where key = 'rent.owed_sleep_energy_pct';

  -- pay_rent: nothing to pay with, partial, full, nothing owed
  perform pg_temp.s_at(v, 'oba_market', 0, 0);
  perform pg_temp.s_hint($q$ select pay_rent() $q$, 'not_enough_cash');
  update profiles set busy_until = bl_now() + interval '1 hour', cash = 600 where id = v;   -- works while busy (a transfer)
  r := pay_rent();
  select * into me from profiles where id = v;
  perform pg_temp.assert((r->>'paid')::int = 600 and me.rent_owed = 500 and me.cash = 0, 'partial payment: owes 500');
  update profiles set bank = 300, cash = 1000 where id = v;
  r := pay_rent();
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.rent_owed = 0 and me.bank = 0 and me.cash = 800 and (r->>'paid_bank')::int = 300, 'settled bank first');
  perform pg_temp.assert(r->>'message' ilike 'Rent settled%', 'settled message');
  perform pg_temp.assert(exists (select 1 from events where user_id = v and kind = 'rent_paid' and title = 'Rent settled'), 'settled event');
  perform pg_temp.assert((select count(*) from ledger where user_id = v and reason = 'rent' and meta ? 'settle') = 3, 'settle ledger rows');
  perform pg_temp.s_hint($q$ select pay_rent() $q$, 'no_rent_owed');
  -- sleeping after paying: full energy again
  perform pg_temp.s_at(v, 'ekenwan_room', 0, 0);
  update profiles set energy = 10 where id = v;
  r := do_activity('sleep');
  perform pg_temp.assert(not (r->>'rent_penalty')::boolean and abs((select energy from profiles where id = v) - 95) < 0.05, 'no penalty once paid');
  perform set_config('bl.test_offset_seconds', '', true);
  raise notice 'ok 6: rent on';
end $$;

-- ---------- 7. get_my_state inventory block stays read-only ----------
do $$
declare v uuid := pg_temp.su('Shop_B'); s jsonb; it jsonb; before profiles; after profiles;
begin
  perform pg_temp.login(v);
  perform bl_give_item(v, 'puff_puff', 3);
  select * into before from profiles where id = v;
  s := get_my_state();
  select * into after from profiles where id = v;
  perform pg_temp.assert(after.hunger = before.hunger and after.cash = before.cash and after.needs_updated_at = before.needs_updated_at, 'no writes');
  select x into it from jsonb_array_elements(s->'inventory') x where x->>'id' = 'puff_puff';
  perform pg_temp.assert((it->>'qty')::int = 3 and it->>'kind' = 'use' and it->>'icon' is not null and it ? 'resale_price', 'inventory entry: ' || coalesce(it::text, 'null'));
  perform pg_temp.assert(s->'inventory' @> '[{"id":"laptop","kind":"keep"}]', 'laptop listed as keep');
  perform pg_temp.assert(s ? 'origin' and s ? 'creator' and s ? 'rent' and s ? 'career', 'older blocks kept');
  raise notice 'ok 7: get_my_state inventory';
end $$;

do $$ begin raise notice 'ALL SHOPS TESTS PASSED'; end $$;
