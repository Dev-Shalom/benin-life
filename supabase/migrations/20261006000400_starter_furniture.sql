<<<<<<< HEAD
-- Starter homes by origin (2026-10-06): furniture is data.
--
-- * furniture        catalog of pieces (admin-editable): what each provides (sleep/bath/cook/tv/radio/...),
--                    the activity label it gives ("Bucket bath") and a small effect percent (bed 110 %).
-- * start_homes.furniture  {"lapo": [ids], "nepo": [ids]} = what a Sim of that origin moves in with.
-- * start_homes.fixtures   pieces that come with the house itself (shower, bathtub, hall bunk).
-- * origin.<tier>.furniture (config, comma-separated) = fallback when a home has no list for the tier.
-- * profiles.furniture     the Sim's own pieces (null = never assigned; only possible before move-in).
-- * activities.requires / requires_note: the capability a home activity needs, and the reason shown.
--
-- Existing Sims: nobody can buy furniture yet (Buy mode is "coming soon"), so every existing Sim still has
-- the old default room. Each one with furniture IS NULL gets the starter set for its origin and home, once.
-- Sleeping on the LAPO foam mattress is the old baseline (100 %), so no existing player loses anything.
--
-- Idempotent: tables/columns "if not exists", seeds "on conflict do nothing", data updates only fill
-- empty/null values. Safe to re-run; never overwrites admin edits.

-- ---------------------------------------------------------------------
-- 1. Tables and columns
-- ---------------------------------------------------------------------
create table if not exists public.furniture (
  id           text primary key check (id ~ '^[a-z0-9_]{2,32}$'),
  name         text not null,
  emoji        text not null default '',
  kind         text not null default '',                -- 3D look hint (client model.ts kinds)
  provides     text[] not null default '{}',            -- capabilities: sleep, bath, cook, tv, radio, seat, water, cold
  activity_pct jsonb not null default '{}'::jsonb check (jsonb_typeof(activity_pct) = 'object'),
                                                       -- {"sleep": 110} = 110 % of that activity's good effects
  labels       jsonb not null default '{}'::jsonb check (jsonb_typeof(labels) = 'object'),
                                                       -- {"bathe": "Bucket bath"} = the activity's name with this piece
  rank         int not null default 0,                  -- the best piece (highest rank) is used
  description  text not null default '',
  sort         int not null default 0,
  active       boolean not null default true
);

alter table public.furniture enable row level security;
revoke all on table public.furniture from anon, authenticated;
grant select on public.furniture to anon, authenticated;
drop policy if exists furniture_read on public.furniture;
create policy furniture_read on public.furniture for select to anon, authenticated using (true);

alter table public.start_homes add column if not exists furniture jsonb not null default '{}'::jsonb;
alter table public.start_homes add column if not exists fixtures text[] not null default '{}';
alter table public.profiles    add column if not exists furniture text[];
alter table public.activities  add column if not exists requires text;
alter table public.activities  add column if not exists requires_note text not null default '';

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'start_homes_furniture_obj') then
    alter table public.start_homes add constraint start_homes_furniture_obj check (jsonb_typeof(furniture) = 'object');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Catalog seed (admin edits the rows afterwards; re-runs never overwrite them)
-- ---------------------------------------------------------------------
insert into public.furniture (id, name, emoji, kind, provides, activity_pct, labels, rank, description, sort) values
('water_drum', 'Water drum', '🛢️', 'drum', '{water}', '{}', '{}', 0,
 'A blue drum you fill when the water comes. Every compound needs one.', 10),
('bucket', 'Bucket and bowl', '🪣', 'bucket', '{bath}', '{}', '{"bathe": "Bucket bath"}', 10,
 'Fetch water from the drum, take it to the bathroom, scoop and pour.', 20),
('stool', 'Small stool', '🪑', 'stool', '{seat}', '{}', '{}', 0,
 'A low wooden stool. Good for cooking, gisting and sitting outside.', 30),
('kerosene_stove', 'Kerosene stove', '🔥', 'kerosene_stove', '{cook}', '{}',
 '{"cook_home": "Cook rice and stew on the kerosene stove"}', 10, 'Smoky, slow and reliable. Buy kerosene by the bottle.', 40),
('single_burner', 'Single gas burner', '🔥', 'hotplate', '{cook}', '{}',
 '{"cook_home": "Cook rice and stew on the single burner"}', 12, 'One ring, a small cylinder, one pot at a time.', 45),
('gas_cooker', 'Gas cooker', '🍳', 'cooktop', '{cook}', '{}',
 '{"cook_home": "Cook rice and stew on the gas cooker"}', 20, 'Proper burners and a full cylinder.', 50),
('sleeping_mat', 'Sleeping mat', '🧺', 'mat', '{sleep}', '{"sleep": 95, "nap": 95}',
 '{"sleep": "Sleep on the mat", "nap": "Nap on the mat"}', 5, 'A woven mat on the floor. Your back will feel it.', 60),
('foam_mattress', 'Thin foam mattress', '🛏️', 'mattress', '{sleep}', '{"sleep": 100, "nap": 100}',
 '{"sleep": "Sleep on the foam", "nap": "Nap on the foam"}', 10, 'A thin Vitafoam on the floor. It does the job.', 65),
