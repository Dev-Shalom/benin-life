-- Industry offices (20261106000100_industry_offices.sql, docs/OFFICES.md). Rolled back. Run (migration applied):
--   bash scripts/sql-test.sh -- supabase/tests/offices_test.sql
-- Or with the migration first: bash scripts/sql-test.sh supabase/migrations/20261106000100_industry_offices.sql -- supabase/tests/offices_test.sql
-- Time moves with bl.test_offset_seconds. Groups: 1 grants / RLS / private helpers · 2 seeds (offices, levers, keys exist and are read) ·
-- 3 apply / withdraw / moderation · 4 admin appoint by username, one office per player, applicants accept / reject / remove, remove a holder, alerts, notices, badge ·
-- 5 levers (band, step, cooldown, daily cap, drift cap, freeze, live setting + the game reads it, audit, notice rate limit) ·
-- 6 restore (removal, term end, inactivity, admin edit wins) + salary · 7 Governor of the Bank balance (rails, sinks, no money printing) ·
-- 8 approval rating · 9 official statement · 10 admin RPCs / Content editors · 11 health lever · 12 switch off, election untouched.
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
create or replace function pg_temp.cv(p_key text) returns numeric
language sql as $$ select (value #>> '{}')::numeric from game_config where key = p_key; $$;
create or replace function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('io.' || p)::uuid $$;
create or replace function pg_temp.bank(p_uid uuid) returns bigint language sql as $$ select bank from profiles where id = p_uid $$;
create or replace function pg_temp.evn(p_uid uuid, p_kind text) returns int language sql as $$ select count(*)::int from events where user_id = p_uid and kind = p_kind $$;
create or replace function pg_temp.bcn() returns int language sql as $$ select count(*)::int from broadcasts where title like 'Industry office:%' or title like 'Official statement:%' $$;
create or replace function pg_temp.bcall() returns int language sql as $$ select count(*)::int from broadcasts $$;

create or replace function pg_temp.at(p_uid uuid, p_loc text) returns void
language sql as $$
  update profiles set location_id = p_loc, travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
                      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = bl_now(), rent_due_at = null
   where id = p_uid;
$$;

create or replace function pg_temp.mk(p_name text, p_home text default 'uselu_selfcon', p_age interval default interval '30 days') returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@io.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, protected_until = null, created_at = now() - p_age, cash = 0, bank = 0, home_location_id = p_home,
         energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0, job_level = 3 where id = v;
  perform pg_temp.at(v, 'third_east');
  return v;
end $$;

-- ---------- setup ----------
do $$
declare
  v_names text[] := array['IO_Adm', 'IO_A', 'IO_B', 'IO_C', 'IO_D', 'IO_E', 'IO_F', 'IO_G', 'IO_H', 'IO_V1', 'IO_V2', 'IO_V3', 'IO_V4'];
  v_keys  text[] := array['adm', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'v1', 'v2', 'v3', 'v4'];
  i int; u uuid;
begin
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  for i in 1..cardinality(v_names) loop
    u := pg_temp.mk(v_names[i]);
    perform set_config('io.' || v_keys[i], u::text, true);
  end loop;
  u := pg_temp.mk('IO_Z', 'uselu_selfcon', interval '1 hour');   -- a young account
  perform set_config('io.z', u::text, true);
  u := pg_temp.mk('IO_L');                                        -- career level too low
  update profiles set job_level = 0 where id = u;
  perform set_config('io.l', u::text, true);
  update profiles set is_admin = true where id = pg_temp.u('adm');
  update profiles set bank = 5000000 where id = pg_temp.u('a');
end $$;

-- ---------- 1. grants / RLS / private helpers ----------
do $$
declare f text; t text;
begin
  foreach f in array array['ind_tick()', 'ind_status()', 'ind_apply(text,text)', 'ind_withdraw()', 'ind_set_lever(text,numeric)', 'ind_vote(bigint,boolean)', 'ind_statement(text)', 'ind_resign()',
    'admin_ind_overview()', 'admin_ind_appoint(text,text,text)', 'admin_ind_application(bigint,text,text)', 'admin_ind_remove_holder(bigint,text)', 'admin_ind_freeze(text,text,boolean)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute'), 'anon cannot run ' || f);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute'), 'authenticated can run ' || f);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || f)::regprocedure), 'security definer ' || f);
  end loop;
  perform pg_temp.assert((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'bl\_ind\_%') >= 15, 'helpers exist');
  perform pg_temp.assert(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'bl\_ind\_%'
                            and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))), 'bl_ind_* helpers are private');
  foreach t in array array['ind_offices', 'ind_levers', 'ind_holders', 'ind_applications', 'ind_baseline', 'ind_changes', 'ind_votes', 'ind_statements'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || t)::regclass), 'RLS on ' || t);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || t, 'insert') and not has_table_privilege('authenticated', 'public.' || t, 'update')
                           and not has_table_privilege('authenticated', 'public.' || t, 'delete') and not has_table_privilege('anon', 'public.' || t, 'select'), 'no direct writes / anon reads on ' || t);
  end loop;
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.ind_offices', 'select') and has_table_privilege('authenticated', 'public.ind_levers', 'select'), 'catalogues readable');
  foreach t in array array['ind_holders', 'ind_applications', 'ind_baseline', 'ind_changes', 'ind_votes', 'ind_statements'] loop
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || t, 'select'), t || ' is server only');
  end loop;
  -- no foreign key to profiles anywhere in the new tables (the live deadlock rule)
  perform pg_temp.assert(not exists (select 1 from pg_constraint c where c.contype = 'f' and c.confrelid = 'public.profiles'::regclass
                          and c.conrelid in ('public.ind_offices'::regclass, 'public.ind_levers'::regclass, 'public.ind_holders'::regclass, 'public.ind_applications'::regclass,
                                             'public.ind_baseline'::regclass, 'public.ind_changes'::regclass, 'public.ind_votes'::regclass, 'public.ind_statements'::regclass)), 'no FK to profiles');
  raise notice 'ok 1: grants / RLS';
end $$;

