-- The Court (docs/COURT.md): High Court, Benin (and a small-claims Customary Court tier). Players sue players over things the game RECORDED
-- (a pickpocket, a tenant who left owing rent, an unfair eviction, an overcharge on the Market), hire real players as lawyers, and a judge
-- (a player holding a court_judge_* industry office) hears both sides in a live hearing with a bounded public gallery. If no judge rules in
-- time the AUTOMATIC ruling follows the recorded evidence, so a victim always gets an outcome.
--   1. Settings `court.*` (category court). A Law course + certificate in the School (the lawyer requirement).
--   2. Judges: four industry offices (court_judge_1..4, badge "Hon. Justice") in the existing ind_offices table: appointment, salary, badge,
--      term, inactivity and removal are the existing industry-office code. No parallel system.
--   3. Tables (no foreign keys to profiles): court_lawyers, court_cases, court_hires, court_statements, court_gallery, court_debts.
--   4. Private helpers: evidence (what the game recorded), tick (lazy, no cron), execute (verdict money), debt collection from income.
--   5. Guarded patches (pg_temp.ct_patch): bl_add_money (court debt garnish after the tax garnish), bl_earn_reasons (court money is never earned),
--      bl_ledger_label, bl_push_on_event (court alerts go out as pushes in the existing "events" category).
-- Player and admin RPCs are in 20261111000200_court_rpcs.sql.
-- Idempotent: tables `if not exists`, seeds `on conflict do nothing`, functions `create or replace`. No loop over players anywhere.

