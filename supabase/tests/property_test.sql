-- Own your home (20261103000100_property.sql, 20261103000200_property_links.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/property_test.sql
-- Groups: 1 catalogue + settings with labels · 2 past homes (return, furniture + upgrades back, expiry, give up) · 3 buying (quote, fees,
-- receipt, ledger, no rent, bills still charged) · 4 selling (no profit loop) · 5 building (needs plots, stages over time, plots locked,
-- finished home, cancel, block of flats units) · 6 listing + renting out (band, rent flows tenant -> landlord minus the cut, earnings,
-- notice, owed-rent eviction, no self-rent, leaving) · 7 upgrades stay with the house · 8 jail / visiting / hostel / owed rent ·
-- 9 admin (content tables, force end, audit) · 10 grants / RLS.
create or replace function pg_temp.hint_of(p_sql text) returns text
language plpgsql as $$
declare v_h text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics v_h = pg_exception_hint;
  return coalesce(v_h, sqlerrm);
end $$;

-- time travel; nobody has a rent day in the middle of the test unless a group sets one
create or replace function pg_temp.warp(p_seconds numeric) returns void
language plpgsql as $$ begin
  perform set_config('bl.test_offset_seconds', p_seconds::text, true);
  update profiles set rent_due_at = null where username like 'PR\_%';
end $$;

create or replace function pg_temp.mk(p_email text, p_name text, p_home text) returns uuid
language plpgsql as $$
declare u uuid := pg_temp.new_user(p_email);
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(u);
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home(p_home);
  update profiles set cash = 0, bank = 1000000000, rent_due_at = null, transfer_trusted = true where id = u;
  return u;
end $$;

create or replace function pg_temp.as_auth(p_uid uuid) returns void
language plpgsql as $$
begin
  perform pg_temp.login(p_uid);
  execute 'set local role authenticated';
end $$;
create or replace function pg_temp.as_super() returns void
language plpgsql as $$ begin execute 'reset role'; end $$;

create or replace function pg_temp.ledger_sum(p_uid uuid, p_reason text) returns bigint
language sql as $$ select coalesce(sum(delta), 0)::bigint from ledger where user_id = p_uid and reason = p_reason $$;

create or replace function pg_temp.give_plots(p_uid uuid, p_market text, p_qty int, p_cost bigint) returns void
language sql as $$
  insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at)
  values (p_uid, p_market, 'land', p_qty, p_cost, now(), now())
  on conflict (user_id, ref_id) where kind = any (array['savings','mmf','bond','stock','crypto','land'])
  do update set qty = invest_positions.qty + excluded.qty, cost = invest_positions.cost + excluded.cost
$$;

do $$
declare
  a  uuid; t uuid; s uuid; h uuid; ad uuid;
  r jsonb; v jsonb; n int; b0 bigint; b1 bigint; t0 bigint; p properties; q properties; p1 uuid; p2 uuid; bld uuid;
  v_price bigint; v_agent bigint; v_legal bigint; v_total bigint; pos invest_positions; rc int; w0 bigint; paid bigint; xx numeric; zz numeric;
  v_home text; wk date; blds jsonb; old_cost bigint;
