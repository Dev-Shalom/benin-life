-- R10: own a business (docs/BUSINESS.md).
-- Players buy a real business on a fixed, limited plot, run it, upgrade it and sell it. It is the active, ownable version of
-- the passive invest units (farms, transport, POS): invest units are not touched.
--   1. config `business.*` (game_config, Settings -> Business): caps, restock, staff, events, insurance, owner cut, sell-back.
--   2. business_types (admin table, Content -> Business types): buy price, setup minutes, allowed areas, base income range,
--      running costs (rent, NEPA / diesel, staff wage), risk events, per-level upgrade cost + income multiplier, staff slots,
--      boost, and the requirement (Business skill level and / or a certificate).
--   3. business_plots (admin table, Content -> Business plots): the fixed slots per named area. Each plot IS a row of
--      `locations` (inactive until sold; the pin, the interior and travel all come from the existing places code). Adding a
--      plot in admin creates its location (trigger). First come, first served.
--   4. businesses (one row per owned plot), business_log (events log). Income accrues per real hour and is settled LAZILY on
--      read / collect (no cron): bl_biz_settle(). Uncollected takings stop at business.cap_hours (48). Stock: a restock keeps
--      income at 100 %, without it income falls to business.stock_floor_pct (50). Staff: wage per day, more income, fewer
--      problems. Owner shift (business_work): boost + Business XP. Events (once per full business day, forced with
--      bl.test_rand): robbery (insurance cuts it), NEPA outage, task force / council levy, great day, staff theft.
--   5. Visitors: a share of what a player spends at somebody else's business goes to the owner as real income (ledger
--      'business_income'). do_activity / shop_buy / place_interior are patched (guarded) for the cut and for the stock list.
--   6. Selling: back to the system at business.sell_back_pct of what was invested, or on the Market (R9) as kind 'business'.
--   7. Admin: Content tabs, Business view, grant / remove (audited). "Takings ready" push (money, at most one a day) is queued
--      for later at every collect and cancelled when the player collects.
--   8. Ledger: business_income counts as earned (leaderboard.earn_reasons); business_buy / _upgrade / _stock / _hire /
--      _insure / _sell do not.
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
('business.enabled', 'true', 'business', 'Business ownership on',
 'R10 (docs/BUSINESS.md): players can buy and run a business. Off = buying, upgrades, hiring and shifts are refused; collecting and selling still work.', 'bool', null, null),
('business.max_owned', '3', 'business', 'Businesses one player can own',
 'R10: most businesses one player can own at the same time (the Market and admin grants respect it too).', 'number', 1, 20),
('business.cap_hours', '48', 'business', 'Uncollected takings stop after (hours)',
 'R10: takings stop growing this many real hours after the last collect, so players have to log in. Collecting starts the clock again.', 'number', 1, 720),
('business.stock_hours', '48', 'business', 'One restock lasts (hours)',
 'R10: a restock purchase adds this many real hours of stock. While there is stock, income is 100 %.', 'number', 1, 720),
('business.stock_max_hours', '168', 'business', 'Most stock you can hold (hours)',
 'R10: restocking never takes the stock past this many real hours from now.', 'number', 1, 2000),
('business.stock_decay_hours', '24', 'business', 'Income falls to the floor over (hours)',
 'R10: when stock runs out, income slides from 100 % down to the floor over this many real hours.', 'number', 0, 720),
('business.stock_floor_pct', '50', 'business', 'Income with no stock (% floor)',
 'R10: the lowest income a stock-hungry business makes (shops, bukas, bars, filling stations ...) when it has not been restocked.', 'percent', 0, 100),
('business.skill_pct_per_level', '1.5', 'business', 'Owner Business skill: income % per level',
 'R10: each Business skill level above 1 adds this % to the income of every business the player owns.', 'number', 0, 20),
('business.hire_fee_days', '2', 'business', 'Hiring fee (days of wage)',
 'R10: hiring one staff member costs this many days of their wage up front.', 'number', 0, 30),
('business.insurance_cost_pct', '3', 'business', 'Insurance price (% of buy price)',
 'R10: one insurance period costs this % of the business buy price.', 'percent', 0, 100),
('business.insurance_days', '7', 'business', 'Insurance lasts (days)',
 'R10: real days one insurance purchase covers.', 'number', 1, 90),
('business.insurance_cover_pct', '80', 'business', 'Insurance covers (% of a robbery loss)',
 'R10: an insured business loses only the rest of a robbery.', 'percent', 0, 100),
('business.shift_seconds', '60', 'business', 'Owner shift lasts (real seconds)',
 'R10: working a shift at your own business keeps your Sim busy this long.', 'number', 5, 1800),
('business.shift_energy', '12', 'business', 'Owner shift energy cost',
 'R10: energy points a shift costs (the player needs at least this much, and hunger of 10).', 'number', 0, 100),
('business.shift_boost_hours', '8', 'business', 'Shift boost lasts (hours)',
 'R10: after a shift the business earns the boost % of its type for this many real hours.', 'number', 1, 168),
('business.shift_daily_cap', '6', 'business', 'Owner shifts per Benin day',
 'R10: shifts a player can work at their businesses per Benin day (stops XP grinding).', 'number', 1, 100),
('business.visit_cut_pct', '30', 'business', 'Owner cut of visitor spending (%)',
 'R10: when another player spends at your business (food, drinks, shop items) this % of the price is paid to you as real income. Spending at your own business pays no cut.', 'percent', 0, 100),
('business.sell_back_pct', '60', 'business', 'Sell back to the system (% of invested)',
 'R10: selling to the system pays this % of what the owner invested (buy price plus upgrades). Gifted businesses invested nothing.', 'percent', 0, 100),
('business.staff_event_cut_pct', '10', 'business', 'Each staff member cuts robbery / levy chance by (%)',
 'R10: relative cut per staff member of the robbery and levy chances, up to 50 % in all. An owner shift (boost active) halves staff theft and robbery.', 'percent', 0, 50),
('business.robbery_pct', '6', 'business', 'Robbery chance per business day (%)',
 'R10: rolled once per full 24 real hours of earning, per business. A type can set its own in Content -> Business types -> Events.', 'percent', 0, 100),
('business.robbery_loss_pct', '40', 'business', 'Robbery takes (% of takings)',
 'R10: a robbery takes this % of the uncollected takings; insurance covers part of it.', 'percent', 0, 100),
('business.outage_pct', '14', 'business', 'NEPA outage chance per business day (%)',
 'R10: light off, diesel up: the day earns less.', 'percent', 0, 100),
('business.outage_loss_pct', '50', 'business', 'NEPA outage costs (% of a day''s income)',
 'R10: a day''s income lost to the outage and the diesel.', 'percent', 0, 100),
('business.levy_pct', '8', 'business', 'Task force / council levy chance per business day (%)',
 'R10: the Lagos-style "Oga, bring your paper" visit.', 'percent', 0, 100),
('business.levy_loss_pct', '35', 'business', 'Levy takes (% of a day''s income)',
 'R10: the levy is this % of one day''s income, taken from the takings.', 'percent', 0, 100),
('business.goodday_pct', '10', 'business', 'Great day chance per business day (%)',
 'R10: a bumper day. An Event centre has a much higher chance (its own events setting).', 'percent', 0, 100),
('business.goodday_bonus_pct', '60', 'business', 'Great day adds (% of a day''s income)',
 'R10: extra takings on a great day.', 'percent', 0, 1000),
('business.theft_pct', '8', 'business', 'Staff theft chance per business day (%)',
 'R10: only when the business has staff.', 'percent', 0, 100),
('business.theft_loss_pct', '20', 'business', 'Staff theft takes (% of a day''s income)',
 'R10: taken from the takings.', 'percent', 0, 100),
('business.push_hours', '36', 'business', '"Takings ready" push after the last collect (hours)',
 'R10: a Money push is queued this many real hours after a collect (before the cap), at most one per player per day. Collecting cancels it.', 'number', 1, 720)
on conflict (key) do nothing;

