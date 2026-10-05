-- Careers tests (V1-3): seeds + config, apply from anywhere, head start (Nepo) capped by requirements,
-- work_shift location/needs refusals, pay + XP scaling with performance and traits, busy label,
-- work_finish settlement, auto-promotion gated by laptop / degree, daily shift cap, quit, config multipliers.
-- Run (migrations applied):  bash scripts/sql-test.sh -- supabase/tests/careers_test.sql
-- Rolled back at the end. Time with bl.test_offset_seconds.

create or replace function pg_temp.c_advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;

create or replace function pg_temp.c_expect_error(p_sql text, p_like text) returns void
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

create temp table t_careers_u (name text primary key, id uuid not null) on commit drop;
create or replace function pg_temp.cu(p_name text) returns uuid
language sql as $$ select id from t_careers_u where name = p_name $$;

-- new logged-in Sim in p_home; p_tier '' = LAPO roll, 'nepo' = forced Nepo
create or replace function pg_temp.c_make(p_name text, p_home text, p_tier text, p_traits text[]) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@careers.bl');
begin
  insert into t_careers_u values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = to_jsonb(p_tier) where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'female', '{"gender":"female"}', p_traits, 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home(p_home);
  return v;
end $$;

-- set needs now (no decay pending), free the Sim and reset today's shift count
create or replace function pg_temp.c_needs(p_uid uuid, h numeric, e numeric, y numeric, s numeric) returns void
language sql as $$
  update profiles set hunger = h, energy = e, hygiene = y, stress = s, fun = 80, social = 80, bladder = 100,
                      needs_updated_at = bl_now(), busy_until = null, busy_label = null, job_shifts_today = 0
   where id = p_uid;
$$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  -- pin the numbers this file asserts (the live DB may hold admin-tuned values; rolled back anyway)
  update game_config set value = '1' where key in ('career.pay_mult', 'career.xp_mult');
  update game_config set value = '0.75' where key = 'time.real_seconds_per_game_minute';
  update game_config set value = '3' where key = 'career.max_shifts_per_game_day';
end $$;

-- ---------- 0. seeds, location, config ----------
do $$
declare n int;
begin
  perform pg_temp.assert((select count(*) from career_tracks where active) = 6, '6 launch tracks');
  perform pg_temp.assert((select count(*) from career_levels where track_id = 'tech') = 7, 'tech has 7 levels');
  perform pg_temp.assert((select title from career_levels where track_id = 'tech' and level = 1) = 'Intern', 'tech starts at Intern');
  perform pg_temp.assert((select title from career_levels where track_id = 'tech' and level = 7) = 'CTO', 'tech tops at CTO');
  perform pg_temp.assert((select xp_to_next from career_levels where track_id = 'tech' and level = 7) is null, 'top level has no xp_to_next');
  select count(*) into n from career_tracks t
   where (select count(*) from career_levels l where l.track_id = t.id) < 4;
  perform pg_temp.assert(n = 0, 'every track has at least 4 levels');
  -- pay rises with level on every track
  select count(*) into n from career_levels a join career_levels b on a.track_id = b.track_id and b.level = a.level + 1
   where b.pay_per_shift <= a.pay_per_shift;
  perform pg_temp.assert(n = 0, 'pay rises every level');
  -- every workplace exists and offers jobs
  select count(*) into n from career_tracks t, unnest(t.location_ids) lid
   where not exists (select 1 from locations l where l.id = lid and 'jobs' = any(l.actions));
  perform pg_temp.assert(n = 0, 'every track location exists with the jobs action');
  perform pg_temp.assert(exists (select 1 from locations where id = 'bronze_tech_hub' and scene = 'office' and x = 535 and y = 190
                                 and district = 'ugbowo' and actions @> '{jobs,activities}'), 'bronze_tech_hub seeded');
  perform pg_temp.assert(exists (select 1 from activities where 'office' = any(scenes)), 'office has activities');
  perform pg_temp.assert((select count(*) from game_config where key like 'career.%' and category = 'career' and label <> '' and description <> '') >= 15,
                         'career config labelled');
  perform pg_temp.assert(bl_cfg('career.max_shifts_per_game_day') = 3, 'daily cap 3');
  raise notice 'ok 0: seeds, location, config';
end $$;

-- ---------- 1. LAPO: apply from anywhere, location rule, pay scales with needs ----------
do $$
declare
  v uuid := pg_temp.c_make('CarLapo', 'ekenwan_face_me', '', '{neat_freak,musical}');
  c jsonb; r jsonb; p profiles; v_cash bigint;
