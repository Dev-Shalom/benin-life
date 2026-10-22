-- Godfather ticket (docs/POLITICS.md "Godfather ticket"): a paid bypass of the election requirements.
--
-- A player who fails the requirements to run for Councillor / Chairman / Governor can buy a ticket when declaring (on top of the
-- normal fee). It waives account age, Charisma, education / career and the clean-record (EFCC) rule. It does NOT waive: jail, a ban,
-- the Councillor ward rule, one candidacy per election, race caps, promise moderation or the fee. Bad sides: (1) a public tag on the
-- candidate card and the ballot, (2) a SECRET EFCC probe rolled at declare time (table pol_ticket_probes, no client access) that the
-- lazy clock resolves during the campaign window: caught = disqualified, no refund; cleared = an alert, (3) vote-buying reports flag
-- the candidate for admin faster (pol.ticket_report_flag_count).
--
--   1. offices.ticket_price (nullable = no ticket), seeded once; pol_candidates.ticket_paid; the secret probe table (RLS, no policies)
--   2. Settings pol.ticket_enabled / pol.ticket_probe_pct / pol.ticket_report_flag_count
--   3. Ledger reason godfather_ticket: a pure sink, never earned (bl_earn_reasons), label, Admin -> Economy category
--   4. Helpers: bl_pol_ticket_info (checklist), bl_pol_ticket_resolve (the probes, called by the clock)
--   5. pol_declare(..., p_ticket) (old 4-argument signature dropped), pol_withdraw drops the probe
--   6. Live functions patched with guarded replaces: bl_pol_tick, bl_pol_cand_json, pol_ballot, pol_status, admin_pol_overview,
--      admin_pol_cancel, bl_ledger_label, bl_econ_category, bl_earn_reasons, bl_admin_table_spec
--
-- Idempotent. Live functions are patched ONLY through a guarded replace on pg_get_functiondef (raises when the marker is missing,
-- skips when already applied; create or replace keeps the grants). Existing candidates simply have no ticket.

create or replace function pg_temp.gt_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n = 0 then raise exception 'godfather_ticket: % : marker not found: %', p_sig, left(p_old, 80); end if;
  if v_n > 1 then raise exception 'godfather_ticket: % : marker not unique (% times): %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Tables and columns
-- ---------------------------------------------------------------------------------------------
-- the price per office (null = no ticket for that office); seeded only when the column is first added so an admin edit is never undone
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'offices' and column_name = 'ticket_price') then
    alter table public.offices add column ticket_price bigint check (ticket_price is null or ticket_price >= 0);
    update public.offices set ticket_price = 10000000 where id = 'councillor';
    update public.offices set ticket_price = 20000000 where id = 'chairman';
    update public.offices set ticket_price = 50000000 where id = 'governor';
  end if;
end $$;

-- what the candidate paid for a ticket (0 = none). The public tag is ticket_paid > 0.
alter table public.pol_candidates add column if not exists ticket_paid bigint not null default 0;

-- the secret EFCC probe of a ticket candidate: rolled at declare time, resolved by the clock. Never readable by a client.
create table if not exists public.pol_ticket_probes (
  candidate_id bigint primary key references public.pol_candidates(id) on delete cascade,
  cycle_id     bigint not null references public.election_cycles(id) on delete cascade,
  catch        boolean not null,                      -- the secret roll
  probe_at     timestamptz not null,                  -- when the clock looks into it
  outcome      text check (outcome in ('caught', 'cleared', 'dropped')),
  resolved_at  timestamptz
);
create index if not exists pol_ticket_probes_due_idx on public.pol_ticket_probes (probe_at) where outcome is null;
create index if not exists pol_ticket_probes_cycle_idx on public.pol_ticket_probes (cycle_id);
alter table public.pol_ticket_probes enable row level security;
revoke all on public.pol_ticket_probes from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 2. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('pol.ticket_enabled', 'true', 'politics', 'Godfather ticket on',
 'Godfather ticket (docs/POLITICS.md): a player who fails the requirements can pay a big fee (price per office: Content -> Offices) on top of the candidacy fee to run anyway. Off = nobody can buy one (existing tickets stay).', 'bool', null, null),
('pol.ticket_probe_pct', '25', 'politics', 'Godfather ticket: EFCC catch chance (%)',
 'Godfather ticket: the chance (rolled secretly when the candidate declares) that EFCC looks into a ticket and catches the candidate at a random time in the campaign window. Caught = disqualified, ticket and fee not refunded.', 'percent', 0, 100),
('pol.ticket_report_flag_count', '1', 'politics', 'Godfather ticket: reports that flag a candidate',
 'Godfather ticket: a ticket candidate with this many open vote-buying reports is highlighted in Admin -> Elections (everybody else uses "Reports that flag a candidate").', 'number', 1, 100)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. Helpers (private)
