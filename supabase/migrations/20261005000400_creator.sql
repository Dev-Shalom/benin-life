-- =====================================================================
-- Benin Life — creator data: traits, dreams, starter homes, two-step creation, rent,
-- origin overrides, copy pass                                    (owner: R3a)
-- Reference: docs/CREATOR.md.  Idempotent: safe to re-run (seeds use on conflict do nothing,
-- copy fixes are explicit updates, functions are create or replace).
--
-- * traits (pick exactly creator.trait_count = 2 per Sim): data-driven effects jsonb. The
--   need-decay multipliers ("decay": {"hunger": 1.2}) are applied inside bl_decay_row now; the
--   other keys (skill_xp, *_bonus, ...) are stored for Phase 2.
-- * dreams: a lifetime goal per Sim; goal jsonb is stored, progress tracking is Phase 2.
-- * start_homes: where a new Sim lives, weekly rent, each origin's start cash, which origins may
--   pick it (+ the joke shown when locked).
-- * create_profile_v2 -> profile in a "no home yet" state (at creator.arrival_location, cash 0);
--   choose_start_home pays the starter pack. Gameplay RPCs refuse with hint 'no_home' until then.
--   create_profile (v1) keeps its all-in-one behaviour.
-- * Rent: profiles.weekly_rent / rent_due_at / rent_owed. Charged lazily in bl_me() when
--   rent.enabled is true (default false until Phase 2 jobs exist; while off the due date just
--   rolls forward, so turning it on never back-charges).
-- * origin.force_next: one-shot origin for the next created profile (seeded 'nepo' once).
-- * admin_set_origin(p_user, p_origin, p_apply_perks) + admin_audit.
-- * Copy: "Dad" instead of "Papa"; moderate Pidgin in seed text and player-facing errors.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Two new home locations (positions consistent with docs/MAP_GEO.md, >= 34 units from pins)
-- ---------------------------------------------------------------------
insert into public.locations (id, name, district, scene, x, y, risk, night_risk_mult, cctv, keke_ok, congestion, remote_km, actions, sort, blurb) values
('uniben_hostel', 'UNIBEN Hostel (Ugbowo)', 'ugbowo', 'home_face_me', 522, 140, .20, 1.6, true, true, 1.0, 0, '{housing,activities}', 145,
 'A bunk in a UNIBEN hall: four roommates, one reading lamp, and noodles cooked on a stove you are not supposed to have.'),
('uselu_selfcon', 'Uselu Self-Contain', 'uselu', 'home_flat', 420, 228, .30, 1.8, false, true, 1.0, 0, '{housing,activities}', 115,
 'Your own room, toilet and kitchen corner off Lagos Road. Not big, but it is all yours.')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. Data tables
-- ---------------------------------------------------------------------
create table if not exists public.traits (
  id          text primary key check (id ~ '^[a-z0-9_]{2,32}$'),
  name        text not null,
  emoji       text not null default '',
  description text not null default '',
  -- e.g. {"decay": {"hunger": 1.2}, "skill_xp": {"cooking": 1.25}, "night_fun_bonus": 5}
  effects     jsonb not null default '{}'::jsonb check (jsonb_typeof(effects) = 'object'),
  sort        int not null default 0,
  active      boolean not null default true
);

create table if not exists public.dreams (
  id          text primary key check (id ~ '^[a-z0-9_]{2,32}$'),
  name        text not null,
  emoji       text not null default '',
  description text not null default '',
  -- e.g. {"type":"career_top"}, {"type":"net_worth","amount":5000000}, {"type":"skill","skill":"music","level":10}
  goal        jsonb not null default '{}'::jsonb check (jsonb_typeof(goal) = 'object'),
  sort        int not null default 0,
  active      boolean not null default true
);

create table if not exists public.start_homes (
  id              text primary key check (id ~ '^[a-z0-9_]{2,32}$'),
  name            text not null,
  emoji           text not null default '',
  location_id     text not null references public.locations(id) on update cascade,
  district        text not null default '',          -- display label, e.g. 'Ugbowo'
  tag             text not null default '',          -- 'Student life' | 'Hard start' | 'Balanced' | 'Big spender'
  description     text not null default '',
  weekly_rent     bigint not null default 0 check (weekly_rent >= 0),
  -- cash in hand per origin, e.g. {"lapo": 8000, "nepo": 80000}; a missing origin falls back to origin.<tier>.start_cash
  start_cash      jsonb not null default '{}'::jsonb check (jsonb_typeof(start_cash) = 'object'),
  allowed_origins text[] not null default '{}',     -- empty = every origin may pick it
  locked_quip     text not null default '',          -- shown when the player's origin cannot pick it
  housing_id      text not null,
  sort            int not null default 0,
  active          boolean not null default true
);

-- small audit trail for admin actions on players (config edits keep using config_audit)
create table if not exists public.admin_audit (
  id          bigserial primary key,
  admin_id    uuid references public.profiles(id) on delete set null,
  action      text not null,
  target_user uuid references public.profiles(id) on delete set null,
  data        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists admin_audit_target_idx on public.admin_audit (target_user, created_at desc);

alter table public.traits      enable row level security;
alter table public.dreams      enable row level security;
alter table public.start_homes enable row level security;
alter table public.admin_audit enable row level security;
revoke all on table public.traits, public.dreams, public.start_homes, public.admin_audit from anon, authenticated;
revoke all on sequence public.admin_audit_id_seq from anon, authenticated;
grant select on public.traits, public.dreams, public.start_homes to anon, authenticated;
grant select on public.admin_audit to authenticated;

drop policy if exists traits_read on public.traits;
create policy traits_read on public.traits for select to anon, authenticated using (true);
drop policy if exists dreams_read on public.dreams;
create policy dreams_read on public.dreams for select to anon, authenticated using (true);
drop policy if exists start_homes_read on public.start_homes;
create policy start_homes_read on public.start_homes for select to anon, authenticated using (true);
drop policy if exists admin_audit_admin on public.admin_audit;
create policy admin_audit_admin on public.admin_audit for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin));

-- ---------------------------------------------------------------------
-- 3. profiles columns
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists traits      text[] not null default '{}';
alter table public.profiles add column if not exists dream       text references public.dreams(id) on update cascade;
alter table public.profiles add column if not exists start_home  text references public.start_homes(id) on update cascade;
-- true for every v1 / pre-existing profile; create_profile_v2 inserts false until choose_start_home
alter table public.profiles add column if not exists home_chosen boolean not null default true;
alter table public.profiles add column if not exists weekly_rent bigint not null default 0 check (weekly_rent >= 0);
alter table public.profiles add column if not exists rent_due_at timestamptz;
alter table public.profiles add column if not exists rent_owed   bigint not null default 0 check (rent_owed >= 0);

-- ---------------------------------------------------------------------
-- 4. Seeds
-- ---------------------------------------------------------------------
insert into public.traits (id, name, emoji, description, effects, sort) values
('hustler', 'Hustler', '💼',
 'Can turn ₦500 into ₦5,000 by Friday. Hustle skill grows faster and pay comes a little easier.',
 '{"skill_xp": {"hustle": 1.25}, "work_pay": 1.05}', 10),
('foodie', 'Foodie', '🍲',
 'Knows every buka in Benin by name. Gets hungry quicker, but cooking grows fast and good food lifts the mood more.',
 '{"decay": {"hunger": 1.15}, "skill_xp": {"cooking": 1.25}, "food_fun_bonus": 5}', 20),
('owambe_spirit', 'Owambe Spirit', '🎉',
 'Never misses a party, aso-ebi always ready. Dancing grows fast and parties hit harder, but boredom creeps in quicker.',
 '{"decay": {"fun": 1.2}, "skill_xp": {"dance": 1.25}, "party_fun_bonus": 10}', 30),
('gym_rat', 'Gym Rat', '💪',
 'Push-ups at Ogbe Stadium before sunrise. Fitness grows fast, and they eat like two people.',
 '{"decay": {"hunger": 1.1}, "skill_xp": {"fitness": 1.3}}', 40),
('smooth_talker', 'Smooth Talker', '😏',
 'Can talk their way past any gateman. Charisma grows fast and chats land better, but they need company more.',
 '{"decay": {"social": 1.1}, "skill_xp": {"charisma": 1.25}, "social_bonus": 5}', 50),
('lazy_bone', 'Lazy Bone', '😴',
 'Why stand when you can sit? Energy lasts longer, but work performance slips a little.',
 '{"decay": {"energy": 0.8}, "work_performance": 0.9}', 60),
('neat_freak', 'Neat Freak', '🧼',
 'Sweeps the compound before anyone wakes up. Stays fresh longer, but mess and dirt stress them out.',
 '{"decay": {"hygiene": 0.75}, "dirty_stress_mult": 1.5}', 70),
