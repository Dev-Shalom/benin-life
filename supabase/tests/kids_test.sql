-- Family & Love, stage 2: kids (20261027000100_family_kids.sql). Rolled back. Run (migration applied):
--   bash scripts/sql-test.sh -- supabase/tests/kids_test.sql
-- Time moves with bl.test_offset_seconds (the clock is pinned to 10:00 Benin time first, so a game day never flips by surprise).
-- Groups: 1 grants / RLS / private helpers / settings / seeds / ledger · 2 eligibility + consent + costs + pregnancy · 3 lazy birth ·
-- 4 naming (moderation, first wins) · 5 needs maths + care actions · 6 next_alert_at + the sweep (cooldown, no duplicates, push, quiet hours) ·
-- 7 admin remove · 8 invite decline / expiry / money checks, sweep-born baby, auto-name · 9 stages, sickness, relatives, reclaim, gone for good,
-- growing up + badge · 10 caps, break-up keeps co-parenting · 11 new life hand-over · 12 kill switch pause · 13 batch limit, index, 20 rows ·
-- 14 no client access to the tables.
update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');

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

create or replace function pg_temp.hours(p_h numeric) returns void language sql as $$ select pg_temp.advance(p_h * 3600) $$;

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('kd.' || p)::uuid $$;
create or replace function pg_temp.cash(p_uid uuid) returns bigint language sql as $$ select cash + bank from profiles where id = p_uid $$;
create or replace function pg_temp.ev(p_uid uuid, p_kind text) returns bigint language sql as $$ select count(*) from events where user_id = p_uid and kind = p_kind $$;
create or replace function pg_temp.login_as(p text) returns void language sql as $$ select pg_temp.login(pg_temp.u(p)) $$;
create or replace function pg_temp.ledger_n(p_uid uuid, p_reason text) returns bigint language sql as $$ select count(*) from ledger where user_id = p_uid and reason = p_reason $$;
create or replace function pg_temp.ledger_sum(p_uid uuid, p_reason text) returns bigint language sql as $$ select coalesce(sum(delta), 0) from ledger where user_id = p_uid and reason = p_reason $$;

create or replace function pg_temp.at(p_uid uuid, p_loc text) returns void
language sql as $$
  update profiles set location_id = p_loc, travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
                      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = bl_now(), rent_due_at = null
   where id = p_uid;
$$;

create or replace function pg_temp.mk(p_name text, p_age interval default interval '30 days') returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@kd.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, protected_until = null, created_at = bl_now() - p_age, cash = 1000000, bank = 0, home_location_id = 'uselu_selfcon',
         energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0 where id = v;
  perform pg_temp.at(v, 'third_east');
  return v;
end $$;

-- A couple (status couple, together for p_days days), without going through flirts.
create or replace function pg_temp.couple(p_a uuid, p_b uuid, p_days numeric default 5) returns bigint
language plpgsql as $$
declare v bigint;
begin
  insert into love_relationships (user_a, user_b, asked_by, status, level, started_at, couple_at, last_activity_at)
  values (least(p_a, p_b), greatest(p_a, p_b), p_a, 'couple', 50, bl_now() - make_interval(secs => (p_days * 86400 + 60)::double precision),
          bl_now() - make_interval(secs => (p_days * 86400)::double precision), bl_now()) returning id into v;
  return v;
end $$;

create or replace function pg_temp.rel(p_a uuid, p_b uuid) returns bigint language sql as $$
  select id from love_relationships where user_a = least(p_a, p_b) and user_b = greatest(p_a, p_b) order by id desc limit 1 $$;

-- A child at home, set up directly (full needs now, born p_age ago, cared for now). Returns its id.
create or replace function pg_temp.mkchild(p_a uuid, p_b uuid, p_age interval default interval '1 hour', p_name text default 'Testy') returns bigint
language plpgsql as $$
declare v bigint; c kids_children;
begin
  insert into kids_children (rel_id, parent_a, parent_b, proposed_by, status, name, gender, conceived_at, due_at, born_at,
                             hunger, hunger_at, sleep, sleep_at, fun, fun_at, health, health_at, love, love_at, last_care_at)
  values (pg_temp.rel(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), p_a, 'home', p_name, 'girl', bl_now() - p_age - interval '3 days', bl_now() - p_age, bl_now() - p_age,
          100, bl_now(), 100, bl_now(), 100, bl_now(), 100, bl_now(), 100, bl_now(), bl_now()) returning id into v;
  select * into c from kids_children where id = v;
  update kids_children set next_alert_at = bl_kids_next(c) where id = v;
  return v;
end $$;

create or replace function pg_temp.kid(p_id bigint) returns kids_children language sql as $$ select * from kids_children where id = p_id $$;

-- the child json for a player from kids_status
create or replace function pg_temp.cj(p_child bigint) returns jsonb language sql as $$
  select x from jsonb_array_elements(kids_status() -> 'children') x where (x ->> 'id')::bigint = p_child $$;

create or replace function pg_temp.sub(p_user uuid) returns void
language plpgsql as $$
begin
  insert into push_subscriptions (user_id, endpoint, p256dh, auth)
  values (p_user, 'https://push.example.test/' || p_user || '/1', repeat('A', 87), repeat('B', 22));
end $$;

-- ---------- setup ----------
do $$
declare
  v_keys text[] := array['adm', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'x', 'h'];
  k text; u uuid;
  v_local timestamp := now() at time zone bl_clock_tz();
  v_target timestamp;
begin
  v_target := date_trunc('day', v_local) + case when v_local::time >= time '10:00' then interval '34 hours' else interval '10 hours' end;
  perform set_config('bl.test_offset_seconds', extract(epoch from (v_target - v_local))::text, true);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  foreach k in array v_keys loop
    u := pg_temp.mk('KD_' || k);
    perform set_config('kd.' || k, u::text, true);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
  -- a and b are a couple of 5 days; c and d too
  perform pg_temp.couple(pg_temp.u('a'), pg_temp.u('b'), 5);
  perform pg_temp.couple(pg_temp.u('c'), pg_temp.u('d'), 5);
  -- devices so pushes can be queued (push prefs default: master + friends on once there is a device)
  perform pg_temp.sub(pg_temp.u('a')); perform pg_temp.sub(pg_temp.u('b'));
  perform pg_temp.login_as('a'); perform push_prefs_set('{"master": true, "friends": true}');
  perform pg_temp.login_as('b'); perform push_prefs_set('{"master": true, "friends": true}');
  update game_config set value = '1000' where key = 'push.max_per_user_hour';
end $$;

