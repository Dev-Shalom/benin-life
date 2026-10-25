-- Cooking and markets (20261030000100_cooking.sql, docs/COOKING.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/cooking_test.sql
-- The clock is pinned to 10:00 Benin time, time moves with bl.test_offset_seconds, random rolls are pinned with bl.test_rand.
-- Groups: 1 seeds, settings, anchors · 2 prices (daily band, determinism, yesterday, supermarket fixed) · 3 buying at both places, hours ·
-- 4 cooking: ingredients, home, stove, level, pots, portions, eating, certificate · 5 Cooking XP cap · 6 sharing with a partner ·
-- 7 kids feeding · 8 admin editors · 9 grants, RLS, no profiles changes.
update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');
update game_config set value = '0' where key = 'kids.daily_sick_pct';

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

create or replace function pg_temp.msg_of(p_sql text) returns text
language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  return sqlerrm;
end $$;

create or replace function pg_temp.advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;

create or replace function pg_temp.hours(p_h numeric) returns void language sql as $$ select pg_temp.advance(p_h * 3600) $$;

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('ck.' || p)::uuid $$;
create or replace function pg_temp.cash(p_uid uuid) returns bigint language sql as $$ select cash + bank from profiles where id = p_uid $$;
create or replace function pg_temp.login_as(p text) returns void language sql as $$ select pg_temp.login(pg_temp.u(p)) $$;
create or replace function pg_temp.qty(p_uid uuid, p_item text) returns int language sql as $$ select coalesce((select qty from inventory where user_id = p_uid and item_id = p_item), 0) $$;
create or replace function pg_temp.ev(p_uid uuid, p_kind text) returns bigint language sql as $$ select count(*) from events where user_id = p_uid and kind = p_kind $$;

create or replace function pg_temp.at(p_uid uuid, p_loc text) returns void
language sql as $$
  update profiles set location_id = p_loc, travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
                      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = bl_now(), rent_due_at = null
   where id = p_uid;
$$;

create or replace function pg_temp.mk(p_name text, p_age interval default interval '30 days') returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@ck.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, protected_until = null, created_at = bl_now() - p_age, cash = 1000000, bank = 0, home_location_id = 'uselu_selfcon',
         energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0 where id = v;
  perform pg_temp.at(v, 'uselu_selfcon');
  return v;
end $$;

create or replace function pg_temp.couple(p_a uuid, p_b uuid, p_days numeric default 5) returns bigint
language plpgsql as $$
declare v bigint;
begin
  insert into love_relationships (user_a, user_b, asked_by, status, level, started_at, couple_at, last_activity_at)
  values (least(p_a, p_b), greatest(p_a, p_b), p_a, 'couple', 50, bl_now() - make_interval(secs => (p_days * 86400 + 60)::double precision),
          bl_now() - make_interval(secs => (p_days * 86400)::double precision), bl_now()) returning id into v;
  return v;
end $$;

create or replace function pg_temp.rel(p_a uuid, p_b uuid) returns bigint language sql as $$
  select id from love_relationships where user_a = least(p_a, p_b) and user_b = greatest(p_a, p_b) order by id desc limit 1 $$;

create or replace function pg_temp.mkchild(p_a uuid, p_b uuid, p_age interval default interval '1 hour', p_name text default 'Testy') returns bigint
language plpgsql as $$
declare v bigint; c kids_children;
begin
  insert into kids_children (rel_id, parent_a, parent_b, proposed_by, status, name, gender, conceived_at, due_at, born_at,
                             hunger, hunger_at, sleep, sleep_at, fun, fun_at, health, health_at, love, love_at, clean, clean_at, last_care_at, score_at)
  values (pg_temp.rel(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), p_a, 'home', p_name, 'girl', bl_now() - p_age - interval '3 days', bl_now() - p_age, bl_now() - p_age,
          100, bl_now(), 100, bl_now(), 100, bl_now(), 100, bl_now(), 100, bl_now(), 100, bl_now(), bl_now(), bl_now()) returning id into v;
  update kids_children set next_roll_at = bl_kids_roll_time(v, bl_now()) where id = v;
  select * into c from kids_children where id = v;
  update kids_children set next_alert_at = bl_kids_next(c) where id = v;
  return v;
end $$;

create or replace function pg_temp.cj(p_child bigint) returns jsonb language sql as $$
  select x from jsonb_array_elements(kids_status() -> 'children') x where (x ->> 'id')::bigint = p_child $$;

-- put p_qty of an item in a bag
create or replace function pg_temp.give(p_uid uuid, p_item text, p_qty int) returns void
language sql as $$
  insert into inventory (user_id, item_id, qty) values (p_uid, p_item, p_qty) on conflict (user_id, item_id) do update set qty = p_qty;
$$;

-- every ingredient for p_pots batches of a recipe (and nothing else of it)
create or replace function pg_temp.pantry(p_uid uuid, p_recipe text, p_pots int default 1) returns void
language plpgsql as $$
declare r record;
begin
  for r in select item_id, qty from cook_ingredients where recipe_id = p_recipe loop
    perform pg_temp.give(p_uid, r.item_id, r.qty * p_pots);
  end loop;
end $$;

create or replace function pg_temp.setxp(p_uid uuid, p_xp int) returns void
language sql as $$
  insert into player_skills (user_id, skill_id, xp) values (p_uid, 'cooking', p_xp) on conflict (user_id, skill_id) do update set xp = p_xp;
$$;

create or replace function pg_temp.price(p_item text, p_loc text) returns bigint
language sql as $$ select bl_dealer_price((select i from items i where i.id = p_item), p_loc) $$;

-- ---------- setup ----------
do $$
declare
  v_keys text[] := array['adm', 'a', 'b', 'c', 'd'];
  k text; u uuid;
  v_local timestamp := now() at time zone bl_clock_tz();
  v_target timestamp;
begin
  v_target := date_trunc('day', v_local) + case when v_local::time >= time '10:00' then interval '34 hours' else interval '10 hours' end;
  perform set_config('bl.test_offset_seconds', extract(epoch from (v_target - v_local))::text, true);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  foreach k in array v_keys loop
    u := pg_temp.mk('CK_' || k);
    perform set_config('ck.' || k, u::text, true);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
  perform pg_temp.couple(pg_temp.u('a'), pg_temp.u('b'), 5);
  update game_config set value = '0' where key = 'moments.daily_cap';
  update game_config set value = '0' where key in ('kids.feed_cooldown_minutes', 'kids.change_cooldown_minutes', 'kids.play_cooldown_minutes', 'kids.medicine_cooldown_minutes', 'kids.cuddle_cooldown_minutes', 'kids.sleep_cooldown_minutes');
  update profiles set cash = 5000000 where id in (pg_temp.u('a'), pg_temp.u('b'), pg_temp.u('c'), pg_temp.u('d'));
  -- player c has no stove
  delete from player_furniture where user_id = pg_temp.u('c') and furniture_id in (select id from furniture where 'cook_home' = any (activities));
end $$;

-- ---------- 1. seeds, settings, anchors ----------
do $$
declare v_n int; r record; v text;
begin
  perform pg_temp.assert((select count(*) from items where category = 'ingredient') = 26, 'twenty-six ingredients');
  perform pg_temp.assert(not exists (select 1 from items where category = 'ingredient' and (not ('oba_market' = any (sold_at)) or not ('edo_fresh_supermarket' = any (sold_at)))), 'every ingredient is sold at Oba Market and the supermarket');
  perform pg_temp.assert(not exists (select 1 from items where category = 'ingredient' and (sellable or tradeable or resale_pct <> 0 or coalesce(icon, '') = '' or price <= 0)), 'ingredients: not resold, not traded, with an icon and a price');
  perform pg_temp.assert(not exists (select 1 from (values ('rice'), ('beans'), ('garri'), ('yam'), ('plantain'), ('palm_oil_cup'), ('veg_oil'), ('tomatoes'), ('pepper'), ('onions'), ('crayfish'), ('dry_fish'), ('chicken'), ('meat'), ('eggs'),
                                                      ('instant_noodles'), ('egusi'), ('bitter_leaf'), ('scent_leaf'), ('ugu'), ('palm_fruit'), ('beletete'), ('potash'), ('starch'), ('pap'), ('seasoning')) x(id)
                          where not exists (select 1 from items i where i.id = x.id and i.category = 'ingredient')), 'all the ingredients from the plan exist');
  -- 2026 Nigerian price anchors: a 50 kg bag of rice N68k-N105k (about 100 dericas), beans about N3,000 a kg, garri about N810 a kg
  perform pg_temp.assert((select price from items where id = 'rice') * 100 between 68000 and 105000 * 1, 'a derica of rice is anchored to a N68k-N105k bag of 50 kg: ' || (select price from items where id = 'rice'));
  perform pg_temp.assert((select price from items where id = 'beans') between 1000 and 1800, 'beans about N3,000 a kg: a derica is ' || (select price from items where id = 'beans'));
  perform pg_temp.assert((select price from items where id = 'garri') between 300 and 500, 'garri about N810 a kg: a derica is ' || (select price from items where id = 'garri'));
  perform pg_temp.assert((select price from items where id = 'yam') between 2000 and 6000 and (select price from items where id = 'eggs') between 150 and 400 and (select price from items where id = 'instant_noodles') between 250 and 500, 'yam, egg and noodles prices are in a sane range');
  perform pg_temp.assert(not exists (select 1 from items where category = 'ingredient' and name ~* '(lagos|indomie|maggi|knorr|peak|golden penny)'), 'no brand or Lagos in ingredient names');
  -- recipes
  perform pg_temp.assert((select count(*) from cook_recipes where active) = 9, 'nine recipes');
  perform pg_temp.assert(not exists (select 1 from (values ('Owo soup with starch'), ('Black soup (omoebe)'), ('Banga soup with starch or eba'), ('Jollof rice and chicken'), ('Egusi soup with pounded yam'), ('Beans and dodo'), ('Yam porridge (asaro)'), ('Akara and pap'), ('Indomie and egg')) x(n)
                          where not exists (select 1 from cook_recipes rc where rc.name = x.n)), 'the nine dishes from the plan');
  for r in select * from cook_recipes loop
    perform pg_temp.assert((select count(*) from cook_ingredients where recipe_id = r.id and qty > 0) >= 2, 'recipe has ingredients: ' || r.id);
    perform pg_temp.assert(r.portions >= 1 and r.game_minutes > 0 and r.hunger > 0 and r.xp > 0 and r.min_level >= 1, 'recipe numbers: ' || r.id);
    perform pg_temp.assert(exists (select 1 from items where id = 'dish_' || r.id and category = 'food' and cardinality(sold_at) = 0 and not sellable and not tradeable and price > 0
                                   and (effects ->> 'hunger')::numeric = r.hunger), 'dish item follows the recipe: ' || r.id);
    -- home cooking is cheaper per hunger point than the ready-made food packs (about N36-40 a point) but never free
    perform pg_temp.assert((select sum(i.price * c.qty) from cook_ingredients c join items i on i.id = c.item_id where c.recipe_id = r.id) / r.portions / r.hunger between 10 and 35, 'cost per hunger point sits in range: ' || r.id);
  end loop;
  perform pg_temp.assert((select min_level from cook_recipes where id = 'noodles_egg') = 1 and (select min_level from cook_recipes where id = 'black_soup') = 6
                         and (select cert_id from cook_recipes where id = 'black_soup') = 'catering' and exists (select 1 from certificates where id = 'catering'), 'harder dishes need a higher level; black soup needs the Catering certificate');
  perform pg_temp.assert((select count(distinct min_level) from cook_recipes) >= 5, 'a real level ladder');
  -- groceries carry no VAT
  perform pg_temp.cfg('economy.vat_enabled', 'true');
  perform pg_temp.assert((bl_tax_rates('item', 'ingredient', 1000))[1] = 0 and (bl_tax_rates('item', 'gadget', 1000))[1] > 0, 'groceries are VAT free, a gadget is not');
  perform pg_temp.cfg('economy.vat_enabled', 'false');
  -- places
  perform pg_temp.assert((select open_hour from locations where id = 'oba_market') = 6 and (select close_hour from locations where id = 'oba_market') = 20 and (select open_hour from locations where id = 'edo_fresh_supermarket') is null, 'Oba is a day market, the supermarket always open');
  -- every number is a setting with a label and a description
  select count(*) into v_n from game_config where category = 'cooking';
  perform pg_temp.assert(v_n = 16, 'sixteen cooking settings, got ' || v_n);
  perform pg_temp.assert(not exists (select 1 from game_config where category = 'cooking' and (coalesce(label, '') = '' or char_length(coalesce(description, '')) < 30)), 'every cooking setting has a label and a description');
  perform pg_temp.assert(not exists (select 1 from game_config where category = 'cooking' and kind in ('number', 'percent', 'naira', 'minutes') and (min is null or max is null)), 'every number has a min and a max');
  perform pg_temp.assert(not exists (select 1 from game_config where category = 'cooking' and kind in ('number', 'percent', 'naira', 'minutes') and ((value #>> '{}')::numeric < min or (value #>> '{}')::numeric > max)), 'every default is inside its min and max');
  for v in select unnest(array['cooking.enabled', 'cooking.market_band_pct', 'cooking.supermarket_markup_pct', 'cooking.max_pot', 'cooking.pot_time_extra_pct', 'cooking.max_busy_seconds', 'cooking.max_portions', 'cooking.stove_required',
                               'cooking.xp_daily_cap', 'cooking.easy_dish_levels', 'cooking.easy_dish_xp_pct', 'cooking.catering_cert', 'cooking.catering_time_cut_pct', 'cooking.share_daily_cap', 'cooking.kid_meal_enabled', 'cooking.kid_meal_boost_pct']) loop
    perform pg_temp.assert(exists (select 1 from game_config where key = v), 'setting exists: ' || v);
  end loop;
  perform pg_temp.assert((select value from game_config where key = 'cooking.market_band_pct') = '8'::jsonb and (select value from game_config where key = 'cooking.supermarket_markup_pct') = '30'::jsonb, 'default band 8 %, supermarket +30 %');
  perform pg_temp.assert(not exists (select 1 from cook_recipes where name ~* 'lagos' or blurb ~* 'lagos'), 'no Lagos in recipes');
  raise notice 'ok 1: seeds, settings, anchors';
end $$;

-- ---------- 2. prices ----------
do $$
declare
  it items; p bigint; v_sup bigint; v_min bigint; v_max bigint; i text; d int; v_seen bigint[]; v jsonb; v_t0 text := current_setting('bl.test_offset_seconds');
  v_today jsonb; v_up int; v_down int; x jsonb; y jsonb; v_band numeric; v_dev numeric; v_worst numeric := 0;
begin
  perform pg_temp.login_as('a');
  -- the supermarket is fixed at +30 %, Oba moves inside the band (default 8 %) and is never dearer than the supermarket
  for i in select id from items where category = 'ingredient' order by id loop
    select * into it from items where id = i;
    v_sup := bl_dealer_price(it, 'edo_fresh_supermarket');
    perform pg_temp.assert(v_sup = (case when it.price * 1.3 < 1000 then round(it.price * 1.3 / 10.0) * 10 else round(it.price * 1.3 / 50.0) * 50 end), 'supermarket is fixed at base + 30 %: ' || i || ' ' || v_sup);
    v_min := 9223372036854775807; v_max := 0; v_seen := '{}';
    for d in 1..14 loop
      p := bl_dealer_price(it, 'oba_market');
      perform pg_temp.assert(p between floor(it.price * 0.92) - 26 and ceil(it.price * 1.08) + 26, 'Oba price inside the 8 % band: ' || i || ' ' || p || ' base ' || it.price);
      perform pg_temp.assert(p <= v_sup, 'Oba is never dearer than the supermarket: ' || i);
      perform pg_temp.hours(2);
      perform pg_temp.assert(bl_dealer_price(it, 'oba_market') = p and bl_dealer_price(it, 'edo_fresh_supermarket') = v_sup, 'stable within a day: ' || i);
      perform pg_temp.hours(-2);
      v_min := least(v_min, p); v_max := greatest(v_max, p); v_seen := v_seen || p;
      perform pg_temp.hours(24);
    end loop;
    perform pg_temp.assert(v_max > v_min or it.price < 300, 'the Oba price moves from day to day: ' || i || ' ' || v_min || '..' || v_max);
    perform set_config('bl.test_offset_seconds', v_t0, true);
  end loop;
  -- deterministic: the same for another player, and the same again when we come back to the same day
  perform pg_temp.login_as('b');
  perform pg_temp.assert(pg_temp.price('rice', 'oba_market') = (select bl_dealer_price(i2, 'oba_market') from items i2 where i2.id = 'rice'), 'same price for another player');
  p := pg_temp.price('tomatoes', 'oba_market');
  perform pg_temp.hours(24 * 5); perform pg_temp.hours(-24 * 5);
  perform pg_temp.assert(pg_temp.price('tomatoes', 'oba_market') = p, 'the same day gives the same price (deterministic)');
  -- the shape of the day price: a fixed function of the day, the item and the place (it can be reproduced outside)
  perform pg_temp.assert(p = (select (case when q < 1000 then round(q / 10.0) * 10 else round(q / 50.0) * 50 end)::bigint
                                from (select least(it2.price * (1 + 0.08 * ((case when h >= 2147483648 then h - 4294967296 else h end) / 2147483648.0)), it2.price * 1.3) as q
                                        from items it2, (select ('x' || substr(md5(bl_cook_day(0) || ':tomatoes:oba_market'), 1, 8))::bit(32)::bigint as h) s where it2.id = 'tomatoes') z), 'the price is seeded by the date and the item');
  -- today's prices: yesterday's price is what the price was yesterday, with the change in percent
  v_today := grocery_prices();
  perform pg_temp.assert(jsonb_array_length(v_today -> 'items') = 26 and v_today ->> 'day' = bl_cook_day(0) and (v_today -> 'market' ->> 'open_now')::boolean and (v_today -> 'supermarket' ->> 'open_now')::boolean, 'grocery_prices lists all 26 and both places are open at 10:00');
  perform pg_temp.assert(v_today -> 'market' ->> 'hours' = '6 AM to 8 PM' and v_today -> 'supermarket' ->> 'hours' = 'Open all day', 'opening hours text: ' || (v_today -> 'market' ->> 'hours'));
  v_up := 0; v_down := 0;
  for x in select * from jsonb_array_elements(v_today -> 'items') loop
    perform pg_temp.assert((x ->> 'today')::bigint = pg_temp.price(x ->> 'id', 'oba_market') and (x ->> 'super')::bigint = pg_temp.price(x ->> 'id', 'edo_fresh_supermarket'), 'today and supermarket prices match the shop: ' || (x ->> 'id'));
    perform pg_temp.assert((x ->> 'yesterday')::bigint > 0 and (x ->> 'today')::bigint <= (x ->> 'super')::bigint, 'yesterday exists and Oba is cheaper: ' || (x ->> 'id'));
    perform pg_temp.assert(sign((x ->> 'change_pct')::numeric) = sign((x ->> 'today')::bigint - (x ->> 'yesterday')::bigint) or abs((x ->> 'change_pct')::numeric) < 0.1, 'trend sign matches: ' || x::text);
    if (x ->> 'change_pct')::numeric > 0 then v_up := v_up + 1; elsif (x ->> 'change_pct')::numeric < 0 then v_down := v_down + 1; end if;
  end loop;
  perform pg_temp.assert(v_up >= 3 and v_down >= 3, 'some prices are up and some are down vs yesterday: up ' || v_up || ' down ' || v_down);
  -- tomorrow's "yesterday" is today's price
  perform pg_temp.hours(24);
  y := grocery_prices();
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(v_today -> 'items') a join jsonb_array_elements(y -> 'items') b on a ->> 'id' = b ->> 'id' where (a ->> 'today') <> (b ->> 'yesterday')),
                         'tomorrow''s yesterday is today''s price for every item');
  perform set_config('bl.test_offset_seconds', v_t0, true);
  -- the admin band: 0 = never moves, 20 = wider (and still inside), the supermarket markup follows its setting
  perform pg_temp.cfg('cooking.market_band_pct', '0');
  for d in 1..4 loop
    perform pg_temp.assert(pg_temp.price('rice', 'oba_market') = 900 and pg_temp.price('beans', 'oba_market') = 1350, 'band 0: Oba is the base price every day');
    perform pg_temp.hours(24);
  end loop;
  perform set_config('bl.test_offset_seconds', v_t0, true);
  perform pg_temp.cfg('cooking.market_band_pct', '20');
  for i in select id from items where category = 'ingredient' loop
    select * into it from items where id = i;
    for d in 1..10 loop
      v_dev := abs(bl_dealer_price(it, 'oba_market') - it.price) * 100.0 / it.price;
      v_worst := greatest(v_worst, v_dev);
      perform pg_temp.assert(v_dev <= 20 + 4 or it.price < 400, 'band 20: inside +/- 20 %: ' || i || ' ' || v_dev);
      perform pg_temp.hours(24);
    end loop;
    perform set_config('bl.test_offset_seconds', v_t0, true);
  end loop;
  perform pg_temp.assert(v_worst > 10, 'band 20 gives bigger moves than band 8: ' || v_worst);
  perform pg_temp.cfg('cooking.market_band_pct', '8');
  perform pg_temp.cfg('cooking.supermarket_markup_pct', '50');
  perform pg_temp.assert(pg_temp.price('rice', 'edo_fresh_supermarket') = 1350 and pg_temp.price('rice', 'oba_market') <= 1350, 'supermarket markup follows the setting (+50 % = 1350)');
  perform pg_temp.cfg('cooking.supermarket_markup_pct', '30');
  -- the price is never an argument: the buy functions take no price from the client
  perform pg_temp.assert((select pronargs from pg_proc where oid = 'public.shop_buy(text, integer)'::regprocedure) = 2 and (select pronargs from pg_proc where oid = 'public.cook_start(text, integer)'::regprocedure) = 2, 'the client sends only the item and the amount');
  raise notice 'ok 2: prices';
end $$;

-- ---------- 3. buying at both places, hours ----------
do $$
declare
  v jsonb; b0 bigint; p_oba bigint; p_sup bigint; v_t0 text := current_setting('bl.test_offset_seconds');
begin
  perform pg_temp.login_as('a');
  perform pg_temp.at(pg_temp.u('a'), 'oba_market');
  delete from inventory where user_id = pg_temp.u('a');
  p_oba := pg_temp.price('rice', 'oba_market');
  -- shop list at Oba: the ingredient shows the day price and yesterday's price, the supermarket only the fixed price
  v := shop_list('oba_market');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(v -> 'items') x where x ->> 'category' = 'ingredient') = 26, 'Oba shop lists all 26 ingredients');
  perform pg_temp.assert((select (x ->> 'price')::bigint from jsonb_array_elements(v -> 'items') x where x ->> 'id' = 'rice') = p_oba
                         and (select (x ->> 'yesterday')::bigint from jsonb_array_elements(v -> 'items') x where x ->> 'id' = 'rice') > 0, 'Oba shop: day price and yesterday''s price');
  perform pg_temp.assert((select x -> 'yesterday' from jsonb_array_elements(v -> 'items') x where x ->> 'id' = 'pure_water') = 'null'::jsonb, 'other items have no yesterday price');
  b0 := pg_temp.cash(pg_temp.u('a'));
  v := shop_buy('rice', 2);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = b0 - 2 * p_oba and pg_temp.qty(pg_temp.u('a'), 'rice') = 2 and (v ->> 'spent')::bigint = 2 * p_oba, 'bought 2 dericas of rice at Oba for the day price, no VAT: ' || v::text);
  perform pg_temp.assert((select count(*) from ledger where user_id = pg_temp.u('a') and reason = 'shop' and meta ->> 'item' = 'rice') >= 1, 'a normal shop ledger row');
  -- the supermarket
  perform pg_temp.at(pg_temp.u('a'), 'edo_fresh_supermarket');
  p_sup := pg_temp.price('rice', 'edo_fresh_supermarket');
  v := shop_list('edo_fresh_supermarket');
  perform pg_temp.assert((select x -> 'yesterday' from jsonb_array_elements(v -> 'items') x where x ->> 'id' = 'rice') = 'null'::jsonb and (select (x ->> 'price')::bigint from jsonb_array_elements(v -> 'items') x where x ->> 'id' = 'rice') = p_sup, 'supermarket shelf: fixed price, no yesterday');
  b0 := pg_temp.cash(pg_temp.u('a'));
  v := shop_buy('rice', 3);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = b0 - 3 * p_sup and pg_temp.qty(pg_temp.u('a'), 'rice') = 5 and p_sup > p_oba, 'bought 3 at the supermarket; it is dearer than Oba');
  -- wrong place
  perform pg_temp.at(pg_temp.u('a'), 'third_east');
  perform pg_temp.assert(pg_temp.hint_of($q$select shop_buy('rice', 1)$q$) = 'not_sold_here', 'rice is not sold at a street corner');
  -- no money
  perform pg_temp.at(pg_temp.u('a'), 'oba_market');
  update profiles set cash = 100 where id = pg_temp.u('a');
  perform pg_temp.assert(pg_temp.hint_of($q$select shop_buy('rice', 1)$q$) = 'not_enough_cash', 'not enough cash');
  update profiles set cash = 5000000 where id = pg_temp.u('a');
  -- Oba is closed at night, the supermarket never closes
  perform pg_temp.cfg('places.hours_enabled', 'true');
  perform pg_temp.hours(13);   -- 23:00
  perform pg_temp.assert((grocery_prices() -> 'market' ->> 'open_now')::boolean = false and (grocery_prices() -> 'supermarket' ->> 'open_now')::boolean, 'night: Oba closed, the supermarket open');
  perform pg_temp.assert(pg_temp.hint_of($q$select shop_buy('rice', 1)$q$) = 'closed', 'Oba Market is closed at night');
  perform pg_temp.assert(pg_temp.msg_of($q$select shop_buy('rice', 1)$q$) like '%closed%Opens 6 AM%', 'the closed message says when it opens');
  perform pg_temp.at(pg_temp.u('a'), 'edo_fresh_supermarket');
  b0 := pg_temp.cash(pg_temp.u('a'));
  perform shop_buy('beans', 1);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) < b0 and pg_temp.qty(pg_temp.u('a'), 'beans') = 1, 'the supermarket sells at night');
  -- prices are still shown at night (read-only)
  perform pg_temp.assert(jsonb_array_length(grocery_prices() -> 'items') = 26, 'today''s prices can be read at night');
  perform set_config('bl.test_offset_seconds', v_t0, true);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  -- no VAT even when VAT is on
  perform pg_temp.cfg('economy.vat_enabled', 'true');
  b0 := pg_temp.cash(pg_temp.u('a'));
  perform shop_buy('eggs', 4);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = b0 - 4 * pg_temp.price('eggs', 'edo_fresh_supermarket'), 'groceries have no VAT on the till');
  perform pg_temp.cfg('economy.vat_enabled', 'false');
  -- ingredients cannot be sold back or eaten raw
  perform pg_temp.assert(pg_temp.hint_of($q$select item_use('rice')$q$) = 'not_usable', 'raw rice cannot be eaten');
  perform pg_temp.assert(pg_temp.hint_of($q$select item_sell('rice', 1)$q$) <> 'ok', 'ingredients cannot be sold back');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(food_menu() -> 'items') x where x ->> 'category' = 'ingredient' or (x ->> 'id') like 'dish\_%'), 'Chowdeck does not list ingredients or home-cooked dishes');
  raise notice 'ok 3: buying at both places and hours';
