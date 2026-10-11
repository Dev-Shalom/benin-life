-- P2 club hype (20261006001700_hype.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/hype_test.sql
-- Groups: 1 a club spend announces with the MC's text · 2 clients can't write announcements · 3 per-player
-- cooldown · 4 app-wide flag at / above hype.global_min (+ global cooldown) · 5 Shut down the club charges,
-- gives cred, buys a round and always announces · 6 bottles count up · 7 non-club spends don't announce ·
-- 8 publication + admin spec.

create or replace function pg_temp.hy_at_hour(p_hour int) returns void
language plpgsql as $$
declare c jsonb; cur numeric; delta numeric;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  c := bl_game_clock();
  cur := (c->>'hour')::numeric * 3600 + (c->>'minute')::numeric * 60;
  delta := ((p_hour * 3600 + 1800 - cur)::numeric % 86400 + 86400) % 86400;
  perform set_config('bl.test_offset_seconds', delta::text, true);
end $$;

create temp table t_hy (name text primary key, id uuid not null) on commit drop;
grant select on t_hy to authenticated;
create or replace function pg_temp.hy(p_name text) returns uuid
language sql as $$ select id from t_hy where name = p_name $$;

create or replace function pg_temp.hy_make(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@hype.bl');
begin
  insert into t_hy values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, location_id = 'club_360', cash = 10000000, busy_until = null where id = v;
  return v;
end $$;

-- does `txt` match one of the active templates of `kind` rendered for this player / place / count?
create or replace function pg_temp.hy_rendered(p_kind text, p_name text, p_count int, p_amount bigint, p_txt text) returns boolean
language sql as $$
  select exists (
    select 1 from hype_templates t where t.kind = p_kind and t.active
       and replace(replace(replace(replace(replace(t.line, '{name}', p_name), '{place}', '360 Signature'), '{count}', p_count::text),
             '{bottles}', p_count || case when p_count = 1 then ' bottle' else ' bottles' end), '{amount}', bl_naira(p_amount)) = p_txt)
$$;

do $$
begin
  perform pg_temp.hy_make('Hy_Nosa');
  perform pg_temp.hy_make('Hy_Ada');
  perform pg_temp.hy_make('Hy_Efe');
  -- known settings for the test
  update game_config set value = '30' where key = 'hype.cooldown_s';
  update game_config set value = '500000' where key = 'hype.global_min';
  update game_config set value = '90' where key = 'hype.global_cooldown_s';
  update game_config set value = 'true' where key = 'hype.enabled';
  update game_config set value = 'true' where key = 'places.hours_enabled';
  update locations set active = true where id = 'club_360';
  delete from place_announcements;
  perform pg_temp.hy_at_hour(23);
  perform set_config('bl.test_rand', '0.999', true); -- no robberies on spray money
end $$;

-- ---------- 1. a club spend announces ----------
do $$
declare a uuid := pg_temp.hy('Hy_Nosa'); r jsonb; pa place_announcements;
begin
  perform pg_temp.login(a);
  r := do_activity('vip_table');
  select * into pa from place_announcements where user_id = a order by id desc limit 1;
  perform pg_temp.assert(pa.id is not null, 'VIP table announced');
  perform pg_temp.assert(pa.location_id = 'club_360' and pa.kind = 'vip' and pa.amount = 150000 and pa.username = 'Hy_Nosa', 'row fields: ' || to_jsonb(pa)::text);
  perform pg_temp.assert(pa.text like '%Hy_Nosa%', 'text has the name: ' || pa.text);
  perform pg_temp.assert(pg_temp.hy_rendered('vip', 'Hy_Nosa', 1, 150000, pa.text), 'text is a rendered vip template: ' || pa.text);
  perform pg_temp.assert(not pa.global and pa.ticker is null, '150k is below the app-wide threshold');
  perform pg_temp.assert((r->'hype'->>'id')::bigint = pa.id, 'do_activity returns the announcement');
  raise notice 'ok 1: club spend announces (%)', pa.text;
end $$;

-- ---------- 2. clients can't write ----------
do $$
declare a uuid := pg_temp.hy('Hy_Nosa'); ok boolean := false; n int;
begin
  perform pg_temp.login(a);
  set local role authenticated;
  begin
    insert into place_announcements (location_id, user_id, username, kind, text) values ('club_360', a, 'Hy_Nosa', 'vip', 'fake!');
  exception when insufficient_privilege then ok := true;
  end;
  perform pg_temp.assert(ok, 'client insert refused');
  ok := false;
  begin
    update place_announcements set text = 'edited';
  exception when insufficient_privilege then ok := true;
  end;
  perform pg_temp.assert(ok, 'client update refused');
  ok := false;
  begin
    perform bl_hype_announce(a, 'club_360', 'shutdown', 9999999, 1, true);
  exception when insufficient_privilege then ok := true;
  end;
  perform pg_temp.assert(ok, 'client cannot call the announcer');
  -- but players can read them
  select count(*) into n from place_announcements;
  perform pg_temp.assert(n >= 1, 'authenticated can read announcements');
  reset role;
  raise notice 'ok 2: clients cannot write announcements';
end $$;

-- ---------- 3. per-player cooldown ----------
do $$
declare a uuid := pg_temp.hy('Hy_Nosa'); n0 int; n1 int;
begin
  perform pg_temp.login(a);
  select count(*) into n0 from place_announcements where user_id = a;
  update profiles set busy_until = null where id = a;
  perform do_activity('hype_shoutout');
  select count(*) into n1 from place_announcements where user_id = a;
  perform pg_temp.assert(n1 = n0, 'second spend within the cooldown: no new announcement');
  perform pg_temp.assert((select cash from profiles where id = a) = 10000000 - 150000 - 100000, 'the spend itself still went through');
  -- cooldown off: announces again
  update game_config set value = '0' where key = 'hype.cooldown_s';
  update profiles set busy_until = null where id = a;
  perform do_activity('hype_shoutout');
  perform pg_temp.assert((select count(*) from place_announcements where user_id = a) = n0 + 1, 'cooldown 0: announced');
  perform pg_temp.assert((select kind from place_announcements where user_id = a order by id desc limit 1) = 'shoutout', 'shout-out kind');
  update game_config set value = '30' where key = 'hype.cooldown_s';
  -- another player isn't blocked by Nosa's cooldown
  perform pg_temp.login(pg_temp.hy('Hy_Ada'));
  perform do_activity('spray_money');
  perform pg_temp.assert(exists (select 1 from place_announcements where user_id = pg_temp.hy('Hy_Ada') and kind = 'spray'), 'Ada announces');
  raise notice 'ok 3: per-player cooldown';
end $$;

-- ---------- 4. app-wide flag ----------
do $$
declare e uuid := pg_temp.hy('Hy_Efe'); pa place_announcements;
begin
  perform pg_temp.login(e);
  -- exactly at the threshold: spray money set to 500k (the threshold is inclusive)
  update activities set cost = 500000 where id = 'spray_money';
  perform do_activity('spray_money');
  select * into pa from place_announcements where user_id = e order by id desc limit 1;
  perform pg_temp.assert(pa.global and pa.ticker like '%@Hy_Efe%' and pa.ticker like '%360 Signature%', 'at threshold: global with ticker ' || coalesce(pa.ticker, 'null'));
  -- below the threshold: local only
  update game_config set value = '0' where key = 'hype.cooldown_s';
  update game_config set value = '0' where key = 'hype.global_cooldown_s';
  update activities set cost = 499999 where id = 'spray_money';
  update profiles set busy_until = null where id = e;
  perform do_activity('spray_money');
  select * into pa from place_announcements where user_id = e order by id desc limit 1;
  perform pg_temp.assert(not pa.global and pa.ticker is null, 'below threshold: local only');
  -- global cooldown: a second big spend inside it stays local
  update game_config set value = '90' where key = 'hype.global_cooldown_s';
  update activities set cost = 600000 where id = 'spray_money';
  update profiles set busy_until = null where id = e;
  perform do_activity('spray_money');
  select * into pa from place_announcements where user_id = e order by id desc limit 1;
  perform pg_temp.assert(not pa.global, 'global ticker cooldown keeps the second big spend local');
  update activities set cost = 50000 where id = 'spray_money';
  update game_config set value = '30' where key = 'hype.cooldown_s';
  raise notice 'ok 4: app-wide flag at/above hype.global_min, global cooldown';
end $$;

-- ---------- 5. Shut down the club ----------
do $$
declare a uuid := pg_temp.hy('Hy_Ada'); n uuid := pg_temp.hy('Hy_Nosa'); r jsonb; pa place_announcements; c0 bigint; cred0 int; fun0 numeric;
begin
  update game_config set value = '0' where key = 'hype.global_cooldown_s';
  perform pg_temp.assert((select cost from activities where id = 'shut_down_club') = 2000000, 'default price 2M on the card');
  perform pg_temp.assert(exists (select 1 from zone_actions where zone_id = 'club.dj' and ref = 'shut_down_club' and active), 'card in the DJ zone');
  -- admin changes the price: the card follows
  update game_config set value = '2500000' where key = 'hype.shutdown_cost';
  perform pg_temp.assert((select cost from activities where id = 'shut_down_club') = 2500000, 'card price follows hype.shutdown_cost');
  update profiles set fun = 20, needs_updated_at = bl_now() where id = n;
  fun0 := (select fun from profiles where id = n);
  perform pg_temp.login(a);
  update profiles set busy_until = null where id = a;
  c0 := (select cash from profiles where id = a);
  cred0 := (select street_cred from profiles where id = a);
  -- Ada is inside her cooldown (spray money in 3) but Shut down the club always announces
  r := do_activity('shut_down_club');
  perform pg_temp.assert((select cash from profiles where id = a) = c0 - 2500000, 'charged 2.5M');
  perform pg_temp.assert((select street_cred from profiles where id = a) = cred0 + 25, 'big street cred');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and delta = -2500000 and meta->>'activity' = 'shut_down_club'), 'ledger row');
  select * into pa from place_announcements where user_id = a order by id desc limit 1;
  perform pg_temp.assert(pa.kind = 'shutdown' and pa.amount = 2500000 and pa.global, 'shutdown announced app-wide: ' || to_jsonb(pa)::text);
  perform pg_temp.assert(pg_temp.hy_rendered('shutdown', 'Hy_Ada', 1, 2500000, pa.text), 'shutdown text: ' || pa.text);
  perform pg_temp.assert((select fun from profiles where id = n) >= fun0 + 9, 'round for the others in the club');
  perform pg_temp.assert(r->>'message' like '%drinks on you%', 'message mentions the round: ' || (r->>'message'));
  update game_config set value = '2000000' where key = 'hype.shutdown_cost';
  update game_config set value = '90' where key = 'hype.global_cooldown_s';
  raise notice 'ok 5: Shut down the club charges, rewards, buys a round, announces';
