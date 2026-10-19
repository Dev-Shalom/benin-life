-- E4 Money sinks (docs/ECONOMY_SINKS.md). Players can still earn big, but money steadily leaves the game and new / low earners are protected.
--   1. Transfer charges: tiered fee (marginal 1 % / 2 % / 3 %), a flat N50 "stamp duty" from N10k, the fee doubles after a daily soft cap, a
--      preview before confirming (bank_transfer_quote). Tips follow the same fee. Market fees are untouched.
--   2. Weekly progressive income tax (0 / 5 / 10 / 15 %) on the SAME earn_reasons as the weekly leaderboard, settled lazily from bl_me() on the
--      player's next call (no cron), bank then cash, the rest becomes tax_owed and future earnings pay it first (bl_add_money). 7-day exemption.
--      Governor policy "Tax holiday" (kind tax_cut) cuts the rates for the term.
--   3. Weekly bills: house service charge + light, car insurance + servicing, business council tax, land ground rent. A Bills list (due date),
--      auto-pay on the due date when the money is there, a late fee, and a car stops driving / a business stops earning only after a long overdue
--      window. Never seized, never negative.
--   4. VAT 7.5 % included in the displayed price on shop, car, furniture and boutique buys, plus a luxury levy (cars, status items, laptops over
--      N1M ...). Food and basic needs are exempt. The item price shown IS the price paid (bl_dealer_price now returns the VAT-inclusive price).
--   5. Prestige sinks: donate to the city (Benin Philanthropists board, badge, Charisma XP), throw a city party (announcement, Fun buff in the
--      venue), buy a Chief title (badge next to the name, fictional tiers).
--   6. Admin Economy dashboard: money supply, created vs destroyed per day by category, top holders, tax, inflation.
--   7. Ledger reasons: tax_income, transfer_fee, stamp_duty, bill_house, bill_car, bill_business, ground_rent, vat, luxury_levy, donation,
--      city_party, chief_title. None of them is ever "earned". Every one is a plain debit with no matching credit: the money is destroyed.
-- Master switches (economy.*_enabled) let tests and the owner pin everything off.
-- Idempotent and safe on a non-empty DB: tables `if not exists`, seeds `on conflict do nothing`, functions `create or replace`, live functions
-- patched ONLY through a guarded replace on pg_get_functiondef (raises when a marker is missing, skips when already applied; create or replace
-- keeps the grants). Private bl_* helpers are revoked from anon / authenticated.

create or replace function pg_temp.bl_patchn(p_sig text, p_done text, p_pairs text[]) returns void
language plpgsql as $$
declare v_def text; v_n int; i int; v_m text; v_new text;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  i := 1;
  while i < array_length(p_pairs, 1) loop
    v_m := p_pairs[i]; v_new := p_pairs[i + 1];
    v_n := (length(v_def) - length(replace(v_def, v_m, ''))) / length(v_m);
    if v_n = 0 then raise exception '% : marker not found: %', p_sig, v_m; end if;
    if v_n > 1 then raise exception '% : marker not unique (% times): %', p_sig, v_n, v_m; end if;
    v_def := replace(v_def, v_m, v_new);
    i := i + 2;
  end loop;
  execute v_def;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (category economy)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
-- master switches
('economy.transfer_fees_enabled', 'true', 'economy', 'Tiered transfer fee on',
 'E4: bank transfers pay the tiered fee + stamp duty below (and tips the same). Off = the old flat bank.transfer_fee and free tips.', 'bool', null, null),
('economy.tax_enabled', 'true', 'economy', 'Weekly income tax on',
 'E4: the weekly income tax (Edo State Internal Revenue). Off = nobody is taxed and nothing new becomes tax owed.', 'bool', null, null),
('economy.bills_enabled', 'true', 'economy', 'Weekly bills on',
 'E4: house, car, business and land bills. Off = no new bills, nothing is blocked and open bills are ignored.', 'bool', null, null),
('economy.vat_enabled', 'true', 'economy', 'VAT on shop buys on',
 'E4: VAT in the displayed price of shop, car, furniture and boutique buys. Off = the old prices.', 'bool', null, null),
('economy.luxury_enabled', 'true', 'economy', 'Luxury levy on',
 'E4: the extra luxury levy on cars, status items, big laptops, big boutique and furniture buys.', 'bool', null, null),
('economy.prestige_enabled', 'true', 'economy', 'Donate / party / Chief titles on',
 'E4: the prestige sinks in the Bank app (Status tab).', 'bool', null, null),
