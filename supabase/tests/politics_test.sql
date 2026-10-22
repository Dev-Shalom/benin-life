-- E4 money sinks: the "Tax holiday" policy (kind tax_cut) is a fifth whitelist entry; this suite counts four, so it is switched off here.
-- money_sinks_test.sql covers it. Tax / bills / VAT are pinned off as well.
update gov_policies set active = false where id = 'tax_holiday';
update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');
-- E3 (20261019000100_economy_balance) halved the office salaries (a seat pays no work). This suite tests the R12 maths on the original
-- numbers, so they are pinned back here (rolled back with everything else).
update offices set salary_per_day = case id when 'councillor' then 20000 when 'chairman' then 50000 when 'governor' then 100000 else 40000 end;
-- R12 Politics, "Benin Votes" (20261018001100_politics.sql). Rolled back. Run (migration applied):
--   bash scripts/sql-test.sh -- supabase/tests/politics_test.sql
-- Or with the migration first: bash scripts/sql-test.sh supabase/migrations/20261018001100_politics.sql -- supabase/tests/politics_test.sql
-- Time moves with bl.test_offset_seconds. Groups: 1 grants / RLS / private helpers · 2 seeds (offices, wards, polling units, policies, parties,
-- settings) · 3 cycle phases with time travel (start, advance, windows) · 4 parties + declare (requirements, fee bank first, moderation, races) ·
-- 5 campaign (rally, poster, momentum, supporters, endorsements, crew endorsement, report vote buying) · 6 voting (refusals: not open, wrong
-- place, alt age, wrong ward; once per office; ballot secrecy) · 7 close (tally, tie-break by rally points, coin flip, vacant seat) ·
-- 8 swearing-in (holders, title badge in places / profile / chat / friends, salary accrual, ledger, earned) · 9 Governor (appoint, sack,
-- policy once + effects, announcement rate limit + moderation, ward notice) · 10 polling units open only on voting day (travel, place) ·
-- 11 admin (second election: disqualify + audit, secrecy, cancel + refund, remove holder) · 12 term end · 13 auto cycle · 14 switch off.
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

create or replace function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('po.' || p)::uuid $$;
create or replace function pg_temp.cash(p_uid uuid) returns bigint language sql as $$ select cash from profiles where id = p_uid $$;
create or replace function pg_temp.bank(p_uid uuid) returns bigint language sql as $$ select bank from profiles where id = p_uid $$;
create or replace function pg_temp.cyc() returns bigint language sql as $$ select (select id from election_cycles where status in ('registration', 'campaign', 'voting') order by id desc limit 1) $$;

-- a free player at a place, online now
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
declare v uuid := pg_temp.new_user(lower(p_name) || '@po.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, protected_until = null, created_at = now() - p_age, cash = 0, bank = 0, home_location_id = p_home,
         energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0 where id = v;
  perform pg_temp.at(v, 'third_east');
  return v;
end $$;

create or replace function pg_temp.skill(p_uid uuid, p_skill text, p_xp int) returns void
language sql as $$
  insert into player_skills (user_id, skill_id, xp) values (p_uid, p_skill, p_xp) on conflict (user_id, skill_id) do update set xp = p_xp;
$$;

create or replace function pg_temp.money(p_uid uuid, p_cash bigint, p_bank bigint) returns void
language sql as $$ update profiles set cash = p_cash, bank = p_bank where id = p_uid; $$;

-- ---------- setup ----------
do $$
declare
  v_names text[] := array['PO_Adm', 'PO_A', 'PO_B', 'PO_C', 'PO_D', 'PO_E', 'PO_F', 'PO_G', 'PO_H', 'PO_I', 'PO_V1', 'PO_V2', 'PO_V3', 'PO_V4', 'PO_W1', 'PO_W2', 'PO_X1', 'PO_X2', 'PO_T'];
  v_keys  text[] := array['adm', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'v1', 'v2', 'v3', 'v4', 'w1', 'w2', 'x1', 'x2', 't'];
  v_homes text[] := array['uselu_selfcon', 'uselu_selfcon', 'uselu_selfcon', 'uselu_selfcon', 'uniben', 'uniben', 'gra_duplex', 'siluko_rd', 'gra_duplex', 'gra_duplex',
                          'uselu_selfcon', 'uselu_selfcon', 'uselu_selfcon', 'uselu_selfcon', 'uniben', 'uniben', 'gra_duplex', 'gra_duplex', 'uselu_selfcon'];
  i int; u uuid;
begin
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  perform pg_temp.cfg('skills.enabled', 'true');
  for i in 1..cardinality(v_names) loop
    u := pg_temp.mk(v_names[i], v_homes[i]);
    perform set_config('po.' || v_keys[i], u::text, true);
  end loop;
  -- a young account (1 hour old)
  u := pg_temp.mk('PO_Z', 'uselu_selfcon', interval '1 hour');
  perform set_config('po.z', u::text, true);
  update profiles set is_admin = true where id = pg_temp.u('adm');
  -- Charisma: A..I have what their race needs (the Governor race also needs a BSc or career level 5)
  perform pg_temp.skill(pg_temp.u('f'), 'charisma', 120);   -- level 3
  perform pg_temp.skill(pg_temp.u('g'), 'charisma', 120);
  perform pg_temp.skill(pg_temp.u('h'), 'charisma', 460);   -- level 5
  perform pg_temp.skill(pg_temp.u('i'), 'charisma', 460);
  insert into player_certificates (user_id, cert_id) values (pg_temp.u('h'), 'bsc') on conflict do nothing;
  update profiles set job_level = 6 where id = pg_temp.u('i');
  perform pg_temp.skill(pg_temp.u('a'), 'charisma', 120);   -- Charisma 3 (can endorse)
  -- no push noise, no random rolls
  perform pg_temp.cfg('pol.auto_cycle', 'true');
end $$;

-- ---------- 1. grants / RLS / private helpers ----------
do $$
declare f text; t text;
begin
  foreach f in array array['pol_status()', 'pol_candidates()', 'pol_ballot()', 'pol_results(int)', 'pol_party_create(text,text,text)', 'pol_declare(text,text,text,text,boolean)',
    'pol_set_promise(text)', 'pol_withdraw()', 'pol_rally()', 'pol_poster()', 'pol_back(bigint,text)', 'pol_unback(bigint,text)', 'pol_report_vote_buying(bigint,text)',
    'pol_vote(bigint)', 'pol_appoint(text,text)', 'pol_sack(text)', 'pol_announce(text)', 'pol_set_policy(text)', 'pol_ward_notice(text)', 'pol_resign()',
    'admin_pol_overview()', 'admin_pol_start(numeric,numeric,numeric,numeric)', 'admin_pol_advance()', 'admin_pol_cancel(text)', 'admin_pol_disqualify(bigint,text)',
    'admin_pol_dismiss_reports(bigint)', 'admin_pol_remove_holder(bigint,text)', 'admin_pol_tallies(bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || f, 'execute'), 'anon cannot run ' || f);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || f, 'execute'), 'authenticated can run ' || f);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || f)::regprocedure), 'security definer ' || f);
  end loop;
  perform pg_temp.assert((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'bl\_pol\_%') >= 30, 'helpers exist');
  perform pg_temp.assert(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname like 'bl\_pol\_%'
                            and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))), 'bl_pol_* helpers private (and the chat trigger)');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.players_here(text)'::regprocedure, 'execute')
                         and has_function_privilege('authenticated', 'public.get_public_profile(uuid)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_chat_row(chat_messages,jsonb,uuid)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_friend_card(profiles,profiles,numeric,boolean)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_ledger_label(text,jsonb)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_travel_quote(profiles,text)'::regprocedure, 'execute')
                         and not has_function_privilege('authenticated', 'public.bl_place_open(locations)'::regprocedure, 'execute'), 'patched functions keep their grants');
  foreach t in array array['wards', 'offices', 'gov_policies', 'parties', 'election_cycles', 'pol_candidates', 'pol_backing', 'pol_votes', 'pol_campaign_log', 'pol_reports',
                           'pol_results', 'office_holders'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || t)::regclass), 'RLS on ' || t);
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || t, 'select'), 'anon cannot read ' || t);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || t, 'insert') and not has_table_privilege('authenticated', 'public.' || t, 'update')
                           and not has_table_privilege('authenticated', 'public.' || t, 'delete'), 'no client writes on ' || t);
  end loop;
  foreach t in array array['election_cycles', 'pol_candidates', 'pol_backing', 'pol_votes', 'pol_campaign_log', 'pol_reports', 'pol_results', 'office_holders'] loop
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || t, 'select'), 'players cannot read ' || t || ' directly (RPCs only: ballots stay secret)');
  end loop;
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.offices', 'select') and has_table_privilege('authenticated', 'public.gov_policies', 'select')
                         and has_table_privilege('authenticated', 'public.wards', 'select') and has_table_privilege('authenticated', 'public.parties', 'select'), 'catalogues readable');
  raise notice 'ok 1: grants / RLS / private helpers';
end $$;

-- ---------- 2. seeds ----------
do $$
declare o offices;
begin
  perform pg_temp.assert((select count(*) from game_config where key like 'pol.%' and category = 'politics') >= 36, 'pol settings in the Politics category');
  perform pg_temp.assert((select count(*) from offices where active) = 9 and (select count(*) from offices where kind = 'commissioner') = 6, 'nine offices: councillor, chairman, governor + six commissioners');
  select * into o from offices where id = 'governor';
  perform pg_temp.assert(o.title = 'Gov.' and o.elected and o.fee = 250000 and o.min_charisma = 4 and o.salary_per_day = 100000 and o.cert_any = '{bsc,business_mgmt}' and o.alt_job_level = 5, 'governor defaults');
  perform pg_temp.assert((select ward_scoped from offices where id = 'councillor') and (select title from offices where id = 'councillor') = 'Hon.'
                         and not (select elected from offices where id = 'commissioner_works'), 'councillor per ward, commissioners appointed');
  perform pg_temp.assert((select count(*) from wards where active) = 8 and (select count(*) from wards w join locations l on l.id = w.poll_unit) = 8, 'eight wards, eight polling units');
  perform pg_temp.assert((select count(*) from locations where id like 'pu\_%' and scene = 'street' and active) = 8, 'polling unit places on the map');
  perform pg_temp.assert((select count(*) from zone_actions where id like 'pu\_%.desk.vote' and kind = 'panel' and ref = 'politics') = 8, 'a "Vote here" action at each unit');
  perform pg_temp.assert((select count(*) from gov_policies where active) = 4
                         and (select kind from gov_policies where id = 'keke_fridays') = 'travel_discount' and (select weekday from gov_policies where id = 'keke_fridays') = 5, 'four policies on the whitelist');
  perform pg_temp.assert((select count(*) from parties where seeded) = 4 and exists (select 1 from parties where name = 'Progressive Benin Movement') and exists (select 1 from parties where name = 'Oba-Town People''s Party'), 'fictional seeded parties');
  perform pg_temp.assert(not exists (select 1 from parties where upper(abbr) in ('APC', 'PDP', 'LP', 'NNPP')), 'no real party seeded');
  perform pg_temp.assert('office_salary' = any (bl_earn_reasons()), 'office_salary counts as earned');
  perform pg_temp.assert(not ('campaign_fee' = any (bl_earn_reasons())) and not ('campaign_spend' = any (bl_earn_reasons())), 'fees and spending are not earned');
  perform pg_temp.assert(bl_ledger_label('campaign_fee', '{}') = 'Election fee' and bl_ledger_label('campaign_spend', '{}') = 'Campaign spending'
                         and bl_ledger_label('office_salary', '{"label":"Governor salary (2 days)"}') = 'Governor salary (2 days)', 'ledger labels');
  perform pg_temp.assert(exists (select 1 from skill_sources where kind = 'politics' and ref = 'rally' and skill_id = 'charisma'), 'rally trains Charisma');
  perform pg_temp.assert(bl_pol_num('pol.registration_hours', 0) = 48 and bl_pol_num('pol.campaign_hours', 0) = 72 and bl_pol_num('pol.voting_hours', 0) = 24 and bl_pol_num('pol.term_days', 0) = 14, 'windows 2 / 3 / 1 days, term 14 days');
  perform pg_temp.assert(bl_pol_ward_of(pg_temp.u('a')) = 'uselu' and bl_pol_ward_of(pg_temp.u('d')) = 'ugbowo' and bl_pol_ward_of(pg_temp.u('f')) = 'gra' and bl_pol_ward_of(pg_temp.u('g')) = 'ring_road', 'a home district decides the ward');
  raise notice 'ok 2: seeds';
