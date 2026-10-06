-- L3 crowds (20261006001500_crowds.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/crowds_test.sql
-- Groups: 1 roster seeded for every place type · 2 profiles cover every hour of every day for every place type
-- · 3 place_people is deterministic, capped, follows the rhythm (market morning, club night, 3 AM street, closed = empty)
-- · 4 admin can edit both tables (audited), players can't.

create temp table t_cr (name text primary key, id uuid not null) on commit drop;
grant select on t_cr to authenticated;
create or replace function pg_temp.cr(p_name text) returns uuid
language sql as $$ select id from t_cr where name = p_name $$;

do $$
declare v uuid := pg_temp.new_user('cr_ada@crowd.bl'); adm uuid := pg_temp.new_user('cr_adm@crowd.bl');
begin
  insert into t_cr values ('ada', v), ('adm', adm);
  perform pg_temp.login(v);
  perform create_profile_v2('Cr_Ada', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  perform pg_temp.login(adm);
  perform create_profile_v2('Cr_Adm', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set is_admin = true where id = adm;
end $$;

-- ---------- 1. roster ----------
do $$
declare v_missing text; n int;
begin
  select count(*) into n from npc_roster where active;
  perform pg_temp.assert(n between 80 and 240, format('roster has ~80-200 people (got %s; P1 added more)', n));
  -- every non-home place type has people, and every place has at least one candidate
  select string_agg(distinct l.scene, ', ') into v_missing from locations l
   where l.scene not like 'home%'
     and not exists (select 1 from npc_roster r where r.active
                      and (l.id = any(r.location_ids) or (cardinality(r.location_ids) = 0 and l.scene = any(r.scenes))));
  perform pg_temp.assert(v_missing is null, 'every place type has roster people, missing: ' || coalesce(v_missing, ''));
  perform pg_temp.assert(exists (select 1 from npc_roster where name = 'MC Lightning' and 'club_360' = any(location_ids)
                                 and motion = 'hype' and headliner), 'MC Lightning hypes at 360 Signature');
  perform pg_temp.assert((select count(*) from npc_roster where 'club_360' = any(location_ids) and motion = 'dj') = 1, 'one DJ at 360');
  perform pg_temp.assert(exists (select 1 from npc_roster where role = 'Bouncer'), 'bouncers seeded');
  perform pg_temp.assert(not exists (select 1 from npc_roster where pidgin <> '' and not (scenes && '{market,street,motorpark,pos}')),
                         'Pidgin lines only for street / market people');
  perform pg_temp.assert(not exists (select 1 from npc_roster where bl_lines(lines) = '{}'), 'everyone has an English line');
  perform pg_temp.assert(not exists (select 1 from npc_roster where avatar->>'gender' not in ('male', 'female')), 'avatar presets have a gender');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.npc_roster', 'insert')
                         and not has_table_privilege('authenticated', 'public.crowd_profiles', 'update')
                         and not has_table_privilege('anon', 'public.npc_roster', 'select'), 'catalog read-only for clients');
  raise notice 'ok 1: roster';
end $$;

-- ---------- 2. profiles ----------
do $$
declare v_gap text;
begin
  select string_agg(format('%s wd%s %sh', s.scene, wd, h), ', ') into v_gap
  from (select distinct scene from locations where scene not like 'home%') s, generate_series(0, 6) wd, generate_series(0, 23) h
  where bl_crowd_count(s.scene, h, wd) is null;
  perform pg_temp.assert(v_gap is null, 'profiles cover every hour: gaps ' || left(coalesce(v_gap, ''), 300));
  -- real Benin rhythms
  perform pg_temp.assert(bl_crowd_count('market', 9, 1) > 3 * bl_crowd_count('market', 20, 1), 'market busy in the morning');
  perform pg_temp.assert(bl_crowd_count('campus', 10, 2) > 2 * bl_crowd_count('campus', 10, 6), 'campus busy on weekdays');
  perform pg_temp.assert(bl_crowd_count('club', 23, 1) > 5 * bl_crowd_count('club', 15, 1), 'clubs at night');
  perform pg_temp.assert(bl_crowd_count('club', 23, 5) > bl_crowd_count('club', 23, 1), 'clubs busier on weekends');
  perform pg_temp.assert(bl_crowd_count('street', 3, 1) <= 1, 'streets nearly empty at 3 AM');
  raise notice 'ok 2: profiles';
end $$;

-- ---------- 3. place_people ----------
do $$
declare a jsonb; b jsonb; c jsonb; n int;
begin
  perform pg_temp.login(pg_temp.cr('ada'));
  a := place_people('oba_market', 9, 1);
  b := place_people('oba_market', 9, 1);
  perform pg_temp.assert(a = b, 'same people for the same place x hour');
  perform pg_temp.assert((a->>'total')::int >= jsonb_array_length(a->'npcs') and jsonb_array_length(a->'npcs') >= 5, 'busy morning market');
  perform pg_temp.assert((a->'npcs'->0->>'line') is not null and (a->'npcs'->0->'avatar'->>'gender') is not null, 'each person has a line and a look');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(a->'npcs') e, jsonb_array_elements_text(e->'lines') l
                                 where l like '%dey%' or l like '%abeg%' or l like '%Abeg%' or l like '%o.%'), 'Pidgin at the market');
  c := place_people('oba_market', 3, 1);
  perform pg_temp.assert(jsonb_array_length(c->'npcs') = 0 and (c->>'total')::int = 0, 'market empty at 3 AM');
  -- cap
  update game_config set value = '3' where key = 'crowd.npc_list_max';
  a := place_people('oba_market', 9, 1);
  perform pg_temp.assert(jsonb_array_length(a->'npcs') = 3 and (a->>'total')::int > 3, 'list capped by crowd.npc_list_max, total still counts everyone');
  update game_config set value = '30' where key = 'crowd.npc_list_max';
  -- 360 Signature at night: MC Lightning + DJ first (headliners), closed in the afternoon
  a := place_people('club_360', 23, 5);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(a->'npcs') e where e->>'name' = 'MC Lightning'), 'MC Lightning at 360 at night');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(a->'npcs') e where e->>'name' = 'DJ Ekpen'), 'the DJ at 360 at night');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(a->'npcs') e where e->>'name' = 'DJ Uyi'), 'other clubs'' DJ not at 360');
  select count(*) into n from jsonb_array_elements(a->'npcs') e where e->>'motion' = 'dance';
  perform pg_temp.assert(n >= 4, 'dancers at 360');
  a := place_people('club_360', 15, 1);
  perform pg_temp.assert(not (a->>'open')::boolean and jsonb_array_length(a->'npcs') = 0, 'closed club is empty');
  -- hidden club (soft launch) is empty even at night
  if exists (select 1 from locations where id = 'rome_club' and not active) then
    perform pg_temp.assert(jsonb_array_length(place_people('rome_club', 23, 5)->'npcs') = 0, 'hidden club empty');
  end if;
  -- homes have no background people
  perform pg_temp.assert(jsonb_array_length(place_people('ekenwan_room', 12, 1)->'npcs') = 0, 'no NPCs at homes');
  -- seeded per hour: a different hour may change who is there, but it is still deterministic
  perform pg_temp.assert(place_people('uniben', 10, 2) = place_people('uniben', 10, 2), 'campus deterministic');
  -- no args = now
  a := place_people('oba_market');
  perform pg_temp.assert(a ? 'npcs' and a ? 'total', 'works with the real clock');
  raise notice 'ok 3: place_people';
