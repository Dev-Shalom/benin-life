-- R5 Daily and weekly challenges (20261018000200_challenges.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/challenges_test.sql
-- Time moves with bl.test_offset_seconds (a hustle needs the mechanic village open; the next day / Monday are jumped to); rolls are pinned with bl.test_rand.
-- Groups: 1 grants + RLS + helpers private · 2 seeds and settings · 3 deterministic assignment (same player + period = same set, every set is
-- doable) · 4 gating skip (certificate, skill, job, friends) · 5 progress from a hustle, a career shift and earnings · 6 complete + claim once
-- (cash, career XP, skill XP, item) · 7 reroll limit · 8 chests · 9 reset on the next day and the next week · 10 rewards are not weekly earnings
-- · 11 the other goals (places, DMs, streak, skill level, shop, fish, friends) · 12 the no-op path, master switch, reward multiplier, admin spec.
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

-- jump to 10:00 on the next Monday (Benin time): the weekly boundary
create or replace function pg_temp.next_week() returns void
language plpgsql as $$
begin
  perform pg_temp.advance(extract(epoch from (bl_week_from(bl_week_start() + 7) + interval '10 hours' - bl_now())));
end $$;

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.u(p_name text) returns uuid
language sql as $$ select current_setting('r5.' || p_name)::uuid; $$;

create or replace function pg_temp.cash(p_uid uuid) returns bigint
language sql as $$ select cash from profiles where id = p_uid; $$;

create or replace function pg_temp.at(p_uid uuid, p_loc text default null) returns void
language sql as $$
  update profiles set location_id = coalesce(p_loc, home_location_id), travel_to = null, travel_mode = null, travel_started_at = null,
                      travel_arrives_at = null, busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = bl_now(), rent_due_at = null, energy = 100, hunger = 100, hygiene = 100, stress = 0, needs_updated_at = bl_now()
   where id = p_uid;
$$;

-- start, wait out the timer, finish with a pinned roll
create or replace function pg_temp.hrun(p_uid uuid, p_id text, p_rand text default '0.9999999') returns jsonb
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

-- only these templates are active; every player's challenge rows, chests and rerolls are cleared
create or replace function pg_temp.only(p_ids text[]) returns void
language plpgsql as $$
begin
  update challenge_templates set active = (id = any (p_ids));
  delete from player_challenges; delete from challenge_chests; delete from challenge_rerolls; delete from events where kind = 'challenge_done';
end $$;

create or replace function pg_temp.tpl(p_id text, p_kind text, p_goal text, p_target bigint, p_cash bigint, p_weight numeric default 10,
                                       p_param text default null, p_needs text default null) returns void
language sql as $$
  insert into challenge_templates (id, kind, goal, title, blurb, icon, target, param, needs, reward_cash, weight, sort)
  values (p_id, p_kind, p_goal, 'T ' || p_id, 'test', '🎯', p_target, p_param, p_needs, p_cash, p_weight, 0)
  on conflict (id) do update set kind = excluded.kind, goal = excluded.goal, target = excluded.target, param = excluded.param, needs = excluded.needs,
    reward_cash = excluded.reward_cash, weight = excluded.weight, active = true, min_skill = null, min_skill_level = 1, req_cert = null,
    reward_xp = 0, reward_skill = null, reward_skill_xp = 0, reward_item = null;
$$;

-- the caller's challenge for a template: jsonb item from challenge_status()
create or replace function pg_temp.item(p_uid uuid, p_kind text, p_tpl text) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.login(p_uid);
  v := challenge_status();
  return (select x from jsonb_array_elements(v->p_kind->'items') x where x->>'template' = p_tpl);
end $$;

create or replace function pg_temp.prog(p_uid uuid, p_kind text, p_tpl text) returns bigint
language sql as $$
  select progress from player_challenges where user_id = p_uid and kind = p_kind and template_id = p_tpl and period = bl_chal_period(p_kind);
$$;

create or replace function pg_temp.ids(p_uid uuid, p_kind text) returns text[]
language sql as $$
  select coalesce(array_agg(template_id order by template_id), '{}') from player_challenges where user_id = p_uid and kind = p_kind and period = bl_chal_period(p_kind);
$$;

do $$
declare
  v_names text[] := array['adm', 'a', 'b', 'c', 'd'];
  n text; u uuid;
begin
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  foreach n in array v_names loop
    u := pg_temp.new_user('r5_' || n || '@rr.bl');
    perform set_config('r5.' || n, u::text, true);
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    perform pg_temp.login(u);
    perform create_profile_v2('R5_' || upper(n), 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home('ekenwan_face_me');
    perform pg_temp.at(u);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
  update profiles set created_at = now() - interval '30 days', protected_until = null, cash = 500000, bank = 0, traits = '{}'
   where username like 'R5\_%';
  delete from inventory where user_id in (select id from profiles where username like 'R5\_%');
  perform pg_temp.cfg('skills.enabled', 'true');
  perform pg_temp.cfg('skills.xp_mult', '1');
  perform pg_temp.cfg('school.enabled', 'true');
  perform pg_temp.cfg('hustles.enabled', 'true');
  perform pg_temp.cfg('hustles.min_energy', '10');
  perform pg_temp.cfg('places.hours_enabled', 'true');
  perform pg_temp.cfg('yahoo.enabled', 'true');
  perform pg_temp.cfg('challenges.enabled', 'true');
  perform pg_temp.cfg('challenges.daily_count', '3');
  perform pg_temp.cfg('challenges.weekly_count', '3');
  perform pg_temp.cfg('challenges.rerolls_per_day', '1');
  perform pg_temp.cfg('challenges.rerolls_per_week', '0');
  perform pg_temp.cfg('challenges.reward_mult', '1');
  perform pg_temp.cfg('challenges.daily_chest_cash', '3000');
  perform pg_temp.cfg('challenges.daily_chest_xp', '20');
  perform pg_temp.cfg('challenges.daily_chest_item', '"energy_drink"');
  perform pg_temp.cfg('challenges.weekly_chest_cash', '20000');
  perform pg_temp.cfg('challenges.weekly_chest_xp', '100');
  perform pg_temp.cfg('challenges.weekly_chest_item', '"kada_chicken"');
  update hustles set active = true;
  -- a friendship between a and b (accepted)
  perform pg_temp.login(pg_temp.u('a'));
  perform social_add_friend(pg_temp.u('b'));
  perform pg_temp.login(pg_temp.u('b'));
  perform social_respond_friend(pg_temp.u('a'), true);
  -- the Benin clock reads 10:00 (the mechanic village is open 7 to 19)
  perform pg_temp.to_hour(10);
end $$;

-- ---------- 1. grants + RLS + helpers private ----------
do $$
declare v_rpc text; a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); v_n int;
begin
  foreach v_rpc in array array['challenge_status()', 'challenge_claim(bigint)', 'challenge_claim_chest(text)', 'challenge_reroll(bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'auth may ' || v_rpc);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v_rpc)::regprocedure), 'secdef ' || v_rpc);
  end loop;
  foreach v_rpc in array array['bl_chal_on()', 'bl_chal_num(text,numeric)', 'bl_chal_period(text)', 'bl_chal_ends(text,date)', 'bl_chal_count(text)',
      'bl_chal_rerolls_max(text)', 'bl_chal_friend_at(uuid,text)', 'bl_chal_has_friend(uuid)', 'bl_chal_can(uuid,public.challenge_templates)',
      'bl_chal_candidates(uuid,text,text,text[])', 'bl_chal_insert(uuid,public.challenge_templates,date,integer)', 'bl_challenge_assign(uuid)',
      'bl_chal_open(uuid,text)', 'bl_chal_done(public.player_challenges)', 'bl_challenge_bump(uuid,text,bigint,text)', 'bl_chal_skill_xp(uuid,text,integer)',
      'bl_chal_pay(uuid,bigint,integer,text,integer,text,integer,jsonb)', 'bl_chal_json(public.player_challenges,integer)',
      'bl_chal_chest_json(uuid,text,date)', 'bl_chal_on_ledger()', 'bl_chal_on_hustle()', 'bl_chal_on_class()', 'bl_chal_on_yahoo()', 'bl_chal_on_skill()',
      'bl_chal_on_profile()', 'bl_chal_on_message()', 'bl_chal_on_streak()', 'bl_chal_on_invite()'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'helper private ' || v_rpc);
  end loop;
  -- the patched live functions kept their grants
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_earn_reasons()'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_admin_table_spec(text)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_ledger_label(text,jsonb)'::regprocedure, 'execute'),
                         'patched helpers stay private');
  -- tables: RLS on, players read their own rows only, no client writes, templates are not readable at all
  perform pg_temp.assert((select bool_and(relrowsecurity) from pg_class where oid in ('public.challenge_templates'::regclass, 'public.player_challenges'::regclass,
                          'public.challenge_chests'::regclass, 'public.challenge_rerolls'::regclass)), 'RLS on all four tables');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.challenge_templates', 'select')
                         and not has_table_privilege('anon', 'public.challenge_templates', 'select'), 'templates private');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.challenge_template_stats', 'select')
                         and not has_table_privilege('anon', 'public.challenge_template_stats', 'select'), 'stats view private');
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.player_challenges', 'select')
                         and not has_table_privilege('anon', 'public.player_challenges', 'select')
                         and not has_table_privilege('authenticated', 'public.player_challenges', 'insert')
                         and not has_table_privilege('authenticated', 'public.player_challenges', 'update')
                         and not has_table_privilege('authenticated', 'public.player_challenges', 'delete'), 'player_challenges: own select only');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.challenge_chests', 'insert') and not has_table_privilege('authenticated', 'public.challenge_rerolls', 'update'),
                         'chests and rerolls are read-only');
  perform pg_temp.login(a);
  perform challenge_status();
  perform pg_temp.login(b);
  perform challenge_status();
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', a::text, true);
  select count(*) into v_n from public.player_challenges;
  perform pg_temp.assert(v_n = 6 and not exists (select 1 from public.player_challenges where user_id <> a), 'RLS: a sees only their own 6 rows');
  select count(*) into v_n from public.challenge_chests;
  perform pg_temp.assert(v_n = 0, 'RLS: no chests yet');
  reset role;
  perform pg_temp.assert(pg_temp.hint_of('select challenge_status()') = 'ok', 'a signed-in player can call challenge_status');
  raise notice 'ok 1: grants, RLS, helpers private';
