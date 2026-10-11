-- B1 Buy mode + arrange (docs/FURNITURE_CATALOGUE.md). Idempotent and safe on a non-empty DB.
--   1. furniture gets catalogue columns (price, tier lapo/mid/nepo, category, footprint w/d, solid,
--      placement in/out/any/wall, max_qty, bonus = extra need effects per home activity, buyable) and
--      ~100 rows of real Nigerian home furniture and appliances (upserted by id; the 13 starter pieces
--      keep their ids and get prices).
--   2. player_furniture.qty (several plastic chairs, fans ...); copy n has the placement key own_<id>
--      (n = 1) or own_<id>-<n>. player_house_furniture.stored (= in the inventory) and .layout (the home
--      layout the position belongs to; rows from a previous home are reset when you move).
--   3. home_layouts: the client layouts' size, yard (lot), fixtures/partitions/door zones and default slots
--      (generated from src/art/home3d/model.ts + arrange.ts), so the server checks placement itself.
--   4. RPCs: furniture_buy(id) (cash first, then bank; goes to the inventory), furniture_place(key, x, z, rot)
--      (validated: area rule, no overlap with fixtures/walls/door zones/your other solid pieces, quarter
--      turns), furniture_store(key). social_home_place_furniture now uses the same validation.
--   5. Placed furniture only: bl_furniture_for ignores stored pieces and returns the best bonus per need;
--      do_activity adds it (bed rest_pct as before, AC/fan -> sleep energy, fridge/cooker -> cook hunger ...).
--   6. Admin Content -> Furniture shows the new columns; the ledger says "Furniture: <name>".

-- ---------------------------------------------------------------- 1. catalogue columns
alter table public.furniture add column if not exists price bigint not null default 0;
alter table public.furniture add column if not exists tier text not null default 'mid';
alter table public.furniture add column if not exists category text not null default 'living';
alter table public.furniture add column if not exists w numeric(5,2) not null default 1;
alter table public.furniture add column if not exists d numeric(5,2) not null default 1;
alter table public.furniture add column if not exists solid boolean not null default true;
alter table public.furniture add column if not exists placement text not null default 'in';
alter table public.furniture add column if not exists max_qty integer not null default 1;
alter table public.furniture add column if not exists bonus jsonb not null default '{}'::jsonb;
alter table public.furniture add column if not exists buyable boolean not null default true;
alter table public.furniture drop constraint if exists furniture_price_check;
alter table public.furniture add constraint furniture_price_check check (price >= 0);
alter table public.furniture drop constraint if exists furniture_tier_check;
alter table public.furniture add constraint furniture_tier_check check (tier in ('lapo', 'mid', 'nepo'));
alter table public.furniture drop constraint if exists furniture_category_check;
alter table public.furniture add constraint furniture_category_check
  check (category in ('living', 'bedroom', 'kitchen', 'bathroom', 'utility', 'decor'));
alter table public.furniture drop constraint if exists furniture_placement_check;
alter table public.furniture add constraint furniture_placement_check check (placement in ('in', 'out', 'any', 'wall'));
alter table public.furniture drop constraint if exists furniture_size_check;
alter table public.furniture add constraint furniture_size_check check (w > 0 and d > 0 and w <= 10 and d <= 10);
alter table public.furniture drop constraint if exists furniture_max_qty_check;
alter table public.furniture add constraint furniture_max_qty_check check (max_qty between 1 and 20);
alter table public.furniture drop constraint if exists furniture_bonus_check;
alter table public.furniture add constraint furniture_bonus_check check (jsonb_typeof(bonus) = 'object');

alter table public.player_furniture add column if not exists qty integer not null default 1;
alter table public.player_furniture drop constraint if exists player_furniture_qty_check;
alter table public.player_furniture add constraint player_furniture_qty_check check (qty between 1 and 20);

alter table public.player_house_furniture add column if not exists stored boolean not null default false;
alter table public.player_house_furniture add column if not exists layout text;

insert into public.furniture
  (id, name, emoji, kind, slot, activities, rest_pct, color, description, sort,
   price, tier, category, w, d, solid, placement, max_qty, bonus)
