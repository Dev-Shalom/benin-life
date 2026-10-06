<<<<<<< HEAD
-- Starter furniture by origin (20261006000400_starter_furniture.sql): catalog + starter sets per home and
-- origin, move-in via choose_start_home, get_my_state().home, furniture-gated home activities (label,
-- percent, reason, hint no_furniture), fixtures (shower/bathtub), the existing-player backfill rule,
-- admin edits (furniture table, start_homes validation, admin_set_furniture). Rolled back.
-- Run (migrations applied):   bash scripts/sql-test.sh -- supabase/tests/furniture_test.sql
-- Re-run safety:              bash scripts/sql-test.sh supabase/migrations/20261006000400_starter_furniture.sql -- supabase/tests/furniture_test.sql

create temp table t_fu (name text primary key, id uuid not null) on commit drop;
create or replace function pg_temp.fu(p_name text) returns uuid
language sql as $$ select id from t_fu where name = p_name $$;

-- new logged-in Sim of p_origin living in p_home
create or replace function pg_temp.f_make(p_name text, p_origin text, p_home text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@furniture.bl');
begin
  insert into t_fu values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = to_jsonb(case when p_origin = 'nepo' then 'nepo' else '' end) where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home(p_home);
  return v;
end $$;

-- at home, free, set needs, no rent trouble
create or replace function pg_temp.f_home(p_uid uuid) returns void
language sql as $$
  update profiles set location_id = home_location_id, travel_to = null, busy_until = null, busy_label = null,
                      cash = 5000, rent_owed = 0, rent_due_at = bl_now() + interval '3 days',
                      hunger = 50, energy = 10, hygiene = 10, fun = 50, social = 50, stress = 40, health = 90,
                      bladder = 80, needs_updated_at = bl_now()
   where id = p_uid;
$$;

create or replace function pg_temp.f_hint(p_sql text, p_hint text) returns void
=======
-- Starter furniture by origin (20261006000400_starter_furniture.sql). Rolled back. Run:
--   bash scripts/sql-test.sh -- supabase/tests/furniture_test.sql
create or replace function pg_temp.expect_hint(p_sql text, p_hint text) returns void
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
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

<<<<<<< HEAD
do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  -- pin the numbers this file asserts (admins may retune the live rows; rolled back anyway)
  update activities set effects = '{"energy": 25, "stress": -5}' where id = 'nap';
  update activities set effects = '{"hygiene": 60, "stress": -3}' where id = 'bathe';
  update activities set night_only = false, cost = 0 where id in ('sleep','nap','bathe','cook_home','watch_tv','listen_radio');
  update furniture set activity_pct = '{"sleep": 100, "nap": 100}', active = true where id = 'foam_mattress';
  update furniture set activity_pct = '{"sleep": 110, "nap": 110}', active = true where id = 'bed';
  update game_config set value = '60' where key = 'rent.owed_sleep_energy_pct';
end $$;

-- ---------- 1. catalog and starter sets ----------
do $$
declare h record; ids text[]; bad text;
begin
  perform pg_temp.assert((select count(*) from furniture) >= 26, 'furniture catalog seeded');
  perform pg_temp.assert(exists (select 1 from information_schema.role_table_grants
                                  where table_name = 'furniture' and grantee = 'authenticated' and privilege_type = 'SELECT')
                         and not exists (select 1 from information_schema.role_table_grants
                                  where table_name = 'furniture' and grantee = 'authenticated' and privilege_type in ('INSERT','UPDATE','DELETE')),
                         'furniture: read-only for players');
  for h in select * from start_homes where id in ('uniben_hostel','ekenwan_face_me','aduwawa_face_me','uselu_self_contain',
                                                   'mission_rd_mini_flat','gra_duplex') loop
    -- LAPO: trench basics only
    select array_agg(e) into ids from jsonb_array_elements_text(h.furniture -> 'lapo') e;
    perform pg_temp.assert(ids @> '{water_drum,bucket,stool}', h.id || ': LAPO drum + bucket + stool');
    perform pg_temp.assert(exists (select 1 from furniture f where f.id = any (ids) and 'cook' = any (f.provides)
                                   and f.id in ('kerosene_stove','single_burner')), h.id || ': LAPO small stove');
    perform pg_temp.assert(not (ids && '{bed,king_bed,sofa,l_sofa,armchair,plastic_chair,tv,big_tv,fridge,gas_cooker,dining_set,rug}'),
                           h.id || ': LAPO has nothing fancy: ' || array_to_string(ids, ','));
    perform pg_temp.assert((select count(*) from furniture f where f.id = any (ids) and 'seat' = any (f.provides)) = 1,
                           h.id || ': LAPO has exactly one seat');
    perform pg_temp.assert(h.id = 'uniben_hostel' or ids && '{sleeping_mat,foam_mattress}', h.id || ': LAPO mat or foam');
    -- Nepo: decent, not mansion
    select array_agg(e) into ids from jsonb_array_elements_text(h.furniture -> 'nepo') e;
    perform pg_temp.assert(not (ids && '{king_bed,l_sofa,big_tv,dining_set}'), h.id || ': Nepo not mansion-level');
    if h.id <> 'uniben_hostel' then
      perform pg_temp.assert(ids @> '{bed,sofa,tv,fridge,gas_cooker}', h.id || ': Nepo bed, sofa, TV, fridge, gas cooker');
    end if;
    -- every id exists
    select string_agg(e, ',') into bad from jsonb_array_elements_text(h.furniture -> 'lapo') e
     where not exists (select 1 from furniture where id = e);
    perform pg_temp.assert(bad is null, h.id || ': unknown ids ' || coalesce(bad, ''));
  end loop;
  perform pg_temp.assert((select fixtures from start_homes where id = 'gra_duplex') = '{bathtub}', 'duplex bathtub fixture');
  perform pg_temp.assert((select fixtures from start_homes where id = 'uselu_self_contain') = '{shower}', 'self-contain shower');
  perform pg_temp.assert((select fixtures from start_homes where id = 'uniben_hostel') = '{hostel_bunk}', 'hostel bunk');
  perform pg_temp.assert((select requires from activities where id = 'bathe') = 'bath'
                         and (select requires from activities where id = 'sleep') = 'sleep'
                         and (select requires from activities where id = 'cook_home') = 'cook'
                         and (select requires from activities where id = 'use_toilet') is null, 'activity requirements');
  perform pg_temp.assert(bl_starter_furniture(null, 'nowhere', 'lapo') @> '{water_drum,bucket,stool,kerosene_stove,foam_mattress}',
                         'config fallback for an unknown home');
  update game_config set value = '"bucket,not_a_thing"' where key = 'origin.lapo.furniture';
  perform pg_temp.assert(bl_starter_furniture(null, 'nowhere', 'lapo') = '{bucket}', 'unknown fallback ids dropped');
  update game_config set value = '"water_drum,bucket,stool,kerosene_stove,foam_mattress"' where key = 'origin.lapo.furniture';
  raise notice 'ok 1: catalog and starter sets';
end $$;

-- ---------- 2. LAPO face-me: trench basics, bucket bath, kerosene stove, foam, no TV ----------
do $$
declare v uuid := pg_temp.f_make('Furn_Lapo', 'lapo', 'ekenwan_face_me'); s jsonb; r jsonb; me profiles;
begin
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.origin = 'lapo', 'is LAPO');
  perform pg_temp.assert(me.furniture @> '{water_drum,bucket,stool,kerosene_stove,foam_mattress}'
                         and cardinality(me.furniture) = 5, 'LAPO starter set: ' || array_to_string(me.furniture, ','));
  s := get_my_state();
  perform pg_temp.assert(jsonb_array_length(s->'home'->'furniture') = 5 and jsonb_array_length(s->'home'->'fixtures') = 0,
                         'home block: 5 pieces, no fixtures');
  perform pg_temp.assert(s->'home'->'activities'->'bathe'->>'label' = 'Bucket bath', 'bucket bath label');
  perform pg_temp.assert(s->'home'->'activities'->'cook_home'->>'via' = 'kerosene_stove', 'cooks on the kerosene stove');
  perform pg_temp.assert(s->'home'->'activities'->'sleep'->>'via' = 'foam_mattress'
                         and (s->'home'->'activities'->'sleep'->>'pct')::numeric = 100, 'sleeps on the foam at 100%');
  perform pg_temp.assert(not (s->'home'->'activities'->'watch_tv'->>'ok')::boolean
                         and s->'home'->'activities'->'watch_tv'->>'reason' ilike '%TV%', 'no TV, with a reason');
  perform pg_temp.assert((s->'home'->'activities'->'use_toilet'->>'ok')::boolean, 'toilet needs no furniture');
  perform pg_temp.assert(s->'profile'->'furniture' is not null, 'profile.furniture exposed');

  perform pg_temp.f_home(v);
  perform pg_temp.f_hint($q$ select do_activity('watch_tv') $q$, 'no_furniture');
  perform pg_temp.f_hint($q$ select do_activity('listen_radio') $q$, 'no_furniture');
  perform pg_temp.assert((select busy_until from profiles where id = v) is null, 'refused activity: not busy');
  r := do_activity('bathe');
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.busy_label = 'Bucket bath' and r->>'label' = 'Bucket bath' and r->>'message' ilike '%Bucket bath%',
                         'bath runs as "Bucket bath": ' || me.busy_label);
  perform pg_temp.assert(abs(me.hygiene - 70) < 0.05, 'bucket bath +60 hygiene');
  perform pg_temp.f_home(v);
  r := do_activity('nap');
  perform pg_temp.assert(abs((select energy from profiles where id = v) - 35) < 0.05, 'foam nap = base effect (25)');
  perform pg_temp.f_home(v);
  r := do_activity('cook_home');
  perform pg_temp.assert((select busy_label from profiles where id = v) ilike '%kerosene stove%', 'cooks on the kerosene stove');

  -- lose the stove and the foam: cooking and sleeping are refused with the reason
  update profiles set furniture = array_remove(array_remove(furniture, 'kerosene_stove'), 'foam_mattress') where id = v;
  perform pg_temp.f_home(v);
  perform pg_temp.f_hint($q$ select do_activity('cook_home') $q$, 'no_furniture');
  perform pg_temp.f_hint($q$ select do_activity('sleep') $q$, 'no_furniture');
  perform pg_temp.assert(get_my_state()->'home'->'activities'->'sleep'->>'reason' ilike '%sleep on%', 'sleep reason');
  -- a mat: sleeps again, at the mat percent
  update profiles set furniture = furniture || '{sleeping_mat}' where id = v;
  update furniture set activity_pct = '{"sleep": 95, "nap": 80}' where id = 'sleeping_mat';
  perform pg_temp.f_home(v);
  r := do_activity('nap');
  perform pg_temp.assert(abs((select energy from profiles where id = v) - 30) < 0.05, 'mat nap at 80% = +20');
  perform pg_temp.assert((select busy_label from profiles where id = v) = 'Nap on the mat', 'mat label');
  raise notice 'ok 2: LAPO face-me';