-- transfer charges
('economy.fee_tier1_upto', '50000', 'economy', 'Transfer fee: tier 1 up to', 'E4: the part of a transfer up to this amount pays tier 1 %.', 'naira', 0, 100000000000),
('economy.fee_tier1_pct', '1', 'economy', 'Transfer fee: tier 1 %', 'E4: percent of the part up to tier 1.', 'percent', 0, 100),
('economy.fee_tier2_upto', '500000', 'economy', 'Transfer fee: tier 2 up to', 'E4: the part between tier 1 and this amount pays tier 2 %.', 'naira', 0, 100000000000),
('economy.fee_tier2_pct', '2', 'economy', 'Transfer fee: tier 2 %', 'E4: percent of the part between tier 1 and tier 2.', 'percent', 0, 100),
('economy.fee_tier3_pct', '3', 'economy', 'Transfer fee: tier 3 % (above tier 2)', 'E4: percent of everything above tier 2.', 'percent', 0, 100),
('economy.fee_min', '10', 'economy', 'Transfer fee: smallest', 'E4: the percentage fee is never below this.', 'naira', 0, 100000),
('economy.stamp_duty', '50', 'economy', 'Stamp duty (EMTL)', 'E4: a flat charge on transfers of at least the amount below (Nigeria''s real N50 on N10k and above).', 'naira', 0, 1000000),
('economy.stamp_duty_min', '10000', 'economy', 'Stamp duty from', 'E4: transfers of this amount or more pay the stamp duty.', 'naira', 0, 100000000000),
('economy.fee_soft_cap', '100000', 'economy', 'Daily soft cap', 'E4: after this much sent in a game day the percentage fee is multiplied (0 = no soft cap).', 'naira', 0, 100000000000),
('economy.fee_soft_cap_mult', '2', 'economy', 'Fee multiplier past the soft cap', 'E4: 2 = the fee doubles once the day''s total passes the soft cap.', 'number', 1, 20),
('economy.tip_fees_enabled', 'true', 'economy', 'Tips pay the transfer fee', 'E4: a tip pays the same tiered fee + stamp duty as a transfer (only when the tiered fee is on).', 'bool', null, null),
-- income tax
('economy.tax_band1_upto', '500000', 'economy', 'Income tax: band 1 up to (weekly)', 'E4: the first part of a week''s earned income, at band 1 %.', 'naira', 0, 1000000000000),
('economy.tax_band1_pct', '0', 'economy', 'Income tax: band 1 %', 'E4: 0 = the first N500k of a week is tax free.', 'percent', 0, 100),
('economy.tax_band2_upto', '5000000', 'economy', 'Income tax: band 2 up to (weekly)', 'E4: the part between band 1 and this amount.', 'naira', 0, 1000000000000),
('economy.tax_band2_pct', '5', 'economy', 'Income tax: band 2 %', 'E4: percent of the part in band 2.', 'percent', 0, 100),
('economy.tax_band3_upto', '50000000', 'economy', 'Income tax: band 3 up to (weekly)', 'E4: the part between band 2 and this amount.', 'naira', 0, 1000000000000),
('economy.tax_band3_pct', '10', 'economy', 'Income tax: band 3 %', 'E4: percent of the part in band 3.', 'percent', 0, 100),
('economy.tax_band4_pct', '15', 'economy', 'Income tax: band 4 % (above band 3)', 'E4: percent of everything above band 3.', 'percent', 0, 100),
('economy.tax_exempt_days', '7', 'economy', 'New players pay no tax for (days)', 'E4: a week that ends before the account is this many days old is not taxed.', 'number', 0, 365),
('economy.tax_catchup_weeks', '8', 'economy', 'Tax: most weeks settled at once', 'E4: a player who was away is only taxed for this many past weeks.', 'number', 1, 52),
-- bills
('economy.bill_grace_days', '7', 'economy', 'New players get no bills for (days)', 'E4: no bill is issued while the account is younger than this at the week boundary.', 'number', 0, 365),
('economy.bill_due_days', '3', 'economy', 'Bills fall due after (days)', 'E4: days from the week boundary to the due date.', 'number', 0, 60),
('economy.bill_late_fee_pct', '10', 'economy', 'Late fee %', 'E4: added once to a bill that is still unpaid on the due date.', 'percent', 0, 100),
('economy.bill_block_days', '14', 'economy', 'Asset stops working after (days overdue)', 'E4: a car cannot drive and a business earns nothing once its bill is this many days past due. Never seized.', 'number', 1, 365),
('economy.bill_catchup_weeks', '2', 'economy', 'Bills: most weeks billed at once', 'E4: a player who was away is billed for at most this many weeks.', 'number', 1, 12),
('economy.bills_autopay', 'true', 'economy', 'Pay bills automatically on the due date', 'E4: on the due date the bill is paid from the bank then cash when the money is there. Off = players pay by hand.', 'bool', null, null),
('economy.bill_retry_minutes', '30', 'economy', 'Autopay retry for late bills (real minutes)', 'E4: how often an overdue bill is tried again.', 'number', 1, 1440),
('economy.bill_min', '10', 'economy', 'Smallest bill', 'E4: bills under this are not issued.', 'naira', 0, 100000),
('economy.bill_house_service_pct', '20', 'economy', 'House: service charge (% of the weekly rent)', 'E4: weekly service charge, scaled by the house tier through its rent.', 'percent', 0, 1000),
('economy.bill_house_light_pct', '10', 'economy', 'House: light bill (% of the weekly rent)', 'E4: weekly light (NEPA) bill, scaled by the house tier through its rent.', 'percent', 0, 1000),
('economy.bill_house_upgrade_pct', '0.3', 'economy', 'House: upkeep of upgrades (% a week of what they cost)', 'E4: generator diesel, solar cleaning, boreholes and so on: a share of the upgrades you built.', 'percent', 0, 100),
('economy.bill_car_pct', '0.5', 'economy', 'Car: insurance + servicing (% a week of the car price)', 'E4: weekly bill per car.', 'percent', 0, 100),
('economy.bill_business_pct', '0.5', 'economy', 'Business: council tax (% a week of its value)', 'E4: weekly council tax per business, separate from its running costs.', 'percent', 0, 100),
('economy.ground_rent_pct', '0.1', 'economy', 'Land: ground rent (% a week of what the plots cost)', 'E4: weekly ground rent on land you hold.', 'percent', 0, 100),
-- VAT and luxury
('economy.vat_pct', '7.5', 'economy', 'VAT %', 'E4: included in the price of shop, car, furniture and boutique buys (Nigeria''s real 7.5 %).', 'percent', 0, 100),
('economy.luxury_pct', '5', 'economy', 'Luxury levy %', 'E4: extra, on top of VAT, on the luxury items below.', 'percent', 0, 100),
('economy.vat_exempt_categories', '"food,drink,fish,health,hygiene,phone,offering"', 'economy', 'VAT-free item categories', 'E4: shop item categories with no VAT (food and basic needs).', 'text', null, null),
('economy.luxury_categories', '"vehicle,gadget,souvenir"', 'economy', 'Luxury item categories', 'E4: shop item categories that pay the luxury levy (cars, status gadgets, keepsakes).', 'text', null, null),
('economy.luxury_laptop_min', '1000000', 'economy', 'Luxury: laptops from', 'E4: laptops priced at or over this pay the luxury levy.', 'naira', 0, 100000000000),
('economy.luxury_wardrobe_min', '1000000', 'economy', 'Luxury: boutique items from', 'E4: boutique items priced at or over this pay the luxury levy.', 'naira', 0, 100000000000),
('economy.luxury_furniture_min', '5000000', 'economy', 'Luxury: furniture from', 'E4: furniture priced at or over this pays the luxury levy.', 'naira', 0, 100000000000),
-- prestige
('economy.donate_min', '10000', 'economy', 'Donate to the city: smallest', 'E4: the least a donation can be.', 'naira', 1, 100000000000),
('economy.donate_xp_step', '100000', 'economy', 'Donation: N per Charisma XP', 'E4: Charisma XP = amount / this, up to the cap below.', 'naira', 1, 100000000000),
('economy.donate_xp_max', '100', 'economy', 'Donation: Charisma XP cap per donation', 'E4: the most Charisma XP one donation gives.', 'number', 0, 100000),
('economy.donor_tiers', '"Helper:10000, Benefactor:1000000, Philanthropist:10000000, City Patron:100000000"', 'economy', 'Philanthropist badge tiers', 'E4: badge by total donated, "Name:amount" pairs, smallest first.', 'text', null, null),
('economy.party_cost', '20000000', 'economy', 'City party: price', 'E4: throwing a city party is very expensive.', 'naira', 0, 100000000000),
('economy.party_fun_boost', '40', 'economy', 'City party: Fun boost', 'E4: Fun points for every player in the venue (once each, also for people who arrive during the party).', 'number', 0, 100),
('economy.party_minutes', '30', 'economy', 'City party: lasts (real minutes)', 'E4: players who walk into the venue in this window get the Fun boost too.', 'number', 1, 1440),
('economy.party_cooldown_minutes', '720', 'economy', 'City party: wait between your parties (real minutes)', 'E4: one party per host per 12 hours.', 'number', 0, 100000),
('economy.party_scenes', '"club,lounge,buka,hotel,stadium"', 'economy', 'City party: venues (place scenes)', 'E4: where a party can be thrown.', 'text', null, null),
('economy.chief_tiers', '"Chief:10000000, High Chief:50000000, Grand Chief:200000000"', 'economy', 'Chief titles', 'E4: "Title:price" pairs, cheapest first. Fictional titles only: never the real titles of the Oba''s palace.', 'text', null, null),
-- dashboard
('economy.internal_reasons', '"transfer_out,transfer_in,tip_out,tip_in,bank_deposit,bank_withdraw,pos_deposit,pos_cashout,market_buy,market_sale,steal_gain,steal_loss,crew_deposit,crew_payout,crew_refund,invest_buy,invest_sell"', 'economy', 'Dashboard: reasons that only move money',
 'E4: ledger reasons the Economy dashboard treats as moves between pockets (not created, not destroyed).', 'text', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables and columns
-- ---------------------------------------------------------------------------------------------
alter table public.profiles add column if not exists sinks_week date not null default public.bl_week_start();
alter table public.profiles add column if not exists tax_owed bigint not null default 0;
alter table public.profiles add column if not exists bills_next_due timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_tax_owed_check') then
    alter table public.profiles add constraint profiles_tax_owed_check check (tax_owed >= 0);
  end if;
end $$;

create table if not exists public.player_bills (
  id          bigserial primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  kind        text not null check (kind in ('house', 'car', 'business', 'land')),
  ref         text not null,
  title       text not null,
  detail      text not null default '',
  amount      bigint not null check (amount > 0),
  late_fee    bigint not null default 0 check (late_fee >= 0),
  period      date not null,
  status      text not null default 'open' check (status in ('open', 'paid')),
  issued_at   timestamptz not null default now(),
  due_at      timestamptz not null,
  late_at     timestamptz,
  paid_at     timestamptz,
  paid_amount bigint,
  unique (user_id, kind, ref, period)
);
create index if not exists player_bills_user_idx on public.player_bills (user_id, status, due_at);

create table if not exists public.tax_records (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  week_start date not null,
  earned     bigint not null default 0,
  tax        bigint not null default 0,
  paid       bigint not null default 0,
  rate_pct   numeric not null default 0,
  holiday    boolean not null default false,
  exempt     boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (user_id, week_start)
);

create table if not exists public.city_donors (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  total   bigint not null default 0,
  donations int not null default 0,
  last_at timestamptz not null default now()
);
create index if not exists city_donors_total_idx on public.city_donors (total desc);

create table if not exists public.city_parties (
  id          bigserial primary key,
  host_id     uuid not null references public.profiles(id) on delete cascade,
  location_id text not null,
  cost        bigint not null,
  fun_boost   int not null,
  started_at  timestamptz not null,
  ends_at     timestamptz not null,
  guests      int not null default 0
);
create index if not exists city_parties_loc_idx on public.city_parties (location_id, ends_at desc);
create table if not exists public.city_party_guests (
  party_id  bigint not null references public.city_parties(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (party_id, user_id)
);

create table if not exists public.chief_titles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  tier    int not null,
  name    text not null,
  ward    text,
  paid    bigint not null default 0,
  since   timestamptz not null default now()
);

alter table public.player_bills enable row level security;
alter table public.tax_records enable row level security;
alter table public.city_donors enable row level security;
alter table public.city_parties enable row level security;
alter table public.city_party_guests enable row level security;
alter table public.chief_titles enable row level security;
revoke all on table public.player_bills, public.tax_records, public.city_donors, public.city_parties, public.city_party_guests, public.chief_titles from anon, authenticated;
revoke all on sequence public.player_bills_id_seq, public.city_parties_id_seq from anon, authenticated;
grant select on table public.player_bills, public.tax_records to authenticated;
drop policy if exists player_bills_own on public.player_bills;
create policy player_bills_own on public.player_bills for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists tax_records_own on public.tax_records;
create policy tax_records_own on public.tax_records for select to authenticated using (user_id = (select auth.uid()));

-- the Governor's whitelist gets one more kind: tax_cut
alter table public.gov_policies drop constraint if exists gov_policies_kind_check;
alter table public.gov_policies add constraint gov_policies_kind_check
  check (kind = any (array['travel_discount', 'levy_cut', 'fitness_xp', 'hygiene_slow', 'tax_cut']));
insert into public.gov_policies (id, name, icon, blurb, kind, value, modes, weekday, sort) values
('tax_holiday', 'Tax holiday', '💸', 'Weekly income tax rates are cut for the whole term. More money for the people, the Governor says.', 'tax_cut', 50, '{}', null, 5)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_econ_num(p_key text, p_def numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_def)
$$;
create or replace function public.bl_econ_on(p_key text, p_def boolean) returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = p_key), p_def)
$$;
create or replace function public.bl_econ_text(p_key text, p_def text) returns text
language sql stable set search_path = public as $$
  select coalesce(nullif((select value #>> '{}' from game_config where key = p_key), ''), p_def)
$$;
create or replace function public.bl_econ_list(p_key text, p_def text) returns text[]
language sql stable set search_path = public as $$
  select coalesce(array(select btrim(x) from unnest(string_to_array(bl_econ_text(p_key, p_def), ',')) x where btrim(x) <> ''), '{}')
$$;
-- "Name:amount, Name:amount" -> rows in order
create or replace function public.bl_econ_tiers(p_key text, p_def text) returns table (idx int, name text, amount bigint)
language sql stable set search_path = public as $$
  select t.n::int, btrim(split_part(t.x, ':', 1)), btrim(split_part(t.x, ':', 2))::bigint
    from unnest(string_to_array(bl_econ_text(p_key, p_def), ',')) with ordinality t(x, n)
   where t.x like '%:%' and btrim(split_part(t.x, ':', 2)) ~ '^[0-9]+$'
   order by t.n
$$;

-- the ledger category a reason belongs to (Admin -> Economy)
create or replace function public.bl_econ_category(p_reason text) returns text
language sql immutable set search_path = public as $$
  select case
    when p_reason in ('salary', 'hustle', 'harvest', 'farm_harvest', 'business_income', 'office_salary', 'hustle_cost') then 'Jobs, hustles and business'
    when p_reason in ('invest_income', 'invest_fee', 'invest_buy', 'invest_sell') then 'Investments'
    when p_reason in ('yahoo_cashout', 'yahoo_pass') then 'Yahoo'
    when p_reason in ('allowance', 'start_bonus', 'weekly_prize', 'referral', 'challenge', 'daily', 'gem', 'money_pick', 'admin_gift', 'crew_payout') then 'Rewards and bonuses'
    when p_reason like 'admin%' then 'Admin'
    when p_reason in ('shrine', 'shrine_blessing', 'shrine_backfire', 'money_charm', 'money_charm_demand') then 'Babalawo'
    when p_reason in ('tax_income') then 'Income tax'
    when p_reason in ('transfer_fee', 'stamp_duty') then 'Transfer charges'
    when p_reason in ('bill_house', 'bill_car', 'bill_business', 'ground_rent') then 'Bills and upkeep'
    when p_reason in ('vat', 'luxury_levy') then 'VAT and luxury levy'
    when p_reason in ('donation', 'city_party', 'chief_title') then 'Prestige'
    when p_reason in ('market_fee', 'pos_fee') then 'Market and PoS fees'
    when p_reason in ('rent', 'house_move', 'house_upgrade', 'garage') then 'Housing'
    when p_reason in ('spray') then 'Clubs and spray'
    when p_reason in ('shop', 'car_purchase', 'furniture', 'food_delivery', 'travel', 'activity', 'lounge', 'event_ticket', 'linkup', 'linkup_gone_wrong') or p_reason like 'Boutique:%' then 'Shops, food and fun'
    when p_reason like 'business\_%' or p_reason like 'crew\_%' then 'Business and gang spending'
    when p_reason in ('shop_sell', 'furniture_sell', 'car_sell', 'item_sell') then 'Sell-backs'
    when p_reason in ('course_fee', 'campaign_fee', 'campaign_spend', 'police_bail', 'bail', 'street_robbery') then 'Fees, bail and crime'
    else 'Other' end
$$;

-- pay from the bank, then cash; refuses when the money is not there
create or replace function public.bl_sink_pay(p_uid uuid, p_amount bigint, p_reason text, p_meta jsonb) returns void
language plpgsql set search_path = public as $$
declare v profiles; v_bank bigint; v_cash bigint;
begin
  if coalesce(p_amount, 0) <= 0 then return; end if;
  select * into v from profiles where id = p_uid for update;
  if v.cash + greatest(v.bank, 0) < p_amount then
    raise exception 'Your money no reach, my guy. This costs % and you have % (bank % + cash %).', bl_naira(p_amount),
      bl_naira(v.cash + greatest(v.bank, 0)), bl_naira(greatest(v.bank, 0)), bl_naira(v.cash)
      using errcode = 'P0001', hint = 'not_enough_money';
  end if;
  v_bank := least(greatest(v.bank, 0), p_amount);
  v_cash := p_amount - v_bank;
  if v_bank > 0 then perform bl_add_money(p_uid, 'bank', -v_bank, p_reason, p_meta); end if;
  if v_cash > 0 then perform bl_add_money(p_uid, 'cash', -v_cash, p_reason, p_meta); end if;
end $$;

-- take up to p_amount from the bank then cash and return what was taken (never below zero)
create or replace function public.bl_sink_take(p_uid uuid, p_amount bigint, p_reason text, p_meta jsonb) returns bigint
language plpgsql set search_path = public as $$
declare v profiles; v_bank bigint; v_cash bigint;
begin
  if coalesce(p_amount, 0) <= 0 then return 0; end if;
  select * into v from profiles where id = p_uid for update;
  if not found then return 0; end if;
  v_bank := least(greatest(v.bank, 0), p_amount);
  v_cash := least(greatest(v.cash, 0), p_amount - v_bank);
  if v_bank > 0 then perform bl_add_money(p_uid, 'bank', -v_bank, p_reason, p_meta); end if;
  if v_cash > 0 then perform bl_add_money(p_uid, 'cash', -v_cash, p_reason, p_meta); end if;
  return v_bank + v_cash;
end $$;

-- ---- transfer charges
create or replace function public.bl_fee_rules() returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'enabled', bl_econ_on('economy.transfer_fees_enabled', true),
    'flat_fee', bl_econ_num('bank.transfer_fee', 0),
    'tiers', jsonb_build_array(
      jsonb_build_object('upto', bl_econ_num('economy.fee_tier1_upto', 50000), 'pct', bl_econ_num('economy.fee_tier1_pct', 1)),
      jsonb_build_object('upto', bl_econ_num('economy.fee_tier2_upto', 500000), 'pct', bl_econ_num('economy.fee_tier2_pct', 2)),
      jsonb_build_object('upto', null, 'pct', bl_econ_num('economy.fee_tier3_pct', 3))),
    'min_fee', bl_econ_num('economy.fee_min', 10),
    'stamp_duty', bl_econ_num('economy.stamp_duty', 50), 'stamp_duty_min', bl_econ_num('economy.stamp_duty_min', 10000),
    'soft_cap', bl_econ_num('economy.fee_soft_cap', 100000), 'soft_cap_mult', bl_econ_num('economy.fee_soft_cap_mult', 2),
    'tips', bl_econ_on('economy.tip_fees_enabled', true))
$$;

create or replace function public.bl_transfer_fee_calc(p_amount bigint, p_sent_today bigint, p_kind text default 'transfer') returns jsonb
language plpgsql stable set search_path = public as $$
declare
  t1 numeric := bl_econ_num('economy.fee_tier1_upto', 50000);  p1 numeric := bl_econ_num('economy.fee_tier1_pct', 1);
  t2 numeric := bl_econ_num('economy.fee_tier2_upto', 500000); p2 numeric := bl_econ_num('economy.fee_tier2_pct', 2);
  p3 numeric := bl_econ_num('economy.fee_tier3_pct', 3);
  v_min numeric := bl_econ_num('economy.fee_min', 10);
  v_stamp numeric := bl_econ_num('economy.stamp_duty', 50);  v_stamp_min numeric := bl_econ_num('economy.stamp_duty_min', 10000);
  v_cap numeric := bl_econ_num('economy.fee_soft_cap', 100000); v_mult numeric := greatest(1, bl_econ_num('economy.fee_soft_cap_mult', 2));
  v_amt numeric := greatest(coalesce(p_amount, 0), 0);
  v_fee numeric; v_st bigint := 0; v_dbl boolean := false;
begin
  if not bl_econ_on('economy.transfer_fees_enabled', true) then
    if p_kind = 'tip' then
      return jsonb_build_object('fee', 0, 'tier_fee', 0, 'stamp_duty', 0, 'doubled', false, 'tiered', false);
    end if;
    v_st := greatest(0, bl_econ_num('bank.transfer_fee', 0))::bigint;
    return jsonb_build_object('fee', v_st, 'tier_fee', v_st, 'stamp_duty', 0, 'doubled', false, 'tiered', false);
  end if;
  if p_kind = 'tip' and not bl_econ_on('economy.tip_fees_enabled', true) then
    return jsonb_build_object('fee', 0, 'tier_fee', 0, 'stamp_duty', 0, 'doubled', false, 'tiered', true);
  end if;
  if v_amt <= 0 then
    return jsonb_build_object('fee', 0, 'tier_fee', 0, 'stamp_duty', 0, 'doubled', false, 'tiered', true);
  end if;
  v_fee := least(v_amt, t1) * p1 / 100
         + greatest(0, least(v_amt, t2) - t1) * p2 / 100
         + greatest(0, v_amt - t2) * p3 / 100;
  v_fee := greatest(ceil(v_fee), v_min);
  if v_cap > 0 and coalesce(p_sent_today, 0) + v_amt > v_cap then
    v_dbl := true;
    v_fee := ceil(v_fee * v_mult);
  end if;
  v_fee := least(v_fee, v_amt);
  v_st := case when v_stamp > 0 and v_amt >= v_stamp_min then v_stamp::bigint else 0 end;
  return jsonb_build_object('fee', v_fee::bigint + v_st, 'tier_fee', v_fee::bigint, 'stamp_duty', v_st, 'doubled', v_dbl, 'tiered', true,
                            'rate_pct', round(v_fee * 100 / v_amt, 2));
end $$;

-- post a transfer's fee as two ledger rows (percentage fee, stamp duty); returns the bank balance after
create or replace function public.bl_transfer_fee_post(p_uid uuid, p_to text, p_amount bigint, p_fee bigint, p_stamp bigint) returns bigint
language plpgsql set search_path = public as $$
declare v_st bigint := least(coalesce(p_stamp, 0), p_fee); v_tier bigint := p_fee - least(coalesce(p_stamp, 0), p_fee); v_bank bigint;
begin
  if v_tier > 0 then
    v_bank := bl_add_money(p_uid, 'bank', -v_tier, 'transfer_fee', jsonb_build_object('to_username', p_to, 'amount', p_amount));
  end if;
  if v_st > 0 then
    v_bank := bl_add_money(p_uid, 'bank', -v_st, 'stamp_duty', jsonb_build_object('to_username', p_to, 'amount', p_amount));
  end if;
  return coalesce(v_bank, (select bank from profiles where id = p_uid));
end $$;

create or replace function public.bl_tip_fee(p_uid uuid, p_amount bigint) returns bigint
language sql stable set search_path = public as $$
  select (bl_transfer_fee_calc(p_amount,
            (select coalesce(sum(amount), 0)::bigint from tips where from_user = p_uid and created_at >= bl_hustle_day_start()), 'tip')->>'fee')::bigint
$$;
create or replace function public.bl_tip_fee_pay(p_uid uuid, p_amount bigint) returns void
language plpgsql set search_path = public as $$
declare c jsonb := bl_transfer_fee_calc(p_amount,
        (select coalesce(sum(amount), 0)::bigint from tips where from_user = p_uid and created_at >= bl_hustle_day_start()), 'tip');
begin
  perform bl_sink_pay(p_uid, (c->>'tier_fee')::bigint, 'transfer_fee', jsonb_build_object('tip', true, 'amount', p_amount));
  perform bl_sink_pay(p_uid, (c->>'stamp_duty')::bigint, 'stamp_duty', jsonb_build_object('tip', true, 'amount', p_amount));
end $$;

-- ---- VAT and the luxury levy
create or replace function public.bl_tax_rates(p_kind text, p_cat text, p_net bigint) returns numeric[]
language plpgsql stable set search_path = public as $$
declare v_vat numeric := 0; v_lux numeric := 0; v_is boolean := false;
begin
  if coalesce(p_net, 0) <= 0 then return array[0, 0]::numeric[]; end if;
  if bl_econ_on('economy.vat_enabled', true)
     and not (p_kind = 'item' and p_cat = any (bl_econ_list('economy.vat_exempt_categories', 'food,drink,fish,health,hygiene,phone,offering'))) then
    v_vat := bl_econ_num('economy.vat_pct', 7.5);
  end if;
  if bl_econ_on('economy.luxury_enabled', true) then
    v_is := case p_kind
      when 'item' then p_cat = any (bl_econ_list('economy.luxury_categories', 'vehicle,gadget,souvenir'))
                       or (p_cat = 'laptop' and p_net >= bl_econ_num('economy.luxury_laptop_min', 1000000))
      when 'wardrobe' then p_net >= bl_econ_num('economy.luxury_wardrobe_min', 1000000)
      when 'furniture' then p_net >= bl_econ_num('economy.luxury_furniture_min', 5000000)
      else false end;
    if v_is then v_lux := bl_econ_num('economy.luxury_pct', 5); end if;
  end if;
  return array[v_vat, v_lux];
end $$;

-- the VAT-inclusive price: what the player sees and pays
create or replace function public.bl_gross(p_kind text, p_cat text, p_net bigint) returns bigint
language plpgsql stable set search_path = public as $$
declare r numeric[] := bl_tax_rates(p_kind, p_cat, p_net);
begin
  return p_net + round(p_net * r[1] / 100)::bigint + round(p_net * r[2] / 100)::bigint;
end $$;

-- the VAT and luxury levy inside a gross price: [vat, luxury]
create or replace function public.bl_tax_split(p_kind text, p_cat text, p_gross bigint) returns bigint[]
language plpgsql stable set search_path = public as $$
declare r numeric[]; net0 numeric; v_vat bigint; v_lux bigint;
begin
  if coalesce(p_gross, 0) <= 0 then return array[0, 0]::bigint[]; end if;
  r := bl_tax_rates(p_kind, p_cat, p_gross);
  net0 := p_gross * 100 / (100 + r[1] + r[2]);
  r := bl_tax_rates(p_kind, p_cat, round(net0)::bigint);
  v_vat := round(p_gross * r[1] / (100 + r[1] + r[2]))::bigint;
  v_lux := round(p_gross * r[2] / (100 + r[1] + r[2]))::bigint;
  return array[least(v_vat, p_gross), least(v_lux, p_gross - least(v_vat, p_gross))];
end $$;

create or replace function public.bl_vat_note(p_kind text, p_cat text, p_gross bigint) returns text
language plpgsql stable set search_path = public as $$
declare s bigint[] := bl_tax_split(p_kind, p_cat, p_gross);
begin
  if s[1] + s[2] <= 0 then return ''; end if;
  return ' (incl. ' || case when s[1] > 0 then 'VAT ' || bl_naira(s[1]) else '' end
         || case when s[1] > 0 and s[2] > 0 then ' + ' else '' end
         || case when s[2] > 0 then 'luxury levy ' || bl_naira(s[2]) else '' end || ')';
end $$;

-- pay a gross price from the bank amount then the cash amount; the VAT / luxury levy part is its own ledger row (destroyed)
create or replace function public.bl_pay_gross(p_uid uuid, p_bank bigint, p_cash bigint, p_reason text, p_meta jsonb, p_vat bigint, p_lux bigint) returns void
language plpgsql set search_path = public as $$
declare v_vat bigint := coalesce(p_vat, 0); v_lux bigint := coalesce(p_lux, 0); v_amt bigint; v_take bigint; a text;
begin
  foreach a in array array['bank', 'cash'] loop
    v_amt := case a when 'bank' then coalesce(p_bank, 0) else coalesce(p_cash, 0) end;
    if v_amt <= 0 then continue; end if;
    v_take := least(v_amt, v_vat);
    if v_take > 0 then perform bl_add_money(p_uid, a, -v_take, 'vat', p_meta); v_vat := v_vat - v_take; v_amt := v_amt - v_take; end if;
    v_take := least(v_amt, v_lux);
    if v_take > 0 then perform bl_add_money(p_uid, a, -v_take, 'luxury_levy', p_meta); v_lux := v_lux - v_take; v_amt := v_amt - v_take; end if;
    if v_amt > 0 then perform bl_add_money(p_uid, a, -v_amt, p_reason, p_meta); end if;
  end loop;
end $$;

-- ---- income tax
create or replace function public.bl_pol_tax_mult() returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select 1 - p.value / 100.0 from bl_pol_policy() p where p.kind = 'tax_cut'), 1)
$$;