-- business income is earned money (weekly top earners, challenge "earn"). Added once: an admin who removes it later stays removed.
do $$
begin
  if not exists (select 1 from public.game_config where key = 'business.earn_seeded') then
    update public.game_config
       set value = to_jsonb(rtrim((value #>> '{}'), ',') || ',business_income')
     where key = 'leaderboard.earn_reasons' and position('business_income' in (value #>> '{}')) = 0;
    insert into public.game_config (key, value, category, label, description, kind)
    values ('business.earn_seeded', 'true', 'business', 'Business income counted as earned (seeded)',
            'R10: set once by the migration so business_income is in leaderboard.earn_reasons. Leave it.', 'bool');
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.business_types (
  id               text primary key,
  name             text not null,
  icon             text not null default '🏪',
  blurb            text not null default '',
  scene            text not null default 'market',          -- the place type its interior / cards use
  price            bigint not null default 500000 check (price >= 0),
  setup_minutes    int not null default 30 check (setup_minutes >= 0),
  areas            text[] not null default '{}',             -- plot areas it may be built in (business_plots.area)
  income_min       bigint not null default 10000 check (income_min >= 0),   -- gross income per real 24 h at level 1
  income_max       bigint not null default 15000 check (income_max >= income_min),
  rent_day         bigint not null default 1000 check (rent_day >= 0),
  power_day        bigint not null default 1000 check (power_day >= 0),     -- NEPA / diesel
  staff_slots      int not null default 2 check (staff_slots >= 0),
  staff_wage       bigint not null default 2000 check (staff_wage >= 0),    -- per staff member per day
  staff_income_pct numeric not null default 15 check (staff_income_pct >= 0),
  restock_cost     bigint not null default 0 check (restock_cost >= 0),     -- 0 = needs no stock
  req_skill_level  int not null default 1 check (req_skill_level >= 1),
  req_cert         text,                                                     -- certificate id(s), comma = either
  max_level        int not null default 4 check (max_level >= 1 and max_level <= 10),
  levels           jsonb not null default '{}'::jsonb,       -- {"2": {"cost": 240000, "mult": 1.4}, ...}
  boost_pct        numeric not null default 20 check (boost_pct >= 0),      -- owner shift boost
  events           jsonb not null default '{}'::jsonb,       -- {"robbery": {"chance_pct": 9, "loss_pct": 40}, ...}
  sort             int not null default 100,
  active           boolean not null default true
);

create table if not exists public.business_plots (
  id         text primary key,                                 -- also the id of its row in `locations`
  area       text not null,                                    -- ring_road, uselu, ugbowo, sapele_rd, airport_rd, gra, ...
  area_label text not null default '',
  district   text not null default 'oredo',                    -- locations.district
  label      text not null,
  x          numeric not null,
  y          numeric not null,
  type_ids   text[] not null default '{}',                     -- empty = any type that allows the area
  price_mult numeric not null default 1 check (price_mult > 0),
  sort       int not null default 100,
  active     boolean not null default true
);

create table if not exists public.businesses (
  id               bigserial primary key,
  owner_id         uuid not null references public.profiles(id) on delete cascade,
  plot_id          text not null references public.business_plots(id),
  type_id          text not null references public.business_types(id),
  name             text not null,
  level            int not null default 1 check (level >= 1),
  base_income      bigint not null,                              -- rolled in the type's range at purchase (per real 24 h)
  invested         bigint not null default 0,                    -- paid by the owner (buy + upgrades): what sell-back refunds from
  bought_at        timestamptz not null default now(),
  ready_at         timestamptz not null default now(),           -- setup done: income and costs start here
  settled_at       timestamptz not null default now(),           -- earned up to here
  last_collect_at  timestamptz not null default now(),           -- the 48 h cap counts from here
  event_carry_h    numeric not null default 0,
  takings          numeric not null default 0,
  stock_until      timestamptz not null default now(),
  staff            int not null default 0 check (staff >= 0),
  boost_until      timestamptz,
  insured_until    timestamptz,
  listed           boolean not null default false,               -- escrowed on the Market
  lifetime_income  bigint not null default 0,
  lifetime_visit   bigint not null default 0,
  source           text not null default 'buy' check (source in ('buy', 'admin', 'market'))
);
create unique index if not exists businesses_plot_uq on public.businesses (plot_id);
create index if not exists businesses_owner_idx on public.businesses (owner_id);

create table if not exists public.business_log (
  id          bigserial primary key,
  business_id bigint not null references public.businesses(id) on delete cascade,
  owner_id    uuid not null,
  kind        text not null,
  title       text not null,
  amount      bigint not null default 0,
  data        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists business_log_biz_idx on public.business_log (business_id, id desc);
create index if not exists business_log_day_idx on public.business_log (owner_id, kind, created_at);

-- the place a business sits in: shown on the map / place card
alter table public.locations add column if not exists biz_id bigint;
alter table public.locations add column if not exists biz_owner text;
alter table public.locations add column if not exists biz_level int;
alter table public.locations add column if not exists biz_type text;

alter table public.business_types  enable row level security;
alter table public.business_plots  enable row level security;
alter table public.businesses      enable row level security;
alter table public.business_log    enable row level security;
revoke all on public.business_types, public.business_plots, public.businesses, public.business_log from public, anon, authenticated;
revoke all on sequence public.businesses_id_seq, public.business_log_id_seq from public, anon, authenticated;
grant select on public.business_types, public.business_plots to authenticated;
drop policy if exists business_types_read on public.business_types;
create policy business_types_read on public.business_types for select to authenticated using (true);
drop policy if exists business_plots_read on public.business_plots;
create policy business_plots_read on public.business_plots for select to authenticated using (true);
grant select on public.businesses, public.business_log to authenticated;
drop policy if exists businesses_own on public.businesses;
create policy businesses_own on public.businesses for select to authenticated using (owner_id = (select auth.uid()));
drop policy if exists business_log_own on public.business_log;
create policy business_log_own on public.business_log for select to authenticated using (owner_id = (select auth.uid()));

-- market kind
do $$
declare r record;
begin
  for r in select c.conrelid::regclass as tbl, c.conname from pg_constraint c
            where c.contype = 'c' and c.conrelid in ('public.market_listings'::regclass, 'public.market_settings'::regclass)
              and pg_get_constraintdef(c.oid) like '%kind%' and pg_get_constraintdef(c.oid) like '%land%'
              and pg_get_constraintdef(c.oid) not like '%business%' loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format('alter table %s add constraint %I check (kind in (''item'', ''furniture'', ''car'', ''land'', ''business''))', r.tbl, r.conname);
  end loop;
end $$;

insert into public.market_settings (kind, label, enabled, fee_pct, floor_pct, ceiling_pct, sort) values
('business', 'Businesses', true, 8, 50, 250, 50)
on conflict (kind) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. Seeds: types and plots
-- ---------------------------------------------------------------------------------------------
-- {"2": {"cost": price * pct, "mult": m}, ...}
create or replace function pg_temp.bl_biz_levels(p_price bigint, p_pcts numeric[], p_mults numeric[]) returns jsonb
language plpgsql as $$
declare v jsonb := '{}'::jsonb; i int;
begin
  for i in 1 .. cardinality(p_pcts) loop
    v := v || jsonb_build_object((i + 1)::text, jsonb_build_object('cost', round(p_price * p_pcts[i] / 100 / 1000) * 1000, 'mult', p_mults[i]));
  end loop;
  return v;
end $$;

insert into public.business_types (id, name, icon, blurb, scene, price, setup_minutes, areas, income_min, income_max, rent_day, power_day,
  staff_slots, staff_wage, staff_income_pct, restock_cost, req_skill_level, req_cert, max_level, levels, boost_pct, events, sort) values
('provision_shop', 'Provision shop / mini-mart', '🏪', 'Noodles, Indomie, drinks, soap and everything the street needs. Steady money, but keep the shelves full.', 'market',
  600000, 20, '{ring_road,uselu,ugbowo,sapele_rd,airport_rd,gra,new_benin,ikpoba_hill}', 12000, 18000, 1500, 1000, 2, 2000, 15, 18000, 1, null, 4,
  pg_temp.bl_biz_levels(600000, '{40,80,150}', '{1.4,1.9,2.6}'), 20, '{}', 10),
('buka', 'Buka / chop house', '🍲', 'Pepper soup, swallow and rice for the hungry crowd. Customers keep coming if the pots are full.', 'buka',
  900000, 30, '{ring_road,uselu,ugbowo,sapele_rd,airport_rd,new_benin,ikpoba_hill}', 16000, 24000, 2000, 2000, 3, 2500, 14, 25000, 1, null, 4,
  pg_temp.bl_biz_levels(900000, '{40,80,150}', '{1.4,1.9,2.6}'), 25, '{}', 20),
('salon', 'Barbing & hair salon', '✂️', 'Fresh cuts, braids and gist. Low stock cost, loyal customers.', 'salon',
  700000, 20, '{ring_road,uselu,ugbowo,sapele_rd,gra,new_benin}', 12000, 19000, 1500, 1500, 2, 2500, 16, 8000, 1, null, 4,
  pg_temp.bl_biz_levels(700000, '{40,80,150}', '{1.4,1.9,2.6}'), 20, '{}', 30),
('car_wash', 'Car wash', '🚿', 'Bucket, hose and a pump on diesel. The pump is what NEPA likes to spoil.', 'street',
  1000000, 45, '{sapele_rd,airport_rd,gra,ring_road,ikpoba_hill}', 14000, 22000, 1500, 2000, 3, 2000, 18, 6000, 2, null, 4,
  pg_temp.bl_biz_levels(1000000, '{40,80,150}', '{1.4,1.9,2.6}'), 20, '{"outage": {"chance_pct": 20}}', 40),
('pos_centre', 'PoS & business centre', '💳', 'Cash-out, printing, photocopy and recharge cards. Cash on the counter attracts the wrong eyes.', 'pos',
  1200000, 30, '{ring_road,uselu,ugbowo,sapele_rd,airport_rd,gra,new_benin,ikpoba_hill}', 18000, 27000, 2000, 2500, 2, 2500, 15, 0, 2, null, 4,
  pg_temp.bl_biz_levels(1200000, '{40,80,150}', '{1.4,1.9,2.6}'), 20, '{"robbery": {"chance_pct": 8}}', 50),
('beer_parlour', 'Beer parlour / bar', '🍺', 'Cold Star, pepper soup and loud football. Big takings, big temptations.', 'lounge',
  1800000, 45, '{uselu,ugbowo,sapele_rd,gra,ring_road,airport_rd}', 28000, 42000, 3500, 4000, 4, 3000, 12, 55000, 3, null, 4,
  pg_temp.bl_biz_levels(1800000, '{40,80,150}', '{1.4,1.9,2.6}'), 25, '{"robbery": {"chance_pct": 9}}', 60),
('chemist', 'Chemist shop', '💊', 'Pharmacy-style chemist: paracetamol, malaria drugs and a trusted counter. Needs a head for numbers.', 'market',
  2800000, 60, '{uselu,ugbowo,gra,ring_road,new_benin}', 30000, 45000, 3000, 2500, 2, 4000, 12, 70000, 3, 'accounting,business_mgmt', 4,
  pg_temp.bl_biz_levels(2800000, '{40,80,150}', '{1.4,1.9,2.6}'), 20, '{}', 70),
('filling_station', 'Filling station', '⛽', 'Pumps, a tanker once a week and a queue that never ends. Expensive, and it pays.', 'motorpark',
  9000000, 240, '{sapele_rd,airport_rd,ring_road,ikpoba_hill}', 90000, 130000, 8000, 9000, 5, 5000, 10, 280000, 4, 'business_mgmt', 5,
  pg_temp.bl_biz_levels(9000000, '{30,60,100,160}', '{1.3,1.7,2.2,3.0}'), 20, '{"robbery": {"chance_pct": 10, "loss_pct": 35}}', 80),
('event_centre', 'Event centre', '🎪', 'Owambe halls, weddings and conferences. It earns from events: slow weeks, then a huge booking.', 'hotel',
  18000000, 360, '{gra,sapele_rd,ugbowo,airport_rd}', 160000, 260000, 12000, 15000, 5, 6000, 10, 0, 6, 'business_mgmt', 5,
  pg_temp.bl_biz_levels(18000000, '{30,60,100,160}', '{1.3,1.7,2.2,3.0}'), 20, '{"goodday": {"chance_pct": 35, "bonus_pct": 120}}', 90)
on conflict (id) do nothing;

insert into public.business_plots (id, area, area_label, district, label, x, y, type_ids, price_mult, sort) values
('biz_ring_road_1', 'ring_road', 'Ring Road', 'oredo', 'Ring Road plot 1', 472, 383, '{}', 1.15, 110),
('biz_ring_road_2', 'ring_road', 'Ring Road', 'oredo', 'Ring Road plot 2', 500, 439, '{}', 1.15, 111),
('biz_ring_road_3', 'ring_road', 'Ring Road', 'oredo', 'Ring Road plot 3', 498, 342, '{}', 1.1, 112),
('biz_uselu_1', 'uselu', 'Uselu', 'uselu', 'Uselu plot 1', 520, 248, '{}', 1.0, 120),
('biz_uselu_2', 'uselu', 'Uselu', 'uselu', 'Uselu plot 2', 447, 333, '{}', 1.0, 121),
('biz_ugbowo_1', 'ugbowo', 'Ugbowo', 'ugbowo', 'Ugbowo plot 1', 504, 90, '{}', 1.05, 130),
('biz_ugbowo_2', 'ugbowo', 'Ugbowo', 'ugbowo', 'Ugbowo plot 2', 555, 90, '{}', 1.05, 131),
('biz_ugbowo_3', 'ugbowo', 'Ugbowo', 'ugbowo', 'Ugbowo plot 3', 524, 45, '{}', 1.0, 132),
('biz_sapele_rd_1', 'sapele_rd', 'Sapele Rd', 'sapele_rd', 'Sapele Rd plot 1', 654, 688, '{}', 1.0, 140),
('biz_sapele_rd_2', 'sapele_rd', 'Sapele Rd', 'sapele_rd', 'Sapele Rd plot 2', 623, 769, '{}', 1.0, 141),
('biz_sapele_rd_3', 'sapele_rd', 'Sapele Rd', 'sapele_rd', 'Sapele Rd plot 3', 613, 702, '{}', 1.0, 142),
('biz_airport_rd_1', 'airport_rd', 'Airport Rd', 'airport_rd', 'Airport Rd plot 1', 346, 679, '{}', 0.95, 150),
('biz_airport_rd_2', 'airport_rd', 'Airport Rd', 'airport_rd', 'Airport Rd plot 2', 264, 628, '{}', 0.9, 151),
('biz_gra_1', 'gra', 'GRA', 'gra', 'GRA plot 1', 453, 781, '{}', 1.3, 160),
('biz_gra_2', 'gra', 'GRA', 'gra', 'GRA plot 2', 381, 791, '{}', 1.3, 161),
('biz_gra_3', 'gra', 'GRA', 'gra', 'GRA plot 3', 444, 736, '{}', 1.35, 162),
('biz_new_benin_1', 'new_benin', 'New Benin', 'new_benin', 'New Benin plot 1', 611, 407, '{}', 1.0, 170),
('biz_ikpoba_hill_1', 'ikpoba_hill', 'Ikpoba Hill', 'ikpoba_hill', 'Ikpoba Hill plot 1', 724, 380, '{}', 0.9, 180)
on conflict (id) do nothing;

insert into public.skill_sources (id, kind, ref, skill_id, xp, note, active) values
('activity:business_shift:business', 'activity', 'business_shift', 'business', 10, 'R10: a shift at your own business (not a real activity id: business_work() awards it)', true)
on conflict (id) do nothing;

-- every plot is a place on the map (hidden until somebody owns it)
create or replace function public.bl_biz_plot_loc() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into locations (id, name, district, scene, blurb, risk, night_risk_mult, cctv, keke_ok, congestion, remote_km, x, y, actions, sort, active)
  values (new.id, new.label, new.district, 'street', 'A business plot in ' || coalesce(nullif(new.area_label, ''), new.area) || '.',
          0.2, 1.5, false, true, 1.0, 0, new.x, new.y, '{chat}', 500 + new.sort, false)
  on conflict (id) do nothing;
  -- an unowned plot follows its row; an owned one keeps the owner's name
  update locations l set district = new.district, x = new.x, y = new.y, sort = 500 + new.sort,
         name = case when l.biz_id is null then new.label else l.name end
   where l.id = new.id;
  return new;
end $$;
drop trigger if exists business_plots_loc on public.business_plots;
create trigger business_plots_loc after insert or update on public.business_plots
  for each row execute function public.bl_biz_plot_loc();
-- seeds that already exist before the trigger (re-run): make sure every plot has its place
insert into public.locations (id, name, district, scene, blurb, risk, night_risk_mult, cctv, keke_ok, congestion, remote_km, x, y, actions, sort, active)
select p.id, p.label, p.district, 'street', 'A business plot in ' || coalesce(nullif(p.area_label, ''), p.area) || '.', 0.2, 1.5, false, true, 1.0, 0, p.x, p.y, '{chat}', 500 + p.sort, false
  from public.business_plots p
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_biz_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_biz_on() returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = 'business.enabled'), true);
$$;

create or replace function public.bl_biz_hours(p_a timestamptz, p_b timestamptz) returns numeric
language sql immutable as $$
  select greatest(0, extract(epoch from (p_b - p_a)) / 3600.0)::numeric;
$$;

-- level multiplier / upgrade cost of a level ("2" is the first upgrade; level 1 is x1)
create or replace function public.bl_biz_mult(t public.business_types, p_lvl int) returns numeric
language sql immutable as $$
  select case when p_lvl <= 1 then 1 else coalesce((t.levels -> p_lvl::text ->> 'mult')::numeric, 1) end;
$$;
create or replace function public.bl_biz_lvcost(t public.business_types, p_lvl int) returns bigint
language sql immutable as $$
  select coalesce((t.levels -> p_lvl::text ->> 'cost')::bigint, 0);
$$;

-- an event setting: the type's own value, else the global key
create or replace function public.bl_biz_evn(t public.business_types, p_ev text, p_field text, p_key text, p_def numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((t.events -> p_ev ->> p_field)::numeric, bl_biz_num(p_key, p_def));
$$;

-- what the plot costs for this type
create or replace function public.bl_biz_price(t public.business_types, pl public.business_plots) returns bigint
language sql immutable as $$
  select round(t.price * coalesce(pl.price_mult, 1))::bigint;
$$;

-- buy price + every upgrade up to the level: what the business is "worth" for the Market
create or replace function public.bl_biz_value(b public.businesses) returns bigint
language sql stable set search_path = public as $$
  select coalesce((select round(t.price * coalesce(pl.price_mult, 1))::bigint
                          + coalesce((select sum(bl_biz_lvcost(t, g)) from generate_series(2, b.level) g), 0)::bigint
                     from business_types t, business_plots pl where t.id = b.type_id and pl.id = b.plot_id), 0);
$$;

create or replace function public.bl_biz_staff_name(p_biz bigint, p_i int) returns text
language sql immutable as $$
  select (array['Efosa','Osas','Ivie','Blessing','Eghosa','Nosa','Amen','Ehi','Uyi','Osaze','Idia','Ese','Itohan','Kelvin','Peace','Godwin'])[1 + ((p_biz * 7 + p_i * 5) % 16)::int];
$$;

-- how well stocked (0..1) at an instant; types without a restock cost never run out
create or replace function public.bl_biz_stock_f(b public.businesses, t public.business_types, p_at timestamptz) returns numeric
language plpgsql stable set search_path = public as $$
declare v_decay numeric := bl_biz_num('business.stock_decay_hours', 24); v_floor numeric := bl_biz_num('business.stock_floor_pct', 50) / 100.0; v_h numeric;
begin
  if t.restock_cost <= 0 or p_at <= b.stock_until then return 1; end if;
  v_h := bl_biz_hours(b.stock_until, p_at);
  if v_decay <= 0 or v_h >= v_decay then return v_floor; end if;
  return 1 - (1 - v_floor) * v_h / v_decay;
end $$;

-- gross income per hour at level / staff / skill, before stock and boost
create or replace function public.bl_biz_gross_hr(b public.businesses, t public.business_types) returns numeric
language sql stable set search_path = public as $$
  select b.base_income / 24.0 * bl_biz_mult(t, b.level) * (1 + b.staff * t.staff_income_pct / 100.0)
         * (1 + greatest(0, bl_skill_level(b.owner_id, 'business') - 1) * bl_biz_num('business.skill_pct_per_level', 1.5) / 100.0);
$$;

create or replace function public.bl_biz_cost_hr(b public.businesses, t public.business_types) returns numeric
language sql immutable as $$
  select (t.rent_day + t.power_day + b.staff * t.staff_wage) / 24.0;
$$;

-- integral of stock x boost over [p_from, p_to] (in factor-hours), only after setup is done
create or replace function public.bl_biz_factor(b public.businesses, t public.business_types, p_from timestamptz, p_to timestamptz) returns numeric
language plpgsql stable set search_path = public as $$
declare
  v_pts timestamptz[]; v_decay numeric := bl_biz_num('business.stock_decay_hours', 24); v_sum numeric := 0; i int; v_a timestamptz; v_b timestamptz;
  v_mid timestamptz; v_f numeric;
begin
  if p_to <= p_from then return 0; end if;
  v_pts := (select array_agg(x order by x) from (
              select p_from as x union all select p_to
              union all select b.ready_at where b.ready_at > p_from and b.ready_at < p_to
              union all select b.stock_until where b.stock_until > p_from and b.stock_until < p_to
              union all select b.stock_until + make_interval(secs => (v_decay * 3600)::double precision)
                         where b.stock_until + make_interval(secs => (v_decay * 3600)::double precision) > p_from
                           and b.stock_until + make_interval(secs => (v_decay * 3600)::double precision) < p_to
              union all select b.boost_until where b.boost_until is not null and b.boost_until > p_from and b.boost_until < p_to) q);
  for i in 1 .. cardinality(v_pts) - 1 loop
    v_a := v_pts[i]; v_b := v_pts[i + 1];
    continue when v_b <= v_a;
    v_mid := v_a + (v_b - v_a) / 2;
    continue when v_mid < b.ready_at;
    v_f := bl_biz_stock_f(b, t, v_mid) * (1 + case when b.boost_until is not null and v_mid < b.boost_until then t.boost_pct / 100.0 else 0 end);
    v_sum := v_sum + v_f * bl_biz_hours(v_a, v_b);
  end loop;
  return v_sum;
end $$;

create or replace function public.bl_biz_log(p_biz bigint, p_owner uuid, p_kind text, p_title text, p_amount bigint default 0, p_data jsonb default '{}'::jsonb) returns void
language sql set search_path = public as $$
  insert into business_log (business_id, owner_id, kind, title, amount, data, created_at) values (p_biz, p_owner, p_kind, p_title, coalesce(p_amount, 0), coalesce(p_data, '{}'::jsonb), bl_now());
$$;

-- keep the place in step with its business: name, type of interior, owner, level; hidden again when there is none
create or replace function public.bl_biz_loc_sync(p_plot text) returns void
language plpgsql security definer set search_path = public as $$
declare b businesses; t business_types; pl business_plots; v_owner text;
  v_looks text[] := array['Fresh signboard, doors open.', 'New paint and a proper counter.', 'Bright LED sign and a standby generator.',
                          'Air-conditioned, tiled and fully branded.', 'The best in the area. Customers dey queue.'];
begin
  select * into pl from business_plots where id = p_plot;
  if not found then return; end if;
  select * into b from businesses where plot_id = p_plot;
  if found then
    select * into t from business_types where id = b.type_id;
    select username into v_owner from profiles where id = b.owner_id;
    update locations set name = b.name, scene = t.scene, active = true, biz_id = b.id, biz_owner = v_owner, biz_level = b.level, biz_type = t.id,
           blurb = t.name || ' owned by @' || coalesce(v_owner, 'someone') || '. ' || v_looks[least(b.level, cardinality(v_looks))]
     where id = p_plot;
  else
    update locations set name = pl.label, scene = 'street', active = false, biz_id = null, biz_owner = null, biz_level = null, biz_type = null,
           blurb = 'A business plot in ' || coalesce(nullif(pl.area_label, ''), pl.area) || '.'
     where id = p_plot;
  end if;
end $$;

-- a business row that disappears any other way (an account deleted, a hand-made delete) hides its place again
create or replace function public.bl_biz_gone() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform bl_biz_loc_sync(old.plot_id);
  return old;
end $$;
drop trigger if exists businesses_gone on public.businesses;
create trigger businesses_gone after delete on public.businesses
  for each row execute function public.bl_biz_gone();

-- pay: bank first, then cash (like the Market and the car dealers)
create or replace function public.bl_biz_pay(p_me public.profiles, p_amount bigint, p_reason text, p_meta jsonb) returns void
language plpgsql set search_path = public as $$
declare v_bank bigint; v_cash bigint; v_now profiles;
begin
  if p_amount <= 0 then return; end if;
  select * into v_now from profiles where id = p_me.id;
  if v_now.cash + greatest(v_now.bank, 0) < p_amount then
    raise exception 'Not enough money. This costs % and you have % (bank % + cash %).', bl_naira(p_amount),
      bl_naira(v_now.cash + greatest(v_now.bank, 0)), bl_naira(greatest(v_now.bank, 0)), bl_naira(v_now.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_bank := least(greatest(v_now.bank, 0), p_amount);
  v_cash := p_amount - v_bank;
  if v_bank > 0 then perform bl_add_money(p_me.id, 'bank', -v_bank, p_reason, p_meta); end if;
  if v_cash > 0 then perform bl_add_money(p_me.id, 'cash', -v_cash, p_reason, p_meta); end if;
end $$;

-- the requirement: Business skill level and / or a certificate. null = fine, otherwise the reason
create or replace function public.bl_biz_gate(p_uid uuid, t public.business_types) returns text
language plpgsql stable set search_path = public as $$
declare v_lvl int; g jsonb;
begin
  if t.req_skill_level > 1 and bl_skill_on() then
    v_lvl := bl_skill_level(p_uid, 'business');
    if v_lvl < t.req_skill_level then
      return 'Needs Business skill level ' || t.req_skill_level || ' (you are level ' || v_lvl || '). Work shifts, hustles and classes to train it.';
    end if;
  end if;
  g := bl_cert_gate(p_uid, t.req_cert);
  if g is not null then return g->>'message'; end if;
  return null;
end $$;

-- "Takings ready" push: one a day at most, queued for later; every collect / purchase moves it, a collect cancels it
create or replace function public.bl_biz_push_plan(p_uid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_at timestamptz; v_first timestamptz; v_id bigint;
begin
  delete from push_outbox where user_id = p_uid and kind = 'business_ready' and status = 'pending';
  select min(last_collect_at) into v_first from businesses where owner_id = p_uid and not listed;
  if v_first is null then return; end if;
  v_at := greatest(now(), v_first + make_interval(secs => (bl_biz_num('business.push_hours', 36) * 3600)::double precision));
  v_id := bl_push_enqueue(p_uid, 'money', 'business_ready', 'Your takings dey ready 💰',
            'Your business don dey pile money. Come collect am before e full.', '/play?go=business', null, null, null,
            'business_ready:' || to_char(v_at at time zone 'Africa/Lagos', 'YYYY-MM-DD'));
  if v_id is not null then
    update push_outbox set send_after = v_at, created_at = v_at where id = v_id;
  end if;
exception when others then
  null;   -- a push problem never breaks a game action
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Settlement (lazy: runs on every read, collect and change)
-- ---------------------------------------------------------------------------------------------
-- Earns from settled_at up to now (or up to the cap), one business day at a time; each full 24 h rolls the events.
-- Returns the updated row. Takings never go below zero.
create or replace function public.bl_biz_settle(p_id bigint, p_notify boolean default true) returns public.businesses
language plpgsql security definer set search_path = public as $$
declare
  b businesses; t business_types; v_now timestamptz := bl_now(); v_end timestamptz; v_cur timestamptz; v_next timestamptz;
  v_step numeric; v_gross_hr numeric; v_cost_hr numeric; v_gain numeric; v_cost numeric; v_day numeric; v_pct numeric; v_cut numeric;
  v_amt numeric; v_title text; v_ins boolean; v_boost boolean; v_staffcut numeric; v_n int := 0;
begin
  select * into b from businesses where id = p_id for update;
  if not found then return null; end if;
  if b.listed then
    update businesses set settled_at = v_now, last_collect_at = v_now where id = b.id returning * into b;   -- frozen while on the Market
    return b;
  end if;
  select * into t from business_types where id = b.type_id;
  v_end := least(v_now, b.last_collect_at + make_interval(secs => (bl_biz_num('business.cap_hours', 48) * 3600)::double precision));
  v_cur := b.settled_at;
  if v_end <= v_cur then return b; end if;
  v_staffcut := least(50, b.staff * bl_biz_num('business.staff_event_cut_pct', 10));
  loop
    exit when v_cur >= v_end or v_n > 40;
    v_n := v_n + 1;
    v_step := least(24 - b.event_carry_h, bl_biz_hours(v_cur, v_end));
    exit when v_step <= 0.0000001 and b.event_carry_h < 24;
    v_next := v_cur + make_interval(secs => (v_step * 3600)::double precision);
    v_gross_hr := bl_biz_gross_hr(b, t);
    v_cost_hr := bl_biz_cost_hr(b, t);
    v_gain := v_gross_hr * bl_biz_factor(b, t, v_cur, v_next);
    v_cost := v_cost_hr * bl_biz_hours(greatest(v_cur, b.ready_at), v_next);
    b.takings := greatest(0, b.takings + v_gain - v_cost);
    b.event_carry_h := b.event_carry_h + v_step;
    if b.event_carry_h >= 24 - 0.000001 then
      b.event_carry_h := 0;
      if v_next > b.ready_at then
        v_day := v_gross_hr * 24;
        v_boost := b.boost_until is not null and b.boost_until > v_cur;
        v_ins := b.insured_until is not null and b.insured_until > v_cur;
        -- robbery
        v_pct := bl_biz_evn(t, 'robbery', 'chance_pct', 'business.robbery_pct', 6) * (1 - v_staffcut / 100.0) * case when v_boost then 0.5 else 1 end;
        if bl_crime_roll(v_pct) then
          v_amt := floor(b.takings * bl_biz_evn(t, 'robbery', 'loss_pct', 'business.robbery_loss_pct', 40) / 100.0);
          v_cut := case when v_ins then floor(v_amt * bl_biz_num('business.insurance_cover_pct', 80) / 100.0) else 0 end;
          v_amt := v_amt - v_cut;
          b.takings := greatest(0, b.takings - v_amt);
          v_title := 'Robbery at ' || b.name;
          perform bl_biz_log(b.id, b.owner_id, 'ev_robbery', v_title || case when v_cut > 0 then ' (insurance paid ' || bl_naira(v_cut) || ')' else '' end, -v_amt::bigint,
                             jsonb_build_object('event', 'robbery', 'covered', v_cut, 'at', v_next));
          if p_notify then
            perform bl_event(b.owner_id, 'business_robbery', 'Robbery at ' || b.name || '!',
              'Armed boys came and took ' || bl_naira(v_amt) || case when v_cut > 0 then '. Your insurance covered ' || bl_naira(v_cut) || '.' else '. No insurance, so na your loss.' end,
              jsonb_build_object('business', b.id, 'loss', v_amt, 'covered', v_cut));
          end if;
        end if;
        -- NEPA outage
        v_pct := bl_biz_evn(t, 'outage', 'chance_pct', 'business.outage_pct', 14);
        if bl_crime_roll(v_pct) then
          v_amt := floor(v_day * bl_biz_evn(t, 'outage', 'loss_pct', 'business.outage_loss_pct', 50) / 100.0);
          b.takings := greatest(0, b.takings - v_amt);
          perform bl_biz_log(b.id, b.owner_id, 'ev_outage', 'NEPA took light, diesel money burst', -v_amt::bigint, jsonb_build_object('event', 'outage', 'at', v_next));
          if p_notify then
            perform bl_event(b.owner_id, 'business_outage', 'NEPA outage at ' || b.name,
              'No light, plenty diesel. The day cost you ' || bl_naira(v_amt) || '.', jsonb_build_object('business', b.id, 'loss', v_amt));
          end if;
        end if;
        -- task force / council levy
        v_pct := bl_biz_evn(t, 'levy', 'chance_pct', 'business.levy_pct', 8) * (1 - v_staffcut / 100.0);
        if bl_crime_roll(v_pct) then
          v_amt := floor(v_day * bl_biz_evn(t, 'levy', 'loss_pct', 'business.levy_loss_pct', 35) / 100.0);
          b.takings := greatest(0, b.takings - v_amt);
          perform bl_biz_log(b.id, b.owner_id, 'ev_levy', 'Task force / council levy', -v_amt::bigint, jsonb_build_object('event', 'levy', 'at', v_next));
          if p_notify then
            perform bl_event(b.owner_id, 'business_levy', 'Council levy at ' || b.name,
              'Task force came with their receipt book: ' || bl_naira(v_amt) || ' gone.', jsonb_build_object('business', b.id, 'loss', v_amt));
          end if;
        end if;
        -- staff theft
        if b.staff > 0 then
          v_pct := bl_biz_evn(t, 'theft', 'chance_pct', 'business.theft_pct', 8) * case when v_boost then 0.5 else 1 end;
          if bl_crime_roll(v_pct) then
            v_amt := floor(v_day * bl_biz_evn(t, 'theft', 'loss_pct', 'business.theft_loss_pct', 20) / 100.0);
            b.takings := greatest(0, b.takings - v_amt);
            perform bl_biz_log(b.id, b.owner_id, 'ev_theft', 'One of your staff dey chop from the till', -v_amt::bigint, jsonb_build_object('event', 'theft', 'at', v_next));
            if p_notify then
              perform bl_event(b.owner_id, 'business_theft', 'Staff theft at ' || b.name,
                'Somebody for your staff don dey help themselves: ' || bl_naira(v_amt) || ' missing. Work a shift yourself sometimes.',
                jsonb_build_object('business', b.id, 'loss', v_amt));
            end if;
          end if;
        end if;
        -- great day
        v_pct := bl_biz_evn(t, 'goodday', 'chance_pct', 'business.goodday_pct', 10);
        if bl_crime_roll(v_pct) then
          v_amt := floor(v_day * bl_biz_evn(t, 'goodday', 'bonus_pct', 'business.goodday_bonus_pct', 60) / 100.0);
          b.takings := b.takings + v_amt;
          perform bl_biz_log(b.id, b.owner_id, 'ev_goodday', 'Great day: customers no gree finish', v_amt::bigint, jsonb_build_object('event', 'goodday', 'at', v_next));
          if p_notify then
            perform bl_event(b.owner_id, 'business_goodday', 'Great day at ' || b.name || '!',
              'Customers no gree finish today: ' || bl_naira(v_amt) || ' extra in the till.', jsonb_build_object('business', b.id, 'bonus', v_amt));
          end if;
        end if;
      end if;
    end if;
    v_cur := v_next;
  end loop;
  update businesses set takings = b.takings, event_carry_h = b.event_carry_h, settled_at = v_end where id = b.id returning * into b;
  return b;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Cards (JSON for the app)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_biz_card(b public.businesses, p_log boolean default true) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  t business_types; pl business_plots; v_now timestamptz := bl_now(); v_gross numeric; v_cost numeric; v_stock numeric; v_boost boolean;
  v_used int; v_next jsonb; v_cap timestamptz; v_staff jsonb := '[]'::jsonb; i int; v_ins boolean; v_lvlmult numeric;
begin
  select * into t from business_types where id = b.type_id;
  select * into pl from business_plots where id = b.plot_id;
  v_stock := bl_biz_stock_f(b, t, v_now);
  v_boost := b.boost_until is not null and b.boost_until > v_now;
  v_ins := b.insured_until is not null and b.insured_until > v_now;
  v_gross := bl_biz_gross_hr(b, t) * 24 * v_stock * (1 + case when v_boost then t.boost_pct / 100.0 else 0 end);
  v_cost := bl_biz_cost_hr(b, t) * 24;
  v_cap := b.last_collect_at + make_interval(secs => (bl_biz_num('business.cap_hours', 48) * 3600)::double precision);
  v_lvlmult := bl_biz_mult(t, b.level);
  select count(*) into v_used from business_log where owner_id = b.owner_id and kind = 'shift'
     and created_at >= date_trunc('day', v_now at time zone 'Africa/Lagos') at time zone 'Africa/Lagos';
  if b.level < t.max_level then
    v_next := jsonb_build_object('level', b.level + 1, 'cost', bl_biz_lvcost(t, b.level + 1), 'mult', bl_biz_mult(t, b.level + 1));
  end if;
  for i in 1 .. b.staff loop
    v_staff := v_staff || jsonb_build_array(jsonb_build_object('name', bl_biz_staff_name(b.id, i), 'wage', t.staff_wage));
  end loop;
  return jsonb_build_object(
    'id', b.id, 'name', b.name, 'type', t.id, 'type_name', t.name, 'icon', t.icon, 'scene', t.scene,
    'plot', pl.id, 'plot_label', pl.label, 'area', pl.area, 'area_label', coalesce(nullif(pl.area_label, ''), pl.area),
    'location', b.plot_id, 'level', b.level, 'max_level', t.max_level, 'next', v_next,
    'takings', floor(b.takings)::bigint, 'cap_at', v_cap, 'full', v_now >= v_cap,
    'ready_at', b.ready_at, 'setting_up', b.ready_at > v_now,
    'gross_day', round(v_gross)::bigint, 'cost_day', round(v_cost)::bigint, 'net_day', round(v_gross - v_cost)::bigint,
    'base_day', b.base_income, 'level_mult', v_lvlmult,
    'needs_stock', t.restock_cost > 0, 'stock_pct', round(v_stock * 100), 'stock_until', b.stock_until,
    'restock_cost', round(t.restock_cost * v_lvlmult)::bigint, 'restock_hours', bl_biz_num('business.stock_hours', 48),
    'staff', b.staff) || jsonb_build_object('staff_slots', t.staff_slots, 'staff_wage', t.staff_wage, 'staff_income_pct', t.staff_income_pct, 'staff_list', v_staff,
    'hire_fee', round(t.staff_wage * bl_biz_num('business.hire_fee_days', 2))::bigint,
    'boost', v_boost, 'boost_until', b.boost_until, 'boost_pct', t.boost_pct,
    'insured', v_ins, 'insured_until', b.insured_until,
    'insure_cost', round(t.price * bl_biz_num('business.insurance_cost_pct', 3) / 100.0)::bigint,
    'insure_days', bl_biz_num('business.insurance_days', 7),
    'shifts_used', v_used, 'shifts_cap', bl_biz_num('business.shift_daily_cap', 6)::int,
    'invested', b.invested, 'value', bl_biz_value(b),
    'sell_back', floor(b.invested * bl_biz_num('business.sell_back_pct', 60) / 100.0)::bigint,
    'listed', b.listed, 'lifetime_income', b.lifetime_income, 'lifetime_visit', b.lifetime_visit, 'bought_at', b.bought_at,
    'log', case when p_log then coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'title', x.title, 'amount', x.amount, 'at', x.created_at) order by x.id desc)
                                            from (select * from business_log where business_id = b.id order by id desc limit 30) x), '[]'::jsonb) end);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_biz_guard(p_me public.profiles, p_write boolean default true) returns void
language plpgsql set search_path = public as $$
begin
  if p_write and not bl_biz_on() then
    raise exception 'Business ownership is closed for now. Check back later.' using errcode = 'P0001', hint = 'business_closed';
  end if;
  if p_me.jailed_until is not null and p_me.jailed_until > bl_now() then
    raise exception 'You dey police cell. Your business can wait until you are out.' using errcode = 'P0001', hint = 'jailed';
  end if;
end $$;

-- lock + load one of my businesses, settled
create or replace function public.bl_biz_mine(p_uid uuid, p_id bigint, p_allow_listed boolean default false) returns public.businesses
language plpgsql security definer set search_path = public as $$
declare b businesses;
begin
  select * into b from businesses where id = p_id and owner_id = p_uid for update;
  if not found then
    raise exception 'That business no dey your name.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  if b.listed and not p_allow_listed then
    raise exception 'That business dey for the Market. Take it down first.' using errcode = 'P0001', hint = 'listed';
  end if;
  return bl_biz_settle(b.id);
end $$;

create or replace function public.business_mine() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); r record; v_cards jsonb := '[]'::jsonb; b businesses;
begin
  for r in select id from businesses where owner_id = v_uid order by id loop
    b := bl_biz_settle(r.id);
    v_cards := v_cards || jsonb_build_array(bl_biz_card(b, true));
  end loop;
  return jsonb_build_object(
    'enabled', bl_biz_on(), 'businesses', v_cards, 'max_owned', bl_biz_num('business.max_owned', 3)::int,
    'cap_hours', bl_biz_num('business.cap_hours', 48), 'skill_level', bl_skill_level(v_uid, 'business'),
    'visit_cut_pct', bl_biz_num('business.visit_cut_pct', 30), 'sell_back_pct', bl_biz_num('business.sell_back_pct', 60),
    'shift_seconds', bl_biz_num('business.shift_seconds', 60), 'shift_energy', bl_biz_num('business.shift_energy', 12),
    'insurance_cover_pct', bl_biz_num('business.insurance_cover_pct', 80));
end $$;

-- the buy list: types with requirements, and the free / taken plots of each area
create or replace function public.business_catalog() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_rows jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'name', t.name, 'icon', t.icon, 'blurb', t.blurb, 'scene', t.scene, 'price', t.price, 'setup_minutes', t.setup_minutes,
      'income_min', t.income_min, 'income_max', t.income_max, 'rent_day', t.rent_day, 'power_day', t.power_day,
      'staff_slots', t.staff_slots, 'staff_wage', t.staff_wage, 'staff_income_pct', t.staff_income_pct, 'max_level', t.max_level,
      'needs_stock', t.restock_cost > 0, 'restock_cost', t.restock_cost, 'req_skill_level', t.req_skill_level,
      'req_cert', t.req_cert, 'req_cert_text', case when t.req_cert is null then null else bl_cert_need_text(t.req_cert) end,
      'gate', bl_biz_gate(v_uid, t), 'met', bl_biz_gate(v_uid, t) is null,
      'slots', coalesce((select jsonb_agg(jsonb_build_object('plot', p.id, 'label', p.label, 'area', p.area, 'area_label', coalesce(nullif(p.area_label, ''), p.area),
                          'price', bl_biz_price(t, p), 'taken', b.id is not null, 'taken_by', (select username from profiles where id = b.owner_id),
                          'taken_name', b.name) order by p.sort, p.id)
                           from business_plots p left join businesses b on b.plot_id = p.id
                          where p.active and p.area = any (t.areas) and (cardinality(p.type_ids) = 0 or t.id = any (p.type_ids))), '[]'::jsonb))
      order by t.sort, t.id), '[]'::jsonb)
    into v_rows from business_types t where t.active;
  return jsonb_build_object('enabled', bl_biz_on(), 'types', v_rows, 'owned', (select count(*) from businesses where owner_id = v_uid),
                            'max_owned', bl_biz_num('business.max_owned', 3)::int, 'skill_level', bl_skill_level(v_uid, 'business'));