end $$;

-- ---------- 3. cycle phases with time travel ----------
do $$
declare v jsonb; c election_cycles; v_id bigint;
begin
  -- no election yet
  perform pg_temp.login(pg_temp.u('a'));
  v := pol_status();
  perform pg_temp.assert(v->'cycle' = 'null'::jsonb and (v->>'enabled')::boolean, 'no election yet');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street'', null)') = 'registration_closed', 'cannot declare before registration opens');
  -- a player cannot run the admin pages; an admin starts the cycle
  perform pg_temp.assert(pg_temp.hint_of('select admin_pol_start()') <> 'ok', 'only an admin starts an election');
  perform pg_temp.login(pg_temp.u('adm'));
  perform pg_temp.assert(pg_temp.hint_of('select admin_pol_start(0, 1, 1, 1)') = 'bad_value', 'windows must be above zero');
  v := admin_pol_start();
  v_id := (v->>'id')::bigint;
  perform set_config('po.cycle', v_id::text, true);
  select * into c from election_cycles where id = v_id;
  perform pg_temp.assert(c.status = 'registration' and c.vote_start - c.camp_start = interval '72 hours' and c.vote_end - c.vote_start = interval '24 hours'
                         and c.camp_start - c.reg_start = interval '48 hours' and c.term_days = 14, 'windows copied from Settings (2 / 3 / 1 days, term 14)');
  perform pg_temp.assert(pg_temp.hint_of('select admin_pol_start()') = 'running', 'one election at a time');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'pol_start' and (data->>'cycle')::bigint = v_id), 'start is audited');
  -- phases move with the clock
  perform pg_temp.advance(47 * 3600);
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pol_status()->'cycle'->>'status' = 'registration', 'still registration at 47 h');
  perform pg_temp.advance(2 * 3600);
  perform pg_temp.assert(pol_status()->'cycle'->>'status' = 'campaign', 'campaign at 49 h');
  perform pg_temp.advance(72 * 3600);
  perform pg_temp.assert(pol_status()->'cycle'->>'status' = 'voting' and (pol_status()->'cycle'->>'voting_open')::boolean, 'voting at 121 h');
  perform pg_temp.advance(24 * 3600);
  v := pol_status();
  perform pg_temp.assert(v->'cycle' = 'null'::jsonb and (select status from election_cycles where id = v_id) = 'closed', 'closed after the voting day (no candidates: nothing happens)');
  perform pg_temp.assert(v->>'next_cycle_at' is not null, 'status says when the next election starts');
  -- the admin can move a phase on (advance keeps the windows)
  delete from election_cycles where id = v_id;
  perform pg_temp.login(pg_temp.u('adm'));
  v_id := (admin_pol_start()->>'id')::bigint;
  perform set_config('po.cycle', v_id::text, true);
  perform pg_temp.assert(admin_pol_advance()->>'status' = 'campaign', 'advance: registration to campaign');
  select * into c from election_cycles where id = v_id;
  perform pg_temp.assert(c.vote_start - c.camp_start = interval '72 hours' and c.vote_end - c.vote_start = interval '24 hours', 'advance keeps the later windows');
  perform pg_temp.assert(admin_pol_advance()->>'status' = 'voting', 'advance: campaign to voting');
  perform pg_temp.assert(admin_pol_advance()->>'status' = 'closed', 'advance: voting to closed');
  perform pg_temp.assert(pg_temp.hint_of('select admin_pol_advance()') = 'none', 'nothing to advance');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'pol_advance' and data->>'to' = 'voting'), 'advance is audited');
  -- the real run for the rest of the suite
  delete from election_cycles where id = v_id;
  v_id := (admin_pol_start()->>'id')::bigint;
  perform set_config('po.cycle', v_id::text, true);
  raise notice 'ok 3: cycle phases';
end $$;

