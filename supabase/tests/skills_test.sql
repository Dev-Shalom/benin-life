-- R3 Skills & progression (20261017000400_skills.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/skills_test.sql
-- Time moves with bl.test_offset_seconds; rolls are pinned with bl.test_rand (bl_rand / bl_crime_roll).
-- Groups: 1 grants + RLS + helpers private · 2 seeds (skills, curve, sources, gates) · 3 XP from a hustle + trait multiplier
-- · 4 the level curve (+ admin edit, level-up event) · 5 XP from Yahoo jobs, activities, career shifts, xp_mult, master switch
-- · 6 Yahoo level lowers the EFCC caught chance (forced rolls, cap) · 7 level gates refuse (Big job, Engine job, DJ open)
-- · 8 hustle pay boost (+5 % per level, admin tune) · 9 admin set skill (audit, refusals) · 10 skills_status JSON.
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
language sql as $$ select current_setting('r3.' || p_name)::uuid; $$;

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

-- hustle: start, wait out the timer, finish with a pinned roll
create or replace function pg_temp.hrun(p_uid uuid, p_id text, p_rand text) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.login(p_uid);
  update profiles set energy = 100, hunger = 100, hygiene = 100, stress = 0, needs_updated_at = bl_now() where id = p_uid;
  perform set_config('bl.test_rand', '', true);
  v := hustle_start(p_id);
  perform pg_temp.advance((v->>'seconds')::numeric + 1);
  perform set_config('bl.test_rand', p_rand, true);
  v := hustle_finish();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.advance(200);
  return v;
end $$;

create or replace function pg_temp.start_hint(p_uid uuid, p_id text) returns text
language plpgsql as $$
begin
  perform pg_temp.login(p_uid);
  perform set_config('bl.test_rand', '', true);
  return pg_temp.hint_of(format('select hustle_start(%L)', p_id));
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

create or replace function pg_temp.yrun(p_uid uuid, p_job text, p_rand text) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.login(p_uid);
  perform set_config('bl.test_rand', '', true);
  v := yahoo_job_start(p_job, null);
  perform pg_temp.advance((v->>'seconds')::numeric + 1);
  perform set_config('bl.test_rand', p_rand, true);
  v := yahoo_finish();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.advance(400);
  return v;
end $$;

-- ---------- setup ----------
do $$
declare
  v_names text[] := array['adm', 'a', 'b', 'c', 'd', 'e', 'f', 'g'];
  n text; u uuid; i int := 0;
begin
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  foreach n in array v_names loop
    i := i + 1;
    u := pg_temp.new_user('r3_' || n || '@rr.bl');
    perform set_config('r3.' || n, u::text, true);
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    perform pg_temp.login(u);
    perform create_profile_v2('R3_' || upper(n), 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home('ekenwan_face_me');
    perform pg_temp.at(u);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
  update profiles set created_at = now() - interval '30 days', protected_until = null, cash = 500000, bank = 0
   where username like 'R3\_%';
  delete from inventory where user_id in (select id from profiles where username like 'R3\_%');
  perform pg_temp.cfg('skills.enabled', 'true');
  perform pg_temp.cfg('skills.xp_mult', '1');
  perform pg_temp.cfg('hustles.enabled', 'true');
  perform pg_temp.cfg('hustles.min_energy', '10');
  perform pg_temp.cfg('places.hours_enabled', 'true');
  perform pg_temp.cfg('yahoo.enabled', 'true');
  perform pg_temp.cfg('yahoo.caught_floor_pct', '0');
  perform pg_temp.cfg('yahoo.seize_laptop_pct', '100');
  perform pg_temp.cfg('yahoo.confiscate_pct', '100');
  perform pg_temp.cfg('club.weekend_price_mult', '1');
  update hustles set active = true;
  update yahoo_jobs set active = true;
  -- pin the Yahoo base chances so the maths below is exact
  update yahoo_jobs set caught_pct = case id when 'chat_client' then 12 when 'romance_job' then 16 when 'big_job' then 24 when 'cash_out' then 14 else caught_pct end;
end $$;

-- ---------- 1. grants + RLS ----------
do $$
declare v_rpc text;
begin
  foreach v_rpc in array array['skills_status()', 'admin_player_skills(uuid)', 'admin_set_player_skill(uuid,text,integer,integer)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'auth may ' || v_rpc);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v_rpc)::regprocedure), 'secdef ' || v_rpc);
  end loop;
  foreach v_rpc in array array['bl_skill_on()', 'bl_skill_num(text,numeric)', 'bl_skill_max_level()', 'bl_skill_level_for_xp(numeric)',
                               'bl_skill_xp_for_level(integer)', 'bl_skill_xp(uuid,text)', 'bl_skill_level(uuid,text)', 'bl_skill_main(text,text)',
                               'bl_skill_gate(uuid,text,text,integer)', 'bl_skill_pay_mult(uuid,text,text)', 'bl_skill_caught_cut(uuid)',
                               'bl_skill_caught_pct(uuid,numeric)', 'bl_skill_card(uuid,text,text,integer)', 'bl_skill_unlocks(text,integer)',
                               'bl_skill_award(uuid,text,text)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'helper private ' || v_rpc);
  end loop;
  perform pg_temp.assert(not has_table_privilege('anon', 'public.player_skills', 'select'), 'anon no skill rows');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.player_skills', 'update')
                         and not has_table_privilege('authenticated', 'public.player_skills', 'insert')
                         and not has_table_privilege('authenticated', 'public.player_skills', 'delete'), 'no client writes to player_skills');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.skills', 'update')
                         and not has_table_privilege('authenticated', 'public.skill_curve', 'update')
                         and not has_table_privilege('authenticated', 'public.skill_sources', 'update'), 'catalogues read-only for players');
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.skills', 'select')
                         and has_table_privilege('authenticated', 'public.skill_sources', 'select'), 'catalogues readable');
  raise notice 'ok 1: grants / helpers private';
end $$;

-- ---------- 2. seeds ----------
do $$
begin
  perform pg_temp.assert((select count(*) from skills) = 10, 'ten skills');
  perform pg_temp.assert((select count(*) from skills where id in ('yahoo', 'driving', 'cooking', 'music', 'teaching', 'fishing', 'mechanic', 'business', 'fitness', 'charisma')) = 10, 'the ten ids');
  perform pg_temp.assert((select count(*) from skill_curve) = 10 and bl_skill_max_level() = 10, 'curve has 10 levels');
  perform pg_temp.assert((select min_skill_level from yahoo_jobs where id = 'big_job') = 3, 'Big job needs Yahoo 3');
  perform pg_temp.assert((select min_skill_level from hustles where id = 'mech_engine') = 2, 'Engine job needs Mechanic 2');
  perform pg_temp.assert((select count(*) from hustles where min_skill_level > 1) = 1 and (select count(*) from yahoo_jobs where min_skill_level > 1) = 1,
                         'only those two are gated');
  perform pg_temp.assert((select min_skill_level from hustles where id = 'dj_set') = 1, 'DJ without a controller still allowed (no gate)');
  perform pg_temp.assert((select caught_pct_per_level from skills where id = 'yahoo') = 4 and (select caught_cap_pct from skills where id = 'yahoo') = 36, 'yahoo -4 % per level, cap 36');
  perform pg_temp.assert((select pay_pct_per_level from skills where id = 'mechanic') = 5, 'pay +5 % per level');
  perform pg_temp.assert(bl_skill_main('hustle', 'vend_jollof') = 'cooking', 'jollof main skill is cooking (most XP)');
  perform pg_temp.assert(bl_skill_main('hustle', 'stall_rent') is null, 'a pass has no skill');
  perform pg_temp.assert((select count(*) from skill_sources where kind = 'career') = 6, 'six career tracks feed skills');
  perform pg_temp.assert((select count(*) from skill_sources where kind = 'activity' and skill_id = 'fitness') >= 1
                         and (select count(*) from skill_sources where kind = 'activity' and skill_id = 'charisma') >= 1
                         and (select count(*) from skill_sources where kind = 'activity' and skill_id = 'cooking') >= 1, 'gym/club/cooking activities mapped');
  perform pg_temp.assert(exists (select 1 from game_config where key = 'skills.enabled') and exists (select 1 from game_config where key = 'skills.xp_mult'), 'config rows');
  raise notice 'ok 2: seeds';
end $$;

-- ---------- 3. XP from a hustle (+ trait multiplier) ----------
do $$
declare a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); v jsonb;
begin
  perform pg_temp.to_hour(10.5);
  update profiles set traits = '{}' where id = b;
  perform pg_temp.at(a, 'mechanic_village');
  perform pg_temp.at(b, 'mechanic_village');
  perform pg_temp.assert(pg_temp.xp(a, 'mechanic') = 0, 'starts at 0 XP');
  -- Quick fix = 6 XP; the Hustler trait (skill_xp.hustle 1.25) makes it 7.5 -> 8
  v := pg_temp.hrun(a, 'mech_quick', '0.9999999');
  perform pg_temp.assert(v->>'status' = 'done', 'quick fix done');
  perform pg_temp.assert(pg_temp.xp(a, 'mechanic') = 8, 'hustler: quick fix gives 8 XP (got ' || pg_temp.xp(a, 'mechanic') || ')');
  v := pg_temp.hrun(b, 'mech_quick', '0.9999999');
  perform pg_temp.assert(pg_temp.xp(b, 'mechanic') = 6, 'no traits: 6 XP (got ' || pg_temp.xp(b, 'mechanic') || ')');
  raise notice 'ok 3: hustle XP';
