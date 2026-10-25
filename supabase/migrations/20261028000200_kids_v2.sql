-- Kids v2 (docs/LOVE.md "Kids v2", docs/MOMENTS.md): five life stages with their own needs, care that uses real items from the bag,
-- random illness with a doctor card for BOTH parents (the life-moments engine, 20261028000100), relatives that cost each parent a share,
-- a gentle passing away (switchable), and a small thank-you gift when a child grows up.
-- Rules for this file:
--   * NOTHING here touches public.profiles (no ALTER, no trigger, no foreign key): a first deploy of kids deadlocked on it (SQLSTATE 40P01).
--     The kids_parent_left trigger that already exists (20261027000200_family_kids_links.sql) only has its FUNCTION body replaced.
--   * Idempotent: columns `if not exists`, seeds `on conflict do nothing`, kids_* functions `create or replace` (they are ours), every
--     OTHER live function is patched through a guarded replace (raises when the marker is missing, skips when already applied).
--   * Settings are only moved while they still hold the old defaults (an admin's own number is never overwritten).
--   * Server stays light: no global scans. The daily illness roll, the passing away and the relatives refund all live in kids_children.next_alert_at,
--     which the existing sweep (bl_push_tick -> bl_kids_alert_sweep, indexed kids_children_due) already takes in batches.

create or replace function pg_temp.kv_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'kids_v2: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Kids)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('kids.daily_sick_pct', '12', 'kids', 'Chance a child falls ill each day (%)',
 'Once every Benin day each child at home has this chance of getting an illness from Content -> Child illnesses. Both parents get a card from the doctor. Neglect can still make a child sick on top of this.', 'percent', 0, 100),
('kids.sick_min_age_hours', '12', 'kids', 'No illness for the first hours (hours)',
 'A newborn cannot fall ill by chance in its first hours at home.', 'number', 0, 720),
('kids.change_restore', '60', 'kids', 'A diaper change gives clean',
 'Points of Clean one diaper change restores (newborn and baby).', 'number', 1, 100),
('kids.change_cooldown_minutes', '10', 'kids', 'Wait between diaper changes (minutes)',
 'Per child, shared by both parents.', 'minutes', 0, 1440),
('kids.reclaim_cost_each', '200000', 'kids', 'Bringing a child home: each parent pays',
 'Naira EACH parent pays to bring a child home from relatives. Either parent can pay their share; the child comes home when both shares are paid (a parent on their own pays only their share). A money sink: ledger kid_reclaim, never earnings.', 'naira', 0, 100000000),
('kids.reclaim_window_days', '3', 'kids', 'Days to pay both shares',
 'If only one parent has paid when this many days pass, that share is refunded (ledger kid_reclaim_refund) and the child stays with relatives. 0 = shares never expire.', 'number', 0, 90),
('kids.passing_enabled', 'true', 'kids', 'Gentle passing away on',
 'On = a child whose Health stays at 0 for the hours below, after several warnings were sent and ignored, passes away. Both parents are told kindly and the Family tab keeps a candle. Off = this can never happen.', 'bool', null, null),
('kids.passing_hours', '72', 'kids', 'Hours at zero Health before passing away',
 'Health must stay at 0 this long. Any medicine or doctor that lifts Health resets it.', 'number', 1, 720),
('kids.passing_min_warnings', '3', 'kids', 'Warnings that must be ignored first',
 'Needs-attention alerts plus doctor cards that nobody answered. Fewer than this and the child never passes away.', 'number', 1, 20),
('kids.grief_days', '3', 'kids', 'Days of grief before trying again',
 'After a child passes away the couple cannot try for another baby for this long.', 'number', 0, 90),
('kids.grief_mood_points', '15', 'kids', 'Low mood after a loss (points)',
 'A small, short dip in Fun (and Social, half as much) and a rise in Stress for both parents. It fades like any need.', 'number', 0, 50),
('kids.gift_gold', '100000', 'kids', 'Thank-you gift: Gold (each parent)',
 'Naira each parent gets once when a well raised child grows up (ledger kid_gift, never counted as earnings). It is a CEILING: it is also capped by the share of what that parent really spent on the child (below), so raising always costs far more than the gift.', 'naira', 0, 100000000),
('kids.gift_silver', '50000', 'kids', 'Thank-you gift: Silver (each parent)',
 'See Gold.', 'naira', 0, 100000000),
('kids.gift_bronze', '20000', 'kids', 'Thank-you gift: Bronze (each parent)',
 'See Gold.', 'naira', 0, 100000000),
('kids.gift_max_spend_pct', '25', 'kids', 'Gift is at most this % of what the parent spent',
 'The gift can never be more than this share of the supplies, lunch money, doctor fees and school costs that parent paid for the child. Keeps baby farming from paying.', 'percent', 0, 100),
('kids.tier_gold_min', '85', 'kids', 'Care score for Gold (0-100)',
 'Care score = the share of time the child''s needs were above the alert level, minus the penalty for each time relatives had to take them in.', 'number', 0, 100),
('kids.tier_silver_min', '65', 'kids', 'Care score for Silver (0-100)', 'See Gold.', 'number', 0, 100),
('kids.tier_bronze_min', '40', 'kids', 'Care score for Bronze (0-100)', 'Under this there is no tier and no gift. The child still grows up and the parents still get the plain Proud parent badge.', 'number', 0, 100),
('kids.removal_penalty', '25', 'kids', 'Care score lost when relatives took the child in',
 'Points taken off the care score for each time the child was with relatives.', 'number', 0, 100)
on conflict (key) do nothing;

-- moved only while they still equal the old defaults
update public.game_config set value = '1500'::jsonb where key = 'kids.feed_cost' and value in ('400'::jsonb, '"400"'::jsonb);
update public.game_config set label = 'Lunch money per meal (Nursery and older)',
  description = 'Naira a parent pays in cash each time they feed a child from Nursery up (no item needed). Newborns and babies eat formula or cereal from the bag instead. A money sink (ledger kid_care), never earnings. 0 = free.'
 where key = 'kids.feed_cost';
update public.game_config set label = 'Medicine cost (not used any more)',
  description = 'Not used any more: medicine now uses a medicine item from the bag (Content -> Kids items).' where key = 'kids.medicine_cost';
update public.game_config set label = 'Cost to bring a child home (not used any more)',
  description = 'Not used any more: each parent now pays "Bringing a child home: each parent pays".' where key = 'kids.reclaim_cost';
delete from public.game_config where key = 'kids.medicine_cost' and value in ('1500'::jsonb, '"1500"'::jsonb);
delete from public.game_config where key = 'kids.reclaim_cost' and value in ('10000'::jsonb, '"10000"'::jsonb);
update public.game_config set description = 'Real days from birth until the child grows up and moves out. The parents get a Proud parent badge (Gold, Silver or Bronze by how well the child was raised) and a thank-you gift. The stages are in Content -> Child stages.'
 where key = 'kids.grow_days';
-- baby and kids items are VAT free (like food and health): only while the list still holds its first value
update public.game_config set value = '"food,drink,fish,health,hygiene,phone,offering,baby,kids"'::jsonb
 where key = 'economy.vat_exempt_categories' and value = '"food,drink,fish,health,hygiene,phone,offering"'::jsonb;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables and columns
-- ---------------------------------------------------------------------------------------------
alter table public.kids_stages add column if not exists rate_clean numeric not null default 0 check (rate_clean between 0 and 50);
alter table public.kids_stages add column if not exists needs text[] not null default '{hunger,sleep,fun,health,love}';

alter table public.kids_children add column if not exists clean numeric not null default 80 check (clean between 0 and 100);
alter table public.kids_children add column if not exists clean_at timestamptz;
alter table public.kids_children add column if not exists illness_id text;
alter table public.kids_children add column if not exists illness_n integer not null default 0;
alter table public.kids_children add column if not exists doctor_ignored integer not null default 0 check (doctor_ignored >= 0);
alter table public.kids_children add column if not exists next_roll_at timestamptz;
alter table public.kids_children add column if not exists passed_at timestamptz;
alter table public.kids_children add column if not exists care_good numeric not null default 0;
alter table public.kids_children add column if not exists care_total numeric not null default 0;
alter table public.kids_children add column if not exists score_at timestamptz;
alter table public.kids_children add column if not exists care_score integer;
alter table public.kids_children add column if not exists tier text check (tier is null or tier in ('gold', 'silver', 'bronze', 'none'));
alter table public.kids_children add column if not exists gift_a bigint;
alter table public.kids_children add column if not exists gift_b bigint;
alter table public.kids_children add column if not exists spent_a bigint not null default 0;
alter table public.kids_children add column if not exists spent_b bigint not null default 0;
alter table public.kids_children add column if not exists reclaim_a_at timestamptz;
alter table public.kids_children add column if not exists reclaim_b_at timestamptz;
alter table public.kids_children add column if not exists reclaim_a_amt bigint;
alter table public.kids_children add column if not exists reclaim_b_amt bigint;

-- status 'passed' and the new care action 'change' (small tables of ours; no lock on profiles)
do $$
declare cn text;
begin
  select conname into cn from pg_constraint
   where conrelid = 'public.kids_children'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%expecting%with_relatives%' and pg_get_constraintdef(oid) not like '%passed%';
  if cn is not null then
    execute format('alter table public.kids_children drop constraint %I', cn);
    alter table public.kids_children add constraint kids_children_status_check check (status in ('expecting', 'home', 'with_relatives', 'grown', 'gone', 'passed'));
  end if;
  select conname into cn from pg_constraint
   where conrelid = 'public.kids_care_log'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%feed%cuddle%' and pg_get_constraintdef(oid) not like '%change%';
  if cn is not null then
    execute format('alter table public.kids_care_log drop constraint %I', cn);
    alter table public.kids_care_log add constraint kids_care_log_action_check check (action in ('feed', 'change', 'sleep', 'play', 'medicine', 'cuddle'));
  end if;
end $$;

-- live children get the new clocks (a fresh grace: nobody is punished for the update)
update public.kids_children set clean = 80, clean_at = bl_now() where clean_at is null and status in ('home', 'with_relatives');
update public.kids_children set score_at = coalesce(last_care_at, born_at, bl_now()) where score_at is null and status in ('home', 'with_relatives');

-- Items that care uses. role: formula, cereal, diaper, paracetamol, malaria, toy. uses = how many feeds / changes / doses one unit gives.
-- stages = the stage ids it is for (empty = every stage). boost_pct: feeding or play restore bonus (toys +, cereal -).
create table if not exists public.kids_items (
  item_id   text primary key references public.items(id) on delete cascade,
  role      text not null check (role in ('formula', 'cereal', 'diaper', 'paracetamol', 'malaria', 'toy')),
  uses      integer not null default 1 check (uses between 1 and 100),
  stages    text[] not null default '{}',
  boost_pct numeric not null default 0 check (boost_pct between -90 and 300),
  sort      integer not null default 100,
  active    boolean not null default true
);

-- Random illnesses (Content -> Child illnesses). moment_id = the doctor card (Content -> Life moments). med_item empty = paracetamol syrup works.
create table if not exists public.kids_illnesses (
  id         text primary key check (id ~ '^[a-z][a-z0-9_]{1,24}$'),
  name       text not null check (char_length(name) between 2 and 30),
  emoji      text not null default '🤒' check (char_length(emoji) between 1 and 8),
  blurb      text not null default '' check (char_length(blurb) <= 160),
  min_days   numeric not null default 0 check (min_days >= 0),
  max_days   numeric not null default 999 check (max_days > 0),
  weight     numeric not null default 1 check (weight between 0 and 1000),
  health_hit numeric not null default 10 check (health_hit between 0 and 100),
  med_item   text,
  moment_id  text not null,
  sort       integer not null default 100,
  active     boolean not null default true
);

-- Partly used supplies: a tin opened with 5 feeds left. No foreign key to profiles (nothing to deadlock; cleaned up when a parent leaves).
create table if not exists public.kids_charges (
  user_id uuid not null,
  item_id text not null,
  uses_left integer not null default 0 check (uses_left >= 0),
  primary key (user_id, item_id)
);

-- Price rules per place (Content -> Shop prices): mult x the item's price, daily_pct = how far the price moves each Benin day
-- (deterministic per day, the same for everybody). No rule = the item's own price.
create table if not exists public.shop_price_rules (
  id         text primary key check (id ~ '^[a-z0-9_:\-]{2,60}$'),
  location_id text not null references public.locations(id) on delete cascade,
  item_id    text references public.items(id) on delete cascade,
  category   text,
  mult       numeric not null default 1 check (mult between 0.1 and 10),
  daily_pct  numeric not null default 0 check (daily_pct between 0 and 50),
  active     boolean not null default true,
  check ((item_id is null) <> (category is null))
);
create index if not exists shop_price_rules_item on public.shop_price_rules (location_id, item_id) where item_id is not null;
create index if not exists shop_price_rules_cat on public.shop_price_rules (location_id, category) where category is not null;