-- ---------- 2. seeds ----------
do $$
declare r record; n int;
begin
  perform pg_temp.assert((select count(*) from ind_offices) = 7, 'seven offices');
  perform pg_temp.assert((select count(*) from ind_offices where active) = 6 and not (select active from ind_offices where id = 'nepa_md'), 'NEPA MD is inactive');
  perform pg_temp.assert(not exists (select 1 from ind_offices where election_enabled) and not exists (select 1 from ind_offices where seats <> 1), 'election_enabled off, one seat');
  perform pg_temp.assert(not exists (select 1 from ind_offices where name = '' or title = '' or blurb = '' or industry = ''), 'offices are labelled');
  perform pg_temp.assert((select salary_per_day from ind_offices where id = 'bank_governor') = 5000000 and (select salary_per_day from ind_offices where id = 'nepa_md') = 3000000
    and (select salary_per_day from ind_offices where id = 'health_commissioner') = 2000000 and (select salary_per_day from ind_offices where id = 'transport_commissioner') = 1500000
    and (select salary_per_day from ind_offices where id = 'markets_commissioner') = 1500000 and (select salary_per_day from ind_offices where id = 'housing_commissioner') = 1500000
    and (select salary_per_day from ind_offices where id = 'education_commissioner') = 1000000, 'salaries');
  perform pg_temp.assert(not exists (select 1 from ind_offices where term_days <> 14), 'terms are 14 days');
  perform pg_temp.assert((select count(*) from ind_levers where office_id = 'bank_governor') = 11, 'eleven bank levers');
  perform pg_temp.assert((select count(*) from ind_levers where office_id = 'transport_commissioner') = 5 and (select count(*) from ind_levers where office_id = 'health_commissioner') = 2
    and (select count(*) from ind_levers where office_id = 'markets_commissioner') = 4 and (select count(*) from ind_levers where office_id = 'education_commissioner') = 3
    and (select count(*) from ind_levers where office_id = 'housing_commissioner') = 6, 'levers per office');
  perform pg_temp.assert(not exists (select 1 from ind_levers where label = '' or blurb = '' or effect = '' or direction = ''), 'levers have labels, plain words and a confirm text');
  perform pg_temp.assert(not exists (select 1 from ind_levers l where not exists (select 1 from game_config g where g.key = l.config_key)), 'every lever key exists in game_config');
  -- every key is read by live code (travel.* is built as a string, so look for the prefix)
  for r in select l.id, l.config_key from ind_levers l where l.office_id <> 'nepa_md' loop
    n := (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%' || r.config_key || '%');
    if n = 0 and r.config_key like 'travel.%' then
      n := (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%''travel.'' ||%' || split_part(r.config_key, '.', 3) || '%');
    end if;
    perform pg_temp.assert(n > 0, 'live code reads ' || r.config_key);
  end loop;
  perform pg_temp.assert((select count(*) from (select config_key from ind_levers group by 1 having count(*) > 1) x) = 0, 'one lever per setting');
  perform pg_temp.assert(not exists (select 1 from ind_levers where band_min > band_max or step <= 0 or cooldown_hours < 24), 'bands sane, cooldown at least a day by default');
  -- bands of the bank are 50 to 150 percent of the live default or narrower
  perform pg_temp.assert(not exists (select 1 from ind_levers l join game_config g on g.key = l.config_key
      where l.office_id = 'bank_governor' and (l.band_min < (g.value #>> '{}')::numeric * 0.5 - 1e-9 or l.band_max > (g.value #>> '{}')::numeric * 1.5 + 1e-9)), 'bank bands within 50 to 150 percent');
  perform pg_temp.assert(not exists (select 1 from ind_levers l join game_config g on g.key = l.config_key
      where l.office_id <> 'nepa_md' and (l.band_min < (g.value #>> '{}')::numeric * 0.5 - 1e-9 or l.band_max > (g.value #>> '{}')::numeric * 1.5 + 1e-9)), 'every band within 50 to 150 percent');
  -- the settings exist with labels, descriptions, min and max
  perform pg_temp.assert((select count(*) from game_config where category = 'offices' and label <> '' and description <> '') >= 15, 'offices settings listed');
  perform pg_temp.assert(not exists (select 1 from game_config where category = 'offices' and kind in ('number', 'percent', 'naira') and (min is null or max is null)), 'every numeric offices setting has min and max');
  -- the badge patch and the health patch are in place
  perform pg_temp.assert(position('bl_ind_title(p_uid)' in pg_get_functiondef('public.bl_pol_title(uuid)'::regprocedure)) > 0, 'bl_pol_title patched');
  perform pg_temp.assert(position('health.price_pct' in pg_get_functiondef('public.bl_dealer_net(items, text)'::regprocedure)) > 0, 'bl_dealer_net patched');
  perform pg_temp.assert(position('ind_' in pg_get_functiondef('public.bl_pol_tick()'::regprocedure)) = 0, 'the election clock is untouched');
  perform pg_temp.assert(bl_admin_table_spec('ind_offices') is not null and bl_admin_table_spec('ind_levers') is not null and bl_admin_table_spec('offices') is not null, 'Content editors');
  raise notice 'ok 2: seeds';
end $$;

-- ---------- 3. apply / withdraw / moderation ----------
do $$
declare r jsonb; v_word text;
begin
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_apply('bank_governor', 'I will keep the fees fair for everybody.') $q$) = 'account_young', 'young account refused');
  perform pg_temp.login(pg_temp.u('l'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_apply('bank_governor', 'I will keep the fees fair for everybody.') $q$) = 'level_low', 'career level refused');
  perform pg_temp.login(pg_temp.u('b'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_apply('nepa_md', 'Lights for everybody, every day, always.') $q$) = 'bad_office', 'inactive office refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_apply('bank_governor', 'short') $q$) = 'too_short', 'pitch too short');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_apply('bank_governor', repeat('x', 200)) $q$) = 'too_long', 'pitch too long');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_apply('bank_governor', 'Visit www.example.com for my plan') $q$) = 'blocked_text', 'no links');
  select split_part(value #>> '{}', ',', 1) into v_word from game_config where key = 'pol.blocked_words';
  perform pg_temp.assert(pg_temp.hint_of(format($q$ select ind_apply('bank_governor', %L) $q$, 'I am a friend of ' || btrim(v_word) || ' and will help.')) = 'blocked_text', 'real names refused (' || v_word || ')');
  r := ind_apply('bank_governor', 'I will keep the fees fair for everybody.');
  perform pg_temp.assert((select count(*) from ind_applications where user_id = pg_temp.u('b') and status = 'pending') = 1, 'application stored');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_apply('health_commissioner', 'Healthy city, healthy people, simple.') $q$) = 'already_applied', 'one active application per player');
  perform pg_temp.assert(ind_status()->'my_application'->>'office_id' = 'bank_governor', 'status shows my application');
  r := ind_withdraw();
  perform pg_temp.assert((select status from ind_applications where user_id = pg_temp.u('b')) = 'withdrawn', 'withdrawn');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_withdraw() $q$) = 'none', 'nothing to withdraw');
  r := ind_apply('health_commissioner', 'Healthy city, healthy people, simple.');
  perform pg_temp.login(pg_temp.u('c'));
  r := ind_apply('bank_governor', 'Sound money and fair fees for the city.');
  perform pg_temp.login(pg_temp.u('d'));
  r := ind_apply('bank_governor', 'Steady hands on the bank counter, always.');
  perform pg_temp.assert((select (o->>'applicants')::int from jsonb_array_elements(ind_status()->'offices') o where o->>'id' = 'bank_governor') = 2, 'applicant count shown');
  raise notice 'ok 3: apply';
end $$;

-- ---------- 4. admin appoint, one office per player, applicants, remove, alerts, notices, badge ----------
do $$
declare r jsonb; v_hid bigint; v_bc int; v_app bigint; v_ev int;
begin
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_ind_appoint('bank_governor', 'IO_A', 'x') $q$) = 'not_admin', 'players cannot appoint');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_ind_overview() $q$) = 'not_admin', 'overview is admin only');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_ind_remove_holder(1, 'x') $q$) = 'not_admin', 'remove is admin only');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_ind_freeze('bank_governor', null, true) $q$) = 'not_admin', 'freeze is admin only');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_ind_application(1, 'accept', '') $q$) = 'not_admin', 'applicants are admin only');
  perform pg_temp.login(pg_temp.u('adm'));
  v_bc := pg_temp.bcall();
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_ind_appoint('bank_governor', 'Nobody_Here', '') $q$) = 'no_player', 'unknown username');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_ind_appoint('nope', 'IO_A', '') $q$) = 'bad_office', 'unknown office');
  r := admin_ind_appoint('bank_governor', '@io_a', 'test appointment');   -- case insensitive, @ ok, no application needed
  v_hid := (r->>'id')::bigint;
  perform pg_temp.assert((select user_id from ind_holders where id = v_hid) = pg_temp.u('a') and (select source from ind_holders where id = v_hid) = 'admin', 'A is Governor of the Bank');
  perform pg_temp.assert((select term_end - term_start from ind_holders where id = v_hid) = interval '14 days', '14 day term');
  perform pg_temp.assert(pg_temp.evn(pg_temp.u('a'), 'ind_appointed') = 1, 'holder gets an alert');
  perform pg_temp.assert(pg_temp.bcall() = v_bc + 1 and exists (select 1 from broadcasts where title = 'Industry office: Governor of the Bank' or body like '%is the new Governor of the Bank%'), 'public notice: X is the new Governor of the Bank');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'ind_appoint' and target_user = pg_temp.u('a')) = 1, 'audited');
  -- one office per player; filled seat
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_ind_appoint('health_commissioner', 'IO_A', '') $q$) = 'holds_office', 'one office per player');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_ind_appoint('bank_governor', 'IO_B', '') $q$) = 'filled', 'seat is filled');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_apply('health_commissioner', 'Healthy city, healthy people, simple.') $q$) in ('holds_office', 'already_applied'), 'a holder cannot apply');
  -- the badge: public profile, and an elected title wins
  perform pg_temp.assert(get_public_profile(pg_temp.u('a'))->>'title' = 'Bank Gov.', 'profile carries the industry badge');
  perform pg_temp.assert(bl_pol_title(pg_temp.u('a')) = 'Bank Gov.', 'bl_pol_title');
  insert into office_holders (office_id, user_id, status, term_start, term_end, paid_through) values ('councillor', pg_temp.u('a'), 'active', bl_now(), bl_now() + interval '14 days', bl_now());
  perform pg_temp.assert(bl_pol_title(pg_temp.u('a')) = 'Hon.', 'an elected office title wins over the industry title');
  -- ... and an elected seat ends the industry office (one office at a time), lever restored by the tick
  perform bl_ind_tick();
  perform pg_temp.assert((select status from ind_holders where id = v_hid) = 'ended', 'elected seat ends the industry office');
  delete from office_holders where user_id = pg_temp.u('a');
  perform pg_temp.assert(bl_pol_title(pg_temp.u('a')) is null, 'no title now');
  perform pg_temp.login(pg_temp.u('adm'));
  -- applicants: accept C, reject B? (B withdrew earlier and applied to Health), remove D
  select id into v_app from ind_applications where user_id = pg_temp.u('c') and status = 'pending';
  perform pg_temp.assert(pg_temp.hint_of(format($q$ select admin_ind_application(%s, 'dance', '') $q$, v_app)) = 'bad_action', 'bad action');
  r := admin_ind_application(v_app, 'accept', 'welcome');
  perform pg_temp.assert((select status from ind_applications where id = v_app) = 'accepted' and exists (select 1 from ind_holders where user_id = pg_temp.u('c') and office_id = 'bank_governor' and status = 'active'
    and source = 'application'), 'accepted: C is Governor of the Bank');
  perform pg_temp.assert(pg_temp.evn(pg_temp.u('c'), 'ind_appointed') = 1, 'accepted applicant alerted');
  select id into v_app from ind_applications where user_id = pg_temp.u('d') and status = 'pending';
  v_ev := pg_temp.evn(pg_temp.u('d'), 'ind_rejected');
  r := admin_ind_application(v_app, 'reject', 'not this time');
  perform pg_temp.assert((select status from ind_applications where id = v_app) = 'rejected' and pg_temp.evn(pg_temp.u('d'), 'ind_rejected') = v_ev + 1, 'rejected + alert');
  perform pg_temp.assert(pg_temp.hint_of(format($q$ select admin_ind_application(%s, 'reject', '') $q$, v_app)) = 'gone', 'decided applications are gone');
  perform pg_temp.login(pg_temp.u('d'));
  r := ind_apply('bank_governor', 'Second try, steady hands for the bank.');
  perform pg_temp.login(pg_temp.u('adm'));
  select id into v_app from ind_applications where user_id = pg_temp.u('d') and status = 'pending';
  r := admin_ind_application(v_app, 'remove', 'spam');
  perform pg_temp.assert((select status from ind_applications where id = v_app) = 'removed' and pg_temp.evn(pg_temp.u('d'), 'ind_app_removed') = 1, 'removed + alert');
  perform pg_temp.login(pg_temp.u('d'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_apply('bank_governor', 'Third try, steady hands for the bank.') $q$) = 'removed_recently', 'removed applicants wait before applying again');
  perform pg_temp.assert((select count(*) from admin_audit where action in ('ind_accept', 'ind_reject', 'ind_remove') ) = 3, 'applicant decisions audited');
  -- remove a holder (C): reason needed, alert, notice, audit; B (Health applicant) then appointed
  perform pg_temp.login(pg_temp.u('adm'));
  select id into v_hid from ind_holders where user_id = pg_temp.u('c') and status = 'active';
  perform pg_temp.assert(pg_temp.hint_of(format($q$ select admin_ind_remove_holder(%s, '') $q$, v_hid)) = 'reason', 'removal needs a reason');
  v_bc := pg_temp.bcall();
  r := admin_ind_remove_holder(v_hid, 'testing removal');
  perform pg_temp.assert((select status from ind_holders where id = v_hid) = 'removed' and pg_temp.evn(pg_temp.u('c'), 'ind_ended') = 1, 'removed + alert');
  perform pg_temp.assert(pg_temp.bcall() = v_bc + 1, 'public notice on removal');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'ind_remove_holder' and target_user = pg_temp.u('c')) = 1, 'removal audited');
  perform pg_temp.assert(pg_temp.hint_of(format($q$ select admin_ind_remove_holder(%s, 'again') $q$, v_hid)) = 'gone', 'seat already empty');
  -- applicant B (pending for Health): admin accepts through the application
  select id into v_app from ind_applications where user_id = pg_temp.u('b') and status = 'pending';
  r := admin_ind_application(v_app, 'accept', '');
  perform pg_temp.assert(exists (select 1 from ind_holders where user_id = pg_temp.u('b') and office_id = 'health_commissioner' and status = 'active'), 'B is Health Commissioner');
  r := admin_ind_remove_holder((select id from ind_holders where user_id = pg_temp.u('b') and status = 'active'), 'done');
  raise notice 'ok 4: appoint / applicants / remove';