('bed', 'Bed', '🛏️', 'bed_double', '{sleep}', '{"sleep": 110, "nap": 110}',
 '{"sleep": "Sleep in your bed", "nap": "Nap in your bed"}', 20, 'A proper bed frame with a thick mattress.', 70),
('king_bed', 'King-size bed', '🛏️', 'bed_king', '{sleep}', '{"sleep": 115, "nap": 115}',
 '{"sleep": "Sleep in your king-size bed", "nap": "Nap in your king-size bed"}', 30, 'Big, soft and quiet.', 75),
('sofa', 'Sofa', '🛋️', 'sofa', '{seat}', '{}', '{}', 10, 'A three-seater for the parlour.', 80),
('l_sofa', 'L-shaped sofa', '🛋️', 'sofa_l', '{seat}', '{}', '{}', 20, 'The big corner sofa.', 85),
('armchair', 'Armchair', '💺', 'armchair', '{seat}', '{}', '{}', 5, 'One soft chair.', 90),
('plastic_chair', 'Plastic chair', '🪑', 'plastic_chair', '{seat}', '{}', '{}', 2, 'The white plastic chair every house has.', 95),
('tv', 'Television', '📺', 'tv', '{tv}', '{}', '{}', 10, 'A flat screen on a small stand.', 100),
('big_tv', 'Big TV', '📺', 'tv_big', '{tv}', '{}', '{}', 20, 'A big flat screen with speakers.', 105),
('radio', 'Radio', '📻', 'radio', '{radio}', '{}', '{}', 10, 'Small radio for news, music and football.', 110),
('fridge', 'Fridge', '🧊', 'fridge', '{cold}', '{}', '{}', 10, 'Cold water and leftover stew.', 120),
('wardrobe', 'Wardrobe', '🚪', 'wardrobe', '{}', '{}', '{}', 0, 'Two doors and a mirror.', 130),
('standing_fan', 'Standing fan', '🌀', 'fan', '{}', '{}', '{}', 0, 'For when NEPA takes light.', 140),
('centre_table', 'Centre table', '🪵', 'centre_table', '{}', '{}', '{}', 0, 'For the remote and the chin-chin.', 150),
('rug', 'Rug', '🟥', 'rug', '{}', '{}', '{}', 0, 'Brightens the floor.', 160),
('dining_set', 'Dining set', '🍽️', 'dining', '{}', '{}', '{}', 0, 'Table and chairs for the family.', 170),
('hostel_bunk', 'Hall bunk bed', '🛏️', 'bunk', '{sleep}', '{"sleep": 100, "nap": 100}',
 '{"sleep": "Sleep on your bunk", "nap": "Nap on your bunk"}', 8, 'Comes with the hostel space.', 300),
('shower', 'Shower', '🚿', 'shower', '{bath}', '{}', '{"bathe": "Take a shower"}', 20, 'Comes with the house.', 310),
('bathtub', 'Bathtub', '🛁', 'bathtub', '{bath}', '{}', '{"bathe": "Soak in the bathtub"}', 30, 'Comes with the house.', 320)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 3. Starter sets per home and origin (only filled while still empty) + fixtures
-- ---------------------------------------------------------------------
update public.start_homes set furniture = v.f::jsonb
  from (values
    ('uniben_hostel',
     '{"lapo": ["water_drum","bucket","stool","single_burner"],
       "nepo": ["water_drum","bucket","plastic_chair","single_burner","standing_fan","radio"]}'),
    ('ekenwan_face_me',
     '{"lapo": ["water_drum","bucket","stool","kerosene_stove","foam_mattress"],
       "nepo": ["water_drum","bucket","bed","sofa","tv","fridge","gas_cooker","wardrobe","standing_fan","rug"]}'),
    ('aduwawa_face_me',
     '{"lapo": ["water_drum","bucket","stool","kerosene_stove","foam_mattress"],
       "nepo": ["water_drum","bucket","bed","sofa","tv","fridge","gas_cooker","wardrobe","standing_fan","rug"]}'),
    ('uselu_self_contain',
     '{"lapo": ["water_drum","bucket","stool","kerosene_stove","foam_mattress"],
       "nepo": ["bed","sofa","tv","fridge","gas_cooker","wardrobe","standing_fan","centre_table"]}'),
    ('mission_rd_mini_flat',
     '{"lapo": ["water_drum","bucket","stool","kerosene_stove","foam_mattress"],
       "nepo": ["bed","sofa","tv","fridge","gas_cooker","wardrobe","centre_table","rug"]}'),
    ('gra_duplex',
     '{"lapo": ["water_drum","bucket","stool","kerosene_stove","foam_mattress"],
       "nepo": ["bed","sofa","tv","fridge","gas_cooker","wardrobe","centre_table","rug"]}')
  ) as v(id, f)
 where start_homes.id = v.id and start_homes.furniture = '{}'::jsonb;

