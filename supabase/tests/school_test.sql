-- R4 School and certificates (20261018000100_school.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/school_test.sql
-- Time moves with bl.test_offset_seconds (classes run 8 AM to 5 PM Benin time, clubs open at night); rolls are pinned with bl.test_rand.
-- Groups: 1 grants + RLS + helpers private · 2 seeds and defaults · 3 enrol and pay (prerequisites, money, fee multiplier) · 4 a class at the wrong
-- place / hours / not enrolled is refused · 5 a class: busy timer, energy, XP, progress, missed days keep progress · 6 cooldown (one class per game
-- day, multiplier) · 7 graduation: certificate, event, re-enrol refused · 8 exam with forced rolls (fail = retake, pass = certificate, chance rises with
-- the skill level) · 9 career gates (level, track, degree via BSc) · 10 hustle gate + Yahoo gate · 11 pay bonus (hustle and career shift) · 12 admin grant,
-- revoke and audit · 13 place cards · 14 public profile · 15 master switch.
create or replace function pg_temp.hint_of(p_sql text) returns text
language plpgsql as $$
declare v_h text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  get stacked diagnostics v_h = pg_exception_hint;
  return coalesce(nullif(v_h, ''), sqlerrm);
end $$;

create or replace function pg_temp.msg_of(p_sql text) returns text
language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  return sqlerrm;
end $$;

create or replace function pg_temp.advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;

-- jump forward to the NEXT time the Benin clock reads p_h
create or replace function pg_temp.to_hour(p_h numeric) returns void
language plpgsql as $$
declare v_local timestamp := bl_now() at time zone 'Africa/Lagos'; v_t timestamp;
begin
  v_t := date_trunc('day', v_local) + make_interval(hours => floor(p_h)::int, mins => round((p_h - floor(p_h)) * 60)::int);
  if v_t <= v_local then v_t := v_t + interval '1 day'; end if;
  perform pg_temp.advance(extract(epoch from (v_t - v_local)));
end $$;

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.u(p_name text) returns uuid
language sql as $$ select current_setting('r4.' || p_name)::uuid; $$;

create or replace function pg_temp.xp(p_uid uuid, p_skill text) returns int
language sql as $$ select coalesce((select xp from player_skills where user_id = p_uid and skill_id = p_skill), 0); $$;

create or replace function pg_temp.setxp(p_uid uuid, p_skill text, p_xp int) returns void
language sql as $$
  insert into player_skills (user_id, skill_id, xp) values (p_uid, p_skill, p_xp)
  on conflict (user_id, skill_id) do update set xp = excluded.xp;
$$;

create or replace function pg_temp.at(p_uid uuid, p_loc text default null) returns void
language sql as $$
  update profiles set location_id = coalesce(p_loc, home_location_id), travel_to = null, travel_mode = null, travel_started_at = null,
                      travel_arrives_at = null, busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = now(), rent_due_at = null, energy = 100, hunger = 100, hygiene = 100, stress = 0, needs_updated_at = bl_now()
   where id = p_uid;
$$;

create or replace function pg_temp.has_cert(p_uid uuid, p_cert text) returns boolean
language sql as $$ select exists (select 1 from player_certificates where user_id = p_uid and cert_id = p_cert); $$;

create or replace function pg_temp.done(p_uid uuid, p_course text) returns int
language sql as $$ select coalesce((select classes_done from course_enrolments where user_id = p_uid and course_id = p_course), 0); $$;

-- one class: start, wait out the timer, finish with a pinned roll
create or replace function pg_temp.cls(p_uid uuid, p_id text, p_rand text default '0.0') returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.login(p_uid);
  update profiles set energy = 100, hunger = 100, hygiene = 100, stress = 0, needs_updated_at = bl_now() where id = p_uid;
  perform set_config('bl.test_rand', '', true);
  v := course_start_class(p_id);
  perform pg_temp.advance((v->>'seconds')::numeric + 1);
  perform set_config('bl.test_rand', p_rand, true);
  v := course_finish_class();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.advance(5);
  return v;
end $$;

create or replace function pg_temp.start_hint(p_uid uuid, p_id text) returns text
language plpgsql as $$
begin
  perform pg_temp.login(p_uid);
  perform set_config('bl.test_rand', '', true);
  update profiles set energy = greatest(energy, 100) where id = p_uid;
  return pg_temp.hint_of(format('select course_start_class(%L)', p_id));
end $$;

create or replace function pg_temp.course(p_uid uuid, p_id text) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.login(p_uid);
  v := course_status();
  return (select x from jsonb_array_elements(v->'courses') x where x->>'id' = p_id);
end $$;

-- complete a whole course quickly (no cooldown, a pinned pass)
create or replace function pg_temp.graduate(p_uid uuid, p_course text) returns void
language plpgsql as $$
declare n int; i int;
begin
  perform pg_temp.login(p_uid);
  perform pg_temp.cfg('school.cooldown_mult', '0');
  perform course_enrol(p_course);
  select classes into n from courses where id = p_course;
  for i in 1..n loop perform pg_temp.cls(p_uid, p_course, '0.0'); end loop;
  perform pg_temp.cfg('school.cooldown_mult', '1');
end $$;

-- Yahoo: only this laptop, MiFi on, at home, no case
create or replace function pg_temp.ysetup(p_uid uuid, p_laptop text) returns void
language plpgsql as $$
begin
  delete from inventory where user_id = p_uid and item_id in (select item_id from laptop_specs);
  perform bl_give_item(p_uid, p_laptop, 1);
  delete from jail_cases where user_id = p_uid;
  perform pg_temp.at(p_uid);
  perform bl_yahoo_row(p_uid);
  update yahoo_players set mifi_until = bl_now() + interval '3 days' where user_id = p_uid;
end $$;

-- ---------- setup ----------
do $$
declare
  v_names text[] := array['adm', 'a', 'b', 'c', 'd', 'e', 'f'];
  n text; u uuid;
begin
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  foreach n in array v_names loop
    u := pg_temp.new_user('r4_' || n || '@rr.bl');
    perform set_config('r4.' || n, u::text, true);
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    perform pg_temp.login(u);
    perform create_profile_v2('R4_' || upper(n), 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home('ekenwan_face_me');
    perform pg_temp.at(u);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
  update profiles set created_at = now() - interval '30 days', protected_until = null, cash = 500000, bank = 0, traits = '{}'
   where username like 'R4\_%';
  delete from inventory where user_id in (select id from profiles where username like 'R4\_%');
  perform pg_temp.cfg('school.enabled', 'true');
  perform pg_temp.cfg('school.fee_mult', '1');
  perform pg_temp.cfg('school.cooldown_mult', '1');
  perform pg_temp.cfg('school.degree_cert', '"bsc"');
  perform pg_temp.cfg('skills.enabled', 'true');
  perform pg_temp.cfg('skills.xp_mult', '1');
  perform pg_temp.cfg('hustles.enabled', 'true');
  perform pg_temp.cfg('hustles.min_energy', '10');
  perform pg_temp.cfg('places.hours_enabled', 'true');
  perform pg_temp.cfg('yahoo.enabled', 'true');
  perform pg_temp.cfg('yahoo.caught_floor_pct', '0');
  perform pg_temp.cfg('club.weekend_price_mult', '1');
  update hustles set active = true;
  update yahoo_jobs set active = true;
end $$;

-- ---------- 1. grants + RLS ----------
do $$
declare v_rpc text; a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); v_n int;
begin
  foreach v_rpc in array array['course_status()', 'course_enrol(text)', 'course_start_class(text)', 'course_finish_class()',
                               'admin_player_certs(uuid)', 'admin_grant_cert(uuid,text,text)', 'admin_revoke_cert(uuid,text,text)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'auth may ' || v_rpc);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v_rpc)::regprocedure), 'secdef ' || v_rpc);
  end loop;
  foreach v_rpc in array array['bl_school_on()', 'bl_school_num(text,numeric)', 'bl_cert_ids(text)', 'bl_cert_has(uuid,text)', 'bl_cert_need_text(text)',
                               'bl_cert_gate(uuid,text)', 'bl_cert_bonus_pct(uuid,text,text)', 'bl_cert_pay_mult(uuid,text,text)', 'bl_cert_degree(uuid)',
                               'bl_cert_list(uuid)', 'bl_career_lreq(jsonb,text)', 'bl_cert_unlocks(text)', 'bl_course_secs_to_next_day()',
                               'bl_course_wait_seconds(bigint,integer)', 'bl_course_wait_label(integer)', 'bl_course_window_label(public.courses)',
                               'bl_course_fee(public.courses)', 'bl_course_at(public.courses,public.locations)', 'bl_course_exam_chance(uuid,public.courses)',
                               'bl_course_module(public.courses,integer)', 'bl_course_enrol_why(public.profiles,public.courses)',
                               'bl_course_why(public.profiles,public.courses,public.locations,boolean)', 'bl_course_run_json(public.course_runs)',
                               'bl_course_json(public.profiles,public.courses,public.locations)',
                               'bl_course_card(public.profiles,public.courses,public.locations,text,text,text)',
                               'bl_cert_award(uuid,text,text,text)', 'bl_course_resolve(bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'helper private ' || v_rpc);
  end loop;
  -- the patched live functions kept their grants
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.place_interior(text)'::regprocedure, 'execute')
                         and has_function_privilege('authenticated', 'public.jobs_catalog()'::regprocedure, 'execute')
                         and has_function_privilege('authenticated', 'public.job_apply(text)'::regprocedure, 'execute')
                         and has_function_privilege('authenticated', 'public.work_shift()'::regprocedure, 'execute')
                         and has_function_privilege('authenticated', 'public.get_public_profile(uuid)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_hustle_why(public.profiles,public.hustles,public.locations,boolean)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_skill_award(uuid,text,text)'::regprocedure, 'execute'), 'patched functions keep grants');
  perform pg_temp.assert(not has_table_privilege('anon', 'public.player_certificates', 'select')
                         and not has_table_privilege('anon', 'public.course_enrolments', 'select')
                         and not has_table_privilege('anon', 'public.courses', 'select'), 'anon reads nothing');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.player_certificates', 'insert')
                         and not has_table_privilege('authenticated', 'public.player_certificates', 'delete')
                         and not has_table_privilege('authenticated', 'public.course_enrolments', 'update')
                         and not has_table_privilege('authenticated', 'public.course_enrolments', 'insert')
                         and not has_table_privilege('authenticated', 'public.course_runs', 'update')
                         and not has_table_privilege('authenticated', 'public.courses', 'update')
                         and not has_table_privilege('authenticated', 'public.certificates', 'update'), 'no client writes');
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.courses', 'select')
                         and has_table_privilege('authenticated', 'public.certificates', 'select'), 'catalogues readable');
  -- RLS: my own rows only
  insert into player_certificates (user_id, cert_id) values (a, 'ict');
  insert into course_enrolments (user_id, course_id) values (a, 'ict_basics');
  perform pg_temp.login(b);
  set local role authenticated;
  select count(*) into v_n from player_certificates where user_id = a;
  perform pg_temp.assert(v_n = 0, 'b cannot see a''s certificates (RLS)');
  select count(*) into v_n from course_enrolments where user_id = a;
  perform pg_temp.assert(v_n = 0, 'b cannot see a''s enrolments (RLS)');
  perform pg_temp.login(a);
  select count(*) into v_n from player_certificates where user_id = a;
  perform pg_temp.assert(v_n = 1, 'a sees own certificate');
  reset role;
  delete from player_certificates where user_id = a;
  delete from course_enrolments where user_id = a;
  raise notice 'ok 1: grants / RLS / helpers private';
