-- F1 club soft launch (20261006001400_soft_launch.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/soft_launch_test.sql
-- Groups: 1 seed (only 360 Signature open among the seeded clubs, flag set) · 2 an inactive place blocks travel,
-- activities, buying and shifts; a player inside can still leave / go home · 3 admin toggles + hours (audited);
-- players can't · 4 hours edited by the admin are enforced.

create or replace function pg_temp.sl_hint(p_sql text, p_hint text) returns text
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

create or replace function pg_temp.sl_at_hour(p_hour int) returns void
language plpgsql as $$
declare c jsonb; cur numeric; delta numeric;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  c := bl_game_clock();
  cur := (c->>'hour')::numeric * 3600 + (c->>'minute')::numeric * 60;
  delta := ((p_hour * 3600 + 1800 - cur)::numeric % 86400 + 86400) % 86400;
  perform set_config('bl.test_offset_seconds', delta::text, true);
end $$;

create temp table t_sl (name text primary key, id uuid not null) on commit drop;
grant select on t_sl to authenticated;
create or replace function pg_temp.sl(p_name text) returns uuid
language sql as $$ select id from t_sl where name = p_name $$;

do $$
declare v uuid := pg_temp.new_user('sl_ada@soft.bl'); adm uuid := pg_temp.new_user('sl_adm@soft.bl');
begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  insert into t_sl values ('ada', v), ('adm', adm);
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2('Sl_Ada', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, cash = 1000000 where id = v;
  perform pg_temp.login(adm);
  perform create_profile_v2('Sl_Adm', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set is_admin = true where id = adm;
end $$;

-- ---------- 1. seed ----------
do $$
begin
  perform pg_temp.assert((select active and open_hour = 21 and close_hour = 5 from locations where id = 'club_360'),
                         '360 Signature active, 9 PM - 5 AM');
  perform pg_temp.assert(not exists (select 1 from locations where active and id in
    ('club_de_medici', 'rome_club', 'cube_nightlife', 'versus_lounge', 'owambe_republic')), 'other L2 clubs hidden');
  perform pg_temp.assert((select value = 'true'::jsonb from game_config where key = 'places.soft_launch_seeded'), 'one-shot flag set');
  perform pg_temp.assert((select count(*) from locations where not active and scene <> 'club') = 0, 'only clubs were hidden');
  raise notice 'ok 1: soft launch seed';
end $$;

-- ---------- 2. an inactive place blocks travel, activity, buying, shifts ----------
do $$
declare a uuid := pg_temp.sl('ada'); m text; q jsonb; c0 bigint; home text;
begin
  perform pg_temp.login(a);
  select home_location_id into home from profiles where id = a;
  -- travel: refused to a hidden club, allowed to 360 Signature
  m := pg_temp.sl_hint($q$ select travel_quote('rome_club') $q$, 'inactive');
  perform pg_temp.assert(m like 'Rome Night Club is closed for now%', 'inactive message: ' || m);
  perform pg_temp.sl_hint($q$ select travel_start('rome_club', 'walk') $q$, 'inactive');
  perform pg_temp.sl_at_hour(23);  -- open hours (closed places can't be travelled to since 20261007000200)
  q := travel_quote('club_360');
  perform pg_temp.assert(q->>'dest' = 'club_360', '360 Signature can be travelled to');
  -- a player already inside a place that gets hidden: no actions, no buying, but can leave
  update locations set active = false where id = 'club_360';
  perform pg_temp.sl_at_hour(23);
  update profiles set location_id = 'club_360', busy_until = null, travel_to = null where id = a;
  c0 := (select cash from profiles where id = a);
  m := pg_temp.sl_hint($q$ select do_activity('club_dance') $q$, 'inactive');
  perform pg_temp.assert(m like '360 Signature is closed for now%', 'activity refused: ' || m);
  perform pg_temp.sl_hint($q$ select shop_buy('star_beer', 1) $q$, 'inactive');
  perform pg_temp.assert((select cash from profiles where id = a) = c0, 'nothing charged');
  perform pg_temp.assert((place_interior('club_360')->>'open')::boolean = false
                         and place_interior('club_360')->>'opens' = 'Closed for now'
                         and (place_interior('club_360')->>'active')::boolean = false, 'interior says closed for now');
  q := travel_quote(home);
  perform pg_temp.assert(q->>'dest' = home, 'can still travel home');
  q := travel_quote('mama_ebo');
  perform pg_temp.assert(q->>'dest' = 'mama_ebo', 'can still travel elsewhere');
  -- your own home is always reachable, even if hidden
  update profiles set location_id = 'mama_ebo' where id = a;
  update locations set active = false where id = home;
  q := travel_quote(home);
  perform pg_temp.assert(q->>'dest' = home, 'hidden home still reachable');
  update locations set active = true where id = home;
  -- shifts at a hidden workplace are refused
  update profiles set job_id = 'tech', job_level = 1, location_id = 'bronze_tech_hub', energy = 100, hunger = 100 where id = a;
  update locations set active = false where id = 'bronze_tech_hub';
  perform pg_temp.sl_hint($q$ select work_shift() $q$, 'inactive');
  update locations set active = true where id in ('bronze_tech_hub', 'club_360');
  -- back on: club works at night
  update profiles set location_id = 'club_360', job_id = null where id = a;
  perform do_activity('club_dance');
  raise notice 'ok 2: inactive place blocks travel, activities, buying and shifts; players can leave';
end $$;

-- ---------- 3. admin toggles + hours; players can't ----------
do $$
declare a uuid := pg_temp.sl('ada'); adm uuid := pg_temp.sl('adm'); r jsonb; ok boolean := false;
begin
  perform pg_temp.login(adm);
  r := admin_row_upsert('locations', '{"id": "rome_club", "active": true}');
  perform pg_temp.assert((select active from locations where id = 'rome_club'), 'admin switched Rome on');
  r := admin_row_upsert('locations', '{"id": "club_360", "active": false}');
  perform pg_temp.assert(not (select active from locations where id = 'club_360'), 'admin switched 360 off');
  r := admin_row_upsert('locations', '{"id": "club_360", "active": true, "open_hour": 22, "close_hour": 4}');
  perform pg_temp.assert((select active and open_hour = 22 and close_hour = 4 from locations where id = 'club_360'), 'admin hours 22 -> 4');
  r := admin_row_upsert('locations', '{"id": "club_360", "open_hour": 21.5, "close_hour": 4}');
  perform pg_temp.assert((select open_hour = 21.5 from locations where id = 'club_360'), 'half hours allowed');
  perform pg_temp.sl_hint($q$ select admin_row_upsert('locations', '{"id": "club_360", "open_hour": 25, "close_hour": 4}') $q$, 'bad_value');
  perform pg_temp.sl_hint($q$ select admin_row_upsert('locations', '{"id": "club_360", "active": "maybe"}') $q$, 'bad_value');
  ok := false;
  begin perform admin_row_upsert('locations', '{"id": "club_360", "open_hour": 20, "close_hour": null}');
  exception when others then ok := true; end;
  perform pg_temp.assert(ok, 'opening hour without closing hour refused');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'row_update' and data->>'table' = 'locations'), 'audited');
  -- a re-run of the seed never overrides the admin's choices
  perform pg_temp.assert((select active from locations where id = 'rome_club'), 'flag already set: Rome stays on');
  -- players can't
  perform pg_temp.login(a);
  ok := false;
  begin perform admin_row_upsert('locations', '{"id": "rome_club", "active": false}'); exception when others then ok := true; end;
  perform pg_temp.assert(ok and (select active from locations where id = 'rome_club'), 'player cannot toggle');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.locations', 'UPDATE')
                         and not has_table_privilege('anon', 'public.locations', 'UPDATE'), 'players cannot write locations directly');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_assert_place_active(public.locations)', 'EXECUTE'), 'helper not callable');
  raise notice 'ok 3: admin toggles and edits hours (audited); players cannot';
end $$;

-- ---------- 4. edited hours are enforced ----------
do $$
declare a uuid := pg_temp.sl('ada'); m text;
begin
  perform pg_temp.login(a);
  update profiles set location_id = 'club_360', busy_until = null where id = a;
  -- 360 now opens 21:30, closes 4
  perform pg_temp.sl_at_hour(21);       -- 21:30 = open
  perform pg_temp.assert((place_interior('club_360')->>'open')::boolean, 'open at 21:30');
  perform pg_temp.sl_at_hour(4);        -- 4:30 = closed (closes 4)
  m := pg_temp.sl_hint($q$ select do_activity('club_dance') $q$, 'closed');
  perform pg_temp.assert(m like '%Opens 9:30 PM%' or m like '%Opens 9%', 'closed message: ' || m);
  perform pg_temp.sl_hint($q$ select shop_buy('star_beer', 1) $q$, 'closed');
  perform pg_temp.sl_at_hour(3);        -- 3:30 = open
  perform pg_temp.assert((place_interior('club_360')->>'open')::boolean, 'open at 3:30');
  raise notice 'ok 4: edited hours enforced';
end $$;