end $$;

-- ---------- 2. seeds and settings ----------
do $$
begin
  perform pg_temp.assert((select count(*) from challenge_templates where kind = 'daily' and id like 'd\_%') >= 30, 'about 30 daily templates');
  perform pg_temp.assert((select count(*) from challenge_templates where kind = 'weekly' and id like 'w\_%') >= 12, 'about 12 weekly templates');
  perform pg_temp.assert((select count(distinct goal) from challenge_templates) = 17, 'all 17 goal types are seeded');
  perform pg_temp.assert((select count(*) from challenge_templates where friends) >= 5, 'friend goals are seeded');
  perform pg_temp.assert((select bool_and(title <> '' and blurb <> '' and icon <> '' and reward_cash >= 0 and weight > 0) from challenge_templates where id ~ '^[dw]_'),
                         'seeds have copy, icon, weight');
  perform pg_temp.assert((select count(*) from game_config where key like 'challenges.%' and category = 'challenges' and label <> '' and description <> '') >= 13,
                         'settings labelled');
  perform pg_temp.assert(bl_cfg('challenges.daily_count') = 3 and bl_cfg('challenges.rerolls_per_day') = 1, 'defaults: 3 a day, 1 reroll');
  perform pg_temp.assert(exists (select 1 from items where id = bl_cfg_text('challenges.weekly_chest_item')) and exists (select 1 from items where id = bl_cfg_text('challenges.daily_chest_item')),
                         'chest items exist');
  perform pg_temp.assert(bl_ledger_label('challenge', '{"title":"Hustle week"}') = 'Challenge: Hustle week', 'ledger label');
  perform pg_temp.assert(bl_ledger_label('challenge', '{"chest":"daily","title":"Daily chest"}') = 'Challenge: Daily chest', 'chest ledger label');
  perform pg_temp.assert(not ('challenge' = any (bl_earn_reasons())), 'challenge is not an earning reason');
  raise notice 'ok 2: seeds and settings';
end $$;

-- ---------- 3. deterministic assignment ----------
do $$
declare
  a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); c uuid := pg_temp.u('c'); d uuid := pg_temp.u('d');
  v jsonb; v_d text[]; v_w text[]; v_d2 text[]; v_w2 text[]; i int; v_other int := 0; v_ids text[];
begin
  delete from player_challenges; delete from challenge_rerolls;
  perform pg_temp.login(a);
  v := challenge_status();
  perform pg_temp.assert(jsonb_array_length(v->'daily'->'items') = 3 and jsonb_array_length(v->'weekly'->'items') = 3, 'three daily and three weekly');
  perform pg_temp.assert((v->'daily'->>'period')::date = bl_wat_date() and (v->'weekly'->>'period')::date = bl_week_start(), 'periods are today and this Monday');
  perform pg_temp.assert((v->'daily'->>'secs_left')::int between 1 and 86400 and (v->'weekly'->>'secs_left')::int between 1 and 7 * 86400, 'time left');
  perform pg_temp.assert((v->'weekly'->>'ends_at')::timestamptz = bl_week_from(bl_week_start() + 7), 'the week ends at the weekly top earners boundary');
  perform pg_temp.assert((v->'daily'->>'ends_at')::timestamptz = ((bl_wat_date() + 1)::timestamp at time zone 'Africa/Lagos'), 'the day ends at midnight Benin time');
  v_d := pg_temp.ids(a, 'daily'); v_w := pg_temp.ids(a, 'weekly');
  perform pg_temp.assert((select count(distinct goal) from player_challenges where user_id = a and kind = 'daily') = 3, 'three different daily goals');
  -- a second call changes nothing
  perform challenge_status();
  perform pg_temp.assert(pg_temp.ids(a, 'daily') = v_d and (select count(*) from player_challenges where user_id = a) = 6, 'a second call hands out nothing new');
  -- wipe the rows: the same player and period give the same set
  delete from player_challenges where user_id = a;
  perform challenge_status();
  perform pg_temp.assert(pg_temp.ids(a, 'daily') = v_d and pg_temp.ids(a, 'weekly') = v_w, 'deterministic: same player and period, same set');
  -- slots and rewards are filled in
  perform pg_temp.assert((select bool_and(target > 0 and reward_cash >= 0 and slot between 1 and 3) from player_challenges where user_id = a), 'rows carry target, reward, slot');
  -- other players get (mostly) other sets
  foreach i in array array[1, 2, 3] loop
    perform pg_temp.login(case i when 1 then b when 2 then c else d end);
    perform challenge_status();
    if pg_temp.ids(case i when 1 then b when 2 then c else d end, 'daily') <> v_d then v_other := v_other + 1; end if;
  end loop;
  perform pg_temp.assert(v_other >= 1, 'players do not all get the same dailies');
  -- the set changes day by day (not the same every day)
  perform pg_temp.login(a);
  v_d2 := '{}';
  for i in 1..6 loop
    perform pg_temp.advance(86400);
    perform challenge_status();
    v_ids := pg_temp.ids(a, 'daily');
    if v_ids <> v_d then v_other := v_other + 1; end if;
  end loop;
  perform pg_temp.assert(v_other >= 4, 'the daily set moves on over a week');
  raise notice 'ok 3: deterministic assignment';
end $$;

-- ---------- 4. gating skip ----------
do $$
declare
  a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); c uuid := pg_temp.u('c'); i int; v_bad int := 0; v_goals text[];
