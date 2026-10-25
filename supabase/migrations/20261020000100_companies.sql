-- Companies (docs/COMPANIES.md): the "Company" phone app. ANY player can open online companies (no map plot, so the 18 map plots
-- being taken no longer blocks anybody), plus "Real business" listings: a real Benin business advertised on the map for real money.
--   1. config `company.*` and `realbiz.*` (game_config; Admin -> Settings -> Company / Real businesses).
--   2. Admin tables: company_industries, company_areas (tiered Benin areas), company_formats (Kiosk / Shop / Store),
--      company_marketing (flyers / radio / influencer), real_biz_slots (generated map spots).
--   3. companies + company_branches (HQ + branches) + company_nights (one row per settled evening) + company_log (news feed).
--   4. Revenue settles ONCE per evening (company.settle_hour, 18 = 6 PM Benin) into the Till, LAZILY on the next read (no cron):
--      bl_co_settle() works out every evening that is due, stops when the till already holds company.max_nights uncollected
--      evenings, and writes NOTHING when no evening is due (polling stays cheap). The player cashes out to the bank
--      (ledger company_income, which counts as earned income for the weekly top earners and the weekly tax).
--      Weekly bills (staff, manager, upkeep) are debited from the till on settle (1/7 each evening): the E4 player_bills list is
--      per-player, autopaid from the bank and blocks assets, which is the wrong shape for a company that lives off its till.
--   5. Rating 1-5 from pricing, staff and marketing consistency; random events (good review, bad review, outage, supplier problem)
--      roll through bl_co_roll() = bl_crime_roll(), so tests force them with bl.test_rand or a 0 / 100 chance.
--   6. Value = company.value_days days of profit after bills. Sell to the system at company.sell_pct of value, or list on the
--      Market (kind 'company', fair-price band in market_settings). Rankings, a public company card (share link /c/<id>).
--   7. Real businesses: a listing like a billboard. real_businesses row -> Paystack (reference BLRB-<hex>, bl_real_biz_paid, the same
--      verify / webhook / refund Edge Functions) -> admin approves (pin goes live on the map from a generated slot, verified badge)
--      or rejects (automatic refund) -> expires after realbiz.days. Admin push on every new submission. No money moves between
--      players and real businesses: the listing is an ad only.
-- Idempotent and safe on a non-empty DB: tables `if not exists`, seeds `on conflict do nothing` (admin edits survive), functions
-- `create or replace`, live functions patched ONLY through a guarded replace on pg_get_functiondef (raises when the marker is
-- missing, skips when already applied; create or replace keeps the grants). Private bl_* helpers are revoked from anon/authenticated.

