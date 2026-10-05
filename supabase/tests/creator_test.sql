-- Creator tests (R3a): traits, dreams, start homes, create_profile_v2 -> choose_start_home,
-- no_home guard, rent, origin.force_next, admin_set_origin, Dad copy. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/creator_test.sql
-- Rolled back at the end. Rolls forced with bl.test_rand, time with bl.test_offset_seconds.
-- Rent is ON since V1-4 (20261005000800_shops.sql); these tests start with it off on purpose (the
-- "while off the due date rolls" path) and switch it on in group 6.
update public.game_config set value = 'false' where key = 'rent.enabled';

-- ---------- local helpers (standalone; safe if other test files defined them) ----------
create or replace function pg_temp.expect_error(p_sql text, p_like text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
    if sqlerrm not ilike p_like then
      raise exception 'TEST FAILED: [%] expected error like "%", got: %', p_sql, p_like, sqlerrm;
    end if;
    return;
  end;
  raise exception 'TEST FAILED: [%] expected error like "%" but it succeeded', p_sql, p_like;
end $$;

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

create or replace function pg_temp.advance(p_seconds numeric) returns numeric
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
  return v;
end $$;

create temp table t_cu (name text primary key, id uuid not null) on commit drop;
create or replace function pg_temp.cu(p_name text) returns uuid
language sql as $$ select id from t_cu where name = p_name $$;

-- new auth user (logged in) + v2 profile; p_force = origin.force_next ('' = roll with p_rand)
create or replace function pg_temp.make_v2(p_name text, p_force text, p_rand text,
                                          p_traits text[] default '{hustler,foodie}', p_dream text default 'oga_at_the_top')
returns jsonb language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@creator.bl'); s jsonb;
begin
  insert into t_cu values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = to_jsonb(p_force) where key = 'origin.force_next';
  perform set_config('bl.test_rand', p_rand, true);
  s := create_profile_v2(p_name, 'male', '{"gender":"male"}', p_traits, p_dream);
  perform set_config('bl.test_rand', '', true);
  return s;
end $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);   -- earlier test files may leave time travelled
  perform set_config('bl.test_rand', '', true);
end $$;

