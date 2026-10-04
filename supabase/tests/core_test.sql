-- Core tests (P1-DB). Run:
--   bash scripts/sql-test.sh supabase/migrations/20261004000100_core.sql supabase/migrations/20261004000200_core_seed.sql -- supabase/tests/core_test.sql
-- Everything runs as one transaction that is rolled back. now() is frozen inside it, so time only
-- moves via bl.test_offset_seconds (pg_temp.advance) — fully deterministic.

-- ---------- local helpers ----------
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

create or replace function pg_temp.advance(p_seconds numeric) returns numeric
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
  return v;
end $$;

create or replace function pg_temp.logout() returns void
language sql as $$
  select set_config('request.jwt.claims', '{}', true);
  select set_config('request.jwt.claim.sub', '', true);
$$;

create temp table t_users (name text primary key, id uuid not null) on commit drop;

create or replace function pg_temp.uid(p_name text) returns uuid
language sql as $$ select id from t_users where name = p_name $$;

create or replace function pg_temp.as_user(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.uid(p_name);
begin
  perform pg_temp.login(v);
  return v;
end $$;

create or replace function pg_temp.approx(a numeric, b numeric) returns boolean
language sql as $$ select abs(a - b) < 0.01 $$;

-- ---------- 0. seed sanity ----------
do $$
begin
  perform pg_temp.assert((select count(*) from locations) = 37, 'expected 37 locations, got ' || (select count(*) from locations));
  perform pg_temp.assert((select night_risk_mult from locations where id = 'upper_sakponba') = 3.0, 'upper_sakponba night x3');
  perform pg_temp.assert((select night_risk_mult from locations where id = 'third_east') = 3.0, 'third_east night x3');
  perform pg_temp.assert((select count(*) from locations where coalesce(blurb, '') = '') = 0, 'every location has blurb');
  perform pg_temp.assert((select count(*) from activities) >= 18, 'at least 18 activities');
  perform pg_temp.assert((select remote_km from locations where id = 'iguobazuwa_farm') = 22, 'farm remote_km');
  perform pg_temp.assert((select count(*) from game_config where key like 'crime.%' or key like 'travel.%'
                          or key like 'clock.%' or key like 'needs.%' or key like 'start.%' or key like 'traffic.%'
                          or key like 'time.%') >= 60, 'core config rows seeded');
  perform pg_temp.assert(not exists (select 1 from game_config where label = '' or category = ''), 'config label/category filled');
  -- every activity scene is a real scene
  perform pg_temp.assert(not exists (
    select 1 from activities a, unnest(a.scenes) s where s not in (select scene from locations)), 'activity scenes exist on map');
  perform pg_temp.assert(bl_cfg('start.cash') = 5000, 'bl_cfg numeric');
  perform pg_temp.assert(bl_cfg_bool('traffic.ramat_flyover_open') = false, 'bl_cfg_bool');
  perform pg_temp.assert(bl_cfg_text('start.home_location') = 'ekenwan_room', 'bl_cfg_text');
  perform pg_temp.expect_error($q$ select bl_cfg('nope.not_a_key') $q$, '%no dey%');
  raise notice 'ok 0: seeds + config helpers';
end $$;

-- ---------- 1. not logged in ----------
do $$
begin
  perform pg_temp.logout();
  perform pg_temp.expect_error($q$ select get_my_state() $q$, '%login%');
  perform pg_temp.expect_error($q$ select create_profile('Nobody', 'male', '{}') $q$, '%login%');
  perform pg_temp.expect_error($q$ select players_here('ekenwan_room') $q$, '%login%');
  perform pg_temp.expect_error($q$ select travel_quote('uniben') $q$, '%login%');
  raise notice 'ok 1: anonymous calls rejected';
end $$;

-- ---------- 2. create_profile ----------
do $$
declare
  s jsonb; p jsonb; k text;
  v_a uuid := pg_temp.new_user('a@test.bl');
begin
  insert into t_users values ('a', v_a), ('b', pg_temp.new_user('b@test.bl')),
                             ('c', pg_temp.new_user('c@test.bl')), ('d', pg_temp.new_user('d@test.bl')),
                             ('e', pg_temp.new_user('e@test.bl'));
  perform pg_temp.as_user('a');
  -- before creating: no profile
  perform pg_temp.expect_error($q$ select get_my_state() $q$, '%never create%');

  s := create_profile('Osas_1', 'male', '{"gender":"male","skin":"s3"}');
  -- GameState shape
  foreach k in array array['profile','clock','location','travel','server_time'] loop
    perform pg_temp.assert(s ? k, 'GameState has ' || k);
  end loop;
  perform pg_temp.assert(jsonb_typeof(s->'travel') = 'null', 'travel null at start');
  p := s->'profile';
  foreach k in array array['id','username','gender','avatar','is_admin','cash','bank','hunger','energy','hygiene',
    'fun','social','health','stress','location_id','home_location_id','housing_id','job_id','job_level','job_xp',
    'street_cred','wanted','busy_until','busy_label','jailed_until','jail_reason','hospitalized_until',
    'protected_until','charm_strength','charm_until','created_at'] loop
    perform pg_temp.assert(p ? k, 'profile has ' || k);
  end loop;
  foreach k in array array['banned','needs_updated_at','travel_to','last_seen'] loop
    perform pg_temp.assert(not (p ? k), 'profile hides ' || k);
  end loop;
  foreach k in array array['game_minutes','day','hour','minute','is_night'] loop
    perform pg_temp.assert(s->'clock' ? k, 'clock has ' || k);
  end loop;
  perform pg_temp.assert(jsonb_typeof(s->'clock'->'is_night') = 'boolean', 'is_night boolean');
  foreach k in array array['id','name','district','scene','blurb','risk','night_risk_mult','cctv','keke_ok',
    'congestion','remote_km','x','y','actions','sort'] loop
    perform pg_temp.assert(s->'location' ? k, 'location has ' || k);
  end loop;
  perform pg_temp.assert(jsonb_typeof(s->'location'->'actions') = 'array', 'actions array');
  perform pg_temp.assert(jsonb_typeof(p->'cash') = 'number', 'cash is number');
  perform pg_temp.assert((p->>'cash')::bigint = 5000, 'start cash 5000');
  perform pg_temp.assert(p->>'location_id' = 'ekenwan_room' and p->>'home_location_id' = 'ekenwan_room', 'start home');
  perform pg_temp.assert(p->>'housing_id' = 'face_me_ekenwan', 'start housing');
  perform pg_temp.assert(p->>'username' = 'Osas_1', 'username kept');
  perform pg_temp.assert((p->>'job_level')::int = 1 and (p->>'job_xp')::int = 0 and jsonb_typeof(p->'job_id') = 'null', 'job defaults');
  perform pg_temp.assert(pg_temp.approx((p->>'hunger')::numeric, 80), 'start hunger 80');
  perform pg_temp.assert((p->>'protected_until')::timestamptz between bl_now() + interval '119 minutes'
                                                                 and bl_now() + interval '121 minutes', 'protection 120 min');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v_a and reason = 'start_bonus' and delta = 5000
                                 and balance_after = 5000), 'start bonus ledger');
  perform pg_temp.assert(exists (select 1 from events where user_id = v_a and kind = 'welcome'), 'welcome event');

  -- one person per account
  perform pg_temp.expect_error($q$ select create_profile('Another1', 'male', '{}') $q$, '%already%');

  -- duplicate username (case-insensitive) + bad usernames + bad gender
  perform pg_temp.as_user('b');
  perform pg_temp.expect_error($q$ select create_profile('osas_1', 'female', '{}') $q$, '%don already carry%');
  perform pg_temp.expect_error($q$ select create_profile('ab', 'female', '{}') $q$, '%3 to 20%');
  perform pg_temp.expect_error($q$ select create_profile('bad name', 'female', '{}') $q$, '%3 to 20%');
  perform pg_temp.expect_error($q$ select create_profile('this_name_is_way_too_long', 'female', '{}') $q$, '%3 to 20%');
  perform pg_temp.expect_error($q$ select create_profile('Efe!', 'female', '{}') $q$, '%3 to 20%');
  perform pg_temp.expect_error($q$ select create_profile('Efe', 'alien', '{}') $q$, '%male or female%');
  perform pg_temp.expect_error($q$ select create_profile('Efe', 'female', '[1,2]') $q$, '%avatar%');
  perform create_profile('Efe', 'female', '{}');
  perform pg_temp.as_user('c'); perform create_profile('Ize', 'male', '{}');
  perform pg_temp.as_user('d'); perform create_profile('Dayo', 'male', '{}');
  perform pg_temp.as_user('e'); perform create_profile('Eki', 'female', '{}');
  raise notice 'ok 2: create_profile + GameState shape';