-- ---------------------------------------------------------------------------------------------
-- the ticket view of an office for a player: price, whether the ticket covers every failing item, and whether anything fails at all
create or replace function public.bl_pol_ticket_info(p_uid uuid, o public.offices) returns jsonb
language plpgsql stable set search_path = public as $$
declare v_req jsonb; v_fail int; v_hard int; v_on boolean := bl_pol_flag('pol.ticket_enabled', true) and o.elected and o.ticket_price is not null;
begin
  if not v_on then return jsonb_build_object('price', null, 'available', false, 'needed', false); end if;
  v_req := bl_pol_requirements(p_uid, o);
  select count(*) filter (where not (c->>'ok')::boolean),
         count(*) filter (where not (c->>'ok')::boolean and (c->>'key') not in ('account_young', 'efcc_record', 'charisma_low', 'qualification'))
    into v_fail, v_hard from jsonb_array_elements(v_req->'checks') c;
  return jsonb_build_object('price', o.ticket_price, 'available', v_fail > 0 and v_hard = 0, 'needed', v_fail > 0);
end $$;

-- resolve every ticket probe whose time has passed (called by the clock, before a closed cycle is counted)
create or replace function public.bl_pol_ticket_resolve() returns void
language plpgsql set search_path = public as $$
declare v_now timestamptz := bl_now(); r record; k pol_candidates;
begin
  for r in select p.candidate_id, p.catch from pol_ticket_probes p where p.outcome is null and p.probe_at <= v_now order by p.probe_at, p.candidate_id limit 100 for update skip locked loop
    select * into k from pol_candidates where id = r.candidate_id for update;
    if not found or k.status <> 'declared' or not exists (select 1 from election_cycles e where e.id = k.cycle_id and e.status in ('registration', 'campaign', 'voting')) then
      update pol_ticket_probes set outcome = 'dropped', resolved_at = v_now where candidate_id = r.candidate_id;
    elsif r.catch then
      -- the same path as an admin disqualification: votes voided, backing gone, reports reviewed. No refund.
      delete from pol_votes where candidate_id = k.id;
      delete from pol_backing where candidate_id = k.id;
      update pol_candidates set status = 'disqualified', dq_reason = 'EFCC probe: godfather ticket' where id = k.id;
      update pol_reports set status = 'reviewed' where candidate_id = k.id and status = 'open';
      update pol_ticket_probes set outcome = 'caught', resolved_at = v_now where candidate_id = r.candidate_id;
      perform bl_event(k.user_id, 'pol_disqualified', 'EFCC caught your Godfather ticket',
        'EFCC looked into your ticket and found the trick. You are disqualified. The ticket and the fee are not refunded.', jsonb_build_object('cycle', k.cycle_id, 'ticket', true));
    else
      update pol_ticket_probes set outcome = 'cleared', resolved_at = v_now where candidate_id = r.candidate_id;
      perform bl_event(k.user_id, 'pol_ticket_cleared', 'EFCC looked into your ticket',
        'EFCC looked into your ticket and found nothing... this time.', jsonb_build_object('cycle', k.cycle_id, 'ticket', true));
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. pol_declare with a ticket (new trailing parameter; the old signature goes)
-- ---------------------------------------------------------------------------------------------
drop function if exists public.pol_declare(text, text, text, text);
create or replace function public.pol_declare(p_office text, p_ward text default null, p_promise text default '', p_party text default null, p_ticket boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); c election_cycles; o offices; w wards; me profiles; v_req jsonb; v_slot text; v_promise text; v_n int; v_id bigint; v_home text;
  v_ticket bigint := 0; v_bad jsonb; v_from timestamptz; v_pct numeric;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into c from bl_pol_open_cycle();
  if c.id is null or c.status <> 'registration' then
    raise exception 'Candidate registration is not open right now.' using errcode = 'P0001', hint = 'registration_closed';
  end if;
  select * into me from profiles where id = v_uid for update;
  select * into o from offices where id = p_office and active and elected;
  if not found then
    raise exception 'You cannot run for that office.' using errcode = 'P0001', hint = 'bad_office';
  end if;
  if o.ward_scoped then
    v_home := bl_pol_ward_of(v_uid);
    select * into w from wards where id = coalesce(nullif(p_ward, ''), v_home) and active;
    if not found or w.id <> v_home then
      raise exception 'A Councillor runs in the ward where they live (%). Move house to run somewhere else.', (select name from wards where id = v_home) using errcode = 'P0001', hint = 'wrong_ward';
    end if;
  end if;
  v_slot := bl_pol_slot(o.id, w.id);
  if exists (select 1 from pol_candidates where cycle_id = c.id and user_id = v_uid and status = 'declared') then
    raise exception 'You are already a candidate in this election. Withdraw first to change your race.' using errcode = 'P0001', hint = 'already_candidate';
  end if;
  v_req := bl_pol_requirements(v_uid, o);
  if coalesce(p_ticket, false) then
    if not bl_pol_flag('pol.ticket_enabled', true) or o.ticket_price is null then
      raise exception 'There is no Godfather ticket for %.', o.name using errcode = 'P0001', hint = 'ticket_off';
    end if;
    if (v_req->>'ok')::boolean then
      raise exception 'You don''t need a ticket. You already meet every requirement for %.', o.name using errcode = 'P0001', hint = 'ticket_not_needed';
    end if;
    -- a ticket waives age, Charisma, education / career and the clean record. Jail (and anything else) still stops you.
    select c2 into v_bad from jsonb_array_elements(v_req->'checks') c2
     where not (c2->>'ok')::boolean and (c2->>'key') not in ('account_young', 'efcc_record', 'charisma_low', 'qualification') limit 1;
    if v_bad is not null then
      raise exception '%', v_bad->>'message' using errcode = 'P0001', hint = v_bad->>'key';
    end if;
    v_ticket := o.ticket_price;
  elsif not (v_req->>'ok')::boolean then
    raise exception '%', v_req->>'message' using errcode = 'P0001', hint = v_req->>'hint';
  end if;
  v_promise := bl_pol_moderate(p_promise, 10, bl_pol_num('pol.promise_max_len', 140)::int, 'promise');
  if p_party is not null and btrim(p_party) <> '' and not exists (select 1 from parties where id = btrim(p_party) and active) then
    raise exception 'Pick a party from the list, or run as an independent.' using errcode = 'P0001', hint = 'bad_party';
  end if;
  select count(*) into v_n from pol_candidates where cycle_id = c.id and slot_key = v_slot and status = 'declared';
  if v_n >= bl_pol_num('pol.max_candidates_per_slot', 8) then
    raise exception 'That race is full (% candidates).', v_n using errcode = 'P0001', hint = 'race_full';
  end if;
  -- fee + ticket together, all or nothing: the same pay rule (bank first, then cash)
  if v_ticket > 0 and me.cash + greatest(me.bank, 0) < o.fee + v_ticket then
    raise exception 'Not enough money. The fee and the ticket cost % together and you have % (bank % + cash %).', bl_naira(o.fee + v_ticket),
      bl_naira(me.cash + greatest(me.bank, 0)), bl_naira(greatest(me.bank, 0)), bl_naira(me.cash) using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  perform bl_pol_pay(v_uid, o.fee, 'campaign_fee', jsonb_build_object('label', 'Candidacy fee: ' || o.name, 'office', o.id));
  if v_ticket > 0 then
    perform bl_pol_pay(v_uid, v_ticket, 'godfather_ticket', jsonb_build_object('label', 'Godfather ticket: ' || o.name, 'office', o.id));
  end if;
  insert into pol_candidates (cycle_id, office_id, ward_id, slot_key, user_id, party_id, promise, fee_paid, ticket_paid, declared_at)
  values (c.id, o.id, w.id, v_slot, v_uid, nullif(btrim(coalesce(p_party, '')), ''), v_promise, o.fee, v_ticket, bl_now()) returning id into v_id;
  if v_ticket > 0 then
    -- the secret probe: does EFCC catch them, and when (any moment of the campaign window, from now on)
    v_pct := least(greatest(bl_pol_num('pol.ticket_probe_pct', 25), 0), 100);
    v_from := greatest(bl_now(), c.camp_start);
    insert into pol_ticket_probes (candidate_id, cycle_id, catch, probe_at)
    values (v_id, c.id, random() * 100 < v_pct, v_from + (c.vote_start - v_from) * random());
  end if;
  perform bl_skill_award(v_uid, 'politics', 'declare');
  return jsonb_build_object('id', v_id, 'message', 'You are a candidate for ' || o.name || coalesce(' in ' || w.name, '') || '. Campaign season starts when registration closes.'
    || case when v_ticket > 0 then ' Your Godfather ticket is on your card for everybody to see.' else '' end);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Patches to live functions (guarded)