end $$;

-- ---------- 4. the level curve ----------
do $$
declare a uuid := pg_temp.u('a'); v_ev int; v jsonb;
begin
  perform pg_temp.assert(bl_skill_level_for_xp(0) = 1 and bl_skill_level_for_xp(39) = 1, 'xp 0..39 = level 1');
  perform pg_temp.assert(bl_skill_level_for_xp(40) = 2 and bl_skill_level_for_xp(119) = 2, 'xp 40 = level 2');
  perform pg_temp.assert(bl_skill_level_for_xp(120) = 3 and bl_skill_level_for_xp(259) = 3 and bl_skill_level_for_xp(260) = 4, 'levels 3 and 4');
  perform pg_temp.assert(bl_skill_level_for_xp(3300) = 10 and bl_skill_level_for_xp(99999999) = 10, 'level 10 is the cap');
  -- an admin edit of the curve applies at once
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_row_upsert('skill_curve', '{"level": 2, "xp": 50}');
  perform pg_temp.assert(bl_skill_level_for_xp(45) = 1 and bl_skill_level_for_xp(50) = 2, 'edited curve: level 2 at 50 XP');
  perform admin_row_upsert('skill_curve', '{"level": 2, "xp": 40}');
  perform pg_temp.assert(bl_skill_level_for_xp(40) = 2, 'curve restored');
  -- crossing a level writes a skill_up event (the toast + confetti)
  perform pg_temp.setxp(a, 'mechanic', 36);
  select count(*) into v_ev from events where user_id = a and kind = 'skill_up';
  perform pg_temp.assert(v_ev = 0, 'no skill_up yet');
  perform pg_temp.to_hour(10.5);
  perform pg_temp.at(a, 'mechanic_village');
  v := pg_temp.hrun(a, 'mech_quick', '0.9999999');   -- +8 -> 44 XP = level 2
  perform pg_temp.assert(pg_temp.xp(a, 'mechanic') = 44, 'xp 44');
  perform pg_temp.assert((select count(*) from events where user_id = a and kind = 'skill_up') = 1, 'one skill_up event');
  perform pg_temp.assert((select (data->>'level')::int from events where user_id = a and kind = 'skill_up') = 2
                         and (select data->>'skill' from events where user_id = a and kind = 'skill_up') = 'mechanic', 'event says Mechanic level 2');
  perform pg_temp.assert((select title from events where user_id = a and kind = 'skill_up') like '%Mechanic level 2!', 'title');
  perform pg_temp.assert((select body from events where user_id = a and kind = 'skill_up') like '%+5% pay on Mechanic hustles%', 'body names the pay boost');
  raise notice 'ok 4: curve';
