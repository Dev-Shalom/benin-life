-- Own your home (docs/PROPERTY.md): past homes, buying, building, renting out.
--   1. Past homes: moving out of a rented home keeps it for house.return_days. Upgrades, the garage and where the furniture stood
--      stay with the house (stash) and come back when you move back in. They are paid out at house.upgrade_resale_pct only when
--      the slot expires or the player gives it up. (Replaces "moving out sells the upgrades and the home is gone for good".)
--   2. Buying: every area has a price per home type (property_offers, Admin -> Content). Price + agent fee + legal fee (sinks).
--      Owned homes pay no rent but still pay the house bill (rent of the same home type) and ground rent on the value.
--      Sell back at property.resale_pct of the value, minus an agent fee, never above what the home cost (no profit loop).
--   3. Building: plots from Invest -> Land (locked while building and under the house), a design (property_designs), a cost that
--      depends on the area, real-time stages (lazy settle, no cron). A finished build becomes an owned home, or several units.
--   4. Renting out: a home the owner is not living in is listed at a rent inside a band around the market rent, with an optional
--      caution. A tenant moves in like in any home; rent goes tenant -> landlord every rent day (minus the agent cut sink),
--      accrued in property_income and collected lazily so no two players' profile rows are ever locked in the wrong order.
-- Every new table is keyed by user id WITHOUT a foreign key to profiles (20261103000200_property_links.sql adds them in a
-- retry loop). Idempotent: tables `if not exists`, seeds `on conflict do nothing` (admin edits survive), functions
-- `create or replace`, live functions patched ONLY through a guarded replace (pg_temp.pr_patch). Private bl_* helpers are
-- revoked from anon / authenticated.

create or replace function pg_temp.pr_patch(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n <> 1 then raise exception 'property: % : marker found % times: %', p_sig, v_n, left(p_marker, 90); end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Own your home; the return window is under Rent)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('house.return_days', '30', 'rent', 'Past homes: days you can move back',
 'Own your home: a home you moved out of stays in Past homes for this many real days. Moving back costs the normal move-in fee and brings back the furniture spots and the finished upgrades. When the days run out (or the player gives it up) the upgrades are paid out at "Upgrades: % given back".', 'number', 1, 365),
('property.enabled', 'true', 'property', 'Own your home on',
 'Master switch for buying, building and renting out homes. Off = the Buy, Build and landlord tabs show but every action is refused. Past homes and tenancies already running keep working.', 'bool', null, null),
('property.buy_enabled', 'true', 'property', 'Buying homes on', 'Players can buy ready-made homes from the Houses app.', 'bool', null, null),
('property.build_enabled', 'true', 'property', 'Building homes on', 'Players can build a home on land they own (Invest -> Land).', 'bool', null, null),
('property.rent_out_enabled', 'true', 'property', 'Renting out on', 'Owners can list homes for rent and players can rent them. Off = no new listings or tenants; running tenancies continue.', 'bool', null, null),
('property.max_owned', '20', 'property', 'Most homes one player can own', 'Owned homes and units of a block of flats together.', 'number', 1, 200),
('property.max_builds', '3', 'property', 'Builds at the same time', 'How many houses one player can have under construction at once.', 'number', 1, 20),
('property.agent_fee_pct', '3', 'property', 'Buying: agent fee %', 'Added to the price when a player buys a home. A sink (ledger agent_fee), never earned.', 'percent', 0, 30),
('property.legal_fee_pct', '1.5', 'property', 'Buying: legal and documentation fee %', 'Deed of assignment, survey and registration. Added to the price. A sink (ledger legal_fee).', 'percent', 0, 30),
('property.legal_fee_min', '20000', 'property', 'Buying: smallest legal fee', 'The legal fee is never lower than this many naira.', 'naira', 0, 100000000),
('property.resale_pct', '85', 'property', 'Selling: % of the value you get', 'Selling a home back to the market pays this % of its value (the price paid grown a little over time), minus the agent fee. Never more than the home cost the player.', 'percent', 10, 95),
('property.sell_agent_pct', '2', 'property', 'Selling: agent fee %', 'Taken from the sale money (ledger agent_fee).', 'percent', 0, 30),
('property.value_gain_pct_week', '0.1', 'property', 'Value growth per week (%)', 'A home you keep is worth a little more each real week, up to the cap below.', 'number', 0, 5),
('property.value_gain_cap_pct', '10', 'property', 'Value growth cap (%)', 'Most a home can grow above what it cost.', 'percent', 0, 30),
('property.build_permit_pct', '2', 'property', 'Building: plan approval fee %', 'Taken on top of the build cost when a build starts (ledger legal_fee, a sink, not refunded).', 'percent', 0, 30),
('property.build_time_pct', '100', 'property', 'Building: time %', 'Scales every build time. 100 = as listed in Content -> Designs, 50 = twice as fast, 0 = finished at once (handy for testing).', 'percent', 0, 1000),
('property.build_cancel_refund_pct', '60', 'property', 'Building: % back when you cancel', 'Cancelling a build in progress gives back this % of the build cost (not the plan fee). The plots are free again.', 'percent', 0, 100),
('property.rent_min_pct', '50', 'property', 'Landlord: lowest rent (% of market rent)', 'A landlord can list at the market rent for the home (value x the area yield) times this %.', 'percent', 1, 100),
('property.rent_max_pct', '150', 'property', 'Landlord: highest rent (% of market rent)', 'The upper end of the band.', 'percent', 100, 500),
('property.caution_max_weeks', '8', 'property', 'Landlord: biggest caution (weeks of rent)', 'The optional refundable caution fee a landlord may ask.', 'number', 0, 52),
('property.rent_cut_pct', '5', 'property', 'Landlord: agent cut and rental tax %', 'Taken from every rent a landlord receives (ledger agent_fee). A sink. Rent received also counts as earnings for the weekly income tax.', 'percent', 0, 50),
('property.tenant_agent_weeks', '1', 'property', 'Tenant: agent and legal fee (weeks of rent)', 'Paid once when a player moves into a home let by another player. A sink (ledger agent_fee).', 'number', 0, 12),
('property.tenant_advance_weeks', '1', 'property', 'Tenant: rent paid in advance (weeks)', 'Paid to the landlord at move-in, on top of the caution.', 'number', 0, 12),
('property.notice_days', '3', 'property', 'Landlord notice (real days)', 'A landlord cannot evict at once. After notice the tenant is moved out. A tenant can always leave at any time.', 'number', 0, 60),
('property.evict_owed_weeks', '3', 'property', 'Eviction: weeks of rent owed', 'A tenant who owes this many weeks of rent is moved out (the caution is taken first). The existing owed-rent rule decides what is owed.', 'number', 1, 52)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Catalogue tables (admin editable, Content)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.property_areas (
  id           text primary key check (id ~ '^[a-z0-9_]{2,24}$'),
  name         text not null,
  district     text not null default '',             -- locations.district the private home takes (map neighbourhood)
  land_market  text,                                  -- invest_markets id of the plots (land_*), null = no building here
  x            numeric not null default 500,          -- where the home sits on the map
  y            numeric not null default 500,
  build_factor numeric not null default 1 check (build_factor > 0),   -- build cost x this
  rent_yield_pct numeric not null default 0.3 check (rent_yield_pct > 0), -- market rent a week, % of value
  blurb        text not null default '',
  sort         int not null default 100,
  active       boolean not null default true
);

create table if not exists public.property_types (
  id            text primary key check (id ~ '^[a-z0-9_]{2,24}$'),
  name          text not null,
  emoji         text not null default '🏠',
  template_home text not null references public.start_homes(id) on update cascade, -- the existing home it looks like (3D layout, scene)
  bedrooms      int not null default 1 check (bedrooms >= 0),
  blurb         text not null default '',
  sort          int not null default 100,
  active        boolean not null default true
);

create table if not exists public.property_offers (
  id      text primary key check (id ~ '^[a-z0-9_]{2,48}$'),
  area    text not null references public.property_areas(id) on update cascade,
  type_id text not null references public.property_types(id) on update cascade,
  price   bigint not null check (price > 0),
  sort    int not null default 100,
  active  boolean not null default true,
  unique (area, type_id)
);

create table if not exists public.property_designs (
  id          text primary key check (id ~ '^[a-z0-9_]{2,32}$'),
  name        text not null,
  emoji       text not null default '🏗️',
  description text not null default '',
  type_id     text not null references public.property_types(id) on update cascade, -- what each finished unit is
  units       int not null default 1 check (units between 1 and 24),
  plots       int not null default 1 check (plots between 1 and 100),
  base_cost   bigint not null check (base_cost > 0),   -- x the area's build factor
  build_hours numeric not null default 12 check (build_hours >= 0), -- real hours, scaled by property.build_time_pct
  stages      jsonb not null default '[{"name":"Foundation","pct":25},{"name":"Blockwork","pct":35},{"name":"Roofing","pct":20},{"name":"Finishing","pct":20}]'::jsonb,
  sort        int not null default 100,
  active      boolean not null default true
);

-- ---------------------------------------------------------------------------------------------
-- 3. Player tables (no foreign keys to profiles here)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.properties (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null,
  area        text not null references public.property_areas(id) on update cascade,
  type_id     text not null references public.property_types(id) on update cascade,
  source      text not null default 'bought' check (source in ('bought', 'built')),
  name        text not null default '',
  basis       bigint not null check (basis >= 0),          -- what the home cost (price, or build + land share)
  acquired_at timestamptz not null default now(),
  build_id    uuid,
  unit_no     int,
  listed      boolean not null default false,
  listed_rent bigint,
  caution     bigint not null default 0 check (caution >= 0),
  listed_at   timestamptz,
  stash       jsonb                                           -- upgrades, garage and furniture spots while nobody uses it as their own home
);
create index if not exists properties_owner_idx on public.properties (owner_id);
create index if not exists properties_listed_idx on public.properties (area) where listed;

create table if not exists public.property_builds (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null,
  area        text not null references public.property_areas(id) on update cascade,
  design_id   text not null references public.property_designs(id) on update cascade,
  plots       int not null check (plots > 0),
  cost        bigint not null check (cost >= 0),
  land_cost   bigint not null default 0,
  status      text not null default 'building' check (status in ('building', 'done', 'cancelled', 'sold')),
  started_at  timestamptz not null default now(),
  ready_at    timestamptz not null,
  finished_at timestamptz,
  name        text not null default ''
);
create index if not exists property_builds_owner_idx on public.property_builds (owner_id, status);
create index if not exists property_builds_due_idx on public.property_builds (ready_at) where status = 'building';

create table if not exists public.player_residence (
  user_id     uuid primary key,
  role        text not null check (role in ('owner', 'tenant')),
  property_id uuid not null references public.properties(id) on delete cascade,
  since       timestamptz not null default now(),
  rent        bigint not null default 0,
  caution     bigint not null default 0,
  landlord_id uuid,
  notice_at   timestamptz,
  ends_at     timestamptz,
  ended_by    text check (ended_by in ('landlord', 'admin'))
);
create unique index if not exists player_residence_property_uq on public.player_residence (property_id);

create table if not exists public.property_income (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null,
  property_id uuid,
  tenant_id   uuid,
  tenant_name text not null default '',
  property_name text not null default '',
  gross       bigint not null check (gross > 0),
  created_at  timestamptz not null default now(),
  collected_at timestamptz
);
create index if not exists property_income_pending_idx on public.property_income (owner_id) where collected_at is null;

