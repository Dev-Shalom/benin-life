-- New-player journey (20261109000100_journey). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/journey_test.sql
-- Each step completes from a real action, pays once, days unlock on distinct play days, eligibility, finish bonus, ledger is not
-- earnings, switch off, admin-only funnel and editor, the push, RLS and grants.

-- put the clock at about noon in Benin so a run never crosses midnight
do $$
declare v_local timestamp := now() at time zone bl_clock_tz();
begin
  perform set_config('bl.test_offset_seconds', round(extract(epoch from (date_trunc('day', v_local) + interval '12 hours' - v_local)))::text, true);
end $$;
update public.game_config set value = '0'::jsonb where key in ('journey.eval_seconds', 'gist.min_account_minutes', 'journey.tick_seconds');
update public.game_config set value = 'false'::jsonb where key = 'rent.enabled';

create or replace function pg_temp.jn_user(p_name text) returns uuid
language plpgsql as $$
declare u uuid := pg_temp.new_user(lower(p_name) || '@jn.bl');
begin
  perform pg_temp.login(u);
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set created_at = least(now(), bl_now()), busy_until = null, busy_label = null where id = u;
  return u;
end $$;

create or replace function pg_temp.jn_jump(p_days numeric) returns void
language plpgsql as $$
begin
  perform set_config('bl.test_offset_seconds', (coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_days * 86400)::text, true);
end $$;

create or replace function pg_temp.jn_hint(p_sql text) returns text
language plpgsql as $$
declare h text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  get stacked diagnostics h = pg_exception_hint;
  return coalesce(h, 'err:' || sqlerrm);
end $$;

-- one step's state / the whole status
create or replace function pg_temp.jn_state(p_step text) returns text
language sql as $$ select x->>'state' from jsonb_array_elements(journey_status()->'steps') x where x->>'id' = p_step $$;

create or replace function pg_temp.jn_cash(p_uid uuid) returns bigint
language sql as $$ select cash from profiles where id = p_uid $$;

-- an unused Sim: play-day rows for days since sign-up
create or replace function pg_temp.jn_day(p_uid uuid, p_offset int) returns void
language sql as $$ insert into player_days (user_id, day) values (p_uid, bl_wat_date() + p_offset) on conflict do nothing $$;

