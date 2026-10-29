-- Industry offices (docs/OFFICES.md): Governor of the Bank, Transport / Health / Markets and Trade / Education / Housing and Lands Commissioners,
-- Power (NEPA) Managing Director (inactive until the power levers are switched on). A holder controls a few LIVE settings of their industry,
-- never freely: every lever has an admin hard band, a step, a cooldown; every office has a daily change cap and a total drift budget; the live
-- setting is written (so the rest of the game just reads it) and the admin baseline is remembered and restored when the holder is removed,
-- the term ends or the holder goes inactive. Offices are filled by ADMIN APPOINTMENT (any player by username, or an applicant); a later
-- election cycle can fill them (election_enabled / seats columns exist and are OFF, nothing is built for them). The political election
-- (offices, office_holders, bl_pol_*) is not touched, except one guarded one-line patch of bl_pol_title (the badge) and bl_dealer_net.
--   1. Settings `offices.*` (category offices) + health.price_pct (the one new lever key, read by bl_dealer_net).
--   2. Tables (all keyed by user id WITHOUT a foreign key to profiles): ind_offices, ind_levers (FK to game_config), ind_holders, ind_applications,
--      ind_baseline, ind_changes (the audit), ind_votes (approval), ind_statements.
--   3. Server: tick (lazy, bounded), apply / withdraw, admin appoint / reject / remove, levers, approval, statements, notices, alerts.
--   4. Admin Content editors for ind_offices and ind_levers; admin RPCs (overview, appoint, applicants, remove, freeze).
-- Idempotent: tables `if not exists`, seeds `on conflict do nothing`, functions `create or replace`, live functions patched through a guarded
-- replace on pg_get_functiondef (skipped when applied, a notice when the anchor is gone). No loop over players anywhere.

create or replace function pg_temp.io_patch(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n <> 1 then
    raise notice 'industry offices: % : marker found % times, patch skipped: %', p_sig, v_n, left(p_marker, 80);
    return;
  end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('offices.enabled', 'true', 'offices', 'Industry offices on',
 'Industry offices (docs/OFFICES.md): applications, appointments, levers, salaries and badges. Off = nothing can be applied, appointed or changed and holders have no powers (levers already moved stay until the next restore).', 'bool', null, null),
('offices.salary_enabled', 'true', 'offices', 'Industry office salaries on', 'Whole days of the term are paid to the holder''s bank (ledger office_salary, counted as earned).', 'bool', null, null),
('offices.inactive_days', '5', 'offices', 'Holder inactive for (days)', 'A holder not seen for this many days loses the office and every lever they moved goes back to the admin baseline.', 'number', 1, 90),
('offices.band_floor_pct', '50', 'offices', 'Lever floor (% of baseline)', 'Hard rail for EVERY lever whatever its own band says: a holder can never set a value below this share of the admin baseline. Keeps fees and taxes (money sinks) from being switched off.', 'percent', 1, 100),
('offices.band_cap_pct', '150', 'offices', 'Lever cap (% of baseline)', 'Hard rail for every lever: never above this share of the admin baseline.', 'percent', 100, 1000),
('offices.notice_gap_hours', '3', 'offices', 'Public notice gap per office (hours)', 'A lever change is announced to everybody at most once per office per this many hours (the others show in the Industry offices list and the holder''s alerts).', 'number', 0, 72),
('offices.notices_per_hour', '6', 'offices', 'Public lever notices per hour (all offices)', 'City-wide cap on public lever notices.', 'number', 1, 100),
('offices.statement_max_len', '160', 'offices', 'Official statement: longest (characters)', 'Moderated like chat plus the real-party and politician blocklists.', 'number', 20, 500),
('offices.statement_cooldown_hours', '24', 'offices', 'Official statement cooldown (hours)', 'One statement a day per holder.', 'number', 0, 720),
('offices.pitch_max_len', '140', 'offices', 'Application pitch: longest (characters)', 'Moderated like a campaign promise.', 'number', 20, 500),
('offices.reapply_days', '7', 'offices', 'Removed applicant waits (days)', 'An applicant the admin removed cannot apply for the same office again for this long.', 'number', 0, 365),
('offices.vote_min_account_days', '3', 'offices', 'Approval vote needs account age (days)', 'Anti-alt: younger accounts cannot give a thumbs up or down.', 'number', 0, 3650),
('offices.low_approval_pct', '30', 'offices', 'Low approval warning below (%)', 'A holder whose approval stays below this (with enough votes) gets a warning alert and is highlighted for the admin. Nobody is removed automatically.', 'percent', 0, 100),
('offices.low_approval_min_votes', '10', 'offices', 'Low approval needs at least (votes)', 'Fewest approval votes before the warning can trigger.', 'number', 1, 10000),
('health.price_pct', '100', 'offices', 'Medicine and pharmacy prices (%)', 'Price of the "health" shop items (medicine) as a percent of the catalogue price. 100 = normal. The Health Commissioner moves it inside a band (docs/OFFICES.md).', 'percent', 50, 200)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.ind_offices (
  id               text primary key,
  name             text not null,
  industry         text not null default '',
  title            text not null default '',                 -- the badge next to a name
  icon             text not null default '🏛️',
  blurb            text not null default '',
  salary_per_day   bigint not null default 0 check (salary_per_day >= 0),
  term_days        numeric not null default 14 check (term_days > 0),
  min_account_days numeric not null default 3 check (min_account_days >= 0),
  min_level        int not null default 0 check (min_level >= 0),          -- career level (profiles.job_level)
  election_enabled boolean not null default false,           -- reserved: a later election cycle may fill this office (NOT built)
  seats            int not null default 1 check (seats >= 1),             -- reserved: only seat 1 is used today
  max_changes_per_day int not null default 4 check (max_changes_per_day >= 0),
  max_total_drift_pct numeric not null default 100 check (max_total_drift_pct >= 0),   -- sum over levers of |value - baseline| / baseline (percent)
  frozen           boolean not null default false,           -- admin froze every lever of the office
  sort             int not null default 0,
  active           boolean not null default true
);

create table if not exists public.ind_levers (
  id            text primary key,
  office_id     text not null references public.ind_offices(id) on update cascade on delete cascade,
  config_key    text not null references public.game_config(key) on update cascade on delete cascade,
  label         text not null,
  blurb         text not null default '',
  unit          text not null default 'number' check (unit in ('percent', 'naira', 'number', 'seconds', 'hour', 'mult')),
  band_min      numeric not null,
  band_max      numeric not null,
  step          numeric not null default 1 check (step > 0),
  cooldown_hours numeric not null default 24 check (cooldown_hours >= 0),
  direction     text not null default '',                    -- plain note: what lower / higher does to players
  effect        text not null default '',                    -- confirm card text with {old} and {new}
  frozen        boolean not null default false,
  sort          int not null default 0,
  active        boolean not null default true,
  check (band_min <= band_max)
);
create unique index if not exists ind_levers_key_uq on public.ind_levers (config_key);
create index if not exists ind_levers_office_idx on public.ind_levers (office_id, sort);

create table if not exists public.ind_holders (
  id            bigserial primary key,
  office_id     text not null references public.ind_offices(id),
  seat_no       int not null default 1,
  user_id       uuid not null,
  source        text not null default 'admin' check (source in ('admin', 'application', 'election')),
  appointed_by  uuid,
  status        text not null default 'active' check (status in ('active', 'ended', 'removed', 'resigned', 'inactive')),
  term_start    timestamptz not null,
  term_end      timestamptz not null,
  paid_through  timestamptz not null,
  salary_paid   bigint not null default 0,
  last_statement_at timestamptz,
  low_warned_at timestamptz,
  ended_at      timestamptz,
  ended_reason  text
);
create unique index if not exists ind_holders_one_seat on public.ind_holders (office_id, seat_no) where status = 'active';
create unique index if not exists ind_holders_one_office on public.ind_holders (user_id) where status = 'active';
create index if not exists ind_holders_office_idx on public.ind_holders (office_id, status);
create index if not exists ind_holders_user_idx on public.ind_holders (user_id);

create table if not exists public.ind_applications (
  id          bigserial primary key,
  office_id   text not null references public.ind_offices(id),
  user_id     uuid not null,
  pitch       text not null default '',
  status      text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'removed', 'withdrawn')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  decided_by  uuid,
  note        text not null default ''
);
create unique index if not exists ind_applications_one_pending on public.ind_applications (user_id) where status = 'pending';
create index if not exists ind_applications_office_idx on public.ind_applications (office_id, status);
create index if not exists ind_applications_user_idx on public.ind_applications (user_id, status);

-- the admin baseline of a setting a holder moved, and the value the holder set (restore only when it still equals that: an admin edit wins)
create table if not exists public.ind_baseline (
  config_key text primary key references public.game_config(key) on update cascade on delete cascade,
  office_id  text not null references public.ind_offices(id) on update cascade on delete cascade,
  baseline   jsonb not null,
  held       jsonb not null,
  holder_id  bigint,
  changed_at timestamptz not null default now()
);
create index if not exists ind_baseline_office_idx on public.ind_baseline (office_id);