values
  ('plastic_chair_white', 'Plastic chair (white)', '🪑', 'plastic_chair', 'seat', array['sit_rest'], 100, '#e8e4dc', 'The chair wey dey every party. Stack am, carry am, sit down.', 10, 6500, 'lapo', 'living', 0.5, 0.5, true, 'any', 6, '{}'::jsonb),
  ('plastic_chair_red', 'Plastic chair (red)', '🪑', 'plastic_chair', 'seat', array['sit_rest'], 100, '#c0392b', 'Owambe red. E no dey break easy.', 20, 6500, 'lapo', 'living', 0.5, 0.5, true, 'any', 6, '{}'::jsonb),
  ('plastic_table', 'Plastic table', '🟦', 'plastic_table', 'none', '{}'::text[], 100, '#2e86c1', 'For eba, for Ludo, for everything.', 30, 18000, 'lapo', 'living', 0.8, 0.8, true, 'any', 2, '{}'::jsonb),
  ('stool', 'Small stool', '🪵', 'stool', 'seat', array['sit_rest'], 100, null, 'Carved wood stool. Small but mighty.', 40, 4000, 'lapo', 'living', 0.4, 0.4, true, 'any', 4, '{}'::jsonb),
  ('bench_wood', 'Wooden bench', '🪵', 'bench', 'seat', array['sit_rest'], 100, null, 'Carpenter-made bench from Uselu.', 50, 25000, 'lapo', 'living', 1.4, 0.4, true, 'any', 2, '{}'::jsonb),
  ('sofa', 'Sofa', '🛋️', 'sofa', 'sofa', array['relax_sofa'], 100, null, 'Correct 3-seater for your parlour.', 60, 250000, 'mid', 'living', 1.9, 0.85, true, 'in', 1, '{}'::jsonb),
  ('sofa_loveseat', '2-seater loveseat', '🛋️', 'sofa_2', 'sofa', array['relax_sofa','sit_rest'], 100, '#2f6f8f', 'Small sofa for small parlour.', 70, 180000, 'mid', 'living', 1.4, 0.85, true, 'in', 2, '{}'::jsonb),
  ('armchair_single', 'Single armchair', '💺', 'armchair', 'seat', array['sit_rest','relax_sofa'], 100, '#7a1f2b', 'Oga chair. Only for the head of the house.', 80, 120000, 'mid', 'living', 0.85, 0.85, true, 'in', 4, '{}'::jsonb),
  ('sofa_l_fabric', 'L-shaped 7-seater sofa', '🛋️', 'sofa_l', 'sofa', array['relax_sofa','sit_rest'], 100, '#5d6d7e', 'The whole family fit sit down for Christmas.', 90, 950000, 'mid', 'living', 2.8, 0.9, true, 'in', 1, '{"relax_sofa":{"stress":-2}}'::jsonb),
  ('sofa_italian', 'Italian leather sofa set', '🛋️', 'sofa_lux', 'sofa', array['relax_sofa','sit_rest'], 100, '#f1e9da', 'Imported from Milan via Apapa. Nobody sits here with Agege bread.', 100, 6500000, 'nepo', 'living', 2.4, 0.95, true, 'in', 1, '{"relax_sofa":{"fun":4,"stress":-4}}'::jsonb),
  ('recliner', 'Leather recliner', '💺', 'recliner', 'seat', array['sit_rest','relax_sofa'], 100, '#3b2a20', 'Lean back, leg up, owner of the house.', 110, 850000, 'nepo', 'living', 0.95, 0.95, true, 'in', 2, '{"relax_sofa":{"stress":-3}}'::jsonb),
  ('centre_table', 'Centre table', '🪵', 'centre_table', 'ctable', '{}'::text[], 100, null, 'Wooden centre table with a vase.', 120, 65000, 'mid', 'living', 1, 0.55, true, 'in', 1, '{}'::jsonb),
  ('centre_glass', 'Glass centre table', '🔷', 'centre_glass', 'ctable', '{}'::text[], 100, null, 'Tempered glass and gold legs.', 130, 350000, 'nepo', 'living', 1.2, 0.65, true, 'in', 1, '{}'::jsonb),
  ('tv_small', 'Small 24" TV', '📺', 'tv_small', 'tv', array['watch_tv'], 100, null, 'Small screen, big Nollywood.', 140, 95000, 'lapo', 'living', 0.8, 0.4, true, 'in', 1, '{}'::jsonb),
  ('tv', 'Flat-screen TV (32")', '📺', 'tv', 'tv', array['watch_tv'], 100, null, '32" Hisense LED on a TV stand.', 150, 185000, 'mid', 'living', 1.2, 0.45, true, 'in', 1, '{}'::jsonb),
  ('tv_43', '43" smart TV (Hisense)', '📺', 'tv_43', 'tv', array['watch_tv'], 100, null, 'Smart TV: YouTube, Netflix, Showmax.', 160, 330000, 'mid', 'living', 1.3, 0.45, true, 'in', 1, '{"watch_tv":{"fun":2}}'::jsonb),
  ('tv_55', '55" 4K smart TV (LG)', '📺', 'tv_55', 'tv', array['watch_tv'], 100, null, '4K. You go see sweat for Nollywood actors face.', 170, 650000, 'mid', 'living', 1.5, 0.45, true, 'in', 1, '{"watch_tv":{"fun":3}}'::jsonb),
  ('tv_65', '65" QLED TV (Samsung)', '📺', 'tv_big', 'tv', array['watch_tv'], 100, null, 'QLED for the big parlour.', 180, 1100000, 'nepo', 'living', 1.8, 0.45, true, 'in', 1, '{"watch_tv":{"fun":5,"stress":-2}}'::jsonb),
  ('tv_75', '75" QLED TV (Hisense)', '📺', 'tv_75', 'tv', array['watch_tv'], 100, null, 'Na cinema be this. Neighbours go come watch match.', 190, 1250000, 'nepo', 'living', 2.2, 0.5, true, 'in', 1, '{"watch_tv":{"fun":8,"stress":-3}}'::jsonb),
  ('radio', 'Rechargeable radio', '📻', 'radio', 'none', array['listen_radio'], 100, null, 'For news, football and Benin highlife.', 200, 12000, 'lapo', 'living', 0.45, 0.4, true, 'any', 1, '{}'::jsonb),
  ('speaker_bt', 'Bluetooth speaker', '🔊', 'speaker_small', 'none', array['listen_radio'], 100, null, 'Small speaker, loud mouth.', 210, 25000, 'lapo', 'living', 0.3, 0.3, true, 'in', 2, '{}'::jsonb),
  ('home_theatre', 'Home theatre system (LG)', '🔊', 'home_theatre', 'none', array['listen_radio'], 100, null, 'Soundbar plus woofer. Bass go shake the louvres.', 220, 280000, 'mid', 'living', 1.6, 0.45, true, 'in', 1, '{"watch_tv":{"fun":3},"listen_radio":{"fun":4}}'::jsonb),
  ('speaker_tower', 'Tower speaker (JBL)', '🔊', 'speaker_tower', 'none', array['listen_radio'], 100, null, 'Buy two. Stereo for your owambe.', 230, 450000, 'nepo', 'living', 0.35, 0.35, true, 'in', 4, '{"listen_radio":{"fun":6},"watch_tv":{"fun":2}}'::jsonb),
  ('rug', 'Rug', '🟥', 'rug', 'rug', '{}'::text[], 100, null, 'Patterned rug for the parlour.', 240, 45000, 'mid', 'living', 2, 1.4, false, 'in', 2, '{}'::jsonb),
  ('mat_raffia', 'Raffia mat', '🟫', 'mat_raffia', 'rug', '{}'::text[], 100, null, 'Woven mat. Cool for the floor when NEPA take light.', 250, 8000, 'lapo', 'living', 1.6, 1, false, 'in', 2, '{}'::jsonb),
  ('rug_shaggy', 'Big shaggy rug', '⬜', 'rug_big', 'rug', '{}'::text[], 100, '#efe6d6', 'Soft like cotton wool. Remove your shoe.', 260, 220000, 'nepo', 'living', 2.6, 1.8, false, 'in', 2, '{"relax_sofa":{"fun":1}}'::jsonb),
  ('curtain_ankara', 'Ankara curtains', '🪟', 'curtain', 'none', '{}'::text[], 100, '#d35400', 'Made by the tailor down the road.', 270, 15000, 'lapo', 'living', 1.4, 0.15, false, 'wall', 4, '{}'::jsonb),
  ('curtain_lux', 'Blackout curtains', '🪟', 'curtain_lux', 'none', '{}'::text[], 100, '#5b2c6f', 'Sun no fit wake you. Sleep like Oga.', 280, 180000, 'nepo', 'living', 1.8, 0.18, false, 'wall', 4, '{"sleep":{"energy":3}}'::jsonb),
  ('fan_standing', 'Standing fan (Binatone)', '🌀', 'fan', 'none', '{}'::text[], 100, null, 'Binatone 16". Rotate am make everybody enjoy.', 290, 38000, 'lapo', 'living', 0.45, 0.45, true, 'in', 3, '{"sleep":{"energy":2},"nap":{"energy":1}}'::jsonb),
  ('fan_rechargeable', 'Rechargeable fan', '🌀', 'fan_table', 'none', '{}'::text[], 100, null, 'When NEPA take light, this one no go fail you (for 5 hours).', 300, 45000, 'lapo', 'living', 0.35, 0.3, true, 'any', 3, '{"sleep":{"energy":2}}'::jsonb),
  ('fan_ceiling', 'Ceiling fan (Ox)', '🌀', 'fan_ceiling', 'none', '{}'::text[], 100, null, 'Ox ceiling fan, 56".', 310, 55000, 'mid', 'living', 1.2, 1.2, false, 'in', 3, '{"sleep":{"energy":3},"nap":{"energy":1}}'::jsonb),
  ('ac_split', '1.5HP split AC (Hisense)', '❄️', 'ac', 'none', '{}'::text[], 100, null, 'Inverter split unit. Cold like Jos.', 320, 430000, 'mid', 'living', 0.9, 0.25, false, 'wall', 4, '{"sleep":{"energy":8,"stress":-4},"nap":{"energy":4}}'::jsonb),
  ('ac_inverter', '2HP inverter AC (LG)', '❄️', 'ac_big', 'none', '{}'::text[], 100, null, 'Dual inverter, low noise, big room.', 330, 850000, 'nepo', 'living', 1.1, 0.28, false, 'wall', 4, '{"sleep":{"energy":12,"stress":-6},"nap":{"energy":5}}'::jsonb),
  ('ac_standing', 'Standing AC (Midea 3HP)', '❄️', 'ac_standing', 'none', '{}'::text[], 100, null, 'Floor-standing AC for the big parlour.', 340, 1350000, 'nepo', 'living', 0.5, 0.4, true, 'in', 2, '{"sleep":{"energy":10,"stress":-5}}'::jsonb),
  ('shelf_wood', 'Wooden shelf', '🗄️', 'shelf', 'none', '{}'::text[], 100, null, 'Open shelf for your things.', 350, 55000, 'mid', 'living', 0.9, 0.35, true, 'in', 2, '{}'::jsonb),
  ('bookshelf', 'Bookshelf with books', '📚', 'bookshelf', 'none', '{}'::text[], 100, null, 'Achebe, Soyinka and old WAEC past questions.', 360, 95000, 'mid', 'living', 1, 0.38, true, 'in', 2, '{"sit_rest":{"stress":-1}}'::jsonb),
  ('foam_mat', 'Thin foam mattress', '🛏️', 'mattress', 'bed', array['sleep','nap'], 90, null, 'Thin foam on the floor. Your back go complain small.', 370, 25000, 'lapo', 'bedroom', 1.3, 1.9, true, 'in', 1, '{}'::jsonb),
  ('foam_mouka_floor', 'Mouka 6" foam (on the floor)', '🛏️', 'mattress_thick', 'bed', array['sleep','nap'], 95, '#2e7d6b', 'Mouka foam, no frame yet. Better than mat.', 380, 85000, 'lapo', 'bedroom', 1.4, 1.95, true, 'in', 1, '{}'::jsonb),
  ('bunk_metal', 'Metal bunk bed', '🛏️', 'bunk', 'bed', array['sleep','nap'], 95, null, 'Hostel style. Upstairs or downstairs.', 390, 120000, 'lapo', 'bedroom', 1, 2, true, 'in', 1, '{}'::jsonb),
  ('bed_single', 'Proper single bed', '🛏️', 'bed_single', 'bed', array['sleep','nap'], 100, null, 'Single wooden bed with Vitafoam mattress.', 400, 150000, 'mid', 'bedroom', 1, 2, true, 'in', 1, '{}'::jsonb),
  ('bed_double', 'Proper bed', '🛏️', 'bed_double', 'bed', array['sleep','nap'], 100, null, '4.5ft bed frame with Vitafoam mattress.', 410, 260000, 'mid', 'bedroom', 1.5, 2, true, 'in', 1, '{}'::jsonb),
  ('bed_vitafoam_6', '6x6 bed + Vitafoam orthopaedic', '🛏️', 'bed_6', 'bed', array['sleep','nap'], 115, '#1f618d', '6x6, 8" Vitafoam orthopaedic. Back pain bye-bye.', 420, 450000, 'mid', 'bedroom', 1.8, 2.05, true, 'in', 1, '{}'::jsonb),
  ('bed_king_mouka', 'King bed + Mouka Royal mattress', '🛏️', 'bed_king', 'bed', array['sleep','nap'], 130, null, 'Mouka Royal spring mattress on a carved king frame.', 430, 1200000, 'nepo', 'bedroom', 1.9, 2.1, true, 'in', 1, '{"sleep":{"stress":-3}}'::jsonb),
  ('bed_lux', 'Upholstered king bed', '🛏️', 'bed_lux', 'bed', array['sleep','nap'], 140, '#c9b79c', 'Tufted velvet headboard, pocket-spring mattress. Sleep like royalty.', 440, 3500000, 'nepo', 'bedroom', 2.1, 2.25, true, 'in', 1, '{"sleep":{"stress":-5}}'::jsonb),
  ('clothes_rack', 'Hanger rack', '👕', 'clothes_rack', 'wardrobe', '{}'::text[], 100, null, 'Metal rail. Your clothes no go rumple for bag again.', 450, 18000, 'lapo', 'bedroom', 1, 0.45, true, 'in', 1, '{}'::jsonb),
  ('locker_metal', 'Metal locker', '🗄️', 'locker', 'wardrobe', '{}'::text[], 100, null, 'Lock your things. Roommate no go touch.', 460, 55000, 'lapo', 'bedroom', 0.6, 0.5, true, 'in', 2, '{}'::jsonb),
  ('wardrobe', 'Wardrobe', '🚪', 'wardrobe', 'wardrobe', '{}'::text[], 100, null, '2-door wardrobe with a mirror strip.', 470, 180000, 'mid', 'bedroom', 1.2, 0.6, true, 'in', 1, '{}'::jsonb),
  ('wardrobe_big', '3-door wardrobe', '🚪', 'wardrobe_big', 'wardrobe', '{}'::text[], 100, null, 'Wardrobe wey fit your aso-ebi collection.', 480, 650000, 'nepo', 'bedroom', 1.9, 0.62, true, 'in', 1, '{}'::jsonb),
  ('dressing_mirror', 'Dressing table + mirror', '🪞', 'dressing', 'none', '{}'::text[], 100, null, 'Make-up, perfume, small comb.', 490, 150000, 'mid', 'bedroom', 1, 0.45, true, 'in', 1, '{"bathe":{"stress":-1}}'::jsonb),
  ('mirror_standing', 'Standing mirror', '🪞', 'mirror_stand', 'none', '{}'::text[], 100, null, 'Check your outfit before you step out.', 500, 22000, 'lapo', 'bedroom', 0.5, 0.35, true, 'in', 2, '{}'::jsonb),
  ('bedside', 'Bedside table', '🗄️', 'bedside', 'none', '{}'::text[], 100, null, 'For phone, Bible or Quran, and water.', 510, 45000, 'mid', 'bedroom', 0.45, 0.4, true, 'in', 2, '{}'::jsonb),
  ('lamp_bedside', 'Bedside lamp', '💡', 'lamp_small', 'none', '{}'::text[], 100, null, 'Soft light for night reading.', 520, 18000, 'mid', 'bedroom', 0.3, 0.3, true, 'in', 4, '{}'::jsonb),
  ('lamp_floor', 'Floor lamp', '💡', 'lamp', 'none', '{}'::text[], 100, null, 'Standing lamp, warm light.', 530, 65000, 'mid', 'bedroom', 0.35, 0.35, true, 'in', 4, '{}'::jsonb),
  ('chandelier', 'Crystal chandelier', '✨', 'chandelier', 'none', '{}'::text[], 100, null, 'Sparkle sparkle. Visitors go look ceiling first.', 540, 950000, 'nepo', 'bedroom', 0.9, 0.9, false, 'in', 2, '{"relax_sofa":{"fun":2}}'::jsonb),
  ('desk_study', 'Study desk', '📝', 'desk', 'none', '{}'::text[], 100, null, 'For JAMB, for hustle, for laptop.', 550, 70000, 'mid', 'bedroom', 1, 0.55, true, 'in', 1, '{}'::jsonb),
  ('office_chair', 'Office chair', '💺', 'office_chair', 'seat', array['sit_rest'], 100, null, 'Swivel chair. Spin am small.', 560, 85000, 'mid', 'bedroom', 0.6, 0.6, true, 'in', 2, '{}'::jsonb),
  ('kerosene_stove', 'Kerosene stove', '🔥', 'kerosene_stove', 'stove', array['cook_home'], 100, null, 'Wick stove on a small table. Kerosene don cost o.', 570, 18000, 'lapo', 'kitchen', 0.6, 0.5, true, 'in', 1, '{}'::jsonb),
  ('hotplate', 'Electric hot plate', '♨️', 'hotplate', 'stove', array['cook_home'], 100, null, 'When light dey, you cook.', 580, 22000, 'lapo', 'kitchen', 0.55, 0.45, true, 'in', 1, '{}'::jsonb),
  ('gas_table', 'Table-top gas burner + 3kg gas', '🔥', 'gas_table', 'stove', array['cook_home'], 100, null, 'Two burners and a small cylinder. Cooking don sharp.', 590, 55000, 'lapo', 'kitchen', 0.7, 0.5, true, 'in', 1, '{"cook_home":{"hunger":2}}'::jsonb),
  ('gas_cooker', 'Gas cooker', '🔥', 'gas_cooker', 'stove', array['cook_home'], 100, null, '4-burner cooker with oven, plus the cylinder.', 600, 320000, 'mid', 'kitchen', 0.95, 0.6, true, 'in', 1, '{"cook_home":{"hunger":4}}'::jsonb),
  ('cooker_lux', '5-burner gas cooker (Scanfrost)', '🔥', 'cooker_big', 'stove', array['cook_home'], 100, null, 'Stainless steel, 5 burners, grill. Jollof for 50.', 610, 840000, 'nepo', 'kitchen', 0.95, 0.62, true, 'in', 1, '{"cook_home":{"hunger":6,"fun":3}}'::jsonb),
  ('gas_cyl', '12.5kg gas cylinder', '🟢', 'gas', 'none', '{}'::text[], 100, null, 'Spare cylinder. Gas no go finish mid-stew.', 620, 65000, 'mid', 'kitchen', 0.32, 0.32, true, 'in', 2, '{"cook_home":{"hunger":1}}'::jsonb),
  ('fridge_bar', 'Bar fridge (Nexus 65L)', '🧊', 'fridge_small', 'fridge', array['cold_drink'], 100, null, 'Small fridge for cold water and malt.', 630, 120000, 'mid', 'kitchen', 0.5, 0.5, true, 'in', 1, '{}'::jsonb),
  ('fridge', 'Fridge', '🧊', 'fridge', 'fridge', array['cold_drink'], 100, null, 'Double-door fridge. Soup go last the week.', 640, 350000, 'mid', 'kitchen', 0.65, 0.62, true, 'in', 1, '{"cook_home":{"hunger":2}}'::jsonb),
  ('fridge_sbs', 'Side-by-side fridge (Samsung)', '🧊', 'fridge_sbs', 'fridge', array['cold_drink'], 100, null, 'Ice maker and water tap for the door.', 650, 1800000, 'nepo', 'kitchen', 0.95, 0.75, true, 'in', 1, '{"cold_drink":{"hunger":4,"fun":3},"cook_home":{"hunger":3}}'::jsonb),
  ('freezer_chest', 'Chest freezer (Haier Thermocool 200L)', '🧊', 'freezer', 'none', array['cold_drink'], 100, null, 'Freeze your turkey for Christmas. 100 hours cold.', 660, 450000, 'mid', 'kitchen', 1, 0.62, true, 'in', 1, '{"cook_home":{"hunger":4}}'::jsonb),
  ('microwave', 'Microwave (Scanfrost 20L)', '📦', 'microwave', 'none', '{}'::text[], 100, null, 'Warm yesterday jollof in 2 minutes.', 670, 95000, 'mid', 'kitchen', 0.55, 0.45, true, 'in', 1, '{"cook_home":{"hunger":2}}'::jsonb),
  ('blender', 'Blender (Binatone)', '🥤', 'blender', 'none', '{}'::text[], 100, null, 'Blend pepper, no more grinding stone.', 680, 45000, 'mid', 'kitchen', 0.4, 0.4, true, 'in', 1, '{"cook_home":{"fun":2}}'::jsonb),
  ('pots_set', 'Pot set + mortar & pestle', '🍲', 'pots', 'none', '{}'::text[], 100, null, 'Pots from Oba Market plus mortar for pounded yam.', 690, 35000, 'lapo', 'kitchen', 0.7, 0.4, true, 'in', 1, '{"cook_home":{"hunger":2}}'::jsonb),
  ('water_dispenser', 'Water dispenser (Nexus)', '🚰', 'dispenser', 'none', array['cold_drink'], 100, null, 'Hot and cold water, no more sachet wahala.', 700, 85000, 'mid', 'kitchen', 0.38, 0.38, true, 'in', 1, '{}'::jsonb),
  ('kitchen_table', 'Wooden kitchen table', '🪵', 'table', 'none', '{}'::text[], 100, null, 'Simple table for chopping and eating.', 710, 30000, 'lapo', 'kitchen', 0.9, 0.6, true, 'in', 2, '{}'::jsonb),
  ('dining_4', '4-seater dining set', '🍽️', 'dining4', 'none', '{}'::text[], 100, null, 'Table and four chairs. Family time.', 720, 350000, 'mid', 'kitchen', 1.5, 1.6, true, 'in', 1, '{"cook_home":{"fun":2}}'::jsonb),
  ('dining_6', '6-seater glass dining set', '🍽️', 'dining6', 'none', '{}'::text[], 100, null, 'Glass top, leather chairs. Sunday rice with the whole family.', 730, 1600000, 'nepo', 'kitchen', 2.1, 1.7, true, 'in', 1, '{"cook_home":{"fun":4}}'::jsonb),
  ('kitchen_cabinet', 'Kitchen cabinet', '🗄️', 'kitchen_cab', 'none', '{}'::text[], 100, null, 'Cupboard plus worktop.', 740, 220000, 'mid', 'kitchen', 1.2, 0.55, true, 'in', 2, '{"cook_home":{"hunger":1}}'::jsonb),
  ('kitchen_fitted', 'Fitted kitchen (cabinets + sink)', '🍳', 'kitchen', 'none', array['cook_home'], 100, null, 'Built-in hob, sink and cabinets. Proper kitchen.', 750, 2500000, 'nepo', 'kitchen', 2.2, 0.62, true, 'in', 1, '{"cook_home":{"hunger":5,"fun":2}}'::jsonb),
  ('kitchen_island', 'Kitchen island + stools', '🍳', 'island', 'none', '{}'::text[], 100, null, 'Breakfast bar with two stools.', 760, 1200000, 'nepo', 'kitchen', 1.6, 0.8, true, 'in', 1, '{"cook_home":{"fun":3}}'::jsonb),
  ('drum_bucket', 'Water drum and bucket', '🪣', 'drum_bucket', 'bath', array['bathe'], 100, null, 'Fetch water, bath with bucket. Classic.', 770, 22000, 'lapo', 'bathroom', 1, 0.6, true, 'in', 1, '{}'::jsonb),
  ('bucket_bowl', 'Bucket and bowl', '🪣', 'bucket_bowl', 'bath', array['bathe'], 100, null, 'Bucket, bowl and small soap. Na so we start.', 780, 6000, 'lapo', 'bathroom', 0.6, 0.45, true, 'in', 1, '{}'::jsonb),
  ('water_heater', 'Water heater (Ariston 30L)', '♨️', 'water_heater', 'none', '{}'::text[], 100, null, 'Hot water for morning bath. Harmattan no go catch you.', 790, 160000, 'mid', 'bathroom', 0.45, 0.3, false, 'wall', 2, '{"bathe":{"hygiene":8,"stress":-4}}'::jsonb),
  ('mirror_bath', 'Bathroom mirror', '🪞', 'mirror_wall', 'none', '{}'::text[], 100, null, 'Wall mirror.', 800, 25000, 'mid', 'bathroom', 0.6, 0.08, false, 'wall', 2, '{}'::jsonb),
  ('towel_rack', 'Towel rack', '🧺', 'towel_rack', 'none', '{}'::text[], 100, null, 'Dry towel, no more smelling towel.', 810, 28000, 'mid', 'bathroom', 0.6, 0.3, true, 'in', 2, '{"bathe":{"hygiene":2}}'::jsonb),
  ('washing_machine', 'Washing machine (LG 8kg)', '🧺', 'washer', 'none', '{}'::text[], 100, null, 'No more hand-washing on Saturday.', 820, 650000, 'nepo', 'bathroom', 0.62, 0.62, true, 'in', 1, '{"bathe":{"hygiene":4}}'::jsonb),
  ('gen_tiger', 'Tiger gen ("I better pass my neighbour")', '⚡', 'gen_small', 'none', '{}'::text[], 100, '#d4232b', '950 watts of pride. Noise pass power.', 830, 95000, 'lapo', 'utility', 0.55, 0.4, true, 'out', 1, '{"watch_tv":{"fun":2},"sleep":{"energy":2}}'::jsonb),
  ('gen_firman', 'Sumec Firman 2.8KVA gen', '⚡', 'generator', 'none', '{}'::text[], 100, '#e2a21a', 'Manual start. Fan, TV, fridge, all dey run.', 840, 370000, 'mid', 'utility', 0.8, 0.55, true, 'out', 1, '{"watch_tv":{"fun":3},"sleep":{"energy":3}}'::jsonb),
  ('gen_soundproof', 'Soundproof diesel gen (20KVA)', '⚡', 'gen_big', 'none', '{}'::text[], 100, null, 'Whole house on, no noise. NEPA who?', 850, 12000000, 'nepo', 'utility', 1.8, 0.9, true, 'out', 1, '{"watch_tv":{"fun":4},"sleep":{"energy":6,"stress":-3}}'::jsonb),
  ('inverter_small', '1.5KVA inverter + battery', '🔋', 'inverter_small', 'none', '{}'::text[], 100, null, 'Fan and TV through the night.', 860, 650000, 'mid', 'utility', 0.5, 0.4, true, 'in', 1, '{"sleep":{"energy":4}}'::jsonb),
  ('inverter_solar', '3.5KVA inverter + solar batteries', '🔋', 'inverter', 'none', '{}'::text[], 100, null, 'Lithium batteries, AC dey run till morning.', 870, 3200000, 'nepo', 'utility', 0.8, 0.5, true, 'in', 1, '{"sleep":{"energy":8,"stress":-4},"watch_tv":{"fun":4}}'::jsonb),
  ('solar_panels', 'Solar panels on frame', '☀️', 'solar', 'none', '{}'::text[], 100, null, 'Sun na free light. Pair am with the inverter.', 880, 1200000, 'nepo', 'utility', 2, 1.1, true, 'out', 2, '{"sleep":{"stress":-2}}'::jsonb),
  ('water_tank', 'GeePee 1000L water tank', '💧', 'water_tank', 'none', '{}'::text[], 100, null, 'Water for the whole week. Borehole carry am go up.', 890, 38000, 'mid', 'utility', 1.2, 1.2, true, 'out', 1, '{"bathe":{"hygiene":4}}'::jsonb),
  ('drum_blue', 'Blue water drum', '🛢️', 'drum', 'none', '{}'::text[], 100, null, 'Store water before the tap stop.', 900, 15000, 'lapo', 'utility', 0.6, 0.6, true, 'any', 2, '{"bathe":{"hygiene":2}}'::jsonb),
  ('gate_light', 'Security floodlight pole', '🔦', 'gate_light', 'none', '{}'::text[], 100, null, 'Thieves no like light.', 910, 60000, 'mid', 'utility', 0.4, 0.4, true, 'out', 2, '{}'::jsonb),
  ('car_shade', 'Car shade', '⛱️', 'car_shade', 'none', '{}'::text[], 100, null, 'Keep sun off your Benz.', 920, 850000, 'nepo', 'utility', 2.8, 4.2, false, 'out', 1, '{}'::jsonb),
  ('clothesline', 'Clothesline', '👚', 'clothesline', 'none', '{}'::text[], 100, null, 'Spread your clothes, pray rain no fall.', 930, 5000, 'lapo', 'utility', 2.4, 0.2, false, 'out', 1, '{}'::jsonb),
  ('garden_set', 'Garden chair set', '⛱️', 'garden_set', 'none', '{}'::text[], 100, null, 'Table, umbrella and two chairs for evening breeze.', 940, 450000, 'nepo', 'utility', 1.6, 1.6, true, 'out', 1, '{"sit_rest":{"stress":-2}}'::jsonb),
  ('plant_potted', 'Potted plant', '🪴', 'plant', 'none', '{}'::text[], 100, null, 'Green thing for the corner.', 950, 15000, 'lapo', 'decor', 0.45, 0.45, true, 'any', 4, '{}'::jsonb),
  ('plant_palm', 'Indoor palm', '🌴', 'plant_big', 'none', '{}'::text[], 100, null, 'Tall palm in a big pot.', 960, 85000, 'nepo', 'decor', 0.6, 0.6, true, 'any', 4, '{}'::jsonb),
  ('wall_art', 'Ankara canvas art', '🖼️', 'wall_art', 'none', '{}'::text[], 100, '#e67e22', 'Bright Ankara pattern on canvas.', 970, 35000, 'mid', 'decor', 0.9, 0.08, false, 'wall', 4, '{"relax_sofa":{"fun":1}}'::jsonb),
  ('bronze_plaque', 'Benin bronze plaque (replica)', '🛡️', 'plaque', 'none', '{}'::text[], 100, null, 'Igun Street bronze-caster replica. Respect to the palace.', 980, 450000, 'nepo', 'decor', 0.5, 0.1, false, 'wall', 4, '{"relax_sofa":{"fun":2}}'::jsonb),
  ('bronze_head', 'Benin bronze head (replica)', '🗿', 'bronze_head', 'none', '{}'::text[], 100, null, 'Queen Idia style head, cast on Igun Street.', 990, 750000, 'nepo', 'decor', 0.45, 0.45, true, 'in', 2, '{"relax_sofa":{"fun":2}}'::jsonb),
  ('wall_clock', 'Wall clock', '🕰️', 'wall_clock', 'none', '{}'::text[], 100, null, 'Tick tock. African time still dey.', 1000, 8000, 'lapo', 'decor', 0.4, 0.08, false, 'wall', 2, '{}'::jsonb),
  ('family_photo', 'Framed family photo', '🖼️', 'photo_frame', 'none', '{}'::text[], 100, null, 'Mama, Papa and everybody for studio.', 1010, 12000, 'lapo', 'decor', 0.5, 0.08, false, 'wall', 4, '{"sit_rest":{"stress":-1}}'::jsonb),
  ('aquarium', 'Aquarium', '🐠', 'aquarium', 'none', '{}'::text[], 100, null, 'Fish wey you no go cook.', 1020, 380000, 'nepo', 'decor', 1, 0.42, true, 'in', 1, '{"relax_sofa":{"stress":-3}}'::jsonb),
  ('flower_vase', 'Artificial flower vase', '💐', 'vase', 'none', '{}'::text[], 100, null, 'Flowers wey no dey die.', 1030, 20000, 'mid', 'decor', 0.3, 0.3, true, 'in', 4, '{}'::jsonb)