do $$
declare t text;
begin
  foreach t in array array['kids_items', 'kids_illnesses', 'kids_charges', 'shop_price_rules'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

create or replace function public.bl_kids_text_guard2() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if bl_chat_mask(new.name) <> new.name or bl_chat_mask(coalesce(new.blurb, '')) <> coalesce(new.blurb, '') then
    raise exception 'Keep the words clean: there is a banned word.' using errcode = 'P0001', hint = 'blocked_text';
  end if;
  return new;
end $$;
drop trigger if exists kids_illnesses_guard on public.kids_illnesses;
create trigger kids_illnesses_guard before insert or update of name, blurb on public.kids_illnesses for each row execute function public.bl_kids_text_guard2();

-- ---------------------------------------------------------------------------------------------
-- 3. Seeds: stages, the supermarket, baby items, prices, illnesses, doctor cards
-- ---------------------------------------------------------------------------------------------
-- Stages: only while the four old rows still hold their first values (an admin's own edits are kept as they are)
do $$
begin
  if exists (select 1 from kids_stages where id = 'baby' and from_days = 0 and rate_hunger = 3.0 and rate_sleep = 2.0 and rate_fun = 1.5 and rate_health = 0.5 and rate_love = 2.0)
     and exists (select 1 from kids_stages where id = 'toddler' and from_days = 3 and rate_hunger = 2.5)
     and exists (select 1 from kids_stages where id = 'child' and from_days = 8 and rate_hunger = 2.0)
     and exists (select 1 from kids_stages where id = 'teen' and from_days = 14 and rate_hunger = 1.5)
     and not exists (select 1 from kids_stages where id in ('newborn', 'nursery', 'primary', 'secondary')) then
    update kids_stages set active = false where id in ('toddler', 'child', 'teen');
    update kids_stages set from_days = 2, name = 'Baby', emoji = '👶', rate_hunger = 2.8, rate_sleep = 1.8, rate_clean = 2.2, rate_fun = 0, rate_health = 0.45, rate_love = 1.8,
                           needs = '{hunger,sleep,clean,love,health}', sort = 20 where id = 'baby';
    insert into kids_stages (id, name, emoji, from_days, rate_hunger, rate_sleep, rate_clean, rate_fun, rate_health, rate_love, needs, sort) values
    ('newborn',   'Newborn',   '🍼', 0,  3.0, 2.0, 2.5, 0,   0.5,  2.0, '{hunger,sleep,clean,love,health}', 10),
    ('nursery',   'Nursery',   '🧒', 5,  2.5, 1.5, 0,   2.2, 0.4,  1.5, '{hunger,sleep,fun,love,health}', 30),
    ('primary',   'Primary',   '🎒', 8,  2.0, 1.2, 0,   2.0, 0.3,  1.2, '{hunger,sleep,fun,love,health}', 40),
    ('secondary', 'Secondary', '🧑', 14, 1.5, 0,   0,   1.8, 0.3,  1.0, '{hunger,fun,love,health}', 50)
    on conflict (id) do nothing;
  end if;
end $$;

-- The supermarket: a fictional, always open, fixed-price shop on Mission Road (no real brand)
insert into public.locations (id, name, district, scene, blurb, x, y, actions, sort)
values ('edo_fresh_supermarket', 'Edo Fresh Supermarket', 'oredo', 'mall',
        'A cool, bright supermarket on Mission Road with baby care, groceries and cold drinks. It never closes and its prices never move.', 468, 420, '{shop}', 44)
on conflict (id) do nothing;

insert into public.items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort, tradeable) values
('kid_formula', 'Baby formula tin', 'baby', 16800, 'About 8 feeds for a newborn or baby. Kept in the bag and used when you feed them (Family -> Kids).', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '🍼', 900, false),
('kid_cereal', 'Baby cereal pack', 'baby', 5000, 'About 6 small feeds for a baby (not a newborn). Cheaper than formula, a little less filling.', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '🥣', 901, false),
('kid_diapers', 'Diapers, jumbo pack', 'baby', 8900, 'About 16 changes for a newborn or baby. Used when you change a diaper (Family -> Kids).', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '🧷', 902, false),
('kid_paracetamol', 'Children''s paracetamol syrup', 'baby', 1150, 'About 6 doses for fever, pain and teething. Used by Medicine (Family -> Kids).', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '🧴', 903, false),
('kid_malaria', 'Malaria drugs for a child', 'baby', 3400, 'One full course of child-size malaria medicine. Used by Medicine when the illness is malaria.', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '💊', 904, false),
('kid_teddy', 'Teddy bear', 'kids', 2200, 'A soft toy. Makes playtime better for a Nursery child. Kept for good.', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '🧸', 910, false),
('kid_ball', 'Football', 'kids', 2500, 'A bouncy ball for Nursery and Primary children. Kept for good.', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '⚽', 911, false),
('kid_puzzle', 'Puzzle set', 'kids', 4800, 'A big picture puzzle for Nursery and Primary children. Kept for good.', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '🧩', 912, false),
('kid_console', 'Game console', 'kids', 20000, 'A small game console for teenagers. Makes playtime much better. Kept for good.', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '🎮', 913, false)
on conflict (id) do nothing;

-- the supermarket also sells everyday basics (its checkout, snack and shelf zones are the mall's, and an empty zone is a broken place)
update public.items set sold_at = sold_at || '{edo_fresh_supermarket}'
 where id in ('bottled_water', 'airtime', 'noodles_pack', 'soap', 'cornflakes_milk', 'meat_pie', 'popcorn') and not ('edo_fresh_supermarket' = any (sold_at));

insert into public.kids_items (item_id, role, uses, stages, boost_pct, sort) values
('kid_formula',     'formula',     8,  '{newborn,baby}',            0,   20),
('kid_cereal',      'cereal',      6,  '{baby}',                    -30, 10),
('kid_diapers',     'diaper',      16, '{newborn,baby}',            0,   10),
('kid_paracetamol', 'paracetamol', 6,  '{}',                        0,   10),
('kid_malaria',     'malaria',     1,  '{}',                        0,   20),
('kid_teddy',       'toy',         1,  '{nursery}',                 25,  10),
('kid_ball',        'toy',         1,  '{nursery,primary}',         35,  20),
('kid_puzzle',      'toy',         1,  '{nursery,primary}',         40,  30),
('kid_console',     'toy',         1,  '{secondary}',               60,  40)
on conflict (item_id) do nothing;

-- Oba Market: the item price, moving up to 10 % a Benin day. The supermarket: 25 % dearer, never moves.
insert into public.shop_price_rules (id, location_id, category, mult, daily_pct) values
('oba:baby',   'oba_market',            'baby', 1,    10),
('oba:kids',   'oba_market',            'kids', 1,    10),
('super:baby', 'edo_fresh_supermarket', 'baby', 1.25, 0),
('super:kids', 'edo_fresh_supermarket', 'kids', 1.25, 0)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Prices: Oba Market moves a little every day, the supermarket is fixed (a patch of the dealer price all shops use)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_shop_price(p_item public.items, p_location text) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare r public.shop_price_rules; v_p numeric; v_h bigint; v_day text;
begin
  select * into r from shop_price_rules x where x.active and x.location_id = p_location and x.item_id = p_item.id limit 1;
  if not found then
    select * into r from shop_price_rules x where x.active and x.location_id = p_location and x.item_id is null and x.category = p_item.category limit 1;
    if not found then return null; end if;
  end if;
  v_p := p_item.price * r.mult;
  if r.daily_pct > 0 then
    v_day := to_char(bl_now() at time zone bl_clock_tz(), 'YYYY-MM-DD');
    v_h := ('x' || substr(md5(v_day || ':' || p_item.id || ':' || p_location), 1, 8))::bit(32)::bigint;
    if v_h >= 2147483648 then v_h := v_h - 4294967296; end if;
    v_p := v_p * (1 + (r.daily_pct / 100.0) * (v_h / 2147483648.0));
  end if;
  if v_p < 1000 then return (round(v_p / 10.0) * 10)::bigint; end if;
  return (round(v_p / 50.0) * 50)::bigint;
end $$;

select pg_temp.kv_patch('public.bl_dealer_net(public.items, text)',
  $o$when p_item.category <> 'vehicle' then p_item.price$o$,
  $o$when p_item.category <> 'vehicle' then coalesce(bl_shop_price(p_item, p_location), p_item.price)$o$,
  $o$bl_shop_price(p_item, p_location)$o$);

-- ---------------------------------------------------------------------------------------------
-- 5. Private helpers: stages, needs, supplies
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_needs() returns text[]
language sql immutable set search_path = public as $$
  select array['hunger', 'sleep', 'clean', 'fun', 'health', 'love']
$$;

create or replace function public.bl_kids_reason(p_need text) returns text
language sql immutable set search_path = public as $$
  select case p_need when 'hunger' then 'hungry' when 'sleep' then 'sleepy' when 'clean' then 'needing a change' when 'fun' then 'bored'
                     when 'health' then 'unwell' else 'wanting a cuddle' end
$$;

create or replace function public.bl_kids_stage_row(c public.kids_children, p_at timestamptz default null) returns public.kids_stages
language plpgsql stable security definer set search_path = public as $$
declare s public.kids_stages; v_age numeric;
begin
  if c.born_at is null then
    select * into s from kids_stages k where k.active order by k.from_days limit 1;
    return s;
  end if;
  v_age := floor(extract(epoch from (coalesce(p_at, bl_now()) - c.born_at)) / 86400);
  select * into s from kids_stages k where k.active and k.from_days <= v_age order by k.from_days desc limit 1;
  if not found then select * into s from kids_stages k where k.active order by k.from_days limit 1; end if;
  return s;
end $$;

create or replace function public.bl_kids_stage_of(c public.kids_children, p_at timestamptz default null) returns text
language sql stable security definer set search_path = public as $$
  select (bl_kids_stage_row(c, p_at)).id
$$;

create or replace function public.bl_kids_stage_needs(c public.kids_children, p_at timestamptz default null) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare s public.kids_stages;
begin
  s := bl_kids_stage_row(c, p_at);
  if s.id is null then return array['hunger', 'sleep', 'fun', 'health', 'love']; end if;
  return s.needs;
end $$;

-- the need's loss per hour in a stage: 0 when the stage does not have that need
create or replace function public.bl_kids_rate(s public.kids_stages, p_need text) returns numeric
language sql immutable set search_path = public as $$
  select case when p_need = any (s.needs) then coalesce((to_jsonb(s) ->> ('rate_' || p_need))::numeric, 0) else 0 end
$$;

-- Total points the need loses between t0 and t1, summing each life stage's rate over the time spent in it.
create or replace function public.bl_kids_drain(c public.kids_children, p_need text, t0 timestamptz, t1 timestamptz) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare s record; v_total numeric := 0; v_a timestamptz; v_b timestamptz;
begin
  if t0 is null or t1 <= t0 or c.born_at is null then return 0; end if;
  for s in
    select row_number() over (order by k.from_days) as rn, k.from_days, lead(k.from_days) over (order by k.from_days) as nxt, bl_kids_rate(k, p_need) as rate
      from kids_stages k where k.active order by k.from_days
  loop
    v_a := case when s.rn = 1 then t0 else greatest(t0, c.born_at + s.from_days * interval '1 day') end;
    v_b := case when s.nxt is null then t1 else least(t1, c.born_at + s.nxt * interval '1 day') end;
    if v_b > v_a then v_total := v_total + s.rate * extract(epoch from (v_b - v_a)) / 3600; end if;
  end loop;
  return v_total;
end $$;

-- When the need falls under p_level (strictly: one second after it touches the level). Null = never. The stored value alone decides this.
create or replace function public.bl_kids_cross(c public.kids_children, p_need text, p_level numeric) returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare
  v numeric := (to_jsonb(c) ->> p_need)::numeric; t0 timestamptz := (to_jsonb(c) ->> (p_need || '_at'))::timestamptz;
  v_rem numeric; s record; v_a timestamptz; v_b timestamptz; v_cap numeric;
begin
  if t0 is null or c.born_at is null then return null; end if;
  if v < p_level then return t0; end if;
  v_rem := v - p_level;
  for s in
    select row_number() over (order by k.from_days) as rn, k.from_days, lead(k.from_days) over (order by k.from_days) as nxt, bl_kids_rate(k, p_need) as rate
      from kids_stages k where k.active order by k.from_days
  loop
    v_a := case when s.rn = 1 then t0 else greatest(t0, c.born_at + s.from_days * interval '1 day') end;
    v_b := case when s.nxt is null then 'infinity'::timestamptz else c.born_at + s.nxt * interval '1 day' end;
    if v_b <= v_a or s.rate <= 0 then continue; end if;
    if v_b = 'infinity'::timestamptz then
      return v_a + ((v_rem / s.rate)::double precision) * interval '1 hour' + interval '1 second';
    end if;
    v_cap := s.rate * extract(epoch from (v_b - v_a)) / 3600;
    if v_cap >= v_rem then
      return v_a + ((v_rem / s.rate)::double precision) * interval '1 hour' + interval '1 second';
    end if;
    v_rem := v_rem - v_cap;
  end loop;
  return null;
end $$;

-- Needs of the child's CURRENT stage that are under the alert level right now (lowest first); a sick child always counts as unwell.
create or replace function public.bl_kids_needy(c public.kids_children, p_at timestamptz default null) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare n text; v numeric; v_lvl numeric := bl_love_num('kids.alert_below', 30); v_out text[] := '{}'; v_rows jsonb := '[]'::jsonb; v_st text[];
begin
  if c.status <> 'home' then return v_out; end if;
  v_st := bl_kids_stage_needs(c, p_at);
  foreach n in array bl_kids_needs() loop
    continue when not (n = any (v_st));
    v := bl_kids_val(c, n, p_at);
    if v < v_lvl then v_rows := v_rows || jsonb_build_object('n', n, 'v', v); end if;
  end loop;
  if c.sick_since is not null and not exists (select 1 from jsonb_array_elements(v_rows) x where x ->> 'n' = 'health') then
    v_rows := v_rows || jsonb_build_object('n', 'health', 'v', 0);
  end if;
  select coalesce(array_agg(x ->> 'n' order by (x ->> 'v')::numeric, x ->> 'n'), '{}') into v_out from jsonb_array_elements(v_rows) x;
  return v_out;
end $$;

-- When a healthy child will fall sick from neglect (a need of its stage at 0 for kids.neglect_hours). Null when already sick or never.
create or replace function public.bl_kids_sick_at(c public.kids_children) returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare n text; t timestamptz; v_best timestamptz; v_st text[];
begin
  if c.status <> 'home' or c.sick_since is not null then return null; end if;
  v_st := bl_kids_stage_needs(c, null);
  foreach n in array bl_kids_needs() loop
    continue when not (n = any (v_st));
    t := bl_kids_cross(c, n, 0);
    if t is not null and (v_best is null or t < v_best) then v_best := t; end if;
  end loop;
  if v_best is null then return null; end if;
  v_best := v_best + make_interval(secs => (bl_love_num('kids.neglect_hours', 24) * 3600)::double precision);
  if c.cured_at is not null then
    v_best := greatest(v_best, c.cured_at + make_interval(secs => (bl_love_num('kids.sick_grace_hours', 6) * 3600)::double precision));
  end if;
  return v_best;
end $$;

-- When a child would pass away: Health at 0 for kids.passing_hours AND enough warnings sent and ignored. Null = never (or switched off).
create or replace function public.bl_kids_pass_at(c public.kids_children) returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare t timestamptz;
begin
  if c.status <> 'home' or not coalesce(bl_cfg_bool('kids.passing_enabled'), true) then return null; end if;
  if c.alerts_unanswered + c.doctor_ignored < bl_love_num('kids.passing_min_warnings', 3)::int then return null; end if;
  t := bl_kids_cross(c, 'health', 0);
  if t is null then return null; end if;
  return t + make_interval(secs => (bl_love_num('kids.passing_hours', 72) * 3600)::double precision);
end $$;

-- the next daily illness roll: tomorrow (Benin day), spread over 08:00 to 20:00 by the child's id so the sweep is never bunched up
create or replace function public.bl_kids_roll_time(p_id bigint, p_after timestamptz) returns timestamptz
language sql stable set search_path = public as $$
  select (date_trunc('day', p_after at time zone bl_clock_tz()) + interval '1 day' + make_interval(mins => (480 + (p_id * 7919) % 720)::int)) at time zone bl_clock_tz()
$$;

update public.kids_children set next_roll_at = bl_kids_roll_time(id, bl_now()) where next_roll_at is null and status = 'home';

-- everything that is scheduled for a child (kind, time): used by the settle loop AND by next_alert_at, so they can never disagree
create or replace function public.bl_kids_due(c public.kids_children) returns table (kind text, at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  v_t timestamptz; v_win interval := make_interval(days => bl_love_num('kids.reclaim_window_days', 3)::int);
  v_a boolean; v_b boolean; v_req int; v_paid int;
begin
  if c.status = 'home' then
    if c.name is null and c.born_at is not null then
      return query select 'name'::text, c.born_at + make_interval(hours => bl_love_num('kids.name_grace_hours', 24)::int);
    end if;
    v_t := bl_kids_sick_at(c);
    if v_t is not null then return query select 'sick'::text, v_t; end if;
    if c.next_roll_at is not null then return query select 'roll'::text, c.next_roll_at; end if;
    return query select 'removal'::text, c.last_care_at + make_interval(days => bl_love_num('kids.removal_days', 7)::int);
    return query select 'grow'::text, c.born_at + make_interval(days => bl_love_num('kids.grow_days', 21)::int);
    v_t := bl_kids_pass_at(c);
    if v_t is not null then return query select 'pass'::text, v_t; end if;
  elsif c.status = 'with_relatives' then
    if c.name is null and c.born_at is not null then
      return query select 'name'::text, c.born_at + make_interval(hours => bl_love_num('kids.name_grace_hours', 24)::int);
    end if;
    v_a := c.parent_a is not null; v_b := c.parent_b is not null;
    v_req := (case when v_a then 1 else 0 end) + (case when v_b then 1 else 0 end);
    v_paid := (case when v_a and c.reclaim_a_at is not null then 1 else 0 end) + (case when v_b and c.reclaim_b_at is not null then 1 else 0 end);
    if v_req > 0 and v_paid = v_req then
      return query select 'reclaim_done'::text, bl_now();
    elsif v_paid > 0 and bl_love_num('kids.reclaim_window_days', 3) > 0 then
      return query select 'refund'::text, least(coalesce(c.reclaim_a_at, 'infinity'::timestamptz), coalesce(c.reclaim_b_at, 'infinity'::timestamptz)) + v_win;
    end if;
  end if;
end $$;

-- Quiet hours (Benin clock): unchanged, kept here so this file is the whole picture
create or replace function public.bl_kids_next(c public.kids_children) returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare
  v_best timestamptz; v_t timestamptz; v_x timestamptz; n text; d record; v_age numeric; v_st text[];
  v_below numeric := bl_love_num('kids.alert_below', 30);
begin
  if c.status = 'expecting' then return c.due_at; end if;
  if c.status not in ('home', 'with_relatives') then return null; end if;
  for d in select * from bl_kids_due(c) loop
    if v_best is null or d.at < v_best then v_best := d.at; end if;
  end loop;
  if c.status <> 'home' then return v_best; end if;
  -- the next life stage starts: new needs begin to count
  v_age := floor(extract(epoch from (bl_now() - c.born_at)) / 86400);
  select c.born_at + make_interval(days => min(k.from_days)::int) into v_x from kids_stages k where k.active and k.from_days > v_age;
  if v_x is not null and (v_best is null or v_x < v_best) then v_best := v_x; end if;
  if c.alerts_unanswered < bl_love_num('kids.max_alerts_unanswered', 4)::int then
    v_t := null;
    v_st := bl_kids_stage_needs(c, null);
    foreach n in array bl_kids_needs() loop
      continue when not (n = any (v_st));
      v_x := bl_kids_cross(c, n, v_below);
      if v_x is not null and (v_t is null or v_x < v_t) then v_t := v_x; end if;
    end loop;
    if c.sick_since is not null then v_t := least(coalesce(v_t, c.sick_since), c.sick_since); end if;
    if v_t is not null then
      if c.last_alert_at is not null then
        v_t := greatest(v_t, c.last_alert_at + make_interval(secs => (bl_love_num('kids.alert_cooldown_hours', 3) * 3600)::double precision));
      end if;
      -- a need that is already low means "alert now" (or when the quiet hours end), never a time in the past: the sweep would spin on it
      v_t := bl_kids_quiet_shift(greatest(v_t, bl_now()));
      if v_best is null or v_t < v_best then v_best := v_t; end if;
    end if;
  end if;
  return v_best;
end $$;

-- who may propose a baby: now with the days of grief after a loss
create or replace function public.bl_kids_eligibility(r public.love_relationships) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_days numeric := bl_love_num('kids.min_couple_days', 2); v_since numeric; v_n int; u uuid; v_cap int; v_g timestamptz; v_gd numeric := bl_love_num('kids.grief_days', 3);
begin
  if not bl_kids_can_start() then
    return jsonb_build_object('code', 'off', 'msg', 'Babies are resting for now. Check back soon.');
  end if;
  if r.status <> 'couple' then
    return jsonb_build_object('code', 'not_couple', 'msg', 'Only a couple can have a baby. Keep building your bond first.');
  end if;
  v_since := extract(epoch from (bl_now() - coalesce(r.couple_at, r.started_at))) / 86400;
  if v_since < v_days then
    return jsonb_build_object('code', 'too_soon', 'msg', 'You need to be a couple for ' || v_days::int || ' days first: '
      || bl_love_wait_text((v_days - v_since) * 86400) || ' to go.');
  end if;
  select max(k.passed_at) into v_g from kids_children k where k.parent_a = r.user_a and k.parent_b = r.user_b and k.status = 'passed';
  if v_g is not null and v_gd > 0 and v_g + make_interval(secs => (v_gd * 86400)::double precision) > bl_now() then
    return jsonb_build_object('code', 'grief', 'msg', 'Take a little time to heal together. You can think about another baby in '
      || bl_love_wait_text(extract(epoch from (v_g + make_interval(secs => (v_gd * 86400)::double precision) - bl_now()))) || '.');
  end if;
  if exists (select 1 from kids_children k where k.parent_a = r.user_a and k.parent_b = r.user_b and k.status = 'expecting') then
    return jsonb_build_object('code', 'expecting', 'msg', 'You are already expecting a little one.');
  end if;
  select count(*) into v_n from kids_children k where k.parent_a = r.user_a and k.parent_b = r.user_b and k.status in ('expecting', 'home', 'with_relatives');
  if v_n >= bl_love_num('kids.max_children_per_couple', 3)::int then
    return jsonb_build_object('code', 'pair_cap', 'msg', 'Your family is full for now: ' || v_n || ' children at the same time is the limit.');
  end if;
  v_cap := bl_love_num('kids.max_children_per_player', 5)::int;
  foreach u in array array[r.user_a, r.user_b] loop
    select (select count(*) from kids_children k where k.parent_a = u and k.status in ('expecting', 'home', 'with_relatives'))
         + (select count(*) from kids_children k where k.parent_b = u and k.status in ('expecting', 'home', 'with_relatives')) into v_n;
    if v_n >= v_cap then
      return jsonb_build_object('code', 'player_cap', 'msg', 'One of you already looks after ' || v_cap || ' children, which is the most for one person.');
    end if;
  end loop;
  return null;
end $$;

-- ---- supplies ----
-- how many uses of an item the player has (opened charges + units x uses)
create or replace function public.bl_kids_left(p_uid uuid, p_item text) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce((select uses_left from kids_charges where user_id = p_uid and item_id = p_item), 0)
       + coalesce((select i.qty from inventory i where i.user_id = p_uid and i.item_id = p_item), 0) * coalesce((select ki.uses from kids_items ki where ki.item_id = p_item), 1)
$$;

-- Take one use. Opens a new unit from the bag when the opened one is empty. Raises when there is nothing.
create or replace function public.bl_kids_use(p_uid uuid, p_item text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uses int; v_left int;
begin
  select ki.uses into v_uses from kids_items ki where ki.item_id = p_item;
  if v_uses is null then raise exception 'That is not a kids supply.' using errcode = 'P0001', hint = 'no_item'; end if;
  select uses_left into v_left from kids_charges where user_id = p_uid and item_id = p_item for update;
  if coalesce(v_left, 0) > 0 then
    update kids_charges set uses_left = uses_left - 1 where user_id = p_uid and item_id = p_item;
    return;
  end if;
  if coalesce((select qty from inventory where user_id = p_uid and item_id = p_item), 0) < 1 then
    raise exception 'You do not have that.' using errcode = 'P0001', hint = 'no_item';
  end if;
  perform bl_give_item(p_uid, p_item, -1);
  insert into kids_charges (user_id, item_id, uses_left) values (p_uid, p_item, v_uses - 1)
  on conflict (user_id, item_id) do update set uses_left = v_uses - 1;
end $$;

-- the supply items of some roles that fit a stage (empty stages = every stage), best first
create or replace function public.bl_kids_supply_rows(p_roles text[], p_stage text) returns setof public.kids_items
language sql stable security definer set search_path = public as $$
  select * from kids_items k where k.active and k.role = any (p_roles) and (cardinality(k.stages) = 0 or p_stage = any (k.stages)) order by k.sort, k.item_id
$$;

-- where to buy an item: [{id,name,open,price,kind}] (cheapest first)
create or replace function public.bl_kids_buy_info(p_item text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare it public.items; l public.locations; v_out jsonb := '[]'::jsonb;
begin
  select * into it from items where id = p_item;
  if not found then return v_out; end if;
  for l in select x.* from locations x where x.active and x.id = any (it.sold_at) order by x.sort loop
    v_out := v_out || jsonb_build_object('id', l.id, 'name', l.name, 'open', bl_place_open(l), 'price', bl_dealer_price(it, l.id),
                                         'kind', case when l.scene = 'market' then 'market' else 'supermarket' end);
  end loop;
  select coalesce(jsonb_agg(x order by (x ->> 'price')::bigint), '[]'::jsonb) into v_out from jsonb_array_elements(v_out) x;
  return v_out;
end $$;

-- the best toy bonus (play restore %) the player owns for this stage
create or replace function public.bl_kids_toy(p_uid uuid, p_stage text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('item', k.item_id, 'name', i.name, 'boost', k.boost_pct)
                     from bl_kids_supply_rows(array['toy'], p_stage) k join items i on i.id = k.item_id
                    where exists (select 1 from inventory v where v.user_id = p_uid and v.item_id = k.item_id and v.qty > 0)
                    order by k.boost_pct desc limit 1), 'null'::jsonb)
$$;

-- Add to what a parent has spent on a child (supplies, lunch money, doctor, reclaim shares). The thank-you gift is capped by this.
create or replace function public.bl_kids_spent(p_child bigint, p_uid uuid, p_amount bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_amount, 0) = 0 or p_uid is null then return; end if;
  update kids_children set spent_a = greatest(0, spent_a + case when parent_a = p_uid then p_amount else 0 end),
                           spent_b = greatest(0, spent_b + case when parent_b = p_uid then p_amount else 0 end)
   where id = p_child and (parent_a = p_uid or parent_b = p_uid);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. What a care action does right now: {"ok","code","msg","wait","cost", and for item care: "item","item_name","left","buy"}
-- ---------------------------------------------------------------------------------------------
drop function if exists public.bl_kids_can(public.kids_children, text, timestamptz);
create or replace function public.bl_kids_can(c public.kids_children, p_action text, p_at timestamptz, p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_now timestamptz := coalesce(p_at, bl_now());
  v_need text := case p_action when 'feed' then 'hunger' when 'change' then 'clean' when 'sleep' then 'sleep' when 'play' then 'fun' when 'medicine' then 'health' when 'cuddle' then 'love' end;
  v_cd numeric := bl_love_num('kids.' || p_action || '_cooldown_minutes', 30) * 60;
  v_last timestamptz; v_wait numeric; v_val numeric; v_nm text := bl_kids_label(c); s public.kids_stages; v_cost bigint := 0;
  v_item text; v_it public.items; v_ill public.kids_illnesses; v_roles text[]; r public.kids_items; v_first text; v_extra jsonb := '{}'::jsonb; v_left int;
begin
  if v_need is null then
    return jsonb_build_object('ok', false, 'code', 'bad_action', 'msg', 'Pick feed, change, sleep, play, medicine or cuddle.', 'wait', 0, 'cost', 0);
  end if;
  if c.status <> 'home' then
    return jsonb_build_object('ok', false, 'code', 'not_home', 'wait', 0, 'cost', 0,
      'msg', case c.status when 'expecting' then 'The baby has not arrived yet.' when 'with_relatives' then v_nm || ' is with relatives right now.'
                           when 'grown' then v_nm || ' has grown up and moved out.' when 'passed' then v_nm || ' is at rest now.' else v_nm || ' is not here any more.' end);
  end if;
  s := bl_kids_stage_row(c, v_now);
  if p_action <> 'medicine' and not (v_need = any (s.needs)) then
    return jsonb_build_object('ok', false, 'code', 'na', 'wait', 0, 'cost', 0, 'msg', '');
  end if;
  select created_at into v_last from kids_care_log where child_id = c.id and action = p_action order by id desc limit 1;
  if v_last is not null then
    v_wait := extract(epoch from (v_last + make_interval(secs => v_cd::double precision) - v_now));
    if v_wait > 0 then
      return jsonb_build_object('ok', false, 'code', 'cooldown', 'wait', ceil(v_wait), 'cost', 0,
                                'msg', 'Easy. You can do that again in ' || bl_love_wait_text(v_wait) || '.');
    end if;
  end if;
  v_val := bl_kids_val(c, v_need, v_now);
  if p_action = 'medicine' then
    if c.sick_since is null and v_val >= bl_love_num('kids.medicine_below', 60) then
      return jsonb_build_object('ok', false, 'code', 'not_needed', 'wait', 0, 'cost', 0, 'msg', v_nm || ' is not unwell. Medicine is only for a child who needs it.');
    end if;
  elsif v_val >= bl_love_num('kids.care_max', 90) then
    return jsonb_build_object('ok', false, 'code', 'not_needed', 'wait', 0, 'cost', 0,
      'msg', v_nm || case p_action when 'feed' then ' is full for now.' when 'change' then ' is clean and dry.' when 'sleep' then ' is not sleepy now.'
                                   when 'play' then ' has had enough play for now.' else ' has had lots of love just now.' end);
  end if;

  -- items
  if p_action = 'feed' then
    v_roles := array['formula', 'cereal'];
    if exists (select 1 from bl_kids_supply_rows(v_roles, s.id)) then
      for r in select * from bl_kids_supply_rows(v_roles, s.id) loop
        if bl_kids_left(p_uid, r.item_id) > 0 then v_item := r.item_id; exit; end if;
      end loop;
      if v_item is null then
        select item_id into v_first from bl_kids_supply_rows(array['formula'], s.id) limit 1;
        v_first := coalesce(v_first, (select item_id from bl_kids_supply_rows(v_roles, s.id) limit 1));
      end if;
    else
      v_cost := bl_love_num('kids.feed_cost', 1500)::bigint;
    end if;
  elsif p_action = 'change' then
    for r in select * from bl_kids_supply_rows(array['diaper'], s.id) loop
      if bl_kids_left(p_uid, r.item_id) > 0 then v_item := r.item_id; exit; end if;
      v_first := coalesce(v_first, r.item_id);
    end loop;
  elsif p_action = 'medicine' then
    if c.illness_id is not null then select * into v_ill from kids_illnesses where id = c.illness_id; end if;
    if v_ill.med_item is not null then
      v_first := v_ill.med_item;
      if bl_kids_left(p_uid, v_first) > 0 then v_item := v_first; end if;
    else
      for r in select * from bl_kids_supply_rows(array['paracetamol'], s.id) loop
        if bl_kids_left(p_uid, r.item_id) > 0 then v_item := r.item_id; exit; end if;
        v_first := coalesce(v_first, r.item_id);
      end loop;
    end if;
  end if;
  if v_first is not null and v_item is null then
    select * into v_it from items where id = v_first;
    return jsonb_build_object('ok', false, 'code', 'no_item', 'wait', 0, 'cost', 0, 'item', v_first, 'item_name', v_it.name, 'left', 0, 'buy', bl_kids_buy_info(v_first),
      'msg', case p_action when 'feed' then 'No formula at home. ' when 'change' then 'No diapers at home. ' else 'No ' || lower(v_it.name) || ' at home. ' end
             || 'Buy ' || case p_action when 'feed' then 'a tin' when 'change' then 'a pack' else 'some' end || ' at Oba Market or the supermarket.');
  end if;
  if v_item is not null then
    select * into v_it from items where id = v_item;
    v_left := bl_kids_left(p_uid, v_item);
    v_extra := jsonb_build_object('item', v_item, 'item_name', v_it.name, 'left', v_left);
  end if;
  return jsonb_build_object('ok', true, 'code', 'ok', 'wait', 0, 'cost', v_cost, 'msg', '') || v_extra;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Score, gift, illness, passing away, relatives, bringing home
-- ---------------------------------------------------------------------------------------------
-- Add the time since the last tick to the care score: for every need of the stage, how long it stayed above the alert level.
create or replace function public.bl_kids_score_tick(c public.kids_children, p_at timestamptz) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare n text; v_a timestamptz := coalesce(c.score_at, c.born_at); v_dt numeric; v_good numeric := 0; v_tot numeric := 0; t timestamptz; v_st text[]; v_lvl numeric := bl_love_num('kids.alert_below', 30);
begin
  if c.status <> 'home' or v_a is null or p_at <= v_a then return c; end if;
  v_dt := extract(epoch from (p_at - v_a));
  v_st := bl_kids_stage_needs(c, p_at);
  foreach n in array bl_kids_needs() loop
    continue when not (n = any (v_st));
    t := bl_kids_cross(c, n, v_lvl);
    v_tot := v_tot + v_dt;
    v_good := v_good + case when t is null then v_dt else greatest(0, least(extract(epoch from (p_at - v_a)), extract(epoch from (t - v_a)))) end;
  end loop;
  update kids_children set care_good = care_good + v_good, care_total = care_total + v_tot, score_at = p_at where id = c.id returning * into c;
  return c;
end $$;

-- Grow up: final care score, tier, the one-time thank-you gift (capped by what the parent really spent), alert.
create or replace function public.bl_kids_finish(c public.kids_children, p_at timestamptz) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare
  v_share numeric; v_score int; v_tier text; v_gift bigint := 0; v_cap numeric := bl_love_num('kids.gift_max_spend_pct', 25) / 100.0; u uuid; v_paid bigint; v_nm text; v_spent bigint; v_msg text;
begin
  c := bl_kids_score_tick(c, p_at);
  v_share := case when c.care_total > 0 then c.care_good / c.care_total else 1 end;
  v_score := greatest(0, round(100 * v_share)::int - (bl_love_num('kids.removal_penalty', 25) * c.removals)::int);
  v_tier := case when v_score >= bl_love_num('kids.tier_gold_min', 85) then 'gold' when v_score >= bl_love_num('kids.tier_silver_min', 65) then 'silver'
                 when v_score >= bl_love_num('kids.tier_bronze_min', 40) then 'bronze' else 'none' end;
  v_gift := case v_tier when 'gold' then bl_love_num('kids.gift_gold', 100000) when 'silver' then bl_love_num('kids.gift_silver', 50000)
                        when 'bronze' then bl_love_num('kids.gift_bronze', 20000) else 0 end;
  v_nm := bl_kids_label(c);
  update kids_children set status = 'grown', grown_at = p_at, sick_since = null, illness_id = null, next_alert_at = null, care_score = v_score, tier = v_tier, gift_a = 0, gift_b = 0
   where id = c.id returning * into c;
  foreach u in array array[c.parent_a, c.parent_b] loop
    continue when u is null;
    v_spent := case when u = c.parent_a then c.spent_a else c.spent_b end;
    v_paid := least(v_gift::bigint, floor(v_spent * v_cap)::bigint);
    if v_paid > 0 then
      perform bl_add_money(u, 'cash', v_paid, 'kid_gift', jsonb_build_object('label', 'Thank-you gift from ' || v_nm, 'child', c.id, 'tier', v_tier));
    end if;
    v_msg := v_nm || ' is moving out with a keepsake from you both.'
             || case when v_tier = 'none' then ' You are a Proud parent 🏅'
                     else ' You earned the ' || initcap(v_tier) || ' Proud parent badge 🏅' || case when v_paid > 0 then ' and a thank-you gift of ' || bl_naira(v_paid) || '.' else '.' end end;
    perform bl_kids_notify(u, 'kids_grown', '🎓 ' || v_nm || ' has grown up!', v_msg, c.id, jsonb_build_object('tier', v_tier, 'gift', v_paid, 'score', v_score));
    if u = c.parent_a then update kids_children set gift_a = v_paid where id = c.id; else update kids_children set gift_b = v_paid where id = c.id; end if;
  end loop;
  select * into c from kids_children where id = c.id;
  return c;
end $$;

-- Close every open doctor card for a child (somebody treated them, or they passed away).
create or replace function public.bl_kids_close_cards(p_child bigint, p_by uuid, p_by_name text, p_close_own boolean default false) returns void
language plpgsql security definer set search_path = public as $$
begin
  update player_moments set status = 'answered', handled_by = case when p_by is null then null else p_by end,
         outcome = case when p_by is null then null else 'Already handled by @' || coalesce(p_by_name, 'your partner') || ' 💛' end,
         answered_at = bl_now(), seen_at = case when p_by is null then bl_now() else null end
   where context ->> 'child_id' = p_child::text and status in ('pending', 'snoozed', 'scheduled') and user_id is distinct from p_by
     and moment_id in (select id from life_moments where kind = 'kids_ill');
  if p_close_own and p_by is not null then
    update player_moments set status = 'expired', answered_at = bl_now(), seen_at = bl_now()
     where context ->> 'child_id' = p_child::text and status in ('pending', 'snoozed', 'scheduled') and user_id = p_by
       and moment_id in (select id from life_moments where kind = 'kids_ill');
  end if;
end $$;

-- The child falls ill: health takes a hit, both parents get the doctor card and an alert.
create or replace function public.bl_kids_make_sick(c public.kids_children, p_illness text, p_at timestamptz, p_hit boolean default true) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare ill public.kids_illnesses; v_h numeric; v_cur numeric; u uuid; v_nm text := bl_kids_label(c);
begin
  select * into ill from kids_illnesses where id = p_illness;
  if not found then return c; end if;
  v_cur := bl_kids_val(c, 'health', p_at);
  v_h := greatest(0, v_cur - case when p_hit then ill.health_hit else 0 end);
  -- the health clock is only rewritten when the illness really takes points (so "health at zero since" stays true)
  update kids_children set sick_since = p_at, sick_med = false, sick_cuddle = false, illness_id = ill.id, illness_n = illness_n + 1,
         health = case when v_h < v_cur then v_h else health end, health_at = case when v_h < v_cur then p_at else health_at end
   where id = c.id returning * into c;
  foreach u in array array[c.parent_a, c.parent_b] loop
    continue when u is null;
    perform bl_moment_create(u, ill.moment_id, jsonb_build_object('child_id', c.id, 'ep', c.illness_n, 'illness', ill.id), bl_now(), true);
  end loop;
  perform bl_kids_notify_both(c, 'kids_sick', ill.emoji || ' ' || v_nm || ' is unwell', 'Dr. Osagie sent you a message about ' || v_nm || '. Open the game to answer.');
  return c;
end $$;

-- A child is brought home from relatives (all shares paid): needs reset, clocks restart.
create or replace function public.bl_kids_bring_home(c public.kids_children, p_at timestamptz, p_by uuid default null) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare v_start numeric := bl_love_num('kids.reclaim_need', 60); v_nm text := bl_kids_label(c);
begin
  update kids_children set status = 'home', reclaims = reclaims + 1, relatives_at = null, last_care_at = p_at, last_alert_at = null, alerts_unanswered = 0, doctor_ignored = 0,
         sick_since = null, sick_med = false, sick_cuddle = false, illness_id = null, reclaim_a_at = null, reclaim_b_at = null, reclaim_a_amt = null, reclaim_b_amt = null,
         hunger = v_start, hunger_at = p_at, sleep = v_start, sleep_at = p_at, fun = v_start, fun_at = p_at, health = v_start, health_at = p_at, love = v_start, love_at = p_at,
         clean = v_start, clean_at = p_at, score_at = p_at, next_roll_at = bl_kids_roll_time(c.id, p_at)
   where id = c.id returning * into c;
  perform bl_kids_notify_both(c, 'kids_home', v_nm || ' is back home 🏠', 'Both of you brought ' || v_nm || ' home from relatives. Look after them well.');
  return c;
end $$;

-- A child passes away, gently. Both parents are told kindly, a small short dip in mood, the doctor cards close.
create or replace function public.bl_kids_pass(c public.kids_children, p_at timestamptz) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare v_nm text := bl_kids_label(c); u uuid; v_pts numeric := bl_love_num('kids.grief_mood_points', 15);
begin
  c := bl_kids_score_tick(c, p_at);
  update kids_children set status = 'passed', passed_at = p_at, sick_since = null, next_alert_at = null where id = c.id returning * into c;
  perform bl_kids_close_cards(c.id, null, null);
  perform bl_kids_notify_both(c, 'kids_passed', 'We are so sorry 💛', 'We are so sorry. After a long illness, ' || v_nm || ' passed away. Rest well, little one 🕊️');
  if v_pts > 0 then
    foreach u in array array[c.parent_a, c.parent_b] loop
      continue when u is null;
      perform bl_adjust_needs(u, jsonb_build_object('fun', -v_pts, 'social', -round(v_pts / 2), 'stress', v_pts));
    end loop;
  end if;
  return c;
end $$;

-- ---- hooks the life-moments engine calls (effects: kid_need, kid_cure, kid_ignore, and the card's cost) ----
create or replace function public.bl_kids_moment_open(p_ctx jsonb) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from kids_children k where k.id = nullif(p_ctx ->> 'child_id', '')::bigint and k.status = 'home' and k.sick_since is not null
                  and k.illness_n::text = coalesce(p_ctx ->> 'ep', k.illness_n::text))
$$;

create or replace function public.bl_kids_moment_need(p_uid uuid, p_child bigint, p_need text, p_delta numeric, p_all boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.kids_children; v_now timestamptz := bl_now(); v_cur numeric; v_new numeric; v_out jsonb := '[]'::jsonb; v_ids bigint[];
begin
  if p_all then
    select coalesce(array_agg(k.id), '{}') into v_ids from (select id from kids_children where (parent_a = p_uid or parent_b = p_uid) and status = 'home' order by id limit 5) k;
  else
    v_ids := array[p_child];
  end if;
  foreach p_child in array v_ids loop
    select * into c from kids_children where id = p_child and (parent_a = p_uid or parent_b = p_uid) and status = 'home' for update;
    continue when not found;
    c := bl_kids_score_tick(c, v_now);
    v_cur := bl_kids_val(c, p_need, v_now);
    v_new := greatest(0, least(100, v_cur + p_delta));
    if v_new <> v_cur then
      execute format('update kids_children set %I = %L, %I = %L where id = %s', p_need, v_new, p_need || '_at', v_now, c.id);
    end if;
    perform bl_kids_process(c.id, false);
    v_out := v_out || to_jsonb(bl_kids_label(c) || ' ' || p_need || case when p_delta >= 0 then ' +' else ' ' end || p_delta::int);
  end loop;
  return v_out;
end $$;

create or replace function public.bl_kids_moment_cure(p_uid uuid, p_child bigint, p_ctx jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.kids_children; v_now timestamptz := bl_now(); v_who text; v_other uuid;
begin
  select * into c from kids_children where id = p_child and (parent_a = p_uid or parent_b = p_uid) and status = 'home' for update;
  if not found or c.sick_since is null then return '[]'::jsonb; end if;
  update kids_children set sick_since = null, sick_med = false, sick_cuddle = false, cured_at = v_now, illness_id = null, doctor_ignored = 0, alerts_unanswered = 0, last_care_at = v_now
   where id = c.id returning * into c;
  select username into v_who from profiles where id = p_uid;
  perform bl_kids_close_cards(c.id, p_uid, v_who);
  v_other := case when c.parent_a = p_uid then c.parent_b else c.parent_a end;
  perform bl_kids_notify(v_other, 'kids_cured', '💚 ' || bl_kids_label(c) || ' is feeling better', '@' || coalesce(v_who, 'your partner') || ' took ' || bl_kids_label(c) || ' to the doctor.', c.id);
  perform bl_kids_process(c.id, false);
  return to_jsonb(bl_kids_label(c) || ' is feeling better');
end $$;

create or replace function public.bl_kids_moment_ignore(p_child bigint, p_ctx jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  update kids_children set doctor_ignored = doctor_ignored + 1 where id = p_child and status = 'home' and sick_since is not null
     and illness_n::text = coalesce(p_ctx ->> 'ep', illness_n::text);
  perform bl_kids_process(p_child, false);
end $$;

create or replace function public.bl_kids_moment_paid(p_uid uuid, p_ctx jsonb, p_cost bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform bl_kids_spent(nullif(p_ctx ->> 'child_id', '')::bigint, p_uid, p_cost);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Settle: everything whose time has come, in the order it happened. Locks the row. Alerts are NOT sent here (bl_kids_process does that).
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_settle(p_id bigint) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare
  c public.kids_children; v_now timestamptz := bl_now(); v_i int := 0; v_best timestamptz; v_kind text;
  v_start numeric := bl_love_num('kids.start_need', 80);
  v_pick text; v_nm_txt text; v_next timestamptz; ill public.kids_illnesses; v_sum numeric; v_r numeric; v_age numeric; v_day text;
  v_amt bigint; u uuid;
begin
  select * into c from kids_children where id = p_id for update;
  if not found then return null; end if;
  if not bl_kids_on() then return c; end if;
  loop
    v_i := v_i + 1;
    exit when v_i > 10;
    if c.status = 'expecting' then
      exit when c.due_at > v_now;
      update kids_children set status = 'home', born_at = v_now,
             hunger = v_start, hunger_at = v_now, sleep = v_start, sleep_at = v_now, fun = v_start, fun_at = v_now,
             health = v_start, health_at = v_now, love = v_start, love_at = v_now, clean = v_start, clean_at = v_now,
             last_care_at = v_now, last_alert_at = null, alerts_unanswered = 0, score_at = v_now, next_roll_at = bl_kids_roll_time(c.id, v_now)
       where id = c.id returning * into c;
      perform bl_kids_notify_both(c, 'kids_born', 'Your baby is here! 👶', 'Come and name them. Open Family to meet your little one.');
      continue;
    elsif c.status not in ('home', 'with_relatives') then
      exit;
    end if;
    v_kind := null; v_best := null;
    select x.kind, x.at into v_kind, v_best from bl_kids_due(c) x where x.at <= v_now order by x.at limit 1;
    exit when v_kind is null;

    if v_kind = 'name' then
      select n.name into v_pick from kids_auto_names n where n.active order by random() limit 1;
      v_pick := coalesce(v_pick, 'Osaze');
      update kids_children set name = v_pick, gender = case when random() < 0.5 then 'boy' else 'girl' end, auto_named = true, named_by = null
       where id = c.id and name is null returning * into c;
      perform bl_kids_notify_both(c, 'kids_named', '👶 Your baby is now called ' || v_pick,
                                  'Nobody picked a name in time, so the game chose one. Give ' || v_pick || ' lots of love.');
    elsif v_kind = 'sick' then
      c := bl_kids_make_sick(c, 'fever', v_best, false);
    elsif v_kind = 'roll' then
      v_age := extract(epoch from (v_now - c.born_at)) / 86400;
      v_day := to_char(v_now at time zone bl_clock_tz(), 'YYYY-MM-DD');
      if c.sick_since is null and extract(epoch from (v_now - c.born_at)) / 3600 >= bl_love_num('kids.sick_min_age_hours', 12)
         and bl_rand() * 100 < bl_love_num('kids.daily_sick_pct', 12) then
        select coalesce(sum(i.weight), 0) into v_sum from kids_illnesses i where i.active and i.weight > 0 and v_age >= i.min_days and v_age < i.max_days;
        if v_sum > 0 then
          v_r := ((('x' || substr(md5(c.id::text || ':' || v_day), 1, 8))::bit(32)::bigint) & 2147483647) / 2147483648.0 * v_sum;
          v_pick := null;
          for ill in select * from kids_illnesses i where i.active and i.weight > 0 and v_age >= i.min_days and v_age < i.max_days order by i.sort, i.id loop
            v_pick := ill.id;
            v_r := v_r - ill.weight;
            exit when v_r < 0;
          end loop;
          if v_pick is not null then c := bl_kids_make_sick(c, v_pick, v_now, true); end if;
        end if;
      end if;
      update kids_children set next_roll_at = bl_kids_roll_time(c.id, v_now) where id = c.id returning * into c;
    elsif v_kind = 'removal' then
      v_nm_txt := bl_kids_label(c);
      c := bl_kids_score_tick(c, v_best);
      perform bl_kids_close_cards(c.id, null, null);
      if c.removals + 1 >= 2 then
        update kids_children set status = 'gone', gone_reason = 'relatives', removals = c.removals + 1, relatives_at = v_best, sick_since = null, next_alert_at = null
         where id = c.id returning * into c;
        perform bl_kids_notify_both(c, 'kids_gone', v_nm_txt || ' now lives with relatives 💛',
                                    'Nobody could look after them for a long time, so relatives are raising ' || v_nm_txt || ' for good. Take your time, and be there for any next little one.');
      else
        update kids_children set status = 'with_relatives', removals = c.removals + 1, relatives_at = v_best, sick_since = null, sick_med = false, sick_cuddle = false, illness_id = null,
               reclaim_a_at = null, reclaim_b_at = null, reclaim_a_amt = null, reclaim_b_amt = null
         where id = c.id returning * into c;
        perform bl_kids_notify_both(c, 'kids_relatives', v_nm_txt || ' is staying with relatives for now 💛',
                                    'Nobody could look after them for ' || bl_love_num('kids.removal_days', 7)::int || ' days, so relatives took them in. Each parent can pay a share to bring ' || v_nm_txt || ' home from Family.');
      end if;
    elsif v_kind = 'refund' then
      -- only one parent paid in time: the share goes back, the child stays with relatives
      foreach u in array array[c.parent_a, c.parent_b] loop
        continue when u is null;
        v_amt := case when u = c.parent_a then c.reclaim_a_amt else c.reclaim_b_amt end;
        continue when coalesce(v_amt, 0) <= 0 or (case when u = c.parent_a then c.reclaim_a_at else c.reclaim_b_at end) is null;
        perform bl_add_money(u, 'bank', v_amt, 'kid_reclaim_refund', jsonb_build_object('label', 'Share returned for ' || bl_kids_label(c), 'child', c.id));
        perform bl_kids_spent(c.id, u, -v_amt);
        perform bl_kids_notify(u, 'kids_refund', 'Your ' || bl_naira(v_amt) || ' share is back', 'The other parent did not pay in time, so ' || bl_kids_label(c) || ' stays with relatives for now and your money was returned to your bank.', c.id);
      end loop;
      update kids_children set reclaim_a_at = null, reclaim_b_at = null, reclaim_a_amt = null, reclaim_b_amt = null where id = c.id returning * into c;
    elsif v_kind = 'reclaim_done' then
      c := bl_kids_bring_home(c, v_now);
    elsif v_kind = 'pass' then
      c := bl_kids_pass(c, v_now);
    else
      c := bl_kids_finish(c, v_best);
    end if;
  end loop;
  v_next := bl_kids_next(c);
  if c.next_alert_at is distinct from v_next then
    update kids_children set next_alert_at = v_next where id = c.id returning * into c;
  end if;
  return c;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. The child as the app shows it
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_child_json(c public.kids_children, p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_now timestamptz := bl_now(); v_age int; s public.kids_stages; v_needs jsonb := '{}'::jsonb; v_acts jsonb := '{}'::jsonb; n text; a text;
  v_other uuid := case when c.parent_a = p_uid then c.parent_b else c.parent_a end; v_pn text; v_pav jsonb; v_log jsonb; v_needy text[];
  v_can jsonb; v_rel jsonb := null; v_grace timestamptz; v_removal timestamptz; v_wait numeric; v_ill jsonb := null; ill public.kids_illnesses; v_sup jsonb := '[]'::jsonb;
  r public.kids_items; it public.items; v_doc bigint; v_mine boolean := coalesce(c.parent_a = p_uid, false); v_mine_at timestamptz; v_part_at timestamptz; v_lone boolean;
  v_paid_me boolean; v_paid_other boolean; v_toy jsonb;
begin
  if c.born_at is not null then
    v_age := floor(extract(epoch from (v_now - c.born_at)) / 86400)::int;
    s := bl_kids_stage_row(c, v_now);
  end if;
  if v_other is not null then select username, avatar into v_pn, v_pav from profiles where id = v_other; end if;
  if c.status in ('home', 'with_relatives') and s.id is not null then
    foreach n in array bl_kids_needs() loop
      continue when not (n = any (s.needs));
      v_needs := v_needs || jsonb_build_object(n, floor(bl_kids_val(c, n, v_now))::int);
    end loop;
  end if;
  if c.status = 'home' then
    v_needy := bl_kids_needy(c, v_now);
    foreach a in array array['feed', 'change', 'sleep', 'play', 'medicine', 'cuddle'] loop
      v_can := bl_kids_can(c, a, v_now, p_uid);
      continue when v_can ->> 'code' = 'na';
      v_acts := v_acts || jsonb_build_object(a, v_can);
    end loop;
    v_removal := c.last_care_at + make_interval(days => bl_love_num('kids.removal_days', 7)::int);
    if c.sick_since is not null and c.illness_id is not null then
      select * into ill from kids_illnesses where id = c.illness_id;
      if found then
        v_ill := jsonb_build_object('id', ill.id, 'name', ill.name, 'emoji', ill.emoji, 'blurb', replace(ill.blurb, '{child}', coalesce(c.name, 'Your baby')), 'med_item', ill.med_item);
      end if;
    end if;
    -- supplies this stage uses (what the parent has left)
    for r in select * from bl_kids_supply_rows(array['formula', 'cereal', 'diaper', 'paracetamol'], s.id) loop
      select * into it from items where id = r.item_id;
      v_sup := v_sup || jsonb_build_object('role', r.role, 'item', r.item_id, 'name', it.name, 'icon', it.icon, 'left', bl_kids_left(p_uid, r.item_id),
                                           'unit', case r.role when 'formula' then 'feeds' when 'cereal' then 'feeds' when 'diaper' then 'changes' else 'doses' end);
    end loop;
    if ill.med_item is not null then
      select * into it from items where id = ill.med_item;
      v_sup := v_sup || jsonb_build_object('role', 'illness_med', 'item', ill.med_item, 'name', it.name, 'icon', it.icon, 'left', bl_kids_left(p_uid, ill.med_item), 'unit', 'doses');
    end if;
    v_toy := bl_kids_toy(p_uid, s.id);
    select m.id into v_doc from player_moments m where m.user_id = p_uid and m.context ->> 'child_id' = c.id::text and m.status in ('pending', 'snoozed', 'scheduled')
       and m.moment_id in (select id from life_moments where kind = 'kids_ill') order by m.id desc limit 1;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'action', g.action, 'mine', g.user_id = p_uid, 'who', coalesce(pr.username, 'a parent'), 'created_at', g.created_at) order by g.id desc), '[]'::jsonb)
    into v_log from (select * from kids_care_log where child_id = c.id order by id desc limit 8) g left join profiles pr on pr.id = g.user_id;
  if c.status = 'with_relatives' then
    v_wait := greatest(0, ceil(extract(epoch from (c.relatives_at + make_interval(hours => bl_love_num('kids.reclaim_wait_hours', 12)::int) - v_now))));
    v_lone := c.parent_a is null or c.parent_b is null;
    v_mine_at := case when v_mine then c.reclaim_a_at else c.reclaim_b_at end;
    v_part_at := case when v_mine then c.reclaim_b_at else c.reclaim_a_at end;
    v_paid_me := v_mine_at is not null; v_paid_other := v_part_at is not null;
    v_rel := jsonb_build_object('since', c.relatives_at, 'removals', c.removals, 'wait_seconds', v_wait, 'used', c.reclaims >= 1,
      'cost_each', bl_love_num('kids.reclaim_cost_each', 200000)::bigint, 'window_days', bl_love_num('kids.reclaim_window_days', 3),
      'lone', v_lone, 'mine_paid', v_paid_me, 'mine_at', v_mine_at,
      'partner', case when v_other is null then null else jsonb_build_object('id', v_other, 'username', v_pn, 'paid', v_paid_other, 'at', v_part_at) end,
      'can_pay', c.reclaims < 1 and v_wait <= 0 and not v_paid_me,
      'refund_at', case when (v_paid_me or v_paid_other) and bl_love_num('kids.reclaim_window_days', 3) > 0
                        then least(coalesce(c.reclaim_a_at, 'infinity'::timestamptz), coalesce(c.reclaim_b_at, 'infinity'::timestamptz)) + make_interval(days => bl_love_num('kids.reclaim_window_days', 3)::int) end);
  end if;
  v_grace := case when c.name is null and c.born_at is not null then c.born_at + make_interval(hours => bl_love_num('kids.name_grace_hours', 24)::int) end;
  return jsonb_build_object(
    'id', c.id, 'rel_id', c.rel_id, 'status', c.status, 'name', c.name, 'gender', c.gender, 'auto_named', c.auto_named,
    'named_by_me', c.named_by = p_uid, 'name_due_at', v_grace,
    'conceived_at', c.conceived_at, 'due_at', c.due_at, 'born_at', c.born_at, 'grown_at', c.grown_at, 'passed_at', c.passed_at,
    'age_days', v_age, 'stage', case when s.id is null then null else jsonb_build_object('id', s.id, 'name', s.name, 'emoji', s.emoji, 'needs', to_jsonb(s.needs)) end,
    'needs', v_needs, 'needy', coalesce(to_jsonb(v_needy), '[]'::jsonb), 'sick', c.sick_since is not null, 'illness', v_ill, 'doctor_moment', v_doc,
    'sick_med', c.sick_med, 'sick_cuddle', c.sick_cuddle,
    'actions', v_acts, 'supplies', v_sup, 'toy', v_toy, 'removal_at', v_removal,
    'partner', case when v_other is null then null else jsonb_build_object('id', v_other, 'username', v_pn, 'avatar', v_pav) end,
    'log', v_log, 'relatives', v_rel);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. Triggers (function bodies only: the kids_parent_left trigger on profiles already exists; nothing here alters profiles)
-- ---------------------------------------------------------------------------------------------
-- A parent leaving: the child stays with the other parent; shares they paid stay paid; their supplies and cards are cleaned up.
create or replace function public.bl_kids_parent_left() returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.kids_children; v_other uuid;
begin
  for c in select * from kids_children k where (k.parent_a = old.id or k.parent_b = old.id) and k.status in ('expecting', 'home', 'with_relatives') for update loop
    v_other := case when c.parent_a = old.id then c.parent_b else c.parent_a end;
    if v_other is null then
      update kids_children set status = 'gone', gone_reason = 'no_parents', next_alert_at = null, parent_a = null, parent_b = null where id = c.id;
    elsif c.status = 'expecting' then
      update kids_children set status = 'gone', gone_reason = 'cancelled', next_alert_at = null, parent_a = null, parent_b = null where id = c.id;
      perform bl_kids_notify(v_other, 'kids_cancelled', 'Your baby plans are cancelled',
                             'The other parent started a new life, so the expected baby will not arrive. You can try again with somebody new, when you are ready.', c.id);
    else
      update kids_children set parent_a = case when parent_a = old.id then null else parent_a end,
                               parent_b = case when parent_b = old.id then null else parent_b end,
                               next_alert_at = least(coalesce(next_alert_at, bl_now()), bl_now()) where id = c.id;
      perform bl_kids_notify(v_other, 'kids_handover', bl_kids_label(c) || ' is in your care now 💛',
                             'The other parent started a new life, so you are looking after ' || bl_kids_label(c) || ' on your own. They count on you.', c.id);
    end if;
  end loop;
  delete from kids_charges where user_id = old.id;
  delete from player_moments where user_id = old.id;
  delete from player_moment_state where user_id = old.id;
  return old;
end $$;

-- Kill switch: also shifts the new clocks
create or replace function public.bl_kids_switch() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_off boolean := not coalesce((new.value #>> '{}')::boolean, true); v_at timestamptz; v_d interval;
begin
  if v_off then
    insert into kids_pause (id, paused_at) values (1, bl_now()) on conflict (id) do update set paused_at = coalesce(kids_pause.paused_at, excluded.paused_at);
    return new;
  end if;
  select paused_at into v_at from kids_pause where id = 1;
  if v_at is null then return new; end if;
  v_d := greatest(interval '0', bl_now() - v_at);
  update kids_children set
    due_at = due_at + v_d, born_at = born_at + v_d, last_care_at = last_care_at + v_d, last_alert_at = last_alert_at + v_d,
    relatives_at = relatives_at + v_d, sick_since = sick_since + v_d, cured_at = cured_at + v_d,
    hunger_at = hunger_at + v_d, sleep_at = sleep_at + v_d, fun_at = fun_at + v_d, health_at = health_at + v_d, love_at = love_at + v_d, clean_at = clean_at + v_d,
    next_roll_at = next_roll_at + v_d, score_at = score_at + v_d, reclaim_a_at = reclaim_a_at + v_d, reclaim_b_at = reclaim_b_at + v_d,
    next_alert_at = next_alert_at + v_d
   where status in ('expecting', 'home', 'with_relatives');
  update kids_invites set expires_at = expires_at + v_d where status = 'pending';
  update kids_pause set paused_at = null where id = 1;
  return new;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 11. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_proud_tier(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select case when bl_kids_on() and exists (select 1 from profiles p where p.id = p_uid and p.show_relationship)
    then (select k.tier from (select tier from kids_children where parent_a = p_uid and status = 'grown' and tier in ('gold', 'silver', 'bronze')
                              union all select tier from kids_children where parent_b = p_uid and status = 'grown' and tier in ('gold', 'silver', 'bronze')) k
           order by case k.tier when 'gold' then 1 when 'silver' then 2 else 3 end limit 1) end
$$;

-- ONE cheap read for the app and the Family icon dot. Settles only MY children whose time has come (indexed, at most 20).
create or replace function public.kids_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_now  timestamptz := bl_now();
  c      public.kids_children;
  r      public.love_relationships;
  v_kids jsonb := '[]'::jsonb; v_cpl jsonb := '[]'::jsonb; v_in jsonb; v_out jsonb; v_grown jsonb; v_mem jsonb; v_att int := 0; v_proud int;
  v_el jsonb; v_pid uuid; v_pn text; v_pav jsonb; v_j jsonb; v_cost bigint := bl_love_num('kids.try_cost_each', 5000)::bigint;
  v_days numeric := bl_love_num('kids.min_couple_days', 2); v_last timestamptz;
begin
  if not exists (select 1 from profiles where id = v_uid) then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if not bl_kids_on() then
    return jsonb_build_object('enabled', false, 'attention', 0, 'poll_seconds', 60, 'children', '[]'::jsonb, 'couples', '[]'::jsonb,
                              'incoming', '[]'::jsonb, 'outgoing', '[]'::jsonb, 'grown', '[]'::jsonb, 'memorials', '[]'::jsonb, 'proud', 0);
  end if;
  for c in
    select * from (
      select * from kids_children k where k.parent_a = v_uid and k.status in ('expecting', 'home', 'with_relatives') and k.next_alert_at <= v_now
      union all
      select * from kids_children k where k.parent_b = v_uid and k.status in ('expecting', 'home', 'with_relatives') and k.next_alert_at <= v_now
    ) x order by id limit 20
  loop
    perform bl_kids_settle(c.id);
  end loop;

  for c in
    select * from (
      select * from kids_children k where k.parent_a = v_uid and k.status in ('expecting', 'home', 'with_relatives')
      union all
      select * from kids_children k where k.parent_b = v_uid and k.status in ('expecting', 'home', 'with_relatives')
    ) x order by id limit 20
  loop
    v_j := bl_kids_child_json(c, v_uid);
    if jsonb_array_length(v_j -> 'needy') > 0 then v_att := v_att + 1; end if;
    if c.status = 'expecting' then
      v_j := v_j || jsonb_build_object('proposed_by_me', c.proposed_by = v_uid);
    end if;
    v_kids := v_kids || v_j;
  end loop;

  for r in select * from love_relationships l where l.status = 'couple' and (l.user_a = v_uid or l.user_b = v_uid) order by l.id limit 3 loop
    v_pid := case when r.user_a = v_uid then r.user_b else r.user_a end;
    select username, avatar into v_pn, v_pav from profiles where id = v_pid;
    v_el := bl_kids_eligibility(r);
    select max(i.created_at) into v_last from kids_invites i where i.rel_id = r.id and i.from_user = v_uid;
    v_cpl := v_cpl || jsonb_build_object(
      'rel_id', r.id, 'partner', jsonb_build_object('id', v_pid, 'username', v_pn, 'avatar', v_pav),
      'couple_days', floor(extract(epoch from (v_now - coalesce(r.couple_at, r.started_at))) / 86400)::int,
      'min_days', v_days, 'can_try', v_el is null, 'why', v_el,
      'invite_wait_seconds', case when v_last is null then 0 else greatest(0, ceil(extract(epoch from (v_last + make_interval(secs => (bl_love_num('kids.invite_cooldown_hours', 6) * 3600)::double precision) - v_now)))) end);
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'rel_id', i.rel_id, 'expires_at', i.expires_at,
           'from', jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar)) order by i.id desc), '[]'::jsonb) into v_in
    from (select * from kids_invites where to_user = v_uid and status = 'pending' and expires_at > v_now order by id desc limit 5) i
    join profiles p on p.id = i.from_user;
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'rel_id', i.rel_id, 'expires_at', i.expires_at,
           'state', case when i.status = 'pending' then 'pending' when i.status = 'declined' then 'declined' else 'noreply' end,
           'to', jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar)) order by i.id desc), '[]'::jsonb) into v_out
    from (select * from kids_invites
           where from_user = v_uid and ((status = 'pending' and expires_at > v_now) or (status in ('declined', 'expired') and created_at > v_now - interval '24 hours')
                                          or (status = 'pending' and expires_at <= v_now and created_at > v_now - interval '48 hours'))
           order by id desc limit 5) i
    join profiles p on p.id = i.to_user;
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'gender', g.gender, 'grown_at', g.grown_at, 'tier', g.tier, 'score', g.care_score,
                                               'gift', case when g.parent_a = v_uid then g.gift_a else g.gift_b end) order by g.grown_at desc), '[]'::jsonb) into v_grown
    from (select * from (select * from kids_children k where k.parent_a = v_uid and k.status = 'grown'
                         union all select * from kids_children k where k.parent_b = v_uid and k.status = 'grown') y order by grown_at desc limit 10) g;
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'gender', g.gender, 'born_at', g.born_at, 'passed_at', g.passed_at,
                                               'days_lived', greatest(0, floor(extract(epoch from (g.passed_at - g.born_at)) / 86400))::int) order by g.passed_at desc), '[]'::jsonb) into v_mem
    from (select * from (select * from kids_children k where k.parent_a = v_uid and k.status = 'passed'
                         union all select * from kids_children k where k.parent_b = v_uid and k.status = 'passed') y order by passed_at desc limit 5) g;
  select count(*) into v_proud from (select 1 from kids_children k where k.parent_a = v_uid and k.status = 'grown'
                                     union all select 1 from kids_children k where k.parent_b = v_uid and k.status = 'grown') z;

  return jsonb_build_object(
    'enabled', true, 'can_start', bl_kids_can_start(),
    'poll_seconds', greatest(20, bl_love_num('kids.poll_seconds', 45)),
    'attention', v_att, 'children', v_kids, 'couples', v_cpl, 'incoming', v_in, 'outgoing', v_out, 'grown', v_grown, 'memorials', v_mem, 'proud', v_proud,
    'rules', jsonb_build_object(
      'try_cost_each', v_cost, 'pregnancy_days', bl_love_num('kids.pregnancy_days', 3), 'min_couple_days', v_days,
      'invite_expire_hours', bl_love_num('kids.invite_expire_hours', 24), 'grow_days', bl_love_num('kids.grow_days', 21),
      'alert_below', bl_love_num('kids.alert_below', 30), 'name_grace_hours', bl_love_num('kids.name_grace_hours', 24),
      'removal_days', bl_love_num('kids.removal_days', 7), 'neglect_hours', bl_love_num('kids.neglect_hours', 24),
      'reclaim_cost_each', bl_love_num('kids.reclaim_cost_each', 200000)::bigint, 'reclaim_wait_hours', bl_love_num('kids.reclaim_wait_hours', 12),
      'reclaim_window_days', bl_love_num('kids.reclaim_window_days', 3),
      'feed_cost', bl_love_num('kids.feed_cost', 1500)::bigint,
      'max_per_couple', bl_love_num('kids.max_children_per_couple', 3), 'max_per_player', bl_love_num('kids.max_children_per_player', 5)));