end $$;

-- ---------- 4. cooking ----------
do $$
declare
  v jsonb; r jsonb; a uuid := pg_temp.u('a'); c uuid := pg_temp.u('c'); n int; v_c1 numeric; v_s1 numeric; v_s2 numeric; b0 bigint;
begin
  perform pg_temp.login_as('a');
  perform pg_temp.at(a, 'uselu_selfcon');
  perform pg_temp.assert(coalesce((bl_furniture_for(a, 'cook_home') ->> 'owned')::boolean, false), 'player a has a stove from the start home');
  update game_config set value = '1000' where key = 'cooking.xp_daily_cap';
  -- kitchen overview (read-only)
  v := cook_overview();
  perform pg_temp.assert((v ->> 'at_home')::boolean and (v ->> 'stove')::boolean and (v ->> 'enabled')::boolean and (v ->> 'level')::int = 1 and jsonb_array_length(v -> 'recipes') = 9 and (v ->> 'max_pot')::int = 3, 'overview: at home, stove, level 1, 9 recipes: ' || left(v::text, 200));
  perform pg_temp.assert((select (x ->> 'level_ok')::boolean from jsonb_array_elements(v -> 'recipes') x where x ->> 'id' = 'noodles_egg') and not (select (x ->> 'level_ok')::boolean from jsonb_array_elements(v -> 'recipes') x where x ->> 'id' = 'egusi_pounded')
                         and not (select (x ->> 'cert_ok')::boolean from jsonb_array_elements(v -> 'recipes') x where x ->> 'id' = 'black_soup'), 'overview shows the locks');
  -- without ingredients
  delete from inventory where user_id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('noodles_egg', 1)$q$) = 'no_ingredients', 'no ingredients: refused');
  perform pg_temp.assert(pg_temp.msg_of($q$select cook_start('noodles_egg', 1)$q$) like 'Missing ingredients: 2 more egg, 2 more instant noodles.%', 'the message lists what is missing: ' || pg_temp.msg_of($q$select cook_start('noodles_egg', 1)$q$));
  perform pg_temp.give(a, 'instant_noodles', 2);
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('noodles_egg', 1)$q$) = 'no_ingredients' and pg_temp.qty(a, 'instant_noodles') = 2 and pg_temp.qty(a, 'dish_noodles_egg') = 0, 'half the ingredients: nothing is taken, nothing is cooked');
  -- not at home
  perform pg_temp.pantry(a, 'noodles_egg', 1);
  perform pg_temp.at(a, 'oba_market');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('noodles_egg', 1)$q$) = 'not_home' and pg_temp.qty(a, 'eggs') = 2, 'not at home: refused, ingredients kept');
  perform pg_temp.assert(not (cook_overview() ->> 'at_home')::boolean, 'overview says you are not at home');
  -- visiting somebody else's house is not your home either
  perform pg_temp.at(a, 'uselu_selfcon');
  update profiles set home_visit_host_id = pg_temp.u('b') where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('noodles_egg', 1)$q$) = 'not_home', 'a host''s home is not your home');
  update profiles set home_visit_host_id = null where id = a;
  -- no stove
  perform pg_temp.login_as('c'); perform pg_temp.at(c, 'uselu_selfcon'); perform pg_temp.pantry(c, 'noodles_egg', 1);
  perform pg_temp.assert(not (cook_overview() ->> 'stove')::boolean and pg_temp.hint_of($q$select cook_start('noodles_egg', 1)$q$) = 'no_stove', 'no stove: refused');
  perform pg_temp.cfg('cooking.stove_required', 'false');
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v ->> 'portions')::int = 2 and pg_temp.qty(c, 'dish_noodles_egg') = 2, 'stove switch off: any home will do');
  perform pg_temp.cfg('cooking.stove_required', 'true');
  perform pg_temp.login_as('a'); perform pg_temp.at(a, 'uselu_selfcon');
  -- level gating
  perform pg_temp.pantry(a, 'egusi_pounded', 1); perform pg_temp.pantry(a, 'jollof_chicken', 1); perform pg_temp.pantry(a, 'beans_dodo', 1);
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('egusi_pounded', 1)$q$) = 'skill_level' and pg_temp.msg_of($q$select cook_start('egusi_pounded', 1)$q$) like '%needs Cooking level 5 (you are level 1)%', 'level 5 dish at level 1: refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('jollof_chicken', 1)$q$) = 'skill_level' and pg_temp.hint_of($q$select cook_start('beans_dodo', 1)$q$) = 'skill_level', 'level 3 and level 2 dishes at level 1: refused');
  perform pg_temp.assert(pg_temp.qty(a, 'rice') = 3 and pg_temp.qty(a, 'chicken') = 2, 'a refused cook takes nothing');
  perform pg_temp.setxp(a, 40);   -- level 2
  v := cook_start('beans_dodo', 1);
  perform pg_temp.assert((v ->> 'portions')::int = 4 and pg_temp.qty(a, 'dish_beans_dodo') = 4 and pg_temp.qty(a, 'beans') = 0 and pg_temp.qty(a, 'plantain') = 0, 'level 2: beans and dodo cooks, 4 portions, ingredients taken: ' || v::text);
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('jollof_chicken', 1)$q$) = 'busy', 'busy while the pot is on');
  perform pg_temp.assert((select busy_label from profiles where id = a) = 'Cooking Beans and dodo' and (select busy_until from profiles where id = a) > bl_now(), 'the cook keeps the player busy');
  -- one batch of noodles: 2 portions, ingredients removed
  perform pg_temp.at(a, 'uselu_selfcon');
  perform pg_temp.pantry(a, 'noodles_egg', 1);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v ->> 'portions')::int = 2 and (v ->> 'pots')::int = 1 and pg_temp.qty(a, 'dish_noodles_egg') = 2 and pg_temp.qty(a, 'instant_noodles') = 0 and pg_temp.qty(a, 'eggs') = 0, 'noodles: 2 portions, noodles and eggs gone: ' || v::text);
  v_s1 := (v ->> 'seconds')::numeric;
  -- a bigger pot: x3 ingredients, x3 portions, longer
  perform pg_temp.at(a, 'uselu_selfcon');
  perform pg_temp.give(a, 'instant_noodles', 5); perform pg_temp.give(a, 'eggs', 5);
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('noodles_egg', 3)$q$) = 'no_ingredients', 'a pot of 3 needs 6 noodles and 6 eggs');
  perform pg_temp.give(a, 'instant_noodles', 6); perform pg_temp.give(a, 'eggs', 7);
  perform pg_temp.cfg('cooking.max_busy_seconds', '300');
  v := cook_start('noodles_egg', 3);
  perform pg_temp.assert((v ->> 'portions')::int = 6 and pg_temp.qty(a, 'dish_noodles_egg') = 8 and pg_temp.qty(a, 'instant_noodles') = 0 and pg_temp.qty(a, 'eggs') = 1, 'pot of 3: 6 portions, 6 noodles and 6 eggs taken: ' || v::text);
  perform pg_temp.assert((v ->> 'seconds')::numeric > v_s1 * 1.9 and (v ->> 'seconds')::numeric <= v_s1 * 2.1, 'a pot of 3 takes about double the time (+50 % per extra batch): ' || (v ->> 'seconds') || ' vs ' || v_s1);
  perform pg_temp.cfg('cooking.max_busy_seconds', '45');
  perform pg_temp.at(a, 'uselu_selfcon');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('noodles_egg', 0)$q$) = 'bad_pots' and pg_temp.hint_of($q$select cook_start('noodles_egg', 4)$q$) = 'bad_pots', 'pot size 1 to 3 only');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('no_such_dish', 1)$q$) = 'no_recipe', 'unknown recipe');
  -- the busy time is capped
  perform pg_temp.cfg('cooking.max_busy_seconds', '5');
  perform pg_temp.give(a, 'instant_noodles', 2); perform pg_temp.give(a, 'eggs', 2);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v ->> 'seconds')::numeric <= 5, 'cook time never goes over the cap');
  perform pg_temp.cfg('cooking.max_busy_seconds', '45');
  -- the bag limit
  perform pg_temp.at(a, 'uselu_selfcon');
  perform pg_temp.pantry(a, 'noodles_egg', 1);
  perform pg_temp.cfg('cooking.max_portions', '10');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('noodles_egg', 1)$q$) = 'bag_full' and pg_temp.qty(a, 'eggs') = 2, 'too many portions of one dish: refused, nothing taken');
  perform pg_temp.cfg('cooking.max_portions', '40');
  -- eating a portion restores needs (the normal Eat button: item_use)
  perform pg_temp.at(a, 'uselu_selfcon');
  update profiles set hunger = 20, energy = 50, fun = 40 where id = a;
  n := pg_temp.qty(a, 'dish_noodles_egg');
  r := item_use('dish_noodles_egg');
  perform pg_temp.assert((select hunger from profiles where id = a) = 52 and (select energy from profiles where id = a) = 52 and (select fun from profiles where id = a) = 43 and pg_temp.qty(a, 'dish_noodles_egg') = n - 1, 'eating a portion: hunger +32, energy +2, mood +3: ' || r::text);
  perform pg_temp.assert(r ->> 'message' like 'You ate Indomie and egg.%', 'the eating message: ' || (r ->> 'message'));
  perform pg_temp.assert(pg_temp.hint_of($q$select item_sell('dish_noodles_egg', 1)$q$) <> 'ok', 'a cooked portion cannot be sold');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements((select (get_my_state() -> 'inventory') from (select 1) z)) x where x ->> 'id' = 'dish_noodles_egg' and x ->> 'kind' = 'use' and (x ->> 'qty')::int = n - 1), 'the dish is in the Bag as a usable food');
  -- the Catering certificate: unlocks black soup, cooks faster
  perform pg_temp.setxp(a, 740);   -- level 6
  perform pg_temp.at(a, 'uselu_selfcon');
  perform pg_temp.pantry(a, 'black_soup', 1);
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('black_soup', 1)$q$) = 'need_cert' and pg_temp.msg_of($q$select cook_start('black_soup', 1)$q$) like '%Catering%certificate%', 'black soup without the certificate: refused');
  perform pg_temp.assert(not (select (x ->> 'cert_ok')::boolean from jsonb_array_elements(cook_overview() -> 'recipes') x where x ->> 'id' = 'black_soup'), 'overview: certificate missing');
  -- time with and without the certificate (same recipe, same pot)
  perform pg_temp.cfg('cooking.max_busy_seconds', '300');
  perform pg_temp.at(a, 'uselu_selfcon'); perform pg_temp.pantry(a, 'jollof_chicken', 1);
  v := cook_start('jollof_chicken', 1);
  v_c1 := (v ->> 'seconds')::numeric;
  insert into player_certificates (user_id, cert_id, source) values (a, 'catering', 'admin') on conflict do nothing;
  perform pg_temp.at(a, 'uselu_selfcon'); perform pg_temp.pantry(a, 'jollof_chicken', 1);
  v := cook_start('jollof_chicken', 1);
  perform pg_temp.assert((v ->> 'seconds')::numeric < v_c1 * 0.8 and (v ->> 'seconds')::numeric > v_c1 * 0.7, 'Catering certificate: 25 % faster: ' || (v ->> 'seconds') || ' vs ' || v_c1);
  perform pg_temp.assert((select (x ->> 'cert_ok')::boolean and (x ->> 'minutes')::int = 45 from jsonb_array_elements(cook_overview() -> 'recipes') x where x ->> 'id' = 'jollof_chicken') and (cook_overview() -> 'catering' ->> 'has')::boolean, 'overview shows the faster time (60 -> 45 min)');
  perform pg_temp.at(a, 'uselu_selfcon'); perform pg_temp.pantry(a, 'black_soup', 1);
  v := cook_start('black_soup', 1);
  perform pg_temp.assert((v ->> 'portions')::int = 8 and pg_temp.qty(a, 'dish_black_soup') = 8, 'with the certificate and level 6, black soup cooks: ' || v::text);
  perform pg_temp.cfg('cooking.max_busy_seconds', '45');
  -- the switch
  perform pg_temp.at(a, 'uselu_selfcon'); perform pg_temp.pantry(a, 'noodles_egg', 1);
  perform pg_temp.cfg('cooking.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('noodles_egg', 1)$q$) = 'off' and not (cook_overview() ->> 'enabled')::boolean, 'cooking switched off');
  perform pg_temp.cfg('cooking.enabled', 'true');
  -- in jail or on the road
  update profiles set jailed_until = bl_now() + interval '5 minutes' where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('noodles_egg', 1)$q$) = 'jailed', 'nobody cooks in a police cell');
  perform pg_temp.at(a, 'uselu_selfcon');
  -- hunger shows the dish as the best food for the wish chip
  update game_config set value = '100' where key = 'cooking.xp_daily_cap';
  raise notice 'ok 4: cooking';