end $$;

-- ---------- 3. client privileges: no direct writes, no helper access ----------
do $$ begin perform pg_temp.as_user('a'); end $$;
set local role authenticated;
do $$
declare n int; ok boolean;
begin
  select count(*) into n from profiles;
  if n <> 1 then raise exception 'TEST FAILED: authenticated sees % profiles (want only own)', n; end if;
  select count(*) into n from locations;
  if n <> 37 then raise exception 'TEST FAILED: locations not readable'; end if;
  ok := false;
  begin update profiles set cash = 999999; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: client could update profiles'; end if;
  ok := false;
  begin insert into ledger (user_id, account, delta, balance_after, reason) values (auth.uid(), 'cash', 1, 1, 'x');
  exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: client could insert ledger'; end if;
  ok := false;
  begin update game_config set value = '0' where key = 'start.cash'; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: client could update game_config'; end if;
  ok := false;
  begin perform bl_add_money(auth.uid(), 'cash', 1000000, 'hack'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: client could call bl_add_money'; end if;
  -- RPCs are callable
  perform get_my_state();
  raise notice 'ok 3: RLS/grants for authenticated';
end $$;
reset role;
set local role anon;
do $$
declare ok boolean := false;
begin
  begin perform get_my_state(); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: anon could call get_my_state'; end if;
  if (select count(*) from locations) <> 37 then raise exception 'TEST FAILED: anon cannot read locations'; end if;
  raise notice 'ok 3b: anon blocked from RPCs, can read catalog';
end $$;
reset role;

-- ---------- 3c. RLS: own rows only, others' private data invisible ----------
do $$
begin
  insert into items (id, name, category, price) values ('test_item_bl', 'Test Phone', 'gadget', 1);
  insert into inventory (user_id, item_id, qty) values (pg_temp.uid('b'), 'test_item_bl', 1),
                                                        (pg_temp.uid('a'), 'test_item_bl', 2);
  insert into config_audit (admin_id, key, old_value, new_value) values (pg_temp.uid('b'), 'start.cash', '1', '2');
  perform set_config('bltest.b', pg_temp.uid('b')::text, true);
  perform pg_temp.as_user('a');
end $$;
set local role authenticated;
do $$
declare n int; ok boolean; me uuid := auth.uid();
begin
  -- own profile row readable (shell uses profiles.select('id').eq('id', uid))
  select count(*) into n from profiles where id = me;
  if n <> 1 then raise exception 'TEST FAILED: cannot read own profiles row'; end if;
  select count(*) into n from profiles where id <> me;
  if n <> 0 then raise exception 'TEST FAILED: can read % other profiles', n; end if;
  select count(*) into n from ledger where user_id <> me;
  if n <> 0 then raise exception 'TEST FAILED: can read others ledger'; end if;
  select count(*) into n from ledger where user_id = me;
  if n < 1 then raise exception 'TEST FAILED: cannot read own ledger'; end if;
  select count(*) into n from events where user_id <> me;
  if n <> 0 then raise exception 'TEST FAILED: can read others events'; end if;
  select count(*) into n from events where user_id = me;
  if n < 1 then raise exception 'TEST FAILED: cannot read own events'; end if;
  select count(*) into n from inventory;
  if n <> 1 then raise exception 'TEST FAILED: inventory visible rows % (want own 1)', n; end if;
  select count(*) into n from config_audit;
  if n <> 0 then raise exception 'TEST FAILED: non-admin sees config_audit'; end if;
  -- catalogs readable
  if (select count(*) from game_config) < 60 or (select count(*) from activities) < 18 then
    raise exception 'TEST FAILED: catalogs not readable';
  end if;
  -- no direct writes on any core table
  ok := false; begin insert into events (user_id, kind, title) values (me, 'x', 'x'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: client could insert events'; end if;
  ok := false; begin update events set read = true; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: client could update events'; end if;
  ok := false; begin delete from profiles where id = me; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: client could delete profile'; end if;
  ok := false; begin insert into inventory values (me, 'test_item_bl', 99); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: client could insert inventory'; end if;
  ok := false; begin insert into locations (id, name, district, scene, x, y) values ('hack','h','h','street',1,1); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: client could insert locations'; end if;
  ok := false; begin update activities set cost = 0; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: client could update activities'; end if;
  ok := false; begin insert into profiles (id, username, location_id, home_location_id) values (me, 'hax', 'ekenwan_room', 'ekenwan_room'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: client could insert profiles'; end if;
  -- other players' public info only via get_public_profile (no private fields)
  if get_public_profile(current_setting('bltest.b')::uuid) ?| array['cash','bank','hunger','jailed_until','is_admin'] then
    raise exception 'TEST FAILED: public profile leaks private fields';
  end if;
  raise notice 'ok 3c: RLS own-rows-only + no direct writes';
end $$;
reset role;
set local role anon;
do $$
declare ok boolean := false;
begin
  begin perform count(*) from profiles; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: anon could select profiles'; end if;
  ok := false; begin perform count(*) from ledger; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: anon could select ledger'; end if;
  if (select count(*) from game_config) < 60 then raise exception 'TEST FAILED: anon cannot read game_config'; end if;
  raise notice 'ok 3d: anon cannot read player tables';
end $$;
reset role;
do $$
declare r record; v_rpc text;
begin
  -- every bl_ helper is internal
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'bl\_%' loop
    perform pg_temp.assert(not has_function_privilege('authenticated', r.sig, 'execute')
                           and not has_function_privilege('anon', r.sig, 'execute'), 'helper exposed: ' || r.sig::text);
  end loop;
  -- every core RPC: authenticated yes, anon no, security definer + search_path set
  foreach v_rpc in array array['create_profile(text,text,jsonb)','update_avatar(jsonb)','get_my_state()','travel_quote(text)',
                               'travel_start(text,text)','travel_arrive()','do_activity(text)','players_here(text)',
                               'get_public_profile(uuid)'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'rpc granted ' || v_rpc);
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'rpc not anon ' || v_rpc);
    perform pg_temp.assert((select prosecdef and proconfig @> array['search_path=public'] from pg_proc
                            where oid = ('public.' || v_rpc)::regprocedure), 'definer+search_path ' || v_rpc);
  end loop;
  -- RLS on every core table
  perform pg_temp.assert((select bool_and(relrowsecurity) from pg_class where oid in
    ('public.profiles'::regclass, 'public.locations'::regclass, 'public.game_config'::regclass, 'public.config_audit'::regclass,
     'public.ledger'::regclass, 'public.events'::regclass, 'public.items'::regclass, 'public.inventory'::regclass,
     'public.activities'::regclass)), 'RLS enabled everywhere');
  -- realtime publication
  perform pg_temp.assert((select count(*) from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public'
                          and tablename in ('profiles','events','game_config')) = 3, 'realtime publication');
  delete from inventory where item_id = 'test_item_bl';
  raise notice 'ok 3e: function privileges, RLS flags, realtime';
end $$;

-- ---------- 4. needs decay ----------
do $$
declare p jsonb;
begin
  perform pg_temp.as_user('a');
  perform pg_temp.advance(3000);          -- 50 real min = 600 game min = 10 game hours
  p := get_my_state()->'profile';
  perform pg_temp.assert(pg_temp.approx((p->>'hunger')::numeric, 40),  'hunger 80-40, got ' || (p->>'hunger'));
  perform pg_temp.assert(pg_temp.approx((p->>'energy')::numeric, 50),  'energy 80-30');
  perform pg_temp.assert(pg_temp.approx((p->>'hygiene')::numeric, 55), 'hygiene 80-25');
  perform pg_temp.assert(pg_temp.approx((p->>'fun')::numeric, 60),     'fun 80-20');
  perform pg_temp.assert(pg_temp.approx((p->>'social')::numeric, 65),  'social 80-15');
  perform pg_temp.assert(pg_temp.approx((p->>'stress')::numeric, 20),  'stress 10+10');
  perform pg_temp.assert(pg_temp.approx((p->>'health')::numeric, 100), 'health untouched');
  perform pg_temp.assert((select last_seen from profiles where id = pg_temp.uid('a')) = bl_now(), 'last_seen bumped');
  -- 20 more game hours: hunger hits 0 after 10h, then 10h starving -> health -20
  perform pg_temp.advance(6000);
  p := get_my_state()->'profile';
  perform pg_temp.assert(pg_temp.approx((p->>'hunger')::numeric, 0), 'hunger clamped 0');
  perform pg_temp.assert(pg_temp.approx((p->>'energy')::numeric, 0), 'energy clamped 0');
  perform pg_temp.assert(pg_temp.approx((p->>'health')::numeric, 80), 'health 100-2*10, got ' || (p->>'health'));
  -- calling twice at same instant changes nothing
  perform pg_temp.assert(pg_temp.approx((get_my_state()->'profile'->>'health')::numeric, 80), 'idempotent decay');
  -- bl_adjust_needs clamps
  perform bl_adjust_needs(pg_temp.uid('a'), '{"hunger": 500, "stress": -500, "bogus": 3}');
  perform pg_temp.assert((select hunger from profiles where id = pg_temp.uid('a')) = 100, 'adjust clamps 100');
  perform pg_temp.assert((select stress from profiles where id = pg_temp.uid('a')) = 0, 'adjust clamps 0');
  -- get_my_state is read-mostly: no needs write; last_seen only re-saved after the throttle
  perform bl_apply_needs(pg_temp.uid('a'));
  perform pg_temp.advance(10);
  declare v_nu timestamptz; v_ls timestamptz; v_h numeric;
  begin
    select needs_updated_at, last_seen, hunger into v_nu, v_ls, v_h from profiles where id = pg_temp.uid('a');
    p := get_my_state()->'profile';
    perform pg_temp.assert((select needs_updated_at from profiles where id = pg_temp.uid('a')) = v_nu, 'get_my_state did not persist decay');
    perform pg_temp.assert((select last_seen from profiles where id = pg_temp.uid('a')) = v_ls, 'last_seen throttled');
    perform pg_temp.assert((p->>'hunger')::numeric < v_h, 'but returned needs are decayed in memory');
    perform pg_temp.advance(31);
    perform get_my_state();
    perform pg_temp.assert((select last_seen from profiles where id = pg_temp.uid('a')) = bl_now(), 'last_seen bumped after throttle');
    perform pg_temp.assert(pg_temp.approx((get_my_state()->'profile'->>'hunger')::numeric,
                                          (bl_apply_needs(pg_temp.uid('a'))).hunger), 'memory decay == persisted decay');
  end;
  -- everyone else refreshes presence
  perform pg_temp.as_user('b'); perform get_my_state();
  perform pg_temp.as_user('c'); perform get_my_state();
  raise notice 'ok 4: lazy needs decay';
end $$;

-- ---------- 5. travel_quote ----------
do $$
declare q jsonb; o jsonb; k text;
begin
  perform pg_temp.as_user('a');
  -- the clock offset is already past the 120-min starter protection; re-protect A for this section
  update profiles set protected_until = bl_now() + interval '1 hour' where id = pg_temp.uid('a');
  q := travel_quote('national_museum');
  perform pg_temp.assert(q->>'dest' = 'national_museum' and (q->>'km')::numeric > 0, 'quote dest/km');
  perform pg_temp.assert(jsonb_array_length(q->'options') = 5, '5 modes');
  for o in select * from jsonb_array_elements(q->'options') loop
    foreach k in array array['mode','label','allowed','cost','game_minutes','real_seconds','risk_pct'] loop
      perform pg_temp.assert(o ? k, 'option has ' || k);
    end loop;
    perform pg_temp.assert((o->>'risk_pct')::numeric = 0, 'protected player risk 0 (' || (o->>'mode') || ')');
    perform pg_temp.assert((o->>'real_seconds')::numeric >= 3, 'min 3s');
  end loop;
  select x into o from jsonb_array_elements(q->'options') x where x->>'mode' = 'keke';
  perform pg_temp.assert(not (o->>'allowed')::boolean and o->>'reason' ilike '%keke%', 'keke blocked to museum');
  select x into o from jsonb_array_elements(q->'options') x where x->>'mode' = 'car';
  perform pg_temp.assert(not (o->>'allowed')::boolean and o->>'reason' ilike '%motor%', 'car blocked w/o vehicle');
  select x into o from jsonb_array_elements(q->'options') x where x->>'mode' = 'walk';
  perform pg_temp.assert((o->>'allowed')::boolean and (o->>'cost')::int = 0 and not (o ? 'reason'), 'walk free');

  q := travel_quote('mama_osas_buka');
  select x into o from jsonb_array_elements(q->'options') x where x->>'mode' = 'keke';
  perform pg_temp.assert((o->>'allowed')::boolean, 'keke ok between keke_ok places');
  -- km formula: dist((205,620),(455,545))/1000*18
  perform pg_temp.assert(abs((q->>'km')::numeric - sqrt(250^2 + 75^2) / 1000 * 18) < 0.01, 'km formula');
  perform pg_temp.assert((o->>'cost')::bigint = ceil((150 + 100 * (q->>'km')::numeric) / 10) * 10, 'keke fare formula');

  -- farm adds remote_km
  perform pg_temp.assert((travel_quote('iguobazuwa_farm')->>'km')::numeric > 22, 'remote km added');

  -- with a vehicle the car is allowed
  insert into items (id, name, category, price) values ('test_car_bl', 'Test Tokunbo', 'vehicle', 1);
  insert into inventory (user_id, item_id, qty) values (pg_temp.uid('a'), 'test_car_bl', 1);
  select x into o from jsonb_array_elements(travel_quote('national_museum')->'options') x where x->>'mode' = 'car';
  perform pg_temp.assert((o->>'allowed')::boolean, 'car allowed with vehicle');

  perform pg_temp.expect_error($q$ select travel_quote('ekenwan_room') $q$, '%already%');
  perform pg_temp.expect_error($q$ select travel_quote('atlantis') $q$, '%no dey for map%');
  raise notice 'ok 5: travel_quote';
end $$;

-- ---------- 6. travel_start / travel_arrive ----------
do $$
declare q jsonb; o jsonb; r jsonb; s jsonb; v_cash bigint; v_secs numeric;
begin
  perform pg_temp.as_user('a');
  v_cash := (select cash from profiles where id = pg_temp.uid('a'));
  q := travel_quote('mama_osas_buka');
  select x into o from jsonb_array_elements(q->'options') x where x->>'mode' = 'keke';
  perform pg_temp.expect_error($q$ select travel_start('mama_osas_buka', 'helicopter') $q$, '%transport%');
  perform pg_temp.expect_error($q$ select travel_start('national_museum', 'keke') $q$, '%keke%');
  r := travel_start('mama_osas_buka', 'keke');
  perform pg_temp.assert(r ? 'message' and r ? 'arrives_at', 'travel_start result');
  perform pg_temp.assert((select cash from profiles where id = pg_temp.uid('a')) = v_cash - (o->>'cost')::bigint, 'fare charged');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = pg_temp.uid('a') and reason = 'travel'
                                 and delta = -(o->>'cost')::bigint), 'travel ledger row');
  s := get_my_state();
  perform pg_temp.assert(s->'travel'->>'to' = 'mama_osas_buka' and s->'travel'->>'mode' = 'keke', 'state shows travel');
  perform pg_temp.assert(s->'profile'->>'location_id' = 'ekenwan_room', 'still at origin while on road');
  -- cannot do things while on the road
  perform pg_temp.expect_error($q$ select travel_start('uniben', 'walk') $q$, '%road%');
  perform pg_temp.expect_error($q$ select do_activity('bathe') $q$, '%road%');
  -- too early
  perform pg_temp.expect_error($q$ select travel_arrive() $q$, '%never reach%');
  -- time passes: travel finished but still reported until arrive
  v_secs := (o->>'real_seconds')::numeric;
  perform pg_temp.advance(v_secs + 1);
  s := get_my_state();
  perform pg_temp.assert(s->'travel' is not null and jsonb_typeof(s->'travel') = 'object', 'travel reported until arrive');
  perform set_config('bl.test_rand', '0.99', true);
  r := travel_arrive();
  perform pg_temp.assert(r ? 'message' and not (r ? 'robbed'), 'arrived, not robbed');
  s := get_my_state();
  perform pg_temp.assert(s->'profile'->>'location_id' = 'mama_osas_buka' and jsonb_typeof(s->'travel') = 'null', 'moved + travel cleared');
  perform pg_temp.assert(s->'location'->>'id' = 'mama_osas_buka', 'state location updated');
  perform pg_temp.expect_error($q$ select travel_arrive() $q$, '%no dey travel%');
  raise notice 'ok 6: travel_start / travel_arrive';
