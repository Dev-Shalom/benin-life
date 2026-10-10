-- G1 garage (20261010000400_garage.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/garage_test.sql
-- Groups: 1 gating by home type · 2 no money · 3 build charges once (bank first, ledger label) · 4 upgrade replaces,
-- a move does not transfer the garage · 5 guests read the host's garage while admitted, strangers can't ·
-- 6 clients can't write the tables · 7 garage.enabled off refuses.
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

do $$
declare h uuid := pg_temp.new_user('g1_host@garage.bl'); g uuid := pg_temp.new_user('g1_guest@garage.bl');
        s uuid := pg_temp.new_user('g1_stranger@garage.bl');
        r jsonb; inv jsonb; n int; b0 bigint; c0 bigint; h_home text;
begin
  perform set_config('g1.h', h::text, true); perform set_config('g1.g', g::text, true); perform set_config('g1.s', s::text, true);
  update game_config set value = 'true' where key = 'garage.enabled';
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(h);
  perform create_profile_v2('G1_Host', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(g);
  perform create_profile_v2('G1_Guest', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(s);
  perform create_profile_v2('G1_Stranger', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('aduwawa_face_me');
  select home_location_id into h_home from profiles where id = h;

  -- 1. gating: a face-me room can't take a luxury or standard garage
  perform pg_temp.login(h);
  update profiles set cash = 0, bank = 50000000 where id = h;
  perform pg_temp.assert(pg_temp.hint_of('select garage_build(''garage_luxury'')') = 'not_allowed_here', 'face-me: no luxury');
  perform pg_temp.assert(pg_temp.hint_of('select garage_build(''garage_standard'')') = 'not_allowed_here', 'face-me: no standard');
  perform pg_temp.assert(pg_temp.hint_of('select garage_build(''nope'')') = 'unknown_garage', 'unknown type');
  perform pg_temp.assert(not exists (select 1 from player_garages where user_id = h), 'nothing built');
  r := garage_home();
  perform pg_temp.assert(r->'garage' = 'null'::jsonb and r->>'kind' = 'face_me', 'home: no garage, face_me');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(r->'types') t where (t->>'allowed')::boolean) = 1, 'face-me: only carport allowed');

  -- 2. no money
  update profiles set cash = 100000, bank = 200000 where id = h;
  perform pg_temp.assert(pg_temp.hint_of('select garage_build(''carport'')') = 'not_enough_cash', 'no money');
  perform pg_temp.assert(not exists (select 1 from player_garages where user_id = h), 'no garage without money');
  perform pg_temp.assert((select cash = 100000 and bank = 200000 from profiles where id = h), 'balances untouched');

  -- 3. build charges once: bank first, then cash; ledger "Garage: Carport"
  update profiles set cash = 2000000, bank = 1000000 where id = h;
  r := garage_build('carport');
  perform pg_temp.assert((r->>'spent')::bigint = 1500000 and (r->>'from_bank')::bigint = 1000000 and (r->>'from_cash')::bigint = 500000, 'split: ' || r::text);
  perform pg_temp.assert((select cash = 1500000 and bank = 0 from profiles where id = h), 'charged once');
  perform pg_temp.assert((select count(*) from ledger where user_id = h and reason = 'garage') = 2, 'two ledger rows (bank + cash)');
  perform pg_temp.assert((select sum(delta) from ledger where user_id = h and reason = 'garage') = -1500000, 'ledger total');
  perform pg_temp.assert((select bl_ledger_label(reason, meta) from ledger where user_id = h and reason = 'garage' limit 1) = 'Garage: Carport', 'ledger label');
  perform pg_temp.assert(pg_temp.hint_of('select garage_build(''carport'')') = 'already_built', 'same type twice refused');
  perform pg_temp.assert((select cash = 1500000 from profiles where id = h), 'not charged twice');

  -- 4. upgrade replaces at full price (move to a duplex first); moving home does not transfer the garage
  update profiles set housing_id = 'duplex_gra', bank = 20000000, cash = 0 where id = h;
  r := garage_home();
  perform pg_temp.assert(r->'garage' = 'null'::jsonb and r->>'kind' = 'duplex', 'after a move: no garage');
  update profiles set housing_id = 'face_me_ekenwan' where id = h;
  perform pg_temp.assert(garage_home()->'garage'->>'type' = 'carport', 'back home: carport again');
  update profiles set housing_id = 'duplex_gra' where id = h;
  r := garage_build('garage_luxury');
  perform pg_temp.assert((select bank = 8000000 from profiles where id = h), 'luxury full price');
  perform pg_temp.assert((select count(*) from player_garages where user_id = h) = 1
                         and (select garage_type from player_garages where user_id = h) = 'garage_luxury', 'one garage, luxury');
  r := garage_build('garage_standard');
  perform pg_temp.assert(r->>'replaced' = 'garage_luxury' and (select bank = 3000000 from profiles where id = h), 'change replaces at full price');
  perform pg_temp.assert((garage_home()->'garage'->>'capacity')::int = 1, 'capacity follows the new type');
  update profiles set housing_id = 'face_me_ekenwan' where id = h;

  -- 5. guests read the host's garage while admitted, strangers can't
  insert into inventory (user_id, item_id, qty) values (h, 'camry_muscle', 1), (h, 'kia_rio_used', 1)
    on conflict (user_id, item_id) do update set qty = 1;
  perform garage_build('carport');
  perform pg_temp.login(g);
  perform pg_temp.assert(pg_temp.hint_of(format('select garage_home(%L)', h)) = 'not_allowed', 'guest before admission refused');
  perform pg_temp.login(h); perform social_add_friend(g);
  perform pg_temp.login(g); perform social_respond_friend(h, true);
  perform pg_temp.login(h); inv := social_send_house_invite(g);
  perform pg_temp.login(g); perform social_respond_house_invite((inv->>'id')::bigint, true);
  perform pg_temp.login(h); perform social_home_admit((inv->>'id')::bigint, true);
  perform pg_temp.assert((select location_id = h_home and home_visit_host_id = h from profiles where id = g), 'guest inside');
  perform pg_temp.login(g);
  r := garage_home(h);
  perform pg_temp.assert(r->'garage'->>'type' = 'carport', 'guest sees host carport');
  perform pg_temp.assert(r->'cars'->0->>'id' = 'camry_muscle' and jsonb_array_length(r->'cars') = 2, 'guest sees host cars, priciest first');
  perform pg_temp.assert(r->'types' = '[]'::jsonb, 'guest gets no build menu');
  perform pg_temp.login(s);
  perform pg_temp.assert(pg_temp.hint_of(format('select garage_home(%L)', h)) = 'not_allowed', 'stranger refused');
  raise notice 'ok 1-5: gating, money, charge once, upgrade, guest read';
end $$;

-- 5b/6. RLS as the authenticated role
do $$ begin perform pg_temp.login(current_setting('g1.g')::uuid); end $$;
set local role authenticated;
do $$ begin
  perform pg_temp.assert((select count(*) from player_garages where user_id = current_setting('g1.h')::uuid) = 1, 'RLS: admitted guest reads host garage');
  perform pg_temp.assert((select count(*) from garage_types) >= 3, 'RLS: types readable');
  begin
    insert into player_garages (user_id, garage_type) values (current_setting('g1.g')::uuid, 'garage_luxury');
    raise exception 'TEST FAILED: direct insert worked';
  exception when insufficient_privilege then null; end;
  begin
    update garage_types set price = 1;
    raise exception 'TEST FAILED: direct type update worked';
  exception when insufficient_privilege then null; end;
  begin
    delete from player_garages;
    raise exception 'TEST FAILED: direct delete worked';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin perform pg_temp.login(current_setting('g1.s')::uuid); end $$;
set local role authenticated;
do $$ begin
  perform pg_temp.assert((select count(*) from player_garages where user_id = current_setting('g1.h')::uuid) = 0, 'RLS: stranger reads nothing');
end $$;
reset role;

-- 7. switch off
do $$ begin
  perform pg_temp.login(current_setting('g1.h')::uuid);
  update game_config set value = 'false' where key = 'garage.enabled';
  perform pg_temp.assert(pg_temp.hint_of('select garage_build(''carport'')') = 'garage_disabled', 'disabled refuses');
  update game_config set value = 'true' where key = 'garage.enabled';
  raise notice 'ok 6-7: clients cannot write, switch off';
end $$;
