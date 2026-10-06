-- L2 "Place interiors + real landmarks" (docs/PLACES.md).
-- * Data-driven interiors: place_zones (per location type = locations.scene, or per place) and zone_actions
--   (zone -> an existing activity / job track / shop item / panel), place_moods (rotating mood lines per
--   place type x part of day). All admin-editable (whitelisted tables) and readable by clients.
-- * Opening hours per place (locations.open_hour / close_hour; clubs 9 PM - 5 AM), enforced by do_activity
--   and shop_buy. Activities can be limited to some places (activities.location_ids), be Risky (a street
--   robbery roll at that place) or sell out at rush hour (activities.rush, Mama Ebo's pepper rice at lunch).
-- * Real Benin landmarks (docs/LANDMARKS.md) + a few made-up local places, new scenes: mall, cinema, hotel,
--   zoo, stadium, monument, car_dealer. Car dealers sell vehicle items; any vehicle in the Bag already
--   unlocks the "own car" travel mode (bl_travel_quote), and shop_buy now pays for a car bank first.
-- * place_interior(p_location) returns the whole interior (zones, action cards, mood lines, open state).
-- Idempotent and safe on a non-empty DB: seeds use "on conflict do nothing" (admin edits survive a re-run),
-- functions are re-created from their live definitions with the same grants.

-- ---------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------
alter table public.locations  add column if not exists open_hour  numeric;   -- null = always open
alter table public.locations  add column if not exists close_hour numeric;   -- may be < open_hour (past midnight)
alter table public.activities add column if not exists location_ids text[] not null default '{}'; -- empty = every place of its scenes
alter table public.activities add column if not exists risky boolean not null default false;      -- rolls a street robbery here
alter table public.activities add column if not exists rush jsonb not null default '{}'::jsonb;   -- {"from":12,"to":15,"pct":40,"line":"..."}
alter table public.activities add column if not exists icon text;                                 -- emoji for the action card

do $$ begin
  alter table public.locations add constraint locations_hours_chk
    check ((open_hour is null) = (close_hour is null)
           and (open_hour is null or (open_hour >= 0 and open_hour < 24 and close_hour >= 0 and close_hour <= 24)));
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------
create table if not exists public.place_zones (
  id          text primary key,                  -- 'club.bar' (type) or 'mama_ebo.counter' (one place)
  scene       text,                              -- location type (locations.scene) ...
  location_id text references public.locations(id) on delete cascade, -- ... or one place (same zone_key replaces the type's zone)
  zone_key    text not null,
  label       text not null,
  icon        text not null default '📍',
  prop        text not null default 'none',      -- what the 3D interior draws there (docs/PLACES.md "Props")
  x           numeric not null,                  -- zone centre in the interior (metres, x east, z towards the camera)
  z           numeric not null,
  w           numeric not null default 2,
  d           numeric not null default 2,
  rot         int not null default 0,            -- quarter turns
  note        text,                              -- small strip under the cards ("VIP prices for your table")
  sort        int not null default 0,
  active      boolean not null default true,
  constraint place_zones_scope_chk check ((scene is null) <> (location_id is null)),
  constraint place_zones_size_chk check (x >= 0 and z >= 0 and w > 0 and d > 0 and x <= 60 and z <= 60 and w <= 30 and d <= 30)
);
create unique index if not exists place_zones_key_uq on public.place_zones (coalesce(scene, ''), coalesce(location_id, ''), zone_key);

create table if not exists public.zone_actions (
  id       text primary key,                     -- 'club.bar.lounge_chill'
  zone_id  text not null references public.place_zones(id) on delete cascade,
  kind     text not null check (kind in ('activity', 'job', 'shop', 'panel')),
  ref      text not null,                        -- activities.id | career_tracks.id | items.id | panel id
  label    text,                                 -- optional card title override
  icon     text,
  sort     int not null default 0,
  active   boolean not null default true
);
create unique index if not exists zone_actions_ref_uq on public.zone_actions (zone_id, kind, ref);

create table if not exists public.place_moods (
  id          text primary key,
  scene       text,
  location_id text references public.locations(id) on delete cascade,
  part        text not null default 'any' check (part in ('any', 'morning', 'afternoon', 'evening', 'night')),
  icon        text not null default '✨',
  line        text not null,
  sort        int not null default 0,
  active      boolean not null default true,
  constraint place_moods_scope_chk check ((scene is null) <> (location_id is null))
);

alter table public.place_zones  enable row level security;
alter table public.zone_actions enable row level security;
alter table public.place_moods  enable row level security;
revoke all on table public.place_zones, public.zone_actions, public.place_moods from public, anon, authenticated;
grant select on table public.place_zones, public.zone_actions, public.place_moods to anon, authenticated;
drop policy if exists place_zones_read on public.place_zones;
create policy place_zones_read on public.place_zones for select using (true);
drop policy if exists zone_actions_read on public.zone_actions;
create policy zone_actions_read on public.zone_actions for select using (true);
drop policy if exists place_moods_read on public.place_moods;
create policy place_moods_read on public.place_moods for select using (true);

-- every zone action must point at something that exists (no polymorphic FK, so a trigger checks it,
-- for seeds and admin edits alike)
create or replace function public.bl_zone_action_check() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.kind = 'activity' and not exists (select 1 from activities where id = new.ref) then
    raise exception 'Zone action %: no activity "%".', new.id, new.ref using errcode = 'P0001', hint = 'bad_value';
  elsif new.kind = 'shop' and not exists (select 1 from items where id = new.ref) then
    raise exception 'Zone action %: no item "%".', new.id, new.ref using errcode = 'P0001', hint = 'bad_value';
  elsif new.kind = 'job' and not exists (select 1 from career_tracks where id = new.ref) then
    raise exception 'Zone action %: no career track "%".', new.id, new.ref using errcode = 'P0001', hint = 'bad_value';
  elsif new.kind = 'panel' and new.ref not in ('shop', 'jobs', 'bank', 'pos', 'activities', 'chat', 'inventory') then
    raise exception 'Zone action %: "%" is not a place tab (shop, jobs, bank, pos, activities, chat, inventory).', new.id, new.ref
      using errcode = 'P0001', hint = 'bad_value';
  end if;
  return new;
end $$;
drop trigger if exists zone_actions_check on public.zone_actions;
create trigger zone_actions_check before insert or update on public.zone_actions
  for each row execute function public.bl_zone_action_check();

create or replace function public.bl_place_zone_check() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.scene is not null and not exists (select 1 from locations where scene = new.scene) then
    raise exception 'Zone %: no place has the type "%".', new.id, new.scene using errcode = 'P0001', hint = 'bad_value';
  end if;
  return new;
end $$;
drop trigger if exists place_zones_check on public.place_zones;
create trigger place_zones_check before insert or update on public.place_zones
  for each row execute function public.bl_place_zone_check();

revoke execute on function public.bl_zone_action_check() from public, anon, authenticated;
revoke execute on function public.bl_place_zone_check()  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Config
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('places.hours_enabled', 'true', 'places', 'Opening hours on',
 'Places with opening hours (clubs 9 PM - 5 AM, cinema, zoo, mall) refuse actions and purchases while closed. Hours per place: Content -> Places.', 'bool', null, null),
('places.mood_seconds', '7', 'places', 'Mood line rotates every (s)',
 'Seconds between mood lines on the place card inside a place.', 'number', 3, 60),
('places.npc_per_zone', '2', 'places', 'Extra people per zone (busy hour)',
 'Background people drawn per zone at the busiest hour of that kind of place (fewer at quiet hours).', 'number', 0, 6),
('crowd.max_visible', '10', 'places', 'Max people drawn inside a place',
 'Render cap for people inside a place (real players first, then background people). The People count still shows everyone.', 'number', 0, 30),
('cars.bank_first', 'true', 'places', 'Cars paid from the bank first',
 'Buying a car at a dealer takes the money from the bank first, then cash (cars cost millions).', 'bool', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 4. Real landmarks + made-up local places (docs/LANDMARKS.md; positions keep pins >= 34 units apart)
-- ---------------------------------------------------------------------
insert into public.locations (id, name, district, scene, blurb, risk, night_risk_mult, cctv, keke_ok, congestion, remote_km, x, y, actions, sort, open_hour, close_hour) values
('emotan_statue', 'Emotan Statue', 'oredo', 'monument',
 'The 1954 statue of Emotan, the market woman who saved a prince, right opposite Oba Market. Locals still greet her with respect.',
 .20, 1.6, true, false, 1.4, 0, 468, 482, '{activities}', 41, null, null),
('kada_plaza', 'Kada Plaza (Kada Cinemas)', 'sapele_rd', 'cinema',
 'Kada Cinemas and Kada Fried Chicken on Old Sapele Rd. Blockbusters, popcorn and a hot chicken counter.',
 .20, 1.5, true, true, 1.3, 0, 554, 605, '{activities,shop}', 42, 10, 24),
('benin_city_mall', 'Benin City Mall (ShopRite)', 'sapele_rd', 'mall',
 'ShopRite, Genesis Cinema and about sixty shops under one cool roof on Sapele Rd.',
 .12, 1.3, true, true, 1.4, 0, 575, 665, '{shop,activities}', 43, 9, 22),
('mama_ebo', 'Mama Ebo Pepper Rice', 'airport_rd', 'buka',
 'The pepper rice everybody talks about, 88 Airport Rd. Come early: it sells out at lunch.',
 .18, 1.5, false, true, 1.2, 0, 405, 588, '{activities,shop}', 44, null, null),
('protea_hotel', 'Protea Hotel Emotan', 'gra', 'hotel',
 'Protea Hotel by Marriott, Central Rd off Sapele Rd. Pool, lounge and the softest beds in town.',
 .08, 1.2, true, false, 1.1, 0, 509, 642, '{activities}', 45, null, null),
('golden_tulip', 'Golden Tulip Essential', 'gra', 'hotel',
 'GRA hotel on Etete Rd (the old Excalibur). Pool parties, buffet and a quiet lounge.',
 .08, 1.2, true, false, 1.0, 0, 486, 670, '{activities}', 46, null, null),
('ogba_zoo', 'Ogba Zoo & Nature Park', 'airport_rd', 'zoo',
 '750 acres of bush past the airport, open since 1971. Lions, chimps, ostriches and shady picnic spots.',
 .15, 1.8, false, true, 1.0, 0, 290, 690, '{activities,shop}', 47, 8, 18),
('ogbemudia_stadium', 'Samuel Ogbemudia Stadium', 'ekenwan', 'stadium',
 'Home of Bendel Insurance FC, off Ekenwan Rd. Match days are loud; the track is open for joggers.',
 .25, 1.8, true, false, 1.3, 0, 372, 532, '{activities,shop}', 48, null, null),
('club_360', '360 Signature', 'gra', 'club',
 'Top-floor club on 1st Ugbor Rd, GRA. Bottles with sparklers, a loud hype man and big spenders.',
 .15, 1.4, true, false, 1.1, 0, 483, 706, '{activities,shop}', 49, 21, 5),
('club_de_medici', 'Club De Medici', 'gra', 'club',
 'Benoni Rd off Airport Rd. VIP booths, Afrobeats till dawn and a DJ who knows your name.',
 .15, 1.4, true, false, 1.1, 0, 386, 638, '{activities,shop}', 50, 21, 5),
('rome_club', 'Rome Night Club', 'sapele_rd', 'club',
 'They call it the biggest club in Benin. Huge dance floor, smoke machines, owambe energy.',
 .25, 1.6, true, false, 1.2, 0, 530, 735, '{activities,shop}', 51, 21, 5),
('cube_nightlife', 'Cube Nightlife', 'airport_rd', 'club',
 'Ihama Rd off Airport Rd. Neon cube bar, amapiano nights and a packed VIP section.',
 .20, 1.5, true, false, 1.2, 0, 445, 582, '{activities,shop}', 52, 21, 5),
('versus_lounge', 'Versus Lounge', 'gra', 'club',
 'Guobadia Ave off 1st Ugbor Rd. Shisha, cocktails and a DJ booth that turns into a party after 11.',
 .15, 1.4, true, false, 1.1, 0, 432, 616, '{activities,shop}', 53, 21, 5),
('owambe_republic', 'Owambe Republic', 'ikpoba_hill', 'club',
 'Ikpoba Hill''s own (made-up) party spot: live band, cheap Star and a hype man called Sweet Mouth.',
 .35, 1.8, false, true, 1.2, 0, 735, 560, '{activities,shop}', 54, 21, 5),
('ighodalo_cars', 'Ighodalo Car Deals', 'sapele_rd', 'car_dealer',
 'Km 5 Sapele Rd. Clean tokunbo saloons and SUVs, "first body", with papers.',
 .20, 1.6, true, false, 1.2, 0, 528, 815, '{shop,activities}', 55, null, null),
('sdd_motors', 'SDD Motors', 'sapele_rd', 'car_dealer',
 '174 Sapele Rd. Big showroom with brand-new and fairly-used cars.',
 .15, 1.5, true, false, 1.2, 0, 585, 740, '{shop,activities}', 56, null, null),
('tokunbo_lot', 'Sapele Rd Tokunbo Lot', 'sapele_rd', 'car_dealer',
 'A (made-up) dusty lot of Belgium-used cars. Haggle hard; the man in the cap always says "last price".',
 .35, 1.8, false, true, 1.2, 0, 575, 850, '{shop,activities}', 57, null, null)
on conflict (id) do nothing;

-- clubs open at night only (existing clubs too); admin-editable per place (Content -> Places)
update public.locations set open_hour = 21, close_hour = 5
 where scene = 'club' and open_hour is null and id in ('bronze_lounge', 'kingdom_lounge');

-- ---------------------------------------------------------------------
-- 5. Activities (new; existing ones keep their values)
-- ---------------------------------------------------------------------
insert into public.activities (id, name, scenes, home_only, cost, game_minutes, effects, night_only, sort, max_seconds, min_seconds, scale_by_need, location_ids, risky, rush, icon) values
-- clubs
('club_dance',     'Dance to the DJ',                       '{club}',       false, 0,      60, '{"fun": 25, "social": 15, "energy": -10, "hygiene": -5, "bladder": -5}', false, 300, 12, 6, false, '{}', false, '{}', '💃'),
('vip_table',      'VIP table + bottle service',            '{club}',       false, 150000, 90, '{"fun": 45, "social": 40, "stress": -20, "bladder": -15, "street_cred": 3}', false, 301, 15, 8, false, '{}', false, '{}', '🍾'),
('spray_money',    'Spray money on the dance floor',        '{club}',       false, 50000,  30, '{"fun": 30, "social": 25, "street_cred": 2}', false, 302, 8, 4, false, '{}', true, '{}', '💸'),
('hype_shoutout',  'Hype man shout-out',                    '{club}',       false, 100000, 20, '{"fun": 25, "social": 35, "stress": -8, "street_cred": 5}', false, 303, 6, 4, false, '{}', false, '{}', '🎤'),
-- cinema + mall
('watch_film',     'Watch a Nollywood blockbuster',         '{cinema,mall}', false, 3500,  120, '{"fun": 40, "stress": -12, "social": 5}', false, 310, 14, 8, false, '{}', false, '{}', '🎬'),
('watch_film_vip', 'VIP recliner + popcorn combo',          '{cinema,mall}', false, 9000,  120, '{"fun": 48, "stress": -16, "hunger": 10, "social": 5}', false, 311, 14, 8, false, '{}', false, '{}', '🍿'),
('arcade_games',   'Arcade games',                          '{cinema}',     false, 1500,   30, '{"fun": 22, "stress": -5}', false, 312, 8, 4, false, '{}', false, '{}', '🕹️'),
('mall_stroll',    'Window-shop around the mall',           '{mall}',       false, 0,      45, '{"fun": 12, "social": 8, "energy": -4}', false, 313, 8, 4, false, '{}', false, '{}', '🛍️'),
-- hotels
('hotel_pool',     'Swim in the hotel pool',                '{hotel}',      false, 7500,   60, '{"fun": 30, "hygiene": 15, "stress": -15, "energy": -8}', false, 320, 12, 6, false, '{}', false, '{}', '🏊'),
('hotel_sleep',    'Luxury suite sleep',                    '{hotel}',      false, 60000, 480, '{"energy": 100, "health": 8, "stress": -35, "hygiene": 20}', false, 321, 15, 4, true, '{}', false, '{}', '🛏️'),
('hotel_lounge',   'Cocktails at the hotel lounge',         '{hotel}',      false, 12000,  60, '{"fun": 22, "social": 22, "stress": -10, "bladder": -12}', false, 322, 10, 5, false, '{}', false, '{}', '🍸'),
('hotel_buffet',   'Hotel buffet',                          '{hotel}',      false, 15000,  45, '{"hunger": 70, "fun": 10}', false, 323, 6, 3, true, '{}', false, '{}', '🍽️'),
-- zoo
('zoo_trip',       'See the lions and chimps',              '{zoo}',        false, 2000,  120, '{"fun": 35, "social": 10, "stress": -12, "energy": -8}', false, 330, 14, 8, false, '{}', false, '{}', '🦁'),
('zoo_birds',      'Feed the ostriches',                    '{zoo}',        false, 1000,   40, '{"fun": 20, "stress": -6}', false, 331, 8, 4, false, '{}', false, '{}', '🦤'),
('zoo_picnic',     'Picnic under the trees',                '{zoo}',        false, 1500,   60, '{"fun": 15, "social": 20, "stress": -10, "hunger": 15}', false, 332, 10, 5, false, '{}', false, '{}', '🧺'),
-- stadium
('match_day',      'Match day in the popular stand',        '{stadium}',    false, 1000,  120, '{"fun": 40, "social": 30, "stress": -10, "energy": -8, "bladder": -10}', false, 340, 15, 8, false, '{}', false, '{}', '⚽'),
('match_vip',      'VIP stand with the big men',            '{stadium}',    false, 10000, 120, '{"fun": 45, "social": 30, "stress": -12, "street_cred": 1}', false, 341, 15, 8, false, '{}', false, '{}', '🎟️'),
('stadium_jog',    'Jog round the track',                   '{stadium}',    false, 0,      40, '{"energy": -12, "stress": -12, "health": 4, "hygiene": -8}', false, 342, 10, 5, false, '{}', false, '{}', '🏃'),
-- Emotan (respectful)
('emotan_photo',   'Photo at the Emotan statue',            '{monument}',   false, 0,      15, '{"fun": 10, "social": 10}', false, 350, 6, 3, false, '{}', false, '{}', '📸'),
('emotan_history', 'Hear Emotan''s story from a guide',     '{monument}',   false, 500,    40, '{"fun": 15, "stress": -8, "social": 5}', false, 351, 12, 6, false, '{}', false, '{}', '📜'),
('people_watch',   'Sit and people-watch',                  '{monument,street}', false, 0,  30, '{"stress": -6, "social": 5, "energy": 3}', false, 352, 8, 4, false, '{}', false, '{}', '👀'),
-- Mama Ebo (only there; sells out at lunch)
('pepper_rice',    'Mama Ebo''s pepper rice + turkey',      '{buka}',       false, 3500,   30, '{"hunger": 65, "fun": 12}', false, 360, 5, 3, true, '{mama_ebo}', false,
 '{"from": 12, "to": 15, "pct": 40, "line": "Pepper rice don finish! The lunch crowd cleared the pot. Mama Ebo says the next one is ready in a bit."}', '🌶️'),
-- car dealers
('test_drive',     'Test-drive a tokunbo',                  '{car_dealer}', false, 0,      30, '{"fun": 20, "stress": -5}', false, 370, 10, 5, false, '{}', false, '{}', '🚗'),
('haggle_dealer',  'Haggle with the dealer',                '{car_dealer}', false, 0,      20, '{"social": 12, "fun": 6, "stress": 3}', false, 371, 6, 3, false, '{}', false, '{}', '🤝'),
-- gaps in the old types (so every zone has something to do)
('checkup',        'Quick check-up with a nurse',           '{hospital}',   false, 2500,   30, '{"health": 20, "stress": -5}', false, 380, 10, 5, false, '{}', false, '{}', '🩺'),
('ward_rest',      'Rest on a ward bed with a drip',        '{hospital}',   false, 4000,   60, '{"health": 15, "energy": 20, "stress": -6}', false, 381, 12, 6, true, '{}', false, '{}', '💧'),
('attend_lecture', 'Sit in on a lecture',                   '{campus}',     false, 0,      60, '{"social": 10, "fun": 4, "energy": -6}', false, 382, 12, 6, false, '{}', false, '{}', '📚'),
('library_read',   'Read in the library',                   '{campus}',     false, 0,      60, '{"stress": -8, "fun": 6, "energy": -3}', false, 383, 12, 6, false, '{}', false, '{}', '📖'),
('bank_cool_off',  'Cool off under the banking hall AC',    '{bank}',       false, 0,      15, '{"stress": -4, "energy": 2}', false, 384, 6, 3, false, '{}', false, '{}', '❄️'),
('police_statement','Make a statement at the counter',      '{police}',     false, 0,      30, '{"stress": -5, "social": 3}', false, 385, 8, 4, false, '{}', false, '{}', '📝'),
('shrine_consult', 'Consult Baba (divination)',             '{shrine}',     false, 2000,   30, '{"stress": -15, "fun": 5}', false, 386, 10, 5, false, '{}', false, '{}', '🪔'),
('shrine_quiet',   'Sit quietly in the courtyard',          '{shrine}',     false, 0,      20, '{"stress": -8}', false, 387, 8, 4, false, '{}', false, '{}', '🕯️'),
('palace_chiefs',  'Watch the chiefs arrive (from a respectful distance)', '{palace}', false, 0, 30, '{"fun": 12, "social": 6}', false, 388, 10, 5, false, '{}', false, '{}', '🪶'),
('museum_guide',   'Guided tour with a curator',            '{museum}',     false, 1500,   60, '{"fun": 22, "stress": -10, "social": 8}', false, 389, 12, 6, false, '{}', false, '{}', '🗿'),
('side_project',   'Hack on a side project',                '{office,cyber}', false, 0,    60, '{"fun": 15, "energy": -6}', false, 390, 14, 7, false, '{}', false, '{}', '👩🏾‍💻'),
('farm_walk',      'Walk the cassava rows',                 '{farm}',       false, 0,      40, '{"fun": 8, "stress": -8, "energy": -6}', false, 391, 10, 5, false, '{}', false, '{}', '🌱'),
('pos_banter',     'Banter in the PoS line',                '{pos}',        false, 0,      20, '{"social": 10, "fun": 4}', false, 392, 6, 3, false, '{}', false, '{}', '💬'),
('night_stroll',   'Late-night stroll with the boys',       '{street}',     false, 0,      40, '{"fun": 15, "social": 15, "stress": -5}', true, 393, 10, 5, false, '{}', true, '{}', '🌙')
on conflict (id) do nothing;

-- icons for the existing activities (cards); only where none was set
update public.activities a set icon = v.icon from (values
  ('owo_soup','🍲'),('banga_starch','🍛'),('black_soup','🥘'),('noodles_egg','🍜'),('pepper_soup','🌶️'),('suya','🍢'),
  ('gist_joint','🗣️'),('watch_football','📺'),('club_night','🪩'),('lounge_chill','🍹'),('museum_tour','🏛️'),
  ('palace_visit','👑'),('campus_stroll','🚶🏾'),('bronze_casting','🔥'),('market_stroll','🧺'),('cyber_browse','🌐'),
  ('salon_freshen','💈'),('plane_spotting','✈️'),('ease_yourself','🚻'),('public_toilet','🚻'),('office_coffee','☕'),
  ('tech_meetup','🎤'),('sleep','😴'),('nap','💤'),('bathe','🚿'),('use_toilet','🚽'),('cook_home','🍳'),('watch_tv','📺'),
  ('listen_radio','📻'),('sit_rest','🪑'),('relax_sofa','🛋️'),('cold_drink','🥤')
) v(id, icon) where a.id = v.id and a.icon is null;

-- ---------------------------------------------------------------------
-- 6. Items: Kada chicken, popcorn, ShopRite, cars
-- ---------------------------------------------------------------------
insert into public.items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort) values
('kada_chicken', 'Kada fried chicken + chips', 'food', 3000, 'Crispy, hot, a little peppery. The Kada Plaza classic.',
 '{"hunger": 40, "fun": 6}', '{kada_plaza}', false, 0, '🍗', 120),
('popcorn', 'Popcorn + soft drink', 'food', 1500, 'Cinema popcorn, salty-sweet, with a cold drink.',
 '{"hunger": 10, "fun": 6, "bladder": -8}', '{kada_plaza,benin_city_mall}', false, 0, '🍿', 121),
('meat_pie', 'Meat pie', 'food', 1200, 'Flaky pastry, minced meat and potato. From the mall bakery.',
 '{"hunger": 18, "fun": 3}', '{benin_city_mall,ogbemudia_stadium,ogba_zoo}', false, 0, '🥧', 122),
('cornflakes_milk', 'Cornflakes + milk (ShopRite)', 'food', 4500, 'A box of cornflakes and a tin of milk. Breakfast sorted.',
 '{"hunger": 35, "energy": 4}', '{benin_city_mall}', false, 0, '🥣', 123),
('club_bottle', 'Bottle of champagne (club price)', 'drink', 45000, 'Comes with sparklers and a waiter who shouts your name.',
 '{"fun": 20, "social": 15, "bladder": -15, "energy": -4}', '{club_360,club_de_medici,rome_club,cube_nightlife,versus_lounge,owambe_republic}', false, 0, '🍾', 124),
('star_beer', 'Cold Star (club)', 'drink', 1500, 'Ice-cold lager. Pace yourself.',
 '{"fun": 8, "social": 4, "bladder": -12}', '{club_360,club_de_medici,rome_club,cube_nightlife,versus_lounge,owambe_republic}', false, 0, '🍺', 125),
('kia_rio_used', 'Fairly-used Kia Rio', 'vehicle', 1800000, 'Small, thirsty for nothing, AC works (most days).',
 '{}', '{tokunbo_lot,ighodalo_cars}', true, 55, '🚙', 300),
('camry_muscle', 'Toyota Camry "Muscle" (tokunbo)', 'vehicle', 6500000, 'The 2008 Camry every Benin big boy started with.',
 '{}', '{ighodalo_cars,sdd_motors}', true, 60, '🚘', 302),
('lexus_rx350', 'Lexus RX 350 (tokunbo)', 'vehicle', 18000000, 'Leather seats, reverse camera, maximum respect at the gate.',
 '{}', '{ighodalo_cars,sdd_motors}', true, 60, '🚙', 303),
('hilux_new', 'Brand-new Toyota Hilux', 'vehicle', 45000000, 'Straight from the showroom. Plates, papers, the works.',
 '{}', '{sdd_motors}', true, 65, '🛻', 304)
on conflict (id) do nothing;

-- the Tokunbo Corolla (Nepo starter car) is now sold at the dealers too
update public.items set sold_at = (select array_agg(distinct e order by e) from unnest(sold_at || '{tokunbo_lot,ighodalo_cars,sdd_motors}'::text[]) e)
 where id = 'tokunbo_car' and not ('tokunbo_lot' = any (sold_at));
-- ShopRite at Benin City Mall stocks some everyday items
update public.items set sold_at = sold_at || '{benin_city_mall}'::text[]
 where id in ('bottled_water', 'malt_drink', 'noodles_pack', 'soap', 'toothpaste', 'pain_relief', 'data_bundle', 'airtime', 'laptop', 'jollof_pack')
   and not ('benin_city_mall' = any (sold_at));
update public.items set sold_at = sold_at || '{mama_ebo}'::text[]
 where id in ('jollof_pack', 'zobo', 'malt_drink', 'pure_water') and not ('mama_ebo' = any (sold_at));
update public.items set sold_at = sold_at || '{ogbemudia_stadium}'::text[]
 where id in ('suya_stick', 'malt_drink', 'pure_water', 'puff_puff') and not ('ogbemudia_stadium' = any (sold_at));
update public.items set sold_at = sold_at || '{ogba_zoo}'::text[]
 where id in ('pure_water', 'malt_drink', 'puff_puff') and not ('ogba_zoo' = any (sold_at));

-- ---------------------------------------------------------------------
-- 7. Zones per location type (+ a few per place). Interior space: x 0..W (east), z 0..D (front, towards
--    the camera); the room is sized from the zones (docs/PLACES.md).
-- ---------------------------------------------------------------------
insert into public.place_zones (id, scene, location_id, zone_key, label, icon, prop, x, z, w, d, rot, note, sort) values
-- market (outdoor)
('market.foodstuff', 'market', null, 'foodstuff', 'Foodstuff stall', '🧺', 'stall',      3.5, 3.0, 3.2, 2.2, 0, null, 1),
('market.drinks',    'market', null, 'drinks',    'Drinks & snacks', '🥤', 'stall',      8.5, 3.0, 3.2, 2.2, 0, null, 2),
('market.mama_put',  'market', null, 'mama_put',  'Mama Put corner', '🍛', 'food_stall', 13.0, 4.5, 2.6, 2.4, 3, null, 3),
('market.traders',   'market', null, 'traders',   'Traders'' row',    '🧑🏾‍🌾', 'stall',      3.5, 8.0, 3.2, 2.2, 2, null, 4),
('market.loading',   'market', null, 'loading',   'Loading bay',     '📦', 'crates',     9.0, 8.5, 3.0, 2.2, 0, null, 5),
('market.toilet',    'market', null, 'toilet',    'Public toilet',   '🚻', 'restroom',   14.6, 1.6, 1.6, 1.6, 3, null, 6),
-- buka
('buka.counter',  'buka', null, 'counter', 'Food counter',  '🍲', 'counter',  3.0, 2.0, 4.0, 1.4, 0, null, 1),
('buka.tables',   'buka', null, 'tables',  'Tables',        '🪑', 'tables',   6.5, 5.5, 4.0, 3.0, 0, null, 2),
('buka.tv',       'buka', null, 'tv',      'TV corner',     '📺', 'tv_screen', 10.5, 2.0, 2.4, 1.4, 0, null, 3),
('buka.restroom', 'buka', null, 'restroom','Restroom',      '🚻', 'restroom', 1.0, 6.0, 1.6, 1.6, 1, null, 4),
-- Mama Ebo: the pepper rice counter replaces the plain counter
('mama_ebo.counter', null, 'mama_ebo', 'counter', 'Pepper rice counter', '🌶️', 'counter', 3.0, 2.0, 4.0, 1.4, 0, 'Lunch rush 12-3 PM: the pot can run out.', 1),
-- club / lounge
('club.bar',        'club', null, 'bar',        'Bar',         '🍹', 'bar',         2.6, 2.2, 4.2, 1.4, 0, null, 1),
('club.dance',      'club', null, 'dance',      'Dance floor', '🪩', 'dance_floor', 7.0, 5.6, 4.4, 4.0, 0, null, 2),
('club.dj',         'club', null, 'dj',         'DJ booth',    '🎧', 'dj_booth',    7.0, 1.6, 2.6, 1.4, 0, null, 3),
('club.vip',        'club', null, 'vip',        'VIP section', '👑', 'vip',         12.0, 3.0, 3.2, 3.2, 3, 'VIP prices for your table', 4),
('club.screens',    'club', null, 'screens',    'Sports screen', '📺', 'tv_screen', 12.0, 8.0, 2.4, 1.4, 3, null, 5),
('club.restroom',   'club', null, 'restroom',   'Restroom',    '🚻', 'restroom',    1.0, 6.2, 1.6, 1.6, 1, null, 6),
-- bank hall
('bank.counter', 'bank', null, 'counter', 'Teller counter', '🏦', 'bank_counter', 5.5, 1.8, 6.0, 1.2, 0, null, 1),
('bank.atm',     'bank', null, 'atm',     'ATM gallery',    '🏧', 'atm',          10.5, 5.0, 1.4, 2.4, 3, null, 2),
('bank.waiting', 'bank', null, 'waiting', 'Waiting chairs', '💺', 'seats',        4.5, 6.0, 4.0, 2.0, 0, null, 3),
-- hospital
('hospital.reception', 'hospital', null, 'reception', 'Reception',  '🩺', 'counter',  3.0, 2.0, 3.6, 1.2, 0, null, 1),
('hospital.pharmacy',  'hospital', null, 'pharmacy',  'Pharmacy',   '💊', 'shelves',  9.5, 1.8, 3.2, 1.0, 0, null, 2),
('hospital.ward',      'hospital', null, 'ward',      'Ward beds',  '🛏️', 'beds',     8.5, 6.5, 4.4, 3.0, 0, null, 3),
('hospital.staff',     'hospital', null, 'staff',     'Staff room', '🧑🏾‍⚕️', 'desk', 2.5, 7.0, 2.4, 1.6, 0, null, 4),
('hospital.restroom',  'hospital', null, 'restroom',  'Restroom',   '🚻', 'restroom', 12.6, 4.4, 1.6, 1.6, 3, null, 5),
-- campus
('campus.lecture',  'campus', null, 'lecture',  'Lecture hall', '📚', 'lecture',  4.5, 3.5, 6.0, 4.0, 0, null, 1),
('campus.library',  'campus', null, 'library',  'Library',      '📖', 'shelves',  11.5, 2.0, 3.2, 1.2, 0, null, 2),
('campus.quad',     'campus', null, 'quad',     'The quad',     '🌳', 'trees',    11.0, 7.0, 3.6, 3.0, 0, null, 3),
('campus.staff',    'campus', null, 'staff',    'Staff office', '🧑🏾‍🏫', 'desk',   3.0, 8.5, 2.4, 1.6, 0, null, 4),
('campus.restroom', 'campus', null, 'restroom', 'Restroom',     '🚻', 'restroom', 14.4, 4.2, 1.6, 1.6, 3, null, 5),
-- motor park (outdoor)
('motorpark.buses', 'motorpark', null, 'buses', 'Loading buses',  '🚌', 'bus',      5.0, 3.0, 6.0, 2.2, 0, null, 1),
('motorpark.keke',  'motorpark', null, 'keke',  'Keke rank',      '🛺', 'keke',     12.5, 3.0, 3.0, 2.0, 0, null, 2),
('motorpark.suya',  'motorpark', null, 'suya',  'Suya spot',      '🍢', 'grill',    3.0, 8.5, 2.2, 1.6, 0, null, 3),
('motorpark.kiosk', 'motorpark', null, 'kiosk', 'Kiosk',          '🥤', 'kiosk',    8.0, 9.0, 2.2, 1.6, 0, null, 4),
('motorpark.bench', 'motorpark', null, 'bench', 'Drivers'' bench', '🗣️', 'bench',   12.5, 8.5, 2.6, 1.2, 0, null, 5),
('motorpark.toilet','motorpark', null, 'toilet','Public toilet',  '🚻', 'restroom', 15.5, 6.0, 1.6, 1.6, 3, null, 6),
-- PoS stand (outdoor)
('pos.kiosk',   'pos', null, 'kiosk',   'PoS kiosk',     '💳', 'kiosk',  3.5, 2.5, 2.6, 1.6, 0, null, 1),
('pos.airtime', 'pos', null, 'airtime', 'Airtime & data','📶', 'stall',  8.5, 2.5, 2.6, 1.8, 0, null, 2),
('pos.line',    'pos', null, 'line',    'The line',      '🧍🏾', 'bench', 5.5, 6.5, 3.0, 1.2, 0, null, 3),
-- police station
('police.desk',  'police', null, 'desk',  'Front desk',   '📝', 'counter', 4.0, 2.0, 4.0, 1.2, 0, null, 1),
('police.bench', 'police', null, 'bench', 'Waiting bench','💺', 'bench',   4.0, 6.5, 3.0, 1.2, 0, null, 2),
('police.board', 'police', null, 'board', 'Wanted board', '📌', 'board',   10.0, 1.2, 2.4, 0.4, 0, null, 3),
-- palace (respectful) + museum
('palace.gate',      'palace', null, 'gate',      'Palace gate',  '👑', 'gate',      8.0, 9.5, 4.0, 1.0, 0, null, 1),
('palace.courtyard', 'palace', null, 'courtyard', 'Courtyard',    '🪶', 'courtyard', 8.0, 5.0, 6.0, 4.0, 0, null, 2),
('palace.bronzes',   'palace', null, 'bronzes',   'Bronze plaques','🗿', 'display',  3.0, 2.0, 3.0, 1.0, 0, null, 3),
('museum.gallery',   'museum', null, 'gallery',   'Bronze gallery','🏛️', 'display',  4.0, 2.0, 5.0, 1.2, 0, null, 1),
('museum.heads',     'museum', null, 'heads',     'Royal heads',   '🗿', 'pedestals',9.5, 5.5, 3.6, 2.4, 0, null, 2),
('museum.shop',      'museum', null, 'shop',      'Gift corner',   '🎁', 'shelves',  3.0, 7.5, 2.4, 1.0, 1, null, 3),
-- tech hub (office) + cyber
('office.desks',    'office', null, 'desks',    'Hot desks',    '💻', 'desks',     4.0, 3.5, 5.0, 3.0, 0, null, 1),
('office.coffee',   'office', null, 'coffee',   'Coffee bar',   '☕', 'bar',       11.0, 2.0, 3.0, 1.2, 0, null, 2),
('office.stage',    'office', null, 'stage',    'Event stage',  '🎤', 'stage',     10.5, 7.0, 3.6, 2.4, 3, null, 3),
('office.restroom', 'office', null, 'restroom', 'Restroom',     '🚻', 'restroom',  1.0, 7.0, 1.6, 1.6, 1, null, 4),
('cyber.desks',  'cyber', null, 'desks',  'Computers',    '🖥️', 'desks',   4.0, 3.0, 5.0, 3.0, 0, null, 1),
('cyber.snacks', 'cyber', null, 'snacks', 'Snack corner', '🍜', 'counter', 9.5, 6.5, 2.4, 1.2, 3, null, 2),
-- street (outdoor)
('street.suya',   'street', null, 'suya',   'Suya grill',      '🍢', 'grill',     3.0, 3.0, 2.2, 1.6, 0, null, 1),
('street.screen', 'street', null, 'screen', 'Viewing centre',  '📺', 'tv_screen', 9.0, 2.5, 3.0, 1.4, 0, null, 2),
('street.corner', 'street', null, 'corner', 'Junction corner', '🗣️', 'bench',     5.0, 8.0, 3.0, 1.2, 0, null, 3),
('street.toilet', 'street', null, 'toilet', 'Public toilet',   '🚻', 'restroom',  13.6, 1.8, 1.6, 1.6, 3, null, 4),
-- shrine (respectful)
('shrine.altar',     'shrine', null, 'altar',     'Shrine room', '🪔', 'altar',     5.0, 2.5, 3.0, 2.0, 0, null, 1),
('shrine.courtyard', 'shrine', null, 'courtyard', 'Courtyard',   '🕯️', 'courtyard', 5.0, 7.0, 4.0, 3.0, 0, null, 2),
-- salon / workshop / airport / farm
('salon.chairs', 'salon', null, 'chairs', 'Barber chairs', '💈', 'salon_chairs', 4.0, 2.0, 5.0, 1.4, 0, null, 1),
('salon.bench',  'salon', null, 'bench',  'Waiting bench', '🗣️', 'bench',        4.0, 6.5, 3.0, 1.2, 0, null, 2),
('salon.shelf',  'salon', null, 'shelf',  'Products shelf','🧴', 'shelves',      9.5, 2.0, 2.4, 1.0, 0, null, 3),
('workshop.furnace', 'workshop', null, 'furnace', 'Casting furnace', '🔥', 'furnace', 4.0, 3.0, 2.6, 2.0, 0, null, 1),
('workshop.display', 'workshop', null, 'display', 'Bronze display',  '🗿', 'display', 10.0, 2.0, 3.0, 1.0, 0, null, 2),
('airport.deck',  'airport', null, 'deck',  'Viewing deck', '✈️', 'seats',  5.0, 3.0, 5.0, 2.0, 0, null, 1),
('airport.cafe',  'airport', null, 'cafe',  'Café',         '☕', 'counter', 11.0, 6.0, 2.6, 1.2, 3, null, 2),
('farm.rows', 'farm', null, 'rows', 'Cassava rows', '🌱', 'crops', 6.0, 4.0, 7.0, 4.0, 0, null, 1),
('farm.shed', 'farm', null, 'shed', 'Tool shed',    '🛖', 'shed',  13.0, 8.0, 2.6, 2.0, 0, null, 2),
-- homes (someone else's home: the actions say "only in your own home")
('home_face_me.room',  'home_face_me', null, 'room',  'Room',     '🛏️', 'beds',     4.0, 3.0, 3.0, 2.2, 0, null, 1),
('home_face_me.yard',  'home_face_me', null, 'yard',  'Compound', '🪣', 'courtyard',8.5, 6.5, 3.6, 2.6, 0, null, 2),
('home_flat.room',     'home_flat',    null, 'room',  'Bedroom',  '🛏️', 'beds',     4.0, 3.0, 3.0, 2.2, 0, null, 1),
('home_flat.parlour',  'home_flat',    null, 'parlour','Parlour', '🛋️', 'seats',    8.5, 6.5, 3.6, 2.0, 0, null, 2),
('home_duplex.room',   'home_duplex',  null, 'room',  'Master bedroom', '🛏️', 'beds', 4.0, 3.0, 3.0, 2.2, 0, null, 1),
('home_duplex.parlour','home_duplex',  null, 'parlour','Living room', '🛋️', 'seats', 8.5, 6.5, 3.6, 2.0, 0, null, 2),
-- NEW types ---------------------------------------------------------
-- mall (ShopRite aisles + Genesis cinema)
('mall.shoprite', 'mall', null, 'shoprite', 'ShopRite aisles', '🛒', 'aisles',     4.5, 4.0, 6.0, 4.0, 0, null, 1),
('mall.checkout', 'mall', null, 'checkout', 'Checkout',        '🧾', 'checkout',   4.5, 9.0, 4.0, 1.2, 0, null, 2),
('mall.cinema',   'mall', null, 'cinema',   'Genesis Cinema',  '🎬', 'cinema_door',13.0, 2.0, 3.6, 1.4, 0, null, 3),
('mall.food',     'mall', null, 'food',     'Food court',      '🥧', 'tables',     12.5, 7.0, 3.6, 2.6, 0, null, 4),
('mall.walk',     'mall', null, 'walk',     'Mall corridor',   '🛍️', 'planters',   9.0, 10.5, 4.0, 1.0, 0, null, 5),
-- cinema (Kada Plaza)
('cinema.screen',  'cinema', null, 'screen',  'Screen 1',        '🎬', 'cinema_hall', 5.0, 4.0, 7.0, 5.0, 0, null, 1),
('cinema.snacks',  'cinema', null, 'snacks',  'Popcorn counter', '🍿', 'counter',     11.5, 2.0, 3.0, 1.2, 0, null, 2),
('cinema.chicken', 'cinema', null, 'chicken', 'Kada Fried Chicken', '🍗', 'counter',  11.5, 6.0, 3.0, 1.2, 3, null, 3),
('cinema.arcade',  'cinema', null, 'arcade',  'Arcade',          '🕹️', 'arcade',      11.5, 9.5, 3.0, 1.2, 0, null, 4),
-- hotel (lobby + pool)
('hotel.reception','hotel', null, 'reception','Reception',    '🛎️', 'counter',  3.0, 2.0, 3.6, 1.2, 0, null, 1),
('hotel.pool',     'hotel', null, 'pool',     'Pool',         '🏊', 'pool',     10.5, 7.5, 6.0, 4.0, 0, null, 2),
('hotel.lounge',   'hotel', null, 'lounge',   'Lounge bar',   '🍸', 'bar',      10.5, 2.0, 4.0, 1.2, 0, null, 3),
('hotel.restaurant','hotel', null,'restaurant','Restaurant',  '🍽️', 'tables',   3.5, 6.5, 3.6, 2.6, 0, null, 4),
('hotel.suites',   'hotel', null, 'suites',   'Suites',       '🛏️', 'bed_lux',  3.0, 10.5, 3.0, 2.0, 0, null, 5),
-- zoo (outdoor)
('zoo.lions',  'zoo', null, 'lions',  'Lion enclosure', '🦁', 'cage',   5.0, 3.5, 5.0, 3.0, 0, null, 1),
('zoo.birds',  'zoo', null, 'birds',  'Ostrich pen',    '🦤', 'pen',    13.0, 3.5, 4.0, 3.0, 0, null, 2),
('zoo.picnic', 'zoo', null, 'picnic', 'Picnic grove',   '🧺', 'trees',  5.0, 10.0, 5.0, 3.0, 0, null, 3),
('zoo.kiosk',  'zoo', null, 'kiosk',  'Snack kiosk',    '🥤', 'kiosk',  14.0, 10.0, 2.4, 1.6, 0, null, 4),
-- stadium
('stadium.popular', 'stadium', null, 'popular', 'Popular stand',  '📣', 'stands', 9.0, 1.8, 12.0, 2.4, 0, null, 1),
('stadium.vip',     'stadium', null, 'vip',     'VIP stand',      '🎟️', 'stands', 16.5, 6.5, 2.4, 6.0, 3, null, 2),
('stadium.pitch',   'stadium', null, 'pitch',   'The pitch & track','⚽', 'pitch', 9.0, 7.0, 11.0, 6.0, 0, null, 3),
('stadium.gate',    'stadium', null, 'gate',    'Gate snacks',    '🍢', 'kiosk',  2.0, 11.5, 2.4, 1.6, 0, null, 4),
-- Emotan statue (respectful)
('monument.statue', 'monument', null, 'statue', 'Emotan statue',  '🗽', 'statue',  6.0, 4.5, 3.0, 3.0, 0, null, 1),
('monument.bench',  'monument', null, 'bench',  'Shady bench',    '🌳', 'bench',   10.5, 8.5, 2.6, 1.2, 0, null, 2),
-- car dealer
('car_dealer.showroom', 'car_dealer', null, 'showroom', 'Showroom floor', '🚘', 'cars',    5.0, 3.5, 7.0, 3.0, 0, null, 1),
('car_dealer.lot',      'car_dealer', null, 'lot',      'Tokunbo lot',    '🚙', 'cars',    5.0, 8.5, 7.0, 3.0, 0, null, 2),
('car_dealer.office',   'car_dealer', null, 'office',   'Dealer''s desk', '🤝', 'desk',    12.5, 3.0, 2.4, 1.6, 0, null, 3),
('car_dealer.track',    'car_dealer', null, 'track',    'Test drive lane','🏁', 'lane',    12.5, 8.5, 2.6, 3.4, 0, null, 4),
-- the Tokunbo Lot has no showroom (just the dusty lot)
('tokunbo_lot.showroom', null, 'tokunbo_lot', 'showroom', 'Showroom floor', '🚘', 'cars', 5.0, 3.5, 7.0, 3.0, 0, null, 1)
on conflict (id) do nothing;
update public.place_zones set active = false where id = 'tokunbo_lot.showroom' and active
  and not exists (select 1 from public.zone_actions where zone_id = 'tokunbo_lot.showroom');

-- ---------------------------------------------------------------------
-- 8. Zone actions
-- ---------------------------------------------------------------------
insert into public.zone_actions (id, zone_id, kind, ref, label, sort)
select z || '.' || r, z, k, r, l, s from (values
  -- market
  ('market.foodstuff', 'shop', 'garri_groundnut', null, 1), ('market.foodstuff', 'shop', 'noodles_pack', null, 2), ('market.foodstuff', 'panel', 'shop', 'Buy foodstuff', 9),
  ('market.drinks', 'shop', 'pure_water', null, 1), ('market.drinks', 'shop', 'zobo', null, 2), ('market.drinks', 'shop', 'malt_drink', null, 3), ('market.drinks', 'shop', 'puff_puff', null, 4),
  ('market.mama_put', 'shop', 'owo_pack', null, 1), ('market.mama_put', 'shop', 'jollof_pack', null, 2), ('market.mama_put', 'shop', 'bread_egg', null, 3),
  ('market.traders', 'job', 'trade', null, 1), ('market.traders', 'shop', 'soap', null, 2), ('market.traders', 'shop', 'toothpaste', null, 3),
  ('market.loading', 'activity', 'market_stroll', null, 1),
  ('market.toilet', 'activity', 'public_toilet', null, 1),
  -- buka
  ('buka.counter', 'activity', 'owo_soup', null, 1), ('buka.counter', 'activity', 'banga_starch', null, 2), ('buka.counter', 'activity', 'black_soup', null, 3),
  ('buka.counter', 'activity', 'noodles_egg', null, 4), ('buka.counter', 'shop', 'jollof_pack', null, 5),
  ('buka.tables', 'activity', 'pepper_soup', null, 1), ('buka.tables', 'activity', 'gist_joint', null, 2), ('buka.tables', 'shop', 'zobo', null, 3),
  ('buka.tv', 'activity', 'watch_football', null, 1),
  ('buka.restroom', 'activity', 'ease_yourself', null, 1),
  ('mama_ebo.counter', 'activity', 'pepper_rice', null, 1), ('mama_ebo.counter', 'activity', 'owo_soup', null, 2), ('mama_ebo.counter', 'activity', 'black_soup', null, 3),
  ('mama_ebo.counter', 'shop', 'jollof_pack', 'Jollof takeaway pack', 4),
  -- club
  ('club.bar', 'activity', 'lounge_chill', null, 1), ('club.bar', 'shop', 'star_beer', null, 2), ('club.bar', 'shop', 'club_bottle', null, 3), ('club.bar', 'activity', 'pepper_soup', null, 4),
  ('club.dance', 'activity', 'club_dance', null, 1), ('club.dance', 'activity', 'club_night', null, 2), ('club.dance', 'activity', 'spray_money', null, 3),
  ('club.dj', 'activity', 'hype_shoutout', null, 1),
  ('club.vip', 'activity', 'vip_table', null, 1), ('club.vip', 'shop', 'club_bottle', null, 2),
  ('club.screens', 'activity', 'watch_football', null, 1),
  ('club.restroom', 'activity', 'ease_yourself', null, 1),
  -- bank
  ('bank.counter', 'panel', 'bank', 'Deposit or withdraw', 1),
  ('bank.atm', 'panel', 'bank', 'Use the ATM', 1),
  ('bank.waiting', 'activity', 'bank_cool_off', null, 1),
  -- hospital
  ('hospital.reception', 'activity', 'checkup', null, 1),
  ('hospital.pharmacy', 'shop', 'pain_relief', null, 1), ('hospital.pharmacy', 'shop', 'bottled_water', null, 2),
  ('hospital.ward', 'activity', 'ward_rest', null, 1),
  ('hospital.staff', 'job', 'health', null, 1),
  ('hospital.restroom', 'activity', 'ease_yourself', null, 1),
  -- campus
  ('campus.lecture', 'activity', 'attend_lecture', null, 1),
  ('campus.library', 'activity', 'library_read', null, 1),
  ('campus.quad', 'activity', 'campus_stroll', null, 1),
  ('campus.staff', 'job', 'education', null, 1),
  ('campus.restroom', 'activity', 'ease_yourself', null, 1),
  -- motor park
  ('motorpark.buses', 'job', 'transport', null, 1), ('motorpark.buses', 'activity', 'gist_joint', null, 2),
  ('motorpark.keke', 'job', 'transport', null, 1),
  ('motorpark.suya', 'activity', 'suya', null, 1), ('motorpark.suya', 'shop', 'suya_stick', null, 2),
  ('motorpark.kiosk', 'shop', 'roll_and_soda', null, 1), ('motorpark.kiosk', 'shop', 'malt_drink', null, 2), ('motorpark.kiosk', 'shop', 'pure_water', null, 3),
  ('motorpark.bench', 'activity', 'gist_joint', null, 1),
  ('motorpark.toilet', 'activity', 'public_toilet', null, 1),
  -- PoS
  ('pos.kiosk', 'panel', 'pos', 'Cash out or deposit', 1), ('pos.kiosk', 'job', 'pos', null, 2),
  ('pos.airtime', 'shop', 'airtime', null, 1), ('pos.airtime', 'shop', 'data_bundle', null, 2),
  ('pos.line', 'activity', 'pos_banter', null, 1),
  -- police
  ('police.desk', 'activity', 'police_statement', null, 1),
  ('police.bench', 'activity', 'police_statement', 'Wait your turn', 1),
  ('police.board', 'activity', 'police_statement', 'Read the notices, then report', 1),
  -- palace / museum
  ('palace.gate', 'activity', 'palace_visit', null, 1),
  ('palace.courtyard', 'activity', 'palace_chiefs', null, 1),
  ('palace.bronzes', 'activity', 'palace_visit', 'Admire the bronze plaques', 1),
  ('museum.gallery', 'activity', 'museum_tour', null, 1),
  ('museum.heads', 'activity', 'museum_guide', null, 1),
  ('museum.shop', 'activity', 'museum_tour', 'Browse the gift corner', 1),
  -- tech hub / cyber
  ('office.desks', 'job', 'tech', null, 1), ('office.desks', 'activity', 'side_project', null, 2),
  ('office.coffee', 'activity', 'office_coffee', null, 1), ('office.coffee', 'shop', 'bottled_water', null, 2),
  ('office.stage', 'activity', 'tech_meetup', null, 1),
  ('office.restroom', 'activity', 'ease_yourself', null, 1),
  ('cyber.desks', 'activity', 'cyber_browse', null, 1), ('cyber.desks', 'activity', 'side_project', null, 2), ('cyber.desks', 'shop', 'data_bundle', null, 3),
  ('cyber.snacks', 'activity', 'noodles_egg', null, 1), ('cyber.snacks', 'shop', 'noodles_pack', null, 2),
  -- street
  ('street.suya', 'activity', 'suya', null, 1),
  ('street.screen', 'activity', 'watch_football', null, 1),
  ('street.corner', 'activity', 'gist_joint', null, 1), ('street.corner', 'activity', 'people_watch', null, 2), ('street.corner', 'activity', 'night_stroll', null, 3),
  ('street.toilet', 'activity', 'public_toilet', null, 1),
  -- shrine
  ('shrine.altar', 'activity', 'shrine_consult', null, 1),
  ('shrine.courtyard', 'activity', 'shrine_quiet', null, 1),
  -- salon / workshop / airport / farm
  ('salon.chairs', 'activity', 'salon_freshen', null, 1),
  ('salon.bench', 'activity', 'gist_joint', null, 1),
  ('salon.shelf', 'shop', 'soap', null, 1), ('salon.shelf', 'shop', 'toothpaste', null, 2),
  ('workshop.furnace', 'activity', 'bronze_casting', null, 1),
  ('workshop.display', 'shop', 'bronze_mini_head', null, 1),
  ('airport.deck', 'activity', 'plane_spotting', null, 1),
  ('airport.cafe', 'activity', 'plane_spotting', 'Coffee by the window', 1),
  ('farm.rows', 'activity', 'farm_walk', null, 1),
  ('farm.shed', 'activity', 'farm_walk', 'Help sort the harvest', 1),
  -- homes
  ('home_face_me.room', 'activity', 'nap', null, 1), ('home_face_me.yard', 'activity', 'bathe', null, 1),
  ('home_flat.room', 'activity', 'nap', null, 1), ('home_flat.parlour', 'activity', 'watch_tv', null, 1),
  ('home_duplex.room', 'activity', 'nap', null, 1), ('home_duplex.parlour', 'activity', 'relax_sofa', null, 1),
  -- mall
  ('mall.shoprite', 'shop', 'cornflakes_milk', null, 1), ('mall.shoprite', 'shop', 'noodles_pack', null, 2), ('mall.shoprite', 'shop', 'soap', null, 3),
  ('mall.shoprite', 'shop', 'laptop', null, 4), ('mall.shoprite', 'panel', 'shop', 'All ShopRite items', 9),
  ('mall.checkout', 'shop', 'bottled_water', null, 1), ('mall.checkout', 'shop', 'airtime', null, 2),
  ('mall.cinema', 'activity', 'watch_film', null, 1), ('mall.cinema', 'activity', 'watch_film_vip', null, 2),
  ('mall.food', 'shop', 'meat_pie', null, 1), ('mall.food', 'shop', 'popcorn', null, 2), ('mall.food', 'shop', 'jollof_pack', null, 3),
  ('mall.walk', 'activity', 'mall_stroll', null, 1),
  -- cinema
  ('cinema.screen', 'activity', 'watch_film', null, 1), ('cinema.screen', 'activity', 'watch_film_vip', null, 2),
  ('cinema.snacks', 'shop', 'popcorn', null, 1),
  ('cinema.chicken', 'shop', 'kada_chicken', null, 1),
  ('cinema.arcade', 'activity', 'arcade_games', null, 1),
  -- hotel
  ('hotel.reception', 'activity', 'hotel_sleep', 'Book a suite for the night', 1),
  ('hotel.pool', 'activity', 'hotel_pool', null, 1),
  ('hotel.lounge', 'activity', 'hotel_lounge', null, 1),
  ('hotel.restaurant', 'activity', 'hotel_buffet', null, 1),
  ('hotel.suites', 'activity', 'hotel_sleep', null, 1),
  -- zoo
  ('zoo.lions', 'activity', 'zoo_trip', null, 1),
  ('zoo.birds', 'activity', 'zoo_birds', null, 1),
  ('zoo.picnic', 'activity', 'zoo_picnic', null, 1),
  ('zoo.kiosk', 'shop', 'meat_pie', null, 1), ('zoo.kiosk', 'shop', 'pure_water', null, 2), ('zoo.kiosk', 'shop', 'malt_drink', null, 3),
  -- stadium
  ('stadium.popular', 'activity', 'match_day', null, 1),
  ('stadium.vip', 'activity', 'match_vip', null, 1),
  ('stadium.pitch', 'activity', 'stadium_jog', null, 1),
  ('stadium.gate', 'shop', 'suya_stick', null, 1), ('stadium.gate', 'shop', 'meat_pie', null, 2), ('stadium.gate', 'shop', 'malt_drink', null, 3),
  -- Emotan
  ('monument.statue', 'activity', 'emotan_photo', null, 1), ('monument.statue', 'activity', 'emotan_history', null, 2),
  ('monument.bench', 'activity', 'people_watch', null, 1),
  -- car dealer
  ('car_dealer.showroom', 'shop', 'hilux_new', null, 1), ('car_dealer.showroom', 'shop', 'lexus_rx350', null, 2), ('car_dealer.showroom', 'shop', 'camry_muscle', null, 3),
  ('car_dealer.lot', 'shop', 'tokunbo_car', null, 1), ('car_dealer.lot', 'shop', 'kia_rio_used', null, 2),
  ('car_dealer.office', 'activity', 'haggle_dealer', null, 1),
  ('car_dealer.track', 'activity', 'test_drive', null, 1)
) v(z, k, r, l, s)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 9. Mood lines (rotate on the place card; part = any | morning 5-12 | afternoon 12-17 | evening 17-21 | night 21-5)
-- ---------------------------------------------------------------------
insert into public.place_moods (id, scene, location_id, part, icon, line, sort)
select id, sc, loc, part, icon, line, row_number() over () from (values
  ('market.1', 'market', null, 'morning', '🚚', 'A truck is offloading tomatoes at the loading bay'),
  ('market.2', 'market', null, 'morning', '📣', 'Traders are calling out first-sale prices'),
  ('market.3', 'market', null, 'afternoon', '☀️', 'The sun is hot and the haggling is hotter'),
  ('market.4', 'market', null, 'any', '🧺', 'Somebody''s aunty is buying the whole stall'),
  ('market.5', 'market', null, 'evening', '🌆', 'Stalls are packing up; last prices are flying'),
  ('market.6', 'market', null, 'night', '🌙', 'Only the night guards and a few lanterns left'),
  ('buka.1', 'buka', null, 'afternoon', '🍲', 'The lunch queue is out the door'),
  ('buka.2', 'buka', null, 'any', '🔥', 'Fresh pot of owo soup just came off the fire'),
  ('buka.3', 'buka', null, 'evening', '📺', 'The guys are arguing about last night''s match'),
  ('buka.4', 'buka', null, 'morning', '☕', 'Early workers grabbing a quick plate'),
  ('mama_ebo.1', null, 'mama_ebo', 'afternoon', '😬', 'Lunch rush: the pepper rice pot is getting low'),
  ('mama_ebo.2', null, 'mama_ebo', 'any', '🌶️', 'The smell of pepper rice is reaching Airport Rd'),
  ('mama_ebo.3', null, 'mama_ebo', 'morning', '🍗', 'Mama Ebo is frying the turkey for lunch'),
  ('club.1', 'club', null, 'night', '🎧', 'The DJ just dropped the new Rema song'),
  ('club.2', 'club', null, 'night', '🎤', 'The hype man is shouting out a big spender'),
  ('club.3', 'club', null, 'night', '🍾', 'Sparklers just went up at the VIP section'),
  ('club.4', 'club', null, 'night', '💸', 'Somebody is spraying money on the dance floor'),
  ('club.5', 'club', null, 'any', '🧹', 'Cleaners are sweeping up last night''s confetti'),
  ('club.6', 'club', null, 'evening', '🔊', 'Sound check: the speakers are warming up'),
  ('bank.1', 'bank', null, 'morning', '🧾', 'The queue started before the doors opened'),
  ('bank.2', 'bank', null, 'any', '❄️', 'The AC is the best thing in this building'),
  ('bank.3', 'bank', null, 'afternoon', '⏳', 'Network is slow; everybody is waiting patiently'),
  ('hospital.1', 'hospital', null, 'any', '🩺', 'A nurse is calling the next number'),
  ('hospital.2', 'hospital', null, 'any', '💊', 'The pharmacy just restocked'),
  ('campus.1', 'campus', null, 'morning', '📚', 'Students are rushing to the 8 AM lecture'),
  ('campus.2', 'campus', null, 'afternoon', '🌳', 'The quad is full of people revising'),
  ('campus.3', 'campus', null, 'evening', '🎶', 'Somebody is playing guitar by the hostel'),
  ('campus.4', 'campus', null, 'night', '🌙', 'Night readers in the library, very quiet'),
  ('motorpark.1', 'motorpark', null, 'any', '🚌', 'Conductor: "Lagos! One chance remaining!"'),
  ('motorpark.2', 'motorpark', null, 'morning', '🌅', 'The first buses are filling up fast'),
  ('motorpark.3', 'motorpark', null, 'evening', '🍢', 'The suya man just lit his grill'),
  ('pos.1', 'pos', null, 'any', '💳', '"Network don come back!" The line moves again'),
  ('pos.2', 'pos', null, 'evening', '💡', 'The PoS man switched on his little bulb'),
  ('police.1', 'police', null, 'any', '📝', 'An officer is writing slowly in a big book'),
  ('palace.1', 'palace', null, 'any', '🪶', 'Chiefs in coral beads are arriving for a meeting'),
  ('palace.2', 'palace', null, 'any', '🥁', 'Royal drummers are practising softly'),
  ('museum.1', 'museum', null, 'any', '🗿', 'A school group is staring at the bronze heads'),
  ('office.1', 'office', null, 'any', '☕', 'Fresh coffee and puff-puff in the lounge'),
  ('office.2', 'office', null, 'evening', '🎤', 'The meetup host is testing the mic'),
  ('cyber.1', 'cyber', null, 'any', '🖥️', 'Somebody is printing 40 pages of a project'),
  ('street.1', 'street', null, 'any', '🛺', 'Kekes are hooting at nothing in particular'),
  ('street.2', 'street', null, 'night', '🌙', 'Street lights flicker; stay sharp out here'),
  ('street.3', 'street', null, 'evening', '📺', 'The viewing centre is packed for the match'),
  ('shrine.1', 'shrine', null, 'any', '🪔', 'Incense smoke curls up from the shrine room'),
  ('salon.1', 'salon', null, 'any', '💈', 'The clippers are buzzing; gist is flowing'),
  ('workshop.1', 'workshop', null, 'any', '🔥', 'Molten bronze glows orange in the furnace'),
  ('airport.1', 'airport', null, 'any', '✈️', 'A plane from Lagos is on final approach'),
  ('farm.1', 'farm', null, 'any', '🌱', 'The cassava is looking healthy this season'),
  ('home.1', 'home_face_me', null, 'any', '🏠', 'Neighbours are chatting in the compound'),
  ('home.2', 'home_flat', null, 'any', '🏢', 'Someone upstairs is playing highlife'),
  ('home.3', 'home_duplex', null, 'any', '🏡', 'The gateman is washing the cars'),
  ('mall.1', 'mall', null, 'any', '🛒', 'ShopRite has a two-for-one on noodles'),
  ('mall.2', 'mall', null, 'evening', '🎬', 'The new blockbuster is selling out at Genesis'),
  ('mall.3', 'mall', null, 'afternoon', '❄️', 'Everybody came in just for the AC'),
  ('cinema.1', 'cinema', null, 'any', '🍿', 'Fresh popcorn is popping'),
  ('cinema.2', 'cinema', null, 'evening', '🎬', 'The 7 PM show is almost full'),
  ('cinema.3', 'cinema', null, 'any', '🍗', 'Kada chicken just came out of the fryer'),
  ('hotel.1', 'hotel', null, 'any', '🏊', 'Someone just cannonballed into the pool'),
  ('hotel.2', 'hotel', null, 'evening', '🎷', 'A saxophonist is playing in the lounge'),
  ('hotel.3', 'hotel', null, 'morning', '🍳', 'The breakfast buffet is still going'),
  ('zoo.1', 'zoo', null, 'any', '🦁', 'The lion is yawning at the visitors'),
  ('zoo.2', 'zoo', null, 'morning', '🐒', 'The chimps are noisy this morning'),
  ('zoo.3', 'zoo', null, 'afternoon', '🧺', 'Families are spreading mats under the trees'),
  ('stadium.1', 'stadium', null, 'afternoon', '⚽', 'Bendel Insurance are warming up on the pitch'),
  ('stadium.2', 'stadium', null, 'any', '📣', 'The popular stand is singing already'),
  ('stadium.3', 'stadium', null, 'morning', '🏃', 'Joggers are doing laps on the track'),
  ('monument.1', 'monument', null, 'any', '🗽', 'Market women greet Emotan as they pass'),
  ('monument.2', 'monument', null, 'morning', '🌺', 'Someone left fresh flowers at the plinth'),
  ('car_dealer.1', 'car_dealer', null, 'any', '🚘', 'A salesman is polishing a Lexus for the third time'),
  ('car_dealer.2', 'car_dealer', null, 'any', '🤝', '"Oga, this one is last price. Truly."'),
  ('rome.1', null, 'rome_club', 'night', '💨', 'The smoke machine just went off over the crowd'),
  ('club_360.1', null, 'club_360', 'night', '✨', 'Bottles with sparklers are parading to a booth'),
  ('owambe.1', null, 'owambe_republic', 'night', '🎺', 'The live band switched to highlife'),
  ('kada.1', null, 'kada_plaza', 'any', '🎬', 'Kada Cinemas has a new Nollywood premiere')
) v(id, sc, loc, part, icon, line)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 10. Helpers: opening hours
-- ---------------------------------------------------------------------
-- "9 PM", "10 AM", "midnight", "noon", "9:30 PM"
create or replace function public.bl_hour_label(p_hour numeric) returns text
language sql immutable as $$
  select case
    when p_hour is null then null
    when p_hour % 24 = 0 then 'midnight'
    when p_hour = 12 then 'noon'
    else (case when floor(p_hour)::int % 12 = 0 then 12 else floor(p_hour)::int % 12 end)::text
         || case when p_hour <> floor(p_hour) then ':' || lpad(round((p_hour - floor(p_hour)) * 60)::int::text, 2, '0') else '' end
         || case when p_hour % 24 < 12 then ' AM' else ' PM' end
  end;
$$;

-- Is a place open now (Benin clock)? Places without hours, or hours switched off, are always open.
create or replace function public.bl_place_open(p_loc public.locations) returns boolean
language plpgsql stable set search_path = public as $$
declare v_clock jsonb; h numeric;
begin
  if p_loc.open_hour is null or not bl_cfg_bool('places.hours_enabled') then return true; end if;
  v_clock := bl_game_clock();
  h := (v_clock->>'hour')::numeric + coalesce((v_clock->>'minute')::numeric, 0) / 60.0;
  if p_loc.open_hour = p_loc.close_hour then return true; end if;
  if p_loc.open_hour < p_loc.close_hour then return h >= p_loc.open_hour and h < p_loc.close_hour; end if;
  return h >= p_loc.open_hour or h < p_loc.close_hour;
end $$;

-- Raise the friendly "closed" error when a place is shut.
create or replace function public.bl_assert_place_open(p_loc public.locations) returns void
language plpgsql stable set search_path = public as $$
begin
  if not bl_place_open(p_loc) then
    raise exception '% is closed right now. Opens % (open % to %).', p_loc.name, bl_hour_label(p_loc.open_hour),
      bl_hour_label(p_loc.open_hour), bl_hour_label(p_loc.close_hour)
      using errcode = 'P0001', hint = 'closed';
  end if;
end $$;

-- Part of the day for mood lines.
create or replace function public.bl_day_part() returns text
language sql stable set search_path = public as $$
  select case when h >= 5 and h < 12 then 'morning' when h >= 12 and h < 17 then 'afternoon'
              when h >= 17 and h < 21 then 'evening' else 'night' end
    from (select (bl_game_clock()->>'hour')::int as h) x;
$$;

revoke execute on function public.bl_hour_label(numeric)               from public, anon, authenticated;
revoke execute on function public.bl_place_open(public.locations)        from public, anon, authenticated;
revoke execute on function public.bl_assert_place_open(public.locations) from public, anon, authenticated;
revoke execute on function public.bl_day_part()                          from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 11. do_activity: live definition (20261006000400_starter_furniture.sql) plus L2:
--     activities.location_ids, opening hours, rush ("sold out" before any charge), Risky (street robbery roll).
-- ---------------------------------------------------------------------
create or replace function public.do_activity(p_activity text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me     profiles := bl_me();
  a        activities;
  v_scene  text;
  v_until  timestamptz;
  v_eff    jsonb;
  v_used   text[] := '{}';
  r        record;
  v_pct    numeric;
  v_rent   boolean := false;
  v_msg    text;
  v_from   jsonb;
  v_secs   numeric;
  v_furn   jsonb;
  v_loc    locations;
  v_hour   numeric;
  v_robbed jsonb;
begin
  perform bl_assert_free(v_me);
  select * into a from activities where id = p_activity;
  if not found then
    raise exception 'That activity doesn''t exist.' using errcode = 'P0001';
  end if;
  select * into v_loc from locations where id = v_me.location_id;
  v_scene := v_loc.scene;
  if not (v_scene = any(a.scenes)) then
    raise exception 'You can''t do "%" here. Go where it is offered.', a.name using errcode = 'P0001';
  end if;
  if cardinality(a.location_ids) > 0 and not (v_loc.id = any (a.location_ids)) then
    raise exception '"%" is only at %.', a.name,
      (select string_agg(name, ', ' order by sort) from locations where id = any (a.location_ids))
      using errcode = 'P0001', hint = 'wrong_place';
  end if;
  if a.home_only and v_me.location_id <> v_me.home_location_id then
    raise exception 'You can only do "%" in your own home.', a.name using errcode = 'P0001';
  end if;
  v_furn := bl_furniture_for(v_me.id, a.id);
  if a.home_only and a.needs_furniture and not (v_furn->>'owned')::boolean then
    raise exception 'You don''t have the furniture for "%" at home yet.', a.name
      using errcode = 'P0001', hint = 'no_furniture';
  end if;
  if a.night_only and not (bl_game_clock()->>'is_night')::boolean then
    raise exception '"%" is a night-time thing. Come back after dark.', a.name using errcode = 'P0001';
  end if;
  -- opening hours (after the night-only rule, so its message stays the same)
  if not a.home_only then
    perform bl_assert_place_open(v_loc);
  end if;
  -- rush hour: it can sell out (nothing is charged)
  if coalesce(a.rush->>'pct', '') <> '' and (a.rush->>'pct')::numeric > 0 then
    v_hour := (bl_game_clock()->>'hour')::numeric;
    if v_hour >= coalesce((a.rush->>'from')::numeric, 0) and v_hour < coalesce((a.rush->>'to')::numeric, 24)
       and bl_rand() < (a.rush->>'pct')::numeric / 100.0 then
      raise exception '%', coalesce(nullif(a.rush->>'line', ''), a.name || ' is sold out right now. Try again soon.')
        using errcode = 'P0001', hint = 'sold_out';
    end if;
  end if;
  if a.cost > 0 then
    perform bl_add_money(v_me.id, 'cash', -a.cost, 'activity', jsonb_build_object('activity', a.id));
  end if;

  v_eff := a.effects;
  for r in select it.id, it.name, it.effects->'boost'->a.id as bonus
             from inventory i join items it on it.id = i.item_id
            where i.user_id = v_me.id and i.qty > 0 and jsonb_typeof(it.effects->'boost'->a.id) = 'object'
            order by it.sort, it.id loop
    v_eff := v_eff || bl_effects_add(bl_need_effects(v_eff), bl_need_effects(r.bonus));
    perform bl_give_item(v_me.id, r.id, -1);
    v_used := v_used || r.name;
  end loop;
  -- how well this piece rests you (foam mat < bed)
  if a.home_only and (v_furn->>'owned')::boolean and (v_furn->>'rest_pct')::numeric <> 100
     and coalesce((v_eff->>'energy')::numeric, 0) > 0 then
    v_eff := v_eff || jsonb_build_object('energy',
               round((v_eff->>'energy')::numeric * greatest(0, least(200, (v_furn->>'rest_pct')::numeric)) / 100, 1));
  end if;
  if v_me.rent_owed > 0 and bl_csv_has(bl_cfg_text('rent.owed_sleep_activities'), a.id)
     and coalesce((v_eff->>'energy')::numeric, 0) > 0 then
    v_pct := greatest(0, least(100, bl_cfg('rent.owed_sleep_energy_pct')));
    if v_pct < 100 then
      v_eff := v_eff || jsonb_build_object('energy', round((v_eff->>'energy')::numeric * v_pct / 100, 1));
      v_rent := true;
    end if;
  end if;

  v_from := bl_needs_snapshot(v_me);
  v_secs := bl_activity_seconds(v_me, a, a.effects);
  perform bl_adjust_needs(v_me.id, v_eff);
  if coalesce((v_eff->>'street_cred')::int, 0) <> 0 then
    update profiles set street_cred = greatest(0, street_cred + (v_eff->>'street_cred')::int) where id = v_me.id;
  end if;
  v_until := bl_set_busy_seconds(v_me.id, v_secs, a.name);
  update profiles set busy_needs_from = v_from where id = v_me.id;
  v_msg := 'You started "' || a.name || '"'
           || case when a.cost > 0 then ' (' || bl_naira(a.cost) || ').' else '. Enjoy!' end;
  if cardinality(v_used) > 0 then
    v_msg := v_msg || ' Used: ' || array_to_string(v_used, ', ') || '.';
  end if;
  if v_rent then
    v_msg := v_msg || ' The landlord keeps knocking: "Where my rent? You owe ' || bl_naira(v_me.rent_owed)
             || '!" You won''t rest well until you pay.';
  end if;
  -- Risky: flashing money here can attract the wrong boys (the usual street robbery roll at this place)
  if a.risky then
    v_robbed := bl_roll_street_robbery(v_me.id, v_loc.id, 'walk', 1.0);
    if v_robbed is not null then
      v_msg := v_msg || ' Omo! Somebody dipped hand for your pocket: ' || bl_naira((v_robbed->>'amount')::bigint) || ' gone.';
    end if;
  end if;
  return jsonb_build_object('message', v_msg, 'busy_until', v_until, 'effects', v_eff,
                            'used', to_jsonb(v_used), 'rent_penalty', v_rent, 'real_seconds', v_secs,
                            'robbed', v_robbed);
end $$;
revoke execute on function public.do_activity(text) from public, anon;
grant execute on function public.do_activity(text) to authenticated;

-- ---------------------------------------------------------------------
-- 12. shop_buy: live definition (20261005000800_shops.sql) plus opening hours, and cars (category vehicle):
--     one at a time, never the same car twice, paid from the bank first then cash (cars.bank_first).
-- ---------------------------------------------------------------------
create or replace function public.shop_buy(p_item text, p_qty int default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  it      items;
  l       locations;
  v_total bigint;
  v_owned int;
  v_where text;
  v_msg   text;
  v_bank  bigint := 0;
  v_cash  bigint := 0;
begin
  perform bl_assert_free(v_me);
  it := bl_item(p_item);
  perform bl_check_qty(p_qty);
  l := bl_location(v_me.location_id);
  if not (l.id = any (it.sold_at)) then
    select string_agg(x.name, ', ' order by x.sort) into v_where
      from (select name, sort from locations where id = any (it.sold_at) order by sort limit 3) x;
    raise exception '% is not sold here.%', it.name,
      case when v_where is null then ' It is not sold anywhere right now.' else ' Try ' || v_where || '.' end
      using errcode = 'P0001', hint = 'not_sold_here';
  end if;
  perform bl_assert_place_open(l);
  v_total := it.price * p_qty;

  if it.category = 'vehicle' then
    if p_qty <> 1 then
      raise exception 'One car at a time, please.' using errcode = 'P0001', hint = 'bad_qty';
    end if;
    if exists (select 1 from inventory where user_id = v_me.id and item_id = it.id and qty > 0) then
      raise exception 'You already own a %. Pick a different car.', it.name using errcode = 'P0001', hint = 'already_owned';
    end if;
    if bl_cfg_bool('cars.bank_first') then
      v_bank := least(v_me.bank, v_total);
      v_cash := v_total - v_bank;
    else
      v_cash := v_total;
    end if;
    if v_cash > v_me.cash then
      raise exception 'Not enough money. % costs % and you have % (bank % + cash %).', it.name, bl_naira(v_total),
        bl_naira(v_me.bank + v_me.cash), bl_naira(v_me.bank), bl_naira(v_me.cash)
        using errcode = 'P0001', hint = 'not_enough_cash';
    end if;
    if v_bank > 0 then
      perform bl_add_money(v_me.id, 'bank', -v_bank, 'car_purchase', jsonb_build_object('item', it.id, 'location', l.id));
    end if;
    if v_cash > 0 then
      perform bl_add_money(v_me.id, 'cash', -v_cash, 'car_purchase', jsonb_build_object('item', it.id, 'location', l.id));
    end if;
    v_owned := bl_give_item(v_me.id, it.id, 1);
    v_msg := 'Congrats! You bought a ' || it.name || ' for ' || bl_naira(v_total)
             || '. "Your car" is now a travel option in the Ride app and the place sheets.';
    return jsonb_build_object('message', v_msg, 'item', it.id, 'qty', 1, 'owned', v_owned, 'spent', v_total,
                              'from_bank', v_bank, 'from_cash', v_cash, 'cash', v_me.cash - v_cash, 'bank', v_me.bank - v_bank,
                              'car', true);
  end if;

  if v_total > v_me.cash then
    raise exception 'Not enough cash. % costs % and you have % on you.',
      case when p_qty > 1 then p_qty || ' × ' || it.name else it.name end, bl_naira(v_total), bl_naira(v_me.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  if v_total > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_total, 'shop',
                         jsonb_build_object('item', it.id, 'qty', p_qty, 'location', l.id));
  end if;
  v_owned := bl_give_item(v_me.id, it.id, p_qty);
  v_msg := 'You bought ' || case when p_qty > 1 then p_qty || ' × ' else '' end || it.name
           || ' for ' || bl_naira(v_total) || '. It''s in your Bag.';
  if l.scene = 'market' then v_msg := v_msg || ' "Thank you o, come back again!"'; end if;
  return jsonb_build_object('message', v_msg, 'item', it.id, 'qty', p_qty, 'owned', v_owned,
                            'spent', v_total, 'cash', v_me.cash - v_total);
end $$;
revoke execute on function public.shop_buy(text, int) from public, anon;
grant execute on function public.shop_buy(text, int) to authenticated;

-- ---------------------------------------------------------------------
-- 13. place_interior: everything the 3D interior + place card needs, in one read.
--     Zones = the type's zones merged with the place's own (same zone_key: the place wins; inactive hides).
--     Actions: activity (cost, seconds, effects, risky, why locked), job (pay, mine/can work), shop (item),
--     panel (opens a place tab). Activities offered elsewhere only (location_ids) are left out.
-- ---------------------------------------------------------------------
create or replace function public.place_interior(p_location text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_me    profiles;
  l       locations;
  v_open  boolean;
  v_night boolean := (bl_game_clock()->>'is_night')::boolean;
  v_part  text := bl_day_part();
  v_here  boolean;
  v_home  boolean;
  v_zones jsonb;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  l := bl_location(coalesce(p_location, v_me.location_id));
  v_open := bl_place_open(l);
  v_here := v_me.location_id = l.id and v_me.travel_to is null;
  v_home := v_me.home_location_id = l.id;

  with z as (
    select distinct on (pz.zone_key) pz.*
      from place_zones pz
     where pz.scene = l.scene or pz.location_id = l.id
     order by pz.zone_key, (pz.location_id is not null) desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', z.id, 'key', z.zone_key, 'label', z.label, 'icon', z.icon, 'prop', z.prop,
           'x', z.x, 'z', z.z, 'w', z.w, 'd', z.d, 'rot', z.rot, 'note', z.note,
           'actions', coalesce((
             select jsonb_agg(act order by s1, s2) from (
               -- activities
               select za.sort as s1, a.sort as s2, jsonb_build_object(
                        'id', za.id, 'kind', 'activity', 'ref', a.id,
                        'name', coalesce(za.label, a.name), 'icon', coalesce(za.icon, a.icon, '✨'),
                        'cost', a.cost, 'effects', a.effects, 'game_minutes', a.game_minutes,
                        'max_seconds', a.max_seconds, 'min_seconds', a.min_seconds, 'scale_by_need', a.scale_by_need,
                        'night_only', a.night_only, 'risky', a.risky, 'home_only', a.home_only,
                        'rush', case when a.rush = '{}'::jsonb then null else a.rush - 'line' end,
                        'locked', case
                          when a.home_only and not v_home then 'Only in your own home'
                          when not a.home_only and not v_open then 'Opens ' || bl_hour_label(l.open_hour)
                          when a.night_only and not v_night then 'Night only'
                          else null end) as act
                 from zone_actions za join activities a on a.id = za.ref
                where za.zone_id = z.id and za.kind = 'activity' and za.active
                  and l.scene = any (a.scenes)
                  and (cardinality(a.location_ids) = 0 or l.id = any (a.location_ids))
               union all
               -- shop items sold at this place
               select za.sort, it.sort, jsonb_build_object(
                        'id', za.id, 'kind', 'shop', 'ref', it.id,
                        'name', coalesce(za.label, it.name), 'icon', coalesce(za.icon, it.icon, '🛍️'),
                        'cost', it.price, 'effects', it.effects, 'category', it.category,
                        'owned', coalesce((select qty from inventory where user_id = v_uid and item_id = it.id), 0),
                        'locked', case when not v_open then 'Opens ' || bl_hour_label(l.open_hour) else null end)
                 from zone_actions za join items it on it.id = za.ref
                where za.zone_id = z.id and za.kind = 'shop' and za.active and l.id = any (it.sold_at)
               union all
               -- job tracks that work here
               select za.sort, 0, jsonb_build_object(
                        'id', za.id, 'kind', 'job', 'ref', t.id,
                        'name', coalesce(za.label, case when v_me.job_id = t.id then 'Work a shift' else t.name || ' jobs' end),
                        'icon', coalesce(za.icon, t.emoji),
                        'mine', v_me.job_id = t.id,
                        'title', (select title from career_levels where track_id = t.id
                                   and level = case when v_me.job_id = t.id then v_me.job_level else 1 end),
                        'pay', (select round(pay_per_shift * bl_cfg('career.pay_mult')) from career_levels where track_id = t.id
                                 and level = case when v_me.job_id = t.id then v_me.job_level else 1 end),
                        'locked', null)
                 from zone_actions za join career_tracks t on t.id = za.ref
                where za.zone_id = z.id and za.kind = 'job' and za.active and t.active and l.id = any (t.location_ids)
               union all
               -- open a tab of the place sheet (bank counter, PoS, the whole shop...)
               select za.sort, 0, jsonb_build_object(
                        'id', za.id, 'kind', 'panel', 'ref', za.ref,
                        'name', coalesce(za.label, initcap(za.ref)), 'icon', coalesce(za.icon,
                          case za.ref when 'bank' then '🏦' when 'pos' then '💳' when 'shop' then '🛍️' when 'jobs' then '💼' else '›' end),
                        'locked', null)
                 from zone_actions za
                where za.zone_id = z.id and za.kind = 'panel' and za.active
                  and (za.ref in ('chat', 'inventory', 'activities') or za.ref = any (l.actions))
             ) q), '[]'::jsonb))
         order by z.sort, z.zone_key), '[]'::jsonb)
    into v_zones
    from z where z.active;

  return jsonb_build_object(
    'location', jsonb_build_object('id', l.id, 'name', l.name, 'district', l.district, 'scene', l.scene, 'blurb', l.blurb,
                                   'open_hour', l.open_hour, 'close_hour', l.close_hour),
    'here', v_here, 'home', v_home, 'open', v_open,
    'opens', case when v_open then null else 'Opens ' || bl_hour_label(l.open_hour) end,
    'hours', case when l.open_hour is null then null
                  else bl_hour_label(l.open_hour) || ' – ' || bl_hour_label(l.close_hour) end,
    'night', v_night, 'part', v_part,
    'moods', coalesce((select jsonb_agg(jsonb_build_object('icon', m.icon, 'line', m.line) order by (m.location_id is null), m.sort)
                         from place_moods m
                        where m.active and (m.scene = l.scene or m.location_id = l.id)
                          and (m.part = 'any' or m.part = v_part)), '[]'::jsonb),
    'zones', v_zones);
end $$;
revoke execute on function public.place_interior(text) from public, anon;
grant execute on function public.place_interior(text) to authenticated;

-- ---------------------------------------------------------------------
-- 14. Admin: whitelist the new tables and columns (live definitions + L2 rows), and a nullable number type
-- ---------------------------------------------------------------------
create or replace function public.bl_admin_table_spec(p_table text) returns jsonb
language sql immutable as $$
  select case p_table
    when 'origin_tiers' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","tagline":"text","welcome":"text","sort":"int","perks":"obj"}}'
    when 'traits' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","effects":"obj","sort":"int","active":"bool"}}'
    when 'dreams' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","goal":"obj","sort":"int","active":"bool"}}'
    when 'start_homes' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","location_id":"text","district":"text","tag":"text","description":"text",
              "weekly_rent":"money","start_cash":"obj","allowed_origins":"arr","locked_quip":"text","housing_id":"text",
              "sort":"int","active":"bool"}}'
    when 'career_tracks' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","location_ids":"arr","skill":"text_null","sort":"int","active":"bool"}}'
    when 'career_levels' then '{"pk":["track_id","level"],"insert":true,"order":"track_id, level",
      "cols":{"title":"text","pay_per_shift":"money","shift_game_minutes":"int","energy_cost":"int","effects":"obj",
              "xp_per_shift":"int","xp_to_next":"int_null","requirements":"obj","perks":"obj"}}'
    when 'items' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","category":"text","price":"money","description":"text","effects":"obj","sold_at":"arr",
              "sellable":"bool","resale_pct":"num","icon":"text_null","sort":"int"}}'
    when 'activities' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","scenes":"arr","home_only":"bool","night_only":"bool","cost":"money","game_minutes":"int",
              "max_seconds":"num","min_seconds":"num","scale_by_need":"bool","needs_furniture":"bool","effects":"obj","sort":"int",
              "location_ids":"arr","risky":"bool","rush":"obj","icon":"text_null"}}'
    when 'locations' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","blurb":"text","risk":"num","night_risk_mult":"num","cctv":"bool","keke_ok":"bool",
              "congestion":"num","remote_km":"num","actions":"arr","sort":"int","open_hour":"num_null","close_hour":"num_null"}}'
    when 'chat_banned_words' then '{"pk":["word"],"insert":true,"order":"word","cols":{"active":"bool"}}'
    when 'furniture' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","kind":"text","slot":"text","activities":"arr","rest_pct":"int",
              "color":"text_null","description":"text","sort":"int","active":"bool"}}'
    when 'starter_furniture' then '{"pk":["id"],"insert":true,"order":"origin, sort, id",
      "cols":{"origin":"text","start_home":"text_null","furniture_id":"text","slot":"text_null","sort":"int","active":"bool"}}'
    when 'place_zones' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","zone_key":"text","label":"text","icon":"text","prop":"text",
              "x":"num","z":"num","w":"num","d":"num","rot":"int","note":"text_null","sort":"int","active":"bool"}}'
    when 'zone_actions' then '{"pk":["id"],"insert":true,"order":"zone_id, sort, id",
      "cols":{"zone_id":"text","kind":"text","ref":"text","label":"text_null","icon":"text_null","sort":"int","active":"bool"}}'
    when 'place_moods' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), part, sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","part":"text","icon":"text","line":"text","sort":"int","active":"bool"}}'
  end::jsonb;
