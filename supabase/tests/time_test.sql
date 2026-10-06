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

-- ---------- L1 defaults (checked before sections 0-3 switch to the accelerated clock) ----------
do $$ begin
  perform pg_temp.assert(bl_cfg_text('clock.mode') = 'real', 'clock.mode defaults to real');
  perform pg_temp.assert(bl_cfg_text('clock.timezone') = 'Africa/Lagos', 'clock.timezone = Africa/Lagos');
  perform pg_temp.assert(bl_cfg_text('action.mode') = 'short', 'action.mode defaults to short');
  -- sections 0-3 pin the P1-TIME behaviour: accelerated clock + game-minute durations (rolled back)
  update game_config set value = '"accelerated"' where key = 'clock.mode';
  update game_config set value = '"game_minutes"' where key = 'action.mode';
  raise notice 'ok L1 defaults; sections 0-3 run on the accelerated clock';
end $$;

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

-- =====================================================================
-- L1: real Benin time (clock.mode = real) + action timing (action.mode = short)
-- =====================================================================
create or replace function pg_temp.at(p timestamptz) returns void
language sql as $$ select set_config('bl.test_offset_seconds', extract(epoch from p - now())::text, true) $$;

-- ---------- L1-1. real clock at fixed instants ----------
do $$
declare c jsonb;
begin
  update game_config set value = '"real"' where key = 'clock.mode';
  update game_config set value = '"short"' where key = 'action.mode';
  update game_config set value = '20' where key = 'clock.night_start_hour';
  update game_config set value = '6' where key = 'clock.night_end_hour';
  perform set_config('bl.test_offset_seconds', '', true);

  -- 21:07 UTC = 22:07 WAT on Monday 5 Oct 2026, launch day = Day 1
  c := bl_game_clock(timestamptz '2026-10-05 21:07:00+00');
  perform pg_temp.assert((c->>'day')::int = 1 and (c->>'hour')::int = 22 and (c->>'minute')::int = 7
                         and (c->>'weekday')::int = 0 and (c->>'is_night')::boolean
                         and c->>'date' = '2026-10-05' and c->>'mode' = 'real', 'Mon 22:07 WAT day 1: ' || c::text);
  perform pg_temp.assert((c->>'game_minutes')::bigint = 22 * 60 + 7, 'game_minutes = (day-1)*1440 + local minutes');
  -- local midnight (23:00 UTC) rolls the day; 00:00 WAT on launch day is still day 1
  c := bl_game_clock(timestamptz '2026-10-05 22:59:59+00');
  perform pg_temp.assert((c->>'day')::int = 1 and (c->>'hour')::int = 23 and (c->>'minute')::int = 59, '23:59 still day 1');
  c := bl_game_clock(timestamptz '2026-10-05 23:00:00+00');
  perform pg_temp.assert((c->>'day')::int = 2 and (c->>'hour')::int = 0 and (c->>'weekday')::int = 1
                         and c->>'date' = '2026-10-06', 'WAT midnight -> Tue day 2');
  c := bl_game_clock(timestamptz '2026-10-04 23:00:00+00');
  perform pg_temp.assert((c->>'day')::int = 1 and (c->>'hour')::int = 0, '00:00 WAT 5 Oct = day 1');
  -- Saturday and the next Monday
  c := bl_game_clock(timestamptz '2026-10-10 12:00:00+00');
  perform pg_temp.assert((c->>'weekday')::int = 5 and (c->>'day')::int = 6 and (c->>'hour')::int = 13, 'Sat 10 Oct = day 6, 13:00');
  c := bl_game_clock(timestamptz '2026-10-12 06:00:00+00');
  perform pg_temp.assert((c->>'weekday')::int = 0 and (c->>'day')::int = 8, 'Mon 12 Oct = day 8');
  -- night boundaries (night_start 20, night_end 6) in WAT
  perform pg_temp.assert(not (bl_game_clock(timestamptz '2026-10-06 18:59:00+00')->>'is_night')::boolean, '19:59 WAT day');
  perform pg_temp.assert((bl_game_clock(timestamptz '2026-10-06 19:00:00+00')->>'is_night')::boolean, '20:00 WAT night');
  perform pg_temp.assert((bl_game_clock(timestamptz '2026-10-07 04:59:00+00')->>'is_night')::boolean, '05:59 WAT night');
  perform pg_temp.assert(not (bl_game_clock(timestamptz '2026-10-07 05:00:00+00')->>'is_night')::boolean, '06:00 WAT day');
  -- the clock is the wall clock: bl_game_clock() follows bl_now()
  perform pg_temp.at(timestamptz '2026-11-20 08:30:00+00');
  c := bl_game_clock();
  perform pg_temp.assert((c->>'hour')::int = 9 and (c->>'minute')::int = 30 and c->>'date' = '2026-11-20'
                         and (c->>'day')::int = 47 and (c->>'weekday')::int = 4, 'Fri 20 Nov 09:30 WAT = day 47: ' || c::text);
  perform set_config('bl.test_offset_seconds', '', true);
  -- epoch renumbers days only; timezone is tunable; bad values rejected
  update game_config set value = '"2026-10-01T00:00:00Z"' where key = 'clock.epoch';
  c := bl_game_clock(timestamptz '2026-10-05 21:07:00+00');
  perform pg_temp.assert((c->>'day')::int = 5 and (c->>'hour')::int = 22, 'epoch 1 Oct -> 5 Oct is day 5, same time');
  update game_config set value = '"2026-10-05T00:00:00Z"' where key = 'clock.epoch';
  update game_config set value = '"UTC"' where key = 'clock.timezone';
  perform pg_temp.assert((bl_game_clock(timestamptz '2026-10-05 21:07:00+00')->>'hour')::int = 21, 'timezone tunable');
  update game_config set value = '"Africa/Lagos"' where key = 'clock.timezone';
  perform pg_temp.expect_error($q$ update game_config set value = '"fast"' where key = 'clock.mode' $q$, '%real or accelerated%');
  perform pg_temp.expect_error($q$ update game_config set value = '"Mars/Base"' where key = 'clock.timezone' $q$, '%time zone%');
  perform pg_temp.expect_error($q$ update game_config set value = '"slow"' where key = 'action.mode' $q$, '%short or game_minutes%');
  -- accelerated mode still uses the old formula
  update game_config set value = '"accelerated"' where key = 'clock.mode';
  perform pg_temp.assert((bl_game_clock(timestamptz '2026-10-05 12:00:00+00')->>'day')::int = 7
                         and bl_game_clock(timestamptz '2026-10-05 12:00:00+00')->>'mode' = 'accelerated', 'accelerated: noon = day 7');
  update game_config set value = '"real"' where key = 'clock.mode';
  perform pg_temp.assert(bl_clock_speed() = 1, 'real clock speed 1');
  raise notice 'ok L1-1: real WAT clock';