begin
  -- 4a. over 30 days a player with no job, no class, no laptop, no friends, no rod is never given a goal they cannot do
  delete from player_challenges;
  update challenge_templates set active = true where id ~ '^[dw]_';
  delete from player_friendships where user_a in (c) or user_b in (c);
  for i in 1..30 loop
    perform pg_temp.login(c);
    perform challenge_status();
    perform pg_temp.advance(86400);
  end loop;
  select array_agg(distinct goal) into v_goals from player_challenges where user_id = c;
  perform pg_temp.assert(not (v_goals && array['shift', 'class', 'yahoo_clean', 'dm_people', 'dm_send', 'friend_hustle', 'friend_house', 'friend_meet', 'fish']),
                         format('c never got a goal they cannot do yet: %s', v_goals));
  perform pg_temp.assert(not exists (select 1 from player_challenges where user_id = c and template_id in ('d_bolt', 'd_pos', 'd_dj', 'w_bolt_6', 'w_yahoo_3')),
                         'no hustle or yahoo goal without the car / machine / laptop');
  perform pg_temp.assert((select count(*) from player_challenges where user_id = c and kind = 'daily') = 90
                         and (select count(*) from player_challenges where user_id = c and kind = 'weekly') >= 12, 'c still got full sets (plenty of doable goals)');

  -- 4b. a friend-less player never gets friend goals; a with a friend and a job does
  delete from player_challenges where user_id = a;
  perform pg_temp.only(array['g_fill1', 'g_fill2', 'g_fill3', 'g_shift', 'g_chat', 'g_fill4']);
  perform pg_temp.tpl('g_fill1', 'daily', 'buy_item', 1, 100); perform pg_temp.tpl('g_fill2', 'daily', 'visit_place', 2, 100);
  perform pg_temp.tpl('g_fill3', 'daily', 'spray', 1000, 100); perform pg_temp.tpl('g_fill4', 'daily', 'skill_up', 1, 100, 0.0001);
  perform pg_temp.tpl('g_shift', 'daily', 'shift', 1, 100, 1000);
  perform pg_temp.tpl('g_chat', 'daily', 'dm_people', 1, 100, 1000);
  perform pg_temp.login(c);
  perform challenge_status();
  perform pg_temp.assert(not ('g_shift' = any (pg_temp.ids(c, 'daily'))) and not ('g_chat' = any (pg_temp.ids(c, 'daily'))), 'no job and no friends: shift and chat goals skipped');
  perform pg_temp.login(a);
  perform challenge_status();
  perform pg_temp.assert('g_chat' = any (pg_temp.ids(a, 'daily')) and not ('g_shift' = any (pg_temp.ids(a, 'daily'))), 'a has a friend (chat) but no job (shift skipped)');
  delete from player_challenges where user_id = a;
  perform job_apply('tech');
  perform challenge_status();
  perform pg_temp.assert('g_shift' = any (pg_temp.ids(a, 'daily')) and 'g_chat' = any (pg_temp.ids(a, 'daily')), 'with a job and a friend both are handed out');

  -- 4c. certificate gate
  perform pg_temp.only(array['k_cert', 'k_f1', 'k_f2', 'k_f3']);
  perform pg_temp.tpl('k_f1', 'daily', 'buy_item', 1, 100); perform pg_temp.tpl('k_f2', 'daily', 'visit_place', 2, 100); perform pg_temp.tpl('k_f3', 'daily', 'spray', 1000, 100);
  perform pg_temp.tpl('k_cert', 'daily', 'earn', 1000, 100, 100000);
  update challenge_templates set req_cert = 'ict' where id = 'k_cert';
  delete from player_certificates where user_id = a and cert_id = 'ict';
  perform pg_temp.login(a);
  perform challenge_status();
  perform pg_temp.assert(not ('k_cert' = any (pg_temp.ids(a, 'daily'))), 'no certificate: the goal is skipped');
  insert into player_certificates (user_id, cert_id, source) values (a, 'ict', 'admin');
  delete from player_challenges where user_id = a;
  perform challenge_status();
  perform pg_temp.assert('k_cert' = any (pg_temp.ids(a, 'daily')), 'with the certificate it is handed out (heavy weight picks it first)');
  perform pg_temp.cfg('school.enabled', 'false');
  delete from player_certificates where user_id = a and cert_id = 'ict';
  delete from player_challenges where user_id = a;
  perform challenge_status();
  perform pg_temp.assert('k_cert' = any (pg_temp.ids(a, 'daily')), 'school off: certificate gates do not apply');
  perform pg_temp.cfg('school.enabled', 'true');

  -- 4d. skill gate (min skill level)
  perform pg_temp.only(array['k_skill', 'k_f1', 'k_f2', 'k_f3']);
  update challenge_templates set min_skill = 'yahoo', min_skill_level = 2 where id = 'k_skill';
  perform pg_temp.tpl('k_skill', 'daily', 'earn', 1000, 100, 100000);
  update challenge_templates set min_skill = 'yahoo', min_skill_level = 2 where id = 'k_skill';
  delete from player_skills where user_id = a and skill_id = 'yahoo';
  perform pg_temp.login(a);
  perform challenge_status();
  perform pg_temp.assert(not ('k_skill' = any (pg_temp.ids(a, 'daily'))), 'skill level 1: Yahoo level 2 goal skipped');
  insert into player_skills (user_id, skill_id, xp) values (a, 'yahoo', 40);
  delete from player_challenges where user_id = a;
  perform challenge_status();
  perform pg_temp.assert('k_skill' = any (pg_temp.ids(a, 'daily')), 'Yahoo level 2: it is handed out');

  -- 4e. a hustle goal follows the hustle's own gates (Bolt needs a car, DJ needs a controller + certificate)
  perform pg_temp.only(array['k_bolt', 'k_dj', 'k_f1', 'k_f2', 'k_f3']);
  perform pg_temp.tpl('k_f1', 'daily', 'buy_item', 1, 100); perform pg_temp.tpl('k_f2', 'daily', 'visit_place', 2, 100); perform pg_temp.tpl('k_f3', 'daily', 'spray', 1000, 100);
  perform pg_temp.tpl('k_bolt', 'daily', 'hustle_done', 1, 100, 100000, 'bolt_shift');
  perform pg_temp.tpl('k_dj', 'daily', 'hustle_done', 1, 100, 100000, 'dj_headline');
  perform pg_temp.login(a);
  perform challenge_status();
  perform pg_temp.assert(not ('k_bolt' = any (pg_temp.ids(a, 'daily'))) and not ('k_dj' = any (pg_temp.ids(a, 'daily'))), 'no car, no controller or certificate: skipped');
  raise notice 'ok 4: gating';
end $$;

-- ---------- 5. progress from a hustle, a career shift and earnings ----------
do $$
declare
  a uuid := pg_temp.u('a'); v jsonb; v_pay bigint; v_sum bigint; v_w_before bigint;