end $$;

-- ---------- 5. levers ----------
do $$
declare r jsonb; v_hid bigint; q jsonb; v_bc int; v_n int; v_money bigint;
begin
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_ind_appoint('bank_governor', 'IO_A', 'levers');
  perform pg_temp.cfg('offices.inactive_days', '90');   -- this group moves the clock for days; inactivity is tested in group 6
  select id into v_hid from ind_holders where user_id = pg_temp.u('a') and status = 'active';
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('transport.keke_base', 120) $q$) = 'not_yours', 'only your own levers');
  perform pg_temp.login(pg_temp.u('e'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 0.8) $q$) = 'not_holder', 'non holders cannot change levers');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.cv('economy.fee_tier1_pct') = 1, 'baseline fee 1 percent');
  q := bank_transfer_quote(60000);
  perform pg_temp.assert((q->>'tier_fee')::int = 700, 'default quote 700: ' || q::text);
  v_money := pg_temp.bank(pg_temp.u('a'));
  v_bc := pg_temp.bcn();
  -- out of band / bad step / same
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 0.4) $q$) = 'out_of_band', 'below the band');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 1.6) $q$) = 'out_of_band', 'above the band');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 0) $q$) = 'out_of_band', 'zero is below the band');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 0.85) $q$) = 'bad_step', 'off the step');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 1) $q$) = 'same', 'same value');
  perform pg_temp.assert(pg_temp.cv('economy.fee_tier1_pct') = 1, 'refused changes change nothing');
  -- a good change: live setting, quote, baseline, audit, alert, notice
  r := ind_set_lever('bank.fee1', 0.8);
  perform pg_temp.assert(pg_temp.cv('economy.fee_tier1_pct') = 0.8, 'the live setting changed');
  q := bank_transfer_quote(60000);
  perform pg_temp.assert((q->>'tier_fee')::int = 600, 'the game reads it: the quote is now 600: ' || q::text);
  perform pg_temp.assert((select (baseline #>> '{}')::numeric from ind_baseline where config_key = 'economy.fee_tier1_pct') = 1, 'baseline remembered');
  perform pg_temp.assert((select count(*) from ind_changes where holder_id = v_hid and kind = 'change' and lever_id = 'bank.fee1') = 1, 'audit row');
  perform pg_temp.assert(pg_temp.evn(pg_temp.u('a'), 'ind_lever') = 1, 'holder alert');
  perform pg_temp.assert(pg_temp.bcn() = v_bc + 1 and exists (select 1 from broadcasts where title = 'Industry office: Governor of the Bank' and body like '%cut the transfer fee, first ₦50,000 to 0.8%%'), 'public notice in plain words');
  perform pg_temp.assert(pg_temp.bank(pg_temp.u('a')) = v_money, 'the lever gives the holder no money');
  -- the rate limit on notices: a second change inside the gap is not announced
  r := ind_set_lever('bank.fee2', 1.5);
  perform pg_temp.assert(not (r->>'announced')::boolean, 'second change inside the gap: no public notice');
  perform pg_temp.assert(pg_temp.bcn() = v_bc + 1, 'notices rate limited');
  -- cooldown
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 0.7) $q$) = 'cooldown', 'cooldown');
  perform pg_temp.advance(23 * 3600);
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 0.7) $q$) = 'cooldown', 'still cooling at 23 h');
  perform pg_temp.advance(3600);
  r := ind_set_lever('bank.fee1', 0.7);
  perform pg_temp.assert((r->>'announced')::boolean and pg_temp.bcn() = v_bc + 2, 'after the gap it is announced again');
  -- daily cap (4): fee1 (t=0) was 24 h ago, fee2 + fee1 now; two more fill the day
  select count(*) into v_n from ind_changes where office_id = 'bank_governor' and kind = 'change' and created_at > bl_now() - interval '24 hours';
  r := ind_set_lever('bank.stamp', 40);
  select count(*) into v_n from ind_changes where office_id = 'bank_governor' and kind = 'change' and created_at > bl_now() - interval '24 hours';
  r := ind_set_lever('bank.pos', 1.25);
  r := ind_set_lever('bank.close', 17);
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.limit', 175000) $q$) = 'daily_cap', 'daily cap of changes per office');
  perform pg_temp.advance(25 * 3600);
  -- drift cap: budget 120. Now: fee1 0.7 (30), fee2 1.5 (25), stamp 40 (20), pos 1.25 (16.7), close 17 (6.25) = about 98
  update ind_offices set max_changes_per_day = 50 where id = 'bank_governor';
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee3', 1.5) $q$) = 'drift_cap', 'a 50 percent move would pass the 120 percent budget');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee3', 2.5) $q$) = 'ok', 'a smaller move still fits (17 percent)');
  perform pg_temp.advance(25 * 3600);
  -- moving back toward the baseline is always allowed
  r := ind_set_lever('bank.fee1', 1);
  perform pg_temp.assert(not exists (select 1 from ind_baseline where config_key = 'economy.fee_tier1_pct'), 'back at the baseline: no baseline row');
  perform pg_temp.assert(pg_temp.cv('economy.fee_tier1_pct') = 1, 'fee back to 1');
  -- freeze: one lever, then the whole office
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_ind_freeze('bank_governor', 'bank.fee2', true);
  perform pg_temp.assert(pg_temp.evn(pg_temp.u('a'), 'ind_frozen') = 1, 'holder alerted of the freeze');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.advance(25 * 3600);
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee2', 1.25) $q$) = 'frozen', 'frozen lever');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.stamp', 45) $q$) = 'ok', 'other levers still work');
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_ind_freeze('bank_governor', null, true);
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.advance(25 * 3600);
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.stamp', 50) $q$) = 'frozen', 'frozen office');
  perform pg_temp.assert((ind_status()->'me'->>'frozen')::boolean, 'status says frozen');
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_ind_freeze('bank_governor', null, false);
  perform admin_ind_freeze('bank_governor', 'bank.fee2', false);
  perform pg_temp.assert((select count(*) from admin_audit where action = 'ind_freeze') = 4, 'freezes audited');
  -- status shows who set what
  perform pg_temp.login(pg_temp.u('e'));
  r := ind_status();
  perform pg_temp.assert((select count(*) from jsonb_array_elements(r->'offices') o, jsonb_array_elements(o->'levers') l where (l->>'changed')::boolean and l->>'changed_by' = 'IO_A') >= 3, 'players see who set what');
  perform pg_temp.assert(jsonb_array_length(r->'recent') >= 5, 'recent changes list');
  perform pg_temp.cfg('offices.inactive_days', '5');
  raise notice 'ok 5: levers';
