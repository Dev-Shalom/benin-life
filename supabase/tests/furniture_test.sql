-- Starter furniture by origin (20261006000400_starter_furniture.sql). Rolled back. Run:
--   bash scripts/sql-test.sh -- supabase/tests/furniture_test.sql
create or replace function pg_temp.expect_hint(p_sql text, p_hint text) returns void
language plpgsql as $$
declare v_h text;
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
    get stacked diagnostics v_h = pg_exception_hint;
    if v_h is distinct from p_hint then
      raise exception 'TEST FAILED: [%] expected hint "%", got "%" (%)', p_sql, p_hint, v_h, sqlerrm;
    end if;
    return;
  end;
  raise exception 'TEST FAILED: [%] expected hint "%" but it succeeded', p_sql, p_hint;
end $$;

create temp table t_fu (name text primary key, id uuid not null) on commit drop;
create or replace function pg_temp.fu(p_name text) returns uuid
language sql as $$ select id from t_fu where name = p_name $$;

-- new user with a v2 profile of the given origin, moved into p_home
create or replace function pg_temp.make_home(p_name text, p_origin text, p_home text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@furniture.bl');
begin
  insert into t_fu values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = to_jsonb(p_origin) where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform pg_temp.assert(not exists (select 1 from player_furniture where user_id = v), 'no furniture before a home is chosen');
  perform choose_start_home(p_home);
  update profiles set rent_owed = 0, energy = 10, cash = 100000 where id = v;
  return v;
end $$;

create or replace function pg_temp.owned(p uuid) returns text[]
language sql as $$ select coalesce(array_agg(furniture_id order by furniture_id), '{}') from player_furniture where user_id = p $$;

create or replace function pg_temp.free(p uuid) returns void
language sql as $$ update profiles set busy_until = null, busy_label = null, busy_started_at = null where id = p $$;

-- shops_test.sql (same run) sets every rest_pct to 100: back to the seed values
update furniture set rest_pct = case id when 'foam_mat' then 90 else 100 end;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
end $$;

-- ---------- 1. seeds and config ----------
do $$
begin
  perform pg_temp.assert((select count(*) from furniture where active) >= 13, 'furniture seeded');
  perform pg_temp.assert((select activities from furniture where id = 'drum_bucket') = '{bathe}', 'drum + bucket hosts the bath');
  perform pg_temp.assert((select rest_pct from furniture where id = 'foam_mat') = 90, 'the mat rests 90 %');
  perform pg_temp.assert((select needs_furniture from activities where id = 'watch_tv'), 'TV needs a TV');
  perform pg_temp.assert((select 'home_face_me' = any (scenes) from activities where id = 'watch_tv'), 'TV possible in a face-me room');
  perform pg_temp.assert(not (select needs_furniture from activities where id = 'bathe'), 'bathing never needs furniture');
  perform pg_temp.assert((select count(*) from activities where id in ('sit_rest', 'relax_sofa', 'cold_drink') and needs_furniture and home_only) = 3,
                         'new furniture activities');
  perform pg_temp.assert((select value from game_config where key = 'home.walk_max_share_pct') = '15'::jsonb, 'walk share config');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'player_furniture', 'insert'), 'players cannot write furniture');
  perform pg_temp.assert(has_table_privilege('anon', 'furniture', 'select'), 'catalog is public');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'bl_give_starter_furniture(uuid)', 'execute'), 'helper revoked');
end $$;

-- ---------- 2. LAPO trench basics / Nepo moderate set ----------
do $$
declare l uuid; n uuid; h uuid; d uuid;
begin
  l := pg_temp.make_home('LapoFu', 'lapo', 'ekenwan_face_me');
  perform pg_temp.assert(pg_temp.owned(l) = '{drum_bucket,foam_mat,kerosene_stove,stool}', 'LAPO basics: ' || pg_temp.owned(l)::text);
  n := pg_temp.make_home('NepoFu', 'nepo', 'gra_duplex');
  perform pg_temp.assert(pg_temp.owned(n) = '{bed_double,centre_table,fridge,gas_cooker,rug,sofa,tv,wardrobe}', 'Nepo set: ' || pg_temp.owned(n)::text);
  h := pg_temp.make_home('NepoHostel', 'nepo', 'uniben_hostel');
  perform pg_temp.assert('bed_single' = any (pg_temp.owned(h)) and not ('bed_double' = any (pg_temp.owned(h))),
                         'hostel row replaces the bed slot: ' || pg_temp.owned(h)::text);
  perform pg_temp.assert((select slot from player_furniture where user_id = h and furniture_id = 'bed_single') = 'bed', 'slot stored');
  -- v1 profile (no start home): found from the housing id
  d := pg_temp.new_user('v1fu@furniture.bl');
  perform pg_temp.login(d);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile('V1Fu', 'male', '{"gender":"male"}');
  perform pg_temp.assert(pg_temp.owned(d) = '{drum_bucket,foam_mat,kerosene_stove,stool}', 'v1 LAPO gets the basics: ' || pg_temp.owned(d)::text);
end $$;

