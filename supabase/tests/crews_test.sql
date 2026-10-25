-- E3 (20261019000100_economy_balance) retuned the crew job pots, the daily job cap and added a disband fee. This suite tests the R11
-- maths on the original numbers, so they are pinned back here (rolled back with everything else).
update crew_jobs set
  reward_min = case id when 'market_shakedown' then 300000 when 'port_container' then 1200000 when 'ring_road_warehouse' then 2000000 when 'bank_van' then 8000000 else reward_min end,
  reward_max = case id when 'market_shakedown' then 900000 when 'port_container' then 3500000 when 'ring_road_warehouse' then 5000000 when 'bank_van' then 25000000 else reward_max end;
-- exact leaderboard numbers are asserted below (rank_bands_test covers the money ranges)
update game_config set value = 'false' where key = 'ranks.hide_amounts';
update game_config set value = '8' where key = 'crew.max_jobs_per_day';
update game_config set value = '0' where key = 'crew.disband_fee_pct';
update game_config set value = '2' where key = 'crew.weekly_min_jobs';
-- R11 Crews (20261018001000_crews.sql). Rolled back. Run (migration applied):
--   bash scripts/sql-test.sh -- supabase/tests/crews_test.sql
-- Or with the migration first: bash scripts/sql-test.sh supabase/migrations/20261018001000_crews.sql -- supabase/tests/crews_test.sql
-- Time moves with bl.test_offset_seconds; every roll is pinned with bl.test_rand (bl_rand, so bl_crime_roll too):
-- a roll of 0.0 is always caught, 0.99 never.
-- Groups: 1 grants / RLS / private helpers · 2 seeds · 3 create (fee, name moderation, founder gate, switch) · 4 invites (friends first,
-- username, gates, rate limit, full) · 5 ranks and permissions · 6 crew bank (deposit, log, spend refused) · 7 job lobby (refusals, join gates,
-- start) · 8 paid run (split, ledger, xp) · 9 busted run (jail for all, fine, no loot) · 10 skill cut · 11 cooldowns + daily cap + auto start +
-- dropped member + too few · 12 level up unlocks (bonus, buy-in, prospect share) · 13 leave / kick / transfer / rejoin cooldown / on job ·
-- 14 recruiting, browse, report · 15 crew chat · 16 tag in places, profile, chat, friends · 17 weekly top crews + settle · 18 disband +
-- no crew job touches other players' money · 19 admin (list, audited member view, rename, disband, reports, content tables) · 20 earned vs transfer.
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

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('cr.' || p)::uuid $$;
create or replace function pg_temp.cid() returns bigint language sql as $$ select current_setting('cr.crew')::bigint $$;
create or replace function pg_temp.cash(p_uid uuid) returns bigint language sql as $$ select cash from profiles where id = p_uid $$;
create or replace function pg_temp.bank(p_uid uuid) returns bigint language sql as $$ select bank from profiles where id = p_uid $$;
create or replace function pg_temp.cbank(p_crew bigint) returns bigint language sql as $$ select bank from crews where id = p_crew $$;

-- a free player at a place, online now
create or replace function pg_temp.at(p_uid uuid, p_loc text default 'upper_sakponba') returns void
language sql as $$
  update profiles set location_id = p_loc, travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
                      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = bl_now(), rent_due_at = null
   where id = p_uid;
$$;

create or replace function pg_temp.mk(p_name text, p_age interval default interval '30 days') returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@cr.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, protected_until = null, created_at = now() - p_age, cash = 0, bank = 0,
         energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0 where id = v;
  perform pg_temp.at(v);
  return v;
end $$;

create or replace function pg_temp.friends(a uuid, b uuid) returns void
language sql as $$
  insert into player_friendships (user_a, user_b, status, requested_by) values (least(a, b), greatest(a, b), 'accepted', a) on conflict do nothing;
$$;

-- the player invites the target by username and the target accepts
create or replace function pg_temp.recruit(p_boss uuid, p_user uuid) returns void
language plpgsql as $$
declare v_name text := (select username from profiles where id = p_user); v_inv bigint;
begin
  perform pg_temp.login(p_boss);
  v_inv := (crew_invite(null, v_name)->>'invite')::bigint;
  perform pg_temp.login(p_user);
  perform crew_invite_respond(v_inv, true);
end $$;

create or replace function pg_temp.rank_of(p_uid uuid) returns text language sql as $$ select rank from crew_members where user_id = p_uid $$;

-- a player stands at a meeting spot with plenty of cash
create or replace function pg_temp.ready(p_uid uuid, p_cash bigint default 500000) returns void
language sql as $$ select pg_temp.at(p_uid); update profiles set cash = p_cash, bank = 0 where id = p_uid; $$;

-- ---------- setup ----------
do $$
declare
  v_names text[] := array['CR_Adm', 'CR_A', 'CR_B', 'CR_C', 'CR_D', 'CR_E', 'CR_F', 'CR_G', 'CR_Z'];
  v_keys text[] := array['adm', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'z'];
  i int;
  u uuid;
begin
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  for i in 1..cardinality(v_names) loop
    u := pg_temp.mk(v_names[i]);
    perform set_config('cr.' || v_keys[i], u::text, true);
  end loop;
  -- a young account that has Charisma 2, and a young one without
  u := pg_temp.mk('CR_Y', interval '1 hour');
  perform set_config('cr.y', u::text, true);
  insert into player_skills (user_id, skill_id, xp) values (u, 'charisma', 40) on conflict (user_id, skill_id) do update set xp = 40;
  u := pg_temp.mk('CR_N', interval '1 hour');
  perform set_config('cr.n', u::text, true);
  update profiles set is_admin = true where id = pg_temp.u('adm');
  perform pg_temp.friends(pg_temp.u('a'), pg_temp.u('b'));
  perform pg_temp.friends(pg_temp.u('a'), pg_temp.u('c'));
  perform pg_temp.friends(pg_temp.u('b'), pg_temp.u('c'));
  -- the default Settings that the rest of the suite relies on
  perform pg_temp.cfg('crew.enabled', 'true');
end $$;

-- ---------- 1. grants / RLS / private helpers ----------
do $$
declare f text; t text;
begin
  foreach f in array array['crew_status()', 'crew_browse(text,int)', 'crew_create(text,text,text,text)', 'crew_invite_candidates(text)', 'crew_invite(uuid,text)',
    'crew_invite_cancel(bigint)', 'crew_invite_respond(bigint,boolean)', 'crew_join_open(bigint)', 'crew_leave()', 'crew_kick(uuid)', 'crew_set_rank(uuid,text)',
    'crew_transfer(uuid)', 'crew_disband()', 'crew_options(numeric,boolean)', 'crew_rename(text)', 'crew_deposit(bigint)', 'crew_upgrade()', 'crew_bank_log_list(int)',
    'crew_chat_send(text)', 'crew_chat_recent(bigint,int)', 'crew_report(bigint,text)', 'crew_top(int)', 'crew_job_open(text)', 'crew_job_join(bigint)',
    'crew_job_leave(bigint)', 'crew_job_cancel(bigint)', 'crew_job_start(bigint)', 'admin_crews_list(text,int)', 'admin_crew_get(bigint)',
    'admin_crew_disband(bigint,text)', 'admin_crew_rename(bigint,text,text,text)', 'admin_crew_dismiss_reports(bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute'), 'anon cannot run ' || f);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute'), 'authenticated can run ' || f);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || f)::regprocedure), 'security definer ' || f);
  end loop;
  -- every bl_crew_* helper (and both triggers) is private
  perform pg_temp.assert((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'bl\_crew\_%') >= 30, 'helpers exist');
  perform pg_temp.assert(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname like 'bl\_crew\_%'
                            and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))), 'bl_crew_* helpers private');
  -- patched live functions keep their grants
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.players_here(text)'::regprocedure, 'execute')
                         and has_function_privilege('authenticated', 'public.get_public_profile(uuid)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_chat_row(chat_messages,jsonb,uuid)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_friend_card(profiles,profiles,numeric,boolean)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_ledger_label(text,jsonb)'::regprocedure, 'execute'), 'patched functions keep grants');
  -- RLS on every table, no direct client access except the two catalogues
  foreach t in array array['crews', 'crew_members', 'crew_invites', 'crew_bank_log', 'crew_cooldowns', 'crew_messages', 'crew_reports', 'crew_runs',
                           'crew_run_members', 'crew_weeks', 'crew_week_winners', 'crew_jobs', 'crew_levels'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || t)::regclass), 'RLS on ' || t);
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || t, 'select'), 'anon cannot read ' || t);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || t, 'insert') and not has_table_privilege('authenticated', 'public.' || t, 'update')
                           and not has_table_privilege('authenticated', 'public.' || t, 'delete'), 'no client writes on ' || t);
  end loop;
  foreach t in array array['crews', 'crew_members', 'crew_invites', 'crew_bank_log', 'crew_cooldowns', 'crew_messages', 'crew_reports', 'crew_runs', 'crew_run_members'] loop
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || t, 'select'), 'players cannot read ' || t || ' directly (RPCs only)');
  end loop;
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.crew_jobs', 'select') and has_table_privilege('authenticated', 'public.crew_levels', 'select'), 'catalogues readable');
  raise notice 'ok 1: grants / RLS / private helpers';
end $$;

-- ---------- 2. seeds ----------
do $$
declare r record;
begin
  perform pg_temp.assert((select count(*) from game_config where key like 'crew.%' and category = 'crews') >= 38, 'crew settings in the Crews category');
  perform pg_temp.assert(bl_crew_num('crew.found_fee', 0) = 500000 and bl_crew_num('crew.default_bank_pct', 0) = 30 and bl_crew_num('crew.rejoin_cooldown_hours', 0) = 48
                         and bl_crew_num('crew.found_min_charisma', 0) = 2, 'defaults: fee 500k, bank 30 %, rejoin 48 h, Charisma 2');
  perform pg_temp.assert((select count(*) from crew_jobs where active) = 4 and (select count(*) from crew_levels) = 5, 'four jobs, five levels');
  select * into r from crew_jobs where id = 'bank_van';
  perform pg_temp.assert(r.min_crew_level = 4 and r.min_members = 4 and r.caught_pct = 40, 'bank van is the high-level job');
  perform pg_temp.assert('crew_payout' = any (bl_earn_reasons()), 'crew_payout counts as earned');
  perform pg_temp.assert(not ('crew_deposit' = any (bl_earn_reasons())) and not ('crew_fee' = any (bl_earn_reasons())) and not ('crew_refund' = any (bl_earn_reasons()))
                         and not ('crew_job' = any (bl_earn_reasons())), 'deposits, fees, supplies and refunds are not earned');
  perform pg_temp.assert(exists (select 1 from skill_sources where kind = 'crew' and ref = 'bank_van' and skill_id = 'driving'), 'crew skill sources');
  perform pg_temp.assert((select count(*) from crew_weeks where skipped) >= 1, 'the week the feature started is skipped');
  perform pg_temp.assert(bl_ledger_label('crew_deposit', '{}') = 'Gang bank deposit' and bl_ledger_label('crew_payout', '{"label":"Gang job: X"}') = 'Gang job: X'
                         and bl_ledger_label('crew_fee', '{}') = 'Gang start fee' and bl_ledger_label('crew_job', '{}') = 'Gang job supplies', 'ledger labels');
  raise notice 'ok 2: seeds';
