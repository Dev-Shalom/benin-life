-- Origin tests (P1-ORIGIN): LAPO baby vs Nepo baby. Run:
--   bash scripts/sql-test.sh supabase/migrations/20261004000100_core.sql supabase/migrations/20261004000200_core_seed.sql \
--     supabase/migrations/20261005000100_map_geo.sql supabase/migrations/20261005000200_origin.sql -- supabase/tests/origin_test.sql
-- Rolled back at the end. Rolls are forced with bl.test_rand, time with bl.test_offset_seconds.

-- R3a: origin.force_next (20261005000400_creator.sql) would override the forced rolls below; clear it.
-- A no-op when that migration is not loaded.
update game_config set value = '""'::jsonb where key = 'origin.force_next';

-- ---------- local helpers (standalone; safe if core_test already defined them) ----------
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

create temp table t_ou (name text primary key, id uuid not null) on commit drop;

create or replace function pg_temp.ou(p_name text) returns uuid
language sql as $$ select id from t_ou where name = p_name $$;

-- new auth user, logged in, profile created under a forced roll; returns the GameState
create or replace function pg_temp.make_player(p_name text, p_rand text) returns jsonb
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@origin.bl'); s jsonb;
begin
  insert into t_ou values (p_name, v);
  perform pg_temp.login(v);
  perform set_config('bl.test_rand', p_rand, true);
  s := create_profile(p_name, 'female', '{"gender":"female"}');
  perform set_config('bl.test_rand', '', true);
  return s;
end $$;

-- ---------- 0. seeds, RLS, grants ----------
do $$
declare k text; r record;
begin
  perform pg_temp.assert((select count(*) from origin_tiers where is_default) = 1, 'exactly one default tier');
  perform pg_temp.assert((select id from origin_tiers where is_default) = 'lapo', 'lapo is default');
  perform pg_temp.assert((select chance_key from origin_tiers where id = 'nepo') = 'origin.nepo_pct', 'nepo chance key');
  perform pg_temp.assert((select perks->>'micro_loan_access' from origin_tiers where id = 'lapo') = 'easy', 'lapo loan hook');
  perform pg_temp.assert(bl_cfg('origin.nepo_pct') = 10, 'nepo pct default 10');
  foreach k in array array['start_cash','start_bank','home_location','housing','items','career_head_start','allowance_daily'] loop
    perform pg_temp.assert(exists (select 1 from game_config where key = 'origin.lapo.' || k and category = 'origin' and label <> ''), 'lapo cfg ' || k);
    perform pg_temp.assert(exists (select 1 from game_config where key = 'origin.nepo.' || k and category = 'origin' and label <> ''), 'nepo cfg ' || k);
  end loop;
  -- every configured tier home is a real location and every tier item exists
  for r in select id from origin_tiers loop
    perform bl_location(bl_origin_cfg(r.id, 'home_location'));
    perform pg_temp.assert(not exists (select 1 from unnest(bl_origin_items(r.id)) i where i not in (select id from items)),
                           'items exist for ' || r.id);
  end loop;
  perform pg_temp.assert((select category from items where id = 'tokunbo_car') = 'vehicle', 'car is a vehicle');
  perform pg_temp.assert((select category from items where id = 'laptop') = 'gadget', 'laptop is a gadget');
  perform pg_temp.assert(bl_origin_items('nepo') = array['tokunbo_car','laptop'], 'nepo items parsed');
  perform pg_temp.assert(bl_origin_items('lapo') = '{}'::text[], 'lapo has no items');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.origin_tiers'::regclass), 'RLS on origin_tiers');
  -- helpers internal, RPC for players only
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'bl\_origin%' or p.proname = 'bl_roll_origin') loop
    perform pg_temp.assert(not has_function_privilege('authenticated', r.sig, 'execute')
                           and not has_function_privilege('anon', r.sig, 'execute'), 'helper exposed: ' || r.sig::text);
  end loop;
  foreach k in array array['claim_allowance()','create_profile(text,text,jsonb)','get_my_state()'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || k)::regprocedure, 'execute'), 'granted ' || k);
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || k)::regprocedure, 'execute'), 'not anon ' || k);
    perform pg_temp.assert((select prosecdef and proconfig @> array['search_path=public'] from pg_proc
                            where oid = ('public.' || k)::regprocedure), 'definer+search_path ' || k);
  end loop;
  raise notice 'ok 0: origin seeds, config, items, privileges';