end $$;

-- ---------- 2. seeds and defaults ----------
do $$
begin
  perform pg_temp.assert((select count(*) from courses) = 10 and (select count(*) from certificates) = 10, 'ten courses, ten certificates');
  perform pg_temp.assert((select count(*) from courses where cert_id is null) = 0, 'every course awards a certificate');
  perform pg_temp.assert((select count(*) from courses where classes >= 4 and fee > 0 and class_seconds >= 1) = 10, 'fees and classes set');
  perform pg_temp.assert((select cardinality(modules) from courses where id = 'uniben_bsc') = 4 and (select classes from courses where id = 'uniben_bsc') = 12, 'BSc: 12 classes in 4 modules');
  perform pg_temp.assert((select count(*) from courses where exam) >= 5, 'several courses have an exam');
  perform pg_temp.assert((select prereq_cert from courses where id = 'digital_marketing') = 'ict'
                         and (select prereq_skill from courses where id = 'accounting') = 'business', 'prerequisites: a certificate and a skill level');
  perform pg_temp.assert((select count(*) from zone_actions where kind = 'class') = 10, 'ten class cards at places');
  perform pg_temp.assert((select req_cert from career_levels where track_id = 'tech' and level = 4) = 'ict,coding_bootcamp'
                         and (select req_cert from career_levels where track_id = 'pos' and level = 4) = 'accounting'
                         and (select req_cert from career_levels where track_id = 'trade' and level = 4) = 'business_mgmt'
                         and (select req_cert from career_levels where track_id = 'transport' and level = 2) = 'driving', 'four career levels gated');
  perform pg_temp.assert((select count(*) from career_levels where req_cert is not null) = 4 and (select count(*) from career_tracks where req_cert is not null) = 0, 'only those gated');
  perform pg_temp.assert((select count(*) from hustles where req_cert is not null) = 2
                         and (select req_cert from hustles where id = 'dj_headline') = 'music_production'
                         and (select req_cert from hustles where id = 'mech_fleet') = 'mechanic_trade', 'two new hustles gated, the old ones stay open');
  perform pg_temp.assert((select count(*) from yahoo_jobs where req_cert is not null) = 0, 'no Yahoo job gated by default');
  perform pg_temp.assert((select req_cert from hustles where id = 'dj_set') is null and (select pay_min from hustles where id = 'dj_headline') > (select pay_min from hustles where id = 'dj_set'),
                         'headline slot pays better than the open warm-up');
  perform pg_temp.assert(exists (select 1 from zone_actions where id = 'club.dj.dj_headline') and exists (select 1 from zone_actions where id = 'mechanic_village.bay.mech_fleet'), 'new hustle cards placed');
  perform pg_temp.assert((select count(*) from game_config where category = 'school') = 6, 'six school settings');
  perform pg_temp.assert((select pay_bonus_pct from certificates where id = 'music_production') = 10, 'cert pay bonus is data');
  -- a zone card with a missing course is refused
  perform pg_temp.assert(pg_temp.hint_of('insert into zone_actions (id, zone_id, kind, ref) values (''x.bad'', ''campus.lecture'', ''class'', ''nope'')') = 'bad_value', 'zone check: unknown course refused');
  raise notice 'ok 2: seeds';