create table if not exists public.ind_changes (
  id         bigserial primary key,
  office_id  text not null,
  lever_id   text not null,
  config_key text not null,
  holder_id  bigint,
  user_id    uuid,
  kind       text not null default 'change' check (kind in ('change', 'restore')),
  old_value  jsonb,
  new_value  jsonb,
  reason     text not null default '',
  announced  boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists ind_changes_office_idx on public.ind_changes (office_id, created_at desc);
create index if not exists ind_changes_holder_idx on public.ind_changes (holder_id, lever_id, created_at desc);
create index if not exists ind_changes_time_idx on public.ind_changes (created_at desc);

create table if not exists public.ind_votes (
  holder_id  bigint not null references public.ind_holders(id) on delete cascade,
  voter_id   uuid not null,
  up         boolean not null,
  created_at timestamptz not null default now(),
  primary key (holder_id, voter_id)
);
create index if not exists ind_votes_voter_idx on public.ind_votes (voter_id);

create table if not exists public.ind_statements (
  id         bigserial primary key,
  holder_id  bigint not null references public.ind_holders(id) on delete cascade,
  office_id  text not null,
  user_id    uuid not null,
  body       text not null,
  created_at timestamptz not null default now()
);
create index if not exists ind_statements_holder_idx on public.ind_statements (holder_id, created_at desc);
create index if not exists ind_statements_time_idx on public.ind_statements (created_at desc);

alter table public.ind_offices enable row level security;
alter table public.ind_levers enable row level security;
alter table public.ind_holders enable row level security;
alter table public.ind_applications enable row level security;
alter table public.ind_baseline enable row level security;
alter table public.ind_changes enable row level security;
alter table public.ind_votes enable row level security;
alter table public.ind_statements enable row level security;
revoke all on table public.ind_offices, public.ind_levers, public.ind_holders, public.ind_applications, public.ind_baseline, public.ind_changes,
  public.ind_votes, public.ind_statements from public, anon, authenticated;
revoke all on sequence public.ind_holders_id_seq, public.ind_applications_id_seq, public.ind_changes_id_seq, public.ind_statements_id_seq from public, anon, authenticated;
-- the two catalogues are readable by signed-in players (admins write through admin_row_upsert); everything else is server-only
grant select on table public.ind_offices, public.ind_levers to authenticated;
drop policy if exists ind_offices_read on public.ind_offices;
create policy ind_offices_read on public.ind_offices for select to authenticated using (true);
drop policy if exists ind_levers_read on public.ind_levers;
create policy ind_levers_read on public.ind_levers for select to authenticated using (true);

-- ---------------------------------------------------------------------------------------------
-- 3. Seeds: offices and levers (fictional titles only; admin edits survive a re-run)
-- ---------------------------------------------------------------------------------------------
insert into public.ind_offices (id, name, industry, title, icon, blurb, salary_per_day, term_days, min_account_days, min_level, max_changes_per_day, max_total_drift_pct, active, sort) values
('bank_governor', 'Governor of the Bank', 'bank', 'Bank Gov.', '🏦', 'Runs Benin City Central Bank. Moves the transfer fee, stamp duty, PoS charge, income tax rates, the daily transfer limit and the counter hours, a little at a time. The fees are sinks: the money is destroyed, never paid to you.', 5000000, 14, 7, 2, 4, 120, true, 1),
('transport_commissioner', 'Transport Commissioner', 'transport', 'Transport Comm.', '🛺', 'Sets keke, bus and drop fares inside a band. Cheap fares are popular, dear fares are not.', 1500000, 14, 5, 1, 4, 100, true, 2),
('health_commissioner', 'Health Commissioner', 'health', 'Health Comm.', '🏥', 'Medicine prices and how long a hospital stay lasts.', 2000000, 14, 5, 1, 4, 100, true, 3),
('markets_commissioner', 'Markets and Trade Commissioner', 'markets', 'Trade Comm.', '🛍️', 'Oba Market and the shops: the council levy on businesses, the lowest haggle offer and the delivery markup.', 1500000, 14, 5, 1, 4, 100, true, 4),
('education_commissioner', 'Education Commissioner', 'education', 'Edu. Comm.', '🎓', 'School and course fees, extra lessons and university pocket money.', 1000000, 14, 5, 1, 4, 100, true, 5),
('housing_commissioner', 'Housing and Lands Commissioner', 'housing', 'Housing Comm.', '🏘️', 'Agent and legal fees on homes, ground rent and the band landlords may charge rent in.', 1500000, 14, 5, 1, 4, 100, true, 6),
('nepa_md', 'Power (NEPA) Managing Director', 'power', 'NEPA MD', '💡', 'Runs the lights: how often each area has an outage. Closed until the power levers are switched on.', 3000000, 14, 7, 2, 4, 100, false, 7)
on conflict (id) do nothing;

insert into public.ind_levers (id, office_id, config_key, label, blurb, unit, band_min, band_max, step, cooldown_hours, direction, effect, sort)
select v.id, v.office_id, v.config_key, v.label, v.blurb, v.unit, v.band_min, v.band_max, v.step, v.cooldown_hours, v.direction, v.effect, v.sort
  from (values
  -- Governor of the Bank: every one of these is a sink (money destroyed). Bands are 50 to 150 percent of the default or narrower.
  ('bank.fee1', 'bank_governor', 'economy.fee_tier1_pct', 'Transfer fee, first ₦50,000', 'The fee on the first ₦50,000 of every transfer. The fee is destroyed, it is not income for anybody.', 'percent', 0.5, 1.5, 0.1, 24, 'Lower is kinder to people sending money. Higher takes more money out of the city.', 'Sending up to ₦50,000 will cost {new} in fees instead of {old}.', 1),
  ('bank.fee2', 'bank_governor', 'economy.fee_tier2_pct', 'Transfer fee, ₦50,000 to ₦500,000', 'The fee on the part of a transfer between ₦50,000 and ₦500,000.', 'percent', 1, 3, 0.25, 24, 'Lower is kinder. Higher destroys more money.', 'The middle part of a transfer will cost {new} in fees instead of {old}.', 2),
  ('bank.fee3', 'bank_governor', 'economy.fee_tier3_pct', 'Transfer fee, above ₦500,000', 'The fee on the part of a transfer above ₦500,000.', 'percent', 1.5, 4.5, 0.25, 24, 'Lower is kinder to big senders. Higher destroys more money.', 'The big part of a transfer will cost {new} in fees instead of {old}.', 3),
  ('bank.stamp', 'bank_governor', 'economy.stamp_duty', 'Stamp duty on transfers', 'A flat duty on every transfer of ₦10,000 or more. Destroyed.', 'naira', 25, 75, 5, 24, 'Lower is kinder. Higher destroys more money.', 'Every transfer of ₦10,000 or more will pay {new} stamp duty instead of {old}.', 4),
  ('bank.pos', 'bank_governor', 'pos.fee_pct', 'PoS charge', 'What a PoS stand charges to cash out or deposit. Destroyed.', 'percent', 1, 2.25, 0.25, 24, 'Lower is kinder to people using PoS. Higher destroys more money.', 'PoS stands will charge {new} instead of {old}.', 5),
  ('bank.tax2', 'bank_governor', 'economy.tax_band2_pct', 'Income tax, ₦500k to ₦5M a week', 'The weekly tax rate on earnings between ₦500,000 and ₦5 million. Destroyed.', 'percent', 4, 6, 0.5, 48, 'Lower leaves more with earners. Higher destroys more money.', 'Weekly earnings between ₦500k and ₦5M will be taxed at {new} instead of {old}.', 6),
  ('bank.tax3', 'bank_governor', 'economy.tax_band3_pct', 'Income tax, ₦5M to ₦50M a week', 'The weekly tax rate on earnings between ₦5 million and ₦50 million.', 'percent', 8, 12, 1, 48, 'Lower leaves more with big earners. Higher destroys more money.', 'Weekly earnings between ₦5M and ₦50M will be taxed at {new} instead of {old}.', 7),
  ('bank.tax4', 'bank_governor', 'economy.tax_band4_pct', 'Income tax, above ₦50M a week', 'The weekly tax rate on earnings above ₦50 million.', 'percent', 12, 18, 1, 48, 'Lower leaves more with the richest. Higher destroys more money.', 'Weekly earnings above ₦50M will be taxed at {new} instead of {old}.', 8),
  ('bank.limit', 'bank_governor', 'bank.transfer_daily_limit', 'Daily transfer limit', 'The most a player can send in one game day.', 'naira', 150000, 250000, 25000, 24, 'Lower is safer against abuse. Higher lets people move more money (it creates none).', 'Players can send up to {new} a day instead of {old}.', 9),
  ('bank.open', 'bank_governor', 'bank.open_hour', 'Bank counter opens', 'The game hour the Bronze Bank counter opens.', 'hour', 7, 9, 1, 24, 'Earlier is more convenient.', 'The bank counter will open at {new} instead of {old}.', 10),
  ('bank.close', 'bank_governor', 'bank.close_hour', 'Bank counter closes', 'The game hour the Bronze Bank counter closes.', 'hour', 15, 18, 1, 24, 'Later is more convenient.', 'The bank counter will close at {new} instead of {old}.', 11),
  -- Transport Commissioner: fares are paid by riders and destroyed
  ('transport.keke_base', 'transport_commissioner', 'travel.keke.base_cost', 'Keke base fare', 'Paid at the start of every keke ride.', 'naira', 100, 200, 10, 24, 'Lower is cheaper for riders.', 'A keke ride will start at {new} instead of {old}.', 1),
  ('transport.keke_km', 'transport_commissioner', 'travel.keke.per_km', 'Keke fare per km', 'Added for every kilometre of a keke ride.', 'naira', 70, 130, 10, 24, 'Lower is cheaper for riders.', 'Keke will cost {new} a km instead of {old}.', 2),
  ('transport.bus_base', 'transport_commissioner', 'travel.bus.base_cost', 'ECTS bus flat fare', 'The flat fare on the city bus.', 'naira', 200, 400, 25, 24, 'Lower is cheaper for riders.', 'The bus will cost {new} instead of {old}.', 3),
  ('transport.drop_base', 'transport_commissioner', 'travel.drop.base_cost', 'Drop base fare', 'Paid at the start of a private drop.', 'naira', 350, 650, 50, 24, 'Lower is cheaper for riders.', 'A drop will start at {new} instead of {old}.', 4),
  ('transport.drop_km', 'transport_commissioner', 'travel.drop.per_km', 'Drop fare per km', 'Added for every kilometre of a drop.', 'naira', 175, 325, 25, 24, 'Lower is cheaper for riders.', 'A drop will cost {new} a km instead of {old}.', 5),
  -- Health Commissioner
  ('health.price', 'health_commissioner', 'health.price_pct', 'Medicine and pharmacy prices', 'The price of medicine in shops, as a percent of the normal price.', 'percent', 75, 125, 5, 24, 'Lower is cheaper for the sick.', 'Medicine will cost {new} of the normal price (now {old}).', 1),
  ('health.stay', 'health_commissioner', 'action.hospital_max_seconds', 'Longest hospital stay', 'The most real seconds a hospital stay can last.', 'seconds', 20, 40, 5, 24, 'Shorter is kinder to patients.', 'A hospital stay will last at most {new} instead of {old}.', 2),
  -- Markets and Trade Commissioner
  ('markets.levy_chance', 'markets_commissioner', 'business.levy_pct', 'Council levy chance for businesses', 'The chance each business day that the council task force comes for a levy.', 'percent', 6, 10, 1, 24, 'Lower is kinder to business owners.', 'A business will face the council levy {new} of days instead of {old}.', 1),
  ('markets.levy_bite', 'markets_commissioner', 'business.levy_loss_pct', 'Council levy bite', 'The share of a day''s takings a levy takes.', 'percent', 25, 45, 5, 24, 'Lower is kinder to business owners.', 'A levy will take {new} of a day''s takings instead of {old}.', 2),
  ('markets.min_offer', 'markets_commissioner', 'market.min_offer_pct', 'Lowest haggle offer on Benin Market', 'The lowest offer a buyer may make, as a percent of the asking price.', 'percent', 40, 60, 5, 24, 'Lower lets buyers haggle harder. Higher protects sellers.', 'Buyers can offer no less than {new} of the price instead of {old}.', 3),
  ('markets.delivery', 'markets_commissioner', 'shop.delivery_markup_pct', 'Chowdeck delivery markup', 'The extra a delivery adds to the shop price.', 'percent', 30, 50, 5, 24, 'Lower is cheaper for people ordering food.', 'Delivery will add {new} to the price instead of {old}.', 4),
  -- Education Commissioner
  ('education.course_fee', 'education_commissioner', 'school.fee_mult', 'Course fees', 'A multiplier on every course fee.', 'mult', 0.75, 1.25, 0.05, 24, 'Lower is cheaper for students.', 'Course fees will be {new} of the normal fee (now {old}).', 1),
  ('education.lessons', 'education_commissioner', 'kids_school.lessons_cost', 'Extra lessons for a child', 'What extra lessons cost per class.', 'naira', 6000, 10000, 500, 24, 'Lower is cheaper for parents.', 'Extra lessons will cost {new} a class instead of {old}.', 2),
  ('education.pocket', 'education_commissioner', 'kids_school.uni_pocket_cost', 'University pocket money', 'What parents pay for university pocket money each time.', 'naira', 4500, 7500, 500, 24, 'Lower is cheaper for parents.', 'University pocket money will cost {new} instead of {old}.', 3),
  -- Housing and Lands Commissioner
  ('housing.agent', 'housing_commissioner', 'property.agent_fee_pct', 'Agent fee when buying a home', 'The agent fee on a home purchase. Destroyed.', 'percent', 1.5, 4.5, 0.5, 24, 'Lower is cheaper for buyers.', 'The agent fee on buying a home will be {new} instead of {old}.', 1),
  ('housing.legal', 'housing_commissioner', 'property.legal_fee_pct', 'Legal fee when buying a home', 'The legal and documentation fee on a home purchase. Destroyed.', 'percent', 1, 2, 0.25, 24, 'Lower is cheaper for buyers.', 'The legal fee on buying a home will be {new} instead of {old}.', 2),
  ('housing.ground', 'housing_commissioner', 'economy.ground_rent_pct', 'Ground rent', 'The weekly ground rent on land and bought homes, as a percent of their value. Destroyed.', 'percent', 0.05, 0.15, 0.01, 24, 'Lower is cheaper for owners.', 'Ground rent will be {new} a week instead of {old}.', 3),
  ('housing.sell_agent', 'housing_commissioner', 'property.sell_agent_pct', 'Agent fee when selling a home', 'The agent fee when a home is sold back. Destroyed.', 'percent', 1, 3, 0.5, 24, 'Lower is better for sellers.', 'The agent fee on selling a home will be {new} instead of {old}.', 4),
  ('housing.rent_max', 'housing_commissioner', 'property.rent_max_pct', 'Highest rent a landlord may ask', 'As a percent of the market rent.', 'percent', 125, 175, 5, 24, 'Lower protects tenants. Higher favours landlords.', 'Landlords can ask up to {new} of the market rent instead of {old}.', 5),
  ('housing.rent_min', 'housing_commissioner', 'property.rent_min_pct', 'Lowest rent a landlord may ask', 'As a percent of the market rent.', 'percent', 40, 60, 5, 24, 'Higher protects landlords. Lower favours tenants.', 'Landlords can ask no less than {new} of the market rent instead of {old}.', 6)
  ) as v(id, office_id, config_key, label, blurb, unit, band_min, band_max, step, cooldown_hours, direction, effect, sort)
 where exists (select 1 from public.game_config g where g.key = v.config_key)
   and (v.config_key <> 'health.price_pct' or exists (select 1 from public.game_config g where g.key = 'health.price_pct'))
on conflict (id) do nothing;

-- Power (NEPA) Managing Director: the outage chance of each area, only when the power settings exist (the office stays inactive: an admin
-- switches it on in Content -> Industry offices once the power system is live). Band 75 to 125 percent of the default, whole percent.
insert into public.ind_levers (id, office_id, config_key, label, blurb, unit, band_min, band_max, step, cooldown_hours, direction, effect, sort)
select 'power.' || substr(g.key, length('power.outage_pct.') + 1), 'nepa_md', g.key,
       'Outage chance, ' || coalesce(nullif(btrim(regexp_replace(g.label, '^Outage % - ', '')), ''), substr(g.key, length('power.outage_pct.') + 1)),
       'How often the area loses power (percent chance in a spell).', 'percent',
       greatest(coalesce(g.min, 0), floor((g.value #>> '{}')::numeric * 0.75)), least(coalesce(g.max, 100), ceil((g.value #>> '{}')::numeric * 1.25)), 1, 24,
       'Lower means more light.', 'The outage chance will be {new} instead of {old}.', 10
  from public.game_config g
 where g.key like 'power.outage\_pct.%' and jsonb_typeof(g.value) = 'number'
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_ind_on() returns boolean
language sql stable set search_path = public as $$
  select bl_pol_flag('offices.enabled', true);
$$;

create or replace function public.bl_ind_guard() returns void
language plpgsql stable set search_path = public as $$
begin
  if not bl_ind_on() then
    raise exception 'Industry offices are closed for now. Check back soon.' using errcode = 'P0001', hint = 'disabled';
  end if;
end $$;

-- a value for people: 1.5 -> "1.5%", 50 (naira) -> "N50", hour 8 -> "8:00", mult 0.9 -> "x0.9"
create or replace function public.bl_ind_fmt(p_unit text, p_val numeric) returns text
language sql immutable set search_path = public as $$
  select case p_unit
    when 'percent' then trim_scale(p_val)::text || '%'
    when 'naira' then '₦' || to_char(p_val, 'FM999,999,999,999,990')
    when 'hour' then trim_scale(p_val)::text || ':00'
    when 'seconds' then trim_scale(p_val)::text || ' s'
    when 'mult' then 'x' || trim_scale(p_val)::text
    else trim_scale(p_val)::text end;
$$;

-- the title next to a name (an industry office). Definer: it reads closed tables.
create or replace function public.bl_ind_title(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select nullif(o.title, '') from ind_holders h join ind_offices o on o.id = h.office_id
   where h.user_id = p_uid and h.status = 'active' and h.term_end > bl_now() and o.active and bl_ind_on() limit 1;
$$;

-- does a player hold any office now (industry or elected)?
create or replace function public.bl_ind_holds_any(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ind_holders h where h.user_id = p_uid and h.status = 'active' and h.term_end > bl_now())
      or exists (select 1 from office_holders h where h.user_id = p_uid and h.status = 'active' and h.term_end > bl_now());
$$;

-- a public notice to everybody through the existing broadcast system (alerts inbox popup + the Announcements push)
create or replace function public.bl_ind_notice(p_actor uuid, p_title text, p_body text) returns bigint
language plpgsql set search_path = public as $$
declare v_id bigint; n int;
begin
  insert into broadcasts (kind, title, body, style, audience, popup, expires_at, created_by)
  values ('message', left(p_title, 80), left(p_body, 300), 'info', 'everyone', true, now() + interval '24 hours', p_actor)
  returning id into v_id;
  select count(*) into n from bl_broadcast_targets('everyone', null);
  update broadcasts set target_count = n where id = v_id;
  perform bl_broadcast_bump(v_id);
  return v_id;
exception when others then
  return null;   -- a notice must never break an appointment or a lever
end $$;

-- pay the salary days a holder has earned and not yet been paid (whole days, never past the end of the term). Ledger office_salary (earned).
create or replace function public.bl_ind_pay(p_holder bigint) returns bigint
language plpgsql set search_path = public as $$
declare h ind_holders; o ind_offices; v_days int; v_amt bigint; v_until timestamptz;
begin
  select * into h from ind_holders where id = p_holder for update;
  if not found or not bl_ind_on() or not bl_pol_flag('offices.salary_enabled', true) then return 0; end if;
  select * into o from ind_offices where id = h.office_id;
  v_until := least(bl_now(), h.term_end);
  v_days := floor(extract(epoch from (v_until - h.paid_through)) / 86400.0)::int;
  if v_days < 1 then return 0; end if;
  v_amt := v_days::bigint * o.salary_per_day;
  update ind_holders set paid_through = paid_through + make_interval(days => v_days), salary_paid = salary_paid + v_amt where id = h.id;
  if v_amt > 0 then
    perform bl_add_money(h.user_id, 'bank', v_amt, 'office_salary',
      jsonb_build_object('label', o.name || ' salary (' || v_days || ' day' || case when v_days = 1 then '' else 's' end || ')', 'office', o.id, 'days', v_days));
  end if;
  return v_amt;
end $$;

-- put every setting this office's holders moved back to the admin baseline. One row per lever of the office (a handful), never per player.
-- A setting an admin edited after the holder moved it is NOT overwritten (the admin's value wins); its baseline row is just dropped.
create or replace function public.bl_ind_restore(p_office text, p_holder bigint, p_reason text) returns int
language plpgsql set search_path = public as $$
declare r record; v_cur jsonb; n int := 0;
begin
  for r in select b.config_key, b.baseline, b.held, l.id as lever_id from ind_baseline b join ind_levers l on l.config_key = b.config_key
            where b.office_id = p_office order by l.sort, l.id loop
    select value into v_cur from game_config where key = r.config_key for update;
    if found and v_cur = r.held then
      update game_config set value = r.baseline where key = r.config_key;
      insert into ind_changes (office_id, lever_id, config_key, holder_id, user_id, kind, old_value, new_value, reason, created_at)
      values (p_office, r.lever_id, r.config_key, p_holder, null, 'restore', r.held, r.baseline, left(p_reason, 200), bl_now());
      n := n + 1;
    end if;
    delete from ind_baseline where config_key = r.config_key;
  end loop;
  -- a baseline row of a lever that left the office (edited in Content) is cleaned too
  return n;
end $$;

-- end a holder's term for any reason: last salary, status, levers back to baseline, an alert and (optionally) a public notice
create or replace function public.bl_ind_end(p_holder bigint, p_status text, p_reason text, p_by uuid, p_notice boolean) returns void
language plpgsql set search_path = public as $$
declare h ind_holders; o ind_offices; v_n int; v_name text; v_title text;
begin
  select * into h from ind_holders where id = p_holder and status = 'active' for update;
  if not found then return; end if;
  select * into o from ind_offices where id = h.office_id;
  perform bl_ind_pay(h.id);
  update ind_holders set status = p_status, ended_at = bl_now(), ended_reason = left(p_reason, 200) where id = h.id;
  v_n := bl_ind_restore(h.office_id, h.id, p_reason);
  select username into v_name from profiles where id = h.user_id;
  v_title := case p_status when 'removed' then 'You were removed as ' || o.name
                           when 'resigned' then 'You resigned as ' || o.name
                           when 'inactive' then 'You lost the ' || o.name || ' office'
                           else 'Your term as ' || o.name || ' is over' end;
  perform bl_event(h.user_id, 'ind_ended', v_title,
    p_reason || case when v_n > 0 then ' Everything you changed went back to the normal values.' else '' end,
    jsonb_build_object('office', o.id, 'status', p_status));
  if p_notice then
    perform bl_ind_notice(coalesce(p_by, h.user_id), o.name || ': seat is empty',
      '@' || coalesce(v_name, 'The holder') || ' is no longer ' || o.name || '. ' ||
      case when v_n > 0 then 'The settings they changed are back to normal.' else 'The seat is vacant.' end);
  end if;
end $$;

-- lazy clock: ends terms, inactive holders, holders of a closed office or of an elected seat, and pays due salaries (a few rows, no cron)
create or replace function public.bl_ind_tick() returns void
language plpgsql set search_path = public as $$
declare r record; v_now timestamptz := bl_now(); v_days numeric := bl_pol_num('offices.inactive_days', 5);
begin
  if not bl_ind_on() then return; end if;
  for r in
    select h.id, h.term_end, o.active as o_active, h.paid_through,
           greatest(coalesce(p.last_seen, h.term_start), h.term_start) as seen,
           exists (select 1 from office_holders eh where eh.user_id = h.user_id and eh.status = 'active' and eh.term_end > v_now) as elected
      from ind_holders h join ind_offices o on o.id = h.office_id left join profiles p on p.id = h.user_id
     where h.status = 'active'
       and (h.term_end <= v_now or not o.active or h.paid_through + interval '1 day' <= v_now
            or greatest(coalesce(p.last_seen, h.term_start), h.term_start) < v_now - make_interval(secs => v_days * 86400)
            or exists (select 1 from office_holders eh where eh.user_id = h.user_id and eh.status = 'active' and eh.term_end > v_now))
     order by h.id limit 25 for update of h skip locked
  loop
    if r.term_end <= v_now then perform bl_ind_end(r.id, 'ended', 'Your term is over. The seat is open for the next appointment.', null, true);
    elsif not r.o_active then perform bl_ind_end(r.id, 'ended', 'The office was closed by an admin.', null, true);
    elsif r.elected then perform bl_ind_end(r.id, 'ended', 'You took an elected seat, so you cannot also hold this office.', null, true);
    elsif r.seen < v_now - make_interval(secs => v_days * 86400) then
      perform bl_ind_end(r.id, 'inactive', 'You were not seen for ' || trim_scale(v_days)::text || ' days, so the office was taken back.', null, true);
    else perform bl_ind_pay(r.id);
    end if;
  end loop;
end $$;

-- can this player apply for an office? Checklist like Benin Votes. {ok, hint, message, checks:[{key,label,ok}]}
create or replace function public.bl_ind_requirements(p_uid uuid, o public.ind_offices) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  me profiles; v_age numeric; v_checks jsonb := '[]'::jsonb; v_ok boolean; v_first jsonb;
  v_days text := trim(trailing '.' from trim(trailing '0' from o.min_account_days::numeric(10, 2)::text));
begin
  select * into me from profiles where id = p_uid;
  v_age := extract(epoch from (bl_now() - me.created_at)) / 86400.0;
  v_ok := v_age >= o.min_account_days;
  v_checks := v_checks || jsonb_build_object('key', 'account_young', 'ok', v_ok, 'label', 'Account at least ' || v_days || ' days old',
                'message', 'Your account must be at least ' || v_days || ' days old to apply for ' || o.name || '.');
  if o.min_level > 0 then
    v_ok := coalesce(me.job_level, 0) >= o.min_level;
    v_checks := v_checks || jsonb_build_object('key', 'level_low', 'ok', v_ok, 'label', 'Career level ' || o.min_level,
                  'message', 'You need career level ' || o.min_level || ' to apply for ' || o.name || '. Work your way up.');
  end if;
  v_ok := not (me.jailed_until is not null and me.jailed_until > bl_now()) and not exists (select 1 from jail_cases j where j.user_id = p_uid and j.status = 'open');
  v_checks := v_checks || jsonb_build_object('key', 'jailed', 'ok', v_ok, 'label', 'Not in jail', 'message', 'You dey inside. Office holders must be free people.');
  v_ok := not bl_ind_holds_any(p_uid);
  v_checks := v_checks || jsonb_build_object('key', 'holds_office', 'ok', v_ok, 'label', 'Not holding another office', 'message', 'You already hold an office. One office at a time.');
  select c into v_first from jsonb_array_elements(v_checks) c where not (c->>'ok')::boolean limit 1;
  return jsonb_build_object('ok', v_first is null, 'hint', v_first->>'key', 'message', v_first->>'message', 'checks', v_checks);
end $$;

-- approval of a holder: {up, down, votes, pct (null with no votes), mine (true / false / null)}
create or replace function public.bl_ind_approval(p_holder bigint, p_viewer uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('up', coalesce(sum(case when v.up then 1 else 0 end), 0), 'down', coalesce(sum(case when v.up then 0 else 1 end), 0),
    'votes', count(*), 'pct', case when count(*) = 0 then null else round(100.0 * sum(case when v.up then 1 else 0 end) / count(*)) end,
    'mine', (select x.up from ind_votes x where x.holder_id = p_holder and x.voter_id = p_viewer))
    from ind_votes v where v.holder_id = p_holder;
$$;

create or replace function public.bl_ind_low(p_holder bigint) returns boolean
language sql stable set search_path = public as $$
  select coalesce((select count(*) >= bl_pol_num('offices.low_approval_min_votes', 10)
                          and 100.0 * sum(case when v.up then 1 else 0 end) / count(*) < bl_pol_num('offices.low_approval_pct', 30)
                     from ind_votes v where v.holder_id = p_holder), false);
$$;

create or replace function public.bl_ind_holder_json(h public.ind_holders, p_viewer uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare s ind_statements;
begin
  select * into s from ind_statements where holder_id = h.id order by id desc limit 1;
  return jsonb_build_object('id', h.id, 'user_id', h.user_id, 'username', (select username from profiles where id = h.user_id), 'source', h.source,
    'term_start', h.term_start, 'term_end', h.term_end, 'approval', bl_ind_approval(h.id, p_viewer),
    'statement', case when s.id is null then null else jsonb_build_object('body', s.body, 'at', s.created_at) end);
end $$;

-- a lever with the live value, the baseline (when a holder moved it), who moved it, and the band a holder may use right now
create or replace function public.bl_ind_lever_json(l public.ind_levers, o public.ind_offices) returns jsonb
language plpgsql stable set search_path = public as $$
declare g game_config; b ind_baseline; v_cur numeric; v_base numeric; v_lo numeric; v_hi numeric; v_floor numeric := bl_pol_num('offices.band_floor_pct', 50); v_cap numeric := bl_pol_num('offices.band_cap_pct', 150);
begin
  select * into g from game_config where key = l.config_key;
  select * into b from ind_baseline where config_key = l.config_key;
  v_cur := (g.value #>> '{}')::numeric;
  v_base := coalesce((b.baseline #>> '{}')::numeric, v_cur);
  v_lo := greatest(l.band_min, coalesce(g.min, l.band_min), v_base * v_floor / 100.0);
  v_hi := least(l.band_max, coalesce(g.max, l.band_max), v_base * v_cap / 100.0);
  return jsonb_build_object('id', l.id, 'office_id', l.office_id, 'config_key', l.config_key, 'label', l.label, 'blurb', l.blurb, 'unit', l.unit, 'direction', l.direction,
    'effect', l.effect, 'step', l.step, 'cooldown_hours', l.cooldown_hours, 'frozen', l.frozen or o.frozen, 'band_min', l.band_min, 'band_max', l.band_max,
    'lo', v_lo, 'hi', v_hi, 'current', v_cur, 'baseline', v_base, 'changed', b.config_key is not null,
    'changed_by', case when b.holder_id is null then null else (select p.username from ind_holders h join profiles p on p.id = h.user_id where h.id = b.holder_id) end,
    'changed_at', b.changed_at);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Install a holder (admin appointment or an accepted application)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_ind_install(p_office text, p_user uuid, p_by uuid, p_source text) returns bigint
language plpgsql set search_path = public as $$
declare o ind_offices; t profiles; v_id bigint; r record; v_now timestamptz := bl_now();
begin
  perform bl_ind_tick();
  select * into o from ind_offices where id = p_office and active;
  if not found then raise exception 'That office is not open.' using errcode = 'P0001', hint = 'bad_office'; end if;
  select * into t from profiles where id = p_user and home_chosen and not banned;
  if not found then raise exception 'No player with that username.' using errcode = 'P0001', hint = 'no_player'; end if;
  if bl_ind_holds_any(t.id) then
    raise exception '@% already holds an office. One office at a time.', t.username using errcode = 'P0001', hint = 'holds_office';
  end if;
  if exists (select 1 from ind_holders where office_id = o.id and seat_no = 1 and status = 'active') then
    raise exception '% is filled. Remove the current holder first.', o.name using errcode = 'P0001', hint = 'filled';
  end if;
  insert into ind_holders (office_id, seat_no, user_id, source, appointed_by, status, term_start, term_end, paid_through)
  values (o.id, 1, t.id, p_source, p_by, 'active', v_now, v_now + make_interval(secs => o.term_days * 86400), v_now) returning id into v_id;
  -- the accepted application is closed; any other pending application of this player is withdrawn
  update ind_applications set status = case when office_id = o.id then 'accepted' else 'withdrawn' end, decided_at = v_now, decided_by = p_by,
         note = case when office_id = o.id then note else 'Appointed to another office' end
   where user_id = t.id and status = 'pending';
  perform bl_event(t.id, 'ind_appointed', 'You are now ' || o.name,
    'You can change a few settings of your industry inside safe limits, post one statement a day and earn ₦' || to_char(o.salary_per_day, 'FM999,999,999,990') ||
    ' a day until the term ends. The city is watching: people can give you a thumbs up or down.', jsonb_build_object('office', o.id));
  perform bl_ind_notice(p_by, o.name || ': new holder', '@' || t.username || ' is the new ' || o.name || '.');
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.ind_tick() returns void
language plpgsql security definer set search_path = public as $$
begin
  perform bl_require_uid();
  perform bl_ind_tick();
end $$;

-- "My Office" phone app: does the caller hold a seat RIGHT NOW (an industry office or an elected / appointed political one)? The app shows only
-- while this says so; every power behind the app checks the seat again on the server (ind_* here, pol_* in Benin Votes).
create or replace function public.office_mine() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_now timestamptz; h ind_holders; o ind_offices; p office_holders; po offices;
begin
  perform bl_ind_tick();
  v_now := bl_now();
  select * into h from ind_holders where user_id = v_uid and status = 'active' and term_end > v_now;
  if h.id is not null and bl_ind_on() then
    select * into o from ind_offices where id = h.office_id;
    return jsonb_build_object('holds', true, 'kind', 'industry', 'office_id', o.id, 'office', o.name, 'title', o.title, 'icon', o.icon, 'term_end', h.term_end,
      'days_left', round((extract(epoch from (h.term_end - v_now)) / 86400.0)::numeric, 1), 'salary_per_day', o.salary_per_day);
  end if;
  select * into p from office_holders where user_id = v_uid and status = 'active' and term_end > v_now;
  if p.id is not null and bl_pol_on() then
    select * into po from offices where id = p.office_id;
    return jsonb_build_object('holds', true, 'kind', 'political', 'office_id', po.id, 'office_kind', po.kind, 'office', po.name, 'title', po.title, 'icon', po.icon, 'term_end', p.term_end,
      'days_left', round((extract(epoch from (p.term_end - v_now)) / 86400.0)::numeric, 1), 'salary_per_day', po.salary_per_day);
  end if;
  return jsonb_build_object('holds', false);
end $$;

create or replace function public.ind_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_now timestamptz; h ind_holders; o ind_offices; v_me jsonb := null; v_app ind_applications; v_levers jsonb; v_drift numeric; v_changes int;
  v_next timestamptz;
begin
  perform bl_ind_tick();
  v_now := bl_now();
  select * into h from ind_holders where user_id = v_uid and status = 'active' and term_end > v_now;
  select * into v_app from ind_applications where user_id = v_uid and status = 'pending';
  if h.id is not null then
    perform bl_ind_pay(h.id);
    select * into h from ind_holders where id = h.id;
    select * into o from ind_offices where id = h.office_id;
    select coalesce(sum(abs((g.value #>> '{}')::numeric - (b.baseline #>> '{}')::numeric) / nullif(abs((b.baseline #>> '{}')::numeric), 0) * 100), 0) into v_drift
      from ind_baseline b join game_config g on g.key = b.config_key where b.office_id = o.id;
    select count(*) into v_changes from ind_changes where office_id = o.id and kind = 'change' and created_at > v_now - interval '24 hours';
    select coalesce(jsonb_agg(bl_ind_lever_json(l, o) || jsonb_build_object('next_at',
             (select max(c.created_at) + make_interval(secs => l.cooldown_hours * 3600) from ind_changes c where c.holder_id = h.id and c.lever_id = l.id and c.kind = 'change'))
             order by l.sort, l.id), '[]'::jsonb) into v_levers from ind_levers l where l.office_id = o.id and l.active;
    v_next := h.last_statement_at + make_interval(hours => bl_pol_num('offices.statement_cooldown_hours', 24)::int);
    v_me := jsonb_build_object('holder', bl_ind_holder_json(h, v_uid), 'office_id', o.id, 'office', o.name, 'title', o.title, 'icon', o.icon, 'salary_per_day', o.salary_per_day,
      'salary_paid', h.salary_paid, 'levers', v_levers, 'changes_today', v_changes, 'max_changes', o.max_changes_per_day, 'drift_used', round(v_drift, 1),
      'drift_budget', o.max_total_drift_pct, 'frozen', o.frozen, 'low_approval', bl_ind_low(h.id),
      'can_statement', h.last_statement_at is null or v_next <= v_now, 'statement_next_at', case when h.last_statement_at is null or v_next <= v_now then null else v_next end,
      'recent', coalesce((select jsonb_agg(jsonb_build_object('lever', l.label, 'unit', l.unit, 'kind', c.kind, 'old', c.old_value, 'new', c.new_value, 'at', c.created_at) order by c.id desc)
                            from (select * from ind_changes where office_id = o.id order by id desc limit 8) c join ind_levers l on l.id = c.lever_id), '[]'::jsonb));
  end if;
  return jsonb_build_object('enabled', bl_ind_on(), 'now', v_now,
    'settings', jsonb_build_object('inactive_days', bl_pol_num('offices.inactive_days', 5), 'statement_max_len', bl_pol_num('offices.statement_max_len', 160),
      'pitch_max_len', bl_pol_num('offices.pitch_max_len', 140), 'low_approval_pct', bl_pol_num('offices.low_approval_pct', 30),
      'low_approval_min_votes', bl_pol_num('offices.low_approval_min_votes', 10), 'vote_min_account_days', bl_pol_num('offices.vote_min_account_days', 3)),
    'me', v_me,
    'my_application', case when v_app.id is null then null else jsonb_build_object('id', v_app.id, 'office_id', v_app.office_id,
        'office', (select name from ind_offices where id = v_app.office_id), 'pitch', v_app.pitch, 'at', v_app.created_at) end,
    'offices', coalesce((
      select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'industry', x.industry, 'title', x.title, 'icon', x.icon, 'blurb', x.blurb,
        'salary_per_day', x.salary_per_day, 'term_days', x.term_days, 'min_account_days', x.min_account_days, 'min_level', x.min_level, 'frozen', x.frozen,
        'election_enabled', x.election_enabled, 'seats', x.seats, 'max_changes_per_day', x.max_changes_per_day,
        'holder', (select bl_ind_holder_json(hh, v_uid) from ind_holders hh where hh.office_id = x.id and hh.status = 'active' and hh.term_end > v_now limit 1),
        'applicants', (select count(*) from ind_applications a where a.office_id = x.id and a.status = 'pending'),
        'requirements', bl_ind_requirements(v_uid, x),
        'levers', coalesce((select jsonb_agg(bl_ind_lever_json(l, x) order by l.sort, l.id) from ind_levers l where l.office_id = x.id and l.active), '[]'::jsonb))
        order by x.sort, x.id)
        from ind_offices x where x.active), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('office', ox.name, 'lever', l.label, 'unit', l.unit, 'kind', c.kind, 'old', c.old_value, 'new', c.new_value, 'at', c.created_at,
                          'by', (select p.username from profiles p where p.id = c.user_id)) order by c.id desc)
                          from (select * from ind_changes order by id desc limit 15) c join ind_levers l on l.id = c.lever_id join ind_offices ox on ox.id = c.office_id), '[]'::jsonb));
end $$;

create or replace function public.ind_apply(p_office text, p_pitch text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); o ind_offices; v_req jsonb; v_pitch text; v_id bigint; me profiles;
begin
  perform bl_ind_tick(); perform bl_ind_guard();
  select * into me from profiles where id = v_uid;
  if me.banned or not me.home_chosen then raise exception 'You cannot apply yet.' using errcode = 'P0001', hint = 'not_allowed'; end if;
  select * into o from ind_offices where id = p_office and active;
  if not found then raise exception 'Pick an office from the list.' using errcode = 'P0001', hint = 'bad_office'; end if;
  if exists (select 1 from ind_applications where user_id = v_uid and status = 'pending') then
    raise exception 'You already have an application waiting. Withdraw it first.' using errcode = 'P0001', hint = 'already_applied';
  end if;
  if exists (select 1 from ind_applications where user_id = v_uid and office_id = o.id and status = 'removed'
                and decided_at > bl_now() - make_interval(days => bl_pol_num('offices.reapply_days', 7)::int)) then
    raise exception 'An admin removed your application. Wait a few days before applying again.' using errcode = 'P0001', hint = 'removed_recently';
  end if;
  v_req := bl_ind_requirements(v_uid, o);
  if not (v_req->>'ok')::boolean then raise exception '%', v_req->>'message' using errcode = 'P0001', hint = v_req->>'hint'; end if;
  v_pitch := bl_pol_moderate(p_pitch, 10, bl_pol_num('offices.pitch_max_len', 140)::int, 'pitch');
  insert into ind_applications (office_id, user_id, pitch, status, created_at) values (o.id, v_uid, v_pitch, 'pending', bl_now()) returning id into v_id;
  return jsonb_build_object('id', v_id, 'message', 'Your application for ' || o.name || ' is in. An admin will decide.');
end $$;

create or replace function public.ind_withdraw() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); a ind_applications;
begin
  select * into a from ind_applications where user_id = v_uid and status = 'pending' for update;
  if not found then raise exception 'You have no application waiting.' using errcode = 'P0001', hint = 'none'; end if;
  update ind_applications set status = 'withdrawn', decided_at = bl_now() where id = a.id;
  return jsonb_build_object('message', 'Application withdrawn.');
end $$;

-- the lever change. Everything is checked on the server: office / lever frozen, band (own band, hard rails of the baseline, the setting's own
-- limits), step, cooldown, changes per day for the office, the total drift budget. Writes the live setting, remembers the baseline, audits,
-- alerts the holder (and the other holders), and posts a rate limited public notice.
create or replace function public.ind_set_lever(p_lever text, p_value numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); h ind_holders; o ind_offices; l ind_levers; g game_config; b ind_baseline;
  v_now timestamptz; v_new numeric; v_old numeric; v_base numeric; v_lo numeric; v_hi numeric; v_n numeric; v_last timestamptz; v_next timestamptz;
  v_changes int; v_others numeric; v_drift_new numeric; v_total_old numeric; v_total_new numeric; v_floor numeric; v_cap numeric;
  v_name text; v_txt text; v_verb text; v_announce boolean := false; v_id bigint; v_notice text; r record;
begin
  perform bl_ind_tick(); perform bl_ind_guard();
  v_now := bl_now();
  select * into h from ind_holders where user_id = v_uid and status = 'active' and term_end > v_now for update;
  if not found then raise exception 'You do not hold an industry office.' using errcode = 'P0001', hint = 'not_holder'; end if;
  select * into o from ind_offices where id = h.office_id;
  select * into l from ind_levers where id = p_lever and active;
  if not found or l.office_id <> o.id then raise exception 'That setting is not yours to change.' using errcode = 'P0001', hint = 'not_yours'; end if;
  if o.frozen or l.frozen then raise exception 'An admin froze this. You cannot change it for now.' using errcode = 'P0001', hint = 'frozen'; end if;
  if p_value is null then raise exception 'Pick a value.' using errcode = 'P0001', hint = 'bad_value'; end if;
  v_new := trim_scale(p_value);
  select * into g from game_config where key = l.config_key for update;
  select * into b from ind_baseline where config_key = l.config_key;
  v_old := (g.value #>> '{}')::numeric;
  v_base := coalesce((b.baseline #>> '{}')::numeric, v_old);
  v_floor := bl_pol_num('offices.band_floor_pct', 50); v_cap := bl_pol_num('offices.band_cap_pct', 150);
  v_lo := greatest(l.band_min, coalesce(g.min, l.band_min), v_base * v_floor / 100.0);
  v_hi := least(l.band_max, coalesce(g.max, l.band_max), v_base * v_cap / 100.0);
  if v_new = v_old then raise exception 'That is already the value.' using errcode = 'P0001', hint = 'same'; end if;
  if v_new < v_lo or v_new > v_hi then
    raise exception 'Outside your limits. You can set this between % and %.', bl_ind_fmt(l.unit, v_lo), bl_ind_fmt(l.unit, v_hi) using errcode = 'P0001', hint = 'out_of_band';
  end if;
  v_n := (v_new - l.band_min) / l.step;
  if abs(v_n - round(v_n)) > 0.0001 and v_new <> v_base then
    raise exception 'Use steps of %.', bl_ind_fmt(l.unit, l.step) using errcode = 'P0001', hint = 'bad_step';
  end if;
  select max(created_at) into v_last from ind_changes where holder_id = h.id and lever_id = l.id and kind = 'change';
  v_next := v_last + make_interval(secs => l.cooldown_hours * 3600);
  if v_last is not null and v_next > v_now then
    raise exception 'You changed this recently. You can change it again in %.', bl_pol_wait(v_next - v_now) using errcode = 'P0001', hint = 'cooldown';
  end if;
  select count(*) into v_changes from ind_changes where office_id = o.id and kind = 'change' and created_at > v_now - interval '24 hours';
  if v_changes >= o.max_changes_per_day then
    raise exception 'Your office has used its % change% for today. Try again tomorrow.', o.max_changes_per_day, case when o.max_changes_per_day = 1 then '' else 's' end using errcode = 'P0001', hint = 'daily_cap';
  end if;
  -- total drift budget: the sum over this office's levers of |value - baseline| / baseline, in percent. Moving back toward the baseline is always fine.
  select coalesce(sum(abs((gg.value #>> '{}')::numeric - (bb.baseline #>> '{}')::numeric) / nullif(abs((bb.baseline #>> '{}')::numeric), 0) * 100), 0) into v_others
    from ind_baseline bb join game_config gg on gg.key = bb.config_key where bb.office_id = o.id and bb.config_key <> l.config_key;
  v_drift_new := case when v_base = 0 then 0 else abs(v_new - v_base) / abs(v_base) * 100 end;
  v_total_old := v_others + case when v_base = 0 then 0 else abs(v_old - v_base) / abs(v_base) * 100 end;
  v_total_new := v_others + v_drift_new;
  if v_total_new > o.max_total_drift_pct + 0.0001 and v_total_new > v_total_old then
    raise exception 'Too far from normal across your settings (% of % allowed). Move another setting back first.', round(v_total_new), round(o.max_total_drift_pct) using errcode = 'P0001', hint = 'drift_cap';
  end if;
  -- write the live setting and remember the baseline
  update game_config set value = to_jsonb(v_new) where key = l.config_key;
  if v_new = v_base and b.config_key is not null then
    delete from ind_baseline where config_key = l.config_key;
  elsif b.config_key is null then
    insert into ind_baseline (config_key, office_id, baseline, held, holder_id, changed_at) values (l.config_key, o.id, to_jsonb(v_old), to_jsonb(v_new), h.id, v_now);
  else
    update ind_baseline set held = to_jsonb(v_new), holder_id = h.id, changed_at = v_now where config_key = l.config_key;
  end if;
  select username into v_name from profiles where id = v_uid;
  -- public notice: once per office per gap, and a city-wide cap per hour
  v_announce := not exists (select 1 from ind_changes where office_id = o.id and announced and created_at > v_now - make_interval(secs => bl_pol_num('offices.notice_gap_hours', 3) * 3600))
            and (select count(*) from ind_changes where announced and created_at > v_now - interval '1 hour') < bl_pol_num('offices.notices_per_hour', 6);
  insert into ind_changes (office_id, lever_id, config_key, holder_id, user_id, kind, old_value, new_value, announced, created_at)
  values (o.id, l.id, l.config_key, h.id, v_uid, 'change', to_jsonb(v_old), to_jsonb(v_new), v_announce, v_now) returning id into v_id;
  v_verb := case when v_new < v_old then 'cut' else 'raised' end;
  v_txt := o.name || ' ' || v_verb || ' the ' || lower(l.label) || ' to ' || bl_ind_fmt(l.unit, v_new) || ' (was ' || bl_ind_fmt(l.unit, v_old) || ').';
  perform bl_event(v_uid, 'ind_lever', 'You changed: ' || l.label, v_txt || ' It is live now. It goes back to normal when your term ends.',
    jsonb_build_object('office', o.id, 'lever', l.id));
  if v_announce then
    perform bl_ind_notice(v_uid, 'Industry office: ' || o.name, v_txt);
    for r in select hh.user_id from ind_holders hh where hh.status = 'active' and hh.term_end > v_now and hh.user_id <> v_uid order by hh.id limit 20 loop
      perform bl_event(r.user_id, 'ind_notice', o.name || ' made a change', v_txt, jsonb_build_object('office', o.id, 'lever', l.id));
    end loop;
  end if;
  return jsonb_build_object('message', l.label || ' is now ' || bl_ind_fmt(l.unit, v_new) || '.', 'value', v_new, 'old', v_old, 'announced', v_announce);
end $$;

-- thumbs up / down for a holder: one vote per player per holder (a term); changing your mind replaces it
create or replace function public.ind_vote(p_holder bigint, p_up boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); h ind_holders; me profiles; o ind_offices; v_ap jsonb;
begin
  perform bl_ind_tick(); perform bl_ind_guard();
  select * into me from profiles where id = v_uid;
  if me.banned or not me.home_chosen then raise exception 'You cannot vote yet.' using errcode = 'P0001', hint = 'not_allowed'; end if;
  if extract(epoch from (bl_now() - me.created_at)) / 86400.0 < bl_pol_num('offices.vote_min_account_days', 3) then
    raise exception 'Your account is too new to rate office holders.' using errcode = 'P0001', hint = 'account_young';
  end if;
  select * into h from ind_holders where id = p_holder and status = 'active' and term_end > bl_now() for update;
  if not found then raise exception 'That seat has changed hands.' using errcode = 'P0001', hint = 'gone'; end if;
  if h.user_id = v_uid then raise exception 'You cannot rate yourself.' using errcode = 'P0001', hint = 'self'; end if;
  insert into ind_votes (holder_id, voter_id, up, created_at) values (h.id, v_uid, coalesce(p_up, true), bl_now())
  on conflict (holder_id, voter_id) do update set up = excluded.up, created_at = excluded.created_at;
  if bl_ind_low(h.id) and h.low_warned_at is null then
    select * into o from ind_offices where id = h.office_id;
    update ind_holders set low_warned_at = bl_now() where id = h.id;
    v_ap := bl_ind_approval(h.id, null);
    perform bl_event(h.user_id, 'ind_low_approval', 'Low approval: ' || o.name,
      'Only ' || (v_ap->>'pct') || '% of ' || (v_ap->>'votes') || ' people approve of you. Talk to the city: post a statement and use your levers wisely. An admin can see this.',
      jsonb_build_object('office', o.id));
  end if;
  return jsonb_build_object('message', case when coalesce(p_up, true) then 'Thumbs up sent.' else 'Thumbs down sent.' end, 'approval', bl_ind_approval(h.id, v_uid));
end $$;

-- one short official statement a day: shown in the Industry offices list and as a public notice
create or replace function public.ind_statement(p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); h ind_holders; o ind_offices; v_body text; v_next timestamptz; v_name text;
begin
  perform bl_ind_tick(); perform bl_ind_guard();
  select * into h from ind_holders where user_id = v_uid and status = 'active' and term_end > bl_now() for update;
  if not found then raise exception 'Only an office holder posts statements.' using errcode = 'P0001', hint = 'not_holder'; end if;
  select * into o from ind_offices where id = h.office_id;
  v_next := h.last_statement_at + make_interval(hours => bl_pol_num('offices.statement_cooldown_hours', 24)::int);
  if h.last_statement_at is not null and v_next > bl_now() then
    raise exception 'One statement a day. Next one in %.', bl_pol_wait(v_next - bl_now()) using errcode = 'P0001', hint = 'cooldown';
  end if;
  v_body := bl_pol_moderate(p_body, 10, bl_pol_num('offices.statement_max_len', 160)::int, 'statement');
  select username into v_name from profiles where id = v_uid;
  insert into ind_statements (holder_id, office_id, user_id, body, created_at) values (h.id, o.id, v_uid, v_body, bl_now());
  update ind_holders set last_statement_at = bl_now() where id = h.id;
  perform bl_ind_notice(v_uid, 'Official statement: ' || o.name, '@' || v_name || ': ' || v_body);
  return jsonb_build_object('message', 'Statement posted.');
end $$;

create or replace function public.ind_resign() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); h ind_holders; o ind_offices;
begin
  perform bl_ind_tick();
  select * into h from ind_holders where user_id = v_uid and status = 'active' and term_end > bl_now() for update;
  if not found then raise exception 'You hold no industry office.' using errcode = 'P0001', hint = 'not_holder'; end if;
  select * into o from ind_offices where id = h.office_id;
  perform bl_ind_end(h.id, 'resigned', 'You resigned.', v_uid, true);
  return jsonb_build_object('message', 'You resigned as ' || o.name || '. Your settings went back to normal.');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Admin RPCs (every action audited in admin_audit and alerts the player)
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_ind_overview() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_now timestamptz;
begin
  perform bl_admin_guard();
  perform bl_ind_tick();
  v_now := bl_now();
  return jsonb_build_object('now', v_now, 'enabled', bl_ind_on(),
    'offices', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'industry', o.industry, 'title', o.title, 'icon', o.icon, 'salary_per_day', o.salary_per_day,
        'term_days', o.term_days, 'active', o.active, 'frozen', o.frozen, 'max_changes_per_day', o.max_changes_per_day, 'max_total_drift_pct', o.max_total_drift_pct,
        'election_enabled', o.election_enabled, 'seats', o.seats,
        'holder', (select jsonb_build_object('id', h.id, 'user_id', h.user_id, 'username', p.username, 'term_start', h.term_start, 'term_end', h.term_end, 'source', h.source,
                      'salary_paid', h.salary_paid, 'last_seen', p.last_seen, 'approval', bl_ind_approval(h.id, null), 'low_approval', bl_ind_low(h.id),
                      'changes_today', (select count(*) from ind_changes c where c.office_id = o.id and c.kind = 'change' and c.created_at > v_now - interval '24 hours'))
                     from ind_holders h join profiles p on p.id = h.user_id where h.office_id = o.id and h.status = 'active' and h.term_end > v_now limit 1),
        'levers', coalesce((select jsonb_agg(bl_ind_lever_json(l, o) || jsonb_build_object('active', l.active) order by l.sort, l.id) from ind_levers l where l.office_id = o.id), '[]'::jsonb))
        order by o.sort, o.id) from ind_offices o), '[]'::jsonb),
    'applicants', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'office_id', a.office_id, 'office', o.name, 'user_id', a.user_id, 'username', p.username, 'pitch', a.pitch,
        'created_at', a.created_at, 'account_days', round((extract(epoch from (v_now - p.created_at)) / 86400.0)::numeric, 1), 'level', p.job_level,
        'last_seen', p.last_seen, 'holds_office', bl_ind_holds_any(a.user_id)) order by a.created_at, a.id)
        from ind_applications a join ind_offices o on o.id = a.office_id join profiles p on p.id = a.user_id where a.status = 'pending'), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'office', o.name, 'username', p.username, 'status', x.status, 'term_start', x.term_start, 'ended_at', x.ended_at,
        'ended_reason', x.ended_reason, 'salary_paid', x.salary_paid) order by x.id desc)
        from (select * from ind_holders where status <> 'active' order by id desc limit 15) x join ind_offices o on o.id = x.office_id left join profiles p on p.id = x.user_id), '[]'::jsonb),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'office', o.name, 'lever', l.label, 'unit', l.unit, 'kind', c.kind, 'old', c.old_value, 'new', c.new_value,
        'reason', c.reason, 'announced', c.announced, 'at', c.created_at, 'by', (select p.username from profiles p where p.id = c.user_id)) order by c.id desc)
        from (select * from ind_changes order by id desc limit 60) c join ind_levers l on l.id = c.lever_id join ind_offices o on o.id = c.office_id), '[]'::jsonb));
end $$;

create or replace function public.admin_ind_appoint(p_office text, p_username text, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); t profiles; o ind_offices; v_id bigint; v_name text := btrim(coalesce(p_username, ''));
begin
  perform bl_ind_tick();
  select * into o from ind_offices where id = p_office;
  if not found then raise exception 'Pick an office.' using errcode = 'P0001', hint = 'bad_office'; end if;
  select * into t from profiles where lower(username) = lower(regexp_replace(v_name, '^@', '')) and home_chosen and not banned;
  if not found then raise exception 'No player with that username.' using errcode = 'P0001', hint = 'no_player'; end if;
  v_id := bl_ind_install(o.id, t.id, v_admin, case when exists (select 1 from ind_applications where user_id = t.id and office_id = o.id and status = 'pending') then 'application' else 'admin' end);
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'ind_appoint', t.id, jsonb_build_object('holder', v_id, 'office', o.id, 'reason', left(coalesce(p_reason, ''), 200)));
  return jsonb_build_object('id', v_id, 'message', '@' || t.username || ' is now ' || o.name || '.');