update public.start_homes set fixtures = v.f::text[]
  from (values ('uniben_hostel', '{hostel_bunk}'), ('uselu_self_contain', '{shower}'),
               ('mission_rd_mini_flat', '{shower}'), ('gra_duplex', '{bathtub}')) as v(id, f)
 where start_homes.id = v.id and start_homes.fixtures = '{}';

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('origin.lapo.furniture', '"water_drum,bucket,stool,kerosene_stove,foam_mattress"', 'origin', 'LAPO baby: starter furniture (fallback)',
 'Comma-separated furniture ids a LAPO baby moves in with when the home has no LAPO list (Content → Homes → Starter furniture).', 'text', null, null),
('origin.nepo.furniture', '"water_drum,bucket,bed,sofa,tv,fridge,gas_cooker,wardrobe,centre_table,rug"', 'origin', 'Nepo baby: starter furniture (fallback)',
 'Comma-separated furniture ids a Nepo baby moves in with when the home has no Nepo list (Content → Homes → Starter furniture).', 'text', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 4. Home activities: what they need (only filled while unset)
-- ---------------------------------------------------------------------
update public.activities a set requires = v.req, requires_note = v.note
  from (values
    ('sleep', 'sleep', 'You need something to sleep on: a mat, a foam mattress or a bed.'),
    ('nap', 'sleep', 'You need something to sleep on: a mat, a foam mattress or a bed.'),
    ('bathe', 'bath', 'You need a bucket (or a shower) to bathe.'),
    ('cook_home', 'cook', 'You need a stove to cook: a kerosene stove, a burner or a gas cooker.'),
    ('watch_tv', 'tv', 'You don''t have a TV yet.'),
    ('listen_radio', 'radio', 'You don''t have a radio yet.')
  ) as v(id, req, note)
 where a.id = v.id and a.requires is null;

-- TV and radio are now gated by the piece itself, so offer them in every home scene.
update public.activities set scenes = scenes || array['home_face_me']
 where id = 'watch_tv' and not ('home_face_me' = any (scenes));
update public.activities set scenes = scenes || array['home_flat']
 where id = 'listen_radio' and not ('home_flat' = any (scenes));
update public.activities set scenes = scenes || array['home_duplex']
 where id = 'listen_radio' and not ('home_duplex' = any (scenes));

-- ---------------------------------------------------------------------
-- 5. Helpers
-- ---------------------------------------------------------------------
-- The start_homes row for a Sim: its start home, else the first home with its housing.
create or replace function public.bl_home_row(p_start_home text, p_housing text) returns public.start_homes
language sql stable set search_path = public as $$
  select h.* from start_homes h
   where h.id = p_start_home or h.housing_id = p_housing
   order by (h.id = p_start_home) desc, h.sort, h.id
   limit 1;
$$;

-- Starter furniture for a home + origin: the home's list for the tier, else origin.<tier>.furniture.
-- Unknown or inactive ids are dropped (a typo never blocks a move-in).
create or replace function public.bl_starter_furniture(p_start_home text, p_housing text, p_tier text) returns text[]
language plpgsql stable set search_path = public as $$
declare
  h     start_homes := bl_home_row(p_start_home, p_housing);
  v_ids text[];
begin
  if h.id is not null and jsonb_typeof(h.furniture -> p_tier) = 'array' then
    select array_agg(e) into v_ids from jsonb_array_elements_text(h.furniture -> p_tier) e;
  else
    select array_agg(btrim(x)) into v_ids
      from unnest(string_to_array(coalesce((select value #>> '{}' from game_config
                                             where key = 'origin.' || p_tier || '.furniture'), ''), ',')) x
     where btrim(x) <> '';
  end if;
  return coalesce((select array_agg(f.id order by f.sort, f.id) from furniture f
                    where f.active and f.id = any (coalesce(v_ids, '{}'))), '{}');
end $$;

-- Fixtures of the house the Sim lives in now.
create or replace function public.bl_home_fixtures(p_me public.profiles) returns text[]
language sql stable set search_path = public as $$
  select coalesce((select h.fixtures from start_homes h where h.housing_id = p_me.housing_id
                    order by (h.id = p_me.start_home) desc, h.sort, h.id limit 1), '{}');
$$;

-- For each home activity: can the Sim do it with its furniture, under which name, at what percent.
-- {"<activity id>": {"ok", "label", "via", "pct", "reason", "requires"}}
-- A Sim with furniture IS NULL (never assigned) is not gated (the old behaviour).
create or replace function public.bl_home_activities(p_me public.profiles) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_have text[] := coalesce(p_me.furniture, '{}') || bl_home_fixtures(p_me);
  v_out  jsonb := '{}'::jsonb;
  a      record;
  f      furniture;
begin
  for a in select * from activities where home_only order by sort, id loop
    f := null;
    if a.requires is not null and a.requires <> '' then
      select * into f from furniture x
       where x.active and x.id = any (v_have) and a.requires = any (x.provides)
       order by x.rank desc, x.sort, x.id limit 1;
    end if;
    v_out := v_out || jsonb_build_object(a.id, jsonb_build_object(
      'requires', a.requires,
      'ok', a.requires is null or a.requires = '' or p_me.furniture is null or f.id is not null,
      'via', f.id,
      'label', coalesce(nullif(f.labels ->> a.id, ''), a.name),
      'pct', coalesce((f.activity_pct ->> a.id)::numeric, 100),
      'reason', case when a.requires is null or a.requires = '' or p_me.furniture is null or f.id is not null then null
                     else coalesce(nullif(a.requires_note, ''), 'You don''t have the furniture for this yet.') end));
  end loop;
  return v_out;
end $$;

-- get_my_state().home: the Sim's pieces, the house fixtures and the home activities.
create or replace function public.bl_home_info(p_me public.profiles) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'furniture', to_jsonb(p_me.furniture),
    'fixtures', to_jsonb(bl_home_fixtures(p_me)),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'emoji', f.emoji, 'kind', f.kind,
                                                           'provides', to_jsonb(f.provides),
                                                           'fixture', not (f.id = any (coalesce(p_me.furniture, '{}'))))
                                        order by f.sort, f.id)
                         from furniture f
                        where f.active and f.id = any (coalesce(p_me.furniture, '{}') || bl_home_fixtures(p_me))), '[]'::jsonb),
    'activities', bl_home_activities(p_me));
