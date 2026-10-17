-- E2 More ways to earn (docs/HUSTLES.md, owner-approved plan docs/ECONOMY_PLAN.md section 3). Every pay, cooldown, cost,
-- chance and cap lives in admin-editable tables / game_config.
-- * Side hustles: `hustles` rows (Bolt shift, PoS agent, food stall x3, DJ set, MC gig, tutoring, fishing, mechanic x2, stall rent,
--   car service). Seconds-long timed actions (busy label "Hustle: ...", live bar like every action), per-hustle cooldown and daily
--   cap (Benin day), requirements (own car, work tool item, rented stall, place, opening hours), an optional bad-luck roll
--   (network down / ride cancelled), a loss roll (PoS fraud) and a bonus roll (parents' tip, crowd tip). Bolt pay depends on the
--   car class (hustle_car_classes) and wears the car (service it at the mechanic village). Fishing catches random fish
--   (hustle_fish -> items category fish, sold at any market with the normal Sell).
-- * Two new places: Ikpoba River Bank (map 655,455, east of the Akpakpava Rd bridge) and Sapele Rd Mechanic Village (590,800).
-- * Referral: referral_codes / referrals, referral_claim (after signup), referral_status (progress check-in + milestone check),
--   both sides paid once; anti-abuse: one per new account, no self-referral, new accounts only, daily + total cap per inviter.
-- * Weekly earnings leaderboard: ledger income (config leaderboard.earn_reasons) per ISO week in Benin time, top 3 paid by the first
--   call after the week closes (lazy, idempotent via weekly_earn_weeks), winners get a targeted popup (broadcasts).
-- * Tips: tips table + tip_player(username, amount, note) for the future Benin Gist app.
-- Idempotent and safe on a non-empty DB: seeds use "on conflict do nothing" (admin edits survive a re-run) and live functions
-- are patched from pg_get_functiondef with guarded replacements (create or replace keeps the grants).

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('hustles.enabled', 'true', 'hustles', 'Side hustles on',
 'E2: Bolt, PoS agent, food stall, DJ / MC, tutoring, fishing and mechanic hustles. Off = every hustle is refused. Per-hustle pay, cooldown, daily cap, cost and risk: Content -> Hustles.', 'bool', null, null),
('hustles.min_energy', '10', 'hustles', 'Lowest energy to start a hustle',
 'E2: a hustle is refused below this energy ("too tired"). Each hustle also takes its own need costs (Content -> Hustles -> effects).', 'number', 0, 100),
('referral.enabled', 'true', 'referral', 'Referral bonus on',
 'E2: every player has a referral link (playbeninlife.app/?ref=CODE). When a new player signs up with it and reaches the milestone, both get the bonus.', 'bool', null, null),
('referral.bonus_referrer', '20000', 'referral', 'Bonus for the inviter',
 'E2: cash the inviter gets when their friend reaches the milestone.', 'naira', 0, 1000000000),
('referral.bonus_referred', '20000', 'referral', 'Bonus for the new player',
 'E2: cash the new player gets when they reach the milestone.', 'naira', 0, 1000000000),
('referral.min_shifts', '1', 'referral', 'Milestone: finished shifts',
 'E2: the new player reaches the milestone after this many finished work shifts (0 = ignore this rule). Any ONE rule is enough: shifts, hustles or play time.', 'number', 0, 1000),
('referral.min_hustles', '3', 'referral', 'Milestone: finished hustles',
 'E2: or after this many finished side hustles (0 = ignore this rule).', 'number', 0, 1000),
('referral.play_minutes', '60', 'referral', 'Milestone: minutes played',
 'E2: or after this many real minutes with the game open (counted from the new player''s own check-ins, at most 5 minutes per check-in; 0 = ignore this rule).', 'number', 0, 100000),
('referral.daily_cap', '5', 'referral', 'Most referrals per inviter per day',
 'E2: anti-abuse: one inviter can sign up at most this many new players per day (Benin time). More are refused.', 'number', 1, 1000),
('referral.max_total', '100', 'referral', 'Most referrals per inviter, ever',
 'E2: anti-abuse: lifetime cap of referred players per inviter.', 'number', 1, 100000),
('referral.max_account_age_hours', '48', 'referral', 'Referral code works for new accounts only (hours)',
 'E2: anti-abuse: a code can only be used by an account younger than this.', 'number', 1, 8760),
('referral.base_url', '"https://playbeninlife.app"', 'referral', 'Referral link base',
 'E2: the referral link is this address + /?ref=CODE.', 'text', null, null),
('leaderboard.weekly_enabled', 'true', 'leaderboard', 'Weekly top earners on',
 'E2: the "This week''s top earners" tab and the automatic prizes for the top 3 when the week closes (Monday 00:00, Benin time).', 'bool', null, null),
('leaderboard.earn_reasons', '"salary,hustle,harvest,farm_harvest,invest_income"', 'leaderboard', 'What counts as earned',
 'E2: comma-separated ledger reasons that count as money EARNED each week (jobs, hustles, harvests, investment income). Transfers, gifts, tips, sales, Yahoo cash-outs and admin gifts are not in the list by default. Add yahoo_cashout or shop_sell here if you want them to count.', 'text', null, null),
('leaderboard.weekly_prize_1', '200000', 'leaderboard', 'Weekly prize: 1st place',
 'E2: paid into the bank of the top earner when the week closes.', 'naira', 0, 1000000000),
('leaderboard.weekly_prize_2', '100000', 'leaderboard', 'Weekly prize: 2nd place',
 'E2: paid into the bank of the 2nd top earner.', 'naira', 0, 1000000000),
('leaderboard.weekly_prize_3', '50000', 'leaderboard', 'Weekly prize: 3rd place',
 'E2: paid into the bank of the 3rd top earner.', 'naira', 0, 1000000000),
('leaderboard.weekly_min_earned', '20000', 'leaderboard', 'Least earned to win a prize',
 'E2: a player must have earned at least this much in the week to take a prize (stops prizes for token amounts).', 'naira', 0, 1000000000),
('tips.enabled', 'true', 'tips', 'Tips on',
 'E2: tip_player(): players can tip each other (built for the Benin Gist creator tips; no screen yet).', 'bool', null, null),
('tips.min_amount', '100', 'tips', 'Smallest tip',
 'E2: the least one tip can be.', 'naira', 1, 1000000000),
('tips.max_amount', '1000000', 'tips', 'Biggest tip',
 'E2: the most one tip can be.', 'naira', 1, 1000000000000),
('tips.daily_max', '5000000', 'tips', 'Most a player can tip per day',
 'E2: total a player can tip in one Benin day.', 'naira', 1, 1000000000000)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Work tools and fish (items). Prices researched for Nigeria, Oct 2026 (docs/HUSTLES.md).
-- ---------------------------------------------------------------------------------------------
insert into public.items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort) values
('pos_machine',   'PoS machine (agent terminal)', 'tool', 35000,
 'Network-ready PoS terminal. Plug in a SIM, set your PIN, and people go start dey queue for cash.', '{}',
 '{oba_market,ekiosa_market,new_benin_market,uselu_market,santana_market,oregbeni_market,new_benin_pos,ring_road_pos,sapele_pos}', true, 50, '💳', 540),
('fishing_rod',   'Fishing rod and line', 'tool', 8000,
 'Bamboo rod, strong line, a few hooks. The river no go beg fish for you.', '{}',
 '{oba_market,oregbeni_market,ikpoba_riverbank}', true, 50, '🎣', 541),
('dj_controller', 'DJ controller (entry level)', 'tool', 220000,
 'Two decks, jog wheels, a mixer and a USB cable. Club resident DJs start from here.', '{}',
 '{bronze_tech_hub,benin_city_mall}', true, 50, '🎛️', 542),
('fish_tilapia_small', 'Small tilapia',      'fish',   1200, 'A little river tilapia, still shining.', '{}', '{}', true, 100, '🐟', 550),
('fish_tilapia',       'Tilapia',            'fish',   2500, 'Fat river tilapia. Mama put go buy am quick.', '{}', '{}', true, 100, '🐠', 551),
('fish_catfish',       'Catfish',            'fish',   5500, 'Heavy river catfish. Pepper soup material.', '{}', '{}', true, 100, '🐟', 552),
('fish_mudfish',       'Big mudfish',        'fish',   9000, 'Big mudfish from the bank mud. The market ladies dey ask for this one.', '{}', '{}', true, 100, '🐡', 553),
('fish_giant_catfish', 'Giant catfish',      'fish',  30000, 'Omo! This one na river king. Whole market go gather.', '{}', '{}', true, 100, '🐋', 554),
('river_junk',         'Old slippers',       'fish',    150, 'Wetin you catch? Somebody''s slippers. Scrap seller go still buy.', '{}', '{}', true, 100, '🩴', 555)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. Places: Ikpoba River Bank and the Sapele Rd Mechanic Village
-- ---------------------------------------------------------------------------------------------
insert into public.locations (id, name, district, scene, blurb, risk, night_risk_mult, cctv, keke_ok, congestion, remote_km, x, y, actions, sort, open_hour, close_hour, active) values
('ikpoba_riverbank', 'Ikpoba River Bank (Ikpoba Bridge)', 'ikpoba_hill', 'farm',
 'The east bank of the Ikpoba River just past the Akpakpava Rd bridge, before Ramat Park. Fishermen, a bait kiosk and shade trees. Bring a rod and some patience.',
 .20, 1.8, false, true, 1.1, 0, 655, 455, '{activities,shop}', 252, null, null, true),
('mechanic_village', 'Sapele Rd Mechanic Village', 'sapele_rd', 'workshop',
 'Rows of roadside bays on Sapele Road where tokunbo cars come back to life. Panel beaters, vulcanizers and oga mechanics. Ask for work.',
 .25, 1.4, false, true, 1.3, 0, 590, 800, '{activities}', 253, 7, 19, true)
on conflict (id) do nothing;

-- the bait kiosk sells the rod, so the river bank needs the shop tab (re-runs fix an older row)
update public.locations set actions = array_append(actions, 'shop') where id = 'ikpoba_riverbank' and not ('shop' = any (actions));

-- two free ambient cards so no zone of the new places is empty
insert into public.activities (id, name, scenes, home_only, cost, game_minutes, effects, night_only, sort, max_seconds, min_seconds, scale_by_need, needs_furniture, location_ids, risky, rush, icon)
values ('river_watch', 'Watch the river flow', '{farm}', false, 0, 30, '{"stress": -12, "fun": 6}', false, 310, 12, 6, false, false, '{ikpoba_riverbank}', false, '{}', '🌊'),
       ('river_rest', 'Rest in the shade', '{farm}', false, 0, 45, '{"energy": 10, "stress": -6}', false, 311, 15, 8, false, false, '{ikpoba_riverbank}', false, '{}', '🌳')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.hustles (
  id                text primary key,
  name              text not null,
  icon              text not null default '💪',
  blurb             text not null default '',
  kind              text not null default 'job' check (kind in ('bolt', 'pos', 'vending', 'dj', 'mc', 'tutor', 'fishing', 'mechanic', 'job', 'pass', 'service')),
  where_text        text not null default '',                 -- "Oba Market" (what the app and refusals say)
  req_text          text not null default '',                 -- "Needs a PoS machine"
  seconds           int not null default 30 check (seconds between 1 and 3600),
  pay_min           bigint not null default 0 check (pay_min >= 0),
  pay_max           bigint not null default 0 check (pay_max >= 0),
  cost              bigint not null default 0 check (cost >= 0),   -- per run (fuel, ingredients, bait, parts); pass / service price
  cooldown_seconds  int not null default 30 check (cooldown_seconds between 0 and 604800),
  daily_cap         int not null default 5 check (daily_cap between 0 and 10000),   -- runs per Benin day, 0 = no cap
  effects           jsonb not null default '{}'::jsonb,       -- need changes at the start, e.g. {"energy": -10}
  location_ids      text[] not null default '{}',
  scenes            text[] not null default '{}',
  anywhere          boolean not null default false,           -- any public place (Bolt)
  hour_from         numeric check (hour_from is null or (hour_from >= 0 and hour_from < 24)),
  hour_to           numeric check (hour_to is null or (hour_to >= 0 and hour_to <= 24)),
  needs_car         boolean not null default false,
  req_item          text,                                     -- item the player must own
  no_item_pay_mult  numeric check (no_item_pay_mult is null or no_item_pay_mult >= 0),   -- null = the item is a must; else pay x this without it
  needs_pass        text,                                     -- an active pass (stall)
  pass_id           text,                                     -- kind 'pass': which pass it sells
  pass_hours        int check (pass_hours is null or pass_hours > 0),
  wear_pct          numeric not null default 0 check (wear_pct >= 0),   -- car wear per run (x the car class wear)
  risk_pct          numeric not null default 0 check (risk_pct between 0 and 100),
  risk_pay_mult     numeric not null default 0 check (risk_pay_mult >= 0),
  risk_text         text not null default '',
  loss_pct          numeric not null default 0 check (loss_pct between 0 and 100),
  loss_min          bigint not null default 0 check (loss_min >= 0),
  loss_max          bigint not null default 0 check (loss_max >= 0),
  loss_text         text not null default '',
  bonus_pct         numeric not null default 0 check (bonus_pct between 0 and 100),
  bonus_min         bigint not null default 0 check (bonus_min >= 0),
  bonus_max         bigint not null default 0 check (bonus_max >= 0),
  bonus_text        text not null default '',
  cred_gain         int not null default 0,                   -- street cred per finished run
  hype_text         text not null default '',                 -- club announcement ("{name}" = player) for DJ / MC
  hour_mult         jsonb not null default '{}'::jsonb,       -- pay x by Benin hour, {"11-15": 1.5}
  sort              int not null default 0,
  active            boolean not null default true
);