end $$;

-- ---------- 3. enrol and pay ----------
do $$
declare a uuid := pg_temp.u('a'); c uuid := pg_temp.u('c'); v jsonb; v_cash bigint; v_ledger text;
begin
  perform pg_temp.cfg('school.cooldown_mult', '1');
  perform pg_temp.at(a, 'uniben');
  perform pg_temp.login(a);
  v_cash := (select cash from profiles where id = a);
  v := course_enrol('ict_basics');
  perform pg_temp.assert((v->>'paid')::bigint = 12000, 'paid the fee');
  perform pg_temp.assert((select cash from profiles where id = a) = v_cash - 12000, 'cash dropped by the fee');
  perform pg_temp.assert((select status from course_enrolments where user_id = a and course_id = 'ict_basics') = 'enrolled'
                         and pg_temp.done(a, 'ict_basics') = 0, 'enrolled, 0 classes');
  select label into v_ledger from (select bl_ledger_label(reason, meta) as label from ledger where user_id = a and reason = 'course_fee' order by id desc limit 1) q;
  perform pg_temp.assert(v_ledger = 'Course fee: Computer Basics / ICT', 'ledger label (got ' || coalesce(v_ledger, 'null') || ')');
  perform pg_temp.assert(pg_temp.hint_of('select course_enrol(''ict_basics'')') = 'already', 'enrolling twice refused');
  -- prerequisites
  perform pg_temp.assert(pg_temp.hint_of('select course_enrol(''business_mgmt'')') = 'prereq', 'Business Management needs Accounting first');
  perform pg_temp.assert(pg_temp.msg_of('select course_enrol(''digital_marketing'')') like '%ICT certificate%first%', 'prereq message names the certificate (digital marketing needs ICT)');
  perform pg_temp.assert(pg_temp.hint_of('select course_enrol(''accounting'')') = 'prereq', 'Accounting needs Business level 2');
  perform pg_temp.assert(pg_temp.msg_of('select course_enrol(''accounting'')') like 'Needs Business level 2%', 'skill prereq message');
  perform pg_temp.setxp(a, 'business', 40);
  perform pg_temp.assert(pg_temp.hint_of('select course_enrol(''accounting'')') = 'ok', 'Business level 2 opens Accounting');
  -- no money
  perform pg_temp.login(c);
  update profiles set cash = 5000, bank = 1000 where id = c;
  perform pg_temp.assert(pg_temp.hint_of('select course_enrol(''ict_basics'')') = 'not_enough_money', 'broke players cannot enrol');
  perform pg_temp.assert((select count(*) from course_enrolments where user_id = c) = 0, 'nothing written on a refusal');
  -- cash first, then bank
  update profiles set cash = 4000, bank = 20000 where id = c;
  perform course_enrol('ict_basics');
  perform pg_temp.assert((select cash from profiles where id = c) = 0 and (select bank from profiles where id = c) = 12000, 'cash first then bank');
  -- the fee multiplier is admin-tunable
  perform pg_temp.cfg('school.fee_mult', '0.5');
  perform pg_temp.assert((pg_temp.course(a, 'ict_basics')->>'fee')::bigint = 6000, 'card shows the half-price fee');
  update profiles set cash = 100000 where id = a;
  perform pg_temp.login(a);
  perform pg_temp.assert((course_enrol('catering')->>'paid')::bigint = 10000, 'half fee charged');
  perform pg_temp.cfg('school.fee_mult', '1');
  perform pg_temp.assert(pg_temp.hint_of('select course_enrol(''nope'')') = 'bad_course', 'unknown course');
  raise notice 'ok 3: enrol and pay';
end $$;

-- ---------- 4. wrong place / hours / not enrolled ----------
do $$
declare a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b');
begin
  perform pg_temp.to_hour(10);
  -- not enrolled
  perform pg_temp.at(b, 'uniben');
  perform pg_temp.assert(pg_temp.start_hint(b, 'ict_basics') = 'not_enrolled', 'a class without enrolling is refused');
  -- wrong place (enrolled in ICT, standing at home / at another place)
  perform pg_temp.at(a);
  perform pg_temp.assert(pg_temp.start_hint(a, 'ict_basics') = 'wrong_place', 'class at home refused (wrong place)');
  perform pg_temp.assert(pg_temp.msg_of('select course_start_class(''ict_basics'')') like '%UNIBEN Ugbowo Campus%', 'message names where the class is');
  perform pg_temp.at(a, 'bronze_tech_hub');
  perform pg_temp.assert(pg_temp.start_hint(a, 'ict_basics') = 'wrong_place', 'ICT is not taught at the tech hub');
  -- outside the 8 AM to 5 PM window
  perform pg_temp.at(a, 'uniben');
  perform pg_temp.to_hour(20);
  perform pg_temp.assert(pg_temp.start_hint(a, 'ict_basics') = 'wrong_hours', 'class at 8 PM refused (UNIBEN classes 8 AM to 5 PM)');
  perform pg_temp.to_hour(7.5);
  perform pg_temp.assert(pg_temp.start_hint(a, 'ict_basics') = 'wrong_hours', 'class at 7:30 AM refused');
  perform pg_temp.to_hour(10);
  -- too tired
  update profiles set energy = 5 where id = a;
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of('select course_start_class(''ict_basics'')') = 'too_tired', 'too tired');
  -- a motor park for the driving school (scene based place)
  perform pg_temp.at(b, 'ramat_park');
  perform pg_temp.login(b);
  update profiles set cash = 100000 where id = b;
  perform course_enrol('driving_school');
  perform pg_temp.assert(pg_temp.start_hint(b, 'driving_school') = 'ok', 'driving school class works at any motor park');
  perform pg_temp.advance(40);
  perform pg_temp.login(b);
  perform course_finish_class();
  perform pg_temp.assert(pg_temp.done(b, 'driving_school') = 1 and pg_temp.xp(b, 'driving') = 8, 'driving school: 1 class, 8 Driving XP');
  raise notice 'ok 4: place, hours, enrolment';
end $$;