-- ---------- 0. seeds, config, RLS, privileges ----------
do $$
declare r record; k text;
begin
  perform pg_temp.assert((select count(*) from traits where active) >= 10, 'at least 10 active traits');
  perform pg_temp.assert((select count(*) from dreams where active) >= 5, 'at least 5 active dreams');
  perform pg_temp.assert((select count(*) from start_homes where active) = 6, '6 start homes');
  perform pg_temp.assert(not exists (select 1 from traits where name = '' or emoji = '' or description = ''), 'trait copy filled');
  perform pg_temp.assert(not exists (select 1 from dreams where goal->>'type' is null), 'every dream has a goal type');
  -- every decay key is a real need and every multiplier is a positive number
  perform pg_temp.assert(not exists (
    select 1 from traits t, jsonb_each(coalesce(t.effects->'decay', '{}')) e
    where e.key not in ('hunger','energy','hygiene','fun','social','stress')
       or jsonb_typeof(e.value) <> 'number' or (e.value #>> '{}')::numeric <= 0), 'trait decay keys valid');
  -- homes: real home locations where sleeping works, origins exist, locked homes have a quip
  for r in select h.*, l.scene from start_homes h join locations l on l.id = h.location_id loop
    perform pg_temp.assert(exists (select 1 from activities a where a.id = 'sleep' and r.scene = any (a.scenes)),
                           'can sleep at home ' || r.id);
    perform pg_temp.assert(not exists (select 1 from unnest(r.allowed_origins) o where o not in (select id from origin_tiers)),
                           'allowed origins exist for ' || r.id);
    perform pg_temp.assert(cardinality(r.allowed_origins) = 0 or r.locked_quip <> '', 'locked quip for ' || r.id);
  end loop;
  perform pg_temp.assert((select allowed_origins from start_homes where id = 'gra_duplex') = '{nepo}', 'duplex nepo-only');
  perform pg_temp.assert((select allowed_origins from start_homes where id = 'mission_rd_mini_flat') = '{nepo}', 'mini-flat nepo-only');
  perform pg_temp.assert((select location_id from start_homes where id = 'aduwawa_face_me') = 'aduwawa_room', 'aduwawa home');
  foreach k in array array['origin.force_next','creator.trait_count','creator.arrival_location','rent.enabled',
                           'rent.due_weekday','rent.first_due_grace_game_days','rent.max_catchup_weeks'] loop
    perform pg_temp.assert(exists (select 1 from game_config where key = k and label <> '' and category <> ''), 'config ' || k);
  end loop;
  perform pg_temp.assert(bl_cfg('creator.trait_count') = 2, 'two traits per Sim');
  perform pg_temp.assert((select jsonb_typeof(value) from game_config where key = 'rent.enabled') = 'boolean', 'rent.enabled is a bool');
  -- RLS + helper privileges
  foreach k in array array['traits','dreams','start_homes','admin_audit'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || k)::regclass), 'RLS on ' || k);
  end loop;
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'bl\_%' loop
    perform pg_temp.assert(not has_function_privilege('authenticated', r.sig, 'execute')
                           and not has_function_privilege('anon', r.sig, 'execute'), 'helper exposed: ' || r.sig::text);
  end loop;
  foreach k in array array['create_profile_v2(text,text,jsonb,text[],text)','choose_start_home(text)',
                           'admin_set_origin(uuid,text,boolean)'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || k)::regprocedure, 'execute'), 'granted ' || k);
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || k)::regprocedure, 'execute'), 'not anon ' || k);
    perform pg_temp.assert((select prosecdef and proconfig @> array['search_path=public'] from pg_proc
                            where oid = ('public.' || k)::regprocedure), 'definer+search_path ' || k);
  end loop;
  perform pg_temp.assert(has_function_privilege('anon', 'public.creator_catalog()', 'execute'), 'catalog for anon');
  -- force_next: only empty or a real tier id
  perform pg_temp.expect_error($q$ update game_config set value = '"royal"' where key = 'origin.force_next' $q$, '%force_next%');
  raise notice 'ok 0: seeds, config, RLS, privileges';
end $$;

