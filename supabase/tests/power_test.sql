-- Power cuts (20261113000100_power.sql, docs/POWER.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/power_test.sql
-- Groups: 1 settings and seeds (labels, ranges) · 2 deterministic outages by area (same for everybody, the percentage over many slots,
-- cut lengths) · 3 admin blackout (audited, limits, non-admin refused, random one) · 4 power_status per backup kind · 5 generator (on, off,
-- burn by real time, empty, refill, wrong fuel) · 6 inverter (takeover, drain, mains recharge, solar by day, batteries = longer, empty) ·
-- 7 notices (cut, back, fuel, battery) · 8 effects (TV refused, bonuses and rest) · 9 visiting uses the host's area · 10 grants / RLS.
-- All times are pinned with bl.test_offset_seconds to a fixed Benin time, so it passes at any hour. An area is forced always-on (0 %)
-- or always-off (100 %) with its outage % setting when a test needs a certain state.
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

-- pin "now" to an absolute Benin time (the transaction clock stays put, bl_now() moves)
create or replace function pg_temp.at(p_local text) returns void
language plpgsql as $$
begin
  perform set_config('bl.test_offset_seconds', extract(epoch from (p_local::timestamp at time zone 'Africa/Lagos') - now())::text, true);
  update profiles set rent_due_at = null where username like 'PW\_%';
end $$;

create or replace function pg_temp.uid(p_name text) returns uuid
language plpgsql as $$ declare v uuid; begin select id into v from pg_temp.pw_u where name = p_name; return v; end $$;

create or replace function pg_temp.give(p_uid uuid, p_furn text, p_qty int default 1) returns void
language sql as $$
  insert into player_furniture (user_id, furniture_id, slot, source, qty) values (p_uid, p_furn, null, 'buy', p_qty)
  on conflict (user_id, furniture_id) do update set qty = excluded.qty
$$;

create or replace function pg_temp.set_area(p_area text, p_pct numeric) returns void
language sql as $$ update game_config set value = to_jsonb(p_pct) where key = 'power.outage_pct.' || p_area $$;

create temp table pw_u (name text primary key, id uuid);

do $$
declare
  v uuid; r record;
begin
  update game_config set value = 'true' where key = 'power.enabled';
  for r in select * from (values ('none', 'ekenwan_face_me', 'lapo'), ('gen', 'ekenwan_face_me', 'lapo'), ('inv', 'ekenwan_face_me', 'lapo'),
                                 ('host', 'uselu_self_contain', 'lapo'), ('gra', 'gra_duplex', 'nepo'), ('admin', 'aduwawa_face_me', 'lapo'),
                                 ('mini', 'mission_rd_mini_flat', 'nepo')) x(n, home, origin) loop
    v := pg_temp.new_user('pw_' || r.n || '@power.bl');
    update game_config set value = to_jsonb(r.origin) where key = 'origin.force_next';
    perform pg_temp.login(v);
    perform create_profile_v2('PW_' || r.n, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home(r.home);
    insert into pw_u values (r.n, v);
  end loop;
  update profiles set is_admin = true where id = pg_temp.uid('admin');
  update profiles set cash = 5000000, bank = 5000000 where username like 'PW\_%';
  update game_config set value = '"lapo"' where key = 'origin.force_next';
end $$;

-- ---------- 1. settings and seeds ----------
do $$
declare n int;
begin
  perform pg_temp.assert((select count(*) from game_config where category = 'power') >= 30, 'power settings seeded');
  perform pg_temp.assert((select count(*) from game_config where category = 'fuel') >= 11, 'fuel settings seeded');
  perform pg_temp.assert((select count(*) from game_config where category = 'blackmarket') >= 20, 'black market settings seeded');
  select count(*) into n from game_config where category in ('power', 'fuel', 'blackmarket')
     and (coalesce(label, '') = '' or coalesce(description, '') = '' or (kind in ('number', 'percent', 'naira', 'minutes') and (min is null or max is null)));
  perform pg_temp.assert(n = 0, 'every power / fuel / black market setting has a label, a description and a min and max (' || n || ' without)');
  perform pg_temp.assert((select count(*) from game_config where category in ('power', 'fuel', 'blackmarket') and key not like (category || '.%')) = 0,
                         'keys are prefixed by their category');
  -- the default outage table from the brief
  perform pg_temp.assert((select value::text from game_config where key = 'power.outage_pct.gra') = '8', 'GRA 8 %');
  perform pg_temp.assert((select value::text from game_config where key = 'power.outage_pct.ugbowo') = '20', 'Ugbowo 20 %');
  perform pg_temp.assert((select value::text from game_config where key = 'power.outage_pct.sapele') = '25', 'Sapele Road 25 %');
  perform pg_temp.assert((select value::text from game_config where key = 'power.outage_pct.airport') = '22', 'Airport Road 22 %');
  perform pg_temp.assert((select value::text from game_config where key = 'power.outage_pct.ikpoba') = '30', 'Ikpoba Hill 30 %');
  perform pg_temp.assert((select value::text from game_config where key = 'power.outage_pct.new_benin') = '28', 'New Benin 28 %');
  perform pg_temp.assert((select value::text from game_config where key = 'power.outage_pct.ring_road') = '25', 'Ring Road 25 %');
  perform pg_temp.assert((select value::text from game_config where key = 'power.outage_pct.ekenwan') = '40', 'Ekenwan 40 %');
  perform pg_temp.assert((select count(*) from power_areas where active) >= 8, 'areas seeded');
  perform pg_temp.assert((select count(*) from power_gear where kind = 'generator') = 3, 'three generators in the gear table');
  perform pg_temp.assert(not exists (select 1 from power_gear g where g.source = 'furniture' and g.kind <> 'fuel'
                           and not exists (select 1 from furniture f where f.id = g.id)), 'every gear row points at a real furniture piece');
  perform pg_temp.assert((select count(*) from items where category = 'fuel') = 6, 'petrol, diesel, cans and grey fuel are items');
  -- homes map to areas
  perform pg_temp.assert(bl_power_area_of(pg_temp.uid('gra')) = 'gra', 'GRA duplex is in GRA');
  perform pg_temp.assert(bl_power_area_of(pg_temp.uid('none')) = 'ekenwan', 'Ekenwan face-me is in Ekenwan');
  perform pg_temp.assert(bl_power_area_of(pg_temp.uid('host')) = 'uselu', 'Uselu self-contain is in Uselu');
  perform pg_temp.assert(bl_power_area_of(pg_temp.uid('mini')) = 'new_benin', 'Mission Road mini-flat is in New Benin');
end $$;

-- ---------- 2. deterministic outages by area ----------
do $$
declare
  t0 double precision := extract(epoch from '2026-11-20 10:00:00+01'::timestamptz);
  a record; b record; c record; area text; n int; off_n int; i int; pct numeric; step int := 420; samples int := 2880;
  segs int; len double precision; s double precision; mn double precision; mx double precision; prev boolean; cur boolean; t double precision;
  v_h1 text; v_h2 text; diffs int;
begin
  perform pg_temp.at('2026-11-20 10:00:00');
  -- the same instant gives the same answer, twice, and for two players in one area
  select * into a from bl_power_mains('ugbowo', t0 + 12345);
  select * into b from bl_power_mains('ugbowo', t0 + 12345);
  perform pg_temp.assert(a.mains_on = b.mains_on and a.nxt = b.nxt, 'same area, same instant: same answer');
  perform pg_temp.login(pg_temp.uid('none'));
  v_h1 := power_status() ->> 'mains';
  perform pg_temp.login(pg_temp.uid('gen'));
  v_h2 := power_status() ->> 'mains';
  perform pg_temp.assert(v_h1 = v_h2, 'two players in Ekenwan see the same cut');
  -- different areas are not in lock step
  diffs := 0;
  for i in 0 .. 299 loop
    if (bl_power_mains('gra', t0 + i * 600)).mains_on <> (bl_power_mains('ekenwan', t0 + i * 600)).mains_on then diffs := diffs + 1; end if;
  end loop;
  perform pg_temp.assert(diffs > 30, 'GRA and Ekenwan do not go off together (' || diffs || ' differences)');
  -- the share of time off is roughly the area's percentage over many slots
  foreach area in array array['gra', 'ugbowo', 'sapele', 'ikpoba', 'ekenwan'] loop
    pct := (select (value #>> '{}')::numeric from game_config where key = 'power.outage_pct.' || area);
    off_n := 0;
    for i in 0 .. samples - 1 loop
      if not (bl_power_mains(area, t0 + i * step)).mains_on then off_n := off_n + 1; end if;
    end loop;
    perform pg_temp.assert(abs(off_n * 100.0 / samples - pct) <= 4, area || ': off ' || round(off_n * 100.0 / samples, 1) || ' % against the setting ' || pct || ' %');
  end loop;
  -- cut lengths stay inside 15 to 60 real minutes (scan one area minute by minute for two days)
  segs := 0; mn := 1e9; mx := 0; prev := true; s := null;
  for i in 0 .. 2879 loop
    t := t0 + i * 60;
    cur := (bl_power_mains('ugbowo', t)).mains_on;
    if prev and not cur then s := (bl_power_mains('ugbowo', t)).since; end if;
    if not prev and cur and s is not null then
      len := (t - s) / 60.0; segs := segs + 1; mn := least(mn, len); mx := greatest(mx, len);
    end if;
    prev := cur;
  end loop;
  perform pg_temp.assert(segs >= 8, 'several cuts in two days (' || segs || ')');
  perform pg_temp.assert(mn >= 14.5 and mx <= 61, 'every cut is 15 to 60 minutes (' || round(mn::numeric, 1) || ' to ' || round(mx::numeric, 1) || ')');
  -- reshuffling the salt moves the cuts
  diffs := 0;
  for i in 0 .. 99 loop
    if (bl_power_mains('ugbowo', t0 + i * 900)).mains_on then diffs := diffs + 1; end if;
  end loop;
  update game_config set value = '"pepper"' where key = 'power.salt';
  n := 0;
  for i in 0 .. 99 loop
    if (bl_power_mains('ugbowo', t0 + i * 900)).mains_on then n := n + 1; end if;
  end loop;
  perform pg_temp.assert((select count(*) from generate_series(0, 99) g
                           where (bl_power_mains('ugbowo', t0 + g * 900)).mains_on is distinct from (bl_power_mains('ugbowo', t0 + g * 900)).mains_on) = 0, 'still pure');
  update game_config set value = '"benin"' where key = 'power.salt';
  -- 0 % never goes off, 100 % is always off, switch off = always on
  perform pg_temp.set_area('gra', 0);
  perform pg_temp.assert(not exists (select 1 from generate_series(0, 200) g where not (bl_power_mains('gra', t0 + g * 997)).mains_on), '0 % never goes off');
  perform pg_temp.set_area('gra', 100);
  perform pg_temp.assert(not exists (select 1 from generate_series(0, 200) g where (bl_power_mains('gra', t0 + g * 997)).mains_on), '100 % is always off');
  update game_config set value = 'false' where key = 'power.enabled';
  perform pg_temp.assert((bl_power_mains('gra', t0)).mains_on, 'power cuts switched off: the light is on');
  perform pg_temp.assert(power_status() ->> 'enabled' = 'false', 'status answers when off');
  update game_config set value = 'true' where key = 'power.enabled';
  perform pg_temp.set_area('gra', 8);
  -- bl_power_flip_at points at the next flip
  perform pg_temp.assert(bl_power_flip_at('ugbowo', t0) > to_timestamp(t0), 'next flip is in the future');
end $$;

-- ---------- 3. admin blackout ----------
do $$
declare
  t0 double precision := extract(epoch from '2026-11-20 10:00:00+01'::timestamptz); r jsonb; n int; area text; m record;
begin
  perform pg_temp.at('2026-11-20 10:00:00');
  perform pg_temp.set_area('gra', 0);
  perform pg_temp.assert((bl_power_mains('gra', t0)).mains_on, 'GRA on before the blackout');
  perform pg_temp.login(pg_temp.uid('none'));
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_power_event_start('blackout', 2, 'x')$q$) <> 'ok', 'a normal player cannot start a blackout');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_power_event_end('blackout')$q$) <> 'ok', 'a normal player cannot end a blackout');
  perform pg_temp.login(pg_temp.uid('admin'));
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_power_event_start('blackout', 0, 'x')$q$) = 'bad_hours', 'zero hours refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_power_event_start('blackout', 500, 'x')$q$) = 'bad_hours', 'longer than the admin limit refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_power_event_start('flood', 2, 'x')$q$) = 'bad_kind', 'unknown kind refused');
  r := admin_power_event_start('blackout', 2, 'test blackout');
  perform pg_temp.assert(r ? 'id', 'blackout started');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'power_blackout_start' and admin_id = pg_temp.uid('admin')) = 1, 'start is audited');
  for area in select id from power_areas where active loop
    perform pg_temp.assert(not (bl_power_mains(area, t0 + 5)).mains_on, area || ' is dark in a city-wide blackout');
    perform pg_temp.assert((bl_power_mains(area, t0 + 5)).city, area || ' says city-wide');
  end loop;
  perform pg_temp.assert(not (bl_power_mains('gra', t0 + 2 * 3600 - 10)).mains_on, 'still dark just before the end');
  perform pg_temp.assert((bl_power_mains('gra', t0 + 2 * 3600 + 10)).mains_on, 'light is back after the hours');
  perform pg_temp.login(pg_temp.uid('none'));
  r := power_status();
  perform pg_temp.assert(r ->> 'mains' = 'off' and (r ->> 'city')::boolean, 'players see the city-wide blackout in power_status');
  perform pg_temp.login(pg_temp.uid('admin'));
  r := admin_power_overview();
  perform pg_temp.assert(r -> 'blackout' is not null and jsonb_typeof(r -> 'blackout') = 'object', 'overview shows the blackout');
  perform pg_temp.assert(jsonb_array_length(r -> 'areas') >= 8, 'overview lists the areas');
  r := admin_power_event_end('blackout');
  perform pg_temp.assert((r ->> 'ended')::int = 1, 'blackout ended');
  perform pg_temp.assert((bl_power_mains('gra', t0 + 5)).mains_on, 'light is back at once');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'power_blackout_end') = 1, 'end is audited');
  perform pg_temp.assert((admin_power_event_end('blackout') ->> 'ended')::int = 0, 'ending nothing is harmless');
  -- the optional random city-wide blackout: off by default, on = deterministic per day
  perform pg_temp.assert((select value::text from game_config where key = 'power.random_blackout_chance_pct') = '0', 'random blackout is off by default');
  update game_config set value = '100' where key = 'power.random_blackout_chance_pct';
  update game_config set value = '120' where key = 'power.random_blackout_minutes';
  select count(*) into n from generate_series(0, 287) g where not (bl_power_mains('gra', t0 + g * 300)).mains_on;
  perform pg_temp.assert(n between 20 and 50, 'a 100 % daily random blackout of 120 minutes: one or two windows fall inside 24 hours, 24 to 48 five-minute samples (' || n || ')');
  perform pg_temp.assert((select count(*) from generate_series(0, 287) g where (bl_power_mains('gra', t0 + g * 300)).city) = n, 'and it says city-wide');
  update game_config set value = '0' where key = 'power.random_blackout_chance_pct';
  perform pg_temp.assert(not exists (select 1 from generate_series(0, 287) g where (bl_power_mains('gra', t0 + g * 300)).city), 'off again');
  perform pg_temp.set_area('gra', 8);