create or replace function pg_temp.bl_patch1(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n = 0 then raise exception '% : marker not found: %', p_sig, p_marker; end if;
  if v_n > 1 then raise exception '% : marker not unique (% times): %', p_sig, v_n, p_marker; end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('company.enabled', 'true', 'company', 'Companies on',
 'Companies (docs/COMPANIES.md): players can register and run online companies. Off = no new companies, hiring, branches or marketing; cashing out and selling still work.', 'bool', null, null),
('company.reg_fee', '50000', 'company', 'Registration fee',
 'Paid once when a company is registered, on top of the industry setup cost. Money destroyed (ledger company_fee).', 'naira', 0, 100000000),
('company.max_owned', '20', 'company', 'Companies one player can own',
 'No map plot is needed, so this is only an anti-abuse cap. The Market and admin respect it too.', 'number', 1, 200),
('company.max_branches', '4', 'company', 'Extra branches per company',
 'Branches besides the HQ.', 'number', 0, 30),
('company.branch_cost_pct', '60', 'company', 'Branch cost (% of the industry price)',
 'A new branch costs this % of the industry price x the area setup multiplier. It opens as a Kiosk.', 'percent', 0, 1000),
('company.settle_hour', '18', 'company', 'Evening settle hour (Benin time)',
 'Revenue settles once per evening at this hour. 18 = 6 PM.', 'number', 0, 23),
('company.max_nights', '3', 'company', 'Uncollected evenings the till holds',
 'The till stops growing after this many evenings without a cash out, so players have to log in. A Manager adds company.manager_extra_nights.', 'number', 1, 60),
('company.player_night_cap', '1000000', 'company', 'Most sales per player per evening (all companies)',
 'Per-player cap on the total sales across all of a player''s companies in one evening. Extra sales are not counted.', 'naira', 0, 100000000000),
('company.hire_fee_weeks', '1', 'company', 'Hiring fee (weeks of wage)',
 'Hiring staff or a Manager costs this many weeks of their wage up front.', 'number', 0, 12),
('company.manager_wage_mult', '3', 'company', 'Manager wage (x staff wage)',
 'A Manager costs this many times the industry staff wage each week.', 'number', 0, 50),
('company.manager_bonus_pct', '8', 'company', 'Manager auto-run bonus (% demand)',
 'A Manager runs the company when you are away: this % more customers every evening.', 'percent', 0, 200),
('company.manager_extra_nights', '4', 'company', 'Manager: extra uncollected evenings',
 'A Manager lets the till keep growing this many evenings longer.', 'number', 0, 60),
('company.generator_pct', '8', 'company', 'Generator price (% of the industry price)',
 'One-off buy.', 'percent', 0, 1000),
('company.generator_cut_pct', '80', 'company', 'Generator cuts outage loss by (%)',
 'With a generator an outage costs only the rest.', 'percent', 0, 100),
('company.price_cheap_cust', '1.3', 'company', 'Cheap pricing: customers x', 'Customers multiplier when the company prices Cheap.', 'number', 0.1, 5),
('company.price_cheap_ticket', '0.8', 'company', 'Cheap pricing: ticket x', 'What each customer pays when the company prices Cheap (cost of goods stays the same).', 'number', 0.1, 5),
('company.price_premium_cust', '0.75', 'company', 'Premium pricing: customers x', 'Customers multiplier when the company prices Premium.', 'number', 0.1, 5),
('company.price_premium_ticket', '1.35', 'company', 'Premium pricing: ticket x', 'What each customer pays when the company prices Premium.', 'number', 0.1, 5),
('company.demand_base', '0.7', 'company', 'Demand from rating: base', 'Customers multiplier = base + per-star x rating. 0.7 + 0.1 x 3 stars = 1.0.', 'number', 0, 5),
('company.demand_per_star', '0.1', 'company', 'Demand from rating: per star', 'See the base above.', 'number', 0, 5),
('company.cap_base', '0.5', 'company', 'Capacity with no staff', 'A location serves this multiple of its base customers with nobody hired.', 'number', 0, 10),
('company.cap_per_staff', '1.3', 'company', 'Capacity added by full staff', 'Added capacity when every staff slot is filled (scales with the share of slots filled).', 'number', 0, 10),
('company.rating_start', '3', 'company', 'Rating of a new company', 'Stars 1 to 5.', 'number', 1, 5),
('company.rating_speed_pct', '35', 'company', 'Rating moves toward its target by (% a night)', 'How fast the stars follow pricing, staff and marketing.', 'percent', 1, 100),
('company.ev_good_review_pct', '12', 'company', 'Good review chance (% per evening)', 'Rolled once per settled evening.', 'percent', 0, 100),
('company.ev_good_review_boost_pct', '15', 'company', 'Good review adds (% customers that evening)', 'Also lifts the rating for a while.', 'percent', 0, 500),
('company.ev_bad_review_pct', '10', 'company', 'Bad review chance (% per evening)', 'Rolled once per settled evening.', 'percent', 0, 100),
('company.ev_bad_review_cut_pct', '12', 'company', 'Bad review cuts (% customers that evening)', 'Also drags the rating down for a while.', 'percent', 0, 100),
('company.ev_outage_pct', '14', 'company', 'NEPA outage chance (% per evening)', 'Rolled once per settled evening. A generator cuts the loss.', 'percent', 0, 100),
('company.ev_outage_loss_pct', '35', 'company', 'Outage costs (% customers that evening)', 'Light off, customers gone.', 'percent', 0, 100),
('company.ev_supplier_pct', '8', 'company', 'Supplier problem chance (% per evening)', 'Rolled once per settled evening.', 'percent', 0, 100),
('company.ev_supplier_cost_pct', '40', 'company', 'Supplier problem adds (% cost of goods)', 'Goods cost this much more that evening.', 'percent', 0, 500),
('company.value_days', '30', 'company', 'Company value = days of profit', 'Value is this many days of profit after bills (never below the floor).', 'number', 1, 365),
('company.value_floor_pct', '20', 'company', 'Value floor (% of what was invested)', 'A company is never worth less than this share of the registration fee and setup cost.', 'percent', 0, 100),
('company.sell_pct', '50', 'company', 'Sell to the system (% of value)', 'Selling to the system pays this % of the company value. The rest leaves the game. Listing on the Market pays full price minus the Market fee.', 'percent', 0, 100),
('company.keep_nights', '40', 'company', 'Evenings of history kept', 'Older evenings and news are deleted when a company settles.', 'number', 8, 365),
('company.rank_limit', '20', 'company', 'Rankings: companies shown', 'Top companies by sales in the last 7 evenings.', 'number', 5, 100),
('company.shop_enabled', 'false', 'company', 'Player shop (coming soon)', 'Reserved: the "Shop" card in the Company app says coming soon while this is off.', 'bool', null, null),
('realbiz.enabled', 'true', 'realbiz', 'Real business listings on',
 'Real Benin businesses can pay to be shown on the map (docs/COMPANIES.md). Needs payments.enabled too. Off = no new listings or renewals.', 'bool', null, null),
('realbiz.price_kobo', '2500000', 'realbiz', 'Listing price (kobo)',
 'Real money, in KOBO (100 kobo = N1). 2500000 = N25,000. The price is stored on the listing when it is created.', 'number', 10000, 1000000000),
('realbiz.days', '30', 'realbiz', 'Listing runs (days)', 'How long a listing stays on the map after the owner approves it.', 'number', 1, 366),
('realbiz.max_per_area', '6', 'realbiz', 'Live pins per area', 'Most live (and waiting) real-business pins in one area. New listings in a full area are refused.', 'number', 1, 100),
('realbiz.max_per_player', '2', 'realbiz', 'Listings per player', 'Most listings one player can have waiting for review or live at once.', 'number', 1, 20),
('realbiz.max_images', '3', 'realbiz', 'Photos per listing', 'Up to this many product / shop photos (each needs admin approval together with the listing).', 'number', 1, 6),
('realbiz.renew_window_days', '7', 'realbiz', 'Renew window (days before the end)', 'A live listing can be renewed this many days before it ends.', 'number', 1, 60),
('realbiz.report_alert', '1', 'realbiz', 'Notify admins after reports', 'Admins get a notification at this many reports on a listing, then each time the count doubles.', 'number', 1, 100),
('realbiz.contact_email', '"code.devshalom@gmail.com"', 'realbiz', 'Owner contact email', 'Shown in the terms: where businesses and players write about a listing.', 'text', null, null),
('realbiz.terms', '"Only legal businesses. No adult content, gambling, crypto schemes, weapons or drugs."', 'realbiz', 'Terms text', 'Shown on the listing form and the showcase. The business must accept it.', 'text', null, null)
on conflict (key) do nothing;

-- company income is earned money (weekly top earners, the weekly tax, challenge "earn"). Added once: an admin who removes it later stays removed.
do $$
begin
  if not exists (select 1 from public.game_config where key = 'company.earn_seeded') then
    update public.game_config
       set value = to_jsonb(rtrim((value #>> '{}'), ',') || ',company_income')
     where key = 'leaderboard.earn_reasons' and position('company_income' in (value #>> '{}')) = 0;
    insert into public.game_config (key, value, category, label, description, kind)
    values ('company.earn_seeded', 'true', 'company', 'Company income counted as earned (seeded)',
            'Set once by the migration so company_income is in leaderboard.earn_reasons. Leave it.', 'bool');
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.company_industries (
  id            text primary key,
  name          text not null,
  icon          text not null default '🏢',
  blurb         text not null default '',
  price         bigint not null default 100000 check (price >= 0),            -- setup cost at an area with multiplier 1
  base_revenue  bigint not null default 5000 check (base_revenue >= 0),       -- nightly sales of one Kiosk, Fair price, 3 stars, area revenue x1
  ticket        bigint not null default 500 check (ticket > 0),               -- what one customer pays (base customers = base_revenue / ticket)
  cogs_pct      numeric not null default 45 check (cogs_pct >= 0 and cogs_pct <= 95),   -- cost of goods, % of the ticket, per customer
  upkeep_week   bigint not null default 3000 check (upkeep_week >= 0),        -- rent / power per Kiosk per week (x format, x area setup)
  wage_week     bigint not null default 3500 check (wage_week >= 0),          -- one staff member per week
  mkt_mult      numeric not null default 1 check (mkt_mult >= 0),             -- marketing price multiplier for this industry
  req_skill_level int not null default 1 check (req_skill_level >= 1),
  req_cert      text,
  sort          int not null default 100,
  active        boolean not null default true
);
create table if not exists public.company_areas (
  id         text primary key,
  name       text not null,
  tier       int not null default 2 check (tier between 1 and 4),
  setup_mult numeric not null default 1 check (setup_mult > 0),
  rev_mult   numeric not null default 1 check (rev_mult > 0),
  district   text not null default '',
  sort       int not null default 100,
  active     boolean not null default true
);
create table if not exists public.company_formats (
  id          text primary key,
  name        text not null,
  emoji       text not null default '🏪',
  demand_mult numeric not null default 1 check (demand_mult > 0),
  staff_slots int not null default 2 check (staff_slots >= 0),
  upgrade_pct numeric not null default 0 check (upgrade_pct >= 0),            -- cumulative % of industry price x area setup to reach this format
  upkeep_mult numeric not null default 1 check (upkeep_mult >= 0),
  sort        int not null default 100
);
create table if not exists public.company_marketing (
  id        text primary key,
  name      text not null,
  emoji     text not null default '📣',
  price     bigint not null default 1000 check (price >= 0),                  -- at industry mkt_mult 1 and one Kiosk
  boost_pct numeric not null default 20 check (boost_pct >= 0),
  nights    int not null default 1 check (nights >= 1),
  sort      int not null default 100,
  active    boolean not null default true
);

create table if not exists public.companies (
  id              bigserial primary key,
  owner_id        uuid not null references public.profiles(id) on delete cascade,
  name            text not null,
  industry_id     text not null references public.company_industries(id),
  logo            text not null default '🏢',
  color           text not null default '#1f7a3f',
  rating          numeric not null default 3 check (rating >= 1 and rating <= 5),
  rating_adj      numeric not null default 0,
  staff           int not null default 0 check (staff >= 0),
  manager         boolean not null default false,
  generator       boolean not null default false,
  pricing         text not null default 'fair' check (pricing in ('cheap', 'fair', 'premium')),
  boost_pct       numeric not null default 0,
  boost_nights    int not null default 0 check (boost_nights >= 0),
  till            bigint not null default 0 check (till >= 0),
  till_nights     int not null default 0 check (till_nights >= 0),
  settled_through date not null,
  invested        bigint not null default 0,
  lifetime_sales  bigint not null default 0,
  lifetime_net    bigint not null default 0,
  lifetime_cashed bigint not null default 0,
  listed          boolean not null default false,                              -- escrowed on the Market
  source          text not null default 'new' check (source in ('new', 'market', 'admin')),
  created_at      timestamptz not null default now(),
  last_cashout_at timestamptz
);
create unique index if not exists companies_name_uq on public.companies (lower(name));
create index if not exists companies_owner_idx on public.companies (owner_id);

create table if not exists public.company_branches (
  id         bigserial primary key,
  company_id bigint not null references public.companies(id) on delete cascade,
  area_id    text not null references public.company_areas(id),
  format_id  text not null references public.company_formats(id),
  is_hq      boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists company_branches_hq_uq on public.company_branches (company_id) where is_hq;
create unique index if not exists company_branches_area_uq on public.company_branches (company_id, area_id);

create table if not exists public.company_nights (
  company_id bigint not null references public.companies(id) on delete cascade,
  night      date not null,
  customers  int not null default 0,
  sales      bigint not null default 0,
  cogs       bigint not null default 0,
  bills      bigint not null default 0,
  net        bigint not null default 0,
  stars      numeric not null default 3,
  boosted    boolean not null default false,
  capped     boolean not null default false,
  events     text[] not null default '{}',
  primary key (company_id, night)
);
create index if not exists company_nights_night_idx on public.company_nights (night, company_id);

create table if not exists public.company_log (
  id         bigserial primary key,
  company_id bigint not null references public.companies(id) on delete cascade,
  owner_id   uuid not null,
  kind       text not null,
  title      text not null,
  amount     bigint not null default 0,
  data       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists company_log_company_idx on public.company_log (company_id, id desc);

-- generated map spots for real-business pins (like the business plots, but only a pin, never a place)
create table if not exists public.real_biz_slots (
  id      text primary key,
  area_id text not null references public.company_areas(id),
  x       numeric not null check (x between 0 and 1000),
  y       numeric not null check (y between 0 and 1000),
  sort    int not null default 100,
  active  boolean not null default true
);
create index if not exists real_biz_slots_area_idx on public.real_biz_slots (area_id, sort);

create table if not exists public.real_businesses (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid references auth.users(id) on delete set null,
  name          text not null,
  category      text not null default 'other',
  descr         text not null default '',
  logo          text not null default '🏪',
  phone         text,
  whatsapp      text,
  instagram     text,
  website       text,
  address       text not null default '',
  area_id       text not null references public.company_areas(id),
  slot_id       text references public.real_biz_slots(id),
  images        text[] not null default '{}',
  company_id    bigint,                                                       -- optional: the owner's in-game company ("Visit in game")
  terms_at      timestamptz,
  status        text not null default 'awaiting_payment'
                check (status in ('awaiting_payment', 'pending_review', 'live', 'rejected', 'suspended', 'expired', 'removed', 'cancelled')),
  days          int not null default 30 check (days between 1 and 366),
  price_kobo    bigint not null default 0 check (price_kobo >= 0),
  reference     text unique,
  paid_kobo     bigint,
  paid_at       timestamptz,
  pay_raw       jsonb not null default '{}'::jsonb,
  renew_reference text unique,
  renew_price_kobo bigint,
  renew_days    int,
  renewed_refs  text[] not null default '{}',
  renewals      int not null default 0,
  reviewed_by   uuid,
  reviewed_at   timestamptz,
  reject_reason text,
  starts_at     timestamptz,
  ends_at       timestamptz,
  suspended_at  timestamptz,
  refund_status text not null default 'none' check (refund_status in ('none', 'pending', 'processing', 'refunded', 'refund_failed')),
  refund_kobo   bigint,
  refund_at     timestamptz,
  refund_error  text,
  refund_raw    jsonb not null default '{}'::jsonb,
  views         bigint not null default 0,
  taps          bigint not null default 0,
  reports       int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index if not exists real_businesses_slot_uq on public.real_businesses (slot_id) where status in ('pending_review', 'live', 'suspended');
create index if not exists real_businesses_area_idx on public.real_businesses (area_id, status);
create index if not exists real_businesses_owner_idx on public.real_businesses (owner_id, created_at desc);
create index if not exists real_businesses_status_idx on public.real_businesses (status, created_at desc);
create index if not exists real_businesses_live_end_idx on public.real_businesses (ends_at) where status = 'live';

create table if not exists public.real_biz_reports (
  biz_id     uuid not null references public.real_businesses(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  reason     text not null default '',
  created_at timestamptz not null default now(),
  primary key (biz_id, user_id)
);
create table if not exists public.real_biz_counter_log (
  user_id uuid not null references auth.users(id) on delete cascade,
  biz_id  uuid not null,
  kind    text not null check (kind in ('view', 'tap')),
  at      timestamptz not null default now(),
  primary key (user_id, biz_id, kind)
);

-- row level security: everything is read through RPCs; players may read only their own rows
do $$
declare t text;
begin
  foreach t in array array['company_industries', 'company_areas', 'company_formats', 'company_marketing', 'companies', 'company_branches',
                           'company_nights', 'company_log', 'real_biz_slots', 'real_businesses', 'real_biz_reports', 'real_biz_counter_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;
revoke all on sequence public.companies_id_seq, public.company_branches_id_seq, public.company_log_id_seq from public, anon, authenticated;
grant select on public.company_industries, public.company_areas, public.company_formats, public.company_marketing to authenticated;
drop policy if exists company_industries_read on public.company_industries;
create policy company_industries_read on public.company_industries for select to authenticated using (true);
drop policy if exists company_areas_read on public.company_areas;
create policy company_areas_read on public.company_areas for select to authenticated using (true);
drop policy if exists company_formats_read on public.company_formats;
create policy company_formats_read on public.company_formats for select to authenticated using (true);
drop policy if exists company_marketing_read on public.company_marketing;
create policy company_marketing_read on public.company_marketing for select to authenticated using (true);
grant select on public.companies to authenticated;
drop policy if exists companies_own on public.companies;
create policy companies_own on public.companies for select to authenticated using (owner_id = (select auth.uid()));
-- real businesses: the owner reads their own rows, never the payment JSON
grant select (id, owner_id, name, category, descr, logo, phone, whatsapp, instagram, website, address, area_id, slot_id, images, company_id,
              status, days, price_kobo, reference, paid_kobo, paid_at, reviewed_at, reject_reason, starts_at, ends_at, refund_status, refund_kobo,
              views, taps, reports, renewals, created_at)
  on public.real_businesses to authenticated;
grant select, insert, update on public.real_businesses to service_role;
drop policy if exists real_businesses_own on public.real_businesses;
create policy real_businesses_own on public.real_businesses for select to authenticated using (owner_id = (select auth.uid()));

-- the Market takes companies
do $$
declare r record;
begin
  for r in select c.conrelid::regclass as tbl, c.conname from pg_constraint c
            where c.contype = 'c' and c.conrelid in ('public.market_listings'::regclass, 'public.market_settings'::regclass)
              and pg_get_constraintdef(c.oid) like '%kind%' and pg_get_constraintdef(c.oid) like '%land%'
              and pg_get_constraintdef(c.oid) not like '%company%' loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format('alter table %s add constraint %I check (kind in (''item'', ''furniture'', ''car'', ''land'', ''business'', ''company''))', r.tbl, r.conname);
  end loop;
end $$;
insert into public.market_settings (kind, label, enabled, fee_pct, floor_pct, ceiling_pct, sort) values
('company', 'Companies', true, 8, 50, 250, 55)
on conflict (kind) do nothing;

-- storage bucket for the real-business photos: public read (like billboard-ads), players upload only into their own folder
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('real-biz', 'real-biz', true, 1572864, array['image/jpeg', 'image/png', 'image/webp']::text[])
on conflict (id) do update set name = excluded.name, public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists real_biz_upload_own on storage.objects;
create policy real_biz_upload_own on storage.objects for insert to authenticated
  with check (bucket_id = 'real-biz' and (storage.foldername(name))[1] = auth.uid()::text
              and array_length(storage.foldername(name), 1) = 1 and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp'));
drop policy if exists real_biz_read_own on storage.objects;
create policy real_biz_read_own on storage.objects for select to authenticated
  using (bucket_id = 'real-biz' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists real_biz_delete_unused on storage.objects;
create policy real_biz_delete_unused on storage.objects for delete to authenticated
  using (bucket_id = 'real-biz' and (storage.foldername(name))[1] = auth.uid()::text
         and not exists (select 1 from public.real_businesses b
                          where storage.objects.name = any (b.images) and b.status in ('pending_review', 'live', 'suspended')));

-- ---------------------------------------------------------------------------------------------
-- 3. Seeds (admin edits survive: on conflict do nothing)
-- ---------------------------------------------------------------------------------------------
-- base_revenue = base customers x ticket. Tuned so a staffed Kiosk in a mid area at Fair price pays back in about 50 days.
insert into public.company_industries (id, name, icon, blurb, price, base_revenue, ticket, cogs_pct, upkeep_week, wage_week, mkt_mult, req_skill_level, req_cert, sort) values
('food_spot', 'Food spot', '🍲', 'Jollof, pepper soup and small chops. Low cost, quick customers: the easiest way to start.', 90000, 5000, 500, 45, 3000, 3500, 0.3, 1, null, 10),
('salon', 'Salon & barbing', '✂️', 'Fresh cuts, braids and gist. Loyal customers and low cost of goods.', 240000, 8400, 600, 25, 6000, 6000, 0.6, 1, null, 20),
('provisions', 'Provisions store', '🛒', 'Noodles, drinks, soap and everything the street needs. Many customers, thin margins.', 480000, 30600, 900, 60, 10000, 8000, 1.2, 1, null, 30),
('fashion', 'Fashion label', '👗', 'Ankara, native and owambe fits. Needs an eye for business.', 900000, 45000, 1500, 50, 18000, 12000, 2.2, 2, null, 40),
('events', 'Events & owambe', '🎪', 'Hall bookings, DJs and decor. Big tickets, fewer customers.', 1200000, 48000, 3000, 40, 25000, 16000, 2.9, 2, null, 50),
('pharmacy', 'Pharmacy', '💊', 'A trusted counter for drugs and first aid. Needs a business head or a certificate.', 1800000, 96000, 2000, 55, 30000, 20000, 4.3, 3, 'accounting,business_mgmt', 60),
('dispatch', 'Dispatch & logistics', '🛵', 'Riders, vans and parcels all over Benin. Volume business.', 3000000, 127500, 1500, 45, 40000, 28000, 7, 3, null, 70),
('tech_startup', 'Tech startup', '💻', 'Apps, software and clients paying in dollars. The biggest upside, the highest bar.', 6000000, 168000, 4000, 20, 80000, 50000, 13.4, 4, 'business_mgmt', 80)
on conflict (id) do nothing;

-- Benin areas: tier 1 outskirts, 2 mid, 3 upscale, 4 premium. district = the map district it sits in
insert into public.company_areas (id, name, tier, setup_mult, rev_mult, district, sort) values
('ikpoba_hill', 'Ikpoba Hill', 1, 0.8, 0.85, 'ikpoba_hill', 10),
('uselu', 'Uselu', 1, 0.85, 0.9, 'uselu', 20),
('ekenwan', 'Ekenwan', 1, 0.8, 0.85, 'ekenwan', 30),
('ugbowo', 'Ugbowo', 2, 1.0, 1.0, 'ugbowo', 40),
('new_benin', 'New Benin', 2, 1.0, 1.0, 'new_benin', 50),
('sakponba', 'Sakponba', 2, 1.05, 1.05, 'sakponba', 60),
('ring_road', 'Ring Road', 2, 1.2, 1.2, 'oredo', 70),
('gra', 'GRA', 3, 1.6, 1.5, 'gra', 80),
('airport_rd', 'Airport Rd', 3, 1.5, 1.4, 'airport_rd', 90),
('sapele_rd', 'Sapele Rd', 3, 1.45, 1.35, 'sapele_rd', 100),
('gra_phase2', 'GRA Phase 2 (Government House area)', 4, 2.4, 2.0, 'gra', 110)
on conflict (id) do nothing;

insert into public.company_formats (id, name, emoji, demand_mult, staff_slots, upgrade_pct, upkeep_mult, sort) values
('kiosk', 'Kiosk', '🛖', 1.0, 2, 0, 1.0, 10),
('shop', 'Shop', '🏪', 1.8, 5, 50, 2.0, 20),
('store', 'Store', '🏬', 3.0, 9, 100, 3.5, 30)
on conflict (id) do nothing;

-- price is at industry multiplier 1 and one Kiosk: it grows with the industry and with the size of the company
insert into public.company_marketing (id, name, emoji, price, boost_pct, nights, sort) values
('flyers', 'Flyers', '📄', 1200, 20, 1, 10),
('radio', 'Radio jingle', '📻', 4000, 35, 2, 20),
('influencer', 'Influencer shout-out', '🤳', 10000, 60, 3, 30)
on conflict (id) do nothing;

-- generated real-business slots: 8 per area on rings around the area centre, 34+ units from every place and from each other
do $$
declare
  a record; v_cx numeric; v_cy numeric; v_n int; v_ang numeric; v_rad numeric; v_x numeric; v_y numeric; k int; r int;
begin
  for a in select * from public.company_areas order by sort loop
    continue when exists (select 1 from public.real_biz_slots where area_id = a.id);
    select avg(x), avg(y) into v_cx, v_cy from public.business_plots where area = a.id;
    if v_cx is null then
      select avg(x), avg(y) into v_cx, v_cy from public.locations where district = a.district and private_home_owner_id is null;
    end if;
    if v_cx is null then continue; end if;
    if a.id = 'gra_phase2' then v_cx := v_cx + 28; v_cy := v_cy + 24; end if;
    v_n := 0;
    for r in 1 .. 12 loop
      v_rad := 38 + (r - 1) * 26;
      for k in 0 .. 11 loop
        exit when v_n >= 8;
        v_ang := radians(k * 30 + (r % 2) * 15);
        v_x := round(v_cx + v_rad * cos(v_ang));
        v_y := round(v_cy + v_rad * sin(v_ang));
        continue when v_x < 24 or v_x > 976 or v_y < 24 or v_y > 976;
        continue when exists (select 1 from public.locations l where sqrt(power(l.x - v_x, 2) + power(l.y - v_y, 2)) < 34 and l.private_home_owner_id is null);
        continue when exists (select 1 from public.real_biz_slots s where sqrt(power(s.x - v_x, 2) + power(s.y - v_y, 2)) < 34);
        v_n := v_n + 1;
        insert into public.real_biz_slots (id, area_id, x, y, sort) values ('rb_' || a.id || '_' || v_n, a.id, v_x, v_y, a.sort * 10 + v_n)
        on conflict (id) do nothing;
      end loop;
      exit when v_n >= 8;
    end loop;
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_co_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_co_on() returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = 'company.enabled'), true);
$$;

-- the evening a moment belongs to: the Benin date of the last settle hour that has passed (6 PM by default)
create or replace function public.bl_co_night_at(p_at timestamptz default null) returns date
language sql stable set search_path = public as $$
  select date_trunc('day', (coalesce(p_at, bl_now()) at time zone 'Africa/Lagos') - make_interval(hours => bl_co_num('company.settle_hour', 18)::int))::date;
$$;

-- when the next evening settles
create or replace function public.bl_co_next_settle(p_at timestamptz default null) returns timestamptz
language sql stable set search_path = public as $$
  select ((bl_co_night_at(p_at) + 1)::timestamp + make_interval(hours => bl_co_num('company.settle_hour', 18)::int)) at time zone 'Africa/Lagos';
$$;

-- the one place random events roll (tests force it with bl.test_rand, or with a chance of 0 / 100)
create or replace function public.bl_co_roll(p_pct numeric) returns boolean
language sql volatile set search_path = public as $$
  select bl_crime_roll(p_pct);
$$;

create or replace function public.bl_co_log(p_company bigint, p_owner uuid, p_kind text, p_title text, p_amount bigint default 0, p_data jsonb default '{}'::jsonb) returns void
language sql set search_path = public as $$
  insert into company_log (company_id, owner_id, kind, title, amount, data, created_at)
  values (p_company, p_owner, p_kind, left(p_title, 200), coalesce(p_amount, 0), coalesce(p_data, '{}'::jsonb), bl_now());
$$;

-- the requirement of an industry (Business skill level and / or a certificate): null = fine, otherwise the reason
create or replace function public.bl_co_gate(p_uid uuid, i public.company_industries) returns text
language plpgsql stable set search_path = public as $$
declare v_lvl int; g jsonb;
begin
  if i.req_skill_level > 1 and bl_skill_on() then
    v_lvl := bl_skill_level(p_uid, 'business');
    if v_lvl < i.req_skill_level then
      return 'Needs Business skill level ' || i.req_skill_level || ' (you are level ' || v_lvl || '). Work shifts, hustles and classes to train it.';
    end if;
  end if;
  g := bl_cert_gate(p_uid, i.req_cert);
  if g is not null then return g->>'message'; end if;
  return null;
end $$;

create or replace function public.bl_co_guard(p_me public.profiles, p_write boolean default true) returns void
language plpgsql set search_path = public as $$
begin
  if p_write and not bl_co_on() then
    raise exception 'Companies are closed for now. Check back later.' using errcode = 'P0001', hint = 'company_closed';
  end if;
  if p_me.jailed_until is not null and p_me.jailed_until > bl_now() then
    raise exception 'You dey police cell. Your company can wait until you are out.' using errcode = 'P0001', hint = 'jailed';
  end if;
end $$;

-- staff slots over every branch
create or replace function public.bl_co_slots(p_company bigint) returns int
language sql stable set search_path = public as $$
  select coalesce(sum(f.staff_slots), 0)::int from company_branches b join company_formats f on f.id = b.format_id where b.company_id = p_company;
$$;

-- how big the company is: the sum of its locations' demand multipliers (a Kiosk = 1)
create or replace function public.bl_co_size(p_company bigint) returns numeric
language sql stable set search_path = public as $$
  select coalesce(sum(f.demand_mult), 1) from company_branches b join company_formats f on f.id = b.format_id where b.company_id = p_company;
$$;

-- weekly bills: upkeep of every location + staff wages + manager
create or replace function public.bl_co_week_bills(c public.companies) returns bigint
language plpgsql stable set search_path = public as $$
declare i company_industries; v_up numeric; v_wage numeric;
begin
  select * into i from company_industries where id = c.industry_id;
  select coalesce(sum(i.upkeep_week * f.upkeep_mult * a.setup_mult), 0) into v_up
    from company_branches b join company_formats f on f.id = b.format_id join company_areas a on a.id = b.area_id where b.company_id = c.id;
  v_wage := c.staff * i.wage_week + case when c.manager then i.wage_week * bl_co_num('company.manager_wage_mult', 3) else 0 end;
  return round(v_up + v_wage)::bigint;
end $$;

-- one evening, worked out. p_events = roll the random events; p_rem = how much more sales the player's cap allows.
-- Returns customers, sales, cogs, before_bills, bills, net, events[], capped.
create or replace function public.bl_co_calc(c public.companies, p_events boolean, p_rem numeric default null) returns jsonb
language plpgsql volatile set search_path = public as $$
declare
  i company_industries; r record; v_slots int; v_staff int; v_ratio numeric; v_pc numeric := 1; v_pt numeric := 1; v_boost numeric := 0; v_mgr numeric := 0;
  v_evm numeric := 1; v_supply numeric := 1; v_base numeric; v_rmult numeric; v_dem numeric; v_cap numeric; v_cust numeric;
  v_customers numeric := 0; v_sales numeric := 0; v_cogs numeric := 0; v_bills numeric; v_ev text[] := '{}'; v_capped boolean := false; v_f numeric; v_out numeric;
begin
  select * into i from company_industries where id = c.industry_id;
  v_slots := bl_co_slots(c.id);
  v_staff := least(c.staff, v_slots);
  v_ratio := case when v_slots > 0 then v_staff::numeric / v_slots else 0 end;
  if c.pricing = 'cheap' then
    v_pc := bl_co_num('company.price_cheap_cust', 1.3); v_pt := bl_co_num('company.price_cheap_ticket', 0.8);
  elsif c.pricing = 'premium' then
    v_pc := bl_co_num('company.price_premium_cust', 0.75); v_pt := bl_co_num('company.price_premium_ticket', 1.35);
  end if;
  v_boost := case when c.boost_nights > 0 then c.boost_pct / 100.0 else 0 end;
  v_mgr := case when c.manager then bl_co_num('company.manager_bonus_pct', 8) / 100.0 else 0 end;
  v_rmult := bl_co_num('company.demand_base', 0.7) + bl_co_num('company.demand_per_star', 0.1) * c.rating;
  if p_events then
    if bl_co_roll(bl_co_num('company.ev_good_review_pct', 12)) then
      v_evm := v_evm * (1 + bl_co_num('company.ev_good_review_boost_pct', 15) / 100.0); v_ev := v_ev || 'good_review'::text;
    end if;
    if bl_co_roll(bl_co_num('company.ev_bad_review_pct', 10)) then
      v_evm := v_evm * (1 - bl_co_num('company.ev_bad_review_cut_pct', 12) / 100.0); v_ev := v_ev || 'bad_review'::text;
    end if;
    if bl_co_roll(bl_co_num('company.ev_outage_pct', 14)) then
      v_out := bl_co_num('company.ev_outage_loss_pct', 35) / 100.0 * (1 - case when c.generator then bl_co_num('company.generator_cut_pct', 80) / 100.0 else 0 end);
      v_evm := v_evm * (1 - v_out); v_ev := v_ev || 'outage'::text;
    end if;
    if bl_co_roll(bl_co_num('company.ev_supplier_pct', 8)) then
      v_supply := 1 + bl_co_num('company.ev_supplier_cost_pct', 40) / 100.0; v_ev := v_ev || 'supplier'::text;
    end if;
  end if;
  v_base := i.base_revenue::numeric / i.ticket;
  for r in select f.demand_mult, a.rev_mult from company_branches b join company_formats f on f.id = b.format_id join company_areas a on a.id = b.area_id
            where b.company_id = c.id loop
    v_dem := v_base * r.demand_mult * v_pc * v_rmult * (1 + v_boost) * (1 + v_mgr) * v_evm;
    v_cap := v_base * r.demand_mult * (bl_co_num('company.cap_base', 0.5) + bl_co_num('company.cap_per_staff', 1.3) * v_ratio);
    v_cust := floor(least(v_dem, v_cap));
    v_customers := v_customers + v_cust;
    v_sales := v_sales + v_cust * i.ticket * v_pt * r.rev_mult;
    v_cogs := v_cogs + v_cust * i.ticket * i.cogs_pct / 100.0 * v_supply;
  end loop;
  if p_rem is not null and v_sales > greatest(p_rem, 0) then
    v_f := case when v_sales > 0 then greatest(p_rem, 0) / v_sales else 0 end;
    v_customers := floor(v_customers * v_f); v_cogs := v_cogs * v_f; v_sales := greatest(p_rem, 0); v_capped := true;
  end if;
  v_bills := round(bl_co_week_bills(c) / 7.0);
  return jsonb_build_object('customers', v_customers::int, 'sales', round(v_sales)::bigint, 'cogs', round(v_cogs)::bigint,
    'before_bills', (round(v_sales) - round(v_cogs))::bigint, 'bills', v_bills::bigint,
    'net', (round(v_sales) - round(v_cogs) - v_bills)::bigint, 'events', to_jsonb(v_ev), 'capped', v_capped,
    'staff_ratio', v_ratio, 'rating_mult', v_rmult);
end $$;

-- the stars an evening aims at: pricing, staff and marketing consistency (+ the memory of reviews)
create or replace function public.bl_co_rating_target(c public.companies, p_boosted_recent int) returns numeric
language plpgsql stable set search_path = public as $$
declare v_slots int := bl_co_slots(c.id); v_ratio numeric; v_price numeric; v_staff numeric; v_mkt numeric;
begin
  v_ratio := case when v_slots > 0 then least(c.staff, v_slots)::numeric / v_slots else 0 end;
  v_price := case c.pricing when 'cheap' then 0.5 when 'premium' then -0.6 + 0.6 * least(1, v_ratio * 2) else 0 end;
  v_staff := least(0.5, -0.7 + 2.4 * v_ratio);
  v_mkt := 0.6 * least(1, p_boosted_recent / 4.0);
  return greatest(1, least(5, 3 + v_price + v_staff + v_mkt + c.rating_adj));
end $$;

-- about 30 days of profit after bills (the last 7 evenings, or tonight's estimate for a new company), never under the floor
create or replace function public.bl_co_value(c public.companies) returns bigint
language plpgsql set search_path = public as $$
declare v_avg numeric; v_n int;
begin
  select avg(net), count(*) into v_avg, v_n from (select net from company_nights where company_id = c.id order by night desc limit 7) x;
  if coalesce(v_n, 0) = 0 then v_avg := (bl_co_calc(c, false, null)->>'net')::numeric; end if;
  return greatest(round(greatest(v_avg, 0) * bl_co_num('company.value_days', 30)),
                  floor(c.invested * bl_co_num('company.value_floor_pct', 20) / 100.0))::bigint;
end $$;

-- pay: bank first, then cash (same helper as the map businesses, reused)
-- (bl_biz_pay raises "Not enough money" with hint not_enough_cash)

-- ---------------------------------------------------------------------------------------------
-- 5. Settlement (lazy: runs on every read, cash out and change; writes NOTHING when no evening is due)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_co_settle(p_id bigint, p_notify boolean default true) returns public.companies
language plpgsql security definer set search_path = public as $$
declare
  c companies; v_cur date := bl_co_night_at(); v_cap int; v_d date; v_calc jsonb; v_rem numeric; v_pcap numeric := bl_co_num('company.player_night_cap', 1000000);
  v_boosted boolean; v_recent int; v_target numeric; v_speed numeric := bl_co_num('company.rating_speed_pct', 35) / 100.0; v_ev text; v_lost int := 0; v_n int := 0;
  v_net bigint; v_keep int := bl_co_num('company.keep_nights', 40)::int; v_first date; v_sales bigint := 0; v_netsum bigint := 0; v_adj numeric;
begin
  select * into c from companies where id = p_id;
  if not found then return null; end if;
  if c.listed or c.settled_through >= v_cur then return c; end if;      -- nothing due: no lock, no write
  select * into c from companies where id = p_id for update;
  if not found then return null; end if;
  if c.listed or c.settled_through >= v_cur then return c; end if;
  v_cap := bl_co_num('company.max_nights', 3)::int + case when c.manager then bl_co_num('company.manager_extra_nights', 4)::int else 0 end;
  v_first := greatest(c.settled_through + 1, v_cur - 59);
  for v_d in select d::date from generate_series(v_first::timestamp, v_cur::timestamp, interval '1 day') d loop
    v_boosted := c.boost_nights > 0;
    if c.till_nights < v_cap then
      select coalesce(sum(n.sales), 0) into v_rem from company_nights n join companies o on o.id = n.company_id
       where o.owner_id = c.owner_id and n.night = v_d and n.company_id <> c.id;
      v_calc := bl_co_calc(c, true, v_pcap - v_rem);
      -- reviews colour the stars for a while
      v_adj := c.rating_adj;
      for v_ev in select jsonb_array_elements_text(v_calc->'events') loop
        if v_ev = 'good_review' then v_adj := v_adj + 0.5; end if;
        if v_ev = 'bad_review' then v_adj := v_adj - 0.5; end if;
      end loop;
      c.rating_adj := v_adj;
      select count(*) into v_recent from company_nights where company_id = c.id and night > v_d - 7 and night < v_d and boosted;
      v_target := bl_co_rating_target(c, v_recent + case when v_boosted then 1 else 0 end);
      c.rating := round(greatest(1, least(5, c.rating + (v_target - c.rating) * v_speed)), 2);
      c.rating_adj := round(c.rating_adj * 0.5, 3);
      v_net := (v_calc->>'net')::bigint;
      c.till := greatest(0, c.till + v_net);
      c.till_nights := c.till_nights + 1;
      c.lifetime_sales := c.lifetime_sales + (v_calc->>'sales')::bigint;
      c.lifetime_net := c.lifetime_net + v_net;
      v_sales := v_sales + (v_calc->>'sales')::bigint; v_netsum := v_netsum + v_net; v_n := v_n + 1;
      insert into company_nights (company_id, night, customers, sales, cogs, bills, net, stars, boosted, capped, events)
      values (c.id, v_d, (v_calc->>'customers')::int, (v_calc->>'sales')::bigint, (v_calc->>'cogs')::bigint, (v_calc->>'bills')::bigint, v_net,
              c.rating, v_boosted, (v_calc->>'capped')::boolean, array(select jsonb_array_elements_text(v_calc->'events')))
      on conflict (company_id, night) do nothing;
      perform bl_co_log(c.id, c.owner_id, 'night', 'Evening ' || to_char(v_d, 'DD Mon') || ': ' || (v_calc->>'customers') || ' customers, ' || bl_naira((v_calc->>'sales')::bigint)
                        || ' sales, ' || bl_naira(v_net) || ' after bills', v_net, jsonb_build_object('night', v_d));
      for v_ev in select jsonb_array_elements_text(v_calc->'events') loop
        perform bl_co_log(c.id, c.owner_id, 'ev_' || v_ev,
          case v_ev when 'good_review' then 'Good review: a customer posted about you, more people came'
                    when 'bad_review' then 'Bad review: a customer no gree, fewer people came'
                    when 'outage' then case when c.generator then 'NEPA took light, your generator saved the evening' else 'NEPA took light, customers left' end
                    else 'Supplier problem: goods cost more tonight' end,
          0, jsonb_build_object('night', v_d, 'event', v_ev));
      end loop;
      if v_calc->>'capped' = 'true' then
        perform bl_co_log(c.id, c.owner_id, 'capped', 'Your sales hit the per-player evening cap, so the rest was not counted', 0, jsonb_build_object('night', v_d));
      end if;
    else
      v_lost := v_lost + 1;
    end if;
    if c.boost_nights > 0 then
      c.boost_nights := c.boost_nights - 1;
      if c.boost_nights = 0 then c.boost_pct := 0; end if;
    end if;
  end loop;
  if v_lost > 0 then
    perform bl_co_log(c.id, c.owner_id, 'till_full', 'Till full: ' || v_lost || ' evening' || case when v_lost = 1 then '' else 's' end || ' of sales were lost. Cash out more often.', 0, jsonb_build_object('lost', v_lost));
    if p_notify then
      perform bl_event(c.owner_id, 'company_till_full', c.name || ': till full',
        'Your till only keeps ' || v_cap || ' evenings. ' || v_lost || ' evening' || case when v_lost = 1 then '' else 's' end || ' of sales were lost. Open the Company app and cash out.',
        jsonb_build_object('company', c.id, 'lost', v_lost));
    end if;
  end if;
  update companies set rating = c.rating, rating_adj = c.rating_adj, till = c.till, till_nights = c.till_nights, boost_nights = c.boost_nights, boost_pct = c.boost_pct,
         lifetime_sales = c.lifetime_sales, lifetime_net = c.lifetime_net, settled_through = v_cur
   where id = c.id returning * into c;
  delete from company_nights where company_id = c.id and night < v_cur - v_keep;
  delete from company_log where company_id = c.id and created_at < bl_now() - make_interval(days => v_keep);
  return c;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Cards (JSON for the app)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_co_card(c public.companies, p_log boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  i company_industries; v_now timestamptz := bl_now(); v_cur date := bl_co_night_at(); v_branches jsonb := '[]'::jsonb; r record; v_nf company_formats; v_cost bigint;
  v_slots int := bl_co_slots(c.id); v_est jsonb; v_last jsonb; v_cap int; v_mk jsonb := '[]'::jsonb; m record; v_size numeric := bl_co_size(c.id); v_hq text;
  v_week bigint; v_value bigint; v_nights jsonb; v_up numeric;
begin
  select * into i from company_industries where id = c.industry_id;
  v_cap := bl_co_num('company.max_nights', 3)::int + case when c.manager then bl_co_num('company.manager_extra_nights', 4)::int else 0 end;
  for r in select b.id, b.area_id, b.format_id, b.is_hq, a.name as area_name, a.tier, a.setup_mult, a.rev_mult, f.name as fname, f.emoji, f.staff_slots, f.demand_mult, f.upgrade_pct, f.sort as fsort
             from company_branches b join company_areas a on a.id = b.area_id join company_formats f on f.id = b.format_id
            where b.company_id = c.id order by b.is_hq desc, b.id loop
    select * into v_nf from company_formats where sort > r.fsort order by sort limit 1;
    v_cost := case when v_nf.id is null then null else round(i.price * (v_nf.upgrade_pct - r.upgrade_pct) / 100.0 * r.setup_mult)::bigint end;
    v_up := i.upkeep_week * (select upkeep_mult from company_formats where id = r.format_id) * r.setup_mult;
    if r.is_hq then v_hq := r.area_name; end if;
    v_branches := v_branches || jsonb_build_array(jsonb_build_object('id', r.id, 'area', r.area_id, 'area_name', r.area_name, 'tier', r.tier, 'rev_mult', r.rev_mult,
      'format', r.format_id, 'format_name', r.fname, 'emoji', r.emoji, 'staff_slots', r.staff_slots, 'is_hq', r.is_hq, 'upkeep_week', round(v_up)::bigint,
      'next_format', v_nf.id, 'next_name', v_nf.name, 'next_cost', v_cost));
  end loop;
  for m in select * from company_marketing where active order by sort, id loop
    v_mk := v_mk || jsonb_build_array(jsonb_build_object('id', m.id, 'name', m.name, 'emoji', m.emoji, 'boost_pct', m.boost_pct, 'nights', m.nights,
      'cost', greatest(100, round(m.price * i.mkt_mult * v_size))::bigint));
  end loop;
  v_est := bl_co_calc(c, false, null);
  select jsonb_build_object('night', night, 'customers', customers, 'sales', sales, 'cogs', cogs, 'before_bills', sales - cogs, 'bills', bills, 'net', net,
                            'stars', stars, 'events', events, 'boosted', boosted, 'capped', capped)
    into v_last from company_nights where company_id = c.id order by night desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('night', night, 'sales', sales, 'net', net, 'customers', customers) order by night), '[]'::jsonb)
    into v_nights from (select * from company_nights where company_id = c.id order by night desc limit 7) x;
  v_week := bl_co_week_bills(c);
  v_value := bl_co_value(c);
  return jsonb_build_object(
    'id', c.id, 'name', c.name, 'logo', c.logo, 'color', c.color, 'industry', i.id, 'industry_name', i.name, 'icon', i.icon,
    'hq_area', v_hq, 'branches', v_branches,
    'stars', round(c.rating)::int, 'rating', c.rating, 'pricing', c.pricing,
    'staff', c.staff, 'staff_slots', v_slots, 'wage', i.wage_week, 'hire_fee', round(i.wage_week * bl_co_num('company.hire_fee_weeks', 1))::bigint,
    'manager', c.manager, 'manager_wage', round(i.wage_week * bl_co_num('company.manager_wage_mult', 3))::bigint,
    'manager_fee', round(i.wage_week * bl_co_num('company.manager_wage_mult', 3) * bl_co_num('company.hire_fee_weeks', 1))::bigint,
    'manager_bonus_pct', bl_co_num('company.manager_bonus_pct', 8), 'manager_extra_nights', bl_co_num('company.manager_extra_nights', 4)::int,
    'generator', c.generator, 'generator_cost', round(i.price * bl_co_num('company.generator_pct', 8) / 100.0)::bigint,
    'generator_cut_pct', bl_co_num('company.generator_cut_pct', 80),
    'boost_pct', case when c.boost_nights > 0 then c.boost_pct else 0 end, 'boost_nights', c.boost_nights, 'marketing', v_mk,
    'till', c.till, 'till_nights', c.till_nights, 'cap_nights', v_cap, 'full', c.till_nights >= v_cap,
    'next_settle_at', bl_co_next_settle(v_now), 'night', v_cur, 'due', c.settled_through < v_cur,
    'last', v_last, 'nights', v_nights,
    'tonight', jsonb_build_object('customers', v_est->'customers', 'sales', v_est->'sales', 'before_bills', v_est->'before_bills', 'after_bills', v_est->'net',
                                  'bills', v_est->'bills'),
    'week_bills', v_week, 'value', v_value, 'sell_value', floor(v_value * bl_co_num('company.sell_pct', 50) / 100.0)::bigint,
    'invested', c.invested, 'lifetime_sales', c.lifetime_sales, 'lifetime_net', c.lifetime_net, 'lifetime_cashed', c.lifetime_cashed,
    'listed', c.listed, 'created_at', c.created_at, 'share', 'https://playbeninlife.app/c/' || c.id,
    'max_branches', bl_co_num('company.max_branches', 4)::int, 'branch_cost', round(i.price * bl_co_num('company.branch_cost_pct', 60) / 100.0)::bigint,
    'log', case when p_log then coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'title', x.title, 'amount', x.amount, 'at', x.created_at) order by x.id desc)
                                            from (select * from company_log where company_id = c.id order by id desc limit 30) x), '[]'::jsonb) end);
end $$;

-- lock + load one of my companies, settled
create or replace function public.bl_co_mine(p_uid uuid, p_id bigint, p_allow_listed boolean default false) returns public.companies
language plpgsql security definer set search_path = public as $$
declare c companies;
begin
  select * into c from companies where id = p_id and owner_id = p_uid for update;
  if not found then
    raise exception 'That company no dey your name.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  if c.listed and not p_allow_listed then
    raise exception 'That company dey for the Market. Take it down first.' using errcode = 'P0001', hint = 'listed';
  end if;
  return bl_co_settle(c.id);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_co_logo_ok(p_logo text) returns boolean
language sql immutable as $$
  select p_logo is not null and char_length(p_logo) between 1 and 14 and p_logo !~ '[A-Za-z0-9<>&"''\\/ ]'
$$;

-- one status call per open app: my companies (settled), the catalog and the rules
create or replace function public.company_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); r record; c companies; v_cards jsonb := '[]'::jsonb; v_ind jsonb; v_area jsonb; v_fmt jsonb;
begin
  for r in select id from companies where owner_id = v_uid order by id loop
    c := bl_co_settle(r.id);
    v_cards := v_cards || jsonb_build_array(bl_co_card(c, true));
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'icon', i.icon, 'blurb', i.blurb, 'price', i.price, 'base_revenue', i.base_revenue,
           'ticket', i.ticket, 'cogs_pct', i.cogs_pct, 'upkeep_week', i.upkeep_week, 'wage_week', i.wage_week, 'req_skill_level', i.req_skill_level,
           'req_cert', i.req_cert, 'req_cert_text', case when i.req_cert is null then null else bl_cert_need_text(i.req_cert) end,
           'gate', bl_co_gate(v_uid, i), 'met', bl_co_gate(v_uid, i) is null) order by i.sort, i.id), '[]'::jsonb)
    into v_ind from company_industries i where i.active;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'tier', a.tier, 'setup_mult', a.setup_mult, 'rev_mult', a.rev_mult, 'district', a.district)
                            order by a.tier, a.sort, a.id), '[]'::jsonb) into v_area from company_areas a where a.active;
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'emoji', f.emoji, 'demand_mult', f.demand_mult, 'staff_slots', f.staff_slots,
                            'upgrade_pct', f.upgrade_pct, 'upkeep_mult', f.upkeep_mult) order by f.sort, f.id), '[]'::jsonb) into v_fmt from company_formats f;
  return jsonb_build_object(
    'enabled', bl_co_on(), 'companies', v_cards, 'industries', v_ind, 'areas', v_area, 'formats', v_fmt,
    'reg_fee', bl_co_num('company.reg_fee', 50000)::bigint, 'max_owned', bl_co_num('company.max_owned', 20)::int,
    'owned', (select count(*) from companies where owner_id = v_uid), 'skill_level', bl_skill_level(v_uid, 'business'),
    'night', bl_co_night_at(), 'next_settle_at', bl_co_next_settle(), 'settle_hour', bl_co_num('company.settle_hour', 18)::int,
    'max_nights', bl_co_num('company.max_nights', 3)::int, 'player_night_cap', bl_co_num('company.player_night_cap', 1000000)::bigint,
    'sell_pct', bl_co_num('company.sell_pct', 50), 'shop_enabled', coalesce((select (value #>> '{}')::boolean from game_config where key = 'company.shop_enabled'), false),
    'pricing', jsonb_build_object('cheap', jsonb_build_array(bl_co_num('company.price_cheap_cust', 1.3), bl_co_num('company.price_cheap_ticket', 0.8)),
                                  'fair', jsonb_build_array(1, 1),
                                  'premium', jsonb_build_array(bl_co_num('company.price_premium_cust', 0.75), bl_co_num('company.price_premium_ticket', 1.35))));
end $$;

create or replace function public.company_register(p_name text, p_industry text, p_logo text, p_color text, p_area text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; i company_industries; a company_areas; v_name text; v_fee bigint; v_setup bigint; v_have bigint; c companies; v_gate text;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_co_guard(v_me);
  select * into i from company_industries where id = p_industry and active;
  if not found then
    raise exception 'Pick what kind of company you want to run.' using errcode = 'P0001', hint = 'bad_industry';
  end if;
  select * into a from company_areas where id = p_area and active;
  if not found then
    raise exception 'Pick an area for your head office.' using errcode = 'P0001', hint = 'bad_area';
  end if;
  v_gate := bl_co_gate(v_uid, i);
  if v_gate is not null then
    raise exception '%', v_gate using errcode = 'P0001', hint = 'requirement';
  end if;
  if (select count(*) from companies where owner_id = v_uid) >= bl_co_num('company.max_owned', 20) then
    raise exception 'You already own % companies. That is the limit.', bl_co_num('company.max_owned', 20)::int using errcode = 'P0001', hint = 'max_owned';
  end if;
  v_name := left(bl_chat_clean(coalesce(p_name, '')), 28);
  if char_length(v_name) < 3 then
    raise exception 'Give your company a name of at least 3 letters.' using errcode = 'P0001', hint = 'bad_name';
  end if;
  if v_name ~ '[<>]' or bl_chat_mask(v_name) <> v_name or not bl_rb_text_ok(v_name) then
    raise exception 'Choose a cleaner name for your company (no rude words, no real politicians or parties).' using errcode = 'P0001', hint = 'bad_name';
  end if;
  if exists (select 1 from companies where lower(name) = lower(v_name)) then
    raise exception 'Somebody already owns a company called "%". Pick another name.', v_name using errcode = 'P0001', hint = 'name_taken';
  end if;
  if not bl_co_logo_ok(coalesce(p_logo, '🏢')) then
    raise exception 'Pick an emoji for your logo.' using errcode = 'P0001', hint = 'bad_logo';
  end if;
  if coalesce(p_color, '#1f7a3f') !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Pick a colour from the list.' using errcode = 'P0001', hint = 'bad_color';
  end if;
  v_fee := bl_co_num('company.reg_fee', 50000)::bigint;
  v_setup := (round(i.price * a.setup_mult / 10.0) * 10)::bigint;
  select cash + greatest(bank, 0) into v_have from profiles where id = v_uid;
  if v_have < v_fee + v_setup then
    raise exception 'Not enough money. Registration % plus setup % is % and you have %.', bl_naira(v_fee), bl_naira(v_setup), bl_naira(v_fee + v_setup), bl_naira(v_have)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  perform bl_biz_pay(v_me, v_fee, 'company_fee', jsonb_build_object('label', 'Company registration: ' || v_name));
  perform bl_biz_pay(v_me, v_setup, 'company_setup', jsonb_build_object('label', 'Company setup: ' || v_name || ' (' || i.name || ', ' || a.name || ')'));
  begin
    insert into companies (owner_id, name, industry_id, logo, color, rating, staff, pricing, settled_through, invested)
    values (v_uid, v_name, i.id, coalesce(p_logo, '🏢'), coalesce(p_color, '#1f7a3f'), bl_co_num('company.rating_start', 3), 0, 'fair', bl_co_night_at(), v_fee + v_setup)
    returning * into c;
  exception when unique_violation then
    raise exception 'Somebody already owns a company called "%". Pick another name.', v_name using errcode = 'P0001', hint = 'name_taken';
  end;
  insert into company_branches (company_id, area_id, format_id, is_hq) values (c.id, a.id, 'kiosk', true);
  perform bl_co_log(c.id, v_uid, 'founded', 'Registered ' || v_name || ' (' || i.name || ') in ' || a.name, -(v_fee + v_setup), jsonb_build_object('fee', v_fee, 'setup', v_setup));
  return jsonb_build_object('message', v_name || ' is registered! Hire staff, then your first evening settles at ' || bl_co_num('company.settle_hour', 18)::int || ':00 tomorrow-ish.',
                            'company', bl_co_card(c, true), 'id', c.id);
end $$;

create or replace function public.company_branch_add(p_id bigint, p_area text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; c companies; i company_industries; a company_areas; v_cost bigint;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_co_guard(v_me);
  c := bl_co_mine(v_uid, p_id);
  select * into i from company_industries where id = c.industry_id;
  select * into a from company_areas where id = p_area and active;
  if not found then
    raise exception 'Pick an area for the new branch.' using errcode = 'P0001', hint = 'bad_area';
  end if;
  if exists (select 1 from company_branches where company_id = c.id and area_id = a.id) then
    raise exception 'You already have a location in %. Pick a different area.', a.name using errcode = 'P0001', hint = 'area_used';
  end if;
  if (select count(*) from company_branches where company_id = c.id and not is_hq) >= bl_co_num('company.max_branches', 4) then
    raise exception 'That is the most branches a company can have (%).', bl_co_num('company.max_branches', 4)::int using errcode = 'P0001', hint = 'max_branches';
  end if;
  v_cost := (round(i.price * bl_co_num('company.branch_cost_pct', 60) / 100.0 * a.setup_mult / 10.0) * 10)::bigint;
  perform bl_biz_pay(v_me, v_cost, 'company_branch', jsonb_build_object('label', c.name || ': new branch in ' || a.name, 'company', c.id));
  insert into company_branches (company_id, area_id, format_id, is_hq) values (c.id, a.id, 'kiosk', false);
  update companies set invested = invested + v_cost where id = c.id returning * into c;
  perform bl_co_log(c.id, v_uid, 'branch', 'Opened a Kiosk in ' || a.name, -v_cost, jsonb_build_object('area', a.id));
  return jsonb_build_object('message', 'New branch open in ' || a.name || '. It starts as a Kiosk: upgrade it to a Shop or a Store for more customers.', 'company', bl_co_card(c, true), 'cost', v_cost);
end $$;

create or replace function public.company_branch_upgrade(p_id bigint, p_branch bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; c companies; i company_industries; b company_branches; a company_areas; f company_formats; nf company_formats; v_cost bigint;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_co_guard(v_me);
  c := bl_co_mine(v_uid, p_id);
  select * into i from company_industries where id = c.industry_id;
  select * into b from company_branches where id = p_branch and company_id = c.id for update;
  if not found then
    raise exception 'That branch no dey.' using errcode = 'P0001', hint = 'bad_branch';
  end if;
  select * into a from company_areas where id = b.area_id;
  select * into f from company_formats where id = b.format_id;
  select * into nf from company_formats where sort > f.sort order by sort limit 1;
  if not found then
    raise exception 'That location is already a Store, the biggest format.' using errcode = 'P0001', hint = 'max_format';
  end if;
  v_cost := (round(i.price * (nf.upgrade_pct - f.upgrade_pct) / 100.0 * a.setup_mult / 10.0) * 10)::bigint;
  perform bl_biz_pay(v_me, v_cost, 'company_format', jsonb_build_object('label', c.name || ': ' || a.name || ' to a ' || nf.name, 'company', c.id));
  update company_branches set format_id = nf.id where id = b.id;
  update companies set invested = invested + v_cost where id = c.id returning * into c;
  perform bl_co_log(c.id, v_uid, 'format', a.name || ' is now a ' || nf.name, -v_cost, jsonb_build_object('branch', b.id, 'format', nf.id));
  return jsonb_build_object('message', a.name || ' is now a ' || nf.name || '. More customers, more staff slots, higher upkeep.', 'company', bl_co_card(c, true), 'cost', v_cost);
end $$;

create or replace function public.company_hire(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; c companies; i company_industries; v_fee bigint;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_co_guard(v_me);
  c := bl_co_mine(v_uid, p_id);
  select * into i from company_industries where id = c.industry_id;
  if c.staff >= bl_co_slots(c.id) then
    raise exception 'No more room for staff (% slots). Upgrade a location to a bigger format.', bl_co_slots(c.id) using errcode = 'P0001', hint = 'staff_full';
  end if;
  v_fee := round(i.wage_week * bl_co_num('company.hire_fee_weeks', 1))::bigint;
  perform bl_biz_pay(v_me, v_fee, 'company_staff', jsonb_build_object('label', c.name || ': hired staff', 'company', c.id));
  update companies set staff = staff + 1 where id = c.id returning * into c;
  perform bl_co_log(c.id, v_uid, 'hire', 'Hired a staff member (' || bl_naira(i.wage_week) || ' a week)', -v_fee, jsonb_build_object('staff', c.staff));
  return jsonb_build_object('message', 'New staff don join. ' || bl_naira(i.wage_week) || ' a week, and you can serve more customers.', 'company', bl_co_card(c, true));
end $$;

create or replace function public.company_fire(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; c companies;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_co_guard(v_me, false);
  c := bl_co_mine(v_uid, p_id);
  if c.staff <= 0 then
    raise exception 'You have no staff to let go.' using errcode = 'P0001', hint = 'no_staff';
  end if;
  update companies set staff = staff - 1 where id = c.id returning * into c;
  perform bl_co_log(c.id, v_uid, 'fire', 'Let a staff member go', 0, jsonb_build_object('staff', c.staff));
  return jsonb_build_object('message', 'Staff member gone. No more wage for that one.', 'company', bl_co_card(c, true));
end $$;

create or replace function public.company_manager(p_id bigint, p_on boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; c companies; i company_industries; v_fee bigint;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_co_guard(v_me, coalesce(p_on, true));
  c := bl_co_mine(v_uid, p_id);
  select * into i from company_industries where id = c.industry_id;
  if coalesce(p_on, true) then
    if c.manager then
      raise exception 'You already have a Manager.' using errcode = 'P0001', hint = 'has_manager';
    end if;
    v_fee := round(i.wage_week * bl_co_num('company.manager_wage_mult', 3) * bl_co_num('company.hire_fee_weeks', 1))::bigint;
    perform bl_biz_pay(v_me, v_fee, 'company_manager', jsonb_build_object('label', c.name || ': hired a Manager', 'company', c.id));
    update companies set manager = true where id = c.id returning * into c;
    perform bl_co_log(c.id, v_uid, 'manager', 'Hired a Manager (+' || bl_co_num('company.manager_bonus_pct', 8)::int || '% customers, longer till)', -v_fee, '{}'::jsonb);
    return jsonb_build_object('message', 'Your Manager don resume. The company runs even when you dey away.', 'company', bl_co_card(c, true));
  end if;
  if not c.manager then
    raise exception 'You have no Manager.' using errcode = 'P0001', hint = 'no_manager';
  end if;
  update companies set manager = false where id = c.id returning * into c;
  perform bl_co_log(c.id, v_uid, 'manager', 'Let the Manager go', 0, '{}'::jsonb);
  return jsonb_build_object('message', 'Manager gone. No more manager wage.', 'company', bl_co_card(c, true));
end $$;

create or replace function public.company_generator(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; c companies; i company_industries; v_cost bigint;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_co_guard(v_me);
  c := bl_co_mine(v_uid, p_id);
  select * into i from company_industries where id = c.industry_id;
  if c.generator then
    raise exception 'You already own a generator.' using errcode = 'P0001', hint = 'has_generator';
  end if;
  v_cost := round(i.price * bl_co_num('company.generator_pct', 8) / 100.0)::bigint;
  perform bl_biz_pay(v_me, v_cost, 'company_generator', jsonb_build_object('label', c.name || ': generator', 'company', c.id));
  update companies set generator = true, invested = invested + v_cost where id = c.id returning * into c;
  perform bl_co_log(c.id, v_uid, 'generator', 'Bought a generator', -v_cost, '{}'::jsonb);
  return jsonb_build_object('message', 'Generator bought. NEPA outages now cost you ' || (100 - bl_co_num('company.generator_cut_pct', 80))::int || '% of the loss.', 'company', bl_co_card(c, true));
end $$;

create or replace function public.company_set_pricing(p_id bigint, p_pricing text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; c companies;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_co_guard(v_me, false);
  if p_pricing is null or p_pricing not in ('cheap', 'fair', 'premium') then
    raise exception 'Pricing is Cheap, Fair or Premium.' using errcode = 'P0001', hint = 'bad_pricing';
  end if;
  c := bl_co_mine(v_uid, p_id);
  update companies set pricing = p_pricing where id = c.id returning * into c;
  perform bl_co_log(c.id, v_uid, 'pricing', 'Pricing set to ' || initcap(p_pricing), 0, jsonb_build_object('pricing', p_pricing));
  return jsonb_build_object('message', 'Pricing is now ' || initcap(p_pricing) || '. It counts from the next evening.', 'company', bl_co_card(c, true));
end $$;

create or replace function public.company_marketing_buy(p_id bigint, p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; c companies; i company_industries; m company_marketing; v_cost bigint;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_co_guard(v_me);
  c := bl_co_mine(v_uid, p_id);
  select * into i from company_industries where id = c.industry_id;
  select * into m from company_marketing where id = p_kind and active;
  if not found then
    raise exception 'That kind of marketing no dey.' using errcode = 'P0001', hint = 'bad_marketing';
  end if;
  if c.boost_nights + m.nights > 14 then
    raise exception 'Marketing is already booked for % evening%. Wait a bit.', c.boost_nights, case when c.boost_nights = 1 then '' else 's' end using errcode = 'P0001', hint = 'boost_full';
  end if;
  v_cost := greatest(100, round(m.price * i.mkt_mult * bl_co_size(c.id)))::bigint;
  perform bl_biz_pay(v_me, v_cost, 'company_marketing', jsonb_build_object('label', c.name || ': ' || m.name, 'company', c.id));
  update companies set boost_pct = greatest(case when boost_nights > 0 then boost_pct else 0 end, m.boost_pct), boost_nights = boost_nights + m.nights
   where id = c.id returning * into c;
  perform bl_co_log(c.id, v_uid, 'marketing', m.name || ': +' || m.boost_pct::int || '% customers for ' || m.nights || ' evening' || case when m.nights = 1 then '' else 's' end, -v_cost,
                    jsonb_build_object('marketing', m.id));
  return jsonb_build_object('message', m.name || ' booked: +' || c.boost_pct::int || '% customers for ' || c.boost_nights || ' evening' || case when c.boost_nights = 1 then '' else 's' end || '.',
                            'company', bl_co_card(c, true), 'cost', v_cost);
end $$;

-- move the till to the bank (ledger company_income: earned income, so the weekly tax applies)
create or replace function public.company_cashout(p_id bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; c companies; r record; v_amt bigint; v_total bigint := 0; v_n int := 0; v_now timestamptz := bl_now(); v_seen boolean := false;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_co_guard(v_me, false);
  for r in select id from companies where owner_id = v_uid and (p_id is null or id = p_id) and not listed order by id loop
    v_seen := true;
    c := bl_co_settle(r.id);
    v_amt := c.till;
    if v_amt > 0 then
      perform bl_add_money(v_uid, 'bank', v_amt, 'company_income', jsonb_build_object('label', 'Till: ' || c.name, 'company', c.id));
      v_total := v_total + v_amt; v_n := v_n + 1;
      perform bl_co_log(c.id, v_uid, 'cashout', 'Cashed out ' || bl_naira(v_amt), v_amt, '{}'::jsonb);
    end if;
    update companies set till = 0, till_nights = 0, last_cashout_at = v_now, lifetime_cashed = lifetime_cashed + v_amt where id = c.id;
  end loop;
  if not v_seen and p_id is not null then
    raise exception 'That company no dey your name.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  if v_total <= 0 then
    raise exception 'The till is empty. Your next evening settles at %:00.', bl_co_num('company.settle_hour', 18)::int using errcode = 'P0001', hint = 'nothing';
  end if;
  return jsonb_build_object('message', 'You moved ' || bl_naira(v_total) || ' from the till to your bank.', 'amount', v_total, 'count', v_n);
end $$;

-- sell to the system at company.sell_pct of the value; the till is paid out first
create or replace function public.company_sell(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; c companies; v_amt bigint; v_take bigint; v_val bigint;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_co_guard(v_me, false);
  c := bl_co_mine(v_uid, p_id);
  v_take := c.till;
  if v_take > 0 then
    perform bl_add_money(v_uid, 'bank', v_take, 'company_income', jsonb_build_object('label', 'Till: ' || c.name, 'company', c.id));
  end if;
  v_val := bl_co_value(c);
  v_amt := floor(v_val * bl_co_num('company.sell_pct', 50) / 100.0)::bigint;
  if v_amt > 0 then
    perform bl_add_money(v_uid, 'bank', v_amt, 'company_sell', jsonb_build_object('label', 'Company sold: ' || c.name, 'company', c.id));
  end if;
  update real_businesses set company_id = null where company_id = c.id;
  delete from companies where id = c.id;
  return jsonb_build_object('message', c.name || ' sold. ' || bl_naira(v_amt) || ' in your bank' || case when v_take > 0 then ' (plus ' || bl_naira(v_take) || ' from the till).' else '.' end,
                            'amount', v_amt, 'till', v_take);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Public card, rankings, discover (read-only: nothing is settled or written here)
-- ---------------------------------------------------------------------------------------------
create or replace function public.company_public(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c companies; i company_industries; v_cur date := bl_co_night_at(); v_sales bigint; v_rank int; v_hq text; v_n int; v_owner text;
begin
  select * into c from companies where id = p_id;
  if not found then return null; end if;
  select * into i from company_industries where id = c.industry_id;
  select a.name into v_hq from company_branches b join company_areas a on a.id = b.area_id where b.company_id = c.id and b.is_hq;
  select count(*) into v_n from company_branches where company_id = c.id;
  select username into v_owner from profiles where id = c.owner_id;
  select coalesce(sum(sales), 0) into v_sales from company_nights where company_id = c.id and night > v_cur - 7;
  select count(*) + 1 into v_rank from (select company_id from company_nights where night > v_cur - 7 group by company_id having sum(sales) > v_sales) x;
  return jsonb_build_object('id', c.id, 'name', c.name, 'logo', c.logo, 'color', c.color, 'industry', i.id, 'industry_name', i.name, 'icon', i.icon, 'blurb', i.blurb,
    'hq_area', v_hq, 'locations', v_n, 'stars', round(c.rating)::int, 'owner', v_owner, 'sales_7d', v_sales, 'rank', case when v_sales > 0 then v_rank end,
    'founded', c.created_at, 'share', 'https://playbeninlife.app/c/' || c.id,
    'areas', coalesce((select jsonb_agg(a.name order by b.is_hq desc, b.id) from company_branches b join company_areas a on a.id = b.area_id where b.company_id = c.id), '[]'::jsonb));
end $$;

create or replace function public.company_rankings(p_limit int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_cur date := bl_co_night_at(); v_lim int := least(greatest(coalesce(p_limit, bl_co_num('company.rank_limit', 20)::int), 1), 100);
begin
  return jsonb_build_object('night', v_cur, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('rank', x.rn, 'id', x.id, 'name', x.name, 'logo', x.logo, 'color', x.color, 'industry', x.iname, 'icon', x.icon,
                       'stars', x.stars, 'sales_7d', x.s, 'owner', x.owner, 'mine', x.owner_id = v_uid) order by x.rn)
      from (select row_number() over (order by s.s desc, c.id) rn, c.id, c.name, c.logo, c.color, i.name iname, i.icon, round(c.rating)::int stars, s.s, p.username owner, c.owner_id
              from (select company_id, sum(sales) s from company_nights where night > v_cur - 7 group by company_id having sum(sales) > 0 order by sum(sales) desc limit v_lim) s
              join companies c on c.id = s.company_id join company_industries i on i.id = c.industry_id join profiles p on p.id = c.owner_id) x), '[]'::jsonb));
end $$;

-- Discover: every company (in-game) plus every live real business, filter by industry and area, search by name
create or replace function public.company_discover(p_q text default null, p_industry text default null, p_area text default null,
                                                   p_kind text default 'all', p_limit int default 30, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_cur date := bl_co_night_at(); v_q text := nullif(btrim(replace(replace(coalesce(p_q, ''), '%', ''), '_', '')), '');
  v_lim int := least(greatest(coalesce(p_limit, 30), 1), 60); v_off int := greatest(coalesce(p_offset, 0), 0);
  v_ind text := nullif(p_industry, ''); v_area text := nullif(p_area, ''); v_kind text := coalesce(nullif(p_kind, ''), 'all');
begin
  return (
    with u as (
      select 'company'::text as kind, c.id::text as id, c.name, c.logo, c.color, i.id as industry, i.name as industry_name, i.icon, a.id as area, a.name as area_name,
             round(c.rating)::int as stars, (select count(*)::int from company_branches b2 where b2.company_id = c.id) as locations, p.username as owner,
             coalesce((select sum(n.sales) from company_nights n where n.company_id = c.id and n.night > v_cur - 7), 0)::bigint as sales_7d, c.created_at, false as verified
        from companies c join company_industries i on i.id = c.industry_id
        join company_branches hq on hq.company_id = c.id and hq.is_hq join company_areas a on a.id = hq.area_id join profiles p on p.id = c.owner_id
       where v_kind in ('all', 'company')
         and (v_q is null or c.name ilike '%' || v_q || '%')
         and (v_ind is null or c.industry_id = v_ind)
         and (v_area is null or exists (select 1 from company_branches b3 where b3.company_id = c.id and b3.area_id = v_area))
      union all
      select 'real', r.id::text, r.name, r.logo, '#d4a017', r.category, coalesce(i.name, 'Other'), coalesce(i.icon, '🏷️'), a.id, a.name, null, 1, null, 0::bigint, r.created_at, true
        from real_businesses r join company_areas a on a.id = r.area_id left join company_industries i on i.id = r.category
       where v_kind in ('all', 'real') and r.status = 'live' and r.ends_at > now()
         and (v_q is null or r.name ilike '%' || v_q || '%')
         and (v_ind is null or r.category = v_ind) and (v_area is null or r.area_id = v_area)
    )
    select jsonb_build_object(
      'rows', coalesce((select jsonb_agg(to_jsonb(x) - 'created_at') from (select * from u order by (kind = 'real') desc, sales_7d desc, created_at desc, id limit v_lim offset v_off) x), '[]'::jsonb),
      'total', (select count(*) from u))
  );
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. Market: kind 'company'
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_co_market_take(p_uid uuid, p_ref text, p_qty int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c companies; i company_industries; v_hq text;
begin
  if p_ref is null or p_ref !~ '^[0-9]+$' then
    raise exception 'That company no dey.' using errcode = 'P0001', hint = 'not_owned';
  end if;
  if coalesce(p_qty, 1) <> 1 then
    raise exception 'A company is sold one at a time.' using errcode = 'P0001', hint = 'bad_amount';
  end if;
  select * into c from companies where id = p_ref::bigint and owner_id = p_uid for update;
  if not found then
    raise exception 'That company no dey your name.' using errcode = 'P0001', hint = 'not_owned';
  end if;
  if c.listed then
    raise exception 'That company is already on the market.' using errcode = 'P0001', hint = 'listed';
  end if;
  c := bl_co_settle(c.id);
  select * into i from company_industries where id = c.industry_id;
  select a.name into v_hq from company_branches b join company_areas a on a.id = b.area_id where b.company_id = c.id and b.is_hq;
  if c.till > 0 then
    perform bl_add_money(p_uid, 'bank', c.till, 'company_income', jsonb_build_object('label', 'Till: ' || c.name, 'company', c.id));
  end if;
  update companies set listed = true, lifetime_cashed = lifetime_cashed + till, till = 0, till_nights = 0, last_cashout_at = bl_now() where id = c.id returning * into c;
  perform bl_co_log(c.id, p_uid, 'listed', 'Put on the Market', 0, '{}'::jsonb);
  return jsonb_build_object('title', c.name || ' (' || round(c.rating)::int || '★)', 'icon', c.logo, 'value', bl_co_value(c),
                            'detail', jsonb_build_object('company', c.id, 'industry', i.id, 'industry_name', i.name, 'stars', round(c.rating)::int, 'area', v_hq,
                                       'locations', (select count(*) from company_branches where company_id = c.id), 'cost', c.invested),
                            'qty', 1);
end $$;

-- the buyer (strict) or the seller getting it back (not strict)
create or replace function public.bl_co_market_give(p_uid uuid, p_ref text, p_detail jsonb, p_cost bigint, p_strict boolean) returns void
language plpgsql security definer set search_path = public as $$
declare c companies; i company_industries; v_gate text; v_old uuid; v_username text; v_now timestamptz := bl_now();
begin
  select * into c from companies where id = (p_ref)::bigint for update;
  if not found then return; end if;
  select * into i from company_industries where id = c.industry_id;
  v_old := c.owner_id;
  if p_strict then
    if (select count(*) from companies where owner_id = p_uid) >= bl_co_num('company.max_owned', 20) then
      raise exception 'You already own % companies. That is the limit.', bl_co_num('company.max_owned', 20)::int using errcode = 'P0001', hint = 'max_owned';
    end if;
    v_gate := bl_co_gate(p_uid, i);
    if v_gate is not null then
      raise exception '%', v_gate using errcode = 'P0001', hint = 'requirement';
    end if;
  end if;
  update companies set owner_id = p_uid, listed = false, till = 0, till_nights = 0, settled_through = bl_co_night_at(), boost_pct = 0, boost_nights = 0,
         invested = case when p_strict and p_uid <> v_old then least(greatest(0, coalesce(p_cost, 0)), bl_co_value(c)) else invested end,
         source = case when p_uid = v_old then source else 'market' end
   where id = c.id;
  if p_uid <> v_old then
    update company_log set owner_id = p_uid where company_id = c.id;
    update real_businesses set company_id = null where company_id = c.id;
  end if;
  select username into v_username from profiles where id = p_uid;
  perform bl_co_log(c.id, p_uid, case when p_uid = v_old then 'unlisted' else 'market_buy' end,
                    case when p_uid = v_old then 'Back with you from the Market' else 'Bought on the Market by @' || coalesce(v_username, 'player') end, 0, '{}'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. Admin (companies)
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_company_overview(p_limit int default 200) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_lim int := least(greatest(coalesce(p_limit, 200), 1), 500); v_cur date := bl_co_night_at();
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'stats', jsonb_build_object('companies', (select count(*) from companies), 'listed', (select count(*) from companies where listed),
                                'till_total', (select coalesce(sum(till), 0) from companies),
                                'sales_7d', (select coalesce(sum(sales), 0) from company_nights where night > v_cur - 7),
                                'income_7d', (select coalesce(sum(delta), 0) from ledger where reason = 'company_income' and delta > 0 and created_at > bl_now() - interval '7 days'),
                                'real_live', (select count(*) from real_businesses where status = 'live'),
                                'real_review', (select count(*) from real_businesses where status = 'pending_review')),
    'industries', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'icon', i.icon, 'companies', (select count(*) from companies c where c.industry_id = i.id)) order by i.sort) from company_industries i), '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'logo', c.logo, 'industry', i.name, 'owner', p.username, 'owner_id', c.owner_id,
                          'hq', (select a.name from company_branches b join company_areas a on a.id = b.area_id where b.company_id = c.id and b.is_hq),
                          'locations', (select count(*) from company_branches b where b.company_id = c.id), 'stars', round(c.rating)::int, 'staff', c.staff, 'manager', c.manager,
                          'till', c.till, 'listed', c.listed, 'source', c.source, 'sales_7d', coalesce((select sum(n.sales) from company_nights n where n.company_id = c.id and n.night > v_cur - 7), 0),
                          'lifetime_sales', c.lifetime_sales, 'lifetime_net', c.lifetime_net, 'created_at', c.created_at) order by c.id desc)
                        from (select * from companies order by id desc limit v_lim) c join company_industries i on i.id = c.industry_id join profiles p on p.id = c.owner_id), '[]'::jsonb));
end $$;

create or replace function public.admin_company_remove(p_company bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); c companies; v_reason text := left(btrim(coalesce(p_reason, '')), 200); v_take bigint;
begin
  select * into c from companies where id = p_company for update;
  if not found then
    raise exception 'That company is gone already.' using errcode = 'P0001', hint = 'gone';
  end if;
  perform 1 from profiles where id = c.owner_id for update;
  if c.listed then
    update market_listings set status = 'removed', closed_at = bl_now(), removed_by = v_admin, removed_reason = 'company removed'
     where kind = 'company' and ref_id = c.id::text and status = 'active';
    update market_offers set status = 'cancelled', closed_at = bl_now()
     where status = 'pending' and listing_id in (select id from market_listings where kind = 'company' and ref_id = c.id::text);
  else
    c := bl_co_settle(c.id, false);
  end if;
  v_take := case when c.listed then 0 else c.till end;
  if v_take > 0 then
    perform bl_add_money(c.owner_id, 'bank', v_take, 'company_income', jsonb_build_object('label', 'Till: ' || c.name, 'company', c.id));
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'company_remove', c.owner_id, jsonb_build_object('company', c.id, 'name', c.name, 'industry', c.industry_id, 'reason', v_reason, 'till_paid', v_take));
  perform bl_event(c.owner_id, 'company_removed', c.name || ' removed',
    'An admin closed the company.' || case when v_reason <> '' then ' Reason: ' || v_reason else '' end || case when v_take > 0 then ' Your till of ' || bl_naira(v_take) || ' was paid to your bank.' else '' end,
    jsonb_build_object('company', c.id));
  update real_businesses set company_id = null where company_id = c.id;
  delete from companies where id = c.id;
  return jsonb_build_object('message', c.name || ' removed.', 'company', c.id);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 11. Patches to live functions (guarded)
-- ---------------------------------------------------------------------------------------------
select pg_temp.bl_patch1('public.bl_market_take(uuid, text, text, integer, text)', 'bl_co_market_take(',
  $m$  elsif p_kind = 'business' then$m$,
  $m$  elsif p_kind = 'company' then
    return bl_co_market_take(p_uid, p_ref, p_qty);

  elsif p_kind = 'business' then$m$);
select pg_temp.bl_patch1('public.bl_market_give(uuid, text, text, integer, jsonb, bigint, boolean)', 'bl_co_market_give(',
  $m$  elsif p_kind = 'business' then$m$,
  $m$  elsif p_kind = 'company' then
    perform bl_co_market_give(p_uid, p_ref, p_detail, p_cost, p_strict);

  elsif p_kind = 'business' then$m$);
select pg_temp.bl_patch1('public.bl_market_cond(text, jsonb, integer)', $m$'company'$m$,
  $m$    when 'item' then case when p_qty > 1$m$,
  $m$    when 'company' then coalesce(p_detail->>'stars', '3') || '★ · ' || coalesce(p_detail->>'industry_name', 'company') || ' · ' || coalesce(p_detail->>'locations', '1') || ' location(s) · ' || coalesce(p_detail->>'area', '')
    when 'item' then case when p_qty > 1$m$);

-- ledger text
select pg_temp.bl_patch1('public.bl_ledger_label(text, jsonb)', $m$when 'company_income' then$m$,
  $m$    when 'garage' then return$m$,
  $m$    when 'company_income' then return coalesce(nullif(p_meta->>'label', ''), 'Company income');
    when 'company_fee' then return coalesce(nullif(p_meta->>'label', ''), 'Company registration');
    when 'company_setup' then return coalesce(nullif(p_meta->>'label', ''), 'Company setup');
    when 'company_branch' then return coalesce(nullif(p_meta->>'label', ''), 'Company: new branch');
    when 'company_format' then return coalesce(nullif(p_meta->>'label', ''), 'Company: location upgrade');
    when 'company_staff' then return coalesce(nullif(p_meta->>'label', ''), 'Company: hired staff');
    when 'company_manager' then return coalesce(nullif(p_meta->>'label', ''), 'Company: Manager');
    when 'company_generator' then return coalesce(nullif(p_meta->>'label', ''), 'Company: generator');
    when 'company_marketing' then return coalesce(nullif(p_meta->>'label', ''), 'Company: marketing');
    when 'company_sell' then return coalesce(nullif(p_meta->>'label', ''), 'Company sold');
    when 'garage' then return$m$);

-- Admin -> Economy: company income is made like business income, company spending is its own sink
select pg_temp.bl_patch1('public.bl_econ_category(text)', $m$'company_income'$m$,
  $m$'business_income', 'office_salary'$m$, $m$'business_income', 'company_income', 'office_salary'$m$);
select pg_temp.bl_patch1('public.bl_econ_category(text)', $m$company\_%$m$,
  $m$p_reason like 'business\_%' or$m$, $m$p_reason like 'business\_%' or p_reason like 'company\_%' or$m$);

-- admin Content editors
select pg_temp.bl_patch1('public.bl_admin_table_spec(text)', $m$'company_industries'$m$,
  $m$    when 'business_types' then$m$,
  $m$    when 'company_industries' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","icon":"text","blurb":"text","price":"money","base_revenue":"money","ticket":"money","cogs_pct":"num","upkeep_week":"money","wage_week":"money","mkt_mult":"num","req_skill_level":"int","req_cert":"text_null","sort":"int","active":"bool"}}'
    when 'company_areas' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","tier":"int","setup_mult":"num","rev_mult":"num","district":"text","sort":"int","active":"bool"}}'
    when 'company_formats' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","demand_mult":"num","staff_slots":"int","upgrade_pct":"num","upkeep_mult":"num","sort":"int"}}'
    when 'company_marketing' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","price":"money","boost_pct":"num","nights":"int","sort":"int","active":"bool"}}'
    when 'real_biz_slots' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"area_id":"text","x":"num","y":"num","sort":"int","active":"bool"}}'
    when 'business_types' then$m$);

-- ---------------------------------------------------------------------------------------------
-- 12. Real businesses (an ad on the map, paid with Paystack, approved by the owner)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_rb_phone(p text) returns text
language sql immutable as $$
  select nullif(regexp_replace(btrim(coalesce(p, '')), '[\s\-().]', '', 'g'), '')
$$;

-- free text must not name the real politicians / parties / election bodies on the Benin Votes blocked lists (pol.blocked_words, pol.blocked_party_words).
-- Whole words and phrases only: bl_pol_text_ok also matches inside a run of letters, which would refuse "online company" (it holds "inec").
create or replace function public.bl_rb_text_ok(p_text text) returns boolean
language plpgsql stable set search_path = public as $$
declare v_words text := ' ' || btrim(regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9]+', ' ', 'g')) || ' '; k text; w text; n text;
begin
  foreach k in array array['pol.blocked_words', 'pol.blocked_party_words'] loop
    foreach w in array bl_pol_list(k, '') loop
      n := btrim(regexp_replace(lower(w), '[^a-z0-9]+', ' ', 'g'));
      if n <> '' and position(' ' || n || ' ' in v_words) > 0 then return false; end if;
    end loop;
  end loop;
  return true;
end $$;

create or replace function public.bl_rb_text(p_key text, p_default text) returns text
language sql stable set search_path = public as $$
  select coalesce((select value #>> '{}' from game_config where key = p_key), p_default)
$$;

-- a slot is held while a listing waits, is live or suspended, or a checkout is less than an hour old
create or replace function public.bl_rb_slot_free(p_slot text, p_except uuid default null) returns boolean
language sql stable set search_path = public as $$
  select not exists (select 1 from real_businesses r where r.slot_id = p_slot and (p_except is null or r.id <> p_except)
                       and (r.status in ('pending_review', 'live', 'suspended') or (r.status = 'awaiting_payment' and r.created_at > now() - interval '1 hour')))
$$;

-- listings counting against an area's cap
create or replace function public.bl_rb_area_used(p_area text) returns int
language sql stable set search_path = public as $$
  select count(*)::int from real_businesses r where r.area_id = p_area
     and (r.status in ('pending_review', 'live', 'suspended') or (r.status = 'awaiting_payment' and r.created_at > now() - interval '1 hour'))
$$;

-- finished listings end; stale unpaid checkouts are cancelled (no write when nothing is due)
create or replace function public.bl_real_biz_sweep() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in update real_businesses set status = 'expired', updated_at = now() where status = 'live' and ends_at <= now() returning id, owner_id, name loop
    n := n + 1;
    perform bl_admin_notify('real_biz_ended', 'Real business ended · ' || r.name, r.name || ' finished its run.', jsonb_build_object('biz_id', r.id), '/admin/real-business');
    if r.owner_id is not null and exists (select 1 from profiles where id = r.owner_id) then
      perform bl_event(r.owner_id, 'real_biz_ended', 'Your map listing ended', r.name || ' is off the map now. Open the Company app, Discover, to list it again.', jsonb_build_object('biz_id', r.id));
    end if;
  end loop;
  update real_businesses set status = 'cancelled', updated_at = now() where status = 'awaiting_payment' and created_at < now() - interval '1 day';
  return n;
end $$;

-- Called by the Edge Functions (service role) after Paystack says the payment succeeded. Idempotent.
create or replace function public.bl_real_biz_paid(p_reference text, p_amount_kobo bigint, p_raw jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b real_businesses; v_user text; v_slot text; v_exp timestamptz;
begin
  if exists (select 1 from real_businesses where p_reference = any (renewed_refs)) then
    select * into b from real_businesses where p_reference = any (renewed_refs);
    return jsonb_build_object('ok', true, 'marked', false, 'already', true, 'biz_id', b.id, 'status', b.status, 'user_id', b.owner_id);
  end if;
  select * into b from real_businesses where reference = p_reference or renew_reference = p_reference for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_reference');
  end if;
  v_user := coalesce('@' || (select username from profiles where id = b.owner_id), 'A player');
  -- ---- a renewal
  if b.renew_reference is not distinct from p_reference then
    if p_amount_kobo is distinct from b.renew_price_kobo or b.status not in ('live', 'expired') then
      update real_businesses set renew_reference = null, renew_price_kobo = null, renewed_refs = renewed_refs || p_reference, updated_at = now() where id = b.id;
      perform bl_admin_notify('refund_needed', 'Refund needed · real business renewal',
        v_user || ' paid ' || bl_naira(coalesce(p_amount_kobo, 0) / 100) || ' to renew ' || b.name || ' but it can''t be renewed (' || case when p_amount_kobo is distinct from b.renew_price_kobo then 'wrong amount' else b.status end
        || '). Refund reference ' || p_reference || ' in the Paystack dashboard.', jsonb_build_object('biz_id', b.id, 'reference', p_reference), '/admin/real-business');
      return jsonb_build_object('ok', false, 'error', 'renewal_refused', 'biz_id', b.id);
    end if;
    if b.status = 'expired' then
      if b.slot_id is null or not bl_rb_slot_free(b.slot_id, b.id) then
        update real_businesses set renew_reference = null, renew_price_kobo = null, renewed_refs = renewed_refs || p_reference, updated_at = now() where id = b.id;
        perform bl_admin_notify('refund_needed', 'Refund needed · real business renewal', v_user || ' renewed ' || b.name || ' after it ended and its map spot was taken. Refund reference ' || p_reference || '.',
                                jsonb_build_object('biz_id', b.id, 'reference', p_reference), '/admin/real-business');
        return jsonb_build_object('ok', false, 'error', 'spot_taken', 'biz_id', b.id);
      end if;
      v_exp := now() + make_interval(days => b.renew_days);
      update real_businesses set status = 'live', starts_at = now(), ends_at = v_exp where id = b.id;
    else
      v_exp := greatest(b.ends_at, now()) + make_interval(days => b.renew_days);
      update real_businesses set ends_at = v_exp where id = b.id;
    end if;
    update real_businesses set renew_reference = null, renew_price_kobo = null, renew_days = null, renewed_refs = renewed_refs || p_reference,
           renewals = renewals + 1, updated_at = now() where id = b.id;
    perform bl_admin_notify('real_biz_renewed', 'Real business renewed · ' || b.name, v_user || ' paid ' || bl_naira(p_amount_kobo / 100) || ' to renew ' || b.name || '.',
                            jsonb_build_object('biz_id', b.id), '/admin/real-business');
    if b.owner_id is not null and exists (select 1 from profiles where id = b.owner_id) then
      perform bl_event(b.owner_id, 'real_biz_renewed', 'Listing renewed', b.name || ' stays on the map until ' || to_char(v_exp at time zone 'Africa/Lagos', 'Dy DD Mon') || '.', jsonb_build_object('biz_id', b.id));
    end if;
    return jsonb_build_object('ok', true, 'marked', true, 'renewal', true, 'biz_id', b.id, 'status', 'live', 'user_id', b.owner_id);
  end if;
  -- ---- the first payment
  if b.paid_at is not null then
    return jsonb_build_object('ok', true, 'marked', false, 'already', true, 'biz_id', b.id, 'status', b.status, 'user_id', b.owner_id);
  end if;
  if b.status not in ('awaiting_payment', 'cancelled') then
    return jsonb_build_object('ok', false, 'error', 'not_awaiting', 'status', b.status);
  end if;
  if p_amount_kobo is distinct from b.price_kobo then
    update real_businesses set status = 'rejected', paid_kobo = p_amount_kobo, paid_at = now(), reject_reason = 'The amount paid did not match the price.',
           refund_status = case when coalesce(p_amount_kobo, 0) > 0 then 'pending' else 'none' end, refund_kobo = case when coalesce(p_amount_kobo, 0) > 0 then p_amount_kobo end,
           pay_raw = coalesce(p_raw, '{}'::jsonb) || jsonb_build_object('bl_error', 'amount_mismatch'), updated_at = now()
     where id = b.id;
    perform bl_admin_notify('refund_needed', 'Refund needed · wrong amount',
      v_user || ' paid ' || bl_naira(coalesce(p_amount_kobo, 0) / 100) || ' instead of ' || bl_naira(b.price_kobo / 100) || ' for the real business ' || b.name || '. Open Real business, Refunds.',
      jsonb_build_object('biz_id', b.id), '/admin/real-business');
    return jsonb_build_object('ok', false, 'error', 'amount_mismatch', 'expected', b.price_kobo, 'got', p_amount_kobo, 'biz_id', b.id);
  end if;
  v_slot := b.slot_id;
  if v_slot is null or not bl_rb_slot_free(v_slot, b.id) then
    -- paid late and somebody took the spot: any free spot in the same area, else a refund
    select s.id into v_slot from real_biz_slots s where s.area_id = b.area_id and s.active and bl_rb_slot_free(s.id, b.id) order by s.sort, s.id limit 1;
  end if;
  if v_slot is null then
    update real_businesses set status = 'rejected', paid_kobo = p_amount_kobo, paid_at = now(), reject_reason = 'No free map spot is left in this area.',
           refund_status = 'pending', refund_kobo = p_amount_kobo, pay_raw = coalesce(p_raw, '{}'::jsonb), updated_at = now() where id = b.id;
    perform bl_admin_notify('refund_needed', 'Refund needed · no free spot', v_user || ' paid for ' || b.name || ' but the area has no free spot. Open Real business, Refunds.',
                            jsonb_build_object('biz_id', b.id), '/admin/real-business');
    if b.owner_id is not null and exists (select 1 from profiles where id = b.owner_id) then
      perform bl_event(b.owner_id, 'real_biz_rejected', 'Listing not placed', 'The area filled up before your payment landed. Your money is being refunded.', jsonb_build_object('biz_id', b.id));
    end if;
    return jsonb_build_object('ok', false, 'error', 'no_slot', 'biz_id', b.id);
  end if;
  update real_businesses set status = 'pending_review', slot_id = v_slot, paid_kobo = p_amount_kobo, paid_at = now(), pay_raw = coalesce(p_raw, '{}'::jsonb), updated_at = now() where id = b.id;
  perform bl_admin_notify('real_biz_paid', 'New real business to approve · ' || bl_naira(p_amount_kobo / 100),
    v_user || ' paid for ' || b.name || ' (' || coalesce((select name from company_areas where id = b.area_id), b.area_id) || '). Check the photos and approve.',
    jsonb_build_object('biz_id', b.id, 'area', b.area_id), '/admin/real-business');
  if b.owner_id is not null and exists (select 1 from profiles where id = b.owner_id) then
    perform bl_event(b.owner_id, 'real_biz_paid', 'Listing paid', 'We got your payment. ' || b.name || ' goes on the map as soon as it is checked (usually within a few hours).', jsonb_build_object('biz_id', b.id));
  end if;
  return jsonb_build_object('ok', true, 'marked', true, 'biz_id', b.id, 'status', 'pending_review', 'user_id', b.owner_id);
end $$;

-- billboard-refund Edge Function (service role): claim the refund so two clicks can't refund twice
create or replace function public.bl_real_biz_refund_claim(p_biz uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b real_businesses;
begin
  select * into b from real_businesses where id = p_biz for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_biz'); end if;
  if b.refund_status = 'refunded' then return jsonb_build_object('ok', false, 'error', 'already_refunded'); end if;
  if not (b.refund_status in ('pending', 'refund_failed') or (b.refund_status = 'processing' and b.updated_at < now() - interval '10 minutes')) then
    return jsonb_build_object('ok', false, 'error', 'no_refund_due', 'refund_status', b.refund_status);
  end if;
  if b.reference is null or coalesce(b.paid_kobo, 0) <= 0 then return jsonb_build_object('ok', false, 'error', 'not_paid'); end if;
  update real_businesses set refund_status = 'processing', updated_at = now() where id = b.id;
  return jsonb_build_object('ok', true, 'reference', b.reference, 'amount_kobo', coalesce(b.refund_kobo, b.paid_kobo));
end $$;

create or replace function public.bl_real_biz_refund_result(p_biz uuid, p_ok boolean, p_error text default null, p_raw jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b real_businesses;
begin
  select * into b from real_businesses where id = p_biz for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_biz'); end if;
  if b.refund_status <> 'processing' then
    return jsonb_build_object('ok', false, 'error', 'not_processing', 'refund_status', b.refund_status);
  end if;
  if p_ok then
    update real_businesses set refund_status = 'refunded', refund_at = now(), refund_error = null, refund_kobo = coalesce(refund_kobo, paid_kobo),
           refund_raw = coalesce(p_raw, '{}'::jsonb), updated_at = now() where id = b.id;
    if b.owner_id is not null and exists (select 1 from profiles where id = b.owner_id) then
      perform bl_event(b.owner_id, 'real_biz_refund', 'Listing refund sent', bl_naira(coalesce(b.refund_kobo, b.paid_kobo) / 100) || ' is on its way back to your card or bank (Paystack takes a few days).',
                       jsonb_build_object('biz_id', b.id));
    end if;
  else
    update real_businesses set refund_status = 'refund_failed', refund_error = left(coalesce(p_error, 'unknown error'), 300), refund_raw = coalesce(p_raw, '{}'::jsonb), updated_at = now() where id = b.id;
    perform bl_admin_notify('refund_failed', 'Refund failed · ' || bl_naira(coalesce(b.refund_kobo, b.paid_kobo) / 100),
      'Paystack refused the refund for ' || coalesce(b.reference, '?') || ': ' || left(coalesce(p_error, 'unknown error'), 120) || '. Retry from Real business, Refunds or refund in the Paystack dashboard.',
      jsonb_build_object('biz_id', b.id), '/admin/real-business');
  end if;
  return jsonb_build_object('ok', true, 'refund_status', case when p_ok then 'refunded' else 'refund_failed' end);
end $$;

-- ---- player RPCs
create or replace function public.real_biz_form() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  perform bl_real_biz_sweep();
  return jsonb_build_object(
    'enabled', coalesce(bl_cfg_bool('realbiz.enabled'), false),
    'buy_enabled', coalesce(bl_cfg_bool('realbiz.enabled'), false) and coalesce(bl_cfg_bool('payments.enabled'), false),
    'price_kobo', bl_co_num('realbiz.price_kobo', 2500000)::bigint, 'days', bl_co_num('realbiz.days', 30)::int,
    'max_images', bl_co_num('realbiz.max_images', 3)::int, 'max_per_player', bl_co_num('realbiz.max_per_player', 2)::int,
    'terms', bl_rb_text('realbiz.terms', 'Only legal businesses. No adult content, gambling, crypto schemes, weapons or drugs.'),
    'contact_email', bl_rb_text('realbiz.contact_email', 'code.devshalom@gmail.com'),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'icon', i.icon) order by i.sort) from company_industries i where i.active), '[]'::jsonb)
                  || jsonb_build_array(jsonb_build_object('id', 'other', 'name', 'Other', 'icon', '🏷️')),
    'areas', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'tier', a.tier, 'cap', bl_co_num('realbiz.max_per_area', 6)::int, 'used', bl_rb_area_used(a.id),
              'slots', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'x', s.x, 'y', s.y) order by s.sort, s.id)
                                   from real_biz_slots s where s.area_id = a.id and s.active and bl_rb_slot_free(s.id)), '[]'::jsonb)) order by a.tier, a.sort)
                         from company_areas a where a.active), '[]'::jsonb),
    'companies', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'logo', c.logo) order by c.id) from companies c where c.owner_id = v_uid), '[]'::jsonb));