set local role anon;
do $$
declare ok boolean := false; c jsonb;
begin
  if (select count(*) from traits) < 10 or (select count(*) from start_homes) < 6 then
    raise exception 'TEST FAILED: anon cannot read creator catalogs';
  end if;
  begin insert into traits (id, name) values ('hax', 'Hax'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: anon could insert traits'; end if;
  ok := false;
  begin perform count(*) from admin_audit; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: anon could read admin_audit'; end if;
  c := creator_catalog();
  if (c->>'trait_count')::int <> 2 or jsonb_array_length(c->'traits') < 10 or jsonb_array_length(c->'homes') <> 6 then
    raise exception 'TEST FAILED: creator_catalog %', c;
  end if;
  raise notice 'ok 0b: anon reads catalogs, cannot write';
end $$;
reset role;

-- ---------- 1. traits / dream validation ----------
do $$
declare v uuid := pg_temp.new_user('invalid@creator.bl');
begin
  insert into t_cu values ('invalid', v);
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  perform pg_temp.expect_hint($q$ select create_profile_v2('Bad_T', 'male', '{}', '{hustler}', 'oga_at_the_top') $q$, 'bad_traits');
  perform pg_temp.expect_hint($q$ select create_profile_v2('Bad_T', 'male', '{}', '{hustler,foodie,musical}', 'oga_at_the_top') $q$, 'bad_traits');
  perform pg_temp.expect_error($q$ select create_profile_v2('Bad_T', 'male', '{}', '{hustler,hustler}', 'oga_at_the_top') $q$, '%different%');
  perform pg_temp.expect_error($q$ select create_profile_v2('Bad_T', 'male', '{}', '{hustler,flying}', 'oga_at_the_top') $q$, '%doesn''t exist%');
  perform pg_temp.expect_hint($q$ select create_profile_v2('Bad_T', 'male', '{}', null, 'oga_at_the_top') $q$, 'bad_traits');
  update traits set active = false where id = 'musical';
  perform pg_temp.expect_hint($q$ select create_profile_v2('Bad_T', 'male', '{}', '{hustler,musical}', 'oga_at_the_top') $q$, 'bad_traits');
  update traits set active = true where id = 'musical';
  perform pg_temp.expect_hint($q$ select create_profile_v2('Bad_T', 'male', '{}', '{hustler,musical}', 'world_peace') $q$, 'bad_dream');
  perform pg_temp.expect_hint($q$ select create_profile_v2('Bad_T', 'male', '{}', '{hustler,musical}', null) $q$, 'bad_dream');
  update dreams set active = false where id = 'afrobeats_star';
  perform pg_temp.expect_hint($q$ select create_profile_v2('Bad_T', 'male', '{}', '{hustler,musical}', 'afrobeats_star') $q$, 'bad_dream');
  update dreams set active = true where id = 'afrobeats_star';
  -- the shared v1 validation still applies
  perform pg_temp.expect_error($q$ select create_profile_v2('ab', 'male', '{}', '{hustler,musical}', 'oga_at_the_top') $q$, '%3 to 20%');
  perform pg_temp.expect_error($q$ select create_profile_v2('Bad_T', 'robot', '{}', '{hustler,musical}', 'oga_at_the_top') $q$, '%male or female%');
  perform pg_temp.assert(not exists (select 1 from profiles where id = v), 'failed creates leave no profile');
  -- a valid pick is normalised (case/space) and stored
  perform create_profile_v2('Good_T', 'female', '{"gender":"female"}', array[' Musical', 'NEAT_FREAK'], ' Afrobeats_Star ');
  perform pg_temp.assert((select traits from profiles where id = v) = '{musical,neat_freak}', 'traits stored');
  perform pg_temp.assert((select dream from profiles where id = v) = 'afrobeats_star', 'dream stored');
  perform pg_temp.expect_error($q$ select create_profile_v2('Other_T', 'male', '{}', '{hustler,musical}', 'oga_at_the_top') $q$, '%already created%');
  raise notice 'ok 1: traits + dream validation';
end $$;

-- ---------- 2. trait decay multipliers ----------
do $$
declare a profiles; b profiles; da profiles; db profiles; h1 profiles; t0 timestamptz := bl_now();
begin
  select * into a from profiles where id = pg_temp.cu('invalid');   -- any row works as a template
  a.traits := '{foodie,lazy_bone}';
  a.hunger := 80; a.energy := 80; a.hygiene := 80; a.fun := 80; a.social := 80; a.stress := 10; a.health := 100;
  a.needs_updated_at := t0;
  b := a; b.traits := '{}';
  -- one real hour = 12 game hours at 12x
  da := bl_decay_row(a, t0 + interval '1 hour');
  db := bl_decay_row(b, t0 + interval '1 hour');
  perform pg_temp.assert(abs((80 - db.hunger) - 4 * 12) < 0.001, 'base hunger decay 48, got ' || (80 - db.hunger));
  perform pg_temp.assert(abs((80 - da.hunger) - 4 * 1.15 * 12) < 0.001, 'foodie hunger x1.15, got ' || (80 - da.hunger));
  perform pg_temp.assert(abs((80 - da.energy) - 3 * 0.8 * 12) < 0.001, 'lazy bone energy x0.8, got ' || (80 - da.energy));
  perform pg_temp.assert(da.hygiene = db.hygiene and da.fun = db.fun and da.social = db.social, 'other needs unchanged');
  -- multipliers stack across both traits
  a.traits := '{foodie,gym_rat}';
  da := bl_decay_row(a, t0 + interval '1 hour');
  perform pg_temp.assert(abs((80 - da.hunger) - 4 * 1.15 * 1.1 * 12) < 0.001, 'foodie+gym rat hunger stacks');
  -- still path-independent
  h1 := bl_decay_row(bl_decay_row(a, t0 + interval '20 minutes'), t0 + interval '1 hour');
  perform pg_temp.assert(abs(h1.hunger - da.hunger) < 0.001 and abs(h1.energy - da.energy) < 0.001, 'decay path-independent with traits');
  -- admin-tunable: the multiplier lives in the traits table
  update traits set effects = jsonb_set(effects, '{decay,hunger}', '2') where id = 'foodie';
  a.traits := '{foodie,lazy_bone}';
  da := bl_decay_row(a, t0 + interval '20 minutes');   -- 4 game hours (no clamp at 0)
  perform pg_temp.assert(abs((80 - da.hunger) - 4 * 2 * 4) < 0.001, 'edited multiplier applies, got ' || (80 - da.hunger));
  update traits set effects = jsonb_set(effects, '{decay,hunger}', '1.15') where id = 'foodie';
  raise notice 'ok 2: trait decay multipliers';
end $$;

-- ---------- 3. v2 flow: LAPO ----------
do $$
declare s jsonb; p jsonb; v uuid; h jsonb; ev text; clk jsonb; v_me profiles; other uuid;
begin
  s := pg_temp.make_v2('Lapo_V2', '', '0.5');
  v := pg_temp.cu('Lapo_V2');
  p := s->'profile';
  perform pg_temp.assert(p->>'origin' = 'lapo', 'rolled lapo');
  perform pg_temp.assert(not (p->>'home_chosen')::boolean and not (s->'creator'->>'home_chosen')::boolean, 'no home yet');
  perform pg_temp.assert((p->>'cash')::bigint = 0 and (p->>'bank')::bigint = 0, 'nothing paid yet');
  perform pg_temp.assert(p->>'location_id' = 'uselu_park' and s->'location'->>'id' = 'uselu_park', 'waiting at the arrival park');
  perform pg_temp.assert(jsonb_typeof(p->'housing_id') = 'null' and jsonb_typeof(p->'start_home') = 'null', 'no housing yet');
  perform pg_temp.assert(s->'creator'->'traits' = '["hustler","foodie"]'::jsonb and s->'creator'->>'dream' = 'oga_at_the_top', 'creator picks echoed');
  perform pg_temp.assert(s->'origin'->>'id' = 'lapo', 'origin block present');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = v), 'no ledger yet');
  perform pg_temp.assert(not exists (select 1 from events where user_id = v), 'no welcome yet');
  perform pg_temp.assert(jsonb_array_length(s->'creator'->'homes') = 6, 'six homes offered');
  select x into h from jsonb_array_elements(s->'creator'->'homes') x where x->>'id' = 'gra_duplex';
  perform pg_temp.assert(not (h->>'allowed')::boolean and h->>'locked_quip' ilike '%LAPO%', 'duplex locked for LAPO with quip');
  select x into h from jsonb_array_elements(s->'creator'->'homes') x where x->>'id' = 'uniben_hostel';
  perform pg_temp.assert((h->>'allowed')::boolean and jsonb_typeof(h->'locked_quip') = 'null'
                         and (h->>'start_cash')::bigint = 6000 and (h->>'weekly_rent')::bigint = 1000
                         and h->>'location_id' = 'uniben_hostel', 'hostel offered with LAPO cash: ' || h::text);
  -- get_my_state routes back to the home step after a reload
  s := get_my_state();
  perform pg_temp.assert(not (s->'creator'->>'home_chosen')::boolean and jsonb_array_length(s->'creator'->'homes') = 6, 'reload shows home step');

  -- gameplay refused until a home is chosen
  perform pg_temp.expect_hint($q$ select travel_quote('uselu_market') $q$, 'no_home');
  perform pg_temp.expect_hint($q$ select travel_start('uselu_market', 'walk') $q$, 'no_home');
  perform pg_temp.expect_hint($q$ select do_activity('gist_joint') $q$, 'no_home');
  perform pg_temp.expect_hint($q$ select claim_allowance() $q$, 'no_home');
  perform pg_temp.expect_error($q$ select travel_quote('uselu_market') $q$, '%choose where you will live%');
  -- the look can still be edited
  perform update_avatar('{"gender":"male","v":2}');
  -- hidden from "People here"
  other := pg_temp.new_user('watcher@creator.bl');
  perform pg_temp.login(other);
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile('Watcher_1', 'male', '{}');
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(not (players_here('uselu_park') @> jsonb_build_array(jsonb_build_object('id', v))), 'limbo Sim hidden');
  perform pg_temp.login(v);

  -- LAPO cannot pick a Nepo-only home; unknown home rejected
  perform pg_temp.expect_hint($q$ select choose_start_home('gra_duplex') $q$, 'home_locked');
  perform pg_temp.expect_error($q$ select choose_start_home('mission_rd_mini_flat') $q$, '%LAPO money%');
  perform pg_temp.expect_hint($q$ select choose_start_home('atlantis') $q$, 'bad_home');

  perform pg_temp.advance(600);   -- needs/protection restart at move-in, not at creation
  s := choose_start_home('ekenwan_face_me');
  p := s->'profile';
  perform pg_temp.assert(s->>'message' ilike '%Ekenwan%', 'move-in message');
  perform pg_temp.assert((p->>'home_chosen')::boolean and p->>'start_home' = 'ekenwan_face_me', 'home chosen');
  perform pg_temp.assert(p->>'location_id' = 'ekenwan_room' and p->>'home_location_id' = 'ekenwan_room', 'moved to Ekenwan');
  perform pg_temp.assert(p->>'housing_id' = 'face_me_ekenwan', 'housing id');
  perform pg_temp.assert((p->>'cash')::bigint = 8000 and (p->>'bank')::bigint = 0, 'LAPO Ekenwan cash 8000, got ' || (p->>'cash'));
  perform pg_temp.assert(not exists (select 1 from inventory where user_id = v), 'LAPO bag empty');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'start_bonus' and delta = 8000
                                 and meta->>'home' = 'ekenwan_face_me' and meta->>'origin' = 'lapo'), 'start_bonus ledger');
  perform pg_temp.assert(abs((p->>'hunger')::numeric - 80) < 0.01, 'fresh needs');
  perform pg_temp.assert((p->>'protected_until')::timestamptz = bl_now() + interval '120 minutes', 'protection from move-in');
  perform pg_temp.assert(s->'creator'->'homes' = 'null'::jsonb, 'no homes list once housed');
  -- rent stored: weekly amount + first rent day (Saturday 00:00, at least 1 game day away)
  select * into v_me from profiles where id = v;
  perform pg_temp.assert(v_me.weekly_rent = 1500 and v_me.rent_owed = 0, 'weekly rent 1500');
  perform pg_temp.assert(v_me.rent_due_at >= bl_now() + interval '7200 seconds'
                         and v_me.rent_due_at < bl_now() + interval '7200 seconds' * 8, 'first due within grace..grace+7 days');
  clk := bl_game_clock(v_me.rent_due_at);
  perform pg_temp.assert((clk->>'weekday')::int = 5 and (clk->>'hour')::int = 0 and (clk->>'minute')::int = 0,
                         'rent due Saturday 00:00, got ' || clk::text);
  perform pg_temp.assert((s->'rent'->>'weekly')::bigint = 1500 and (s->'rent'->>'due_at')::timestamptz = v_me.rent_due_at, 'rent block');
  select body into ev from events where user_id = v and kind = 'welcome';
  perform pg_temp.assert(ev ilike '%Ekenwan%' and ev ilike '%₦8,000%' and ev ilike '%Rent is ₦1,500 a week%' and ev not ilike '%Papa%',
                         'LAPO welcome: ' || coalesce(ev, 'null'));
  -- once only
  perform pg_temp.expect_hint($q$ select choose_start_home('uniben_hostel') $q$, 'home_already_chosen');
  perform pg_temp.assert((select cash from profiles where id = v) = 8000, 'no double pay');
  -- gameplay works now
  perform travel_quote('national_museum');
  raise notice 'ok 3: v2 LAPO flow';