end $$;

-- ---------- 6. restore: removal, term end, inactivity, admin edit wins; salary ----------
do $$
declare r jsonb; v_hid bigint; v_bank bigint; v_n int; v_b0 bigint;
begin
  -- state now: A holds the bank office with several levers moved
  select id into v_hid from ind_holders where user_id = pg_temp.u('a') and status = 'active';
  perform pg_temp.assert((select count(*) from ind_baseline) >= 3, 'levers are moved');
  -- (a) removal restores everything in one go
  perform pg_temp.login(pg_temp.u('adm'));
  r := admin_ind_remove_holder(v_hid, 'restore test');
  perform pg_temp.assert(not exists (select 1 from ind_baseline), 'no baseline rows left');
  perform pg_temp.assert(pg_temp.cv('economy.fee_tier1_pct') = 1 and pg_temp.cv('economy.fee_tier2_pct') = 2 and pg_temp.cv('economy.stamp_duty') = 50 and pg_temp.cv('pos.fee_pct') = 1.5
                         and pg_temp.cv('bank.transfer_daily_limit') = 200000 and pg_temp.cv('economy.fee_tier3_pct') = 3, 'every lever is back at the baseline');
  perform pg_temp.assert((select count(*) from ind_changes where holder_id = v_hid and kind = 'restore') >= 3, 'restores are audited');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert((bank_transfer_quote(60000)->>'tier_fee')::int = 700, 'the quote is back to 700');
  -- (b) term end: the lever goes back by itself, the holder is paid 14 days
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_ind_appoint('bank_governor', 'IO_A', 'term test');
  select id into v_hid from ind_holders where user_id = pg_temp.u('a') and status = 'active';
  v_b0 := pg_temp.bank(pg_temp.u('a'));
  perform pg_temp.at(pg_temp.u('a'), 'third_east');
  perform pg_temp.login(pg_temp.u('a'));
  r := ind_set_lever('bank.fee1', 0.9);
  perform pg_temp.advance(3 * 86400);
  perform pg_temp.at(pg_temp.u('a'), 'third_east');
  r := ind_status();
  perform pg_temp.assert(pg_temp.bank(pg_temp.u('a')) = v_b0 + 3 * 5000000, 'three days of salary paid: ' || (pg_temp.bank(pg_temp.u('a')) - v_b0));
  perform pg_temp.assert(exists (select 1 from ledger l where l.user_id = pg_temp.u('a') and l.reason = 'office_salary'), 'ledger office_salary');
  perform pg_temp.assert('office_salary' = any (bl_earn_reasons()), 'office_salary counts as earned');
  perform pg_temp.advance(12 * 86400);   -- day 15: past the term; keep A "seen" so only the term ends it
  perform pg_temp.at(pg_temp.u('a'), 'third_east');
  perform pg_temp.login(pg_temp.u('e'));
  r := ind_status();
  perform pg_temp.assert((select status from ind_holders where id = v_hid) = 'ended', 'term ended');
  perform pg_temp.assert(pg_temp.cv('economy.fee_tier1_pct') = 1 and not exists (select 1 from ind_baseline), 'term end restored the baseline');
  perform pg_temp.assert(pg_temp.bank(pg_temp.u('a')) = v_b0 + 14 * 5000000, 'a full term paid exactly 14 days, never past the end: ' || (pg_temp.bank(pg_temp.u('a')) - v_b0));
  perform pg_temp.assert(pg_temp.evn(pg_temp.u('a'), 'ind_ended') >= 1, 'holder alert at term end');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 0.9) $q$) = 'not_holder', 'no powers after the term');
  perform pg_temp.advance(86400);
  r := ind_status();
  perform pg_temp.assert(pg_temp.bank(pg_temp.u('a')) = v_b0 + 14 * 5000000, 'no salary after the term');
  -- (c) inactivity: a holder not seen for 5 days loses the office
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_ind_appoint('bank_governor', 'IO_A', 'inactivity test');
  select id into v_hid from ind_holders where user_id = pg_temp.u('a') and status = 'active';
  perform pg_temp.at(pg_temp.u('a'), 'third_east');
  perform pg_temp.login(pg_temp.u('a'));
  r := ind_set_lever('bank.stamp', 40);
  perform pg_temp.assert(pg_temp.cv('economy.stamp_duty') = 40, 'stamp duty moved');
  perform pg_temp.advance(4 * 86400);
  perform pg_temp.login(pg_temp.u('e'));
  r := ind_status();
  perform pg_temp.assert((select status from ind_holders where id = v_hid) = 'active', 'seen 4 days ago: still holds');
  perform pg_temp.advance(2 * 86400);
  r := ind_status();
  perform pg_temp.assert((select status from ind_holders where id = v_hid) = 'inactive', 'not seen for 5 days: loses the office');
  perform pg_temp.assert(pg_temp.cv('economy.stamp_duty') = 50 and not exists (select 1 from ind_baseline), 'inactivity restored the baseline');
  perform pg_temp.assert((select ended_reason from ind_holders where id = v_hid) like '%not seen%', 'reason says why');
  -- (d) an admin edit after the holder's change wins on restore
  perform pg_temp.at(pg_temp.u('a'), 'third_east');
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_ind_appoint('bank_governor', 'IO_A', 'override test');
  select id into v_hid from ind_holders where user_id = pg_temp.u('a') and status = 'active';
  perform pg_temp.login(pg_temp.u('a'));
  r := ind_set_lever('bank.stamp', 40);
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_config_set('economy.stamp_duty', '60'::jsonb);
  r := admin_ind_remove_holder(v_hid, 'override');
  perform pg_temp.assert(pg_temp.cv('economy.stamp_duty') = 60 and not exists (select 1 from ind_baseline), 'the admin''s own value is kept, the baseline row is dropped');
  perform pg_temp.cfg('economy.stamp_duty', '50');
  raise notice 'ok 6: restore + salary';