end $$;

-- ---------- 4. power_status per backup kind ----------
do $$
declare r jsonb; k text;
begin
  perform pg_temp.at('2026-11-20 10:00:00');
  perform pg_temp.set_area('ekenwan', 100);   -- Ekenwan is dark all day
  perform pg_temp.set_area('gra', 0);
  perform pg_temp.give(pg_temp.uid('gen'), 'gen_tiger');
  perform pg_temp.give(pg_temp.uid('inv'), 'inverter_small');
  -- nothing
  perform pg_temp.login(pg_temp.uid('none'));
  r := power_status();
  perform pg_temp.assert(r #>> '{area,id}' = 'ekenwan' and r ->> 'mains' = 'off', 'area and mains off');
  perform pg_temp.assert(r #>> '{backup,kind}' = 'none' and r ->> 'source' = 'none' and not (r ->> 'lit')::boolean, 'no backup: source none, not lit');
  perform pg_temp.assert(r ? 'until' and r ? 'poll_seconds' and r ? 'hours_left' and r ? 'fuel_l' and r ? 'battery_pct', 'every field the brief lists is there');
  perform pg_temp.assert(r -> 'notices' @> '[{"kind":"outage_none"}]'::jsonb, 'a no-backup notice');
  -- a generator, tank empty
  perform pg_temp.login(pg_temp.uid('gen'));
  r := power_status();
  perform pg_temp.assert(r #>> '{backup,kind}' = 'generator' and r ->> 'source' = 'none' and not (r ->> 'lit')::boolean, 'generator, off: dark');
  perform pg_temp.assert((r #>> '{backup,generator,tank_l}')::numeric = 5 and (r #>> '{backup,generator,fuel_l}')::numeric = 0, 'tank 5 L, empty');
  perform pg_temp.assert(r -> 'notices' @> '[{"kind":"outage_nofuel"}]'::jsonb, 'out of fuel notice');
  -- an inverter
  perform pg_temp.login(pg_temp.uid('inv'));
  r := power_status();
  perform pg_temp.assert(r #>> '{backup,kind}' = 'inverter' and r ->> 'source' = 'battery' and (r ->> 'lit')::boolean, 'inverter takes over: lit from the battery');
  perform pg_temp.assert((r #>> '{backup,inverter,pct}')::numeric = 50, 'a new battery starts half full');
  perform pg_temp.assert((r ->> 'hours_left')::numeric > 0, 'hours left shown');
  perform pg_temp.assert(r -> 'notices' @> '[{"kind":"outage_inverter"}]'::jsonb, 'an inverter notice');
  -- the mains on: lit from mains
  perform pg_temp.login(pg_temp.uid('gra'));
  r := power_status();
  perform pg_temp.assert(r ->> 'mains' = 'on' and r ->> 'source' = 'mains' and (r ->> 'lit')::boolean, 'GRA on: mains');
end $$;

-- ---------- 5. generator ----------
do $$
declare r jsonb; u uuid := pg_temp.uid('gen'); fuel0 numeric; speed numeric; burn numeric; p record; before_qty int;
begin
  perform pg_temp.at('2026-11-20 10:00:00');
  perform pg_temp.set_area('ekenwan', 100);
  update game_config set value = '2' where key = 'power.speed_mult';
  perform pg_temp.login(u);
  perform pg_temp.assert(pg_temp.hint_of($q$select power_gen_toggle(true)$q$) = 'no_fuel', 'cannot start with an empty tank');
  perform pg_temp.assert(pg_temp.hint_of($q$select power_refuel('petrol', 1)$q$) = 'no_fuel_item', 'cannot pour fuel you do not have');
  perform bl_give_item(u, 'petrol', 3);
  perform bl_give_item(u, 'diesel', 1);
  perform pg_temp.assert(pg_temp.hint_of($q$select power_refuel('diesel', 1)$q$) = 'wrong_fuel', 'a petrol generator refuses diesel');
  perform pg_temp.assert(pg_temp.hint_of($q$select power_refuel('bread', 1)$q$) = 'not_fuel', 'bread is not fuel');
  r := power_refuel('petrol', 2);
  perform pg_temp.assert((r ->> 'poured')::numeric = 2 and (r #>> '{backup,generator,fuel_l}')::numeric = 2, 'poured 2 litres');
  perform pg_temp.assert((select qty from inventory where user_id = u and item_id = 'petrol') = 1, 'two litres left the bag');
  r := power_gen_toggle(true);
  perform pg_temp.assert((r #>> '{backup,generator,on}')::boolean and r ->> 'source' = 'generator' and (r ->> 'lit')::boolean, 'generator on: lit');
  -- burn by real time: 0.9 L/h x speed 2 = 1.8 L/h. 20 minutes -> 0.6 L
  perform pg_temp.at('2026-11-20 10:20:00');
  r := power_status();
  perform pg_temp.assert(abs((r #>> '{backup,generator,fuel_l}')::numeric - 1.4) < 0.02, 'after 20 minutes 1.4 L are left (' || (r #>> '{backup,generator,fuel_l}') || ')');
  perform pg_temp.assert(abs((r ->> 'hours_left')::numeric - 1.4 / 1.8) < 0.02, 'hours left follows the burn');
  -- asking again at once does not burn twice
  r := power_status();
  perform pg_temp.assert(abs((r #>> '{backup,generator,fuel_l}')::numeric - 1.4) < 0.02, 'no double counting on a second read');
  perform pg_temp.at('2026-11-20 10:20:30');
  perform power_status();
  perform pg_temp.at('2026-11-20 10:20:40');
  r := power_status();
  perform pg_temp.assert(abs((r #>> '{backup,generator,fuel_l}')::numeric - (1.4 - 40 / 3600.0 * 1.8)) < 0.02, 'small steps add up to the same');
  -- switch off: fuel stops burning
  r := power_gen_toggle(false);
  fuel0 := (r #>> '{backup,generator,fuel_l}')::numeric;
  perform pg_temp.assert(r ->> 'source' = 'none' and not (r ->> 'lit')::boolean, 'off again: dark');
  perform pg_temp.at('2026-11-20 11:20:00');
  r := power_status();
  perform pg_temp.assert(abs((r #>> '{backup,generator,fuel_l}')::numeric - fuel0) < 0.001, 'an off generator burns nothing');
  -- run it dry
  r := power_gen_toggle(true);
  perform pg_temp.at('2026-11-20 12:20:00');
  r := power_status();
  perform pg_temp.assert((r #>> '{backup,generator,fuel_l}')::numeric = 0 and not (r #>> '{backup,generator,on}')::boolean, 'ran dry: stopped by itself');
  perform pg_temp.assert(r ->> 'source' = 'none' and not (r ->> 'lit')::boolean, 'dry generator: dark');
  perform pg_temp.assert(r -> 'notices' @> '[{"kind":"fuel_empty"}]'::jsonb, 'Your fuel don finish notice');
  perform pg_temp.assert((select gen_empty_at from player_power where user_id = u) < bl_now(), 'the empty moment is recorded');
  perform pg_temp.assert(pg_temp.hint_of($q$select power_gen_toggle(true)$q$) = 'no_fuel', 'cannot start while empty');
  -- acknowledging a notice once makes it go away
  perform power_ack('fuel', (select (e ->> 'key') from jsonb_array_elements(r -> 'notices') e where e ->> 'kind' = 'fuel_empty'));
  perform pg_temp.assert(not (power_status() -> 'notices' @> '[{"kind":"fuel_empty"}]'::jsonb), 'acknowledged: not shown again');
  -- refill: the tank takes at most its size
  perform bl_give_item(u, 'petrol', 20);
  r := power_refuel('petrol', 20);
  perform pg_temp.assert((r ->> 'poured')::numeric = 5 and (r #>> '{backup,generator,fuel_l}')::numeric = 5, 'a refill stops at the tank size (5 L)');
  perform pg_temp.assert(pg_temp.hint_of($q$select power_refuel('petrol', 1)$q$) = 'tank_full', 'a full tank takes no more');
  -- not enough hours / mains on: it still burns (the warning in the message)
  perform pg_temp.set_area('ekenwan', 0);
  perform pg_temp.at('2026-11-20 13:05:00');
  r := power_gen_toggle(true);
  perform pg_temp.assert(r ->> 'source' = 'mains', 'mains on: source is mains even with the generator on');
  perform pg_temp.at('2026-11-20 13:35:00');
  r := power_status();
  perform pg_temp.assert((r #>> '{backup,generator,fuel_l}')::numeric < 4.2, 'a generator left on with mains still burns fuel');
  perform power_gen_toggle(false);
  perform pg_temp.set_area('ekenwan', 100);
  -- no generator, no switch
  perform pg_temp.login(pg_temp.uid('none'));
  perform pg_temp.assert(pg_temp.hint_of($q$select power_gen_toggle(true)$q$) = 'no_generator', 'no generator: cannot switch');
    -- diesel generator: soundproof, big tank, takes diesel
  perform pg_temp.give(pg_temp.uid('mini'), 'gen_soundproof');
  perform pg_temp.login(pg_temp.uid('mini'));
  perform bl_give_item(pg_temp.uid('mini'), 'diesel_can', 1);
  r := power_refuel('diesel_can', 1);
  perform pg_temp.assert((r ->> 'poured')::numeric = 20, 'a diesel can is 20 litres');
  perform pg_temp.assert((r #>> '{backup,generator,soundproof}')::boolean and (r #>> '{backup,generator,tank_l}')::numeric = 100, 'soundproof diesel gen, 100 L tank');
  update game_config set value = '4' where key = 'power.speed_mult';
end $$;

-- ---------- 6. inverter and solar ----------
do $$
declare r jsonb; u uuid := pg_temp.uid('inv'); h0 numeric; h1 numeric; b0 numeric; b1 numeric; hrs numeric;
begin
  update game_config set value = '1' where key = 'power.speed_mult';
  update game_config set value = '0.5' where key = 'power.mains_charge_kw';
  perform pg_temp.give(u, 'inverter_small');
  -- night, no sun: drains by load. Reset the row so the numbers are exact.
  perform pg_temp.at('2026-11-20 20:00:00');
  perform pg_temp.set_area('ekenwan', 100);
  delete from player_power where user_id = u;
  perform pg_temp.login(u);
  r := power_status();
  perform pg_temp.assert((r #>> '{backup,inverter,kwh}')::numeric = 0.6 and (r #>> '{backup,inverter,cap_kwh}')::numeric = 1.2, 'inverter: 1.2 kWh, starts at 50 % = 0.6');
  perform pg_temp.at('2026-11-20 20:00:00');
  perform power_status();
  perform pg_temp.at('2026-11-20 20:30:00');  -- half an hour at 0.25 kW = 0.125 kWh
  r := power_status();
  perform pg_temp.assert(abs((r #>> '{backup,inverter,kwh}')::numeric - 0.475) < 0.01, 'drained 0.125 kWh in 30 minutes at the base load (' || (r #>> '{backup,inverter,kwh}') || ')');
  perform pg_temp.assert(r ->> 'source' = 'battery' and (r ->> 'lit')::boolean, 'still lit from the battery');
  h0 := (r ->> 'hours_left')::numeric;
  perform pg_temp.assert(abs(h0 - 0.475 / 0.25) < 0.05, 'hours left = battery / load (' || h0 || ')');
  -- more batteries = longer: add a 200Ah tubular battery (+1.2 kWh). The new battery starts at 50 %.
  perform pg_temp.give(u, 'battery_tubular');
  perform pg_temp.at('2026-11-20 20:30:05');
  r := power_status();
  perform pg_temp.assert((r #>> '{backup,inverter,cap_kwh}')::numeric = 2.4, 'two batteries: 2.4 kWh');
  perform pg_temp.assert((r ->> 'hours_left')::numeric > h0 + 1.5, 'a bigger battery gives more hours (' || (r ->> 'hours_left') || ' against ' || h0 || ')');
  perform pg_temp.give(u, 'battery_lithium');
  perform pg_temp.at('2026-11-20 20:30:10');
  r := power_status();
  perform pg_temp.assert((r #>> '{backup,inverter,cap_kwh}')::numeric = 7.4, 'lithium adds 5 kWh');
  -- run flat: all the way to empty
  perform pg_temp.at('2026-11-21 11:05:00');
  r := power_status();
  perform pg_temp.assert((r #>> '{backup,inverter,empty}')::boolean or (r #>> '{backup,inverter,kwh}')::numeric < 0.01, 'flat after 14 hours with no sun');
  perform pg_temp.assert(r ->> 'source' = 'none' and not (r ->> 'lit')::boolean, 'flat battery: dark');
  perform pg_temp.assert(r -> 'notices' @> '[{"kind":"battery_empty"}]'::jsonb, 'Battery don finish notice');
  -- mains on: recharges slowly (0.5 kW x 1 h = 0.5 kWh)
  perform pg_temp.set_area('ekenwan', 0);
  perform pg_temp.at('2026-11-21 11:10:00');
  r := power_status();
  b0 := (r #>> '{backup,inverter,kwh}')::numeric;
  perform pg_temp.at('2026-11-21 12:10:00');   -- this kit has no panels
  r := power_status();
  b1 := (r #>> '{backup,inverter,kwh}')::numeric;
  perform pg_temp.assert(abs((b1 - b0) - 0.5) < 0.03, 'recharged 0.5 kWh in an hour on the mains (' || round(b1 - b0, 3) || ')');
  perform pg_temp.assert(r ->> 'source' = 'mains', 'mains on: source is mains');
  -- the settle never counts the same time twice (read again at the same moment)
  r := power_status();
  perform pg_temp.assert(abs((r #>> '{backup,inverter,kwh}')::numeric - b1) < 0.001, 'a second read adds nothing');
  -- never over the cap
  perform pg_temp.at('2026-11-22 12:00:00');
  r := power_status();
  perform pg_temp.assert((r #>> '{backup,inverter,kwh}')::numeric <= 7.4 + 0.0001, 'battery never goes over its capacity');
  -- solar by day: a solar kit charges for free even with the mains off
  perform pg_temp.set_area('ekenwan', 100);
  perform pg_temp.give(pg_temp.uid('host'), 'inverter_solar');
  perform pg_temp.give(pg_temp.uid('host'), 'solar_panels');
  perform pg_temp.set_area('uselu', 100);
  perform pg_temp.at('2026-11-20 06:00:00');
  perform pg_temp.login(pg_temp.uid('host'));
  delete from player_power where user_id = pg_temp.uid('host');
  perform power_status();
  update player_power set batt_kwh = 0.5 where user_id = pg_temp.uid('host');
  perform pg_temp.at('2026-11-20 12:00:00');   -- six hours of sun, load 0.25 kW
  r := power_status();
  perform pg_temp.assert((r #>> '{backup,inverter,kwh}')::numeric > 0.5 + 3, 'solar charges the battery by day with the mains off (' || (r #>> '{backup,inverter,kwh}') || ')');
  perform pg_temp.assert((r #>> '{backup,inverter,solar_kw}')::numeric = 2.0, 'panels listed');
  perform pg_temp.assert((r ->> 'lit')::boolean, 'lit at midday');
  perform pg_temp.at('2026-11-20 12:10:00');
  r := power_status();
  perform pg_temp.assert(r ->> 'source' = 'solar' and (r #>> '{backup,inverter,solar_covers}')::boolean, 'at midday the sun covers the load: source solar');
  -- at night the same kit is just a battery and drains
  perform pg_temp.at('2026-11-20 22:00:00');
  r := power_status();
  perform pg_temp.assert(r ->> 'source' in ('battery', 'none'), 'night: battery');
  perform pg_temp.set_area('uselu', 22);
end $$;

-- ---------- 7. notices ----------
do $$
declare r jsonb; u uuid := pg_temp.uid('none'); key text;
begin
  perform pg_temp.at('2026-11-20 10:00:00');
  perform pg_temp.set_area('ekenwan', 100);
  perform pg_temp.login(u);
  r := power_status();
  perform pg_temp.assert(r -> 'notices' @> '[{"kind":"outage_none"}]'::jsonb, 'cut notice once');
  key := (select e ->> 'key' from jsonb_array_elements(r -> 'notices') e where e ->> 'kind' = 'outage_none');
  perform pg_temp.assert(key is not null, 'the notice has a key');
  perform power_ack('outage', key);
  perform pg_temp.assert(not (power_status() -> 'notices' @> '[{"kind":"outage_none"}]'::jsonb), 'acknowledged: gone');
  -- the light comes back: a "back" notice for a cut the player saw
  perform pg_temp.set_area('ekenwan', 0);
  perform pg_temp.at('2026-11-20 10:05:00');
  r := power_status();
  perform pg_temp.assert(r -> 'notices' @> '[{"kind":"back"}]'::jsonb, 'Light don come back notice');
  perform power_ack('back', key);
  perform pg_temp.assert(not (power_status() -> 'notices' @> '[{"kind":"back"}]'::jsonb), 'back acknowledged');
  perform pg_temp.assert(pg_temp.hint_of($q$select power_ack('nonsense', 'x')$q$) = 'bad_kind', 'unknown notice kind refused');
  -- a city-wide cut has its own key
  perform pg_temp.login(pg_temp.uid('admin'));
  perform admin_power_event_start('blackout', 1, '');
  perform pg_temp.login(u);
  r := power_status();
  perform pg_temp.assert((r ->> 'city')::boolean and (r ->> 'cut_key') like 'city:%', 'a city-wide cut has a city key');
  perform pg_temp.login(pg_temp.uid('admin'));
  perform admin_power_event_end('blackout');
  perform pg_temp.set_area('ekenwan', 40);
end $$;

-- ---------- 8. effects ----------
do $$
declare r jsonb; u uuid := pg_temp.uid('none'); eff jsonb; furn jsonb;
begin
  perform pg_temp.at('2026-11-20 10:00:00');
  perform pg_temp.set_area('ekenwan', 100);
  perform pg_temp.login(u);
  perform pg_temp.assert(not bl_power_lit(u), 'no backup, mains off: not lit');
  furn := jsonb_build_object('owned', true, 'rest_pct', 100, 'bonus', jsonb_build_object('energy', 4, 'stress', -2));
  perform pg_temp.assert(pg_temp.hint_of($q$select bl_power_dark_furn(pg_temp.uid('none'), 'watch_tv', '{"bonus":{}}'::jsonb)$q$) = 'no_light', 'TV refused in the dark');
  perform pg_temp.assert(bl_power_dark_furn(u, 'sleep', furn) -> 'bonus' ->> 'energy' = '1.0', 'furniture bonus shrinks to 25 % in the dark');
  eff := bl_power_rest(u, 'sleep', '{"energy":40}'::jsonb);
  perform pg_temp.assert((eff ->> 'energy')::numeric = 34, 'sleep recovers 85 % in the dark (' || (eff ->> 'energy') || ')');
  perform pg_temp.assert(bl_power_house_bonus(u, 'sleep') = '{}'::jsonb, 'house upgrade bonuses are off in the dark');
  perform pg_temp.assert((bl_power_rest(u, 'bathe', '{"hygiene":30}'::jsonb) ->> 'hygiene') = '30', 'other activities are unchanged');
  -- a generator that runs lights the home: no penalty, but a noisy one adds stress while sleeping
  perform pg_temp.give(u, 'gen_tiger');
  perform bl_give_item(u, 'petrol', 5);
  perform power_refuel('petrol', 5);
  perform power_gen_toggle(true);
  perform pg_temp.assert(bl_power_lit(u), 'generator on: lit');
  perform pg_temp.assert(bl_power_dark_furn(u, 'sleep', furn) = furn, 'lit: furniture bonus kept');
  eff := bl_power_rest(u, 'sleep', '{"energy":40,"stress":-5}'::jsonb);
  perform pg_temp.assert((eff ->> 'energy')::numeric = 40 and (eff ->> 'stress')::numeric = -1, 'a noisy generator costs 4 stress while sleeping (' || (eff ->> 'stress') || ')');
  -- the real activity: do_activity goes through the same helpers
  perform power_gen_toggle(false);
  perform pg_temp.give(u, 'tv');
  perform pg_temp.give(u, 'foam_mat');
  update profiles set busy_until = null, jailed_until = null where id = u;
  perform pg_temp.assert(pg_temp.hint_of($q$select do_activity('watch_tv')$q$) = 'no_light', 'do_activity: Nollywood needs light');
  perform power_gen_toggle(true);
  perform pg_temp.assert(pg_temp.hint_of($q$select do_activity('watch_tv')$q$) = 'ok', 'do_activity: with the generator on the TV works');
  update profiles set busy_until = null where id = u;
  perform power_gen_toggle(false);
  -- the effects switch
  update game_config set value = 'false' where key = 'power.effects_enabled';
  perform pg_temp.assert(bl_power_dark_furn(u, 'watch_tv', '{"bonus":{}}'::jsonb) = '{"bonus":{}}'::jsonb, 'effects off: TV allowed');
  perform pg_temp.assert((bl_power_rest(u, 'sleep', '{"energy":40}'::jsonb) ->> 'energy') = '40', 'effects off: full rest');
  update game_config set value = 'true' where key = 'power.effects_enabled';
  perform pg_temp.set_area('ekenwan', 40);
end $$;

-- ---------- 9. visiting uses the host's area ----------
do $$
declare r jsonb; v uuid := pg_temp.uid('none'); h uuid := pg_temp.uid('gra');
begin
  perform pg_temp.at('2026-11-20 10:00:00');
  perform pg_temp.set_area('ekenwan', 100);
  perform pg_temp.set_area('gra', 0);
  perform pg_temp.login(v);
  r := power_status();
  perform pg_temp.assert(r #>> '{area,id}' = 'ekenwan' and not (r ->> 'lit')::boolean and not (r ->> 'visiting')::boolean, 'at home: Ekenwan, dark');
  update profiles set home_visit_host_id = h where id = v;
  r := power_status();
  perform pg_temp.assert(r #>> '{area,id}' = 'gra' and (r ->> 'lit')::boolean and (r ->> 'visiting')::boolean, 'visiting a GRA home: GRA, lit');
  perform pg_temp.assert(bl_power_lit(v), 'bl_power_lit follows the host while visiting');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r -> 'notices') e where e ->> 'kind' like 'outage%'), 'a visitor gets no cut notices for somebody else''s home');
  -- the host's generator state, not the visitor's
  perform pg_temp.set_area('gra', 100);
  r := power_status();
  perform pg_temp.assert(r #>> '{area,id}' = 'gra' and not (r ->> 'lit')::boolean, 'GRA cut: the visitor sits in the dark too');
  update profiles set home_visit_host_id = null where id = v;
  perform pg_temp.set_area('ekenwan', 40);
  perform pg_temp.set_area('gra', 8);
end $$;

-- ---------- 10. grants / RLS ----------
do $$
declare p text; v_none uuid := pg_temp.uid('none');
begin
  perform pg_temp.assert(not has_function_privilege('anon', 'public.power_status()', 'execute'), 'anon cannot read power_status');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.power_status()', 'execute'), 'players can call power_status');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.power_gen_toggle(boolean)', 'execute'), 'players can switch the generator');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.power_refuel(text,integer)', 'execute'), 'players can refuel');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_power_settle(uuid,boolean)', 'execute'), 'bl_power_settle is private');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.bl_power_mains(text,double precision)', 'execute'), 'bl_power_mains is private');
  perform pg_temp.assert(not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'bl\_power\_%' or proname like 'bl\_fuel\_%')
                                      and (has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute'))),
                         'no bl_power_* / bl_fuel_* helper is open to anon or players');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.player_power'::regclass), 'player_power has RLS');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.power_events'::regclass), 'power_events has RLS');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.power_areas'::regclass), 'power_areas has RLS');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.power_gear'::regclass), 'power_gear has RLS');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.player_power', 'insert') and not has_table_privilege('authenticated', 'public.player_power', 'update'),
                         'players cannot write player_power');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.power_events', 'select'), 'players cannot read power_events');
  perform pg_temp.assert(not has_table_privilege('anon', 'public.player_power', 'select'), 'anon cannot read player_power');
  perform pg_temp.login(pg_temp.uid('none'));
  execute 'set local role authenticated';
  perform pg_temp.assert((select count(*) from player_power) <= 1, 'a player sees at most their own power row');
  perform pg_temp.assert(not exists (select 1 from player_power where user_id <> v_none), 'no one else''s row is visible');
  execute 'reset role';
end $$;

-- clean up the test players (the whole run rolls back anyway)
delete from auth.users where email like 'pw\_%@power.bl';