end $$;

-- a place's business (the place card): null when the place is not a business
create or replace function public.business_at(p_location text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); b businesses; t business_types; v_owner text; v_cut numeric := bl_biz_num('business.visit_cut_pct', 30);
begin
  select * into b from businesses where plot_id = p_location;
  if not found then return null; end if;
  select * into t from business_types where id = b.type_id;
  select username into v_owner from profiles where id = b.owner_id;
  return jsonb_build_object('id', b.id, 'name', b.name, 'type', t.id, 'type_name', t.name, 'icon', t.icon, 'level', b.level, 'max_level', t.max_level,
    'owner', v_owner, 'mine', b.owner_id = v_uid, 'setting_up', b.ready_at > bl_now(), 'ready_at', b.ready_at, 'listed', b.listed,
    'staff', b.staff, 'cut_pct', v_cut,
    'takings', case when b.owner_id = v_uid then floor((bl_biz_settle(b.id)).takings)::bigint end,
    'boost', b.owner_id = v_uid and b.boost_until is not null and b.boost_until > bl_now());
end $$;

create or replace function public.business_buy(p_type text, p_plot text, p_name text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; t business_types; pl business_plots; v_name text; v_price bigint; v_now timestamptz := bl_now();
  v_inc bigint; b businesses; v_gate text; v_masked text; v_owned int;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_biz_guard(v_me);
  select * into t from business_types where id = p_type and active;
  if not found then
    raise exception 'That kind of business no dey.' using errcode = 'P0001', hint = 'bad_type';
  end if;
  select * into pl from business_plots where id = p_plot and active for update;
  if not found then
    raise exception 'That plot no dey.' using errcode = 'P0001', hint = 'bad_plot';
  end if;
  if exists (select 1 from businesses where plot_id = pl.id) then
    raise exception 'Somebody don buy that plot. Pick another one.' using errcode = 'P0001', hint = 'plot_taken';
  end if;
  if not (pl.area = any (t.areas)) or (cardinality(pl.type_ids) > 0 and not (t.id = any (pl.type_ids))) then
    raise exception 'You no fit build a % for %.', lower(t.name), coalesce(nullif(pl.area_label, ''), pl.area) using errcode = 'P0001', hint = 'wrong_area';
  end if;
  select count(*) into v_owned from businesses where owner_id = v_uid;
  if v_owned >= bl_biz_num('business.max_owned', 3) then
    raise exception 'You already own % businesses. That is the limit.', bl_biz_num('business.max_owned', 3)::int using errcode = 'P0001', hint = 'max_owned';
  end if;
  v_gate := bl_biz_gate(v_uid, t);
  if v_gate is not null then
    raise exception '%', v_gate using errcode = 'P0001', hint = 'requirement';
  end if;
  v_name := left(bl_chat_clean(coalesce(p_name, '')), 28);
  if v_name = '' then v_name := t.name; end if;
  if char_length(v_name) < 3 then
    raise exception 'Give your business a name of at least 3 letters.' using errcode = 'P0001', hint = 'bad_name';
  end if;
  v_masked := bl_chat_mask(v_name);
  if v_masked <> v_name then
    raise exception 'Choose a cleaner name for your business.' using errcode = 'P0001', hint = 'bad_name';
  end if;
  v_price := bl_biz_price(t, pl);
  perform bl_biz_pay(v_me, v_price, 'business_buy', jsonb_build_object('label', 'Business: bought ' || v_name, 'type', t.id, 'plot', pl.id));
  v_inc := t.income_min + floor(bl_rand() * (t.income_max - t.income_min + 1))::bigint;
  begin
    insert into businesses (owner_id, plot_id, type_id, name, base_income, invested, bought_at, ready_at, settled_at, last_collect_at, stock_until, source)
    values (v_uid, pl.id, t.id, v_name, v_inc, v_price, v_now, v_now + make_interval(mins => t.setup_minutes), v_now + make_interval(mins => t.setup_minutes),
            v_now + make_interval(mins => t.setup_minutes), v_now + make_interval(mins => t.setup_minutes) + make_interval(secs => (bl_biz_num('business.stock_hours', 48) * 3600)::double precision), 'buy')
    returning * into b;
  exception when unique_violation then
    raise exception 'Somebody don buy that plot. Pick another one.' using errcode = 'P0001', hint = 'plot_taken';
  end;
  perform bl_biz_loc_sync(pl.id);
  perform bl_biz_log(b.id, v_uid, 'buy', 'Bought ' || v_name || ' for ' || bl_naira(v_price), -v_price, jsonb_build_object('plot', pl.id));
  perform bl_biz_push_plan(v_uid);
  return jsonb_build_object('message', v_name || ' is yours! ' || case when t.setup_minutes > 0 then 'The builders need ' || t.setup_minutes || ' minutes, then the money starts.' else 'Doors open.' end,
                            'business', bl_biz_card(b, true), 'location', pl.id);
end $$;

create or replace function public.business_collect(p_id bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; b businesses; r record; v_amt bigint; v_total bigint := 0; v_n int := 0; v_now timestamptz := bl_now();
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_biz_guard(v_me, false);
  for r in select id from businesses where owner_id = v_uid and (p_id is null or id = p_id) and not listed order by id loop
    b := bl_biz_settle(r.id);
    v_amt := floor(b.takings)::bigint;
    if v_amt > 0 then
      perform bl_add_money(v_uid, 'bank', v_amt, 'business_income', jsonb_build_object('label', 'Takings: ' || b.name, 'business', b.id));
      v_total := v_total + v_amt; v_n := v_n + 1;
    end if;
    update businesses set takings = 0, last_collect_at = v_now, settled_at = v_now, lifetime_income = lifetime_income + v_amt where id = b.id returning * into b;
    if v_amt > 0 then perform bl_biz_log(b.id, v_uid, 'collect', 'Collected ' || bl_naira(v_amt), v_amt, '{}'::jsonb); end if;
  end loop;
  if not found and p_id is not null then
    raise exception 'That business no dey your name.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  if v_total <= 0 then
    raise exception 'Nothing to collect yet. Let the business work a bit more.' using errcode = 'P0001', hint = 'nothing';
  end if;
  perform bl_biz_push_plan(v_uid);
  return jsonb_build_object('message', 'You collected ' || bl_naira(v_total) || ' into your bank.', 'amount', v_total, 'count', v_n);
end $$;

create or replace function public.business_restock(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; b businesses; t business_types; v_cost bigint; v_now timestamptz := bl_now(); v_until timestamptz; v_max timestamptz;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_biz_guard(v_me);
  b := bl_biz_mine(v_uid, p_id);
  select * into t from business_types where id = b.type_id;
  if t.restock_cost <= 0 then
    raise exception '% needs no stock. Nothing to buy.', b.name using errcode = 'P0001', hint = 'no_stock_needed';
  end if;
  v_max := v_now + make_interval(secs => (bl_biz_num('business.stock_max_hours', 168) * 3600)::double precision);
  if b.stock_until >= v_max - interval '1 minute' then
    raise exception 'Your shelves are full already.' using errcode = 'P0001', hint = 'stock_full';
  end if;
  v_cost := round(t.restock_cost * bl_biz_mult(t, b.level))::bigint;
  perform bl_biz_pay(v_me, v_cost, 'business_stock', jsonb_build_object('label', 'Business: restock ' || b.name, 'business', b.id));
  v_until := least(v_max, greatest(b.stock_until, v_now) + make_interval(secs => (bl_biz_num('business.stock_hours', 48) * 3600)::double precision));
  update businesses set stock_until = v_until where id = b.id returning * into b;
  perform bl_biz_log(b.id, v_uid, 'restock', 'Restocked for ' || bl_naira(v_cost), -v_cost, '{}'::jsonb);
  return jsonb_build_object('message', 'Shelves full again. Income stays at 100%.', 'business', bl_biz_card(b, true), 'cost', v_cost);
end $$;

create or replace function public.business_upgrade(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; b businesses; t business_types; v_cost bigint;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_biz_guard(v_me);
  b := bl_biz_mine(v_uid, p_id);
  select * into t from business_types where id = b.type_id;
  if b.level >= t.max_level then
    raise exception '% is already at the top level.', b.name using errcode = 'P0001', hint = 'max_level';
  end if;
  v_cost := bl_biz_lvcost(t, b.level + 1);
  if v_cost <= 0 then
    raise exception 'That upgrade is not available yet.' using errcode = 'P0001', hint = 'no_upgrade';
  end if;
  perform bl_biz_pay(v_me, v_cost, 'business_upgrade', jsonb_build_object('label', 'Business: upgrade ' || b.name || ' to level ' || (b.level + 1), 'business', b.id));
  update businesses set level = level + 1, invested = invested + v_cost where id = b.id returning * into b;
  perform bl_biz_loc_sync(b.plot_id);
  perform bl_biz_log(b.id, v_uid, 'upgrade', 'Upgraded to level ' || b.level, -v_cost, jsonb_build_object('level', b.level));
  return jsonb_build_object('message', b.name || ' is now level ' || b.level || '. Income x' || bl_biz_mult(t, b.level) || '.', 'business', bl_biz_card(b, true), 'cost', v_cost);
end $$;

create or replace function public.business_hire(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; b businesses; t business_types; v_fee bigint;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_biz_guard(v_me);
  b := bl_biz_mine(v_uid, p_id);
  select * into t from business_types where id = b.type_id;
  if b.staff >= t.staff_slots then
    raise exception 'No more room for staff here (% slot%).', t.staff_slots, case when t.staff_slots = 1 then '' else 's' end using errcode = 'P0001', hint = 'staff_full';
  end if;
  v_fee := round(t.staff_wage * bl_biz_num('business.hire_fee_days', 2))::bigint;
  perform bl_biz_pay(v_me, v_fee, 'business_hire', jsonb_build_object('label', 'Business: hired staff at ' || b.name, 'business', b.id));
  update businesses set staff = staff + 1 where id = b.id returning * into b;
  perform bl_biz_log(b.id, v_uid, 'hire', 'Hired ' || bl_biz_staff_name(b.id, b.staff) || ' (' || bl_naira(t.staff_wage) || ' a day)', -v_fee, jsonb_build_object('staff', b.staff));
  return jsonb_build_object('message', bl_biz_staff_name(b.id, b.staff) || ' don join your team. ' || bl_naira(t.staff_wage) || ' a day.', 'business', bl_biz_card(b, true));
end $$;

create or replace function public.business_fire(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; b businesses; v_name text;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_biz_guard(v_me, false);
  b := bl_biz_mine(v_uid, p_id);
  if b.staff <= 0 then
    raise exception 'You have no staff to let go.' using errcode = 'P0001', hint = 'no_staff';
  end if;
  v_name := bl_biz_staff_name(b.id, b.staff);
  update businesses set staff = staff - 1 where id = b.id returning * into b;
  perform bl_biz_log(b.id, v_uid, 'fire', 'Let ' || v_name || ' go', 0, jsonb_build_object('staff', b.staff));
  return jsonb_build_object('message', v_name || ' don go. No more wage for that one.', 'business', bl_biz_card(b, true));
end $$;

create or replace function public.business_insure(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; b businesses; t business_types; v_cost bigint; v_now timestamptz := bl_now();
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_biz_guard(v_me);
  b := bl_biz_mine(v_uid, p_id);
  select * into t from business_types where id = b.type_id;
  v_cost := round(t.price * bl_biz_num('business.insurance_cost_pct', 3) / 100.0)::bigint;
  perform bl_biz_pay(v_me, v_cost, 'business_insure', jsonb_build_object('label', 'Business: insurance for ' || b.name, 'business', b.id));
  update businesses set insured_until = greatest(coalesce(insured_until, v_now), v_now) + make_interval(days => bl_biz_num('business.insurance_days', 7)::int)
   where id = b.id returning * into b;
  perform bl_biz_log(b.id, v_uid, 'insure', 'Insured until ' || to_char(b.insured_until at time zone 'Africa/Lagos', 'DD Mon'), -v_cost, '{}'::jsonb);
  return jsonb_build_object('message', 'Insured. A robbery will cost you only ' || (100 - bl_biz_num('business.insurance_cover_pct', 80))::int || '% of the loss.', 'business', bl_biz_card(b, true));
end $$;

-- the owner works a shift at their own business: boost + Business XP
create or replace function public.business_work(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; b businesses; t business_types; v_now timestamptz := bl_now(); v_used int; v_en numeric; v_until timestamptz;
  v_skill jsonb;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_biz_guard(v_me);
  perform bl_assert_free(v_me);
  b := bl_biz_mine(v_uid, p_id);
  select * into t from business_types where id = b.type_id;
  if v_me.location_id is distinct from b.plot_id or v_me.travel_to is not null then
    raise exception 'Go to % first. A shift must be worked at the business.', b.name using errcode = 'P0001', hint = 'not_here';
  end if;
  if b.ready_at > v_now then
    raise exception 'The builders are still working here. Come back when e don ready.' using errcode = 'P0001', hint = 'setting_up';
  end if;
  select count(*) into v_used from business_log where owner_id = v_uid and kind = 'shift'
     and created_at >= date_trunc('day', v_now at time zone 'Africa/Lagos') at time zone 'Africa/Lagos';
  if v_used >= bl_biz_num('business.shift_daily_cap', 6) then
    raise exception 'You don work % shifts today. Rest, your staff go cover.', v_used using errcode = 'P0001', hint = 'shift_cap';
  end if;
  v_en := bl_biz_num('business.shift_energy', 12);
  if v_me.energy < greatest(v_en, 1) or v_me.hunger < 10 then
    raise exception 'You too tire or hungry for a shift. Eat or rest first.' using errcode = 'P0001', hint = 'too_tired';
  end if;
  perform bl_adjust_needs(v_uid, jsonb_build_object('energy', -v_en, 'hunger', -6, 'stress', 4));
  update businesses set boost_until = v_now + make_interval(secs => (bl_biz_num('business.shift_boost_hours', 8) * 3600)::double precision)
   where id = b.id returning * into b;
  v_until := bl_set_busy_seconds(v_uid, bl_biz_num('business.shift_seconds', 60), 'Working at ' || b.name);
  v_skill := bl_skill_award(v_uid, 'activity', 'business_shift');
  perform bl_biz_log(b.id, v_uid, 'shift', 'Worked a shift: +' || t.boost_pct::int || '% for ' || bl_biz_num('business.shift_boost_hours', 8)::int || ' h', 0, '{}'::jsonb);
  return jsonb_build_object('message', 'You worked a shift at ' || b.name || '. Customers dey happy: +' || t.boost_pct::int || '% income for ' || bl_biz_num('business.shift_boost_hours', 8)::int || ' hours.',
                            'busy_until', v_until, 'skill', v_skill, 'business', bl_biz_card(b, true));
end $$;

-- sell to the system at business.sell_back_pct of what was invested; uncollected takings are paid out first
create or replace function public.business_sell(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; b businesses; v_amt bigint; v_take bigint; v_plot text;
begin
  perform 1 from profiles where id = v_uid for update;
  v_me := bl_me();
  perform bl_biz_guard(v_me, false);
  b := bl_biz_mine(v_uid, p_id);
  v_take := floor(b.takings)::bigint;
  if v_take > 0 then
    perform bl_add_money(v_uid, 'bank', v_take, 'business_income', jsonb_build_object('label', 'Takings: ' || b.name, 'business', b.id));
  end if;
  v_amt := floor(b.invested * bl_biz_num('business.sell_back_pct', 60) / 100.0)::bigint;
  if v_amt > 0 then
    perform bl_add_money(v_uid, 'bank', v_amt, 'business_sell', jsonb_build_object('label', 'Business: sold ' || b.name, 'business', b.id));
  end if;
  v_plot := b.plot_id;
  delete from businesses where id = b.id;
  perform bl_biz_loc_sync(v_plot);
  perform bl_biz_push_plan(v_uid);
  return jsonb_build_object('message', b.name || ' sold. ' || bl_naira(v_amt) || ' in your bank' || case when v_take > 0 then ' (plus ' || bl_naira(v_take) || ' takings).' else '.' end,
                            'amount', v_amt, 'takings', v_take);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Visitors pay the owner a cut; the shop list at a business
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_biz_visit_cut(p_visitor uuid, p_loc text, p_amount bigint, p_what text) returns bigint
language plpgsql security definer set search_path = public as $$
declare b businesses; v_cut bigint; v_who text; v_ok boolean;
begin
  if p_amount is null or p_amount <= 0 or p_loc is null or not bl_biz_on() then return 0; end if;
  select * into b from businesses where plot_id = p_loc;
  if not found or b.owner_id = p_visitor or b.listed then return 0; end if;
  v_cut := floor(p_amount * bl_biz_num('business.visit_cut_pct', 30) / 100.0)::bigint;
  if v_cut <= 0 then return 0; end if;
  select username into v_who from profiles where id = p_visitor;
  -- never wait on the owner's row (two players buying at each other's business must not deadlock):
  -- if it is busy the cut waits in the takings and is paid with the next collect
  begin
    perform 1 from profiles where id = b.owner_id for update nowait;
    v_ok := true;
  exception when lock_not_available then
    v_ok := false;
  end;
  if v_ok then
    perform bl_add_money(b.owner_id, 'bank', v_cut, 'business_income',
      jsonb_build_object('label', 'Customer at ' || b.name || ': @' || coalesce(v_who, 'player') || ' · ' || coalesce(p_what, 'purchase'), 'business', b.id, 'visitor', p_visitor, 'customer', true));
    update businesses set lifetime_visit = lifetime_visit + v_cut where id = b.id;
  else
    update businesses set takings = takings + v_cut, lifetime_visit = lifetime_visit + v_cut where id = b.id;
  end if;
  return v_cut;
end $$;

-- an item is on the shelf of an owned business when a plain place of the same type sells it
create or replace function public.bl_biz_sells(p_loc text, p_item text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from locations l where l.id = p_loc and l.biz_id is not null)
     and exists (select 1 from locations l, items i, locations s
                  where l.id = p_loc and i.id = p_item and s.id = any (i.sold_at) and s.scene = l.scene and s.biz_id is null and s.id not like 'biz\_%');
$$;

-- ---------------------------------------------------------------------------------------------
-- 9. Market: kind 'business'
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_biz_market_take(p_uid uuid, p_ref text, p_qty int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b businesses; t business_types; v_take bigint;
begin
  if p_ref is null or p_ref !~ '^[0-9]+$' then
    raise exception 'That business no dey.' using errcode = 'P0001', hint = 'not_owned';
  end if;
  if coalesce(p_qty, 1) <> 1 then
    raise exception 'A business is sold one at a time.' using errcode = 'P0001', hint = 'bad_amount';
  end if;
  select * into b from businesses where id = p_ref::bigint and owner_id = p_uid for update;
  if not found then
    raise exception 'That business no dey your name.' using errcode = 'P0001', hint = 'not_owned';
  end if;
  if b.listed then
    raise exception 'That business is already on the market.' using errcode = 'P0001', hint = 'listed';
  end if;
  b := bl_biz_settle(b.id);
  select * into t from business_types where id = b.type_id;
  v_take := floor(b.takings)::bigint;
  if v_take > 0 then
    perform bl_add_money(p_uid, 'bank', v_take, 'business_income', jsonb_build_object('label', 'Takings: ' || b.name, 'business', b.id));
  end if;
  update businesses set listed = true, takings = 0, last_collect_at = bl_now(), settled_at = bl_now(), lifetime_income = lifetime_income + v_take where id = b.id;
  perform bl_biz_log(b.id, p_uid, 'listed', 'Put on the Market', 0, '{}'::jsonb);
  return jsonb_build_object('title', b.name || ' (level ' || b.level || ')', 'icon', t.icon, 'value', bl_biz_value(b),
                            'detail', jsonb_build_object('business', b.id, 'type', t.id, 'type_name', t.name, 'level', b.level, 'plot', b.plot_id,
                                       'area', (select coalesce(nullif(area_label, ''), area) from business_plots where id = b.plot_id), 'cost', b.invested),
                            'qty', 1);
end $$;

-- the buyer (strict) or the seller getting it back (not strict)
create or replace function public.bl_biz_market_give(p_uid uuid, p_ref text, p_detail jsonb, p_cost bigint, p_strict boolean) returns void
language plpgsql security definer set search_path = public as $$
declare b businesses; t business_types; v_now timestamptz := bl_now(); v_gate text; v_old uuid; v_username text;
begin
  select * into b from businesses where id = (p_ref)::bigint for update;
  if not found then return; end if;
  select * into t from business_types where id = b.type_id;
  v_old := b.owner_id;
  if p_strict then
    if (select count(*) from businesses where owner_id = p_uid) >= bl_biz_num('business.max_owned', 3) then
      raise exception 'You already own % businesses. That is the limit.', bl_biz_num('business.max_owned', 3)::int using errcode = 'P0001', hint = 'max_owned';
    end if;
    v_gate := bl_biz_gate(p_uid, t);
    if v_gate is not null then
      raise exception '%', v_gate using errcode = 'P0001', hint = 'requirement';
    end if;
  end if;
  update businesses set owner_id = p_uid, listed = false, takings = 0, settled_at = v_now, last_collect_at = v_now, event_carry_h = 0,
         boost_until = null, insured_until = case when p_uid = v_old then insured_until else null end,
         invested = case when p_strict and p_uid <> v_old then greatest(0, coalesce(p_cost, 0)) else invested end,
         source = case when p_uid = v_old then source else 'market' end
   where id = b.id;
  if p_uid <> v_old then
    update business_log set owner_id = p_uid where business_id = b.id;
  end if;
  select username into v_username from profiles where id = p_uid;
  perform bl_biz_loc_sync(b.plot_id);
  perform bl_biz_log(b.id, p_uid, case when p_uid = v_old then 'unlisted' else 'market_buy' end,
                     case when p_uid = v_old then 'Back with you from the Market' else 'Bought on the Market by @' || coalesce(v_username, 'player') end, 0, '{}'::jsonb);
  perform bl_biz_push_plan(p_uid);
  if p_uid <> v_old then perform bl_biz_push_plan(v_old); end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. Admin
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_business_overview(p_limit int default 200) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_lim int := least(greatest(coalesce(p_limit, 200), 1), 500);
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'stats', jsonb_build_object('owned', (select count(*) from businesses), 'plots', (select count(*) from business_plots where active),
                                'free', (select count(*) from business_plots p where p.active and not exists (select 1 from businesses b where b.plot_id = p.id)),
                                'listed', (select count(*) from businesses where listed),
                                'income_7d', (select coalesce(sum(delta), 0) from ledger where reason = 'business_income' and delta > 0 and created_at > bl_now() - interval '7 days')),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'type', t.name, 'icon', t.icon, 'level', b.level, 'owner', p.username, 'owner_id', b.owner_id,
                          'plot', pl.label, 'takings', floor(b.takings)::bigint, 'staff', b.staff, 'listed', b.listed, 'source', b.source, 'bought_at', b.bought_at,
                          'lifetime_income', b.lifetime_income, 'lifetime_visit', b.lifetime_visit) order by b.id desc)
                        from (select * from businesses order by id desc limit v_lim) b
                        join business_types t on t.id = b.type_id join business_plots pl on pl.id = b.plot_id join profiles p on p.id = b.owner_id), '[]'::jsonb));
end $$;

create or replace function public.admin_business_get(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'businesses', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'type', t.name, 'icon', t.icon, 'level', b.level, 'plot', pl.label, 'takings', floor(b.takings)::bigint,
                          'staff', b.staff, 'listed', b.listed, 'source', b.source, 'invested', b.invested, 'lifetime_income', b.lifetime_income) order by b.id)
                        from businesses b join business_types t on t.id = b.type_id join business_plots pl on pl.id = b.plot_id where b.owner_id = p_user), '[]'::jsonb),
    'types', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'areas', areas) order by sort, id) from business_types where active), '[]'::jsonb),
    'plots', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'label', p.label, 'area', p.area) order by p.sort, p.id)
                         from business_plots p where p.active and not exists (select 1 from businesses b where b.plot_id = p.id)), '[]'::jsonb));