end $$;

-- ---------- 4. force_next + v2 Nepo flow ----------
do $$
declare s jsonb; p jsonb; v uuid; ev text; h jsonb; n_audit int;
begin
  n_audit := (select count(*) from config_audit where key = 'origin.force_next');
  s := pg_temp.make_v2('Nepo_V2', 'nepo', '0.99', '{tech_sibling,night_crawler}', 'benin_tech_unicorn');
  v := pg_temp.cu('Nepo_V2');
  perform pg_temp.assert(s->'profile'->>'origin' = 'nepo', 'force_next beats a LAPO roll');
  perform pg_temp.assert(bl_cfg_text('origin.force_next') = '', 'force_next reset after use');
  perform pg_temp.assert((select count(*) from config_audit where key = 'origin.force_next') = n_audit + 1
                         and exists (select 1 from config_audit where key = 'origin.force_next' and old_value = '"nepo"' and new_value = '""'),
                         'force_next reset is audited');
  select x into h from jsonb_array_elements(s->'creator'->'homes') x where x->>'id' = 'gra_duplex';
  perform pg_temp.assert((h->>'allowed')::boolean and (h->>'start_cash')::bigint = 50000 and (h->>'start_bank')::bigint = 500000,
                         'duplex open for Nepo: ' || h::text);
  s := choose_start_home('gra_duplex');
  p := s->'profile';
  perform pg_temp.assert(p->>'location_id' = 'gra_duplex' and p->>'housing_id' = 'duplex_gra', 'Nepo in the duplex');
  perform pg_temp.assert((p->>'cash')::bigint = 50000 and (p->>'bank')::bigint = 500000, 'Nepo money');
  perform pg_temp.assert((select qty from inventory where user_id = v and item_id = 'tokunbo_car') = 1
                         and (select qty from inventory where user_id = v and item_id = 'laptop') = 1, 'Nepo items');
  perform pg_temp.assert((p->>'weekly_rent')::bigint = 25000, 'duplex rent');
  select body into ev from events where user_id = v and kind = 'welcome';
  perform pg_temp.assert(ev ilike '%Dad%' and ev ilike '%GRA Duplex%' and ev ilike '%₦500,000%' and ev not ilike '%Papa%',
                         'Nepo welcome: ' || coalesce(ev, 'null'));
  -- next account rolls normally again
  s := pg_temp.make_v2('After_Force', '', '0.99');
  perform pg_temp.assert(s->'profile'->>'origin' = 'lapo', 'normal roll after the one-shot');
  -- v1 create_profile honours force_next too
  perform pg_temp.login(pg_temp.new_user('v1force@creator.bl'));
  update game_config set value = '"nepo"' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  s := create_profile('V1_Force', 'female', '{}');
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(s->'profile'->>'origin' = 'nepo' and (s->'profile'->>'home_chosen')::boolean
                         and s->'profile'->>'location_id' = 'gra_duplex', 'v1 honours force_next, all-in-one');
  perform pg_temp.assert(bl_cfg_text('origin.force_next') = '', 'v1 resets force_next');
  -- force_next 'lapo' beats a Nepo roll
  s := pg_temp.make_v2('Force_Lapo', 'lapo', '0.01');
  perform pg_temp.assert(s->'profile'->>'origin' = 'lapo', 'force_next lapo');
  raise notice 'ok 4: force_next + v2 Nepo flow';