create or replace function pg_temp.ct_patch(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n <> 1 then
    raise notice 'court: % : marker found % times, patch skipped: %', p_sig, v_n, left(p_marker, 80);
    return;
  end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('court.enabled', 'true', 'court', 'Court open', 'The switch. Off: nobody can file, hire, post or rule. Cases already filed still get their automatic ruling.', 'bool', null, null),
('court.filing_fee', '5000', 'court', 'Filing fee, High Court', 'Paid to file a case worth more than the Customary Court limit. A sink (destroyed). Refunded when the verdict is guilty; lost when not guilty.', 'naira', 0, 10000000),
('court.customary_fee', '1500', 'court', 'Filing fee, Customary Court', 'Paid to file a small claim (up to the Customary Court limit). Same refund rule.', 'naira', 0, 10000000),
('court.customary_max', '100000', 'court', 'Customary Court limit', 'A claim up to this amount goes to the Customary Court (small claims). Bigger claims go to the High Court.', 'naira', 0, 1000000000),
('court.min_claim', '500', 'court', 'Smallest claim', 'The court will not hear a case where the recorded loss is below this.', 'naira', 0, 100000000),
('court.lookback_hours', '72', 'court', 'Case look-back (hours)', 'How old a recorded event can be and still be filed.', 'number', 1, 720),
('court.hearing_delay_minutes', '30', 'court', 'Hearing delay (real minutes)', 'The hearing starts this long after filing. Lawyers must accept before it starts.', 'minutes', 1, 1440),
('court.ruling_window_minutes', '60', 'court', 'Ruling window (real minutes)', 'The judge has this long after the hearing starts. Then the automatic ruling applies.', 'minutes', 1, 2880),
('court.min_hearing_minutes', '2', 'court', 'Hearing minimum (real minutes)', 'A judge may rule only after the hearing has been live this long, so both sides can speak. 0 = at once.', 'minutes', 0, 120),
('court.gallery_size', '30', 'court', 'Gallery size', 'How many players can watch one hearing. Parties, lawyers and the judge do not use a seat.', 'number', 0, 500),
('court.gallery_idle_minutes', '10', 'court', 'Gallery idle limit (minutes)', 'A watcher who stops checking in loses the seat after this long.', 'minutes', 1, 240),
('court.statement_max_len', '240', 'court', 'Statement length', 'Longest statement (characters). Cleaned and masked like chat.', 'number', 20, 1000),
('court.statements_per_side', '8', 'court', 'Statements per side', 'Each side (party and lawyer together) may post this many statements in one hearing.', 'number', 1, 50),
('court.statement_gap_seconds', '3', 'court', 'Statement gap (seconds)', 'Minimum wait between two statements by the same person.', 'number', 0, 300),
('court.fine_pct', '20', 'court', 'Fine (% of the claim)', 'A guilty defendant also pays this share of the claim as a fine. A sink (destroyed).', 'percent', 0, 200),
('court.fine_min', '2000', 'court', 'Smallest fine', 'The fine is never below this.', 'naira', 0, 100000000),
('court.cut_pct', '5', 'court', 'Court cut (% of a lawyer fee)', 'The court keeps this share of every lawyer fee. A sink (destroyed).', 'percent', 0, 50),
('court.cred_hit', '5', 'court', 'Street cred lost when guilty', 'Taken from the defendant on a guilty verdict.', 'number', 0, 100),
('court.debt_enabled', 'true', 'court', 'Court debt', 'A guilty defendant who cannot pay in full owes the rest as court debt, taken from their future income. Off: the rest is forgiven.', 'bool', null, null),
('court.debt_collect_pct', '30', 'court', 'Debt collection (% of income)', 'Share of each earning (salary, hustle and the other earned reasons) taken for court debt until it is paid.', 'percent', 1, 100),
('court.jail_after_verdicts', '2', 'court', 'Jail on the Nth guilty verdict', 'The Nth guilty verdict within the repeat window sends the defendant to jail through the Police case system. 1 = every guilty verdict.', 'number', 1, 20),
('court.repeat_days', '30', 'court', 'Repeat-offender window (days)', 'Guilty verdicts older than this do not count as repeats.', 'number', 1, 365),
('court.jail_base_seconds', '60', 'court', 'Jail time (seconds)', 'Jail time for the first jail sentence. Each further guilty verdict adds this much again. Capped by the Police case maximum.', 'number', 1, 86400),
('court.lawyer_min_fee', '2000', 'court', 'Lowest lawyer fee', 'A lawyer cannot ask for less than this per case.', 'naira', 0, 100000000),
('court.lawyer_max_fee', '2000000', 'court', 'Highest lawyer fee', 'A lawyer cannot ask for more than this per case.', 'naira', 0, 1000000000),
('court.lawyer_min_account_days', '2', 'court', 'Lawyer: account age (days)', 'A player must be this old to register as a lawyer.', 'number', 0, 365),
('court.lawyer_cert', '"law"', 'court', 'Lawyer: certificate', 'School certificate id a lawyer must hold (the Law and Advocacy course gives "law"). Empty = no certificate needed.', 'text', null, null),
('court.lawyer_online_minutes', '10', 'court', 'Lawyer "available now" (minutes)', 'A lawyer counts as available now when they switched availability on and were seen within this long.', 'minutes', 1, 1440),
('court.lawyer_max_open', '5', 'court', 'Lawyer: open cases at once', 'A lawyer cannot accept more than this many live cases.', 'number', 1, 50),
('court.hire_attempts', '3', 'court', 'Hire attempts per side', 'How many lawyer requests one side can send for one case (declined and expired ones count).', 'number', 1, 20),
('court.rank_advocate_wins', '5', 'court', 'Rank: Advocate (wins)', 'Wins needed for the Advocate rank. Junior Lawyer is the starting rank.', 'number', 1, 10000),
('court.rank_barrister_wins', '15', 'court', 'Rank: Barrister (wins)', 'Wins needed for the Barrister rank.', 'number', 1, 10000),
('court.rank_senior_wins', '40', 'court', 'Rank: Senior Advocate (wins)', 'Wins needed for the top rank.', 'number', 1, 10000),
('court.min_account_hours', '12', 'court', 'Account age to file (hours)', 'A brand-new account cannot file or be sued by a fresh alt. Both sides must be at least this old.', 'number', 0, 720),
('court.file_cooldown_minutes', '5', 'court', 'Filing cooldown (minutes)', 'One filing per player per this long.', 'minutes', 0, 1440),
('court.max_open_cases', '3', 'court', 'Open cases as plaintiff', 'A player can have this many undecided cases they filed.', 'number', 1, 50),
('court.max_per_day', '5', 'court', 'Filings per day', 'At most this many filings per player per Benin day.', 'number', 1, 100),
('court.eviction_protect_days', '7', 'court', 'Unfair eviction: protected stay (days)', 'A tenant given notice within this many days of moving in can sue the landlord.', 'number', 1, 90),
('court.eviction_comp_weeks', '1', 'court', 'Unfair eviction: compensation (weeks of rent)', 'The landlord pays this many weeks of the rent recorded at move-in.', 'number', 1, 12),
('court.type_pickpocket_enabled', 'true', 'court', 'Case type: pickpocket', 'Players can sue the thief of a recorded pickpocket.', 'bool', null, null),
('court.type_rent_owed_enabled', 'true', 'court', 'Case type: rent owed', 'Landlords can sue a tenant who was moved out owing rent.', 'bool', null, null),
('court.type_eviction_enabled', 'true', 'court', 'Case type: unfair eviction', 'Tenants can sue a landlord who gave notice soon after move-in.', 'bool', null, null),
('court.type_overcharge_enabled', 'true', 'court', 'Case type: Market overcharge', 'Buyers can sue the seller of a Market trade the game flagged as far above value.', 'bool', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. School: the Law and Advocacy course (the lawyer requirement) and the judges' offices
-- ---------------------------------------------------------------------------------------------
insert into public.certificates (id, name, icon, blurb, pay_bonus_pct, bonus_tracks, bonus_hustles, sort) values
('law', 'Law and Advocacy', '⚖️', 'Court procedure, evidence and how to speak before a judge. You can register as a lawyer at the High Court, Benin.', 0, '{}', '{}', 110)
on conflict (id) do nothing;

insert into public.courses (id, name, icon, blurb, where_text, location_ids, scenes, fee, classes, class_game_minutes, class_seconds, cooldown_days,
  energy_cost, effects, hour_from, hour_to, skill_id, xp_per_class, prereq_cert, prereq_skill, prereq_skill_level, cert_id, exam, exam_base_pct,
  exam_per_level_pct, exam_text, modules, sort) values
('law_advocacy', 'Law and Advocacy', '⚖️', 'Court procedure, evidence and speaking before a judge. Pass it to register as a lawyer at the High Court.',
 'UNIBEN Ugbowo Campus (lecture hall)', '{uniben}', '{}', 40000, 5, 120, 35, 1, 12, '{"stress":4}', 8, 17, 'charisma', 8, null, null, 1, 'law', true, 50, 7,
 'Moot court: the better your Charisma, the better your chance.', '{}', 110)
on conflict (id) do nothing;

insert into public.ind_offices (id, name, industry, title, icon, blurb, salary_per_day, term_days, min_account_days, min_level, election_enabled, seats,
  max_changes_per_day, max_total_drift_pct, frozen, sort, active) values
('court_judge_1', 'High Court Judge I', 'Law and justice', 'Hon. Justice', '⚖️', 'Hears cases at the High Court, Benin, and rules on them. The court sets the rules, not the judge.', 1500000, 14, 5, 0, false, 1, 0, 0, false, 90, true),
('court_judge_2', 'High Court Judge II', 'Law and justice', 'Hon. Justice', '⚖️', 'Hears cases at the High Court, Benin, and rules on them. The court sets the rules, not the judge.', 1500000, 14, 5, 0, false, 1, 0, 0, false, 91, true),
('court_judge_3', 'High Court Judge III', 'Law and justice', 'Hon. Justice', '⚖️', 'Hears cases at the High Court, Benin, and rules on them. The court sets the rules, not the judge.', 1500000, 14, 5, 0, false, 1, 0, 0, false, 92, true),
('court_judge_4', 'High Court Judge IV', 'Law and justice', 'Hon. Justice', '⚖️', 'Hears cases at the High Court, Benin, and rules on them. The court sets the rules, not the judge.', 1500000, 14, 5, 0, false, 1, 0, 0, false, 93, true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. Tables (user ids are plain uuids: NO foreign key to profiles)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.court_lawyers (
  user_id       uuid primary key,
  fee           bigint not null check (fee >= 0),
  bio           text not null default '',
  available     boolean not null default true,
  retired       boolean not null default false,
  wins          int not null default 0 check (wins >= 0),
  losses        int not null default 0 check (losses >= 0),
  banned        boolean not null default false,
  ban_reason    text,
  registered_at timestamptz not null default now()
);

create table if not exists public.court_cases (
  id               bigint generated by default as identity primary key,
  case_no          text not null,
  tier             text not null check (tier in ('high', 'customary')),
  kind             text not null check (kind in ('pickpocket', 'rent_owed', 'eviction', 'overcharge')),
  event_ref        text not null,
  title            text not null,
  evidence         jsonb not null default '{}'::jsonb,
  plaintiff_id     uuid not null,
  defendant_id     uuid not null,
  claim            bigint not null check (claim >= 0),
  filing_fee       bigint not null default 0 check (filing_fee >= 0),
  status           text not null default 'scheduled' check (status in ('scheduled', 'ruled', 'dismissed')),
  judge_id         uuid,
  hearing_at       timestamptz not null,
  ruling_deadline  timestamptz not null,
  verdict          text check (verdict in ('guilty', 'not_guilty')),
  verdict_by       text check (verdict_by in ('judge', 'auto', 'admin')),
  verdict_note     text not null default '',
  restitution_paid bigint not null default 0,
  restitution_debt bigint not null default 0,
  fine             bigint not null default 0,
  fine_paid        bigint not null default 0,
  cred_hit         int not null default 0,
  jail_seconds     int not null default 0,
  overridden       boolean not null default false,
  created_at       timestamptz not null default now(),
  ruled_at         timestamptz
);
create unique index if not exists court_cases_case_no_uq on public.court_cases (case_no);
-- ONE case per recorded event (a dismissed case frees the event)
create unique index if not exists court_cases_event_uq on public.court_cases (kind, event_ref) where status <> 'dismissed';
create index if not exists court_cases_plaintiff_idx on public.court_cases (plaintiff_id, id desc);
create index if not exists court_cases_defendant_idx on public.court_cases (defendant_id, id desc);
create index if not exists court_cases_judge_idx on public.court_cases (judge_id, status);
create index if not exists court_cases_due_idx on public.court_cases (hearing_at) where status = 'scheduled';
create index if not exists court_cases_live_idx on public.court_cases (status, hearing_at);

create table if not exists public.court_hires (
  id         bigint generated always as identity primary key,
  case_id    bigint not null references public.court_cases(id) on delete cascade,
  side       text not null check (side in ('plaintiff', 'defendant')),
  client_id  uuid not null,
  lawyer_id  uuid not null,
  fee        bigint not null check (fee >= 0),
  cut        bigint not null default 0,
  status     text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired', 'cancelled', 'paid', 'refunded')),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
-- one live lawyer per side; a lawyer can never hold both sides (checked in the RPC, and by this index on (case, lawyer))
create unique index if not exists court_hires_side_uq on public.court_hires (case_id, side) where status in ('pending', 'accepted', 'paid');
create unique index if not exists court_hires_lawyer_uq on public.court_hires (case_id, lawyer_id) where status in ('pending', 'accepted', 'paid');
create index if not exists court_hires_lawyer_idx on public.court_hires (lawyer_id, status);
create index if not exists court_hires_client_idx on public.court_hires (client_id, status);
create index if not exists court_hires_case_idx on public.court_hires (case_id, id);

create table if not exists public.court_statements (
  id         bigint generated always as identity primary key,
  case_id    bigint not null references public.court_cases(id) on delete cascade,
  side       text not null check (side in ('plaintiff', 'defendant', 'bench')),
  kind       text not null default 'statement' check (kind in ('statement', 'note', 'ruling')),
  author_id  uuid,
  as_lawyer  boolean not null default false,
  body       text not null,
  created_at timestamptz not null default now()
);
create index if not exists court_statements_case_idx on public.court_statements (case_id, id);

create table if not exists public.court_gallery (
  case_id   bigint not null references public.court_cases(id) on delete cascade,
  user_id   uuid not null,
  joined_at timestamptz not null default now(),
  seen_at   timestamptz not null default now(),
  primary key (case_id, user_id)
);
create index if not exists court_gallery_user_idx on public.court_gallery (user_id);

create table if not exists public.court_debts (
  id          bigint generated always as identity primary key,
  case_id     bigint not null references public.court_cases(id) on delete cascade,
  debtor_id   uuid not null,
  creditor_id uuid,                          -- null = a fine (destroyed)
  kind        text not null check (kind in ('restitution', 'fine')),
  amount      bigint not null check (amount > 0),
  owed        bigint not null check (owed >= 0),
  held        bigint not null default 0 check (held >= 0),   -- collected, waiting to be paid out to the creditor on their next call (so two player rows are never locked together)
  created_at  timestamptz not null default now(),
  settled_at  timestamptz
);
create index if not exists court_debts_debtor_idx on public.court_debts (debtor_id, id) where owed > 0;
create index if not exists court_debts_creditor_idx on public.court_debts (creditor_id) where held > 0;
create index if not exists court_debts_case_idx on public.court_debts (case_id);

alter table public.court_lawyers enable row level security;
alter table public.court_cases enable row level security;
alter table public.court_hires enable row level security;
alter table public.court_statements enable row level security;
alter table public.court_gallery enable row level security;
alter table public.court_debts enable row level security;
revoke all on table public.court_lawyers, public.court_cases, public.court_hires, public.court_statements, public.court_gallery, public.court_debts
  from public, anon, authenticated;
revoke all on sequence public.court_cases_id_seq, public.court_hires_id_seq, public.court_statements_id_seq, public.court_debts_id_seq
  from public, anon, authenticated;

-- Realtime reads statements straight from the table (one channel per hearing): the policy lets only people in the case or the gallery see a row.
-- court_can_see is NOT a bl_ helper: authenticated must be allowed to run it (the policy runs as the caller). It answers only "can I see this case".
create or replace function public.court_can_see(p_case bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (
    select 1 from court_cases c
     where c.id = p_case
       and (auth.uid() in (c.plaintiff_id, c.defendant_id) or auth.uid() = c.judge_id
            or exists (select 1 from court_hires h where h.case_id = c.id and h.lawyer_id = auth.uid() and h.status in ('accepted', 'paid'))
            or exists (select 1 from court_gallery g where g.case_id = c.id and g.user_id = auth.uid())));
$$;
revoke all on function public.court_can_see(bigint) from public, anon;
grant execute on function public.court_can_see(bigint) to authenticated, service_role;

grant select on table public.court_statements to authenticated;
drop policy if exists court_statements_read on public.court_statements;
create policy court_statements_read on public.court_statements for select to authenticated using (public.court_can_see(case_id));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'court_statements') then
    alter publication supabase_realtime add table public.court_statements;
  end if;
exception when others then
  raise notice 'court_statements not published: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. Helpers (private)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_court_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_court_on() returns boolean
language sql stable set search_path = public as $$
  select bl_pol_flag('court.enabled', true);
$$;

create or replace function public.bl_court_guard() returns void
language plpgsql stable set search_path = public as $$
begin
  if not bl_court_on() then
    raise exception 'The court is closed for now. Check back soon.' using errcode = 'P0001', hint = 'disabled';
  end if;
end $$;

create or replace function public.bl_court_person(p_uid uuid) returns jsonb
language sql stable set search_path = public as $$
  select case when p.id is null then null else jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar, 'title', bl_pol_title(p.id)) end
    from (select 1) x left join profiles p on p.id = p_uid;
$$;

create or replace function public.bl_court_rank(p_wins int) returns text
language sql stable set search_path = public as $$
  select case when p_wins >= bl_court_num('court.rank_senior_wins', 40) then 'Senior Advocate'
              when p_wins >= bl_court_num('court.rank_barrister_wins', 15) then 'Barrister'
              when p_wins >= bl_court_num('court.rank_advocate_wins', 5) then 'Advocate'
              else 'Junior Lawyer' end;
$$;

-- is this player a sitting judge (a court_judge_* office, term running, office active)?
create or replace function public.bl_court_judge_ok(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_uid is not null and bl_ind_on() and exists (
    select 1 from ind_holders h join ind_offices o on o.id = h.office_id
     where h.user_id = p_uid and h.status = 'active' and h.term_end > bl_now() and o.active and o.id like 'court\_judge\_%')
    and not exists (select 1 from profiles p where p.id = p_uid and p.banned);
$$;

create or replace function public.bl_court_year() returns text
language sql stable set search_path = public as $$
  select to_char(bl_now() at time zone 'Africa/Lagos', 'YYYY');
$$;

-- what the game RECORDED. {ok, why, defendant, claim, title, sub, at, evidence}. p_window false = skip the look-back (the automatic ruling re-checks the record).
create or replace function public.bl_court_evidence(p_me uuid, p_kind text, p_ref text, p_window boolean default true) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_since timestamptz := case when p_window then bl_now() - make_interval(secs => bl_court_num('court.lookback_hours', 72) * 3600) else '-infinity'::timestamptz end;
  v_min bigint := greatest(0, bl_court_num('court.min_claim', 500))::bigint;
  v_id bigint; a crime_attempts; e property_events; n property_events; mi property_events; pr properties; t market_trades;
  v_place text; v_owed bigint; v_kept bigint; v_claim bigint; v_land uuid; v_stay numeric; v_name text; v_tenant text;
begin
  if p_kind not in ('pickpocket', 'rent_owed', 'eviction', 'overcharge') then
    return jsonb_build_object('ok', false, 'why', 'The court cannot hear that kind of case.');
  end if;
  if not bl_pol_flag('court.type_' || p_kind || '_enabled', true) then
    return jsonb_build_object('ok', false, 'why', 'The court is not hearing that kind of case right now.');
  end if;
  begin v_id := p_ref::bigint; exception when others then
    return jsonb_build_object('ok', false, 'why', 'We have no record of that.');
  end;

  if p_kind = 'pickpocket' then
    select * into a from crime_attempts where id = v_id;
    if not found or a.victim_id <> p_me or a.status <> 'success' or a.amount <= 0 then
      return jsonb_build_object('ok', false, 'why', 'We have no record of that theft against you.');
    end if;
    if a.resolved_at < v_since then
      return jsonb_build_object('ok', false, 'why', 'That happened too long ago. The court only hears recent cases.');
    end if;
    if a.amount < v_min then return jsonb_build_object('ok', false, 'why', 'That loss is too small for the court.'); end if;
    select name into v_place from locations where id = a.location_id;
    return jsonb_build_object('ok', true, 'defendant', a.thief_id, 'claim', a.amount, 'title', 'Pickpocketed at ' || coalesce(v_place, 'a public place'),
      'sub', 'Someone took ' || bl_naira(a.amount) || ' from your pocket.', 'at', a.resolved_at,
      'evidence', jsonb_build_object('record', 'crime_attempts', 'id', a.id, 'place', v_place, 'amount', a.amount, 'at', a.resolved_at));

  elsif p_kind = 'rent_owed' then
    select * into e from property_events where id = v_id and kind = 'tenancy_ended';
    if not found or e.property_id is null then return jsonb_build_object('ok', false, 'why', 'We have no record of that tenancy.'); end if;
    select * into pr from properties where id = e.property_id;
    if not found or pr.owner_id <> p_me then return jsonb_build_object('ok', false, 'why', 'That tenancy is not on your property record.'); end if;
    if e.created_at < v_since then return jsonb_build_object('ok', false, 'why', 'That happened too long ago. The court only hears recent cases.'); end if;
    if coalesce(e.detail ->> 'why', '') not in ('owed', 'notice') then
      return jsonb_build_object('ok', false, 'why', 'That tenant did not leave owing rent.');
    end if;
    v_owed := coalesce((e.detail ->> 'owed')::bigint, 0); v_kept := coalesce((e.detail ->> 'caution_kept')::bigint, 0);
    v_claim := v_owed - v_kept;
    if v_claim < v_min then return jsonb_build_object('ok', false, 'why', 'The caution already covered the rent owed.'); end if;
    if e.user_id is null then return jsonb_build_object('ok', false, 'why', 'We cannot find that tenant.'); end if;
    v_tenant := coalesce(e.detail ->> 'tenant', '');
    return jsonb_build_object('ok', true, 'defendant', e.user_id, 'claim', v_claim, 'title', 'Rent owed on ' || bl_prop_name(pr),
      'sub', '@' || v_tenant || ' left owing ' || bl_naira(v_claim) || ' after the caution.', 'at', e.created_at,
      'evidence', jsonb_build_object('record', 'property_events', 'id', e.id, 'property', bl_prop_name(pr), 'owed', v_owed, 'caution_kept', v_kept, 'unpaid', v_claim, 'at', e.created_at));

  elsif p_kind = 'eviction' then
    select * into e from property_events where id = v_id and kind = 'tenancy_ended';
    if not found or e.property_id is null or e.user_id <> p_me then return jsonb_build_object('ok', false, 'why', 'We have no record of that tenancy for you.'); end if;
    if e.created_at < v_since then return jsonb_build_object('ok', false, 'why', 'That happened too long ago. The court only hears recent cases.'); end if;
    if coalesce(e.detail ->> 'why', '') <> 'notice' or coalesce((e.detail ->> 'owed')::bigint, 0) > 0 then
      return jsonb_build_object('ok', false, 'why', 'You were not moved out by notice, or you owed rent.');
    end if;
    select * into n from property_events where property_id = e.property_id and kind = 'notice_given' and id < e.id order by id desc limit 1;
    select * into mi from property_events where property_id = e.property_id and kind = 'tenant_moved_in' and user_id = p_me and id < e.id order by id desc limit 1;
    if n.id is null or mi.id is null then return jsonb_build_object('ok', false, 'why', 'The record of the notice is incomplete.'); end if;
    v_stay := extract(epoch from (e.created_at - mi.created_at)) / 86400.0;
    if v_stay >= bl_court_num('court.eviction_protect_days', 7) then
      return jsonb_build_object('ok', false, 'why', 'You had a fair stay before the notice. That is not an unfair eviction.');
    end if;
    v_claim := greatest(0, round(bl_court_num('court.eviction_comp_weeks', 1) * coalesce((mi.detail ->> 'rent')::numeric, 0)))::bigint;
    if v_claim < v_min then return jsonb_build_object('ok', false, 'why', 'There is no rent on record to claim.'); end if;
    if n.user_id is null or n.user_id = p_me then return jsonb_build_object('ok', false, 'why', 'We cannot find the landlord.'); end if;
    return jsonb_build_object('ok', true, 'defendant', n.user_id, 'claim', v_claim, 'title', 'Unfair eviction after ' || to_char(round(v_stay, 1), 'FM990.0') || ' days',
      'sub', 'Your landlord gave notice soon after you moved in.', 'at', e.created_at,
      'evidence', jsonb_build_object('record', 'property_events', 'id', e.id, 'stay_days', round(v_stay, 2), 'protect_days', bl_court_num('court.eviction_protect_days', 7), 'at', e.created_at));

  else -- overcharge
    select * into t from market_trades where id = v_id;
    if not found or t.buyer_id <> p_me or not ('far_high' = any (t.flags)) then
      return jsonb_build_object('ok', false, 'why', 'We have no record of an overcharge on that trade.');
    end if;
    if t.created_at < v_since then return jsonb_build_object('ok', false, 'why', 'That happened too long ago. The court only hears recent cases.'); end if;
    v_claim := t.price - t.value;
    if t.value <= 0 or v_claim < v_min then return jsonb_build_object('ok', false, 'why', 'The price was not far above the value.'); end if;
    return jsonb_build_object('ok', true, 'defendant', t.seller_id, 'claim', v_claim, 'title', 'Overcharged for ' || t.title,
      'sub', 'You paid ' || bl_naira(t.price) || ' for something worth ' || bl_naira(t.value) || '.', 'at', t.created_at,
      'evidence', jsonb_build_object('record', 'market_trades', 'id', t.id, 'item', t.title, 'price', t.price, 'value', t.value, 'at', t.created_at));
  end if;
end $$;

create or replace function public.bl_court_tier(p_claim bigint) returns text
language sql stable set search_path = public as $$
  select case when p_claim <= bl_court_num('court.customary_max', 100000) then 'customary' else 'high' end;
$$;

create or replace function public.bl_court_fee(p_tier text) returns bigint
language sql stable set search_path = public as $$
  select greatest(0, case when p_tier = 'customary' then bl_court_num('court.customary_fee', 1500) else bl_court_num('court.filing_fee', 5000) end)::bigint;
$$;

-- the recorded events this player can sue about, newest first (each one already checked by bl_court_evidence)
create or replace function public.bl_court_my_events(p_me uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_since timestamptz := bl_now() - make_interval(secs => bl_court_num('court.lookback_hours', 72) * 3600);
  r record; ev jsonb; v_out jsonb := '[]'::jsonb; v_tier text;
begin
  for r in
    select * from (
      (select 'pickpocket'::text as k, a.id::text as ref, a.resolved_at as at from crime_attempts a
        where a.victim_id = p_me and a.status = 'success' and a.amount > 0 and a.resolved_at >= v_since order by a.id desc limit 15)
      union all
      (select 'rent_owed', e.id::text, e.created_at from property_events e join properties pr on pr.id = e.property_id
        where pr.owner_id = p_me and e.kind = 'tenancy_ended' and e.created_at >= v_since order by e.id desc limit 15)
      union all
      (select 'eviction', e.id::text, e.created_at from property_events e
        where e.user_id = p_me and e.kind = 'tenancy_ended' and e.created_at >= v_since and e.detail ->> 'why' = 'notice' order by e.id desc limit 15)
      union all
      (select 'overcharge', t.id::text, t.created_at from market_trades t
        where t.buyer_id = p_me and 'far_high' = any (t.flags) and t.created_at >= v_since order by t.id desc limit 15)
    ) x order by at desc limit 40
  loop
    ev := bl_court_evidence(p_me, r.k, r.ref);
    if coalesce((ev ->> 'ok')::boolean, false) and (ev ->> 'defendant')::uuid <> p_me then
      v_tier := bl_court_tier((ev ->> 'claim')::bigint);
      v_out := v_out || jsonb_build_array(ev || jsonb_build_object('kind', r.k, 'ref', r.ref, 'tier', v_tier, 'fee', bl_court_fee(v_tier),
        'defendant_name', bl_username((ev ->> 'defendant')::uuid),
        'filed', exists (select 1 from court_cases c where c.kind = r.k and c.event_ref = r.ref and c.status <> 'dismissed')));
    end if;
  end loop;
  return v_out;
end $$;

-- take up to p_amount from CASH first, then the bank, never below zero; returns what was taken
create or replace function public.bl_court_take(p_uid uuid, p_amount bigint, p_reason text, p_meta jsonb) returns bigint
language plpgsql set search_path = public as $$
declare v profiles; v_cash bigint; v_bank bigint;
begin
  if coalesce(p_amount, 0) <= 0 then return 0; end if;
  select * into v from profiles where id = p_uid for update;
  if not found then return 0; end if;
  v_cash := least(greatest(v.cash, 0), p_amount);
  v_bank := least(greatest(v.bank, 0), p_amount - v_cash);
  if v_cash > 0 then perform bl_add_money(p_uid, 'cash', -v_cash, p_reason, p_meta); end if;
  if v_bank > 0 then perform bl_add_money(p_uid, 'bank', -v_bank, p_reason, p_meta); end if;
  return v_cash + v_bank;
end $$;

-- the Police jail case system: a repeat offender goes to the cell like a caught thief (the "Police don catch you" popup, bail, serve, escape)
create or replace function public.bl_court_jail(p_uid uuid, p_seconds int, p_reason text) returns int
language plpgsql set search_path = public as $$
declare
  v_now timestamptz := bl_now(); v_max int := greatest(1, bl_crime_num('crime.case_jail_max_seconds', 86400))::int;
  v_sec int := least(greatest(1, p_seconds), v_max); c jail_cases; v_loc text := coalesce(bl_cfg_text('crime.jail_location'), 'police_hq');
begin
  perform bl_crime_close_stale(p_uid);
  select * into c from jail_cases where user_id = p_uid and status = 'open';
  if found then
    update jail_cases set jail_seconds = least(v_max, jail_seconds + v_sec), jail_until = jail_until + make_interval(secs => v_sec) where id = c.id returning * into c;
    update profiles set jailed_until = greatest(coalesce(jailed_until, c.jail_until), c.jail_until), wanted = least(5, wanted + 1) where id = p_uid;
  else
    insert into jail_cases (user_id, reason, location_id, attempt_id, bail_amount, jail_seconds, jail_until, created_at)
    values (p_uid, left(p_reason, 200), v_loc, null, greatest(0, round(bl_crime_num('crime.bail_base', 20000000)))::bigint, v_sec, v_now + make_interval(secs => v_sec), v_now)
    returning * into c;
    update profiles set jailed_until = c.jail_until, jail_reason = c.reason, wanted = least(5, wanted + 1),
      location_id = coalesce((select id from locations where id = v_loc), location_id),
      travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
     where id = p_uid;
  end if;
  return v_sec;
end $$;

-- pick a judge: a sitting judge who is not a party and not a lawyer in this case, with the fewest live cases. Null when there is none.
create or replace function public.bl_court_assign_judge(p_case bigint) returns uuid
language plpgsql set search_path = public as $$
declare c court_cases; v_j uuid;
begin
  select * into c from court_cases where id = p_case and status = 'scheduled' for update;
  if not found then return null; end if;
  select h.user_id into v_j
    from ind_holders h join ind_offices o on o.id = h.office_id
    left join (select judge_id, count(*) as n from court_cases where status = 'scheduled' and judge_id is not null group by judge_id) l on l.judge_id = h.user_id
   where h.status = 'active' and h.term_end > bl_now() and o.active and o.id like 'court\_judge\_%' and bl_ind_on()
     and h.user_id not in (c.plaintiff_id, c.defendant_id)
     and not exists (select 1 from court_hires x where x.case_id = c.id and x.lawyer_id = h.user_id and x.status in ('pending', 'accepted', 'paid'))
     and not exists (select 1 from profiles p where p.id = h.user_id and p.banned)
   order by coalesce(l.n, 0), h.user_id limit 1;
  update court_cases set judge_id = v_j where id = c.id;
  if v_j is not null then
    perform bl_event(v_j, 'court_assigned', 'You have a case to hear', c.case_no || ': ' || c.title || '. The hearing starts ' ||
      to_char(c.hearing_at at time zone 'Africa/Lagos', 'HH24:MI') || '. Open the Court app to rule.', jsonb_build_object('case', c.id));
  end if;
  return v_j;
end $$;

create or replace function public.bl_court_hire_refund(p_hire bigint, p_status text, p_why text) returns void
language plpgsql set search_path = public as $$
declare h court_hires; c court_cases;
begin
  select * into h from court_hires where id = p_hire and status in ('pending', 'accepted') for update;
  if not found then return; end if;
  select * into c from court_cases where id = h.case_id;
  if h.fee > 0 then
    perform bl_add_money(h.client_id, 'bank', h.fee, 'lawyer_fee_refund', jsonb_build_object('label', 'Lawyer fee returned (' || c.case_no || ')', 'case', c.case_no));
  end if;
  update court_hires set status = p_status, decided_at = bl_now() where id = h.id;
  perform bl_event(h.client_id, 'court_hire_answer', 'Lawyer fee returned', p_why || ' ' || bl_naira(h.fee) || ' is back in your bank. ' || c.case_no || '.',
    jsonb_build_object('case', c.id, 'hire', h.id));
  if p_status in ('expired', 'refunded') then
    perform bl_event(h.lawyer_id, 'court_hire_answer', 'Hire request closed', c.case_no || ': ' || p_why, jsonb_build_object('case', c.id, 'hire', h.id));
  end if;
end $$;

-- the verdict and its money. ONE place. Locks everyone in id order first (no two player rows are ever locked in a different order).
create or replace function public.bl_court_execute(p_case bigint, p_verdict text, p_by text, p_note text, p_actor uuid) returns void
language plpgsql set search_path = public as $$
declare
  c court_cases; h court_hires; v_now timestamptz := bl_now(); v_ids uuid[]; v_pn text; v_dn text; v_note text := left(btrim(coalesce(p_note, '')), 300);
  v_paid bigint := 0; v_debt bigint := 0; v_fine bigint := 0; v_fine_paid bigint := 0; v_fine_debt bigint := 0; v_prior int; v_jail int := 0; v_hit int := 0;
  v_debt_on boolean := bl_pol_flag('court.debt_enabled', true); v_cut bigint; v_win boolean; v_body text; v_jail_after int;
begin
  if p_verdict not in ('guilty', 'not_guilty') then raise exception 'Bad verdict.' using errcode = 'P0001', hint = 'bad_verdict'; end if;
  select * into c from court_cases where id = p_case for update;
  if not found or c.status <> 'scheduled' then return; end if;
  select array_agg(distinct u order by u) into v_ids from (
    select c.plaintiff_id as u union all select c.defendant_id
    union all select x.lawyer_id from court_hires x where x.case_id = c.id and x.status in ('pending', 'accepted', 'paid')
    union all select x.client_id from court_hires x where x.case_id = c.id and x.status in ('pending', 'accepted')) q where u is not null;
  perform 1 from profiles where id = any (v_ids) order by id for update;
  v_pn := bl_username(c.plaintiff_id); v_dn := bl_username(c.defendant_id);

  if p_verdict = 'guilty' then
    -- restitution: what the record shows was taken, from cash then bank; the rest becomes court debt (collected from future income)
    v_paid := bl_court_take(c.defendant_id, c.claim, 'court_restitution_out',
      jsonb_build_object('label', 'Court order: paid back @' || v_pn, 'case', c.case_no));
    if v_paid > 0 then
      perform bl_add_money(c.plaintiff_id, 'bank', v_paid, 'court_restitution_in',
        jsonb_build_object('label', 'Court order: paid by @' || v_dn, 'case', c.case_no));
    end if;
    v_debt := c.claim - v_paid;
    if v_debt > 0 and v_debt_on then
      insert into court_debts (case_id, debtor_id, creditor_id, kind, amount, owed) values (c.id, c.defendant_id, c.plaintiff_id, 'restitution', v_debt, v_debt);
    else
      v_debt := 0;
    end if;
    -- the fine is a sink
    v_fine := greatest(greatest(0, bl_court_num('court.fine_min', 2000)), round(c.claim * bl_court_num('court.fine_pct', 20) / 100.0))::bigint;
    v_fine_paid := bl_court_take(c.defendant_id, v_fine, 'court_fine', jsonb_build_object('label', 'Court fine (' || c.case_no || ')', 'case', c.case_no));
    v_fine_debt := v_fine - v_fine_paid;
    if v_fine_debt > 0 and v_debt_on then
      insert into court_debts (case_id, debtor_id, creditor_id, kind, amount, owed) values (c.id, c.defendant_id, null, 'fine', v_fine_debt, v_fine_debt);
    else
      v_fine_debt := 0;
    end if;
    -- the plaintiff gets the filing fee back
    if c.filing_fee > 0 then
      perform bl_add_money(c.plaintiff_id, 'bank', c.filing_fee, 'court_fee_refund', jsonb_build_object('label', 'Filing fee returned (' || c.case_no || ')', 'case', c.case_no));
    end if;
    -- street cred
    v_hit := greatest(0, bl_court_num('court.cred_hit', 5))::int;
    if v_hit > 0 then update profiles set street_cred = street_cred - v_hit where id = c.defendant_id; end if;
    -- repeat offenders: jail through the Police case system
    select count(*) into v_prior from court_cases x
     where x.defendant_id = c.defendant_id and x.verdict = 'guilty' and x.status = 'ruled' and x.id <> c.id
       and x.ruled_at > v_now - make_interval(secs => bl_court_num('court.repeat_days', 30) * 86400);
    v_jail_after := greatest(1, bl_court_num('court.jail_after_verdicts', 2))::int;
    if v_prior + 1 >= v_jail_after then
      v_jail := bl_court_jail(c.defendant_id, (greatest(1, bl_court_num('court.jail_base_seconds', 60)) * (v_prior + 2 - v_jail_after))::int,
        'Jailed by the court: repeat offender (' || c.case_no || ')');
    end if;
  end if;

  -- lawyers: paid on the verdict (minus the court cut, a sink); a request nobody accepted is returned; on an admin re-ruling only the record changes
  for h in select * from court_hires where case_id = c.id and status in ('pending', 'accepted', 'paid') order by id loop
    if h.status = 'pending' then
      perform bl_court_hire_refund(h.id, 'expired', 'Nobody took the request before the verdict.');
    else
      v_win := (p_verdict = 'guilty' and h.side = 'plaintiff') or (p_verdict = 'not_guilty' and h.side = 'defendant');
      if h.status = 'accepted' then
        v_cut := round(h.fee * bl_court_num('court.cut_pct', 5) / 100.0)::bigint;
        if h.fee - v_cut > 0 then
          perform bl_add_money(h.lawyer_id, 'bank', h.fee - v_cut, 'lawyer_fee_in',
            jsonb_build_object('label', 'Lawyer fee (' || c.case_no || ')', 'case', c.case_no, 'cut', v_cut));
        end if;
        update court_hires set status = 'paid', cut = v_cut, decided_at = v_now where id = h.id;
      end if;
      update court_lawyers set wins = wins + case when v_win then 1 else 0 end, losses = losses + case when v_win then 0 else 1 end where user_id = h.lawyer_id;
      perform bl_event(h.lawyer_id, 'court_verdict', case when v_win then 'You won the case' else 'You lost the case' end,
        c.case_no || ': ' || case p_verdict when 'guilty' then 'Guilty.' else 'Not guilty.' end
        || case when h.status = 'accepted' then ' Your fee ' || bl_naira(h.fee - v_cut) || ' is in your bank.' else '' end,
        jsonb_build_object('case', c.id, 'win', v_win));
    end if;
  end loop;

  v_body := case p_verdict
    when 'guilty' then 'GUILTY. @' || v_dn || ' pays @' || v_pn || ' ' || bl_naira(c.claim) || ' and a fine of ' || bl_naira(v_fine) || '.'
         || case when v_debt + v_fine_debt > 0 then ' The part not paid today (' || bl_naira(v_debt + v_fine_debt) || ') is court debt.' else '' end
         || case when v_jail > 0 then ' Repeat offender: jailed.' else '' end
    else 'NOT GUILTY. The case is dismissed and the filing fee is lost.' end
    || case when v_note <> '' then ' ' || v_note else '' end;
  insert into court_statements (case_id, side, kind, author_id, as_lawyer, body, created_at) values (c.id, 'bench', 'ruling', p_actor, false, v_body, v_now);

  update court_cases set status = 'ruled', verdict = p_verdict, verdict_by = p_by, verdict_note = v_note, ruled_at = v_now,
    restitution_paid = v_paid, restitution_debt = v_debt, fine = v_fine, fine_paid = v_fine_paid, cred_hit = v_hit, jail_seconds = v_jail
   where id = c.id;

  perform bl_event(c.plaintiff_id, 'court_verdict', case p_verdict when 'guilty' then 'You won your case' else 'You lost your case' end,
    c.case_no || ': ' || case p_verdict when 'guilty' then 'Guilty. ' || bl_naira(v_paid) || ' paid back to your bank'
         || case when v_debt > 0 then ' and ' || bl_naira(v_debt) || ' more will follow from @' || v_dn || '''s income' else '' end
         || '. Your filing fee is returned.'
       else 'Not guilty. The filing fee is not returned.' end,
    jsonb_build_object('case', c.id, 'verdict', p_verdict));
  perform bl_event(c.defendant_id, 'court_verdict', case p_verdict when 'guilty' then 'The court found you guilty' else 'The court found you not guilty' end,
    c.case_no || ': ' || case p_verdict when 'guilty' then 'You paid ' || bl_naira(v_paid) || ' and a fine of ' || bl_naira(v_fine_paid) || '. You lost ' || v_hit || ' street cred.'
         || case when v_debt + v_fine_debt > 0 then ' You owe ' || bl_naira(v_debt + v_fine_debt) || ' more: ' || trim_scale(bl_court_num('court.debt_collect_pct', 30))::text || '% of your income goes to it.' else '' end
         || case when v_jail > 0 then ' Repeat offender: ' || v_jail || ' seconds in the cell.' else '' end
       else 'Not guilty. The case is dismissed.' end,
    jsonb_build_object('case', c.id, 'verdict', p_verdict));
  if c.judge_id is not null and p_by <> 'judge' then
    perform bl_event(c.judge_id, 'court_verdict', 'Case closed', c.case_no || ' was closed by ' || case p_by when 'auto' then 'the automatic ruling' else 'an admin' end || '.', jsonb_build_object('case', c.id));
  end if;
end $$;

-- admin override of an executed ruling: put the money back as far as it can go, then the caller rules again
create or replace function public.bl_court_reverse(p_case bigint) returns void
language plpgsql set search_path = public as $$
declare c court_cases; h court_hires; v_ids uuid[]; v_held bigint; v_win_was boolean;
begin
  select * into c from court_cases where id = p_case and status = 'ruled' for update;
  if not found then return; end if;
  select array_agg(distinct u order by u) into v_ids from (
    select c.plaintiff_id as u union all select c.defendant_id
    union all select x.lawyer_id from court_hires x where x.case_id = c.id and x.status = 'paid') q where u is not null;
  perform 1 from profiles where id = any (v_ids) order by id for update;
  if c.verdict = 'guilty' then
    -- the defendant gets back what was taken (restitution and fine); the plaintiff pays back as much as they still have
    if c.restitution_paid > 0 then
      perform bl_add_money(c.defendant_id, 'bank', c.restitution_paid, 'court_refund', jsonb_build_object('label', 'Court order undone (' || c.case_no || ')', 'case', c.case_no));
      perform bl_court_take(c.plaintiff_id, c.restitution_paid, 'court_refund_out', jsonb_build_object('label', 'Court order undone (' || c.case_no || ')', 'case', c.case_no));
    end if;
    if c.fine_paid > 0 then
      perform bl_add_money(c.defendant_id, 'bank', c.fine_paid, 'court_refund', jsonb_build_object('label', 'Court fine returned (' || c.case_no || ')', 'case', c.case_no));
    end if;
    if c.filing_fee > 0 then
      perform bl_court_take(c.plaintiff_id, c.filing_fee, 'court_refund_out', jsonb_build_object('label', 'Filing fee returned to the court (' || c.case_no || ')', 'case', c.case_no));
    end if;
    -- debts for this case end; money collected but not yet paid out goes back to the debtor
    select coalesce(sum(held), 0) into v_held from court_debts where case_id = c.id;
    if v_held > 0 then
      perform bl_add_money(c.defendant_id, 'bank', v_held, 'court_refund', jsonb_build_object('label', 'Court debt collected, returned (' || c.case_no || ')', 'case', c.case_no));
    end if;
    update court_debts set owed = 0, held = 0, settled_at = bl_now() where case_id = c.id;
    if c.cred_hit > 0 then update profiles set street_cred = street_cred + c.cred_hit where id = c.defendant_id; end if;
  end if;
  -- lawyer records: undo the old win or loss (the new ruling counts again; the fee already paid stays paid)
  for h in select * from court_hires where case_id = c.id and status = 'paid' loop
    v_win_was := (c.verdict = 'guilty' and h.side = 'plaintiff') or (c.verdict = 'not_guilty' and h.side = 'defendant');
    update court_lawyers set wins = greatest(0, wins - case when v_win_was then 1 else 0 end), losses = greatest(0, losses - case when v_win_was then 0 else 1 end)
     where user_id = h.lawyer_id;
  end loop;
  update court_cases set status = 'scheduled', verdict = null, verdict_by = null, restitution_paid = 0, restitution_debt = 0, fine = 0, fine_paid = 0, cred_hit = 0,
    jail_seconds = 0, ruled_at = null where id = c.id;
end $$;

-- everything that is due for ONE case: expire lawyer requests when the hearing starts, find a judge, and the automatic ruling after the window
create or replace function public.bl_court_settle_case(p_case bigint) returns void
language plpgsql set search_path = public as $$
declare c court_cases; h court_hires; v_now timestamptz := bl_now(); v_ok boolean;
begin
  select * into c from court_cases where id = p_case and status = 'scheduled' for update skip locked;
  if not found then return; end if;
  if c.hearing_at <= v_now then
    for h in select * from court_hires where case_id = c.id and status = 'pending' order by id loop
      perform bl_court_hire_refund(h.id, 'expired', 'The lawyer did not accept before the hearing started.');
    end loop;
    if c.judge_id is null or not bl_court_judge_ok(c.judge_id) then
      perform bl_court_assign_judge(c.id);
    end if;
  end if;
  if c.ruling_deadline <= v_now then
    v_ok := coalesce((bl_court_evidence(c.plaintiff_id, c.kind, c.event_ref, false) ->> 'ok')::boolean, false);
    perform bl_court_execute(c.id, case when v_ok then 'guilty' else 'not_guilty' end, 'auto',
      'Automatic ruling: no judge ruled in time, so the court followed the recorded evidence.', null);
  end if;
end $$;

-- the lazy clock (no cron): this player's own due cases, one global overdue case, and their share of collected court debt
create or replace function public.bl_court_tick(p_uid uuid) returns void
language plpgsql set search_path = public as $$
declare r record; v_now timestamptz := bl_now(); v_held bigint;
begin
  for r in
    select c.id from court_cases c
     where c.status = 'scheduled' and c.hearing_at <= v_now
       and (c.plaintiff_id = p_uid or c.defendant_id = p_uid or c.judge_id = p_uid
            or exists (select 1 from court_hires h where h.case_id = c.id and h.lawyer_id = p_uid and h.status in ('pending', 'accepted')))
     order by c.id limit 5
  loop
    perform bl_court_settle_case(r.id);
  end loop;
  -- one global overdue case: a case past its ruling deadline first, then one still waiting for a judge
  for r in select c.id from court_cases c where c.status = 'scheduled' and c.hearing_at <= v_now
              and (c.ruling_deadline <= v_now or c.judge_id is null)
            order by (c.ruling_deadline <= v_now) desc, c.id limit 1 loop
    perform bl_court_settle_case(r.id);
  end loop;
  select coalesce(sum(q.held), 0) into v_held from (select held from court_debts where creditor_id = p_uid and held > 0 for update) q;
  if v_held > 0 then
    update court_debts set held = 0 where creditor_id = p_uid and held > 0;
    perform bl_add_money(p_uid, 'bank', v_held, 'court_restitution_in', jsonb_build_object('label', 'Court order: payment received from your debtor'));
    perform bl_event(p_uid, 'court_debt_paid', 'Court payment received', bl_naira(v_held) || ' of what the court ordered is now in your bank.', jsonb_build_object('amount', v_held));
  end if;
end $$;

-- court debt is collected out of EARNINGS through the ledger, right after the tax garnish (bl_add_money calls this for every credit)
create or replace function public.bl_court_garnish(p_uid uuid, p_account text, p_delta bigint, p_reason text) returns bigint
language plpgsql set search_path = public as $$
declare d court_debts; v_budget bigint; v_part bigint; v_total bigint := 0; v_left_all bigint;
begin
  if p_delta <= 0 or not (p_reason = any (bl_earn_reasons())) then return 0; end if;
  if not exists (select 1 from court_debts where debtor_id = p_uid and owed > 0) then return 0; end if;
  v_budget := floor(p_delta * greatest(0, least(100, bl_court_num('court.debt_collect_pct', 30))) / 100.0)::bigint;
  if v_budget <= 0 then return 0; end if;
  for d in select * from court_debts where debtor_id = p_uid and owed > 0 order by id for update loop
    exit when v_budget <= 0;
    v_part := least(d.owed, v_budget);
    perform bl_add_money(p_uid, p_account, -v_part, 'court_debt',
      jsonb_build_object('label', case d.kind when 'fine' then 'Court fine (from your earnings)' else 'Court debt (from your earnings)' end, 'case', d.case_id, 'garnish', true));
    update court_debts set owed = owed - v_part, held = held + case when d.creditor_id is null then 0 else v_part end,
      settled_at = case when owed - v_part = 0 then bl_now() else null end where id = d.id;
    v_budget := v_budget - v_part; v_total := v_total + v_part;
  end loop;
  select coalesce(sum(owed), 0) into v_left_all from court_debts where debtor_id = p_uid;
  if v_total > 0 and v_left_all = 0 then
    perform bl_event(p_uid, 'court_debt_cleared', 'Court debt cleared', 'You have paid everything the court ordered.', '{}'::jsonb);
  end if;
  return v_total;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Guarded patches of live functions
-- ---------------------------------------------------------------------------------------------
-- debt garnish right after the tax garnish
select pg_temp.ct_patch('public.bl_add_money(uuid, text, bigint, text, jsonb)', 'bl_court_garnish',
  $o$v_bal := v_bal - bl_tax_garnish(p_uid, p_account, p_delta, p_reason);$o$,
  $o$v_bal := v_bal - bl_tax_garnish(p_uid, p_account, p_delta, p_reason);
    v_bal := v_bal - bl_court_garnish(p_uid, p_account, p_delta, p_reason);$o$);

-- court money is never earned, whatever Admin writes into leaderboard.earn_reasons
select pg_temp.ct_patch('public.bl_earn_reasons()', 'court_restitution_in',
  $o$'phone_bank_withdraw'])$o$,
  $o$'phone_bank_withdraw', 'court_restitution_in', 'court_restitution_out', 'court_fee', 'court_fee_refund', 'court_fine', 'court_debt', 'court_refund', 'court_refund_out', 'lawyer_escrow', 'lawyer_fee_refund'])$o$);

-- ledger labels
select pg_temp.ct_patch('public.bl_ledger_label(text, jsonb)', 'court_restitution_in',
  $o$when 'house_buy' then return coalesce(nullif(p_meta->>'label', ''), 'Home bought');$o$,
  $o$when 'court_fee' then return coalesce(nullif(p_meta->>'label', ''), 'Court filing fee');
    when 'court_fee_refund' then return coalesce(nullif(p_meta->>'label', ''), 'Filing fee returned');
    when 'court_restitution_out' then return coalesce(nullif(p_meta->>'label', ''), 'Court order: paid back');
    when 'court_restitution_in' then return coalesce(nullif(p_meta->>'label', ''), 'Court order: paid to you');
    when 'court_fine' then return coalesce(nullif(p_meta->>'label', ''), 'Court fine');
    when 'court_debt' then return coalesce(nullif(p_meta->>'label', ''), 'Court debt');
    when 'court_refund' then return coalesce(nullif(p_meta->>'label', ''), 'Court order undone');
    when 'court_refund_out' then return coalesce(nullif(p_meta->>'label', ''), 'Court order undone');
    when 'lawyer_escrow' then return coalesce(nullif(p_meta->>'label', ''), 'Lawyer fee held');
    when 'lawyer_fee_in' then return coalesce(nullif(p_meta->>'label', ''), 'Lawyer fee');
    when 'lawyer_fee_refund' then return coalesce(nullif(p_meta->>'label', ''), 'Lawyer fee returned');
    when 'house_buy' then return coalesce(nullif(p_meta->>'label', ''), 'Home bought');$o$);

-- court alerts go out as pushes in the existing "events" category (same caps and preferences as the weekly prize)
select pg_temp.ct_patch('public.bl_push_on_event()', 'court_summons',
  $o$elsif new.kind = 'referral_bonus' then$o$,
  $o$elsif new.kind in ('court_summons', 'court_hire_request', 'court_hire_answer', 'court_assigned', 'court_verdict', 'court_debt_paid') then
    perform bl_push_enqueue(new.user_id, 'events', new.kind, new.title, new.body, '/play?go=court');
  elsif new.kind = 'referral_bonus' then$o$);

-- ---------------------------------------------------------------------------------------------
-- 6. Grants: every bl_court_* helper is private
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and proname like 'bl\_court\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
end $$;
notify pgrst, 'reload schema';
