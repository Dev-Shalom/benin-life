-- Filling stations and the black market (20261113000200_fuel_market.sql, docs/POWER.md parts 2 and 3). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/fuel_market_test.sql
-- Groups: 1 stations seeded, the yard hidden by RLS · 2 daily price band, determinism, same for everybody · 3 buying at a station (shop_buy,
-- queue) · 4 fuel scarcity (admin start / end, price x1.6, dry stations, random one) · 5 a player-owned Filling station (the visitor cut) ·
-- 6 station info and the attendant · 7 black market unlock (street cred, crew), night hours · 8 deals with bl.test_rand pinned (clean, scam,
-- raid -> jail case, robbery, stolen, faulty, grey fuel) · 9 adulterated fuel hurts the generator for a while, a mechanic fixes it ·
-- 10 expected value near the legit price · 11 grants / RLS.
-- All times are pinned with bl.test_offset_seconds, so it passes at any hour. Risks are forced with the settings (0 or 100 %).
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

create or replace function pg_temp.at(p_local text) returns void
language plpgsql as $$
begin
  perform set_config('bl.test_offset_seconds', extract(epoch from (p_local::timestamp at time zone 'Africa/Lagos') - now())::text, true);
  update profiles set rent_due_at = null, busy_until = null where username like 'FM\_%';
end $$;

create or replace function pg_temp.uid(p_name text) returns uuid
language plpgsql as $$ declare v uuid; begin select id into v from pg_temp.fm_u where name = p_name; return v; end $$;

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key $$;

create or replace function pg_temp.give(p_uid uuid, p_furn text, p_qty int default 1) returns void
language sql as $$
  insert into player_furniture (user_id, furniture_id, slot, source, qty) values (p_uid, p_furn, null, 'buy', p_qty)
  on conflict (user_id, furniture_id) do update set qty = excluded.qty
$$;

create temp table fm_u (name text primary key, id uuid);