end $$;

-- ---------- 5. admin_set_origin ----------
do $$
declare r jsonb; v uuid := pg_temp.cu('Lapo_V2'); adm uuid := pg_temp.new_user('admin@creator.bl'); a admin_audit;
begin
  -- not an admin
  perform pg_temp.login(pg_temp.cu('Nepo_V2'));
  perform pg_temp.expect_hint(format('select admin_set_origin(%L, %L)', v, 'nepo'), 'not_admin');
  perform pg_temp.assert((select origin from profiles where id = v) = 'lapo', 'non-admin changed nothing');
  -- make an admin
  perform pg_temp.login(adm);
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile('Admin_1', 'male', '{}');
  perform set_config('bl.test_rand', '', true);
  update profiles set is_admin = true where id = adm;
  perform pg_temp.expect_hint(format('select admin_set_origin(%L, %L)', v, 'royal'), 'bad_origin');
  perform pg_temp.expect_hint(format('select admin_set_origin(%L, %L)', gen_random_uuid(), 'nepo'), 'no_player');

  -- without perks: only the origin changes
  r := admin_set_origin(v, 'nepo');
  perform pg_temp.assert(r->>'old' = 'lapo' and r->>'new' = 'nepo', 'result old/new');
  perform pg_temp.assert((select origin from profiles where id = v) = 'nepo', 'origin changed');
  perform pg_temp.assert((select cash from profiles where id = v) = 8000 and (select bank from profiles where id = v) = 0, 'no money without perks');
  perform pg_temp.assert(not exists (select 1 from inventory where user_id = v), 'no items without perks');
  select * into a from admin_audit where target_user = v order by id desc limit 1;
  perform pg_temp.assert(a.admin_id = adm and a.action = 'set_origin' and a.data->>'old' = 'lapo' and a.data->>'new' = 'nepo'
                         and not (a.data->>'apply_perks')::boolean, 'audit row');
  perform pg_temp.assert(exists (select 1 from events where user_id = v and kind = 'origin_changed' and body ilike '%Dad%'), 'player told');

  -- back to LAPO, then Nepo with perks: tops up the difference at the player's start home
  perform admin_set_origin(v, 'lapo');
  r := admin_set_origin(v, 'nepo', true);
  perform pg_temp.assert((r->>'cash')::bigint = 80000 - 8000 and (r->>'bank')::bigint = 500000, 'perk top-up amounts: ' || r::text);
  perform pg_temp.assert((select cash from profiles where id = v) = 80000 and (select bank from profiles where id = v) = 500000, 'topped up');
  perform pg_temp.assert((select count(*) from inventory where user_id = v and qty = 1) = 2, 'items given');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'admin_origin' and account = 'bank' and delta = 500000), 'admin_origin ledger');
  perform pg_temp.assert((select home_location_id from profiles where id = v) = 'ekenwan_room', 'home unchanged');
  select * into a from admin_audit where target_user = v order by id desc limit 1;
  perform pg_temp.assert((a.data->>'apply_perks')::boolean and (a.data->>'cash')::bigint = 72000, 'perk audit');
  -- again: nothing more to top up, items not duplicated
  r := admin_set_origin(v, 'nepo', true);
  perform pg_temp.assert((r->>'cash')::bigint = 0 and (r->>'bank')::bigint = 0 and jsonb_array_length(r->'items') = 0, 'no double top-up');
  perform pg_temp.assert((select sum(qty) from inventory where user_id = v) = 2, 'no duplicate items');
  -- going down never takes money away
  r := admin_set_origin(v, 'lapo', true);
  perform pg_temp.assert((select cash from profiles where id = v) = 80000 and (select bank from profiles where id = v) = 500000, 'downgrade keeps money');
  -- a Sim still choosing a home gets the new tier's pack at move-in instead
  r := admin_set_origin(pg_temp.cu('After_Force'), 'nepo', true);
  perform pg_temp.assert((r->>'cash')::bigint = 0 and (select cash from profiles where id = pg_temp.cu('After_Force')) = 0, 'no top-up before move-in');
  perform pg_temp.login(pg_temp.cu('After_Force'));
  perform pg_temp.assert((choose_start_home('gra_duplex')->'profile'->>'bank')::bigint = 500000, 'new tier applies at move-in');
  raise notice 'ok 5: admin_set_origin';