('night_crawler', 'Night Crawler', '🦉',
 'Comes alive after 8pm. Nights out are more fun, but the sleep debt hits a little harder.',
 '{"decay": {"energy": 1.1}, "night_fun_bonus": 10}', 80),
('tech_sibling', 'Tech Bro/Sis', '💻',
 'Laptop open, always hunting for Wi-Fi. Coding grows fast, but they forget to see people sometimes.',
 '{"decay": {"social": 1.15}, "skill_xp": {"coding": 1.3}}', 90),
('musical', 'Musical', '🎶',
 'Hums Afrobeats in traffic. Music grows fast and boredom takes longer to set in.',
 '{"decay": {"fun": 0.85}, "skill_xp": {"music": 1.3}}', 100),
('bini_pride', 'Bini to the Bone', '🗿',
 'Greets in Edo and knows the history of every Oba. Palace and museum visits are extra fun, and bronze craft comes easier.',
 '{"culture_fun_bonus": 10, "skill_xp": {"bronze": 1.25}}', 110)
on conflict (id) do nothing;

insert into public.dreams (id, name, emoji, description, goal, sort) values
('oga_at_the_top', 'Oga at the Top', '👔',
 'Reach the highest level of any career, from intern to the corner office.', '{"type": "career_top"}', 10),
('gra_landlord', 'GRA Landlord', '🏡',
 'Build a net worth of ₦5,000,000 and own your piece of GRA.', '{"type": "net_worth", "amount": 5000000}', 20),
('afrobeats_star', 'Afrobeats Star', '🎤',
 'Take your Music skill to level 10 and pack out Bronze Lounge.', '{"type": "skill", "skill": "music", "level": 10}', 30),
('everybodys_padi', 'Everybody''s Padi', '🤝',
 'Make 4 best friends. In Benin, your people are your wealth.', '{"type": "friends", "count": 4, "level": "best_friend"}', 40),
('benin_tech_unicorn', 'Benin Tech Unicorn', '🚀',
 'Get your startup funded and put Benin on the tech map.', '{"type": "startup_funded"}', 50),
('igun_guild_elder', 'Igun Guild Elder', '🔥',
 'Rise to the top of the bronze casters of Igun Street.', '{"type": "career_top", "track": "bronze_art"}', 60)
on conflict (id) do nothing;

insert into public.start_homes (id, name, emoji, location_id, district, tag, description, weekly_rent, start_cash, allowed_origins, locked_quip, housing_id, sort) values
('uniben_hostel', 'UNIBEN Hostel', '🎓', 'uniben_hostel', 'Ugbowo', 'Student life',
 'A bunk space in a UNIBEN hall. Lectures, handouts, night reading and the cheapest rent in town.',
 1000, '{"lapo": 6000, "nepo": 40000}', '{}', '', 'hostel_uniben', 10),
('ekenwan_face_me', 'Face-me-I-face-you', '🏚️', 'ekenwan_room', 'Ekenwan', 'Hard start',
 'One room on a shared corridor, loud neighbours and one bathroom for everybody. Cheap rent, big dreams.',
 1500, '{"lapo": 8000, "nepo": 80000}', '{}', '', 'face_me_ekenwan', 20),
('aduwawa_face_me', 'Face-me-I-face-you', '🏚️', 'aduwawa_room', 'Aduwawa', 'Hard start',
 'Out east past Ramat Park. The cheapest room in Benin, but the go-slow into town is real.',
 1200, '{"lapo": 8500, "nepo": 80000}', '{}', '', 'face_me_aduwawa', 30),
('uselu_self_contain', 'Self-contain', '🏠', 'uselu_selfcon', 'Uselu', 'Balanced',
 'Your own room, toilet and kitchen corner off Lagos Road, close to the market and the campus.',
 4000, '{"lapo": 4000, "nepo": 70000}', '{}', '', 'self_contain_uselu', 40),
('mission_rd_mini_flat', 'Mini-flat', '🏢', 'mission_rd_flats', 'Mission Road', 'Big spender',
 'A one-bedroom flat in New Benin with a sitting room, a kitchen and your own toilet. Close to the clinic and the market.',
 8000, '{"nepo": 60000}', '{nepo}', 'A mini-flat on LAPO money? 😂 Hustle first, then come back.', 'mini_flat_mission', 50),
('gra_duplex', 'Duplex', '🏰', 'gra_duplex', 'GRA', 'Big spender',
 'Big gate, quiet street, security at the post and space for the car. Dad''s friends live next door.',
 25000, '{"nepo": 50000}', '{nepo}', 'GRA with LAPO money? 😂 The gateman won''t even open. Work your way here.', 'duplex_gra', 60)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 5. Config (admin-tunable)
-- ---------------------------------------------------------------------
-- origin.force_next is inserted as 'nepo' ONLY when the key is new: the next account created after
-- this migration first runs is a Nepo baby. Re-running the migration never re-arms it (the row
-- already exists, on conflict do nothing); after that only an admin sets it.
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('origin.force_next', '"nepo"', 'origin', 'Force next new account''s origin',
 'One-shot override: the next profile created gets this origin tier id (e.g. nepo, lapo), then it resets to empty. Empty = normal roll.', 'text', null, null),
('creator.trait_count', '2', 'creator', 'Traits per Sim', 'How many distinct personality traits a new Sim must pick.', 'number', 1, 5),
('creator.arrival_location', '"uselu_park"', 'creator', 'Arrival spot before choosing a home',
 'Location id a new Sim waits at between creation and choosing a home (they cannot play until a home is chosen and are hidden from "People here").', 'text', null, null),
('rent.enabled', 'false', 'rent', 'Charge weekly rent',
 'When on, rent is taken weekly (bank first, then cash; any shortfall becomes rent owed). Off until Phase 2 jobs give players an income; while off, the due date just rolls forward so nobody is back-charged when it is turned on.', 'bool', null, null),
('rent.due_weekday', '5', 'rent', 'Rent day (0 = Mon … 6 = Sun)', 'Game weekday rent is due at 00:00. Day 1 of the game clock counts as Monday. 5 = Saturday.', 'number', 0, 6),
('rent.first_due_grace_game_days', '1', 'rent', 'First rent grace (game days)', 'A new tenant''s first rent day is the first rent weekday at least this many game days after moving in.', 'number', 0, 14),
('rent.max_catchup_weeks', '4', 'rent', 'Max weeks charged at once', 'If a player was away for several rent days, at most this many weeks are charged in one go (the rest are forgiven).', 'number', 1, 52)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 6. Copy pass: "Dad" for Nepo, moderate Pidgin (FEEDBACK_PHASE1 items 1 + 2)
-- ---------------------------------------------------------------------
update public.origin_tiers set
  tagline = 'Na hustle go carry you. Small room, small money, big dreams.',
  welcome = 'Oya {name}, welcome to {home}. You have {cash} in your pocket. Na hustle go carry you: find work, eat well, and don''t carry too much cash at night.'
where id = 'lapo';
update public.origin_tiers set
  tagline = 'Dad has connections. A nice home, a car, a laptop — just don''t embarrass the family name.',
  welcome = 'Welcome home, {name}! Dad has sorted everything: {home}, {cash} in your pocket and {bank} in the bank. The car is parked outside. Please don''t embarrass the family name.'
where id = 'nepo';

update public.game_config set label = 'LAPO baby: Dad allowance per game day',
  description = 'Daily allowance paid into bank by claim_allowance. 0 = none.' where key = 'origin.lapo.allowance_daily';
update public.game_config set label = 'Nepo baby: Dad allowance per game day',
  description = 'Daily allowance from Dad, paid into bank by claim_allowance. 0 = none.' where key = 'origin.nepo.allowance_daily';
update public.game_config set description = 'How fast hunger drops.'         where key = 'needs.hunger_per_hour';
update public.game_config set description = 'How fast energy drops.'         where key = 'needs.energy_per_hour';
update public.game_config set description = 'How fast hygiene drops.'        where key = 'needs.hygiene_per_hour';
update public.game_config set description = 'How fast boredom sets in.'      where key = 'needs.fun_per_hour';
update public.game_config set description = 'How fast loneliness sets in.'   where key = 'needs.social_per_hour';
update public.game_config set description = 'Benin life adds stress little by little.' where key = 'needs.stress_per_hour';
update public.game_config set description = 'Travel runs faster than the clock so trips are not too long.' where key = 'travel.real_seconds_per_game_minute';
update public.game_config set description = 'Turn on when the flyover opens. Removes the Ramat jam.' where key = 'traffic.ramat_flyover_open';

update public.items set description = 'Belgium-used Toyota Corolla. It has seen some road, but the engine still sings. Fuel is on you.'
  where id = 'tokunbo_car';
update public.items set description = 'Clean UK-used laptop. The battery lasts about two hours if you pray. Your key to tech work.'
  where id = 'laptop';