begin
  perform pg_temp.only(array['c_hus', 'c_earn', 'c_shift', 'w_hus', 'w_earn', 'w_shift']);
  perform pg_temp.tpl('c_hus', 'daily', 'hustle_done', 1, 1000);
  perform pg_temp.tpl('c_earn', 'daily', 'earn', 5000, 1500);
  perform pg_temp.tpl('c_shift', 'daily', 'shift', 1, 1200);
  perform pg_temp.tpl('w_hus', 'weekly', 'hustle_done', 2, 5000);
  perform pg_temp.tpl('w_earn', 'weekly', 'earn', 12000, 6000);
  perform pg_temp.tpl('w_shift', 'weekly', 'shift', 1, 4000);
  perform pg_temp.login(a);
  update profiles set job_id = 'tech', job_level = 1, job_xp = 0 where id = a;
  v := challenge_status();
  perform pg_temp.assert(pg_temp.ids(a, 'daily') = array['c_earn', 'c_hus', 'c_shift'] and pg_temp.ids(a, 'weekly') = array['w_earn', 'w_hus', 'w_shift'],
                         'the six test challenges are handed out');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'c_hus') = 0 and pg_temp.prog(a, 'weekly', 'w_earn') = 0, 'progress starts at 0');

  -- a hustle (Mechanic quick fix, pays up to 8,000)
  perform pg_temp.at(a, 'mechanic_village');
  v := pg_temp.hrun(a, 'mech_quick');
  v_pay := (v->>'amount')::bigint;
  perform pg_temp.assert(v_pay >= 3500, format('the hustle paid: %s', v));
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'c_hus') = 1 and exists (select 1 from player_challenges where user_id = a and template_id = 'c_hus' and completed_at is not null),
                         'daily "finish a hustle" done by one hustle');
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'w_hus') = 1, 'weekly hustle counter at 1 of 2');
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'w_earn') = v_pay, 'weekly earnings = the hustle pay (ledger rows of the weekly top earners rule)');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'c_earn') = least(v_pay, 5000), 'daily earnings counted, capped at the target');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'challenge_done' and (data->>'template') = 'c_hus'), 'completion event (toast)');
  -- not finished yet: no claim
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_claim(%s)', (pg_temp.item(a, 'daily', 'c_shift')->>'id')::bigint)) = 'not_done', 'claiming an unfinished challenge is refused');
  -- a hustle LOSS does not count
  perform pg_temp.assert(pg_temp.item(a, 'weekly', 'w_hus')->>'done' = 'false', 'weekly hustles not done yet');
  -- a second hustle finishes the weekly hustle goal and the weekly earnings goal (total of two max-ish payouts passes 12,000)
  v := pg_temp.hrun(a, 'mech_quick');
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'w_hus') = 2 and (pg_temp.item(a, 'weekly', 'w_hus')->>'done')::boolean, 'two hustles finish the weekly hustle goal');
  select coalesce(sum(delta), 0) into v_sum from ledger where user_id = a and reason = 'hustle' and delta > 0;
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'w_earn') = least(12000, v_sum), format('weekly earnings follow the ledger (%s)', v_sum));
  perform pg_temp.assert((pg_temp.item(a, 'weekly', 'w_earn')->>'done')::boolean = (v_sum >= 12000), 'weekly earnings done at 12,000');

  -- a career shift (salary + shift counter)
  perform pg_temp.at(a, 'bronze_tech_hub');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'c_shift') = 0, 'no shift yet');
  perform work_shift();
  perform pg_temp.advance(500);
  perform work_finish();
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'c_shift') = 1 and (pg_temp.item(a, 'daily', 'c_shift')->>'done')::boolean, 'a finished shift counts');
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'w_shift') = 1, 'weekly shift counter');
  perform pg_temp.assert((select progress from player_challenges where user_id = a and template_id = 'w_earn' and period = bl_week_start())
                         = least(12000, (select sum(delta) from ledger where user_id = a and reason in ('hustle', 'salary') and delta > 0)), 'salary counts as earnings too');
  raise notice 'ok 5: progress from a hustle, a shift, earnings';
end $$;

-- ---------- 6. complete and claim once ----------
do $$
declare
  a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); v jsonb; v_id bigint; v_cash bigint; v_xp0 int; v_sk0 int; v_n int; v_xp int;
begin
  perform pg_temp.login(a);
  v_id := (pg_temp.item(a, 'daily', 'c_hus')->>'id')::bigint;
  v_cash := pg_temp.cash(a);
  -- a template edit after the hand-out does not change the running challenge
  update challenge_templates set reward_cash = 99999 where id = 'c_hus';
  v := challenge_claim(v_id);
  perform pg_temp.assert(pg_temp.cash(a) = v_cash + 1000 and (v->>'cash')::bigint = 1000, format('paid the snapshot reward 1,000: %s', v));
  perform pg_temp.assert((select count(*) from ledger where user_id = a and reason = 'challenge') = 1
                         and (select delta from ledger where user_id = a and reason = 'challenge') = 1000, 'one ledger row, reason challenge');
  perform pg_temp.assert((select meta->>'title' from ledger where user_id = a and reason = 'challenge') = 'T c_hus', 'ledger meta carries the title');
  perform pg_temp.assert(pg_temp.item(a, 'daily', 'c_hus')->>'claimed' = 'true', 'status says claimed');
  update challenge_templates set reward_cash = 1000 where id = 'c_hus';
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_claim(%s)', v_id)) = 'already_claimed', 'claim once: the second claim is refused');
  perform pg_temp.assert(pg_temp.cash(a) = v_cash + 1000 and (select count(*) from ledger where user_id = a and reason = 'challenge') = 1, 'no double payment');
  -- someone else's challenge
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_claim(%s)', v_id)) = 'not_found', 'cannot claim another player''s challenge');
  perform pg_temp.assert(pg_temp.hint_of('select challenge_claim(-5)') = 'not_found', 'unknown id');
  perform pg_temp.login(a);
  -- the rich reward bundle: cash + career XP + skill XP + item
  select job_xp into v_xp0 from profiles where id = a;
  select coalesce((select xp from player_skills where user_id = a and skill_id = 'mechanic'), 0) into v_sk0;
  update player_challenges set reward_xp = 25, reward_skill = 'mechanic', reward_skill_xp = 30, reward_item = 'kada_chicken', reward_item_qty = 2
   where user_id = a and template_id = 'c_shift' and period = bl_wat_date();
  v_id := (pg_temp.item(a, 'daily', 'c_shift')->>'id')::bigint;
  v_cash := pg_temp.cash(a);
  v := challenge_claim(v_id);
  perform pg_temp.assert(pg_temp.cash(a) = v_cash + 1200, 'cash paid');
  perform pg_temp.assert((select job_xp from profiles where id = a) = v_xp0 + 25, 'career XP paid (a has a job)');
  perform pg_temp.assert(coalesce((select xp from player_skills where user_id = a and skill_id = 'mechanic'), 0) = v_sk0 + 30, 'skill XP paid');
  perform pg_temp.assert((select qty from inventory where user_id = a and item_id = 'kada_chicken') = 2, 'item paid');
  perform pg_temp.assert(v->>'message' like '%T c_shift%' and v->>'message' like '%Mechanic XP%', format('message lists the pieces: %s', v->>'message'));
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_claim(%s)', v_id)) = 'already_claimed', 'bundle is claim-once too');
  raise notice 'ok 6: claim once';
end $$;

-- ---------- 7. reroll limit ----------
do $$
declare
  a uuid := pg_temp.u('a'); v jsonb; v_id bigint; v_id2 bigint; v_id3 bigint;
begin
  perform pg_temp.only(array['r1', 'r2', 'r3', 'r_spare', 'rw1', 'rw2', 'rw3', 'rw_spare']);
  perform pg_temp.tpl('r1', 'daily', 'buy_item', 3, 100); perform pg_temp.tpl('r2', 'daily', 'visit_place', 2, 100); perform pg_temp.tpl('r3', 'daily', 'spray', 1000, 100);
  perform pg_temp.tpl('r_spare', 'daily', 'skill_up', 1, 100, 0.0001);
  perform pg_temp.tpl('rw1', 'weekly', 'buy_item', 3, 100); perform pg_temp.tpl('rw2', 'weekly', 'visit_place', 2, 100); perform pg_temp.tpl('rw3', 'weekly', 'spray', 1000, 100);
  perform pg_temp.tpl('rw_spare', 'weekly', 'skill_up', 1, 100, 0.0001);
  perform pg_temp.login(a);
  v := challenge_status();
  perform pg_temp.assert(pg_temp.ids(a, 'daily') = array['r1', 'r2', 'r3'] and (v->'daily'->>'rerolls_left')::int = 1 and (v->'daily'->>'rerolls_max')::int = 1, 'one free reroll a day');
  perform pg_temp.assert((pg_temp.item(a, 'daily', 'r1')->>'can_reroll')::boolean, 'an unfinished challenge can be rerolled');
  v_id := (pg_temp.item(a, 'daily', 'r1')->>'id')::bigint;
  v_id2 := (pg_temp.item(a, 'daily', 'r2')->>'id')::bigint;
  -- some progress on r1 is lost on a reroll
  perform bl_challenge_bump(a, 'buy_item', 2, null);
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'r1') = 2, 'r1 has progress 2');
  v := challenge_reroll(v_id);
  perform pg_temp.assert(v->'item'->>'template' = 'r_spare' and (v->>'rerolls_left')::int = 0, format('rerolled into the spare: %s', v->'item'));
  perform pg_temp.assert((select progress from player_challenges where id = v_id) = 0 and (select goal from player_challenges where id = v_id) = 'skill_up', 'progress reset, new goal in the same row');
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_reroll(%s)', v_id2)) = 'no_rerolls', 'the second reroll of the day is refused');
  perform pg_temp.assert((challenge_status()->'daily'->>'rerolls_left')::int = 0 and not (pg_temp.item(a, 'daily', 'r2')->>'can_reroll')::boolean, 'status shows none left');
  -- tunable: 2 a day
  perform pg_temp.cfg('challenges.rerolls_per_day', '2');
  perform pg_temp.assert((challenge_status()->'daily'->>'rerolls_left')::int = 1, 'raise the limit: one more');
  -- no alternative left: every template is already in the set
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_reroll(%s)', v_id2)) = 'no_alternative', 'nothing else to swap in');
  -- a finished challenge cannot be rerolled
  perform bl_challenge_bump(a, 'spray', 1000, null);
  v_id3 := (pg_temp.item(a, 'daily', 'r3')->>'id')::bigint;
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_reroll(%s)', v_id3)) = 'already_done', 'a finished challenge cannot be rerolled');
  perform pg_temp.cfg('challenges.rerolls_per_day', '0');
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_reroll(%s)', v_id2)) = 'no_rerolls', 'rerolls off');
  -- weekly: none by default, one when tuned
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_reroll(%s)', (pg_temp.item(a, 'weekly', 'rw1')->>'id')::bigint)) = 'no_rerolls', 'no weekly rerolls by default');
  perform pg_temp.cfg('challenges.rerolls_per_week', '1');
  v := challenge_reroll((pg_temp.item(a, 'weekly', 'rw1')->>'id')::bigint);
  perform pg_temp.assert(v->'item'->>'template' = 'rw_spare', 'weekly reroll works when tuned');
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_reroll(%s)', (pg_temp.item(a, 'weekly', 'rw2')->>'id')::bigint)) = 'no_rerolls', 'one weekly reroll only');
  perform pg_temp.cfg('challenges.rerolls_per_day', '1');
  perform pg_temp.cfg('challenges.rerolls_per_week', '0');
  raise notice 'ok 7: rerolls';