$$;

-- Good effects scaled by a percent (gains of hunger/energy/hygiene/fun/social/health/bladder, stress relief).
create or replace function public.bl_effects_pct(p_eff jsonb, p_pct numeric) returns jsonb
language sql immutable set search_path = public as $$
  select coalesce(p_eff, '{}'::jsonb) || coalesce((
    select jsonb_object_agg(k, round((p_eff ->> k)::numeric * p_pct / 100.0, 1))
      from jsonb_object_keys(coalesce(p_eff, '{}'::jsonb)) k
     where jsonb_typeof(p_eff -> k) = 'number'
       and ((k = 'stress' and (p_eff ->> k)::numeric < 0)
            or (k in ('hunger','energy','hygiene','fun','social','health','bladder') and (p_eff ->> k)::numeric > 0))),
    '{}'::jsonb);
$$;

-- Move-in: a Sim that has a home but no furniture list yet gets the starter set (new profiles via
-- create_profile, choose_start_home). Never touches a Sim that already has a list.
create or replace function public.bl_profile_furniture_trigger() returns trigger
language plpgsql set search_path = public as $$
begin
  new.furniture := bl_starter_furniture(new.start_home, new.housing_id, new.origin);
  return new;
end $$;

drop trigger if exists profiles_starter_furniture on public.profiles;
create trigger profiles_starter_furniture
  before insert or update on public.profiles
  for each row when (new.home_chosen and new.furniture is null)
  execute function public.bl_profile_furniture_trigger();

-- Furniture ids in start_homes must exist (admin edits).
create or replace function public.bl_start_homes_furniture_check() returns trigger
language plpgsql set search_path = public as $$
declare v_bad text; v_tier text;
begin
  for v_tier in select jsonb_object_keys(new.furniture) loop
    if jsonb_typeof(new.furniture -> v_tier) <> 'array' then
      raise exception 'Starter furniture for "%" must be a list, e.g. {"lapo": ["bucket", "stool"]}.', v_tier
        using errcode = 'P0001', hint = 'bad_value';
    end if;
    if not exists (select 1 from origin_tiers where id = v_tier) then
      raise exception 'Unknown origin in starter furniture: %', v_tier using errcode = 'P0001', hint = 'bad_value';
    end if;
  end loop;
  select string_agg(distinct e, ', ') into v_bad
    from (select jsonb_array_elements_text(new.furniture -> k) e from jsonb_object_keys(new.furniture) k
           where jsonb_typeof(new.furniture -> k) = 'array'
          union all select unnest(new.fixtures)) x
   where not exists (select 1 from furniture f where f.id = x.e);
  if v_bad is not null then
    raise exception 'Unknown furniture id(s): %', v_bad using errcode = 'P0001', hint = 'bad_value';
  end if;
  return new;
end $$;

drop trigger if exists start_homes_furniture_check on public.start_homes;
create trigger start_homes_furniture_check
  before insert or update of furniture, fixtures on public.start_homes
  for each row execute function public.bl_start_homes_furniture_check();

-- ---------------------------------------------------------------------
-- 6. Existing Sims (once): the starter set for their origin + home, only while they have none
-- ---------------------------------------------------------------------
update public.profiles p
   set furniture = public.bl_starter_furniture(p.start_home, p.housing_id, p.origin)
 where p.furniture is null and p.home_chosen;

-- ---------------------------------------------------------------------
-- 7. do_activity: furniture gate, label and percent (otherwise the same as L1)
=======
-- Starter homes by origin: what furniture each player owns at home, data-driven per origin and per
-- start home (docs/HUD_HOME.md "Furniture sets").
--   * furniture          catalog of pieces: 3D kind, default slot, the home activities the piece enables,
--                        rest_pct (how well you sleep on it), admin-editable.
--   * starter_furniture  origin (+ optional start home) -> pieces. A start-home row replaces the
--                        origin-wide row for the same slot.
--   * player_furniture   what a player owns (starter, bought later, admin). Never removed here.
--   * activities.needs_furniture: the activity is offered at home only when the player owns a piece
--                        that lists it (TV, sofa, fridge, stool...). Basic needs (sleep, bath, toilet,
--                        cook) stay possible anywhere at home; the furniture decides where and how well.
-- Starter pieces are given when a home is chosen (trigger, so create_profile / choose_start_home stay
-- untouched) and backfilled once for existing players (additive, nothing is removed).
-- Safe on a non-empty hosted DB and idempotent.

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
do $$
begin
  -- first apply? (seeds that admins may edit later run only once)
  perform set_config('bl.furniture_first',
    case when to_regclass('public.furniture') is null then 'on' else 'off' end, false);
