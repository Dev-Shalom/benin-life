-- Benin Life — V1-4 "Spend money": NPC shops, the Bag (inventory), ChopNow delivery, weekly rent ON.
-- docs/SHOPS.md is the spec. Safe on a non-empty DB and idempotent:
-- * items are inserted with `on conflict do nothing` (admin price edits survive a re-run); the two
--   starter items (laptop, tokunbo_car) are only touched while they still hold their seed values;
-- * config rows use `on conflict do nothing`;
-- * 'shop' is appended to location actions only where it is missing;
-- * rent.enabled is flipped to true ONCE: only while it still holds the seeded false and no admin
--   has touched it (updated_by is null). A trigger rolls every overdue rent day forward whenever
--   rent.enabled goes false -> true, so switching it on (now or later from the admin page) never
--   back-charges the weeks it was off.
--
-- Item effects (items.effects jsonb):
-- * need keys (hunger, energy, hygiene, fun, social, health, stress, bladder): "use" items. item_use
--   consumes one and applies them through bl_adjust_needs.
-- * {"boost": {"<activity id>": {<need deltas>}}}: consumed automatically (one each) when the player
--   does that activity, adding the deltas (soap makes a home bath better). item_use refuses them.
-- * {} : "keep" items (laptop, car, souvenir). Owning them is the point (career requirement, car mode).

-- ---------------------------------------------------------------------
-- 1. Config
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('shop.max_qty_per_buy', '10', 'shop', 'Max items per purchase',
 'The most of one item a player can buy (or order on ChopNow) in one go.', 'number', 1, 99),
('shop.delivery_markup_pct', '40', 'shop', 'ChopNow delivery markup',
 'ChopNow (phone food app) price = shop price plus this percent (at least the minimum delivery fee), rounded up to ₦10.', 'percent', 0, 300),
('shop.delivery_min_fee', '200', 'shop', 'ChopNow minimum delivery fee',
 'The smallest amount ChopNow adds on top of the shop price of each item.', 'naira', 0, 5000),
('shop.sell_scenes', '"market"', 'shop', 'Where players can sell items',
 'Comma-separated location scenes where items can be sold back for their resale percent (e.g. market).', 'text', null, null),
('rent.owed_sleep_energy_pct', '60', 'rent', 'Sleep energy while owing rent',
 'While a player owes rent, sleeping or napping at home gives only this percent of the usual energy (the landlord keeps knocking). 100 = no penalty.', 'percent', 0, 100),
('rent.owed_sleep_activities', '"sleep,nap"', 'rent', 'Activities hit by the rent penalty',
 'Comma-separated activity ids whose energy gain is cut while rent is owed.', 'text', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. Where things are sold: give the selling places a Shop tab
-- ---------------------------------------------------------------------
update public.locations set actions = array_append(actions, 'shop')
 where id in ('mama_osas_buka', 'back_gate_joint',                          -- bukas: packs to go
              'uselu_park', 'oluku_park', 'ramat_park', 'aduwawa_park',     -- motor park hawkers
              'ring_road_pos', 'new_benin_pos', 'sapele_pos',               -- PoS stands: credit + data
              'wifi_joint', 'bronze_tech_hub',                              -- laptops + data
              'ubth', 'mercy_clinic')                                       -- pharmacy counter
   and not ('shop' = any (actions));

-- ---------------------------------------------------------------------
-- 3. Items (admin-editable rows). Prices are balanced against docs/CAREERS.md pay (see docs/SHOPS.md).
-- ---------------------------------------------------------------------
insert into public.items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort) values
-- drinks
('pure_water', 'Pure water sachet', 'drink', 50,
 'Ice-cold sachet water from the cooler. Bite the corner and drink.',
 '{"stress": -2, "energy": 1, "bladder": -8}',
 '{oba_market,new_benin_market,uselu_market,oregbeni_market,ekiosa_market,santana_market,uselu_park,oluku_park,ramat_park,aduwawa_park,mama_osas_buka,back_gate_joint}', false, 0, '💧', 100),
('bottled_water', 'Bottled water', 'drink', 250,
 'Sealed 75cl bottle. For when you want to feel a bit posh.',
 '{"stress": -3, "energy": 2, "bladder": -10}',
 '{oba_market,new_benin_market,uselu_market,oregbeni_market,ekiosa_market,santana_market,uselu_park,ramat_park,ubth,mercy_clinic,bronze_tech_hub,wifi_joint}', false, 0, '🥤', 110),
('zobo', 'Chilled zobo', 'drink', 300,
 'Hibiscus drink with ginger and pineapple, served cold in a reused bottle.',
 '{"fun": 3, "stress": -3, "bladder": -8}',
 '{oba_market,new_benin_market,uselu_market,ekiosa_market,santana_market,mama_osas_buka,back_gate_joint}', false, 0, '🍹', 120),
