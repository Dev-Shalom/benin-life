-- L3: crowds (docs/PLACES.md "L3 crowds", docs/REAL_LIFE_PLAN.md section 2).
-- * npc_roster: named background people (name, role, motion, avatar preset in the AvatarConfigV2 shape, English
--   lines, Pidgin lines for street / market moments, place types and / or place ids, preferred zone, headliner).
-- * crowd_profiles: place type x hour band x day kind (all / weekday / weekend) -> how many people are there.
--   The most specific row wins (weekday/weekend before all, then the narrowest band, then sort).
-- * place_people(p_location, p_hour, p_weekday): who is present right now, deterministic per place x date x hour
--   (md5-seeded), so every player sees the same people. Capped by crowd.npc_list_max; `total` is the full count.
-- * Admin: both tables editable in Content (bl_admin_table_spec re-created from its live definition + 2 tables).
-- Idempotent and safe on a non-empty DB: seeds use `on conflict do nothing` (admin edits are never overwritten).

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
create table if not exists public.npc_roster (
  id           text primary key,
  name         text not null,
  role         text not null,
  motion       text not null default 'idle'
               check (motion in ('idle', 'dance', 'hype', 'dj', 'trade', 'serve', 'guard', 'sit', 'cheer', 'work', 'phone')),
  avatar       jsonb not null default '{}'::jsonb check (jsonb_typeof(avatar) = 'object' and length(avatar::text) <= 4000),
  lines        text not null default '',        -- English, one line per row
  pidgin       text not null default '',        -- Pidgin, used only at markets / streets / motor parks / PoS
  scenes       text[] not null default '{}',    -- place types (used when location_ids is empty)
  location_ids text[] not null default '{}',    -- only these places (wins over scenes)
  zone_key     text,                            -- preferred zone (dj, dance, bar, counter...)
  headliner    boolean not null default false,  -- always there while the place is open and has people
  sort         int not null default 0,
  active       boolean not null default true
);

create table if not exists public.crowd_profiles (
  id        text primary key,
  scene     text not null,
  days      text not null default 'all' check (days in ('all', 'weekday', 'weekend')),
  from_hour int not null check (from_hour between 0 and 23),
  to_hour   int not null check (to_hour between 1 and 24),
  npcs      int not null check (npcs between 0 and 500),
  sort      int not null default 0,
  active    boolean not null default true,
  constraint crowd_profiles_band_chk check (from_hour < to_hour)
);
create index if not exists crowd_profiles_scene_idx on public.crowd_profiles (scene);

alter table public.npc_roster     enable row level security;
alter table public.crowd_profiles enable row level security;
revoke all on table public.npc_roster, public.crowd_profiles from public, anon, authenticated;
grant select on table public.npc_roster, public.crowd_profiles to authenticated;
drop policy if exists npc_roster_read on public.npc_roster;
create policy npc_roster_read on public.npc_roster for select using (true);
drop policy if exists crowd_profiles_read on public.crowd_profiles;
create policy crowd_profiles_read on public.crowd_profiles for select using (true);

-- ---------------------------------------------------------------------
-- 2. Config
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('crowd.npc_list_max', '30', 'places', 'Most named people listed per place',
 'How many named background people place_people returns (People list + 3D). The People count still shows everyone.', 'number', 0, 60),
('crowd.rigs_high', '4', 'places', 'Full 3D people (Graphics High)',
 'Nearest people drawn with the full avatar rig at Graphics High (the rest are cheap figures).', 'number', 0, 8),
('crowd.rigs_low', '2', 'places', 'Full 3D people (Graphics Low)',
 'Nearest people drawn with the full avatar rig at Graphics Low. Medium is halfway.', 'number', 0, 8),
('crowd.chatter_seconds', '22', 'places', 'Background people speak every (s)',
 'Average seconds between background people saying a line as a bubble. 0 = never.', 'number', 0, 600)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 3. Seed: crowd profiles (real Benin rhythms; every place type has an all-day base row)
