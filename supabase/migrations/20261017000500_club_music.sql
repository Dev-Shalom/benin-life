-- M1 Club music playlists (docs/MUSIC.md).
-- The owner uploads MP3 / M4A / OGG files into the public Storage bucket `club-music` (admins only can write),
-- builds playlists, and assigns one to each club (locations.playlist_id) and, optionally, to each event
-- (place_events.playlist_id). While an event with a playlist is LIVE at a club its playlist plays; otherwise the
-- club's playlist; otherwise the default playlist (if one is marked); otherwise the client falls back to
-- music.club_track_url (a single looping file) and finally to the synthesized amapiano groove.
--   * Radio-style sync: the client computes position = (server now - playlist.anchor) mod total duration, so
--     every player hears the same moment. The anchor only moves when a playlist's track list / order / shuffle
--     (or the length of one of its tracks) is edited, or a track in it is deleted.
--   * Tables music_tracks, music_playlists, music_playlist_tracks: RLS on, no direct grants (players and the
--     browser cannot read or write them); everything goes through RPCs.
--   * club_music_for(location): the player read RPC (any logged-in player; anon is blocked by launch_safety): the resolved playlist for a place
--     (track URLs, durations, shuffle, anchor, the live event id, when to ask again).
--   * admin_music_*: admin-only RPCs, every change written to admin_audit.
--   * music.club_track_url, when set, is migrated into a "Default" playlist (one track, duration unknown and CORS
--     unchecked, so it is NOT played as a radio until the admin presses "Measure" on the Music page; until then
--     the old single-file setting keeps working exactly as before). The setting stays as the fallback.
-- No existing function is changed. Idempotent and safe on a non-empty DB.

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
create table if not exists public.music_tracks (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  artist       text not null default '',
  url          text not null,
  storage_path text,
  duration_ms  int not null default 0,
  size_bytes   bigint,
  cors_ok      boolean not null default true,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  constraint music_tracks_title_chk check (char_length(btrim(title)) between 1 and 120 and char_length(artist) <= 120),
  constraint music_tracks_url_chk check (url ~ '^https?://' and char_length(url) <= 800),
  -- 0 = not measured yet (only the migrated settings track); a real track is 1 s .. 3 h
  constraint music_tracks_dur_chk check (duration_ms between 0 and 10800000)
);

create table if not exists public.music_playlists (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  shuffle    boolean not null default false,
  is_default boolean not null default false,
  anchor     timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint music_playlists_name_chk check (char_length(btrim(name)) between 1 and 80)
);
create unique index if not exists music_playlists_name_uq on public.music_playlists (lower(btrim(name)));
create unique index if not exists music_playlists_default_uq on public.music_playlists (is_default) where is_default;

create table if not exists public.music_playlist_tracks (
  playlist_id uuid not null references public.music_playlists(id) on delete cascade,
  track_id    uuid not null references public.music_tracks(id) on delete cascade,
  position    int  not null,
  primary key (playlist_id, track_id)
);
create index if not exists music_playlist_tracks_pos_idx on public.music_playlist_tracks (playlist_id, position);

alter table public.locations     add column if not exists playlist_id uuid references public.music_playlists(id) on delete set null;
alter table public.place_events  add column if not exists playlist_id uuid references public.music_playlists(id) on delete set null;
create index if not exists locations_playlist_idx on public.locations (playlist_id) where playlist_id is not null;
create index if not exists place_events_playlist_idx on public.place_events (playlist_id) where playlist_id is not null;

alter table public.music_tracks          enable row level security;
alter table public.music_playlists       enable row level security;
alter table public.music_playlist_tracks enable row level security;
revoke all on table public.music_tracks, public.music_playlists, public.music_playlist_tracks from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Storage: public-read bucket, admin-only writes
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('club-music', 'club-music', true, 31457280,
        array['audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/x-m4a', 'audio/m4a', 'audio/aac', 'audio/ogg', 'application/ogg',
              'audio/wav', 'audio/x-wav', 'audio/webm']::text[])
on conflict (id) do update set
  name = excluded.name,
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- public objects are served without any policy; this select policy lets the admin list / upsert
drop policy if exists club_music_read on storage.objects;
create policy club_music_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'club-music');
drop policy if exists club_music_admin_insert on storage.objects;
create policy club_music_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'club-music'
              and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin and not p.banned));