end $$;

set local role anon;
do $$
declare ok boolean := false;
begin
  if (select count(*) from origin_tiers) < 2 then raise exception 'TEST FAILED: anon cannot read origin_tiers'; end if;
  begin insert into origin_tiers (id, name, chance_key) values ('hax', 'Hax', 'x'); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: anon could insert origin_tiers'; end if;
  raise notice 'ok 0b: anon reads tiers, cannot write';
end $$;
reset role;
set local role authenticated;
do $$
declare ok boolean := false;
begin
  if (select count(*) from origin_tiers) < 2 then raise exception 'TEST FAILED: authenticated cannot read origin_tiers'; end if;
  begin update origin_tiers set tagline = 'x'; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'TEST FAILED: authenticated could update origin_tiers'; end if;
  raise notice 'ok 0c: authenticated reads tiers, cannot write';
end $$;
reset role;

-- ---------- 1. forced Nepo roll ----------
do $$
declare s jsonb; p jsonb; o jsonb; v uuid; ev text;
begin
  s := pg_temp.make_player('Nepo_Osaro', '0.01');
  v := pg_temp.ou('Nepo_Osaro');
  p := s->'profile';
  perform pg_temp.assert(p->>'origin' = 'nepo', 'origin nepo, got ' || coalesce(p->>'origin', 'null'));
  perform pg_temp.assert(p ? 'allowance_claimed_day' and jsonb_typeof(p->'allowance_claimed_day') = 'null', 'allowance_claimed_day exposed, null');
  perform pg_temp.assert((p->>'cash')::bigint = 50000, 'nepo cash 50000, got ' || (p->>'cash'));
  perform pg_temp.assert((p->>'bank')::bigint = 500000, 'nepo bank 500000');
  perform pg_temp.assert(p->>'home_location_id' = 'gra_duplex' and p->>'location_id' = 'gra_duplex', 'nepo home GRA duplex');
  perform pg_temp.assert(p->>'housing_id' = 'duplex_gra', 'nepo housing');
  perform pg_temp.assert(s->'location'->>'scene' = 'home_duplex', 'state location is the duplex');
  perform pg_temp.assert((select qty from inventory where user_id = v and item_id = 'tokunbo_car') = 1, 'nepo has car');
  perform pg_temp.assert((select qty from inventory where user_id = v and item_id = 'laptop') = 1, 'nepo has laptop');
  perform pg_temp.assert((select count(*) from ledger where user_id = v and reason = 'start_bonus') = 2, 'two start_bonus rows');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'start_bonus' and account = 'bank'
                                 and delta = 500000 and meta->>'origin' = 'nepo'), 'bank start_bonus ledger');
  select body into ev from events where user_id = v and kind = 'welcome';
  perform pg_temp.assert(ev ilike '%GRA Duplex%' and ev not ilike '%Ekenwan%' and ev ilike '%₦50,000%', 'nepo welcome text: ' || coalesce(ev, 'null'));
  perform pg_temp.assert((select data->>'origin' from events where user_id = v and kind = 'welcome') = 'nepo', 'welcome event data');
  o := s->'origin';
  perform pg_temp.assert(o->>'id' = 'nepo' and o->>'name' = 'Nepo baby' and coalesce(o->>'tagline', '') <> '', 'origin block');
  perform pg_temp.assert((o->>'allowance_daily')::bigint = 5000 and (o->>'allowance_claimable')::boolean, 'nepo allowance claimable');
  perform pg_temp.assert((o->>'career_head_start')::int = 2, 'nepo head start 2');
  perform pg_temp.assert((o->>'start_cash')::bigint = 50000 and (o->>'start_bank')::bigint = 500000, 'origin start money');
  perform pg_temp.assert(jsonb_array_length(o->'items') = 2 and o->'items'->0->>'id' = 'tokunbo_car'
                         and o->'items'->1->>'name' = 'Fairly-used Laptop', 'origin items with names');
  raise notice 'ok 1: forced Nepo roll';