end $$;

-- ---------- L1-2. rent day = next Saturday 00:00 WAT ----------
do $$
declare v uuid := (select id from t_tu where name = 'sleeper'); d timestamptz; c jsonb;
begin
  update game_config set value = '5' where key = 'rent.due_weekday';
  d := bl_rent_due_after(timestamptz '2026-10-05 21:07:00+00', 0);
  perform pg_temp.assert(d = timestamptz '2026-10-09 23:00:00+00', 'Mon night -> Sat 10 Oct 00:00 WAT, got ' || d);
  c := bl_game_clock(d);
  perform pg_temp.assert((c->>'weekday')::int = 5 and (c->>'hour')::int = 0 and (c->>'minute')::int = 0, 'due is Sat 00:00');
  perform pg_temp.assert(bl_rent_due_after(timestamptz '2026-10-09 22:30:00+00', 0) = timestamptz '2026-10-09 23:00:00+00',
                         'Fri 23:30 -> 30 min later');
  perform pg_temp.assert(bl_rent_due_after(timestamptz '2026-10-09 23:00:00+00', 0) = timestamptz '2026-10-16 23:00:00+00',
                         'strictly after: Sat 00:00 -> next Sat');
  perform pg_temp.assert(bl_rent_due_after(timestamptz '2026-10-09 22:30:00+00', 1) = timestamptz '2026-10-16 23:00:00+00',
                         'grace 1 day from Fri 23:30 -> the Sat after');
  -- weekly charge steps one real week
  perform pg_temp.assert(bl_rent_due_after(d + interval '1 second', 0) - d = interval '7 days', 'next rent a real week later');
  -- switching clock mode re-aligns rent days to the new clock (never back-charges)
  update profiles set rent_due_at = bl_now() - interval '3 days', allowance_claimed_day = 99, job_shift_day = 99 where id = v;
  update game_config set value = '"accelerated"' where key = 'clock.mode';
  perform pg_temp.assert((select rent_due_at from profiles where id = v) = bl_rent_due_after(bl_now(), 0)
                         and (select rent_due_at from profiles where id = v) > bl_now(), 'mode switch: rent rolled forward');
  perform pg_temp.assert((select allowance_claimed_day is null and job_shift_day is null from profiles where id = v),
                         'mode switch clears stored day numbers');
  update game_config set value = '"real"' where key = 'clock.mode';
  perform pg_temp.assert((select rent_due_at from profiles where id = v) = bl_rent_due_after(bl_now(), 0), 'switch back: real Saturday');
  perform pg_temp.assert(((bl_game_clock((select rent_due_at from profiles where id = v)))->>'weekday')::int = 5, 'real due is a Saturday');
  raise notice 'ok L1-2: rent on real Saturdays';
