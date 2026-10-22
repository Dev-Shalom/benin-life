-- Godfather ticket (20261022000100_godfather_ticket.sql). Rolled back. Run (migration applied):
--   bash scripts/sql-test.sh -- supabase/tests/godfather_ticket_test.sql
-- Time moves with bl.test_offset_seconds. Groups: 1 grants / RLS / seeds / ledger · 2 refusals (not needed, off, no price, jail, broke) ·
-- 3 waivers + payment (bank first, fee + ticket, ledger, not earned) · 4 public tag + hidden probe · 5 probes (caught, cleared, during voting) ·
-- 6 report flag at 1 · 7 withdraw / admin disqualify / cancel refunds.
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

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('gt.' || p)::uuid $$;
create or replace function pg_temp.total(p_uid uuid) returns bigint language sql as $$ select cash + bank from profiles where id = p_uid $$;
create or replace function pg_temp.cand(p text) returns bigint language sql as $$ select id from pol_candidates where user_id = pg_temp.u(p) order by id desc limit 1 $$;

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
declare v uuid := pg_temp.new_user(lower(p_name) || '@gt.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, protected_until = null, created_at = now() - p_age, cash = 0, bank = 0, home_location_id = 'uselu_selfcon',
         energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0 where id = v;
  perform pg_temp.at(v, 'third_east');
  return v;
end $$;

create or replace function pg_temp.money(p_uid uuid, p_cash bigint, p_bank bigint) returns void
language sql as $$ update profiles set cash = p_cash, bank = p_bank where id = p_uid; $$;

-- ---------- setup ----------
do $$
declare
  v_keys text[] := array['adm', 'a', 'z', 'e', 'ch', 'gv', 'w', 'dq', 'j', 'broke', 'r1', 'r2', 'q'];
  v_young text[] := array['z', 'gv', 'w', 'dq', 'j', 'broke', 'q'];
  k text; u uuid;
begin
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  perform pg_temp.cfg('skills.enabled', 'true');
  perform pg_temp.cfg('pol.auto_cycle', 'false');
  foreach k in array v_keys loop
    u := pg_temp.mk('GT_' || k, case when k = any (v_young) then interval '1 hour' else interval '30 days' end);
    perform set_config('gt.' || k, u::text, true);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
  update profiles set job_level = 0 where id in (pg_temp.u('ch'), pg_temp.u('gv'));
end $$;

-- ---------- 1. grants / RLS / seeds / ledger ----------
do $$
begin
  perform pg_temp.assert(not has_function_privilege('anon', 'public.pol_declare(text,text,text,text,boolean)', 'execute'), 'anon cannot run pol_declare');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.pol_declare(text,text,text,text,boolean)', 'execute'), 'authenticated can run pol_declare');
  perform pg_temp.assert((select prosecdef from pg_proc where oid = 'public.pol_declare(text,text,text,text,boolean)'::regprocedure), 'pol_declare is security definer');
  perform pg_temp.assert(to_regprocedure('public.pol_declare(text,text,text,text)') is null, 'the old 4-argument pol_declare is gone');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_pol_ticket_info(uuid,offices)', 'execute')
                         and not has_function_privilege('anon', 'public.bl_pol_ticket_resolve()', 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_pol_ticket_resolve()', 'execute'), 'ticket helpers are private');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.pol_ticket_probes', 'select') and not has_table_privilege('anon', 'public.pol_ticket_probes', 'select')
                         and not has_table_privilege('authenticated', 'public.pol_ticket_probes', 'insert'), 'no grant on the probe table');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.pol_ticket_probes'::regclass)
                         and not exists (select 1 from pg_policies where tablename = 'pol_ticket_probes'), 'probe table: RLS on, no policies');
  perform pg_temp.assert((select ticket_price from offices where id = 'councillor') = 5000000000 and (select ticket_price from offices where id = 'chairman') = 25000000000
                         and (select ticket_price from offices where id = 'governor') = 50000000000
                         and not exists (select 1 from offices where kind = 'commissioner' and ticket_price is not null), 'ticket prices seeded, commissioners none');
  perform pg_temp.assert((select count(*) from game_config where key in ('pol.ticket_enabled', 'pol.ticket_probe_pct', 'pol.ticket_report_flag_count') and category = 'politics' and label <> '' and description <> '') = 3
                         and bl_pol_num('pol.ticket_probe_pct', 0) = 10 and bl_pol_num('pol.ticket_report_flag_count', 0) = 1 and bl_pol_flag('pol.ticket_enabled', false), 'ticket settings and defaults');
  perform pg_temp.assert(not ('godfather_ticket' = any (bl_earn_reasons())), 'godfather_ticket is not earned');
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,hustle,godfather_ticket"');
  perform pg_temp.assert(not ('godfather_ticket' = any (bl_earn_reasons())), 'not earned even if an admin lists it');
  perform pg_temp.assert(bl_ledger_label('godfather_ticket', '{}') = 'Godfather ticket', 'ledger label');
  perform pg_temp.assert(bl_econ_category('godfather_ticket') <> 'Other', 'Admin economy category');
  perform pg_temp.assert(bl_admin_table_spec('offices')->'cols'->>'ticket_price' = 'int_null', 'Content -> Offices edits the price');
  raise notice 'ok 1: grants, seeds, ledger';
