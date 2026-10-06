-- P1 polish batch (docs/SHIP_TODAY.md "P1"): data + one re-created function (bl_travel_quote).
-- * People in every place: more npc_roster people for the thin place types, and a small all-day crowd
--   (staff on duty) where the base crowd profile was 0 or 1. Seeded once (places.p1_people_seeded), so an admin
--   who sets a profile back to 0 later is never overwritten.
-- * Luxury cars at every car dealer: Mercedes-AMG G 63 (G-Wagon), Mercedes-AMG GLE 63 Coupe, Lamborghini Urus,
--   Tesla Cybertruck as vehicle items sold only at the three dealers, on the showroom floor (new prop
--   'lux_cars': spotlit pads, the 3D models are in src/art/place3d/engine/cars.ts). The Tokunbo Lot gets a
--   "Luxury corner". Same purchase flow as L2 (shop_buy, one of each, bank first); any car unlocks "Your car".
-- * More vehicles (lead request): Cadillac Escalade, Mercedes-Benz C300, new Toyota Camry (dealer cars), a Bajaj
--   Boxer motorcycle and a bicycle. A bike/motorcycle unlocks own-vehicle travel with its own speed + cost.
-- * action.queue_max default 5 -> 7 (only when still 5), crowd.rigs_high 4 -> 6 (only when still 4).
-- Idempotent and safe on a non-empty DB: inserts use `on conflict do nothing`, one-time updates are guarded.

-- ---------------------------------------------------------------------
-- 1. Config
-- ---------------------------------------------------------------------
update public.game_config set value = '7'::jsonb
 where key = 'action.queue_max' and value = '5'::jsonb;
update public.game_config set value = '6'::jsonb
 where key = 'crowd.rigs_high' and value = '4'::jsonb;

insert into public.game_config (key, value, category, label, description, kind) values
('places.p1_people_seeded', 'false', 'places', 'P1 people + luxury cars seeded',
 'Set once by the P1 migration (staff on duty in quiet places, Tokunbo Lot luxury corner). Leave it alone.', 'bool')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. Luxury cars (vehicle items, dealers only)
-- ---------------------------------------------------------------------
insert into public.items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort) values
('gwagon_g63', 'Mercedes-AMG G 63 (G-Wagon)', 'vehicle', 350000000,
 'Boxy, loud and unmistakable. The spare wheel on the back says you have arrived.',
 '{}', '{ighodalo_cars,sdd_motors,tokunbo_lot}', true, 70, '🚙', 310),
('gle63_coupe', 'Mercedes-AMG GLE 63 Coupe', 'vehicle', 180000000,
 'The AMG grille with the vertical slats, a coupe roofline and a growl at every gate.',
 '{}', '{ighodalo_cars,sdd_motors,tokunbo_lot}', true, 70, '🚘', 311),
('lambo_urus', 'Lamborghini Urus', 'vehicle', 450000000,
 'Low, wide and angry-looking. Hexagons everywhere. GRA will hear you before they see you.',
 '{}', '{ighodalo_cars,sdd_motors,tokunbo_lot}', true, 65, '🏎️', 312),
('tesla_cybertruck', 'Tesla Cybertruck', 'vehicle', 250000000,
 'Flat stainless steel, one light bar, zero fuel queues. People will stop and film.',
 '{}', '{ighodalo_cars,sdd_motors,tokunbo_lot}', true, 60, '🛻', 313),
('escalade', 'Cadillac Escalade', 'vehicle', 250000000,
 'Big, black and square-shouldered. The convoy car of every politician in Edo.',
 '{}', '{ighodalo_cars,sdd_motors,tokunbo_lot}', true, 65, '🚙', 314),
('benz_c300', 'Mercedes-Benz C300 (brand new)', 'vehicle', 95000000,
 'The classy saloon. Ambient lights inside, the star on the bonnet outside.',
 '{}', '{ighodalo_cars,sdd_motors,tokunbo_lot}', true, 65, '🚘', 315),