end $$;

-- ---------- 8. chests ----------
do $$
declare
  a uuid := pg_temp.u('a'); v jsonb; v_cash bigint; v_xp int; v_n int; v_push int; i int;
begin
  perform pg_temp.only(array['h1', 'h2', 'h3', 'hw1', 'hw2', 'hw3']);
  perform pg_temp.tpl('h1', 'daily', 'buy_item', 1, 100); perform pg_temp.tpl('h2', 'daily', 'visit_place', 1, 100); perform pg_temp.tpl('h3', 'daily', 'spray', 1000, 100);
  perform pg_temp.tpl('hw1', 'weekly', 'fish', 1, 100); perform pg_temp.tpl('hw2', 'weekly', 'club_spend', 1000, 100); perform pg_temp.tpl('hw3', 'weekly', 'skill_up', 1, 100);
  perform pg_temp.login(a);
  v := challenge_status();
  perform pg_temp.assert(not (v->'daily'->'chest'->>'ready')::boolean and (v->'daily'->'chest'->>'total')::int = 3 and (v->'daily'->'chest'->>'cash')::bigint = 3000, 'chest listed, not ready');
  perform pg_temp.assert(pg_temp.hint_of('select challenge_claim_chest(''daily'')') = 'not_done', 'chest refused with nothing done');
  perform pg_temp.assert(pg_temp.hint_of('select challenge_claim_chest(''monthly'')') = 'bad_kind', 'bad kind');
  perform bl_challenge_bump(a, 'buy_item', 1, null);
  perform bl_challenge_bump(a, 'spray', 1000, null);
  perform pg_temp.assert(pg_temp.hint_of('select challenge_claim_chest(''daily'')') = 'not_done', 'two of three is not enough');
  perform pg_temp.assert(not (challenge_status()->'daily'->'chest'->>'ready')::boolean, 'not ready at 2 of 3');
  perform bl_challenge_bump(a, 'visit_place', 1, 'oba_market');
  v := challenge_status();
  perform pg_temp.assert((v->'daily'->'chest'->>'ready')::boolean and (v->'daily'->'chest'->>'done')::int = 3, 'all three done: the chest is ready');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'challenge_done' and (data->>'chest_ready')::boolean and (data->>'template') = 'h2'), 'the last completion says the chest is ready');
  select cash into v_cash from profiles where id = a;
  select job_xp into v_xp from profiles where id = a;
  v := challenge_claim_chest('daily');
  perform pg_temp.assert(pg_temp.cash(a) = v_cash + 3000 and (v->>'cash')::bigint = 3000, format('daily chest pays 3,000: %s', v));
  perform pg_temp.assert((select job_xp from profiles where id = a) = v_xp + 20, 'daily chest career XP');
  perform pg_temp.assert(coalesce((select qty from inventory where user_id = a and item_id = 'energy_drink'), 0) = 1, 'daily chest item');
  perform pg_temp.assert((select count(*) from ledger where user_id = a and reason = 'challenge' and (meta->>'chest') = 'daily') = 1, 'ledger: one challenge row for the chest');
  perform pg_temp.assert(pg_temp.hint_of('select challenge_claim_chest(''daily'')') = 'already_claimed', 'the chest opens once');
  perform pg_temp.assert((challenge_status()->'daily'->'chest'->>'claimed')::boolean and not (challenge_status()->'daily'->'chest'->>'ready')::boolean, 'status: claimed');
  -- weekly: bigger chest, push when ready (events category, opt-in)
  insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (a, 'https://push.test/r5', 'k', 'a');
  insert into push_prefs (user_id, master, events) values (a, true, true) on conflict (user_id) do update set master = true, events = true;
  update profiles set last_seen = bl_now() - interval '10 minutes' where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select challenge_claim_chest(''weekly'')') = 'not_done', 'weekly chest needs every weekly challenge');
  perform bl_challenge_bump(a, 'fish', 1, null);
  perform bl_challenge_bump(a, 'club_spend', 1000, null);
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'challenge_chest') = 0, 'no push until the whole week is done');
  perform bl_challenge_bump(a, 'skill_up', 1, 'fishing');
  select count(*) into v_push from push_outbox where user_id = a and kind = 'challenge_chest';
  perform pg_temp.assert(v_push = 1, 'one push when the weekly chest is ready');
  select cash into v_cash from profiles where id = a;
  v := challenge_claim_chest('weekly');
  perform pg_temp.assert(pg_temp.cash(a) = v_cash + 20000 and (v->>'cash')::bigint = 20000, 'weekly chest pays 20,000');
  perform pg_temp.assert(coalesce((select qty from inventory where user_id = a and item_id = 'kada_chicken'), 0) >= 1, 'weekly chest item');
  perform pg_temp.assert(pg_temp.hint_of('select challenge_claim_chest(''weekly'')') = 'already_claimed', 'weekly chest opens once');
  perform pg_temp.assert((select count(*) from challenge_chests where user_id = a) = 2, 'two chest rows');
  -- push off by setting
  raise notice 'ok 8: chests';
end $$;

-- ---------- 9. reset on the next day and the next week ----------
do $$
declare
  a uuid := pg_temp.u('a'); v jsonb; v_d0 date := bl_wat_date(); v_w0 date := bl_week_start(); v_ids0 text[]; v_id bigint; v_wid bigint; v_open bigint;
