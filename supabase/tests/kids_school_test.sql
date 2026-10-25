-- Kids school and university (20261029000100_kids_school.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/kids_school_test.sql
-- The clock is pinned to 10:00 Benin time, time moves with bl.test_offset_seconds. Talent is switched off (kids_school.talent_pts 0) where exact grades are asserted.
-- Groups: 1 grants / RLS / settings / seeds / ledger · 2 enrol rules · 3 fees: pay, unpaid = missed class · 4 grade maths (homework, books, uniform, lessons, needs, quality, talent) ·
-- 5 promotion vs repeat, textbooks, lessons, homework limits · 6 school requests (both parents, first pays, ignore, cap, one per class) · 7 the sweep ·
-- 8 a whole school life: classes by day, report cards, WAEC, the university decision, levels, graduation, outcome, gift and the Graduate tier ·
-- 9 WAEC fail, no university · 10 university: unpaid levels repeat, drop out after the repeat limit · 11 no answer = work · 12 outcome lines · 13 switch off, admin.
update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');
-- chance illness is tested in kids_v2_test.sql; here it is off so the stage 2 flows are deterministic
update game_config set value = '0' where key = 'kids.daily_sick_pct';

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
                             hunger, hunger_at, sleep, sleep_at, fun, fun_at, health, health_at, love, love_at, clean, clean_at, last_care_at, score_at)
  values (pg_temp.rel(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), p_a, 'home', p_name, 'girl', bl_now() - p_age - interval '3 days', bl_now() - p_age, bl_now() - p_age,
          100, bl_now(), 100, bl_now(), 100, bl_now(), 100, bl_now(), 100, bl_now(), 100, bl_now(), bl_now(), bl_now()) returning id into v;
  update kids_children set next_roll_at = bl_kids_roll_time(v, bl_now()) where id = v;
  select * into c from kids_children where id = v;
  update kids_children set next_alert_at = bl_kids_next(c) where id = v;
  return v;
end $$;

create or replace function pg_temp.kid(p_id bigint) returns kids_children language sql as $$ select * from kids_children where id = p_id $$;

-- the child json for a player from kids_status
create or replace function pg_temp.cj(p_child bigint) returns jsonb language sql as $$
  select x from jsonb_array_elements(kids_status() -> 'children') x where (x ->> 'id')::bigint = p_child $$;

-- supplies for care: formula, diapers, syrup, malaria drugs (a few of each)
create or replace function pg_temp.stock(p_uid uuid, p_qty int default 5) returns void
language plpgsql as $$
declare i text;
begin
  foreach i in array array['kid_formula', 'kid_diapers', 'kid_paracetamol', 'kid_malaria'] loop
    insert into inventory (user_id, item_id, qty) values (p_uid, i, p_qty) on conflict (user_id, item_id) do update set qty = p_qty;
  end loop;
  delete from kids_charges where user_id = p_uid;
end $$;

create or replace function pg_temp.sub(p_user uuid) returns void
language plpgsql as $$
begin
  insert into push_subscriptions (user_id, endpoint, p256dh, auth)
  values (p_user, 'https://push.example.test/' || p_user || '/1', repeat('A', 87), repeat('B', 22));
end $$;


-- ---------- school helpers ----------
create or replace function pg_temp.sch(p_child bigint) returns jsonb language sql as $$ select (pg_temp.cj(p_child)) -> 'school' $$;
create or replace function pg_temp.spent(p_child bigint, p_user text) returns bigint language sql as $$ select case when parent_a = pg_temp.u(p_user) then spent_a else spent_b end from kids_children where id = p_child $$;
create or replace function pg_temp.ks(p_child bigint) returns kids_school language sql as $$ select * from kids_school where child_id = p_child $$;
create or replace function pg_temp.clear(p_keys text[]) returns void
language plpgsql as $$
declare k text;
begin
  foreach k in array p_keys loop
    update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where (parent_a = pg_temp.u(k) or parent_b = pg_temp.u(k)) and status in ('home', 'university', 'with_relatives');
  end loop;
  update player_moments set status = 'expired' where status in ('pending', 'snoozed', 'scheduled');
end $$;

-- one care round: feed, sleep, play, cuddle (what is not needed or not available is skipped)
create or replace function pg_temp.care(p_child bigint, p_user text) returns void
language plpgsql as $$
declare a text;
begin
  perform pg_temp.login_as(p_user);
  foreach a in array array['feed', 'sleep', 'play', 'cuddle'] loop
    begin perform kids_care(p_child, a); exception when others then null; end;
  end loop;
end $$;

-- answer every school card a parent has: pay (school requests) and the university choice
create or replace function pg_temp.cards(p_user text, p_uni text) returns void
language plpgsql as $$
declare m jsonb;
begin
  perform pg_temp.login_as(p_user);
  for m in select x from jsonb_array_elements(moments_pending() -> 'moments') x loop
    if m ->> 'kind' = 'kids_school' then
      begin perform moments_answer((m ->> 'id')::bigint, 'pay'); exception when others then null; end;
    elsif m ->> 'kind' = 'kids_uni' and p_uni <> '' then
      begin perform moments_answer((m ->> 'id')::bigint, p_uni); exception when others then null; end;
    end if;
  end loop;
end $$;

-- one tending round for a child: read (settles the school clock), pick a school when needed, pay the fee, homework by both parents, answer the cards
create or replace function pg_temp.tend(p_child bigint, p_a text, p_b text, p_pay boolean default true, p_uni text default 'uniben') returns void
language plpgsql as $$
declare j jsonb; r jsonb;
begin
  perform pg_temp.login_as(p_a);
  j := pg_temp.sch(p_child);
  if j is null then return; end if;
  if j ->> 'state' = 'need_school' then
    r := kids_school_schools(p_child);
    perform kids_school_enrol(p_child, case r ->> 'level' when 'secondary' then 'ugbowo_grammar' else 'uselu_model' end);
    j := pg_temp.sch(p_child);
  end if;
  if j ->> 'state' in ('learning', 'university') and p_pay and not (j -> 'fee' ->> 'paid')::boolean then
    perform kids_school_pay(p_child);
  end if;
  if j ->> 'state' = 'learning' then
    begin perform kids_school_homework(p_child); exception when others then null; end;
    perform pg_temp.login_as(p_b);
    begin perform kids_school_homework(p_child); exception when others then null; end;
  end if;
  perform pg_temp.cards(p_a, '');
  perform pg_temp.cards(p_b, p_uni);
end $$;

-- run a school life: p_days of real time in 3 hour steps, caring and tending at every step
create or replace function pg_temp.journey(p_child bigint, p_a text, p_b text, p_days numeric, p_pay boolean default true, p_uni text default 'uniben') returns void
language plpgsql as $$
declare i int;
begin
  for i in 1..(p_days * 8)::int loop
    perform pg_temp.advance(3 * 3600);
    perform pg_temp.care(p_child, p_a);
    perform pg_temp.tend(p_child, p_a, p_b, p_pay, p_uni);
  end loop;
end $$;

-- ---------- setup ----------
do $$
declare
  v_keys text[] := array['adm', 'a', 'b', 'c', 'd', 'e', 'f'];
  k text; u uuid;
  v_local timestamp := now() at time zone bl_clock_tz();
  v_target timestamp;
begin
  v_target := date_trunc('day', v_local) + case when v_local::time >= time '10:00' then interval '34 hours' else interval '10 hours' end;
  perform set_config('bl.test_offset_seconds', extract(epoch from (v_target - v_local))::text, true);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  foreach k in array v_keys loop
    u := pg_temp.mk('KS_' || k);
    perform set_config('kd.' || k, u::text, true);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
  perform pg_temp.couple(pg_temp.u('a'), pg_temp.u('b'), 5);
  perform pg_temp.couple(pg_temp.u('c'), pg_temp.u('d'), 5);
  perform pg_temp.couple(pg_temp.u('e'), pg_temp.u('f'), 5);
  foreach k in array array['a', 'b', 'c', 'd', 'e', 'f'] loop
    perform pg_temp.stock(pg_temp.u(k));
    perform pg_temp.sub(pg_temp.u(k));
    perform pg_temp.login_as(k); perform push_prefs_set('{"master": true, "friends": true}');
  end loop;
  update game_config set value = '1000' where key = 'push.max_per_user_hour';
  update game_config set value = '0' where key in ('kids.feed_cooldown_minutes', 'kids.change_cooldown_minutes', 'kids.play_cooldown_minutes', 'kids.medicine_cooldown_minutes', 'kids.cuddle_cooldown_minutes', 'kids.sleep_cooldown_minutes');
  update game_config set value = '100' where key = 'moments.daily_cap';
  update game_config set value = '0' where key = 'kids_school.request_pct';
  update profiles set cash = 50000000 where id in (pg_temp.u('a'), pg_temp.u('b'), pg_temp.u('c'), pg_temp.u('d'), pg_temp.u('e'), pg_temp.u('f'));
end $$;