create or replace function public.bl_tax_bands() returns jsonb
language sql stable set search_path = public as $$
  with b as (select bl_econ_num('economy.tax_band1_upto', 500000) u1, bl_econ_num('economy.tax_band1_pct', 0) p1,
                    bl_econ_num('economy.tax_band2_upto', 5000000) u2, bl_econ_num('economy.tax_band2_pct', 5) p2,
                    bl_econ_num('economy.tax_band3_upto', 50000000) u3, bl_econ_num('economy.tax_band3_pct', 10) p3,
                    bl_econ_num('economy.tax_band4_pct', 15) p4, bl_pol_tax_mult() m)
  select jsonb_build_array(
    jsonb_build_object('from', 0, 'to', u1, 'pct', p1, 'eff_pct', round(p1 * m, 2)),
    jsonb_build_object('from', u1, 'to', u2, 'pct', p2, 'eff_pct', round(p2 * m, 2)),
    jsonb_build_object('from', u2, 'to', u3, 'pct', p3, 'eff_pct', round(p3 * m, 2)),
    jsonb_build_object('from', u3, 'to', null, 'pct', p4, 'eff_pct', round(p4 * m, 2))) from b
$$;

-- tax on one week's earned income (the Governor's tax holiday applies)
create or replace function public.bl_tax_calc(p_earned bigint) returns bigint
language plpgsql stable set search_path = public as $$
declare e numeric := greatest(coalesce(p_earned, 0), 0);
  u1 numeric := bl_econ_num('economy.tax_band1_upto', 500000); p1 numeric := bl_econ_num('economy.tax_band1_pct', 0);
  u2 numeric := bl_econ_num('economy.tax_band2_upto', 5000000); p2 numeric := bl_econ_num('economy.tax_band2_pct', 5);
  u3 numeric := bl_econ_num('economy.tax_band3_upto', 50000000); p3 numeric := bl_econ_num('economy.tax_band3_pct', 10);
  p4 numeric := bl_econ_num('economy.tax_band4_pct', 15);
  t numeric;
begin
  t := least(e, u1) * p1 + greatest(0, least(e, u2) - u1) * p2 + greatest(0, least(e, u3) - u2) * p3 + greatest(0, e - u3) * p4;
  return floor(t / 100 * bl_pol_tax_mult())::bigint;