-- ---------- 1. grants / RLS / private helpers / settings / seeds / ledger ----------
do $$
declare v text; n int;
begin
  foreach v in array array['kids_status()', 'kids_try(bigint)', 'kids_accept(bigint,boolean)', 'kids_withdraw(bigint)', 'kids_name(bigint,text,text)',
                           'kids_care(bigint,text)', 'kids_reclaim(bigint)', 'admin_kids_overview()', 'admin_kids_remove(bigint,text)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || v, 'execute'), 'anon cannot run ' || v);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || v, 'execute'), 'authenticated can run ' || v);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v)::regprocedure), v || ' is security definer');
  end loop;
  select string_agg(p.proname, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and (p.proname like 'kids\_%' or p.proname like 'admin\_kids\_%')
     and (not p.prosecdef or not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%'));
  perform pg_temp.assert(v is null, 'kids RPCs are security definer with a search_path: ' || coalesce(v, ''));
  select string_agg(p.proname, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like 'bl\_kids\_%'
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'));
  perform pg_temp.assert(v is null, 'every bl_kids_* helper is private: ' || coalesce(v, ''));
  perform pg_temp.assert(has_function_privilege('service_role', 'public.bl_kids_alert_sweep()', 'execute'), 'the sweep can be called by the service role');
  select string_agg(t, ', ') into v from unnest(array['kids_stages', 'kids_auto_names', 'kids_children', 'kids_invites', 'kids_care_log', 'kids_pause']) t
   where not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass)
      or has_table_privilege('authenticated', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'select')
      or has_table_privilege('authenticated', 'public.' || t, 'insert') or has_table_privilege('authenticated', 'public.' || t, 'update')
      or has_table_privilege('authenticated', 'public.' || t, 'delete');
  perform pg_temp.assert(v is null, 'kids tables: RLS on, no grants: ' || coalesce(v, ''));
  select count(*) into n from game_config where key like 'kids.%' and category = 'kids' and label <> '' and description <> '';
  perform pg_temp.assert(n = 39 and n = (select count(*) from game_config where key like 'kids.%'), 'every kids setting has a label and description (' || n || ')');
  perform pg_temp.assert(bl_cfg_bool('kids.enabled') and bl_cfg('kids.min_couple_days') = 2 and bl_cfg('kids.max_children_per_couple') = 3 and bl_cfg('kids.max_children_per_player') = 5
                         and bl_cfg('kids.invite_expire_hours') = 24 and bl_cfg('kids.try_cost_each') = 5000 and bl_cfg('kids.pregnancy_days') = 3 and bl_cfg('kids.name_grace_hours') = 24
                         and bl_cfg('kids.grow_days') = 21 and bl_cfg('kids.alert_below') = 30 and bl_cfg('kids.alert_cooldown_hours') = 3 and bl_cfg('kids.sweep_batch') = 200
                         and bl_cfg('kids.neglect_hours') = 24 and bl_cfg('kids.removal_days') = 7, 'defaults');
  perform pg_temp.assert((select count(*) from kids_stages where active) = 4 and (select min(from_days) from kids_stages) = 0
                         and (select array_agg(from_days order by from_days) from kids_stages) = array[0, 3, 8, 14], 'stages: Baby 0, Toddler 3, Child 8, Teen 14');
  perform pg_temp.assert((select rate_hunger from kids_stages where id = 'baby') > (select rate_hunger from kids_stages where id = 'teen'), 'a baby loses hunger faster than a teen');
  perform pg_temp.assert((select count(*) from kids_auto_names where active) >= 20 and not exists (select 1 from kids_auto_names where bl_chat_mask(name) <> name), 'auto names: enough and clean');
  perform pg_temp.assert(pg_temp.hint_of($q$insert into kids_auto_names (name) values ('Ab1')$q$) <> 'ok', 'an auto name must be letters only');
  perform pg_temp.assert(not ('kid_try' = any (bl_earn_reasons())) and not ('kid_care' = any (bl_earn_reasons())) and not ('kid_reclaim' = any (bl_earn_reasons())), 'kid ledger reasons are not earned');
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,hustle,kid_try,kid_care,kid_reclaim"');
  perform pg_temp.assert(not ('kid_try' = any (bl_earn_reasons())) and not ('kid_care' = any (bl_earn_reasons())) and not ('kid_reclaim' = any (bl_earn_reasons())), 'not earned even if an admin lists them');
  perform pg_temp.assert(bl_econ_category('kid_try') <> 'Other' and bl_econ_category('kid_care') <> 'Other' and bl_econ_category('kid_reclaim') <> 'Other', 'Admin economy categories');
  perform pg_temp.assert(bl_ledger_label('kid_try', '{}') = 'Baby plans' and bl_ledger_label('kid_care', '{"label":"Feeding Ada"}') = 'Feeding Ada' and bl_ledger_label('kid_reclaim', '{}') <> 'kid_reclaim', 'ledger labels');
  perform pg_temp.assert(bl_ledger_label('love_date', '{}') = 'Date' and bl_econ_category('love_flirt') <> 'Other' and 'love_flirt' <> all (bl_earn_reasons()), 'stage 1 love reasons still work');
  perform pg_temp.assert(bl_admin_table_spec('kids_stages')->'cols'->>'rate_hunger' = 'num' and bl_admin_table_spec('kids_auto_names')->'pk'->>0 = 'name' and bl_admin_table_spec('love_flirts') is not null, 'Content editors exist');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(get_public_profile(pg_temp.u('a')) ? 'proud_parent' and get_public_profile(pg_temp.u('a')) ? 'relationship', 'public profile has proud_parent next to the relationship');
  perform pg_temp.assert(bl_push_tick() ? 'kids_swept', 'the push tick runs the kids sweep');
  raise notice 'ok 1: grants, RLS, settings, seeds, ledger';
end $$;

-- ---------- 2. eligibility, consent, costs, pregnancy (couple a+b) ----------
do $$
declare v jsonb; v_inv bigint; v_rel bigint := pg_temp.rel(pg_temp.u('a'), pg_temp.u('b')); v_ca bigint; v_cb bigint; c kids_children;
begin
  -- not a couple: nobody linked / only talking
  perform pg_temp.login_as('h');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'no_relationship', 'no partner, no baby');
  insert into love_relationships (user_a, user_b, asked_by, status, level, started_at, last_activity_at)
  values (least(pg_temp.u('e'), pg_temp.u('f')), greatest(pg_temp.u('e'), pg_temp.u('f')), pg_temp.u('e'), 'talking', 10, bl_now(), bl_now());
  perform pg_temp.login_as('e');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'not_couple', 'talking is not enough');
  delete from love_relationships where status = 'talking' and user_a in (pg_temp.u('e'), pg_temp.u('f')) and user_b in (pg_temp.u('e'), pg_temp.u('f'));
  -- too soon
  update love_relationships set couple_at = bl_now() - interval '1 day' where id = v_rel;
  perform pg_temp.login_as('a');
  v := kids_status();
  perform pg_temp.assert((v->'couples'->0->>'can_try')::boolean = false and v->'couples'->0->'why'->>'code' = 'too_soon' and (v->'couples'->0->>'couple_days')::int = 1, 'status: too soon, 1 day so far: ' || v::text);
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'too_soon', 'a couple of 1 day cannot try yet (min 2)');
  update love_relationships set couple_at = bl_now() - interval '5 days' where id = v_rel;
  -- kill switches
  perform pg_temp.cfg('love.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'off', 'love off: no new babies');
  perform pg_temp.cfg('love.enabled', 'true');
  perform pg_temp.cfg('kids.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'off' and (kids_status()->>'enabled')::boolean = false, 'kids off: no new babies, status says off');
  perform pg_temp.cfg('kids.enabled', 'true');
  perform pg_temp.assert((kids_status()->'couples'->0->>'can_try')::boolean, 'eligible now');
  -- cannot afford it
  update profiles set cash = 100, bank = 0 where id = pg_temp.u('a');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'not_enough_money', 'the proposer needs the money');
  update profiles set cash = 1000000 where id = pg_temp.u('a');
  -- propose
  v := kids_try();
  v_inv := (v->>'invite_id')::bigint;
  perform pg_temp.assert(v_inv is not null and pg_temp.cash(pg_temp.u('a')) = 1000000, 'invite sent, nothing charged yet: ' || v::text);
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('b'), 'kids_invite') = 1, 'b is told');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'already_asked', 'one invite at a time');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_accept(%s)', v_inv)) = 'no_invite', 'the asker cannot accept their own invite');
  v := kids_status();
  perform pg_temp.assert(v->'outgoing'->0->>'state' = 'pending', 'a sees the outgoing invite');
  perform pg_temp.login_as('b');
  v := kids_status();
  perform pg_temp.assert(jsonb_array_length(v->'incoming') = 1 and v->'incoming'->0->'from'->>'username' = 'KD_a', 'b sees the incoming invite');
  perform pg_temp.login_as('c');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_accept(%s)', v_inv)) = 'no_invite', 'a stranger cannot answer');
  -- accept: both pay, pregnancy starts
  perform pg_temp.login_as('b');
  v := kids_accept(v_inv, true);
  perform pg_temp.assert((v->>'accepted')::boolean and (v->>'child')::bigint is not null, 'accepted: ' || v::text);
  v_ca := (v->>'child')::bigint;
  perform set_config('kd.ab_child', v_ca::text, true);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 995000 and pg_temp.cash(pg_temp.u('b')) = 995000, 'each pays 5000');
  perform pg_temp.assert(pg_temp.ledger_n(pg_temp.u('a'), 'kid_try') = 1 and pg_temp.ledger_sum(pg_temp.u('a'), 'kid_try') = -5000 and pg_temp.ledger_sum(pg_temp.u('b'), 'kid_try') = -5000, 'ledger kid_try x2, both sinks');
  select * into c from kids_children where id = v_ca;
  perform pg_temp.assert(c.status = 'expecting' and c.due_at between bl_now() + interval '3 days' - interval '5 seconds' and bl_now() + interval '3 days' + interval '5 seconds'
                         and c.next_alert_at = c.due_at, 'pregnancy: due in 3 days, the sweep will look at the due time');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_expecting') = 1, 'a is told they are expecting');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_accept(%s)', v_inv)) = 'answered', 'cannot answer twice');
  -- both see the countdown
  v := pg_temp.cj(v_ca);
  perform pg_temp.assert(v->>'status' = 'expecting' and v->'partner'->>'username' = 'KD_a' and (v->>'due_at')::timestamptz = c.due_at, 'b sees the countdown: ' || v::text);
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.cj(v_ca)->>'status' = 'expecting', 'a sees it too');
  -- no second pregnancy
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'expecting', 'no double pregnancy');
  perform pg_temp.assert((kids_status()->'couples'->0->>'can_try')::boolean = false, 'status: cannot try while expecting');
  -- care while expecting is refused, and nobody can name an unborn baby
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_ca, 'feed')) = 'not_home', 'no care before the birth');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_ca, 'Osaze', 'boy')) = 'not_born', 'no name before the birth');
  raise notice 'ok 2: eligibility, consent, costs, pregnancy';