-- ---------- 1. grants, RLS, settings, seeds, ledger ----------
do $$
declare v text; n int; r record;
begin
  select string_agg(p.proname, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and (p.proname like 'kids\_school\_%' or p.proname = 'kids_report_cards')
     and (not p.prosecdef or not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
          or not has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'));
  perform pg_temp.assert(v is null, 'school RPCs: security definer, search_path, authenticated only: ' || coalesce(v, ''));
  perform pg_temp.assert((select count(*) from pg_proc where proname in ('kids_school_schools', 'kids_school_enrol', 'kids_school_pay', 'kids_school_homework', 'kids_school_lessons', 'kids_school_gear', 'kids_report_cards')) = 7, 'seven player RPCs');
  select string_agg(p.proname, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like 'bl\_kids\_%'
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'));
  perform pg_temp.assert(v is null, 'every bl_kids_* helper (new ones too) is private: ' || coalesce(v, ''));
  select string_agg(t, ', ') into v from unnest(array['kids_schools', 'kids_subjects', 'kids_classes', 'kids_school', 'kids_school_results', 'kids_report_cards', 'kids_school_requests']) t
   where not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass)
      or has_table_privilege('authenticated', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'select')
      or has_table_privilege('authenticated', 'public.' || t, 'insert') or has_table_privilege('authenticated', 'public.' || t, 'update')
      or has_table_privilege('authenticated', 'public.' || t, 'delete');
  perform pg_temp.assert(v is null, 'school tables: RLS on, no grants: ' || coalesce(v, ''));
  perform pg_temp.assert(not exists (select 1 from pg_constraint where conrelid in ('public.kids_school'::regclass, 'public.kids_school_results'::regclass, 'public.kids_school_requests'::regclass, 'public.kids_report_cards'::regclass) and contype = 'f'),
                         'the school tables have no foreign keys (nothing touches profiles)');
  select count(*) into n from game_config where category = 'kids_school' and label <> '' and description <> '';
  perform pg_temp.assert(n >= 28 and n = (select count(*) from game_config where key like 'kids\_school.%'), 'every school setting has a label and description (' || n || ')');
  perform pg_temp.assert(bl_cfg('kids_school.class_hours') = 24 and bl_cfg('kids_school.pass_mark') = 50 and bl_cfg('kids_school.uni_level_hours') = 24 and bl_cfg('kids_school.uni_max_repeats') = 2
                         and bl_cfg('kids.gift_graduate') = 250000 and bl_cfg_bool('kids_school.enabled') and bl_cfg_bool('kids_school.uni_enabled'), 'defaults');
  -- seeds
  perform pg_temp.assert((select count(*) from kids_schools where active and not ('university' = any (levels))) = 6 and (select count(*) from kids_schools where 'university' = any (levels)) = 2, 'six schools and two universities');
  perform pg_temp.assert(not exists (select 1 from kids_schools where 'university' <> all (levels) and fee_per_class not between 20000 and 150000)
                         and not exists (select 1 from kids_schools where 'university' = any (levels) and fee_per_class not between 60000 and 400000), 'fees: schools 20,000-150,000, universities 60,000-400,000');
  perform pg_temp.assert((select count(distinct tier) from kids_schools where 'university' <> all (levels)) = 3 and exists (select 1 from kids_schools where id = 'uniben' and tier = 'public')
                         and (select fee_per_class from kids_schools where id = 'uniben') < (select fee_per_class from kids_schools where id = 'edo_royal_university')
                         and (select quality from kids_schools where id = 'uniben') < (select quality from kids_schools where id = 'edo_royal_university'), 'budget, mid and premium schools; UNIBEN is cheaper than the private university');
  perform pg_temp.assert(not exists (select 1 from kids_schools where bl_chat_mask(name) <> name or name ilike '%lagos%' or blurb ilike '%lagos%'), 'school names are clean');
  perform pg_temp.assert((select count(*) from kids_classes) = 14 and (select array_agg(name order by seq) from kids_classes where seq in (1, 2, 3, 8, 9, 11, 12, 14)) = array['Nursery 1', 'Nursery 2', 'Primary 1', 'Primary 6', 'JSS 1', 'JSS 3', 'SSS 1', 'SSS 3'], 'fourteen classes');
  perform pg_temp.assert((select count(*) from kids_subjects where level = 'nursery') = 3 and (select count(*) from kids_subjects where level = 'primary') = 4 and (select count(*) from kids_subjects where level = 'secondary') = 5
                         and (select count(*) from kids_subjects where level = 'university') = 2 and (select count(*) from kids_subjects where level = 'waec') = 9, 'subjects per level, nine WAEC papers');
  perform pg_temp.assert((select name from kids_subjects where id = 'p_science') = 'Basic Science' and (select name from kids_subjects where id = 's_bio') = 'Biology/Physics' and (select name from kids_subjects where id = 'u_course') = 'Course work', 'subject names');
  perform pg_temp.assert((select price from items where id = 'kid_books_primary') between 5000 and 25000 and (select price from items where id = 'kid_books_secondary') between 5000 and 25000 and (select price from items where id = 'kid_uniform') between 5000 and 25000
                         and (select count(*) from kids_items where role in ('books', 'uniform')) = 3 and not exists (select 1 from items where id in ('kid_books_primary', 'kid_books_secondary', 'kid_uniform') and (category <> 'kids' or tradeable or not ('oba_market' = any (sold_at)))), 'school items: kids category, realistic prices, sold at the markets');
  perform pg_temp.assert((select kind from life_moments where id = 'school_pta') = 'kids_school' and (select kind from life_moments where id = 'uni_decision') = 'kids_uni'
                         and (select count(*) from life_moments where kind = 'kids_school') = 5 and (select count(*) from life_moments where id = 'uni_decision' and jsonb_array_length(choices) = 3) = 1, 'five school request cards and the university card');
  perform pg_temp.assert(pg_temp.hint_of($q$update life_moments set choices = '[{"id":"x","label":"x","outcome":"x","effects":[{"t":"kid_uni","school":"Bad Id"}]}]'::jsonb where id = 'school_pta'$q$) = 'bad_value', 'kid_uni needs a clean school id');
  perform pg_temp.assert(pg_temp.hint_of($q$update life_moments set choices = '[{"id":"x","label":"x","outcome":"x","effects":[{"t":"kid_school_hack"}]}]'::jsonb where id = 'school_pta'$q$) = 'bad_value', 'unknown effects are still refused');
  -- ledger
  perform pg_temp.assert(not ('kid_school_fee' = any (bl_earn_reasons())) and not ('kid_school_lessons' = any (bl_earn_reasons())), 'school ledger reasons are not earned');
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,hustle,kid_school_fee,kid_school_lessons"');
  perform pg_temp.assert(not ('kid_school_fee' = any (bl_earn_reasons())) and not ('kid_school_lessons' = any (bl_earn_reasons())), 'not earned even if an admin lists them');
  perform pg_temp.assert(bl_econ_category('kid_school_fee') = 'School fees' and bl_econ_category('kid_school_lessons') = 'School fees' and bl_ledger_label('kid_school_fee', '{"label":"School fees: Ada"}') = 'School fees: Ada'
                         and bl_ledger_label('kid_school_lessons', '{}') = 'Extra lessons', 'labels and category');
  perform pg_temp.assert(bl_admin_table_spec('kids_schools')->'cols'->>'fee_per_class' = 'int' and bl_admin_table_spec('kids_subjects')->'pk'->>0 = 'id' and bl_admin_table_spec('kids_illnesses') is not null and bl_admin_table_spec('kids_stages') is not null, 'Content editors for schools and subjects (and the old ones still there)');
  perform pg_temp.assert((select needs from kids_stages where id = 'university') = array['hunger', 'love'], 'university needs: pocket money and attention');
  raise notice 'ok 1: grants, RLS, settings, seeds, ledger';
end $$;

-- ---------- 2. enrol rules ----------
do $$
declare ca bigint; cb bigint; cbaby bigint; v jsonb; s kids_school; n int; v_fee0 bigint;
begin
  perform pg_temp.cfg('kids_school.talent_pts', '0');
  -- a baby cannot go to school
  cbaby := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '1 hour', 'Baby');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.cj(cbaby) -> 'school' ->> 'state' = 'none' and (pg_temp.cj(cbaby) -> 'school' ->> 'can_enrol')::boolean = false, 'a baby has no school yet');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_enrol(%s, %L)', cbaby, 'uselu_model')) = 'too_young', 'too young for school');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = cbaby;
  -- a Nursery child (day 5)
  ca := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '5 days 1 hour', 'Osaze');
  perform set_config('kd.ca', ca::text, true);
  v := pg_temp.sch(ca);
  perform pg_temp.assert(v ->> 'state' = 'none' and (v ->> 'can_enrol')::boolean and v ->> 'level' = 'nursery', 'a nursery child can be enrolled');
  v := kids_school_schools(ca);
  perform pg_temp.assert(v ->> 'level' = 'nursery' and jsonb_array_length(v -> 'schools') = 3 and not exists (select 1 from jsonb_array_elements(v -> 'schools') x where x ->> 'id' in ('ugbowo_grammar', 'uniben')), 'only nursery schools are listed');
  perform pg_temp.assert((v -> 'schools' -> 0 ->> 'id') = 'uselu_model' and (v -> 'schools' -> 0 ->> 'fee')::bigint = 20000, 'listed by fee, with fee and quality');
  perform pg_temp.assert((v -> 'schools' -> 2 ->> 'area') = 'GRA' and (v -> 'schools' -> 1 ->> 'area') = 'Third East', 'area labels are tidy (GRA, Third East)');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_enrol(%s, %L)', ca, 'ugbowo_grammar')) = 'wrong_level', 'the school must teach the level');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_enrol(%s, %L)', ca, 'nope')) = 'bad_school', 'unknown school');
  perform pg_temp.login_as('c');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_enrol(%s, %L)', ca, 'uselu_model')) = 'not_parent', 'only a parent can enrol');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_pay(%s)', ca)) = 'not_parent' and pg_temp.hint_of(format('select kids_school_homework(%s)', ca)) = 'not_parent'
                         and pg_temp.hint_of(format('select kids_report_cards(%s)', ca)) = 'not_parent', 'nor pay, help or read the report cards');
  -- either parent: b enrols
  perform pg_temp.login_as('b');
  v := kids_school_enrol(ca, 'uselu_model');
  perform pg_temp.assert(v ->> 'school' = 'uselu_model', 'b enrols the child');
  s := pg_temp.ks(ca);
  perform pg_temp.assert(s.school_id = 'uselu_model' and s.seq = 1 and s.class_start is not null and s.fee_amount = 20000 and s.fee_paid_at is null and s.max_seq = 1, 'Nursery 1 starts at once with the fee due');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_school_enrol') = 1 and pg_temp.ev(pg_temp.u('a'), 'kids_school_fee') >= 1, 'a is told: new school, fee due');
  perform pg_temp.login_as('a');
  v := pg_temp.sch(ca);
  perform pg_temp.assert(v ->> 'state' = 'learning' and v -> 'class' ->> 'name' = 'Nursery 1' and v -> 'school' ->> 'name' = 'Uselu Model Nursery & Primary School'
                         and not (v -> 'fee' ->> 'paid')::boolean and (v -> 'fee' ->> 'amount')::bigint = 20000 and jsonb_array_length(v -> 'grades') = 3, 'the app shows the class, the school, the unpaid fee and three subjects');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_enrol(%s, %L)', ca, 'uselu_model')) = 'same_school', 'same school');
  -- switching between classes: allowed while this class is not paid
  v := kids_school_enrol(ca, 'gra_royal_kids');
  s := pg_temp.ks(ca);
  perform pg_temp.assert(s.school_id = 'gra_royal_kids' and s.fee_amount = 120000 and s.seq = 1, 'switched before paying: the fee follows the school');
  v := kids_school_enrol(ca, 'uselu_model');
  -- once paid it stays until the class ends
  perform pg_temp.login_as('a');
  v := kids_school_pay(ca);
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_enrol(%s, %L)', ca, 'thirdeast_stars')) = 'class_running', 'cannot switch after paying until the class ends');
  perform pg_temp.assert((pg_temp.sch(ca) -> 'can_switch')::boolean = false, 'the app says so');
  raise notice 'ok 2: enrol rules';
