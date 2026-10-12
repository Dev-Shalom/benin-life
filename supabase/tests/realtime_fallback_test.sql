-- F1 Realtime fallback (20261012001000_realtime_fallback.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/realtime_fallback_test.sql
-- Groups: 1 config switch · 2 outsiders can't post/read a house · 3 host + admitted guest see each other (+ players_here_ids) ·
-- 4 avatars only on request, path kept · 5 leaving marks the row left and hides it · 6 RLS reads (members only,
-- no client writes) · 7 grants
do $$
begin
  perform pg_temp.assert((select value #>> '{}' from game_config where key = 'realtime.mode') = 'auto', 'realtime.mode defaults to auto');
  perform pg_temp.assert((select kind from game_config where key = 'realtime.mode') = 'text', 'realtime.mode is a text setting');
  raise notice 'ok: realtime.mode config';
end $$;

do $$
declare h uuid := pg_temp.new_user('rf_host@rt.bl'); g uuid := pg_temp.new_user('rf_guest@rt.bl');
        o uuid := pg_temp.new_user('rf_out@rt.bl');
        inv jsonb; r jsonb; m text; v_home text;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(h);
  perform create_profile_v2('Rf_Host', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(g);
  perform create_profile_v2('Rf_Guest', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(o);
  perform create_profile_v2('Rf_Out', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  select location_id into v_home from profiles where id = h;
  perform pg_temp.assert((select private_home_owner_id from locations where id = v_home) = h, 'host is at their private home');

  -- 2. the guest is not in the host's house yet: can't post there, state is about their own home only
  perform pg_temp.login(h);
  r := house_room_move(1.5, 2.0, 0.5, false, null, null, null);
  perform pg_temp.assert(r->>'ok' = 'true', 'host posts at home');
  perform pg_temp.login(g);
  r := house_room_state(true);
  perform pg_temp.assert(r->>'location' <> v_home, 'guest reads only the home they are in');
  perform pg_temp.assert(jsonb_array_length(r->'members') = 0, 'guest sees nobody in their own empty home');
  -- an outsider parked on the host's home location (no admission) is refused
  update profiles set location_id = v_home where id = o;
  perform pg_temp.login(o);
  begin perform house_room_state(false); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%not inside a home%', 'outsider cannot read the house: ' || coalesce(m, 'none'));
  begin perform house_room_move(1, 1, 0, false, null, null, null); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%not inside a home%', 'outsider cannot post in the house: ' || coalesce(m, 'none'));
  update profiles set location_id = home_location_id where id = o;

  -- admit the guest (friend -> invite -> knock -> admit)
  perform pg_temp.login(h);
  perform social_add_friend(g);
  perform pg_temp.login(g); perform social_respond_friend(h, true);
  perform pg_temp.login(h); inv := social_send_house_invite(g);
  perform pg_temp.login(g); perform social_respond_house_invite((inv->>'id')::bigint, true);
  perform pg_temp.login(h); perform social_home_admit((inv->>'id')::bigint, true);
  perform pg_temp.assert((select location_id from profiles where id = g) = v_home, 'guest is inside');

  -- 3. guest posts a walk; host sees the guest (and the guest sees the host)
  perform pg_temp.login(g);
  r := house_room_move(2.0, 3.0, 1.0, true, null, '{"p":[2,3,2.5,3.5,3,4],"f":1.2,"at":12345}'::jsonb, null);
  perform pg_temp.login(h);
  r := house_room_state(false);
  perform pg_temp.assert(r->>'location' = v_home, 'host reads own home');
  perform pg_temp.assert(jsonb_array_length(r->'members') = 1, 'host sees one member: ' || r::text);
  perform pg_temp.assert(r->'members'->0->>'id' = g::text, 'that member is the guest');
  perform pg_temp.assert((r->'members'->0->>'x')::numeric = 2.0 and (r->'members'->0->>'moving')::boolean, 'position + moving');
  perform pg_temp.assert((r->'members'->0->'path'->>'at')::bigint = 12345, 'walk path returned');
  -- 4. no avatar/username unless asked
  perform pg_temp.assert(not (r->'members'->0 ? 'avatar') and not (r->'members'->0 ? 'username'), 'small payload without avatars');
  r := house_room_state(true);
  perform pg_temp.assert(r->'members'->0->>'username' = 'Rf_Guest' and r->'members'->0 ? 'avatar', 'avatars on request');
  perform pg_temp.login(g);
  r := house_room_state(false);
  perform pg_temp.assert(jsonb_array_length(r->'members') = 1 and r->'members'->0->>'id' = h::text, 'guest sees the host');
  -- a stop without a path keeps the last walk (receivers don't replay it: same "at")
  r := house_room_move(3.0, 4.0, 1.2, false, 'sit:sofa', null, null);
  perform pg_temp.login(h);
  r := house_room_state(false);
  perform pg_temp.assert((r->'members'->0->'path'->>'at')::bigint = 12345 and r->'members'->0->>'activity' = 'sit:sofa'
                         and not (r->'members'->0->>'moving')::boolean, 'stop keeps path, sets pose');
  -- oversized path is dropped, bad position refused
  perform pg_temp.login(g);
  r := house_room_move(3.0, 4.0, 0, false, null, jsonb_build_object('p', (select jsonb_agg(i) from generate_series(1, 200) i), 'at', 1), null);
  perform pg_temp.assert((select (path->>'at')::bigint from house_room_positions where user_id = g) = 12345, 'oversized path ignored');
  begin perform house_room_move(1000, 0, 0, false, null, null, null); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%Bad position%', 'bad position refused: ' || coalesce(m, 'none'));

  -- players_here_ids: ids + last_seen only; the outsider can't list a private home
  perform pg_temp.login(h);
  r := players_here_ids(v_home);
  perform pg_temp.assert(jsonb_array_length(r) = 1 and r->0->>'id' = g::text and r->0 ? 'last_seen' and not (r->0 ? 'avatar'),
                         'players_here_ids: the guest, ids only: ' || r::text);
  perform pg_temp.login(o);
  begin perform players_here_ids(v_home); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%private%', 'outsider cannot list a private home: ' || coalesce(m, 'none'));
  perform pg_temp.login(g);

  -- 5. the guest leaves: row marked left, the host no longer sees them
  perform social_leave_house();
  perform pg_temp.assert((select left_at is not null from house_room_positions where user_id = g), 'leaving marks the row left');
  perform pg_temp.login(h);
  r := house_room_state(false);
  perform pg_temp.assert(jsonb_array_length(r->'members') = 0, 'host sees nobody after the guest left: ' || r::text);
  -- and a guest that left can't read the house any more
  perform pg_temp.login(g);
  r := house_room_state(false);
  perform pg_temp.assert(r->>'location' <> v_home, 'former guest reads only their own home now');
  raise notice 'ok: house room state / move';
end $$;

-- 6. RLS: rows readable only by members of that house; no client writes
do $$ begin
  perform set_config('rf.h', (select id::text from profiles where username = 'Rf_Host'), true);
  perform set_config('rf.o', (select id::text from profiles where username = 'Rf_Out'), true);
end $$;
set local role authenticated;
do $$
declare h uuid := current_setting('rf.h')::uuid; o uuid := current_setting('rf.o')::uuid; m text;
begin
  perform pg_temp.login(h);
  perform pg_temp.assert((select count(*) from house_room_positions where user_id = h) = 1, 'host reads own house rows');
  perform pg_temp.login(o);
  perform pg_temp.assert((select count(*) from house_room_positions) = 0, 'outsider reads no house rows');
  begin insert into house_room_positions (user_id, location_id) select o, location_id from profiles where id = o; m := null;
  exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m is not null, 'client insert refused');
  begin update house_room_positions set x = 9; m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m is not null, 'client update refused');
  raise notice 'ok: house_room_positions RLS';
end $$;
reset role;

-- 7. grants
do $$
begin
  perform pg_temp.assert(not has_function_privilege('anon', 'public.house_room_state(boolean)', 'execute'), 'anon cannot read house state');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.house_room_move(real,real,real,boolean,text,jsonb,jsonb,text)', 'execute'), 'anon cannot post');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.house_room_state(boolean)', 'execute'), 'players can read');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.players_here_ids(text)', 'execute'), 'anon cannot list players');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_house_room_on_leave()', 'execute'), 'trigger fn private');
  perform pg_temp.assert(not has_table_privilege('anon', 'public.house_room_positions', 'select'), 'anon cannot select rows');
  perform pg_temp.assert(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'house_room_positions'),
                         'rows published to Realtime (live tabs bridge)');
  raise notice 'ok: realtime fallback grants';
end $$;