end $$;

-- ---------- 5. the Cooking XP cap ----------
do $$
declare
  v jsonb; d uuid := pg_temp.u('d'); x0 int;
begin
  perform pg_temp.login_as('d'); perform pg_temp.at(d, 'uselu_selfcon');
  perform pg_temp.cfg('cooking.xp_daily_cap', '25');
  perform pg_temp.setxp(d, 0);
  -- a Foodie trait speeds Cooking XP up (x1.3, the normal trait multiplier): 10 base XP -> 13
  perform pg_temp.pantry(d, 'noodles_egg', 1);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 13 and bl_skill_xp(d, 'cooking') = 13, 'the Foodie trait gives x1.3 Cooking XP: ' || v::text);
  perform pg_temp.hours(24);
  update profiles set traits = '{}' where id = d;
  perform pg_temp.setxp(d, 0);
  perform pg_temp.at(d, 'uselu_selfcon');
  -- recipe xp is 10: 10, 10, then the last 5, then nothing more today
  perform pg_temp.pantry(d, 'noodles_egg', 1);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 10 and bl_skill_xp(d, 'cooking') = 10 and (v ->> 'message') like '%Cooking +10 XP.', 'first cook +10 XP: ' || v::text);
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'noodles_egg', 1);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 10 and bl_skill_xp(d, 'cooking') = 20, 'second cook +10 XP');
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'noodles_egg', 1);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 5 and bl_skill_xp(d, 'cooking') = 25 and (v -> 'xp' ->> 'capped')::boolean, 'third cook only the last 5 XP of the daily cap: ' || v::text);
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'noodles_egg', 1);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 0 and bl_skill_xp(d, 'cooking') = 25 and (v ->> 'message') like '%No more Cooking XP today%', 'fourth cook: the cap is reached, still cooks but no XP: ' || v::text);
  perform pg_temp.assert(pg_temp.qty(d, 'dish_noodles_egg') = 10, 'the portions still come when XP is capped');
  perform pg_temp.assert((cook_overview() ->> 'xp_today')::int = 25 and (cook_overview() ->> 'xp_cap')::int = 25, 'overview shows XP today and the cap');
  -- the next Benin day the cap is fresh; a big pot gives the same XP as a small one; a level-up writes the normal skill_up event
  perform pg_temp.hours(24);
  x0 := pg_temp.ev(d, 'skill_up');
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'noodles_egg', 3);
  v := cook_start('noodles_egg', 3);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 10 and bl_skill_xp(d, 'cooking') = 35, 'next day: XP flows again, a big pot gives the same XP as a small one: ' || v::text);
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'noodles_egg', 1);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'level')::int = 2 and (v -> 'xp' ->> 'up')::boolean and pg_temp.ev(d, 'skill_up') = x0 + 1, 'level 2 reached: skill_up event: ' || v::text);
  -- easy dishes give less (level 3 cooking an entry dish: 40 % of 10 = 4)
  perform pg_temp.hours(24);
  perform pg_temp.cfg('cooking.xp_daily_cap', '100');
  perform pg_temp.setxp(d, 120);
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'noodles_egg', 1);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 4 and (v -> 'xp' ->> 'easy')::boolean, 'an easy dish gives 40 % XP: ' || v::text);
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'beans_dodo', 1);
  v := cook_start('beans_dodo', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 14 and not (v -> 'xp' ->> 'easy')::boolean, 'a dish near your level gives full XP: ' || v::text);
  -- cap 0 = cooking gives no XP at all
  perform pg_temp.hours(24);
  perform pg_temp.cfg('cooking.xp_daily_cap', '0');
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'noodles_egg', 1);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 0 and bl_skill_xp(d, 'cooking') = 120 + 4 + 14, 'cap 0: no XP');
  -- the XP multiplier (double XP weekend) applies after the cap
  perform pg_temp.hours(24);
  perform pg_temp.cfg('cooking.xp_daily_cap', '25');
  perform pg_temp.cfg('skills.xp_mult', '2');
  perform pg_temp.setxp(d, 0);
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'noodles_egg', 1);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 20, 'double XP: 10 x 2 = 20: ' || v::text);
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'noodles_egg', 1); perform cook_start('noodles_egg', 1);
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'noodles_egg', 1);
  v := cook_start('noodles_egg', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 10 and bl_skill_xp(d, 'cooking') = 50, 'the cap counts base XP (25), the multiplier applies on top: ' || v::text);
  perform pg_temp.cfg('skills.xp_mult', '1');
  -- skills off: no XP, no level gates
  perform pg_temp.cfg('skills.enabled', 'false');
  perform pg_temp.setxp(d, 0);
  perform pg_temp.hours(24);
  perform pg_temp.at(d, 'uselu_selfcon'); perform pg_temp.pantry(d, 'egusi_pounded', 1);
  v := cook_start('egusi_pounded', 1);
  perform pg_temp.assert((v -> 'xp' ->> 'gain')::int = 0 and bl_skill_xp(d, 'cooking') = 0 and (v ->> 'portions')::int = 8 and (cook_overview() -> 'level') = 'null'::jsonb, 'skills off: a level 5 dish cooks at once and no XP is given: ' || v::text);
  perform pg_temp.cfg('skills.enabled', 'true');
  perform pg_temp.cfg('cooking.xp_daily_cap', '100');
  raise notice 'ok 5: XP cap';
