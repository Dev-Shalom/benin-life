-- Y1 Yahoo lifestyle (docs/YAHOO.md, owner-approved spec docs/LIFESTYLE_PLAN.md section 2). In-game satire: slang only,
-- the jobs are abstract buttons ("Chat a client"); nothing here describes how any real scam works.
-- * Gear (items, admin-editable prices): six laptops (the old N45k "Fairly-used Laptop" stays the weakest one and still
--   counts for tech jobs; any laptop now does), the iPhone 18 (Burgundy) N2,400,000 (status item, small hype bonus),
--   MiFi + data bundle N50,000 / week and a cybercafe desk N5,000 / day (timed passes in yahoo_players).
-- * laptop_specs: what each laptop does for Yahoo work (tier, +% payout, - EFCC points, % faster). yahoo_jobs: Chat a client
--   20 s N5k-N50k 20 %, Romance job 40 s N50k-N400k 25 %, Big job 60 s N500k-N3M 35 % (mid-tier laptop+), Cash out 15 s 32 %.
--   Cooldown per job. yahoo_ranks: Aspirant -> G-boy -> Big Boy -> Chairman by total successful Yahoo earnings.
-- * Jobs run at home with an active MiFi, or at the cybercafe (yahoo.cafe_locations, Ugbowo Wi-Fi Joint near UNIBEN) with a
--   desk pass. Payouts land in the dirty "yahoo balance" (yahoo_players.dirty), spendable only after a Cash out.
-- * EFCC caught (bl_rand roll; laptop and charm modifiers: EFCC blindfold -15 pts, bad luck +10 pts, road opener never):
--   the C1 jail_cases flow with kind 'efcc' (bail yahoo.bail_base N50M, escape caught yahoo.escape_caught_pct 55 %, the
--   vanishing charm still applies), the laptop used is seized and the whole dirty balance is confiscated.
-- * Rank perks: badge (get_public_profile.yahoo_rank), Big Boys' VIP booth in clubs (yahoo.vip_rank), + hype %.
--   bl_yahoo_rank(uid) / bl_yahoo_rank_at_least(uid, rank) for later features (Hookup weekend getaway: Big Boy+).
-- Idempotent and safe on a non-empty DB: seeds use "on conflict do nothing" (admin edits survive a re-run), live
-- functions are patched from pg_get_functiondef with guarded replacements (create or replace keeps the grants).

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (category yahoo)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('yahoo.enabled', 'true', 'yahoo', 'Yahoo life on',
 'Y1: players with a laptop can do Yahoo jobs from the phone (at home with MiFi, or at the cybercafe with a desk). Off = jobs and passes are refused.', 'bool', null, null),
('yahoo.mifi_price', '50000', 'yahoo', 'MiFi + data bundle price',
 'Y1: price of one MiFi + data pass (lets you do Yahoo jobs at home). Paid from cash first, then bank.', 'naira', 0, 1000000000000),
('yahoo.mifi_days', '7', 'yahoo', 'MiFi pass: days',
 'Y1: how many real days one MiFi pass lasts. Buying again adds the days on top.', 'number', 1, 365),
('yahoo.desk_price', '5000', 'yahoo', 'Cybercafe desk price',
 'Y1: price of one cybercafe desk pass (lets you do Yahoo jobs at the cybercafe without MiFi).', 'naira', 0, 1000000000000),
('yahoo.desk_hours', '24', 'yahoo', 'Cybercafe desk pass: hours',
 'Y1: how many real hours one desk pass lasts. Buying again adds the hours on top.', 'number', 1, 720),
('yahoo.cafe_locations', '"wifi_joint"', 'yahoo', 'Cybercafe places',
 'Y1: comma-separated location ids where a desk pass works (default: Ugbowo Wi-Fi Joint by UNIBEN).', 'text', null, null),
('yahoo.bail_base', '50000000', 'yahoo', 'EFCC bail',
 'Y1: bail price when EFCC catches a player (bank first, then cash). Failed escapes multiply it like crime bail (crime.escape_bail_mult).', 'naira', 0, 9000000000000000),
('yahoo.escape_caught_pct', '55', 'yahoo', 'EFCC escape: chance of being caught again',
 'Y1: chance a "Try to escape" from an EFCC case fails (the vanishing charm and bad luck still apply). Fail = time and bail multiply (crime.escape_*_mult).', 'percent', 0, 100),
('yahoo.jail_seconds', '90', 'yahoo', 'EFCC jail time (seconds)',
 'Y1: base cell time for an EFCC case. Failed escapes multiply it (crime.escape_time_mult), capped by crime.case_jail_max_seconds.', 'number', 1, 604800),
('yahoo.caught_floor_pct', '5', 'yahoo', 'Lowest EFCC caught chance',
 'Y1: laptops and charms can never push a job''s EFCC caught chance below this (or below the job''s own chance when that is lower).', 'percent', 0, 100),
('yahoo.min_seconds', '5', 'yahoo', 'Shortest job time (seconds)',
 'Y1: faster laptops never make a job shorter than this.', 'number', 1, 600),
('yahoo.cashout_min', '1000', 'yahoo', 'Smallest cash out',
 'Y1: the least a player can cash out at once (or their whole yahoo balance when it is smaller).', 'naira', 0, 1000000000000),
('yahoo.iphone_item', '"iphone_18"', 'yahoo', 'Status phone item',
 'Y1: item id of the status phone that gives a small club hype bonus.', 'text', null, null),
('yahoo.iphone_hype_pct', '10', 'yahoo', 'Status phone: + club hype %',
 'Y1: owning the status phone (iPhone 18) makes club hype announcements this much bigger.', 'percent', 0, 500),
('yahoo.vip_rank', '"big_boy"', 'yahoo', 'VIP booth: lowest rank',
 'Y1: the Yahoo rank id (Content -> Yahoo ranks) needed for the Big Boys'' VIP booth.', 'text', null, null),
('yahoo.vip_activities', '"big_boy_booth"', 'yahoo', 'VIP booth activities',
 'Y1: comma-separated activity ids that need the VIP booth rank.', 'text', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Gear (items). Prices researched for Nigeria, Oct 2026 (docs/YAHOO.md): UK-used ThinkPad T480 ~N280k,
--    UK-used EliteBook 840 G5 ~N330k (refurbished N540k+), Dell XPS 13 (2026) ~N1.1M, MacBook Air M4 ~N1.85M,
--    MacBook Pro 14" M4 Pro ~N4.35M.
-- ---------------------------------------------------------------------------------------------
insert into public.items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort) values
('thinkpad_t480',   'Lenovo ThinkPad T480 (UK-used)', 'laptop', 280000,
 'Black brick wey no dey die. Keyboard sweet, battery fit last small. Students and G-boys love am.', '{}',
 '{bronze_tech_hub,wifi_joint,benin_city_mall}', true, 40, '💻', 511),
('elitebook_840',   'HP EliteBook 840 G5 (UK-used)', 'laptop', 330000,
 'Silver office laptop from London. Core i5, 16GB, fingerprint reader. E dey move.', '{}',
 '{bronze_tech_hub,wifi_joint,benin_city_mall}', true, 40, '💻', 512),
('dell_xps_13',     'Dell XPS 13 (2026)', 'laptop', 1100000,
 'Brand-new, thin, fast. Screen bright like Ring Road at night. Opens the Big job.', '{}',
 '{bronze_tech_hub,benin_city_mall}', true, 45, '💻', 513),
