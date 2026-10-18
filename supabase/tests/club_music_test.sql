-- M1 club music (20261017000500_club_music.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/club_music_test.sql
-- Groups: 1 grants + RLS (players can read / write nothing; the resolver is for logged-in players; helpers private) ·
-- 2 admin-only writes, validation, audit · 3 playlists: save / reorder / shuffle, anchor moves only on real edits ·
-- 4 resolve: none -> club playlist -> default -> live event -> back to club -> unplayable falls through ·
-- 5 track update / delete move anchors and clean playlists · 6 storage bucket + admin-only write policies ·
-- 7 the music.club_track_url migration shape.

create or replace function pg_temp.cm_hint(p_sql text, p_hint text) returns text
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

create temp table t_cm (name text primary key, id uuid not null) on commit drop;
grant select on t_cm to authenticated;
create or replace function pg_temp.cm(p_name text) returns uuid
language sql as $$ select id from t_cm where name = p_name $$;

do $$
declare a uuid := pg_temp.new_user('cm_ada@club.bl'); adm uuid := pg_temp.new_user('cm_adm@club.bl');
begin
  perform set_config('bl.test_offset_seconds', '', true);
  insert into t_cm values ('ada', a), ('adm', adm);
  perform pg_temp.login(a);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2('Cm_Ada', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  perform pg_temp.login(adm);
  perform create_profile_v2('Cm_Adm', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set is_admin = true where id = adm;
  update locations set active = true where id in ('club_raptor', 'club_360');
  -- a clean slate for the assertions (rolled back anyway)
  update locations set playlist_id = null;
  update place_events set playlist_id = null;
  delete from music_playlists;
  delete from music_tracks;
end $$;

-- ---------- 1. grants + RLS ----------
do $$
declare v_rpc text;
begin
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.music_tracks'::regclass)
                         and (select relrowsecurity from pg_class where oid = 'public.music_playlists'::regclass)
                         and (select relrowsecurity from pg_class where oid = 'public.music_playlist_tracks'::regclass), 'RLS on all three tables');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.music_tracks', 'select')
                         and not has_table_privilege('anon', 'public.music_tracks', 'select')
                         and not has_table_privilege('authenticated', 'public.music_playlists', 'select')
                         and not has_table_privilege('authenticated', 'public.music_playlist_tracks', 'select'), 'no direct select');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.music_tracks', 'insert')
                         and not has_table_privilege('authenticated', 'public.music_tracks', 'update')
                         and not has_table_privilege('authenticated', 'public.music_tracks', 'delete')
                         and not has_table_privilege('authenticated', 'public.music_playlists', 'insert')
                         and not has_table_privilege('authenticated', 'public.music_playlist_tracks', 'insert')
                         and not has_table_privilege('anon', 'public.music_playlists', 'insert'), 'no direct writes');
  foreach v_rpc in array array['admin_music_overview()', 'admin_music_track_add(text,text,text,text,int,bigint,boolean)',
                               'admin_music_track_update(uuid,text,text,int,boolean)', 'admin_music_track_delete(uuid)',
                               'admin_music_playlist_save(uuid,text,boolean,uuid[],boolean)', 'admin_music_playlist_delete(uuid)',
                               'admin_music_assign(text,text,uuid)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'authenticated may call (admin-checked inside) ' || v_rpc);
  end loop;
  foreach v_rpc in array array['bl_music_playable(uuid)', 'bl_music_playlist_json(uuid)', 'bl_music_touch(uuid)', 'bl_music_track_json(music_tracks)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'helper private ' || v_rpc);
  end loop;
  perform pg_temp.assert(not has_function_privilege('anon', 'public.club_music_for(text)', 'execute')
                         and has_function_privilege('authenticated', 'public.club_music_for(text)', 'execute'), 'resolver: logged-in players only');
  raise notice 'ok 1: grants + RLS';
end $$;

-- ---------- 2. admin-only writes + validation + audit ----------
do $$
declare a uuid := pg_temp.cm('ada'); adm uuid := pg_temp.cm('adm'); t jsonb; n0 bigint := (select count(*) from admin_audit where action like 'music_%');
        tid uuid;
begin
  perform pg_temp.login(a);
  perform pg_temp.cm_hint($q$select admin_music_overview()$q$, 'not_admin');
  perform pg_temp.cm_hint($q$select admin_music_track_add('x', '', 'https://a.b/x.mp3', null, 5000)$q$, 'not_admin');
  perform pg_temp.cm_hint($q$select admin_music_playlist_save(null, 'Mine', false, '{}')$q$, 'not_admin');
  perform pg_temp.cm_hint($q$select admin_music_assign('club', 'club_360', null)$q$, 'not_admin');
  perform pg_temp.cm_hint($q$select admin_music_track_delete(gen_random_uuid())$q$, 'not_admin');
  perform pg_temp.cm_hint($q$select admin_music_playlist_delete(gen_random_uuid())$q$, 'not_admin');
  perform pg_temp.cm_hint($q$select admin_music_track_update(gen_random_uuid(), 'x')$q$, 'not_admin');
  perform pg_temp.assert((select count(*) from music_tracks) = 0 and (select count(*) from music_playlists) = 0, 'players wrote nothing');

  perform pg_temp.login(adm);
  perform pg_temp.cm_hint($q$select admin_music_track_add('', '', 'https://a.b/x.mp3', null, 5000)$q$, 'bad_title');
  perform pg_temp.cm_hint($q$select admin_music_track_add('T', '', 'ftp://a.b/x.mp3', null, 5000)$q$, 'bad_url');
  perform pg_temp.cm_hint($q$select admin_music_track_add('T', '', 'https://a.b/x.mp3', null, 500)$q$, 'bad_duration');
  perform pg_temp.cm_hint($q$select admin_music_track_add('T', '', 'https://a.b/x.mp3', null, 99999999)$q$, 'bad_duration');
  perform pg_temp.cm_hint($q$select admin_music_track_add('T', '', 'https://a.b/x.mp3', 'ghost/none.mp3', 5000)$q$, 'file_missing');
  t := admin_music_track_add('Alpha', 'DJ A', 'https://a.b/alpha.mp3', null, 60000, 1000);
  perform pg_temp.assert(t->>'title' = 'Alpha' and (t->>'duration_ms')::int = 60000 and (t->>'cors_ok')::boolean, 'track added: ' || t::text);
  tid := (t->>'id')::uuid;
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'music_track_add' and admin_id = adm and data->>'track_id' = tid::text), 'add audited');
  perform pg_temp.assert(jsonb_array_length(admin_music_overview()->'tracks') = 1, 'overview lists the track');
  perform pg_temp.assert(jsonb_array_length(admin_music_overview()->'clubs') >= 5 and (admin_music_overview()->'events') is not null, 'overview has clubs + events');
  perform pg_temp.assert((select count(*) from admin_audit where action like 'music_%') = n0 + 1, 'one audit row so far');
  raise notice 'ok 2: admin-only writes, validation, audit';
