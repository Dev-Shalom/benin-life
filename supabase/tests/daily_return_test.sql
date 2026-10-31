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

-- =========================================================================================
-- PART 2: WELCOME-BACK GIFT, LAPSED PUSHES, "SOMETHING NEEDS YOU" PUSHES
-- =========================================================================================
-- pin the clock to 10:00 Benin time (inside the push hours) and keep it there
create or replace function pg_temp.dr_pin(p_hour numeric default 10) returns void
language plpgsql as $$
declare v_tz text := bl_clock_tz(); v_t timestamptz;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  v_t := (date_trunc('day', now() at time zone v_tz) + make_interval(hours => p_hour::int)) at time zone v_tz;
  if v_t < now() then v_t := v_t + interval '1 day'; end if;
  perform set_config('bl.test_offset_seconds', floor(extract(epoch from v_t - now()))::text, true);
end $$;

create or replace function pg_temp.dr_beat(p_uid uuid) returns void   -- a heartbeat that is not skipped by the 55 s throttle
language plpgsql as $$
begin
  update profiles set last_seen = bl_now() - interval '10 minutes' where id = p_uid;
  perform pg_temp.login(p_uid);
  perform get_my_state();
end $$;

create or replace function pg_temp.dr_push(p_uid uuid, p_events boolean default true) returns void
language plpgsql as $$
begin
  perform pg_temp.login(p_uid);
  perform push_prefs_set(jsonb_build_object('master', true, 'events', p_events, 'money', true));
  insert into push_subscriptions (user_id, endpoint, p256dh, auth)
  values (p_uid, 'https://push.example.test/dr/' || p_uid, repeat('A', 87), repeat('B', 22));
end $$;

create or replace function pg_temp.dr_tick() returns jsonb
language plpgsql as $$
begin
  update return_job set last_run = '-infinity';
  return bl_return_push_tick();
end $$;

create or replace function pg_temp.dr_hint(p_sql text) returns text
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