drop policy if exists club_music_admin_update on storage.objects;
create policy club_music_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'club-music'
         and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin and not p.banned))
  with check (bucket_id = 'club-music'
              and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin and not p.banned));
drop policy if exists club_music_admin_delete on storage.objects;
create policy club_music_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'club-music'
         and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin and not p.banned));

-- ---------------------------------------------------------------------
-- 3. Private helpers
-- ---------------------------------------------------------------------
-- A playlist can be played as a radio when it has tracks, every track has a measured length, and every track
-- can be routed through WebAudio (CORS ok).
create or replace function public.bl_music_playable(p_playlist uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_playlist is not null
     and exists (select 1 from music_playlist_tracks where playlist_id = p_playlist)
     and not exists (select 1 from music_playlist_tracks pt join music_tracks t on t.id = pt.track_id
                      where pt.playlist_id = p_playlist and (t.duration_ms <= 0 or not t.cors_ok));
$$;

create or replace function public.bl_music_track_json(t music_tracks) returns jsonb
language sql immutable as $$
  select jsonb_build_object('id', t.id, 'title', t.title, 'artist', t.artist, 'url', t.url,
                            'duration_ms', t.duration_ms);
$$;

-- One playlist for players: ordered tracks, total length, shuffle, anchor (epoch ms)
create or replace function public.bl_music_playlist_json(p_playlist uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'name', p.name, 'shuffle', p.shuffle,
    'anchor_ms', floor(extract(epoch from p.anchor) * 1000)::bigint,
    'total_ms', coalesce((select sum(t.duration_ms) from music_playlist_tracks pt join music_tracks t on t.id = pt.track_id
                           where pt.playlist_id = p.id), 0),
    'tracks', coalesce((select jsonb_agg(bl_music_track_json(t) order by pt.position)
                          from music_playlist_tracks pt join music_tracks t on t.id = pt.track_id
                         where pt.playlist_id = p.id), '[]'::jsonb))
  from music_playlists p where p.id = p_playlist;
$$;

-- Move a playlist's anchor to now (its edit made the old schedule meaningless)
create or replace function public.bl_music_touch(p_playlist uuid) returns void
language sql volatile security definer set search_path = public as $$
  update music_playlists set anchor = bl_now(), updated_at = bl_now() where id = p_playlist;
$$;

revoke execute on function public.bl_music_playable(uuid) from public, anon, authenticated;
revoke execute on function public.bl_music_track_json(music_tracks) from public, anon, authenticated;
revoke execute on function public.bl_music_playlist_json(uuid) from public, anon, authenticated;
revoke execute on function public.bl_music_touch(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Public read: the resolved playlist for a place
-- ---------------------------------------------------------------------
-- {location_id, source: event | club | default | none, event_id, playlist: {...} | null, now_ms, refresh_at_ms}
-- A LIVE event (bl_event_occurrences, real Benin time) with a playable playlist wins; then the club's own
-- playlist; then the default playlist (clubs only). refresh_at_ms = when the answer will change by itself
-- (the live event ends, or the next one with a playlist starts); the client also re-asks every couple of minutes
-- to pick up admin edits.
create or replace function public.club_music_for(p_location text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_now    timestamptz := bl_now();
  l        locations;
  v_ev     text;
  v_ev_pl  uuid;
  v_ev_end timestamptz;
  v_next   timestamptz;
  v_pl     uuid;
  v_src    text := 'none';
begin
  select * into l from locations where id = p_location and coalesce(active, true);
  if l.id is null then
    return jsonb_build_object('location_id', p_location, 'source', 'none', 'event_id', null, 'playlist', null,
                              'now_ms', floor(extract(epoch from v_now) * 1000)::bigint, 'refresh_at_ms', null);
  end if;
  select o.event_id, e.playlist_id, o.ends_at into v_ev, v_ev_pl, v_ev_end
    from bl_event_occurrences(v_now) o join place_events e on e.id = o.event_id
   where e.location_id = l.id and e.active and e.playlist_id is not null and bl_music_playable(e.playlist_id)
     and o.starts_at <= v_now and o.ends_at > v_now
   order by o.starts_at, e.sort, e.id limit 1;
  select min(o.starts_at) into v_next
    from bl_event_occurrences(v_now) o join place_events e on e.id = o.event_id
   where e.location_id = l.id and e.active and e.playlist_id is not null and bl_music_playable(e.playlist_id)
     and o.starts_at > v_now;
  if v_ev_pl is not null then
    v_pl := v_ev_pl; v_src := 'event';
  elsif bl_music_playable(l.playlist_id) then
    v_pl := l.playlist_id; v_src := 'club';
  elsif l.scene = 'club' then
    select id into v_pl from music_playlists where is_default and bl_music_playable(id);
    if v_pl is not null then v_src := 'default'; end if;
  end if;
  return jsonb_build_object(
    'location_id', l.id, 'source', v_src, 'event_id', case when v_src = 'event' then v_ev end,
    'playlist', case when v_pl is null then null else bl_music_playlist_json(v_pl) end,
    'now_ms', floor(extract(epoch from v_now) * 1000)::bigint,
    'refresh_at_ms', case when coalesce(v_ev_end, v_next) is null then null
                          else floor(extract(epoch from least(coalesce(v_ev_end, v_next), coalesce(v_next, v_ev_end))) * 1000)::bigint end);
end $$;

revoke all on function public.club_music_for(text) from public, anon;
grant execute on function public.club_music_for(text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 5. Admin RPCs (bl_admin_guard + admin_audit)
-- ---------------------------------------------------------------------
create or replace function public.admin_music_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard();
begin
  return jsonb_build_object(
    'tracks', coalesce((select jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'artist', t.artist, 'url', t.url, 'storage_path', t.storage_path,
        'duration_ms', t.duration_ms, 'size_bytes', t.size_bytes, 'cors_ok', t.cors_ok, 'created_at', t.created_at,
        'used_in', (select count(*) from music_playlist_tracks pt where pt.track_id = t.id)) order by t.created_at desc, t.title)
      from music_tracks t), '[]'::jsonb),
    'playlists', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'shuffle', p.shuffle, 'is_default', p.is_default, 'anchor', p.anchor,
        'playable', bl_music_playable(p.id),
        'total_ms', coalesce((select sum(t.duration_ms) from music_playlist_tracks pt join music_tracks t on t.id = pt.track_id where pt.playlist_id = p.id), 0),
        'track_ids', coalesce((select jsonb_agg(pt.track_id order by pt.position) from music_playlist_tracks pt where pt.playlist_id = p.id), '[]'::jsonb),
        'clubs', (select count(*) from locations l where l.playlist_id = p.id),
        'events', (select count(*) from place_events e where e.playlist_id = p.id)) order by p.name)
      from music_playlists p), '[]'::jsonb),
    'clubs', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'active', coalesce(l.active, true), 'playlist_id', l.playlist_id)
                                        order by l.sort, l.name) from locations l where l.scene = 'club'), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'title', e.title, 'icon', e.icon, 'kind', e.kind, 'active', e.active,
                                        'location_id', e.location_id, 'location_name', l.name, 'playlist_id', e.playlist_id)
                                        order by l.sort, l.name, e.sort, e.id)
                          from place_events e join locations l on l.id = e.location_id where l.scene = 'club'), '[]'::jsonb),
    'setting_url', coalesce(nullif(btrim(coalesce((select value #>> '{}' from game_config where key = 'music.club_track_url'), '')), ''), null));
end $$;

create or replace function public.admin_music_track_add(p_title text, p_artist text, p_url text, p_storage_path text,
                                                        p_duration_ms int, p_size bigint default null, p_cors_ok boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  v_title text := btrim(coalesce(p_title, ''));
  t       music_tracks;
begin
  if char_length(v_title) not between 1 and 120 then
    raise exception 'Give the track a title (up to 120 characters).' using errcode = 'P0001', hint = 'bad_title';
  end if;
  if char_length(coalesce(p_artist, '')) > 120 then
    raise exception 'Artist is too long (120 characters max).' using errcode = 'P0001', hint = 'bad_artist';
  end if;
  if p_url is null or p_url !~ '^https?://' or char_length(p_url) > 800 then
    raise exception 'That link does not look right.' using errcode = 'P0001', hint = 'bad_url';
  end if;
  if p_duration_ms is null or p_duration_ms < 1000 or p_duration_ms > 10800000 then
    raise exception 'The track length must be between 1 second and 3 hours.' using errcode = 'P0001', hint = 'bad_duration';
  end if;
  if p_storage_path is not null and not exists (select 1 from storage.objects o where o.bucket_id = 'club-music' and o.name = p_storage_path) then
    raise exception 'The upload did not finish. Try again.' using errcode = 'P0001', hint = 'file_missing';
  end if;
  insert into music_tracks (title, artist, url, storage_path, duration_ms, size_bytes, cors_ok, created_by)
  values (v_title, btrim(coalesce(p_artist, '')), p_url, p_storage_path, p_duration_ms, p_size, coalesce(p_cors_ok, true), v_admin)
  returning * into t;
  insert into admin_audit (admin_id, action, data)
  values (v_admin, 'music_track_add', jsonb_build_object('track_id', t.id, 'title', t.title, 'storage_path', t.storage_path, 'duration_ms', t.duration_ms));
  return bl_music_track_json(t) || jsonb_build_object('storage_path', t.storage_path, 'cors_ok', t.cors_ok, 'used_in', 0);
end $$;

-- Rename / re-artist / fix the length of a track. A new length moves the anchor of every playlist that has it.
create or replace function public.admin_music_track_update(p_id uuid, p_title text default null, p_artist text default null,
                                                           p_duration_ms int default null, p_cors_ok boolean default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  t       music_tracks;
  v_re    boolean;
  v_touch int := 0;
  r       record;
begin
  select * into t from music_tracks where id = p_id for update;
  if t.id is null then
    raise exception 'That track doesn''t exist.' using errcode = 'P0001', hint = 'no_track';
  end if;
  if p_title is not null and char_length(btrim(p_title)) not between 1 and 120 then
    raise exception 'Give the track a title (up to 120 characters).' using errcode = 'P0001', hint = 'bad_title';
  end if;
  if p_artist is not null and char_length(p_artist) > 120 then
    raise exception 'Artist is too long (120 characters max).' using errcode = 'P0001', hint = 'bad_artist';
  end if;
  if p_duration_ms is not null and p_duration_ms not between 1000 and 10800000 then
    raise exception 'The track length must be between 1 second and 3 hours.' using errcode = 'P0001', hint = 'bad_duration';
  end if;
  v_re := (p_duration_ms is not null and p_duration_ms <> t.duration_ms) or (p_cors_ok is not null and p_cors_ok <> t.cors_ok);
  update music_tracks set
    title = coalesce(btrim(p_title), title),
    artist = coalesce(btrim(p_artist), artist),
    duration_ms = coalesce(p_duration_ms, duration_ms),
    cors_ok = coalesce(p_cors_ok, cors_ok)
  where id = t.id returning * into t;
  if v_re then
    for r in select distinct playlist_id from music_playlist_tracks where track_id = t.id loop
      perform bl_music_touch(r.playlist_id);
      v_touch := v_touch + 1;
    end loop;
  end if;
  insert into admin_audit (admin_id, action, data)
  values (v_admin, 'music_track_update', jsonb_build_object('track_id', t.id, 'title', t.title, 'duration_ms', t.duration_ms,
                                                            'cors_ok', t.cors_ok, 'playlists_restarted', v_touch));
  return bl_music_track_json(t) || jsonb_build_object('storage_path', t.storage_path, 'cors_ok', t.cors_ok, 'playlists_restarted', v_touch);
end $$;

-- Delete a track (and drop it from every playlist, moving their anchors). Returns storage_path so the admin
-- page can remove the file from the bucket (storage objects cannot be deleted from SQL).
create or replace function public.admin_music_track_delete(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  t       music_tracks;
  v_touch int := 0;
  r       record;
begin
  select * into t from music_tracks where id = p_id for update;
  if t.id is null then
    raise exception 'That track doesn''t exist.' using errcode = 'P0001', hint = 'no_track';
  end if;
  for r in select distinct playlist_id from music_playlist_tracks where track_id = t.id loop
    delete from music_playlist_tracks where playlist_id = r.playlist_id and track_id = t.id;
    -- close the gap in the order
    update music_playlist_tracks pt set position = x.rn
      from (select track_id, row_number() over (order by position) as rn from music_playlist_tracks where playlist_id = r.playlist_id) x
     where pt.playlist_id = r.playlist_id and pt.track_id = x.track_id;
    perform bl_music_touch(r.playlist_id);
    v_touch := v_touch + 1;
  end loop;
  delete from music_tracks where id = t.id;
  insert into admin_audit (admin_id, action, data)
  values (v_admin, 'music_track_delete', jsonb_build_object('track_id', t.id, 'title', t.title, 'storage_path', t.storage_path, 'playlists_restarted', v_touch));
  return jsonb_build_object('id', t.id, 'storage_path', t.storage_path, 'playlists_restarted', v_touch,
                            'message', 'Deleted "' || t.title || '".');
end $$;

-- Create (p_id null) or update a playlist. p_tracks is the full ordered list. The anchor moves when the list
-- (membership or order) or the shuffle setting changes, never for a rename.
create or replace function public.admin_music_playlist_save(p_id uuid, p_name text, p_shuffle boolean, p_tracks uuid[],
                                                            p_default boolean default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_admin   uuid := bl_admin_guard();
  v_name    text := btrim(coalesce(p_name, ''));
  v_tracks  uuid[] := coalesce(p_tracks, '{}'::uuid[]);
  p         music_playlists;
  v_old     uuid[];
  v_new     boolean := p_id is null;
  v_moved   boolean := false;
begin
  if char_length(v_name) not between 1 and 80 then
    raise exception 'Give the playlist a name (up to 80 characters).' using errcode = 'P0001', hint = 'bad_name';
  end if;
  if cardinality(v_tracks) > 200 then
    raise exception 'A playlist can have up to 200 tracks.' using errcode = 'P0001', hint = 'too_many';
  end if;
  if (select count(distinct x) from unnest(v_tracks) x) <> cardinality(v_tracks) then
    raise exception 'A track can only be in a playlist once.' using errcode = 'P0001', hint = 'dup_track';
  end if;
  if exists (select 1 from unnest(v_tracks) x where not exists (select 1 from music_tracks t where t.id = x)) then
    raise exception 'One of those tracks no longer exists. Refresh the page.' using errcode = 'P0001', hint = 'no_track';
  end if;
  if exists (select 1 from music_playlists q where lower(btrim(q.name)) = lower(v_name) and q.id is distinct from p_id) then
    raise exception 'There is already a playlist called "%".', v_name using errcode = 'P0001', hint = 'name_taken';
  end if;
  if v_new then
    insert into music_playlists (name, shuffle, anchor) values (v_name, coalesce(p_shuffle, false), bl_now()) returning * into p;
    v_old := '{}';
    v_moved := true;
  else
    select * into p from music_playlists where id = p_id for update;
    if p.id is null then
      raise exception 'That playlist doesn''t exist.' using errcode = 'P0001', hint = 'no_playlist';
    end if;
    select coalesce(array_agg(track_id order by position), '{}') into v_old from music_playlist_tracks where playlist_id = p.id;
    v_moved := v_old is distinct from v_tracks or p.shuffle is distinct from coalesce(p_shuffle, p.shuffle);
    update music_playlists set name = v_name, shuffle = coalesce(p_shuffle, shuffle), updated_at = bl_now() where id = p.id returning * into p;
  end if;
  if v_new or v_old is distinct from v_tracks then
    delete from music_playlist_tracks where playlist_id = p.id;
    insert into music_playlist_tracks (playlist_id, track_id, position)
    select p.id, x.t, x.ord from unnest(v_tracks) with ordinality as x(t, ord);
  end if;
  if p_default is not null then
    if p_default then update music_playlists set is_default = false where is_default and id <> p.id; end if;
    update music_playlists set is_default = p_default where id = p.id;
  end if;
  if v_moved and not v_new then perform bl_music_touch(p.id); end if;
  insert into admin_audit (admin_id, action, data)
  values (v_admin, case when v_new then 'music_playlist_create' else 'music_playlist_edit' end,
          jsonb_build_object('playlist_id', p.id, 'name', v_name, 'shuffle', p.shuffle, 'tracks', cardinality(v_tracks),
                             'restarted', v_moved, 'default', p_default));
  return bl_music_playlist_json(p.id) || jsonb_build_object('restarted', v_moved, 'is_default', (select is_default from music_playlists where id = p.id));
end $$;

create or replace function public.admin_music_playlist_delete(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  p       music_playlists;
  v_l     int;
  v_e     int;
begin
  select * into p from music_playlists where id = p_id for update;
  if p.id is null then
    raise exception 'That playlist doesn''t exist.' using errcode = 'P0001', hint = 'no_playlist';
  end if;
  select count(*) into v_l from locations where playlist_id = p.id;
  select count(*) into v_e from place_events where playlist_id = p.id;
  delete from music_playlists where id = p.id; -- FKs null out locations / events, cascade the track rows
  insert into admin_audit (admin_id, action, data)
  values (v_admin, 'music_playlist_delete', jsonb_build_object('playlist_id', p.id, 'name', p.name, 'clubs_cleared', v_l, 'events_cleared', v_e));
  return jsonb_build_object('id', p.id, 'clubs_cleared', v_l, 'events_cleared', v_e, 'message', 'Deleted playlist "' || p.name || '".');
end $$;

-- Assign (or clear, with null) a playlist: p_kind 'club' (locations) or 'event' (place_events)
create or replace function public.admin_music_assign(p_kind text, p_id text, p_playlist uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  v_name  text;
  v_old   uuid;
begin
  if p_playlist is not null and not exists (select 1 from music_playlists where id = p_playlist) then
    raise exception 'That playlist doesn''t exist.' using errcode = 'P0001', hint = 'no_playlist';
  end if;
  if p_kind = 'club' then
    select name, playlist_id into v_name, v_old from locations where id = p_id and scene = 'club' for update;
    if v_name is null then
      raise exception 'That club doesn''t exist.' using errcode = 'P0001', hint = 'no_club';
    end if;
    update locations set playlist_id = p_playlist where id = p_id;
  elsif p_kind = 'event' then
    select title, playlist_id into v_name, v_old from place_events where id = p_id for update;
    if v_name is null then
      raise exception 'That event doesn''t exist.' using errcode = 'P0001', hint = 'no_event';
    end if;
    update place_events set playlist_id = p_playlist where id = p_id;
  else
    raise exception 'Unknown kind.' using errcode = 'P0001', hint = 'bad_kind';
  end if;
  insert into admin_audit (admin_id, action, data)
  values (v_admin, 'music_assign', jsonb_build_object('kind', p_kind, 'id', p_id, 'name', v_name, 'playlist_id', p_playlist, 'was', v_old));
  return jsonb_build_object('kind', p_kind, 'id', p_id, 'playlist_id', p_playlist,
    'message', v_name || case when p_playlist is null then ' has no playlist now.' else ' playlist saved.' end);
end $$;

revoke all on function public.admin_music_overview() from public, anon;
revoke all on function public.admin_music_track_add(text, text, text, text, int, bigint, boolean) from public, anon;
revoke all on function public.admin_music_track_update(uuid, text, text, int, boolean) from public, anon;
revoke all on function public.admin_music_track_delete(uuid) from public, anon;
revoke all on function public.admin_music_playlist_save(uuid, text, boolean, uuid[], boolean) from public, anon;
revoke all on function public.admin_music_playlist_delete(uuid) from public, anon;
revoke all on function public.admin_music_assign(text, text, uuid) from public, anon;
grant execute on function public.admin_music_overview() to authenticated;
grant execute on function public.admin_music_track_add(text, text, text, text, int, bigint, boolean) to authenticated;
grant execute on function public.admin_music_track_update(uuid, text, text, int, boolean) to authenticated;
grant execute on function public.admin_music_track_delete(uuid) to authenticated;
grant execute on function public.admin_music_playlist_save(uuid, text, boolean, uuid[], boolean) to authenticated;
grant execute on function public.admin_music_playlist_delete(uuid) to authenticated;
grant execute on function public.admin_music_assign(text, text, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 6. music.club_track_url -> a "Default" playlist (only when the setting is filled and nothing exists yet)
-- ---------------------------------------------------------------------
do $$
declare
  v_url text := btrim(coalesce((select value #>> '{}' from public.game_config where key = 'music.club_track_url'), ''));
  v_track uuid;
  v_pl uuid;
begin
  if v_url = '' or v_url !~ '^https?://' or exists (select 1 from public.music_playlists) then
    return;
  end if;
  -- duration unknown (0) and CORS unchecked: not played as a radio until "Measure" on the Music page; the setting keeps working meanwhile
  insert into public.music_tracks (title, artist, url, duration_ms, cors_ok)
  values ('Club track (from settings)', '', v_url, 0, false) returning id into v_track;
  insert into public.music_playlists (name, shuffle, is_default) values ('Default', false, true) returning id into v_pl;
  insert into public.music_playlist_tracks (playlist_id, track_id, position) values (v_pl, v_track, 1);
end $$;

notify pgrst, 'reload schema';
