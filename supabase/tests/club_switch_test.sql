-- R2 club switch (20261017000200_club_switch.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/club_switch_test.sql
-- Groups: 1 every club is ON by default; admin list · 2 switching OFF audits, sends idle players home, refuses
-- travel / activity / shop / spray / ticket with a friendly message, hides the club's events · 3 busy player is
-- cleared by place_closed_eject with the "closed for now" wording · 4 switching ON again restores everything ·
-- 5 players can't use the admin RPCs; unknown / non-club ids refused.

create or replace function pg_temp.cs_hint(p_sql text, p_hint text) returns text
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

create or replace function pg_temp.cs_at_hour(p_hour int) returns void
language plpgsql as $$
declare c jsonb; cur numeric; delta numeric;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  c := bl_game_clock();
  cur := (c->>'hour')::numeric * 3600 + (c->>'minute')::numeric * 60;
  delta := ((p_hour * 3600 + 1800 - cur)::numeric % 86400 + 86400) % 86400;
  perform set_config('bl.test_offset_seconds', delta::text, true);
end $$;

create temp table t_cs (name text primary key, id uuid not null) on commit drop;
grant select on t_cs to authenticated;
create or replace function pg_temp.cs(p_name text) returns uuid
language sql as $$ select id from t_cs where name = p_name $$;

do $$
declare a uuid := pg_temp.new_user('cs_ada@club.bl'); b uuid := pg_temp.new_user('cs_bayo@club.bl'); adm uuid := pg_temp.new_user('cs_adm@club.bl');
begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  insert into t_cs values ('ada', a), ('bayo', b), ('adm', adm);
  perform pg_temp.login(a);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2('Cs_Ada', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, cash = 5000000 where id = a;
  perform pg_temp.login(b);
  perform create_profile_v2('Cs_Bayo', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, cash = 5000000 where id = b;
  perform pg_temp.login(adm);
  perform create_profile_v2('Cs_Adm', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set is_admin = true where id = adm;
  -- the hidden soft-launch clubs and the test club hours: make Club Raptor a normal ON club for the test
  update locations set active = true where id in ('club_raptor', 'patricia_nightlife');
end $$;

-- ---------- 1. default ON + the list ----------
do $$
declare adm uuid := pg_temp.cs('adm'); l jsonb; row jsonb; n0 bigint := (select count(*) from admin_audit where action = 'club_switch');
begin
  perform pg_temp.login(adm);
  l := admin_club_list();
  perform pg_temp.assert(jsonb_array_length(l) = (select count(*) from locations where scene = 'club'), 'list has every club');
  perform pg_temp.assert((select count(*) from jsonb_array_elements(l) e where e->>'id' in ('club_raptor', 'patricia_nightlife', 'club_360')) = 3, 'known clubs listed');
  row := (select e from jsonb_array_elements(l) e where e->>'id' = 'club_raptor');
  perform pg_temp.assert((row->>'on')::boolean, 'club_raptor is ON');
  perform pg_temp.assert(row ? 'inside' and row ? 'events' and row ? 'open_now', 'list carries inside / events / open_now');
  -- a no-op switch changes nothing and logs nothing
  perform pg_temp.assert(not (admin_club_set('club_raptor', true)->>'changed')::boolean, 'already on: no change');
  perform pg_temp.assert((select count(*) from admin_audit where action = 'club_switch') = n0, 'no audit for a no-op');
  raise notice 'ok 1: default ON, admin list';
end $$;

-- ---------- 2. switch OFF ----------
do $$
declare a uuid := pg_temp.cs('ada'); b uuid := pg_temp.cs('bayo'); adm uuid := pg_temp.cs('adm');
        m text; r jsonb; home text; n0 bigint; wd int; c0 bigint;
begin
  perform pg_temp.cs_at_hour(23);
  -- a weekly club event on tonight so the banner has something to hide
  wd := (bl_game_clock()->>'weekday')::int;
  insert into place_events (id, location_id, title, description, kind, icon, recurrence, weekday, start_time, end_time, ticket_price, capacity, perks, variants, sort)
  values ('cs_test_night', 'club_raptor', 'CS test night', 'test', 'club_night', '🦖', 'weekly', wd, 22, 4, 0, 100, '{}'::jsonb, '', 999);
  perform pg_temp.login(a);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(events_on_today()) e where e->>'location_id' = 'club_raptor'), 'event shows while ON');
  update profiles set location_id = 'club_raptor', busy_until = null, travel_to = null where id = a;
  select home_location_id into home from profiles where id = a;
  update profiles set location_id = 'club_raptor', busy_until = now() + interval '1 hour', travel_to = null where id = b;
  perform do_activity('club_dance');   -- ON: works
  update profiles set busy_until = null where id = a;

  perform pg_temp.login(adm);
  r := admin_club_set('club_raptor', false);
  perform pg_temp.assert((r->>'changed')::boolean and not (r->>'on')::boolean and (r->>'moved')::int = 1, 'off: one idle player moved: ' || r::text);
  perform pg_temp.assert(not (select active from locations where id = 'club_raptor'), 'locations.active false');
  perform pg_temp.assert((select location_id from profiles where id = a) = home, 'idle player sent home');
  perform pg_temp.assert((select location_id from profiles where id = b) = 'club_raptor', 'busy player left alone for now');
  perform pg_temp.assert((select count(*) from events where user_id = a and kind = 'place_closed' and data->>'location_id' = 'club_raptor') = 1, 'alert sent');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'club_switch' and admin_id = adm
                                   and data->>'location_id' = 'club_raptor' and (data->>'on')::boolean = false), 'audited');
  -- the others stay ON
  perform pg_temp.assert((select active from locations where id = 'patricia_nightlife'), 'other clubs untouched');

  perform pg_temp.login(a);
  m := pg_temp.cs_hint($q$ select travel_quote('club_raptor') $q$, 'inactive');
  perform pg_temp.assert(m = 'Club Raptor is closed for now. Check back soon.', 'friendly travel message: ' || m);
  perform pg_temp.cs_hint($q$ select travel_start('club_raptor', 'walk') $q$, 'inactive');
  -- already-inside actions (put the player back as if they never left)
  update profiles set location_id = 'club_raptor', busy_until = null where id = a;
  c0 := (select cash from profiles where id = a);
  m := pg_temp.cs_hint($q$ select do_activity('club_dance') $q$, 'inactive');
  perform pg_temp.assert(m like 'Club Raptor is closed for now%', 'activity refused: ' || m);
  perform pg_temp.cs_hint($q$ select shop_buy('star_beer', 1) $q$, 'inactive');
  perform pg_temp.cs_hint($q$ select spray_custom('club_raptor', 5000) $q$, 'inactive');
  perform pg_temp.cs_hint($q$ select event_buy_ticket('cs_test_night') $q$, 'inactive');
  perform pg_temp.assert((select cash from profiles where id = a) = c0, 'nothing charged');
  perform pg_temp.assert(not (place_interior('club_raptor')->>'open')::boolean
                         and place_interior('club_raptor')->>'opens' = 'Closed for now', 'place card says Closed for now');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(events_on_today()) e where e->>'location_id' = 'club_raptor'), 'no banner for a switched-off club');
  -- the club is the only thing that closed: another club still works
  update profiles set location_id = 'patricia_nightlife' where id = a;
  perform do_activity('club_dance');
  -- RLS: a switched-off club is still readable by players (pin shows "Closed for now"); other hidden places are not
  set local role authenticated;
  perform pg_temp.assert(exists (select 1 from locations where id = 'club_raptor' and not active), 'off club readable by players');
  perform pg_temp.assert(not exists (select 1 from locations where scene <> 'club' and not active and private_home_owner_id is null), 'other hidden places stay hidden');
  reset role;
  raise notice 'ok 2: switch off audits, moves idle players, refuses travel/activity/shop/spray/ticket, hides events';