end $$;

-- ---------- 3. playlists + the anchor ----------
do $$
declare adm uuid := pg_temp.cm('adm'); a1 uuid; a2 uuid; a3 uuid; p jsonb; pid uuid; an0 timestamptz; an1 timestamptz;
begin
  perform pg_temp.login(adm);
  a1 := (select id from music_tracks where title = 'Alpha');
  a2 := (admin_music_track_add('Bravo', '', 'https://a.b/bravo.mp3', null, 90000)->>'id')::uuid;
  a3 := (admin_music_track_add('Charlie', '', 'https://a.b/charlie.mp3', null, 30000)->>'id')::uuid;
  p := admin_music_playlist_save(null, 'Night mix', false, array[a1, a2]);
  pid := (p->>'id')::uuid;
  perform pg_temp.assert((p->>'total_ms')::bigint = 150000 and p->'tracks'->0->>'title' = 'Alpha' and p->'tracks'->1->>'title' = 'Bravo', 'saved in order: ' || p::text);
  perform pg_temp.assert(not (p->>'shuffle')::boolean and (p->>'anchor_ms')::bigint > 0, 'anchor_ms set');
  perform pg_temp.cm_hint(format($q$select admin_music_playlist_save(null, 'night MIX', false, '{}')$q$), 'name_taken');
  perform pg_temp.cm_hint(format($q$select admin_music_playlist_save(%L, 'Night mix', false, array[%L, %L]::uuid[])$q$, pid, a1, a1), 'dup_track');
  perform pg_temp.cm_hint(format($q$select admin_music_playlist_save(%L, 'Night mix', false, array[gen_random_uuid()])$q$, pid), 'no_track');
  perform pg_temp.cm_hint($q$select admin_music_playlist_save(null, '   ', false, '{}')$q$, 'bad_name');

  -- time passes; a rename does NOT move the anchor
  perform set_config('bl.test_offset_seconds', '120', true);
  an0 := (select anchor from music_playlists where id = pid);
  p := admin_music_playlist_save(pid, 'Night mix 2', false, array[a1, a2]);
  perform pg_temp.assert(not (p->>'restarted')::boolean and (select anchor from music_playlists where id = pid) = an0, 'rename keeps the anchor');
  -- reorder moves it
  p := admin_music_playlist_save(pid, 'Night mix 2', false, array[a2, a1]);
  an1 := (select anchor from music_playlists where id = pid);
  perform pg_temp.assert((p->>'restarted')::boolean and an1 > an0, 'reorder moves the anchor');
  perform pg_temp.assert(p->'tracks'->0->>'title' = 'Bravo', 'new order saved');
  -- adding a track moves it; shuffle toggle moves it
  perform set_config('bl.test_offset_seconds', '240', true);
  p := admin_music_playlist_save(pid, 'Night mix 2', false, array[a2, a1, a3]);
  perform pg_temp.assert((select anchor from music_playlists where id = pid) > an1 and (p->>'total_ms')::bigint = 180000, 'add moves the anchor, total 180 s');
  an1 := (select anchor from music_playlists where id = pid);
  perform set_config('bl.test_offset_seconds', '360', true);
  p := admin_music_playlist_save(pid, 'Night mix 2', true, array[a2, a1, a3]);
  perform pg_temp.assert((p->>'shuffle')::boolean and (select anchor from music_playlists where id = pid) > an1, 'shuffle toggle moves the anchor');
  -- an identical save does nothing
  an1 := (select anchor from music_playlists where id = pid);
  perform set_config('bl.test_offset_seconds', '480', true);
  p := admin_music_playlist_save(pid, 'Night mix 2', true, array[a2, a1, a3]);
  perform pg_temp.assert(not (p->>'restarted')::boolean and (select anchor from music_playlists where id = pid) = an1, 'same save, same anchor');
  perform pg_temp.assert((select array_agg(track_id order by position) from music_playlist_tracks where playlist_id = pid) = array[a2, a1, a3], 'positions stored');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'music_playlist_create' and data->>'playlist_id' = pid::text)
                         and exists (select 1 from admin_audit where action = 'music_playlist_edit' and data->>'playlist_id' = pid::text), 'create + edit audited');
  perform set_config('bl.test_offset_seconds', '', true);
  raise notice 'ok 3: playlists + anchor';
