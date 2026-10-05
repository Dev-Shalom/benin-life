-- Bladder tests (R4): column + config, decay with trait multipliers, the empty-bladder hygiene
-- penalty, toilet activities (home only / paid public ones), clamping, get_my_state stays read-only,
-- players_online(). Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/bladder_test.sql
-- Rolled back at the end. Time with bl.test_offset_seconds.
-- Rent is ON since V1-4; keep it off here so time travel never charges rent and moves cash.
update public.game_config set value = 'false' where key = 'rent.enabled';

create or replace function pg_temp.b_advance(p_seconds numeric) returns numeric
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
  return v;
end $$;

create or replace function pg_temp.b_approx(a numeric, b numeric, eps numeric default 0.05) returns boolean
language sql as $$ select abs(coalesce(a, -999) - b) <= eps $$;

create or replace function pg_temp.b_expect_error(p_sql text, p_like text) returns void
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

create temp table t_bu (name text primary key, id uuid not null) on commit drop;
create or replace function pg_temp.bu(p_name text) returns uuid
language sql as $$ select id from t_bu where name = p_name $$;

-- new logged-in user with a v2 Sim moved into p_home (LAPO roll)
create or replace function pg_temp.b_make(p_name text, p_home text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@bladder.bl');
begin
  insert into t_bu values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home(p_home);
  return v;
end $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
end $$;

-- ---------- 0. schema, config, seeds ----------
do $$
begin
  perform pg_temp.assert(exists (select 1 from information_schema.columns
                                 where table_schema = 'public' and table_name = 'profiles' and column_name = 'bladder'
                                   and column_default = '100'), 'profiles.bladder default 100');
  perform pg_temp.assert(bl_cfg('needs.bladder_per_hour') = 5, 'bladder decay config');
  perform pg_temp.assert(bl_cfg('needs.bladder_empty_hygiene_per_hour') = 4, 'accident config');
  perform pg_temp.assert((select count(*) from game_config where key like 'needs.bladder%' and label <> '' and category = 'needs') = 2,
                         'bladder config labelled');
  perform pg_temp.assert((select home_only and cost = 0 and (effects->>'bladder')::numeric > 0
                          from activities where id = 'use_toilet'), 'use_toilet is free and home only');
  perform pg_temp.assert((select scenes @> '{home_face_me,home_flat,home_duplex}' from activities where id = 'use_toilet'),
                         'toilet in every home type');
  perform pg_temp.assert((select not home_only and cost > 0 and scenes @> '{buka,club}' from activities where id = 'ease_yourself'),
                         'restroom at buka/club costs a little');
  perform pg_temp.assert((select not home_only and cost > 0 and scenes @> '{market,motorpark}' from activities where id = 'public_toilet'),
                         'public toilet at market/motorpark costs a little');
  perform pg_temp.assert((select (effects->>'bladder')::numeric < 0 from activities where id = 'club_night'), 'club drinks fill the bladder');
  perform pg_temp.assert(exists (select 1 from activities where id = 'watch_tv' and home_only)
                         and exists (select 1 from activities where id = 'listen_radio' and home_only), 'tv/radio home activities');
  -- every home scene still offers sleep, nap, bathe, cook and the toilet
  perform pg_temp.assert(not exists (
    select 1 from unnest(array['home_face_me','home_flat','home_duplex']) s, unnest(array['sleep','nap','bathe','cook_home','use_toilet']) a
    where not exists (select 1 from activities x where x.id = a and s = any (x.scenes))), 'home basics everywhere');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.players_online()', 'execute'), 'anon cannot count players');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.players_online()', 'execute'), 'players can count players');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_adjust_needs(uuid, jsonb)', 'execute'), 'helpers internal');
end $$;