-- =========================================================================================
-- 0. shape, grants, RLS
-- =========================================================================================
do $$
declare t text; f text;
begin
  perform pg_temp.assert((select count(*) from journey_steps where active) = 14, '14 steps seeded');
  perform pg_temp.assert((select count(*) from journey_steps where day = 1) = 5 and (select count(*) from journey_steps where day = 2) = 5
                          and (select count(*) from journey_steps where day = 3) = 4, '5 + 5 + 4 steps by day');
  perform pg_temp.assert((select count(*) from game_config where category = 'journey') >= 14, 'settings are in category journey');
  perform pg_temp.assert((select count(*) from game_config where category = 'journey' and (label = '' or description = '')) = 0, 'every setting has a label and a description');
  -- every step reward stays under one starter work day (the BALANCE.md ladder: a starter day is about 8,400)
  perform pg_temp.assert((select max(reward_cash) from journey_steps) <= 1500, 'no single step pays more than 1,500');
  perform pg_temp.assert((select sum(reward_cash) from journey_steps) < 3 * 8400, 'all steps together pay less than three starter days: ' || (select sum(reward_cash) from journey_steps));
  perform pg_temp.assert(not ('New player reward' = any (bl_earn_reasons())), 'the ledger reason is not an earn reason (no tax, no leaderboard)');
  foreach t in array array['journey_steps', 'journey_progress', 'journey_done', 'journey_step_stats', 'journey_job'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || t)::regclass), t || ' has RLS');
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || t, 'select') and not has_table_privilege('authenticated', 'public.' || t, 'select')
                            and not has_table_privilege('authenticated', 'public.' || t, 'insert'), t || ' is closed to players');
  end loop;
  foreach f in array array['journey_status()', 'journey_claim(text)', 'journey_mark(text)', 'admin_journey_funnel()'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute') and not has_function_privilege('anon', 'public.' || f, 'execute'), f || ' is for signed-in players only');
  end loop;
  foreach f in array array['bl_journey_note(uuid,text)', 'bl_journey_visit(uuid,text)', 'bl_journey_stat(text,text)', 'bl_journey_earned(uuid,timestamptz)',
                           'bl_journey_nth_day(uuid,timestamptz,integer)', 'bl_journey_start(uuid)', 'bl_journey_eval(uuid,boolean)', 'bl_journey_tick()'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', 'public.' || f, 'execute') and not has_function_privilege('anon', 'public.' || f, 'execute'), f || ' is not callable by players');
  end loop;
  -- no foreign key to profiles, no trigger of ours on it
  perform pg_temp.assert(not exists (select 1 from pg_constraint where contype = 'f' and confrelid = 'public.profiles'::regclass
                                       and conrelid in ('public.journey_progress'::regclass, 'public.journey_done'::regclass)), 'no foreign key to profiles');
  perform pg_temp.assert(not exists (select 1 from pg_trigger where tgrelid = 'public.profiles'::regclass and not tgisinternal and tgname like '%journey%'), 'no trigger on profiles');
end $$;

-- =========================================================================================
-- 1. a new player: the line starts on day 1, locked days are shown but locked
-- =========================================================================================
do $$
declare a uuid := pg_temp.jn_user('JN_One'); r jsonb;
begin
  perform pg_temp.login(a);
  r := journey_status();
  perform pg_temp.assert((r->>'enabled')::boolean and (r->>'eligible')::boolean, 'a new player is offered the journey');
  perform pg_temp.assert((r->>'day')::int = 1 and (r->>'total')::int = 14 and (r->>'done')::int = 0 and (r->>'pct')::int = 0, 'day 1, 14 steps, nothing done: ' || r::text);
  perform pg_temp.assert((select count(*) from jsonb_array_elements(r->'steps') x where x->>'state' = 'active') = 5, 'five active steps on day 1');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(r->'steps') x where x->>'state' = 'locked') = 9, 'nine locked steps');
  perform pg_temp.assert(pg_temp.jn_state('j_earn') = 'locked' and pg_temp.jn_state('j_skill') = 'locked', 'later days are locked');
  perform pg_temp.assert((select count(*) from journey_progress where user_id = a) = 1, 'one progress row');
  perform journey_status(); perform journey_status();
  perform pg_temp.assert((select count(*) from journey_progress where user_id = a) = 1, 'still one progress row');
  perform pg_temp.assert((select reached from journey_step_stats where step_id = '_started') >= 1, 'the funnel counted a start');
  perform pg_temp.assert(pg_temp.jn_hint('select journey_claim(''j_tour'')') = 'not_done', 'cannot claim a step that is not done');
  perform pg_temp.assert(pg_temp.jn_hint('select journey_claim(''j_earn'')') = 'not_done', 'cannot claim a locked step');
  perform pg_temp.assert(pg_temp.jn_hint('select journey_claim(''nope'')') = 'no_step', 'unknown step');
  perform pg_temp.assert(pg_temp.jn_hint('select journey_mark(''whatever'')') = 'ok' and (select marks = '{}'::jsonb from journey_progress where user_id = a), 'journey_mark only takes the dream mark');
  perform pg_temp.assert(not exists (select 1 from events where user_id = a and kind like 'journey%'), 'the first look is quiet: no alerts for what was already true');
end $$;