end $$;

-- ---------- 3. lazy birth ----------
do $$
declare v_ca bigint := current_setting('kd.ab_child')::bigint; v jsonb; c kids_children;
begin
  perform pg_temp.hours(48);
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.cj(v_ca)->>'status' = 'expecting', 'still expecting after 2 days');
  perform pg_temp.hours(24 + 0.02);
  v := pg_temp.cj(v_ca);   -- the first read after the due time gives birth
  perform pg_temp.assert(v->>'status' = 'home' and v->>'name' is null and v->'stage'->>'id' = 'baby' and (v->>'age_days')::int = 0, 'born on the first read: ' || v::text);
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_born') = 1 and pg_temp.ev(pg_temp.u('b'), 'kids_born') = 1, 'both parents get the alert');
  perform pg_temp.assert((select title from events where user_id = pg_temp.u('a') and kind = 'kids_born') like 'Your baby is here!%', 'alert text');
  perform pg_temp.assert(exists (select 1 from push_outbox where user_id = pg_temp.u('b') and kind = 'kids_born'), 'and a push (friends category)');
  perform pg_temp.login_as('b');
  v := pg_temp.cj(v_ca);
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('b'), 'kids_born') = 1, 'no second birth alert');
  select * into c from kids_children where id = v_ca;
  perform pg_temp.assert(c.hunger = 80 and c.sleep = 80 and c.fun = 80 and c.health = 80 and c.love = 80 and c.born_at = bl_now(), 'needs start at 80');
  perform pg_temp.assert(c.next_alert_at between c.born_at + interval '16 hours 40 minutes' - interval '10 seconds' and c.born_at + interval '16 hours 40 minutes' + interval '10 seconds',
                         'next_alert_at = the hunger crossing (80 -> 30 at 3 a hour is 16h40): ' || c.next_alert_at::text || ' vs born ' || c.born_at::text);
  raise notice 'ok 3: lazy birth';
end $$;

-- ---------- 4. naming ----------
do $$
declare v_ca bigint := current_setting('kd.ab_child')::bigint; v jsonb;
begin
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_ca, 'Ab', 'boy')) = 'bad_name', 'too short');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_ca, 'Abcdefghijklmnopq', 'boy')) = 'bad_name', 'too long (17)');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_ca, 'Ola2', 'boy')) = 'bad_name', 'no digits');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_ca, 'Ola Ola', 'boy')) = 'bad_name', 'no spaces');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_ca, 'Osaze', 'robot')) = 'bad_gender', 'Boy or Girl only');
  insert into chat_banned_words (word, active) values ('zorbo', true) on conflict do nothing;
  update chat_banned_words set active = true where word = 'zorbo';
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_ca, 'Zorbo', 'boy')) = 'blocked_text', 'a banned word is refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_ca, 'ZORBO', 'boy')) = 'blocked_text', 'in any case');
  perform pg_temp.assert((select name from kids_children where id = v_ca) is null, 'still no name');
  perform pg_temp.login_as('h');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_ca, 'Osaze', 'boy')) = 'not_parent', 'only a parent can name');
  perform pg_temp.login_as('a');
  v := kids_name(v_ca, '  osAZE ', 'Boy');
  perform pg_temp.assert(v->>'name' = 'Osaze', 'name is tidied: ' || v::text);
  perform pg_temp.assert((select gender from kids_children where id = v_ca) = 'boy' and (select named_by from kids_children where id = v_ca) = pg_temp.u('a'), 'gender and who named it');
  perform pg_temp.login_as('b');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_ca, 'Ehi', 'girl')) = 'already_named', 'the first parent to name wins');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('b'), 'kids_named') = 1, 'the other parent is told');
  perform pg_temp.assert(pg_temp.cj(v_ca)->>'name' = 'Osaze' and (pg_temp.cj(v_ca)->>'named_by_me')::boolean = false, 'b sees the name');
  raise notice 'ok 4: naming';
end $$;