end $$;

-- ---------- 5. XP from Yahoo jobs, activities, career shifts, xp_mult, master switch ----------
do $$
declare c uuid := pg_temp.u('c'); g uuid := pg_temp.u('g'); r jsonb; x0 int;
begin
  -- Yahoo: Chat a client = 8 XP x 1.25 (hustler) = 10; a caught run gives none
  perform pg_temp.ysetup(c, 'laptop');
  r := pg_temp.yrun(c, 'chat_client', '0.9999999');
  perform pg_temp.assert(r->>'status' = 'paid', 'chat client paid');
  perform pg_temp.assert(pg_temp.xp(c, 'yahoo') = 10, 'yahoo job: 10 XP (got ' || pg_temp.xp(c, 'yahoo') || ')');
  perform pg_temp.ysetup(c, 'laptop');
  r := pg_temp.yrun(c, 'chat_client', '0.0000001');
  perform pg_temp.assert(r->>'status' = 'caught', 'caught');
  perform pg_temp.assert(pg_temp.xp(c, 'yahoo') = 10, 'a caught run gives no XP');
  -- activity: a jog round the stadium = fitness 4
  perform pg_temp.login(g);
  perform pg_temp.at(g, 'ogbemudia_stadium');
  perform do_activity('stadium_jog');
  perform pg_temp.assert(pg_temp.xp(g, 'fitness') = 4, 'jog gives 4 fitness XP (got ' || pg_temp.xp(g, 'fitness') || ')');
  -- career shift: the shift settle path awards by track
  update profiles set traits = '{}' where id = g;
  perform bl_skill_award(g, 'career', 'transport');
  perform pg_temp.assert(pg_temp.xp(g, 'driving') = 6, 'transport shift = 6 driving XP');
  perform bl_skill_award(g, 'career', 'tech');
  perform pg_temp.assert(pg_temp.xp(g, 'yahoo') = 6, 'tech shift = 6 yahoo XP (IT)');
  -- one action can feed two skills (jollof: cooking + business)
  perform bl_skill_award(g, 'hustle', 'vend_jollof');
  perform pg_temp.assert(pg_temp.xp(g, 'cooking') = 7 and pg_temp.xp(g, 'business') = 3, 'jollof feeds cooking 7 and business 3');
  -- the global multiplier
  perform pg_temp.cfg('skills.xp_mult', '2');
  x0 := pg_temp.xp(g, 'driving');
  perform bl_skill_award(g, 'career', 'transport');
  perform pg_temp.assert(pg_temp.xp(g, 'driving') = x0 + 12, 'xp_mult 2 doubles');
  perform pg_temp.cfg('skills.xp_mult', '1');
  -- an inactive source gives nothing; a missing source gives nothing
  update skill_sources set active = false where id = 'career:transport:driving';
  x0 := pg_temp.xp(g, 'driving');
  perform bl_skill_award(g, 'career', 'transport');
  perform pg_temp.assert(pg_temp.xp(g, 'driving') = x0, 'inactive source = no XP');
  update skill_sources set active = true where id = 'career:transport:driving';
  perform bl_skill_award(g, 'activity', 'no_such_thing');
  -- master switch: no XP, no gates, no effects
  perform pg_temp.cfg('skills.enabled', 'false');
  x0 := pg_temp.xp(g, 'driving');
  perform bl_skill_award(g, 'career', 'transport');
  perform pg_temp.assert(pg_temp.xp(g, 'driving') = x0, 'switch off: no XP');
  perform pg_temp.assert(bl_skill_gate(g, 'yahoo', 'big_job', 3) is null, 'switch off: no gate');
  perform pg_temp.assert(bl_skill_pay_mult(g, 'hustle', 'mech_quick') = 1 and bl_skill_caught_cut(g) = 0, 'switch off: no effects');
  perform pg_temp.cfg('skills.enabled', 'true');
  raise notice 'ok 5: XP sources';