end $$;

create or replace function public.admin_business_grant(p_user uuid, p_type text, p_plot text, p_name text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); t business_types; pl business_plots; b businesses; v_now timestamptz := bl_now(); v_name text; v_inc bigint; v_who text;
begin
  select username into v_who from profiles where id = p_user for update;
  if not found then
    raise exception 'No such player.' using errcode = 'P0001', hint = 'no_player';
  end if;
  select * into t from business_types where id = p_type;
  if not found then
    raise exception 'No such business type.' using errcode = 'P0001', hint = 'bad_type';
  end if;
  select * into pl from business_plots where id = p_plot for update;
  if not found then
    raise exception 'No such plot.' using errcode = 'P0001', hint = 'bad_plot';
  end if;
  if exists (select 1 from businesses where plot_id = pl.id) then
    raise exception 'That plot is already taken.' using errcode = 'P0001', hint = 'plot_taken';
  end if;
  v_name := left(bl_chat_clean(coalesce(p_name, '')), 28);
  if char_length(v_name) < 3 then v_name := t.name; end if;
  v_inc := t.income_min + floor(bl_rand() * (t.income_max - t.income_min + 1))::bigint;
  insert into businesses (owner_id, plot_id, type_id, name, base_income, invested, bought_at, ready_at, settled_at, last_collect_at, stock_until, source)
  values (p_user, pl.id, t.id, v_name, v_inc, 0, v_now, v_now, v_now, v_now, v_now + make_interval(secs => (bl_biz_num('business.stock_hours', 48) * 3600)::double precision), 'admin')
  returning * into b;
  perform bl_biz_loc_sync(pl.id);
  perform bl_biz_log(b.id, p_user, 'grant', 'Given by Benin Life', 0, jsonb_build_object('admin', v_admin));
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'business_grant', p_user, jsonb_build_object('business', b.id, 'type', t.id, 'plot', pl.id, 'name', v_name));
  perform bl_event(p_user, 'business_granted', v_name || ' is yours', 'Benin Life gave you a ' || lower(t.name) || ' at ' || pl.label || '. Open the Business app.', jsonb_build_object('business', b.id));
  perform bl_biz_push_plan(p_user);
  return jsonb_build_object('message', v_name || ' given to @' || v_who || '.', 'business', b.id);