end $$;

-- ---------- 3. fees ----------
do $$
declare ca bigint := current_setting('kd.ca')::bigint; v jsonb; s kids_school; v_cash bigint; kid kids_children; v_b0 bigint; n int;
begin
  perform pg_temp.login_as('a');
  s := pg_temp.ks(ca);
  perform pg_temp.assert(s.fee_paid_at is not null and s.fee_paid_by = pg_temp.u('a'), 'the fee is paid by a');
  perform pg_temp.assert(pg_temp.ledger_n(pg_temp.u('a'), 'kid_school_fee') = 1 and pg_temp.ledger_sum(pg_temp.u('a'), 'kid_school_fee') = -20000, 'ledger kid_school_fee, a sink of the fee');
  perform pg_temp.assert(pg_temp.spent(ca, 'a') = 20000 and pg_temp.spent(ca, 'b') = 0, 'the fee counts as what a spent on the child');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_pay(%s)', ca)) = 'already_paid', 'paying twice is refused');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('b'), 'kids_school_paid') = 1, 'b is told a paid');
  perform pg_temp.assert((pg_temp.sch(ca) -> 'fee' ->> 'paid')::boolean and (pg_temp.sch(ca) -> 'fee' ->> 'paid_by_me')::boolean, 'the app shows paid');
  -- money short: all or nothing
  update profiles set cash = 100, bank = 0 where id = pg_temp.u('d');
  update profiles set cash = 50000000 where id = pg_temp.u('d');
  -- an unpaid class is missed: child c1 of c and d, nobody pays
  declare cc bigint; ccs kids_school; fun0 numeric; r kids_school_results;
  begin
    cc := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '5 days 1 hour', 'Efe');
    perform set_config('kd.cc', cc::text, true);
    perform pg_temp.login_as('c');
    perform kids_school_enrol(cc, 'uselu_model');
    perform pg_temp.hours(13);
    perform pg_temp.sch(cc);
    perform pg_temp.assert(pg_temp.ev(pg_temp.u('c'), 'kids_school_fee') >= 2, 'a reminder when the fee is still due half way through');
    perform pg_temp.hours(11);
    perform pg_temp.assert((pg_temp.ks(cc)).class_start is not null, 'the class has not run out yet (before the read settles it)');
    perform pg_temp.hours(1);
    v := pg_temp.sch(cc);
    select * into r from kids_school_results where child_id = cc order by id desc limit 1;
    ccs := pg_temp.ks(cc);
    perform pg_temp.assert(r.attended = false and not r.promoted and r.avg < 50 and r.class_name = 'Nursery 1', 'unpaid: the class is missed and the grades drop (' || r.avg || ')');
    perform pg_temp.assert(ccs.seq = 1 and ccs.attempt = 2 and ccs.missed = 1 and ccs.class_start is not null, 'repeats Nursery 1, attempt 2, and the repeat starts at once');
    perform pg_temp.assert((select fun from kids_children where id = cc) < 60, 'the child is sad (fun dropped)');
    perform pg_temp.assert(pg_temp.ev(pg_temp.u('c'), 'kids_school_result') = 1 and pg_temp.ev(pg_temp.u('d'), 'kids_school_result') = 1, 'both parents are told');
    perform pg_temp.assert(v ->> 'state' = 'learning' and (v ->> 'attempt')::int = 2 and (v -> 'last' ->> 'promoted')::boolean = false and (v -> 'last' ->> 'attended')::boolean = false, 'the app shows repeating');
    perform pg_temp.assert(pg_temp.ledger_n(pg_temp.u('c'), 'kid_school_fee') = 0, 'nothing was charged');
  end;
  raise notice 'ok 3: fees, missed classes';
end $$;

-- ---------- 4. grade maths ----------
do $$
declare s kids_school; j jsonb; j2 jsonb; i int; v_t numeric; t0 timestamptz := bl_now();
begin
  perform pg_temp.cfg('kids_school.talent_pts', '0');
  s.hw_users := '{}'; s.penalty := 0; s.class_start := t0; s.fee_paid_at := t0;
  j := bl_kids_school_calc(777, s, 'primary', 'primary', 0, true, 1);
  perform pg_temp.assert((j ->> 'avg')::numeric = 56 and jsonb_array_length(j -> 'grades') = 4 and (j -> 'grades' -> 0 ->> 'name') = 'Maths' and (j -> 'grades' -> 2 ->> 'name') = 'Basic Science',
                         'base 38 + fee on time 6 + a well cared for child 12 = 56 (' || (j ->> 'avg') || ')');
  s.hw_users := array[pg_temp.u('a'), pg_temp.u('b')];
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'primary', 'primary', 0, true, 1) ->> 'avg')::numeric = 64, 'two homework helps: +4 each');
  s.hw_users := '{}';
  s.books_stage := 'primary';
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'primary', 'primary', 0, true, 1) ->> 'avg')::numeric = 61, 'textbooks of the level: +5');
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'primary', 'secondary', 0, true, 1) ->> 'avg')::numeric = 56, 'textbooks of another level do nothing');
  s.books_stage := 'university';
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'university', 'university', 0, true, 1) ->> 'avg')::numeric = 56 and jsonb_array_length(bl_kids_school_calc(777, s, 'university', 'university', 0, true, 1) -> 'grades') = 2, 'no books bonus at university, two subjects');
  s.books_stage := null; s.uniform_stage := 'primary';
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'primary', 'primary', 0, true, 1) ->> 'avg')::numeric = 59, 'school bag and uniform: +3');
  s.uniform_stage := null; s.lessons_at := t0;
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'primary', 'primary', 0, true, 1) ->> 'avg')::numeric = 64, 'extra lessons: +8');
  s.lessons_at := null; s.penalty := 4;
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'primary', 'primary', 0, true, 1) ->> 'avg')::numeric = 52, 'an ignored request: -4');
  s.penalty := 0;
  s.fee_paid_at := t0 + interval '13 hours';
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'primary', 'primary', 0, true, 1) ->> 'avg')::numeric = 50, 'a fee paid late: no on-time points');
  s.fee_paid_at := t0;
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'primary', 'primary', 0, true, 0) ->> 'avg')::numeric = 32 and (bl_kids_school_calc(777, s, 'primary', 'primary', 0, true, 0.5) ->> 'avg')::numeric = 44,
                         'needs: a neglected child -12, in between scaled');
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'primary', 'primary', 10, true, 1) ->> 'avg')::numeric = 62, 'school quality 10 % lifts every grade (56 x 1.10 = 61.6)');
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'primary', 'primary', 0, false, 1) ->> 'avg')::numeric = 22, 'a missed class starts from the missed grade');
  s.hw_users := array[pg_temp.u('a'), pg_temp.u('b')]; s.books_stage := 'secondary'; s.uniform_stage := 'secondary'; s.lessons_at := t0;
  j := bl_kids_school_calc(777, s, 'secondary', 'secondary', 50, true, 1);
  perform pg_temp.assert((j ->> 'avg')::numeric = 100 and jsonb_array_length(j -> 'grades') = 5, 'grades never go over 100');
  s.hw_users := '{}'; s.books_stage := null; s.uniform_stage := null; s.lessons_at := null; s.penalty := 200;
  perform pg_temp.assert((bl_kids_school_calc(777, s, 'primary', 'primary', 0, true, 1) ->> 'avg')::numeric = 0, 'nor under 0');
  s.penalty := 0;
  -- talent: hidden, fixed, per child and subject
  perform pg_temp.cfg('kids_school.talent_pts', '8');
  j := bl_kids_school_calc(101, s, 'primary', 'primary', 0, true, 1);
  j2 := bl_kids_school_calc(101, s, 'primary', 'primary', 0, true, 1);
  perform pg_temp.assert(j = j2, 'talent is deterministic');
  perform pg_temp.assert(j <> bl_kids_school_calc(102, s, 'primary', 'primary', 0, true, 1) or j <> bl_kids_school_calc(103, s, 'primary', 'primary', 0, true, 1), 'children differ');
  for i in 0..3 loop
    v_t := (j -> 'grades' -> i ->> 'g')::numeric;
    perform pg_temp.assert(v_t between 56 - 13 and 56 + 13, 'a subject stays within the talent swing of the base: ' || v_t);
  end loop;
  perform pg_temp.assert(bl_kids_talent(5, 'x') = bl_kids_talent(5, 'x') and abs(bl_kids_talent(5, 'x')) <= 1 and bl_kids_talent(5, 'x') <> bl_kids_talent(6, 'x'), 'bl_kids_talent is in [-1, 1] and fixed');
  perform pg_temp.cfg('kids_school.talent_pts', '0');
  perform pg_temp.assert(bl_kids_degree(72) = 'First Class' and bl_kids_degree(70) = 'First Class' and bl_kids_degree(65) = 'Second Class Upper' and bl_kids_degree(57) = 'Second Class Lower' and bl_kids_degree(51) = 'Third Class', 'degree classes');
  perform pg_temp.assert(bl_kids_position(80) = 'Excellent' and bl_kids_position(65) = 'Very good' and bl_kids_position(52) = 'Good' and bl_kids_position(30) = 'Needs help', 'position text');
  raise notice 'ok 4: grade maths';
end $$;

