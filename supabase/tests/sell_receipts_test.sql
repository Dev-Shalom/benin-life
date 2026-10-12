-- H2 sell furniture + cars, dealer price tiers, receipts (20261012000400_sell_receipts.sql). Rolled back. Run:
--   bash scripts/sql-test.sh -- supabase/tests/sell_receipts_test.sql
-- Groups: 1 sell furniture (payout, copy removal + key renumbering, ledger, fixed refusals; H4: starters sell) ·
-- 2 receipts above/below the threshold (furniture) · 3 dealer price tiers + stock · 4 car purchase receipt ·
-- 5 sell a car (bank payout, ledger, refusals, no market path) · 6 RLS + grants on receipts · 7 switches.
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

create or replace function pg_temp.sr_at_hour(p_hour int) returns void
language plpgsql as $$
declare c jsonb; cur numeric; delta numeric;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  c := bl_game_clock();
  cur := (c->>'hour')::numeric * 3600 + (c->>'minute')::numeric * 60;
  delta := ((p_hour * 3600 + 1800 - cur)::numeric % 86400 + 86400) % 86400;
  perform set_config('bl.test_offset_seconds', delta::text, true);
end $$;

do $$
declare a uuid := pg_temp.new_user('h2_a@sell.bl'); b uuid := pg_temp.new_user('h2_b@sell.bl');
begin
  perform set_config('h2.a', a::text, true); perform set_config('h2.b', b::text, true);
  update game_config set value = 'true' where key in ('furniture.sell_enabled', 'cars.sell_enabled', 'receipts.enabled');
  update game_config set value = '45' where key = 'furniture.resale_pct';
  update game_config set value = '60' where key = 'cars.resale_pct';
  update game_config set value = '500000' where key = 'receipts.min_amount';
  update car_dealers set active = true, multiplier = case tier when 'budget' then 0.88 when 'mid' then 1 else 1.2 end;
  update items set price = 2500000 where id = 'tokunbo_car';
  update items set price = 450000000 where id = 'lambo_urus';
  update furniture set price = 6500, max_qty = 6, active = true, buyable = true where id = 'plastic_chair_red';
  update furniture set price = 1250000, active = true, buyable = true where id = 'tv_75';
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(a);
  perform create_profile_v2('H2_Seller', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(b);
  perform create_profile_v2('H2_Other', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, busy_until = null, travel_to = null where id in (a, b);
end $$;

-- ---------- 1. sell furniture ----------
do $$
declare a uuid := current_setting('h2.a')::uuid; r jsonb; c0 bigint; n int;
begin
  perform pg_temp.login(a);
  update profiles set cash = 100000, bank = 0 where id = a;
  perform furniture_buy('plastic_chair_red');
  perform furniture_buy('plastic_chair_red');
  perform furniture_buy('plastic_chair_red');
  perform pg_temp.assert((select qty from player_furniture where user_id = a and furniture_id = 'plastic_chair_red') = 3, 'three chairs');
  -- copy 3 stands somewhere special; selling copy 1 hands its key (and spot) to copy 3's row
  update player_house_furniture set stored = false, x = 1.234, z = 0.5 where owner_id = a and furniture_key = 'own_plastic_chair_red-3';
  select cash into c0 from profiles where id = a;
  r := furniture_sell('own_plastic_chair_red');
  perform pg_temp.assert((r->>'earned')::bigint = 2900, '45% of 6,500 rounded down to ₦100 = 2,900: ' || r::text);
  perform pg_temp.assert((select cash from profiles where id = a) = c0 + 2900, 'paid in cash');
  perform pg_temp.assert((select qty from player_furniture where user_id = a and furniture_id = 'plastic_chair_red') = 2, 'qty 3 -> 2');
  perform pg_temp.assert(not exists (select 1 from player_house_furniture where owner_id = a and furniture_key = 'own_plastic_chair_red-3'), 'last key gone');
  perform pg_temp.assert((select x from player_house_furniture where owner_id = a and furniture_key = 'own_plastic_chair_red') = 1.234
                         and not (select stored from player_house_furniture where owner_id = a and furniture_key = 'own_plastic_chair_red'),
                         'copy 3 took key 1 with its spot');
  perform pg_temp.assert(r->>'moved_from' = 'own_plastic_chair_red-3', 'moved_from reported');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'furniture_sell' and delta = 2900 and account = 'cash'
                                   and meta->>'furniture' = 'plastic_chair_red'), 'ledger row');
  perform pg_temp.assert(bl_ledger_label('furniture_sell', '{"name":"Red plastic chair"}') = 'Sold furniture: Red plastic chair', 'ledger label');
  -- sell the rest: the row disappears
  perform furniture_sell('own_plastic_chair_red-2');
  perform furniture_sell('own_plastic_chair_red');
  perform pg_temp.assert(not exists (select 1 from player_furniture where user_id = a and furniture_id = 'plastic_chair_red'), 'all sold: row gone');
  select count(*) into n from player_house_furniture where owner_id = a and furniture_key like 'own_plastic_chair_red%';
  perform pg_temp.assert(n = 0, 'no placement rows left');
  -- refusals
  perform pg_temp.assert(pg_temp.hint_of($q$ select furniture_sell('own_plastic_chair_red') $q$) = 'not_owned', 'not owned');
  perform pg_temp.assert(pg_temp.hint_of($q$ select furniture_sell('bed') $q$) = 'fixed_furniture', 'built-in / fixed key refused');
  -- H4 (20261012001400): the starter mat came with the house and sells at furniture.included_resale_pct (25%)
  perform pg_temp.assert((furniture_sell('own_foam_mat')->>'earned')::bigint = 6200, 'H4: starter mat sells for 25% of 25,000');
  -- a bought extra copy of a starter piece: the bought one takes key 1, the starter is the highest copy
  perform furniture_buy('stool');
  perform pg_temp.assert((select qty from player_furniture where user_id = a and furniture_id = 'stool') = 2, 'two stools');
  r := furniture_sell('own_stool-2');
  perform pg_temp.assert((r->>'included')::boolean and (select qty from player_furniture where user_id = a and furniture_id = 'stool') = 1, 'starter stool (copy 2) sold');
  perform pg_temp.assert(not (furniture_sell_quote('own_stool')->>'included')::boolean, 'the bought stool is left on key 1');
  -- busy refuses
  update profiles set busy_until = bl_now() + interval '1 minute', busy_label = 'Sleeping' where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$ select furniture_sell('own_stool') $q$) = 'busy', 'busy refuses');
  update profiles set busy_until = null, busy_label = null where id = a;
  raise notice 'ok 1: sell furniture';
