-- K1 new clubs + weekend club prices (20261012001300_new_clubs.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/new_clubs_test.sql
-- Groups: 1 both clubs exist, active, on the map (x/y, spacing), zones/cards/bar like 360 Signature ·
-- 2 closed before 10 PM, open after (and after midnight), closed after 5 AM; travel + actions refused while closed ·
-- 3 weekend multiplier: Fri/Sat nights incl. after midnight, not Thu/Sun/Mon nights; config tunable; exempt list ·
-- 4 do_activity / shop_buy charge the weekend price, place_interior / shop_list / club_prices show it + flags ·
-- 5 server-only helpers, config rows.

-- Move the Benin clock to weekday p_wd (0 = Monday ... 4 = Friday, 5 = Saturday, 6 = Sunday) at p_hour:30.
create or replace function pg_temp.nc_at(p_wd int, p_hour int) returns void
language plpgsql as $$
declare c jsonb; cur numeric; tgt numeric; delta numeric;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  c := bl_game_clock();
  cur := (c->>'weekday')::numeric * 86400 + (c->>'hour')::numeric * 3600 + (c->>'minute')::numeric * 60;
  tgt := p_wd * 86400 + p_hour * 3600 + 1800;
  delta := ((tgt - cur) % 604800 + 604800) % 604800;
  perform set_config('bl.test_offset_seconds', delta::text, true);
  c := bl_game_clock();
  if (c->>'weekday')::int <> p_wd or (c->>'hour')::int <> p_hour then
    raise exception 'TEST FAILED: time travel to wd % h % landed on %', p_wd, p_hour, c;
  end if;
end $$;

create or replace function pg_temp.nc_hint(p_sql text, p_hint text) returns text
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

-- What the player has spent on activities + shop so far (rent and other ledger rows don't count).
create or replace function pg_temp.nc_spent(p uuid) returns bigint
language sql as $$
  select coalesce(-sum(delta), 0)::bigint from ledger where user_id = p and reason in ('activity', 'shop')
$$;

do $$
declare
  v uuid := pg_temp.new_user('nc_ada@clubs.bl');
  l locations; n int; r jsonb; m text; c0 bigint; c1 bigint; card jsonb; pid text;
begin
  perform set_config('bl.test_rand', '0.99', true);   -- no robbery / sold-out rolls
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2('Nc_Ada', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = 'true' where key = 'places.hours_enabled';
  update game_config set value = '"real"' where key = 'clock.mode';
  update game_config set value = '1.5' where key = 'club.weekend_price_mult';
  update game_config set value = '"spray_money,ease_yourself"' where key = 'club.weekend_exempt';
  update game_config set value = '12' where key = 'club.night_rollover_hour';
  update game_config set value = '2000000' where key = 'hype.shutdown_cost';

  -- 1. both clubs exist like the others
  foreach pid in array array['club_raptor', 'patricia_nightlife'] loop
    select * into l from locations where locations.id = pid;
    perform pg_temp.assert(l.id is not null, pid || ' exists');
    perform pg_temp.assert(l.scene = 'club' and l.active, pid || ' is an active club');
    perform pg_temp.assert(l.x between 0 and 1000 and l.y between 0 and 1000, pid || ' has map coordinates');
    perform pg_temp.assert(l.open_hour = 22 and l.close_hour = (select close_hour from locations where locations.id = 'club_360'),
      pid || ' opens 10 PM and closes with the other clubs');
    perform pg_temp.assert(l.actions @> '{activities,shop}', pid || ' sheet tabs');
    perform pg_temp.assert(coalesce(l.blurb, '') <> '', pid || ' blurb');
    select count(*) into n from locations o where o.id <> l.id and o.private_home_owner_id is null
       and sqrt((o.x - l.x)^2 + (o.y - l.y)^2) < 34;
    perform pg_temp.assert(n = 0, pid || ' pin is >= 34 map units from every other pin');
    perform pg_temp.assert((select count(*) from place_zones where scene = 'club' and active) >= 6, 'club zones');
    perform pg_temp.assert((select count(*) from items where items.id in ('club_bottle', 'star_beer') and l.id = any (sold_at)) = 2,
      pid || ' bar sells bottles + Star');
    perform pg_temp.assert(exists (select 1 from npc_roster where l.id = any (location_ids) and zone_key = 'dj'), pid || ' has a DJ');
    perform pg_temp.assert(exists (select 1 from place_moods where location_id = l.id), pid || ' mood lines');
    perform pg_temp.assert(exists (select 1 from place_events where location_id = l.id and kind = 'club_night' and active), pid || ' club night');
  end loop;
  perform pg_temp.assert((select district from locations where id = 'club_raptor') = 'ekenwan', 'Raptor on Stadium Rd (Ekenwan side)');
  perform pg_temp.assert((select district from locations where id = 'patricia_nightlife') = 'gra', 'Patricia in GRA');
  -- every zone card the club type has shows at both (same set as 360 Signature)
  update profiles set location_id = 'club_raptor', cash = 80000 where id = v;
  perform pg_temp.nc_at(2, 23);  -- Wednesday 11:30 PM
  r := place_interior('club_raptor');
  perform pg_temp.assert(jsonb_array_length(r->'zones') = jsonb_array_length(place_interior('club_360')->'zones'), 'same zones as 360 Signature');
  perform pg_temp.assert(r->>'hours' is not null and (r->>'open')::boolean, 'Raptor open at 11:30 PM');
  raise notice 'ok 1: clubs exist, active, placed, wired like 360 Signature';

  -- 2. hours: closed before 10 PM, open after (and past midnight), closed after 5 AM
  foreach pid in array array['club_raptor', 'patricia_nightlife'] loop
    select * into l from locations where locations.id = pid;
    perform pg_temp.nc_at(2, 21);  perform pg_temp.assert(not bl_place_open(l), pid || ' closed at 9:30 PM');
    perform pg_temp.nc_at(2, 20);  perform pg_temp.assert(not bl_place_open(l), pid || ' closed at 8:30 PM');
    perform pg_temp.nc_at(2, 14);  perform pg_temp.assert(not bl_place_open(l), pid || ' closed in the afternoon');
    perform pg_temp.nc_at(2, 22);  perform pg_temp.assert(bl_place_open(l), pid || ' open at 10:30 PM');
    perform pg_temp.nc_at(3, 2);   perform pg_temp.assert(bl_place_open(l), pid || ' open at 2:30 AM');
    perform pg_temp.nc_at(3, 4);   perform pg_temp.assert(bl_place_open(l), pid || ' open at 4:30 AM');
    perform pg_temp.nc_at(3, 5);   perform pg_temp.assert(not bl_place_open(l), pid || ' closed at 5:30 AM');
  end loop;
  perform pg_temp.nc_at(2, 21);
  update profiles set location_id = 'national_museum', busy_until = null where id = v;
  m := pg_temp.nc_hint($q$ select travel_quote('patricia_nightlife') $q$, 'closed');
  perform pg_temp.assert(m like 'Patricia Nightlife is closed right now%', 'travel refused while closed: ' || m);
  update profiles set location_id = 'club_raptor', busy_until = null where id = v;
  perform pg_temp.nc_hint($q$ select do_activity('club_night') $q$, 'closed');
  perform pg_temp.nc_hint($q$ select shop_buy('star_beer', 1) $q$, 'closed');
  r := place_interior('club_raptor');
  perform pg_temp.assert(not (r->>'open')::boolean and r->>'opens' = 'Opens ' || bl_hour_label(22), 'interior says Opens 10 PM: ' || coalesce(r->>'opens', 'null'));
  perform pg_temp.nc_at(2, 22);
  perform pg_temp.assert((travel_quote('patricia_nightlife')->>'dest') = 'patricia_nightlife', 'travel ok when open');
  raise notice 'ok 2: closed before 10 PM, open 10 PM - 5 AM';

  -- 3. weekend: Fri / Sat nights incl. after midnight; not Thu / Sun nights
  perform pg_temp.nc_at(4, 22); perform pg_temp.assert(bl_club_weekend(), 'Fri 10:30 PM is weekend');
  perform pg_temp.nc_at(5, 1);  perform pg_temp.assert(bl_club_weekend(), 'Sat 1:30 AM still Friday night');
  perform pg_temp.nc_at(5, 4);  perform pg_temp.assert(bl_club_weekend(), 'Sat 4:30 AM still Friday night');
  perform pg_temp.nc_at(5, 23); perform pg_temp.assert(bl_club_weekend(), 'Sat 11:30 PM is weekend');
  perform pg_temp.nc_at(6, 2);  perform pg_temp.assert(bl_club_weekend(), 'Sun 2:30 AM still Saturday night');
  perform pg_temp.nc_at(6, 22); perform pg_temp.assert(not bl_club_weekend(), 'Sun 10:30 PM is not');
  perform pg_temp.nc_at(0, 1);  perform pg_temp.assert(not bl_club_weekend(), 'Mon 1:30 AM (Sunday night) is not');
  perform pg_temp.nc_at(3, 23); perform pg_temp.assert(not bl_club_weekend(), 'Thu 11:30 PM is not');
  perform pg_temp.nc_at(4, 2);  perform pg_temp.assert(not bl_club_weekend(), 'Fri 2:30 AM (Thursday night) is not');
  perform pg_temp.nc_at(2, 23); perform pg_temp.assert(not bl_club_weekend(), 'Wed 11:30 PM is not');

  select * into l from locations where id = 'club_raptor';
  perform pg_temp.nc_at(2, 23);
  perform pg_temp.assert(bl_club_price(l, 'vip_table', 150000) = 150000, 'weekday VIP table normal price');
  perform pg_temp.nc_at(5, 1);
  perform pg_temp.assert(bl_club_price(l, 'vip_table', 150000) = 225000, 'Friday night (Sat 1:30 AM) VIP table x1.5');
  perform pg_temp.assert(bl_club_price(l, 'star_beer', 1500) = 2250, 'Star x1.5');
  perform pg_temp.assert(bl_club_price(l, 'spray_money', 50000) = 50000, 'spray money exempt');
  perform pg_temp.assert(bl_club_price(l, 'ease_yourself', 50) = 50, 'restroom exempt');
  perform pg_temp.assert(bl_club_price(l, 'club_dance', 0) = 0, 'free stays free');
  -- every club, not only the new ones; never outside clubs
  perform pg_temp.assert(bl_club_price((select lo from locations lo where lo.id = 'club_360'), 'club_bottle', 45000) = 67500, '360 Signature bottle x1.5');
  perform pg_temp.assert(bl_club_price((select lo from locations lo where lo.id = 'mama_ebo'), 'pepper_soup', 1200) = 1200, 'buka not marked up');
  -- admin-tunable
  update game_config set value = '2' where key = 'club.weekend_price_mult';
  perform pg_temp.assert(bl_club_price(l, 'vip_table', 150000) = 300000, 'multiplier follows config (x2)');
  update game_config set value = '1' where key = 'club.weekend_price_mult';
  perform pg_temp.assert(bl_club_price(l, 'vip_table', 150000) = 150000 and not bl_club_weekend_on(l), 'x1 switches it off');
  update game_config set value = '1.5' where key = 'club.weekend_price_mult';
  update game_config set value = '"spray_money,ease_yourself,vip_table"' where key = 'club.weekend_exempt';
  perform pg_temp.assert(bl_club_price(l, 'vip_table', 150000) = 150000, 'exempt list follows config');
  update game_config set value = '"spray_money,ease_yourself"' where key = 'club.weekend_exempt';
  raise notice 'ok 3: weekend = Fri/Sat nights incl. after midnight, multiplier + exempt tunable';

  -- 4. what you pay and what you see
  update profiles set location_id = 'club_raptor', cash = 80000, busy_until = null where id = v;
  perform pg_temp.nc_at(2, 23);   -- Wednesday night: normal price
  c0 := pg_temp.nc_spent(v);
  r := do_activity('club_night');
  c1 := pg_temp.nc_spent(v);
  perform pg_temp.assert(c1 - c0 = 3000, format('weekday entry ₦3,000, paid %s', c1 - c0));
  r := place_interior('club_raptor');
  perform pg_temp.assert(not (r->>'weekend_price')::boolean, 'no weekend badge on a weekday');

  perform pg_temp.nc_at(5, 0);    -- Saturday 12:30 AM = Friday night
  update profiles set busy_until = null, cash = 80000 where id = v;
  r := place_interior('club_raptor');
  perform pg_temp.assert((r->>'weekend_price')::boolean, 'weekend badge on Friday night');
  select a into card from jsonb_array_elements(r->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'club_night' limit 1;
  perform pg_temp.assert((card->>'cost')::bigint = 4500 and (card->>'weekend')::boolean, 'entry card shows ₦4,500 + weekend: ' || card::text);
  select a into card from jsonb_array_elements(r->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'star_beer' limit 1;
  perform pg_temp.assert((card->>'cost')::bigint = 2250 and (card->>'weekend')::boolean, 'Star card shows ₦2,250: ' || card::text);
  select a into card from jsonb_array_elements(r->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'spray_money' limit 1;
  perform pg_temp.assert((card->>'cost')::bigint = 50000 and not (card->>'weekend')::boolean, 'spray money card unchanged');
  c0 := pg_temp.nc_spent(v);
  r := do_activity('club_night');
  c1 := pg_temp.nc_spent(v);
  perform pg_temp.assert(c1 - c0 = 4500, format('Friday-night entry ₦4,500, paid %s', c1 - c0));
  perform pg_temp.assert(r->>'message' like '%₦4,500%', 'message shows the weekend price: ' || (r->>'message'));
  update profiles set busy_until = null where id = v;
  c0 := pg_temp.nc_spent(v);
  r := shop_buy('star_beer', 2);
  c1 := pg_temp.nc_spent(v);
  perform pg_temp.assert(c1 - c0 = 4500 and (r->>'spent')::bigint = 4500, format('2 x Star on Friday night = ₦4,500, paid %s', c1 - c0));
  r := shop_list('club_raptor');
  perform pg_temp.assert((r->>'weekend_price')::boolean, 'shop_list weekend flag');
  perform pg_temp.assert((select (i->>'price')::bigint from jsonb_array_elements(r->'items') i where i->>'id' = 'club_bottle') = 67500
     and (select (i->>'weekend')::boolean from jsonb_array_elements(r->'items') i where i->>'id' = 'club_bottle'), 'shop_list bottle ₦67,500');
  r := club_prices('patricia_nightlife');
  perform pg_temp.assert((r->>'weekend')::boolean and (r->>'mult')::numeric = 1.5, 'club_prices weekend x1.5');
  perform pg_temp.assert((r->'activities'->'vip_table'->>'cost')::bigint = 225000 and (r->'activities'->'vip_table'->>'base')::bigint = 150000, 'club_prices VIP');
  perform pg_temp.assert((r->'activities'->'shut_down_club'->>'cost')::bigint = 3000000, 'club_prices shut down x1.5');
  r := club_prices('mama_ebo');
  perform pg_temp.assert(not (r->>'weekend')::boolean, 'club_prices: not a club, no weekend');
  -- a weekday at another club (Sunday night): back to normal
  perform pg_temp.nc_at(6, 23);
  update profiles set location_id = 'club_360', busy_until = null where id = v;
  c0 := pg_temp.nc_spent(v);
  perform do_activity('club_night');
  perform pg_temp.assert(pg_temp.nc_spent(v) - c0 = 3000, 'Sunday night entry back to ₦3,000');
  raise notice 'ok 4: pay + see the weekend price (do_activity, shop_buy, place_interior, shop_list, club_prices)';

  -- 5. server-only helpers, config rows
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_club_price(public.locations, text, bigint)', 'execute'), 'bl_club_price server-only');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_club_weekend(timestamptz)', 'execute'), 'bl_club_weekend server-only');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.club_prices(text)', 'execute'), 'club_prices not for anon');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.club_prices(text)', 'execute'), 'club_prices for players');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.do_activity(text)', 'execute'), 'do_activity grant kept');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.shop_buy(text,integer)', 'execute'), 'shop_buy grant kept');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.place_interior(text)', 'execute'), 'place_interior grant kept');
  perform pg_temp.assert((select category = 'club' and kind = 'number' and min = 1 and max = 5 from game_config where key = 'club.weekend_price_mult'), 'mult config row');
  perform pg_temp.assert(exists (select 1 from game_config where key = 'club.weekend_exempt'), 'exempt config row');
  raise notice 'ALL NEW CLUBS TESTS PASSED';
end $$;