end $$;

-- Look after a child: feed / change / sleep / play / medicine / cuddle. Either parent. Items come from MY bag.
create or replace function public.kids_care(p_child bigint, p_action text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_now   timestamptz := bl_now();
  c       public.kids_children;
  v_can   jsonb; v_need text; v_cur numeric; v_add numeric; v_cost bigint; v_cured boolean := false; v_nm text; v_msg text; v_new numeric;
  v_item text; v_it public.items; v_ki public.kids_items; v_boost numeric := 0; v_toy jsonb; v_nominal bigint := 0; v_left int;
begin
  if not bl_kids_on() then
    raise exception 'Kids is resting for now.' using errcode = 'P0001', hint = 'off';
  end if;
  v_need := case p_action when 'feed' then 'hunger' when 'change' then 'clean' when 'sleep' then 'sleep' when 'play' then 'fun' when 'medicine' then 'health' when 'cuddle' then 'love' end;
  if v_need is null then
    raise exception 'Pick feed, change, sleep, play, medicine or cuddle.' using errcode = 'P0001', hint = 'bad_action';
  end if;
  c := bl_kids_settle(p_child);
  if c.id is null or (c.parent_a is distinct from v_me.id and c.parent_b is distinct from v_me.id) then
    raise exception 'That child is not yours to look after.' using errcode = 'P0001', hint = 'not_parent';
  end if;
  v_can := bl_kids_can(c, p_action, v_now, v_me.id);
  if not (v_can ->> 'ok')::boolean then
    raise exception '%', v_can ->> 'msg' using errcode = 'P0001', hint = v_can ->> 'code';
  end if;
  v_nm := bl_kids_label(c);
  v_cost := (v_can ->> 'cost')::bigint;
  v_item := v_can ->> 'item';
  c := bl_kids_score_tick(c, v_now);
  if v_cost > 0 then
    perform bl_sink_pay(v_me.id, v_cost, 'kid_care', jsonb_build_object('label', case p_action when 'feed' then 'Lunch money for ' else 'Care for ' end || v_nm, 'child', c.id, 'action', p_action));
    v_nominal := v_cost;
  end if;
  if v_item is not null then
    perform bl_kids_use(v_me.id, v_item);
    select * into v_ki from kids_items where item_id = v_item;
    select * into v_it from items where id = v_item;
    v_nominal := round(v_it.price::numeric / greatest(1, v_ki.uses))::bigint;
    if p_action = 'feed' then v_boost := v_ki.boost_pct; end if;
    v_left := bl_kids_left(v_me.id, v_item);
  end if;
  if p_action = 'play' then
    v_toy := bl_kids_toy(v_me.id, bl_kids_stage_of(c, v_now));
    if v_toy is not null and v_toy <> 'null'::jsonb then v_boost := (v_toy ->> 'boost')::numeric; end if;
  end if;
  if v_nominal > 0 then perform bl_kids_spent(c.id, v_me.id, v_nominal); end if;
  v_cur := bl_kids_val(c, v_need, v_now);
  v_add := bl_love_num('kids.' || p_action || '_restore', 40) * (1 + v_boost / 100.0);
  v_new := least(100, v_cur + v_add);
  execute format('update kids_children set %I = %L, %I = %L where id = %s', v_need, v_new, v_need || '_at', v_now, c.id);
  update kids_children set last_care_at = v_now, alerts_unanswered = 0 where id = c.id;
  if c.sick_since is not null and p_action = 'medicine' then update kids_children set sick_med = true where id = c.id; end if;
  if c.sick_since is not null and p_action = 'cuddle' then update kids_children set sick_cuddle = true where id = c.id; end if;
  select * into c from kids_children where id = c.id;
  if c.sick_since is not null and c.sick_med and c.sick_cuddle then
    update kids_children set sick_since = null, sick_med = false, sick_cuddle = false, cured_at = v_now, illness_id = null, doctor_ignored = 0 where id = c.id;
    perform bl_kids_close_cards(c.id, v_me.id, v_me.username, true);
    v_cured := true;
  end if;
  insert into kids_care_log (child_id, user_id, action, cost, created_at) values (c.id, v_me.id, p_action, v_cost, v_now);
  delete from kids_care_log where child_id = c.id and id < coalesce((select id from kids_care_log where child_id = c.id order by id desc offset 40 limit 1), 0);
  c := bl_kids_process(c.id, false);
  v_msg := case p_action
    when 'feed' then 'You fed ' || v_nm || '. Tummy full 🍼'
    when 'change' then v_nm || ' is clean and fresh again 🧷'
    when 'sleep' then v_nm || ' is sleeping peacefully 😴'
    when 'play' then 'You played with ' || v_nm || '. Lots of giggles 🎈'
    when 'medicine' then 'You gave ' || v_nm || ' medicine 💊'
    else 'A big cuddle for ' || v_nm || ' 🤗' end;
  if v_cured then v_msg := v_msg || ' ' || v_nm || ' is feeling better!';
  elsif c.sick_since is not null then v_msg := v_msg || case when c.sick_med and not c.sick_cuddle then ' Now a cuddle will help too.' when c.sick_cuddle and not c.sick_med then ' Medicine will help too.' else '' end;
  end if;
  return jsonb_build_object('message', v_msg, 'spent', v_cost, 'cured', v_cured, 'child', c.id, 'need', v_need, 'value', floor(v_new)::int,
                            'item', v_item, 'item_left', v_left);
end $$;

-- Pay MY share to bring a child home from relatives. The child comes home when every parent has paid (a lone parent pays only theirs).
drop function if exists public.kids_reclaim(bigint);
create or replace function public.kids_reclaim(p_child bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_now   timestamptz := bl_now();
  c       public.kids_children;
  v_cost  bigint := bl_love_num('kids.reclaim_cost_each', 200000)::bigint; v_wait numeric; v_nm text; v_a boolean; v_other uuid; v_done boolean; v_msg text;
begin
  if not bl_kids_on() then
    raise exception 'Kids is resting for now.' using errcode = 'P0001', hint = 'off';
  end if;
  c := bl_kids_settle(p_child);
  if c.id is null or (c.parent_a is distinct from v_me.id and c.parent_b is distinct from v_me.id) then
    raise exception 'That child is not yours.' using errcode = 'P0001', hint = 'not_parent';
  end if;
  if c.status <> 'with_relatives' then
    raise exception 'That child is not with relatives.' using errcode = 'P0001', hint = 'not_away';
  end if;
  if c.reclaims >= 1 then
    raise exception 'You already brought this child home once. They stay with relatives now.' using errcode = 'P0001', hint = 'used';
  end if;
  v_a := coalesce(c.parent_a = v_me.id, false);
  if (case when v_a then c.reclaim_a_at else c.reclaim_b_at end) is not null then
    raise exception 'You already paid your share. Now it is up to the other parent.' using errcode = 'P0001', hint = 'already_paid';
  end if;
  v_wait := extract(epoch from (c.relatives_at + make_interval(hours => bl_love_num('kids.reclaim_wait_hours', 12)::int) - v_now));
  if v_wait > 0 then
    raise exception 'Relatives are enjoying the visit. You can bring them home in %.', bl_love_wait_text(v_wait) using errcode = 'P0001', hint = 'cooldown';
  end if;
  v_nm := bl_kids_label(c);
  if v_cost > 0 then
    perform bl_sink_pay(v_me.id, v_cost, 'kid_reclaim', jsonb_build_object('label', 'Bringing ' || v_nm || ' home (your share)', 'child', c.id));
  end if;
  update kids_children set reclaim_a_at = case when v_a then v_now else reclaim_a_at end, reclaim_a_amt = case when v_a then v_cost else reclaim_a_amt end,
                           reclaim_b_at = case when not v_a then v_now else reclaim_b_at end, reclaim_b_amt = case when not v_a then v_cost else reclaim_b_amt end
   where id = c.id returning * into c;
  perform bl_kids_spent(c.id, v_me.id, v_cost);
  v_other := case when v_a then c.parent_b else c.parent_a end;
  v_done := (c.parent_a is null or c.reclaim_a_at is not null) and (c.parent_b is null or c.reclaim_b_at is not null);
  if v_done then
    c := bl_kids_bring_home(c, v_now, v_me.id);
    v_msg := v_nm || ' is back home 🏠 Look after them well.';
  else
    perform bl_kids_notify(v_other, 'kids_share', '@' || v_me.username || ' paid their share for ' || v_nm,
                           'Your share of ' || bl_naira(v_cost) || ' brings ' || v_nm || ' home. If it is not paid in ' || bl_love_num('kids.reclaim_window_days', 3)::int || ' days, the money goes back.', c.id);
    v_msg := 'Your share is paid. ' || v_nm || ' comes home when the other parent pays too.';
  end if;
  c := bl_kids_process(c.id, false);
  return jsonb_build_object('message', v_msg, 'spent', v_cost, 'child', c.id, 'home', v_done);
end $$;

-- "See the doctor" for a sick child with no open doctor card for me: Dr. Osagie sends a new one (at most one every hour).
create or replace function public.kids_call_doctor(p_child bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); c public.kids_children; ill public.kids_illnesses; v_id bigint;
begin
  if not bl_kids_on() or not bl_moments_on() then
    raise exception 'The doctor is resting for now.' using errcode = 'P0001', hint = 'off';
  end if;
  c := bl_kids_settle(p_child);
  if c.id is null or (c.parent_a is distinct from v_me.id and c.parent_b is distinct from v_me.id) then
    raise exception 'That child is not yours.' using errcode = 'P0001', hint = 'not_parent';
  end if;
  if c.status <> 'home' or c.sick_since is null then
    raise exception '% is not unwell right now.', bl_kids_label(c) using errcode = 'P0001', hint = 'not_sick';
  end if;
  select m.id into v_id from player_moments m where m.user_id = v_me.id and m.context ->> 'child_id' = c.id::text and m.context ->> 'ep' = c.illness_n::text
     and m.status in ('pending', 'snoozed', 'scheduled') and m.moment_id in (select id from life_moments where kind = 'kids_ill') order by m.id desc limit 1;
  if v_id is null then
    select * into ill from kids_illnesses where id = coalesce(c.illness_id, 'fever');
    if exists (select 1 from player_moments m where m.user_id = v_me.id and m.context ->> 'child_id' = c.id::text and m.created_at > bl_now() - interval '1 hour'
                  and m.moment_id = ill.moment_id and m.status = 'answered') then
      raise exception 'Dr. Osagie is with another patient. Try again in a little while.' using errcode = 'P0001', hint = 'cooldown';
    end if;
    v_id := bl_moment_create(v_me.id, ill.moment_id, jsonb_build_object('child_id', c.id, 'ep', c.illness_n, 'illness', ill.id), bl_now(), true);
  end if;
  return jsonb_build_object('moment', v_id);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 12. Admin
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_kids_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard();
begin
  return jsonb_build_object(
    'enabled', bl_kids_on(),
    'expecting', (select count(*) from kids_children where status = 'expecting'),
    'home', (select count(*) from kids_children where status = 'home'),
    'with_relatives', (select count(*) from kids_children where status = 'with_relatives'),
    'needs_attention', (select count(*) from kids_children where status = 'home' and last_alert_at > bl_now() - interval '24 hours'),
    'sick', (select count(*) from kids_children where status = 'home' and sick_since is not null),
    'grown', (select count(*) from kids_children where status = 'grown'),
    'gone', (select count(*) from kids_children where status = 'gone'),
    'passed', (select count(*) from kids_children where status = 'passed'),
    'passing_enabled', coalesce(bl_cfg_bool('kids.passing_enabled'), true),
    'due_now', (select count(*) from kids_children where next_alert_at <= bl_now()),
    'children', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'status', x.status, 'born_at', x.born_at, 'due_at', x.due_at,
                 'sick', x.sick_since is not null, 'illness', x.illness_id, 'removals', x.removals,
                 'a', (select username from profiles where id = x.parent_a), 'b', (select username from profiles where id = x.parent_b)) order by x.id desc)
                 from (select * from kids_children where status in ('expecting', 'home', 'with_relatives') order by id desc limit 50) x), '[]'::jsonb),
    'passed_list', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'born_at', x.born_at, 'passed_at', x.passed_at,
                 'days_lived', greatest(0, floor(extract(epoch from (x.passed_at - x.born_at)) / 86400))::int, 'warnings', x.alerts_unanswered + x.doctor_ignored,
                 'a', (select username from profiles where id = x.parent_a), 'b', (select username from profiles where id = x.parent_b)) order by x.passed_at desc)
                 from (select * from kids_children where status = 'passed' order by passed_at desc limit 20) x), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 13. Doctor cards (the life-moments engine runs them). Dr. Osagie is fictional.