end $$;

-- ---------- 6. bottles count up ----------
do $$
declare e uuid := pg_temp.hy('Hy_Efe'); pa place_announcements;
begin
  perform pg_temp.login(e);
  update game_config set value = '0' where key = 'hype.cooldown_s';
  update profiles set busy_until = null where id = e;
  perform shop_buy('club_bottle', 1);
  select * into pa from place_announcements where user_id = e order by id desc limit 1;
  perform pg_temp.assert(pa.kind = 'bottles' and pa.qty = 1 and pa.text like '%1 bottle%', 'first bottle: ' || pa.text);
  perform shop_buy('club_bottle', 2);
  select * into pa from place_announcements where user_id = e order by id desc limit 1;
  perform pg_temp.assert(pa.qty = 3 and pa.text like '%3 bottles%', 'bottles count up in the window: ' || pa.text);
  perform pg_temp.assert(pa.amount = 3 * (select price from items where id = 'club_bottle'), 'amount = the window total');
  update game_config set value = '30' where key = 'hype.cooldown_s';
  raise notice 'ok 6: bottles count up (%)', pa.text;
end $$;

-- ---------- 7. non-club spends don't announce ----------
do $$
declare a uuid := pg_temp.hy('Hy_Nosa'); n0 int;
begin
  perform pg_temp.login(a);
  update game_config set value = '0' where key = 'hype.cooldown_s';
  n0 := (select count(*) from place_announcements);
  update profiles set location_id = 'club_360', busy_until = null where id = a;
  perform do_activity('club_dance');                 -- a free club activity: no announcement
  update profiles set busy_until = null where id = a;
  perform shop_buy('star_beer', 1);                  -- a club drink that isn't a bottle
  update profiles set location_id = 'mama_ebo', busy_until = null, hunger = 20 where id = a;
  perform set_config('bl.test_rand', '0.999', true);
  perform do_activity('owo_soup');                   -- a buka spend
  perform pg_temp.assert((select count(*) from place_announcements) = n0, 'no announcements outside club spends');
  -- the announcer itself ignores non-club places
  perform pg_temp.assert(bl_hype_announce(a, 'mama_ebo', 'vip', 999999, 1, true) is null, 'announcer ignores a buka');
  -- switched off: nothing
  update profiles set location_id = 'club_360', busy_until = null where id = a;
  update game_config set value = 'false' where key = 'hype.enabled';
  perform do_activity('hype_shoutout');
  perform pg_temp.assert((select count(*) from place_announcements) = n0, 'hype.enabled off: silent');
  update game_config set value = 'true' where key = 'hype.enabled';
  update game_config set value = '30' where key = 'hype.cooldown_s';
  raise notice 'ok 7: non-club spends do not announce';
end $$;

-- ---------- 8. publication + admin ----------
do $$
begin
  perform pg_temp.assert(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'place_announcements'), 'in supabase_realtime');
  perform pg_temp.assert(bl_admin_table_spec('hype_templates') is not null, 'admin can edit hype lines');
  perform pg_temp.assert(bl_admin_table_spec('crowd_profiles') is not null and bl_admin_table_spec('items') is not null, 'earlier specs kept');
  perform pg_temp.assert((select count(*) from game_config where key like 'hype.%') >= 9 and exists (select 1 from game_config where key = 'music.club_track_url' and value = '""'), 'config keys');
  raise notice 'ok 8: publication + admin spec + config';
end $$;