end $$;

-- earned income of one player for one week (the same earn_reasons as the weekly top earners)
create or replace function public.bl_week_earned(p_uid uuid, p_week date) returns bigint
language sql stable set search_path = public as $$
  select coalesce(sum(l.delta), 0)::bigint from ledger l
   where l.user_id = p_uid and l.delta > 0 and l.reason = any (bl_earn_reasons())
     and l.created_at >= bl_week_from(p_week) and l.created_at < bl_week_from(p_week + 7)
$$;

create or replace function public.bl_tax_settle_week(p_uid uuid, p_week date) returns void
language plpgsql set search_path = public as $$
declare v profiles; v_earned bigint; v_tax bigint; v_paid bigint := 0; v_owed bigint; v_ex boolean; v_hol boolean; n int;
begin
  select * into v from profiles where id = p_uid;
  if not found then return; end if;
  if exists (select 1 from tax_records where user_id = p_uid and week_start = p_week) then return; end if;
  v_earned := bl_week_earned(p_uid, p_week);
  if v_earned <= 0 then return; end if;
  v_ex := bl_week_from(p_week + 7) - v.created_at < make_interval(secs => bl_econ_num('economy.tax_exempt_days', 7) * 86400);
  v_hol := bl_pol_tax_mult() < 1;
  v_tax := case when v_ex then 0 else bl_tax_calc(v_earned) end;
  if v_tax > 0 then
    v_paid := bl_sink_take(p_uid, v_tax, 'tax_income', jsonb_build_object('week', p_week, 'earned', v_earned));
  end if;
  v_owed := v_tax - v_paid;
  insert into tax_records (user_id, week_start, earned, tax, paid, rate_pct, holiday, exempt, created_at)
  values (p_uid, p_week, v_earned, v_tax, v_paid, round(v_tax * 100.0 / v_earned, 2), v_hol, v_ex, bl_now())
  on conflict (user_id, week_start) do nothing;
  get diagnostics n = row_count;
  if n = 0 then return; end if;
  if v_owed > 0 then update profiles set tax_owed = tax_owed + v_owed where id = p_uid; end if;
  if v_tax > 0 then
    perform bl_event(p_uid, 'tax_paid', 'Edo State Internal Revenue',
      'You paid ' || bl_naira(v_paid) || ' tax this week' || case when v_hol then ' (tax holiday rates)' else '' end || ' on ' || bl_naira(v_earned) || ' earned.'
      || case when v_owed > 0 then ' You still owe ' || bl_naira(v_owed) || '. Your next earnings pay it first.' else '' end,
      jsonb_build_object('week', p_week, 'earned', v_earned, 'tax', v_tax, 'paid', v_paid, 'owed', v_owed, 'holiday', v_hol));
  end if;
end $$;

-- future earnings pay tax owed first: called from bl_add_money after a credit
create or replace function public.bl_tax_garnish(p_uid uuid, p_account text, p_delta bigint, p_reason text) returns bigint
language plpgsql set search_path = public as $$
declare v_owed bigint; v_take bigint;
begin
  select tax_owed into v_owed from profiles where id = p_uid;
  if coalesce(v_owed, 0) <= 0 then return 0; end if;
  if not (p_reason = any (bl_earn_reasons())) then return 0; end if;
  v_take := least(v_owed, p_delta);
  perform bl_add_money(p_uid, p_account, -v_take, 'tax_income', jsonb_build_object('garnish', true, 'owed_before', v_owed));
  update profiles set tax_owed = tax_owed - v_take where id = p_uid;
  return v_take;
end $$;

-- ---- bills
create or replace function public.bl_bill_reason(p_kind text) returns text
language sql immutable as $$
  select case p_kind when 'house' then 'bill_house' when 'car' then 'bill_car' when 'business' then 'bill_business' else 'ground_rent' end
$$;

create or replace function public.bl_bills_issue(p_uid uuid, p_period date) returns jsonb
language plpgsql set search_path = public as $$
declare v profiles; v_due timestamptz; v_min bigint := greatest(0, bl_econ_num('economy.bill_min', 10))::bigint;
  v_amt bigint; r record; n int := 0; v_n int; v_total bigint := 0; v_upg numeric;
begin
  select * into v from profiles where id = p_uid;
  if not found then return jsonb_build_object('n', 0, 'total', 0); end if;
  if bl_week_from(p_period) - v.created_at < make_interval(secs => bl_econ_num('economy.bill_grace_days', 7) * 86400) then
    return jsonb_build_object('n', 0, 'total', 0);
  end if;
  v_due := case when p_period >= bl_week_start() then bl_week_from(p_period) else bl_now() end
           + make_interval(secs => bl_econ_num('economy.bill_due_days', 3) * 86400);
  -- house: service charge + light bill, scaled by the rent (the tier) and the upgrades built
  if v.home_chosen and v.weekly_rent > 0 then
    select coalesce(sum(price_paid), 0) into v_upg from player_house_upgrades where user_id = p_uid and done_at is not null;
    v_amt := (round((v.weekly_rent * (bl_econ_num('economy.bill_house_service_pct', 20) + bl_econ_num('economy.bill_house_light_pct', 10)) / 100
                     + v_upg * bl_econ_num('economy.bill_house_upgrade_pct', 0.3) / 100) / 10.0) * 10)::bigint;
    if v_amt >= greatest(v_min, 1) then
      insert into player_bills (user_id, kind, ref, title, detail, amount, period, issued_at, due_at)
      values (p_uid, 'house', coalesce(v.housing_id, 'home'), 'Service charge + light bill',
              'Your home, scaled by its rent and ' || case when v_upg > 0 then 'the upgrades you built' else 'no upgrades yet' end,
              v_amt, p_period, bl_now(), v_due)
      on conflict (user_id, kind, ref, period) do nothing;
      get diagnostics v_n = row_count; n := n + v_n; v_total := v_total + v_amt * v_n;
    end if;
  end if;
  -- cars
  for r in select it.id, it.name, it.price from inventory i join items it on it.id = i.item_id
            where i.user_id = p_uid and i.qty > 0 and it.category = 'vehicle' loop
    v_amt := (round(r.price * bl_econ_num('economy.bill_car_pct', 0.5) / 100 / 10.0) * 10)::bigint;
    if v_amt >= greatest(v_min, 1) then
      insert into player_bills (user_id, kind, ref, title, detail, amount, period, issued_at, due_at)
      values (p_uid, 'car', r.id, 'Insurance + servicing', r.name, v_amt, p_period, bl_now(), v_due)
      on conflict (user_id, kind, ref, period) do nothing;
      get diagnostics v_n = row_count; n := n + v_n; v_total := v_total + v_amt * v_n;
    end if;
  end loop;
  -- businesses: council tax on the value
  for r in select b.id, b.name, bl_biz_value(b) as val from businesses b where b.owner_id = p_uid loop
    v_amt := (round(r.val * bl_econ_num('economy.bill_business_pct', 0.5) / 100 / 10.0) * 10)::bigint;
    if v_amt >= greatest(v_min, 1) then
      insert into player_bills (user_id, kind, ref, title, detail, amount, period, issued_at, due_at)
      values (p_uid, 'business', r.id::text, 'Council tax', r.name, v_amt, p_period, bl_now(), v_due)
      on conflict (user_id, kind, ref, period) do nothing;
      get diagnostics v_n = row_count; n := n + v_n; v_total := v_total + v_amt * v_n;
    end if;
  end loop;
  -- land: ground rent on what the plots cost
  for r in select p.ref_id, p.qty, p.cost, m.name from invest_positions p join invest_markets m on m.id = p.ref_id
            where p.user_id = p_uid and p.kind = 'land' and p.qty > 0 loop
    v_amt := (round(r.cost * bl_econ_num('economy.ground_rent_pct', 0.1) / 100 / 10.0) * 10)::bigint;
    if v_amt >= greatest(v_min, 1) then
      insert into player_bills (user_id, kind, ref, title, detail, amount, period, issued_at, due_at)
      values (p_uid, 'land', r.ref_id, 'Ground rent', r.name || ' (' || trim_scale(r.qty)::text || ' plot' || case when r.qty = 1 then '' else 's' end || ')',
              v_amt, p_period, bl_now(), v_due)
      on conflict (user_id, kind, ref, period) do nothing;
      get diagnostics v_n = row_count; n := n + v_n; v_total := v_total + v_amt * v_n;
    end if;
  end loop;
  return jsonb_build_object('n', n, 'total', v_total, 'due_at', v_due);
end $$;

-- on the due date: pay from the bank then cash when the money is there (autopay), else add the late fee once
create or replace function public.bl_bills_collect(p_uid uuid) returns void
language plpgsql set search_path = public as $$
declare b player_bills; v_now timestamptz := bl_now(); v_auto boolean := bl_econ_on('economy.bills_autopay', true);
  v_fee numeric := bl_econ_num('economy.bill_late_fee_pct', 10); v_total bigint; v_have bigint;
  n_paid int := 0; v_paid bigint := 0; n_late int := 0; v_late bigint := 0; v_next timestamptz;
begin
  if bl_econ_on('economy.bills_enabled', true) then
    for b in select * from player_bills where user_id = p_uid and status = 'open' and due_at <= v_now order by due_at, id for update loop
      v_total := b.amount + b.late_fee;
      select cash + greatest(bank, 0) into v_have from profiles where id = p_uid;
      if v_auto and v_have >= v_total then
        perform bl_sink_pay(p_uid, v_total, bl_bill_reason(b.kind),
          jsonb_build_object('bill', b.id, 'title', b.title, 'detail', b.detail, 'late_fee', b.late_fee, 'auto', true));
        update player_bills set status = 'paid', paid_at = v_now, paid_amount = v_total where id = b.id;
        n_paid := n_paid + 1; v_paid := v_paid + v_total;
      elsif b.late_at is null then
        update player_bills set late_at = v_now, late_fee = ceil(b.amount * v_fee / 100)::bigint where id = b.id;
        n_late := n_late + 1; v_late := v_late + ceil(b.amount * v_fee / 100)::bigint;
      end if;
    end loop;
    if n_paid > 0 then
      perform bl_event(p_uid, 'bills_paid', 'Bills paid',
        n_paid || ' bill' || case when n_paid = 1 then '' else 's' end || ' paid from your bank: ' || bl_naira(v_paid) || '. See Bank, Bills.',
        jsonb_build_object('count', n_paid, 'paid', v_paid));
    end if;
    if n_late > 0 then
      perform bl_event(p_uid, 'bills_late', 'Bill overdue',
        n_late || ' bill' || case when n_late = 1 then ' is' else 's are' end || ' overdue (late fee ' || bl_naira(v_late)
        || ' added). Pay in Bank, Bills before your car or business stops working.',
        jsonb_build_object('count', n_late, 'late_fee', v_late));
    end if;
  end if;
  select min(case when late_at is null then due_at else v_now + make_interval(mins => bl_econ_num('economy.bill_retry_minutes', 30)::int) end)
    into v_next from player_bills where user_id = p_uid and status = 'open'
     and (late_at is null or v_auto);
  update profiles set bills_next_due = v_next where id = p_uid and bills_next_due is distinct from v_next;
end $$;

-- the weekly boundary, then whatever is due
create or replace function public.bl_sinks_settle(p_uid uuid) returns void
language plpgsql set search_path = public as $$
declare v profiles; v_cw date := bl_week_start(); v_wk date; v_first date; v_catch int; v_r jsonb; n int := 0; v_total bigint := 0; v_due timestamptz;
begin
  select * into v from profiles where id = p_uid for update;
  if not found then return; end if;
  if v.sinks_week < v_cw then
    if bl_econ_on('economy.tax_enabled', true) then
      v_catch := greatest(1, bl_econ_num('economy.tax_catchup_weeks', 8)::int);
      v_first := greatest(v.sinks_week, v_cw - 7 * v_catch);
      for v_wk in select d::date from generate_series(v_first::timestamp, (v_cw - 7)::timestamp, interval '7 days') d loop
        perform bl_tax_settle_week(p_uid, v_wk);
      end loop;
    end if;
    if bl_econ_on('economy.bills_enabled', true) then
      v_catch := greatest(1, bl_econ_num('economy.bill_catchup_weeks', 2)::int);
      for v_wk in select d::date from generate_series(greatest(v.sinks_week + 7, v_cw - 7 * (v_catch - 1))::timestamp, v_cw::timestamp, interval '7 days') d loop
        v_r := bl_bills_issue(p_uid, v_wk);
        n := n + (v_r->>'n')::int; v_total := v_total + (v_r->>'total')::bigint; v_due := coalesce((v_r->>'due_at')::timestamptz, v_due);
      end loop;
      if n > 0 then
        perform bl_event(p_uid, 'bills_issued', 'New bills',
          n || ' new bill' || case when n = 1 then '' else 's' end || ' this week, ' || bl_naira(v_total) || ' in all, due '
          || to_char(v_due at time zone 'Africa/Lagos', 'DD Mon') || '. See Bank, Bills.',
          jsonb_build_object('count', n, 'total', v_total, 'due_at', v_due));
      end if;
    end if;
    update profiles set sinks_week = v_cw where id = p_uid;
  end if;
  perform bl_bills_collect(p_uid);