end $$;

-- ---------- 6. Yahoo level lowers the EFCC caught chance ----------
do $$
declare d uuid := pg_temp.u('d'); r jsonb; s jsonb; j jsonb;
begin
  -- level 1: 12 % (chat client); a roll of 0.11 is caught
  perform pg_temp.setxp(d, 'yahoo', 0);
  perform pg_temp.assert(bl_skill_caught_cut(d) = 0, 'level 1: no cut');
  perform pg_temp.ysetup(d, 'laptop');
  r := pg_temp.yrun(d, 'chat_client', '0.11');
  perform pg_temp.assert(r->>'status' = 'caught', 'level 1: 0.11 < 12 % is caught');
  -- level 5 (460 XP): cut 16 % relative -> 12 * 0.84 = 10.08 %; the same roll 0.11 now gets away
  perform pg_temp.setxp(d, 'yahoo', 460);
  perform pg_temp.assert(bl_skill_caught_cut(d) = 16, 'level 5 cuts 16 %');
  perform pg_temp.assert(abs(bl_skill_caught_pct(d, 12) - 10.08) < 0.0001, 'caught 12 -> 10.08');
  perform pg_temp.ysetup(d, 'laptop');
  perform pg_temp.login(d);
  s := yahoo_status();
  j := (select e from jsonb_array_elements(s->'jobs') e where e->>'id' = 'chat_client');
  perform pg_temp.assert(abs((j->>'skill_caught_pct')::numeric - 10.08) < 0.0001 and (j->>'caught_pct')::numeric = 12, 'status shows base 12 and skill 10.08');
  perform pg_temp.assert((j->'skill'->>'level')::int = 5 and (j->'skill'->>'caught_cut_pct')::numeric = 16, 'status skill card');
  r := pg_temp.yrun(d, 'chat_client', '0.11');
  perform pg_temp.assert(r->>'status' = 'paid', 'level 5: 0.11 is not < 10.08 %, paid');
  -- 0.10 is still caught at level 5 (10 < 10.08)
  perform pg_temp.ysetup(d, 'laptop');
  r := pg_temp.yrun(d, 'chat_client', '0.10');
  perform pg_temp.assert(r->>'status' = 'caught', 'level 5: 0.10 < 10.08 % is caught');
  -- level 10 (3300 XP): -36 %, 12 -> 7.68; 0.08 gets away, 0.07 is caught
  perform pg_temp.setxp(d, 'yahoo', 3300);
  perform pg_temp.assert(bl_skill_caught_cut(d) = 36 and abs(bl_skill_caught_pct(d, 12) - 7.68) < 0.0001, 'level 10: -36 % (12 -> 7.68)');
  perform pg_temp.ysetup(d, 'laptop');
  r := pg_temp.yrun(d, 'chat_client', '0.08');
  perform pg_temp.assert(r->>'status' = 'paid', 'level 10: 0.08 gets away');
  perform pg_temp.ysetup(d, 'laptop');
  r := pg_temp.yrun(d, 'chat_client', '0.07');
  perform pg_temp.assert(r->>'status' = 'caught', 'level 10: 0.07 < 7.68 % is caught');
  -- the cash-out roll gets the cut too (14 % -> 8.96 %)
  perform pg_temp.assert(abs(bl_skill_caught_pct(d, 14) - 8.96) < 0.0001, 'cash out 14 -> 8.96');
  -- admin tune: 10 % per level, capped at 20 %
  update skills set caught_pct_per_level = 10, caught_cap_pct = 20 where id = 'yahoo';
  perform pg_temp.assert(bl_skill_caught_cut(d) = 20, 'cap 20 % holds at level 10');
  perform pg_temp.setxp(d, 'yahoo', 120);  -- level 3 -> 20 %
  perform pg_temp.assert(bl_skill_caught_cut(d) = 20, 'level 3 at 10 %/level = 20 %');
  perform pg_temp.setxp(d, 'yahoo', 40);   -- level 2 -> 10 %
  perform pg_temp.assert(bl_skill_caught_cut(d) = 10, 'level 2 at 10 %/level = 10 %');
  update skills set caught_pct_per_level = 4, caught_cap_pct = 36 where id = 'yahoo';
  -- the skill that cuts is configurable; point it at a skill with no cut = no effect
  perform pg_temp.setxp(d, 'yahoo', 3300);
  perform pg_temp.cfg('skills.caught_skill', '"driving"');
  perform pg_temp.assert(bl_skill_caught_cut(d) = 0, 'other skill, no cut');
  perform pg_temp.cfg('skills.caught_skill', '"yahoo"');
  raise notice 'ok 6: yahoo catch reduction';