end $$;

-- ---------- L1-3. shift cap resets at local midnight; allowance once per local day ----------
do $$
declare v uuid := pg_temp.new_user('worker@time.bl'); r jsonb; cap int;
  o_cap jsonb := (select value from game_config where key = 'career.max_shifts_per_game_day');
  o_en  jsonb := (select value from game_config where key = 'career.min_energy');
  o_hu  jsonb := (select value from game_config where key = 'career.min_hunger');
begin
  insert into t_tu values ('worker', v);
  perform pg_temp.login(v);
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile('Shift_Osa', 'female', '{"gender":"female"}');
  perform set_config('bl.test_rand', '', true);
  perform job_apply('tech');
  update game_config set value = '3' where key = 'career.max_shifts_per_game_day';
  update game_config set value = '1' where key = 'career.min_energy';
  update game_config set value = '1' where key = 'career.min_hunger';
  cap := bl_cfg('career.max_shifts_per_game_day')::int;
  perform pg_temp.at(timestamptz '2026-10-07 22:50:00+00');   -- Wed 23:50 WAT
  for i in 1..cap loop
    update profiles set location_id = 'bronze_tech_hub', busy_until = null, job_shift_ends_at = null,
                        hunger = 100, energy = 100, needs_updated_at = bl_now() where id = v;
    r := work_shift();
  end loop;
  perform pg_temp.assert((select job_shifts_today from profiles where id = v) = cap, 'cap shifts done');
  update profiles set busy_until = null, job_shift_ends_at = null, hunger = 100, energy = 100, needs_updated_at = bl_now() where id = v;
  perform pg_temp.expect_error($q$ select work_shift() $q$, '%shifts today%');
  perform pg_temp.at(timestamptz '2026-10-07 22:59:30+00');   -- 23:59:30 WAT: same day
  update profiles set busy_until = null, job_shift_ends_at = null, needs_updated_at = bl_now() where id = v;
  perform pg_temp.expect_error($q$ select work_shift() $q$, '%shifts today%');
  perform pg_temp.at(timestamptz '2026-10-07 23:00:30+00');   -- 00:00:30 WAT Thursday
  update profiles set busy_until = null, job_shift_ends_at = null, hunger = 100, energy = 100, needs_updated_at = bl_now() where id = v;
  r := work_shift();
  perform pg_temp.assert((select job_shifts_today from profiles where id = v) = 1
                         and (select job_shift_day from profiles where id = v) = (bl_game_clock()->>'day')::int,
                         'new local day: shifts reset');
  -- restore the career config for the files that run after this one
  update game_config set value = o_cap where key = 'career.max_shifts_per_game_day';
  update game_config set value = o_en  where key = 'career.min_energy';
  update game_config set value = o_hu  where key = 'career.min_hunger';
  perform set_config('bl.test_offset_seconds', '', true);
  raise notice 'ok L1-3a: shift cap resets at WAT midnight';
end $$;

