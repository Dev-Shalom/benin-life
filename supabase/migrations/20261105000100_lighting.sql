-- L1 Home lighting (docs/HUD_HOME.md "Lighting", docs/FURNITURE_CATALOGUE.md "Lighting").
--   1. furniture gets brightness (0-10), warmth (kelvin) and works_without_power; category 'lighting'.
--   2. 14 new light fixtures (real Benin City 2026 naira prices) + the four lights that were already in the
--      catalogue (floor lamp, bedside lamp, crystal chandelier, floodlight pole) move into the Lighting category.
--   3. home_layouts.lights: the lights each home comes with (a bulb in EVERY room, richer homes get more).
--      Generated from src/art/home3d/model.ts: `node scripts/home-space-check.mjs --lights-sql`.
--   4. bl_house_lights_grant: gives them as real furniture copies ('came_with_house'), ONCE per (player, home)
--      and once per finished extension room. LAZY: it runs from bl_house_items_grant (every furniture action,
--      moving house, first home) and house_upgrade_state (sign-in). There is NO loop over players here: the
--      statement timeout on the live database is ~2 minutes and a loop over all players killed an earlier deploy.
--      A player who already has a home simply gets the new lights the next time one of those runs for them.
--   Nothing on profiles, no triggers, no foreign keys. Idempotent: every statement is create-if-not-exists,
--   on conflict do nothing, or a guarded patch (pg_get_functiondef + marker).

-- ---------------------------------------------------------------- 1. columns
alter table public.furniture add column if not exists brightness numeric(3,1) not null default 0;
alter table public.furniture add column if not exists warmth integer not null default 0;
alter table public.furniture add column if not exists works_without_power boolean not null default false;
alter table public.furniture drop constraint if exists furniture_brightness_check;
alter table public.furniture add constraint furniture_brightness_check check (brightness >= 0 and brightness <= 10);
alter table public.furniture drop constraint if exists furniture_warmth_check;
alter table public.furniture add constraint furniture_warmth_check check (warmth = 0 or (warmth >= 1000 and warmth <= 10000));
alter table public.furniture drop constraint if exists furniture_category_check;
alter table public.furniture add constraint furniture_category_check
  check (category in ('living', 'bedroom', 'kitchen', 'bathroom', 'utility', 'decor', 'lighting'));

alter table public.home_layouts add column if not exists lights jsonb not null default '[]'::jsonb;

-- ---------------------------------------------------------------- 2. catalogue
-- prices: Jumia / Jiji / Alaba market, Benin City, 2026 (estimates; edit in Admin -> Content -> Furniture)
insert into public.furniture
  (id, name, emoji, kind, slot, activities, rest_pct, color, description, sort,
   price, tier, category, w, d, solid, placement, max_qty, bonus, brightness, warmth, works_without_power)