end $$;

-- ---------- 6. sharing with a partner (couple a + b) ----------
do $$
declare
  v jsonb; a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); c uuid := pg_temp.u('c'); x0 bigint;
begin
  perform pg_temp.login_as('a');
  perform pg_temp.give(a, 'dish_jollof_chicken', 8); perform pg_temp.give(b, 'dish_jollof_chicken', 0); delete from inventory where user_id = b and item_id = 'dish_jollof_chicken';
  perform pg_temp.assert((cook_overview() -> 'partner' ->> 'id')::uuid = b, 'the overview knows the partner');
  x0 := pg_temp.ev(b, 'cook_gift');
  v := cook_share('dish_jollof_chicken', 3);
  perform pg_temp.assert(pg_temp.qty(a, 'dish_jollof_chicken') = 5 and pg_temp.qty(b, 'dish_jollof_chicken') = 3 and (v ->> 'shared_today')::int = 3, 'three portions sent: ' || v::text);
  perform pg_temp.assert(pg_temp.ev(b, 'cook_gift') = x0 + 1 and (select body from events where user_id = b and kind = 'cook_gift' order by id desc limit 1) like '3 portions of Jollof rice and chicken%', 'the partner is told');
  -- the partner can eat it
  perform pg_temp.login_as('b');
  update profiles set hunger = 10 where id = b;
  perform item_use('dish_jollof_chicken');
  perform pg_temp.assert((select hunger from profiles where id = b) between 50 and 62 and pg_temp.qty(b, 'dish_jollof_chicken') = 2, 'the partner eats a shared portion: hunger +52, now ' || (select hunger from profiles where id = b));
  perform pg_temp.login_as('a');
  -- rules
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_share('rice', 1)$q$) = 'not_a_dish', 'only cooked food can be shared');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_share('dish_jollof_chicken', 0)$q$) = 'bad_qty', 'a number is needed');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_share('dish_jollof_chicken', 6)$q$) = 'no_item', 'you cannot send more than you hold');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_share('dish_banga_starch', 1)$q$) = 'no_item', 'you cannot send what you do not have');
  perform pg_temp.cfg('cooking.share_daily_cap', '4');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_share('dish_jollof_chicken', 2)$q$) = 'share_cap' and pg_temp.msg_of($q$select cook_share('dish_jollof_chicken', 2)$q$) like '%1 more portion(s) today (limit 4 a day)%', 'daily cap on sent portions: ' || pg_temp.msg_of($q$select cook_share('dish_jollof_chicken', 2)$q$));
  perform cook_share('dish_jollof_chicken', 1);
  perform pg_temp.hours(24);
  perform pg_temp.assert((cook_share('dish_jollof_chicken', 1) ->> 'shared_today')::int = 1, 'the cap resets the next Benin day');
  perform pg_temp.cfg('cooking.share_daily_cap', '0');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_share('dish_jollof_chicken', 1)$q$) = 'off', 'sharing off');
  perform pg_temp.cfg('cooking.share_daily_cap', '20');
  perform pg_temp.cfg('cooking.max_portions', '3');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_share('dish_jollof_chicken', 1)$q$) = 'partner_full', 'the partner''s bag cannot go over the limit');
  perform pg_temp.cfg('cooking.max_portions', '40');
  -- no partner
  perform pg_temp.login_as('c');
  perform pg_temp.give(c, 'dish_noodles_egg', 2);
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_share('dish_noodles_egg', 1)$q$) = 'no_partner' and (cook_overview() -> 'partner') = 'null'::jsonb, 'without a partner nothing is sent');
  -- a break-up ends it
  update love_relationships set status = 'ended', ended_at = bl_now() where id = pg_temp.rel(a, b);
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_share('dish_jollof_chicken', 1)$q$) = 'no_partner', 'after a break-up there is no partner to send to');
  update love_relationships set status = 'couple', ended_at = null where id = pg_temp.rel(a, b);
  -- sharing is free: no ledger rows, no money moves
  perform pg_temp.assert(not exists (select 1 from ledger where user_id in (a, b) and (reason like 'cook%' or meta ->> 'item' like 'dish\_%')), 'sharing and cooking never touch money');
  raise notice 'ok 6: sharing';