-- ---------- 5. promotion or repeat, homework, textbooks, lessons ----------
do $$
declare ca bigint := current_setting('kd.ca')::bigint; cc bigint := current_setting('kd.cc')::bigint; v jsonb; r kids_school_results; s kids_school; n int; v_u0 bigint;
begin
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = cc;
  -- ca: Nursery 1 was paid and ran out; the read settles it
  perform pg_temp.login_as('a');
  v := pg_temp.sch(ca);
  select * into r from kids_school_results where child_id = ca order by id limit 1;
  perform pg_temp.assert(r.attended and r.on_time and r.promoted and r.class_name = 'Nursery 1' and r.avg = 56, 'Nursery 1: fee on time, needs fine: 56 and promoted (' || r.avg || ')');
  s := pg_temp.ks(ca);
  perform pg_temp.assert(s.seq = 2 and s.attempt = 1 and s.class_start is not null and s.fee_paid_at is null and s.max_seq = 2, 'Nursery 2 started when Nursery 1 ended');
  perform pg_temp.assert(s.class_start = (select created_at from kids_school_results where child_id = ca order by id limit 1), 'and at the exact end of Nursery 1, not at the time of the read');
  -- gear: bag and uniform
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_gear(%s, %L)', ca, 'uniform')) = 'no_item', 'no uniform in the bag');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_gear(%s, %L)', ca, 'books')) = 'na', 'nursery has no textbooks');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_gear(%s, %L)', ca, 'shoes')) = 'bad_kind', 'only books or uniform');
  v := pg_temp.sch(ca);
  perform pg_temp.assert(jsonb_array_length(v -> 'gear') = 1 and v -> 'gear' -> 0 ->> 'kind' = 'uniform' and (v -> 'gear' -> 0 ->> 'have')::boolean = false and jsonb_array_length(v -> 'gear' -> 0 -> 'buy') >= 1, 'the app lists the uniform with where to buy it');
  insert into inventory (user_id, item_id, qty) values (pg_temp.u('a'), 'kid_uniform', 2) on conflict (user_id, item_id) do update set qty = 2;
  v_u0 := pg_temp.spent(ca, 'a');
  v := kids_school_gear(ca, 'uniform');
  perform pg_temp.assert((pg_temp.ks(ca)).uniform_stage = 'nursery' and pg_temp.spent(ca, 'a') = v_u0 + 12000 and (select qty from inventory where user_id = pg_temp.u('a') and item_id = 'kid_uniform') = 1, 'uniform given: one used from the bag, 12,000 counted as spend');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_gear(%s, %L)', ca, 'uniform')) = 'done', 'once per stage');
  -- homework: once per parent per class, shared cooldown
  v := kids_school_homework(ca);
  perform pg_temp.assert((v ->> 'helps')::int = 1, 'a helps with homework');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_homework(%s)', ca)) = 'done', 'a only once per class');
  perform pg_temp.login_as('b');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_homework(%s)', ca)) = 'cooldown', 'b has to wait for the shared cooldown');
  perform pg_temp.assert((pg_temp.sch(ca) -> 'homework' ->> 'wait')::int > 0 and not (pg_temp.sch(ca) -> 'homework' ->> 'can')::boolean, 'the app counts it down');
  perform pg_temp.hours(1.1);
  v := kids_school_homework(ca);
  perform pg_temp.assert((v ->> 'helps')::int = 2 and cardinality((pg_temp.ks(ca)).hw_users) = 2, 'b helps after the cooldown');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_homework(%s)', ca)) = 'done', 'b only once too');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_homework(%s)', ca)) = 'done', 'both done');
  -- lessons
  v_u0 := pg_temp.spent(ca, 'a');
  v := kids_school_lessons(ca);
  perform pg_temp.assert(pg_temp.ledger_sum(pg_temp.u('a'), 'kid_school_lessons') = -8000 and pg_temp.spent(ca, 'a') = v_u0 + 8000 and (pg_temp.ks(ca)).lessons_at is not null, 'a tutor: 8,000, a sink, counted as spend');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_lessons(%s)', ca)) = 'done', 'one tutor per class');
  -- the forecast uses all of it: fee unpaid = missed, then paid = 38 + 6 + 12 + 8 + 3 + 8 = 75
  v := pg_temp.sch(ca);
  perform pg_temp.assert((v ->> 'avg_now')::int < 40 and not (v -> 'fee' ->> 'paid')::boolean, 'unpaid: the forecast shows a missed class');
  perform pg_temp.login_as('b');
  perform kids_school_pay(ca);
  v := pg_temp.sch(ca);
  perform pg_temp.assert((v ->> 'avg_now')::int between 70 and 76 and (v -> 'fee' ->> 'on_time')::boolean, 'paid: the forecast is about 75 (' || (v ->> 'avg_now') || ')');
  perform pg_temp.assert(pg_temp.spent(ca, 'b') = 20000 and pg_temp.ledger_sum(pg_temp.u('b'), 'kid_school_fee') = -20000, 'either parent can pay: b paid Nursery 2');
  perform pg_temp.hours(24);
  v := pg_temp.sch(ca);
  select * into r from kids_school_results where child_id = ca order by id desc limit 1;
  perform pg_temp.assert(r.class_name = 'Nursery 2' and r.promoted and r.avg between 62 and 76, 'Nursery 2: homework, uniform and lessons lifted it (' || r.avg || ')');
  perform pg_temp.assert((pg_temp.ks(ca)).seq = 3 and (pg_temp.ks(ca)).class_start is null and v ->> 'state' = 'waiting' and v -> 'class' ->> 'name' = 'Primary 1', 'after Nursery 2 the child waits for Primary (day 8)');
  perform pg_temp.assert((v ->> 'starts_at')::timestamptz = (select born_at from kids_children where id = ca) + interval '8 days', 'Primary 1 starts on day 8, not before');
  -- pass mark: with needs ignored an attended, on-time class averages exactly 44
  perform pg_temp.cfg('kids_school.needs_pts', '0');
  cc := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '5 days 1 hour', 'Pass');
  perform pg_temp.login_as('c');
  perform kids_school_enrol(cc, 'uselu_model');
  perform kids_school_pay(cc);
  perform pg_temp.cfg('kids_school.pass_mark', '45');
  perform pg_temp.hours(24);
  v := pg_temp.sch(cc);
  select * into r from kids_school_results where child_id = cc order by id desc limit 1;
  perform pg_temp.assert(r.attended and r.on_time and r.avg = 44 and not r.promoted and r.attempt = 1, 'attended with an average of 44 under a pass mark of 45: repeat (' || r.avg || ')');
  perform pg_temp.assert((pg_temp.ks(cc)).seq = 1 and (pg_temp.ks(cc)).attempt = 2 and (v -> 'last' ->> 'promoted')::boolean = false, 'repeat: same class, attempt 2');
  perform kids_school_pay(cc);
  perform pg_temp.cfg('kids_school.pass_mark', '44');
  perform pg_temp.hours(24);
  v := pg_temp.sch(cc);
  select * into r from kids_school_results where child_id = cc order by id desc limit 1;
  perform pg_temp.assert(r.avg = 44 and r.promoted and r.attempt = 2, 'an average equal to the pass mark is promoted');
  perform pg_temp.assert((pg_temp.ks(cc)).seq = 2 and (pg_temp.ks(cc)).attempt = 1 and (v -> 'class' ->> 'name') = 'Nursery 2' and (v -> 'last' ->> 'promoted')::boolean, 'promoted to Nursery 2');
  perform pg_temp.assert((select count(*) from kids_school_results where child_id = cc) = 2, 'every try is kept (2 rows)');
  perform pg_temp.cfg('kids_school.needs_pts', '12');
  perform pg_temp.cfg('kids_school.pass_mark', '50');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = cc;

  raise notice 'ok 5: promotion, repeat, homework, gear, lessons';
end $$;

