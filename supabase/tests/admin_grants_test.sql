-- Admin Grant toolbox (20261107000100 / 200 / 300). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/admin_grants_test.sql
-- Groups: 1 privileges · 2 non-admin refused everywhere · 3 career (set, promote, demote, xp, remove, validation, shift guard) ·
-- 4 needs and stuck states · 5 jail · 6 numbers, debts, Yahoo rank · 7 items and cars (usable, undo) · 8 furniture ·
-- 9 garage, wardrobe, pass · 10 business level (takings change) · 11 company · 12 home, property, land · 13 crew ·
-- 14 chief title, course · 15 state + catalog · 16 banned and deleted targets · 17 audit rows + alerts + nothing earned.
update public.locations set open_hour = null, close_hour = null where scene = 'market';

create or replace function pg_temp.ag_hint(p_sql text, p_hint text) returns text
language plpgsql as $$
declare v_h text; v_m text;
begin
  execute p_sql;
  raise exception 'TEST FAILED: [%] expected hint "%" but it succeeded', p_sql, p_hint;
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  get stacked diagnostics v_h = pg_exception_hint, v_m = message_text;
  if v_h is distinct from p_hint then
    raise exception 'TEST FAILED: [%] expected hint "%", got "%" (%)', p_sql, p_hint, v_h, sqlerrm;
  end if;
  return v_m;
end $$;

create or replace function pg_temp.ag_u(p_name text) returns uuid
language sql as $$ select current_setting('agtest.' || p_name)::uuid $$;

create or replace function pg_temp.ag_make(p_name text, p_gender text default 'female') returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@grants.bl');
begin
  perform set_config('agtest.' || lower(p_name), v::text, true);
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, p_gender, jsonb_build_object('gender', p_gender), '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, busy_until = null, travel_to = null, protected_until = null,
         created_at = now() - interval '30 days', cash = 5000, bank = 5000,
         energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0 where id = v;
  return v;
end $$;

create or replace function pg_temp.ag_as(p_name text) returns void
language sql as $$ select pg_temp.login(pg_temp.ag_u(p_name)) $$;

create or replace function pg_temp.ag_audit(p_action text) returns int
language sql as $$ select count(*)::int from admin_audit where target_user = pg_temp.ag_u('agplayer') and action = p_action $$;

create or replace function pg_temp.ag_alerts(p_kind text) returns int
language sql as $$ select count(*)::int from events where user_id = pg_temp.ag_u('agplayer') and kind = p_kind $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  update profiles set is_admin = false where is_admin;
  perform pg_temp.ag_make('AgBoss');
  perform pg_temp.ag_make('AgPlayer');
  perform pg_temp.ag_make('AgOther');
  perform pg_temp.ag_make('AgBanned');
  update profiles set is_admin = true where id = pg_temp.ag_u('agboss');
  update profiles set banned = true where id = pg_temp.ag_u('agbanned');
  perform set_config('agtest.ledger0', (select count(*) from ledger where user_id = pg_temp.ag_u('agplayer'))::text, true);
end $$;

-- 1. privileges -------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'admin_grant_career(uuid, text, int, int, boolean, text)', 'admin_career_remove(uuid, text)', 'admin_refill_needs(uuid, text[], text)',
    'admin_clear_states(uuid, text[], text)', 'admin_jail_set(uuid, int, text)', 'admin_set_numbers(uuid, int, int, jsonb, text)',
    'admin_clear_debts(uuid, boolean, boolean, text)', 'admin_set_yahoo_rank(uuid, text, text)', 'admin_give_item(uuid, text, int, text)',
    'admin_take_item(uuid, text, int, text)', 'admin_give_furniture(uuid, text, int, text)', 'admin_take_furniture(uuid, text, int, text)',
    'admin_give_garage(uuid, text, text)', 'admin_remove_garage(uuid, text)', 'admin_give_wardrobe(uuid, text, text, text)',
    'admin_take_wardrobe(uuid, text, text)', 'admin_give_hustle_pass(uuid, text, int, text)', 'admin_take_hustle_pass(uuid, text, text)',
    'admin_business_set(bigint, int, int, int, int, text)', 'admin_company_grant(uuid, text, text, text, text)',
    'admin_company_set(bigint, text, int, boolean, boolean, text)', 'admin_set_home(uuid, text, uuid, text)',
    'admin_give_property(uuid, text, text)', 'admin_take_property(uuid, uuid, text)', 'admin_give_land(uuid, text, int, text)',
    'admin_take_land(uuid, text, int, text)', 'admin_crew_set(uuid, bigint, text, text)', 'admin_crew_remove(uuid, text)',
    'admin_set_chief_title(uuid, int, text, text)', 'admin_remove_chief_title(uuid, text)', 'admin_complete_course(uuid, text, text)',
    'admin_reset_course(uuid, text, boolean, text)', 'admin_grant_state(uuid)', 'admin_grant_catalog()'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute'), 'anon cannot call ' || f);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute'), 'authenticated may call (guarded) ' || f);
  end loop;
  foreach f in array array['bl_ag_fail(text, text)', 'bl_ag_target(uuid, boolean)', 'bl_ag_reason(text, boolean)', 'bl_ag_log(uuid, uuid, text, jsonb)',
                           'bl_ag_alert(uuid, text, text, text, text, jsonb)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', 'public.' || f, 'execute'), 'helper revoked ' || f);
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute'), 'helper revoked from anon ' || f);
  end loop;
  raise notice 'grants 1 OK: privileges';
end $$;