end $$;

-- ---------- 7. do_activity + bl_assert_free ----------
do $$
declare r jsonb; v_cash bigint; v_h numeric; me profiles;
begin
  perform pg_temp.as_user('a');           -- at mama_osas_buka (buka)
  perform pg_temp.expect_error($q$ select do_activity('museum_tour') $q$, '%no fit do%');
  perform pg_temp.expect_error($q$ select do_activity('sleep') $q$, '%no fit do%');
  perform pg_temp.expect_error($q$ select do_activity('fly_to_moon') $q$, '%no dey%');
  perform bl_apply_needs(pg_temp.uid('a'));
  update profiles set hunger = 20 where id = pg_temp.uid('a');
  select cash, hunger into v_cash, v_h from profiles where id = pg_temp.uid('a');
  r := do_activity('owo_soup');
  perform pg_temp.assert(r ? 'message', 'activity message');
  perform pg_temp.assert((select cash from profiles where id = pg_temp.uid('a')) = v_cash - 1500, 'owo soup cost 1500');
  perform pg_temp.assert(pg_temp.approx((select hunger from profiles where id = pg_temp.uid('a')), v_h + 55), 'hunger +55');
  select * into me from profiles where id = pg_temp.uid('a');
  perform pg_temp.assert(me.busy_until = bl_now() + make_interval(secs => 30 * 5), 'busy 30 game min = 150 s');
  perform pg_temp.assert(me.busy_label = (select name from activities where id = 'owo_soup'), 'busy label');
  -- busy blocks everything
  perform pg_temp.expect_error($q$ select do_activity('pepper_soup') $q$, '%busy%');
  perform pg_temp.expect_error($q$ select travel_start('uniben', 'walk') $q$, '%busy%');
  perform pg_temp.expect_error(format('select bl_assert_free(p) from profiles p where id = %L', me.id), '%busy%');
  -- after it finishes, free again
  perform pg_temp.advance(151);
  perform bl_assert_free(bl_me());

  -- home_only / money checks with Efe (b)
  perform pg_temp.as_user('b');
  update profiles set location_id = 'aduwawa_room' where id = pg_temp.uid('b');
  perform pg_temp.expect_error($q$ select do_activity('bathe') $q$, '%own house%');
  update profiles set location_id = 'ekenwan_room', cash = 100 where id = pg_temp.uid('b');
  perform pg_temp.expect_error($q$ select do_activity('cook_home') $q$, '%money no reach%');
  perform pg_temp.assert((select cash from profiles where id = pg_temp.uid('b')) = 100, 'failed activity no charge');
  perform pg_temp.assert((select busy_until from profiles where id = pg_temp.uid('b')) is null, 'failed activity not busy');
  perform bl_apply_needs(pg_temp.uid('b'));   -- settle decay first (get_my_state never writes needs)
  update profiles set hygiene = 10 where id = pg_temp.uid('b');
  perform do_activity('bathe');
  perform pg_temp.assert(pg_temp.approx((select hygiene from profiles where id = pg_temp.uid('b')), 70), 'bathe hygiene +60');

  -- night_only
  if not (bl_game_clock()->>'is_night')::boolean then
    perform pg_temp.as_user('a');
    update profiles set location_id = 'bronze_lounge' where id = pg_temp.uid('a');
    perform pg_temp.expect_error($q$ select do_activity('club_night') $q$, '%night%');
    update profiles set location_id = 'mama_osas_buka' where id = pg_temp.uid('a');
  end if;
  raise notice 'ok 7: do_activity + bl_assert_free';