end $$;

-- ---------- 3. Nepo duplex: decent furniture, bathtub fixture, bed a bit better ----------
do $$
declare v uuid := pg_temp.f_make('Furn_Nepo', 'nepo', 'gra_duplex'); s jsonb; r jsonb; me profiles;
begin
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.origin = 'nepo', 'is Nepo');
  perform pg_temp.assert(me.furniture @> '{bed,sofa,tv,fridge,gas_cooker}' and not (me.furniture && '{stool,kerosene_stove,foam_mattress}'),
                         'Nepo starter set: ' || array_to_string(me.furniture, ','));
  s := get_my_state();
  perform pg_temp.assert(s->'home'->'fixtures' = '["bathtub"]'::jsonb, 'bathtub fixture');
  perform pg_temp.assert(s->'home'->'activities'->'bathe'->>'label' = 'Soak in the bathtub', 'bathtub label');
  perform pg_temp.assert((s->'home'->'activities'->'watch_tv'->>'ok')::boolean, 'can watch TV');
  perform pg_temp.assert(s->'home'->'activities'->'cook_home'->>'via' = 'gas_cooker', 'gas cooker');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(s->'home'->'items') i
                                  where i->>'id' = 'bathtub' and (i->>'fixture')::boolean), 'items mark fixtures');
  perform pg_temp.f_home(v);
  r := do_activity('nap');
  select * into me from profiles where id = v;
  perform pg_temp.assert(abs(me.energy - 37.5) < 0.05, 'bed nap 110% = +27.5, got ' || me.energy);
  perform pg_temp.assert(abs(me.stress - 34.5) < 0.05, 'bed nap stress relief 110% = -5.5, got ' || me.stress);
  perform pg_temp.assert(me.busy_label = 'Nap in your bed', 'bed label');
  -- rent penalty still applies on top
  perform pg_temp.f_home(v);
  update profiles set rent_owed = 500 where id = v;
  r := do_activity('nap');
  perform pg_temp.assert(abs((select energy from profiles where id = v) - (10 + 27.5 * 0.6)) < 0.06 and (r->>'rent_penalty')::boolean,
                         'bed percent then rent penalty');
  perform pg_temp.f_home(v);
  r := do_activity('watch_tv');
  perform pg_temp.assert((select busy_label from profiles where id = v) = (select name from activities where id = 'watch_tv'),
                         'no label override: activity name');
  raise notice 'ok 3: Nepo duplex';