end $$;

-- ---------- 2. refusals ----------
do $$
declare v_before bigint; v jsonb;
begin
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_pol_start();
  -- requirements met: no ticket
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.money(pg_temp.u('a'), 50000000, 0);
  v_before := pg_temp.total(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Steady light and clean gutters'', null, true)') = 'ticket_not_needed', 'refused when requirements already met');
  perform pg_temp.assert(pg_temp.total(pg_temp.u('a')) = v_before and not exists (select 1 from pol_candidates where user_id = pg_temp.u('a')), 'nothing charged, nobody declared');
  -- status: ticket not available for a player who meets everything
  v := pol_status();
  perform pg_temp.assert((select (e->>'ticket_available')::boolean from jsonb_array_elements(v->'offices') e where e->>'id' = 'councillor') = false
                         and (select (e->>'ticket_price')::bigint from jsonb_array_elements(v->'offices') e where e->>'id' = 'councillor') = 5000000000, 'status: price shown, ticket not available');
  -- the same player, without a ticket, declares as before (4 positional args still work)
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Steady light and clean gutters'', null)') = 'ok', 'plain declare still works');
  perform pg_temp.assert((select ticket_paid from pol_candidates where user_id = pg_temp.u('a')) = 0 and not exists (select 1 from pol_ticket_probes p join pol_candidates k on k.id = p.candidate_id where k.user_id = pg_temp.u('a')), 'no ticket, no probe');
  -- disabled / no price / not elected
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.money(pg_temp.u('z'), 3000000, 8000000);
  perform pg_temp.cfg('pol.ticket_enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null, true)') = 'ticket_off', 'refused when the ticket is switched off');
  v := pol_status();
  perform pg_temp.assert((select e->'ticket_price' from jsonb_array_elements(v->'offices') e where e->>'id' = 'councillor') = 'null'::jsonb
                         and (select (e->>'ticket_available')::boolean from jsonb_array_elements(v->'offices') e where e->>'id' = 'councillor') = false, 'status: no price when off');
  perform pg_temp.cfg('pol.ticket_enabled', 'true');
  update offices set ticket_price = null where id = 'councillor';
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null, true)') = 'ticket_off', 'refused when the office has no price');
  -- the rest of the suite uses smaller prices than the live ones (5B / 25B / 50B) so the money helpers stay readable
  update offices set ticket_price = 10000000 where id = 'councillor';
  update offices set ticket_price = 20000000 where id = 'chairman';
  update offices set ticket_price = 50000000 where id = 'governor';
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''commissioner_works'', null, ''Light for every street here'', null, true)') = 'bad_office', 'commissioners cannot be run for, ticket or not');
  -- jail is not waived (and the status says a ticket would not cover it)
  perform pg_temp.login(pg_temp.u('j'));
  perform pg_temp.money(pg_temp.u('j'), 50000000, 0);
  update profiles set jailed_until = bl_now() + interval '1 hour' where id = pg_temp.u('j');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null, true)') = 'jailed', 'a ticket does not get you out of jail');
  perform pg_temp.assert((select (e->>'ticket_available')::boolean from jsonb_array_elements(pol_status()->'offices') e where e->>'id' = 'councillor') = false, 'status: a ticket would not cover jail');
  update profiles set jailed_until = null where id = pg_temp.u('j');
  -- a banned player is refused like everybody else (the session guard)
  -- not enough money: fee + ticket together, nothing taken
  perform pg_temp.login(pg_temp.u('broke'));
  perform pg_temp.money(pg_temp.u('broke'), 5000000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null, true)') = 'not_enough_cash', 'all or nothing: cannot afford fee + ticket');
  perform pg_temp.assert(pg_temp.total(pg_temp.u('broke')) = 5000000 and not exists (select 1 from ledger where user_id = pg_temp.u('broke') and reason in ('campaign_fee', 'godfather_ticket') and created_at > bl_now() - interval '1 hour' and delta < 0), 'no money moved');
  -- the ticket does not skip the ward rule (a Councillor runs where they live): wrong ward still refused
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', ''ugbowo'', ''Light for every street here'', null, true)') = 'wrong_ward', 'the ward rule is not waived');
  raise notice 'ok 2: refusals';