update public.activities set name = 'Sleep'                                where id = 'sleep';
update public.activities set name = 'Take a nap'                           where id = 'nap';
update public.activities set name = 'Bucket bath'                          where id = 'bathe';
update public.activities set name = 'Owo soup and starch'                  where id = 'owo_soup';
update public.activities set name = 'Watch football at the viewing centre' where id = 'watch_football';
update public.activities set name = 'Night out at the club'                where id = 'club_night';
update public.activities set name = 'Stroll around campus'                 where id = 'campus_stroll';
update public.activities set name = 'Market stroll and price check'        where id = 'market_stroll';
update public.activities set name = 'Fresh haircut or hairdo'              where id = 'salon_freshen';
update public.activities set name = 'Watch the planes land'                where id = 'plane_spotting';

update public.locations l set blurb = v.blurb from (values
 ('national_museum', 'All of Benin''s history in one place: bronze heads, ivory carvings and centuries of royal art. Ring Road traffic circles it like it is the centre of the world, because it is.'),
 ('oba_market', 'The biggest market in Benin. If you can''t find it at Oba Market, it doesn''t exist. Hold your bag tight; the crowd no dey joke.'),
 ('ring_road_pos', 'Ten PoS umbrellas, one long queue and plenty of "network no dey". Cash flows here, so eyes are watching too.'),
 ('oba_palace', 'The royal palace of the Oba of Benin. Show respect, dress decently and take in centuries of culture.'),
 ('igun_street', 'Bronze casters have worked on this street for generations. Hammers knock, furnaces roar, and art is born.'),
 ('mama_osas_buka', 'Mama Osas''s owo soup can make a grown man emotional. Sit down, wash your hands, and don''t ask for extra meat without change.'),
 ('new_benin_market', 'Tomatoes, phone chargers, okrika: New Benin Market has everything. The price? "How much you get?"'),
 ('new_benin_pos', 'Busy junction, busy PoS, and boys watching your pocket. Withdraw quick, leave quicker.'),
 ('mercy_clinic', 'Small clinic, big heart. The nurse checks your BP, sets up a drip, then tells you it is stress. Rest, please.'),
 ('mission_rd_flats', 'Mini-flats with your own toilet and kitchen. No more morning queue. You are moving up in life.'),
 ('uselu_market', 'Uselu Market noise fit wake the dead. Foodstuff is cheap; the go-slow on Lagos Road is not.'),
 ('fresh_cut_salon', 'The generator hums, the clippers buzz and the gist flows. Walk out looking like money, even if your account is crying.'),
 ('uselu_park', '"Lagos! Lagos! One chance remain!" Agberos shouting, buses loading, suya smoking. New arrivals land here. Watch your pocket.'),
 ('uniben', 'Great UNIBEN! Lectures, handouts and plenty of gist under the trees. Strike or no strike, campus stays lively.'),
 ('ubth', 'The teaching hospital that patches Benin back together. The queue is long, but the doctors know their work.'),
 ('back_gate_joint', 'Where students eat noodles and egg on credit and argue football till midnight. Cheap food, expensive gist.'),
 ('wifi_joint', 'Fast Wi-Fi, a loud generator and people typing like it is exam day. Do your assignment; only legit work here.'),
 ('oluku_park', 'Gateway to the Lagos–Benin expressway. Trailers, buses and hustlers everywhere. Don''t linger at night.'),
 ('ramat_park', 'The kingdom of go-slow. The flyover is almost finished… it will finish soon. Bring patience and small chops.'),
 ('oregbeni_market', 'Up on Ikpoba Hill, market women will call you "my husband" or "fine sister" until you buy something. That is marketing.'),
 ('aduwawa_park', 'Last stop before Auchi Road. Buses load for the north; travel by day if you can.'),
 ('aduwawa_room', 'Ten rooms, one corridor, one bathroom, and everybody''s business is your business. Cheap rent, plenty drama.'),
 ('third_east', 'Busy with shops and spare parts by day. At night? Omo, don''t hold your phone in your hand. Boys dey operate.'),
 ('ekiosa_market', 'Fresh fish, dry fish, snail and periwinkle: Ekiosa has the soup ingredients your mum uses.'),
 ('baba_shrine', 'Baba Osagie has herbs for everything: headache, bad luck, a little "protection". Pay first, believe later.'),
 ('upper_sakponba', 'Lively in the afternoon. When night falls, head home; this place doesn''t smile after dark.'),
 ('santana_market', 'Off Sapele Road, Santana sells everything from yam to Ankara. Bargain hard; the first price is a joke.'),
 ('sapele_pos', 'Sapele Road PoS is a hot spot: plenty of cash, plenty of eyes. Withdraw small-small and don''t form big man.'),
 ('bronze_lounge', 'The DJ drops Afrobeats, the Chapman is cold, and everybody is "boss" here. Spray money with sense.'),
 ('police_hq', 'Report a case, pay bail, or visit your guy in the cell. Speak respectfully; the officers are busy.'),
 ('bronze_bank', 'Money in the bank can''t be robbed on the street. Cold AC, long queue, but your money is safe.'),
 ('gra_duplex', 'Big gate, quiet street, a security man at the post. When you live here, you have arrived.'),
 ('kingdom_lounge', 'Classy GRA spot: big men, soft music and small chops that cost a week''s salary. Dress to impress.'),
 ('benin_airport', 'Flights to Lagos and Abuja are coming soon. For now, watch the planes land and dream big.'),
 ('siluko_rd', 'A long road of shops, churches and mechanics. Daytime is for hustle; at night, keep your eyes open.'),
 ('ekenwan_room', 'A first room in Benin: small, hot, and the landlord collects rent on time. This is where the hustle starts.'),
 ('iguobazuwa_farm', 'Far from town, close to the soil. Plant cassava, plantain or pepper, and watch out for harvest thieves.')
) as v(id, blurb) where l.id = v.id;

-- ---------------------------------------------------------------------
-- 7. Internal helpers
-- ---------------------------------------------------------------------

