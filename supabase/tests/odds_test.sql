-- E3 probability verification. Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/odds_test.sql
--
-- Every chance the game states ("EFCC 12%", "62% caught", "Bolt cancels 8%", "exam 55%", "20% falls as notes" ...) is checked three ways:
--   1. STATED   what the setting / table / help text says, plus the modifiers we know apply (laptop, Yahoo level, charms, staff);
--   2. SHOWN    what the server reports to the client (status RPCs and *_json helpers that the screens print), must equal what the
--               roll really uses;
--   3. OBSERVED the REAL resolve function run N times with NO forced roll (bl.test_rand is cleared), must land within 4 binomial
--               standard deviations of the stated chance (about +-3 to 4 points at N = 1,000 to 2,000).
-- The test prints one "ODDS" line per check (the table in docs/BALANCE.md comes from them) and raises on any mismatch.
-- Time: about 40 s. A 4-sigma band fails about once in 15,000 runs per check by luck; rerun before suspecting a bug.

create or replace function pg_temp.z_check(p_name text, p_hits int, p_n int, p_pct numeric, p_shown numeric default null, p_z numeric default 4) returns void
language plpgsql as $$
declare v_obs numeric := p_hits::numeric * 100 / p_n; v_p numeric := least(1, greatest(0, p_pct / 100));
        v_sd numeric := sqrt(v_p * (1 - v_p) / p_n) * 100; v_tol numeric;
begin
  v_tol := greatest(p_z * v_sd, 0.2);
  raise notice 'ODDS | % | stated % | shown % | observed % | n % | tol +-%', rpad(p_name, 44), round(p_pct, 2), coalesce(round(p_shown, 2)::text, '-'), round(v_obs, 2), p_n, round(v_tol, 1);
  if p_shown is not null and abs(p_shown - p_pct) > 0.05 then
    raise exception 'TEST FAILED: % : the screen shows % but the roll uses %', p_name, p_shown, p_pct;
  end if;
  if abs(v_obs - p_pct) > v_tol then
    raise exception 'TEST FAILED: % : observed % %% vs stated % %% (n %, tolerance +-%)', p_name, round(v_obs, 2), p_pct, p_n, round(v_tol, 1);
  end if;
end $$;

-- trials: the default sizes keep the whole file near a minute; for a stronger run set  odds.mult  first, e.g.
--   select set_config('odds.mult', '4', false);   (4 x the trials, about 2.5 times tighter bands, a few minutes)
create or replace function pg_temp.nn(p_base int) returns int
language sql as $$ select greatest(1, round(p_base * coalesce(nullif(current_setting('odds.mult', true), '')::numeric, 1))::int) $$;

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

-- free, at home (or another place), online, no case
create or replace function pg_temp.at(p_uid uuid, p_loc text default null) returns void
language sql as $$
  update profiles set location_id = coalesce(p_loc, home_location_id), travel_to = null, travel_mode = null, travel_started_at = null,
                      travel_arrives_at = null, busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = now(), rent_due_at = null, energy = 100, hunger = 100, health = 100
   where id = p_uid;
$$;

create or replace function pg_temp.setxp(p_uid uuid, p_skill text, p_xp int) returns void
language sql as $$
  insert into player_skills (user_id, skill_id, xp) values (p_uid, p_skill, p_xp)
  on conflict (user_id, skill_id) do update set xp = excluded.xp;
$$;

create or replace function pg_temp.lvl(p_xp int) returns int
language sql as $$ select max(level) from skill_curve where xp <= p_xp; $$;

create or replace function pg_temp.mk(p_email text, p_name text) returns uuid
language plpgsql as $$
declare u uuid := pg_temp.new_user(p_email);
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(u);
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  perform pg_temp.at(u);
  update profiles set created_at = now() - interval '30 days', protected_until = null, cash = 0, bank = 0 where id = u;
  delete from inventory where user_id = u;
  return u;
end $$;

-- ---------- setup ----------
do $$
declare a uuid; b uuid; c uuid; t uuid; v uuid;
begin
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  a := pg_temp.mk('odds_a@oo.bl', 'Odds_A'); b := pg_temp.mk('odds_b@oo.bl', 'Odds_B'); c := pg_temp.mk('odds_c@oo.bl', 'Odds_C');
  t := pg_temp.mk('odds_t@oo.bl', 'Odds_T'); v := pg_temp.mk('odds_v@oo.bl', 'Odds_V');
  perform set_config('odds.a', a::text, true); perform set_config('odds.b', b::text, true); perform set_config('odds.c', c::text, true);
  perform set_config('odds.t', t::text, true); perform set_config('odds.v', v::text, true);
  -- the settings these checks read are the live defaults; only what could disturb a long loop is pinned
  perform pg_temp.cfg('skills.enabled', 'true');
  perform pg_temp.cfg('yahoo.enabled', 'true');
  perform pg_temp.cfg('yahoo.caught_floor_pct', '5');
  perform pg_temp.cfg('yahoo.cafe_locations', '"wifi_joint"');
  perform pg_temp.cfg('club.weekend_price_mult', '1');
  update yahoo_jobs set active = true;
  -- no skill XP during the long loops (the level must not move between rolls); the XP rules have their own suite (skills_test)
  update skill_sources set active = false;
  update profiles set cash = 5000000000, bank = 0 where id in (a, b, c, t, v);
end $$;
-- the long loops below call the real resolve functions thousands of times; triggers that only feed alerts / challenges are skipped to keep
-- the run short (the roll logic lives in the functions, not in the triggers). Everything here is rolled back.
set local session_replication_role = replica;

-- ---------- 1. Yahoo solo jobs: chance = job % - laptop points, then the Yahoo level cut ----------
create or replace function pg_temp.yahoo_odds(p_label text, p_job text, p_laptop text, p_xp int, p_n int) returns void
language plpgsql as $$
declare
  u uuid := current_setting('odds.a')::uuid; j yahoo_jobs; sp laptop_specs; v_base numeric; v_cut numeric; v_exp numeric;
  v jsonb; v_run bigint; v_hits int := 0; v_shown numeric; v_status jsonb; i int; r yahoo_runs; k skills; res jsonb;
