-- Benin Life I1 "Invest & Save" (docs/INVEST.md; owner-approved spec docs/ECONOMY_PLAN.md section 2).
-- New Bank-app tabs Save + Invest. Server-authoritative; every naira moves from / to the player's BANK balance.
--
-- Time scale: 1 game year = invest.year_days real days (30). One "invest day" = year / 365. All product terms, cycles,
-- daily incomes are in invest days. Returns accrue by real time and are computed lazily from timestamps (no jobs).
-- Market prices (stocks, crypto, land areas, bond wobble, property index) are a deterministic seeded random walk per
-- market per step (hash of market id + step), stored once in invest_prices, so every player sees the same series.
--
-- Tables (all admin-tunable catalogues have RLS read for signed-in players; positions/log/deals are own-row read):
--   invest_products   Save + Safe + Medium unit products (savings, safelock, mmf, fd, tbill, bond, farm, transport, pos, flat)
--   invest_markets    price-series assets (stocks, crypto, land areas, bond price, property index)
--   invest_prices / invest_dividends   shared deterministic series
--   invest_positions  my holdings  /  invest_land_deals (levy flow)  /  invest_log (history + realised profit)
-- RPCs (security definer, authenticated): invest_overview, invest_market_series, invest_buy, invest_withdraw,
--   invest_collect, invest_market_buy, invest_market_sell, invest_land_quote, invest_land_buy, invest_land_levy,
--   invest_land_sell. Private helpers bl_inv_* (revoked from clients).
-- Ledger reasons: invest_buy / invest_sell / invest_fee / invest_income (label in meta.label via bl_ledger_label).
-- Idempotent and safe on a non-empty DB: seeds use "on conflict do nothing"; the live functions bl_ledger_label and
-- bl_admin_table_spec are patched from pg_get_functiondef with guarded replacements (grants are kept).

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (category invest)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('invest.enabled', 'true', 'invest', 'Invest & Save on',
 'I1: the Save and Invest tabs in the Bank app. Off = no new deposits or purchases (selling and withdrawing still work).', 'bool', null, null),
('invest.year_days', '30', 'invest', 'One game year = real days',
 'I1: how many REAL days make one game year. Every yearly rate (10%, 18%...) is per game year, accrued continuously by real time. One "invest day" (terms, cycles, daily income) = a game year / 365.', 'number', 1, 3650),
('invest.land_deal_minutes', '10', 'invest', 'Land deal expiry (real minutes)',
 'I1: how long a land deal with a development-levy demand waits for the player to pay or walk away.', 'minutes', 1, 1440),
('invest.land_walk_cooldown_seconds', '30', 'invest', 'Land: wait after walking away (seconds)',
 'I1: after the player walks away from a land deal (levy) they must wait this long before opening another deal. Stops re-rolling the levy chance for free.', 'number', 0, 86400),
('invest.event_days_cap', '365', 'invest', 'Max invest days of risk rolls per visit',
 'I1: transport / POS / flat risk events are rolled once per invest day since the last visit, at most this many days per visit (income for older days is paid without risk rolls).', 'number', 1, 3650),
('invest.spark_points', '48', 'invest', 'Chart points per market',
 'I1: how many points the small market charts get (the last 7 real days).', 'number', 8, 200)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.invest_products (
  id                 text primary key,
  kind               text not null check (kind in ('savings','safelock','mmf','fd','tbill','bond','farm','transport','pos','flat')),
  name               text not null,
  icon               text not null default '💰',
  blurb              text not null default '',
  risk               text not null default 'safe' check (risk in ('safe','medium','high')),
  rate_pct           numeric not null default 0 check (rate_pct >= 0),
  term_days          int not null default 0 check (term_days >= 0),
  exit_fee_pct       numeric not null default 0 check (exit_fee_pct between 0 and 100),
  forfeits_interest  boolean not null default false,
  unit_price         bigint not null default 0 check (unit_price >= 0),
  market_id          text,
  min_amount         bigint not null default 1000 check (min_amount >= 1),
  max_amount         bigint not null default 1000000000000 check (max_amount >= 1 and max_amount <= 9000000000000000),
  cycle_days         int not null default 0 check (cycle_days >= 0),
  gain_min_pct       numeric not null default 0,
  gain_max_pct       numeric not null default 0,
  income_day         bigint not null default 0 check (income_day >= 0),
  resale_pct         numeric not null default 100 check (resale_pct between 0 and 100),
  depr_pct_year      numeric not null default 0 check (depr_pct_year >= 0),
  resale_floor_pct   numeric not null default 0 check (resale_floor_pct between 0 and 100),
  events             jsonb not null default '{}'::jsonb,
  sort               int not null default 100,
  active             boolean not null default true
);

create table if not exists public.invest_markets (
  id                   text primary key,
  kind                 text not null check (kind in ('stock','crypto','land','bond','index')),
  name                 text not null,
  icon                 text not null default '📈',
  blurb                text not null default '',
  risk                 text not null default 'medium' check (risk in ('safe','medium','high')),
  ticker               text not null default '',
  base_price           numeric not null check (base_price > 0),
  price_mult           numeric not null default 1 check (price_mult > 0),
  drift_pct_year       numeric not null default 0,
  vol_pct              numeric not null default 0 check (vol_pct >= 0),
  step_seconds         int not null default 3600 check (step_seconds >= 60),
  swing_pct            numeric not null default 0 check (swing_pct >= 0),
  swing_days           numeric not null default 20 check (swing_days > 0),
  fee_pct              numeric not null default 0 check (fee_pct between 0 and 100),
  community_pct        numeric not null default 0 check (community_pct >= 0),
  levy_chance_pct      numeric not null default 0 check (levy_chance_pct between 0 and 100),
  levy_min_pct         numeric not null default 0 check (levy_min_pct >= 0),
  levy_max_pct         numeric not null default 0 check (levy_max_pct >= 0),
  dividend_chance_pct  numeric not null default 0 check (dividend_chance_pct between 0 and 100),
  dividend_yield_pct   numeric not null default 0 check (dividend_yield_pct >= 0),
  min_qty              numeric not null default 1 check (min_qty > 0),
  max_qty              numeric not null default 1000000 check (max_qty > 0),
  start_at             timestamptz not null default (date_trunc('hour', now()) - interval '7 days'),
  sort                 int not null default 100,
  active               boolean not null default true
);

create table if not exists public.invest_prices (
  market_id text not null references public.invest_markets(id) on delete cascade,
  step      bigint not null,
  walk      numeric not null,
  price     numeric not null,
  primary key (market_id, step)
);

create table if not exists public.invest_dividends (
  market_id text not null references public.invest_markets(id) on delete cascade,
  step      bigint not null,
  per_share numeric not null,
  primary key (market_id, step)
);

create table if not exists public.invest_positions (
  id         bigserial primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  ref_id     text not null,
  kind       text not null,
  qty        numeric not null default 0 check (qty >= 0),
  cost       bigint not null default 0 check (cost >= 0),
  accrued    bigint not null default 0,
  opened_at  timestamptz not null,
  last_at    timestamptz not null,
  matures_at timestamptz,
  state      jsonb not null default '{}'::jsonb
);
create index if not exists invest_positions_user_idx on public.invest_positions (user_id);
create unique index if not exists invest_positions_pooled_uq on public.invest_positions (user_id, ref_id)
  where kind in ('savings','mmf','bond','stock','crypto','land');

create table if not exists public.invest_land_deals (
  id          bigserial primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  area        text not null references public.invest_markets(id) on delete cascade,
  plots       int not null check (plots > 0),
  plot_price  bigint not null,
  subtotal    bigint not null,
  agent_fee   bigint not null,
  community   bigint not null,
  levy        bigint not null default 0,
  status      text not null default 'pending' check (status in ('pending','done','walked','expired')),
  created_at  timestamptz not null,
  expires_at  timestamptz not null,
  closed_at   timestamptz
);
create index if not exists invest_land_deals_user_idx on public.invest_land_deals (user_id, created_at desc);

create table if not exists public.invest_log (
  id      bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  at      timestamptz not null,
  kind    text not null,
  ref_id  text not null default '',
  label   text not null default '',
  amount  bigint not null default 0,
  profit  bigint,
  meta    jsonb not null default '{}'::jsonb
);
create index if not exists invest_log_user_idx on public.invest_log (user_id, id desc);

alter table public.invest_products   enable row level security;
alter table public.invest_markets    enable row level security;
alter table public.invest_prices     enable row level security;
alter table public.invest_dividends  enable row level security;
alter table public.invest_positions  enable row level security;
alter table public.invest_land_deals enable row level security;
alter table public.invest_log        enable row level security;
revoke all on table public.invest_products, public.invest_markets, public.invest_prices, public.invest_dividends,
  public.invest_positions, public.invest_land_deals, public.invest_log from public, anon, authenticated;
revoke all on sequence public.invest_positions_id_seq, public.invest_land_deals_id_seq, public.invest_log_id_seq
  from public, anon, authenticated;
-- catalogues and shared price series: readable by every signed-in player; writes only via admin_row_upsert / the RPCs
grant select on table public.invest_products, public.invest_markets, public.invest_prices, public.invest_dividends to authenticated;
drop policy if exists invest_products_read on public.invest_products;
create policy invest_products_read on public.invest_products for select to authenticated using (true);
drop policy if exists invest_markets_read on public.invest_markets;
create policy invest_markets_read on public.invest_markets for select to authenticated using (true);
drop policy if exists invest_prices_read on public.invest_prices;
create policy invest_prices_read on public.invest_prices for select to authenticated using (true);
drop policy if exists invest_dividends_read on public.invest_dividends;
create policy invest_dividends_read on public.invest_dividends for select to authenticated using (true);
-- my own holdings, deals and history (no client writes)
grant select on table public.invest_positions, public.invest_land_deals, public.invest_log to authenticated;
drop policy if exists invest_positions_own on public.invest_positions;
create policy invest_positions_own on public.invest_positions for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists invest_land_deals_own on public.invest_land_deals;
create policy invest_land_deals_own on public.invest_land_deals for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists invest_log_own on public.invest_log;
create policy invest_log_own on public.invest_log for select to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------
-- 3. Seeds: products
-- ---------------------------------------------------------------------------------------------
insert into public.invest_products
  (id, kind, name, icon, blurb, risk, rate_pct, term_days, exit_fee_pct, forfeits_interest, unit_price, market_id, min_amount, max_amount,
   cycle_days, gain_min_pct, gain_max_pct, income_day, resale_pct, depr_pct_year, resale_floor_pct, events, sort) values