end $$;

create or replace function public.real_biz_create(p_name text, p_category text, p_desc text, p_phone text, p_whatsapp text, p_instagram text, p_website text,
                                                  p_address text, p_area text, p_slot text, p_images text[], p_logo text default null, p_company bigint default null,
                                                  p_terms boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_ban boolean; v_email text; v_name text; v_desc text; v_addr text; v_phone text := bl_rb_phone(p_phone); v_wa text := bl_rb_phone(p_whatsapp);
  v_ig text := nullif(regexp_replace(btrim(coalesce(p_instagram, '')), '^@', ''), ''); v_web text := nullif(btrim(coalesce(p_website, '')), ''); a company_areas; s real_biz_slots;
  v_img text; v_n int; v_price bigint := bl_co_num('realbiz.price_kobo', 2500000)::bigint; v_days int := bl_co_num('realbiz.days', 30)::int; v_ref text; v_id uuid;
  v_logo text := coalesce(nullif(btrim(coalesce(p_logo, '')), ''), '🏪'); v_cat text := coalesce(nullif(btrim(coalesce(p_category, '')), ''), 'other');
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  if not coalesce(bl_cfg_bool('realbiz.enabled'), false) then
    raise exception 'Real business listings are off right now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  if not coalesce(bl_cfg_bool('payments.enabled'), false) then
    raise exception 'Listing payments are coming soon.' using errcode = 'P0001', hint = 'payments_off';
  end if;
  select banned into v_ban from profiles where id = v_uid;
  if not found then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v_ban then
    raise exception 'This account can''t list a business.' using errcode = 'P0001', hint = 'banned';
  end if;
  if not coalesce(p_terms, false) then
    raise exception 'Accept the terms to continue.' using errcode = 'P0001', hint = 'terms';
  end if;
  v_name := left(bl_chat_clean(coalesce(p_name, '')), 40);
  if char_length(v_name) < 3 or v_name ~ '[<>]' or bl_chat_mask(v_name) <> v_name or not bl_rb_text_ok(v_name) then
    raise exception 'Give the business a clean name of 3 to 40 letters (no rude words, no real politicians or parties).' using errcode = 'P0001', hint = 'bad_name';
  end if;
  v_desc := left(bl_chat_clean(coalesce(p_desc, '')), 400);
  if char_length(v_desc) < 15 or v_desc ~ '[<>]' or bl_chat_mask(v_desc) <> v_desc or not bl_rb_text_ok(v_desc)
     or v_desc ~* '(https?:|www\.|\.com\b|\.ng\b|\.net\b|\.org\b)' then
    raise exception 'Write a short, clean description (at least 15 letters, no rude words, no links, no real politicians or parties). Put your website in its own box.' using errcode = 'P0001', hint = 'bad_desc';
  end if;
  v_addr := left(bl_chat_clean(coalesce(p_address, '')), 120);
  if char_length(v_addr) < 5 or v_addr ~ '[<>]' or bl_chat_mask(v_addr) <> v_addr or not bl_rb_text_ok(v_addr) then
    raise exception 'Add the street address of the business.' using errcode = 'P0001', hint = 'bad_address';
  end if;
  if not exists (select 1 from company_industries where id = v_cat and active) and v_cat <> 'other' then
    raise exception 'Pick a category.' using errcode = 'P0001', hint = 'bad_category';
  end if;
  if v_phone is not null and v_phone !~ '^\+?[0-9]{8,15}$' then
    raise exception 'That phone number looks wrong. Use digits only, like 08012345678.' using errcode = 'P0001', hint = 'bad_phone';
  end if;
  if v_wa is not null and v_wa !~ '^\+?[0-9]{8,15}$' then
    raise exception 'That WhatsApp number looks wrong. Use digits only, like 2348012345678.' using errcode = 'P0001', hint = 'bad_phone';
  end if;
  if v_ig is not null and v_ig !~ '^[A-Za-z0-9._]{2,30}$' then
    raise exception 'That Instagram name looks wrong. Letters, numbers, dots and underscores only.' using errcode = 'P0001', hint = 'bad_instagram';
  end if;
  if v_web is not null and not bl_billboard_link_ok(v_web) then
    raise exception 'The website must be a full link that starts with https://' using errcode = 'P0001', hint = 'bad_link';
  end if;
  if v_phone is null and v_wa is null and v_ig is null and v_web is null then
    raise exception 'Add at least one way for customers to reach you: phone, WhatsApp, Instagram or a website.' using errcode = 'P0001', hint = 'no_contact';
  end if;
  if not bl_co_logo_ok(v_logo) then
    raise exception 'Pick an emoji for the pin.' using errcode = 'P0001', hint = 'bad_logo';
  end if;
  select * into a from company_areas where id = p_area and active;
  if not found then
    raise exception 'Pick the area your business is in.' using errcode = 'P0001', hint = 'bad_area';
  end if;
  v_n := coalesce(cardinality(p_images), 0);
  if v_n < 1 or v_n > bl_co_num('realbiz.max_images', 3) then
    raise exception 'Add 1 to % photos of your products or shop.', bl_co_num('realbiz.max_images', 3)::int using errcode = 'P0001', hint = 'bad_image';
  end if;
  foreach v_img in array p_images loop
    if v_img !~ ('^' || v_uid::text || '/[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp)$')
       or not exists (select 1 from storage.objects o where o.bucket_id = 'real-biz' and o.name = v_img) then
      raise exception 'Upload your photos first.' using errcode = 'P0001', hint = 'bad_image';
    end if;
  end loop;
  if p_company is not null and not exists (select 1 from companies where id = p_company and owner_id = v_uid) then
    raise exception 'That company is not yours.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  select email into v_email from auth.users where id = v_uid;
  if coalesce(v_email, '') = '' then
    raise exception 'Your account needs an email address to pay.' using errcode = 'P0001', hint = 'no_email';
  end if;
  perform 1 from profiles where id = v_uid for update;
  perform bl_real_biz_sweep();
  if (select count(*) from real_businesses where owner_id = v_uid
       and (status in ('pending_review', 'live', 'suspended') or (status = 'awaiting_payment' and created_at > now() - interval '1 hour'))) >= bl_co_num('realbiz.max_per_player', 2) then
    raise exception 'You already have % listings running or waiting.', bl_co_num('realbiz.max_per_player', 2)::int using errcode = 'P0001', hint = 'limit';
  end if;
  if (select count(*) from real_businesses where owner_id = v_uid and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Too many tries. Wait a little and try again.' using errcode = 'P0001', hint = 'rate';
  end if;
  if bl_rb_area_used(a.id) >= bl_co_num('realbiz.max_per_area', 6) then
    raise exception '% is full for now: only % real businesses fit on the map there. Try another area or come back later.', a.name, bl_co_num('realbiz.max_per_area', 6)::int
      using errcode = 'P0001', hint = 'area_full';
  end if;
  select * into s from real_biz_slots where id = p_slot and area_id = a.id and active;
  if not found or not bl_rb_slot_free(s.id) then
    raise exception 'That map spot is not free. Pick another spot.' using errcode = 'P0001', hint = 'slot_taken';
  end if;
  v_ref := 'BLRB-' || replace(gen_random_uuid()::text, '-', '');
  insert into real_businesses (owner_id, name, category, descr, logo, phone, whatsapp, instagram, website, address, area_id, slot_id, images, company_id, terms_at, days, price_kobo, status, reference)
  values (v_uid, v_name, v_cat, v_desc, v_logo, v_phone, v_wa, v_ig, v_web, v_addr, a.id, s.id, p_images, p_company, now(), v_days, v_price, 'awaiting_payment', v_ref)
  returning id into v_id;
  return jsonb_build_object('biz_id', v_id, 'reference', v_ref, 'amount_kobo', v_price, 'email', v_email,
                            'currency', coalesce(bl_cfg_text('payments.currency'), 'NGN'), 'days', v_days);
end $$;

create or replace function public.real_biz_cancel(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update real_businesses set status = 'cancelled', updated_at = now() where id = p_id and owner_id = auth.uid() and status = 'awaiting_payment' and paid_at is null;
  get diagnostics n = row_count;
  return jsonb_build_object('cancelled', n > 0);
end $$;

create or replace function public.real_biz_mine() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_win numeric := bl_co_num('realbiz.renew_window_days', 7);
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  perform bl_real_biz_sweep();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', r.id, 'name', r.name, 'logo', r.logo, 'category', r.category, 'area', a.name, 'area_id', r.area_id, 'status', r.status, 'images', r.images,
      'days', r.days, 'price_kobo', r.price_kobo, 'starts_at', r.starts_at, 'ends_at', r.ends_at, 'created_at', r.created_at, 'reject_reason', r.reject_reason,
      'refund_status', r.refund_status, 'views', r.views, 'taps', r.taps, 'renewals', r.renewals, 'reports', r.reports,
      'can_renew', r.status = 'live' and r.ends_at - now() <= make_interval(days => v_win::int), 'renew_price_kobo', r.price_kobo) order by r.created_at desc)
    from real_businesses r join company_areas a on a.id = r.area_id where r.owner_id = v_uid and r.status <> 'cancelled'), '[]'::jsonb);