('macbook_air_m4',  'MacBook Air M4 (13")', 'laptop', 1850000,
 'Apple fruit on the lid, no fan, battery wey fit last all day. Clients sabi say you serious.', '{}',
 '{bronze_tech_hub,benin_city_mall}', true, 50, '💻', 514),
('macbook_pro_m4',  'MacBook Pro 14" (M4 Pro)', 'laptop', 4350000,
 'The chairman machine. Space black, monster chip. Na Big Boy dey carry this one.', '{}',
 '{bronze_tech_hub,benin_city_mall}', true, 50, '💻', 515),
('iphone_18',       'iPhone 18 (Burgundy)', 'gadget', 2400000,
 'The only iPhone in town, deep burgundy. Status don land. Small extra hype for club.', '{}',
 '{bronze_tech_hub,benin_city_mall}', true, 50, '📱', 520)
on conflict (id) do nothing;

-- the old N45k laptop becomes the first (weakest) laptop of the Laptops section (only while it is still a gadget)
update public.items set category = 'laptop' where id = 'laptop' and category = 'gadget';

-- ---------------------------------------------------------------------------------------------
-- 3. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.laptop_specs (
  item_id         text primary key references public.items(id) on update cascade on delete cascade,
  label           text not null default '',               -- short tier name on the cards ("Tokunbo", "Mid", "Top")
  tier            int not null default 0 check (tier between 0 and 100),
  pay_bonus_pct   numeric not null default 0 check (pay_bonus_pct between 0 and 500),   -- + % Yahoo payout
  efcc_minus_pts  numeric not null default 0 check (efcc_minus_pts between 0 and 100),  -- - points EFCC caught
  speed_pct       numeric not null default 0 check (speed_pct between 0 and 90),        -- % shorter job time
  sort            int not null default 0
);
insert into public.laptop_specs (item_id, label, tier, pay_bonus_pct, efcc_minus_pts, speed_pct, sort) values
('laptop',         'Tokunbo',   0,  0, 0,  0, 1),
('thinkpad_t480',  'Workhorse', 1,  5, 1,  5, 2),
('elitebook_840',  'Office',    2,  8, 2, 10, 3),
('dell_xps_13',    'Mid',       3, 15, 4, 15, 4),
('macbook_air_m4', 'Premium',   4, 20, 5, 20, 5),
('macbook_pro_m4', 'Chairman',  5, 30, 8, 30, 6)
on conflict (item_id) do nothing;

create table if not exists public.yahoo_jobs (
  id                text primary key,
  name              text not null,
  icon              text not null default '💻',
  blurb             text not null default '',
  kind              text not null default 'job' check (kind in ('job', 'cashout')),
  seconds           int not null default 20 check (seconds between 1 and 3600),
  pay_min           bigint not null default 0 check (pay_min >= 0),
  pay_max           bigint not null default 0 check (pay_max >= 0),
  caught_pct        numeric not null default 20 check (caught_pct between 0 and 100),
  cooldown_seconds  int not null default 30 check (cooldown_seconds between 0 and 604800),
  min_tier          int not null default 0 check (min_tier between 0 and 100),   -- laptop_specs.tier needed
  sort              int not null default 0,
  active            boolean not null default true
);
insert into public.yahoo_jobs (id, name, icon, blurb, kind, seconds, pay_min, pay_max, caught_pct, cooldown_seconds, min_tier, sort) values
('chat_client', 'Chat a client', '💬', 'Small talk, small money. Keep am sweet, keep am short.', 'job', 20, 5000, 50000, 20, 30, 0, 1),
('romance_job', 'Romance job', '💘', 'Long talk, plenty "my dear". The client dey feel am.', 'job', 40, 50000, 400000, 25, 90, 0, 2),
('big_job', 'Big job', '💼', 'The big one. Only serious machine fit carry am.', 'job', 60, 500000, 3000000, 35, 300, 3, 3),
('cash_out', 'Cash out (crypto / "Western Union guy")', '💸', 'Turn the yahoo balance into money you fit spend. EFCC dey watch the exit.', 'cashout', 15, 0, 0, 32, 60, 0, 4)
on conflict (id) do nothing;

create table if not exists public.yahoo_ranks (
  id           text primary key,
  name         text not null,
  icon         text not null default '💻',
  min_earned   bigint not null default 0 check (min_earned >= 0),   -- total successful Yahoo earnings
  hype_pct     numeric not null default 0 check (hype_pct between 0 and 500),
  perks        text not null default '',
  sort         int not null default 0
);
insert into public.yahoo_ranks (id, name, icon, min_earned, hype_pct, perks, sort) values
('aspirant', 'Aspirant', '🧢', 0, 0, 'Everybody start from somewhere.', 1),
('g_boy', 'G-boy', '😎', 1000000, 5, 'G-boy badge · +5% club hype', 2),
('big_boy', 'Big Boy', '🤑', 10000000, 10, 'Big Boy badge · Big Boys'' VIP booth in every club · +10% club hype', 3),
('chairman', 'Chairman', '👑', 50000000, 20, 'Chairman badge · VIP booth · +20% club hype', 4)
on conflict (id) do nothing;

create table if not exists public.yahoo_players (
  user_id       uuid primary key references public.profiles(id) on delete cascade,
  dirty         bigint not null default 0 check (dirty >= 0),     -- the yahoo balance (not spendable)
  total_earned  bigint not null default 0 check (total_earned >= 0),
  jobs_done     int not null default 0,
  cashed_out    bigint not null default 0,
  busts         int not null default 0,
  mifi_until    timestamptz,
  desk_until    timestamptz,
  updated_at    timestamptz not null default now()
);

create table if not exists public.yahoo_runs (
  id             bigserial primary key,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  job_id         text not null,
  laptop_item    text,
  location_id    text,
  place          text,                   -- 'home' or 'cafe'
  started_at     timestamptz not null,
  resolve_at     timestamptz not null,
  status         text not null default 'running' check (status in ('running', 'paid', 'cashed', 'caught', 'cancelled')),
  caught_pct     numeric not null default 0,
  pay_bonus_pct  numeric not null default 0,
  amount         bigint not null default 0,
  case_id        bigint,
  resolved_at    timestamptz
);
create index if not exists yahoo_runs_user_idx on public.yahoo_runs (user_id, id desc);
create index if not exists yahoo_runs_user_job_idx on public.yahoo_runs (user_id, job_id, started_at desc);
create unique index if not exists yahoo_runs_one_running_uidx on public.yahoo_runs (user_id) where status = 'running';

-- the dirty balance has its own history ("Yahoo: client paid", "Cash out", "EFCC seized")
create table if not exists public.yahoo_ledger (
  id             bigserial primary key,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  delta          bigint not null,
  balance_after  bigint not null,
  reason         text not null check (reason in ('job', 'cashout', 'seized', 'admin')),
  meta           jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);
create index if not exists yahoo_ledger_user_idx on public.yahoo_ledger (user_id, id desc);

alter table public.laptop_specs enable row level security;
alter table public.yahoo_jobs enable row level security;
alter table public.yahoo_ranks enable row level security;
alter table public.yahoo_players enable row level security;
alter table public.yahoo_runs enable row level security;
alter table public.yahoo_ledger enable row level security;
revoke all on table public.laptop_specs, public.yahoo_jobs, public.yahoo_ranks, public.yahoo_players, public.yahoo_runs, public.yahoo_ledger
  from public, anon, authenticated;