-- Reject config values the server cannot use (redefines the P1-TIME trigger function; keeps its epoch check).
create or replace function public.bl_game_config_validate() returns trigger
language plpgsql set search_path = public as $$
declare v timestamptz; v_txt text;
begin
  if new.key = 'clock.epoch' then
    begin
      v := (new.value #>> '{}')::timestamptz;
    exception when others then
      raise exception 'Clock epoch must be a date/time like 2026-10-05T00:00:00Z.' using errcode = 'P0001';
    end;
    if v is null then
      raise exception 'Clock epoch must be a date/time like 2026-10-05T00:00:00Z.' using errcode = 'P0001';
    end if;
  elsif new.key = 'origin.force_next' then
    v_txt := trim(coalesce(new.value #>> '{}', ''));
    if v_txt <> '' and not exists (select 1 from origin_tiers where id = v_txt) then
      raise exception 'origin.force_next must be empty or an origin tier id (e.g. nepo, lapo).' using errcode = 'P0001';
    end if;
  elsif new.key = 'creator.arrival_location' then
    if not exists (select 1 from locations where id = new.value #>> '{}') then
      raise exception 'creator.arrival_location must be a location id.' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;

-- Game clock (same signature); adds weekday (0 = Monday … 6 = Sunday; game day 1 is a Monday).
create or replace function public.bl_game_clock(p_at timestamptz default null) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_at    timestamptz := coalesce(p_at, bl_now());
  v_epoch timestamptz := bl_cfg_text('clock.epoch')::timestamptz;
  v_gm    bigint;
  v_hour  int;
  v_min   int;
  v_day   bigint;
  v_ns    int := bl_cfg('clock.night_start_hour')::int;
  v_ne    int := bl_cfg('clock.night_end_hour')::int;
begin
  v_gm := floor(extract(epoch from (v_at - v_epoch))
                * bl_cfg('clock.game_minutes_per_real_minute') / 60.0
                + bl_cfg('clock.start_hour_offset') * 60)::bigint;
  v_hour := ((v_gm % 1440 + 1440) % 1440) / 60;
  v_min  := ((v_gm % 60) + 60) % 60;
  v_day  := floor(v_gm / 1440.0)::bigint + 1;
  return jsonb_build_object(
    'game_minutes', v_gm,
    'day', v_day,
    'weekday', (((v_day - 1) % 7) + 7) % 7,
    'hour', v_hour,
    'minute', v_min,
    'is_night', case when v_ns > v_ne then (v_hour >= v_ns or v_hour < v_ne)
                     else (v_hour >= v_ns and v_hour < v_ne) end
  );
end $$;

-- First rent day (rent.due_weekday, 00:00 game time) strictly after p_from + p_grace_game_days.
create or replace function public.bl_rent_due_after(p_from timestamptz, p_grace_game_days numeric) returns timestamptz
language plpgsql stable set search_path = public as $$
declare
  v_speed numeric := greatest(bl_cfg('clock.game_minutes_per_real_minute'), 0.0001);
  v_off   numeric := bl_cfg('clock.start_hour_offset') * 60;
  v_epoch timestamptz := bl_cfg_text('clock.epoch')::timestamptz;
  v_wd    int := ((bl_cfg('rent.due_weekday')::int % 7) + 7) % 7;
  v_gm    numeric;
  v_k     bigint;   -- 0-based game day index (day number k+1, weekday k mod 7)
begin
  v_gm := extract(epoch from (p_from - v_epoch)) * v_speed / 60.0 + v_off + greatest(p_grace_game_days, 0) * 1440;
  v_k := floor(v_gm / 1440)::bigint + 1;
  v_k := v_k + (((v_wd - v_k) % 7) + 7) % 7;
  return v_epoch + make_interval(secs => ((v_k * 1440 - v_off) * 60.0 / v_speed)::double precision);
end $$;

-- Product of the traits' decay multipliers for one need (1 when none apply).
create or replace function public.bl_trait_mult(p_traits text[], p_need text) returns numeric
language plpgsql stable set search_path = public as $$
declare v numeric := 1; r record;
begin
  if p_traits is null or cardinality(p_traits) = 0 then return 1; end if;
  for r in select (t.effects #>> array['decay', p_need]) as m from traits t where t.id = any (p_traits) loop
    if r.m is not null then v := v * greatest(r.m::numeric, 0); end if;
  end loop;
  return v;
end $$;

-- Pure needs decay (same signature as core). Trait decay multipliers scale each rate; the rates are
-- constant per profile, so decay stays path-independent.
create or replace function public.bl_decay_row(p_row public.profiles, p_at timestamptz) returns public.profiles
language plpgsql stable set search_path = public as $$
declare
  v        profiles := p_row;
  v_hours  numeric;
  r_hun    numeric; r_en numeric; r_hy numeric; r_fun numeric; r_soc numeric; r_str numeric;
  r_starve numeric; v_floor numeric;
  v_zero   numeric;
  v_health numeric;
begin
  if v.id is null then return v; end if;
  v_hours := extract(epoch from (p_at - v.needs_updated_at))::numeric / 3600.0
             * bl_cfg('clock.game_minutes_per_real_minute');
  if v_hours <= 0 then return v; end if;

  r_hun := bl_cfg('needs.hunger_per_hour')  * bl_trait_mult(v.traits, 'hunger');
  r_en  := bl_cfg('needs.energy_per_hour')  * bl_trait_mult(v.traits, 'energy');
  r_hy  := bl_cfg('needs.hygiene_per_hour') * bl_trait_mult(v.traits, 'hygiene');
  r_fun := bl_cfg('needs.fun_per_hour')     * bl_trait_mult(v.traits, 'fun');
  r_soc := bl_cfg('needs.social_per_hour')  * bl_trait_mult(v.traits, 'social');
  r_str := bl_cfg('needs.stress_per_hour')  * bl_trait_mult(v.traits, 'stress');
  r_starve := bl_cfg('needs.starve_health_per_hour');
  v_floor  := bl_cfg('needs.starve_health_floor');

  v_zero := least(case when r_hun > 0 then greatest(v.hunger, 0) / r_hun else 1e9 end,
                  case when r_en  > 0 then greatest(v.energy, 0) / r_en  else 1e9 end);
  v_health := v.health - greatest(0, v_hours - v_zero) * r_starve;
  v_health := greatest(v_health, least(v.health, v_floor));

  v.hunger  := round(greatest(0, least(100, v.hunger  - r_hun * v_hours)), 4);
  v.energy  := round(greatest(0, least(100, v.energy  - r_en  * v_hours)), 4);
  v.hygiene := round(greatest(0, least(100, v.hygiene - r_hy  * v_hours)), 4);
  v.fun     := round(greatest(0, least(100, v.fun     - r_fun * v_hours)), 4);
  v.social  := round(greatest(0, least(100, v.social  - r_soc * v_hours)), 4);
  v.stress  := round(greatest(0, least(100, v.stress  + r_str * v_hours)), 4);
  v.health  := round(greatest(0, least(100, v_health)), 4);
  v.needs_updated_at := p_at;
  return v;
end $$;

-- Login check (same signature as core; plain-English message).
create or replace function public.bl_require_uid() returns uuid
language plpgsql stable set search_path = public as $$
declare v uuid := auth.uid();
begin
  if v is null then
    raise exception 'Please log in first.' using errcode = 'P0001', hint = 'not_logged_in';
  end if;
  return v;
end $$;

-- Weekly rent, lazily. Returns true when it changed the row. Never raises for lack of money:
-- it takes bank first, then cash, and adds any shortfall to rent_owed (eviction = P2-ECON housing).
-- While rent.enabled is false the due date just rolls forward (no back-charge when switched on).
create or replace function public.bl_charge_rent(p_uid uuid) returns boolean
language plpgsql set search_path = public as $$
declare
  v       profiles;
  v_now   timestamptz := bl_now();
  v_due   timestamptz;
  v_weeks int := 0;
  v_cap   int := greatest(1, bl_cfg('rent.max_catchup_weeks')::int);
  v_total bigint; v_left bigint; v_pay bigint; v_paid bigint;
  v_meta  jsonb;
begin
  select * into v from profiles where id = p_uid for update;
  if not found or not v.home_chosen or v.rent_due_at is null or v.rent_due_at > v_now then
    return false;
  end if;
  v_due := v.rent_due_at;
  while v_due <= v_now and v_weeks < 100000 loop
    v_weeks := v_weeks + 1;
    v_due := bl_rent_due_after(v_due + interval '1 second', 0);
  end loop;

  if not bl_cfg_bool('rent.enabled') or (v.weekly_rent <= 0 and v.rent_owed <= 0) then
    update profiles set rent_due_at = v_due where id = p_uid;
    return true;
  end if;

  v_total := v.rent_owed + v.weekly_rent * least(v_weeks, v_cap);
  v_left := v_total;
  v_meta := jsonb_build_object('weeks', least(v_weeks, v_cap), 'weekly_rent', v.weekly_rent,
                               'previous_owed', v.rent_owed, 'housing', v.housing_id);
  v_pay := least(v_left, v.bank);
  if v_pay > 0 then perform bl_add_money(p_uid, 'bank', -v_pay, 'rent', v_meta); v_left := v_left - v_pay; end if;
  v_pay := least(v_left, v.cash);
  if v_pay > 0 then perform bl_add_money(p_uid, 'cash', -v_pay, 'rent', v_meta); v_left := v_left - v_pay; end if;
  v_paid := v_total - v_left;
  update profiles set rent_due_at = v_due, rent_owed = v_left where id = p_uid;

  if v_left = 0 then
    perform bl_event(p_uid, 'rent_paid', 'Rent paid',
      'Your landlord collected ' || bl_naira(v_paid) || ' rent. See you next week.',
      v_meta || jsonb_build_object('paid', v_paid, 'next_due_at', v_due));
  else
    perform bl_event(p_uid, 'rent_owed', 'Rent overdue',
      'Landlord don knock! You paid ' || bl_naira(v_paid) || ' and still owe ' || bl_naira(v_left)
      || ' rent. Settle it before things get serious.',
      v_meta || jsonb_build_object('paid', v_paid, 'owed', v_left, 'next_due_at', v_due));
  end if;
  return true;
end $$;

-- Caller's row locked FOR UPDATE with needs decayed — no home check (creator steps, avatar edits).
create or replace function public.bl_me_any() returns public.profiles
language plpgsql set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v profiles;
begin
  select * into v from profiles where id = v_uid for update;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v.banned then
    raise exception 'This account has been banned. If this is a mistake, contact the admin.' using errcode = 'P0001', hint = 'banned';
  end if;
  return bl_apply_needs(v_uid);
end $$;

-- Gameplay guard (same signature as core): also refuses until a home is chosen (hint no_home),
-- then charges any weekly rent that fell due.
create or replace function public.bl_me() returns public.profiles
language plpgsql set search_path = public as $$
declare v profiles := bl_me_any();
begin
  if not v.home_chosen then
    raise exception 'Hold on, choose where you will live first.' using errcode = 'P0001', hint = 'no_home';
  end if;
  if v.rent_due_at is not null and v.rent_due_at <= bl_now() then
    if bl_charge_rent(v.id) then
      select * into v from profiles where id = v.id;
    end if;
  end if;
  return v;
end $$;

-- Same signature as core; plain-English messages.
create or replace function public.bl_assert_free(p_me public.profiles) returns void
language plpgsql stable set search_path = public as $$
declare v_now timestamptz := bl_now(); v_left int;
begin
  if p_me.jailed_until is not null and p_me.jailed_until > v_now then
    v_left := ceil(extract(epoch from p_me.jailed_until - v_now));
    raise exception 'You are in a police cell! Wait about % sec or find bail.', v_left using errcode = 'P0001', hint = 'jailed';
  end if;
  if p_me.hospitalized_until is not null and p_me.hospitalized_until > v_now then
    v_left := ceil(extract(epoch from p_me.hospitalized_until - v_now));
    raise exception 'You are still admitted in hospital. Rest a little — about % sec left.', v_left using errcode = 'P0001', hint = 'hospitalized';
  end if;
  if p_me.travel_to is not null then
    raise exception 'You are still on the road. Wait until you arrive.' using errcode = 'P0001', hint = 'traveling';
  end if;
  if p_me.busy_until is not null and p_me.busy_until > v_now then
    v_left := ceil(extract(epoch from p_me.busy_until - v_now));
    raise exception 'Hold on, you are busy with "%". It finishes in about % sec.', coalesce(p_me.busy_label, 'something'), v_left
      using errcode = 'P0001', hint = 'busy';
  end if;
end $$;

-- One bl_rand() roll (same as P1-ORIGIN) unless origin.force_next names a tier: then that tier wins
-- and the key is reset to '' (one-shot; the reset is in the same transaction as the profile insert,
-- so a failed create leaves it armed). An unknown id is ignored and cleared.
create or replace function public.bl_roll_origin() returns text
language plpgsql volatile set search_path = public as $$
declare
  v_force text;
  v_roll  double precision;
  v_acc   numeric := 0;
  r       record;
  v_id    text;
begin
  select trim(coalesce(value #>> '{}', '')) into v_force from game_config where key = 'origin.force_next';
  if coalesce(v_force, '') <> '' then
    update game_config set value = '""'::jsonb where key = 'origin.force_next';
    insert into config_audit (admin_id, key, old_value, new_value)
    values (null, 'origin.force_next', to_jsonb(v_force), '""'::jsonb);
    if exists (select 1 from origin_tiers where id = v_force) then
      return v_force;
    end if;
  end if;

  v_roll := bl_rand() * 100;
  for r in select id, chance_key from origin_tiers
           where not is_default and chance_key is not null order by sort, id loop
    v_acc := v_acc + greatest(0, bl_cfg(r.chance_key));
    if v_roll < v_acc then return r.id; end if;
  end loop;
  select id into v_id from origin_tiers where is_default order by sort limit 1;
  if v_id is null then
    raise exception 'Origin setup is incomplete. Admin, please add a default tier.' using errcode = 'P0001';
  end if;
  return v_id;
end $$;

-- Cash in hand for a tier at a start home: the home's start_cash[tier], else origin.<tier>.start_cash.
create or replace function public.bl_start_cash(p_tier text, p_home text) returns bigint
language sql stable set search_path = public as $$
  select greatest(0, coalesce(
    (select (h.start_cash ->> p_tier)::numeric from start_homes h where h.id = p_home),
    bl_origin_num(p_tier, 'start_cash')))::bigint;
$$;

create or replace function public.bl_home_allowed(p_home public.start_homes, p_tier text) returns boolean
language sql immutable set search_path = public as $$
  select cardinality(p_home.allowed_origins) = 0 or p_tier = any (p_home.allowed_origins);
$$;

-- Active start homes as the creator's home step sees them for one origin tier.
create or replace function public.bl_homes_for(p_tier text) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', h.id, 'name', h.name, 'emoji', h.emoji, 'district', h.district, 'tag', h.tag,
           'description', h.description, 'location_id', h.location_id, 'location_name', l.name,
           'scene', l.scene, 'housing_id', h.housing_id, 'weekly_rent', h.weekly_rent,
           'start_cash', bl_start_cash(p_tier, h.id),
           'start_bank', greatest(0, bl_origin_num(p_tier, 'start_bank'))::bigint,
           'allowed', bl_home_allowed(h, p_tier),
           'locked_quip', case when bl_home_allowed(h, p_tier) then null else h.locked_quip end)
         order by h.sort, h.id), '[]'::jsonb)
  from start_homes h join locations l on l.id = h.location_id
  where h.active;
$$;

-- Shared create_profile / create_profile_v2 validation (raises; plain-English messages).
create or replace function public.bl_check_new_profile(p_uid uuid, p_name text, p_gender text, p_avatar jsonb) returns void
language plpgsql stable set search_path = public as $$
begin
  if exists (select 1 from profiles where id = p_uid) then
    raise exception 'You have already created your Sim. One account, one Sim.' using errcode = 'P0001', hint = 'profile_exists';
  end if;
  if p_name !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'Usernames must be 3 to 20 letters, numbers or underscores (_). No spaces or symbols.'
      using errcode = 'P0001';
  end if;
  if p_gender not in ('male','female') then
    raise exception 'Please pick male or female.' using errcode = 'P0001';
  end if;
  if p_avatar is null or jsonb_typeof(p_avatar) <> 'object' or length(p_avatar::text) > 4000 then
    raise exception 'Your avatar data is not valid. Please try again.' using errcode = 'P0001';
  end if;
  if exists (select 1 from profiles where lower(username) = lower(p_name)) then
    raise exception 'Somebody don already carry "%" as a username. Try another one.', p_name using errcode = 'P0001';
  end if;
end $$;

-- Validated, de-duplicated trait list (exactly creator.trait_count distinct active traits).
create or replace function public.bl_check_traits(p_traits text[]) returns text[]
language plpgsql stable set search_path = public as $$
declare
  v_n   int := bl_cfg('creator.trait_count')::int;
  v_out text[];
begin
  select coalesce(array_agg(t order by ord), '{}') into v_out
  from unnest(coalesce(p_traits, '{}')) with ordinality as u(raw, ord)
  cross join lateral (select lower(trim(u.raw)) as t) x;
  if cardinality(v_out) <> v_n then
    raise exception 'Pick exactly % personality traits.', v_n using errcode = 'P0001', hint = 'bad_traits';
  end if;
  if (select count(distinct t) from unnest(v_out) t) <> v_n then
    raise exception 'Pick % different traits, not the same one twice.', v_n using errcode = 'P0001', hint = 'bad_traits';
  end if;
  if exists (select 1 from unnest(v_out) t where not exists (select 1 from traits tr where tr.id = t and tr.active)) then
    raise exception 'One of those traits doesn''t exist. Pick again.' using errcode = 'P0001', hint = 'bad_traits';
  end if;
  return v_out;
end $$;

create or replace function public.bl_check_dream(p_dream text) returns text
language plpgsql stable set search_path = public as $$
declare v text := lower(trim(coalesce(p_dream, '')));
begin
  if v = '' or not exists (select 1 from dreams where id = v and active) then
    raise exception 'Pick a dream for your Sim from the list.' using errcode = 'P0001', hint = 'bad_dream';
  end if;
  return v;
end $$;

-- Starter items of a tier into the bag (unknown ids skipped). p_missing_only: only items not owned yet.
create or replace function public.bl_give_origin_items(p_uid uuid, p_tier text, p_missing_only boolean default false) returns text[]
language plpgsql set search_path = public as $$
declare v_item text; v_given text[] := '{}';
begin
  foreach v_item in array bl_origin_items(p_tier) loop
    if not exists (select 1 from items where id = v_item) then continue; end if;
    if p_missing_only and exists (select 1 from inventory where user_id = p_uid and item_id = v_item and qty > 0) then
      continue;
    end if;
    insert into inventory (user_id, item_id, qty) values (p_uid, v_item, 1)
    on conflict (user_id, item_id) do update set qty = inventory.qty + 1;
    v_given := v_given || v_item;
  end loop;
  return v_given;
end $$;

create or replace function public.bl_welcome_text(p_tier text, p_name text, p_home text, p_cash bigint, p_bank bigint) returns text
language sql stable set search_path = public as $$
  select replace(replace(replace(replace(coalesce(t.welcome, ''),
           '{name}', p_name), '{home}', p_home), '{cash}', bl_naira(p_cash)), '{bank}', bl_naira(p_bank))
  from origin_tiers t where t.id = p_tier;
$$;

-- ---------------------------------------------------------------------
-- 8. RPCs
-- ---------------------------------------------------------------------

-- Same as P1-ORIGIN plus `creator` and `rent` blocks. Still read-mostly: the only write is the
-- throttled last_seen (no decay persist, no rent charge here).
create or replace function public.get_my_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_now   timestamptz := bl_now();
  v_me    profiles;
  v_clock jsonb;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v_me.banned then
    raise exception 'This account has been banned. If this is a mistake, contact the admin.' using errcode = 'P0001', hint = 'banned';
  end if;
  if v_me.last_seen is null
     or v_me.last_seen < v_now - make_interval(secs => bl_cfg('time.last_seen_throttle_real_seconds')::double precision) then
    update profiles set last_seen = v_now where id = v_uid returning * into v_me;
  end if;
  v_me := bl_decay_row(v_me, v_now);
  v_clock := bl_game_clock(v_now);
  return jsonb_build_object(
    'profile', to_jsonb(v_me) - array['banned','needs_updated_at','last_seen',
                                      'travel_to','travel_mode','travel_started_at','travel_arrives_at'],
    'clock', v_clock,
    'location', (select to_jsonb(l) from locations l where l.id = v_me.location_id),
    'travel', case when v_me.travel_to is null then null
                   else jsonb_build_object('to', v_me.travel_to, 'mode', v_me.travel_mode,
                                           'started_at', v_me.travel_started_at,
                                           'arrives_at', v_me.travel_arrives_at) end,
    'origin', bl_origin_info(v_me.origin, v_me.allowance_claimed_day, (v_clock->>'day')::bigint),
    'creator', jsonb_build_object(
      'home_chosen', v_me.home_chosen,
      'traits', to_jsonb(v_me.traits),
      'dream', v_me.dream,
      'start_home', v_me.start_home,
      'homes', case when v_me.home_chosen then null else bl_homes_for(v_me.origin) end),
    'rent', jsonb_build_object(
      'weekly', v_me.weekly_rent,
      'due_at', v_me.rent_due_at,
      'owed', v_me.rent_owed,
      'enabled', bl_cfg_bool('rent.enabled')),
    'server_time', v_now
  );
end $$;

-- v1 (same signature): all-in-one creation as before (origin roll incl. force_next, starter pack,
-- welcome). traits = '{}', dream = null, no rent.
create or replace function public.create_profile(p_username text, p_gender text, p_avatar jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := bl_require_uid();
  v_name   text := trim(coalesce(p_username, ''));
  v_gender text := lower(trim(coalesce(p_gender, '')));
  v_avatar jsonb := coalesce(p_avatar, '{}'::jsonb);
  v_now    timestamptz := bl_now();
  v_need   numeric := bl_cfg('start.need_level');
  v_tier   text;
  v_home   locations;
  v_cash   bigint;
  v_bank   bigint;
begin
  perform bl_check_new_profile(v_uid, v_name, v_gender, v_avatar);

  v_tier := bl_roll_origin();
  v_home := bl_location(bl_origin_cfg(v_tier, 'home_location'));
  v_cash := greatest(0, bl_origin_num(v_tier, 'start_cash'))::bigint;
  v_bank := greatest(0, bl_origin_num(v_tier, 'start_bank'))::bigint;

  begin
    insert into profiles (id, username, gender, avatar, cash, bank,
                          hunger, energy, hygiene, fun, social, health, stress, needs_updated_at,
                          location_id, home_location_id, housing_id, origin,
                          protected_until, last_seen, created_at)
    values (v_uid, v_name, v_gender, v_avatar, 0, 0,
            v_need, v_need, v_need, v_need, v_need, bl_cfg('start.health'), bl_cfg('start.stress'), v_now,
            v_home.id, v_home.id, bl_origin_cfg(v_tier, 'housing'), v_tier,
            v_now + make_interval(mins => bl_cfg('start.protection_real_minutes')::int), v_now, v_now);
  exception when unique_violation then
    raise exception 'Somebody don already carry "%" as a username. Try another one.', v_name using errcode = 'P0001';
  end;

  if v_cash > 0 then perform bl_add_money(v_uid, 'cash', v_cash, 'start_bonus', jsonb_build_object('origin', v_tier)); end if;
  if v_bank > 0 then perform bl_add_money(v_uid, 'bank', v_bank, 'start_bonus', jsonb_build_object('origin', v_tier)); end if;
  perform bl_give_origin_items(v_uid, v_tier);
  perform bl_event(v_uid, 'welcome', 'Welcome to Benin!', bl_welcome_text(v_tier, v_name, v_home.name, v_cash, v_bank),
                   jsonb_build_object('origin', v_tier));
  return get_my_state();
end $$;

-- v2 step 1 (after Look -> Personality -> Dream): validates, rolls the origin and creates the Sim
-- with no home yet (at creator.arrival_location, cash 0, home_chosen false). Nothing is paid here.
-- Returns GameState; GameState.creator.homes lists the start homes for the rolled origin.
create or replace function public.create_profile_v2(p_username text, p_gender text, p_avatar jsonb,
                                                    p_traits text[], p_dream text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := bl_require_uid();
  v_name   text := trim(coalesce(p_username, ''));
  v_gender text := lower(trim(coalesce(p_gender, '')));
  v_avatar jsonb := coalesce(p_avatar, '{}'::jsonb);
  v_now    timestamptz := bl_now();
  v_need   numeric := bl_cfg('start.need_level');
  v_traits text[];
  v_dream  text;
  v_tier   text;
  v_arrive locations;
begin
  perform bl_check_new_profile(v_uid, v_name, v_gender, v_avatar);
  v_traits := bl_check_traits(p_traits);
  v_dream := bl_check_dream(p_dream);
  v_arrive := bl_location(bl_cfg_text('creator.arrival_location'));
  v_tier := bl_roll_origin();

  begin
    insert into profiles (id, username, gender, avatar, cash, bank,
                          hunger, energy, hygiene, fun, social, health, stress, needs_updated_at,
                          location_id, home_location_id, housing_id, origin,
                          traits, dream, home_chosen,
                          protected_until, last_seen, created_at)
    values (v_uid, v_name, v_gender, v_avatar, 0, 0,
            v_need, v_need, v_need, v_need, v_need, bl_cfg('start.health'), bl_cfg('start.stress'), v_now,
            v_arrive.id, v_arrive.id, null, v_tier,
            v_traits, v_dream, false,
            v_now + make_interval(mins => bl_cfg('start.protection_real_minutes')::int), v_now, v_now);
  exception when unique_violation then
    raise exception 'Somebody don already carry "%" as a username. Try another one.', v_name using errcode = 'P0001';
  end;
  return get_my_state();
end $$;

-- v2 step 2 (once): move into a start home the origin may pick, get the starter pack
-- (home's start cash for the origin + origin bank + origin items), fresh needs, protection from now,
-- weekly rent with the first rent day, and the welcome event.
create or replace function public.choose_start_home(p_home text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me_any();
  h      start_homes;
  v_loc  locations;
  v_now  timestamptz := bl_now();
  v_need numeric := bl_cfg('start.need_level');
  v_cash bigint;
  v_bank bigint;
  v_due  timestamptz;
  v_body text;
begin
  if v_me.home_chosen then
    raise exception 'You have already moved in. Your first home is chosen.' using errcode = 'P0001', hint = 'home_already_chosen';
  end if;
  select * into h from start_homes where id = lower(trim(coalesce(p_home, ''))) and active;
  if not found then
    raise exception 'That home is not on the list. Pick one of the options.' using errcode = 'P0001', hint = 'bad_home';
  end if;
  if not bl_home_allowed(h, v_me.origin) then
    raise exception '%', coalesce(nullif(h.locked_quip, ''), 'That home is not available for you. Pick another one.')
      using errcode = 'P0001', hint = 'home_locked';
  end if;
  v_loc := bl_location(h.location_id);
  v_cash := bl_start_cash(v_me.origin, h.id);
  v_bank := greatest(0, bl_origin_num(v_me.origin, 'start_bank'))::bigint;
  v_due := bl_rent_due_after(v_now, bl_cfg('rent.first_due_grace_game_days'));

  update profiles set
    home_chosen = true, start_home = h.id,
    location_id = v_loc.id, home_location_id = v_loc.id, housing_id = h.housing_id,
    weekly_rent = h.weekly_rent, rent_due_at = v_due, rent_owed = 0,
    hunger = v_need, energy = v_need, hygiene = v_need, fun = v_need, social = v_need,
    health = bl_cfg('start.health'), stress = bl_cfg('start.stress'), needs_updated_at = v_now,
    protected_until = v_now + make_interval(mins => bl_cfg('start.protection_real_minutes')::int),
    last_seen = v_now
  where id = v_me.id;

  if v_cash > 0 then
    perform bl_add_money(v_me.id, 'cash', v_cash, 'start_bonus', jsonb_build_object('origin', v_me.origin, 'home', h.id));
  end if;
  if v_bank > 0 then
    perform bl_add_money(v_me.id, 'bank', v_bank, 'start_bonus', jsonb_build_object('origin', v_me.origin, 'home', h.id));
  end if;
  perform bl_give_origin_items(v_me.id, v_me.origin);

  v_body := bl_welcome_text(v_me.origin, v_me.username, v_loc.name, v_cash, v_bank);
  if h.weekly_rent > 0 then
    v_body := v_body || ' Rent is ' || bl_naira(h.weekly_rent) || ' a week.';
  end if;
  perform bl_event(v_me.id, 'welcome', 'Welcome to Benin!', v_body,
                   jsonb_build_object('origin', v_me.origin, 'home', h.id));
  return get_my_state() || jsonb_build_object('message', 'Welcome to your new home: ' || h.name
                                                        || case when h.district <> '' then ', ' || h.district else '' end || '!');
end $$;

-- Creator catalog (traits, dreams, all active homes with per-origin cash) — readable before sign-up.
create or replace function public.creator_catalog() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'trait_count', bl_cfg('creator.trait_count')::int,
    'traits', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'emoji', emoji,
                         'description', description, 'effects', effects) order by sort, id)
                        from traits where active), '[]'::jsonb),
    'dreams', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'emoji', emoji,
                         'description', description, 'goal', goal) order by sort, id)
                        from dreams where active), '[]'::jsonb),
    'homes', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'name', h.name, 'emoji', h.emoji,
                         'district', h.district, 'tag', h.tag, 'description', h.description,
                         'location_id', h.location_id, 'weekly_rent', h.weekly_rent, 'start_cash', h.start_cash,
                         'allowed_origins', to_jsonb(h.allowed_origins), 'locked_quip', h.locked_quip)
                         order by h.sort, h.id)
                       from start_homes h where h.active), '[]'::jsonb),
    'rent_weekday', bl_cfg('rent.due_weekday')::int);