do $$
declare g1 uuid; g2 uuid; g3 uuid; g4 uuid; g5 uuid; today date; r jsonb; c0 bigint; c1 bigint;
begin
  perform pg_temp.dr_pin(10);
  update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');
  update game_config set value = 'true' where key = 'return.gift_enabled';
  today := bl_wat_date();
  g1 := pg_temp.dr_user('DR_G1'); g2 := pg_temp.dr_user('DR_G2'); g3 := pg_temp.dr_user('DR_G3'); g4 := pg_temp.dr_user('DR_G4'); g5 := pg_temp.dr_user('DR_G5');

  -- 1. threshold + scaling + cap
  insert into player_return_state (user_id, last_day) values (g1, today - 2), (g2, today - 3), (g3, today - 8), (g4, today - 40)
  on conflict (user_id) do update set last_day = excluded.last_day;
  perform pg_temp.dr_beat(g1); perform pg_temp.dr_beat(g2); perform pg_temp.dr_beat(g3); perform pg_temp.dr_beat(g4);
  -- g5: no state row at all, last seen 5 days ago (the first heartbeat of an old player after the deploy)
  delete from player_return_state where user_id = g5;
  update profiles set last_seen = bl_now() - interval '5 days' where id = g5;
  perform pg_temp.login(g5); perform get_my_state();
  perform pg_temp.assert(not exists (select 1 from return_gifts where user_id = g1), '2 days away: no gift');
  perform pg_temp.assert((select cash from return_gifts where user_id = g2) = 5000 and (select away_days from return_gifts where user_id = g2) = 3, '3 days: base 5000');
  perform pg_temp.assert((select item_id from return_gifts where user_id = g2) = 'kada_chicken' and (select qty from return_gifts where user_id = g2) = 1, 'a food item');
  perform pg_temp.assert((select cash from return_gifts where user_id = g3) = 7500, '8 days: 5000 + 5 x 500 = 7500');
  perform pg_temp.assert((select cash from return_gifts where user_id = g4) = 10000, '40 days: capped at 10000');
  perform pg_temp.assert((select cash from return_gifts where user_id = g5) = 6000 and (select away_days from return_gifts where user_id = g5) = 5, 'first heartbeat of an old player uses last_seen: 6000');

  -- 2. status, claim, once per absence
  perform pg_temp.login(g1);
  perform pg_temp.assert((return_gift_status()->>'pending')::boolean is false, 'g1 has no gift');
  perform pg_temp.assert(pg_temp.dr_hint('select return_gift_claim()') = 'no_gift', 'g1 claim refused');
  perform pg_temp.login(g2);
  r := return_gift_status();
  perform pg_temp.assert((r->>'pending')::boolean and (r->>'cash')::int = 5000 and r->'item'->>'name' is not null and (r->>'away_days')::int = 3, 'status: ' || r::text);
  perform pg_temp.dr_beat(g2); perform pg_temp.dr_beat(g2);
  perform pg_temp.assert((select count(*) from return_gifts where user_id = g2) = 1, 'more heartbeats the same day: still one gift');
  perform pg_temp.login(g2);
  select cash into c0 from profiles where id = g2;
  r := return_gift_claim();
  select cash into c1 from profiles where id = g2;
  perform pg_temp.assert(c1 - c0 = 5000 and (r->>'cash')::int = 5000, 'paid 5000');
  perform pg_temp.assert((select qty from inventory where user_id = g2 and item_id = 'kada_chicken') = 1, 'item in the bag');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = g2 and reason = 'Welcome-back gift' and delta = 5000), 'ledger label');
  perform pg_temp.assert(pg_temp.dr_hint('select return_gift_claim()') = 'no_gift', 'second claim refused');
  perform pg_temp.assert((return_gift_status()->>'pending')::boolean is false, 'nothing pending after the claim');
  -- the same absence cannot pay twice: daily visits make no new gift
  perform pg_temp.dr_jump(1); perform pg_temp.dr_beat(g2);
  perform pg_temp.dr_jump(1); perform pg_temp.dr_beat(g2);
  perform pg_temp.assert((select count(*) from return_gifts where user_id = g2) = 1, 'daily visits make no new gift');
  -- a NEW absence (4 days) gives a new one
  perform pg_temp.dr_jump(4); perform pg_temp.dr_beat(g2);
  perform pg_temp.assert((select count(*) from return_gifts where user_id = g2) = 2 and (return_gift_status()->>'pending')::boolean, 'a new absence: a new gift');
  perform pg_temp.dr_jump(-6);

  -- 3. not earnings: no tax garnish, not an earn reason
  perform pg_temp.assert(not ('Welcome-back gift' = any (bl_earn_reasons())), 'not an earn reason');
  update game_config set value = 'true' where key = 'economy.tax_enabled';
  update profiles set tax_owed = 3000 where id = g3;
  perform pg_temp.login(g3);
  select cash into c0 from profiles where id = g3;
  perform return_gift_claim();
  select cash into c1 from profiles where id = g3;
  perform pg_temp.assert(c1 - c0 = 7500 and not exists (select 1 from ledger where user_id = g3 and reason = 'tax_income') and (select tax_owed from profiles where id = g3) = 3000,
    'tax is not taken from a gift');
  update game_config set value = 'false' where key = 'economy.tax_enabled';

  -- 4. switch off, expiry, cap setting
  update game_config set value = 'false' where key = 'return.gift_enabled';
  perform pg_temp.login(g4);
  perform pg_temp.assert((return_gift_status()->>'pending')::boolean is false, 'switch off: nothing pending');
  perform pg_temp.assert(pg_temp.dr_hint('select return_gift_claim()') = 'no_gift', 'switch off: claim refused');
  update game_config set value = 'true' where key = 'return.gift_enabled';
  perform pg_temp.assert((return_gift_status()->>'pending')::boolean, 'switched back on: pending again');
  update return_gifts set created_at = now() - interval '9 days' where user_id = g4;
  perform pg_temp.assert((return_gift_status()->>'pending')::boolean is false, 'an old unclaimed gift is dropped');
  update game_config set value = '6000' where key = 'return.gift_cash_cap';
  update player_return_state set last_day = today - 9 where user_id = g4;
  perform pg_temp.dr_beat(g4);
  perform pg_temp.assert((select cash from return_gifts where user_id = g4 order by id desc limit 1) = 6000, 'admin cap respected');
  update game_config set value = '10000' where key = 'return.gift_cash_cap';
  update game_config set value = 'false' where key = 'return.gift_enabled';
  update player_return_state set last_day = today - 6 where user_id = g1;
  perform pg_temp.dr_beat(g1);
  perform pg_temp.assert(not exists (select 1 from return_gifts where user_id = g1), 'switch off: no gift is made');
  update game_config set value = 'true' where key = 'return.gift_enabled';
  perform pg_temp.assert(not has_function_privilege('anon', 'public.return_gift_claim()', 'execute') and has_function_privilege('authenticated', 'public.return_gift_claim()', 'execute')
    and not has_function_privilege('authenticated', 'public.bl_return_push_tick()', 'execute') and not has_function_privilege('authenticated', 'public.bl_return_gift_make(uuid,date,date)', 'execute')
    and not has_table_privilege('authenticated', 'public.return_gifts', 'select') and not has_table_privilege('authenticated', 'public.return_nudges', 'insert'), 'part 2 grants');
  raise notice 'DAILY RETURN part 2a (gift) OK';