-- 2. a non-admin is refused by every RPC --------------------------------------------------
do $$
declare s text; u text := quote_literal(pg_temp.ag_u('agplayer')::text) || '::uuid';
begin
  perform pg_temp.ag_as('agother');
  foreach s in array array[
    'admin_grant_career(' || u || ', ''tech'', 3, null, false, ''x y z'')', 'admin_career_remove(' || u || ', ''xyz'')',
    'admin_refill_needs(' || u || ', null, '''')', 'admin_clear_states(' || u || ', array[''busy''], '''')', 'admin_jail_set(' || u || ', 10, ''xyz'')',
    'admin_set_numbers(' || u || ', 5, null, null, ''xyz'')', 'admin_clear_debts(' || u || ', true, true, ''xyz'')', 'admin_set_yahoo_rank(' || u || ', ''g_boy'', ''xyz'')',
    'admin_give_item(' || u || ', ''roll_and_soda'', 1, '''')', 'admin_take_item(' || u || ', ''roll_and_soda'', 1, '''')',
    'admin_give_furniture(' || u || ', ''stool'', 1, '''')', 'admin_take_furniture(' || u || ', ''stool'', 1, '''')',
    'admin_give_garage(' || u || ', ''carport'', '''')', 'admin_remove_garage(' || u || ', '''')',
    'admin_give_wardrobe(' || u || ', ''bb_tee'', null, '''')', 'admin_take_wardrobe(' || u || ', ''bb_tee'', '''')',
    'admin_give_hustle_pass(' || u || ', ''stall'', 24, '''')', 'admin_take_hustle_pass(' || u || ', ''stall'', '''')',
    'admin_business_set(1, 2, null, null, null, ''xyz'')', 'admin_company_grant(' || u || ', ''x'', ''y'', null, ''xyz'')',
    'admin_company_set(1, null, 1, null, null, ''xyz'')', 'admin_set_home(' || u || ', ''uselu_self_contain'', null, ''xyz'')',
    'admin_give_property(' || u || ', ''x'', ''xyz'')', 'admin_take_property(' || u || ', gen_random_uuid(), ''xyz'')',
    'admin_give_land(' || u || ', ''land_gra'', 1, ''xyz'')', 'admin_take_land(' || u || ', ''land_gra'', 1, ''xyz'')',
    'admin_crew_set(' || u || ', 1, ''member'', '''')', 'admin_crew_remove(' || u || ', '''')',
    'admin_set_chief_title(' || u || ', 1, ''x'', ''xyz'')', 'admin_remove_chief_title(' || u || ', '''')',
    'admin_complete_course(' || u || ', ''driving_school'', '''')', 'admin_reset_course(' || u || ', ''driving_school'', false, '''')',
    'admin_grant_state(' || u || ')', 'admin_grant_catalog()'] loop
    perform pg_temp.ag_hint('select ' || s, 'not_admin');
  end loop;
  raise notice 'grants 2 OK: non-admin refused (% calls)', 35;
end $$;

-- 3. career --------------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); r jsonb; v_top int; j jsonb;
begin
  perform pg_temp.ag_as('agboss');
  select max(level) into v_top from career_levels where track_id = 'health';
  perform pg_temp.ag_hint(format('select admin_grant_career(%L, ''health'', 3, null, false, '''')', p), 'reason_required');
  perform pg_temp.ag_hint(format('select admin_grant_career(%L, ''nope'', 3, null, false, ''for the test'')', p), 'bad_track');
  perform pg_temp.ag_hint(format('select admin_grant_career(%L, ''health'', %s, null, false, ''for the test'')', p, v_top + 1), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_grant_career(%L, ''health'', 0, null, false, ''for the test'')', p), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_grant_career(%L, ''health'', 3, 999999, false, ''for the test'')', p), 'bad_value');
  perform pg_temp.assert((select job_id from profiles where id = p) is null, 'nothing changed by refused calls');
  r := admin_grant_career(p, 'health', 3, 25, false, 'Test promotion');
  perform pg_temp.assert((r->>'level')::int = 3, 'level 3 returned');
  perform pg_temp.assert((select job_id || job_level || job_xp from profiles where id = p) = 'health325', 'profile row has the track, level and xp');
  perform pg_temp.assert((select (career_best->>'health')::int from profiles where id = p) = 3, 'career_best raised');
  perform pg_temp.ag_as('agplayer');
  j := get_my_state()->'career'->'job';
  perform pg_temp.assert((j->>'level')::int = 3 and j->>'track' = 'health' and (j->>'xp')::int = 25, 'the game''s own state shows level 3, 25 xp');
  perform pg_temp.assert(j->>'title' = (select title from career_levels where track_id = 'health' and level = 3), 'title matches the level');
  perform pg_temp.assert(pg_temp.ag_audit('grant_career') = 1, 'audit row written');
  perform pg_temp.assert((select data->'new'->>'level' from admin_audit where target_user = p and action = 'grant_career') = '3', 'audit has the new level');
  perform pg_temp.assert((select data->>'reason' from admin_audit where target_user = p and action = 'grant_career') = 'Test promotion', 'audit has the reason');
  perform pg_temp.assert(pg_temp.ag_alerts('admin_grant') = 1, 'player got an alert');
  perform pg_temp.assert((select body from events where user_id = p and kind = 'admin_grant' order by id desc limit 1) like 'An admin gave you career level 3%Reason: Test promotion', 'alert text names the level and reason');
  -- top level and promote more
  perform pg_temp.ag_as('agboss');
  r := admin_grant_career(p, 'health', v_top, null, false, 'Top level test');
  perform pg_temp.assert((select job_level from profiles where id = p) = v_top and (select job_xp from profiles where id = p) = 0, 'top level, xp reset on a level change');
  -- demote, with and without lowering the best
  perform admin_grant_career(p, 'health', 2, null, false, 'Demote test');
  perform pg_temp.assert((select (career_best->>'health')::int from profiles where id = p) = v_top, 'best-ever kept on demotion by default');
  perform pg_temp.assert(pg_temp.ag_alerts('admin_take') = 1, 'a demotion alert is plain (admin_take)');
  perform admin_grant_career(p, 'health', 2, null, true, 'Demote and reset');
  perform pg_temp.assert((select (career_best->>'health')::int from profiles where id = p) = 2, 'best-ever lowered when asked');
  -- xp only
  r := admin_grant_career(p, 'health', null, 10, false, 'Just xp');
  perform pg_temp.assert((select job_xp from profiles where id = p) = 10 and (select job_level from profiles where id = p) = 2, 'xp only keeps the level');
  -- change track
  perform admin_grant_career(p, 'tech', null, null, false, 'Switch track');
  perform pg_temp.assert((select job_id || job_level from profiles where id = p) = 'tech1', 'another track starts at level 1');
  -- mid-shift refused
  update profiles set job_shift_ends_at = bl_now() + interval '10 minutes', job_shift_pay = 1000, job_shift_xp = 5, job_shift_perf = 100 where id = p;
  perform pg_temp.ag_hint(format('select admin_grant_career(%L, ''tech'', 3, null, false, ''while on shift'')', p), 'on_shift');
  perform pg_temp.ag_hint(format('select admin_career_remove(%L, ''while on shift'')', p), 'on_shift');
  update profiles set job_shift_ends_at = null, job_shift_pay = null, job_shift_xp = null, job_shift_perf = null where id = p;
  -- remove
  perform pg_temp.ag_hint(format('select admin_career_remove(%L, '''')', p), 'reason_required');
  perform admin_career_remove(p, 'Remove test');
  perform pg_temp.assert((select job_id from profiles where id = p) is null, 'job removed');
  perform pg_temp.ag_hint(format('select admin_career_remove(%L, ''again please'')', p), 'no_job');
  perform pg_temp.assert(pg_temp.ag_audit('career_remove') = 1, 'remove audited');
  raise notice 'grants 3 OK: career';
end $$;

-- 4. needs and stuck states -------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); r jsonb;
begin
  perform pg_temp.ag_as('agboss');
  update profiles set hunger = 10, energy = 12, hygiene = 30, fun = 5, social = 8, health = 40, stress = 90, bladder = 20, needs_updated_at = bl_now() where id = p;
  perform pg_temp.ag_hint(format('select admin_refill_needs(%L, array[''mood''], '''')', p), 'bad_value');
  r := admin_refill_needs(p, array['hunger', 'stress'], 'partial');
  perform pg_temp.assert((select hunger from profiles where id = p) = 100 and (select stress from profiles where id = p) = 0, 'hunger full, stress calm');
  perform pg_temp.assert((select energy from profiles where id = p) < 20, 'untouched needs stay');
  r := admin_refill_needs(p, null, '');
  perform pg_temp.assert((select least(hunger, energy, hygiene, fun, social, health, bladder) from profiles where id = p) = 100 and (select stress from profiles where id = p) = 0, 'all needs refilled');
  perform pg_temp.assert(pg_temp.ag_audit('refill_needs') = 2, 'refills audited');
  -- stuck states
  update profiles set busy_until = bl_now() + interval '1 hour', busy_label = 'Stuck thing', travel_to = 'police_hq', travel_arrives_at = bl_now() + interval '1 hour',
         hospitalized_until = bl_now() + interval '1 hour', job_id = 'tech', job_level = 1,
         job_shift_ends_at = bl_now() + interval '1 hour', job_shift_pay = 500, job_shift_xp = 3, job_shift_perf = 90 where id = p;
  perform pg_temp.ag_hint(format('select admin_clear_states(%L, array[''bogus''], '''')', p), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_clear_states(%L, null, '''')', p), 'bad_value');
  r := admin_clear_states(p, array['busy', 'travel', 'shift', 'hospital'], 'cleanup');
  perform pg_temp.assert((select busy_until is null and busy_label is null and travel_to is null and hospitalized_until is null and job_shift_ends_at is null from profiles where id = p), 'all stuck states cleared');
  perform pg_temp.assert((select cash from profiles where id = p) = 5000, 'a running shift is cancelled without pay');
  perform pg_temp.ag_as('agplayer');
  perform bl_assert_free(pr) from profiles pr where pr.id = p;
  perform pg_temp.assert(true, 'player is free again (bl_assert_free passes)');
  raise notice 'grants 4 OK: needs and states';