-- =========================================================================================
-- 2. day 1 steps from real actions, claim once, ledger, no tax
-- =========================================================================================
do $$
declare a uuid := pg_temp.jn_user('JN_Day1'); r jsonb; c0 bigint; n int; v_pay bigint;
begin
  perform pg_temp.login(a);
  perform journey_status();

  -- tour
  perform tour_done();
  perform pg_temp.assert(pg_temp.jn_state('j_tour') = 'done', 'tour step done after tour_done()');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'journey_step' and (data->>'step') = 'j_tour' and title like '%Step done%'), 'a "Step done" alert');
  perform pg_temp.assert((select body from events where user_id = a and kind = 'journey_step' and (data->>'step') = 'j_tour') like '%₦500%', 'the alert names the reward');
  -- claim pays once. Tax owed must not be garnished (not an earn reason).
  update profiles set tax_owed = 1000 where id = a;
  c0 := pg_temp.jn_cash(a);
  r := journey_claim('j_tour');
  perform pg_temp.assert(pg_temp.jn_cash(a) = c0 + 500 and (r->>'cash')::bigint = 500, 'claim pays the written reward: ' || r::text);
  perform pg_temp.assert((select tax_owed from profiles where id = a) = 1000, 'no tax garnish on the reward');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'New player reward' and delta = 500), 'ledger reason New player reward');
  perform pg_temp.assert(bl_journey_earned(a, bl_now() - interval '1 day') = 0, 'the reward is not counted as earnings');
  perform pg_temp.assert(pg_temp.jn_hint('select journey_claim(''j_tour'')') = 'already_claimed', 'second claim refused');
  perform pg_temp.assert(pg_temp.jn_cash(a) = c0 + 500, 'second claim paid nothing');
  perform pg_temp.assert(pg_temp.jn_state('j_tour') = 'claimed', 'state claimed');
  update profiles set tax_owed = 0 where id = a;

  -- eat: needs an item in the Bag
  perform pg_temp.assert(pg_temp.jn_state('j_eat') = 'active', 'eat is active');
  perform bl_give_item(a, 'bottled_water', 1);
  update profiles set busy_until = null, busy_label = null where id = a;
  perform item_use('bottled_water');
  perform pg_temp.assert(pg_temp.jn_state('j_eat') = 'done', 'eating completes the step');

  -- first shift: apply, go to work, work a shift, finish it
  perform pg_temp.assert(pg_temp.jn_state('j_shift') = 'active', 'shift is active');
  perform job_apply('tech');
  perform pg_temp.assert(pg_temp.jn_state('j_shift') = 'active', 'having a job is not enough');
  update profiles set location_id = 'bronze_tech_hub', hunger = 100, energy = 100, hygiene = 100, stress = 0, needs_updated_at = bl_now() where id = a;
  perform work_shift();
  perform pg_temp.jn_jump(400.0 / 86400);
  perform work_finish();
  perform pg_temp.assert((select job_total_shifts from profiles where id = a) = 1, 'one shift is settled');
  perform pg_temp.assert(pg_temp.jn_state('j_shift') = 'done', 'one finished shift completes the step');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'salary'), 'salary is a real earning');

  -- buy something (a shop item, paid with cash)
  perform pg_temp.assert(pg_temp.jn_state('j_buy') = 'active', 'buy is active');
  update profiles set location_id = 'oba_market', cash = cash + 5000 where id = a;
  perform shop_buy('bottled_water', 1);
  perform pg_temp.assert(pg_temp.jn_state('j_buy') = 'done', 'a shop purchase completes the step');

  -- daily story
  perform pg_temp.assert(pg_temp.jn_state('j_story') = 'active', 'story is active');
  r := story_today();
  update profiles set location_id = 'ekenwan_room' where id = a;
  select id into n from player_stories where user_id = a and kind = 'daily' and status = 'pending' order by id limit 1;
  if n is not null then
    perform story_answer(n, (select c->>'id' from player_stories s join life_moments m on m.id = s.story_id, jsonb_array_elements(m.choices) c where s.id = n limit 1));
    perform pg_temp.assert(pg_temp.jn_state('j_story') = 'done', 'answering today''s story completes the step');
  else
    raise notice 'no daily story available in this database: story step checked in group 3 only';
  end if;
end $$;

-- the story step from a direct row, and the home activity mark
do $$
declare a uuid := pg_temp.jn_user('JN_Story'); b uuid := pg_temp.jn_user('JN_Home');
begin
  perform pg_temp.login(a); perform journey_status();
  perform pg_temp.assert(pg_temp.jn_state('j_story') = 'active', 'story active');
  insert into player_stories (user_id, story_id, kind, day, status, answered_at) values (a, (select id from life_moments where kind = 'daily' limit 1), 'daily', bl_wat_date(), 'pending', null);
  perform pg_temp.assert(pg_temp.jn_state('j_story') = 'active', 'an unanswered story does not count');
  update player_stories set status = 'answered', answered_at = bl_now() where user_id = a;
  perform pg_temp.assert(pg_temp.jn_state('j_story') = 'done', 'an answered daily story counts');

  perform pg_temp.login(b); perform journey_status();
  update profiles set location_id = home_location_id, energy = 30, busy_until = null, busy_label = null where id = b;
  begin
    perform do_activity('sleep');
  exception when others then
    -- no bed yet: the mark is still written by any home activity; use the first one the home allows
    raise notice 'sleep refused (%), trying another home activity', sqlerrm;
    perform do_activity((select id from activities where home_only and not needs_furniture order by id limit 1));
  end;
  perform pg_temp.assert(pg_temp.jn_state('j_eat') = 'done', 'resting at home completes the eat-or-rest step');