begin
  c := jobs_catalog();
  perform pg_temp.assert(jsonb_array_length(c->'tracks') = 6, 'catalog lists 6 tracks');
  perform pg_temp.assert((select (t->>'entry_level')::int from jsonb_array_elements(c->'tracks') t where t->>'id' = 'tech') = 1,
                         'LAPO enters tech at 1');
  perform pg_temp.c_expect_error('select work_shift()', '%don''t have a job%');
  perform pg_temp.c_expect_error('select job_quit()', '%don''t have a job%');

  r := job_apply('tech');                       -- from Ekenwan: applying works anywhere
  select * into p from profiles where id = v;
  perform pg_temp.assert(p.job_id = 'tech' and p.job_level = 1 and p.job_xp = 0, 'hired as tech intern');
  perform pg_temp.assert(r->>'message' like '%Intern%', 'hire message names the title');
  perform pg_temp.assert(exists (select 1 from events where user_id = v and kind = 'hired'), 'hired event');
  perform pg_temp.c_expect_error('select job_apply(''tech'')', '%already work%');
  perform pg_temp.c_expect_error('select job_apply(''nope'')', '%isn''t hiring%');

  perform pg_temp.c_expect_error('select work_shift()', '%Bronze Tech Hub%');   -- not_here
  update profiles set location_id = 'bronze_tech_hub' where id = v;

  -- refusals from needs
  perform pg_temp.c_needs(v, 100, 5, 100, 0);
  perform pg_temp.c_expect_error('select work_shift()', '%too tired%');
  perform pg_temp.c_needs(v, 5, 100, 100, 0);
  perform pg_temp.c_expect_error('select work_shift()', '%too hungry%');

  -- best needs -> perf 120% -> 3500 * 1.2 = 4200, xp 12
  perform pg_temp.c_needs(v, 100, 100, 100, 0);
  select cash into v_cash from profiles where id = v;
  r := work_shift();
  perform pg_temp.assert((r->>'perf')::int = 120 and (r->>'pay')::bigint = 4200 and (r->>'xp')::int = 12,
                         format('high-needs shift: %s', r));
  select * into p from profiles where id = v;
  perform pg_temp.assert(p.busy_label = 'Working: Intern' and p.busy_until > bl_now(), 'busy with Working: Intern');
  perform pg_temp.assert(p.cash = v_cash, 'not paid until the shift ends');
  perform pg_temp.assert(p.energy < 100 and p.hunger < 100, 'shift costs energy and hunger');
  perform pg_temp.assert((get_my_state()->'career'->'job'->>'title') = 'Intern', 'state career block');
  perform pg_temp.assert((get_my_state()->'career'->'job'->'pending'->>'pay')::bigint = 4200, 'pending shift visible');
  perform pg_temp.c_expect_error('select work_shift()', '%busy%');
  perform pg_temp.c_expect_error('select work_finish()', '%isn''t over%');
  perform pg_temp.c_expect_error('select job_quit()', '%Finish your current shift%');

  perform pg_temp.c_advance(400);
  r := work_finish();
  select * into p from profiles where id = v;
  perform pg_temp.assert(p.cash = v_cash + 4200, 'paid 4200 at the end');
  perform pg_temp.assert(p.job_xp = 12 and p.job_shifts_in_level = 1 and p.job_total_shifts = 1, 'xp + shift counters');
  perform pg_temp.assert(p.job_shift_ends_at is null, 'pending cleared');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'salary' and delta = 4200), 'ledger reason salary');
  perform pg_temp.assert(r->>'message' like 'Shift done!%', 'finish message');
  perform pg_temp.assert(work_finish()->>'message' is null, 'nothing left to collect');

  -- low needs -> score 20 -> perf 56% -> 1960, xp 6
  perform pg_temp.c_needs(v, 20, 20, 20, 80);
  r := work_shift();
  perform pg_temp.assert((r->>'perf')::int = 56 and (r->>'pay')::bigint = 1960 and (r->>'xp')::int = 6,
                         format('low-needs shift: %s', r));
  perform pg_temp.c_advance(400);

  -- auto-settle on the next shift + promotion gated by the laptop
  update profiles set job_xp = 33, job_shifts_in_level = 3 where id = v;   -- + pending 6 -> 39
  perform pg_temp.c_needs(v, 100, 100, 100, 0);
  r := work_shift();                                                         -- settles 1960 first
  perform pg_temp.assert((r->'settled'->>'pay')::bigint = 1960, 'previous shift settled by work_shift');
  perform pg_temp.c_advance(400);
  r := work_finish();                                                        -- 39 + 12 = 51 >= 40, no laptop
  select * into p from profiles where id = v;
  perform pg_temp.assert(p.job_level = 1 and p.job_xp = 40, format('blocked without laptop, xp held at bar: %s/%s', p.job_level, p.job_xp));
  perform pg_temp.assert(r ? 'blocked' and r->>'message' ilike '%laptop%', 'blocked message names the laptop');
  insert into inventory (user_id, item_id, qty) values (v, 'laptop', 1);
  perform pg_temp.c_needs(v, 100, 100, 100, 0);
  perform work_shift();
  perform pg_temp.c_advance(400);
  r := work_finish();
  select * into p from profiles where id = v;
  perform pg_temp.assert(p.job_level = 2 and p.job_xp = 0 and p.job_shifts_in_level = 0, 'promoted to Junior Dev');
  perform pg_temp.assert(r->'promoted'->>'title' = 'Junior Dev' and r->>'message' like '%Promoted to Junior Dev!%', 'promotion result');
  perform pg_temp.assert(exists (select 1 from events where user_id = v and kind = 'promoted' and title = 'Promoted to Junior Dev!'), 'promotion event');
  perform pg_temp.assert((p.career_best->>'tech')::int = 2, 'career_best tracks level');

  -- min_shifts_in_level gate: enough XP but 0 shifts at level 2 -> one shift gives 1/3
  update profiles set job_xp = 69 where id = v;
  perform pg_temp.c_needs(v, 100, 100, 100, 0);
  perform work_shift();
  perform pg_temp.c_advance(400);
  r := work_finish();
  perform pg_temp.assert((select job_level from profiles where id = v) = 2, 'min_shifts_in_level blocks');
  perform pg_temp.assert(r->'blocked'->>'title' = 'Mid-level Dev', 'blocked on shifts');

  -- daily cap
  perform pg_temp.c_needs(v, 100, 100, 100, 0);
  update profiles set job_shift_day = (bl_game_clock()->>'day')::int, job_shifts_today = 3 where id = v;
  perform pg_temp.c_expect_error('select work_shift()', '%3 shifts today%');

  -- config multipliers: pay x2, xp x3
  update game_config set value = '2' where key = 'career.pay_mult';
  update game_config set value = '3' where key = 'career.xp_mult';
  perform pg_temp.c_needs(v, 100, 100, 100, 0);
  r := work_shift();
  perform pg_temp.assert((r->>'pay')::bigint = 19200 and (r->>'xp')::int = 36, format('config multipliers: %s', r));
  update game_config set value = '1' where key in ('career.pay_mult', 'career.xp_mult');
  perform pg_temp.c_advance(400);

  -- quit (settles the finished shift first)
  r := job_quit();
  select * into p from profiles where id = v;
  perform pg_temp.assert(p.job_id is null and r->>'message' like '%resigned%', 'quit');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'salary' and delta = 19200), 'quit settled the last shift');
  perform pg_temp.c_expect_error('select job_quit()', '%don''t have a job%');
  -- rejoin: best 2 - 1 = level 1
  perform job_apply('tech');
  perform pg_temp.assert((select job_level from profiles where id = v) = 1, 'rejoin loses a level');
  raise notice 'ok 1: apply, refusals, pay scaling, settlement, laptop gate, cap, config, quit';
