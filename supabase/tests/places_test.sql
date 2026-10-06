-- L2 place interiors + real landmarks (20261006001300_places.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/places_test.sql
-- Groups: 1 seeds (landmarks, config, privileges) · 2 zones for every type + every action points at something
-- real · 3 place_interior shape + merge · 4 club hours · 5 prices + effects + Mama Ebo sold out + Risky ·
-- 6 car purchase unlocks own-car travel · 7 admin edits zones, players can't.

create or replace function pg_temp.pl_hint(p_sql text, p_hint text) returns text
language plpgsql as $$
declare v_h text; v_m text;
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
    get stacked diagnostics v_h = pg_exception_hint, v_m = message_text;
    if v_h is distinct from p_hint then
      raise exception 'TEST FAILED: [%] expected hint "%", got "%" (%)', p_sql, p_hint, v_h, sqlerrm;
    end if;
    return v_m;
  end;
  raise exception 'TEST FAILED: [%] expected hint "%" but it succeeded', p_sql, p_hint;
end $$;

-- move the test clock so the Benin clock reads p_hour:30 (real clock mode)
create or replace function pg_temp.pl_at_hour(p_hour int) returns void
language plpgsql as $$
declare c jsonb; cur numeric; delta numeric;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  c := bl_game_clock();
  cur := (c->>'hour')::numeric * 3600 + (c->>'minute')::numeric * 60;
  delta := ((p_hour * 3600 + 1800 - cur)::numeric % 86400 + 86400) % 86400;
  perform set_config('bl.test_offset_seconds', delta::text, true);
  if (bl_game_clock()->>'hour')::int <> p_hour then
    raise exception 'TEST FAILED: could not move the clock to %:30 (got %)', p_hour, bl_game_clock();
  end if;
end $$;

create temp table t_pl (name text primary key, id uuid not null) on commit drop;
grant select on t_pl to authenticated;
create or replace function pg_temp.pl(p_name text) returns uuid
language sql as $$ select id from t_pl where name = p_name $$;

create or replace function pg_temp.pl_make(p_name text, p_origin text, p_home text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@places.bl');
begin
  insert into t_pl values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = to_jsonb(p_origin) where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home(p_home);
  update profiles set rent_owed = 0 where id = v;
  return v;
end $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
end $$;

-- ---------- 1. seeds, config, privileges ----------
do $$
declare r record;
begin
  for r in select * from (values
    ('benin_city_mall', 'mall'), ('kada_plaza', 'cinema'), ('mama_ebo', 'buka'), ('protea_hotel', 'hotel'),
    ('golden_tulip', 'hotel'), ('ogba_zoo', 'zoo'), ('ogbemudia_stadium', 'stadium'), ('emotan_statue', 'monument'),
    ('club_360', 'club'), ('club_de_medici', 'club'), ('rome_club', 'club'), ('cube_nightlife', 'club'),
    ('versus_lounge', 'club'), ('owambe_republic', 'club'),
    ('ighodalo_cars', 'car_dealer'), ('sdd_motors', 'car_dealer'), ('tokunbo_lot', 'car_dealer')) v(id, scene) loop
    perform pg_temp.assert(exists (select 1 from locations where id = r.id and scene = r.scene and blurb <> ''),
      format('landmark %s (%s) seeded', r.id, r.scene));
  end loop;
  perform pg_temp.assert((select count(*) from locations where scene = 'club' and open_hour = 21 and close_hour = 5) >= 8,
    'every club opens 9 PM - 5 AM');
  perform pg_temp.assert(bl_cfg('crowd.max_visible') = 10, 'crowd.max_visible defaults to 10');
  perform pg_temp.assert(bl_cfg_bool('places.hours_enabled'), 'hours on by default');
  perform pg_temp.assert(bl_cfg_bool('cars.bank_first'), 'cars paid bank first');
  perform pg_temp.assert(bl_hour_label(21) = '9 PM' and bl_hour_label(5) = '5 AM' and bl_hour_label(24) = 'midnight'
                         and bl_hour_label(12) = 'noon' and bl_hour_label(9.5) = '9:30 AM', 'hour labels');
  -- untouched config (the lead checks these)
  perform pg_temp.assert(bl_cfg_bool('rent.enabled'), 'rent.enabled stays on');
  perform pg_temp.assert(bl_cfg('origin.nepo_pct') = 10, 'origin.nepo_pct stays 10');
  perform pg_temp.assert(bl_cfg_text('clock.mode') = 'real', 'clock.mode stays real');
  perform pg_temp.assert(bl_cfg('bank.transfer_min_account_real_minutes') = 1440, 'transfer wait stays 1440');
  -- privileges
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.place_interior(text)', 'execute'), 'players read interiors');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.place_interior(text)', 'execute'), 'anon may not');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_place_open(public.locations)', 'execute'), 'helper revoked');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.do_activity(text)', 'execute')
                         and not has_function_privilege('anon', 'public.do_activity(text)', 'execute'), 'do_activity grants kept');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.shop_buy(text, integer)', 'execute')
                         and not has_function_privilege('anon', 'public.shop_buy(text, integer)', 'execute'), 'shop_buy grants kept');
  perform pg_temp.assert(has_table_privilege('anon', 'public.place_zones', 'select')
                         and not has_table_privilege('authenticated', 'public.place_zones', 'insert')
                         and not has_table_privilege('authenticated', 'public.zone_actions', 'update')
                         and not has_table_privilege('authenticated', 'public.place_moods', 'delete'), 'catalog read-only for clients');
  raise notice 'ok 1: landmarks, config, privileges';