on conflict (id) do update set
  name = excluded.name, emoji = excluded.emoji, kind = excluded.kind, slot = excluded.slot,
  activities = excluded.activities, rest_pct = excluded.rest_pct, color = excluded.color,
  description = excluded.description, sort = excluded.sort, price = excluded.price, tier = excluded.tier,
  category = excluded.category, w = excluded.w, d = excluded.d, solid = excluded.solid,
  placement = excluded.placement, max_qty = excluded.max_qty, bonus = excluded.bonus;

-- ---------------------------------------------------------------- 3. home layouts (server copy)
create table if not exists public.home_layouts (
  id     text primary key,
  w      numeric(5,2) not null,
  d      numeric(5,2) not null,
  lot    jsonb not null,           -- [x0, z0, x1, z1] house + yard
  blocks jsonb not null,           -- [[x0, z0, x1, z1], ...] solid pieces may not overlap these
  doors  jsonb not null,           -- the door clear zones (also in blocks)
  slots  jsonb not null            -- {"bed": [x, z, rot], ...} default spots of row-less furniture
);
alter table public.home_layouts enable row level security;
drop policy if exists home_layouts_read on public.home_layouts;
create policy home_layouts_read on public.home_layouts for select to anon, authenticated using (true);
grant select on public.home_layouts to anon, authenticated;