create table if not exists public.property_events (
  id          bigint generated always as identity primary key,
  property_id uuid,
  user_id     uuid,
  kind        text not null,
  detail      jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists property_events_prop_idx on public.property_events (property_id, id desc);

create table if not exists public.player_past_homes (
  user_id    uuid not null,
  start_home text not null references public.start_homes(id) on update cascade on delete cascade,
  housing_id text,
  left_at    timestamptz not null default now(),
  expires_at timestamptz not null,
  stash      jsonb not null default '{}'::jsonb,
  primary key (user_id, start_home)
);
create index if not exists player_past_homes_expiry_idx on public.player_past_homes (expires_at);

-- bills: ground rent on a bought home
alter table public.player_bills drop constraint if exists player_bills_kind_check;
alter table public.player_bills add constraint player_bills_kind_check check (kind in ('house', 'car', 'business', 'land', 'property'));

-- RLS: catalogues readable, player rows readable by their owner (or the tenant / landlord of a home), no client writes at all
alter table public.property_areas enable row level security;
alter table public.property_types enable row level security;
alter table public.property_offers enable row level security;
alter table public.property_designs enable row level security;
alter table public.properties enable row level security;
alter table public.property_builds enable row level security;
alter table public.player_residence enable row level security;
alter table public.property_income enable row level security;
alter table public.property_events enable row level security;
alter table public.player_past_homes enable row level security;
revoke all on public.property_areas, public.property_types, public.property_offers, public.property_designs, public.properties,
  public.property_builds, public.player_residence, public.property_income, public.property_events, public.player_past_homes
  from anon, authenticated;
grant select on public.property_areas, public.property_types, public.property_offers, public.property_designs,
  public.properties, public.property_builds, public.player_residence, public.property_income, public.player_past_homes to authenticated;
drop policy if exists property_areas_read on public.property_areas;
create policy property_areas_read on public.property_areas for select to authenticated using (true);
drop policy if exists property_types_read on public.property_types;
create policy property_types_read on public.property_types for select to authenticated using (true);
drop policy if exists property_offers_read on public.property_offers;
create policy property_offers_read on public.property_offers for select to authenticated using (true);
drop policy if exists property_designs_read on public.property_designs;
create policy property_designs_read on public.property_designs for select to authenticated using (true);
drop policy if exists properties_own on public.properties;
create policy properties_own on public.properties for select to authenticated using (owner_id = (select auth.uid()));
drop policy if exists property_builds_own on public.property_builds;
create policy property_builds_own on public.property_builds for select to authenticated using (owner_id = (select auth.uid()));
drop policy if exists player_residence_own on public.player_residence;
create policy player_residence_own on public.player_residence for select to authenticated
  using (user_id = (select auth.uid()) or landlord_id = (select auth.uid()));
drop policy if exists property_income_own on public.property_income;
create policy property_income_own on public.property_income for select to authenticated using (owner_id = (select auth.uid()));
drop policy if exists player_past_homes_own on public.player_past_homes;
create policy player_past_homes_own on public.player_past_homes for select to authenticated using (user_id = (select auth.uid()));
-- property_events: no client policy at all (admin RPCs read it)

-- ---------------------------------------------------------------------------------------------
-- 4. Seeds: areas, home types, prices (real Benin City 2026, in line with the Invest land prices), designs
-- ---------------------------------------------------------------------------------------------
insert into public.property_areas (id, name, district, land_market, x, y, build_factor, rent_yield_pct, blurb, sort) values
('gra',     'GRA',         'gra',         'land_gra',     422, 762, 1.40, 0.22, 'Government Reserved Area: quiet estates, tarred streets, the dearest land in Benin.', 10),
('ugbowo',  'Ugbowo',      'ugbowo',      'land_ugbowo',  592,  72, 1.15, 0.28, 'Round UNIBEN and UBTH: students, lecturers, doctors. Always somebody looking for a flat.', 20),
('sapele',  'Sapele Road', 'sapele_rd',   'land_sapele',  688, 712, 1.05, 0.30, 'The busy spine road of Benin: malls, dealers and plenty of tenants.', 30),
('airport', 'Airport Road','airport_rd',  'land_airport', 362, 662, 1.00, 0.30, 'Estates and new layouts round the airport. Our base price for building.', 40),
('ikpoba',  'Ikpoba Hill', 'ikpoba_hill', 'land_ikpoba',  772, 432, 0.95, 0.33, 'Hill side of town: cheaper plots, fast-growing streets.', 50),
('okhoro',  'Okhoro',      'sapele_rd',   'land_okhoro',  642, 252, 0.92, 0.34, 'Okhoro quarters: affordable, close to the market, small compounds.', 60),
('ekenwan', 'Ekenwan',     'ekenwan',     'land_ekenwan', 276, 602, 0.90, 0.35, 'Ekenwan Road: the cheapest land and the best rent for your money.', 70)
on conflict (id) do nothing;

insert into public.property_types (id, name, emoji, template_home, bedrooms, blurb, sort) values
('room_fmiyf',  'Room in a face-me-I-face-you', '🚪', 'ekenwan_face_me',      1, 'One room in a row house with a shared passage. The first step on the ladder.', 10),
('self_contain','Self-contain',                  '🛏️', 'uselu_self_contain',   1, 'One room with its own toilet and kitchenette behind your own door.', 20),
('flat_2bed',   '2-bedroom flat',                '🏢', 'mission_rd_mini_flat', 2, 'Parlour, two bedrooms, kitchen and bathroom on one floor.', 30),
('flat_3bed',   '3-bedroom flat',                '🏢', 'mission_rd_mini_flat', 3, 'A big flat with a long parlour and three bedrooms.', 40),
('bungalow_2',  '2-bedroom bungalow',            '🏡', 'mission_rd_mini_flat', 2, 'A single-storey house on its own plot.', 50),
('bungalow_3',  '3-bedroom bungalow',            '🏡', 'mission_rd_mini_flat', 3, 'The Benin dream: a three-bedroom bungalow with a compound.', 60),
('duplex_4',    '4-bedroom duplex',              '🏘️', 'gra_duplex',           4, 'Two floors, four bedrooms, a guest toilet and a staircase.', 70),
('duplex_5',    '5-bedroom duplex',              '🏰', 'gra_duplex',           5, 'The big house: five bedrooms, boys quarters and a wide compound.', 80)
on conflict (id) do nothing;

-- price by area and type (naira). Room / self-contain / flat prices follow what a Benin City buyer pays in 2026; the
-- bungalows and duplexes sit about 30% above what it costs to build them on your own plots (land + build, see designs below).
insert into public.property_offers (id, area, type_id, price, sort)
select o.area || '_' || o.type_id, o.area, o.type_id, o.price, o.sort
  from (values
    ('ekenwan','room_fmiyf',    3000000, 10), ('okhoro','room_fmiyf',    3600000, 10), ('ikpoba','room_fmiyf',   4200000, 10),
    ('airport','room_fmiyf',    4800000, 10), ('sapele','room_fmiyf',    5400000, 10), ('ugbowo','room_fmiyf',   6000000, 10),
    ('ekenwan','self_contain',  7000000, 20), ('okhoro','self_contain',  8500000, 20), ('ikpoba','self_contain', 9500000, 20),
    ('airport','self_contain', 11000000, 20), ('sapele','self_contain', 13000000, 20), ('ugbowo','self_contain',15000000, 20),
    ('gra','self_contain',     30000000, 20),
    ('okhoro','flat_2bed',     20000000, 30), ('ikpoba','flat_2bed',    22000000, 30), ('airport','flat_2bed',  26000000, 30),
    ('sapele','flat_2bed',     30000000, 30), ('ugbowo','flat_2bed',    36000000, 30), ('gra','flat_2bed',      80000000, 30),
    ('okhoro','flat_3bed',     30000000, 40), ('ikpoba','flat_3bed',    34000000, 40), ('airport','flat_3bed',  40000000, 40),
    ('sapele','flat_3bed',     46000000, 40), ('ugbowo','flat_3bed',    54000000, 40), ('gra','flat_3bed',     115000000, 40),
    ('ekenwan','bungalow_2',   34000000, 50), ('okhoro','bungalow_2',   36000000, 50), ('ikpoba','bungalow_2',  38000000, 50),
    ('airport','bungalow_2',   41000000, 50), ('sapele','bungalow_2',   44000000, 50), ('ugbowo','bungalow_2',  50000000, 50),
    ('gra','bungalow_2',       66000000, 50),
    ('ekenwan','bungalow_3',   52000000, 60), ('okhoro','bungalow_3',   55000000, 60), ('ikpoba','bungalow_3',  58000000, 60),
    ('airport','bungalow_3',   62000000, 60), ('sapele','bungalow_3',   66000000, 60), ('ugbowo','bungalow_3',  75000000, 60),
    ('gra','bungalow_3',      100000000, 60),
    ('okhoro','duplex_4',     122000000, 70), ('ikpoba','duplex_4',    128000000, 70), ('airport','duplex_4', 138000000, 70),
    ('sapele','duplex_4',     148000000, 70), ('ugbowo','duplex_4',    165000000, 70), ('gra','duplex_4',     215000000, 70),
    ('ikpoba','duplex_5',     215000000, 80), ('airport','duplex_5',   225000000, 80), ('sapele','duplex_5',  240000000, 80),
    ('ugbowo','duplex_5',     270000000, 80), ('gra','duplex_5',       340000000, 80)
  ) as o(area, type_id, price, sort)
on conflict (id) do nothing;

insert into public.property_designs (id, name, emoji, description, type_id, units, plots, base_cost, build_hours, sort) values
('bungalow_2',  '2-bedroom bungalow',     '🏡', 'Two bedrooms, parlour, kitchen and bathroom on one plot.',                  'bungalow_2', 1, 1,  28000000, 12, 10),
('bungalow_3',  '3-bedroom bungalow',     '🏡', 'Three bedrooms and a compound on one plot. The classic.',                  'bungalow_3', 1, 1,  42000000, 18, 20),
('duplex_4',    '4-bedroom duplex',       '🏘️', 'Two floors and four bedrooms. Needs two plots for the compound.',            'duplex_4',   1, 2,  95000000, 36, 30),
('duplex_5',    '5-bedroom duplex',       '🏰', 'The mansion: five bedrooms, boys quarters, two plots.',                      'duplex_5',   1, 2, 160000000, 48, 40),
('rooms_block_6','Block of 6 self-contains','🏬','Six self-contain units under one roof. Live in one, let the rest.',        'self_contain', 6, 2,  45000000, 36, 50),
('flats_block_4','Block of 4 flats',      '🏢', 'Four 2-bedroom flats, one per floor and side. Three plots.',                 'flat_2bed',  4, 3,  85000000, 72, 60)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 5. Small helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_prop_num(p_key text, p_def numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_def)
$$;
create or replace function public.bl_prop_on(p_key text) returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = p_key), true)
$$;

-- what a home is worth now: the price paid, grown a little each real week up to a cap (never a money printer)
create or replace function public.bl_prop_value(p public.properties) returns bigint
language sql stable set search_path = public as $$
  select floor(p.basis * (1 + least(bl_prop_num('property.value_gain_cap_pct', 10),
           bl_prop_num('property.value_gain_pct_week', 0.1) * greatest(0, extract(epoch from (bl_now() - p.acquired_at)) / 604800.0)) / 100.0))::bigint
$$;

-- market rent a week: value x the area's yield, rounded to N100
create or replace function public.bl_prop_market_rent(p public.properties) returns bigint
language sql stable set search_path = public as $$
  select greatest(100, round(bl_prop_value(p) * a.rent_yield_pct / 100.0 / 100.0) * 100)::bigint from property_areas a where a.id = p.area
$$;
create or replace function public.bl_prop_rent_min(p public.properties) returns bigint
language sql stable set search_path = public as $$
  select greatest(100, round(bl_prop_market_rent(p) * bl_prop_num('property.rent_min_pct', 50) / 100.0 / 100.0) * 100)::bigint
$$;
create or replace function public.bl_prop_rent_max(p public.properties) returns bigint
language sql stable set search_path = public as $$
  select greatest(100, round(bl_prop_market_rent(p) * bl_prop_num('property.rent_max_pct', 150) / 100.0 / 100.0) * 100)::bigint
$$;

-- the existing home a property looks like (3D layout, scene, rent used for the house bill)
create or replace function public.bl_prop_home(p public.properties) returns public.start_homes
language sql stable set search_path = public as $$
  select h.* from property_types t join start_homes h on h.id = t.template_home where t.id = p.type_id
$$;

-- the rent the weekly house bill is scaled by: an owner pays the bill of the same home type, a tenant of what they pay
create or replace function public.bl_home_bill_rent(p public.profiles) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce((select h.weekly_rent from player_residence r join properties pr on pr.id = r.property_id
                     join property_types t on t.id = pr.type_id join start_homes h on h.id = t.template_home
                    where r.user_id = p.id and r.role = 'owner'), p.weekly_rent)
$$;

create or replace function public.bl_prop_log(p_prop uuid, p_user uuid, p_kind text, p_detail jsonb default '{}'::jsonb) returns void
language sql security definer set search_path = public as $$
  insert into property_events (property_id, user_id, kind, detail, created_at) values (p_prop, p_user, p_kind, coalesce(p_detail, '{}'::jsonb), bl_now())
$$;

create or replace function public.bl_prop_name(p public.properties) returns text
language sql stable set search_path = public as $$
  select coalesce(nullif(p.name, ''), t.name || ' · ' || a.name || case when p.unit_no is not null then ' (unit ' || p.unit_no || ')' else '' end)
    from property_types t, property_areas a where t.id = p.type_id and a.id = p.area
$$;

create or replace function public.bl_username(p_uid uuid) returns text
language sql stable set search_path = public as $$ select username from profiles where id = p_uid $$;