end $$;

-- ---------- 8. players_here + get_public_profile ----------
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('c'); perform get_my_state();   -- Ize at ekenwan_room, fresh
  perform pg_temp.as_user('b'); perform get_my_state();   -- Efe at ekenwan_room
  r := players_here('ekenwan_room');
  perform pg_temp.assert(jsonb_typeof(r) = 'array', 'players_here array');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(r) x where x->>'username' = 'Ize'), 'sees Ize');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r) x where x->>'username' = 'Efe'), 'excludes self');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r) x where x->>'username' = 'Osas_1'), 'excludes other places');
  perform pg_temp.assert((select bool_and(x ? 'id' and x ? 'avatar' and x ? 'street_cred' and x ? 'last_seen')
                          from jsonb_array_elements(r) x), 'player shape');
  -- 4 real minutes later Ize is stale
  perform pg_temp.advance(240);
  r := players_here('ekenwan_room');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r) x where x->>'username' = 'Ize'), 'stale player hidden');
  perform pg_temp.assert(players_here('nowhere') = '[]'::jsonb, 'empty list');

  r := get_public_profile(pg_temp.uid('c'));
  perform pg_temp.assert(r->>'username' = 'Ize' and r ? 'avatar' and r ? 'location_id' and not (r ? 'cash'), 'public profile');
  perform pg_temp.expect_error(format('select get_public_profile(%L)', gen_random_uuid()), '%no dey%');
  raise notice 'ok 8: players_here + get_public_profile';