end $$;

do $$
declare a uuid; b uuid; c uuid; d uuid; e uuid; f uuid; r jsonb; i int; us uuid[] := '{}'; u uuid; tt text; rent_at timestamptz;
begin
  perform pg_temp.dr_pin(10);
  update game_config set value = 'true' where key in ('push.enabled', 'push.cat_events', 'push.cat_money', 'return.push_enabled', 'return.gap_push_enabled');
  update game_config set value = '9' where key = 'return.push_from_hour';
  update game_config set value = '20' where key = 'return.push_to_hour';
  update game_config set value = '200' where key = 'return.push_batch';
  update game_config set value = 'true' where key = 'stories.daily_enabled';

  a := pg_temp.dr_user('DR_L1'); b := pg_temp.dr_user('DR_L2'); c := pg_temp.dr_user('DR_L3'); d := pg_temp.dr_user('DR_L4');
  perform pg_temp.dr_push(a); perform pg_temp.dr_push(b);
  perform pg_temp.dr_push(c, false);            -- events category off: opted out
  -- d: no device at all
  update profiles set last_seen = bl_now() - interval '2 days 3 hours' where id in (a, b, c, d);

  -- 1. about 2 days away: one push, only for opted-in players with a device
  r := pg_temp.dr_tick();
  perform pg_temp.assert((r->>'stage1')::int >= 2, 'stage 1 sent: ' || r::text);
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'return_lapsed') = 1, 'a got one');
  perform pg_temp.assert((select count(*) from push_outbox where user_id = b and kind = 'return_lapsed') = 1, 'b got one');
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id in (c, d) and kind = 'return_lapsed'), 'opted-out and device-less players get nothing');
  perform pg_temp.assert((select title from push_outbox where user_id = a and kind = 'return_lapsed') like '%story%', 'a real thing about their life (the story)');
  perform pg_temp.assert((select count(*) from return_nudges where user_id = a) = 1, 'the nudge is remembered');
  r := pg_temp.dr_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'return_lapsed') = 1, 'ticking again does not repeat it');
  perform pg_temp.assert(bl_return_push_tick()->>'skipped' = 'throttled', 'throttled between ticks');

  -- 2. 5 days and 10 days away; never more than three
  perform pg_temp.dr_jump(3);        -- 5 days 3 hours away
  r := pg_temp.dr_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'return_lapsed') = 2, 'second push at about 5 days: ' || r::text);
  perform pg_temp.dr_jump(5);        -- 10 days 3 hours
  r := pg_temp.dr_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'return_lapsed') = 3, 'third push at about 10 days: ' || r::text);
  perform pg_temp.assert((select title from push_outbox where user_id = a and kind = 'return_lapsed' order by id desc limit 1) like '%Benin don miss you%', 'third push is Benin don miss you');
  perform pg_temp.dr_jump(1); perform pg_temp.dr_tick(); perform pg_temp.dr_jump(20); perform pg_temp.dr_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'return_lapsed') = 3, 'never more than three per absence');
  perform pg_temp.assert((select count(*) from return_nudges where user_id = a) = 3, 'three nudge rows');

  -- 3. a personal line: a baby at home, then business takings
  perform pg_temp.dr_pin(10);
  e := pg_temp.dr_user('DR_L5'); perform pg_temp.dr_push(e);
  insert into kids_children (parent_a, status, name, due_at, born_at) values (e, 'home', 'Osas', bl_now() - interval '30 days', bl_now() - interval '10 days');
  update profiles set last_seen = bl_now() - interval '2 days 2 hours' where id = e;
  r := pg_temp.dr_tick();
  select title into tt from push_outbox where user_id = e and kind = 'return_lapsed';
  perform pg_temp.assert(tt like '%Osas misses you%', 'the baby line: ' || coalesce(tt, 'none'));
  f := pg_temp.dr_user('DR_L6'); perform pg_temp.dr_push(f);
  insert into businesses (owner_id, plot_id, type_id, name, base_income, ready_at, last_collect_at, settled_at)
  values (f, 'biz_ring_road_1', 'salon', 'Mama Joy Salon', 5000, bl_now() - interval '10 days', bl_now() - interval '3 days', bl_now() - interval '3 days');
  update profiles set last_seen = bl_now() - interval '2 days 2 hours' where id = f;
  r := pg_temp.dr_tick();
  select title into tt from push_outbox where user_id = f and kind = 'return_lapsed';
  perform pg_temp.assert(tt like '%takings are waiting%', 'the shop line: ' || coalesce(tt, 'none'));

  -- 4. quiet hours and the switch
  update game_config set value = '15' where key = 'return.push_from_hour';
  perform pg_temp.assert(pg_temp.dr_tick()->>'skipped' = 'quiet hours', 'quiet at 10:00 when sending starts at 15');
  update game_config set value = '9' where key = 'return.push_from_hour';

  -- 5. batch: 12 eligible players, batch of 10
  update game_config set value = '10' where key = 'return.push_batch';
  update profiles set last_seen = bl_now() - interval '60 days' where id in (a, b, c, d, e, f);
  for i in 1..12 loop
    u := pg_temp.dr_user('DR_B' || i); perform pg_temp.dr_push(u); us := us || u;
    update profiles set last_seen = bl_now() - interval '2 days 4 hours' where id = u;
  end loop;
  r := pg_temp.dr_tick();
  perform pg_temp.assert((r->>'stage1')::int = 10, 'a batch of 10: ' || r::text);
  r := pg_temp.dr_tick();
  perform pg_temp.assert((r->>'stage1')::int >= 2, 'the rest on the next tick: ' || r::text);
  perform pg_temp.assert((select count(*) from push_outbox where kind = 'return_lapsed' and user_id = any (us)) = 12, 'all 12 got exactly one');
  update game_config set value = '200' where key = 'return.push_batch';
  update game_config set value = 'false' where key = 'return.push_enabled';
  update profiles set last_seen = bl_now() - interval '2 days 4 hours' where id = d;
  perform pg_temp.dr_push(d);
  r := pg_temp.dr_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = d and kind = 'return_lapsed'), 'switch off: no lapsed push');
  update game_config set value = 'true' where key = 'return.push_enabled';
  raise notice 'DAILY RETURN part 2b (lapsed pushes) OK';