end $$;

-- ---------- 7. level gates refuse ----------
do $$
declare e uuid := pg_temp.u('e'); r jsonb; s jsonb; j jsonb; h jsonb;
begin
  -- Yahoo Big job: Yahoo lvl 3, even with a strong laptop
  perform pg_temp.ysetup(e, 'dell_xps_13');
  perform pg_temp.setxp(e, 'yahoo', 119);
  perform pg_temp.login(e);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''big_job'', null)') = 'skill_level', 'level 2 Yahoo cannot start the Big job');
  begin
    perform yahoo_job_start('big_job', null);
  exception when others then
    perform pg_temp.assert(sqlerrm like 'Needs Yahoo level 3 (you are level 2)%', 'message names the skill and level: ' || sqlerrm);
  end;
  s := yahoo_status();
  j := (select x from jsonb_array_elements(s->'jobs') x where x->>'id' = 'big_job');
  perform pg_temp.assert(j->>'locked' = 'skill_level' and (j->>'min_skill_level')::int = 3, 'status marks it locked: skill_level');
  perform pg_temp.assert((select x->>'locked' from jsonb_array_elements(s->'jobs') x where x->>'id' = 'chat_client') is null, 'chat client open');
  perform pg_temp.setxp(e, 'yahoo', 120);
  perform pg_temp.assert(pg_temp.hint_of('select yahoo_job_start(''big_job'', null)') = 'ok', 'level 3 can start the Big job');
  perform pg_temp.advance(500);
  -- Engine job: Mechanic lvl 2 (a Quick fix first)
  perform pg_temp.to_hour(10.5);
  perform pg_temp.at(e, 'mechanic_village');
  perform pg_temp.setxp(e, 'mechanic', 10);
  perform pg_temp.assert(pg_temp.start_hint(e, 'mech_engine') = 'skill_level', 'level 1 Mechanic cannot do the Engine job');
  perform pg_temp.login(e);
  h := (select x from jsonb_array_elements(hustle_status()->'hustles') x where x->>'id' = 'mech_engine');
  perform pg_temp.assert(h->'locked'->>'short' = 'Needs Mechanic lvl 2' and h->'locked'->>'hint' = 'skill_level', 'locked short: Needs Mechanic lvl 2 (' || coalesce(h->'locked'->>'short', 'null') || ')');
  perform pg_temp.assert((h->'skill'->>'level')::int = 1 and (h->'skill'->>'min_level')::int = 2 and (h->'skill'->>'ok')::boolean = false, 'hustle skill card');
  perform pg_temp.assert((select x->'locked' from jsonb_array_elements(hustle_status()->'hustles') x where x->>'id' = 'mech_quick') = 'null'::jsonb, 'quick fix open');
  perform pg_temp.setxp(e, 'mechanic', 40);
  perform pg_temp.assert(pg_temp.start_hint(e, 'mech_engine') = 'ok', 'level 2 Mechanic can do the Engine job');
  perform pg_temp.advance(300);
  -- the zone card carries the lock too (place_interior)
  perform pg_temp.setxp(e, 'mechanic', 0);
  perform pg_temp.at(e, 'mechanic_village');
  perform pg_temp.login(e);
  perform pg_temp.assert((select a->>'locked' from jsonb_array_elements(place_interior('mechanic_village')->'zones') z,
                               jsonb_array_elements(z->'actions') a where a->>'ref' = 'mech_engine') = 'Needs Mechanic lvl 2', 'zone card says Needs Mechanic lvl 2');
  -- the DJ set has no gate (no controller still allowed)
  perform pg_temp.assert(bl_skill_gate(e, 'hustle', 'dj_set', (select min_skill_level from hustles where id = 'dj_set')) is null, 'DJ open at level 1');
  -- an admin can open or close any gate
  update hustles set min_skill_level = 4 where id = 'mech_quick';
  perform pg_temp.assert(pg_temp.start_hint(e, 'mech_quick') = 'skill_level', 'admin gated the quick fix');
  update hustles set min_skill_level = 1 where id = 'mech_quick';
  raise notice 'ok 7: gates';