end $$;

-- ---------- 2. zones for every type; every action points at something real ----------
do $$
declare v_missing text; n int;
begin
  select string_agg(distinct l.scene, ', ') into v_missing from locations l
   where not exists (select 1 from place_zones z where z.active and (z.scene = l.scene or z.location_id = l.id));
  perform pg_temp.assert(v_missing is null, 'types without zones: ' || coalesce(v_missing, ''));
  select count(*) into n from zone_actions za where za.kind = 'activity' and not exists (select 1 from activities a where a.id = za.ref);
  perform pg_temp.assert(n = 0, n || ' zone actions point at missing activities');
  select count(*) into n from zone_actions za where za.kind = 'shop' and not exists (select 1 from items i where i.id = za.ref);
  perform pg_temp.assert(n = 0, n || ' zone actions point at missing items');
  select count(*) into n from zone_actions za where za.kind = 'job' and not exists (select 1 from career_tracks t where t.id = za.ref);
  perform pg_temp.assert(n = 0, n || ' zone actions point at missing career tracks');
  select count(*) into n from zone_actions za where za.kind = 'panel' and za.ref not in ('shop', 'jobs', 'bank', 'pos', 'activities', 'chat', 'inventory');
  perform pg_temp.assert(n = 0, n || ' zone actions point at unknown tabs');
  -- the activity a zone offers is offered at that zone's type
  select string_agg(za.id, ', ') into v_missing from zone_actions za join place_zones z on z.id = za.zone_id
    join activities a on a.id = za.ref
   where za.kind = 'activity' and z.scene is not null and not (z.scene = any (a.scenes));
  perform pg_temp.assert(v_missing is null, 'activities offered in a zone of the wrong type: ' || coalesce(v_missing, ''));
  select string_agg(za.id, ', ') into v_missing from zone_actions za join place_zones z on z.id = za.zone_id
    join activities a on a.id = za.ref join locations l on l.id = z.location_id
   where za.kind = 'activity' and not (l.scene = any (a.scenes));
  perform pg_temp.assert(v_missing is null, 'place zone activity not offered at its scene: ' || coalesce(v_missing, ''));
  -- every activity scene exists on the map (the new scenes included)
  perform pg_temp.assert(not exists (select 1 from activities a, unnest(a.scenes) s where s not in (select scene from locations)),
    'activity scenes exist on the map');
  -- the trigger refuses a dangling reference
  perform pg_temp.pl_hint($q$ insert into zone_actions (id, zone_id, kind, ref) values ('x.bad', 'club.bar', 'activity', 'no_such_thing') $q$, 'bad_value');
  perform pg_temp.pl_hint($q$ insert into zone_actions (id, zone_id, kind, ref) values ('x.bad2', 'club.bar', 'panel', 'hospital') $q$, 'bad_value');
  perform pg_temp.pl_hint($q$ insert into place_zones (id, scene, zone_key, label, x, z) values ('x.z', 'no_scene', 'k', 'K', 1, 1) $q$, 'bad_value');
  raise notice 'ok 2: zones for every type, every action references something real';