end $$;

create or replace function public.real_biz_renew_start(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); b real_businesses; v_email text; v_ref text; v_price bigint := bl_co_num('realbiz.price_kobo', 2500000)::bigint; v_days int := bl_co_num('realbiz.days', 30)::int;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  if not coalesce(bl_cfg_bool('realbiz.enabled'), false) or not coalesce(bl_cfg_bool('payments.enabled'), false) then
    raise exception 'Renewals are off right now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into b from real_businesses where id = p_id and owner_id = v_uid for update;
  if not found then
    raise exception 'That listing is not yours.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  if b.status <> 'live' then
    raise exception 'Only a live listing can be renewed (this one is %).', b.status using errcode = 'P0001', hint = 'bad_status';
  end if;
  if b.ends_at - now() > make_interval(days => bl_co_num('realbiz.renew_window_days', 7)::int) then
    raise exception 'You can renew in the last % days of the listing.', bl_co_num('realbiz.renew_window_days', 7)::int using errcode = 'P0001', hint = 'too_early';
  end if;
  select email into v_email from auth.users where id = v_uid;
  v_ref := 'BLRB-' || replace(gen_random_uuid()::text, '-', '');
  update real_businesses set renew_reference = v_ref, renew_price_kobo = v_price, renew_days = v_days, updated_at = now() where id = b.id;
  return jsonb_build_object('biz_id', b.id, 'reference', v_ref, 'amount_kobo', v_price, 'email', v_email,
                            'currency', coalesce(bl_cfg_text('payments.currency'), 'NGN'), 'days', v_days);