end $$;

-- ---------- 6. rent ----------
do $$
declare v uuid := pg_temp.cu('Force_Lapo'); me profiles; due0 timestamptz; due1 timestamptz; n int; week numeric;
begin
  perform pg_temp.login(v);
  perform choose_start_home('uniben_hostel');   -- rent 1000/wk, LAPO cash 6000
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.weekly_rent = 1000 and me.cash = 6000, 'hostel rent + cash');
  due0 := me.rent_due_at;
  week := 7 * 1440 * 60 / bl_cfg('clock.game_minutes_per_real_minute');   -- real seconds per game week

  -- charging off: the due date rolls forward silently
  perform set_config('bl.test_offset_seconds', (extract(epoch from due0 - now()) + 60)::text, true);
  perform pg_temp.assert(bl_now() > due0, 'time travelled past the rent day');
  perform get_my_state();   -- read-only: no charge, no roll
  perform pg_temp.assert((select rent_due_at from profiles where id = v) = due0, 'get_my_state never touches rent');
  perform travel_quote('national_museum');
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.cash = 6000 and not exists (select 1 from ledger where user_id = v and reason = 'rent'), 'no charge while off');
  perform pg_temp.assert(abs(extract(epoch from me.rent_due_at - due0) - week) < 1, 'due date rolled one week');

  -- charging on
  update game_config set value = 'true' where key = 'rent.enabled';
  due1 := me.rent_due_at;
  perform set_config('bl.test_offset_seconds', (extract(epoch from due1 - now()) + 60)::text, true);
  perform travel_quote('national_museum');
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.cash = 5000 and me.rent_owed = 0, 'one week charged from cash, got ' || me.cash);
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'rent' and delta = -1000 and account = 'cash'), 'rent ledger');
  perform pg_temp.assert(abs(extract(epoch from me.rent_due_at - due1) - week) < 1, 'next due one week later');
  perform pg_temp.assert(exists (select 1 from events where user_id = v and kind = 'rent_paid'), 'rent_paid event');
  -- calling again the same moment does not double-charge
  perform travel_quote('national_museum');
  perform pg_temp.assert((select cash from profiles where id = v) = 5000, 'no double charge');

  -- bank pays first; a shortfall becomes rent owed
  update profiles set bank = 300 where id = v;
  perform bl_add_money(v, 'cash', -4800, 'test');   -- cash 200
  perform pg_temp.advance(week);
  perform travel_quote('national_museum');
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.bank = 0 and me.cash = 0 and me.rent_owed = 500, 'paid 300 bank + 200 cash, owes 500: ' || me.rent_owed);
  perform pg_temp.assert(exists (select 1 from events where user_id = v and kind = 'rent_owed' and body ilike '%₦500%'), 'rent_owed event');
  -- next week: owed + weekly
  perform bl_add_money(v, 'cash', 10000, 'test');
  perform pg_temp.advance(week);
  perform travel_quote('national_museum');
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.cash = 10000 - 1500 and me.rent_owed = 0, 'owed + weekly paid: ' || me.cash);
  -- long absence: at most rent.max_catchup_weeks weeks charged
  perform pg_temp.advance(week * 10);
  select count(*) into n from ledger where user_id = v and reason = 'rent';
  perform travel_quote('national_museum');
  perform pg_temp.assert((select cash from profiles where id = v) = 8500 - 4 * 1000, 'capped at 4 weeks');
  perform pg_temp.assert((select rent_due_at from profiles where id = v) > bl_now(), 'due date in the future again');
  update game_config set value = 'false' where key = 'rent.enabled';
  perform set_config('bl.test_offset_seconds', '', true);
  raise notice 'ok 6: rent stored, rolled, charged';