create table if not exists public.hustle_car_classes (
  id         text primary key,
  name       text not null,
  icon       text not null default '🚗',
  min_price  bigint not null default 0 check (min_price >= 0),     -- cars at least this expensive are in the class
  pay_mult   numeric not null default 1 check (pay_mult >= 0),
  fuel_mult  numeric not null default 1 check (fuel_mult >= 0),
  wear_mult  numeric not null default 1 check (wear_mult >= 0),
  sort       int not null default 0
);

create table if not exists public.hustle_fish (
  item_id  text primary key references public.items(id) on update cascade on delete cascade,
  weight   numeric not null default 10 check (weight >= 0),
  sort     int not null default 0,
  active   boolean not null default true
);

create table if not exists public.hustle_players (
  user_id       uuid primary key references public.profiles(id) on delete cascade,
  car_wear      numeric not null default 0 check (car_wear >= 0),
  total_earned  bigint not null default 0,
  runs_done     int not null default 0,
  updated_at    timestamptz not null default now()
);

create table if not exists public.hustle_passes (
  user_id   uuid not null references public.profiles(id) on delete cascade,
  pass_id   text not null,
  until_at  timestamptz not null,
  primary key (user_id, pass_id)
);

create table if not exists public.hustle_runs (
  id           bigserial primary key,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  hustle_id    text not null,
  location_id  text,
  started_at   timestamptz not null,
  resolve_at   timestamptz not null,
  status       text not null default 'running' check (status in ('running', 'done', 'cancelled')),
  cost         bigint not null default 0,
  pay_mult     numeric not null default 1,
  amount       bigint not null default 0,          -- gross income of the run (fish: the catch's value)
  outcome      text,                               -- ok / bonus / risk / loss
  detail       jsonb not null default '{}'::jsonb,
  resolved_at  timestamptz
);
create index if not exists hustle_runs_user_idx on public.hustle_runs (user_id, id desc);
create index if not exists hustle_runs_user_hustle_idx on public.hustle_runs (user_id, hustle_id, started_at desc);
create unique index if not exists hustle_runs_one_running_uidx on public.hustle_runs (user_id) where status = 'running';

create table if not exists public.referral_codes (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  code        text not null unique,
  created_at  timestamptz not null default now()
);

create table if not exists public.referrals (
  id               bigserial primary key,
  referrer_id      uuid not null references public.profiles(id) on delete cascade,
  referred_id      uuid not null unique references public.profiles(id) on delete cascade,   -- one referral per new account
  code             text not null,
  status           text not null default 'pending' check (status in ('pending', 'rewarded', 'rejected')),
  reason           text,
  play_seconds     int not null default 0,
  last_ping        timestamptz,
  bonus_referrer   bigint not null default 0,
  bonus_referred   bigint not null default 0,
  created_at       timestamptz not null default now(),
  rewarded_at      timestamptz,
  check (referrer_id <> referred_id)
);
create index if not exists referrals_referrer_idx on public.referrals (referrer_id, created_at desc);

create table if not exists public.weekly_earn_weeks (
  week_start     date primary key,                 -- the Monday (Benin time)
  settled_at     timestamptz not null default now(),
  skipped        boolean not null default false,   -- a week before the feature existed: no prizes
  total_players  int not null default 0,
  total_earned   numeric not null default 0
);

create table if not exists public.weekly_earn_winners (
  id          bigserial primary key,
  week_start  date not null references public.weekly_earn_weeks(week_start) on delete cascade,
  rank        int not null check (rank between 1 and 100),
  user_id     uuid references public.profiles(id) on delete set null,
  username    text not null,
  total       bigint not null default 0,
  prize       bigint not null default 0,
  paid_at     timestamptz,
  unique (week_start, rank)
);

create table if not exists public.tips (
  id             bigserial primary key,
  from_user      uuid references public.profiles(id) on delete set null,
  to_user        uuid references public.profiles(id) on delete set null,
  from_username  text not null,
  to_username    text not null,
  amount         bigint not null check (amount > 0),
  note           text,
  source         text not null default 'gist',
  created_at     timestamptz not null default now()
);
create index if not exists tips_from_idx on public.tips (from_user, created_at desc);
create index if not exists tips_to_idx on public.tips (to_user, created_at desc);

alter table public.hustles enable row level security;
alter table public.hustle_car_classes enable row level security;
alter table public.hustle_fish enable row level security;
alter table public.hustle_players enable row level security;
alter table public.hustle_passes enable row level security;
alter table public.hustle_runs enable row level security;
alter table public.referral_codes enable row level security;
alter table public.referrals enable row level security;
alter table public.weekly_earn_weeks enable row level security;
alter table public.weekly_earn_winners enable row level security;
alter table public.tips enable row level security;
revoke all on table public.hustles, public.hustle_car_classes, public.hustle_fish, public.hustle_players, public.hustle_passes,
  public.hustle_runs, public.referral_codes, public.referrals, public.weekly_earn_weeks, public.weekly_earn_winners, public.tips
  from public, anon, authenticated;
revoke all on sequence public.hustle_runs_id_seq, public.referrals_id_seq, public.weekly_earn_winners_id_seq, public.tips_id_seq
  from public, anon, authenticated;
-- catalogues and public results: read by signed-in players; writes only through admin_row_upsert / server functions
grant select on table public.hustles, public.hustle_car_classes, public.hustle_fish, public.weekly_earn_weeks, public.weekly_earn_winners to authenticated;
drop policy if exists hustles_read on public.hustles;
create policy hustles_read on public.hustles for select to authenticated using (true);
drop policy if exists hustle_car_classes_read on public.hustle_car_classes;
create policy hustle_car_classes_read on public.hustle_car_classes for select to authenticated using (true);
drop policy if exists hustle_fish_read on public.hustle_fish;
create policy hustle_fish_read on public.hustle_fish for select to authenticated using (true);
drop policy if exists weekly_earn_weeks_read on public.weekly_earn_weeks;
create policy weekly_earn_weeks_read on public.weekly_earn_weeks for select to authenticated using (true);
drop policy if exists weekly_earn_winners_read on public.weekly_earn_winners;
create policy weekly_earn_winners_read on public.weekly_earn_winners for select to authenticated using (true);
-- my own rows (no client writes)
grant select on table public.hustle_players, public.hustle_passes, public.hustle_runs, public.referral_codes, public.referrals, public.tips to authenticated;
drop policy if exists hustle_players_own on public.hustle_players;
create policy hustle_players_own on public.hustle_players for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists hustle_passes_own on public.hustle_passes;
create policy hustle_passes_own on public.hustle_passes for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists hustle_runs_own on public.hustle_runs;
create policy hustle_runs_own on public.hustle_runs for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists referral_codes_own on public.referral_codes;
create policy referral_codes_own on public.referral_codes for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists referrals_own on public.referrals;
create policy referrals_own on public.referrals for select to authenticated
  using (referrer_id = (select auth.uid()) or referred_id = (select auth.uid()));
drop policy if exists tips_own on public.tips;
create policy tips_own on public.tips for select to authenticated
  using (from_user = (select auth.uid()) or to_user = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------
-- 5. Seeds: car classes, hustles (numbers explained in docs/HUSTLES.md), fish
-- ---------------------------------------------------------------------------------------------
insert into public.hustle_car_classes (id, name, icon, min_price, pay_mult, fuel_mult, wear_mult, sort) values
('economy',  'Bolt Economy',  '🚗', 1700000,   1.0, 1.0, 1.0, 1),
('comfort',  'Bolt Comfort',  '🚙', 6000000,   1.5, 1.3, 1.0, 2),
('premium',  'Bolt Premium',  '🚘', 40000000,  2.2, 1.7, 1.4, 3),
('luxury',   'Bolt Black',    '🏎️', 150000000, 3.5, 2.4, 2.0, 4)
on conflict (id) do nothing;

insert into public.hustles (id, name, icon, blurb, kind, where_text, req_text, seconds, pay_min, pay_max, cost, cooldown_seconds, daily_cap,
                            effects, location_ids, scenes, anywhere, hour_from, hour_to, needs_car, req_item, no_item_pay_mult, needs_pass,
                            pass_id, pass_hours, wear_pct, risk_pct, risk_pay_mult, risk_text, loss_pct, loss_min, loss_max, loss_text,
                            bonus_pct, bonus_min, bonus_max, bonus_text, cred_gain, hype_text, hour_mult, sort) values
('bolt_shift', 'Bolt driver shift', '🚖', 'Switch on the app, carry NPC passengers round town. Fuel and wear come out of your pocket; a better car pays more.',
 'bolt', 'Anywhere on the road (not at home)', 'Needs your own car (Kia Rio or better)', 40, 9000, 15000, 3200, 90, 5,
 '{"energy": -10, "hunger": -4, "stress": 6}', '{}', '{}', true, null, null, true, null, null, null,
 null, null, 10, 8, 0.5, 'Passenger cancelled at the pick-up point. You collect half the fare.', 0, 0, 0, '',
 0, 0, 0, '', 0, '', '{"6-9": 1.2, "16-19": 1.25, "23-24": 0.8, "0-5": 0.8}', 1),
('pos_agent', 'PoS agent batch', '💳', 'Serve the cash-out queue at the market. You earn the commission on each batch.',
 'pos', 'Any market or PoS stand', 'Needs a PoS machine (buy one at a market)', 25, 2500, 6500, 0, 60, 6,
 '{"energy": -6, "stress": 4}', '{}', '{market,pos}', false, null, null, false, 'pos_machine', null, null,
 null, null, 0, 12, 0, 'Network don fail. No commission this batch.', 4, 5000, 20000, 'Fake alert! A customer ran with your cash. You lost money.',
 0, 0, 0, '', 1, '', '{"7-10": 1.2, "12-14": 1.15, "17-19": 1.2}', 2),
('stall_rent', 'Rent a food stall', '🏪', 'Rent a stall at Oba Market for the day. You need it to sell food.',
 'pass', 'Oba Market', 'Pay the day''s stall rent', 3, 0, 0, 3000, 0, 0,
 '{}', '{oba_market}', '{}', false, null, null, false, null, null, null,
 'stall', 24, 0, 0, 0, '', 0, 0, 0, '',
 0, 0, 0, '', 0, '', '{}', 3),
('vend_jollof', 'Sell jollof rice', '🍛', 'Jollof and chicken by the plate. Lunch rush is the money time.',
 'vending', 'Oba Market stall', 'Needs a rented stall', 35, 6500, 11000, 4500, 40, 4,
 '{"energy": -7, "hunger": -3}', '{oba_market}', '{}', false, null, null, false, null, null, 'stall',
 null, null, 0, 10, 0.4, 'Few customers today. A lot of the food goes spoil.', 0, 0, 0, '',
 0, 0, 0, '', 0, '', '{"6-10": 0.6, "11-15": 1.5, "15-17": 0.8, "17-20": 1.2}', 4),
('vend_puff', 'Sell puff-puff', '🥯', 'Hot puff-puff by the bag. Morning and evening customers love am.',
 'vending', 'Oba Market stall', 'Needs a rented stall', 20, 2800, 5000, 1500, 30, 4,
 '{"energy": -5}', '{oba_market}', '{}', false, null, null, false, null, null, 'stall',
 null, null, 0, 10, 0.4, 'Rain threaten and people vanish. Half of the batch goes cold.', 0, 0, 0, '',
 0, 0, 0, '', 0, '', '{"6-10": 1.3, "10-16": 1.0, "16-20": 1.3}', 5),
('vend_fried_yam', 'Sell fried yam and egg', '🍠', 'Yam, egg and pepper sauce. Breakfast people no dey carry last.',
 'vending', 'Oba Market stall', 'Needs a rented stall', 30, 4500, 8000, 2500, 35, 4,
 '{"energy": -6}', '{oba_market}', '{}', false, null, null, false, null, null, 'stall',
 null, null, 0, 10, 0.4, 'Slow day. You sell half.', 0, 0, 0, '',
 0, 0, 0, '', 0, '', '{"6-10": 1.6, "10-14": 0.8, "14-20": 0.5}', 6),
('dj_set', 'Play a DJ set', '🎧', 'Take the decks and keep the floor moving. Good sets get a shout-out from the crowd.',
 'dj', 'Any open club (night)', 'DJ controller for full pay (without it you play the resident warm-up slot)', 60, 15000, 35000, 0, 180, 2,
 '{"energy": -14, "hunger": -4, "fun": 8}', '{}', '{club}', false, null, null, false, 'dj_controller', 0.4, null,
 null, null, 0, 0, 0, '', 0, 0, 0, '',
 15, 10000, 30000, 'The crowd sprayed you for a banger set.', 3, '🎧 DJ {name} dey on the decks. The floor don catch fire!', '{}', 7),
('mc_gig', 'MC the night', '🎤', 'Hype the crowd, call names, keep the energy. No equipment needed.',
 'mc', 'Any open club (night)', 'Nothing to buy: walk in and ask for the mic', 45, 8000, 18000, 0, 120, 3,
 '{"energy": -10, "hunger": -3, "fun": 6}', '{}', '{club}', false, null, null, false, null, null, null,
 null, null, 0, 0, 0, '', 0, 0, 0, '',
 20, 5000, 15000, 'A big spender tipped the MC.', 2, '🎤 MC {name} dey run the mic. Make noise, Benin!', '{}', 8),
('tutor_session', 'Tutor a student', '📚', 'Teach a UNIBEN student or a parent''s child. Daytime only.',
 'tutor', 'UNIBEN Ugbowo Campus', 'Daytime only, 8 AM to 5 PM', 40, 6000, 12000, 0, 60, 4,
 '{"energy": -8, "stress": 3}', '{}', '{campus}', false, 8, 17, false, null, null, null,
 null, null, 0, 0, 0, '', 0, 0, 0, '',
 10, 5000, 15000, 'The parents were so happy they added a bonus.', 1, '', '{}', 9),
('fish_cast', 'Go fishing', '🎣', 'Cast a line in the Ikpoba River. Sell your catch at any market.',
 'fishing', 'Ikpoba River Bank', 'Needs a fishing rod. Bait costs a little', 25, 0, 0, 300, 20, 10,
 '{"energy": -6, "stress": -4}', '{ikpoba_riverbank}', '{}', false, 5, 19, false, 'fishing_rod', null, null,
 null, null, 0, 10, 0, 'Nothing bit. The water too cold.', 0, 0, 0, '',
 0, 0, 0, '', 0, '', '{}', 10),
('mech_quick', 'Quick fix', '🔧', 'Flat tyre, brake pads, plugs. A quick fix for a customer''s car.',
 'mechanic', 'Sapele Rd Mechanic Village', 'Walk in and ask oga for work', 30, 3500, 8000, 1000, 45, 5,
 '{"energy": -8, "hygiene": -6}', '{mechanic_village}', '{}', false, null, null, false, null, null, null,
 null, null, 0, 0, 0, '', 0, 0, 0, '',
 0, 0, 0, '', 0, '', '{}', 11),
('mech_engine', 'Engine job', '🛠️', 'Strip, fix and rebuild. The customer pays well if you do am right.',
 'mechanic', 'Sapele Rd Mechanic Village', 'Walk in and ask oga for work', 50, 9000, 18000, 3000, 90, 2,
 '{"energy": -12, "hygiene": -10, "stress": 4}', '{mechanic_village}', '{}', false, null, null, false, null, null, null,
 null, null, 0, 10, 0.5, 'The customer argued about the bill. You settle for half.', 0, 0, 0, '',
 0, 0, 0, '', 1, '', '{}', 12),
('car_service', 'Service your car', '🧰', 'Full service for your car at the mechanic village. Brings the wear back to zero.',
 'service', 'Sapele Rd Mechanic Village', 'Needs your own car', 3, 0, 0, 20000, 0, 0,
 '{}', '{mechanic_village}', '{}', false, null, null, true, null, null, null,
 null, null, 0, 0, 0, '', 0, 0, 0, '',
 0, 0, 0, '', 0, '', '{}', 13)
on conflict (id) do nothing;

insert into public.hustle_fish (item_id, weight, sort, active) values
('fish_tilapia_small', 40, 1, true),
('fish_tilapia', 25, 2, true),
('fish_catfish', 17, 3, true),
('fish_mudfish', 8, 4, true),
('fish_giant_catfish', 2, 5, true),
('river_junk', 8, 6, true)
on conflict (item_id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 6. Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_hustle_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_hustle_text(p_key text, p_default text) returns text
language sql stable set search_path = public as $$
  select coalesce(nullif((select value #>> '{}' from game_config where key = p_key), ''), p_default);
$$;

create or replace function public.bl_hustle_on(p_key text, p_default boolean) returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_hustle_row(p_uid uuid, p_lock boolean default false) returns public.hustle_players
language plpgsql set search_path = public as $$
declare r hustle_players;
begin
  insert into hustle_players (user_id) values (p_uid) on conflict (user_id) do nothing;
  if p_lock then
    select * into r from hustle_players where user_id = p_uid for update;
  else
    select * into r from hustle_players where user_id = p_uid;
  end if;
  return r;
end $$;

-- Start of today (Benin day).
create or replace function public.bl_hustle_day_start() returns timestamptz
language sql stable set search_path = public as $$
  select date_trunc('day', bl_now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos';
$$;

-- Benin hour with minutes (0..24).
create or replace function public.bl_hustle_hour() returns numeric
language sql stable set search_path = public as $$
  select (bl_game_clock()->>'hour')::numeric + coalesce((bl_game_clock()->>'minute')::numeric, 0) / 60.0;
$$;

create or replace function public.bl_hustle_runs_today(p_uid uuid, p_id text) returns int
language sql stable set search_path = public as $$
  select count(*)::int from hustle_runs where user_id = p_uid and hustle_id = p_id and status <> 'cancelled' and started_at >= bl_hustle_day_start();
$$;

create or replace function public.bl_hustle_pass_until(p_uid uuid, p_pass text) returns timestamptz
language sql stable set search_path = public as $$
  select until_at from hustle_passes where user_id = p_uid and pass_id = p_pass and until_at > bl_now();
$$;

-- The best car I own: {item_id, name, icon, price, class_id, class_name, class_icon, pay_mult, fuel_mult, wear_mult} (null = no car).
create or replace function public.bl_hustle_car(p_uid uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('item_id', it.id, 'name', it.name, 'icon', it.icon, 'price', it.price, 'class_id', c.id,
                            'class_name', c.name, 'class_icon', c.icon, 'pay_mult', c.pay_mult, 'fuel_mult', c.fuel_mult, 'wear_mult', c.wear_mult)
    from inventory i
    join items it on it.id = i.item_id and it.category = 'vehicle'
    join lateral (select * from hustle_car_classes k where k.min_price <= it.price order by k.min_price desc limit 1) c on true
   where i.user_id = p_uid and i.qty > 0
   order by it.price desc
   limit 1;
$$;

-- Pay multiplier for the Benin hour from the hustle's hour_mult ({"11-15": 1.5}); 1 when no band matches.
create or replace function public.bl_hustle_hour_mult(h public.hustles) returns numeric
language plpgsql stable set search_path = public as $$
declare e record; v_h numeric := bl_hustle_hour(); a numeric; b numeric;
begin
  for e in select key, value from jsonb_each_text(coalesce(h.hour_mult, '{}'::jsonb)) loop
    begin
      a := split_part(e.key, '-', 1)::numeric;
      b := split_part(e.key, '-', 2)::numeric;
    exception when others then
      continue;
    end;
    if (a <= b and v_h >= a and v_h < b) or (a > b and (v_h >= a or v_h < b)) then
      return greatest(0, e.value::numeric);
    end if;
  end loop;
  return 1;
end $$;

create or replace function public.bl_hustle_window_label(h public.hustles) returns text
language sql immutable set search_path = public as $$
  select case when h.hour_from is null or h.hour_to is null then null
              else bl_hour_label(h.hour_from) || ' – ' || bl_hour_label(h.hour_to) end;
$$;

-- Why can't I do this hustle? null = fine, else {hint, message, short}. p_check_place = false skips the place and opening checks
-- (the phone app lists hustles from anywhere). p_loc = the place the player is at (or the card's place). Read-only.
create or replace function public.bl_hustle_why(p_me public.profiles, h public.hustles, p_loc public.locations, p_check_place boolean default true) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_hour numeric := bl_hustle_hour();
  v_car jsonb;
  v_wear numeric := coalesce((select car_wear from hustle_players where user_id = p_me.id), 0);
  v_item text;
  v_last timestamptz;
  v_n int;
  v_in boolean;
begin
  if not bl_hustle_on('hustles.enabled', true) then
    return jsonb_build_object('hint', 'disabled', 'message', 'Hustles are switched off for now.', 'short', 'Switched off');
  end if;
  if p_check_place then
    if h.anywhere then
      if p_loc.id is null or p_loc.scene like 'home\_%' or p_loc.private_home_owner_id is not null or p_me.home_visit_host_id is not null then
        return jsonb_build_object('hint', 'wrong_place', 'message', 'Bolt work happens out on the road. Leave the house and go to any public place first.', 'short', 'Not at home');
      end if;
    else
      v_in := (p_loc.id = any (h.location_ids)) or (p_loc.scene = any (h.scenes));
      if not coalesce(v_in, false) then
        return jsonb_build_object('hint', 'wrong_place', 'message', coalesce(nullif(h.where_text, ''), 'Wrong place for this hustle.') || ' is where this one happens.', 'short', 'Wrong place');
      end if;
      if not bl_place_open(p_loc) then
        return jsonb_build_object('hint', 'closed', 'message', p_loc.name || ' is closed right now. Opens ' || bl_hour_label(p_loc.open_hour) || '.',
                                  'short', 'Opens ' || bl_hour_label(p_loc.open_hour));
      end if;
    end if;
  end if;
  if h.hour_from is not null and h.hour_to is not null then
    if not ((h.hour_from <= h.hour_to and v_hour >= h.hour_from and v_hour < h.hour_to)
            or (h.hour_from > h.hour_to and (v_hour >= h.hour_from or v_hour < h.hour_to))) then
      return jsonb_build_object('hint', 'wrong_hours', 'message', h.name || ' only runs between ' || bl_hustle_window_label(h) || '.',
                                'short', 'Only ' || bl_hustle_window_label(h));
    end if;
  end if;
  if h.needs_car then
    v_car := bl_hustle_car(p_me.id);
    if v_car is null then
      return jsonb_build_object('hint', 'no_car', 'message', 'You need your own car for this. Buy one from a car dealer or in Phone -> Cars.', 'short', 'Needs a car');
    end if;
    if h.kind = 'bolt' and v_wear >= 100 then
      return jsonb_build_object('hint', 'car_needs_service', 'message', 'Your ' || (v_car->>'name') || ' is worn out. Service it at the Sapele Rd Mechanic Village first.', 'short', 'Car needs service');
    end if;
    if h.kind = 'service' and v_wear <= 0 then
      return jsonb_build_object('hint', 'no_need', 'message', 'Your car is fine. No need for a service yet.', 'short', 'Car is fine');
    end if;
  end if;
  if h.req_item is not null and h.no_item_pay_mult is null
     and not exists (select 1 from inventory where user_id = p_me.id and item_id = h.req_item and qty > 0) then
    select name into v_item from items where id = h.req_item;
    return jsonb_build_object('hint', 'no_item', 'message', 'You need a ' || coalesce(v_item, h.req_item) || ' for this. Check the markets.', 'short', 'Needs ' || coalesce(v_item, h.req_item));
  end if;
  if h.needs_pass is not null and bl_hustle_pass_until(p_me.id, h.needs_pass) is null then
    return jsonb_build_object('hint', 'no_pass', 'message', 'Rent a stall first (' || bl_naira(coalesce((select cost from hustles where pass_id = h.needs_pass and kind = 'pass' limit 1), 0)) || ' a day).',
                              'short', 'Rent a stall first');
  end if;
  if h.kind not in ('pass', 'service') then
    if p_me.energy < bl_hustle_num('hustles.min_energy', 10) then
      return jsonb_build_object('hint', 'too_tired', 'message', 'You are too tired to hustle. Sleep or take a nap first.', 'short', 'Too tired');
    end if;
    if h.daily_cap > 0 then
      v_n := bl_hustle_runs_today(p_me.id, h.id);
      if v_n >= h.daily_cap then
        return jsonb_build_object('hint', 'daily_cap', 'message', 'You have done ' || v_n || ' ' || h.name || ' today. Come back tomorrow (Benin time).', 'short', 'Done for today');
      end if;
    end if;
    select max(started_at) into v_last from hustle_runs where user_id = p_me.id and hustle_id = h.id and status <> 'cancelled';
    if v_last is not null and v_last + make_interval(secs => h.cooldown_seconds) > bl_now() then
      return jsonb_build_object('hint', 'cooldown', 'message', 'Cool down small. ' || h.name || ' again in about '
                                || ceil(extract(epoch from v_last + make_interval(secs => h.cooldown_seconds) - bl_now()))::int || ' sec.',
                                'short', 'Cooldown');
    end if;
  end if;
  return null;
end $$;

-- What a run costs me (fuel scales with the car class, service with its wear).
create or replace function public.bl_hustle_cost(p_uid uuid, h public.hustles) returns bigint
language sql stable set search_path = public as $$
  select case when h.kind = 'service' then round(h.cost * coalesce((bl_hustle_car(p_uid)->>'wear_mult')::numeric, 1))::bigint
              when h.kind = 'bolt' then round(h.cost * coalesce((bl_hustle_car(p_uid)->>'fuel_mult')::numeric, 1))::bigint
              else h.cost end;
$$;

-- My pay multiplier before the roll: car class x (no tool: no_item_pay_mult) x time of day.
create or replace function public.bl_hustle_pay_mult(p_uid uuid, h public.hustles) returns numeric
language sql stable set search_path = public as $$
  select coalesce(case when h.needs_car then (bl_hustle_car(p_uid)->>'pay_mult')::numeric end, 1)
         * case when h.req_item is not null and h.no_item_pay_mult is not null
                     and not exists (select 1 from inventory where user_id = p_uid and item_id = h.req_item and qty > 0)
                then h.no_item_pay_mult else 1 end
         * bl_hustle_hour_mult(h);
$$;

-- Places where a hustle works (nearest first, up to 5): [{id, name, open}].
create or replace function public.bl_hustle_places(h public.hustles, p_loc public.locations) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'open', bl_place_open((select lx from locations lx where lx.id = x.id))) order by x.d), '[]'::jsonb)
    from (select l.*, ((l.x - coalesce(p_loc.x, 500)) ^ 2 + (l.y - coalesce(p_loc.y, 500)) ^ 2) as d
            from locations l
           where coalesce(l.active, true) and l.private_home_owner_id is null
             and (l.id = any (h.location_ids) or l.scene = any (h.scenes))
           order by d limit 5) x;
$$;

-- Everything the phone app shows for one hustle.
create or replace function public.bl_hustle_json(p_me public.profiles, h public.hustles, p_loc public.locations) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_why jsonb := bl_hustle_why(p_me, h, p_loc, false);
  v_here jsonb := bl_hustle_why(p_me, h, p_loc, true);
  v_pm numeric := case when h.kind in ('pass', 'service') then 1 else bl_hustle_pay_mult(p_me.id, h) end;
  v_carm numeric := coalesce(case when h.needs_car then (bl_hustle_car(p_me.id)->>'pay_mult')::numeric end, 1);
  v_item items;
  v_n int := bl_hustle_runs_today(p_me.id, h.id);
  v_cool timestamptz;
begin
  if h.req_item is not null then select * into v_item from items where id = h.req_item; end if;
  select max(started_at) + make_interval(secs => h.cooldown_seconds) into v_cool
    from hustle_runs where user_id = p_me.id and hustle_id = h.id and status <> 'cancelled';
  if v_cool is not null and v_cool <= bl_now() then v_cool := null; end if;
  return jsonb_build_object(
    'id', h.id, 'name', h.name, 'icon', h.icon, 'blurb', h.blurb, 'kind', h.kind,
    'where_text', h.where_text, 'req_text', h.req_text, 'anywhere', h.anywhere,
    'seconds', h.seconds, 'cooldown_seconds', h.cooldown_seconds, 'daily_cap', h.daily_cap, 'runs_today', v_n,
    'cap_left', case when h.daily_cap > 0 then greatest(0, h.daily_cap - v_n) end,
    'cooldown_until', v_cool,
    'cost', bl_hustle_cost(p_me.id, h),
    'pay_min', round(h.pay_min * v_carm), 'pay_max', round(h.pay_max * v_carm),
    'pay_mult_now', v_pm,
    'hours', bl_hustle_window_label(h),
    'hour_mult', coalesce(h.hour_mult, '{}'::jsonb),
    'risk', case when h.risk_pct > 0 then jsonb_build_object('pct', h.risk_pct, 'text', h.risk_text, 'pay_mult', h.risk_pay_mult) end,
    'loss', case when h.loss_pct > 0 then jsonb_build_object('pct', h.loss_pct, 'min', h.loss_min, 'max', h.loss_max, 'text', h.loss_text) end,
    'bonus', case when h.bonus_pct > 0 then jsonb_build_object('pct', h.bonus_pct, 'min', h.bonus_min, 'max', h.bonus_max, 'text', h.bonus_text) end,
    'item', case when v_item.id is not null then jsonb_build_object(
              'id', v_item.id, 'name', v_item.name, 'icon', v_item.icon, 'price', v_item.price,
              'owned', exists (select 1 from inventory where user_id = p_me.id and item_id = v_item.id and qty > 0),
              'optional', h.no_item_pay_mult is not null, 'no_item_pay_mult', h.no_item_pay_mult,
              'sold_at', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name) order by l.sort)
                                     from locations l where l.id = any (v_item.sold_at) and coalesce(l.active, true)), '[]'::jsonb)) end,
    'needs_car', h.needs_car,
    'pass', case when h.needs_pass is not null then jsonb_build_object('id', h.needs_pass, 'until', bl_hustle_pass_until(p_me.id, h.needs_pass)) end,
    'pass_hours', h.pass_hours,
    'places', bl_hustle_places(h, p_loc),
    'here', v_here is null,
    'here_why', v_here,
    'locked', v_why);
end $$;

-- The card shown at a place zone (place_interior): short lock text for this place + the numbers.
create or replace function public.bl_hustle_card(p_me public.profiles, h public.hustles, l public.locations, p_id text, p_name text, p_icon text) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_why jsonb := bl_hustle_why(p_me, h, l, true);
  v_pm numeric := case when h.kind in ('pass', 'service') then 1 else bl_hustle_pay_mult(p_me.id, h) end;
  v_n int := bl_hustle_runs_today(p_me.id, h.id);
  v_cool timestamptz;
begin
  select max(started_at) + make_interval(secs => h.cooldown_seconds) into v_cool
    from hustle_runs where user_id = p_me.id and hustle_id = h.id and status <> 'cancelled';
  if v_cool is not null and v_cool <= bl_now() then v_cool := null; end if;
  return jsonb_build_object(
    'id', p_id, 'kind', 'hustle', 'ref', h.id, 'name', p_name, 'icon', p_icon,
    'cost', bl_hustle_cost(p_me.id, h), 'seconds', h.seconds, 'instant', h.kind in ('pass', 'service'),
    'hustle_kind', h.kind,
    'pay_min', round(h.pay_min * v_pm), 'pay_max', round(h.pay_max * v_pm),
    'cap_left', case when h.daily_cap > 0 then greatest(0, h.daily_cap - v_n) end,
    'cooldown_until', v_cool,
    'note', nullif(h.req_text, ''),
    'locked', v_why->>'short');
end $$;

-- Money out: cash first, then bank, with ledger lines. Returns the cash / bank split.
create or replace function public.bl_hustle_charge(p_uid uuid, p_amount bigint, p_reason text, p_meta jsonb) returns jsonb
language plpgsql set search_path = public as $$
declare v_me profiles; v_cash bigint; v_bank bigint;
begin
  if coalesce(p_amount, 0) <= 0 then return jsonb_build_object('cash', 0, 'bank', 0); end if;
  select * into v_me from profiles where id = p_uid;
  if v_me.cash + v_me.bank < p_amount then
    raise exception 'That costs %. You have % (cash + bank).', bl_naira(p_amount), bl_naira(v_me.cash + v_me.bank)
      using errcode = 'P0001', hint = 'not_enough_money';
  end if;
  v_cash := least(v_me.cash, p_amount);
  v_bank := p_amount - v_cash;
  if v_cash > 0 then perform bl_add_money(p_uid, 'cash', -v_cash, p_reason, p_meta); end if;
  if v_bank > 0 then perform bl_add_money(p_uid, 'bank', -v_bank, p_reason, p_meta); end if;
  return jsonb_build_object('cash', v_cash, 'bank', v_bank);
end $$;

create or replace function public.bl_hustle_run_json(r public.hustle_runs) returns jsonb
language sql stable set search_path = public as $$
  select case when r.id is null then null else jsonb_build_object(
    'id', r.id, 'hustle_id', r.hustle_id, 'name', (select name from hustles where id = r.hustle_id),
    'icon', (select icon from hustles where id = r.hustle_id), 'started_at', r.started_at, 'resolve_at', r.resolve_at,
    'status', r.status, 'cost', r.cost, 'amount', r.amount, 'outcome', r.outcome) end;
$$;

-- Resolve one running hustle (the server roll). Order of rolls: loss (fraud), risk (network / cancel), bonus, then the pay or the fish.
-- Locks the run and the profile.
create or replace function public.bl_hustle_resolve(p_id bigint) returns jsonb
language plpgsql set search_path = public as $$
declare
  r        hustle_runs;
  h        hustles;
  v_now    timestamptz := bl_now();
  v_pay    bigint := 0;
  v_net    bigint;
  v_out    text := 'ok';
  v_loss   bigint := 0;
  v_bonus  bigint := 0;
  v_fish   record;
  v_total  numeric;
  v_pick   numeric;
  v_acc    numeric := 0;
  v_fish_j jsonb;
  v_msg    text;
  v_place  text;
  v_loc    locations;
  v_me     profiles;
begin
  select * into r from hustle_runs where id = p_id for update;
  if not found then return jsonb_build_object('status', 'none'); end if;
  if r.status <> 'running' then
    return jsonb_build_object('status', r.status, 'already', true, 'amount', r.amount, 'hustle_id', r.hustle_id, 'outcome', r.outcome);
  end if;
  perform 1 from profiles where id = r.user_id for update;
  select * into h from hustles where id = r.hustle_id;
  select * into v_me from profiles where id = r.user_id;
  select * into v_loc from locations where id = r.location_id;
  v_place := regexp_replace(coalesce(v_loc.name, ''), '\s*\(.*\)\s*$', '');
  perform bl_hustle_row(r.user_id, true);

  if h.kind = 'fishing' then
    -- the roll for "nothing bit", then a weighted fish
    if h.risk_pct > 0 and bl_rand() * 100 < h.risk_pct then
      v_out := 'risk';
      v_msg := coalesce(nullif(h.risk_text, ''), 'Nothing bit.');
    else
      select coalesce(sum(f.weight), 0) into v_total from hustle_fish f where f.active;
      v_pick := bl_rand() * v_total;
      for v_fish in select f.item_id, f.weight, it.name, it.icon, it.price
                      from hustle_fish f join items it on it.id = f.item_id where f.active order by f.sort, f.item_id loop
        v_acc := v_acc + v_fish.weight;
        if v_pick < v_acc then
          v_fish_j := jsonb_build_object('item', v_fish.item_id, 'name', v_fish.name, 'icon', v_fish.icon, 'value', v_fish.price);
          exit;
        end if;
      end loop;
      if v_fish_j is null then
        select f.item_id, it.name, it.icon, it.price into v_fish
          from hustle_fish f join items it on it.id = f.item_id where f.active order by f.sort desc, f.item_id desc limit 1;
        if found then
          v_fish_j := jsonb_build_object('item', v_fish.item_id, 'name', v_fish.name, 'icon', v_fish.icon, 'value', v_fish.price);
        end if;
      end if;
      if v_fish_j is null then
        v_out := 'risk';
        v_msg := 'Nothing bit.';
      else
        perform bl_give_item(r.user_id, v_fish_j->>'item', 1);
        v_pay := (v_fish_j->>'value')::bigint;
        v_msg := 'You caught a ' || (v_fish_j->>'name') || '! Worth about ' || bl_naira(v_pay) || ' at the market.';
      end if;
    end if;
  else
    v_pay := h.pay_min + floor(bl_rand() * (greatest(h.pay_max, h.pay_min) - h.pay_min + 1))::bigint;
    v_pay := greatest(0, round(v_pay * r.pay_mult / 100.0) * 100)::bigint;
    if h.loss_pct > 0 and bl_rand() * 100 < h.loss_pct then
      v_out := 'loss';
      v_pay := 0;
      v_loss := h.loss_min + floor(bl_rand() * (greatest(h.loss_max, h.loss_min) - h.loss_min + 1))::bigint;
      select * into v_me from profiles where id = r.user_id;
      v_loss := least(v_loss, v_me.cash + v_me.bank);
      if v_loss > 0 then
        perform bl_hustle_charge(r.user_id, v_loss, 'hustle_loss', jsonb_build_object('hustle', h.id, 'name', h.name, 'run_id', r.id));
      end if;
      v_msg := coalesce(nullif(h.loss_text, ''), 'Something went wrong.') || case when v_loss > 0 then ' (−' || bl_naira(v_loss) || ')' else '' end;
    elsif h.risk_pct > 0 and bl_rand() * 100 < h.risk_pct then
      v_out := 'risk';
      v_pay := greatest(0, round(v_pay * h.risk_pay_mult / 100.0) * 100)::bigint;
      v_msg := coalesce(nullif(h.risk_text, ''), 'Bad luck.') || case when v_pay > 0 then ' +' || bl_naira(v_pay) else '' end;
    else
      if h.bonus_pct > 0 and bl_rand() * 100 < h.bonus_pct then
        v_out := 'bonus';
        v_bonus := h.bonus_min + floor(bl_rand() * (greatest(h.bonus_max, h.bonus_min) - h.bonus_min + 1))::bigint;
        v_bonus := greatest(0, round(v_bonus / 100.0) * 100)::bigint;
        v_pay := v_pay + v_bonus;
      end if;
      v_msg := h.name || ' done: +' || bl_naira(v_pay) || '.'
               || case when v_bonus > 0 then ' ' || coalesce(nullif(h.bonus_text, ''), 'Bonus!') || ' (+' || bl_naira(v_bonus) || ')' else '' end;
    end if;
    if v_pay > 0 then
      perform bl_add_money(r.user_id, 'cash', v_pay, 'hustle', jsonb_build_object('hustle', h.id, 'name', h.name, 'run_id', r.id, 'outcome', v_out));
    end if;
  end if;

  v_net := case when h.kind = 'fishing' then 0 else v_pay end;
  if h.cred_gain <> 0 and v_out in ('ok', 'bonus') then
    update profiles set street_cred = greatest(0, street_cred + h.cred_gain) where id = r.user_id;
  end if;
  -- DJ / MC: the club hears about it
  if h.kind in ('dj', 'mc') and coalesce(h.hype_text, '') <> '' and v_loc.scene = 'club' and v_out in ('ok', 'bonus') then
    insert into place_announcements (location_id, user_id, username, kind, amount, qty, text, place)
    values (r.location_id, r.user_id, v_me.username, 'shoutout', 0, 1,
            left(replace(h.hype_text, '{name}', '@' || v_me.username), 400), v_place);
  end if;
  update hustle_players set total_earned = total_earned + v_net, runs_done = runs_done + 1, updated_at = v_now where user_id = r.user_id;
  update hustle_runs set status = 'done', amount = v_pay, outcome = v_out, resolved_at = v_now,
         detail = jsonb_build_object('loss', v_loss, 'bonus', v_bonus, 'fish', v_fish_j, 'message', v_msg)
   where id = r.id;
  update profiles set busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
   where id = r.user_id and busy_label like 'Hustle:%';
  perform bl_referral_check(r.user_id);
  return jsonb_build_object('status', 'done', 'hustle_id', h.id, 'name', h.name, 'icon', h.icon, 'kind', h.kind, 'outcome', v_out,
                            'amount', v_pay, 'cost', r.cost, 'net', v_pay - case when h.kind = 'fishing' then 0 else r.cost end,
                            'loss', v_loss, 'bonus', v_bonus, 'fish', v_fish_j, 'message', v_msg);
end $$;

create or replace function public.bl_hustle_ledger_label(p_reason text, p_meta jsonb) returns text
language sql immutable as $$
  select case p_reason
    when 'hustle' then 'Hustle: ' || coalesce(nullif(p_meta->>'name', ''), 'side hustle')
    when 'hustle_cost' then coalesce(nullif(p_meta->>'label', ''), 'Hustle costs')
    when 'hustle_loss' then 'Hustle loss: ' || coalesce(nullif(p_meta->>'name', ''), 'side hustle')
    when 'hustle_pass' then coalesce(nullif(p_meta->>'label', ''), 'Hustle pass')
    when 'hustle_service' then 'Car service'
    when 'referral' then 'Referral bonus'
    when 'weekly_prize' then 'Weekly top earners prize'
    when 'tip_out' then 'Tip to @' || coalesce(nullif(p_meta->>'to_username', ''), 'player')
    when 'tip_in' then 'Tip from @' || coalesce(nullif(p_meta->>'from_username', ''), 'player')
    else null end;
$$;

revoke all on function public.bl_hustle_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_hustle_text(text, text) from public, anon, authenticated;
revoke all on function public.bl_hustle_on(text, boolean) from public, anon, authenticated;
revoke all on function public.bl_hustle_row(uuid, boolean) from public, anon, authenticated;
revoke all on function public.bl_hustle_day_start() from public, anon, authenticated;
revoke all on function public.bl_hustle_hour() from public, anon, authenticated;
revoke all on function public.bl_hustle_runs_today(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_hustle_pass_until(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_hustle_car(uuid) from public, anon, authenticated;
revoke all on function public.bl_hustle_hour_mult(public.hustles) from public, anon, authenticated;
revoke all on function public.bl_hustle_window_label(public.hustles) from public, anon, authenticated;
revoke all on function public.bl_hustle_why(public.profiles, public.hustles, public.locations, boolean) from public, anon, authenticated;
revoke all on function public.bl_hustle_cost(uuid, public.hustles) from public, anon, authenticated;
revoke all on function public.bl_hustle_pay_mult(uuid, public.hustles) from public, anon, authenticated;
revoke all on function public.bl_hustle_places(public.hustles, public.locations) from public, anon, authenticated;
revoke all on function public.bl_hustle_json(public.profiles, public.hustles, public.locations) from public, anon, authenticated;
revoke all on function public.bl_hustle_card(public.profiles, public.hustles, public.locations, text, text, text) from public, anon, authenticated;
revoke all on function public.bl_hustle_charge(uuid, bigint, text, jsonb) from public, anon, authenticated;
revoke all on function public.bl_hustle_run_json(public.hustle_runs) from public, anon, authenticated;
revoke all on function public.bl_hustle_resolve(bigint) from public, anon, authenticated;
revoke all on function public.bl_hustle_ledger_label(text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 7. Referral helpers
-- ---------------------------------------------------------------------------------------------
-- My referral code (made on first use; 7 upper-case hex characters).
create or replace function public.bl_referral_code(p_uid uuid) returns text
language plpgsql set search_path = public as $$
declare v text; n int := 0;
begin
  select code into v from referral_codes where user_id = p_uid;
  if v is not null then return v; end if;
  loop
    v := upper(substr(md5(random()::text || p_uid::text || clock_timestamp()::text || n::text), 1, 7));
    begin
      insert into referral_codes (user_id, code) values (p_uid, v) on conflict (user_id) do nothing;
      select code into v from referral_codes where user_id = p_uid;
      exit;
    exception when unique_violation then
      n := n + 1;
      if n > 20 then raise; end if;
    end;
  end loop;
  return v;
end $$;

-- How far the new player is: {shifts, hustles, play_minutes, need_*, met, pct}.
create or replace function public.bl_referral_progress(p_referred uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_sh int := coalesce((select job_total_shifts from profiles where id = p_referred), 0);
  v_hu int := (select count(*)::int from hustle_runs where user_id = p_referred and status = 'done');
  v_pl int := coalesce((select play_seconds from referrals where referred_id = p_referred), 0);
  n_sh int := bl_hustle_num('referral.min_shifts', 1)::int;
  n_hu int := bl_hustle_num('referral.min_hustles', 3)::int;
  n_pl int := (bl_hustle_num('referral.play_minutes', 60) * 60)::int;
  v_met boolean;
  v_pct numeric := 0;
begin
  v_met := (n_sh > 0 and v_sh >= n_sh) or (n_hu > 0 and v_hu >= n_hu) or (n_pl > 0 and v_pl >= n_pl);
  v_pct := greatest(case when n_sh > 0 then least(1, v_sh::numeric / n_sh) else 0 end,
                    case when n_hu > 0 then least(1, v_hu::numeric / n_hu) else 0 end,
                    case when n_pl > 0 then least(1, v_pl::numeric / n_pl) else 0 end);
  return jsonb_build_object('shifts', v_sh, 'need_shifts', n_sh, 'hustles', v_hu, 'need_hustles', n_hu,
                            'play_minutes', floor(v_pl / 60.0), 'need_minutes', n_pl / 60, 'met', v_met, 'pct', round(v_pct * 100));
end $$;

-- If the new player reached the milestone, pay both sides once. Returns the paid amounts or null.
create or replace function public.bl_referral_check(p_referred uuid) returns jsonb
language plpgsql set search_path = public as $$
declare
  r      referrals;
  v_prog jsonb;
  v_b1   bigint := greatest(0, bl_hustle_num('referral.bonus_referrer', 20000))::bigint;
  v_b2   bigint := greatest(0, bl_hustle_num('referral.bonus_referred', 20000))::bigint;
  v_n1   text;
  v_n2   text;
  v_ban  boolean;
begin
  if not bl_hustle_on('referral.enabled', true) then return null; end if;
  select * into r from referrals where referred_id = p_referred and status = 'pending' for update;
  if not found then return null; end if;
  v_prog := bl_referral_progress(p_referred);
  if not (v_prog->>'met')::boolean then return null; end if;
  select banned, username into v_ban, v_n1 from profiles where id = r.referrer_id;
  select username into v_n2 from profiles where id = p_referred;
  if v_ban is null or v_ban then
    update referrals set status = 'rejected', reason = 'referrer_banned' where id = r.id;
    return null;
  end if;
  update referrals set status = 'rewarded', rewarded_at = bl_now(), bonus_referrer = v_b1, bonus_referred = v_b2 where id = r.id;
  if v_b1 > 0 then
    perform bl_add_money(r.referrer_id, 'cash', v_b1, 'referral', jsonb_build_object('role', 'inviter', 'friend', v_n2, 'referral_id', r.id));
  end if;
  if v_b2 > 0 then
    perform bl_add_money(p_referred, 'cash', v_b2, 'referral', jsonb_build_object('role', 'new_player', 'friend', v_n1, 'referral_id', r.id));
  end if;
  perform bl_event(r.referrer_id, 'referral_bonus', 'Referral bonus: ' || bl_naira(v_b1),
                   '@' || v_n2 || ' reached the milestone. ' || bl_naira(v_b1) || ' cash for you. Thanks for bringing am to Benin Life!',
                   jsonb_build_object('amount', v_b1, 'friend', v_n2));
  perform bl_event(p_referred, 'referral_bonus', 'Welcome bonus: ' || bl_naira(v_b2),
                   'You reached the milestone, so you and @' || v_n1 || ' both get a bonus. ' || bl_naira(v_b2) || ' cash for you.',
                   jsonb_build_object('amount', v_b2, 'friend', v_n1));
  return jsonb_build_object('referrer', v_b1, 'referred', v_b2);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Weekly earnings helpers
-- ---------------------------------------------------------------------------------------------
-- The Monday (Benin time) of the ISO week the instant falls in.
create or replace function public.bl_week_start(p_at timestamptz default null) returns date
language sql stable set search_path = public as $$
  select date_trunc('week', coalesce(p_at, bl_now()) at time zone 'Africa/Lagos')::date;
$$;

create or replace function public.bl_week_from(p_week date) returns timestamptz
language sql immutable as $$
  select p_week::timestamp at time zone 'Africa/Lagos';
$$;

create or replace function public.bl_earn_reasons() returns text[]
language sql stable set search_path = public as $$
  select coalesce(array(select btrim(x) from unnest(string_to_array(bl_hustle_text('leaderboard.earn_reasons', 'salary,hustle,harvest,farm_harvest,invest_income'), ',')) x where btrim(x) <> ''), '{}');
$$;

-- Ranking for one week: money EARNED (positive ledger rows whose reason is in leaderboard.earn_reasons).
create or replace function public.bl_weekly_ranked(p_week date)
returns table (id uuid, username text, avatar jsonb, origin text, total bigint, rank bigint)
language plpgsql stable set search_path = public as $$
declare v_hide boolean := coalesce((select (value #>> '{}')::boolean from game_config where key = 'leaderboard.hide_admins'), true);
begin
  return query
  with e as (
    select l.user_id, sum(l.delta)::bigint as total
      from ledger l
     where l.delta > 0 and l.reason = any (bl_earn_reasons())
       and l.created_at >= bl_week_from(p_week) and l.created_at < bl_week_from(p_week + 7)
     group by l.user_id
  )
  select p.id, p.username, p.avatar, p.origin, e.total,
         row_number() over (order by e.total desc, p.created_at, p.id)
    from e join profiles p on p.id = e.user_id
   where not p.banned and (not v_hide or not p.is_admin);
end $$;

-- Settle every week that has closed and was never settled (the first call after the week ends does it; the unique week row
-- makes it idempotent). Weeks before the feature existed are marked skipped by the migration. Returns the weeks settled now.
create or replace function public.bl_weekly_settle() returns jsonb
language plpgsql set search_path = public as $$
declare
  v_cur   date := bl_week_start();
  v_last  date;
  v_from  date;
  w       date;
  n       int;
  r       record;
  v_prize bigint;
  v_min   bigint := greatest(0, bl_hustle_num('leaderboard.weekly_min_earned', 20000))::bigint;
  v_id    bigint;
  v_out   jsonb := '[]'::jsonb;
  v_count int;
  v_total numeric;
  v_title text;
  v_body  text;
begin
  if not bl_hustle_on('leaderboard.weekly_enabled', true) then return v_out; end if;
  select max(week_start) into v_last from weekly_earn_weeks;
  v_from := greatest(coalesce(v_last + 7, v_cur - 7), v_cur - 56);
  for w in select generate_series(v_from, v_cur - 7, interval '7 days')::date loop
    insert into weekly_earn_weeks (week_start, settled_at) values (w, bl_now()) on conflict (week_start) do nothing;
    get diagnostics n = row_count;
    if n = 0 then continue; end if;
    for r in select * from bl_weekly_ranked(w) where rank <= 3 and total >= v_min order by rank loop
      v_prize := greatest(0, bl_hustle_num('leaderboard.weekly_prize_' || r.rank, 0))::bigint;
      insert into weekly_earn_winners (week_start, rank, user_id, username, total, prize, paid_at)
      values (w, r.rank::int, r.id, r.username, r.total, v_prize, case when v_prize > 0 then bl_now() end);
      if v_prize > 0 then
        perform bl_add_money(r.id, 'bank', v_prize, 'weekly_prize', jsonb_build_object('week', w, 'rank', r.rank, 'earned', r.total));
      end if;
      v_title := case r.rank when 1 then '🥇 You are the top earner of the week!' when 2 then '🥈 2nd top earner of the week!' else '🥉 3rd top earner of the week!' end;
      v_body := 'You earned ' || bl_naira(r.total) || ' in the week of ' || to_char(w, 'DD Mon') || '.'
                || case when v_prize > 0 then ' Prize: ' || bl_naira(v_prize) || ' is in your bank.' else '' end;
      insert into broadcasts (kind, title, body, style, audience, popup, expires_at, targeted, target_count, created_by)
      values ('message', v_title, v_body, 'celebration', 'online', true, bl_now() + interval '7 days', true, 1, null)
      returning id into v_id;
      insert into broadcast_reads (broadcast_id, user_id) values (v_id, r.id);
      perform bl_broadcast_bump(v_id);
      perform bl_event(r.id, 'weekly_prize', v_title, v_body, jsonb_build_object('week', w, 'rank', r.rank, 'prize', v_prize));
    end loop;
    select count(*), coalesce(sum(total), 0) into v_count, v_total from bl_weekly_ranked(w);
    update weekly_earn_weeks set total_players = v_count, total_earned = v_total where week_start = w;
    v_out := v_out || to_jsonb(w);
  end loop;
  return v_out;
end $$;

revoke all on function public.bl_referral_code(uuid) from public, anon, authenticated;
revoke all on function public.bl_referral_progress(uuid) from public, anon, authenticated;
revoke all on function public.bl_referral_check(uuid) from public, anon, authenticated;
revoke all on function public.bl_week_start(timestamptz) from public, anon, authenticated;
revoke all on function public.bl_week_from(date) from public, anon, authenticated;
revoke all on function public.bl_earn_reasons() from public, anon, authenticated;
revoke all on function public.bl_weekly_ranked(date) from public, anon, authenticated;
revoke all on function public.bl_weekly_settle() from public, anon, authenticated;

-- the week the feature started: the week that just closed is not paid retroactively
insert into public.weekly_earn_weeks (week_start, settled_at, skipped)
select public.bl_week_start() - 7, now(), true
 where not exists (select 1 from public.weekly_earn_weeks)
on conflict (week_start) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 9. Player RPCs: hustles
-- ---------------------------------------------------------------------------------------------
-- Everything the Hustles app needs; also finishes a hustle whose time is up (after a reload / on login).
create or replace function public.hustle_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_me   profiles;
  v_loc  locations;
  r      hustle_runs;
  v_res  jsonb;
  y      hustle_players;
  v_car  jsonb;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    return jsonb_build_object('enabled', false, 'run', null);
  end if;
  perform bl_weekly_settle();
  select * into r from hustle_runs where user_id = v_uid and status = 'running' order by id desc limit 1;
  if found and r.resolve_at <= bl_now() then
    v_res := bl_hustle_resolve(r.id);
    r := null;
    select * into v_me from profiles where id = v_uid;
  end if;
  select * into v_loc from locations where id = v_me.location_id;
  y := bl_hustle_row(v_uid);
  v_car := bl_hustle_car(v_uid);
  return jsonb_build_object(
    'enabled', bl_hustle_on('hustles.enabled', true),
    'cash', v_me.cash, 'bank', v_me.bank,
    'total_earned', y.total_earned, 'runs_done', y.runs_done,
    'car', case when v_car is null then null else v_car || jsonb_build_object('wear', y.car_wear) end,
    'classes', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'icon', icon, 'min_price', min_price, 'pay_mult', pay_mult) order by min_price)
                           from hustle_car_classes), '[]'::jsonb),
    'location', v_me.location_id,
    'hustles', coalesce((select jsonb_agg(bl_hustle_json(v_me, h, v_loc) order by h.sort, h.id) from hustles h where h.active), '[]'::jsonb),
    'run', bl_hustle_run_json(r),
    'resolved', v_res,
    'history', coalesce((select jsonb_agg(bl_hustle_run_json(x) order by x.id desc)
                           from (select * from hustle_runs where user_id = v_uid and status = 'done' order by id desc limit 8) x), '[]'::jsonb));
end $$;
revoke all on function public.hustle_status() from public, anon;
grant execute on function public.hustle_status() to authenticated, service_role;

-- Start a hustle (a timed action with a live bar). Everything is checked on the server.
create or replace function public.hustle_start(p_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  h       hustles;
  l       locations;
  v_why   jsonb;
  v_now   timestamptz := bl_now();
  v_until timestamptz;
  v_cost  bigint;
  v_pm    numeric;
  v_id    bigint;
  v_old   hustle_runs;
  v_car   jsonb;
begin
  if not bl_hustle_on('hustles.enabled', true) then
    raise exception 'Hustles are switched off for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into h from hustles where id = p_id and active;
  if not found or h.kind in ('pass', 'service') then
    raise exception 'No such hustle.' using errcode = 'P0001', hint = 'bad_hustle';
  end if;
  perform 1 from profiles where id = v_me.id for update;
  v_me := bl_me();
  -- an overdue hustle the client never finished: settle it first
  select * into v_old from hustle_runs where user_id = v_me.id and status = 'running' order by id desc limit 1;
  if found and v_old.resolve_at <= v_now then
    perform bl_hustle_resolve(v_old.id);
    v_me := bl_me();
  end if;
  perform bl_assert_free(v_me);
  if exists (select 1 from hustle_runs where user_id = v_me.id and status = 'running') then
    raise exception 'Finish the hustle you dey do first.' using errcode = 'P0001', hint = 'busy';
  end if;
  perform bl_hustle_row(v_me.id, true);
  select * into l from locations where id = v_me.location_id;
  v_why := bl_hustle_why(v_me, h, l, true);
  if v_why is not null then
    raise exception '%', v_why->>'message' using errcode = 'P0001', hint = v_why->>'hint';
  end if;
  v_cost := bl_hustle_cost(v_me.id, h);
  v_pm := bl_hustle_pay_mult(v_me.id, h);
  if v_cost > 0 then
    if v_me.cash + v_me.bank < v_cost then
      raise exception '% costs % to start (%). You have % (cash + bank).', h.name, bl_naira(v_cost),
        case h.kind when 'bolt' then 'fuel' when 'vending' then 'ingredients' when 'fishing' then 'bait' when 'mechanic' then 'parts' else 'costs' end,
        bl_naira(v_me.cash + v_me.bank) using errcode = 'P0001', hint = 'not_enough_money';
    end if;
    perform bl_hustle_charge(v_me.id, v_cost, 'hustle_cost',
      jsonb_build_object('hustle', h.id, 'label', case h.kind when 'bolt' then 'Fuel: ' when 'vending' then 'Ingredients: ' when 'fishing' then 'Bait: '
                                                    when 'mechanic' then 'Parts: ' else 'Hustle costs: ' end || h.name));
  end if;
  if h.kind = 'bolt' then
    v_car := bl_hustle_car(v_me.id);
    update hustle_players set car_wear = least(100, car_wear + h.wear_pct * coalesce((v_car->>'wear_mult')::numeric, 1)), updated_at = v_now
     where user_id = v_me.id;
  end if;
  if h.effects <> '{}'::jsonb then
    perform bl_adjust_needs(v_me.id, h.effects);
  end if;
  v_until := v_now + make_interval(secs => h.seconds);
  insert into hustle_runs (user_id, hustle_id, location_id, started_at, resolve_at, cost, pay_mult)
  values (v_me.id, h.id, v_me.location_id, v_now, v_until, v_cost, v_pm)
  returning id into v_id;
  -- can't be stopped halfway (busy_needs_from stays null, so activity_stop refuses)
  update profiles set busy_until = v_until, busy_started_at = v_now, busy_label = 'Hustle: ' || h.name, busy_needs_from = null
   where id = v_me.id;
  return jsonb_build_object('run_id', v_id, 'busy_until', v_until, 'resolve_at', v_until, 'seconds', h.seconds, 'hustle_id', h.id,
                            'name', h.name, 'icon', h.icon, 'cost', v_cost, 'started_at', v_now,
                            'message', h.name || '… e don start.');
end $$;
revoke all on function public.hustle_start(text) from public, anon;
grant execute on function public.hustle_start(text) to authenticated, service_role;

-- Roll my running hustle once its timer is over.
create or replace function public.hustle_finish() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  r hustle_runs;
begin
  perform bl_me_any();
  select * into r from hustle_runs where user_id = v_uid and status = 'running' order by id desc limit 1;
  if not found then
    raise exception 'You are not doing any hustle right now.' using errcode = 'P0001', hint = 'no_run';
  end if;
  if r.resolve_at > bl_now() then
    raise exception 'Hold on, about % sec more.', ceil(extract(epoch from r.resolve_at - bl_now()))::int using errcode = 'P0001', hint = 'not_yet';
  end if;
  return bl_hustle_resolve(r.id);
end $$;
revoke all on function public.hustle_finish() from public, anon;
grant execute on function public.hustle_finish() to authenticated, service_role;

-- Instant buys: rent the food stall ('pass') or service my car ('service'). Cash first, then bank.
create or replace function public.hustle_buy(p_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  h       hustles;
  l       locations;
  v_why   jsonb;
  v_cost  bigint;
  v_until timestamptz;
  v_split jsonb;
begin
  if not bl_hustle_on('hustles.enabled', true) then
    raise exception 'Hustles are switched off for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into h from hustles where id = p_id and active and kind in ('pass', 'service');
  if not found then
    raise exception 'No such hustle.' using errcode = 'P0001', hint = 'bad_hustle';
  end if;
  perform 1 from profiles where id = v_me.id for update;
  v_me := bl_me();
  perform bl_assert_free(v_me);
  select * into l from locations where id = v_me.location_id;
  v_why := bl_hustle_why(v_me, h, l, true);
  if v_why is not null then
    raise exception '%', v_why->>'message' using errcode = 'P0001', hint = v_why->>'hint';
  end if;
  v_cost := bl_hustle_cost(v_me.id, h);
  if h.kind = 'pass' then
    v_split := bl_hustle_charge(v_me.id, v_cost, 'hustle_pass', jsonb_build_object('hustle', h.id, 'label', h.name));
    insert into hustle_passes (user_id, pass_id, until_at)
    values (v_me.id, h.pass_id, bl_now() + make_interval(hours => coalesce(h.pass_hours, 24)))
    on conflict (user_id, pass_id) do update
      set until_at = greatest(hustle_passes.until_at, bl_now()) + make_interval(hours => coalesce(h.pass_hours, 24))
    returning until_at into v_until;
    return jsonb_build_object('kind', 'pass', 'until', v_until, 'paid', v_cost,
                              'message', h.name || ' ready till ' || to_char(v_until at time zone 'Africa/Lagos', 'Dy FMHH12:MI AM') || '. Go sell!');
  end if;
  v_split := bl_hustle_charge(v_me.id, v_cost, 'hustle_service', jsonb_build_object('hustle', h.id));
  perform bl_hustle_row(v_me.id);
  update hustle_players set car_wear = 0, updated_at = bl_now() where user_id = v_me.id;
  return jsonb_build_object('kind', 'service', 'paid', v_cost, 'message', 'Car serviced for ' || bl_naira(v_cost) || '. Good as new.');
end $$;
revoke all on function public.hustle_buy(text) from public, anon;
grant execute on function public.hustle_buy(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 10. Player RPCs: referral
-- ---------------------------------------------------------------------------------------------
-- A new player uses someone's code (right after the Sim is created). Refusals carry a hint; the client stays silent about them.
create or replace function public.referral_claim(p_code text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me_any();
  v_code  text;
  v_ref   uuid;
  v_n     int;
  v_id    bigint;
begin
  if not bl_hustle_on('referral.enabled', true) then
    raise exception 'Referral bonuses are switched off for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  v_code := upper(btrim(coalesce(nullif(btrim(p_code), ''),
                                 (select raw_user_meta_data->>'referral_code' from auth.users where id = v_me.id), '')));
  if v_code = '' then
    raise exception 'No referral code.' using errcode = 'P0001', hint = 'no_code';
  end if;
  if v_code !~ '^[A-Z0-9]{4,12}$' then
    raise exception 'That referral code does not look right.' using errcode = 'P0001', hint = 'bad_code';
  end if;
  if exists (select 1 from referrals where referred_id = v_me.id) then
    raise exception 'You already used a referral code.' using errcode = 'P0001', hint = 'already_referred';
  end if;
  select user_id into v_ref from referral_codes where code = v_code;
  if v_ref is null then
    raise exception 'That referral code does not exist.' using errcode = 'P0001', hint = 'bad_code';
  end if;
  if v_ref = v_me.id then
    raise exception 'You can''t refer yourself.' using errcode = 'P0001', hint = 'self';
  end if;
  if v_me.created_at < bl_now() - make_interval(hours => greatest(1, bl_hustle_num('referral.max_account_age_hours', 48))::int) then
    raise exception 'Referral codes are for brand-new accounts only.' using errcode = 'P0001', hint = 'too_late';
  end if;
  if exists (select 1 from profiles where id = v_ref and banned) then
    raise exception 'That referral code is not active.' using errcode = 'P0001', hint = 'bad_code';
  end if;
  -- serialize this inviter's claims so the caps hold under parallel sign-ups
  perform 1 from profiles where id = v_ref for update;
  select count(*)::int into v_n from referrals where referrer_id = v_ref and created_at >= bl_hustle_day_start();
  if v_n >= greatest(1, bl_hustle_num('referral.daily_cap', 5))::int then
    raise exception 'That inviter has reached today''s referral limit. Try again tomorrow.' using errcode = 'P0001', hint = 'capped';
  end if;
  select count(*)::int into v_n from referrals where referrer_id = v_ref;
  if v_n >= greatest(1, bl_hustle_num('referral.max_total', 100))::int then
    raise exception 'That inviter has reached the referral limit.' using errcode = 'P0001', hint = 'capped';
  end if;
  insert into referrals (referrer_id, referred_id, code, created_at, last_ping) values (v_ref, v_me.id, v_code, bl_now(), bl_now()) returning id into v_id;
  perform bl_referral_check(v_me.id);
  return jsonb_build_object('ok', true, 'referral_id', v_id,
    'message', 'Referral accepted. Reach the milestone and you and your inviter both get a bonus.');
end $$;
revoke all on function public.referral_claim(text) from public, anon;
grant execute on function public.referral_claim(text) to authenticated, service_role;

-- My referral card: code, link, my invitees, and (when I was invited) my own progress. Also the play-time check-in.
create or replace function public.referral_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_code  text;
  v_base  text := regexp_replace(bl_hustle_text('referral.base_url', 'https://playbeninlife.app'), '/+$', '');
  rf      referrals;
  v_by    jsonb;
begin
  perform 1 from profiles where id = v_uid;
  if not found then
    return jsonb_build_object('enabled', false);
  end if;
  -- check-in: a pending new player earns play time (at most 5 minutes per check-in)
  update referrals set play_seconds = play_seconds + least(300, greatest(0, floor(extract(epoch from bl_now() - coalesce(last_ping, bl_now()))))::int),
                       last_ping = bl_now()
   where referred_id = v_uid and status = 'pending';
  perform bl_referral_check(v_uid);
  v_code := bl_referral_code(v_uid);
  select * into rf from referrals where referred_id = v_uid;
  if found then
    v_by := jsonb_build_object('username', (select username from profiles where id = rf.referrer_id), 'status', rf.status, 'bonus', rf.bonus_referred,
                               'progress', bl_referral_progress(v_uid), 'created_at', rf.created_at, 'rewarded_at', rf.rewarded_at);
  end if;
  return jsonb_build_object(
    'enabled', bl_hustle_on('referral.enabled', true),
    'code', v_code, 'link', v_base || '/?ref=' || v_code,
    'bonus_referrer', bl_hustle_num('referral.bonus_referrer', 20000), 'bonus_referred', bl_hustle_num('referral.bonus_referred', 20000),
    'daily_cap', bl_hustle_num('referral.daily_cap', 5),
    'today', (select count(*) from referrals where referrer_id = v_uid and created_at >= bl_hustle_day_start()),
    'milestone', jsonb_build_object('shifts', bl_hustle_num('referral.min_shifts', 1), 'hustles', bl_hustle_num('referral.min_hustles', 3),
                                    'minutes', bl_hustle_num('referral.play_minutes', 60)),
    'invited', (select count(*) from referrals where referrer_id = v_uid),
    'rewarded', (select count(*) from referrals where referrer_id = v_uid and status = 'rewarded'),
    'earned', coalesce((select sum(bonus_referrer) from referrals where referrer_id = v_uid and status = 'rewarded'), 0),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('username', p.username, 'status', x.status, 'created_at', x.created_at,
                                                            'rewarded_at', x.rewarded_at, 'progress', bl_referral_progress(x.referred_id)) order by x.id desc)
                        from (select * from referrals where referrer_id = v_uid order by id desc limit 30) x
                        join profiles p on p.id = x.referred_id), '[]'::jsonb),
    'referred_by', v_by);
end $$;
revoke all on function public.referral_status() from public, anon;
grant execute on function public.referral_status() to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 11. Player RPCs: weekly leaderboard and tips; admin overview
-- ---------------------------------------------------------------------------------------------
create or replace function public.weekly_leaderboard(p_limit int default 50) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_lim  int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_wk   date := bl_week_start();
  v_rows jsonb;
  v_me   jsonb;
  v_n    bigint;
  v_last date;
begin
  perform bl_weekly_settle();
  with r as materialized (select * from bl_weekly_ranked(v_wk))
  select (select count(*) from r),
         (select coalesce(jsonb_agg(jsonb_build_object('rank', r.rank, 'id', r.id, 'username', r.username, 'avatar', r.avatar,
                                                       'origin', r.origin, 'total', r.total, 'me', r.id = v_uid) order by r.rank), '[]'::jsonb)
            from r where r.rank <= v_lim),
         (select jsonb_build_object('rank', r.rank, 'id', r.id, 'username', r.username, 'avatar', r.avatar, 'origin', r.origin, 'total', r.total)
            from r where r.id = v_uid)
    into v_n, v_rows, v_me;
  if v_me is null then
    select jsonb_build_object('rank', null, 'id', p.id, 'username', p.username, 'avatar', p.avatar, 'origin', p.origin, 'total', 0)
      into v_me from profiles p where p.id = v_uid;
  end if;
  select max(week_start) into v_last from weekly_earn_winners;
  return jsonb_build_object(
    'enabled', bl_hustle_on('leaderboard.weekly_enabled', true),
    'week_start', v_wk, 'ends_at', bl_week_from(v_wk + 7), 'players', v_n,
    'rows', v_rows, 'me', v_me,
    'prizes', jsonb_build_array(
        jsonb_build_object('rank', 1, 'amount', bl_hustle_num('leaderboard.weekly_prize_1', 200000)),
        jsonb_build_object('rank', 2, 'amount', bl_hustle_num('leaderboard.weekly_prize_2', 100000)),
        jsonb_build_object('rank', 3, 'amount', bl_hustle_num('leaderboard.weekly_prize_3', 50000))),
    'min_earned', bl_hustle_num('leaderboard.weekly_min_earned', 20000),
    'reasons', to_jsonb(bl_earn_reasons()),
    'last_week', case when v_last is null then null else jsonb_build_object(
        'week_start', v_last,
        'winners', coalesce((select jsonb_agg(jsonb_build_object('rank', w.rank, 'username', w.username, 'total', w.total, 'prize', w.prize) order by w.rank)
                               from weekly_earn_winners w where w.week_start = v_last), '[]'::jsonb)) end);
end $$;
revoke all on function public.weekly_leaderboard(int) from public, anon;
grant execute on function public.weekly_leaderboard(int) to authenticated, service_role;

-- BENIN GIST HOOK: the Benin Gist app (built later) calls tip_player(username, amount, note) when a reader tips a creator.
-- Money moves bank-first from the tipper to the creator's bank; the ledger lines read "Tip to @x" / "Tip from @x".
create or replace function public.tip_player(p_username text, p_amount bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  r       profiles := bl_find_player(p_username);
  v_me    profiles;
  v_now   timestamptz := bl_now();
  v_min   bigint := greatest(1, bl_hustle_num('tips.min_amount', 100))::bigint;
  v_max   bigint := greatest(1, bl_hustle_num('tips.max_amount', 1000000))::bigint;
  v_day   bigint := greatest(1, bl_hustle_num('tips.daily_max', 5000000))::bigint;
  v_age   numeric := bl_hustle_num('bank.transfer_min_account_real_minutes', 0) * 60;
  v_sent  bigint;
  v_note  text;
  v_meta  jsonb;
  v_bank  bigint;
  v_cash  bigint;
  v_id    bigint;
begin
  if not bl_hustle_on('tips.enabled', true) then
    raise exception 'Tips are switched off for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  if r.id = v_uid then
    raise exception 'You can''t tip yourself.' using errcode = 'P0001', hint = 'self';
  end if;
  perform 1 from profiles where id in (v_uid, r.id) order by id for update;
  v_me := bl_me();
  if v_me.jailed_until is not null and v_me.jailed_until > v_now then
    raise exception 'The police took your phone. Tips can wait until you are out.' using errcode = 'P0001', hint = 'jailed';
  end if;
  if not coalesce(v_me.transfer_trusted, false) and v_age > 0 and extract(epoch from v_now - v_me.created_at) < v_age then
    raise exception 'New accounts can send money after % real minutes.', round(v_age / 60) using errcode = 'P0001', hint = 'limit';
  end if;
  if p_amount is null or p_amount < v_min then
    raise exception 'The smallest tip is %.', bl_naira(v_min) using errcode = 'P0001', hint = 'too_small';
  end if;
  if p_amount > v_max then
    raise exception 'The biggest tip is %.', bl_naira(v_max) using errcode = 'P0001', hint = 'too_big';
  end if;
  select coalesce(sum(amount), 0) into v_sent from tips where from_user = v_uid and created_at >= bl_hustle_day_start();
  if v_sent + p_amount > v_day then
    raise exception 'That is over your daily tip limit of %. You can still tip % today.', bl_naira(v_day), bl_naira(greatest(0, v_day - v_sent))
      using errcode = 'P0001', hint = 'limit';
  end if;
  if v_me.bank + v_me.cash < p_amount then
    raise exception 'You don''t have enough money for that tip.' using errcode = 'P0001', hint = 'not_enough_money';
  end if;
  v_note := nullif(left(btrim(regexp_replace(coalesce(p_note, ''), '[[:cntrl:][:space:]]+', ' ', 'g')), 80), '');
  v_meta := jsonb_build_object('to', r.id, 'to_username', r.username, 'from', v_me.id, 'from_username', v_me.username)
            || case when v_note is null then '{}'::jsonb else jsonb_build_object('note', v_note) end;
  v_bank := least(v_me.bank, p_amount);
  v_cash := p_amount - v_bank;
  if v_bank > 0 then perform bl_add_money(v_me.id, 'bank', -v_bank, 'tip_out', v_meta); end if;
  if v_cash > 0 then perform bl_add_money(v_me.id, 'cash', -v_cash, 'tip_out', v_meta); end if;
  perform bl_add_money(r.id, 'bank', p_amount, 'tip_in', v_meta);
  insert into tips (from_user, to_user, from_username, to_username, amount, note, created_at)
  values (v_me.id, r.id, v_me.username, r.username, p_amount, v_note, v_now) returning id into v_id;
  perform bl_event(r.id, 'tip_in', 'Tip from @' || v_me.username, bl_naira(p_amount) || ' landed in your bank.' || coalesce(' "' || v_note || '"', ''),
                   v_meta || jsonb_build_object('amount', p_amount));
  return jsonb_build_object('message', 'Tip of ' || bl_naira(p_amount) || ' sent to @' || r.username || '.', 'tip_id', v_id, 'amount', p_amount,
                            'to', jsonb_build_object('id', r.id, 'username', r.username));
end $$;
revoke all on function public.tip_player(text, bigint, text) from public, anon;
grant execute on function public.tip_player(text, bigint, text) to authenticated, service_role;

-- My tips, sent and received (newest first).
create or replace function public.tips_mine(p_limit int default 30) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'from', t.from_username, 'to', t.to_username, 'amount', t.amount, 'note', t.note,
                                               'mine', t.from_user = auth.uid(), 'created_at', t.created_at) order by t.id desc), '[]'::jsonb)
    from (select * from tips where auth.uid() is not null and (from_user = auth.uid() or to_user = auth.uid())
           order by id desc limit least(greatest(coalesce(p_limit, 30), 1), 100)) t;
$$;
revoke all on function public.tips_mine(int) from public, anon;
grant execute on function public.tips_mine(int) to authenticated, service_role;

-- Admin: referrals, weekly winners and tips in one read.
create or replace function public.admin_earn_overview(p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_lim int := least(greatest(coalesce(p_limit, 100), 1), 500);
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'referrals', jsonb_build_object(
      'total', (select count(*) from referrals), 'pending', (select count(*) from referrals where status = 'pending'),
      'rewarded', (select count(*) from referrals where status = 'rewarded'), 'rejected', (select count(*) from referrals where status = 'rejected'),
      'paid', coalesce((select sum(bonus_referrer + bonus_referred) from referrals where status = 'rewarded'), 0),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'inviter', a.username, 'inviter_id', x.referrer_id, 'new_player', b.username,
                                                              'new_id', x.referred_id, 'code', x.code, 'status', x.status, 'reason', x.reason,
                                                              'play_minutes', floor(x.play_seconds / 60.0), 'bonus_referrer', x.bonus_referrer,
                                                              'bonus_referred', x.bonus_referred, 'created_at', x.created_at, 'rewarded_at', x.rewarded_at) order by x.id desc)
                          from (select * from referrals order by id desc limit v_lim) x
                          join profiles a on a.id = x.referrer_id join profiles b on b.id = x.referred_id), '[]'::jsonb)),
    'weeks', coalesce((select jsonb_agg(jsonb_build_object('week_start', w.week_start, 'settled_at', w.settled_at, 'skipped', w.skipped,
                                                             'players', w.total_players, 'earned', w.total_earned,
                                                             'winners', coalesce((select jsonb_agg(jsonb_build_object('rank', x.rank, 'username', x.username, 'total', x.total, 'prize', x.prize) order by x.rank)
                                                                                    from weekly_earn_winners x where x.week_start = w.week_start), '[]'::jsonb)) order by w.week_start desc)
                         from (select * from weekly_earn_weeks order by week_start desc limit 26) w), '[]'::jsonb),
    'tips', jsonb_build_object(
      'total', (select count(*) from tips), 'amount', coalesce((select sum(amount) from tips), 0),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'from', t.from_username, 'to', t.to_username, 'amount', t.amount, 'note', t.note,
                                                              'created_at', t.created_at) order by t.id desc)
                          from (select * from tips order by id desc limit v_lim) t), '[]'::jsonb)));
