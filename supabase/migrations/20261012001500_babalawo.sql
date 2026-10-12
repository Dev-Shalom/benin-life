-- B2 Babalawo shrine (docs/BABALAWO.md, owner-approved spec docs/LIFESTYLE_PLAN.md section 1).
-- * "Baba's Shrine" (babas_shrine): a new public place on the outskirts (Evbuomore, off Sakponba Rd past Upper Sakponba).
--   Baba is fictional and never named. The old in-town "Baba Osagie Shrine" (baba_shrine) is hidden once (active = false;
--   admin can switch it back on) so there is one shrine, and its name never shows on the map again.
-- * 9 offerings sold at Oba Market (items, category 'offering', plan prices = draft x 1.2): kola nut ... cow.
-- * shrine_services: the 10 services (admin-editable in Admin -> Content: price, offerings jsonb, effect value, duration,
--   uses, fail chance, seconds, lines). shrine_start(service) charges cash + consumes the offerings from the Bag, starts a
--   seconds-long action ("With Baba: ..."); shrine_finish() rolls the fail chance (shrine.fail_pct, default 10 %; per-service
--   override) and stores the charm in player_charms.
-- * Effects (server-side): protection -> bl_steal_caught_pct (thief), home guard -> bl_steal_caught_pct (victim, x1.5,
--   capped), vanishing -> jail_case_escape (uses), road opener + luck - bad luck -> work_shift pay, fame bath -> hype amount,
--   madness -> no shifts. Attraction / EFCC blindfold are stored for the coming dating / Yahoo life: bl_charm_value().
-- * Money charm (14 days): bl_money_charm_tick() pays shrine.money_payout_min..max into cash at most once per
--   shrine.money_payout_hours (on session start / status poll), a weekly demand (1 goat + N300,000) with a 24 h deadline,
--   and a backfire (half the cash, madness 1 game day, bad luck 3 days). Idempotent, row-locked, server-timed.
-- * Admin: admin_player_charms(), admin_charm_clear() (audited). Ledger labels "Baba: <service>".
-- Idempotent and safe on a non-empty DB: seeds use "on conflict do nothing" (admin edits survive a re-run), live
-- functions are patched from pg_get_functiondef with guarded replacements (create or replace keeps the grants).

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (category shrine)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('shrine.enabled', 'true', 'shrine', 'Babalawo shrine on',
 'B2: Baba''s Shrine sells charms. Off = the services are refused (charms already bought keep working).', 'bool', null, null),
('shrine.fail_pct', '10', 'shrine', 'Charm fails (chance)',
 'B2: chance a charm fails: the money and offerings are gone and Baba explains. A service with its own fail chance (Content -> Shrine services) uses that instead.', 'percent', 0, 100),
('shrine.money_payout_min', '150000', 'shrine', 'Money charm: smallest payout',
 'B2: the money charm pays a random amount between this and the biggest payout into cash.', 'naira', 0, 1000000000000),
('shrine.money_payout_max', '300000', 'shrine', 'Money charm: biggest payout',
 'B2: see the smallest payout.', 'naira', 0, 1000000000000),
('shrine.money_payout_hours', '8', 'shrine', 'Money charm: hours between payouts',
 'B2: the money charm pays at most once in this many real hours (checked when the player opens the game).', 'number', 1, 720),
('shrine.demand_days', '7', 'shrine', 'Money charm: days between Baba''s demands',
 'B2: every this many days Baba calls for his offering (goats + cash).', 'number', 1, 60),
('shrine.demand_cash', '300000', 'shrine', 'Money charm: demand cash',
 'B2: cash Baba asks for each week (paid from cash on hand).', 'naira', 0, 1000000000000),
('shrine.demand_goats', '1', 'shrine', 'Money charm: demand goats',
 'B2: goats Baba asks for each week (from the Bag).', 'number', 0, 100),
('shrine.demand_hours', '24', 'shrine', 'Money charm: hours to answer Baba',
 'B2: the demand must be paid within this many real hours of Baba calling, or the charm backfires.', 'number', 1, 720),
('shrine.backfire_cash_pct', '50', 'shrine', 'Backfire: share of cash lost',
 'B2: when the weekly demand is ignored the player loses this share of their cash on hand.', 'percent', 0, 100),
('shrine.madness_game_days', '1', 'shrine', 'Backfire: madness (game days)',
 'B2: "madness": no work shifts for this many game days (1 game day = 24 h on the real Benin clock).', 'number', 0, 30),
('shrine.bad_luck_days', '3', 'shrine', 'Backfire: bad luck (days)',
 'B2: bad luck after a backfire lasts this many real days.', 'number', 0, 60),
('shrine.bad_luck_caught_pts', '10', 'shrine', 'Bad luck: extra caught chance (points)',
 'B2: while bad luck lasts, pickpocket and escape caught chances are this many points higher.', 'number', 0, 100),
('shrine.bad_luck_pay_pct', '10', 'shrine', 'Bad luck: less job pay (%)',
 'B2: while bad luck lasts, job shifts pay this much less.', 'percent', 0, 100),
('shrine.guard_cap_pct', '95', 'shrine', 'Home guard: highest caught chance',
 'B2: the home guard makes thieves who target the holder more likely to be caught, never above this.', 'percent', 0, 100),