insert into public.home_layouts (id, w, d, lot, blocks, doors, slots) values
  ('hostel', 5.2, 4.4, '[0,0,7.6,5.6]'::jsonb, '[[6.05,0.45,7.15,1.55],[6.05,1.85,7.15,2.95],[6.3,4.3,6.9,4.9],[4.4,3.1,6,4.1]]'::jsonb, '[[4.4,3.1,6,4.1]]'::jsonb, '{"bed":[0.75,1.1,0],"seat":[3.2,2.9,0],"sofa":[2,3.4,3],"tv":[0.3,3.4,1],"stove":[4.7,0.4,0],"fridge":[4.85,1.45,3],"wardrobe":[3.4,0.35,0],"bath":[6.8,3.55,3]}'::jsonb),
  ('face_me', 4.2, 3.8, '[0,0,7.2,5.4]'::jsonb, '[[5.65,0.35,6.75,1.45],[5.65,1.7,6.75,2.8],[4.6,4.43,5.4,4.98],[6.1,4.3,6.7,4.9],[3.4,2.4,5,3.3]]'::jsonb, '[[3.4,2.4,5,3.3]]'::jsonb, '{"bed":[0.85,1.1,0],"seat":[1.3,3.2,3],"sofa":[1.7,3.3,2],"tv":[2.75,0.3,0],"rug":[2.2,2.4,0],"stove":[3.6,2,3],"fridge":[3.75,0.4,0],"wardrobe":[0.35,3,1],"bath":[5.7,3.5,3]}'::jsonb),
  ('self_contain', 6, 4.8, '[0,0,7.4,6]'::jsonb, '[[0.23,0.15,0.68,0.85],[0.83,0.18,1.78,1.13],[0.14,1.25,0.56,1.75],[6.53,0.6,7.08,1.4],[1.84,-0.06,1.96,1.16],[-0.06,1.94,1.26,2.06],[5.2,2.55,6.8,3.45]]'::jsonb, '[[5.2,2.55,6.8,3.45]]'::jsonb, '{"bed":[4.95,1.5,3],"seat":[2.6,3.5,3],"sofa":[2.6,3.5,3],"tv":[0.3,3.5,1],"ctable":[1.45,3.5,1],"rug":[1.6,3.5,1],"stove":[2.7,0.35,0],"fridge":[3.55,0.4,0],"wardrobe":[5.3,0.35,0],"bath":[6.7,2,0]}'::jsonb),
  ('flat', 8, 6.2, '[0,0,9.4,7.4]'::jsonb, '[[5.88,0.15,6.32,0.85],[6.98,0.13,7.93,1.08],[6.55,0.09,7.05,0.51],[8.53,0.8,9.08,1.6],[3.14,-0.06,3.26,1.66],[3.14,2.34,3.26,2.86],[-0.06,2.74,2.46,2.86],[5.54,-0.06,5.66,1.46],[5.54,2.34,6.66,2.46],[7.34,2.34,8.06,2.46],[7.2,4.4,8.8,5.4]]'::jsonb, '[[7.2,4.4,8.8,5.4]]'::jsonb, '{"bed":[0.95,1.15,0],"seat":[3.2,4.7,3],"sofa":[3.2,4.7,3],"tv":[0.3,4.7,1],"ctable":[1.9,4.7,1],"rug":[2,4.7,0],"stove":[4.2,0.35,0],"fridge":[5.1,0.4,0],"wardrobe":[2.4,0.35,0],"bath":[8.7,2.6,0]}'::jsonb),
  ('duplex', 10, 7.6, '[-1,-0.4,14.5,10.6]'::jsonb, '[[7.48,0.15,7.93,0.85],[9.1,0.35,9.9,2.05],[8.25,0.09,8.75,0.51],[10.73,1,11.28,1.8],[3.74,-0.06,3.86,2.06],[-0.06,3.14,2.86,3.26],[7.14,-0.06,7.26,1.66],[7.14,2.74,8.06,2.86],[8.84,2.74,10.06,2.86],[9.2,5,10.8,6.2],[4.4,6.8,5.6,8.4]]'::jsonb, '[[9.2,5,10.8,6.2],[4.4,6.8,5.6,8.4]]'::jsonb, '{"bed":[1.3,1.25,0],"seat":[3.2,5.6,3],"sofa":[3.2,5.6,3],"tv":[0.3,5.6,1],"ctable":[1.9,5.6,1],"rug":[2.2,5.6,0],"stove":[5.7,0.35,0],"fridge":[4.4,0.35,0],"wardrobe":[3,0.35,0],"bath":[11,3,0]}'::jsonb)
