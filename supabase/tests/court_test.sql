-- The Court (20261111000100_court.sql, 20261111000200_court_rpcs.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/court_test.sql
-- Weekly rent is clock-dependent and would add a charge to the money checks, so it is off here.
update public.game_config set value = 'false'::jsonb where key in ('rent.enabled', 'economy.bills_enabled');
-- Time moves with bl.test_offset_seconds. Groups:
--  1 grants, RLS, anon refused, helpers private · 2 settings and judge offices seeded · 3 filing only from recorded events (every refusal, fee tiers, sink)
--  4 lawyers: register, requirements, fee, list / search / available / top, rank, update, retire · 5 hiring: escrow, accept, decline, both sides, refusals, expiry
--  6 judges: appoint, badge, assignment, statements, gallery limit, ruling window, guilty (restitution cash then bank, fine sink, lawyer pay, cred, alerts)
--  7 not guilty (fee lost) · 8 automatic ruling after the window, court debt, collection from income, not earnings, debt cleared, debt off
--  9 jail for repeat offenders · 10 statement cleaning and caps · 11 anti-abuse · 12 other case types (rent owed, unfair eviction, overcharge)
-- 13 admin: overview, override (audited, money back), dismiss, judges, ban lawyer · 14 realtime RLS on statements · 15 patched functions (push, label, earn reasons)
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

create or replace function pg_temp.u(p_name text) returns uuid
language sql as $$ select current_setting('ct.' || p_name)::uuid; $$;

create or replace function pg_temp.mk(p_name text, p_old boolean default true) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user('ct_' || p_name || '@court.bl');
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(v);
  perform create_profile_v2('CT_' || p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  if p_old then update profiles set created_at = now() - interval '30 days' where id = v; end if;
  update profiles set location_id = 'oba_market', last_seen = now(), cash = 0, bank = 0, protected_until = null where id = v;
  perform set_config('ct.' || p_name, v::text, true);
  return v;
end $$;

create or replace function pg_temp.money(p_name text, p_cash bigint, p_bank bigint) returns void
language sql as $$ update profiles set cash = p_cash, bank = p_bank where id = pg_temp.u(p_name); $$;

create or replace function pg_temp.cash(p_name text) returns bigint language sql as $$ select cash from profiles where id = pg_temp.u(p_name); $$;
create or replace function pg_temp.bank(p_name text) returns bigint language sql as $$ select bank from profiles where id = pg_temp.u(p_name); $$;
create or replace function pg_temp.total(p_name text) returns bigint language sql as $$ select cash + bank from profiles where id = pg_temp.u(p_name); $$;

-- a recorded pickpocket (thief -> victim)
create or replace function pg_temp.theft(p_thief text, p_victim text, p_amount bigint, p_status text default 'success', p_age_hours numeric default 1) returns bigint
language plpgsql as $$
declare v_id bigint;
begin
  insert into crime_attempts (thief_id, victim_id, location_id, started_at, resolve_at, status, amount, resolved_at)
  values (pg_temp.u(p_thief), pg_temp.u(p_victim), 'oba_market', bl_now() - make_interval(hours => 0, secs => p_age_hours * 3600 + 5),
          bl_now() - make_interval(secs => p_age_hours * 3600), p_status, p_amount, bl_now() - make_interval(secs => p_age_hours * 3600))
  returning id into v_id;
  return v_id;
end $$;

create or replace function pg_temp.file(p_name text, p_kind text, p_ref text, p_lawyer text default null) returns jsonb
language plpgsql as $$
begin
  perform pg_temp.login(pg_temp.u(p_name));
  return court_file(p_kind, p_ref, case when p_lawyer is null then null else pg_temp.u(p_lawyer) end);
end $$;

create or replace function pg_temp.call(p_name text, p_sql text) returns text
language plpgsql as $$
begin
  perform pg_temp.login(pg_temp.u(p_name));
  return pg_temp.hint_of(p_sql);
end $$;

create or replace function pg_temp.case_id(p_json jsonb) returns bigint language sql as $$ select (p_json -> 'case' ->> 'id')::bigint; $$;
create or replace function pg_temp.reasons(p_name text, p_reason text) returns bigint
language sql as $$ select coalesce(sum(delta), 0)::bigint from ledger where user_id = pg_temp.u(p_name) and reason = p_reason; $$;

-- ---------- setup ----------
do $$
declare v uuid;
begin
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.mk('adm');
  perform pg_temp.mk('p'); perform pg_temp.mk('d'); perform pg_temp.mk('x');
  perform pg_temp.mk('l1'); perform pg_temp.mk('l2'); perform pg_temp.mk('l3');
  perform pg_temp.mk('j1'); perform pg_temp.mk('j2');
  perform pg_temp.mk('g1'); perform pg_temp.mk('g2'); perform pg_temp.mk('g3');
  perform pg_temp.mk('n', false);
  update profiles set is_admin = true where id = pg_temp.u('adm');
  insert into player_certificates (user_id, cert_id, source) values (pg_temp.u('l1'), 'law', 'admin'), (pg_temp.u('l2'), 'law', 'admin'), (pg_temp.u('l3'), 'law', 'admin');
  perform pg_temp.cfg('court.file_cooldown_minutes', '0');
  perform pg_temp.cfg('court.max_open_cases', '50');
  perform pg_temp.cfg('court.max_per_day', '100');
  perform pg_temp.cfg('court.gallery_size', '2');
  perform pg_temp.cfg('offices.enabled', 'true');
  perform pg_temp.money('p', 50000, 1000000);
  perform pg_temp.money('d', 30000, 100000);
  perform pg_temp.money('l1', 0, 100000); perform pg_temp.money('l2', 0, 100000); perform pg_temp.money('l3', 0, 100000);
end $$;

-- ---------- 1. grants, RLS, anon ----------
do $$
declare v_rpc text; v_t text;
begin
  foreach v_rpc in array array['court_status()', 'court_events()', 'court_file(text,text,uuid)', 'court_lawyers_list(text,text,integer)', 'court_lawyer_register(bigint,text)',
      'court_lawyer_update(bigint,text,boolean)', 'court_lawyer_retire()', 'court_hire(bigint,uuid)', 'court_hire_respond(bigint,boolean)', 'court_hire_cancel(bigint)',
      'court_case(bigint)', 'court_live()', 'court_post(bigint,text)', 'court_rule(bigint,text,text)', 'court_judge_take(bigint)', 'court_gallery_join(bigint)',
      'court_gallery_leave(bigint)', 'court_after(bigint,bigint)', 'admin_court_overview(text)', 'admin_court_override(bigint,text,text)', 'admin_court_dismiss(bigint,text)',
      'admin_court_appoint_judge(text,text)', 'admin_court_remove_judge(bigint,text)', 'admin_court_ban_lawyer(uuid,boolean,text)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'auth may ' || v_rpc);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v_rpc)::regprocedure), 'secdef ' || v_rpc);
    perform pg_temp.assert((select provolatile from pg_proc where oid = ('public.' || v_rpc)::regprocedure) = 'v', 'volatile, not stable: ' || v_rpc);
  end loop;
  -- every bl_court_* helper is private
  perform pg_temp.assert(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'bl\_court\_%'
                                      and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))), 'bl_court_* helpers private');
  perform pg_temp.assert((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'bl\_court\_%') >= 25, 'helpers exist');
  foreach v_t in array array['court_lawyers', 'court_cases', 'court_hires', 'court_statements', 'court_gallery', 'court_debts'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || v_t)::regclass), 'RLS on ' || v_t);
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || v_t, 'select'), 'anon no read ' || v_t);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || v_t, 'insert') and not has_table_privilege('authenticated', 'public.' || v_t, 'update')
                           and not has_table_privilege('authenticated', 'public.' || v_t, 'delete'), 'no client writes ' || v_t);
  end loop;
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.court_cases', 'select') and not has_table_privilege('authenticated', 'public.court_debts', 'select'), 'cases and debts only through RPCs');
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.court_statements', 'select'), 'statements readable (realtime), by policy');
  perform pg_temp.assert(exists (select 1 from pg_policies where tablename = 'court_statements' and policyname = 'court_statements_read'), 'statements policy');
  perform pg_temp.assert(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'court_statements'), 'statements in realtime publication');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.court_can_see(bigint)'::regprocedure, 'execute') and not has_function_privilege('anon', 'public.court_can_see(bigint)'::regprocedure, 'execute'), 'court_can_see grant');
  perform pg_temp.assert(not exists (select 1 from information_schema.table_constraints tc join information_schema.constraint_column_usage cu on cu.constraint_name = tc.constraint_name
                         where tc.table_name like 'court\_%' and tc.constraint_type = 'FOREIGN KEY' and cu.table_name = 'profiles'), 'no foreign keys to profiles');
  raise notice 'ok 1: grants / RLS / helpers private / volatile';
end $$;

set local role anon;
do $$
begin
  perform pg_temp.assert(pg_temp.hint_of('select court_status()') like '%permission denied%', 'anon status refused');
  perform pg_temp.assert(pg_temp.hint_of('select court_live()') like '%permission denied%', 'anon live refused');
  perform pg_temp.assert(pg_temp.hint_of('select admin_court_overview()') like '%permission denied%', 'anon admin refused');
end $$;
reset role;

-- ---------- 2. settings and offices ----------
do $$
begin
  perform pg_temp.assert((select count(*) from game_config where category = 'court') >= 40, 'court settings');
  perform pg_temp.assert((select count(*) from game_config where category = 'court' and (label = '' or description = '' or min is null and max is null and kind not in ('bool', 'text'))) = 0, 'every court setting has label, description and band');
  perform pg_temp.assert((select count(*) from ind_offices where id like 'court\_judge\_%' and title = 'Hon. Justice' and salary_per_day > 0) = 4, 'four judge offices with salary and badge');
  perform pg_temp.assert(exists (select 1 from courses where id = 'law_advocacy' and cert_id = 'law') and exists (select 1 from certificates where id = 'law'), 'law course and certificate');
  raise notice 'ok 2: settings and offices';