end $$;

-- ---------- 9. forced street robbery at night ----------
do $$
declare
  i int; q jsonb; o jsonb; r jsonb; s jsonb;
  v_amt bigint; v_health numeric;
  v_d uuid := pg_temp.uid('d');
  v_night timestamptz; v_day timestamptz;
begin
  -- move the clock until it is 22:xx game time
  for i in 1..30 loop
    exit when (bl_game_clock()->>'hour')::int = 22;
    perform pg_temp.advance(300);          -- 300 real s = 1 game hour
  end loop;
  perform pg_temp.assert((bl_game_clock()->>'is_night')::boolean, 'it is night now');

  -- night risk at upper_sakponba is 3x day risk (walk ignores traffic)
  update profiles set protected_until = null, cash = 50000, location_id = 'ekenwan_room' where id = v_d;
  v_night := bl_now();
  v_day := bl_now() + make_interval(secs => 300 * 12);   -- +12 game hours = 10:xx
  perform pg_temp.assert(abs(bl_street_robbery_chance(v_d, 'upper_sakponba', 'walk', 1, v_night)
                             - 3 * bl_street_robbery_chance(v_d, 'upper_sakponba', 'walk', 1, v_day)) < 0.0001,
                         'night x3 at upper_sakponba');
  perform pg_temp.assert(bl_street_robbery_chance(v_d, 'upper_sakponba', 'walk', 1, v_night)
                         > bl_street_robbery_chance(v_d, 'upper_sakponba', 'car', 1, v_night), 'walking riskier than car');

  perform pg_temp.as_user('d');
  q := travel_quote('upper_sakponba');
  select x into o from jsonb_array_elements(q->'options') x where x->>'mode' = 'walk';
  perform pg_temp.assert((o->>'risk_pct')::numeric > 5, 'quote warns of night risk, got ' || (o->>'risk_pct'));

  perform travel_start('upper_sakponba', 'walk');
  perform pg_temp.advance((o->>'real_seconds')::numeric + 1);
  perform pg_temp.assert((bl_game_clock()->>'is_night')::boolean, 'still night on arrival');
  v_health := (select health from profiles where id = v_d);
  perform set_config('bl.test_rand', '0.0001', true);
  r := travel_arrive();
  perform set_config('bl.test_rand', '0.99', true);
  perform pg_temp.assert(r ? 'robbed', 'robbed! ' || r::text);
  v_amt := (r->'robbed'->>'amount')::bigint;
  perform pg_temp.assert(v_amt between 10000 and 30000, 'loss 20–60% of 50000, got ' || v_amt);
  perform pg_temp.assert((select cash from profiles where id = v_d) = 50000 - v_amt, 'cash dropped');
  perform pg_temp.assert(exists (select 1 from events where user_id = v_d and kind = 'robbed'
                                 and (data->>'amount')::bigint = v_amt and data->>'location' = 'upper_sakponba'), 'robbed event');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v_d and reason = 'street_robbery' and delta = -v_amt), 'robbery ledger');
  perform pg_temp.assert((r->'robbed'->>'injured')::boolean, 'rand 0.0001 -> injured');
  perform pg_temp.assert((select health from profiles where id = v_d) < v_health, 'health dropped');
  perform pg_temp.assert(r->>'message' ilike '%Omo%', 'pidgin robbery message');
  perform pg_temp.assert((select location_id from profiles where id = v_d) = 'upper_sakponba', 'arrived anyway');
  raise notice 'ok 9: forced night robbery (lost %)', v_amt;