end $$;

-- ---------- 2. forced LAPO roll ----------
do $$
declare s jsonb; p jsonb; v uuid; ev text;
begin
  s := pg_temp.make_player('Lapo_Efosa', '0.5');
  v := pg_temp.ou('Lapo_Efosa');
  p := s->'profile';
  perform pg_temp.assert(p->>'origin' = 'lapo', 'origin lapo');
  perform pg_temp.assert((p->>'cash')::bigint = 5000 and (p->>'bank')::bigint = 0, 'lapo money');
  perform pg_temp.assert(p->>'home_location_id' = 'ekenwan_room' and p->>'location_id' = 'ekenwan_room', 'lapo home');
  perform pg_temp.assert(p->>'housing_id' = 'face_me_ekenwan', 'lapo housing');
  perform pg_temp.assert(not exists (select 1 from inventory where user_id = v), 'lapo bag empty');
  perform pg_temp.assert((select count(*) from ledger where user_id = v) = 1, 'only the cash start_bonus');
  select body into ev from events where user_id = v and kind = 'welcome';
  perform pg_temp.assert(ev ilike '%Ekenwan%' and ev ilike '%₦5,000%' and ev ilike '%hustle%', 'lapo welcome text');
  perform pg_temp.assert((s->'origin'->>'allowance_daily')::bigint = 0 and not (s->'origin'->>'allowance_claimable')::boolean,
                         'lapo no allowance');
  perform pg_temp.assert(s->'origin'->'perks'->>'micro_loan_access' = 'easy', 'lapo perks exposed');
  -- boundary: roll 0.10 -> 10 is not < 10 -> LAPO
  s := pg_temp.make_player('Lapo_Edge', '0.1');
  perform pg_temp.assert(s->'profile'->>'origin' = 'lapo', 'roll at exactly nepo_pct is LAPO');
  s := pg_temp.make_player('Nepo_Edge', '0.0999');
  perform pg_temp.assert(s->'profile'->>'origin' = 'nepo', 'roll just under nepo_pct is Nepo');
  raise notice 'ok 2: forced LAPO roll + boundary';
end $$;