end $$;

-- map pins of every live listing (read-only; the client caches it)
create or replace function public.real_biz_map() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  return jsonb_build_object('pins', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name, 'logo', r.logo, 'x', s.x, 'y', s.y, 'area', r.area_id, 'category', r.category)
                                                              order by s.sort) from real_businesses r join real_biz_slots s on s.id = r.slot_id
                                                             where r.status = 'live' and r.ends_at > now()), '[]'::jsonb));
end $$;

-- the showcase sheet
create or replace function public.real_biz_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); r real_businesses; v_area text; v_cat text; v_co jsonb;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  select * into r from real_businesses where id = p_id;
  if not found or not ((r.status = 'live' and r.ends_at > now()) or r.owner_id = v_uid) then return null; end if;
  select name into v_area from company_areas where id = r.area_id;
  select name into v_cat from company_industries where id = r.category;
  if r.company_id is not null then
    select jsonb_build_object('id', c.id, 'name', c.name, 'logo', c.logo) into v_co from companies c where c.id = r.company_id and c.owner_id = r.owner_id;
  end if;
  return jsonb_build_object('id', r.id, 'name', r.name, 'logo', r.logo, 'category', r.category, 'category_name', coalesce(v_cat, 'Other'), 'descr', r.descr,
    'phone', r.phone, 'whatsapp', r.whatsapp, 'instagram', r.instagram, 'website', r.website, 'address', r.address, 'area', v_area, 'images', r.images,
    'company', v_co, 'verified', r.status = 'live', 'mine', r.owner_id = v_uid, 'status', r.status, 'ends_at', r.ends_at,
    'terms', bl_rb_text('realbiz.terms', 'Only legal businesses. No adult content, gambling, crypto schemes, weapons or drugs.'),
    'contact_email', bl_rb_text('realbiz.contact_email', 'code.devshalom@gmail.com'));