end $$;

-- ---------- 3. filing only from recorded events ----------
do $$
declare
  v_a bigint; v_old bigint; v_other bigint; v_fail bigint; v_big bigint; v_self bigint; r jsonb; v_before bigint; v_sum_before bigint; v_sum_after bigint; v_n bigint;
begin
  v_a := pg_temp.theft('d', 'p', 80000);
  v_other := pg_temp.theft('p', 'd', 5000);                    -- the other way round
  v_fail := pg_temp.theft('d', 'p', 7000, 'caught');
  v_old := pg_temp.theft('d', 'p', 9000, 'success', 100);       -- 100 hours ago: outside the 72 h look-back
  v_big := pg_temp.theft('d', 'p', 300000);
  v_self := pg_temp.theft('p', 'p', 4000);
  -- every refusal
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'pickpocket', 'abc')) = 'no_record', 'bad ref refused');
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'gossip', v_a::text)) = 'no_record', 'unknown kind refused (free-text accusations do not exist)');
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'pickpocket', v_other::text)) = 'no_record', 'someone else''s event refused');
  perform pg_temp.assert(pg_temp.call('d', format('select court_file(%L, %L)', 'pickpocket', v_a::text)) = 'no_record', 'the thief cannot file the victim''s event');
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'pickpocket', v_fail::text)) = 'no_record', 'a caught (failed) attempt is not a loss');
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'pickpocket', v_old::text)) = 'no_record', 'older than the look-back refused');
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'pickpocket', v_self::text)) = 'self', 'suing yourself refused');
  perform pg_temp.assert(pg_temp.call('n', format('select court_file(%L, %L)', 'pickpocket', v_a::text)) = 'blocked', 'a brand-new account cannot file');
  perform pg_temp.cfg('court.type_pickpocket_enabled', 'false');
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'pickpocket', v_a::text)) = 'no_record', 'a switched-off case type refused');
  perform pg_temp.cfg('court.type_pickpocket_enabled', 'true');
  perform pg_temp.cfg('court.enabled', 'false');
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'pickpocket', v_a::text)) = 'disabled', 'court closed: nobody files');
  perform pg_temp.cfg('court.enabled', 'true');
  -- the event list shows only what the game recorded for ME
  perform pg_temp.login(pg_temp.u('p'));
  r := court_events();
  perform pg_temp.assert((select count(*) from jsonb_array_elements(r -> 'events') e where e ->> 'kind' = 'pickpocket') = 2, 'two recent recorded thefts are listed (not the old, caught, self or others)');
  perform pg_temp.assert((r -> 'events' -> 0 ->> 'defendant_name') is not null and (r ->> 'filing_fee')::bigint = 5000 and (r ->> 'customary_fee')::bigint = 1500, 'event rows carry the defendant and the fees');
  -- a valid filing: Customary Court (claim 80,000 <= 100,000), fee 1,500 is a sink
  select sum(cash + bank) into v_sum_before from profiles;
  v_before := pg_temp.total('p');
  r := pg_temp.file('p', 'pickpocket', v_a::text);
  select sum(cash + bank) into v_sum_after from profiles;
  perform pg_temp.assert(r -> 'case' ->> 'case_no' ~ '^CC/[0-9]+/20[0-9]{2}$', 'customary case number like CC/1234/2026: ' || (r -> 'case' ->> 'case_no'));
  perform pg_temp.assert(v_before - pg_temp.total('p') = 1500 and v_sum_before - v_sum_after = 1500, 'filing fee 1,500 charged and destroyed (a sink, nobody gets it)');
  perform pg_temp.assert(pg_temp.reasons('p', 'court_fee') = -1500, 'ledger court_fee');
  perform pg_temp.assert((select claim from court_cases where id = pg_temp.case_id(r)) = 80000 and (select defendant_id from court_cases where id = pg_temp.case_id(r)) = pg_temp.u('d'), 'claim and defendant come from the record');
  perform pg_temp.assert((select hearing_at - created_at from court_cases where id = pg_temp.case_id(r)) = interval '30 minutes', 'hearing 30 minutes after filing');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('d') and kind = 'court_summons'), 'the defendant is summoned (alert)');
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'pickpocket', v_a::text)) = 'already_filed', 'one case per event');
  -- High Court for a big claim: fee 5,000, number BC/..
  v_before := pg_temp.total('p');
  r := pg_temp.file('p', 'pickpocket', v_big::text);
  perform pg_temp.assert(r -> 'case' ->> 'case_no' ~ '^BC/[0-9]+/20[0-9]{2}$' and v_before - pg_temp.total('p') = 5000, 'High Court number BC/.. and fee 5,000');
  select count(*) into v_n from court_cases where plaintiff_id = pg_temp.u('p');
  perform pg_temp.assert(v_n = 2, 'two cases so far');
  -- clean up: dismiss them so the later groups start fresh
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_court_dismiss(c.id, 'test cleanup') from court_cases c where c.plaintiff_id = pg_temp.u('p') and c.status = 'scheduled';
  perform pg_temp.assert((select count(*) from court_cases where status = 'dismissed') = 2, 'dismissed');
  perform pg_temp.assert(not exists (select 1 from court_cases where status = 'scheduled'), 'no open cases');
  -- the filed event is free again after a dismissal
  perform pg_temp.assert((select count(*) from jsonb_array_elements(court_events() -> 'events') e where (e ->> 'filed')::boolean) = 0, 'dismissed events can be filed again');
  raise notice 'ok 3: filing only from recorded events';
end $$;

-- ---------- 4. lawyers ----------
do $$
declare r jsonb; v_names text;
begin
  -- requirements: the Law certificate
  perform pg_temp.assert(pg_temp.call('g1', 'select court_lawyer_register(10000, ''hi'')') = 'requirements', 'no certificate: cannot register');
  perform pg_temp.assert(pg_temp.call('n', 'select court_lawyer_register(10000, ''hi'')') = 'requirements', 'account too new: cannot register');
  perform pg_temp.assert(pg_temp.call('l1', 'select court_lawyer_register(100, ''hi'')') = 'bad_fee', 'fee below the minimum refused');
  perform pg_temp.assert(pg_temp.call('l1', 'select court_lawyer_register(999999999, ''hi'')') = 'bad_fee', 'fee above the maximum refused');
  perform pg_temp.login(pg_temp.u('l1'));
  r := court_lawyer_register(10000, 'Fast, fair and f' || 'uck free.');
  perform pg_temp.assert(r -> 'lawyer' ->> 'rank' = 'Junior Lawyer' and (r -> 'lawyer' ->> 'fee')::bigint = 10000, 'registered as a Junior Lawyer');
  perform pg_temp.assert((r -> 'lawyer' ->> 'bio') like '%****%' and (r -> 'lawyer' ->> 'bio') not like '%fuck%', 'bio is cleaned and masked');
  perform pg_temp.login(pg_temp.u('l2')); perform court_lawyer_register(5000, 'Cheap and cheerful');
  perform pg_temp.login(pg_temp.u('l3')); perform court_lawyer_register(7000, 'Property law');
  -- admin setting lets players register without the certificate
  perform pg_temp.cfg('court.lawyer_cert', '""');
  perform pg_temp.login(pg_temp.u('g1'));
  perform court_lawyer_register(3000, 'No cert needed now');
  perform pg_temp.assert((court_status() -> 'lawyer' ->> 'fee')::bigint = 3000, 'registered once the certificate rule is off');
  perform court_lawyer_retire();
  perform pg_temp.cfg('court.lawyer_cert', '"law"');
  perform pg_temp.assert(pg_temp.call('g1', 'select court_lawyer_register(3000, ''again'')') = 'requirements', 'a retired lawyer without the certificate cannot come back');
  -- a sitting judge cannot practise
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_court_appoint_judge('CT_j2', 'test');
  update player_certificates set cert_id = 'law' where false;
  insert into player_certificates (user_id, cert_id, source) values (pg_temp.u('j2'), 'law', 'admin') on conflict do nothing;
  perform pg_temp.assert(pg_temp.call('j2', 'select court_lawyer_register(5000, ''judge'')') = 'requirements', 'a sitting judge cannot register as a lawyer');
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_court_remove_judge((select id from ind_holders where user_id = pg_temp.u('j2') and status = 'active'), 'test: seat is not needed');
  -- list, search, available now, top by wins
  update court_lawyers set wins = 7, losses = 1 where user_id = pg_temp.u('l2');
  update court_lawyers set wins = 20, losses = 2 where user_id = pg_temp.u('l3');
  update profiles set last_seen = now() - interval '2 hours' where id = pg_temp.u('l3');
  perform pg_temp.login(pg_temp.u('p'));
  r := court_lawyers_list('', 'all', 30);
  perform pg_temp.assert(jsonb_array_length(r) = 3, 'three lawyers listed (the retired one is hidden)');
  perform pg_temp.assert(r -> 0 ->> 'username' = 'CT_l2', 'available lawyers first, by wins (l3 is not online)');
  r := court_lawyers_list('', 'top', 30);
  perform pg_temp.assert(r -> 0 ->> 'username' = 'CT_l3' and r -> 0 ->> 'rank' = 'Advocate' is not null, 'top by wins puts l3 first');
  perform pg_temp.assert(r -> 0 ->> 'rank' = 'Barrister', 'rank by wins: 20 wins = Barrister');
  r := court_lawyers_list('', 'available', 30);
  perform pg_temp.assert(jsonb_array_length(r) = 2 and not exists (select 1 from jsonb_array_elements(r) e where e ->> 'username' = 'CT_l3'), 'available now hides the offline lawyer');
  r := court_lawyers_list('@ct_l1', 'all', 30);
  perform pg_temp.assert(jsonb_array_length(r) = 1 and r -> 0 ->> 'username' = 'CT_l1', 'search by @name');
  r := court_lawyers_list('%', 'all', 30);
  perform pg_temp.assert(jsonb_array_length(r) = 0, 'a % in the search is a plain character, not a wildcard');
  perform pg_temp.assert(court_lawyers_list('', 'all', 30) -> 0 ->> 'rank' is not null, 'rank on every card');
  update court_lawyers set wins = 40 where user_id = pg_temp.u('l1');
  perform pg_temp.assert(bl_court_rank(4) = 'Junior Lawyer' and bl_court_rank(5) = 'Advocate' and bl_court_rank(15) = 'Barrister' and bl_court_rank(40) = 'Senior Advocate', 'rank thresholds');
  update court_lawyers set wins = 0 where user_id = pg_temp.u('l1');
  -- update fee / availability
  perform pg_temp.login(pg_temp.u('l1'));
  perform court_lawyer_update(12000, null, true);
  perform pg_temp.assert((select fee from court_lawyers where user_id = pg_temp.u('l1')) = 12000, 'fee updated');
  perform pg_temp.assert(pg_temp.call('l1', 'select court_lawyer_update(1, null, true)') = 'bad_fee', 'update checks the band');
  perform court_lawyer_update(10000, null, true);
  perform pg_temp.assert(pg_temp.call('p', 'select court_lawyer_update(5000, null, true)') = 'not_lawyer', 'only lawyers update');
  raise notice 'ok 4: lawyers';
