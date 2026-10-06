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
  v_furn := bl_furniture_for(v_me.id, a.id);
  if a.home_only and a.needs_furniture and not (v_furn->>'owned')::boolean then
    raise exception 'You don''t have the furniture for "%" at home yet.', a.name
      using errcode = 'P0001', hint = 'no_furniture';
  end if;
  if a.night_only and not (bl_game_clock()->>'is_night')::boolean then
    raise exception '"%" is a night-time thing. Come back after dark.', a.name using errcode = 'P0001';
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
  return jsonb_build_object('message', v_msg, 'busy_until', v_until, 'effects', v_eff,
                            'used', to_jsonb(v_used), 'rent_penalty', v_rent, 'real_seconds', v_secs);
end $$;

-- ---------------------------------------------------------------------
-- 6. Admin: whitelist furniture + starter_furniture, and activities.needs_furniture
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
              "max_seconds":"num","min_seconds":"num","scale_by_need":"bool","needs_furniture":"bool","effects":"obj","sort":"int"}}'
    when 'locations' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","blurb":"text","risk":"num","night_risk_mult":"num","cctv":"bool","keke_ok":"bool",
              "congestion":"num","remote_km":"num","actions":"arr","sort":"int"}}'
    when 'chat_banned_words' then '{"pk":["word"],"insert":true,"order":"word","cols":{"active":"bool"}}'
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