end $$;

-- views (sheet opened) and taps (a contact button): one per player per hour per listing, never your own
create or replace function public.real_biz_track(p_id uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); n int;
begin
  if v_uid is null or p_kind not in ('view', 'tap') then return jsonb_build_object('counted', false); end if;
  if not exists (select 1 from real_businesses where id = p_id and status = 'live' and owner_id is distinct from v_uid) then return jsonb_build_object('counted', false); end if;
  insert into real_biz_counter_log (user_id, biz_id, kind, at) values (v_uid, p_id, p_kind, now())
  on conflict (user_id, biz_id, kind) do update set at = excluded.at where real_biz_counter_log.at < now() - interval '1 hour';
  get diagnostics n = row_count;
  if n > 0 then
    if p_kind = 'view' then update real_businesses set views = views + 1 where id = p_id; else update real_businesses set taps = taps + 1 where id = p_id; end if;
  end if;
  return jsonb_build_object('counted', n > 0);
end $$;

create or replace function public.real_biz_report(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); r real_businesses; n int; v_alert int := greatest(1, bl_co_num('realbiz.report_alert', 1)::int);
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  select * into r from real_businesses where id = p_id and status = 'live' for update;
  if not found then
    raise exception 'That listing is not showing any more.' using errcode = 'P0001', hint = 'not_live';
  end if;
  if r.owner_id = v_uid then
    raise exception 'You can''t report your own listing.' using errcode = 'P0001', hint = 'own';
  end if;
  insert into real_biz_reports (biz_id, user_id, reason) values (r.id, v_uid, left(btrim(coalesce(p_reason, '')), 200)) on conflict do nothing;
  get diagnostics n = row_count;
  if n = 0 then
    return jsonb_build_object('reported', false, 'already', true, 'message', 'You already reported this listing. Thanks!');
  end if;
  update real_businesses set reports = reports + 1 where id = r.id returning reports into n;
  if n >= v_alert and (n = v_alert or (n % v_alert = 0 and ((n / v_alert) & ((n / v_alert) - 1)) = 0)) then
    perform bl_admin_notify('real_biz_reported', 'Real business reported · ' || r.name, n || (case when n = 1 then ' report' else ' reports' end) || coalesce(': "' || nullif(left(btrim(coalesce(p_reason, '')), 80), '') || '"', '') || '.',
                            jsonb_build_object('biz_id', r.id, 'reports', n), '/admin/real-business');
  end if;
  return jsonb_build_object('reported', true, 'message', 'Thanks. The Benin Life team will check this listing.');