end $$;

-- 5. jail --------------------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); r jsonb;
begin
  perform pg_temp.ag_as('agboss');
  perform pg_temp.ag_hint(format('select admin_jail_set(%L, 9999, ''too long'')', p), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_jail_set(%L, 30, '''')', p), 'reason_required');
  r := admin_jail_set(p, 30, 'Jail test');
  perform pg_temp.assert((select jailed_until > bl_now() from profiles where id = p), 'player is jailed');
  perform pg_temp.assert(exists (select 1 from jail_cases where user_id = p and status = 'open' and bail_amount >= 0), 'an open case exists (the normal jail case)');
  perform pg_temp.ag_hint(format('select admin_jail_set(%L, 30, ''again please'')', p), 'already_jailed');
  perform pg_temp.ag_as('agplayer');
  perform pg_temp.ag_hint('select shop_buy(''roll_and_soda'', 1)', 'jailed');
  perform pg_temp.ag_as('agboss');
  r := admin_jail_set(p, 0, 'Release test');
  perform pg_temp.assert((select jailed_until is null from profiles where id = p), 'released');
  perform pg_temp.assert(not exists (select 1 from jail_cases where user_id = p and status = 'open'), 'case closed');
  perform pg_temp.assert(exists (select 1 from jail_cases where user_id = p and status = 'released' and released_by = pg_temp.ag_u('agboss')), 'closed as released by the admin');
  perform pg_temp.assert(pg_temp.ag_alerts('police_release') = 1 and pg_temp.ag_alerts('admin_jail') = 1, 'both alerts sent');
  perform pg_temp.assert(pg_temp.ag_audit('jail_put') = 1 and pg_temp.ag_audit('jail_release') = 1, 'both audited');
  raise notice 'grants 5 OK: jail';
end $$;

-- 6. numbers, debts, yahoo -------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); r jsonb;
begin
  perform pg_temp.ag_as('agboss');
  perform pg_temp.ag_hint(format('select admin_set_numbers(%L, 50, null, null, '''')', p), 'reason_required');
  perform pg_temp.ag_hint(format('select admin_set_numbers(%L, -1, null, null, ''negative'')', p), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_set_numbers(%L, null, 6, null, ''too wanted'')', p), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_set_numbers(%L, null, null, ''{"goodwill": 101}'', ''too good'')', p), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_set_numbers(%L, null, null, ''{"swagger": 5}'', ''unknown'')', p), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_set_numbers(%L, null, null, null, ''nothing'')', p), 'bad_value');
  r := admin_set_numbers(p, 250, 3, '{"goodwill": 40, "trouble": -10}', 'Numbers test');
  perform pg_temp.assert((select street_cred || '/' || wanted from profiles where id = p) = '250/3', 'street cred and wanted set');
  perform pg_temp.assert((select goodwill || '/' || trouble || '/' || luck from player_path where user_id = p) = '40/-10/0', 'path numbers set, others kept');
  perform pg_temp.assert(pg_temp.ag_audit('set_numbers') = 1, 'audited');
  perform pg_temp.assert((select data->'old'->>'street_cred' from admin_audit where target_user = p and action = 'set_numbers') = '0', 'audit has the old value');
  -- debts
  perform pg_temp.ag_hint(format('select admin_clear_debts(%L, true, true, ''nothing owed'')', p), 'nothing_owed');
  update profiles set rent_owed = 7000, tax_owed = 300 where id = p;
  perform pg_temp.ag_hint(format('select admin_clear_debts(%L, true, true, '''')', p), 'reason_required');
  r := admin_clear_debts(p, true, false, 'Rent forgiven');
  perform pg_temp.assert((select rent_owed || '/' || tax_owed from profiles where id = p) = '0/300', 'only the rent was cleared');
  perform admin_clear_debts(p, false, true, 'Tax forgiven');
  perform pg_temp.assert((select tax_owed from profiles where id = p) = 0, 'tax cleared');
  -- yahoo
  perform pg_temp.ag_hint(format('select admin_set_yahoo_rank(%L, ''nope'', ''bad rank'')', p), 'bad_rank');
  r := admin_set_yahoo_rank(p, 'big_boy', 'Yahoo test');
  perform pg_temp.assert(bl_yahoo_rank(p) = 'big_boy', 'the game''s own rank function says Big Boy');
  r := admin_set_yahoo_rank(p, 'aspirant', 'Yahoo undo');
  perform pg_temp.assert(bl_yahoo_rank(p) = 'aspirant', 'rank lowered again');
  raise notice 'grants 6 OK: numbers, debts, yahoo';
end $$;

-- 7. items and cars --------------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); r jsonb; v_h numeric;
begin
  perform pg_temp.ag_as('agboss');
  perform pg_temp.ag_hint(format('select admin_give_item(%L, ''roll_and_soda'', 0, '''')', p), 'bad_qty');
  perform pg_temp.ag_hint(format('select admin_give_item(%L, ''roll_and_soda'', 100, '''')', p), 'bad_qty');
  perform pg_temp.ag_hint(format('select admin_give_item(%L, ''no_such_item'', 1, '''')', p), 'no_item');
  r := admin_give_item(p, 'roll_and_soda', 3, 'Snacks');
  perform pg_temp.assert((select qty from inventory where user_id = p and item_id = 'roll_and_soda') = 3, 'three in the bag');
  -- usable through the normal game path
  update profiles set hunger = 20, needs_updated_at = bl_now() where id = p;
  perform pg_temp.ag_as('agplayer');
  perform item_use('roll_and_soda');
  perform pg_temp.assert((select qty from inventory where user_id = p and item_id = 'roll_and_soda') = 2, 'item_use ate one');
  perform pg_temp.assert((select hunger from profiles where id = p) > 20, 'and it fed the player');
  perform pg_temp.ag_as('agboss');
  -- undo
  perform pg_temp.ag_hint(format('select admin_take_item(%L, ''roll_and_soda'', 5, '''')', p), 'not_enough');
  r := admin_take_item(p, 'roll_and_soda', 2, 'Take back');
  perform pg_temp.assert(not exists (select 1 from inventory where user_id = p and item_id = 'roll_and_soda'), 'all taken, row gone');
  -- car
  perform pg_temp.ag_hint(format('select admin_give_item(%L, ''tokunbo_car'', 2, '''')', p), 'bad_qty');
  r := admin_give_item(p, 'tokunbo_car', 1, 'A car');
  perform pg_temp.assert(exists (select 1 from inventory where user_id = p and item_id = 'tokunbo_car' and qty = 1), 'car owned');
  perform pg_temp.ag_hint(format('select admin_give_item(%L, ''tokunbo_car'', 1, '''')', p), 'already_owned');
  perform pg_temp.assert(pg_temp.ag_audit('grant_car') = 1 and pg_temp.ag_alerts('admin_grant') >= 3, 'car audited and alerted');
  perform pg_temp.ag_as('agplayer');
  perform pg_temp.assert((get_my_state()->'inventory') @> '[{"id": "tokunbo_car"}]'::jsonb, 'the game''s own state lists the car in the bag');
  perform pg_temp.ag_as('agboss');
  r := admin_take_item(p, 'tokunbo_car', 1, 'Car back');
  perform pg_temp.assert(not exists (select 1 from inventory where user_id = p and item_id = 'tokunbo_car'), 'car taken');
  perform pg_temp.assert(pg_temp.ag_audit('take_item') = 2, 'takes audited');
  raise notice 'grants 7 OK: items and cars';
end $$;

-- 8. furniture ---------------------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); r jsonb; v_max int; v_before int;
begin
  perform pg_temp.ag_as('agboss');
  select least(max_qty, 20) into v_max from furniture where id = 'plastic_chair_white';
  perform pg_temp.ag_hint(format('select admin_give_furniture(%L, ''plastic_chair_white'', 0, '''')', p), 'bad_qty');
  perform pg_temp.ag_hint(format('select admin_give_furniture(%L, ''no_such_piece'', 1, '''')', p), 'unknown_furniture');
  perform pg_temp.ag_hint(format('select admin_give_furniture(%L, ''plastic_chair_white'', %s, '''')', p, v_max + 1), 'max_owned');
  v_before := coalesce((select qty from player_furniture where user_id = p and furniture_id = 'plastic_chair_white'), 0);
  r := admin_give_furniture(p, 'plastic_chair_white', 3, 'Chairs');
  perform pg_temp.assert((select qty from player_furniture where user_id = p and furniture_id = 'plastic_chair_white') = v_before + 3, 'three more copies');
  perform pg_temp.assert((select count(*) from player_house_furniture where owner_id = p and furniture_key like 'own\_plastic\_chair\_white%') = v_before + 3, 'every copy has a house row (My items)');
  perform pg_temp.assert((select count(*) from player_house_furniture where owner_id = p and furniture_key = 'own_plastic_chair_white-' || (v_before + 3)) = 1, 'keys are numbered like furniture_buy does');
  perform pg_temp.ag_as('agplayer');
  perform pg_temp.assert(furniture_sell('own_plastic_chair_white-' || (v_before + 3)) is not null, 'a granted piece sells through the normal game path');
  perform pg_temp.ag_as('agboss');
  r := admin_take_furniture(p, 'plastic_chair_white', 2, 'Back');
  perform pg_temp.assert(coalesce((select qty from player_furniture where user_id = p and furniture_id = 'plastic_chair_white'), 0) = v_before, 'copies back to the start');
  perform pg_temp.assert((select count(*) from player_house_furniture where owner_id = p and furniture_key like 'own\_plastic\_chair\_white%') = v_before, 'house rows follow');
  perform pg_temp.ag_hint(format('select admin_take_furniture(%L, ''plastic_chair_white'', 1, '''')', p), 'not_enough');
  perform pg_temp.assert(pg_temp.ag_audit('grant_furniture') = 1 and pg_temp.ag_audit('take_furniture') = 1, 'furniture audited');
  raise notice 'grants 8 OK: furniture';
end $$;

-- 9. garage, wardrobe, hustle pass ---------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); r jsonb; v_m bigint;
begin
  v_m := (select cash + bank from profiles where id = p);
  perform pg_temp.ag_as('agboss');
  perform pg_temp.ag_hint(format('select admin_give_garage(%L, ''nope'', '''')', p), 'unknown_garage');
  perform pg_temp.ag_hint(format('select admin_give_garage(%L, ''garage_luxury'', '''')', p), 'not_allowed_here');
  r := admin_give_garage(p, 'carport', 'Garage test');
  perform pg_temp.assert((select garage_type || price_paid from player_garages where user_id = p) = 'carport0', 'carport built for free');
  perform pg_temp.assert((select cash + bank from profiles where id = p) = v_m, 'no money moved');
  perform pg_temp.ag_hint(format('select admin_give_garage(%L, ''carport'', '''')', p), 'already_built');
  r := admin_remove_garage(p, 'Garage back');
  perform pg_temp.assert(not exists (select 1 from player_garages where user_id = p), 'garage removed');
  perform pg_temp.ag_hint(format('select admin_remove_garage(%L, '''')', p), 'no_garage');
  -- wardrobe
  perform pg_temp.ag_hint(format('select admin_give_wardrobe(%L, ''nope'', null, '''')', p), 'unknown_item');
  perform pg_temp.ag_hint(format('select admin_give_wardrobe(%L, ''bb_tee'', ''#123456'', '''')', p), 'bad_colour');
  r := admin_give_wardrobe(p, 'bb_tee', null, 'Clothes');
  perform pg_temp.assert(exists (select 1 from player_wardrobe where user_id = p and item_id = 'bb_tee' and price_paid = 0), 'owned in the wardrobe');
  perform pg_temp.ag_hint(format('select admin_give_wardrobe(%L, ''bb_tee'', null, '''')', p), 'already_owned');
  perform pg_temp.ag_as('agplayer');
  perform pg_temp.assert((select bool_or((i->>'owned')::boolean) from jsonb_array_elements(wardrobe_state()->'items') i where i->>'id' = 'bb_tee'), 'wardrobe_state shows it owned');
  perform pg_temp.ag_as('agboss');
  r := admin_take_wardrobe(p, 'bb_tee', 'Clothes back');
  perform pg_temp.assert(not exists (select 1 from player_wardrobe where user_id = p and item_id = 'bb_tee'), 'taken');
  perform pg_temp.ag_hint(format('select admin_take_wardrobe(%L, ''bb_tee'', '''')', p), 'not_owned');
  -- hustle pass
  perform pg_temp.ag_hint(format('select admin_give_hustle_pass(%L, ''stall'', 0, '''')', p), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_give_hustle_pass(%L, ''nope'', 24, '''')', p), 'bad_pass');
  r := admin_give_hustle_pass(p, 'stall', 24, 'Pass test');
  perform pg_temp.assert(bl_hustle_pass_until(p, 'stall') > bl_now() + interval '23 hours', 'the game sees the stall pass');
  r := admin_take_hustle_pass(p, 'stall', 'Pass back');
  perform pg_temp.assert(bl_hustle_pass_until(p, 'stall') is null or bl_hustle_pass_until(p, 'stall') <= bl_now(), 'pass gone');
  raise notice 'grants 9 OK: garage, wardrobe, pass';
end $$;

-- 10. business level --------------------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); v_biz bigint; b businesses; t business_types; v_g1 numeric; v_g2 numeric; r jsonb; v_plot text;
begin
  perform pg_temp.ag_as('agboss');
  select id into v_plot from business_plots bp where bp.active and not exists (select 1 from businesses x where x.plot_id = bp.id)
     and (cardinality(bp.type_ids) = 0 or 'provision_shop' = any (bp.type_ids)) order by bp.sort limit 1;
  r := admin_business_grant(p, 'provision_shop', v_plot, 'Ag Shop');
  v_biz := (r->>'business')::bigint;
  update businesses set base_income = 24000, staff = 0, level = 1 where id = v_biz;
  select * into b from businesses where id = v_biz;
  select * into t from business_types where id = b.type_id;
  v_g1 := bl_biz_gross_hr(b, t);
  perform pg_temp.ag_hint(format('select admin_business_set(%s, 2, null, null, null, '''')', v_biz), 'reason_required');
  perform pg_temp.ag_hint(format('select admin_business_set(%s, %s, null, null, null, ''too high'')', v_biz, t.max_level + 1), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_business_set(%s, 0, null, null, null, ''too low'')', v_biz), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_business_set(%s, null, %s, null, null, ''too many staff'')', v_biz, t.staff_slots + 1), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_business_set(%s, null, null, 91, null, ''too long'')', v_biz), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_business_set(%s, null, null, null, null, ''nothing'')', v_biz), 'bad_value');
  perform pg_temp.ag_hint('select admin_business_set(999999999, 2, null, null, null, ''ghost'')', 'gone');
  r := admin_business_set(v_biz, 3, 1, 7, 100, 'Business test');
  select * into b from businesses where id = v_biz;
  perform pg_temp.assert(b.level = 3 and b.staff = 1 and b.insured_until > bl_now() + interval '6 days' and b.stock_until > bl_now() + interval '99 hours', 'level, staff, insurance, stock set');
  v_g2 := bl_biz_gross_hr(b, t);
  perform pg_temp.assert(v_g2 > v_g1, 'the granted level raises the hourly takings (' || v_g1 || ' to ' || v_g2 || ')');
  perform pg_temp.assert(b.invested = 0, 'invested stays 0 (a gift is not an investment)');
  perform pg_temp.assert((select biz_level from locations where id = b.plot_id) = 3, 'map pin shows the new level');
  perform admin_business_set(v_biz, 1, null, 0, 0, 'Business undo');
  select * into b from businesses where id = v_biz;
  perform pg_temp.assert(b.level = 1 and b.insured_until is null, 'lowered again, insurance removed');
  update businesses set listed = true where id = v_biz;
  perform pg_temp.ag_hint(format('select admin_business_set(%s, 2, null, null, null, ''listed one'')', v_biz), 'listed');
  update businesses set listed = false where id = v_biz;
  perform pg_temp.assert(pg_temp.ag_audit('grant_business_level') = 2, 'audited twice');
  perform pg_temp.assert((select data->'old'->>'level' from admin_audit where target_user = p and action = 'grant_business_level' order by id limit 1) = '1', 'audit keeps the old level');
  raise notice 'grants 10 OK: business level';