end $$;

-- ---------- 7. kids: a home-cooked portion is a child's food (couple a + b) ----------
do $$
declare
  v jsonb; a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); v_c bigint; v_new bigint; b0 bigint; c kids_children; v_sp0 bigint;
begin
  perform pg_temp.login_as('a');
  perform pg_temp.pantry(a, 'noodles_egg', 1);   -- keep something in the bag while we test
  delete from inventory where user_id = a and left(item_id, 5) = 'dish_';
  -- NURSERY (from 5 days): feeding costs lunch money unless there is a cooked portion
  v_c := pg_temp.mkchild(a, b, interval '6 days', 'Nene');
  perform pg_temp.assert(pg_temp.cj(v_c) -> 'stage' ->> 'id' = 'nursery', 'a nursery child');
  update kids_children set hunger = 30, hunger_at = bl_now() where id = v_c;
  v := pg_temp.cj(v_c) -> 'actions' -> 'feed';
  perform pg_temp.assert((v ->> 'ok')::boolean and (v ->> 'cost')::bigint = 1500 and v ->> 'item' is null, 'no cooked food: the feed button costs lunch money: ' || v::text);
  b0 := pg_temp.cash(a);
  v := kids_care(v_c, 'feed');
  perform pg_temp.assert(pg_temp.cash(a) = b0 - 1500 and (v ->> 'value')::int = 80, 'lunch money paid, hunger 30 + 50 = 80');
  -- with a cooked portion in the bag
  perform pg_temp.give(a, 'dish_jollof_chicken', 2);
  update kids_children set hunger = 30, hunger_at = bl_now() where id = v_c;
  v := pg_temp.cj(v_c) -> 'actions' -> 'feed';
  perform pg_temp.assert((v ->> 'ok')::boolean and (v ->> 'cost')::bigint = 0 and v ->> 'item' = 'dish_jollof_chicken' and (v ->> 'left')::int = 2 and v ->> 'item_name' = 'Jollof rice and chicken', 'the feed button shows the cooked portion and is free: ' || v::text);
  select spent_a + spent_b into v_sp0 from kids_children where id = v_c;
  b0 := pg_temp.cash(a);
  v := kids_care(v_c, 'feed');
  perform pg_temp.assert(pg_temp.cash(a) = b0 and pg_temp.qty(a, 'dish_jollof_chicken') = 1 and v ->> 'item' = 'dish_jollof_chicken' and (v ->> 'spent')::bigint = 0, 'a cooked portion was used, no money: ' || v::text);
  perform pg_temp.assert((v ->> 'value')::int = 92, 'a home-cooked meal fills 25 % more: 30 + 50 x 1.25 = 92: ' || v::text);
  select * into c from kids_children where id = v_c;
  perform pg_temp.assert(c.spent_a + c.spent_b - v_sp0 = (select price from items where id = 'dish_jollof_chicken') and (select price from items where id = 'dish_jollof_chicken') > 0, 'the meal counts as spending on the child at its ingredient cost (the gift cap sees it)');
  -- the other parent uses their own bag
  perform pg_temp.login_as('b');
  delete from inventory where user_id = b and left(item_id, 5) = 'dish_';
  update kids_children set hunger = 30, hunger_at = bl_now() where id = v_c;
  b0 := pg_temp.cash(b);
  v := kids_care(v_c, 'feed');
  perform pg_temp.assert(pg_temp.cash(b) = b0 - 1500 and v ->> 'item' is null, 'parent b has no cooked food: pays lunch money');
  perform pg_temp.login_as('a');
  -- the setting
  perform pg_temp.cfg('cooking.kid_meal_enabled', 'false');
  update kids_children set hunger = 30, hunger_at = bl_now() where id = v_c;
  b0 := pg_temp.cash(a);
  v := kids_care(v_c, 'feed');
  perform pg_temp.assert(pg_temp.cash(a) = b0 - 1500 and pg_temp.qty(a, 'dish_jollof_chicken') = 1, 'kid meals switched off: lunch money again, the portion stays');
  perform pg_temp.cfg('cooking.kid_meal_enabled', 'true');
  perform pg_temp.cfg('cooking.kid_meal_boost_pct', '0');
  update kids_children set hunger = 30, hunger_at = bl_now() where id = v_c;
  v := kids_care(v_c, 'feed');
  perform pg_temp.assert((v ->> 'value')::int = 80 and pg_temp.qty(a, 'dish_jollof_chicken') = 0, 'boost 0: the normal 50 points');
  perform pg_temp.cfg('cooking.kid_meal_boost_pct', '25');
  -- a newborn still needs formula: a cooked portion is not baby food
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  perform pg_temp.give(a, 'dish_jollof_chicken', 3);
  v_new := pg_temp.mkchild(a, b, interval '2 hours', 'Nena');
  update kids_children set hunger = 30, hunger_at = bl_now() where id = v_new;
  delete from inventory where user_id = a and item_id in ('kid_formula', 'kid_cereal'); delete from kids_charges where user_id = a;
  v := pg_temp.cj(v_new) -> 'actions' -> 'feed';
  perform pg_temp.assert(not (v ->> 'ok')::boolean and v ->> 'code' = 'no_item' and v ->> 'item' = 'kid_formula', 'a newborn cannot be fed jollof: ' || v::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_new, 'feed')) = 'no_item' and pg_temp.qty(a, 'dish_jollof_chicken') = 3, 'refused, the portions are kept');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_new;
  raise notice 'ok 7: kids';