end $$;

do $$
declare a uuid; b uuid; r jsonb; today date;
begin
  perform pg_temp.dr_pin(10);
  today := bl_wat_date();
  update game_config set value = 'true' where key in ('push.enabled', 'push.cat_money', 'return.gap_push_enabled', 'rent.enabled');
  update game_config set value = '9' where key = 'return.push_from_hour';
  update game_config set value = '20' where key = 'return.push_to_hour';
  update game_config set value = '200' where key = 'return.push_batch';
  update game_config set value = '12' where key = 'return.takings_hours';

  -- rent due tomorrow
  a := pg_temp.dr_user('DR_R1'); perform pg_temp.dr_push(a);
  update profiles set weekly_rent = 12000, rent_due_at = ((today + 1)::timestamp + interval '12 hours') at time zone bl_clock_tz(), last_seen = bl_now() - interval '1 hour' where id = a;
  r := pg_temp.dr_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'rent_due') = 1, 'rent due tomorrow: one push: ' || r::text);
  perform pg_temp.assert((select body from push_outbox where user_id = a and kind = 'rent_due') like '%12,000%', 'the amount is in it');
  r := pg_temp.dr_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'rent_due') = 1, 'not twice for the same due date');
  update profiles set rent_due_at = ((today + 3)::timestamp + interval '12 hours') at time zone bl_clock_tz() where id = a;
  delete from push_outbox where user_id = a;
  r := pg_temp.dr_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = a and kind = 'rent_due'), 'rent due in 3 days: nothing yet');

  -- business takings ready
  b := pg_temp.dr_user('DR_T1'); perform pg_temp.dr_push(b);
  insert into businesses (owner_id, plot_id, type_id, name, base_income, ready_at, last_collect_at, settled_at)
  values (b, 'biz_ring_road_2', 'salon', 'Ada Hair Studio', 5000, bl_now() - interval '10 days', bl_now() - interval '20 hours', bl_now() - interval '20 hours');
  update profiles set last_seen = bl_now() - interval '1 hour' where id = b;
  r := pg_temp.dr_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = b and kind = 'takings_ready') = 1, 'takings ready: one push: ' || r::text);
  r := pg_temp.dr_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = b and kind = 'takings_ready') = 1, 'takings: not twice for the same collect cycle');
  update businesses set last_collect_at = bl_now() - interval '2 hours' where owner_id = b;
  delete from push_outbox where user_id = b;
  r := pg_temp.dr_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = b and kind = 'takings_ready'), 'collected two hours ago: nothing');

  -- the player is in the game right now: not pinged (p_skip_active)
  update businesses set last_collect_at = bl_now() - interval '30 hours' where owner_id = b;
  update profiles set last_seen = bl_now() where id = b;
  r := pg_temp.dr_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = b and kind = 'takings_ready'), 'active players are not pinged');

  -- master switch, category switch, hourly cap
  update game_config set value = 'false' where key = 'push.cat_money';
  update profiles set last_seen = bl_now() - interval '1 hour' where id = b;
  r := pg_temp.dr_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = b and kind = 'takings_ready'), 'money category off: nothing');
  update game_config set value = 'true' where key = 'push.cat_money';
  update game_config set value = 'false' where key = 'return.gap_push_enabled';
  r := pg_temp.dr_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = b and kind = 'takings_ready'), 'gap switch off: nothing');
  update game_config set value = 'true' where key = 'return.gap_push_enabled';
  update game_config set value = '1' where key = 'push.max_per_user_hour';
  insert into push_outbox (user_id, category, kind, title, body, url, status) values (b, 'money', 'filler', 'x', 'y', '/play', 'sent');
  r := pg_temp.dr_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = b and kind = 'takings_ready'), 'the hourly cap holds');
  update game_config set value = '20' where key = 'push.max_per_user_hour';

  -- push_tick runs the job (cron path) and reports it
  r := bl_push_tick();
  perform pg_temp.assert(r ? 'return_pushed', 'bl_push_tick calls the return job');
  raise notice 'DAILY RETURN part 2c (gap pushes) OK';