-- ---------------------------------------------------------------------
insert into public.crowd_profiles (id, scene, days, from_hour, to_hour, npcs, sort)
select v.scene || '.' || v.days || '.' || v.f || '-' || v.t, v.scene, v.days, v.f, v.t, v.n, 0
from (values
  ('club','all',0,24,2), ('club','all',21,24,24), ('club','all',0,3,28), ('club','all',3,5,10),
  ('club','weekend',21,24,40), ('club','weekend',0,3,45),
  ('market','all',0,24,2), ('market','all',0,5,0), ('market','all',5,7,15), ('market','all',7,12,60),
  ('market','all',12,16,40), ('market','all',16,19,25), ('market','all',19,21,8),
  ('street','all',0,24,4), ('street','all',0,5,1), ('street','all',7,17,12), ('street','all',17,23,22), ('street','weekend',18,24,30),
  ('motorpark','all',0,24,4), ('motorpark','all',0,5,2), ('motorpark','all',5,10,30), ('motorpark','all',10,16,15), ('motorpark','all',16,20,28),
  ('campus','all',0,24,2), ('campus','weekday',8,17,40), ('campus','weekday',17,21,12), ('campus','weekend',10,18,8),
  ('buka','all',0,24,3), ('buka','all',0,6,0), ('buka','all',7,11,8), ('buka','all',12,15,20), ('buka','all',18,21,10),
  ('bank','all',0,24,0), ('bank','weekday',8,16,14), ('bank','weekend',10,14,4),
  ('hospital','all',0,24,6), ('hospital','all',0,6,4), ('hospital','all',8,18,14),
  ('police','all',0,24,4), ('police','all',8,18,8),
  ('office','all',0,24,1), ('office','weekday',9,19,12), ('office','weekend',11,17,4),
  ('cyber','all',0,24,3), ('cyber','all',0,7,1), ('cyber','all',9,22,10),
  ('salon','all',0,24,0), ('salon','all',9,20,6), ('salon','weekend',9,20,10),
  ('hotel','all',0,24,4), ('hotel','all',18,23,12), ('hotel','weekend',12,23,16),
  ('mall','all',0,24,0), ('mall','all',9,22,18), ('mall','weekend',11,21,30),
  ('cinema','all',0,24,0), ('cinema','all',11,17,10), ('cinema','all',17,23,25), ('cinema','weekend',14,24,35),
  ('car_dealer','all',0,24,0), ('car_dealer','weekday',9,17,5), ('car_dealer','weekend',10,16,8),
  ('stadium','all',0,24,2), ('stadium','all',6,9,8), ('stadium','all',15,19,40), ('stadium','weekend',14,20,120),
  ('zoo','all',0,24,0), ('zoo','all',8,18,10), ('zoo','weekend',10,17,25),
  ('airport','all',0,24,4), ('airport','all',0,5,2), ('airport','all',6,20,14),
  ('museum','all',0,24,0), ('museum','weekday',9,17,6), ('museum','weekend',10,16,10),
  ('palace','all',0,24,2), ('palace','all',8,18,6),
  ('monument','all',0,24,3), ('monument','all',0,5,0), ('monument','all',8,20,10),
  ('shrine','all',0,24,1), ('shrine','all',6,19,3),
  ('workshop','all',0,24,0), ('workshop','weekday',8,18,6), ('workshop','weekend',9,15,4),
  ('farm','all',0,24,0), ('farm','all',6,12,6), ('farm','all',12,18,3),
  ('pos','all',0,24,1), ('pos','all',0,6,0), ('pos','all',7,21,8)
) as v(scene, days, f, t, n)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 4. Seed: the roster (~110 people). avatar = a partial AvatarConfigV2; "preset" = the outfit preset applied.
--    E'\n' separates lines. Pidgin only for market / street / motor park / PoS people.
-- ---------------------------------------------------------------------
insert into public.npc_roster (id, name, role, motion, avatar, lines, pidgin, scenes, location_ids, zone_key, headliner, sort)
select v.id, v.name, v.role, v.motion,
       jsonb_strip_nulls(jsonb_build_object('v', 2, 'gender', v.g, 'skin', v.skin, 'hair', v.hair, 'preset', v.preset,
                                            'top', case when v.top is null then null else jsonb_build_object('c', v.top) end)),
       v.lines, v.pidgin, v.scenes::text[], v.locs::text[], v.zone, v.head, v.sort