('malt_drink', 'Malt drink', 'drink', 500,
 'Sweet, cold malt. Small energy, big satisfaction.',
 '{"energy": 6, "fun": 3, "bladder": -10}',
 '{oba_market,new_benin_market,uselu_market,oregbeni_market,ekiosa_market,santana_market,mama_osas_buka,back_gate_joint,uselu_park,oluku_park,ramat_park,aduwawa_park}', false, 0, '🍺', 130),
('roll_and_soda', 'Sausage roll + soda', 'food', 600,
 'The classic go-slow lunch: a sausage roll and a cold apple soda from the hawker.',
 '{"hunger": 14, "fun": 4, "bladder": -8}',
 '{uselu_park,oluku_park,ramat_park,aduwawa_park,ring_road_pos,new_benin_pos,sapele_pos,oba_market,uselu_market}', false, 0, '🥐', 140),
-- food
('puff_puff', 'Puff-puff (5 balls)', 'food', 300,
 'Hot, sweet dough balls fried in front of you. Hard to stop at five.',
 '{"hunger": 12, "fun": 3}',
 '{oba_market,new_benin_market,uselu_market,oregbeni_market,ekiosa_market,santana_market,uselu_park,oluku_park,ramat_park,aduwawa_park,back_gate_joint}', false, 0, '🍩', 200),
('garri_groundnut', 'Garri + groundnut', 'food', 300,
 'Soaked garri with cold water, sugar and roasted groundnut. Student power food.',
 '{"hunger": 20, "bladder": -6}',
 '{oba_market,new_benin_market,uselu_market,oregbeni_market,ekiosa_market,santana_market,back_gate_joint}', false, 0, '🥣', 210),
('boli_groundnut', 'Boli + groundnut', 'food', 400,
 'Roasted plantain off the roadside grill, with a twist of groundnut.',
 '{"hunger": 18, "fun": 2}',
 '{oba_market,uselu_market,ekiosa_market,santana_market,uselu_park,oluku_park,ramat_park,aduwawa_park}', false, 0, '🍌', 220),
('noodles_pack', 'Noodles pack', 'food', 400,
 'Instant noodles with the seasoning sachet. Quick, filling, not much else.',
 '{"hunger": 18}',
 '{oba_market,new_benin_market,uselu_market,oregbeni_market,ekiosa_market,santana_market,back_gate_joint,wifi_joint}', false, 0, '🍜', 230),
('suya_stick', 'Suya stick', 'food', 500,
 'Spicy grilled beef on a stick with onions and yaji. Watch the pepper.',
 '{"hunger": 15, "fun": 5}',
 '{uselu_park,oluku_park,ramat_park,aduwawa_park,mama_osas_buka,back_gate_joint,new_benin_market,oregbeni_market}', false, 0, '🍢', 240),
('bread_egg', 'Bread + fried egg', 'food', 700,
 'Agege bread with a fried egg and a touch of pepper. A proper breakfast.',
 '{"hunger": 25, "energy": 2}',
 '{oba_market,new_benin_market,uselu_market,oregbeni_market,ekiosa_market,santana_market,uselu_park,ramat_park,back_gate_joint}', false, 0, '🍞', 250),
('owo_pack', 'Owo soup + starch pack', 'food', 1800,
 'Benin''s own: owo soup with starch, wrapped to go from the buka.',
 '{"hunger": 50, "fun": 5, "social": 2}',
 '{mama_osas_buka,back_gate_joint,oba_market,ekiosa_market}', false, 0, '🍲', 260),
('jollof_pack', 'Jollof rice + chicken pack', 'food', 2000,
 'Party-style smoky jollof with a piece of chicken and plantain, in a takeaway pack.',
 '{"hunger": 50, "fun": 8}',
 '{mama_osas_buka,back_gate_joint,new_benin_market,uselu_market,santana_market}', false, 0, '🍛', 270),
-- hygiene + health
('soap', 'Bar of soap', 'hygiene', 300,
 'A good bathing soap. Used up on your next bath at home for a much fresher feeling.',
 '{"boost": {"bathe": {"hygiene": 20, "fun": 2}}}',
 '{oba_market,new_benin_market,uselu_market,oregbeni_market,ekiosa_market,santana_market,fresh_cut_salon}', true, 30, '🧼', 300),
('toothpaste', 'Toothpaste + brush', 'hygiene', 400,
 'Brush your teeth anywhere. Fresh breath, more confidence.',
 '{"hygiene": 10, "social": 3}',
 '{oba_market,new_benin_market,uselu_market,oregbeni_market,ekiosa_market,santana_market,fresh_cut_salon}', false, 0, '🪥', 310),