end $$;

create table if not exists public.furniture (
  id          text primary key,
  name        text not null,
  emoji       text not null default '🪑',
  kind        text not null,                    -- 3D kind (src/art/home3d/model.ts KINDS)
  slot        text not null,                    -- default slot in the home layout
  activities  text[] not null default '{}',     -- home activities this piece enables / hosts
  rest_pct    int  not null default 100 check (rest_pct between 0 and 200),
  color       text,
  description text not null default '',
  sort        int  not null default 0,
  active      boolean not null default true
);

create table if not exists public.starter_furniture (
  id           text primary key,
  origin       text not null references public.origin_tiers(id),
  start_home   text references public.start_homes(id),   -- null = every home of that origin
  furniture_id text not null references public.furniture(id),
  slot         text,                                      -- null = the piece's default slot
  sort         int  not null default 0,
  active       boolean not null default true
);

create table if not exists public.player_furniture (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  furniture_id text not null references public.furniture(id) on delete cascade,
  slot         text,
  source       text not null default 'starter',
  created_at   timestamptz not null default now(),
  primary key (user_id, furniture_id)
);

alter table public.activities add column if not exists needs_furniture boolean not null default false;

alter table public.furniture         enable row level security;
alter table public.starter_furniture enable row level security;
alter table public.player_furniture  enable row level security;
drop policy if exists furniture_read on public.furniture;
create policy furniture_read on public.furniture for select to anon, authenticated using (true);
drop policy if exists starter_furniture_read on public.starter_furniture;
create policy starter_furniture_read on public.starter_furniture for select to anon, authenticated using (true);
drop policy if exists player_furniture_own on public.player_furniture;
create policy player_furniture_own on public.player_furniture for select to authenticated
  using (user_id = (select auth.uid()));
revoke all on public.furniture, public.starter_furniture, public.player_furniture from anon, authenticated;
grant select on public.furniture, public.starter_furniture to anon, authenticated;
grant select on public.player_furniture to authenticated;

-- ---------------------------------------------------------------------
-- 2. Seeds (on conflict do nothing: admin edits survive)
-- ---------------------------------------------------------------------
insert into public.furniture (id, name, emoji, kind, slot, activities, rest_pct, color, description, sort) values
-- LAPO trench basics
('drum_bucket', 'Water drum and bucket', '🪣', 'drum_bucket', 'bath', '{bathe}', 100, null,
 'A blue drum of water and a bucket with a small bowl. Bucket bath, every day.', 10),
('stool', 'Small stool', '🪑', 'stool', 'seat', '{sit_rest}', 100, null, 'One small wooden stool.', 20),
('kerosene_stove', 'Kerosene stove', '🔥', 'kerosene_stove', 'stove', '{cook_home}', 100, null,
 'A small kerosene stove on a wooden stand. It cooks, slowly.', 30),
('foam_mat', 'Thin foam mattress', '🛏️', 'mattress', 'bed', '{sleep,nap}', 90, null,
 'A thin foam on the floor. You sleep, but not like on a real bed.', 40),
-- Nepo: moderate, decent
('bed_double', 'Proper bed', '🛏️', 'bed_double', 'bed', '{sleep,nap}', 100, '#5b3fa0', 'A double bed with a good mattress.', 50),
('bed_single', 'Proper single bed', '🛏️', 'bed_single', 'bed', '{sleep,nap}', 100, '#2f6fb3', 'A single bed with a good mattress.', 51),
('sofa', 'Sofa', '🛋️', 'sofa', 'sofa', '{relax_sofa}', 100, '#7a1f2b', 'A comfortable three-seater.', 60),
('tv', 'Flat-screen TV', '📺', 'tv', 'tv', '{watch_tv}', 100, null, 'A 43-inch TV on a stand.', 70),
('fridge', 'Fridge', '🧊', 'fridge', 'fridge', '{cold_drink}', 100, null, 'A fridge with cold drinks inside.', 80),
('gas_cooker', 'Gas cooker', '🍳', 'gas_cooker', 'stove', '{cook_home}', 100, null, 'A standing gas cooker with an oven and a cylinder.', 90),
('wardrobe', 'Wardrobe', '👔', 'wardrobe', 'wardrobe', '{}', 100, '#8a5a33', 'Space for your clothes. Tap it to change your look.', 100),
('rug', 'Rug', '🟥', 'rug', 'rug', '{}', 100, '#b3332c', 'A soft rug for the parlour.', 110),
('centre_table', 'Centre table', '🪵', 'centre_table', 'ctable', '{}', 100, null, 'A small table in front of the sofa.', 120)
on conflict (id) do nothing;