-- ---------- 5. a class: timer, energy, XP, progress ----------
do $$
declare a uuid := pg_temp.u('a'); v jsonb; v_e0 numeric; v_xp0 int; v_run int;
begin
  perform pg_temp.at(a, 'uniben');
  perform pg_temp.to_hour(10);
  perform pg_temp.login(a);
  perform pg_temp.cfg('school.cooldown_mult', '0');
  v_e0 := (select energy from profiles where id = a);
  v_xp0 := pg_temp.xp(a, 'yahoo');
  v := course_start_class('ict_basics');
  perform pg_temp.assert((v->>'class_no')::int = 1 and (v->>'classes')::int = 4 and (v->>'seconds')::int = 30, 'class 1 of 4, 30 seconds');
  perform pg_temp.assert((select busy_label from profiles where id = a) = 'Class: Computer Basics / ICT', 'busy label');
  perform pg_temp.assert((select energy from profiles where id = a) <= v_e0 - 10, 'class costs energy (got ' || (select energy from profiles where id = a) || ')');
  perform pg_temp.assert(pg_temp.hint_of('select course_start_class(''ict_basics'')') = 'busy', 'cannot start a second class while one runs');
  perform pg_temp.assert(pg_temp.hint_of('select activity_stop()') = 'not_stoppable', 'a class cannot be stopped');
  perform pg_temp.assert(pg_temp.hint_of('select course_finish_class()') = 'not_yet', 'cannot finish early');
  perform pg_temp.assert((course_status()->'run'->>'class_no')::int = 1, 'status shows the running class');
  perform pg_temp.advance(31);
  v := course_finish_class();
  perform pg_temp.assert(v->>'outcome' = 'ok' and (v->>'done')::int = 1, 'class 1 done');
  perform pg_temp.assert((v->>'xp')::int = 8 and pg_temp.xp(a, 'yahoo') = v_xp0 + 8, 'ICT gives 8 Yahoo (IT) XP per class (got ' || (v->>'xp') || ')');
  perform pg_temp.assert(pg_temp.done(a, 'ict_basics') = 1, 'progress saved');
  perform pg_temp.assert((select busy_label from profiles where id = a) is null, 'busy cleared');
  perform pg_temp.assert(pg_temp.hint_of('select course_finish_class()') = 'no_run', 'no class running now');
  -- the status settles an overdue class by itself (reload while away)
  perform pg_temp.advance(5);
  perform course_start_class('ict_basics');
  perform pg_temp.advance(300);
  v := course_status();
  perform pg_temp.assert((v->'resolved'->>'done')::int = 2 and v->'run' = 'null'::jsonb, 'overdue class settled by course_status');
  perform pg_temp.assert(pg_temp.done(a, 'ict_basics') = 2, 'progress 2 after the settle');
  -- missing days never resets progress
  perform pg_temp.advance(86400 * 6);
  perform pg_temp.assert(pg_temp.done(a, 'ict_basics') = 2, 'six days away: still 2 of 4');
  perform pg_temp.to_hour(10);
  v := pg_temp.cls(a, 'ict_basics');
  perform pg_temp.assert((v->>'done')::int = 3, 'back after a week: class 3 (progress kept)');
  -- XP stays 0 when the skill is off
  perform pg_temp.cfg('skills.enabled', 'false');
  perform pg_temp.at(pg_temp.u('b'), 'ramat_park');
  v := pg_temp.cls(pg_temp.u('b'), 'driving_school');
  perform pg_temp.assert((v->>'xp')::int = 0 and pg_temp.xp(pg_temp.u('b'), 'driving') = 8 and (v->>'done')::int = 2, 'skills off: the class counts, no XP');
  perform pg_temp.cfg('skills.enabled', 'true');
  v := pg_temp.cls(pg_temp.u('b'), 'driving_school');
  perform pg_temp.assert((v->>'xp')::int = 8 and pg_temp.xp(pg_temp.u('b'), 'driving') = 16 and (v->>'done')::int = 3, 'driving school gives 8 Driving XP per class');
  perform pg_temp.cfg('school.cooldown_mult', '1');
  raise notice 'ok 5: class';
end $$;

-- ---------- 6. cooldown ----------
do $$
declare d uuid := pg_temp.u('d'); v jsonb; v_h text;
begin
  perform pg_temp.at(d, 'uniben');
  perform pg_temp.to_hour(10);
  perform pg_temp.login(d);
  perform course_enrol('ict_basics');
  perform pg_temp.cfg('school.cooldown_mult', '1');
  v := pg_temp.cls(d, 'ict_basics');
  perform pg_temp.assert((v->>'done')::int = 1, 'first class');
  perform pg_temp.assert(pg_temp.start_hint(d, 'ict_basics') = 'cooldown', 'a second class the same game day is refused');
  perform pg_temp.assert(pg_temp.msg_of('select course_start_class(''ict_basics'')') like 'One class at a time%progress is safe%', 'friendly cooldown message');
  v := pg_temp.course(d, 'ict_basics');
  perform pg_temp.assert((v->>'wait_seconds')::int > 0 and (v->>'wait_seconds')::int <= 86400, 'card shows the wait');
  perform pg_temp.assert(v->>'next_class_at' is not null and v->'locked'->>'hint' = 'cooldown', 'card: next class time and the cooldown lock');
  perform pg_temp.assert((v->>'here')::boolean is false, 'not "here" while cooling down');
  -- the next game day (Benin midnight) frees it
  perform pg_temp.to_hour(9);
  perform pg_temp.to_hour(10);
  perform pg_temp.assert(pg_temp.start_hint(d, 'ict_basics') = 'ok', 'next game day: ready again');
  perform pg_temp.advance(40);
  perform pg_temp.login(d);
  perform course_finish_class();
  -- the multiplier: 0 = no wait, 2 = two days
  perform pg_temp.cfg('school.cooldown_mult', '0');
  perform pg_temp.assert(pg_temp.start_hint(d, 'ict_basics') = 'ok', 'multiplier 0: no wait');
  perform pg_temp.advance(40);
  perform pg_temp.login(d);
  perform course_finish_class();
  perform pg_temp.cfg('school.cooldown_mult', '2');
  perform pg_temp.assert(pg_temp.course(d, 'ict_basics')->>'cooldown_days' = '2', 'card shows 2 days');
  perform pg_temp.cfg('school.cooldown_mult', '1');
  raise notice 'ok 6: cooldown';
end $$;

-- ---------- 7. graduation ----------
do $$
declare a uuid := pg_temp.u('a'); v jsonb; v_ev events;
begin
  perform pg_temp.at(a, 'uniben');
  perform pg_temp.to_hour(10);
  perform pg_temp.cfg('school.cooldown_mult', '0');
  perform pg_temp.assert(pg_temp.done(a, 'ict_basics') = 4 or pg_temp.done(a, 'ict_basics') = 3, 'a is on the last class (' || pg_temp.done(a, 'ict_basics') || ')');
  perform pg_temp.assert(not pg_temp.has_cert(a, 'ict'), 'no certificate before the last class');
  v := pg_temp.cls(a, 'ict_basics');
  perform pg_temp.assert(v->'graduated'->>'cert' = 'ict' and (v->'graduated'->>'new')::boolean, 'graduated: ICT');
  perform pg_temp.assert(pg_temp.has_cert(a, 'ict'), 'certificate row exists');
  perform pg_temp.assert((select source from player_certificates where user_id = a and cert_id = 'ict') = 'course', 'source = course');
  perform pg_temp.assert((select status from course_enrolments where user_id = a and course_id = 'ict_basics') = 'completed', 'enrolment completed');
  select * into v_ev from events where user_id = a and kind = 'graduated' order by id desc limit 1;
  perform pg_temp.assert(v_ev.id is not null and v_ev.title like '%ICT certificate!%', 'graduated event (the toast + confetti)');
  perform pg_temp.assert(v_ev.body like '%Senior Dev%', 'event lists what it unlocks: ' || v_ev.body);
  perform pg_temp.assert(v_ev.data->>'cert' = 'ict', 'event data');
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.course(a, 'ict_basics')->>'state' = 'completed', 'status: completed');
  perform pg_temp.assert(pg_temp.hint_of('select course_enrol(''ict_basics'')') = 'have_cert', 're-enrol refused (already certified)');
  perform pg_temp.assert(pg_temp.start_hint(a, 'ict_basics') <> 'ok', 'no more classes after graduating');
  -- a finished course shows the certificates in course_status
  perform pg_temp.assert(jsonb_array_length(course_status()->'certificates') = 1, 'certificates listed');
  -- Digital Marketing now opens (ICT prerequisite)
  update profiles set cash = 100000 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select course_enrol(''digital_marketing'')') = 'ok', 'ICT opens Digital Marketing');
  -- XP went through bl_skill_award: a level-up wrote a skill_up event once the curve was crossed
  perform pg_temp.assert(pg_temp.xp(a, 'yahoo') >= 8, 'XP in the course skill');
  -- BSc: module name follows the class number
  perform pg_temp.assert(bl_course_module((select c from courses c where id = 'uniben_bsc'), 1) = 'Year 1: Foundations'
                         and bl_course_module((select c from courses c where id = 'uniben_bsc'), 12) = 'Year 4: Project and finals'
                         and bl_course_module((select c from courses c where id = 'uniben_bsc'), 4) = 'Year 2: Core courses', 'BSc modules by class number');
  perform pg_temp.cfg('school.cooldown_mult', '1');
  raise notice 'ok 7: graduation';