-- ---------- 4. parties + declare ----------
do $$
declare v jsonb; w_banned text; n int; v_bank0 bigint;
begin
  -- parties: fictional only, a fee (bank first), one per player
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.money(pg_temp.u('a'), 300000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_party_create(''APC Reborn'', ''ARB'', ''#336699'')') = 'blocked_name', 'a real party name is refused (whole-word match)');
  perform pg_temp.assert(pg_temp.hint_of('select pol_party_create(''Peoples Democratic Party'', ''PDB'', ''#336699'')') = 'blocked_name', 'a real party full name is refused');
  perform pg_temp.assert(pg_temp.hint_of('select pol_party_create(''Ugbowo Green Front'', ''LP'', ''#336699'')') = 'blocked_name', 'a real abbreviation is refused');
  perform pg_temp.assert(pg_temp.hint_of('select pol_party_create(''Tinubu Boys Club'', ''TBC'', ''#336699'')') = 'blocked_name', 'a real politician name is refused');
  perform pg_temp.assert(pg_temp.hint_of('select pol_party_create(''Ab'', ''ABC'', ''#336699'')') = 'bad_name', 'party name too short');
  perform pg_temp.assert(pg_temp.hint_of('select pol_party_create(''Ugbowo Green Front'', ''U'', ''#336699'')') = 'bad_abbr', 'abbreviation 2 to 5 letters');
  perform pg_temp.assert(pg_temp.hint_of('select pol_party_create(''Ugbowo Green Front'', ''UGF'', ''green'')') = 'bad_color', 'bad colour');
  perform pg_temp.assert(pg_temp.hint_of('select pol_party_create(''Progressive Benin Movement'', ''PBX'', ''#336699'')') = 'name_taken', 'seeded name taken');
  perform pg_temp.assert(pg_temp.hint_of('select pol_party_create(''Another Front'', ''PBM'', ''#336699'')') = 'name_taken', 'seeded abbreviation taken');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 300000, 'refusals charged nothing');
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_party_create(''Young Front'', ''YFR'', ''#336699'')') = 'not_enough_cash', 'a party costs money');
  perform pg_temp.login(pg_temp.u('a'));
  v := pol_party_create('Ugbowo Green Front', 'ugf', '#2f9e6b');
  perform set_config('po.party_a', v->>'id', true);
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 250000 and (select sum(-delta) from ledger where user_id = pg_temp.u('a') and reason = 'campaign_fee') = 50000, 'party fee 50,000 (ledger campaign_fee)');
  perform pg_temp.assert((select abbr from parties where id = v->>'id') = 'UGF' and not (select seeded from parties where id = v->>'id'), 'party saved, abbreviation upper-cased');
  perform pg_temp.assert(pg_temp.hint_of('select pol_party_create(''Second Front'', ''SEF'', ''#336699'')') = 'party_exists', 'one party per founder');

  -- declare: refusals
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.money(pg_temp.u('z'), 100000, 0);
  update profiles set created_at = bl_now() - interval '1 hour' where id = pg_temp.u('z');   -- time travel aged the account: make it young again
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street in Uselu'', null)') = 'account_young', 'a 1 hour old account cannot run (min account age)');
  perform pg_temp.login(pg_temp.u('b'));
  perform pg_temp.money(pg_temp.u('b'), 20000, 5000);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''chairman'', null, ''A better city for everybody here'', null)') = 'charisma_low', 'chairman needs Charisma 2');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''commissioner_works'', null, ''I will fix the roads fast'', null)') = 'bad_office', 'appointed offices cannot be run for');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', ''ugbowo'', ''Light for every street in Uselu'', null)') = 'wrong_ward', 'a Councillor runs where they live');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''short'', null)') = 'too_short', 'promise too short');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_declare(''councillor'', null, %L, null)', repeat('x', 200))) = 'too_long', 'promise too long');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Vote APC for better light please'', null)') = 'blocked_text', 'a real party in a promise is refused');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''I will copy what Tinubu did here'', null)') = 'blocked_text', 'a real politician in a promise is refused');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''INEC will rig this for me abeg'', null)') = 'blocked_text', 'the real election body is refused');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Read more on www.mypromise.com today'', null)') = 'blocked_text', 'no links');
  select word into w_banned from chat_banned_words where active order by word limit 1;
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_declare(''councillor'', null, %L, null)', 'I will ' || w_banned || ' every street')) = 'blocked_text', 'the chat banned words apply: ' || w_banned);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street in Uselu'', ''nope'')') = 'bad_party', 'unknown party');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('b')) = 20000 and pg_temp.bank(pg_temp.u('b')) = 5000, 'refusals charged nothing');
  -- jail and EFCC record
  perform pg_temp.login(pg_temp.u('t'));
  perform pg_temp.money(pg_temp.u('t'), 50000, 0);
  update profiles set jailed_until = bl_now() + interval '1 hour' where id = pg_temp.u('t');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street in Uselu'', null)') = 'jailed', 'a jailed player cannot run');
  update profiles set jailed_until = null where id = pg_temp.u('t');
  insert into jail_cases (user_id, reason, bail_amount, jail_seconds, jail_until, status, kind, created_at, closed_at)
  values (pg_temp.u('t'), 'EFCC test', 1000, 60, bl_now() - interval '1 day', 'served', 'efcc', bl_now() - interval '2 days', bl_now() - interval '2 days');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street in Uselu'', null)') = 'efcc_record', 'a recent EFCC case blocks a candidacy');
  perform pg_temp.cfg('pol.clean_record_days', '1');
  perform pg_temp.assert((bl_pol_requirements(pg_temp.u('t'), (select o from offices o where id = 'councillor'))->>'ok')::boolean, 'an old EFCC case does not (window is tunable)');
  perform pg_temp.cfg('pol.clean_record_days', '7');
  delete from jail_cases where user_id = pg_temp.u('t');
  -- the Governor needs Charisma 4 and a BSc / Business Management certificate or career level 5
  perform pg_temp.login(pg_temp.u('f'));
  perform pg_temp.money(pg_temp.u('f'), 1000000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''governor'', null, ''Roads, light and jollof for all'', null)') = 'charisma_low', 'governor needs Charisma 4');
  perform pg_temp.skill(pg_temp.u('c'), 'charisma', 460);
  perform pg_temp.login(pg_temp.u('c'));
  perform pg_temp.money(pg_temp.u('c'), 1000000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''governor'', null, ''Roads, light and jollof for all'', null)') = 'qualification', 'governor needs a certificate or career level 5');
  perform pg_temp.skill(pg_temp.u('c'), 'charisma', 0);
  -- the requirement checklist in the status (what the app shows)
  v := pol_status();
  perform pg_temp.assert((select count(*) from jsonb_array_elements(v->'offices') e where e->'requirements' is not null and e->>'kind' <> 'commissioner') = 3 and jsonb_array_length((v->'offices'->2->'requirements'->'checks')) >= 4, 'status carries a requirements checklist per elected office');

  -- declare for real. Fees: councillor 10,000, chairman 50,000, governor 250,000; bank first, then cash
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Steady light and clean gutters in Uselu'', null)') = 'ok', 'A declares (Ugbowo Green Front)');
  update pol_candidates set party_id = 'pbm' where user_id = pg_temp.u('a');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Another try for the same seat'', null)') = 'already_candidate', 'one candidacy per player per election');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 240000, 'fee 10,000 charged');
  perform pg_temp.login(pg_temp.u('b'));
  v := pol_declare('councillor', null, 'Free pure water at every junction', null);
  perform pg_temp.assert(pg_temp.bank(pg_temp.u('b')) = 0 and pg_temp.cash(pg_temp.u('b')) = 15000, 'fee taken bank first (5,000) then cash (5,000)');
  perform pg_temp.assert((select sum(-delta) from ledger where user_id = pg_temp.u('b') and reason = 'campaign_fee') = 10000
                         and (select meta->>'label' from ledger where user_id = pg_temp.u('b') and reason = 'campaign_fee' order by id limit 1) like 'Candidacy fee: Councillor%', 'ledger campaign_fee with a label');
  perform set_config('po.k_b', v->>'id', true);
  perform pg_temp.login(pg_temp.u('c'));
  perform pg_temp.money(pg_temp.u('c'), 1000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Jobs for the youths of Uselu'', ''opp'')') = 'not_enough_cash', 'no money, no candidacy');
  perform pg_temp.money(pg_temp.u('c'), 100000, 0);
  v := pol_declare('councillor', null, 'Jobs for the youths of Uselu', 'opp');
  perform set_config('po.k_c', v->>'id', true);
  -- race cap
  perform pg_temp.cfg('pol.max_candidates_per_slot', '3');
  perform pg_temp.login(pg_temp.u('x1'));
  perform pg_temp.money(pg_temp.u('x1'), 100000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', ''gra'', ''GRA needs quiet streets'', null)') = 'ok', 'a race in another ward (GRA)');
  perform pg_temp.login(pg_temp.u('t'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''One more voice for Uselu'', null)') = 'race_full', 'a race is full at the cap (3 in Uselu)');
  perform pg_temp.cfg('pol.max_candidates_per_slot', '8');
  -- the rest of the field
  perform pg_temp.login(pg_temp.u('d'));
  perform pg_temp.money(pg_temp.u('d'), 100000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Better roads around the campus'', null)') = 'ok', 'D (Ugbowo)');
  perform pg_temp.login(pg_temp.u('e'));
  perform pg_temp.money(pg_temp.u('e'), 100000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Students first, always'', ''bua'')') = 'ok', 'E (Ugbowo)');
  perform pg_temp.login(pg_temp.u('f'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''chairman'', null, ''One clean, safe city for all of us'', ''pbm'')') = 'ok', 'F runs for Chairman (lives in GRA, a city race)');
  perform pg_temp.login(pg_temp.u('g'));
  perform pg_temp.money(pg_temp.u('g'), 100000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''chairman'', null, ''Markets and motor parks that work'', ''jjp'')') = 'ok', 'G runs for Chairman');
  perform pg_temp.login(pg_temp.u('h'));
  perform pg_temp.money(pg_temp.u('h'), 1000000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''governor'', null, ''A Benin where light never goes'', ''pbm'')') = 'ok', 'H runs for Governor (BSc)');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('h')) = 750000, 'governor fee 250,000');
  perform pg_temp.login(pg_temp.u('i'));
  perform pg_temp.money(pg_temp.u('i'), 1000000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''governor'', null, ''Experience and a steady hand'', ''opp'')') = 'ok', 'I runs for Governor (career level 6)');
  -- T withdraws (and the promise can be edited while running)
  perform pg_temp.login(pg_temp.u('x1'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_set_promise(''Quiet streets and polite queues'')') = 'ok', 'promise can be edited');
  perform pg_temp.assert(pg_temp.hint_of('select pol_set_promise(''Vote PDP for us all'')') = 'blocked_text', 'an edited promise is moderated too');
  perform pg_temp.assert((select promise from pol_candidates where user_id = pg_temp.u('x1')) = 'Quiet streets and polite queues', 'promise saved');
  perform pg_temp.login(pg_temp.u('x2'));
  perform pg_temp.money(pg_temp.u('x2'), 100000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', ''gra'', ''Parking for everybody in GRA'', null)') = 'ok', 'X2 declares in GRA');
  perform pg_temp.assert(pg_temp.hint_of('select pol_withdraw()') = 'ok', 'a candidate can withdraw');
  perform pg_temp.assert((select status from pol_candidates where user_id = pg_temp.u('x2')) = 'withdrawn', 'withdrawn');
  perform pg_temp.assert(pg_temp.hint_of('select pol_withdraw()') = 'not_candidate', 'not a candidate any more');
  -- the lists
  perform pg_temp.login(pg_temp.u('v1'));
  v := pol_candidates();
  select count(*) into n from jsonb_array_elements(v);
  perform pg_temp.assert(n = 10, 'ten candidates are listed (A B C, X1, D E, F G, H I; the withdrawn one is gone): ' || n);
  perform pg_temp.assert((select e->'party'->>'abbr' from jsonb_array_elements(v) e where e->>'username' = 'PO_C') = 'OPP', 'the party shows on the card');
  -- campaign actions are closed until the campaign window
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.at(pg_temp.u('a'), 'uselu_market');
  perform pg_temp.assert(pg_temp.hint_of('select pol_rally()') = 'not_campaign', 'no rally during registration');
  perform pg_temp.assert(pg_temp.hint_of('select pol_poster()') = 'not_campaign', 'no poster during registration');
  raise notice 'ok 4: parties + declare';
end $$;

create or replace function pg_temp.k(p_uid uuid) returns bigint language sql as $$
  select id from pol_candidates where user_id = p_uid and status = 'declared' and cycle_id = pg_temp.cyc()
$$;
create or replace function pg_temp.cand(p_viewer uuid, p_uid uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.login(p_viewer);
  select e into v from jsonb_array_elements(pol_candidates()) e where (e->>'id')::bigint = pg_temp.k(p_uid);
  return v;
end $$;

-- ---------- 5. campaign: rally, poster, momentum, backing, crew endorsement, report vote buying ----------
do $$
declare v jsonb; xp0 int; n int; ka bigint; kb bigint; kc bigint; kf bigint; kg bigint; c1 bigint; c2 bigint; a_cash bigint;
begin
  perform pg_temp.advance(49 * 3600);                       -- registration is over
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pol_status()->'cycle'->>'status' = 'campaign', 'campaign window');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Too late to declare now'', null)') = 'registration_closed', 'declaring is closed once the campaign starts');
  ka := pg_temp.k(pg_temp.u('a')); kb := pg_temp.k(pg_temp.u('b')); kc := pg_temp.k(pg_temp.u('c')); kf := pg_temp.k(pg_temp.u('f')); kg := pg_temp.k(pg_temp.u('g'));
  perform pg_temp.money(pg_temp.u('a'), 240000, 0);
  -- rally refusals
  perform pg_temp.at(pg_temp.u('a'), 'uselu_market');
  update profiles set busy_until = bl_now() + interval '10 minutes', busy_label = 'Busy' where id = pg_temp.u('a');
  perform pg_temp.assert(pg_temp.hint_of('select pol_rally()') = 'not_free', 'a busy candidate cannot rally');
  perform pg_temp.at(pg_temp.u('a'), 'pu_uselu');
  perform pg_temp.assert(pg_temp.hint_of('select pol_rally()') = 'bad_place', 'no rally at a polling unit');
  perform pg_temp.at(pg_temp.u('a'), 'oba_market');
  perform pg_temp.assert(pg_temp.hint_of('select pol_rally()') = 'wrong_ward', 'a Councillor rally must be inside the ward');
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_rally()') = 'not_candidate', 'only candidates rally');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 240000, 'refusals cost nothing');
  -- a real rally: costs money, earns Charisma XP and momentum, announced in the place; a crowd adds points
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.at(pg_temp.u('a'), 'uselu_market'); perform pg_temp.at(pg_temp.u('v1'), 'uselu_market');
  xp0 := bl_skill_xp(pg_temp.u('a'), 'charisma');
  v := pol_rally();
  perform pg_temp.assert((v->>'points')::int = 12 and (v->>'attendees')::int = 1, 'base 10 + 2 for the one player there = 12 points');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 220000 and (select sum(-delta) from ledger where user_id = pg_temp.u('a') and reason = 'campaign_spend') = 20000, 'rally costs 20,000 (ledger campaign_spend)');
  perform pg_temp.assert(bl_skill_xp(pg_temp.u('a'), 'charisma') > xp0, 'a rally trains Charisma');
  perform pg_temp.assert((select rally_points from pol_candidates where id = ka) = 12 and (select rallies from pol_candidates where id = ka) = 1, 'rally points recorded');
  perform pg_temp.assert(exists (select 1 from place_announcements where location_id = 'uselu_market' and kind = 'rally' and username = 'PO_A' and text like '%Steady light%'), 'announced in the place');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('v1') and kind = 'pol_rally'), 'the people there get an alert');
  perform pg_temp.assert(not exists (select 1 from events where user_id = pg_temp.u('a') and kind = 'pol_rally'), 'not the candidate');
  perform pg_temp.assert(pg_temp.hint_of('select pol_rally()') = 'cooldown', 'rally cooldown');
  perform pg_temp.advance(21 * 60);
  perform pg_temp.at(pg_temp.u('a'), 'uselu_market'); perform pg_temp.at(pg_temp.u('v1'), 'uselu_market');
  perform pg_temp.cfg('pol.rally_max_per_day', '2');
  perform pg_temp.assert(pg_temp.hint_of('select pol_rally()') = 'ok', 'second rally after the cooldown');
  perform pg_temp.advance(21 * 60);
  perform pg_temp.at(pg_temp.u('a'), 'uselu_market');
  perform pg_temp.assert(pg_temp.hint_of('select pol_rally()') = 'daily_cap', 'rallies per day are capped');
  perform pg_temp.cfg('pol.rally_max_per_day', '6');
  perform pg_temp.assert(pg_temp.hint_of('select pol_rally()') = 'ok', 'a third rally once the cap is lifted');
  perform pg_temp.assert((select rally_points from pol_candidates where id = ka) = 12 + 12 + 10, 'three rallies: 12 + 12 + 10 (nobody else there the third time: V1 went quiet)');
  -- a Chairman rallies anywhere public
  perform pg_temp.login(pg_temp.u('f'));
  perform pg_temp.at(pg_temp.u('f'), 'oba_market'); perform pg_temp.at(pg_temp.u('g'), 'oba_market');
  perform pg_temp.money(pg_temp.u('f'), 100000, 0);
  v := pol_rally();
  perform pg_temp.assert((v->>'points')::int = 12, 'the Chairman race has no ward limit');
  -- poster
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_poster()') = 'ok', 'poster up');
  perform pg_temp.assert((select posters from pol_candidates where id = ka) = 1 and (select sum(-delta) from ledger where user_id = pg_temp.u('a') and reason = 'campaign_spend' and meta->>'label' = 'Campaign poster') = 10000, 'poster costs 10,000 (campaign_spend)');
  perform pg_temp.assert(pg_temp.hint_of('select pol_poster()') = 'cooldown', 'poster cooldown');
  perform pg_temp.advance(7 * 3600);
  perform pg_temp.cfg('pol.poster_max', '1');
  perform pg_temp.assert(pg_temp.hint_of('select pol_poster()') = 'poster_max', 'poster limit');
  perform pg_temp.cfg('pol.poster_max', '5');
  perform pg_temp.assert(pg_temp.hint_of('select pol_poster()') = 'ok', 'a second poster');
  -- supporters, endorsements, crews: three tiers of momentum, none of them votes
  perform pg_temp.login(pg_temp.u('v1'));
  perform pg_temp.assert((pg_temp.cand(pg_temp.u('v1'), pg_temp.u('a'))->>'supporters')::int = 0, 'no supporters yet');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''support'')', ka)) = 'ok', 'V1 declares support for A');
  perform pg_temp.assert((pg_temp.cand(pg_temp.u('v1'), pg_temp.u('a'))->>'supporters')::int = 1 and pg_temp.cand(pg_temp.u('v1'), pg_temp.u('a'))->>'my_backing' = 'support', 'supporter counted, my_backing says so');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''endorse'')', kb)) = 'charisma_low', 'a public endorsement needs Charisma 2');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''support'')', kb)) = 'ok', 'switching moves the backing within a race');
  perform pg_temp.assert((pg_temp.cand(pg_temp.u('v1'), pg_temp.u('a'))->>'supporters')::int = 0 and (pg_temp.cand(pg_temp.u('v1'), pg_temp.u('b'))->>'supporters')::int = 1, 'one backing per race');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''support'')', pg_temp.k(pg_temp.u('d')))) = 'ok', 'a different race is a separate backing');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''nonsense'')', ka)) = 'bad_kind', 'bad kind');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''endorse'')', ka)) = 'self', 'cannot back yourself');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''endorse'')', kc)) = 'ok', 'A (Charisma 3) endorses C in public');
  v := pg_temp.cand(pg_temp.u('a'), pg_temp.u('c'));
  perform pg_temp.assert((v->>'endorse_n')::int = 1 and v->'endorsers'->>0 = 'PO_A', 'named endorsement listed');
  update profiles set created_at = bl_now() - interval '1 hour' where id = pg_temp.u('z');
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''support'')', ka)) = 'account_young', 'anti-alt: a young account cannot back');
  -- crew endorsement: a Boss / Lieutenant of a crew with enough members
  insert into crews (name, tag, color, emblem) values ('Uselu Test Crew', 'UTC', '#336699', '🦁') returning id into c1;
  insert into crews (name, tag, color, emblem) values ('Lonely Crew', 'LON', '#993366', '🐺') returning id into c2;
  insert into crew_members (user_id, crew_id, rank) values (pg_temp.u('v2'), c1, 'boss'), (pg_temp.u('v3'), c1, 'member'), (pg_temp.u('v4'), c2, 'boss');
  perform pg_temp.login(pg_temp.u('v3'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''crew'')', kf)) = 'not_crew_leader', 'a plain member cannot endorse for the crew');
  perform pg_temp.login(pg_temp.u('v4'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''crew'')', kf)) = 'crew_small', 'a one-member crew cannot endorse');
  perform pg_temp.login(pg_temp.u('v2'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''crew'')', kg)) = 'ok', 'the crew Boss endorses G');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''crew'')', kf)) = 'ok', 'and moves the crew endorsement to F (one per race)');
  v := pg_temp.cand(pg_temp.u('v2'), pg_temp.u('f'));
  perform pg_temp.assert(v->'crews'->0->>'tag' = 'UTC' and v->>'my_backing' = 'crew', 'the crew shows on the candidate card');
  perform pg_temp.assert(jsonb_array_length(pg_temp.cand(pg_temp.u('v2'), pg_temp.u('g'))->'crews') = 0, 'moved away from G');
  -- momentum: shown against the race leader. A: 34 rally + 6 posters = 40; B: 1 support; C: 4 endorsement
  v := pg_temp.cand(pg_temp.u('v1'), pg_temp.u('a'));
  perform pg_temp.assert((v->>'points')::numeric = 12 + 12 + 10 + 2 * 3 and v->>'momentum' = 'Leading' and (v->>'momentum_pct')::int = 100, 'A leads: 34 rally points + 2 posters x 3');
  v := pg_temp.cand(pg_temp.u('v1'), pg_temp.u('c'));
  perform pg_temp.assert((v->>'points')::numeric = 4 and (v->>'momentum_pct')::int = round(100 * 4 / 40.0)::int and v->>'momentum' = 'Cold', 'C: an endorsement is 4 points, 10 % of the leader');
  v := pg_temp.cand(pg_temp.u('v1'), pg_temp.u('f'));
  perform pg_temp.assert((v->>'points')::numeric = 12 + 8 and v->>'momentum' = 'Leading', 'F leads the Chairman race: rally 12 + crew 8');
  perform pg_temp.assert(pg_temp.cand(pg_temp.u('v1'), pg_temp.u('g'))->>'momentum' = 'Cold', 'G has no momentum');
  perform pg_temp.assert(pg_temp.cand(pg_temp.u('v1'), pg_temp.u('h'))->>'momentum' = 'No momentum yet', 'a race with no activity says so');
  perform pg_temp.assert(not (pg_temp.cand(pg_temp.u('v1'), pg_temp.u('a')) ? 'votes') and not (pg_temp.cand(pg_temp.u('v1'), pg_temp.u('a')) ? 'final_votes'), 'momentum carries no vote counts');
  perform pg_temp.login(pg_temp.u('v1'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_unback(%s)', kb)) = 'ok' and (pg_temp.cand(pg_temp.u('v1'), pg_temp.u('b'))->>'supporters')::int = 0, 'support can be withdrawn');
  -- report vote buying (not a mechanic: a button)
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_report_vote_buying(%s, ''Giving out rice for votes'')', kc)) = 'ok', 'V1 reports C');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_report_vote_buying(%s, ''again'')', kc)) = 'already_reported', 'one report per player per candidate');
  perform pg_temp.login(pg_temp.u('v2'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_report_vote_buying(%s, ''Money for votes'')', kc)) = 'ok', 'V2 reports C');
  perform pg_temp.login(pg_temp.u('v3'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_report_vote_buying(%s, ''Money for votes'')', kc)) = 'ok', 'V3 reports C');
  perform pg_temp.login(pg_temp.u('c'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_report_vote_buying(%s)', kc)) = 'self', 'cannot report yourself');
  perform pg_temp.login(pg_temp.u('z'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_report_vote_buying(%s)', kc)) = 'account_young', 'a young account cannot report');
  perform pg_temp.login(pg_temp.u('v4'));
  perform pg_temp.cfg('pol.report_daily_cap', '1');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_report_vote_buying(%s)', kc)) = 'ok', 'first report today');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_report_vote_buying(%s)', ka)) = 'daily_cap', 'reports per day are capped');
  perform pg_temp.cfg('pol.report_daily_cap', '5');
  -- there is no vote-buying action anywhere: a player cannot pay another player to vote through any politics RPC
  perform pg_temp.assert(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'pol\_%' and (p.proname like '%buy%' and p.proname <> 'pol_report_vote_buying')), 'no vote-buying mechanic');
  perform pg_temp.assert((select count(*) from pol_reports where candidate_id = kc and status = 'open') = 4, 'four open reports on C');
  raise notice 'ok 5: campaign';
end $$;

-- ---------- 6. voting ----------
do $$
declare v jsonb; ka bigint; kb bigint; kd bigint; kf bigint; kg bigint; kh bigint; ki bigint; kx bigint; n int;
begin
  ka := pg_temp.k(pg_temp.u('a')); kb := pg_temp.k(pg_temp.u('b')); kd := pg_temp.k(pg_temp.u('d')); kf := pg_temp.k(pg_temp.u('f')); kg := pg_temp.k(pg_temp.u('g'));
  kh := pg_temp.k(pg_temp.u('h')); ki := pg_temp.k(pg_temp.u('i'));
  -- still the campaign: the polling units are closed and voting is refused
  perform pg_temp.login(pg_temp.u('v1'));
  perform pg_temp.at(pg_temp.u('v1'), 'pu_uselu');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', ka)) = 'not_voting', 'no voting during the campaign');
  perform pg_temp.assert(not bl_place_open((select l from locations l where id = 'pu_uselu')), 'a polling unit is closed outside voting day');
  perform pg_temp.at(pg_temp.u('v1'), 'third_east');
  perform pg_temp.assert(pg_temp.hint_of('select travel_quote(''pu_uselu'')') = 'closed', 'you cannot travel to a closed polling unit');
  begin
    perform travel_quote('pu_uselu');
  exception when others then
    perform pg_temp.assert(sqlerrm like '%Polling units open on voting day only%', 'the message says why: ' || sqlerrm);
  end;
  -- voting day
  perform pg_temp.advance(72 * 3600);
  perform pg_temp.at(pg_temp.u('v1'), 'third_east');
  perform pg_temp.assert(pol_status()->'cycle'->>'status' = 'voting', 'voting day');
  perform pg_temp.assert(bl_place_open((select l from locations l where id = 'pu_uselu')) and bl_place_open((select l from locations l where id = 'pu_airport_rd')), 'every polling unit opens on voting day');
  perform pg_temp.assert(jsonb_array_length(travel_quote('pu_uselu')->'options') = 5, 'and you can travel there');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_back(%s, ''support'')', ka)) = 'locked', 'no backing on voting day');
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Way too late now'', null)') = 'registration_closed', 'no declaring on voting day');
  -- wrong place, alt age, wrong ward, travelling, jail
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', ka)) = 'wrong_place', 'you must be at your polling unit');
  begin
    perform pol_vote(ka);
  exception when others then
    perform pg_temp.assert(sqlerrm like '%Uselu Polling Unit%', 'the message names the polling unit');
  end;
  perform pg_temp.at(pg_temp.u('v1'), 'pu_ugbowo');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', ka)) = 'wrong_place', 'another ward''s polling unit is the wrong place');
  perform pg_temp.login(pg_temp.u('z'));
  update profiles set created_at = bl_now() - interval '1 hour' where id = pg_temp.u('z');
  perform pg_temp.at(pg_temp.u('z'), 'pu_uselu');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', ka)) = 'account_young', 'anti-alt: a young account cannot vote');
  perform pg_temp.assert(not (pol_ballot()->'eligible'->>'ok')::boolean and (pol_ballot()->>'can_vote')::boolean is not true, 'the ballot says so too');
  perform pg_temp.login(pg_temp.u('v2'));
  perform pg_temp.at(pg_temp.u('v2'), 'pu_uselu');
  update profiles set travel_to = 'uniben' where id = pg_temp.u('v2');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', ka)) = 'wrong_place', 'not while on the road');
  update profiles set travel_to = null, jailed_until = bl_now() + interval '1 hour' where id = pg_temp.u('v2');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', ka)) = 'jailed', 'not from jail');
  update profiles set jailed_until = null where id = pg_temp.u('v2');
  -- V1 votes at the Uselu unit
  perform pg_temp.login(pg_temp.u('v1'));
  perform pg_temp.at(pg_temp.u('v1'), 'pu_uselu');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kd)) = 'wrong_ward', 'a Councillor race of another ward is not on my ballot');
  perform pg_temp.assert(pg_temp.hint_of('select pol_vote(999999)') = 'not_candidate', 'unknown candidate');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', (select id from pol_candidates where status = 'withdrawn' limit 1))) = 'not_candidate', 'a withdrawn candidate is not on the ballot');
  v := pol_ballot();
  perform pg_temp.assert((v->>'voting_open')::boolean and (v->>'at_unit')::boolean and (v->>'can_vote')::boolean and v->'unit'->>'id' = 'pu_uselu' and v->'ward'->>'id' = 'uselu', 'ballot: open, I am at my unit');
  perform pg_temp.assert(jsonb_array_length(v->'races') = 3 and (select count(*) from jsonb_array_elements(v->'races') r where not (r->>'voted')::boolean) = 3, 'three races (my Councillor, Chairman, Governor), none voted yet');
  perform pg_temp.assert(jsonb_array_length(v->'races'->0->'candidates') = 3, 'three Councillor candidates in Uselu');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', ka)) = 'ok', 'V1 votes for the Councillor');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kb)) = 'already_voted', 'one vote per office');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', ka)) = 'already_voted', 'not even the same one twice');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kf)) = 'ok', 'V1 votes for the Chairman (any ward votes)');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kh)) = 'ok', 'and the Governor');
  v := pol_ballot();
  perform pg_temp.assert((select count(*) from jsonb_array_elements(v->'races') r where (r->>'voted')::boolean) = 3, 'ballot shows that I voted ...');
  perform pg_temp.assert(position('"votes"' in v::text) = 0 and position('final_votes' in v::text) = 0 and position('my_vote' in v::text) = 0, '... but never for whom, and no counts');
  -- the others
  perform pg_temp.login(pg_temp.u('v2'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', ka)) = 'ok' and pg_temp.hint_of(format('select pol_vote(%s)', kg)) = 'ok' and pg_temp.hint_of(format('select pol_vote(%s)', ki)) = 'ok', 'V2: A, G, I');
  perform pg_temp.login(pg_temp.u('v3'));
  perform pg_temp.at(pg_temp.u('v3'), 'pu_uselu');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', ka)) = 'ok', 'V3: A');
  perform pg_temp.login(pg_temp.u('v4'));
  perform pg_temp.at(pg_temp.u('v4'), 'pu_uselu');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kb)) = 'ok', 'V4: B');
  perform pg_temp.login(pg_temp.u('w1'));
  perform pg_temp.at(pg_temp.u('w1'), 'pu_ugbowo');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kd)) = 'ok', 'W1: D (Ugbowo)');
  perform pg_temp.login(pg_temp.u('w2'));
  perform pg_temp.at(pg_temp.u('w2'), 'pu_ugbowo');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kd)) = 'ok', 'W2: D (Ugbowo)');
  -- ballot secrecy: no tallies anywhere before the close
  perform pg_temp.login(pg_temp.u('v1'));
  perform pg_temp.assert(pol_results(5) = '[]'::jsonb, 'no results while voting');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(pol_candidates()) e where e ? 'votes' or e ? 'final_votes'), 'candidate cards carry no counts');
  perform pg_temp.login(pg_temp.u('adm'));
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_pol_tallies(%s)', pg_temp.cyc())) = 'secret', 'even admins see no tallies before the close');
  v := admin_pol_overview();
  perform pg_temp.assert((v->'cycle'->>'votes_cast')::int = 10 and (v->'cycle'->>'voters')::int = 6, 'admin sees turnout only: 10 votes from 6 voters');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(v->'candidates') e where e->>'final_votes' is not null), 'and no per-candidate counts');
  perform pg_temp.assert((select count(*) from pol_candidates where final_votes is not null) = 0, 'nothing written before the close');
  raise notice 'ok 6: voting';