end $$;

-- ---------- 4. LAPO self-contain: shower fixture wins over the bucket; hostel bunk ----------
do $$
declare v uuid := pg_temp.f_make('Furn_Selfcon', 'lapo', 'uselu_self_contain'); w uuid; s jsonb;
begin
  s := get_my_state();
  perform pg_temp.assert(s->'home'->'activities'->'bathe'->>'via' = 'shower'
                         and s->'home'->'activities'->'bathe'->>'label' = 'Take a shower', 'shower beats bucket');
  w := pg_temp.f_make('Furn_Hostel', 'lapo', 'uniben_hostel');
  s := get_my_state();
  perform pg_temp.assert(s->'home'->'activities'->'sleep'->>'via' = 'hostel_bunk', 'hostel: sleeps on the hall bunk');
  perform pg_temp.assert(s->'home'->'activities'->'cook_home'->>'via' = 'single_burner', 'hostel: single burner');
  raise notice 'ok 4: fixtures';
end $$;

-- ---------- 5. existing players: backfill only fills empty lists; null never sticks ----------
do $$
declare v uuid := pg_temp.fu('Furn_Lapo'); w uuid := pg_temp.fu('Furn_Nepo');
begin
  update profiles set furniture = '{bucket,big_tv}' where id = v;
  -- the migration's backfill statement again: a Sim with a list is left alone
  update profiles p set furniture = bl_starter_furniture(p.start_home, p.housing_id, p.origin)
   where p.furniture is null and p.home_chosen;
  perform pg_temp.assert((select furniture from profiles where id = v) = '{bucket,big_tv}', 'bought/edited furniture kept');
  -- a Sim without a list (e.g. created before the migration) gets its origin + home starter set
  update profiles set furniture = null where id = w;
  perform pg_temp.assert((select furniture from profiles where id = w) @> '{bed,sofa,tv,fridge,gas_cooker}', 'null -> Nepo starter set');
  -- a v1 Sim (no start home): by housing
  perform pg_temp.assert(bl_starter_furniture(null, 'face_me_ekenwan', 'lapo') = bl_starter_furniture('ekenwan_face_me', null, 'lapo'),
                         'v1 Sim: start home found by housing');
  raise notice 'ok 5: backfill rule';