-- ---------- 5. needs maths + care actions ----------
do $$
declare v_ca bigint := current_setting('kd.ab_child')::bigint; v jsonb; n jsonb; b0 bigint; b1 bigint; c kids_children; v_born timestamptz;
begin
  select born_at into v_born from kids_children where id = v_ca;
  perform pg_temp.hours(6);
  perform pg_temp.login_as('a');
  n := pg_temp.cj(v_ca)->'needs';
  perform pg_temp.assert((n->>'hunger')::int = 62 and (n->>'sleep')::int = 68 and (n->>'fun')::int = 71 and (n->>'health')::int = 77 and (n->>'love')::int = 68,
                         'baby needs after 6 h (3, 2, 1.5, 0.5, 2 an hour): ' || n::text);
  perform pg_temp.assert((select hunger from kids_children where id = v_ca) = 80, 'nothing was written: the value is computed');
  -- feeding: costs money (sink), restores, cooldown
  b0 := pg_temp.cash(pg_temp.u('a'));
  v := kids_care(v_ca, 'feed');
  perform pg_temp.assert((v->>'spent')::int = 400 and (v->>'value')::int = 100 and pg_temp.cash(pg_temp.u('a')) = b0 - 400, 'feed: 400, hunger back to 100: ' || v::text);
  perform pg_temp.assert(pg_temp.ledger_n(pg_temp.u('a'), 'kid_care') = 1 and pg_temp.ledger_sum(pg_temp.u('a'), 'kid_care') = -400, 'ledger kid_care');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_ca, 'feed')) = 'cooldown', 'feeding has a short cooldown');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = b0 - 400, 'a refused action costs nothing');
  -- free actions: no money, per-child cooldown shared by both parents
  b0 := pg_temp.cash(pg_temp.u('a'));
  v := kids_care(v_ca, 'sleep');
  perform pg_temp.assert((v->>'spent')::int = 0 and (v->>'value')::int = 100 and pg_temp.cash(pg_temp.u('a')) = b0, 'sleep is free (68 + 50 = 100)');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_ca, 'sleep')) = 'cooldown', 'sleep: cooldown for me');
  perform pg_temp.login_as('b');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_ca, 'sleep')) = 'cooldown', 'and for the other parent (per child)');
  v := kids_care(v_ca, 'play');
  perform pg_temp.assert((v->>'value')::int = 100 and (v->>'spent')::int = 0, 'either parent can care: b plays (71 + 40, capped at 100)');
  v := kids_care(v_ca, 'cuddle');
  perform pg_temp.assert((v->>'value')::int = 100, 'b cuddles (68 + 40 = 108 capped)');
  perform pg_temp.assert(pg_temp.ledger_n(pg_temp.u('b'), 'kid_care') = 0, 'free actions leave no ledger row');
  -- medicine only when needed
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_ca, 'medicine')) = 'not_needed', 'medicine refused: health 77 is fine');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_ca, 'dance')) = 'bad_action', 'unknown action');
  perform pg_temp.login_as('h');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_ca, 'feed')) = 'not_parent', 'a stranger cannot care');
  -- the care log shows who did what
  perform pg_temp.login_as('a');
  v := pg_temp.cj(v_ca);
  perform pg_temp.assert(jsonb_array_length(v->'log') = 4 and v->'log'->0->>'action' = 'cuddle' and v->'log'->0->>'who' = 'KD_b' and (v->'log'->3->>'mine')::boolean, 'care log: ' || (v->'log')::text);
  perform pg_temp.assert((v->'actions'->'feed'->>'ok')::boolean = false and v->'actions'->'feed'->>'code' in ('cooldown', 'not_needed'), 'the app gets the reason as well');
  -- either parent resets the "nobody cared" clock
  perform pg_temp.assert((select last_care_at from kids_children where id = v_ca) = bl_now(), 'last_care_at moves with any care');
  -- poor parent: feeding needs money
  perform pg_temp.hours(8);
  update profiles set cash = 100, bank = 0 where id = pg_temp.u('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_ca, 'feed')) = 'not_enough_money', 'not enough money to feed');
  update profiles set cash = 1000000 where id = pg_temp.u('a');
  -- the stage maths adds the stage rates across a boundary: health 100 at the birth, baby 0.5/h for 72 h then toddler 0.4/h for 24 h = 45.6
  update kids_children set health = 100, health_at = born_at where id = v_ca;
  update kids_children set born_at = bl_now() - interval '96 hours' where id = v_ca;
  update kids_children set health_at = born_at where id = v_ca;
  select * into c from kids_children where id = v_ca;
  perform pg_temp.assert(round(bl_kids_val(c, 'health', bl_now()), 1) = 54.4, 'health over two stages: ' || bl_kids_val(c, 'health', bl_now())::text);
  perform pg_temp.assert(pg_temp.cj(v_ca)->'stage'->>'id' = 'toddler' and (pg_temp.cj(v_ca)->>'age_days')::int = 4, 'age 4 days is a toddler');
  -- crossing time is on the same maths: 100 -> under 30 needs 70 points: 36 in the baby stage, 34 left at 0.4 = 85 h into the toddler stage
  perform pg_temp.assert(abs(extract(epoch from (bl_kids_cross(c, 'health', 30) - (c.born_at + interval '72 hours' + interval '85 hours' + interval '1 second')))) < 5, 'cross over two stages');
  perform pg_temp.assert(bl_kids_val(c, 'health', c.born_at) = 100 and bl_kids_val(c, 'health', c.born_at - interval '1 hour') = 100, 'never above the stored value');
  update kids_children set born_at = (select born_at from kids_children where id = v_ca) where id = v_ca;
  raise notice 'ok 5: needs maths and care';
end $$;

-- ---------- 6. next_alert_at + the sweep ----------
do $$
declare v_ca bigint; v jsonb; c kids_children; v_n int; v_t timestamptz; v_born timestamptz;
begin
  -- a clean child for the alert tests (a+b)
  perform pg_temp.login_as('a');
  v_ca := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '0 seconds', 'Eghosa');
  perform set_config('kd.alert_child', v_ca::text, true);
  select * into c from kids_children where id = v_ca;
  v_born := c.born_at;
  -- the old ab child must not interfere: retire it
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = current_setting('kd.ab_child')::bigint;
  perform pg_temp.assert(c.next_alert_at between v_born + interval '23 hours 20 minutes' - interval '10 seconds' and v_born + interval '23 hours 20 minutes' + interval '10 seconds',
                         'full needs: first crossing is hunger, (100-30)/3 h = 23h20: ' || c.next_alert_at::text);
  -- feeding moves it; sleep falls from 100 at 2/h: crossing at 35 h, hunger refed at 4h: 4h + 23h20
  perform pg_temp.hours(4);
  update kids_children set hunger = 40, hunger_at = bl_now() where id = v_ca;
  perform kids_care(v_ca, 'feed');
  select * into c from kids_children where id = v_ca;
  perform pg_temp.assert(c.hunger = 90 and c.next_alert_at between v_born + interval '24 hours' - interval '10 seconds' and v_born + interval '24 hours' + interval '10 seconds',
                         'after a feed (40 + 50 = 90) next_alert_at is recomputed from the new value: ' || c.next_alert_at::text);
  -- nothing is due: the sweep does nothing
  select bl_kids_alert_sweep() into v_n;
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_needs') = 0, 'nothing due yet: no alert');
  -- go to just after the crossing
  perform pg_temp.advance(extract(epoch from (c.next_alert_at - bl_now())) + 2);
  perform pg_temp.assert(array_length(bl_kids_needy(pg_temp.kid(v_ca)), 1) >= 1, 'a need is under 30 now: ' || bl_kids_needy(pg_temp.kid(v_ca))::text);
  perform pg_temp.assert(pg_temp.cj(v_ca) is not null and jsonb_array_length(pg_temp.cj(v_ca)->'needy') >= 1 and (kids_status()->>'attention')::int >= 1, 'the app says needs you, attention count >= 1');
  v_n := bl_kids_alert_sweep();
  perform pg_temp.assert(v_n >= 1, 'the sweep took the child: ' || v_n);
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_needs') = 1 and pg_temp.ev(pg_temp.u('b'), 'kids_needs') = 1, 'both parents get one alert');
  perform pg_temp.assert((select title from events where user_id = pg_temp.u('b') and kind = 'kids_needs') like '🍼 Eghosa needs attention: %'
                         and (select body from events where user_id = pg_temp.u('b') and kind = 'kids_needs') = 'Go and take care of them.', 'alert wording');
  perform pg_temp.assert((select count(*) from push_outbox where kind = 'kids_needs' and user_id in (pg_temp.u('a'), pg_temp.u('b'))) = 2, 'a push for each parent');
  perform pg_temp.assert((select category from push_outbox where kind = 'kids_needs' limit 1) = 'friends' and (select url from push_outbox where kind = 'kids_needs' limit 1) = '/play?go=family:family', 'push category and link');
  select * into c from kids_children where id = v_ca;
  perform pg_temp.assert(c.alerts_unanswered = 1 and c.last_alert_at = bl_now() and c.next_alert_at >= bl_now() + interval '3 hours' - interval '5 seconds', 'next alert at least 3 hours later: ' || c.next_alert_at::text);
  -- no duplicates, cooldown holds
  perform bl_kids_alert_sweep();
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_needs') = 1, 'no duplicate alert');
  perform pg_temp.hours(2);
  perform bl_kids_alert_sweep();
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_needs') = 1, 'inside the 3 hour cooldown: nothing');
  perform pg_temp.hours(1.05);
  perform bl_kids_alert_sweep();
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_needs') = 2 and pg_temp.ev(pg_temp.u('b'), 'kids_needs') = 2, 'after the cooldown, still unattended: alert again');
  -- it goes quiet after kids.max_alerts_unanswered, until somebody cares
  perform pg_temp.cfg('kids.max_alerts_unanswered', '2');
  perform pg_temp.hours(4);
  perform bl_kids_alert_sweep();
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_needs') = 2, 'no third alert at the limit of 2');
  perform pg_temp.assert((select next_alert_at from kids_children where id = v_ca) > bl_now(), 'and it is not stuck as due');
  perform pg_temp.cfg('kids.max_alerts_unanswered', '4');
  update kids_children set hunger = 20, hunger_at = bl_now() where id = v_ca;
  perform kids_care(v_ca, 'cuddle');
  perform pg_temp.assert((select alerts_unanswered from kids_children where id = v_ca) = 0, 'a care action starts the count again');
  -- the push tick runs the sweep (the scheduler the push pipeline already has)
  update kids_children set last_alert_at = null where id = v_ca;
  update kids_children set next_alert_at = bl_now() - interval '1 minute' where id = v_ca;
  delete from events where user_id = pg_temp.u('a') and kind = 'kids_needs';
  v := bl_push_tick();
  perform pg_temp.assert((v->>'kids_swept')::int >= 1 and pg_temp.ev(pg_temp.u('a'), 'kids_needs') = 1, 'bl_push_tick runs the sweep: ' || v::text);
  -- quiet hours: an alert due inside the quiet period waits for its end
  perform pg_temp.cfg('kids.quiet_enabled', 'true');
  perform pg_temp.cfg('kids.quiet_from_hour', '22');
  perform pg_temp.cfg('kids.quiet_to_hour', '6');
  perform pg_temp.assert(bl_kids_quiet_shift((date_trunc('day', now() at time zone bl_clock_tz()) + interval '1 day 23 hours') at time zone bl_clock_tz())
                         = (date_trunc('day', now() at time zone bl_clock_tz()) + interval '2 days 6 hours') at time zone bl_clock_tz(), '23:00 waits for 06:00 next day');
  perform pg_temp.assert(bl_kids_quiet_shift((date_trunc('day', now() at time zone bl_clock_tz()) + interval '1 day 2 hours') at time zone bl_clock_tz())
                         = (date_trunc('day', now() at time zone bl_clock_tz()) + interval '1 day 6 hours') at time zone bl_clock_tz(), '02:00 waits for 06:00 the same day');
  perform pg_temp.assert(bl_kids_quiet_shift((date_trunc('day', now() at time zone bl_clock_tz()) + interval '1 day 12 hours') at time zone bl_clock_tz())
                         = (date_trunc('day', now() at time zone bl_clock_tz()) + interval '1 day 12 hours') at time zone bl_clock_tz(), 'noon is not quiet');
  -- a window around "now": sweep sends nothing, the alert is moved to the end of the window
  perform pg_temp.cfg('kids.quiet_from_hour', extract(hour from (bl_now() at time zone bl_clock_tz()))::int::text);
  perform pg_temp.cfg('kids.quiet_to_hour', ((extract(hour from (bl_now() at time zone bl_clock_tz()))::int + 2) % 24)::text);
  update kids_children set hunger = 10, hunger_at = bl_now(), last_alert_at = null, alerts_unanswered = 0, next_alert_at = bl_now() - interval '1 minute' where id = v_ca;
  delete from events where user_id = pg_temp.u('a') and kind = 'kids_needs';
  perform bl_kids_alert_sweep();
  select * into c from kids_children where id = v_ca;
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_needs') = 0 and c.next_alert_at > bl_now() and c.next_alert_at <= bl_now() + interval '2 hours 1 minute', 'quiet hours: no alert now, due when the window ends: ' || c.next_alert_at::text);
  perform pg_temp.advance(extract(epoch from (c.next_alert_at - bl_now())) + 1);
  perform bl_kids_alert_sweep();
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_needs') = 1, 'sent when the quiet hours end');
  perform pg_temp.cfg('kids.quiet_enabled', 'false');
  raise notice 'ok 6: next_alert_at and the sweep';