end $$;

-- ---------- 7. close: tally, tie-breaks, vacant seats ----------
do $$
declare v jsonb; r jsonb; v_gov uuid; v_exp uuid; ka bigint; kh bigint; ki bigint; v_cycle bigint := pg_temp.cyc();
begin
  perform pg_temp.advance(24 * 3600);
  perform pg_temp.login(pg_temp.u('v1'));
  v := pol_status();
  perform pg_temp.assert(v->'cycle' = 'null'::jsonb and (select status from election_cycles where id = v_cycle) = 'closed' and (select closed_at from election_cycles where id = v_cycle) is not null, 'the election closed');
  perform pg_temp.assert(not bl_place_open((select l from locations l where id = 'pu_uselu')), 'polling units close again');
  perform pg_temp.assert(pg_temp.hint_of('select travel_quote(''pu_uselu'')') = 'closed', 'and cannot be travelled to');
  v := pol_results(5);
  perform pg_temp.assert(jsonb_array_length(v) = 1 and (v->0->>'votes')::int = 10 and (v->0->>'voters')::int = 6 and jsonb_array_length(v->0->'races') = 5, 'one election in the history, 5 races, 10 votes by 6 voters');
  -- Uselu Councillor: A 3, B 1, C 0, a plain win
  select e into r from jsonb_array_elements(v->0->'races') e where e->>'ward_id' = 'uselu';
  perform pg_temp.assert(r->'winner'->>'username' = 'PO_A' and (r->'winner'->>'votes')::int = 3 and (r->>'total_votes')::int = 4 and r->>'tie' is null, 'Uselu: A wins 3 of 4 votes, no tie');
  perform pg_temp.assert(r->'candidates'->0->>'username' = 'PO_A' and r->'candidates'->1->>'username' = 'PO_B' and (r->'candidates'->2->>'votes')::int = 0, 'the tallies are public now, in order');
  select e into r from jsonb_array_elements(v->0->'races') e where e->>'ward_id' = 'ugbowo';
  perform pg_temp.assert(r->'winner'->>'username' = 'PO_D' and (r->'winner'->>'votes')::int = 2, 'Ugbowo: D wins 2-0');
  -- GRA: one candidate and nobody voted: low turnout is fine, the lone candidate takes the seat
  select e into r from jsonb_array_elements(v->0->'races') e where e->>'ward_id' = 'gra';
  perform pg_temp.assert(r->'winner'->>'username' = 'PO_X1' and (r->'winner'->>'votes')::int = 0 and (r->>'total_votes')::int = 0, 'GRA: a lone candidate wins even with 0 votes');
  -- tie on votes (1 each): the Chairman is decided by rally points (F 12, G 0)
  select e into r from jsonb_array_elements(v->0->'races') e where e->>'office_id' = 'chairman';
  perform pg_temp.assert(r->'winner'->>'username' = 'PO_F' and r->>'tie' = 'rally' and (r->>'total_votes')::int = 2, 'Chairman: 1-1, F wins on rally points');
  -- tie on votes AND rally points (H, I: 1 vote each, no rallies): the deterministic coin flip
  select e into r from jsonb_array_elements(v->0->'races') e where e->>'office_id' = 'governor';
  select user_id into v_exp from pol_candidates k where cycle_id = v_cycle and slot_key = 'governor:-' and status = 'declared' order by bl_pol_coin(k) limit 1;
  perform pg_temp.assert(r->>'tie' = 'coin' and r->'winner'->>'username' = (select username from profiles where id = v_exp), 'Governor: 1-1 and equal rally points, the coin decides (lowest md5 of cycle:race:player)');
  perform pg_temp.assert(bl_pol_coin((select k from pol_candidates k where user_id = pg_temp.u('h') and cycle_id = v_cycle)) = md5(v_cycle::text || ':governor:-:' || pg_temp.u('h')::text || ':coin'), 'the coin seed is deterministic');
  perform pg_temp.assert((select final_votes from pol_candidates where user_id = pg_temp.u('a') and cycle_id = v_cycle) = 3 and (select won from pol_candidates where user_id = pg_temp.u('a') and cycle_id = v_cycle), 'counts written at the close');
  -- vacant seats stay vacant
  perform pg_temp.assert((select count(*) from office_holders where status = 'active' and office_id = 'councillor') = 3, 'three Councillors sworn in; the other five wards are vacant');
  -- alerts
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('a') and kind = 'pol_won') and exists (select 1 from events where user_id = pg_temp.u('b') and kind = 'pol_lost' and body like '%1 vote%'), 'winners and losers are told');
  -- admin tallies open
  perform pg_temp.login(pg_temp.u('adm'));
  perform pg_temp.assert(jsonb_array_length(admin_pol_tallies(v_cycle)->'races') = 5, 'admin tallies after the close');
  perform pg_temp.assert(pg_temp.hint_of('select admin_pol_tallies(999999)') = 'gone', 'no such election');
  -- a late vote is refused
  perform pg_temp.login(pg_temp.u('v3'));
  perform pg_temp.at(pg_temp.u('v3'), 'pu_uselu');
  perform pg_temp.assert(pg_temp.hint_of('select pol_vote(1)') = 'not_voting', 'no voting after the close');
  raise notice 'ok 7: close, tie-breaks';