end $$;

-- ---------- 5 + 6 + 7. a full case with lawyers, a judge, a live hearing, a gallery and a verdict ----------
do $$
declare
  v_ev bigint; r jsonb; v_case bigint; v_h1 bigint; v_h2 bigint; v_p0 bigint; v_d0 bigint; v_l10 bigint; v_l20 bigint; v_sum0 bigint; v_n int; v_hires jsonb;
  v_hold bigint;
begin
  -- judge: appoint j1 (badge, salary office)
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_court_appoint_judge('@CT_j1', 'first judge');
  perform pg_temp.assert(bl_court_judge_ok(pg_temp.u('j1')) and bl_pol_title(pg_temp.u('j1')) = 'Hon. Justice', 'judge holds the office and the "Hon. Justice" badge');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'court_judge_appoint' and target_user = pg_temp.u('j1')), 'appointment audited');
  perform pg_temp.assert(pg_temp.call('p', 'select admin_court_appoint_judge(''CT_g1'', '''')') like '%permission%' or pg_temp.call('p', 'select admin_court_appoint_judge(''CT_g1'', '''')') = 'not_admin', 'a player cannot appoint a judge');
  perform pg_temp.assert(pg_temp.call('adm', 'select admin_court_appoint_judge(''CT_j1'', '''')') = 'holds_office', 'one office at a time');

  -- file with a lawyer: fee + escrow
  perform pg_temp.money('p', 50000, 1000000);
  perform pg_temp.money('d', 30000, 100000);
  v_ev := pg_temp.theft('d', 'p', 80000);
  v_p0 := pg_temp.total('p'); v_d0 := pg_temp.total('d'); v_l10 := pg_temp.total('l1'); v_l20 := pg_temp.total('l2');
  r := pg_temp.file('p', 'pickpocket', v_ev::text, 'l1');
  v_case := pg_temp.case_id(r);
  perform pg_temp.assert(v_p0 - pg_temp.total('p') = 1500 + 10000, 'fee 1,500 + lawyer fee 10,000 held in escrow');
  perform pg_temp.assert(pg_temp.total('l1') = v_l10, 'the lawyer is not paid yet');
  perform pg_temp.assert(pg_temp.reasons('p', 'lawyer_escrow') = -10000, 'ledger lawyer_escrow');
  perform pg_temp.assert((select judge_id from court_cases where id = v_case) = pg_temp.u('j1'), 'judge j1 assigned (not a party, not a lawyer)');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('j1') and kind = 'court_assigned') and exists (select 1 from events where user_id = pg_temp.u('l1') and kind = 'court_hire_request'), 'judge and lawyer alerted');
  select id into v_h1 from court_hires where case_id = v_case and side = 'plaintiff';
  -- refusals around hiring
  perform pg_temp.assert(pg_temp.call('d', format('select court_hire(%s, %L)', v_case, pg_temp.u('l1'))) = 'lawyer_taken', 'a lawyer cannot take both sides');
  perform pg_temp.assert(pg_temp.call('d', format('select court_hire(%s, %L)', v_case, pg_temp.u('p'))) = 'lawyer_unavailable', 'a non-lawyer cannot be hired');
  perform pg_temp.assert(pg_temp.call('g2', format('select court_hire(%s, %L)', v_case, pg_temp.u('l2'))) = 'not_party', 'only the two sides hire');
  perform pg_temp.assert(pg_temp.call('l2', format('select court_hire_respond(%s, true)', v_h1)) = 'not_yours', 'only the hired lawyer answers');
  perform pg_temp.assert(pg_temp.call('p', format('select court_hire(%s, %L)', v_case, pg_temp.u('l2'))) = 'has_lawyer', 'one lawyer per side');
  -- a lawyer who is also the plaintiff? register p as a lawyer (cert) and let d try to hire them
  insert into player_certificates (user_id, cert_id, source) values (pg_temp.u('p'), 'law', 'admin') on conflict do nothing;
  perform pg_temp.login(pg_temp.u('p')); perform court_lawyer_register(3000, 'self');
  perform pg_temp.assert(pg_temp.call('d', format('select court_hire(%s, %L)', v_case, pg_temp.u('p'))) = 'lawyer_party', 'a lawyer cannot act in a case they are a party to');
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L, %L)', 'pickpocket', '0', pg_temp.u('p'))) in ('lawyer_self', 'no_record'), 'you cannot be your own lawyer');
  -- decline returns the escrow
  perform pg_temp.login(pg_temp.u('l1'));
  v_hold := pg_temp.total('p');
  perform court_hire_respond(v_h1, false);
  perform pg_temp.assert(pg_temp.total('p') = v_hold + 10000 and (select status from court_hires where id = v_h1) = 'declined', 'declined: the fee is back');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('p') and kind = 'court_hire_answer'), 'client told');
  -- hire again (a second attempt), accept
  perform pg_temp.login(pg_temp.u('p'));
  perform court_hire(v_case, pg_temp.u('l1'));
  select id into v_h1 from court_hires where case_id = v_case and side = 'plaintiff' and status = 'pending';
  perform pg_temp.login(pg_temp.u('l1'));
  r := court_status();
  perform pg_temp.assert(jsonb_array_length(r -> 'hire_requests') = 1, 'the lawyer sees the request');
  perform court_hire_respond(v_h1, true);
  perform pg_temp.assert((select status from court_hires where id = v_h1) = 'accepted', 'accepted');
  -- the defendant hires l2 and accepts
  perform pg_temp.login(pg_temp.u('d'));
  perform court_hire(v_case, pg_temp.u('l2'));
  select id into v_h2 from court_hires where case_id = v_case and side = 'defendant' and status = 'pending';
  perform pg_temp.assert(v_d0 - pg_temp.total('d') = 5000, 'the defendant''s escrow 5,000');
  perform pg_temp.login(pg_temp.u('l2')); perform court_hire_respond(v_h2, true);
  -- the hire is refused once the hearing has started
  perform pg_temp.assert(pg_temp.call('p', format('select court_hire(%s, %L)', v_case, pg_temp.u('l3'))) = 'has_lawyer', 'plaintiff already has one');

  -- before the hearing: statements refused, the gallery can be joined
  perform pg_temp.assert(pg_temp.call('p', format('select court_post(%s, %L)', v_case, 'hello')) = 'not_started', 'no statements before the hearing starts');
  perform pg_temp.assert(pg_temp.call('j1', format('select court_rule(%s, %L, %L)', v_case, 'guilty', '')) = 'too_early', 'the judge cannot rule before the hearing');
  perform pg_temp.advance(31 * 60);
  update profiles set last_seen = now() where id in (select id from profiles where username like 'CT\_%');
  -- the hearing is LIVE
  perform pg_temp.login(pg_temp.u('g1'));
  r := court_live();
  perform pg_temp.assert(jsonb_array_length(r -> 'live') = 1 and (r -> 'live' -> 0 ->> 'live')::boolean and r -> 'live' -> 0 ->> 'case_no' = (select case_no from court_cases where id = v_case), 'Live now: the card shows LIVE');
  perform pg_temp.assert(r -> 'live' -> 0 -> 'plaintiff' ->> 'username' = 'CT_p' and r -> 'live' -> 0 -> 'defendant' ->> 'username' = 'CT_d' and (r -> 'live' -> 0 -> 'plaintiff' -> 'avatar') is not null, 'card has both parties with avatars');
  perform pg_temp.assert(pg_temp.call('g1', format('select court_after(%s, 0)', v_case)) = 'not_seated', 'a visitor must take a seat before watching');
  -- gallery limit 2
  perform pg_temp.login(pg_temp.u('g1')); perform court_gallery_join(v_case);
  perform pg_temp.login(pg_temp.u('g2')); perform court_gallery_join(v_case);
  perform pg_temp.assert(pg_temp.call('g3', format('select court_gallery_join(%s)', v_case)) = 'gallery_full', 'gallery limit: the third watcher is refused');
  perform pg_temp.login(pg_temp.u('p')); r := court_gallery_join(v_case);
  perform pg_temp.assert((r ->> 'participant')::boolean and not exists (select 1 from court_gallery where case_id = v_case and user_id = pg_temp.u('p')), 'parties never use a seat');
  perform pg_temp.login(pg_temp.u('g2')); perform court_gallery_leave(v_case);
  perform pg_temp.assert(pg_temp.call('g3', format('select court_gallery_join(%s)', v_case)) = 'ok', 'a free seat after someone leaves');
  perform pg_temp.assert(bl_court_gallery_count(v_case) = 2, 'gallery count 2');
  -- seats of idle watchers are freed
  perform pg_temp.advance(11 * 60);
  perform pg_temp.assert(bl_court_gallery_count(v_case) = 0, 'idle watchers do not count');
  perform pg_temp.login(pg_temp.u('g1')); perform court_gallery_join(v_case);
  perform pg_temp.login(pg_temp.u('g2')); perform court_gallery_join(v_case);
  update profiles set last_seen = now() where id in (select id from profiles where username like 'CT\_%');

  -- statements
  perform pg_temp.assert(pg_temp.call('g1', format('select court_post(%s, %L)', v_case, 'I can talk too')) = 'not_party', 'the gallery cannot speak');
  perform pg_temp.assert(pg_temp.call('g3', format('select court_post(%s, %L)', v_case, 'x')) = 'not_party', 'a stranger cannot speak');
  perform pg_temp.login(pg_temp.u('p')); perform court_post(v_case, 'He took my money at Oba Market.');
  perform pg_temp.advance(5);
  perform pg_temp.login(pg_temp.u('d')); perform court_post(v_case, 'I was not there, my lord.');
  perform pg_temp.advance(5);
  perform pg_temp.login(pg_temp.u('l1')); perform court_post(v_case, 'The record shows the theft.');
  perform pg_temp.assert((select as_lawyer from court_statements where case_id = v_case and author_id = pg_temp.u('l1')), 'lawyer statements are flagged');
  perform pg_temp.advance(5);
  perform pg_temp.login(pg_temp.u('j1')); perform court_post(v_case, 'Order in court.');
  perform pg_temp.assert((select kind from court_statements where case_id = v_case and author_id = pg_temp.u('j1')) = 'note' and (select side from court_statements where case_id = v_case and author_id = pg_temp.u('j1')) = 'bench', 'judge remarks are bench notes');
  perform pg_temp.login(pg_temp.u('g1')); r := court_after(v_case, 0);
  perform pg_temp.assert(jsonb_array_length(r -> 'statements') = 4 and (r ->> 'gallery')::int = 2, 'the gallery sees every statement');
  perform pg_temp.assert(jsonb_array_length(court_after(v_case, (r -> 'statements' -> 2 ->> 'id')::bigint) -> 'statements') = 1, 'polling after an id returns only newer statements');
  perform pg_temp.assert(jsonb_array_length(court_case(v_case) -> 'statements') = 4 and (court_case(v_case) -> 'me' ->> 'role') = 'gallery', 'case page for a watcher');

  -- the judge rules
  perform pg_temp.assert(pg_temp.call('g1', format('select court_rule(%s, %L, %L)', v_case, 'guilty', '')) = 'not_judge', 'only the judge rules');
  perform pg_temp.assert(pg_temp.call('p', format('select court_rule(%s, %L, %L)', v_case, 'guilty', '')) = 'not_judge', 'a party cannot rule');
  raise notice 'case % ready for the ruling (hearing min: already %)', v_case, (select status from court_cases where id = v_case);
  perform set_config('ct.case_a', v_case::text, true);
  perform set_config('ct.p0', v_p0::text, true);
end $$;

-- ---------- 6 (cont). the judge rules: guilty, restitution cash then bank, fine, lawyers, cred, alerts ----------
do $$
declare
  v_case bigint := current_setting('ct.case_a')::bigint; r jsonb; v_pt bigint; v_dc bigint; v_db bigint; v_l1 bigint; v_l2 bigint; v_cred int; v_losses int; v_cnt int; c court_cases;
begin
  v_pt := pg_temp.total('p'); v_dc := pg_temp.cash('d'); v_db := pg_temp.bank('d'); v_l1 := pg_temp.total('l1'); v_l2 := pg_temp.total('l2');
  select street_cred into v_cred from profiles where id = pg_temp.u('d');
  select losses into v_losses from court_lawyers where user_id = pg_temp.u('l2');
  perform pg_temp.assert(v_dc = 30000 and v_db = 95000, 'defendant has cash 30,000 and bank 95,000 (5,000 escrow came from the bank)');
  perform pg_temp.login(pg_temp.u('j1'));
  r := court_rule(v_case, 'guilty', 'The record is clear.');
  select * into c from court_cases where id = v_case;
  perform pg_temp.assert(c.status = 'ruled' and c.verdict = 'guilty' and c.verdict_by = 'judge', 'ruled guilty by the judge');
  -- restitution: CASH first, then bank
  perform pg_temp.assert(pg_temp.cash('d') = 0, 'cash taken first');
  perform pg_temp.assert((select delta from ledger where user_id = pg_temp.u('d') and reason = 'court_restitution_out' and account = 'cash') = -30000
                         and (select delta from ledger where user_id = pg_temp.u('d') and reason = 'court_restitution_out' and account = 'bank') = -50000, 'restitution: 30,000 cash then 50,000 bank');
  perform pg_temp.assert(c.restitution_paid = 80000 and c.restitution_debt = 0, 'restitution paid in full');
  perform pg_temp.assert(pg_temp.total('p') - v_pt = 80000 + 1500, 'plaintiff gets 80,000 and the 1,500 filing fee back');
  perform pg_temp.assert((select sum(delta) from ledger where user_id = pg_temp.u('p') and reason = 'court_restitution_in' and meta ->> 'case' = c.case_no) = 80000
                         and (select sum(delta) from ledger where user_id = pg_temp.u('p') and reason = 'court_fee_refund' and meta ->> 'case' = c.case_no) = 1500, 'ledger reasons');
  -- the fine: 20% of 80,000 = 16,000, a sink (taken, credited to nobody)
  perform pg_temp.assert(c.fine = 16000 and c.fine_paid = 16000 and pg_temp.reasons('d', 'court_fine') = -16000, 'fine 16,000');
  perform pg_temp.assert(not exists (select 1 from ledger where reason = 'court_fine' and delta > 0), 'a fine is never credited to anyone');
  perform pg_temp.assert(pg_temp.bank('d') = v_db - 50000 - 16000, 'defendant bank after');
  -- not earnings
  perform pg_temp.assert('court_restitution_in' <> all (bl_earn_reasons()) and 'lawyer_fee_in' <> all (bl_earn_reasons()) and 'court_fee_refund' <> all (bl_earn_reasons()), 'restitution is not counted as earnings');
  -- street cred hit, no jail for a first verdict
  perform pg_temp.assert((select street_cred from profiles where id = pg_temp.u('d')) = v_cred - 5 and c.cred_hit = 5, 'street cred -5');
  perform pg_temp.assert(not exists (select 1 from jail_cases where user_id = pg_temp.u('d')) and c.jail_seconds = 0, 'first guilty verdict: no jail');
  -- lawyers: paid on the verdict minus the court cut (5%, a sink); records
  perform pg_temp.assert(pg_temp.total('l1') - v_l1 = 9500 and pg_temp.total('l2') - v_l2 = 4750, 'lawyer fees paid minus the 5% cut');
  perform pg_temp.assert((select cut from court_hires where case_id = v_case and side = 'plaintiff' and status = 'paid') = 500, 'hire marked paid with the cut recorded');
  perform pg_temp.assert((select wins from court_lawyers where user_id = pg_temp.u('l1')) = 1 and (select losses from court_lawyers where user_id = pg_temp.u('l2')) = v_losses + 1, 'plaintiff lawyer wins, defendant lawyer loses');
  -- alerts for both parties, both lawyers
  select count(*) into v_cnt from events where kind = 'court_verdict' and user_id in (pg_temp.u('p'), pg_temp.u('d'), pg_temp.u('l1'), pg_temp.u('l2'));
  perform pg_temp.assert(v_cnt >= 4, 'both parties and both lawyers get an alert');
  -- the ruling is part of the record; the case is closed to more statements and a second ruling
  perform pg_temp.assert(exists (select 1 from court_statements where case_id = v_case and kind = 'ruling' and body like 'GUILTY.%'), 'the ruling is kept in the case record');
  perform pg_temp.assert(pg_temp.call('p', format('select court_post(%s, %L)', v_case, 'one more')) = 'ok', 'post on a ruled case is a soft no');
  perform pg_temp.assert(not exists (select 1 from court_statements where case_id = v_case and body = 'one more'), 'no statement is added after the ruling');
  perform pg_temp.login(pg_temp.u('j1'));
  perform pg_temp.assert((court_rule(v_case, 'not_guilty', '')) ->> 'closed' = 'true', 'cannot rule twice');
  -- anyone can read a ruled case (open court)
  perform pg_temp.login(pg_temp.u('g3'));
  r := court_case(v_case);
  perform pg_temp.assert(jsonb_array_length(r -> 'statements') >= 5 and r ->> 'verdict' = 'guilty' and (r ->> 'fine')::bigint = 16000, 'a ruled case is public record');
  raise notice 'ok 5-6: hiring, judge, hearing, gallery, guilty verdict';
end $$;

-- ---------- 7. not guilty: the plaintiff loses the filing fee. 13b. override up (jail on the 2nd guilty verdict) and back ----------
do $$
declare
  v_ev bigint; r jsonb; v_case bigint; v_pt bigint; v_dt bigint; v_cred int; c court_cases; v_pbank bigint;
begin
  perform pg_temp.money('p', 50000, 1000000); perform pg_temp.money('d', 40000, 60000);
  v_ev := pg_temp.theft('d', 'p', 40000);
  r := pg_temp.file('p', 'pickpocket', v_ev::text);
  v_case := pg_temp.case_id(r);
  v_pt := pg_temp.total('p'); v_dt := pg_temp.total('d');
  perform pg_temp.advance(33 * 60);
  perform pg_temp.login(pg_temp.u('j1'));
  perform court_rule(v_case, 'not_guilty', 'The defendant gave a good account.');
  select * into c from court_cases where id = v_case;
  perform pg_temp.assert(c.verdict = 'not_guilty' and pg_temp.total('p') = v_pt and pg_temp.total('d') = v_dt, 'not guilty: nothing moves');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = pg_temp.u('p') and reason = 'court_fee_refund' and meta ->> 'case' = c.case_no), 'not guilty: the filing fee is NOT returned');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('p') and kind = 'court_verdict' and body like '%filing fee is not returned%'), 'the plaintiff is told');
  -- the admin overrides: guilty. Audited. The second guilty verdict in 30 days sends d to jail.
  perform pg_temp.assert(pg_temp.call('p', format('select admin_court_override(%s, %L, %L)', v_case, 'guilty', 'x')) = 'not_admin', 'a player cannot override');
  perform pg_temp.assert(pg_temp.call('adm', format('select admin_court_override(%s, %L, %L)', v_case, 'guilty', '')) = 'reason', 'an override needs a reason');
  perform pg_temp.assert(pg_temp.call('adm', format('select admin_court_override(%s, %L, %L)', v_case, 'not_guilty', 'same')) = 'same', 'same verdict refused');
  select street_cred into v_cred from profiles where id = pg_temp.u('d');
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_court_override(v_case, 'guilty', 'New evidence from the Police.');
  select * into c from court_cases where id = v_case;
  perform pg_temp.assert(c.verdict = 'guilty' and c.verdict_by = 'admin' and c.overridden, 'overridden to guilty by an admin');
  perform pg_temp.assert(pg_temp.total('p') = v_pt + 40000 + 1500 and c.restitution_paid = 40000 and c.fine = 8000, 'money moved as for a normal ruling (restitution + the fee back; fine 8,000)');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'court_override' and (data ->> 'case')::bigint = v_case and data ->> 'old' = 'not_guilty' and data ->> 'new' = 'guilty' and data ->> 'reason' like 'New evidence%'), 'override audited');
  -- repeat offender: a SECOND guilty verdict within 30 days = jail through the Police case system
  perform pg_temp.assert(c.jail_seconds = 60, 'second guilty verdict: 60 seconds of jail');
  perform pg_temp.assert(exists (select 1 from jail_cases where user_id = pg_temp.u('d') and status = 'open' and reason like 'Jailed by the court%' and jail_seconds = 60 and attempt_id is null), 'a jail case opened (the existing popup, bail, escape)');
  perform pg_temp.assert((select jailed_until from profiles where id = pg_temp.u('d')) > bl_now() and (select wanted from profiles where id = pg_temp.u('d')) >= 1, 'the defendant is in the cell');
  perform pg_temp.assert(pg_temp.reasons('d', 'court_fine') = -16000 - 8000, 'fines are ledgered');
  -- override back to not guilty: the money goes back, cred restored
  v_pbank := pg_temp.total('p');
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_court_override(v_case, 'not_guilty', 'Overturned on review.');
  select * into c from court_cases where id = v_case;
  perform pg_temp.assert(c.verdict = 'not_guilty' and c.overridden and c.restitution_paid = 0 and c.fine = 0, 'back to not guilty');
  perform pg_temp.assert(pg_temp.total('p') = v_pbank - 40000 - 1500, 'the plaintiff paid back the restitution and the fee');
  perform pg_temp.assert(pg_temp.reasons('d', 'court_refund') >= 40000 + 8000, 'the defendant got restitution and fine back');
  perform pg_temp.assert((select street_cred from profiles where id = pg_temp.u('d')) = v_cred, 'street cred restored');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'court_override' and (data ->> 'case')::bigint = v_case) = 2, 'both overrides audited');
  perform pg_temp.assert(pg_temp.cash('p') >= 0 and pg_temp.bank('p') >= 0 and pg_temp.cash('d') >= 0 and pg_temp.bank('d') >= 0, 'nobody below zero');
  -- free d again (jail) for the next groups
  update jail_cases set status = 'released', closed_at = now() where user_id = pg_temp.u('d');
  update profiles set jailed_until = null, jail_reason = null where id = pg_temp.u('d');
  raise notice 'ok 7 + 13b: not guilty, override up and down, jail for the 2nd guilty verdict';
end $$;

-- ---------- 8. automatic ruling, court debt, collection from income, not earnings ----------
do $$
declare
  v_ev bigint; r jsonb; v_case bigint; c court_cases; v_pb bigint;
begin
  perform pg_temp.money('p', 0, 1000000); perform pg_temp.money('x', 5000, 0);
  v_ev := pg_temp.theft('x', 'p', 120000);
  r := pg_temp.file('p', 'pickpocket', v_ev::text);
  v_case := pg_temp.case_id(r);
  perform pg_temp.assert(r -> 'case' ->> 'case_no' like 'BC/%', 'a 120,000 claim goes to the High Court');
  -- nobody rules; the window passes (hearing +30, ruling window +60)
  perform pg_temp.advance(89 * 60);
  perform pg_temp.login(pg_temp.u('p'));
  perform court_status();
  perform pg_temp.assert((select status from court_cases where id = v_case) = 'scheduled', 'still waiting just inside the window');
  perform pg_temp.advance(2 * 60);
  v_pb := pg_temp.total('p');
  perform court_status();                                      -- any player opening the app settles it (lazy clock, no cron)
  select * into c from court_cases where id = v_case;
  perform pg_temp.assert(c.status = 'ruled' and c.verdict = 'guilty' and c.verdict_by = 'auto', 'AUTOMATIC ruling after the window follows the recorded evidence: guilty');
  perform pg_temp.assert(exists (select 1 from court_statements where case_id = v_case and kind = 'ruling' and body like '%Automatic ruling%'), 'the record says it was automatic');
  -- restitution: cash 5,000 then nothing in the bank; the rest is court debt (never below zero)
  perform pg_temp.assert(c.restitution_paid = 5000 and c.restitution_debt = 115000, 'paid 5,000 (all the cash), 115,000 becomes court debt');
  perform pg_temp.assert(pg_temp.cash('x') = 0 and pg_temp.bank('x') = 0, 'never below zero');
  perform pg_temp.assert(pg_temp.total('p') - v_pb = 5000 + 5000, 'plaintiff: 5,000 restitution + the 5,000 filing fee back');
  perform pg_temp.assert(c.fine = 24000 and c.fine_paid = 0, 'fine 24,000 (20%), nothing left to pay it from');
  perform pg_temp.assert((select count(*) from court_debts where debtor_id = pg_temp.u('x') and owed > 0) = 2 and (select sum(owed) from court_debts where debtor_id = pg_temp.u('x')) = 139000, 'court debt 115,000 + fine 24,000');
  perform pg_temp.login(pg_temp.u('x'));
  perform pg_temp.assert((court_status() -> 'debts' ->> 'owed')::bigint = 139000 and (court_status() -> 'debts' ->> 'collect_pct')::numeric = 30, 'the debtor sees the debt and the collection rate');
  -- only EARNINGS are garnished; a transfer is not
  perform bl_add_money(pg_temp.u('x'), 'bank', 50000, 'transfer_in', '{}'::jsonb);
  perform pg_temp.assert(pg_temp.reasons('x', 'court_debt') = 0 and pg_temp.bank('x') = 50000, 'a transfer is not income: nothing taken');
  perform pg_temp.money('x', 0, 0);
  perform bl_add_money(pg_temp.u('x'), 'bank', 100000, 'salary', '{}'::jsonb);
  perform pg_temp.assert(pg_temp.reasons('x', 'court_debt') = -30000 and pg_temp.bank('x') = 70000, '30% of a salary goes to court debt through the ledger');
  perform pg_temp.assert((select owed from court_debts where debtor_id = pg_temp.u('x') and kind = 'restitution') = 85000 and (select held from court_debts where debtor_id = pg_temp.u('x') and kind = 'restitution') = 30000, 'restitution debt paid down, money held for the creditor');
  -- the creditor receives it on their next call (two player rows are never locked together); it is not earnings
  v_pb := pg_temp.total('p');
  perform pg_temp.login(pg_temp.u('p'));
  perform court_status();
  perform pg_temp.assert(pg_temp.total('p') - v_pb = 30000 and (select coalesce(sum(held), 0) from court_debts where creditor_id = pg_temp.u('p')) = 0, 'the plaintiff is paid from the debtor''s income');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('p') and kind = 'court_debt_paid'), 'alert on payment');
  update game_config set value = to_jsonb('salary,hustle,court_restitution_in,court_debt'::text) where key = 'leaderboard.earn_reasons';
  perform pg_temp.assert('court_restitution_in' <> all (bl_earn_reasons()) and 'court_debt' <> all (bl_earn_reasons()), 'even if Admin lists them, court money is never earned');
  update game_config set value = to_jsonb('salary,hustle,harvest,farm_harvest,invest_income'::text) where key = 'leaderboard.earn_reasons';
  -- clear it all (100% collection): restitution first, then the fine (a sink)
  perform pg_temp.cfg('court.debt_collect_pct', '100');
  perform bl_add_money(pg_temp.u('x'), 'cash', 500000, 'salary', '{}'::jsonb);
  perform pg_temp.assert(not exists (select 1 from court_debts where debtor_id = pg_temp.u('x') and owed > 0), 'all debt collected');
  perform pg_temp.assert(pg_temp.cash('x') = 500000 - 85000 - 24000, 'the rest of the salary is theirs');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('x') and kind = 'court_debt_cleared'), 'cleared alert');
  perform pg_temp.cfg('court.debt_collect_pct', '30');
  perform pg_temp.assert(not exists (select 1 from ledger where reason = 'court_debt' and delta > 0), 'debt collection credits nobody directly');
  raise notice 'ok 8: automatic ruling, debt, collection, not earnings';
end $$;

create or replace function pg_temp.court_list(p_name text) returns jsonb
language plpgsql as $$
begin
  perform pg_temp.login(pg_temp.u(p_name));
  return court_lawyers_list('', 'all', 50);
end $$;

-- ---------- 9. jail for repeat offenders; debt switched off forgives the rest ----------
do $$
declare
  v_ev bigint; r jsonb; v_case bigint; c court_cases; v_n int; v_prior int;
begin
  perform pg_temp.money('p', 0, 3000000); perform pg_temp.money('x', 0, 0);
  select count(*) into v_prior from court_cases where defendant_id = pg_temp.u('x') and verdict = 'guilty';
  perform pg_temp.assert(v_prior = 1, 'x has one guilty verdict from group 8');
  perform pg_temp.cfg('court.debt_enabled', 'false');
  -- 2nd guilty verdict inside 30 days: jail, base 60 s
  v_ev := pg_temp.theft('x', 'p', 30000);
  r := pg_temp.file('p', 'pickpocket', v_ev::text); v_case := pg_temp.case_id(r);
  perform pg_temp.advance(91 * 60);
  perform pg_temp.login(pg_temp.u('p')); perform court_status();
  select * into c from court_cases where id = v_case;
  perform pg_temp.assert(c.verdict = 'guilty' and c.jail_seconds = 60, '2nd guilty verdict: 60 s of jail');
  perform pg_temp.assert(c.restitution_paid = 0 and c.restitution_debt = 0 and c.fine_paid = 0, 'nothing to pay from, and with court debt off the rest is forgiven');
  perform pg_temp.assert(not exists (select 1 from court_debts where case_id = v_case), 'no debt row when court debt is off');
  perform pg_temp.assert((select count(*) from jail_cases where user_id = pg_temp.u('x') and reason like 'Jailed by the court%') = 1, 'one court jail case for x');
  -- 3rd verdict: longer jail (120 s)
  v_ev := pg_temp.theft('x', 'p', 25000);
  r := pg_temp.file('p', 'pickpocket', v_ev::text); v_case := pg_temp.case_id(r);
  perform pg_temp.advance(91 * 60);
  perform pg_temp.login(pg_temp.u('p')); perform court_status();
  select * into c from court_cases where id = v_case;
  perform pg_temp.assert(c.verdict = 'guilty' and c.jail_seconds = 120, '3rd guilty verdict: 120 s (longer for repeat offenders)');
  perform pg_temp.assert((select jail_seconds from jail_cases where user_id = pg_temp.u('x') order by id desc limit 1) = 120, 'the Police jail case carries the longer time');
  -- an old verdict does not count: the repeat window
  perform pg_temp.cfg('court.repeat_days', '1');
  perform pg_temp.advance(3 * 86400);
  update profiles set last_seen = now() where id in (select id from profiles where username like 'CT\_%');
  v_ev := pg_temp.theft('x', 'p', 20000);
  r := pg_temp.file('p', 'pickpocket', v_ev::text); v_case := pg_temp.case_id(r);
  perform pg_temp.advance(91 * 60);
  perform pg_temp.login(pg_temp.u('p')); perform court_status();
  select * into c from court_cases where id = v_case;
  perform pg_temp.assert(c.verdict = 'guilty' and c.jail_seconds = 0, 'verdicts older than the repeat window do not count: no jail');
  perform pg_temp.cfg('court.repeat_days', '30');
  perform pg_temp.cfg('court.debt_enabled', 'true');
  update jail_cases set status = 'released', closed_at = now() where user_id = pg_temp.u('x');
  update profiles set jailed_until = null, jail_reason = null where id = pg_temp.u('x');
  raise notice 'ok 9: jail for repeat offenders, debt off';
end $$;

-- ---------- 10. statements: cleaning, masking, caps ----------
do $$
declare
  v_ev bigint; r jsonb; v_case bigint; v_body text;
begin
  perform pg_temp.money('p', 0, 3000000); perform pg_temp.money('d', 100000, 100000);
  perform pg_temp.cfg('court.statements_per_side', '3');
  v_ev := pg_temp.theft('d', 'p', 20000);
  r := pg_temp.file('p', 'pickpocket', v_ev::text); v_case := pg_temp.case_id(r);
  perform set_config('ct.case_s', v_case::text, true);
  perform pg_temp.advance(31 * 60);
  update profiles set last_seen = now() where id in (select id from profiles where username like 'CT\_%');
  perform pg_temp.login(pg_temp.u('p'));
  perform court_post(v_case, E'  hello\n\tworld   fu' || 'ck  ');
  select body into v_body from court_statements where case_id = v_case and author_id = pg_temp.u('p') order by id desc limit 1;
  perform pg_temp.assert(v_body = 'hello world ****', 'cleaned (spaces, newlines, tabs) and masked like chat: ' || v_body);
  perform pg_temp.advance(4);
  perform court_post(v_case, E'a​b\u0001c');
  select body into v_body from court_statements where case_id = v_case and author_id = pg_temp.u('p') order by id desc limit 1;
  perform pg_temp.assert(v_body = 'abc', 'zero-width and control characters removed');
  perform pg_temp.assert(pg_temp.call('p', format('select court_post(%s, %L)', v_case, 'too soon')) = 'slow', 'a second statement within the gap is refused');
  perform pg_temp.advance(4);
  perform pg_temp.assert(pg_temp.call('p', format('select court_post(%s, %L)', v_case, repeat('a', 241))) = 'too_long', 'over the length limit refused');
  perform pg_temp.assert(pg_temp.call('p', format('select court_post(%s, %L)', v_case, E'  \n ')) = 'empty', 'an empty statement refused');
  perform pg_temp.assert(pg_temp.call('p', format('select court_post(%s, %L)', v_case, repeat('a', 240))) = 'ok', 'exactly the limit is fine');
  perform pg_temp.advance(4);
  perform pg_temp.assert(pg_temp.call('p', format('select court_post(%s, %L)', v_case, 'fourth')) = 'limit', 'each side has a statement cap');
  perform pg_temp.assert(pg_temp.call('d', format('select court_post(%s, %L)', v_case, 'my turn')) = 'ok', 'the other side has its own allowance');
  update profiles set chat_muted_until = bl_now() + interval '1 day' where id = pg_temp.u('d');
  perform pg_temp.advance(4);
  perform pg_temp.assert(pg_temp.call('d', format('select court_post(%s, %L)', v_case, 'muted?')) = 'muted', 'a muted player cannot post');
  update profiles set chat_muted_until = null where id = pg_temp.u('d');
  perform pg_temp.cfg('court.statements_per_side', '8');
  raise notice 'ok 10: statements cleaned, masked and capped';
end $$;

-- ---------- 14. realtime RLS on statements (people in the case or the gallery only) ----------
do $$
declare v_case bigint := current_setting('ct.case_s')::bigint;
begin
  perform pg_temp.login(pg_temp.u('g1')); perform court_gallery_join(v_case);
end $$;
set local role authenticated;
do $$
declare v_case bigint := current_setting('ct.case_s')::bigint; v_n int;
begin
  perform pg_temp.login(pg_temp.u('p'));
  select count(*) into v_n from court_statements where case_id = v_case;
  perform pg_temp.assert(v_n >= 4, 'a party reads the statements directly (realtime): ' || v_n);
  perform pg_temp.login(pg_temp.u('g1'));
  select count(*) into v_n from court_statements where case_id = v_case;
  perform pg_temp.assert(v_n >= 4, 'a seated watcher reads them');
  perform pg_temp.login(pg_temp.u('g3'));
  select count(*) into v_n from court_statements where case_id = v_case;
  perform pg_temp.assert(v_n = 0, 'a stranger reads nothing');
  perform pg_temp.assert(pg_temp.hint_of('select count(*) from court_cases') ~* 'permission denied|privileges', 'cases are not readable directly');
  perform pg_temp.assert(pg_temp.hint_of(format('insert into court_statements (case_id, side, body) values (%s, %L, %L)', v_case, 'plaintiff', 'forged')) ~* 'permission denied|privileges', 'no direct writes');
end $$;
reset role;

-- ---------- 11. anti-abuse ----------
do $$
declare
  v_ev bigint; v_ev2 bigint; r jsonb; v_case bigint; v_case2 bigint; v_h bigint;
begin
  perform pg_temp.money('p', 0, 3000000); perform pg_temp.money('d', 100000, 100000); perform pg_temp.money('g1', 0, 500000); perform pg_temp.money('g2', 0, 500000); perform pg_temp.money('g3', 0, 500000); perform pg_temp.money('j1', 0, 100000);
  perform pg_temp.advance(3 * 3600);
  update profiles set last_seen = now() where id in (select id from profiles where username like 'CT\_%');
  -- cooldown between filings
  perform pg_temp.cfg('court.file_cooldown_minutes', '5');
  v_ev := pg_temp.theft('d', 'g1', 15000); v_ev2 := pg_temp.theft('d', 'g1', 16000);
  perform pg_temp.file('g1', 'pickpocket', v_ev::text);
  perform pg_temp.assert(pg_temp.call('g1', format('select court_file(%L, %L)', 'pickpocket', v_ev2::text)) = 'blocked', 'filing cooldown');
  perform pg_temp.advance(6 * 60);
  perform pg_temp.assert(pg_temp.call('g1', format('select court_file(%L, %L)', 'pickpocket', v_ev2::text)) = 'ok', 'after the cooldown the filing works');
  perform pg_temp.cfg('court.file_cooldown_minutes', '0');
  -- open case cap
  perform pg_temp.cfg('court.max_open_cases', '1');
  v_ev := pg_temp.theft('d', 'g2', 15000); v_ev2 := pg_temp.theft('d', 'g2', 16000);
  perform pg_temp.file('g2', 'pickpocket', v_ev::text);
  perform pg_temp.assert(pg_temp.call('g2', format('select court_file(%L, %L)', 'pickpocket', v_ev2::text)) = 'blocked', 'open case cap');
  perform pg_temp.cfg('court.max_open_cases', '50');
  -- daily cap
  perform pg_temp.cfg('court.max_per_day', '1');
  v_ev := pg_temp.theft('d', 'g3', 15000); v_ev2 := pg_temp.theft('d', 'g3', 16000);
  perform pg_temp.file('g3', 'pickpocket', v_ev::text);
  perform pg_temp.assert(pg_temp.call('g3', format('select court_file(%L, %L)', 'pickpocket', v_ev2::text)) = 'blocked', 'daily filing cap');
  perform pg_temp.cfg('court.max_per_day', '100');
  -- a lawyer who is busy; hire attempts; hiring after the hearing starts; a pending request expires at the hearing
  perform pg_temp.cfg('court.lawyer_max_open', '1');
  select id into v_case from court_cases where plaintiff_id = pg_temp.u('g1') order by id limit 1;
  select id into v_case2 from court_cases where plaintiff_id = pg_temp.u('g2') order by id limit 1;
  perform pg_temp.login(pg_temp.u('g1')); perform court_hire(v_case, pg_temp.u('l3'));
  perform pg_temp.assert(pg_temp.call('g2', format('select court_hire(%s, %L)', v_case2, pg_temp.u('l3'))) = 'lawyer_busy', 'a lawyer cannot take more than the open-case limit');
  perform pg_temp.cfg('court.lawyer_max_open', '5');
  perform pg_temp.cfg('court.hire_attempts', '1');
  perform pg_temp.login(pg_temp.u('g2')); perform court_hire(v_case2, pg_temp.u('l2'));
  select id into v_h from court_hires where case_id = v_case2 and status = 'pending';
  perform court_hire_cancel(v_h);
  perform pg_temp.assert(pg_temp.call('g2', format('select court_hire(%s, %L)', v_case2, pg_temp.u('l1'))) = 'hire_limit', 'hire attempts per side are limited');
  perform pg_temp.cfg('court.hire_attempts', '3');
  -- the pending request to l3 expires when the hearing starts, and the fee comes back
  perform pg_temp.advance(31 * 60);
  perform pg_temp.login(pg_temp.u('g1'));
  perform court_status();
  perform pg_temp.assert((select status from court_hires where case_id = v_case and lawyer_id = pg_temp.u('l3')) = 'expired', 'an unanswered request expires at the hearing');
  perform pg_temp.assert(pg_temp.reasons('g1', 'lawyer_fee_refund') = 7000, 'and the escrow comes back');
  perform pg_temp.assert(pg_temp.call('g2', format('select court_hire(%s, %L)', v_case2, pg_temp.u('l2'))) = 'too_late', 'no hiring once the hearing has started');
  perform pg_temp.login(pg_temp.u('l3'));
  perform pg_temp.assert(pg_temp.call('l3', format('select court_hire_respond(%s, true)', (select id from court_hires where case_id = v_case and lawyer_id = pg_temp.u('l3')))) = 'closed', 'an expired request cannot be accepted');
  -- a judge cannot rule on a case they are a party to: j1 sues d
  perform pg_temp.cfg('court.type_pickpocket_enabled', 'true');
  v_ev := pg_temp.theft('d', 'j1', 50000);
  r := pg_temp.file('j1', 'pickpocket', v_ev::text); v_case := pg_temp.case_id(r);
  perform pg_temp.assert((select judge_id from court_cases where id = v_case) is null, 'the only judge is a party, so nobody is assigned');
  perform pg_temp.assert(pg_temp.call('j1', format('select court_rule(%s, %L, %L)', v_case, 'guilty', '')) = 'not_judge', 'a judge cannot rule on their own case');
  perform pg_temp.assert(pg_temp.call('j1', format('select court_judge_take(%s)', v_case)) = 'judge_party', 'a judge cannot take their own case');
  perform pg_temp.assert(pg_temp.call('g1', format('select court_judge_take(%s)', v_case)) = 'not_judge', 'only judges can take a case');
  perform pg_temp.assert(pg_temp.call('d', format('select court_hire(%s, %L)', v_case, pg_temp.u('j1'))) in ('lawyer_unavailable', 'lawyer_party'), 'a party judge cannot be hired');
  -- a second judge is appointed: they are assigned when the hearing starts and can rule
  perform pg_temp.login(pg_temp.u('adm')); perform admin_court_appoint_judge('CT_j2', 'second judge');
  perform pg_temp.advance(31 * 60);
  update profiles set last_seen = now() where id in (select id from profiles where username like 'CT\_%');
  perform pg_temp.login(pg_temp.u('d')); perform court_status();
  perform pg_temp.assert((select judge_id from court_cases where id = v_case) = pg_temp.u('j2'), 'the new judge is assigned at the hearing');
  perform pg_temp.assert(pg_temp.call('j1', format('select court_rule(%s, %L, %L)', v_case, 'guilty', '')) = 'not_judge', 'still not j1');
  perform pg_temp.advance(3 * 60);
  perform pg_temp.assert(pg_temp.call('j2', format('select court_rule(%s, %L, %L)', v_case, 'guilty', 'Fair.')) = 'ok', 'j2 rules');
  perform set_config('ct.case_j', v_case::text, true);
  raise notice 'ok 11: anti-abuse';
end $$;

-- ---------- 12. other case types: rent owed, unfair eviction, overcharge ----------
do $$
declare
  v_prop uuid; v_prop2 uuid; v_ev bigint; v_ev2 bigint; v_ev3 bigint; r jsonb; v_case bigint; c court_cases; v_trade bigint; v_trade2 bigint;
begin
  perform pg_temp.money('p', 0, 3000000); perform pg_temp.money('d', 500000, 500000);
  perform pg_temp.advance(3 * 3600);
  update profiles set last_seen = now() where id in (select id from profiles where username like 'CT\_%');
  -- rent owed: p is the landlord, d the tenant who was moved out owing 60,000 with 10,000 of caution kept
  insert into properties (owner_id, area, type_id, source, basis) values (pg_temp.u('p'), 'gra', 'self_contain', 'bought', 1000000) returning id into v_prop;
  insert into property_events (property_id, user_id, kind, detail, created_at)
    values (v_prop, pg_temp.u('d'), 'tenancy_ended', '{"why":"owed","tenant":"CT_d","owed":60000,"caution_kept":10000}', bl_now() - interval '2 hours') returning id into v_ev;
  insert into property_events (property_id, user_id, kind, detail, created_at)
    values (v_prop, pg_temp.u('d'), 'tenancy_ended', '{"why":"owed","tenant":"CT_d","owed":30000,"caution_kept":30000}', bl_now() - interval '2 hours') returning id into v_ev2;
  perform pg_temp.assert(pg_temp.call('g1', format('select court_file(%L, %L)', 'rent_owed', v_ev::text)) = 'no_record', 'only the landlord of that property can sue');
  perform pg_temp.assert(pg_temp.call('d', format('select court_file(%L, %L)', 'rent_owed', v_ev::text)) = 'no_record', 'the tenant cannot file it');
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'rent_owed', v_ev2::text)) = 'no_record', 'nothing is owed after the caution');
  r := pg_temp.file('p', 'rent_owed', v_ev::text); v_case := pg_temp.case_id(r);
  perform pg_temp.assert((select claim from court_cases where id = v_case) = 50000 and (select title from court_cases where id = v_case) like 'Rent owed on%', 'claim = owed minus the caution kept, from the property record');
  perform pg_temp.advance(91 * 60);
  perform pg_temp.login(pg_temp.u('p')); perform court_status();
  select * into c from court_cases where id = v_case;
  perform pg_temp.assert(c.verdict = 'guilty' and c.verdict_by = 'auto' and c.restitution_paid = 50000, 'rent owed: automatic ruling from the record, paid back');
  -- unfair eviction: p is the tenant; d the landlord gave notice 2 days after move-in
  insert into properties (owner_id, area, type_id, source, basis) values (pg_temp.u('d'), 'gra', 'self_contain', 'bought', 1000000) returning id into v_prop2;
  insert into property_events (property_id, user_id, kind, detail, created_at) values
    (v_prop2, pg_temp.u('p'), 'tenant_moved_in', '{"tenant":"CT_p","rent":20000,"caution":0}', bl_now() - interval '2 days'),
    (v_prop2, pg_temp.u('d'), 'notice_given', '{"tenant":"CT_p"}', bl_now() - interval '30 hours');
  insert into property_events (property_id, user_id, kind, detail, created_at)
    values (v_prop2, pg_temp.u('p'), 'tenancy_ended', '{"why":"notice","tenant":"CT_p","owed":0,"caution_kept":0}', bl_now() - interval '1 hour') returning id into v_ev;
  insert into property_events (property_id, user_id, kind, detail, created_at)
    values (v_prop2, pg_temp.u('p'), 'tenancy_ended', '{"why":"notice","tenant":"CT_p","owed":5000,"caution_kept":0}', bl_now() - interval '1 hour') returning id into v_ev2;
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'eviction', v_ev2::text)) = 'no_record', 'a tenant who owed rent cannot claim an unfair eviction');
  perform pg_temp.assert(pg_temp.call('d', format('select court_file(%L, %L)', 'eviction', v_ev::text)) = 'no_record', 'the landlord cannot file it');
  r := pg_temp.file('p', 'eviction', v_ev::text); v_case := pg_temp.case_id(r);
  perform pg_temp.assert((select claim from court_cases where id = v_case) = 20000 and (select defendant_id from court_cases where id = v_case) = pg_temp.u('d'), 'compensation = one week of the rent at move-in; the landlord is the one who gave notice');
  perform pg_temp.advance(91 * 60);
  perform pg_temp.login(pg_temp.u('p')); perform court_status();
  perform pg_temp.assert((select verdict from court_cases where id = v_case) = 'guilty', 'unfair eviction ruled from the record');
  -- a fair stay is not an unfair eviction
  update property_events set created_at = bl_now() - interval '20 days' where property_id = v_prop2 and kind = 'tenant_moved_in';
  insert into property_events (property_id, user_id, kind, detail, created_at)
    values (v_prop2, pg_temp.u('p'), 'tenancy_ended', '{"why":"notice","tenant":"CT_p","owed":0,"caution_kept":0}', bl_now() - interval '1 hour') returning id into v_ev3;
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'eviction', v_ev3::text)) = 'no_record', 'a long stay: not unfair');
  -- overcharge on the Market: only a trade the game flagged far_high
  insert into market_trades (kind, ref_id, title, seller_id, buyer_id, price, fee, value, flags, created_at)
    values ('car', 'camry', 'Old Camry', pg_temp.u('d'), pg_temp.u('p'), 900000, 0, 300000, '{far_high}', bl_now()) returning id into v_trade;
  insert into market_trades (kind, ref_id, title, seller_id, buyer_id, price, fee, value, flags, created_at)
    values ('car', 'rio', 'Kia Rio', pg_temp.u('d'), pg_temp.u('p'), 1000000, 0, 900000, '{}', bl_now()) returning id into v_trade2;
  perform pg_temp.assert(pg_temp.call('p', format('select court_file(%L, %L)', 'overcharge', v_trade2::text)) = 'no_record', 'an unflagged trade cannot be sued');
  perform pg_temp.assert(pg_temp.call('d', format('select court_file(%L, %L)', 'overcharge', v_trade::text)) = 'no_record', 'the seller cannot sue');
  r := pg_temp.file('p', 'overcharge', v_trade::text); v_case := pg_temp.case_id(r);
  perform pg_temp.assert((select claim from court_cases where id = v_case) = 600000 and r -> 'case' ->> 'case_no' like 'BC/%', 'overcharge claim = price minus value (600,000), High Court');
  perform pg_temp.advance(91 * 60);
  perform pg_temp.login(pg_temp.u('p')); perform court_status();
  select * into c from court_cases where id = v_case;
  perform pg_temp.assert(c.verdict = 'guilty' and c.restitution_paid + c.restitution_debt = 600000, 'overcharge: paid and the rest is debt (never below zero)');
  perform pg_temp.assert(pg_temp.cash('d') >= 0 and pg_temp.bank('d') >= 0, 'defendant never below zero');
  raise notice 'ok 12: rent owed, unfair eviction, overcharge';
end $$;

-- ---------- 13. admin: overview, dismiss, remove judge, ban lawyer ----------
do $$
declare
  r jsonb; v_ev bigint; v_case bigint; v_pb bigint; v_h bigint; v_hold bigint; v_holder bigint; v_open int;
begin
  perform pg_temp.money('p', 0, 3000000); perform pg_temp.money('d', 500000, 500000);
  perform pg_temp.advance(3 * 3600);
  update profiles set last_seen = now() where id in (select id from profiles where username like 'CT\_%');
  perform pg_temp.login(pg_temp.u('adm'));
  r := admin_court_overview();
  perform pg_temp.assert(jsonb_array_length(r -> 'judges') = 4 and jsonb_array_length(r -> 'cases') > 5 and (r -> 'stats' ->> 'ruled')::int > 5 and jsonb_array_length(r -> 'lawyers') >= 3, 'overview: cases, judges, lawyers, stats');
  perform pg_temp.assert(pg_temp.call('p', 'select admin_court_overview()') = 'not_admin', 'overview is admin only');
  perform pg_temp.assert(pg_temp.call('p', 'select admin_court_ban_lawyer(''' || pg_temp.u('l1') || ''', true, ''x'')') = 'not_admin', 'ban is admin only');
  -- dismiss a case with a pending lawyer: filing fee and escrow come back
  v_ev := pg_temp.theft('d', 'p', 60000);
  v_pb := pg_temp.total('p');
  r := pg_temp.file('p', 'pickpocket', v_ev::text, 'l2'); v_case := pg_temp.case_id(r);
  perform pg_temp.assert(v_pb - pg_temp.total('p') = 1500 + 5000, 'fee and escrow paid');
  perform pg_temp.assert(pg_temp.call('adm', format('select admin_court_dismiss(%s, %L)', v_case, '')) = 'reason', 'dismiss needs a reason');
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_court_dismiss(v_case, 'Filed by mistake.');
  perform pg_temp.assert(pg_temp.total('p') = v_pb and (select status from court_cases where id = v_case) = 'dismissed', 'dismissed: everything refunded');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'court_dismiss' and (data ->> 'case')::bigint = v_case), 'dismissal audited');
  perform pg_temp.assert(exists (select 1 from court_statements where case_id = v_case and kind = 'ruling' and body like 'CASE DISMISSED%'), 'recorded');
  -- ban a lawyer who has an accepted hire: refunded, cannot practise
  r := pg_temp.file('p', 'pickpocket', v_ev::text, 'l2'); v_case := pg_temp.case_id(r);
  perform pg_temp.login(pg_temp.u('l2'));
  select id into v_h from court_hires where case_id = v_case and status = 'pending';
  perform court_hire_respond(v_h, true);
  v_hold := pg_temp.total('p');
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_court_ban_lawyer(pg_temp.u('l2'), true, 'Fake claims.');
  perform pg_temp.assert(pg_temp.total('p') = v_hold + 5000 and (select status from court_hires where id = v_h) = 'refunded', 'ban: open hires refunded');
  perform pg_temp.assert((select banned from court_lawyers where user_id = pg_temp.u('l2')) and exists (select 1 from admin_audit where action = 'court_lawyer_ban' and target_user = pg_temp.u('l2')), 'banned and audited');
  perform pg_temp.assert(pg_temp.call('l2', 'select court_lawyer_update(5000, null, true)') = 'banned_lawyer', 'a banned lawyer cannot update');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(pg_temp.court_list('p')) e where e ->> 'username' = 'CT_l2'), 'a banned lawyer is not listed');
  perform pg_temp.assert(pg_temp.call('d', format('select court_hire(%s, %L)', v_case, pg_temp.u('l2'))) in ('not_party', 'lawyer_unavailable'), 'cannot be hired');
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_court_ban_lawyer(pg_temp.u('l2'), false, '');
  perform pg_temp.assert(not (select banned from court_lawyers where user_id = pg_temp.u('l2')), 'reinstated');
  -- remove a judge: their open cases go back to the pool
  update court_cases set judge_id = pg_temp.u('j2') where id = v_case;
  select id into v_holder from ind_holders where user_id = pg_temp.u('j2') and status = 'active';
  perform pg_temp.assert(pg_temp.call('adm', format('select admin_court_remove_judge(%s, %L)', v_holder, '')) = 'reason', 'removal needs a reason');
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_court_remove_judge(v_holder, 'Not seen in court.');
  perform pg_temp.assert(not bl_court_judge_ok(pg_temp.u('j2')) and (select judge_id from court_cases where id = v_case) is null, 'judge removed, open cases released');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'court_judge_remove' and target_user = pg_temp.u('j2')), 'removal audited');
  perform pg_temp.assert(bl_pol_title(pg_temp.u('j2')) is distinct from 'Hon. Justice', 'the badge goes with the seat');
  perform admin_court_dismiss(v_case, 'cleanup');
  -- every filled seat: appoint beyond four fails
  perform admin_court_appoint_judge('CT_j2', 'a'); perform admin_court_appoint_judge('CT_g1', 'b'); perform admin_court_appoint_judge('CT_g2', 'c');
  perform pg_temp.assert(pg_temp.call('adm', 'select admin_court_appoint_judge(''CT_g3'', ''d'')') = 'filled', 'all four seats filled');
  select count(*) into v_open from ind_holders where office_id like 'court\_judge\_%' and status = 'active';
  perform pg_temp.assert(v_open = 4, 'four sitting judges');
  raise notice 'ok 13: admin overview, dismiss, ban lawyer, remove judge';
end $$;

-- ---------- 15. patched functions ----------
do $$
begin
  perform pg_temp.assert(pg_get_functiondef('public.bl_add_money(uuid, text, bigint, text, jsonb)'::regprocedure) like '%bl_court_garnish%'
                         and pg_get_functiondef('public.bl_add_money(uuid, text, bigint, text, jsonb)'::regprocedure) like '%bl_tax_garnish%', 'bl_add_money garnishes tax then court debt');
  perform pg_temp.assert(pg_get_functiondef('public.bl_push_on_event()'::regprocedure) like '%court_summons%' and pg_get_functiondef('public.bl_push_on_event()'::regprocedure) like '%referral_bonus%', 'court alerts push in the events category');
  perform pg_temp.assert(bl_ledger_label('court_fine', '{}'::jsonb) = 'Court fine' and bl_ledger_label('lawyer_fee_in', '{"label":"Lawyer fee (X)"}'::jsonb) = 'Lawyer fee (X)'
                         and bl_ledger_label('court_fee', '{}'::jsonb) = 'Court filing fee' and bl_ledger_label('lawyer_escrow', '{}'::jsonb) = 'Lawyer fee held', 'ledger labels');
  perform pg_temp.assert(bl_ledger_label('house_buy', '{}'::jsonb) = 'Home bought', 'the label function still knows its old reasons');
  raise notice 'ok 15: patched functions';
end $$;