begin
  perform pg_temp.only(array['n1', 'n2', 'n3', 'nw1', 'nw2', 'nw3']);
  perform pg_temp.tpl('n1', 'daily', 'buy_item', 1, 700); perform pg_temp.tpl('n2', 'daily', 'visit_place', 5, 100); perform pg_temp.tpl('n3', 'daily', 'spray', 1000, 100);
  perform pg_temp.tpl('nw1', 'weekly', 'buy_item', 1, 900); perform pg_temp.tpl('nw2', 'weekly', 'visit_place', 9, 100); perform pg_temp.tpl('nw3', 'weekly', 'spray', 99000, 100);
  perform pg_temp.login(a);
  perform challenge_status();
  -- finish n1 and nw1 but do not claim them; n2 stays open
  perform bl_challenge_bump(a, 'buy_item', 1, null);
  v_id := (pg_temp.item(a, 'daily', 'n1')->>'id')::bigint;
  v_wid := (pg_temp.item(a, 'weekly', 'nw1')->>'id')::bigint;
  v_open := (pg_temp.item(a, 'daily', 'n2')->>'id')::bigint;
  perform bl_challenge_bump(a, 'visit_place', 1, 'oba_market');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'n2') = 1, 'n2 at 1 of 5');

  -- the next Benin day, 10:00
  perform pg_temp.advance(86400);
  perform pg_temp.assert(bl_wat_date() = v_d0 + 1, 'it is the next Benin day');
  -- the old claim window is shut
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_claim(%s)', v_id)) = 'expired', 'yesterday''s finished challenge can no longer be claimed');
  -- no status call yet: the first real action of the day hands the new set out and counts
  perform bl_challenge_bump(a, 'buy_item', 1, null);
  perform pg_temp.assert((select count(*) from player_challenges where user_id = a and kind = 'daily' and period = v_d0 + 1) = 3, 'the first action of the day hands out the new dailies');
  perform pg_temp.assert((select progress from player_challenges where user_id = a and period = v_d0 + 1 and template_id = 'n1') = 1, 'and counted');
  perform pg_temp.assert((select expired from player_challenges where id = v_open), 'yesterday''s unfinished challenge is expired');
  perform pg_temp.assert((select progress from player_challenges where user_id = a and period = v_d0 + 1 and template_id = 'n2') = 0, 'new day: n2 starts again at 0');
  v := challenge_status();
  perform pg_temp.assert(not (v->'daily'->'chest'->>'claimed')::boolean and (v->'daily'->'chest'->>'done')::int = 1, 'new day: a fresh chest');
  perform pg_temp.assert((v->'daily'->>'rerolls_left')::int = 1, 'new day: the free reroll is back');
  if bl_week_start() = v_w0 then
    perform pg_temp.assert((select count(*) from player_challenges where user_id = a and kind = 'weekly' and period = v_w0) = 3, 'same week: the weekly set stays');
    perform pg_temp.assert(pg_temp.hint_of(format('select challenge_claim(%s)', v_wid)) = 'ok', 'the weekly one is still claimable on day 2');
  end if;

  -- the next Monday, 10:00
  perform pg_temp.next_week();
  perform pg_temp.assert(bl_week_start() = v_w0 + 7, 'the next Monday');
  perform pg_temp.assert(extract(isodow from bl_week_start()) = 1, 'weeks start on Monday');
  v := challenge_status();
  perform pg_temp.assert((v->'weekly'->>'period')::date = v_w0 + 7 and (select count(*) from player_challenges where user_id = a and kind = 'weekly' and period = v_w0 + 7) = 3, 'new week: new weekly set');
  perform pg_temp.assert(not (v->'weekly'->'chest'->>'claimed')::boolean and (v->'weekly'->'chest'->>'done')::int = 0, 'new week: fresh weekly chest');
  perform pg_temp.assert((select count(*) from player_challenges where user_id = a and kind = 'daily' and period = bl_wat_date()) = 3, 'and fresh dailies');
  -- the weekly boundary is exactly the weekly top earners one (Sunday 23:59 vs Monday 00:00 Benin time)
  perform pg_temp.assert(bl_chal_ends('weekly', v_w0 + 7) = bl_week_from(v_w0 + 14), 'weekly period ends where the weekly earners week ends');
  -- a claim in the new week for the earnings test (group 10): finish and claim nw1 and n1
  perform bl_challenge_bump(a, 'buy_item', 1, null);
  perform challenge_claim((pg_temp.item(a, 'weekly', 'nw1')->>'id')::bigint);
  perform challenge_claim((pg_temp.item(a, 'daily', 'n1')->>'id')::bigint);
  raise notice 'ok 9: resets';
end $$;

-- ---------- 10. rewards are not weekly earnings ----------
do $$
declare
  a uuid := pg_temp.u('a'); v_chal bigint; v_hustle bigint; v_total bigint;
begin
  perform pg_temp.login(a);
  perform pg_temp.at(a, 'mechanic_village');
  perform pg_temp.hrun(a, 'mech_quick');
  select coalesce(sum(delta), 0) into v_chal from ledger where user_id = a and reason = 'challenge' and delta > 0 and created_at >= bl_week_from(bl_week_start());
  select coalesce(sum(delta), 0) into v_hustle from ledger where user_id = a and reason = 'hustle' and delta > 0 and created_at >= bl_week_from(bl_week_start());
  perform pg_temp.assert(v_chal >= 1600 and v_hustle > 0, format('this week has challenge pay (%s) and hustle pay (%s)', v_chal, v_hustle));
  select total into v_total from bl_weekly_ranked(bl_week_start()) where id = a;
  perform pg_temp.assert(v_total = v_hustle, format('weekly earners count the hustle (%s) and not the challenge pay (total %s)', v_hustle, v_total));
  -- even if an admin lists the reason, it is dropped
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,hustle,challenge"');
  perform pg_temp.assert(not ('challenge' = any (bl_earn_reasons())), 'challenge is never an earn reason');
  select total into v_total from bl_weekly_ranked(bl_week_start()) where id = a;
  perform pg_temp.assert(v_total = v_hustle, 'still excluded after the admin lists it');
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,hustle,harvest,farm_harvest,invest_income"');
  -- and a challenge payout never moves an earn challenge
  perform pg_temp.only(array['x_earn', 'x_f1', 'x_f2']);
  perform pg_temp.tpl('x_earn', 'daily', 'earn', 1000, 100, 1000);
  perform pg_temp.tpl('x_f1', 'daily', 'buy_item', 1, 100); perform pg_temp.tpl('x_f2', 'daily', 'spray', 100, 100);
  perform challenge_status();
  perform bl_add_money(a, 'cash', 5000, 'challenge', '{"title":"x"}');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'x_earn') = 0, 'challenge rewards do not count towards an earn challenge');
  perform bl_add_money(a, 'cash', 400, 'hustle', '{"name":"x"}');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'x_earn') = 400, 'real earnings do');
  perform bl_add_money(a, 'cash', 700, 'transfer_in', '{}');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'x_earn') = 400, 'gifts and transfers do not');
  raise notice 'ok 10: not an earning';
end $$;

-- ---------- 11. the other goals ----------
do $$
declare
  a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); c uuid := pg_temp.u('c');
  v_p1 text; v_p2 text; v_item text; v_conv bigint; v jsonb; v_course text; v_run bigint;
