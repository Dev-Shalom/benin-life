-- H4: everything that comes with a house is the player's own furniture (docs/FURNITURE_CATALOGUE.md
-- "Came with the house"). Idempotent and safe on a non-empty DB: columns/tables `if not exists`, seeds
-- `on conflict`, new functions `create or replace`, live functions patched from pg_get_functiondef with guarded
-- text replacement (grants kept).
--   1. config furniture.included_resale_pct (25) and furniture.included_move_cap_pct (75).
--   2. player_furniture.house_qty: how many copies came with a house (the starter piece, a home's built-ins).
--      They are always the HIGHEST copy numbers (qty - house_qty + 1 .. qty), so a key says what it is. A trigger
--      sets house_qty for starter rows; existing starter rows with bought extras swap keys once to follow the rule.
--   3. home_layouts.included: the movable pieces each home comes with (catalogue id + default spot), generated
--      from src/art/home3d/model.ts (`included`). blocks no longer hold them (only walls, partitions, doors,
--      plumbing, the fitted kitchen counter + island and the staircase, which stay part of the house).
--   4. player_house_grants: one row per (player, home) and one 'starter' row per life. bl_house_items_grant(uid,
--      move_in) gives the home's pieces ONCE per home as real copies at their default spots (source
--      'came_with_house'), and records an allowance: the most the player can ever earn selling came-with-the-
--      house pieces from that grant: at most furniture.included_move_cap_pct of the move-in fee paid (the first
--      home: of its move-in fee), so move -> sell never profits. Starter pieces (once per life): their resale value.
--      Called by house_move (before the old pieces are placed), on choosing the first home (profiles trigger),
--      as a safety net from bl_furniture_materialize, and below for every existing player.
--   5. furniture_sell: the 'starter_piece' refusal is gone. A came-with-the-house copy pays
--      furniture.included_resale_pct of the catalogue price, capped by the allowance left (refused with
--      'house_resale_used' when none is left); a bought copy pays furniture.resale_pct as before. Keys are renumbered
--      so came-with-the-house copies stay the highest numbers. furniture_sell_quote(key) shows the payout first.
--      furniture_buy keeps the rule too (the new bought copy takes the first came-with-the-house number).
--   6. Need bonuses: unchanged code. bl_furniture_for counts qty minus stored rows, so a sold piece (qty - 1) or a
--      stored one stops giving its bonus.

-- ---------------------------------------------------------------- 1. config
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('furniture.included_resale_pct', '25', 'shop', 'Came-with-house resale %',
 'H4: a piece that came with the house (starter piece, a home''s built-ins: ACs, dining set, chandelier ...) sells for this % of its catalogue price, capped by furniture.included_move_cap_pct for homes you moved into.',
 'percent', 0, 100),
('furniture.included_move_cap_pct', '75', 'shop', 'Came-with-house cap (% of move-in fee)',
 'H4: selling a home''s came-with-the-house pieces pays at most this % of that home''s move-in fee (the fee paid when moving; the first home: its listed move-in fee). Keep it under 100 so moving to sell is never a profit. Starter pieces are not capped.',
 'percent', 0, 100)
on conflict (key) do nothing;

-- ---------------------------------------------------------------- helpers
-- own_x (copy 1) / own_x-n
create or replace function public.bl_furniture_key(p_id text, p_copy integer) returns text
language sql immutable set search_path = public as $$
  select case when coalesce(p_copy, 1) <= 1 then 'own_' || p_id else 'own_' || p_id || '-' || p_copy end
$$;
revoke execute on function public.bl_furniture_key(text, integer) from public, anon, authenticated;

-- resale of one piece at p_pct, rounded down to ₦100 (same as furniture_sell)
create or replace function public.bl_furniture_resale(p_price bigint, p_pct numeric) returns bigint
language sql immutable set search_path = public as $$
  select (floor(coalesce(p_price, 0) * greatest(0, least(100, coalesce(p_pct, 0))) / 100.0 / 100) * 100)::bigint
$$;
revoke execute on function public.bl_furniture_resale(bigint, numeric) from public, anon, authenticated;