end $$;

-- ---------- 3. waivers + payment ----------
do $$
declare v jsonb; v_cand bigint;
begin
  -- z: account too young. Cash 3,000,000 + bank 8,000,000. Fee 10,000 + ticket 10,000,000: bank first.
  perform pg_temp.login(pg_temp.u('z'));
  v := pol_status();
  perform pg_temp.assert((select (e->>'ticket_available')::boolean from jsonb_array_elements(v->'offices') e where e->>'id' = 'councillor') = true, 'status: the ticket would cover a young account');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null)') = 'account_young', 'without a ticket the young account is refused');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null, true)') = 'ok', 'ticket waives account age (Councillor)');
  perform pg_temp.assert((select bank from profiles where id = pg_temp.u('z')) = 0 and (select cash from profiles where id = pg_temp.u('z')) = 990000, 'bank first, then cash (11,000,000 - 10,010,000)');
  perform pg_temp.assert((select -sum(delta) from ledger where user_id = pg_temp.u('z') and reason = 'campaign_fee') = 10000
                         and (select -sum(delta) from ledger where user_id = pg_temp.u('z') and reason = 'godfather_ticket') = 10000000, 'ledger: fee 10,000 and ticket 10,000,000');
  perform pg_temp.assert((select count(*) from ledger where user_id = pg_temp.u('z') and reason = 'godfather_ticket' and delta > 0) = 0, 'a ticket is a pure sink (no credit)');
  perform pg_temp.assert(bl_ledger_label('godfather_ticket', (select meta from ledger where user_id = pg_temp.u('z') and reason = 'godfather_ticket' limit 1)) like 'Godfather ticket%', 'ledger label');
  perform pg_temp.assert((select ticket_paid from pol_candidates where user_id = pg_temp.u('z')) = 10000000 and (select fee_paid from pol_candidates where user_id = pg_temp.u('z')) = 10000, 'ticket and fee recorded');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null, true)') = 'already_candidate', 'one candidacy per election, ticket or not');
  -- e: recent EFCC record
  perform pg_temp.login(pg_temp.u('e'));
  perform pg_temp.money(pg_temp.u('e'), 20000000, 0);
  insert into jail_cases (user_id, reason, bail_amount, jail_seconds, jail_until, status, kind, created_at, closed_at)
  values (pg_temp.u('e'), 'EFCC test', 1000, 60, bl_now() - interval '1 day', 'served', 'efcc', bl_now() - interval '2 days', bl_now() - interval '2 days');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null)') = 'efcc_record', 'EFCC record blocks without a ticket');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null, true)') = 'ok', 'ticket waives the clean record');
  -- ch: Chairman, Charisma too low (a 30 day old account)
  perform pg_temp.login(pg_temp.u('ch'));
  perform pg_temp.money(pg_temp.u('ch'), 0, 30000000);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''chairman'', null, ''A better city for everybody'', null)') = 'charisma_low', 'Chairman needs Charisma 2');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''chairman'', null, ''A better city for everybody'', null, true)') = 'ok', 'ticket waives Charisma');
  perform pg_temp.assert(pg_temp.total(pg_temp.u('ch')) = 30000000 - 50000 - 20000000, 'Chairman: fee 50,000 + ticket 20,000,000');
  -- gv: Governor: age, Charisma and education all fail
  perform pg_temp.login(pg_temp.u('gv'));
  perform pg_temp.money(pg_temp.u('gv'), 60000000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''governor'', null, ''Roads, light and jollof for all'', null)') = 'account_young', 'Governor refused without a ticket');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''governor'', null, ''Roads, light and jollof for all'', null, true)') = 'ok', 'ticket waives age, Charisma and education / career');
  perform pg_temp.assert(pg_temp.total(pg_temp.u('gv')) = 60000000 - 250000 - 50000000, 'Governor: fee 250,000 + ticket 50,000,000');
  -- w and dq: more ticket candidates for the withdraw / disqualify tests
  perform pg_temp.login(pg_temp.u('w'));
  perform pg_temp.money(pg_temp.u('w'), 11000000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null, true)') = 'ok', 'w declares with a ticket');
  perform pg_temp.login(pg_temp.u('dq'));
  perform pg_temp.money(pg_temp.u('dq'), 11000000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null, true)') = 'ok', 'dq declares with a ticket');
  raise notice 'ok 3: waivers and payment';