end $$;

create or replace function public.admin_business_remove(p_business bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); b businesses; v_reason text := left(btrim(coalesce(p_reason, '')), 200); v_take bigint; v_plot text;
begin
  select * into b from businesses where id = p_business for update;
  if not found then
    raise exception 'That business is gone already.' using errcode = 'P0001', hint = 'gone';
  end if;
  perform 1 from profiles where id = b.owner_id for update;
  if b.listed then
    update market_listings set status = 'removed', closed_at = bl_now(), removed_by = v_admin, removed_reason = 'business removed'
     where kind = 'business' and ref_id = b.id::text and status = 'active';
    update market_offers set status = 'cancelled', closed_at = bl_now()
     where status = 'pending' and listing_id in (select id from market_listings where kind = 'business' and ref_id = b.id::text);
  else
    b := bl_biz_settle(b.id, false);
  end if;
  v_take := case when b.listed then 0 else floor(b.takings)::bigint end;
  if v_take > 0 then
    perform bl_add_money(b.owner_id, 'bank', v_take, 'business_income', jsonb_build_object('label', 'Takings: ' || b.name, 'business', b.id));
  end if;
  v_plot := b.plot_id;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'business_remove', b.owner_id, jsonb_build_object('business', b.id, 'name', b.name, 'type', b.type_id, 'plot', v_plot, 'reason', v_reason, 'takings_paid', v_take));
  perform bl_event(b.owner_id, 'business_removed', b.name || ' removed',
    'An admin took the business away.' || case when v_reason <> '' then ' Reason: ' || v_reason else '' end || case when v_take > 0 then ' Your takings of ' || bl_naira(v_take) || ' were paid to your bank.' else '' end,
    jsonb_build_object('business', b.id));
  delete from businesses where id = b.id;
  perform bl_biz_loc_sync(v_plot);
  perform bl_biz_push_plan(b.owner_id);
  return jsonb_build_object('message', b.name || ' removed.', 'business', b.id);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 11. Patches to live functions (guarded)