end $$;

-- ---------- 2. Degree gate on Health ----------
do $$
declare v uuid := pg_temp.c_make('CarNurse', 'uniben_hostel', '', '{neat_freak,musical}'); r jsonb; p profiles;
begin
  perform job_apply('health');
  update profiles set location_id = 'ubth', job_level = 2, job_xp = 69, job_shifts_in_level = 3 where id = v;
  perform pg_temp.c_needs(v, 100, 100, 100, 0);
  perform work_shift();
  perform pg_temp.c_advance(400);
  r := work_finish();
  perform pg_temp.assert((select job_level from profiles where id = v) = 2 and r->>'message' ilike '%degree%', 'no degree -> blocked');
  perform pg_temp.assert(not (get_my_state()->'career'->>'degree')::boolean, 'no degree yet');
  update profiles set career_best = career_best || '{"education": 2}' where id = v;
  perform pg_temp.assert((get_my_state()->'career'->>'degree')::boolean, 'education 2 = degree');
  perform pg_temp.c_needs(v, 100, 100, 100, 0);
  perform work_shift();
  perform pg_temp.c_advance(400);
  r := work_finish();
  select * into p from profiles where id = v;
  perform pg_temp.assert(p.job_level = 3 and r->'promoted'->>'title' = 'Staff Nurse', 'degree -> Staff Nurse');
  -- works at Mercy Clinic too, not at the market
  update profiles set location_id = 'oba_market' where id = v;
  perform pg_temp.c_needs(v, 100, 100, 100, 0);
  perform pg_temp.c_expect_error('select work_shift()', '%UBTH%Mercy Clinic%');
  update profiles set location_id = 'mercy_clinic' where id = v;
  perform work_shift();
  perform pg_temp.c_advance(400);
  raise notice 'ok 2: degree gate';