begin
  perform pg_temp.cfg('chat.rate_seconds', '0');
  perform pg_temp.cfg('challenges.daily_count', '6');
  perform pg_temp.cfg('challenges.weekly_count', '6');
  -- c becomes a's friend too (two different chat partners)
  perform pg_temp.login(c);
  perform social_add_friend(a);
  perform pg_temp.login(a);
  perform social_respond_friend(c, true);

  -- Round A
  perform pg_temp.only(array['o_visit', 'o_dm', 'o_chat', 'o_buy', 'o_streak', 'o_skill']);
  perform pg_temp.tpl('o_visit', 'daily', 'visit_place', 2, 100); perform pg_temp.tpl('o_dm', 'daily', 'dm_send', 2, 100);
  perform pg_temp.tpl('o_chat', 'daily', 'dm_people', 2, 100); perform pg_temp.tpl('o_buy', 'daily', 'buy_item', 1, 100);
  perform pg_temp.tpl('o_streak', 'daily', 'streak', 1, 100); perform pg_temp.tpl('o_skill', 'daily', 'skill_up', 1, 100);
  perform pg_temp.login(a);
  delete from player_skills where user_id = a and skill_id = 'fishing';
  delete from daily_reward_state where user_id = a;
  perform challenge_status();
  perform pg_temp.assert(array_length(pg_temp.ids(a, 'daily'), 1) = 6, 'six dailies when the setting says six');

  -- places: public places count once each, a home never counts
  select id into v_p1 from locations where active and private_home_owner_id is null and scene not like 'home%' order by id limit 1;
  select id into v_p2 from locations where active and private_home_owner_id is null and scene not like 'home%' and id <> v_p1 order by id limit 1;
  perform pg_temp.at(a, v_p1);
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_visit') = 1, 'arriving at a place counts');
  perform pg_temp.at(a);
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_visit') = 1, 'going home does not count');
  perform pg_temp.at(a, v_p1);
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_visit') = 1, 'the same place twice counts once');
  perform pg_temp.at(a, v_p2);
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_visit') = 2 and (pg_temp.item(a, 'daily', 'o_visit')->>'done')::boolean, 'a second different place finishes it');

  -- DMs: messages, and different people
  v := social_open_conversation(b);
  v_conv := (v->>'id')::bigint;
  perform social_send_message(v_conv, 'Oya, how far?');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_dm') = 1 and pg_temp.prog(a, 'daily', 'o_chat') = 1, 'one DM: one message, one person');
  perform social_send_message(v_conv, 'You dey?');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_dm') = 2 and pg_temp.prog(a, 'daily', 'o_chat') = 1, 'two DMs to the same person: messages 2, people still 1');
  v := social_open_conversation(c);
  perform social_send_message((v->>'id')::bigint, 'Padi mi!');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_chat') = 2 and (pg_temp.item(a, 'daily', 'o_chat')->>'done')::boolean, 'a second person finishes the chat goal');

  -- buying from a shop
  select i.id, i.sold_at[1] into v_item, v_p1 from items i where cardinality(i.sold_at) > 0 and i.price < 1000 order by i.id limit 1;
  perform pg_temp.at(a, v_p1);
  perform shop_buy(v_item, 1);
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_buy') = 1, 'buying an item counts');

  -- the daily reward streak
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_streak') = 0, 'streak not started');
  perform daily_reward_claim();
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_streak') = 1 and (pg_temp.item(a, 'daily', 'o_streak')->>'done')::boolean, 'claiming the daily reward counts');

  -- a skill level
  insert into player_skills (user_id, skill_id, xp) values (a, 'fishing', 10);
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_skill') = 0, 'XP without a level-up does not count');
  update player_skills set xp = 50 where user_id = a and skill_id = 'fishing';
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_skill') = 1, 'gaining a skill level counts');

  -- weekly streak climbs day by day (set, not add)
  perform pg_temp.next_week();
  perform pg_temp.only(array['o_wstreak', 'o_f1', 'o_f2']);
  perform pg_temp.tpl('o_wstreak', 'weekly', 'streak', 3, 100); perform pg_temp.tpl('o_f1', 'daily', 'buy_item', 1, 100); perform pg_temp.tpl('o_f2', 'daily', 'spray', 1, 100);
  delete from daily_reward_state where user_id = a;
  perform pg_temp.login(a);
  perform challenge_status();
  perform daily_reward_claim();
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'o_wstreak') = 1, 'streak day 1');
  perform pg_temp.advance(86400); perform daily_reward_claim();
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'o_wstreak') = 2, 'streak day 2');
  perform pg_temp.advance(86400); perform daily_reward_claim();
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'o_wstreak') = 3 and (pg_temp.item(a, 'weekly', 'o_wstreak')->>'done')::boolean, 'a 3-day streak finishes the weekly goal');
  -- a streak already held when the challenge is handed out counts from the start
  perform pg_temp.only(array['o_sstreak', 'o_f1', 'o_f2']);
  perform pg_temp.tpl('o_sstreak', 'daily', 'streak', 2, 100, 100000);
  perform challenge_status();
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'o_sstreak') = 2, 'a streak already held today starts the goal at that streak');

  -- Round B: fish, club spending, spray, friends, class, Yahoo
  perform pg_temp.only(array['p_fish', 'p_club', 'p_spray', 'p_meet', 'p_fhus', 'p_house', 'p_class', 'p_yahoo']);
  perform pg_temp.tpl('p_fish', 'daily', 'fish', 1, 100); perform pg_temp.tpl('p_club', 'daily', 'club_spend', 4000, 100);
  perform pg_temp.tpl('p_spray', 'daily', 'spray', 2000, 100); perform pg_temp.tpl('p_meet', 'daily', 'friend_meet', 1, 100);
  perform pg_temp.tpl('p_fhus', 'daily', 'friend_hustle', 1, 100); perform pg_temp.tpl('p_house', 'daily', 'friend_house', 1, 100);
  perform pg_temp.tpl('p_class', 'weekly', 'class', 1, 100); perform pg_temp.tpl('p_yahoo', 'weekly', 'yahoo_clean', 1, 100);
  perform bl_give_item(a, 'fishing_rod', 1);
  perform bl_give_item(a, 'laptop', 1);
  select id into v_course from courses order by sort limit 1;
  insert into course_enrolments (user_id, course_id, status) values (a, v_course, 'enrolled') on conflict (user_id, course_id) do update set status = 'enrolled';
  perform pg_temp.login(a);
  perform challenge_status();
  perform pg_temp.assert(array_length(pg_temp.ids(a, 'daily'), 1) = 6 and array_length(pg_temp.ids(a, 'weekly'), 1) = 2, 'every Round B goal is handed out (rod, laptop, class, friend)');

  -- club spending: a club night counts at a club, not elsewhere; spray counts as both
  perform pg_temp.at(a, 'mechanic_village');
  perform bl_add_money(a, 'cash', -3000, 'activity', '{"activity":"club_night"}');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_club') = 0, 'a club activity outside a club does not count');
  perform pg_temp.at(a, 'kingdom_lounge');
  perform bl_add_money(a, 'cash', -3000, 'activity', '{"activity":"club_night"}');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_club') = 3000, 'a club night at a club counts as club spending');
  perform bl_add_money(a, 'cash', -1000, 'activity', '{"activity":"cook_home"}');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_club') = 3000, 'other activities do not');
  perform bl_add_money(a, 'cash', -2000, 'spray', '{"place":"Kingdom Lounge"}');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_spray') = 2000 and (pg_temp.item(a, 'daily', 'p_spray')->>'done')::boolean, 'spraying counts towards the spray goal');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_club') = 4000 and (pg_temp.item(a, 'daily', 'p_club')->>'done')::boolean, 'and towards club spending');

  -- fishing (a real hustle)
  perform pg_temp.at(a, 'ikpoba_riverbank');
  v := pg_temp.hrun(a, 'fish_cast');
  perform pg_temp.assert(v->'fish' is not null and v->>'outcome' = 'ok', format('caught a fish: %s', v));
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_fish') = 1, 'a catch counts');

  -- friends: arriving where a friend stands
  update profiles set location_id = 'oba_market', travel_to = null, last_seen = bl_now() where id = b;
  perform pg_temp.at(a, 'ring_road_pos');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_meet') = 0, 'no friend there: no link-up');
  perform pg_temp.at(a, 'oba_market');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_meet') = 1, 'arriving where a friend is counts');
  -- a hustle at the same place as a friend
  update profiles set location_id = 'ring_road_pos', last_seen = bl_now() where id = b;
  perform pg_temp.at(a, 'mechanic_village');
  perform pg_temp.hrun(a, 'mech_quick');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_fhus') = 0, 'friend elsewhere: a normal hustle does not count');
  update profiles set location_id = 'mechanic_village', travel_to = null, last_seen = bl_now() where id = b;
  perform pg_temp.hrun(a, 'mech_quick');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_fhus') = 1, 'a hustle where a friend stands counts');
  -- a friend who walked away long ago does not count
  update profiles set last_seen = bl_now() - interval '1 hour' where id = b;
  perform pg_temp.assert(not bl_chal_friend_at(a, 'mechanic_village'), 'a stale friend is not "there"');
  -- a friend's house
  insert into player_house_invites (host_id, guest_id, home_location_id, status, expires_at)
  values (b, a, (select home_location_id from profiles where id = b), 'knocking', bl_now() + interval '1 hour');
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_house') = 0, 'knocking is not visiting');
  update player_house_invites set status = 'admitted' where host_id = b and guest_id = a;
  perform pg_temp.assert(pg_temp.prog(a, 'daily', 'p_house') = 1, 'being let in counts');

  -- a class and a clean Yahoo run (the real run tables)
  insert into course_runs (user_id, course_id, class_no, location_id, resolve_at, status) values (a, v_course, 1, 'mechanic_village', bl_now(), 'running') returning id into v_run;
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'p_class') = 0, 'a class in progress does not count');
  update course_runs set status = 'done', outcome = 'ok', resolved_at = bl_now() where id = v_run;
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'p_class') = 1, 'a finished class counts');
  insert into yahoo_runs (user_id, job_id, started_at, resolve_at, status) values (a, 'chat_client', bl_now(), bl_now(), 'running') returning id into v_run;
  update yahoo_runs set status = 'caught' where id = v_run;
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'p_yahoo') = 0, 'a caught run does not count');
  insert into yahoo_runs (user_id, job_id, started_at, resolve_at, status) values (a, 'chat_client', bl_now(), bl_now(), 'running') returning id into v_run;
  update yahoo_runs set status = 'paid', amount = 5000 where id = v_run;
  perform pg_temp.assert(pg_temp.prog(a, 'weekly', 'p_yahoo') = 1, 'a clean run counts');
  perform pg_temp.cfg('challenges.daily_count', '3');
  perform pg_temp.cfg('challenges.weekly_count', '3');
  raise notice 'ok 11: the other goals';