-- ---------- 6. school requests ----------
do $$
declare ce bigint; ce2 bigint; v jsonb; m jsonb; mb jsonb; rq kids_school_requests; v_inst bigint; v_inst_b bigint; r2 kids_school_requests; fun0 numeric; sp0 bigint; n int; v_moment text;
begin
  perform pg_temp.clear(array['a', 'b', 'c', 'd']);
  perform pg_temp.cfg('kids_school.request_pct', '100');
  ce := pg_temp.mkchild(pg_temp.u('e'), pg_temp.u('f'), interval '5 days 1 hour', 'Ada');
  ce2 := pg_temp.mkchild(pg_temp.u('e'), pg_temp.u('f'), interval '5 days 1 hour', 'Bola');
  perform set_config('kd.ce', ce::text, true);
  perform pg_temp.login_as('e');
  perform kids_school_enrol(ce, 'uselu_model');
  perform kids_school_enrol(ce2, 'uselu_model');
  perform kids_school_pay(ce); perform kids_school_pay(ce2);
  perform pg_temp.assert((pg_temp.ks(ce)).req_type in ('pta', 'party') and not (pg_temp.ks(ce)).req_done and (pg_temp.ks(ce)).req_at > bl_now(), 'a request is planned for later in the class (nursery: PTA levy or party)');
  perform pg_temp.assert(jsonb_array_length(moments_pending() -> 'moments') = 0, 'nothing yet');
  perform pg_temp.hours(20);
  perform pg_temp.care(ce, 'e'); perform pg_temp.care(ce2, 'e');
  perform pg_temp.login_as('e');
  v := pg_temp.sch(ce);
  select * into rq from kids_school_requests where child_id = ce;
  perform pg_temp.assert(rq.id is not null and rq.status = 'open' and rq.req_type in ('pta', 'party') and rq.seq = 1 and rq.attempt = 1, 'the request is made (' || coalesce(rq.req_type, '?') || ')');
  perform pg_temp.assert((v -> 'request' ->> 'status') = 'open', 'the app knows');
  -- both parents get the card
  v := moments_pending();
  select x into m from jsonb_array_elements(v -> 'moments') x where (x ->> 'child_id')::bigint = ce limit 1;
  perform pg_temp.login_as('f');
  select x into mb from jsonb_array_elements(moments_pending() -> 'moments') x where (x ->> 'child_id')::bigint = ce limit 1;
  perform pg_temp.assert(m is not null and mb is not null and m ->> 'kind' = 'kids_school' and mb ->> 'kind' = 'kids_school' and (m ->> 'id') <> (mb ->> 'id'), 'both parents get a school card');
  perform pg_temp.assert(m ->> 'moment' = 'school_' || rq.req_type and m ->> 'title' like '%Ada%' and (m -> 'choices' -> 0 ->> 'id') = 'pay' and (m -> 'choices' -> 1 ->> 'id') = 'ignore' and (m -> 'choices' -> 1 ->> 'ignore')::boolean
                         and (m -> 'choices' -> 0 ->> 'cost')::bigint in (6000, 4000) and (m ->> 'snoozes_left')::int > 0, 'Pay / Ignore (and Remind me later), with the cost');
  v_inst := (m ->> 'id')::bigint; v_inst_b := (mb ->> 'id')::bigint;
  -- later
  perform pg_temp.login_as('e');
  v := moments_snooze(v_inst);
  perform pg_temp.assert(not (v ->> 'expired')::boolean, 'Later hides the card');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(moments_pending() -> 'moments') x where (x ->> 'id')::bigint = v_inst), 'not shown while snoozed');
  perform pg_temp.hours(2.1);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(moments_pending() -> 'moments') x where (x ->> 'id')::bigint = v_inst), 'and back after the snooze hours');
  -- the first to pay resolves it
  sp0 := pg_temp.spent(ce, 'e');
  v := moments_answer(v_inst, 'pay');
  perform pg_temp.assert((v ->> 'success')::boolean and (v ->> 'spent')::bigint in (6000, 4000), 'e pays');
  select * into r2 from kids_school_requests where id = rq.id;
  perform pg_temp.assert(r2.status = 'paid' and r2.paid_by = pg_temp.u('e'), 'request paid by e');
  perform pg_temp.assert(pg_temp.ledger_n(pg_temp.u('e'), 'life_moment') >= 1 and pg_temp.spent(ce, 'e') = sp0 + (v ->> 'spent')::bigint, 'ledger life_moment (a sink) and counted as spend');
  perform pg_temp.login_as('f');
  v := moments_pending();
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(v -> 'moments') x where (x ->> 'id')::bigint = v_inst_b), 'f no longer has the card');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v -> 'handled') x where x ->> 'outcome' like 'Already handled by @%'), 'f sees "already handled"');
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_inst_b, 'pay')) = 'already_answered', 'and cannot pay again');
  perform pg_temp.assert(pg_temp.spent(ce, 'f') = 0, 'f paid nothing');
  -- ignore: it takes BOTH parents to ignore before the child pays for it
  perform pg_temp.login_as('e');
  select * into rq from kids_school_requests where child_id = ce2;
  perform pg_temp.assert(rq.id is not null, 'the second child has a request too');
  select (x ->> 'id')::bigint into v_inst from jsonb_array_elements(moments_pending() -> 'moments') x where (x ->> 'child_id')::bigint = ce2 limit 1;
  select fun into fun0 from kids_children where id = ce2;
  v := moments_answer(v_inst, 'ignore');
  select * into r2 from kids_school_requests where id = rq.id;
  perform pg_temp.assert(r2.status = 'open' and cardinality(r2.ignores) = 1 and (pg_temp.ks(ce2)).penalty = 0, 'one parent ignoring: still open, no penalty yet');
  perform pg_temp.login_as('f');
  select (x ->> 'id')::bigint into v_inst_b from jsonb_array_elements(moments_pending() -> 'moments') x where (x ->> 'child_id')::bigint = ce2 limit 1;
  perform pg_temp.assert(v_inst_b is not null, 'f still has the card');
  v := moments_answer(v_inst_b, 'ignore');
  select * into r2 from kids_school_requests where id = rq.id;
  perform pg_temp.assert(r2.status = 'ignored' and (pg_temp.ks(ce2)).penalty = 4 and (select fun from kids_children where id = ce2) < fun0, 'both ignored: grades -4 for the class and the child is sadder');
  -- one request per child per class (the next class starts at this read: pin the random draw so its request is planned late in the class, after the cap test below)
  perform set_config('bl.test_rand', '0.9', true);
  perform pg_temp.hours(6);
  perform pg_temp.login_as('e'); perform pg_temp.sch(ce); perform pg_temp.sch(ce2);
  select count(*) into n from kids_school_requests where child_id = ce and seq = 1 and attempt = 1;
  perform pg_temp.assert(n = 1, 'at most one request per child per class');
  perform pg_temp.assert(not exists (select 1 from player_moments m where m.context ->> 'req_id' in (select q.id::text from kids_school_requests q where q.child_id in (ce, ce2) and q.seq = 1) and m.status in ('pending', 'snoozed', 'scheduled')), 'the class is over: no card of its requests is left open');
  -- the daily cap of life moments is respected: no request is made
  perform pg_temp.cfg('moments.daily_cap', '0');
  perform pg_temp.assert((pg_temp.ks(ce)).seq = 2, 'ce is in Nursery 2');
  perform pg_temp.login_as('e'); perform kids_school_pay(ce);
  perform pg_temp.hours(23);
  perform pg_temp.care(ce, 'e');
  perform pg_temp.sch(ce);
  perform pg_temp.assert(not exists (select 1 from kids_school_requests where child_id = ce and seq = 2), 'under the daily cap: no request in that class');
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.cfg('moments.daily_cap', '100');
  perform pg_temp.cfg('kids_school.request_pct', '0');
  raise notice 'ok 6: school requests';
end $$;

-- ---------- 7. the sweep ----------
do $$
declare cs bigint; v_next timestamptz; s kids_school; n int;
begin
  perform pg_temp.clear(array['e', 'f']);
  cs := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '5 days 1 hour', 'Sweepy');
  perform pg_temp.login_as('c');
  perform kids_school_enrol(cs, 'uselu_model');
  perform kids_school_pay(cs);
  s := pg_temp.ks(cs);
  select next_alert_at into v_next from kids_children where id = cs;
  perform pg_temp.assert(v_next is not null and v_next <= s.class_start + interval '24 hours' + interval '1 second' and v_next >= bl_now(), 'next_alert_at holds the next school moment (' || v_next || ')');
  perform pg_temp.hours(25);
  perform pg_temp.assert((select count(*) from kids_school_results where child_id = cs) = 0, 'nothing is written until somebody looks or the sweep runs');
  perform bl_kids_alert_sweep();
  perform pg_temp.assert((select count(*) from kids_school_results where child_id = cs) = 1 and (pg_temp.ks(cs)).seq = 2, 'the sweep closed the class without anybody reading');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('c'), 'kids_school_result') >= 1, 'and told the parents');
  perform pg_temp.assert((select next_alert_at from kids_children where id = cs) > bl_now() - interval '1 second', 'the next due moment moved on');
  raise notice 'ok 7: the sweep';
end $$;

create or replace function pg_temp.age_days(p_child bigint) returns numeric language sql as $$ select extract(epoch from (bl_now() - born_at)) / 86400 from kids_children where id = p_child $$;
create or replace function pg_temp.run_to(p_child bigint, p_a text, p_b text, p_age numeric, p_pay boolean default true, p_uni text default 'uniben') returns void
language plpgsql as $$
begin
  while pg_temp.age_days(p_child) < p_age loop
    perform pg_temp.advance(3 * 3600);
    perform pg_temp.care(p_child, p_a);
    perform pg_temp.tend(p_child, p_a, p_b, p_pay, p_uni);
  end loop;
end $$;
create or replace function pg_temp.kid_of(p_id bigint) returns kids_children language sql as $$ select * from kids_children where id = p_id $$;

-- ---------- 8. a whole school life: a and b ----------
do $$
declare cj bigint; v jsonb; r kids_school_results; s kids_school; n int; c kids_children; v_in bigint; vb jsonb; m jsonb; mb jsonb; v_g0 bigint; rc kids_report_cards; v_course text; v_uni_avg numeric; v_spent_a bigint;
begin
  perform pg_temp.clear(array['c', 'd', 'e', 'f']);
  perform pg_temp.cfg('kids_school.talent_pts', '0');
  perform pg_temp.cfg('kids_school.request_pct', '0');
  cj := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '5 days 1 hour', 'Osas');
  perform set_config('kd.cj', cj::text, true);
  perform pg_temp.login_as('a');
  perform kids_school_enrol(cj, 'uselu_model');
  -- Nursery 1-2 on days 5-7, then Primary waits for day 8
  perform pg_temp.run_to(cj, 'a', 'b', 7.5);
  v := pg_temp.sch(cj);
  perform pg_temp.assert((select count(*) from kids_school_results where child_id = cj and level = 'nursery' and promoted) = 2 and (pg_temp.ks(cj)).seq = 3, 'Nursery 1 and 2 are done by day 7.5');
  perform pg_temp.assert(v ->> 'state' = 'waiting' and v -> 'class' ->> 'name' = 'Primary 1' and (v ->> 'starts_at')::timestamptz = (pg_temp.kid_of(cj)).born_at + interval '8 days', 'Primary 1 waits for day 8');
  select * into rc from kids_report_cards where child_id = cj and stage_key = 'nursery';
  perform pg_temp.assert(rc.id is not null and jsonb_array_length(rc.grades) = 3 and rc.promoted and rc.position in ('Excellent', 'Very good', 'Good', 'Needs help') and rc.teacher <> '' and rc.remark like '%Osas%' and rc.title = 'Nursery report card'
                         and rc.school_name = 'Uselu Model Nursery & Primary School', 'the Nursery report card: three subjects, position, remark with the name, teacher, school (' || rc.position || ')');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_report') >= 1, 'a is told the report card is ready');
  perform pg_temp.run_to(cj, 'a', 'b', 8.3);
  s := pg_temp.ks(cj);
  perform pg_temp.assert(s.seq = 3 and s.class_start = (pg_temp.kid_of(cj)).born_at + interval '8 days', 'Primary 1 started on the stroke of day 8');
  -- primary: textbooks and bag
  insert into inventory (user_id, item_id, qty) values (pg_temp.u('a'), 'kid_books_primary', 1) on conflict (user_id, item_id) do update set qty = 1;
  perform pg_temp.login_as('a');
  v := pg_temp.sch(cj);
  perform pg_temp.assert(jsonb_array_length(v -> 'gear') = 2 and exists (select 1 from jsonb_array_elements(v -> 'gear') x where x ->> 'kind' = 'books' and (x ->> 'have')::boolean) and exists (select 1 from jsonb_array_elements(v -> 'gear') x where x ->> 'kind' = 'uniform' and (x ->> 'applied')::boolean = false), 'primary shows textbooks (owned) and the uniform (not applied for primary yet)');
  perform kids_school_gear(cj, 'books');
  perform pg_temp.assert((pg_temp.ks(cj)).books_stage = 'primary' and pg_temp.hint_of(format('select kids_school_gear(%s, %L)', cj, 'books')) = 'done', 'textbooks given for the whole of primary');
  -- primary to day 13.9, then Primary 6 ends and secondary needs another school
  perform pg_temp.run_to(cj, 'a', 'b', 13.9);
  perform pg_temp.assert((pg_temp.sch(cj) -> 'class' ->> 'name') = 'Primary 6' and (pg_temp.ks(cj)).seq = 8, 'day 13.9: Primary 6');
  perform pg_temp.advance(0.25 * 86400);
  perform pg_temp.care(cj, 'a');
  perform pg_temp.login_as('a');
  v := pg_temp.sch(cj);
  perform pg_temp.assert(v ->> 'state' = 'need_school' and v -> 'class' ->> 'name' = 'JSS 1' and v -> 'class' ->> 'level' = 'secondary', 'Uselu teaches no secondary: the child needs a new school');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_school_pick') = 1, 'both parents are told to pick one');
  perform pg_temp.assert((select count(*) from kids_report_cards where child_id = cj) = 2 and exists (select 1 from kids_report_cards where child_id = cj and stage_key = 'primary' and jsonb_array_length(grades) = 4), 'the Primary report card has four subjects');
  v := kids_school_schools(cj);
  perform pg_temp.assert(v ->> 'level' = 'secondary' and jsonb_array_length(v -> 'schools') = 3 and (v -> 'schools' -> 0 ->> 'id') = 'ugbowo_grammar', 'three secondary schools, cheapest first');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_enrol(%s, %L)', cj, 'uselu_model')) = 'wrong_level', 'not Uselu again');
  perform kids_school_enrol(cj, 'ugbowo_grammar');
  perform pg_temp.assert((pg_temp.ks(cj)).class_start is not null and (pg_temp.ks(cj)).class_start = (pg_temp.kid_of(cj)).born_at + interval '14 days', 'JSS 1 started at day 14 as soon as a school was chosen');
  -- secondary: JSS 1-3 on days 14-17, SSS 1-3 on days 17-20
  perform pg_temp.run_to(cj, 'a', 'b', 19.4);
  v := pg_temp.sch(cj);
  perform pg_temp.assert(v -> 'class' ->> 'name' = 'SSS 3' and (select count(*) from kids_report_cards where child_id = cj) = 3, 'day 19.4: SSS 3, three report cards (nursery, primary, JSS)');
  perform pg_temp.assert(exists (select 1 from kids_school_requests where child_id = cj and req_type = 'waec') or (pg_temp.ks(cj)).req_type = 'waec', 'SSS 3 comes with the WAEC fee request');
  perform pg_temp.run_to(cj, 'a', 'b', 19.95);
  raise notice 'ok 8a: days 5-20';