-- ---------------------------------------------------------------------------------------------
create or replace function pg_temp.doc_card(p_id text, p_title text, p_body text, p_hosp bigint, p_hosp_pct int, p_chem bigint, p_chem_pct int, p_sort int) returns void
language plpgsql as $$
declare v_choices jsonb;
begin
  v_choices := jsonb_build_array(
    jsonb_build_object('id', 'hospital', 'label', 'Hospital', 'cost', p_hosp, 'chance', p_hosp_pct,
      'effects', jsonb_build_array(jsonb_build_object('t', 'kid_cure'), jsonb_build_object('t', 'kid_need', 'need', 'health', 'delta', 30)),
      'outcome', '{child} was seen at Central Hospital and is already feeling better. Dr. Osagie says: keep them warm and rested.',
      'fail_effects', jsonb_build_array(jsonb_build_object('t', 'kid_need', 'need', 'health', 'delta', 5), jsonb_build_object('t', 'follow_up', 'moment', p_id, 'delay_hours', 1)),
      'fail_outcome', 'The treatment has not worked yet. Dr. Osagie asks you to come back in an hour.'),
    jsonb_build_object('id', 'chemist', 'label', 'Chemist', 'cost', p_chem, 'chance', p_chem_pct,
      'effects', jsonb_build_array(jsonb_build_object('t', 'kid_cure'), jsonb_build_object('t', 'kid_need', 'need', 'health', 'delta', 15)),
      'outcome', 'The chemist drugs worked. {child} is feeling better. Next time the hospital may be safer.',
      'fail_effects', jsonb_build_array(jsonb_build_object('t', 'kid_need', 'need', 'health', 'delta', -15), jsonb_build_object('t', 'follow_up', 'moment', p_id, 'delay_hours', 1)),
      'fail_outcome', 'The chemist drugs did not help and {child} looks a little worse. Dr. Osagie says to come to the hospital.'),
    jsonb_build_object('id', 'ignore', 'label', 'Ignore', 'ignore', true,
      'effects', jsonb_build_array(jsonb_build_object('t', 'kid_ignore')),
      'outcome', 'You decide to wait. {child} is still unwell. Dr. Osagie will check on you again.'));
  insert into life_moments (id, title, body, icon, speaker, kind, conditions, choices, cooldown_days, weight, push, sort)
  values (p_id, p_title, p_body, '👩🏾‍⚕️', 'Dr. Osagie · Central Hospital', 'kids_ill', '{}'::jsonb, v_choices, 0, 0, true, p_sort)
  on conflict (id) do nothing;