from (values
  -- ===== 360 Signature (the open club) =====
  ('mc_lightning','MC Lightning','Hype man','hype','male','tone5','waves','yahoo','#111111',
   E'Make some noise for Benin City!\nIf you are having a good time, hands in the air!\n360 Signature, where my big boys dey?\nDJ Ekpen, bring it back!',
   '', '{}', '{club_360}', 'dj', true, 1),
  ('dj_ekpen','DJ Ekpen','DJ','dj','male','tone4','low_cut','street','#1d1d24',
   E'This next one is for the ladies.\nRequests? Tip the DJ first.\nWe are going till 5 AM.',
   '', '{}', '{club_360}', 'dj', true, 2),
  ('bouncer_osaze','Big Osaze','Bouncer','guard','male','tone6','bald','corporate','#111111',
   E'VIP is wristbands only.\nNo wahala tonight, enjoy yourself.\nStep aside, let them pass.',
   '', '{}', '{club_360}', 'vip', true, 3),
  ('waiter_ivie_360','Ivie','Waitress','serve','female','tone3','bun','corporate','#111111',
   E'Another round for your table?\nThe hookah is coming now.\nBottle service? I will bring the sparklers.',
   '', '{}', '{club_360}', 'bar', true, 4),
  -- ===== every club =====
  ('dj_uyi','DJ Uyi','DJ','dj','male','tone5','high_top','street','#2a2440',
   E'Benin to the world!\nOne more Afrobeats jam, then amapiano.\nHands up for the birthday girl!',
   '', '{}', '{club_de_medici,rome_club,cube_nightlife,versus_lounge,owambe_republic,kingdom_lounge,bronze_lounge}', 'dj', true, 5),
  ('bouncer_igbinosa','Igbinosa','Bouncer','guard','male','tone5','bald','corporate','#1a1a1a',
   E'ID first, then you enter.\nNo fighting inside, abeg.\nTable is reserved, oga.',
   '', '{club}', '{}', 'vip', true, 6),
  ('bartender_efe','Efe','Bartender','serve','male','tone4','low_cut','corporate','#202020',
   E'Chapman or something stronger?\nThe Hennessy is cold tonight.\nTab or cash?',
   '', '{club}', '{}', 'bar', false, 7),
  ('chief_omoruyi','Chief Omoruyi','Big spender','sit','male','tone4','bald','senator','#f3f0e8',
   E'Bring two more bottles!\nMy driver is outside, no rush.\nThis is how we do it in GRA.',
   '', '{club}', '{}', 'vip', false, 8),
  ('osato_glam','Osato','Big girl','sit','female','tone3','bone_straight','glam','#c74b8a',
   E'Take my picture with the sparklers!\nWho is buying the next round?\nThis song is my jam!',
   '', '{club}', '{}', 'vip', false, 9),
  ('dancer_osas','Osas','Party goer','dance','male','tone4','waves','street','#d2342a', E'This DJ is on fire tonight!\nWe no dey go home.\nMy legs are not tired yet!', '', '{club}', '{}', 'dance', false, 10),
  ('dancer_eki','Eki','Party goer','dance','female','tone3','braids','glam','#6d4aa0', E'Amapiano is everything!\nDance with me!\nThis is my song!', '', '{club}', '{}', 'dance', false, 11),
  ('dancer_nosa','Nosa','Party goer','dance','male','tone5','low_cut','yahoo','#111111', E'Spray the money!\nBenin boys know how to party.\nOne more song, then I go.', '', '{club}', '{}', 'dance', false, 12),
  ('dancer_imade','Imade','Party goer','dance','female','tone4','ponytail','glam','#e07a2e', E'My shoes are killing me, but I am still dancing.\nWho knows this song?\nLet us take a video!', '', '{club}', '{}', 'dance', false, 13),
  ('dancer_ehis','Ehis','Party goer','dance','male','tone3','high_top','street','#2f6fb3', E'Na today we go enjoy.\nTurn it up!\nThe vibe here is mad.', '', '{club}', '{}', 'dance', false, 14),
  ('dancer_adesuwa','Adesuwa','Party goer','dance','female','tone5','bantu_knots','glam','#1f7a3f', E'This is my birthday week!\nI came with my girls.\nDJ, play Burna!', '', '{club}', '{}', 'dance', false, 15),
  ('dancer_osaro','Osaro','Party goer','dance','male','tone6','twists','street','#d9a441', E'The bass is shaking my chest!\nWho get lighter?\nNo sleep tonight.', '', '{club}', '{}', 'dance', false, 16),
  ('dancer_itohan','Itohan','Party goer','dance','female','tone2','bun','glam','#0b625a', E'I love this place.\nWe are here till morning.\nSlow down the music small.', '', '{club}', '{}', 'dance', false, 17),
  ('dancer_osagie','Osagie','Party goer','dance','male','tone4','locs','yahoo','#111111', E'Make we shake body!\nOga DJ, you too much.\nWhere my guys dey?', '', '{club}', '{}', 'dance', false, 18),
  -- ===== markets =====
  ('mama_eki','Mama Eki','Pepper seller','trade','female','tone5','cornrows','market','#d2342a',
   E'Fresh pepper and tomatoes here.\nCome and buy, my customer!',
   E'Customer, come buy pepper!\nI go add you small, no worry.\nNa fresh tomato be this o.', '{market}', '{}', 'foodstuff', false, 30),
  ('efosa_yam','Efosa','Yam seller','trade','male','tone5','low_cut','ankara','#b5552b',
   E'Big tubers from Ekiadolor.\nThree for a good price.',
   E'Oga, see yam wey sweet!\nNa last price be dat.\nCarry two, I go dash you one.', '{market}', '{}', 'traders', false, 31),
  ('ivie_provisions','Ivie','Provisions seller','trade','female','tone4','braids','market','#2f6fb3',
   E'Milk, sugar, Milo, all here.\nI have change, no problem.',
   E'Aunty, wetin you wan buy?\nMilo don cost o, but I go do am for you.\nNa original, no be fake.', '{market}', '{}', 'traders', false, 32),
  ('itohan_fabrics','Aunty Itohan','Fabric seller','trade','female','tone3','cornrows','boubou','#6d4aa0',
   E'Original Hollandaise, just arrived.\nThis lace will fit you well.',
   E'My sister, see better material!\nNa six yards, complete.\nI no dey cheat customer.', '{market}', '{}', 'traders', false, 33),
  ('iyobosa_mamaput','Mama Iyobosa','Mama put','trade','female','tone5','cornrows','market','#e07a2e',
   E'Rice and stew, hot and fresh.\nOwo soup with starch today.',
   E'Come chop! Rice don done.\nMeat na extra o.\nSit down, I go serve you now now.', '{market}', '{}', 'mama_put', true, 34),
  ('nosa_truck','Nosa','Truck pusher','work','male','tone6','bald','street','#4a4038',
   E'Make way, heavy load coming!\nI can carry your things to the park.',
   E'Shift! Shift! Load dey come!\nAunty, I go carry am reach your motor.\nGive me small change abeg.', '{market}', '{}', 'loading', false, 35),
  ('omoruyi_drinks','Omoruyi','Drinks seller','trade','male','tone4','low_cut','ankara','#1f7a3f',
   E'Cold drinks here, malt and Fanta.\nWater is ice cold.',
   E'Cold mineral dey!\nPure water, one one hundred.\nNa ice block cold am, e sweet.', '{market}', '{}', 'drinks', false, 36),
  ('osaretin_hawker','Osaretin','Pure water hawker','work','male','tone5','low_cut','street','#3a3f6e',
   E'Pure water, cold pure water!',
   E'Pure water! Pure water!\nE cold well well.\nBuy two, e cheap.', '{market,motorpark,street}', '{}', null, false, 37),
  ('mama_ngozi','Mama Ngozi','Tomato seller','trade','female','tone4','bun','market','#c74b8a',
   E'One basket or a small bowl?\nFresh from the farm this morning.',
   E'Tomato dey o! Fresh one.\nI go reduce am for you.\nNa morning market price.', '{market}', '{}', 'foodstuff', false, 38),
  ('imade_shopper','Imade','Shopper','idle','female','tone3','ponytail','ankara','#d9a441',
   E'Everything is so expensive this week.\nI need crayfish and ogbono.',
   E'Abeg reduce am small.\nNa so una dey sell am now?', '{market,mall}', '{}', null, false, 39),
  ('ehis_shopper','Ehis','Shopper','phone','male','tone4','waves','street','#7dbb45',
   E'My wife sent me a long list.\nWhere do they sell garri here?',
   E'Oga, how much be this one?\nI dey find my wife.', '{market,mall}', '{}', null, false, 40),
  ('aunty_uyi','Aunty Uyi','Snail seller','trade','female','tone6','cornrows','market','#7dbb45',
   E'Big snails from Okada road.\nPeriwinkle and snails, fresh.',
   E'Congo meat dey! Fresh one.\nNa big ones remain.', '{market}', '{}', 'traders', false, 41),
  -- ===== streets =====
  ('mallam_sani','Mallam Sani','Suya man','trade','male','tone5','low_cut','senator','#f3f0e8',
   E'Suya, hot suya!\nWith onions and yaji?',
   E'Suya dey hot! Come buy.\nOga, how many sticks?\nI go add pepper well.', '{street,motorpark}', '{}', 'suya', true, 50),
  ('osagie_corner','Osagie','Corner boy','sit','male','tone5','waves','street','#d2342a',
   E'Did you see the match last night?\nNothing is happening today.',
   E'How far, my guy?\nNa so we dey o.\nWetin dey happen for town?', '{street}', '{}', 'corner', false, 51),
  ('uyi_corner','Uyi','Corner boy','sit','male','tone4','high_top','street','#2f6fb3',
   E'Who wants to play draughts?\nThe light just came back!',
   E'NEPA don bring light!\nMy guy, borrow me two hundred.\nWe dey here, dey watch.', '{street}', '{}', 'corner', false, 52),
  ('efe_viewer','Efe','Football fan','cheer','male','tone4','low_cut','street','#1f7a3f',
   E'Goal! Did you see that?\nThat referee is blind.',
   E'Goal! Goal!\nThat referee don collect money.\nArsenal go win today.', '{street}', '{}', 'screen', false, 53),
  ('ivie_street','Ivie','Passer-by','phone','female','tone3','braids','street','#c74b8a',
   E'I am almost there, wait for me.\nThis road is so dark at night.',
   E'I dey come, no vex.\nThis road no get light.', '{street}', '{}', null, false, 54),
  ('keke_efosa','Efosa','Keke rider','idle','male','tone5','low_cut','keke','#d9a441',
   E'Ring Road? Climb in.\nI am going towards Uselu.',
   E'Ring Road! Ring Road!\nOne chance remain.\nNa two hundred, no argue.', '{street,motorpark}', '{}', 'keke', false, 55),
  -- ===== motor parks =====
  ('agbero_nosa','Nosa','Agbero','hype','male','tone6','bald','street','#3a3f6e',
   E'Lagos bus is loading!\nAbuja, Abuja, one seat left!',
   E'Lagos! Lagos! E remain one!\nOga, enter, motor don full.\nUselu! Uselu! One chance!', '{motorpark}', '{}', 'buses', true, 60),
  ('driver_ehigie','Ehigie','Bus driver','idle','male','tone5','low_cut','ankara','#b5552b',
   E'We move once the bus is full.\nRoad is clear to Lagos today.',
   E'Motor go move soon soon.\nNo shake, I sabi road well.', '{motorpark}', '{}', 'buses', false, 61),
  ('keke_osamudiamen','Osamudiamen','Keke rider','idle','male','tone4','waves','keke','#e07a2e',
   E'Where are you going?\nSiluko, Sakponba, I go there.',
   E'Where you dey go?\nNa keke be the fastest.\nShift small make another person enter.', '{motorpark}', '{}', 'keke', false, 62),
  ('keke_eghosa','Eghosa','Keke rider','idle','female','tone5','cornrows','keke','#7dbb45',
   E'Lady rider, safe and fast.\nUniben gate? Come.',
   E'Aunty, climb make we go.\nNa me dey drive pass all of dem.', '{motorpark}', '{}', 'keke', false, 63),
  ('traveller_osas','Osas','Traveller','sit','female','tone3','bun','corporate','#2f6fb3',
   E'This bus has been loading for an hour.\nI hope we reach before dark.',
   E'This motor never full?\nI don tire for here.', '{motorpark,airport}', '{}', 'bench', false, 64),
  ('traveller_ikpomwosa','Ikpomwosa','Traveller','sit','male','tone4','low_cut','senator','#f3f0e8',
   E'I am going to Lagos for business.\nWhich bus leaves first?',
   E'Abeg, which motor dey go Lagos?\nMake e no do one chance o.', '{motorpark}', '{}', 'bench', false, 65),
  ('kiosk_eseosa','Eseosa','Kiosk owner','serve','female','tone4','cornrows','ankara','#d2342a',
   E'Recharge card, biscuits, water.\nI have small change.',
   E'Wetin you need? Card dey.\nNo change o, buy something join am.', '{motorpark}', '{}', 'kiosk', false, 66),
  -- ===== PoS =====
  ('pos_esohe','Esohe','PoS agent','serve','female','tone4','braids','corporate','#2f6fb3',
   E'Withdrawal or transfer?\nNetwork is a bit slow today.',
   E'Network dey do anyhow today.\nNa one hundred charge per ten thousand.\nWait small, e dey go.', '{pos}', '{}', 'kiosk', true, 70),
  ('pos_airtime','Uyiosa','Airtime seller','trade','male','tone5','low_cut','street','#1f7a3f',
   E'MTN, Glo, Airtel, 9mobile.\nData bundle also.',
   E'Card dey! Which network?\nI fit load am for you direct.', '{pos}', '{}', 'airtime', false, 71),
  ('pos_customer1','Eghe','Customer','phone','female','tone3','ponytail','ankara','#e07a2e',
   E'My transfer has not reflected.\nI need cash for the market.',
   E'This network sef!\nAbeg do am quick, I dey rush.', '{pos,bank}', '{}', 'line', false, 72),
  ('pos_customer2','Edosa','Customer','idle','male','tone5','low_cut','corporate','#3a3f6e',
   E'The ATM is not paying again.\nHow long is the line?',
   E'Na so this line long?\nATM no dey pay again.', '{pos}', '{}', 'line', false, 73),
  -- ===== bukas =====
  ('mama_osas','Mama Osas','Buka owner','serve','female','tone5','cornrows','market','#d9a441',
   E'Banga soup and starch today.\nSit down, my dear, food is ready.\nYou want extra meat?',
   '', '{buka}', '{}', 'counter', true, 80),
  ('buka_waiter','Osahon','Waiter','serve','male','tone4','low_cut','ankara','#0b625a',
   E'Rice or swallow?\nThe pepper soup is hot today.',
   '', '{buka}', '{}', 'tables', false, 81),
  ('buka_cust1','Kingsley','Customer','sit','male','tone4','low_cut','corporate','#2f6fb3',
   E'This owo soup is the best in town.\nMake mine extra hot.',
   '', '{buka}', '{}', 'tables', false, 82),
  ('buka_cust2','Precious','Customer','sit','female','tone3','braids','ankara','#c74b8a',
   E'I come here every lunch break.\nThe meat is so soft today.',
   '', '{buka}', '{}', 'tables', false, 83),
  ('buka_cust3','Edwin','Customer','sit','male','tone6','bald','keke','#d9a441',
   E'Turn up the TV, the match is on.\nOne more plate, please.',
   '', '{buka}', '{}', 'tv', false, 84),
  -- ===== UNIBEN =====
  ('student_osaro','Osaro','Student','idle','male','tone4','high_top','student','#2f6fb3', E'Exams start on Monday.\nDid you copy the lecture notes?\nThe library closes at nine.', '', '{campus}', '{}', 'quad', false, 90),
  ('student_eki','Eki','Student','phone','female','tone3','braids','student','#c74b8a', E'Lecturer has not come again.\nWho has the past questions?\nI need a strong Wi-Fi.', '', '{campus}', '{}', 'quad', false, 91),
  ('student_uyi','Uyi','Student','sit','male','tone5','waves','student','#1f7a3f', E'I have read this page five times.\nThe test is tomorrow.\nKeep quiet, please.', '', '{campus}', '{}', 'library', false, 92),
  ('student_ivie','Ivie','Student','sit','female','tone4','bun','student','#6d4aa0', E'GST lecture is full again.\nI sat in front today.\nThe projector is not working.', '', '{campus}', '{}', 'lecture', false, 93),
  ('student_efosa','Efosa','Student','sit','male','tone4','low_cut','student','#d2342a', E'Is this seat taken?\nWho is the course rep?\nWe have a group project.', '', '{campus}', '{}', 'lecture', false, 94),
  ('student_omoye','Omoye','Student','idle','female','tone2','ponytail','student','#d9a441', E'Hostel water is not running.\nLet us go to the back gate for food.\nSUG week starts tomorrow.', '', '{campus}', '{}', 'quad', false, 95),
  ('lecturer_aisien','Dr. Aisien','Lecturer','idle','male','tone4','bald','corporate','#3a3f6e', E'Submit your assignments by Friday.\nAttendance is compulsory.\nWho can answer this question?', '', '{campus}', '{}', 'lecture', true, 96),
  ('staff_edosa','Mr. Edosa','Faculty officer','sit','male','tone5','low_cut','senator','#f3f0e8', E'Come back after lunch.\nYour result is not out yet.\nBring your clearance form.', '', '{campus}', '{}', 'staff', false, 97),
  -- ===== bank =====
  ('banker_omoregie','Mrs. Omoregie','Banker','serve','female','tone4','bone_straight','corporate','#2f6fb3', E'Good day, how may I help you?\nPlease fill this deposit slip.\nYour BVN, please.', '', '{bank}', '{}', 'counter', true, 100),
  ('bank_guard','Idahosa','Security guard','guard','male','tone6','low_cut','police','#3a3f6e', E'Drop your phone in the box, please.\nOne at a time through the door.\nThe ATM is working now.', '', '{bank}', '{}', 'atm', true, 101),
  ('bank_cust1','Nekpen','Customer','sit','female','tone3','braids','corporate','#6d4aa0', E'I have been waiting for an hour.\nThey called number forty.', '', '{bank}', '{}', 'waiting', false, 102),
  ('bank_cust2','Aiyamenkhue','Customer','sit','male','tone5','low_cut','senator','#f3f0e8', E'I came to update my account.\nThe network is down again.', '', '{bank}', '{}', 'waiting', false, 103),
  -- ===== hospitals =====
  ('nurse_osayande','Nurse Osayande','Nurse','serve','female','tone4','bun','nurse',null, E'Please take a seat, the doctor will see you.\nHave you registered?\nTake this twice a day after food.', '', '{hospital}', '{}', 'reception', true, 110),
  ('nurse_efe','Nurse Efe','Nurse','idle','female','tone5','cornrows','nurse',null, E'Visiting hours end at six.\nLet me check your blood pressure.', '', '{hospital}', '{}', 'ward', false, 111),
  ('doctor_uwaifo','Dr. Uwaifo','Doctor','idle','male','tone4','low_cut','corporate','#f3f0e8', E'It is malaria, you will be fine.\nGet some rest and drink water.\nNext patient, please.', '', '{hospital}', '{}', 'staff', false, 112),
  ('patient_osagie','Osagie','Patient','sit','male','tone5','low_cut','ankara','#b5552b', E'My head has been aching since morning.\nI have been here since eight.', '', '{hospital}', '{}', 'reception', false, 113),
  ('patient_ese','Ese','Patient','sit','female','tone3','bun','ankara','#7dbb45', E'I came for my test result.\nThe queue is long today.', '', '{hospital}', '{}', 'pharmacy', false, 114),
  -- ===== police =====
  ('police_igbinedion','Sergeant Igbinedion','Police officer','guard','male','tone5','low_cut','police',null, E'Write your statement here.\nWhere were you on Friday night?\nWait on that bench.', '', '{police}', '{}', 'desk', true, 120),
  ('police_osaze','Corporal Osaze','Police officer','idle','female','tone4','bun','police',null, E'Who is next?\nThe DPO is not in today.', '', '{police}', '{}', 'board', false, 121),
  ('complainant_aisosa','Aisosa','Complainant','sit','female','tone3','braids','ankara','#d2342a', E'They stole my phone at the park.\nI have been waiting since morning.', '', '{police}', '{}', 'bench', false, 122),
  -- ===== tech hub =====
  ('dev_osayi','Osayi','Developer','sit','male','tone4','locs','street','#25232b', E'The server is down again.\nOne more bug, then I go home.\nWho broke the build?', '', '{office}', '{}', 'desks', false, 130),
  ('dev_imuetinyan','Imuetinyan','Designer','sit','female','tone3','twists','street','#c74b8a', E'Make the logo bigger, they said.\nThe client wants it by tonight.', '', '{office}', '{}', 'desks', false, 131),
  ('dev_ewaen','Ewaen','Founder','phone','male','tone5','low_cut','corporate','#1d1d24', E'We are raising our seed round.\nThe pitch is on Thursday.', '', '{office}', '{}', 'stage', false, 132),
  ('barista_ofure','Ofure','Barista','serve','female','tone4','bun','street','#0b625a', E'Coffee or zobo?\nThe Wi-Fi password is on the board.', '', '{office}', '{}', 'coffee', false, 133),
  -- ===== cyber cafe =====
  ('cyber_attendant','Obehi','Attendant','serve','female','tone4','braids','ankara','#2f6fb3', E'Thirty minutes is three hundred.\nPrinting is extra.', '', '{cyber}', '{}', 'snacks', true, 140),
  ('cyber_gamer','Osahon','Gamer','sit','male','tone5','high_top','street','#d2342a', E'One more FIFA match!\nThis network is slow today.', '', '{cyber}', '{}', 'desks', false, 141),
  ('cyber_student','Eseosa','Student','sit','female','tone3','ponytail','student','#d9a441', E'I am registering my JAMB.\nThe portal keeps crashing.', '', '{cyber}', '{}', 'desks', false, 142),
  -- ===== salon =====
  ('barber_osas','Barber Osas','Barber','serve','male','tone5','waves','street','#f3f0e8', E'Low cut or punk?\nSit still, let me fix your line.\nNEPA took light, the clipper is on battery.', '', '{salon}', '{}', 'chairs', true, 150),
  ('salon_cust1','Uyi','Customer','sit','male','tone4','low_cut','ankara','#1f7a3f', E'Make it clean for Sunday.\nHow long is the wait?', '', '{salon}', '{}', 'bench', false, 151),
  ('salon_cust2','Omosede','Customer','sit','female','tone3','bone_straight','glam','#c74b8a', E'I want knotless braids.\nIs the stylist around?', '', '{salon}', '{}', 'bench', false, 152),
  -- ===== hotels =====
  ('hotel_reception','Ruth','Receptionist','serve','female','tone3','bone_straight','corporate','#3a3f6e', E'Welcome, do you have a booking?\nBreakfast is from seven to ten.', '', '{hotel}', '{}', 'reception', true, 160),
  ('hotel_waiter','Ehimen','Waiter','serve','male','tone4','low_cut','corporate','#111111', E'Table for two?\nThe chef recommends the peppered fish.', '', '{hotel}', '{}', 'restaurant', false, 161),
  ('hotel_guest1','Mr. Ehigiator','Guest','sit','male','tone4','bald','senator','#f3f0e8', E'The meeting runs late tonight.\nThis pool is so quiet.', '', '{hotel}', '{}', 'lounge', false, 162),
  ('hotel_guest2','Mrs. Igbinoba','Guest','sit','female','tone3','bun','boubou','#e07a2e', E'We are here for a wedding.\nThe room service is good.', '', '{hotel}', '{}', 'pool', false, 163),
  -- ===== mall =====
  ('mall_cashier','Blessing','Cashier','serve','female','tone4','bun','corporate','#d2342a', E'Card or transfer?\nDo you have a bag?\nNext customer, please.', '', '{mall}', '{}', 'checkout', true, 170),
  ('mall_shopper1','Eghosa','Shopper','idle','male','tone4','waves','street','#2f6fb3', E'Shoprite is packed today.\nLet us go and see a film after.', '', '{mall}', '{}', 'shoprite', false, 171),
  ('mall_shopper2','Itohan','Shopper','phone','female','tone3','ponytail','glam','#c74b8a', E'I am at the mall, where are you?\nThey have a sale on shoes.', '', '{mall}', '{}', 'walk', false, 172),
  -- ===== cinema =====
  ('cinema_attendant','Ewere','Snack attendant','serve','female','tone4','braids','corporate','#e07a2e', E'Popcorn, sweet or salted?\nThe next film starts in ten minutes.', '', '{cinema}', '{}', 'snacks', true, 180),
  ('cinema_goer1','Osayamen','Movie goer','idle','male','tone5','high_top','street','#1d1d24', E'Is the new Nollywood film showing?\nTwo tickets, please.', '', '{cinema}', '{}', 'screen', false, 181),
  ('cinema_goer2','Esosa','Movie goer','phone','female','tone3','braids','glam','#6d4aa0', E'We are late, the film has started!\nGet the big popcorn.', '', '{cinema}', '{}', 'arcade', false, 182),
  ('cinema_goer3','Ikponmwosa','Gamer','idle','male','tone4','low_cut','street','#7dbb45', E'I beat the high score!\nOne more token.', '', '{cinema}', '{}', 'arcade', false, 183),
  -- ===== car dealers =====
  ('car_sales_ehigie','Mr. Ehigie','Car salesman','trade','male','tone4','low_cut','corporate','#1d1d24', E'This one is Belgium-used, very clean.\nI can give you a good price today.\nTest drive? Let me get the key.', '', '{car_dealer}', '{}', 'showroom', true, 190),
  ('car_sales_osemwegie','Osemwegie','Car salesman','trade','male','tone5','waves','corporate','#3a3f6e', E'The engine is original, no story.\nCash or bank transfer?', '', '{car_dealer}', '{}', 'lot', false, 191),
  ('car_buyer','Mrs. Aigbe','Customer','idle','female','tone3','bone_straight','corporate','#c74b8a', E'Is the AC working?\nI want something for school runs.', '', '{car_dealer}', '{}', 'showroom', false, 192),
  -- ===== stadium =====
  ('fan_osas','Osas','Football fan','cheer','male','tone4','low_cut','street','#1f7a3f', E'Come on, Insurance!\nThe referee is blind!\nGoal!', '', '{stadium}', '{}', 'popular', false, 200),
  ('fan_eki','Eki','Football fan','cheer','female','tone3','cornrows','street','#7dbb45', E'We are winning today!\nPass the ball!', '', '{stadium}', '{}', 'popular', false, 201),
  ('fan_nosa','Nosa','Football fan','cheer','male','tone5','bald','street','#d9a441', E'Sing with me!\nWho is that striker?', '', '{stadium}', '{}', 'popular', false, 202),
  ('fan_chief','Chief Ogbe','VIP fan','sit','male','tone4','bald','agbada','#f3f0e8', E'This team needs a new coach.\nBring me a cold drink.', '', '{stadium}', '{}', 'vip', false, 203),
  ('stadium_seller','Oghogho','Gate seller','trade','female','tone5','cornrows','market','#e07a2e', E'Jerseys, scarves, whistles!\nGala and malt at the gate.', '', '{stadium}', '{}', 'gate', true, 204),
  -- ===== zoo =====
  ('zookeeper','Mr. Odia','Zookeeper','work','male','tone5','low_cut','keke','#1f7a3f', E'Do not feed the animals, please.\nThe lions eat at four.', '', '{zoo}', '{}', 'lions', true, 210),
  ('zoo_family1','Mrs. Edokpolo','Visitor','idle','female','tone3','bun','ankara','#d2342a', E'The children love the monkeys.\nLet us take a picture here.', '', '{zoo}', '{}', 'birds', false, 211),
  ('zoo_family2','Osahenrumwen','Visitor','sit','male','tone4','low_cut','ankara','#2f6fb3', E'This place is calm today.\nPass me the meat pie.', '', '{zoo}', '{}', 'picnic', false, 212),
  -- ===== airport =====
  ('airport_traveller1','Mr. Asemota','Traveller','sit','male','tone4','bald','corporate','#1d1d24', E'My flight to Abuja is delayed.\nIs there Wi-Fi here?', '', '{airport}', '{}', 'deck', false, 220),
  ('airport_traveller2','Nosakhare','Traveller','phone','female','tone3','bone_straight','glam','#6d4aa0', E'I just landed, come and pick me.\nThe bags are taking forever.', '', '{airport}', '{}', 'deck', false, 221),
  ('airport_cafe','Ifueko','Cafe attendant','serve','female','tone4','bun','corporate','#b5552b', E'Tea or coffee?\nMeat pie is fresh.', '', '{airport}', '{}', 'cafe', true, 222),
  -- ===== museum / palace / monument / shrine =====
  ('museum_guide','Mr. Ogiamien','Museum guide','idle','male','tone5','low_cut','bini','#f3f0e8', E'These bronze heads are over five hundred years old.\nThis plaque shows the Oba in court.\nNo flash photography, please.', '', '{museum}', '{}', 'heads', true, 230),
  ('museum_visitor1','Adesuwa','Visitor','idle','female','tone3','braids','ankara','#0b625a', E'Our history is so rich.\nSome of these came back from London.', '', '{museum}', '{}', 'gallery', false, 231),
  ('museum_visitor2','Ehimare','Student','phone','male','tone4','low_cut','student','#2f6fb3', E'I am writing a project on the bronzes.\nCan I take notes here?', '', '{museum}', '{}', 'gallery', false, 232),
  ('palace_guard','Ihama','Palace guard','guard','male','tone5','bald','bini','#f3f0e8', E'Greet the palace with respect.\nVisitors wait at the gate.', '', '{palace}', '{}', 'gate', true, 240),
  ('palace_chief','Chief Ezomo','Palace chief','idle','male','tone4','bald','bini','#d2342a', E'Oba ghato okpere!\nThe Igue festival is coming soon.', '', '{palace}', '{}', 'courtyard', false, 241),
  ('palace_visitor','Iyare','Visitor','idle','female','tone3','cornrows','bini','#d2342a', E'The palace walls hold so much history.\nWe came for the festival.', '', '{palace,monument}', '{}', null, false, 242),
  ('emotan_visitor','Osamwonyi','Visitor','idle','male','tone5','low_cut','ankara','#e07a2e', E'Queen Emotan watches over the market.\nLet us take a picture by the statue.', '', '{monument}', '{}', 'statue', false, 243),
  ('emotan_seller','Mama Oghogho','Groundnut seller','trade','female','tone5','cornrows','market','#d9a441', E'Groundnut and banana, fresh.\nSit and rest, my child.', '', '{monument}', '{}', 'bench', false, 244),
  ('shrine_keeper','Pa Osemwengie','Shrine keeper','sit','male','tone5','bald','bini','#f3f0e8', E'Remove your shoes before you enter.\nSpeak softly here.', '', '{shrine}', '{}', 'altar', true, 250),
  ('shrine_visitor','Ekiomado','Visitor','idle','female','tone4','cornrows','bini','#d2342a', E'I came to give thanks.\nMy mother sent me.', '', '{shrine}', '{}', 'courtyard', false, 251),
  -- ===== Igun Street / farm =====
  ('caster_igun','Osarobo','Bronze caster','work','male','tone5','bald','bini','#f3f0e8', E'My family has cast bronze for generations.\nThe furnace is hot, stand back.', '', '{workshop}', '{}', 'furnace', true, 260),
  ('caster_apprentice','Efe','Apprentice','work','male','tone4','low_cut','street','#4a4038', E'Master says I will finish my first head this year.\nPass me the wax.', '', '{workshop}', '{}', 'display', false, 261),
  ('farmer_okoro','Pa Okungbowa','Farmer','work','male','tone5','bald','ankara','#7dbb45', E'The cassava will be ready next month.\nRain has been good this year.', '', '{farm}', '{}', 'rows', true, 270),
  ('farmer_aunty','Mama Ekhator','Farmer','work','female','tone5','cornrows','market','#b5552b', E'We start before the sun gets hot.\nHelp me carry this basket.', '', '{farm}', '{}', 'shed', false, 271)
) as v(id, name, role, motion, g, skin, hair, preset, top, lines, pidgin, scenes, locs, zone, head, sort)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 5. Helpers + place_people()
-- ---------------------------------------------------------------------
-- how many people are at a place type at an hour on a weekday (0 = Monday .. 6 = Sunday); null = no profile
create or replace function public.bl_crowd_count(p_scene text, p_hour int, p_weekday int) returns int
language sql stable set search_path = public as $$
  select npcs from crowd_profiles
   where active and scene = p_scene and p_hour >= from_hour and p_hour < to_hour
     and (days = 'all' or (days = 'weekend') = (p_weekday >= 5))
   order by (days <> 'all') desc, (to_hour - from_hour) asc, sort, id
   limit 1;