end $$;

-- ---------- 7. admin ----------
do $$
declare v jsonb; v_c bigint; v_before bigint;
begin
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of('select admin_kids_overview()') = 'not_admin', 'players cannot read the admin overview');
  perform pg_temp.assert(pg_temp.hint_of('select admin_kids_remove(1)') = 'not_admin', 'nor remove a child');
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '1 hour', 'Badname');
  perform pg_temp.login_as('adm');
  v := admin_kids_overview();
  perform pg_temp.assert((v->>'home')::int >= 2 and (v->>'gone')::int >= 1 and jsonb_array_length(v->'children') >= 2 and v->'children'->0 ? 'a', 'admin counts: ' || (v - 'children')::text);
  perform pg_temp.assert(pg_temp.hint_of('select admin_kids_remove(99999999)') = 'no_child', 'unknown child');
  v_before := pg_temp.ev(pg_temp.u('a'), 'kids_gone');
  perform admin_kids_remove(v_c, 'rude name');
  perform pg_temp.assert((select status from kids_children where id = v_c) = 'gone' and (select gone_reason from kids_children where id = v_c) = 'admin'
                         and exists (select 1 from admin_audit where action = 'kids_remove' and (data->>'child')::bigint = v_c), 'removed + audited');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_gone') = v_before + 1 and pg_temp.ev(pg_temp.u('b'), 'kids_gone') >= 1, 'both parents told');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_kids_remove(%s)', v_c)) = 'no_child', 'already removed');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.cj(v_c) is null and pg_temp.hint_of(format('select kids_care(%s, %L)', v_c, 'play')) = 'not_home', 'a removed child is gone from the app');
  raise notice 'ok 7: admin';
end $$;

-- ---------- 8. invite decline / expiry / money checks, sweep-born baby, auto-name (couple c+d) ----------
do $$
declare v jsonb; v_inv bigint; v_cid bigint; v_nm text; v_n int;
begin
  perform pg_temp.login_as('c');
  update profiles set cash = 100, bank = 0 where id = pg_temp.u('c');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'not_enough_money', 'c cannot afford the plans');
  update profiles set cash = 1000000 where id = pg_temp.u('c');
  -- decline: nothing charged, the asker is told gently, and has to wait before asking again
  v := kids_try(); v_inv := (v->>'invite_id')::bigint;
  perform pg_temp.login_as('d');
  v := kids_accept(v_inv, false);
  perform pg_temp.assert(not (v->>'accepted')::boolean and pg_temp.cash(pg_temp.u('d')) = 1000000, 'declined, no charge: ' || v::text);
  perform pg_temp.login_as('c');
  perform pg_temp.assert(kids_status()->'outgoing'->0->>'state' = 'declined', 'c sees "declined"');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'cooldown', 'no nagging: wait between invites');
  perform pg_temp.hours(7);
  -- expiry
  v := kids_try(); v_inv := (v->>'invite_id')::bigint;
  perform pg_temp.hours(25);
  perform pg_temp.login_as('d');
  v := kids_accept(v_inv, true);
  perform pg_temp.assert((v->>'expired')::boolean and pg_temp.cash(pg_temp.u('d')) = 1000000, 'expired: ' || v::text);
  perform pg_temp.assert((select status from kids_invites where id = v_inv) = 'expired', 'the expiry sticks');
  -- money at the moment of the yes
  perform pg_temp.login_as('c');
  v := kids_try(); v_inv := (v->>'invite_id')::bigint;
  update profiles set cash = 0, bank = 0 where id = pg_temp.u('c');
  perform pg_temp.login_as('d');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_accept(%s)', v_inv)) = 'partner_short', 'the partner cannot cover their share');
  update profiles set cash = 1000000 where id = pg_temp.u('c');
  update profiles set cash = 100, bank = 0 where id = pg_temp.u('d');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_accept(%s)', v_inv)) = 'not_enough_money', 'the accepter cannot cover theirs');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('c')) = 1000000 and pg_temp.ledger_n(pg_temp.u('c'), 'kid_try') = 0, 'all or nothing: no money moved');
  update profiles set cash = 1000000 where id = pg_temp.u('d');
  -- withdraw and try again
  perform pg_temp.login_as('c');
  v := kids_withdraw(v_inv);
  perform pg_temp.assert((select status from kids_invites where id = v_inv) = 'withdrawn' and pg_temp.hint_of(format('select kids_withdraw(%s)', v_inv)) = 'no_invite', 'withdrawn once');
  perform pg_temp.hours(7);
  v := kids_try(); v_inv := (v->>'invite_id')::bigint;
  perform pg_temp.login_as('d');
  v := kids_accept(v_inv);
  v_cid := (v->>'child')::bigint;
  perform pg_temp.assert((v->>'accepted')::boolean and pg_temp.ledger_n(pg_temp.u('c'), 'kid_try') = 1, 'accepted: ' || v::text);
  -- the baby is born by the sweep (no parent opens the app)
  perform pg_temp.hours(72 + 0.1);
  delete from events where kind = 'kids_born' and user_id in (pg_temp.u('c'), pg_temp.u('d'));
  v_n := bl_kids_alert_sweep();
  perform pg_temp.assert((select status from kids_children where id = v_cid) = 'home' and pg_temp.ev(pg_temp.u('c'), 'kids_born') = 1 and pg_temp.ev(pg_temp.u('d'), 'kids_born') = 1,
                         'the sweep gives birth and alerts both parents');
  perform bl_kids_alert_sweep();
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('c'), 'kids_born') = 1, 'once');
  -- nobody names it: after 24 hours the game picks from the list
  perform pg_temp.hours(23);
  perform pg_temp.assert((select name from kids_children where id = v_cid) is null, 'still within the grace time');
  perform pg_temp.hours(1.1);
  perform pg_temp.login_as('c');
  v := pg_temp.cj(v_cid);
  v_nm := v->>'name';
  perform pg_temp.assert(v_nm is not null and exists (select 1 from kids_auto_names where name = v_nm) and (v->>'auto_named')::boolean and v->>'gender' in ('boy', 'girl'), 'auto name from the list: ' || v::text);
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('d'), 'kids_named') = 1, 'both told about the name');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_cid, 'Ehi', 'boy')) = 'already_named', 'an auto-named baby cannot be renamed either');
  perform set_config('kd.cd_child', v_cid::text, true);
  raise notice 'ok 8: invite flows, sweep birth, auto-name';
