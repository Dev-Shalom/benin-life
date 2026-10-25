-- Cooking and markets (docs/COOKING.md, step C of the family plan): real ingredients in the bag (a cup, a derica, a tuber, a bunch, a sachet),
-- two places to buy them (Oba Market: cheaper, day hours only, a small server-computed price change every Benin day; Edo Fresh Supermarket:
-- always open, dearer, fixed), recipes anyone can edit in Admin -> Content, cooking on the stove at home (the server checks and removes the
-- ingredients, portions land in the bag), a Cooking skill with a daily XP cap, the Catering certificate (unlocks Black soup, cooks faster),
-- sharing portions with a partner, and home-cooked meals as kids' food.
-- Rules for this file:
--   * NOTHING here touches public.profiles (no ALTER, no trigger, no foreign key): a first deploy of kids deadlocked on it (SQLSTATE 40P01).
--     cook_daily is keyed by user id with no foreign key.
--   * Idempotent: tables `if not exists`, seeds and settings `on conflict do nothing`; our own functions `create or replace`; every live function
--     written by an earlier step is patched with a guarded replace against its CURRENT definition (raises when the marker is missing,
--     skips when already applied).
--   * The price of an ingredient is computed by the server only (bl_cook_price). Items are the existing `items` table (category 'ingredient'),
--     shops are the existing shop_list / shop_buy, eating is the existing item_use. A dish is a normal food item `dish_<recipe id>` that the
--     recipe keeps in step (trigger on our own tables).

create or replace function pg_temp.ck_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'cooking: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Cooking and markets)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('cooking.enabled', 'true', 'cooking', 'Cooking on',
 'Off = nobody can cook (recipes and prices still show). Shops and the Bag are not affected.', 'bool', null, null),
('cooking.market_band_pct', '8', 'cooking', 'Oba Market: daily price band (+/- %)',
 'Every Benin day the price of each ingredient at Oba Market moves by a fixed, server-computed amount between minus and plus this percent of its base price (Content -> Items). The same for every player all day. 0 = prices never move.', 'percent', 0, 40),
('cooking.supermarket_markup_pct', '30', 'cooking', 'Supermarket: markup over the base price (%)',
 'Edo Fresh Supermarket sells ingredients at the base price plus this percent, fixed, open all day. Oba Market never costs more than this.', 'percent', 0, 200),
('cooking.max_pot', '3', 'cooking', 'Biggest pot (batches)',
 'A player can cook 1 up to this many batches at once. Ingredients and portions are multiplied by the pot size.', 'number', 1, 6),
('cooking.pot_time_extra_pct', '50', 'cooking', 'Each extra batch adds to the cooking time (%)',
 'Cooking 2 batches takes (100 + this) percent of the time of 1 batch, 3 batches 100 + 2 x this, and so on.', 'percent', 0, 300),
('cooking.max_busy_seconds', '45', 'cooking', 'Longest a cook keeps you busy (real seconds)',
 'The cooking time in game minutes is turned into real seconds like any activity, but never above this.', 'number', 3, 300),
('cooking.max_portions', '40', 'cooking', 'Most portions of one dish in a bag',
 'Cooking is refused when the new portions would take one dish over this number. Keeps hoarding and food parcels sensible.', 'number', 1, 500),
('cooking.stove_required', 'true', 'cooking', 'A stove is needed at home',
 'On = the home must have a cooker or stove (kerosene stove, hot plate, gas cooker). Off = any home will do.', 'bool', null, null),
('cooking.xp_daily_cap', '100', 'cooking', 'Cooking XP a player can earn per Benin day',
 'Cooking XP stops at this number each Benin day (before the XP multiplier in Settings -> Skills). Stops XP farming. 0 = cooking gives no XP.', 'number', 0, 10000),
('cooking.easy_dish_levels', '2', 'cooking', 'A dish is "easy" when you are this many levels above it',
 'A dish whose required level is at least this many levels under the player gives only the easy share of its XP.', 'number', 1, 10),
('cooking.easy_dish_xp_pct', '40', 'cooking', 'XP from an easy dish (%)',
 'See above. 100 = easy dishes give full XP.', 'percent', 0, 100),
('cooking.catering_cert', '"catering"', 'cooking', 'Catering certificate id',
 'The certificate (Content -> Certificates) that cooks faster. Dishes can also need a certificate: Content -> Recipes.', 'text', null, null),
('cooking.catering_time_cut_pct', '25', 'cooking', 'Catering certificate: cooking time cut (%)',
 'Players with the Catering certificate cook every dish this much faster.', 'percent', 0, 90),
('cooking.share_daily_cap', '20', 'cooking', 'Portions a player can send their partner per Benin day',
 'Sharing food with a partner is free but limited. 0 = sharing is off.', 'number', 0, 500),
('cooking.kid_meal_enabled', 'true', 'cooking', 'Home-cooked meals feed children',
 'On = feeding a child from Nursery up uses one cooked portion from the bag instead of lunch money, when the parent has one.', 'bool', null, null),
('cooking.kid_meal_boost_pct', '25', 'cooking', 'Home-cooked meal: extra fullness for a child (%)',
 'A home-cooked portion fills a child this much more than the normal feeding (Settings -> Kids: Feeding gives hunger).', 'percent', 0, 200)
on conflict (key) do nothing;