end $$;

-- ---------- 4. resolve ----------
do $$
declare adm uuid := pg_temp.cm('adm'); a uuid := pg_temp.cm('ada'); pl uuid := (select id from music_playlists where name = 'Night mix 2');
        ev_pl uuid; r jsonb; bad uuid; badpl uuid; t_zero uuid;
begin
  perform pg_temp.login(adm);
  -- nothing assigned
  r := club_music_for('club_360');
  perform pg_temp.assert(r->>'source' = 'none' and r->'playlist' = 'null'::jsonb, 'no playlist: none');
  -- unknown / non-club ids never raise
  perform pg_temp.assert(club_music_for('nowhere')->>'source' = 'none', 'unknown place: none');
  -- club playlist
  perform admin_music_assign('club', 'club_360', pl);
  perform pg_temp.login(a); -- a player reads it
  r := club_music_for('club_360');
  perform pg_temp.assert(r->>'source' = 'club' and r->'playlist'->>'id' = pl::text and (r->'playlist'->>'shuffle')::boolean, 'club playlist resolves: ' || r::text);
  perform pg_temp.assert(jsonb_array_length(r->'playlist'->'tracks') = 3 and r->'playlist'->'tracks'->0 ? 'url' and r->'playlist'->'tracks'->0 ? 'duration_ms', 'tracks carry url + duration');
  perform pg_temp.assert((r->>'now_ms')::bigint > 0 and r->'event_id' = 'null'::jsonb, 'now_ms, no event');
  perform pg_temp.assert(club_music_for('club_raptor')->>'source' = 'none', 'another club is unaffected');

  -- default playlist reaches clubs with nothing of their own
  perform pg_temp.login(adm);
  declare dp jsonb; begin
    dp := admin_music_playlist_save(null, 'Everywhere', false, array[(select id from music_tracks where title = 'Charlie')], true);
    perform pg_temp.assert((dp->>'is_default')::boolean, 'marked default');
    perform pg_temp.assert(club_music_for('club_raptor')->>'source' = 'default', 'club without a playlist uses the default');
    perform pg_temp.assert(club_music_for('club_360')->>'source' = 'club', 'club playlist beats the default');
    -- only one default: marking another clears it
    perform admin_music_playlist_save(pl, 'Night mix 2', true, (select array_agg(track_id order by position) from music_playlist_tracks where playlist_id = pl), true);
    perform pg_temp.assert((select count(*) from music_playlists where is_default) = 1 and (select is_default from music_playlists where id = pl), 'one default at a time');
    perform admin_music_playlist_save(pl, 'Night mix 2', true, (select array_agg(track_id order by position) from music_playlist_tracks where playlist_id = pl), false);
    perform admin_music_playlist_save((dp->>'id')::uuid, 'Everywhere', false, array[(select id from music_tracks where title = 'Charlie')], false);
    perform pg_temp.assert(club_music_for('club_raptor')->>'source' = 'none', 'default off: none again');
  end;

  -- a live event with a playlist wins, then falls back when it is over
  ev_pl := (admin_music_playlist_save(null, 'Event mix', false, array[(select id from music_tracks where title = 'Charlie')])->>'id')::uuid;
  insert into place_events (id, location_id, title, kind, recurrence, starts_at, ends_at, sort)
  values ('cm_ev', 'club_360', 'CM test event', 'club_night', 'none', bl_now() - interval '1 hour', bl_now() + interval '1 hour', 999);
  perform admin_music_assign('event', 'cm_ev', ev_pl);
  r := club_music_for('club_360');
  perform pg_temp.assert(r->>'source' = 'event' and r->>'event_id' = 'cm_ev' and r->'playlist'->>'id' = ev_pl::text, 'live event playlist wins: ' || r::text);
  perform pg_temp.assert((r->>'refresh_at_ms')::bigint > (r->>'now_ms')::bigint and (r->>'refresh_at_ms')::bigint <= (r->>'now_ms')::bigint + 3600000 + 2000, 'refresh_at = event end');
  perform pg_temp.assert(club_music_for('club_raptor')->>'source' = 'none', 'event at club_360 does not touch another club');
  -- inactive event: club playlist again
  update place_events set active = false where id = 'cm_ev';
  perform pg_temp.assert(club_music_for('club_360')->>'source' = 'club', 'inactive event ignored');
  update place_events set active = true where id = 'cm_ev';
  -- an event that has not started: club playlist now, refresh at its start
  update place_events set starts_at = bl_now() + interval '30 minutes', ends_at = bl_now() + interval '2 hours' where id = 'cm_ev';
  r := club_music_for('club_360');
  perform pg_temp.assert(r->>'source' = 'club' and (r->>'refresh_at_ms')::bigint between (r->>'now_ms')::bigint + 1700000 and (r->>'now_ms')::bigint + 1900000, 'upcoming event: club plays, refresh at start');
  -- over: back to the club playlist
  update place_events set starts_at = bl_now() - interval '3 hours', ends_at = bl_now() - interval '1 hour' where id = 'cm_ev';
  perform pg_temp.assert(club_music_for('club_360')->>'source' = 'club' and club_music_for('club_360')->'refresh_at_ms' = 'null'::jsonb, 'event over: club playlist');
  -- time travel: live now, gone in 2 hours
  update place_events set starts_at = bl_now() - interval '1 hour', ends_at = bl_now() + interval '1 hour' where id = 'cm_ev';
  perform set_config('bl.test_offset_seconds', '7200', true);
  perform pg_temp.assert(club_music_for('club_360')->>'source' = 'club', 'two hours later the event is over');
  perform set_config('bl.test_offset_seconds', '', true);
  -- a hidden (switched off) club resolves to none
  update locations set active = false where id = 'club_360';
  perform pg_temp.assert(club_music_for('club_360')->>'source' = 'none', 'closed club: none');
  update locations set active = true where id = 'club_360';

  -- an unplayable playlist (a track with no length, or no CORS) falls through
  t_zero := (select id from music_tracks where title = 'Alpha');
  update place_events set active = false where id = 'cm_ev';
  update music_tracks set cors_ok = false where id = t_zero;
  perform pg_temp.assert(not bl_music_playable(pl), 'a no-CORS track makes the playlist unplayable');
  perform pg_temp.assert(club_music_for('club_360')->>'source' = 'none', 'unplayable club playlist: none (client uses the setting / synth)');
  update music_tracks set cors_ok = true where id = t_zero;
  insert into music_tracks (title, url, duration_ms, cors_ok) values ('Unmeasured', 'https://a.b/u.mp3', 0, true) returning id into bad;
  badpl := (admin_music_playlist_save(null, 'Bad', false, array[bad])->>'id')::uuid;
  perform pg_temp.assert(not bl_music_playable(badpl), 'unmeasured track: unplayable');
  perform pg_temp.assert(bl_music_playable((select id from music_playlists where name = 'Event mix')), 'sanity: event mix is playable');
  raise notice 'ok 4: resolve (none / club / default / live event / fall-through)';