('pain_relief', 'Paracetamol strip', 'health', 300,
 'Ten tablets for headache and body pain. Take with water.',
 '{"health": 4, "stress": -6}',
 '{ubth,mercy_clinic,oba_market,new_benin_market,uselu_market}', false, 0, '💊', 320),
-- phone
('airtime', 'Airtime top-up (₦500)', 'phone', 500,
 'Recharge card from the PoS stand. Call your people and catch up.',
 '{"social": 12, "fun": 2}',
 '{ring_road_pos,new_benin_pos,sapele_pos,oba_market,new_benin_market,uselu_market,uselu_park,wifi_joint}', false, 0, '📶', 400),
('data_bundle', 'Data bundle (1.5GB)', 'phone', 1000,
 'A week of scrolling, memes and videos. Good for your mood.',
 '{"fun": 15, "social": 5}',
 '{ring_road_pos,new_benin_pos,sapele_pos,wifi_joint,bronze_tech_hub}', false, 0, '📱', 410),
-- keepsakes
('bronze_mini_head', 'Mini bronze head', 'souvenir', 8000,
 'A small cast-bronze head from the Igun Street guild. Pride of Benin on your shelf.',
 '{}',
 '{igun_street}', true, 60, '🗿', 600)
on conflict (id) do nothing;

-- The laptop (starter item, R3a/P1-ORIGIN placeholder ₦250,000) becomes a real shop item. Only while it
-- still holds the seed price, so an admin's price is never overwritten.
update public.items
   set price = 45000,
       description = 'Clean UK-used laptop. The battery lasts about two hours. Tech jobs from Junior Dev up need one.',
       sold_at = '{bronze_tech_hub,wifi_joint}',
       resale_pct = 40,
       icon = '💻'
 where id = 'laptop' and price = 250000;
update public.items set icon = '💻' where id = 'laptop' and icon = 'laptop';
update public.items set icon = '🚗' where id = 'tokunbo_car' and icon = 'car';
-- The Nepo starter car is free, so selling it at the market would print ₦1.25M. Not sellable until a
-- Cars app/dealer exists (only while it still holds its seed values).
update public.items set sellable = false
 where id = 'tokunbo_car' and sellable and price = 2500000 and resale_pct = 50;

-- ---------------------------------------------------------------------
-- 4. Helpers (internal)
-- ---------------------------------------------------------------------
-- Need keys an item's effects may change directly.
create or replace function public.bl_need_keys() returns text[]
language sql immutable as $$
  select array['hunger','energy','hygiene','fun','social','health','stress','bladder']::text[]
$$;

-- 'use' (has need deltas), 'boost' (consumed by an activity) or 'keep' (owned, never used up).
create or replace function public.bl_item_kind(p_effects jsonb) returns text
language sql immutable set search_path = public as $$
  select case
    when p_effects ?| bl_need_keys() then 'use'
    when jsonb_typeof(p_effects->'boost') = 'object' then 'boost'
    else 'keep' end
$$;