end $$;

-- 11. company ----------------------------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); r jsonb; v_c bigint; v_i text; v_a text;
begin
  perform pg_temp.ag_as('agboss');
  select id into v_i from company_industries where active order by sort limit 1;
  select id into v_a from company_areas where active order by sort limit 1;
  perform pg_temp.ag_hint(format('select admin_company_grant(%L, ''nope'', %L, ''Ag Co'', ''reason'')', p, v_a), 'bad_industry');
  perform pg_temp.ag_hint(format('select admin_company_grant(%L, %L, ''nope'', ''Ag Co'', ''reason'')', p, v_i), 'bad_area');
  perform pg_temp.ag_hint(format('select admin_company_grant(%L, %L, %L, ''Ag Co'', '''')', p, v_i, v_a), 'reason_required');
  r := admin_company_grant(p, v_i, v_a, 'Ag Co', 'Company test');
  v_c := (r->>'id')::bigint;
  v_c := coalesce(v_c, (r->>'company')::bigint);
  perform pg_temp.assert((select source || invested from companies where id = v_c) = 'admin0', 'company exists, source admin, invested 0');
  perform pg_temp.assert(exists (select 1 from company_branches where company_id = v_c and is_hq and format_id = 'kiosk'), 'head office kiosk');
  perform pg_temp.ag_hint(format('select admin_company_grant(%L, %L, %L, ''ag co'', ''dup'')', p, v_i, v_a), 'name_taken');
  perform pg_temp.ag_hint(format('select admin_company_set(%s, ''nope'', null, null, null, ''bad size'')', v_c), 'bad_format');
  perform pg_temp.ag_hint(format('select admin_company_set(%s, null, 99, null, null, ''too many'')', v_c), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_company_set(%s, null, null, null, null, ''nothing'')', v_c), 'bad_value');
  r := admin_company_set(v_c, 'shop', 4, true, true, 'Company set');
  perform pg_temp.assert((select format_id from company_branches where company_id = v_c and is_hq) = 'shop', 'size changed to shop');
  perform pg_temp.assert((select staff || manager::text || generator::text from companies where id = v_c) = '4truetrue', 'staff, manager, generator set');
  r := admin_company_set(v_c, 'kiosk', null, false, false, 'Company undo');
  perform pg_temp.assert((select staff from companies where id = v_c) <= 2, 'staff squeezed to the smaller size');
  update companies set listed = true where id = v_c;
  perform pg_temp.ag_hint(format('select admin_company_set(%s, ''shop'', null, null, null, ''listed'')', v_c), 'listed');
  update companies set listed = false where id = v_c;
  perform pg_temp.assert(pg_temp.ag_audit('grant_company') = 1 and pg_temp.ag_audit('grant_company_set') = 2, 'company audited');
  raise notice 'grants 11 OK: company';
end $$;

-- 12. home, property, land ---------------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); r jsonb; v_prop uuid; v_offer text; v_old text; v_plots numeric;
begin
  perform pg_temp.ag_as('agboss');
  perform pg_temp.ag_hint(format('select admin_set_home(%L, ''uselu_self_contain'', null, '''')', p), 'reason_required');
  perform pg_temp.ag_hint(format('select admin_set_home(%L, ''nope'', null, ''bad home'')', p), 'bad_home');
  perform pg_temp.ag_hint(format('select admin_set_home(%L, null, null, ''nothing picked'')', p), 'bad_value');
  perform pg_temp.ag_hint(format('select admin_set_home(%L, ''ekenwan_face_me'', null, ''same'')', p), 'same_home');
  update profiles set busy_until = bl_now() + interval '1 hour', busy_label = 'Busy test' where id = p;
  perform pg_temp.ag_hint(format('select admin_set_home(%L, ''uselu_self_contain'', null, ''busy now'')', p), 'cannot_move');
  update profiles set busy_until = null, busy_label = null where id = p;
  v_old := (select start_home from profiles where id = p);
  perform set_config('agtest.money12', (select cash + bank from profiles where id = p)::text, true);
  r := admin_set_home(p, 'uselu_self_contain', null, 'Home test');
  perform pg_temp.assert((select start_home from profiles where id = p) = 'uselu_self_contain', 'start_home changed');
  perform pg_temp.assert((select housing_id from profiles where id = p) = (select housing_id from start_homes where id = 'uselu_self_contain'), 'housing follows');
  perform pg_temp.assert((select cash + bank from profiles where id = p) = current_setting('agtest.money12')::bigint, 'no move-in fee charged');
  perform pg_temp.ag_as('agplayer');
  perform pg_temp.assert(get_my_state()->'profile'->>'start_home' = 'uselu_self_contain', 'the game state shows the new home');
  perform pg_temp.ag_as('agboss');
  -- give a property, live in it, refuse to take it while occupied
  select id into v_offer from property_offers where active order by price limit 1;
  perform pg_temp.ag_hint(format('select admin_give_property(%L, ''nope'', ''bad offer'')', p), 'bad_offer');
  perform pg_temp.ag_hint(format('select admin_give_property(%L, %L, '''')', p, v_offer), 'reason_required');
  r := admin_give_property(p, v_offer, 'Property test');
  v_prop := (r->>'property')::uuid;
  perform pg_temp.assert((select basis from properties where id = v_prop) = 0 and (select owner_id from properties where id = v_prop) = p, 'property owned, basis 0');
  perform pg_temp.ag_as('agplayer');
  r := property_live_in(v_prop);
  perform pg_temp.assert(exists (select 1 from player_residence where user_id = p and property_id = v_prop), 'the player can live in it (normal game path)');
  perform pg_temp.ag_as('agboss');
  perform pg_temp.ag_hint(format('select admin_take_property(%L, %L, ''occupied'')', p, v_prop), 'occupied');
  r := admin_set_home(p, 'ekenwan_face_me', null, 'Back to a room');
  perform pg_temp.assert(not exists (select 1 from player_residence where user_id = p), 'moved out of the property');
  r := admin_set_home(p, null, v_prop, 'Into the property');
  perform pg_temp.assert(exists (select 1 from player_residence where user_id = p and property_id = v_prop and role = 'owner'), 'set home into an owned property works');
  r := admin_set_home(p, 'ekenwan_face_me', null, 'Out again');
  r := admin_take_property(p, v_prop, 'Property undo');
  perform pg_temp.assert(not exists (select 1 from properties where id = v_prop), 'property removed');
  -- land
  perform pg_temp.ag_hint(format('select admin_give_land(%L, ''land_gra'', 0, ''bad'')', p), 'bad_qty');
  perform pg_temp.ag_hint(format('select admin_give_land(%L, ''land_nope'', 2, ''bad market'')', p), 'bad_market');
  r := admin_give_land(p, 'land_gra', 3, 'Land test');
  perform pg_temp.assert((select qty from invest_positions where user_id = p and ref_id = 'land_gra') = 3, 'three plots');
  r := admin_give_land(p, 'land_gra', 2, 'More land');
  perform pg_temp.assert((select qty from invest_positions where user_id = p and ref_id = 'land_gra') = 5, 'five plots (merged into one position)');
  perform pg_temp.assert((select cost from invest_positions where user_id = p and ref_id = 'land_gra') = 0, 'gift land has cost 0');
  perform pg_temp.ag_hint(format('select admin_take_land(%L, ''land_gra'', 6, ''too many'')', p), 'not_enough');
  r := admin_take_land(p, 'land_gra', 5, 'Land undo');
  perform pg_temp.assert(not exists (select 1 from invest_positions where user_id = p and ref_id = 'land_gra'), 'position removed at zero');
  perform pg_temp.assert(pg_temp.ag_audit('set_home') = 4 and pg_temp.ag_audit('grant_land') = 2 and pg_temp.ag_audit('take_land') = 1, 'audited');
  raise notice 'grants 12 OK: home, property, land';
end $$;

-- 13. crew -----------------------------------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); o uuid := pg_temp.ag_u('agother'); v_crew bigint; r jsonb;
begin
  perform pg_temp.ag_as('agboss');
  insert into crews (name, tag, created_by) values ('Ag Crew', 'AGC', o) returning id into v_crew;
  insert into crew_members (user_id, crew_id, rank) values (o, v_crew, 'boss');
  perform pg_temp.ag_hint(format('select admin_crew_set(%L, %s, ''boss'', '''')', p, v_crew), 'bad_rank');
  perform pg_temp.ag_hint(format('select admin_crew_set(%L, 99999999, ''member'', '''')', p), 'bad_crew');
  r := admin_crew_set(p, v_crew, 'prospect', 'Crew test');
  perform pg_temp.assert((select rank from crew_members where user_id = p and crew_id = v_crew) = 'prospect', 'in the crew as prospect');
  perform pg_temp.assert(exists (select 1 from events where user_id = o and kind = 'crew_joined'), 'the crew was told (normal join path)');
  perform pg_temp.ag_hint(format('select admin_crew_set(%L, %s, ''prospect'', '''')', p, v_crew), 'same_rank');
  r := admin_crew_set(p, v_crew, 'lieutenant', 'Promote');
  perform pg_temp.assert((select rank from crew_members where user_id = p) = 'lieutenant', 'rank changed');
  perform pg_temp.ag_hint(format('select admin_crew_remove(%L, '''')', o), 'is_boss');
  r := admin_crew_remove(p, 'Crew undo');
  perform pg_temp.assert(not exists (select 1 from crew_members where user_id = p), 'removed');
  perform pg_temp.ag_hint(format('select admin_crew_remove(%L, '''')', p), 'no_crew');
  perform pg_temp.assert(pg_temp.ag_audit('grant_crew') = 2 and pg_temp.ag_audit('crew_remove') = 1, 'crew audited');
  delete from crew_members where crew_id = v_crew;
  raise notice 'grants 13 OK: crew';