end $$;

-- =========================================================================================
-- PART 3: WEEKLY EVENTS ("This week in Benin")
-- =========================================================================================
-- move the clock to the next given Benin weekday (0 = Monday) at the given hour
create or replace function pg_temp.dr_at(p_dow int, p_hour int default 10) returns void
language plpgsql as $$
declare v_tz text := bl_clock_tz(); v_local timestamp := (now() at time zone bl_clock_tz()); v_cur int; v_ahead int; v_t timestamptz;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  v_local := now() at time zone v_tz;
  v_cur := extract(isodow from v_local)::int - 1;
  v_ahead := (p_dow - v_cur + 7) % 7;
  v_t := (date_trunc('day', v_local) + make_interval(days => v_ahead, hours => p_hour)) at time zone v_tz;
  if v_t < now() then v_t := v_t + interval '7 days'; end if;
  perform set_config('bl.test_offset_seconds', floor(extract(epoch from v_t - now()))::text, true);
end $$;

create or replace function pg_temp.dr_goto(p_uid uuid, p_loc text) returns void
language sql as $$
  update profiles set location_id = p_loc, travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
                      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null, needs_updated_at = bl_now(), last_seen = bl_now()
   where id = p_uid;
$$;

do $$
declare u uuid; adm uuid; r jsonb; fun0 numeric; c0 bigint; c1 bigint; w jsonb; n0 int; p0 bigint; p1 bigint; i int; wk date; home text;
begin
  update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');
  update game_config set value = 'true' where key like 'weekly.%\_enabled' or key = 'weekly.enabled';
  perform pg_temp.dr_at(4, 10);                      -- a Friday, 10:00
  u := pg_temp.dr_user('DR_W1');
  select home_location_id into home from profiles where id = u;

  -- 1. the right event on the right day
  r := weekly_calendar();
  perform pg_temp.assert(jsonb_array_length(r->'days') = 7 and (r->>'weekday')::int = 4 and r->'today_event'->>'key' = 'fri_club', 'Friday: Club Night: ' || r::text);
  perform pg_temp.assert((r->'days'->4->>'today')::boolean and (r->'days'->0->>'past')::boolean and r->'days'->0->'event'->>'key' = 'mon_winners'
     and r->'days'->1->'event' = 'null'::jsonb and r->'days'->2->'event'->>'key' = 'wed_market' and r->'days'->5->'event'->>'key' = 'sat_owambe'
     and r->'days'->6->'event'->>'key' = 'sun_rest' and r->'days'->3->'event' = 'null'::jsonb, 'the whole week: ' || (r->'days')::text);
  perform pg_temp.assert(r->'today_event'->>'reward' like '%1,000%' and (r->'today_event'->>'checked_in')::boolean is false, 'reward text');
  for i in 0..6 loop
    perform pg_temp.dr_at(i, 10);
    r := weekly_calendar();
    perform pg_temp.assert((r->>'weekday')::int = i and coalesce(r->'today_event'->>'key', 'none') = (array['mon_winners', 'none', 'wed_market', 'none', 'fri_club', 'sat_owambe', 'sun_rest'])[i + 1],
      'weekday ' || i || ' today_event = ' || coalesce(r->'today_event'->>'key', 'none'));
  end loop;

  -- 2. Friday Club Night check-in
  perform pg_temp.dr_at(4, 22);
  perform pg_temp.login(u);
  perform pg_temp.dr_goto(u, 'ekenwan_room');
  perform pg_temp.assert(pg_temp.dr_hint('select weekly_event_checkin()') = 'not_here', 'not at a club: refused');
  perform pg_temp.dr_goto(u, 'club_360');
  update profiles set fun = 40 where id = u;
  select cash into c0 from profiles where id = u;
  r := weekly_event_checkin();
  select cash, fun into c1, fun0 from profiles where id = u;
  perform pg_temp.assert(c1 - c0 = 1000 and (r->>'cash')::int = 1000 and fun0 between 50 and 56, 'Friday reward: 1000 and fun about +15: ' || c1 || '/' || fun0);
  perform pg_temp.assert(exists (select 1 from ledger where user_id = u and reason = 'Weekly event: Friday Club Night' and delta = 1000), 'ledger label');
  perform pg_temp.assert(not ('Weekly event: Friday Club Night' = any (bl_earn_reasons())), 'not earnings');
  perform pg_temp.assert(pg_temp.dr_hint('select weekly_event_checkin()') = 'already', 'once a day');
  perform pg_temp.assert((weekly_calendar()->'today_event'->>'checked_in')::boolean, 'calendar shows it done');
  perform pg_temp.dr_jump(7); perform pg_temp.dr_goto(u, 'club_360');
  perform weekly_event_checkin();
  perform pg_temp.assert((select count(*) from weekly_event_checkins where user_id = u and event_key = 'fri_club') = 2, 'next Friday works again');
  perform pg_temp.dr_jump(-1); perform pg_temp.dr_goto(u, 'club_360');       -- Thursday
  perform pg_temp.assert(pg_temp.dr_hint('select weekly_event_checkin()') = 'no_event', 'Thursday: nothing to check in to');

  -- 3. Saturday Owambe, Sunday Rest Day
  perform pg_temp.dr_at(5, 15); perform pg_temp.dr_goto(u, 'club_360');
  perform pg_temp.assert(pg_temp.dr_hint('select weekly_event_checkin()') = 'not_here', 'owambe: not at the party place');
  perform pg_temp.dr_goto(u, 'golden_tulip');
  select cash into c0 from profiles where id = u;
  r := weekly_event_checkin();
  select cash into c1 from profiles where id = u;
  perform pg_temp.assert(c1 - c0 = 1500, 'Saturday reward 1500');
  perform pg_temp.dr_at(6, 15); perform pg_temp.dr_goto(u, 'golden_tulip');
  perform pg_temp.assert(pg_temp.dr_hint('select weekly_event_checkin()') = 'not_here', 'rest: not at home');
  perform pg_temp.dr_goto(u, home);
  update profiles set stress = 50, energy = 40 where id = u;
  perform weekly_event_checkin();
  perform pg_temp.assert((select stress from profiles where id = u) <= 31 and (select energy from profiles where id = u) >= 49, 'Sunday: less stress, more energy');
  perform pg_temp.assert((select cash from profiles where id = u) = c1, 'Sunday gives no cash');

  -- 4. Monday Winners: announced once, as a broadcast
  perform pg_temp.dr_at(0, 10);
  wk := bl_week_start() - 7;
  insert into weekly_earn_weeks (week_start, settled_at) values (wk, bl_now()) on conflict (week_start) do nothing;
  delete from weekly_earn_winners where week_start = wk;
  insert into weekly_earn_winners (week_start, rank, user_id, username, total, prize) values (wk, 1, u, 'DR_W1', 150000, 0);
  delete from weekly_event_runs where event_key = 'mon_winners';      -- the weekday loop above already visited a Monday
  select count(*) into n0 from broadcasts where title = '🏆 Monday Winners';
  r := weekly_calendar();
  perform pg_temp.assert((select count(*) from broadcasts where title = '🏆 Monday Winners') = n0 + 1, 'the announcement was made');
  perform pg_temp.assert((select body from broadcasts where title = '🏆 Monday Winners' order by id desc limit 1) like '%@DR_W1%150,000%', 'it names the winner');
  perform pg_temp.assert(r->'today_event'->'winners'->0->>'username' = 'DR_W1', 'the calendar lists the winners');
  perform weekly_calendar(); perform bl_weekly_tick();
  perform pg_temp.assert((select count(*) from broadcasts where title = '🏆 Monday Winners') = n0 + 1, 'only once a Monday');
  update game_config set value = 'false' where key = 'weekly.mon_winners_enabled';
  perform pg_temp.dr_jump(7); delete from weekly_event_runs where event_key = 'mon_winners';
  perform weekly_calendar();
  perform pg_temp.assert((select count(*) from broadcasts where title = '🏆 Monday Winners') = n0 + 1, 'switched off: no announcement');
  update game_config set value = 'true' where key = 'weekly.mon_winners_enabled';

  -- 5. Wednesday Market Day: Oba Market is cheaper (list, price function), other markets are not
  perform pg_temp.dr_at(2, 11);
  declare it items; v_wed bigint; v_wed_other bigint; v_list bigint; v_thu bigint; v_thu_other bigint; v_list_thu bigint;
  begin
    select * into it from items where id = 'boli_groundnut';
    v_wed := bl_dealer_net(it, 'oba_market'); v_wed_other := bl_dealer_net(it, 'new_benin_market');
    v_list := (select (x->>'price')::bigint from jsonb_array_elements(shop_list('oba_market')->'items') x where x->>'id' = 'boli_groundnut');
    perform pg_temp.dr_jump(1);
    v_thu := bl_dealer_net(it, 'oba_market'); v_thu_other := bl_dealer_net(it, 'new_benin_market');
    v_list_thu := (select (x->>'price')::bigint from jsonb_array_elements(shop_list('oba_market')->'items') x where x->>'id' = 'boli_groundnut');
    perform pg_temp.assert(v_wed < v_thu and v_wed >= floor(v_thu * 0.80), 'Wednesday Oba Market is cheaper: ' || v_wed || ' vs ' || v_thu);
    perform pg_temp.assert(v_wed_other = v_thu_other, 'other markets unchanged');
    perform pg_temp.assert(v_list < v_list_thu, 'the shop list shows the lower price: ' || v_list || ' vs ' || v_list_thu);
    perform pg_temp.dr_jump(-1);
    update game_config set value = 'false' where key = 'weekly.wed_market_enabled';
    perform pg_temp.assert(bl_dealer_net(it, 'oba_market') = v_thu, 'switched off: normal price');
    update game_config set value = 'true' where key = 'weekly.wed_market_enabled';
    update game_config set value = '30' where key = 'weekly.wed_market_discount_pct';
    perform pg_temp.assert(bl_dealer_net(it, 'oba_market') < v_wed, 'the discount is a setting');
    update game_config set value = '15' where key = 'weekly.wed_market_discount_pct';
    perform pg_temp.assert(weekly_calendar()->'today_event'->>'reward' like '15% off at Oba Market', 'calendar says so');
  end;

  -- 6. each event can be switched off; master off
  perform pg_temp.dr_at(4, 22); perform pg_temp.dr_goto(u, 'club_360');
  update game_config set value = 'false' where key = 'weekly.fri_club_enabled';
  perform pg_temp.assert(weekly_calendar()->'today_event' = 'null'::jsonb and pg_temp.dr_hint('select weekly_event_checkin()') = 'no_event', 'Friday switched off');
  update game_config set value = 'true' where key = 'weekly.fri_club_enabled';
  update game_config set value = 'false' where key = 'weekly.enabled';
  perform pg_temp.assert((weekly_calendar()->>'enabled')::boolean is false and pg_temp.dr_hint('select weekly_event_checkin()') = 'no_event', 'master off');
  update game_config set value = 'true' where key = 'weekly.enabled';
  raise notice 'DAILY RETURN part 3a (weekly events) OK';