end $$;

-- ---- admin
create or replace function public.admin_real_biz_queue(p_filter text default 'review', p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_filter text := coalesce(p_filter, 'review');
begin
  perform bl_real_biz_sweep();
  return jsonb_build_object(
    'counts', jsonb_build_object('review', (select count(*) from real_businesses where status = 'pending_review'), 'live', (select count(*) from real_businesses where status = 'live'),
      'suspended', (select count(*) from real_businesses where status = 'suspended'), 'reported', (select count(*) from real_businesses where status = 'live' and reports > 0),
      'refunds', (select count(*) from real_businesses where refund_status in ('pending', 'processing', 'refund_failed')),
      'ended', (select count(*) from real_businesses where status in ('expired', 'removed', 'rejected'))),
    'payments_enabled', coalesce(bl_cfg_bool('payments.enabled'), false),
    'areas', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'used', bl_rb_area_used(a.id), 'cap', bl_co_num('realbiz.max_per_area', 6)::int,
                         'slots', (select count(*) from real_biz_slots s where s.area_id = a.id and s.active)) order by a.tier, a.sort) from company_areas a where a.active), '[]'::jsonb),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name, 'logo', r.logo, 'category', r.category, 'descr', r.descr, 'phone', r.phone, 'whatsapp', r.whatsapp,
               'instagram', r.instagram, 'website', r.website, 'address', r.address, 'area_id', r.area_id, 'area', a.name, 'slot', r.slot_id, 'images', r.images, 'status', r.status,
               'days', r.days, 'price_kobo', r.price_kobo, 'paid_kobo', r.paid_kobo, 'paid_at', r.paid_at, 'created_at', r.created_at, 'starts_at', r.starts_at, 'ends_at', r.ends_at,
               'reviewed_at', r.reviewed_at, 'reviewer', (select username from profiles where id = r.reviewed_by), 'reject_reason', r.reject_reason,
               'refund_status', r.refund_status, 'refund_kobo', r.refund_kobo, 'refund_error', r.refund_error, 'reference', r.reference, 'user_id', r.owner_id,
               'username', p.username, 'email', u.email, 'views', r.views, 'taps', r.taps, 'reports', r.reports, 'renewals', r.renewals, 'terms_at', r.terms_at, 'company_id', r.company_id,
               'report_reasons', (select coalesce(jsonb_agg(x.reason order by x.created_at desc), '[]'::jsonb) from (select reason, created_at from real_biz_reports where biz_id = r.id and reason <> '' order by created_at desc limit 5) x))
             order by case when v_filter = 'review' then r.paid_at end asc nulls last, r.created_at desc)
        from (select * from real_businesses x where case v_filter
                 when 'review' then x.status = 'pending_review' when 'live' then x.status = 'live' when 'suspended' then x.status = 'suspended'
                 when 'reported' then x.status = 'live' and x.reports > 0 when 'refunds' then x.refund_status in ('pending', 'processing', 'refund_failed')
                 when 'ended' then x.status in ('expired', 'removed', 'rejected') else x.status not in ('awaiting_payment', 'cancelled') end
               order by x.created_at desc limit greatest(1, least(coalesce(p_limit, 100), 300))) r
        join company_areas a on a.id = r.area_id left join profiles p on p.id = r.owner_id left join auth.users u on u.id = r.owner_id), '[]'::jsonb));