end $$;

-- ---------- 2. receipts: above and below the threshold ----------
do $$
declare a uuid := current_setting('h2.a')::uuid; r jsonb; n0 int;
begin
  perform pg_temp.login(a);
  update profiles set cash = 2000000, bank = 0 where id = a;
  select count(*) into n0 from receipts where user_id = a;
  r := furniture_buy('plastic_chair_red');
  perform pg_temp.assert(not (r ? 'receipt'), 'no receipt under ₦500k');
  perform pg_temp.assert((select count(*) from receipts where user_id = a) = n0, 'no row under the threshold');
  r := furniture_buy('tv_75');
  perform pg_temp.assert(r ? 'receipt' and (r->'receipt'->>'amount')::bigint = 1250000, 'receipt returned: ' || r::text);
  perform pg_temp.assert(r->'receipt'->>'ref' ~ '^BL-[0-9]{4}-[A-Z2-9]{6}$', 'ref format BL-YYYY-XXXXXX: ' || (r->'receipt'->>'ref'));
  perform pg_temp.assert(r->'receipt'->>'kind' = 'furniture' and r->'receipt'->>'seller' <> '', 'kind + seller');
  perform pg_temp.assert(exists (select 1 from receipts where user_id = a and ref = r->'receipt'->>'ref' and amount = 1250000), 'row stored');
  perform pg_temp.assert(r->>'furniture_key' = 'own_tv_75', 'normal result still there');
  -- threshold is admin-tunable
  update game_config set value = '5000' where key = 'receipts.min_amount';
  r := furniture_buy('plastic_chair_red');
  perform pg_temp.assert(r ? 'receipt', 'lower threshold -> receipt for a chair');
  update game_config set value = '500000' where key = 'receipts.min_amount';
  raise notice 'ok 2: receipts above / below threshold';
end $$;