end $$;

-- an asset stops working only after its bill is long overdue (never seized)
create or replace function public.bl_sink_blocked(p_uid uuid, p_kind text, p_ref text) returns boolean
language sql stable set search_path = public as $$
  select bl_econ_on('economy.bills_enabled', true) and exists (
    select 1 from player_bills b where b.user_id = p_uid and b.kind = p_kind and b.ref = p_ref and b.status = 'open'
       and b.due_at + make_interval(secs => bl_econ_num('economy.bill_block_days', 14) * 86400) <= bl_now())
$$;
create or replace function public.bl_sink_any_blocked(p_uid uuid, p_kind text) returns boolean
language sql stable set search_path = public as $$
  select bl_econ_on('economy.bills_enabled', true) and exists (
    select 1 from player_bills b where b.user_id = p_uid and b.kind = p_kind and b.status = 'open'
       and b.due_at + make_interval(secs => bl_econ_num('economy.bill_block_days', 14) * 86400) <= bl_now())
$$;

-- ---- prestige
create or replace function public.bl_chief_title(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select nullif(c.name, '') from chief_titles c where c.user_id = p_uid and bl_econ_on('economy.prestige_enabled', true)
$$;
create or replace function public.bl_donor_badge(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select (select t.name from bl_econ_tiers('economy.donor_tiers', 'Helper:10000') t where t.amount <= d.total order by t.amount desc limit 1)
    from city_donors d where d.user_id = p_uid and bl_econ_on('economy.prestige_enabled', true)
$$;

-- a city party: everybody in the venue (and everybody who walks in while it lasts) gets the Fun boost once
create or replace function public.bl_party_join(p_uid uuid, p_loc text) returns boolean
language plpgsql set search_path = public as $$
declare pt city_parties; n int; v_boost int;
begin
  select * into pt from city_parties where location_id = p_loc and ends_at > bl_now() order by id desc limit 1;
  if not found then return false; end if;
  insert into city_party_guests (party_id, user_id, joined_at) values (pt.id, p_uid, bl_now()) on conflict do nothing;
  get diagnostics n = row_count;
  if n = 0 then return false; end if;
  v_boost := pt.fun_boost;
  update profiles set fun = least(100, fun + v_boost) where id = p_uid;
  update city_parties set guests = guests + 1 where id = pt.id;
  perform bl_event(p_uid, 'city_party', '🎉 City party!', 'The party at ' || coalesce((select name from locations where id = p_loc), 'the venue')
    || ' is on. Fun +' || v_boost || '.', jsonb_build_object('party', pt.id, 'fun', v_boost));
  return true;
end $$;

create or replace function public.bl_bills_next(p_uid uuid) returns void
language plpgsql set search_path = public as $$
declare v_next timestamptz; v_now timestamptz := bl_now(); v_auto boolean := bl_econ_on('economy.bills_autopay', true);
begin
  select min(case when late_at is null then due_at else v_now + make_interval(mins => bl_econ_num('economy.bill_retry_minutes', 30)::int) end)
    into v_next from player_bills where user_id = p_uid and status = 'open' and (late_at is null or v_auto);
  update profiles set bills_next_due = v_next where id = p_uid and bills_next_due is distinct from v_next;
end $$;

create or replace function public.bl_chief_area(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select w.name from chief_titles c left join wards w on w.id = c.ward where c.user_id = p_uid
$$;

create or replace function public.bl_pay_shop(p_uid uuid, p_total bigint, p_cat text, p_meta jsonb) returns void
language plpgsql set search_path = public as $$
declare s bigint[] := bl_tax_split('item', p_cat, p_total);
begin
  perform bl_pay_gross(p_uid, 0, p_total, 'shop', p_meta, s[1], s[2]);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. Guarded patches to live functions
-- ---------------------------------------------------------------------------------------------
-- every credit from an earn reason pays tax owed first
select pg_temp.bl_patchn('public.bl_add_money(uuid, text, bigint, text, jsonb)', 'bl_tax_garnish', array[
  $m$return v_bal;$m$,
  $m$if p_delta > 0 then
    v_bal := v_bal - bl_tax_garnish(p_uid, p_account, p_delta, p_reason);
  end if;
  return v_bal;$m$]);

-- the tiered transfer fee + stamp duty
select pg_temp.bl_patchn('public.bank_transfer(text, bigint, text)', 'bl_transfer_fee_post', array[
  $m$v_day := (v_st->>'day')::bigint;$m$,
  $m$v_day := (v_st->>'day')::bigint;
   v_fee := (bl_transfer_fee_calc(p_amount, (v_st->>'sent')::bigint, 'transfer')->>'fee')::bigint;$m$,
  $m$v_bank := bl_add_money(v_me.id, 'bank', -v_fee, 'transfer_fee', jsonb_build_object('to_username', r.username, 'amount', p_amount));$m$,
  $m$v_bank := bl_transfer_fee_post(v_me.id, r.username, p_amount, v_fee,
                                    (bl_transfer_fee_calc(p_amount, (v_st->>'sent')::bigint, 'transfer')->>'stamp_duty')::bigint);$m$]);

-- tips pay the same fee
select pg_temp.bl_patchn('public.tip_player(text, bigint, text)', 'bl_tip_fee_pay', array[
  $m$if v_me.bank + v_me.cash < p_amount then$m$,
  $m$if v_me.bank + v_me.cash < p_amount + bl_tip_fee(v_me.id, p_amount) then$m$,
  $m$if v_cash > 0 then perform bl_add_money(v_me.id, 'cash', -v_cash, 'tip_out', v_meta); end if;$m$,
  $m$if v_cash > 0 then perform bl_add_money(v_me.id, 'cash', -v_cash, 'tip_out', v_meta); end if;
  perform bl_tip_fee_pay(v_me.id, p_amount);$m$]);

select pg_temp.bl_patchn('public.bank_info()', 'bl_fee_rules', array[
  $m$'fee', bl_cfg('bank.transfer_fee'),$m$,
  $m$'fee', bl_cfg('bank.transfer_fee'), 'fee_rules', bl_fee_rules(),$m$]);

-- lazy settle: tax, bills, party Fun boost, on the player's next call
select pg_temp.bl_patchn('public.bl_me()', 'bl_sinks_settle', array[
  $m$return v;$m$,
  $m$if v.sinks_week < bl_week_start() or (v.bills_next_due is not null and v.bills_next_due <= bl_now()) then
    perform bl_sinks_settle(v.id);
    select * into v from profiles where id = v.id;
  end if;
  if exists (select 1 from city_parties where location_id = v.location_id and ends_at > bl_now()) then
    if bl_party_join(v.id, v.location_id) then
      select * into v from profiles where id = v.id;
    end if;
  end if;
  return v;$m$]);

-- VAT: bl_dealer_price becomes the VAT-inclusive price (bl_dealer_net is the old price)
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.bl_dealer_price(public.items, text)'::regprocedure) into v_def;
  if position('bl_gross' in v_def) = 0 and position('car_dealers' in v_def) = 0 then
    raise exception 'bl_dealer_price: unexpected body';
  end if;
end $$;
create or replace function public.bl_dealer_net(p_item public.items, p_location text) returns bigint
language sql stable set search_path = public as $$
  select case
    when p_item.category <> 'vehicle' then p_item.price
    else coalesce((
      select case when p_item.price * d.multiplier >= 1000000
                  then (round(p_item.price * d.multiplier / 10000.0) * 10000)::bigint
                  else (round(p_item.price * d.multiplier / 1000.0) * 1000)::bigint end
        from car_dealers d where d.location_id = p_location and d.active), p_item.price)
  end
$$;
create or replace function public.bl_dealer_price(p_item public.items, p_location text) returns bigint
language sql stable set search_path = public as $$
  select bl_gross('item', p_item.category, bl_dealer_net(p_item, p_location))
$$;

select pg_temp.bl_patchn('public.shop_list(text)', 'bl_tax_rates', array[
  $m$'base_price', it.price,$m$,
  $m$'base_price', bl_gross('item', it.category, it.price),
               'vat_pct', (bl_tax_rates('item', it.category, bl_dealer_net(it, l.id)))[1],
               'lux_pct', (bl_tax_rates('item', it.category, bl_dealer_net(it, l.id)))[2],$m$]);

select pg_temp.bl_patchn('public.shop_buy(text, integer)', 'bl_pay_gross', array[
  E'    if v_bank > 0 then\n      perform bl_add_money(v_me.id, ''bank'', -v_bank, ''car_purchase'', jsonb_build_object(''item'', it.id, ''location'', l.id));\n    end if;\n    if v_cash > 0 then\n      perform bl_add_money(v_me.id, ''cash'', -v_cash, ''car_purchase'', jsonb_build_object(''item'', it.id, ''location'', l.id));\n    end if;',
  $m$    perform bl_pay_gross(v_me.id, v_bank, v_cash, 'car_purchase', jsonb_build_object('item', it.id, 'location', l.id),
                         (bl_tax_split('item', it.category, v_total))[1], (bl_tax_split('item', it.category, v_total))[2]);$m$,
  $m$'. "Your car" is now a travel option$m$,
  $m$bl_vat_note('item', it.category, v_total) || '. "Your car" is now a travel option$m$,
  $m$perform bl_add_money(v_me.id, 'cash', -v_total, 'shop',$m$,
  $m$perform bl_pay_shop(v_me.id, v_total, it.category,$m$,
  $m$perform bl_biz_visit_cut(v_me.id, l.id, v_total, it.name);$m$,
  $m$perform bl_biz_visit_cut(v_me.id, l.id, v_total - (bl_tax_split('item', it.category, v_total))[1] - (bl_tax_split('item', it.category, v_total))[2], it.name);$m$,
  $m$bl_naira(v_total) || '. It''s in your Bag.'$m$,
  $m$bl_naira(v_total) || bl_vat_note('item', it.category, v_total) || '. It''s in your Bag.'$m$]);

select pg_temp.bl_patchn('public.furniture_buy(text)', 'bl_pay_gross', array[
  $m$if v_me.cash + greatest(v_me.bank, 0) < f.price then$m$,
  $m$if v_me.cash + greatest(v_me.bank, 0) < bl_gross('furniture', f.category, f.price) then$m$,
  $m$bl_naira(f.price),$m$,
  $m$bl_naira(bl_gross('furniture', f.category, f.price)),$m$,
  $m$v_cash := least(greatest(v_me.cash, 0), f.price);$m$,
  $m$v_cash := least(greatest(v_me.cash, 0), bl_gross('furniture', f.category, f.price));$m$,
  $m$v_bank := f.price - v_cash;$m$,
  $m$v_bank := bl_gross('furniture', f.category, f.price) - v_cash;$m$,
  E'  if v_cash > 0 then\n    perform bl_add_money(v_uid, ''cash'', -v_cash, ''furniture'', jsonb_build_object(''furniture'', f.id, ''name'', f.name));\n  end if;\n  if v_bank > 0 then\n    perform bl_add_money(v_uid, ''bank'', -v_bank, ''furniture'', jsonb_build_object(''furniture'', f.id, ''name'', f.name));\n  end if;',
  $m$  perform bl_pay_gross(v_uid, v_bank, v_cash, 'furniture', jsonb_build_object('furniture', f.id, 'name', f.name),
                       (bl_tax_split('furniture', f.category, bl_gross('furniture', f.category, f.price)))[1],
                       (bl_tax_split('furniture', f.category, bl_gross('furniture', f.category, f.price)))[2]);$m$,
  $m$bl_receipt_issue(v_uid, 'furniture', f.name, f.price,$m$,
  $m$bl_receipt_issue(v_uid, 'furniture', f.name, bl_gross('furniture', f.category, f.price),$m$,
  $m$'spent', f.price,$m$,
  $m$'spent', bl_gross('furniture', f.category, f.price),$m$]);

select pg_temp.bl_patchn('public.wardrobe_buy(text, text)', 'bl_pay_gross', array[
  $m$if it.price > v_me.bank + v_me.cash then$m$,
  $m$if bl_gross('wardrobe', it.category, it.price) > v_me.bank + v_me.cash then$m$,
  $m$bl_naira(it.price), bl_naira(v_me.bank + v_me.cash)$m$,
  $m$bl_naira(bl_gross('wardrobe', it.category, it.price)), bl_naira(v_me.bank + v_me.cash)$m$,
  $m$v_bank := least(it.price, v_me.bank);$m$,
  $m$v_bank := least(bl_gross('wardrobe', it.category, it.price), v_me.bank);$m$,
  $m$v_cash := it.price - v_bank;$m$,
  $m$v_cash := bl_gross('wardrobe', it.category, it.price) - v_bank;$m$,
  $m$if v_bank > 0 then perform bl_add_money(v_me.id, 'bank', -v_bank, 'Boutique: ' || it.name, v_meta); end if;$m$,
  $m$perform bl_pay_gross(v_me.id, v_bank, v_cash, 'Boutique: ' || it.name, v_meta,
                         (bl_tax_split('wardrobe', it.category, bl_gross('wardrobe', it.category, it.price)))[1],
                         (bl_tax_split('wardrobe', it.category, bl_gross('wardrobe', it.category, it.price)))[2]);$m$,
  $m$if v_cash > 0 then perform bl_add_money(v_me.id, 'cash', -v_cash, 'Boutique: ' || it.name, v_meta); end if;$m$,
  $m$null;$m$,
  $m$bl_receipt_issue(v_me.id, 'boutique', it.name, it.price,$m$,
  $m$bl_receipt_issue(v_me.id, 'boutique', it.name, bl_gross('wardrobe', it.category, it.price),$m$,
  $m$bl_naira(it.price) || '. It''s in your wardrobe.'$m$,
  $m$bl_naira(bl_gross('wardrobe', it.category, it.price)) || bl_vat_note('wardrobe', it.category, bl_gross('wardrobe', it.category, it.price)) || '. It''s in your wardrobe.'$m$,
  $m$'paid', it.price,$m$,
  $m$'paid', bl_gross('wardrobe', it.category, it.price),$m$]);

-- an unpaid business bill long overdue pauses its income (never seized)
select pg_temp.bl_patchn('public.bl_biz_settle(bigint, boolean)', 'bl_sink_blocked', array[
  $m$v_gain := v_gross_hr * bl_biz_factor(b, t, v_cur, v_next);$m$,
  $m$v_gain := v_gross_hr * bl_biz_factor(b, t, v_cur, v_next)
                * case when bl_sink_blocked(b.owner_id, 'business', b.id::text) then 0 else 1 end;$m$]);

-- ... and a car with a long overdue bill cannot drive or run Bolt
select pg_temp.bl_patchn('public.bl_hustle_car(uuid)', 'bl_sink_blocked', array[
  $m$where i.user_id = p_uid and i.qty > 0$m$,
  $m$where i.user_id = p_uid and i.qty > 0 and not bl_sink_blocked(p_uid, 'car', it.id)$m$]);
select pg_temp.bl_patchn('public.bl_travel_quote(public.profiles, text)', 'bl_sink_blocked', array[
  $m$where i.user_id = p_me.id and i.qty > 0 and it.category = 'vehicle';$m$,
  $m$where i.user_id = p_me.id and i.qty > 0 and it.category = 'vehicle' and not bl_sink_blocked(p_me.id, 'car', i.item_id);$m$,
  $m$v_reason := 'You don''t have a car yet. Buy one first.';$m$,
  $m$v_reason := case when bl_sink_any_blocked(p_me.id, 'car')
                      then 'Your car dey park: the insurance bill is long overdue. Pay it in Bank, Bills.'
                      else 'You don''t have a car yet. Buy one first.' end;$m$]);

-- ledger text
select pg_temp.bl_patchn('public.bl_ledger_label(text, jsonb)', 'when ''stamp_duty'' then', array[
  $m$when 'transfer_fee' then return 'Transfer fee';$m$,
  $m$when 'transfer_fee' then return case when coalesce((p_meta->>'tip')::boolean, false) then 'Tip fee' else 'Transfer fee' end;
    when 'stamp_duty' then return 'Stamp duty (EMTL)';
    when 'tax_income' then return case when coalesce((p_meta->>'garnish')::boolean, false) then 'Income tax owed (from your earnings)'
                                       else 'Income tax' || coalesce(' · week of ' || to_char((p_meta->>'week')::date, 'DD Mon'), '') end;
    when 'bill_house' then return 'Bill: ' || coalesce(nullif(p_meta->>'title', ''), 'service charge + light');
    when 'bill_car' then return 'Bill: ' || coalesce(nullif(p_meta->>'title', ''), 'car') || coalesce(' · ' || nullif(p_meta->>'detail', ''), '');
    when 'bill_business' then return 'Bill: ' || coalesce(nullif(p_meta->>'title', ''), 'council tax') || coalesce(' · ' || nullif(p_meta->>'detail', ''), '');
    when 'ground_rent' then return 'Bill: ' || coalesce(nullif(p_meta->>'title', ''), 'ground rent') || coalesce(' · ' || nullif(p_meta->>'detail', ''), '');
    when 'vat' then return 'VAT';
    when 'luxury_levy' then return 'Luxury levy';
    when 'donation' then return 'Donation to the city';
    when 'city_party' then return 'City party' || coalesce(' · ' || nullif(p_meta->>'place', ''), '');
    when 'chief_title' then return 'Chief title: ' || coalesce(nullif(p_meta->>'name', ''), 'title');$m$]);

-- none of the new sinks is ever earned, even if an admin lists one in leaderboard.earn_reasons
select pg_temp.bl_patchn('public.bl_earn_reasons()', 'tax_income', array[
  $m$and btrim(x) not like 'market\_%'$m$,
  $m$and btrim(x) not like 'market\_%'
         and btrim(x) <> all (array['tax_income', 'transfer_fee', 'stamp_duty', 'bill_house', 'bill_car', 'bill_business', 'ground_rent', 'vat', 'luxury_levy', 'donation', 'city_party', 'chief_title'])$m$]);

-- Chief titles share the badge slot next to the name (an office title wins)
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.bl_pol_title(uuid)'::regprocedure) into v_def;
  if position('bl_chief_title' in v_def) > 0 then return; end if;
  if position('office_holders' in v_def) = 0 then raise exception 'bl_pol_title: unexpected body'; end if;
  create or replace function public.bl_pol_title(p_uid uuid) returns text
  language sql stable security definer set search_path = public as $f$
    select coalesce(
      (select nullif(o.title, '') from office_holders h join offices o on o.id = h.office_id
        where h.user_id = p_uid and h.status = 'active' and h.term_end > bl_now() and bl_pol_on() limit 1),
      bl_chief_title(p_uid))
  $f$;
end $$;

select pg_temp.bl_patchn('public.get_public_profile(uuid)', 'bl_donor_badge', array[
  $m$'title', bl_pol_title(id))$m$,
  $m$'title', bl_pol_title(id), 'chief_of', bl_chief_area(id), 'donor', bl_donor_badge(id))$m$]);

-- ---------------------------------------------------------------------------------------------
-- 5. Player RPCs
-- ---------------------------------------------------------------------------------------------
-- the fee, shown before the player confirms
create or replace function public.bank_transfer_quote(p_amount bigint, p_kind text default 'transfer') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_sent bigint; c jsonb; v_cap numeric := bl_econ_num('economy.fee_soft_cap', 100000); v_kind text := case when p_kind = 'tip' then 'tip' else 'transfer' end;
begin
  if v_kind = 'tip' then
    select coalesce(sum(amount), 0)::bigint into v_sent from tips where from_user = v_uid and created_at >= bl_hustle_day_start();
  else
    v_sent := (bl_transfer_stats(v_uid)->>'sent')::bigint;
  end if;
  c := bl_transfer_fee_calc(greatest(coalesce(p_amount, 0), 0), v_sent, v_kind);
  return c || jsonb_build_object('amount', greatest(coalesce(p_amount, 0), 0), 'kind', v_kind,
    'total', greatest(coalesce(p_amount, 0), 0) + (c->>'fee')::bigint, 'sent_today', v_sent,
    'soft_cap', case when (c->>'tiered')::boolean then v_cap else 0 end,
    'left_before_soft_cap', case when (c->>'tiered')::boolean and v_cap > 0 then greatest(0, v_cap - v_sent) else null end);
end $$;

-- the tax card: bands, this week so far, what is owed, the tax holiday (shown in Bank and Benin Votes)
create or replace function public.tax_info() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me profiles; v_wk date := bl_week_start(); v_earned bigint; v_pol gov_policies; v_ex timestamptz;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  v_earned := bl_week_earned(v_uid, v_wk);
  select * into v_pol from bl_pol_policy() p where p.kind = 'tax_cut';
  v_ex := v_me.created_at + make_interval(secs => bl_econ_num('economy.tax_exempt_days', 7) * 86400);
  return jsonb_build_object(
    'enabled', bl_econ_on('economy.tax_enabled', true),
    'bands', bl_tax_bands(),
    'holiday', case when v_pol.id is null then null else jsonb_build_object('name', v_pol.name, 'cut_pct', v_pol.value) end,
    'week', jsonb_build_object('start', v_wk, 'ends_at', bl_week_from(v_wk + 7), 'earned', v_earned, 'est_tax', bl_tax_calc(v_earned)),
    'owed', v_me.tax_owed,
    'exempt_until', v_ex, 'exempt_now', bl_now() < v_ex,
    'last', coalesce((select jsonb_agg(jsonb_build_object('week', t.week_start, 'earned', t.earned, 'tax', t.tax, 'paid', t.paid,
                          'rate_pct', t.rate_pct, 'holiday', t.holiday, 'exempt', t.exempt) order by t.week_start desc)
                        from (select * from tax_records where user_id = v_uid order by week_start desc limit 8) t), '[]'::jsonb));
end $$;

create or replace function public.bank_sinks() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); v_block numeric := bl_econ_num('economy.bill_block_days', 14);
begin
  return jsonb_build_object(
    'enabled', bl_econ_on('economy.bills_enabled', true),
    'owed', v_me.tax_owed,
    'grace_until', v_me.created_at + make_interval(secs => bl_econ_num('economy.bill_grace_days', 7) * 86400),
    'block_days', v_block, 'late_fee_pct', bl_econ_num('economy.bill_late_fee_pct', 10), 'autopay', bl_econ_on('economy.bills_autopay', true),
    'open_total', coalesce((select sum(amount + late_fee) from player_bills where user_id = v_me.id and status = 'open'), 0),
    'bills', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'kind', b.kind, 'title', b.title, 'detail', b.detail, 'amount', b.amount,
                'late_fee', b.late_fee, 'total', b.amount + b.late_fee, 'due_at', b.due_at, 'status', b.status, 'paid_at', b.paid_at,
                'late', b.late_at is not null, 'overdue', b.status = 'open' and b.due_at <= bl_now(),
                'blocked', b.status = 'open' and b.due_at + make_interval(secs => v_block * 86400) <= bl_now(),
                'blocks_at', b.due_at + make_interval(secs => v_block * 86400))
                order by (b.status = 'paid'), b.due_at, b.id)
                from (select * from player_bills where user_id = v_me.id and (status = 'open' or paid_at > bl_now() - interval '30 days')
                      order by (status = 'paid'), due_at, id limit 60) b), '[]'::jsonb),
    'tax', tax_info());
end $$;

create or replace function public.bills_pay(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); b player_bills; v_total bigint;
begin
  select * into b from player_bills where id = p_id and user_id = v_me.id for update;
  if not found then raise exception 'That bill does not exist.' using errcode = 'P0001', hint = 'unknown_bill'; end if;
  if b.status = 'paid' then raise exception 'That bill is already paid.' using errcode = 'P0001', hint = 'already_paid'; end if;
  v_total := b.amount + b.late_fee;
  perform bl_sink_pay(v_me.id, v_total, bl_bill_reason(b.kind),
    jsonb_build_object('bill', b.id, 'title', b.title, 'detail', b.detail, 'late_fee', b.late_fee));
  update player_bills set status = 'paid', paid_at = bl_now(), paid_amount = v_total where id = b.id;
  perform bl_bills_next(v_me.id);
  return jsonb_build_object('message', 'Paid ' || bl_naira(v_total) || ' for ' || lower(b.title) || coalesce(' (' || nullif(b.detail, '') || ')', '') || '.', 'paid', v_total,
                            'bank', (select bank from profiles where id = v_me.id), 'cash', (select cash from profiles where id = v_me.id));
end $$;

create or replace function public.bills_pay_all() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); b player_bills; v_have bigint; n int := 0; v_paid bigint := 0; v_left int := 0;
begin
  for b in select * from player_bills where user_id = v_me.id and status = 'open' order by due_at, id for update loop
    select cash + greatest(bank, 0) into v_have from profiles where id = v_me.id;
    if v_have >= b.amount + b.late_fee then
      perform bl_sink_pay(v_me.id, b.amount + b.late_fee, bl_bill_reason(b.kind),
        jsonb_build_object('bill', b.id, 'title', b.title, 'detail', b.detail, 'late_fee', b.late_fee));
      update player_bills set status = 'paid', paid_at = bl_now(), paid_amount = b.amount + b.late_fee where id = b.id;
      n := n + 1; v_paid := v_paid + b.amount + b.late_fee;
    else
      v_left := v_left + 1;
    end if;
  end loop;
  perform bl_bills_next(v_me.id);
  if n = 0 and v_left = 0 then raise exception 'You have no open bills.' using errcode = 'P0001', hint = 'no_bills'; end if;
  if n = 0 then raise exception 'Your money no reach for any of your bills right now.' using errcode = 'P0001', hint = 'not_enough_money'; end if;
  return jsonb_build_object('message', 'Paid ' || n || ' bill' || case when n = 1 then '' else 's' end || ' (' || bl_naira(v_paid) || ').'
                            || case when v_left > 0 then ' ' || v_left || ' still waiting: your money no reach.' else '' end,
                            'paid', v_paid, 'count', n, 'left', v_left);
end $$;

create or replace function public.tax_pay(p_amount bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); v_want bigint; v_take bigint;
begin
  if v_me.tax_owed <= 0 then raise exception 'You owe no tax. Edo State Internal Revenue thanks you.' using errcode = 'P0001', hint = 'no_tax_owed'; end if;
  v_want := least(v_me.tax_owed, coalesce(p_amount, v_me.tax_owed));
  if v_want <= 0 then raise exception 'Money amount no correct.' using errcode = 'P0001', hint = 'bad_amount'; end if;
  if v_me.cash + greatest(v_me.bank, 0) <= 0 then
    raise exception 'Your money no reach, my guy. You owe % tax.', bl_naira(v_me.tax_owed) using errcode = 'P0001', hint = 'not_enough_money';
  end if;
  v_take := bl_sink_take(v_me.id, v_want, 'tax_income', jsonb_build_object('settle', true));
  update profiles set tax_owed = tax_owed - v_take where id = v_me.id;
  return jsonb_build_object('message', 'Paid ' || bl_naira(v_take) || ' tax.' || case when v_me.tax_owed - v_take > 0 then ' You still owe ' || bl_naira(v_me.tax_owed - v_take) || '.' else ' You owe nothing now.' end,
                            'paid', v_take, 'owed', v_me.tax_owed - v_take);
end $$;

-- ---- prestige: donate, party, Chief titles
create or replace function public.bl_prestige_guard() returns void
language plpgsql stable set search_path = public as $$
begin
  if not bl_econ_on('economy.prestige_enabled', true) then
    raise exception 'The city is not taking donations and parties for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
end $$;

create or replace function public.donate_city(p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); v_min bigint := greatest(1, bl_econ_num('economy.donate_min', 10000))::bigint; v_total bigint; v_xp int; v_before text; v_after text;
begin
  perform bl_prestige_guard();
  if p_amount is null or p_amount < v_min then
    raise exception 'The smallest donation is %.', bl_naira(v_min) using errcode = 'P0001', hint = 'too_small';
  end if;
  perform bl_sink_pay(v_me.id, p_amount, 'donation', jsonb_build_object('amount', p_amount));
  v_before := bl_donor_badge(v_me.id);
  insert into city_donors (user_id, total, donations, last_at) values (v_me.id, p_amount, 1, bl_now())
  on conflict (user_id) do update set total = city_donors.total + p_amount, donations = city_donors.donations + 1, last_at = bl_now()
  returning total into v_total;
  v_after := bl_donor_badge(v_me.id);
  v_xp := least(greatest(0, bl_econ_num('economy.donate_xp_max', 100)), floor(p_amount / greatest(1, bl_econ_num('economy.donate_xp_step', 100000))))::int;
  if v_xp > 0 then perform bl_chal_skill_xp(v_me.id, 'charisma', v_xp); end if;
  perform bl_event(v_me.id, 'donation', 'Thank you, ' || v_me.username || '!',
    'The city received your ' || bl_naira(p_amount) || '. You have given ' || bl_naira(v_total) || ' in all.'
    || case when v_after is distinct from v_before then ' New badge: ' || v_after || '.' else '' end,
    jsonb_build_object('amount', p_amount, 'total', v_total, 'badge', v_after, 'xp', v_xp));
  return jsonb_build_object('message', 'The city says thank you. ' || bl_naira(p_amount) || ' donated.' || case when v_after is not null then ' You are a ' || v_after || '.' else '' end
                              || case when v_xp > 0 then ' Charisma +' || v_xp || ' XP.' else '' end,
                            'total', v_total, 'badge', v_after, 'xp', v_xp);
end $$;

create or replace function public.donors_top(p_limit int default 20) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_lim int := least(greatest(coalesce(p_limit, 20), 1), 100);
begin
  return jsonb_build_object(
    'tiers', coalesce((select jsonb_agg(jsonb_build_object('name', t.name, 'amount', t.amount) order by t.amount) from bl_econ_tiers('economy.donor_tiers', 'Helper:10000') t), '[]'::jsonb),
    'min', bl_econ_num('economy.donate_min', 10000),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('rank', x.rank, 'username', x.username, 'total', x.total, 'badge', bl_donor_badge(x.user_id),
                          'title', bl_pol_title(x.user_id), 'me', x.user_id = v_uid) order by x.rank)
                        from (select d.user_id, p.username, d.total, row_number() over (order by d.total desc, d.last_at) as rank
                                from city_donors d join profiles p on p.id = d.user_id where not p.banned and not p.is_admin
                               order by d.total desc, d.last_at limit v_lim) x), '[]'::jsonb),
    'me', (select jsonb_build_object('total', d.total, 'donations', d.donations, 'badge', bl_donor_badge(v_uid)) from city_donors d where d.user_id = v_uid));