('camry_new', 'Toyota Camry (brand new)', 'vehicle', 75000000,
 'Not the 2008 "Muscle": this one is new, with the warranty and the new-car smell.',
 '{}', '{ighodalo_cars,sdd_motors,tokunbo_lot}', true, 65, '🚗', 316),
('bajaj_boxer', 'Bajaj Boxer motorcycle', 'vehicle', 1600000,
 'The okada everybody knows. Fast through traffic, cheap on fuel. Wear a helmet.',
 '{}', '{ighodalo_cars,sdd_motors,tokunbo_lot}', true, 60, '🏍️', 290),
('bicycle', 'Bicycle', 'vehicle', 180000,
 'A sturdy roadster with a bell. Slow, free, and good for your legs.',
 '{}', '{ighodalo_cars,sdd_motors,tokunbo_lot}', true, 55, '🚲', 289)
on conflict (id) do nothing;

-- the showroom floor shows the four luxury cars (prop lux_cars); widened a little so they fit side by side.
-- Only the seeded geometry is touched (an admin-moved zone keeps its place).
update public.place_zones set prop = 'lux_cars', label = 'Luxury showroom', icon = '✨'
 where id = 'car_dealer.showroom' and prop = 'cars';
update public.place_zones set x = 5.5, w = 9.0, z = 3.6, d = 3.4
 where id = 'car_dealer.showroom' and x = 5.0 and w = 7.0 and z = 3.5 and d = 3.0;
-- the front lot: Escalade, C300, the new Camry, a tokunbo saloon, a Bajaj Boxer and a bicycle (prop car_lot)
update public.place_zones set prop = 'car_lot', label = 'Car lot', icon = '🚗'
 where id = 'car_dealer.lot' and prop = 'cars';
update public.place_zones set x = 5.5, w = 9.0, z = 8.6, d = 3.2
 where id = 'car_dealer.lot' and x = 5.0 and w = 7.0 and z = 8.5 and d = 3.0;
-- the Tokunbo Lot: its own (hidden) showroom becomes a small luxury corner, once
update public.place_zones set prop = 'lux_cars', label = 'Luxury corner', icon = '✨', active = true,
       x = 5.5, w = 9.0, z = 3.6, d = 3.4,
       note = 'Fresh off the ship. The oga keeps these under the shade.'
 where id = 'tokunbo_lot.showroom'
   and not coalesce((select (value)::text = 'true' from public.game_config where key = 'places.p1_people_seeded'), false);

insert into public.zone_actions (id, zone_id, kind, ref, label, sort)
select z || '.' || r, z, 'shop', r, null, s from (values
  ('car_dealer.showroom', 'lambo_urus', -4), ('car_dealer.showroom', 'gwagon_g63', -3),
  ('car_dealer.showroom', 'tesla_cybertruck', -2), ('car_dealer.showroom', 'gle63_coupe', -1),
  ('tokunbo_lot.showroom', 'lambo_urus', 1), ('tokunbo_lot.showroom', 'gwagon_g63', 2),
  ('tokunbo_lot.showroom', 'tesla_cybertruck', 3), ('tokunbo_lot.showroom', 'gle63_coupe', 4),
  ('tokunbo_lot.showroom', 'tokunbo_car', 5),
  ('car_dealer.lot', 'escalade', -5), ('car_dealer.lot', 'benz_c300', -4), ('car_dealer.lot', 'camry_new', -3),
  ('car_dealer.lot', 'bajaj_boxer', 10), ('car_dealer.lot', 'bicycle', 11)
) as v(z, r, s)
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 3. Crowd profiles: staff on duty where the base was empty (seeded once)
-- ---------------------------------------------------------------------
update public.crowd_profiles c set npcs = v.n
  from (values
    ('bank', 2), ('car_dealer', 2), ('cinema', 3), ('farm', 2), ('mall', 3), ('museum', 2), ('salon', 2),
    ('workshop', 2), ('zoo', 2), ('office', 2), ('pos', 2), ('shrine', 2), ('palace', 3), ('police', 4),
    ('cyber', 3), ('hotel', 4), ('airport', 4), ('monument', 3)
  ) as v(scene, n)
 where c.id = v.scene || '.all.0-24' and c.npcs < v.n
   and not coalesce((select (value)::text = 'true' from public.game_config where key = 'places.p1_people_seeded'), false);