-- ---------------------------------------------------------------------------------------------
-- spending at somebody else's business pays the owner a cut
select pg_temp.bl_patch1('public.do_activity(text)', 'bl_biz_visit_cut(',
  E'    perform bl_add_money(v_me.id, ''cash'', -a.cost, ''activity'', jsonb_build_object(''activity'', a.id));',
  E'    perform bl_add_money(v_me.id, ''cash'', -a.cost, ''activity'', jsonb_build_object(''activity'', a.id));\n    perform bl_biz_visit_cut(v_me.id, v_loc.id, a.cost, a.name); -- R10: the business owner''s cut');
select pg_temp.bl_patch1('public.shop_buy(text, integer)', 'bl_biz_visit_cut(',
  E'                         jsonb_build_object(''item'', it.id, ''qty'', p_qty, ''location'', l.id));\n  end if;',
  E'                         jsonb_build_object(''item'', it.id, ''qty'', p_qty, ''location'', l.id));\n    perform bl_biz_visit_cut(v_me.id, l.id, v_total, it.name); -- R10: the business owner''s cut\n  end if;');
-- an owned business sells what plain places of its type sell
select pg_temp.bl_patch1('public.shop_buy(text, integer)', 'bl_biz_sells(',
  E'  if not (l.id = any (it.sold_at)) then',
  E'  if not (l.id = any (it.sold_at)) and not bl_biz_sells(l.id, it.id) then');