end $$;

-- =========================================================================================
-- 3. day unlock on DISTINCT play days; day 2 and day 3 steps
-- =========================================================================================
do $$
declare a uuid := pg_temp.jn_user('JN_Days'); o uuid := pg_temp.jn_user('JN_Other'); r jsonb; v_c bigint; v_id bigint; v_g bigint;
begin
  perform pg_temp.login(a);
  perform journey_status();
  perform pg_temp.jn_day(a, 0);
  perform pg_temp.jn_day(a, 0);   -- the same day twice = one day
  perform get_my_state();
  r := journey_status();
  perform pg_temp.assert((r->>'day')::int = 1, 'many heartbeats on one day stay on day 1');
  perform pg_temp.assert(pg_temp.jn_state('j_reward2') = 'locked', 'day 2 is locked on day 1');

  -- claim the daily reward on day 1: does NOT complete the day-2 step
  perform daily_reward_claim();
  r := journey_status();
  perform pg_temp.assert(pg_temp.jn_state('j_reward2') = 'locked', 'a day-1 reward claim never completes the day-2 step');

  -- the 2nd distinct play day
  perform pg_temp.jn_jump(1);
  perform pg_temp.jn_day(a, 0);
  r := journey_status();
  perform pg_temp.assert((r->>'day')::int = 2, 'the second distinct play day unlocks day 2: ' || r::text);
  perform pg_temp.assert(pg_temp.jn_state('j_reward2') = 'active' and pg_temp.jn_state('j_day3') = 'locked', 'day 2 steps are active, day 3 locked');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'journey_day' and title like '%Day 2%'), 'a day-2 unlock alert');
  perform journey_status();
  perform pg_temp.assert((select count(*) from events where user_id = a and kind = 'journey_day') = 1, 'the alert is made once');

  -- j_reward2: claim today's daily reward
  perform daily_reward_claim();
  perform pg_temp.assert(pg_temp.jn_state('j_reward2') = 'done', 'claiming on day 2 completes the step');

  -- j_earn: 15,000 in earn-reason ledger rows (progress shows)
  perform bl_add_money(a, 'cash', 6000, 'salary', '{}');
  r := journey_status();
  perform pg_temp.assert((select (x->'progress'->>'have')::int = 6000 and (x->'progress'->>'need')::int = 15000 from jsonb_array_elements(r->'steps') x where x->>'id' = 'j_earn'), 'earn progress 6000 of 15000');
  perform pg_temp.assert(pg_temp.jn_state('j_earn') = 'active', 'not yet');
  perform bl_add_money(a, 'cash', 9000, 'hustle', '{}');
  perform pg_temp.assert(pg_temp.jn_state('j_earn') = 'done', 'total earnings reach the target');

  -- j_friend: a friend request counts (and a message works for another player)
  perform pg_temp.assert(pg_temp.jn_state('j_friend') = 'active', 'friend active');
  perform social_add_friend(o);
  perform pg_temp.assert(pg_temp.jn_state('j_friend') = 'done', 'sending a friend request completes the step');
  perform pg_temp.login(o); perform journey_status(); perform pg_temp.jn_day(o, 0);
  perform pg_temp.jn_jump(1); perform pg_temp.jn_jump(-1);

  -- j_gist: post a gist
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.jn_state('j_gist') = 'active', 'gist active');
  perform gist_post('First gist from my first days');
  perform pg_temp.assert(pg_temp.jn_state('j_gist') = 'done', 'a gist post completes the step');

  -- j_visit: 3 different public places; home and repeats do not count
  perform pg_temp.assert(pg_temp.jn_state('j_visit') = 'active', 'visit active');
  update profiles set location_id = 'oba_market' where id = a;
  update profiles set location_id = home_location_id where id = a;
  update profiles set location_id = 'oba_market' where id = a;
  r := journey_status();
  perform pg_temp.assert((select (x->'progress'->>'have')::int = 1 from jsonb_array_elements(r->'steps') x where x->>'id' = 'j_visit'), 'home and a repeat do not count: 1 of 3');
  update profiles set location_id = 'uniben' where id = a;
  update profiles set location_id = 'bronze_bank' where id = a;
  perform pg_temp.assert(pg_temp.jn_state('j_visit') = 'done', 'three different public places complete the step');

  -- day 3
  perform pg_temp.assert(pg_temp.jn_state('j_day3') = 'locked', 'day 3 locked on day 2');
  perform pg_temp.jn_jump(1);
  perform pg_temp.jn_day(a, 0);
  r := journey_status();
  perform pg_temp.assert((r->>'day')::int = 3 and pg_temp.jn_state('j_day3') = 'done', 'the third play day unlocks day 3 and the come-back step is done');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'journey_day' and title like '%Day 3%'), 'a day-3 alert');

  -- j_skill: enrol in a course
  perform pg_temp.assert(pg_temp.jn_state('j_skill') = 'active', 'skill active');
  update profiles set cash = cash + 50000 where id = a;
  begin
    perform course_enrol('ict_basics');
  exception when others then
    raise notice 'course_enrol: %', sqlerrm;
    insert into course_enrolments (user_id, course_id) values (a, 'ict_basics') on conflict do nothing;
  end;
  perform pg_temp.assert(pg_temp.jn_state('j_skill') = 'done', 'enrolling in a course completes the step');

  -- j_bank: deposit cash at the bank
  perform pg_temp.assert(pg_temp.jn_state('j_bank') = 'active', 'bank active');
  update profiles set location_id = 'bronze_bank', cash = cash + 10000 where id = a;
  update game_config set value = '0'::jsonb where key = 'bank.min_amount';
  perform bank_deposit(1000);
  perform pg_temp.assert(pg_temp.jn_state('j_bank') = 'done', 'a bank deposit completes the step');

  -- j_dream: the phone reports the look
  perform pg_temp.assert(pg_temp.jn_state('j_dream') = 'active', 'dream active');
  perform journey_mark('dream_seen');
  perform pg_temp.assert(pg_temp.jn_state('j_dream') = 'done', 'looking at the dream completes the step');
  r := journey_status();
  perform pg_temp.assert((r->>'claimable')::int = 9, 'all nine day-2 and day-3 steps wait to be claimed: ' || (r->>'claimable'));