do $$
declare v uuid; r record;
begin
  for r in select * from (values ('buyer', 'ekenwan_face_me'), ('owner', 'ekenwan_face_me'), ('admin', 'aduwawa_face_me'), ('cred', 'ekenwan_face_me'),
                                 ('crew', 'ekenwan_face_me'), ('green', 'ekenwan_face_me')) x(n, home) loop
    v := pg_temp.new_user('fm_' || r.n || '@fuel.bl');
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    perform pg_temp.login(v);
    perform create_profile_v2('FM_' || r.n, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home(r.home);
    insert into fm_u values (r.n, v);
  end loop;
  update profiles set is_admin = true where id = pg_temp.uid('admin');
  update profiles set cash = 3000000, bank = 5000000 where username like 'FM\_%';
  update profiles set street_cred = 0 where username like 'FM\_%';
  update profiles set street_cred = 30 where id = pg_temp.uid('cred');
  update game_config set value = '0' where key = 'fuel.random_scarcity_chance_pct';   -- no surprise scarcity in the price tests
end $$;

-- ---------- 1. stations seeded, the yard hidden ----------
do $$
declare v_green uuid := pg_temp.uid('green'); v_cred uuid := pg_temp.uid('cred'); n int;
begin
  perform pg_temp.assert((select count(*) from locations where id like 'fs\_%' and active and scene = 'motorpark' and 'shop' = any (actions)) = 7, 'seven filling stations on the map');
  perform pg_temp.assert((select count(distinct district) from locations where id like 'fs\_%') >= 5, 'in at least five areas');
  perform pg_temp.assert(not exists (select 1 from locations l where l.id like 'fs\_%' and exists (select 1 from locations o where o.id <> l.id and o.active and sqrt(power(o.x - l.x, 2) + power(o.y - l.y, 2)) < 30)),
                         'no station pin sits on top of another place');
  perform pg_temp.assert((select count(*) from items where category = 'fuel' and id in ('petrol', 'petrol_can', 'diesel', 'diesel_can') and cardinality(sold_at) = 7) = 4,
                         'petrol, diesel and both cans are sold at the seven stations');
  perform pg_temp.assert(not exists (select 1 from items where id in ('petrol_bm', 'diesel_bm') and cardinality(sold_at) > 0), 'grey fuel is not on any normal shelf');
  perform pg_temp.assert((select litres from power_gear where id = 'petrol_can') = 5 and (select litres from power_gear where id = 'diesel_can') = 20, 'a petrol can is 5 L and a diesel can 20 L');
  -- the yard: not on the map for a player who has not earned the way in
  execute 'set local role authenticated';
  perform pg_temp.login(v_green);
  select count(*) into n from locations where id = 'bm_yard';
  perform pg_temp.assert(n = 0, 'a new player cannot see the yard');
  select count(*) into n from locations where id like 'fs\_%';
  perform pg_temp.assert(n = 7, 'but sees the stations');
  perform pg_temp.login(v_cred);
  select count(*) into n from locations where id = 'bm_yard';
  perform pg_temp.assert(n = 1, 'a player with street cred sees the yard');
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  select count(*) into n from locations where id = 'bm_yard';
  perform pg_temp.assert(n = 0, 'anon never sees the yard');
  execute 'reset role';
end $$;

-- ---------- 2. daily price band ----------
do $$
declare
  petrol items; diesel items; can items; d int; p bigint; pmin bigint := 1e9; pmax bigint := 0; prev bigint; maxmove numeric := 0; moves int := 0; q bigint; dmin bigint := 1e9; dmax bigint := 0;
  a bigint; b bigint; ts text;
begin
  select * into petrol from items where id = 'petrol'; select * into diesel from items where id = 'diesel'; select * into can from items where id = 'petrol_can';
  for d in 0 .. 59 loop
    ts := (date '2026-11-20' + d)::text || ' 12:00:00';
    perform pg_temp.at(ts);
    p := bl_fuel_price(petrol, 'fs_sapele');
    pmin := least(pmin, p); pmax := greatest(pmax, p);
    q := bl_fuel_price(diesel, 'fs_sapele'); dmin := least(dmin, q); dmax := greatest(dmax, q);
    if prev is not null then maxmove := greatest(maxmove, abs(p - prev)::numeric / prev); if p <> prev then moves := moves + 1; end if; end if;
    prev := p;
    -- deterministic: asking twice, at another hour of the same Benin day, and for another station of the same price band
    perform pg_temp.assert(bl_fuel_price(petrol, 'fs_sapele') = p, 'same price when asked twice');
    perform pg_temp.at((date '2026-11-20' + d)::text || ' 23:30:00');
    perform pg_temp.assert(bl_fuel_price(petrol, 'fs_sapele') = p, 'the whole Benin day has one price');
    perform pg_temp.assert(abs(bl_fuel_price(petrol, 'fs_ugbowo') - p) <= p * 0.045, 'stations differ by a couple of percent at most');
    a := bl_fuel_price(can, 'fs_sapele');
    perform pg_temp.assert(abs(a - p * 5 * 0.98) <= 60, 'a 5 L can is 5 litres less the can discount');
  end loop;
  perform pg_temp.assert(pmin >= 900 and pmax <= 1200, 'petrol stays between N900 and N1,200 a litre over 60 days (' || pmin || ' to ' || pmax || ')');
  perform pg_temp.assert(dmin > pmin and dmax <= 1450, 'diesel is dearer and stays sensible (' || dmin || ' to ' || dmax || ')');
  perform pg_temp.assert(moves >= 40, 'the price moves most days (' || moves || ')');
  perform pg_temp.assert(maxmove <= 0.14, 'but only a little each day (largest move ' || round(maxmove * 100, 1) || ' %)');
  -- same for two players (it does not depend on the player)
  perform pg_temp.at('2026-11-20 12:00:00');
  perform pg_temp.login(pg_temp.uid('buyer'));
  a := (fuel_station_info('fs_sapele') ->> 'petrol')::bigint;
  perform pg_temp.login(pg_temp.uid('green'));
  b := (fuel_station_info('fs_sapele') ->> 'petrol')::bigint;
  perform pg_temp.assert(a = b and a = bl_fuel_price(petrol, 'fs_sapele'), 'two players see the same price');
  -- the shop price follows (bl_shop_price is patched)
  perform pg_temp.assert(bl_shop_price(petrol, 'fs_sapele') = a, 'bl_shop_price uses the fuel price');
  perform pg_temp.assert(bl_dealer_price(petrol, 'fs_sapele') = a, 'and so does the dealer price the shop charges');
  -- the admin base price moves it
  update game_config set value = '2000' where key = 'fuel.petrol_price';
  perform pg_temp.assert(bl_fuel_price(petrol, 'fs_sapele') > 1700, 'admin base price is live');
  update game_config set value = '1050' where key = 'fuel.petrol_price';
end $$;

-- ---------- 3. buying at a station ----------
do $$
declare
  u uuid := pg_temp.uid('buyer'); r jsonb; price bigint; c0 bigint; petrol items; l0 int; q0 int;
begin
  perform pg_temp.at('2026-11-21 12:00:00');
  select * into petrol from items where id = 'petrol';
  perform pg_temp.login(u);
  update profiles set location_id = 'fs_sapele', travel_to = null where id = u;
  select cash into c0 from profiles where id = u;
  price := bl_fuel_price(petrol, 'fs_sapele');
  r := shop_buy('petrol', 3);
  perform pg_temp.assert((select qty from inventory where user_id = u and item_id = 'petrol') = 3, 'three litres in the bag');
  perform pg_temp.assert(c0 - (select cash from profiles where id = u) = price * 3, 'paid three litres at the station price (' || price || ' each)');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = u and delta = -price * 3), 'one ledger line for the purchase');
  r := shop_buy('petrol_can', 1);
  perform pg_temp.assert((select qty from inventory where user_id = u and item_id = 'petrol_can') = 1, 'a jerrycan');
  perform pg_temp.assert(pg_temp.hint_of($q$select shop_buy('petrol_bm', 1)$q$) = 'not_sold_here', 'grey fuel is not sold at a station');
  -- not at a station: not sold here
  update profiles set location_id = 'uniben' where id = u;
  perform pg_temp.assert(pg_temp.hint_of($q$select shop_buy('petrol', 1)$q$) = 'not_sold_here', 'petrol is only sold at stations');
  update profiles set location_id = 'fs_sapele' where id = u;
  -- a short queue when the admin asks for one
  update game_config set value = '12' where key = 'fuel.queue_seconds';
  update profiles set busy_until = null where id = u;
  r := shop_buy('petrol', 1);
  perform pg_temp.assert((select busy_until from profiles where id = u) > bl_now() + interval '8 seconds', 'a queue wait keeps the player busy');
  update game_config set value = '0' where key = 'fuel.queue_seconds';
  update profiles set busy_until = null where id = u;
end $$;

-- ---------- 4. fuel scarcity ----------
do $$
declare
  petrol items; adm uuid := pg_temp.uid('admin'); u uuid := pg_temp.uid('buyer'); normal bigint; scarce bigint; r jsonb; s text; dry int; open_s text; yday bigint;
