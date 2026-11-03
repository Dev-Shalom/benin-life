-- Drive scene 2 (20261116000100_drive_realtime.sql, docs/DRIVE.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/drive2_test.sql
-- Groups: 1 settings · 2 the ECTS Bus label · 3 trip time grows with the real distance (formula, modes, clamps) ·
-- 4 switch off = the old timings, and the old cap does not fight the new one · 5 travel_start stores the same length · 6 closed airport.
-- Times are pinned with bl.test_offset_seconds where a trip is started.
create or replace function pg_temp.setc(p_key text, p_val jsonb) returns void
language sql as $$ update game_config set value = p_val where key = p_key $$;

create or replace function pg_temp.opt(p_uid uuid, p_dest text, p_mode text) returns jsonb
language plpgsql as $$
declare q jsonb;
begin
  q := bl_travel_quote((select p from profiles p where p.id = p_uid), p_dest);
  return (select o from jsonb_array_elements(q->'options') o where o->>'mode' = p_mode);
end $$;

create temp table d2_u (name text primary key, id uuid);
create temp table d2_dest (kind text primary key, id text, km numeric);

do $$
declare v uuid; src text;
begin
  v := pg_temp.new_user('d2_a@drive.bl');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(v);
  perform create_profile_v2('D2_a', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  insert into d2_u values ('a', v);
  update profiles set cash = 5000000, needs_updated_at = bl_now() where id = v;
  select location_id into src from profiles where id = v;
  -- the nearest and the farthest open public place from where the player is
  insert into d2_dest select 'near', l.id, bl_distance_km(src, l.id) from locations l
   where l.active and l.id <> src and l.id not like 'home\_%' and bl_place_open(l) order by bl_distance_km(src, l.id), l.id limit 1;
  insert into d2_dest select 'far', l.id, bl_distance_km(src, l.id) from locations l
   where l.active and l.id <> src and l.id not like 'home\_%' and bl_place_open(l) order by bl_distance_km(src, l.id) desc, l.id limit 1;
end $$;

-- ---------- 1. settings ----------
do $$
declare n int;
begin
  perform pg_temp.assert((select count(*) from game_config where key like 'drive.travel.%') >= 12, 'trip time settings seeded');
  select count(*) into n from game_config where key like 'drive.travel.%'
     and (category <> 'drive' or coalesce(label, '') = '' or coalesce(description, '') = '' or (kind = 'number' and (min is null or max is null)));
  perform pg_temp.assert(n = 0, 'every trip time setting is in category drive, has a label, a description and a range (' || n || ' without)');
  perform pg_temp.assert((select kind from game_config where key = 'drive.travel.real_time_enabled') = 'bool', 'the master switch is a bool');
  perform pg_temp.assert((select value from game_config where key = 'drive.travel.real_time_enabled') = 'true'::jsonb, 'real trip time is on by default');
  perform pg_temp.assert(bl_cfg('drive.travel.max_seconds') = 150 and bl_cfg('drive.travel.min_seconds') = 25, 'defaults: 25 s to 150 s');
  perform pg_temp.assert((select count(*) from game_config where key like 'drive.travel.%' and (label ilike '%lagos%' or description ilike '%lagos%')) = 0, 'no "Lagos" in the text');
  perform pg_temp.assert((select km from d2_dest where kind = 'far') > (select km from d2_dest where kind = 'near') + 3, 'the test places are really near and far (' ||
    (select km from d2_dest where kind = 'near') || ' km, ' || (select km from d2_dest where kind = 'far') || ' km)');
end $$;

-- ---------- 2. the bus is the ECTS Bus ----------
do $$
declare a uuid := (select id from d2_u where name = 'a'); q jsonb; far text := (select id from d2_dest where kind = 'far');
begin
  perform pg_temp.login(a);
  q := bl_travel_quote((select p from profiles p where p.id = a), far);
  perform pg_temp.assert(pg_temp.opt(a, far, 'bus')->>'label' = 'ECTS Bus', 'the bus option says ECTS Bus (got ' || (pg_temp.opt(a, far, 'bus')->>'label') || ')');
  perform pg_temp.assert(q::text not ilike '%green%', 'no "Green" left in the travel options');
  perform pg_temp.assert(pg_temp.opt(a, far, 'keke')->>'label' = 'Keke Napep' and pg_temp.opt(a, far, 'walk')->>'label' = 'Walk', 'the other labels did not change');
  perform pg_temp.assert(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prosrc ilike '%ECTS Green Bus%'), 'no function still says ECTS Green Bus');
  perform pg_temp.assert((length(pg_get_functiondef('public.bl_travel_quote(public.profiles, text)'::regprocedure)) -
    length(replace(pg_get_functiondef('public.bl_travel_quote(public.profiles, text)'::regprocedure), 'drive.travel.real_time_enabled', ''))) / length('drive.travel.real_time_enabled') = 1,
    'the quote carries the trip time patch exactly once');
end $$;

-- ---------- 3. trip time grows with the real distance ----------
do $$
declare a uuid := (select id from d2_u where name = 'a'); far text := (select id from d2_dest where kind = 'far'); near text := (select id from d2_dest where kind = 'near');
  m text; km_far numeric := (select km from d2_dest where kind = 'far'); f numeric; want numeric; got numeric; prev numeric;
begin
  perform pg_temp.login(a);
  -- the formula, with the clamps out of the way
  perform pg_temp.setc('drive.travel.min_seconds', '1'); perform pg_temp.setc('drive.travel.max_seconds', '1800');
  foreach m in array array['walk', 'keke', 'bus', 'drop', 'car'] loop
    f := bl_cfg('drive.travel.f_' || m);
    want := round(bl_cfg('drive.travel.base_seconds') + bl_cfg('drive.travel.seconds_per_km') * km_far * f, 1);
    got := (pg_temp.opt(a, far, m)->>'real_seconds')::numeric;
    perform pg_temp.assert(abs(got - want) <= 0.11, m || ': real_seconds = base + per_km x km x factor (want ' || want || ', got ' || got || ')');
  end loop;
  -- far takes longer than near in every mode
  foreach m in array array['walk', 'keke', 'bus', 'drop', 'car'] loop
    perform pg_temp.assert((pg_temp.opt(a, far, m)->>'real_seconds')::numeric > (pg_temp.opt(a, near, m)->>'real_seconds')::numeric, m || ': the far trip is longer than the near one');
  end loop;
  -- the speed differences stay: walk > bus > keke > drop > car
  perform pg_temp.assert((pg_temp.opt(a, far, 'walk')->>'real_seconds')::numeric > (pg_temp.opt(a, far, 'bus')->>'real_seconds')::numeric
                     and (pg_temp.opt(a, far, 'bus')->>'real_seconds')::numeric > (pg_temp.opt(a, far, 'keke')->>'real_seconds')::numeric
                     and (pg_temp.opt(a, far, 'keke')->>'real_seconds')::numeric > (pg_temp.opt(a, far, 'drop')->>'real_seconds')::numeric
                     and (pg_temp.opt(a, far, 'drop')->>'real_seconds')::numeric > (pg_temp.opt(a, far, 'car')->>'real_seconds')::numeric, 'walk > bus > keke > drop > car');
  -- the clamps (defaults back)
  perform pg_temp.setc('drive.travel.min_seconds', '25'); perform pg_temp.setc('drive.travel.max_seconds', '150');
  foreach m in array array['walk', 'keke', 'bus', 'drop', 'car'] loop
    got := (pg_temp.opt(a, near, m)->>'real_seconds')::numeric;
    perform pg_temp.assert(got >= 25 and got <= 150, m || ': a near trip stays inside 25 s to 150 s (' || got || ')');
    got := (pg_temp.opt(a, far, m)->>'real_seconds')::numeric;
    perform pg_temp.assert(got >= 25 and got <= 150, m || ': a far trip stays inside 25 s to 150 s (' || got || ')');
  end loop;
  perform pg_temp.assert((pg_temp.opt(a, far, 'walk')->>'real_seconds')::numeric = 150, 'walking across town hits the 150 s cap');
  perform pg_temp.setc('drive.travel.max_seconds', '40');
  perform pg_temp.assert((pg_temp.opt(a, far, 'walk')->>'real_seconds')::numeric = 40 and (pg_temp.opt(a, far, 'bus')->>'real_seconds')::numeric <= 40, 'max_seconds is the ceiling');
  perform pg_temp.setc('drive.travel.max_seconds', '150'); perform pg_temp.setc('drive.travel.min_seconds', '100');
  perform pg_temp.assert((pg_temp.opt(a, near, 'car')->>'real_seconds')::numeric = 100, 'min_seconds is the floor');
  perform pg_temp.setc('drive.travel.min_seconds', '25');
  -- fare and risk numbers are still there
  perform pg_temp.assert((pg_temp.opt(a, far, 'bus')->>'cost')::bigint = 300 and pg_temp.opt(a, far, 'car') ? 'risk_pct', 'cost and risk are untouched');
  prev := (pg_temp.opt(a, far, 'car')->>'game_minutes')::numeric;
  perform pg_temp.assert(prev >= 1, 'game minutes are still there');
end $$;

-- ---------- 4. the master switch, and the old cap does not fight the new one ----------
do $$
declare a uuid := (select id from d2_u where name = 'a'); far text := (select id from d2_dest where kind = 'far'); m text; got numeric;
begin
  perform pg_temp.login(a);
  -- off: the old short timings (everything at or under action.travel_max_seconds = 20)
  perform pg_temp.setc('drive.travel.real_time_enabled', 'false');
  foreach m in array array['walk', 'keke', 'bus', 'drop', 'car'] loop
    got := (pg_temp.opt(a, far, m)->>'real_seconds')::numeric;
    perform pg_temp.assert(got <= bl_cfg('action.travel_max_seconds') + 0.01, m || ': switch off = old short trip (' || got || ' s)');
  end loop;
  -- on again with a tiny old cap: the new rules still decide
  perform pg_temp.setc('drive.travel.real_time_enabled', 'true');
  perform pg_temp.setc('action.travel_max_seconds', '5');
  got := (pg_temp.opt(a, far, 'car')->>'real_seconds')::numeric;
  perform pg_temp.assert(got >= 25, 'the old cap (action.travel_max_seconds) does not clip a real-time trip (' || got || ' s)');
  -- and off with the tiny cap: the old cap is back in charge
  perform pg_temp.setc('drive.travel.real_time_enabled', 'false');
  got := (pg_temp.opt(a, far, 'car')->>'real_seconds')::numeric;
  perform pg_temp.assert(got <= 5.01, 'switch off: the old cap rules again (' || got || ' s)');
  perform pg_temp.setc('drive.travel.real_time_enabled', 'true');
  perform pg_temp.setc('action.travel_max_seconds', '20');
end $$;

-- ---------- 5. travel_start stores exactly the quoted length ----------
do $$
declare a uuid := (select id from d2_u where name = 'a'); far text := (select id from d2_dest where kind = 'far'); r jsonb; q numeric; len numeric;
begin
  perform pg_temp.login(a);
  q := (pg_temp.opt(a, far, 'bus')->>'real_seconds')::numeric;
  r := travel_start(far, 'bus');
  perform pg_temp.assert((r->>'real_seconds')::numeric = q, 'travel_start returns the quoted real_seconds');
  select extract(epoch from (travel_arrives_at - travel_started_at)) into len from profiles where id = a;
  perform pg_temp.assert(abs(len - q) < 0.06, 'arrival minus start = the quoted seconds (' || len || ' vs ' || q || ')');
  perform pg_temp.assert(q > 25, 'a cross-town bus ride is a long one (' || q || ' s)');
  perform pg_temp.assert((select travel_mode from profiles where id = a) = 'bus', 'the trip is on the bus');
end $$;

-- ---------- 6. the airport is closed ----------
do $$
declare a uuid := (select id from d2_u where name = 'a');
begin
  perform pg_temp.login(a);
  update profiles set travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null where id = a;
  begin
    perform bl_travel_quote((select p from profiles p where p.id = a), 'benin_airport');
    perform pg_temp.assert(false, 'the airport should be closed');
  exception when others then
    perform pg_temp.assert(sqlerrm like '%under construction%', 'the airport says it is under construction (' || sqlerrm || ')');
  end;
end $$;