end $$;

-- =========================================================================================
-- 4. finishing: every step claimed -> the bonus once, the badge, the item
-- =========================================================================================
do $$
declare a uuid := pg_temp.jn_user('JN_Finish'); r jsonb; c0 bigint; s text; v_sum bigint := 0; v_bonus bigint; v_water int; v_fin int;
begin
  perform pg_temp.login(a);
  perform journey_status();
  -- fake completion of every step (rows as if each condition had been met), then claim them all for real
  update journey_progress set day_n = 3 where user_id = a;
  insert into journey_done (user_id, step_id, cash) select a, id, reward_cash from journey_steps where active on conflict do nothing;
  v_fin := coalesce((select reached from journey_step_stats where step_id = '_finished'), 0);
  c0 := pg_temp.jn_cash(a);
  foreach s in array array(select id from journey_steps where active order by day, sort, id) loop
    r := journey_claim(s);
    v_sum := v_sum + (r->>'cash')::bigint;
    if s <> 'j_dream' then perform pg_temp.assert(not (r->>'finished')::boolean, 'not finished before the last step: ' || s); end if;
  end loop;
  v_bonus := bl_cfg('journey.bonus_cash')::bigint;
  perform pg_temp.assert((r->>'finished')::boolean and (r->>'bonus')::bigint = v_bonus and r->>'badge' = 'Benin Newcomer', 'the last claim finishes the line: ' || r::text);
  perform pg_temp.assert(pg_temp.jn_cash(a) = c0 + v_sum + v_bonus, 'cash = every step + the bonus');
  perform pg_temp.assert(exists (select 1 from inventory where user_id = a and item_id = 'kada_chicken'), 'the bonus item is in the Bag');
  perform pg_temp.assert((select count(*) from ledger where user_id = a and reason = 'New player reward') = 15, '14 steps + 1 bonus in the ledger');
  perform pg_temp.assert((select completed_at is not null and badge = 'Benin Newcomer' from journey_progress where user_id = a), 'completed_at and badge saved');
  perform pg_temp.assert((journey_status()->>'complete')::boolean, 'status says complete');
  perform pg_temp.assert((select reached from journey_step_stats where step_id = '_finished') = v_fin + 1, 'the funnel counted a finish');
  perform pg_temp.assert(pg_temp.jn_hint('select journey_claim(''j_dream'')') = 'already_claimed', 'no second claim, no second bonus');
  perform pg_temp.assert(pg_temp.jn_cash(a) = c0 + v_sum + v_bonus, 'still the same cash');