end $$;

create or replace function public.admin_real_biz_approve(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); b real_businesses;
begin
  select * into b from real_businesses where id = p_id for update;
  if not found then
    raise exception 'No such listing.' using errcode = 'P0001', hint = 'unknown';
  end if;
  if b.status <> 'pending_review' or b.paid_at is null then
    raise exception 'Only paid listings waiting for review can be approved (this one is %).', b.status using errcode = 'P0001', hint = 'bad_status';
  end if;
  update real_businesses set status = 'live', reviewed_by = v_admin, reviewed_at = now(), starts_at = now(), ends_at = now() + make_interval(days => b.days), updated_at = now()
   where id = b.id returning * into b;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'real_biz_approve', b.owner_id, jsonb_build_object('biz_id', b.id, 'name', b.name, 'area', b.area_id, 'days', b.days, 'ends_at', b.ends_at));
  if b.owner_id is not null and exists (select 1 from profiles where id = b.owner_id) then
    perform bl_event(b.owner_id, 'real_biz_approved', b.name || ' is on the map!', 'Players can find your verified business pin now, until ' || to_char(b.ends_at at time zone 'Africa/Lagos', 'Dy DD Mon') || '. See views and taps in the Company app.', jsonb_build_object('biz_id', b.id));
  end if;
  return jsonb_build_object('message', 'Approved. The pin is live now.', 'biz_id', b.id, 'ends_at', b.ends_at);
end $$;

create or replace function public.admin_real_biz_reject(p_id uuid, p_reason text, p_refund boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); b real_businesses; v_reason text := left(btrim(coalesce(p_reason, '')), 300); v_refund boolean;
begin
  if v_reason = '' then
    raise exception 'Write a short reason (the owner sees it).' using errcode = 'P0001', hint = 'reason';
  end if;
  select * into b from real_businesses where id = p_id for update;
  if not found then
    raise exception 'No such listing.' using errcode = 'P0001', hint = 'unknown';
  end if;
  if b.status <> 'pending_review' then
    raise exception 'Only listings waiting for review can be rejected (this one is %).', b.status using errcode = 'P0001', hint = 'bad_status';
  end if;
  v_refund := coalesce(p_refund, true) and coalesce(b.paid_kobo, 0) > 0 and b.reference is not null;
  update real_businesses set status = 'rejected', reviewed_by = v_admin, reviewed_at = now(), reject_reason = v_reason,
         refund_status = case when v_refund then 'pending' else refund_status end, refund_kobo = case when v_refund then b.paid_kobo else refund_kobo end, updated_at = now()
   where id = b.id;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'real_biz_reject', b.owner_id, jsonb_build_object('biz_id', b.id, 'name', b.name, 'reason', v_reason, 'refund', v_refund, 'paid_kobo', b.paid_kobo));
  if b.owner_id is not null and exists (select 1 from profiles where id = b.owner_id) then
    perform bl_event(b.owner_id, 'real_biz_rejected', b.name || ' not approved', 'Reason: ' || v_reason || case when v_refund then ' Your money is being refunded.' else '' end, jsonb_build_object('biz_id', b.id));
  end if;
  return jsonb_build_object('message', case when v_refund then 'Rejected. Refunding now…' else 'Rejected.' end, 'biz_id', b.id, 'refund', v_refund);
end $$;

-- take a live pin off the map but keep the listing (the owner is told why); unsuspend puts it back for the time that is left
create or replace function public.admin_real_biz_suspend(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); b real_businesses; v_reason text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if v_reason = '' then
    raise exception 'Write a short reason (the owner sees it).' using errcode = 'P0001', hint = 'reason';
  end if;
  select * into b from real_businesses where id = p_id for update;
  if not found then
    raise exception 'No such listing.' using errcode = 'P0001', hint = 'unknown';
  end if;
  if b.status <> 'live' then
    raise exception 'Only live listings can be suspended (this one is %).', b.status using errcode = 'P0001', hint = 'bad_status';
  end if;
  update real_businesses set status = 'suspended', suspended_at = now(), reject_reason = v_reason, updated_at = now() where id = b.id;
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'real_biz_suspend', b.owner_id, jsonb_build_object('biz_id', b.id, 'name', b.name, 'reason', v_reason));
  if b.owner_id is not null and exists (select 1 from profiles where id = b.owner_id) then
    perform bl_event(b.owner_id, 'real_biz_suspended', b.name || ' taken off the map', 'Reason: ' || v_reason || ' Write to ' || bl_rb_text('realbiz.contact_email', 'the owner') || ' if you think this is a mistake.', jsonb_build_object('biz_id', b.id));
  end if;
  return jsonb_build_object('message', 'Suspended. The pin is off the map.', 'biz_id', b.id);
end $$;

create or replace function public.admin_real_biz_unsuspend(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); b real_businesses;
begin
  select * into b from real_businesses where id = p_id for update;
  if not found then
    raise exception 'No such listing.' using errcode = 'P0001', hint = 'unknown';
  end if;
  if b.status <> 'suspended' then
    raise exception 'Only suspended listings can be put back (this one is %).', b.status using errcode = 'P0001', hint = 'bad_status';
  end if;
  update real_businesses set status = 'live', ends_at = ends_at + (now() - coalesce(suspended_at, now())), suspended_at = null, reject_reason = null, updated_at = now() where id = b.id returning * into b;
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'real_biz_unsuspend', b.owner_id, jsonb_build_object('biz_id', b.id, 'name', b.name));
  if b.owner_id is not null and exists (select 1 from profiles where id = b.owner_id) then
    perform bl_event(b.owner_id, 'real_biz_approved', b.name || ' is back on the map', 'Your pin is live again.', jsonb_build_object('biz_id', b.id));
  end if;
  return jsonb_build_object('message', 'Back on the map.', 'biz_id', b.id);
end $$;

create or replace function public.admin_real_biz_remove(p_id uuid, p_reason text, p_refund boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); b real_businesses; v_reason text := left(btrim(coalesce(p_reason, '')), 300); v_refund boolean;
begin
  select * into b from real_businesses where id = p_id for update;
  if not found then
    raise exception 'No such listing.' using errcode = 'P0001', hint = 'unknown';
  end if;
  if b.status not in ('live', 'suspended', 'pending_review') then
    raise exception 'Only live, suspended or waiting listings can be removed (this one is %).', b.status using errcode = 'P0001', hint = 'bad_status';
  end if;
  v_refund := coalesce(p_refund, false) and coalesce(b.paid_kobo, 0) > 0 and b.reference is not null and b.refund_status = 'none';
  update real_businesses set status = 'removed', ends_at = least(coalesce(ends_at, now()), now()), reviewed_by = v_admin, reviewed_at = now(), reject_reason = nullif(v_reason, ''),
         refund_status = case when v_refund then 'pending' else refund_status end, refund_kobo = case when v_refund then b.paid_kobo else refund_kobo end, updated_at = now()
   where id = b.id;
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'real_biz_remove', b.owner_id, jsonb_build_object('biz_id', b.id, 'name', b.name, 'reason', v_reason, 'refund', v_refund));
  if b.owner_id is not null and exists (select 1 from profiles where id = b.owner_id) then
    perform bl_event(b.owner_id, 'real_biz_removed', b.name || ' removed', coalesce('Reason: ' || nullif(v_reason, '') || ' ', '') || case when v_refund then 'Your money is being refunded.' else 'Listings that break the rules are removed without a refund.' end,
                     jsonb_build_object('biz_id', b.id));
  end if;
  return jsonb_build_object('message', case when v_refund then 'Removed. Refunding now…' else 'Removed.' end, 'biz_id', b.id, 'refund', v_refund);
end $$;

-- billboard-refund Edge Function calls this with the admin's JWT first (admin check + audit), then refunds
create or replace function public.admin_real_biz_refund_start(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); b real_businesses;
begin
  select * into b from real_businesses where id = p_id;
  if not found then
    raise exception 'No such listing.' using errcode = 'P0001', hint = 'unknown';
  end if;
  if b.refund_status not in ('pending', 'processing', 'refund_failed') then
    raise exception 'No refund is due on this listing (%).', b.refund_status using errcode = 'P0001', hint = 'no_refund_due';
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'real_biz_refund', b.owner_id, jsonb_build_object('biz_id', b.id, 'reference', b.reference, 'amount_kobo', coalesce(b.refund_kobo, b.paid_kobo), 'retry', b.refund_status = 'refund_failed'));
  return jsonb_build_object('ok', true, 'biz_id', b.id);
end $$;

-- Admin -> Payments: what the real-business listings brought in
create or replace function public.admin_real_biz_revenue() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_today timestamptz := (date_trunc('day', now() at time zone 'Africa/Lagos')) at time zone 'Africa/Lagos';
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'today_kobo', (select coalesce(sum(paid_kobo), 0) from real_businesses where paid_at >= v_today and (refund_status <> 'refunded')),
    'd7_kobo', (select coalesce(sum(paid_kobo), 0) from real_businesses where paid_at >= now() - interval '7 days' and (refund_status <> 'refunded')),
    'all_kobo', (select coalesce(sum(paid_kobo + renewals * price_kobo), 0) from real_businesses where paid_at is not null and (refund_status <> 'refunded')),
    'renew_count', (select coalesce(sum(renewals), 0) from real_businesses),
    'paid_count', (select count(*) from real_businesses where paid_at is not null and status not in ('rejected')),
    'refunded_kobo', (select coalesce(sum(refund_kobo), 0) from real_businesses where refund_status = 'refunded'),
    'refund_due', (select count(*) from real_businesses where refund_status in ('pending', 'processing', 'refund_failed')),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name, 'username', p.username, 'paid_kobo', r.paid_kobo, 'paid_at', r.paid_at, 'status', r.status,
                'refund_status', r.refund_status, 'reference', r.reference, 'renewals', r.renewals) order by r.paid_at desc)
              from (select * from real_businesses where paid_at is not null order by paid_at desc limit 30) r left join profiles p on p.id = r.owner_id), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 13. Grants: private helpers are revoked from every client role; RPCs are for signed-in players
-- ---------------------------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace and (p.proname like 'bl\_co\_%' or p.proname like 'bl\_rb\_%' or p.proname like 'bl\_real\_biz\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;
-- service-role entry points (the Edge Functions)
grant execute on function public.bl_real_biz_sweep() to service_role;
grant execute on function public.bl_real_biz_paid(text, bigint, jsonb) to service_role;
grant execute on function public.bl_real_biz_refund_claim(uuid) to service_role;
grant execute on function public.bl_real_biz_refund_result(uuid, boolean, text, jsonb) to service_role;

do $$
declare f text; r record;
begin
  foreach f in array array['company_status', 'company_register', 'company_branch_add', 'company_branch_upgrade', 'company_hire', 'company_fire', 'company_manager',
    'company_generator', 'company_set_pricing', 'company_marketing_buy', 'company_cashout', 'company_sell', 'company_rankings', 'company_discover',
    'real_biz_form', 'real_biz_create', 'real_biz_cancel', 'real_biz_mine', 'real_biz_renew_start', 'real_biz_map', 'real_biz_get', 'real_biz_track', 'real_biz_report',
    'admin_company_overview', 'admin_company_remove', 'admin_real_biz_queue', 'admin_real_biz_approve', 'admin_real_biz_reject', 'admin_real_biz_suspend',
    'admin_real_biz_unsuspend', 'admin_real_biz_remove', 'admin_real_biz_refund_start', 'admin_real_biz_revenue'] loop
    for r in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f loop
      execute format('revoke all on function %s from public, anon', r.sig);
      execute format('grant execute on function %s to authenticated, service_role', r.sig);
    end loop;
  end loop;
end $$;
-- the public company card (share link /c/<id>) works without signing in
revoke all on function public.company_public(bigint) from public;
grant execute on function public.company_public(bigint) to anon, authenticated, service_role;

notify pgrst, 'reload schema';