do $$
declare v uuid := pg_temp.new_user('nepo@time.bl'); r jsonb;
begin
  insert into t_tu values ('nepo', v);
  perform pg_temp.login(v);
  update game_config set value = '"nepo"' where key = 'origin.force_next';
  perform create_profile('Allow_Osa', 'male', '{"gender":"male"}');
  update game_config set value = '""' where key = 'origin.force_next';
  perform pg_temp.assert((select origin from profiles where id = v) = 'nepo', 'nepo player');
  perform pg_temp.at(timestamptz '2026-10-08 22:58:00+00');   -- Thu 23:58 WAT
  r := claim_allowance();
  perform pg_temp.assert((r->>'day')::int = (bl_game_clock()->>'day')::int, 'claimed today');
  perform pg_temp.expect_error($q$ select claim_allowance() $q$, '%already sent today%');
  perform pg_temp.at(timestamptz '2026-10-08 22:59:59+00');
  perform pg_temp.expect_error($q$ select claim_allowance() $q$, '%already sent today%');
  perform pg_temp.at(timestamptz '2026-10-08 23:00:01+00');   -- Fri 00:00:01 WAT
  r := claim_allowance();
  perform pg_temp.assert((r->>'amount')::bigint > 0, 'allowance again after WAT midnight');
  raise notice 'ok L1-3b: allowance once per WAT day';
end $$;

-- ---------- L1-4. banking hours in WAT ----------
do $$
declare v uuid := (select id from t_tu where name = 'worker'); m text; b jsonb;
begin
  update game_config set value = '8' where key = 'bank.open_hour';
  update game_config set value = '16' where key = 'bank.close_hour';
  perform pg_temp.assert(not bl_bank_open(bl_game_clock(timestamptz '2026-10-06 06:59:00+00')), '07:59 WAT closed');
  perform pg_temp.assert(bl_bank_open(bl_game_clock(timestamptz '2026-10-06 07:00:00+00')), '08:00 WAT open');
  perform pg_temp.assert(bl_bank_open(bl_game_clock(timestamptz '2026-10-06 14:59:00+00')), '15:59 WAT open');
  perform pg_temp.assert(not bl_bank_open(bl_game_clock(timestamptz '2026-10-06 15:00:00+00')), '16:00 WAT closed');
  perform pg_temp.login(v);
  perform pg_temp.at(timestamptz '2026-10-06 05:00:00+00');   -- 06:00 WAT: opens in 2 real hours
  b := bank_info()->'bank_hours';
  perform pg_temp.assert(not (b->>'open')::boolean and (b->>'opens_in_game_minutes')::int = 120
                         and (b->>'opens_in_real_seconds')::int = 7200, 'bank_info: real seconds = real minutes: ' || b::text);
  update profiles set location_id = 'bronze_bank', busy_until = null, job_shift_ends_at = null, travel_to = null where id = v;
  begin
    perform bank_deposit(500);
  exception when others then m := sqlerrm;
  end;
  perform pg_temp.assert(m ilike '%is closed. Banking hours are 8:00 AM to 4:00 PM. It opens at 8:00 AM, in about 2 hrs.%', 'closed copy: ' || coalesce(m, 'none'));
  perform set_config('bl.test_offset_seconds', '', true);
  raise notice 'ok L1-4: banking hours in WAT';
end $$;