create or replace function public.bl_included_pct() returns numeric
language sql stable set search_path = public as $$
  select greatest(0, least(100, coalesce((select (value #>> '{}')::numeric from game_config
                                           where key = 'furniture.included_resale_pct'), 25)))
$$;
revoke execute on function public.bl_included_pct() from public, anon, authenticated;

-- ---------------------------------------------------------------- 2. house_qty
alter table public.player_furniture add column if not exists house_qty integer not null default 0;

-- starter rows given before H4: copy 1 is the free piece. Bought extras (copies 2..n) swap keys with it once so the
-- free piece is the highest copy number (rows first, so a row-less starter keeps its spot).
do $mig$
declare r record; v_first text; v_last text;
begin
  for r in select user_id, furniture_id, qty from public.player_furniture
            where source = 'starter' and house_qty = 0 and qty > 1 loop
    perform public.bl_furniture_materialize(r.user_id);
    v_first := 'own_' || r.furniture_id;
    v_last := 'own_' || r.furniture_id || '-' || r.qty;
    update public.player_house_furniture set furniture_key = '__h4_swap' where owner_id = r.user_id and furniture_key = v_first;
    update public.player_house_furniture set furniture_key = v_first where owner_id = r.user_id and furniture_key = v_last;
    update public.player_house_furniture set furniture_key = v_last where owner_id = r.user_id and furniture_key = '__h4_swap';
  end loop;
  update public.player_furniture set house_qty = 1 where source = 'starter' and house_qty = 0;
end $mig$;

alter table public.player_furniture drop constraint if exists player_furniture_house_qty_check;
alter table public.player_furniture add constraint player_furniture_house_qty_check check (house_qty between 0 and qty);

-- new starter rows (bl_give_starter_furniture) and came-with-house rows: every copy came with the house
create or replace function public.bl_player_furniture_house_qty() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.source in ('starter', 'came_with_house') and coalesce(new.house_qty, 0) = 0 then
    new.house_qty := new.qty;
  end if;
  return new;
end $$;
revoke execute on function public.bl_player_furniture_house_qty() from public, anon, authenticated;
drop trigger if exists player_furniture_house_qty on public.player_furniture;
create trigger player_furniture_house_qty before insert on public.player_furniture
  for each row execute function public.bl_player_furniture_house_qty();

-- ---------------------------------------------------------------- 3. home layouts (generated from model.ts)
alter table public.home_layouts add column if not exists included jsonb not null default '[]'::jsonb;
insert into public.home_layouts (id, w, d, lot, blocks, doors, slots, included) values
  ('hostel', 5.2, 4.4, '[0,0,7.6,5.6]'::jsonb, '[[6.05,0.45,7.15,1.55],[6.05,1.85,7.15,2.95],[6.3,4.3,6.9,4.9],[4.4,3.1,6,4.1]]'::jsonb, '[[4.4,3.1,6,4.1]]'::jsonb, '{"bed":[0.75,1.1,0],"seat":[3.2,2.9,0],"sofa":[2,3.4,3],"tv":[0.3,3.4,1],"stove":[4.7,0.4,0],"fridge":[4.85,1.45,3],"wardrobe":[3.4,0.35,0],"bath":[6.8,3.55,3]}'::jsonb, '[]'::jsonb),
  ('face_me', 4.2, 3.8, '[0,0,7.2,5.4]'::jsonb, '[[5.65,0.35,6.75,1.45],[5.65,1.7,6.75,2.8],[4.6,4.43,5.4,4.98],[6.1,4.3,6.7,4.9],[3.4,2.4,5,3.3]]'::jsonb, '[[3.4,2.4,5,3.3]]'::jsonb, '{"bed":[0.85,1.1,0],"seat":[1.3,3.2,3],"sofa":[1.7,3.3,2],"tv":[2.75,0.3,0],"rug":[2.2,2.4,0],"stove":[3.6,2,3],"fridge":[3.75,0.4,0],"wardrobe":[0.35,3,1],"bath":[5.7,3.5,3]}'::jsonb, '[]'::jsonb),
  ('self_contain', 6, 4.8, '[0,0,7.4,6]'::jsonb, '[[0.23,0.15,0.68,0.85],[0.83,0.18,1.78,1.13],[0.14,1.25,0.56,1.75],[6.53,0.6,7.08,1.4],[1.84,-0.06,1.96,1.16],[-0.06,1.94,1.26,2.06],[5.2,2.55,6.8,3.45]]'::jsonb, '[[5.2,2.55,6.8,3.45]]'::jsonb, '{"bed":[4.95,1.5,3],"seat":[2.6,3.5,3],"sofa":[2.6,3.5,3],"tv":[0.3,3.5,1],"ctable":[1.45,3.5,1],"rug":[1.6,3.5,1],"stove":[2.7,0.35,0],"fridge":[3.55,0.4,0],"wardrobe":[5.3,0.35,0],"bath":[6.7,2,0]}'::jsonb, '[]'::jsonb),
  ('flat', 9.6, 7.2, '[0,0,11.4,8.6]'::jsonb, '[[7.03,0.15,7.48,0.85],[7.75,0.09,8.25,0.51],[8.58,0.13,9.53,1.08],[3.74,-0.06,3.86,3.26],[-0.06,3.14,2.86,3.26],[6.74,-0.06,6.86,2.66],[6.74,2.54,7.66,2.66],[8.54,2.54,9.66,2.66],[3.74,3.14,4.46,3.26],[8.8,4,10.4,5.2]]'::jsonb, '[[8.8,4,10.4,5.2]]'::jsonb, '{"bed":[1.15,1.25,0],"seat":[2,6.7,2],"sofa":[3.4,5.2,3],"tv":[0.3,5.2,1],"ctable":[1.9,5.2,1],"rug":[2,5.2,0],"stove":[4.4,0.35,0],"fridge":[4.25,1.75,1],"wardrobe":[3.42,1.6,3],"bath":[7.25,1.9,1]}'::jsonb, '[{"id":"cab","furniture":"kitchen_cabinet","kind":"kitchen_cab","x":6.12,"z":0.33,"rot":0},{"id":"ac","furniture":"ac_split","kind":"ac","x":1.2,"z":0.15,"rot":0},{"id":"cfan","furniture":"fan_ceiling","kind":"fan_ceiling","x":2.2,"z":5.2,"rot":0},{"id":"dining","furniture":"dining_4","kind":"dining4","x":7.6,"z":4.7,"rot":0},{"id":"gen","furniture":"gen_firman","kind":"generator","x":10.6,"z":1.2,"rot":1}]'::jsonb),
  ('duplex', 14.4, 10, '[-1,-0.5,18.6,14.6]'::jsonb, '[[9.48,0.15,9.92,0.85],[10.35,0.09,10.85,0.51],[10.9,0.35,11.7,2.05],[5.65,0.04,7.85,0.66],[6.1,1.9,7.7,2.7],[13.3,0.2,14.3,2.8],[4.34,-0.06,4.46,3.86],[-0.06,3.74,3.26,3.86],[9.14,-0.06,9.26,3.06],[9.14,2.94,9.96,3.06],[10.84,2.94,11.86,3.06],[11.74,-0.06,11.86,3.06],[11.74,2.94,12.26,3.06],[10.34,5.34,14.46,5.46],[10.34,5.34,10.46,6.26],[10.34,7.14,10.46,10.06],[7.14,8.54,7.26,10.06],[5.4,9.2,6.6,10.8],[13.6,3.6,15.2,4.8]]'::jsonb, '[[5.4,9.2,6.6,10.8],[13.6,3.6,15.2,4.8]]'::jsonb, '{"bed":[1.4,1.35,0],"seat":[2.2,9.2,2],"sofa":[3.7,6.9,3],"tv":[0.3,6.9,1],"ctable":[1.9,6.9,1],"rug":[2.1,6.9,0],"stove":[5.1,0.35,0],"fridge":[4.85,1.75,1],"wardrobe":[3.4,0.35,0],"bath":[9.75,2.2,1]}'::jsonb, '[{"id":"heater","furniture":"water_heater","kind":"water_heater","x":10.3,"z":0.15,"rot":0},{"id":"cab","furniture":"kitchen_cabinet","kind":"kitchen_cab","x":8.5,"z":0.33,"rot":0},{"id":"washer","furniture":"washing_machine","kind":"washer","x":12.3,"z":0.4,"rot":0},{"id":"ac1","furniture":"ac_split","kind":"ac","x":1.4,"z":0.15,"rot":0},{"id":"ac2","furniture":"ac_split","kind":"ac","x":0.15,"z":5.2,"rot":1},{"id":"chand","furniture":"chandelier","kind":"chandelier","x":2.2,"z":6.9,"rot":0},{"id":"cfan","furniture":"fan_ceiling","kind":"fan_ceiling","x":8.8,"z":6.4,"rot":0},{"id":"dining","furniture":"dining_6","kind":"dining6","x":8.8,"z":6.4,"rot":0},{"id":"gbed","furniture":"bed_double","kind":"bed_double","x":13.4,"z":7.6,"rot":3},{"id":"gside","furniture":"bedside","kind":"bedside","x":13.9,"z":6.2,"rot":0},{"id":"gward","furniture":"wardrobe_big","kind":"wardrobe_big","x":11.5,"z":9.65,"rot":2},{"id":"gen","furniture":"gen_firman","kind":"generator","x":16.6,"z":1.2,"rot":1},{"id":"palm1","furniture":"plant_palm","kind":"plant_big","x":-0.5,"z":13.8,"rot":0},{"id":"palm2","furniture":"plant_palm","kind":"plant_big","x":17.9,"z":6.2,"rot":0}]'::jsonb)
on conflict (id) do update set w = excluded.w, d = excluded.d, lot = excluded.lot, blocks = excluded.blocks,
  doors = excluded.doors, slots = excluded.slots, included = excluded.included;

-- every included piece must be a catalogue row of the same 3D kind (the client draws the owned copy by kind)
do $mig$
declare v text;
begin
  select string_agg(i->>'furniture', ', ') into v
    from public.home_layouts hl, jsonb_array_elements(hl.included) i
   where not exists (select 1 from public.furniture f where f.id = i->>'furniture' and f.kind = i->>'kind');
  if v is not null then raise exception 'H4: included pieces missing from the furniture catalogue: %', v; end if;
end $mig$;

-- ---------------------------------------------------------------- 4. grants
create table if not exists public.player_house_grants (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  home_key   text not null,                     -- start_homes.id (housing_id for legacy rows), or 'starter'
  layout     text,
  items      jsonb not null default '[]'::jsonb, -- [{furniture, key}] what was given
  value      bigint not null default 0,          -- their resale value at furniture.included_resale_pct
  move_in    bigint,                             -- the move-in fee paid (null = first home: its fee is used / starter)
  allowance  bigint not null default 0,          -- the most selling them can ever pay
  paid       bigint not null default 0,          -- paid out so far (came-with-house sales, oldest grant first)
  granted_at timestamptz not null default now(),
  primary key (user_id, home_key)
);
alter table public.player_house_grants enable row level security;
revoke all on public.player_house_grants from anon, authenticated;
grant select on public.player_house_grants to authenticated;
drop policy if exists player_house_grants_own on public.player_house_grants;
create policy player_house_grants_own on public.player_house_grants for select to authenticated
  using (user_id = (select auth.uid()));

-- What came-with-the-house sales may still pay this player.
create or replace function public.bl_house_resale_left(p_uid uuid) returns bigint
language sql stable set search_path = public as $$
  select greatest(0, coalesce(sum(allowance - paid), 0))::bigint from player_house_grants where user_id = p_uid
$$;
revoke execute on function public.bl_house_resale_left(uuid) from public, anon, authenticated;

-- Give the player's current home's pieces, once per home (and record the starter allowance once per life).
-- p_move_in = the move-in fee just paid (house_move); null = first home (the home's move-in fee is used for the cap).
-- Returns how many pieces were given.
create or replace function public.bl_house_items_grant(p_uid uuid, p_move_in bigint default null) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_me     profiles;
  v_home   text;
  v_layout text;
  hl       home_layouts;
  it       jsonb;
  f        furniture;
  v_pct    numeric := bl_included_pct();
  v_cap    numeric := greatest(0, least(100, coalesce((select (value #>> '{}')::numeric from game_config
                                                        where key = 'furniture.included_move_cap_pct'), 75)));
  v_q      int;
  v_key    text;
  v_n      int := 0;
  v_value  bigint := 0;
  v_items  jsonb := '[]'::jsonb;
  v_fee    bigint;
begin
  select * into v_me from profiles where id = p_uid;
  if not found or not v_me.home_chosen then return 0; end if;

  -- starter pieces: their allowance is recorded once per life (not capped: a new life starts with new money)
  insert into player_house_grants (user_id, home_key, layout, items, value, move_in, allowance, granted_at)
  select p_uid, 'starter', null,
         jsonb_agg(jsonb_build_object('furniture', pf.furniture_id, 'qty', pf.house_qty)),
         sum(bl_furniture_resale(f2.price, v_pct) * pf.house_qty), null,
         sum(bl_furniture_resale(f2.price, v_pct) * pf.house_qty), bl_now()
    from player_furniture pf join furniture f2 on f2.id = pf.furniture_id
   where pf.user_id = p_uid and pf.source = 'starter' and pf.house_qty > 0
  having count(*) > 0
  on conflict (user_id, home_key) do nothing;

  v_home := coalesce(v_me.start_home, v_me.housing_id);
  if v_home is null then return 0; end if;
  v_layout := bl_home_layout_id(v_me.housing_id);
  -- once per home: claim the row first (a parallel call waits here, then finds it taken)
  insert into player_house_grants (user_id, home_key, layout, move_in, granted_at)
  values (p_uid, v_home, v_layout, p_move_in, bl_now())
  on conflict (user_id, home_key) do nothing;
  if not found then return 0; end if;

  select * into hl from home_layouts where id = v_layout;
  for it in select * from jsonb_array_elements(coalesce(hl.included, '[]'::jsonb)) loop
    select * into f from furniture where id = it->>'furniture' and active;
    continue when not found;
    v_q := null;
    insert into player_furniture (user_id, furniture_id, slot, source, qty, house_qty)
    values (p_uid, f.id, null, 'came_with_house', 1, 1)
    on conflict (user_id, furniture_id) do update
      set qty = player_furniture.qty + 1, house_qty = player_furniture.house_qty + 1
      where player_furniture.qty < 20
    returning qty into v_q;
    continue when v_q is null;
    -- the new copy is the highest number: no other key moves
    v_key := bl_furniture_key(f.id, v_q);
    insert into player_house_furniture (owner_id, furniture_key, x, z, rotation, stored, layout, updated_at)
    values (p_uid, v_key, 0, 0, 0, true, v_layout, bl_now())
    on conflict (owner_id, furniture_key) do update
      set x = 0, z = 0, rotation = 0, stored = true, layout = excluded.layout, updated_at = excluded.updated_at;
    -- its default spot (where the house had it), else the nearest free spot, else My items
    perform bl_furniture_autoplace(p_uid, v_layout, v_key, (it->>'x')::numeric, (it->>'z')::numeric,
                                   coalesce((it->>'rot')::int, 0), true);
    v_n := v_n + 1;
    v_value := v_value + bl_furniture_resale(f.price, v_pct);
    v_items := v_items || jsonb_build_object('furniture', f.id, 'key', v_key, 'name', f.name);
  end loop;

  -- the allowance: at most included_move_cap_pct of the move-in fee paid (the first home: of its move-in fee)
  v_fee := coalesce(p_move_in,
                    (select (h.weekly_rent * coalesce((select (value #>> '{}')::numeric from game_config
                                                        where key = 'house.move_in_weeks'), 4))::bigint
                       from start_homes h where h.id = v_me.start_home), 0);
  update player_house_grants
     set items = v_items, value = v_value,
         allowance = least(v_value, floor(greatest(v_fee, 0) * v_cap / 100.0))::bigint
   where user_id = p_uid and home_key = v_home;
  return v_n;
end $$;
revoke execute on function public.bl_house_items_grant(uuid, bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------- 5. selling
-- What selling one owned copy pays now: {key, id, name, price, included, pct, full, payout, left, capped}.
create or replace function public.bl_furniture_sale_quote(p_uid uuid, p_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  pf     player_furniture;
  f      furniture;
  v_copy int := bl_furniture_copy_of(p_key);
  v_incl boolean;
  v_pct  numeric;
  v_full bigint;
  v_left bigint;
  v_pay  bigint;
begin
  select * into pf from player_furniture where user_id = p_uid and furniture_id = bl_furniture_id_of(p_key);
  if not found or pf.qty < v_copy then return null; end if;
  select * into f from furniture where id = pf.furniture_id;
  v_incl := v_copy > pf.qty - pf.house_qty;
  if v_incl then
    v_pct := bl_included_pct();
    v_full := bl_furniture_resale(f.price, v_pct);
    v_left := bl_house_resale_left(p_uid);
    v_pay := least(v_full, v_left);
  else
    v_pct := greatest(0, least(100, coalesce((select (value #>> '{}')::numeric from game_config
                                               where key = 'furniture.resale_pct'), 45)));
    v_full := bl_furniture_resale(f.price, v_pct);
    v_pay := v_full;
  end if;
  return jsonb_build_object('key', bl_furniture_key(f.id, v_copy), 'id', f.id, 'name', f.name, 'price', f.price,
                            'included', v_incl, 'pct', v_pct, 'full', v_full, 'payout', v_pay,
                            'left', v_left, 'capped', v_incl and v_pay < v_full);
end $$;
revoke execute on function public.bl_furniture_sale_quote(uuid, text) from public, anon, authenticated;

-- The sell dialog asks first. Read-only.
create or replace function public.furniture_sell_quote(p_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
begin
  perform bl_furniture_require_owned(v_uid, p_key);
  return bl_furniture_sale_quote(v_uid, p_key);
end $$;
revoke all on function public.furniture_sell_quote(text) from public, anon;
grant execute on function public.furniture_sell_quote(text) to authenticated, service_role;

-- Sell one owned copy. Bought copy: furniture.resale_pct. Came-with-the-house copy: furniture.included_resale_pct,
-- capped by what the player's house grants still allow. Not while busy; no double payout (L1).
CREATE OR REPLACE FUNCTION public.furniture_sell(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me    profiles := bl_me();
  pf      player_furniture;
  f       furniture;
  v_id    text;
  v_copy  int;
  v_key   text;
  v_last  text;
  v_b     text;
  v_moved text;
  q       jsonb;
  v_incl  boolean;
  v_pct   numeric;
  v_pay   bigint;
  v_cash  bigint;
  v_rest  bigint;
  g       record;
begin
  perform bl_assert_free(v_me);
  if not bl_cfg_bool('furniture.sell_enabled') then
    raise exception 'Selling furniture is paused right now.' using errcode = 'P0001', hint = 'sell_disabled';
  end if;
  perform bl_furniture_require_owned(v_me.id, p_key);
  v_id := bl_furniture_id_of(p_key);
  v_copy := bl_furniture_copy_of(p_key);
  v_key := bl_furniture_key(v_id, v_copy);
  select * into pf from player_furniture where user_id = v_me.id and furniture_id = v_id for update;
  -- L1: a second, parallel sell of the same piece waits on the lock above and then finds the row gone
  -- (or fewer copies than the key names). Refuse it instead of paying out twice.
  if not found or pf.qty < v_copy then
    raise exception 'You don''t have that piece any more.' using errcode = 'P0001', hint = 'not_owned';
  end if;
  select * into f from furniture where id = v_id;
  -- the house allowance is shared by all came-with-house sales: lock the grants too
  perform 1 from player_house_grants where user_id = v_me.id for update;
  q := bl_furniture_sale_quote(v_me.id, v_key);
  v_incl := (q->>'included')::boolean;
  v_pct := (q->>'pct')::numeric;
  v_pay := (q->>'payout')::bigint;
  if v_pay <= 0 then
    if v_incl and (q->>'full')::bigint > 0 then
      raise exception 'The landlord don already collect back wetin you fit make from this house''s things. You fit still keep % or store am.', f.name
        using errcode = 'P0001', hint = 'house_resale_used';
    end if;
    raise exception 'Nobody go buy % from you.', f.name using errcode = 'P0001', hint = 'not_sellable';
  end if;
  -- every copy gets its row first, so the renumbering below sees them all
  perform bl_furniture_materialize(v_me.id);
  delete from player_house_furniture where owner_id = v_me.id and furniture_key = v_key;
  v_last := bl_furniture_key(v_id, pf.qty);
  if not v_incl and pf.house_qty > 0 then
    -- H4: came-with-house copies stay the highest numbers: the last bought copy takes the sold key, the last copy
    -- (came with the house) takes the last bought copy's key
    v_b := bl_furniture_key(v_id, pf.qty - pf.house_qty);
    if v_b <> v_key then
      update player_house_furniture set furniture_key = v_key, updated_at = bl_now()
       where owner_id = v_me.id and furniture_key = v_b;
    end if;
    update player_house_furniture set furniture_key = v_b, updated_at = bl_now()
     where owner_id = v_me.id and furniture_key = v_last;
    v_moved := v_last;
  elsif v_last <> v_key then
    -- the last copy takes the sold key, so the keys stay own_x, own_x-2 ... own_x-(qty-1)
    update player_house_furniture set furniture_key = v_key, updated_at = bl_now()
     where owner_id = v_me.id and furniture_key = v_last;
    v_moved := v_last;
  end if;
  if pf.qty <= 1 then
    delete from player_furniture where user_id = v_me.id and furniture_id = v_id;
  else
    update player_furniture set qty = qty - 1, house_qty = house_qty - case when v_incl then 1 else 0 end
     where user_id = v_me.id and furniture_id = v_id;
  end if;
  if v_incl then
    -- use up the allowance, oldest grant first
    v_rest := v_pay;
    for g in select home_key, allowance - paid as room from player_house_grants
              where user_id = v_me.id and allowance > paid order by granted_at, home_key loop
      exit when v_rest <= 0;
      update player_house_grants set paid = paid + least(v_rest, g.room) where user_id = v_me.id and home_key = g.home_key;
      v_rest := v_rest - least(v_rest, g.room);
    end loop;
  end if;
  v_cash := bl_add_money(v_me.id, 'cash', v_pay, 'furniture_sell',
                         jsonb_build_object('furniture', f.id, 'name', f.name, 'key', v_key, 'price', f.price,
                                            'included', v_incl, 'pct', v_pct));
  return jsonb_build_object(
    'message', 'You sold ' || f.name || ' for ' || bl_naira(v_pay) || '. The buyer don carry am go.',
    'furniture_key', v_key, 'moved_from', v_moved, 'id', f.id, 'name', f.name, 'earned', v_pay,
    'price', f.price, 'resale_pct', v_pct, 'included', v_incl, 'capped', (q->>'capped')::boolean,
    'qty', greatest(pf.qty - 1, 0), 'cash', v_cash);
end $function$;
revoke all on function public.furniture_sell(text) from public, anon;
grant execute on function public.furniture_sell(text) to authenticated, service_role;

-- ---------------------------------------------------------------- live patches
create or replace function pg_temp.h4_patch(p_fn text, p_guard text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  v_def := pg_get_functiondef(p_fn::regprocedure);
  if position(p_guard in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / greatest(length(p_marker), 1);
  if v_n <> 1 then
    raise exception 'H4: marker for % found % times: %', p_fn, v_n, p_marker;
  end if;
  execute replace(v_def, p_marker, p_new);
end $$;

do $mig$
begin
  -- buying: the new bought copy takes the first came-with-the-house number, that copy moves to the end
  perform pg_temp.h4_patch('public.furniture_buy(text)', 'H4: came-with-house copies',
    $m$  v_key := case when v_qty = 1 then 'own_' || f.id else 'own_' || f.id || '-' || v_qty end;$m$,
    $m$  v_key := case when v_qty = 1 then 'own_' || f.id else 'own_' || f.id || '-' || v_qty end;
  -- H4: came-with-house copies stay the highest numbers
  if coalesce((select house_qty from player_furniture where user_id = v_uid and furniture_id = f.id), 0) > 0 then
    delete from player_house_furniture where owner_id = v_uid and furniture_key = v_key;
    v_key := (select bl_furniture_key(f.id, qty - house_qty) from player_furniture where user_id = v_uid and furniture_id = f.id);
    update player_house_furniture set furniture_key = bl_furniture_key(f.id, v_qty), updated_at = bl_now()
     where owner_id = v_uid and furniture_key = v_key;
  end if;$m$);

  -- safety net: whatever path changed the home, the first furniture action gives its pieces
  perform pg_temp.h4_patch('public.bl_furniture_materialize(uuid)', 'bl_house_items_grant(',
    $m$  select bl_home_layout_id(housing_id) into v_layout from profiles where id = p_uid;$m$,
    $m$  perform bl_house_items_grant(p_uid); -- H4: the home's pieces, once per home
  select bl_home_layout_id(housing_id) into v_layout from profiles where id = p_uid;$m$);

  -- moving house: the new home's pieces stand at their spots before the old furniture is placed around them;
  -- the allowance is capped by the move-in fee just paid
  perform pg_temp.h4_patch('public.house_move(text)', 'bl_house_items_grant(',
    $m$  if hl.id is not null then
    -- pieces with a default slot first$m$,
    $m$  perform bl_house_items_grant(v_me.id, v_cost); -- H4: what this home comes with, once
  if hl.id is not null then
    -- pieces with a default slot first$m$);
  perform pg_temp.h4_patch('public.house_move(text)', $g$'came_with'$g$,
    $m$'placed', v_placed,$m$,
    $m$'came_with', coalesce((select jsonb_array_length(g.items) from player_house_grants g
                              where g.user_id = v_me.id and g.home_key = h.id), 0), 'placed', v_placed,$m$);

  -- first home: starter pieces, then the home's pieces
  perform pg_temp.h4_patch('public.bl_profiles_furnish()', 'bl_house_items_grant(',
    $m$    perform bl_give_starter_furniture(new.id);$m$,
    $m$    perform bl_give_starter_furniture(new.id);
    perform bl_house_items_grant(new.id);$m$);
end $mig$;

-- ---------------------------------------------------------------- existing players
-- Everyone gets their current home's pieces now, at the spots the built-ins stood (nothing of theirs can be there:
-- the built-ins blocked those spots until now). A player who moved into the home (released an earlier one) gets
-- the move-in cap, using the move-in fee in their ledger (else the home's current fee).
do $mig$
declare r record; v_fee bigint; v_weeks numeric;
begin
  v_weeks := coalesce((select (value #>> '{}')::numeric from public.game_config where key = 'house.move_in_weeks'), 4);
  for r in select p.id, p.start_home, h.weekly_rent
             from public.profiles p left join public.start_homes h on h.id = p.start_home
            where p.home_chosen
              and not exists (select 1 from public.player_house_grants g
                               where g.user_id = p.id and g.home_key = coalesce(p.start_home, p.housing_id)) loop
    v_fee := null;
    if exists (select 1 from public.player_released_homes rh where rh.user_id = r.id) then
      select nullif(-sum(l.delta), 0) into v_fee from public.ledger l
       where l.user_id = r.id and l.reason = 'house_move' and l.meta->>'home' = r.start_home;
      v_fee := coalesce(v_fee, (coalesce(r.weekly_rent, 0) * v_weeks)::bigint);
    end if;
    perform public.bl_house_items_grant(r.id, v_fee);
  end loop;
end $mig$;

notify pgrst, 'reload schema';