end $$;

-- =========================================================================================
-- 5. eligibility: new vs old accounts, the existing-player switch
-- =========================================================================================
do $$
declare old uuid := pg_temp.jn_user('JN_Old'); low uuid := pg_temp.jn_user('JN_Low'); r jsonb;
begin
  update profiles set created_at = bl_now() - interval '30 days' where id in (old, low);
  perform pg_temp.login(old);
  r := journey_status();
  perform pg_temp.assert((r->>'enabled')::boolean and not (r->>'eligible')::boolean and r->'steps' is null, 'a 30-day-old account is not offered the journey: ' || r::text);
  perform pg_temp.assert(not exists (select 1 from journey_progress where user_id = old), 'and no row is made for it');
  perform pg_temp.assert(pg_temp.jn_hint('select journey_claim(''j_tour'')') = 'not_eligible', 'it cannot claim either');
  -- a window of 40 days offers it
  update game_config set value = '40'::jsonb where key = 'journey.max_age_days';
  perform pg_temp.assert((journey_status()->>'eligible')::boolean, 'max_age_days 40 includes a 30-day-old account');
  delete from journey_progress where user_id = old;
  update game_config set value = '7'::jsonb where key = 'journey.max_age_days';
  -- the existing-player switch: older and low-level
  perform pg_temp.login(low);
  update game_config set value = 'true'::jsonb where key = 'journey.offer_existing';
  update profiles set job_total_shifts = 3 where id = low;
  r := journey_status();
  perform pg_temp.assert((r->>'eligible')::boolean, 'offer_existing: an old low-level player is offered it');
  perform pg_temp.assert((select anchor > bl_now() - interval '1 hour' from journey_progress where user_id = low), 'and starts fresh from now');
  perform pg_temp.assert((r->>'day')::int = 1, 'at day 1');
  -- a veteran is not offered it even with the switch on
  perform pg_temp.login(old);
  update profiles set job_total_shifts = 50 where id = old;
  perform pg_temp.assert(not (journey_status()->>'eligible')::boolean, 'a veteran (50 shifts) is not offered it');
  update game_config set value = 'false'::jsonb where key = 'journey.offer_existing';
  -- someone who started keeps going when they get "too old" (the window only decides who is OFFERED it)
  perform pg_temp.login(low);
  update profiles set job_total_shifts = 40 where id = low;
  perform pg_temp.assert((journey_status()->>'eligible')::boolean, 'a started journey continues');
end $$;

-- =========================================================================================
-- 6. switch off, reward percent, evaluation throttle
-- =========================================================================================
do $$
declare a uuid := pg_temp.jn_user('JN_Switch'); r jsonb; c0 bigint;
begin
  perform pg_temp.login(a);
  perform journey_status();
  update game_config set value = 'false'::jsonb where key = 'journey.enabled';
  r := journey_status();
  perform pg_temp.assert(not (r->>'enabled')::boolean and r->'steps' is null, 'switched off: nothing is shown');
  perform pg_temp.assert(pg_temp.jn_hint('select journey_claim(''j_tour'')') = 'disabled', 'switched off: nothing can be claimed');
  update game_config set value = 'true'::jsonb where key = 'journey.enabled';

  -- reward percent 50
  update game_config set value = '50'::jsonb where key = 'journey.reward_pct';
  perform tour_done();
  c0 := pg_temp.jn_cash(a);
  r := journey_claim('j_tour');
  perform pg_temp.assert((r->>'cash')::bigint = 250 and pg_temp.jn_cash(a) = c0 + 250, 'reward_pct 50 halves the step reward: ' || r::text);
  update game_config set value = '100'::jsonb where key = 'journey.reward_pct';

  -- evaluation throttle: a re-check inside the window is skipped, a claim always checks
  update game_config set value = '1000'::jsonb where key = 'journey.eval_seconds';
  perform journey_status();
  perform bl_give_item(a, 'bottled_water', 1);
  perform item_use('bottled_water');
  perform pg_temp.assert(pg_temp.jn_state('j_eat') = 'active', 'inside the throttle window the status does not re-check');
  perform pg_temp.assert(pg_temp.jn_hint('select journey_claim(''j_eat'')') = 'ok', 'a claim re-checks at once');
  update game_config set value = '0'::jsonb where key = 'journey.eval_seconds';