end $$;

-- ---------- 3. Nepo head start, capped by requirements; first job only ----------
do $$
declare v uuid := pg_temp.c_make('CarNepo', 'gra_duplex', 'nepo', '{neat_freak,musical}'); c jsonb;
begin
  perform pg_temp.assert((select origin from profiles where id = v) = 'nepo', 'forced nepo');
  c := jobs_catalog();
  perform pg_temp.assert((select (t->>'entry_level')::int from jsonb_array_elements(c->'tracks') t where t->>'id' = 'tech') = 3,
                         'Nepo with laptop would enter tech at 3');
  perform pg_temp.assert((select (t->>'entry_level')::int from jsonb_array_elements(c->'tracks') t where t->>'id' = 'health') = 2,
                         'Nepo without degree capped at Student Nurse');
  perform job_apply('health');
  perform pg_temp.assert((select job_level from profiles where id = v) = 2, 'hired as Student Nurse');
  perform job_apply('tech');                            -- switch: head start was for the first job only
  perform pg_temp.assert((select job_id || job_level from profiles where id = v) = 'tech1', 'second job starts at 1');
  update game_config set value = 'false' where key = 'career.head_start_first_job_only';
  perform job_apply('trade');
  perform pg_temp.assert((select job_level from profiles where id = v) = 3, 'head start every job when the key is off');
  update game_config set value = 'true' where key = 'career.head_start_first_job_only';
  raise notice 'ok 3: Nepo head start';
end $$;

-- ---------- 4. Trait multipliers (Hustler: work_pay 1.05, skill_xp hustle 1.25) ----------
do $$
declare v uuid := pg_temp.c_make('CarHustle', 'aduwawa_face_me', '', '{hustler,foodie}'); r jsonb;
begin
  perform job_apply('pos');
  update profiles set location_id = 'ring_road_pos' where id = v;
  perform pg_temp.c_needs(v, 100, 100, 100, 0);
  perform pg_temp.assert((get_my_state()->'career'->'job'->>'pay_now')::bigint = 3150, 'pay_now preview matches');
  r := work_shift();      -- 2500 * 1.2 * 1.05 = 3150 ; xp 10 * 1.2 * 1.25 = 15
  perform pg_temp.assert((r->>'pay')::bigint = 3150 and (r->>'xp')::int = 15, format('hustler multipliers: %s', r));
  perform pg_temp.assert((select busy_label from profiles where id = v) = 'Working: PoS Attendant', 'pos busy label');
  -- lazy bone performance malus
  update profiles set traits = '{lazy_bone,musical}' where id = v;
  perform pg_temp.c_needs(v, 100, 100, 100, 0);
  perform pg_temp.assert(bl_career_perf((select p from profiles p where id = v)) = 108, 'work_performance 0.9');
  raise notice 'ok 4: traits';
end $$;

-- ---------- 5. privileges ----------
do $$
begin
  perform pg_temp.assert(not has_function_privilege('anon', 'public.work_shift()', 'execute'), 'anon cannot work');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.work_shift()', 'execute'), 'authenticated can work');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_settle_shift(uuid)', 'execute'), 'helper revoked');
  perform pg_temp.assert(has_table_privilege('anon', 'public.career_levels', 'select'), 'levels readable');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.career_levels', 'insert'), 'no client writes');
  raise notice 'ok 5: privileges';
  raise notice 'ALL CAREERS TESTS PASSED';
end $$;