on conflict (id) do update set w = excluded.w, d = excluded.d, lot = excluded.lot, blocks = excluded.blocks,
  doors = excluded.doors, slots = excluded.slots;

-- ---------------------------------------------------------------- helpers
-- housing_id -> client layout id (src/art/home3d/model.ts homeLayoutFor).
create or replace function public.bl_home_layout_id(p_housing text) returns text
language sql immutable set search_path = public as $$
  select case bl_housing_kind(p_housing) when 'mini_flat' then 'flat' else bl_housing_kind(p_housing) end
$$;
revoke execute on function public.bl_home_layout_id(text) from public, anon, authenticated;

-- own_plastic_chair-3 -> plastic_chair
create or replace function public.bl_furniture_id_of(p_key text) returns text
language sql immutable set search_path = public as $$
  select regexp_replace(regexp_replace(coalesce(p_key, ''), '^own_', ''), '-[0-9]+$', '')
$$;
revoke execute on function public.bl_furniture_id_of(text) from public, anon, authenticated;

-- copy number of a key (own_x = 1, own_x-3 = 3)
create or replace function public.bl_furniture_copy_of(p_key text) returns integer
language sql immutable set search_path = public as $$
  select coalesce(nullif(substring(coalesce(p_key, '') from '-([0-9]+)$'), '')::int, 1)