begin
  perform pg_temp.at('2026-11-22 12:00:00');
  select * into petrol from items where id = 'petrol';
  normal := bl_fuel_price(petrol, 'fs_sapele');
  perform pg_temp.assert(not bl_fuel_scarce() and not bl_fuel_dry('fs_sapele'), 'no scarcity by default');
  perform pg_temp.login(pg_temp.uid('green'));
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_power_event_start('scarcity', 4, '')$q$) <> 'ok', 'a player cannot start a scarcity');
  perform pg_temp.login(adm);
  r := admin_power_event_start('scarcity', 4, 'test scarcity');
  perform pg_temp.assert(bl_fuel_scarce(), 'scarcity on');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'power_scarcity_start') = 1, 'scarcity start is audited');
  scarce := bl_fuel_price(petrol, 'fs_sapele');
  perform pg_temp.assert(abs(scarce::numeric / normal - 1.6) < 0.03, 'price x1.6 in a scarcity (' || normal || ' to ' || scarce || ')');
  -- every station dry / none dry (admin dial), the others sell with a long queue
  update game_config set value = '100' where key = 'fuel.scarcity_dry_pct';
  perform pg_temp.assert((select count(*) from locations where id like 'fs\_%' and bl_fuel_dry(id)) = 7, 'dry share 100 %: every station is dry');
  perform pg_temp.login(u);
  update profiles set location_id = 'fs_sapele', busy_until = null where id = u;
  perform pg_temp.assert(pg_temp.hint_of($q$select shop_buy('petrol', 1)$q$) = 'station_dry', 'a dry station sells nothing');
  update game_config set value = '0' where key = 'fuel.scarcity_dry_pct';
  perform pg_temp.assert((select count(*) from locations where id like 'fs\_%' and bl_fuel_dry(id)) = 0, 'dry share 0 %: none dry');
  perform pg_temp.assert(pg_temp.hint_of($q$select shop_buy('petrol', 1)$q$) = 'ok', 'buying works at a station with fuel');
  perform pg_temp.assert((select busy_until from profiles where id = u) > bl_now() + interval '20 seconds', 'long queue in a scarcity');
  update profiles set busy_until = null where id = u;
  -- some stations dry, some not, fixed by date and station: the same answer all day
  update game_config set value = '50' where key = 'fuel.scarcity_dry_pct';
  select count(*) into dry from locations where id like 'fs\_%' and bl_fuel_dry(id);
  perform pg_temp.at('2026-11-22 14:00:00');
  perform pg_temp.assert((select count(*) from locations where id like 'fs\_%' and bl_fuel_dry(id)) = dry, 'the dry stations stay the same all day');
  perform pg_temp.at('2026-11-22 12:00:00');
  update game_config set value = '35' where key = 'fuel.scarcity_dry_pct';
  -- the attendant
  r := fuel_station_info('fs_sapele');
  perform pg_temp.assert((r ->> 'scarce')::boolean and r ->> 'state' in ('scarce', 'dry') and length(r ->> 'line') > 10, 'the attendant says queue is long');
  perform pg_temp.assert((r ->> 'queue_seconds')::int = 25, 'info shows the queue');
  -- end it
  perform pg_temp.login(adm);
  r := admin_power_event_end('scarcity');
  perform pg_temp.assert((r ->> 'ended')::int = 1 and not bl_fuel_scarce(), 'scarcity ended');
  perform pg_temp.assert(bl_fuel_price(petrol, 'fs_sapele') = normal, 'price back to normal');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'power_scarcity_end') = 1, 'end is audited');
  -- the rare random one: on = deterministic window, default is rare
  perform pg_temp.assert((select value::text from game_config where key = 'fuel.random_scarcity_chance_pct') = '0', 'test switched it off (default is 2)');
  update game_config set value = '100' where key = 'fuel.random_scarcity_chance_pct';
  update game_config set value = '24' where key = 'fuel.random_scarcity_hours';
  perform pg_temp.assert(bl_fuel_scarce(), 'a random scarcity that lasts a day is on');
  update game_config set value = '0' where key = 'fuel.random_scarcity_chance_pct';
  perform pg_temp.assert(not bl_fuel_scarce(), 'off again');
  update game_config set value = '10' where key = 'fuel.random_scarcity_hours';
end $$;

-- ---------- 5. a player-owned Filling station ----------
do $$
declare
  adm uuid := pg_temp.uid('admin'); o uuid := pg_temp.uid('owner'); b uuid := pg_temp.uid('buyer'); r jsonb; plot text := 'biz_ring_road_1'; petrol items; price bigint;
  bank0 bigint; cut bigint; paid bigint; c0 bigint; own_c0 bigint;