('bronze_savings', 'savings', 'Bronze Savings', '🥉', 'Plain savings. 10% a game year, take your money out any time.', 'safe', 10, 0, 0, false, 0, null, 500, 1000000000000, 0, 0, 0, 0, 100, 0, 0, '{}', 10),
('safelock_7',  'safelock', 'SafeLock 7 days',  '🔒', 'Lock it for 7 days at 15% a year. Break it early and you lose ALL the interest (you get your money back).', 'safe', 15, 7,  0, true, 0, null, 5000, 1000000000000, 0, 0, 0, 0, 100, 0, 0, '{}', 20),
('safelock_30', 'safelock', 'SafeLock 30 days', '🔒', 'Lock it for 30 days at 18% a year. Break it early and you lose ALL the interest.', 'safe', 18, 30, 0, true, 0, null, 5000, 1000000000000, 0, 0, 0, 0, 100, 0, 0, '{}', 21),
('safelock_90', 'safelock', 'SafeLock 90 days', '🔒', 'Lock it for 90 days at 22% a year. Break it early and you lose ALL the interest.', 'safe', 22, 90, 0, true, 0, null, 5000, 1000000000000, 0, 0, 0, 0, 100, 0, 0, '{}', 22),
('mmf', 'mmf', 'Money market fund', '🏦', 'Pooled short-term money. 18% a game year, in and out any time.', 'safe', 18, 0, 0, false, 0, null, 1000, 1000000000000, 0, 0, 0, 0, 100, 0, 0, '{}', 30),
('fd_30', 'fd', 'Fixed deposit 30 days', '📄', 'Bank fixed deposit, 16% a year for 30 days. Exit early and the interest is gone.', 'safe', 16, 30, 0, true, 0, null, 10000, 1000000000000, 0, 0, 0, 0, 100, 0, 0, '{}', 31),
('fd_90', 'fd', 'Fixed deposit 90 days', '📄', 'Bank fixed deposit, 19% a year for 90 days. Exit early and the interest is gone.', 'safe', 19, 90, 0, true, 0, null, 10000, 1000000000000, 0, 0, 0, 0, 100, 0, 0, '{}', 32),
('tbill_91',  'tbill', 'Treasury bill 91 days',  '🏛️', 'FGN T-bill. 16% a year, 91 days. Sell early: 2% fee, you keep the interest earned so far.', 'safe', 16,    91,  2, false, 0, null, 50000, 1000000000000, 0, 0, 0, 0, 100, 0, 0, '{}', 40),
('tbill_182', 'tbill', 'Treasury bill 182 days', '🏛️', 'FGN T-bill. 17.75% a year, 182 days. Sell early: 2% fee, you keep the interest earned so far.', 'safe', 17.75, 182, 2, false, 0, null, 50000, 1000000000000, 0, 0, 0, 0, 100, 0, 0, '{}', 41),
('tbill_364', 'tbill', 'Treasury bill 364 days', '🏛️', 'FGN T-bill. 21.85% a year, 364 days. Sell early: 2% fee, you keep the interest earned so far.', 'safe', 21.85, 364, 2, false, 0, null, 50000, 1000000000000, 0, 0, 0, 0, 100, 0, 0, '{}', 42),
('fgn_bond', 'bond', 'FGN bond', '📜', 'Pays a 19% coupon on face value. Sell any time at the market price, which wobbles about 3% either way.', 'safe', 19, 0, 0.5, false, 0, 'fgn_bond', 10000, 1000000000000, 0, 0, 0, 0, 100, 0, 0, '{}', 50),
-- farms: cycle = invest days, payout +25-40%, one roll per risk event at harvest
('farm_poultry', 'farm', 'Poultry unit', '🐔', 'A pen of 100 broilers. Harvest after one cycle for +25-35%. Risk: bird flu, thieves.', 'medium', 0, 0, 0, false, 150000, null, 1, 100, 150, 25, 35, 0, 80, 0, 0,
 '{"bird_flu":{"label":"Bird flu hit the pens","chance_pct":10,"loss_of":"cycle","loss_pct":60},"theft":{"label":"Thieves cleared some birds","chance_pct":5,"loss_of":"cycle","loss_pct":30}}', 100),
('farm_fish', 'farm', 'Fish pond unit', '🐟', 'One earth pond of catfish. +28-38% after a cycle. Risk: flood, thieves.', 'medium', 0, 0, 0, false, 400000, null, 1, 100, 180, 28, 38, 0, 80, 0, 0,
 '{"flood":{"label":"Flood broke the pond wall","chance_pct":8,"loss_of":"cycle","loss_pct":50},"theft":{"label":"Thieves netted the fish at night","chance_pct":5,"loss_of":"cycle","loss_pct":30}}', 101),
('farm_cassava', 'farm', 'Cassava farm unit', '🥔', 'A hectare of cassava. +30-40% at harvest. Risk: flood, thieves.', 'medium', 0, 0, 0, false, 250000, null, 1, 100, 270, 30, 40, 0, 80, 0, 0,
 '{"flood":{"label":"Flood washed the ridges","chance_pct":10,"loss_of":"cycle","loss_pct":45},"theft":{"label":"Thieves harvested before you","chance_pct":6,"loss_of":"cycle","loss_pct":25}}', 102),
('farm_plantain', 'farm', 'Plantain farm unit', '🍌', 'A plantain plot. +25-35% at harvest. Risk: flood, thieves.', 'medium', 0, 0, 0, false, 300000, null, 1, 100, 240, 25, 35, 0, 80, 0, 0,
 '{"flood":{"label":"Flood hit the plantain plot","chance_pct":8,"loss_of":"cycle","loss_pct":40},"theft":{"label":"Thieves cut the bunches","chance_pct":6,"loss_of":"cycle","loss_pct":30}}', 103),
-- transport / POS: daily income per unit, random breakdowns / fraud
('transport_keke', 'transport', 'Keke (tricycle)', '🛺', 'A keke on hire. Earns daily income. Risk: breakdowns and police wahala. Sells back at a depreciated price.', 'medium', 0, 0, 0, false, 2400000, null, 1, 50, 0, 0, 0, 3800, 88, 12, 35,
 '{"breakdown":{"label":"Keke breakdown, mechanic collect money","chance_pct":1.5,"loss_of":"unit","loss_pct":3.5},"police":{"label":"Police checkpoint wahala, no work today","chance_pct":0.6,"loss_of":"income","loss_pct":100}}', 110),
('transport_okada', 'transport', 'Okada (motorbike)', '🏍️', 'An okada for a rider. Earns daily income. Risk: breakdowns, accidents.', 'medium', 0, 0, 0, false, 900000, null, 1, 50, 0, 0, 0, 1500, 88, 12, 35,
 '{"breakdown":{"label":"Okada knock engine","chance_pct":2,"loss_of":"unit","loss_pct":3},"accident":{"label":"Small accident, repair bill","chance_pct":0.4,"loss_of":"unit","loss_pct":10}}', 111),
('transport_sienna', 'transport', 'Sienna bus', '🚐', 'A Sienna on the Ramat Park run. Earns daily income. Risk: breakdowns.', 'medium', 0, 0, 0, false, 9500000, null, 1, 25, 0, 0, 0, 14000, 88, 12, 35,
 '{"breakdown":{"label":"Sienna gearbox wahala","chance_pct":1.2,"loss_of":"unit","loss_pct":3.5},"go_slow":{"label":"Ramat go-slow, half day lost","chance_pct":1.5,"loss_of":"income","loss_pct":50}}', 112),
('pos_stand', 'pos', 'POS stand', '🏧', 'One POS machine at a busy junction. Daily commission. Risk: fake-alert fraud, network down.', 'medium', 0, 0, 0, false, 450000, null, 1, 100, 0, 0, 0, 600, 85, 0, 0,
 '{"fraud":{"label":"Fake alert fraud, customer don run","chance_pct":0.5,"loss_of":"unit","loss_pct":8},"network":{"label":"Network down all day","chance_pct":3,"loss_of":"income","loss_pct":100}}', 120),
('pos_shop', 'pos', 'POS shop (3 machines)', '🏪', 'A small POS shop with three machines. Bigger daily commission, same fraud risk.', 'medium', 0, 0, 0, false, 1200000, null, 1, 50, 0, 0, 0, 1700, 85, 0, 0,
 '{"fraud":{"label":"Fake alert fraud, customer don run","chance_pct":0.5,"loss_of":"unit","loss_pct":8},"network":{"label":"Network down all day","chance_pct":3,"loss_of":"income","loss_pct":100}}', 121),
-- rental flats (high): price follows the property index; daily rent; vacancy spells and repair bills
('flat_room', 'flat', 'Room & parlour block', '🏘️', 'A small block of rooms. Daily rent. Risk: empty months and repair bills. Sells at the market price (3% agent fee).', 'high', 0, 0, 3, false, 6000000, 'property_index', 1, 20, 0, 0, 0, 3200, 100, 0, 0,
 '{"vacancy":{"label":"Tenants left, flat empty a month","chance_pct":0.45,"loss_of":"vacancy","span_days":30},"repair":{"label":"Roof and pipe repairs","chance_pct":0.25,"loss_of":"unit","loss_pct":4}}', 200),
('flat_2bed', 'flat', '2-bedroom flat', '🏢', 'A 2-bedroom flat in a good area. Daily rent. Risk: empty months and repair bills.', 'high', 0, 0, 3, false, 18000000, 'property_index', 1, 10, 0, 0, 0, 9500, 100, 0, 0,
 '{"vacancy":{"label":"Tenant left, flat empty a month","chance_pct":0.45,"loss_of":"vacancy","span_days":30},"repair":{"label":"Burst pipe and wiring repairs","chance_pct":0.25,"loss_of":"unit","loss_pct":4}}', 201),
('flat_duplex', 'flat', 'Duplex for rent', '🏡', 'A duplex let to a company. Daily rent. Risk: empty months and repair bills.', 'high', 0, 0, 3, false, 45000000, 'property_index', 1, 5, 0, 0, 0, 24000, 100, 0, 0,
 '{"vacancy":{"label":"Company moved out, duplex empty a month","chance_pct":0.45,"loss_of":"vacancy","span_days":30},"repair":{"label":"Generator house and roof repairs","chance_pct":0.25,"loss_of":"unit","loss_pct":4}}', 202)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Seeds: markets
-- ---------------------------------------------------------------------------------------------
insert into public.invest_markets
  (id, kind, name, icon, blurb, risk, ticker, base_price, drift_pct_year, vol_pct, step_seconds, swing_pct, swing_days,
   fee_pct, community_pct, levy_chance_pct, levy_min_pct, levy_max_pct, dividend_chance_pct, dividend_yield_pct, min_qty, max_qty, sort) values