end $$;

-- ---------- 4. public tag + hidden probe ----------
do $$
declare v jsonb; c election_cycles;
begin
  perform pg_temp.login(pg_temp.u('a'));
  v := pol_candidates();
  perform pg_temp.assert((select count(*) from jsonb_array_elements(v) e where (e->>'ticket')::boolean) = 6 and (select count(*) from jsonb_array_elements(v) e where not (e->>'ticket')::boolean) = 1, 'pol_candidates: six tagged, one plain');
  perform pg_temp.assert((select (e->>'ticket')::boolean from jsonb_array_elements(v) e where e->>'username' = 'GT_z') and not (select (e->>'ticket')::boolean from jsonb_array_elements(v) e where e->>'username' = 'GT_a'), 'the tag is on the ticket card only');
  perform pg_temp.assert(v::text !~* 'probe|catch|efcc', 'no probe fields in pol_candidates');
  v := pol_ballot();
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v->'races') r, jsonb_array_elements(r->'candidates') cand where cand->>'username' = 'GT_z' and (cand->>'ticket')::boolean)
                         and exists (select 1 from jsonb_array_elements(v->'races') r, jsonb_array_elements(r->'candidates') cand where cand->>'username' = 'GT_a' and not (cand->>'ticket')::boolean), 'pol_ballot carries the tag');
  perform pg_temp.assert(v::text !~* 'probe|catch', 'no probe fields in pol_ballot');
  perform pg_temp.assert(pol_status()::text !~* 'probe', 'no probe fields in pol_status');
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.assert((pol_status()->'me'->'candidacy'->>'ticket')::boolean, 'my own card shows the tag');
  perform pg_temp.login(pg_temp.u('adm'));
  v := admin_pol_overview();
  perform pg_temp.assert((select (e->>'ticket')::boolean from jsonb_array_elements(v->'candidates') e where e->>'username' = 'GT_z') and v::text !~* 'probe', 'Admin candidates table: tag, no probe');
  -- the probes: one per ticket candidate, inside the campaign window
  select * into c from election_cycles where status = 'registration';
  perform pg_temp.assert((select count(*) from pol_ticket_probes where cycle_id = c.id) = 6, 'one probe per ticket candidate');
  perform pg_temp.assert(not exists (select 1 from pol_ticket_probes where cycle_id = c.id and (probe_at < c.camp_start or probe_at > c.vote_start)), 'every probe time is inside the campaign window');
  perform pg_temp.assert((select count(distinct probe_at) from pol_ticket_probes where cycle_id = c.id) = 6, 'probe times are random');
  perform pg_temp.cfg('pol.ticket_probe_pct', '0');
  perform pg_temp.login(pg_temp.u('q'));
  raise notice 'ok 4: tag and hidden probe';