begin
  -- settings pinned for the test
  update game_config set value = 'true' where key in ('house.move_enabled', 'house.upgrades_enabled', 'garage.enabled', 'property.enabled',
    'property.buy_enabled', 'property.build_enabled', 'property.rent_out_enabled', 'rent.enabled');
  update game_config set value = '4' where key = 'house.move_in_weeks';
  update game_config set value = '30' where key = 'house.return_days';
  update game_config set value = '0' where key = 'house.upgrade_time_pct';
  update game_config set value = '50' where key = 'house.upgrade_resale_pct';
  update game_config set value = '10' where key = 'house.upgrade_landlord_fee_pct';
  update game_config set value = '1' where key = 'house.upgrade_max_builds';
  update game_config set value = 'false' where key in ('economy.tax_enabled', 'economy.bills_enabled', 'economy.transfer_fees_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');
  update game_config set value = '1' where key = 'receipts.min_amount';
  update game_config set value = '100' where key = 'property.build_time_pct';
  update game_config set value = '20' where key = 'property.max_owned';
  update game_config set value = '3' where key = 'property.max_builds';
  perform pg_temp.warp(0);

  a  := pg_temp.mk('pr_a@prop.bl', 'PR_Owner', 'ekenwan_face_me');
  t  := pg_temp.mk('pr_t@prop.bl', 'PR_Tenant', 'aduwawa_face_me');
  s  := pg_temp.mk('pr_s@prop.bl', 'PR_Stranger', 'aduwawa_face_me');
  h  := pg_temp.mk('pr_h@prop.bl', 'PR_Hostel', 'uniben_hostel');
  ad := pg_temp.mk('pr_ad@prop.bl', 'PR_Admin', 'aduwawa_face_me');
  update profiles set is_admin = true where id = ad;

  -- 1. catalogue + settings ------------------------------------------------------------------------------------
  perform pg_temp.assert((select count(*) from property_areas where active) = 7, 'seven areas (the seven land markets)');
  perform pg_temp.assert(not exists (select 1 from property_areas a where a.land_market is not null and not exists (select 1 from invest_markets m where m.id = a.land_market and m.kind = 'land')), 'every area plot market exists');
  perform pg_temp.assert((select count(*) from property_types where active) = 8, 'eight home types');
  perform pg_temp.assert(not exists (select 1 from property_types t2 where not exists (select 1 from start_homes sh where sh.id = t2.template_home)), 'every type maps to an existing home layout');
  perform pg_temp.assert((select count(*) from property_offers where active) >= 50, 'prices by area and type');
  perform pg_temp.assert((select count(*) from property_designs where active) = 6, 'six designs');
  perform pg_temp.assert(exists (select 1 from property_designs where units = 6) and exists (select 1 from property_designs where units = 4), 'blocks of flats exist');
  -- coherent with the Invest land prices: a home costs at least one plot of the same area; a room is a few millions at Ekenwan / Okhoro
  perform pg_temp.assert(not exists (select 1 from property_offers o join property_areas a on a.id = o.area join invest_markets m on m.id = a.land_market where o.price < m.base_price), 'no home is cheaper than its plot');
  perform pg_temp.assert((select price from property_offers where id = 'ekenwan_room_fmiyf') between 2000000 and 5000000
                         and (select price from property_offers where id = 'okhoro_room_fmiyf') between 2000000 and 5000000, 'a room at Ekenwan / Okhoro is a few million');
  perform pg_temp.assert((select price from property_offers where id = 'ugbowo_flat_2bed') between 10000000 and 99000000
                         and (select price from property_offers where id = 'sapele_flat_3bed') between 10000000 and 99000000, 'a flat at Ugbowo / Sapele Road is tens of millions');
  perform pg_temp.assert((select price from property_offers where id = 'gra_duplex_5') >= 300000000, 'a GRA duplex is hundreds of millions');
  perform pg_temp.assert((select bl_prop_build_cost(d, a2) from property_designs d, property_areas a2 where d.id = 'bungalow_3' and a2.id = 'airport') = 42000000, 'bungalow cost at the base area');
  perform pg_temp.assert((select bl_prop_build_cost(d, g) > bl_prop_build_cost(d, e) from property_designs d, property_areas g, property_areas e where d.id = 'duplex_4' and g.id = 'gra' and e.id = 'ekenwan'), 'GRA builds cost more than Ekenwan');
  perform pg_temp.assert(not exists (select 1 from property_designs d join property_areas a2 on a2.land_market is not null
         join property_offers o on o.type_id = d.type_id and o.area = a2.id join invest_markets m on m.id = a2.land_market
         where d.units = 1 and o.price < (bl_prop_build_cost(d, a2) + d.plots * m.base_price)), 'a ready home never costs less than building it');
  perform pg_temp.assert(not exists (select 1 from game_config g where (g.key like 'property.%' or g.key = 'house.return_days')
          and (coalesce(g.label, '') = '' or coalesce(g.description, '') = '' or (g.kind <> 'bool' and (g.min is null or g.max is null)))
          and g.key not in ('property.earn_seeded', 'property.legacy_seeded')), 'every setting has label, description, min and max');
  perform pg_temp.assert((select count(*) from game_config where category = 'property') >= 25, 'settings in category property');
  perform pg_temp.assert((select category from game_config where key = 'house.return_days') = 'rent', 'return days sits with the rent settings');
  perform pg_temp.assert('rent_income' = any (bl_earn_reasons()), 'rent income is earned money');
  perform pg_temp.assert(not ('agent_fee' = any (bl_earn_reasons())) and not ('house_sell' = any (bl_earn_reasons())) and not ('rent_paid_player' = any (bl_earn_reasons())), 'fees, sales and rent paid are never earned');
  perform pg_temp.assert(bl_econ_category('house_buy') = 'Housing' and bl_econ_category('agent_fee') = 'Housing', 'dashboard category');
  perform pg_temp.assert(bl_ledger_label('house_buy', '{"label":"Bought: X"}') = 'Bought: X' and bl_ledger_label('rent_income', '{}') = 'Rent received', 'ledger labels');

  -- 2. past homes ------------------------------------------------------------------------------------------------
  perform pg_temp.login(a);
  select home_location_id into v_home from profiles where id = a;
  update profiles set cash = 0, bank = 900000000, location_id = home_location_id where id = a;
  perform house_upgrade_buy('ext_bedroom');
  perform house_upgrade_buy('paint_fresh');
  select coalesce(sum(price_paid), 0) into paid from player_house_upgrades where user_id = a;
  perform pg_temp.assert(paid > 0 and (select count(*) from player_house_upgrades where user_id = a and done_at is not null) = 2, 'two finished upgrades');
  r := furniture_place('own_stool', 1.0, 6.0, 0);
  perform pg_temp.assert((select x = 1.0 and z = 6.0 and not stored from player_house_furniture where owner_id = a and furniture_key = 'own_stool'), 'stool stands in the new room');
  b0 := (select bank from profiles where id = a);
  r := house_move('uselu_self_contain');
  perform pg_temp.assert((r->>'upgrade_refund')::bigint = 0 and (select bank from profiles where id = a) = b0 - (r->>'spent')::bigint, 'moving out refunds nothing');
  perform pg_temp.assert(exists (select 1 from player_past_homes where user_id = a and start_home = 'ekenwan_face_me'
                                 and jsonb_array_length(stash->'upgrades') = 2 and expires_at > bl_now() + interval '29 days'), 'the old home is a past home with its upgrades');
  perform pg_temp.assert(not exists (select 1 from player_house_upgrades where user_id = a), 'the new home starts plain');
  perform pg_temp.assert(house_options()->>'return_days' = '30', 'options carry the return days');
  perform pg_temp.assert((select hh->>'status' from jsonb_array_elements(house_options()->'homes') hh where hh->>'id' = 'ekenwan_face_me') = 'past', 'listed as a past home');
  -- back again: normal move-in fee, upgrades and the stool's spot return
  b0 := (select bank from profiles where id = a);
  r := house_move('ekenwan_face_me');
  perform pg_temp.assert((r->>'returned')::boolean and (r->>'upgrades_back')::int = 2, 'moved back: ' || r::text);
  perform pg_temp.assert((r->>'spent')::bigint = 6000 and (select bank from profiles where id = a) = b0 - 6000, 'the normal move-in fee (4 weeks of 1,500)');
  perform pg_temp.assert((select count(*) from player_house_upgrades where user_id = a and done_at is not null) = 2, 'finished upgrades are back');
  perform pg_temp.assert((select x = 1.0 and z = 6.0 and not stored from player_house_furniture where owner_id = a and furniture_key = 'own_stool'), 'furniture is back where it stood');
  perform pg_temp.assert(not exists (select 1 from player_past_homes where user_id = a and start_home = 'ekenwan_face_me'), 'the slot is used up');
  perform pg_temp.assert(exists (select 1 from player_past_homes where user_id = a and start_home = 'uselu_self_contain'), 'the self-contain is now the past home');
  perform pg_temp.assert(house_upgrade_home()->'done' @> '[{"id":"ext_bedroom"}]'::jsonb, 'the extension is drawn again');
  -- expiry pays the upgrades out (house.upgrade_resale_pct) and the slot goes
  perform house_move('uselu_self_contain');
  perform pg_temp.warp(31 * 86400);
  b0 := (select bank from profiles where id = a);
  r := house_options();
  perform pg_temp.assert((select hh->>'status' from jsonb_array_elements(r->'homes') hh where hh->>'id' = 'ekenwan_face_me') = 'available', 'expired past home is gone');
  perform pg_temp.assert((select bank from profiles where id = a) = b0 + floor(paid * 0.5), 'expiry pays out the upgrades at the resale %');
  perform pg_temp.assert(exists (select 1 from events e where e.user_id = a and e.kind = 'past_home_closed'), 'a player event says so');
  perform pg_temp.assert(pg_temp.hint_of($q$ select house_past_release('ekenwan_face_me') $q$) = 'not_found', 'nothing left to give up');
  -- expired homes cannot be returned to for free: moving there is a plain new rental (no upgrades)
  r := house_move('ekenwan_face_me');
  perform pg_temp.assert(not (r->>'returned')::boolean and (r->>'upgrades_back')::int = 0, 'after expiry a move is a plain rental');
  update game_config set value = '10' where key = 'house.return_days';
  perform house_move('uselu_self_contain');
  perform pg_temp.assert((select expires_at from player_past_homes where user_id = a and start_home = 'ekenwan_face_me') < bl_now() + interval '11 days', 'return days are admin-tunable');
  update game_config set value = '30' where key = 'house.return_days';
  perform pg_temp.warp(0);

  -- 3. buying ---------------------------------------------------------------------------------------------------
  perform pg_temp.login(a);
  update profiles set cash = 0, bank = 900000000 where id = a;
  v := property_quote_buy('ekenwan_room_fmiyf');
  perform pg_temp.assert((v->>'price')::bigint = 3000000 and (v->>'agent')::bigint = 90000 and (v->>'legal')::bigint = 45000 and (v->>'total')::bigint = 3135000 and (v->>'can_buy')::boolean,
                         'quote: price + 3% agent + 1.5% legal: ' || v::text);
  perform pg_temp.assert((v->>'rent_market')::bigint = 10500, 'the quote shows the market rent');
  perform pg_temp.assert(pg_temp.hint_of($q$ select property_quote_buy('nope') $q$) = 'bad_offer', 'unknown offer');
  update profiles set cash = 1000, bank = 100000 where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$ select property_buy('ekenwan_room_fmiyf') $q$) = 'not_enough_cash', 'cannot afford');
  perform pg_temp.assert(not (property_quote_buy('ekenwan_room_fmiyf')->>'can_buy')::boolean, 'quote says no');
  update profiles set cash = 0, bank = 900000000 where id = a;
  b0 := (select bank from profiles where id = a);
  r := property_buy('ekenwan_room_fmiyf');
  p1 := (r->>'property')::uuid;
  perform pg_temp.assert(b0 - (select bank from profiles where id = a) = 3135000, 'paid the total');
  perform pg_temp.assert(pg_temp.ledger_sum(a, 'house_buy') = -3000000 and pg_temp.ledger_sum(a, 'agent_fee') = -90000 and pg_temp.ledger_sum(a, 'legal_fee') = -45000, 'ledger rows per fee');
  perform pg_temp.assert(r->'receipt'->>'kind' = 'house' and (r->'receipt'->>'amount')::bigint = 3135000, 'receipt for the whole bill');
  perform pg_temp.assert(exists (select 1 from receipts where user_id = a and kind = 'house' and amount = 3135000), 'receipt kept');
  perform pg_temp.assert(not (select bool_or('house_buy' = any (bl_earn_reasons())) from ledger where user_id = a), 'buying is not earning');
  perform pg_temp.assert((select owner_id = a and basis = 3000000 and source = 'bought' and area = 'ekenwan' and not listed from properties where id = p1), 'property row');
  perform pg_temp.assert((select count(*) from properties where owner_id = a) = 1, 'one owned home');
  perform pg_temp.assert(bl_ledger_label('house_buy', (select meta from ledger where user_id = a and reason = 'house_buy' limit 1)) = 'Bought: Room in a face-me-I-face-you · Ekenwan', 'label names the home');
  -- live in it: no rent, same layout, the old rented home becomes a past home
  update profiles set cash = 0, bank = 900000000 where id = a;
  r := property_live_in(p1);
  perform pg_temp.assert((select start_home = 'ekenwan_face_me' and weekly_rent = 0 and location_id = home_location_id from profiles where id = a), 'moved in, no rent');
  perform pg_temp.assert((select role = 'owner' from player_residence where user_id = a), 'residence: owner');
  perform pg_temp.assert(exists (select 1 from player_past_homes where user_id = a and start_home = 'uselu_self_contain'), 'the home he left is a past home');
  perform pg_temp.assert((select x = 276 and y = 602 from locations where id = (select home_location_id from profiles where id = a)), 'the home sits in Ekenwan on the map');
  update profiles set rent_due_at = bl_now() - interval '1 hour' where id = a;
  b0 := (select bank from profiles where id = a);
  perform property_overview();
  perform pg_temp.assert((select bank from profiles where id = a) = b0 and not exists (select 1 from ledger where user_id = a and reason = 'rent' and created_at > bl_now() - interval '1 minute'), 'an owned home pays no rent');
  perform pg_temp.assert((select rent_due_at > bl_now() from profiles where id = a), 'the rent day just rolled on');
  -- house bills and ground rent are still charged
  update game_config set value = '-30' where key = 'economy.bill_grace_days';
  wk := bl_week_start();
  perform bl_bills_issue(a, wk);
  perform pg_temp.assert((select amount from player_bills where user_id = a and kind = 'house' and period = wk) = 450, 'house bill follows the rent of the same home type (30% of 1,500)');
  perform pg_temp.assert((select amount from player_bills where user_id = a and kind = 'property' and period = wk and ref = p1::text) = 3000, 'ground rent 0.1% of the value');
  perform pg_temp.assert(bl_ledger_label('ground_rent', '{"title":"Ground rent"}') like 'Bill: Ground rent%', 'ground rent label');
  -- upgrades on an owned home: no landlord fee; no tier upgrade
  v := house_upgrade_state();
  perform pg_temp.assert((v->>'landlord_fee_pct')::numeric = 0, 'no landlord fee on your own home');
  perform pg_temp.assert((select x->>'state' from jsonb_array_elements(v->'available') x where x->>'id' = 'tier_face_to_selfcon') = 'locked', 'no tier upgrade for an owned home');
  b0 := (select bank from profiles where id = a);
  perform house_upgrade_buy('borehole');
  perform pg_temp.assert(b0 - (select bank from profiles where id = a) = (select bl_house_upgrade_price(u, 'face_me') from house_upgrades u where u.id = 'borehole') and
                         (select price_paid from player_house_upgrades where user_id = a and upgrade_id = 'borehole') > 0, 'works cost the price only');
  -- the most homes one player can own
  update game_config set value = '1' where key = 'property.max_owned';
  perform pg_temp.assert(pg_temp.hint_of($q$ select property_buy('ekenwan_room_fmiyf') $q$) = 'too_many', 'max owned');
  update game_config set value = '20' where key = 'property.max_owned';
  perform pg_temp.assert(pg_temp.hint_of($q$ select property_buy('gra_room_fmiyf') $q$) = 'bad_offer', 'no such offer (no rooms in GRA)');

  -- 4. selling: never a profit ---------------------------------------------------------------------------------
  perform pg_temp.assert(pg_temp.hint_of(format('select property_sell(%L)', p1)) = 'live_here', 'cannot sell the home you live in');
  perform pg_temp.assert(pg_temp.hint_of(format('select property_sell(%L)', gen_random_uuid())) = 'not_yours', 'not yours');
  perform pg_temp.login(s);
  perform pg_temp.assert(pg_temp.hint_of(format('select property_sell(%L)', p1)) = 'not_yours', 'a stranger cannot sell it');
  perform pg_temp.login(a);
  update profiles set cash = 0, bank = 900000000 where id = a;
  perform house_move('ekenwan_face_me');       -- back to a city room
  perform pg_temp.assert(not exists (select 1 from player_residence where user_id = a) and (select stash is not null from properties where id = p1), 'moving out keeps the home and stashes its upgrades');
  v := (select bl_prop_sale(x) from properties x where x.id = p1);
  perform pg_temp.assert((v->>'gross')::bigint = 2550000 and (v->>'agent')::bigint = 51000 and (v->>'upgrades')::bigint = (select floor(sum((x->>'price_paid')::bigint) * 0.5) from properties pp, jsonb_array_elements(pp.stash->'upgrades') x where pp.id = p1), 'sale quote: 85% of the value, 2% agent, upgrades at the resale %');
  b0 := (select bank from profiles where id = a);
  r := property_sell(p1);
  perform pg_temp.assert((r->>'gross')::bigint = 2550000 and (r->>'agent')::bigint = 51000, 'sale: 85% of the value less 2% agent: ' || r::text);
  perform pg_temp.assert((r->>'upgrades')::bigint > 0 and (select bank from profiles where id = a) = b0 + (r->>'net')::bigint, 'the upgrades are paid at the resale %, net paid into the bank');
  perform pg_temp.assert(pg_temp.ledger_sum(a, 'house_sell') = 2550000 and pg_temp.ledger_sum(a, 'agent_fee') = -141000, 'ledger: sale and agent fee');
  perform pg_temp.assert(not exists (select 1 from properties where id = p1), 'the home is gone');
  perform pg_temp.assert((r->>'gross')::bigint + (r->>'upgrades')::bigint - (r->>'agent')::bigint < 3135000 + 3000000, 'no buy-then-sell profit');
  -- even a generous setting and a long wait can never pay more than the home cost
  update game_config set value = '95' where key = 'property.resale_pct';
  r := property_buy('ekenwan_room_fmiyf');
  p2 := (r->>'property')::uuid;
  perform pg_temp.warp(800 * 86400);
  v := (select bl_prop_sale(x) from properties x where x.id = p2);
  perform pg_temp.assert((select bl_prop_value(x) from properties x where x.id = p2) = 3300000, 'a kept home is worth 10% more at most');
  perform pg_temp.assert((v->>'gross')::bigint <= 3000000, 'the sale never pays more than the price paid: ' || v::text);
  update game_config set value = '85' where key = 'property.resale_pct';
  perform pg_temp.warp(0);
  update properties set acquired_at = bl_now() where id = p2;

  -- 5. building ------------------------------------------------------------------------------------------------
  perform pg_temp.login(a);
  update profiles set cash = 0, bank = 900000000 where id = a;
  v := property_quote_build('bungalow_2', 'ekenwan');
  perform pg_temp.assert((v->>'cost')::bigint = 25200000 and (v->>'permit')::bigint = 504000 and not (v->>'can_build')::boolean
                         and v->>'reason' like 'You need 1 free plot%', 'quote without plots: ' || v::text);
  perform pg_temp.assert(pg_temp.hint_of($q$ select property_build_start('bungalow_2', 'ekenwan') $q$) = 'no_plots', 'needs plots');
  perform pg_temp.give_plots(a, 'land_airport', 5, 17500000);
  perform pg_temp.assert(pg_temp.hint_of($q$ select property_build_start('bungalow_2', 'ekenwan') $q$) = 'no_plots', 'plots in another area do not count');
  perform pg_temp.give_plots(a, 'land_ekenwan', 4, 4800000);
  v := property_quote_build('bungalow_2', 'ekenwan');
  perform pg_temp.assert((v->>'can_build')::boolean and (v->'land'->>'free')::int = 4 and (v->>'hours')::numeric = 12, 'quote with plots');
  b0 := (select bank from profiles where id = a);
  r := property_build_start('bungalow_2', 'ekenwan');
  bld := (r->>'build')::uuid;
  perform pg_temp.assert(b0 - (select bank from profiles where id = a) = 25704000, 'paid works + plan approval');
  perform pg_temp.assert(pg_temp.ledger_sum(a, 'build_cost') = -25200000 and pg_temp.ledger_sum(a, 'legal_fee') <= -504000, 'ledger: build cost and plan fee');
  perform pg_temp.assert(r->'receipt'->>'kind' = 'house' and (r->'receipt'->>'amount')::bigint = 25704000, 'receipt');
  perform pg_temp.assert((select status = 'building' and plots = 1 and land_cost = 1200000 and ready_at > bl_now() + interval '11 hours' from property_builds where id = bld), 'a build is going: land share 1,200,000');
  perform pg_temp.assert(bl_land_locked(a, 'land_ekenwan') = 1, 'one plot is locked');
  -- plots under a build cannot be sold or listed: 4 held, 1 locked
  perform pg_temp.assert(pg_temp.hint_of($q$ select invest_land_sell('land_ekenwan', 4) $q$) = 'plots_locked', 'cannot sell the plot under the build');
  perform pg_temp.assert(pg_temp.hint_of($q$ select bl_market_take(auth.uid(), 'land', 'land_ekenwan', 4, null) $q$) = 'plots_locked', 'cannot list it on the Market either');
  perform pg_temp.assert(pg_temp.hint_of($q$ select invest_land_sell('land_ekenwan', 1) $q$) = 'ok', 'a free plot sells fine');
  -- stages over real time
  v := property_overview();
  perform pg_temp.assert(v->'builds'->0->>'stage' = 'Foundation' and jsonb_array_length(v->'builds'->0->'stages') = 4, 'stage 1: Foundation');
  perform pg_temp.warp(4 * 3600);
  perform pg_temp.assert(property_overview()->'builds'->0->>'stage' = 'Blockwork', 'after 4 h: Blockwork');
  perform pg_temp.warp(8 * 3600);
  perform pg_temp.assert(property_overview()->'builds'->0->>'stage' = 'Roofing', 'after 8 h: Roofing');
  perform pg_temp.warp(10 * 3600);
  v := property_overview();
  perform pg_temp.assert(v->'builds'->0->>'stage' = 'Finishing' and (v->'builds'->0->>'progress')::int between 80 and 90, 'after 10 h: Finishing');
  perform pg_temp.assert(not exists (select 1 from properties where build_id = bld), 'not a home yet');
  perform pg_temp.warp(12 * 3600 + 60);
  v := property_overview();
  perform pg_temp.assert(jsonb_array_length(v->'builds') = 0 and (select count(*) from properties where build_id = bld) = 1, 'finished: it is an owned home now');
  select * into p from properties where build_id = bld;
  perform pg_temp.assert(p.source = 'built' and p.owner_id = a and p.type_id = 'bungalow_2' and p.basis = 26400000 and p.unit_no is null, 'built home: cost + land share is its price');
  perform pg_temp.assert(exists (select 1 from events e where e.user_id = a and e.kind = 'build_done'), 'builders don finish event');
  perform pg_temp.assert(bl_land_locked(a, 'land_ekenwan') = 1 and (select status = 'done' from property_builds where id = bld), 'the plot stays locked under the house');
  perform pg_temp.assert(pg_temp.hint_of($q$ select invest_land_sell('land_ekenwan', 3) $q$) = 'plots_locked', 'two free plots only (3 held, 1 locked)');
  -- cancel a second build
  perform pg_temp.warp(12 * 3600 + 60);
  b0 := (select bank from profiles where id = a);
  r := property_build_start('bungalow_3', 'ekenwan');
  perform pg_temp.assert(bl_land_locked(a, 'land_ekenwan') = 2, 'second build locks a second plot');
  b0 := (select bank from profiles where id = a);
  r := property_build_cancel((r->>'build')::uuid);
  perform pg_temp.assert((r->>'refund')::bigint = floor(37800000 * 0.6) and (select bank from profiles where id = a) = b0 + floor(37800000 * 0.6), 'cancel refunds 60% of the works');
  perform pg_temp.assert(bl_land_locked(a, 'land_ekenwan') = 1 and pg_temp.ledger_sum(a, 'build_refund') = floor(37800000 * 0.6), 'plot free again; ledger row');
  perform pg_temp.assert(pg_temp.hint_of(format('select property_build_cancel(%L)', bld)) = 'not_building', 'a finished build cannot be cancelled');
  perform pg_temp.assert(pg_temp.hint_of($q$ select property_build_start('nope', 'ekenwan') $q$) = 'bad_design', 'unknown design');
  update game_config set value = 'false' where key = 'property.build_enabled';
  perform pg_temp.assert(pg_temp.hint_of($q$ select property_build_start('bungalow_2', 'ekenwan') $q$) = 'property_disabled', 'switch off');
  update game_config set value = 'true' where key = 'property.build_enabled';
  -- the build admin time dial
  update game_config set value = '0' where key = 'property.build_time_pct';
  perform pg_temp.give_plots(a, 'land_ugbowo', 3, 18000000);
  r := property_build_start('flats_block_4', 'ugbowo');
  perform pg_temp.assert((select count(*) from properties where owner_id = a and source = 'built' and type_id = 'flat_2bed') = 4, 'time 0%: a block of flats is four units at once');
  update game_config set value = '100' where key = 'property.build_time_pct';
  perform pg_temp.assert((select array_agg(unit_no order by unit_no) from properties where owner_id = a and type_id = 'flat_2bed') = array[1, 2, 3, 4], 'units are numbered');
  perform pg_temp.assert((select count(distinct build_id) from properties where owner_id = a and type_id = 'flat_2bed') = 1 and (select count(distinct basis) from properties where owner_id = a and type_id = 'flat_2bed') = 1, 'one build, equal shares');
  perform pg_temp.assert((select basis from properties where owner_id = a and type_id = 'flat_2bed' and unit_no = 1) = floor((97750000 + 18000000.0 * 3 / 3) / 4), 'unit basis = (build cost + land share) / 4');
  perform pg_temp.assert(bl_prop_name((select x from properties x where owner_id = a and unit_no = 2)) like '%(unit 2)', 'unit names');
  perform pg_temp.assert(bl_land_locked(a, 'land_ugbowo') = 3, 'three plots carry the block');
  -- selling units: the plots come free only when the last unit is sold
  update profiles set cash = 0, bank = 900000000 where id = a;
  for n in 1..3 loop
    perform property_sell((select id from properties where owner_id = a and type_id = 'flat_2bed' and unit_no = n));
  end loop;
  perform pg_temp.assert(bl_land_locked(a, 'land_ugbowo') = 3 and (select status = 'done' from property_builds where design_id = 'flats_block_4' and owner_id = a), 'plots stay locked while a unit is left');
  perform property_sell((select id from properties where owner_id = a and type_id = 'flat_2bed' and unit_no = 4));
  perform pg_temp.assert((select status = 'sold' from property_builds where design_id = 'flats_block_4' and owner_id = a) and bl_land_locked(a, 'land_ugbowo') = 0
                         and not exists (select 1 from invest_positions where user_id = a and ref_id = 'land_ugbowo'), 'last unit sold: the plots went with the house');
  -- the rooms block (six self-contains) at Ekenwan from the plots he still has
  update game_config set value = '0' where key = 'property.build_time_pct';
  r := property_build_start('rooms_block_6', 'ekenwan');
  update game_config set value = '100' where key = 'property.build_time_pct';
  perform pg_temp.assert((select count(*) from properties where owner_id = a and type_id = 'self_contain' and source = 'built') = 6, 'six self-contain units');
  perform pg_temp.assert(pg_temp.hint_of($q$ select property_build_start('rooms_block_6', 'ekenwan') $q$) = 'no_plots', 'no plots left for another');

  perform pg_temp.warp(0);
  -- 6. renting out ---------------------------------------------------------------------------------------------
  perform pg_temp.login(a);
  update profiles set cash = 0, bank = 900000000 where id = a;
  select * into p from properties where owner_id = a and type_id = 'bungalow_2' limit 1;     -- the built bungalow
  r := property_buy('ekenwan_room_fmiyf');
  p1 := (r->>'property')::uuid;
  update properties set acquired_at = bl_now() where id = p1;
  v := (select bl_prop_card(x) from properties x where x.id = p1);
  perform pg_temp.assert((v->>'market_rent')::bigint = 10500 and (v->>'rent_min')::bigint = 5300 and (v->>'rent_max')::bigint = 15800, 'band around the market rent: ' || v::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select property_list(%L, 1000, 0)', p1)) = 'rent_band', 'too cheap');
  perform pg_temp.assert(pg_temp.hint_of(format('select property_list(%L, 100000, 0)', p1)) = 'rent_band', 'too dear');
  perform pg_temp.assert(pg_temp.hint_of(format('select property_list(%L, 10000, 90000)', p1)) = 'caution_max', 'caution above 8 weeks');
  perform pg_temp.login(s);
  perform pg_temp.assert(pg_temp.hint_of(format('select property_list(%L, 10000, 0)', p1)) = 'not_yours', 'only the owner lists');
  perform pg_temp.login(a);
  r := property_list(p1, 10000, 20000);
  perform pg_temp.assert((select listed and listed_rent = 10000 and caution = 20000 from properties where id = p1), 'listed');
  select * into q from properties where owner_id = a and type_id = 'bungalow_2' limit 1;
  perform pg_temp.assert(pg_temp.hint_of(format('select property_list(%L, %s, 0)', q.id, bl_prop_market_rent(q))) = 'ok', 'a second home can be listed (the built bungalow: market rent ' || bl_prop_market_rent(q) || ')');
  -- a new account cannot let (same trust rule as the Market)
  update profiles set transfer_trusted = false, created_at = now() where id = a;
  perform pg_temp.assert(pg_temp.hint_of(format('select property_list(%L, 10000, 0)', p1)) = 'new_account', 'new accounts cannot let homes yet');
  update profiles set transfer_trusted = true where id = a;
  -- the listing board
  perform pg_temp.login(t);
  v := property_listings();
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v->'listings') x where x->>'id' = p1::text and x->>'landlord' = 'PR_Owner' and (x->>'rent')::bigint = 10000), 'the listing shows with its landlord');
  perform pg_temp.assert(jsonb_array_length(property_listings('ugbowo')->'listings') = 0, 'area filter');
  perform pg_temp.assert(jsonb_array_length(property_listings('ekenwan', 9000)->'listings') = 0 and jsonb_array_length(property_listings('ekenwan', 10000)->'listings') >= 1, 'price filter');
  perform pg_temp.assert(jsonb_array_length(property_listings(null, null, 'duplex')->'listings') = 0, 'kind filter');
  perform pg_temp.login(a);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(property_listings()->'listings') x where x->>'id' = p1::text), 'your own listing is not in your rent list');
  -- no self-renting
  perform pg_temp.assert(pg_temp.hint_of(format('select property_rent(%L)', p1)) = 'own_property', 'cannot rent from yourself');
  -- the quote shows every fee
  perform pg_temp.login(t);
  update profiles set cash = 0, bank = 500000, location_id = home_location_id where id = t;
  v := property_rent_quote(p1);
  perform pg_temp.assert((v->>'advance')::bigint = 10000 and (v->>'agent')::bigint = 10000 and (v->>'caution')::bigint = 20000 and (v->>'total')::bigint = 40000 and (v->>'can_rent')::boolean,
                         'rent quote: caution 20,000 + 1 week 10,000 + agent 10,000: ' || v::text);
  update profiles set bank = 30000 where id = t;
  perform pg_temp.assert(pg_temp.hint_of(format('select property_rent(%L)', p1)) = 'not_enough_cash', 'cannot afford the move-in');
  update profiles set bank = 500000 where id = t;
  b0 := (select bank from profiles where id = t);
  r := property_rent(p1);
  perform pg_temp.assert(b0 - (select bank from profiles where id = t) = 40000, 'tenant paid 40,000');
  perform pg_temp.assert(pg_temp.ledger_sum(t, 'rent_caution') = -20000 and pg_temp.ledger_sum(t, 'rent_paid_player') = -10000 and pg_temp.ledger_sum(t, 'agent_fee') = -10000, 'tenant ledger');
  perform pg_temp.assert(r->'receipt'->>'kind' = 'house' and (r->'receipt'->>'amount')::bigint = 40000, 'tenant receipt');
  perform pg_temp.assert((select start_home = 'ekenwan_face_me' and weekly_rent = 10000 and location_id = home_location_id from profiles where id = t), 'tenant lives there');
  perform pg_temp.assert((select role = 'tenant' and rent = 10000 and caution = 20000 and landlord_id = a from player_residence where user_id = t), 'residence: tenant');
  perform pg_temp.assert(exists (select 1 from player_past_homes where user_id = t and start_home = 'aduwawa_face_me'), 'his old room is a past home');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(property_listings()->'listings') x where x->>'id' = p1::text), 'taken homes leave the board');
  -- the landlord is paid the next time he plays: rent in advance minus the agent cut (5%)
  perform pg_temp.assert((select sum(gross) from property_income where owner_id = a and collected_at is null) = 10000, 'rent waits for the landlord');
  perform pg_temp.login(a);
  b0 := (select bank from profiles where id = a);
  v := property_overview();
  perform pg_temp.assert((select bank from profiles where id = a) = b0 + 9500, 'landlord: 10,000 rent less the 5% agent cut');
  perform pg_temp.assert(pg_temp.ledger_sum(a, 'rent_income') = 10000 and exists (select 1 from ledger where user_id = a and reason = 'agent_fee' and delta = -500), 'landlord ledger: income and cut');
  perform pg_temp.assert(not exists (select 1 from property_income where owner_id = a and collected_at is null), 'collected once');
  perform pg_temp.assert((select (x->'occupant'->>'username') = 'PR_Tenant' and (x->>'earned')::bigint = 10000 from jsonb_array_elements(v->'properties') x where x->>'id' = p1::text), 'dashboard shows the tenant and the income');
  perform pg_temp.assert((bl_week_earned(a, bl_week_start()) >= 10000), 'rent income counts as earnings');
  -- the landlord cannot walk into the tenant's home
  perform pg_temp.assert(pg_temp.hint_of(format('select house_upgrade_home(%L)', t)) = 'not_allowed', 'no entry without an invite');
  -- tenant protections: no listing changes, no sale, no moving in while rented
  perform pg_temp.assert(pg_temp.hint_of(format('select property_list(%L, 12000, 0)', p1)) = 'tenant_inside', 'rent cannot change mid-tenancy');
  perform pg_temp.assert(pg_temp.hint_of(format('select property_sell(%L)', p1)) = 'tenant_inside', 'cannot sell over a tenant');
  perform pg_temp.assert(pg_temp.hint_of(format('select property_live_in(%L)', p1)) = 'tenant_inside', 'cannot move in over a tenant');
  -- the tenant cannot do works in the landlord's home
  perform pg_temp.login(t);
  v := house_upgrade_state();
  perform pg_temp.assert(not (v->>'can_upgrade')::boolean and v->>'reason' like '%landlord%', 'tenant cannot upgrade');
  perform pg_temp.assert(pg_temp.hint_of($q$ select house_upgrade_buy('paint_fresh') $q$) in ('locked', 'not_for_this_home'), 'tenant works refused');
  -- rent day: the tenant pays the landlord
  update profiles set rent_due_at = bl_now() - interval '1 hour', bank = 100000, cash = 0 where id = t;
  b0 := (select bank from profiles where id = t);
  perform property_overview();
  perform pg_temp.assert(b0 - (select bank from profiles where id = t) = 10000 and exists (select 1 from ledger where user_id = t and reason = 'rent_paid_player' and delta = -10000 and bl_ledger_label(reason, meta) = 'Rent to landlord'), 'tenant paid a week on the rent day');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = t and reason = 'rent' and created_at > bl_now() - interval '1 minute'), 'not city rent');
  perform pg_temp.login(a);
  b0 := (select bank from profiles where id = a);
  perform property_overview();
  perform pg_temp.assert((select bank from profiles where id = a) = b0 + 9500, 'weekly rent reached the landlord, minus the cut');
  -- the owner can also collect from a tenant who never logged in (his dashboard charges the due rent first)
  update profiles set rent_due_at = bl_now() - interval '1 hour' where id = t;
  b0 := (select bank from profiles where id = a);
  perform property_overview();
  perform pg_temp.assert((select bank from profiles where id = a) = b0 + 9500 and (select bank from profiles where id = t) = b0 * 0 + 80000, 'the landlord''s dashboard collects from an absent tenant');
  -- a tenant who stops paying: owed rent grows, then the existing owed-rent rule moves him out and the landlord keeps the caution
  perform pg_temp.login(t);
  update profiles set bank = 0, cash = 0, rent_due_at = bl_now() - interval '1 hour' where id = t;
  perform property_overview();
  perform pg_temp.assert((select rent_owed from profiles where id = t) = 10000 and exists (select 1 from player_residence where user_id = t), 'owes a week, still inside (3 weeks needed)');
  perform pg_temp.assert((select weekly_rent from profiles where id = t) = 10000, 'rent stays');
  update profiles set rent_owed = 30000 where id = t;
  perform pg_temp.login(a);
  b0 := (select bank from profiles where id = a);
  perform pg_temp.login(t);
  perform property_overview();
  perform pg_temp.assert(not exists (select 1 from player_residence where user_id = t) and (select start_home = 'aduwawa_face_me' and rent_owed = 0 from profiles where id = t), 'evicted for owed rent, back in the old room');
  perform pg_temp.assert(not exists (select 1 from player_past_homes where user_id = t and start_home = 'aduwawa_face_me'), 'the past home was used');
  perform pg_temp.assert(exists (select 1 from property_events where property_id = p1 and kind = 'tenancy_ended' and detail->>'why' = 'owed'), 'logged');
  perform pg_temp.login(a);
  v := property_overview();
  perform pg_temp.assert((select bank from profiles where id = a) = b0 + 19000, 'the landlord kept the caution: 20,000 less the cut');
  perform pg_temp.assert((select listed and not exists (select 1 from player_residence where property_id = p1) from properties where id = p1), 'vacant and still listed');
  perform pg_temp.assert(exists (select 1 from events e where e.user_id = a and e.kind = 'tenancy_ended'), 'landlord told');
  -- notice: not instant; the tenant can leave any time
  perform pg_temp.login(t);
  update profiles set bank = 500000, cash = 0, location_id = home_location_id where id = t;
  perform property_rent(p1);
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select property_give_notice(%L)', p1)) = 'ok', 'notice given');
  perform pg_temp.assert((select ends_at > bl_now() + interval '2 days 23 hours' and ends_at < bl_now() + interval '3 days 1 hour' and ended_by = 'landlord' from player_residence where user_id = t), 'three days');
  perform pg_temp.assert(pg_temp.hint_of(format('select property_give_notice(%L)', p1)) = 'already_notice', 'one notice at a time');
  perform pg_temp.login(t);
  perform property_overview();
  perform pg_temp.assert(exists (select 1 from player_residence where user_id = t), 'the tenant is still in during the notice');
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select property_cancel_notice(%L)', p1)) = 'ok', 'a notice can be withdrawn');
  perform pg_temp.assert((select ends_at is null from player_residence where user_id = t), 'and it is gone');
  perform property_give_notice(p1);
  perform pg_temp.warp(3 * 86400 + 3600);
  perform pg_temp.login(t);
  b0 := (select bank from profiles where id = t);
  perform property_overview();
  perform pg_temp.assert(not exists (select 1 from player_residence where user_id = t), 'the notice ran out: tenant moved out');
  perform pg_temp.assert((select bank from profiles where id = t) = b0 + 20000 and exists (select 1 from ledger where user_id = t and reason = 'rent_caution' and delta = 20000), 'caution back');
  perform pg_temp.assert((select not listed from properties where id = p1), 'taken off the market after a notice');
  perform pg_temp.warp(0);
  -- tenants may leave any time
  perform pg_temp.login(a);
  perform property_list(p1, 10000, 0);
  perform pg_temp.login(t);
  update profiles set bank = 500000, cash = 0, location_id = home_location_id where id = t;
  perform property_rent(p1);
  b0 := (select bank from profiles where id = t);
  perform house_move('aduwawa_face_me');
  perform pg_temp.assert(not exists (select 1 from player_residence where user_id = t) and (select start_home = 'aduwawa_face_me' from profiles where id = t), 'tenant left');
  perform pg_temp.assert(exists (select 1 from events e where e.user_id = a and e.kind = 'tenant_left'), 'landlord told');
  -- no renting from your own tenant
  perform pg_temp.login(a);
  perform property_list(p1, 10000, 0);
  perform pg_temp.login(t);
  update profiles set bank = 500000, cash = 0, location_id = home_location_id where id = t;
  perform property_rent(p1);
  select * into q from properties where owner_id = a and type_id = 'self_contain' and unit_no = 1;
  perform pg_temp.login(a);
  perform pg_temp.login(t);
  update profiles set location_id = home_location_id where id = t;
  -- (t owns nothing yet: buy and list, then a, his landlord, tries to rent it)
  update profiles set bank = 900000000 where id = t;
  r := property_buy('ekenwan_room_fmiyf');
  perform property_list((r->>'property')::uuid, 10500, 0);
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select property_rent(%L)', (r->>'property')::uuid)) = 'own_tenant', 'a landlord cannot rent from his own tenant');
  -- block units are listed one by one
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select property_list(%L, %s, 0)', q.id, bl_prop_market_rent(q))) = 'ok', 'a unit can be listed');
  perform pg_temp.login(s);
  update profiles set cash = 0, bank = 900000000, location_id = home_location_id where id = s;
  r := property_rent(q.id);
  perform pg_temp.assert((select role = 'tenant' and property_id = q.id from player_residence where user_id = s), 'a unit has its own tenant');
  perform pg_temp.login(a);
  v := property_overview();
  perform pg_temp.assert((select count(*) from jsonb_array_elements(v->'properties') x where x->'occupant' is not null and x->'occupant'->>'role' = 'tenant') = 2, 'dashboard: two tenants');
  -- an absent tenant: the notice runs out while the tenant is away (visiting): not moved until he is home
  -- (covered in group 8)

  -- 7. the house keeps its upgrades ------------------------------------------------------------------------------
  perform pg_temp.login(a);
  update profiles set cash = 0, bank = 900000000, location_id = home_location_id where id = a;
  r := property_buy('ekenwan_room_fmiyf');
  p2 := (r->>'property')::uuid;
  perform property_live_in(p2);
  perform house_upgrade_buy('paint_fresh');
  select price_paid into paid from player_house_upgrades where user_id = a and upgrade_id = 'paint_fresh';
  perform house_move('ekenwan_face_me');
  perform pg_temp.assert((select jsonb_array_length(stash->'upgrades') = 1 from properties where id = p2) and not exists (select 1 from player_house_upgrades where user_id = a), 'the paint stays with the house');
  perform property_list(p2, 10500, 0);
  perform pg_temp.login(h);
  update profiles set cash = 0, bank = 900000000, location_id = home_location_id where id = h;
  perform property_rent(p2);
  perform pg_temp.assert((select price_paid = 0 and done_at is not null from player_house_upgrades where user_id = h and upgrade_id = 'paint_fresh'), 'the tenant gets the finished paint, worth nothing to him');
  perform pg_temp.assert(house_upgrade_home()->'done' @> '[{"id":"paint_fresh"}]'::jsonb, 'and sees it');
  perform house_move('uniben_hostel');
  perform pg_temp.assert(not exists (select 1 from player_house_upgrades where user_id = h) and (select jsonb_array_length(stash->'upgrades') = 1 from properties where id = p2), 'the tenant leaves with nothing; the house keeps its paint');
  perform pg_temp.assert(exists (select 1 from player_past_homes where user_id = h and start_home = 'ekenwan_face_me') = false, 'a rented player home is never a past home of its template');
  perform pg_temp.login(a);
  perform property_unlist(p2);
  perform property_live_in(p2);
  perform pg_temp.assert((select price_paid = paid from player_house_upgrades where user_id = a and upgrade_id = 'paint_fresh'), 'the owner has his paint back at its original price');
  -- a home the owner left for good keeps everything: owned homes are never lost
  perform pg_temp.warp(200 * 86400);
  perform house_move('ekenwan_face_me');
  perform pg_temp.assert(exists (select 1 from properties where id = p2 and jsonb_array_length(stash->'upgrades') = 1), 'an owned home never expires');
  perform pg_temp.warp(0);
  -- furniture spots return to an owned home too
  perform property_live_in(p2);
  r := furniture_place('own_stool', 1.0, 3.0, 0);
  perform house_move('ekenwan_face_me');
  r := property_live_in(p2);
  perform pg_temp.assert((select x = 1.0 and z = 3.0 and not stored from player_house_furniture where owner_id = a and furniture_key = 'own_stool'), 'the stool stands where it did in the owned home');
  perform house_move('ekenwan_face_me');
  r := property_sell(p2);
  perform pg_temp.assert(pg_temp.hint_of(format('select property_sell(%L)', p2)) = 'not_yours', 'sold');

  -- 8. jail / visiting / hostel / owed rent -------------------------------------------------------------------------
  perform pg_temp.login(a);
  update profiles set cash = 0, bank = 900000000, location_id = home_location_id, jailed_until = bl_now() + interval '10 minutes' where id = a;
  perform pg_temp.assert(pg_temp.hint_of($q$ select property_buy('ekenwan_room_fmiyf') $q$) = 'jailed', 'no buying from jail');
  perform pg_temp.assert(pg_temp.hint_of(format('select property_live_in(%L)', p1)) = 'jailed', 'no moving from jail');
  perform pg_temp.assert(pg_temp.hint_of($q$ select property_build_start('bungalow_2', 'ekenwan') $q$) = 'jailed', 'no building from jail');
  update profiles set jailed_until = null where id = a;
  perform pg_temp.login(s);
  update profiles set home_visit_host_id = a where id = s;
  perform pg_temp.assert(pg_temp.hint_of(format('select property_rent(%L)', p1)) = 'visiting', 'no renting while visiting');
  update profiles set home_visit_host_id = null where id = s;
  update profiles set rent_owed = 5000 where id = s;
  perform pg_temp.assert(pg_temp.hint_of(format('select property_rent(%L)', p1)) = 'rent_owed', 'owed rent first');
  update profiles set rent_owed = 0 where id = s;
  -- the hostel: a hostel student can buy and live in a home, and the hostel room is a past home he can return to
  perform pg_temp.login(h);
  update profiles set cash = 0, bank = 900000000, location_id = home_location_id, home_visit_host_id = null where id = h;
  r := property_buy('ekenwan_room_fmiyf');
  perform property_live_in((r->>'property')::uuid);
  perform pg_temp.assert(exists (select 1 from player_past_homes where user_id = h and start_home = 'uniben_hostel'), 'the hostel room is a past home');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(house_upgrade_state()->'available') x) > 0 and bl_housing_kind('hostel_uniben') = 'hostel', 'hostel kind is unchanged');
  perform house_move('uniben_hostel');
  perform pg_temp.assert((select start_home = 'uniben_hostel' from profiles where id = h), 'back in the hostel');
  perform pg_temp.assert((select (house_upgrade_state()->>'can_upgrade')::boolean) = false, 'the hostel can never be upgraded');
  -- a tenant who is away (visiting) is not moved out by a notice that ran out; an admin cannot end it until he is home
  perform pg_temp.login(a);
  update profiles set bank = 900000000, cash = 0 where id = a;
  r := property_buy('ekenwan_room_fmiyf');
  p2 := (r->>'property')::uuid;
  perform property_list(p2, 10500, 0);
  perform pg_temp.login(s);
  update profiles set cash = 0, bank = 900000000, location_id = home_location_id where id = s;
  perform property_rent(p2);
  perform pg_temp.login(a);
  perform property_give_notice(p2);
  perform pg_temp.warp(4 * 86400);
  update profiles set home_visit_host_id = a where id = s;
  perform pg_temp.assert(not bl_tenancy_tick(s) and exists (select 1 from player_residence where user_id = s and property_id = p2), 'away tenants stay put');
  perform pg_temp.login(ad);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_property_end_tenancy(%L, ''test'')', p2)) = 'tenant_away', 'admin waits for the tenant to be home');
  update profiles set home_visit_host_id = null where id = s;
  perform pg_temp.warp(0);

  -- 9. admin ------------------------------------------------------------------------------------------------------
  perform pg_temp.login(ad);
  v := admin_property_overview();
  perform pg_temp.assert((v->'stats'->>'tenancies')::int >= 2 and jsonb_typeof(v->'listings') = 'array' and jsonb_array_length(v->'events') > 0, 'admin sees tenancies and events');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v->'tenancies') x where x->>'tenant' = 'PR_Stranger' and x->>'owner' = 'PR_Owner'), 'tenancy row names both sides');
  r := admin_property_end_tenancy(p2, 'rent dispute');
  perform pg_temp.assert(not exists (select 1 from player_residence where property_id = p2), 'the tenancy is ended');
  perform pg_temp.assert(exists (select 1 from admin_audit where admin_id = ad and action = 'property_end_tenancy' and target_user = s and data->>'reason' = 'rent dispute'), 'audited');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = s and reason = 'rent_caution' and delta = 0) is false, 'no empty ledger rows');
  perform pg_temp.assert((select not listed from properties where id = p2), 'an admin end takes the home off the market');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_property_end_tenancy(%L, '''')', p2)) = 'no_tenant', 'nobody left to end');
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_property_end_tenancy(%L, '''')', p2)) = 'not_admin', 'players cannot end tenancies');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_property_overview() $q$) = 'not_admin', 'players cannot read the admin view');
  perform pg_temp.assert(bl_admin_table_spec('property_offers') is not null and bl_admin_table_spec('property_designs') is not null
                         and bl_admin_table_spec('property_areas') is not null and bl_admin_table_spec('property_types') is not null, 'content tables are editable');
  perform pg_temp.login(ad);
  r := admin_row_upsert('property_offers', jsonb_build_object('id', 'ekenwan_room_fmiyf', 'price', 3300000));
  perform pg_temp.assert((select price from property_offers where id = 'ekenwan_room_fmiyf') = 3300000, 'an admin edits a price');
  perform pg_temp.assert((property_quote_buy('ekenwan_room_fmiyf')->>'price')::bigint = 3300000, 'the quote follows');
  r := admin_row_upsert('property_designs', jsonb_build_object('id', 'bungalow_2', 'base_cost', 30000000, 'stages', '[{"name":"All","pct":100}]'::jsonb));
  perform pg_temp.assert((select bl_prop_build_cost(d, a2) from property_designs d, property_areas a2 where d.id = 'bungalow_2' and a2.id = 'airport') = 30000000, 'design cost edited');
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_row_upsert('property_offers', '{"id":"x","price":1}'::jsonb) $q$) = 'not_admin', 'players cannot edit prices');

  -- 10. grants / RLS ------------------------------------------------------------------------------------------------
  perform pg_temp.assert(not has_function_privilege('anon', 'public.property_buy(text)', 'execute') and not has_function_privilege('anon', 'public.property_overview()', 'execute')
                         and not has_function_privilege('anon', 'public.house_move(text)', 'execute') and not has_function_privilege('anon', 'public.house_options()', 'execute'), 'anon cannot call the player RPCs');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.property_buy(text)', 'execute') and has_function_privilege('authenticated', 'public.property_rent(uuid)', 'execute')
                         and has_function_privilege('authenticated', 'public.property_build_start(text, text)', 'execute') and has_function_privilege('authenticated', 'public.house_past_release(text)', 'execute'), 'players can call them');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_home_enter(uuid, public.start_homes, uuid, text, bigint, bigint, uuid, bigint)', 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_property_tick(uuid)', 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_tenancy_end(uuid, text)', 'execute')
                         and not has_function_privilege('anon', 'public.bl_property_collect(uuid)', 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_past_home_close(uuid, text, text)', 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_land_locked(uuid, text)', 'execute'), 'bl_ helpers are private');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.admin_property_overview(int)', 'execute') and has_function_privilege('authenticated', 'public.admin_property_end_tenancy(uuid, text)', 'execute'), 'admin RPC grants');
  perform pg_temp.assert(not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'public' and g.grantee in ('anon', 'authenticated')
        and g.table_name in ('property_areas', 'property_types', 'property_offers', 'property_designs', 'properties', 'property_builds', 'player_residence', 'property_income', 'property_events', 'player_past_homes')
        and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE')), 'no client writes on any property table');
  perform pg_temp.assert(not exists (select 1 from information_schema.role_table_grants g where g.table_schema = 'public' and g.grantee = 'anon'
        and g.table_name in ('property_areas', 'property_types', 'property_offers', 'property_designs', 'properties', 'property_builds', 'player_residence', 'property_income', 'property_events', 'player_past_homes')), 'anon reads nothing');
  perform pg_temp.assert((select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('property_areas', 'property_types', 'property_offers', 'property_designs', 'properties',
        'property_builds', 'player_residence', 'property_income', 'property_events', 'player_past_homes') and c.relrowsecurity) = 10, 'RLS on all ten tables');
  perform pg_temp.assert((select count(*) from pg_constraint c where c.contype = 'f' and c.confrelid = 'public.profiles'::regclass
        and c.conrelid in ('public.properties'::regclass, 'public.property_builds'::regclass, 'public.player_residence'::regclass, 'public.property_income'::regclass, 'public.player_past_homes'::regclass)) >= 6,
        'the links migration added the profile foreign keys');
  -- RLS: own rows only; the landlord sees his tenant's residence, a stranger sees nothing
  perform pg_temp.as_auth(s);
  perform pg_temp.assert((select count(*) from properties) = 0 and (select count(*) from property_builds) = 0 and (select count(*) from property_income) = 0, 'a stranger sees no homes, builds or rent');
  perform pg_temp.assert((select count(*) from player_residence where user_id <> s) = 0, 'a stranger sees nobody else''s residence');
  perform pg_temp.assert(pg_temp.hint_of($q$ select count(*) from property_events $q$) <> 'ok', 'property_events has no client access');
  perform pg_temp.as_super();
  perform pg_temp.as_auth(a);
  perform pg_temp.assert((select count(*) from properties) = (select count(*) from properties where owner_id = a) and (select count(*) from properties) > 0, 'the owner sees only his homes');
  perform pg_temp.assert((select count(*) from property_areas) = 7 and (select count(*) from property_offers) >= 50, 'the catalogue is readable');
  perform pg_temp.assert((select count(*) from player_residence where landlord_id = a) >= 1, 'a landlord sees his tenant''s residence');
  perform pg_temp.as_super();
  raise notice 'property_test: all groups passed';
end $$;