begin
  perform pg_temp.at('2026-11-23 12:00:00');
  select * into petrol from items where id = 'petrol';
  perform pg_temp.login(adm);
  r := admin_business_grant(o, 'filling_station', plot, 'Osas Pumps');
  perform pg_temp.assert((select biz_owner from locations where id = plot) is not null, 'the plot is now a station owned by a player');
  perform pg_temp.assert(bl_biz_sells(plot, 'petrol') and bl_biz_sells(plot, 'diesel_can'), 'an owned Filling station sells the same fuel shelf');
  perform pg_temp.assert(not bl_biz_sells(plot, 'petrol_bm'), 'but not grey fuel');
  price := bl_fuel_price(petrol, plot);
  perform pg_temp.assert(price between 900 and 1250, 'priced like any station (' || price || ')');
  -- a visitor buys: the owner gets the visitor cut
  perform pg_temp.login(b);
  update profiles set location_id = plot, busy_until = null where id = b;
  select bank into bank0 from profiles where id = o;
  select cash into c0 from profiles where id = b;
  r := shop_buy('petrol', 10);
  paid := c0 - (select cash from profiles where id = b);
  perform pg_temp.assert(paid = price * 10, 'visitor paid the pump price');
  cut := (select bank from profiles where id = o) - bank0;
  perform pg_temp.assert(cut = floor(paid * (select (value #>> '{}')::numeric from game_config where key = 'business.visit_cut_pct') / 100.0), 'owner earned the visitor cut (' || cut || ' of ' || paid || ')');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = o and reason = 'business_income' and delta = cut), 'ledger business_income for the owner');
  -- the owner buying at their own pumps pays no cut
  perform pg_temp.login(o);
  update profiles set location_id = plot, busy_until = null where id = o;
  select bank into bank0 from profiles where id = o;
  perform shop_buy('petrol', 2);
  perform pg_temp.assert((select bank from profiles where id = o) = bank0, 'no cut on your own purchase');
  -- the owned station has the same attendant info and shows the owner
  r := fuel_station_info(plot);
  perform pg_temp.assert((r ->> 'station')::boolean and r ->> 'owner' is not null, 'station info names the owner');
  -- scarcity applies to it too (it may be dry by the date hash)
  perform pg_temp.login(adm);
  perform admin_power_event_start('scarcity', 2, '');
  update game_config set value = '100' where key = 'fuel.scarcity_dry_pct';
  perform pg_temp.login(b);
  update profiles set location_id = plot, busy_until = null where id = b;
  perform pg_temp.assert(pg_temp.hint_of($q$select shop_buy('petrol', 1)$q$) = 'station_dry', 'an owned station can run dry too');
  update game_config set value = '35' where key = 'fuel.scarcity_dry_pct';
  perform pg_temp.login(adm);
  perform admin_power_event_end('scarcity');
end $$;

-- ---------- 6. station info ----------
do $$
declare r jsonb; u uuid := pg_temp.uid('buyer'); n int; s text; st text[] := '{}';
begin
  perform pg_temp.login(u);
  perform pg_temp.at('2026-11-24 12:00:00');
  r := fuel_station_info('fs_airport');
  perform pg_temp.assert((r ->> 'station')::boolean and r ->> 'name' like '%Airport%' and (r ->> 'petrol')::int > 0 and (r ->> 'diesel')::int > (r ->> 'petrol')::int, 'info: name, petrol, diesel');
  perform pg_temp.assert(length(r ->> 'line') > 10 and r ->> 'state' in ('normal', 'up', 'down'), 'the attendant has a line (' || (r ->> 'state') || ')');
  perform pg_temp.assert(not (fuel_station_info('uniben') ->> 'station')::boolean, 'a campus is not a station');
  -- over 40 days the attendant mentions both ups and downs
  for n in 0 .. 39 loop
    perform pg_temp.at((date '2026-11-24' + n)::text || ' 12:00:00');
    s := fuel_station_info('fs_airport') ->> 'state';
    if not (s = any (st)) then st := st || s; end if;
  end loop;
  perform pg_temp.assert(st @> array['up'] and st @> array['down'], 'prices go up and down (' || array_to_string(st, ',') || ')');
  -- every attendant line is Pidgin-flavoured and varied
  perform pg_temp.assert((select count(distinct bl_fuel_line('fs_airport', x)) from unnest(array['normal', 'dry', 'scarce', 'up', 'down']) x) = 5, 'a line per state');
end $$;

-- ---------- 7. black market unlock and hours ----------
do $$
declare r jsonb; g uuid := pg_temp.uid('green'); c uuid := pg_temp.uid('cred'); w uuid := pg_temp.uid('crew'); crew_id int;
begin
  perform pg_temp.assert(not bl_bm_unlocked(g), 'a green player is locked out');
  perform pg_temp.assert(bl_bm_unlocked(c), 'street cred 30 unlocks (the setting is 20)');
  update profiles set street_cred = 19 where id = c;
  perform pg_temp.assert(not bl_bm_unlocked(c), '19 is not enough');
  update profiles set street_cred = 20 where id = c;
  perform pg_temp.assert(bl_bm_unlocked(c), '20 is enough');
  -- crew members get in without the cred
  insert into crews (name, tag, created_by) values ('FM Crew', 'FMC', w) returning id into crew_id;
  insert into crew_members (user_id, crew_id, rank) values (w, crew_id, 'boss');
  perform pg_temp.assert(bl_bm_unlocked(w), 'a crew member is let in');
  update game_config set value = 'false' where key = 'blackmarket.crew_unlocks';
  perform pg_temp.assert(not bl_bm_unlocked(w), 'crew entry can be switched off');
  update game_config set value = 'true' where key = 'blackmarket.crew_unlocks';
  update game_config set value = 'false' where key = 'blackmarket.enabled';
  perform pg_temp.assert(not bl_bm_unlocked(c), 'the whole black market can be switched off');
  update game_config set value = 'true' where key = 'blackmarket.enabled';
  -- hours (Benin time): open 21:00 to 05:00
  perform pg_temp.at('2026-11-25 12:00:00');
  perform pg_temp.assert(not bl_bm_open_now(), 'shut at noon');
  perform pg_temp.at('2026-11-25 20:59:00');
  perform pg_temp.assert(not bl_bm_open_now(), 'shut at 20:59');
  perform pg_temp.at('2026-11-25 21:00:00');
  perform pg_temp.assert(bl_bm_open_now(), 'open at 21:00');
  perform pg_temp.at('2026-11-26 02:00:00');
  perform pg_temp.assert(bl_bm_open_now(), 'open at 02:00');
  perform pg_temp.at('2026-11-26 05:01:00');
  perform pg_temp.assert(not bl_bm_open_now(), 'shut after 05:00');
  update game_config set value = '18' where key = 'blackmarket.open_hour';
  perform pg_temp.at('2026-11-26 18:30:00');
  perform pg_temp.assert(bl_bm_open_now(), 'admin hours: open from 18:00');
  update game_config set value = '21' where key = 'blackmarket.open_hour';
  -- bm_status
  perform pg_temp.login(g);
  perform pg_temp.at('2026-11-26 23:00:00');
  r := bm_status();
  perform pg_temp.assert(not (r ->> 'unlocked')::boolean and not r ? 'offers', 'a locked player learns nothing');
  perform pg_temp.login(c);
  r := bm_status();
  perform pg_temp.assert((r ->> 'unlocked')::boolean and (r ->> 'open')::boolean and jsonb_array_length(r -> 'offers') = 7, 'unlocked and open: seven offers');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r -> 'offers') o where not (o ? 'risk') or not (o ? 'price')), 'every offer shows its price and risk');
  perform pg_temp.at('2026-11-26 12:00:00');
  r := bm_status();
  perform pg_temp.assert(not (r ->> 'open')::boolean and jsonb_array_length(r -> 'offers') = 0, 'by day the shelf is empty');
  -- the place itself: entering it is checked by the same rule as any closed place
  perform pg_temp.assert(pg_temp.hint_of($q$select bl_bm_guard((select l from locations l where id = 'bm_yard'))$q$) = 'closed', 'by day the yard is shut');
  perform pg_temp.login(g);
  perform pg_temp.assert(pg_temp.hint_of($q$select bl_bm_guard((select l from locations l where id = 'bm_yard'))$q$) = 'inactive', 'a green player is told it is closed');
  update profiles set street_cred = 0 where id = c;
  update profiles set street_cred = 30 where id = c;
end $$;

-- ---------- 8. deals ----------
create or replace function pg_temp.zero_risks() returns void
language plpgsql as $$
begin
  update game_config set value = '0' where key in ('blackmarket.scam_pct', 'blackmarket.raid_pct', 'blackmarket.robbery_pct', 'blackmarket.hot_night_pct', 'power.bad_fuel_pct');
  update bm_offers set faulty_pct = 0, stolen_pct = 0;
  perform set_config('bl.test_rand', '0.5', true);
end $$;

do $$
declare
  c uuid := pg_temp.uid('cred'); r jsonb; c0 bigint; bag int; price bigint; cred0 int; w0 int; n int; case_row jail_cases; fur0 int; lost bigint;
begin
  perform pg_temp.at('2026-11-26 23:00:00');
  perform pg_temp.login(c);
  update profiles set location_id = 'bm_yard', travel_to = null, cash = 4000000, busy_until = null, jailed_until = null, wanted = 0, street_cred = 30 where id = c;
  -- preconditions
  perform pg_temp.zero_risks();
  update profiles set location_id = 'uniben' where id = c;
  perform pg_temp.assert(pg_temp.hint_of($q$select bm_buy('grey_petrol', 1)$q$) = 'not_here', 'you must be at the yard');
  update profiles set location_id = 'bm_yard' where id = c;
  perform pg_temp.assert(pg_temp.hint_of($q$select bm_buy('grey_petrol', 0)$q$) = 'bad_qty' and pg_temp.hint_of($q$select bm_buy('grey_petrol', 500)$q$) = 'bad_qty', 'bad quantities refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select bm_buy('nothing', 1)$q$) = 'unknown_offer', 'unknown offer refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select bm_buy('tk_tiger', 2)$q$) = 'bad_qty', 'one piece of gear at a time');
  update profiles set cash = 100 where id = c;
  perform pg_temp.assert(pg_temp.hint_of($q$select bm_buy('grey_petrol', 5)$q$) = 'not_enough_cash', 'cash only, and enough of it');
  update profiles set cash = 4000000 where id = c;
  perform pg_temp.at('2026-11-26 12:00:00');
  perform pg_temp.assert(pg_temp.hint_of($q$select bm_buy('grey_petrol', 1)$q$) = 'closed', 'no deals by day');
  perform pg_temp.at('2026-11-26 23:00:00');