-- is this player the owner of a home they live in / the tenant of a player landlord
create or replace function public.bl_home_role(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$ select role from player_residence where user_id = p_uid $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Stash: what stays with a house when you leave it (upgrades, the garage, where the furniture stood)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_home_stash_capture(p_uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_up jsonb; v_pl jsonb; v_g jsonb;
begin
  perform bl_house_upgrades_settle(p_uid);
  select coalesce(jsonb_agg(jsonb_build_object('upgrade_id', upgrade_id, 'price_paid', price_paid, 'fee_paid', fee_paid,
           'bought_at', bought_at, 'ready_at', ready_at, 'done_at', done_at, 'notified', notified, 'source', source)
           order by bought_at, upgrade_id), '[]'::jsonb) into v_up
    from player_house_upgrades where user_id = p_uid;
  select coalesce(jsonb_agg(jsonb_build_object('key', furniture_key, 'x', x, 'z', z, 'rot', rotation)
           order by updated_at, furniture_key), '[]'::jsonb) into v_pl
    from player_house_furniture where owner_id = p_uid and not stored;
  select jsonb_build_object('garage_type', g.garage_type, 'price_paid', g.price_paid, 'built_at', g.built_at, 'extra_capacity', g.extra_capacity)
    into v_g from player_garages g where g.user_id = p_uid;
  return jsonb_build_object('upgrades', v_up, 'placements', v_pl, 'garage', v_g, 'at', bl_now());
end $$;

-- put the stash back for the home the player now lives in (profile already points at it). p_free = a tenant: it is the
-- landlord's, so it carries no value for the tenant.
create or replace function public.bl_home_stash_restore(p_uid uuid, p_stash jsonb, p_start_home text, p_free boolean) returns int
language plpgsql security definer set search_path = public as $$
declare v_me profiles; n int := 0; g jsonb := p_stash -> 'garage';
begin
  if p_stash is null or p_stash = '{}'::jsonb then return 0; end if;
  select * into v_me from profiles where id = p_uid;
  insert into player_house_upgrades (user_id, upgrade_id, start_home, price_paid, fee_paid, bought_at, ready_at, done_at, notified, source)
  select p_uid, x.upgrade_id, p_start_home, case when p_free then 0 else coalesce(x.price_paid, 0) end,
         case when p_free then 0 else coalesce(x.fee_paid, 0) end,
         coalesce(x.bought_at, bl_now()), coalesce(x.ready_at, bl_now()), x.done_at, case when p_free then true else coalesce(x.notified, true) end,
         case when x.source = 'admin' then 'admin' else 'buy' end
    from jsonb_to_recordset(p_stash -> 'upgrades') as x(upgrade_id text, price_paid bigint, fee_paid bigint, bought_at timestamptz,
                                                         ready_at timestamptz, done_at timestamptz, notified boolean, source text)
   where exists (select 1 from house_upgrades u where u.id = x.upgrade_id)
  on conflict (user_id, upgrade_id) do nothing;
  get diagnostics n = row_count;
  if g is not null and jsonb_typeof(g) = 'object' and exists (select 1 from garage_types t where t.id = g->>'garage_type') then
    insert into player_garages (user_id, garage_type, housing_id, home_location_id, price_paid, built_at, extra_capacity)
    values (p_uid, g->>'garage_type', v_me.housing_id, v_me.home_location_id,
            case when p_free then 0 else coalesce((g->>'price_paid')::bigint, 0) end,
            coalesce((g->>'built_at')::timestamptz, bl_now()), coalesce((g->>'extra_capacity')::int, 0))
    on conflict (user_id) do nothing;
  end if;
  return n;
end $$;

-- what a stash of upgrades pays out when the home is given up (finished: house.upgrade_resale_pct, unfinished: in full)
create or replace function public.bl_stash_value(p_stash jsonb) returns bigint
language sql stable set search_path = public as $$
  select coalesce(sum(case when x.done_at is null then coalesce(x.price_paid, 0)
                           else floor(coalesce(x.price_paid, 0) * greatest(0, least(100, bl_prop_num('house.upgrade_resale_pct', 50))) / 100.0) end), 0)::bigint
    from jsonb_to_recordset(coalesce(p_stash -> 'upgrades', '[]'::jsonb)) as x(price_paid bigint, done_at timestamptz)
$$;

-- close one past home: pay its upgrades out into the bank, drop the slot. Returns the refund.
create or replace function public.bl_past_home_close(p_uid uuid, p_home text, p_why text) returns bigint
language plpgsql security definer set search_path = public as $$
declare r public.player_past_homes; v bigint; v_name text;
begin
  select * into r from player_past_homes where user_id = p_uid and start_home = p_home for update;
  if not found then return 0; end if;
  v := bl_stash_value(r.stash);
  delete from player_past_homes where user_id = p_uid and start_home = p_home;
  select name || case when district <> '' then ' · ' || district else '' end into v_name from start_homes where id = p_home;
  if v > 0 then
    perform bl_add_money(p_uid, 'bank', v, 'house_upgrade', jsonb_build_object('refund', true, 'home', p_home, 'why', p_why));
  end if;
  perform bl_event(p_uid, 'past_home_closed', case when p_why = 'expired' then 'Past home expired' else 'Past home given up' end,
    coalesce(v_name, 'Your old home') || case when p_why = 'expired' then ' is gone: the landlord gave it to someone else.' else ' is off your list.' end
    || case when v > 0 then ' Your upgrades there were sold for ' || bl_naira(v) || '.' else '' end,
    jsonb_build_object('home', p_home, 'refund', v));
  return v;
end $$;

create or replace function public.bl_past_homes_expire(p_uid uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare r record; v bigint := 0;
begin
  for r in select start_home from player_past_homes where user_id = p_uid and expires_at <= bl_now() order by expires_at loop
    v := v + bl_past_home_close(p_uid, r.start_home, 'expired');
  end loop;
  return v;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Leaving and entering a home (the one place where homes change hands)
-- ---------------------------------------------------------------------------------------------
-- Everything that stays with the home you leave goes into its stash. A rented city home becomes a past home, an owned
-- home keeps its stash on the property, a tenant just walks out (caution back, landlord told).
create or replace function public.bl_home_leave(p_uid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles; res public.player_residence; p public.properties; v_stash jsonb;
begin
  select * into v_me from profiles where id = p_uid;
  select * into res from player_residence where user_id = p_uid for update;
  v_stash := bl_home_stash_capture(p_uid);
  if res.user_id is null then
    if v_me.start_home is not null then
      insert into player_past_homes (user_id, start_home, housing_id, left_at, expires_at, stash)
      values (p_uid, v_me.start_home, v_me.housing_id, bl_now(), bl_now() + interval '1 day' * bl_prop_num('house.return_days', 30), v_stash)
      on conflict (user_id, start_home) do update
        set housing_id = excluded.housing_id, left_at = excluded.left_at, expires_at = excluded.expires_at, stash = excluded.stash;
    end if;
  elsif res.role = 'owner' then
    update properties set stash = v_stash where id = res.property_id;
    delete from player_residence where user_id = p_uid;
  else
    select * into p from properties where id = res.property_id;
    if res.caution > 0 then
      perform bl_add_money(p_uid, 'bank', res.caution, 'rent_caution', jsonb_build_object('label', 'Caution back: ' || bl_prop_name(p), 'refund', true));
    end if;
    delete from player_residence where user_id = p_uid;
    perform bl_prop_log(res.property_id, p_uid, 'tenant_left', jsonb_build_object('tenant', v_me.username, 'caution_back', res.caution));
    if res.landlord_id is not null then
      perform bl_event(res.landlord_id, 'tenant_left', 'Tenant moved out',
        '@' || coalesce(v_me.username, 'your tenant') || ' moved out of ' || bl_prop_name(p) || '. It is empty again.',
        jsonb_build_object('property', res.property_id));
    end if;
  end if;
  delete from player_house_upgrades where user_id = p_uid;
  delete from player_garages where user_id = p_uid;
end $$;

-- Move the player into p_home. Money and the checks are the caller's job. p_role: null = a home rented from the city,
-- 'owner' / 'tenant' = a property (p_prop). Furniture: the pieces that stood in the old home go to their remembered spot
-- (a past home or an owned home), else the default slot, else the nearest free spot, else My items.
create or replace function public.bl_home_enter(p_uid uuid, p_home public.start_homes, p_prop uuid, p_role text,
                                                p_rent bigint, p_caution bigint, p_landlord uuid, p_move_in bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles; v_loc locations; v_old_layout text; v_new_layout text; v_old_w numeric; v_old_d numeric;
  hl home_layouts; v_stash jsonb := '{}'::jsonb; v_garage text; v_placed int := 0; v_left int := 0; v_items int := 0;
  v_slots text[] := '{}'; r record; v_ok boolean; v_prop public.properties; v_area public.property_areas;
  v_ups int := 0; v_restored boolean := false; v_pl jsonb;
begin
  select * into v_me from profiles where id = p_uid for update;
  v_old_layout := bl_furniture_materialize(p_uid);
  select w, d into v_old_w, v_old_d from home_layouts where id = v_old_layout;
  create temp table if not exists bl_pr_move (key text, slot text, sort int, copy int, rx numeric, rz numeric) on commit drop;
  truncate bl_pr_move;
  insert into bl_pr_move
  select hf.furniture_key, coalesce(pf.slot, f.slot), f.sort, bl_furniture_copy_of(hf.furniture_key),
         hf.x / nullif(v_old_w, 0), hf.z / nullif(v_old_d, 0)
    from player_house_furniture hf
    join player_furniture pf on pf.user_id = hf.owner_id and pf.furniture_id = bl_furniture_id_of(hf.furniture_key)
    join furniture f on f.id = pf.furniture_id
   where hf.owner_id = p_uid and not hf.stored;
  select t.name into v_garage from player_garages g join garage_types t on t.id = g.garage_type where g.user_id = p_uid;

  perform bl_home_leave(p_uid);

  if p_role is null then
    select stash into v_stash from player_past_homes where user_id = p_uid and start_home = p_home.id and expires_at > bl_now();
    delete from player_past_homes where user_id = p_uid and start_home = p_home.id;
  else
    select * into v_prop from properties where id = p_prop;
    v_stash := coalesce(v_prop.stash, '{}'::jsonb);
    if p_role = 'owner' then update properties set stash = null where id = p_prop; end if;
    select * into v_area from property_areas where id = v_prop.area;
  end if;
  v_stash := coalesce(v_stash, '{}'::jsonb);

  -- the private home takes the new place's map spot and scene; the movers carry you home
  v_loc := bl_location(p_home.location_id);
  update locations set district = coalesce(nullif(v_area.district, ''), v_loc.district), scene = v_loc.scene, blurb = v_loc.blurb,
         risk = v_loc.risk, night_risk_mult = v_loc.night_risk_mult, cctv = v_loc.cctv, keke_ok = v_loc.keke_ok,
         congestion = v_loc.congestion, remote_km = v_loc.remote_km, x = coalesce(v_area.x, v_loc.x), y = coalesce(v_area.y, v_loc.y),
         actions = v_loc.actions, open_hour = v_loc.open_hour, close_hour = v_loc.close_hour
   where id = v_me.home_location_id and private_home_owner_id = p_uid;
  update profiles set start_home = p_home.id, housing_id = p_home.housing_id, weekly_rent = p_rent, location_id = home_location_id,
         rent_due_at = coalesce(rent_due_at, bl_rent_due_after(bl_now(), bl_cfg('rent.first_due_grace_game_days')))
   where id = p_uid;
  if p_role is not null then
    insert into player_residence (user_id, role, property_id, since, rent, caution, landlord_id)
    values (p_uid, p_role, p_prop, bl_now(), case when p_role = 'tenant' then p_rent else 0 end, p_caution,
            case when p_role = 'tenant' then p_landlord end);
  end if;

  -- upgrades and the garage that belong to this house come back; builders that finished while you were away settle now
  v_ups := bl_home_stash_restore(p_uid, v_stash, p_home.id, p_role = 'tenant');
  perform bl_house_upgrades_settle(p_uid);
  v_restored := v_ups > 0 or jsonb_array_length(coalesce(v_stash -> 'placements', '[]'::jsonb)) > 0;

  -- every owned copy goes in as stored for the new layout, then the furniture is placed again
  v_new_layout := bl_home_layout_id(p_home.housing_id);
  select * into hl from home_layouts where id = v_new_layout;
  delete from player_house_furniture where owner_id = p_uid;
  insert into player_house_furniture (owner_id, furniture_key, x, z, rotation, stored, layout, updated_at)
  select p_uid, case when n = 1 then 'own_' || pf.furniture_id else 'own_' || pf.furniture_id || '-' || n end,
         0, 0, 0, true, v_new_layout, bl_now()
    from player_furniture pf join furniture f on f.id = pf.furniture_id
   cross join lateral generate_series(1, pf.qty) n
   where pf.user_id = p_uid and f.active
  on conflict (owner_id, furniture_key) do nothing;
  perform bl_house_items_grant(p_uid, p_move_in);
  if hl.id is not null then
    -- 1. the spots remembered by this house (a past or owned home): exactly there when it is still valid
    for r in select x.key, x.x, x.z, x.rot from jsonb_to_recordset(coalesce(v_stash -> 'placements', '[]'::jsonb)) as x(key text, x numeric, z numeric, rot int)
              where exists (select 1 from player_house_furniture hf where hf.owner_id = p_uid and hf.furniture_key = x.key and hf.stored) loop
      if bl_furniture_check(p_uid, v_new_layout, r.key, r.x, r.z, r.rot) is null then
        update player_house_furniture set x = round(r.x, 3), z = round(r.z, 3), rotation = ((coalesce(r.rot, 0) % 4) + 4) % 4,
               stored = false, layout = v_new_layout, updated_at = bl_now()
         where owner_id = p_uid and furniture_key = r.key;
        v_placed := v_placed + 1;
      end if;
    end loop;
    -- 2. what stood in the old home and is not placed yet: default slot, else the nearest free spot
    for r in select m.* from bl_pr_move m
              where exists (select 1 from player_house_furniture hf where hf.owner_id = p_uid and hf.furniture_key = m.key and hf.stored)
              order by (copy = 1 and hl.slots ? slot) desc, sort, key loop
      v_ok := false;
      if r.copy = 1 and hl.slots ? r.slot and not (r.slot = any (v_slots)) then
        v_ok := bl_furniture_autoplace(p_uid, v_new_layout, r.key, (hl.slots->r.slot->>0)::numeric,
                  (hl.slots->r.slot->>1)::numeric, (hl.slots->r.slot->>2)::int, true);
        if v_ok then v_slots := v_slots || r.slot; end if;
      end if;
      if not v_ok then
        v_ok := bl_furniture_autoplace(p_uid, v_new_layout, r.key, r.rx * hl.w, r.rz * hl.d, 0, false);
      end if;
      if v_ok then v_placed := v_placed + 1; else v_left := v_left + 1; end if;
    end loop;
    -- 3. pieces waiting in My items take a free default slot of a bigger home (not when the house remembered its own spots)
    if not v_restored then
      for r in select hf.furniture_key as key, coalesce(pf.slot, f.slot) as slot
                 from player_house_furniture hf
                 join player_furniture pf on pf.user_id = hf.owner_id and pf.furniture_id = bl_furniture_id_of(hf.furniture_key)
                 join furniture f on f.id = pf.furniture_id
                where hf.owner_id = p_uid and hf.stored and bl_furniture_copy_of(hf.furniture_key) = 1
                  and hl.slots ? coalesce(pf.slot, f.slot)
                order by f.sort, hf.furniture_key loop
        continue when r.slot = any (v_slots)
          or bl_furniture_check(p_uid, v_new_layout, r.key, (hl.slots->r.slot->>0)::numeric,
                                (hl.slots->r.slot->>1)::numeric, (hl.slots->r.slot->>2)::int) is not null;
        update player_house_furniture
           set x = (hl.slots->r.slot->>0)::numeric, z = (hl.slots->r.slot->>1)::numeric,
               rotation = ((((hl.slots->r.slot->>2)::int) % 4) + 4) % 4, stored = false, updated_at = bl_now()
         where owner_id = p_uid and furniture_key = r.key;
        v_slots := v_slots || r.slot;
        v_placed := v_placed + 1;
      end loop;
    end if;
  end if;
  select count(*) into v_items from player_house_furniture where owner_id = p_uid and stored;
  return jsonb_build_object('layout', v_new_layout, 'placed', v_placed, 'not_fit', v_left, 'in_items', v_items,
    'garage_left', v_garage, 'upgrades_back', v_ups, 'restored', v_restored,
    'came_with', coalesce((select jsonb_array_length(g.items) from player_house_grants g where g.user_id = p_uid and g.home_key = p_home.id), 0));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. house_move: rent a city home, or move back into a past home. house_options: the lists.
-- ---------------------------------------------------------------------------------------------
create or replace function public.house_move(p_home text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me     profiles := bl_me();
  h        start_homes;
  v_weeks  numeric;
  v_cost   bigint;
  v_bank   bigint := 0;
  v_cash   bigint := 0;
  v_meta   jsonb;
  v_res    jsonb;
  v_back   boolean;
  v_items  int;
  v_old    text := v_me.start_home;
begin
  perform bl_assert_free(v_me);
  if v_me.home_visit_host_id is not null then
    raise exception 'You are visiting someone. Go back home first, then move.' using errcode = 'P0001', hint = 'visiting';
  end if;
  if exists (select 1 from profiles g where g.home_visit_host_id = v_me.id and g.location_id = v_me.home_location_id) then
    raise exception 'Your guests are still in the house. See them off first, then move.' using errcode = 'P0001', hint = 'hosting';
  end if;
  if not bl_cfg_bool('house.move_enabled') then
    raise exception 'Moving house is paused right now. Try again later.' using errcode = 'P0001', hint = 'moving_disabled';
  end if;
  select * into h from start_homes where id = lower(trim(coalesce(p_home, ''))) and active;
  if not found then
    raise exception 'That home is not on the list.' using errcode = 'P0001', hint = 'bad_home';
  end if;
  if h.id = v_me.start_home and not exists (select 1 from player_residence where user_id = v_me.id) then
    raise exception 'You already live here.' using errcode = 'P0001', hint = 'same_home';
  end if;
  if v_me.rent_owed > 0 then
    raise exception 'Settle the % rent you owe first. Your landlord won''t release you.', bl_naira(v_me.rent_owed)
      using errcode = 'P0001', hint = 'rent_owed';
  end if;
  if exists (select 1 from player_house_upgrades p join house_upgrades u on u.id = p.upgrade_id
              where p.user_id = v_me.id and p.done_at is null and u.effect ? 'to_home') then
    raise exception 'The builders are changing your whole home right now. Wait until they finish, then move.' using errcode = 'P0001', hint = 'tier_building';
  end if;
  perform bl_past_homes_expire(v_me.id);
  v_back := exists (select 1 from player_past_homes where user_id = v_me.id and start_home = h.id);
  v_weeks := greatest(0, bl_prop_num('house.move_in_weeks', 4));
  v_cost := (h.weekly_rent * v_weeks)::bigint;
  if greatest(v_me.bank, 0) + greatest(v_me.cash, 0) < v_cost then
    raise exception 'Not enough money. Moving into % costs % and you have %.', h.name, bl_naira(v_cost),
      bl_naira(greatest(v_me.bank, 0) + greatest(v_me.cash, 0)) using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_meta := jsonb_build_object('home', h.id, 'name', h.name, 'from', v_old, 'weeks', v_weeks, 'back', v_back);
  v_bank := least(v_cost, greatest(v_me.bank, 0));
  v_cash := v_cost - v_bank;
  if v_bank > 0 then perform bl_add_money(v_me.id, 'bank', -v_bank, 'house_move', v_meta); end if;
  if v_cash > 0 then perform bl_add_money(v_me.id, 'cash', -v_cash, 'house_move', v_meta); end if;

  v_res := bl_home_enter(v_me.id, h, null, null, h.weekly_rent, 0, null, v_cost);
  v_items := (v_res->>'in_items')::int;

  return bl_receipt_issue(v_me.id, 'house', 'Move-in: ' || h.name || ' (' || rtrim(to_char(v_weeks, 'FM990.##'), '.') || ' weeks rent)',
             v_cost, 'Landlord' || case when h.district <> '' then ', ' || h.district else '' end,
             jsonb_build_object('home', h.id, 'weekly_rent', h.weekly_rent, 'weeks', v_weeks, 'from_bank', v_bank, 'from_cash', v_cash))
    || jsonb_build_object(
    'message', case when v_back then 'Welcome back to your ' else 'Welcome to your new ' end || lower(h.name)
               || case when h.district <> '' then ' in ' || h.district else '' end || '!'
               || case when (v_res->>'upgrades_back')::int > 0 then ' Your upgrades are still here.' else '' end
               || case when v_items > 0 then ' ' || v_items || case when v_items = 1 then ' item is' else ' items are' end
                       || ' in My items. Place them in Arrange.' else '' end,
    'home', h.id, 'name', h.name, 'layout', v_res->>'layout', 'from', v_old, 'returned', v_back,
    'came_with', (v_res->>'came_with')::int, 'placed', (v_res->>'placed')::int, 'not_fit', (v_res->>'not_fit')::int, 'in_items', v_items,
    'garage_left', v_res->>'garage_left', 'upgrades_back', (v_res->>'upgrades_back')::int,
    'upgrade_refund', 0, 'spent', v_cost, 'from_bank', v_bank, 'from_cash', v_cash, 'weekly_rent', h.weekly_rent);
end $$;

-- Give up a past home: its upgrades are paid out now (house.upgrade_resale_pct) and the slot is gone.
create or replace function public.house_past_release(p_home text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); v bigint;
begin
  if not exists (select 1 from player_past_homes where user_id = v_me.id and start_home = lower(trim(coalesce(p_home, '')))) then
    raise exception 'That home is not in your past homes.' using errcode = 'P0001', hint = 'not_found';
  end if;
  v := bl_past_home_close(v_me.id, lower(trim(p_home)), 'released');
  return jsonb_build_object('message', 'Past home given up.' || case when v > 0 then ' Your upgrades there paid ' || bl_naira(v) || ' into your bank.' else '' end,
                            'refund', v);
end $$;

-- The Houses app: every city home (current / past / available), the past homes with their clock, the move-in fee.
create or replace function public.house_options() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me    profiles := bl_me_any();
  v_weeks numeric := bl_prop_num('house.move_in_weeks', 4);
  v_kind  text;
  v_garage jsonb;
  v_res   boolean;
begin
  perform bl_past_homes_expire(v_me.id);
  v_res := exists (select 1 from player_residence where user_id = v_me.id);
  v_kind := bl_housing_kind(coalesce(v_me.home_visit_original_housing_id, v_me.housing_id));
  select jsonb_build_object('type', g.garage_type, 'name', t.name) into v_garage
    from player_garages g join garage_types t on t.id = g.garage_type
   where g.user_id = v_me.id
     and g.housing_id is not distinct from coalesce(v_me.home_visit_original_housing_id, v_me.housing_id);
  return jsonb_build_object(
    'enabled', bl_cfg_bool('house.move_enabled'),
    'move_in_weeks', v_weeks,
    'return_days', bl_prop_num('house.return_days', 30),
    'current', case when v_res then null else v_me.start_home end,
    'garage', v_garage,
    'homes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', h.id, 'name', h.name, 'emoji', h.emoji, 'district', h.district, 'tag', h.tag,
               'description', h.description, 'weekly_rent', h.weekly_rent,
               'move_in', (h.weekly_rent * v_weeks)::bigint,
               'kind', bl_housing_kind(h.housing_id), 'layout', bl_home_layout_id(h.housing_id),
               'w', hl.w, 'd', hl.d, 'area', round(hl.w * hl.d),
               'status', case when h.id = v_me.start_home and not v_res then 'current'
                              when ph.start_home is not null then 'past' else 'available' end,
               'past_until', ph.expires_at,
               'past_upgrades', case when ph.start_home is null then 0 else jsonb_array_length(coalesce(ph.stash -> 'upgrades', '[]'::jsonb)) end,
               'past_value', case when ph.start_home is null then 0 else bl_stash_value(ph.stash) end)
             order by h.weekly_rent, h.sort)
        from start_homes h
        left join home_layouts hl on hl.id = bl_home_layout_id(h.housing_id)
        left join player_past_homes ph on ph.user_id = v_me.id and ph.start_home = h.id and ph.expires_at > bl_now()
       where h.active), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. Plots that carry a build or a house
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_land_locked(p_uid uuid, p_market text) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(sum(b.plots), 0)::int
    from property_builds b join property_areas a on a.id = b.area
   where b.owner_id = p_uid and a.land_market = p_market and b.status in ('building', 'done')
$$;

-- ---------------------------------------------------------------------------------------------
-- 10. Buying and selling
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_prop_fees(p_price bigint) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('price', p_price,
    'agent', round(p_price * bl_prop_num('property.agent_fee_pct', 3) / 100.0)::bigint,
    'legal', greatest(bl_prop_num('property.legal_fee_min', 20000)::bigint, round(p_price * bl_prop_num('property.legal_fee_pct', 1.5) / 100.0)::bigint))
$$;

create or replace function public.bl_prop_owned_count(p_uid uuid) returns int
language sql stable security definer set search_path = public as $$
  select (select count(*) from properties where owner_id = p_uid)::int
       + coalesce((select sum(d.units) from property_builds b join property_designs d on d.id = b.design_id
                    where b.owner_id = p_uid and b.status = 'building'), 0)::int
$$;

-- one card of an offer with every fee, so the screen shows the whole bill before paying
create or replace function public.bl_prop_offer_card(o public.property_offers) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', o.id, 'area', o.area, 'type_id', o.type_id, 'price', o.price,
           'agent', (bl_prop_fees(o.price)->>'agent')::bigint, 'legal', (bl_prop_fees(o.price)->>'legal')::bigint,
           'total', o.price + (bl_prop_fees(o.price)->>'agent')::bigint + (bl_prop_fees(o.price)->>'legal')::bigint,
           'rent_market', greatest(100, round(o.price * a.rent_yield_pct / 100.0 / 100.0) * 100)::bigint)
    from property_areas a where a.id = o.area
$$;

create or replace function public.property_quote_buy(p_offer text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); o property_offers; v_card jsonb; v_reason text; v_have bigint := greatest(v_me.bank, 0) + greatest(v_me.cash, 0);
begin
  select * into o from property_offers where id = p_offer and active;
  if not found then
    raise exception 'That home is not for sale right now.' using errcode = 'P0001', hint = 'bad_offer';
  end if;
  v_card := bl_prop_offer_card(o);
  v_reason := case
    when not bl_prop_on('property.enabled') or not bl_prop_on('property.buy_enabled') then 'Buying homes is paused right now.'
    when bl_prop_owned_count(v_me.id) >= bl_prop_num('property.max_owned', 20) then 'You own the most homes allowed.'
    when v_have < (v_card->>'total')::bigint then 'You need ' || bl_naira((v_card->>'total')::bigint) || ' and have ' || bl_naira(v_have) || '.'
    else null end;
  return v_card || jsonb_build_object('can_buy', v_reason is null, 'reason', v_reason, 'have', v_have);
end $$;

create or replace function public.property_buy(p_offer text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); o property_offers; t property_types; a property_areas; v_card jsonb; v_total bigint; v_have bigint;
  v_price bigint; v_agent bigint; v_legal bigint; v_id uuid; v_label text; v_name text;
begin
  perform bl_assert_free(v_me);
  if not bl_prop_on('property.enabled') or not bl_prop_on('property.buy_enabled') then
    raise exception 'Buying homes is paused right now.' using errcode = 'P0001', hint = 'property_disabled';
  end if;
  select * into o from property_offers where id = p_offer and active;
  if not found then
    raise exception 'That home is not for sale right now.' using errcode = 'P0001', hint = 'bad_offer';
  end if;
  select * into t from property_types where id = o.type_id and active;
  select * into a from property_areas where id = o.area and active;
  if t.id is null or a.id is null then
    raise exception 'That home is not for sale right now.' using errcode = 'P0001', hint = 'bad_offer';
  end if;
  if bl_prop_owned_count(v_me.id) >= bl_prop_num('property.max_owned', 20) then
    raise exception 'You own the most homes allowed (%).', bl_prop_num('property.max_owned', 20)::int using errcode = 'P0001', hint = 'too_many';
  end if;
  v_card := bl_prop_offer_card(o);
  v_price := o.price; v_agent := (v_card->>'agent')::bigint; v_legal := (v_card->>'legal')::bigint; v_total := v_price + v_agent + v_legal;
  v_have := greatest(v_me.bank, 0) + greatest(v_me.cash, 0);
  if v_have < v_total then
    raise exception 'Not enough money. % in % costs % (price % + agent % + legal %) and you have %.', t.name, a.name,
      bl_naira(v_total), bl_naira(v_price), bl_naira(v_agent), bl_naira(v_legal), bl_naira(v_have)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_name := t.name || ' · ' || a.name;
  perform bl_sink_pay(v_me.id, v_price, 'house_buy', jsonb_build_object('label', 'Bought: ' || v_name, 'offer', o.id));
  if v_agent > 0 then perform bl_sink_pay(v_me.id, v_agent, 'agent_fee', jsonb_build_object('label', 'Agent fee: ' || v_name, 'offer', o.id)); end if;
  if v_legal > 0 then perform bl_sink_pay(v_me.id, v_legal, 'legal_fee', jsonb_build_object('label', 'Legal and documentation: ' || v_name, 'offer', o.id)); end if;
  insert into properties (owner_id, area, type_id, source, basis, acquired_at) values (v_me.id, a.id, t.id, 'bought', v_price, bl_now())
  returning id into v_id;
  perform bl_prop_log(v_id, v_me.id, 'bought', jsonb_build_object('price', v_price, 'total', v_total));
  return bl_receipt_issue(v_me.id, 'house', 'Home: ' || v_name, v_total, 'Benin Homes & Estates, ' || a.name,
           jsonb_build_object('property', v_id, 'price', v_price, 'agent', v_agent, 'legal', v_legal))
    || jsonb_build_object('message', 'You now own a ' || lower(t.name) || ' in ' || a.name || '. Total paid ' || bl_naira(v_total) || '.',
         'property', v_id, 'price', v_price, 'agent', v_agent, 'legal', v_legal, 'total', v_total);
end $$;

-- What a sale pays today: the lower of (value x resale %) and what the home cost, minus the agent, plus the upgrades.
create or replace function public.bl_prop_sale(p public.properties) returns jsonb
language sql stable security definer set search_path = public as $$
  with g as (select least(p.basis, floor(bl_prop_value(p) * bl_prop_num('property.resale_pct', 85) / 100.0))::bigint as gross)
  select jsonb_build_object('gross', g.gross,
           'agent', round(g.gross * bl_prop_num('property.sell_agent_pct', 2) / 100.0)::bigint,
           'upgrades', bl_stash_value(p.stash),
           'net', g.gross - round(g.gross * bl_prop_num('property.sell_agent_pct', 2) / 100.0)::bigint + bl_stash_value(p.stash))
    from g
$$;

-- take the plots a finished build stood on out of the land position (the house sale paid for them)
create or replace function public.bl_prop_release_build(p_build uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b property_builds; v_market text; pos invest_positions;
begin
  select * into b from property_builds where id = p_build for update;
  if not found or b.status <> 'done' then return; end if;
  update property_builds set status = 'sold' where id = b.id;
  select land_market into v_market from property_areas where id = b.area;
  select * into pos from invest_positions where user_id = b.owner_id and ref_id = v_market and kind = 'land' for update;
  if not found then return; end if;
  if pos.qty <= b.plots then
    delete from invest_positions where id = pos.id;
  else
    update invest_positions set qty = qty - b.plots, cost = greatest(0, cost - b.land_cost) where id = pos.id;
  end if;
end $$;

create or replace function public.property_sell(p_property uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); p properties; s jsonb; v_name text; res player_residence;
begin
  perform bl_assert_free(v_me);
  select * into p from properties where id = p_property and owner_id = v_me.id for update;
  if not found then
    raise exception 'That home is not yours.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  select * into res from player_residence where property_id = p.id;
  if res.user_id = v_me.id then
    raise exception 'You live here. Move out first, then sell.' using errcode = 'P0001', hint = 'live_here';
  elsif res.user_id is not null then
    raise exception 'A tenant lives here. Give notice and wait for them to leave, then sell.' using errcode = 'P0001', hint = 'tenant_inside';
  end if;
  s := bl_prop_sale(p);
  v_name := bl_prop_name(p);
  if (s->>'gross')::bigint > 0 then
    perform bl_add_money(v_me.id, 'bank', (s->>'gross')::bigint, 'house_sell', jsonb_build_object('label', 'Sold: ' || v_name, 'property', p.id));
  end if;
  if (s->>'agent')::bigint > 0 then
    perform bl_add_money(v_me.id, 'bank', -(s->>'agent')::bigint, 'agent_fee', jsonb_build_object('label', 'Agent fee (sale): ' || v_name, 'property', p.id));
  end if;
  if (s->>'upgrades')::bigint > 0 then
    perform bl_add_money(v_me.id, 'bank', (s->>'upgrades')::bigint, 'house_upgrade', jsonb_build_object('refund', true, 'property', p.id));
  end if;
  perform bl_prop_log(p.id, v_me.id, 'sold', s);
  delete from properties where id = p.id;
  if p.build_id is not null and not exists (select 1 from properties where build_id = p.build_id) then
    perform bl_prop_release_build(p.build_id);
  end if;
  return jsonb_build_object('message', v_name || ' sold. ' || bl_naira((s->>'net')::bigint) || ' in your bank.',
                            'gross', (s->>'gross')::bigint, 'agent', (s->>'agent')::bigint, 'upgrades', (s->>'upgrades')::bigint, 'net', (s->>'net')::bigint);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 11. Building
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_prop_build_cost(d public.property_designs, a public.property_areas) returns bigint
language sql stable set search_path = public as $$
  select (round(d.base_cost * a.build_factor / 10000.0) * 10000)::bigint
$$;
create or replace function public.bl_prop_build_hours(d public.property_designs) returns numeric
language sql stable set search_path = public as $$
  select d.build_hours * greatest(0, bl_prop_num('property.build_time_pct', 100)) / 100.0
$$;

-- the stages of a build with their start / end times
create or replace function public.bl_prop_stages(b public.property_builds) returns jsonb
language sql stable set search_path = public as $$
  with d as (select * from property_designs where id = b.design_id),
  s as (select x.v->>'name' as name, greatest(0, coalesce((x.v->>'pct')::numeric, 0)) as pct, x.ord,
               sum(greatest(0, coalesce((x.v->>'pct')::numeric, 0))) over (order by x.ord) as cum,
               sum(greatest(0, coalesce((x.v->>'pct')::numeric, 0))) over () as tot
          from d, jsonb_array_elements(d.stages) with ordinality as x(v, ord))
  select coalesce(jsonb_agg(jsonb_build_object('name', s.name, 'pct', s.pct,
           'starts_at', b.started_at + (b.ready_at - b.started_at) * ((s.cum - s.pct) / nullif(s.tot, 0)),
           'ends_at', b.started_at + (b.ready_at - b.started_at) * (s.cum / nullif(s.tot, 0))) order by s.ord), '[]'::jsonb) from s
$$;

create or replace function public.bl_prop_build_card(b public.property_builds) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_total numeric := greatest(1, extract(epoch from (b.ready_at - b.started_at)));
  v_done numeric := greatest(0, least(v_total, extract(epoch from (bl_now() - b.started_at))));
  v_stages jsonb := bl_prop_stages(b); v_cur text;
  d property_designs; a property_areas;
begin
  select * into d from property_designs where id = b.design_id;
  select * into a from property_areas where id = b.area;
  select x->>'name' into v_cur from jsonb_array_elements(v_stages) x where (x->>'ends_at')::timestamptz > bl_now() order by (x->>'ends_at')::timestamptz limit 1;
  return jsonb_build_object('id', b.id, 'area', b.area, 'area_name', a.name, 'design_id', b.design_id, 'name', d.name, 'emoji', d.emoji,
           'units', d.units, 'plots', b.plots, 'cost', b.cost, 'status', b.status, 'started_at', b.started_at, 'ready_at', b.ready_at,
           'progress', round(v_done / v_total * 100)::int, 'seconds_left', greatest(0, ceil(extract(epoch from (b.ready_at - bl_now()))))::int,
           'stage', coalesce(v_cur, 'Finishing'), 'stages', v_stages,
           'refund', floor(b.cost * bl_prop_num('property.build_cancel_refund_pct', 60) / 100.0)::bigint);
end $$;

-- plots in an area: held, locked (build or house), free, and what one costs today
create or replace function public.bl_prop_land(p_uid uuid, p_area public.property_areas) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare pos invest_positions; v_locked int; v_price numeric := null;
begin
  if p_area.land_market is null then return jsonb_build_object('plots', 0, 'locked', 0, 'free', 0, 'plot_price', null, 'avg_cost', 0); end if;
  select * into pos from invest_positions where user_id = p_uid and ref_id = p_area.land_market and kind = 'land';
  v_locked := bl_land_locked(p_uid, p_area.land_market);
  begin v_price := bl_inv_price(p_area.land_market); exception when others then v_price := null; end;
  return jsonb_build_object('plots', coalesce(pos.qty, 0)::int, 'locked', v_locked, 'free', greatest(0, coalesce(pos.qty, 0)::int - v_locked),
                            'plot_price', v_price, 'avg_cost', case when coalesce(pos.qty, 0) > 0 then floor(pos.cost / pos.qty) else 0 end);
end $$;

create or replace function public.property_quote_build(p_design text, p_area text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); d property_designs; a property_areas; v_cost bigint; v_permit bigint; v_have bigint; v_land jsonb; v_reason text;
  v_hours numeric; v_n int;
begin
  perform bl_property_tick(v_me.id);
  select * into d from property_designs where id = p_design and active;
  select * into a from property_areas where id = p_area and active and land_market is not null;
  if d.id is null or a.id is null then
    raise exception 'That design or area is not available.' using errcode = 'P0001', hint = 'bad_design';
  end if;
  v_cost := bl_prop_build_cost(d, a);
  v_permit := round(v_cost * bl_prop_num('property.build_permit_pct', 2) / 100.0)::bigint;
  v_hours := bl_prop_build_hours(d);
  v_land := bl_prop_land(v_me.id, a);
  v_have := greatest(v_me.bank, 0) + greatest(v_me.cash, 0);
  select count(*) into v_n from property_builds where owner_id = v_me.id and status = 'building';
  v_reason := case
    when not bl_prop_on('property.enabled') or not bl_prop_on('property.build_enabled') then 'Building is paused right now.'
    when (v_land->>'free')::int < d.plots then 'You need ' || d.plots || ' free plot' || case when d.plots = 1 then '' else 's' end || ' in ' || a.name
      || ' (you have ' || (v_land->>'free') || '). Buy plots in Bank, Invest, Land.'
    when v_n >= bl_prop_num('property.max_builds', 3) then 'You already have the most builds going.'
    when bl_prop_owned_count(v_me.id) + d.units > bl_prop_num('property.max_owned', 20) then 'You would own more homes than allowed.'
    when v_have < v_cost + v_permit then 'You need ' || bl_naira(v_cost + v_permit) || ' and have ' || bl_naira(v_have) || '.'
    else null end;
  return jsonb_build_object('design', d.id, 'area', a.id, 'cost', v_cost, 'permit', v_permit, 'total', v_cost + v_permit,
           'hours', v_hours, 'units', d.units, 'plots', d.plots, 'land', v_land, 'have', v_have,
           'can_build', v_reason is null, 'reason', v_reason, 'stages', d.stages);
end $$;

create or replace function public.property_build_start(p_design text, p_area text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); d property_designs; a property_areas; v_cost bigint; v_permit bigint; v_land jsonb; pos invest_positions;
  v_land_cost bigint; v_id uuid; v_ready timestamptz; v_label text; v_have bigint; v_n int;
begin
  perform bl_assert_free(v_me);
  if not bl_prop_on('property.enabled') or not bl_prop_on('property.build_enabled') then
    raise exception 'Building is paused right now.' using errcode = 'P0001', hint = 'property_disabled';
  end if;
  select * into d from property_designs where id = p_design and active;
  select * into a from property_areas where id = p_area and active and land_market is not null;
  if d.id is null or a.id is null then
    raise exception 'That design or area is not available.' using errcode = 'P0001', hint = 'bad_design';
  end if;
  select count(*) into v_n from property_builds where owner_id = v_me.id and status = 'building';
  if v_n >= bl_prop_num('property.max_builds', 3) then
    raise exception 'You already have % builds going. Wait for one to finish.', v_n using errcode = 'P0001', hint = 'too_many_builds';
  end if;
  if bl_prop_owned_count(v_me.id) + d.units > bl_prop_num('property.max_owned', 20) then
    raise exception 'You would own more than % homes. Sell one first.', bl_prop_num('property.max_owned', 20)::int using errcode = 'P0001', hint = 'too_many';
  end if;
  select * into pos from invest_positions where user_id = v_me.id and ref_id = a.land_market and kind = 'land' for update;
  v_land := bl_prop_land(v_me.id, a);
  if (v_land->>'free')::int < d.plots then
    raise exception 'You need % free plot(s) in % for a % and you have %. Buy plots in Bank, Invest, Land.', d.plots, a.name, lower(d.name), (v_land->>'free')
      using errcode = 'P0001', hint = 'no_plots';
  end if;
  v_cost := bl_prop_build_cost(d, a);
  v_permit := round(v_cost * bl_prop_num('property.build_permit_pct', 2) / 100.0)::bigint;
  v_have := greatest(v_me.bank, 0) + greatest(v_me.cash, 0);
  if v_have < v_cost + v_permit then
    raise exception 'Not enough money. Building a % in % costs % (works % + plan approval %) and you have %.', lower(d.name), a.name,
      bl_naira(v_cost + v_permit), bl_naira(v_cost), bl_naira(v_permit), bl_naira(v_have) using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_label := d.name || ' · ' || a.name;
  perform bl_sink_pay(v_me.id, v_cost, 'build_cost', jsonb_build_object('label', 'Build: ' || v_label, 'design', d.id, 'area', a.id));
  if v_permit > 0 then perform bl_sink_pay(v_me.id, v_permit, 'legal_fee', jsonb_build_object('label', 'Plan approval: ' || v_label, 'design', d.id)); end if;
  -- the plots' cost share (their average price in your land position) goes into what the home cost you
  v_land_cost := floor(pos.cost * d.plots / greatest(pos.qty, 1))::bigint;
  v_ready := bl_now() + make_interval(secs => (bl_prop_build_hours(d) * 3600)::double precision);
  insert into property_builds (owner_id, area, design_id, plots, cost, land_cost, status, started_at, ready_at, name)
  values (v_me.id, a.id, d.id, d.plots, v_cost, v_land_cost, 'building', bl_now(), v_ready, d.name)
  returning id into v_id;
  perform bl_prop_log(null, v_me.id, 'build_started', jsonb_build_object('build', v_id, 'design', d.id, 'area', a.id, 'cost', v_cost));
  perform bl_property_builds_settle(v_me.id);
  return bl_receipt_issue(v_me.id, 'house', 'Build: ' || v_label, v_cost + v_permit, 'Benin Builders & Sons',
           jsonb_build_object('build', v_id, 'cost', v_cost, 'permit', v_permit))
    || jsonb_build_object('message', 'Builders don arrive: your ' || lower(d.name) || ' in ' || a.name || ' will be ready in about '
         || case when bl_prop_build_hours(d) >= 1 then round(bl_prop_build_hours(d)::numeric, 1) || ' hours' else 'a few minutes' end || '.',
         'build', v_id, 'cost', v_cost, 'permit', v_permit, 'total', v_cost + v_permit, 'ready_at', v_ready);
end $$;

create or replace function public.property_build_cancel(p_build uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); b property_builds; v_refund bigint; v_name text;
begin
  perform bl_assert_free(v_me);
  perform bl_property_builds_settle(v_me.id);
  select * into b from property_builds where id = p_build and owner_id = v_me.id for update;
  if not found then
    raise exception 'That build is not yours.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  if b.status <> 'building' then
    raise exception 'The builders already finished. Sell the house if you no longer want it.' using errcode = 'P0001', hint = 'not_building';
  end if;
  v_refund := floor(b.cost * bl_prop_num('property.build_cancel_refund_pct', 60) / 100.0)::bigint;
  v_name := b.name;
  update property_builds set status = 'cancelled', finished_at = bl_now() where id = b.id;
  if v_refund > 0 then
    perform bl_add_money(v_me.id, 'bank', v_refund, 'build_refund', jsonb_build_object('label', 'Build cancelled: ' || v_name, 'build', b.id));
  end if;
  perform bl_prop_log(null, v_me.id, 'build_cancelled', jsonb_build_object('build', b.id, 'refund', v_refund));
  return jsonb_build_object('message', 'Build cancelled. ' || bl_naira(v_refund) || ' back in your bank. Your plots are free again.', 'refund', v_refund);
end $$;

-- lazy: every build whose time is up becomes finished homes (units). Returns how many builds finished.
create or replace function public.bl_property_builds_settle(p_uid uuid) returns int
language plpgsql security definer set search_path = public as $$
declare b property_builds; d property_designs; n int := 0; i int; v_basis bigint;
begin
  for b in select * from property_builds where owner_id = p_uid and status = 'building' and ready_at <= bl_now() order by ready_at for update loop
    select * into d from property_designs where id = b.design_id;
    update property_builds set status = 'done', finished_at = b.ready_at where id = b.id;
    v_basis := floor((b.cost + b.land_cost) / greatest(d.units, 1))::bigint;
    for i in 1..greatest(d.units, 1) loop
      insert into properties (owner_id, area, type_id, source, basis, acquired_at, build_id, unit_no)
      values (p_uid, b.area, d.type_id, 'built', v_basis, b.ready_at, b.id, case when d.units > 1 then i end);
    end loop;
    perform bl_prop_log(null, p_uid, 'build_done', jsonb_build_object('build', b.id, 'units', d.units));
    perform bl_event(p_uid, 'build_done', 'Builders don finish!',
      'Your ' || lower(d.name) || ' in ' || (select name from property_areas where id = b.area) || ' is ready'
      || case when d.units > 1 then ' (' || d.units || ' units)' else '' end || '. Open Houses, Mine.',
      jsonb_build_object('build', b.id, 'design', d.id));
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 12. Landlord and tenant
-- ---------------------------------------------------------------------------------------------
-- the checks every move shares (rent, live in, rent a home): free, not visiting, no guests, owed rent settled, not mid tier works
create or replace function public.bl_prop_move_guard(v_me public.profiles) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform bl_assert_free(v_me);
  if v_me.home_visit_host_id is not null then
    raise exception 'You are visiting someone. Go back home first, then move.' using errcode = 'P0001', hint = 'visiting';
  end if;
  if exists (select 1 from profiles g where g.home_visit_host_id = v_me.id and g.location_id = v_me.home_location_id) then
    raise exception 'Your guests are still in the house. See them off first, then move.' using errcode = 'P0001', hint = 'hosting';
  end if;
  if not bl_cfg_bool('house.move_enabled') then
    raise exception 'Moving house is paused right now. Try again later.' using errcode = 'P0001', hint = 'moving_disabled';
  end if;
  if v_me.rent_owed > 0 then
    raise exception 'Settle the % rent you owe first. Your landlord won''t release you.', bl_naira(v_me.rent_owed)
      using errcode = 'P0001', hint = 'rent_owed';
  end if;
  if exists (select 1 from player_house_upgrades p join house_upgrades u on u.id = p.upgrade_id
              where p.user_id = v_me.id and p.done_at is null and u.effect ? 'to_home') then
    raise exception 'The builders are changing your whole home right now. Wait until they finish, then move.' using errcode = 'P0001', hint = 'tier_building';
  end if;
end $$;

-- the owner moves into a home he owns (free, no fees); his own furniture and the home's upgrades come with him
create or replace function public.property_live_in(p_property uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); p properties; h start_homes; v_res jsonb; res player_residence; v_items int;
begin
  perform bl_prop_move_guard(v_me);
  select * into p from properties where id = p_property and owner_id = v_me.id for update;
  if not found then
    raise exception 'That home is not yours.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  select * into res from player_residence where property_id = p.id;
  if res.user_id = v_me.id then
    raise exception 'You already live here.' using errcode = 'P0001', hint = 'same_home';
  elsif res.user_id is not null then
    raise exception 'A tenant lives here. Give notice first.' using errcode = 'P0001', hint = 'tenant_inside';
  end if;
  h := bl_prop_home(p);
  perform bl_past_homes_expire(v_me.id);
  v_res := bl_home_enter(v_me.id, h, p.id, 'owner', 0, 0, null, 0);
  update properties set listed = false where id = p.id;
  perform bl_prop_log(p.id, v_me.id, 'owner_moved_in', '{}'::jsonb);
  v_items := (v_res->>'in_items')::int;
  return jsonb_build_object('message', 'Welcome home to your ' || lower(bl_prop_name(p)) || '.'
           || case when (v_res->>'upgrades_back')::int > 0 then ' Your upgrades are all here.' else '' end
           || case when v_items > 0 then ' ' || v_items || case when v_items = 1 then ' item is' else ' items are' end || ' in My items. Place them in Arrange.' else '' end,
           'property', p.id, 'layout', v_res->>'layout', 'placed', (v_res->>'placed')::int, 'in_items', v_items);
end $$;

create or replace function public.property_list(p_property uuid, p_rent bigint, p_caution bigint default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); p properties; v_min bigint; v_max bigint; v_cmax bigint;
begin
  perform bl_assert_free(v_me);
  if not bl_prop_on('property.enabled') or not bl_prop_on('property.rent_out_enabled') then
    raise exception 'Renting out homes is paused right now.' using errcode = 'P0001', hint = 'property_disabled';
  end if;
  perform bl_market_seller_ok(v_me);
  select * into p from properties where id = p_property and owner_id = v_me.id for update;
  if not found then
    raise exception 'That home is not yours.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  if exists (select 1 from player_residence where property_id = p.id and user_id = v_me.id) then
    raise exception 'You live here. Move out first, then list it for rent.' using errcode = 'P0001', hint = 'live_here';
  end if;
  if exists (select 1 from player_residence where property_id = p.id) then
    raise exception 'A tenant already lives here. You can change the rent after they leave.' using errcode = 'P0001', hint = 'tenant_inside';
  end if;
  v_min := bl_prop_rent_min(p); v_max := bl_prop_rent_max(p);
  if p_rent is null or p_rent < v_min or p_rent > v_max then
    raise exception 'Rent for this home must be between % and % a week (market rent is %).', bl_naira(v_min), bl_naira(v_max), bl_naira(bl_prop_market_rent(p))
      using errcode = 'P0001', hint = 'rent_band';
  end if;
  v_cmax := floor(p_rent * bl_prop_num('property.caution_max_weeks', 8))::bigint;
  if coalesce(p_caution, 0) < 0 or coalesce(p_caution, 0) > v_cmax then
    raise exception 'The caution can be at most % (% weeks of rent).', bl_naira(v_cmax), bl_prop_num('property.caution_max_weeks', 8)::int
      using errcode = 'P0001', hint = 'caution_max';
  end if;
  update properties set listed = true, listed_rent = p_rent, caution = coalesce(p_caution, 0), listed_at = bl_now() where id = p.id;
  perform bl_prop_log(p.id, v_me.id, 'listed', jsonb_build_object('rent', p_rent, 'caution', coalesce(p_caution, 0)));
  return jsonb_build_object('message', bl_prop_name(p) || ' is listed for ' || bl_naira(p_rent) || ' a week.', 'rent', p_rent, 'caution', coalesce(p_caution, 0));
end $$;

create or replace function public.property_unlist(p_property uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); p properties;
begin
  select * into p from properties where id = p_property and owner_id = v_me.id for update;
  if not found then
    raise exception 'That home is not yours.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  update properties set listed = false, listed_at = null where id = p.id;
  perform bl_prop_log(p.id, v_me.id, 'unlisted', '{}'::jsonb);
  return jsonb_build_object('message', bl_prop_name(p) || ' is off the market.');
end $$;

create or replace function public.bl_prop_listing_card(p public.properties) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  t property_types; a property_areas; h start_homes; hl home_layouts; v_adv bigint; v_agent bigint;
begin
  select * into t from property_types where id = p.type_id;
  select * into a from property_areas where id = p.area;
  h := bl_prop_home(p);
  select * into hl from home_layouts where id = bl_home_layout_id(h.housing_id);
  v_adv := round(p.listed_rent * bl_prop_num('property.tenant_advance_weeks', 1))::bigint;
  v_agent := round(p.listed_rent * bl_prop_num('property.tenant_agent_weeks', 1))::bigint;
  return jsonb_build_object('id', p.id, 'name', bl_prop_name(p), 'area', p.area, 'area_name', a.name, 'type_id', t.id, 'type_name', t.name,
    'emoji', t.emoji, 'bedrooms', t.bedrooms, 'kind', bl_housing_kind(h.housing_id), 'm2', round(hl.w * hl.d),
    'rent', p.listed_rent, 'caution', p.caution, 'market_rent', bl_prop_market_rent(p), 'landlord', bl_username(p.owner_id),
    'unit_no', p.unit_no, 'upgrades', jsonb_array_length(coalesce(p.stash -> 'upgrades', '[]'::jsonb)),
    'garage', coalesce(p.stash -> 'garage', 'null'::jsonb) <> 'null'::jsonb,
    'advance', v_adv, 'agent', v_agent, 'total', v_adv + v_agent + p.caution, 'listed_at', p.listed_at);
end $$;

create or replace function public.property_listings(p_area text default null, p_max_rent bigint default null, p_kind text default null) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_me profiles := bl_me();
begin
  return jsonb_build_object('listings', coalesce((
    select jsonb_agg(bl_prop_listing_card(p) order by p.listed_rent, p.listed_at desc)
      from (select * from properties p
             where p.listed and p.owner_id <> v_me.id and p.listed_rent is not null
               and not exists (select 1 from player_residence r where r.property_id = p.id)
               and not exists (select 1 from player_residence r2 where r2.user_id = p.owner_id and r2.landlord_id = v_me.id)
               and (p_area is null or p_area = '' or p.area = p_area)
               and (p_max_rent is null or p.listed_rent <= p_max_rent)
               and (p_kind is null or p_kind = '' or bl_housing_kind((bl_prop_home(p)).housing_id) = p_kind)
             order by p.listed_rent, p.listed_at desc limit 60) p), '[]'::jsonb));
end $$;

create or replace function public.property_rent_quote(p_property uuid) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_me profiles := bl_me(); p properties; v_card jsonb; v_have bigint; v_reason text;
begin
  select * into p from properties where id = p_property and listed and listed_rent is not null
     and not exists (select 1 from player_residence r where r.property_id = properties.id);
  if not found then
    raise exception 'That home is not for rent any more.' using errcode = 'P0001', hint = 'not_listed';
  end if;
  v_card := bl_prop_listing_card(p);
  v_have := greatest(v_me.bank, 0) + greatest(v_me.cash, 0);
  v_reason := case
    when not bl_prop_on('property.enabled') or not bl_prop_on('property.rent_out_enabled') then 'Renting is paused right now.'
    when p.owner_id = v_me.id then 'You cannot rent your own home.'
    when exists (select 1 from player_residence r2 where r2.user_id = p.owner_id and r2.landlord_id = v_me.id) then 'You cannot rent from your own tenant.'
    when v_have < (v_card->>'total')::bigint then 'You need ' || bl_naira((v_card->>'total')::bigint) || ' and have ' || bl_naira(v_have) || '.'
    else null end;
  return v_card || jsonb_build_object('can_rent', v_reason is null, 'reason', v_reason, 'have', v_have,
    'notice_days', bl_prop_num('property.notice_days', 3));
end $$;

-- a tenant rents a home from a player: caution (held) + rent in advance (to the landlord) + the agent fee, then moves in
create or replace function public.property_rent(p_property uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); p properties; h start_homes; v_card jsonb; v_total bigint; v_adv bigint; v_agent bigint; v_caution bigint;
  v_res jsonb; v_name text; v_items int; v_land text;
begin
  perform bl_prop_move_guard(v_me);
  if not bl_prop_on('property.enabled') or not bl_prop_on('property.rent_out_enabled') then
    raise exception 'Renting is paused right now.' using errcode = 'P0001', hint = 'property_disabled';
  end if;
  select * into p from properties where id = p_property for update;
  if not found or not p.listed or p.listed_rent is null or exists (select 1 from player_residence r where r.property_id = p.id) then
    raise exception 'That home is not for rent any more.' using errcode = 'P0001', hint = 'not_listed';
  end if;
  if p.owner_id = v_me.id then
    raise exception 'You cannot rent your own home. Use "Live here" instead.' using errcode = 'P0001', hint = 'own_property';
  end if;
  if exists (select 1 from player_residence r2 where r2.user_id = p.owner_id and r2.landlord_id = v_me.id) then
    raise exception 'You cannot rent from your own tenant.' using errcode = 'P0001', hint = 'own_tenant';
  end if;
  v_card := bl_prop_listing_card(p);
  v_adv := (v_card->>'advance')::bigint; v_agent := (v_card->>'agent')::bigint; v_caution := p.caution; v_total := (v_card->>'total')::bigint;
  if greatest(v_me.bank, 0) + greatest(v_me.cash, 0) < v_total then
    raise exception 'Not enough money. Moving in costs % (caution % + rent in advance % + agent %) and you have %.', bl_naira(v_total),
      bl_naira(v_caution), bl_naira(v_adv), bl_naira(v_agent), bl_naira(greatest(v_me.bank, 0) + greatest(v_me.cash, 0))
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_name := bl_prop_name(p);
  if v_caution > 0 then perform bl_sink_pay(v_me.id, v_caution, 'rent_caution', jsonb_build_object('label', 'Caution held: ' || v_name, 'property', p.id)); end if;
  if v_adv > 0 then
    perform bl_sink_pay(v_me.id, v_adv, 'rent_paid_player', jsonb_build_object('label', 'Rent in advance to @' || coalesce(bl_username(p.owner_id), 'landlord') || ': ' || v_name, 'property', p.id));
    insert into property_income (owner_id, property_id, tenant_id, tenant_name, property_name, gross, created_at)
    values (p.owner_id, p.id, v_me.id, coalesce(v_me.username, ''), v_name, v_adv, bl_now());
  end if;
  if v_agent > 0 then perform bl_sink_pay(v_me.id, v_agent, 'agent_fee', jsonb_build_object('label', 'Agent and legal fee: ' || v_name, 'property', p.id)); end if;
  h := bl_prop_home(p);
  perform bl_past_homes_expire(v_me.id);
  v_res := bl_home_enter(v_me.id, h, p.id, 'tenant', p.listed_rent, v_caution, p.owner_id,
                         (h.weekly_rent * bl_prop_num('house.move_in_weeks', 4))::bigint);
  perform bl_prop_log(p.id, v_me.id, 'tenant_moved_in', jsonb_build_object('tenant', v_me.username, 'rent', p.listed_rent, 'caution', v_caution));
  perform bl_event(p.owner_id, 'tenant_moved_in', 'New tenant!',
    '@' || coalesce(v_me.username, 'someone') || ' rented ' || v_name || ' at ' || bl_naira(p.listed_rent) || ' a week.',
    jsonb_build_object('property', p.id, 'rent', p.listed_rent));
  v_items := (v_res->>'in_items')::int;
  select 'Landlord @' || coalesce(bl_username(p.owner_id), 'owner') || ', ' || a.name into v_land from property_areas a where a.id = p.area;
  return bl_receipt_issue(v_me.id, 'house', 'Rent: ' || v_name || ' (caution + 1st week)', v_total, v_land,
           jsonb_build_object('property', p.id, 'rent', p.listed_rent, 'caution', v_caution, 'advance', v_adv, 'agent', v_agent))
    || jsonb_build_object('message', 'Welcome to ' || v_name || '! Rent is ' || bl_naira(p.listed_rent) || ' a week, on the usual rent day.'
         || case when v_items > 0 then ' ' || v_items || case when v_items = 1 then ' item is' else ' items are' end || ' in My items. Place them in Arrange.' else '' end,
         'property', p.id, 'layout', v_res->>'layout', 'in_items', v_items, 'spent', v_total, 'weekly_rent', p.listed_rent);
end $$;

create or replace function public.property_give_notice(p_property uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); p properties; res player_residence; v_end timestamptz;
begin
  select * into p from properties where id = p_property and owner_id = v_me.id for update;
  if not found then
    raise exception 'That home is not yours.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  select * into res from player_residence where property_id = p.id and role = 'tenant' for update;
  if not found then
    raise exception 'Nobody is renting this home.' using errcode = 'P0001', hint = 'no_tenant';
  end if;
  if res.ends_at is not null then
    raise exception 'Notice was already given. The tenant must leave by %.', to_char(res.ends_at at time zone 'Africa/Lagos', 'DD Mon HH24:MI')
      using errcode = 'P0001', hint = 'already_notice';
  end if;
  v_end := bl_now() + interval '1 day' * bl_prop_num('property.notice_days', 3);
  update player_residence set notice_at = bl_now(), ends_at = v_end, ended_by = 'landlord' where user_id = res.user_id;
  perform bl_prop_log(p.id, v_me.id, 'notice_given', jsonb_build_object('tenant', bl_username(res.user_id), 'ends_at', v_end));
  perform bl_event(res.user_id, 'rent_notice', 'Notice to leave',
    '@' || coalesce(v_me.username, 'your landlord') || ' wants ' || bl_prop_name(p) || ' back. You must leave by ' || to_char(v_end at time zone 'Africa/Lagos', 'DD Mon HH24:MI')
    || '. Your caution comes back when you move out.', jsonb_build_object('property', p.id, 'ends_at', v_end));
  return jsonb_build_object('message', 'Notice given. @' || coalesce(bl_username(res.user_id), 'the tenant') || ' has until ' || to_char(v_end at time zone 'Africa/Lagos', 'DD Mon HH24:MI') || ' (Benin time).',
                            'ends_at', v_end);
end $$;

create or replace function public.property_cancel_notice(p_property uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); p properties; res player_residence;
begin
  select * into p from properties where id = p_property and owner_id = v_me.id for update;
  if not found then
    raise exception 'That home is not yours.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  select * into res from player_residence where property_id = p.id and role = 'tenant' and ends_at is not null and ended_by = 'landlord' for update;
  if not found then
    raise exception 'There is no notice to cancel.' using errcode = 'P0001', hint = 'no_notice';
  end if;
  update player_residence set notice_at = null, ends_at = null, ended_by = null where user_id = res.user_id;
  perform bl_prop_log(p.id, v_me.id, 'notice_cancelled', '{}'::jsonb);
  perform bl_event(res.user_id, 'rent_notice_off', 'Notice withdrawn', 'Your landlord withdrew the notice. You can stay in ' || bl_prop_name(p) || '.', jsonb_build_object('property', p.id));
  return jsonb_build_object('message', 'Notice withdrawn. The tenant can stay.');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 13. Rent flows tenant -> landlord, evictions, the lazy tick
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_rent_reason(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from player_residence where user_id = p_uid and role = 'tenant') then 'rent_paid_player' else 'rent' end
$$;

-- a tenant paid p_paid of rent: it is the landlord's, collected the next time the landlord plays (no lock on the landlord here)
create or replace function public.bl_tenant_rent_paid(p_uid uuid, p_paid bigint) returns void
language plpgsql security definer set search_path = public as $$
declare res player_residence; p properties;
begin
  if coalesce(p_paid, 0) <= 0 then return; end if;
  select * into res from player_residence where user_id = p_uid and role = 'tenant';
  if not found then return; end if;
  select * into p from properties where id = res.property_id;
  insert into property_income (owner_id, property_id, tenant_id, tenant_name, property_name, gross, created_at)
  values (p.owner_id, p.id, p_uid, coalesce(bl_username(p_uid), ''), bl_prop_name(p), p_paid, bl_now());
end $$;

-- where an evicted tenant goes: the newest past home, else the cheapest city room
create or replace function public.bl_evict_target(p_uid uuid) returns public.start_homes
language plpgsql stable security definer set search_path = public as $$
declare h start_homes;
begin
  select s.* into h from player_past_homes ph join start_homes s on s.id = ph.start_home
   where ph.user_id = p_uid and ph.expires_at > bl_now() and s.active order by ph.left_at desc limit 1;
  if found then return h; end if;
  select * into h from start_homes where active and bl_housing_kind(housing_id) <> 'hostel' order by weekly_rent, sort limit 1;
  return h;
end $$;

-- a tenancy ends without the tenant choosing: 'notice' (the landlord's notice ran out), 'owed' (too much rent owed), 'admin'
create or replace function public.bl_tenancy_end(p_uid uuid, p_why text) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles; res player_residence; p properties; h start_homes; v_seize bigint := 0; v_name text; v_owed bigint;
begin
  select * into v_me from profiles where id = p_uid for update;
  select * into res from player_residence where user_id = p_uid and role = 'tenant' for update;
  if not found then return false; end if;
  -- not while the tenant is away from home (visiting, on the road, in a cell or a ward): the lazy tick tries again later
  if v_me.home_visit_host_id is not null or v_me.travel_to is not null
     or (v_me.jailed_until is not null and v_me.jailed_until > bl_now()) or (v_me.hospitalized_until is not null and v_me.hospitalized_until > bl_now()) then
    if p_why = 'admin' then
      raise exception 'The tenant is away right now (visiting, travelling, in a cell or in hospital). Try again in a few minutes.' using errcode = 'P0001', hint = 'tenant_away';
    end if;
    return false;
  end if;
  select * into p from properties where id = res.property_id;
  v_name := bl_prop_name(p);
  v_owed := v_me.rent_owed;
  if p_why in ('owed', 'notice') and v_owed > 0 and res.caution > 0 then
    -- the landlord keeps as much of the caution as the tenant owes
    v_seize := least(res.caution, v_owed);
    update player_residence set caution = caution - v_seize where user_id = p_uid;
    insert into property_income (owner_id, property_id, tenant_id, tenant_name, property_name, gross, created_at)
    values (p.owner_id, p.id, p_uid, coalesce(v_me.username, ''), v_name || ' (caution kept)', v_seize, bl_now());
  end if;
  if v_owed > 0 then update profiles set rent_owed = 0 where id = p_uid; end if;   -- the rest is written off
  h := bl_evict_target(p_uid);
  update properties set listed = case when p_why in ('notice', 'admin') then false else listed end where id = p.id;
  perform bl_prop_log(p.id, p_uid, 'tenancy_ended', jsonb_build_object('why', p_why, 'tenant', v_me.username, 'owed', v_owed, 'caution_kept', v_seize));
  perform bl_home_enter(p_uid, h, null, null, h.weekly_rent, 0, null, 0);
  perform bl_event(p_uid, 'tenancy_ended',
    case p_why when 'owed' then 'Evicted for unpaid rent' when 'admin' then 'Tenancy ended' else 'Your notice ran out' end,
    case p_why when 'owed' then 'You owed too much rent on ' || v_name || '. The landlord took the caution (' || bl_naira(v_seize) || ') and you were moved to ' || h.name || '.'
               when 'admin' then 'An admin ended your tenancy of ' || v_name || '. You were moved to ' || h.name || '. Your caution came back.'
               else 'The notice on ' || v_name || ' ran out. You were moved to ' || h.name || ' and your caution came back.' end,
    jsonb_build_object('property', p.id, 'why', p_why));
  perform bl_event(p.owner_id, 'tenancy_ended', 'Tenancy ended',
    '@' || coalesce(v_me.username, 'your tenant') || ' is out of ' || v_name || case p_why when 'owed' then ' (unpaid rent).' when 'admin' then ' (ended by an admin).' else '.' end,
    jsonb_build_object('property', p.id, 'why', p_why));
  return true;
end $$;

-- the tenant side: notice ran out, or too many weeks of rent owed (the existing owed-rent rule)
create or replace function public.bl_tenancy_tick(p_uid uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare res player_residence; v_owed bigint;
begin
  select * into res from player_residence where user_id = p_uid and role = 'tenant';
  if not found then return false; end if;
  select rent_owed into v_owed from profiles where id = p_uid;
  if res.ends_at is not null and res.ends_at <= bl_now() then
    return bl_tenancy_end(p_uid, 'notice');
  elsif v_owed > 0 and res.rent > 0 and v_owed >= res.rent * bl_prop_num('property.evict_owed_weeks', 3) then
    return bl_tenancy_end(p_uid, 'owed');
  end if;
  return false;
end $$;

-- the landlord's rent: collected into the bank, the agent cut taken, one ledger line per property and tenant
create or replace function public.bl_property_collect(p_uid uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare r record; v_cut bigint; v_total bigint := 0; v_net bigint := 0; v_cutpct numeric := bl_prop_num('property.rent_cut_pct', 5);
begin
  for r in select property_id, tenant_id, max(tenant_name) as tn, max(property_name) as pn, sum(gross)::bigint as g, array_agg(id) as ids
             from property_income where owner_id = p_uid and collected_at is null group by property_id, tenant_id order by min(id) loop
    perform bl_add_money(p_uid, 'bank', r.g, 'rent_income', jsonb_build_object('label', 'Rent from @' || coalesce(nullif(r.tn, ''), 'tenant') || ': ' || r.pn,
      'property', r.property_id, 'tenant', r.tenant_id));
    v_cut := round(r.g * v_cutpct / 100.0)::bigint;
    if v_cut > 0 then
      perform bl_add_money(p_uid, 'bank', -v_cut, 'agent_fee', jsonb_build_object('label', 'Agent cut on rent: ' || r.pn, 'property', r.property_id));
    end if;
    update property_income set collected_at = bl_now() where id = any (r.ids);
    v_total := v_total + r.g; v_net := v_net + r.g - v_cut;
  end loop;
  if v_total > 0 then
    perform bl_event(p_uid, 'rent_income', 'Rent received', bl_naira(v_net) || ' rent landed in your bank (' || bl_naira(v_total) || ' less the agent cut).',
      jsonb_build_object('gross', v_total, 'net', v_net));
  end if;
  return v_net;
end $$;

-- the cheap question asked on every call: is there anything for this player to settle?
create or replace function public.bl_property_pending(p_uid uuid, p_owed bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from property_builds b where b.owner_id = p_uid and b.status = 'building' and b.ready_at <= bl_now())
      or exists (select 1 from property_income i where i.owner_id = p_uid and i.collected_at is null)
      or exists (select 1 from player_residence r where r.user_id = p_uid and r.role = 'tenant'
                  and ((r.ends_at is not null and r.ends_at <= bl_now())
                       or (p_owed > 0 and r.rent > 0 and p_owed >= r.rent * bl_prop_num('property.evict_owed_weeks', 3))))
$$;

create or replace function public.bl_property_tick(p_uid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform bl_property_builds_settle(p_uid);
  perform bl_tenancy_tick(p_uid);
  perform bl_property_collect(p_uid);
end $$;

-- the landlord looks: charge his tenants who have not played since their rent day (their rows are locked after his, never the other way)
create or replace function public.bl_property_owner_tick(p_uid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  for t in select r.user_id from player_residence r where r.landlord_id = p_uid and r.role = 'tenant' order by r.user_id loop
    perform 1 from profiles where id = t for update;
    perform bl_charge_rent(t);
    perform bl_tenancy_tick(t);
  end loop;
  perform bl_property_tick(p_uid);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 14. The Houses app: one call for the whole picture
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_prop_card(p public.properties) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  t property_types; a property_areas; res player_residence; v_occ jsonb := null; h start_homes; hl home_layouts; v_up int; v_garage boolean;
  v_owed bigint; v_un text;
begin
  select * into t from property_types where id = p.type_id;
  select * into a from property_areas where id = p.area;
  select * into res from player_residence where property_id = p.id;
  if res.user_id is not null then
    select username, rent_owed into v_un, v_owed from profiles where id = res.user_id;
    v_occ := jsonb_build_object('user_id', res.user_id, 'username', v_un, 'role', res.role, 'since', res.since, 'rent', res.rent, 'caution', res.caution,
               'owed', coalesce(v_owed, 0), 'notice_at', res.notice_at, 'ends_at', res.ends_at, 'ended_by', res.ended_by);
  end if;
  h := bl_prop_home(p);
  select * into hl from home_layouts where id = bl_home_layout_id(h.housing_id);
  if res.user_id = p.owner_id then
    select count(*) into v_up from player_house_upgrades where user_id = p.owner_id;
    v_garage := exists (select 1 from player_garages where user_id = p.owner_id);
  else
    v_up := jsonb_array_length(coalesce(p.stash -> 'upgrades', '[]'::jsonb));
    v_garage := coalesce(p.stash -> 'garage', 'null'::jsonb) <> 'null'::jsonb;
  end if;
  return jsonb_build_object('id', p.id, 'name', bl_prop_name(p), 'area', p.area, 'area_name', a.name, 'type_id', t.id, 'type_name', t.name,
    'emoji', t.emoji, 'bedrooms', t.bedrooms, 'kind', bl_housing_kind(h.housing_id), 'm2', round(hl.w * hl.d),
    'source', p.source, 'unit_no', p.unit_no, 'build_id', p.build_id, 'basis', p.basis, 'value', bl_prop_value(p),
    'market_rent', bl_prop_market_rent(p), 'rent_min', bl_prop_rent_min(p), 'rent_max', bl_prop_rent_max(p),
    'listed', p.listed, 'listed_rent', p.listed_rent, 'caution', p.caution, 'sale', bl_prop_sale(p),
    'upgrades', v_up, 'garage', v_garage, 'occupant', v_occ, 'lives_here', coalesce(res.user_id = p.owner_id, false),
    'bill_rent', h.weekly_rent,
    'pending_income', (select coalesce(sum(gross), 0) from property_income where property_id = p.id and collected_at is null),
    'earned', (select coalesce(sum(gross), 0) from property_income where property_id = p.id),
    'acquired_at', p.acquired_at);
end $$;

create or replace function public.property_overview() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); v_res jsonb := null; res player_residence; p properties;
begin
  perform bl_property_owner_tick(v_me.id);
  select * into v_me from profiles where id = v_me.id;
  perform bl_past_homes_expire(v_me.id);
  select * into res from player_residence where user_id = v_me.id;
  if res.user_id is not null then
    select * into p from properties where id = res.property_id;
    v_res := jsonb_build_object('role', res.role, 'property', bl_prop_card(p), 'since', res.since, 'rent', res.rent, 'caution', res.caution,
               'landlord', bl_username(p.owner_id), 'notice_at', res.notice_at, 'ends_at', res.ends_at, 'ended_by', res.ended_by);
  end if;
  return jsonb_build_object(
    'enabled', bl_prop_on('property.enabled'), 'buy_enabled', bl_prop_on('property.buy_enabled'),
    'build_enabled', bl_prop_on('property.build_enabled'), 'rent_out_enabled', bl_prop_on('property.rent_out_enabled'),
    'money', jsonb_build_object('bank', v_me.bank, 'cash', v_me.cash),
    'settings', jsonb_build_object('agent_fee_pct', bl_prop_num('property.agent_fee_pct', 3), 'legal_fee_pct', bl_prop_num('property.legal_fee_pct', 1.5),
       'resale_pct', bl_prop_num('property.resale_pct', 85), 'sell_agent_pct', bl_prop_num('property.sell_agent_pct', 2),
       'rent_cut_pct', bl_prop_num('property.rent_cut_pct', 5), 'notice_days', bl_prop_num('property.notice_days', 3),
       'caution_max_weeks', bl_prop_num('property.caution_max_weeks', 8), 'return_days', bl_prop_num('house.return_days', 30),
       'evict_owed_weeks', bl_prop_num('property.evict_owed_weeks', 3), 'advance_weeks', bl_prop_num('property.tenant_advance_weeks', 1),
       'tenant_agent_weeks', bl_prop_num('property.tenant_agent_weeks', 1), 'max_owned', bl_prop_num('property.max_owned', 20),
       'permit_pct', bl_prop_num('property.build_permit_pct', 2), 'cancel_refund_pct', bl_prop_num('property.build_cancel_refund_pct', 60)),
    'areas', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'blurb', a.blurb, 'can_build', a.land_market is not null,
                          'land', bl_prop_land(v_me.id, a)) order by a.sort, a.id) from property_areas a where a.active), '[]'::jsonb),
    'types', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'emoji', t.emoji, 'bedrooms', t.bedrooms, 'blurb', t.blurb,
                          'kind', bl_housing_kind(h.housing_id), 'm2', round(hl.w * hl.d)) order by t.sort, t.id)
                         from property_types t join start_homes h on h.id = t.template_home
                         left join home_layouts hl on hl.id = bl_home_layout_id(h.housing_id) where t.active), '[]'::jsonb),
    'offers', coalesce((select jsonb_agg(bl_prop_offer_card(o) order by o.sort, o.price) from property_offers o
                         join property_areas a on a.id = o.area and a.active join property_types t on t.id = o.type_id and t.active
                        where o.active), '[]'::jsonb),
    'designs', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'emoji', d.emoji, 'description', d.description,
                           'type_id', d.type_id, 'units', d.units, 'plots', d.plots, 'hours', bl_prop_build_hours(d), 'stages', d.stages,
                           'costs', (select jsonb_object_agg(a.id, bl_prop_build_cost(d, a)) from property_areas a where a.active and a.land_market is not null))
                           order by d.sort, d.id) from property_designs d where d.active), '[]'::jsonb),
    'builds', coalesce((select jsonb_agg(bl_prop_build_card(b) order by b.ready_at) from property_builds b where b.owner_id = v_me.id and b.status = 'building'), '[]'::jsonb),
    'properties', coalesce((select jsonb_agg(bl_prop_card(x) order by x.acquired_at, x.unit_no nulls first) from properties x where x.owner_id = v_me.id), '[]'::jsonb),
    'residence', v_res,
    'pending_income', (select coalesce(sum(gross), 0) from property_income where owner_id = v_me.id and collected_at is null),
    'owned_count', bl_prop_owned_count(v_me.id));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 15. Admin: listings, tenancies, builds, and ending a bad tenancy (audited)
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_property_overview(p_limit int default 100) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_lim int := greatest(1, least(coalesce(p_limit, 100), 500));
begin
  return jsonb_build_object(
    'stats', jsonb_build_object(
      'properties', (select count(*) from properties), 'bought', (select count(*) from properties where source = 'bought'),
      'built', (select count(*) from properties where source = 'built'),
      'listed_vacant', (select count(*) from properties p where p.listed and not exists (select 1 from player_residence r where r.property_id = p.id)),
      'tenancies', (select count(*) from player_residence where role = 'tenant'),
      'owner_living', (select count(*) from player_residence where role = 'owner'),
      'builds', (select count(*) from property_builds where status = 'building'),
      'rent_per_week', (select coalesce(sum(rent), 0) from player_residence where role = 'tenant'),
      'rent_paid_7d', (select coalesce(sum(gross), 0) from property_income where created_at > bl_now() - interval '7 days'),
      'value', (select coalesce(sum(basis), 0) from properties)),
    'listings', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', bl_prop_name(p), 'area', p.area, 'owner', bl_username(p.owner_id),
        'rent', p.listed_rent, 'caution', p.caution, 'market_rent', bl_prop_market_rent(p), 'listed_at', p.listed_at) order by p.listed_at desc)
        from (select * from properties p where p.listed and not exists (select 1 from player_residence r where r.property_id = p.id)
               order by p.listed_at desc limit v_lim) p), '[]'::jsonb),
    'tenancies', coalesce((select jsonb_agg(jsonb_build_object('property', p.id, 'name', bl_prop_name(p), 'area', p.area, 'owner', bl_username(p.owner_id),
        'tenant', bl_username(r.user_id), 'rent', r.rent, 'caution', r.caution, 'owed', pr.rent_owed, 'since', r.since, 'notice_at', r.notice_at,
        'ends_at', r.ends_at, 'ended_by', r.ended_by) order by r.since desc)
        from player_residence r join properties p on p.id = r.property_id join profiles pr on pr.id = r.user_id
       where r.role = 'tenant' limit v_lim), '[]'::jsonb),
    'builds', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'owner', bl_username(b.owner_id), 'name', b.name, 'area', b.area, 'cost', b.cost,
        'started_at', b.started_at, 'ready_at', b.ready_at) order by b.ready_at) from property_builds b where b.status = 'building'), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.created_at, 'kind', e.kind, 'user', bl_username(e.user_id), 'detail', e.detail) order by e.id desc)
        from (select * from property_events order by id desc limit 40) e), '[]'::jsonb));
