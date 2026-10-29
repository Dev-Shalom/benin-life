-- Benin Life: Admin Grant toolbox, part 2 (docs/ADMIN_GRANTS.md): things a player owns.
-- Items and cars (inventory), furniture, garage, wardrobe, hustle stall pass. Each has a give and a take (undo).
-- Same tables and key rules the shop, furniture_buy / furniture_sell, garage_build and wardrobe_buy use; no money moves
-- and nothing is written to the ledger or receipts, so a gift is never counted as earned.

-- ---------------------------------------------------------------------
-- 1. Items (food, drink, tools, laptops, phones, ingredients, kids things ...) and cars (category 'vehicle')
-- ---------------------------------------------------------------------
create or replace function public.admin_give_item(p_user uuid, p_item text, p_qty int default 1, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false);
  p profiles; it items; v_old int; v_new int;
begin
  if p_qty is null or p_qty < 1 or p_qty > 99 then
    perform bl_ag_fail('Quantity goes from 1 to 99.', 'bad_qty');
  end if;
  select * into it from items where id = p_item;
  if not found then
    perform bl_ag_fail('That item doesn''t exist.', 'no_item');
  end if;
  p := bl_ag_target(p_user);
  v_old := coalesce((select qty from inventory where user_id = p_user and item_id = it.id), 0);
  if it.category = 'vehicle' then
    if p_qty <> 1 then
      perform bl_ag_fail('Cars are given one at a time.', 'bad_qty');
    end if;
    if v_old >= 1 then
      perform bl_ag_fail('They already own a ' || it.name || '. The game allows one of each car.', 'already_owned');
    end if;
  end if;
  if v_old + p_qty > 9999 then
    perform bl_ag_fail('They would hold more than 9,999 of that. Take some back first.', 'max_owned');
  end if;
  v_new := bl_give_item(p_user, it.id, p_qty);
  perform bl_ag_log(v_admin, p_user, case when it.category = 'vehicle' then 'grant_car' else 'grant_item' end,
                    jsonb_build_object('item', it.id, 'name', it.name, 'qty', p_qty, 'old', v_old, 'new', v_new, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', case when it.category = 'vehicle' then 'A car for you' else 'A gift in your Bag' end,
    'An admin gave you ' || case when p_qty > 1 then p_qty || ' x ' else '' end || it.name
      || case when it.category = 'vehicle' then '. It is now a travel option in the Ride app.' else '. It is in your Bag.' end,
    v_reason, jsonb_build_object('item', it.id, 'qty', p_qty));
  return jsonb_build_object('message', 'Gave ' || case when p_qty > 1 then p_qty || ' x ' else '' end || it.name || ' to @' || p.username || ' (now ' || v_new || ').',
                            'item', it.id, 'qty', v_new);
end $$;

create or replace function public.admin_take_item(p_user uuid, p_item text, p_qty int default 1, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false);
  p profiles; it items; v_old int; v_new int;
begin
  if p_qty is null or p_qty < 1 or p_qty > 9999 then
    perform bl_ag_fail('Quantity goes from 1 to 9,999.', 'bad_qty');
  end if;
  select * into it from items where id = p_item;
  if not found then
    perform bl_ag_fail('That item doesn''t exist.', 'no_item');
  end if;
  p := bl_ag_target(p_user, true);
  v_old := coalesce((select qty from inventory where user_id = p_user and item_id = it.id), 0);
  if v_old < p_qty then
    perform bl_ag_fail('They only have ' || v_old || ' of ' || it.name || '.', 'not_enough');
  end if;
  v_new := bl_give_item(p_user, it.id, -p_qty);
  if it.category = 'vehicle' then
    delete from player_cars where user_id = p_user and item_id = it.id;
  end if;
  perform bl_ag_log(v_admin, p_user, 'take_item', jsonb_build_object('item', it.id, 'name', it.name, 'qty', p_qty, 'old', v_old, 'new', v_new, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_take', 'Removed from your Bag', 'An admin took ' || case when p_qty > 1 then p_qty || ' x ' else '' end || it.name || ' from you.', v_reason);
  return jsonb_build_object('message', 'Took ' || case when p_qty > 1 then p_qty || ' x ' else '' end || it.name || ' from @' || p.username || ' (now ' || v_new || ').',
                            'item', it.id, 'qty', v_new);
end $$;

-- ---------------------------------------------------------------------
-- 2. Furniture (up to the piece's max_qty, the same key numbering furniture_buy uses)
-- ---------------------------------------------------------------------
create or replace function public.admin_give_furniture(p_user uuid, p_furniture text, p_qty int default 1, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false);
  p profiles; f furniture; v_old int; v_qty int; v_key text; v_layout text; i int;
begin
  if p_qty is null or p_qty < 1 or p_qty > 20 then
    perform bl_ag_fail('Quantity goes from 1 to 20.', 'bad_qty');
  end if;
  select * into f from furniture where id = p_furniture and active;
  if not found then
    perform bl_ag_fail('That furniture piece doesn''t exist.', 'unknown_furniture');
  end if;
  p := bl_ag_target(p_user);
  v_old := coalesce((select qty from player_furniture where user_id = p_user and furniture_id = f.id), 0);
  if v_old + p_qty > least(f.max_qty, 20) then
    perform bl_ag_fail('The most they can hold is ' || least(f.max_qty, 20) || ' of ' || f.name || ' and they have ' || v_old || '.', 'max_owned');
  end if;
  v_layout := bl_furniture_materialize(p_user);
  for i in 1..p_qty loop
    insert into player_furniture (user_id, furniture_id, slot, source, qty) values (p_user, f.id, null, 'admin', 1)
    on conflict (user_id, furniture_id) do update set qty = player_furniture.qty + 1
    returning qty into v_qty;
    v_key := bl_furniture_key(f.id, v_qty);
    if coalesce((select house_qty from player_furniture where user_id = p_user and furniture_id = f.id), 0) > 0 then
      delete from player_house_furniture where owner_id = p_user and furniture_key = v_key;
      v_key := (select bl_furniture_key(f.id, qty - house_qty) from player_furniture where user_id = p_user and furniture_id = f.id);
      update player_house_furniture set furniture_key = bl_furniture_key(f.id, v_qty), updated_at = bl_now()
       where owner_id = p_user and furniture_key = v_key;
    end if;
    insert into player_house_furniture (owner_id, furniture_key, x, z, rotation, stored, layout, updated_at)
    values (p_user, v_key, 0, 0, 0, true, v_layout, bl_now())
    on conflict (owner_id, furniture_key) do update set stored = true, layout = excluded.layout, updated_at = excluded.updated_at;
  end loop;
  perform bl_ag_log(v_admin, p_user, 'grant_furniture', jsonb_build_object('furniture', f.id, 'name', f.name, 'qty', p_qty, 'old', v_old, 'new', v_old + p_qty, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'New furniture', 'An admin sent ' || case when p_qty > 1 then p_qty || ' x ' else '' end || f.name || ' to your house. Find it in My items and place it.',
                      v_reason, jsonb_build_object('furniture', f.id, 'qty', p_qty));
  return jsonb_build_object('message', 'Gave ' || case when p_qty > 1 then p_qty || ' x ' else '' end || f.name || ' to @' || p.username || ' (now ' || (v_old + p_qty) || ').',
                            'furniture', f.id, 'qty', v_old + p_qty);
end $$;

-- Takes back bought or gifted copies (the pieces that came with a house stay: they belong to the home).
create or replace function public.admin_take_furniture(p_user uuid, p_furniture text, p_qty int default 1, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false);
  p profiles; f furniture; pf player_furniture; v_old int; v_key text; v_last text; i int;
begin
  if p_qty is null or p_qty < 1 or p_qty > 20 then
    perform bl_ag_fail('Quantity goes from 1 to 20.', 'bad_qty');
  end if;
  select * into f from furniture where id = p_furniture;
  if not found then
    perform bl_ag_fail('That furniture piece doesn''t exist.', 'unknown_furniture');
  end if;
  p := bl_ag_target(p_user, true);
  select * into pf from player_furniture where user_id = p_user and furniture_id = f.id for update;
  if not found or pf.qty - pf.house_qty < p_qty then
    perform bl_ag_fail('They only have ' || coalesce(pf.qty - pf.house_qty, 0) || ' removable ' || f.name || ' (pieces that came with the house stay).', 'not_enough');
  end if;
  v_old := pf.qty;
  perform bl_furniture_materialize(p_user);
  for i in 1..p_qty loop
    select * into pf from player_furniture where user_id = p_user and furniture_id = f.id for update;
    v_key := bl_furniture_key(f.id, pf.qty - pf.house_qty);          -- the last bought copy
    v_last := bl_furniture_key(f.id, pf.qty);
    delete from player_house_furniture where owner_id = p_user and furniture_key = v_key;
    if v_last <> v_key then
      update player_house_furniture set furniture_key = v_key, updated_at = bl_now() where owner_id = p_user and furniture_key = v_last;
    end if;
    if pf.qty <= 1 then
      delete from player_furniture where user_id = p_user and furniture_id = f.id;
    else
      update player_furniture set qty = qty - 1 where user_id = p_user and furniture_id = f.id;
    end if;
  end loop;
  perform bl_ag_log(v_admin, p_user, 'take_furniture', jsonb_build_object('furniture', f.id, 'name', f.name, 'qty', p_qty, 'old', v_old, 'new', v_old - p_qty, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_take', 'Furniture removed', 'An admin took ' || case when p_qty > 1 then p_qty || ' x ' else '' end || f.name || ' from your house.', v_reason);
  return jsonb_build_object('message', 'Took ' || case when p_qty > 1 then p_qty || ' x ' else '' end || f.name || ' from @' || p.username || ' (now ' || (v_old - p_qty) || ').',
                            'furniture', f.id, 'qty', v_old - p_qty);
end $$;

-- ---------------------------------------------------------------------
-- 3. Garage (free; must fit the home type exactly like garage_build) and remove
-- ---------------------------------------------------------------------
create or replace function public.admin_give_garage(p_user uuid, p_type text, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false);
  p profiles; g garage_types; old player_garages; v_kind text; v_stale boolean;
begin
  select * into g from garage_types where id = p_type and active;
  if not found then
    perform bl_ag_fail('That garage type isn''t available.', 'unknown_garage');
  end if;
  p := bl_ag_target(p_user);
  v_kind := bl_housing_kind(p.housing_id);
  if not (v_kind = any (g.allowed_housing)) then
    perform bl_ag_fail('A ' || lower(g.name) || ' can''t be built at their ' || replace(v_kind, '_', ' ') || ' home. Set a bigger home first, or pick another garage.', 'not_allowed_here');
  end if;
  select * into old from player_garages where user_id = p_user for update;
  v_stale := old.user_id is not null and (old.housing_id is distinct from p.housing_id or old.home_location_id is distinct from p.home_location_id);
  if old.user_id is not null and not v_stale and old.garage_type = g.id then
    perform bl_ag_fail('They already have a ' || lower(g.name) || ' at home.', 'already_built');
  end if;
  insert into player_garages (user_id, garage_type, housing_id, home_location_id, price_paid, built_at)
  values (p_user, g.id, p.housing_id, p.home_location_id, 0, bl_now())
  on conflict (user_id) do update set garage_type = excluded.garage_type, housing_id = excluded.housing_id,
    home_location_id = excluded.home_location_id, price_paid = excluded.price_paid, built_at = excluded.built_at;
  perform bl_ag_log(v_admin, p_user, 'grant_garage', jsonb_build_object('garage', g.id, 'name', g.name, 'replaced', case when old.user_id is not null and not v_stale then old.garage_type end, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'A garage for your home', 'An admin built a ' || lower(g.name) || ' at your home. Your cars are parked there.', v_reason, jsonb_build_object('garage', g.id));
  return jsonb_build_object('message', g.name || ' built for @' || p.username || '.', 'garage', g.id);
end $$;

create or replace function public.admin_remove_garage(p_user uuid, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false); p profiles; old player_garages;
begin
  p := bl_ag_target(p_user, true);
  delete from player_garages where user_id = p_user returning * into old;
  if old.user_id is null then
    perform bl_ag_fail('They have no garage.', 'no_garage');
  end if;
  perform bl_ag_log(v_admin, p_user, 'remove_garage', jsonb_build_object('garage', old.garage_type, 'price_paid', old.price_paid, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_take', 'Garage removed', 'An admin removed your garage. Your cars stay yours and park outside.', v_reason);
  return jsonb_build_object('message', 'Garage removed from @' || p.username || '. Their cars stay.');
end $$;

-- ---------------------------------------------------------------------
-- 4. Wardrobe (boutique clothes)
-- ---------------------------------------------------------------------
create or replace function public.admin_give_wardrobe(p_user uuid, p_item text, p_colour text default null, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false);
  p profiles; it wardrobe_items; v_col text;
begin
  select * into it from wardrobe_items where id = p_item and active;
  if not found then
    perform bl_ag_fail('That clothing item doesn''t exist.', 'unknown_item');
  end if;
  p := bl_ag_target(p_user);
  if it.gender is not null and it.gender <> p.gender::text then
    perform bl_ag_fail(it.name || ' isn''t made for their Sim.', 'wrong_gender');
  end if;
  if p_colour is not null and cardinality(it.colours) > 0 and not (lower(p_colour) = any (select lower(c) from unnest(it.colours) c)) then
    perform bl_ag_fail(it.name || ' doesn''t come in that colour.', 'bad_colour');
  end if;
  if exists (select 1 from player_wardrobe where user_id = p_user and item_id = it.id) then
    perform bl_ag_fail('They already own the ' || it.name || '.', 'already_owned');
  end if;
  v_col := lower(coalesce(p_colour, it.colours[1]));
  insert into player_wardrobe (user_id, item_id, colour, price_paid, bought_at) values (p_user, it.id, v_col, 0, bl_now());
  perform bl_ag_log(v_admin, p_user, 'grant_wardrobe', jsonb_build_object('item', it.id, 'name', it.name, 'colour', v_col, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'New clothes', 'An admin added the ' || it.name || ' to your wardrobe.', v_reason, jsonb_build_object('item', it.id));
  return jsonb_build_object('message', it.name || ' added to @' || p.username || '''s wardrobe.', 'item', it.id);
end $$;

create or replace function public.admin_take_wardrobe(p_user uuid, p_item text, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false); p profiles; it wardrobe_items; w player_wardrobe;
begin
  select * into it from wardrobe_items where id = p_item;
  if not found then
    perform bl_ag_fail('That clothing item doesn''t exist.', 'unknown_item');
  end if;
  p := bl_ag_target(p_user, true);
  delete from player_wardrobe where user_id = p_user and item_id = it.id returning * into w;
  if w.user_id is null then
    perform bl_ag_fail('They don''t own the ' || it.name || '.', 'not_owned');
  end if;
  delete from player_outfits where user_id = p_user and items::text like '%"' || it.id || '"%';   -- outfits that used it fall back to the everyday look
  perform bl_ag_log(v_admin, p_user, 'take_wardrobe', jsonb_build_object('item', it.id, 'name', it.name, 'paid', w.price_paid, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_take', 'Clothes removed', 'An admin took the ' || it.name || ' from your wardrobe.', v_reason);
  return jsonb_build_object('message', it.name || ' removed from @' || p.username || '.');
end $$;

-- ---------------------------------------------------------------------
-- 5. Hustle stall pass (the market-stall rental the vending hustles need)
-- ---------------------------------------------------------------------
create or replace function public.admin_give_hustle_pass(p_user uuid, p_pass text, p_hours int default 24, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false); p profiles; v_until timestamptz; v_old timestamptz;
begin
  if p_hours is null or p_hours < 1 or p_hours > 720 then
    perform bl_ag_fail('Hours go from 1 to 720.', 'bad_value');
  end if;
  if not exists (select 1 from hustles where pass_id = p_pass) then
    perform bl_ag_fail('That pass doesn''t exist.', 'bad_pass');
  end if;
  p := bl_ag_target(p_user);
  select until_at into v_old from hustle_passes where user_id = p_user and pass_id = p_pass;
  v_until := greatest(coalesce(v_old, bl_now()), bl_now()) + make_interval(hours => p_hours);
  insert into hustle_passes (user_id, pass_id, until_at) values (p_user, p_pass, v_until)
  on conflict (user_id, pass_id) do update set until_at = excluded.until_at;
  perform bl_ag_log(v_admin, p_user, 'grant_hustle_pass', jsonb_build_object('pass', p_pass, 'hours', p_hours, 'old_until', v_old, 'new_until', v_until, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'Stall pass', 'An admin gave you ' || p_hours || ' hours on your ' || p_pass || ' pass.', v_reason, jsonb_build_object('pass', p_pass));
  return jsonb_build_object('message', 'Gave @' || p.username || ' ' || p_hours || ' hours of the ' || p_pass || ' pass.', 'until', v_until);
end $$;

create or replace function public.admin_take_hustle_pass(p_user uuid, p_pass text, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false); p profiles; h hustle_passes;
begin
  p := bl_ag_target(p_user, true);
  delete from hustle_passes where user_id = p_user and pass_id = p_pass returning * into h;
  if h.user_id is null then
    perform bl_ag_fail('They don''t have that pass.', 'not_owned');
  end if;
  perform bl_ag_log(v_admin, p_user, 'take_hustle_pass', jsonb_build_object('pass', p_pass, 'was_until', h.until_at, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_take', 'Stall pass ended', 'An admin ended your ' || p_pass || ' pass.', v_reason);
  return jsonb_build_object('message', 'Pass removed from @' || p.username || '.');
end $$;

-- ---------------------------------------------------------------------
-- 6. Privileges
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'admin_give_item(uuid, text, int, text)', 'admin_take_item(uuid, text, int, text)',
    'admin_give_furniture(uuid, text, int, text)', 'admin_take_furniture(uuid, text, int, text)',
    'admin_give_garage(uuid, text, text)', 'admin_remove_garage(uuid, text)',
    'admin_give_wardrobe(uuid, text, text, text)', 'admin_take_wardrobe(uuid, text, text)',
    'admin_give_hustle_pass(uuid, text, int, text)', 'admin_take_hustle_pass(uuid, text, text)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
