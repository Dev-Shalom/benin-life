-- Daily return pack (20261108000100_growth, 20261108000200_return_gift, 20261108000300_weekly_events,
-- 20261108000400_today_card). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/daily_return_test.sql
-- Part 1 Growth: player-day recording (once a day), cohort maths, source capture, channel vs player referral, admin-only RPCs, RLS + grants.
-- Part 2 Welcome-back gift + lapsed pushes + gap pushes.   Part 3 Weekly events.   Part 4 Today card.

create or replace function pg_temp.dr_user(p_name text) returns uuid
language plpgsql as $$
declare u uuid := pg_temp.new_user(lower(p_name) || '@dr.bl');
begin
  perform pg_temp.login(u);
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  return u;
end $$;

create or replace function pg_temp.dr_jump(p_days numeric) returns void
language plpgsql as $$
begin
  perform set_config('bl.test_offset_seconds', (coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_days * 86400)::text, true);
end $$;

-- =========================================================================================
-- PART 1: GROWTH
-- =========================================================================================
do $$
declare a uuid; b uuid; c uuid; adm uuid; r jsonb; m text; t0 timestamptz; today date; row jsonb;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  today := bl_wat_date();
  a := pg_temp.dr_user('DR_One'); b := pg_temp.dr_user('DR_Two'); c := pg_temp.dr_user('DR_Three');
  adm := pg_temp.dr_user('DR_Admin'); update profiles set is_admin = true where id = adm;

  -- 1. player-day: recorded by the heartbeat, once a day, no second write
  perform set_config('bl.test_offset_seconds', '120', true);   -- create_profile just stamped last_seen: wait out the 55 s throttle
  perform pg_temp.login(a);
  perform get_my_state(); perform get_my_state(); perform get_my_state();
  perform pg_temp.assert((select count(*) from player_days where user_id = a) = 1, 'one player_days row after 3 heartbeats');
  select updated_at into t0 from player_return_state where user_id = a;
  perform bl_growth_touch(a, bl_now(), null); perform bl_growth_touch(a, bl_now() + interval '1 minute', null);
  perform pg_temp.assert((select updated_at from player_return_state where user_id = a) = t0, 'second touch the same day writes nothing');
  perform pg_temp.assert((select last_day from player_return_state where user_id = a) = today, 'last_day = today');
  perform pg_temp.dr_jump(1);
  perform get_my_state(); perform get_my_state();
  perform pg_temp.assert((select count(*) from player_days where user_id = a) = 2, 'next WAT day = second row');
  perform pg_temp.assert((select prev_day from player_return_state where user_id = a) = today, 'prev_day remembered');
  perform pg_temp.dr_jump(-1);

  -- 2. cohort maths: a and b signed up 28 days ago (before anyone else in the dev database), c yesterday
  delete from player_days where user_id in (a, b, c);
  update profiles set created_at = bl_now() - interval '28 days' where id in (a, b);
  update profiles set created_at = bl_now() - interval '1 day' where id = c;
  insert into player_days values (a, today - 28), (a, today - 27), (a, today - 21), (b, today - 28), (b, today - 27), (c, today - 1), (c, today);
  perform pg_temp.login(adm);
  r := admin_growth_overview(true);
  select x into row from jsonb_array_elements(r->'cohorts') x where (x->>'day')::date = today - 28;
  perform pg_temp.assert((row->>'size')::int = 2 and (row->>'d1')::int = 2 and (row->>'d7')::int = 1, 'cohort -28: size 2, d1 2, d7 1: ' || coalesce(row::text, 'none'));
  select x into row from jsonb_array_elements(r->'cohorts') x where (x->>'day')::date = today - 1;
  perform pg_temp.assert(row->'d1' = 'null'::jsonb and row->'d7' = 'null'::jsonb, 'yesterday cohort: d1/d7 not measurable yet: ' || row::text);
  perform pg_temp.assert(jsonb_array_length(r->'dau') = 30 and jsonb_array_length(r->'signups') = 30, '30-day series');
  perform pg_temp.assert((select (x->>'n')::int from jsonb_array_elements(r->'dau') x where (x->>'day')::date = today) >= 1, 'today active counted');
  perform pg_temp.assert((r->'totals'->>'wau')::int >= 1 and (r->'totals'->>'players')::int >= 4 and (r->>'online')::int >= 0, 'totals');

  -- 3. sources: first answer wins, junk ignored, channel link saved
  perform pg_temp.login(a);
  r := growth_source_set('tiktok', 'tiktok');
  perform pg_temp.assert(r->>'heard' = 'tiktok' and r->>'channel' = 'tiktok', 'saved');
  r := growth_source_set('x', 'whatsapp');
  perform pg_temp.assert(r->>'heard' = 'tiktok' and r->>'channel' = 'tiktok', 'first answer wins');
  perform pg_temp.login(b);
  r := growth_source_set('bogus', 'Not A Channel!');
  perform pg_temp.assert(r->>'heard' is null and r->>'channel' is null, 'junk ignored');
  r := growth_source_set('friend', null);
  perform pg_temp.assert(r->>'heard' = 'friend', 'heard friend');
  perform pg_temp.login(adm);
  r := admin_growth_overview(true);
  select x into row from jsonb_array_elements(r->'sources') x where x->>'source' = 'tiktok';
  perform pg_temp.assert((row->>'n')::int = 1 and (row->>'e1')::int = 1 and (row->>'r1')::int = 1 and (row->>'r7')::int = 1, 'tiktok source with d1 and d7: ' || coalesce(row::text, 'none'));
  select x into row from jsonb_array_elements(r->'sources') x where x->>'source' = 'friend';
  perform pg_temp.assert((row->>'n')::int = 1 and (row->>'r1')::int = 1 and (row->>'r7')::int = 0, 'friend source (heard): ' || coalesce(row::text, 'none'));
  select x into row from jsonb_array_elements(r->'sources') x where x->>'source' = 'unknown';
  perform pg_temp.assert(row is not null, 'unknown bucket exists');

  -- 4. channel links never collide with player referral codes
  perform pg_temp.login(a);
  r := referral_status();
  perform pg_temp.assert(r->>'code' is not null, 'player has a referral code');
  perform pg_temp.login(c);
  begin perform referral_claim('TIKTOK'); m := null; exception when others then m := 'refused'; end;
  perform pg_temp.assert(m = 'refused', 'a channel word is not a referral code');
  perform pg_temp.assert(not exists (select 1 from referrals where referred_id = c), 'no referral row from a channel word');
  perform referral_claim((select code from referral_codes where user_id = a));
  update profiles set created_at = bl_now() - interval '28 days' where id = c;
  delete from player_days where user_id = c; insert into player_days values (c, today - 28);
  perform pg_temp.assert(exists (select 1 from referrals where referred_id = c and referrer_id = a), 'player referral still works');
  perform pg_temp.assert(not exists (select 1 from player_sources where user_id = c), 'referral does not write a channel');
  perform pg_temp.login(adm);
  r := admin_growth_overview(true);
  select x into row from jsonb_array_elements(r->'sources') x where x->>'source' = 'friend';
  perform pg_temp.assert((row->>'n')::int = 2, 'referred player counts as friend: ' || row::text);

  -- 5. app opens: once per player per app per day
  perform pg_temp.login(a);
  perform pg_temp.assert(growth_app_open('dr_test_app') is true, 'first open counted');
  perform pg_temp.assert(growth_app_open('dr_test_app') is false, 'second open the same day not counted');
  perform pg_temp.assert(growth_app_open('Bad App!') is false, 'bad name ignored');
  perform pg_temp.login(b);
  perform growth_app_open('dr_test_app');
  perform pg_temp.assert((select players from app_day_counts where day = today and app = 'dr_test_app') = 2, 'two players counted');
  perform pg_temp.dr_jump(1);
  perform growth_app_open('dr_test_app');
  perform pg_temp.assert((select players from app_day_counts where day = today + 1 and app = 'dr_test_app') = 1, 'next day counts again');
  perform pg_temp.dr_jump(-1);
  perform pg_temp.login(adm);
  r := admin_growth_overview(true);
  select x into row from jsonb_array_elements(r->'apps') x where x->>'app' = 'dr_test_app';
  perform pg_temp.assert((row->>'today')::int = 2, 'app in the admin list');

  -- 6. cache: a second call within the window returns the saved copy
  update game_config set value = '600' where key = 'growth.cache_seconds';
  r := admin_growth_overview(true);
  insert into player_days values (c, today - 3);
  perform pg_temp.assert(admin_growth_overview(false)->>'computed_at' = r->>'computed_at', 'cached copy within the window');

  -- 7. admin only, grants, RLS
  perform pg_temp.login(a);
  begin perform admin_growth_overview(); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like 'Only admins%', 'players cannot read Growth: ' || coalesce(m, 'none'));
  perform pg_temp.assert(not has_function_privilege('anon', 'public.admin_growth_overview(boolean)', 'execute')
    and not has_function_privilege('anon', 'public.growth_source_set(text,text)', 'execute')
    and not has_function_privilege('anon', 'public.growth_app_open(text)', 'execute')
    and has_function_privilege('authenticated', 'public.growth_app_open(text)', 'execute')
    and not has_function_privilege('authenticated', 'public.bl_growth_touch(uuid,timestamptz,timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.bl_growth_compute()', 'execute'), 'function grants');
  perform pg_temp.assert((select bool_and(relrowsecurity) from pg_class where oid in ('public.player_days'::regclass, 'public.player_return_state'::regclass,
    'public.player_sources'::regclass, 'public.player_app_days'::regclass, 'public.app_day_counts'::regclass, 'public.growth_cache'::regclass)), 'RLS on');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.player_days', 'select')
    and not has_table_privilege('authenticated', 'public.player_sources', 'select')
    and not has_table_privilege('anon', 'public.app_day_counts', 'select'), 'tables closed to clients');
  raise notice 'DAILY RETURN part 1 (growth) OK';
end $$;