-- ---------- L1-5. needs decay per real hour ----------
do $$
declare v uuid := (select id from t_tu where name = 'sleeper'); p profiles; q profiles; spd numeric; rate numeric;
begin
  update game_config set value = '2.5' where key = 'needs.decay_speed';
  update profiles set hunger = 90, energy = 90, health = 100, traits = '{}', needs_updated_at = bl_now() where id = v;
  select * into p from profiles where id = v;
  spd := bl_cfg('needs.decay_speed');
  rate := bl_cfg('needs.hunger_per_hour');
  q := bl_decay_row(p, bl_now() + interval '1 hour');
  perform pg_temp.assert(abs(q.hunger - (90 - rate * spd)) < 0.001, format('1 real hour: hunger -%s, got %s', rate * spd, q.hunger));
  -- path-independent: 2 x 30 min = 1 hour
  perform pg_temp.assert(bl_decay_row(bl_decay_row(p, bl_now() + interval '30 minutes'), bl_now() + interval '1 hour') = q,
                         'decay path-independent');
  -- hunger 100 -> 0 in 100 / (rate x speed) real hours (10 h at the defaults)
  perform pg_temp.assert(abs(100 / (rate * spd) - 10) < 0.001 or spd <> 2.5, 'hunger empties in ~10 real hours');
  -- admin-tunable
  update game_config set value = '5' where key = 'needs.decay_speed';
  perform pg_temp.assert(abs((bl_decay_row(p, bl_now() + interval '1 hour')).hunger - (90 - rate * 5)) < 0.001, 'decay_speed tunable');
  update game_config set value = '2.5' where key = 'needs.decay_speed';
  -- accelerated mode: need-hours = game hours (clock speed), as before
  update game_config set value = '"accelerated"' where key = 'clock.mode';
  perform pg_temp.assert(abs((bl_decay_row(p, bl_now() + interval '10 minutes')).hunger
                             - (90 - rate * bl_cfg('clock.game_minutes_per_real_minute') / 6)) < 0.001, 'accelerated decay x clock speed');
  update game_config set value = '"real"' where key = 'clock.mode';
  raise notice 'ok L1-5: needs decay per real hour';
end $$;