end $$;

-- ---------- 3. place_interior: shape, merge, every place offers something ----------
do $$
declare
  a uuid := pg_temp.pl_make('Pl_Ada', 'lapo', 'ekenwan_face_me');
  j jsonb; l record; n int; v_bad text := '';
begin
  perform pg_temp.login(a);
  perform pg_temp.pl_at_hour(22);
  -- every non-home place: zones, each zone with at least one card, valid boxes
  for l in select id, scene from locations where scene not like 'home_%' order by sort loop
    j := place_interior(l.id);
    n := jsonb_array_length(j->'zones');
    if n = 0 then v_bad := v_bad || l.id || ' (no zones) '; end if;
    if exists (select 1 from jsonb_array_elements(j->'zones') z where jsonb_array_length(z->'actions') = 0) then
      v_bad := v_bad || l.id || ' (empty zone: ' || (select string_agg(z->>'key', ',') from jsonb_array_elements(j->'zones') z
                                                    where jsonb_array_length(z->'actions') = 0) || ') ';
    end if;
  end loop;
  perform pg_temp.assert(v_bad = '', 'places with missing cards: ' || v_bad);
  -- Mama Ebo: the place's counter replaces the buka's, with pepper rice; other bukas don't offer it
  j := place_interior('mama_ebo');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(j->'zones') z where z->>'key' = 'counter') = 1, 'one counter at Mama Ebo');
  perform pg_temp.assert((select z->>'label' from jsonb_array_elements(j->'zones') z where z->>'key' = 'counter') = 'Pepper rice counter', 'place zone wins');
  perform pg_temp.assert(j::text like '%pepper_rice%', 'pepper rice at Mama Ebo');
  perform pg_temp.assert(place_interior('mama_osas_buka')::text not like '%pepper_rice%', 'no pepper rice at Mama Osas');
  perform pg_temp.assert(jsonb_array_length(j->'moods') >= 2, 'mood lines for Mama Ebo');
  -- shop cards only for items sold at that place
  perform pg_temp.assert(place_interior('oregbeni_market')::text not like '%"ref": "zobo"%', 'zobo not sold at Oregbeni -> no card');
  perform pg_temp.assert(place_interior('oba_market')::text like '%"ref": "zobo"%', 'zobo card at Oba Market');
  -- jobs: a card for the track that works here
  perform pg_temp.assert(place_interior('uniben')::text like '%"kind": "job"%', 'job card at UNIBEN');
  -- shape
  j := place_interior('club_360');
  perform pg_temp.assert(j ? 'zones' and j ? 'moods' and j ? 'open' and j->'location'->>'scene' = 'club' and (j->>'here')::boolean = false, 'interior shape');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(j->'zones') z where z->>'key' in ('bar', 'dance', 'dj', 'vip')) = 4, 'club zones bar/dance/dj/vip');
  perform pg_temp.assert(place_interior()->'location'->>'id' = 'ekenwan_room', 'default = where I am');
  raise notice 'ok 3: place_interior';
end $$;