end $$;

do $$
declare cj bigint := current_setting('kd.cj')::bigint; v jsonb; r kids_school_results; s kids_school; n int; c kids_children; m jsonb; mb jsonb; rc kids_report_cards; v_course text; v_uni_avg numeric; v_in bigint; vb jsonb;
  v_spent_a bigint; v_ledger_a bigint; v_ua text; v_ub text; v_pa uuid; v_pb uuid; w jsonb;
begin
  -- the WAEC fee request was paid by whoever answered first, the other card is "already handled"
  perform pg_temp.assert(exists (select 1 from kids_school_requests where child_id = cj and req_type = 'waec' and status = 'paid'), 'the WAEC registration fee was paid');
  perform pg_temp.assert(exists (select 1 from player_moments where moment_id = 'school_waec' and user_id = pg_temp.u('b') and handled_by is not null and outcome like 'Already handled by @%')
                         or exists (select 1 from player_moments where moment_id = 'school_waec' and user_id = pg_temp.u('a') and handled_by is not null), 'and the other parent''s card was handled');
  -- WAEC at the end of SSS 3 (day 20)
  perform pg_temp.run_to(cj, 'a', 'b', 20.15);
  perform pg_temp.login_as('a');
  v := pg_temp.sch(cj);
  w := v -> 'waec';
  perform pg_temp.assert(v ->> 'state' = 'finished' and w is not null and (w ->> 'pass')::boolean and jsonb_array_length(w -> 'papers') = 9 and (w ->> 'credits')::int >= 5
                         and (w ->> 'text') = (w ->> 'credits') || ' credits including Maths and English', 'WAEC passed: ' || (w ->> 'text'));
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(w -> 'papers') x where x ->> 'name' = 'Mathematics' and (x ->> 'credit')::boolean) and exists (select 1 from jsonb_array_elements(w -> 'papers') x where x ->> 'name' = 'English Language' and (x ->> 'credit')::boolean)
                         and not exists (select 1 from jsonb_array_elements(w -> 'papers') x where (x ->> 'letter') !~ '^[A-F][1-9]$'), 'Maths and English credited, letters like B2 / C4');
  select * into rc from kids_report_cards where child_id = cj and stage_key = 'sss';
  perform pg_temp.assert(rc.id is not null and rc.extra like 'WAEC: % credits including Maths and English' and jsonb_array_length(rc.grades) = 5 and (select count(*) from kids_report_cards where child_id = cj) = 4, 'the SSS report card carries the WAEC line (4 cards so far)');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_waec') >= 1 and (select (pg_temp.kid_of(cj)).status) = 'home', 'WAEC alert, and the child is still at home until day 21');
  perform pg_temp.assert((select count(*) from kids_school_results where child_id = cj and level = 'secondary' and promoted) = 6, 'six secondary classes passed');
  -- day 21: the university decision for BOTH parents (nobody answers yet)
  perform pg_temp.run_to(cj, 'a', 'b', 21.05, true, '');
  c := pg_temp.kid_of(cj);
  perform pg_temp.assert(c.status = 'university' and (pg_temp.ks(cj)).uni_state = 'deciding' and c.grown_at is null, 'day 21 with a WAEC pass: status university (deciding), not moved out yet');
  perform pg_temp.login_as('a');
  select x into m from jsonb_array_elements(moments_pending() -> 'moments') x where x ->> 'moment' = 'uni_decision' limit 1;
  perform pg_temp.login_as('b');
  select x into mb from jsonb_array_elements(moments_pending() -> 'moments') x where x ->> 'moment' = 'uni_decision' limit 1;
  perform pg_temp.assert(m is not null and mb is not null and m ->> 'kind' = 'kids_uni' and m ->> 'title' like 'Send Osas to university?', 'both parents get "Send Osas to university?"');
  perform pg_temp.assert((m -> 'choices' -> 0 ->> 'id') = 'uniben' and (m -> 'choices' -> 0 ->> 'label') = 'UNIBEN · ₦60,000' and (m -> 'choices' -> 1 ->> 'label') = 'Edo Royal · ₦400,000' and (m -> 'choices' -> 2 ->> 'id') = 'work', 'UNIBEN, Edo Royal University with their fees per level, or work');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(moments_pending() -> 'moments') x where x ->> 'kind' = 'kids_school'), 'no school card is left');
  -- the child at university: simple needs (pocket money, attention), no diapers or toys
  perform pg_temp.login_as('a');
  v := pg_temp.cj(cj);
  perform pg_temp.assert(v ->> 'status' = 'university' and (v -> 'stage' ->> 'id') = 'university' and (v -> 'needs') ?& array['hunger', 'love'] and not (v -> 'needs') ? 'sleep' and v -> 'actions' ? 'feed' and v -> 'actions' ? 'cuddle'
                         and not v -> 'actions' ? 'change' and not v -> 'actions' ? 'play' and not v -> 'actions' ? 'medicine', 'university needs and actions: pocket money and attention only');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_care(%s, %L)', cj, 'play')) <> 'ok' and (v -> 'actions' -> 'feed' ->> 'cost')::bigint in (0, 6000), 'play is not for a student; pocket money costs the setting when due');
  perform pg_temp.assert(v -> 'school' ->> 'state' = 'deciding', 'the app says the parents are deciding');
  -- b chooses UNIBEN; a sees "already handled"
  perform pg_temp.login_as('b');
  v := moments_answer((mb ->> 'id')::bigint, 'uniben');
  perform pg_temp.assert((v ->> 'success')::boolean and (v ->> 'outcome') like '%UNIBEN%', 'b chooses UNIBEN');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(moments_pending() -> 'handled') x where x ->> 'outcome' like 'Already handled by @%') and pg_temp.hint_of(format('select moments_answer(%s, %L)', (m ->> 'id')::bigint, 'work')) = 'already_answered', 'a sees "already handled" and cannot pick again');
  s := pg_temp.ks(cj);
  perform pg_temp.assert(s.uni_state = 'studying' and s.uni_level = 1 and s.school_id = 'uniben' and s.fee_amount = 60000 and s.uni_course is not null and s.fee_paid_at is null, '100L at UNIBEN, fee 60,000 per level, a course');
  v := pg_temp.sch(cj);
  perform pg_temp.assert(v ->> 'state' = 'university' and v -> 'uni' ->> 'level_name' = '100L' and v -> 'school' ->> 'name' = 'UNIBEN' and not (v -> 'fee' ->> 'paid')::boolean and jsonb_array_length(v -> 'grades') = 2
                         and v -> 'grades' -> 0 ->> 'name' = 'Course work' and v -> 'grades' -> 1 ->> 'name' = 'Exams', 'the app shows level, school, unpaid fee and Course work / Exams');
  v_course := s.uni_course;
  -- 100L to 400L, one level a day; either parent pays (a pays in tend)
  perform pg_temp.run_to(cj, 'a', 'b', 22.3, true, '');
  perform pg_temp.assert((pg_temp.ks(cj)).uni_level = 2 and (select count(*) from kids_school_results where child_id = cj and level = 'university' and promoted) = 1, '100L passed, now 200L');
  perform pg_temp.assert(pg_temp.ledger_sum(pg_temp.u('a'), 'kid_school_fee') <= -60000, 'university fees go through kid_school_fee too');
  -- give the parents a big spend on this child, to see the gift tiers and the cap
  select spent_a, spent_b into n, v_spent_a from kids_children where id = cj;
  update kids_children set spent_a = case when parent_a = pg_temp.u('a') then 5000000 else 100000 end, spent_b = case when parent_b = pg_temp.u('a') then 5000000 else 100000 end where id = cj;
  v_ledger_a := pg_temp.ledger_sum(pg_temp.u('a'), 'kid_gift');
  perform pg_temp.run_to(cj, 'a', 'b', 25.4, true, '');
  c := pg_temp.kid_of(cj);
  s := pg_temp.ks(cj);
  perform pg_temp.assert(c.status = 'grown' and c.grown_at is not null and s.uni_state = 'graduated' and (select count(*) from kids_school_results where child_id = cj and level = 'university' and promoted) = 4, 'four levels passed: graduated and moved out');
  select avg(avg) into v_uni_avg from kids_school_results where child_id = cj and level = 'university' and promoted;
  perform pg_temp.assert(s.uni_degree = bl_kids_degree(v_uni_avg) and s.uni_degree = 'Second Class Lower', 'degree class from the university grades: ' || s.uni_degree || ' (avg ' || round(v_uni_avg, 1) || ')');
  perform pg_temp.assert(c.outcome = 'Graduated from UNIBEN with ' || s.uni_degree || ' in ' || v_course, 'outcome line: ' || c.outcome);
  perform pg_temp.assert(c.tier = 'graduate' and c.care_score is not null, 'the top tier: Graduate');
  select * into rc from kids_report_cards where child_id = cj and stage_key = 'university';
  perform pg_temp.assert(rc.id is not null and rc.extra = s.uni_degree || ' in ' || v_course and (select count(*) from kids_report_cards where child_id = cj) = 5, 'five report cards: nursery, primary, JSS, SSS, university');
  -- the thank-you gift: the Graduate amount, capped by the share each parent spent
  v_pa := c.parent_a; v_pb := c.parent_b;
  perform pg_temp.assert((case when v_pa = pg_temp.u('a') then c.gift_a else c.gift_b end) = 250000 and (case when v_pa = pg_temp.u('a') then c.gift_b else c.gift_a end) = 25000, 'gift: 250,000 for the parent who spent 5,000,000, 25 % of 100,000 for the other (' || c.gift_a || ' / ' || c.gift_b || ')');
  perform pg_temp.assert((select coalesce(sum(delta), 0) from ledger where user_id = pg_temp.u('a') and reason = 'kid_gift') = 250000 and (select coalesce(sum(delta), 0) from ledger where user_id = pg_temp.u('b') and reason = 'kid_gift') = 25000, 'ledger kid_gift paid');
  perform pg_temp.assert(not ('kid_gift' = any (bl_earn_reasons())), 'never earnings');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'kids_grown') >= 1 and (select data ->> 'outcome' from events where user_id = pg_temp.u('a') and kind = 'kids_grown' order by id desc limit 1) = c.outcome, 'the keepsake alert carries the outcome line');
  -- the Family tab lists the grown child with the outcome and the badge tier; the public profile shows Graduate
  perform pg_temp.login_as('a');
  v := kids_status();
  perform pg_temp.assert((v -> 'grown' -> 0 ->> 'outcome') = c.outcome and (v -> 'grown' -> 0 ->> 'tier') = 'graduate' and (v -> 'grown' -> 0 ->> 'cards')::int = 5, 'kids_status: grown list with outcome, tier and report card count');
  update profiles set show_relationship = true where id in (pg_temp.u('a'), pg_temp.u('b'));
  perform pg_temp.assert(get_public_profile(pg_temp.u('a'))->>'proud_tier' = 'graduate', 'the public profile shows the Graduate tier above Gold');
  perform pg_temp.assert(jsonb_array_length((kids_report_cards(cj)) -> 'cards') = 5 and (kids_report_cards(cj) -> 'cards' -> 0 ->> 'stage') = 'university', 'the report cards list (newest first)');
  raise notice 'ok 8b: WAEC, university decision, levels, graduation, outcome, gift, Graduate tier';