-- ---------------------------------------------------------------------------------------------
-- the clock resolves due probes first, so a probe is settled before votes are counted at the close
select pg_temp.gt_patch('public.bl_pol_tick()',
  E'  if not bl_pol_on() then return; end if;\n  loop\n',
  E'  if not bl_pol_on() then return; end if;\n  perform bl_pol_ticket_resolve();\n  loop\n',
  'bl_pol_ticket_resolve');

-- withdrawing drops the probe (nothing is refunded)
select pg_temp.gt_patch('public.pol_withdraw()',
  E'  update pol_candidates set status = ''withdrawn'' where id = k.id;\n',
  E'  update pol_candidates set status = ''withdrawn'' where id = k.id;\n  delete from pol_ticket_probes where candidate_id = k.id;\n',
  'pol_ticket_probes');

-- the public tag on cards (pol_candidates, my candidacy) and on the ballot
select pg_temp.gt_patch('public.bl_pol_cand_json(public.pol_candidates, uuid, numeric)',
  E'''mine'', k.user_id = p_viewer,',
  E'''ticket'', k.ticket_paid > 0, ''mine'', k.user_id = p_viewer,',
  '''ticket'', k.ticket_paid');
select pg_temp.gt_patch('public.pol_ballot()',
  E'''promise'', k.promise, ''title'', bl_pol_title(k.user_id))',
  E'''promise'', k.promise, ''title'', bl_pol_title(k.user_id), ''ticket'', k.ticket_paid > 0)',
  '''ticket'', k.ticket_paid');