-- ---------- L1-6. action timing: sleep <= 15 s scaled by tiredness, live-bar snapshot ----------
do $$
declare v uuid := (select id from t_tu where name = 'sleeper'); a activities; r jsonb; me profiles; secs numeric;
begin
  perform pg_temp.login(v);
  perform set_config('bl.test_offset_seconds', '', true);
  update game_config set value = 'true' where key = 'action.scale_by_need';
  select * into a from activities where id = 'sleep';
  perform pg_temp.assert(a.max_seconds = 15 and a.min_seconds = 3 and a.scale_by_need, 'sleep 15 s max, 3 s min');
  -- energy 0 -> the full max
  update profiles set location_id = home_location_id, busy_until = null, travel_to = null, energy = 0, hunger = 80,
                      rent_owed = 0, rent_due_at = bl_now() + interval '3 days', needs_updated_at = bl_now() where id = v;
  r := do_activity('sleep');
  select * into me from profiles where id = v;
  secs := extract(epoch from me.busy_until - me.busy_started_at);
  perform pg_temp.assert(abs(secs - a.max_seconds) < 0.05 and (r->>'real_seconds')::numeric = a.max_seconds,
                         'energy 0: sleep = max seconds, got ' || secs);
  perform pg_temp.assert((me.busy_needs_from->>'energy')::numeric = 0 and me.energy > 0, 'busy_needs_from keeps the start value');
  perform pg_temp.assert((get_my_state()->'profile'->'busy_needs_from'->>'energy')::numeric = 0, 'busy_needs_from exposed');
  -- energy 50 -> half; energy 90 -> the minimum
  update profiles set busy_until = null, energy = 50, needs_updated_at = bl_now() where id = v;
  perform do_activity('sleep');
  select * into me from profiles where id = v;
  perform pg_temp.assert(abs(extract(epoch from me.busy_until - me.busy_started_at) - a.max_seconds * 0.5) < 0.05, 'energy 50: half');
  update profiles set busy_until = null, energy = 90, needs_updated_at = bl_now() where id = v;
  perform do_activity('sleep');
  select * into me from profiles where id = v;
  perform pg_temp.assert(abs(extract(epoch from me.busy_until - me.busy_started_at) - greatest(a.min_seconds, a.max_seconds * 0.1)) < 0.05, 'energy 90: min');
  -- scale off -> max
  update game_config set value = 'false' where key = 'action.scale_by_need';
  update profiles set busy_until = null, energy = 90, needs_updated_at = bl_now() where id = v;
  perform do_activity('sleep');
  select * into me from profiles where id = v;
  perform pg_temp.assert(abs(extract(epoch from me.busy_until - me.busy_started_at) - a.max_seconds) < 0.05, 'scale off: max');
  update game_config set value = 'true' where key = 'action.scale_by_need';
  -- game_minutes mode: the old duration
  update game_config set value = '"game_minutes"' where key = 'action.mode';
  update profiles set busy_until = null, energy = 90, needs_updated_at = bl_now() where id = v;
  perform do_activity('sleep');
  select * into me from profiles where id = v;
  perform pg_temp.assert(abs(extract(epoch from me.busy_until - me.busy_started_at) - a.game_minutes * bl_cfg('time.real_seconds_per_game_minute')) < 0.05,
                         'game_minutes mode: game_minutes x rate');
  perform pg_temp.assert(bl_shift_seconds(300) = 300 * bl_cfg('time.real_seconds_per_game_minute'), 'game_minutes mode shift');
  update game_config set value = '"short"' where key = 'action.mode';
  perform pg_temp.assert(bl_shift_seconds(300) = bl_cfg('action.shift_seconds'), 'short mode shift = action.shift_seconds');
  -- every seeded activity lasts at most 15 s at worst
  perform pg_temp.assert(not exists (select 1 from activities where max_seconds > 15 or min_seconds > max_seconds), 'all activities <= 15 s');
  -- travel capped
  update profiles set busy_until = null, cash = 100000 where id = v;
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(travel_quote('benin_airport')->'options') o
                                      where (o->>'real_seconds')::numeric > bl_cfg('action.travel_max_seconds')), 'travel <= travel_max_seconds');
  -- shift: action.shift_seconds real seconds (worker from L1-3)
  perform pg_temp.assert(bl_cfg('action.shift_seconds') between 15 and 20, 'shift default 15-20 s');
  -- jail / hospital capped to seconds in short mode, uncapped in game_minutes mode
  update profiles set jailed_until = null, hospitalized_until = null where id = v;
  perform bl_jail(v, 600, 'test');
  select * into me from profiles where id = v;
  perform pg_temp.assert(abs(extract(epoch from me.jailed_until - bl_now()) - bl_cfg('action.jail_max_seconds')) < 0.05,
                         'jail capped to action.jail_max_seconds');
  perform bl_hospitalize(v, 600, 'test');
  select * into me from profiles where id = v;
  perform pg_temp.assert(abs(extract(epoch from me.hospitalized_until - bl_now()) - bl_cfg('action.hospital_max_seconds')) < 0.05,
                         'hospital capped to action.hospital_max_seconds');
  perform pg_temp.assert(bl_status_seconds(10, 'action.jail_max_seconds') = 10 * bl_cfg('time.real_seconds_per_game_minute'),
                         'short stays are not stretched to the cap');
  update game_config set value = '"game_minutes"' where key = 'action.mode';
  perform pg_temp.assert(bl_status_seconds(600, 'action.jail_max_seconds') = 600 * bl_cfg('time.real_seconds_per_game_minute'),
                         'game_minutes mode: uncapped');
  update game_config set value = '"short"' where key = 'action.mode';
  update profiles set jailed_until = null, hospitalized_until = null where id = v;
  -- admin can edit the timing columns
  perform pg_temp.assert(bl_admin_table_spec('activities')->'cols' ?& array['max_seconds','min_seconds','scale_by_need'],
                         'admin whitelist has the activity seconds');
  raise notice 'ok L1-6: action timing';
end $$;

-- ---------- L1-7. transfer limits count the real (WAT) day ----------
do $$
declare v uuid := (select id from t_tu where name = 'worker'); st jsonb;
begin
  perform pg_temp.at(timestamptz '2026-10-07 22:30:00+00');   -- Wed 23:30 WAT
  insert into ledger (user_id, account, delta, balance_after, reason, meta)
  values (v, 'bank', -1000, 0, 'transfer_out', jsonb_build_object('day', (bl_game_clock()->>'day')::int));
  st := bl_transfer_stats(v);
  perform pg_temp.assert((st->>'sent')::bigint = 1000 and (st->>'count')::int = 1, 'counted today: ' || st::text);
  perform pg_temp.at(timestamptz '2026-10-07 23:00:01+00');   -- Thu 00:00 WAT
  st := bl_transfer_stats(v);
  perform pg_temp.assert((st->>'sent')::bigint = 0 and (st->>'count')::int = 0, 'new WAT day resets: ' || st::text);
  perform set_config('bl.test_offset_seconds', '', true);
  raise notice 'ok L1-7: transfer limits on the real day';
end $$;

do $$ begin raise notice 'ALL TIME TESTS PASSED'; end $$;