end $$;

-- =========================================================================================
-- 7. admin: funnel is admin only, the Content editor works and never rewrites what is done
-- =========================================================================================
do $$
declare a uuid := pg_temp.jn_user('JN_Pl'); adm uuid := pg_temp.jn_user('JN_Adm'); r jsonb; fx jsonb;
begin
  update profiles set is_admin = true where id = adm;
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.jn_hint('select admin_journey_funnel()') = 'not_admin', 'funnel is admin only');
  perform pg_temp.assert(pg_temp.jn_hint('select admin_row_upsert(''journey_steps'', ''{"id":"j_tour","reward_cash":1}'')') = 'not_admin', 'editor is admin only');
  perform journey_status(); perform tour_done(); perform journey_status();
  perform pg_temp.login(adm);
  r := admin_journey_funnel();
  perform pg_temp.assert((r->>'started')::int >= 2 and jsonb_array_length(r->'steps') = 14, 'funnel lists started and 14 steps');
  select s into fx from jsonb_array_elements(r->'steps') s where s->>'id' = 'j_tour';
  perform pg_temp.assert((fx->>'reached')::int >= 2 and (fx->>'claimed')::int >= 1, 'the tour step was reached and claimed by several: ' || fx::text);
  -- the funnel moves once per player per step
  perform pg_temp.login(a); perform journey_status(); perform journey_status();
  perform pg_temp.login(adm);
  perform pg_temp.assert((select (s->>'reached')::int from jsonb_array_elements(admin_journey_funnel()->'steps') s where s->>'id' = 'j_tour') = (fx->>'reached')::int, 'a step counts a player once');
  -- editor
  r := admin_row_upsert('journey_steps', '{"id":"j_bank","reward_cash":1250,"title":"Save some money","hint":"Bank it.","day":3,"sort":35}');
  perform pg_temp.assert((r->'row'->>'reward_cash')::bigint = 1250 and r->'row'->>'title' = 'Save some money', 'admin edits title, hint, day, order, reward');
  perform pg_temp.assert(pg_temp.jn_hint('select admin_row_upsert(''journey_steps'', ''{"id":"j_bank","kind":"tour"}'')') = 'bad_column', 'the condition kind is not editable');
  perform pg_temp.assert(pg_temp.jn_hint('select admin_row_upsert(''journey_steps'', ''{"id":"j_new","title":"x"}'')') = 'no_insert', 'steps cannot be invented from the editor');
  perform pg_temp.assert(pg_temp.jn_hint('select admin_row_upsert(''journey_steps'', ''{"id":"j_bank","day":9}'')') = 'bad_value', 'day must be 1 to 3');
  perform pg_temp.assert(jsonb_array_length(admin_table_rows('journey_steps')) = 14, 'the editor lists the steps');
  -- a done step keeps the reward it was done with
  perform pg_temp.login(a);
  perform pg_temp.assert((select (x->'reward'->>'cash')::bigint = 1250 from jsonb_array_elements(journey_status()->'steps') x where x->>'id' = 'j_bank'), 'a new reward shows on a step that is not done');
  perform pg_temp.login(adm);
  perform admin_row_upsert('journey_steps', '{"id":"j_bank","reward_cash":1000,"title":"Save money in the bank","hint":"Go to the bank and deposit some cash. Street thieves cannot touch it there.","sort":30}');
  -- inactive steps drop out of the line
  perform admin_row_upsert('journey_steps', '{"id":"j_dream","active":false}');
  perform pg_temp.login(a);
  perform pg_temp.assert((journey_status()->>'total')::int = 13, 'an inactive step leaves the line');
  perform pg_temp.login(adm);
  perform admin_row_upsert('journey_steps', '{"id":"j_dream","active":true}');
end $$;

