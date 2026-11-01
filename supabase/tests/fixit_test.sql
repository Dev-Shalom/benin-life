-- "Fix it" update (migrations 20261110000100 and up). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/fixit_test.sql
-- One group per item with server logic (the numbers in the headers are the item numbers):
-- 3 club spray alert prefs · 4 beds · 5 gang boss hand-back · 6 land levy · 7 laptops · 8 delete account ·
-- 9 phone banking · 10 primary car · 11 balance guards · 12 money history
create or replace function pg_temp.fx_hint(p_sql text) returns text
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

create or replace function pg_temp.fx_make(p_name text, p_cash bigint default 1000000, p_bank bigint default 1000000) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@fx.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  update game_config set value = 'false' where key = 'stories.push_enabled';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  update profiles set last_seen = now() - interval '1 hour', transfer_trusted = true, bank = p_bank, cash = p_cash,
         protected_until = null where id = v;
  return v;
end $$;

-- ---------- 3. Club spray alerts ----------
do $$
declare a uuid := pg_temp.fx_make('FxAda'); b uuid := pg_temp.fx_make('FxBayo'); r jsonb; v_club text; n int;
begin
  perform pg_temp.login(a);
  r := club_alert_prefs_get();
  perform pg_temp.assert((r->>'toasts')::boolean and not (r->>'strip')::boolean and not (r->>'push')::boolean, 'defaults: toasts on, strip off, push off');
  r := club_alert_prefs_set('{"push": true}');
  perform pg_temp.assert((r->>'push')::boolean and (r->>'toasts')::boolean, 'partial set');
  perform pg_temp.assert(pg_temp.fx_hint($q$select club_alert_prefs_set('{"nope": true}')$q$) = 'bad_value', 'unknown switch refused');
  perform pg_temp.assert(pg_temp.fx_hint($q$select club_alert_prefs_set('{"push": 1}')$q$) = 'bad_value', 'non-boolean refused');
  -- B cannot see A's row
  perform pg_temp.login(b);
  perform pg_temp.assert((club_alert_prefs_get()->>'push')::boolean = false, 'B has own defaults');
  set local role authenticated;
  select count(*) into n from club_alert_prefs;
  reset role;
  perform pg_temp.assert(n = 0, 'RLS: B reads no other row');
  raise notice 'ok 3: club spray alert prefs';
end $$;

-- ---------- 4. Beds: every sleeping piece works, also a second bed in an extension room ----------
-- (the bug was in the client: the Sim always walked to the FIRST bed, not the one tapped; the server never cared where a bed stood)
do $$
declare v uuid := pg_temp.fx_make('FxBedder', 50000000, 0); r record; res jsonb; n int := 0;
begin
  perform pg_temp.login(v);
  insert into player_house_upgrades(user_id, upgrade_id, start_home, done_at, source)
    values (v, 'ext_bedroom', (select start_home from profiles where id = v), now(), 'admin');
  perform bl_furniture_materialize(v);
  for r in select id from furniture where 'sleep' = any(activities) and active order by price loop
    delete from player_furniture where user_id = v and furniture_id = r.id;
    insert into player_furniture(user_id, furniture_id, slot, source, qty) values (v, r.id, null, 'buy', 1);
    perform bl_furniture_materialize(v);
    perform pg_temp.assert((bl_furniture_for(v, 'sleep')->>'owned')::boolean, 'bed ' || r.id || ' hosts sleep');
    perform pg_temp.assert((bl_furniture_for(v, 'nap')->>'owned')::boolean, 'bed ' || r.id || ' hosts nap');
    n := n + 1;
    delete from player_furniture where user_id = v and furniture_id = r.id;
    delete from player_house_furniture where owner_id = v and furniture_key like 'own\_' || r.id || '%';
  end loop;
  perform pg_temp.assert(n >= 8, 'all bed kinds checked');
  -- a second bed standing in the extension room: sleep works and the room's bonus applies
  insert into player_furniture(user_id, furniture_id, slot, source, qty) values (v, 'bed_single', null, 'buy', 1);
  perform bl_furniture_materialize(v);
  res := furniture_place('own_bed_single', 3.2, 7.4, 0);
  perform pg_temp.assert(res->>'stored' = 'false', 'bed placed in the extension room');
  res := do_activity('sleep');
  perform pg_temp.assert((res->'effects'->>'energy')::numeric = 85 and (res->'effects'->>'stress')::numeric < -20, 'sleep works, extension room bonus on');
  raise notice 'ok 4: beds';