end $$;

-- ---------- 9. stages, sickness, relatives, reclaim, gone for good, growing up + badge (parents c+d) ----------
do $$
declare v_c bigint; v jsonb; c kids_children; b0 bigint; v_n int; v_e int;
begin
  perform pg_temp.login_as('c');
  -- stage names by age
  foreach v_n in array array[0, 2, 3, 7, 8, 13, 14, 20] loop
    v_c := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), make_interval(days => v_n) + interval '1 hour', 'Stagey');
    v := pg_temp.cj(v_c);
    perform pg_temp.assert(v->'stage'->>'id' = case when v_n < 3 then 'baby' when v_n < 8 then 'toddler' when v_n < 14 then 'child' else 'teen' end, 'stage at day ' || v_n || ': ' || (v->'stage')::text);
    update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  end loop;
  v := pg_temp.cj(current_setting('kd.cd_child')::bigint);
  perform pg_temp.assert(v->'stage'->>'emoji' = '👶', 'the baby emoji');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = current_setting('kd.cd_child')::bigint;

  -- sickness: a need at 0 for 24 hours
  v_c := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '2 days', 'Sicky');
  update kids_children set hunger = 0, hunger_at = bl_now() - interval '25 hours', last_care_at = bl_now() where id = v_c;
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  perform pg_temp.assert((select next_alert_at from kids_children where id = v_c) <= bl_now(), 'sickness is already due');
  v := pg_temp.cj(v_c);
  perform pg_temp.assert((v->>'sick')::boolean and (select sick_since from kids_children where id = v_c) <= bl_now(), 'sick after a day at zero: ' || v::text);
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('c'), 'kids_sick') = 1 and pg_temp.ev(pg_temp.u('d'), 'kids_sick') = 1, 'both told, once');
  perform pg_temp.assert(v->'needy' ? 'health' and v->'needy' ? 'hunger' and (v->'actions'->'medicine'->>'ok')::boolean, 'sick means unwell, and medicine is allowed even with high health');
  -- medicine alone does not cure; a cuddle alone does not either
  perform pg_temp.cfg('kids.medicine_cooldown_minutes', '0'); perform pg_temp.cfg('kids.cuddle_cooldown_minutes', '0');
  update kids_children set love = 50, love_at = bl_now() where id = v_c;
  v := kids_care(v_c, 'medicine');
  perform pg_temp.assert(not (v->>'cured')::boolean and (select sick_since from kids_children where id = v_c) is not null and v->>'message' like '%cuddle%', 'medicine alone: still sick: ' || v::text);
  perform pg_temp.login_as('d');
  v := kids_care(v_c, 'cuddle');
  perform pg_temp.assert((v->>'cured')::boolean and (select sick_since from kids_children where id = v_c) is null and (select cured_at from kids_children where id = v_c) = bl_now(), 'medicine + a cuddle (from the other parent) cure: ' || v::text);
  perform pg_temp.assert(pg_temp.ledger_sum(pg_temp.u('c'), 'kid_care') <= -1500, 'medicine cost money (ledger kid_care)');
  -- the hunger is still at 0: it does not make the child sick again right away (safe time), but it does after
  perform pg_temp.hours(1);
  perform pg_temp.assert(not (pg_temp.cj(v_c)->>'sick')::boolean, 'safe time after getting better');
  perform pg_temp.hours(6);
  perform pg_temp.assert((pg_temp.cj(v_c)->>'sick')::boolean, 'a need that is still empty makes them sick again after the safe time');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('c'), 'kids_sick') = 2, 'told again');
  perform pg_temp.cfg('kids.medicine_cooldown_minutes', '60'); perform pg_temp.cfg('kids.cuddle_cooldown_minutes', '30');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;

  -- either parent keeps the child from the relatives: only "nobody at all" counts
  v_c := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '1 day', 'Relo');
  update kids_children set last_care_at = bl_now() - interval '6 days' where id = v_c;
  perform pg_temp.hours(24 * 3);  -- 9 days since the last care (they would be with relatives)
  update kids_children set hunger = 100, hunger_at = bl_now(), sleep = 100, sleep_at = bl_now(), fun = 100, fun_at = bl_now(), health = 100, health_at = bl_now(), love = 100, love_at = bl_now() where id = v_c;
  update kids_children set last_care_at = bl_now() - interval '1 day' where id = v_c;   -- b cared yesterday: nobody is neglected
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  perform pg_temp.assert(pg_temp.cj(v_c)->>'status' = 'home', 'cared for by either parent: stays home');
  -- 7 days with nobody: relatives
  update kids_children set last_care_at = bl_now() - interval '7 days 1 minute', hunger = 100, hunger_at = bl_now(), sleep = 100, sleep_at = bl_now(), fun = 100, fun_at = bl_now(), love = 100, love_at = bl_now() where id = v_c;
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  v := pg_temp.cj(v_c);
  perform pg_temp.assert(v->>'status' = 'with_relatives' and (v->'relatives'->>'removals')::int = 1 and not (v->'relatives'->>'can_reclaim')::boolean, 'with relatives: ' || v::text);
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('c'), 'kids_relatives') = 1 and pg_temp.ev(pg_temp.u('d'), 'kids_relatives') = 1, 'both told, kindly');
  perform pg_temp.assert((select body from events where kind = 'kids_relatives' and user_id = pg_temp.u('c') limit 1) not ilike '%died%' and (select title from events where kind = 'kids_relatives' and user_id = pg_temp.u('c') limit 1) like '%with relatives%', 'wording is warm');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_c, 'play')) = 'not_home', 'no care while away');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'cooldown', 'relatives keep them a while first');
  perform pg_temp.hours(13);
  b0 := pg_temp.cash(pg_temp.u('c'));
  perform pg_temp.assert((pg_temp.cj(v_c)->'relatives'->>'can_reclaim')::boolean, 'can bring home now');
  perform pg_temp.login_as('h');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'not_parent', 'only a parent');
  perform pg_temp.login_as('c');
  update profiles set cash = 100, bank = 0 where id = pg_temp.u('c');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'not_enough_money', 'it costs 10,000');
  update profiles set cash = b0 where id = pg_temp.u('c');
  v := kids_reclaim(v_c);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('c')) = b0 - 10000 and pg_temp.ledger_sum(pg_temp.u('c'), 'kid_reclaim') = -10000, 'reclaim cost, ledger kid_reclaim: ' || v::text);
  select * into c from kids_children where id = v_c;
  perform pg_temp.assert(c.status = 'home' and c.reclaims = 1 and c.hunger = 60 and c.love = 60 and c.last_care_at = bl_now() and c.sick_since is null, 'home again with needs at 60');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'not_away', 'cannot reclaim a child who is home');
  -- a second time with relatives is for good
  update kids_children set last_care_at = bl_now() - interval '7 days 1 minute', hunger = 100, hunger_at = bl_now(), sleep = 100, sleep_at = bl_now(), fun = 100, fun_at = bl_now(), love = 100, love_at = bl_now() where id = v_c;
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  v := pg_temp.cj(v_c);
  perform pg_temp.assert(v is null, 'gone from the active list');
  select * into c from kids_children where id = v_c;
  perform pg_temp.assert(c.status = 'gone' and c.gone_reason = 'relatives' and c.removals = 2, 'second removal: for good');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('c'), 'kids_gone') >= 1 and (select body from events where kind = 'kids_gone' and user_id = pg_temp.u('c') order by id desc limit 1) not ilike '%died%', 'told kindly');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'not_away', 'no way back');

  -- growing up: the keepsake, the badge, nothing paid
  v_c := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '22 days', 'Grownup');
  update kids_children set last_care_at = bl_now() where id = v_c;
  update kids_children set born_at = bl_now() - interval '21 days 1 minute' where id = v_c;
  update kids_children set next_alert_at = bl_kids_next(pg_temp.kid(v_c)) where id = v_c;
  b0 := pg_temp.cash(pg_temp.u('c'));
  perform pg_temp.assert(pg_temp.cj(v_c) is null, 'not in the active list once grown');
  select * into c from kids_children where id = v_c;
  perform pg_temp.assert(c.status = 'grown' and c.grown_at is not null and c.next_alert_at is null, 'grown up at 21 days');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('c')) = b0, 'no money for growing up');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('c'), 'kids_grown') = 1 and pg_temp.ev(pg_temp.u('d'), 'kids_grown') = 1 and (select title from events where kind = 'kids_grown' limit 1) like '%has grown up!', 'keepsake alert to both');
  v := kids_status();
  perform pg_temp.assert((v->>'proud')::int = 1 and v->'grown'->0->>'name' = 'Grownup', 'proud parent in the app: ' || (v->'grown')::text);
  perform pg_temp.login_as('h');
  perform pg_temp.assert((get_public_profile(pg_temp.u('c'))->>'proud_parent')::int = 1, 'the badge shows on the profile');
  perform pg_temp.login_as('c');
  perform love_set_show_relationship(false);
  perform pg_temp.login_as('h');
  perform pg_temp.assert((get_public_profile(pg_temp.u('c'))->>'proud_parent')::int = 0, 'hidden when the profile toggle is off');
  perform pg_temp.login_as('c');
  perform love_set_show_relationship(true);
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_c, 'feed')) = 'not_home', 'no care for a grown child');
  raise notice 'ok 9: stages, sickness, relatives, reclaim, gone, growing up';