insert into public.starter_furniture (id, origin, start_home, furniture_id, slot, sort) values
('lapo_bath',  'lapo', null, 'drum_bucket',    null, 10),
('lapo_seat',  'lapo', null, 'stool',          null, 20),
('lapo_stove', 'lapo', null, 'kerosene_stove', null, 30),
('lapo_bed',   'lapo', null, 'foam_mat',       null, 40),
('nepo_bed',   'nepo', null, 'bed_double',     null, 10),
('nepo_sofa',  'nepo', null, 'sofa',           null, 20),
('nepo_tv',    'nepo', null, 'tv',             null, 30),
('nepo_fridge','nepo', null, 'fridge',         null, 40),
('nepo_stove', 'nepo', null, 'gas_cooker',     null, 50),
('nepo_wardrobe', 'nepo', null, 'wardrobe',    null, 60),
('nepo_rug',   'nepo', null, 'rug',            null, 70),
('nepo_ctable','nepo', null, 'centre_table',   null, 80)
on conflict (id) do nothing;
-- the hostel room only fits a single bed
insert into public.starter_furniture (id, origin, start_home, furniture_id, slot, sort)
select 'nepo_hostel_bed', 'nepo', 'uniben_hostel', 'bed_single', 'bed', 11
 where exists (select 1 from public.start_homes where id = 'uniben_hostel')
on conflict (id) do nothing;

-- New home activities for the new pieces (needs_furniture: only with the piece).
insert into public.activities (id, name, scenes, home_only, cost, game_minutes, effects, night_only, sort,
                               max_seconds, min_seconds, scale_by_need, needs_furniture) values
('sit_rest', 'Sit and rest', '{home_face_me,home_flat,home_duplex}', true, 0, 15,
 '{"energy": 5, "stress": -3}', false, 47, 4, 2, true, true),
('relax_sofa', 'Relax on the sofa', '{home_face_me,home_flat,home_duplex}', true, 0, 30,
 '{"energy": 8, "fun": 8, "stress": -6}', false, 48, 6, 3, true, true),
('cold_drink', 'Cold drink from the fridge', '{home_face_me,home_flat,home_duplex}', true, 300, 5,
 '{"hunger": 6, "fun": 5, "bladder": -8}', false, 49, 3, 2, false, true)
on conflict (id) do nothing;

do $$
begin
  if current_setting('bl.furniture_first', true) = 'on' then
    -- TV/radio need the piece; a Nepo in a face-me room has a TV too.
    update public.activities set needs_furniture = true where id in ('watch_tv', 'listen_radio');
    update public.activities set scenes = scenes || '{home_face_me}'::text[]
     where id = 'watch_tv' and not ('home_face_me' = any (scenes));
  end if;
end $$;

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('home.walk_max_share_pct', '15', 'action', 'Walk to furniture (max % of the action)',
 'In the 3D home the Sim walks to the furniture only when the walk takes at most this % of the action; otherwise it is there at once, so short actions start immediately. 0 = never walk.',
 'number', 0, 100)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------
-- The starter pieces for an origin + start home (start_home null: found from the housing id).
create or replace function public.bl_starter_furniture(p_origin text, p_start_home text, p_housing text)
returns table (furniture_id text, slot text)
language sql stable set search_path = public as $$
  with home as (
    select coalesce(p_start_home,
                    (select h.id from start_homes h where h.housing_id = p_housing order by h.sort, h.id limit 1)) as id
  ), rows as (
    select sf.furniture_id, coalesce(sf.slot, f.slot) as slot, sf.start_home is not null as specific, sf.sort, sf.id
      from starter_furniture sf
      join furniture f on f.id = sf.furniture_id and f.active
     where sf.active and sf.origin = p_origin
       and (sf.start_home is null or sf.start_home = (select id from home))
  )
  select r.furniture_id, r.slot from rows r
   where r.specific
      or not exists (select 1 from rows s where s.specific and s.slot = r.slot)
   order by r.sort, r.id;
$$;