end $$;

create or replace function public.city_party_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); l locations; v_last timestamptz; v_cool numeric := bl_econ_num('economy.party_cooldown_minutes', 720);
  v_ok boolean := true; v_why text;
begin
  select * into l from locations where id = v_me.location_id;
  if not bl_econ_on('economy.prestige_enabled', true) then v_ok := false; v_why := 'Parties are switched off for now.';
  elsif not (l.scene = any (bl_econ_list('economy.party_scenes', 'club,lounge,buka,hotel,stadium'))) then
    v_ok := false; v_why := 'Go to a club, lounge, buka or hotel to throw a party.';
  end if;
  select max(started_at) into v_last from city_parties where host_id = v_me.id;
  return jsonb_build_object(
    'enabled', bl_econ_on('economy.prestige_enabled', true),
    'cost', bl_econ_num('economy.party_cost', 20000000), 'fun_boost', bl_econ_num('economy.party_fun_boost', 40),
    'minutes', bl_econ_num('economy.party_minutes', 30),
    'cooldown_left_seconds', case when v_last is null then 0 else greatest(0, ceil(extract(epoch from v_last + make_interval(mins => v_cool::int) - bl_now()))) end,
    'here', jsonb_build_object('id', l.id, 'name', l.name, 'ok', v_ok, 'reason', v_why),
    'active', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'location', c.location_id, 'name', (select name from locations where id = c.location_id),
                          'host', (select username from profiles where id = c.host_id), 'ends_at', c.ends_at, 'guests', c.guests) order by c.ends_at)
                          from city_parties c where c.ends_at > bl_now()), '[]'::jsonb));