end $$;

create or replace function pg_temp.friends(a uuid, b uuid) returns void
language sql as $$
  insert into player_friendships (user_a, user_b, status, requested_by) values (least(a, b), greatest(a, b), 'accepted', a) on conflict do nothing;
$$;
create or replace function pg_temp.gov() returns uuid language sql as $$ select user_id from office_holders where office_id = 'governor' and status = 'active' $$;
create or replace function pg_temp.holder(p_office text, p_ward text default null) returns office_holders language sql as $$
  select h from office_holders h where h.office_id = p_office and coalesce(h.ward_id, '') = coalesce(p_ward, '') and h.status = 'active'
$$;

-- ---------- 8. swearing-in: holders, title badge, salary ----------
do $$
declare h office_holders; v jsonb; row jsonb; bank0 bigint; n int;
begin
  perform set_config('po.c1', (select max(id) from election_cycles where status = 'closed')::text, true);
  h := pg_temp.holder('councillor', 'uselu');
  perform pg_temp.assert(h.user_id = pg_temp.u('a') and h.term_end - h.term_start = interval '14 days' and h.paid_through = h.term_start, 'A is the Uselu Councillor for 14 days');
  perform pg_temp.assert((select count(*) from office_holders where status = 'active') = 5, 'five seats filled: 3 Councillors, the Chairman, the Governor');
  perform pg_temp.assert(bl_pol_title(pg_temp.u('a')) = 'Hon.' and bl_pol_title(pg_temp.u('f')) = 'Chairman' and bl_pol_title(pg_temp.gov()) = 'Gov.' and bl_pol_title(pg_temp.u('b')) is null, 'titles: Hon. / Chairman / Gov., none for the losers');
  -- the badge next to a name: places, profile, chat, friends
  perform pg_temp.at(pg_temp.u('a'), 'uselu_market'); perform pg_temp.at(pg_temp.u('v1'), 'uselu_market');
  perform pg_temp.login(pg_temp.u('v1'));
  select e into row from jsonb_array_elements(players_here('uselu_market')) e where e->>'username' = 'PO_A';
  perform pg_temp.assert(row->>'title' = 'Hon.', 'players_here carries the title');
  select e into row from jsonb_array_elements(players_here('uselu_market')) e where e->>'username' = 'PO_V1' or e->>'username' = 'PO_V4' limit 1;
  perform pg_temp.assert(row is null or row->>'title' is null, 'no title for a plain player');
  perform pg_temp.assert(get_public_profile(pg_temp.u('a'))->>'title' = 'Hon.' and get_public_profile(pg_temp.u('b'))->>'title' is null, 'profile carries the title');
  perform pg_temp.cfg('chat.min_account_real_minutes', '0');
  perform pg_temp.login(pg_temp.u('a'));
  v := chat_send('Wetin dey happen for ward');
  perform pg_temp.assert(v->>'pol_title' = 'Hon.' and (select pol_title from chat_messages where user_id = pg_temp.u('a') order by id desc limit 1) = 'Hon.', 'chat rows carry the title (stamped when written)');
  perform pg_temp.login(pg_temp.u('v1'));
  perform pg_temp.assert((select e->>'pol_title' from jsonb_array_elements(chat_recent('uselu_market', 20)) e where e->>'username' = 'PO_A' limit 1) = 'Hon.', 'chat_recent shows the title');
  perform pg_temp.advance(5);
  v := chat_send('hello from a plain citizen');
  perform pg_temp.assert(v->>'pol_title' is null, 'no title without office');
  perform pg_temp.friends(pg_temp.u('a'), pg_temp.u('v1'));
  perform pg_temp.assert((select e->>'title' from jsonb_array_elements(friends_overview()->'friends') e where e->>'username' = 'PO_A') = 'Hon.', 'friend cards carry the title');
  -- the salary: a day of term = the office salary, paid to the bank, earned money
  bank0 := pg_temp.bank(pg_temp.u('a'));
  perform pg_temp.advance(3 * 86400 + 60);
  perform pg_temp.login(pg_temp.u('a'));
  v := pol_status();
  perform pg_temp.assert(pg_temp.bank(pg_temp.u('a')) = bank0 + 3 * 20000, 'three days of Councillor salary (3 x 20,000) paid to the bank');
  perform pg_temp.assert((select count(*) from ledger where user_id = pg_temp.u('a') and reason = 'office_salary') = 1
                         and (select meta->>'label' from ledger where user_id = pg_temp.u('a') and reason = 'office_salary') = 'Councillor salary (3 days)', 'one ledger line office_salary with a label');
  perform pg_temp.assert((v->'me'->'office'->>'salary_paid')::bigint = 60000 and v->'me'->'office'->>'title' = 'Hon.', 'status shows the salary paid and the title');
  perform pg_temp.assert(pol_status() is not null and pg_temp.bank(pg_temp.u('a')) = bank0 + 60000, 'asking again never pays twice');
  perform pg_temp.assert(pg_temp.bank(pg_temp.gov()) >= 300000 and (select salary_paid from office_holders where office_id = 'governor' and status = 'active') = 300000, 'the Governor''s 3 days (3 x 100,000) were paid by the same clock');
  perform pg_temp.assert('office_salary' = any (bl_earn_reasons()) and exists (select 1 from ledger l where l.reason = any (bl_earn_reasons()) and l.reason = 'office_salary'), 'salary counts as earned income');
  -- status shapes: the government list has every seat, vacant ones too
  v := pol_status();
  perform pg_temp.assert(jsonb_array_length(v->'government') = 8 + 1 + 1 + 6, '16 seats: 8 wards, Chairman, Governor, 6 Commissioners');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(v->'government') e where e->'holder' <> 'null'::jsonb) = 5, 'five seats filled');
  perform pg_temp.assert(v->>'next_cycle_at' is not null and v->'cycle' = 'null'::jsonb, 'the next election is scheduled');
  raise notice 'ok 8: swearing-in, titles, salary';