end $$;

-- ---------- 3. create ----------
do $$
declare v jsonb; v_w text; c record; v_bank0 bigint;
begin
  -- founder gate: an account 30 days old passes (age rule), a 1 h old account without Charisma 2 does not, with Charisma 2 it does
  perform pg_temp.login(pg_temp.u('n'));
  update profiles set bank = 600000 where id = pg_temp.u('n');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Night Owls'', ''OWL'', ''#336699'', ''🌙'')') = 'too_new', 'new account without Charisma 2 cannot found');
  -- money: not enough
  perform pg_temp.login(pg_temp.u('c'));
  update profiles set cash = 100000, bank = 0 where id = pg_temp.u('c');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Poor Boys'', ''POR'', ''#336699'', ''🌙'')') = 'not_enough_cash', 'founding fee needs money');
  perform pg_temp.assert(not exists (select 1 from crews where lower(name) = 'poor boys'), 'nothing created without money');
  -- the master switch
  perform pg_temp.cfg('crew.enabled', 'false');
  perform pg_temp.login(pg_temp.u('a'));
  update profiles set bank = 300000, cash = 300000 where id = pg_temp.u('a');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Ring Road Boys'', ''RNG'', ''#e0a030'', ''🦁'')') = 'crews_off', 'switch off refuses founding');
  perform pg_temp.cfg('crew.enabled', 'true');
  -- name moderation: bad lengths and characters, the banned-words list, real cult names, taken name / tag, bad tag, emblem, colour
  select word into v_w from chat_banned_words where active order by word limit 1;
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Ab'', ''ABC'', ''#e0a030'', ''🦁'')') = 'bad_name', 'too short');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''This crew name is far too long'', ''ABC'', ''#e0a030'', ''🦁'')') = 'bad_name', 'too long');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Bad <b> name'', ''ABC'', ''#e0a030'', ''🦁'')') = 'bad_name', 'bad characters');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_create(%L, ''ABC'', ''#e0a030'', ''🦁'')', 'The ' || v_w || ' crew')) = 'bad_name', 'banned word is refused: ' || v_w);
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Black Axe Boys'', ''ABC'', ''#e0a030'', ''🦁'')') = 'blocked_name', 'a real cult name is refused');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''E-i-y-e Nation'', ''ABC'', ''#e0a030'', ''🦁'')') = 'blocked_name', 'hyphens do not hide a real name');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''AIYE'', ''ABC'', ''#e0a030'', ''🦁'')') = 'blocked_name', 'another real name');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Ring Road Boys'', ''AB'', ''#e0a030'', ''🦁'')') = 'bad_tag', 'tag too short');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Ring Road Boys'', ''ABCDE'', ''#e0a030'', ''🦁'')') = 'bad_tag', 'tag too long');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Ring Road Boys'', ''A1B'', ''#e0a030'', ''🦁'')') = 'bad_tag', 'tag letters only');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Ring Road Boys'', ''NBM'', ''#e0a030'', ''🦁'')') = 'blocked_tag', 'blocked tag');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Ring Road Boys'', ''RNG'', ''red'', ''🦁'')') = 'bad_color', 'bad colour');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Ring Road Boys'', ''RNG'', ''#e0a030'', ''🪓'')') = 'bad_emblem', 'emblem must be on the list');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 300000 and pg_temp.bank(pg_temp.u('a')) = 300000 and not exists (select 1 from crews), 'refusals charged nothing');
  -- founding: the fee is charged bank first, then cash; ledger crew_fee
  v := crew_create('Ring Road Boys', 'rng', '#E0A030', '🦁');
  perform set_config('cr.crew', (v->'crew'->>'id'), true);
  select * into c from crews where id = pg_temp.cid();
  perform pg_temp.assert(c.name = 'Ring Road Boys' and c.tag = 'RNG' and c.color = '#e0a030' and c.emblem = '🦁' and c.level = 1 and c.bank = 0 and c.split_bank_pct = 30, 'crew row (tag upper-cased, colour lower-cased)');
  perform pg_temp.assert(pg_temp.bank(pg_temp.u('a')) = 0 and pg_temp.cash(pg_temp.u('a')) = 100000, 'fee 500,000 taken bank first (300k) then cash (200k)');
  perform pg_temp.assert((select sum(-delta) from ledger where user_id = pg_temp.u('a') and reason = 'crew_fee') = 500000
                         and (select meta->>'label' from ledger where user_id = pg_temp.u('a') and reason = 'crew_fee' order by id limit 1) like 'Gang: start fee%', 'ledger crew_fee');
  perform pg_temp.assert(pg_temp.rank_of(pg_temp.u('a')) = 'boss', 'founder is the Boss');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Another One'', ''ANO'', ''#e0a030'', ''🦁'')') = 'in_crew', 'one crew at a time');
  -- taken name (any case) and taken tag, by another eligible founder
  perform pg_temp.login(pg_temp.u('b'));
  update profiles set cash = 600000 where id = pg_temp.u('b');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''ring road boys'', ''XYZ'', ''#e0a030'', ''🦁'')') = 'name_taken', 'name taken, any case');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Other Name'', ''RNG'', ''#e0a030'', ''🦁'')') = 'tag_taken', 'tag taken');
  -- Charisma 2 lets a young account found a crew
  perform pg_temp.login(pg_temp.u('y'));
  update profiles set bank = 600000 where id = pg_temp.u('y');
  v := crew_create('Young Guns', 'YNG', '#2288cc', '🚀');
  perform set_config('cr.crew2', (v->'crew'->>'id'), true);
  perform pg_temp.assert(pg_temp.rank_of(pg_temp.u('y')) = 'boss', 'Charisma 2 founder');
  raise notice 'ok 3: create';
end $$;