-- ---------- 4. club hours ----------
do $$
declare a uuid := pg_temp.pl('Pl_Ada'); j jsonb; m text;
begin
  perform pg_temp.login(a);
  update profiles set location_id = 'club_360', cash = 1000000, busy_until = null, energy = 60, fun = 20, social = 20 where id = a;
  -- by day: closed, cards locked "Opens 9 PM", actions and purchases refused
  perform pg_temp.pl_at_hour(14);
  j := place_interior('club_360');
  perform pg_temp.assert((j->>'open')::boolean = false and j->>'opens' = 'Opens 9 PM', 'closed by day, opens 9 PM');
  perform pg_temp.assert((select bool_and(ac->>'locked' = 'Opens 9 PM') from jsonb_array_elements(j->'zones') z, jsonb_array_elements(z->'actions') ac
                           where ac->>'kind' in ('activity', 'shop')), 'every card locked by day');
  m := pg_temp.pl_hint($q$ select do_activity('club_dance') $q$, 'closed');
  perform pg_temp.assert(m like '%360 Signature is closed%Opens 9 PM%', 'closed message: ' || m);
  perform pg_temp.pl_hint($q$ select shop_buy('star_beer', 1) $q$, 'closed');
  perform pg_temp.assert((select cash from profiles where id = a) = 1000000, 'nothing charged while closed');
  -- 9:30 PM and 2:30 AM: open
  perform pg_temp.pl_at_hour(21);
  perform pg_temp.assert((place_interior('club_360')->>'open')::boolean, 'open at 9:30 PM');
  perform do_activity('club_dance');
  update profiles set busy_until = null where id = a;
  perform pg_temp.pl_at_hour(2);
  perform pg_temp.assert((place_interior('club_360')->>'open')::boolean, 'open at 2:30 AM');
  perform shop_buy('star_beer', 1);
  -- 5:30 AM: closed again
  perform pg_temp.pl_at_hour(5);
  perform pg_temp.assert(not (place_interior('club_360')->>'open')::boolean, 'closed at 5:30 AM');
  -- hours can be switched off by the admin
  update game_config set value = 'false' where key = 'places.hours_enabled';
  perform pg_temp.assert((place_interior('club_360')->>'open')::boolean, 'hours off -> open');
  update game_config set value = 'true' where key = 'places.hours_enabled';
  -- a place without hours is always open
  perform pg_temp.assert((place_interior('mama_ebo')->>'open')::boolean and place_interior('mama_ebo')->'hours' = 'null'::jsonb, 'no hours = always open');
  raise notice 'ok 4: club hours enforced';
end $$;