values
  ('bulb_holder', 'Bulb holder with bulb', '💡', 'bulb_holder', 'none', '{}'::text[], 100, null, 'Holder, wire and one 9W LED bulb. Small light, big difference.', 1000, 1500, 'lapo', 'lighting', 0.3, 0.3, false, 'in', 20, '{}'::jsonb, 3, 2700, false),
  ('bulb_energy', 'Energy-saving bulb (20W)', '💡', 'bulb_energy', 'none', '{}'::text[], 100, null, 'Energy saver in a holder. Brighter than the small bulb and e no dey drink NEPA.', 1010, 3500, 'lapo', 'lighting', 0.3, 0.3, false, 'in', 12, '{}'::jsonb, 4, 4000, false),
  ('bulb_rechargeable', 'Rechargeable bulb (emergency)', '🔋', 'bulb_recharge', 'none', '{}'::text[], 100, null, 'Battery inside the bulb. NEPA take light? E still dey shine for hours.', 1020, 4500, 'lapo', 'lighting', 0.3, 0.3, false, 'in', 8, '{}'::jsonb, 3, 5000, true),
  ('tube_light', 'Fluorescent tube light (4ft)', '📏', 'tube_light', 'none', '{}'::text[], 100, null, 'Long white tube for the kitchen or passage. Cool, bright and plain.', 1030, 7500, 'lapo', 'lighting', 1.25, 0.16, false, 'in', 8, '{}'::jsonb, 6, 6000, false),
  ('ceiling_light', 'LED ceiling light (flush)', '🔆', 'ceiling_light', 'none', '{}'::text[], 100, null, 'Flat round LED panel on the POP ceiling. Clean, even light.', 1040, 14000, 'mid', 'lighting', 0.6, 0.6, false, 'in', 12, '{}'::jsonb, 6, 3500, false),
  ('led_strip', 'LED strip lights (5 m, remote)', '🌈', 'led_strip', 'none', '{}'::text[], 100, null, 'Stick am for the ceiling edge. Warm glow, remote control, instant owambe.', 1050, 12000, 'mid', 'lighting', 2.0, 0.06, false, 'wall', 6, '{}'::jsonb, 3, 3000, false),
  ('table_lamp', 'Table lamp', '🪔', 'table_lamp', 'none', '{}'::text[], 100, null, 'Fabric shade. Put am on a table or shelf and the whole corner go soften.', 1060, 16000, 'mid', 'lighting', 0.3, 0.3, false, 'any', 6, '{}'::jsonb, 3, 2700, false),
  ('wall_light', 'Wall light (bracket)', '💡', 'wall_light', 'none', '{}'::text[], 100, null, 'Brass bracket light for the passage or the parlour wall.', 1070, 18000, 'mid', 'lighting', 0.26, 0.14, false, 'wall', 8, '{}'::jsonb, 3, 2700, false),
  ('chandelier_modern', 'Pendant chandelier', '✨', 'pendant_chandelier', 'none', '{}'::text[], 100, null, 'Modern glass pendants. Make the parlour look like a show house.', 1080, 185000, 'mid', 'lighting', 0.8, 0.8, false, 'in', 4, '{}'::jsonb, 7, 3000, false),
  ('yard_lamp', 'Garden lamp post', '🏮', 'yard_lamp', 'none', '{}'::text[], 100, null, 'Low lamp post for the compound. Your gate go look like estate.', 1090, 28000, 'mid', 'lighting', 0.3, 0.3, true, 'out', 6, '{}'::jsonb, 4, 3000, false),
  ('lamp_rechargeable', 'Rechargeable lamp (LED)', '🔦', 'lamp_recharge', 'none', '{}'::text[], 100, null, 'Charge am when light dey, use am when NEPA take am. About 8 hours.', 1100, 9500, 'lapo', 'lighting', 0.22, 0.22, false, 'any', 6, '{}'::jsonb, 4, 5000, true),
  ('lantern', 'Hurricane lantern', '🏮', 'lantern', 'none', '{}'::text[], 100, null, 'Old-school kerosene lantern. Dim, warm and never fails.', 1110, 6500, 'lapo', 'lighting', 0.22, 0.22, false, 'any', 6, '{}'::jsonb, 2, 2200, true),
  ('candle', 'Candles (pack of 6)', '🕯️', 'candle', 'none', '{}'::text[], 100, null, 'Small flame, small light. For romance or when NEPA dey do their wonders.', 1120, 1500, 'lapo', 'lighting', 0.12, 0.12, false, 'any', 8, '{}'::jsonb, 1, 1900, true)
on conflict (id) do nothing;

-- the four lights that were already for sale join the Lighting category (first run only: once they are in it,
-- admin edits to their price, brightness or warmth are never overwritten)
update public.furniture set category = 'lighting', brightness = 4, warmth = 2700, sort = 1130 where id = 'lamp_floor' and category <> 'lighting';
update public.furniture set category = 'lighting', brightness = 2, warmth = 2700, sort = 1140, name = 'Bedside lamp',
       solid = false, placement = 'any', description = 'Soft light for night reading. Stands on the bedside table.'
 where id = 'lamp_bedside' and category <> 'lighting';
update public.furniture set category = 'lighting', brightness = 9, warmth = 2700, sort = 1150 where id = 'chandelier' and category <> 'lighting';
update public.furniture set category = 'lighting', brightness = 7, warmth = 5500, sort = 1160, max_qty = 6, name = 'Security floodlight pole'
 where id = 'gate_light' and category <> 'lighting';