end $$;

-- ---------- 8. admin editors ----------
do $$
declare
  v jsonb; a uuid := pg_temp.u('a'); n int;
begin
  perform pg_temp.assert(bl_admin_table_spec('cook_recipes') is not null and bl_admin_table_spec('cook_ingredients') is not null
                         and bl_admin_table_spec('cook_ingredients') -> 'pk' = '["recipe_id","item_id"]'::jsonb and (bl_admin_table_spec('cook_recipes') -> 'cols') ? 'min_level' and (bl_admin_table_spec('cook_recipes') -> 'cols') ? 'cert_id', 'Content editors exist for recipes and ingredients');
  perform pg_temp.login_as('adm');
  perform pg_temp.assert(jsonb_array_length(admin_table_rows('cook_recipes')) = 9 and jsonb_array_length(admin_table_rows('cook_ingredients')) = (select count(*) from cook_ingredients), 'the editors list the rows');
  -- ingredients are ordinary items: the Items editor changes the price, the day price follows
  perform pg_temp.assert((admin_row_upsert('items', '{"id":"rice","price":1000}') -> 'row' ->> 'price')::int = 1000 and pg_temp.price('rice', 'edo_fresh_supermarket') = 1300, 'an admin changes the base price of rice in Content -> Items (supermarket +30 % = 1300)');
  perform admin_row_upsert('items', '{"id":"rice","price":900}');
  -- a recipe edit moves the dish item with it
  perform admin_row_upsert('cook_recipes', '{"id":"noodles_egg","hunger":40,"mood":5}');
  perform pg_temp.assert((select effects ->> 'hunger' from items where id = 'dish_noodles_egg') = '40' and (select effects ->> 'fun' from items where id = 'dish_noodles_egg') = '5', 'editing a recipe updates the dish: eat it and get the new numbers');
  perform admin_row_upsert('cook_recipes', '{"id":"noodles_egg","hunger":32,"mood":3}');
  -- ingredient amounts
  perform admin_row_upsert('cook_ingredients', '{"recipe_id":"noodles_egg","item_id":"eggs","qty":4}');
  perform pg_temp.assert((select price from items where id = 'dish_noodles_egg') = round((2 * 350 + 4 * 250) / 2.0 / 10) * 10, 'the dish value follows the ingredient cost');
  perform pg_temp.login_as('a'); perform pg_temp.at(a, 'uselu_selfcon'); perform pg_temp.give(a, 'instant_noodles', 2); perform pg_temp.give(a, 'eggs', 3);
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('noodles_egg', 1)$q$) = 'no_ingredients', 'the new amount (4 eggs) is checked by the server');
  perform pg_temp.login_as('adm');
  perform admin_row_upsert('cook_ingredients', '{"recipe_id":"noodles_egg","item_id":"eggs","qty":0}');
  perform pg_temp.login_as('a');
  perform pg_temp.assert((cook_start('noodles_egg', 1) ->> 'portions')::int = 2 and pg_temp.qty(a, 'eggs') = 3, 'amount 0 = the ingredient is not used any more');
  perform pg_temp.login_as('adm');
  perform admin_row_upsert('cook_ingredients', '{"recipe_id":"noodles_egg","item_id":"eggs","qty":2}');
  -- a new recipe
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('cook_recipes', '{"id":"fried_yam_x","name":"Yam and egg","emoji":"🍳","portions":2,"game_minutes":10,"hunger":30,"energy":2,"mood":4,"xp":8,"min_level":1,"sort":5}')$q$) = 'ok', 'an admin adds a recipe');
  perform admin_row_upsert('cook_ingredients', '{"recipe_id":"fried_yam_x","item_id":"yam","qty":1}');
  perform admin_row_upsert('cook_ingredients', '{"recipe_id":"fried_yam_x","item_id":"eggs","qty":2}');
  perform pg_temp.assert(exists (select 1 from items where id = 'dish_fried_yam_x' and category = 'food' and not sellable and (effects ->> 'hunger')::numeric = 30), 'the new dish item exists');
  perform pg_temp.login_as('a'); perform pg_temp.at(a, 'uselu_selfcon'); perform pg_temp.give(a, 'yam', 1); perform pg_temp.give(a, 'eggs', 2);
  perform pg_temp.assert((cook_start('fried_yam_x', 1) ->> 'portions')::int = 2 and pg_temp.qty(a, 'dish_fried_yam_x') = 2, 'players can cook the new recipe at once');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(cook_overview() -> 'recipes') x where x ->> 'id' = 'fried_yam_x'), 'and it shows in the kitchen');
  -- switching a recipe off
  perform pg_temp.login_as('adm');
  perform admin_row_upsert('cook_recipes', '{"id":"fried_yam_x","active":false}');
  perform pg_temp.login_as('a'); perform pg_temp.at(a, 'uselu_selfcon');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('fried_yam_x', 1)$q$) = 'no_recipe' and not exists (select 1 from jsonb_array_elements(cook_overview() -> 'recipes') x where x ->> 'id' = 'fried_yam_x'), 'a recipe that is off is hidden and refused');
  -- a recipe needing a certificate
  perform pg_temp.login_as('adm');
  perform admin_row_upsert('cook_recipes', '{"id":"noodles_egg","cert_id":"ict"}');
  perform pg_temp.login_as('a'); perform pg_temp.pantry(a, 'noodles_egg', 1); perform pg_temp.at(a, 'uselu_selfcon');
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_start('noodles_egg', 1)$q$) = 'need_cert', 'an admin can lock any dish behind a certificate');
  perform pg_temp.login_as('adm');
  perform admin_row_upsert('cook_recipes', '{"id":"noodles_egg","cert_id":null}');
  -- the settings are editable and clamped by their range
  perform pg_temp.assert((admin_row_upsert('cook_recipes', '{"id":"noodles_egg","xp":12}') -> 'row' ->> 'xp')::int = 12, 'XP is editable');
  perform admin_row_upsert('cook_recipes', '{"id":"noodles_egg","xp":10}');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('cook_recipes', '{"id":"noodles_egg","hunger":500}')$q$) = 'bad_value', 'a silly number is refused (hunger 500)');
  -- players cannot
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('cook_recipes', '{"id":"noodles_egg","hunger":99}')$q$) = 'not_admin', 'players cannot edit recipes');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('cook_ingredients', '{"recipe_id":"noodles_egg","item_id":"eggs","qty":0}')$q$) = 'not_admin', 'players cannot edit ingredients');
  raise notice 'ok 8: admin editors';