end $$;

-- ---------- 7. Governor of the Bank: balance guarantees ----------
do $$
declare r jsonb; v_hid bigint; k text; v_def numeric; v_min numeric; v_fee0 int; v_fee1 int;
begin
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_ind_appoint('bank_governor', 'IO_A', 'balance');
  perform pg_temp.at(pg_temp.u('a'), 'third_east');
  perform pg_temp.login(pg_temp.u('a'));
  -- none of the levers is a switch, an interest rate or a payout
  perform pg_temp.assert(not exists (select 1 from ind_levers where config_key like '%enabled%' or config_key like '%interest%' or config_key like '%reward%' or config_key like '%bonus%'
                         or config_key like '%salary%' or config_key like '%income%' or config_key like '%payout%' or config_key like 'invest.%' or config_key like 'yahoo.%'
                         or config_key like 'daily.%' or config_key like 'referral.%' or config_key like '%\_gain%'), 'no lever can switch a sink off or create money');
  perform pg_temp.assert(not exists (select 1 from ind_levers where office_id = 'bank_governor' and config_key not in ('economy.fee_tier1_pct', 'economy.fee_tier2_pct', 'economy.fee_tier3_pct', 'economy.stamp_duty',
                         'pos.fee_pct', 'economy.tax_band2_pct', 'economy.tax_band3_pct', 'economy.tax_band4_pct', 'bank.transfer_daily_limit', 'bank.open_hour', 'bank.close_hour')), 'the bank lever list is exactly the documented one');
  -- even if an admin widens a band to 0..100, the hard rails (50 to 150 percent of the baseline) hold
  update ind_levers set band_min = 0, band_max = 100 where id = 'bank.fee1';
  update ind_levers set band_min = 0, band_max = 100 where id = 'bank.tax2';
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 0) $q$) = 'out_of_band', 'cannot switch the transfer fee off');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 0.4) $q$) = 'out_of_band', 'floor holds at 50 percent');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 2) $q$) = 'out_of_band', 'cap holds at 150 percent');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.tax2', 0) $q$) = 'out_of_band', 'cannot switch the income tax off');
  -- the worst case inside the drift budget still leaves the sinks working: fee tiers at the floor, stamp duty at the floor
  update ind_offices set max_changes_per_day = 50, max_total_drift_pct = 1000 where id = 'bank_governor';
  update ind_levers set band_min = 0.5, band_max = 1.5 where id = 'bank.fee1';
  v_fee0 := (bl_transfer_fee_calc(600000, 0)->>'fee')::int;
  r := ind_set_lever('bank.fee1', 0.5);
  perform pg_temp.advance(25 * 3600); r := ind_set_lever('bank.fee2', 1); r := ind_set_lever('bank.fee3', 1.5); r := ind_set_lever('bank.stamp', 25);
  perform pg_temp.advance(25 * 3600); r := ind_set_lever('bank.tax2', 4); r := ind_set_lever('bank.pos', 1);
  v_fee1 := (bl_transfer_fee_calc(600000, 0)->>'fee')::int;
  perform pg_temp.assert(v_fee1 >= v_fee0 * 0.5 and v_fee1 > 0, 'at the floors the fee sink is still at least half: ' || v_fee0 || ' -> ' || v_fee1);
  perform pg_temp.assert((bl_transfer_fee_calc(10000, 0)->>'stamp_duty')::int = 25 and (bl_transfer_fee_calc(10000, 0)->>'tier_fee')::int >= 50, 'stamp duty and a fee are still charged');
  perform pg_temp.assert(pg_temp.cv('economy.tax_band2_pct') = 4 and pg_temp.cv('economy.tax_band2_pct') >= 5 * 0.5, 'tax rate cut at most 20 percent in the band');
  -- the same worst case in reverse: the cap is 150 percent
  perform pg_temp.advance(25 * 3600);
  r := ind_set_lever('bank.fee3', 4.5);
  perform pg_temp.assert(pg_temp.cv('economy.fee_tier3_pct') = 4.5, 'raising to the cap works');
  -- the holder's own money never moves because of a lever (no income from fees)
  raise notice 'ok 7: bank balance';