end $$;

create or replace function public.admin_property_end_tenancy(p_property uuid, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); res player_residence; p properties; v_reason text := left(btrim(coalesce(p_reason, '')), 200); v_tenant uuid;
begin
  select * into res from player_residence where property_id = p_property and role = 'tenant';
  if not found then
    raise exception 'Nobody is renting that home.' using errcode = 'P0001', hint = 'no_tenant';
  end if;
  v_tenant := res.user_id;
  select * into p from properties where id = p_property;
  perform 1 from profiles where id = v_tenant for update;
  perform bl_tenancy_end(v_tenant, 'admin');
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'property_end_tenancy', v_tenant,
          jsonb_build_object('property', p_property, 'name', bl_prop_name(p), 'owner', p.owner_id, 'rent', res.rent, 'reason', v_reason));
  return jsonb_build_object('message', 'Tenancy ended and the tenant moved out.', 'property', p_property);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 16. Patches to live functions (guarded)
-- ---------------------------------------------------------------------------------------------
-- bl_me: settle builds, rent income and tenancies that are due (one cheap check)
select pg_temp.pr_patch('public.bl_me()', 'bl_property_pending',
  $o$  if exists (select 1 from city_parties where location_id = v.location_id and ends_at > bl_now()) then$o$,
  $o$  if bl_property_pending(v.id, v.rent_owed) then
    perform bl_property_tick(v.id);
    select * into v from profiles where id = v.id;
  end if;
  if exists (select 1 from city_parties where location_id = v.location_id and ends_at > bl_now()) then$o$);