('stk_okomu',   'stock', 'Okomu Oil',     '🌴', 'Palm oil and rubber estates in Edo. Steady grower.',        'medium', 'OKOMUOIL',   710,  14, 1.0, 3600, 0, 20, 0.5, 0, 0, 0, 0, 0.25, 3.0, 1, 1000000, 10),
('stk_presco',  'stock', 'Presco',        '🌿', 'Palm and rubber plantations near Benin. Jumpy.',            'medium', 'PRESCO',     1350, 16, 1.3, 3600, 0, 20, 0.5, 0, 0, 0, 0, 0.25, 3.5, 1, 1000000, 11),
('stk_dangcem', 'stock', 'Dangote Cement','🏭', 'Biggest cement maker in Africa. Calm.',                     'medium', 'DANGCEM',    540,  10, 0.8, 3600, 0, 20, 0.5, 0, 0, 0, 0, 0.25, 2.5, 1, 1000000, 12),
('stk_mtnn',    'stock', 'MTN Nigeria',   '📱', 'The network everybody uses.',                               'medium', 'MTNN',       330,  12, 0.9, 3600, 0, 20, 0.5, 0, 0, 0, 0, 0.25, 2.5, 1, 1000000, 13),
('stk_gtco',    'stock', 'GTCO',          '🏦', 'Guaranty Trust bank group.',                                'medium', 'GTCO',       68,   15, 1.1, 3600, 0, 20, 0.5, 0, 0, 0, 0, 0.25, 3.0, 1, 1000000, 14),
('stk_zenith',  'stock', 'Zenith Bank',   '🏦', 'Big bank, big dividends.',                                  'medium', 'ZENITHBANK', 52,   13, 1.0, 3600, 0, 20, 0.5, 0, 0, 0, 0, 0.25, 3.0, 1, 1000000, 15),
('crypto_btc',  'crypto','Bitcoin (BTC)', '₿', 'Very wild. Can double or halve. Long run goes up.',         'high',   'BTC',        150000000, 55, 0.55, 900, 0, 20, 0.8, 0, 0, 0, 0, 0, 0, 0.00001, 1000, 30),
('crypto_usdt', 'crypto','Tether (USDT)', '💵', 'Dollar coin. Moves small, drifts up as naira weakens.',    'high',   'USDT',       1550, 6, 0.12, 900, 0, 20, 0.5, 0, 0, 0, 0, 0, 0, 1, 100000000, 31),
('land_gra',        'land', 'GRA',        '🏡', 'Quiet, formal, expensive. Elders easy to settle.',                  'high', 'GRA',        12000000, 22, 0.5, 21600, 5, 25, 5, 4,  8,  3, 8,  0, 0, 1, 100, 40),
('land_ugbowo',     'land', 'Ugbowo',     '🎓', 'By UNIBEN. Students and landlords everywhere.',                     'high', 'Ugbowo',     6000000,  28, 0.55, 21600, 6, 25, 5, 7,  15, 4, 10, 0, 0, 1, 100, 41),
('land_sapele',     'land', 'Sapele Rd',  '🛣️', 'Busy road frontage. Many hands to settle.',                         'high', 'Sapele Rd',  4500000,  24, 0.55, 21600, 6, 25, 5, 9,  18, 4, 11, 0, 0, 1, 100, 42),
('land_airport',    'land', 'Airport Rd', '✈️', 'Near the airport. Fast growth, tough negotiations.',                 'high', 'Airport Rd', 3500000,  30, 0.6, 21600, 7, 25, 5, 10, 20, 5, 12, 0, 0, 1, 100, 43),
('land_ikpoba',     'land', 'Ikpoba Hill','⛰️', 'Hilltop plots. Omonile family wants plenty.',                      'high', 'Ikpoba Hill',2500000,  26, 0.6, 21600, 7, 25, 6, 12, 25, 5, 13, 0, 0, 1, 100, 44),
('land_okhoro',     'land', 'Okhoro',     '🌆', 'Fast-growing edge of town. Area boys will come.',                   'high', 'Okhoro',     1800000,  33, 0.7, 21600, 8, 25, 6, 15, 30, 6, 14, 0, 0, 1, 100, 45),
('land_ekenwan',    'land', 'Ekenwan',    '🛤️', 'Cheapest plots, biggest growth, roughest settlement.',               'high', 'Ekenwan',    1200000,  35, 0.8, 21600, 9, 25, 7, 18, 35, 6, 15, 0, 0, 1, 100, 46),
('fgn_bond',        'bond', 'FGN bond price','📜', 'Market price of the FGN bond (per ₦100 face). Wobbles about 3%.', 'safe', 'FGN',       100,       0,  0,   3600,  3, 12, 0, 0, 0, 0, 0, 0, 0, 1, 1000000, 60),
('property_index',  'index','Property index','🏘️', 'How much rental flats are worth. Drives flat prices and resale.', 'high', 'PROP',      1000,      14, 0.5, 21600, 4, 30, 0, 0, 0, 0, 0, 0, 0, 1, 1000000, 61)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 5. Private helpers (bl_inv_*)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_inv_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

-- seconds in one game year / one invest day (a game year / 365)
create or replace function public.bl_inv_year() returns numeric
language sql stable set search_path = public as $$
  select greatest(1, bl_inv_num('invest.year_days', 30)) * 86400;
$$;
create or replace function public.bl_inv_day() returns numeric
language sql stable set search_path = public as $$
  select bl_inv_year() / 365;
$$;

-- simple interest: floor(amount * rate% * seconds / year)
create or replace function public.bl_inv_interest(p_amt numeric, p_rate numeric, p_secs numeric) returns bigint
language sql stable set search_path = public as $$
  select floor(greatest(0, p_amt) * greatest(0, p_rate) / 100 * greatest(0, p_secs) / bl_inv_year())::bigint;
$$;

-- deterministic uniform [0,1) from a seed string
create or replace function public.bl_inv_u(p_seed text) returns double precision
language sql immutable set search_path = public as $$
  select (('x' || substr(md5(p_seed), 1, 13))::bit(52)::bigint)::double precision / 4503599627370496.0;
$$;

-- smooth value noise in [-1, 1]: cosine interpolation between hashed knots
create or replace function public.bl_inv_vnoise(p_seed text, p_t numeric, p_knot numeric) returns double precision
language plpgsql immutable set search_path = public as $$
declare k bigint := floor(p_t / p_knot); f double precision := (p_t / p_knot - k)::double precision; a double precision; b double precision;
begin
  a := bl_inv_u(p_seed || ':' || k) * 2 - 1;
  b := bl_inv_u(p_seed || ':' || (k + 1)) * 2 - 1;
  return a + (b - a) * ((1 - cos(pi() * f)) / 2);
end $$;

-- swing component of a market's price at time t (epoch seconds): bounded by swing_pct
create or replace function public.bl_inv_swing(m public.invest_markets, p_t numeric) returns numeric
language sql stable set search_path = public as $$
  select case when m.swing_pct <= 0 then 0::numeric else
    (m.swing_pct / 100 * (0.6 * bl_inv_vnoise(m.id || 'a', p_t, greatest(60, m.swing_days * bl_inv_day()))
                        + 0.4 * bl_inv_vnoise(m.id || 'b', p_t, greatest(60, m.swing_days * bl_inv_day() * 0.37))))::numeric end;
$$;

-- Generate the shared series up to now (lazy, under an advisory lock so every player sees the same rows).
create or replace function public.bl_inv_extend(p_market text) returns void
language plpgsql set search_path = public as $$
declare
  m invest_markets;
  v_now_step bigint; v_last bigint; v_walk numeric; v_first bigint; v_to bigint; v_y numeric := bl_inv_year();
  v_drift numeric; v_loops int := 0;
begin
  select * into m from invest_markets where id = p_market;
  if not found then return; end if;
  v_now_step := floor(extract(epoch from bl_now()) / m.step_seconds)::bigint;
  select max(step) into v_last from invest_prices where market_id = p_market;
  if v_last is not null and v_last >= v_now_step then return; end if;
  perform pg_advisory_xact_lock(hashtextextended('invest_prices:' || p_market, 0));
  select step, walk into v_last, v_walk from invest_prices where market_id = p_market order by step desc limit 1;
  if not found then
    v_first := floor(extract(epoch from m.start_at) / m.step_seconds)::bigint;
    insert into invest_prices (market_id, step, walk, price)
    values (m.id, v_first, m.base_price,
            greatest(0.01, case when m.kind = 'land' then round(m.base_price * (1 + bl_inv_swing(m, v_first::numeric * m.step_seconds)))
                                else round(m.base_price * (1 + bl_inv_swing(m, v_first::numeric * m.step_seconds)), 2) end));
    v_last := v_first; v_walk := m.base_price;
  end if;
  if v_last >= v_now_step then return; end if;
  v_drift := ln(1 + greatest(m.drift_pct_year, -99) / 100) * m.step_seconds / v_y;
  while v_last < v_now_step and v_loops < 6 loop
    v_loops := v_loops + 1;
    v_to := least(v_now_step, v_last + 4000);
    with s as (
      select g as step,
             v_drift + (m.vol_pct / 100) * ((bl_inv_u(m.id || ':' || g || ':1') + bl_inv_u(m.id || ':' || g || ':2') + bl_inv_u(m.id || ':' || g || ':3') - 1.5) * 2)::numeric
               - 0.5 * power(m.vol_pct / 100, 2) as ret
        from generate_series(v_last + 1, v_to) g
    ), c as (
      select step, v_walk * exp(sum(ret) over (order by step)) as walk from s
    )
    insert into invest_prices (market_id, step, walk, price)
    select m.id, step, walk,
           greatest(0.01, case when m.kind = 'land' then round(walk * (1 + bl_inv_swing(m, step::numeric * m.step_seconds)))
                               else round(walk * (1 + bl_inv_swing(m, step::numeric * m.step_seconds)), 2) end)
      from c;
    if m.dividend_chance_pct > 0 and m.dividend_yield_pct > 0 then
      insert into invest_dividends (market_id, step, per_share)
      select p.market_id, p.step, round(p.price * m.dividend_yield_pct / 100, 2)
        from invest_prices p
       where p.market_id = m.id and p.step > v_last and p.step <= v_to
         and bl_inv_u(m.id || ':' || p.step || ':d') * 100 < m.dividend_chance_pct
      on conflict do nothing;
    end if;
    select walk into v_walk from invest_prices where market_id = m.id and step = v_to;
    v_last := v_to;
  end loop;
end $$;

-- Current (or past) price per unit, with the admin price multiplier applied.
create or replace function public.bl_inv_price(p_market text, p_at timestamptz default null) returns numeric
language plpgsql set search_path = public as $$
declare m invest_markets; v_p numeric; v_step bigint;
begin
  select * into m from invest_markets where id = p_market;
  if not found then
    raise exception 'Market no dey.' using errcode = 'P0001', hint = 'bad_market';
  end if;
  perform bl_inv_extend(p_market);
  v_step := floor(extract(epoch from coalesce(p_at, bl_now())) / m.step_seconds)::bigint;
  select price into v_p from invest_prices where market_id = p_market and step <= v_step order by step desc limit 1;
  if v_p is null then
    select price into v_p from invest_prices where market_id = p_market order by step asc limit 1;
  end if;
  v_p := v_p * m.price_mult;
  return case when m.kind = 'land' then round(v_p) else round(v_p, 2) end;
end $$;

-- Chart points [[epoch_seconds, price], ...] for the last p_hours (about p_points points, last point = now).
create or replace function public.bl_inv_series(p_market text, p_points int default 48, p_hours int default 168) returns jsonb
language plpgsql set search_path = public as $$
declare m invest_markets; v_cur bigint; v_win bigint; v_stride bigint;
begin
  select * into m from invest_markets where id = p_market;
  if not found then return '[]'::jsonb; end if;
  perform bl_inv_extend(p_market);
  v_cur := floor(extract(epoch from bl_now()) / m.step_seconds)::bigint;
  v_win := greatest(2, (p_hours::numeric * 3600 / m.step_seconds)::bigint);
  v_stride := greatest(1, ceil(v_win::numeric / greatest(8, p_points))::bigint);
  return coalesce((
    select jsonb_agg(jsonb_build_array(p.step * m.step_seconds,
             case when m.kind = 'land' then round(p.price * m.price_mult) else round(p.price * m.price_mult, 2) end) order by p.step)
      from invest_prices p
     where p.market_id = p_market and p.step <= v_cur and p.step > v_cur - v_win and (v_cur - p.step) % v_stride = 0
  ), '[]'::jsonb);
end $$;

create or replace function public.bl_inv_change(p_market text, p_hours int default 24) returns numeric
language plpgsql set search_path = public as $$
declare v_now numeric; v_old numeric;
begin
  v_now := bl_inv_price(p_market);
  v_old := bl_inv_price(p_market, bl_now() - make_interval(hours => p_hours));
  if v_old is null or v_old = 0 then return 0; end if;
  return round((v_now / v_old - 1) * 100, 2);
end $$;

create or replace function public.bl_inv_roll(p_pct numeric) returns boolean
language sql volatile set search_path = public as $$
  select bl_rand() * 100 < coalesce(p_pct, 0);
$$;

create or replace function public.bl_inv_log(p_uid uuid, p_kind text, p_ref text, p_label text, p_amount bigint, p_profit bigint,
                                             p_meta jsonb default '{}'::jsonb) returns void
language sql set search_path = public as $$
  insert into invest_log (user_id, at, kind, ref_id, label, amount, profit, meta)
  values (p_uid, bl_now(), p_kind, coalesce(p_ref, ''), coalesce(p_label, ''), coalesce(p_amount, 0), p_profit, coalesce(p_meta, '{}'::jsonb));
$$;