-- groceries carry no VAT, like the other basic foods
update public.game_config set value = to_jsonb((value #>> '{}') || ',ingredient')
 where key = 'economy.vat_exempt_categories' and position('ingredient' in (value #>> '{}')) = 0;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables (RLS on, no client grants: players read through RPCs, admins through Content)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.cook_recipes (
  id           text primary key check (id ~ '^[a-z0-9_]{2,30}$'),
  name         text not null check (char_length(name) between 2 and 50),
  emoji        text not null default '🍲',
  blurb        text not null default '' check (char_length(blurb) <= 240),
  min_level    integer not null default 1 check (min_level between 1 and 50),
  cert_id      text,
  portions     integer not null default 4 check (portions between 1 and 50),
  game_minutes integer not null default 30 check (game_minutes between 1 and 600),
  hunger       numeric not null default 40 check (hunger between 0 and 100),
  energy       numeric not null default 0 check (energy between -100 and 100),
  mood         numeric not null default 0 check (mood between -100 and 100),
  xp           integer not null default 10 check (xp between 0 and 1000),
  sort         integer not null default 100,
  active       boolean not null default true
);

create table if not exists public.cook_ingredients (
  recipe_id text not null references public.cook_recipes (id) on update cascade on delete cascade,
  item_id   text not null references public.items (id) on update cascade on delete cascade,
  qty       integer not null default 1 check (qty between 0 and 50),
  primary key (recipe_id, item_id)
);

-- per player and Benin day: XP given, cooks, portions sent to the partner. No foreign key to profiles.
create table if not exists public.cook_daily (
  user_id uuid not null,
  day     date not null,
  xp      integer not null default 0 check (xp >= 0),
  cooks   integer not null default 0 check (cooks >= 0),
  shared  integer not null default 0 check (shared >= 0),
  primary key (user_id, day)
);

do $$
declare t text;
begin
  foreach t in array array['cook_recipes', 'cook_ingredients', 'cook_daily'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. Ingredients (normal items, category 'ingredient'), 2026 Nigerian prices in small portions
-- ---------------------------------------------------------------------------------------------
insert into public.items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort, tradeable) values
('rice',         'Rice, 1 derica',               'ingredient',  900, 'One derica of local rice (a 50 kg bag is about N85,000). For jollof and more.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🍚', 1000, false),
('beans',        'Beans, 1 derica',              'ingredient', 1350, 'One derica of brown beans (about N3,000 a kg).', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🫘', 1001, false),
('garri',        'Garri, 1 derica',              'ingredient',  400, 'One derica of white garri (about N810 a kg). For eba.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🥣', 1002, false),
('yam',          'Yam tuber, medium',            'ingredient', 3500, 'One medium tuber of yam.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🍠', 1003, false),
('plantain',     'Plantain, 1 big finger',       'ingredient',  500, 'One big ripe plantain, for dodo.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🍌', 1004, false),
('palm_oil_cup', 'Palm oil, 1 cup',              'ingredient',  900, 'One cup of red palm oil.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🛢️', 1005, false),
('veg_oil',      'Vegetable oil, 1 cup',         'ingredient', 1100, 'One cup of vegetable oil for frying.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🫗', 1006, false),
('tomatoes',     'Tomatoes, 1 small heap',       'ingredient', 1200, 'A small heap of fresh tomatoes.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🍅', 1007, false),
('pepper',       'Fresh pepper, 1 heap',         'ingredient',  600, 'A heap of tatashe and scotch bonnet.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🌶️', 1008, false),
('onions',       'Onions, 3 bulbs',              'ingredient',  500, 'Three bulbs of onions.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🧅', 1009, false),
('crayfish',     'Crayfish, 1 cup',              'ingredient', 1500, 'One cup of ground crayfish.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🦐', 1010, false),
('dry_fish',     'Dry fish, 1 piece',            'ingredient', 2500, 'One medium smoked dry fish.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🐟', 1011, false),
('chicken',      'Chicken, 1 piece',             'ingredient', 2500, 'One big piece of chicken.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🍗', 1012, false),
('meat',         'Assorted meat, 1 portion',     'ingredient', 2500, 'A portion of beef and assorted meat.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🥩', 1013, false),
('eggs',         'Egg, 1',                       'ingredient',  250, 'One fresh egg.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🥚', 1014, false),
('instant_noodles', 'Instant noodles, 1 pack',   'ingredient',  350, 'One pack of instant noodles.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🍜', 1015, false),
('egusi',        'Egusi, 1 cup',                 'ingredient', 1500, 'One cup of ground egusi (melon seed).', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🌰', 1016, false),
('bitter_leaf',  'Bitter leaf, 1 bunch',         'ingredient',  400, 'One bunch of washed bitter leaf.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🌿', 1017, false),
('scent_leaf',   'Scent leaf, 1 bunch',          'ingredient',  200, 'One bunch of scent leaf (efirin).', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🍃', 1018, false),
('ugu',          'Ugu (spinach), 1 bunch',       'ingredient',  400, 'One bunch of fresh ugu leaves.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🥬', 1019, false),
('palm_fruit',   'Palm fruit, 1 bowl',           'ingredient', 2000, 'One bowl of fresh palm fruit, for banga.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🌴', 1020, false),
('beletete',     'Beletete spice, 1 sachet',     'ingredient',  300, 'One sachet of beletete, the spice that makes banga smell like banga.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🧂', 1021, false),
('potash',       'Potash (kaun), 1 small lump',  'ingredient',  200, 'A small lump of potash for owo and black soup.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🪨', 1022, false),
('starch',       'Starch, 1 wrap',               'ingredient',  700, 'One wrap of cassava starch for owo and banga.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🥣', 1023, false),
('pap',          'Pap (ogi), 1 cup',             'ingredient',  300, 'One cup of ogi, ready for pap.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🥛', 1024, false),
('seasoning',    'Seasoning cubes, 1 sachet',    'ingredient',  250, 'A sachet of seasoning cubes.', '{}'::jsonb, '{oba_market,edo_fresh_supermarket}', false, 0, '🧂', 1025, false)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Recipes (Content -> Recipes and Recipe ingredients)
-- ---------------------------------------------------------------------------------------------
insert into public.cook_recipes (id, name, emoji, blurb, min_level, cert_id, portions, game_minutes, hunger, energy, mood, xp, sort) values
('noodles_egg',   'Indomie and egg',               '🍜', 'Instant noodles and fried egg. The student special: quick, cheap, never fails.', 1, null, 2, 8, 32, 2, 3, 10, 10),
('akara_pap',     'Akara and pap',                 '🥣', 'Hot bean cakes and warm pap, the Benin morning.', 1, null, 4, 25, 38, 4, 4, 10, 20),
('beans_dodo',    'Beans and dodo',                '🫘', 'Soft beans in palm oil with sweet fried plantain.', 2, null, 4, 40, 50, 5, 6, 14, 30),
('yam_asaro',     'Yam porridge (asaro)',          '🍠', 'Yam cooked soft in palm oil, pepper and crayfish. One pot, plenty of food.', 2, null, 5, 45, 55, 6, 6, 14, 40),
('jollof_chicken','Jollof rice and chicken',       '🍛', 'Party jollof with fried chicken. Everybody go ask for more.', 3, null, 8, 60, 52, 4, 9, 18, 50),
('owo_starch',    'Owo soup with starch',          '🍲', 'Thick owo soup with potash, palm oil and meat, with soft starch.', 4, null, 8, 55, 55, 4, 7, 22, 60),
('banga_starch',  'Banga soup with starch or eba', '🥘', 'Palm fruit banga with beletete, fish and meat. Eat with starch or eba.', 4, null, 8, 60, 58, 4, 8, 22, 70),
('egusi_pounded', 'Egusi soup with pounded yam',   '🍲', 'Rich egusi with ugu, fish and meat, and pounded yam on the side.', 5, null, 8, 75, 65, 5, 10, 28, 80),
('black_soup',    'Black soup (omoebe)',           '🥣', 'The Benin pride: bitter leaf, scent leaf, potash and palm oil. Needs the Catering certificate.', 6, 'catering', 8, 80, 70, 6, 12, 34, 90)
on conflict (id) do nothing;

insert into public.cook_ingredients (recipe_id, item_id, qty) values
('noodles_egg', 'instant_noodles', 2), ('noodles_egg', 'eggs', 2),
('akara_pap', 'beans', 1), ('akara_pap', 'pepper', 1), ('akara_pap', 'onions', 1), ('akara_pap', 'veg_oil', 1), ('akara_pap', 'pap', 2),
('beans_dodo', 'beans', 1), ('beans_dodo', 'plantain', 3), ('beans_dodo', 'palm_oil_cup', 1), ('beans_dodo', 'onions', 1), ('beans_dodo', 'pepper', 1), ('beans_dodo', 'seasoning', 1),
('yam_asaro', 'yam', 1), ('yam_asaro', 'palm_oil_cup', 1), ('yam_asaro', 'pepper', 1), ('yam_asaro', 'onions', 1), ('yam_asaro', 'crayfish', 1), ('yam_asaro', 'ugu', 1), ('yam_asaro', 'seasoning', 1),
('jollof_chicken', 'rice', 3), ('jollof_chicken', 'tomatoes', 1), ('jollof_chicken', 'pepper', 1), ('jollof_chicken', 'onions', 1), ('jollof_chicken', 'veg_oil', 1), ('jollof_chicken', 'chicken', 2), ('jollof_chicken', 'seasoning', 1),
('owo_starch', 'starch', 3), ('owo_starch', 'potash', 1), ('owo_starch', 'palm_oil_cup', 2), ('owo_starch', 'pepper', 1), ('owo_starch', 'crayfish', 1), ('owo_starch', 'dry_fish', 1), ('owo_starch', 'meat', 1), ('owo_starch', 'beletete', 1), ('owo_starch', 'seasoning', 1),
('banga_starch', 'palm_fruit', 2), ('banga_starch', 'beletete', 1), ('banga_starch', 'pepper', 1), ('banga_starch', 'onions', 1), ('banga_starch', 'crayfish', 1), ('banga_starch', 'dry_fish', 1), ('banga_starch', 'meat', 1), ('banga_starch', 'garri', 2), ('banga_starch', 'seasoning', 1),
('egusi_pounded', 'egusi', 2), ('egusi_pounded', 'palm_oil_cup', 1), ('egusi_pounded', 'ugu', 1), ('egusi_pounded', 'crayfish', 1), ('egusi_pounded', 'dry_fish', 1), ('egusi_pounded', 'meat', 1), ('egusi_pounded', 'pepper', 1), ('egusi_pounded', 'onions', 1), ('egusi_pounded', 'yam', 1), ('egusi_pounded', 'seasoning', 1),
('black_soup', 'bitter_leaf', 2), ('black_soup', 'scent_leaf', 2), ('black_soup', 'potash', 1), ('black_soup', 'palm_oil_cup', 2), ('black_soup', 'dry_fish', 1), ('black_soup', 'meat', 2), ('black_soup', 'crayfish', 1), ('black_soup', 'pepper', 1), ('black_soup', 'yam', 1), ('black_soup', 'seasoning', 1)
on conflict (recipe_id, item_id) do nothing;

-- the Cooking skill text now points at the kitchen (only while nobody changed it)
update public.skills set train_text = 'Cook at home in the Kitchen (Chowdeck app) with ingredients from Oba Market or the supermarket, and sell jollof, puff-puff or fried yam at the Oba Market stall.'
 where id = 'cooking' and train_text = 'Cook at home (rice and stew) and sell jollof, puff-puff or fried yam at the Oba Market stall.';

-- ---------------------------------------------------------------------------------------------
-- 5. Private helpers (revoked from clients at the end)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_cook_num(p_key text, p_default numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_cook_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = 'cooking.enabled'), true);
$$;

-- the Benin day as text (p_back = days ago)
create or replace function public.bl_cook_day(p_back integer default 0) returns text
language sql stable security definer set search_path = public as $$
  select to_char((bl_now() at time zone bl_clock_tz())::date - greatest(coalesce(p_back, 0), 0), 'YYYY-MM-DD');
$$;

-- The price of an ingredient at a place on a Benin day (p_day null = today). A market (scene 'market') moves each day by a fixed amount
-- inside the admin band, seeded by day + item + place, and never above the supermarket. Any other place is the fixed supermarket price.
create or replace function public.bl_cook_price(p_item public.items, p_location text, p_day text default null) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare v_day text := coalesce(p_day, bl_cook_day(0)); v_scene text; v_h bigint; v_band numeric; v_sup numeric; v_p numeric;
begin
  select scene into v_scene from locations where id = p_location;
  v_sup := p_item.price * (1 + greatest(0, bl_cook_num('cooking.supermarket_markup_pct', 30)) / 100.0);
  if v_scene = 'market' then
    v_band := greatest(0, least(100, bl_cook_num('cooking.market_band_pct', 8)));
    v_h := ('x' || substr(md5(v_day || ':' || p_item.id || ':' || p_location), 1, 8))::bit(32)::bigint;
    if v_h >= 2147483648 then v_h := v_h - 4294967296; end if;
    v_p := least(p_item.price * (1 + (v_band / 100.0) * (v_h / 2147483648.0)), v_sup);
  else
    v_p := v_sup;
  end if;
  if v_p < 1000 then return greatest(10, (round(v_p / 10.0) * 10)::bigint); end if;
  return (round(v_p / 50.0) * 50)::bigint;
end $$;

-- yesterday's shelf price (with VAT if any) at a market, null for anything that does not move
create or replace function public.bl_cook_yesterday(p_item public.items, p_location text) returns bigint
language plpgsql stable security definer set search_path = public as $$
begin
  if p_item.category <> 'ingredient' or coalesce((select scene from locations where id = p_location), '') <> 'market' then return null; end if;
  return bl_gross('item', p_item.category, bl_cook_price(p_item, p_location, bl_cook_day(1)));
end $$;

-- the Cooking level the gates use (everything is open when Skills are off)
create or replace function public.bl_cook_level(p_uid uuid) returns integer
language sql stable security definer set search_path = public as $$
  select case when bl_skill_on() then bl_skill_level(p_uid, 'cooking') else 99 end;
$$;

create or replace function public.bl_cook_partner(p_uid uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select case when r.user_a = p_uid then r.user_b else r.user_a end
    from love_relationships r
   where r.status = 'couple' and r.ended_at is null and (r.user_a = p_uid or r.user_b = p_uid)
   order by r.couple_at desc nulls last, r.id desc limit 1;
$$;

-- the cooked dish a parent feeds a child with (most portions first), null when off or none
create or replace function public.bl_cook_kid_dish(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select i.item_id from inventory i
   where i.user_id = p_uid and i.qty > 0 and left(i.item_id, 5) = 'dish_'
     and coalesce((select (value #>> '{}')::boolean from game_config where key = 'cooking.kid_meal_enabled'), true)
   order by i.qty desc, i.item_id limit 1;
$$;

-- Keep the dish item in step with its recipe: name, effects per portion, and the ingredient cost of one portion (shown as its value).
create or replace function public.bl_cook_sync_dish(p_recipe text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.cook_recipes; v_cost numeric; v_eff jsonb;
begin
  select * into r from cook_recipes where id = p_recipe;
  if not found then return; end if;
  select coalesce(sum(it.price * ci.qty), 0) into v_cost from cook_ingredients ci join items it on it.id = ci.item_id where ci.recipe_id = r.id;
  v_eff := '{}'::jsonb;
  if r.hunger <> 0 then v_eff := v_eff || jsonb_build_object('hunger', r.hunger); end if;
  if r.energy <> 0 then v_eff := v_eff || jsonb_build_object('energy', r.energy); end if;
  if r.mood <> 0 then v_eff := v_eff || jsonb_build_object('fun', r.mood); end if;
  insert into items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort, tradeable)
  values ('dish_' || r.id, r.name, 'food', greatest(0, round(v_cost / greatest(r.portions, 1) / 10.0) * 10)::bigint,
          'One home-cooked portion of ' || r.name || '. Eat it from your Bag, share it with your partner, or feed a child.',
          v_eff, '{}', false, 0, r.emoji, 800 + r.sort, false)
  on conflict (id) do update set name = excluded.name, price = excluded.price, description = excluded.description,
                                 effects = excluded.effects, icon = excluded.icon, sort = excluded.sort;
end $$;

create or replace function public.bl_cook_sync_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'cook_recipes' then
    perform bl_cook_sync_dish(new.id);
  else
    perform bl_cook_sync_dish(case when tg_op = 'DELETE' then old.recipe_id else new.recipe_id end);
  end if;
  return null;
end $$;

drop trigger if exists cook_recipes_sync on public.cook_recipes;
create trigger cook_recipes_sync after insert or update on public.cook_recipes for each row execute function public.bl_cook_sync_trg();
drop trigger if exists cook_ingredients_sync on public.cook_ingredients;
create trigger cook_ingredients_sync after insert or update or delete on public.cook_ingredients for each row execute function public.bl_cook_sync_trg();

-- the dish items for the seeded recipes (also covers a re-run)
do $$
declare r record;
begin
  for r in select id from cook_recipes loop perform bl_cook_sync_dish(r.id); end loop;
end $$;

-- Cooking XP: capped per Benin day (in base XP, before the XP multipliers), less for dishes far below the player's level.
-- Level-ups use the normal skill_up event.
create or replace function public.bl_cook_award(p_uid uuid, p_recipe public.cook_recipes) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles; k skills; v_day date := bl_cook_day(0)::date; v_used int; v_cap int := greatest(0, bl_cook_num('cooking.xp_daily_cap', 100)::int);
  v_base numeric := p_recipe.xp; v_lvl int; v_give numeric; v_mult numeric; v_gain int := 0; v_old int; v_xp int; v_new int; v_ups text[]; v_easy boolean := false;
begin
  insert into cook_daily (user_id, day) values (p_uid, v_day) on conflict do nothing;
  delete from cook_daily where user_id = p_uid and day < v_day - 7;
  select xp into v_used from cook_daily where user_id = p_uid and day = v_day for update;
  update cook_daily set cooks = cooks + 1 where user_id = p_uid and day = v_day;
  if not bl_skill_on() then
    return jsonb_build_object('gain', 0, 'capped', false, 'off', true);
  end if;
  select * into k from skills where id = 'cooking';
  select * into v_me from profiles where id = p_uid;
  v_lvl := bl_skill_level(p_uid, 'cooking');
  if v_lvl >= p_recipe.min_level + greatest(1, bl_cook_num('cooking.easy_dish_levels', 2)::int) then
    v_base := round(v_base * least(100, greatest(0, bl_cook_num('cooking.easy_dish_xp_pct', 40))) / 100.0);
    v_easy := true;
  end if;
  v_give := greatest(0, least(v_base, v_cap - v_used));
  if v_give <= 0 then
    return jsonb_build_object('gain', 0, 'capped', v_base > 0, 'easy', v_easy, 'xp_today', v_used, 'xp_cap', v_cap);
  end if;
  update cook_daily set xp = xp + v_give::int where user_id = p_uid and day = v_day;
  v_mult := coalesce((select max(bl_trait_mult(v_me, array['skill_xp', tk])) from unnest(coalesce(k.trait_keys, '{}')) tk), 1);
  v_gain := greatest(1, round(v_give * v_mult * bl_skill_num('skills.xp_mult', 1))::int);
  v_old := bl_skill_level_for_xp(bl_skill_xp(p_uid, 'cooking'));
  insert into player_skills (user_id, skill_id, xp, updated_at) values (p_uid, 'cooking', least(v_gain, 1000000000), bl_now())
  on conflict (user_id, skill_id) do update set xp = least(player_skills.xp::bigint + v_gain, 1000000000)::int, updated_at = bl_now()
  returning xp into v_xp;
  v_new := bl_skill_level_for_xp(v_xp);
  if v_new > v_old then
    v_ups := bl_skill_unlocks('cooking', v_new);
    perform bl_event(p_uid, 'skill_up', k.icon || ' ' || k.name || ' level ' || v_new || '!',
      case when cardinality(v_ups) > 0 then array_to_string(v_ups, ' · ') else 'Keep training, e dey show.' end,
      jsonb_build_object('skill', 'cooking', 'name', k.name, 'icon', k.icon, 'level', v_new, 'unlocks', to_jsonb(v_ups)));
  end if;
  return jsonb_build_object('gain', v_gain, 'xp', v_xp, 'level', v_new, 'up', v_new > v_old, 'easy', v_easy,
                            'xp_today', v_used + v_give::int, 'xp_cap', v_cap, 'capped', (v_used + v_give::int) >= v_cap);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Patches of live functions (guarded)
-- ---------------------------------------------------------------------------------------------
-- a) the shelf price: groceries come from bl_cook_price (admin band + supermarket markup)
select pg_temp.ck_patch('public.bl_shop_price(public.items, text)',
  $o$select * into r from shop_price_rules x where x.active and x.location_id = p_location and x.item_id = p_item.id limit 1;$o$,
  $o$if p_item.category = 'ingredient' then return bl_cook_price(p_item, p_location, null); end if;
  select * into r from shop_price_rules x where x.active and x.location_id = p_location and x.item_id = p_item.id limit 1;$o$,
  $o$bl_cook_price(p_item, p_location, null)$o$);

-- b) the shop list shows yesterday's price (null for anything that does not move)
select pg_temp.ck_patch('public.shop_list(text)',
  $o$'description', it.description, 'effects', it.effects, 'icon', it.icon,$o$,
  $o$'description', it.description, 'effects', it.effects, 'icon', it.icon, 'yesterday', bl_cook_yesterday(it, l.id),$o$,
  $o$bl_cook_yesterday(it, l.id)$o$);

-- c) kids: from Nursery a parent with a home-cooked portion feeds with it (no lunch money)
select pg_temp.ck_patch('public.bl_kids_can(public.kids_children, text, timestamp with time zone, uuid)',
  $o$v_cost := case when c.status = 'university' then bl_love_num('kids_school.uni_pocket_cost', 6000)::bigint else bl_love_num('kids.feed_cost', 1500)::bigint end;$o$,
  $o$v_item := bl_cook_kid_dish(p_uid);
      if v_item is null then
        v_cost := case when c.status = 'university' then bl_love_num('kids_school.uni_pocket_cost', 6000)::bigint else bl_love_num('kids.feed_cost', 1500)::bigint end;
      end if;$o$,
  $o$bl_cook_kid_dish(p_uid)$o$);
select pg_temp.ck_patch('public.kids_care(bigint, text)',
  $o$perform bl_kids_use(v_me.id, v_item);$o$,
  $o$if left(v_item, 5) = 'dish_' then perform bl_give_item(v_me.id, v_item, -1); else perform bl_kids_use(v_me.id, v_item); end if;$o$,
  $o$left(v_item, 5) = 'dish_'$o$);
select pg_temp.ck_patch('public.kids_care(bigint, text)',
  $o$if p_action = 'feed' then v_boost := v_ki.boost_pct; end if;$o$,
  $o$if p_action = 'feed' then v_boost := case when left(v_item, 5) = 'dish_' then bl_cook_num('cooking.kid_meal_boost_pct', 25) else v_ki.boost_pct end; end if;$o$,
  $o$bl_cook_num('cooking.kid_meal_boost_pct', 25)$o$);

-- d) Admin -> Content editors: recipes and their ingredients
select pg_temp.ck_patch('public.bl_admin_table_spec(text)',
  $o$when 'kids_auto_names' then$o$,
  E'when ''cook_recipes'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","emoji":"text","blurb":"text","min_level":"int","cert_id":"text_null","portions":"int","game_minutes":"int","hunger":"num","energy":"num","mood":"num","xp":"int","sort":"int","active":"bool"}}\'\n    when ''cook_ingredients'' then ''{"pk":["recipe_id","item_id"],"insert":true,"order":"recipe_id, item_id",\n      "cols":{"qty":"int"}}\'\n    when ''kids_auto_names'' then',
  $o$when 'cook_recipes' then$o$);

-- ---------------------------------------------------------------------------------------------
-- 7. Player RPCs
-- ---------------------------------------------------------------------------------------------
-- Today's grocery prices at both places, with yesterday's price at the market (read-only).
create or replace function public.grocery_prices() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); m locations; s locations;
begin
  select * into m from locations where id = 'oba_market';
  select * into s from locations where id = 'edo_fresh_supermarket';
  return jsonb_build_object(
    'day', bl_cook_day(0),
    'band_pct', bl_cook_num('cooking.market_band_pct', 8), 'markup_pct', bl_cook_num('cooking.supermarket_markup_pct', 30),
    'market', jsonb_build_object('id', m.id, 'name', m.name, 'open_now', bl_place_open(m), 'open_hour', m.open_hour, 'close_hour', m.close_hour,
                                 'hours', case when m.open_hour is null then 'Open all day' else bl_hour_label(m.open_hour) || ' to ' || bl_hour_label(m.close_hour) end),
    'supermarket', jsonb_build_object('id', s.id, 'name', s.name, 'open_now', bl_place_open(s), 'hours', 'Open all day'),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', it.id, 'name', it.name, 'icon', it.icon, 'description', it.description,
               'today', bl_dealer_price(it, m.id), 'yesterday', bl_cook_yesterday(it, m.id), 'super', bl_dealer_price(it, s.id),
               'change_pct', case when bl_cook_yesterday(it, m.id) > 0
                                  then round((bl_dealer_price(it, m.id) - bl_cook_yesterday(it, m.id)) * 100.0 / bl_cook_yesterday(it, m.id), 1) else 0 end,
               'owned', coalesce((select qty from inventory where user_id = v_uid and item_id = it.id), 0))
             order by it.sort, it.id)
        from items it where it.category = 'ingredient' and m.id = any (it.sold_at) and s.id = any (it.sold_at)), '[]'::jsonb));
end $$;

-- The kitchen: recipes with what you have, your Cooking level, the dishes in your bag (read-only).
create or replace function public.cook_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_me profiles := bl_me_any(); v_lvl int; v_xp int; v_cert text := coalesce(bl_cfg_text('cooking.catering_cert'), 'catering'); v_has_cert boolean;
  v_at_home boolean; v_stove boolean; v_day date := bl_cook_day(0)::date; d cook_daily; v_max_pot int := greatest(1, bl_cook_num('cooking.max_pot', 3)::int);
  v_cut numeric; v_partner uuid; v_cap int := greatest(0, bl_cook_num('cooking.xp_daily_cap', 100)::int); v_share_cap int := greatest(0, bl_cook_num('cooking.share_daily_cap', 20)::int);
begin
  v_at_home := v_me.location_id = v_me.home_location_id and v_me.travel_to is null and v_me.home_visit_host_id is null;
  v_stove := not coalesce(bl_cfg_bool('cooking.stove_required'), true) or coalesce((bl_furniture_for(v_me.id, 'cook_home') ->> 'owned')::boolean, false);
  v_lvl := bl_cook_level(v_me.id);
  v_xp := bl_skill_xp(v_me.id, 'cooking');
  v_has_cert := v_cert <> '' and exists (select 1 from player_certificates pc where pc.user_id = v_me.id and pc.cert_id = v_cert);
  v_cut := case when v_has_cert then least(90, greatest(0, bl_cook_num('cooking.catering_time_cut_pct', 25))) else 0 end;
  select * into d from cook_daily where user_id = v_me.id and day = v_day;
  v_partner := bl_cook_partner(v_me.id);
  return jsonb_build_object(
    'enabled', bl_cook_on(), 'at_home', v_at_home, 'stove', v_stove, 'home_name', (select name from locations where id = v_me.home_location_id),
    'skills_on', bl_skill_on(), 'level', case when bl_skill_on() then v_lvl else null end, 'xp', v_xp,
    'level_from', bl_skill_xp_for_level(case when bl_skill_on() then v_lvl else 1 end),
    'level_next', case when bl_skill_on() and v_lvl < bl_skill_max_level() then bl_skill_xp_for_level(v_lvl + 1) else null end,
    'xp_today', coalesce(d.xp, 0), 'xp_cap', v_cap,
    'max_pot', v_max_pot, 'pot_extra_pct', bl_cook_num('cooking.pot_time_extra_pct', 50), 'max_portions', bl_cook_num('cooking.max_portions', 40)::int,
    'catering', jsonb_build_object('cert', v_cert, 'name', coalesce((select name from certificates where id = v_cert), 'Catering'), 'has', v_has_cert, 'time_cut_pct', v_cut,
                                   'full_cut_pct', least(90, greatest(0, bl_cook_num('cooking.catering_time_cut_pct', 25)))),
    'partner', case when v_partner is null then null else (select jsonb_build_object('id', p.id, 'username', p.username) from profiles p where p.id = v_partner) end,
    'shared_today', coalesce(d.shared, 0), 'share_cap', v_share_cap,
    'kid_meal', coalesce((select (value #>> '{}')::boolean from game_config where key = 'cooking.kid_meal_enabled'), true), 'kid_boost_pct', bl_cook_num('cooking.kid_meal_boost_pct', 25),
    'recipes', coalesce((
      select jsonb_agg(x order by (x ->> 'sort')::int, x ->> 'id') from (
        select jsonb_build_object(
          'id', r.id, 'name', r.name, 'emoji', r.emoji, 'blurb', r.blurb, 'sort', r.sort, 'min_level', r.min_level, 'portions', r.portions,
          'minutes', greatest(1, round(r.game_minutes * (1 - v_cut / 100.0))), 'base_minutes', r.game_minutes,
          'hunger', r.hunger, 'energy', r.energy, 'mood', r.mood, 'xp', r.xp, 'dish', 'dish_' || r.id,
          'dish_owned', coalesce((select qty from inventory where user_id = v_me.id and item_id = 'dish_' || r.id), 0),
          'cert', r.cert_id, 'cert_name', (select name from certificates where id = r.cert_id),
          'cert_ok', r.cert_id is null or exists (select 1 from player_certificates pc where pc.user_id = v_me.id and pc.cert_id = r.cert_id),
          'level_ok', v_lvl >= r.min_level,
          'cost_per_portion', (select coalesce(sum(it.price * ci.qty), 0) / greatest(r.portions, 1) from cook_ingredients ci join items it on it.id = ci.item_id where ci.recipe_id = r.id and ci.qty > 0),
          'max_pots', (select least(v_max_pot, coalesce(min(coalesce(inv.qty, 0) / ci.qty), v_max_pot)) from cook_ingredients ci
                         left join inventory inv on inv.user_id = v_me.id and inv.item_id = ci.item_id where ci.recipe_id = r.id and ci.qty > 0),
          'ingredients', coalesce((select jsonb_agg(jsonb_build_object('id', it.id, 'name', it.name, 'icon', it.icon, 'need', ci.qty,
                                                                      'have', coalesce((select qty from inventory where user_id = v_me.id and item_id = it.id), 0))
                                                     order by it.sort, it.id)
                                     from cook_ingredients ci join items it on it.id = ci.item_id where ci.recipe_id = r.id and ci.qty > 0), '[]'::jsonb)) as x
          from cook_recipes r where r.active) q), '[]'::jsonb),
    'dishes', coalesce((
      select jsonb_agg(jsonb_build_object('id', it.id, 'name', it.name, 'icon', it.icon, 'qty', i.qty, 'effects', it.effects) order by it.sort, it.id)
        from inventory i join items it on it.id = i.item_id where i.user_id = v_me.id and i.qty > 0 and left(i.item_id, 5) = 'dish_'), '[]'::jsonb));
end $$;

-- Cook p_pots batches of a recipe on your stove at home. Takes the ingredients, puts the portions in the bag, keeps you busy for the cooking time.
create or replace function public.cook_start(p_recipe text, p_pots integer default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); r cook_recipes; v_pots int := coalesce(p_pots, 1); v_max_pot int := greatest(1, bl_cook_num('cooking.max_pot', 3)::int);
  v_lvl int; v_cert text := coalesce(bl_cfg_text('cooking.catering_cert'), 'catering'); v_has_cert boolean; v_cut numeric := 0; v_min numeric; v_secs numeric;
  v_have int; v_miss text[] := '{}'; ci record; v_portions int; v_owned int; v_cap int := greatest(1, bl_cook_num('cooking.max_portions', 40)::int);
  v_until timestamptz; v_award jsonb; v_msg text;
begin
  if not bl_cook_on() then
    raise exception 'The kitchen is closed for now.' using errcode = 'P0001', hint = 'off';
  end if;
  perform bl_assert_free(v_me);
  select * into r from cook_recipes where id = p_recipe and active;
  if not found then
    raise exception 'That recipe doesn''t exist.' using errcode = 'P0001', hint = 'no_recipe';
  end if;
  if v_me.location_id <> v_me.home_location_id or v_me.home_visit_host_id is not null then
    raise exception 'You can only cook in your own home. Go home to use your stove.' using errcode = 'P0001', hint = 'not_home';
  end if;
  if coalesce(bl_cfg_bool('cooking.stove_required'), true) and not coalesce((bl_furniture_for(v_me.id, 'cook_home') ->> 'owned')::boolean, false) then
    raise exception 'You need a stove or cooker at home first. Buy one in the Buy sheet.' using errcode = 'P0001', hint = 'no_stove';
  end if;
  if v_pots < 1 or v_pots > v_max_pot then
    raise exception 'Pick a pot of 1 to % batches.', v_max_pot using errcode = 'P0001', hint = 'bad_pots';
  end if;
  v_lvl := bl_cook_level(v_me.id);
  if v_lvl < r.min_level then
    raise exception '% needs Cooking level % (you are level %). Cook easier dishes to level up.', r.name, r.min_level, v_lvl using errcode = 'P0001', hint = 'skill_level';
  end if;
  if r.cert_id is not null and not exists (select 1 from player_certificates pc where pc.user_id = v_me.id and pc.cert_id = r.cert_id) then
    raise exception '% needs the % certificate. Take the course in the School app.', r.name, coalesce((select name from certificates where id = r.cert_id), r.cert_id)
      using errcode = 'P0001', hint = 'need_cert';
  end if;
  v_portions := r.portions * v_pots;
  select coalesce(qty, 0) into v_owned from inventory where user_id = v_me.id and item_id = 'dish_' || r.id;
  if coalesce(v_owned, 0) + v_portions > v_cap then
    raise exception 'Your bag cannot hold that much % (at most % portions). Eat or share some first.', r.name, v_cap using errcode = 'P0001', hint = 'bag_full';
  end if;
  for ci in select ci2.item_id, ci2.qty, it.name from cook_ingredients ci2 join items it on it.id = ci2.item_id where ci2.recipe_id = r.id and ci2.qty > 0 order by it.sort, it.id loop
    select coalesce(qty, 0) into v_have from inventory where user_id = v_me.id and item_id = ci.item_id;
    if coalesce(v_have, 0) < ci.qty * v_pots then
      v_miss := v_miss || ((ci.qty * v_pots - coalesce(v_have, 0)) || ' more ' || lower(split_part(ci.name, ',', 1)));
    end if;
  end loop;
  if cardinality(v_miss) > 0 then
    raise exception 'Missing ingredients: %. Buy them at Oba Market or the supermarket.', array_to_string(v_miss, ', ') using errcode = 'P0001', hint = 'no_ingredients';
  end if;
  -- the server takes the ingredients and puts the portions in the bag
  for ci in select ci2.item_id, ci2.qty from cook_ingredients ci2 where ci2.recipe_id = r.id and ci2.qty > 0 loop
    perform bl_give_item(v_me.id, ci.item_id, -(ci.qty * v_pots));
  end loop;
  perform bl_give_item(v_me.id, 'dish_' || r.id, v_portions);
  -- time: the recipe minutes, longer for a bigger pot, shorter with the Catering certificate, never longer than the cap
  v_has_cert := v_cert <> '' and exists (select 1 from player_certificates pc where pc.user_id = v_me.id and pc.cert_id = v_cert);
  if v_has_cert then v_cut := least(90, greatest(0, bl_cook_num('cooking.catering_time_cut_pct', 25))); end if;
  v_min := r.game_minutes * (1 + (v_pots - 1) * greatest(0, bl_cook_num('cooking.pot_time_extra_pct', 50)) / 100.0) * (1 - v_cut / 100.0);
  v_secs := greatest(3, least(bl_real_seconds(v_min), greatest(3, bl_cook_num('cooking.max_busy_seconds', 45))));
  v_until := bl_set_busy_seconds(v_me.id, v_secs, 'Cooking ' || r.name);
  v_award := bl_cook_award(v_me.id, r);
  v_msg := 'You cooked ' || v_portions || ' ' || case when v_portions = 1 then 'portion' else 'portions' end || ' of ' || r.name || '. They are in your Bag.';
  if coalesce((v_award ->> 'gain')::int, 0) > 0 then
    v_msg := v_msg || ' Cooking +' || (v_award ->> 'gain') || ' XP.';
  elsif coalesce((v_award ->> 'capped')::boolean, false) then
    v_msg := v_msg || ' No more Cooking XP today, come back tomorrow.';
  end if;
  return jsonb_build_object('message', v_msg, 'recipe', r.id, 'dish', 'dish_' || r.id, 'portions', v_portions, 'pots', v_pots, 'seconds', round(v_secs, 1),
                            'busy_until', v_until, 'owned', coalesce(v_owned, 0) + v_portions, 'xp', v_award);
end $$;

-- Send cooked portions to your partner (a couple). Free, capped per Benin day, and a dish can never be sold, so this farms nothing.
create or replace function public.cook_share(p_item text, p_qty integer default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); v_to uuid; v_to_name text; it items; v_qty int := coalesce(p_qty, 1); v_day date := bl_cook_day(0)::date;
  v_cap int := greatest(0, bl_cook_num('cooking.share_daily_cap', 20)::int); v_used int; v_have int; v_their int; v_max int := greatest(1, bl_cook_num('cooking.max_portions', 40)::int);
begin
  if p_item is null or left(p_item, 5) <> 'dish_' then
    raise exception 'Only cooked food can be shared.' using errcode = 'P0001', hint = 'not_a_dish';
  end if;
  if v_qty < 1 or v_qty > 100 then
    raise exception 'Pick a number from 1 to 100.' using errcode = 'P0001', hint = 'bad_qty';
  end if;
  if v_cap <= 0 then
    raise exception 'Sharing food is switched off for now.' using errcode = 'P0001', hint = 'off';
  end if;
  v_to := bl_cook_partner(v_me.id);
  if v_to is null then
    raise exception 'Only a partner can get your food. Link up in the Family app first.' using errcode = 'P0001', hint = 'no_partner';
  end if;
  select * into it from items where id = p_item;
  if not found then
    raise exception 'That dish doesn''t exist.' using errcode = 'P0001', hint = 'no_item';
  end if;
  select coalesce(qty, 0) into v_have from inventory where user_id = v_me.id and item_id = p_item;
  if coalesce(v_have, 0) < v_qty then
    raise exception 'You only have % portion(s) of % in your Bag.', coalesce(v_have, 0), it.name using errcode = 'P0001', hint = 'no_item';
  end if;
  insert into cook_daily (user_id, day) values (v_me.id, v_day) on conflict do nothing;
  select shared into v_used from cook_daily where user_id = v_me.id and day = v_day for update;
  if v_used + v_qty > v_cap then
    raise exception 'You can send % more portion(s) today (limit % a day).', greatest(0, v_cap - v_used), v_cap using errcode = 'P0001', hint = 'share_cap';
  end if;
  select coalesce(qty, 0) into v_their from inventory where user_id = v_to and item_id = p_item;
  if coalesce(v_their, 0) + v_qty > v_max then
    raise exception 'Their bag is full of %. Try fewer portions.', it.name using errcode = 'P0001', hint = 'partner_full';
  end if;
  perform bl_give_item(v_me.id, p_item, -v_qty);
  perform bl_give_item(v_to, p_item, v_qty);
  update cook_daily set shared = shared + v_qty where user_id = v_me.id and day = v_day;
  select username into v_to_name from profiles where id = v_to;
  perform bl_event(v_to, 'cook_gift', '🍲 @' || v_me.username || ' sent you food',
                   v_qty || ' ' || case when v_qty = 1 then 'portion' else 'portions' end || ' of ' || it.name || ' is in your Bag.',
                   jsonb_build_object('from', v_me.id, 'item', p_item, 'qty', v_qty));
  return jsonb_build_object('message', 'You sent ' || v_qty || ' ' || case when v_qty = 1 then 'portion' else 'portions' end || ' of ' || it.name || ' to @' || v_to_name || '. 💞',
                            'item', p_item, 'qty', v_qty, 'left', v_have - v_qty, 'shared_today', v_used + v_qty, 'share_cap', v_cap);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Grants: private helpers closed, player RPCs for authenticated only
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and proname like 'bl\_cook\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and proname in ('grocery_prices', 'cook_overview', 'cook_start', 'cook_share') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated', p.sig);
  end loop;
end $$;

notify pgrst, 'reload schema';