-- busier daytime bands where the roster used to be the limit
insert into public.crowd_profiles (id, scene, days, from_hour, to_hour, npcs, sort)
select v.scene || '.' || v.days || '.' || v.f || '-' || v.t, v.scene, v.days, v.f, v.t, v.n, 0
from (values
  ('car_dealer','all',17,21,3), ('police','all',18,24,5), ('shrine','all',19,22,2), ('palace','all',18,21,4),
  ('workshop','all',18,21,3), ('pos','all',21,24,3), ('museum','all',17,19,3), ('salon','all',20,22,3)
) as v(scene, days, f, t, n)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 4. Roster: more people for the thin place types (every active type now has 5+)
-- ---------------------------------------------------------------------
insert into public.npc_roster (id, name, role, motion, avatar, lines, pidgin, scenes, location_ids, zone_key, headliner, sort)
select v.id, v.name, v.role, v.motion,
       jsonb_strip_nulls(jsonb_build_object('v', 2, 'gender', v.g, 'skin', v.skin, 'hair', v.hair, 'preset', v.preset,
                                            'top', case when v.top is null then null else jsonb_build_object('c', v.top) end)),
       v.lines, v.pidgin, v.scenes::text[], v.locs::text[], v.zone, v.head, v.sort
from (values
  -- car dealers
  ('car_sales_amenze','Amenze','Car saleswoman','trade','female','tone4','bone_straight','corporate','#2c3540', E'The Urus? Only two in Benin, and one is here.\nCash or transfer, we accept both.', '', '{car_dealer}', '{}', 'showroom', true, 400),
  ('car_guard_musa','Musa','Security guard','guard','male','tone5','low_cut','police','#3a3f6e', E'Park well, oga.\nNo touching the cars without the sales lady.', '', '{car_dealer}', '{}', 'lot', false, 401),
  ('car_mech_osamede','Osamede','Mechanic','work','male','tone5','low_cut','street','#4a4038', E'This engine is clean, I checked it myself.\nTokunbo no be scrap o.', '', '{car_dealer}', '{}', 'track', false, 402),
  ('car_buyer_iyamu','Chief Iyamu','Big man buyer','idle','male','tone4','bald','senator','#f3f0e8', E'I want the G-Wagon in black. Nothing else.\nMy son will drive the Cybertruck.', '', '{car_dealer}', '{}', 'showroom', false, 403),
  ('car_buyer_aisosa','Aisosa','Customer','phone','female','tone3','braids','glam','#c74b8a', E'Babe, I am at the car dealer. Guess which one.\nThe Urus is yellow like a taxi, I love it.', '', '{car_dealer}', '{}', 'lot', false, 404),
  -- airport
  ('airport_pilot','Captain Ogbebor','Pilot','idle','male','tone4','low_cut','corporate','#1c2a52', E'Lagos in forty minutes, weather permitting.\nFasten your seatbelts.', '', '{airport}', '{}', 'deck', false, 410),
  ('airport_porter','Iro','Porter','work','male','tone5','bald','street','#e07a2e', E'Your bags, madam? I will carry them.\nThe Lagos flight is boarding.', '', '{airport}', '{}', 'deck', false, 411),
  ('airport_security','Officer Ekhator','Security','guard','female','tone4','bun','police','#3a3f6e', E'Boarding pass and ID, please.\nNo liquids in the hand luggage.', '', '{airport}', '{}', 'cafe', false, 412),
  -- bank
  ('bank_teller2','Mr. Agbonlahor','Teller','serve','male','tone4','low_cut','corporate','#13512a', E'Next customer, please.\nYour BVN is not linked yet.', '', '{bank}', '{}', 'counter', false, 420),
  ('bank_cust3','Osaretin','Customer','phone','male','tone5','waves','street','#2f6fb3', E'The ATM swallowed my card again.\nNetwork is slow today.', '', '{bank}', '{}', 'atm', false, 421),
  -- buka
  ('buka_cook_ifueko','Mama Ifueko','Cook','serve','female','tone5','cornrows','market','#a8361a', E'Owo soup is ready!\nWho ordered starch?', '', '{buka}', '{}', 'counter', false, 430),
  ('buka_cust4','Okhuoromi','Customer','sit','male','tone4','low_cut','corporate','#3a3f6e', E'This pepper soup is hitting.\nOne more bottle of water, please.', '', '{buka}', '{}', 'tables', false, 431),
  -- cinema
  ('cinema_kada_cook','Ehiz','Chicken cook','serve','male','tone5','low_cut','street','#d9a441', E'Spicy or regular?\nKada chicken, best in Benin.', '', '{cinema}', '{}', 'chicken', false, 440),
  ('cinema_couple','Osagie & Ivie','Date night','sit','male','tone4','waves','yahoo','#111111', E'Two tickets for the 8 PM, abeg.\nShe chose the movie, I chose the popcorn.', '', '{cinema}', '{}', 'screen', false, 441),
  ('cinema_usher','Imuetinyan','Usher','guard','female','tone3','bun','corporate','#151832', E'Hall 2 is to your left.\nPhones on silent, please.', '', '{cinema}', '{}', 'snacks', false, 442),
  -- cyber cafe
  ('cyber_efe','Efe','Student','sit','female','tone4','braids','student','#2f6fb3', E'I am registering for JAMB.\nThe printer jammed again.', '', '{cyber}', '{}', 'desks', false, 450),
  ('cyber_owen','Owen','Customer','phone','male','tone5','high_top','street','#4a4038', E'How much for one hour?\nThe Wi-Fi is flying today.', '', '{cyber}', '{}', 'snacks', false, 451),
  ('cyber_joy','Joy','Typist','sit','female','tone3','bun','corporate','#c74b8a', E'I type CVs and letters.\nYour passport photo will be ready now.', '', '{cyber}', '{}', 'desks', false, 452),
  -- farm
  ('farm_osaze','Osaze','Farm hand','work','male','tone5','low_cut','street','#7dbb45', E'Yam heaps all morning.\nThe sun is not playing today.', '', '{farm}', '{}', 'rows', false, 460),
  ('farm_iyobosa','Mama Iyobosa','Produce buyer','trade','female','tone5','cornrows','market','#d9a441', E'I buy plantain by the bunch.\nHow much for the pepper?', '', '{farm}', '{}', 'shed', false, 461),
  ('farm_ekhator_boy','Ekhator','Farmer''s son','work','male','tone4','low_cut','student','#2f6fb3', E'After farm, school.\nPapa says the land is our bank.', '', '{farm}', '{}', 'rows', false, 462),
  -- hospital
  ('hospital_pa','Pa Igbinovia','Patient','sit','male','tone5','bald','senator','#f3f0e8', E'My BP is better now.\nThe queue is long today.', '', '{hospital}', '{}', 'reception', false, 470),
  ('nurse_imade','Nurse Imade','Nurse','serve','female','tone4','bun','nurse','#f3f0e8', E'Take this twice a day after food.\nThe doctor will see you now.', '', '{hospital}', '{}', 'ward', false, 471),
  -- hotel
  ('hotel_porter','Sunday','Porter','work','male','tone5','low_cut','corporate','#1d5874', E'Welcome to the hotel, sir.\nLet me take your bag to the room.', '', '{hotel}', '{}', 'reception', false, 480),
  ('hotel_lifeguard','Osayi','Lifeguard','guard','male','tone4','low_cut','street','#d2342a', E'No running by the pool.\nThe deep end is that side.', '', '{hotel}', '{}', 'pool', false, 481),
  ('hotel_bartender','Eghosa','Bartender','serve','male','tone5','waves','corporate','#111111', E'Chapman or Zobo?\nThe lounge is quiet tonight.', '', '{hotel}', '{}', 'lounge', false, 482),
  -- mall
  ('mall_guard','Ikponmwonsa','Mall security','guard','male','tone5','bald','police','#3a3f6e', E'Bags at the counter, please.\nThe cinema is upstairs.', '', '{mall}', '{}', 'walk', false, 490),
  ('mall_teen','Osas','Teenager','phone','male','tone4','high_top','street','#e07a2e', E'We are just waiting for the movie.\nShoprite meat pie is the best.', '', '{mall}', '{}', 'food', false, 491),
  -- monument
  ('emotan_story','Pa Omoregbe','Storyteller','sit','male','tone5','bald','bini','#f3f0e8', E'Let me tell you how Emotan helped Oba Ewuare.\nThis spot is sacred to Benin people.', '', '{monument}', '{}', 'bench', false, 500),
  ('emotan_photo','Itohan','Photographer','idle','female','tone4','braids','ankara','#0b625a', E'One photo, five hundred naira.\nSmile, look at the statue!', '', '{monument}', '{}', 'statue', false, 501),
  ('emotan_student','Nosa','Student','phone','male','tone4','low_cut','student','#2f6fb3', E'Our teacher sent us here for history.\nThe statue is taller than I thought.', '', '{monument}', '{}', 'statue', false, 502),
  -- museum
  ('museum_guard','Officer Uwagboe','Museum guard','guard','male','tone5','low_cut','police','#3a3f6e', E'No flash photography, please.\nThe gallery closes at five.', '', '{museum}', '{}', 'gallery', false, 510),
  ('museum_shop','Omonigho','Gift shop attendant','serve','female','tone4','bun','corporate','#74461c', E'We have small bronze copies.\nPostcards are two hundred.', '', '{museum}', '{}', 'shop', false, 511),
  ('museum_ivie','Ivie','Visitor','idle','female','tone3','twists','ankara','#d9a441', E'Look at the detail on this head.\nMy grandfather told me about these.', '', '{museum}', '{}', 'heads', false, 512),
  -- tech hub
  ('dev_eseosa','Eseosa','Product manager','phone','female','tone4','bone_straight','corporate','#155a78', E'Standup in five minutes!\nWho pushed to main?', '', '{office}', '{}', 'desks', false, 520),
  ('dev_osaro_intern','Osaro','Intern','idle','male','tone4','low_cut','student','#2f6fb3', E'I just finished my first pull request.\nThe coffee here is free, right?', '', '{office}', '{}', 'coffee', false, 521),
  -- palace
  ('palace_drummer','Ogbeide','Palace drummer','work','male','tone5','bald','bini','#f3f0e8', E'The drums speak for the Oba.\nListen to the rhythm.', '', '{palace}', '{}', 'courtyard', false, 530),
  ('palace_guard2','Edigin','Palace guard','guard','male','tone4','bald','bini','#d2342a', E'Bow your head at the gate.\nPhotos only from outside.', '', '{palace}', '{}', 'gate', false, 531),
  ('palace_elder','Chief Ogiamien','Elder','idle','male','tone5','bald','agbada','#f3f0e8', E'Our customs are older than the city walls.\nGreet the elders first.', '', '{palace}', '{}', 'bronzes', false, 532),
  -- police
  ('police_aigbe','Inspector Aigbe','Inspector','idle','male','tone5','low_cut','police','#1a285c', E'Write your statement here.\nWe will look into it.', '', '{police}', '{}', 'desk', false, 540),
  ('police_ehis','Constable Ehis','Constable','guard','male','tone4','low_cut','police','#1a285c', E'Wait outside until you are called.\nNo phones at the counter.', '', '{police}', '{}', 'board', false, 541),
  ('police_odion','Mr. Odion','Complainant','phone','male','tone4','waves','corporate','#3a3f6e', E'They stole my phone at the park.\nI have been here since morning.', '', '{police}', '{}', 'bench', false, 542),
  -- PoS
  ('pos_mama_ese','Mama Ese','Recharge card seller','trade','female','tone5','cornrows','market','#e07a2e', E'MTN, Glo, Airtel, 9mobile!\nTransfer or cash, I have change.', E'Recharge card dey, all network!\nMy pikin, buy from me.', '{pos}', '{}', 'airtime', false, 550),
  ('pos_kelvin','Kelvin','Customer','phone','male','tone4','high_top','street','#2a2d3a', E'The transfer has not dropped.\nPlease check again.', E'Abeg check am again, e never drop.\nNetwork wahala!', '{pos}', '{}', 'line', false, 551),
  -- salon
  ('barber_kelly','Barber Kelly','Barber','serve','male','tone5','waves','street','#a02c68', E'Low cut or fade?\nSit down, you are next.', '', '{salon}', '{}', 'chairs', false, 560),
  ('salon_ivie','Ivie','Hairdresser','serve','female','tone3','bone_straight','glam','#c74b8a', E'Braids take three hours, sit well.\nThis attachment is the best quality.', '', '{salon}', '{}', 'shelf', false, 561),
  ('salon_cust3','Ehis','Customer','sit','male','tone4','low_cut','yahoo','#111111', E'Make it sharp, I have a date.\nHow much now?', '', '{salon}', '{}', 'bench', false, 562),
  -- shrine
  ('shrine_drummer','Iyoha','Drummer','work','male','tone5','bald','bini','#f3f0e8', E'The drum calls the ancestors.\nStep softly.', '', '{shrine}', '{}', 'courtyard', false, 570),
  ('shrine_mama','Mama Ewere','Devotee','idle','female','tone5','cornrows','bini','#f3f0e8', E'I came to pray for my children.\nPeace be with you.', '', '{shrine}', '{}', 'courtyard', false, 571),
  ('shrine_visitor2','Osaro','Visitor','idle','male','tone4','low_cut','ankara','#b5552b', E'My grandmother brought me here as a boy.\nIt feels calm here.', '', '{shrine}', '{}', 'altar', false, 572),
  ('shrine_kola','Ekhosuehi','Kola seller','trade','female','tone4','cornrows','market','#b5552b', E'Kola nut for the offering.\nWhite chalk, fifty naira.', '', '{shrine}', '{}', 'courtyard', false, 573),
  -- stadium
  ('stadium_coach','Coach Imade','Coach','idle','male','tone4','bald','corporate','#125a38', E'Press higher! Press higher!\nInsurance FC go win today.', '', '{stadium}', '{}', 'pitch', false, 580),
  ('fan_uyi','Uyi','Football fan','cheer','male','tone5','low_cut','street','#125a38', E'Goaaal!\nReferee, are you blind?', '', '{stadium}', '{}', 'popular', false, 581),
  -- street
  ('street_okada','Ikpomwosa','Okada rider','idle','male','tone5','low_cut','keke','#d9a441', E'Where you dey go?\nUselu, two hundred.', E'Oya enter, I go carry you.\nNo shaking, I sabi road.', '{street}', '{}', 'corner', false, 590),
  ('street_ivie_puff','Aunty Ivie','Puff-puff seller','trade','female','tone4','cornrows','market','#d2342a', E'Hot puff-puff and akara!\nBuy two, I dash you one.', E'Puff-puff dey hot!\nCome buy, e sweet well well.', '{street}', '{}', 'suya', false, 591),
  -- Igun Street workshop
  ('igun_ehigie','Ehigie','Bronze caster','work','male','tone4','bald','bini','#f3f0e8', E'We pour the bronze at noon.\nThis plaque took me a month.', '', '{workshop}', '{}', 'furnace', false, 600),
  ('igun_mama_idia','Mama Idia','Bronze seller','trade','female','tone5','cornrows','bini','#d2342a', E'Queen Idia mask, real Igun Street work.\nI will give you a good price.', '', '{workshop}', '{}', 'display', false, 601),
  ('igun_visitor','Mr. Okafor','Collector','idle','male','tone3','low_cut','senator','#f3f0e8', E'I collect Benin bronzes.\nThe new ones are beautiful too.', '', '{workshop}', '{}', 'display', false, 602),
  ('igun_apprentice2','Osas','Apprentice','work','male','tone4','low_cut','street','#4a4038', E'I am learning the lost-wax method.\nMy hands are always black.', '', '{workshop}', '{}', 'furnace', false, 603),
  -- zoo
  ('zoo_kid','Osas','Excited kid','cheer','male','tone4','low_cut','student','#e07a2e', E'Mummy, look at the lion!\nCan we feed the monkeys?', '', '{zoo}', '{}', 'birds', false, 610),
  ('zoo_vendor','Mama Kingsley','Snack seller','trade','female','tone5','cornrows','market','#d9a441', E'Gala and Lacasera, cold!\nBuy groundnut for the monkeys.', '', '{zoo}', '{}', 'kiosk', false, 611),
  ('zoo_keeper2','Ehis','Keeper','work','male','tone5','low_cut','street','#3f6e1c', E'Do not put your hand in the cage.\nThe lion ate at noon.', '', '{zoo}', '{}', 'birds', false, 612),
  ('zoo_dad','Mr. Edokpolo','Visitor','idle','male','tone4','low_cut','ankara','#2f6fb3', E'I came here as a boy too.\nThe lions look tired today.', '', '{zoo}', '{}', 'lions', false, 613)
) as v(id, name, role, motion, g, skin, hair, preset, top, lines, pidgin, scenes, locs, zone, head, sort)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 5. Own-vehicle travel: a bicycle or a motorcycle also unlocks "Your own ..." (mode 'car'). With no car in
--    the Bag, the option uses the bike's own speed and cost: the bicycle is slow and free (no traffic), the
--    Bajaj Boxer is fast and cheap (weaves through traffic). The street robbery risk is the own-vehicle one
--    (crime.mode_mult_car), the same the arrival roll uses. bl_travel_quote re-created from its live (F1)
--    definition; only the 'car' option changed. Grants unchanged (internal helper).
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('travel.bicycle.speed_kmh', '12', 'travel', 'Bicycle speed (km/h)', 'Own bicycle (used when you have no car). No traffic.', 'number', 1, 200),
('travel.bicycle.base_cost', '0', 'travel', 'Bicycle base cost', 'Own bicycle: fixed cost per trip.', 'naira', 0, 100000),
('travel.bicycle.per_km', '0', 'travel', 'Bicycle cost per km', 'Own bicycle: cost per km.', 'naira', 0, 100000),
('travel.motorcycle.speed_kmh', '35', 'travel', 'Motorcycle speed (km/h)', 'Own motorcycle (used when you have no car). Traffic hurts it less.', 'number', 1, 200),
('travel.motorcycle.base_cost', '0', 'travel', 'Motorcycle base cost', 'Own motorcycle: fixed cost per trip.', 'naira', 0, 100000),
('travel.motorcycle.per_km', '40', 'travel', 'Motorcycle fuel per km', 'Own motorcycle: fuel cost per km.', 'naira', 0, 100000)
on conflict (key) do nothing;