end $$;

-- 14. chief title, course ------------------------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); r jsonb; v_ward text;
begin
  perform pg_temp.ag_as('agboss');
  select id into v_ward from wards where active order by sort limit 1;
  perform pg_temp.ag_hint(format('select admin_set_chief_title(%L, 99, %L, ''bad tier'')', p, v_ward), 'bad_tier');
  perform pg_temp.ag_hint(format('select admin_set_chief_title(%L, 1, ''nope'', ''bad ward'')', p), 'bad_ward');
  perform pg_temp.ag_hint(format('select admin_set_chief_title(%L, 1, %L, '''')', p, v_ward), 'reason_required');
  r := admin_set_chief_title(p, 1, v_ward, 'Title test');
  perform pg_temp.assert(bl_chief_title(p) is not null, 'the game''s title function returns it');
  perform pg_temp.assert((select paid from chief_titles where user_id = p) = 0, 'paid 0 (no upgrade credit from a gift)');
  r := admin_remove_chief_title(p, 'Title undo');
  perform pg_temp.assert(bl_chief_title(p) is null, 'title removed');
  perform pg_temp.ag_hint(format('select admin_remove_chief_title(%L, '''')', p), 'no_title');
  -- course
  perform pg_temp.ag_hint(format('select admin_complete_course(%L, ''nope'', '''')', p), 'bad_course');
  r := admin_complete_course(p, 'driving_school', 'Course test');
  perform pg_temp.assert((select status || classes_done from course_enrolments where user_id = p and course_id = 'driving_school') = 'completed5', 'course completed with every class');
  perform pg_temp.assert(bl_cert_has(p, 'driving'), 'the certificate is awarded through the game''s own function');
  perform pg_temp.assert(pg_temp.ag_alerts('graduated') = 1, 'the graduation alert fires');
  perform pg_temp.ag_hint(format('select admin_complete_course(%L, ''driving_school'', '''')', p), 'already');
  r := admin_reset_course(p, 'driving_school', true, 'Course undo');
  perform pg_temp.assert(not exists (select 1 from course_enrolments where user_id = p and course_id = 'driving_school') and not bl_cert_has(p, 'driving'), 'reset and certificate revoked');
  perform pg_temp.ag_hint(format('select admin_reset_course(%L, ''driving_school'', false, '''')', p), 'not_enrolled');
  raise notice 'grants 14 OK: chief title, course';
end $$;

-- 15. state + catalog -----------------------------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); s jsonb; c jsonb; k text;
begin
  perform pg_temp.ag_as('agboss');
  perform admin_grant_career(p, 'tech', 2, 5, false, 'State test');
  perform admin_give_item(p, 'roll_and_soda', 2, '');
  s := admin_grant_state(p);
  foreach k in array array['career', 'status', 'needs', 'states', 'home', 'inventory', 'furniture', 'wardrobe', 'passes', 'properties', 'land', 'businesses', 'companies', 'courses'] loop
    perform pg_temp.assert(s ? k, 'state has ' || k);
  end loop;
  perform pg_temp.assert((s->'career'->>'level')::int = 2 and (s->'career'->>'xp')::int = 5, 'state shows career level and xp');
  perform pg_temp.assert(s->'inventory' @> '[{"item": "roll_and_soda", "qty": 2}]'::jsonb, 'state lists the bag');
  perform pg_temp.assert(jsonb_array_length(s->'courses') >= 10, 'all courses listed');
  perform pg_temp.assert(jsonb_array_length(s->'businesses') = 1, 'the business is listed');
  perform pg_temp.ag_hint(format('select admin_grant_state(%L)', gen_random_uuid()), 'no_player');
  c := admin_grant_catalog();
  foreach k in array array['careers', 'items', 'furniture', 'wardrobe', 'garages', 'homes', 'offers', 'land', 'chief_tiers', 'wards', 'yahoo_ranks', 'passes', 'company_industries', 'company_areas', 'company_formats', 'path_keys', 'needs'] loop
    perform pg_temp.assert(c ? k and jsonb_array_length(c->k) > 0, 'catalog has ' || k);
  end loop;
  perform pg_temp.assert(c ? 'crews', 'catalog has a crews list (may be empty)');
  perform admin_take_item(p, 'roll_and_soda', 2, '');
  raise notice 'grants 15 OK: state and catalog';
end $$;

-- 16. banned and deleted targets ------------------------------------------------------------------------------------
do $$
declare b uuid := pg_temp.ag_u('agbanned'); ghost uuid := gen_random_uuid(); s text; u text;
begin
  perform pg_temp.ag_as('agboss');
  foreach u in array array[b::text, ghost::text] loop
    foreach s in array array[
      'admin_grant_career(%L, ''tech'', 2, null, false, ''try'')', 'admin_refill_needs(%L, null, '''')', 'admin_jail_set(%L, 10, ''try'')',
      'admin_set_numbers(%L, 5, null, null, ''try'')', 'admin_clear_debts(%L, true, true, ''try'')', 'admin_set_yahoo_rank(%L, ''g_boy'', ''try'')',
      'admin_give_item(%L, ''roll_and_soda'', 1, '''')', 'admin_give_furniture(%L, ''stool'', 1, '''')', 'admin_give_garage(%L, ''carport'', '''')',
      'admin_give_wardrobe(%L, ''bb_tee'', null, '''')', 'admin_give_hustle_pass(%L, ''stall'', 24, '''')', 'admin_set_home(%L, ''uselu_self_contain'', null, ''try'')',
      'admin_give_property(%L, ''airport_room_fmiyf'', ''try'')', 'admin_give_land(%L, ''land_gra'', 1, ''try'')', 'admin_crew_set(%L, 1, ''member'', '''')',
      'admin_set_chief_title(%L, 1, ''x'', ''try'')', 'admin_complete_course(%L, ''driving_school'', '''')'] loop
      perform pg_temp.ag_hint('select ' || format(s, u), case when u = b::text then 'banned' else 'no_player' end);
    end loop;
  end loop;
  -- taking back from a banned account is still allowed
  insert into inventory (user_id, item_id, qty) values (b, 'roll_and_soda', 2);
  perform admin_take_item(b, 'roll_and_soda', 2, 'strip a cheater');
  perform pg_temp.assert(not exists (select 1 from inventory where user_id = b and item_id = 'roll_and_soda'), 'a take works on a banned account');
  perform pg_temp.assert(not exists (select 1 from admin_audit where target_user = b and action like 'grant\_%'), 'no grant audit rows for the banned account');
  raise notice 'grants 16 OK: banned and deleted targets refused';
end $$;

-- 17. audit rows, alerts, nothing earned ------------------------------------------------------------------------------
do $$
declare p uuid := pg_temp.ag_u('agplayer'); v_n int;
begin
  perform pg_temp.ag_as('agboss');
  select count(*) into v_n from admin_audit where target_user = p and (action like 'grant\_%' or action like 'take\_%' or action in ('career_remove', 'refill_needs', 'clear_states', 'jail_put', 'jail_release', 'set_numbers', 'clear_debts', 'set_yahoo_rank', 'set_home', 'crew_remove', 'remove_chief_title', 'reset_course', 'remove_garage'));
  perform pg_temp.assert(v_n >= 40, 'many audit rows exist (' || v_n || ')');
  perform pg_temp.assert(not exists (select 1 from admin_audit where target_user = p and (data->>'reason' is null) and action in ('grant_career', 'set_numbers', 'grant_business_level', 'set_home', 'grant_property', 'grant_land')), 'every level and money-like audit row carries a reason');
  perform pg_temp.assert((select count(*) from ledger where user_id = p and reason <> 'furniture_sell') = current_setting('agtest.ledger0')::int, 'no ledger rows written by any grant (the one furniture_sell row is the test selling a gifted chair)');
  perform pg_temp.assert(bl_week_earned(p, bl_week_start(bl_now())) = 0, 'nothing counts as earned this week');
  perform pg_temp.assert(not ('admin_grant' = any (bl_earn_reasons())) and not ('grant_item' = any (bl_earn_reasons())), 'no grant reason is an earning reason');
  perform pg_temp.assert((select count(*) from events where user_id = p and kind in ('admin_grant', 'admin_take', 'admin_jail', 'police_release') and data->>'admin' = 'true') >= 30, 'the player got an alert for the grants');
  perform pg_temp.assert(not exists (select 1 from events where user_id = p and kind like 'admin\_%' and title is null), 'alerts have titles');
  perform pg_temp.ag_as('agplayer');
  perform pg_temp.assert(exists (select 1 from events where user_id = p and kind = 'admin_grant'), 'the player can read their own alerts');
  perform pg_temp.ag_as('agboss');
  perform pg_temp.ag_hint(format('select admin_give_item(%L, ''roll_and_soda'', 1, '''')', pg_temp.ag_u('agbanned')), 'banned');
  perform pg_temp.assert((select count(*) from admin_audit where target_user = pg_temp.ag_u('agbanned') and action in ('grant_item', 'grant_car')) = 0, 'refused grants leave no audit row');
  raise notice 'grants 17 OK: audit, alerts, nothing earned';
end $$;