end $$;

-- ---------- 10. protection + charm prevent robbery ----------
do $$
declare q jsonb; o jsonb; r jsonb; v_e uuid := pg_temp.uid('e');
begin
  update profiles set cash = 50000, protected_until = bl_now() + interval '1 hour' where id = v_e;
  perform pg_temp.as_user('e');
  q := travel_quote('upper_sakponba');
  select x into o from jsonb_array_elements(q->'options') x where x->>'mode' = 'walk';
  perform pg_temp.assert((o->>'risk_pct')::numeric = 0, 'protected -> risk 0');
  perform travel_start('upper_sakponba', 'walk');
  perform pg_temp.advance((o->>'real_seconds')::numeric + 1);
  perform set_config('bl.test_rand', '0.0001', true);
  r := travel_arrive();
  perform set_config('bl.test_rand', '0.99', true);
  perform pg_temp.assert(not (r ? 'robbed'), 'protected player not robbed');
  perform pg_temp.assert((select cash from profiles where id = v_e) = 50000, 'cash intact');
  perform pg_temp.assert(not exists (select 1 from events where user_id = v_e and kind = 'robbed'), 'no robbed event');
  -- full-strength charm also gives 0
  update profiles set protected_until = null, charm_strength = 1, charm_until = bl_now() + interval '1 hour' where id = v_e;
  perform pg_temp.assert(bl_street_robbery_chance(v_e, 'third_east', 'walk', 1) = 0, 'charm 1.0 -> 0');
  update profiles set charm_strength = 0.5 where id = v_e;
  perform pg_temp.assert(bl_street_robbery_chance(v_e, 'third_east', 'walk', 1) > 0, 'half charm still some risk');
  -- no cash, nothing to rob
  update profiles set cash = 0 where id = v_e;
  perform pg_temp.assert(bl_street_robbery_chance(v_e, 'third_east', 'walk', 1) = 0, 'broke -> 0');
  raise notice 'ok 10: protection / charm';
end $$;