-- Give a player their starter pieces (additive; pieces they already own are kept as they are).
create or replace function public.bl_give_starter_furniture(p_uid uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v profiles; n int;
begin
  select * into v from profiles where id = p_uid;
  if not found then return 0; end if;
  insert into player_furniture (user_id, furniture_id, slot, source)
  select p_uid, s.furniture_id, s.slot, 'starter'
    from bl_starter_furniture(v.origin, v.start_home, v.housing_id) s
  on conflict (user_id, furniture_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.bl_profiles_furnish() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.home_chosen and (tg_op = 'INSERT' or not old.home_chosen) then
    perform bl_give_starter_furniture(new.id);
  end if;
  return null;
end $$;
drop trigger if exists profiles_furnish on public.profiles;
create trigger profiles_furnish after insert or update of home_chosen on public.profiles
  for each row execute function public.bl_profiles_furnish();

-- Owned pieces that host an activity: does the player have one, and the best rest_pct among them.
create or replace function public.bl_furniture_for(p_uid uuid, p_activity text) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('owned', count(*) > 0, 'rest_pct', coalesce(max(f.rest_pct), 100))
    from player_furniture pf join furniture f on f.id = pf.furniture_id
   where pf.user_id = p_uid and f.active and p_activity = any (f.activities);
$$;

revoke execute on function public.bl_starter_furniture(text, text, text) from public, anon, authenticated;
revoke execute on function public.bl_give_starter_furniture(uuid)        from public, anon, authenticated;
revoke execute on function public.bl_profiles_furnish()                  from public, anon, authenticated;
revoke execute on function public.bl_furniture_for(uuid, text)           from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Backfill existing players (first apply only; additive)
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  if current_setting('bl.furniture_first', true) <> 'on' then return; end if;
  for r in select id from public.profiles where home_chosen loop
    perform public.bl_give_starter_furniture(r.id);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5. do_activity: same as L1 (20261006000100_real_time.sql) plus the furniture rules:
--    needs_furniture -> the player must own a piece that lists the activity (home activities only);
--    rest_pct of the best owned piece scales the energy it gives (the foam mat rests 90 %).
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
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
<<<<<<< HEAD
  v_home   jsonb;
  v_label  text;
=======
  v_furn   jsonb;
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
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
<<<<<<< HEAD
  v_label := a.name;
  v_eff := a.effects;
  if a.home_only then
    v_home := bl_home_activities(v_me) -> a.id;
    if v_home is not null and not (v_home ->> 'ok')::boolean then
      raise exception '%', v_home ->> 'reason' using errcode = 'P0001', hint = 'no_furniture';
    end if;
    if v_home is not null then
      v_label := coalesce(v_home ->> 'label', a.name);
      v_pct := coalesce((v_home ->> 'pct')::numeric, 100);
      if v_pct <> 100 then v_eff := bl_effects_pct(v_eff, greatest(0, least(200, v_pct))); end if;
    end if;
  end if;
  if a.night_only and not (bl_game_clock()->>'is_night')::boolean then
    raise exception '"%" is a night-time thing. Come back after dark.', v_label using errcode = 'P0001';
=======
  v_furn := bl_furniture_for(v_me.id, a.id);
  if a.home_only and a.needs_furniture and not (v_furn->>'owned')::boolean then
    raise exception 'You don''t have the furniture for "%" at home yet.', a.name
      using errcode = 'P0001', hint = 'no_furniture';
  end if;
  if a.night_only and not (bl_game_clock()->>'is_night')::boolean then
    raise exception '"%" is a night-time thing. Come back after dark.', a.name using errcode = 'P0001';
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
  end if;
  if a.cost > 0 then
    perform bl_add_money(v_me.id, 'cash', -a.cost, 'activity', jsonb_build_object('activity', a.id));
  end if;

<<<<<<< HEAD
=======
  v_eff := a.effects;
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
  for r in select it.id, it.name, it.effects->'boost'->a.id as bonus
             from inventory i join items it on it.id = i.item_id
            where i.user_id = v_me.id and i.qty > 0 and jsonb_typeof(it.effects->'boost'->a.id) = 'object'
            order by it.sort, it.id loop
    v_eff := v_eff || bl_effects_add(bl_need_effects(v_eff), bl_need_effects(r.bonus));
    perform bl_give_item(v_me.id, r.id, -1);
    v_used := v_used || r.name;
  end loop;
<<<<<<< HEAD
=======
  -- how well this piece rests you (foam mat < bed)
  if a.home_only and (v_furn->>'owned')::boolean and (v_furn->>'rest_pct')::numeric <> 100
     and coalesce((v_eff->>'energy')::numeric, 0) > 0 then
    v_eff := v_eff || jsonb_build_object('energy',
               round((v_eff->>'energy')::numeric * greatest(0, least(200, (v_furn->>'rest_pct')::numeric)) / 100, 1));
  end if;
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
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
<<<<<<< HEAD
  v_until := bl_set_busy_seconds(v_me.id, v_secs, v_label);
  update profiles set busy_needs_from = v_from where id = v_me.id;
  v_msg := 'You started "' || v_label || '"'
=======
  v_until := bl_set_busy_seconds(v_me.id, v_secs, a.name);
  update profiles set busy_needs_from = v_from where id = v_me.id;
  v_msg := 'You started "' || a.name || '"'
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
           || case when a.cost > 0 then ' (' || bl_naira(a.cost) || ').' else '. Enjoy!' end;
  if cardinality(v_used) > 0 then
    v_msg := v_msg || ' Used: ' || array_to_string(v_used, ', ') || '.';
  end if;
  if v_rent then
    v_msg := v_msg || ' The landlord keeps knocking: "Where my rent? You owe ' || bl_naira(v_me.rent_owed)
             || '!" You won''t rest well until you pay.';
  end if;
  return jsonb_build_object('message', v_msg, 'busy_until', v_until, 'effects', v_eff,
<<<<<<< HEAD
                            'used', to_jsonb(v_used), 'rent_penalty', v_rent, 'real_seconds', v_secs,
                            'label', v_label, 'activity', a.id);
end $$;

-- ---------------------------------------------------------------------
-- 8. get_my_state: same as V1-4 plus the "home" block
-- ---------------------------------------------------------------------
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
      'enabled', bl_cfg_bool('rent.enabled'),
      'owed_sleep_pct', bl_cfg('rent.owed_sleep_energy_pct')),
    'career', bl_career_info(v_me),
    'inventory', bl_inventory_info(v_me.id),
    'home', bl_home_info(v_me),
    'server_time', v_now
  );
