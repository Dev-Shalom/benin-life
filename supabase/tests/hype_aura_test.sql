-- P3 hype with aura (20261006001900_hype_aura.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/hype_aura_test.sql
-- Groups: 1 at least 15 active lines per kind, every line names the player, bottles lines count, every ticker
-- has name + place · 2 no repeats per place until the pool cycles (and no back-to-back repeat at the cycle
-- edge), other places have their own cycle · 3 variables fill ({name} {place} {count} {bottles} {amount}),
-- place column set · 4 the recent table is server-only, the announcer stays server-only · 5 inactive lines skipped.

create temp table t_ha (name text primary key, id uuid not null) on commit drop;
create or replace function pg_temp.ha(p_name text) returns uuid
language sql as $$ select id from t_ha where name = p_name $$;

do $$
declare v uuid;
begin
  v := pg_temp.new_user('ha_nosa@hype.bl');
  insert into t_ha values ('Ha_Nosa', v);
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2('Ha_Nosa', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set location_id = 'club_360' where id = v;
  update game_config set value = 'true' where key = 'hype.enabled';
  update game_config set value = '0' where key = 'hype.cooldown_s';
  update game_config set value = '999999999999' where key = 'hype.global_min';
  delete from place_announcements;
  delete from hype_template_recent;
end $$;

-- ---------- 1. the pool ----------
do $$
declare r record;
begin
  for r in select k from unnest(array['vip', 'bottles', 'spray', 'shoutout', 'shutdown']) k loop
    perform pg_temp.assert((select count(*) from hype_templates where kind = r.k and active) >= 15,
      r.k || ' has >= 15 active lines: ' || (select count(*) from hype_templates where kind = r.k and active));
  end loop;
  perform pg_temp.assert(not exists (select 1 from hype_templates where active and line not like '%{name}%'), 'every line names the player');
  perform pg_temp.assert(not exists (select 1 from hype_templates where kind = 'bottles' and line not like '%{bottles}%'), 'every bottles line counts');
  perform pg_temp.assert(not exists (select 1 from hype_templates where ticker <> '' and (ticker not like '%{name}%' or ticker not like '%{place}%')), 'tickers have name + place');
  perform pg_temp.assert(not exists (select 1 from hype_templates where char_length(ticker) > 60), 'tickers are short');
  raise notice 'ok 1: >= 15 lines per kind';
end $$;

-- ---------- 2. no repeats until the pool cycles ----------
do $$
declare a uuid := pg_temp.ha('Ha_Nosa'); pool int; i int; seen text[] := '{}'; j jsonb; last text; cur text; distinct_n int;
begin
  select count(*) into pool from hype_templates where kind = 'vip' and active;
  -- first full cycle: every line exactly once
  for i in 1..pool loop
    j := bl_hype_announce(a, 'club_360', 'vip', 150000, 1, true);
    perform pg_temp.assert(j is not null, 'announced #' || i);
    cur := (select template_id from hype_template_recent where location_id = 'club_360' and kind = 'vip' order by used_at desc limit 1);
    perform pg_temp.assert(not (cur = any(seen)), 'no repeat inside the cycle (#' || i || ' ' || cur || ')');
    seen := seen || cur;
  end loop;
  select count(distinct t) into distinct_n from unnest(seen) t;
  perform pg_temp.assert(distinct_n = pool, 'the whole pool was used: ' || distinct_n || '/' || pool);
  perform pg_temp.assert((select count(distinct text) from place_announcements where kind = 'vip') = pool, 'distinct texts = pool');
  last := cur;
  -- next one starts a new cycle, never the line just heard
  for i in 1..10 loop
    j := bl_hype_announce(a, 'club_360', 'vip', 150000, 1, true);
    cur := (select template_id from hype_template_recent where location_id = 'club_360' and kind = 'vip' order by used_at desc limit 1);
    perform pg_temp.assert(i > 1 or cur <> last, 'no back-to-back repeat at the cycle edge');
  end loop;
  perform pg_temp.assert((select count(*) from hype_template_recent where location_id = 'club_360' and kind = 'vip') = 10, 'second cycle tracked (10 used)');
  -- other kinds and other places have their own cycles
  perform pg_temp.assert((select count(*) from hype_template_recent where location_id = 'club_360' and kind = 'spray') = 0, 'spray cycle untouched');
  if exists (select 1 from locations where scene = 'club' and id <> 'club_360') then
    update locations set active = true where id = (select id from locations where scene = 'club' and id <> 'club_360' order by id limit 1);
    perform bl_hype_announce(a, (select id from locations where scene = 'club' and id <> 'club_360' order by id limit 1), 'vip', 150000, 1, true);
    perform pg_temp.assert((select count(*) from hype_template_recent where location_id = 'club_360' and kind = 'vip') = 10, 'another club does not touch 360''s cycle');
  end if;
  raise notice 'ok 2: no repeats over % announcements, then a new cycle', pool;
end $$;

-- ---------- 3. variables fill ----------
do $$
declare a uuid := pg_temp.ha('Ha_Nosa'); pa place_announcements; r record;
begin
  delete from place_announcements;
  for r in select k from unnest(array['vip', 'bottles', 'spray', 'shoutout', 'shutdown']) k loop
    for i in 1..20 loop
      perform bl_hype_announce(a, 'club_360', r.k, 2500000, 3, true);
    end loop;
  end loop;
  perform pg_temp.assert(not exists (select 1 from place_announcements where text ~ '\{(name|place|count|bottles|amount)\}'), 'no placeholder left');
  perform pg_temp.assert(not exists (select 1 from place_announcements where text not like '%Ha_Nosa%'), 'every line names the player');
  perform pg_temp.assert(not exists (select 1 from place_announcements where kind = 'bottles' and text not like '%3 bottles%'), 'bottles lines say 3 bottles');
  perform pg_temp.assert(exists (select 1 from place_announcements where kind = 'spray' and text like '%' || bl_naira(2500000) || '%'), 'amount fills: ' || bl_naira(2500000));
  perform pg_temp.assert(exists (select 1 from place_announcements where text like '%360 Signature%'), 'place fills');
  perform pg_temp.assert(not exists (select 1 from place_announcements where place is distinct from '360 Signature'), 'place column = display name');
  -- the ticker fills too when it goes app-wide
  update game_config set value = '500000' where key = 'hype.global_min';
  update game_config set value = '0' where key = 'hype.global_cooldown_s';
  pa := jsonb_populate_record(null::place_announcements, bl_hype_announce(a, 'club_360', 'shutdown', 2500000, 1, true));
  perform pg_temp.assert(pa.global and pa.ticker like '%@Ha_Nosa%' and pa.ticker like '%360 Signature%' and pa.ticker !~ '\{', 'ticker fills: ' || coalesce(pa.ticker, 'null'));
  raise notice 'ok 3: variables fill (e.g. %)', pa.text;
end $$;

-- ---------- 4. server-only ----------
do $$
declare ok boolean := false;
begin
  perform pg_temp.login(pg_temp.ha('Ha_Nosa'));
  set local role authenticated;
  begin
    perform 1 from hype_template_recent limit 1;
  exception when insufficient_privilege then ok := true;
  end;
  reset role;
  perform pg_temp.assert(ok, 'clients cannot read the recent table');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_hype_announce(uuid,text,text,bigint,int,boolean)', 'execute'), 'announcer not executable by clients');
  perform pg_temp.assert(has_function_privilege('service_role', 'public.bl_hype_announce(uuid,text,text,bigint,int,boolean)', 'execute'), 'grants kept for service_role');
  raise notice 'ok 4: server-only';
end $$;

-- ---------- 5. inactive lines are skipped ----------
do $$
declare a uuid := pg_temp.ha('Ha_Nosa'); i int;
begin
  update hype_templates set active = false where kind = 'shoutout' and id <> 'shoutout.3';
  delete from hype_template_recent;
  for i in 1..4 loop
    perform bl_hype_announce(a, 'club_360', 'shoutout', 100000, 1, true);
    perform pg_temp.assert((select template_id from hype_template_recent where kind = 'shoutout' order by used_at desc limit 1) = 'shoutout.3',
      'only the active line is used (pool of one cycles on itself)');
  end loop;
  raise notice 'ok 5: inactive lines skipped';
end $$;