end $$;

-- ---------- 8. approval rating ----------
do $$
declare r jsonb; v_hid bigint; v_ev int; v_ap jsonb;
begin
  select id into v_hid from ind_holders where user_id = pg_temp.u('a') and status = 'active';
  update profiles set created_at = bl_now() - interval '1 hour' where id = pg_temp.u('z');
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.assert(pg_temp.hint_of(format($q$ select ind_vote(%s, true) $q$, v_hid)) = 'account_young', 'young accounts cannot vote');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of(format($q$ select ind_vote(%s, true) $q$, v_hid)) = 'self', 'no self rating');
  perform pg_temp.login(pg_temp.u('b'));
  r := ind_vote(v_hid, true);
  r := ind_vote(v_hid, true);
  perform pg_temp.assert((select count(*) from ind_votes where holder_id = v_hid) = 1, 'one vote per player');
  perform pg_temp.login(pg_temp.u('c')); r := ind_vote(v_hid, false);
  perform pg_temp.login(pg_temp.u('d')); r := ind_vote(v_hid, true);
  v_ap := bl_ind_approval(v_hid, null);
  perform pg_temp.assert((v_ap->>'pct')::int = 67 and (v_ap->>'votes')::int = 3, 'approval 2 of 3 = 67: ' || v_ap::text);
  perform pg_temp.login(pg_temp.u('b')); r := ind_vote(v_hid, false);   -- changing your mind replaces the vote
  perform pg_temp.assert((bl_ind_approval(v_hid, null)->>'pct')::int = 33 and (bl_ind_approval(v_hid, null)->>'votes')::int = 3, 'switching replaces: still 3 votes');
  perform pg_temp.assert((select o->'holder'->'approval'->>'pct' from jsonb_array_elements(ind_status()->'offices') o where o->>'id' = 'bank_governor')::int = 33, 'approval shown next to the holder');
  perform pg_temp.assert((select o->'holder'->'approval'->>'mine' from jsonb_array_elements(ind_status()->'offices') o where o->>'id' = 'bank_governor') = 'false', 'my own vote shown');
  -- low approval warning: min votes and threshold are admin settings; no automatic removal
  perform pg_temp.cfg('offices.low_approval_min_votes', '4');
  perform pg_temp.cfg('offices.low_approval_pct', '40');
  perform pg_temp.assert(pg_temp.evn(pg_temp.u('a'), 'ind_low_approval') = 0 and not bl_ind_low(v_hid), 'not enough votes yet');
  perform pg_temp.login(pg_temp.u('e')); r := ind_vote(v_hid, false);
  perform pg_temp.assert(bl_ind_low(v_hid) and pg_temp.evn(pg_temp.u('a'), 'ind_low_approval') = 1, 'low approval warns the holder once');
  perform pg_temp.login(pg_temp.u('f')); r := ind_vote(v_hid, false);
  perform pg_temp.assert(pg_temp.evn(pg_temp.u('a'), 'ind_low_approval') = 1, 'warned only once');
  perform pg_temp.assert((select status from ind_holders where id = v_hid) = 'active', 'a low rating removes nobody');
  perform pg_temp.login(pg_temp.u('adm'));
  perform pg_temp.assert((select (o->'holder'->>'low_approval')::boolean from jsonb_array_elements(admin_ind_overview()->'offices') o where o->>'id' = 'bank_governor'), 'admin sees it highlighted');
  raise notice 'ok 8: approval';