-- Only the need deltas of an effects object.
create or replace function public.bl_need_effects(p_effects jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
    from jsonb_each(coalesce(p_effects, '{}'::jsonb)) as e(k, v)
   where k = any (bl_need_keys()) and jsonb_typeof(v) = 'number'
$$;

-- Sum two need-delta objects key by key.
create or replace function public.bl_effects_add(a jsonb, b jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select coalesce(jsonb_object_agg(k, to_jsonb(s)), '{}'::jsonb) from (
    select k, sum(v::numeric) as s from (
      select k, v #>> '{}' as v from jsonb_each(coalesce(a, '{}'::jsonb)) as x(k, v) where jsonb_typeof(v) = 'number'
      union all
      select k, v #>> '{}' from jsonb_each(coalesce(b, '{}'::jsonb)) as y(k, v) where jsonb_typeof(v) = 'number'
    ) u group by k
  ) t
$$;

-- What a market trader pays for one item (rounded down to ₦10).
create or replace function public.bl_resale_price(p_item public.items) returns bigint
language sql immutable as $$
  select case when p_item.sellable
              then (floor(p_item.price * greatest(0, least(100, p_item.resale_pct)) / 100.0 / 10) * 10)::bigint
              else 0 end
$$;

-- ChopNow price of one item: shop price + max(min fee, markup %), rounded up to ₦10.
create or replace function public.bl_delivery_price(p_price bigint) returns bigint
language plpgsql stable set search_path = public as $$
begin
  return (ceil((p_price + greatest(bl_cfg('shop.delivery_min_fee'),
                                   p_price * bl_cfg('shop.delivery_markup_pct') / 100.0)) / 10.0) * 10)::bigint;
end $$;

create or replace function public.bl_csv_has(p_csv text, p_val text) returns boolean
language sql immutable as $$
  select p_val = any (select btrim(x) from unnest(string_to_array(coalesce(p_csv, ''), ',')) x)
$$;

-- Can the player sell at this location? (scene listed in shop.sell_scenes)
create or replace function public.bl_can_sell_at(p_location text) returns boolean
language plpgsql stable set search_path = public as $$
declare v_scene text;
begin
  select scene into v_scene from locations where id = p_location;
  return v_scene is not null and bl_csv_has(bl_cfg_text('shop.sell_scenes'), v_scene);
end $$;

-- Add (or remove, negative) items in the bag; rows at 0 are deleted.
create or replace function public.bl_give_item(p_uid uuid, p_item text, p_qty int) returns int
language plpgsql set search_path = public as $$
declare v_qty int;
begin
  insert into inventory (user_id, item_id, qty) values (p_uid, p_item, greatest(p_qty, 0))
  on conflict (user_id, item_id) do update set qty = inventory.qty + p_qty
  returning qty into v_qty;
  if v_qty < 0 then
    raise exception 'You don''t have that many.' using errcode = 'P0001', hint = 'no_item';
  end if;
  if v_qty = 0 then delete from inventory where user_id = p_uid and item_id = p_item; end if;
  return v_qty;
end $$;

-- Item row or a clear error.
create or replace function public.bl_item(p_item text) returns public.items
language plpgsql stable set search_path = public as $$
declare it items;
begin
  select * into it from items where id = p_item;
  if not found then
    raise exception 'That item doesn''t exist.' using errcode = 'P0001', hint = 'no_item';
  end if;
  return it;
end $$;

create or replace function public.bl_check_qty(p_qty int) returns void
language plpgsql stable set search_path = public as $$
declare v_max int := bl_cfg('shop.max_qty_per_buy')::int;
begin
  if p_qty is null or p_qty < 1 or p_qty > v_max then
    raise exception 'Pick a quantity from 1 to %.', v_max using errcode = 'P0001', hint = 'bad_qty';
  end if;
end $$;

-- Bag block for get_my_state (pure read).
create or replace function public.bl_inventory_info(p_uid uuid) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', it.id, 'name', it.name, 'category', it.category, 'icon', it.icon, 'qty', i.qty,
           'price', it.price, 'description', it.description, 'effects', it.effects,
           'kind', bl_item_kind(it.effects), 'sellable', it.sellable, 'resale_price', bl_resale_price(it))
         order by it.sort, it.id), '[]'::jsonb)
    from inventory i join items it on it.id = i.item_id
   where i.user_id = p_uid and i.qty > 0
$$;

-- Turning rent on never back-charges: every overdue rent day rolls forward to the next one.
create or replace function public.bl_rent_switch_trigger() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.key = 'rent.enabled' and new.value = 'true'::jsonb and old.value is distinct from 'true'::jsonb then
    update profiles set rent_due_at = bl_rent_due_after(bl_now(), 0)
     where rent_due_at is not null and rent_due_at <= bl_now();
  end if;
  return new;
end $$;

drop trigger if exists game_config_rent_switch on public.game_config;
create trigger game_config_rent_switch after update on public.game_config
  for each row when (new.key = 'rent.enabled') execute function public.bl_rent_switch_trigger();

-- ---------------------------------------------------------------------
-- 5. RPCs
-- ---------------------------------------------------------------------
-- Items sold at a place (default: where the player is). Read-only.
create or replace function public.shop_list(p_location text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_me  profiles;
  l     locations;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  l := bl_location(coalesce(p_location, v_me.location_id));
  return jsonb_build_object(
    'location', jsonb_build_object('id', l.id, 'name', l.name, 'scene', l.scene),
    'here', v_me.location_id = l.id and v_me.travel_to is null,
    'sell_here', bl_can_sell_at(l.id),
    'cash', v_me.cash,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', it.id, 'name', it.name, 'category', it.category, 'price', it.price,
               'description', it.description, 'effects', it.effects, 'icon', it.icon,
               'kind', bl_item_kind(it.effects), 'sellable', it.sellable, 'resale_price', bl_resale_price(it),
               'owned', coalesce((select qty from inventory where user_id = v_uid and item_id = it.id), 0),
               'affordable', v_me.cash >= it.price)
             order by it.sort, it.id)
        from items it where l.id = any (it.sold_at)), '[]'::jsonb));
end $$;