$$;
revoke execute on function public.bl_admin_table_spec(text) from public, anon, authenticated;

-- live definition (20261005001100_admin.sql) + num_null (a number or empty) and the 0-24 hour range
create or replace function public.bl_admin_check_value(p_col text, p_type text, p_val jsonb) returns void
language plpgsql immutable as $$
declare t text := jsonb_typeof(p_val); n numeric;
begin
  if t is null or t = 'null' then
    if p_type in ('text_null', 'int_null', 'num_null') then return; end if;
    raise exception '% can''t be empty.', p_col using errcode = 'P0001', hint = 'bad_value';
  end if;
  case p_type
    when 'text', 'text_null' then
      if t <> 'string' then raise exception '% must be text.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
      if length(p_val #>> '{}') > 4000 then raise exception '% is too long.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
    when 'bool' then
      if t <> 'boolean' then raise exception '% must be true or false.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
    when 'obj' then
      if t <> 'object' then raise exception '% must be a JSON object ({...}).', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
    when 'arr' then
      if t <> 'array' or exists (select 1 from jsonb_array_elements(p_val) e where jsonb_typeof(e) <> 'string') then
        raise exception '% must be a list of text values.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
    when 'int', 'int_null', 'money', 'num', 'num_null' then
      if t <> 'number' then raise exception '% must be a number.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
      n := p_val::text::numeric;
      if p_type not in ('num', 'num_null') and n <> trunc(n) then
        raise exception '% must be a whole number.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
      if p_col <> 'sort' and n < 0 then
        raise exception '% can''t be negative.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
      if abs(n) > 1e13 then raise exception '% is too big.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
      if p_col in ('resale_pct') and n > 100 then
        raise exception '% must be 0–100.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
      if p_col = 'risk' and n > 1 then
        raise exception 'risk must be between 0 and 1.' using errcode = 'P0001', hint = 'bad_value';
      end if;
      if p_col in ('open_hour', 'close_hour') and n > 24 then
        raise exception '% must be an hour from 0 to 24.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
    else
      raise exception 'Unknown column type %', p_type using errcode = 'P0001';
  end case;
end $$;
revoke execute on function public.bl_admin_check_value(text, text, jsonb) from public, anon, authenticated;
