-- R8 house upgrades (20261018000500_house_upgrades.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/house_upgrades_test.sql
-- Groups: 1 catalogue + the Upgrade list · 2 who may upgrade (own home only: hostel, visiting, rent owed) · 3 requirements ·
-- 4 paying (bank first, landlord fee, ledger) · 5 the build timer (builders working, time travel with bl.test_offset_seconds,
-- lazy settle, toast list once) · 6 effects (extension room is furnishable server-side, doorway blocks, bonuses reach do_activity,
-- garage + car space) · 7 in-place tier upgrade keeps furniture and garage · 8 sale value + moving out · 9 admin grant + audit ·
-- 10 grants / RLS.
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

create or replace function pg_temp.warp(p_seconds numeric) returns void
language plpgsql as $$ begin
  perform set_config('bl.test_offset_seconds', p_seconds::text, true);
  update profiles set rent_due_at = null where username like 'R8\_%';   -- no rent day in the middle of the test
end $$;

create or replace function pg_temp.as_auth(p_uid uuid) returns void
language plpgsql as $$
begin
  perform pg_temp.login(p_uid);
  execute 'set local role authenticated';
end $$;
create or replace function pg_temp.as_super() returns void
language plpgsql as $$ begin execute 'reset role'; end $$;

do $$
declare
  a uuid := pg_temp.new_user('r8_a@house.bl');      -- LAPO face-me: the main player
  s uuid := pg_temp.new_user('r8_stranger@house.bl'); -- another face-me
  h uuid := pg_temp.new_user('r8_hostel@house.bl');   -- hostel
  ad uuid := pg_temp.new_user('r8_admin@house.bl');
  r jsonb; v jsonb; n int; b0 bigint; c0 bigint; p0 profiles; p1 profiles; paid bigint; w0 bigint;
  v_cost bigint; v_fee bigint; rent0 bigint; k0 int; k1 int; hyg0 numeric; hyg1 numeric; d0 numeric; d1 numeric;
  a_home text; mv jsonb; bank_before bigint;
begin
  update game_config set value = 'true' where key = 'house.upgrades_enabled';
  update game_config set value = '100' where key = 'house.upgrade_time_pct';
  update game_config set value = '10' where key = 'house.upgrade_landlord_fee_pct';
  update game_config set value = '50' where key = 'house.upgrade_resale_pct';
  update game_config set value = '1' where key = 'house.upgrade_max_builds';
  update game_config set value = 'true' where key = 'garage.enabled';
  update game_config set value = 'true' where key = 'house.move_enabled';
  update game_config set value = '4' where key = 'house.move_in_weeks';
  perform pg_temp.warp(0);

  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(a);
  perform create_profile_v2('R8_Owner', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(s);
  perform create_profile_v2('R8_Stranger', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('aduwawa_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(h);
  perform create_profile_v2('R8_Hostel', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('uniben_hostel');
  perform pg_temp.login(ad);
  perform create_profile_v2('R8_Admin', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('aduwawa_face_me');
  update profiles set is_admin = true where id = ad;
  select home_location_id into a_home from profiles where id = a;

  -- 1. catalogue + the Upgrade list ------------------------------------------------------------------------
  perform pg_temp.assert((select count(*) from house_upgrades where active) >= 19, 'catalogue seeded');
  perform pg_temp.assert(not exists (select 1 from house_upgrades where 'hostel' = any (tiers)), 'no upgrade is for a hostel');
  perform pg_temp.assert((select effect->'geom'->'face_me'->'room'->'rect' from house_upgrades where id = 'ext_bedroom') = '[0,5.6,6.8,8.8]'::jsonb,
                         'extension geometry seeded for the server check');
  perform pg_temp.login(a);
  update profiles set cash = 0, bank = 60000000, rent_due_at = null where id = a;
  r := house_upgrade_state();
  perform pg_temp.assert((r->>'can_upgrade')::boolean and r->>'kind' = 'face_me', 'state: can upgrade, face_me');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(r->'available') x where x->>'id' = 'ext_bedroom' and x->>'state' = 'available'), 'extra bedroom listed');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r->'available') x where x->>'id' = 'ext_guest_wing'), 'duplex wing not listed for face-me');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(r->'available') x where x->>'id' = 'tier_face_to_selfcon'), 'tier upgrade listed');
  perform pg_temp.assert((select (x->>'price')::bigint from jsonb_array_elements(r->'available') x where x->>'id' = 'ext_bedroom') = 1800000, 'face-me price override');
  perform pg_temp.assert((select (x->>'landlord_fee')::bigint from jsonb_array_elements(r->'available') x where x->>'id' = 'ext_bedroom') = 180000, 'landlord fee 10%');
  perform pg_temp.assert((select x->>'state' from jsonb_array_elements(r->'available') x where x->>'id' = 'finish_pop') = 'locked', 'POP locked before paint');
  perform pg_temp.assert((r->>'sale_value')::bigint = 0 and jsonb_array_length(r->'building') = 0, 'nothing built yet');

  -- 2. who may upgrade -------------------------------------------------------------------------------------
  perform pg_temp.login(h);
  update profiles set bank = 60000000 where id = h;
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''paint_fresh'')') in ('not_yours', 'not_for_this_home'), 'hostel refused');
  perform pg_temp.assert(not (house_upgrade_state()->>'can_upgrade')::boolean, 'hostel: state says no');
  perform pg_temp.assert(jsonb_array_length(house_upgrade_state()->'available') = 0, 'hostel: nothing to list');
  perform pg_temp.login(s);
  update profiles set bank = 60000000, rent_owed = 5000 where id = s;
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''paint_fresh'')') = 'rent_owed', 'rent owed refused');
  update profiles set rent_owed = 0, home_visit_host_id = a where id = s;
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''paint_fresh'')') = 'visiting', 'visiting someone: refused');
  update profiles set home_visit_host_id = null where id = s;
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''nope'')') = 'unknown_upgrade', 'unknown upgrade');
  update game_config set value = 'false' where key = 'house.upgrades_enabled';
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''paint_fresh'')') = 'upgrades_disabled', 'switch off refuses');
  update game_config set value = 'true' where key = 'house.upgrades_enabled';
  -- the stranger buying never touches the owner
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''ext_guest_wing'')') = 'not_for_this_home', 'wrong home type refused');

  -- 3. requirements ----------------------------------------------------------------------------------------
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''finish_pop'')') = 'locked', 'needs fresh paint first');
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''gate_security'')') = 'locked', 'gate needs the wall first');
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''garage_space_1'')') = 'locked', 'car space needs a garage');
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''garage_standard'')') = 'not_for_this_home', 'standard garage not for face-me');

  -- 4. paying: bank first, landlord fee on top, ledger --------------------------------------------------------
  update profiles set cash = 100000, bank = 2000000 where id = a;
  select * into p0 from profiles where id = a;
  r := house_upgrade_buy('ext_bedroom');
  select * into p1 from profiles where id = a;
  v_cost := 1800000; v_fee := 180000;
  perform pg_temp.assert((r->>'spent')::bigint = v_cost + v_fee and (r->>'landlord_fee')::bigint = v_fee, 'spent = price + landlord fee');
  perform pg_temp.assert(p0.bank - p1.bank = v_cost + v_fee and p1.cash = p0.cash, 'paid from the bank first');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'house_upgrade' and delta = -(v_cost + v_fee)), 'ledger kind house_upgrade');
  perform pg_temp.assert(bl_ledger_label('house_upgrade', '{"name":"Extra bedroom"}') = 'House upgrade: Extra bedroom', 'ledger label');
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''ext_bedroom'')') = 'already_have', 'no double purchase');
  -- not enough money (cash + bank short)
  update profiles set cash = 1000, bank = 1000 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''borehole'')') in ('not_enough_cash', 'builders_busy'), 'short of money / builders busy');
  update profiles set bank = 60000000 where id = a;

  -- 5. the build timer -------------------------------------------------------------------------------------
  r := house_upgrade_state();
  perform pg_temp.assert(jsonb_array_length(r->'building') = 1 and (r->'building'->0->>'id') = 'ext_bedroom', 'builders working on the bedroom');
  perform pg_temp.assert((r->'building'->0->>'progress')::int between 0 and 5 and (r->'building'->0->>'seconds_left')::int > 7000, 'just started');
  perform pg_temp.assert(jsonb_array_length(r->'done') = 0 and jsonb_array_length(r->'just_finished') = 0, 'nothing finished yet');
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''borehole'')') = 'builders_busy', 'one build at a time');
  perform pg_temp.assert((house_upgrade_home()->'building'->0->>'id') = 'ext_bedroom' and jsonb_array_length(house_upgrade_home()->'done') = 0, 'home read: scaffolding only');
  -- before it is finished the new room is not floor
  perform pg_temp.assert(bl_furniture_check(a, 'face_me', 'own_stool', 1.0, 7.6, 0) is not null, 'no room yet: nothing to stand on south of the house (refused)');
  perform pg_temp.warp(60 * 60);  -- one hour: half way
  r := house_upgrade_state();
  perform pg_temp.assert((r->'building'->0->>'progress')::int between 40 and 60, 'half way after an hour');
  perform pg_temp.assert(jsonb_array_length(r->'done') = 0, 'still building');
  perform pg_temp.warp(125 * 60);  -- done
  r := house_upgrade_state();
  perform pg_temp.assert(jsonb_array_length(r->'building') = 0 and jsonb_array_length(r->'done') = 1, 'settled lazily on the next read');
  perform pg_temp.assert(jsonb_array_length(r->'just_finished') = 1 and r->'just_finished'->0->>'id' = 'ext_bedroom', 'toast list: once');
  perform pg_temp.assert(jsonb_array_length(house_upgrade_state()->'just_finished') = 0, 'toast list is empty the second time');
  perform pg_temp.assert((r->>'sale_value')::bigint = 900000, 'sale value = 50% of the works price (not the landlord fee)');
  perform pg_temp.assert(jsonb_array_length(house_upgrade_home()->'done') = 1, 'home read: the room is built');

  -- 6. effects ---------------------------------------------------------------------------------------------
  -- the new room is floor the server lets you furnish; the doorway and the shared wall are not
  perform pg_temp.assert(bl_furniture_check(a, 'face_me', 'own_stool', 1.0, 7.6, 0) is null, 'stool can stand in the new room');
  perform pg_temp.assert(bl_furniture_check(a, 'face_me', 'own_stool', 3.8, 5.9, 0) like 'blocks_door|%', 'doorway is kept clear');
  perform pg_temp.assert(bl_furniture_check(a, 'face_me', 'own_stool', 1.0, 5.6, 0) like 'overlap|%'
                         or bl_furniture_check(a, 'face_me', 'own_stool', 1.0, 5.6, 0) is not null, 'the shared wall blocks');
  perform pg_temp.assert(bl_furniture_check(a, 'face_me', 'own_stool', 1.0, 10.0, 0) is not null, 'beyond the room: still refused');
  r := furniture_place('own_stool', 1.0, 7.6, 0);
  perform pg_temp.assert((select x = 1.0 and z = 7.6 and not stored from player_house_furniture where owner_id = a and furniture_key = 'own_stool'), 'furniture_place into the new room');
  perform pg_temp.assert(bl_house_bonus(a, 'sleep') = '{"stress": -2}'::jsonb, 'bedroom bonus: calmer sleep');

  -- bonuses reach do_activity: a borehole makes the bucket bath cleaner
  update game_config set value = '0' where key = 'house.upgrade_time_pct';
  update profiles set hygiene = 10, bladder = 100, needs_updated_at = bl_now(), busy_until = null, busy_started_at = null, busy_label = null where id = a;
  hyg0 := (select hygiene from profiles where id = a);
  perform do_activity('bathe');
  d0 := (select hygiene from profiles where id = a) - hyg0;
  r := house_upgrade_buy('borehole');
  perform pg_temp.assert((r->>'instant')::boolean, 'build time 0 = instant');
  perform pg_temp.assert(jsonb_array_length(house_upgrade_state()->'building') = 0, 'instant: no builders');
  update profiles set hygiene = 10, needs_updated_at = bl_now(), busy_until = null, busy_started_at = null, busy_label = null, busy_needs_from = null where id = a;
  hyg0 := (select hygiene from profiles where id = a);
  perform do_activity('bathe');
  d1 := (select hygiene from profiles where id = a) - hyg0;
  perform pg_temp.assert(d1 = d0 + 6, format('borehole adds 6 hygiene to a bath (%s vs %s)', d1, d0));

  -- finish levels chain, security chain, generator
  perform house_upgrade_buy('paint_fresh');
  perform house_upgrade_buy('finish_pop');
  r := house_upgrade_state();
  perform pg_temp.assert((r->>'finish')::int = 2, 'finish level 2');
  perform pg_temp.assert(house_upgrade_home()->'done' @> '[{"id":"finish_pop"}]'::jsonb, 'home read carries the finish effect');
  perform house_upgrade_buy('fence_wall');
  perform house_upgrade_buy('gate_security');
  perform house_upgrade_buy('gen_house');
  perform pg_temp.assert((bl_house_bonus(a, 'sleep')->>'energy')::numeric = 2 and (bl_house_bonus(a, 'sleep')->>'stress')::numeric = -7,
                         'generator + security + finish + bedroom bonuses stack on sleep');
  update game_config set value = '3' where key = 'house.upgrade_bonus_cap';
  perform pg_temp.assert((bl_house_bonus(a, 'sleep')->>'stress')::numeric = -3, 'bonus is capped');
  update game_config set value = '12' where key = 'house.upgrade_bonus_cap';

  -- garage added where none exists (instant), then an extra car space
  perform pg_temp.assert(not exists (select 1 from player_garages where user_id = a), 'no garage yet');
  perform house_upgrade_buy('garage_carport');
  perform pg_temp.assert((select garage_type from player_garages where user_id = a) = 'carport', 'carport added');
  perform pg_temp.assert((garage_home()->'garage'->>'capacity')::int = 1, 'one bay');
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''garage_carport'')') in ('already_have'), 'cannot buy it twice');
  perform house_upgrade_buy('garage_space_1');
  perform pg_temp.assert((garage_home()->'garage'->>'capacity')::int = 2, 'extra car space: two bays');
  update game_config set value = '100' where key = 'house.upgrade_time_pct';

  -- 7. in-place tier upgrade keeps furniture and garage ---------------------------------------------------------
  select count(*) into k0 from player_house_furniture where owner_id = a;
  select weekly_rent into rent0 from profiles where id = a;
  update profiles set bank = 60000000, cash = 0 where id = a;
  select * into p0 from profiles where id = a;
  r := (select x from jsonb_array_elements(house_upgrade_state()->'available') x where x->>'id' = 'tier_face_to_selfcon');
  perform pg_temp.assert((r->>'rent_fee')::bigint = (4000 - 1500) * 4, 'tier price includes the rent difference x move-in weeks');
  perform pg_temp.assert((r->>'total')::bigint = 3500000 + 10000 + 350000, 'total = fee + rent difference + landlord');
  update game_config set value = '100' where key = 'house.upgrade_time_pct';
  r := house_upgrade_buy('tier_face_to_selfcon');
  select * into p1 from profiles where id = a;
  perform pg_temp.assert(p1.start_home = 'ekenwan_face_me' and p0.bank - p1.bank = (r->>'spent')::bigint, 'paid now, still a face-me while the builders work');
  perform pg_temp.assert(pg_temp.hint_of('select house_upgrade_buy(''paint_fresh'')') in ('already_have', 'tier_building'), 'no other works during a tier upgrade');
  perform pg_temp.warp(125 * 60 + 200 * 60);
  perform pg_temp.assert(bl_housing_kind((select housing_id from profiles where id = a)) = 'face_me', 'timer not done yet');
  perform pg_temp.warp(125 * 60 + 245 * 60);
  r := house_upgrade_state();
  select * into p1 from profiles where id = a;
  perform pg_temp.assert(p1.start_home = 'uselu_self_contain' and bl_housing_kind(p1.housing_id) = 'self_contain', 'became a self-contain at the same address');
  perform pg_temp.assert(p1.home_location_id = a_home, 'same private home location (same address)');
  perform pg_temp.assert(p1.weekly_rent = 4000, 'rent follows the new tier');
  perform pg_temp.assert(exists (select 1 from player_released_homes where user_id = a and start_home = 'ekenwan_face_me'), 'old tier is released');
  select count(*) into k1 from player_house_furniture where owner_id = a and layout = 'self_contain';
  perform pg_temp.assert(k1 >= k0 and not exists (select 1 from player_house_furniture where owner_id = a and layout is distinct from 'self_contain'), 'every piece of furniture kept (placed or in My items) in the new layout');
  perform pg_temp.assert(exists (select 1 from player_house_furniture where owner_id = a and furniture_key = 'own_stool'), 'the stool is still yours');
  perform pg_temp.assert((select count(*) from player_house_furniture where owner_id = a and not stored) >= 1, 'something stands in the new home');
  perform pg_temp.assert(coalesce((select bool_and(bl_furniture_check(h.owner_id, h.layout, h.furniture_key, h.x, h.z, h.rotation) is null)
                                     from player_house_furniture h where h.owner_id = a and not h.stored), true), 'every placed piece is valid in the new plan');
  perform pg_temp.assert((select garage_type from player_garages where user_id = a) = 'carport'
                         and (select housing_id from player_garages where user_id = a) = p1.housing_id, 'garage kept and re-keyed');
  perform pg_temp.assert((garage_home()->'garage'->>'capacity')::int = 2, 'garage still shows its two bays');
  perform pg_temp.assert(exists (select 1 from player_house_upgrades where user_id = a and upgrade_id = 'borehole' and done_at is not null), 'other upgrades carry over');
  perform pg_temp.assert((r->>'kind') = 'self_contain' and exists (select 1 from jsonb_array_elements(r->'available') x where x->>'id' = 'tier_selfcon_to_flat'), 'next tier now offered');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r->'available') x where x->>'id' = 'tier_face_to_selfcon'), 'old tier no longer offered');
  perform pg_temp.assert(house_upgrade_home()->'done' @> '[{"id":"ext_bedroom"}]'::jsonb, 'the bedroom stays a bonus');
  -- scene follows the tier
  perform pg_temp.assert((select scene from locations where id = a_home) = (select scene from locations where id = 'uselu_selfcon'), 'home scene follows the tier');

  -- 8. sale value + moving out -----------------------------------------------------------------------------------
  select coalesce(sum(price_paid), 0) into paid from player_house_upgrades where user_id = a;
  r := house_upgrade_state();
  perform pg_temp.assert((r->>'sale_value')::bigint = floor(paid * 0.5), 'sale value is 50% of the upgrades paid');
  perform pg_temp.assert(paid > 0, 'paid something');
  update game_config set value = '30' where key = 'house.upgrade_resale_pct';
  perform pg_temp.assert((house_upgrade_state()->>'sale_value')::bigint = floor(paid * 0.3), 'resale % is admin-tunable');
  update game_config set value = '50' where key = 'house.upgrade_resale_pct';
  update profiles set cash = 0, bank = 5000000, rent_owed = 0, location_id = home_location_id, busy_until = null, travel_to = null where id = a;
  select bank into bank_before from profiles where id = a;
  mv := house_move('mission_rd_mini_flat');
  perform pg_temp.assert((mv->>'upgrade_refund')::bigint = floor(paid * 0.5), 'move result reports the upgrade refund');
  perform pg_temp.assert((select bank from profiles where id = a) = bank_before - (mv->>'from_bank')::bigint + floor(paid * 0.5), 'refund paid into the bank');
  perform pg_temp.assert(not exists (select 1 from player_house_upgrades where user_id = a), 'upgrades cleared with the old home');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'house_upgrade' and delta = floor(paid * 0.5)), 'refund is on the ledger');
  perform pg_temp.assert(bl_ledger_label('house_upgrade', '{"refund":true}') = 'Upgrades sold with your old home', 'refund label');
  perform pg_temp.assert(jsonb_array_length(house_upgrade_home()->'done') = 0, 'new home starts plain');
  -- an unfinished build is refunded in full when you move
  update profiles set bank = 80000000 where id = a;
  perform house_upgrade_buy('paint_fresh');
  perform pg_temp.assert((house_upgrade_state()->>'sale_value')::bigint = (select price_paid from player_house_upgrades where user_id = a and upgrade_id = 'paint_fresh'), 'unfinished build: full value');

  -- 9. admin grant + audit -----------------------------------------------------------------------------------------
  perform pg_temp.login(ad);
  v := admin_house_upgrade_get(s);
  perform pg_temp.assert(v->>'kind' = 'face_me' and jsonb_array_length(v->'options') > 5, 'admin sees the options for that home');
  r := admin_house_upgrade_grant(s, 'borehole');
  perform pg_temp.assert(exists (select 1 from player_house_upgrades where user_id = s and upgrade_id = 'borehole' and done_at is not null and source = 'admin' and granted_by = ad and price_paid = 0), 'granted, finished, free');
  perform pg_temp.assert(exists (select 1 from admin_audit where admin_id = ad and action = 'house_upgrade_grant' and target_user = s and data->>'upgrade' = 'borehole'), 'audited');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_house_upgrade_grant(%L, ''borehole'')', s)) = 'already_have', 'no double grant');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_house_upgrade_grant(%L, ''ext_guest_wing'')', s)) = 'not_for_this_home', 'wrong tier refused');
  perform admin_house_upgrade_grant(s, 'garage_carport');
  perform pg_temp.assert((select garage_type from player_garages where user_id = s) = 'carport', 'granted garage appears');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = s and reason = 'house_upgrade'), 'a grant costs the player nothing');
  perform pg_temp.login(s);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_house_upgrade_grant(%L, ''fence_wall'')', s)) = 'not_admin', 'players cannot grant');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_house_upgrade_get(%L)', s)) = 'not_admin', 'players cannot read the admin view');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(house_upgrade_state()->'done') x where x->>'id' = 'borehole'), 'player sees the granted upgrade');
  -- a stranger cannot see someone else's upgrades; strangers see own only
  perform pg_temp.login(h);
  perform pg_temp.assert(pg_temp.hint_of(format('select house_upgrade_home(%L)', s)) = 'not_allowed', 'a stranger cannot read another home''s upgrades');

  -- 10. grants / RLS ------------------------------------------------------------------------------------------------
  perform pg_temp.assert(not has_function_privilege('anon', 'public.house_upgrade_state()', 'execute'), 'anon cannot run the Upgrade list');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.house_upgrade_buy(text)', 'execute'), 'players can buy');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_house_upgrades_settle(uuid)', 'execute'), 'settle is private');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_house_bonus(uuid, text)', 'execute'), 'bonus is private');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_home_ext(uuid)', 'execute'), 'bl_home_ext is private');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.bl_house_apply_tier(uuid, text)', 'execute'), 'tier apply is private');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_house_upgrades_release(uuid)', 'execute'), 'release is private');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.player_house_upgrades', 'insert')
                         and not has_table_privilege('authenticated', 'public.player_house_upgrades', 'update')
                         and not has_table_privilege('authenticated', 'public.player_house_upgrades', 'delete'), 'clients cannot write purchases');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.house_upgrades', 'insert')
                         and not has_table_privilege('authenticated', 'public.house_upgrades', 'update'), 'clients cannot edit the catalogue');
  perform pg_temp.assert(not has_table_privilege('anon', 'public.house_upgrades', 'select')
                         and not has_table_privilege('anon', 'public.player_house_upgrades', 'select'), 'anon reads nothing');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.player_house_upgrades'::regclass)
                         and (select relrowsecurity from pg_class where oid = 'public.house_upgrades'::regclass), 'RLS on');
  -- RLS: own rows only
  perform pg_temp.as_auth(s);
  select count(*) into n from player_house_upgrades;
  perform pg_temp.assert(n = (select count(*) from player_house_upgrades where user_id = s) and n >= 2, 'RLS: a player reads only their own purchases');
  perform pg_temp.assert(pg_temp.hint_of('insert into player_house_upgrades (user_id, upgrade_id) values (auth.uid(), ''fence_wall'')') <> 'ok', 'insert refused');
  perform pg_temp.assert(pg_temp.hint_of('select bl_house_bonus(auth.uid(), ''sleep'')') <> 'ok', 'private helper refused for players');
  perform pg_temp.as_super();

  raise notice 'HOUSE UPGRADES TEST OK';
end $$;