end $$;

-- accept (= appoint), reject, or remove an applicant
create or replace function public.admin_ind_application(p_application bigint, p_action text, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); a ind_applications; o ind_offices; v_note text := left(btrim(coalesce(p_note, '')), 200); v_id bigint; v_name text;
begin
  select * into a from ind_applications where id = p_application and status = 'pending' for update;
  if not found then raise exception 'That application is no longer waiting.' using errcode = 'P0001', hint = 'gone'; end if;
  select * into o from ind_offices where id = a.office_id;
  select username into v_name from profiles where id = a.user_id;
  if p_action = 'accept' then
    v_id := bl_ind_install(a.office_id, a.user_id, v_admin, 'application');
    update ind_applications set note = v_note where id = a.id;
    insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'ind_accept', a.user_id, jsonb_build_object('application', a.id, 'office', o.id, 'holder', v_id));
    return jsonb_build_object('message', '@' || v_name || ' is now ' || o.name || '.');
  elsif p_action in ('reject', 'remove') then
    update ind_applications set status = case when p_action = 'reject' then 'rejected' else 'removed' end, decided_at = bl_now(), decided_by = v_admin, note = v_note where id = a.id;
    perform bl_event(a.user_id, case when p_action = 'reject' then 'ind_rejected' else 'ind_app_removed' end,
      case when p_action = 'reject' then 'Application not accepted' else 'Application removed' end,
      'Your application for ' || o.name || case when p_action = 'reject' then ' was not accepted this time.' else ' was removed by an admin.' end ||
      case when v_note <> '' then ' Note: ' || v_note else '' end, jsonb_build_object('office', o.id));
    insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'ind_' || p_action, a.user_id, jsonb_build_object('application', a.id, 'office', o.id, 'note', v_note));
    return jsonb_build_object('message', '@' || v_name || ' was ' || case when p_action = 'reject' then 'rejected' else 'removed from the applicants' end || '.');
  end if;
  raise exception 'Choose accept, reject or remove.' using errcode = 'P0001', hint = 'bad_action';