-- ---------- 3. config drives the roll; tiers stack; missing tier keys fall back to start.* ----------
do $$
declare s jsonb;
begin
  update game_config set value = '60' where key = 'origin.nepo_pct';
  s := pg_temp.make_player('Pct_Sixty', '0.5');
  perform pg_temp.assert(s->'profile'->>'origin' = 'nepo', 'nepo_pct 60 + roll 0.5 -> nepo');
  update game_config set value = '0' where key = 'origin.nepo_pct';
  s := pg_temp.make_player('Pct_Zero', '0');
  perform pg_temp.assert(s->'profile'->>'origin' = 'lapo', 'nepo_pct 0 -> always lapo');
  update game_config set value = '10' where key = 'origin.nepo_pct';

  -- a new tier only needs a row + config rows
  insert into game_config (key, value, category, label, kind) values
    ('origin.test_pct', '5', 'origin', 'Test tier chance', 'percent'),
    ('origin.oba_cousin.start_cash', '777', 'origin', 'Test cash', 'naira');
  insert into origin_tiers (id, name, tagline, welcome, chance_key, sort)
    values ('oba_cousin', 'Test tier', 'test', 'Hi {name} at {home}', 'origin.test_pct', 5);
  s := pg_temp.make_player('Stack_A', '0.03');   -- 3 < 5            -> oba_cousin (sort 5 first)
  perform pg_temp.assert(s->'profile'->>'origin' = 'oba_cousin', 'first tier by sort');
  perform pg_temp.assert((s->'profile'->>'cash')::bigint = 777, 'tier cash from its own key');
  perform pg_temp.assert(s->'profile'->>'home_location_id' = bl_cfg_text('start.home_location')
                         and (s->'profile'->>'bank')::bigint = bl_cfg('start.bank')
                         and s->'profile'->>'housing_id' = bl_cfg_text('start.housing'), 'missing keys fall back to start.*');
  perform pg_temp.assert((s->'origin'->>'allowance_daily')::bigint = 0 and jsonb_array_length(s->'origin'->'items') = 0,
                         'missing allowance/items -> none');
  s := pg_temp.make_player('Stack_B', '0.12');   -- 5 <= 12 < 5+10   -> nepo
  perform pg_temp.assert(s->'profile'->>'origin' = 'nepo', 'percentages stack cumulatively');
  s := pg_temp.make_player('Stack_C', '0.16');   -- >= 15            -> default
  perform pg_temp.assert(s->'profile'->>'origin' = 'lapo', 'beyond the stack -> default tier');
  delete from profiles where origin = 'oba_cousin';
  delete from origin_tiers where id = 'oba_cousin';
  delete from game_config where key in ('origin.test_pct', 'origin.oba_cousin.start_cash');
  raise notice 'ok 3: nepo_pct drives the roll, tiers stack, start.* fallback';
end $$;

-- ---------- 4. claim_allowance ----------
do $$
declare r jsonb; v uuid := pg_temp.ou('Nepo_Osaro'); v_bank bigint; v_day int; v_nu timestamptz;
begin
  perform pg_temp.login(v);
  v_bank := (select bank from profiles where id = v);
  v_day := (bl_game_clock()->>'day')::int;
  r := claim_allowance();
  perform pg_temp.assert(r->>'message' = 'Dad sent ₦5,000 to your account. Spend it wisely.', 'allowance message: ' || (r->>'message'));
  perform pg_temp.assert((r->>'amount')::bigint = 5000 and r->>'account' = 'bank', 'allowance result');
  perform pg_temp.assert((select bank from profiles where id = v) = v_bank + 5000, 'bank +5000');
  perform pg_temp.assert((select allowance_claimed_day from profiles where id = v) = v_day, 'claimed day stored');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'allowance' and delta = 5000
                                 and (meta->>'day')::int = v_day), 'allowance ledger');
  perform pg_temp.assert(not (get_my_state()->'origin'->>'allowance_claimable')::boolean, 'not claimable after claim');
  -- second claim the same game day fails, nothing paid
  perform pg_temp.expect_error($q$ select claim_allowance() $q$, '%already sent today%');
  perform pg_temp.assert((select bank from profiles where id = v) = v_bank + 5000, 'no double pay');
  -- next game day (1 game day = 2 real hours at 12x)
  perform pg_temp.advance(7200);
  perform pg_temp.assert((bl_game_clock()->>'day')::int = v_day + 1, 'clock moved one game day');
  perform pg_temp.assert((get_my_state()->'origin'->>'allowance_claimable')::boolean, 'claimable next day');
  -- get_my_state stays read-only (no needs persist, no allowance change)
  select needs_updated_at into v_nu from profiles where id = v;
  perform get_my_state();
  perform pg_temp.assert((select needs_updated_at from profiles where id = v) = v_nu
                         and (select allowance_claimed_day from profiles where id = v) = v_day, 'get_my_state read-only');
  -- works while busy (bank transfer)
  perform bl_set_busy(v, 60, 'Sleeping');
  r := claim_allowance();
  perform pg_temp.assert((select bank from profiles where id = v) = v_bank + 10000, 'claimed again next day, even while busy');
  update profiles set busy_until = null, busy_label = null where id = v;
  -- not while jailed
  perform pg_temp.advance(7200);
  perform bl_jail(v, 30, 'test');
  perform pg_temp.expect_error($q$ select claim_allowance() $q$, '%cell%');
  update profiles set jailed_until = null, jail_reason = null, location_id = 'gra_duplex' where id = v;
  perform claim_allowance();
  -- LAPO babies have no allowance
  perform pg_temp.login(pg_temp.ou('Lapo_Efosa'));
  perform pg_temp.expect_error($q$ select claim_allowance() $q$, '%No Dad allowance%');
  perform pg_temp.assert((select bank from profiles where id = pg_temp.ou('Lapo_Efosa')) = 0, 'lapo bank untouched');
  -- admin can turn LAPO allowance on
  update game_config set value = '1000' where key = 'origin.lapo.allowance_daily';
  r := claim_allowance();
  perform pg_temp.assert((select bank from profiles where id = pg_temp.ou('Lapo_Efosa')) = 1000, 'tunable lapo allowance');
  update game_config set value = '0' where key = 'origin.lapo.allowance_daily';
  raise notice 'ok 4: claim_allowance once per game day';