-- ---------------------------------------------------------------- 3. the lights each home comes with
-- generated: node scripts/home-space-check.mjs --lights-sql
update public.home_layouts h set lights = v.lights
  from (values
  ('hostel', '[{"id":"lt_room","furniture":"bulb_holder","kind":"bulb_holder","x":3.1,"z":2.1,"rot":0}]'::jsonb),
  ('face_me', '[{"id":"lt_room","furniture":"bulb_holder","kind":"bulb_holder","x":3.4,"z":2.6,"rot":0}]'::jsonb),
  ('self_contain', '[{"id":"lt_bath","furniture":"bulb_holder","kind":"bulb_holder","x":1.3,"z":1.3,"rot":0},{"id":"lt_kitchen","furniture":"bulb_holder","kind":"bulb_holder","x":4.8,"z":1.4,"rot":0},{"id":"lt_bed","furniture":"bulb_holder","kind":"bulb_holder","x":7,"z":2.6,"rot":0},{"id":"lt_sit","furniture":"bulb_energy","kind":"bulb_energy","x":3,"z":5,"rot":0}]'::jsonb),
  ('flat', '[{"id":"lt_bed","furniture":"ceiling_light","kind":"ceiling_light","x":2.5,"z":2.2,"rot":0},{"id":"lt_kitchen","furniture":"tube_light","kind":"tube_light","x":7.1,"z":1.7,"rot":0},{"id":"lt_bath","furniture":"bulb_holder","kind":"bulb_holder","x":11.1,"z":1.6,"rot":0},{"id":"lt_parlour","furniture":"chandelier_modern","kind":"pendant_chandelier","x":4.9,"z":6.9,"rot":0},{"id":"lt_dining","furniture":"ceiling_light","kind":"ceiling_light","x":10.4,"z":6.8,"rot":0},{"id":"lt_wall1","furniture":"wall_light","kind":"wall_light","x":0.1,"z":5,"rot":1},{"id":"lt_wall2","furniture":"wall_light","kind":"wall_light","x":0.1,"z":8.8,"rot":1},{"id":"lt_gate","furniture":"gate_light","kind":"gate_light","x":14.6,"z":10.3,"rot":0}]'::jsonb),
  ('duplex', '[{"id":"lt_master","furniture":"ceiling_light","kind":"ceiling_light","x":3,"z":2.5,"rot":0},{"id":"lt_mwall","furniture":"wall_light","kind":"wall_light","x":0.1,"z":3.3,"rot":1},{"id":"lt_mstrip","furniture":"led_strip","kind":"led_strip","x":3.2,"z":0.05,"rot":0},{"id":"lt_kit1","furniture":"tube_light","kind":"tube_light","x":8,"z":2.2,"rot":0},{"id":"lt_kit2","furniture":"tube_light","kind":"tube_light","x":10.4,"z":2.2,"rot":0},{"id":"lt_bath","furniture":"bulb_energy","kind":"bulb_energy","x":13.8,"z":1.8,"rot":0},{"id":"lt_laundry","furniture":"bulb_holder","kind":"bulb_holder","x":17.2,"z":1.8,"rot":0},{"id":"lt_study","furniture":"ceiling_light","kind":"ceiling_light","x":17.1,"z":8.2,"rot":0},{"id":"lt_parlour","furniture":"ceiling_light","kind":"ceiling_light","x":6.6,"z":8,"rot":0},{"id":"lt_pwall1","furniture":"wall_light","kind":"wall_light","x":0.1,"z":8.6,"rot":1},{"id":"lt_pwall2","furniture":"wall_light","kind":"wall_light","x":0.1,"z":11.4,"rot":1},{"id":"lt_standing","furniture":"lamp_floor","kind":"lamp","x":0.45,"z":12.9,"rot":0},{"id":"lt_hall","furniture":"chandelier_modern","kind":"pendant_chandelier","x":8,"z":6.4,"rot":0},{"id":"lt_lobby","furniture":"ceiling_light","kind":"ceiling_light","x":7.7,"z":12,"rot":0},{"id":"lt_dining","furniture":"ceiling_light","kind":"ceiling_light","x":11.4,"z":11.4,"rot":0},{"id":"lt_guest","furniture":"ceiling_light","kind":"ceiling_light","x":16.3,"z":11.6,"rot":0},{"id":"lt_gbed","furniture":"lamp_bedside","kind":"lamp_small","x":18.5,"z":10.4,"rot":0},{"id":"lt_gate","furniture":"gate_light","kind":"gate_light","x":20.8,"z":4.2,"rot":0},{"id":"lt_yard1","furniture":"yard_lamp","kind":"yard_lamp","x":-0.6,"z":14.8,"rot":0},{"id":"lt_yard2","furniture":"yard_lamp","kind":"yard_lamp","x":12,"z":15.2,"rot":0}]'::jsonb)
  ) as v(id, lights)
 where h.id = v.id;

