-- Bigger homes (20261102000100_bigger_homes.sql, docs/HUD_HOME.md "Home sizes"). Rolled back. Run:
--   bash scripts/sql-test.sh supabase/migrations/20261102000100_bigger_homes.sql -- supabase/tests/bigger_homes_test.sql
-- (or without the migration once it is applied). Checks the new sizes, the new server geometry, and the re-placement
-- of saved furniture: a piece on its old default slot follows the slot, yard pieces follow the east / south wall, a
-- piece the player placed stays where it is when it is still valid, nothing is lost, and a second run changes nothing.
update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');

create temp table t_bg (name text primary key, id uuid not null) on commit drop;
create or replace function pg_temp.bg(p_name text) returns uuid
language sql as $$ select id from t_bg where name = p_name $$;

create or replace function pg_temp.make_home(p_name text, p_origin text, p_home text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@big.bl');
begin
  insert into t_bg values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = to_jsonb(p_origin) where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home(p_home);
  update profiles set rent_owed = 0, energy = 10, cash = 100000, bank = 0, busy_until = null where id = v;
  return v;
end $$;

-- the plans before the resize (20261012001400 + the 2026-10-17 dining fix): what the migration remembers
create temp table t_old (snap jsonb) on commit drop;
insert into t_old values ($j$[
 {"id":"face_me","w":4.2,"d":3.8,"slots":{"bed":[0.85,1.1,0],"seat":[1.3,3.2,3],"sofa":[1.7,3.3,2],"tv":[2.75,0.3,0],"rug":[2.2,2.4,0],"stove":[3.6,2,3],"fridge":[3.75,0.4,0],"wardrobe":[0.35,3,1],"bath":[5.7,3.5,3]},"included":[]},
 {"id":"duplex","w":14.4,"d":10,"slots":{"bed":[1.4,1.35,0],"seat":[2.2,9.2,2],"sofa":[3.7,6.9,3],"tv":[0.3,6.9,1],"ctable":[1.9,6.9,1],"rug":[2.1,6.9,0],"stove":[5.1,0.35,0],"fridge":[4.85,1.75,1],"wardrobe":[3.4,0.35,0],"bath":[9.75,2.2,1]},
  "included":[{"id":"heater","furniture":"water_heater","kind":"water_heater","x":10.3,"z":0.15,"rot":0},{"id":"cab","furniture":"kitchen_cabinet","kind":"kitchen_cab","x":8.5,"z":0.33,"rot":0},{"id":"washer","furniture":"washing_machine","kind":"washer","x":12.3,"z":0.4,"rot":0},{"id":"ac1","furniture":"ac_split","kind":"ac","x":1.4,"z":0.15,"rot":0},{"id":"ac2","furniture":"ac_split","kind":"ac","x":0.15,"z":5.2,"rot":1},{"id":"chand","furniture":"chandelier","kind":"chandelier","x":2.2,"z":6.9,"rot":0},{"id":"cfan","furniture":"fan_ceiling","kind":"fan_ceiling","x":8.2,"z":6.4,"rot":0},{"id":"dining","furniture":"dining_6","kind":"dining6","x":8.2,"z":6.4,"rot":0},{"id":"gbed","furniture":"bed_double","kind":"bed_double","x":13.4,"z":7.6,"rot":3},{"id":"gside","furniture":"bedside","kind":"bedside","x":13.9,"z":6.2,"rot":0},{"id":"gward","furniture":"wardrobe_big","kind":"wardrobe_big","x":11.5,"z":9.65,"rot":2},{"id":"gen","furniture":"gen_firman","kind":"generator","x":16.6,"z":1.2,"rot":1},{"id":"palm1","furniture":"plant_palm","kind":"plant_big","x":-0.5,"z":13.8,"rot":0},{"id":"palm2","furniture":"plant_palm","kind":"plant_big","x":17.9,"z":6.2,"rot":0}]}
]$j$::jsonb);

-- ---------- 1. sizes and server geometry ----------
do $$
begin
  perform pg_temp.assert((select count(*) from home_layouts) = 5, 'five home layouts');
  perform pg_temp.assert((select w = 6.2 and d = 5.0 from home_layouts where id = 'hostel'), 'hostel 6.2 x 5.0');
  perform pg_temp.assert((select w = 6.8 and d = 5.6 from home_layouts where id = 'face_me'), 'face-me (LAPO) 6.8 x 5.6');
  perform pg_temp.assert((select w = 9 and d = 6.8 from home_layouts where id = 'self_contain'), 'self-contain 9 x 6.8');
  perform pg_temp.assert((select w = 13 and d = 9.4 from home_layouts where id = 'flat'), 'flat 13 x 9.4');
  perform pg_temp.assert((select w = 19 and d = 13.4 from home_layouts where id = 'duplex'), 'duplex 19 x 13.4');
  perform pg_temp.assert((select (lot->>2)::numeric > w and (lot->>3)::numeric > d from home_layouts where id = 'face_me'), 'face-me keeps its compound');

  perform pg_temp.assert((select effect->'geom'->'duplex'->'room'->'rect' from house_upgrades where id = 'ext_guest_wing') = '[9,13.4,19,17.2]'::jsonb, 'guest wing geometry');
  perform pg_temp.assert((select effect->'geom'->'flat'->'room'->'rect' from house_upgrades where id = 'ext_bedroom') = '[0,9.4,8,12.8]'::jsonb, 'flat bedroom geometry');
end $$;

-- ---------- 2. a LAPO face-me player: pieces on old defaults follow the slots, custom spots stay ----------
do $$
declare l uuid := pg_temp.make_home('LapoBig', 'lapo', 'ekenwan_face_me'); n int; n2 int; v int;
begin
  perform pg_temp.login(l);
  perform bl_furniture_materialize(l);
  perform furniture_buy('plastic_chair_white');
  perform furniture_buy('plastic_chair_white');
  -- rows as they stood before the resize
  update player_house_furniture set x = 0.85, z = 1.1, rotation = 0, stored = false where owner_id = l and furniture_key = 'own_foam_mat';
  update player_house_furniture set x = 1.3, z = 3.2, rotation = 3, stored = false where owner_id = l and furniture_key = 'own_stool';
  update player_house_furniture set x = 3.6, z = 2.0, rotation = 3, stored = false where owner_id = l and furniture_key = 'own_kerosene_stove';
  update player_house_furniture set x = 2.5, z = 1.5, rotation = 0, stored = false where owner_id = l and furniture_key = 'own_plastic_chair_white';      -- the player's own spot
  update player_house_furniture set x = 6.0, z = 1.0, rotation = 0, stored = false where owner_id = l and furniture_key = 'own_plastic_chair_white-2';    -- old yard, east of the old wall
  select count(*) into n from player_house_furniture where owner_id = l;
  select count(*) into v from player_house_furniture where owner_id = l and not stored;
  perform pg_temp.assert(public.bl_homes_replace_after_resize((select snap from t_old)) >= 1, 'the migration re-checked the face-me home');
  select count(*) into n2 from player_house_furniture where owner_id = l;
  perform pg_temp.assert(n = n2, 'no piece lost');
  perform pg_temp.assert((select x = 0.85 and z = 1.2 and not stored from player_house_furniture where owner_id = l and furniture_key = 'own_foam_mat'), 'mat follows the new bed slot');
  perform pg_temp.assert((select x = 4.6 and z = 4.45 and not stored from player_house_furniture where owner_id = l and furniture_key = 'own_stool'), 'stool follows the new seat slot');
  perform pg_temp.assert((select x = 5.25 and z = 0.4 and not stored from player_house_furniture where owner_id = l and furniture_key = 'own_kerosene_stove'), 'stove follows the new stove slot');
  perform pg_temp.assert((select x = 2.5 and z = 1.5 and not stored from player_house_furniture where owner_id = l and furniture_key = 'own_plastic_chair_white'), 'a spot the player chose stays');
  perform pg_temp.assert((select not stored from player_house_furniture where owner_id = l and furniture_key = 'own_plastic_chair_white-2'), 'the yard chair still stands somewhere (nearest free spot)');
  perform pg_temp.assert((select count(*) from player_house_furniture where owner_id = l and not stored) = v, 'every standing piece still stands');
  perform pg_temp.assert(not exists (select 1 from player_house_furniture h where h.owner_id = l and not h.stored
                                       and bl_furniture_check(h.owner_id, h.layout, h.furniture_key, h.x, h.z, h.rotation) is not null), 'every placed piece is valid in the new plan');
  -- a second run changes nothing
  select count(*) into v from player_house_furniture where owner_id = l and not stored;
  perform pg_temp.assert(public.bl_homes_replace_after_resize((select jsonb_agg(jsonb_build_object('id', id, 'w', w, 'd', d, 'slots', slots, 'included', included)) from home_layouts)) = 0, 'same sizes: nothing to do');
  perform pg_temp.assert((select count(*) from player_house_furniture where owner_id = l and not stored) = v, 'unchanged');
end $$;

-- ---------- 3. a NEPO duplex player: the pieces that came with the house follow their new spots ----------
do $$
declare n uuid := pg_temp.make_home('NepoBig', 'nepo', 'gra_duplex'); c0 int; c1 int;
begin
  perform pg_temp.login(n);
  perform bl_furniture_materialize(n);
  select count(*) into c0 from player_house_furniture where owner_id = n;
  update player_house_furniture set x = 8.2, z = 6.4, rotation = 0, stored = false where owner_id = n and furniture_key = 'own_dining_6';
  update player_house_furniture set x = 8.2, z = 6.4, rotation = 0, stored = false where owner_id = n and furniture_key = 'own_fan_ceiling';
  update player_house_furniture set x = 2.2, z = 6.9, rotation = 0, stored = false where owner_id = n and furniture_key = 'own_chandelier';
  update player_house_furniture set x = 12.3, z = 0.4, rotation = 0, stored = false where owner_id = n and furniture_key = 'own_washing_machine';
  update player_house_furniture set x = 13.4, z = 7.6, rotation = 3, stored = false where owner_id = n and furniture_key = 'own_bed_double-2';
  update player_house_furniture set x = 1.4, z = 1.35, rotation = 0, stored = false where owner_id = n and furniture_key = 'own_bed_double';
  update player_house_furniture set x = 13.9, z = 6.2, rotation = 0, stored = false where owner_id = n and furniture_key = 'own_bedside';
  update player_house_furniture set x = 11.5, z = 9.65, rotation = 2, stored = false where owner_id = n and furniture_key = 'own_wardrobe_big';
  update player_house_furniture set x = 16.6, z = 1.2, rotation = 1, stored = false where owner_id = n and furniture_key = 'own_gen_firman';
  update player_house_furniture set x = 8.5, z = 0.33, rotation = 0, stored = false where owner_id = n and furniture_key = 'own_kitchen_cabinet';
  update player_house_furniture set x = 10.3, z = 0.15, rotation = 0, stored = false where owner_id = n and furniture_key = 'own_water_heater';
  update player_house_furniture set x = 1.4, z = 0.15, rotation = 0, stored = false where owner_id = n and furniture_key = 'own_ac_split';
  update player_house_furniture set x = 0.15, z = 5.2, rotation = 1, stored = false where owner_id = n and furniture_key = 'own_ac_split-2';
  update player_house_furniture set x = -0.5, z = 13.8, rotation = 0, stored = false where owner_id = n and furniture_key = 'own_plant_palm';
  update player_house_furniture set x = 17.9, z = 6.2, rotation = 0, stored = false where owner_id = n and furniture_key = 'own_plant_palm-2';
  perform pg_temp.assert(public.bl_homes_replace_after_resize((select snap from t_old)) >= 1, 're-checked the duplex');
  select count(*) into c1 from player_house_furniture where owner_id = n;
  perform pg_temp.assert(c0 = c1, 'no piece lost');
  perform pg_temp.assert((select x = 11.4 and z = 8.8 and not stored from player_house_furniture where owner_id = n and furniture_key = 'own_dining_6'), 'dining set at its new spot');
  perform pg_temp.assert((select x = 11.4 and z = 8.8 and not stored from player_house_furniture where owner_id = n and furniture_key = 'own_fan_ceiling'), 'ceiling fan over it');
  perform pg_temp.assert((select x = 2.3 and z = 9.4 and not stored from player_house_furniture where owner_id = n and furniture_key = 'own_chandelier'), 'chandelier in the parlour');
  perform pg_temp.assert((select x = 16.0 and z = 0.45 and not stored from player_house_furniture where owner_id = n and furniture_key = 'own_washing_machine'), 'washer in the laundry');
  perform pg_temp.assert((select x = 18.0 and z = 11.6 and rotation = 3 and not stored from player_house_furniture where owner_id = n and furniture_key = 'own_bed_double-2'), 'guest bed in the guest bedroom');
  perform pg_temp.assert((select x = 1.6 and z = 1.5 and not stored from player_house_furniture where owner_id = n and furniture_key = 'own_bed_double'), 'master bed on the new bed slot');
  perform pg_temp.assert((select x = 15.1 and z = 13.05 and rotation = 2 from player_house_furniture where owner_id = n and furniture_key = 'own_wardrobe_big'), 'guest wardrobe');
  perform pg_temp.assert((select x = 21.2 and z = 1.2 from player_house_furniture where owner_id = n and furniture_key = 'own_gen_firman'), 'generator moves out with the east wall');
  perform pg_temp.assert((select x = 22.6 and z = 5.2 from player_house_furniture where owner_id = n and furniture_key = 'own_plant_palm-2'), 'palm in the east compound');
  perform pg_temp.assert(not exists (select 1 from player_house_furniture h where h.owner_id = n and not h.stored
                                       and bl_furniture_check(h.owner_id, h.layout, h.furniture_key, h.x, h.z, h.rotation) is not null), 'every placed piece is valid in the new plan');
end $$;

-- ---------- 4. the migration only queues players; each is re-checked the first time they load their home ----------
do $$
declare l uuid := pg_temp.make_home('LapoLazy', 'lapo', 'ekenwan_face_me'); v_layout text; v_n int;
begin
  perform pg_temp.login(l);
  perform bl_furniture_materialize(l);
  select layout into v_layout from player_house_furniture where owner_id = l limit 1;
  -- stage what the migration leaves behind: the old plans, and this player waiting in the queue with old-plan rows
  insert into home_layouts_prev (id, w, d, slots, included, queued)
  select e->>'id', (e->>'w')::numeric, (e->>'d')::numeric, e->'slots', e->'included', true
    from t_old, jsonb_array_elements(snap) e
  on conflict (id) do update set w = excluded.w, d = excluded.d, slots = excluded.slots, included = excluded.included, queued = true;
  update player_house_furniture set x = 0.85, z = 1.1, rotation = 0, stored = false where owner_id = l and furniture_key = 'own_foam_mat';
  insert into home_resize_pending (owner_id, layout) values (l, v_layout);
  -- not re-checked yet: the migration itself touched nobody
  perform pg_temp.assert((select x = 0.85 and z = 1.1 from player_house_furniture where owner_id = l and furniture_key = 'own_foam_mat'), 'queued, not touched yet');
  -- the sign-in call (house_upgrade_state) re-checks this player
  perform house_upgrade_state();
  perform pg_temp.assert(not exists (select 1 from home_resize_pending where owner_id = l), 'sign-in took the player off the queue');
  perform pg_temp.assert((select x = 0.85 and z = 1.2 and not stored from player_house_furniture where owner_id = l and furniture_key = 'own_foam_mat'), 'mat follows the new bed slot');
  -- a second call does nothing
  perform pg_temp.assert(bl_home_resize_owner(l) = 0, 'nothing left to do');
  -- any furniture action re-checks too (materialize hook)
  update player_house_furniture set x = 0.85, z = 1.1, rotation = 0, stored = false where owner_id = l and furniture_key = 'own_foam_mat';
  insert into home_resize_pending (owner_id, layout) values (l, v_layout);
  perform bl_furniture_materialize(l);
  perform pg_temp.assert(not exists (select 1 from home_resize_pending where owner_id = l), 'a furniture action took the player off the queue');
  perform pg_temp.assert((select x = 0.85 and z = 1.2 from player_house_furniture where owner_id = l and furniture_key = 'own_foam_mat'), 'mat moved by the furniture action');
  -- the queue and the old plans are private
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.home_resize_pending', 'select')
                         and not has_table_privilege('anon', 'public.home_layouts_prev', 'select'), 'queue tables are private');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_home_resize_owner(uuid)', 'execute'), 'bl_home_resize_owner is not callable by players');
end $$;

select 'bigger_homes_test OK' as result;