end $$;

-- ---------- 10. caps, break-up keeps co-parenting (couple e+f) ----------
do $$
declare v_rel bigint; v jsonb; v_c bigint; v_inv bigint;
begin
  v_rel := pg_temp.couple(pg_temp.u('e'), pg_temp.u('f'), 5);
  -- player cap: e already looks after a child with somebody else
  v_c := pg_temp.mkchild(pg_temp.u('e'), pg_temp.u('g'), interval '1 hour', 'Elder');
  update kids_children set rel_id = null where id = v_c;
  perform pg_temp.cfg('kids.max_children_per_player', '1');
  perform pg_temp.login_as('e');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'player_cap', 'player cap (e has 1, the limit is 1)');
  perform pg_temp.login_as('f');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'player_cap', 'it counts for the partner too');
  perform pg_temp.cfg('kids.max_children_per_player', '5');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  -- couple cap
  perform pg_temp.cfg('kids.max_children_per_couple', '1');
  v_c := pg_temp.mkchild(pg_temp.u('e'), pg_temp.u('f'), interval '1 day', 'Kidone');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'pair_cap', 'couple cap');
  perform pg_temp.cfg('kids.max_children_per_couple', '3');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'ok', 'with room again, an invite is sent');
  select id into v_inv from kids_invites where from_user = pg_temp.u('f') and status = 'pending';
  perform pg_temp.login_as('e');
  -- break-up: the child stays with both, the pending invite does not start a pregnancy
  perform love_breakup(v_rel);
  perform pg_temp.assert((select status from love_relationships where id = v_rel) = 'ended', 'they broke up');
  v := kids_accept(v_inv, true);
  perform pg_temp.assert(not (v->>'accepted')::boolean and (v->>'expired')::boolean and not exists (select 1 from kids_children where status = 'expecting' and parent_a in (pg_temp.u('e'), pg_temp.u('f'))),
                         'an invite cannot be accepted after a break-up: ' || v::text);
  perform pg_temp.assert((select status from kids_invites where id = v_inv) = 'cancelled', 'and it is cancelled');
  update kids_children set fun = 40, fun_at = bl_now(), love = 40, love_at = bl_now() where id = v_c;
  perform pg_temp.assert(pg_temp.cj(v_c)->>'status' = 'home', 'e still has the child');
  perform pg_temp.assert((pg_temp.cj(v_c)->'partner'->>'username') = 'KD_f', 'with f as the other parent');
  v := kids_care(v_c, 'play');
  perform pg_temp.assert(v->>'child' = v_c::text, 'e can still care');
  perform pg_temp.login_as('f');
  perform pg_temp.assert(pg_temp.cj(v_c)->>'status' = 'home', 'f still has the child');
  v := kids_care(v_c, 'cuddle');
  perform pg_temp.assert(v->>'child' = v_c::text, 'f can still care');
  perform pg_temp.assert(pg_temp.hint_of('select kids_try()') = 'no_relationship', 'no new baby after the break-up');
  perform pg_temp.assert((select count(*) from kids_children where id = v_c and parent_a is not null and parent_b is not null) = 1, 'linked to both parents');
  raise notice 'ok 10: caps and co-parenting after a break-up';
end $$;

