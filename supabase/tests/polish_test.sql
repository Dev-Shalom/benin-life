-- P1 polish batch (20261006001600_polish.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/polish_test.sql
-- Groups: 1 every active place type has roster people + crowd profiles (and people at quiet places at 8 PM)
-- · 2 the luxury cars + extra vehicles exist, sold at the dealers only, on the showroom / lot cards
-- · 3 buying one unlocks own-vehicle travel (bicycle slow + free, motorcycle fast + cheap, car)
-- · 4 action.queue_max default logic (5 -> 7 only when untouched), crowd.rigs_high.

create or replace function pg_temp.po_hint(p_sql text, p_hint text) returns text
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

-- move the test clock so the Benin clock reads p_hour:30
create or replace function pg_temp.po_at_hour(p_hour int) returns void
language plpgsql as $$
declare c jsonb; cur numeric; delta numeric;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  c := bl_game_clock();
  cur := (c->>'hour')::numeric * 3600 + (c->>'minute')::numeric * 60;
  delta := ((p_hour * 3600 + 1800 - cur)::numeric % 86400 + 86400) % 86400;
  perform set_config('bl.test_offset_seconds', delta::text, true);
end $$;

create temp table t_po (name text primary key, id uuid not null) on commit drop;
grant select on t_po to authenticated;

create or replace function pg_temp.po_make(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@polish.bl');
begin
  insert into t_po values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0 where id = v;
  return v;
end $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
end $$;

-- ---------- 1. people in every place ----------
do $$
declare v_missing text; v_thin text; v_gap text; a uuid := pg_temp.po_make('Po_Ada'); j jsonb; p text;
begin
  -- roster: every active non-home place type has 5+ people of its own (or the place has its own people)
  select string_agg(s, ', ') into v_thin from (
    select distinct l.scene as s from locations l
     where l.active and l.scene not like 'home%'
       and (select count(*) from npc_roster r where r.active
             and (l.id = any(r.location_ids) or (cardinality(r.location_ids) = 0 and l.scene = any(r.scenes)))) < 5) x;
  perform pg_temp.assert(v_thin is null, 'every active place has 5+ roster people, thin: ' || coalesce(v_thin, ''));
  -- the types the user listed are all covered
  select string_agg(s, ', ') into v_missing from unnest(array['pos','police','hospital','motorpark','office','shrine','palace',
      'stadium','zoo','hotel','cinema','mall','car_dealer','street','campus','bank','market','buka','club']) s
   where not exists (select 1 from npc_roster r where r.active and s = any(r.scenes))
     and not exists (select 1 from npc_roster r join locations l on l.id = any(r.location_ids) where r.active and l.scene = s);
  perform pg_temp.assert(v_missing is null, 'listed place types have people, missing: ' || coalesce(v_missing, ''));
  -- profiles: every active place type has a profile for every hour (weekday and weekend)
  select string_agg(distinct l.scene || '@' || h || '/' || wd, ', ') into v_gap
    from locations l, generate_series(0, 23) h, (values (1), (6)) w(wd)
   where l.active and l.scene not like 'home%' and bl_crowd_count(l.scene, h, wd) is null;
  perform pg_temp.assert(v_gap is null, 'profiles cover every hour, gaps: ' || coalesce(v_gap, ''));
  -- every active place type has staff on duty all day (base row > 0)
  select string_agg(distinct l.scene, ', ') into v_thin from locations l
   where l.active and l.scene not like 'home%' and l.scene not in ('market', 'buka')   -- markets/bukas empty at night on purpose
     and coalesce((select npcs from crowd_profiles where id = l.scene || '.all.0-24'), 0) < 1;
  perform pg_temp.assert(v_thin is null, 'base crowd > 0, empty: ' || coalesce(v_thin, ''));
  -- places that were empty at 8 PM on a weekday now have people
  perform pg_temp.login(a);
  foreach p in array array['sdd_motors', 'bronze_bank', 'national_museum', 'igun_street', 'fresh_cut_salon'] loop
    j := place_people(p, 20, 1);
    perform pg_temp.assert((j->>'open')::boolean is false or jsonb_array_length(j->'npcs') >= 2,
      format('%s has people at 8 PM: %s', p, j));
  end loop;
  -- the car dealer daytime has the saleswoman, headliners first
  j := place_people('sdd_motors', 11, 1);
  perform pg_temp.assert(j::text like '%car_sales_amenze%' and (j->'npcs'->0->>'headliner')::boolean, 'Amenze + a headliner first at the dealer: ' || j::text);
  raise notice 'ok 1: people in every place';
end $$;

-- ---------- 2. the cars ----------
do $$
declare v_cars text[] := array['gwagon_g63','gle63_coupe','lambo_urus','tesla_cybertruck','escalade','benz_c300','camry_new','bajaj_boxer','bicycle'];
        c text; it items; j jsonb; a uuid := pg_temp.po_make('Po_Ben');
begin
  foreach c in array v_cars loop
    select * into it from items where id = c;
    perform pg_temp.assert(it.id is not null and it.category = 'vehicle', c || ' is a vehicle item');
    perform pg_temp.assert(it.sold_at <@ array(select id from locations where scene = 'car_dealer') and cardinality(it.sold_at) = 3,
      c || ' sold at the three dealers only: ' || it.sold_at::text);
    perform pg_temp.assert(coalesce(it.icon, '') <> '', c || ' has an icon');
  end loop;
  perform pg_temp.assert((select price from items where id = 'gwagon_g63') = 350000000, 'G-Wagon 350m');
  perform pg_temp.assert((select price from items where id = 'gle63_coupe') = 180000000, 'GLE 180m');
  perform pg_temp.assert((select price from items where id = 'lambo_urus') = 450000000, 'Urus 450m');
  perform pg_temp.assert((select price from items where id = 'tesla_cybertruck') = 250000000, 'Cybertruck 250m');
  perform pg_temp.assert((select price from items where id = 'camry_new') > (select price from items where id = 'camry_muscle'), 'new Camry dearer than the tokunbo one');
  perform pg_temp.assert((select price from items where id = 'bicycle') < (select price from items where id = 'bajaj_boxer'), 'bicycle < motorcycle');
  -- on the cards at every dealer
  perform pg_temp.login(a);
  foreach c in array array['ighodalo_cars', 'sdd_motors', 'tokunbo_lot'] loop
    j := place_interior(c);
    perform pg_temp.assert(j::text like '%lambo_urus%' and j::text like '%gwagon_g63%' and j::text like '%tesla_cybertruck%'
                           and j::text like '%gle63_coupe%' and j::text like '%escalade%' and j::text like '%bicycle%',
                           c || ' shows the cars');
    perform pg_temp.assert(exists (select 1 from jsonb_array_elements(j->'zones') z where z->>'prop' = 'lux_cars'), c || ' has the luxury showroom');
  end loop;
  -- not sold anywhere else
  update profiles set location_id = 'oba_market', cash = 1000000000, busy_until = null where id = a;
  perform pg_temp.po_hint($q$ select shop_buy('lambo_urus', 1) $q$, 'not_sold_here');
  perform pg_temp.po_hint($q$ select shop_buy('bicycle', 1) $q$, 'not_sold_here');
  raise notice 'ok 2: luxury cars + vehicles at the dealers';
end $$;

-- ---------- 3. buying unlocks own-vehicle travel ----------
do $$
declare a uuid := pg_temp.po_make('Po_Car'); b uuid := pg_temp.po_make('Po_Bike'); m uuid := pg_temp.po_make('Po_Moto');
        q jsonb; o jsonb; r jsonb; p profiles; car_gm int; bike jsonb; moto jsonb;
begin
  perform pg_temp.po_at_hour(11);
  -- G-Wagon at SDD Motors: bank first, then cash
  perform pg_temp.login(a);
  update profiles set location_id = 'sdd_motors', cash = 50000000, bank = 300000000, busy_until = null where id = a;
  q := travel_quote('mama_ebo');
  perform pg_temp.assert(not (select (x->>'allowed')::boolean from jsonb_array_elements(q->'options') x where x->>'mode' = 'car'), 'no car yet');
  r := shop_buy('gwagon_g63', 1);
  select * into p from profiles where id = a;
  perform pg_temp.assert((r->>'car')::boolean and p.bank = 0 and p.cash = 0, format('paid 300m bank + 50m cash (bank %s cash %s)', p.bank, p.cash));
  perform pg_temp.po_hint($q$ select shop_buy('gwagon_g63', 1) $q$, 'already_owned');
  update profiles set cash = 100000 where id = a;
  q := travel_quote('mama_ebo');
  select x into o from jsonb_array_elements(q->'options') x where x->>'mode' = 'car';
  perform pg_temp.assert((o->>'allowed')::boolean and o->>'label' = 'Your own car' and o->>'vehicle' = 'car', 'car travel unlocked: ' || o::text);
  car_gm := (o->>'game_minutes')::int;
  -- bicycle only: slow and free
  perform pg_temp.login(b);
  update profiles set location_id = 'sdd_motors', cash = 200000, bank = 0, busy_until = null where id = b;
  perform shop_buy('bicycle', 1);
  update profiles set cash = 0 where id = b;
  q := travel_quote('mama_ebo');
  select x into bike from jsonb_array_elements(q->'options') x where x->>'mode' = 'car';
  perform pg_temp.assert((bike->>'allowed')::boolean and bike->>'label' = 'Your bicycle' and (bike->>'cost')::int = 0,
    'bicycle travel is free (even with no cash): ' || bike::text);
  -- motorcycle only: fast and cheap
  perform pg_temp.login(m);
  update profiles set location_id = 'sdd_motors', cash = 2000000, bank = 0, busy_until = null where id = m;
  perform shop_buy('bajaj_boxer', 1);
  update profiles set cash = 100000 where id = m;
  q := travel_quote('mama_ebo');
  select x into moto from jsonb_array_elements(q->'options') x where x->>'mode' = 'car';
  perform pg_temp.assert((moto->>'allowed')::boolean and moto->>'label' = 'Your motorcycle' and (moto->>'cost')::int > 0
    and (moto->>'cost')::int < (select (x->>'cost')::int from jsonb_array_elements(q->'options') x where x->>'mode' = 'drop'),
    'motorcycle is cheap: ' || moto::text);
  perform pg_temp.assert((moto->>'game_minutes')::int < (bike->>'game_minutes')::int, 'motorcycle faster than the bicycle');
  perform pg_temp.assert((bike->>'game_minutes')::int > car_gm, 'bicycle slower than a car');
  -- travel_start works with it
  r := travel_start('mama_ebo', 'car');
  perform pg_temp.assert((select travel_mode from profiles where id = m) = 'car', 'set off on the motorcycle');
  raise notice 'ok 3: own-vehicle travel';
end $$;

-- ---------- 4. queue_max default logic ----------
do $$
declare v jsonb;
begin
  perform pg_temp.assert(bl_cfg('action.queue_max') >= 7 or bl_cfg('action.queue_max') <> 5, 'queue_max no longer the old default 5');
  -- untouched default -> 7
  update game_config set value = '5'::jsonb where key = 'action.queue_max';
  update public.game_config set value = '7'::jsonb where key = 'action.queue_max' and value = '5'::jsonb;  -- the migration's statement
  perform pg_temp.assert(bl_cfg('action.queue_max') = 7, 'old default 5 becomes 7');
  -- an admin edit stays
  update game_config set value = '9'::jsonb where key = 'action.queue_max';
  update public.game_config set value = '7'::jsonb where key = 'action.queue_max' and value = '5'::jsonb;
  perform pg_temp.assert(bl_cfg('action.queue_max') = 9, 'admin value 9 kept');
  select value into v from game_config where key = 'crowd.rigs_high';
  perform pg_temp.assert(v::text::int between 0 and 8, 'rigs_high in range');
  perform pg_temp.assert((select value from game_config where key = 'places.p1_people_seeded') = 'true'::jsonb, 'seeded flag set');
  raise notice 'ok 4: queue_max default';
end $$;