-- rent a tenant pays is the landlord's: ledger reason rent_paid_player, accrued for the landlord
select pg_temp.pr_patch('public.bl_charge_rent(uuid)', '''bank'', -v_pay, bl_rent_reason(p_uid)',
  $o$perform bl_add_money(p_uid, 'bank', -v_pay, 'rent', v_meta);$o$,
  $o$perform bl_add_money(p_uid, 'bank', -v_pay, bl_rent_reason(p_uid), v_meta);$o$);
select pg_temp.pr_patch('public.bl_charge_rent(uuid)', '''cash'', -v_pay, bl_rent_reason(p_uid)',
  $o$perform bl_add_money(p_uid, 'cash', -v_pay, 'rent', v_meta);$o$,
  $o$perform bl_add_money(p_uid, 'cash', -v_pay, bl_rent_reason(p_uid), v_meta);$o$);
select pg_temp.pr_patch('public.bl_charge_rent(uuid)', 'bl_tenant_rent_paid',
  $o$update profiles set rent_due_at = v_due, rent_owed = v_left where id = p_uid;$o$,
  $o$update profiles set rent_due_at = v_due, rent_owed = v_left where id = p_uid;
  perform bl_tenant_rent_paid(p_uid, v_paid);$o$);

select pg_temp.pr_patch('public.pay_rent()', '''bank'', -v_bank, bl_rent_reason(v_me.id)',
  $o$perform bl_add_money(v_me.id, 'bank', -v_bank, 'rent', v_meta);$o$,
  $o$perform bl_add_money(v_me.id, 'bank', -v_bank, bl_rent_reason(v_me.id), v_meta);$o$);
select pg_temp.pr_patch('public.pay_rent()', '''cash'', -v_cash, bl_rent_reason(v_me.id)',
  $o$perform bl_add_money(v_me.id, 'cash', -v_cash, 'rent', v_meta);$o$,
  $o$perform bl_add_money(v_me.id, 'cash', -v_cash, bl_rent_reason(v_me.id), v_meta);$o$);