end $$;

-- ---------- 9. the Governor: appoint, sack, policy, announcement; the Councillor's ward notice ----------
do $$
declare
  v jsonb; v_gov uuid := pg_temp.gov(); v_name text; g office_holders; prof profiles; q1 jsonb; q2 jsonb; k1 bigint; k2 bigint; g0 int; g1 int; h0 numeric; h1 numeric; n int; r jsonb;
begin
  select username into v_name from profiles where id = v_gov;
  -- appoint / sack
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_appoint(''commissioner_works'', ''PO_V3'')') = 'not_governor', 'only the Governor appoints');
  perform pg_temp.assert(pg_temp.hint_of('select pol_sack(''commissioner_works'')') = 'not_governor', 'only the Governor sacks');
  perform pg_temp.assert(pg_temp.hint_of('select pol_set_policy(''clean_benin'')') = 'not_governor', 'only the Governor sets policy');
  perform pg_temp.assert(pg_temp.hint_of('select pol_announce(''Hello everybody, Hon. A here'')') = 'not_governor', 'only the Governor announces');
  perform pg_temp.login(v_gov);
  v := pol_status();
  perform pg_temp.assert((v->'me'->'powers'->>'can_announce')::boolean and (v->'me'->'powers'->>'can_set_policy')::boolean and jsonb_array_length(v->'me'->'powers'->'commissioners') = 6
                         and jsonb_array_length(v->'me'->'powers'->'policies') = 4, 'the Governor''s status lists the powers');
  perform pg_temp.assert(pg_temp.hint_of('select pol_appoint(''governor'', ''PO_V3'')') = 'bad_office', 'only Commissioner posts');
  perform pg_temp.assert(pg_temp.hint_of('select pol_appoint(''commissioner_works'', ''nobody_xyz'')') = 'no_player', 'unknown username');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_appoint(''commissioner_works'', %L)', v_name)) = 'self', 'not yourself');
  update profiles set created_at = bl_now() - interval '1 hour' where id = pg_temp.u('z');
  perform pg_temp.assert(pg_temp.hint_of('select pol_appoint(''commissioner_works'', ''PO_Z'')') = 'account_young', 'anti-alt: a young account cannot be appointed');
  perform pg_temp.assert(pg_temp.hint_of('select pol_appoint(''commissioner_works'', ''@PO_A'')') = 'holds_office', 'a sitting Councillor holds an office already');
  perform pg_temp.assert(pg_temp.hint_of('select pol_appoint(''commissioner_works'', ''@po_v3'')') = 'ok', 'V3 becomes Commissioner for Works (case and @ do not matter)');
  perform pg_temp.assert(pg_temp.hint_of('select pol_appoint(''commissioner_works'', ''PO_V4'')') = 'filled', 'a filled post must be vacated first');
  perform pg_temp.assert(pg_temp.hint_of('select pol_appoint(''commissioner_finance'', ''PO_V3'')') = 'holds_office', 'one office per player');
  perform pg_temp.assert(pg_temp.hint_of('select pol_appoint(''commissioner_finance'', ''PO_V4'')') = 'ok', 'V4 becomes Commissioner for Finance');
  g := pg_temp.holder('governor');
  perform pg_temp.assert((pg_temp.holder('commissioner_works')).term_end = g.term_end and (pg_temp.holder('commissioner_works')).appointed_by = v_gov, 'appointees serve until the Governor''s term ends');
  perform pg_temp.assert(bl_pol_title(pg_temp.u('v3')) = 'Comm.' and exists (select 1 from events where user_id = pg_temp.u('v3') and kind = 'pol_appointed'), 'title Comm. and an alert');
  perform pg_temp.login(pg_temp.u('v3'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_appoint(''commissioner_commerce'', ''PO_T'')') = 'not_governor', 'a Commissioner cannot appoint');
  perform pg_temp.login(v_gov);
  perform pg_temp.assert(pg_temp.hint_of('select pol_sack(''commissioner_finance'')') = 'ok', 'the Governor sacks the Finance Commissioner');
  perform pg_temp.assert(bl_pol_title(pg_temp.u('v4')) is null and (select status from office_holders where user_id = pg_temp.u('v4') and office_id = 'commissioner_finance') = 'sacked'
                         and exists (select 1 from events where user_id = pg_temp.u('v4') and kind = 'pol_sacked'), 'sacked: no title, an alert');
  perform pg_temp.assert(pg_temp.hint_of('select pol_sack(''commissioner_finance'')') = 'vacant', 'nobody holds it any more');
  perform pg_temp.assert(pg_temp.hint_of('select pol_sack(''chairman'')') = 'bad_office', 'only Commissioners can be sacked');

  -- ONE policy per term, from the whitelist
  perform pg_temp.assert(pg_temp.hint_of('select pol_set_policy(''free_money'')') = 'bad_policy', 'only whitelisted policies');
  perform pg_temp.assert(pg_temp.hint_of('select pol_set_policy(''keke_fridays'')') = 'ok', 'Keke Fridays is the policy');
  perform pg_temp.assert(pg_temp.hint_of('select pol_set_policy(''clean_benin'')') = 'policy_set', 'one policy per term');
  v := pol_status();
  perform pg_temp.assert(v->'policy'->>'id' = 'keke_fridays' and (v->'policy'->>'value')::numeric = 30, 'the status shows the policy and its value');
  -- effect 1: travel. On a Friday (here: today's weekday is made the policy day) keke fares drop 30 %, other fares do not
  select * into prof from profiles where id = pg_temp.u('v1');
  update gov_policies set weekday = extract(isodow from (bl_now() at time zone 'Africa/Lagos'))::int where id = 'keke_fridays';
  q1 := bl_travel_quote(prof, 'oba_market');
  update gov_policies set weekday = (extract(isodow from (bl_now() at time zone 'Africa/Lagos'))::int % 7) + 1 where id = 'keke_fridays';
  q2 := bl_travel_quote(prof, 'oba_market');
  k1 := (select (e->>'cost')::bigint from jsonb_array_elements(q1->'options') e where e->>'mode' = 'keke');
  k2 := (select (e->>'cost')::bigint from jsonb_array_elements(q2->'options') e where e->>'mode' = 'keke');
  perform pg_temp.assert(k2 > 0 and k1 = (ceil(k2 * 0.7 / 10) * 10)::bigint and k1 < k2, 'keke fare on the policy day is 30 % cheaper: ' || k1 || ' vs ' || k2);
  perform pg_temp.assert((select (e->>'cost')::bigint from jsonb_array_elements(q1->'options') e where e->>'mode' = 'bus') = (select (e->>'cost')::bigint from jsonb_array_elements(q2->'options') e where e->>'mode' = 'bus')
                         and (select (e->>'cost')::bigint from jsonb_array_elements(q1->'options') e where e->>'mode' = 'drop') = (select (e->>'cost')::bigint from jsonb_array_elements(q2->'options') e where e->>'mode' = 'drop'), 'other fares are untouched');
  update gov_policies set weekday = extract(isodow from (bl_now() at time zone 'Africa/Lagos'))::int where id = 'keke_fridays';
  -- effect 2: Fitness XP (youth sports week). The other kinds are switched in directly (a Governor sets only one)
  update office_holders set policy_id = null where office_id = 'governor' and status = 'active';
  r := bl_skill_award(pg_temp.u('v1'), 'crew', 'port_container');
  g0 := (select (e->>'gain')::int from jsonb_array_elements(r) e where e->>'skill' = 'fitness');
  update office_holders set policy_id = 'youth_sports_week' where office_id = 'governor' and status = 'active';
  r := bl_skill_award(pg_temp.u('v1'), 'crew', 'port_container');
  g1 := (select (e->>'gain')::int from jsonb_array_elements(r) e where e->>'skill' = 'fitness');
  perform pg_temp.assert(g0 >= 1 and g1 > g0 and abs(g1 - g0 * 1.25) <= 1, 'Fitness XP +25 %: ' || g0 || ' -> ' || g1);
  perform pg_temp.assert((select gain from (select (e->>'gain')::int as gain from jsonb_array_elements(r) e where e->>'skill' = 'driving') x) = (select (e->>'gain')::int from jsonb_array_elements(bl_skill_award(pg_temp.u('v2'), 'crew', 'port_container')) e where e->>'skill' = 'driving'), 'only Fitness is boosted');
  -- effect 3: slower hygiene decay (Clean Benin)
  update profiles set hygiene = 100, bladder = 100, needs_updated_at = bl_now() - interval '1 hour' where id = pg_temp.u('v1');
  select * into prof from profiles where id = pg_temp.u('v1');
  update office_holders set policy_id = null where office_id = 'governor' and status = 'active';
  h0 := 100 - (bl_decay_row(prof, bl_now())).hygiene;
  update office_holders set policy_id = 'clean_benin' where office_id = 'governor' and status = 'active';
  h1 := 100 - (bl_decay_row(prof, bl_now())).hygiene;
  perform pg_temp.assert(h0 > 0 and abs(h1 - 0.8 * h0) < 0.01, 'hygiene falls 20 % slower: ' || h0 || ' -> ' || h1);
  -- effect 4: council levy chance (R10 business events) cut 25 %
  update office_holders set policy_id = null where office_id = 'governor' and status = 'active';
  perform pg_temp.assert(bl_pol_levy_mult() = 1, 'no policy: levy chance unchanged');
  update office_holders set policy_id = 'levy_holiday' where office_id = 'governor' and status = 'active';
  perform pg_temp.assert(bl_pol_levy_mult() = 0.75, 'Market levy holiday: levy chance x 0.75');
  perform pg_temp.assert(position('bl_pol_levy_mult()' in pg_get_functiondef('public.bl_biz_settle(bigint, boolean)'::regprocedure)) > 0, 'the business settle uses it');
  perform set_config('bl.test_rand', '0.07', true);
  perform pg_temp.assert(bl_crime_roll(8) and not bl_crime_roll(8 * bl_pol_levy_mult()), 'a roll of 0.07 hits an 8 % levy but misses it at 6 %');
  perform set_config('bl.test_rand', '', true);
  update office_holders set policy_id = 'keke_fridays' where office_id = 'governor' and status = 'active';

  -- announcement: moderated, once a day, through the broadcast system
  perform pg_temp.assert(pg_temp.hint_of('select pol_announce(''short'')') = 'too_short', 'announcement too short');
  perform pg_temp.assert(pg_temp.hint_of('select pol_announce(''Vote APC everybody, they are best'')') = 'blocked_text', 'a real party is refused');
  perform pg_temp.assert(pg_temp.hint_of('select pol_announce(''Tinubu will visit Benin next week'')') = 'blocked_text', 'a real politician is refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_announce(%L)', repeat('x', 300))) = 'too_long', 'announcement too long');
  select count(*) into n from broadcasts where created_by = v_gov;
  v := pol_announce('Keke fares drop on Fridays. Make everybody dey enjoy am!');
  perform pg_temp.assert(n = 0 and (select count(*) from broadcasts where created_by = v_gov) = 1, 'one broadcast row');
  perform pg_temp.assert((select title from broadcasts where created_by = v_gov) = 'Government announcement: Gov. @' || v_name and (select audience from broadcasts where created_by = v_gov) = 'everyone', 'titled as the Government, to everybody');
  perform pg_temp.assert((v->>'reach')::int >= 15, 'reaches the players');
  perform pg_temp.login(pg_temp.u('t'));
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(broadcast_inbox()->'rows') e where e->>'title' like 'Government announcement%' and e->>'body' like 'Keke fares%'), 'any player sees it in the alerts inbox');
  perform pg_temp.login(v_gov);
  perform pg_temp.assert(pg_temp.hint_of('select pol_announce(''A second announcement the same day'')') = 'cooldown', 'rate limit: one a day');
  perform pg_temp.assert(not (pol_status()->'me'->'powers'->>'can_announce')::boolean and pol_status()->'me'->'powers'->>'announce_next_at' is not null, 'status says when the next one is allowed');
  perform pg_temp.advance(25 * 3600);
  perform pg_temp.assert(pg_temp.hint_of('select pol_announce(''Day two: gutters are being cleared, abeg dey patient'')') = 'ok', 'the next day another one is allowed');

  -- a Councillor's ward notice, once per term, to the ward's neighbours
  perform pg_temp.login(pg_temp.u('v1'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_ward_notice(''Football match for the ward on Saturday'')') = 'not_councillor', 'only a Councillor');
  perform pg_temp.at(pg_temp.u('v1'), 'third_east'); perform pg_temp.at(pg_temp.u('v2'), 'third_east'); perform pg_temp.at(pg_temp.u('d'), 'third_east');
  perform pg_temp.login(pg_temp.u('a'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_ward_notice(''Vote PDP for the ward football'')') = 'blocked_text', 'moderated');
  perform pg_temp.assert(pg_temp.hint_of('select pol_ward_notice(''hi'')') = 'too_short', 'too short');
  v := pol_ward_notice('Ward football match on Saturday, everybody come!');
  perform pg_temp.assert((v->>'reach')::int >= 2, 'sent to the ward''s recently active neighbours: ' || (v->>'reach'));
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('v1') and kind = 'pol_ward_notice' and body like 'Ward football%')
                         and not exists (select 1 from events where user_id = pg_temp.u('d') and kind = 'pol_ward_notice'), 'Uselu residents get it; Ugbowo does not');
  perform pg_temp.assert(pg_temp.hint_of('select pol_ward_notice(''A second ward notice, same term'')') = 'used', 'one per term');
  -- resigning
  perform pg_temp.login(pg_temp.u('x1'));
  perform pg_temp.assert(bl_pol_title(pg_temp.u('x1')) = 'Hon.', 'X1 is the GRA Councillor');
  perform pg_temp.assert(pg_temp.hint_of('select pol_resign()') = 'ok', 'a Councillor can resign');
  perform pg_temp.assert(bl_pol_title(pg_temp.u('x1')) is null, 'and the title is gone');
  perform pg_temp.assert(pg_temp.hint_of('select pol_resign()') = 'no_office', 'nothing left to resign from');
  raise notice 'ok 9: Governor powers, policies, announcements, ward notice';
end $$;

-- ---------- 10. the next election starts by itself, when the term ends minus the election span ----------
do $$
declare v jsonb; c1 election_cycles; v_target timestamptz; c election_cycles;
begin
  select * into c1 from election_cycles where id = current_setting('po.c1')::bigint;
  v_target := c1.vote_end + make_interval(secs => c1.term_days * 86400 - 144 * 3600);     -- 14 d term, 6 d election: 8 days after the results
  perform pg_temp.assert(v_target - c1.vote_end = interval '8 days', 'the next election is due 8 days after the results (14 d term - 2 + 3 + 1 d)');
  perform pg_temp.advance(extract(epoch from (v_target - bl_now())) - 120);
  perform pg_temp.login(pg_temp.u('v1'));
  v := pol_status();
  perform pg_temp.assert(v->'cycle' = 'null'::jsonb and abs(extract(epoch from ((v->>'next_cycle_at')::timestamptz - v_target))) < 2, 'two minutes before: nothing running, status knows the date');
  perform pg_temp.advance(180);
  v := pol_status();
  perform pg_temp.assert(v->'cycle'->>'status' = 'registration', 'it starts itself: registration is open');
  select * into c from election_cycles where id = (v->'cycle'->>'id')::bigint;
  perform pg_temp.assert(c.created_by is null and c.vote_end - c.reg_start = interval '144 hours' and c.term_days = 14, 'started by the system with the Settings windows');
  perform pg_temp.assert(exists (select 1 from push_outbox where kind = 'pol_registration' limit 1) or not exists (select 1 from push_subscriptions), 'registration open is pushed (events category) to players with a device');
  -- the government is still in office for the rest of the term
  perform pg_temp.assert(bl_pol_title(pg_temp.u('a')) = 'Hon.' and bl_pol_title(pg_temp.gov()) = 'Gov.', 'the government stays until the results');
  raise notice 'ok 10: auto cycle';
end $$;

-- ---------- 11. admin: disqualify (audited), report review, remove from office, cancel with refunds ----------
do $$
declare v jsonb; kv1 bigint; kv2 bigint; n int; v_gov uuid := pg_temp.gov(); bank0 bigint; hid bigint; a record;
begin
  -- two Chairman candidates, three voters
  perform pg_temp.skill(pg_temp.u('v1'), 'charisma', 40); perform pg_temp.skill(pg_temp.u('v2'), 'charisma', 40);
  perform pg_temp.login(pg_temp.u('v1'));
  perform pg_temp.money(pg_temp.u('v1'), 200000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''chairman'', null, ''Cheap keke and clean markets'', ''bua'')') = 'ok', 'V1 runs for Chairman');
  perform pg_temp.login(pg_temp.u('v2'));
  perform pg_temp.money(pg_temp.u('v2'), 200000, 0);
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''chairman'', null, ''Safer roads at night'', null)') = 'ok', 'V2 runs for Chairman');
  kv1 := pg_temp.k(pg_temp.u('v1')); kv2 := pg_temp.k(pg_temp.u('v2'));
  perform pg_temp.login(pg_temp.u('t'));
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_report_vote_buying(%s, ''Rice for votes at the junction'')', kv2)) = 'ok', 'T reports V2');
  -- admin pages are for admins
  perform pg_temp.assert(pg_temp.hint_of('select admin_pol_overview()') <> 'ok' and pg_temp.hint_of(format('select admin_pol_disqualify(%s, ''x'')', kv1)) <> 'ok'
                         and pg_temp.hint_of('select admin_pol_cancel(''x'')') <> 'ok' and pg_temp.hint_of('select admin_pol_advance()') <> 'ok', 'players cannot run admin actions');
  perform pg_temp.login(pg_temp.u('adm'));
  v := admin_pol_overview();
  perform pg_temp.assert(v->'cycle'->>'status' = 'registration' and jsonb_array_length(v->'candidates') = 2 and jsonb_array_length(v->'holders') = 5, 'overview: the cycle, 2 candidates, 5 sitting holders');
  perform pg_temp.assert((select (e->>'reports')::int from jsonb_array_elements(v->'candidates') e where e->>'username' = 'PO_V2') = 1
                         and (select e->'report_texts'->>0 from jsonb_array_elements(v->'candidates') e where e->>'username' = 'PO_V2') like 'Rice for votes%', 'reports and their text are visible to admins');
  perform pg_temp.assert(admin_pol_advance()->>'status' = 'campaign' and admin_pol_advance()->>'status' = 'voting', 'admin moves to voting');
  -- votes: T and V4 for V1, W1 for V2
  perform pg_temp.login(pg_temp.u('t'));
  perform pg_temp.at(pg_temp.u('t'), 'pu_uselu');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kv1)) = 'ok', 'T votes V1');
  perform pg_temp.login(pg_temp.u('v4'));
  perform pg_temp.at(pg_temp.u('v4'), 'pu_uselu');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kv1)) = 'ok', 'V4 votes V1');
  perform pg_temp.login(pg_temp.u('w1'));
  perform pg_temp.at(pg_temp.u('w1'), 'pu_ugbowo');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kv2)) = 'ok', 'W1 votes V2');
  -- disqualify: reason needed, audited, votes for them are voided (voters can vote again)
  perform pg_temp.login(pg_temp.u('adm'));
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_pol_disqualify(%s, '''')', kv1)) = 'reason', 'a reason is required');
  perform pg_temp.assert(pg_temp.hint_of('select admin_pol_disqualify(999999, ''x'')') = 'gone', 'no such candidate');
  v := admin_pol_disqualify(kv1, 'Vote buying confirmed by two witnesses');
  perform pg_temp.assert(v->>'message' like '%2 votes voided%', 'two votes voided: ' || (v->>'message'));
  perform pg_temp.assert((select status from pol_candidates where id = kv1) = 'disqualified' and (select dq_reason from pol_candidates where id = kv1) like 'Vote buying%', 'status disqualified, reason kept');
  select * into a from admin_audit where action = 'pol_disqualify' order by id desc limit 1;
  perform pg_temp.assert(a.admin_id = pg_temp.u('adm') and a.target_user = pg_temp.u('v1') and (a.data->>'votes_voided')::int = 2 and a.data->>'reason' like 'Vote buying%' and (a.data->>'candidate')::bigint = kv1, 'the disqualification is audited (who, whom, why, votes voided)');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('v1') and kind = 'pol_disqualified'), 'the candidate is told');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_pol_disqualify(%s, ''again'')', kv1)) = 'gone', 'cannot disqualify twice');
  perform pg_temp.assert((select count(*) from pol_votes where cycle_id = pg_temp.cyc() and office_id = 'chairman') = 1, 'only W''s vote stays');
  perform pg_temp.login(pg_temp.u('t'));
  perform pg_temp.assert(jsonb_array_length(pol_ballot()->'races'->1->'candidates') = 1 and not (pol_ballot()->'races'->1->>'voted')::boolean, 'T''s ballot lists only V2 and T can vote again');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kv1)) = 'not_candidate', 'a disqualified candidate cannot be voted for');
  perform pg_temp.assert(pg_temp.hint_of(format('select pol_vote(%s)', kv2)) = 'ok', 'T votes again, for V2');
  perform pg_temp.login(pg_temp.u('adm'));
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_pol_tallies(%s)', pg_temp.cyc())) = 'secret', 'still no tallies while voting');
  -- reports: review
  v := admin_pol_dismiss_reports(kv2);
  perform pg_temp.assert(v->>'message' like '1 report%' and exists (select 1 from admin_audit where action = 'pol_reports_dismiss' and (data->>'candidate')::bigint = kv2), 'reports reviewed (audited)');
  -- remove holders (sitting government) with a reason, audited
  hid := (pg_temp.holder('chairman')).id;
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_pol_remove_holder(%s, '''')', hid)) = 'reason', 'a reason is required');
  v := admin_pol_remove_holder(hid, 'Abuse of the announcement tool');
  perform pg_temp.assert(v->>'message' = 'Removed from office.', 'the Chairman is removed');
  perform pg_temp.assert(bl_pol_title(pg_temp.u('f')) is null and (select status from office_holders where id = hid) = 'removed' and exists (select 1 from events where user_id = pg_temp.u('f') and kind = 'pol_removed'), 'no title, an alert');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'pol_remove_holder' and target_user = pg_temp.u('f') and data->>'reason' like 'Abuse%'), 'removal audited');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_pol_remove_holder(%s, ''again'')', hid)) = 'gone', 'already empty');
  -- cancel: fees come back (not for the disqualified), the sitting government stays, no restart by itself
  bank0 := pg_temp.bank(pg_temp.u('v2'));
  v := admin_pol_cancel('Testing the cancel button');
  perform pg_temp.assert((select status from election_cycles where id = (select max(id) from election_cycles)) = 'cancelled' and v->>'message' like '%1 candidate%', 'cancelled, one candidate refunded');
  perform pg_temp.assert(pg_temp.bank(pg_temp.u('v2')) = bank0 + 50000 and exists (select 1 from ledger where user_id = pg_temp.u('v2') and reason = 'campaign_fee' and delta = 50000 and meta->>'label' like '%refunded%'), 'the 50,000 fee is refunded (ledger campaign_fee, a credit)');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = pg_temp.u('v1') and reason = 'campaign_fee' and delta > 0), 'the disqualified candidate gets no refund');
  perform pg_temp.assert(exists (select 1 from events where user_id = pg_temp.u('v2') and kind = 'pol_cancelled') and exists (select 1 from admin_audit where action = 'pol_cancel'), 'told and audited');
  perform pg_temp.assert(bl_pol_title(pg_temp.u('a')) = 'Hon.' and pg_temp.hint_of('select admin_pol_cancel(''x'')') = 'none', 'the government stays; nothing left to cancel');
  perform pg_temp.assert(pg_temp.hint_of('select admin_pol_disqualify(' || kv2 || ', ''late'')') = 'closed', 'no disqualification after the election is over');
  raise notice 'ok 11: admin';