$$;

-- Admin: set a player's origin. With p_apply_perks (and a home already chosen) it tops up the
-- difference — never takes anything away:
--   cash += max(0, start cash of new tier − old tier)  (at the player's start home; else origin.<tier>.start_cash)
--   bank += max(0, origin.<new>.start_bank − origin.<old>.start_bank)
--   + any of the new tier's starter items the player does not own yet.
-- Ledger reason 'admin_origin'. Home, housing and rent are not changed. The allowance follows the
-- new tier automatically. Writes admin_audit + an 'origin_changed' event to the player.
create or replace function public.admin_set_origin(p_user uuid, p_origin text, p_apply_perks boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_require_uid();
  v_tier  origin_tiers;
  v_p     profiles;
  v_old   text;
  v_cash  bigint := 0;
  v_bank  bigint := 0;
  v_items text[] := '{}';
  v_body  text;
begin
  if not bl_is_admin() then
    raise exception 'Only admins can do that.' using errcode = 'P0001', hint = 'not_admin';
  end if;
  select * into v_tier from origin_tiers where id = lower(trim(coalesce(p_origin, '')));
  if not found then
    raise exception 'That origin tier doesn''t exist.' using errcode = 'P0001', hint = 'bad_origin';
  end if;
  select * into v_p from profiles where id = p_user for update;
  if not found then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  v_old := v_p.origin;
  update profiles set origin = v_tier.id where id = p_user;

  if coalesce(p_apply_perks, false) and v_p.home_chosen then
    v_cash := greatest(0, bl_start_cash(v_tier.id, v_p.start_home) - bl_start_cash(v_old, v_p.start_home));
    v_bank := greatest(0, greatest(0, bl_origin_num(v_tier.id, 'start_bank'))::bigint
                          - greatest(0, bl_origin_num(v_old, 'start_bank'))::bigint);
    if v_cash > 0 then
      perform bl_add_money(p_user, 'cash', v_cash, 'admin_origin', jsonb_build_object('from', v_old, 'to', v_tier.id));
    end if;
    if v_bank > 0 then
      perform bl_add_money(p_user, 'bank', v_bank, 'admin_origin', jsonb_build_object('from', v_old, 'to', v_tier.id));
    end if;
    v_items := bl_give_origin_items(p_user, v_tier.id, true);
  end if;

  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'set_origin', p_user, jsonb_build_object(
    'old', v_old, 'new', v_tier.id, 'apply_perks', coalesce(p_apply_perks, false),
    'cash', v_cash, 'bank', v_bank, 'items', to_jsonb(v_items)));

  v_body := case when v_tier.id = 'nepo' then 'Dad has been in touch: you are now a Nepo baby.'
                 when v_tier.id = 'lapo' then 'Change of story: you are now a LAPO baby. Na hustle go carry you.'
                 else 'Your family background is now: ' || v_tier.name || '.' end
            || case when v_cash + v_bank > 0 or cardinality(v_items) > 0
                    then ' Sent to you: ' || concat_ws(', ',
                           case when v_cash > 0 then bl_naira(v_cash) || ' cash' end,
                           case when v_bank > 0 then bl_naira(v_bank) || ' to your bank' end,
                           case when cardinality(v_items) > 0 then
                             (select string_agg(it.name, ', ') from items it where it.id = any (v_items)) end) || '.'
                    else '' end;
  perform bl_event(p_user, 'origin_changed', 'Family news', v_body,
                   jsonb_build_object('from', v_old, 'to', v_tier.id, 'cash', v_cash, 'bank', v_bank, 'items', to_jsonb(v_items)));
  return jsonb_build_object('message', 'Origin changed from ' || v_old || ' to ' || v_tier.id || '.',
                            'old', v_old, 'new', v_tier.id, 'cash', v_cash, 'bank', v_bank, 'items', to_jsonb(v_items));
end $$;

-- Daily Dad allowance into bank (same behaviour as P1-ORIGIN; "Dad" copy).
create or replace function public.claim_allowance() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_amt   bigint;
  v_day   int := (bl_game_clock()->>'day')::int;
  v_bal   bigint;
begin
  v_amt := bl_origin_num(v_me.origin, 'allowance_daily')::bigint;
  if v_amt <= 0 then
    raise exception 'No Dad allowance for you. Na your own hustle go pay you, and e go sweet you pass.'
      using errcode = 'P0001', hint = 'no_allowance';
  end if;
  if v_me.jailed_until is not null and v_me.jailed_until > bl_now() then
    raise exception 'Dad heard you are in a police cell. He won''t send a kobo until you are out.' using errcode = 'P0001', hint = 'jailed';
  end if;
  if v_me.allowance_claimed_day is not distinct from v_day then
    raise exception 'Dad has already sent today''s allowance. Wait until tomorrow.' using errcode = 'P0001', hint = 'already_claimed';
  end if;
  update profiles set allowance_claimed_day = v_day where id = v_me.id;
  v_bal := bl_add_money(v_me.id, 'bank', v_amt, 'allowance', jsonb_build_object('origin', v_me.origin, 'day', v_day));
  return jsonb_build_object(
    'message', 'Dad sent ' || bl_naira(v_amt) || ' to your account. Spend it wisely.',
    'amount', v_amt, 'account', 'bank', 'bank', v_bal, 'day', v_day);
end $$;

-- Same as core but works before a home is chosen (the creator may go back to the Look step).
create or replace function public.update_avatar(p_avatar jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me_any();
begin
  if p_avatar is null or jsonb_typeof(p_avatar) <> 'object' or length(p_avatar::text) > 4000 then
    raise exception 'Your avatar data is not valid. Please try again.' using errcode = 'P0001';
  end if;
  update profiles set
    avatar = p_avatar,
    gender = case when p_avatar->>'gender' in ('male','female') then p_avatar->>'gender' else gender end
  where id = v_me.id;
  return jsonb_build_object('message', 'Your new look is saved. Looking good!');
end $$;

-- Same as core; plain-English labels/reasons (Pidgin kept for the keke banter).
create or replace function public.bl_travel_quote(p_me public.profiles, p_dest text) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  dst      locations := bl_location(p_dest);
  src      locations := bl_location(p_me.location_id);
  v_km     numeric;
  v_now    timestamptz := bl_now();
  v_traffic_road numeric;
  v_has_car boolean;
  v_opts   jsonb := '[]'::jsonb;
  m        text;
  v_label  text;
  v_speed  numeric; v_cost bigint; v_traffic numeric; v_gm int; v_rs numeric;
  v_allowed boolean; v_reason text;
  v_risk   numeric;
begin
  if dst.id = src.id then
    raise exception 'You are already at %.', dst.name using errcode = 'P0001';
  end if;
  v_km := bl_distance_km(src.id, dst.id);
  v_traffic_road := bl_traffic(src.id, dst.id, v_now);
  v_has_car := exists (select 1 from inventory i join items it on it.id = i.item_id
                       where i.user_id = p_me.id and i.qty > 0 and it.category = 'vehicle');

  foreach m in array array['walk','keke','bus','drop','car'] loop
    v_label := case m when 'walk' then 'Walk'
                      when 'keke' then 'Keke Napep'
                      when 'bus'  then 'ECTS Green Bus'
                      when 'drop' then 'Drop (ride-hail)'
                      else 'Your own car' end;
    v_speed := greatest(bl_cfg('travel.' || m || '.speed_kmh'), 0.1);
    v_cost  := (ceil((bl_cfg('travel.' || m || '.base_cost') + bl_cfg('travel.' || m || '.per_km') * v_km) / 10.0) * 10)::bigint;
    v_traffic := case when m = 'walk' then 1 else v_traffic_road end;
    v_gm := greatest(1, ceil(v_km / v_speed * 60 * v_traffic))::int;
    v_rs := round(greatest(bl_cfg('travel.min_real_seconds'),
                           v_gm * bl_cfg('travel.real_seconds_per_game_minute')), 1);
    v_allowed := true; v_reason := null;
    if m = 'keke' and not (src.keke_ok and dst.keke_ok) then
      v_allowed := false;
      v_reason := 'Keke no fit pass there. Keke is banned on the major roads.';
    elsif m = 'car' and not v_has_car then
      v_allowed := false;
      v_reason := 'You don''t have a motor yet. Buy one first.';
    elsif v_cost > p_me.cash then
      v_allowed := false;
      v_reason := 'Your money no reach for this one (' || bl_naira(v_cost) || ').';
    end if;
    v_risk := round(100 * bl_street_robbery_chance(p_me.id, dst.id, m, v_traffic,
                                                   v_now + make_interval(secs => v_rs::double precision)), 1);
    v_opts := v_opts || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'mode', m, 'label', v_label, 'allowed', v_allowed, 'reason', v_reason,
      'cost', v_cost, 'game_minutes', v_gm, 'real_seconds', v_rs, 'risk_pct', v_risk)));
  end loop;

  return jsonb_build_object('dest', dst.id, 'km', v_km, 'traffic', v_traffic_road, 'options', v_opts);