end $$;

-- ---------- 9. grants, RLS, no profiles changes ----------
do $$
declare v text; t text;
begin
  foreach v in array array['grocery_prices()', 'cook_overview()', 'cook_start(text,integer)', 'cook_share(text,integer)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || v, 'execute'), 'anon cannot run ' || v);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || v, 'execute'), 'authenticated can run ' || v);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v)::regprocedure) and exists (select 1 from pg_proc p where p.oid = ('public.' || v)::regprocedure and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')), v || ' is security definer with a search_path');
  end loop;
  select string_agg(p.proname, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like 'bl\_cook\_%'
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'));
  perform pg_temp.assert(v is null, 'every bl_cook helper is private: ' || coalesce(v, ''));
  perform pg_temp.assert((select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname like 'bl\_cook\_%') >= 11, 'the helpers exist');
  select string_agg(t2, ', ') into v from unnest(array['cook_recipes', 'cook_ingredients', 'cook_daily']) t2
   where not (select relrowsecurity from pg_class where oid = ('public.' || t2)::regclass)
      or has_table_privilege('authenticated', 'public.' || t2, 'select') or has_table_privilege('anon', 'public.' || t2, 'select')
      or has_table_privilege('authenticated', 'public.' || t2, 'insert') or has_table_privilege('authenticated', 'public.' || t2, 'update') or has_table_privilege('authenticated', 'public.' || t2, 'delete');
  perform pg_temp.assert(v is null, 'new tables: RLS on, no client grants: ' || coalesce(v, ''));
  perform pg_temp.assert(not exists (select 1 from pg_constraint where conrelid in ('public.cook_recipes'::regclass, 'public.cook_ingredients'::regclass, 'public.cook_daily'::regclass) and contype = 'f' and confrelid = 'public.profiles'::regclass), 'no foreign key to profiles (it deadlocked a deploy once)');
  perform pg_temp.assert(not exists (select 1 from pg_trigger where tgrelid = 'public.profiles'::regclass and not tgisinternal and pg_get_triggerdef(oid) ilike '%cook%'), 'no trigger on profiles for cooking');
  perform pg_temp.assert(not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name like 'cook%'), 'profiles has no cooking column');
  -- RLS really blocks a signed-in player
  perform pg_temp.login_as('a');
  set local role authenticated;
  begin
    perform count(*) from public.cook_recipes;
    reset role;
    perform pg_temp.assert(false, 'a player could read cook_recipes directly');
  exception when insufficient_privilege then
    reset role;
  end;
  begin
    set local role authenticated;
    perform count(*) from public.cook_daily;
    reset role;
    perform pg_temp.assert(false, 'a player could read cook_daily directly');
  exception when insufficient_privilege then
    reset role;
  end;
  -- a player can only cook for themselves and only read their own bag
  perform pg_temp.assert(pg_temp.hint_of($q$select cook_share('dish_jollof_chicken', 1)$q$) <> 'not_authenticated', 'RPCs work for a signed-in player');
  -- the patched live functions kept their markers
  perform pg_temp.assert(pg_get_functiondef('public.bl_shop_price(items, text)'::regprocedure) like '%bl_cook_price%' and pg_get_functiondef('public.shop_list(text)'::regprocedure) like '%bl_cook_yesterday%'
                         and pg_get_functiondef('public.kids_care(bigint, text)'::regprocedure) like '%dish_%' and pg_get_functiondef('public.bl_kids_can(kids_children, text, timestamptz, uuid)'::regprocedure) like '%bl_cook_kid_dish%'
                         and pg_get_functiondef('public.bl_admin_table_spec(text)'::regprocedure) like '%cook_recipes%', 'the guarded patches are in place');
  raise notice 'ok 9: grants, RLS, profiles untouched';
end $$;

-- ---------- 10. the read-only RPCs really are read-only (PostgREST runs them in a read-only transaction) ----------
do $$
declare v jsonb;
begin
  perform pg_temp.login_as('a');
  begin
    set local transaction_read_only = on;
    v := cook_overview();
    perform pg_temp.assert(jsonb_array_length(v -> 'recipes') >= 9, 'cook_overview works read-only');
    v := grocery_prices();
    perform pg_temp.assert(jsonb_array_length(v -> 'items') >= 26, 'grocery_prices works read-only');
    v := shop_list('oba_market');
    perform pg_temp.assert(jsonb_array_length(v -> 'items') > 0, 'shop_list works read-only');
    raise exception 'READONLY_OK';
  exception when others then
    if sqlerrm <> 'READONLY_OK' then raise; end if;
  end;
  perform pg_temp.assert(current_setting('transaction_read_only') = 'off', 'the sub-transaction was rolled back');
  raise notice 'ok 10: read-only RPCs';
end $$;