-- ---------- 11. status helpers, money, avatar, ban ----------
do $$
declare v_b uuid := pg_temp.uid('b'); v_c uuid := pg_temp.uid('c'); s jsonb;
begin
  perform pg_temp.advance(3000);   -- clear any busy timers
  -- jail
  perform bl_jail(v_b, 60, 'test case');
  perform pg_temp.assert((select location_id from profiles where id = v_b) = 'police_hq', 'jailed -> police_hq');
  perform pg_temp.assert((select jailed_until from profiles where id = v_b) = bl_now() + interval '300 seconds', 'jail 60 game min = 300 s');
  perform pg_temp.as_user('b');
  s := get_my_state();                                   -- still works while jailed
  perform pg_temp.assert(s->'profile'->>'jail_reason' = 'test case', 'jail reason in state');
  perform pg_temp.expect_error($q$ select do_activity('gist_joint') $q$, '%cell%');
  perform pg_temp.expect_error($q$ select travel_start('uniben', 'walk') $q$, '%cell%');
  -- hospital
  perform bl_hospitalize(v_c, 30, 'robbed');
  perform pg_temp.assert((select location_id from profiles where id = v_c) = 'ubth', 'hospitalised -> ubth');
  perform pg_temp.as_user('c');
  perform pg_temp.expect_error($q$ select travel_start('uniben', 'walk') $q$, '%hospital%');
  -- money helper
  perform pg_temp.expect_error(format('select bl_add_money(%L, %L, -999999999, %L)', v_c, 'cash', 'x'), '%money no reach%');
  perform pg_temp.expect_error(format('select bl_add_money(%L, %L, 1, %L)', v_c, 'wallet', 'x'), '%account%');
  perform pg_temp.assert(bl_add_money(v_c, 'bank', 700, 'test') = 700, 'bank credit');
  -- avatar
  perform pg_temp.as_user('a');
  perform pg_temp.assert(update_avatar('{"gender":"female","outfit":"ankara"}') ? 'message', 'update_avatar msg');
  perform pg_temp.assert((select gender from profiles where id = pg_temp.uid('a')) = 'female', 'gender synced');
  perform pg_temp.expect_error($q$ select update_avatar('"nope"') $q$, '%avatar%');
  -- clock helper sanity
  perform pg_temp.assert((bl_game_clock(timestamptz '2026-01-01 00:00:00+00')->>'hour')::int = 6, 'epoch = 06:00 day 1');
  perform pg_temp.assert((bl_game_clock(timestamptz '2026-01-01 00:00:00+00')->>'day')::int = 1, 'day 1');
  perform pg_temp.assert((bl_game_clock(timestamptz '2026-01-01 01:10:00+00')->>'hour')::int = 20
                         and (bl_game_clock(timestamptz '2026-01-01 01:10:00+00')->>'is_night')::boolean, '70 real min -> 20:00 night');
  -- ban
  update profiles set banned = true where id = pg_temp.uid('c');
  perform pg_temp.as_user('c');
  perform pg_temp.expect_error($q$ select get_my_state() $q$, '%ban%');
  raise notice 'ok 11: jail / hospital / money / avatar / clock / ban';
end $$;

-- ---------- 12. formulas: robbery chance, traffic, travel time/fare, clock ----------
do $$
declare
  v_d uuid := pg_temp.uid('d');
  t_night timestamptz; t_noon timestamptz; t_rush timestamptz;
  v_exp numeric; v_got numeric; q jsonb; o jsonb; v_km numeric; v_tr numeric;
  base numeric := 0.06;
  g timestamptz := timestamptz '2026-01-01 00:00:00+00';