end $$;

-- ---------- 6. admin: furniture table, start_homes validation, admin_set_furniture ----------
do $$
declare v_admin uuid := pg_temp.new_user('boss@furniture.bl'); v uuid := pg_temp.fu('Furn_Lapo'); r jsonb;
begin
  insert into t_fu values ('Furn_Admin', v_admin);
  perform pg_temp.login(v_admin);
  update game_config set value = '""' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2('Furn_Boss', 'male', '{"gender":"male"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  update profiles set is_admin = true where id = v_admin;

  perform pg_temp.assert(jsonb_array_length(admin_table_rows('furniture')) = (select count(*) from furniture), 'admin reads furniture');
  perform admin_row_upsert('furniture', '{"id":"foam_mattress","activity_pct":{"sleep":100,"nap":80}}');
  perform admin_row_upsert('furniture', '{"id":"bucket","labels":{"bathe":"Bucket and sponge bath"}}');
  perform admin_row_upsert('start_homes', '{"id":"aduwawa_face_me","furniture":{"lapo":["water_drum","bucket","stool","kerosene_stove","sleeping_mat"],"nepo":["bed","tv"]}}');
  perform pg_temp.assert((select furniture->'lapo' from start_homes where id = 'aduwawa_face_me') ? 'sleeping_mat', 'start home list edited');
  perform pg_temp.f_hint($q$ select admin_row_upsert('start_homes', '{"id":"aduwawa_face_me","furniture":{"lapo":["golden_throne"]}}') $q$, 'bad_value');
  perform pg_temp.f_hint($q$ select admin_row_upsert('start_homes', '{"id":"aduwawa_face_me","furniture":{"royal":["bed"]}}') $q$, 'bad_value');
  perform pg_temp.f_hint($q$ select admin_row_upsert('start_homes', '{"id":"aduwawa_face_me","fixtures":["jacuzzi"]}') $q$, 'bad_value');
  perform admin_row_upsert('activities', '{"id":"bathe","requires_note":"Get a bucket first."}');
  perform pg_temp.assert(bl_starter_furniture('aduwawa_face_me', null, 'nepo') = '{bed,tv}', 'edited Nepo list used');
  r := admin_set_furniture(v, null);
  perform pg_temp.assert((select furniture from profiles where id = v) = bl_starter_furniture('ekenwan_face_me', null, 'lapo'),
                         'admin reset to the starter set');
  r := admin_set_furniture(v, '{bed,bucket}');
  perform pg_temp.assert((select furniture from profiles where id = v) = '{bed,bucket}', 'admin set list');
  perform pg_temp.f_hint(format('select admin_set_furniture(%L, ''{flying_carpet}'')', v), 'bad_value');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'set_furniture' and target_user = v), 'audited');

  -- tuned values reach the player
  perform pg_temp.login(v);
  update profiles set furniture = '{water_drum,bucket,stool,kerosene_stove,foam_mattress}' where id = v;
  perform pg_temp.f_home(v);
  perform do_activity('nap');
  perform pg_temp.assert(abs((select energy from profiles where id = v) - 30) < 0.05, 'admin-tuned foam nap 80%');
  perform pg_temp.assert(get_my_state()->'home'->'activities'->'bathe'->>'label' = 'Bucket and sponge bath', 'admin-tuned label');
  update profiles set furniture = '{water_drum}' where id = v;
  perform pg_temp.assert(get_my_state()->'home'->'activities'->'bathe'->>'reason' = 'Get a bucket first.', 'admin-tuned reason');

  -- players can't call it
  perform pg_temp.f_hint(format('select admin_set_furniture(%L, null)', v), 'not_admin');
  raise notice 'ok 6: admin';
end $$;

do $$ begin raise notice 'furniture_test PASSED'; end $$;
=======
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
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
