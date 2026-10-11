-- H2: sell furniture + cars, car dealer price tiers, receipts for big purchases.
-- Docs: docs/FURNITURE_CATALOGUE.md (selling), docs/GARAGE.md (selling cars, dealer tiers), docs/RECEIPTS.md.
-- Idempotent and safe on a non-empty DB: tables `if not exists`, seeds `on conflict do nothing`, functions
-- `create or replace`, and live functions patched from pg_get_functiondef with guarded text replacement.
--   1. config: furniture.sell_enabled / furniture.resale_pct (45), cars.sell_enabled / cars.resale_pct (60),
--      receipts.enabled / receipts.min_amount (500,000).
--   2. car_dealers (admin Content -> Car dealers): a tier (budget / mid / premium) and a price multiplier per
--      dealer location. Tokunbo Lot = budget x0.88, Ighodalo = mid x1.00, SDD Motors = premium x1.20.
--      bl_dealer_price(item, location) = base x multiplier (rounded); shop_list, shop_buy and place_interior
--      use it. Stock: luxury cars only at the premium showroom, brand-new cars not at the budget lot, and the
--      tokunbo Lexus / Camry "Muscle" now also at the lot (only rows still holding the seeded sold_at change).
--   3. furniture_sell(key): pays resale_pct of the catalogue price in cash, removes that copy (the last copy
--      takes its key so keys stay own_x, own_x-2 ...), ledger 'furniture_sell'. The free starter piece (copy 1
--      of a starter row) can't be sold; built-ins are never player furniture.
--   4. car_sell(item): pays cars.resale_pct of the base price into the bank, ledger 'car_sell'. Not while on
--      the road / busy (bl_assert_free). item_sell no longer takes vehicles at the market (one price path).
--   5. receipts (owner-read RLS, written only by bl_receipt_issue from server functions): furniture_buy,
--      shop_buy (cars and shop items), garage_build, house_move and wardrobe_buy issue one when the amount is
--      >= receipts.min_amount and return it as `receipt` (the client shows the receipt sheet).

-- ---------------------------------------------------------------- 1. config
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('furniture.sell_enabled', 'true', 'shop', 'Selling furniture on',
 'H2: Buy -> Arrange -> My items has Sell on every piece you bought. Off = selling refused.', 'bool', null, null),
('furniture.resale_pct', '45', 'shop', 'Furniture resale %',
 'H2: a sold piece pays this % of its catalogue price, in cash (fairly-used furniture sells for about half).', 'percent', 0, 100),
('cars.sell_enabled', 'true', 'places', 'Selling cars on',
 'H2: Phone -> Cars -> My cars and the garage sheet can sell a car back. Off = selling refused.', 'bool', null, null),
('cars.resale_pct', '60', 'places', 'Car resale %',
 'H2: a sold car pays this % of its base (list) price into the bank. Depreciation is 40% by default.', 'percent', 0, 100),
('receipts.enabled', 'true', 'shop', 'Receipts on',
 'H2 (docs/RECEIPTS.md): big purchases give a receipt (sheet after paying + Bank -> Receipts).', 'bool', null, null),
