-- B1 buy catalogue + arrange (20261012000200_buy_catalogue.sql). Rolled back. Run:
--   bash scripts/sql-test.sh -- supabase/tests/buy_catalogue_test.sql
create or replace function pg_temp.expect_hint(p_sql text, p_hint text) returns text
language plpgsql as $$
declare v_h text; v_m text;
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
    get stacked diagnostics v_h = pg_exception_hint, v_m = message_text;
    if v_h is distinct from p_hint then
      raise exception 'TEST FAILED: [%] expected hint "%", got "%" (%)', p_sql, p_hint, v_h, sqlerrm;
    end if;
    return v_m;
  end;
  raise exception 'TEST FAILED: [%] expected hint "%" but it succeeded', p_sql, p_hint;
end $$;

create temp table t_bu (name text primary key, id uuid not null) on commit drop;
create or replace function pg_temp.bu(p_name text) returns uuid
language sql as $$ select id from t_bu where name = p_name $$;

create or replace function pg_temp.make_home(p_name text, p_origin text, p_home text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@buy.bl');
begin
  insert into t_bu values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = to_jsonb(p_origin) where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home(p_home);
  update profiles set rent_owed = 0, energy = 10, cash = 100000, bank = 0, busy_until = null where id = v;
  return v;
end $$;

create or replace function pg_temp.row_of(p uuid, k text) returns player_house_furniture
language sql as $$ select * from player_house_furniture where owner_id = p and furniture_key = k $$;

create or replace function pg_temp.free(p uuid) returns void
language sql as $$ update profiles set busy_until = null, busy_label = null, busy_started_at = null where id = p $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
end $$;
-- other suites in the same DB may have changed rest_pct; the seed values matter here
update furniture set rest_pct = 90 where id = 'foam_mat';

-- ---------- 1. catalogue ----------
do $$
begin
  perform pg_temp.assert((select count(*) from furniture where active and buyable) >= 80, 'catalogue has 80+ items');
  perform pg_temp.assert((select count(distinct tier) from furniture where active) = 3, 'LAPO, mid and Nepo tiers');
  perform pg_temp.assert((select count(distinct category) from furniture where active) = 6, 'six categories');
  perform pg_temp.assert(not exists (select 1 from furniture where active and buyable and price <= 0), 'every item has a price');
  perform pg_temp.assert((select price from furniture where id = 'tv_75') = 1250000, '75" TV price');
  perform pg_temp.assert((select tier from furniture where id = 'gen_tiger') = 'lapo'
                         and (select placement from furniture where id = 'gen_tiger') = 'out', 'Tiger gen: LAPO, outside');
  perform pg_temp.assert((select count(*) from home_layouts) = 5, 'five home layouts');
  perform pg_temp.assert((select slots ? 'bed' from home_layouts where id = 'face_me'), 'face_me has a bed slot');
end $$;

-- ---------- 2. buying ----------
do $$
declare l uuid := pg_temp.make_home('LapoBuy', 'lapo', 'ekenwan_face_me'); r jsonb; m text;
begin
  perform pg_temp.login(l);
  r := furniture_buy('plastic_chair_white');
  perform pg_temp.assert((select cash from profiles where id = l) = 93500, 'buying debits cash: ' || (select cash from profiles where id = l));
  perform pg_temp.assert(r->>'furniture_key' = 'own_plastic_chair_white' and (r->>'qty')::int = 1, 'first copy key: ' || r::text);
  perform pg_temp.assert((pg_temp.row_of(l, 'own_plastic_chair_white')).stored, 'a bought piece waits in the inventory');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = l and reason = 'furniture' and delta = -6500), 'ledger entry');
  perform pg_temp.assert(bl_ledger_label('furniture', '{"name":"Plastic chair (white)"}'::jsonb) like 'Furniture: Plastic chair%', 'ledger label');
  r := furniture_buy('plastic_chair_white');
  perform pg_temp.assert(r->>'furniture_key' = 'own_plastic_chair_white-2' and (r->>'qty')::int = 2, 'second copy key: ' || r::text);
  perform pg_temp.assert((select qty from player_furniture where user_id = l and furniture_id = 'plastic_chair_white') = 2, 'qty 2');
  -- buying gave the starter pieces their rows (defaults), the mat sits at the bed slot
  perform pg_temp.assert((select not stored and x = 0.85 and z = 1.1 from player_house_furniture
                           where owner_id = l and furniture_key = 'own_foam_mat'), 'starter mat materialised at its slot');

  -- not enough money: cash + bank short
  update profiles set cash = 1000, bank = 0 where id = l;
  m := pg_temp.expect_hint($q$select furniture_buy('tv_75')$q$, 'not_enough_cash');
  perform pg_temp.assert(m like 'Not enough money%', 'clear message: ' || m);
  perform pg_temp.assert((select cash from profiles where id = l) = 1000, 'nothing taken on a failed buy');
  perform pg_temp.assert(not exists (select 1 from player_furniture where user_id = l and furniture_id = 'tv_75'), 'nothing given');
  -- cash first, then bank
  update profiles set cash = 50000, bank = 2000000 where id = l;
  r := furniture_buy('tv_75');
  perform pg_temp.assert((select cash = 0 and bank = 800000 from profiles where id = l), 'cash first then bank: ' || r::text);
  perform pg_temp.expect_hint($q$select furniture_buy('tv_75')$q$, 'max_owned');
  perform pg_temp.expect_hint($q$select furniture_buy('nope_item')$q$, 'unknown_furniture');
  update profiles set cash = 500000 where id = l;