-- the checklist per office: the ticket price and whether it would cover what fails
select pg_temp.gt_patch('public.pol_status()',
  E'''requirements'', case when x.elected then bl_pol_requirements(v_uid, x) end)',
  E'''requirements'', case when x.elected then bl_pol_requirements(v_uid, x) end,\n                ''ticket_price'', case when x.elected then bl_pol_ticket_info(v_uid, x)->''price'' end,\n                ''ticket_available'', x.elected and coalesce((bl_pol_ticket_info(v_uid, x)->>''available'')::boolean, false))',
  'ticket_available');

-- admin: the tag and a lower flag threshold for ticket candidates (the probe itself is never shown)
select pg_temp.gt_patch('public.admin_pol_overview()',
  E'v_flag int := bl_pol_num(''pol.report_flag_count'', 3)::int;',
  E'v_flag int := bl_pol_num(''pol.report_flag_count'', 3)::int; v_tflag int := bl_pol_num(''pol.ticket_report_flag_count'', 1)::int;',
  'v_tflag');
select pg_temp.gt_patch('public.admin_pol_overview()',
  E'''flagged'', (select count(*) from pol_reports r where r.candidate_id = k.id and r.status = ''open'') >= v_flag,',
  E'''flagged'', (select count(*) from pol_reports r where r.candidate_id = k.id and r.status = ''open'') >= case when k.ticket_paid > 0 then v_tflag else v_flag end,',
  'then v_tflag else');
select pg_temp.gt_patch('public.admin_pol_overview()',
  E'''fee_paid'', k.fee_paid,',
  E'''fee_paid'', k.fee_paid, ''ticket'', k.ticket_paid > 0, ''ticket_paid'', k.ticket_paid,',
  '''ticket_paid'', k.ticket_paid');

-- admin cancel: the ticket comes back too (a credit, like the fee)
select pg_temp.gt_patch('public.admin_pol_cancel(text)',
  'select k.id, k.user_id, k.fee_paid from pol_candidates k',
  'select k.id, k.user_id, k.fee_paid, k.ticket_paid from pol_candidates k',
  'k.ticket_paid');
select pg_temp.gt_patch('public.admin_pol_cancel(text)',
  E'    perform bl_event(r.user_id, ''pol_cancelled''',
  E'    if r.ticket_paid > 0 then\n      perform bl_add_money(r.user_id, ''bank'', r.ticket_paid, ''godfather_ticket'', jsonb_build_object(''label'', ''Godfather ticket refunded (election cancelled)'', ''refund'', true));\n    end if;\n    perform bl_event(r.user_id, ''pol_cancelled''',
  'Godfather ticket refunded');

-- ledger text, the Admin -> Economy category, and never earned
select pg_temp.gt_patch('public.bl_ledger_label(text, jsonb)',
  E'    when ''campaign_fee'' then return',
  E'    when ''godfather_ticket'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Godfather ticket'');\n    when ''campaign_fee'' then return',
  '''godfather_ticket''');
select pg_temp.gt_patch('public.bl_econ_category(text)',
  '''campaign_spend'', ''police_bail''',
  '''campaign_spend'', ''godfather_ticket'', ''police_bail''',
  '''godfather_ticket''');
select pg_temp.gt_patch('public.bl_earn_reasons()',
  '''chief_title'']',
  '''chief_title'', ''godfather_ticket'']',
  '''godfather_ticket''');

-- Admin -> Content -> Offices: the price column (empty = no ticket)
select pg_temp.gt_patch('public.bl_admin_table_spec(text)',
  '"fee":"money","min_charisma":"int","min_account_days":"num","cert_any":"arr"',
  '"fee":"money","ticket_price":"int_null","min_charisma":"int","min_account_days":"num","cert_any":"arr"',
  '"ticket_price":"int_null"');

-- ---------------------------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'bl\_pol\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
  revoke all on function public.pol_declare(text, text, text, text, boolean) from public, anon;
  grant execute on function public.pol_declare(text, text, text, text, boolean) to authenticated, service_role;
end $$;

notify pgrst, 'reload schema';