-- ---------- 5. prices, effects, sold out, Risky ----------
do $$
declare a uuid := pg_temp.pl('Pl_Ada'); r jsonb; p profiles; c0 bigint; m text;
begin
  perform pg_temp.login(a);
  perform pg_temp.pl_at_hour(23);
  update profiles set location_id = 'club_360', cash = 1000000, busy_until = null, fun = 10, social = 10, street_cred = 0, stress = 50, needs_updated_at = bl_now() where id = a;
  -- hype man: costs 100k, +fun +social +5 street cred
  r := do_activity('hype_shoutout');
  select * into p from profiles where id = a;
  perform pg_temp.assert(p.cash = 1000000 - 100000, 'hype man costs 100k, cash ' || p.cash);
  perform pg_temp.assert(p.fun = 35 and p.social = 45 and p.street_cred = 5, format('hype effects fun %s social %s cred %s', p.fun, p.social, p.street_cred));
  perform pg_temp.assert(p.busy_label = 'Hype man shout-out' and p.busy_until > bl_now(), 'busy while it runs');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'activity' and delta = -100000), 'ledger row');
  -- VIP table: 150k
  update profiles set busy_until = null where id = a;
  c0 := (select cash from profiles where id = a);
  perform do_activity('vip_table');
  perform pg_temp.assert((select cash from profiles where id = a) = c0 - 150000, 'VIP table 150k');
  perform pg_temp.assert((select street_cred from profiles where id = a) = 8, 'VIP table +3 street cred');
  -- Risky: spray money with a sure robbery roll takes some cash and says so; with no roll it doesn't
  update profiles set busy_until = null, protected_until = null where id = a;
  perform set_config('bl.test_rand', '0', true);
  r := do_activity('spray_money');
  perform pg_temp.assert(r->'robbed' is not null and r->'robbed' <> 'null'::jsonb and r->>'message' like '%Omo!%', 'risky spray money can get you robbed: ' || r::text);
  perform set_config('bl.test_rand', '0.999', true);
  update profiles set busy_until = null where id = a;
  r := do_activity('spray_money');
  perform pg_temp.assert(r->'robbed' = 'null'::jsonb, 'no robbery on a lucky roll');
  -- not enough cash
  update profiles set busy_until = null, cash = 10 where id = a;
  perform pg_temp.assert(exists (select 1 from activities where id = 'vip_table'), 'vip exists');
  begin
    perform do_activity('vip_table');
    raise exception 'TEST FAILED: VIP table with ₦10';
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
  end;
  -- Mama Ebo: pepper rice only there; at lunch it can sell out (nothing charged), otherwise 3,500 + hunger
  perform set_config('bl.test_rand', '', true);
  update profiles set location_id = 'mama_osas_buka', cash = 50000, busy_until = null, hunger = 20 where id = a;
  m := pg_temp.pl_hint($q$ select do_activity('pepper_rice') $q$, 'wrong_place');
  perform pg_temp.assert(m like '%only at Mama Ebo%', 'pepper rice only at Mama Ebo: ' || m);
  perform pg_temp.pl_at_hour(13);
  update profiles set location_id = 'mama_ebo', hunger = 20, needs_updated_at = bl_now() where id = a;
  perform set_config('bl.test_rand', '0.01', true);
  m := pg_temp.pl_hint($q$ select do_activity('pepper_rice') $q$, 'sold_out');
  perform pg_temp.assert(m like 'Pepper rice don finish!%', 'sold out joke: ' || m);
  perform pg_temp.assert((select cash from profiles where id = a) = 50000, 'sold out: nothing charged');
  perform set_config('bl.test_rand', '0.99', true);
  perform do_activity('pepper_rice');
  select * into p from profiles where id = a;
  perform pg_temp.assert(p.cash = 50000 - 3500 and p.hunger = 85, format('pepper rice 3,500 and +65 hunger (cash %s hunger %s)', p.cash, p.hunger));
  -- outside lunch it never sells out
  perform pg_temp.pl_at_hour(18);
  perform set_config('bl.test_rand', '0.01', true);
  update profiles set busy_until = null, hunger = 20 where id = a;
  perform do_activity('pepper_rice');
  perform set_config('bl.test_rand', '', true);
  -- hotel luxury sleep fills energy; cinema film; zoo; stadium; Emotan is free
  update profiles set location_id = 'protea_hotel', busy_until = null, energy = 5, cash = 100000, needs_updated_at = bl_now() where id = a;
  perform do_activity('hotel_sleep');
  select * into p from profiles where id = a;
  perform pg_temp.assert(p.energy = 100 and p.cash = 40000, format('hotel sleep 60k, energy 100 (cash %s energy %s)', p.cash, p.energy));
  perform pg_temp.pl_at_hour(19);
  update profiles set location_id = 'kada_plaza', busy_until = null, fun = 10, cash = 10000, needs_updated_at = bl_now() where id = a;
  perform do_activity('watch_film');
  perform pg_temp.assert((select cash from profiles where id = a) = 6500 and (select fun from profiles where id = a) = 50, 'film 3,500 +40 fun');
  update profiles set location_id = 'emotan_statue', busy_until = null where id = a;
  perform do_activity('emotan_photo');
  perform pg_temp.assert((select cash from profiles where id = a) = 6500, 'Emotan photo is free');
  update profiles set location_id = 'ogba_zoo', busy_until = null where id = a;
  perform pg_temp.pl_at_hour(20);
  perform pg_temp.pl_hint($q$ select do_activity('zoo_trip') $q$, 'closed');  -- zoo shuts at 6 PM
  perform pg_temp.pl_at_hour(10);
  perform do_activity('zoo_trip');
  update profiles set location_id = 'ogbemudia_stadium', busy_until = null where id = a;
  perform do_activity('match_day');
  raise notice 'ok 5: prices, effects, sold out, risky';