end $$;

-- ---------- 3. busy player cleared by the existing closed-hours logic ----------
do $$
declare b uuid := pg_temp.cs('bayo'); r jsonb; home text;
begin
  perform pg_temp.login(b);
  select home_location_id into home from profiles where id = b;
  r := place_closed_eject();
  perform pg_temp.assert(not (r->>'ejected')::boolean and r->>'reason' = 'busy', 'still busy: not ejected yet');
  update profiles set busy_until = null where id = b;
  r := place_closed_eject();
  perform pg_temp.assert((r->>'ejected')::boolean and (r->>'off')::boolean, 'ejected once free, flagged off: ' || r::text);
  perform pg_temp.assert((select location_id from profiles where id = b) = home, 'sent home');
  perform pg_temp.assert((select body from events where user_id = b and kind = 'place_closed' order by id desc limit 1) like '%closed for now%Check back soon.', 'wording: closed for now');
  -- a normal closed-hours eject keeps the old wording
  perform pg_temp.cs_at_hour(13);
  update profiles set location_id = 'patricia_nightlife' where id = b;
  r := place_closed_eject();
  perform pg_temp.assert((r->>'ejected')::boolean and not (r->>'off')::boolean and r->>'opens' = '10 PM', 'hours eject unchanged: ' || r::text);
  perform pg_temp.assert((select body from events where user_id = b and kind = 'place_closed' order by id desc limit 1) like '%It opens again at 10 PM.', 'hours wording kept');
  raise notice 'ok 3: place_closed_eject wording';