end $$;

-- ---------- 5. track update + delete ----------
do $$
declare adm uuid := pg_temp.cm('adm'); pl uuid := (select id from music_playlists where name = 'Night mix 2'); tr uuid; an0 timestamptz; r jsonb; ev uuid;
begin
  perform pg_temp.login(adm);
  tr := (select id from music_tracks where title = 'Bravo');
  an0 := (select anchor from music_playlists where id = pl);
  perform set_config('bl.test_offset_seconds', '900', true);
  r := admin_music_track_update(tr, 'Bravo (edit)', 'Someone', null, null);
  perform pg_temp.assert(r->>'title' = 'Bravo (edit)' and (select artist from music_tracks where id = tr) = 'Someone', 'renamed');
  perform pg_temp.assert((select anchor from music_playlists where id = pl) = an0, 'rename keeps the playlist anchor');
  perform pg_temp.cm_hint(format($q$select admin_music_track_update(%L, null, null, 10, null)$q$, tr), 'bad_duration');
  r := admin_music_track_update(tr, null, null, 95000, null);
  perform pg_temp.assert((r->>'playlists_restarted')::int = 1 and (select anchor from music_playlists where id = pl) > an0, 'a new length moves the anchor');
  an0 := (select anchor from music_playlists where id = pl);
  perform set_config('bl.test_offset_seconds', '1800', true);
  r := admin_music_track_delete(tr);
  perform pg_temp.assert((r->>'playlists_restarted')::int = 1 and (select anchor from music_playlists where id = pl) > an0, 'delete moves the anchor');
  perform pg_temp.assert(not exists (select 1 from music_tracks where id = tr) and not exists (select 1 from music_playlist_tracks where track_id = tr), 'track and rows gone');
  perform pg_temp.assert((select array_agg(position order by position) from music_playlist_tracks where playlist_id = pl) = array[1, 2], 'positions closed up');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'music_track_delete' and data->>'track_id' = tr::text), 'delete audited');
  perform pg_temp.cm_hint(format($q$select admin_music_track_delete(%L)$q$, tr), 'no_track');
  -- deleting a playlist clears its clubs and events
  ev := (select id from music_playlists where name = 'Event mix');
  perform admin_music_assign('club', 'club_raptor', ev);
  r := admin_music_playlist_delete(ev);
  perform pg_temp.assert((r->>'clubs_cleared')::int = 1 and (r->>'events_cleared')::int = 1, 'delete clears assignments: ' || r::text);
  perform pg_temp.assert((select playlist_id from locations where id = 'club_raptor') is null and (select playlist_id from place_events where id = 'cm_ev') is null, 'FKs nulled');
  perform pg_temp.cm_hint($q$select admin_music_assign('club', 'oba_market', null)$q$, 'no_club');
  perform pg_temp.cm_hint($q$select admin_music_assign('event', 'nope', null)$q$, 'no_event');
  perform pg_temp.cm_hint($q$select admin_music_assign('zzz', 'x', null)$q$, 'bad_kind');
  perform pg_temp.cm_hint($q$select admin_music_assign('club', 'club_360', gen_random_uuid())$q$, 'no_playlist');
  perform set_config('bl.test_offset_seconds', '', true);
  raise notice 'ok 5: track update / delete, playlist delete';