end $$;

-- ---------- 6. a car from the dealer unlocks own-car travel ----------
do $$
declare b uuid := pg_temp.pl_make('Pl_Ben', 'lapo', 'ekenwan_face_me'); q jsonb; r jsonb; p profiles;
begin
  perform pg_temp.login(b);
  perform pg_temp.pl_at_hour(11);
  update profiles set location_id = 'tokunbo_lot', cash = 300000, bank = 2000000, busy_until = null where id = b;
  q := travel_quote('mama_ebo');
  perform pg_temp.assert(not (select (o->>'allowed')::boolean from jsonb_array_elements(q->'options') o where o->>'mode' = 'car'),
    'no car yet -> car travel not allowed');
  perform pg_temp.assert((select o->>'reason' from jsonb_array_elements(q->'options') o where o->>'mode' = 'car') ilike '%car%',
    'the reason is the missing car');
  -- the lot sells the Tokunbo Corolla and the Kia; not the Hilux
  perform pg_temp.assert(place_interior('tokunbo_lot')::text like '%tokunbo_car%', 'Corolla card at the lot');
  perform pg_temp.pl_hint($q$ select shop_buy('hilux_new', 1) $q$, 'not_sold_here');
  perform pg_temp.pl_hint($q$ select shop_buy('tokunbo_car', 2) $q$, 'bad_qty');
  -- too expensive for bank + cash
  update profiles set bank = 100000 where id = b;
  perform pg_temp.pl_hint($q$ select shop_buy('tokunbo_car', 1) $q$, 'not_enough_cash');
  -- bank first, then cash: 2.0m bank + 0.5m cash of 300k? -> 2.2m bank + 300k cash covers 2.5m
  update profiles set bank = 2200000, cash = 300000 where id = b;
  r := shop_buy('tokunbo_car', 1);
  select * into p from profiles where id = b;
  perform pg_temp.assert((r->>'car')::boolean and p.bank = 0 and p.cash = 0, format('paid 2.2m bank + 300k cash (bank %s cash %s)', p.bank, p.cash));
  perform pg_temp.assert(exists (select 1 from ledger where user_id = b and reason = 'car_purchase' and account = 'bank' and delta = -2200000), 'bank ledger');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = b and reason = 'car_purchase' and account = 'cash' and delta = -300000), 'cash ledger');
  perform pg_temp.assert(exists (select 1 from inventory where user_id = b and item_id = 'tokunbo_car' and qty = 1), 'car in the Bag');
  -- own-car travel is now allowed (with fuel money)
  update profiles set cash = 10000 where id = b;
  q := travel_quote('mama_ebo');
  perform pg_temp.assert((select (o->>'allowed')::boolean from jsonb_array_elements(q->'options') o where o->>'mode' = 'car'),
    'car travel unlocked: ' || q::text);
  -- the same car twice is refused
  update profiles set bank = 5000000 where id = b;
  perform pg_temp.pl_hint($q$ select shop_buy('tokunbo_car', 1) $q$, 'already_owned');
  raise notice 'ok 6: car purchase unlocks own-car travel';
end $$;

-- ---------- 7. admin edits zones; players can't ----------
do $$
declare
  adm uuid := pg_temp.pl_make('Pl_Admin', 'lapo', 'ekenwan_face_me');
  pla uuid := pg_temp.pl('Pl_Ada');
  r jsonb; ok boolean;