end $$;

create or replace function public.travel_start(p_dest text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_q     jsonb;
  v_opt   jsonb;
  v_now   timestamptz := bl_now();
  v_arr   timestamptz;
  v_name  text;
begin
  perform bl_assert_free(v_me);
  if p_mode is null or p_mode not in ('walk','keke','bus','drop','car') then
    raise exception 'That kind of transport doesn''t exist in Benin.' using errcode = 'P0001';
  end if;
  v_q := bl_travel_quote(v_me, p_dest);
  select o into v_opt from jsonb_array_elements(v_q->'options') o where o->>'mode' = p_mode;
  if not (v_opt->>'allowed')::boolean then
    raise exception '%', v_opt->>'reason' using errcode = 'P0001';
  end if;
  if (v_opt->>'cost')::bigint > 0 then
    perform bl_add_money(v_me.id, 'cash', -(v_opt->>'cost')::bigint, 'travel',
                         jsonb_build_object('from', v_me.location_id, 'to', p_dest, 'mode', p_mode));
  end if;
  v_arr := v_now + make_interval(secs => (v_opt->>'real_seconds')::double precision);
  update profiles set travel_to = p_dest, travel_mode = p_mode,
                      travel_started_at = v_now, travel_arrives_at = v_arr
  where id = v_me.id;
  select name into v_name from locations where id = p_dest;
  return jsonb_build_object(
    'message', case p_mode
                 when 'walk' then 'You set off on foot to ' || v_name || '.'
                 when 'keke' then 'A keke is taking you to ' || v_name || '. Hold your phone well.'
                 when 'bus'  then 'You boarded an ECTS bus to ' || v_name || '.'
                 when 'drop' then 'Your drop has arrived. Heading to ' || v_name || '.'
                 else 'You started your car. Heading to ' || v_name || '. Drive safely.' end,
    'arrives_at', v_arr,
    'cost', (v_opt->>'cost')::bigint,
    'game_minutes', (v_opt->>'game_minutes')::int,
    'real_seconds', (v_opt->>'real_seconds')::numeric);
end $$;

create or replace function public.travel_arrive() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me      profiles := bl_me();
  v_now     timestamptz := bl_now();
  v_from    text;
  v_dest    text;
  v_mode    text;
  v_traffic numeric;
  v_robbed  jsonb;
  v_name    text;
  v_msg     text;
begin
  if v_me.travel_to is null then
    raise exception 'You are not travelling right now.' using errcode = 'P0001';
  end if;
  if v_now < v_me.travel_arrives_at then
    raise exception 'You haven''t arrived yet! About % sec left.',
      ceil(extract(epoch from v_me.travel_arrives_at - v_now)) using errcode = 'P0001';
  end if;
  v_from := v_me.location_id; v_dest := v_me.travel_to; v_mode := v_me.travel_mode;
  v_traffic := case when v_mode = 'walk' then 1 else bl_traffic(v_from, v_dest, v_me.travel_started_at) end;

  update profiles set location_id = v_dest, travel_to = null, travel_mode = null,
                      travel_started_at = null, travel_arrives_at = null, last_seen = v_now
  where id = v_me.id;

  v_robbed := bl_roll_street_robbery(v_me.id, v_dest, v_mode, v_traffic);
  select name into v_name from locations where id = v_dest;

  if v_robbed is null then
    v_msg := 'You have arrived at ' || v_name || '.';
    return jsonb_build_object('message', v_msg, 'location', v_dest);
  end if;
  -- street moment: Pidgin stays
  v_msg := 'Omo! You reach ' || v_name || ' but some boys collect '
           || bl_naira((v_robbed->>'amount')::bigint) || ' from you. You fit report to the Police.'
           || case when (v_robbed->>'injured')::boolean
                   then ' Dem wound you small. Go to UBTH or a clinic quick.' else '' end;
  return jsonb_build_object('message', v_msg, 'location', v_dest, 'robbed', v_robbed);
end $$;

create or replace function public.do_activity(p_activity text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  a       activities;
  v_scene text;
  v_until timestamptz;
begin
  perform bl_assert_free(v_me);
  select * into a from activities where id = p_activity;
  if not found then
    raise exception 'That activity doesn''t exist.' using errcode = 'P0001';
  end if;
  select scene into v_scene from locations where id = v_me.location_id;
  if not (v_scene = any(a.scenes)) then
    raise exception 'You can''t do "%" here. Go where it is offered.', a.name using errcode = 'P0001';
  end if;
  if a.home_only and v_me.location_id <> v_me.home_location_id then
    raise exception 'You can only do "%" in your own home.', a.name using errcode = 'P0001';
  end if;
  if a.night_only and not (bl_game_clock()->>'is_night')::boolean then
    raise exception '"%" is a night-time thing. Come back after dark.', a.name using errcode = 'P0001';
  end if;
  if a.cost > 0 then
    perform bl_add_money(v_me.id, 'cash', -a.cost, 'activity', jsonb_build_object('activity', a.id));
  end if;
  perform bl_adjust_needs(v_me.id, a.effects);
  if coalesce((a.effects->>'street_cred')::int, 0) <> 0 then
    update profiles set street_cred = greatest(0, street_cred + (a.effects->>'street_cred')::int) where id = v_me.id;
  end if;
  v_until := bl_set_busy(v_me.id, a.game_minutes, a.name);
  return jsonb_build_object(
    'message', 'You started "' || a.name || '"'
               || case when a.cost > 0 then ' (' || bl_naira(a.cost) || ').' else '. Enjoy!' end,
    'busy_until', v_until,
    'effects', a.effects);
end $$;

-- Same as core; Sims still choosing a home are not shown.
create or replace function public.players_here(p_location text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar,
                                        'street_cred', p.street_cred, 'last_seen', p.last_seen)
                     order by p.last_seen desc)
    from (select * from profiles
          where location_id = p_location and id <> v_uid and not banned and travel_to is null and home_chosen
            and last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)
          order by last_seen desc limit 50) p
  ), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- 9. Function privileges
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'bl\_%' loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

revoke execute on function public.create_profile_v2(text, text, jsonb, text[], text) from public, anon;
revoke execute on function public.choose_start_home(text)                          from public, anon;
revoke execute on function public.admin_set_origin(uuid, text, boolean)            from public, anon;
revoke execute on function public.creator_catalog()                                from public;
grant execute on function public.create_profile_v2(text, text, jsonb, text[], text) to authenticated;
grant execute on function public.choose_start_home(text)                          to authenticated;
grant execute on function public.admin_set_origin(uuid, text, boolean)            to authenticated;
grant execute on function public.creator_catalog()                                to anon, authenticated;
-- redefined RPCs keep their grants (create or replace preserves them); restated for clarity
grant execute on function public.get_my_state()                    to authenticated;
grant execute on function public.create_profile(text, text, jsonb) to authenticated;
grant execute on function public.claim_allowance()                 to authenticated;
grant execute on function public.update_avatar(jsonb)              to authenticated;
grant execute on function public.travel_start(text, text)          to authenticated;
grant execute on function public.travel_arrive()                   to authenticated;
grant execute on function public.do_activity(text)                 to authenticated;
grant execute on function public.players_here(text)                to authenticated;