end $$;

-- ---------- 8. hustle pay boost ----------
do $$
declare f uuid := pg_temp.u('f'); v jsonb; h jsonb;
begin
  perform pg_temp.to_hour(10.5);
  perform pg_temp.at(f, 'mechanic_village');
  update profiles set cash = 200000 where id = f;
  -- level 1: top pay 8,000, no boost
  perform pg_temp.setxp(f, 'mechanic', 0);
  v := pg_temp.hrun(f, 'mech_quick', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 8000, 'level 1 pays 8,000 (got ' || (v->>'amount') || ')');
  -- level 4 (260 XP): +15 % -> 9,200, and the card says so
  perform pg_temp.setxp(f, 'mechanic', 260);
  perform pg_temp.login(f);
  h := (select x from jsonb_array_elements(hustle_status()->'hustles') x where x->>'id' = 'mech_quick');
  perform pg_temp.assert((h->>'pay_mult_now')::numeric = 1.15 and (h->'skill'->>'pay_boost_pct')::numeric = 15, 'card: x1.15 and +15 % from skill');
  perform pg_temp.assert((h->>'pay_max')::bigint = 8000, 'catalogue pay range unchanged');
  perform pg_temp.assert((select (a->>'pay_max')::bigint from jsonb_array_elements(place_interior('mechanic_village')->'zones') z,
                               jsonb_array_elements(z->'actions') a where a->>'ref' = 'mech_quick') = 9200, 'zone card pay max 9,200');
  perform pg_temp.assert((select (a->'skill'->>'pay_boost_pct')::numeric from jsonb_array_elements(place_interior('mechanic_village')->'zones') z,
                               jsonb_array_elements(z->'actions') a where a->>'ref' = 'mech_quick') = 15, 'zone card +15 %');
  v := pg_temp.hrun(f, 'mech_quick', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 9200, 'level 4 pays 9,200 (got ' || (v->>'amount') || ')');
  -- level 10 (3300 XP): +45 %
  perform pg_temp.setxp(f, 'mechanic', 3300);
  perform pg_temp.assert(bl_skill_pay_mult(f, 'hustle', 'mech_quick') = 1.45, 'level 10: x1.45');
  -- admin tune: 10 % per level at level 4 = +30 %
  perform pg_temp.setxp(f, 'mechanic', 260);
  update skills set pay_pct_per_level = 10 where id = 'mechanic';
  v := pg_temp.hrun(f, 'mech_quick', '0.9999999');
  perform pg_temp.assert((v->>'amount')::bigint = 10400, 'tuned to 10 %/level: 10,400 (got ' || (v->>'amount') || ')');
  update skills set pay_pct_per_level = 0 where id = 'mechanic';
  perform pg_temp.assert(bl_skill_pay_mult(f, 'hustle', 'mech_quick') = 1, '0 % per level = no boost');
  update skills set pay_pct_per_level = 5 where id = 'mechanic';
  -- the boost follows the hustle's own skill: a Mechanic level does nothing for Bolt (Driving)
  perform pg_temp.assert(bl_skill_pay_mult(f, 'hustle', 'bolt_shift') = 1, 'driving untouched by mechanic level');
  raise notice 'ok 8: pay boost';