CREATE OR REPLACE FUNCTION public.bl_travel_quote(p_me profiles, p_dest text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  dst      locations := bl_location(p_dest);
  src      locations := bl_location(p_me.location_id);
  v_km     numeric;
  v_now    timestamptz := bl_now();
  v_traffic_road numeric;
  v_has_car boolean;
  v_ride   text;   -- P1: 'car' (any car), 'motorcycle', 'bicycle', or null (no vehicle)
  v_key    text;
  v_opts   jsonb := '[]'::jsonb;
  m        text;
  v_label  text;
  v_speed  numeric; v_cost bigint; v_traffic numeric; v_gm int; v_rs numeric;
  v_allowed boolean; v_reason text;
  v_risk   numeric;
  v_short  boolean := bl_action_short();
  v_minrs  numeric := bl_cfg('travel.min_real_seconds');
begin
  -- F1 soft launch: a hidden place can't be travelled to (your own home always can)
  if not coalesce(dst.active, true) and dst.id is distinct from p_me.home_location_id then
    raise exception '% is closed for now. Check back soon.', dst.name using errcode = 'P0001', hint = 'inactive';
  end if;
  if dst.id = src.id then
    raise exception 'You are already at %.', dst.name using errcode = 'P0001';
  end if;
  v_km := bl_distance_km(src.id, dst.id);
  v_traffic_road := bl_traffic(src.id, dst.id, v_now);
  select case when bool_or(i.item_id not in ('bicycle', 'bajaj_boxer')) then 'car'
              when bool_or(i.item_id = 'bajaj_boxer') then 'motorcycle'
              when bool_or(i.item_id = 'bicycle') then 'bicycle' end
    into v_ride
    from inventory i join items it on it.id = i.item_id
   where i.user_id = p_me.id and i.qty > 0 and it.category = 'vehicle';
  v_has_car := v_ride is not null;

  foreach m in array array['walk','keke','bus','drop','car'] loop
    v_label := case m when 'walk' then 'Walk'
                      when 'keke' then 'Keke Napep'
                      when 'bus'  then 'ECTS Green Bus'
                      when 'drop' then 'Drop (ride-hail)'
                      else case v_ride when 'motorcycle' then 'Your motorcycle'
                                       when 'bicycle' then 'Your bicycle'
                                       else 'Your own car' end end;
    v_key := case when m = 'car' and v_ride in ('motorcycle', 'bicycle') then v_ride else m end;
    v_speed := greatest(bl_cfg('travel.' || v_key || '.speed_kmh'), 0.1);
    v_cost  := (ceil((bl_cfg('travel.' || v_key || '.base_cost') + bl_cfg('travel.' || v_key || '.per_km') * v_km) / 10.0) * 10)::bigint;
    v_traffic := case when m = 'walk' or v_key = 'bicycle' then 1
                      when v_key = 'motorcycle' then 1 + (v_traffic_road - 1) * 0.35
                      else v_traffic_road end;
    v_gm := greatest(1, ceil(v_km / v_speed * 60 * v_traffic))::int;
    v_rs := greatest(v_minrs, v_gm * bl_cfg('travel.real_seconds_per_game_minute'));
    if v_short then
      v_rs := least(v_rs, greatest(bl_cfg('action.travel_max_seconds'), v_minrs));
    end if;
    v_rs := round(v_rs, 1);
    v_allowed := true; v_reason := null;
    if m = 'keke' and not (src.keke_ok and dst.keke_ok) then
      v_allowed := false;
      v_reason := 'Keke can''t go there. Keke is banned on the major roads.';
    elsif m = 'car' and not v_has_car then
      v_allowed := false;
      v_reason := 'You don''t have a car yet. Buy one first.';
    elsif v_cost > p_me.cash then
      v_allowed := false;
      v_reason := 'Your money no reach for this one (' || bl_naira(v_cost) || ').';
    end if;
    v_risk := round(100 * bl_street_robbery_chance(p_me.id, dst.id, m, v_traffic,
                                                   v_now + make_interval(secs => v_rs::double precision)), 1);
    v_opts := v_opts || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'mode', m, 'label', v_label, 'allowed', v_allowed, 'reason', v_reason,
      'cost', v_cost, 'game_minutes', v_gm, 'real_seconds', v_rs, 'risk_pct', v_risk,
      'vehicle', case when m = 'car' then v_ride end)));
  end loop;

  return jsonb_build_object('dest', dst.id, 'km', v_km, 'traffic', v_traffic_road, 'options', v_opts);
end $function$;

-- ---------------------------------------------------------------------
-- 6. Done once
-- ---------------------------------------------------------------------
update public.game_config set value = 'true'::jsonb
 where key = 'places.p1_people_seeded' and value <> 'true'::jsonb;