$$;
revoke execute on function public.bl_crowd_count(text, int, int) from public, anon, authenticated;

create or replace function public.bl_lines(p_text text) returns text[]
language sql immutable as $$
  select coalesce(array_agg(btrim(l) order by n) filter (where btrim(l) <> ''), '{}')
  from unnest(string_to_array(coalesce(p_text, ''), E'\n')) with ordinality as t(l, n);
$$;
revoke execute on function public.bl_lines(text) from public, anon, authenticated;

-- Who is present at a place: deterministic per place x date x hour (every player sees the same people).
-- p_hour / p_weekday override the clock (visual checks); null = now (Benin time).
create or replace function public.place_people(p_location text, p_hour int default null, p_weekday int default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_loc   locations;
  v_clock jsonb := bl_game_clock();
  v_hour  int;
  v_wd    int;
  v_open  boolean;
  v_count int;
  v_max   int := greatest(0, least(60, coalesce(bl_cfg('crowd.npc_list_max'), 30)::int));
  v_seed  text;
  v_pidgin boolean;
  v_npcs  jsonb;
begin
  select * into v_loc from locations where id = p_location;
  if not found then
    raise exception 'Unknown place.' using errcode = 'P0001', hint = 'unknown_location';
  end if;
  v_hour := coalesce(p_hour, (v_clock->>'hour')::int);
  v_wd   := coalesce(p_weekday, (v_clock->>'weekday')::int);
  if v_hour < 0 or v_hour > 23 or v_wd < 0 or v_wd > 6 then
    raise exception 'Hour must be 0-23 and weekday 0-6.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  -- open at that hour (same rule as bl_place_open)
  v_open := coalesce(v_loc.active, true);
  if v_open and v_loc.open_hour is not null and bl_cfg_bool('places.hours_enabled') and v_loc.open_hour <> v_loc.close_hour then
    if v_loc.open_hour < v_loc.close_hour then v_open := v_hour >= v_loc.open_hour and v_hour < v_loc.close_hour;
    else v_open := v_hour >= v_loc.open_hour or v_hour < v_loc.close_hour; end if;
  end if;
  if v_loc.scene like 'home%' or not v_open then
    v_count := 0;
  else
    v_count := coalesce(bl_crowd_count(v_loc.scene, v_hour, v_wd), 0);
  end if;
  v_seed   := p_location || ':' || (v_clock->>'date') || ':' || v_hour;
  v_pidgin := v_loc.scene in ('market', 'street', 'motorpark', 'pos');

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'name', r.name, 'role', r.role, 'motion', r.motion, 'zone', r.zone_key,
           'headliner', r.headliner, 'avatar', r.avatar,
           'lines', r.lines,
           'line', r.lines[1 + (('x' || substr(md5(v_seed || ':line:' || r.id), 1, 7))::bit(28)::int % greatest(1, cardinality(r.lines)))]
         ) order by r.rk), '[]'::jsonb)
    into v_npcs
  from (
    select n.id, n.name, n.role, n.motion, n.zone_key, n.headliner, n.avatar,
           case when v_pidgin then bl_lines(n.pidgin) || bl_lines(n.lines) else bl_lines(n.lines) end as lines,
           row_number() over (order by n.headliner desc, md5(v_seed || ':' || n.id), n.id) as rk
    from npc_roster n
    where n.active
      and (p_location = any(n.location_ids) or (cardinality(n.location_ids) = 0 and v_loc.scene = any(n.scenes)))
  ) r
  where r.rk <= least(v_count, v_max);

  return jsonb_build_object('location', p_location, 'hour', v_hour, 'weekday', v_wd, 'open', v_open,
                            'total', greatest(v_count, jsonb_array_length(v_npcs)), 'npcs', v_npcs);
end $$;
revoke execute on function public.place_people(text, int, int) from public, anon;
grant execute on function public.place_people(text, int, int) to authenticated;

-- ---------------------------------------------------------------------
-- 6. Admin: npc_roster + crowd_profiles editable (Content). Re-created from the live definition (F1) + 2 tables.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bl_admin_table_spec(p_table text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
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
              "congestion":"num","remote_km":"num","actions":"arr","sort":"int","open_hour":"num_null","close_hour":"num_null","active":"bool"}}'
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
    when 'npc_roster' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","role":"text","motion":"text","avatar":"obj","lines":"text","pidgin":"text","scenes":"arr",
              "location_ids":"arr","zone_key":"text_null","headliner":"bool","sort":"int","active":"bool"}}'
    when 'crowd_profiles' then '{"pk":["id"],"insert":true,"order":"scene, from_hour, days, id",
      "cols":{"scene":"text","days":"text","from_hour":"int","to_hour":"int","npcs":"int","sort":"int","active":"bool"}}'
  end::jsonb;
$function$;
revoke execute on function public.bl_admin_table_spec(text) from public, anon, authenticated;