end $$;

create or replace function public.admin_ind_remove_holder(p_holder bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); h ind_holders; o ind_offices; v_reason text := left(btrim(coalesce(p_reason, '')), 200);
begin
  select * into h from ind_holders where id = p_holder and status = 'active' for update;
  if not found then raise exception 'That seat is already empty.' using errcode = 'P0001', hint = 'gone'; end if;
  if v_reason = '' then raise exception 'Give a reason (it is kept in the audit log).' using errcode = 'P0001', hint = 'reason'; end if;
  select * into o from ind_offices where id = h.office_id;
  perform bl_ind_end(h.id, 'removed', 'An admin removed you. Reason: ' || v_reason, v_admin, true);
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'ind_remove_holder', h.user_id, jsonb_build_object('holder', h.id, 'office', o.id, 'reason', v_reason));
  return jsonb_build_object('message', 'Removed. Their settings are back to normal.');
end $$;

-- freeze one lever (p_lever) or every lever of an office (p_lever null). The holder gets an alert.
create or replace function public.admin_ind_freeze(p_office text, p_lever text, p_frozen boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); o ind_offices; l ind_levers; h ind_holders;
begin
  select * into o from ind_offices where id = p_office;
  if not found then raise exception 'Pick an office.' using errcode = 'P0001', hint = 'bad_office'; end if;
  if p_lever is null then
    update ind_offices set frozen = coalesce(p_frozen, true) where id = o.id;
  else
    select * into l from ind_levers where id = p_lever and office_id = o.id;
    if not found then raise exception 'Pick a lever of this office.' using errcode = 'P0001', hint = 'bad_lever'; end if;
    update ind_levers set frozen = coalesce(p_frozen, true) where id = l.id;
  end if;
  select * into h from ind_holders where office_id = o.id and status = 'active';
  if found then
    perform bl_event(h.user_id, 'ind_frozen', case when coalesce(p_frozen, true) then 'Settings frozen' else 'Settings unfrozen' end,
      case when p_lever is null then 'An admin ' || case when coalesce(p_frozen, true) then 'froze all your settings' else 'unfroze your settings' end || ' for ' || o.name || '.'
           else 'An admin ' || case when coalesce(p_frozen, true) then 'froze' else 'unfroze' end || ' "' || l.label || '".' end,
      jsonb_build_object('office', o.id));
  end if;
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'ind_freeze', h.user_id, jsonb_build_object('office', o.id, 'lever', p_lever, 'frozen', coalesce(p_frozen, true)));
  return jsonb_build_object('message', case when coalesce(p_frozen, true) then 'Frozen.' else 'Unfrozen.' end);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Patch the live functions (guarded): the title badge, medicine prices, the Admin Content editors