end $$;

-- ---------- 3. placement ----------
do $$
declare l uuid := pg_temp.bu('LapoBuy'); r jsonb;
begin
  perform pg_temp.login(l);
  -- valid: an empty floor spot (face_me room is 4.2 x 3.8, door on the east wall z 2.4..3.3)
  r := furniture_place('own_plastic_chair_white', 2.5, 1.0, 5);
  perform pg_temp.assert((r->>'rotation')::int = 1 and not (r->>'stored')::boolean, 'placed, rotation in quarter turns: ' || r::text);
  perform pg_temp.assert((select not stored and x = 2.5 and z = 1.0 and rotation = 1 and layout = 'face_me'
                            from player_house_furniture where owner_id = l and furniture_key = 'own_plastic_chair_white'), 'placement persisted');
  -- invalid spots
  perform pg_temp.expect_hint($q$select furniture_place('own_plastic_chair_white-2', 20, 20, 0)$q$, 'outside_home');
  perform pg_temp.expect_hint($q$select furniture_place('own_plastic_chair_white-2', 0.8, 1.0, 0)$q$, 'overlap');   -- on the mat
  perform pg_temp.expect_hint($q$select furniture_place('own_plastic_chair_white-2', 2.55, 1.05, 0)$q$, 'overlap'); -- on chair 1
  perform pg_temp.expect_hint($q$select furniture_place('own_plastic_chair_white-2', 3.8, 2.85, 0)$q$, 'blocks_door');
  perform pg_temp.expect_hint($q$select furniture_place('own_plastic_chair_white-2', 4.1, 1.0, 0)$q$, 'outside_home'); -- across the wall
  perform pg_temp.assert((pg_temp.row_of(l, 'own_plastic_chair_white-2')).stored, 'a refused placement leaves it in the inventory');
  -- chairs may also stand in the compound
  r := furniture_place('own_plastic_chair_white-2', 4.8, 3.9, 0);
  -- outdoor-only and wall pieces
  perform furniture_buy('gen_tiger');
  perform pg_temp.expect_hint($q$select furniture_place('own_gen_tiger', 2.5, 2.0, 0)$q$, 'outside_home');
  r := furniture_place('own_gen_tiger', 4.8, 1.0, 0);
  perform furniture_buy('wall_clock');
  perform pg_temp.expect_hint($q$select furniture_place('own_wall_clock', 2.0, 2.0, 0)$q$, 'not_on_wall');
  r := furniture_place('own_wall_clock', 2.0, 0.04, 0);
  -- non-solid pieces (a rug) can go under others
  perform furniture_buy('mat_raffia');
  r := furniture_place('own_mat_raffia', 0.9, 1.1, 0);
  -- the old V2 RPC validates too
  perform pg_temp.expect_hint($q$select social_home_place_furniture('own_plastic_chair_white', 0.8, 1.0, 0::smallint)$q$, 'overlap');
  perform pg_temp.expect_hint($q$select furniture_place('own_tv_75-2', 2, 2, 0)$q$, 'not_owned');
  perform pg_temp.expect_hint($q$select furniture_place('toilet', 2, 2, 0)$q$, 'fixed_furniture');
  -- only at home
  update profiles set location_id = 'uselu_park' where id = l;
  perform pg_temp.expect_hint($q$select furniture_place('own_plastic_chair_white', 2.5, 1.5, 0)$q$, 'not_homeowner');
  perform pg_temp.expect_hint($q$select furniture_store('own_plastic_chair_white')$q$, 'not_homeowner');
  update profiles set location_id = home_location_id where id = l;
