-- H1 Move house + bigger homes (docs/SHOPS.md "Moving house", docs/FURNITURE_CATALOGUE.md, docs/GARAGE.md).
-- Idempotent and safe on a non-empty DB.
--   1. home_layouts: the mini-flat (9.6 x 7.2 m) and the GRA duplex (14.4 x 10 m) are bigger, zoned homes with
--      built-in fixtures (fitted kitchen, ACs, dining set, guest room, staircase ...). Rows are generated from
--      src/art/home3d/model.ts + arrange.ts (hostel / face-me / self-contain are unchanged).
--   2. Existing placements in the changed layouts are re-checked: a piece that no longer fits moves to the nearest
--      free spot, or into the inventory (stored) when nothing fits.
--   3. player_released_homes: homes a player moved out of. You can't move back.
--   4. house_options() (the Houses app list) and house_move(home): pays the move-in fee (bank first, then cash,
--      ledger 'house_move'), releases the old home for good, moves the player home (the movers carry you), and
--      re-places every piece that stood in the old home (default slot, else the nearest free spot to where it
--      stood, else My items); pieces already in My items take a free default slot of the new home when valid.
--      The garage stays behind (its row is removed; cars stay owned).
--   5. Config house.move_enabled, house.move_in_weeks (admin-tunable).

-- ---------------------------------------------------------------- 1. layouts
insert into public.home_layouts (id, w, d, lot, blocks, doors, slots) values
  ('hostel', 5.2, 4.4, '[0,0,7.6,5.6]'::jsonb, '[[6.05,0.45,7.15,1.55],[6.05,1.85,7.15,2.95],[6.3,4.3,6.9,4.9],[4.4,3.1,6,4.1]]'::jsonb, '[[4.4,3.1,6,4.1]]'::jsonb, '{"bed":[0.75,1.1,0],"seat":[3.2,2.9,0],"sofa":[2,3.4,3],"tv":[0.3,3.4,1],"stove":[4.7,0.4,0],"fridge":[4.85,1.45,3],"wardrobe":[3.4,0.35,0],"bath":[6.8,3.55,3]}'::jsonb),
  ('face_me', 4.2, 3.8, '[0,0,7.2,5.4]'::jsonb, '[[5.65,0.35,6.75,1.45],[5.65,1.7,6.75,2.8],[4.6,4.43,5.4,4.98],[6.1,4.3,6.7,4.9],[3.4,2.4,5,3.3]]'::jsonb, '[[3.4,2.4,5,3.3]]'::jsonb, '{"bed":[0.85,1.1,0],"seat":[1.3,3.2,3],"sofa":[1.7,3.3,2],"tv":[2.75,0.3,0],"rug":[2.2,2.4,0],"stove":[3.6,2,3],"fridge":[3.75,0.4,0],"wardrobe":[0.35,3,1],"bath":[5.7,3.5,3]}'::jsonb),
  ('self_contain', 6, 4.8, '[0,0,7.4,6]'::jsonb, '[[0.23,0.15,0.68,0.85],[0.83,0.18,1.78,1.13],[0.14,1.25,0.56,1.75],[6.53,0.6,7.08,1.4],[1.84,-0.06,1.96,1.16],[-0.06,1.94,1.26,2.06],[5.2,2.55,6.8,3.45]]'::jsonb, '[[5.2,2.55,6.8,3.45]]'::jsonb, '{"bed":[4.95,1.5,3],"seat":[2.6,3.5,3],"sofa":[2.6,3.5,3],"tv":[0.3,3.5,1],"ctable":[1.45,3.5,1],"rug":[1.6,3.5,1],"stove":[2.7,0.35,0],"fridge":[3.55,0.4,0],"wardrobe":[5.3,0.35,0],"bath":[6.7,2,0]}'::jsonb),
  ('flat', 9.6, 7.2, '[0,0,11.4,8.6]'::jsonb, '[[7.03,0.15,7.48,0.85],[7.75,0.09,8.25,0.51],[8.58,0.13,9.53,1.08],[5.52,0.05,6.72,0.61],[6.85,3.9,8.35,5.5],[10.33,0.8,10.88,1.6],[3.74,-0.06,3.86,3.26],[-0.06,3.14,2.86,3.26],[6.74,-0.06,6.86,2.66],[6.74,2.54,7.66,2.66],[8.54,2.54,9.66,2.66],[3.74,3.14,4.46,3.26],[8.8,4,10.4,5.2]]'::jsonb, '[[8.8,4,10.4,5.2]]'::jsonb, '{"bed":[1.15,1.25,0],"seat":[2,6.7,2],"sofa":[3.4,5.2,3],"tv":[0.3,5.2,1],"ctable":[1.9,5.2,1],"rug":[2,5.2,0],"stove":[4.4,0.35,0],"fridge":[4.25,1.75,1],"wardrobe":[3.42,1.6,3],"bath":[7.25,1.9,1]}'::jsonb),
  ('duplex', 14.4, 10, '[-1,-0.5,18.6,14.6]'::jsonb, '[[9.48,0.15,9.92,0.85],[10.35,0.09,10.85,0.51],[10.9,0.35,11.7,2.05],[5.65,0.04,7.85,0.66],[7.9,0.05,9.1,0.61],[6.1,1.9,7.7,2.7],[11.99,0.09,12.61,0.71],[13.3,0.2,14.3,2.8],[7.75,5.55,9.85,7.25],[12.4,6.85,14.4,8.35],[13.68,6,14.13,6.4],[10.55,9.34,12.45,9.96],[16.33,0.8,16.88,1.6],[-0.8,13.5,-0.2,14.1],[17.6,5.9,18.2,6.5],[4.34,-0.06,4.46,3.86],[-0.06,3.74,3.26,3.86],[9.14,-0.06,9.26,3.06],[9.14,2.94,9.96,3.06],[10.84,2.94,11.86,3.06],[11.74,-0.06,11.86,3.06],[11.74,2.94,12.26,3.06],[10.34,5.34,14.46,5.46],[10.34,5.34,10.46,6.26],[10.34,7.14,10.46,10.06],[7.14,8.54,7.26,10.06],[5.4,9.2,6.6,10.8],[13.6,3.6,15.2,4.8]]'::jsonb, '[[5.4,9.2,6.6,10.8],[13.6,3.6,15.2,4.8]]'::jsonb, '{"bed":[1.4,1.35,0],"seat":[2.2,9.2,2],"sofa":[3.7,6.9,3],"tv":[0.3,6.9,1],"ctable":[1.9,6.9,1],"rug":[2.1,6.9,0],"stove":[5.1,0.35,0],"fridge":[4.85,1.75,1],"wardrobe":[3.4,0.35,0],"bath":[9.75,2.2,1]}'::jsonb)