end $$;

-- ---------- 12. term end: titles go, the last salary stops at the term end, policies stop, a cancelled cycle never restarts ----------
do $$
declare h office_holders; hg office_holders; prof profiles; q jsonb; k bigint; v jsonb; sal0 bigint;
begin
  h := pg_temp.holder('councillor', 'uselu'); hg := pg_temp.holder('governor');
  perform pg_temp.assert(bl_pol_levy_mult() = 0.75 or (select policy_id from office_holders where id = hg.id) = 'keke_fridays', 'a policy is in force during the term');
  perform pg_temp.advance(extract(epoch from (hg.term_end - bl_now())) + 3600);
  perform pg_temp.login(pg_temp.u('a'));
  v := pol_status();
  perform pg_temp.assert((select status from office_holders where id = h.id) = 'ended' and (select status from office_holders where id = hg.id) = 'ended', 'terms ended');
  perform pg_temp.assert((select salary_paid from office_holders where id = h.id) = 14 * 20000, 'the Councillor was paid 14 days, never more: ' || (select salary_paid from office_holders where id = h.id));
  perform pg_temp.assert((select salary_paid from office_holders where id = hg.id) = 14 * 100000, 'the Governor 14 x 100,000');
  perform pg_temp.assert((select count(*) from office_holders where status = 'active') = 0 and bl_pol_title(pg_temp.u('a')) is null and bl_pol_title(pg_temp.gov()) is null, 'no titles left');
  perform pg_temp.assert(v->'me'->'office' = 'null'::jsonb and (select count(*) from jsonb_array_elements(v->'government') e where e->'holder' <> 'null'::jsonb) = 0, 'the government list is empty');
  perform pg_temp.assert(exists (select 1 from office_holders where office_id = 'commissioner_works' and status = 'ended' and salary_paid = 40000 * floor(extract(epoch from (term_end - term_start)) / 86400)), 'appointees are paid to the end of the term and end with it');
  -- the policy stops with the term
  select * into prof from profiles where id = pg_temp.u('v1');
  q := bl_travel_quote(prof, 'oba_market');
  update gov_policies set weekday = extract(isodow from (bl_now() at time zone 'Africa/Lagos'))::int where id = 'keke_fridays';
  perform pg_temp.assert((select (e->>'cost')::bigint from jsonb_array_elements(bl_travel_quote(prof, 'oba_market')->'options') e where e->>'mode' = 'keke') = (select (e->>'cost')::bigint from jsonb_array_elements(q->'options') e where e->>'mode' = 'keke'), 'no keke discount after the term');
  perform pg_temp.assert(bl_pol_levy_mult() = 1 and bl_pol_hygiene_mult() = 1 and bl_pol_skill_mult('fitness') = 1, 'no policy effect after the term');
  perform pg_temp.assert(not exists (select 1 from election_cycles where status in ('registration', 'campaign', 'voting')), 'a cancelled election never restarts by itself');
  raise notice 'ok 12: term end';