-- =========================================================================================
-- 8. the Day 2 / Day 3 push
-- =========================================================================================
create or replace function pg_temp.jn_push(p_uid uuid) returns void
language plpgsql as $$
begin
  perform pg_temp.login(p_uid);
  perform push_prefs_set(jsonb_build_object('master', true, 'events', true));
  insert into push_subscriptions (user_id, endpoint, p256dh, auth)
  values (p_uid, 'https://push.example.test/jn/' || p_uid, repeat('A', 87), repeat('B', 22));
end $$;

do $$
declare a uuid := pg_temp.jn_user('JN_Push'); b uuid := pg_temp.jn_user('JN_NoDevice'); today date := bl_wat_date(); r jsonb;
begin
  perform pg_temp.jn_push(a);
  perform pg_temp.login(a); perform journey_status();
  perform pg_temp.login(b); perform journey_status();
  update game_config set value = '0'::jsonb where key = 'journey.push_hour';
  update game_config set value = '24'::jsonb where key = 'return.push_to_hour';
  update game_config set value = 'true'::jsonb where key in ('push.enabled', 'push.cat_events');
  -- seen today: nothing to push yet
  r := bl_journey_tick();
  perform pg_temp.assert((r->>'pushed')::int = 0, 'a player who is here today gets no push: ' || r::text);
  -- seen yesterday on day 1: push for day 2
  update journey_progress set last_day = today - 1 where user_id in (a, b);
  r := bl_journey_tick();
  perform pg_temp.assert((r->>'pushed')::int = 1 and (r->>'looked_at')::int >= 2, 'one push (the player with a device): ' || r::text);
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'journey_day' and title like '%Day 2%' and url = '/play?go=journey') = 1, 'Day 2 of your Benin life is ready');
  perform pg_temp.assert((select pushed_day from journey_progress where user_id = b) = 2, 'a player without a device is examined once and not again');
  r := bl_journey_tick();
  perform pg_temp.assert((r->>'pushed')::int = 0, 'never twice for the same day');
  -- came back on day 2, seen yesterday again: push for day 3, then no more
  update journey_progress set day_n = 2, last_day = today - 1 where user_id = a;
  r := bl_journey_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'journey_day' and title like '%Day 3%') = 1, 'Day 3 push');
  update journey_progress set day_n = 3, last_day = today - 1 where user_id = a;
  perform pg_temp.assert((bl_journey_tick()->>'pushed')::int = 0, 'nothing after day 3: two pushes in all');
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'journey_day') = 2, 'two pushes ever');
  -- switches
  update journey_progress set day_n = 1, pushed_day = 1, last_day = today - 1 where user_id = a;
  delete from push_outbox where user_id = a;
  update game_config set value = 'false'::jsonb where key = 'journey.push_enabled';
  perform pg_temp.assert(bl_journey_tick()->>'skipped' = 'off', 'push switch off');
  update game_config set value = 'true'::jsonb where key = 'journey.push_enabled';
  update game_config set value = '23'::jsonb where key = 'journey.push_hour';
  perform pg_temp.assert(bl_journey_tick()->>'skipped' = 'hours' or (extract(hour from (bl_now() at time zone bl_clock_tz())) >= 23), 'not before the push hour');
  update game_config set value = '0'::jsonb where key = 'journey.push_hour';
  -- opted out of Game events: nothing queued
  perform pg_temp.login(a);
  perform push_prefs_set(jsonb_build_object('events', false));
  perform bl_journey_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = a and kind = 'journey_day'), 'opted out of Game events: no push');
end $$;

-- =========================================================================================
-- 9. cheap: nothing in the hooks runs for players without a journey, and old accounts leave no rows
-- =========================================================================================
do $$
declare old uuid := pg_temp.jn_user('JN_Cheap'); n int;
begin
  update profiles set created_at = bl_now() - interval '90 days' where id = old;
  perform pg_temp.login(old);
  perform bl_give_item(old, 'bottled_water', 1);
  perform item_use('bottled_water');
  update profiles set location_id = 'oba_market' where id = old;
  update profiles set location_id = 'uniben' where id = old;
  perform pg_temp.assert(not exists (select 1 from journey_progress where user_id = old), 'hooks write nothing for a player with no journey');
  perform pg_temp.assert(not exists (select 1 from journey_done where user_id = old), 'and no done rows');
end $$;