on conflict (id) do update set w = excluded.w, d = excluded.d, lot = excluded.lot, blocks = excluded.blocks,
  doors = excluded.doors, slots = excluded.slots;

-- ---------------------------------------------------------------- helpers
-- The nearest spot (to tx/tz) where p_key may stand in p_uid's home, on a 0.5 m grid with quarter turns
-- (wall pieces hang flush on the north / west wall), as {x, z, rot}; null when nothing fits. Same rules as
-- the client's findFreeSpot (src/art/home3d/arrange.ts), checked by bl_furniture_check.
create or replace function public.bl_furniture_find_spot(p_uid uuid, p_layout text, p_key text, p_tx numeric, p_tz numeric)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  f  furniture;
  hl home_layouts;
  ax0 numeric; az0 numeric; ax1 numeric; az1 numeric;
  c  record;
begin
  select * into f from furniture where id = bl_furniture_id_of(p_key);
  select * into hl from home_layouts where id = p_layout;
  if f.id is null or hl.id is null then return null; end if;
  if f.placement = 'out' then
    ax0 := (hl.lot->>0)::numeric; az0 := (hl.lot->>1)::numeric; ax1 := (hl.lot->>2)::numeric; az1 := (hl.lot->>3)::numeric;
  else
    ax0 := 0; az0 := 0; ax1 := hl.w; az1 := hl.d;
  end if;
  for c in
    select x, z, rot from (
      select case when f.placement = 'wall' and r.rot = 1 then f.d / 2 else ax0 + i * 0.5 end as x,
             case when f.placement = 'wall' and r.rot = 0 then f.d / 2 else az0 + j * 0.5 end as z,
             r.rot
        from generate_series(0, floor((ax1 - ax0) / 0.5)::int) i
       cross join generate_series(0, floor((az1 - az0) / 0.5)::int) j
       cross join (select unnest(case when f.placement = 'wall' then array[0, 1] else array[0, 1, 2, 3] end) as rot) r) g
     group by x, z, rot
     order by (x - coalesce(p_tx, hl.w / 2)) ^ 2 + (z - coalesce(p_tz, hl.d / 2)) ^ 2, rot
  loop
    if bl_furniture_check(p_uid, p_layout, p_key, c.x, c.z, c.rot) is null then
      return jsonb_build_object('x', c.x, 'z', c.z, 'rot', c.rot);
    end if;
  end loop;
  return null;