end $$;

select pg_temp.doc_card('doc_malaria', '{child} is unwell',
  '{child} has malaria: fever, shivering and no appetite. Treatment today is best. The hospital has drugs and a drip. The chemist across the road is cheaper, but its drugs may not work.', 12500, 92, 4000, 55, 300);
select pg_temp.doc_card('doc_fever', '{child} has a fever',
  '{child} is hot and restless with a fever. Please see to it today. The hospital will find the cause. The chemist is cheaper, but it may not help much.', 8000, 90, 2500, 60, 310);
select pg_temp.doc_card('doc_teething', '{child} is teething',
  '{child} is fussy, drooling and not sleeping well: the teeth are coming. The hospital can ease the pain well. The chemist has gel for less money, but it does not always work.', 5000, 90, 1500, 70, 320);
select pg_temp.doc_card('doc_cough', '{child} has a bad cough',
  '{child} has been coughing since the night and can hardly sleep. The hospital can check the chest. The chemist has cough syrup that costs less, but it may not be enough.', 6000, 92, 2000, 65, 330);
select pg_temp.doc_card('doc_diarrhoea', '{child} has a running stomach',
  '{child} has a running stomach and is getting weak. The hospital can give fluids and drugs. The chemist is cheaper, but it may not be enough.', 9000, 92, 2500, 55, 340);