end $$;

-- bad input
do $$
begin
  perform pg_temp.login(pg_temp.cr('ada'));
  begin
    perform place_people('oba_market', 25, 1);
    raise exception 'TEST FAILED: hour 25 accepted';
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
  end;
  begin
    perform place_people('nowhere');
    raise exception 'TEST FAILED: unknown place accepted';
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
  end;
  raise notice 'ok 3b: bad input refused';
end $$;

-- anon can't call it
do $$
begin
  perform pg_temp.assert(not has_function_privilege('anon', 'public.place_people(text, int, int)', 'execute'), 'anon cannot call place_people');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_crowd_count(text, int, int)', 'execute'), 'helper revoked');
end $$;

-- ---------- 4. admin ----------
do $$
declare r jsonb; ok boolean;
begin
  perform pg_temp.login(pg_temp.cr('adm'));
  r := admin_row_upsert('npc_roster', '{"id": "mc_lightning", "lines": "Benin City, make some noise!"}');
  perform pg_temp.assert((select lines from npc_roster where id = 'mc_lightning') = 'Benin City, make some noise!', 'admin edits a line');
  r := admin_row_upsert('npc_roster', '{"id": "test_npc", "name": "Test Osas", "role": "Trader", "motion": "trade",
        "avatar": {"v": 2, "gender": "male", "preset": "ankara"}, "lines": "Hello", "pidgin": "", "scenes": ["market"],
        "location_ids": [], "zone_key": null, "headliner": false, "sort": 999, "active": true}');
  perform pg_temp.assert(exists (select 1 from npc_roster where id = 'test_npc'), 'admin adds a person');
  r := admin_row_upsert('crowd_profiles', '{"id": "market.all.7-12", "npcs": 80}');
  perform pg_temp.assert(bl_crowd_count('market', 9, 1) = 80, 'admin retunes a profile');
  perform pg_temp.assert(exists (select 1 from admin_audit where data::text like '%crowd_profiles%' or action like '%crowd_profiles%'), 'audited');
  -- bad values refused
  ok := false;
  begin
    r := admin_row_upsert('npc_roster', '{"id": "test_npc", "motion": "fly"}');
  exception when others then ok := true;
  end;
  perform pg_temp.assert(ok, 'unknown motion refused');
  ok := false;
  begin
    r := admin_row_upsert('crowd_profiles', '{"id": "market.all.7-12", "from_hour": 13}');
  exception when others then ok := true;
  end;
  perform pg_temp.assert(ok, 'band with from >= to refused');
  -- players can't
  perform pg_temp.login(pg_temp.cr('ada'));
  ok := false;
  begin
    r := admin_row_upsert('npc_roster', '{"id": "mc_lightning", "lines": "hacked"}');
  exception when others then ok := true;
  end;
  perform pg_temp.assert(ok and (select lines from npc_roster where id = 'mc_lightning') <> 'hacked', 'players cannot edit the roster');
  ok := false;
  begin
    r := admin_row_upsert('crowd_profiles', '{"id": "market.all.7-12", "npcs": 1}');
  exception when others then ok := true;
  end;
  perform pg_temp.assert(ok, 'players cannot edit profiles');
  raise notice 'ok 4: admin';
end $$;