('shrine.old_hidden_seeded', 'false', 'shrine', 'Old shrine hidden (internal)',
 'B2: set once when the migration hid the old in-town shrine. Leave it alone.', 'bool', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. The place
-- ---------------------------------------------------------------------------------------------
insert into public.locations (id, name, district, scene, blurb, risk, night_risk_mult, cctv, keke_ok, congestion, remote_km, x, y, actions, sort, active) values
('babas_shrine', 'Baba''s Shrine', 'evbuomore', 'shrine',
 'Far end of Sakponba Road, where the tar finishes and the bush path starts. Mud walls, red and white cloth, firelight. Baba sees everybody wey come. Bring your offering.',
 .25, 1.8, false, true, 1.0, 0, 760, 730, '{babalawo,activities,chat}', 251, true)
on conflict (id) do nothing;

-- one shrine on the map: hide the old in-town one once (admin can switch it back on in Content -> Places) and drop the
-- personal name from it (Baba is never named)
update public.locations set name = 'Old Sakponba shrine',
       blurb = 'A small old shrine on the Sakponba side. Baba moved to the outskirts: find Baba''s Shrine past Upper Sakponba.'
 where id = 'baba_shrine' and name = 'Baba Osagie Shrine';
do $$
begin
  if not coalesce((select (value #>> '{}')::boolean from public.game_config where key = 'shrine.old_hidden_seeded'), false) then
    update public.locations set active = false where id = 'baba_shrine';
    update public.game_config set value = 'true' where key = 'shrine.old_hidden_seeded';
  end if;
end $$;

-- the old cheap "Consult Baba (divination)" activity stays at the old shrine only (Baba's consultation is a service here)
update public.activities set location_ids = '{baba_shrine}' where id = 'shrine_consult' and cardinality(location_ids) = 0;

-- zones (place zones replace the shrine type's zones with the same key)
insert into public.place_zones (id, scene, location_id, zone_key, label, icon, prop, x, z, w, d, rot, note, sort) values
('babas_shrine.hut',       null, 'babas_shrine', 'hut',       'Baba''s hut',   '🛖', 'shrine_hut',   3.0, 2.2, 4.0, 2.6, 0, 'Sit before Baba. Remove your shoes.', 1),
('babas_shrine.altar',     null, 'babas_shrine', 'altar',     'Charm altar',   '🪔', 'altar',        8.2, 2.0, 3.2, 2.0, 0, 'Cash and offerings go on the altar. Offerings come from Oba Market.', 2),
('babas_shrine.fire',      null, 'babas_shrine', 'fire',      'Fire pit',      '🔥', 'fire_pit',     6.0, 5.4, 2.0, 2.0, 0, null, 3),
('babas_shrine.courtyard', null, 'babas_shrine', 'courtyard', 'Offering mat',  '🧺', 'offering_mat', 2.4, 5.8, 2.6, 1.8, 0, 'Kola, schnapps, white cloth, animals: buy them at Oba Market.', 4)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. Offerings (Oba Market)
-- ---------------------------------------------------------------------------------------------
insert into public.items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort) values
('kola_nut',         'Kola nut',          'offering', 240,     'Offering for Baba''s shrine. Kola na the first thing wey Baba go ask for.', '{}', '{oba_market}', true, 50, '🌰', 900),
('alligator_pepper', 'Alligator pepper',  'offering', 600,     'Offering for Baba''s shrine. Hot seeds for a sweet tongue.', '{}', '{oba_market}', true, 50, '🌶️', 901),
('cowries',          'Cowries',           'offering', 2400,    'Offering for Baba''s shrine. A string of white cowrie shells.', '{}', '{oba_market}', true, 50, '🐚', 902),
('white_cloth',      'White cloth',       'offering', 3600,    'Offering for Baba''s shrine. Clean white cloth, two yards.', '{}', '{oba_market}', true, 50, '🏳️', 903),
('palm_oil',         'Palm oil',          'offering', 4200,    'Offering for Baba''s shrine. A bottle of red palm oil.', '{}', '{oba_market}', true, 50, '🫙', 904),
('schnapps',         'Schnapps',          'offering', 7800,    'Offering for Baba''s shrine. Baba pours some for the ancestors first.', '{}', '{oba_market}', true, 50, '🍾', 905),
('white_chicken',    'White chicken',     'offering', 9600,    'Offering for Baba''s shrine. A live white chicken in a basket.', '{}', '{oba_market}', true, 50, '🐓', 906),
('goat',             'Goat',              'offering', 102000,  'Offering for Baba''s shrine. A healthy he-goat on a rope.', '{}', '{oba_market}', true, 50, '🐐', 907),
('cow',              'Cow',               'offering', 1440000, 'Offering for Baba''s shrine. A full cow. Na big man offering be this.', '{}', '{oba_market}', true, 50, '🐄', 908)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.shrine_services (
  id                text primary key,
  name              text not null,
  icon              text not null default '🪔',
  blurb             text not null default '',
  note              text not null default '',          -- extra line under the card (e.g. "works with ... (coming)")
  price             bigint not null default 0 check (price >= 0),
  offerings         jsonb not null default '{}'::jsonb check (jsonb_typeof(offerings) = 'object'),  -- {"kola_nut": 2}
  effect_kind       text not null,                     -- the player_charms.kind it stores (or consultation / cleansing)
  effect_value      numeric not null default 0,        -- see docs/BABALAWO.md (units per kind)
  duration_seconds  int check (duration_seconds is null or duration_seconds > 0),   -- null = no time limit / instant
  uses              int check (uses is null or uses > 0),                           -- null = no use limit
  fail_pct          numeric check (fail_pct is null or (fail_pct >= 0 and fail_pct <= 100)), -- null = shrine.fail_pct
  seconds           int not null default 12 check (seconds between 1 and 600),       -- how long the action takes
  baba_line         text not null default '',          -- what Baba says when it works
  fail_line         text not null default '',          -- what Baba says when it fails
  lines             text not null default '',          -- consultation: the readings, one per line
  sort              int not null default 0,
  active            boolean not null default true
);

insert into public.shrine_services (id, name, icon, blurb, note, price, offerings, effect_kind, effect_value, duration_seconds, uses, fail_pct, seconds, baba_line, fail_line, lines, sort) values
('consultation', 'Consultation (Ifá reading)', '🔮', 'Baba casts the opele and reads your road. Small luck follows you for a day.', '',
 50000, '{"kola_nut": 1}', 'luck', 5, 86400, null, 0, 10,
 'The opele don talk. Go well, my child.', 'The spirits are quiet today. Come back another time.',
 E'Baba squints at the opele: "Money dey your front, but e dey shy. Chase am small small."\n'
 'Baba laughs: "Somebody dey talk your name for good place. Your matter go soon settle."\n'
 'Baba taps the tray twice: "Avoid long throat this week. Wetin be your own go come."\n'
 'Baba nods slowly: "Your feet go carry you go new place. Go with clean heart."\n'
 'Baba points at the kola: "Two people go help you this month. One of them, you never meet."\n'
 'Baba says: "Your star dey shine, but dust dey on top. Wash am with hard work."\n'
 'Baba hums: "Rain no dey fall on one roof. Your own turn dey come."\n'
 'Baba smiles: "The road is open small. Walk am before e close."',
 1),
('road_opener', 'Road opener', '🛣️', 'Baba clears the bush from your road. Your work pays better for a week.', '',
 250000, '{"kola_nut": 2, "palm_oil": 1}', 'road_opener', 20, 604800, null, null, 12,
 'Your road don open. Go work, money go follow.', 'The road is still blocked. Baba no fit force am today. Your offering don go.', '', 2),
('protection', 'Protection charm', '🛡️', 'A small leather charm for your pocket. Police no go see your hand quick.', '',
 420000, '{"schnapps": 1, "white_chicken": 1}', 'protection', 45, 259200, null, null, 12,
 'Tie am for your waist. Dem no go easily catch you.', 'The charm no gree hold. E don spoil before e start. Na so e dey happen sometimes.', '', 3),
('vanishing', 'Vanishing charm', '💨', 'Smoke for your legs. When you run from police, you fit vanish.', '',
 750000, '{"goat": 2, "cowries": 1}', 'vanishing', 30, null, 3, null, 15,
 'If dem hold you, just run. Smoke go cover you. E get three times inside.', 'The smoke scatter for air. The charm no take. Baba don chop the goat sha.', '', 4),
('home_guard', 'Home guard', '🏠', 'Baba guards your back. Anybody wey try pick your pocket go fall for police hand.', '',
 300000, '{"white_cloth": 1, "palm_oil": 1}', 'home_guard', 50, 604800, null, null, 12,
 'Anybody wey touch your pocket, police go hold am.', 'The guard no stand. Your offering don go to the ancestors anyway.', '', 5),
('attraction', 'Attraction charm', '💘', 'Sweet mouth and fine face. People go dey look you twice.', 'Works with the dating life (coming soon). Baba keeps it ready on you till then.',
 150000, '{"alligator_pepper": 5}', 'attraction', 20, 432000, null, null, 10,
 'Your face don sweet. Dem go dey smile when you pass.', 'The pepper too hot. The charm no catch. Try again another day.', '', 6),
('fame_bath', 'Fame bath', '✨', 'A herbal bath with schnapps. When you spend for club, the MC go shout your name louder.', '',
 800000, '{"schnapps": 2}', 'fame_bath', 50, 259200, null, null, 15,
 'Go club. The whole Benin go hear your name.', 'The water no hold the fame. Na so e be sometimes. Your money don go.', '', 7),
('efcc_blindfold', 'EFCC blindfold', '🙈', 'A cloth over the eyes of those who look for you.', 'Works with the Yahoo life (coming soon). Baba keeps it ready on you till then.',
 1200000, '{"goat": 2}', 'efcc_blindfold', 15, 259200, null, null, 15,
 'Dem go look you, dem no go see you.', 'The cloth tear. The charm no work. The goats don already enter pot.', '', 8),
('money_charm', 'Money charm', '💰', 'Money go dey find you every time you come back. But Baba go call you every week: no forget am.', 'Baba calls every week for a goat and ₦300,000. Ignore am and e go backfire.',
 3000000, '{"cow": 2, "schnapps": 1, "white_cloth": 1}', 'money_charm', 0, 1209600, null, null, 20,
 'Money go dey find you. But when I call you, answer me o.', 'The spirits reject am today. The cows don go. No vex, na so e dey.', '', 9),
('cleansing', 'Cleansing', '🕊️', 'Baba washes away curses and bad luck with a white chicken.', '',
 50000, '{"white_chicken": 1}', 'cleansing', 0, null, null, 0, 10,
 'You don wash clean. Go in peace.', 'The water no reach. Come back.', '', 10)
on conflict (id) do nothing;

alter table public.shrine_services enable row level security;
revoke all on table public.shrine_services from public, anon, authenticated;
grant select on table public.shrine_services to authenticated;
drop policy if exists shrine_services_read on public.shrine_services;
create policy shrine_services_read on public.shrine_services for select to authenticated using (true);

create table if not exists public.player_charms (
  id          bigserial primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  kind        text not null,                -- protection, vanishing, home_guard, road_opener, fame_bath, attraction,
                                            -- efcc_blindfold, luck, money_charm, madness, bad_luck, curse
  service_id  text,
  status      text not null default 'active' check (status in ('active', 'used', 'expired', 'cleared', 'backfired')),
  expires_at  timestamptz,                  -- null = no time limit (uses only)
  uses_left   int check (uses_left is null or uses_left >= 0),
  data        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  ended_at    timestamptz
);
create index if not exists player_charms_user_idx on public.player_charms (user_id, status, kind);
create unique index if not exists player_charms_one_money_uidx on public.player_charms (user_id) where kind = 'money_charm' and status = 'active';

create table if not exists public.shrine_visits (
  id           bigserial primary key,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  service_id   text not null,
  started_at   timestamptz not null,
  resolve_at   timestamptz not null,
  status       text not null default 'running' check (status in ('running', 'done', 'failed')),
  paid         bigint not null default 0,
  offerings    jsonb not null default '{}'::jsonb,
  fail_pct     numeric not null default 0,
  charm_id     bigint references public.player_charms(id) on delete set null,
  line         text,
  resolved_at  timestamptz
);
create index if not exists shrine_visits_user_idx on public.shrine_visits (user_id, id desc);
create unique index if not exists shrine_visits_one_running_uidx on public.shrine_visits (user_id) where status = 'running';
create index if not exists shrine_visits_charm_idx on public.shrine_visits (charm_id) where charm_id is not null;

create table if not exists public.shrine_notices (
  id          bigserial primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  kind        text not null check (kind in ('blessing', 'backfire', 'demand_paid', 'charm_failed', 'charm_ok')),
  title       text not null,
  body        text not null default '',
  amount      bigint not null default 0,
  created_at  timestamptz not null default now(),
  seen_at     timestamptz
);
create index if not exists shrine_notices_user_idx on public.shrine_notices (user_id, id desc) where seen_at is null;

alter table public.player_charms enable row level security;
alter table public.shrine_visits enable row level security;
alter table public.shrine_notices enable row level security;
revoke all on table public.player_charms from public, anon, authenticated;
revoke all on table public.shrine_visits from public, anon, authenticated;
revoke all on table public.shrine_notices from public, anon, authenticated;
revoke all on sequence public.player_charms_id_seq from public, anon, authenticated;
revoke all on sequence public.shrine_visits_id_seq from public, anon, authenticated;
revoke all on sequence public.shrine_notices_id_seq from public, anon, authenticated;
-- players read their own charms (no writes); visits / notices go through the RPCs only
grant select on table public.player_charms to authenticated;
drop policy if exists player_charms_own on public.player_charms;
create policy player_charms_own on public.player_charms for select to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------
-- 5. Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_shrine_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

-- Is this charm row in force right now?
create or replace function public.bl_charm_live(c public.player_charms) returns boolean
language sql stable set search_path = public as $$
  select c.id is not null and c.status = 'active'
     and (c.expires_at is null or c.expires_at > bl_now())
     and (c.uses_left is null or c.uses_left > 0);
$$;

-- The value of a player's active charm of this kind (the strongest one), or null when they have none.
-- Later features read their charm through this: bl_charm_value(uid, 'attraction'), bl_charm_value(uid, 'efcc_blindfold').
-- p_key picks another number in the charm's data (bad_luck: caught_pts, pay_pct).
create or replace function public.bl_charm_value(p_uid uuid, p_kind text, p_key text default 'value') returns numeric
language sql stable set search_path = public as $$
  select max((c.data ->> coalesce(p_key, 'value'))::numeric)
    from player_charms c
   where c.user_id = p_uid and c.kind = p_kind and c.status = 'active'
     and (c.expires_at is null or c.expires_at > bl_now())
     and (c.uses_left is null or c.uses_left > 0)
     and jsonb_typeof(c.data -> coalesce(p_key, 'value')) = 'number';
$$;

create or replace function public.bl_charm_active(p_uid uuid, p_kind text) returns boolean
language sql stable set search_path = public as $$
  select exists (select 1 from player_charms c
                  where c.user_id = p_uid and c.kind = p_kind and c.status = 'active'
                    and (c.expires_at is null or c.expires_at > bl_now())
                    and (c.uses_left is null or c.uses_left > 0));
$$;

-- Job pay with charms: road opener (+%), Baba's luck (+%), bad luck (-%). Rounded to N10 like work_shift.
create or replace function public.bl_charm_pay(p_uid uuid, p_pay bigint) returns bigint
language sql stable set search_path = public as $$
  select greatest(0, (round(coalesce(p_pay, 0) * greatest(0, 1
           + coalesce(bl_charm_value(p_uid, 'road_opener'), 0) / 100.0
           + coalesce(bl_charm_value(p_uid, 'luck'), 0) / 100.0
           - coalesce(bl_charm_value(p_uid, 'bad_luck', 'pay_pct'), 0) / 100.0) / 10.0) * 10))::bigint;
$$;

-- Club hype amount with a fame bath (+%).
create or replace function public.bl_charm_hype_amount(p_uid uuid, p_amount bigint) returns bigint
language sql stable set search_path = public as $$
  select case when bl_charm_value(p_uid, 'fame_bath') is null then p_amount
              else round(coalesce(p_amount, 0) * (1 + bl_charm_value(p_uid, 'fame_bath') / 100.0))::bigint end;
$$;

-- "Madness": no work shifts while it lasts.
create or replace function public.bl_charm_assert_can_work(p_uid uuid) returns void
language plpgsql stable set search_path = public as $$
declare v_until timestamptz;
begin
  select max(expires_at) into v_until from player_charms
   where user_id = p_uid and kind = 'madness' and status = 'active' and expires_at > bl_now();
  if v_until is not null then
    raise exception 'Baba''s madness is on you. You can''t work a shift for about % more hours. A cleansing at Baba''s Shrine can wash it off.',
      greatest(1, ceil(extract(epoch from v_until - bl_now()) / 3600))::int using errcode = 'P0001', hint = 'madness';
  end if;
end $$;

-- Escape caught chance with charms, without using anything up (for the popup).
create or replace function public.bl_escape_pct_peek(p_uid uuid) returns numeric
language sql stable set search_path = public as $$
  select greatest(0, least(100,
           least(bl_shrine_num('crime.escape_caught_pct', 52),
                 coalesce(bl_charm_value(p_uid, 'vanishing'), 100))
           + coalesce(bl_charm_value(p_uid, 'bad_luck', 'caught_pts'), 0)));
$$;

-- Escape caught chance for a real attempt: uses one vanishing charm use when one is active.
create or replace function public.bl_escape_pct_use(p_uid uuid) returns numeric
language plpgsql set search_path = public as $$
declare
  v_pct numeric := bl_escape_pct_peek(p_uid);
  c player_charms;
begin
  select * into c from player_charms
   where user_id = p_uid and kind = 'vanishing' and status = 'active'
     and (expires_at is null or expires_at > bl_now()) and (uses_left is null or uses_left > 0)
   order by (data->>'value')::numeric nulls last, id
   limit 1 for update;
  if found and c.uses_left is not null then
    update player_charms set uses_left = uses_left - 1,
           status = case when uses_left - 1 <= 0 then 'used' else status end,
           ended_at = case when uses_left - 1 <= 0 then bl_now() else ended_at end
     where id = c.id;
  end if;
  return v_pct;
end $$;

-- One game day in real seconds (24 h on the real Benin clock; shorter on an accelerated clock).
create or replace function public.bl_shrine_game_day_seconds() returns numeric
language sql stable set search_path = public as $$
  select case when coalesce(bl_cfg_text('clock.mode'), 'real') = 'real' then 86400
              else 86400 / greatest(1, coalesce(bl_cfg('clock.game_minutes_per_real_minute'), 12)) end;
$$;

-- What a service does, in words (cards and receipts).
create or replace function public.bl_shrine_effect_text(s public.shrine_services) returns text
language sql stable set search_path = public as $$
  select case s.effect_kind
    when 'luck' then 'Reveals your luck · +' || trim_scale(s.effect_value) || '% job pay'
    when 'road_opener' then '+' || trim_scale(s.effect_value) || '% job pay'
    when 'protection' then 'Pickpocket caught chance ' || trim_scale(bl_shrine_num('crime.steal_caught_pct', 62)) || '% → '
                           || trim_scale(least(s.effect_value, bl_shrine_num('crime.steal_caught_pct', 62))) || '%'
    when 'vanishing' then 'Escape caught chance ' || trim_scale(bl_shrine_num('crime.escape_caught_pct', 52)) || '% → '
                          || trim_scale(least(s.effect_value, bl_shrine_num('crime.escape_caught_pct', 52))) || '%'
    when 'home_guard' then 'Thieves who target you +' || trim_scale(s.effect_value) || '% more likely caught'
    when 'attraction' then 'Dates say yes more often (+' || trim_scale(s.effect_value) || '%)'
    when 'fame_bath' then '+' || trim_scale(s.effect_value) || '% club hype'
    when 'efcc_blindfold' then 'Yahoo EFCC caught chance −' || trim_scale(s.effect_value) || ' points'
    when 'money_charm' then 'Cash each time you come back after ' || trim_scale(bl_shrine_num('shrine.money_payout_hours', 8)) || '+ h ('
                            || bl_naira(bl_shrine_num('shrine.money_payout_min', 150000)) || '–' || bl_naira(bl_shrine_num('shrine.money_payout_max', 300000)) || ')'
    when 'cleansing' then 'Removes curses, bad luck and madness'
    else s.blurb end;
$$;

create or replace function public.bl_shrine_duration_text(s public.shrine_services) returns text
language sql immutable set search_path = public as $$
  select case
    when s.effect_kind = 'cleansing' then 'Instant'
    when s.uses is not null and s.duration_seconds is null then 'Next ' || s.uses || ' escape' || case when s.uses = 1 then '' else 's' end
    when s.duration_seconds is null then 'Until used'
    when s.duration_seconds % 86400 = 0 then (s.duration_seconds / 86400) || ' day' || case when s.duration_seconds = 86400 then '' else 's' end
    when s.duration_seconds % 3600 = 0 then (s.duration_seconds / 3600) || ' h'
    else ceil(s.duration_seconds / 60.0) || ' min' end;
$$;

create or replace function public.bl_shrine_charm_json(c public.player_charms) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'kind', c.kind, 'service_id', c.service_id, 'status', c.status, 'expires_at', c.expires_at,
    'uses_left', c.uses_left, 'created_at', c.created_at, 'value', c.data->'value',
    'name', coalesce((select name from shrine_services where id = c.service_id),
                     case c.kind when 'madness' then 'Madness' when 'bad_luck' then 'Bad luck' when 'curse' then 'Curse'
                                 when 'luck' then 'Baba''s luck' else initcap(replace(c.kind, '_', ' ')) end),
    'icon', coalesce((select icon from shrine_services where id = c.service_id),
                     case c.kind when 'madness' then '😵‍💫' when 'bad_luck' then '🐈‍⬛' when 'curse' then '🌑' else '📿' end),
    'debuff', c.kind in ('madness', 'bad_luck', 'curse'),
    'effect', case c.kind
      when 'madness' then 'No work shifts'
      when 'bad_luck' then '+' || coalesce(c.data->>'caught_pts', '10') || ' pts caught chance · −' || coalesce(c.data->>'pay_pct', '10') || '% job pay'
      when 'curse' then 'Bad things follow you'
      else (select bl_shrine_effect_text(s) from shrine_services s where s.id = c.service_id) end,
    'demand', case when c.kind = 'money_charm' then jsonb_build_object(
      'due_at', c.data->>'demand_due_at', 'open', coalesce((c.data->>'demand_open')::boolean, false),
      'deadline', c.data->>'demand_deadline', 'ignored', coalesce((c.data->>'demand_ignored')::boolean, false),
      'cash', bl_shrine_num('shrine.demand_cash', 300000), 'goats', bl_shrine_num('shrine.demand_goats', 1),
      'next_payout_at', c.data->>'next_payout_at', 'payouts', coalesce((c.data->>'payouts')::int, 0)) end);
$$;

create or replace function public.bl_shrine_notice(p_uid uuid, p_kind text, p_title text, p_body text, p_amount bigint default 0) returns void
language sql set search_path = public as $$
  insert into shrine_notices (user_id, kind, title, body, amount, created_at) values (p_uid, p_kind, p_title, coalesce(p_body, ''), coalesce(p_amount, 0), bl_now());
$$;

-- Missing offerings for a service: [{item, name, icon, need, have}] (empty = all there).
create or replace function public.bl_shrine_missing(p_uid uuid, p_offerings jsonb) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('item', o.key, 'name', coalesce(it.name, o.key), 'icon', it.icon,
                                               'need', (o.value #>> '{}')::int, 'have', coalesce(i.qty, 0))
                            order by it.sort, o.key), '[]'::jsonb)
    from jsonb_each(coalesce(p_offerings, '{}'::jsonb)) o
    left join items it on it.id = o.key
    left join inventory i on i.user_id = p_uid and i.item_id = o.key
   where (o.value #>> '{}')::int > 0 and coalesce(i.qty, 0) < (o.value #>> '{}')::int;
$$;

-- The money charm clock: weekly demand, backfire, payout. Locks the charm row; safe to call any number of times.
create or replace function public.bl_money_charm_tick(p_uid uuid) returns jsonb
language plpgsql set search_path = public as $$
declare
  c          player_charms;
  v_now      timestamptz := bl_now();
  d          jsonb;
  v_due      timestamptz;
  v_deadline timestamptz;
  v_hours    numeric := greatest(1, bl_shrine_num('shrine.money_payout_hours', 8));
  v_last     timestamptz;
  v_min      bigint := greatest(0, bl_shrine_num('shrine.money_payout_min', 150000))::bigint;
  v_max      bigint := greatest(0, bl_shrine_num('shrine.money_payout_max', 300000))::bigint;
  v_amt      bigint;
  v_cash     bigint;
  v_loss     bigint := 0;
  v_out      jsonb := '{}'::jsonb;
begin
  select * into c from player_charms where user_id = p_uid and kind = 'money_charm' and status = 'active' for update;
  if not found then return v_out; end if;
  d := c.data;
  v_due := (d->>'demand_due_at')::timestamptz;
  v_deadline := (d->>'demand_deadline')::timestamptz;

  -- a) Baba calls: the weekly demand opens (only inside the charm's 14 days)
  if not coalesce((d->>'demand_open')::boolean, false) and v_due is not null and v_due <= v_now
     and (c.expires_at is null or v_due < c.expires_at) then
    v_deadline := v_due + make_interval(secs => (greatest(1, bl_shrine_num('shrine.demand_hours', 24)) * 3600)::double precision);
    d := d || jsonb_build_object('demand_open', true, 'demand_deadline', v_deadline, 'demand_ignored', false);
    perform bl_event(p_uid, 'baba_calling', 'Baba is calling you',
                     'Baba wants ' || trim_scale(bl_shrine_num('shrine.demand_goats', 1)) || ' goat and ' || bl_naira(bl_shrine_num('shrine.demand_cash', 300000))
                     || ' before ' || to_char(v_deadline at time zone 'Africa/Lagos', 'Dy FMHH12:MI AM') || '.', jsonb_build_object('charm_id', c.id));
    v_out := v_out || jsonb_build_object('demand_opened', true);
  end if;

  -- b) the demand was not answered in time: backfire
  if coalesce((d->>'demand_open')::boolean, false) and v_deadline is not null and v_deadline <= v_now then
    select cash into v_cash from profiles where id = p_uid for update;
    v_loss := floor(coalesce(v_cash, 0) * greatest(0, least(100, bl_shrine_num('shrine.backfire_cash_pct', 50))) / 100.0)::bigint;
    if v_loss > 0 then
      perform bl_add_money(p_uid, 'cash', -v_loss, 'shrine_backfire', jsonb_build_object('charm_id', c.id, 'service', 'money_charm'));
    end if;
    update player_charms set status = 'backfired', ended_at = v_now,
           data = d || jsonb_build_object('demand_open', false, 'backfired_at', v_now, 'backfire_loss', v_loss)
     where id = c.id;
    if bl_shrine_num('shrine.madness_game_days', 1) > 0 then
      insert into player_charms (user_id, kind, service_id, expires_at, data, created_at)
      values (p_uid, 'madness', null,
              v_now + make_interval(secs => (bl_shrine_num('shrine.madness_game_days', 1) * bl_shrine_game_day_seconds())::double precision),
              jsonb_build_object('value', 1, 'from_charm', c.id), v_now);
    end if;
    if bl_shrine_num('shrine.bad_luck_days', 3) > 0 then
      insert into player_charms (user_id, kind, service_id, expires_at, data, created_at)
      values (p_uid, 'bad_luck', null,
              v_now + make_interval(secs => (bl_shrine_num('shrine.bad_luck_days', 3) * 86400)::double precision),
              jsonb_build_object('value', 1, 'caught_pts', bl_shrine_num('shrine.bad_luck_caught_pts', 10),
                                 'pay_pct', bl_shrine_num('shrine.bad_luck_pay_pct', 10), 'from_charm', c.id), v_now);
    end if;
    perform bl_shrine_notice(p_uid, 'backfire', 'Baba''s charm don backfire!',
      'You ignored Baba''s call. ' || case when v_loss > 0 then bl_naira(v_loss) || ' of your cash vanished, ' else '' end
      || 'madness has caught you (no work for a game day) and bad luck follows you for '
      || trim_scale(bl_shrine_num('shrine.bad_luck_days', 3)) || ' days. A cleansing at the shrine can wash it.', v_loss);
    perform bl_event(p_uid, 'baba_backfire', 'Baba''s charm don backfire!', 'You lost ' || bl_naira(v_loss) || ' and madness don catch you.',
                     jsonb_build_object('loss', v_loss));
    return v_out || jsonb_build_object('backfire', true, 'loss', v_loss);
  end if;

  -- c) the charm's time is over (and no demand waits): it ends quietly
  if c.expires_at is not null and c.expires_at <= v_now and not coalesce((d->>'demand_open')::boolean, false) then
    update player_charms set status = 'expired', ended_at = v_now, data = d where id = c.id;
    return v_out || jsonb_build_object('expired', true);
  end if;

  -- d) payout: at most once per shrine.money_payout_hours, never while Baba's call is unanswered
  v_last := coalesce((d->>'last_payout_at')::timestamptz, c.created_at);
  if not coalesce((d->>'demand_open')::boolean, false) and (c.expires_at is null or c.expires_at > v_now)
     and v_last + make_interval(secs => (v_hours * 3600)::double precision) <= v_now then
    v_amt := v_min + floor(bl_rand() * (greatest(v_max, v_min) - v_min + 1))::bigint;
    v_amt := least(greatest(v_min, (round(v_amt / 1000.0) * 1000)::bigint), greatest(v_max, v_min));
    if v_amt > 0 then
      perform bl_add_money(p_uid, 'cash', v_amt, 'shrine_blessing', jsonb_build_object('charm_id', c.id));
      perform bl_shrine_notice(p_uid, 'blessing', 'Baba''s blessing',
        'While you were away, money found its way to your pocket: +' || bl_naira(v_amt) || '.', v_amt);
    end if;
    d := d || jsonb_build_object('last_payout_at', v_now, 'payouts', coalesce((d->>'payouts')::int, 0) + 1,
                                 'next_payout_at', v_now + make_interval(secs => (v_hours * 3600)::double precision));
    v_out := v_out || jsonb_build_object('payout', v_amt);
  end if;

  update player_charms set data = d where id = c.id;
  return v_out;
end $$;

-- Resolve one running shrine visit (the server roll). Locks the visit.
create or replace function public.bl_shrine_resolve(p_id bigint) returns jsonb
language plpgsql set search_path = public as $$
declare
  v       shrine_visits;
  s       shrine_services;
  v_now   timestamptz := bl_now();
  v_line  text;
  v_read  text;
  v_cid   bigint;
  v_n     int := 0;
  v_lines text[];
  v_hours numeric := greatest(1, bl_shrine_num('shrine.money_payout_hours', 8));
  v_ok    boolean := false;
begin
  select * into v from shrine_visits where id = p_id for update;
  if not found then return jsonb_build_object('status', 'none'); end if;
  if v.status <> 'running' then
    return jsonb_build_object('status', v.status, 'already', true, 'line', v.line, 'service_id', v.service_id);
  end if;
  select * into s from shrine_services where id = v.service_id;

  if bl_rand() * 100 < v.fail_pct then
    v_line := coalesce(nullif(s.fail_line, ''), 'The spirits said no today. Your offering don go.');
    update shrine_visits set status = 'failed', line = v_line, resolved_at = v_now where id = v.id;
    perform bl_shrine_notice(v.user_id, 'charm_failed', coalesce(s.name, 'The charm') || ' failed', v_line, v.paid);
  else
    v_ok := true;
    v_line := coalesce(nullif(s.baba_line, ''), 'It is done.');
    if s.effect_kind = 'cleansing' then
      update player_charms set status = 'cleared', ended_at = v_now
       where user_id = v.user_id and kind in ('madness', 'bad_luck', 'curse') and status = 'active';
      get diagnostics v_n = row_count;
      v_line := v_line || case when v_n > 0 then ' ' || v_n || ' bad thing' || case when v_n = 1 then '' else 's' end || ' washed away.'
                               else ' Nothing bad was on you, but clean body no bad.' end;
    else
      if s.effect_kind = 'luck' then
        v_lines := array(select btrim(x) from regexp_split_to_table(coalesce(s.lines, ''), E'\n') x where btrim(x) <> '');
        if coalesce(array_length(v_lines, 1), 0) > 0 then
          v_read := v_lines[1 + floor(bl_rand() * array_length(v_lines, 1))::int];
        end if;
      end if;
      insert into player_charms (user_id, kind, service_id, expires_at, uses_left, data, created_at)
      values (v.user_id, s.effect_kind, s.id,
              case when s.duration_seconds is not null then v_now + make_interval(secs => s.duration_seconds) end,
              s.uses,
              jsonb_build_object('value', s.effect_value)
              || case when s.effect_kind = 'money_charm' then jsonb_build_object(
                   'last_payout_at', v_now,
                   'next_payout_at', v_now + make_interval(secs => (v_hours * 3600)::double precision),
                   'payouts', 0,
                   'demand_due_at', v_now + make_interval(secs => (greatest(1, bl_shrine_num('shrine.demand_days', 7)) * 86400)::double precision),
                   'demand_open', false) else '{}'::jsonb end
              || case when v_read is not null then jsonb_build_object('reading', v_read) else '{}'::jsonb end,
              v_now)
      returning id into v_cid;
    end if;
    update shrine_visits set status = 'done', line = coalesce(v_read || ' ', '') || v_line, charm_id = v_cid, resolved_at = v_now where id = v.id;
  end if;
  update profiles set busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
   where id = v.user_id and busy_label like 'With Baba:%';
  return jsonb_build_object('status', case when v_ok then 'done' else 'failed' end,
    'service_id', v.service_id, 'name', s.name, 'icon', s.icon, 'line', v_line, 'reading', v_read, 'paid', v.paid,
    'charm', (select bl_shrine_charm_json(c) from player_charms c where c.id = v_cid));
end $$;

revoke all on function public.bl_shrine_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_charm_live(public.player_charms) from public, anon, authenticated;
revoke all on function public.bl_charm_value(uuid, text, text) from public, anon, authenticated;
revoke all on function public.bl_charm_active(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_charm_pay(uuid, bigint) from public, anon, authenticated;
revoke all on function public.bl_charm_hype_amount(uuid, bigint) from public, anon, authenticated;
revoke all on function public.bl_charm_assert_can_work(uuid) from public, anon, authenticated;
revoke all on function public.bl_escape_pct_peek(uuid) from public, anon, authenticated;
revoke all on function public.bl_escape_pct_use(uuid) from public, anon, authenticated;
revoke all on function public.bl_shrine_game_day_seconds() from public, anon, authenticated;
revoke all on function public.bl_shrine_effect_text(public.shrine_services) from public, anon, authenticated;
revoke all on function public.bl_shrine_duration_text(public.shrine_services) from public, anon, authenticated;
revoke all on function public.bl_shrine_charm_json(public.player_charms) from public, anon, authenticated;
revoke all on function public.bl_shrine_notice(uuid, text, text, text, bigint) from public, anon, authenticated;
revoke all on function public.bl_shrine_missing(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.bl_money_charm_tick(uuid) from public, anon, authenticated;
revoke all on function public.bl_shrine_resolve(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 6. Player RPCs
-- ---------------------------------------------------------------------------------------------
-- Everything the shrine tab needs: services (price, offerings with what I have, effect, duration, my active charm of
-- that kind), my charms, the running visit, the offering items and the money charm's demand.
create or replace function public.shrine_info() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me_any();
  v_fail numeric := greatest(0, least(100, bl_shrine_num('shrine.fail_pct', 10)));
  r shrine_visits;
begin
  perform bl_money_charm_tick(v_me.id);
  select * into r from shrine_visits where user_id = v_me.id and status = 'running';
  return jsonb_build_object(
    'enabled', coalesce(bl_cfg_bool('shrine.enabled'), true),
    'fail_pct', v_fail,
    'cash', (select cash from profiles where id = v_me.id),
    'here', exists (select 1 from locations l where l.id = v_me.location_id and 'babalawo' = any (l.actions) and coalesce(l.active, true)),
    'services', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'name', s.name, 'icon', s.icon, 'blurb', s.blurb, 'note', s.note, 'price', s.price,
               'kind', s.effect_kind, 'value', s.effect_value, 'uses', s.uses, 'seconds', s.seconds,
               'fail_pct', coalesce(s.fail_pct, v_fail),
               'effect', bl_shrine_effect_text(s), 'duration', bl_shrine_duration_text(s),
               'offerings', coalesce((
                 select jsonb_agg(jsonb_build_object('item', o.key, 'name', coalesce(it.name, o.key), 'icon', it.icon,
                                                     'price', it.price, 'need', (o.value #>> '{}')::int, 'have', coalesce(i.qty, 0))
                                  order by it.sort, o.key)
                   from jsonb_each(s.offerings) o left join items it on it.id = o.key
                   left join inventory i on i.user_id = v_me.id and i.item_id = o.key
                  where (o.value #>> '{}')::int > 0), '[]'::jsonb),
               'active', (select bl_shrine_charm_json(c) from player_charms c
                           where c.user_id = v_me.id and c.kind = s.effect_kind and c.status = 'active'
                             and s.effect_kind not in ('cleansing')
                             and (c.kind = 'money_charm' or ((c.expires_at is null or c.expires_at > bl_now()) and (c.uses_left is null or c.uses_left > 0)))
                           order by c.id desc limit 1))
             order by s.sort, s.id)
        from shrine_services s where s.active), '[]'::jsonb),
    'charms', coalesce((
      select jsonb_agg(bl_shrine_charm_json(c) order by c.expires_at nulls last, c.id)
        from player_charms c
       where c.user_id = v_me.id and c.status = 'active'
         and (c.kind = 'money_charm' or ((c.expires_at is null or c.expires_at > bl_now()) and (c.uses_left is null or c.uses_left > 0)))), '[]'::jsonb),
    'visit', case when r.id is not null then jsonb_build_object('id', r.id, 'service_id', r.service_id, 'resolve_at', r.resolve_at,
                                                                  'name', (select name from shrine_services where id = r.service_id)) end);
end $$;
revoke all on function public.shrine_info() from public, anon;
grant execute on function public.shrine_info() to authenticated, service_role;

-- Start a service: at the shrine, free, enough cash, every offering in the Bag. Cash and offerings are taken now;
-- the roll comes at the end of the timer (shrine_finish).
create or replace function public.shrine_start(p_service text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me     profiles := bl_me();
  s        shrine_services;
  l        locations;
  v_now    timestamptz := bl_now();
  v_miss   jsonb;
  v_until  timestamptz;
  v_id     bigint;
  v_rcpt   jsonb;
  o        record;
  v_left   numeric;
begin
  if not coalesce(bl_cfg_bool('shrine.enabled'), true) then
    raise exception 'Baba is not receiving visitors right now. Come back later.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into s from shrine_services where id = p_service and active;
  if not found then
    raise exception 'Baba does not do that one.' using errcode = 'P0001', hint = 'bad_service';
  end if;
  perform 1 from profiles where id = v_me.id for update;
  v_me := bl_me();
  perform bl_assert_free(v_me);
  l := bl_location(v_me.location_id);
  if v_me.home_visit_host_id is not null or not ('babalawo' = any (l.actions)) then
    raise exception 'Go to Baba''s Shrine first. It is at the far end of Sakponba Road.' using errcode = 'P0001', hint = 'not_here';
  end if;
  perform bl_assert_place_open(l);
  perform bl_money_charm_tick(v_me.id);
  if exists (select 1 from shrine_visits where user_id = v_me.id and status = 'running') then
    raise exception 'Baba is still working on your last request.' using errcode = 'P0001', hint = 'busy';
  end if;
  -- one of each charm at a time (only one money charm, even while its weekly call is open)
  if s.effect_kind = 'money_charm' and exists (select 1 from player_charms where user_id = v_me.id and kind = 'money_charm' and status = 'active') then
    raise exception 'You already carry a money charm. Baba gives only one.' using errcode = 'P0001', hint = 'already_active';
  end if;
  if s.effect_kind not in ('cleansing', 'money_charm') and bl_charm_active(v_me.id, s.effect_kind) then
    select ceil(extract(epoch from min(expires_at) - v_now) / 3600) into v_left from player_charms
     where user_id = v_me.id and kind = s.effect_kind and status = 'active';
    raise exception 'Your % is still working%. Come back when it finishes.', s.name,
      case when v_left is not null then ' (about ' || greatest(1, v_left)::int || ' h left)' else '' end
      using errcode = 'P0001', hint = 'already_active';
  end if;
  v_miss := bl_shrine_missing(v_me.id, s.offerings);
  if jsonb_array_length(v_miss) > 0 then
    raise exception 'Baba needs % for this. Buy them at Oba Market.',
      (select string_agg(((x->>'need')::int - (x->>'have')::int) || ' more ' || lower(x->>'name'), ', ') from jsonb_array_elements(v_miss) x)
      using errcode = 'P0001', hint = 'missing_offerings';
  end if;
  if s.price > v_me.cash then
    raise exception 'Baba collects % in cash for %. You have % on you.', bl_naira(s.price), s.name, bl_naira(v_me.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;

  if s.price > 0 then
    perform bl_add_money(v_me.id, 'cash', -s.price, 'shrine', jsonb_build_object('service', s.id, 'service_name', s.name, 'location', l.id));
  end if;
  for o in select key, (value #>> '{}')::int as n from jsonb_each(s.offerings) where (value #>> '{}')::int > 0 loop
    perform bl_give_item(v_me.id, o.key, -o.n);
  end loop;
  v_until := bl_set_busy_seconds(v_me.id, greatest(1, s.seconds), 'With Baba: ' || s.name);
  insert into shrine_visits (user_id, service_id, started_at, resolve_at, paid, offerings, fail_pct)
  values (v_me.id, s.id, v_now, v_until, s.price, s.offerings,
          greatest(0, least(100, coalesce(s.fail_pct, bl_shrine_num('shrine.fail_pct', 10)))))
  returning id into v_id;
  v_rcpt := bl_receipt_issue(v_me.id, 'shrine', 'Baba: ' || s.name, s.price, l.name,
                             jsonb_build_object('service', s.id, 'offerings', s.offerings, 'visit_id', v_id));
  return coalesce(v_rcpt, '{}'::jsonb) || jsonb_build_object(
    'visit_id', v_id, 'busy_until', v_until, 'seconds', s.seconds, 'service_id', s.id, 'name', s.name, 'paid', s.price,
    'message', 'Baba takes your offering and starts to chant…');
end $$;
revoke all on function public.shrine_start(text) from public, anon;
grant execute on function public.shrine_start(text) to authenticated, service_role;

-- Roll my running shrine visit once its timer is over.
create or replace function public.shrine_finish() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v shrine_visits;
begin
  perform bl_me_any();
  select * into v from shrine_visits where user_id = v_uid and status = 'running' order by id desc limit 1;
  if not found then
    raise exception 'Baba is not working on anything for you.' using errcode = 'P0001', hint = 'no_visit';
  end if;
  if v.resolve_at > bl_now() then
    raise exception 'Baba is still chanting. About % sec more.', ceil(extract(epoch from v.resolve_at - bl_now()))
      using errcode = 'P0001', hint = 'not_yet';
  end if;
  return bl_shrine_resolve(v.id);
end $$;
revoke all on function public.shrine_finish() from public, anon;
grant execute on function public.shrine_finish() to authenticated, service_role;

-- My shrine state for the whole game (session start + a slow poll): finishes a due visit, runs the money charm clock,
-- and returns my charms, unseen notices (blessing / backfire popups) and Baba's open call.
create or replace function public.shrine_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v      shrine_visits;
  v_res  jsonb;
  v_tick jsonb;
  m      player_charms;
begin
  if not exists (select 1 from profiles where id = v_uid) then
    return jsonb_build_object('charms', '[]'::jsonb, 'notices', '[]'::jsonb, 'demand', null, 'visit', null);
  end if;
  select * into v from shrine_visits where user_id = v_uid and status = 'running' order by id desc limit 1;
  if found and v.resolve_at <= bl_now() then
    v_res := bl_shrine_resolve(v.id);
    v := null;
  end if;
  v_tick := bl_money_charm_tick(v_uid);
  select * into m from player_charms where user_id = v_uid and kind = 'money_charm' and status = 'active';
  return jsonb_build_object(
    'resolved', v_res,
    'tick', v_tick,
    'visit', case when v.id is not null then jsonb_build_object('id', v.id, 'service_id', v.service_id, 'resolve_at', v.resolve_at) end,
    'charms', coalesce((
      select jsonb_agg(bl_shrine_charm_json(c) order by c.expires_at nulls last, c.id)
        from player_charms c
       where c.user_id = v_uid and c.status = 'active'
         and (c.kind = 'money_charm' or ((c.expires_at is null or c.expires_at > bl_now()) and (c.uses_left is null or c.uses_left > 0)))), '[]'::jsonb),
    'notices', coalesce((
      select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'title', n.title, 'body', n.body, 'amount', n.amount,
                                          'created_at', n.created_at) order by n.id)
        from (select * from shrine_notices where user_id = v_uid and seen_at is null and kind in ('blessing', 'backfire')
               order by id desc limit 10) n), '[]'::jsonb),
    'demand', case when m.id is not null and coalesce((m.data->>'demand_open')::boolean, false) then jsonb_build_object(
      'charm_id', m.id, 'deadline', m.data->>'demand_deadline', 'ignored', coalesce((m.data->>'demand_ignored')::boolean, false),
      'cash', bl_shrine_num('shrine.demand_cash', 300000), 'goats', bl_shrine_num('shrine.demand_goats', 1),
      'have_goats', coalesce((select qty from inventory where user_id = v_uid and item_id = 'goat'), 0),
      'have_cash', (select cash from profiles where id = v_uid)) end);
end $$;
revoke all on function public.shrine_status() from public, anon;
grant execute on function public.shrine_status() to authenticated, service_role;

create or replace function public.shrine_notice_seen(p_ids bigint[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_n int;
begin
  update shrine_notices set seen_at = bl_now() where user_id = v_uid and id = any (coalesce(p_ids, '{}')) and seen_at is null;
  get diagnostics v_n = row_count;
  return jsonb_build_object('seen', v_n);
end $$;
revoke all on function public.shrine_notice_seen(bigint[]) from public, anon;
grant execute on function public.shrine_notice_seen(bigint[]) to authenticated, service_role;

-- Answer Baba's weekly call: goats from the Bag + cash. Works from anywhere (the popup).
create or replace function public.shrine_demand_pay() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me_any();
  m       player_charms;
  v_cash  bigint := greatest(0, bl_shrine_num('shrine.demand_cash', 300000))::bigint;
  v_goats int := greatest(0, bl_shrine_num('shrine.demand_goats', 1))::int;
  v_have  int;
  v_now   timestamptz := bl_now();
  v_next  timestamptz;
begin
  perform 1 from profiles where id = v_me.id for update;
  perform bl_money_charm_tick(v_me.id);
  select * into m from player_charms where user_id = v_me.id and kind = 'money_charm' and status = 'active' for update;
  if not found or not coalesce((m.data->>'demand_open')::boolean, false) then
    raise exception 'Baba is not calling you right now.' using errcode = 'P0001', hint = 'no_demand';
  end if;
  select coalesce(qty, 0) into v_have from inventory where user_id = v_me.id and item_id = 'goat';
  if coalesce(v_have, 0) < v_goats then
    raise exception 'Baba wants % goat%. You have %. Buy one at Oba Market, quick.', v_goats, case when v_goats = 1 then '' else 's' end, coalesce(v_have, 0)
      using errcode = 'P0001', hint = 'missing_offerings';
  end if;
  if (select cash from profiles where id = v_me.id) < v_cash then
    raise exception 'Baba wants % in cash. You have % on you.', bl_naira(v_cash), bl_naira((select cash from profiles where id = v_me.id))
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  if v_cash > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_cash, 'shrine', jsonb_build_object('service', 'money_charm_demand', 'service_name', 'weekly demand', 'charm_id', m.id));
  end if;
  if v_goats > 0 then
    perform bl_give_item(v_me.id, 'goat', -v_goats);
  end if;
  v_next := (m.data->>'demand_due_at')::timestamptz + make_interval(secs => (greatest(1, bl_shrine_num('shrine.demand_days', 7)) * 86400)::double precision);
  if v_next <= v_now then
    v_next := v_now + make_interval(secs => (greatest(1, bl_shrine_num('shrine.demand_days', 7)) * 86400)::double precision);
  end if;
  update player_charms set
    data = data || jsonb_build_object('demand_open', false, 'demand_ignored', false, 'demand_deadline', null,
                                      'demand_due_at', v_next, 'demands_paid', coalesce((data->>'demands_paid')::int, 0) + 1),
    status = case when expires_at is not null and expires_at <= v_now then 'expired' else status end,
    ended_at = case when expires_at is not null and expires_at <= v_now then v_now else ended_at end
   where id = m.id;
  perform bl_shrine_notice(v_me.id, 'demand_paid', 'Baba is satisfied', 'Baba collected his goat and cash. The money charm continues.', v_cash);
  return jsonb_build_object('message', 'Baba is satisfied. The money go continue to find you.', 'paid', v_cash, 'goats', v_goats,
                            'next_due_at', v_next);
end $$;
revoke all on function public.shrine_demand_pay() from public, anon;
grant execute on function public.shrine_demand_pay() to authenticated, service_role;

-- Ignore Baba's call (the popup stops coming back; the deadline still runs and the charm backfires when it passes).
create or replace function public.shrine_demand_ignore() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me_any(); m player_charms;
begin
  select * into m from player_charms where user_id = v_me.id and kind = 'money_charm' and status = 'active' for update;
  if not found or not coalesce((m.data->>'demand_open')::boolean, false) then
    raise exception 'Baba is not calling you right now.' using errcode = 'P0001', hint = 'no_demand';
  end if;
  update player_charms set data = data || jsonb_build_object('demand_ignored', true) where id = m.id;
  return jsonb_build_object('message', 'You ignored Baba. He no go forget.', 'deadline', m.data->>'demand_deadline');
end $$;
revoke all on function public.shrine_demand_ignore() from public, anon;
grant execute on function public.shrine_demand_ignore() to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 7. Admin RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_player_charms(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(bl_shrine_charm_json(c) || jsonb_build_object('data', c.data, 'ended_at', c.ended_at,
                     'live', bl_charm_live(c) or (c.kind = 'money_charm' and c.status = 'active')) order by c.id desc)
      from (select * from player_charms where user_id = p_user order by id desc limit 50) c), '[]'::jsonb));
end $$;
revoke all on function public.admin_player_charms(uuid) from public, anon;
grant execute on function public.admin_player_charms(uuid) to authenticated, service_role;

-- Clear one charm (p_charm) or all of a player's active charms (null). Audited.
create or replace function public.admin_charm_clear(p_user uuid, p_charm bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_n int;
begin
  update player_charms set status = 'cleared', ended_at = bl_now()
   where user_id = p_user and status = 'active' and (p_charm is null or id = p_charm);
  get diagnostics v_n = row_count;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'charm_clear', p_user, jsonb_build_object('charm_id', p_charm, 'cleared', v_n));
  return jsonb_build_object('cleared', v_n, 'message', case when v_n = 0 then 'Nothing to clear.' else v_n || ' charm(s) cleared.' end);
end $$;
revoke all on function public.admin_charm_clear(uuid, bigint) from public, anon;
grant execute on function public.admin_charm_clear(uuid, bigint) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 8. Existing functions (guarded edits of the live definitions)
-- ---------------------------------------------------------------------------------------------
-- bl_steal_caught_pct(): protection (thief) caps the base, bad luck (thief) adds points, the skill hook stays,
-- home guard (victim) multiplies (relative +%, capped at shrine.guard_cap_pct, never lowers it).
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.bl_steal_caught_pct(uuid,uuid,numeric)'::regprocedure) into v_def;
  if position('bl_charm_value' in v_def) > 0 then
    return;
  end if;
  create or replace function public.bl_steal_caught_pct(p_thief uuid, p_victim uuid, p_skill_mod numeric default 0) returns numeric
  language sql stable set search_path = public as $f$
    with b as (
      select greatest(0, least(100,
               least(bl_crime_num('crime.steal_caught_pct', 62), coalesce(bl_charm_value(p_thief, 'protection'), 100))
               + coalesce(bl_charm_value(p_thief, 'bad_luck', 'caught_pts'), 0)
               - coalesce(p_skill_mod, 0))) as pct,
             bl_charm_value(p_victim, 'home_guard') as guard,
             greatest(0, least(100, bl_crime_num('shrine.guard_cap_pct', 95))) as cap)
    select case when b.guard is null or b.pct >= b.cap then b.pct
                else least(b.cap, b.pct * (1 + b.guard / 100.0)) end
      from b;
  $f$;
end $$;
revoke all on function public.bl_steal_caught_pct(uuid, uuid, numeric) from public, anon, authenticated;

-- jail_case_escape(): the escape roll uses (and spends) a vanishing charm.
do $$
declare v_def text; v_anchor text := 'if bl_crime_roll(bl_crime_num(''crime.escape_caught_pct'', 52)) then';
begin
  select pg_get_functiondef('public.jail_case_escape()'::regprocedure) into v_def;
  if position('bl_escape_pct_use' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'B2: jail_case_escape() changed; update the babalawo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor, 'if bl_crime_roll(bl_escape_pct_use(v_me.id)) then');
  execute v_def;
end $$;
revoke all on function public.jail_case_escape() from public, anon;
grant execute on function public.jail_case_escape() to authenticated, service_role;

-- bl_crime_case_json(): the popup shows the escape chance with the player's charms.
do $$
declare v_def text; v_anchor text := '''escape_caught_pct'', bl_crime_num(''crime.escape_caught_pct'', 52),';
begin
  select pg_get_functiondef('public.bl_crime_case_json(jail_cases)'::regprocedure) into v_def;
  if position('bl_escape_pct_peek' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'B2: bl_crime_case_json() changed; update the babalawo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor, '''escape_caught_pct'', bl_escape_pct_peek(c.user_id),');
  execute v_def;
end $$;
revoke all on function public.bl_crime_case_json(public.jail_cases) from public, anon, authenticated;

-- work_shift(): madness blocks shifts; road opener / luck / bad luck change the pay.
do $$
declare
  v_def text;
  a1 text := '  if v_me.job_id is null then';
  a2 text := '  v_xp := round(cl.xp_per_shift';
begin
  select pg_get_functiondef('public.work_shift()'::regprocedure) into v_def;
  if position('bl_charm_pay' in v_def) > 0 then
    return;
  end if;
  if position(a1 in v_def) = 0 or position(a2 in v_def) = 0 then
    raise exception 'B2: work_shift() changed; update the babalawo migration anchors.';
  end if;
  v_def := replace(v_def, a1, '  perform bl_charm_assert_can_work(v_me.id);' || chr(10) || a1);
  v_def := replace(v_def, a2, '  v_pay := bl_charm_pay(v_me.id, v_pay);  -- B2 charms' || chr(10) || a2);
  execute v_def;
end $$;
revoke all on function public.work_shift() from public, anon;
grant execute on function public.work_shift() to authenticated, service_role;

-- bl_hype_announce(): a fame bath makes the club hype amount bigger.
do $$
declare v_def text; v_anchor text := '  select username into v_name from profiles where id = p_user;';
begin
  select pg_get_functiondef('public.bl_hype_announce(uuid,text,text,bigint,integer,boolean)'::regprocedure) into v_def;
  if position('bl_charm_hype_amount' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'B2: bl_hype_announce() changed; update the babalawo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor, '  p_amount := bl_charm_hype_amount(p_user, p_amount);  -- B2 fame bath' || chr(10) || v_anchor);
  execute v_def;
end $$;

-- zone_actions: a new card kind 'shrine' (ref = shrine_services.id).
do $$
declare v_con text;
begin
  select pg_get_constraintdef(oid) into v_con from pg_constraint
   where conrelid = 'public.zone_actions'::regclass and conname = 'zone_actions_kind_check';
  if v_con is null or position('shrine' in v_con) = 0 then
    alter table public.zone_actions drop constraint if exists zone_actions_kind_check;
    alter table public.zone_actions add constraint zone_actions_kind_check
      check (kind in ('activity', 'job', 'shop', 'panel', 'shrine'));
  end if;
end $$;

-- bl_zone_action_check(): shrine cards point at a service; zone cards may also open the Babalawo tab.
do $$
declare
  v_def text;
  a1 text := '(''shop'', ''jobs'', ''bank'', ''pos'', ''activities'', ''chat'', ''inventory'')';
  a2 text := '  elsif new.kind = ''panel''';
begin
  select pg_get_functiondef('public.bl_zone_action_check()'::regprocedure) into v_def;
  if position('shrine_services' in v_def) > 0 then
    return;
  end if;
  if position(a1 in v_def) = 0 or position(a2 in v_def) = 0 then
    raise exception 'B2: bl_zone_action_check() changed; update the babalawo migration anchors.';
  end if;
  v_def := replace(v_def, a1, '(''shop'', ''jobs'', ''bank'', ''pos'', ''activities'', ''chat'', ''inventory'', ''babalawo'')');
  v_def := replace(v_def, '(shop, jobs, bank, pos, activities, chat, inventory)', '(shop, jobs, bank, pos, activities, chat, inventory, babalawo)');
  v_def := replace(v_def, a2,
    '  elsif new.kind = ''shrine'' and not exists (select 1 from shrine_services where id = new.ref) then' || chr(10)
    || '    raise exception ''Zone action %: no shrine service "%".'', new.id, new.ref using errcode = ''P0001'', hint = ''bad_value'';' || chr(10)
    || a2);
  execute v_def;
end $$;

-- place_interior(): shrine service cards (price, seconds, effect, duration, offerings missing, my charm of that kind).
do $$
declare v_def text; v_anchor text := '               -- open a tab of the place sheet (bank counter, PoS, the whole shop...)';
begin
  select pg_get_functiondef('public.place_interior(text)'::regprocedure) into v_def;
  if position('shrine_services' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'B2: place_interior() changed; update the babalawo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
'               -- B2 shrine services at Baba''s Shrine
               select za.sort, s.sort, jsonb_build_object(
                        ''id'', za.id, ''kind'', ''shrine'', ''ref'', s.id,
                        ''name'', coalesce(za.label, s.name), ''icon'', coalesce(za.icon, s.icon),
                        ''cost'', s.price, ''seconds'', s.seconds, ''effect'', bl_shrine_effect_text(s),
                        ''duration'', bl_shrine_duration_text(s), ''offerings'', s.offerings, ''note'', nullif(s.note, ''''),
                        ''missing'', bl_shrine_missing(v_uid, s.offerings),
                        ''charm_until'', (select max(coalesce(c.expires_at, ''infinity''::timestamptz)) from player_charms c
                                          where c.user_id = v_uid and c.kind = s.effect_kind and c.status = ''active''
                                            and s.effect_kind <> ''cleansing''
                                            and (c.expires_at is null or c.expires_at > bl_now() or c.kind = ''money_charm'')
                                            and (c.uses_left is null or c.uses_left > 0)),
                        ''locked'', case when not v_open then v_closed_for else null end)
                 from zone_actions za join shrine_services s on s.id = za.ref
                where za.zone_id = z.id and za.kind = ''shrine'' and za.active and s.active
               union all
' || v_anchor);
  execute v_def;
end $$;

-- bl_ledger_label(): Bank -> History lines.
do $$
declare v_def text; v_anchor text := '    when ''topup'' then';
begin
  select pg_get_functiondef('public.bl_ledger_label(text, jsonb)'::regprocedure) into v_def;
  if position('shrine_blessing' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'B2: bl_ledger_label() changed; update the babalawo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''shrine'' then return ''Baba: '' || coalesce(nullif(p_meta->>''service_name'', ''''), ''offering'');' || chr(10)
    || '    when ''shrine_blessing'' then return ''Baba''''s blessing'';' || chr(10)
    || '    when ''shrine_backfire'' then return ''Baba: charm backfired'';' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

-- bl_admin_table_spec(): Admin -> Content -> Shrine services.
do $$
declare v_def text; v_anchor text := '    when ''interaction_types'' then';
begin
  select pg_get_functiondef('public.bl_admin_table_spec(text)'::regprocedure) into v_def;
  if position('shrine_services' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'B2: bl_admin_table_spec() changed; update the babalawo migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''shrine_services'' then ''{"pk":["id"],"insert":true,"order":"sort, id",' || chr(10)
    || '      "cols":{"name":"text","icon":"text","blurb":"text","note":"text","price":"money","offerings":"obj","effect_kind":"text",' || chr(10)
    || '              "effect_value":"num","duration_seconds":"int_null","uses":"int_null","fail_pct":"num_null","seconds":"int",' || chr(10)
    || '              "baba_line":"text","fail_line":"text","lines":"text","sort":"int","active":"bool"}}''' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. Zone cards, mood lines, Baba (after the trigger allows the babalawo tab)
-- ---------------------------------------------------------------------------------------------
insert into public.zone_actions (id, zone_id, kind, ref, label, icon, sort) values
  ('babas_shrine.hut.consultation',    'babas_shrine.hut',       'shrine', 'consultation',   null, null, 1),
  ('babas_shrine.hut.cleansing',       'babas_shrine.hut',       'shrine', 'cleansing',      null, null, 2),
  ('babas_shrine.hut.charms',          'babas_shrine.hut',       'panel',  'babalawo',       'My charms & all services', '📿', 3),
  ('babas_shrine.altar.road_opener',   'babas_shrine.altar',     'shrine', 'road_opener',    null, null, 1),
  ('babas_shrine.altar.protection',    'babas_shrine.altar',     'shrine', 'protection',     null, null, 2),
  ('babas_shrine.altar.vanishing',     'babas_shrine.altar',     'shrine', 'vanishing',      null, null, 3),
  ('babas_shrine.altar.home_guard',    'babas_shrine.altar',     'shrine', 'home_guard',     null, null, 4),
  ('babas_shrine.altar.attraction',    'babas_shrine.altar',     'shrine', 'attraction',     null, null, 5),
  ('babas_shrine.altar.fame_bath',     'babas_shrine.altar',     'shrine', 'fame_bath',      null, null, 6),
  ('babas_shrine.altar.efcc_blindfold','babas_shrine.altar',     'shrine', 'efcc_blindfold', null, null, 7),
  ('babas_shrine.altar.money_charm',   'babas_shrine.altar',     'shrine', 'money_charm',    null, null, 8),
  ('babas_shrine.fire.quiet',          'babas_shrine.fire',      'activity', 'shrine_quiet', 'Sit quietly by the fire', '🔥', 1),
  ('babas_shrine.courtyard.bag',       'babas_shrine.courtyard', 'panel',  'inventory',      'Check your offerings', '🧺', 1)
on conflict (id) do nothing;

insert into public.place_moods (id, scene, location_id, part, icon, line, sort) values
  ('babas_shrine.1', null, 'babas_shrine', 'any',     '🔥', 'The fire pops softly. Somebody is chanting low inside the hut', 1),
  ('babas_shrine.2', null, 'babas_shrine', 'any',     '🐚', 'Cowries click on Baba''s tray', 2),
  ('babas_shrine.3', null, 'babas_shrine', 'night',   '🌙', 'Firelight dances on the red and white cloth', 3),
  ('babas_shrine.4', null, 'babas_shrine', 'morning', '🐓', 'A white chicken scratches near the offering mat', 4)
on conflict (id) do nothing;

insert into public.npc_roster (id, name, role, motion, avatar, lines, pidgin, scenes, location_ids, zone_key, headliner, sort) values
  ('baba_babalawo', 'Baba', 'Babalawo', 'sit',
   '{"v": 2, "top": {"c": "#f3f0e8"}, "hair": "bald", "skin": "tone5", "gender": "male", "preset": "bini"}',
   E'Sit down, my child. Wetin dey worry you?\nBring your offering. The spirits no dey chop promise.\nWhen I call you, answer me o.',
   '', '{}', '{babas_shrine}', 'hut', true, 249),
  ('baba_apprentice', 'Omo Baba', 'Baba''s helper', 'work',
   '{"v": 2, "top": {"c": "#d2342a"}, "hair": "low_cut", "skin": "tone4", "gender": "male", "preset": "bini"}',
   E'Baba dey inside. Remove your shoe.\nOfferings dey sell for Oba Market. Kola, schnapps, goat.',
   '', '{}', '{babas_shrine}', 'fire', false, 252)
on conflict (id) do nothing;

notify pgrst, 'reload schema';