end $$;

-- ---------- 8. exams with forced rolls ----------
do $$
declare e uuid := pg_temp.u('e'); v jsonb; v_chance numeric; i int; v_xp int; v_fails int;
begin
  perform pg_temp.at(e, 'uniben');
  perform pg_temp.to_hour(10);
  perform pg_temp.cfg('school.cooldown_mult', '0');
  perform pg_temp.login(e);
  update profiles set cash = 500000 where id = e;
  perform pg_temp.setxp(e, 'business', 40);   -- Business level 2: opens Accounting; exam 45 + 7 per level above 1 = 52 %
  perform course_enrol('accounting');
  v := pg_temp.course(e, 'accounting');
  perform pg_temp.assert((v->'exam'->>'chance_now')::numeric = 52, 'exam chance at Business level 2 = 52 (got ' || (v->'exam'->>'chance_now') || ')');
  for i in 1..5 loop
    v := pg_temp.cls(e, 'accounting', '0.99');   -- the roll is only used on the final class
    perform pg_temp.assert(v->>'outcome' = 'ok', 'class ' || i || ' is a normal class');
  end loop;
  perform pg_temp.assert(pg_temp.done(e, 'accounting') = 5, '5 of 6 done');
  perform pg_temp.assert((pg_temp.course(e, 'accounting')->>'final_next')::boolean, 'the next class is the exam');
  v_xp := pg_temp.xp(e, 'business');
  -- the exam is rolled against 52 %: 99 fails
  v := pg_temp.cls(e, 'accounting', '0.99');
  perform pg_temp.assert(v->>'outcome' = 'fail' and (v->>'done')::int = 5, 'exam failed: still 5 of 6 (retake that class)');
  perform pg_temp.assert(not pg_temp.has_cert(e, 'accounting'), 'no certificate on a fail');
  perform pg_temp.assert(pg_temp.xp(e, 'business') = v_xp and (v->>'xp')::int = 0, 'no XP on a failed exam');
  perform pg_temp.assert(v->>'message' like '%Retake the final class%progress dey safe%', 'friendly fail message');
  select exam_fails into v_fails from course_enrolments where user_id = e and course_id = 'accounting';
  perform pg_temp.assert(v_fails = 1 and (pg_temp.course(e, 'accounting')->'exam'->>'fails')::int = 1, 'fail counted');
  perform pg_temp.assert((select status from course_enrolments where user_id = e and course_id = 'accounting') = 'enrolled', 'still enrolled');
  -- a roll just under the chance passes (51 < 52), a roll at 52 or more fails
  v := pg_temp.cls(e, 'accounting', '0.52');
  perform pg_temp.assert(v->>'outcome' = 'fail', '52 vs a 52 % chance fails (needs strictly under)');
  v := pg_temp.cls(e, 'accounting', '0.51');
  perform pg_temp.assert(v->>'outcome' = 'pass' and (v->>'done')::int = 6, 'a 51 roll passes the exam');
  perform pg_temp.assert(pg_temp.has_cert(e, 'accounting') and v->'graduated'->>'cert' = 'accounting', 'accounting certificate awarded on the pass');
  perform pg_temp.assert(v->>'message' like 'You passed the exam!%', 'pass message');
  -- the chance rises with the skill level and is clamped
  perform pg_temp.setxp(e, 'business', 0);
  perform pg_temp.assert(bl_course_exam_chance(e, (select c from courses c where id = 'accounting')) = 45, 'level 1: 45 %');
  perform pg_temp.setxp(e, 'business', 460);
  perform pg_temp.assert(bl_course_exam_chance(e, (select c from courses c where id = 'accounting')) = 45 + 7 * 4, 'level 5: 73 %');
  perform pg_temp.setxp(e, 'business', 3300);
  perform pg_temp.assert(bl_course_exam_chance(e, (select c from courses c where id = 'accounting')) = 95, 'level 10 is clamped to the cap (95)');
  perform pg_temp.cfg('school.exam_cap_pct', '80');
  perform pg_temp.assert(bl_course_exam_chance(e, (select c from courses c where id = 'accounting')) = 80, 'cap is admin-tunable');
  perform pg_temp.cfg('school.exam_cap_pct', '95');
  perform pg_temp.setxp(e, 'business', 0);
  update courses set exam_base_pct = 0, exam_per_level_pct = 0 where id = 'accounting';
  perform pg_temp.assert(bl_course_exam_chance(e, (select c from courses c where id = 'accounting')) = 5, 'floor is admin-tunable (5)');
  update courses set exam_base_pct = 45, exam_per_level_pct = 7 where id = 'accounting';
  perform pg_temp.assert(bl_course_exam_chance(e, (select c from courses c where id = 'ict_basics')) is null, 'no exam = null chance');
  perform pg_temp.cfg('school.cooldown_mult', '1');
  raise notice 'ok 8: exams';
end $$;