-- Buy p_qty of an item at the shop where you stand. Cash only.
create or replace function public.shop_buy(p_item text, p_qty int default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  it      items;
  l       locations;
  v_total bigint;
  v_owned int;
  v_where text;
  v_msg   text;
begin
  perform bl_assert_free(v_me);
  it := bl_item(p_item);
  perform bl_check_qty(p_qty);
  l := bl_location(v_me.location_id);
  if not (l.id = any (it.sold_at)) then
    select string_agg(x.name, ', ' order by x.sort) into v_where
      from (select name, sort from locations where id = any (it.sold_at) order by sort limit 3) x;
    raise exception '% is not sold here.%', it.name,
      case when v_where is null then ' It is not sold anywhere right now.' else ' Try ' || v_where || '.' end
      using errcode = 'P0001', hint = 'not_sold_here';
  end if;
  v_total := it.price * p_qty;
  if v_total > v_me.cash then
    raise exception 'Not enough cash. % costs % and you have % on you.',
      case when p_qty > 1 then p_qty || ' × ' || it.name else it.name end, bl_naira(v_total), bl_naira(v_me.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  if v_total > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_total, 'shop',
                         jsonb_build_object('item', it.id, 'qty', p_qty, 'location', l.id));
  end if;
  v_owned := bl_give_item(v_me.id, it.id, p_qty);
  v_msg := 'You bought ' || case when p_qty > 1 then p_qty || ' × ' else '' end || it.name
           || ' for ' || bl_naira(v_total) || '. It''s in your Bag.';
  if l.scene = 'market' then v_msg := v_msg || ' "Thank you o, come back again!"'; end if;
  return jsonb_build_object('message', v_msg, 'item', it.id, 'qty', p_qty, 'owned', v_owned,
                            'spent', v_total, 'cash', v_me.cash - v_total);
end $$;

-- Eat, drink or use one item from the Bag. Instant.
create or replace function public.item_use(p_item text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  it     items;
  v_have int;
  v_kind text;
  v_eff  jsonb;
  v_left int;
  v_act  text;
begin
  perform bl_assert_free(v_me);
  it := bl_item(p_item);
  select qty into v_have from inventory where user_id = v_me.id and item_id = it.id;
  if coalesce(v_have, 0) < 1 then
    raise exception 'You don''t have % in your Bag.', it.name using errcode = 'P0001', hint = 'no_item';
  end if;
  v_kind := bl_item_kind(it.effects);
  if v_kind = 'boost' then
    select string_agg(lower(coalesce(a.name, k)), ' or ') into v_act
      from jsonb_object_keys(it.effects->'boost') k left join activities a on a.id = k;
    raise exception '% is used up automatically when you do "%" at home.', it.name, v_act
      using errcode = 'P0001', hint = 'use_with_activity';
  elsif v_kind = 'keep' then
    raise exception 'You don''t use % up. Owning it is enough.', it.name using errcode = 'P0001', hint = 'not_usable';
  end if;
  v_eff := bl_need_effects(it.effects);
  perform bl_adjust_needs(v_me.id, v_eff);
  v_left := bl_give_item(v_me.id, it.id, -1);
  return jsonb_build_object(
    'message', case it.category when 'food' then 'You ate ' when 'drink' then 'You drank ' else 'You used ' end
               || it.name || '.' || case when v_left > 0 then ' ' || v_left || ' left.' else '' end,
    'item', it.id, 'effects', v_eff, 'left', v_left);
end $$;

-- Sell items back at a market for their resale price.
create or replace function public.item_sell(p_item text, p_qty int default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  it      items;
  v_have  int;
  v_each  bigint;
  v_total bigint;
  v_left  int;
begin
  perform bl_assert_free(v_me);
  it := bl_item(p_item);
  if p_qty is null or p_qty < 1 then
    raise exception 'Pick how many to sell.' using errcode = 'P0001', hint = 'bad_qty';
  end if;
  if not bl_can_sell_at(v_me.location_id) then
    raise exception 'You can only sell things at a market.' using errcode = 'P0001', hint = 'cant_sell_here';
  end if;
  v_each := bl_resale_price(it);
  if not it.sellable or v_each <= 0 then
    raise exception 'Nobody at the market will buy % from you.', it.name using errcode = 'P0001', hint = 'not_sellable';
  end if;
  select qty into v_have from inventory where user_id = v_me.id and item_id = it.id;
  if coalesce(v_have, 0) < p_qty then
    raise exception 'You only have % × % in your Bag.', coalesce(v_have, 0), it.name using errcode = 'P0001', hint = 'no_item';
  end if;
  v_total := v_each * p_qty;
  v_left := bl_give_item(v_me.id, it.id, -p_qty);
  perform bl_add_money(v_me.id, 'cash', v_total, 'shop_sell',
                       jsonb_build_object('item', it.id, 'qty', p_qty, 'location', v_me.location_id));
  return jsonb_build_object(
    'message', 'You sold ' || case when p_qty > 1 then p_qty || ' × ' else '' end || it.name || ' for '
               || bl_naira(v_total) || '. "Na small money o, but we don do business."',
    'item', it.id, 'qty', p_qty, 'earned', v_total, 'left', v_left);
end $$;

-- ChopNow menu: every food and drink sold somewhere, at delivery prices. Read-only.
create or replace function public.food_menu() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles;
begin
  select * into v_me from profiles where id = v_uid;
  return jsonb_build_object(
    'markup_pct', bl_cfg('shop.delivery_markup_pct'),
    'min_fee', bl_cfg('shop.delivery_min_fee'),
    'cash', coalesce(v_me.cash, 0), 'bank', coalesce(v_me.bank, 0),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', it.id, 'name', it.name, 'category', it.category, 'icon', it.icon,
               'description', it.description, 'effects', it.effects, 'shop_price', it.price,
               'price', bl_delivery_price(it.price),
               'owned', coalesce((select qty from inventory where user_id = v_uid and item_id = it.id), 0))
             order by it.sort, it.id)
        from items it
       where it.category in ('food', 'drink') and cardinality(it.sold_at) > 0
         and bl_item_kind(it.effects) = 'use'), '[]'::jsonb));
