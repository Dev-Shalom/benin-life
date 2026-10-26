-- H1 move house + bigger homes (20261012000300_move_house.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/move_house_test.sql
-- Groups: 1 layouts grow by tier · 2 existing placements are valid · 3 the Houses list · 4 refusals (travelling,
-- visiting, hosting, busy, rent owed, money, same home, disabled) · 5 move: fee (bank first) + ledger, home, map spot,
-- furniture re-placed validly, garage stays behind, cars stay · 6 can't go back · 7 a big furnished move into the
-- duplex (all placed pieces valid, the rest in My items) · 8 grants.
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

-- every placed (not stored) row of a player is valid in its layout
create or replace function pg_temp.all_valid(p_uid uuid) returns boolean
language sql as $$
  select coalesce(bool_and(bl_furniture_check(h.owner_id, h.layout, h.furniture_key, h.x, h.z, h.rotation) is null), true)
    from player_house_furniture h where h.owner_id = p_uid and not h.stored
$$;

do $$
declare
  a uuid := pg_temp.new_user('h1_a@move.bl'); g uuid := pg_temp.new_user('h1_g@move.bl');
  r jsonb; v jsonb; n int; m int; a_home text; old_x numeric; old_y numeric; inv0 int;
begin
  -- 1. layouts grow by tier: LAPO homes stay small, the mini-flat is bigger, the GRA duplex is by far the widest
  perform pg_temp.assert((select w * d from home_layouts where id = 'face_me') < 20, 'face-me stays small');
  perform pg_temp.assert((select w * d from home_layouts where id = 'self_contain') < 30, 'self-contain stays small');
  perform pg_temp.assert((select w * d from home_layouts where id = 'flat') > 2 * (select w * d from home_layouts where id = 'self_contain'), 'flat > 2x self-contain');
  perform pg_temp.assert((select w * d from home_layouts where id = 'duplex') > 2 * (select w * d from home_layouts where id = 'flat'), 'duplex > 2x flat');
  perform pg_temp.assert((select w from home_layouts where id = 'duplex') = (select max(w) from home_layouts), 'duplex widest');
  perform pg_temp.assert((select jsonb_array_length(blocks) from home_layouts where id = 'duplex')
                         > (select jsonb_array_length(blocks) from home_layouts where id = 'flat'), 'duplex has more fixtures/partitions');

  -- 2. every existing placement in every layout passes the server check after the migration's re-check
  perform pg_temp.assert(not exists (
    select 1 from player_house_furniture h
     where not h.stored and h.layout in ('flat', 'duplex')
       and bl_furniture_check(h.owner_id, h.layout, h.furniture_key, h.x, h.z, h.rotation) is not null), 'existing placements valid');

  update game_config set value = 'true' where key = 'house.move_enabled';
  update game_config set value = '4' where key = 'house.move_in_weeks';
  update game_config set value = 'true' where key = 'garage.enabled';
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(a);
  perform create_profile_v2('H1_Mover', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(g);
  perform create_profile_v2('H1_Guest', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('aduwawa_face_me');
  select home_location_id into a_home from profiles where id = a;

  -- 3. the Houses list
  perform pg_temp.login(a);
  r := house_options();
  perform pg_temp.assert((r->>'enabled')::boolean and r->>'current' = 'ekenwan_face_me', 'options: enabled, current');
  perform pg_temp.assert((select h->>'status' from jsonb_array_elements(r->'homes') h where h->>'id' = 'ekenwan_face_me') = 'current', 'current flagged');
  perform pg_temp.assert((select (h->>'move_in')::bigint from jsonb_array_elements(r->'homes') h where h->>'id' = 'mission_rd_mini_flat') = 32000, 'flat move-in = 4 weeks');
  perform pg_temp.assert((select (h->>'area')::numeric from jsonb_array_elements(r->'homes') h where h->>'id' = 'gra_duplex') = 144, 'duplex area');

  -- 4. refusals
  update profiles set cash = 0, bank = 1000000 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select house_move(''ekenwan_face_me'')') = 'same_home', 'same home');
  perform pg_temp.assert(pg_temp.hint_of('select house_move(''nope'')') = 'bad_home', 'unknown home');
  update profiles set travel_to = 'national_museum', travel_arrives_at = bl_now() + interval '1 hour' where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select house_move(''mission_rd_mini_flat'')') = 'traveling', 'travelling');
  update profiles set travel_to = null, travel_arrives_at = null, busy_until = bl_now() + interval '1 minute', busy_label = 'Sleep' where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select house_move(''mission_rd_mini_flat'')') = 'busy', 'busy');
  update profiles set busy_until = null, busy_label = null, home_visit_host_id = g where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select house_move(''mission_rd_mini_flat'')') = 'visiting', 'visiting');
  update profiles set home_visit_host_id = null where id = a;
  update profiles set home_visit_host_id = a, location_id = a_home where id = g;
  perform pg_temp.assert(pg_temp.hint_of('select house_move(''mission_rd_mini_flat'')') = 'hosting', 'hosting guests');
  update profiles set home_visit_host_id = null, location_id = home_location_id where id = g;
  update profiles set rent_owed = 1500 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select house_move(''mission_rd_mini_flat'')') = 'rent_owed', 'rent owed');
  update profiles set rent_owed = 0, bank = 20000, cash = 10000 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select house_move(''mission_rd_mini_flat'')') = 'not_enough_cash', 'no money');
  update game_config set value = 'false' where key = 'house.move_enabled';
  update profiles set bank = 1000000 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select house_move(''mission_rd_mini_flat'')') = 'moving_disabled', 'disabled');
  update game_config set value = 'true' where key = 'house.move_enabled';
  perform pg_temp.assert((select start_home = 'ekenwan_face_me' and bank = 1000000 and cash = 10000 from profiles where id = a), 'refusals change nothing');

  -- 5. move (from somewhere else in town): garage + a car, starter furniture standing at its slots
  update profiles set cash = 0, bank = 50000000 where id = a;
  perform garage_build('carport');
  insert into inventory (user_id, item_id, qty) values (a, 'tokunbo_car', 1) on conflict do nothing;
  select count(*) into inv0 from inventory where user_id = a;
  perform bl_furniture_materialize(a);
  perform pg_temp.assert((select count(*) from player_house_furniture where owner_id = a and not stored) >= 3, 'starters stand in the face-me');
  update profiles set cash = 15000, bank = 20000, location_id = 'national_museum' where id = a;
  select x, y into old_x, old_y from locations where id = a_home;
  r := house_move('mission_rd_mini_flat');
  perform pg_temp.assert((r->>'spent')::bigint = 32000 and (r->>'from_bank')::bigint = 20000 and (r->>'from_cash')::bigint = 12000, 'fee split: ' || r::text);
  perform pg_temp.assert((select bank = 0 and cash = 3000 from profiles where id = a), 'charged once');
  perform pg_temp.assert((select count(*) from ledger where user_id = a and reason = 'house_move') = 2, 'ledger rows (bank + cash)');
  perform pg_temp.assert((select bool_and(bl_ledger_label(reason, meta) = 'Move-in: Mini-flat') from ledger where user_id = a and reason = 'house_move'), 'ledger label');
  perform pg_temp.assert((select start_home = 'mission_rd_mini_flat' and housing_id = 'mini_flat_mission' and weekly_rent = 8000
                                 and location_id = home_location_id and home_location_id = a_home from profiles where id = a), 'moved in, carried home');
  perform pg_temp.assert((select x <> old_x or y <> old_y from locations where id = a_home), 'home moved on the map');
  perform pg_temp.assert((select scene from locations where id = a_home) = (select scene from locations where id = 'mission_rd_flats'), 'home scene');
  perform pg_temp.assert(r->>'garage_left' = 'Carport' and not exists (select 1 from player_garages where user_id = a), 'garage stays behind');
  perform pg_temp.assert((select count(*) from inventory where user_id = a) = inv0, 'cars stay owned');
  perform pg_temp.assert((garage_home())->'garage' = 'null'::jsonb and jsonb_array_length((garage_home())->'cars') >= 1, 'no garage here yet, car listed');
  perform pg_temp.assert(not exists (select 1 from player_house_furniture where owner_id = a and layout <> 'flat'), 'all rows are for the flat');
  select count(*) into n from player_furniture pf, generate_series(1, pf.qty) where pf.user_id = a;
  perform pg_temp.assert((select count(*) from player_house_furniture where owner_id = a) = n, 'every owned copy has a row');
  perform pg_temp.assert((r->>'placed')::int >= 3 and (select count(*) from player_house_furniture where owner_id = a and not stored) = (r->>'placed')::int + (r->>'came_with')::int, 'starters re-placed (+ H4 came-with pieces): ' || r::text);
  perform pg_temp.assert(not exists (select 1 from player_house_furniture where owner_id = a and stored and furniture_key = 'own_stool'), 'stool takes the flat''s seat slot');
  perform pg_temp.assert(pg_temp.all_valid(a), 'placements valid in the flat');

  -- 6. a home you left is a past home for house.return_days: you can go back (own-your-home)
  update profiles set bank = 10000000 where id = a;
  r := house_options();
  perform pg_temp.assert((select h->>'status' from jsonb_array_elements(r->'homes') h where h->>'id' = 'ekenwan_face_me') = 'past', 'old home is a past home');
  perform pg_temp.assert((select h->>'past_until' from jsonb_array_elements(r->'homes') h where h->>'id' = 'ekenwan_face_me') is not null, 'it has a clock');
  perform pg_temp.assert(exists (select 1 from player_past_homes where user_id = a and start_home = 'ekenwan_face_me' and expires_at > bl_now() + interval '29 days'), 'past row, 30 days');
  perform pg_temp.assert(not exists (select 1 from player_released_homes where user_id = a and start_home = 'ekenwan_face_me'), 'no more released rows for a move');

  -- 7. a big furnished move: buy a lot for the flat, then move into the duplex
  update profiles set location_id = home_location_id, bank = 500000000 where id = a;
  for v in select to_jsonb(f) from furniture f where f.active and f.buyable and f.tier in ('mid', 'nepo')
            and f.category in ('living', 'bedroom', 'kitchen', 'decor') order by f.sort limit 25 loop
    perform furniture_buy(v->>'id');
    -- place it wherever it fits (as the player would in Arrange)
    perform bl_furniture_autoplace(a, 'flat', 'own_' || (v->>'id'), null, null, 0, false);
  end loop;
  select count(*) into m from player_house_furniture where owner_id = a and not stored;
  perform pg_temp.assert(pg_temp.all_valid(a), 'flat placements valid before the move');
  r := house_move('gra_duplex');
  raise notice 'duplex move: % standing before, %', m, r;
  perform pg_temp.assert(r->>'layout' = 'duplex' and (r->>'placed')::int + (r->>'not_fit')::int >= m, 'all standing pieces handled: ' || r::text);
  perform pg_temp.assert((r->>'placed')::int >= m - 2, 'the duplex fits (almost) everything: ' || r::text);
  perform pg_temp.assert(pg_temp.all_valid(a), 'placements valid in the duplex');
  perform pg_temp.assert((r->>'in_items')::int = (select count(*) from player_house_furniture where owner_id = a and stored), 'in_items count');
  perform pg_temp.assert(((r->>'in_items')::int = 0) = (position('My items' in r->>'message') = 0), 'message names My items only when needed');
  perform pg_temp.assert((select count(*) from player_past_homes where user_id = a) = 2, 'two past homes');
  -- arranging still works in the new home
  perform pg_temp.assert(pg_temp.hint_of('select furniture_store(''own_foam_mat'')') = 'ok', 'store works after the move');

  -- 8. grants: no anon calls, private helpers closed, released rows only for the owner
  perform pg_temp.assert(not has_function_privilege('anon', 'public.house_move(text)', 'execute'), 'anon: no house_move');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.house_options()', 'execute'), 'anon: no house_options');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.house_move(text)', 'execute'), 'authenticated: house_move');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_furniture_find_spot(uuid, text, text, numeric, numeric)', 'execute'), 'find_spot private');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_furniture_autoplace(uuid, text, text, numeric, numeric, integer, boolean)', 'execute'), 'autoplace private');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.player_released_homes', 'insert'), 'no client writes');
  perform pg_temp.assert((select provolatile from pg_proc where oid = 'public.house_options'::regproc) = 'v', 'house_options volatile (PostgREST read-only tx vs bl_me_any lock)');
  raise notice 'move_house_test: all groups passed';
end $$;