select pg_temp.doc_card('doc_rash', '{child} has a rash',
  '{child} has a red rash and a mild fever, like measles. The hospital can tell what it is and treat it. The chemist is cheaper, but it may not help.', 10000, 90, 3000, 55, 350);

insert into public.kids_illnesses (id, name, emoji, blurb, min_days, max_days, weight, health_hit, med_item, moment_id, sort) values
('malaria',    'Malaria',          '🦟', '{child} has a fever and shivers: it looks like malaria.',  0, 999, 3, 20, 'kid_malaria', 'doc_malaria', 10),
('fever',      'Fever',            '🌡️', '{child} has a fever and feels hot.',                         0, 999, 3, 12, null,          'doc_fever', 20),
('teething',   'Teething',         '🦷', '{child} is fussy because the teeth are coming.',            2, 5,   2, 8,  null,          'doc_teething', 30),
('cough',      'Cough and cold',   '🤧', '{child} has a cough and a blocked nose.',                    0, 999, 3, 8,  null,          'doc_cough', 40),
('diarrhoea',  'Running stomach',  '💧', '{child} has a running stomach and is weak.',                 0, 999, 2, 15, null,          'doc_diarrhoea', 50),
('rash',       'Measles-like rash','🔴', '{child} has a red rash and a mild fever.',                   5, 999, 1, 10, null,          'doc_rash', 60)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 14. Patches on live functions (guarded, written against the CURRENT definitions)
-- ---------------------------------------------------------------------------------------------
select pg_temp.kv_patch('public.get_public_profile(uuid)',
  $o$'proud_parent', bl_kids_proud(id)$o$,
  $o$'proud_parent', bl_kids_proud(id), 'proud_tier', bl_kids_proud_tier(id)$o$,
  $o$bl_kids_proud_tier(id)$o$);