begin
  -- fixed instants (real -> game): +0 = 06:00, +80 min = 22:00 (night), +30 min = 12:00, +10 min = 08:00 (rush)
  t_night := g + interval '80 minutes'; t_noon := g + interval '30 minutes'; t_rush := g + interval '10 minutes';
  perform pg_temp.assert((bl_game_clock(t_night)->>'hour')::int = 22 and (bl_game_clock(t_night)->>'is_night')::boolean, 'clock 22 night');
  perform pg_temp.assert((bl_game_clock(t_noon)->>'hour')::int = 12 and not (bl_game_clock(t_noon)->>'is_night')::boolean, 'clock 12 day');
  perform pg_temp.assert((bl_game_clock(g + interval '90 minutes')->>'day')::int = 2
                         and (bl_game_clock(g + interval '90 minutes')->>'hour')::int = 0, 'midnight rolls to day 2');
  perform pg_temp.assert((bl_game_clock(g + interval '115 minutes')->>'is_night')::boolean, '05:00 is night');
  perform pg_temp.assert(not (bl_game_clock(g + interval '120 minutes')->>'is_night')::boolean, '06:00 is day');
  perform pg_temp.assert((bl_game_clock(g + interval '1 minute 5 seconds')->>'minute')::int = 13, 'minute field (12 game min/real min)');

  -- robbery p = base/100 * risk * (night ? night_mult*crime.night_mult : 1) * (1+(traffic-1)*w) * cash_factor * mode * (1-charm)
  update profiles set protected_until = null, charm_strength = 0, charm_until = null, cash = 50000 where id = v_d;
  -- night, upper_sakponba (.55, x3), traffic 1.4, cash factor min(1.5, 0.3+50000/20000)=1.5, walk 1.4
  v_exp := base * 0.55 * 3.0 * (1 + 0.4 * 0.5) * 1.5 * 1.4;
  v_got := bl_street_robbery_chance(v_d, 'upper_sakponba', 'walk', 1.4, t_night);
  perform pg_temp.assert(abs(v_got - v_exp) < 1e-9, format('night formula: want %s got %s', v_exp, v_got));
  -- day, third_east (.50), traffic 1, cash 2000 -> 0.3+0.1=0.4, bus 0.8
  update profiles set cash = 2000 where id = v_d;
  v_exp := base * 0.50 * 1 * 1 * 0.4 * 0.8;
  v_got := bl_street_robbery_chance(v_d, 'third_east', 'bus', 1, t_noon);
  perform pg_temp.assert(abs(v_got - v_exp) < 1e-9, format('day formula: want %s got %s', v_exp, v_got));
  -- mode ordering walk > keke > bus > drop > car
  perform pg_temp.assert(bl_street_robbery_chance(v_d, 'third_east', 'walk', 1, t_noon) > bl_street_robbery_chance(v_d, 'third_east', 'keke', 1, t_noon)
                     and bl_street_robbery_chance(v_d, 'third_east', 'keke', 1, t_noon) > bl_street_robbery_chance(v_d, 'third_east', 'bus', 1, t_noon)
                     and bl_street_robbery_chance(v_d, 'third_east', 'bus', 1, t_noon) > bl_street_robbery_chance(v_d, 'third_east', 'drop', 1, t_noon)
                     and bl_street_robbery_chance(v_d, 'third_east', 'drop', 1, t_noon) > bl_street_robbery_chance(v_d, 'third_east', 'car', 1, t_noon),
                     'mode ordering');
  -- half charm halves it
  update profiles set charm_strength = 0.5, charm_until = t_noon + interval '1 hour' where id = v_d;
  perform pg_temp.assert(abs(bl_street_robbery_chance(v_d, 'third_east', 'bus', 1, t_noon) - v_exp * 0.5) < 1e-9, 'charm 0.5 halves risk');
  -- expired charm ignored
  update profiles set charm_until = t_noon - interval '1 second' where id = v_d;
  perform pg_temp.assert(abs(bl_street_robbery_chance(v_d, 'third_east', 'bus', 1, t_noon) - v_exp) < 1e-9, 'expired charm ignored');
  -- cap at crime.npc_max_pct (35%)
  update profiles set cash = 10000000, charm_strength = 0 where id = v_d;
  perform pg_temp.assert(bl_street_robbery_chance(v_d, 'upper_sakponba', 'walk', 3, t_night) = 0.35, 'capped at 35%');
  -- admin tunes base -> instant effect
  update game_config set value = '12' where key = 'crime.npc_base_pct';
  update profiles set cash = 2000 where id = v_d;
  perform pg_temp.assert(abs(bl_street_robbery_chance(v_d, 'third_east', 'bus', 1, t_noon) - v_exp * 2) < 1e-9, 'config change applies');
  update game_config set value = '6' where key = 'crime.npc_base_pct';

  -- traffic: avg(congestion) x rush 1.8 (07-10,16-20) x ramat 1.6 (ikpoba_hill/aduwawa while flyover closed)
  perform pg_temp.assert(bl_traffic('ekenwan_room', 'uniben', t_noon) = 1.1, 'traffic avg');
  perform pg_temp.assert(bl_traffic('ekenwan_room', 'uniben', t_rush) = round(1.1 * 1.8, 3), 'rush hour');
  perform pg_temp.assert(bl_traffic('ekenwan_room', 'ramat_park', t_noon) = round(1.6 * 1.6, 3), 'ramat jam');
  perform pg_temp.assert(bl_traffic('aduwawa_room', 'third_east', t_noon) = round(1.15 * 1.6, 3), 'aduwawa counts for ramat');
  update game_config set value = 'true' where key = 'traffic.ramat_flyover_open';
  perform pg_temp.assert(bl_traffic('ekenwan_room', 'ramat_park', t_noon) = 1.6, 'flyover open removes jam');
  update game_config set value = 'false' where key = 'traffic.ramat_flyover_open';

  -- quote: bus time uses traffic, walk ignores it; risk_pct = chance at arrival time
  perform pg_temp.as_user('d');
  update profiles set location_id = 'ekenwan_room', cash = 50000, busy_until = null where id = v_d;
  q := travel_quote('ramat_park');
  v_km := (q->>'km')::numeric;
  v_tr := (q->>'traffic')::numeric;
  perform pg_temp.assert(v_tr = bl_traffic('ekenwan_room', 'ramat_park', bl_now()), 'quote traffic');
  select x into o from jsonb_array_elements(q->'options') x where x->>'mode' = 'bus';
  perform pg_temp.assert((o->>'game_minutes')::int = ceil(v_km / 15 * 60 * v_tr), 'bus minutes with traffic');
  perform pg_temp.assert((o->>'cost')::int = 300, 'bus flat fare');
  perform pg_temp.assert((o->>'real_seconds')::numeric = greatest(3, (o->>'game_minutes')::int * 1.0), 'real seconds = game min x 1.0');
  perform pg_temp.assert((o->>'risk_pct')::numeric = round(100 * bl_street_robbery_chance(v_d, 'ramat_park', 'bus', v_tr,
                           bl_now() + make_interval(secs => (o->>'real_seconds')::double precision)), 1), 'risk_pct matches formula');
  select x into o from jsonb_array_elements(q->'options') x where x->>'mode' = 'walk';
  perform pg_temp.assert((o->>'game_minutes')::int = ceil(v_km / 5 * 60), 'walk ignores traffic');
  select x into o from jsonb_array_elements(q->'options') x where x->>'mode' = 'drop';
  perform pg_temp.assert((o->>'cost')::int = ceil((500 + 250 * v_km) / 10) * 10, 'drop fare');

  -- not enough cash: option disallowed with reason, travel_start refuses and charges nothing
  update profiles set cash = 100 where id = v_d;
  select x into o from jsonb_array_elements(travel_quote('ramat_park')->'options') x where x->>'mode' = 'drop';
  perform pg_temp.assert(not (o->>'allowed')::boolean and o->>'reason' ilike '%money no reach%', 'drop unaffordable');
  perform pg_temp.expect_error($q$ select travel_start('ramat_park', 'drop') $q$, '%money no reach%');
  perform pg_temp.assert((select cash from profiles where id = v_d) = 100 and (select travel_to from profiles where id = v_d) is null, 'nothing charged');
  -- walking is free even when broke
  update profiles set cash = 0 where id = v_d;
  perform travel_start('ramat_park', 'walk');
  perform pg_temp.assert((get_my_state()->'travel'->>'mode') = 'walk', 'broke player can walk');

  -- get_my_state clock = bl_game_clock(now); server_time = bl_now()
  perform pg_temp.assert(get_my_state()->'clock' = bl_game_clock(bl_now()), 'state clock');
  perform pg_temp.assert((get_my_state()->>'server_time')::timestamptz = bl_now(), 'server_time = bl_now');
  raise notice 'ok 12: robbery formula, traffic, travel time/fare, clock';
end $$;

do $$ begin raise notice 'ALL CORE TESTS PASSED'; end $$;