end $$;
revoke execute on function public.bl_furniture_find_spot(uuid, text, text, numeric, numeric) from public, anon, authenticated;

-- Place one stored row: at (x, z, rot) when that is valid, else the nearest free spot to it, else it stays
-- stored. Returns true when the piece stands in the room.
create or replace function public.bl_furniture_autoplace(p_uid uuid, p_layout text, p_key text, p_x numeric, p_z numeric, p_rot integer, p_try_exact boolean)
returns boolean language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if p_try_exact and p_x is not null and bl_furniture_check(p_uid, p_layout, p_key, p_x, p_z, p_rot) is null then
    v := jsonb_build_object('x', p_x, 'z', p_z, 'rot', ((coalesce(p_rot, 0) % 4) + 4) % 4);
  else
    v := bl_furniture_find_spot(p_uid, p_layout, p_key, p_x, p_z);
  end if;
  if v is null then return false; end if;
  update player_house_furniture
     set x = round((v->>'x')::numeric, 3), z = round((v->>'z')::numeric, 3), rotation = (v->>'rot')::int,
         stored = false, layout = p_layout, updated_at = bl_now()
   where owner_id = p_uid and furniture_key = p_key;
  return true;
end $$;
revoke execute on function public.bl_furniture_autoplace(uuid, text, text, numeric, numeric, integer, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------- 2. re-check placements in the changed layouts
do $mig$
declare
  o record;
  r record;
begin
  for o in select distinct owner_id, layout from public.player_house_furniture
            where layout in ('flat', 'duplex') and not stored loop
    -- take them all out, then put them back one by one (oldest first), so each check sees only pieces
    -- that are already valid
    create temp table if not exists bl_h1_rows (key text, x numeric, z numeric, rot int, at timestamptz) on commit drop;
    truncate bl_h1_rows;
    insert into bl_h1_rows select furniture_key, x, z, rotation, updated_at from public.player_house_furniture
     where owner_id = o.owner_id and layout = o.layout and not stored;
    update public.player_house_furniture set stored = true where owner_id = o.owner_id and layout = o.layout and not stored;
    for r in select * from bl_h1_rows order by at, key loop
      perform public.bl_furniture_autoplace(o.owner_id, o.layout, r.key, r.x, r.z, r.rot, true);
    end loop;
  end loop;
end $mig$;

-- ---------------------------------------------------------------- 3. released homes + config
create table if not exists public.player_released_homes (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  start_home  text not null references public.start_homes(id) on update cascade on delete cascade,
  housing_id  text,
  released_at timestamptz not null default now(),
  primary key (user_id, start_home)
);
alter table public.player_released_homes enable row level security;
revoke all on public.player_released_homes from anon, authenticated;
grant select on public.player_released_homes to authenticated;
drop policy if exists player_released_homes_own on public.player_released_homes;
create policy player_released_homes_own on public.player_released_homes for select to authenticated
  using (user_id = (select auth.uid()));

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('house.move_enabled', 'true', 'rent', 'Moving house on',
 'H1: players can rent another home from the phone''s Houses app and move in. Off = the list shows but moving is refused.',
 'bool', null, null),
('house.move_in_weeks', '4', 'rent', 'Move-in fee (weeks of rent)',
 'H1: the one-off move-in fee (agent, caution and legal) is this many weeks of the new home''s rent. Weekly rent then continues on the usual rent day.',
 'number', 0, 52)
on conflict (key) do nothing;

-- ---------------------------------------------------------------- 4. RPCs
-- The Houses app list: every active home with its move-in fee and size, and whether it is yours, one you left
-- (can't go back) or available. garage = the garage you would leave behind (null = none).
-- (volatile: bl_me_any locks the profile row, so PostgREST must not run it read-only)
create or replace function public.house_options() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me    profiles := bl_me_any();
  v_weeks numeric := coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.move_in_weeks'), 4);
  v_kind  text;
  v_garage jsonb;
begin
  v_kind := bl_housing_kind(coalesce(v_me.home_visit_original_housing_id, v_me.housing_id));
  select jsonb_build_object('type', g.garage_type, 'name', t.name) into v_garage
    from player_garages g join garage_types t on t.id = g.garage_type
   where g.user_id = v_me.id
     and g.housing_id is not distinct from coalesce(v_me.home_visit_original_housing_id, v_me.housing_id);
  return jsonb_build_object(
    'enabled', bl_cfg_bool('house.move_enabled'),
    'move_in_weeks', v_weeks,
    'current', v_me.start_home,
    'garage', v_garage,
    'homes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', h.id, 'name', h.name, 'emoji', h.emoji, 'district', h.district, 'tag', h.tag,
               'description', h.description, 'weekly_rent', h.weekly_rent,
               'move_in', (h.weekly_rent * v_weeks)::bigint,
               'kind', bl_housing_kind(h.housing_id), 'layout', bl_home_layout_id(h.housing_id),
               'w', hl.w, 'd', hl.d, 'area', round(hl.w * hl.d),
               'status', case when h.id = v_me.start_home then 'current'
                              when r.start_home is not null then 'released' else 'available' end)
             order by h.weekly_rent, h.sort)
        from start_homes h
        left join home_layouts hl on hl.id = bl_home_layout_id(h.housing_id)
        left join player_released_homes r on r.user_id = v_me.id and r.start_home = h.id
       where h.active), '[]'::jsonb));