end $$;

-- ---------- 9. official statement ----------
do $$
declare r jsonb; v_b int; v_hid bigint;
begin
  select id into v_hid from ind_holders where user_id = pg_temp.u('a') and status = 'active';
  perform pg_temp.login(pg_temp.u('e'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_statement('I am not a holder but I talk anyway.') $q$) = 'not_holder', 'holders only');
  perform pg_temp.at(pg_temp.u('a'), 'third_east');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_statement('short') $q$) = 'too_short', 'statement too short');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_statement(repeat('y', 300)) $q$) = 'too_long', 'statement too long');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_statement('Visit www.example.com now for the plan') $q$) = 'blocked_text', 'no links');
  v_b := pg_temp.bcall();
  r := ind_statement('The bank counter is safe and the fees are fair.');
  perform pg_temp.assert(pg_temp.bcall() = v_b + 1 and exists (select 1 from broadcasts where title = 'Official statement: Governor of the Bank'), 'a public notice');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_statement('Another statement in the same day, abeg.') $q$) = 'cooldown', 'one statement a day');
  perform pg_temp.assert((select o->'holder'->'statement'->>'body' from jsonb_array_elements(ind_status()->'offices') o where o->>'id' = 'bank_governor') = 'The bank counter is safe and the fees are fair.', 'shown in the Industry offices list');
  perform pg_temp.advance(25 * 3600);
  perform pg_temp.at(pg_temp.u('a'), 'third_east');
  r := ind_statement('Second day, second statement, all is well.');
  perform pg_temp.assert((select count(*) from ind_statements where holder_id = v_hid) = 2, 'a new statement the next day');
  raise notice 'ok 9: statement';
end $$;

-- ---------- 10. admin RPCs and the Content editors ----------
do $$
declare r jsonb;
begin
  perform pg_temp.login(pg_temp.u('adm'));
  r := admin_ind_overview();
  perform pg_temp.assert(jsonb_array_length(r->'offices') = 7 and jsonb_array_length(r->'applicants') >= 0 and jsonb_array_length(r->'audit') > 3, 'overview: offices, applicants, audit');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(r->'offices') o where o->'holder' is not null and o->>'holder' <> 'null') >= 1, 'overview shows holders');
  r := admin_row_upsert('ind_levers', jsonb_build_object('id', 'bank.stamp', 'band_min', 30, 'band_max', 70, 'cooldown_hours', 12));
  perform pg_temp.assert((select band_min from ind_levers where id = 'bank.stamp') = 30 and (select cooldown_hours from ind_levers where id = 'bank.stamp') = 12, 'admin edits a band and a cooldown');
  r := admin_row_upsert('ind_offices', jsonb_build_object('id', 'bank_governor', 'salary_per_day', 5500000));
  perform pg_temp.assert((select salary_per_day from ind_offices where id = 'bank_governor') = 5500000, 'admin edits a salary');
  update ind_offices set salary_per_day = 5000000 where id = 'bank_governor';
  perform pg_temp.login(pg_temp.u('e'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_row_upsert('ind_levers', '{"id":"bank.stamp","band_min":1}'::jsonb) $q$) = 'not_admin', 'players cannot edit the catalogue');
  raise notice 'ok 10: admin';
end $$;

