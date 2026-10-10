-- W1: Wardrobe ("Benin Boutique"). docs/WARDROBE.md
-- Idempotent: tables `if not exists`, seeds `on conflict do nothing`, functions `create or replace`.
-- Purely cosmetic: nothing here touches needs, skills, jobs or any other gameplay number.
-- Money moves only through bl_add_money (ledger "Boutique: <item>"), bank first, then cash.

-- ---------------------------------------------------------------------
-- 1. Config
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('wardrobe.enabled', 'true', 'wardrobe', 'Wardrobe on',
 'The Benin Boutique (phone app + Sim sheet) and outfit slots (everyday, home, sleep, date, party, work, gym). Off = the app is hidden, buying and saving are refused and every Sim shows its everyday look. Items: Content → Wardrobe items.', 'bool', null, null),
('wardrobe.brands_enabled', 'true', 'wardrobe', 'Show brands',
 'The boutique is organised by brand (Content → Wardrobe brands). Off = no brand pills; every item is shown by category only.', 'bool', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------
create table if not exists public.wardrobe_brands (
  id       text primary key,
  name     text not null,
  tagline  text not null default '',
  colour   text not null default '#25232b' check (colour ~* '^#[0-9a-f]{6}$'),
  is_house boolean not null default false,
  sponsor  boolean not null default false,
  active   boolean not null default true,
  sort     int not null default 100
);

create table if not exists public.wardrobe_items (
  id            text primary key,
  name          text not null,
  brand_id      text references public.wardrobe_brands(id) on update cascade on delete set null,
  category      text not null check (category in ('top', 'bottom', 'outfit', 'shoes', 'bag', 'hat_hair')),
  -- null = both; otherwise only that gender sees/wears it (the renderer has gendered garments)
  gender        text check (gender in ('male', 'female')),
  -- partial avatar config (docs/AVATAR3D.md): top/bottom {s,f}, shoes {s}, hat, accessories. The chosen colour
  -- fills top.c / bottom.c / shoes.c, or accent for bags and hats (bl_wardrobe_item_patch).
  patch         jsonb not null default '{}'::jsonb,
  colours       text[] not null default '{}',
  price         bigint not null default 0 check (price >= 0),
  tag           text not null default 'basic' check (tag in ('basic', 'designer', 'owambe')),
  default_slots text[] not null default '{}',
  icon          text not null default '👕',
  description   text not null default '',
  active        boolean not null default true,
  sort          int not null default 100
);
alter table public.wardrobe_items add column if not exists brand_id text references public.wardrobe_brands(id) on update cascade on delete set null;

create table if not exists public.player_wardrobe (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  item_id    text not null references public.wardrobe_items(id) on update cascade on delete cascade,
  colour     text,
  price_paid bigint not null default 0,
  bought_at  timestamptz not null default now(),
  primary key (user_id, item_id)
);

create table if not exists public.player_outfits (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  slot       text not null check (slot in ('everyday', 'home', 'sleep', 'date', 'party', 'work', 'gym')),
  -- [{item, colour}] that make the look; null with patch null = "use the default" for this slot
  items      jsonb,
  -- the merged avatar patch (null = use the slot's default rule). No row at all = keep the everyday look.
  patch      jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, slot)
);

alter table public.wardrobe_brands enable row level security;
alter table public.wardrobe_items  enable row level security;
alter table public.player_wardrobe enable row level security;
alter table public.player_outfits  enable row level security;

drop policy if exists wardrobe_brands_read on public.wardrobe_brands;
create policy wardrobe_brands_read on public.wardrobe_brands for select to authenticated using (true);
drop policy if exists wardrobe_items_read on public.wardrobe_items;
create policy wardrobe_items_read on public.wardrobe_items for select to authenticated using (true);
drop policy if exists player_wardrobe_own on public.player_wardrobe;
create policy player_wardrobe_own on public.player_wardrobe for select to authenticated using (user_id = auth.uid());
drop policy if exists player_outfits_own on public.player_outfits;
create policy player_outfits_own on public.player_outfits for select to authenticated using (user_id = auth.uid());

-- Read-only for players; every write goes through the security-definer RPCs below.
revoke all on public.wardrobe_brands, public.wardrobe_items, public.player_wardrobe, public.player_outfits from anon, authenticated;
grant select on public.wardrobe_brands, public.wardrobe_items, public.player_wardrobe, public.player_outfits to authenticated;

-- ---------------------------------------------------------------------
-- 3. Seed: brands + items (only garments the 3D renderer draws; ids from src/art/avatar3d/catalog.ts)
-- Real-brand prices are ESTIMATES (placeholders) - set real prices in admin. docs/WARDROBE.md
-- ---------------------------------------------------------------------
insert into public.wardrobe_brands (id, name, tagline, colour, is_house, sponsor, active, sort) values
  ('benin_basics', 'Benin Basics',      'Everyday pieces, made in Benin City.',            '#1f8a55', true,  false, true, 10),
  ('benin_owambe', 'Benin Owambe',      'Lace, aso-oke and ankara for the big day.',       '#7a1f33', true,  false, true, 20),
  ('ring_road',    'Ring Road Atelier', 'Designer pieces, one tailor at a time.',          '#e0a526', true,  false, true, 30),
  ('go_crazy',     'Go Crazy',          'Loud streetwear for the bold.',                   '#e8692a', false, false, true, 40),
  ('nike',         'Nike',              'Sportswear.',                                     '#25232b', false, false, true, 50),
  ('adidas',       'Adidas',            'Sportswear.',                                     '#2346a8', false, false, true, 60)
on conflict (id) do nothing;

insert into public.wardrobe_items (id, name, brand_id, category, gender, patch, colours, price, tag, default_slots, icon, description, sort) values
  -- Benin Basics: free and affordable everyday pieces
  ('bb_tee',        'Plain tee',          'benin_basics', 'top',    null, '{"top":{"s":"tee","f":"plain"}}',
     '{#f4f1ea,#25232b,#7d828c,#1c2847,#e0a526,#1f8a55}', 0, 'basic', '{everyday,home}', '👕', 'Soft cotton tee. Goes with everything.', 10),
  ('bb_singlet',    'Singlet',            'benin_basics', 'top',    null, '{"top":{"s":"singlet","f":"plain"}}',
     '{#f4f1ea,#25232b,#7d828c}', 0, 'basic', '{home,gym}', '🎽', 'Cool for hot afternoons at home.', 12),
  ('bb_polo',       'Polo shirt',         'benin_basics', 'top',    null, '{"top":{"s":"polo","f":"plain"}}',
     '{#2346a8,#f4f1ea,#1f8a55,#7a1f33,#25232b}', 12000, 'basic', '{everyday,work}', '👕', 'Smart-casual collar for campus or office.', 14),
  ('bb_office',     'Office shirt',       'benin_basics', 'top',    null, '{"top":{"s":"shirt","f":"plain"}}',
     '{#f4f1ea,#5aa7e0,#e25a95,#25232b}', 18000, 'basic', '{work}', '👔', 'Crisp long sleeves for the 9 to 5.', 16),
  ('bb_shirt_tie',  'Shirt and tie',      'benin_basics', 'top',    null, '{"top":{"s":"shirt_tie","f":"plain"}}',
     '{#f4f1ea,#5aa7e0}', 30000, 'basic', '{work}', '👔', 'The tie takes your accent colour.', 18),
  ('bb_jeans',      'Blue jeans',         'benin_basics', 'bottom', null, '{"bottom":{"s":"jeans","f":"plain"}}',
     '{#2f4f86,#25232b,#7d828c}', 0, 'basic', '{everyday}', '👖', 'Your everyday denim.', 20),
  ('bb_joggers',    'Joggers',            'benin_basics', 'bottom', null, '{"bottom":{"s":"joggers","f":"plain"}}',
     '{#25232b,#7d828c,#1c2847}', 0, 'basic', '{home,gym}', '🩳', 'Lounge, run errands, repeat.', 22),
  ('bb_trousers',   'Tailored trousers',  'benin_basics', 'bottom', null, '{"bottom":{"s":"trousers","f":"plain"}}',
     '{#1c2847,#25232b,#7d828c,#c8b28a}', 20000, 'basic', '{work,date}', '👖', 'Sharp crease, all-day comfort.', 24),
  ('bb_wrapper',    'Cotton wrapper',     'benin_basics', 'bottom', null, '{"bottom":{"s":"wrapper","f":"plain"}}',
     '{#f4f1ea,#169c97,#e0a526,#7a1f33}', 8000, 'basic', '{home}', '🧣', 'Tie it and relax at home.', 26),
  ('bb_skirt',      'Pencil skirt',       'benin_basics', 'bottom', 'female', '{"bottom":{"s":"skirt","f":"plain"}}',
     '{#25232b,#1c2847,#7a1f33}', 18000, 'basic', '{work}', '👗', 'Office-ready.', 28),
  ('bb_pyjamas',    'Cotton pyjamas',     'benin_basics', 'outfit', null, '{"top":{"s":"tee","f":"plain"},"bottom":{"s":"joggers","f":"plain"},"shoes":{"s":"slippers","c":"#7d828c"},"hat":"none"}',
     '{#5aa7e0,#e25a95,#7d828c,#c8b28a}', 9000, 'basic', '{sleep}', '😴', 'Matching top and bottoms for a good night.', 30),
  ('bb_slippers',   'Slippers',           'benin_basics', 'shoes',  null, '{"shoes":{"s":"slippers"}}',
     '{#25232b,#7a4a2a,#2346a8}', 0, 'basic', '{home,sleep}', '🩴', 'Indoor and quick-errand slippers.', 40),
  ('bb_sneakers',   'Canvas sneakers',    'benin_basics', 'shoes',  null, '{"shoes":{"s":"sneakers"}}',
     '{#f4f1ea,#25232b}', 0, 'basic', '{everyday}', '👟', 'Clean and simple.', 42),
  ('bb_formal',     'Leather shoes',      'benin_basics', 'shoes',  null, '{"shoes":{"s":"formal"}}',
     '{#25232b,#5a3420}', 28000, 'basic', '{work}', '👞', 'Polished for the office.', 44),
  ('bb_backpack',   'Backpack',           'benin_basics', 'bag',    null, '{"accessories":["backpack"]}',
     '{#25232b,#2346a8,#7a1f33}', 14000, 'basic', '{everyday}', '🎒', 'Books, charger, small chops.', 50),
  ('bb_handbag',    'Handbag',            'benin_basics', 'bag',    null, '{"accessories":["bag"]}',
     '{#25232b,#7a4a2a,#d2342a}', 25000, 'basic', '{everyday,work}', '👜', 'Everyday handbag.', 52),
  ('bb_bare_head',  'No hat',             'benin_basics', 'hat_hair', null, '{"hat":"none"}',
     '{}', 0, 'basic', '{everyday,home}', '💇🏾', 'Show off your hair.', 60),
  ('bb_head_tie',   'Head tie',           'benin_basics', 'hat_hair', 'female', '{"hat":"head_tie"}',
     '{#e0a526,#169c97,#d2342a,#25232b}', 6000, 'basic', '{home,sleep}', '🧕🏾', 'Wrap and go.', 62),
  ('bb_bucket',     'Bucket hat',         'benin_basics', 'hat_hair', null, '{"hat":"bucket"}',
     '{#c8b28a,#25232b,#1f8a55}', 7000, 'basic', '{everyday}', '👒', 'Sun-proof.', 64),
  -- Benin Owambe: traditional and party pieces
  ('bo_ankara_shirt','Ankara shirt',      'benin_owambe', 'top',    null, '{"top":{"s":"short_shirt","f":"ankara"}}',
     '{#e8692a,#169c97,#2346a8,#e0a526}', 22000, 'owambe', '{everyday,date}', '🌀', 'Bright ankara, short sleeves.', 100),
  ('bo_senator',    'Senator kaftan',     'benin_owambe', 'outfit', 'male', '{"top":{"s":"kaftan","f":"plain"},"bottom":{"s":"trousers","f":"plain"}}',
     '{#1f8a55,#1c2847,#f4f1ea,#25232b,#7a1f33}', 65000, 'owambe', '{work,party}', '🧔🏾‍♂️', 'Clean senator for Fridays and functions.', 102),
  ('bo_agbada',     'Lace agbada',        'benin_owambe', 'outfit', 'male', '{"top":{"s":"agbada","f":"lace"},"bottom":{"s":"trousers","f":"plain"},"hat":"fila"}',
     '{#5aa7e0,#f4f1ea,#e0a526,#7a1f33}', 450000, 'owambe', '{party}', '🕴🏾', 'Flowing lace agbada with a matching fila.', 104),
  ('bo_asooke_buba','Aso-oke buba and wrapper','benin_owambe','outfit','female', '{"top":{"s":"buba","f":"asooke"},"bottom":{"s":"wrapper","f":"asooke"},"hat":"gele"}',
     '{#7a1f33,#e0a526,#169c97,#6d2f9c}', 380000, 'owambe', '{party}', '🎉', 'Aso-oke set with a towering gele.', 106),
  ('bo_ankara_gown','Ankara gown',        'benin_owambe', 'outfit', 'female', '{"top":{"s":"gown","f":"ankara"},"bottom":{"s":"skirt","f":"ankara"}}',
     '{#169c97,#e8692a,#2346a8,#d2342a}', 55000, 'owambe', '{party,date}', '👗', 'Fitted ankara gown.', 108),
  ('bo_boubou',     'Lace boubou',        'benin_owambe', 'outfit', 'female', '{"top":{"s":"boubou","f":"lace"},"bottom":{"s":"wrapper","f":"lace"}}',
     '{#169c97,#f4f1ea,#e0a526,#6d2f9c}', 240000, 'owambe', '{party}', '🌺', 'Wide, floating lace boubou.', 110),
  ('bo_sandals',    'Leather sandals',    'benin_owambe', 'shoes',  null, '{"shoes":{"s":"sandals"}}',
     '{#7a4a2a,#25232b,#e0a526}', 12000, 'owambe', '{party}', '🩴', 'Hand-stitched leather.', 112),
  ('bo_heels',      'Party heels',        'benin_owambe', 'shoes',  'female', '{"shoes":{"s":"heels"}}',
     '{#e0a526,#25232b,#d2342a}', 35000, 'owambe', '{party,date}', '👠', 'Dance-floor ready.', 114),
  ('bo_coral_cap',  'Coral bead cap',     'benin_owambe', 'hat_hair', 'male', '{"hat":"coral_cap"}',
     '{#d2342a}', 250000, 'owambe', '{party}', '📿', 'Edo coral beads for the big occasion.', 116),
  -- Ring Road Atelier: designer pieces (cosmetic only)
  ('rr_blazer',     'Date-night suit',    'ring_road',    'outfit', 'male', '{"top":{"s":"blazer","f":"plain"},"bottom":{"s":"trousers","f":"plain"}}',
     '{#1c2847,#25232b,#7a1f33,#c8b28a}', 1800000, 'designer', '{date,work}', '🤵🏾', 'Slim tailored suit.', 200),
  ('rr_evening',    'Evening gown',       'ring_road',    'outfit', 'female', '{"top":{"s":"maxi","f":"plain"},"bottom":{"s":"long_skirt","f":"plain"}}',
     '{#7a1f33,#25232b,#e0a526,#1c2847}', 1500000, 'designer', '{date}', '💃🏾', 'Floor-length, made to measure.', 202),
  ('rr_agbada',     'Royal aso-oke agbada','ring_road',   'outfit', 'male', '{"top":{"s":"agbada","f":"asooke"},"bottom":{"s":"trousers","f":"plain"},"hat":"fila"}',
     '{#7a1f33,#e0a526,#1c2847,#f4f1ea}', 9000000, 'designer', '{party}', '👑', 'Hand-woven aso-oke. The whole hall will look.', 204),
  ('rr_lace_maxi',  'Ivory lace maxi',    'ring_road',    'outfit', 'female', '{"top":{"s":"maxi","f":"lace"},"bottom":{"s":"long_skirt","f":"lace"},"hat":"gele"}',
     '{#f4f1ea,#e0a526,#169c97}', 7500000, 'designer', '{party,date}', '✨', 'Couture lace with a matching gele.', 206),
  ('rr_bag',        'Designer handbag',   'ring_road',    'bag',    null, '{"accessories":["bag"]}',
     '{#e0a526,#25232b,#7a1f33}', 4500000, 'designer', '{date,party}', '👜', 'Gold hardware, soft leather.', 208),
  -- Go Crazy (streetwear). Prices are placeholders: set real prices in admin.
  ('gc_tee',        'Go Crazy tee',       'go_crazy',     'top',    null, '{"top":{"s":"graphic_tee","f":"plain"}}',
     '{#25232b,#f4f1ea,#e8692a}', 35000, 'designer', '{everyday}', '👕', 'Bold graphic print.', 300),
  ('gc_hoodie',     'Go Crazy hoodie',    'go_crazy',     'top',    null, '{"top":{"s":"hoodie","f":"plain"}}',
     '{#e8692a,#25232b,#6d2f9c}', 85000, 'designer', '{everyday}', '🧥', 'Heavyweight hoodie.', 302),
  ('gc_joggers',    'Go Crazy joggers',   'go_crazy',     'bottom', null, '{"bottom":{"s":"joggers","f":"plain"}}',
     '{#25232b,#e8692a,#7d828c}', 60000, 'designer', '{everyday,gym}', '👖', 'Tapered streetwear joggers.', 304),
  ('gc_cap',        'Go Crazy cap',       'go_crazy',     'hat_hair', null, '{"hat":"cap"}',
     '{#e8692a,#25232b,#f4f1ea}', 25000, 'designer', '{everyday}', '🧢', 'Curved peak.', 306),
  -- Nike (estimated Nigerian retail; set real prices in admin)
  ('nk_tee',        'Nike tee',           'nike',         'top',    null, '{"top":{"s":"tee","f":"plain"}}',
     '{#25232b,#f4f1ea,#d2342a}', 55000, 'designer', '{everyday,gym}', '👕', 'Dri-fit training tee.', 400),
  ('nk_hoodie',     'Nike hoodie',        'nike',         'top',    null, '{"top":{"s":"hoodie","f":"plain"}}',
     '{#25232b,#7d828c,#1c2847}', 150000, 'designer', '{everyday}', '🧥', 'Fleece pullover.', 402),
  ('nk_joggers',    'Nike joggers',       'nike',         'bottom', null, '{"bottom":{"s":"joggers","f":"plain"}}',
     '{#25232b,#7d828c}', 120000, 'designer', '{gym,everyday}', '👖', 'Tech fleece joggers.', 404),
  ('nk_cap',        'Nike cap',           'nike',         'hat_hair', null, '{"hat":"cap"}',
     '{#25232b,#f4f1ea}', 45000, 'designer', '{gym,everyday}', '🧢', 'Classic six-panel.', 406),
  ('nk_sneakers',   'Nike sneakers',      'nike',         'shoes',  null, '{"shoes":{"s":"sneakers"}}',
     '{#f4f1ea,#25232b,#d2342a}', 220000, 'designer', '{everyday,gym}', '👟', 'Cushioned runners.', 408),
  -- Adidas (estimated Nigerian retail; set real prices in admin)
  ('ad_tee',        'Adidas tee',         'adidas',       'top',    null, '{"top":{"s":"tee","f":"plain"}}',
     '{#2346a8,#f4f1ea,#25232b}', 50000, 'designer', '{everyday,gym}', '👕', 'Three-stripe tee.', 500),
  ('ad_tracksuit',  'Adidas tracksuit',   'adidas',       'outfit', null, '{"top":{"s":"hoodie","f":"plain"},"bottom":{"s":"joggers","f":"plain"}}',
     '{#2346a8,#25232b,#1f8a55}', 200000, 'designer', '{gym,everyday}', '🏃🏾', 'Full zip-up and pants set.', 502),
  ('ad_sneakers',   'Adidas sneakers',    'adidas',       'shoes',  null, '{"shoes":{"s":"sneakers"}}',
     '{#f4f1ea,#25232b}', 180000, 'designer', '{everyday,gym}', '👟', 'Court classics.', 504),
  ('ad_cap',        'Adidas cap',         'adidas',       'hat_hair', null, '{"hat":"cap"}',
     '{#2346a8,#25232b,#f4f1ea}', 40000, 'designer', '{gym}', '🧢', 'Lightweight training cap.', 506),
  ('ad_kit',        'Adidas sports kit',  'adidas',       'outfit', null, '{"top":{"s":"tee","f":"plain"},"bottom":{"s":"shorts","f":"plain"},"shoes":{"s":"sneakers","c":"#f4f1ea"}}',
     '{#2346a8,#1f8a55,#d2342a}', 95000, 'designer', '{gym}', '⚽', 'Jersey, shorts and trainers for the pitch.', 508)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 4. Helpers (not callable by players)
-- ---------------------------------------------------------------------
-- One item's patch with the chosen colour filled in. Mirrors itemPatch() in src/lib/outfit.ts.
create or replace function public.bl_wardrobe_item_patch(p_category text, p_patch jsonb, p_colour text) returns jsonb
language plpgsql immutable set search_path = public as $$
declare p jsonb := coalesce(p_patch, '{}'::jsonb);
begin
  if p_colour is null then return p; end if;
  if p_category in ('top', 'outfit') and jsonb_typeof(p->'top') = 'object' then
    p := jsonb_set(p, '{top,c}', to_jsonb(p_colour));
  end if;
  if p_category = 'bottom' and jsonb_typeof(p->'bottom') = 'object' then
    p := jsonb_set(p, '{bottom,c}', to_jsonb(p_colour));
  end if;
  if p_category = 'outfit' and jsonb_typeof(p->'bottom') = 'object' and not (p->'bottom' ? 'c') then
    p := jsonb_set(p, '{bottom,c}', to_jsonb(p_colour));
  end if;
  if p_category = 'shoes' and jsonb_typeof(p->'shoes') = 'object' then
    p := jsonb_set(p, '{shoes,c}', to_jsonb(p_colour));
  end if;
  if p_category in ('bag', 'hat_hair') then
    p := p || jsonb_build_object('accent', p_colour);
  end if;
  return p;
end $$;

-- A whole avatar patch over a look: garments merge key by key, bag accessories replace bag accessories.
create or replace function public.bl_wardrobe_apply(p_avatar jsonb, p_patch jsonb) returns jsonb
language plpgsql immutable set search_path = public as $$
declare a jsonb := coalesce(p_avatar, '{}'::jsonb); p jsonb := coalesce(p_patch, '{}'::jsonb); k text;
begin
  foreach k in array array['top', 'bottom', 'shoes'] loop
    if jsonb_typeof(p->k) = 'object' then
      a := a || jsonb_build_object(k, (case when jsonb_typeof(a->k) = 'object' then a->k else '{}'::jsonb end) || (p->k));
    end if;
    p := p - k;
  end loop;
  if jsonb_typeof(p->'accessories') = 'array' then
    a := a || jsonb_build_object('accessories',
      coalesce((select jsonb_agg(x) from jsonb_array_elements_text(
                  case when jsonb_typeof(a->'accessories') = 'array' then a->'accessories' else '[]'::jsonb end) x
                where x not in ('bag', 'backpack')), '[]'::jsonb) || (p->'accessories'));
    p := p - 'accessories';
  end if;
  return (a || p) - 'preset' || jsonb_build_object('preset', null);
end $$;

create or replace function public.bl_wardrobe_on() returns void
language plpgsql stable set search_path = public as $$
begin
  if not coalesce(bl_cfg_bool('wardrobe.enabled'), true) then
    raise exception 'The boutique is closed right now. Try again later.' using errcode = 'P0001', hint = 'wardrobe_off';
  end if;
end $$;

create or replace function public.bl_wardrobe_slot(p_slot text) returns text
language plpgsql immutable set search_path = public as $$
begin
  if p_slot is null or p_slot not in ('everyday', 'home', 'sleep', 'date', 'party', 'work', 'gym') then
    raise exception 'That outfit slot doesn''t exist.' using errcode = 'P0001', hint = 'bad_slot';
  end if;
  return p_slot;
end $$;

-- ---------------------------------------------------------------------
-- 5. RPCs
-- ---------------------------------------------------------------------
-- Everything the boutique needs: brands, items (active + any the caller owns), ownership, the 7 slots, money.
create or replace function public.wardrobe_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me();
begin
  return jsonb_build_object(
    'enabled', coalesce(bl_cfg_bool('wardrobe.enabled'), true),
    'brands_enabled', coalesce(bl_cfg_bool('wardrobe.brands_enabled'), true),
    'cash', v_me.cash, 'bank', v_me.bank, 'gender', v_me.gender,
    'brands', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'tagline', b.tagline, 'colour', b.colour,
                                  'is_house', b.is_house, 'sponsor', b.sponsor) order by b.sort, b.id)
                        from wardrobe_brands b where b.active), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', i.id, 'name', i.name, 'brand_id', case when b.active then i.brand_id end, 'category', i.category,
                 'gender', i.gender, 'patch', i.patch, 'colours', to_jsonb(i.colours), 'price', i.price, 'tag', i.tag,
                 'default_slots', to_jsonb(i.default_slots), 'icon', i.icon, 'description', i.description,
                 'owned', w.item_id is not null, 'owned_colour', w.colour) order by i.sort, i.id)
               from wardrobe_items i
               left join wardrobe_brands b on b.id = i.brand_id
               left join player_wardrobe w on w.item_id = i.id and w.user_id = v_me.id
               where (i.active or w.item_id is not null) and (i.gender is null or i.gender = v_me.gender::text)), '[]'::jsonb),
    'outfits', coalesce((select jsonb_object_agg(o.slot, jsonb_build_object('items', o.items, 'patch', o.patch))
                         from player_outfits o where o.user_id = v_me.id), '{}'::jsonb));