end $$;

-- ---------- 9. admin set skill (audit) ----------
do $$
declare adm uuid := pg_temp.u('adm'); a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); r jsonb; n0 int;
begin
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_set_player_skill(%L, ''yahoo'', 5, null)', a)) = 'not_admin', 'players cannot set skills');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_player_skills(%L)', a)) = 'not_admin', 'players cannot read the admin view');
  perform pg_temp.login(adm);
  select count(*) into n0 from admin_audit where action = 'set_skill' and target_user = a;
  r := admin_set_player_skill(a, 'yahoo', 5, null);
  perform pg_temp.assert((r->>'level')::int = 5 and (r->>'xp')::int = 460 and pg_temp.xp(a, 'yahoo') = 460, 'set level 5 = 460 XP');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'set_skill' and target_user = a) = n0 + 1, 'logged to the audit');
  perform pg_temp.assert((select data->>'skill' from admin_audit where action = 'set_skill' and target_user = a order by id desc limit 1) = 'yahoo'
                         and (select (data->>'new_level')::int from admin_audit where action = 'set_skill' and target_user = a order by id desc limit 1) = 5, 'audit has skill and new level');
  r := admin_set_player_skill(a, 'yahoo', null, 50);
  perform pg_temp.assert((r->>'level')::int = 2 and pg_temp.xp(a, 'yahoo') = 50, 'set exact XP 50 = level 2');
  r := admin_set_player_skill(a, 'yahoo', 1, null);
  perform pg_temp.assert(pg_temp.xp(a, 'yahoo') = 0, 'set level 1 = 0 XP');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_set_player_skill(%L, ''yahoo'', 11, null)', a)) = 'bad_value', 'level 11 refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_set_player_skill(%L, ''yahoo'', null, -5)', a)) = 'bad_value', 'negative XP refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_set_player_skill(%L, ''nope'', 2, null)', a)) = 'bad_skill', 'unknown skill refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_set_player_skill(%L, ''yahoo'', null, null)', a)) = 'bad_value', 'level or XP needed');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_set_player_skill(%L, ''yahoo'', 2, null)', gen_random_uuid())) = 'no_player', 'unknown player refused');
  r := admin_player_skills(a);
  perform pg_temp.assert(jsonb_array_length(r->'rows') = 10 and (r->>'max_level')::int = 10, 'admin view lists all 10 skills');
  perform pg_temp.assert((select (x->>'level')::int from jsonb_array_elements(r->'rows') x where x->>'skill' = 'mechanic') = 2, 'admin view shows mechanic level 2');
  -- the Content editor can edit the three new tables and the gate columns
  perform admin_row_upsert('skills', '{"id": "yahoo", "caught_pct_per_level": 5}');
  perform pg_temp.assert((select caught_pct_per_level from skills where id = 'yahoo') = 5, 'admin edits a skill');
  perform admin_row_upsert('skills', '{"id": "yahoo", "caught_pct_per_level": 4}');
  perform admin_row_upsert('skill_sources', '{"id": "activity:cook_home:cooking", "xp": 9}');
  perform pg_temp.assert((select xp from skill_sources where id = 'activity:cook_home:cooking') = 9, 'admin edits a source');
  perform admin_row_upsert('skill_sources', '{"id": "activity:tv:charisma", "kind": "activity", "ref": "watch_tv", "skill_id": "charisma", "xp": 1, "note": "test", "active": true}');
  perform pg_temp.assert(exists (select 1 from skill_sources where id = 'activity:tv:charisma'), 'admin adds a source');
  perform admin_row_upsert('yahoo_jobs', '{"id": "romance_job", "min_skill_level": 2}');
  perform admin_row_upsert('hustles', '{"id": "pos_agent", "min_skill_level": 2}');
  perform pg_temp.assert((select min_skill_level from yahoo_jobs where id = 'romance_job') = 2 and (select min_skill_level from hustles where id = 'pos_agent') = 2, 'admin edits the gates');
  raise notice 'ok 9: admin';