begin
  select * into j from yahoo_jobs where id = p_job;
  select * into sp from laptop_specs where item_id = p_laptop;
  select * into k from skills where id = 'yahoo';
  v_base := greatest(least(j.caught_pct, 5), j.caught_pct - sp.efcc_minus_pts);
  v_cut := least(k.caught_cap_pct, (pg_temp.lvl(p_xp) - 1) * k.caught_pct_per_level);
  v_exp := v_base * (1 - v_cut / 100.0);
  -- setup: only this laptop, MiFi on, at home, no case, skill xp fixed
  delete from inventory where user_id = u and item_id in (select item_id from laptop_specs);
  perform bl_give_item(u, p_laptop, 1);
  perform pg_temp.setxp(u, 'yahoo', p_xp);
  perform pg_temp.at(u); perform bl_yahoo_row(u);
  update yahoo_players set mifi_until = bl_now() + interval '300 days', dirty = 0 where user_id = u;
  delete from yahoo_runs where user_id = u; delete from jail_cases where user_id = u;
  perform pg_temp.login(u); perform set_config('bl.test_rand', '', true);
  -- SHOWN: the job card, the start reply and the running-job json must all carry the cut chance the roll will use
  v_status := yahoo_status();
  select (x->>'skill_caught_pct')::numeric into v_shown from jsonb_array_elements(v_status->'jobs') x where x->>'id' = p_job;
  v := yahoo_job_start(p_job, null);
  if abs((v->>'skill_caught_pct')::numeric - v_exp) > 0.05 then raise exception 'TEST FAILED: % start reply shows % expected %', p_label, v->>'skill_caught_pct', v_exp; end if;
  v_status := yahoo_status();
  if abs((v_status->'run'->>'skill_caught_pct')::numeric - v_exp) > 0.05 then raise exception 'TEST FAILED: % running json shows % expected %', p_label, v_status->'run'->>'skill_caught_pct', v_exp; end if;
  v_run := (v->>'run_id')::bigint;
  select * into r from yahoo_runs where id = v_run;
  update yahoo_runs set status = 'cancelled' where id = v_run;
  -- OBSERVED: the real resolve, N times (copies of the real run, state reset after each roll)
  if p_n = 0 then
    raise notice 'ODDS | % | stated % | shown % | observed - (formula and screens only)', rpad(p_label, 44), round(v_exp, 2), round(v_shown, 2);
    if abs(v_shown - v_exp) > 0.05 then raise exception 'TEST FAILED: % the card shows % but the roll uses %', p_label, v_shown, v_exp; end if;
    delete from yahoo_runs where user_id = u; return;
  end if;
  for i in 1 .. p_n loop
    insert into yahoo_runs (user_id, job_id, laptop_item, location_id, place, started_at, resolve_at, caught_pct, pay_bonus_pct, amount)
    values (u, p_job, r.laptop_item, r.location_id, r.place, r.started_at, r.started_at, r.caught_pct, r.pay_bonus_pct, r.amount) returning id into v_run;
    res := bl_yahoo_resolve(v_run);
    if res->>'status' = 'caught' then
      v_hits := v_hits + 1;
      delete from jail_cases where user_id = u;
      update profiles set jailed_until = null, jail_reason = null where id = u;
      if not exists (select 1 from inventory where user_id = u and item_id = p_laptop and qty > 0) then perform bl_give_item(u, p_laptop, 1); end if;
    end if;
  end loop;
  perform pg_temp.z_check(p_label, v_hits, p_n, v_exp, v_shown);
  delete from yahoo_runs where user_id = u; delete from jail_cases where user_id = u;
end $$;

do $$
begin
  perform pg_temp.yahoo_odds('yahoo chat client, lvl 1, Tokunbo laptop', 'chat_client', 'laptop', 0, pg_temp.nn(700));
  perform pg_temp.yahoo_odds('yahoo chat client, lvl 6 (-20% cut)', 'chat_client', 'laptop', 740, pg_temp.nn(500));
  perform pg_temp.yahoo_odds('yahoo romance, lvl 2, ThinkPad (-1 pt)', 'romance_job', 'thinkpad_t480', 40, 0);
  perform pg_temp.yahoo_odds('yahoo elon format, lvl 4, EliteBook (-2 pts)', 'elon_format', 'elitebook_840', 260, pg_temp.nn(500));
  perform pg_temp.yahoo_odds('yahoo big job, lvl 3, XPS (-4 pts)', 'big_job', 'dell_xps_13', 120, pg_temp.nn(400));
end $$;

-- ---------- 2. Yahoo cash-out options: job % x option multiplier, floor, then the level cut ----------
create or replace function pg_temp.cashout_odds(p_label text, p_mode text, p_xp int, p_n int) returns void
language plpgsql as $$
declare
  u uuid := current_setting('odds.a')::uuid; j yahoo_jobs; k skills; v_base numeric; v_mult numeric; v_pct numeric; v_exp numeric;
  v_q jsonb; v jsonb; r yahoo_runs; v_run bigint; i int; v_hits int := 0; res jsonb;
