-- Closed places (20261007000200_closed_places.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/closed_places_test.sql
-- Groups: 1 travel to a place outside its hours is refused (quote + start), allowed when open, home always ok ·
-- 2 place_closed_eject sends a Sim inside a closed place home with an alert; no-op when open / at home / busy.

create or replace function pg_temp.cp_hint(p_sql text, p_hint text) returns text
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

create or replace function pg_temp.cp_at_hour(p_hour int) returns void
language plpgsql as $$
declare c jsonb; cur numeric; delta numeric;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  c := bl_game_clock();
  cur := (c->>'hour')::numeric * 3600 + (c->>'minute')::numeric * 60;
  delta := ((p_hour * 3600 + 1800 - cur)::numeric % 86400 + 86400) % 86400;
  perform set_config('bl.test_offset_seconds', delta::text, true);
end $$;

do $$
declare v uuid := pg_temp.new_user('cp_ada@closed.bl'); m text; q jsonb; r jsonb; home text; n0 bigint;
begin
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2('Cp_Ada', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, cash = 1000000 where id = v;
  select home_location_id into home from profiles where id = v;
  update game_config set value = 'true' where key = 'places.hours_enabled';

  -- 1. travel to a closed place is refused; open is fine; home always reachable
  perform pg_temp.cp_at_hour(13);
  m := pg_temp.cp_hint($q$ select travel_quote('club_360') $q$, 'closed');
  perform pg_temp.assert(m like '360 Signature is closed right now. It opens at%', 'closed message: ' || m);
  perform pg_temp.cp_hint($q$ select travel_start('club_360', 'walk') $q$, 'closed');
  perform pg_temp.cp_at_hour(23);
  q := travel_quote('club_360');
  perform pg_temp.assert(q->>'dest' = 'club_360', 'open club can be travelled to');
  perform pg_temp.cp_at_hour(13);
  update profiles set location_id = 'mama_ebo' where id = v;
  q := travel_quote(home);
  perform pg_temp.assert(q->>'dest' = home, 'home always reachable');
  raise notice 'ok 1: closed places refuse travel; open ok; home ok';

  -- 2. eject
  update profiles set location_id = 'club_360', busy_until = null, travel_to = null where id = v;
  n0 := (select count(*) from events where user_id = v and kind = 'place_closed');
  r := place_closed_eject();
  perform pg_temp.assert((r->>'ejected')::boolean, 'ejected from a closed club: ' || r::text);
  perform pg_temp.assert((select location_id from profiles where id = v) = home, 'sent home');
  perform pg_temp.assert((select count(*) from events where user_id = v and kind = 'place_closed') = n0 + 1, 'alert sent');
  r := place_closed_eject();
  perform pg_temp.assert(not (r->>'ejected')::boolean and r->>'reason' = 'home', 'no-op at home');
  perform pg_temp.cp_at_hour(23);
  update profiles set location_id = 'club_360' where id = v;
  r := place_closed_eject();
  perform pg_temp.assert(not (r->>'ejected')::boolean and r->>'reason' = 'open', 'no-op when open');
  perform pg_temp.cp_at_hour(13);
  update profiles set busy_until = now() + interval '1 hour' where id = v;
  r := place_closed_eject();
  perform pg_temp.assert(not (r->>'ejected')::boolean and r->>'reason' = 'busy', 'no-op while busy');
  perform pg_temp.assert((select location_id from profiles where id = v) = 'club_360', 'still inside while busy');
  raise notice 'ok 2: place_closed_eject';
end $$;