end $$;

create or replace function public.city_party_throw() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); l locations; v_cost bigint := greatest(0, bl_econ_num('economy.party_cost', 20000000))::bigint;
  v_last timestamptz; v_cool numeric := bl_econ_num('economy.party_cooldown_minutes', 720); v_id bigint; v_bid bigint; n int; r record; v_in int := 0;
  v_mins numeric := bl_econ_num('economy.party_minutes', 30); v_name text;
begin
  perform bl_prestige_guard();
  perform bl_assert_free(v_me);
  select * into l from locations where id = v_me.location_id;
  if not (l.scene = any (bl_econ_list('economy.party_scenes', 'club,lounge,buka,hotel,stadium'))) then
    raise exception 'You can only throw a city party at a club, lounge, buka or hotel.' using errcode = 'P0001', hint = 'bad_venue';
  end if;
  perform bl_assert_place_open(l);
  if exists (select 1 from city_parties where location_id = l.id and ends_at > bl_now()) then
    raise exception 'There is already a party at %. Wait for it to end.', l.name using errcode = 'P0001', hint = 'party_on';
  end if;
  select max(started_at) into v_last from city_parties where host_id = v_me.id;
  if v_last is not null and v_last + make_interval(mins => v_cool::int) > bl_now() then
    raise exception 'You threw a party recently. Rest small. Try again in about % min.',
      ceil(extract(epoch from v_last + make_interval(mins => v_cool::int) - bl_now()) / 60) using errcode = 'P0001', hint = 'cooldown';
  end if;
  perform bl_sink_pay(v_me.id, v_cost, 'city_party', jsonb_build_object('place', l.name, 'location', l.id));
  insert into city_parties (host_id, location_id, cost, fun_boost, started_at, ends_at)
  values (v_me.id, l.id, v_cost, bl_econ_num('economy.party_fun_boost', 40)::int, bl_now(), bl_now() + make_interval(secs => v_mins * 60))
  returning id into v_id;
  v_name := left('🎉 City party at ' || l.name || '!', 80);
  insert into broadcasts (kind, title, body, style, audience, popup, expires_at, created_by)
  values ('message', v_name, left('@' || v_me.username || ' is throwing a city party at ' || l.name || '. Everybody is invited. Walk in for a Fun boost while it lasts.', 500),
          'celebration', 'everyone', true, now() + make_interval(secs => v_mins * 60), v_me.id)
  returning id into v_bid;
  select count(*) into n from bl_broadcast_targets('everyone', null);
  update broadcasts set target_count = n where id = v_bid;
  perform bl_broadcast_bump(v_bid);
  for r in select id from profiles where location_id = l.id and not banned and last_seen > bl_now() - interval '10 minutes' loop
    if bl_party_join(r.id, l.id) then v_in := v_in + 1; end if;
  end loop;
  return jsonb_build_object('message', 'Party don start at ' || l.name || '! Everybody in the city has been told.', 'party', v_id, 'guests', v_in, 'ends_at', bl_now() + make_interval(secs => v_mins * 60));
end $$;

create or replace function public.chief_titles() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c chief_titles;
begin
  select * into c from chief_titles where user_id = v_uid;
  return jsonb_build_object(
    'enabled', bl_econ_on('economy.prestige_enabled', true),
    'mine', case when c.user_id is null then null else jsonb_build_object('tier', c.tier, 'name', c.name, 'ward', c.ward, 'of', (select name from wards where id = c.ward), 'paid', c.paid) end,
    'tiers', coalesce((select jsonb_agg(jsonb_build_object('tier', t.idx, 'name', t.name, 'price', t.amount,
                          'cost_now', greatest(0, t.amount - coalesce(c.paid, 0)), 'owned', c.tier is not null and c.tier >= t.idx) order by t.idx)
                        from bl_econ_tiers('economy.chief_tiers', 'Chief:10000000') t), '[]'::jsonb),
    'wards', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'name', w.name) order by w.sort, w.id) from wards w where w.active), '[]'::jsonb));