-- Guard used by every RPC: banned/jail handled by bl_me(); jailed players can't touch the phone bank.
create or replace function public.bl_inv_assert_ok(p_me public.profiles, p_buying boolean) returns void
language plpgsql set search_path = public as $$
begin
  if p_me.jailed_until is not null and p_me.jailed_until > bl_now() then
    raise exception 'The police took your phone. Investments can wait until you are out.' using errcode = 'P0001', hint = 'jailed';
  end if;
  if p_buying and not coalesce((select (value #>> '{}')::boolean from game_config where key = 'invest.enabled'), true) then
    raise exception 'Invest and Save is closed for now. You can still sell and withdraw.' using errcode = 'P0001', hint = 'closed';
  end if;
end $$;

create or replace function public.bl_inv_need_bank(p_me public.profiles, p_need numeric) returns void
language plpgsql set search_path = public as $$
begin
  if p_need > 9000000000000000 then
    raise exception 'That amount is too big.' using errcode = 'P0001', hint = 'bad_amount';
  end if;
  if p_me.bank < p_need then
    raise exception 'Not enough in your bank. You need % but your bank has %. Deposit cash at Bronze Bank or a PoS stand first.',
      bl_naira(p_need), bl_naira(p_me.bank) using errcode = 'P0001', hint = 'not_enough_bank';
  end if;
end $$;

create or replace function public.bl_inv_amount(p_amount numeric, p_min numeric, p_max numeric, p_what text) returns void
language plpgsql set search_path = public as $$
begin
  if p_amount is null or p_amount < 1 or p_amount <> trunc(p_amount) then
    raise exception 'Put a whole number, abeg.' using errcode = 'P0001', hint = 'bad_amount';
  end if;
  if p_amount < p_min then
    raise exception 'Minimum for % is %.', p_what, case when p_what like '%unit%' then p_min::text else bl_naira(p_min) end using errcode = 'P0001', hint = 'bad_amount';
  end if;
  if p_amount > p_max then
    raise exception 'Maximum at once for % is %.', p_what, case when p_what like '%unit%' then p_max::text else bl_naira(p_max) end using errcode = 'P0001', hint = 'bad_amount';
  end if;
end $$;

-- Pay dividends / resolve daily risk events for one position since last_at. The caller holds the player lock (bl_me()).
create or replace function public.bl_inv_settle_pos(p_id bigint) returns void
language plpgsql set search_path = public as $$
declare
  pos invest_positions; pr invest_products; m invest_markets;
  v_now timestamptz := bl_now(); v_day numeric := bl_inv_day();
  v_ps numeric; v_div bigint; v_n int; v_skip int; v_cap int; i int; ev record;
  v_inc bigint; v_vac timestamptz; v_acc bigint; v_ds timestamptz; v_loss bigint; v_cnt int := 0; v_lost bigint := 0; v_msg text := '';
  v_state jsonb;
begin
  select * into pos from invest_positions where id = p_id for update;
  if not found then return; end if;
  if pos.kind = 'stock' then
    select * into m from invest_markets where id = pos.ref_id;
    if not found then return; end if;
    perform bl_inv_extend(m.id);
    select coalesce(sum(d.per_share), 0) into v_ps from invest_dividends d
     where d.market_id = m.id
       and to_timestamp(d.step::double precision * m.step_seconds) > pos.last_at
       and to_timestamp(d.step::double precision * m.step_seconds) <= v_now;
    v_div := floor(pos.qty * v_ps * m.price_mult)::bigint;
    if v_div > 0 then
      perform bl_add_money(pos.user_id, 'bank', v_div, 'invest_income', jsonb_build_object('label', 'Dividend: ' || m.name, 'market', m.id));
      perform bl_inv_log(pos.user_id, 'dividend', m.id, 'Dividend: ' || m.name, v_div, v_div, jsonb_build_object('shares', pos.qty));
      perform bl_event(pos.user_id, 'invest', m.name || ' paid a dividend', 'You got ' || bl_naira(v_div) || ' for ' || pos.qty::bigint || ' shares. It is in your bank.', jsonb_build_object('market', m.id));
    end if;
    update invest_positions set last_at = v_now where id = pos.id;
    return;
  end if;
  if pos.kind not in ('transport', 'pos', 'flat') then return; end if;
  select * into pr from invest_products where id = pos.ref_id;
  if not found then return; end if;
  v_n := floor(extract(epoch from v_now - pos.last_at) / v_day)::int;
  if v_n < 1 then return; end if;
  v_cap := greatest(1, bl_inv_num('invest.event_days_cap', 365)::int);
  v_skip := greatest(0, v_n - v_cap);
  v_inc := pr.income_day * floor(pos.qty)::bigint;
  v_vac := (pos.state->>'vacant_until')::timestamptz;
  v_acc := pos.accrued + v_inc * v_skip;
  for i in 1 .. (v_n - v_skip) loop
    v_ds := pos.last_at + make_interval(secs => (v_skip + i - 1) * v_day);
    if v_vac is null or v_ds >= v_vac then v_acc := v_acc + v_inc; end if;
    for ev in select key, value from jsonb_each(pr.events) loop
      if bl_inv_roll((ev.value->>'chance_pct')::numeric) then
        v_loss := 0;
        case ev.value->>'loss_of'
          when 'vacancy' then
            v_vac := v_ds + make_interval(secs => coalesce((ev.value->>'span_days')::numeric, 30) * v_day);
          when 'unit' then
            v_loss := floor(pos.cost * coalesce((ev.value->>'loss_pct')::numeric, 0) / 100)::bigint;
          when 'income' then
            v_loss := floor(v_inc * coalesce((ev.value->>'loss_pct')::numeric, 0) / 100)::bigint;
          else null;
        end case;
        v_acc := v_acc - v_loss;
        v_lost := v_lost + v_loss; v_cnt := v_cnt + 1;
        if v_cnt <= 5 then
          v_msg := v_msg || case when v_msg = '' then '' else ' ' end || coalesce(ev.value->>'label', ev.key) || case when v_loss > 0 then ' (−' || bl_naira(v_loss) || ').' else '.' end;
          perform bl_inv_log(pos.user_id, 'event', pr.id, coalesce(ev.value->>'label', ev.key), -v_loss, -v_loss, jsonb_build_object('event', ev.key));
        end if;
      end if;
    end loop;
  end loop;
  v_state := case when v_vac is null then pos.state else jsonb_set(pos.state, '{vacant_until}', to_jsonb(v_vac)) end;
  update invest_positions set accrued = v_acc, last_at = pos.last_at + make_interval(secs => v_n * v_day), state = v_state where id = pos.id;
  if v_cnt > 0 then
    perform bl_event(pos.user_id, 'invest', pr.name || ': trouble', v_msg, jsonb_build_object('product', pr.id, 'events', v_cnt, 'lost', v_lost));
  end if;
end $$;

create or replace function public.bl_inv_settle(p_uid uuid) returns void
language plpgsql set search_path = public as $$
declare r record;
begin
  for r in select id from invest_positions where user_id = p_uid and kind in ('stock', 'transport', 'pos', 'flat') order by id loop
    perform bl_inv_settle_pos(r.id);
  end loop;
end $$;

-- One source of truth for a position's numbers: value (mark to model), exit_value (what you get if you leave now),
-- fee, forfeited interest, day_change, collectable, ready. All bigint naira.
create or replace function public.bl_inv_calc(p public.invest_positions) returns jsonb
language plpgsql set search_path = public as $$
declare
  pr invest_products; m invest_markets;
  v_now timestamptz := bl_now(); D numeric := bl_inv_day();
  v_val bigint := 0; v_exit bigint := 0; v_fee bigint := 0; v_forfeit bigint := 0; v_day bigint := 0; v_coll bigint := 0;
  v_ready boolean := false; v_matured boolean := false; v_name text := p.ref_id; v_icon text := '💰'; v_risk text := 'safe';
  v_note text := ''; v_price numeric; v_chart text := 'line'; v_market text; v_rate numeric := 0;
  v_el numeric; v_term numeric; v_int bigint; v_f numeric; v_f0 numeric; v_prog numeric; v_gain numeric; v_asset bigint; v_age numeric;
  v_pending bigint; v_cyc numeric; v_secs numeric; v_vac timestamptz;
begin
  select * into pr from invest_products where id = p.ref_id;
  if found then
    v_name := pr.name; v_icon := pr.icon; v_risk := pr.risk; v_market := pr.market_id;
  else
    select * into m from invest_markets where id = p.ref_id;
    if found then v_name := m.name; v_icon := m.icon; v_risk := m.risk; v_market := m.id; end if;
  end if;

  if p.kind in ('savings', 'mmf') then
    v_rate := pr.rate_pct;
    v_int := p.accrued + bl_inv_interest(p.qty, pr.rate_pct, extract(epoch from v_now - p.last_at));
    v_val := floor(p.qty)::bigint + v_int; v_exit := v_val;
    v_day := bl_inv_interest(p.qty, pr.rate_pct, 86400);
    v_note := 'Interest ' || bl_naira(v_int) || ' so far. Withdraw any time.';
  elsif p.kind in ('safelock', 'fd', 'tbill') then
    v_rate := coalesce((p.state->>'rate_pct')::numeric, pr.rate_pct);
    v_term := extract(epoch from p.matures_at - p.opened_at);
    v_el := least(v_term, greatest(0, extract(epoch from v_now - p.opened_at)));
    v_int := bl_inv_interest(p.qty, v_rate, v_el);
    v_matured := v_now >= p.matures_at;
    v_val := floor(p.qty)::bigint + v_int;
    if v_matured then
      v_exit := v_val; v_ready := true; v_note := 'Matured. Collect principal and interest.';
    elsif p.kind = 'tbill' then
      v_fee := ceil(v_val * pr.exit_fee_pct / 100)::bigint; v_exit := v_val - v_fee;
      v_note := 'Sell early: ' || pr.exit_fee_pct || '% fee, you keep interest earned.';
    elsif pr.forfeits_interest then
      v_forfeit := v_int; v_exit := floor(p.qty)::bigint;
      v_note := 'Break early and you lose all ' || bl_naira(v_int) || ' interest.';
    else
      v_exit := v_val;
    end if;
    v_day := case when v_matured then 0 else bl_inv_interest(p.qty, v_rate, least(86400, v_term)) end;
  elsif p.kind = 'bond' then
    v_rate := pr.rate_pct;
    select * into m from invest_markets where id = pr.market_id;
    v_price := bl_inv_price(m.id); v_f := v_price / m.base_price;
    v_f0 := bl_inv_price(m.id, greatest(p.opened_at, v_now - interval '24 hours')) / m.base_price;
    v_int := p.accrued + bl_inv_interest(p.qty, pr.rate_pct, extract(epoch from v_now - p.last_at));
    v_asset := floor(p.qty * v_f)::bigint;
    v_val := v_asset + v_int;
    v_fee := ceil(v_asset * pr.exit_fee_pct / 100)::bigint;
    v_exit := v_val - v_fee;
    v_day := floor(p.qty * (v_f - v_f0))::bigint + bl_inv_interest(p.qty, pr.rate_pct, 86400);
    v_chart := 'market'; v_note := 'Coupon ' || bl_naira(v_int) || ' earned. Sells at market price.';
  elsif p.kind in ('stock', 'crypto', 'land') then
    select * into m from invest_markets where id = p.ref_id;
    v_price := bl_inv_price(m.id);
    v_asset := floor(p.qty * v_price)::bigint;
    v_val := v_asset; v_fee := ceil(v_asset * m.fee_pct / 100)::bigint; v_exit := v_val - v_fee;
    v_day := floor(p.qty * (v_price - bl_inv_price(m.id, greatest(p.opened_at, v_now - interval '24 hours'))))::bigint;
    v_chart := 'market';
    v_note := case p.kind when 'land' then 'Selling costs ' || m.fee_pct || '% agent fee.' else 'Selling costs ' || m.fee_pct || '% broker fee.' end;
  elsif p.kind = 'farm' then
    v_cyc := extract(epoch from p.matures_at - p.opened_at);
    v_prog := least(1, greatest(0, extract(epoch from v_now - p.opened_at) / greatest(1, v_cyc)));
    v_gain := coalesce((p.state->>'gain_pct')::numeric, 0);
    v_val := floor(p.cost * (1 + v_gain / 100 * v_prog))::bigint;
    v_ready := v_now >= p.matures_at;
    if v_ready then
      v_coll := floor(p.cost * (1 + v_gain / 100))::bigint; v_exit := 0;
      v_note := 'Ready to harvest (before any risk events).';
    else
      v_exit := floor(p.cost * pr.resale_pct / 100)::bigint;
      v_day := floor(p.cost * v_gain / 100 * 86400 / greatest(1, v_cyc))::bigint;
      v_note := 'Selling now returns ' || pr.resale_pct || '% and loses this cycle.';
    end if;
    v_rate := v_gain;
  elsif p.kind in ('transport', 'pos', 'flat') then
    v_age := greatest(0, extract(epoch from v_now - p.opened_at)) / bl_inv_year();
    if p.kind = 'flat' then
      select * into m from invest_markets where id = pr.market_id;
      v_f := bl_inv_price(m.id) / m.base_price; v_f0 := coalesce((p.state->>'f0')::numeric, 1);
      v_asset := floor(p.cost * v_f / v_f0)::bigint;
      v_fee := ceil(v_asset * pr.exit_fee_pct / 100)::bigint;
      v_chart := 'market';
    else
      v_asset := floor(p.cost * greatest(pr.resale_floor_pct, pr.resale_pct - pr.depr_pct_year * v_age) / 100)::bigint;
    end if;
    v_vac := (p.state->>'vacant_until')::timestamptz;
    v_secs := least(greatest(0, extract(epoch from v_now - p.last_at)), D);
    v_pending := floor(pr.income_day * p.qty * v_secs / D)::bigint;
    if v_vac is not null and v_vac > v_now then v_pending := 0; end if;
    v_val := v_asset + p.accrued + v_pending;
    v_exit := greatest(0, v_asset - v_fee + p.accrued + v_pending);
    v_coll := greatest(0, p.accrued);
    v_day := case when v_vac is not null and v_vac > v_now then 0 else pr.income_day * floor(p.qty)::bigint end;
    v_note := case when v_vac is not null and v_vac > v_now then 'Empty right now. No rent until a new tenant comes.' else 'Earns ' || bl_naira(pr.income_day * floor(p.qty)::bigint) || ' per day.' end;
  end if;
  v_val := greatest(0, v_val);
  return jsonb_build_object(
    'id', p.id, 'ref_id', p.ref_id, 'kind', p.kind, 'name', v_name, 'icon', v_icon, 'risk', v_risk,
    'qty', p.qty, 'cost', p.cost, 'value', v_val, 'profit', v_val - p.cost,
    'exit_value', v_exit, 'exit_fee', v_fee, 'forfeit', v_forfeit, 'day_change', v_day,
    'collectable', v_coll, 'ready', v_ready, 'matured', v_matured, 'note', v_note, 'chart', v_chart, 'market_id', v_market,
    'price', v_price, 'rate_pct', v_rate, 'accrued', p.accrued,
    'opened_at', p.opened_at, 'matures_at', p.matures_at, 'locked', (p.kind in ('safelock', 'fd') and not v_matured),
    'vacant_until', p.state->>'vacant_until', 'gain_pct', p.state->'gain_pct', 'last_at', p.last_at);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.invest_market_series(p_market text, p_points int default 120, p_hours int default 168) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me();
begin
  if not exists (select 1 from invest_markets where id = p_market and active) then
    raise exception 'Market no dey.' using errcode = 'P0001', hint = 'bad_market';
  end if;
  return jsonb_build_object('market', p_market, 'price', bl_inv_price(p_market),
    'points', bl_inv_series(p_market, least(greatest(coalesce(p_points, 120), 8), 400), least(greatest(coalesce(p_hours, 168), 1), 2160)));
end $$;

create or replace function public.invest_overview() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me();
  v_pts int := bl_inv_num('invest.spark_points', 48)::int;
  v_prod jsonb; v_mkts jsonb; v_pos jsonb; v_sum jsonb; v_log jsonb;
  v_inv bigint; v_val bigint; v_day bigint; v_real bigint;
begin
  perform bl_inv_assert_ok(v_me, false);
  perform bl_inv_settle(v_me.id);
  select * into v_me from profiles where id = v_me.id;
  delete from invest_land_deals where user_id = v_me.id and status <> 'pending' and created_at < bl_now() - interval '2 days';

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'kind', p.kind, 'name', p.name, 'icon', p.icon, 'blurb', p.blurb, 'risk', p.risk, 'rate_pct', p.rate_pct,
      'term_days', p.term_days, 'exit_fee_pct', p.exit_fee_pct, 'forfeits_interest', p.forfeits_interest,
      'unit_price', case when p.kind = 'flat' then ceil(p.unit_price * bl_inv_price(p.market_id) / (select base_price from invest_markets where id = p.market_id))::bigint else p.unit_price end,
      'market_id', p.market_id, 'min_amount', p.min_amount, 'max_amount', p.max_amount, 'cycle_days', p.cycle_days,
      'gain_min_pct', p.gain_min_pct, 'gain_max_pct', p.gain_max_pct, 'income_day', p.income_day, 'resale_pct', p.resale_pct,
      'depr_pct_year', p.depr_pct_year, 'events', p.events, 'sort', p.sort) order by p.sort, p.id), '[]'::jsonb)
    into v_prod from invest_products p where p.active;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', k.id, 'kind', k.kind, 'name', k.name, 'icon', k.icon, 'blurb', k.blurb, 'risk', k.risk, 'ticker', k.ticker,
      'price', bl_inv_price(k.id), 'change_24h', bl_inv_change(k.id, 24), 'change_7d', bl_inv_change(k.id, 168),
      'fee_pct', k.fee_pct, 'community_pct', k.community_pct, 'levy_chance_pct', k.levy_chance_pct,
      'levy_min_pct', k.levy_min_pct, 'levy_max_pct', k.levy_max_pct, 'dividend_yield_pct', k.dividend_yield_pct,
      'drift_pct_year', k.drift_pct_year, 'min_qty', k.min_qty, 'max_qty', k.max_qty,
      'spark', bl_inv_series(k.id, v_pts, 168), 'sort', k.sort) order by k.sort, k.id), '[]'::jsonb)
    into v_mkts from invest_markets k where k.active;

  select coalesce(jsonb_agg(bl_inv_calc(x) order by x.id), '[]'::jsonb) into v_pos from invest_positions x where x.user_id = v_me.id;
  select coalesce(sum(cost), 0), coalesce(sum((c->>'value')::bigint), 0), coalesce(sum((c->>'day_change')::bigint), 0)
    into v_inv, v_val, v_day
    from invest_positions x, lateral bl_inv_calc(x) c where x.user_id = v_me.id;
  select coalesce(sum(profit), 0) into v_real from invest_log where user_id = v_me.id and profit is not null;
  v_sum := jsonb_build_object('invested', v_inv, 'value', v_val, 'unrealized', v_val - v_inv, 'realized', v_real,
                              'profit', v_val - v_inv + v_real, 'today', v_day,
                              'count', (select count(*) from invest_positions where user_id = v_me.id));
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'at', l.at, 'kind', l.kind, 'label', l.label, 'amount', l.amount, 'profit', l.profit) order by l.id desc), '[]'::jsonb)
    into v_log from (select * from invest_log where user_id = v_me.id order by id desc limit 30) l;
  return jsonb_build_object('cash', v_me.cash, 'bank', v_me.bank, 'year_days', bl_inv_num('invest.year_days', 30),
    'day_seconds', bl_inv_day(), 'now', bl_now(), 'enabled', coalesce((select (value #>> '{}')::boolean from game_config where key = 'invest.enabled'), true),
    'summary', v_sum, 'products', v_prod, 'markets', v_mkts, 'positions', v_pos, 'log', v_log,
    'pending_deal', (select to_jsonb(d) from invest_land_deals d where d.user_id = v_me.id and d.status = 'pending' and d.expires_at > bl_now() order by d.id desc limit 1));
end $$;

-- Save / safe invest / medium units: p_amount = naira (savings, safelock, mmf, fd, tbill, bond) or units (farm, transport, pos, flat).
create or replace function public.invest_buy(p_product text, p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me();
  pr invest_products; m invest_markets; pos invest_positions;
  v_day numeric := bl_inv_day(); v_now timestamptz := bl_now();
  v_units boolean; v_cost numeric; v_f numeric := 1; v_unit bigint; v_label text; v_bank bigint; v_rcpt jsonb := '{}'::jsonb; v_add numeric;
begin
  perform bl_inv_assert_ok(v_me, true);
  select * into pr from invest_products where id = p_product and active;
  if not found then
    raise exception 'That product no dey.' using errcode = 'P0001', hint = 'bad_product';
  end if;
  v_units := pr.kind in ('farm', 'transport', 'pos', 'flat');
  perform bl_inv_amount(p_amount, pr.min_amount, pr.max_amount, case when v_units then pr.name || ' (units)' else pr.name end);
  if v_units then
    if pr.kind = 'flat' then
      select * into m from invest_markets where id = pr.market_id;
      v_f := bl_inv_price(m.id) / m.base_price;
    end if;
    v_unit := ceil(pr.unit_price * v_f)::bigint;
    v_cost := v_unit::numeric * p_amount;
  else
    v_cost := p_amount;
  end if;
  perform bl_inv_need_bank(v_me, v_cost);
  v_label := case when pr.kind in ('savings', 'safelock') then 'Save: ' else 'Invest: ' end || pr.name
             || case when v_units and p_amount > 1 then ' ×' || p_amount else '' end;

  if pr.kind in ('savings', 'mmf', 'bond') then
    v_add := p_amount;
    if pr.kind = 'bond' then
      select * into m from invest_markets where id = pr.market_id;
      v_add := round(p_amount / (bl_inv_price(m.id) / m.base_price), 4);
    end if;
    select * into pos from invest_positions where user_id = v_me.id and ref_id = pr.id for update;
    if found then
      update invest_positions
         set accrued = accrued + bl_inv_interest(qty, pr.rate_pct, extract(epoch from v_now - last_at)), last_at = v_now,
             qty = qty + v_add, cost = cost + p_amount
       where id = pos.id returning * into pos;
    else
      insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at)
      values (v_me.id, pr.id, pr.kind, v_add, p_amount, v_now, v_now) returning * into pos;
    end if;
  elsif pr.kind in ('safelock', 'fd', 'tbill') then
    insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at, matures_at, state)
    values (v_me.id, pr.id, pr.kind, p_amount, p_amount, v_now, v_now, v_now + make_interval(secs => pr.term_days * v_day),
            jsonb_build_object('rate_pct', pr.rate_pct)) returning * into pos;
  elsif pr.kind = 'farm' then
    insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at, matures_at, state)
    values (v_me.id, pr.id, pr.kind, p_amount, v_cost::bigint, v_now, v_now, v_now + make_interval(secs => pr.cycle_days * v_day),
            jsonb_build_object('gain_pct', round((pr.gain_min_pct + (pr.gain_max_pct - pr.gain_min_pct) * bl_rand())::numeric, 1), 'cycle', 1))
    returning * into pos;
  else
    insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at, state)
    values (v_me.id, pr.id, pr.kind, p_amount, v_cost::bigint, v_now, v_now, jsonb_build_object('f0', v_f)) returning * into pos;
  end if;

  v_bank := bl_add_money(v_me.id, 'bank', -v_cost::bigint, 'invest_buy', jsonb_build_object('label', v_label, 'product', pr.id));
  perform bl_inv_log(v_me.id, 'buy', pr.id, v_label, -v_cost::bigint, null, jsonb_build_object('units', case when v_units then p_amount end));
  v_rcpt := bl_receipt_issue(v_me.id, 'invest', pr.name || case when v_units and p_amount > 1 then ' ×' || p_amount else '' end,
                             v_cost::bigint, 'Benin Life Invest', jsonb_build_object('product', pr.id));
  return jsonb_build_object('message', case when pr.kind in ('savings', 'safelock') then 'Saved ' else 'Invested ' end || bl_naira(v_cost) || ' in ' || pr.name || '.',
                            'amount', v_cost::bigint, 'bank', v_bank, 'position', bl_inv_calc(pos)) || v_rcpt;