select pg_temp.pr_patch('public.pay_rent()', 'bl_tenant_rent_paid',
  $o$update profiles set rent_owed = v_left where id = v_me.id;$o$,
  $o$update profiles set rent_owed = v_left where id = v_me.id;
  perform bl_tenant_rent_paid(v_me.id, v_pay);$o$);

-- weekly bills: an owner's house bill follows the rent of the same home type; a bought home pays ground rent on its value
select pg_temp.pr_patch('public.bl_bills_issue(uuid, date)', 'bl_home_bill_rent(v) > 0',
  $o$if v.home_chosen and v.weekly_rent > 0 then$o$,
  $o$if v.home_chosen and bl_home_bill_rent(v) > 0 then$o$);
select pg_temp.pr_patch('public.bl_bills_issue(uuid, date)', '(bl_home_bill_rent(v) * (',
  $o$v_amt := (round((v.weekly_rent * ($o$,
  $o$v_amt := (round((bl_home_bill_rent(v) * ($o$);
select pg_temp.pr_patch('public.bl_bills_issue(uuid, date)', 'from properties pr where pr.owner_id = p_uid',
  $o$return jsonb_build_object('n', n, 'total', v_total, 'due_at', v_due);$o$,
  $o$-- bought homes: ground rent on what the home is worth (a built home pays it through its land plots)
  for r in select pr.id, bl_prop_value(pr) as val, bl_prop_name(pr) as nm from properties pr where pr.owner_id = p_uid and pr.source = 'bought' loop
    v_amt := (round(r.val * bl_econ_num('economy.ground_rent_pct', 0.1) / 100 / 10.0) * 10)::bigint;
    if v_amt >= greatest(v_min, 1) then
      insert into player_bills (user_id, kind, ref, title, detail, amount, period, issued_at, due_at)
      values (p_uid, 'property', r.id::text, 'Ground rent', r.nm, v_amt, p_period, bl_now(), v_due)
      on conflict (user_id, kind, ref, period) do nothing;
      get diagnostics v_n = row_count; n := n + v_n; v_total := v_total + v_amt * v_n;
    end if;
  end loop;
  return jsonb_build_object('n', n, 'total', v_total, 'due_at', v_due);$o$);

-- ledger labels, the Admin -> Economy category, never earned
select pg_temp.pr_patch('public.bl_ledger_label(text, jsonb)', 'when ''house_buy'' then',
  $o$when 'house_move' then return 'Move-in: ' || coalesce(p_meta->>'name', 'new home');$o$,
  $o$when 'house_move' then return 'Move-in: ' || coalesce(p_meta->>'name', 'new home');
    when 'house_buy' then return coalesce(nullif(p_meta->>'label', ''), 'Home bought');
    when 'house_sell' then return coalesce(nullif(p_meta->>'label', ''), 'Home sold');
    when 'build_cost' then return coalesce(nullif(p_meta->>'label', ''), 'Build');
    when 'build_refund' then return coalesce(nullif(p_meta->>'label', ''), 'Build cancelled');
    when 'rent_income' then return coalesce(nullif(p_meta->>'label', ''), 'Rent received');
    when 'rent_paid_player' then return coalesce(nullif(p_meta->>'label', ''), case when (p_meta->>'settle')::boolean then 'Rent paid to landlord (owed)' else 'Rent to landlord' end);
    when 'rent_caution' then return coalesce(nullif(p_meta->>'label', ''), 'Caution');
    when 'agent_fee' then return coalesce(nullif(p_meta->>'label', ''), 'Agent fee');
    when 'legal_fee' then return coalesce(nullif(p_meta->>'label', ''), 'Legal fee');$o$);

select pg_temp.pr_patch('public.bl_econ_category(text)', '''house_buy''',
  $o$when p_reason in ('rent', 'house_move', 'house_upgrade', 'garage') then 'Housing'$o$,
  $o$when p_reason in ('rent', 'house_move', 'house_upgrade', 'garage', 'house_buy', 'house_sell', 'build_cost', 'build_refund', 'rent_income', 'rent_paid_player', 'rent_caution', 'agent_fee', 'legal_fee') then 'Housing'$o$);

-- rent_income IS earned (added to leaderboard.earn_reasons below); every other new reason never is
select pg_temp.pr_patch('public.bl_earn_reasons()', '''build_refund''',
  $o$'kid_school_fee', 'kid_school_lessons'])$o$,
  $o$'kid_school_fee', 'kid_school_lessons', 'house_buy', 'house_sell', 'build_cost', 'build_refund', 'rent_paid_player', 'rent_caution', 'agent_fee', 'legal_fee'])$o$);

-- rent income counts as earnings (weekly top earners and the weekly income tax). Added once.
do $$
begin
  if not exists (select 1 from public.game_config where key = 'property.earn_seeded') then
    update public.game_config
       set value = to_jsonb(rtrim((value #>> '{}'), ',') || ',rent_income')
     where key = 'leaderboard.earn_reasons' and position('rent_income' in (value #>> '{}')) = 0;
    insert into public.game_config (key, value, category, label, description, kind)
    values ('property.earn_seeded', 'true', 'property', 'Rent income counted as earned (seeded)',
            'Set once by the migration so rent_income is in leaderboard.earn_reasons. Leave it.', 'bool');
  end if;
end $$;

-- the Economy dashboard treats buying / selling a home and rent between players as moves, not new money (only while the list is still the old default)
update public.game_config
   set value = to_jsonb((value #>> '{}') || ',house_buy,house_sell,build_cost,build_refund,rent_paid_player,rent_income,rent_caution')
 where key = 'economy.internal_reasons'
   and (value #>> '{}') = 'transfer_out,transfer_in,tip_out,tip_in,bank_deposit,bank_withdraw,pos_deposit,pos_cashout,market_buy,market_sale,steal_gain,steal_loss,crew_deposit,crew_payout,crew_refund,invest_buy,invest_sell';

-- plots under a house or a build cannot be sold or listed
select pg_temp.pr_patch('public.invest_land_sell(text, integer)', 'bl_land_locked',
  $o$  v_price := bl_inv_price(m.id);$o$,
  $o$  if p_plots > pos.qty - bl_land_locked(v_me.id, m.id) then
    raise exception 'Some of your plots carry a house or a build. You can sell % free plot(s) in %.', greatest(0, pos.qty - bl_land_locked(v_me.id, m.id))::bigint, m.name
      using errcode = 'P0001', hint = 'plots_locked';
  end if;
  v_price := bl_inv_price(m.id);$o$);
select pg_temp.pr_patch('public.bl_market_take(uuid, text, text, integer, text)', 'bl_land_locked',
  $o$    v_price := bl_inv_price(m.id);
    v_rel := case when p_qty = pos.qty then pos.cost else floor(pos.cost * p_qty / pos.qty)::bigint end;$o$,
  $o$    if p_qty > pos.qty - bl_land_locked(p_uid, m.id) then
      raise exception 'Some of your plots carry a house or a build. You can list % free plot(s) in %.', greatest(0, pos.qty - bl_land_locked(p_uid, m.id))::bigint, m.name
        using errcode = 'P0001', hint = 'plots_locked';
    end if;
    v_price := bl_inv_price(m.id);
    v_rel := case when p_qty = pos.qty then pos.cost else floor(pos.cost * p_qty / pos.qty)::bigint end;$o$);

-- house upgrades on owned and let homes
select pg_temp.pr_patch('public.bl_house_upgrade_lock(profiles, public.house_upgrades)', 'player_residence',
  $o$  if not (v_kind = any (u.tiers)) then return 'Not for a ' || replace(v_kind, '_', ' ') || '.'; end if;$o$,
  $o$  if not (v_kind = any (u.tiers)) then return 'Not for a ' || replace(v_kind, '_', ' ') || '.'; end if;
  if exists (select 1 from player_residence where user_id = p_me.id and role = 'tenant') then
    return 'This home belongs to your landlord. Only the owner can do works.';
  end if;
  if u.effect ? 'to_home' and exists (select 1 from player_residence where user_id = p_me.id) then
    return 'You own this home. For a bigger plan, buy or build a bigger home.';
  end if;$o$);
select pg_temp.pr_patch('public.bl_house_upgrade_lock(profiles, public.house_upgrades)', 'player_past_homes',
  $o$from player_released_homes where user_id = p_me.id and start_home = h.id) then$o$,
  $o$from player_past_homes where user_id = p_me.id and start_home = h.id and expires_at > bl_now()) then$o$);
select pg_temp.pr_patch('public.bl_house_upgrade_lock(profiles, public.house_upgrades)', 'as a past home',
  $o$return 'You moved out of ' || h.name || ' already. You can''t go back.';$o$,
  $o$return 'You still hold ' || h.name || ' as a past home. Move back to it, or give it up, first.';$o$);
select pg_temp.pr_patch('public.house_upgrade_state()', 'player_residence',
  $o$v_fee_pct numeric := coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.upgrade_landlord_fee_pct'), 10);$o$,
  $o$v_fee_pct numeric := case when exists (select 1 from player_residence where user_id = v_me.id and role = 'owner') then 0
                          else coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.upgrade_landlord_fee_pct'), 10) end;$o$);
select pg_temp.pr_patch('public.house_upgrade_state()', 'belongs to a player landlord',
  $o$    when v_me.rent_owed > 0 then 'Settle your ' || bl_naira(v_me.rent_owed) || ' rent first. The landlord won''t approve works while you owe.'$o$,
  $o$    when exists (select 1 from player_residence where user_id = v_me.id and role = 'tenant') then 'This home belongs to a player landlord. Only the owner can do works.'
    when v_me.rent_owed > 0 then 'Settle your ' || bl_naira(v_me.rent_owed) || ' rent first. The landlord won''t approve works while you owe.'$o$);
select pg_temp.pr_patch('public.house_upgrade_buy(text)', 'player_residence',
  $o$v_fee_pct numeric := coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.upgrade_landlord_fee_pct'), 10);$o$,
  $o$v_fee_pct numeric := case when exists (select 1 from player_residence where user_id = v_me.id and role = 'owner') then 0
                          else coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.upgrade_landlord_fee_pct'), 10) end;$o$);

-- admin Content editor
select pg_temp.pr_patch('public.bl_admin_table_spec(text)', 'when ''property_areas'' then',
  E'when ''house_upgrades'' then',
  E'when ''property_areas'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","district":"text","land_market":"text_null","x":"num","y":"num","build_factor":"num","rent_yield_pct":"num","blurb":"text","sort":"int","active":"bool"}}''\n    when ''property_types'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","emoji":"text","template_home":"text","bedrooms":"int","blurb":"text","sort":"int","active":"bool"}}''\n    when ''property_offers'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"area":"text","type_id":"text","price":"money","sort":"int","active":"bool"}}''\n    when ''property_designs'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","emoji":"text","description":"text","type_id":"text","units":"int","plots":"int","base_cost":"money","build_hours":"num","stages":"jarr","sort":"int","active":"bool"}}''\n    when ''house_upgrades'' then');

-- ---------------------------------------------------------------------------------------------
-- 17. Players who moved out before this update get their old homes back as past homes (for house.return_days from now)
-- ---------------------------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from public.game_config where key = 'property.legacy_seeded') then
    insert into public.player_past_homes (user_id, start_home, housing_id, left_at, expires_at, stash)
    select r.user_id, r.start_home, r.housing_id, now(), now() + interval '1 day' * coalesce((select (value #>> '{}')::numeric from public.game_config where key = 'house.return_days'), 30), '{}'::jsonb
      from public.player_released_homes r
      join public.start_homes h on h.id = r.start_home and h.active
      join public.profiles p on p.id = r.user_id and p.start_home is distinct from r.start_home
    on conflict (user_id, start_home) do nothing;
    insert into public.game_config (key, value, category, label, description, kind)
    values ('property.legacy_seeded', 'true', 'property', 'Old released homes turned into past homes (seeded)',
            'Set once by the migration. Leave it.', 'bool');
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 18. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and (proname like 'bl\_prop\_%' or proname like 'bl\_home\_%' or proname like 'bl\_past\_home%' or proname like 'bl\_property\_%'
                 or proname like 'bl\_tenan%' or proname in ('bl_land_locked', 'bl_stash_value', 'bl_rent_reason', 'bl_evict_target', 'bl_username')) loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and (proname like 'property\_%' or proname in ('house_move', 'house_options', 'house_past_release')) loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and proname like 'admin\_property\_%' loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
end $$;

notify pgrst, 'reload schema';