-- ---------- 9. career gates ----------
do $$
declare f uuid := pg_temp.u('f'); adm uuid := pg_temp.u('adm'); r jsonb; v_req jsonb; v_lbl text; v_cert jsonb; cl career_levels;
begin
  perform pg_temp.at(f, 'bronze_tech_hub');
  perform bl_give_item(f, 'laptop', 1);
  select * into cl from career_levels where track_id = 'tech' and level = 3;
  -- level 3 -> 4 needs: laptop (have), degree, ICT or Bootcamp
  update profiles set job_id = 'tech', job_level = 3, job_xp = cl.xp_to_next, job_shifts_in_level = 3, job_shift_ends_at = bl_now() - interval '1 second',
                      job_shift_pay = 0, job_shift_xp = 0, job_shift_perf = 100, career_best = '{"tech": 3}' where id = f;
  perform pg_temp.login(f);
  v_req := bl_career_reqs((select p from profiles p where id = f), bl_career_lreq((select requirements from career_levels where track_id = 'tech' and level = 4), 'ict,coding_bootcamp'), true);
  select x into v_cert from jsonb_array_elements(v_req) x where x->>'key' = 'cert';
  perform pg_temp.assert(v_cert is not null and (v_cert->>'met')::boolean is false, 'cert requirement listed and unmet');
  perform pg_temp.assert(v_cert->>'label' = 'Needs ICT or Coding Bootcamp certificate', 'label: Needs ICT or Coding Bootcamp certificate (got ' || (v_cert->>'label') || ')');
  -- jobs_catalog carries it too
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(jobs_catalog()->'tracks') t, jsonb_array_elements(t->'levels') l, jsonb_array_elements(l->'requirements') q
                                  where t->>'id' = 'tech' and (l->>'level')::int = 4 and q->>'key' = 'cert'), 'jobs_catalog shows the certificate requirement');
  -- blocked: laptop ok, but no degree and no certificate
  r := bl_settle_shift(f);
  perform pg_temp.assert(r->'blocked' is not null and (r->'blocked'->'missing') @> '"Needs ICT or Coding Bootcamp certificate"'::jsonb, 'promotion blocked: missing the certificate');
  perform pg_temp.assert((select job_level from profiles where id = f) = 3, 'still level 3');
  -- ICT alone is not enough while the degree is missing
  perform pg_temp.login(adm);
  perform admin_grant_cert(f, 'ict');
  update profiles set job_shift_ends_at = bl_now() - interval '1 second', job_shift_perf = 100 where id = f;
  r := bl_settle_shift(f);
  perform pg_temp.assert(r->'blocked' is not null and not ((r->'blocked'->'missing') @> '"Needs ICT or Coding Bootcamp certificate"'::jsonb)
                         and (r->'blocked'->'missing') @> '"A UNIBEN degree"'::jsonb, 'with ICT only the degree is missing');
  -- the BSc counts as the UNIBEN degree
  perform pg_temp.assert(not bl_has_degree((select p from profiles p where id = f)), 'no degree yet');
  perform admin_grant_cert(f, 'bsc');
  perform pg_temp.assert(bl_has_degree((select p from profiles p where id = f)), 'BSc certificate counts as the degree');
  update profiles set job_shift_ends_at = bl_now() - interval '1 second', job_shift_perf = 100 where id = f;
  r := bl_settle_shift(f);
  perform pg_temp.assert(r->'promoted' is not null and (r->'promoted'->>'level')::int = 4, 'promoted to Senior Dev with the certificate and the BSc');
  -- either certificate in the list works (the Bootcamp instead of ICT)
  perform admin_revoke_cert(f, 'ict');
  perform admin_grant_cert(f, 'coding_bootcamp');
  perform pg_temp.assert(bl_cert_has(f, 'ict,coding_bootcamp') and not bl_cert_has(f, 'ict'), 'any-of list');
  -- the degree switch
  perform pg_temp.cfg('school.degree_cert', '""');
  perform pg_temp.assert(not bl_has_degree((select p from profiles p where id = f)), 'no degree cert configured: BSc no longer counts');
  perform pg_temp.cfg('school.degree_cert', '"bsc"');
  -- a track-level gate
  update career_tracks set req_cert = 'accounting' where id = 'pos';
  update profiles set job_id = null, job_level = 1, job_shift_ends_at = null where id = f;
  perform pg_temp.login(f);
  perform pg_temp.assert(pg_temp.hint_of('select job_apply(''pos'')') = 'need_cert', 'track gate refuses job_apply');
  perform pg_temp.assert(pg_temp.msg_of('select job_apply(''pos'')') like 'Needs Accounting certificate%', 'message: Needs Accounting certificate');
  perform pg_temp.assert((select t->'cert_gate'->>'short' from jsonb_array_elements(jobs_catalog()->'tracks') t where t->>'id' = 'pos') = 'Needs Accounting certificate', 'catalog: short lock text');
  perform pg_temp.login(adm);
  perform admin_grant_cert(f, 'accounting');
  perform pg_temp.login(f);
  perform pg_temp.assert(pg_temp.hint_of('select job_apply(''pos'')') = 'ok', 'with the certificate the track opens');
  update career_tracks set req_cert = null where id = 'pos';
  -- level gate on entry (a rejoin never lands above a gated level without the certificate)
  perform pg_temp.assert(bl_career_entry_level((select p from profiles p where id = pg_temp.u('b')), 'transport') = 1, 'fresh player enters transport at 1');
  perform pg_temp.cfg('school.enabled', 'false');
  perform pg_temp.assert(bl_cert_gate(f, 'music_production') is null and (select (x->>'met')::boolean from jsonb_array_elements(
      bl_career_reqs((select p from profiles p where id = pg_temp.u('b')), '{"cert":"ict"}', true)) x) is true, 'school off: gates are open');
  perform pg_temp.cfg('school.enabled', 'true');
  raise notice 'ok 9: career gates';
end $$;

-- ---------- 10. hustle gate + Yahoo gate ----------
do $$
declare c uuid := pg_temp.u('c'); adm uuid := pg_temp.u('adm'); d uuid := pg_temp.u('d'); v jsonb; v_card text; r jsonb;
begin
  -- Headline DJ slot (clubs open at night)
  perform pg_temp.to_hour(23);
  perform pg_temp.at(c, 'bronze_lounge');
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.hint_of('select hustle_start(''dj_headline'')') = 'need_cert', 'Headline DJ slot needs a certificate');
  perform pg_temp.assert(pg_temp.msg_of('select hustle_start(''dj_headline'')') like 'Needs Music Production certificate%', 'message names the certificate');
  select (h->'locked'->>'short') into v_card from jsonb_array_elements(hustle_status()->'hustles') h where h->>'id' = 'dj_headline';
  perform pg_temp.assert(v_card = 'Needs Music Production certificate', 'Hustles app lock text: Needs Music Production certificate (got ' || coalesce(v_card, 'null') || ')');
  -- the zone card at the DJ booth says the same
  select (a->>'locked') into v_card from jsonb_array_elements(place_interior('bronze_lounge')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'dj_headline';
  perform pg_temp.assert(v_card = 'Needs Music Production certificate', 'place card lock text');
  -- the open DJ set is not gated
  perform pg_temp.assert(pg_temp.hint_of('select hustle_start(''dj_set'')') = 'ok', 'the plain DJ set stays open');
  perform pg_temp.advance(70);
  perform hustle_finish();
  perform pg_temp.advance(300);
  -- grant, then it works
  perform pg_temp.login(adm);
  perform admin_grant_cert(c, 'music_production');
  perform pg_temp.at(c, 'bronze_lounge');
  perform pg_temp.login(c);
  v := hustle_start('dj_headline');
  perform pg_temp.assert(v->>'hustle_id' = 'dj_headline', 'headline slot starts with the certificate');
  perform pg_temp.advance(70);
  perform hustle_finish();
  -- Fleet service contract (Mechanic Trade Test), at the Mechanic Village in the daytime
  perform pg_temp.to_hour(10.5);
  perform pg_temp.at(c, 'mechanic_village');
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.hint_of('select hustle_start(''mech_fleet'')') = 'need_cert', 'Fleet service needs the trade test');
  perform pg_temp.assert(pg_temp.hint_of('select hustle_start(''mech_quick'')') = 'ok', 'quick fix stays open');
  perform pg_temp.advance(40);
  perform hustle_finish();
  -- Yahoo job gate (column + enforcement, off by default)
  update yahoo_jobs set req_cert = 'ict' where id = 'chat_client';
  perform pg_temp.ysetup(d, 'laptop');
  perform pg_temp.login(d);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'', null)') = 'need_cert', 'Yahoo job gate refuses');
  select (j->>'locked') into v_card from jsonb_array_elements(yahoo_status()->'jobs') j where j->>'id' = 'chat_client';
  perform pg_temp.assert(v_card = 'cert', 'yahoo_status locked = cert (got ' || coalesce(v_card, 'null') || ')');
  perform pg_temp.assert((select j->>'cert_short' from jsonb_array_elements(yahoo_status()->'jobs') j where j->>'id' = 'chat_client') = 'Needs ICT certificate', 'cert_short');
  perform pg_temp.login(adm);
  perform admin_grant_cert(d, 'ict');
  perform pg_temp.login(d);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''chat_client'', null)') = 'ok', 'ICT opens the Yahoo job');
  update yahoo_jobs set req_cert = null where id = 'chat_client';
  raise notice 'ok 10: hustle and yahoo gates';
