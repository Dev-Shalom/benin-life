-- M2 movement & task feel (20261006001200_sim_feel.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/sim_feel_test.sql
-- Groups: config keys + privileges, activity_stop keeps the earned share (ease-out) and frees the player,
-- nothing running / shifts / other players.

create or replace function pg_temp.sf_hint(p_sql text, p_hint text) returns text
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

create temp table t_sf (name text primary key, id uuid not null) on commit drop;
grant select on t_sf to authenticated;
create or replace function pg_temp.sf(p_name text) returns uuid
language sql as $$ select id from t_sf where name = p_name $$;

create or replace function pg_temp.sf_make(p_name text, p_origin text, p_home text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@simfeel.bl');
begin
  insert into t_sf values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = to_jsonb(p_origin) where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home(p_home);
  update profiles set rent_owed = 0 where id = v;
  return v;
end $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
end $$;

-- ---------- 1. config + privileges ----------
do $$
begin
  perform pg_temp.assert(bl_cfg('sim.walk_speed') = 1.9, 'sim.walk_speed defaults to 1.9');
  perform pg_temp.assert(bl_cfg('sim.robe_speed_mult') = 0.7, 'sim.robe_speed_mult defaults to 0.7');
  perform pg_temp.assert(bl_cfg('sim.tired_slowdown') = 0.18, 'sim.tired_slowdown defaults to 0.18');
  perform pg_temp.assert(bl_cfg('action.queue_max') in (5, 7), 'action.queue_max defaults to 5 (7 since P1)');
  perform pg_temp.assert((select category from game_config where key = 'sim.walk_speed') = 'sim', 'category sim');
  perform pg_temp.assert((select category from game_config where key = 'action.queue_max') = 'action', 'queue in action timing');
  perform pg_temp.assert((select min = 0.5 and max = 4 from game_config where key = 'sim.walk_speed'), 'walk speed range');
  perform pg_temp.assert((select value from game_config where key = 'home.walk_max_share_pct') = '15'::jsonb, 'old walk share kept');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.activity_stop()', 'execute'), 'authenticated may stop');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.activity_stop()', 'execute'), 'anon may not stop');
  raise notice 'ok 1: config + privileges';
end $$;

-- ---------- 2. stop halfway keeps the earned share ----------
do $$
declare
  a uuid := pg_temp.sf_make('Sf_Ada', 'lapo', 'ekenwan_face_me');
  r jsonb;
  p profiles;
  v_from numeric;
  v_to numeric;
  v_e numeric := 1 - 0.5 * 0.5; -- ease-out at half time
begin
  perform pg_temp.login(a);
  update profiles set energy = 10, busy_until = null where id = a;
  r := do_activity('nap');
  select * into p from profiles where id = a;
  v_from := (p.busy_needs_from->>'energy')::numeric;
  v_to := p.energy;
  perform pg_temp.assert(v_to > v_from, 'nap raised energy up front');
  -- put the window so that now is exactly half way
  update profiles set busy_started_at = now() - interval '4 seconds', busy_until = now() + interval '4 seconds' where id = a;
  perform pg_temp.assert(pg_temp.sf_hint('select do_activity(''nap'')', 'busy') ilike '%busy%', 'busy while napping');
  r := activity_stop();
  perform pg_temp.assert((r->>'stopped')::boolean, 'stopped: ' || r::text);
  perform pg_temp.assert((r->>'kept_pct')::int = 75, 'kept 75 % at half time (ease-out): ' || r::text);
  select * into p from profiles where id = a;
  perform pg_temp.assert(abs(p.energy - (v_from + (v_to - v_from) * v_e)) < 0.2,
    format('energy keeps the earned share: %s from %s to %s', p.energy, v_from, v_to));
  perform pg_temp.assert(p.busy_until <= bl_now() and p.busy_needs_from is null, 'free again');
  -- free: the next action starts at once
  r := do_activity('use_toilet');
  perform pg_temp.assert(r ? 'busy_until', 'next action starts after a stop');
  raise notice 'ok 2: stop keeps the earned share';
end $$;

-- ---------- 3. nothing running / shifts / old rows ----------
do $$
declare
  a uuid := pg_temp.sf('Sf_Ada');
  r jsonb;
begin
  perform pg_temp.login(a);
  update profiles set busy_until = null, busy_needs_from = null, job_shift_ends_at = null where id = a;
  r := activity_stop();
  perform pg_temp.assert(not (r->>'stopped')::boolean, 'nothing to stop');
  update profiles set busy_started_at = now(), busy_until = now() + interval '10 seconds',
                      busy_needs_from = '{"energy": 1}', job_shift_ends_at = now() + interval '10 seconds' where id = a;
  update profiles set job_shift_ends_at = busy_until where id = a;
  perform pg_temp.sf_hint('select activity_stop()', 'shift');
  update profiles set job_shift_ends_at = null, busy_needs_from = null where id = a;
  perform pg_temp.sf_hint('select activity_stop()', 'not_stoppable');
  perform pg_temp.assert((select busy_until > now() from profiles where id = a), 'refused stops leave the timer alone');
  update profiles set busy_until = null where id = a;
  raise notice 'ok 3: nothing running / shift / no snapshot';
end $$;

-- ---------- 4. only your own timer ----------
do $$
declare
  a uuid := pg_temp.sf('Sf_Ada');
  b uuid := pg_temp.sf_make('Sf_Bisi', 'nepo', 'gra_duplex');
  r jsonb;
begin
  perform pg_temp.login(a);
  update profiles set energy = 20, busy_until = null where id = a;
  r := do_activity('nap');
  perform pg_temp.login(b);
  r := activity_stop();
  perform pg_temp.assert(not (r->>'stopped')::boolean, 'Bisi has nothing running');
  perform pg_temp.assert((select busy_until > now() from profiles where id = a), 'Ada keeps napping');
  raise notice 'ok 4: only your own timer';
end $$;