end $$;

-- ---------------------------------------------------------------------
-- 9. Admin: furniture table, new columns, and a per-player furniture edit
=======
                            'used', to_jsonb(v_used), 'rent_penalty', v_rent, 'real_seconds', v_secs);
end $$;

-- ---------------------------------------------------------------------
-- 6. Admin: whitelist furniture + starter_furniture, and activities.needs_furniture
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
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
<<<<<<< HEAD
              "furniture":"obj","fixtures":"arr","sort":"int","active":"bool"}}'
    when 'furniture' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","kind":"text","provides":"arr","activity_pct":"obj","labels":"obj",
              "rank":"int","description":"text","sort":"int","active":"bool"}}'
=======
              "sort":"int","active":"bool"}}'
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
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
<<<<<<< HEAD
              "max_seconds":"num","min_seconds":"num","scale_by_need":"bool","effects":"obj","sort":"int",
              "requires":"text_null","requires_note":"text"}}'
=======
              "max_seconds":"num","min_seconds":"num","scale_by_need":"bool","needs_furniture":"bool","effects":"obj","sort":"int"}}'
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
    when 'locations' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","blurb":"text","risk":"num","night_risk_mult":"num","cctv":"bool","keke_ok":"bool",
              "congestion":"num","remote_km":"num","actions":"arr","sort":"int"}}'
    when 'chat_banned_words' then '{"pk":["word"],"insert":true,"order":"word","cols":{"active":"bool"}}'
<<<<<<< HEAD
  end::jsonb;
$$;

-- Set a player's own furniture (p_furniture null = reset to the starter set for their origin + home).
create or replace function public.admin_set_furniture(p_user uuid, p_furniture text[] default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  v_me    profiles;
  v_new   text[];
  v_bad   text;
begin
  select * into v_me from profiles where id = p_user;
  if not found then
    raise exception 'No such player.' using errcode = 'P0001', hint = 'no_player';
  end if;
  if p_furniture is null then
    v_new := bl_starter_furniture(v_me.start_home, v_me.housing_id, v_me.origin);
  else
    select string_agg(e, ', ') into v_bad from unnest(p_furniture) e where not exists (select 1 from furniture f where f.id = e);
    if v_bad is not null then
      raise exception 'Unknown furniture id(s): %', v_bad using errcode = 'P0001', hint = 'bad_value';
    end if;
    select coalesce(array_agg(distinct e order by e), '{}') into v_new from unnest(p_furniture) e;
  end if;
  update profiles set furniture = v_new where id = p_user;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'set_furniture', p_user, jsonb_build_object('old', to_jsonb(v_me.furniture), 'new', to_jsonb(v_new),
                                                               'reset', p_furniture is null));
  return jsonb_build_object('message', case when p_furniture is null then 'Furniture reset to the starter set.'
                                            else 'Furniture saved.' end,
                            'furniture', to_jsonb(v_new));
end $$;

-- ---------------------------------------------------------------------
-- 10. Privileges
-- ---------------------------------------------------------------------
revoke execute on function public.bl_home_row(text, text)                  from public, anon, authenticated;
revoke execute on function public.bl_starter_furniture(text, text, text)   from public, anon, authenticated;
revoke execute on function public.bl_home_fixtures(public.profiles)        from public, anon, authenticated;
revoke execute on function public.bl_home_activities(public.profiles)      from public, anon, authenticated;
revoke execute on function public.bl_home_info(public.profiles)            from public, anon, authenticated;
revoke execute on function public.bl_effects_pct(jsonb, numeric)           from public, anon, authenticated;
revoke execute on function public.bl_profile_furniture_trigger()           from public, anon, authenticated;
revoke execute on function public.bl_start_homes_furniture_check()         from public, anon, authenticated;
revoke execute on function public.do_activity(text)                        from public, anon;
revoke execute on function public.get_my_state()                           from public, anon;
revoke execute on function public.admin_set_furniture(uuid, text[])        from public, anon;
grant execute on function public.do_activity(text)                         to authenticated;
grant execute on function public.get_my_state()                            to authenticated;
grant execute on function public.admin_set_furniture(uuid, text[])         to authenticated;
=======
    when 'furniture' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","kind":"text","slot":"text","activities":"arr","rest_pct":"int",
              "color":"text_null","description":"text","sort":"int","active":"bool"}}'
    when 'starter_furniture' then '{"pk":["id"],"insert":true,"order":"origin, sort, id",
      "cols":{"origin":"text","start_home":"text_null","furniture_id":"text","slot":"text_null","sort":"int","active":"bool"}}'
  end::jsonb;
$$;
revoke execute on function public.bl_admin_table_spec(text) from public, anon, authenticated;

-- tidy: the first-apply flag is only for this file
select set_config('bl.furniture_first', 'off', false);
>>>>>>> 6bef09efb9654b4c8cff8a7a9d2395e7b37f94b1