end $$;

-- ---------- 11. pay bonus ----------
do $$
declare c uuid := pg_temp.u('c'); b uuid := pg_temp.u('b'); h hustles; m0 numeric; m1 numeric; v_p0 bigint; v_p1 bigint; v jsonb; adm uuid := pg_temp.u('adm');
begin
  -- hustle: Music Production +10 % on DJ sets (c has the certificate from group 10, b does not)
  select * into h from hustles where id = 'dj_set';
  m1 := bl_hustle_pay_mult(c, h);
  m0 := bl_hustle_pay_mult(b, h);
  perform pg_temp.assert(round(m1 / m0, 4) = 1.10, 'certificate: +10 % on the DJ set (ratio ' || round(m1 / m0, 4) || ')');
  perform pg_temp.assert(bl_cert_bonus_pct(c, 'hustle', 'dj_set') = 10 and bl_cert_bonus_pct(b, 'hustle', 'dj_set') = 0, 'bonus pct helper');
  perform pg_temp.assert(bl_cert_bonus_pct(c, 'hustle', 'bolt_shift') = 0, 'unrelated hustle: no bonus');
  -- the card/range follows it
  perform pg_temp.to_hour(23);
  perform pg_temp.at(c, 'bronze_lounge');
  perform pg_temp.login(c);
  perform pg_temp.assert((select (x->>'cert_bonus_pct')::numeric from jsonb_array_elements(hustle_status()->'hustles') x where x->>'id' = 'dj_set') = 10, 'Hustles app shows the bonus');
  -- admin-tunable
  update certificates set pay_bonus_pct = 25 where id = 'music_production';
  perform pg_temp.assert(round(bl_hustle_pay_mult(c, h) / bl_hustle_pay_mult(b, h), 4) = 1.25, 'tuned to +25 %');
  update certificates set pay_bonus_pct = 10 where id = 'music_production';
  -- stacking on the same target (Business Management and Accounting both +pos)
  perform pg_temp.assert(bl_cert_bonus_pct(pg_temp.u('f'), 'career', 'pos') = 8 + 0, 'f has accounting (+8 on pos)');
  -- career shift pay: ICT +5 % on the Tech track
  perform pg_temp.at(b, 'bronze_tech_hub');
  update profiles set job_id = 'tech', job_level = 1, job_xp = 0, job_shift_ends_at = null, job_shift_day = null, job_shifts_today = 0, career_best = '{"tech":1}' where id = b;
  perform pg_temp.login(b);
  perform work_shift();
  select job_shift_pay into v_p0 from profiles where id = b;
  perform pg_temp.advance(60);
  perform bl_settle_shift(b);
  perform pg_temp.login(adm);
  perform admin_grant_cert(b, 'ict');
  perform pg_temp.at(b, 'bronze_tech_hub');
  update profiles set job_shifts_today = 0, job_shift_day = null where id = b;
  perform pg_temp.login(b);
  perform work_shift();
  select job_shift_pay into v_p1 from profiles where id = b;
  perform pg_temp.assert(v_p0 > 0 and v_p1 = (round(v_p0 * 1.05 / 10.0) * 10)::bigint, 'shift pay +5 % with ICT (' || v_p0 || ' -> ' || v_p1 || ')');
  perform pg_temp.assert((bl_career_info((select p from profiles p where id = b))->'job'->>'cert_bonus_pct')::numeric = 5, 'career info shows the bonus');
  -- school off: no bonus
  perform pg_temp.cfg('school.enabled', 'false');
  perform pg_temp.assert(bl_cert_pay_mult(b, 'career', 'tech') = 1, 'school off: no bonus');
  perform pg_temp.cfg('school.enabled', 'true');
  raise notice 'ok 11: pay bonus';
end $$;

-- ---------- 12. admin grant, revoke, audit ----------
do $$
declare adm uuid := pg_temp.u('adm'); a uuid := pg_temp.u('a'); d uuid := pg_temp.u('d'); v jsonb; v_n int;
begin
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_grant_cert(%L, ''catering'', null)', d)) = 'not_admin', 'players cannot grant');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_revoke_cert(%L, ''ict'', null)', d)) = 'not_admin', 'players cannot revoke');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_player_certs(%L)', d)) = 'not_admin', 'players cannot read another player''s list');
  perform pg_temp.login(adm);
  perform pg_temp.assert(not pg_temp.has_cert(d, 'catering'), 'd has no catering');
  v := admin_grant_cert(d, 'catering', 'prize for the cook-off');
  perform pg_temp.assert(v->>'message' = 'Catering & Hospitality certificate granted.' and pg_temp.has_cert(d, 'catering'), 'granted');
  perform pg_temp.assert((select source from player_certificates where user_id = d and cert_id = 'catering') = 'admin', 'source = admin');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'grant_cert' and target_user = d and admin_id = adm and data->>'cert' = 'catering'
                           and data->>'note' = 'prize for the cook-off') = 1, 'grant audited with the note');
  perform pg_temp.assert(exists (select 1 from events where user_id = d and kind = 'graduated' and data->>'cert' = 'catering' and data->>'source' = 'admin'), 'the player gets the graduation moment');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_grant_cert(%L, ''catering'', null)', d)) = 'already', 'double grant refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_grant_cert(%L, ''nope'', null)', d)) = 'bad_cert', 'unknown certificate');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_grant_cert(%L, ''ict'', null)', gen_random_uuid())) = 'no_player', 'unknown player');
  v := admin_player_certs(d);
  perform pg_temp.assert(jsonb_array_length(v->'catalog') = 10 and exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'id' = 'catering' and r->>'source' = 'admin'), 'admin list: owned rows + the catalogue');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v->'catalog') r where r->>'id' = 'catering' and (r->>'has')::boolean), 'catalogue marks owned');
  -- revoke
  v := admin_revoke_cert(d, 'catering', 'granted by mistake');
  perform pg_temp.assert(not pg_temp.has_cert(d, 'catering'), 'revoked');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'revoke_cert' and target_user = d and data->>'cert' = 'catering'
                           and data->>'was_source' = 'admin' and data->>'note' = 'granted by mistake') = 1, 'revoke audited');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_revoke_cert(%L, ''catering'', null)', d)) = 'not_held', 'revoking what they do not have is refused');
  -- a revoked course certificate lets them enrol again from scratch
  perform pg_temp.login(adm);
  perform admin_revoke_cert(a, 'ict');
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.course(a, 'ict_basics')->>'state' = 'new', 'card back to "new" after the certificate was revoked');
  update profiles set cash = 100000 where id = a;
  perform course_enrol('ict_basics');
  perform pg_temp.assert(pg_temp.done(a, 'ict_basics') = 0, 're-enrol starts from 0');
  -- the admin content editor knows the new tables and gate columns
  perform pg_temp.login(adm);
  perform admin_row_upsert('certificates', '{"id": "t_cert", "name": "Test", "icon": "T", "blurb": "b", "pay_bonus_pct": 3, "bonus_tracks": ["tech"], "bonus_hustles": [], "sort": 999, "active": true}');
  perform pg_temp.assert(exists (select 1 from certificates where id = 't_cert' and pay_bonus_pct = 3 and bonus_tracks = '{tech}'), 'admin can add a certificate');
  perform admin_row_upsert('courses', '{"id": "t_course", "name": "Test course", "fee": 1000, "classes": 2, "cert_id": "t_cert", "location_ids": ["uniben"], "exam": false}');
  perform pg_temp.assert(exists (select 1 from courses where id = 't_course' and cert_id = 't_cert'), 'admin can add a course');
  perform admin_row_upsert('hustles', '{"id": "dj_headline", "req_cert": null}');
  perform pg_temp.assert((select req_cert from hustles where id = 'dj_headline') is null, 'admin can clear a hustle gate');
  perform admin_row_upsert('hustles', '{"id": "dj_headline", "req_cert": "music_production"}');
  perform admin_row_upsert('career_levels', '{"track_id": "tech", "level": 5, "req_cert": "coding_bootcamp"}');
  perform pg_temp.assert((select req_cert from career_levels where track_id = 'tech' and level = 5) = 'coding_bootcamp', 'admin can gate a career level');
  raise notice 'ok 12: admin';