end $$;
revoke all on function public.admin_earn_overview(int) from public, anon;
grant execute on function public.admin_earn_overview(int) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 12. Existing functions (guarded edits of the live definitions)
-- ---------------------------------------------------------------------------------------------
-- zone_actions: a new card kind 'hustle' (ref = hustles.id). The kind list is read from the live constraint.
do $$
declare v_con text; v_kinds text[];
begin
  select pg_get_constraintdef(oid) into v_con from pg_constraint
   where conrelid = 'public.zone_actions'::regclass and conname = 'zone_actions_kind_check';
  if v_con is null or position('hustle' in v_con) = 0 then
    select array_agg(m[1]) into v_kinds from regexp_matches(coalesce(v_con, ''), '''([a-z_]+)''::text', 'g') m;
    v_kinds := coalesce(v_kinds, array['activity', 'job', 'shop', 'panel', 'shrine']);
    v_kinds := array_append(v_kinds, 'hustle');
    alter table public.zone_actions drop constraint if exists zone_actions_kind_check;
    execute 'alter table public.zone_actions add constraint zone_actions_kind_check check (kind in ('
            || (select string_agg(quote_literal(k), ', ') from unnest(v_kinds) k) || '))';
  end if;
end $$;

-- bl_zone_action_check(): hustle cards point at a hustle.
do $$
declare v_def text; v_anchor text := '  elsif new.kind = ''panel''';
begin
  select pg_get_functiondef('public.bl_zone_action_check()'::regprocedure) into v_def;
  if position('hustles' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'E2: bl_zone_action_check() changed; update the hustles migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '  elsif new.kind = ''hustle'' and not exists (select 1 from hustles where id = new.ref) then' || chr(10)
    || '    raise exception ''Zone action %: no hustle "%".'', new.id, new.ref using errcode = ''P0001'', hint = ''bad_value'';' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

-- place_interior(): hustle cards (Bolt, PoS, stall, DJ / MC, tutoring, fishing, mechanic).
do $$
declare v_def text; v_anchor text := '               -- open a tab of the place sheet (bank counter, PoS, the whole shop...)';
begin
  select pg_get_functiondef('public.place_interior(text)'::regprocedure) into v_def;
  if position('bl_hustle_card' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'E2: place_interior() changed; update the hustles migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
'               -- E2 side hustles
               select za.sort, h.sort, bl_hustle_card(v_me, h, l, za.id, coalesce(za.label, h.name), coalesce(za.icon, h.icon))
                 from zone_actions za join hustles h on h.id = za.ref
                where za.zone_id = z.id and za.kind = ''hustle'' and za.active and h.active
               union all
' || v_anchor);
  execute v_def;
end $$;

-- bl_ledger_label(): Bank -> History lines.
do $$
declare v_def text; v_anchor text := '    when ''topup'' then';
begin
  select pg_get_functiondef('public.bl_ledger_label(text, jsonb)'::regprocedure) into v_def;
  if position('hustle_cost' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'E2: bl_ledger_label() changed; update the hustles migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''hustle'' then return bl_hustle_ledger_label(p_reason, p_meta);' || chr(10)
    || '    when ''hustle_cost'' then return bl_hustle_ledger_label(p_reason, p_meta);' || chr(10)
    || '    when ''hustle_loss'' then return bl_hustle_ledger_label(p_reason, p_meta);' || chr(10)
    || '    when ''hustle_pass'' then return bl_hustle_ledger_label(p_reason, p_meta);' || chr(10)
    || '    when ''hustle_service'' then return bl_hustle_ledger_label(p_reason, p_meta);' || chr(10)
    || '    when ''referral'' then return bl_hustle_ledger_label(p_reason, p_meta);' || chr(10)
    || '    when ''weekly_prize'' then return bl_hustle_ledger_label(p_reason, p_meta);' || chr(10)
    || '    when ''tip_out'' then return bl_hustle_ledger_label(p_reason, p_meta);' || chr(10)
    || '    when ''tip_in'' then return bl_hustle_ledger_label(p_reason, p_meta);' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

-- bl_admin_table_spec(): Admin -> Content -> Hustles, Car classes (Bolt), Fish.
do $$
declare v_def text; v_anchor text := '    when ''interaction_types'' then';
begin
  select pg_get_functiondef('public.bl_admin_table_spec(text)'::regprocedure) into v_def;
  if position('hustle_car_classes' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'E2: bl_admin_table_spec() changed; update the hustles migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''hustles'' then ''{"pk":["id"],"insert":true,"order":"sort, id",' || chr(10)
    || '      "cols":{"name":"text","icon":"text","blurb":"text","kind":"text","where_text":"text","req_text":"text","seconds":"int",' || chr(10)
    || '              "pay_min":"money","pay_max":"money","cost":"money","cooldown_seconds":"int","daily_cap":"int","effects":"obj",' || chr(10)
    || '              "location_ids":"arr","scenes":"arr","anywhere":"bool","hour_from":"num_null","hour_to":"num_null","needs_car":"bool",' || chr(10)
    || '              "req_item":"text_null","no_item_pay_mult":"num_null","needs_pass":"text_null","pass_id":"text_null","pass_hours":"int_null",' || chr(10)
    || '              "wear_pct":"num","risk_pct":"num","risk_pay_mult":"num","risk_text":"text","loss_pct":"num","loss_min":"money","loss_max":"money",' || chr(10)
    || '              "loss_text":"text","bonus_pct":"num","bonus_min":"money","bonus_max":"money","bonus_text":"text","cred_gain":"int",' || chr(10)
    || '              "hype_text":"text","hour_mult":"obj","sort":"int","active":"bool"}}''' || chr(10)
    || '    when ''hustle_car_classes'' then ''{"pk":["id"],"insert":true,"order":"min_price, sort, id",' || chr(10)
    || '      "cols":{"name":"text","icon":"text","min_price":"money","pay_mult":"num","fuel_mult":"num","wear_mult":"num","sort":"int"}}''' || chr(10)
    || '    when ''hustle_fish'' then ''{"pk":["item_id"],"insert":true,"order":"sort, item_id",' || chr(10)
    || '      "cols":{"weight":"num","sort":"int","active":"bool"}}''' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 13. Zones, cards and mood lines
-- ---------------------------------------------------------------------------------------------
-- Ikpoba River Bank (farm yard kit): the farm's cassava rows and tool shed are hidden here, the river bank is drawn instead.
insert into public.place_zones (id, scene, location_id, zone_key, label, icon, prop, x, z, w, d, rot, note, sort, active) values
('ikpoba_riverbank.rows',   null, 'ikpoba_riverbank', 'rows',   'Cassava rows', '🌱', 'crops', 6, 4, 7, 4, 0, null, 1, false),
('ikpoba_riverbank.shed',   null, 'ikpoba_riverbank', 'shed',   'Tool shed',    '🛖', 'shed', 13, 8, 2.6, 2, 0, null, 2, false),
('ikpoba_riverbank.river',  null, 'ikpoba_riverbank', 'river',  'Ikpoba River', '🌊', 'pool', 9.5, 2.6, 8, 3.4, 0, 'Brown water, slow current, the old bridge above you', 3, true),
('ikpoba_riverbank.bank',   null, 'ikpoba_riverbank', 'bank',   'Fishing spot', '🎣', 'bench', 5, 6.4, 3, 1.4, 0, 'Throw the line, wait small. Sell the catch at any market', 4, true),
('ikpoba_riverbank.kiosk',  null, 'ikpoba_riverbank', 'kiosk',  'Bait & tackle', '🪱', 'kiosk', 2.2, 2.2, 2.6, 1.6, 0, null, 5, true),
('ikpoba_riverbank.trees',  null, 'ikpoba_riverbank', 'trees',  'Shade trees',  '🌳', 'trees', 12.6, 7.6, 3.4, 3, 0, null, 6, true)
on conflict (id) do nothing;

-- Mechanic village (workshop hall kit): the bronze-casting furnace and display are hidden here.
insert into public.place_zones (id, scene, location_id, zone_key, label, icon, prop, x, z, w, d, rot, note, sort, active) values
('mechanic_village.display', null, 'mechanic_village', 'display', 'Bronze display', '🔥', 'display', 10, 2, 3, 1, 0, null, 1, false),
('mechanic_village.furnace', null, 'mechanic_village', 'furnace', 'Casting furnace', '🔥', 'furnace', 4, 3, 2.6, 2, 0, null, 2, false),
('mechanic_village.bay',     null, 'mechanic_village', 'bay',     'Repair bay', '🔧', 'cars', 6, 4.6, 7, 3.2, 0, 'Oga mechanic: "You wan work? Come, bring spanner."', 3, true),
('mechanic_village.parts',   null, 'mechanic_village', 'parts',   'Spare parts', '⚙️', 'crates', 12.4, 2.6, 3, 2.2, 0, null, 4, false)
on conflict (id) do nothing;

-- Oba Market: the rentable food stall
insert into public.place_zones (id, scene, location_id, zone_key, label, icon, prop, x, z, w, d, rot, note, sort, active) values
('oba_market.stall', null, 'oba_market', 'stall', 'Your food stall', '🏪', 'food_stall', 7, 5.8, 2.6, 1.8, 0, 'Rent the stall for the day, cook, and sell. Lunch and breakfast bring the crowd', 20, true)
on conflict (id) do nothing;

insert into public.zone_actions (id, zone_id, kind, ref, label, icon, sort) values
  ('motorpark.keke.bolt_shift',        'motorpark.keke',           'hustle', 'bolt_shift',     null, null, 9),
  ('street.corner.bolt_shift',         'street.corner',            'hustle', 'bolt_shift',     null, null, 9),
  ('market.traders.pos_agent',         'market.traders',           'hustle', 'pos_agent',      null, null, 8),
  ('market.traders.pos_machine',       'market.traders',           'shop',   'pos_machine',    null, null, 9),
  ('market.traders.fishing_rod',       'market.traders',           'shop',   'fishing_rod',    null, null, 10),
  ('pos.kiosk.pos_agent',              'pos.kiosk',                'hustle', 'pos_agent',      null, null, 8),
  ('pos.kiosk.pos_machine',            'pos.kiosk',                'shop',   'pos_machine',    null, null, 9),
  ('oba_market.stall.stall_rent',      'oba_market.stall',         'hustle', 'stall_rent',     null, null, 1),
  ('oba_market.stall.vend_jollof',     'oba_market.stall',         'hustle', 'vend_jollof',    null, null, 2),
  ('oba_market.stall.vend_puff',       'oba_market.stall',         'hustle', 'vend_puff',      null, null, 3),
  ('oba_market.stall.vend_fried_yam',  'oba_market.stall',         'hustle', 'vend_fried_yam', null, null, 4),
  ('club.dj.dj_set',                   'club.dj',                  'hustle', 'dj_set',         null, null, 8),
  ('club.dance.mc_gig',                'club.dance',               'hustle', 'mc_gig',         null, null, 8),
  ('campus.lecture.tutor_session',     'campus.lecture',           'hustle', 'tutor_session',  null, null, 8),
  ('ikpoba_riverbank.bank.fish_cast',  'ikpoba_riverbank.bank',    'hustle', 'fish_cast',      null, null, 1),
  ('ikpoba_riverbank.kiosk.fishing_rod', 'ikpoba_riverbank.kiosk', 'shop',   'fishing_rod',    null, null, 1),
  ('ikpoba_riverbank.river.river_watch',  'ikpoba_riverbank.river',  'activity', 'river_watch', null, null, 1),
  ('ikpoba_riverbank.trees.river_rest',   'ikpoba_riverbank.trees',  'activity', 'river_rest',  null, null, 1),
  ('mechanic_village.bay.mech_quick',  'mechanic_village.bay',     'hustle', 'mech_quick',     null, null, 1),
  ('mechanic_village.bay.mech_engine', 'mechanic_village.bay',     'hustle', 'mech_engine',    null, null, 2),
  ('mechanic_village.bay.car_service', 'mechanic_village.bay',     'hustle', 'car_service',    null, null, 3)
on conflict (id) do nothing;

insert into public.place_moods (id, scene, location_id, part, icon, line, sort) values
  ('ikpoba_riverbank.1', null, 'ikpoba_riverbank', 'any',     '🌊', 'The Ikpoba River moves slow and brown under the bridge', 1),
  ('ikpoba_riverbank.2', null, 'ikpoba_riverbank', 'morning', '🐟', 'Old fishermen mend nets and talk about the one wey get away', 2),
  ('ikpoba_riverbank.3', null, 'ikpoba_riverbank', 'evening', '🌅', 'Traffic hum on the bridge while the water turn orange', 3),
  ('mechanic_village.1', null, 'mechanic_village', 'any',     '🔧', 'Spanners clang and somebody dey shout for a 13 spanner', 1),
  ('mechanic_village.2', null, 'mechanic_village', 'morning', '🚗', 'Tokunbo cars line up for diagnosis. Oga mechanic dey look under the bonnet', 2),
  ('mechanic_village.3', null, 'mechanic_village', 'afternoon', '🛞', 'Vulcanizer boy dey roll a tyre across the road', 3)
on conflict (id) do nothing;

notify pgrst, 'reload schema';