-- ---------- 3. dealer price tiers ----------
do $$
declare a uuid := current_setting('h2.a')::uuid; lot jsonb; mid jsonb; sdd jsonb; p_lot bigint; p_mid bigint; p_sdd bigint; j jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.sr_at_hour(11);
  lot := shop_list('tokunbo_lot'); mid := shop_list('ighodalo_cars'); sdd := shop_list('sdd_motors');
  select (x->>'price')::bigint into p_lot from jsonb_array_elements(lot->'items') x where x->>'id' = 'tokunbo_car';
  select (x->>'price')::bigint into p_mid from jsonb_array_elements(mid->'items') x where x->>'id' = 'tokunbo_car';
  select (x->>'price')::bigint into p_sdd from jsonb_array_elements(sdd->'items') x where x->>'id' = 'tokunbo_car';
  perform pg_temp.assert(p_lot = 2200000 and p_mid = 2500000 and p_sdd = 3000000,
    format('tokunbo saloon: lot 2.2m / mid 2.5m / showroom 3.0m (got %s / %s / %s)', p_lot, p_mid, p_sdd));
  perform pg_temp.assert(lot->'dealer'->>'tier' = 'budget' and mid->'dealer'->>'tier' = 'mid' and sdd->'dealer'->>'tier' = 'premium', 'tiers in shop_list');
  perform pg_temp.assert((select (x->>'base_price')::bigint from jsonb_array_elements(sdd->'items') x where x->>'id' = 'tokunbo_car') = 2500000, 'base price shown');
  -- non-dealer places keep base prices and have no dealer block
  j := shop_list('oba_market');
  perform pg_temp.assert(jsonb_typeof(j->'dealer') = 'null', 'market: no dealer');
  -- luxury stock only at the premium showroom (seeded rows)
  if (select sold_at from items where id = 'lambo_urus') = '{sdd_motors}' then
    perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(lot->'items') x where x->>'id' = 'lambo_urus'), 'no Urus at the lot');
    perform pg_temp.assert(exists (select 1 from jsonb_array_elements(sdd->'items') x where x->>'id' = 'lambo_urus'), 'Urus at SDD');
    update profiles set location_id = 'tokunbo_lot', busy_until = null where id = a;
    perform pg_temp.assert(pg_temp.hint_of($q$ select shop_buy('lambo_urus', 1) $q$) = 'not_sold_here', 'Urus not sold at the lot');
  end if;
  -- the place card shows the dealer price too
  j := place_interior('sdd_motors');
  perform pg_temp.assert(j::text like '%' || (select bl_dealer_price(i, 'sdd_motors')::text from items i where id = 'lambo_urus') || '%', 'card cost = dealer price');
  -- admin multiplier is live
  update car_dealers set multiplier = 1.5 where location_id = 'sdd_motors';
  perform pg_temp.assert((select bl_dealer_price(i, 'sdd_motors') from items i where id = 'tokunbo_car') = 3750000, 'multiplier tunable');
  update car_dealers set multiplier = 1.2 where location_id = 'sdd_motors';
  perform pg_temp.assert((select bl_dealer_price(i, 'oba_market') from items i where id = 'tokunbo_car') = 2500000, 'no dealer -> base');
  raise notice 'ok 3: dealer price tiers';
end $$;

-- ---------- 4. buy at the budget lot: dealer price charged + receipt ----------
do $$
declare a uuid := current_setting('h2.a')::uuid; r jsonb; p profiles;
begin
  perform pg_temp.login(a);
  perform pg_temp.sr_at_hour(11);
  delete from inventory where user_id = a and item_id = 'tokunbo_car';
  update profiles set location_id = 'tokunbo_lot', cash = 0, bank = 3000000, busy_until = null, travel_to = null where id = a;
  r := shop_buy('tokunbo_car', 1);
  select * into p from profiles where id = a;
  perform pg_temp.assert((r->>'spent')::bigint = 2200000 and p.bank = 800000, 'paid the lot price 2.2m: ' || r::text);
  perform pg_temp.assert(r ? 'receipt' and r->'receipt'->>'kind' = 'car' and (r->'receipt'->>'amount')::bigint = 2200000
                         and r->'receipt'->>'seller' = (select name from locations where id = 'tokunbo_lot'), 'car receipt from the lot');
  perform pg_temp.assert(r->'receipt'->'meta'->'dealer'->>'tier' = 'budget', 'receipt carries the tier');
  perform pg_temp.assert(bl_ledger_label('car_purchase', jsonb_build_object('item', 'tokunbo_car')) like 'Car: %', 'car ledger label');
  raise notice 'ok 4: car bought at dealer price with receipt';
end $$;