revoke all on sequence public.yahoo_runs_id_seq, public.yahoo_ledger_id_seq from public, anon, authenticated;
-- catalogues: read by signed-in players; writes only through admin_row_upsert
grant select on table public.laptop_specs, public.yahoo_jobs, public.yahoo_ranks to authenticated;
drop policy if exists laptop_specs_read on public.laptop_specs;
create policy laptop_specs_read on public.laptop_specs for select to authenticated using (true);
drop policy if exists yahoo_jobs_read on public.yahoo_jobs;
create policy yahoo_jobs_read on public.yahoo_jobs for select to authenticated using (true);
drop policy if exists yahoo_ranks_read on public.yahoo_ranks;
create policy yahoo_ranks_read on public.yahoo_ranks for select to authenticated using (true);
-- my own Yahoo row and history (no client writes); runs stay server-only (the RPCs return them)
grant select on table public.yahoo_players, public.yahoo_ledger to authenticated;
drop policy if exists yahoo_players_own on public.yahoo_players;
create policy yahoo_players_own on public.yahoo_players for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists yahoo_ledger_own on public.yahoo_ledger;
create policy yahoo_ledger_own on public.yahoo_ledger for select to authenticated using (user_id = (select auth.uid()));

-- jail cases learn who caught you (police / EFCC) and what was taken (laptop, dirty money)
alter table public.jail_cases add column if not exists kind text not null default 'police';
alter table public.jail_cases add column if not exists meta jsonb not null default '{}'::jsonb;
do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.jail_cases'::regclass and conname = 'jail_cases_kind_check') then
    alter table public.jail_cases add constraint jail_cases_kind_check check (kind in ('police', 'efcc'));
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_yahoo_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_yahoo_text(p_key text, p_default text) returns text
language sql stable set search_path = public as $$
  select coalesce(nullif((select value #>> '{}' from game_config where key = p_key), ''), p_default);
$$;

create or replace function public.bl_yahoo_list(p_key text, p_default text) returns text[]
language sql stable set search_path = public as $$
  select coalesce(array(select btrim(x) from unnest(string_to_array(bl_yahoo_text(p_key, p_default), ',')) x where btrim(x) <> ''), '{}');
$$;

-- My Yahoo row (created on first use).
create or replace function public.bl_yahoo_row(p_uid uuid, p_lock boolean default false) returns public.yahoo_players
language plpgsql set search_path = public as $$
declare r yahoo_players;
begin
  insert into yahoo_players (user_id) values (p_uid) on conflict (user_id) do nothing;
  if p_lock then
    select * into r from yahoo_players where user_id = p_uid for update;
  else
    select * into r from yahoo_players where user_id = p_uid;
  end if;
  return r;
end $$;

-- The best laptop I own (highest tier, then price): {item_id, name, icon, label, tier, pay_bonus_pct, efcc_minus_pts, speed_pct}.
create or replace function public.bl_yahoo_laptop(p_uid uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('item_id', s.item_id, 'name', it.name, 'icon', it.icon, 'label', s.label, 'tier', s.tier,
                            'pay_bonus_pct', s.pay_bonus_pct, 'efcc_minus_pts', s.efcc_minus_pts, 'speed_pct', s.speed_pct)
    from laptop_specs s join items it on it.id = s.item_id
    join inventory i on i.user_id = p_uid and i.item_id = s.item_id and i.qty > 0
   order by s.tier desc, it.price desc, s.sort
   limit 1;
$$;

create or replace function public.bl_yahoo_rank_row(p_uid uuid) returns public.yahoo_ranks
language sql stable set search_path = public as $$
  select r.* from yahoo_ranks r
   where r.min_earned <= coalesce((select total_earned from yahoo_players where user_id = p_uid), 0)
   order by r.min_earned desc, r.sort desc limit 1;
$$;

-- Rank id for later features (Hookup weekend getaway needs 'big_boy' or higher): 'aspirant' / 'g_boy' / 'big_boy' / 'chairman'.
create or replace function public.bl_yahoo_rank(p_uid uuid) returns text
language sql stable set search_path = public as $$
  select coalesce((bl_yahoo_rank_row(p_uid)).id, 'aspirant');
$$;

-- Is my rank at least this one (by the ranks' earnings thresholds)?
create or replace function public.bl_yahoo_rank_at_least(p_uid uuid, p_rank text) returns boolean
language sql stable set search_path = public as $$
  select coalesce((select total_earned from yahoo_players where user_id = p_uid), 0)
         >= coalesce((select min_earned from yahoo_ranks where id = p_rank), 9223372036854775807);
$$;

-- Badge for profiles: {id, name, icon} above the first rank (null for Aspirants / non-Yahoo players).
create or replace function public.bl_yahoo_rank_public(p_uid uuid) returns jsonb
language sql stable set search_path = public as $$
  select case when r.id is null or r.min_earned <= 0 then null
              else jsonb_build_object('id', r.id, 'name', r.name, 'icon', r.icon) end
    from (select (bl_yahoo_rank_row(p_uid)).*) r;
$$;

create or replace function public.bl_yahoo_assert_rank(p_uid uuid, p_rank text) returns void
language plpgsql stable set search_path = public as $$
declare v_name text;
begin
  if not bl_yahoo_rank_at_least(p_uid, p_rank) then
    select name into v_name from yahoo_ranks where id = p_rank;
    raise exception 'This one na for % and above. Keep hustling.', coalesce(v_name, p_rank) using errcode = 'P0001', hint = 'yahoo_rank';
  end if;
end $$;

-- EFCC caught chance for a job: the job's chance - laptop points - EFCC blindfold + bad luck points (road opener never),
-- never below yahoo.caught_floor_pct (or the job's own chance when that is lower), never above 100.
create or replace function public.bl_yahoo_caught_pct(p_uid uuid, j public.yahoo_jobs, p_laptop jsonb) returns numeric
language sql stable set search_path = public as $$
  select greatest(least(j.caught_pct, greatest(0, least(100, bl_yahoo_num('yahoo.caught_floor_pct', 5)))),
                  least(100, j.caught_pct
                             - coalesce((p_laptop->>'efcc_minus_pts')::numeric, 0)
                             - coalesce(bl_charm_value(p_uid, 'efcc_blindfold'), 0)
                             + coalesce(bl_charm_value(p_uid, 'bad_luck', 'caught_pts'), 0)));
$$;

create or replace function public.bl_yahoo_seconds(j public.yahoo_jobs, p_laptop jsonb) returns int
language sql stable set search_path = public as $$
  select greatest(least(j.seconds, greatest(1, bl_yahoo_num('yahoo.min_seconds', 5)))::int,
                  round(j.seconds * (1 - least(90, greatest(0, coalesce((p_laptop->>'speed_pct')::numeric, 0))) / 100.0))::int);
$$;

-- Where can I work right now? {ok, place ('home' | 'cafe'), hint, message}
create or replace function public.bl_yahoo_where(p_me public.profiles) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  y yahoo_players;
  v_cafes text[] := bl_yahoo_list('yahoo.cafe_locations', 'wifi_joint');
  v_cafe_name text;
begin
  select * into y from yahoo_players where user_id = p_me.id;
  select string_agg(name, ' or ' order by sort) into v_cafe_name from locations where id = any (v_cafes) and coalesce(active, true);
  v_cafe_name := coalesce(v_cafe_name, 'the cybercafe');
  if p_me.travel_to is null and p_me.home_visit_host_id is null and p_me.location_id = p_me.home_location_id then
    if y.mifi_until is not null and y.mifi_until > bl_now() then
      return jsonb_build_object('ok', true, 'place', 'home', 'message', 'Working from home on MiFi.');
    end if;
    return jsonb_build_object('ok', false, 'place', 'home', 'hint', 'no_mifi',
      'message', 'No data for house. Buy a MiFi + data bundle, or go rent a desk at ' || v_cafe_name || '.');
  end if;
  if p_me.travel_to is null and p_me.home_visit_host_id is null and p_me.location_id = any (v_cafes) then
    if y.desk_until is not null and y.desk_until > bl_now() then
      return jsonb_build_object('ok', true, 'place', 'cafe', 'message', 'Working from a cybercafe desk.');
    end if;
    return jsonb_build_object('ok', false, 'place', 'cafe', 'hint', 'no_desk',
      'message', 'Rent a desk first (' || bl_naira(bl_yahoo_num('yahoo.desk_price', 5000)::bigint) || ' a day).');
  end if;
  return jsonb_build_object('ok', false, 'place', null, 'hint', 'wrong_place',
    'message', 'Yahoo work happens at home (with MiFi) or at ' || v_cafe_name || ' (with a desk).');
end $$;

-- Move the dirty balance (locks nothing: callers hold the yahoo_players row).
create or replace function public.bl_yahoo_dirty(p_uid uuid, p_delta bigint, p_reason text, p_meta jsonb) returns bigint
language plpgsql set search_path = public as $$
declare v_after bigint;
begin
  update yahoo_players set dirty = greatest(0, dirty + p_delta), updated_at = bl_now() where user_id = p_uid returning dirty into v_after;
  insert into yahoo_ledger (user_id, delta, balance_after, reason, meta, created_at)
  values (p_uid, p_delta, coalesce(v_after, 0), p_reason, coalesce(p_meta, '{}'::jsonb), bl_now());
  return v_after;
end $$;

create or replace function public.bl_yahoo_ledger_label(p_reason text, p_meta jsonb) returns text
language sql immutable as $$
  select case p_reason
    when 'job' then 'Yahoo: client paid' || coalesce(' · ' || nullif(p_meta->>'job_name', ''), '')
    when 'cashout' then 'Cash out'
    when 'seized' then 'EFCC seized'
    else 'Adjustment' end;
$$;

-- Club hype with Yahoo status: rank hype % + status phone %.
create or replace function public.bl_yahoo_hype_amount(p_uid uuid, p_amount bigint) returns bigint
language sql stable set search_path = public as $$
  select round(coalesce(p_amount, 0) * (1
           + coalesce((bl_yahoo_rank_row(p_uid)).hype_pct, 0) / 100.0
           + case when exists (select 1 from inventory where user_id = p_uid and item_id = bl_yahoo_text('yahoo.iphone_item', 'iphone_18') and qty > 0)
                  then greatest(0, bl_yahoo_num('yahoo.iphone_hype_pct', 10)) / 100.0 else 0 end))::bigint;
$$;

create or replace function public.bl_yahoo_run_json(r public.yahoo_runs) returns jsonb
language sql stable set search_path = public as $$
  select case when r.id is null then null else jsonb_build_object(
    'id', r.id, 'job_id', r.job_id, 'name', (select name from yahoo_jobs where id = r.job_id),
    'icon', (select icon from yahoo_jobs where id = r.job_id), 'started_at', r.started_at, 'resolve_at', r.resolve_at,
    'status', r.status, 'caught_pct', r.caught_pct, 'amount', r.amount, 'laptop_item', r.laptop_item) end;
$$;

-- Resolve one running job (the server roll). Locks the run, the profile and my Yahoo row.
create or replace function public.bl_yahoo_resolve(p_id bigint) returns jsonb
language plpgsql set search_path = public as $$
declare
  r        yahoo_runs;
  j        yahoo_jobs;
  y        yahoo_players;
  v_now    timestamptz := bl_now();
  v_amt    bigint := 0;
  v_seized bigint := 0;
  v_status text;
  v_lap    text;
  v_lap_name text;
  v_had_lap boolean := false;
  v_rank0  text;
  v_rank1  yahoo_ranks;
  v_jail   int := greatest(1, ceil(bl_yahoo_num('yahoo.jail_seconds', 90)))::int;
  v_jail_loc text := bl_yahoo_text('crime.jail_location', 'police_hq');
  v_place  text;
  c        jail_cases;
  v_msg    text;
begin
  select * into r from yahoo_runs where id = p_id for update;
  if not found then return jsonb_build_object('status', 'none'); end if;
  if r.status <> 'running' then
    return jsonb_build_object('status', r.status, 'already', true, 'amount', r.amount, 'job_id', r.job_id);
  end if;
  perform 1 from profiles where id = r.user_id for update;
  y := bl_yahoo_row(r.user_id, true);
  select * into j from yahoo_jobs where id = r.job_id;
  v_rank0 := bl_yahoo_rank(r.user_id);
  select name into v_place from locations where id = r.location_id;

  if bl_crime_roll(r.caught_pct) then
    -- EFCC: the dirty balance is confiscated, the laptop used is seized, a case opens (bail / jail / escape)
    v_status := 'caught';
    v_seized := y.dirty;
    if v_seized > 0 then
      perform bl_yahoo_dirty(r.user_id, -v_seized, 'seized', jsonb_build_object('run_id', r.id, 'job', r.job_id));
    end if;
    v_lap := r.laptop_item;
    select name into v_lap_name from items where id = v_lap;
    if v_lap is not null and exists (select 1 from inventory where user_id = r.user_id and item_id = v_lap and qty > 0) then
      perform bl_give_item(r.user_id, v_lap, -1);
      v_had_lap := true;
    end if;
    update yahoo_players set busts = busts + 1, updated_at = v_now where user_id = r.user_id;
    perform bl_crime_close_stale(r.user_id);
    if exists (select 1 from jail_cases where user_id = r.user_id and status = 'open') then
      update jail_cases set status = 'released', closed_at = v_now where user_id = r.user_id and status = 'open';
    end if;
    insert into jail_cases (user_id, reason, location_id, bail_amount, jail_seconds, jail_until, created_at, kind, meta)
    values (r.user_id, 'EFCC caught you doing Yahoo work' || coalesce(' at ' || v_place, ''), r.location_id,
            greatest(0, round(bl_yahoo_num('yahoo.bail_base', 50000000)))::bigint, v_jail,
            v_now + make_interval(secs => v_jail), v_now, 'efcc',
            jsonb_build_object('run_id', r.id, 'job', r.job_id, 'job_name', j.name, 'laptop', case when v_had_lap then v_lap end,
                               'laptop_name', case when v_had_lap then v_lap_name end, 'seized', v_seized))
    returning * into c;
    update profiles set
      jailed_until = c.jail_until, jail_reason = c.reason, wanted = least(5, wanted + 1),
      location_id = coalesce((select id from locations where id = v_jail_loc), location_id),
      travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
     where id = r.user_id;
    v_msg := 'EFCC don catch you!';
    perform bl_event(r.user_id, 'efcc_caught', 'EFCC don catch you!',
      'EFCC caught you doing Yahoo work.' || case when v_had_lap then ' Your ' || v_lap_name || ' was seized.' else '' end
      || case when v_seized > 0 then ' ' || bl_naira(v_seized) || ' yahoo balance confiscated.' else '' end,
      jsonb_build_object('case_id', c.id, 'seized', v_seized, 'laptop', v_lap));
    update yahoo_runs set status = 'caught', amount = v_seized, case_id = c.id, resolved_at = v_now where id = r.id;
  elsif j.kind = 'cashout' then
    v_status := 'cashed';
    v_amt := least(r.amount, y.dirty);
    if v_amt > 0 then
      perform bl_yahoo_dirty(r.user_id, -v_amt, 'cashout', jsonb_build_object('run_id', r.id));
      perform bl_add_money(r.user_id, 'cash', v_amt, 'yahoo_cashout', jsonb_build_object('run_id', r.id));
      update yahoo_players set cashed_out = cashed_out + v_amt where user_id = r.user_id;
    end if;
    v_msg := case when v_amt > 0 then 'Cash out don land: +' || bl_naira(v_amt) || ' cash.' else 'Nothing left to cash out.' end;
    update yahoo_runs set status = 'cashed', amount = v_amt, resolved_at = v_now where id = r.id;
  else
    v_status := 'paid';
    v_amt := j.pay_min + floor(bl_rand() * (greatest(j.pay_max, j.pay_min) - j.pay_min + 1))::bigint;
    v_amt := greatest(0, round(v_amt * (1 + r.pay_bonus_pct / 100.0) / 100.0) * 100)::bigint;
    if v_amt > 0 then
      perform bl_yahoo_dirty(r.user_id, v_amt, 'job', jsonb_build_object('run_id', r.id, 'job', j.id, 'job_name', j.name));
    end if;
    update yahoo_players set total_earned = total_earned + v_amt, jobs_done = jobs_done + 1, updated_at = v_now where user_id = r.user_id;
    v_msg := 'Client paid: +' || bl_naira(v_amt) || ' (yahoo balance). Cash out before you spend am.';
    update yahoo_runs set status = 'paid', amount = v_amt, resolved_at = v_now where id = r.id;
  end if;

  update profiles set busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
   where id = r.user_id and busy_label like 'Yahoo:%';

  v_rank1 := bl_yahoo_rank_row(r.user_id);
  if v_rank1.id is distinct from v_rank0 and v_status = 'paid' then
    perform bl_event(r.user_id, 'yahoo_rank_up', 'You don rise: ' || v_rank1.name || ' ' || v_rank1.icon,
                     coalesce(nullif(v_rank1.perks, ''), 'New Yahoo rank.'), jsonb_build_object('rank', v_rank1.id));
  end if;

  return jsonb_build_object(
    'status', v_status, 'job_id', r.job_id, 'name', j.name, 'icon', j.icon, 'amount', v_amt, 'seized', v_seized,
    'laptop_seized', case when v_had_lap then v_lap_name end, 'message', v_msg,
    'rank_up', case when v_rank1.id is distinct from v_rank0 and v_status = 'paid'
                    then jsonb_build_object('id', v_rank1.id, 'name', v_rank1.name, 'icon', v_rank1.icon) end,
    'case', case when v_status = 'caught' then bl_crime_case_json(c) end);
end $$;

revoke all on function public.bl_yahoo_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_yahoo_text(text, text) from public, anon, authenticated;
revoke all on function public.bl_yahoo_list(text, text) from public, anon, authenticated;
revoke all on function public.bl_yahoo_row(uuid, boolean) from public, anon, authenticated;
revoke all on function public.bl_yahoo_laptop(uuid) from public, anon, authenticated;
revoke all on function public.bl_yahoo_rank_row(uuid) from public, anon, authenticated;
revoke all on function public.bl_yahoo_rank(uuid) from public, anon, authenticated;
revoke all on function public.bl_yahoo_rank_at_least(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_yahoo_rank_public(uuid) from public, anon, authenticated;
revoke all on function public.bl_yahoo_assert_rank(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_yahoo_caught_pct(uuid, public.yahoo_jobs, jsonb) from public, anon, authenticated;
revoke all on function public.bl_yahoo_seconds(public.yahoo_jobs, jsonb) from public, anon, authenticated;
revoke all on function public.bl_yahoo_where(public.profiles) from public, anon, authenticated;
revoke all on function public.bl_yahoo_dirty(uuid, bigint, text, jsonb) from public, anon, authenticated;
revoke all on function public.bl_yahoo_ledger_label(text, jsonb) from public, anon, authenticated;
revoke all on function public.bl_yahoo_hype_amount(uuid, bigint) from public, anon, authenticated;
revoke all on function public.bl_yahoo_run_json(public.yahoo_runs) from public, anon, authenticated;
revoke all on function public.bl_yahoo_resolve(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 5. Player RPCs
-- ---------------------------------------------------------------------------------------------
-- Everything the Yahoo app needs; also finishes a job whose time is up (after a reload / on login).
create or replace function public.yahoo_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_me   profiles;
  y      yahoo_players;
  r      yahoo_runs;
  v_res  jsonb;
  v_lap  jsonb;
  v_rank yahoo_ranks;
  v_next yahoo_ranks;
  v_where jsonb;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    return jsonb_build_object('enabled', false, 'run', null);
  end if;
  select * into r from yahoo_runs where user_id = v_uid and status = 'running' order by id desc limit 1;
  if found and r.resolve_at <= bl_now() then
    v_res := bl_yahoo_resolve(r.id);
    r := null;
    select * into v_me from profiles where id = v_uid;
  end if;
  y := bl_yahoo_row(v_uid);
  v_lap := bl_yahoo_laptop(v_uid);
  v_rank := bl_yahoo_rank_row(v_uid);
  select * into v_next from yahoo_ranks where min_earned > y.total_earned order by min_earned, sort limit 1;
  v_where := bl_yahoo_where(v_me);
  return jsonb_build_object(
    'enabled', coalesce(bl_cfg_bool('yahoo.enabled'), true),
    'dirty', y.dirty, 'total_earned', y.total_earned, 'jobs_done', y.jobs_done, 'cashed_out', y.cashed_out, 'busts', y.busts,
    'cash', v_me.cash, 'bank', v_me.bank,
    'mifi_until', case when y.mifi_until > bl_now() then y.mifi_until end,
    'desk_until', case when y.desk_until > bl_now() then y.desk_until end,
    'prices', jsonb_build_object('mifi', bl_yahoo_num('yahoo.mifi_price', 50000), 'mifi_days', bl_yahoo_num('yahoo.mifi_days', 7),
                                 'desk', bl_yahoo_num('yahoo.desk_price', 5000), 'desk_hours', bl_yahoo_num('yahoo.desk_hours', 24),
                                 'cashout_min', bl_yahoo_num('yahoo.cashout_min', 1000), 'bail', bl_yahoo_num('yahoo.bail_base', 50000000),
                                 'escape_caught_pct', bl_yahoo_num('yahoo.escape_caught_pct', 55)),
    'cafes', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name) order by l.sort)
                         from locations l where l.id = any (bl_yahoo_list('yahoo.cafe_locations', 'wifi_joint')) and coalesce(l.active, true)), '[]'::jsonb),
    'where', v_where,
    'laptop', v_lap,
    'laptops', coalesce((select jsonb_agg(jsonb_build_object('item_id', s.item_id, 'name', it.name, 'icon', it.icon, 'price', it.price,
                                                             'label', s.label, 'tier', s.tier, 'pay_bonus_pct', s.pay_bonus_pct,
                                                             'efcc_minus_pts', s.efcc_minus_pts, 'speed_pct', s.speed_pct,
                                                             'owned', coalesce(i.qty, 0) > 0, 'sold_at', it.sold_at)
                                          order by s.tier, it.price)
                           from laptop_specs s join items it on it.id = s.item_id
                           left join inventory i on i.user_id = v_uid and i.item_id = s.item_id), '[]'::jsonb),
    'iphone', exists (select 1 from inventory where user_id = v_uid and item_id = bl_yahoo_text('yahoo.iphone_item', 'iphone_18') and qty > 0),
    'charms', jsonb_build_object('blindfold', bl_charm_value(v_uid, 'efcc_blindfold'), 'bad_luck', bl_charm_value(v_uid, 'bad_luck', 'caught_pts')),
    'rank', jsonb_build_object('id', coalesce(v_rank.id, 'aspirant'), 'name', coalesce(v_rank.name, 'Aspirant'), 'icon', coalesce(v_rank.icon, '🧢'),
                               'min_earned', coalesce(v_rank.min_earned, 0), 'hype_pct', coalesce(v_rank.hype_pct, 0), 'perks', v_rank.perks),
    'next_rank', case when v_next.id is not null then jsonb_build_object('id', v_next.id, 'name', v_next.name, 'icon', v_next.icon,
                                                                       'min_earned', v_next.min_earned, 'perks', v_next.perks) end,
    'ranks', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'icon', icon, 'min_earned', min_earned, 'hype_pct', hype_pct, 'perks', perks)
                                        order by min_earned, sort) from yahoo_ranks), '[]'::jsonb),
    'jobs', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', j.id, 'name', j.name, 'icon', j.icon, 'blurb', j.blurb, 'kind', j.kind,
               'seconds', bl_yahoo_seconds(j, v_lap), 'base_seconds', j.seconds,
               'pay_min', round(j.pay_min * (1 + coalesce((v_lap->>'pay_bonus_pct')::numeric, 0) / 100.0)),
               'pay_max', round(j.pay_max * (1 + coalesce((v_lap->>'pay_bonus_pct')::numeric, 0) / 100.0)),
               'caught_pct', bl_yahoo_caught_pct(v_uid, j, v_lap), 'base_caught_pct', j.caught_pct,
               'min_tier', j.min_tier,
               'min_laptop', (select it.name from laptop_specs s join items it on it.id = s.item_id where s.tier >= j.min_tier order by s.tier, it.price limit 1),
               'locked', case when v_lap is null then 'no_laptop'
                              when (v_lap->>'tier')::int < j.min_tier then 'laptop_too_weak' end,
               'cooldown_until', (select max(x.started_at) + make_interval(secs => j.cooldown_seconds) from yahoo_runs x
                                   where x.user_id = v_uid and x.job_id = j.id and x.status <> 'cancelled'
                                   having max(x.started_at) + make_interval(secs => j.cooldown_seconds) > bl_now()))
             order by j.sort, j.id)
        from yahoo_jobs j where j.active), '[]'::jsonb),
    'run', bl_yahoo_run_json(r),
    'resolved', v_res,
    'ledger', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'delta', l.delta, 'balance_after', l.balance_after, 'reason', l.reason,
                                                           'label', bl_yahoo_ledger_label(l.reason, l.meta), 'created_at', l.created_at) order by l.id desc)
                          from (select * from yahoo_ledger where user_id = v_uid order by id desc limit 12) l), '[]'::jsonb));