end $$;
revoke execute on function public.house_options() from public, anon;
grant execute on function public.house_options() to authenticated, service_role;

-- Rent the home and move in now. Server-authoritative: not while travelling, busy, jailed, in hospital,
-- visiting someone, or with guests in the house; not the same home and never back to one you left; rent owed
-- must be settled. Pays weekly_rent x house.move_in_weeks (bank first, then cash).
create or replace function public.house_move(p_home text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me     profiles := bl_me();
  h        start_homes;
  v_old    start_homes;
  v_loc    locations;
  v_weeks  numeric;
  v_cost   bigint;
  v_bank   bigint := 0;
  v_cash   bigint := 0;
  v_meta   jsonb;
  v_old_layout text;
  v_new_layout text;
  v_old_w  numeric; v_old_d numeric;
  hl       home_layouts;
  v_garage text;
  v_placed int := 0;
  v_left   int := 0;
  v_items  int := 0;
  v_slots  text[] := '{}';
  r        record;
  v_ok     boolean;
begin
  perform bl_assert_free(v_me);
  if v_me.home_visit_host_id is not null then
    raise exception 'You are visiting someone. Go back home first, then move.' using errcode = 'P0001', hint = 'visiting';
  end if;
  if exists (select 1 from profiles g where g.home_visit_host_id = v_me.id and g.location_id = v_me.home_location_id) then
    raise exception 'Your guests are still in the house. See them off first, then move.' using errcode = 'P0001', hint = 'hosting';
  end if;
  if not bl_cfg_bool('house.move_enabled') then
    raise exception 'Moving house is paused right now. Try again later.' using errcode = 'P0001', hint = 'moving_disabled';
  end if;
  select * into h from start_homes where id = lower(trim(coalesce(p_home, ''))) and active;
  if not found then
    raise exception 'That home is not on the list.' using errcode = 'P0001', hint = 'bad_home';
  end if;
  if h.id = v_me.start_home then
    raise exception 'You already live here.' using errcode = 'P0001', hint = 'same_home';
  end if;
  if exists (select 1 from player_released_homes where user_id = v_me.id and start_home = h.id) then
    raise exception 'You moved out of % already. The landlord has given it to someone else; you can''t go back.', h.name
      using errcode = 'P0001', hint = 'old_home';
  end if;
  if v_me.rent_owed > 0 then
    raise exception 'Settle the % rent you owe first. Your landlord won''t release you.', bl_naira(v_me.rent_owed)
      using errcode = 'P0001', hint = 'rent_owed';
  end if;
  v_weeks := greatest(0, coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.move_in_weeks'), 4));
  v_cost := (h.weekly_rent * v_weeks)::bigint;
  if greatest(v_me.bank, 0) + greatest(v_me.cash, 0) < v_cost then
    raise exception 'Not enough money. Moving into % costs % and you have %.', h.name, bl_naira(v_cost),
      bl_naira(greatest(v_me.bank, 0) + greatest(v_me.cash, 0)) using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  select * into v_old from start_homes where id = v_me.start_home;
  v_meta := jsonb_build_object('home', h.id, 'name', h.name, 'from', v_me.start_home, 'weeks', v_weeks);
  v_bank := least(v_cost, greatest(v_me.bank, 0));
  v_cash := v_cost - v_bank;
  if v_bank > 0 then perform bl_add_money(v_me.id, 'bank', -v_bank, 'house_move', v_meta); end if;
  if v_cash > 0 then perform bl_add_money(v_me.id, 'cash', -v_cash, 'house_move', v_meta); end if;

  -- the old home is gone for good; its garage stays behind (the cars stay yours)
  if v_me.start_home is not null then
    insert into player_released_homes (user_id, start_home, housing_id, released_at)
    values (v_me.id, v_me.start_home, v_me.housing_id, bl_now()) on conflict (user_id, start_home) do nothing;
  end if;
  select t.name into v_garage from player_garages g join garage_types t on t.id = g.garage_type where g.user_id = v_me.id;
  delete from player_garages where user_id = v_me.id;

  -- furniture: what stood in the old home (row-less starters count as standing at their slot)
  v_old_layout := bl_furniture_materialize(v_me.id);
  select w, d into v_old_w, v_old_d from home_layouts where id = v_old_layout;
  create temp table if not exists bl_h1_move (key text, slot text, sort int, copy int, rx numeric, rz numeric) on commit drop;
  truncate bl_h1_move;
  insert into bl_h1_move
  select hf.furniture_key, coalesce(pf.slot, f.slot), f.sort, bl_furniture_copy_of(hf.furniture_key),
         hf.x / nullif(v_old_w, 0), hf.z / nullif(v_old_d, 0)
    from player_house_furniture hf
    join player_furniture pf on pf.user_id = hf.owner_id and pf.furniture_id = bl_furniture_id_of(hf.furniture_key)
    join furniture f on f.id = pf.furniture_id
   where hf.owner_id = v_me.id and not hf.stored;

  -- move in: the private home location takes the new place's map spot and scene; the movers carry you home
  v_loc := bl_location(h.location_id);
  update locations set district = v_loc.district, scene = v_loc.scene, blurb = v_loc.blurb, risk = v_loc.risk,
         night_risk_mult = v_loc.night_risk_mult, cctv = v_loc.cctv, keke_ok = v_loc.keke_ok,
         congestion = v_loc.congestion, remote_km = v_loc.remote_km, x = v_loc.x, y = v_loc.y,
         actions = v_loc.actions, open_hour = v_loc.open_hour, close_hour = v_loc.close_hour
   where id = v_me.home_location_id and private_home_owner_id = v_me.id;
  update profiles set start_home = h.id, housing_id = h.housing_id, weekly_rent = h.weekly_rent,
         location_id = home_location_id,
         rent_due_at = coalesce(rent_due_at, bl_rent_due_after(bl_now(), bl_cfg('rent.first_due_grace_game_days')))
   where id = v_me.id;

  -- every owned copy goes in as stored for the new layout, then what stood in the old home is placed again
  v_new_layout := bl_home_layout_id(h.housing_id);
  select * into hl from home_layouts where id = v_new_layout;
  delete from player_house_furniture where owner_id = v_me.id;
  insert into player_house_furniture (owner_id, furniture_key, x, z, rotation, stored, layout, updated_at)
  select v_me.id, case when n = 1 then 'own_' || pf.furniture_id else 'own_' || pf.furniture_id || '-' || n end,
         0, 0, 0, true, v_new_layout, bl_now()
    from player_furniture pf join furniture f on f.id = pf.furniture_id
   cross join lateral generate_series(1, pf.qty) n
   where pf.user_id = v_me.id and f.active
  on conflict (owner_id, furniture_key) do nothing;
  if hl.id is not null then
    -- pieces with a default slot first (bed, sofa, TV ...), then the rest
    for r in select * from bl_h1_move order by (copy = 1 and hl.slots ? slot) desc, sort, key loop
      v_ok := false;
      if r.copy = 1 and hl.slots ? r.slot and not (r.slot = any (v_slots)) then
        v_ok := bl_furniture_autoplace(v_me.id, v_new_layout, r.key, (hl.slots->r.slot->>0)::numeric,
                  (hl.slots->r.slot->>1)::numeric, (hl.slots->r.slot->>2)::int, true);
        if v_ok then v_slots := v_slots || r.slot; end if;
      end if;
      if not v_ok then
        v_ok := bl_furniture_autoplace(v_me.id, v_new_layout, r.key, r.rx * hl.w, r.rz * hl.d, 0, false);
      end if;
      if v_ok then v_placed := v_placed + 1; else v_left := v_left + 1; end if;
    end loop;
    -- a bigger home has more default slots: pieces waiting in My items (e.g. a centre table the face-me had no
    -- room for) take a free default slot of the new home when it is valid there
    for r in select hf.furniture_key as key, coalesce(pf.slot, f.slot) as slot
               from player_house_furniture hf
               join player_furniture pf on pf.user_id = hf.owner_id and pf.furniture_id = bl_furniture_id_of(hf.furniture_key)
               join furniture f on f.id = pf.furniture_id
              where hf.owner_id = v_me.id and hf.stored and bl_furniture_copy_of(hf.furniture_key) = 1
                and hl.slots ? coalesce(pf.slot, f.slot)
              order by f.sort, hf.furniture_key loop
      continue when r.slot = any (v_slots)
        or bl_furniture_check(v_me.id, v_new_layout, r.key, (hl.slots->r.slot->>0)::numeric,
                              (hl.slots->r.slot->>1)::numeric, (hl.slots->r.slot->>2)::int) is not null;
      update player_house_furniture
         set x = (hl.slots->r.slot->>0)::numeric, z = (hl.slots->r.slot->>1)::numeric,
             rotation = ((((hl.slots->r.slot->>2)::int) % 4) + 4) % 4, stored = false, updated_at = bl_now()
       where owner_id = v_me.id and furniture_key = r.key;
      v_slots := v_slots || r.slot;
      v_placed := v_placed + 1;
    end loop;
  end if;
  select count(*) into v_items from player_house_furniture where owner_id = v_me.id and stored;

  return jsonb_build_object(
    'message', 'Welcome to your new ' || lower(h.name) || case when h.district <> '' then ' in ' || h.district else '' end || '!'
               || case when v_items > 0 then ' ' || v_items || case when v_items = 1 then ' item is' else ' items are' end
                       || ' in My items. Place them in Arrange.' else '' end,
    'home', h.id, 'name', h.name, 'layout', v_new_layout, 'from', v_me.start_home,
    'placed', v_placed, 'not_fit', v_left, 'in_items', v_items, 'garage_left', v_garage,
    'spent', v_cost, 'from_bank', v_bank, 'from_cash', v_cash, 'weekly_rent', h.weekly_rent);
end $$;
revoke execute on function public.house_move(text) from public, anon;
grant execute on function public.house_move(text) to authenticated, service_role;

-- ledger label "Move-in: <home>"
do $mig$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.bl_ledger_label'::regproc);
  if position('''house_move''' in v_def) = 0 then
    if position('    when ''garage'' then' in v_def) = 0 then raise exception 'H1: bl_ledger_label marker not found'; end if;
    v_def := replace(v_def, '    when ''garage'' then',
      E'    when ''house_move'' then return ''Move-in: '' || coalesce(p_meta->>''name'', ''new home'');\n    when ''garage'' then');
    execute v_def;
  end if;
end $mig$;

notify pgrst, 'reload schema';