begin
  update profiles set is_admin = true where id = adm;
  perform pg_temp.login(adm);
  -- move the club bar, add a zone + action for one club, hide it again, edit a mood line
  r := admin_row_upsert('place_zones', '{"id": "club.bar", "x": 3.1, "label": "Main bar"}');
  perform pg_temp.assert((select x = 3.1 and label = 'Main bar' from place_zones where id = 'club.bar'), 'admin moved the bar');
  r := admin_row_upsert('place_zones', '{"id": "rome_club.balcony", "location_id": "rome_club", "zone_key": "balcony", "label": "Balcony", "icon": "🌃", "prop": "vip", "x": 12, "z": 9, "w": 2, "d": 2, "rot": 0, "sort": 9, "active": true}');
  r := admin_row_upsert('zone_actions', '{"id": "rome_club.balcony.vip_table", "zone_id": "rome_club.balcony", "kind": "activity", "ref": "vip_table", "sort": 1, "active": true}');
  perform pg_temp.assert(place_interior('rome_club')::text like '%Balcony%', 'new zone shows at Rome');
  perform pg_temp.assert(place_interior('club_360')::text not like '%Balcony%', 'only at Rome');
  r := admin_row_upsert('place_zones', '{"id": "rome_club.balcony", "active": false}');
  perform pg_temp.assert(place_interior('rome_club')::text not like '%Balcony%', 'inactive zone hidden');
  perform pg_temp.pl_hint($q$ select admin_row_upsert('zone_actions', '{"id": "z.bad", "zone_id": "club.bar", "kind": "shop", "ref": "nope", "sort": 1, "active": true}') $q$, 'bad_value');
  r := admin_row_upsert('place_moods', '{"id": "club.1", "line": "The DJ is on fire tonight"}');
  r := admin_row_upsert('activities', '{"id": "vip_table", "cost": 200000, "risky": false}');
  perform pg_temp.assert((select cost from activities where id = 'vip_table') = 200000, 'admin retuned the VIP price');
  r := admin_row_upsert('locations', '{"id": "club_360", "open_hour": 22, "close_hour": 4}');
  perform pg_temp.assert((select open_hour from locations where id = 'club_360') = 22, 'admin changed the hours');
  r := admin_row_upsert('locations', '{"id": "club_360", "open_hour": null, "close_hour": null}');
  perform pg_temp.assert((select open_hour is null from locations where id = 'club_360'), 'admin cleared the hours');
  perform pg_temp.pl_hint($q$ select admin_row_upsert('locations', '{"id": "club_360", "open_hour": 30, "close_hour": 4}') $q$, 'bad_value');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'row_update' and data->>'table' = 'place_zones'), 'audited');
  -- a player can't
  perform pg_temp.login(pla);
  ok := false;
  begin perform admin_row_upsert('place_zones', '{"id": "club.bar", "x": 1}'); exception when others then ok := true; end;
  perform pg_temp.assert(ok, 'player cannot use admin_row_upsert');
  ok := false;
  begin perform admin_table_rows('zone_actions'); exception when others then ok := true; end;
  perform pg_temp.assert(ok, 'player cannot list admin rows');
  set local role authenticated;
  ok := false;
  begin update place_zones set x = 1 where id = 'club.bar'; exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'player cannot write place_zones directly');
  ok := false;
  begin insert into zone_actions (id, zone_id, kind, ref) values ('p.x', 'club.bar', 'activity', 'club_dance'); exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'player cannot write zone_actions directly');
  perform pg_temp.assert((select count(*) from place_zones) > 50, 'player can read the zones');
  reset role;
  perform pg_temp.assert((select x from place_zones where id = 'club.bar') = 3.1, 'bar unchanged by the player');
  raise notice 'ok 7: admin edits zones, players cannot';
  raise notice 'ALL PLACES TESTS PASSED';
end $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
end $$;