-- ---------- 1. decay, trait multiplier, accident ----------
do $$
declare u uuid; s jsonb; p profiles;
begin
  u := pg_temp.b_make('bladder_a', 'uniben_hostel');
  s := get_my_state();
  perform pg_temp.assert((s->'profile') ? 'bladder', 'GameState.profile has bladder');
  perform pg_temp.assert(pg_temp.b_approx((s->'profile'->>'bladder')::numeric, 100), 'starts full');

  -- 4 game hours (12 game min per real min => 1 game hour = 300 s)
  update profiles set bladder = 100, hygiene = 80, needs_updated_at = bl_now() where id = u;
  perform pg_temp.b_advance(1200);
  s := get_my_state();
  perform pg_temp.assert(pg_temp.b_approx((s->'profile'->>'bladder')::numeric, 80), 'bladder -5/h x4 = 80, got ' || (s->'profile'->>'bladder'));
  perform pg_temp.assert(pg_temp.b_approx((s->'profile'->>'hygiene')::numeric, 70), 'no accident yet: hygiene 80-10');
  -- get_my_state never writes needs
  select * into p from profiles where id = u;
  perform pg_temp.assert(p.bladder = 100, 'get_my_state is read-only for bladder');

  -- accident: bladder 10 empties after 2 h; the remaining 2 h cost 4/h extra hygiene
  update profiles set bladder = 10, hygiene = 80, needs_updated_at = bl_now() where id = u;
  perform pg_temp.b_advance(1200);
  p := bl_apply_needs(u);
  perform pg_temp.assert(p.bladder = 0, 'bladder clamps at 0');
  perform pg_temp.assert(pg_temp.b_approx(p.hygiene, 80 - 2.5 * 4 - 4 * 2), 'accident hygiene = 62, got ' || p.hygiene);

  -- path independence: two half steps == one full step
  update profiles set bladder = 10, hygiene = 80, needs_updated_at = bl_now() where id = u;
  perform pg_temp.b_advance(600);
  perform bl_apply_needs(u);
  perform pg_temp.b_advance(600);
  p := bl_apply_needs(u);
  perform pg_temp.assert(p.bladder = 0 and pg_temp.b_approx(p.hygiene, 62), 'path independent, got ' || p.hygiene);

  -- trait multiplier (effects.decay.bladder) doubles the rate
  insert into traits (id, name, emoji, description, effects, sort, active)
  values ('tiny_bladder_test', 'Tiny Bladder', '🚽', 'Test only', '{"decay":{"bladder":2}}', 999, false);
  update profiles set traits = '{tiny_bladder_test}', bladder = 100, hygiene = 80, needs_updated_at = bl_now() where id = u;
  perform pg_temp.b_advance(1200);
  p := bl_apply_needs(u);
  perform pg_temp.assert(pg_temp.b_approx(p.bladder, 60), 'trait x2: 100-40 = 60, got ' || p.bladder);
  perform pg_temp.assert(pg_temp.b_approx(p.hygiene, 70), 'other needs unaffected by the bladder trait');
  update profiles set traits = '{hustler,foodie}' where id = u;
end $$;

-- ---------- 2. activities ----------
do $$
declare u uuid := pg_temp.bu('bladder_a'); r jsonb; p profiles; v_cash bigint;
begin
  perform pg_temp.login(u);
  -- toilet at home
  update profiles set bladder = 20, busy_until = null, needs_updated_at = bl_now() where id = u;
  r := do_activity('use_toilet');
  select * into p from profiles where id = u;
  perform pg_temp.assert(p.bladder = 100, 'toilet refills to 100 (clamped), got ' || p.bladder);
  perform pg_temp.assert(p.busy_until > bl_now() and p.busy_label = 'Use the toilet', 'toilet sets busy');
  perform pg_temp.assert(r->>'message' like '%Use the toilet%', 'toilet message');

  -- the home toilet is not offered in a market; the paid public one is
  update profiles set busy_until = null, location_id = 'uselu_market', bladder = 30, cash = 1000 where id = u;
  perform pg_temp.b_expect_error($q$ select do_activity('use_toilet') $q$, '%can''t do%here%');
  r := do_activity('public_toilet');
  select * into p from profiles where id = u;
  v_cash := (select cost from activities where id = 'public_toilet');
  perform pg_temp.assert(p.cash = 1000 - v_cash, 'public toilet costs ' || v_cash);
  perform pg_temp.assert(p.bladder = 100, 'public toilet refills');

  -- broke: the paid toilet refuses
  update profiles set busy_until = null, cash = 0 where id = u;
  perform pg_temp.b_expect_error($q$ select do_activity('public_toilet') $q$, '%money no reach%');

  -- buka restroom
  update profiles set busy_until = null, location_id = 'mama_osas_buka', cash = 500, bladder = 5 where id = u;
  perform do_activity('ease_yourself');
  perform pg_temp.assert((select bladder from profiles where id = u) = 100, 'buka restroom refills');

  -- drinks lower it; adjust clamps both ways
  perform bl_adjust_needs(u, '{"bladder": -500}');
  perform pg_temp.assert((select bladder from profiles where id = u) = 0, 'clamp at 0');
  perform bl_adjust_needs(u, '{"bladder": 500}');
  perform pg_temp.assert((select bladder from profiles where id = u) = 100, 'clamp at 100');
  update profiles set location_id = home_location_id, busy_until = null where id = u;
end $$;

-- ---------- 3. players_online ----------
do $$
declare u uuid := pg_temp.bu('bladder_a'); r jsonb; n bigint;
begin
  perform pg_temp.login(u);
  update profiles set last_seen = bl_now() where id = u;
  r := players_online();
  n := (r->>'count')::bigint;
  perform pg_temp.assert(n >= 1, 'at least me online');
  perform pg_temp.assert((r->>'minutes')::numeric = bl_cfg('time.presence_real_minutes'), 'presence window echoed');
  update profiles set last_seen = bl_now() - interval '1 hour' where id = u;
  perform pg_temp.assert((players_online()->>'count')::bigint = n - 1, 'stale players not counted');
end $$;

do $$ begin raise notice 'bladder_test: all passed'; end $$;