end $$;

create or replace function public.chief_title_buy(p_tier int, p_ward text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); t record; c chief_titles; v_ward wards; v_cost bigint; v_area text;
begin
  perform bl_prestige_guard();
  select * into t from bl_econ_tiers('economy.chief_tiers', 'Chief:10000000') x where x.idx = p_tier;
  if not found then raise exception 'Pick a title from the list.' using errcode = 'P0001', hint = 'bad_tier'; end if;
  select * into v_ward from wards where id = p_ward and active;
  if not found then raise exception 'Pick the part of Benin your title is "of".' using errcode = 'P0001', hint = 'bad_ward'; end if;
  select * into c from chief_titles where user_id = v_me.id;
  if found and c.tier >= t.idx then
    raise exception 'You already hold %.', c.name using errcode = 'P0001', hint = 'already_owned';
  end if;
  v_cost := greatest(0, t.amount - coalesce(c.paid, 0));
  perform bl_sink_pay(v_me.id, v_cost, 'chief_title', jsonb_build_object('name', t.name, 'tier', t.idx, 'ward', v_ward.id));
  insert into chief_titles (user_id, tier, name, ward, paid, since) values (v_me.id, t.idx, t.name, v_ward.id, t.amount, bl_now())
  on conflict (user_id) do update set tier = excluded.tier, name = excluded.name, ward = excluded.ward, paid = excluded.paid, since = excluded.since;
  v_area := v_ward.name;
  perform bl_event(v_me.id, 'chief_title', 'You are now ' || t.name || ' ' || v_me.username || ' of ' || v_area,
    'Your title shows next to your name for everybody to see.', jsonb_build_object('tier', t.idx, 'name', t.name, 'ward', v_ward.id));
  return jsonb_build_object('message', 'You are now ' || t.name || ' ' || v_me.username || ' of ' || v_area || '. Congratulations!', 'name', t.name, 'of', v_area, 'paid', v_cost);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Admin Economy dashboard
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_economy_overview(p_days int default 14) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_days int := least(greatest(coalesce(p_days, 14), 1), 60);
  v_from date := (bl_now() at time zone 'Africa/Lagos')::date - (least(greatest(coalesce(p_days, 14), 1), 60) - 1);
  v_from_ts timestamptz; v_to_ts timestamptz;
  v_int text[] := bl_econ_list('economy.internal_reasons', 'transfer_out,transfer_in');
  v_cash bigint; v_bank bigint; v_yahoo bigint; v_gang bigint; v_biz bigint; v_players int; v_supply bigint;
  v_created bigint; v_destroyed bigint; v_c7 bigint; v_d7 bigint; v_start bigint; v_start7 bigint; v_g numeric; v_g7 numeric;
  v_series jsonb; v_cats jsonb; v_reasons jsonb; v_hold jsonb; v_tax jsonb;
begin
  perform bl_admin_guard();
  v_from_ts := v_from::timestamp at time zone 'Africa/Lagos';
  v_to_ts := ((bl_now() at time zone 'Africa/Lagos')::date + 1)::timestamp at time zone 'Africa/Lagos';
  select coalesce(sum(cash), 0), coalesce(sum(bank), 0), count(*) into v_cash, v_bank, v_players from profiles where not is_admin;
  select coalesce(sum(y.dirty), 0) into v_yahoo from yahoo_players y join profiles p on p.id = y.user_id where not p.is_admin;
  select coalesce(sum(bank), 0) into v_gang from crews;
  select coalesce(sum(floor(b.takings)), 0) into v_biz from businesses b join profiles p on p.id = b.owner_id where not p.is_admin;
  v_supply := v_cash + v_bank + v_yahoo + v_gang + v_biz;

  create temp table if not exists tmp_econ_rows (day date, reason text, created bigint, destroyed bigint) on commit drop;
  truncate tmp_econ_rows;
  insert into tmp_econ_rows
    select (l.created_at at time zone 'Africa/Lagos')::date, l.reason,
           coalesce(sum(l.delta) filter (where l.delta > 0), 0)::bigint, coalesce(-sum(l.delta) filter (where l.delta < 0), 0)::bigint
      from ledger l join profiles p on p.id = l.user_id
     where l.created_at >= v_from_ts and l.created_at < v_to_ts and not p.is_admin and l.reason <> all (v_int)
     group by 1, 2;

  select coalesce(sum(created), 0), coalesce(sum(destroyed), 0) into v_created, v_destroyed from tmp_econ_rows;
  select coalesce(sum(created), 0), coalesce(sum(destroyed), 0) into v_c7, v_d7 from tmp_econ_rows where day > (bl_now() at time zone 'Africa/Lagos')::date - 7;
  v_start := v_supply - (v_created - v_destroyed);
  v_start7 := v_supply - (v_c7 - v_d7);
  v_g := case when v_start > 0 then round((v_created - v_destroyed) * 100.0 / v_start, 2) end;
  v_g7 := case when v_start7 > 0 then round((v_c7 - v_d7) * 100.0 / v_start7, 2) end;

  select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'created', coalesce(s.c, 0), 'destroyed', coalesce(s.x, 0), 'net', coalesce(s.c, 0) - coalesce(s.x, 0),
           'categories', coalesce(s.cats, '[]'::jsonb)) order by d.day), '[]'::jsonb)
    into v_series
    from generate_series(v_from::timestamp, (bl_now() at time zone 'Africa/Lagos')::date::timestamp, interval '1 day') g(d0)
    cross join lateral (select g.d0::date as day) d
    left join lateral (
      select sum(k.c) c, sum(k.x) x,
             jsonb_agg(jsonb_build_object('category', k.category, 'created', k.c, 'destroyed', k.x) order by k.category) cats
        from (select bl_econ_category(r.reason) category, sum(r.created) c, sum(r.destroyed) x from tmp_econ_rows r where r.day = d.day group by 1) k
    ) s on true;

  select coalesce(jsonb_agg(jsonb_build_object('category', k.category, 'created', k.c, 'destroyed', k.x) order by k.c + k.x desc), '[]'::jsonb) into v_cats
    from (select bl_econ_category(reason) category, sum(created) c, sum(destroyed) x from tmp_econ_rows group by 1) k;
  select coalesce(jsonb_agg(jsonb_build_object('reason', k.reason, 'category', bl_econ_category(k.reason), 'created', k.c, 'destroyed', k.x) order by k.c + k.x desc), '[]'::jsonb) into v_reasons
    from (select reason, sum(created) c, sum(destroyed) x from tmp_econ_rows group by 1 order by sum(created) + sum(destroyed) desc limit 40) k;

  select coalesce(jsonb_agg(jsonb_build_object('rank', h.rk, 'id', h.id, 'username', h.username, 'cash', h.cash, 'bank', h.bank, 'yahoo', h.yahoo, 'business', h.biz, 'total', h.total) order by h.rk), '[]'::jsonb)
    into v_hold
    from (select p.id, p.username, p.cash, p.bank, coalesce(y.dirty, 0) as yahoo,
                 coalesce((select sum(floor(b.takings)) from businesses b where b.owner_id = p.id), 0)::bigint as biz,
                 p.cash + p.bank + coalesce(y.dirty, 0) + coalesce((select sum(floor(b.takings)) from businesses b where b.owner_id = p.id), 0)::bigint as total,
                 row_number() over (order by p.cash + p.bank + coalesce(y.dirty, 0) + coalesce((select sum(floor(b.takings)) from businesses b where b.owner_id = p.id), 0) desc, p.created_at) as rk
            from profiles p left join yahoo_players y on y.user_id = p.id where not p.is_admin and not p.banned
           order by 8 desc limit 20) h;

  select jsonb_build_object(
    'collected_total', coalesce((select -sum(l.delta) from ledger l join profiles p on p.id = l.user_id where l.reason = 'tax_income' and l.delta < 0 and not p.is_admin), 0),
    'collected_window', coalesce((select sum(destroyed) from tmp_econ_rows where reason = 'tax_income'), 0),
    'owed_total', coalesce((select sum(tax_owed) from profiles where not is_admin), 0),
    'taxpayers_window', (select count(distinct t.user_id) from tax_records t where t.tax > 0 and t.week_start >= v_from - 7),
    'bills_open_total', coalesce((select sum(b.amount + b.late_fee) from player_bills b where b.status = 'open'), 0),
    'bills_overdue_total', coalesce((select sum(b.amount + b.late_fee) from player_bills b where b.status = 'open' and b.due_at <= bl_now()), 0),
    'bills_paid_window', coalesce((select sum(destroyed) from tmp_econ_rows where reason in ('bill_house', 'bill_car', 'bill_business', 'ground_rent')), 0),
    'transfer_charges_window', coalesce((select sum(destroyed) from tmp_econ_rows where reason in ('transfer_fee', 'stamp_duty')), 0),
    'vat_window', coalesce((select sum(destroyed) from tmp_econ_rows where reason = 'vat'), 0),
    'luxury_window', coalesce((select sum(destroyed) from tmp_econ_rows where reason = 'luxury_levy'), 0),
    'prestige_window', coalesce((select sum(destroyed) from tmp_econ_rows where reason in ('donation', 'city_party', 'chief_title')), 0)) into v_tax;

  return jsonb_build_object(
    'days', v_days, 'from', v_from,
    'supply', jsonb_build_object('total', v_supply, 'cash', v_cash, 'bank', v_bank, 'yahoo', v_yahoo, 'gangs', v_gang, 'business', v_biz, 'players', v_players),
    'window', jsonb_build_object('created', v_created, 'destroyed', v_destroyed, 'net', v_created - v_destroyed,
                                 'destroyed_pct_of_created', case when v_created > 0 then round(v_destroyed * 100.0 / v_created, 1) end),
    'inflation', jsonb_build_object('growth_pct', v_g, 'growth_7d_pct', v_g7, 'supply_start', v_start,
                                    'state', case when v_g7 is null then 'unknown' when v_g7 > 10 then 'hot' when v_g7 < -2 then 'cooling' else 'ok' end),
    'series', v_series, 'categories', v_cats, 'reasons', v_reasons, 'holders', v_hold, 'tax', v_tax,
    'switches', jsonb_build_object('transfer_fees', bl_econ_on('economy.transfer_fees_enabled', true), 'tax', bl_econ_on('economy.tax_enabled', true),
                                   'bills', bl_econ_on('economy.bills_enabled', true), 'vat', bl_econ_on('economy.vat_enabled', true),
                                   'luxury', bl_econ_on('economy.luxury_enabled', true), 'prestige', bl_econ_on('economy.prestige_enabled', true)));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = any (array[
              'bl_econ_num', 'bl_econ_on', 'bl_econ_text', 'bl_econ_list', 'bl_econ_tiers', 'bl_econ_category', 'bl_sink_pay', 'bl_sink_take',
              'bl_fee_rules', 'bl_transfer_fee_calc', 'bl_transfer_fee_post', 'bl_tip_fee', 'bl_tip_fee_pay', 'bl_tax_rates', 'bl_gross', 'bl_tax_split',
              'bl_vat_note', 'bl_pay_gross', 'bl_pay_shop', 'bl_pol_tax_mult', 'bl_tax_bands', 'bl_tax_calc', 'bl_week_earned', 'bl_tax_settle_week',
              'bl_tax_garnish', 'bl_bill_reason', 'bl_bills_issue', 'bl_bills_collect', 'bl_bills_next', 'bl_sinks_settle', 'bl_sink_blocked',
              'bl_sink_any_blocked', 'bl_chief_title', 'bl_chief_area', 'bl_donor_badge', 'bl_party_join', 'bl_prestige_guard', 'bl_dealer_net']) loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'bank_transfer_quote(bigint, text)', 'tax_info()', 'bank_sinks()', 'bills_pay(bigint)', 'bills_pay_all()', 'tax_pay(bigint)',
    'donate_city(bigint)', 'donors_top(int)', 'city_party_status()', 'city_party_throw()', 'chief_titles()', 'chief_title_buy(int, text)',
    'admin_economy_overview(int)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