end $$;

-- ---------- 10. skills_status ----------
do $$
declare a uuid := pg_temp.u('a'); s jsonb; y jsonb;
begin
  perform pg_temp.setxp(a, 'yahoo', 50);
  perform pg_temp.login(a);
  s := skills_status();
  perform pg_temp.assert((s->>'enabled')::boolean and (s->>'max_level')::int = 10 and jsonb_array_length(s->'curve') = 10, 'status header');
  perform pg_temp.assert(jsonb_array_length(s->'skills') = 10, 'all ten skills');
  y := (select x from jsonb_array_elements(s->'skills') x where x->>'id' = 'yahoo');
  perform pg_temp.assert((y->>'level')::int = 2 and (y->>'xp')::int = 50 and (y->>'level_xp')::int = 40 and (y->>'next_xp')::int = 120, 'yahoo level 2, 50 xp, next at 120');
  perform pg_temp.assert((y->>'pct')::numeric = round(100.0 * 10 / 80, 1), 'bar is 10 / 80 of the way');
  perform pg_temp.assert(y->'next_unlocks' @> '"Unlocks: Big job"'::jsonb or exists (select 1 from jsonb_array_elements_text(y->'next_unlocks') t where t like 'Unlocks: %Big job%'), 'level 3 unlocks the Big job');
  perform pg_temp.assert((y->>'caught_cut_pct')::numeric = 4 and jsonb_array_length(y->'train') > 0, 'cut and where to train');
  perform pg_temp.setxp(a, 'fitness', 5000);
  s := skills_status();
  y := (select x from jsonb_array_elements(s->'skills') x where x->>'id' = 'fitness');
  perform pg_temp.assert((y->>'level')::int = 10 and (y->>'pct')::numeric = 100 and y->'next_xp' = 'null'::jsonb and y->'next_unlocks' = '[]'::jsonb, 'max level: full bar, nothing next');
  raise notice 'ok 10: skills_status';
end $$;

-- ---------- 11. RLS ----------
do $$
declare a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); n int;
begin
  perform pg_temp.setxp(a, 'yahoo', 50);
  perform pg_temp.setxp(b, 'yahoo', 60);
  set local role authenticated;
  perform pg_temp.login(a);
  select count(*) into n from public.player_skills where user_id = b;
  perform pg_temp.assert(n = 0, 'cannot read another player''s skills');
  select count(*) into n from public.player_skills where user_id = a;
  perform pg_temp.assert(n >= 1, 'can read own skills');
  begin
    update public.player_skills set xp = 99999 where user_id = a;
    raise exception 'TEST FAILED: client wrote XP';
  exception when insufficient_privilege then null;
  end;
  reset role;
  raise notice 'ok 11: RLS';
end $$;