end $$;

-- ---------- 5. probes ----------
do $$
declare c election_cycles; v_before bigint; v_cand bigint;
begin
  select * into c from election_cycles where status = 'registration';
  -- not due yet: nothing happens
  perform pg_temp.login(pg_temp.u('a'));
  perform pol_status();
  perform pg_temp.assert((select count(*) from pol_ticket_probes where cycle_id = c.id and outcome is null) = 6, 'probes wait for their time');
  -- e is caught, ch is cleared (forced; the roll itself is secret)
  update pol_ticket_probes set catch = true, probe_at = bl_now() - interval '1 second' where candidate_id = pg_temp.cand('e');
  update pol_ticket_probes set catch = false, probe_at = bl_now() - interval '1 second' where candidate_id = pg_temp.cand('ch');
  v_before := pg_temp.total(pg_temp.u('e'));
  perform pg_temp.login(pg_temp.u('a'));
  perform pol_candidates();
  perform pg_temp.assert((select status from pol_candidates where user_id = pg_temp.u('e')) = 'disqualified' and (select dq_reason from pol_candidates where user_id = pg_temp.u('e')) = 'EFCC probe: godfather ticket', 'caught: disqualified with the reason');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('e') and kind = 'pol_disqualified' and body like '%EFCC%'), 'caught: alert sent');
  perform pg_temp.assert(pg_temp.total(pg_temp.u('e')) = v_before and not exists (select 1 from ledger where user_id = pg_temp.u('e') and reason in ('godfather_ticket', 'campaign_fee') and delta > 0), 'caught: no refund');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(pol_candidates()) x where x->>'username' = 'GT_e'), 'caught: off the candidates list');
  perform pg_temp.assert((select outcome from pol_ticket_probes where candidate_id = pg_temp.cand('e')) = 'caught', 'caught: probe closed');
  perform pg_temp.assert((select status from pol_candidates where user_id = pg_temp.u('ch')) = 'declared' and (select outcome from pol_ticket_probes where candidate_id = pg_temp.cand('ch')) = 'cleared', 'cleared: still a candidate');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('ch') and kind = 'pol_ticket_cleared' and body like '%found nothing%this time%'), 'cleared: alert sent');
  -- a second tick does not repeat alerts
  perform pol_candidates();
  perform pg_temp.assert((select count(*) from events where user_id = pg_temp.u('ch') and kind = 'pol_ticket_cleared') = 1 and (select count(*) from events where user_id = pg_temp.u('e') and kind = 'pol_disqualified') = 1, 'resolved once');
  raise notice 'ok 5: probes';
end $$;

-- ---------- 6. reports flag at 1 for ticket candidates ----------
do $$
declare v jsonb; v_tc bigint := pg_temp.cand('gv'); v_pc bigint := pg_temp.cand('a');
begin
  perform pg_temp.login(pg_temp.u('r1'));
  perform pol_report_vote_buying(v_tc, 'Giving out rice');
  perform pol_report_vote_buying(v_pc, 'Giving out rice');
  perform pg_temp.login(pg_temp.u('adm'));
  v := admin_pol_overview();
  perform pg_temp.assert((select (e->>'flagged')::boolean from jsonb_array_elements(v->'candidates') e where (e->>'id')::bigint = v_tc), 'ticket candidate flagged at 1 report');
  perform pg_temp.assert(not (select (e->>'flagged')::boolean from jsonb_array_elements(v->'candidates') e where (e->>'id')::bigint = v_pc), 'a normal candidate is not flagged at 1 report');
  perform pg_temp.cfg('pol.ticket_report_flag_count', '2');
  perform pg_temp.assert(not (select (e->>'flagged')::boolean from jsonb_array_elements(admin_pol_overview()->'candidates') e where (e->>'id')::bigint = v_tc), 'the ticket threshold is a setting');
  perform pg_temp.cfg('pol.ticket_report_flag_count', '1');
  raise notice 'ok 6: report flag';