-- every light a home gives must be a catalogue row of the same 3D kind (the client draws the owned copy by kind)
do $mig$
declare v text;
begin
  select string_agg(i->>'furniture', ', ') into v
    from public.home_layouts hl, jsonb_array_elements(hl.lights) i
   where not exists (select 1 from public.furniture f where f.id = i->>'furniture' and f.kind = i->>'kind' and f.category = 'lighting');
  if v is not null then raise exception 'lighting: home lights missing from the Lighting catalogue: %', v; end if;
end $mig$;

-- ---------------------------------------------------------------- 4. giving the lights (lazy, idempotent)
-- One light as a came-with-the-house copy, standing at x/z (else the nearest free spot, else My items).
-- Returns the placement key, null when the player already owns the maximum of that piece.
create or replace function public.bl_house_light_give(p_uid uuid, p_layout text, p_furniture text, p_x numeric, p_z numeric, p_rot integer) returns text
language plpgsql security definer set search_path = public as $$
declare f furniture; v_q int; v_key text;
begin
  select * into f from furniture where id = p_furniture and active;
  if not found then return null; end if;
  v_q := null;
  insert into player_furniture (user_id, furniture_id, slot, source, qty, house_qty)
  values (p_uid, f.id, null, 'came_with_house', 1, 1)
  on conflict (user_id, furniture_id) do update
    set qty = player_furniture.qty + 1, house_qty = player_furniture.house_qty + 1
    where player_furniture.qty < 20
  returning qty into v_q;
  if v_q is null then return null; end if;
  -- the new copy is the highest number: no other key moves
  v_key := bl_furniture_key(f.id, v_q);
  insert into player_house_furniture (owner_id, furniture_key, x, z, rotation, stored, layout, updated_at)
  values (p_uid, v_key, 0, 0, 0, true, p_layout, bl_now())
  on conflict (owner_id, furniture_key) do update
    set x = 0, z = 0, rotation = 0, stored = true, layout = excluded.layout, updated_at = excluded.updated_at;
  perform bl_furniture_autoplace(p_uid, p_layout, v_key, p_x, p_z, coalesce(p_rot, 0), true);
  return v_key;
end $$;
revoke execute on function public.bl_house_light_give(uuid, text, text, numeric, numeric, integer) from public, anon, authenticated;

-- A home's lights, once per home (grant row '<home>#lights', value and allowance 0: the lights never add to the
-- resale allowance), and one bulb (two in a long wing) per finished extension room, once per upgrade.
-- Cheap when nothing is due: two primary-key lookups.
create or replace function public.bl_house_lights_grant(p_uid uuid, p_home text, p_layout text) returns integer
language plpgsql security definer set search_path = public as $$
declare
  hl      home_layouts;
  it      jsonb;
  u       record;
  v_key   text;
  v_items jsonb := '[]'::jsonb;
  v_n     int := 0;
  v_fid   text := case when p_layout in ('flat', 'duplex') then 'ceiling_light' else 'bulb_holder' end;
  r       jsonb;
  v_w     numeric;
  v_cnt   int;
  i       int;
