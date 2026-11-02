-- L1 home lighting (20261112000100_lighting.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/lighting_test.sql
-- Groups: 1 catalogue rows, prices, flags · 2 home_layouts.lights and the 3D kind rule · 3 built-ins per home type ·
-- 4 buying and placing a light, placement rules · 5 lazy grant for an existing player, idempotent re-run ·
-- 6 extension rooms get a bulb once · 7 grants / RLS.
create or replace function pg_temp.hint_of(p_sql text) returns text
language plpgsql as $$
declare v_h text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  get stacked diagnostics v_h = pg_exception_hint;
  return coalesce(nullif(v_h, ''), sqlerrm);
end $$;

create or replace function pg_temp.all_valid(p_uid uuid) returns boolean
language sql as $$
  select coalesce(bool_and(bl_furniture_check(h.owner_id, h.layout, h.furniture_key, h.x, h.z, h.rotation) is null), true)
    from player_house_furniture h where h.owner_id = p_uid and not h.stored
     and h.furniture_key not like 'own_drum_bucket%'  -- the LAPO bathing corner stands in the compound by design
$$;

-- light copies a player owns that came with the house
create or replace function pg_temp.light_qty(p_uid uuid) returns integer
language sql as $$
  select coalesce(sum(pf.house_qty), 0)::int from player_furniture pf join furniture f on f.id = pf.furniture_id
   where pf.user_id = p_uid and f.category = 'lighting' and pf.source = 'came_with_house'
$$;

-- ---------- 1. catalogue ----------
do $$
declare v_kinds text[] := array['bulb_holder','bulb_energy','bulb_recharge','ceiling_light','tube_light','led_strip','table_lamp','wall_light',
                                'pendant_chandelier','yard_lamp','lamp_recharge','lantern','candle','lamp','lamp_small','chandelier','gate_light'];
begin
  perform pg_temp.assert((select count(*) from furniture where category = 'lighting') = 17, '17 lighting pieces');
  perform pg_temp.assert(not exists (select 1 from furniture where category = 'lighting' and not (kind = any (v_kinds))), 'every lighting kind is a known 3D light kind');
  perform pg_temp.assert(not exists (select 1 from furniture where category = 'lighting' and (brightness <= 0 or brightness > 10 or warmth < 1000 or price <= 0)),
                         'every light has brightness, warmth and a price');
  perform pg_temp.assert((select price from furniture where id = 'bulb_holder') = 1500, 'bulb holder N1,500');
  perform pg_temp.assert((select price from furniture where id = 'bulb_energy') = 3500, 'energy-saving bulb N3,500');
  perform pg_temp.assert((select price from furniture where id = 'tube_light') = 7500, 'tube light N7,500');
  perform pg_temp.assert((select price from furniture where id = 'ceiling_light') = 14000, 'ceiling light N14,000');
  perform pg_temp.assert((select price from furniture where id = 'chandelier_modern') = 185000, 'pendant chandelier N185,000');
  perform pg_temp.assert((select price from furniture where id = 'chandelier') = 950000, 'crystal chandelier keeps its price');
  perform pg_temp.assert((select price from furniture where id = 'lamp_rechargeable') = 9500, 'rechargeable lamp N9,500');
  perform pg_temp.assert((select price from furniture where id = 'candle') = 1500, 'candles N1,500');
  -- works without power: exactly the battery / flame ones
  perform pg_temp.assert((select array_agg(id order by id) from furniture where works_without_power)
                         = array['bulb_rechargeable','candle','lamp_rechargeable','lantern'], 'works_without_power is the rechargeable lamp, battery bulb, lantern and candle');
  perform pg_temp.assert(not (select works_without_power from furniture where id = 'ceiling_light'), 'a ceiling light needs power');
  -- placement rules mirror the 3D kinds
  perform pg_temp.assert((select placement from furniture where id = 'wall_light') = 'wall' and (select placement from furniture where id = 'led_strip') = 'wall', 'wall lights hang on a wall');
  perform pg_temp.assert((select placement from furniture where id = 'yard_lamp') = 'out' and (select placement from furniture where id = 'gate_light') = 'out', 'yard lights stand outside');
  perform pg_temp.assert((select placement from furniture where id = 'bulb_holder') = 'in' and (select placement from furniture where id = 'ceiling_light') = 'in', 'ceiling lights are inside');
  perform pg_temp.assert((select placement from furniture where id = 'table_lamp') = 'any' and (select placement from furniture where id = 'lantern') = 'any', 'table lights go anywhere');
  perform pg_temp.assert(not exists (select 1 from furniture where category = 'lighting' and solid and id not in ('lamp_floor', 'yard_lamp', 'gate_light')), 'only standing lamps and yard posts are solid');
  perform pg_temp.assert(not exists (select 1 from furniture where active and buyable and category = 'lighting' and max_qty < 2), 'lights can be owned several times');
  perform pg_temp.assert((select count(distinct category) from furniture where active) = 7, 'seven shop rooms now');
  -- rows are admin-editable: a re-run of the migration keeps the edit
  update furniture set price = 1750, brightness = 3.5 where id = 'bulb_holder';
  perform pg_temp.assert((select price from furniture where id = 'bulb_holder') = 1750, 'admin edits the price');
end $$;

-- ---------- 2. home_layouts.lights ----------
do $$
declare r record;
begin
  perform pg_temp.assert((select jsonb_array_length(lights) from home_layouts where id = 'hostel') = 1, 'hostel: one bulb');
  perform pg_temp.assert((select jsonb_array_length(lights) from home_layouts where id = 'face_me') = 1, 'face-me: one bulb');
  perform pg_temp.assert((select jsonb_array_length(lights) from home_layouts where id = 'self_contain') = 4, 'self-contain: a light in each of its 4 rooms');
  perform pg_temp.assert((select jsonb_array_length(lights) from home_layouts where id = 'flat') = 8, 'flat: 8 lights');
  perform pg_temp.assert((select jsonb_array_length(lights) from home_layouts where id = 'duplex') = 20, 'duplex: 20 lights');
  -- every plan has a ceiling light (the 3D "bulb in the room" kinds)
  for r in select id, lights from home_layouts loop
    perform pg_temp.assert((select count(*) from jsonb_array_elements(r.lights) i where i->>'kind' in ('bulb_holder','bulb_energy','bulb_recharge','ceiling_light','tube_light','pendant_chandelier','chandelier')) >= 1,
                           r.id || ' has a ceiling light');
  end loop;
  -- every included piece (old and new) must be a catalogue row of the same 3D kind
  perform pg_temp.assert(not exists (select 1 from home_layouts hl, jsonb_array_elements(hl.included || hl.lights) i
                                      where not exists (select 1 from furniture f where f.id = i->>'furniture' and f.kind = i->>'kind')),
                         'every included piece and light is a catalogue row of the same 3D kind');
  perform pg_temp.assert(not exists (select 1 from home_layouts hl, jsonb_array_elements(hl.lights) i
                                      where not exists (select 1 from furniture f where f.id = i->>'furniture' and f.category = 'lighting')),
                         'every light a home gives is in the Lighting category');
  -- the richer homes are brighter
  perform pg_temp.assert((select coalesce(sum(f.brightness), 0) from home_layouts hl, jsonb_array_elements(hl.lights) i join furniture f on f.id = i->>'furniture' where hl.id = 'duplex')
                         > (select coalesce(sum(f.brightness), 0) from home_layouts hl, jsonb_array_elements(hl.lights) i join furniture f on f.id = i->>'furniture' where hl.id = 'flat')
                       and (select coalesce(sum(f.brightness), 0) from home_layouts hl, jsonb_array_elements(hl.lights) i join furniture f on f.id = i->>'furniture' where hl.id = 'flat')
                         > (select coalesce(sum(f.brightness), 0) from home_layouts hl, jsonb_array_elements(hl.lights) i join furniture f on f.id = i->>'furniture' where hl.id = 'self_contain'),
                         'duplex > flat > self-contain in total brightness');
  perform pg_temp.assert(exists (select 1 from home_layouts hl, jsonb_array_elements(hl.lights) i where hl.id = 'duplex' and i->>'furniture' = 'gate_light')
                     and exists (select 1 from home_layouts hl, jsonb_array_elements(hl.lights) i where hl.id = 'flat' and i->>'furniture' = 'gate_light')
                     and exists (select 1 from home_layouts hl, jsonb_array_elements(hl.lights) i where hl.id = 'duplex' and i->>'furniture' = 'wall_light'),
                         'flat and duplex come with yard security lights, the duplex with wall lights');
  -- the crystal chandelier stays a duplex built-in (included), not a light grant
  perform pg_temp.assert(exists (select 1 from home_layouts hl, jsonb_array_elements(hl.included) i where hl.id = 'duplex' and i->>'furniture' = 'chandelier'), 'duplex still comes with the crystal chandelier');
end $$;

-- ---------- 3. built-ins per home type ----------
do $$
declare v_homes text[][] := array[['uniben_hostel','hostel'],['ekenwan_face_me','face_me'],['uselu_self_contain','self_contain'],['mission_rd_mini_flat','flat'],['gra_duplex','duplex']];
        i int; u uuid; v_exp int; v_home text; v_lay text;
begin
  update game_config set value = 'true' where key in ('furniture.sell_enabled', 'house.move_enabled');
  for i in 1 .. array_length(v_homes, 1) loop
    v_home := v_homes[i][1]; v_lay := v_homes[i][2];
    u := pg_temp.new_user('l1_' || v_lay || '@light.bl');
    update game_config set value = case when v_lay in ('flat', 'duplex') then '"nepo"'::jsonb else '"lapo"'::jsonb end where key = 'origin.force_next';
    perform pg_temp.login(u);
    perform create_profile_v2('L1_' || v_lay, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home(v_home);
    -- the lights column plus any lighting piece in `included` (the duplex's crystal chandelier)
    select jsonb_array_length(hl.lights) + (select count(*) from jsonb_array_elements(hl.included) inc join furniture f on f.id = inc->>'furniture' where f.category = 'lighting')
      into v_exp from home_layouts hl where hl.id = v_lay;
    perform pg_temp.assert(pg_temp.light_qty(u) = v_exp, v_lay || ': ' || v_exp || ' lights came with the home, got ' || pg_temp.light_qty(u));
    perform pg_temp.assert(not exists (select 1 from player_house_furniture h join furniture f on f.id = bl_furniture_id_of(h.furniture_key)
                                        where h.owner_id = u and f.category = 'lighting' and h.stored), v_lay || ': every light is placed, none waits in My items');
    perform pg_temp.assert(pg_temp.all_valid(u), v_lay || ': every placed piece passes the server rule');
    perform pg_temp.assert(exists (select 1 from player_house_grants where user_id = u and home_key like '%#lights'), v_lay || ': one grant row for the lights');
    perform set_config('l1.' || v_lay, u::text, true);
  end loop;
end $$;

-- ---------- 4. buy and place a light ----------
do $$
declare u uuid := current_setting('l1.face_me')::uuid; r jsonb; v_key text; v_cash bigint;
begin
  perform pg_temp.login(u);
  update profiles set cash = 200000, rent_owed = 0, busy_until = null, travel_to = null, location_id = home_location_id where id = u;
  r := furniture_buy('lamp_rechargeable');
  v_key := r->>'furniture_key';
  perform pg_temp.assert(v_key = 'own_lamp_rechargeable', 'bought the rechargeable lamp: ' || v_key);
  -- the usual furniture VAT (7.5 %) applies on top of the catalogue price
  perform pg_temp.assert(200000 - (select cash from profiles where id = u) between 9500 and 9500 * 1.08, 'paid the price plus VAT, cash is ' || (select cash from profiles where id = u));
  perform pg_temp.assert(pg_temp.hint_of(format('select furniture_place(%L, 3.0, 2.0, 0)', v_key)) = 'ok', 'placed on the floor / a table inside the room');
  perform pg_temp.assert(not (select stored from player_house_furniture where owner_id = u and furniture_key = v_key), 'it stands in the room');
  -- candles can go in the yard too
  perform furniture_buy('candle');
  perform pg_temp.assert(pg_temp.hint_of('select furniture_place(''own_candle'', 8.5, 4.0, 0)') = 'ok', 'a candle may stand in the compound');
  -- wall light: only against the north / west wall
  perform furniture_buy('wall_light');
  perform pg_temp.assert(pg_temp.hint_of('select furniture_place(''own_wall_light'', 3.0, 3.0, 0)') = 'not_on_wall', 'a wall light in mid-room is refused');
  perform pg_temp.assert(pg_temp.hint_of('select furniture_place(''own_wall_light'', 4.0, 0.07, 0)') = 'ok', 'a wall light on the back wall is fine');
  -- garden lamp: outside only
  perform furniture_buy('yard_lamp');
  perform pg_temp.assert(pg_temp.hint_of('select furniture_place(''own_yard_lamp'', 3.0, 3.0, 0)') = 'outside_home', 'a garden lamp inside the house is refused');
  perform pg_temp.assert(pg_temp.hint_of('select furniture_place(''own_yard_lamp'', 8.6, 5.0, 0)') = 'ok', 'a garden lamp in the compound is fine');
  -- a ceiling light must stay inside the house
  perform furniture_buy('ceiling_light');
  perform pg_temp.assert(pg_temp.hint_of('select furniture_place(''own_ceiling_light'', 9.0, 5.0, 0)') = 'outside_home', 'a ceiling light outside is refused');
  perform pg_temp.assert(pg_temp.hint_of('select furniture_place(''own_ceiling_light'', 2.0, 4.5, 0)') = 'ok', 'a ceiling light inside is fine');
  -- the second bulb holder is a second copy (own_bulb_holder-2: the home's came first)
  perform furniture_buy('bulb_holder');
  perform pg_temp.assert((select qty from player_furniture where user_id = u and furniture_id = 'bulb_holder') = 2, 'two bulb holders now (built-in + bought)');
  perform pg_temp.assert(pg_temp.all_valid(u), 'everything still passes the server rule');
end $$;

-- ---------- 5. lazy grant for an existing player ----------
do $$
declare u uuid := current_setting('l1.flat')::uuid; v_n int; v_exp int;
begin
  perform pg_temp.login(u);
  select jsonb_array_length(lights) into v_exp from home_layouts where id = 'flat';
  -- a player from before the lights: no light copies, no grant row
  delete from player_house_furniture h using furniture f where h.owner_id = u and f.id = bl_furniture_id_of(h.furniture_key) and f.category = 'lighting';
  delete from player_furniture pf using furniture f where pf.user_id = u and f.id = pf.furniture_id and f.category = 'lighting';
  delete from player_house_grants where user_id = u and home_key like '%#lights';
  perform pg_temp.assert(pg_temp.light_qty(u) = 0, 'pre-lighting state: no lights');
  -- the next furniture action (or sign-in) gives them
  perform bl_furniture_materialize(u);
  perform pg_temp.assert(pg_temp.light_qty(u) = v_exp, 'the next furniture action gave all ' || v_exp || ' lights: ' || pg_temp.light_qty(u));
  perform pg_temp.assert(pg_temp.all_valid(u), 'flat lights pass the server rule');
  -- idempotent: nothing more on the next call, nor on sign-in
  perform bl_furniture_materialize(u);
  perform house_upgrade_state();
  perform pg_temp.assert(pg_temp.light_qty(u) = v_exp, 'a second run gives nothing more');
  perform pg_temp.assert(bl_house_items_grant(u, null) = 0, 'items grant gives nothing more');
  perform pg_temp.assert((select count(*) from player_house_grants where user_id = u and home_key like '%#lights') = 1, 'one lights grant row');
  -- sign-in alone also grants (house_upgrade_state)
  delete from player_house_furniture h using furniture f where h.owner_id = u and f.id = bl_furniture_id_of(h.furniture_key) and f.category = 'lighting';
  delete from player_furniture pf using furniture f where pf.user_id = u and f.id = pf.furniture_id and f.category = 'lighting';
  delete from player_house_grants where user_id = u and home_key like '%#lights';
  perform house_upgrade_state();
  perform pg_temp.assert(pg_temp.light_qty(u) = v_exp, 'house_upgrade_state (sign-in) grants the lights too');
  -- the lights never feed the resale allowance
  perform pg_temp.assert((select coalesce(sum(allowance), 0) from player_house_grants where user_id = u and home_key like '%#lights') = 0, 'lights add nothing to the resale allowance');
end $$;

-- ---------- 6. extension rooms ----------
do $$
declare u uuid := current_setting('l1.face_me')::uuid; v_before int; v_after int; v_home text;
begin
  perform pg_temp.login(u);
  select coalesce(start_home, housing_id) into v_home from profiles where id = u;
  v_before := pg_temp.light_qty(u);
  insert into player_house_upgrades (user_id, upgrade_id, start_home, bought_at, ready_at, done_at, notified, source)
  values (u, 'ext_bedroom', v_home, now(), now(), now(), true, 'admin');
  perform house_upgrade_state();
  v_after := pg_temp.light_qty(u);
  perform pg_temp.assert(v_after = v_before + 1, 'the new bedroom came with a bulb: ' || v_before || ' -> ' || v_after);
  perform pg_temp.assert(exists (select 1 from player_house_furniture h where h.owner_id = u and not h.stored and h.z > 5.6 and h.furniture_key like 'own_bulb_holder%'), 'the bulb hangs in the extension room');
  perform house_upgrade_state();
  perform bl_furniture_materialize(u);
  perform pg_temp.assert(pg_temp.light_qty(u) = v_after, 'only once per room');
  perform pg_temp.assert(pg_temp.all_valid(u), 'the extension bulb passes the server rule');
end $$;

-- ---------- 7. grants / RLS ----------
do $$
begin
  perform pg_temp.assert(not has_function_privilege('anon', 'public.bl_house_lights_grant(uuid,text,text)', 'execute'), 'anon cannot run the lights grant');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_house_lights_grant(uuid,text,text)', 'execute'), 'players cannot run the lights grant');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_house_lights_for(uuid)', 'execute'), 'players cannot run the sign-in lights grant');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_house_light_give(uuid,text,text,numeric,numeric,integer)', 'execute'), 'players cannot give themselves a light');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.furniture_buy(text)', 'execute'), 'players still buy furniture');
  perform pg_temp.assert(exists (select 1 from pg_policies where tablename = 'furniture' and policyname = 'furniture_read'), 'the catalogue is still readable');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.player_house_grants'::regclass), 'grant rows stay behind RLS');
end $$;