-- ---------------------------------------------------------------------------------------------
-- the badge: an elected office wins, then an industry office, then a bought chief title
select pg_temp.io_patch('public.bl_pol_title(uuid)', 'bl_ind_title(p_uid)', 'bl_chief_title(p_uid))', E'bl_ind_title(p_uid),\n      bl_chief_title(p_uid))');
-- medicine (category health) follows health.price_pct
select pg_temp.io_patch('public.bl_dealer_net(items, text)', 'health.price_pct',
  $m$when p_item.category <> 'vehicle' then coalesce(bl_shop_price(p_item, p_location), p_item.price)$m$,
  $m$when p_item.category = 'health' then (case when bl_pol_num('health.price_pct', 100) = 100 then coalesce(bl_shop_price(p_item, p_location), p_item.price)
         else (round(coalesce(bl_shop_price(p_item, p_location), p_item.price) * bl_pol_num('health.price_pct', 100) / 1000.0) * 10)::bigint end)
    when p_item.category <> 'vehicle' then coalesce(bl_shop_price(p_item, p_location), p_item.price)$m$);
-- Admin -> Content editors
select pg_temp.io_patch('public.bl_admin_table_spec(text)', $m$when 'ind_offices' then$m$, $m$when 'offices' then$m$,
  E'when ''ind_offices'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","industry":"text","title":"text","icon":"text","blurb":"text","salary_per_day":"money","term_days":"num","min_account_days":"num","min_level":"int","election_enabled":"bool","seats":"int","max_changes_per_day":"int","max_total_drift_pct":"num","frozen":"bool","sort":"int","active":"bool"}}\'\n    when ''ind_levers'' then ''{"pk":["id"],"insert":true,"order":"office_id, sort, id",\n      "cols":{"office_id":"text","config_key":"text","label":"text","blurb":"text","unit":"text","band_min":"num","band_max":"num","step":"num","cooldown_hours":"num","direction":"text","effect":"text","frozen":"bool","sort":"int","active":"bool"}}\'\n    when ''offices'' then');

-- ---------------------------------------------------------------------------------------------
-- 9. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and proname like 'bl\_ind\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and proname in ('office_mine', 'ind_tick', 'ind_status', 'ind_apply', 'ind_withdraw', 'ind_set_lever', 'ind_vote', 'ind_statement', 'ind_resign',
                            'admin_ind_overview', 'admin_ind_appoint', 'admin_ind_application', 'admin_ind_remove_holder', 'admin_ind_freeze') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
end $$;
notify pgrst, 'reload schema';