end $$;

do $$
declare
  c uuid := pg_temp.uid('cred'); r jsonb; c0 bigint; price bigint; cred0 int; n int; k jail_cases; lost bigint; bag0 int;
begin
  perform pg_temp.at('2026-11-26 23:00:00');
  perform pg_temp.login(c);
  update profiles set location_id = 'bm_yard', travel_to = null, cash = 4000000, busy_until = null, jailed_until = null, wanted = 0, street_cred = 30 where id = c;
  perform pg_temp.zero_risks();
  -- a clean deal: grey fuel, cheaper than the station, +cred, in the bag
  price := bl_bm_unit_price((select o from bm_offers o where id = 'grey_petrol'));
  perform pg_temp.assert(price < bl_fuel_price((select i from items i where i.id = 'petrol'), null), 'grey petrol is cheaper than the station on a normal day (' || price || ')');
  select cash, street_cred into c0, cred0 from profiles where id = c;
  r := bm_buy('grey_petrol', 10);
  perform pg_temp.assert(r ->> 'outcome' = 'ok' and (r ->> 'spent')::bigint = price * 10, 'clean deal pays 10 litres');
  perform pg_temp.assert((select qty from inventory where user_id = c and item_id = 'petrol_bm') = 10, 'ten litres of grey petrol in the bag');
  perform pg_temp.assert(c0 - (select cash from profiles where id = c) = price * 10, 'cash paid');
  perform pg_temp.assert((select street_cred from profiles where id = c) = cred0 + 1, 'a clean deal builds a little street cred');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = c and reason = 'blackmarket' and delta = -price * 10), 'ledger reason blackmarket');
  perform pg_temp.assert((select count(*) from ledger where user_id = c and reason = 'blackmarket') = 1, 'one ledger line');
  -- scam: money gone, nothing delivered
  update game_config set value = '100' where key = 'blackmarket.scam_pct';
  select cash into c0 from profiles where id = c; bag0 := (select qty from inventory where user_id = c and item_id = 'petrol_bm');
  r := bm_buy('grey_petrol', 5);
  perform pg_temp.assert(r ->> 'outcome' = 'scam' and (select qty from inventory where user_id = c and item_id = 'petrol_bm') = bag0, 'a scam delivers nothing');
  perform pg_temp.assert(c0 - (select cash from profiles where id = c) = price * 5, 'and takes the money');
  update game_config set value = '0' where key = 'blackmarket.scam_pct';
  -- robbery on the way out: no goods, some cash
  update game_config set value = '100' where key = 'blackmarket.robbery_pct';
  update game_config set value = '10' where key = 'blackmarket.robbery_cash_pct';
  select cash into c0 from profiles where id = c; bag0 := (select qty from inventory where user_id = c and item_id = 'petrol_bm');
  r := bm_buy('grey_petrol', 5);
  perform pg_temp.assert(r ->> 'outcome' = 'robbery' and (select qty from inventory where user_id = c and item_id = 'petrol_bm') = bag0, 'a robbery takes the goods');
  lost := (r ->> 'lost_cash')::bigint;
  perform pg_temp.assert(lost > 0 and lost <= 200000, 'and some cash, never over the cap (' || lost || ')');
  perform pg_temp.assert(c0 - (select cash from profiles where id = c) = price * 5 + lost, 'total cash loss is price plus the robbery');
  update game_config set value = '0' where key = 'blackmarket.robbery_pct';
  -- police raid: a jail case, wanted +1, cred down, nothing paid
  update game_config set value = '100' where key = 'blackmarket.raid_pct';
  update game_config set value = '0' where key = 'blackmarket.crew_raid_cut_pct';
  select cash, street_cred into c0, cred0 from profiles where id = c;
  r := bm_buy('grey_petrol', 5);
  perform pg_temp.assert(r ->> 'outcome' = 'raid' and (r ->> 'spent')::int = 0, 'raid: nothing is paid');
  perform pg_temp.assert((select cash from profiles where id = c) = c0, 'cash untouched in a raid');
  select * into k from jail_cases where user_id = c and status = 'open';
  perform pg_temp.assert(found and k.reason like '%raid%' and k.bail_amount > 0, 'a normal jail case with a bail is open (existing crime system)');
  perform pg_temp.assert((select wanted from profiles where id = c) = 1, 'wanted +1');
  perform pg_temp.assert((select street_cred from profiles where id = c) = cred0 - 3, 'street cred drops in a raid');
  perform pg_temp.assert((select jailed_until from profiles where id = c) > bl_now(), 'the player is held');
  -- the jailed player cannot deal
  perform pg_temp.assert(pg_temp.hint_of($q$select bm_buy('grey_petrol', 1)$q$) <> 'ok', 'jailed players cannot deal');
  update jail_cases set status = 'released', closed_at = bl_now() where id = k.id;
  update profiles set jailed_until = null, location_id = 'bm_yard', wanted = 0 where id = c;
  update game_config set value = '0' where key = 'blackmarket.raid_pct';
  -- the crew cuts the raid chance
  update game_config set value = '40' where key = 'blackmarket.crew_raid_cut_pct';
  update game_config set value = '10' where key = 'blackmarket.raid_pct';
  perform pg_temp.assert((bl_bm_risk((select o from bm_offers o where id = 'grey_petrol'), c) ->> 'raid_pct')::numeric = 10, 'no crew: full raid chance');
  perform pg_temp.assert((bl_bm_risk((select o from bm_offers o where id = 'grey_petrol'), pg_temp.uid('crew')) ->> 'raid_pct')::numeric = 6, 'crew: raid chance cut by 40 %');
  update game_config set value = '8' where key = 'blackmarket.hot_night_pct';
  update game_config set value = '100' where key = 'blackmarket.hot_night_pct';
  perform pg_temp.assert(bl_bm_hot() and (bl_bm_risk((select o from bm_offers o where id = 'grey_petrol'), c) ->> 'raid_pct')::numeric = 40, 'a hot night multiplies the raid chance');
  perform pg_temp.zero_risks();
  -- stolen goods: wanted +1, money and goods gone
  update bm_offers set stolen_pct = 100 where id = 'tk_tiger';
  select cash into c0 from profiles where id = c;
  r := bm_buy('tk_tiger', 1);
  perform pg_temp.assert(r ->> 'outcome' = 'stolen' and not exists (select 1 from player_furniture where user_id = c and furniture_id = 'gen_tiger'), 'hot goods are taken back at the gate');
  perform pg_temp.assert((select wanted from profiles where id = c) = 1, 'wanted +1 for hot goods');
  update profiles set wanted = 0 where id = c;
  update bm_offers set stolen_pct = 0 where id = 'tk_tiger';
  -- a clean gear deal: tokunbo generator at a discount, delivered to the home inventory
  price := bl_bm_unit_price((select o from bm_offers o where id = 'tk_tiger'));
  perform pg_temp.assert(price < (select bl_gross('furniture', f.category, f.price) from furniture f where f.id = 'gen_tiger'), 'tokunbo is cheaper than new (' || price || ')');
  select cash into c0 from profiles where id = c;
  r := bm_buy('tk_tiger', 1);
  perform pg_temp.assert(r ->> 'outcome' = 'ok' and exists (select 1 from player_furniture where user_id = c and furniture_id = 'gen_tiger' and qty = 1), 'a clean tokunbo generator arrives');
  perform pg_temp.assert(c0 - (select cash from profiles where id = c) = price, 'paid the tokunbo price');
  perform pg_temp.assert((power_status() #>> '{backup,generator,id}') = 'gen_tiger' and not (power_status() #>> '{backup,generator,faulty}')::boolean, 'the power system sees it, not faulty');
  -- max owned
  perform pg_temp.assert(pg_temp.hint_of($q$select bm_buy('tk_tiger', 1)$q$) in ('max_owned', 'ok'), 'max owned is respected');
  -- a faulty generator: coughs and burns more until a mechanic
  delete from player_furniture where user_id = c and furniture_id = 'gen_tiger';
  delete from player_power where user_id = c;
  update bm_offers set faulty_pct = 100 where id = 'tk_tiger';
  r := bm_buy('tk_tiger', 1);
  perform pg_temp.assert(r ->> 'outcome' = 'faulty' and (r ->> 'faulty')::boolean, 'faulty tokunbo generator');
  perform pg_temp.assert((power_status() #>> '{backup,generator,faulty}')::boolean, 'the generator shows as faulty');
  perform pg_temp.assert((select gen_burn_mult from player_power where user_id = c) = 1.6, 'and burns 1.6 times the fuel');
  -- a faulty battery holds less
  update bm_offers set faulty_pct = 100 where id = 'tk_inverter';
  r := bm_buy('tk_inverter', 1);
  perform pg_temp.assert(r ->> 'outcome' = 'faulty' and (select batt_health from player_power where user_id = c) = 60, 'a faulty inverter battery holds only 60 %');
  perform pg_temp.assert((power_status() #>> '{backup,inverter,cap_kwh}')::numeric = 0.72, 'capacity shows the weak battery (1.2 x 60 %)');
  -- the mechanic fixes both
  r := power_gen_repair();
  perform pg_temp.assert((select batt_health from player_power where user_id = c) = 100 and (select gen_burn_mult from player_power where user_id = c) = 1 and (select gen_fault_until from player_power where user_id = c) is null, 'the mechanic clears both faults');
  perform pg_temp.assert(pg_temp.hint_of($q$select power_gen_repair()$q$) = 'no_fault', 'nothing left to fix');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = c and reason = 'power_repair' and delta = -25000), 'the repair is a sink in the ledger');
  update bm_offers set faulty_pct = 0 where id in ('tk_tiger', 'tk_inverter');
  -- one hundred tries with a plain random roll: the shares are about the settings
  perform set_config('bl.test_rand', '', true);
  update game_config set value = '30' where key = 'blackmarket.scam_pct';
  update profiles set cash = 400000000 where id = c;
  n := 0;
  for r in select bm_buy('grey_petrol', 1) from generate_series(1, 200) loop
    if r ->> 'outcome' = 'scam' then n := n + 1; end if;
  end loop;
  perform pg_temp.assert(n between 35 and 85, 'a 30 % scam setting scams about 30 % of 200 random deals (' || n || ')');
end $$;

-- ---------- 9. adulterated fuel ----------
do $$
declare
  c uuid := pg_temp.uid('cred'); r jsonb; h_clean numeric; h_bad numeric; mult numeric;
begin
  perform pg_temp.at('2026-11-27 23:00:00');
  perform pg_temp.login(c);
  perform pg_temp.zero_risks();
  update profiles set cash = 4000000, location_id = 'bm_yard', jailed_until = null, wanted = 0, busy_until = null where id = c;
  delete from player_furniture where user_id = c;
  delete from player_power where user_id = c;
  delete from inventory where user_id = c and item_id in ('petrol_bm', 'petrol');
  perform pg_temp.give(c, 'gen_tiger') ;
  perform bl_give_item(c, 'petrol_bm', 5);
  -- grey fuel into a petrol generator, bad_fuel_pct 0: clean
  r := power_refuel('petrol_bm', 1);
  perform pg_temp.assert(not (r ->> 'bad_batch')::boolean, 'bad_fuel_pct 0: a clean pour');
  h_clean := (r #>> '{backup,generator,hours_left}')::numeric;
  perform power_gen_toggle(true);
  r := power_status();
  h_clean := (r #>> '{backup,generator,burn_lph}')::numeric;
  perform power_gen_toggle(false);
  -- bad_fuel_pct 100: adulterated, the generator coughs and burns more for a while
  update game_config set value = '100' where key = 'power.bad_fuel_pct';
  r := power_refuel('petrol_bm', 1);
  perform pg_temp.assert((r ->> 'bad_batch')::boolean and (r #>> '{backup,generator,faulty}')::boolean, 'adulterated fuel: the generator is faulty');
  perform pg_temp.assert((r ->> 'message') like '%bad%', 'the message says the fuel is bad');
  perform power_gen_toggle(true);
  r := power_status();
  h_bad := (r #>> '{backup,generator,burn_lph}')::numeric;
  perform pg_temp.assert(abs(h_bad / h_clean - 1.6) < 0.01, 'it burns 1.6 times the fuel (' || h_clean || ' to ' || h_bad || ')');
  perform pg_temp.assert((r #>> '{backup,generator,noisy}')::boolean, 'and is noisy');
  -- it recovers by itself after the admin minutes
  perform pg_temp.at('2026-11-27 23:50:00');
  r := power_status();
  perform pg_temp.assert(not (r #>> '{backup,generator,faulty}')::boolean, 'the cough clears after 45 minutes');
  perform pg_temp.assert(abs((r #>> '{backup,generator,burn_lph}')::numeric - h_clean) < 0.01, 'normal burn again');
  -- clean (station) fuel is never adulterated
  perform bl_give_item(c, 'petrol', 2);
  perform power_gen_toggle(false);
  r := power_refuel('petrol', 1);
  perform pg_temp.assert(not (r ->> 'bad_batch')::boolean and not (r #>> '{backup,generator,faulty}')::boolean, 'station fuel is always clean');
  update game_config set value = '25' where key = 'power.bad_fuel_pct';
  perform pg_temp.assert(not exists (select 1 from items where id = 'petrol_bm' and sellable), 'grey fuel cannot be sold on');
end $$;

-- ---------- 10. expected value near the legit price ----------
do $$
declare r record; n int := 0;
begin
  perform pg_temp.at('2026-11-28 23:00:00');
  perform set_config('bl.test_rand', '', true);
  update game_config set value = '4' where key = 'blackmarket.raid_pct';
  update game_config set value = '6' where key = 'blackmarket.scam_pct';
  update game_config set value = '6' where key = 'blackmarket.robbery_pct';
  update game_config set value = '8' where key = 'blackmarket.hot_night_pct';
  update bm_offers set faulty_pct = case id when 'tk_tiger' then 20 when 'tk_firman' then 20 when 'tk_inverter' then 25 when 'tk_battery' then 25 when 'tk_panels' then 10 else 0 end,
                       stolen_pct = case id when 'tk_tiger' then 8 when 'tk_firman' then 8 when 'tk_inverter' then 8 when 'tk_battery' then 6 when 'tk_panels' then 10 else 0 end;
  for r in select o.id, bl_bm_risk(o, null) as risk from bm_offers o where active loop
    n := n + 1;
    perform pg_temp.assert((r.risk ->> 'ev_ratio')::numeric between 0.9 and 1.1, r.id || ': price over expected value is ' || (r.risk ->> 'ev_ratio') || ', must be 0.9 to 1.1');
    perform pg_temp.assert((r.risk ->> 'unit_price')::numeric < (r.risk ->> 'shop_price')::numeric, r.id || ' is cheaper than the shop before the risks');
  end loop;
  perform pg_temp.assert(n = 7, 'seven offers checked');
  -- in a scarcity grey fuel is dearer than the stations
  perform pg_temp.login(pg_temp.uid('admin'));
  perform admin_power_event_start('scarcity', 3, '');
  perform pg_temp.assert(bl_bm_unit_price((select o from bm_offers o where id = 'grey_petrol')) > bl_fuel_price((select i from items i where i.id = 'petrol'), 'fs_sapele'), 'in a scarcity grey fuel costs more than the (dear) stations');
  update game_config set value = '100' where key = 'fuel.scarcity_dry_pct';
  perform pg_temp.assert((select count(*) from locations where id like 'fs\_%' and bl_fuel_dry(id)) = 7 and (bm_status() is not null), 'when every station is dry the yard still has fuel');
  perform pg_temp.login(pg_temp.uid('cred'));
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements((bm_status()) -> 'offers') o where o ->> 'id' = 'grey_petrol'), 'grey petrol is on the shelf during the scarcity');
  update game_config set value = '35' where key = 'fuel.scarcity_dry_pct';
  perform pg_temp.login(pg_temp.uid('admin'));
  perform admin_power_event_end('scarcity');
end $$;

-- ---------- 11. grants / RLS ----------
do $$
declare v_cred uuid := pg_temp.uid('cred');
begin
  perform pg_temp.assert(not has_function_privilege('anon', 'public.bm_buy(text,integer)', 'execute'), 'anon cannot deal');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.bm_buy(text,integer)', 'execute') and has_function_privilege('authenticated', 'public.bm_status()', 'execute'), 'players can call the yard rpcs');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_bm_risk(public.bm_offers,uuid)', 'execute'), 'bl_bm_risk is private');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_crime_arrest(uuid,text,text)', 'execute'), 'bl_crime_arrest is private');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.fuel_station_info(text)', 'execute') and not has_function_privilege('anon', 'public.fuel_station_info(text)', 'execute'), 'fuel_station_info for players only');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.bm_offers'::regclass), 'bm_offers has RLS');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.bm_offers', 'select'), 'players cannot read the shelf table (only bm_status)');
  perform pg_temp.login(v_cred);
  execute 'set local role authenticated';
  perform pg_temp.assert(pg_temp.hint_of($q$select * from bm_offers$q$) <> 'ok', 'reading bm_offers directly is refused');
  execute 'reset role';
end $$;

delete from auth.users where email like 'fm\_%@fuel.bl';