select pg_temp.kv_patch('public.bl_ledger_label(text, jsonb)',
  $o$when 'life_moment' then return coalesce(nullif(p_meta->>'label', ''), 'Life moment');$o$,
  $o$when 'life_moment' then return coalesce(nullif(p_meta->>'label', ''), 'Life moment');
    when 'kid_gift' then return coalesce(nullif(p_meta->>'label', ''), 'Thank-you gift from your child');
    when 'kid_reclaim_refund' then return coalesce(nullif(p_meta->>'label', ''), 'Share returned');$o$,
  $o$when 'kid_gift' then$o$);
select pg_temp.kv_patch('public.bl_econ_category(text)',
  $o$'admin_gift', 'crew_payout') then 'Rewards and bonuses'$o$,
  $o$'admin_gift', 'crew_payout', 'kid_gift') then 'Rewards and bonuses'$o$,
  $o$'crew_payout', 'kid_gift')$o$);
select pg_temp.kv_patch('public.bl_econ_category(text)',
  $o$'love_flirt', 'love_date', 'kid_try', 'kid_care', 'kid_reclaim') or p_reason like$o$,
  $o$'love_flirt', 'love_date', 'kid_try', 'kid_care', 'kid_reclaim', 'kid_reclaim_refund') or p_reason like$o$,
  $o$'kid_reclaim', 'kid_reclaim_refund')$o$);