-- ---------- 5. sell a car ----------
do $$
declare a uuid := current_setting('h2.a')::uuid; r jsonb; b0 bigint;
begin
  perform pg_temp.login(a);
  -- on the road: refused
  update profiles set travel_to = 'oba_market' where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$ select car_sell('tokunbo_car') $q$) = 'traveling', 'no selling while on the road');
  update profiles set travel_to = null, location_id = 'oba_market' where id = a;
  -- the market won't take cars (one price path)
  perform pg_temp.assert(pg_temp.hint_of($q$ select item_sell('tokunbo_car', 1) $q$) = 'use_car_sell', 'market refuses cars');
  select bank into b0 from profiles where id = a;
  r := car_sell('tokunbo_car');
  perform pg_temp.assert((r->>'earned')::bigint = 1500000, '60% of the 2.5m base = 1.5m: ' || r::text);
  perform pg_temp.assert((select bank from profiles where id = a) = b0 + 1500000, 'paid into the bank');
  perform pg_temp.assert(not exists (select 1 from inventory where user_id = a and item_id = 'tokunbo_car'), 'car gone');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'car_sell' and delta = 1500000 and account = 'bank'), 'ledger row');
  perform pg_temp.assert(bl_ledger_label('car_sell', '{"name":"Tokunbo Saloon"}') = 'Sold car: Tokunbo Saloon', 'label');
  perform pg_temp.assert(pg_temp.hint_of($q$ select car_sell('tokunbo_car') $q$) = 'not_owned', 'sold already');
  perform pg_temp.assert(pg_temp.hint_of($q$ select car_sell('malt_drink') $q$) = 'not_a_car', 'not a car');
  -- garage_home no longer lists it
  perform pg_temp.assert(not ((garage_home())->'cars')::text like '%tokunbo_car%', 'garage drops the sold car');
  raise notice 'ok 5: sell a car';
end $$;

-- ---------- 6. receipts: RLS + grants ----------
do $$ begin perform pg_temp.login(current_setting('h2.b')::uuid); end $$;
set local role authenticated;
do $$ begin
  perform pg_temp.assert((select count(*) from receipts where user_id = current_setting('h2.a')::uuid) = 0, 'RLS: B cannot read A''s receipts');
  begin
    insert into receipts (user_id, kind, item_name, amount, ref) values (current_setting('h2.b')::uuid, 'x', 'Fake', 1, 'BL-FAKE');
    raise exception 'TEST FAILED: direct insert worked';
  exception when insufficient_privilege then null; end;
  begin
    update receipts set amount = 1;
    raise exception 'TEST FAILED: direct update worked';
  exception when insufficient_privilege then null; end;
  perform pg_temp.assert((select count(*) from car_dealers) >= 3, 'dealers readable');
end $$;
reset role;
do $$ begin perform pg_temp.login(current_setting('h2.a')::uuid); end $$;
set local role authenticated;
do $$ begin
  perform pg_temp.assert((select count(*) from receipts where user_id = current_setting('h2.a')::uuid) >= 3, 'RLS: owner reads own receipts');
end $$;
reset role;
do $$ begin
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_receipt_issue(uuid,text,text,bigint,text,jsonb)', 'execute'), 'issuer private');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_dealer_price(items,text)', 'execute'), 'dealer price private');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.furniture_sell(text)', 'execute')
                         and not has_function_privilege('anon', 'public.furniture_sell(text)', 'execute'), 'furniture_sell grants');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.car_sell(text)', 'execute')
                         and not has_function_privilege('anon', 'public.car_sell(text)', 'execute'), 'car_sell grants');
  perform pg_temp.assert(not has_table_privilege('anon', 'public.receipts', 'select'), 'anon cannot read receipts');
  raise notice 'ok 6: RLS + grants';
end $$;

-- ---------- 7. switches ----------
do $$
declare a uuid := current_setting('h2.a')::uuid; r jsonb;
begin
  perform pg_temp.login(a);
  update game_config set value = 'false' where key = 'furniture.sell_enabled';
  perform pg_temp.assert(pg_temp.hint_of($q$ select furniture_sell('own_tv_75') $q$) = 'sell_disabled', 'furniture selling off');
  update game_config set value = 'false' where key = 'cars.sell_enabled';
  perform pg_temp.assert(pg_temp.hint_of($q$ select car_sell('tokunbo_car') $q$) = 'sell_disabled', 'car selling off');
  update game_config set value = 'false' where key = 'receipts.enabled';
  update profiles set cash = 2000000 where id = a;
  delete from player_furniture where user_id = a and furniture_id = 'tv_75';
  r := furniture_buy('tv_75');
  perform pg_temp.assert(not (r ? 'receipt'), 'receipts off');
  raise notice 'ok 7: switches';
end $$;