end $$;

-- ---------- 5. Gang Boss hand-back ----------
do $$
declare a uuid := pg_temp.fx_make('FxBossA'); b uuid := pg_temp.fx_make('FxBossB'); c uuid := pg_temp.fx_make('FxBossC');
        v_crew bigint; r jsonb; v_admin uuid := pg_temp.fx_make('FxBossAdm');
begin
  update profiles set created_at = now() - interval '30 days' where id in (a, b, c, v_admin);
  perform pg_temp.login(a);
  r := crew_create('Fixit Boys', 'FXB', '#aa3322', '🌙');
  select crew_id into v_crew from crew_members where user_id = a;
  perform bl_crew_add_member(v_crew, b, 'member');
  perform bl_crew_add_member(v_crew, c, 'member');
  -- nothing handed over yet
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_handback()') <> 'ok', 'a founder has nothing to hand back');
  perform pg_temp.assert(not (crew_boss_state()->>'can_handback')::boolean, 'state: no handback for the founder');
  -- A hands the gang to B by mistake
  perform crew_transfer(b);
  perform pg_temp.assert((select rank from crew_members where user_id = b) = 'boss' and (select rank from crew_members where user_id = a) = 'lieutenant', 'B is Boss');
  perform pg_temp.assert((crew_boss_state()->>'can_request')::boolean, 'state: A may ask');
  -- C (random member) can do nothing
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_request()') = 'not_previous_boss', 'C cannot ask');
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_handback()') <> 'ok', 'C cannot hand back');
  -- A asks, B declines
  perform pg_temp.login(a);
  perform crew_boss_request();
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_request()') = 'pending', 'one request at a time');
  perform pg_temp.login(b);
  perform pg_temp.assert((crew_boss_state()->'request'->>'to_me')::boolean, 'B sees the request');
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_respond(true)') <> 'ok', 'A cannot answer their own request');
  perform pg_temp.login(b);
  perform crew_boss_respond(false);
  perform pg_temp.assert((select rank from crew_members where user_id = b) = 'boss', 'declined: B stays Boss');
  -- A asks again, B accepts
  perform pg_temp.login(a);
  perform crew_boss_request();
  perform pg_temp.login(b);
  perform crew_boss_respond(true);
  perform pg_temp.assert((select rank from crew_members where user_id = a) = 'boss' and (select rank from crew_members where user_id = b) = 'lieutenant', 'accepted: A is Boss again');
  -- late request is refused: hand over again, age the handover past 24 h
  perform pg_temp.login(a);
  perform crew_transfer(b);
  update crew_boss_log set created_at = now() - interval '25 hours' where crew_id = v_crew and kind = 'transfer';
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_request()') = 'too_late', 'after 24 h the request is refused');
  -- but B can hand it back any time
  perform pg_temp.login(b);
  perform pg_temp.assert((crew_boss_state()->>'can_handback')::boolean, 'state: B may hand back');
  perform crew_boss_handback();
  perform pg_temp.assert((select rank from crew_members where user_id = a) = 'boss' and (select rank from crew_members where user_id = b) = 'lieutenant', 'handed back');
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_handback()') <> 'ok', 'hand back once');
  perform pg_temp.assert((select count(*) from crew_boss_log where crew_id = v_crew) >= 7, 'every step is in the log');
  -- admin sets the Boss
  update profiles set is_admin = false where is_admin;
  update profiles set is_admin = true where id = v_admin;
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.fx_hint(format('select admin_crew_set_boss(%L, %s, ''x'')', c, v_crew)) <> 'ok', 'a player cannot use the admin RPC');
  perform pg_temp.login(v_admin);
  perform admin_crew_set_boss(c, v_crew, 'Owner request');
  perform pg_temp.assert((select rank from crew_members where user_id = c) = 'boss' and (select count(*) from crew_members where crew_id = v_crew and rank = 'boss') = 1, 'admin made C Boss');
  perform pg_temp.assert((select rank from crew_members where user_id = a) = 'lieutenant', 'old Boss is Lieutenant');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'grant_crew_boss' and target_user = c), 'admin audit row');
  raise notice 'ok 5: gang boss hand-back';
end $$;