end $$;

-- ---------- 12. no-op path, master switch, multiplier, admin ----------
do $$
declare
  a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); d uuid := pg_temp.u('d'); adm uuid := pg_temp.u('adm');
  v_rows int; v_ev int; v_id bigint; v_cash bigint; v jsonb; v_hint text;
begin
  -- no matching open challenge: nothing is written (the hot path is a probe)
  perform pg_temp.only(array['q1', 'q2', 'q3']);
  perform pg_temp.tpl('q1', 'daily', 'buy_item', 1, 1000); perform pg_temp.tpl('q2', 'daily', 'visit_place', 9, 100); perform pg_temp.tpl('q3', 'daily', 'spray', 99999, 100);
  perform pg_temp.login(d);
  perform challenge_status();
  select count(*) into v_rows from player_challenges; select count(*) into v_ev from events;
  perform bl_challenge_bump(d, 'fish', 1, null);
  perform bl_challenge_bump(d, 'streak', 3, null);
  perform bl_add_money(d, 'cash', 50, 'salary', '{}');
  perform pg_temp.assert((select count(*) from player_challenges) = v_rows and (select count(*) from events) = v_ev, 'bumps for goals the player does not have change nothing');
  perform pg_temp.assert(not exists (select 1 from player_challenges where user_id = d and progress > 0), 'no progress anywhere');
  -- bad amounts are ignored
  perform bl_challenge_bump(d, 'buy_item', 0, null); perform bl_challenge_bump(d, 'buy_item', -4, null); perform bl_challenge_bump(null, 'buy_item', 1, null);
  perform pg_temp.assert(pg_temp.prog(d, 'daily', 'q1') = 0, 'zero and negative amounts are ignored');
  -- param narrows a goal
  update player_challenges set param = 'puff_puff' where user_id = d and template_id = 'q1';
  perform bl_challenge_bump(d, 'buy_item', 1, 'garri_groundnut');
  perform pg_temp.assert(pg_temp.prog(d, 'daily', 'q1') = 0, 'the wrong item does not count for an item goal');
  perform bl_challenge_bump(d, 'buy_item', 1, 'puff_puff');
  perform pg_temp.assert(pg_temp.prog(d, 'daily', 'q1') = 1, 'the named item does');
  update player_challenges set param = null where user_id = d and template_id = 'q1';

  -- reward multiplier (double cash weekend)
  perform pg_temp.cfg('challenges.reward_mult', '2');
  v_id := (pg_temp.item(d, 'daily', 'q1')->>'id')::bigint;
  perform pg_temp.assert((pg_temp.item(d, 'daily', 'q1')->'reward'->>'cash')::bigint = 2000, 'status shows the multiplied reward');
  select cash into v_cash from profiles where id = d;
  perform challenge_claim(v_id);
  perform pg_temp.assert(pg_temp.cash(d) = v_cash + 2000, 'claim pays reward x multiplier');
  perform pg_temp.cfg('challenges.reward_mult', '1');

  -- master switch
  perform bl_challenge_bump(d, 'spray', 99999, null);
  v_id := (pg_temp.item(d, 'daily', 'q3')->>'id')::bigint;
  perform pg_temp.cfg('challenges.enabled', 'false');
  perform pg_temp.assert((challenge_status()->>'enabled')::boolean = false, 'switched off: status says disabled');
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_claim(%s)', v_id)) = 'disabled', 'switched off: claims refused');
  perform pg_temp.assert(pg_temp.hint_of('select challenge_claim_chest(''daily'')') = 'disabled', 'switched off: chests refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select challenge_reroll(%s)', v_id)) = 'disabled', 'switched off: rerolls refused');
  perform pg_temp.login(a);
  delete from player_challenges where user_id = a;
  perform bl_challenge_bump(a, 'buy_item', 1, null);
  perform pg_temp.assert(not exists (select 1 from player_challenges where user_id = a), 'switched off: nothing is handed out');
  perform pg_temp.cfg('challenges.enabled', 'true');
  perform pg_temp.login(d);
  perform challenge_claim(v_id);

  -- admin tools: the spec, the editor, the stats view
  perform pg_temp.assert(bl_admin_table_spec('challenge_templates') is not null and bl_admin_table_spec('challenge_template_stats') is not null, 'admin specs');
  perform pg_temp.assert(bl_admin_table_spec('daily_reward_steps') is not null and bl_admin_table_spec('skills') is not null and bl_admin_table_spec('courses') is not null,
                         'the older admin specs survived the patch');
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of('select admin_table_rows(''challenge_templates'')') <> 'ok', 'players cannot read the admin tables');
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''challenge_templates'', ''{"id":"q1","weight":1}'')') <> 'ok', 'players cannot edit templates');
  perform pg_temp.login(adm);
  perform pg_temp.assert(jsonb_array_length(admin_table_rows('challenge_templates')) >= 40, 'admin sees all templates');
  v := admin_row_upsert('challenge_templates', '{"id":"q1","weight":3,"reward_cash":1234,"title":"Edited title"}');
  perform pg_temp.assert((v->'row'->>'weight')::numeric = 3 and (v->'row'->>'reward_cash')::bigint = 1234, 'admin edits weight and reward');
  v := admin_row_upsert('challenge_templates', '{"id":"zz_new","kind":"daily","goal":"fish","title":"New one","blurb":"b","icon":"🎣","target":2,"reward_cash":500,"weight":5}');
  perform pg_temp.assert(v->>'message' = 'Added.', 'admin adds a template');
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''challenge_templates'', ''{"id":"zz_new","kind":"monthly"}'')') = 'bad_value', 'a bad kind is refused');
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''challenge_templates'', ''{"id":"zz_new","goal":"fly"}'')') = 'bad_value', 'a bad goal is refused');
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''challenge_templates'', ''{"id":"zz_new","target":0}'')') = 'bad_value', 'target 0 refused');
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''challenge_templates'', ''{"id":"zz_new","reward_skill":"nope"}'')') = 'bad_value', 'unknown skill refused');
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''challenge_templates'', ''{"id":"zz_new","bogus":1}'')') = 'bad_column', 'unknown column refused');
  v := admin_table_rows('challenge_template_stats');
  perform pg_temp.assert((select (x->>'completed')::int from jsonb_array_elements(v) x where x->>'id' = 'q1') >= 1, 'stats: completions per template (q1 was claimed)');
  perform pg_temp.assert((select (x->>'assigned')::int from jsonb_array_elements(v) x where x->>'id' = 'q2') >= 1, 'stats: assigned counts');
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''challenge_template_stats'', ''{"id":"q1","completed":9}'')') in ('bad_column', 'no_change', 'ok'), 'the stats view cannot be edited');
  perform pg_temp.assert((select completed from challenge_template_stats where id = 'q1') <> 9, 'stats unchanged');
  -- edit audit
  perform pg_temp.assert(exists (select 1 from admin_audit where action in ('row_update', 'row_insert') and data->>'table' = 'challenge_templates'), 'edits are audited');
  raise notice 'ok 12: no-op path, switch, multiplier, admin';
end $$;