end $$;

-- Order food from anywhere: delivery price, paid by transfer (bank) first, the rest in cash on delivery.
-- Lands straight in the Bag. Works while busy or on the road; not in a cell or a hospital bed.
create or replace function public.food_order(p_item text, p_qty int default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  it      items;
  v_now   timestamptz := bl_now();
  v_each  bigint;
  v_total bigint;
  v_bank  bigint;
  v_cash  bigint;
  v_owned int;
  v_meta  jsonb;
begin
  if v_me.jailed_until is not null and v_me.jailed_until > v_now then
    raise exception 'Delivery riders don''t come to police cells.' using errcode = 'P0001', hint = 'jailed';
  end if;
  if v_me.hospitalized_until is not null and v_me.hospitalized_until > v_now then
    raise exception 'The hospital feeds you while you are admitted. Order when you are out.' using errcode = 'P0001', hint = 'hospitalized';
  end if;
  it := bl_item(p_item);
  if it.category not in ('food', 'drink') or cardinality(it.sold_at) = 0 or bl_item_kind(it.effects) <> 'use' then
    raise exception '% is not on the ChopNow menu.', it.name using errcode = 'P0001', hint = 'not_on_menu';
  end if;
  perform bl_check_qty(p_qty);
  v_each := bl_delivery_price(it.price);
  v_total := v_each * p_qty;
  if v_total > v_me.bank + v_me.cash then
    raise exception 'Not enough money. The order is % with delivery and you have % in total.',
      bl_naira(v_total), bl_naira(v_me.bank + v_me.cash) using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_bank := least(v_total, v_me.bank);
  v_cash := v_total - v_bank;
  v_meta := jsonb_build_object('item', it.id, 'qty', p_qty, 'each', v_each, 'shop_price', it.price);
  if v_bank > 0 then perform bl_add_money(v_me.id, 'bank', -v_bank, 'food_delivery', v_meta); end if;
  if v_cash > 0 then perform bl_add_money(v_me.id, 'cash', -v_cash, 'food_delivery', v_meta); end if;
  v_owned := bl_give_item(v_me.id, it.id, p_qty);
  return jsonb_build_object(
    'message', 'Your ' || case when p_qty > 1 then p_qty || ' × ' else '' end || it.name
               || ' just arrived. The rider took ' || bl_naira(v_total)
               || case when v_bank > 0 and v_cash > 0 then ' (transfer + cash)' when v_bank > 0 then ' by transfer' else ' in cash' end
               || '. It''s in your Bag.',
    'item', it.id, 'qty', p_qty, 'owned', v_owned, 'paid', v_total, 'paid_bank', v_bank, 'paid_cash', v_cash);
end $$;

-- Settle rent owed (from anywhere: it's a transfer). Bank first, then cash; partial payments count.
create or replace function public.pay_rent() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  v_pay  bigint;
  v_bank bigint;
  v_cash bigint;
  v_left bigint;
  v_meta jsonb;
begin
  if v_me.rent_owed <= 0 then
    raise exception 'You don''t owe any rent. Your landlord is happy.' using errcode = 'P0001', hint = 'no_rent_owed';
  end if;
  v_pay := least(v_me.rent_owed, v_me.bank + v_me.cash);
  if v_pay <= 0 then
    raise exception 'You have no money to pay the landlord. You owe %.', bl_naira(v_me.rent_owed)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_bank := least(v_pay, v_me.bank);
  v_cash := v_pay - v_bank;
  v_meta := jsonb_build_object('settle', true, 'previous_owed', v_me.rent_owed, 'housing', v_me.housing_id);
  if v_bank > 0 then perform bl_add_money(v_me.id, 'bank', -v_bank, 'rent', v_meta); end if;
  if v_cash > 0 then perform bl_add_money(v_me.id, 'cash', -v_cash, 'rent', v_meta); end if;
  v_left := v_me.rent_owed - v_pay;
  update profiles set rent_owed = v_left where id = v_me.id;
  if v_left = 0 then
    perform bl_event(v_me.id, 'rent_paid', 'Rent settled',
      'You paid the ' || bl_naira(v_pay) || ' you owed. Landlord: "Thank you, my tenant. We are good now."',
      v_meta || jsonb_build_object('paid', v_pay, 'owed', 0));
  end if;
  return jsonb_build_object(
    'message', case when v_left = 0
                    then 'Rent settled: ' || bl_naira(v_pay) || ' paid. No more knocking at night.'
                    else 'You paid ' || bl_naira(v_pay) || '. You still owe ' || bl_naira(v_left) || '.' end,
    'paid', v_pay, 'paid_bank', v_bank, 'paid_cash', v_cash, 'owed', v_left);
end $$;

-- do_activity (same signature; latest body from 20261005000400_creator.sql) plus:
-- * boost items (soap) in the Bag are used up and add their bonus to the activity's effects;
-- * while rent is owed, the energy from rent.owed_sleep_activities is cut to rent.owed_sleep_energy_pct.
create or replace function public.do_activity(p_activity text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me     profiles := bl_me();
  a        activities;
  v_scene  text;
  v_until  timestamptz;
  v_eff    jsonb;
  v_used   text[] := '{}';
  r        record;
  v_pct    numeric;
  v_rent   boolean := false;
  v_msg    text;
begin
  perform bl_assert_free(v_me);
  select * into a from activities where id = p_activity;
  if not found then
    raise exception 'That activity doesn''t exist.' using errcode = 'P0001';
  end if;
  select scene into v_scene from locations where id = v_me.location_id;
  if not (v_scene = any(a.scenes)) then
    raise exception 'You can''t do "%" here. Go where it is offered.', a.name using errcode = 'P0001';
  end if;
  if a.home_only and v_me.location_id <> v_me.home_location_id then
    raise exception 'You can only do "%" in your own home.', a.name using errcode = 'P0001';
  end if;
  if a.night_only and not (bl_game_clock()->>'is_night')::boolean then
    raise exception '"%" is a night-time thing. Come back after dark.', a.name using errcode = 'P0001';
  end if;
  if a.cost > 0 then
    perform bl_add_money(v_me.id, 'cash', -a.cost, 'activity', jsonb_build_object('activity', a.id));
  end if;

  v_eff := a.effects;
  -- boost items for this activity (one of each)
  for r in select it.id, it.name, it.effects->'boost'->a.id as bonus
             from inventory i join items it on it.id = i.item_id
            where i.user_id = v_me.id and i.qty > 0 and jsonb_typeof(it.effects->'boost'->a.id) = 'object'
            order by it.sort, it.id loop
    v_eff := v_eff || bl_effects_add(bl_need_effects(v_eff), bl_need_effects(r.bonus));
    perform bl_give_item(v_me.id, r.id, -1);
    v_used := v_used || r.name;
  end loop;
  -- unpaid rent: the landlord keeps you up
  if v_me.rent_owed > 0 and bl_csv_has(bl_cfg_text('rent.owed_sleep_activities'), a.id)
     and coalesce((v_eff->>'energy')::numeric, 0) > 0 then
    v_pct := greatest(0, least(100, bl_cfg('rent.owed_sleep_energy_pct')));
    if v_pct < 100 then
      v_eff := v_eff || jsonb_build_object('energy', round((v_eff->>'energy')::numeric * v_pct / 100, 1));
      v_rent := true;
    end if;
  end if;

  perform bl_adjust_needs(v_me.id, v_eff);
  if coalesce((v_eff->>'street_cred')::int, 0) <> 0 then
    update profiles set street_cred = greatest(0, street_cred + (v_eff->>'street_cred')::int) where id = v_me.id;
  end if;
  v_until := bl_set_busy(v_me.id, a.game_minutes, a.name);
  v_msg := 'You started "' || a.name || '"'
           || case when a.cost > 0 then ' (' || bl_naira(a.cost) || ').' else '. Enjoy!' end;
  if cardinality(v_used) > 0 then
    v_msg := v_msg || ' Used: ' || array_to_string(v_used, ', ') || '.';
  end if;
  if v_rent then
    v_msg := v_msg || ' The landlord keeps knocking: "Where my rent? You owe ' || bl_naira(v_me.rent_owed)
             || '!" You won''t rest well until you pay.';
  end if;
  return jsonb_build_object('message', v_msg, 'busy_until', v_until, 'effects', v_eff,
                            'used', to_jsonb(v_used), 'rent_penalty', v_rent);
end $$;

-- get_my_state: same as V1-3 (keeps origin, creator, rent, career) plus `inventory` and the rent
-- penalty in the rent block. Still read-mostly: the only write is the throttled last_seen.
create or replace function public.get_my_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_now   timestamptz := bl_now();
  v_me    profiles;
  v_clock jsonb;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v_me.banned then
    raise exception 'This account has been banned. If this is a mistake, contact the admin.' using errcode = 'P0001', hint = 'banned';
  end if;
  if v_me.last_seen is null
     or v_me.last_seen < v_now - make_interval(secs => bl_cfg('time.last_seen_throttle_real_seconds')::double precision) then
    update profiles set last_seen = v_now where id = v_uid returning * into v_me;
  end if;
  v_me := bl_decay_row(v_me, v_now);
  v_clock := bl_game_clock(v_now);
  return jsonb_build_object(
    'profile', to_jsonb(v_me) - array['banned','needs_updated_at','last_seen',
                                      'travel_to','travel_mode','travel_started_at','travel_arrives_at'],
    'clock', v_clock,
    'location', (select to_jsonb(l) from locations l where l.id = v_me.location_id),
    'travel', case when v_me.travel_to is null then null
                   else jsonb_build_object('to', v_me.travel_to, 'mode', v_me.travel_mode,
                                           'started_at', v_me.travel_started_at,
                                           'arrives_at', v_me.travel_arrives_at) end,
    'origin', bl_origin_info(v_me.origin, v_me.allowance_claimed_day, (v_clock->>'day')::bigint),
    'creator', jsonb_build_object(
      'home_chosen', v_me.home_chosen,
      'traits', to_jsonb(v_me.traits),
      'dream', v_me.dream,
      'start_home', v_me.start_home,
      'homes', case when v_me.home_chosen then null else bl_homes_for(v_me.origin) end),
    'rent', jsonb_build_object(
      'weekly', v_me.weekly_rent,
      'due_at', v_me.rent_due_at,
      'owed', v_me.rent_owed,
      'enabled', bl_cfg_bool('rent.enabled'),
      'owed_sleep_pct', bl_cfg('rent.owed_sleep_energy_pct')),
    'career', bl_career_info(v_me),
    'inventory', bl_inventory_info(v_me.id),
    'server_time', v_now
  );
end $$;

-- ---------------------------------------------------------------------
-- 6. Turn weekly rent on (once). Jobs pay since V1-3. Only while the seeded default (false) is still
--    there and no admin has set it (updated_by is null); the trigger above rolls overdue rent days
--    forward first, so nobody is charged for the weeks rent was off.
-- ---------------------------------------------------------------------
update public.game_config
   set value = 'true'::jsonb,
       description = 'When on, rent is taken weekly on rent day (bank first, then cash; any shortfall becomes rent owed). Turning it on never back-charges the weeks it was off.'
 where key = 'rent.enabled' and value = 'false'::jsonb and updated_by is null;

-- ---------------------------------------------------------------------
-- 7. Privileges
-- ---------------------------------------------------------------------
revoke execute on function public.bl_need_keys()                    from public, anon, authenticated;
revoke execute on function public.bl_item_kind(jsonb)               from public, anon, authenticated;
revoke execute on function public.bl_need_effects(jsonb)            from public, anon, authenticated;
revoke execute on function public.bl_effects_add(jsonb, jsonb)      from public, anon, authenticated;
revoke execute on function public.bl_resale_price(public.items)     from public, anon, authenticated;
revoke execute on function public.bl_delivery_price(bigint)         from public, anon, authenticated;
revoke execute on function public.bl_csv_has(text, text)            from public, anon, authenticated;
revoke execute on function public.bl_can_sell_at(text)              from public, anon, authenticated;
revoke execute on function public.bl_give_item(uuid, text, int)     from public, anon, authenticated;
revoke execute on function public.bl_item(text)                     from public, anon, authenticated;
revoke execute on function public.bl_check_qty(int)                 from public, anon, authenticated;
revoke execute on function public.bl_inventory_info(uuid)           from public, anon, authenticated;
revoke execute on function public.bl_rent_switch_trigger()          from public, anon, authenticated;

revoke execute on function public.shop_list(text)       from public, anon;
revoke execute on function public.shop_buy(text, int)   from public, anon;
revoke execute on function public.item_use(text)        from public, anon;
revoke execute on function public.item_sell(text, int)  from public, anon;
revoke execute on function public.food_menu()           from public, anon;
revoke execute on function public.food_order(text, int) from public, anon;
revoke execute on function public.pay_rent()            from public, anon;
grant execute on function public.shop_list(text)        to authenticated;
grant execute on function public.shop_buy(text, int)    to authenticated;
grant execute on function public.item_use(text)         to authenticated;
grant execute on function public.item_sell(text, int)   to authenticated;
grant execute on function public.food_menu()            to authenticated;
grant execute on function public.food_order(text, int)  to authenticated;
grant execute on function public.pay_rent()             to authenticated;
grant execute on function public.do_activity(text)      to authenticated;
grant execute on function public.get_my_state()         to authenticated;