begin
  if p_home is null or p_layout is null then return 0; end if;

  insert into player_house_grants (user_id, home_key, layout, items, value, allowance, granted_at)
  values (p_uid, p_home || '#lights', p_layout, '[]'::jsonb, 0, 0, bl_now())
  on conflict (user_id, home_key) do nothing;
  if found then
    select * into hl from home_layouts where id = p_layout;
    for it in select * from jsonb_array_elements(coalesce(hl.lights, '[]'::jsonb)) loop
      v_key := bl_house_light_give(p_uid, p_layout, it->>'furniture', (it->>'x')::numeric, (it->>'z')::numeric, coalesce((it->>'rot')::int, 0));
      continue when v_key is null;
      v_n := v_n + 1;
      v_items := v_items || jsonb_build_object('furniture', it->>'furniture', 'key', v_key);
    end loop;
    update player_house_grants set items = v_items where user_id = p_uid and home_key = p_home || '#lights';
  end if;

  -- extension rooms (finished upgrades with a room on this plan)
  for u in
    select pu.upgrade_id, hu.effect -> 'geom' -> p_layout -> 'room' as room
      from player_house_upgrades pu
      join house_upgrades hu on hu.id = pu.upgrade_id
     where pu.user_id = p_uid and pu.done_at is not null and hu.effect -> 'geom' -> p_layout ? 'room'
  loop
    insert into player_house_grants (user_id, home_key, layout, items, value, allowance, granted_at)
    values (p_uid, p_home || '#light:' || u.upgrade_id, p_layout, '[]'::jsonb, 0, 0, bl_now())
    on conflict (user_id, home_key) do nothing;
    continue when not found;
    r := u.room -> 'rect';
    v_w := (r->>2)::numeric - (r->>0)::numeric;
    v_cnt := case when v_w > 6 then 2 else 1 end;
    v_items := '[]'::jsonb;
    for i in 1 .. v_cnt loop
      v_key := bl_house_light_give(p_uid, p_layout, v_fid,
                 round((r->>0)::numeric + v_w * i / (v_cnt + 1), 2),
                 round(((r->>1)::numeric + (r->>3)::numeric) / 2, 2), 0);
      continue when v_key is null;
      v_n := v_n + 1;
      v_items := v_items || jsonb_build_object('furniture', v_fid, 'key', v_key);
    end loop;
    update player_house_grants set items = v_items where user_id = p_uid and home_key = p_home || '#light:' || u.upgrade_id;
  end loop;
  return v_n;
end $$;
revoke execute on function public.bl_house_lights_grant(uuid, text, text) from public, anon, authenticated;

-- sign-in entry point: the player's current home (nothing for someone without a home, or visiting is irrelevant:
-- this only ever touches the caller's own home)
create or replace function public.bl_house_lights_for(p_uid uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare v_me profiles;
begin
  select * into v_me from profiles where id = p_uid;
  if not found or not v_me.home_chosen then return 0; end if;
  return public.bl_house_lights_grant(p_uid, coalesce(v_me.start_home, v_me.housing_id), bl_home_layout_id(v_me.housing_id));
end $$;
revoke execute on function public.bl_house_lights_for(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- 5. hooks (guarded: skipped when already applied,
-- an error when the function changed shape)
create or replace function pg_temp.l1_patch(p_fn regprocedure, p_guard text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  v_def := pg_get_functiondef(p_fn);
  if position(p_guard in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / greatest(length(p_marker), 1);
  if v_n <> 1 then raise exception 'lighting: anchor for % found % times: %', p_fn, v_n, p_marker; end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- every call of the home items grant (first home, moving, any furniture action) also gives the lights it is missing
select pg_temp.l1_patch('public.bl_house_items_grant(uuid,bigint)'::regprocedure, 'bl_house_lights_grant(',
  E'  v_layout := bl_home_layout_id(v_me.housing_id);\n',
  E'  v_layout := bl_home_layout_id(v_me.housing_id);\n  perform bl_house_lights_grant(p_uid, v_home, v_layout); -- L1: the home''s lights, once per home\n');

-- sign-in: the home screen reads this first, so the lights are there when the room opens (and after a build finishes)
select pg_temp.l1_patch('public.house_upgrade_state()'::regprocedure, 'bl_house_lights_for(',
  E'  select * into v_me from profiles where id = v_me.id; -- a finished tier upgrade changed the home\n',
  E'  select * into v_me from profiles where id = v_me.id; -- a finished tier upgrade changed the home\n  perform public.bl_house_lights_for(v_me.id); -- L1: lights of this home and of finished extension rooms, once\n');

notify pgrst, 'reload schema';