end $$;

-- ---------- 4. switch ON again ----------
do $$
declare a uuid := pg_temp.cs('ada'); adm uuid := pg_temp.cs('adm'); m text;
begin
  perform pg_temp.cs_at_hour(23);
  perform pg_temp.login(adm);
  perform pg_temp.assert((admin_club_set('club_raptor', true)->>'changed')::boolean, 'on: changed');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'club_switch' and (data->>'on')::boolean), 'on is audited too');
  perform pg_temp.login(a);
  perform pg_temp.assert(travel_quote('club_raptor')->>'dest' = 'club_raptor', 'travel works again');
  update profiles set location_id = 'club_raptor', busy_until = null where id = a;
  perform do_activity('club_dance');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(events_on_today()) e where e->>'location_id' = 'club_raptor'), 'event banner back');
  perform pg_temp.assert((place_interior('club_raptor')->>'open')::boolean, 'place card open');
  raise notice 'ok 4: switch on restores everything';
end $$;

-- ---------- 5. guards ----------
do $$
declare a uuid := pg_temp.cs('ada'); adm uuid := pg_temp.cs('adm'); ok boolean;
begin
  perform pg_temp.login(a);
  ok := false; begin perform admin_club_set('club_raptor', false); exception when others then ok := true; end;
  perform pg_temp.assert(ok, 'player can''t switch a club');
  ok := false; begin perform admin_club_list(); exception when others then ok := true; end;
  perform pg_temp.assert(ok, 'player can''t list clubs for admin');
  perform pg_temp.assert((select active from locations where id = 'club_raptor'), 'unchanged');
  perform pg_temp.login(adm);
  perform pg_temp.cs_hint($q$ select admin_club_set('mama_ebo', false) $q$, 'no_club');
  perform pg_temp.cs_hint($q$ select admin_club_set('nope', false) $q$, 'no_club');
  perform pg_temp.assert((select active from locations where id = 'mama_ebo'), 'non-club not switched');
  -- grants: anon can't run them, private helpers untouched
  perform pg_temp.assert(not has_function_privilege('anon', 'public.admin_club_set(text, boolean)', 'execute'), 'anon revoked');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.admin_club_set(text, boolean)', 'execute'), 'authenticated granted');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_place_open(public.locations)', 'execute'), 'bl_place_open still private');
  raise notice 'ok 5: guards';
end $$;