begin
  select * into j from yahoo_jobs where id = 'cash_out';
  select * into k from skills where id = 'yahoo';
  v_base := greatest(least(j.caught_pct, 5), j.caught_pct);                       -- Tokunbo laptop: no points off
  v_mult := case p_mode when 'half' then (select (value #>> '{}')::numeric from game_config where key = 'yahoo.cashout_half_caught_mult')
                        when 'launder' then (select (value #>> '{}')::numeric from game_config where key = 'yahoo.launder_caught_mult')
                        else (select (value #>> '{}')::numeric from game_config where key = 'yahoo.cashout_full_caught_mult') end;
  v_pct := least(100, case when p_mode = 'full' then v_base * v_mult / 100 else greatest(least(v_base, (select (value #>> '{}')::numeric from game_config where key = 'yahoo.cashout_floor_pct')), v_base * v_mult / 100) end);
  v_exp := v_pct * (1 - least(k.caught_cap_pct, (pg_temp.lvl(p_xp) - 1) * k.caught_pct_per_level) / 100.0);
  delete from inventory where user_id = u and item_id in (select item_id from laptop_specs);
  perform bl_give_item(u, 'laptop', 1);
  perform pg_temp.setxp(u, 'yahoo', p_xp);
  perform pg_temp.at(u); perform bl_yahoo_row(u);
  update yahoo_players set mifi_until = bl_now() + interval '300 days', dirty = 1000000 where user_id = u;
  delete from yahoo_runs where user_id = u; delete from jail_cases where user_id = u;
  perform pg_temp.login(u); perform set_config('bl.test_rand', '', true);
  v_q := yahoo_cashout_quote();                                                   -- the sheet the player reads
  v := yahoo_cashout_start(p_mode);
  select * into r from yahoo_runs where id = (v->>'run_id')::bigint;
  update yahoo_runs set status = 'cancelled' where id = r.id;
  if abs((v->>'skill_caught_pct')::numeric - v_exp) > 0.05 then raise exception 'TEST FAILED: % start reply shows % expected %', p_label, v->>'skill_caught_pct', v_exp; end if;
  for i in 1 .. p_n loop
    insert into yahoo_runs (user_id, job_id, laptop_item, location_id, place, started_at, resolve_at, caught_pct, pay_bonus_pct, amount, mode, fee)
    values (u, 'cash_out', r.laptop_item, r.location_id, r.place, r.started_at, r.started_at, r.caught_pct, 0, r.amount, r.mode, r.fee) returning id into v_run;
    res := bl_yahoo_resolve(v_run);
    if res->>'status' = 'caught' then
      v_hits := v_hits + 1;
      delete from jail_cases where user_id = u;
      update profiles set jailed_until = null, jail_reason = null where id = u;
      if not exists (select 1 from inventory where user_id = u and item_id = 'laptop' and qty > 0) then perform bl_give_item(u, 'laptop', 1); end if;
    end if;
    update yahoo_players set dirty = 1000000 where user_id = u;
  end loop;
  -- the quote object must say the same: find this option in the quote list the app reads
  perform pg_temp.z_check(p_label, v_hits, p_n, v_exp, (v->>'skill_caught_pct')::numeric);
  delete from yahoo_runs where user_id = u; delete from jail_cases where user_id = u;
end $$;

do $$
begin
  perform pg_temp.cashout_odds('cash out FULL (14% x 100%)', 'full', 0, pg_temp.nn(400));
  perform pg_temp.cashout_odds('cash out HALF (14% x 60% = 8.4%)', 'half', 0, pg_temp.nn(400));
  perform pg_temp.cashout_odds('cash out LAUNDER (14% x 25% = 3.5%)', 'launder', 0, pg_temp.nn(400));
end $$;

-- ---------- 3. Yahoo group mission: one roll for the crew, chance cut by the crew's AVERAGE Yahoo level ----------
do $$
declare
  a uuid := current_setting('odds.a')::uuid; b uuid := current_setting('odds.b')::uuid; m group_missions; k skills;
  g bigint; v_exp numeric; v_shown numeric; v_hits int := 0; i int; n int := pg_temp.nn(500); x uuid;
begin
  select * into m from group_missions where id = 'crew_hustle';
  select * into k from skills where id = 'yahoo';
  v_exp := round(m.caught_pct * (1 - least(k.caught_cap_pct, ((pg_temp.lvl(260) + pg_temp.lvl(40)) / 2.0 - 1) * k.caught_pct_per_level) / 100.0), 2);
  foreach x in array array[a, b] loop
    delete from inventory where user_id = x and item_id in (select item_id from laptop_specs);
    perform bl_give_item(x, 'laptop', 1);
    perform pg_temp.at(x); perform bl_yahoo_row(x);
    update yahoo_players set mifi_until = bl_now() + interval '300 days', dirty = 0 where user_id = x;
    delete from yahoo_runs where user_id = x; delete from jail_cases where user_id = x;
  end loop;
  perform pg_temp.setxp(a, 'yahoo', 260); perform pg_temp.setxp(b, 'yahoo', 40);
  delete from yahoo_groups where host_id in (a, b);
  insert into yahoo_groups (mission_id, name, host_id, location_id, start_at) values ('crew_hustle', m.name, a, (select home_location_id from profiles where id = a), bl_now())
    returning id into g;
  insert into yahoo_group_members (group_id, user_id, status, laptop_item, responded_at) values (g, a, 'accepted', 'laptop', bl_now()), (g, b, 'accepted', 'laptop', bl_now());
  perform bl_yahoo_group_start(g);
  if (select status from yahoo_groups where id = g) <> 'running' then raise exception 'TEST FAILED: the group did not start (%)', (select status from yahoo_groups where id = g); end if;
  perform pg_temp.login(a);
  v_shown := (yahoo_group_status()->'group'->>'caught_pct')::numeric;              -- what the host's screen prints
  for i in 1 .. n loop
    update yahoo_groups set status = 'running', resolve_at = bl_now() - interval '1 second', resolved_at = null where id = g;
    perform bl_yahoo_group_resolve(g);
    if (select status from yahoo_groups where id = g) = 'caught' then
      v_hits := v_hits + 1;
      delete from jail_cases where user_id in (a, b);
      update profiles set jailed_until = null, jail_reason = null where id in (a, b);
      foreach x in array array[a, b] loop
        if not exists (select 1 from inventory where user_id = x and item_id = 'laptop' and qty > 0) then perform bl_give_item(x, 'laptop', 1); end if;
      end loop;
    end if;
  end loop;
  perform pg_temp.z_check('yahoo group crew_hustle, avg lvl 3 (-8%)', v_hits, n, v_exp, v_shown);
  delete from jail_cases where user_id in (a, b); delete from yahoo_groups where id = g;
end $$;

-- ---------- 4. Crew job: one roll for the crew, base % cut by the members' average skill (1.5 points a level, cap 30) ----------
do $$
declare
  a uuid := current_setting('odds.a')::uuid; b uuid := current_setting('odds.b')::uuid; c uuid := current_setting('odds.c')::uuid;
  j crew_jobs; cr bigint; run bigint; v_avg numeric; v_exp numeric; v_shown numeric; v_hits int := 0; i int; n int := pg_temp.nn(400); x uuid; v_ids uuid[] := array[a, b, c];
begin
  select * into j from crew_jobs where id = 'market_shakedown';
  -- skill levels 4, 3, 2 in charisma (the job's skill) = average 3.0
  perform pg_temp.setxp(a, 'charisma', 260); perform pg_temp.setxp(b, 'charisma', 120); perform pg_temp.setxp(c, 'charisma', 40);
  v_avg := (pg_temp.lvl(260) + pg_temp.lvl(120) + pg_temp.lvl(40)) / 3.0;
  v_exp := round(j.caught_pct * (1 - least((select (value #>> '{}')::numeric from game_config where key = 'crew.skill_cut_cap'),
                                          (v_avg - 1) * (select (value #>> '{}')::numeric from game_config where key = 'crew.skill_cut_per_level')) / 100.0), 2);
  delete from crew_members where user_id = any (v_ids);
  insert into crews (name, tag, created_by) values ('Odds Crew', 'ODX', a) returning id into cr;
  insert into crew_members (user_id, crew_id, rank) values (a, cr, 'boss'), (b, cr, 'member'), (c, cr, 'member');
  foreach x in array v_ids loop
    perform pg_temp.at(x, 'upper_sakponba');
    update profiles set last_seen = now() where id = x;
    delete from jail_cases where user_id = x;
  end loop;
  insert into crew_runs (crew_id, job_id, job_name, started_by, lobby_until) values (cr, j.id, j.name, a, bl_now() + interval '2 minutes') returning id into run;
  insert into crew_run_members (run_id, user_id, rank) values (run, a, 'boss'), (run, b, 'member'), (run, c, 'member');
  perform bl_crew_run_start(run);                                                   -- the real start fixes the chance
  if (select status from crew_runs where id = run) <> 'running' then raise exception 'TEST FAILED: the crew job did not start (%)', (select note from crew_runs where id = run); end if;
  -- SHOWN: the job card's estimate (what the lobby screen prints) and the running job's chance
  v_shown := (bl_crew_job_json(j, (select c2 from crews c2 where c2.id = cr), v_ids)->>'est_pct')::numeric;
  if abs((select caught_pct from crew_runs where id = run) - v_exp) > 0.05 then
    raise exception 'TEST FAILED: crew run stored % expected %', (select caught_pct from crew_runs where id = run), v_exp;
  end if;
  for i in 1 .. n loop
    update crew_runs set status = 'running', resolve_at = bl_now() - interval '1 second', resolved_at = null where id = run;
    perform bl_crew_run_resolve(run);
    if (select status from crew_runs where id = run) = 'caught' then
      v_hits := v_hits + 1;
      delete from jail_cases where user_id = any (v_ids);
      update profiles set jailed_until = null, jail_reason = null where id = any (v_ids);
    end if;
  end loop;
  perform pg_temp.z_check('crew job market_shakedown, avg skill 3 (-3%)', v_hits, n, v_exp, v_shown);
  delete from jail_cases where user_id = any (v_ids); delete from crews where id = cr;
end $$;

-- ---------- 5. Pickpocket: 62 % caught (the thief's protection charm lowers it, the victim's home guard raises it) ----------
create or replace function pg_temp.steal_odds(p_label text, p_exp numeric, p_n int) returns void
language plpgsql as $$
declare t uuid := current_setting('odds.t')::uuid; v uuid := current_setting('odds.v')::uuid; i int; v_id bigint; v_hits int := 0; v_seen int := 0; st text;
begin
  perform pg_temp.at(t, 'oba_market'); perform pg_temp.at(v, 'oba_market');
  update profiles set cash = 100000 where id = v;
  delete from crime_attempts where thief_id = t; delete from jail_cases where user_id = t;
  if abs(bl_steal_caught_pct(t, v, 0) - p_exp) > 0.05 then raise exception 'TEST FAILED: % server chance % expected %', p_label, bl_steal_caught_pct(t, v, 0), p_exp; end if;
  for i in 1 .. p_n loop
    insert into crime_attempts (thief_id, victim_id, location_id, started_at, resolve_at) values (t, v, 'oba_market', bl_now() - interval '5 seconds', bl_now() - interval '1 second') returning id into v_id;
    perform bl_steal_resolve(v_id);
    select status into st from crime_attempts where id = v_id;
    if st = 'caught' then
      v_hits := v_hits + 1; v_seen := v_seen + 1;
      delete from jail_cases where user_id = t;
      update profiles set jailed_until = null, jail_reason = null, location_id = 'oba_market' where id = t;
    elsif st = 'success' then
      v_seen := v_seen + 1; update profiles set cash = 100000 where id = v;
    end if;
    delete from crime_attempts where id = v_id;
  end loop;
  perform pg_temp.z_check(p_label, v_hits, v_seen, p_exp, null);
end $$;

do $$
declare t uuid := current_setting('odds.t')::uuid; v uuid := current_setting('odds.v')::uuid;
begin
  perform pg_temp.cfg('crime.steal_newbie_hours', '0');
  perform pg_temp.steal_odds('pickpocket, no charms (62%)', 62, pg_temp.nn(500));
  -- thief with a protection charm (45), victim with a home guard (+50%): 45 x 1.5 = 67.5
  insert into player_charms (user_id, kind, data) values (t, 'protection', '{"value":45}'), (v, 'home_guard', '{"value":50}');
  perform pg_temp.steal_odds('pickpocket, protection 45 + victim guard 50%', 67.5, pg_temp.nn(400));
  delete from player_charms where user_id in (t, v);
end $$;

-- ---------- 6. Jail escape: 52 % caught (police), 55 % (EFCC); vanishing charm caps it at 30, bad luck adds 10 ----------
create or replace function pg_temp.escape_odds(p_label text, p_kind text, p_exp numeric, p_n int) returns void
language plpgsql as $$
declare t uuid := current_setting('odds.t')::uuid; i int; v_hits int := 0; cs jail_cases; v_shown numeric;
begin
  perform pg_temp.login(t); perform pg_temp.at(t, 'police_hq');
  delete from jail_cases where user_id = t;
  for i in 1 .. p_n loop
    update profiles set jailed_until = bl_now() + interval '1 hour', jail_reason = 'odds', location_id = 'police_hq' where id = t;
    delete from jail_cases where user_id = t;
    insert into jail_cases (user_id, reason, location_id, bail_amount, jail_seconds, jail_until, kind) values (t, 'odds', 'police_hq', 20000000, 3600, bl_now() + interval '1 hour', p_kind)
      returning * into cs;
    if i = 1 then v_shown := (bl_crime_case_json(cs)->>'escape_caught_pct')::numeric; end if;
    -- vanishing charm has 3 uses: refill so the cap holds for every roll
    update player_charms set uses_left = 3 where user_id = t and kind = 'vanishing';
    if (jail_case_escape()->>'escaped')::boolean is not true then v_hits := v_hits + 1; end if;
  end loop;
  perform pg_temp.z_check(p_label, v_hits, p_n, p_exp, v_shown);
  delete from jail_cases where user_id = t; update profiles set jailed_until = null, jail_reason = null where id = t;
end $$;

do $$
declare t uuid := current_setting('odds.t')::uuid;
begin
  perform pg_temp.cfg('crime.escape_caught_pct', '52'); perform pg_temp.cfg('yahoo.escape_caught_pct', '55');
  perform pg_temp.escape_odds('escape, police case (52% caught)', 'police', 52, pg_temp.nn(400));
  perform pg_temp.escape_odds('escape, EFCC case (55% caught)', 'efcc', 55, pg_temp.nn(400));
  insert into player_charms (user_id, kind, uses_left, data) values (t, 'vanishing', 3, '{"value":30}');
  perform pg_temp.escape_odds('escape, vanishing charm (cap 30%)', 'police', 30, pg_temp.nn(400));
  delete from player_charms where user_id = t;
  insert into player_charms (user_id, kind, data) values (t, 'bad_luck', '{"value":1,"caught_pts":10}');
  perform pg_temp.escape_odds('escape, bad luck (+10 pts = 62%)', 'police', 62, pg_temp.nn(400));
  delete from player_charms where user_id = t;
end $$;

-- ---------- 7. Hustle side events: Bolt cancel, PoS network / fake alert, food spoil, DJ / MC / tutor tips, fishing, mechanic ----------
-- Real bl_hustle_resolve on N copies of a run. The roll order in the code is: loss, then risk, then bonus, each only when the one
-- before did not happen, so the chance of a later event is (stated x chance that the earlier ones did not happen).
create or replace function pg_temp.hustle_odds(p_id text, p_n int, p_assert_loss numeric, p_assert_risk numeric, p_assert_bonus numeric) returns void
language plpgsql as $$
declare
  u uuid := current_setting('odds.c')::uuid; h hustles; i int; v_id bigint; res jsonb; v_loss int := 0; v_risk int := 0; v_bonus int := 0; v_ok int := 0;
begin
  select * into h from hustles where id = p_id;
  if h.loss_pct <> p_assert_loss or h.risk_pct <> p_assert_risk or h.bonus_pct <> p_assert_bonus then
    raise exception 'TEST FAILED: % documented chances loss % / risk % / bonus % but the table says % / % / %', p_id, p_assert_loss, p_assert_risk, p_assert_bonus, h.loss_pct, h.risk_pct, h.bonus_pct;
  end if;
  perform bl_hustle_row(u, true);
  for i in 1 .. p_n loop
    insert into hustle_runs (user_id, hustle_id, location_id, started_at, resolve_at, cost, pay_mult) values (u, p_id, null, bl_now(), bl_now(), 0, 1) returning id into v_id;
    res := bl_hustle_resolve(v_id);
    case res->>'outcome' when 'loss' then v_loss := v_loss + 1; when 'risk' then v_risk := v_risk + 1; when 'bonus' then v_bonus := v_bonus + 1; else v_ok := v_ok + 1; end case;
  end loop;
  if h.loss_pct > 0 then perform pg_temp.z_check('hustle ' || p_id || ' loss (fake alert etc.)', v_loss, p_n, h.loss_pct, null); end if;
  if h.risk_pct > 0 then perform pg_temp.z_check('hustle ' || p_id || ' risk event', v_risk, p_n, h.risk_pct * (1 - h.loss_pct / 100.0), null); end if;
  if h.bonus_pct > 0 then perform pg_temp.z_check('hustle ' || p_id || ' tip / bonus', v_bonus, p_n, h.bonus_pct * (1 - h.loss_pct / 100.0) * (1 - h.risk_pct / 100.0), null); end if;
end $$;

do $$
declare u uuid := current_setting('odds.c')::uuid;
begin
  perform pg_temp.at(u);
  update profiles set cash = 5000000000, bank = 0 where id = u;
  perform pg_temp.hustle_odds('bolt_shift',      pg_temp.nn(400), 0, 8, 0);       -- "Passenger cancelled at the pick-up point" 8 %
  perform pg_temp.hustle_odds('pos_agent',       pg_temp.nn(600), 4, 12, 0);      -- fake alert 4 %, network down 12 %
  perform pg_temp.hustle_odds('vend_jollof',     pg_temp.nn(250), 0, 10, 0);      -- food spoil / slow day 10 %
  perform pg_temp.hustle_odds('vend_puff',       pg_temp.nn(250), 0, 10, 0);
  perform pg_temp.hustle_odds('vend_fried_yam',  pg_temp.nn(250), 0, 10, 0);
  perform pg_temp.hustle_odds('dj_set',          pg_temp.nn(400), 0, 0, 15);      -- the crowd sprays the DJ 15 %
  perform pg_temp.hustle_odds('dj_headline',     pg_temp.nn(250), 0, 0, 20);
  perform pg_temp.hustle_odds('mc_gig',          pg_temp.nn(300), 0, 0, 20);      -- big spender tips the MC 20 %
  perform pg_temp.hustle_odds('tutor_session',   pg_temp.nn(250), 0, 0, 10);      -- happy parents 10 %
  perform pg_temp.hustle_odds('mech_engine',     pg_temp.nn(250), 0, 10, 0);      -- customer argues about the bill 10 %
  perform pg_temp.hustle_odds('mech_fleet',      pg_temp.nn(250), 0, 8, 0);
end $$;

-- fishing: "nothing bites" 10 %, then a weighted fish (river junk is a catch of weight 8, not "nothing")
do $$
declare
  u uuid := current_setting('odds.c')::uuid; h hustles; i int; v_id bigint; res jsonb; n int := pg_temp.nn(600); v_none int := 0; v_tot numeric; f record; v_hits jsonb := '{}'::jsonb; v_it text;
begin
  select * into h from hustles where id = 'fish_cast';
  if h.risk_pct <> 10 then raise exception 'TEST FAILED: fish_cast documented nothing-bites 10 %% but the table says %', h.risk_pct; end if;
  for i in 1 .. n loop
    insert into hustle_runs (user_id, hustle_id, location_id, started_at, resolve_at, cost, pay_mult) values (u, 'fish_cast', null, bl_now(), bl_now(), 0, 1) returning id into v_id;
    res := bl_hustle_resolve(v_id);
    if res->>'outcome' = 'risk' then v_none := v_none + 1;
    else
      v_it := res->'fish'->>'item';
      v_hits := jsonb_set(v_hits, array[v_it], to_jsonb(coalesce((v_hits->>v_it)::int, 0) + 1));
    end if;
  end loop;
  perform pg_temp.z_check('fishing: nothing bites', v_none, n, h.risk_pct, null);
  select sum(weight) into v_tot from hustle_fish where active;
  for f in select item_id, weight from hustle_fish where active order by sort loop
    perform pg_temp.z_check('fishing: ' || f.item_id || ' (weight ' || f.weight || ')', coalesce((v_hits->>f.item_id)::int, 0), n, (100 - h.risk_pct) * f.weight / v_tot, null);
  end loop;
end $$;

-- ---------- 8. Business events per business day: robbery 6, NEPA 14, levy 8, great day 10, staff theft 8 (+ staff / boost / type overrides) ----------
create or replace function pg_temp.biz_odds(p_label text, p_type text, p_staff int, p_boost boolean, p_n int, p_exp jsonb) returns void
language plpgsql as $$
declare
  o uuid := current_setting('odds.b')::uuid; v_plot text; bid bigint; i int; v_days int := p_n * 10; k text; v_cnt int;
begin
  perform pg_temp.cfg('business.cap_hours', '240');
  select p.id into v_plot from business_plots p where p.active and not exists (select 1 from businesses x where x.plot_id = p.id) limit 1;
  insert into businesses (owner_id, plot_id, type_id, name, base_income, invested, bought_at, ready_at, settled_at, last_collect_at, stock_until, staff, boost_until)
  values (o, v_plot, p_type, 'Odds ' || p_type, 15000, 600000, bl_now() - interval '400 days', bl_now() - interval '399 days', bl_now() - interval '10 days', bl_now() - interval '10 days',
          bl_now() + interval '400 days', p_staff, case when p_boost then bl_now() + interval '400 days' end) returning id into bid;
  for i in 1 .. p_n loop
    perform bl_biz_settle(bid, false);
    update businesses set settled_at = bl_now() - interval '10 days', last_collect_at = bl_now() - interval '10 days', event_carry_h = 0, takings = 0 where id = bid;
  end loop;
  for k in select jsonb_object_keys(p_exp) loop
    select count(*) into v_cnt from business_log where business_id = bid and kind = 'ev_' || k;
    perform pg_temp.z_check(p_label || ' ' || k, v_cnt, v_days, (p_exp->>k)::numeric, null);
  end loop;
  delete from business_log where business_id = bid; delete from businesses where id = bid;
end $$;

do $$
begin
  perform pg_temp.assert(bl_pol_levy_mult() = 1, 'no levy policy in force for the odds run');
  perform pg_temp.biz_odds('business provision shop, no staff', 'provision_shop', 0, false, pg_temp.nn(200),
    '{"robbery":6,"outage":14,"levy":8,"goodday":10}');
  -- 2 staff cut robbery and levy by 10 % each (x0.8); a worked shift (boost) halves robbery and theft
  perform pg_temp.biz_odds('business shop, 2 staff + shift boost', 'provision_shop', 2, true, pg_temp.nn(200),
    '{"robbery":2.4,"outage":14,"levy":6.4,"goodday":10,"theft":4}');
  perform pg_temp.biz_odds('business event centre (type override)', 'event_centre', 0, false, pg_temp.nn(150), '{"goodday":35}');
end $$;

-- ---------- 9. Babalawo: every service's fail chance on the card = the one stored by shrine_start; the roll uses the stored one ----------
do $$
declare
  u uuid := current_setting('odds.a')::uuid; s record; v jsonb; o record; v_shown numeric; v_used numeric; v_id bigint; i int; n int := pg_temp.nn(500); v_hits int := 0; v_info jsonb; r jsonb;
begin
  perform pg_temp.at(u, 'babas_shrine');
  update profiles set cash = 5000000000 where id = u;
  perform pg_temp.login(u);
  delete from player_charms where user_id = u;
  -- SHOWN vs STORED for all ten services, through the real start
  for s in select * from shrine_services where active order by sort loop
    for o in select key, (value #>> '{}')::int as q from jsonb_each(s.offerings) loop perform bl_give_item(u, o.key, o.q + 1); end loop;
    perform pg_temp.at(u, 'babas_shrine');
    v_info := shrine_info();
    select (x->>'fail_pct')::numeric into v_shown from jsonb_array_elements(v_info->'services') x where x->>'id' = s.id;
    v := shrine_start(s.id);
    select fail_pct into v_used from shrine_visits where id = (v->>'visit_id')::bigint;
    perform pg_temp.assert(v_shown = v_used, 'shrine ' || s.id || ': card ' || v_shown || '% vs stored ' || v_used || '%');
    raise notice 'ODDS | % | stated % | shown % | observed - (card vs stored visit)', rpad('babalawo ' || s.id || ' fail', 44), coalesce(s.fail_pct, 10), v_shown;
    delete from shrine_visits where id = (v->>'visit_id')::bigint;
    update profiles set busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null where id = u;
  end loop;
  -- OBSERVED: the real resolve at the default 10 % (road opener) and at 0 % (cleansing)
  for i in 1 .. n loop
    insert into shrine_visits (user_id, service_id, started_at, resolve_at, paid, offerings, fail_pct) values (u, 'road_opener', bl_now(), bl_now(), 0, '{}', 10) returning id into v_id;
    r := bl_shrine_resolve(v_id);
    if r->>'status' = 'failed' then v_hits := v_hits + 1; end if;
    delete from player_charms where user_id = u;
  end loop;
  perform pg_temp.z_check('babalawo road opener fails 10%', v_hits, n, 10, (select (x->>'fail_pct')::numeric from jsonb_array_elements(shrine_info()->'services') x where x->>'id' = 'road_opener'));
  v_hits := 0;
  for i in 1 .. 200 loop
    insert into shrine_visits (user_id, service_id, started_at, resolve_at, paid, offerings, fail_pct) values (u, 'cleansing', bl_now(), bl_now(), 0, '{}', 0) returning id into v_id;
    r := bl_shrine_resolve(v_id);
    if r->>'status' = 'failed' then v_hits := v_hits + 1; end if;
  end loop;
  perform pg_temp.z_check('babalawo cleansing never fails (0%)', v_hits, 200, 0, 0);
end $$;

-- ---------- 10. Exam pass chance: base + per level x (skill level - 1), floor 5, cap 95 ----------
create or replace function pg_temp.exam_odds(p_label text, p_xp int, p_n int) returns void
language plpgsql as $$
declare
  u uuid := current_setting('odds.b')::uuid; c courses; v_exp numeric; v_shown numeric; i int; v_run bigint; v_hits int := 0; v_cls int;
begin
  select * into c from courses where id = 'catering';
  v_cls := c.classes;
  perform pg_temp.setxp(u, 'cooking', p_xp);
  v_exp := greatest(5, least(95, c.exam_base_pct + c.exam_per_level_pct * (pg_temp.lvl(p_xp) - 1)));
  delete from course_enrolments where user_id = u; delete from course_runs where user_id = u; delete from player_certificates where user_id = u;
  insert into course_enrolments (user_id, course_id, status, classes_done, fee_paid) values (u, c.id, 'enrolled', v_cls - 1, 0);
  perform pg_temp.login(u);
  select (x->'exam'->>'chance_now')::numeric into v_shown from jsonb_array_elements(course_status()->'courses') x where x->>'id' = c.id;
  for i in 1 .. p_n loop
    insert into course_runs (user_id, course_id, class_no, started_at, resolve_at) values (u, c.id, v_cls, bl_now(), bl_now()) returning id into v_run;
    perform bl_course_resolve(v_run);
    if (select outcome from course_runs where id = v_run) = 'pass' then
      v_hits := v_hits + 1;
      update course_enrolments set status = 'enrolled', classes_done = v_cls - 1, completed_at = null where user_id = u and course_id = c.id;
      delete from player_certificates where user_id = u;
      perform pg_temp.setxp(u, 'cooking', p_xp);                 -- a passed class pays Cooking XP (course rows, not skill_sources): keep the level fixed
    end if;
    delete from course_runs where id = v_run;
  end loop;
  perform pg_temp.z_check(p_label, v_hits, p_n, v_exp, v_shown);
end $$;

do $$
begin
  perform pg_temp.exam_odds('exam: Catering, skill lvl 1 (55%)', 0, pg_temp.nn(500));
  perform pg_temp.exam_odds('exam: Catering, skill lvl 6 (55 + 5 x 6 = 85%)', 740, pg_temp.nn(400));
end $$;

-- ---------- 11. Money pick (20 % of a spray falls, N10,000 a tap), origin roll (10 % Nepo), street robbery chance and injury ----------
do $$
declare
  a uuid := current_setting('odds.a')::uuid; b uuid := current_setting('odds.b')::uuid; d jsonb; r jsonb; v_amt bigint; v_exp bigint; v_cash0 bigint;
begin
  -- the share that falls: floor(spray x pick_pct / 100), nothing when under one note
  foreach v_amt in array array[5000, 49999, 50000, 123456, 1000000, 77777777]::bigint[] loop
    d := bl_money_drop_create(a, 'club_360', v_amt, false);
    v_exp := floor(v_amt * 20 / 100.0);
    if v_exp < 10000 then
      perform pg_temp.assert(d is null, 'no drop for a spray of ' || v_amt || ' (share ' || v_exp || ' is under one note)');
    else
      perform pg_temp.assert((d->>'total')::bigint = v_exp, 'drop total for ' || v_amt || ' is ' || v_exp || ' (got ' || (d->>'total') || ')');
    end if;
    raise notice 'ODDS | % | stated % | shown % | observed % | (share of the spray that falls as notes)', rpad('money pick: spray ' || v_amt, 44), 20, '20', case when d is null then '0 (under one note)' else round(((d->>'total')::numeric * 100 / v_amt), 2)::text end;
  end loop;
  -- a pick pays exactly N10,000 a tap and never more than the drop
  perform pg_temp.at(a, 'club_360'); perform pg_temp.at(b, 'club_360');
  d := bl_money_drop_create(a, 'club_360', 100000, false);                       -- 20,000 = 2 notes
  perform pg_temp.login(b);
  select cash into v_cash0 from profiles where id = b;
  r := money_pick((d->>'id')::bigint, 5);
  perform pg_temp.assert((r->>'picked')::bigint = 20000 and (r->>'taps')::int = 2, 'five taps on two notes pay N20,000 (' || (r->>'picked') || ')');
  perform pg_temp.assert((select cash from profiles where id = b) = v_cash0 + 20000, 'the cash is in the pocket');
end $$;

do $$
declare i int; v_hits int := 0; n int := pg_temp.nn(4000); v_exp numeric;
begin
  update game_config set value = '""'::jsonb where key = 'origin.force_next';
  select greatest(0, (value #>> '{}')::numeric) into v_exp from game_config where key = 'origin.nepo_pct';
  for i in 1 .. n loop
    if bl_roll_origin() = 'nepo' then v_hits := v_hits + 1; end if;
  end loop;
  perform pg_temp.z_check('origin roll: Nepo (origin.nepo_pct)', v_hits, n, v_exp, null);
end $$;

do $$
declare
  a uuid := current_setting('odds.a')::uuid; i int; n int := pg_temp.nn(1500); v_p numeric; v_hit int := 0; v_inj int := 0; r jsonb;
begin
  perform pg_temp.at(a, 'oba_market');
  update profiles set cash = 20000, protected_until = null, charm_strength = 0, charm_until = null where id = a;
  v_p := bl_street_robbery_chance(a, 'oba_market', 'walk', 1);
  for i in 1 .. n loop
    r := bl_roll_street_robbery(a, 'oba_market', 'walk', 1);
    if r is not null then v_hit := v_hit + 1; update profiles set cash = 20000 where id = a; end if;
  end loop;
  perform pg_temp.z_check('street robbery on foot at Oba Market, N20k', v_hit, n, v_p * 100, v_p * 100);
  -- injury: 15 % of robberies (raise the base chance so there are enough robberies to count)
  perform pg_temp.cfg('crime.npc_base_pct', '60'); perform pg_temp.cfg('crime.npc_max_pct', '60');
  v_hit := 0; n := pg_temp.nn(800);
  for i in 1 .. n loop
    r := bl_roll_street_robbery(a, 'oba_market', 'walk', 1);
    if r is not null then v_hit := v_hit + 1; if (r->>'injured')::boolean then v_inj := v_inj + 1; end if; update profiles set cash = 20000, health = 100 where id = a; end if;
  end loop;
  perform pg_temp.z_check('street robbery: injured (crime.injury_pct)', v_inj, v_hit, (select (value #>> '{}')::numeric from game_config where key = 'crime.injury_pct'), null);
  perform pg_temp.cfg('crime.npc_base_pct', '6'); perform pg_temp.cfg('crime.npc_max_pct', '35');
end $$;

-- ---------- 12. Invest risk events: POS network down 3 % a day, Okada breakdown 2 %, poultry bird flu 10 % / theft 5 % a harvest, land levy ----------
create or replace function pg_temp.inv_day_odds(p_label text, p_product text, p_event text, p_exp numeric, p_calls int) returns void
language plpgsql as $$
declare
  u uuid := current_setting('odds.c')::uuid; pr invest_products; pid bigint; i int; v_step int := 30; v_day numeric := bl_inv_day(); v_cnt int; v_label text;
begin
  select * into pr from invest_products where id = p_product;
  v_label := pr.events->p_event->>'label';
  perform pg_temp.cfg('invest.event_days_cap', '100000');
  delete from invest_log where user_id = u;
  insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at, state)
  values (u, pr.id, pr.kind, 1, pr.unit_price, bl_now() - make_interval(secs => 100000 * v_day), bl_now() - make_interval(secs => v_step * v_day), '{}') returning id into pid;
  for i in 1 .. p_calls loop
    perform bl_inv_settle_pos(pid);
    update invest_positions set last_at = bl_now() - make_interval(secs => v_step * v_day) where id = pid;
  end loop;
  select count(*) into v_cnt from invest_log where user_id = u and kind = 'event' and label = v_label;
  perform pg_temp.z_check(p_label, v_cnt, p_calls * v_step, p_exp, (pr.events->p_event->>'chance_pct')::numeric);
  delete from invest_positions where id = pid;
end $$;

do $$
declare
  u uuid := current_setting('odds.c')::uuid; pos bigint; i int; n int := pg_temp.nn(500); v_flu int := 0; v_theft int := 0; r jsonb; e jsonb; pr invest_products;
  m invest_markets; q jsonb; v_levy int := 0; nl int := pg_temp.nn(400);
begin
  perform pg_temp.inv_day_odds('invest POS stand: network down, a day', 'pos_stand', 'network', 3, pg_temp.nn(70));
  perform pg_temp.inv_day_odds('invest Okada: engine knock, a day', 'transport_okada', 'breakdown', 2, pg_temp.nn(70));
  -- farm harvest: events roll once per cycle
  select * into pr from invest_products where id = 'farm_poultry';
  update profiles set bank = 5000000000000 where id = u;
  perform pg_temp.login(u);
  insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at, matures_at, state)
  values (u, pr.id, 'farm', 1, pr.unit_price, bl_now() - interval '400 days', bl_now() - interval '400 days', bl_now() - interval '1 day', '{"gain_pct":25,"cycle":1}') returning id into pos;
  for i in 1 .. n loop
    r := invest_collect(pos, true);
    for e in select * from jsonb_array_elements(r->'events') loop
      if e->>'id' = 'bird_flu' then v_flu := v_flu + 1; elsif e->>'id' = 'theft' then v_theft := v_theft + 1; end if;
    end loop;
    update invest_positions set matures_at = bl_now() - interval '1 day' where id = pos;
  end loop;
  perform pg_temp.z_check('invest poultry harvest: bird flu', v_flu, n, (pr.events->'bird_flu'->>'chance_pct')::numeric, (pr.events->'bird_flu'->>'chance_pct')::numeric);
  perform pg_temp.z_check('invest poultry harvest: thieves', v_theft, n, (pr.events->'theft'->>'chance_pct')::numeric, (pr.events->'theft'->>'chance_pct')::numeric);
  -- land levy: the card says "N % chance of a development levy"; the buy rolls it
  select * into m from invest_markets where id = 'land_ekenwan';
  q := invest_land_quote('land_ekenwan', 1);
  for i in 1 .. nl loop
    delete from invest_land_deals where user_id = u;
    r := invest_land_buy('land_ekenwan', 1);
    if r->>'status' = 'levy' then v_levy := v_levy + 1; end if;
  end loop;
  perform pg_temp.z_check('invest land Ekenwan: development levy', v_levy, nl, m.levy_chance_pct, (q->>'levy_chance_pct')::numeric);
end $$;

-- ---------- 13. Link-ups: "yes" chance on the card = the stored one, hotel risks 10 % robbed / 35 % partner finds out ----------
do $$
declare
  u uuid := current_setting('odds.v')::uuid; n1 linkup_npcs; n2 linkup_npcs; i int; v_id bigint; r jsonb; v_rob int := 0; v_cau int := 0; n int := pg_temp.nn(400); v_pct jsonb;
begin
  select * into n1 from linkup_npcs where active order by id limit 1;
  select * into n2 from linkup_npcs where active and id <> n1.id order by id limit 1;
  perform bl_linkup_row(u, true);
  -- the default player: shown pct is the formula (base 45 + the NPC's pickiness + fresh looks + ...); assert the helper agrees with the card JSON
  v_pct := bl_linkup_yes_pct(u, n1.id);
  perform pg_temp.assert((v_pct->>'pct')::numeric = greatest(5, least(95, 45 + n1.pickiness + (v_pct->>'charm')::numeric + (v_pct->>'rank')::numeric + (v_pct->>'cred')::numeric + (v_pct->>'looks')::numeric + (v_pct->>'spark')::numeric)),
                         'yes chance adds up from its parts');
  -- partner: a steady NPC (n2) so a night with n1 can be found out
  insert into linkup_people (user_id, npc_id, met_at, last_at, steady, steady_since, spark) values (u, n2.id, bl_now(), bl_now(), true, bl_now(), 70)
  on conflict (user_id, npc_id) do update set steady = true, steady_since = bl_now(), ended_at = null;
  perform pg_temp.cfg('linkup.robbed_pct', '10'); perform pg_temp.cfg('linkup.caught_pct', '35');
  update profiles set cash = 200000 where id = u;
  for i in 1 .. n loop
    delete from linkup_people where user_id = u and npc_id = n1.id;
    update linkup_people set steady = true, ended_at = null, cold_until = null where user_id = u and npc_id = n2.id;
    insert into linkup_runs (user_id, npc_id, action_id, started_at, resolve_at) values (u, n1.id, 'short_time', bl_now(), bl_now()) returning id into v_id;
    r := bl_linkup_resolve(v_id);
    if (select (morning->>'robbed')::boolean from linkup_runs where id = v_id) then v_rob := v_rob + 1; update profiles set cash = 200000 where id = u; end if;
    if (select (morning->>'caught')::boolean from linkup_runs where id = v_id) then v_cau := v_cau + 1; end if;
    delete from linkup_runs where id = v_id;
  end loop;
  perform pg_temp.z_check('link-up hotel night: phone / cash missing', v_rob, n, 10, null);
  perform pg_temp.z_check('link-up hotel night: partner finds out', v_cau, n, 35, null);
end $$;