end $$;

-- ---------- 9. WAEC failed: no university, the child just moves out ----------
do $$
declare ck bigint; v jsonb; c kids_children; w jsonb; rc kids_report_cards; v_spent bigint; v_gift bigint;
begin
  perform pg_temp.clear(array['a', 'b']);
  perform pg_temp.cfg('kids_school.waec_credit_mark', '100');
  ck := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '5 days 1 hour', 'Tobi');
  perform pg_temp.login_as('c');
  perform kids_school_enrol(ck, 'uselu_model');
  perform pg_temp.run_to(ck, 'c', 'd', 20.2);
  perform pg_temp.login_as('c');
  v := pg_temp.sch(ck);
  w := v -> 'waec';
  perform pg_temp.assert(not (w ->> 'pass')::boolean and (w ->> 'text') = 'fewer than 5 credits' and (w ->> 'credits')::int = 0 and v ->> 'state' = 'finished', 'WAEC failed: fewer than 5 credits');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(w -> 'papers') x where (x ->> 'credit')::boolean) and exists (select 1 from jsonb_array_elements(w -> 'papers') x where x ->> 'letter' in ('D7', 'E8', 'F9')), 'no credits, letters D7 to F9');
  select * into rc from kids_report_cards where child_id = ck and stage_key = 'sss';
  perform pg_temp.assert(rc.extra = 'WAEC: fewer than 5 credits' and rc.promoted, 'the SSS report card says so (SSS 3 itself was passed)');
  perform pg_temp.run_to(ck, 'c', 'd', 21.2);
  c := pg_temp.kid_of(ck);
  perform pg_temp.assert(c.status = 'grown' and c.outcome = 'Sat WAEC but did not get enough credits (0)', 'day 21: moves out at once: ' || coalesce(c.outcome, '?'));
  perform pg_temp.assert(not exists (select 1 from player_moments where moment_id = 'uni_decision' and user_id in (pg_temp.u('c'), pg_temp.u('d'))), 'no university card');
  perform pg_temp.assert(c.tier in ('gold', 'silver', 'bronze') and c.tier <> 'graduate', 'the care tier, not Graduate (' || c.tier || ')');
  -- the gift counts school fees: far above what care alone could ever reach before
  v_spent := pg_temp.spent(ck, 'c');
  v_gift := case when c.parent_a = pg_temp.u('c') then c.gift_a else c.gift_b end;
  perform pg_temp.assert(v_spent >= 300000 and v_gift = least(case c.tier when 'gold' then 100000 when 'silver' then 50000 else 20000 end, floor(v_spent * 0.25)) and v_gift >= 50000,
                         'school fees count as spend, so the tier gift is reachable: spent ' || v_spent || ', gift ' || v_gift || ' (' || c.tier || ')');
  perform pg_temp.assert((select count(*) from kids_report_cards where child_id = ck) = 4, 'four report cards (no university)');
  perform pg_temp.cfg('kids_school.waec_credit_mark', '50');
  raise notice 'ok 9: WAEC fail';
end $$;

-- ---------- 10. university: an unpaid level is missed; two repeats, then drop out ----------
do $$
declare cm bigint; v jsonb; c kids_children; s kids_school; mb jsonb; rc kids_report_cards; n int; v_course text;
begin
  perform pg_temp.clear(array['c', 'd']);
  cm := pg_temp.mkchild(pg_temp.u('e'), pg_temp.u('f'), interval '5 days 1 hour', 'Kemi');
  perform pg_temp.login_as('e');
  perform kids_school_enrol(cm, 'uselu_model');
  perform pg_temp.run_to(cm, 'e', 'f', 21.05, true, '');
  perform pg_temp.login_as('f');
  select x into mb from jsonb_array_elements(moments_pending() -> 'moments') x where x ->> 'moment' = 'uni_decision' limit 1;
  perform pg_temp.assert(mb is not null and (pg_temp.kid_of(cm)).status = 'university', 'the decision card is there');
  v := moments_answer((mb ->> 'id')::bigint, 'edo_royal');
  s := pg_temp.ks(cm);
  perform pg_temp.assert(s.school_id = 'edo_royal_university' and s.fee_amount = 400000 and s.uni_state = 'studying', 'Edo Royal University: 400,000 a level');
  v_course := s.uni_course;
  perform pg_temp.login_as('e');
  perform pg_temp.assert((pg_temp.sch(cm) -> 'fee' ->> 'can_pay')::boolean and (pg_temp.sch(cm) -> 'fee' ->> 'amount')::bigint = 400000, 'the fee is open to pay');
  -- nobody pays: 100L is missed
  perform pg_temp.run_to(cm, 'e', 'f', 22.2, false, '');
  s := pg_temp.ks(cm);
  perform pg_temp.assert(s.uni_level = 1 and s.uni_repeats = 1 and s.uni_state = 'studying' and (select count(*) from kids_school_results where child_id = cm and level = 'university' and not attended) = 1, '100L missed: repeats (1 of 2)');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('e'), 'kids_uni_result') >= 1, 'the parents are told');
  perform pg_temp.run_to(cm, 'e', 'f', 23.2, false, '');
  perform pg_temp.assert((pg_temp.ks(cm)).uni_repeats = 2 and (pg_temp.kid_of(cm)).status = 'university', 'second repeat');
  perform pg_temp.run_to(cm, 'e', 'f', 24.6, false, '');
  c := pg_temp.kid_of(cm);
  s := pg_temp.ks(cm);
  perform pg_temp.assert(c.status = 'grown' and s.uni_state = 'dropped' and s.uni_repeats = 2, 'after the repeats allowed, the next failure drops out and the child moves out');
  perform pg_temp.assert(c.outcome = 'Didn''t finish university (Edo Royal University, ' || v_course || ')', 'outcome: ' || c.outcome);
  select * into rc from kids_report_cards where child_id = cm and stage_key = 'university';
  perform pg_temp.assert(rc.id is not null and not rc.promoted and rc.extra = 'Left university in 100L', 'a university report card with the failure');
  perform pg_temp.assert(abs(pg_temp.ledger_sum(pg_temp.u('e'), 'kid_school_fee')) < 400000 and abs(pg_temp.ledger_sum(pg_temp.u('f'), 'kid_school_fee')) < 400000, 'the university fee was never charged');
  perform pg_temp.assert(c.tier <> 'graduate', 'no Graduate tier for a drop-out');
  raise notice 'ok 10: university repeats and drop-out';