end $$;
revoke all on function public.yahoo_status() from public, anon;
grant execute on function public.yahoo_status() to authenticated, service_role;

-- Buy a MiFi + data week ('mifi') or a cybercafe desk day ('desk'). Cash first, then bank. Stacks on an active pass.
create or replace function public.yahoo_buy_pass(p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  y       yahoo_players;
  v_price bigint;
  v_secs  numeric;
  v_cash  bigint;
  v_bank  bigint;
  v_until timestamptz;
  v_label text;
begin
  if not coalesce(bl_cfg_bool('yahoo.enabled'), true) then
    raise exception 'Yahoo work is switched off for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  if p_kind = 'mifi' then
    v_price := greatest(0, bl_yahoo_num('yahoo.mifi_price', 50000))::bigint;
    v_secs := greatest(1, bl_yahoo_num('yahoo.mifi_days', 7)) * 86400;
    v_label := 'MiFi + data bundle';
  elsif p_kind = 'desk' then
    v_price := greatest(0, bl_yahoo_num('yahoo.desk_price', 5000))::bigint;
    v_secs := greatest(1, bl_yahoo_num('yahoo.desk_hours', 24)) * 3600;
    v_label := 'Cybercafe desk';
  else
    raise exception 'Unknown pass.' using errcode = 'P0001', hint = 'bad_pass';
  end if;
  perform 1 from profiles where id = v_me.id for update;
  v_me := bl_me();
  if v_me.cash + v_me.bank < v_price then
    raise exception '% costs %. You have % (cash + bank).', v_label, bl_naira(v_price), bl_naira(v_me.cash + v_me.bank)
      using errcode = 'P0001', hint = 'not_enough_money';
  end if;
  y := bl_yahoo_row(v_me.id, true);
  v_cash := least(v_me.cash, v_price);
  v_bank := v_price - v_cash;
  if v_cash > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_cash, 'yahoo_pass', jsonb_build_object('pass', p_kind, 'label', v_label));
  end if;
  if v_bank > 0 then
    perform bl_add_money(v_me.id, 'bank', -v_bank, 'yahoo_pass', jsonb_build_object('pass', p_kind, 'label', v_label));
  end if;
  if p_kind = 'mifi' then
    update yahoo_players set mifi_until = greatest(coalesce(mifi_until, bl_now()), bl_now()) + make_interval(secs => v_secs::double precision),
           updated_at = bl_now() where user_id = v_me.id returning mifi_until into v_until;
  else
    update yahoo_players set desk_until = greatest(coalesce(desk_until, bl_now()), bl_now()) + make_interval(secs => v_secs::double precision),
           updated_at = bl_now() where user_id = v_me.id returning desk_until into v_until;
  end if;
  return jsonb_build_object('pass', p_kind, 'until', v_until, 'paid', v_price, 'cash', v_cash, 'bank', v_bank,
                            'message', v_label || ' ready till ' || to_char(v_until at time zone 'Africa/Lagos', 'Dy FMHH12:MI AM') || '.');