-- ---------- 11. new life hands the child to the other parent (couple g+x) ----------
do $$
declare v_rel bigint; v_c bigint; v_p bigint; v jsonb; v_inv bigint;
begin
  v_rel := pg_temp.couple(pg_temp.u('g'), pg_temp.u('x'), 5);
  v_c := pg_temp.mkchild(pg_temp.u('g'), pg_temp.u('x'), interval '1 day', 'Handed');
  -- an expecting baby too (g+x: only one)
  perform pg_temp.login_as('g');
  v := kids_try(); v_inv := (v->>'invite_id')::bigint;
  perform pg_temp.login_as('x');
  v := kids_accept(v_inv);
  v_p := (v->>'child')::bigint;
  perform pg_temp.assert((select status from kids_children where id = v_p) = 'expecting', 'g and x expect a baby');
  -- x starts a new life (the real function)
  perform pg_temp.cfg('life.restart_cooldown_hours', '0');
  perform life_restart();
  perform pg_temp.assert(not exists (select 1 from profiles where id = pg_temp.u('x')), 'x is gone (a new life)');
  perform pg_temp.assert((select status from kids_children where id = v_c) = 'home' and (select (parent_a is null) <> (parent_b is null) from kids_children where id = v_c), 'the child stays, with one parent: g');
  perform pg_temp.assert((select count(*) from kids_children where id = v_c and (parent_a = pg_temp.u('g') or parent_b = pg_temp.u('g'))) = 1, 'g is the parent');
  perform pg_temp.assert((select status from kids_children where id = v_p) = 'gone' and (select gone_reason from kids_children where id = v_p) = 'cancelled', 'the pregnancy is cancelled');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('g'), 'kids_handover') = 1 and pg_temp.ev(pg_temp.u('g'), 'kids_cancelled') = 1, 'g is told, kindly');
  perform pg_temp.assert((select body from events where user_id = pg_temp.u('g') and kind = 'kids_handover') like '%on your own%', 'wording');
  perform pg_temp.login_as('g');
  v := pg_temp.cj(v_c);
  perform pg_temp.assert(v->>'status' = 'home' and v->'partner' = 'null'::jsonb, 'g sees the child, no other parent: ' || v::text);
  update kids_children set fun = 40, fun_at = bl_now() where id = v_c;
  v := kids_care(v_c, 'play');
  perform pg_temp.assert(v->>'child' = v_c::text, 'g can look after them alone');
  -- when the last parent leaves, relatives take the child for good
  delete from profiles where id = pg_temp.u('g');
  perform pg_temp.assert((select status from kids_children where id = v_c) = 'gone' and (select gone_reason from kids_children where id = v_c) = 'no_parents', 'no parent left: relatives');
  raise notice 'ok 11: new life hand-over';
end $$;

-- ---------- 12. kill switch pause ----------
do $$
declare v_c bigint; c0 kids_children; c1 kids_children; v_hunger numeric; v_n int; v jsonb;
begin
  v_c := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '2 days', 'Pausy');
  perform pg_temp.login_as('a');
  select * into c0 from kids_children where id = v_c;
  v_hunger := bl_kids_val(c0, 'hunger', bl_now());
  perform pg_temp.cfg('kids.enabled', 'false');
  perform pg_temp.assert((select paused_at from kids_pause where id = 1) = bl_now(), 'the pause is recorded');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', v_c, 'feed')) = 'off' and pg_temp.hint_of(format('select kids_name(%s, %L, %L)', v_c, 'Osaze', 'boy')) = 'off'
                         and pg_temp.hint_of(format('select kids_reclaim(%s)', v_c)) = 'off', 'care, naming and reclaim are off');
  update kids_children set next_alert_at = bl_now() - interval '1 minute' where id = v_c;
  delete from events where kind = 'kids_needs';
  v_n := bl_kids_alert_sweep();
  perform pg_temp.assert(v_n = 0 and not exists (select 1 from events where kind = 'kids_needs'), 'the sweep does nothing while off');
  perform pg_temp.hours(10);
  perform pg_temp.cfg('kids.enabled', 'true');
  select * into c1 from kids_children where id = v_c;
  perform pg_temp.assert(abs(extract(epoch from (c1.born_at - c0.born_at)) - 36000) < 2 and abs(extract(epoch from (c1.last_care_at - c0.last_care_at)) - 36000) < 2
                         and abs(extract(epoch from (c1.hunger_at - c0.hunger_at)) - 36000) < 2, 'every clock moved forward by the 10 hour pause');
  perform pg_temp.assert(abs(bl_kids_val(c1, 'hunger', bl_now()) - v_hunger) < 0.01, 'needs are exactly where they were: nobody is punished for the pause');
  perform pg_temp.assert((select paused_at from kids_pause where id = 1) is null, 'pause cleared');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v_c;
  raise notice 'ok 12: kill switch pause';
end $$;

-- ---------- 13. batch limit, the due index, 20 rows ----------
do $$
declare v_ids bigint[] := '{}'; v_id bigint; i int; v_n int; v_due int; v jsonb;
begin
  perform pg_temp.cfg('kids.sweep_batch', '10');
  for i in 1..25 loop
    v_id := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '1 hour', 'Batchy');
    update kids_children set hunger = 20, hunger_at = bl_now(), next_alert_at = bl_now() - interval '1 minute' where id = v_id;
    v_ids := v_ids || v_id;
  end loop;
  update kids_children set next_alert_at = null where id <> all (v_ids);   -- the children of the earlier groups are not part of this count
  select count(*) into v_due from kids_children where next_alert_at <= bl_now();
  perform pg_temp.assert(v_due = 25, '25 children are due');
  v_n := bl_kids_alert_sweep();
  perform pg_temp.assert(v_n = 10 and (select count(*) from kids_children where next_alert_at <= bl_now()) = 15, 'the sweep takes at most the batch size (10): ' || v_n);
  perform pg_temp.assert((select count(*) from events where kind = 'kids_needs' and (data->>'child')::bigint = any (v_ids)) = 20, 'two parents each for 10 children');
  v_n := bl_kids_alert_sweep();
  v_n := v_n + bl_kids_alert_sweep();
  perform pg_temp.assert((select count(*) from kids_children where next_alert_at <= bl_now()) = 0 and (select count(*) from events where kind = 'kids_needs' and (data->>'child')::bigint = any (v_ids)) = 50, 'three sweeps handle them all, once each');
  -- 20 rows at most in the app
  perform pg_temp.login_as('a');
  v := kids_status();
  perform pg_temp.assert(jsonb_array_length(v->'children') <= 20, 'at most 20 children in one read: ' || jsonb_array_length(v->'children'));
  perform pg_temp.assert(exists (select 1 from pg_indexes where indexname = 'kids_children_due' and indexdef like '%next_alert_at%')
                         and exists (select 1 from pg_indexes where indexname = 'kids_children_a') and exists (select 1 from pg_indexes where indexname = 'kids_children_b'), 'indexes exist');
  delete from kids_children where id = any (v_ids);
  perform pg_temp.cfg('kids.sweep_batch', '200');
  raise notice 'ok 13: batch limit, index, row limit';
end $$;

-- the plan of the due lookup (explain output read through a function)
create or replace function pg_temp.plan_of(p_sql text) returns text
language plpgsql as $$
declare r record; v text := '';
begin
  for r in execute 'explain ' || p_sql loop v := v || (r."QUERY PLAN") || E'\n'; end loop;
  return v;
end $$;

do $$
declare v_plan text;
begin
  set local enable_seqscan = off;
  v_plan := pg_temp.plan_of('select id from kids_children where next_alert_at <= now() order by next_alert_at limit 200');
  reset enable_seqscan;
  perform pg_temp.assert(v_plan like '%kids_children_due%', 'the due query uses the due index: ' || v_plan);
  raise notice 'ok 13b: due index in the plan';
end $$;

-- ---------- 14. no client access to the tables ----------
do $$
declare t text; v boolean;
begin
  perform pg_temp.login_as('a');
  set local role authenticated;
  foreach t in array array['kids_stages', 'kids_auto_names', 'kids_children', 'kids_invites', 'kids_care_log', 'kids_pause'] loop
    begin
      execute format('select * from public.%I limit 1', t);
      v := false;
    exception when insufficient_privilege then v := true;
    end;
    reset role;
    perform pg_temp.assert(v, 'clients cannot read ' || t);
    set local role authenticated;
    begin
      execute format('delete from public.%I', t);
      v := false;
    exception when insufficient_privilege then v := true;
    end;
    reset role;
    perform pg_temp.assert(v, 'clients cannot write ' || t);
    set local role authenticated;
  end loop;
  reset role;
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_kids_alert_sweep()', 'execute'), 'players cannot run the sweep');
  perform pg_temp.assert((select count(*) from kids_children) > 0, 'the table is not empty to the owner role');
  raise notice 'ok 14: no direct table access';
end $$;