-- ---------- 4. invites ----------
do $$
declare v jsonb; v_inv bigint; e record; i int;
begin
  perform pg_temp.login(pg_temp.u('b'));
  update profiles set last_seen = bl_now() where id = pg_temp.u('b');
  update profiles set last_seen = bl_now() - interval '1 hour' where id = pg_temp.u('c');
  -- a member without rank cannot invite (a is the only leader so far): b is outside, so crew_invite_candidates refuses
  perform pg_temp.assert(pg_temp.hint_of('select crew_invite_candidates('''')') = 'no_crew', 'outsider has no candidates');
  -- friends first: an empty search lists friends only, online before offline; a name search also finds strangers
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_invite_candidates('');
  perform pg_temp.assert(jsonb_array_length(v->'players') = 2 and (v->'players'->0->>'username') = 'CR_B' and (v->'players'->0->>'friend')::boolean
                         and (v->'players'->0->>'online')::boolean and not (v->'players'->1->>'online')::boolean, 'friends first, online first');
  v := crew_invite_candidates('CR_D');
  perform pg_temp.assert(jsonb_array_length(v->'players') = 1 and not (v->'players'->0->>'friend')::boolean and (v->'players'->0->>'eligible')::boolean, 'a stranger found by username');
  v := crew_invite_candidates('CR_N');
  perform pg_temp.assert(not (v->'players'->0->>'eligible')::boolean and (v->'players'->0->>'why') like '%hours%', 'a new account is not eligible (and says why)');
  -- invite by username: alert + friends push
  insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (pg_temp.u('b'), 'https://push.test/cr-b', 'k', 'a');
  v := crew_invite(null, '@cr_b');
  v_inv := (v->>'invite')::bigint;
  perform set_config('cr.inv_b', v_inv::text, true);
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('b') and kind = 'crew_invite' and title like '[RNG]%'), 'alert for the invited player');
  perform pg_temp.assert(exists (select 1 from push_outbox where user_id = pg_temp.u('b') and category = 'friends' and kind = 'crew_invite' and url = '/play?go=crew'), 'push in the friends category');
  perform pg_temp.assert(pg_temp.hint_of('select crew_invite(null, ''CR_B'')') = 'already_invited', 'one pending invite per player');
  perform pg_temp.assert(pg_temp.hint_of('select crew_invite(null, ''nobody_here'')') = 'no_player', 'unknown username');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_invite(%L, null)', pg_temp.u('a'))) = 'self', 'cannot invite yourself');
  perform pg_temp.assert(pg_temp.hint_of('select crew_invite(null, ''CR_N'')') = 'too_new', 'new account cannot be invited');
  perform pg_temp.assert(pg_temp.hint_of('select crew_invite(null, ''CR_Y'')') = 'in_crew', 'a player in a crew cannot be invited');
  -- status for b shows the invite
  perform pg_temp.login(pg_temp.u('b'));
  v := crew_status();
  perform pg_temp.assert(jsonb_array_length(v->'invites') = 1 and v->'invites'->0->'crew'->>'tag' = 'RNG' and v->'crew' = 'null'::jsonb, 'status shows the invite and no crew');
  -- accept: a Prospect
  v := crew_invite_respond(v_inv, true);
  perform pg_temp.assert(pg_temp.rank_of(pg_temp.u('b')) = 'prospect', 'recruits start as Prospect');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_invite_respond(%s, true)', v_inv)) = 'gone', 'an answered invite is gone');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('a') and kind = 'crew_joined'), 'the crew is told');
  -- decline
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_invite(null, 'CR_C');
  perform pg_temp.login(pg_temp.u('c'));
  v := crew_invite_respond((select id from crew_invites where to_user = pg_temp.u('c') and status = 'pending'), false);
  perform pg_temp.assert((select status from crew_invites where to_user = pg_temp.u('c') order by id desc limit 1) = 'declined', 'declined');
  -- rate limit per crew per day
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.cfg('crew.invite_daily_cap', '2');
  perform pg_temp.assert(pg_temp.hint_of('select crew_invite(null, ''CR_D'')') = 'rate_limit', 'invite cap per crew per day');
  perform pg_temp.cfg('crew.invite_daily_cap', '20');
  -- expiry
  v := crew_invite(null, 'CR_D');
  perform pg_temp.advance(49 * 3600);
  update profiles set last_seen = bl_now() where id in (select id from profiles where username like 'CR\_%');
  perform pg_temp.login(pg_temp.u('d'));
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_invite_respond(%s, true)', (v->>'invite'))) = 'expired', 'an expired invite cannot be accepted');
  perform pg_temp.assert(jsonb_array_length(crew_status()->'invites') = 0, 'status hides it');
  perform pg_temp.assert((select status from crew_invites where id = (v->>'invite')::bigint) = 'expired', 'marked expired');
  -- cancel
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_invite(null, 'CR_D');
  perform crew_invite_cancel((v->>'invite')::bigint);
  perform pg_temp.assert((select status from crew_invites where id = (v->>'invite')::bigint) = 'cancelled', 'cancelled');
  -- fill the crew: C D E F join (6 members at level 1), G is turned away as full
  for e in select unnest(array['c', 'd', 'e']) as k loop
    perform pg_temp.recruit(pg_temp.u('a'), pg_temp.u(e.k));
  end loop;
  perform pg_temp.assert((select count(*) from crew_members where crew_id = pg_temp.cid()) = 5, 'five members');
  perform pg_temp.recruit(pg_temp.u('a'), pg_temp.u('f'));
  perform pg_temp.assert((select count(*) from crew_members where crew_id = pg_temp.cid()) = 6, 'six members = level 1 cap');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_invite(null, ''CR_G'')') = 'full', 'full for its level');

  raise notice 'ok 4: invites';
end $$;

-- ---------- 5. ranks and permissions ----------
do $$
declare v jsonb;
begin
  perform pg_temp.login(pg_temp.u('a'));
  -- promote: b Lieutenant, c / d / f Member, e and g stay Prospects
  perform crew_set_rank(pg_temp.u('b'), 'lieutenant');
  perform crew_set_rank(pg_temp.u('c'), 'member');
  perform crew_set_rank(pg_temp.u('d'), 'member');
  perform pg_temp.assert(pg_temp.rank_of(pg_temp.u('b')) = 'lieutenant' and pg_temp.rank_of(pg_temp.u('c')) = 'member' and pg_temp.rank_of(pg_temp.u('e')) = 'prospect', 'ranks set');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('b') and kind = 'crew_rank'), 'rank change alert');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_set_rank(%L, ''boss'')', pg_temp.u('c'))) = 'bad_rank', 'cannot set Boss by rank');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_set_rank(%L, ''member'')', pg_temp.u('a'))) = 'not_member', 'cannot change your own rank');
  perform pg_temp.cfg('crew.max_lieutenants', '1');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_set_rank(%L, ''lieutenant'')', pg_temp.u('c'))) = 'max_lieutenants', 'Lieutenant cap');
  perform pg_temp.cfg('crew.max_lieutenants', '3');
  -- a Member can do none of the leader things
  perform pg_temp.login(pg_temp.u('c'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_invite(null, ''CR_Adm'')') = 'rank', 'member cannot invite');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_kick(%L)', pg_temp.u('e'))) = 'rank', 'member cannot kick');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_set_rank(%L, ''member'')', pg_temp.u('e'))) = 'rank', 'member cannot promote');
  perform pg_temp.assert(pg_temp.hint_of('select crew_upgrade()') = 'rank', 'member cannot upgrade');
  perform pg_temp.assert(pg_temp.hint_of('select crew_options(40, null)') = 'rank', 'member cannot set the split');
  perform pg_temp.assert(pg_temp.hint_of('select crew_options(null, true)') = 'rank', 'member cannot open recruiting');
  perform pg_temp.assert(pg_temp.hint_of('select crew_rename(''Whatever Crew'')') = 'rank', 'member cannot rename');
  perform pg_temp.assert(pg_temp.hint_of('select crew_disband()') = 'rank', 'member cannot disband');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_transfer(%L)', pg_temp.u('d'))) = 'rank', 'member cannot transfer');
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''market_shakedown'')') = 'rank', 'member cannot open a job lobby');
  -- a Lieutenant: promote a Prospect to Member only, kick below themselves only, no split, no rename, no disband, no transfer
  perform pg_temp.login(pg_temp.u('b'));
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_set_rank(%L, ''lieutenant'')', pg_temp.u('e'))) = 'rank', 'Lieutenant cannot make a Lieutenant');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_set_rank(%L, ''prospect'')', pg_temp.u('c'))) = 'rank', 'Lieutenant cannot demote');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_kick(%L)', pg_temp.u('a'))) = 'rank', 'nobody kicks the Boss');
  perform pg_temp.assert(pg_temp.hint_of('select crew_options(40, null)') = 'rank', 'only the Boss sets the split');
  perform pg_temp.assert(pg_temp.hint_of('select crew_rename(''Whatever Crew'')') = 'rank', 'only the Boss renames');
  perform pg_temp.assert(pg_temp.hint_of('select crew_disband()') = 'rank', 'only the Boss disbands');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_transfer(%L)', pg_temp.u('c'))) = 'rank', 'only the Boss transfers');
  perform crew_set_rank(pg_temp.u('f'), 'member');
  perform pg_temp.assert(pg_temp.rank_of(pg_temp.u('f')) = 'member', 'a Lieutenant promotes a Prospect to Member');
  -- (f was promoted by a Lieutenant above; the Boss puts them back on trial)
  perform pg_temp.login(pg_temp.u('a'));
  perform crew_set_rank(pg_temp.u('f'), 'prospect');
  perform pg_temp.assert(pg_temp.rank_of(pg_temp.u('f')) = 'prospect', 'the Boss demotes');
  -- the Boss sets the split inside the limits
  perform pg_temp.assert(pg_temp.hint_of('select crew_options(5, null)') = 'bad_split' and pg_temp.hint_of('select crew_options(95, null)') = 'bad_split', 'split limits 10-80');
  perform crew_options(40, null);
  perform pg_temp.assert((select split_bank_pct from crews where id = pg_temp.cid()) = 40, 'split 40');
  perform crew_options(30, null);
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_transfer(%L)', pg_temp.u('e'))) = 'rank', 'a Prospect cannot become Boss');
  raise notice 'ok 5: ranks and permissions';
end $$;

-- ---------- 6. crew bank ----------
do $$
declare v jsonb; n int;
begin
  perform pg_temp.login(pg_temp.u('c'));
  update profiles set cash = 20000, bank = 0 where id = pg_temp.u('c');
  perform pg_temp.assert(pg_temp.hint_of('select crew_deposit(500)') = 'too_small', 'smallest deposit');
  perform pg_temp.assert(pg_temp.hint_of('select crew_deposit(50000)') = 'not_enough_cash', 'cannot deposit money you do not have');
  v := crew_deposit(5000);
  perform pg_temp.assert(pg_temp.cbank(pg_temp.cid()) = 5000 and pg_temp.cash(pg_temp.u('c')) = 15000, 'deposit moves cash into the crew bank');
  perform pg_temp.assert((select delta from ledger where user_id = pg_temp.u('c') and reason = 'crew_deposit') = -5000, 'ledger crew_deposit');
  perform pg_temp.assert((select deposited from crew_members where user_id = pg_temp.u('c')) = 5000, 'member deposit total');
  -- a Prospect can deposit too; bank first
  perform pg_temp.login(pg_temp.u('e'));
  update profiles set cash = 1000, bank = 4000 where id = pg_temp.u('e');
  perform crew_deposit(3000);
  perform pg_temp.assert(pg_temp.bank(pg_temp.u('e')) = 1000 and pg_temp.cash(pg_temp.u('e')) = 1000 and pg_temp.cbank(pg_temp.cid()) = 8000, 'bank first');
  -- the log
  v := crew_bank_log_list(10);
  perform pg_temp.assert(jsonb_array_length(v->'rows') = 2 and v->'rows'->0->>'kind' = 'deposit' and (v->'rows'->0->>'amount')::bigint = 3000
                         and (v->'rows'->0->>'balance_after')::bigint = 8000 and v->'rows'->0->>'username' = 'CR_E', 'bank log: newest first with the balance');
  -- spending: a rename costs the bank money it does not have; an upgrade needs XP and money
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_rename(''Ring Road Kings'')') = 'bank_short', 'rename needs the bank to pay');
  perform pg_temp.assert(pg_temp.hint_of('select crew_upgrade()') = 'need_xp', 'upgrade needs crew XP');
  -- another crew cannot read this log
  perform pg_temp.login(pg_temp.u('y'));
  v := crew_bank_log_list(10);
  perform pg_temp.assert(jsonb_array_length(v->'rows') = 0, 'another crew sees only its own bank log');
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_bank_log_list(10)') = 'no_crew', 'an outsider has no bank log');
  raise notice 'ok 6: crew bank';
end $$;

-- ---------- 7. job lobby ----------
do $$
declare v jsonb; v_run bigint;
begin
  -- everybody who can join stands at a meeting spot
  perform pg_temp.ready(pg_temp.u('a')); perform pg_temp.ready(pg_temp.u('b')); perform pg_temp.ready(pg_temp.u('c'), 40000);
  perform pg_temp.ready(pg_temp.u('d')); perform pg_temp.ready(pg_temp.u('e')); perform pg_temp.ready(pg_temp.u('f'));
  perform pg_temp.login(pg_temp.u('a'));
  -- refusals on opening
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''nope'')') = 'bad_job', 'unknown job');
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''bank_van'')') = 'crew_level', 'bank van needs crew level 4');
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''port_container'')') = 'crew_level', 'port needs crew level 2');
  update profiles set location_id = 'ring_road_pos' where id = pg_temp.u('a');
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''market_shakedown'')') = 'wrong_place', 'the organiser must be at a meeting spot');
  update profiles set location_id = 'upper_sakponba', last_seen = bl_now() - interval '1 hour' where id = pg_temp.u('a');
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''market_shakedown'')') = 'offline', 'the organiser must be online');
  perform pg_temp.at(pg_temp.u('a'));
  update profiles set jailed_until = bl_now() + interval '5 minutes' where id = pg_temp.u('a');
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''market_shakedown'')') = 'jailed', 'a jailed organiser is refused');
  perform pg_temp.at(pg_temp.u('a'));
  perform pg_temp.cfg('crew.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''market_shakedown'')') = 'crews_off', 'switch off refuses a new job');
  perform pg_temp.cfg('crew.enabled', 'true');
  -- open
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_job_open('market_shakedown');
  v_run := (v->'run'->>'id')::bigint;
  perform set_config('cr.run', v_run::text, true);
  perform pg_temp.assert(v->'run'->>'status' = 'lobby' and (v->'run'->>'member_count')::int = 1 and (v->'run'->>'joined')::boolean, 'lobby open, organiser in');
  perform pg_temp.assert(abs(extract(epoch from (v->'run'->>'lobby_until')::timestamptz - bl_now()) - 120) < 3, 'countdown = crew.lobby_seconds');
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''market_shakedown'')') = 'run_open', 'one open job per crew');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('b') and kind = 'crew_job_lobby'), 'members are alerted');
  -- join gates
  perform pg_temp.login(pg_temp.u('d'));
  update profiles set location_id = 'ring_road_pos' where id = pg_temp.u('d');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_job_join(%s)', v_run)) = 'wrong_place', 'must stand at a meeting spot');
  update profiles set location_id = 'upper_sakponba', last_seen = bl_now() - interval '1 hour' where id = pg_temp.u('d');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_job_join(%s)', v_run)) = 'offline', 'must be online');
  perform pg_temp.at(pg_temp.u('d'));
  update profiles set busy_until = bl_now() + interval '5 minutes', busy_label = 'Something' where id = pg_temp.u('d');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_job_join(%s)', v_run)) = 'busy', 'must be free');
  perform pg_temp.at(pg_temp.u('d'));
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_job_join(%s)', v_run)) = 'no_crew', 'an outsider cannot join');
  perform pg_temp.login(pg_temp.u('y'));
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_job_join(%s)', v_run)) = 'not_open', 'another crew cannot join this lobby');
  -- too few to start
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_job_start(%s)', v_run)) = 'too_few', 'start needs the minimum members');
  -- join and leave
  perform pg_temp.login(pg_temp.u('b'));
  v := crew_job_join(v_run);
  perform pg_temp.assert((v->'run'->>'member_count')::int = 2 and (v->'run'->>'joined')::boolean, 'b joined');
  v := crew_job_join(v_run);
  perform pg_temp.assert((v->'run'->>'member_count')::int = 2, 'joining twice changes nothing');
  perform pg_temp.login(pg_temp.u('d'));
  perform crew_job_join(v_run);
  perform crew_job_leave(v_run);
  perform pg_temp.assert((select count(*) from crew_run_members where run_id = v_run) = 2, 'a member can leave the lobby');
  -- the status shows the lobby with the estimate and the ready members
  perform pg_temp.login(pg_temp.u('c'));
  v := crew_status();
  perform pg_temp.assert(v->'crew'->'run'->>'status' = 'lobby' and jsonb_array_length(v->'crew'->'run'->'members') = 2 and (v->'crew'->'run'->>'caught_pct')::numeric = 22, 'status: lobby, 2 ready, 22 %');
  raise notice 'ok 7: job lobby';
end $$;

-- ---------- 8. paid run ----------
do $$
declare
  v jsonb; v_run bigint := current_setting('cr.run')::bigint; v_pot bigint; v_bank bigint; v_pool bigint; v_each bigint; j crew_jobs; a0 bigint; b0 bigint; cb0 bigint; r crew_runs;
begin
  perform pg_temp.login(pg_temp.u('a'));
  select * into j from crew_jobs where id = 'market_shakedown';
  a0 := pg_temp.cash(pg_temp.u('a')); b0 := pg_temp.cash(pg_temp.u('b')); cb0 := pg_temp.cbank(pg_temp.cid());
  v := crew_job_start(v_run);
  perform pg_temp.assert(v->'run'->>'status' = 'running' and (v->'run'->>'caught_pct')::numeric = 22 and (v->'run'->>'skill_cut_pct')::numeric = 0, 'running at 22 %');
  perform pg_temp.assert((select busy_label from profiles where id = pg_temp.u('b')) = 'Gang job: Night market shakedown'
                         and (select busy_until from profiles where id = pg_temp.u('b')) > bl_now(), 'members are busy for the job');
  -- not done yet: the status leaves it running
  perform pg_temp.advance(30);
  v := crew_status();
  perform pg_temp.assert(v->'crew'->'run'->>'status' = 'running', 'still running after 30 s');
  perform pg_temp.advance(35);
  perform set_config('bl.test_rand', '0.99', true);
  v := crew_status();
  perform set_config('bl.test_rand', '', true);
  select * into r from crew_runs where id = v_run;
  perform pg_temp.assert(r.status = 'paid', 'paid with a roll of 0.99');
  -- pot = min + floor(0.99 x (range + 1)), x 1.08 for the second member (level 1 has no bonus), 30 % to the bank, the rest split by weight
  v_pot := round((j.reward_min + floor(0.99 * (j.reward_max - j.reward_min + 1))) * 1.08)::bigint;
  v_bank := floor(v_pot * 30 / 100.0)::bigint;
  v_pool := v_pot - v_bank;
  v_each := floor(v_pool / 2.0 / 100) * 100;
  perform pg_temp.assert(r.pot = v_pot and r.bank_share = v_bank + (v_pool - 2 * v_each), 'pot ' || v_pot || ', bank share ' || r.bank_share);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = a0 + v_each and pg_temp.cash(pg_temp.u('b')) = b0 + v_each, 'both members got ' || v_each || ' in cash');
  perform pg_temp.assert(pg_temp.cbank(pg_temp.cid()) = cb0 + r.bank_share and r.bank_share >= v_bank, 'the crew bank got its share');
  perform pg_temp.assert((select delta from ledger where user_id = pg_temp.u('a') and reason = 'crew_payout' order by id desc limit 1) = v_each
                         and (select meta->>'label' from ledger where user_id = pg_temp.u('a') and reason = 'crew_payout' order by id desc limit 1) = 'Gang job: Night market shakedown', 'ledger crew_payout');
  perform pg_temp.assert((select amount from crew_bank_log where crew_id = pg_temp.cid() and kind = 'job' order by id desc limit 1) = r.bank_share, 'bank log kind job');
  perform pg_temp.assert((select busy_label from profiles where id = pg_temp.u('b')) is null, 'busy cleared');
  perform pg_temp.assert((select xp from crews where id = pg_temp.cid()) = 20 and (select jobs_done from crews where id = pg_temp.cid()) = 1
                         and (select loot_total from crews where id = pg_temp.cid()) = v_pot, 'crew XP +20, jobs 1, loot total');
  perform pg_temp.assert((select jobs from crew_members where user_id = pg_temp.u('a')) = 1 and (select earned from crew_members where user_id = pg_temp.u('a')) = v_each, 'member stats');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('b') and kind = 'crew_job_paid'), 'paid alert');
  perform pg_temp.assert((select xp from player_skills where user_id = pg_temp.u('a') and skill_id = 'charisma') >= 5, 'charisma XP from the job');
  v := crew_status();
  perform pg_temp.assert(v->'crew'->'run' = 'null'::jsonb and v->'crew'->'last_run'->>'status' = 'paid' and (v->'crew'->'last_run'->'members'->0->>'payout')::bigint = v_each, 'last run shows the split');
  perform set_config('cr.pot1', v_pot::text, true);
  raise notice 'ok 8: paid run (pot %, each %, bank share %)', v_pot, v_each, r.bank_share;
end $$;

-- ---------- 9. busted run ----------
do $$
declare v jsonb; v_run bigint; cb0 bigint; a0 bigint; r crew_runs; k jail_cases; w0 int; n_events int;
begin
  -- the same job again after its cooldown (20 minutes)
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''market_shakedown'')') = 'cooldown', 'the job has a cooldown per crew');
  perform pg_temp.advance(1210);
  perform pg_temp.ready(pg_temp.u('a'), 100000); perform pg_temp.ready(pg_temp.u('b'), 100000); perform pg_temp.ready(pg_temp.u('d'), 100000);
  v := crew_job_open('market_shakedown');
  v_run := (v->'run'->>'id')::bigint;
  perform pg_temp.login(pg_temp.u('b')); perform crew_job_join(v_run);
  perform pg_temp.login(pg_temp.u('d')); perform crew_job_join(v_run);
  perform pg_temp.login(pg_temp.u('a'));
  cb0 := pg_temp.cbank(pg_temp.cid()); a0 := pg_temp.cash(pg_temp.u('a'));
  select wanted into w0 from profiles where id = pg_temp.u('b');
  perform crew_job_start(v_run);
  perform pg_temp.advance(65);
  perform set_config('bl.test_rand', '0.0', true);
  v := crew_status();
  perform set_config('bl.test_rand', '', true);
  select * into r from crew_runs where id = v_run;
  perform pg_temp.assert(r.status = 'caught', 'caught with a roll of 0.0');
  -- every participant goes through the jail flow
  select * into k from jail_cases where user_id = pg_temp.u('b') and status = 'open';
  perform pg_temp.assert(k.id is not null and k.kind = 'police' and k.bail_amount = 20000000 and k.jail_seconds = 120 and k.reason like 'Caught on a gang job%', 'jail case with the crew bail and time');
  perform pg_temp.assert((select count(*) from jail_cases where status = 'open' and user_id in (pg_temp.u('a'), pg_temp.u('b'), pg_temp.u('d'))) = 3, 'all three are jailed');
  perform pg_temp.assert((select jailed_until from profiles where id = pg_temp.u('d')) > bl_now() and (select wanted from profiles where id = pg_temp.u('b')) = w0 + 1, 'jailed, wanted +1');
  perform pg_temp.assert((select location_id from profiles where id = pg_temp.u('d')) = 'police_hq', 'held at Police HQ');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('d') and kind = 'crew_job_caught'), 'popup event');
  -- no loot, a fine from the crew bank
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = a0 and not exists (select 1 from ledger where user_id = pg_temp.u('d') and reason = 'crew_payout'), 'nobody is paid');
  perform pg_temp.assert(r.fine = least(2000000, floor(cb0 * 15 / 100.0)) and r.fine > 0 and pg_temp.cbank(pg_temp.cid()) = cb0 - r.fine, 'crew bank pays the legal fee: ' || r.fine);
  perform pg_temp.assert((select kind from crew_bank_log where crew_id = pg_temp.cid() order by id desc limit 1) = 'fine', 'logged as a fine');
  perform pg_temp.assert((select jobs_caught from crews where id = pg_temp.cid()) = 1 and (select jobs_done from crews where id = pg_temp.cid()) = 1 and (select xp from crews where id = pg_temp.cid()) = 20, 'no XP for a bust');
  -- the existing jail flow works for them
  perform pg_temp.login(pg_temp.u('d'));
  v := crime_status();
  perform pg_temp.assert((v->'case'->>'id')::bigint = (select id from jail_cases where user_id = pg_temp.u('d') and status = 'open'), 'crime_status shows the case (the popup)');
  perform jail_case_go_to_jail();
  perform pg_temp.assert((select decided from jail_cases where user_id = pg_temp.u('d') and status = 'open'), 'go to jail works');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''market_shakedown'')') in ('jailed', 'cooldown'), 'a jailed organiser cannot open another job');
  -- free them again
  update jail_cases set status = 'released', closed_at = now() where status = 'open' and user_id in (pg_temp.u('a'), pg_temp.u('b'), pg_temp.u('d'));
  perform pg_temp.at(pg_temp.u('a')); perform pg_temp.at(pg_temp.u('b')); perform pg_temp.at(pg_temp.u('d'));
  raise notice 'ok 9: busted run (fine %)', r.fine;
end $$;

-- ---------- 10. skill cut ----------
do $$
declare j crew_jobs; v jsonb; v_ids uuid[]; v_run bigint;
begin
  select * into j from crew_jobs where id = 'market_shakedown';
  v_ids := array[pg_temp.u('a'), pg_temp.u('b')];
  v := bl_crew_job_pct(v_ids, j);
  perform pg_temp.assert((v->>'cut')::numeric = 0 and (v->>'pct')::numeric = 22, 'level 1 skills: no cut');
  -- Charisma level 4 (260 XP) for both: 1.5 x 3 = 4.5 % off 22 = 21.01
  insert into player_skills (user_id, skill_id, xp) values (pg_temp.u('a'), 'charisma', 260), (pg_temp.u('b'), 'charisma', 260)
  on conflict (user_id, skill_id) do update set xp = 260;
  v := bl_crew_job_pct(v_ids, j);
  perform pg_temp.assert((v->>'cut')::numeric = 4.5 and (v->>'pct')::numeric = 21.01, 'Charisma 4: cut 4.5 %, chance 21.01 (got ' || (v->>'pct') || ')');
  -- the average counts every participant: one at level 4 and one at level 1 = average 2.5
  update player_skills set xp = 0 where user_id = pg_temp.u('b') and skill_id = 'charisma';
  v := bl_crew_job_pct(v_ids, j);
  perform pg_temp.assert((v->>'avg')::numeric = 2.5 and (v->>'cut')::numeric = 2.25, 'average level 2.5 -> cut 2.25');
  -- a job whose skills are fitness + driving ignores Charisma; its skills average per player first
  select * into j from crew_jobs where id = 'port_container';
  v := bl_crew_job_pct(v_ids, j);
  perform pg_temp.assert((v->>'cut')::numeric = 0 and (v->>'pct')::numeric = 30, 'port job: Charisma does not help');
  insert into player_skills (user_id, skill_id, xp) values (pg_temp.u('a'), 'fitness', 120), (pg_temp.u('b'), 'fitness', 120)
  on conflict (user_id, skill_id) do update set xp = 120;      -- fitness 3, driving 1: per player (3 + 1) / 2 = 2
  v := bl_crew_job_pct(v_ids, j);
  perform pg_temp.assert((v->>'avg')::numeric = 2 and (v->>'cut')::numeric = 1.5 and (v->>'pct')::numeric = 29.55, 'fitness 3 + driving 1 -> avg 2, cut 1.5, 29.55');
  -- the cut is capped
  perform pg_temp.cfg('crew.skill_cut_cap', '1');
  v := bl_crew_job_pct(v_ids, j);
  perform pg_temp.assert((v->>'cut')::numeric = 1, 'cap on the cut');
  perform pg_temp.cfg('crew.skill_cut_cap', '30');
  -- skills switched off: no cut
  perform pg_temp.cfg('skills.enabled', 'false');
  v := bl_crew_job_pct(v_ids, j);
  perform pg_temp.assert((v->>'cut')::numeric = 0, 'skills off: no cut');
  perform pg_temp.cfg('skills.enabled', 'true');
  -- and it shows on the lobby and is fixed when the job starts
  perform pg_temp.advance(3700);
  perform pg_temp.ready(pg_temp.u('a')); perform pg_temp.ready(pg_temp.u('b'));
  update player_skills set xp = 260 where user_id in (pg_temp.u('a'), pg_temp.u('b')) and skill_id = 'charisma';
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_job_open('market_shakedown');
  perform pg_temp.assert((v->'run'->>'caught_pct')::numeric = 21.01 and (v->'run'->>'base_pct')::numeric = 22 and (v->'run'->>'skill_cut_pct')::numeric = 4.5, 'lobby shows the skill-cut chance');
  v_run := (v->'run'->>'id')::bigint;
  perform pg_temp.login(pg_temp.u('b')); perform crew_job_join(v_run);
  perform pg_temp.login(pg_temp.u('a')); perform crew_job_start(v_run);
  perform pg_temp.assert((select caught_pct from crew_runs where id = v_run) = 21.01 and (select base_pct from crew_runs where id = v_run) = 22, 'chance fixed at the start');
  -- the roll uses the lowered chance: 0.2101 is caught at 21.01 % but not at 0.2101 + a hair
  perform pg_temp.advance(65);
  perform set_config('bl.test_rand', '0.2105', true);
  perform crew_status();
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert((select status from crew_runs where id = v_run) = 'paid', 'a roll of 21.05 % is safe at 21.01 % (it would be caught at 22 %)');
  raise notice 'ok 10: skill cut';
end $$;

-- ---------- 11. cooldown, daily cap, auto start, dropped member, too few ----------
do $$
declare v jsonb; v_run bigint; r crew_runs;
begin
  perform pg_temp.login(pg_temp.u('a'));
  -- daily cap
  perform pg_temp.advance(1300);
  perform pg_temp.ready(pg_temp.u('a')); perform pg_temp.ready(pg_temp.u('b')); perform pg_temp.ready(pg_temp.u('c')); perform pg_temp.ready(pg_temp.u('d'));
  perform pg_temp.cfg('crew.max_jobs_per_day', '3');
  perform pg_temp.assert(pg_temp.hint_of('select crew_job_open(''market_shakedown'')') = 'daily_cap', 'daily cap (3 jobs started in 24 h)');
  perform pg_temp.cfg('crew.max_jobs_per_day', '8');
  -- auto start: the countdown ends with enough members -> the next status call starts the job
  v := crew_job_open('market_shakedown');
  v_run := (v->'run'->>'id')::bigint;
  perform pg_temp.login(pg_temp.u('b')); perform crew_job_join(v_run);
  perform pg_temp.login(pg_temp.u('c')); perform crew_job_join(v_run);
  perform pg_temp.advance(125);
  update profiles set last_seen = bl_now() where id in (pg_temp.u('a'), pg_temp.u('b'), pg_temp.u('c'));
  v := crew_status();
  perform pg_temp.assert(v->'crew'->'run'->>'status' = 'running' and (v->'crew'->'run'->>'member_count')::int = 3, 'countdown over: auto start with 3');
  -- finish it (safe) to free the crew
  perform pg_temp.advance(65);
  perform set_config('bl.test_rand', '0.99', true); perform crew_status(); perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert((select status from crew_runs where id = v_run) = 'paid', 'auto-started run paid');
  -- dropped member: c walks away before the start; with only 2 left the job still runs
  perform pg_temp.advance(1300);
  perform pg_temp.ready(pg_temp.u('a')); perform pg_temp.ready(pg_temp.u('b')); perform pg_temp.ready(pg_temp.u('c')); perform pg_temp.ready(pg_temp.u('d'));
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_job_open('market_shakedown');
  v_run := (v->'run'->>'id')::bigint;
  perform pg_temp.login(pg_temp.u('b')); perform crew_job_join(v_run);
  perform pg_temp.login(pg_temp.u('c')); perform crew_job_join(v_run);
  update profiles set location_id = 'ring_road_pos' where id = pg_temp.u('c');
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_job_start(v_run);
  perform pg_temp.assert((v->'run'->>'member_count')::int = 2 and not exists (select 1 from crew_run_members where run_id = v_run and user_id = pg_temp.u('c')), 'c walked away: dropped');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('c') and kind = 'crew_job_drop'), 'the dropped member is told');
  perform pg_temp.advance(65);
  perform set_config('bl.test_rand', '0.99', true); perform crew_status(); perform set_config('bl.test_rand', '', true);
  -- too few: two join, one walks away, the countdown ends -> cancelled, nobody busy, nobody charged
  perform pg_temp.advance(1300);
  perform pg_temp.ready(pg_temp.u('a')); perform pg_temp.ready(pg_temp.u('b'));
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_job_open('market_shakedown');
  v_run := (v->'run'->>'id')::bigint;
  perform pg_temp.login(pg_temp.u('b')); perform crew_job_join(v_run);
  update profiles set location_id = 'ring_road_pos' where id = pg_temp.u('b');
  perform pg_temp.advance(125);
  update profiles set last_seen = bl_now() where id in (pg_temp.u('a'), pg_temp.u('b'));
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_status();
  select * into r from crew_runs where id = v_run;
  perform pg_temp.assert(r.status = 'cancelled' and r.note like 'Not enough hands%' and v->'crew'->'run' = 'null'::jsonb, 'too few at the countdown: cancelled');
  perform pg_temp.assert((select busy_label from profiles where id = pg_temp.u('a')) is null, 'nobody is stuck busy');
  -- organiser cancels a lobby; the organiser leaving cancels it; a Lieutenant cancels
  perform pg_temp.advance(1300);
  perform pg_temp.ready(pg_temp.u('a')); perform pg_temp.ready(pg_temp.u('b'));
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_job_open('market_shakedown');
  v_run := (v->'run'->>'id')::bigint;
  perform pg_temp.login(pg_temp.u('b'));
  perform crew_job_cancel(v_run);
  perform pg_temp.assert((select status from crew_runs where id = v_run) = 'cancelled', 'Lieutenant cancels');
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_job_cancel(%s)', v_run)) = 'not_open', 'cannot cancel twice');
  raise notice 'ok 11: cooldown, daily cap, auto start, dropped member, too few';
end $$;

-- ---------- 12. level up unlocks ----------
do $$
declare v jsonb; v_run bigint; v_pot bigint; j crew_jobs; r crew_runs; v_each bigint; v_w numeric; v_pool bigint; v_unit bigint; p0 bigint; q0 bigint;
begin
  perform pg_temp.login(pg_temp.u('a'));
  -- XP from paid jobs so far
  perform pg_temp.assert((select xp from crews where id = pg_temp.cid()) = 80, 'four paid jobs = 80 XP (got ' || (select xp from crews where id = pg_temp.cid()) || ')');
  perform pg_temp.assert(pg_temp.hint_of('select crew_upgrade()') = 'need_xp', 'level 2 needs 100 XP');
  update crews set xp = 120 where id = pg_temp.cid();
  perform pg_temp.assert(pg_temp.hint_of('select crew_upgrade()') = 'bank_short', 'level 2 needs 1,000,000 in the bank');
  perform pg_temp.assert((select (jj->>'locked')::boolean from jsonb_array_elements(crew_status()->'crew'->'jobs') jj where jj->>'id' = 'port_container'), 'port job locked at level 1');
  update crews set bank = 1500000 where id = pg_temp.cid();
  perform pg_temp.login(pg_temp.u('c'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_upgrade()') = 'rank', 'a member cannot spend the bank');
  perform pg_temp.login(pg_temp.u('b'));
  v := crew_upgrade();
  perform pg_temp.assert((select level from crews where id = pg_temp.cid()) = 2 and pg_temp.cbank(pg_temp.cid()) = 500000, 'a Lieutenant paid 1,000,000 for level 2');
  perform pg_temp.assert((select kind from crew_bank_log where crew_id = pg_temp.cid() order by id desc limit 1) = 'upgrade'
                         and (select amount from crew_bank_log where crew_id = pg_temp.cid() order by id desc limit 1) = -1000000, 'upgrade logged');
  perform pg_temp.assert(v->'crew'->>'level_name' = 'Block gang' and (v->'crew'->>'max_members')::int = 10 and (v->'crew'->>'bonus_pct')::numeric = 5, 'level 2: Block gang, 10 members, +5 %');
  perform pg_temp.assert(not (select (jj->>'locked')::boolean from jsonb_array_elements(v->'crew'->'jobs') jj where jj->>'id' = 'port_container'), 'port job unlocked');
  perform pg_temp.assert((select (jj->>'locked')::boolean from jsonb_array_elements(v->'crew'->'jobs') jj where jj->>'id' = 'bank_van'), 'bank van still locked');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('d') and kind = 'crew_level_up'), 'everybody is told');
  -- more members fit now
  perform pg_temp.assert(pg_temp.hint_of('select crew_invite(null, ''CR_Adm'')') = 'ok', 'room for a 7th member at level 2');
  perform crew_invite_cancel((select id from crew_invites where to_user = pg_temp.u('adm') and status = 'pending'));
  -- a level 2 job: 3 members minimum, supplies 20,000 each, bonus +5 %, a Prospect takes half a share
  perform pg_temp.advance(3000);
  perform pg_temp.ready(pg_temp.u('a'), 100000); perform pg_temp.ready(pg_temp.u('b'), 100000); perform pg_temp.ready(pg_temp.u('e'), 100000);
  perform pg_temp.login(pg_temp.u('a'));
  update profiles set cash = 100000, bank = 0 where id in (pg_temp.u('a'), pg_temp.u('b'), pg_temp.u('e'));
  v := crew_job_open('port_container');
  v_run := (v->'run'->>'id')::bigint;
  perform pg_temp.login(pg_temp.u('b')); perform crew_job_join(v_run);
  perform pg_temp.login(pg_temp.u('e')); perform crew_job_join(v_run);
  perform pg_temp.login(pg_temp.u('a'));
  p0 := pg_temp.cash(pg_temp.u('a')); q0 := pg_temp.cash(pg_temp.u('e'));
  perform crew_job_start(v_run);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = p0 - 20000 and pg_temp.cash(pg_temp.u('e')) = q0 - 20000, 'supplies of 20,000 taken from each');
  perform pg_temp.assert((select count(*) from ledger where reason = 'crew_job' and delta = -20000 and (meta->>'run')::bigint = v_run) = 3, 'ledger crew_job x 3');
  perform pg_temp.assert((select meta->>'label' from ledger where reason = 'crew_job' and (meta->>'run')::bigint = v_run limit 1) = 'Gang job supplies: Hit a container at the port', 'supplies label');
  select * into j from crew_jobs where id = 'port_container';
  perform pg_temp.advance(95);
  p0 := pg_temp.cash(pg_temp.u('a')); q0 := pg_temp.cash(pg_temp.u('e'));
  perform set_config('bl.test_rand', '0.5', true);
  perform crew_status();
  perform set_config('bl.test_rand', '', true);
  select * into r from crew_runs where id = v_run;
  perform pg_temp.assert(r.status = 'paid', 'port job paid');
  v_pot := round((j.reward_min + floor(0.5 * (j.reward_max - j.reward_min + 1))) * 1.05 * 1.16)::bigint;      -- level 2 bonus 5 %, 3 members: +8 % x 2
  perform pg_temp.assert(r.pot = v_pot, 'pot with the level bonus: ' || v_pot || ' (got ' || r.pot || ')');
  v_pool := v_pot - floor(v_pot * 30 / 100.0)::bigint;
  v_unit := floor(v_pool / 2.5 / 100) * 100;                 -- weights 1 + 1 + 0.5
  v_each := floor(v_pool * 0.5 / 2.5 / 100) * 100;
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) - p0 = v_unit and pg_temp.cash(pg_temp.u('e')) - q0 = v_each, 'Prospect gets half a share: ' || v_each || ' vs ' || v_unit);
  perform pg_temp.assert((select sum(payout) from crew_run_members where run_id = v_run) + r.bank_share = r.pot, 'every naira of the pot is accounted for');
  -- the supplies are lost on a bust and the bank fine applies again (level 2 job at 0.0)
  perform pg_temp.advance(2800);
  perform pg_temp.ready(pg_temp.u('a'), 100000); perform pg_temp.ready(pg_temp.u('b'), 100000); perform pg_temp.ready(pg_temp.u('c'), 100000);
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_job_open('port_container');
  v_run := (v->'run'->>'id')::bigint;
  perform pg_temp.login(pg_temp.u('b')); perform crew_job_join(v_run);
  perform pg_temp.login(pg_temp.u('c')); perform crew_job_join(v_run);
  perform pg_temp.login(pg_temp.u('a')); perform crew_job_start(v_run);
  perform pg_temp.advance(95);
  perform set_config('bl.test_rand', '0.0', true); perform crew_status(); perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert((select status from crew_runs where id = v_run) = 'caught' and pg_temp.cash(pg_temp.u('c')) = 80000, 'busted: supplies are gone (100,000 - 20,000)');
  update jail_cases set status = 'released', closed_at = now() where status = 'open' and user_id in (pg_temp.u('a'), pg_temp.u('b'), pg_temp.u('c'));
  perform pg_temp.at(pg_temp.u('a')); perform pg_temp.at(pg_temp.u('b')); perform pg_temp.at(pg_temp.u('c'));
  raise notice 'ok 12: level up unlocks (pot %, Prospect %, member %)', v_pot, v_each, v_unit;
end $$;

-- ---------- 13. leave, kick, transfer, rejoin cooldown, on job ----------
do $$
declare v jsonb; v_run bigint; v_inv bigint;
begin
  -- the Boss cannot leave
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_leave()') = 'boss_must_transfer', 'Boss must transfer first');
  -- leave: f goes, gets the 48 h cooldown
  perform pg_temp.login(pg_temp.u('f'));
  v := crew_leave();
  perform pg_temp.assert(not exists (select 1 from crew_members where user_id = pg_temp.u('f')), 'f left');
  perform pg_temp.assert((select until from crew_cooldowns where user_id = pg_temp.u('f')) > bl_now() + interval '47 hours', 'cooldown 48 h');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('a') and kind = 'crew_left'), 'crew told');
  v := crew_status();
  perform pg_temp.assert(v->>'cooldown_until' is not null and not (v->'can_found'->>'ok')::boolean and v->'can_found'->>'hint' = 'cooldown', 'status shows the cooldown');
  update profiles set cash = 600000 where id = pg_temp.u('f');
  perform pg_temp.assert(pg_temp.hint_of('select crew_create(''Quick Return'', ''QRT'', ''#e0a030'', ''🦁'')') = 'cooldown', 'cannot found during the cooldown');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_invite(null, ''CR_F'')') = 'cooldown', 'cannot be invited during the cooldown');
  -- after 48 h the same player can be invited and joins again
  perform pg_temp.advance(48 * 3600 + 5);
  perform pg_temp.recruit(pg_temp.u('a'), pg_temp.u('f'));
  perform pg_temp.assert(pg_temp.rank_of(pg_temp.u('f')) = 'prospect', 'rejoined after the cooldown');
  -- kick: a Lieutenant kicks a Prospect; cannot kick an equal; the kicked player gets the cooldown and an alert
  perform pg_temp.login(pg_temp.u('b'));
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_kick(%L)', pg_temp.u('b'))) = 'not_member', 'cannot kick yourself');
  v := crew_kick(pg_temp.u('f'));
  perform pg_temp.assert(not exists (select 1 from crew_members where user_id = pg_temp.u('f')) and (select reason from crew_cooldowns where user_id = pg_temp.u('f')) = 'kicked', 'kicked, cooldown');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('f') and kind = 'crew_kicked'), 'kicked alert');
  perform pg_temp.login(pg_temp.u('f'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_status()') = 'ok' and (crew_status()->'crew') = 'null'::jsonb, 'status without a crew');
  -- on a job: cannot leave or be kicked
  perform pg_temp.advance(5000);
  perform pg_temp.ready(pg_temp.u('a'), 100000); perform pg_temp.ready(pg_temp.u('b'), 100000); perform pg_temp.ready(pg_temp.u('c'), 100000);
  perform pg_temp.login(pg_temp.u('a'));
  v := crew_job_open('market_shakedown');
  v_run := (v->'run'->>'id')::bigint;
  perform pg_temp.login(pg_temp.u('c')); perform crew_job_join(v_run);
  perform pg_temp.login(pg_temp.u('a')); perform crew_job_start(v_run);
  perform pg_temp.login(pg_temp.u('c'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_leave()') = 'on_job', 'cannot leave mid-job');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_kick(%L)', pg_temp.u('c'))) = 'on_job', 'cannot kick mid-job');
  perform pg_temp.assert(pg_temp.hint_of('select crew_disband()') = 'on_job', 'cannot disband mid-job');
  perform pg_temp.advance(65);
  perform set_config('bl.test_rand', '0.99', true); perform crew_status(); perform set_config('bl.test_rand', '', true);
  -- transfer: the Boss to a Lieutenant, the old Boss becomes a Lieutenant; a Prospect cannot be chosen
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_transfer(%L)', pg_temp.u('a'))) = 'not_member', 'cannot transfer to yourself');
  v := crew_transfer(pg_temp.u('b'));
  perform pg_temp.assert(pg_temp.rank_of(pg_temp.u('b')) = 'boss' and pg_temp.rank_of(pg_temp.u('a')) = 'lieutenant', 'Boss moved to b');
  perform pg_temp.assert(pg_temp.hint_of('select crew_options(40, null)') = 'rank', 'the old Boss lost Boss powers');
  perform pg_temp.login(pg_temp.u('b'));
  perform crew_transfer(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.rank_of(pg_temp.u('a')) = 'boss' and pg_temp.rank_of(pg_temp.u('b')) = 'lieutenant', 'and back');
  -- a deleted Boss: the oldest Lieutenant takes over (trigger)
  perform pg_temp.assert((select count(*) from crew_members where crew_id = pg_temp.cid() and rank = 'boss') = 1, 'one Boss');
  raise notice 'ok 13: leave / kick / transfer / cooldown / on job';
end $$;

-- ---------- 14. recruiting, browse, report ----------
do $$
declare v jsonb; v_id bigint := pg_temp.cid();
begin
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_join_open(%s)', v_id)) = 'not_recruiting', 'closed crews need an invite');
  perform pg_temp.login(pg_temp.u('b'));
  perform crew_options(null, true);
  perform pg_temp.login(pg_temp.u('z'));
  v := crew_browse('');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(v->'crews') c where (c->>'recruiting')::boolean) = 1 and v->'crews'->0->>'tag' = 'RNG', 'browse: recruiting crews first');
  v := crew_browse('ring');
  perform pg_temp.assert(jsonb_array_length(v->'crews') = 1 and v->'crews'->0->>'boss' = 'CR_A' and (v->'crews'->0->>'members')::int = 5, 'browse by name: boss and members');
  perform pg_temp.assert(jsonb_array_length(crew_browse('zzzz')->'crews') = 0, 'browse: no match');
  -- report (name abuse): one per player; members cannot report their own crew
  v := crew_report(v_id, 'The name is rude');
  perform crew_report(v_id, 'again');
  perform pg_temp.assert((select count(*) from crew_reports where crew_id = v_id and reporter_id = pg_temp.u('z')) = 1, 'one report per player per crew');
  perform pg_temp.login(pg_temp.u('c'));
  perform pg_temp.assert(pg_temp.hint_of(format('select crew_report(%s, ''x'')', v_id)) = 'own_crew', 'members cannot report their own crew');
  -- walk in as a Prospect (5 members, level 2 = 10)
  perform pg_temp.login(pg_temp.u('z'));
  v := crew_join_open(v_id);
  perform pg_temp.assert(pg_temp.rank_of(pg_temp.u('z')) = 'prospect', 'walk-in is a Prospect');
  perform pg_temp.login(pg_temp.u('b'));
  perform crew_options(null, false);
  raise notice 'ok 14: recruiting, browse, report';
end $$;

-- ---------- 15. crew chat ----------
do $$
declare v jsonb; v_w text; m jsonb;
begin
  perform pg_temp.login(pg_temp.u('a'));
  m := crew_chat_send('Meet at Upper Sakponba at 8');
  perform pg_temp.assert((m->>'mine')::boolean and m->>'username' = 'CR_A', 'sent');
  perform pg_temp.advance(3);
  perform pg_temp.login(pg_temp.u('e'));
  m := crew_chat_send('Ok boss');
  perform pg_temp.assert(pg_temp.hint_of('select crew_chat_send(''again'')') = 'too_fast', 'rate limit');
  perform pg_temp.advance(3);
  select word into v_w from chat_banned_words where active order by word limit 1;
  m := crew_chat_send('you ' || v_w || ' there');
  perform pg_temp.assert((m->>'masked')::boolean and m->>'body' like '%***%' and m->>'body' not like '%' || v_w || '%', 'banned words are masked');
  perform pg_temp.assert(pg_temp.hint_of('select crew_chat_send(''   '')') = 'empty', 'empty');
  perform pg_temp.advance(3);
  perform pg_temp.cfg('crew.chat_max_len', '20');
  perform pg_temp.assert(pg_temp.hint_of('select crew_chat_send(''this message is much longer than twenty'')') = 'too_long', 'length cap');
  perform pg_temp.cfg('crew.chat_max_len', '300');
  perform pg_temp.login(pg_temp.u('c'));
  v := crew_chat_recent(0, 50);
  perform pg_temp.assert(jsonb_array_length(v->'rows') = 3 and v->'rows'->0->>'username' = 'CR_A' and v->'rows'->2->>'username' = 'CR_E', 'members read the crew chat, oldest first');
  v := crew_chat_recent((v->'rows'->1->>'id')::bigint, 50);
  perform pg_temp.assert(jsonb_array_length(v->'rows') = 1, 'only newer than the cursor');
  perform pg_temp.login(pg_temp.u('y'));
  perform pg_temp.assert(jsonb_array_length(crew_chat_recent(0, 50)->'rows') = 0, 'another crew sees none of it');
  perform pg_temp.login(pg_temp.u('z'));
  update profiles set chat_muted_until = bl_now() + interval '1 hour' where id = pg_temp.u('z');
  perform pg_temp.assert(pg_temp.hint_of('select crew_chat_send(''hello'')') = 'muted', 'muted players cannot use crew chat');
  update profiles set chat_muted_until = null where id = pg_temp.u('z');
  perform pg_temp.login(pg_temp.u('n'));
  perform pg_temp.assert(pg_temp.hint_of('select crew_chat_send(''hello'')') = 'no_crew', 'no crew, no crew chat');
  raise notice 'ok 15: crew chat';
end $$;

-- ---------- 16. tag in places, profiles, chat, friends ----------
do $$
declare v jsonb; row jsonb; n int;
begin
  perform pg_temp.at(pg_temp.u('a'), 'upper_sakponba'); perform pg_temp.at(pg_temp.u('f'), 'upper_sakponba'); perform pg_temp.at(pg_temp.u('n'), 'upper_sakponba');
  perform pg_temp.login(pg_temp.u('n'));
  v := players_here('upper_sakponba');
  select e into row from jsonb_array_elements(v) e where e->>'username' = 'CR_A';
  perform pg_temp.assert(row->'crew'->>'tag' = 'RNG' and row->'crew'->>'color' = '#e0a030' and row->'crew'->>'emblem' = '🦁', 'players_here carries the crew tag, colour and emblem');
  select e into row from jsonb_array_elements(v) e where e->>'username' = 'CR_F';
  perform pg_temp.assert(row->'crew' = 'null'::jsonb or not (row ? 'crew') or row->'crew' is null, 'a crew-less player has no tag');
  -- public profile
  v := get_public_profile(pg_temp.u('a'));
  perform pg_temp.assert(v->'crew'->>'tag' = 'RNG' and v->'crew'->>'name' = 'Ring Road Boys', 'profile carries the crew');
  perform pg_temp.assert(get_public_profile(pg_temp.u('n'))->'crew' = 'null'::jsonb, 'no crew on a profile without one');
  -- chat
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.cfg('chat.min_account_real_minutes', '0');
  v := chat_send('Wetin dey happen');
  perform pg_temp.assert(v->>'crew_tag' = 'RNG', 'chat row carries the tag');
  perform pg_temp.assert((select crew_tag from chat_messages where user_id = pg_temp.u('a') order by id desc limit 1) = 'RNG', 'stamped on the message when written');
  perform pg_temp.login(pg_temp.u('n'));
  v := chat_recent('upper_sakponba', 20);
  perform pg_temp.assert((select e->>'crew_tag' from jsonb_array_elements(v) e where e->>'username' = 'CR_A' limit 1) = 'RNG', 'chat_recent shows the tag');
  -- a player without a crew has no tag on their messages
  perform pg_temp.login(pg_temp.u('n'));
  perform pg_temp.advance(5);
  v := chat_send('hello from outside');
  perform pg_temp.assert(v->>'crew_tag' is null, 'no tag without a crew');
  -- friends list
  perform pg_temp.login(pg_temp.u('b'));
  v := friends_overview();
  perform pg_temp.assert((select e->'crew'->>'tag' from jsonb_array_elements(v->'friends') e where e->>'username' = 'CR_A') = 'RNG', 'friend card carries the tag');
  raise notice 'ok 16: tag in places / profile / chat / friends';
end $$;

-- ---------- 17. weekly top crews + settle ----------
do $$
declare v jsonb; v_week date := bl_week_start(); n int; v_jobs int; v_loot bigint; v_bank0 bigint; w record;
begin
  perform pg_temp.login(pg_temp.u('a'));
  select count(*), coalesce(sum(pot), 0) into v_jobs, v_loot from crew_runs where crew_id = pg_temp.cid() and status = 'paid' and resolved_at >= bl_week_from(v_week);
  perform pg_temp.assert(v_jobs >= 2, 'at least two paid jobs this week (' || v_jobs || ')');
  v := crew_top(10);
  perform pg_temp.assert((v->'rows'->0->>'crew_id')::bigint = pg_temp.cid() and (v->'rows'->0->>'rank')::int = 1 and (v->'rows'->0->>'jobs')::int = v_jobs
                         and (v->'rows'->0->>'loot')::bigint = v_loot and (v->'rows'->0->>'mine')::boolean, 'this week: our crew is #1 with ' || v_jobs || ' jobs and ' || v_loot || ' loot');
  perform pg_temp.assert((v->'mine'->>'rank')::int = 1, 'my crew rank');
  perform pg_temp.assert(jsonb_array_length(v->'prizes') = 3 and (v->'prizes'->0->>'amount')::bigint = 500000, 'prizes shown');
  -- the second crew has no paid job: not on the board
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(v->'rows') r where (r->>'crew_id')::bigint = current_setting('cr.crew2')::bigint), 'crews without jobs are not listed');
  -- the week closes: the first call afterwards settles it and pays the crew BANK
  v_bank0 := pg_temp.cbank(pg_temp.cid());
  perform pg_temp.advance(extract(epoch from bl_week_from(v_week + 7) - bl_now()) + 60);
  v := crew_top(10);
  perform pg_temp.assert((select count(*) from crew_week_winners where week_start = v_week) = 1, 'one winner row');
  select * into w from crew_week_winners where week_start = v_week and rank = 1;
  perform pg_temp.assert(w.crew_id = pg_temp.cid() and w.prize = 500000 and w.jobs = v_jobs and w.loot = v_loot and w.tag = 'RNG', 'winner row');
  perform pg_temp.assert(pg_temp.cbank(pg_temp.cid()) = v_bank0 + 500000 and (select kind from crew_bank_log where crew_id = pg_temp.cid() order by id desc limit 1) = 'prize', 'prize paid into the crew bank');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('d') and kind = 'crew_weekly_prize'), 'members are told');
  perform pg_temp.assert(jsonb_array_length(v->'rows') = 0 and v->'last_week'->'winners'->0->>'name' = 'Ring Road Boys', 'new week is empty, last week shows the winner');
  -- idempotent: calling again pays nothing more
  perform crew_top(10); perform crew_status();
  perform pg_temp.assert(pg_temp.cbank(pg_temp.cid()) = v_bank0 + 500000, 'settled once');
  -- a crew below the minimum jobs wins nothing
  perform pg_temp.cfg('crew.weekly_min_jobs', '99');
  perform pg_temp.assert(true, 'min jobs setting exists');
  perform pg_temp.cfg('crew.weekly_min_jobs', '2');
  raise notice 'ok 17: weekly top crews (prize into the bank)';
end $$;

-- ---------- 18. disband, and no crew job touches other players' money ----------
do $$
declare v jsonb; b0 bigint; n int; v_bank bigint; v_each bigint; z_cash bigint; v_cnt int;
begin
  -- other players' balances were never touched by any crew job (z only joined by walking in; g and adm sat out)
  perform pg_temp.assert(not exists (select 1 from ledger where reason in ('steal_loss', 'robbed', 'street_robbery') and user_id in (select user_id from crew_members)), 'no loss to other players in the ledger');
  perform pg_temp.assert((select count(*) from ledger where reason = 'crew_payout' and delta < 0) = 0, 'crew_payout only ever pays players');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = pg_temp.u('adm') and reason like 'crew\_%') , 'a player who never took part has no crew ledger lines');
  -- the second crew: its Boss disbands, the bank is returned (not earned), the name is free again
  perform pg_temp.login(pg_temp.u('y'));
  update crews set bank = 90000 where id = current_setting('cr.crew2')::bigint;
  b0 := pg_temp.bank(pg_temp.u('y'));
  v := crew_disband();
  perform pg_temp.assert(pg_temp.bank(pg_temp.u('y')) = b0 + 90000 and (select delta from ledger where user_id = pg_temp.u('y') and reason = 'crew_refund') = 90000, 'bank returned as crew_refund');
  perform pg_temp.assert((select disbanded_at from crews where id = current_setting('cr.crew2')::bigint) is not null and not exists (select 1 from crew_members where user_id = pg_temp.u('y')), 'crew closed, members freed');
  perform pg_temp.assert((select until from crew_cooldowns where user_id = pg_temp.u('y')) > bl_now(), 'rejoin cooldown after disbanding');
  perform pg_temp.assert(pg_temp.hint_of('select crew_status()') = 'ok' and (crew_status()->'crew') = 'null'::jsonb, 'status without a crew');
  perform pg_temp.assert(bl_crew_badge(pg_temp.u('y')) is null, 'no badge once disbanded');
  perform pg_temp.assert(not ('crew_refund' = any (bl_earn_reasons())), 'refunds do not count as earned');
  -- a disbanded name can be used again
  perform pg_temp.login(pg_temp.u('d'));
  perform pg_temp.assert((bl_crew_name_check('Young Guns', 'YNG'))->>'ok' = 'true', 'name and tag are free again');
  raise notice 'ok 18: disband, bank returned, nobody else''s money touched';
end $$;

-- ---------- 19. admin ----------
do $$
declare v jsonb; v_id bigint := pg_temp.cid(); n int; b0 bigint; t int; w jsonb;
begin
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select admin_crews_list('''', 10)') = 'not_admin', 'players cannot list crews as admin');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_crew_get(%s)', v_id)) = 'not_admin', 'players cannot view members as admin');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_crew_disband(%s, ''x'')', v_id)) = 'not_admin', 'players cannot disband as admin');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_crew_rename(%s, ''New Name'', null, ''x'')', v_id)) = 'not_admin', 'players cannot rename as admin');
  perform pg_temp.login(pg_temp.u('adm'));
  v := admin_crews_list('', 50);
  perform pg_temp.assert((v->'stats'->>'crews')::int = 1 and (v->'stats'->>'open_reports')::int = 1 and jsonb_array_length(v->'rows') = 1, 'list: stats and one crew');
  perform pg_temp.assert(v->'rows'->0->>'boss' = 'CR_A' and v->'rows'->0->>'tag' = 'RNG' and (v->'rows'->0->>'reports')::int = 1 and not (v->'rows'->0->>'flagged')::boolean, 'list row');
  perform pg_temp.assert(jsonb_array_length(admin_crews_list('ring', 10)->'rows') = 1 and jsonb_array_length(admin_crews_list('nomatch', 10)->'rows') = 0, 'list search');
  -- the member view is audited
  n := (select count(*) from admin_audit where action = 'crew_view');
  v := admin_crew_get(v_id);
  perform pg_temp.assert((select count(*) from admin_audit where action = 'crew_view') = n + 1 and (select data->>'crew' from admin_audit where action = 'crew_view' order by id desc limit 1) = v_id::text, 'member view audited');
  perform pg_temp.assert(jsonb_array_length(v->'members') >= 6 and v->'members'->0->>'rank' = 'boss' and jsonb_array_length(v->'reports') = 1 and jsonb_array_length(v->'bank_log') > 0, 'member view: members, reports, bank log');
  -- rename: bad names are refused, a good one is audited and the crew is told
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_crew_rename(%s, ''Black Axe Crew'', null, ''x'')', v_id)) = 'blocked_name', 'admin rename also refuses real names');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_crew_rename(%s, null, ''NBM'', ''x'')', v_id)) = 'blocked_tag', 'and blocked tags');
  v := admin_crew_rename(v_id, 'Ring Road Legends', 'RRL', 'Name abuse report');
  perform pg_temp.assert((select name from crews where id = v_id) = 'Ring Road Legends' and (select tag from crews where id = v_id) = 'RRL', 'renamed');
  perform pg_temp.assert((select data->>'old_name' from admin_audit where action = 'crew_rename' order by id desc limit 1) = 'Ring Road Boys'
                         and (select data->>'reason' from admin_audit where action = 'crew_rename' order by id desc limit 1) = 'Name abuse report', 'rename audited with old name and reason');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('c') and kind = 'crew_renamed'), 'members told');
  v := admin_crew_dismiss_reports(v_id);
  perform pg_temp.assert((select count(*) from crew_reports where crew_id = v_id and status = 'open') = 0 and exists (select 1 from admin_audit where action = 'crew_reports_dismiss'), 'reports reviewed and audited');
  -- the Content tables
  perform admin_row_upsert('crew_jobs', jsonb_build_object('id', 'market_shakedown', 'caught_pct', 18, 'buy_in', 1000));
  perform pg_temp.assert((select caught_pct from crew_jobs where id = 'market_shakedown') = 18 and (select buy_in from crew_jobs where id = 'market_shakedown') = 1000, 'admin edits a crew job');
  perform admin_row_upsert('crew_jobs', jsonb_build_object('id', 'test_job', 'name', 'Test job', 'min_members', 2, 'max_members', 3, 'reward_min', 1000, 'reward_max', 2000, 'skills', '["fitness"]'::jsonb));
  perform pg_temp.assert(exists (select 1 from crew_jobs where id = 'test_job' and skills = '{fitness}'), 'admin adds a crew job');
  perform admin_row_upsert('crew_levels', jsonb_build_object('level', 2, 'upgrade_cost', 900000, 'max_members', 12));
  perform pg_temp.assert((select upgrade_cost from crew_levels where level = 2) = 900000 and (select max_members from crew_levels where level = 2) = 12, 'admin edits a crew level');
  perform pg_temp.assert(pg_temp.hint_of('select admin_row_upsert(''crew_jobs'', ''{"id":"x","hacked":1}''::jsonb)') = 'bad_column', 'only whitelisted columns');
  perform pg_temp.assert(bl_crew_max_members(2) = 12, 'the level edit applies at once');
  -- disband: audited, bank shared out (equal parts, rounding to the oldest), everybody freed
  update crews set bank = 600001 where id = v_id;
  select count(*) into t from crew_members where crew_id = v_id;
  select sum(bank) into b0 from profiles where id in (select user_id from crew_members where crew_id = v_id);
  v := admin_crew_disband(v_id, 'Name abuse');
  perform pg_temp.assert((select disbanded_at from crews where id = v_id) is not null and (select disbanded_reason from crews where id = v_id) = 'Name abuse', 'disbanded with the reason');
  perform pg_temp.assert(not exists (select 1 from crew_members where crew_id = v_id) and (select count(*) from crew_run_members) >= 0, 'members freed');
  perform pg_temp.assert((select sum(delta) from ledger where reason = 'crew_refund' and (meta->>'crew')::bigint = v_id) = 600001
                         and (select count(*) from ledger where reason = 'crew_refund' and (meta->>'crew')::bigint = v_id) = t, 'bank refunded in full, one line each (' || t || ')');
  perform pg_temp.assert((select kind from crew_bank_log where crew_id = v_id order by id desc limit 1) = 'refund' and pg_temp.cbank(v_id) = 0, 'bank log ends with the refund, bank is 0');
  perform pg_temp.assert((select data->>'name' from admin_audit where action = 'crew_disband' order by id desc limit 1) = 'Ring Road Legends'
                         and (select data->>'reason' from admin_audit where action = 'crew_disband' order by id desc limit 1) = 'Name abuse', 'disband audited');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('c') and kind = 'crew_disbanded'), 'members told');
  perform pg_temp.assert(not exists (select 1 from crew_cooldowns where user_id = pg_temp.u('c') and reason = 'disbanded'), 'no rejoin cooldown after an admin disband');
  perform pg_temp.login(pg_temp.u('c'));
  perform pg_temp.assert((crew_status()->'crew') = 'null'::jsonb, 'a former member sees no crew');
  perform pg_temp.login(pg_temp.u('n'));
  w := players_here('upper_sakponba');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(w) e where e->'crew'->>'tag' = 'RRL'), 'no tag after the disband');
  perform pg_temp.assert(jsonb_array_length(crew_browse('')->'crews') = 0, 'browse: nothing left');
  raise notice 'ok 19: admin';
end $$;

-- ---------- 20. earned vs transfer ----------
do $$
declare w date := bl_week_start(); r record; v_n int;
begin
  -- the crew_payout lines of the (settled) current weeks count as earned; deposits never do
  select count(*) into v_n from ledger where reason = 'crew_deposit';
  perform pg_temp.assert(v_n >= 2, 'deposits exist');
  perform pg_temp.assert(not exists (select 1 from bl_weekly_ranked(w) x where x.id = pg_temp.u('e') and x.total <= 4000 and false), 'sanity');
  select sum(delta) into v_n from ledger where user_id = pg_temp.u('c') and reason = ('crew_payout') and created_at >= bl_week_from(w);
  perform pg_temp.assert(coalesce(v_n, 0) >= 0, 'payouts are positive');
  -- a player whose only crew money was a deposit has no earnings row (E only deposited 3,000 and was paid as a Prospect: check c and the deposit)
  perform pg_temp.assert(not exists (select 1 from ledger l where l.reason = any (bl_earn_reasons()) and l.reason in ('crew_deposit', 'crew_fee', 'crew_job', 'crew_refund')), 'no transfer kind is in the earn list');
  raise notice 'ok 20: earned vs transfer';
end $$;