end $$;
revoke all on function public.yahoo_buy_pass(text) from public, anon;
grant execute on function public.yahoo_buy_pass(text) to authenticated, service_role;

-- Start a job (or a cash out of p_amount; null = everything). Laptop + home/MiFi or cafe/desk, free, cooldown over.
create or replace function public.yahoo_job_start(p_job text, p_amount bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  j       yahoo_jobs;
  y       yahoo_players;
  v_lap   jsonb;
  v_where jsonb;
  v_now   timestamptz := bl_now();
  v_last  timestamptz;
  v_secs  int;
  v_pct   numeric;
  v_amt   bigint := 0;
  v_min   bigint := greatest(0, bl_yahoo_num('yahoo.cashout_min', 1000))::bigint;
  v_until timestamptz;
  v_id    bigint;
  v_need  text;
begin
  if not coalesce(bl_cfg_bool('yahoo.enabled'), true) then
    raise exception 'Yahoo work is switched off for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into j from yahoo_jobs where id = p_job and active;
  if not found then
    raise exception 'No such job.' using errcode = 'P0001', hint = 'bad_job';
  end if;
  perform 1 from profiles where id = v_me.id for update;
  v_me := bl_me();
  perform bl_crime_close_stale(v_me.id);
  perform bl_assert_free(v_me);
  y := bl_yahoo_row(v_me.id, true);
  if exists (select 1 from yahoo_runs where user_id = v_me.id and status = 'running') then
    raise exception 'Finish the job you dey do first.' using errcode = 'P0001', hint = 'busy';
  end if;
  v_lap := bl_yahoo_laptop(v_me.id);
  if v_lap is null then
    raise exception 'You need a laptop for this. Check Bronze Tech Hub or the Wi-Fi Joint.' using errcode = 'P0001', hint = 'no_laptop';
  end if;
  if (v_lap->>'tier')::int < j.min_tier then
    select it.name into v_need from laptop_specs s join items it on it.id = s.item_id where s.tier >= j.min_tier order by s.tier, it.price limit 1;
    raise exception '% needs a stronger machine (% or better). Your % no fit carry am.', j.name, coalesce(v_need, 'a better laptop'), v_lap->>'name'
      using errcode = 'P0001', hint = 'laptop_too_weak';
  end if;
  v_where := bl_yahoo_where(v_me);
  if not (v_where->>'ok')::boolean then
    raise exception '%', v_where->>'message' using errcode = 'P0001', hint = v_where->>'hint';
  end if;
  select max(started_at) into v_last from yahoo_runs where user_id = v_me.id and job_id = j.id and status <> 'cancelled';
  if v_last is not null and v_last + make_interval(secs => j.cooldown_seconds) > v_now then
    raise exception 'Cool down small. % again in about % sec.', j.name,
      ceil(extract(epoch from v_last + make_interval(secs => j.cooldown_seconds) - v_now))::int using errcode = 'P0001', hint = 'cooldown';
  end if;
  if j.kind = 'cashout' then
    v_amt := coalesce(p_amount, y.dirty);
    if y.dirty <= 0 or v_amt <= 0 then
      raise exception 'Your yahoo balance is empty. Nothing to cash out.' using errcode = 'P0001', hint = 'nothing_to_cash';
    end if;
    if v_amt > y.dirty then
      raise exception 'You only have % in your yahoo balance.', bl_naira(y.dirty) using errcode = 'P0001', hint = 'too_much';
    end if;
    if v_amt < least(v_min, y.dirty) then
      raise exception 'Cash out at least %.', bl_naira(least(v_min, y.dirty)) using errcode = 'P0001', hint = 'too_small';
    end if;
  end if;

  v_secs := bl_yahoo_seconds(j, v_lap);
  v_pct := bl_yahoo_caught_pct(v_me.id, j, v_lap);
  v_until := v_now + make_interval(secs => v_secs);
  insert into yahoo_runs (user_id, job_id, laptop_item, location_id, place, started_at, resolve_at, caught_pct, pay_bonus_pct, amount)
  values (v_me.id, j.id, v_lap->>'item_id', v_me.location_id, v_where->>'place', v_now, v_until, v_pct,
          coalesce((v_lap->>'pay_bonus_pct')::numeric, 0), v_amt)
  returning id into v_id;
  -- can't be stopped halfway (busy_needs_from stays null, so activity_stop refuses)
  update profiles set busy_until = v_until, busy_started_at = v_now, busy_label = 'Yahoo: ' || j.name, busy_needs_from = null
   where id = v_me.id;
  return jsonb_build_object('run_id', v_id, 'busy_until', v_until, 'resolve_at', v_until, 'seconds', v_secs, 'job_id', j.id, 'name', j.name,
                            'caught_pct', v_pct, 'amount', v_amt,
                            'message', case when j.kind = 'cashout' then 'You call the "Western Union guy"… ' || bl_naira(v_amt) || ' on the way.'
                                            else j.name || '… laptop open, fingers dey move.' end);
end $$;
revoke all on function public.yahoo_job_start(text, bigint) from public, anon;
grant execute on function public.yahoo_job_start(text, bigint) to authenticated, service_role;

-- Roll my running job once its timer is over.
create or replace function public.yahoo_finish() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  r yahoo_runs;
begin
  perform bl_me_any();
  select * into r from yahoo_runs where user_id = v_uid and status = 'running' order by id desc limit 1;
  if not found then
    raise exception 'You are not doing any Yahoo job right now.' using errcode = 'P0001', hint = 'no_run';
  end if;
  if r.resolve_at > bl_now() then
    raise exception 'Hold on, about % sec more.', ceil(extract(epoch from r.resolve_at - bl_now()))::int using errcode = 'P0001', hint = 'not_yet';
  end if;
  return bl_yahoo_resolve(r.id);
end $$;
revoke all on function public.yahoo_finish() from public, anon;
grant execute on function public.yahoo_finish() to authenticated, service_role;

-- Admin: a player's Yahoo row + recent runs.
create or replace function public.admin_yahoo_player(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare y yahoo_players;
begin
  perform bl_admin_guard();
  select * into y from yahoo_players where user_id = p_user;
  return jsonb_build_object('player', to_jsonb(y), 'rank', bl_yahoo_rank(p_user), 'laptop', bl_yahoo_laptop(p_user),
    'runs', coalesce((select jsonb_agg(bl_yahoo_run_json(x) order by x.id desc)
                        from (select * from yahoo_runs where user_id = p_user order by id desc limit 30) x), '[]'::jsonb));
end $$;
revoke all on function public.admin_yahoo_player(uuid) from public, anon;
grant execute on function public.admin_yahoo_player(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 6. Existing functions (guarded edits of the live definitions)
-- ---------------------------------------------------------------------------------------------
-- bl_escape_pct_peek(): an EFCC case escapes against yahoo.escape_caught_pct (vanishing + bad luck still apply).
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.bl_escape_pct_peek(uuid)'::regprocedure) into v_def;
  if position('yahoo.escape_caught_pct' in v_def) > 0 then
    return;
  end if;
  create or replace function public.bl_escape_pct_peek(p_uid uuid) returns numeric
  language sql stable set search_path = public as $f$
    select greatest(0, least(100,
             least(case when exists (select 1 from jail_cases where user_id = p_uid and status = 'open' and kind = 'efcc')
                        then bl_shrine_num('yahoo.escape_caught_pct', 55)
                        else bl_shrine_num('crime.escape_caught_pct', 52) end,
                   coalesce(bl_charm_value(p_uid, 'vanishing'), 100))
             + coalesce(bl_charm_value(p_uid, 'bad_luck', 'caught_pts'), 0)));
  $f$;
end $$;
revoke all on function public.bl_escape_pct_peek(uuid) from public, anon, authenticated;

-- bl_crime_case_json(): the popup learns the case kind (EFCC copy) and what was taken.
do $$
declare v_def text; v_anchor text := '''id'', c.id, ''status'', c.status,';
begin
  select pg_get_functiondef('public.bl_crime_case_json(jail_cases)'::regprocedure) into v_def;
  if position('''kind''' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'Y1: bl_crime_case_json() changed; update the yahoo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor, '''id'', c.id, ''kind'', coalesce(c.kind, ''police''), ''meta'', coalesce(c.meta, ''{}''::jsonb), ''status'', c.status,');
  execute v_def;
end $$;
revoke all on function public.bl_crime_case_json(public.jail_cases) from public, anon, authenticated;

-- jail_case_bail(): EFCC receipts say EFCC.
do $$
declare v_def text; v_anchor text := '''Bail · Police HQ'', v_cost, ''Nigeria Police Force, Benin City''';
begin
  select pg_get_functiondef('public.jail_case_bail()'::regprocedure) into v_def;
  if position('EFCC' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'Y1: jail_case_bail() changed; update the yahoo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    'case when c.kind = ''efcc'' then ''Bail · EFCC'' else ''Bail · Police HQ'' end, v_cost, '
    || 'case when c.kind = ''efcc'' then ''EFCC zonal office, Benin City'' else ''Nigeria Police Force, Benin City'' end');
  execute v_def;
end $$;
revoke all on function public.jail_case_bail() from public, anon;
grant execute on function public.jail_case_bail() to authenticated, service_role;

-- bl_ledger_label(): Bank -> History lines.
do $$
declare v_def text; v_anchor text := '    when ''topup'' then';
begin
  select pg_get_functiondef('public.bl_ledger_label(text, jsonb)'::regprocedure) into v_def;
  if position('yahoo_cashout' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'Y1: bl_ledger_label() changed; update the yahoo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''yahoo_cashout'' then return ''Cash out'';' || chr(10)
    || '    when ''yahoo_pass'' then return ''Yahoo: '' || coalesce(nullif(p_meta->>''label'', ''''), ''pass'');' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

-- bl_admin_table_spec(): Admin -> Content -> Laptops (Yahoo), Yahoo jobs, Yahoo ranks.
do $$
declare v_def text; v_anchor text := '    when ''interaction_types'' then';
begin
  select pg_get_functiondef('public.bl_admin_table_spec(text)'::regprocedure) into v_def;
  if position('laptop_specs' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'Y1: bl_admin_table_spec() changed; update the yahoo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''laptop_specs'' then ''{"pk":["item_id"],"insert":true,"order":"sort, tier, item_id",' || chr(10)
    || '      "cols":{"label":"text","tier":"int","pay_bonus_pct":"num","efcc_minus_pts":"num","speed_pct":"num","sort":"int"}}''' || chr(10)
    || '    when ''yahoo_jobs'' then ''{"pk":["id"],"insert":true,"order":"sort, id",' || chr(10)
    || '      "cols":{"name":"text","icon":"text","blurb":"text","kind":"text","seconds":"int","pay_min":"money","pay_max":"money",' || chr(10)
    || '              "caught_pct":"num","cooldown_seconds":"int","min_tier":"int","sort":"int","active":"bool"}}''' || chr(10)
    || '    when ''yahoo_ranks'' then ''{"pk":["id"],"insert":true,"order":"min_earned, sort, id",' || chr(10)
    || '      "cols":{"name":"text","icon":"text","min_earned":"money","hype_pct":"num","perks":"text","sort":"int"}}''' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

-- bl_career_reqs(): "Own a laptop" (tech career) is met by any laptop in laptop_specs.
do $$
declare v_def text; v_anchor text := 'item_id = p_req->>''item'' and qty > 0';
begin
  select pg_get_functiondef('public.bl_career_reqs(profiles,jsonb,boolean)'::regprocedure) into v_def;
  if position('laptop_specs' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'Y1: bl_career_reqs() changed; update the yahoo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '(item_id = p_req->>''item'' or (p_req->>''item'' = ''laptop'' and item_id in (select ls.item_id from laptop_specs ls))) and qty > 0');
  execute v_def;
end $$;

-- bl_hype_announce(): Yahoo rank + status phone make the club hype bigger.
do $$
declare v_def text; v_anchor text := '  p_amount := bl_charm_hype_amount(p_user, p_amount);  -- B2 fame bath';
begin
  select pg_get_functiondef('public.bl_hype_announce(uuid,text,text,bigint,integer,boolean)'::regprocedure) into v_def;
  if position('bl_yahoo_hype_amount' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'Y1: bl_hype_announce() changed; update the yahoo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor, v_anchor || chr(10) || '  p_amount := bl_yahoo_hype_amount(p_user, p_amount);  -- Y1 yahoo rank + status phone');
  execute v_def;
end $$;

-- bl_hype_kind(): the Big Boys' VIP booth gets the VIP announcement.
do $$
declare v_def text; v_anchor text := 'when ''vip_table'' then ''vip''';
begin
  select pg_get_functiondef('public.bl_hype_kind(text)'::regprocedure) into v_def;
  if position('big_boy_booth' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'Y1: bl_hype_kind() changed; update the yahoo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor, v_anchor || chr(10) || '    when ''big_boy_booth'' then ''vip''');
  execute v_def;
end $$;

-- do_activity(): VIP booth activities need the Yahoo rank (yahoo.vip_rank).
do $$
declare v_def text; v_anchor text := '  -- L4: event-only cards';
begin
  select pg_get_functiondef('public.do_activity(text)'::regprocedure) into v_def;
  if position('bl_yahoo_assert_rank' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'Y1: do_activity() changed; update the yahoo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '  -- Y1: the Big Boys'' VIP booth needs the Yahoo rank' || chr(10)
    || '  if a.id = any (bl_yahoo_list(''yahoo.vip_activities'', ''big_boy_booth'')) then' || chr(10)
    || '    perform bl_yahoo_assert_rank(v_me.id, bl_yahoo_text(''yahoo.vip_rank'', ''big_boy''));' || chr(10)
    || '  end if;' || chr(10) || v_anchor);
  execute v_def;
end $$;

-- get_public_profile(): the Yahoo rank badge (null below G-boy).
do $$
declare v_def text; v_anchor text := '''created_at'', created_at)';
begin
  select pg_get_functiondef('public.get_public_profile(uuid)'::regprocedure) into v_def;
  if position('yahoo_rank' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'Y1: get_public_profile() changed; update the yahoo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor, '''created_at'', created_at, ''yahoo_rank'', bl_yahoo_rank_public(id))');
  execute v_def;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Places: the cybercafe desks, laptop cards, the Big Boys' VIP booth
-- ---------------------------------------------------------------------------------------------
insert into public.activities (id, name, scenes, home_only, cost, game_minutes, effects, night_only, sort, max_seconds, min_seconds, scale_by_need, needs_furniture, location_ids, risky, rush, icon)
values ('big_boy_booth', 'Big Boys'' VIP booth', '{club}', false, 250000, 90,
        '{"fun": 50, "social": 45, "stress": -22, "bladder": -15, "street_cred": 4}', false, 302, 15, 8, false, false, '{}', false, '{}', '🤑')
on conflict (id) do nothing;

insert into public.zone_actions (id, zone_id, kind, ref, label, icon, sort) values
  ('club.vip.big_boy_booth', 'club.vip', 'activity', 'big_boy_booth', null, null, 5),
  ('cyber.desks.laptop', 'cyber.desks', 'shop', 'laptop', null, null, 4),
  ('cyber.desks.thinkpad_t480', 'cyber.desks', 'shop', 'thinkpad_t480', null, null, 5),
  ('cyber.desks.elitebook_840', 'cyber.desks', 'shop', 'elitebook_840', null, null, 6)
on conflict (id) do nothing;

insert into public.place_moods (id, scene, location_id, part, icon, line, sort) values
  ('wifi_joint.yahoo1', null, 'wifi_joint', 'any', '💻', 'Back-row desks full of boys in face caps, typing fast', 11),
  ('wifi_joint.yahoo2', null, 'wifi_joint', 'night', '🌙', 'The cybercafe never sleeps. Desk na ₦5,000 a day', 12)
on conflict (id) do nothing;

-- the EFCC blindfold works now: drop its "coming soon" note (only while it still holds the B2 seed text)
update public.shrine_services set note = 'Works on Yahoo jobs: EFCC caught chance −15 points while it lasts.'
 where id = 'efcc_blindfold' and note like '%coming soon%';

notify pgrst, 'reload schema';