end $$;

-- ---------- 4. store + need bonuses from placed pieces ----------
do $$
declare l uuid := pg_temp.bu('LapoBuy'); r jsonb; base numeric;
begin
  perform pg_temp.login(l);
  perform furniture_store('own_gen_tiger'); -- the Tiger gen also helps sleep; keep only the fan
  perform furniture_buy('fan_standing');
  perform pg_temp.assert(bl_furniture_for(l, 'sleep')->'bonus' = '{}'::jsonb, 'a stored fan gives nothing');
  r := furniture_place('own_fan_standing', 2.0, 2.0, 0);
  perform pg_temp.assert((bl_furniture_for(l, 'sleep')->'bonus'->>'energy')::numeric = 2, 'placed fan: +2 sleep energy');
  base := round((select (effects->>'energy')::numeric from activities where id = 'sleep') * 0.9, 1);
  perform pg_temp.free(l);
  r := do_activity('sleep');
  perform pg_temp.assert((r->'effects'->>'energy')::numeric = base + 2, 'mat sleep + fan bonus: ' || (r->'effects'->>'energy'));
  perform pg_temp.free(l);
  r := furniture_store('own_fan_standing');
  perform pg_temp.assert((pg_temp.row_of(l, 'own_fan_standing')).stored and bl_furniture_for(l, 'sleep')->'bonus' = '{}'::jsonb,
                         'stored again: no bonus');
  -- storing every seat takes away sit_rest's furniture
  perform pg_temp.assert((bl_furniture_for(l, 'sit_rest')->>'owned')::boolean, 'stool/chairs host sit_rest');
  perform furniture_store('own_stool');
  perform furniture_store('own_plastic_chair_white');
  perform pg_temp.assert((bl_furniture_for(l, 'sit_rest')->>'owned')::boolean, 'chair copy 2 still out');
  perform furniture_store('own_plastic_chair_white-2');
  perform pg_temp.assert(not (bl_furniture_for(l, 'sit_rest')->>'owned')::boolean, 'everything stored: no seat');
  perform pg_temp.expect_hint($q$select do_activity('sit_rest')$q$, 'no_furniture');
  -- unstore = place again
  r := furniture_place('own_stool', 2.0, 3.2, 0);
  perform pg_temp.assert((bl_furniture_for(l, 'sit_rest')->>'owned')::boolean, 'stool back out');
end $$;

-- ---------- 5. moving house resets the positions; Nepo luxury pieces ----------
do $$
declare l uuid := pg_temp.bu('LapoBuy'); n uuid := pg_temp.make_home('NepoBuy', 'nepo', 'gra_duplex'); r jsonb;
begin
  perform pg_temp.login(l);
  update profiles set housing_id = 'self_contain_uselu' where id = l;
  r := furniture_place('own_stool', 3.0, 3.0, 0);
  perform pg_temp.assert(not exists (select 1 from player_house_furniture where owner_id = l and layout = 'face_me'),
                         'old home rows dropped after moving');
  perform pg_temp.assert((select layout = 'self_contain' and not stored from player_house_furniture
                           where owner_id = l and furniture_key = 'own_foam_mat'), 'starter mat back at the new bed slot');
  perform pg_temp.assert((pg_temp.row_of(l, 'own_gen_tiger')).stored, 'pieces without a slot wait in the inventory');

  perform pg_temp.login(n);
  update profiles set cash = 20000000 where id = n;
  perform furniture_buy('sofa_italian');
  perform furniture_buy('ac_inverter');
  r := furniture_place('own_ac_inverter', 0.14, 2.0, 1);    -- on the west wall
  r := furniture_place('own_sofa_italian', 5.5, 5.0, 0);
  perform pg_temp.assert((select count(*) from player_house_furniture where owner_id = n and not stored and layout = 'duplex'
                            and furniture_key in ('own_sofa_italian', 'own_ac_inverter')) = 2, 'Nepo pieces placed');
  perform pg_temp.assert((bl_furniture_for(n, 'sleep')->'bonus'->>'energy')::numeric = 12, 'inverter AC +12 sleep energy');
  perform pg_temp.assert((select cash from profiles where id = n) = 20000000 - 6500000 - 850000, 'Nepo paid');
end $$;