end $$;

do $$
declare a uuid; b uuid; c uuid; r jsonb; n int;
begin
  update game_config set value = 'true' where key in ('push.enabled', 'push.cat_events', 'weekly.enabled', 'weekly.fri_club_enabled', 'weekly.push_enabled', 'weekly.mon_winners_enabled');
  update game_config set value = '9' where key = 'weekly.push_hour';
  update game_config set value = '20' where key = 'return.push_to_hour';
  perform pg_temp.dr_at(4, 10);                      -- Friday 10:00
  a := pg_temp.dr_user('DR_P1'); b := pg_temp.dr_user('DR_P2'); c := pg_temp.dr_user('DR_P3');
  perform pg_temp.dr_push(a); perform pg_temp.dr_push(b); perform pg_temp.dr_push(c, false);
  update profiles set last_seen = bl_now() where id in (a, b, c);

  -- morning push: before the hour nothing, then one each for opted-in players, never twice
  perform pg_temp.dr_at(4, 7);
  r := bl_weekly_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = a and kind = 'weekly_event'), '7 AM: too early');
  perform pg_temp.dr_at(4, 10);
  update profiles set last_seen = bl_now() where id in (a, b, c);
  r := bl_weekly_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'weekly_event') = 1 and (select count(*) from push_outbox where user_id = b and kind = 'weekly_event') = 1, 'one morning push each: ' || r::text);
  perform pg_temp.assert((select title from push_outbox where user_id = a and kind = 'weekly_event') like '%Friday Club Night%', 'the title names the event');
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = c and kind = 'weekly_event'), 'opted out: nothing');
  r := bl_weekly_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'weekly_event') = 1, 'not twice the same day');
  perform pg_temp.assert(exists (select 1 from weekly_event_runs where event_key = 'push:fri_club' and day = bl_wat_date()), 'finished marker (no more scanning today)');
  -- the next Friday sends again; Monday has no morning push (the announcement is the broadcast)
  perform pg_temp.dr_jump(7); update profiles set last_seen = bl_now() where id in (a, b);
  r := bl_weekly_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'weekly_event') = 2, 'next Friday: a new push');
  perform pg_temp.dr_at(0, 10); update profiles set last_seen = bl_now() where id in (a, b);
  r := bl_weekly_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'weekly_event') = 2, 'Monday: no morning push');
  -- switches
  perform pg_temp.dr_at(4, 10); perform pg_temp.dr_jump(14);
  delete from weekly_push_log; update profiles set last_seen = bl_now() where id in (a, b);
  update game_config set value = 'false' where key = 'weekly.push_enabled';
  r := bl_weekly_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = a and kind = 'weekly_event') = 2, 'push switch off');
  update game_config set value = 'true' where key = 'weekly.push_enabled';

  -- batch size
  update game_config set value = '10' where key = 'weekly.push_batch';
  delete from weekly_event_runs where event_key like 'push:%'; delete from weekly_push_log;
  update push_outbox set status = 'sent' where kind = 'weekly_event';
  declare i int; u uuid; us uuid[] := '{}'; begin
    for i in 1..12 loop u := pg_temp.dr_user('DR_PB' || i); perform pg_temp.dr_push(u); us := us || u; update profiles set last_seen = bl_now() where id = u; end loop;
    update profiles set last_seen = bl_now() - interval '30 days' where id in (a, b, c);
    r := bl_weekly_tick();
    perform pg_temp.assert((r->>'looked_at')::int = 10, 'a batch of 10: ' || r::text);
    perform pg_temp.assert(not exists (select 1 from weekly_event_runs where event_key like 'push:%'), 'not finished yet');
    r := bl_weekly_tick();
    perform pg_temp.assert((r->>'looked_at')::int = 2 and (select count(*) from push_outbox where kind = 'weekly_event' and user_id = any (us)) = 12, 'the rest next tick, 12 pushes in all: ' || r::text);
  end;

  -- grants / RLS / cron hook
  perform pg_temp.assert(not has_function_privilege('anon', 'public.weekly_calendar()', 'execute') and has_function_privilege('authenticated', 'public.weekly_event_checkin()', 'execute')
    and not has_function_privilege('authenticated', 'public.bl_weekly_tick()', 'execute') and not has_function_privilege('authenticated', 'public.bl_weekly_discount(bigint,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.bl_weekly_monday_run()', 'execute')
    and not has_table_privilege('authenticated', 'public.weekly_event_checkins', 'select') and not has_table_privilege('anon', 'public.weekly_event_runs', 'select')
    and (select bool_and(relrowsecurity) from pg_class where oid in ('public.weekly_event_checkins'::regclass, 'public.weekly_event_runs'::regclass, 'public.weekly_push_log'::regclass)), 'part 3 grants and RLS');
  perform pg_temp.assert(bl_push_tick() ? 'weekly', 'bl_push_tick calls the weekly job');
  raise notice 'DAILY RETURN part 3b (weekly push) OK';
end $$;