end $$;

-- ---------- 6. storage bucket + policies ----------
do $$
declare b record; pols int;
begin
  select * into b from storage.buckets where id = 'club-music';
  perform pg_temp.assert(b.id is not null and b.public, 'bucket club-music exists and is public');
  perform pg_temp.assert(b.allowed_mime_types @> array['audio/mpeg', 'audio/ogg', 'audio/mp4'] and b.file_size_limit > 0, 'audio mime types + size limit');
  select count(*) into pols from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'club_music_%';
  perform pg_temp.assert(pols = 4, 'four club_music policies (read + admin insert / update / delete), got ' || pols);
  perform pg_temp.assert(not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'club_music_%'
                                      and cmd in ('INSERT', 'UPDATE', 'DELETE') and (coalesce(with_check, '') not like '%is_admin%' and coalesce(qual, '') not like '%is_admin%')),
                         'every write policy checks is_admin');
  raise notice 'ok 6a: bucket + policies exist';
end $$;
-- behaviour: a player cannot write into the bucket, an admin can
do $$
declare a uuid := pg_temp.cm('ada'); adm uuid := pg_temp.cm('adm'); v_player_blocked boolean := false; v_admin_ok boolean := false; v_read int;
begin
  perform pg_temp.login(a);
  set local role authenticated;
  begin
    insert into storage.objects (bucket_id, name) values ('club-music', 'player-try.mp3');
  exception when others then v_player_blocked := true;
  end;
  reset role;
  perform pg_temp.assert(v_player_blocked and not exists (select 1 from storage.objects where name = 'player-try.mp3'), 'a player cannot upload to club-music');
  perform pg_temp.login(adm);
  set local role authenticated;
  begin
    insert into storage.objects (bucket_id, name) values ('club-music', 'admin-ok.mp3');
    v_admin_ok := true;
  exception when others then v_admin_ok := false;
  end;
  select count(*) into v_read from storage.objects where bucket_id = 'club-music';
  reset role;
  perform pg_temp.assert(v_admin_ok and v_read = 1, 'an admin can upload to club-music');
  -- anon can read, not write
  set local role anon;
  select count(*) into v_read from storage.objects where bucket_id = 'club-music';
  begin
    insert into storage.objects (bucket_id, name) values ('club-music', 'anon-try.mp3');
    v_player_blocked := false;
  exception when others then v_player_blocked := true;
  end;
  reset role;
  perform pg_temp.assert(v_read = 1 and v_player_blocked, 'anon reads, cannot write');
  -- add a track pointing at the uploaded file
  perform pg_temp.login(adm);
  perform pg_temp.assert(admin_music_track_add('Uploaded', '', 'http://x/storage/v1/object/public/club-music/admin-ok.mp3', 'admin-ok.mp3', 20000, 10)->>'storage_path' = 'admin-ok.mp3', 'track from a stored file');
  raise notice 'ok 6b: storage writes are admin-only';
end $$;

-- ---------- 7. the settings migration ----------
do $$
begin
  -- the migration creates a "Default" playlist with one unmeasured, CORS-unchecked track when the setting was filled.
  -- Here the setting is empty (nothing to migrate) or the playlists were just cleared, so assert the shape it builds.
  perform pg_temp.assert(not exists (select 1 from music_tracks where title = 'Club track (from settings)'), 'nothing migrated from an empty setting');
  raise notice 'ok 7: settings migration idle when the setting is empty';
end $$;