end $$;

-- ---------- 13. auto cycle after a closed one; auto off; admin windows ----------
do $$
declare v jsonb; c election_cycles; n int;
begin
  perform pg_temp.login(pg_temp.u('adm'));
  v := admin_pol_start(1, 1, 1, 1);
  select * into c from election_cycles where id = (v->>'id')::bigint;
  perform pg_temp.assert(c.camp_start - c.reg_start = interval '1 hour' and c.term_days = 1, 'admin can override the windows for one election');
  perform admin_pol_advance(); perform admin_pol_advance(); perform admin_pol_advance();
  perform pg_temp.assert((select status from election_cycles where id = c.id) = 'closed', 'closed with no candidates (nothing to fill)');
  perform pg_temp.login(pg_temp.u('v1'));
  v := pol_status();
  perform pg_temp.assert(v->'cycle'->>'status' = 'registration' and (select created_by from election_cycles where id = (v->'cycle'->>'id')::bigint) is null, 'a closed election is followed by one that starts itself');
  perform pg_temp.login(pg_temp.u('adm'));
  perform admin_pol_cancel('stop the auto one');
  perform pg_temp.cfg('pol.auto_cycle', 'false');
  v := admin_pol_start(1, 1, 1, 1);
  perform admin_pol_advance(); perform admin_pol_advance(); perform admin_pol_advance();
  perform pg_temp.login(pg_temp.u('v1'));
  perform pg_temp.assert(pol_status()->'cycle' = 'null'::jsonb and pol_status()->>'next_cycle_at' is null, 'auto off: nothing starts by itself and no date is promised');
  perform pg_temp.cfg('pol.auto_cycle', 'true');
  raise notice 'ok 13: auto cycle';
end $$;

-- ---------- 14. switch off, and removing a Governor ends the Commissioners ----------
do $$
declare v jsonb; gid bigint; cid bigint;
begin
  perform pg_temp.login(pg_temp.u('adm'));
  -- a clean slate: cancel whatever the auto cycle started
  begin perform admin_pol_cancel('clean slate'); exception when others then null; end;
  perform pg_temp.cfg('pol.auto_cycle', 'false');
  insert into office_holders (office_id, user_id, status, term_start, term_end, paid_through, policy_id) values ('governor', pg_temp.u('v1'), 'active', bl_now(), bl_now() + interval '14 days', bl_now(), 'levy_holiday') returning id into gid;
  insert into office_holders (office_id, user_id, appointed_by, status, term_start, term_end, paid_through) values ('commissioner_security', pg_temp.u('v2'), pg_temp.u('v1'), 'active', bl_now(), bl_now() + interval '14 days', bl_now()) returning id into cid;
  perform pg_temp.assert(bl_pol_levy_mult() = 0.75 and bl_pol_title(pg_temp.u('v1')) = 'Gov.', 'a seated Governor with a policy');
  perform pg_temp.cfg('pol.enabled', 'false');
  perform pg_temp.assert(bl_pol_levy_mult() = 1 and bl_pol_title(pg_temp.u('v1')) is null and not bl_pol_poll_open(), 'switched off: no policy effect, no title');
  perform pg_temp.login(pg_temp.u('v3'));
  perform pg_temp.assert(pg_temp.hint_of('select pol_declare(''councillor'', null, ''Light for every street in Uselu'', null)') = 'disabled', 'declare refused');
  perform pg_temp.assert(pg_temp.hint_of('select pol_vote(1)') = 'disabled' and pg_temp.hint_of('select pol_rally()') = 'disabled' and pg_temp.hint_of('select pol_party_create(''Off Front'', ''OFF'', ''#336699'')') = 'disabled', 'vote, rally and party refused');
  perform pg_temp.assert(not (pol_status()->>'enabled')::boolean, 'status says it is off');
  perform pg_temp.login(pg_temp.u('adm'));
  perform pg_temp.assert(pg_temp.hint_of('select admin_pol_start()') = 'disabled', 'admin cannot start an election while it is off');
  perform pg_temp.cfg('pol.enabled', 'true');
  -- the Governor is removed: the Commissioners go with them
  v := admin_pol_remove_holder(gid, 'Test removal');
  perform pg_temp.assert((select status from office_holders where id = gid) = 'removed' and (select status from office_holders where id = cid) = 'ended', 'removing a Governor ends the Commissioners');
  perform pg_temp.assert(bl_pol_levy_mult() = 1, 'and the policy with them');
  perform pg_temp.cfg('pol.auto_cycle', 'true');
  raise notice 'ok 14: switch off, removal';
  raise notice 'ALL POLITICS TESTS PASSED';
end $$;