$$;
revoke execute on function public.bl_furniture_copy_of(text) from public, anon, authenticated;

-- Give every owned copy a row for the current home (same rule as the client's furnishHome):
-- rows saved in another home are dropped, then each row-less copy 1 takes its slot's default spot if it is
-- the first row-less piece of that slot (by furniture.sort) and the layout has the slot; the rest are stored.
-- Returns the layout id.
create or replace function public.bl_furniture_materialize(p_uid uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_layout text;
  hl home_layouts;
begin
  select bl_home_layout_id(housing_id) into v_layout from profiles where id = p_uid;
  select * into hl from home_layouts where id = v_layout;
  if hl.id is null then return v_layout; end if;
  delete from player_house_furniture where owner_id = p_uid and layout is not null and layout <> v_layout;
  update player_house_furniture set layout = v_layout
   where owner_id = p_uid and layout is null
     and x between (hl.lot->>0)::numeric and (hl.lot->>2)::numeric
     and z between (hl.lot->>1)::numeric and (hl.lot->>3)::numeric;
  delete from player_house_furniture where owner_id = p_uid and layout is null;
  delete from player_house_furniture h
   where h.owner_id = p_uid
     and not exists (select 1 from player_furniture pf
                      where pf.user_id = p_uid and pf.furniture_id = bl_furniture_id_of(h.furniture_key)
                        and bl_furniture_copy_of(h.furniture_key) <= pf.qty);
  insert into player_house_furniture (owner_id, furniture_key, x, z, rotation, stored, layout, updated_at)
  select p_uid, r.key,
         case when r.placed then (hl.slots->r.slot->>0)::numeric else 0 end,
         case when r.placed then (hl.slots->r.slot->>1)::numeric else 0 end,
         case when r.placed then (((hl.slots->r.slot->>2)::int % 4) + 4) % 4 else 0 end,
         not r.placed, v_layout, bl_now()
    from (select m.key, m.slot,
                 (m.copy = 1 and hl.slots ? m.slot
                  and row_number() over (partition by m.slot, m.copy = 1 order by m.sort, m.furniture_id) = 1) as placed
            from (select pf.furniture_id, coalesce(pf.slot, f.slot) as slot, f.sort, n as copy,
                         case when n = 1 then 'own_' || pf.furniture_id else 'own_' || pf.furniture_id || '-' || n end as key
                    from player_furniture pf
                    join furniture f on f.id = pf.furniture_id
                    cross join lateral generate_series(1, pf.qty) n
                   where pf.user_id = p_uid and f.active) m
           where not exists (select 1 from player_house_furniture h where h.owner_id = p_uid and h.furniture_key = m.key)) r
  on conflict (owner_id, furniture_key) do nothing;
  return v_layout;
end $$;
revoke execute on function public.bl_furniture_materialize(uuid) from public, anon, authenticated;

-- Why a piece can't stand at x/z/rot in p_uid's home (null = fine), as 'hint|message'. Mirrors
-- src/art/home3d/arrange.ts placementIssue. Other pieces = p_uid's placed (not stored) solid rows.
create or replace function public.bl_furniture_check(p_uid uuid, p_layout text, p_key text, p_x numeric, p_z numeric, p_rot integer)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  f furniture;
  hl home_layouts;
  e constant numeric := 0.02;
  t constant numeric := 0.000001;
  v_w numeric; v_d numeric;
  x0 numeric; z0 numeric; x1 numeric; z1 numeric;
  v_in boolean; v_yard boolean;
  b jsonb;
  o record;
begin
  select * into f from furniture where id = bl_furniture_id_of(p_key);
  select * into hl from home_layouts where id = p_layout;
  if f.id is null or hl.id is null then return 'unknown_furniture|That furniture can''t be placed here.'; end if;
  if p_x is null or p_z is null then return 'outside_home|Place furniture on the floor inside your home.'; end if;
  if ((coalesce(p_rot, 0) % 2) + 2) % 2 = 1 then v_w := f.d; v_d := f.w; else v_w := f.w; v_d := f.d; end if;
  x0 := p_x - v_w / 2; x1 := p_x + v_w / 2; z0 := p_z - v_d / 2; z1 := p_z + v_d / 2;
  v_in := x0 >= -t and z0 >= -t and x1 <= hl.w + t and z1 <= hl.d + t;
  v_yard := x0 >= (hl.lot->>0)::numeric - t and z0 >= (hl.lot->>1)::numeric - t
        and x1 <= (hl.lot->>2)::numeric + t and z1 <= (hl.lot->>3)::numeric + t
        and not (least(x1, hl.w) - greatest(x0, 0) > e and least(z1, hl.d) - greatest(z0, 0) > e);
  if f.placement = 'in' and not v_in then return 'outside_home|This one must stay inside the house.'; end if;
  if f.placement = 'out' and not v_yard then return 'outside_home|This one belongs outside in the compound.'; end if;
  if f.placement = 'any' and not v_in and not v_yard then
    return 'outside_home|Keep it fully inside the house or fully in the compound.';
  end if;
  if f.placement = 'wall' then
    if not v_in then return 'outside_home|Hang it on a wall inside the house.'; end if;
    if z0 > 0.35 and x0 > 0.35 then return 'not_on_wall|Push it against the back wall to hang it.'; end if;
  end if;
  if not f.solid then return null; end if;
  for b in select * from jsonb_array_elements(hl.doors) loop
    if least(x1, (b->>2)::numeric) - greatest(x0, (b->>0)::numeric) > e
       and least(z1, (b->>3)::numeric) - greatest(z0, (b->>1)::numeric) > e then
      return 'blocks_door|You are blocking the door.';
    end if;
  end loop;
  for b in select * from jsonb_array_elements(hl.blocks) loop
    if least(x1, (b->>2)::numeric) - greatest(x0, (b->>0)::numeric) > e
       and least(z1, (b->>3)::numeric) - greatest(z0, (b->>1)::numeric) > e then
      return 'overlap|Something is already there (wall or fixture).';
    end if;
  end loop;
  for o in
    select h.x, h.z, h.rotation, fo.w, fo.d, fo.name
      from player_house_furniture h
      join furniture fo on fo.id = bl_furniture_id_of(h.furniture_key)
     where h.owner_id = p_uid and h.furniture_key <> p_key and not h.stored and h.layout = p_layout and fo.solid
  loop
    declare ow numeric := case when o.rotation % 2 = 1 then o.d else o.w end;
            od numeric := case when o.rotation % 2 = 1 then o.w else o.d end;
    begin
      if least(x1, o.x + ow / 2) - greatest(x0, o.x - ow / 2) > e
         and least(z1, o.z + od / 2) - greatest(z0, o.z - od / 2) > e then
        return 'overlap|It is touching your ' || lower(o.name) || '.';
      end if;
    end;
  end loop;
  return null;
end $$;
revoke execute on function public.bl_furniture_check(uuid, text, text, numeric, numeric, integer) from public, anon, authenticated;

-- The homeowner, at home, not travelling / visiting (the same rule as social_home_place_furniture).
create or replace function public.bl_furniture_owner_home(p_uid uuid) returns profiles
language plpgsql security definer set search_path = public as $$
declare v_me profiles;
begin
  select * into v_me from profiles where id = p_uid for update;
  if v_me.home_visit_host_id is not null or v_me.location_id is distinct from v_me.home_location_id or v_me.travel_to is not null then
    raise exception 'Only the homeowner can arrange furniture while at home.' using errcode = 'P0001', hint = 'not_homeowner';
  end if;
  return v_me;
end $$;
revoke execute on function public.bl_furniture_owner_home(uuid) from public, anon, authenticated;

create or replace function public.bl_furniture_require_owned(p_uid uuid, p_key text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(p_key, '') !~ '^own_[a-z0-9_]+(-[0-9]+)?$' then
    raise exception 'Choose one of your movable furniture pieces.' using errcode = 'P0001', hint = 'fixed_furniture';
  end if;
  if not exists (select 1 from player_furniture pf join furniture f on f.id = pf.furniture_id
                  where pf.user_id = p_uid and pf.furniture_id = bl_furniture_id_of(p_key) and f.active
                    and bl_furniture_copy_of(p_key) between 1 and pf.qty) then
    raise exception 'You do not own that furniture.' using errcode = 'P0001', hint = 'not_owned';
  end if;
end $$;
revoke execute on function public.bl_furniture_require_owned(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- 4. RPCs
-- Buy one piece: cash first, then bank. It is delivered to the inventory (stored); the client then
-- opens placement. Works anywhere (the shop delivers to your house).
create or replace function public.furniture_buy(p_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_me   profiles;
  f      furniture;
  v_qty  int;
  v_key  text;
  v_cash bigint;
  v_bank bigint;
  v_layout text;
begin
  select * into v_me from profiles where id = v_uid for update;
  select * into f from furniture where id = p_id and active and buyable;
  if not found then
    raise exception 'That item is not for sale.' using errcode = 'P0001', hint = 'unknown_furniture';
  end if;
  select qty into v_qty from player_furniture where user_id = v_uid and furniture_id = f.id for update;
  if coalesce(v_qty, 0) >= f.max_qty then
    raise exception 'You already have % of these. Na the maximum.', f.max_qty using errcode = 'P0001', hint = 'max_owned';
  end if;
  if v_me.cash + greatest(v_me.bank, 0) < f.price then
    raise exception 'Not enough money. % costs % and you have % (cash % + bank %).', f.name, bl_naira(f.price),
      bl_naira(v_me.cash + greatest(v_me.bank, 0)), bl_naira(v_me.cash), bl_naira(greatest(v_me.bank, 0))
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_cash := least(greatest(v_me.cash, 0), f.price);
  v_bank := f.price - v_cash;
  if v_cash > 0 then
    perform bl_add_money(v_uid, 'cash', -v_cash, 'furniture', jsonb_build_object('furniture', f.id, 'name', f.name));
  end if;
  if v_bank > 0 then
    perform bl_add_money(v_uid, 'bank', -v_bank, 'furniture', jsonb_build_object('furniture', f.id, 'name', f.name));
  end if;
  -- existing pieces get their rows first (so the new copy can't steal a default slot)
  v_layout := bl_furniture_materialize(v_uid);
  insert into player_furniture (user_id, furniture_id, slot, source, qty)
  values (v_uid, f.id, null, 'buy', 1)
  on conflict (user_id, furniture_id) do update set qty = player_furniture.qty + 1
  returning qty into v_qty;
  v_key := case when v_qty = 1 then 'own_' || f.id else 'own_' || f.id || '-' || v_qty end;
  insert into player_house_furniture (owner_id, furniture_key, x, z, rotation, stored, layout, updated_at)
  values (v_uid, v_key, 0, 0, 0, true, v_layout, bl_now())
  on conflict (owner_id, furniture_key) do update set stored = true, layout = excluded.layout, updated_at = excluded.updated_at;
  return jsonb_build_object('furniture_key', v_key, 'id', f.id, 'name', f.name, 'qty', v_qty, 'spent', f.price,
                            'from_cash', v_cash, 'from_bank', v_bank,
                            'cash', v_me.cash - v_cash, 'bank', v_me.bank - v_bank,
                            'message', f.name || ' don land for your house! Place am where you like.');
end $$;
revoke execute on function public.furniture_buy(text) from public, anon;
grant execute on function public.furniture_buy(text) to authenticated, service_role;

-- Place (or move) one of my pieces at home. Validated server-side; quarter turns only.
create or replace function public.furniture_place(p_key text, p_x numeric, p_z numeric, p_rotation integer default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_rot int := ((coalesce(p_rotation, 0) % 4) + 4) % 4;
  v_layout text;
  v_err text;
  v_x numeric := round(p_x, 3);
  v_z numeric := round(p_z, 3);
begin
  perform bl_furniture_owner_home(v_uid);
  perform bl_furniture_require_owned(v_uid, p_key);
  v_layout := bl_furniture_materialize(v_uid);
  v_err := bl_furniture_check(v_uid, v_layout, p_key, v_x, v_z, v_rot);
  if v_err is not null then
    raise exception '%', split_part(v_err, '|', 2) using errcode = 'P0001', hint = split_part(v_err, '|', 1);
  end if;
  insert into player_house_furniture (owner_id, furniture_key, x, z, rotation, stored, layout, updated_at)
  values (v_uid, p_key, v_x, v_z, v_rot, false, v_layout, bl_now())
  on conflict (owner_id, furniture_key) do update
    set x = excluded.x, z = excluded.z, rotation = excluded.rotation, stored = false,
        layout = excluded.layout, updated_at = excluded.updated_at;
  return jsonb_build_object('furniture_key', p_key, 'x', v_x, 'z', v_z, 'rotation', v_rot, 'stored', false, 'layout', v_layout);
end $$;
revoke execute on function public.furniture_place(text, numeric, numeric, integer) from public, anon;
grant execute on function public.furniture_place(text, numeric, numeric, integer) to authenticated, service_role;

-- Put a piece back in the inventory.
create or replace function public.furniture_store(p_key text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_layout text;
begin
  perform bl_furniture_owner_home(v_uid);
  perform bl_furniture_require_owned(v_uid, p_key);
  v_layout := bl_furniture_materialize(v_uid);
  update player_house_furniture set stored = true, updated_at = bl_now()
   where owner_id = v_uid and furniture_key = p_key;
  return jsonb_build_object('furniture_key', p_key, 'stored', true, 'layout', v_layout);
end $$;
revoke execute on function public.furniture_store(text) from public, anon;
grant execute on function public.furniture_store(text) to authenticated, service_role;

-- The V2 arrange RPC keeps its signature and grants and now uses the same validation.
CREATE OR REPLACE FUNCTION public.social_home_place_furniture(p_furniture_key text, p_x numeric, p_z numeric, p_rotation smallint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  r := public.furniture_place(p_furniture_key, p_x, p_z, coalesce(p_rotation, 0)::int);
  return jsonb_build_object('furniture_key', r->>'furniture_key', 'x', (r->>'x')::numeric, 'z', (r->>'z')::numeric,
                            'rotation', (r->>'rotation')::int);
end $function$;

-- ---------------------------------------------------------------- 5. need bonuses from placed furniture
-- owned = a piece listing the activity that is not (all copies) stored; rest_pct = best of those;
-- bonus = per need, the strongest bonus->activity value among placed pieces (no stacking of 5 ACs).
CREATE OR REPLACE FUNCTION public.bl_furniture_for(p_uid uuid, p_activity text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with owner as (
    select coalesce((select p.home_visit_host_id from public.profiles p
                      where p.id = p_uid and p.home_visit_host_id is not null
                        and p.location_id = p.home_location_id), p_uid) as id),
  own as (
    select f.*
      from public.player_furniture pf
      join public.furniture f on f.id = pf.furniture_id
     where pf.user_id = (select id from owner) and f.active
       and pf.qty > (select count(*) from public.player_house_furniture h
                      where h.owner_id = pf.user_id and h.stored
                        and public.bl_furniture_id_of(h.furniture_key) = pf.furniture_id))
  select jsonb_build_object(
    'owned', count(*) filter (where p_activity = any (own.activities)) > 0,
    'rest_pct', coalesce(max(own.rest_pct) filter (where p_activity = any (own.activities)), 100),
    'bonus', (select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
                from (select e.key as k, (array_agg((e.value #>> '{}')::numeric order by abs((e.value #>> '{}')::numeric) desc))[1] as v
                        from own o2, jsonb_each(coalesce(o2.bonus -> p_activity, '{}'::jsonb)) e
                       where jsonb_typeof(o2.bonus -> p_activity) = 'object' and jsonb_typeof(e.value) = 'number'
                       group by e.key) x))
    from own;
$function$;

-- do_activity (live definition) + the bonus right after the rest_pct block; ledger label; admin columns.
do $mig$
declare
  v_def text;
  v_marker text := '  if v_me.rent_owed > 0 and bl_csv_has(bl_cfg_text(''rent.owed_sleep_activities''), a.id)';
begin
  v_def := pg_get_functiondef('public.do_activity'::regproc);
  if position('B1: placed furniture bonus' in v_def) = 0 then
    if position(v_marker in v_def) = 0 then raise exception 'B1: do_activity marker not found'; end if;
    v_def := replace(v_def, v_marker,
      E'  -- B1: placed furniture bonus (AC/fan -> sleep, fridge/cooker -> cooking, water heater -> bath ...)\n'
      || E'  if a.home_only and jsonb_typeof(v_furn->''bonus'') = ''object'' and v_furn->''bonus'' <> ''{}''::jsonb then\n'
      || E'    v_eff := v_eff || bl_effects_add(bl_need_effects(v_eff), bl_need_effects(v_furn->''bonus''));\n'
      || E'  end if;\n' || v_marker);
    execute v_def;
  end if;

  v_def := pg_get_functiondef('public.bl_ledger_label'::regproc);
  if position('''furniture''' in v_def) = 0 then
    if position('    when ''garage'' then' in v_def) = 0 then raise exception 'B1: bl_ledger_label marker not found'; end if;
    v_def := replace(v_def, '    when ''garage'' then',
      E'    when ''furniture'' then return ''Furniture: '' || coalesce(p_meta->>''name'', ''furniture'');\n    when ''garage'' then');
    execute v_def;
  end if;

  v_def := pg_get_functiondef('public.bl_admin_table_spec'::regproc);
  if position('"max_qty"' in v_def) = 0 then
    if position('"color":"text_null","description":"text","sort":"int","active":"bool"}}''' in v_def) = 0 then
      raise exception 'B1: bl_admin_table_spec marker not found';
    end if;
    v_def := replace(v_def, '"color":"text_null","description":"text","sort":"int","active":"bool"}}''',
      '"color":"text_null","description":"text","sort":"int","active":"bool","price":"money","tier":"text",'
      || '"category":"text","w":"num","d":"num","solid":"bool","placement":"text","max_qty":"int","bonus":"obj","buyable":"bool"}}''');
    execute v_def;
  end if;
end $mig$;

notify pgrst, 'reload schema';