-- ---------- 3. actions follow the furniture ----------
do $$
declare l uuid := pg_temp.fu('LapoFu'); n uuid := pg_temp.fu('NepoFu'); r jsonb;
begin
  perform pg_temp.login(l);
  perform pg_temp.expect_hint($q$select do_activity('watch_tv')$q$, 'no_furniture');
  perform pg_temp.expect_hint($q$select do_activity('relax_sofa')$q$, 'no_furniture');
  perform pg_temp.expect_hint($q$select do_activity('cold_drink')$q$, 'no_furniture');
  perform pg_temp.expect_hint($q$select do_activity('listen_radio')$q$, 'no_furniture');
  r := do_activity('bathe');
  perform pg_temp.assert(r->>'message' like '%Bucket bath%', 'bucket bath works: ' || (r->>'message'));
  perform pg_temp.free(l);
  r := do_activity('cook_home');
  perform pg_temp.assert((r->'effects'->>'hunger')::numeric > 0, 'cooking on the stove works');
  perform pg_temp.free(l);
  r := do_activity('sit_rest');
  perform pg_temp.assert((r->'effects'->>'energy')::numeric = 5, 'stool: sit and rest');
  perform pg_temp.free(l);
  r := do_activity('sleep');
  perform pg_temp.assert((r->'effects'->>'energy')::numeric = round((select (effects->>'energy')::numeric from activities where id = 'sleep') * 0.9, 1),
                         'mat sleep = 90 % of a bed: ' || (r->'effects'->>'energy'));
  perform pg_temp.free(l);

  perform pg_temp.login(n);
  r := do_activity('sleep');
  perform pg_temp.assert((r->'effects'->>'energy')::numeric = (select (effects->>'energy')::numeric from activities where id = 'sleep'),
                         'bed sleep = full energy');
  perform pg_temp.free(n);
  r := do_activity('watch_tv');
  perform pg_temp.assert(r ? 'busy_until', 'Nepo watches TV');
  perform pg_temp.free(n);
  r := do_activity('relax_sofa');
  perform pg_temp.free(n);
  r := do_activity('cold_drink');
  perform pg_temp.assert((r->'effects'->>'hunger')::numeric = 6, 'cold drink from the fridge');
  perform pg_temp.free(n);
  perform pg_temp.expect_hint($q$select do_activity('sit_rest')$q$, 'no_furniture');
  -- a Nepo in a face-me room can watch TV there
  perform pg_temp.login(pg_temp.fu('NepoHostel'));
  r := do_activity('watch_tv');
  perform pg_temp.free(pg_temp.fu('NepoHostel'));
  -- away from home: the home-only rule still answers first
  perform pg_temp.login(l);
  update profiles set location_id = 'uselu_park' where id = l;
  begin
    perform do_activity('sit_rest');
    raise exception 'TEST FAILED: home only';
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
  end;
  update profiles set location_id = home_location_id where id = l;
end $$;

-- ---------- 4. additive: bought pieces are kept, nothing duplicated ----------
do $$
declare l uuid := pg_temp.fu('LapoFu'); v int;
begin
  insert into player_furniture (user_id, furniture_id, slot, source) values (l, 'tv', 'tv', 'bought');
  v := bl_give_starter_furniture(l);
  perform pg_temp.assert(v = 0, 'nothing new to give');
  perform pg_temp.assert(pg_temp.owned(l) = '{drum_bucket,foam_mat,kerosene_stove,stool,tv}', 'bought TV kept');
  perform pg_temp.login(l);
  perform do_activity('watch_tv');           -- the bought TV unlocks it
  perform pg_temp.free(l);
  -- the trigger fires only when the home is first chosen
  update profiles set home_chosen = true where id = l;
  perform pg_temp.assert((select count(*) from player_furniture where user_id = l) = 5, 'no re-give on a no-op update');
end $$;

-- ---------- 5. RLS: own rows only ----------
select pg_temp.login(pg_temp.fu('LapoFu'));
set local role authenticated;
do $$
begin
  perform pg_temp.assert((select count(*) from player_furniture) = 5, 'sees own furniture only');
  perform pg_temp.assert((select count(*) from furniture) >= 13, 'reads the catalog');
  perform pg_temp.assert((select count(*) from starter_furniture) >= 12, 'reads starter sets');
end $$;
reset role;

-- ---------- 6. admin whitelist ----------
do $$
declare a uuid := pg_temp.fu('NepoFu'); r jsonb;
begin
  update profiles set is_admin = true where id = a;
  perform pg_temp.login(a);
  r := admin_row_upsert('furniture', '{"id":"foam_mat","rest_pct":80}');
  perform pg_temp.assert((select rest_pct from furniture where id = 'foam_mat') = 80, 'admin edits rest_pct');
  r := admin_row_upsert('furniture', '{"id":"radio","name":"Radio","emoji":"📻","kind":"radio","slot":"seat","activities":["listen_radio"],"rest_pct":100,"description":"","sort":130,"active":true}');
  perform pg_temp.assert(exists (select 1 from furniture where id = 'radio'), 'admin adds a piece');
  r := admin_row_upsert('starter_furniture', '{"id":"lapo_ekenwan_radio","origin":"lapo","start_home":"ekenwan_face_me","furniture_id":"radio","slot":"radio","sort":50,"active":true}');
  perform pg_temp.assert('radio' = any (array(select furniture_id from bl_starter_furniture('lapo', 'ekenwan_face_me', null))), 'per-home extra');
  perform pg_temp.assert(not ('radio' = any (array(select furniture_id from bl_starter_furniture('lapo', 'aduwawa_face_me', null)))), 'only that home');
  r := admin_row_upsert('activities', '{"id":"bathe","needs_furniture":false}');
  perform pg_temp.expect_hint($q$select admin_row_upsert('furniture', '{"id":"tv","owner":"x"}')$q$, 'bad_column');
  perform pg_temp.expect_hint($q$select admin_row_upsert('starter_furniture', '{"id":"bad","origin":"lapo","furniture_id":"nope","sort":1,"active":true}')$q$, 'bad_value');
  perform pg_temp.assert((select count(*) from admin_audit where admin_id = a and data->>'table' in ('furniture', 'starter_furniture')) = 3, 'audited');
  update game_config set value = '"nepo"' where key = 'origin.force_next';
end $$;

select 'furniture_test OK' as result;