end $$;

-- ---------- 11. work: chosen by a parent, or by nobody answering ----------
do $$
declare c1 bigint; c2 bigint; v jsonb; c kids_children; mb jsonb; ma jsonb; n int; s kids_school; i int;
begin
  perform pg_temp.clear(array['e', 'f']);
  c1 := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '5 days 1 hour', 'Nosa');
  c2 := pg_temp.mkchild(pg_temp.u('a'), pg_temp.u('b'), interval '5 days 1 hour', 'Ivie');
  perform pg_temp.login_as('a');
  perform kids_school_enrol(c1, 'uselu_model'); perform kids_school_enrol(c2, 'uselu_model');
  while pg_temp.age_days(c1) < 21.05 loop
    perform pg_temp.advance(3 * 3600);
    perform pg_temp.care(c1, 'a'); perform pg_temp.care(c2, 'a');
    perform pg_temp.tend(c1, 'a', 'b', true, ''); perform pg_temp.tend(c2, 'a', 'b', true, '');
  end loop;
  perform pg_temp.assert((pg_temp.kid_of(c1)).status = 'university' and (pg_temp.kid_of(c2)).status = 'university', 'both are deciding');
  -- c1: the parent picks "Let them start working"
  perform pg_temp.login_as('a');
  select x into ma from jsonb_array_elements(moments_pending() -> 'moments') x where (x ->> 'child_id')::bigint = c1 and x ->> 'moment' = 'uni_decision';
  perform pg_temp.assert((ma -> 'choices' -> 2 ->> 'id') = 'work' and (ma -> 'choices' -> 2 ->> 'ignore')::boolean, 'work is the free "ignore" choice of the card');
  v := moments_answer((ma ->> 'id')::bigint, 'work');
  c := pg_temp.kid_of(c1);
  perform pg_temp.assert(c.status = 'grown' and c.outcome like 'Got % credits in WAEC and started work' and (pg_temp.ks(c1)).uni_state = 'working' and c.tier in ('gold', 'silver', 'bronze', 'none'), 'work: moved out: ' || c.outcome);
  perform pg_temp.login_as('b');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(moments_pending() -> 'moments') x where (x ->> 'child_id')::bigint = c1), 'the other parent''s card is closed');
  -- c2: nobody answers for 36 hours: work
  perform pg_temp.hours(30);
  perform pg_temp.login_as('a'); perform pg_temp.sch(c2);
  perform pg_temp.assert((pg_temp.kid_of(c2)).status = 'university', 'still deciding after 30 hours');
  perform pg_temp.hours(7);
  perform pg_temp.login_as('a'); perform pg_temp.sch(c2);
  c := pg_temp.kid_of(c2);
  perform pg_temp.assert(c.status = 'grown' and c.outcome like 'Got % credits in WAEC and started work' and (pg_temp.ks(c2)).uni_state = 'working', 'no answer in 36 hours: the child starts working');
  perform pg_temp.assert(not exists (select 1 from player_moments where moment_id = 'uni_decision' and (context ->> 'child_id') = c2::text and status in ('pending', 'snoozed', 'scheduled')), 'no card is left open');
  perform pg_temp.assert(c.gift_a is not null and c.gift_b is not null and c.care_score is not null, 'badge and gift were settled');
  raise notice 'ok 11: work choice and timeout';
end $$;

-- ---------- 12. outcome lines ----------
do $$
declare v_id bigint; r text;
begin
  perform pg_temp.clear(array['a', 'b']);
  create or replace function pg_temp.out(p_max int, p_waec jsonb, p_uni text, p_deg text, p_school text, p_course text) returns text language plpgsql as $f$
  declare v bigint; o text;
  begin
    v := pg_temp.mkchild(pg_temp.u('e'), pg_temp.u('f'), interval '1 hour', 'Outy');
    if p_max >= 0 then
      insert into kids_school (child_id, school_id, seq, max_seq, waec, uni_state, uni_degree, uni_course) values (v, p_school, greatest(p_max, 1), p_max, p_waec, p_uni, p_deg, p_course);
    end if;
    o := bl_kids_outcome(pg_temp.kid_of(v));
    update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = v;
    return o;
  end $f$;
  perform pg_temp.assert(pg_temp.out(-1, null, null, null, null, null) = 'Moved out without going to school', 'never enrolled');
  perform pg_temp.assert(pg_temp.out(2, null, null, null, 'uselu_model', null) = 'Only went as far as Nursery 2', 'nursery only');
  perform pg_temp.assert(pg_temp.out(5, null, null, null, 'uselu_model', null) = 'Didn''t finish primary school (reached Primary 3)', 'left in primary');
  perform pg_temp.assert(pg_temp.out(10, null, null, null, 'ugbowo_grammar', null) = 'Didn''t finish secondary school (reached JSS 2)', 'left in secondary');
  perform pg_temp.assert(pg_temp.out(13, null, null, null, 'ugbowo_grammar', null) = 'Didn''t finish secondary school (reached SSS 2)', 'left in SSS 2');
  perform pg_temp.assert(pg_temp.out(14, '{"pass":true,"credits":7,"text":"7 credits including Maths and English"}', null, null, 'ugbowo_grammar', null) = 'Got 7 credits in WAEC and started work', 'WAEC pass, work');
  perform pg_temp.assert(pg_temp.out(14, '{"pass":false,"credits":3,"text":"fewer than 5 credits"}', null, null, 'ugbowo_grammar', null) = 'Sat WAEC but did not get enough credits (3)', 'WAEC fail');
  perform pg_temp.assert(pg_temp.out(14, '{"pass":true,"credits":8}', 'graduated', 'First Class', 'uniben', 'Medicine') = 'Graduated from UNIBEN with First Class in Medicine', 'graduated');
  perform pg_temp.assert(pg_temp.out(14, '{"pass":true,"credits":8}', 'dropped', null, 'edo_royal_university', 'Law') = 'Didn''t finish university (Edo Royal University, Law)', 'dropped out');
  raise notice 'ok 12: outcome lines';
end $$;

-- ---------- 13. switches and admin ----------
do $$
declare cx bigint; cu bigint; v jsonb; c kids_children; n int; s kids_school;
begin
  -- school off: nothing can be enrolled or paid, and the app shows no school block
  perform pg_temp.clear(array['e', 'f']);
  cx := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '5 days 1 hour', 'Offy');
  perform pg_temp.cfg('kids_school.enabled', 'false');
  perform pg_temp.login_as('c');
  perform pg_temp.assert(pg_temp.hint_of(format('select kids_school_enrol(%s, %L)', cx, 'uselu_model')) = 'school_off', 'enrol is refused when school is off');
  perform pg_temp.assert(pg_temp.cj(cx) ? 'school' and pg_temp.cj(cx) -> 'school' = 'null'::jsonb, 'no school block');
  perform pg_temp.cfg('kids_school.enabled', 'true');
  perform kids_school_enrol(cx, 'uselu_model');
  perform pg_temp.assert((pg_temp.ks(cx)).class_start is not null, 'and works again when it is back on');
  update kids_children set status = 'gone', gone_reason = 'admin', next_alert_at = null where id = cx;
  -- university off: a WAEC pass just moves out at day 21
  cu := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '20 days 22 hours', 'Uni');
  insert into kids_school (child_id, school_id, seq, max_seq, state, waec, ready_at) values (cu, 'ugbowo_grammar', 14, 14, 'finished', '{"pass":true,"credits":6,"text":"6 credits including Maths and English"}', bl_now() - interval '1 day');
  perform pg_temp.cfg('kids_school.uni_enabled', 'false');
  perform pg_temp.hours(3);
  perform pg_temp.login_as('c'); perform pg_temp.sch(cu);
  c := pg_temp.kid_of(cu);
  perform pg_temp.assert(c.status = 'grown' and c.outcome = 'Got 6 credits in WAEC and started work', 'university off: moved out with the WAEC outcome');
  perform pg_temp.cfg('kids_school.uni_enabled', 'true');
  cu := pg_temp.mkchild(pg_temp.u('c'), pg_temp.u('d'), interval '20 days 22 hours', 'Unia');
  insert into kids_school (child_id, school_id, seq, max_seq, state, waec, ready_at) values (cu, 'ugbowo_grammar', 14, 14, 'finished', '{"pass":true,"credits":6,"text":"6 credits including Maths and English"}', bl_now() - interval '1 day');
  perform pg_temp.hours(3);
  perform pg_temp.login_as('c'); perform pg_temp.sch(cu);
  perform pg_temp.assert((pg_temp.kid_of(cu)).status = 'university' and (pg_temp.ks(cu)).uni_state = 'deciding', 'university on: the decision comes');
  -- a pause with the kids switch moves the school clocks too
  perform pg_temp.cfg('moments.enabled', 'false');
  -- admin overview
  perform pg_temp.login_as('adm');
  perform pg_temp.assert((admin_kids_overview() -> 'children') @> jsonb_build_array(jsonb_build_object('id', cu)), 'Admin lists a child at university');
  v := admin_kids_overview();
  perform pg_temp.assert(v ? 'at_school' and v ? 'university' and v ? 'graduated' and v ? 'dropped_uni' and v ? 'waec_passed' and (v ->> 'graduated')::int >= 1 and (v ->> 'dropped_uni')::int >= 1 and (v ->> 'university')::int >= 1 and (v ->> 'waec_passed')::int >= 2,
                         'Admin: kids at school, at university, graduated, dropped out, WAEC passed');
  perform pg_temp.login_as('c');
  perform pg_temp.assert(pg_temp.hint_of('select admin_kids_overview()') <> 'ok', 'not for players');
  perform pg_temp.login_as('adm');
  perform admin_kids_remove(cu, 'test');
  perform pg_temp.assert((pg_temp.kid_of(cu)).status = 'gone', 'Admin can remove a child at university');
  perform pg_temp.cfg('moments.enabled', 'true');
  -- the sweep has no school work left that spins (every due school moment moves on)
  perform pg_temp.hours(1);
  perform bl_kids_alert_sweep();
  perform pg_temp.assert(not exists (select 1 from kids_children k where k.status in ('home', 'university') and k.next_alert_at <= bl_now() - interval '2 hours'), 'nothing is stuck in the past');
  raise notice 'ok 13: switches and admin';
end $$;