end $$;

-- Take money out. Pooled (savings, mmf, bond): p_amount = naira to take (null = all). Lots (safelock, fd, tbill, farm, transport,
-- pos, flat): the whole lot, p_amount ignored. Early-exit rules come from bl_inv_calc().
create or replace function public.invest_withdraw(p_position bigint, p_amount bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me();
  pos invest_positions; pr invest_products; c jsonb;
  v_pay bigint; v_profit bigint; v_label text; v_bank bigint; v_tot numeric; v_take_acc bigint; v_take_pr bigint;
  v_frac numeric; v_rel bigint; v_val bigint; v_int bigint;
begin
  perform bl_inv_assert_ok(v_me, false);
  select * into pos from invest_positions where id = p_position and user_id = v_me.id for update;
  if not found then
    raise exception 'That holding no dey.' using errcode = 'P0001', hint = 'bad_position';
  end if;
  if pos.kind in ('stock', 'crypto', 'land') then
    raise exception 'Sell this one from its market page.' using errcode = 'P0001', hint = 'bad_position';
  end if;
  perform bl_inv_settle_pos(pos.id);
  select * into pos from invest_positions where id = p_position;
  select * into pr from invest_products where id = pos.ref_id;
  c := bl_inv_calc(pos);

  if pos.kind in ('savings', 'mmf') then
    v_int := pos.accrued + bl_inv_interest(pos.qty, pr.rate_pct, extract(epoch from bl_now() - pos.last_at));
    v_tot := floor(pos.qty) + v_int;
    v_pay := coalesce(p_amount, v_tot::bigint);
    if v_pay < 1 then raise exception 'Put a whole number, abeg.' using errcode = 'P0001', hint = 'bad_amount'; end if;
    if v_pay > v_tot then
      raise exception 'You only have % there.', bl_naira(v_tot) using errcode = 'P0001', hint = 'bad_amount';
    end if;
    v_take_acc := least(v_pay, v_int); v_take_pr := v_pay - v_take_acc;
    v_profit := v_take_acc;
    if v_pay = v_tot then
      delete from invest_positions where id = pos.id;
    else
      update invest_positions set accrued = v_int - v_take_acc, last_at = bl_now(), qty = qty - v_take_pr, cost = greatest(0, cost - v_take_pr) where id = pos.id;
    end if;
    v_label := 'Save: withdraw ' || pr.name;
    if pos.kind = 'mmf' then v_label := 'Invest: withdraw ' || pr.name; end if;
  elsif pos.kind = 'bond' then
    v_val := (c->>'exit_value')::bigint;
    v_pay := coalesce(p_amount, v_val);
    if v_pay < 1 then raise exception 'Put a whole number, abeg.' using errcode = 'P0001', hint = 'bad_amount'; end if;
    if v_pay > v_val then
      raise exception 'You can take at most % now.', bl_naira(v_val) using errcode = 'P0001', hint = 'bad_amount';
    end if;
    v_frac := v_pay::numeric / v_val;
    v_rel := floor(pos.cost * v_frac)::bigint;
    v_profit := v_pay - v_rel;
    if v_pay = v_val then
      delete from invest_positions where id = pos.id;
    else
      v_int := pos.accrued + bl_inv_interest(pos.qty, pr.rate_pct, extract(epoch from bl_now() - pos.last_at));
      update invest_positions set qty = qty - qty * v_frac, accrued = v_int - floor(v_int * v_frac)::bigint,
             last_at = bl_now(), cost = greatest(0, cost - v_rel) where id = pos.id;
    end if;
    v_label := 'Invest: sold ' || pr.name;
  else
    if pos.kind = 'farm' and (c->>'ready')::boolean then
      raise exception 'The harvest is ready. Collect it first.' using errcode = 'P0001', hint = 'ready';
    end if;
    v_pay := (c->>'exit_value')::bigint;
    v_profit := v_pay - pos.cost;
    delete from invest_positions where id = pos.id;
    v_label := case
      when pos.kind in ('safelock') then 'Save: ' || case when (c->>'matured')::boolean then 'matured ' else 'broke ' end || pr.name
      when pos.kind = 'fd' then 'Invest: ' || case when (c->>'matured')::boolean then 'matured ' else 'broke ' end || pr.name
      when pos.kind = 'tbill' then 'Invest: ' || case when (c->>'matured')::boolean then 'matured ' else 'sold early ' end || pr.name
      else 'Invest: sold ' || pr.name end;
  end if;
  if v_pay > 0 then
    v_bank := bl_add_money(v_me.id, 'bank', v_pay, 'invest_sell', jsonb_build_object('label', v_label, 'product', pr.id));
  else
    v_bank := v_me.bank;
  end if;
  perform bl_inv_log(v_me.id, 'sell', pr.id, v_label, v_pay, v_profit,
                     jsonb_build_object('fee', c->'exit_fee', 'forfeited', c->'forfeit', 'early', not coalesce((c->>'matured')::boolean, true)));
  return jsonb_build_object('message', v_label || ': ' || bl_naira(v_pay) || ' is back in your bank.'
                              || case when (c->>'forfeit')::bigint > 0 then ' You lost ' || bl_naira((c->>'forfeit')::bigint) || ' interest.' else '' end
                              || case when (c->>'exit_fee')::bigint > 0 then ' Fee ' || bl_naira((c->>'exit_fee')::bigint) || '.' else '' end,
                            'payout', v_pay, 'profit', v_profit, 'fee', (c->>'exit_fee')::bigint, 'forfeited', (c->>'forfeit')::bigint,
                            'matured', (c->>'matured')::boolean, 'bank', v_bank);
end $$;

-- Harvest a farm (rolls the cycle's risk events; optionally re-invest = start the next cycle) or collect transport / POS / flat income.
create or replace function public.invest_collect(p_position bigint, p_reinvest boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me();
  pos invest_positions; pr invest_products; c jsonb; ev record;
  v_gross bigint; v_pay bigint; v_mult numeric := 1; v_hits jsonb := '[]'::jsonb; v_bank bigint; v_label text; v_net bigint;
  v_now timestamptz := bl_now(); v_gain numeric;
begin
  perform bl_inv_assert_ok(v_me, false);
  select * into pos from invest_positions where id = p_position and user_id = v_me.id for update;
  if not found then
    raise exception 'That holding no dey.' using errcode = 'P0001', hint = 'bad_position';
  end if;
  perform bl_inv_settle_pos(pos.id);
  select * into pos from invest_positions where id = p_position;
  select * into pr from invest_products where id = pos.ref_id;
  c := bl_inv_calc(pos);
  if pos.kind = 'farm' then
    if v_now < pos.matures_at then
      raise exception 'Not ready yet. Harvest in about % minutes.', ceil(extract(epoch from pos.matures_at - v_now) / 60)::int
        using errcode = 'P0001', hint = 'not_ready';
    end if;
    v_gross := floor(pos.cost * (1 + coalesce((pos.state->>'gain_pct')::numeric, 0) / 100))::bigint;
    for ev in select key, value from jsonb_each(pr.events) loop
      if coalesce(ev.value->>'loss_of', 'cycle') = 'cycle' and bl_inv_roll((ev.value->>'chance_pct')::numeric) then
        v_mult := v_mult * (1 - least(100, coalesce((ev.value->>'loss_pct')::numeric, 0)) / 100);
        v_hits := v_hits || jsonb_build_array(jsonb_build_object('id', ev.key, 'label', ev.value->>'label', 'loss_pct', (ev.value->>'loss_pct')::numeric));
      end if;
    end loop;
    v_pay := floor(v_gross * v_mult)::bigint;
    v_label := 'Harvest: ' || lower(pr.name);
    if p_reinvest then
      v_net := v_pay - pos.cost;                       -- profit paid out (or shortfall topped up) while the capital stays in the farm
      if v_net < 0 then perform bl_inv_need_bank(v_me, -v_net); end if;
      v_gain := round((pr.gain_min_pct + (pr.gain_max_pct - pr.gain_min_pct) * bl_rand())::numeric, 1);
      update invest_positions set opened_at = v_now, last_at = v_now, matures_at = v_now + make_interval(secs => pr.cycle_days * bl_inv_day()),
             state = jsonb_build_object('gain_pct', v_gain, 'cycle', coalesce((state->>'cycle')::int, 1) + 1) where id = pos.id;
      if v_net <> 0 then
        v_bank := bl_add_money(v_me.id, 'bank', v_net, case when v_net < 0 then 'invest_buy' else 'invest_income' end, jsonb_build_object('label', v_label || ' (re-invested)', 'product', pr.id));
      else
        v_bank := v_me.bank;
      end if;
    else
      delete from invest_positions where id = pos.id;
      v_bank := bl_add_money(v_me.id, 'bank', v_pay, 'invest_income', jsonb_build_object('label', v_label, 'product', pr.id));
    end if;
    perform bl_inv_log(v_me.id, 'harvest', pr.id, v_label, case when p_reinvest then v_net else v_pay end, v_pay - pos.cost,
                       jsonb_build_object('gross', v_gross, 'payout', v_pay, 'events', v_hits, 'reinvest', p_reinvest));
    return jsonb_build_object('message', case when jsonb_array_length(v_hits) > 0
                                then (v_hits->0->>'label') || '. Harvest paid ' || bl_naira(v_pay) || ' (expected ' || bl_naira(v_gross) || ').'
                                else 'Good harvest! ' || bl_naira(v_pay) || ' for ' || pr.name || '.' end,
                              'payout', v_pay, 'expected', v_gross, 'profit', v_pay - pos.cost, 'events', v_hits, 'reinvested', p_reinvest, 'bank', v_bank);
  elsif pos.kind in ('transport', 'pos', 'flat') then
    v_pay := greatest(0, pos.accrued);
    if v_pay < 1 then
      raise exception 'Nothing to collect yet.' using errcode = 'P0001', hint = 'nothing';
    end if;
    update invest_positions set accrued = accrued - v_pay where id = pos.id;
    v_label := 'Income: ' || pr.name;
    v_bank := bl_add_money(v_me.id, 'bank', v_pay, 'invest_income', jsonb_build_object('label', v_label, 'product', pr.id));
    perform bl_inv_log(v_me.id, 'income', pr.id, v_label, v_pay, v_pay);
    return jsonb_build_object('message', 'Collected ' || bl_naira(v_pay) || ' from ' || pr.name || '.', 'payout', v_pay, 'profit', v_pay, 'bank', v_bank);
  end if;
  raise exception 'Nothing to collect here.' using errcode = 'P0001', hint = 'nothing';
end $$;

-- Stocks + crypto: buy p_qty (whole shares / fractional coins to 8 decimals). Broker fee on top, own ledger row.
create or replace function public.invest_market_buy(p_market text, p_qty numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me();
  m invest_markets; pos invest_positions;
  v_q numeric; v_price numeric; v_gross bigint; v_fee bigint; v_total numeric; v_bank bigint; v_now timestamptz := bl_now(); v_rcpt jsonb;
  v_label text;
begin
  perform bl_inv_assert_ok(v_me, true);
  select * into m from invest_markets where id = p_market and active and kind in ('stock', 'crypto');
  if not found then
    raise exception 'That market no dey.' using errcode = 'P0001', hint = 'bad_market';
  end if;
  if p_qty is null or p_qty <= 0 then
    raise exception 'Put how many you want, abeg.' using errcode = 'P0001', hint = 'bad_amount';
  end if;
  v_q := case when m.kind = 'stock' then floor(p_qty) else trunc(p_qty, 8) end;
  if v_q < m.min_qty then
    raise exception 'Minimum is % %.', m.min_qty::text, m.ticker using errcode = 'P0001', hint = 'bad_amount';
  end if;
  if v_q > m.max_qty then
    raise exception 'Maximum at once is % %.', m.max_qty::text, m.ticker using errcode = 'P0001', hint = 'bad_amount';
  end if;
  v_price := bl_inv_price(m.id);
  v_total := ceil(v_q * v_price);
  if v_total < 1 then
    raise exception 'That is too small to buy.' using errcode = 'P0001', hint = 'bad_amount';
  end if;
  v_gross := v_total::bigint;
  v_fee := ceil(v_gross * m.fee_pct / 100)::bigint;
  perform bl_inv_need_bank(v_me, v_gross + v_fee);
  select * into pos from invest_positions where user_id = v_me.id and ref_id = m.id for update;
  if found then
    perform bl_inv_settle_pos(pos.id);
    update invest_positions set qty = qty + v_q, cost = cost + v_gross + v_fee, last_at = v_now where id = pos.id returning * into pos;
  else
    insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at)
    values (v_me.id, m.id, m.kind, v_q, v_gross + v_fee, v_now, v_now) returning * into pos;
  end if;
  v_label := 'Invest: ' || case when m.kind = 'stock' then 'NGX ' else 'Crypto ' end || m.name || ' ×' || trim(trailing '.' from trim(trailing '0' from v_q::text));
  v_bank := bl_add_money(v_me.id, 'bank', -v_gross, 'invest_buy', jsonb_build_object('label', v_label, 'market', m.id));
  if v_fee > 0 then
    v_bank := bl_add_money(v_me.id, 'bank', -v_fee, 'invest_fee', jsonb_build_object('label', 'Invest: broker fee · ' || m.name, 'market', m.id));
  end if;
  perform bl_inv_log(v_me.id, 'buy', m.id, v_label, -(v_gross + v_fee), null, jsonb_build_object('qty', v_q, 'price', v_price, 'fee', v_fee));
  v_rcpt := bl_receipt_issue(v_me.id, 'invest', m.name || ' ×' || trim(trailing '.' from trim(trailing '0' from v_q::text)), v_gross + v_fee,
                             case when m.kind = 'stock' then 'Benin Life Stockbrokers' else 'Benin Life Crypto Desk' end, jsonb_build_object('market', m.id));
  return jsonb_build_object('message', 'Bought ' || trim(trailing '.' from trim(trailing '0' from v_q::text)) || ' ' || m.ticker || ' at ' || bl_naira(v_price) || '.',
                            'qty', v_q, 'price', v_price, 'gross', v_gross, 'fee', v_fee, 'total', v_gross + v_fee, 'bank', v_bank,
                            'position', bl_inv_calc(pos)) || v_rcpt;
end $$;

create or replace function public.invest_market_sell(p_market text, p_qty numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me();
  m invest_markets; pos invest_positions;
  v_q numeric; v_price numeric; v_gross bigint; v_fee bigint; v_rel bigint; v_bank bigint; v_label text;
begin
  perform bl_inv_assert_ok(v_me, false);
  select * into m from invest_markets where id = p_market and kind in ('stock', 'crypto');
  if not found then
    raise exception 'That market no dey.' using errcode = 'P0001', hint = 'bad_market';
  end if;
  select * into pos from invest_positions where user_id = v_me.id and ref_id = m.id for update;
  if not found then
    raise exception 'You no get any % to sell.', m.ticker using errcode = 'P0001', hint = 'bad_position';
  end if;
  perform bl_inv_settle_pos(pos.id);
  select * into pos from invest_positions where id = pos.id;
  v_q := case when p_qty is null then pos.qty when m.kind = 'stock' then floor(p_qty) else trunc(p_qty, 8) end;
  if v_q <= 0 then
    raise exception 'Put how many you want to sell.' using errcode = 'P0001', hint = 'bad_amount';
  end if;
  if v_q > pos.qty then
    raise exception 'You only have % %.', trim(trailing '.' from trim(trailing '0' from pos.qty::text)), m.ticker using errcode = 'P0001', hint = 'bad_amount';
  end if;
  v_price := bl_inv_price(m.id);
  v_gross := floor(v_q * v_price)::bigint;
  v_fee := ceil(v_gross * m.fee_pct / 100)::bigint;
  v_rel := case when v_q = pos.qty then pos.cost else floor(pos.cost * v_q / pos.qty)::bigint end;
  if v_q = pos.qty then
    delete from invest_positions where id = pos.id;
  else
    update invest_positions set qty = qty - v_q, cost = greatest(0, cost - v_rel) where id = pos.id;
  end if;
  v_label := 'Invest: sold ' || case when m.kind = 'stock' then 'NGX ' else 'Crypto ' end || m.name || ' ×' || trim(trailing '.' from trim(trailing '0' from v_q::text));
  v_bank := bl_add_money(v_me.id, 'bank', v_gross, 'invest_sell', jsonb_build_object('label', v_label, 'market', m.id));
  if v_fee > 0 then
    v_bank := bl_add_money(v_me.id, 'bank', -v_fee, 'invest_fee', jsonb_build_object('label', 'Invest: broker fee · ' || m.name, 'market', m.id));
  end if;
  perform bl_inv_log(v_me.id, 'sell', m.id, v_label, v_gross - v_fee, v_gross - v_fee - v_rel, jsonb_build_object('qty', v_q, 'price', v_price, 'fee', v_fee));
  return jsonb_build_object('message', 'Sold ' || trim(trailing '.' from trim(trailing '0' from v_q::text)) || ' ' || m.ticker || ' at ' || bl_naira(v_price) || '. ' || bl_naira(v_gross - v_fee) || ' in your bank.',
                            'qty', v_q, 'price', v_price, 'gross', v_gross, 'fee', v_fee, 'payout', v_gross - v_fee,
                            'profit', v_gross - v_fee - v_rel, 'bank', v_bank);
end $$;

-- Land: price breakdown for p_plots plots (read only; the levy is rolled when the deal opens).
create or replace function public.invest_land_quote(p_area text, p_plots int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); m invest_markets; v_pp bigint; v_sub numeric; v_agent bigint; v_comm bigint;
begin
  select * into m from invest_markets where id = p_area and kind = 'land' and active;
  if not found then
    raise exception 'That area no dey.' using errcode = 'P0001', hint = 'bad_market';
  end if;
  if p_plots is null or p_plots < 1 or p_plots > m.max_qty then
    raise exception 'Plots must be 1 to %.', m.max_qty::bigint using errcode = 'P0001', hint = 'bad_amount';
  end if;
  v_pp := bl_inv_price(m.id)::bigint;
  v_sub := v_pp::numeric * p_plots;
  v_agent := ceil(v_sub * m.fee_pct / 100)::bigint;
  v_comm := ceil(v_sub * m.community_pct / 100)::bigint;
  return jsonb_build_object('area', m.id, 'name', m.name, 'plots', p_plots, 'plot_price', v_pp, 'subtotal', v_sub::bigint,
    'agent_fee_pct', m.fee_pct, 'agent_fee', v_agent, 'community_pct', m.community_pct, 'community', v_comm,
    'total', v_sub::bigint + v_agent + v_comm, 'levy_chance_pct', m.levy_chance_pct,
    'levy_min', ceil(v_sub * m.levy_min_pct / 100)::bigint, 'levy_max', ceil(v_sub * m.levy_max_pct / 100)::bigint, 'bank', v_me.bank);
end $$;

-- Closes a land deal: money out (4 ledger rows), plots in. The caller holds the player lock.
create or replace function public.bl_inv_land_close(p_deal bigint) returns jsonb
language plpgsql set search_path = public as $$
declare
  d invest_land_deals; m invest_markets; pos invest_positions; v_total numeric; v_bank bigint; v_now timestamptz := bl_now(); v_rcpt jsonb;
  v_meta jsonb;
begin
  select * into d from invest_land_deals where id = p_deal for update;
  select * into m from invest_markets where id = d.area;
  v_total := d.subtotal::numeric + d.agent_fee + d.community + d.levy;
  v_meta := jsonb_build_object('area', m.id);
  v_bank := bl_add_money(d.user_id, 'bank', -d.subtotal, 'invest_buy', v_meta || jsonb_build_object('label', 'Land: ' || d.plots || ' plot' || case when d.plots > 1 then 's' else '' end || ' · ' || m.name));
  if d.agent_fee > 0 then
    v_bank := bl_add_money(d.user_id, 'bank', -d.agent_fee, 'invest_fee', v_meta || jsonb_build_object('label', 'Land: agent fee · ' || m.name));
  end if;
  if d.community > 0 then
    v_bank := bl_add_money(d.user_id, 'bank', -d.community, 'invest_fee', v_meta || jsonb_build_object('label', 'Land: community settlement · ' || m.name));
  end if;
  if d.levy > 0 then
    v_bank := bl_add_money(d.user_id, 'bank', -d.levy, 'invest_fee', v_meta || jsonb_build_object('label', 'Land: development levy · ' || m.name));
  end if;
  select * into pos from invest_positions where user_id = d.user_id and ref_id = m.id for update;
  if found then
    update invest_positions set qty = qty + d.plots, cost = cost + v_total::bigint where id = pos.id returning * into pos;
  else
    insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at)
    values (d.user_id, m.id, 'land', d.plots, v_total::bigint, v_now, v_now) returning * into pos;
  end if;
  update invest_land_deals set status = 'done', closed_at = v_now where id = d.id;
  perform bl_inv_log(d.user_id, 'buy', m.id, 'Land: ' || d.plots || ' plot(s) · ' || m.name, -v_total::bigint, null,
                     jsonb_build_object('plot_price', d.plot_price, 'agent_fee', d.agent_fee, 'community', d.community, 'levy', d.levy));
  v_rcpt := bl_receipt_issue(d.user_id, 'invest', d.plots || ' plot' || case when d.plots > 1 then 's' else '' end || ' of land, ' || m.name, v_total::bigint,
                             'Benin Land Agents', jsonb_build_object('area', m.id, 'levy', d.levy));
  return jsonb_build_object('status', 'done', 'deal_id', d.id, 'area', m.id, 'name', m.name, 'plots', d.plots, 'plot_price', d.plot_price,
    'subtotal', d.subtotal, 'agent_fee', d.agent_fee, 'community', d.community, 'levy', d.levy, 'total', v_total::bigint, 'bank', v_bank,
    'message', 'Land bought: ' || d.plots || ' plot' || case when d.plots > 1 then 's' else '' end || ' in ' || m.name || ' for ' || bl_naira(v_total) || '.',
    'position', bl_inv_calc(pos)) || v_rcpt;
end $$;

-- Open a land deal. Returns {status:'done'} or, when the community asks for an extra levy, {status:'levy', deal_id, levy, ...}
-- (nothing is charged until the player pays; walking away costs nothing but a short wait).
create or replace function public.invest_land_buy(p_area text, p_plots int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me();
  m invest_markets; q jsonb; v_levy bigint := 0; v_id bigint; v_now timestamptz := bl_now(); v_cd numeric; v_last timestamptz; v_pct numeric;
begin
  perform bl_inv_assert_ok(v_me, true);
  q := invest_land_quote(p_area, p_plots);
  select * into m from invest_markets where id = p_area;
  update invest_land_deals set status = 'expired', closed_at = v_now where user_id = v_me.id and status = 'pending' and expires_at <= v_now;
  if exists (select 1 from invest_land_deals where user_id = v_me.id and status = 'pending') then
    raise exception 'You still have a land deal open. Pay the levy or walk away first.' using errcode = 'P0001', hint = 'pending';
  end if;
  v_cd := bl_inv_num('invest.land_walk_cooldown_seconds', 30);
  select max(closed_at) into v_last from invest_land_deals where user_id = v_me.id and status = 'walked';
  if v_last is not null and v_cd > 0 and v_now < v_last + make_interval(secs => v_cd) then
    raise exception 'The community is still arguing. Wait about % seconds before you try again.', ceil(extract(epoch from v_last + make_interval(secs => v_cd) - v_now))::int
      using errcode = 'P0001', hint = 'cooldown';
  end if;
  perform bl_inv_need_bank(v_me, (q->>'total')::numeric);
  if bl_inv_roll(m.levy_chance_pct) then
    v_pct := m.levy_min_pct + (m.levy_max_pct - m.levy_min_pct) * bl_rand();
    v_levy := ceil((q->>'subtotal')::numeric * v_pct / 100)::bigint;
  end if;
  insert into invest_land_deals (user_id, area, plots, plot_price, subtotal, agent_fee, community, levy, created_at, expires_at)
  values (v_me.id, m.id, p_plots, (q->>'plot_price')::bigint, (q->>'subtotal')::bigint, (q->>'agent_fee')::bigint, (q->>'community')::bigint,
          v_levy, v_now, v_now + make_interval(mins => bl_inv_num('invest.land_deal_minutes', 10)::int))
  returning id into v_id;
  if v_levy = 0 then
    return bl_inv_land_close(v_id);
  end if;
  return q || jsonb_build_object('status', 'levy', 'deal_id', v_id, 'levy', v_levy, 'levy_pct', round(v_pct, 1),
    'total_with_levy', (q->>'total')::bigint + v_levy,
    'message', 'The omonile boys came back: they want ' || bl_naira(v_levy) || ' development levy before they sign. Pay it, or walk away and lose nothing.');
end $$;

create or replace function public.invest_land_levy(p_deal bigint, p_pay boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); d invest_land_deals; v_now timestamptz := bl_now();
begin
  perform bl_inv_assert_ok(v_me, false);
  select * into d from invest_land_deals where id = p_deal and user_id = v_me.id for update;
  if not found or d.status <> 'pending' then
    raise exception 'That deal don close.' using errcode = 'P0001', hint = 'bad_deal';
  end if;
  if not coalesce(p_pay, false) then
    update invest_land_deals set status = 'walked', closed_at = v_now where id = d.id;
    return jsonb_build_object('status', 'walked', 'message', 'You walked away. You lost nothing but time.', 'bank', v_me.bank);
  end if;
  if d.expires_at <= v_now then
    update invest_land_deals set status = 'expired', closed_at = v_now where id = d.id;
    raise exception 'The deal went cold. Start again.' using errcode = 'P0001', hint = 'expired';
  end if;
  perform bl_inv_assert_ok(v_me, true);
  perform bl_inv_need_bank(v_me, d.subtotal::numeric + d.agent_fee + d.community + d.levy);
  return bl_inv_land_close(d.id);
end $$;

create or replace function public.invest_land_sell(p_area text, p_plots int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me();
  m invest_markets; pos invest_positions; v_price numeric; v_gross bigint; v_fee bigint; v_rel bigint; v_bank bigint;
begin
  perform bl_inv_assert_ok(v_me, false);
  select * into m from invest_markets where id = p_area and kind = 'land';
  if not found then
    raise exception 'That area no dey.' using errcode = 'P0001', hint = 'bad_market';
  end if;
  select * into pos from invest_positions where user_id = v_me.id and ref_id = m.id for update;
  if not found then
    raise exception 'You no get plot for %.', m.name using errcode = 'P0001', hint = 'bad_position';
  end if;
  if p_plots is null or p_plots < 1 or p_plots > pos.qty then
    raise exception 'You have % plot(s) there.', pos.qty::bigint using errcode = 'P0001', hint = 'bad_amount';
  end if;
  v_price := bl_inv_price(m.id);
  v_gross := floor(p_plots * v_price)::bigint;
  v_fee := ceil(v_gross * m.fee_pct / 100)::bigint;
  v_rel := case when p_plots = pos.qty then pos.cost else floor(pos.cost * p_plots / pos.qty)::bigint end;
  if p_plots = pos.qty then
    delete from invest_positions where id = pos.id;
  else
    update invest_positions set qty = qty - p_plots, cost = greatest(0, cost - v_rel) where id = pos.id;
  end if;
  v_bank := bl_add_money(v_me.id, 'bank', v_gross, 'invest_sell', jsonb_build_object('label', 'Land: sold ' || p_plots || ' plot' || case when p_plots > 1 then 's' else '' end || ' · ' || m.name, 'area', m.id));
  if v_fee > 0 then
    v_bank := bl_add_money(v_me.id, 'bank', -v_fee, 'invest_fee', jsonb_build_object('label', 'Land: agent fee (sale) · ' || m.name, 'area', m.id));
  end if;
  perform bl_inv_log(v_me.id, 'sell', m.id, 'Land: sold ' || p_plots || ' plot(s) · ' || m.name, v_gross - v_fee, v_gross - v_fee - v_rel,
                     jsonb_build_object('plot_price', v_price, 'agent_fee', v_fee));
  return jsonb_build_object('message', 'Sold ' || p_plots || ' plot(s) in ' || m.name || ' at ' || bl_naira(v_price) || ' each. ' || bl_naira(v_gross - v_fee) || ' in your bank after the agent.',
                            'plots', p_plots, 'plot_price', v_price, 'gross', v_gross, 'agent_fee', v_fee, 'payout', v_gross - v_fee,
                            'profit', v_gross - v_fee - v_rel, 'bank', v_bank);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Grants (private helpers revoked; RPCs for signed-in players only)
-- ---------------------------------------------------------------------------------------------
revoke all on function public.bl_inv_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_inv_year() from public, anon, authenticated;
revoke all on function public.bl_inv_day() from public, anon, authenticated;
revoke all on function public.bl_inv_interest(numeric, numeric, numeric) from public, anon, authenticated;
revoke all on function public.bl_inv_u(text) from public, anon, authenticated;
revoke all on function public.bl_inv_vnoise(text, numeric, numeric) from public, anon, authenticated;
revoke all on function public.bl_inv_swing(public.invest_markets, numeric) from public, anon, authenticated;
revoke all on function public.bl_inv_extend(text) from public, anon, authenticated;
revoke all on function public.bl_inv_price(text, timestamptz) from public, anon, authenticated;
revoke all on function public.bl_inv_series(text, int, int) from public, anon, authenticated;
revoke all on function public.bl_inv_change(text, int) from public, anon, authenticated;
revoke all on function public.bl_inv_roll(numeric) from public, anon, authenticated;
revoke all on function public.bl_inv_log(uuid, text, text, text, bigint, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.bl_inv_assert_ok(public.profiles, boolean) from public, anon, authenticated;
revoke all on function public.bl_inv_need_bank(public.profiles, numeric) from public, anon, authenticated;
revoke all on function public.bl_inv_amount(numeric, numeric, numeric, text) from public, anon, authenticated;
revoke all on function public.bl_inv_settle_pos(bigint) from public, anon, authenticated;
revoke all on function public.bl_inv_settle(uuid) from public, anon, authenticated;
revoke all on function public.bl_inv_calc(public.invest_positions) from public, anon, authenticated;
revoke all on function public.bl_inv_land_close(bigint) from public, anon, authenticated;

revoke all on function public.invest_market_series(text, int, int) from public, anon;
revoke all on function public.invest_overview() from public, anon;
revoke all on function public.invest_buy(text, bigint) from public, anon;
revoke all on function public.invest_withdraw(bigint, bigint) from public, anon;
revoke all on function public.invest_collect(bigint, boolean) from public, anon;
revoke all on function public.invest_market_buy(text, numeric) from public, anon;
revoke all on function public.invest_market_sell(text, numeric) from public, anon;
revoke all on function public.invest_land_quote(text, int) from public, anon;
revoke all on function public.invest_land_buy(text, int) from public, anon;
revoke all on function public.invest_land_levy(bigint, boolean) from public, anon;
revoke all on function public.invest_land_sell(text, int) from public, anon;
grant execute on function public.invest_market_series(text, int, int) to authenticated, service_role;
grant execute on function public.invest_overview() to authenticated, service_role;
grant execute on function public.invest_buy(text, bigint) to authenticated, service_role;
grant execute on function public.invest_withdraw(bigint, bigint) to authenticated, service_role;
grant execute on function public.invest_collect(bigint, boolean) to authenticated, service_role;
grant execute on function public.invest_market_buy(text, numeric) to authenticated, service_role;
grant execute on function public.invest_market_sell(text, numeric) to authenticated, service_role;
grant execute on function public.invest_land_quote(text, int) to authenticated, service_role;
grant execute on function public.invest_land_buy(text, int) to authenticated, service_role;
grant execute on function public.invest_land_levy(bigint, boolean) to authenticated, service_role;
grant execute on function public.invest_land_sell(text, int) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 8. Ledger labels (guarded replacement of the live function)
-- ---------------------------------------------------------------------------------------------
do $$
declare v_def text; v_anchor text := '    when ''money_pick'' then';
begin
  select pg_get_functiondef('public.bl_ledger_label(text,jsonb)'::regprocedure) into v_def;
  if position('invest_buy' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'I1: bl_ledger_label() changed; update the invest migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''invest_buy'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Invest'');' || chr(10)
    || '    when ''invest_sell'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Invest: sold'');' || chr(10)
    || '    when ''invest_fee'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Invest: fee'');' || chr(10)
    || '    when ''invest_income'' then return coalesce(nullif(p_meta->>''label'', ''''), ''Invest: income'');' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. Admin -> Content tables (guarded replacement of the live function)
-- ---------------------------------------------------------------------------------------------
do $$
declare v_def text; v_anchor text := '    when ''interaction_types'' then';
begin
  select pg_get_functiondef('public.bl_admin_table_spec(text)'::regprocedure) into v_def;
  if position('invest_products' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'I1: bl_admin_table_spec() changed; update the invest migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''invest_products'' then ''{"pk":["id"],"insert":true,"order":"sort, id",' || chr(10)
    || '      "cols":{"kind":"text","name":"text","icon":"text","blurb":"text","risk":"text","rate_pct":"num","term_days":"int",' || chr(10)
    || '              "exit_fee_pct":"num","forfeits_interest":"bool","unit_price":"money","market_id":"text_null","min_amount":"money",' || chr(10)
    || '              "max_amount":"money","cycle_days":"int","gain_min_pct":"num","gain_max_pct":"num","income_day":"money",' || chr(10)
    || '              "resale_pct":"num","depr_pct_year":"num","resale_floor_pct":"num","events":"obj","sort":"int","active":"bool"}}''' || chr(10)
    || '    when ''invest_markets'' then ''{"pk":["id"],"insert":false,"order":"sort, id",' || chr(10)
    || '      "cols":{"name":"text","icon":"text","blurb":"text","risk":"text","ticker":"text","price_mult":"num","drift_pct_year":"num",' || chr(10)
    || '              "vol_pct":"num","swing_pct":"num","swing_days":"num","fee_pct":"num","community_pct":"num","levy_chance_pct":"num",' || chr(10)
    || '              "levy_min_pct":"num","levy_max_pct":"num","dividend_chance_pct":"num","dividend_yield_pct":"num",' || chr(10)
    || '              "min_qty":"num","max_qty":"num","sort":"int","active":"bool"}}''' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

notify pgrst, 'reload schema';