end $$;

-- ---------- 5. Nepo baby can drive ----------
do $$
declare o jsonb;
begin
  perform pg_temp.login(pg_temp.ou('Nepo_Osaro'));
  update profiles set busy_until = null, travel_to = null where id = pg_temp.ou('Nepo_Osaro');
  select x into o from jsonb_array_elements(travel_quote('national_museum')->'options') x where x->>'mode' = 'car';
  perform pg_temp.assert((o->>'allowed')::boolean, 'nepo car allowed: ' || o::text);
  perform pg_temp.login(pg_temp.ou('Lapo_Efosa'));
  select x into o from jsonb_array_elements(travel_quote('national_museum')->'options') x where x->>'mode' = 'car';
  perform pg_temp.assert(not (o->>'allowed')::boolean and o->>'reason' ilike '%car yet%', 'lapo has no car');
  raise notice 'ok 5: car travel for Nepo baby';
end $$;

-- ---------- 6. create_profile validation unchanged ----------
do $$
declare v uuid := pg_temp.new_user('valid@origin.bl');
begin
  perform pg_temp.login(pg_temp.ou('Nepo_Osaro'));
  perform pg_temp.expect_error($q$ select create_profile('Another1', 'male', '{}') $q$, '%already create%');
  perform pg_temp.login(v);
  perform pg_temp.expect_error($q$ select create_profile('nepo_osaro', 'female', '{}') $q$, '%already taken%');
  perform pg_temp.expect_error($q$ select create_profile('ab', 'female', '{}') $q$, '%3 to 20%');
  perform pg_temp.expect_error($q$ select create_profile('bad name', 'female', '{}') $q$, '%3 to 20%');
  perform pg_temp.expect_error($q$ select create_profile('Efe', 'alien', '{}') $q$, '%male or female%');
  perform pg_temp.expect_error($q$ select create_profile('Efe', 'female', '[1,2]') $q$, '%avatar%');
  perform pg_temp.assert(not exists (select 1 from profiles where id = v), 'failed creates leave no profile');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = v), 'failed creates pay nothing');
  -- a broken tier home blocks creation with a Pidgin error instead of a half-made profile
  update game_config set value = '"atlantis"' where key = 'origin.lapo.home_location';
  perform set_config('bl.test_rand', '0.9', true);
  perform pg_temp.expect_error($q$ select create_profile('Efe_Ok', 'female', '{}') $q$, '%isn''t on the map%');
  update game_config set value = '"ekenwan_room"' where key = 'origin.lapo.home_location';
  perform pg_temp.assert(create_profile('Efe_Ok', 'female', '{}')->'profile'->>'origin' = 'lapo', 'valid create after fix');
  perform set_config('bl.test_rand', '', true);
  raise notice 'ok 6: create_profile validation';
end $$;

do $$ begin raise notice 'ALL ORIGIN TESTS PASSED'; end $$;