select pg_temp.kv_patch('public.bl_earn_reasons()',
  $o$'kid_try', 'kid_care', 'kid_reclaim', 'life_moment'])$o$,
  $o$'kid_try', 'kid_care', 'kid_reclaim', 'life_moment', 'kid_gift', 'kid_reclaim_refund'])$o$,
  $o$'kid_gift', 'kid_reclaim_refund'$o$);
-- Admin Content editors: stage needs, illnesses, kids items, shop prices
select pg_temp.kv_patch('public.bl_admin_table_spec(text)',
  $o$"rate_health":"num","rate_love":"num","sort":"int","active":"bool"}}'$o$,
  $o$"rate_health":"num","rate_love":"num","rate_clean":"num","needs":"arr","sort":"int","active":"bool"}}'$o$,
  $o$"rate_clean":"num"$o$);
select pg_temp.kv_patch('public.bl_admin_table_spec(text)',
  $o$when 'kids_auto_names' then$o$,
  E'when ''kids_illnesses'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","emoji":"text","blurb":"text","min_days":"num","max_days":"num","weight":"num","health_hit":"num","med_item":"text_null","moment_id":"text","sort":"int","active":"bool"}}\'\n    when ''kids_items'' then ''{"pk":["item_id"],"insert":true,"order":"sort, item_id",\n      "cols":{"role":"text","uses":"int","stages":"arr","boost_pct":"num","sort":"int","active":"bool"}}\'\n    when ''shop_price_rules'' then ''{"pk":["id"],"insert":true,"order":"location_id, id",\n      "cols":{"location_id":"text","item_id":"text_null","category":"text_null","mult":"num","daily_pct":"num","active":"bool"}}\'\n    when ''kids_auto_names'' then',
  $o$when 'kids_illnesses' then$o$);

-- ---------------------------------------------------------------------------------------------
-- 15. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'bl\_kids\_%' or proname = 'bl_shop_price') loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  grant execute on function public.bl_kids_alert_sweep() to service_role;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and (proname like 'kids\_%' or proname like 'admin\_kids\_%') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
end $$;
notify pgrst, 'reload schema';