end $$;

-- Buy one item (all its colours become yours). Bank first, then cash. Once per item.
create or replace function public.wardrobe_buy(p_item text, p_colour text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  it     wardrobe_items;
  v_bank bigint;
  v_cash bigint;
  v_meta jsonb;
begin
  perform bl_wardrobe_on();
  select * into it from wardrobe_items where id = p_item and active for update;
  if not found then
    raise exception 'That item isn''t in the boutique.' using errcode = 'P0001', hint = 'unknown_item';
  end if;
  if it.gender is not null and it.gender <> v_me.gender::text then
    raise exception '% isn''t made for your Sim.', it.name using errcode = 'P0001', hint = 'wrong_gender';
  end if;
  if p_colour is not null and cardinality(it.colours) > 0 and not (lower(p_colour) = any (select lower(c) from unnest(it.colours) c)) then
    raise exception '% doesn''t come in that colour.', it.name using errcode = 'P0001', hint = 'bad_colour';
  end if;
  if exists (select 1 from player_wardrobe where user_id = v_me.id and item_id = it.id) then
    raise exception 'You already own the %.', it.name using errcode = 'P0001', hint = 'already_owned';
  end if;
  if it.price > v_me.bank + v_me.cash then
    raise exception 'Not enough money. The % costs % and you have % in total.',
      it.name, bl_naira(it.price), bl_naira(v_me.bank + v_me.cash) using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_bank := least(it.price, v_me.bank);
  v_cash := it.price - v_bank;
  v_meta := jsonb_build_object('item', it.id, 'colour', p_colour, 'price', it.price);
  if v_bank > 0 then perform bl_add_money(v_me.id, 'bank', -v_bank, 'Boutique: ' || it.name, v_meta); end if;
  if v_cash > 0 then perform bl_add_money(v_me.id, 'cash', -v_cash, 'Boutique: ' || it.name, v_meta); end if;
  insert into player_wardrobe (user_id, item_id, colour, price_paid, bought_at)
  values (v_me.id, it.id, lower(coalesce(p_colour, it.colours[1])), it.price, bl_now());
  return jsonb_build_object(
    'message', case when it.price = 0 then it.name || ' added to your wardrobe.'
                    else 'You bought the ' || it.name || ' for ' || bl_naira(it.price) || '. It''s in your wardrobe.' end,
    'item', it.id, 'paid', it.price, 'paid_bank', v_bank, 'paid_cash', v_cash);
end $$;

-- Save a look for a slot. p_items = [{"item": id, "colour": "#hex"}, ...] (one per category; an outfit
-- replaces top + bottom). [] = this slot shows the everyday look as it is. null = use the slot's default rule.
-- Every paid item must be owned; free items (price 0) are always allowed. The everyday slot is also written
-- into profiles.avatar, so portraits, chat and other players see it.
create or replace function public.wardrobe_set_outfit(p_slot text, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_slot  text := bl_wardrobe_slot(p_slot);
  e       jsonb;
  it      wardrobe_items;
  v_col   text;
  v_cats  text[] := '{}';
  v_clean jsonb := '[]'::jsonb;
  v_patch jsonb := '{}'::jsonb;
  v_av    jsonb;
  c       text;
begin
  perform bl_wardrobe_on();
  if p_items is null or jsonb_typeof(p_items) = 'null' then
    if v_slot = 'everyday' then
      raise exception 'Everyday is your main look. Pick pieces for it instead.' using errcode = 'P0001', hint = 'bad_slot';
    end if;
    insert into player_outfits (user_id, slot, items, patch, updated_at) values (v_me.id, v_slot, null, null, bl_now())
    on conflict (user_id, slot) do update set items = null, patch = null, updated_at = excluded.updated_at;
    return jsonb_build_object('message', 'Using the default for ' || v_slot || '.', 'slot', v_slot, 'patch', null);
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 6 then
    raise exception 'That look doesn''t make sense.' using errcode = 'P0001', hint = 'bad_items';
  end if;
  for e in select * from jsonb_array_elements(p_items) loop
    select * into it from wardrobe_items where id = e->>'item';
    if not found then
      raise exception 'That item isn''t in the boutique.' using errcode = 'P0001', hint = 'unknown_item';
    end if;
    if it.gender is not null and it.gender <> v_me.gender::text then
      raise exception '% isn''t made for your Sim.', it.name using errcode = 'P0001', hint = 'wrong_gender';
    end if;
    if it.price > 0 and not exists (select 1 from player_wardrobe where user_id = v_me.id and item_id = it.id) then
      raise exception 'Buy the % first.', it.name using errcode = 'P0001', hint = 'not_owned';
    end if;
    if not it.active and it.price = 0 and not exists (select 1 from player_wardrobe where user_id = v_me.id and item_id = it.id) then
      raise exception 'That item isn''t in the boutique.' using errcode = 'P0001', hint = 'unknown_item';
    end if;
    if it.category = any (v_cats)
       or (it.category = 'outfit' and v_cats && array['top', 'bottom'])
       or (it.category in ('top', 'bottom') and 'outfit' = any (v_cats)) then
      raise exception 'One piece per part of the body, please.' using errcode = 'P0001', hint = 'bad_items';
    end if;
    v_cats := v_cats || it.category;
    v_col := lower(nullif(e->>'colour', ''));
    if cardinality(it.colours) = 0 then v_col := null;
    elsif v_col is null then v_col := lower(it.colours[1]);
    elsif not (v_col = any (select lower(x) from unnest(it.colours) x)) then
      raise exception '% doesn''t come in that colour.', it.name using errcode = 'P0001', hint = 'bad_colour';
    end if;
    v_clean := v_clean || jsonb_build_array(jsonb_build_object('item', it.id, 'colour', v_col));
  end loop;
  -- merge in a fixed category order (same as the client)
  foreach c in array array['outfit', 'top', 'bottom', 'shoes', 'bag', 'hat_hair'] loop
    for e in select x from jsonb_array_elements(v_clean) x loop
      select * into it from wardrobe_items where id = e->>'item';
      if it.category = c then
        v_patch := bl_wardrobe_apply(v_patch, bl_wardrobe_item_patch(it.category, it.patch, e->>'colour')) - 'preset';
      end if;
    end loop;
  end loop;
  insert into player_outfits (user_id, slot, items, patch, updated_at) values (v_me.id, v_slot, v_clean, v_patch, bl_now())
  on conflict (user_id, slot) do update set items = excluded.items, patch = excluded.patch, updated_at = excluded.updated_at;
  if v_slot = 'everyday' and v_patch <> '{}'::jsonb then
    v_av := bl_wardrobe_apply(v_me.avatar, v_patch);
    if length(v_av::text) > 4000 then
      raise exception 'That look is too big to save.' using errcode = 'P0001', hint = 'avatar_too_big';
    end if;
    update profiles set avatar = v_av where id = v_me.id;
  end if;
  return jsonb_build_object('message', 'Saved your ' || case v_slot when 'date' then 'date night' else v_slot end || ' look.',
                            'slot', v_slot, 'items', v_clean, 'patch', v_patch);
end $$;

-- "Keep my everyday look" for a slot: forget the saved look (or default rule).
create or replace function public.wardrobe_clear_slot(p_slot text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); v_slot text := bl_wardrobe_slot(p_slot);
begin
  perform bl_wardrobe_on();
  delete from player_outfits where user_id = v_me.id and slot = v_slot;
  return jsonb_build_object('message', case when v_slot = 'everyday' then 'Everyday look kept as it is.'
                                            else 'Your Sim keeps the everyday look for ' || case v_slot when 'date' then 'date night' else v_slot end || '.' end,
                            'slot', v_slot);
end $$;

-- ---------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------
revoke execute on function public.bl_wardrobe_item_patch(text, jsonb, text) from public, anon, authenticated;
revoke execute on function public.bl_wardrobe_apply(jsonb, jsonb)           from public, anon, authenticated;
revoke execute on function public.bl_wardrobe_on()                          from public, anon, authenticated;
revoke execute on function public.bl_wardrobe_slot(text)                    from public, anon, authenticated;
revoke execute on function public.wardrobe_state()                          from public, anon;
revoke execute on function public.wardrobe_buy(text, text)                  from public, anon;
revoke execute on function public.wardrobe_set_outfit(text, jsonb)          from public, anon;
revoke execute on function public.wardrobe_clear_slot(text)                 from public, anon;
grant execute on function public.wardrobe_state()                 to authenticated;
grant execute on function public.wardrobe_buy(text, text)         to authenticated;
grant execute on function public.wardrobe_set_outfit(text, jsonb) to authenticated;
grant execute on function public.wardrobe_clear_slot(text)        to authenticated;

-- ---------------------------------------------------------------------
-- 7. Admin: Content -> Wardrobe brands / Wardrobe items (same whitelist as 20261009000300_daily.sql + 2 tables)
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
              "location_ids":"arr","risky":"bool","rush":"obj","icon":"text_null","requires_event":"text_null"}}'
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
    when 'hype_templates' then '{"pk":["id"],"insert":true,"order":"kind, sort, id",
      "cols":{"kind":"text","line":"text","ticker":"text","sort":"int","active":"bool"}}'
    when 'place_events' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"location_id":"text","title":"text","description":"text","kind":"text","icon":"text","recurrence":"text",
              "weekday":"int_null","start_time":"num_null","end_time":"num_null","starts_at":"ts_null","ends_at":"ts_null",
              "ticket_price":"money","capacity":"int_null","perks":"obj","variants":"text","sort":"int","active":"bool"}}'
    when 'topup_packs' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"label":"text","game_naira":"money","price_kobo":"money","bonus_tag":"text_null","sort":"int","active":"bool"}}'
    when 'daily_reward_steps' then '{"pk":["day"],"insert":false,"order":"day",
      "cols":{"cash":"money","item_id":"text_null","label":"text"}}'
    when 'gem_finds' then '{"pk":["user_id","hunt_date","location_id"],"insert":false,"order":"hunt_date desc, found_at desc",
      "cols":{}}'
    when 'wardrobe_brands' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","tagline":"text","colour":"text","is_house":"bool","sponsor":"bool","sort":"int","active":"bool"}}'
    when 'wardrobe_items' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","brand_id":"text_null","category":"text","gender":"text_null","patch":"obj","colours":"arr",
              "price":"money","tag":"text","default_slots":"arr","icon":"text","description":"text","sort":"int","active":"bool"}}'
  end::jsonb;
$function$;
revoke execute on function public.bl_admin_table_spec(text) from public, anon, authenticated;
