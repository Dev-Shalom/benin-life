-- Time tuning tests (P1-TIME): shorter busy timers, busy_started_at, clock epoch. Run after all
-- migrations through 20261005000300_time_tuning.sql:
--   bash scripts/sql-test.sh supabase/migrations/*.sql -- supabase/tests/time_test.sql
-- Rolled back at the end. Time travel with bl.test_offset_seconds (relative to real now()).

-- local helper (standalone; safe if another test already defined it)
-- R3a: origin.force_next (20261005000400_creator.sql) would override the forced rolls below; clear it.
-- A no-op when that migration is not loaded.
update game_config set value = '""'::jsonb where key = 'origin.force_next';

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

create temp table t_tu (name text primary key, id uuid not null) on commit drop;

-- ---------- 0. config ----------
do $$
declare r record;
begin
  select * into r from game_config where key = 'time.real_seconds_per_game_minute';
  perform pg_temp.assert(bl_cfg('time.real_seconds_per_game_minute') = 0.75, 'real_seconds_per_game_minute = 0.75');
  perform pg_temp.assert(r.min <= 0.75 and r.max >= 0.75 and r.category = 'time', 'range allows 0.75, still tunable');
  perform pg_temp.assert(bl_real_seconds(480) = 360, 'sleep 480 game min = 360 real s (6 min)');

  select * into r from game_config where key = 'clock.epoch';
  perform pg_temp.assert(found and r.category = 'clock' and r.kind = 'text' and r.label <> '', 'clock.epoch config row');
  perform pg_temp.assert(bl_cfg_text('clock.epoch')::timestamptz = timestamptz '2026-10-05 00:00:00+00', 'epoch default 2026-10-05Z');
  -- the clock no longer counts from 2026-01-01: today is a small day number
  perform pg_temp.assert((bl_game_clock(timestamptz '2026-10-05 12:00:00+00')->>'day')::int = 7, 'noon on launch day = day 7');
  -- bad epoch rejected (would break every clock call)
  perform pg_temp.expect_error($q$ update game_config set value = '"next tuesday"' where key = 'clock.epoch' $q$, '%Clock epoch%');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_set_busy(uuid,int,text)', 'execute')
                     and not has_function_privilege('authenticated', 'public.bl_game_clock(timestamptz)', 'execute'),
                         'helpers stay internal');
  raise notice 'ok 0: time config + epoch';
end $$;

-- ---------- 1. sleep at home: busy_started_at / busy_until ----------
do $$
declare v uuid := pg_temp.new_user('sleeper@time.bl'); s jsonb; r jsonb; me profiles; v_rate numeric;
begin
  insert into t_tu values ('sleeper', v);
  perform set_config('bl.test_offset_seconds', '', true);   -- earlier test files may leave time travelled
  perform pg_temp.login(v);
  perform set_config('bl.test_rand', '0.99', true);   -- default tier (LAPO baby): home = face-me room
  s := create_profile('Sleepy_Osa', 'male', '{"gender":"male"}');
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(s->'profile' ? 'busy_started_at' and jsonb_typeof(s->'profile'->'busy_started_at') = 'null',
                         'busy_started_at exposed, null at start');
  perform pg_temp.assert(s->'profile'->>'location_id' = s->'profile'->>'home_location_id', 'spawned at home');

  v_rate := bl_cfg('time.real_seconds_per_game_minute');
  r := do_activity('sleep');
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.busy_started_at = bl_now(), 'busy_started_at = now');
  perform pg_temp.assert(me.busy_until = bl_now() + make_interval(secs => (480 * v_rate)::double precision),
                         'busy_until = now + 480 x rate');
  perform pg_temp.assert(abs(extract(epoch from me.busy_until - me.busy_started_at) - 360) < 0.001, 'sleep lasts 6 real minutes');
  perform pg_temp.assert((r->>'busy_until')::timestamptz = me.busy_until, 'do_activity returns busy_until');

  -- exposed by get_my_state (read-only), and busy blocks until the end
  s := get_my_state();
  perform pg_temp.assert((s->'profile'->>'busy_started_at')::timestamptz = me.busy_started_at, 'get_my_state has busy_started_at');
  perform set_config('bl.test_offset_seconds', '359', true);
  perform pg_temp.expect_error($q$ select do_activity('nap') $q$, '%busy%');
  perform set_config('bl.test_offset_seconds', '361', true);
  r := do_activity('nap');
  select * into me from profiles where id = v;
  perform pg_temp.assert(me.busy_started_at = bl_now() and me.busy_label = (select name from activities where id = 'nap'),
                         'next activity restarts busy_started_at');
  perform pg_temp.assert(me.busy_until = bl_now() + make_interval(secs => (90 * v_rate)::double precision), 'nap 90 x rate');

  -- admin retune applies to the next activity
  update game_config set value = '2' where key = 'time.real_seconds_per_game_minute';
  perform bl_set_busy(v, 10, 'Test');
  perform pg_temp.assert((select busy_until - busy_started_at from profiles where id = v) = interval '20 seconds', 'tunable rate');
  update game_config set value = '0.75' where key = 'time.real_seconds_per_game_minute';
  perform set_config('bl.test_offset_seconds', '', true);
  raise notice 'ok 1: sleep 6 real min, busy_started_at';
end $$;

-- ---------- 2. clock epoch: day 1 at the epoch, +1 day every 1440 game minutes ----------
do $$
declare
  e timestamptz := bl_cfg_text('clock.epoch')::timestamptz;
  spd numeric := bl_cfg('clock.game_minutes_per_real_minute');
  off numeric := bl_cfg('clock.start_hour_offset');
  day_s numeric := 1440 * 60 / spd;         -- real seconds per game day
  c jsonb; v_now_off numeric;
begin
  c := bl_game_clock(e);
  perform pg_temp.assert((c->>'day')::int = 1 and (c->>'hour')::int = off and (c->>'minute')::int = 0
                         and (c->>'game_minutes')::bigint = off * 60, 'epoch = day 1, start_hour_offset:00');
  -- just before the first midnight is still day 1; midnight is day 2; +1440 game min = +1 day
  perform pg_temp.assert((bl_game_clock(e + make_interval(secs => ((1440 - off * 60) * 60 / spd - 1)::double precision))->>'day')::int = 1,
                         'still day 1 just before midnight');
  c := bl_game_clock(e + make_interval(secs => ((1440 - off * 60) * 60 / spd)::double precision));
  perform pg_temp.assert((c->>'day')::int = 2 and (c->>'hour')::int = 0, 'midnight -> day 2');
  perform pg_temp.assert((bl_game_clock(e + make_interval(secs => (9 * day_s)::double precision))->>'day')::int = 10
                         and (bl_game_clock(e + make_interval(secs => (9 * day_s)::double precision))->>'hour')::int = off,
                         '+9 game days -> day 10 same hour');

  -- time-travel bl_now() relative to real now(): put "now" exactly on the epoch, then step a day
  v_now_off := extract(epoch from e - now());
  perform set_config('bl.test_offset_seconds', v_now_off::text, true);
  perform pg_temp.assert(abs(extract(epoch from bl_now() - e)) < 0.001, 'offset lands on epoch');
  perform pg_temp.assert((bl_game_clock()->>'day')::int = 1, 'bl_game_clock() day 1 at epoch');
  perform set_config('bl.test_offset_seconds', (v_now_off + day_s)::text, true);
  perform pg_temp.assert((bl_game_clock()->>'day')::int = 2 and (bl_game_clock()->>'hour')::int = off, 'day 2 one game day later');

  -- moving the epoch renumbers days; same-parity hour shift keeps time of day (2 real h = 1 game day at 12x)
  update game_config set value = to_jsonb(to_char((e - interval '2 hours') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
   where key = 'clock.epoch';
  perform pg_temp.assert((bl_game_clock()->>'day')::int = 3 and (bl_game_clock()->>'hour')::int = off, 'epoch tunable');
  update game_config set value = to_jsonb(to_char(e at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')) where key = 'clock.epoch';

  -- old 2026-01-01 epoch and new one agree on time of day (only day number changes)
  perform pg_temp.assert(mod(extract(epoch from e - timestamptz '2026-01-01 00:00:00+00') * spd / 60, 1440) = 0,
                         'epoch shift is whole game days');
  perform set_config('bl.test_offset_seconds', '', true);
  raise notice 'ok 2: clock epoch day counter';
end $$;

-- ---------- 3. real-time systems are untouched by the epoch ----------
do $$
declare v uuid := (select id from t_tu where name = 'sleeper'); h_before numeric; h_after numeric;
begin
  -- needs decay uses real elapsed time x clock speed, not game day: moving the epoch changes nothing
  update profiles set hunger = 80, needs_updated_at = bl_now() - interval '10 minutes' where id = v;
  h_before := (bl_decay_row((select p from profiles p where id = v), bl_now())).hunger;
  update game_config set value = '"2020-01-01T00:00:00Z"' where key = 'clock.epoch';
  h_after := (bl_decay_row((select p from profiles p where id = v), bl_now())).hunger;
  perform pg_temp.assert(h_before = h_after, 'decay independent of epoch');
  update game_config set value = '"2026-10-05T00:00:00Z"' where key = 'clock.epoch';
  raise notice 'ok 3: decay independent of epoch';
end $$;

do $$ begin raise notice 'ALL TIME TESTS PASSED'; end $$;