select pg_temp.bl_patch1('public.place_interior(text)', 'bl_biz_sells(',
  E'za.kind = ''shop'' and za.active and l.id = any (it.sold_at)',
  E'za.kind = ''shop'' and za.active and (l.id = any (it.sold_at) or bl_biz_sells(l.id, it.id))');

-- Market kind 'business'
select pg_temp.bl_patch1('public.bl_market_take(uuid, text, text, integer, text)', 'bl_biz_market_take(',
  E'  elsif p_kind = ''land'' then\n    select * into m from invest_markets',
  E'  elsif p_kind = ''business'' then\n    return bl_biz_market_take(p_uid, p_ref, p_qty);\n\n  elsif p_kind = ''land'' then\n    select * into m from invest_markets');
select pg_temp.bl_patch1('public.bl_market_give(uuid, text, text, integer, jsonb, bigint, boolean)', 'bl_biz_market_give(',
  E'  elsif p_kind = ''land'' then\n    select * into pos from invest_positions',
  E'  elsif p_kind = ''business'' then\n    perform bl_biz_market_give(p_uid, p_ref, p_detail, p_cost, p_strict);\n\n  elsif p_kind = ''land'' then\n    select * into pos from invest_positions');
select pg_temp.bl_patch1('public.bl_market_cond(text, jsonb, integer)', '''business''',
  E'    when ''item'' then case when p_qty > 1',
  E'    when ''business'' then ''Level '' || coalesce(p_detail->>''level'', ''1'') || '' · '' || coalesce(p_detail->>''type_name'', ''business'') || '' · '' || coalesce(p_detail->>''area'', '''')\n    when ''item'' then case when p_qty > 1');

-- ledger text
select pg_temp.bl_patch1('public.bl_ledger_label(text, jsonb)', 'when ''business_income'' then',
  E'    when ''garage'' then return',
  E'    when ''business_income'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Business income'');\n    when ''business_buy'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Business: bought'');\n    when ''business_upgrade'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Business: upgrade'');\n    when ''business_stock'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Business: restock'');\n    when ''business_hire'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Business: hired staff'');\n    when ''business_insure'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Business: insurance'');\n    when ''business_sell'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Business: sold'');\n    when ''garage'' then return');

-- admin Content editors
select pg_temp.bl_patch1('public.bl_admin_table_spec(text)', 'when ''business_types'' then',
  E'    when ''market_settings'' then',
  E'    when ''business_types'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","icon":"text","blurb":"text","scene":"text","price":"money","setup_minutes":"int","areas":"arr","income_min":"money","income_max":"money","rent_day":"money","power_day":"money","staff_slots":"int","staff_wage":"money","staff_income_pct":"num","restock_cost":"money","req_skill_level":"int","req_cert":"text_null","max_level":"int","levels":"obj","boost_pct":"num","events":"obj","sort":"int","active":"bool"}}''\n    when ''business_plots'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"area":"text","area_label":"text","district":"text","label":"text","x":"num","y":"num","type_ids":"arr","price_mult":"num","sort":"int","active":"bool"}}''\n    when ''market_settings'' then');

-- ---------------------------------------------------------------------------------------------
-- 12. Grants
-- ---------------------------------------------------------------------------------------------
revoke all on function public.bl_biz_plot_loc() from public, anon, authenticated;
revoke all on function public.bl_biz_gone() from public, anon, authenticated;
revoke all on function public.bl_biz_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_biz_on() from public, anon, authenticated;
revoke all on function public.bl_biz_hours(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.bl_biz_mult(public.business_types, int) from public, anon, authenticated;
revoke all on function public.bl_biz_lvcost(public.business_types, int) from public, anon, authenticated;
revoke all on function public.bl_biz_evn(public.business_types, text, text, text, numeric) from public, anon, authenticated;
revoke all on function public.bl_biz_price(public.business_types, public.business_plots) from public, anon, authenticated;
revoke all on function public.bl_biz_value(public.businesses) from public, anon, authenticated;
revoke all on function public.bl_biz_staff_name(bigint, int) from public, anon, authenticated;
revoke all on function public.bl_biz_stock_f(public.businesses, public.business_types, timestamptz) from public, anon, authenticated;
revoke all on function public.bl_biz_gross_hr(public.businesses, public.business_types) from public, anon, authenticated;
revoke all on function public.bl_biz_cost_hr(public.businesses, public.business_types) from public, anon, authenticated;
revoke all on function public.bl_biz_factor(public.businesses, public.business_types, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.bl_biz_log(bigint, uuid, text, text, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.bl_biz_loc_sync(text) from public, anon, authenticated;
revoke all on function public.bl_biz_pay(public.profiles, bigint, text, jsonb) from public, anon, authenticated;
revoke all on function public.bl_biz_gate(uuid, public.business_types) from public, anon, authenticated;
revoke all on function public.bl_biz_push_plan(uuid) from public, anon, authenticated;
revoke all on function public.bl_biz_settle(bigint, boolean) from public, anon, authenticated;
revoke all on function public.bl_biz_card(public.businesses, boolean) from public, anon, authenticated;
revoke all on function public.bl_biz_guard(public.profiles, boolean) from public, anon, authenticated;
revoke all on function public.bl_biz_mine(uuid, bigint, boolean) from public, anon, authenticated;
revoke all on function public.bl_biz_visit_cut(uuid, text, bigint, text) from public, anon, authenticated;
revoke all on function public.bl_biz_sells(text, text) from public, anon, authenticated;
revoke all on function public.bl_biz_market_take(uuid, text, int) from public, anon, authenticated;
revoke all on function public.bl_biz_market_give(uuid, text, jsonb, bigint, boolean) from public, anon, authenticated;

revoke all on function public.business_mine() from public, anon;
grant execute on function public.business_mine() to authenticated, service_role;
revoke all on function public.business_catalog() from public, anon;
grant execute on function public.business_catalog() to authenticated, service_role;
revoke all on function public.business_at(text) from public, anon;
grant execute on function public.business_at(text) to authenticated, service_role;
revoke all on function public.business_buy(text, text, text) from public, anon;
grant execute on function public.business_buy(text, text, text) to authenticated, service_role;
revoke all on function public.business_collect(bigint) from public, anon;
grant execute on function public.business_collect(bigint) to authenticated, service_role;
revoke all on function public.business_restock(bigint) from public, anon;
grant execute on function public.business_restock(bigint) to authenticated, service_role;
revoke all on function public.business_upgrade(bigint) from public, anon;
grant execute on function public.business_upgrade(bigint) to authenticated, service_role;
revoke all on function public.business_hire(bigint) from public, anon;
grant execute on function public.business_hire(bigint) to authenticated, service_role;
revoke all on function public.business_fire(bigint) from public, anon;
grant execute on function public.business_fire(bigint) to authenticated, service_role;
revoke all on function public.business_insure(bigint) from public, anon;
grant execute on function public.business_insure(bigint) to authenticated, service_role;
revoke all on function public.business_work(bigint) from public, anon;
grant execute on function public.business_work(bigint) to authenticated, service_role;
revoke all on function public.business_sell(bigint) from public, anon;
grant execute on function public.business_sell(bigint) to authenticated, service_role;
revoke all on function public.admin_business_overview(int) from public, anon;
grant execute on function public.admin_business_overview(int) to authenticated, service_role;
revoke all on function public.admin_business_get(uuid) from public, anon;
grant execute on function public.admin_business_get(uuid) to authenticated, service_role;
revoke all on function public.admin_business_grant(uuid, text, text, text) from public, anon;
grant execute on function public.admin_business_grant(uuid, text, text, text) to authenticated, service_role;
revoke all on function public.admin_business_remove(bigint, text) from public, anon;
grant execute on function public.admin_business_remove(bigint, text) to authenticated, service_role;

notify pgrst, 'reload schema';