end $$;

-- ---------- 7. withdraw / disqualify / cancel ----------
do $$
declare v_w bigint; v_before bigint; v_z bigint; v_ch bigint; v_msg jsonb;
begin
  -- withdraw: nothing refunded, probe dropped
  perform pg_temp.login(pg_temp.u('w'));
  v_w := pg_temp.cand('w');
  v_before := pg_temp.total(pg_temp.u('w'));
  perform pol_withdraw();
  perform pg_temp.assert(pg_temp.total(pg_temp.u('w')) = v_before and not exists (select 1 from ledger where user_id = pg_temp.u('w') and reason = 'godfather_ticket' and delta > 0), 'withdraw: no refund');
  perform pg_temp.assert(not exists (select 1 from pol_ticket_probes where candidate_id = v_w), 'withdraw: probe dropped');
  -- admin disqualify: no refund, same as the fee
  perform pg_temp.login(pg_temp.u('adm'));
  v_before := pg_temp.total(pg_temp.u('dq'));
  perform admin_pol_disqualify(pg_temp.cand('dq'), 'Vote buying');
  perform pg_temp.assert(pg_temp.total(pg_temp.u('dq')) = v_before, 'admin disqualify: no refund');
  -- admin cancel: ticket + fee come back as credits
  v_z := pg_temp.total(pg_temp.u('z')); v_ch := pg_temp.total(pg_temp.u('ch'));
  v_msg := admin_pol_cancel('Test cancel');
  perform pg_temp.assert(pg_temp.total(pg_temp.u('z')) = v_z + 10000 + 10000000, 'cancel refunds fee + ticket (Councillor)');
  perform pg_temp.assert(pg_temp.total(pg_temp.u('ch')) = v_ch + 50000 + 20000000, 'cancel refunds fee + ticket (Chairman)');
  perform pg_temp.assert((select sum(delta) from ledger where user_id = pg_temp.u('z') and reason = 'godfather_ticket') = 0, 'ticket ledger nets to zero after the refund');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = pg_temp.u('z') and reason = 'godfather_ticket' and delta = 10000000 and (meta->>'refund')::boolean), 'refund is a credit marked refund');
  perform pg_temp.assert(pg_temp.total(pg_temp.u('dq')) = v_before, 'disqualified are not refunded by cancel');
  raise notice 'ok 7: withdraw, disqualify, cancel';
end $$;

-- ---------- 8. a probe resolves even when voting has started ----------
do $$
declare c election_cycles; v_id bigint;
begin
  perform pg_temp.cfg('pol.ticket_probe_pct', '100');
  perform pg_temp.login(pg_temp.u('adm'));
  v_id := (admin_pol_start()->>'id')::bigint;
  perform pg_temp.login(pg_temp.u('q'));
  perform pg_temp.money(pg_temp.u('q'), 11000000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street here'', null, true)') = 'ok', 'q declares in the second election');
  perform pg_temp.assert((select catch from pol_ticket_probes where candidate_id = pg_temp.cand('q')), 'probe chance 100 always rolls caught');
  select * into c from election_cycles where id = v_id;
  -- nobody touches the app until voting day is on: the first call after that resolves the probe
  perform pg_temp.advance(extract(epoch from (c.vote_start - bl_now())) + 60);
  perform pg_temp.login(pg_temp.u('a'));
  perform pol_candidates();
  perform pg_temp.assert((select status from election_cycles where id = v_id) = 'voting', 'voting is open');
  perform pg_temp.assert((select status from pol_candidates where user_id = pg_temp.u('q')) = 'disqualified' and (select outcome from pol_ticket_probes where candidate_id = pg_temp.cand('q')) = 'caught', 'a due probe resolves during voting');
  raise notice 'ok 8: probe during voting';
end $$;