('receipts.min_amount', '500000', 'shop', 'Receipt from (naira)',
 'H2: purchases of this amount or more get a receipt: house move-in, cars, furniture, garages, big boutique items.', 'naira', 0, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------- 2. car dealers
create table if not exists public.car_dealers (
  location_id text primary key references public.locations(id) on update cascade on delete cascade,
  tier        text not null default 'mid' check (tier in ('budget', 'mid', 'premium')),
  multiplier  numeric(4,2) not null default 1 check (multiplier between 0.5 and 2),
  label       text not null default '',
  blurb       text not null default '',
  sort        int not null default 100,
  active      boolean not null default true
);
alter table public.car_dealers enable row level security;
drop policy if exists car_dealers_read on public.car_dealers;
create policy car_dealers_read on public.car_dealers for select to anon, authenticated using (true);
revoke all on public.car_dealers from anon, authenticated;
grant select on public.car_dealers to anon, authenticated;

insert into public.car_dealers (location_id, tier, multiplier, label, blurb, sort)
select v.* from (values
  ('tokunbo_lot', 'budget', 0.88::numeric, 'Tokunbo lot',
   'Roadside Belgium-used stock: cheapest prices, older cars, no brand-new or luxury.', 10),
  ('ighodalo_cars', 'mid', 1.00::numeric, 'Car dealer',
   'Clean tokunbo and a few brand-new saloons at list price.', 20),
  ('sdd_motors', 'premium', 1.20::numeric, 'Official showroom',
   'Brand showroom: new cars with warranty, papers and plates. The only place that sells the luxury cars.', 30)
) v(location_id, tier, multiplier, label, blurb, sort)
where exists (select 1 from public.locations l where l.id = v.location_id)
on conflict (location_id) do nothing;

-- stock by tier (only rows still holding the seeded value, so admin edits stay)
update public.items set sold_at = '{sdd_motors}'
 where id in ('gwagon_g63', 'gle63_coupe', 'lambo_urus', 'tesla_cybertruck', 'escalade')
   and sold_at = '{ighodalo_cars,sdd_motors,tokunbo_lot}';
update public.items set sold_at = '{ighodalo_cars,sdd_motors}'
 where id in ('camry_new', 'benz_c300') and sold_at = '{ighodalo_cars,sdd_motors,tokunbo_lot}';
update public.items set sold_at = '{ighodalo_cars,sdd_motors,tokunbo_lot}'
 where id in ('lexus_rx350', 'camry_muscle') and sold_at = '{ighodalo_cars,sdd_motors}';

-- Price of an item at a place: vehicles at an active dealer = base x multiplier, rounded to ₦10,000
-- (₦1,000 under ₦1M). Everything else = the base price. The client mirrors this in src/lib/dealers.ts.
create or replace function public.bl_dealer_price(p_item items, p_location text) returns bigint
language sql stable set search_path = public as $$
  select case
    when p_item.category <> 'vehicle' then p_item.price
    else coalesce((
      select case when p_item.price * d.multiplier >= 1000000
                  then (round(p_item.price * d.multiplier / 10000.0) * 10000)::bigint
                  else (round(p_item.price * d.multiplier / 1000.0) * 1000)::bigint end
        from car_dealers d where d.location_id = p_location and d.active), p_item.price)
  end
$$;
revoke execute on function public.bl_dealer_price(items, text) from public, anon, authenticated;

create or replace function public.bl_dealer_info(p_location text) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('tier', d.tier, 'multiplier', d.multiplier, 'label', d.label, 'blurb', d.blurb)
    from car_dealers d where d.location_id = p_location and d.active
$$;
revoke execute on function public.bl_dealer_info(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- 5a. receipts (table + issuer)
create table if not exists public.receipts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null,
  item_name  text not null,
  amount     bigint not null check (amount >= 0),
  seller     text not null default '',
  ref        text not null unique,
  meta       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists receipts_user_idx on public.receipts (user_id, created_at desc);
alter table public.receipts enable row level security;
drop policy if exists receipts_owner_read on public.receipts;
create policy receipts_owner_read on public.receipts for select to authenticated using (user_id = auth.uid());
revoke all on public.receipts from anon, authenticated;
grant select on public.receipts to authenticated;

-- Issue a receipt when the amount reaches receipts.min_amount. Returns {"receipt": {...}} or {} (so callers
-- can write `return bl_receipt_issue(...) || jsonb_build_object(...)`).
create or replace function public.bl_receipt_issue(p_uid uuid, p_kind text, p_item text, p_amount bigint,
                                                   p_seller text, p_meta jsonb default '{}'::jsonb)
returns jsonb language plpgsql set search_path = public as $$
declare
  v_min bigint := coalesce((select (value #>> '{}')::numeric from game_config where key = 'receipts.min_amount'), 500000)::bigint;
  v_ref text;
  v_abc text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  r receipts;
begin
  if p_uid is null or coalesce(p_amount, 0) <= 0 or p_amount < v_min
     or not coalesce((select (value #>> '{}')::boolean from game_config where key = 'receipts.enabled'), true) then
    return '{}'::jsonb;
  end if;
  loop
    v_ref := 'BL-' || to_char(bl_now() at time zone 'Africa/Lagos', 'YYYY') || '-'
             || (select string_agg(substr(v_abc, 1 + floor(random() * length(v_abc))::int, 1), '') from generate_series(1, 6));
    exit when not exists (select 1 from receipts where ref = v_ref);
  end loop;
  insert into receipts (user_id, kind, item_name, amount, seller, ref, meta, created_at)
  values (p_uid, coalesce(p_kind, 'purchase'), coalesce(p_item, 'Purchase'), p_amount, coalesce(p_seller, ''), v_ref,
          coalesce(p_meta, '{}'::jsonb), bl_now())
  returning * into r;
  return jsonb_build_object('receipt', jsonb_build_object('id', r.id, 'ref', r.ref, 'kind', r.kind, 'item_name', r.item_name,
    'amount', r.amount, 'seller', r.seller, 'meta', r.meta, 'created_at', r.created_at));
end $$;
revoke execute on function public.bl_receipt_issue(uuid, text, text, bigint, text, jsonb) from public, anon, authenticated;

-- Seller names on furniture receipts (made-up shops by tier).
create or replace function public.bl_furniture_seller(p_tier text) returns text
language sql immutable set search_path = public as $$
  select case p_tier when 'lapo' then 'Oba Market Furniture Stalls'
                     when 'nepo' then 'Ring Road Interiors'
                     else 'Benin Home Store' end
$$;
revoke execute on function public.bl_furniture_seller(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- 3. sell furniture
create or replace function public.furniture_sell(p_key text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  pf      player_furniture;
  f       furniture;
  v_id    text;
  v_copy  int;
  v_key   text;
  v_last  text;
  v_moved text;
  v_pct   numeric;
  v_pay   bigint;
  v_cash  bigint;
begin
  perform bl_assert_free(v_me);
  if not bl_cfg_bool('furniture.sell_enabled') then
    raise exception 'Selling furniture is paused right now.' using errcode = 'P0001', hint = 'sell_disabled';
  end if;
  perform bl_furniture_require_owned(v_me.id, p_key);
  v_id := bl_furniture_id_of(p_key);
  v_copy := bl_furniture_copy_of(p_key);
  v_key := case when v_copy = 1 then 'own_' || v_id else 'own_' || v_id || '-' || v_copy end;
  select * into pf from player_furniture where user_id = v_me.id and furniture_id = v_id for update;
  select * into f from furniture where id = v_id;
  if pf.source = 'starter' and pf.qty <= 1 then
    raise exception '% came with your house. You fit store am, but you no fit sell am.', f.name
      using errcode = 'P0001', hint = 'starter_piece';
  end if;
  v_pct := greatest(0, least(100, coalesce(bl_cfg('furniture.resale_pct'), 45)));
  v_pay := (floor(f.price * v_pct / 100.0 / 100) * 100)::bigint;
  if v_pay <= 0 then
    raise exception 'Nobody go buy % from you.', f.name using errcode = 'P0001', hint = 'not_sellable';
  end if;
  -- every copy gets its row first, so the renumbering below sees them all
  perform bl_furniture_materialize(v_me.id);
  v_last := case when pf.qty <= 1 then 'own_' || v_id else 'own_' || v_id || '-' || pf.qty end;
  delete from player_house_furniture where owner_id = v_me.id and furniture_key = v_key;
  if v_last <> v_key then
    -- the last copy takes the sold key, so the keys stay own_x, own_x-2 ... own_x-(qty-1)
    update player_house_furniture set furniture_key = v_key, updated_at = bl_now()
     where owner_id = v_me.id and furniture_key = v_last;
    v_moved := v_last;
  end if;
  if pf.qty <= 1 then
    delete from player_furniture where user_id = v_me.id and furniture_id = v_id;
  else
    update player_furniture set qty = qty - 1 where user_id = v_me.id and furniture_id = v_id;
  end if;
  v_cash := bl_add_money(v_me.id, 'cash', v_pay, 'furniture_sell',
                         jsonb_build_object('furniture', f.id, 'name', f.name, 'key', v_key, 'price', f.price));
  return jsonb_build_object(
    'message', 'You sold ' || f.name || ' for ' || bl_naira(v_pay) || '. The buyer don carry am go.',
    'furniture_key', v_key, 'moved_from', v_moved, 'id', f.id, 'name', f.name, 'earned', v_pay,
    'price', f.price, 'resale_pct', v_pct, 'qty', greatest(pf.qty - 1, 0), 'cash', v_cash);
end $$;
revoke execute on function public.furniture_sell(text) from public, anon;
grant execute on function public.furniture_sell(text) to authenticated, service_role;

-- ---------------------------------------------------------------- 4. sell a car
create or replace function public.car_sell(p_item text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  it     items;
  v_have int;
  v_pct  numeric;
  v_pay  bigint;
  v_bank bigint;
  v_left int;
begin
  perform bl_assert_free(v_me);
  if not bl_cfg_bool('cars.sell_enabled') then
    raise exception 'Selling cars is paused right now.' using errcode = 'P0001', hint = 'sell_disabled';
  end if;
  select * into it from items where id = p_item and category = 'vehicle';
  if not found then
    raise exception 'That is not a car.' using errcode = 'P0001', hint = 'not_a_car';
  end if;
  select qty into v_have from inventory where user_id = v_me.id and item_id = it.id for update;
  if coalesce(v_have, 0) < 1 then
    raise exception 'You don''t own a %.', it.name using errcode = 'P0001', hint = 'not_owned';
  end if;
  v_pct := greatest(0, least(100, coalesce(bl_cfg('cars.resale_pct'), 60)));
  v_pay := (floor(it.price * v_pct / 100.0 / 1000) * 1000)::bigint;
  v_left := bl_give_item(v_me.id, it.id, -1);
  v_bank := v_me.bank;
  if v_pay > 0 then
    v_bank := bl_add_money(v_me.id, 'bank', v_pay, 'car_sell', jsonb_build_object('item', it.id, 'name', it.name, 'price', it.price));
  end if;
  return jsonb_build_object(
    'message', 'Deal done! You sold your ' || it.name || ' for ' || bl_naira(v_pay) || '. The money don enter your bank.',
    'item', it.id, 'name', it.name, 'earned', v_pay, 'price', it.price, 'resale_pct', v_pct, 'left', v_left, 'bank', v_bank);
end $$;
revoke execute on function public.car_sell(text) from public, anon;
grant execute on function public.car_sell(text) to authenticated, service_role;

-- ---------------------------------------------------------------- live patches
create or replace function pg_temp.h2_patch(p_fn text, p_guard text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  v_def := pg_get_functiondef(p_fn::regprocedure);
  if position(p_guard in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / greatest(length(p_marker), 1);
  if v_n <> 1 then
    raise exception 'H2: marker for % found % times: %', p_fn, v_n, p_marker;
  end if;
  execute replace(v_def, p_marker, p_new);
end $$;

do $mig$
begin
  -- dealer prices: shop_list, shop_buy, place_interior
  perform pg_temp.h2_patch('public.shop_list(text)', 'bl_dealer_price(',
    $m$'sell_here', bl_can_sell_at(l.id),$m$,
    $m$'sell_here', bl_can_sell_at(l.id), 'dealer', bl_dealer_info(l.id),$m$);
  perform pg_temp.h2_patch('public.shop_list(text)', $g$'base_price', it.price$g$,
    $m$'price', it.price,$m$,
    $m$'price', bl_dealer_price(it, l.id), 'base_price', it.price, 'sold_at', it.sold_at,$m$);
  perform pg_temp.h2_patch('public.shop_list(text)', 'v_me.cash >= bl_dealer_price(it, l.id)',
    $m$'affordable', v_me.cash >= it.price$m$,
    $m$'affordable', v_me.cash >= bl_dealer_price(it, l.id)$m$);
  perform pg_temp.h2_patch('public.shop_buy(text,integer)', 'bl_dealer_price(it, l.id) * p_qty',
    'v_total := it.price * p_qty;',
    'v_total := bl_dealer_price(it, l.id) * p_qty;');
  perform pg_temp.h2_patch('public.place_interior(text)', 'bl_dealer_price(',
    $m$'cost', it.price,$m$,
    $m$'cost', bl_dealer_price(it, l.id),$m$);

  -- receipts on the purchase RPCs
  perform pg_temp.h2_patch('public.shop_buy(text,integer)', $g$bl_receipt_issue(v_me.id, 'car'$g$,
    $m$return jsonb_build_object('message', v_msg, 'item', it.id, 'qty', 1,$m$,
    $m$return bl_receipt_issue(v_me.id, 'car', it.name, v_total, l.name,
             jsonb_build_object('item', it.id, 'location', l.id, 'base_price', it.price, 'dealer', bl_dealer_info(l.id),
                                'from_bank', v_bank, 'from_cash', v_cash))
      || jsonb_build_object('message', v_msg, 'item', it.id, 'qty', 1,$m$);
  perform pg_temp.h2_patch('public.shop_buy(text,integer)', $g$bl_receipt_issue(v_me.id, 'shop'$g$,
    $m$return jsonb_build_object('message', v_msg, 'item', it.id, 'qty', p_qty,$m$,
    $m$return bl_receipt_issue(v_me.id, 'shop', case when p_qty > 1 then p_qty || ' × ' || it.name else it.name end,
             v_total, l.name, jsonb_build_object('item', it.id, 'qty', p_qty, 'location', l.id, 'from_cash', v_total))
    || jsonb_build_object('message', v_msg, 'item', it.id, 'qty', p_qty,$m$);
  perform pg_temp.h2_patch('public.furniture_buy(text)', 'bl_receipt_issue(',
    $m$return jsonb_build_object('furniture_key', v_key,$m$,
    $m$return bl_receipt_issue(v_uid, 'furniture', f.name, f.price, bl_furniture_seller(f.tier),
             jsonb_build_object('furniture', f.id, 'tier', f.tier, 'from_cash', v_cash, 'from_bank', v_bank))
    || jsonb_build_object('furniture_key', v_key,$m$);
  perform pg_temp.h2_patch('public.garage_build(text)', 'bl_receipt_issue(',
    $m$return jsonb_build_object('message', v_msg, 'garage', g.id,$m$,
    $m$return bl_receipt_issue(v_me.id, 'garage', g.name, g.price, 'Benin Builders & Sons',
             jsonb_build_object('garage', g.id, 'from_bank', v_bank, 'from_cash', v_cash))
    || jsonb_build_object('message', v_msg, 'garage', g.id,$m$);
  perform pg_temp.h2_patch('public.house_move(text)', 'bl_receipt_issue(',
    'return jsonb_build_object(',
    $m$return bl_receipt_issue(v_me.id, 'house', 'Move-in: ' || h.name || ' (' || rtrim(to_char(v_weeks, 'FM990.##'), '.') || ' weeks rent)',
             v_cost, 'Landlord' || case when h.district <> '' then ', ' || h.district else '' end,
             jsonb_build_object('home', h.id, 'weekly_rent', h.weekly_rent, 'weeks', v_weeks, 'from_bank', v_bank, 'from_cash', v_cash))
    || jsonb_build_object($m$);
  perform pg_temp.h2_patch('public.wardrobe_buy(text,text)', 'bl_receipt_issue(',
    'return jsonb_build_object(',
    $m$return bl_receipt_issue(v_me.id, 'boutique', it.name, it.price,
             coalesce((select b.name from wardrobe_brands b where b.id = it.brand_id), 'Benin Boutique'),
             jsonb_build_object('item', it.id, 'colour', p_colour, 'from_bank', v_bank, 'from_cash', v_cash))
    || jsonb_build_object($m$);

  -- cars are sold back through car_sell only (one price path)
  perform pg_temp.h2_patch('public.item_sell(text,integer)', 'use_car_sell',
    '  it := bl_item(p_item);',
    E'  it := bl_item(p_item);\n'
    || E'  if it.category = ''vehicle'' then\n'
    || E'    raise exception ''Sell cars from Phone -> Cars -> My cars.'' using errcode = ''P0001'', hint = ''use_car_sell'';\n'
    || E'  end if;');

  -- ledger labels
  perform pg_temp.h2_patch('public.bl_ledger_label(text,jsonb)', $g$'furniture_sell'$g$,
    $m$    when 'garage' then$m$,
    $m$    when 'furniture_sell' then return 'Sold furniture: ' || coalesce(p_meta->>'name', 'furniture');
    when 'car_sell' then return 'Sold car: ' || coalesce(p_meta->>'name', 'car');
    when 'car_purchase' then
      select name into v from items where id = p_meta->>'item';
      return 'Car: ' || coalesce(v, 'car');
    when 'garage' then$m$);

  -- admin Content -> Car dealers
  perform pg_temp.h2_patch('public.bl_admin_table_spec(text)', $g$'car_dealers'$g$,
    $m$    when 'garage_types' then$m$,
    $m$    when 'car_dealers' then '{"pk":["location_id"],"insert":true,"order":"sort, location_id",
      "cols":{"tier":"text","multiplier":"num","label":"text","blurb":"text","sort":"int","active":"bool"}}'
    when 'garage_types' then$m$);
end $mig$;

notify pgrst, 'reload schema';