end $$;

-- ---------- 7. Dad copy ----------
do $$
declare r jsonb; v uuid := pg_temp.cu('Nepo_V2');
begin
  perform pg_temp.login(v);
  update profiles set allowance_claimed_day = null where id = v;
  r := claim_allowance();
  perform pg_temp.assert(r->>'message' ilike 'Dad sent ₦5,000%' and r->>'message' not ilike '%Papa%', 'Dad allowance message: ' || (r->>'message'));
  perform pg_temp.expect_error($q$ select claim_allowance() $q$, '%Dad has already sent%');
  perform pg_temp.assert(not exists (select 1 from origin_tiers where tagline ilike '%papa%' or welcome ilike '%papa%'), 'no Papa in tiers');
  perform pg_temp.assert(not exists (select 1 from game_config where label ilike '%papa%' or description ilike '%papa%'), 'no Papa in config labels');
  perform pg_temp.assert((select tagline from origin_tiers where id = 'nepo') ilike '%Dad%', 'Nepo tagline says Dad');
  perform pg_temp.login(pg_temp.cu('Lapo_V2'));
  update profiles set origin = 'lapo' where id = pg_temp.cu('Lapo_V2');
  perform pg_temp.expect_error($q$ select claim_allowance() $q$, '%No Dad allowance%');
  raise notice 'ok 7: Dad copy';
end $$;

do $$ begin raise notice 'ALL CREATOR TESTS PASSED'; end $$;