end $$;

-- ---------- 13. place cards ----------
do $$
declare b uuid := pg_temp.u('b'); v jsonb; card jsonb;
begin
  perform pg_temp.to_hour(10);
  perform pg_temp.cfg('school.cooldown_mult', '1');
  perform pg_temp.at(b, 'uniben');
  update profiles set cash = 500000 where id = b;
  perform pg_temp.login(b);
  select a into card from jsonb_array_elements(place_interior('uniben')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'kind' = 'class' and a->>'ref' = 'accounting';
  perform pg_temp.assert(card is not null and card->>'class_state' = 'new' and (card->>'instant')::boolean and (card->>'cost')::bigint = 25000, 'not enrolled: an instant Enrol card with the fee');
  perform pg_temp.assert(card->>'locked' = 'Needs Business lvl 2', 'card shows the prerequisite lock');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(place_interior('uniben')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'kind' = 'class') = 7, 'UNIBEN shows seven course cards');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(place_interior('bronze_tech_hub')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'kind' = 'class') = 1, 'tech hub shows the bootcamp card');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(place_interior('ramat_park')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'kind' = 'class') = 1, 'motor park shows the driving school card');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(place_interior('mechanic_village')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'kind' = 'class') = 1, 'mechanic village shows the trade test card');
  -- after enrolling: class card with progress
  perform course_enrol('catering');
  select a into card from jsonb_array_elements(place_interior('uniben')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'kind' = 'class' and a->>'ref' = 'catering';
  perform pg_temp.assert(card->>'class_state' = 'enrolled' and (card->>'done')::int = 0 and (card->>'classes')::int = 5 and not (card->>'instant')::boolean
                         and (card->>'seconds')::int = 35 and card->>'locked' is null, 'enrolled: a class card, 0 of 5, no lock');
  perform pg_temp.cls(b, 'catering');
  select a into card from jsonb_array_elements(place_interior('uniben')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'kind' = 'class' and a->>'ref' = 'catering';
  perform pg_temp.assert((card->>'done')::int = 1 and card->>'locked' like 'Next class in %', 'after a class: 1 of 5 and the cooldown shows');
  -- away from the place the card still renders, saying wrong place
  perform pg_temp.at(b);
  select a into card from jsonb_array_elements(place_interior('uniben')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'kind' = 'class' and a->>'ref' = 'catering';
  perform pg_temp.assert(card is not null, 'card also renders when browsing the place from elsewhere');
  -- the status app view: where to go
  v := pg_temp.course(b, 'catering');
  perform pg_temp.assert(jsonb_array_length(v->'places') = 1 and v->'places'->0->>'id' = 'uniben', 'places: UNIBEN');
  perform pg_temp.assert(jsonb_array_length(v->'unlocks') > 0 and v->>'hours' is not null, 'hours and unlocks listed');
  perform pg_temp.assert(v->'cert'->>'id' = 'catering' and (v->'cert'->>'pay_bonus_pct')::numeric = 10, 'certificate and bonus on the course card');
  perform pg_temp.assert(jsonb_array_length(pg_temp.course(b, 'driving_school')->'places') >= 3, 'driving school lists the motor parks');
  -- inactive courses vanish
  update courses set active = false where id = 'catering';
  perform pg_temp.assert(pg_temp.course(b, 'catering') is null, 'inactive course hidden');
  update courses set active = true where id = 'catering';
  raise notice 'ok 13: place cards';
end $$;

-- ---------- 14. public profile ----------
do $$
declare b uuid := pg_temp.u('b'); a uuid := pg_temp.u('a'); v jsonb;
begin
  perform pg_temp.login(a);
  v := get_public_profile(b);
  perform pg_temp.assert(v ? 'certificates' and exists (select 1 from jsonb_array_elements(v->'certificates') x where x->>'id' = 'ict'), 'public profile lists certificates');
  perform pg_temp.assert(v->'certificates'->0 ? 'name' and v->'certificates'->0 ? 'icon', 'name and icon');
  perform pg_temp.assert(v ? 'yahoo_rank' and v ? 'username', 'the old fields are still there');
  raise notice 'ok 14: public profile';
end $$;

-- ---------- 15. master switch ----------
do $$
declare a uuid := pg_temp.u('a'); v jsonb;
begin
  perform pg_temp.cfg('school.enabled', 'false');
  perform pg_temp.at(a, 'uniben');
  perform pg_temp.to_hour(10);
  perform pg_temp.assert(pg_temp.hint_of('select course_enrol(''catering'')') = 'disabled', 'enrol off');
  perform pg_temp.assert(pg_temp.hint_of('select course_start_class(''ict_basics'')') = 'disabled', 'class off');
  perform pg_temp.assert(not (course_status()->>'enabled')::boolean, 'status says off');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(place_interior('uniben')->'zones') z, jsonb_array_elements(z->'actions') x where x->>'kind' = 'class') = 0, 'no class cards while off');
  perform pg_temp.assert(bl_cert_gate(a, 'music_production') is null, 'gates open while off');
  perform pg_temp.cfg('school.enabled', 'true');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(place_interior('uniben')->'zones') z, jsonb_array_elements(z->'actions') x where x->>'kind' = 'class') = 7, 'cards back on');
  raise notice 'ok 15: master switch';
end $$;