-- ---------- 11. health lever: the shop reads it ----------
do $$
declare r jsonb; v_p bigint; i items;
begin
  perform pg_temp.login(pg_temp.u('adm'));
  r := admin_ind_remove_holder((select id from ind_holders where user_id = pg_temp.u('a') and status = 'active'), 'making room');
  perform admin_ind_appoint('health_commissioner', 'IO_B', 'health');
  perform pg_temp.at(pg_temp.u('b'), 'third_east');
  perform pg_temp.login(pg_temp.u('b'));
  select * into i from items where id = 'pain_relief';
  perform pg_temp.assert(bl_dealer_net(i, 'ubth') = 300, 'normal medicine price: ' || bl_dealer_net(i, 'ubth'));
  r := ind_set_lever('health.price', 80);
  perform pg_temp.assert(pg_temp.cv('health.price_pct') = 80 and bl_dealer_net(i, 'ubth') = 240, 'medicine is 20 percent cheaper: ' || bl_dealer_net(i, 'ubth'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('health.price', 60) $q$) in ('out_of_band', 'cooldown'), 'band');
  perform pg_temp.advance(25 * 3600);
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('health.price', 70) $q$) = 'out_of_band', 'band of 75 to 125');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('health.stay', 50) $q$) = 'out_of_band', 'hospital stay band 20 to 40');
  r := ind_resign();
  perform pg_temp.assert(pg_temp.cv('health.price_pct') = 100 and bl_dealer_net(i, 'ubth') = 300, 'resigning restores the price');
  raise notice 'ok 11: health';
end $$;

-- ---------- 11b. My Office: visibility follows the seat, powers refuse non holders ----------
do $$
declare r jsonb; v_hid bigint;
begin
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.office_mine()'::regprocedure, 'execute') and not has_function_privilege('anon', 'public.office_mine()'::regprocedure, 'execute'), 'office_mine grants');
  perform pg_temp.login(pg_temp.u('e'));
  perform pg_temp.assert(not (office_mine()->>'holds')::boolean, 'a non holder has no My Office');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('bank.fee1', 0.9) $q$) = 'not_holder' and pg_temp.hint_of($q$ select ind_statement('Not a holder but talking anyway.') $q$) = 'not_holder'
    and pg_temp.hint_of($q$ select pol_ward_notice('Not a councillor but trying anyway.') $q$) = 'not_councillor' and pg_temp.hint_of($q$ select pol_announce('Not a governor but trying anyway.') $q$) = 'not_governor'
    and pg_temp.hint_of($q$ select pol_appoint('commissioner_works', 'IO_F') $q$) = 'not_governor', 'every power refuses a non holder on the server');
  -- an industry holder
  perform pg_temp.login(pg_temp.u('adm'));
  r := admin_ind_appoint('education_commissioner', 'IO_E', 'my office');
  v_hid := (r->>'id')::bigint;
  perform pg_temp.at(pg_temp.u('e'), 'third_east');
  perform pg_temp.login(pg_temp.u('e'));
  r := office_mine();
  perform pg_temp.assert((r->>'holds')::boolean and r->>'kind' = 'industry' and r->>'title' = 'Edu. Comm.' and (r->>'salary_per_day')::bigint = 1000000 and (r->>'days_left')::numeric between 13.9 and 14, 'holder sees it: ' || r::text);
  -- removed: gone at once
  perform pg_temp.login(pg_temp.u('adm'));
  r := admin_ind_remove_holder(v_hid, 'my office test');
  perform pg_temp.login(pg_temp.u('e'));
  perform pg_temp.assert(not (office_mine()->>'holds')::boolean, 'removed: the app is gone');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('education.course_fee', 0.9) $q$) = 'not_holder', 'removed holder refused');
  -- term end
  perform pg_temp.login(pg_temp.u('adm'));
  r := admin_ind_appoint('education_commissioner', 'IO_E', 'my office');
  perform pg_temp.cfg('offices.inactive_days', '90');
  perform pg_temp.login(pg_temp.u('e'));
  perform pg_temp.assert((office_mine()->>'holds')::boolean, 'holds again');
  perform pg_temp.advance(15 * 86400);
  perform pg_temp.assert(not (office_mine()->>'holds')::boolean, 'term over: the app is gone');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_statement('Term is over but I still talk.') $q$) = 'not_holder', 'refused after the term');
  perform pg_temp.cfg('offices.inactive_days', '5');
  -- a political holder (a Councillor sworn in): the app shows, with the existing powers
  insert into office_holders (office_id, ward_id, user_id, status, term_start, term_end, paid_through)
    values ('councillor', 'uselu', pg_temp.u('f'), 'active', bl_now(), bl_now() + interval '14 days', bl_now());
  perform pg_temp.login(pg_temp.u('f'));
  r := office_mine();
  perform pg_temp.assert((r->>'holds')::boolean and r->>'kind' = 'political' and r->>'office_kind' = 'councillor' and r->>'title' = 'Hon.', 'a councillor sees My Office: ' || r::text);
  update office_holders set status = 'removed' where user_id = pg_temp.u('f');
  perform pg_temp.assert(not (office_mine()->>'holds')::boolean, 'political seat ended: the app is gone');
  perform pg_temp.assert(pg_temp.hint_of($q$ select pol_ward_notice('A ward notice after the seat ended.') $q$) = 'not_councillor', 'old powers refuse after the seat ended');
  raise notice 'ok 11b: my office';
end $$;

-- ---------- 12. switch off, election untouched ----------
do $$
declare r jsonb;
begin
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_ind_appoint('transport_commissioner', 'IO_C', 'switch');
  perform pg_temp.cfg('offices.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_apply('bank_governor', 'Switched off, but I try anyway abeg.') $q$) = 'disabled', 'apply refused when off');
  perform pg_temp.login(pg_temp.u('c'));
  perform pg_temp.assert(pg_temp.hint_of($q$ select ind_set_lever('transport.keke_base', 120) $q$) = 'disabled', 'levers refused when off');
  perform pg_temp.assert(bl_pol_title(pg_temp.u('c')) is null, 'no badge when off');
  perform pg_temp.cfg('offices.enabled', 'true');
  perform pg_temp.assert(bl_pol_title(pg_temp.u('c')) = 'Transport Comm.', 'badge back when on');
  r := ind_set_lever('transport.keke_base', 120);
  perform pg_temp.assert(pg_temp.cv('travel.keke.base_cost') = 120, 'keke base fare moved');
  perform pg_temp.assert((select count(*) from offices) >= 12 and not exists (select 1 from offices where id in ('bank_governor', 'nepa_md')), 'political offices untouched, industry offices live in their own table');
  raise notice 'ok 12: switch off';
end $$;
