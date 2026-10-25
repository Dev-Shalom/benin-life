-- Benin Gist (docs/GIST.md): ONE social place in the phone. Posts + likes + comments + tips (feed), group chats with voice notes and
-- money bubbles, moderation and notifications. It replaces the old "Messages" phone app (DMs and friends keep working unchanged).
--
-- Scale rules (docs/SCALING.md, docs/DISK_IO.md): there is NO "all posts" or "all groups" Realtime channel. The feed is paged by RPC
-- (keyset cursors, ~20 per page). Counts are cached on the row (likes, comments, tips, members, last message). "For you" is ranked by a
-- stored, time-independent key (ln(1 + engagement) + age term), so one index serves the whole feed. Realtime exists only for the ONE
-- group a player has open (INSERT/UPDATE on gist_messages, RLS: members only, blocked pairs hidden).
--
-- Safety: NO foreign key to public.profiles here (a lock on profiles deadlocked a live deploy once); those links are in the tiny
-- migration 20261031000200_gist_links.sql. All writes are security-definer RPCs; no client can write a table directly.
-- Idempotent: tables / indexes `if not exists`, seeds `on conflict do nothing`, functions `create or replace`, policies re-created.

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Benin Gist, category `gist`)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('gist.enabled', 'true', 'gist', 'Benin Gist on',
 'Master switch. Off = nobody can post, like, comment, create / join groups or send group messages. Old content stays hidden behind a "resting" message.', 'bool', null, null),
('gist.photos_enabled', 'false', 'gist', 'Photos in gists on',
 'Players can add one photo to a gist. The phone shrinks it first (about 1080 px, under the size limit below). Photos live in Supabase Storage (bucket gist-photos), so keep this off on a tight storage plan.', 'bool', null, null),
('gist.photo_max_kb', '300', 'gist', 'Biggest photo (KB)',
 'A photo bigger than this after the phone shrinks it is refused by the server. The bucket itself never takes more than 512 KB.', 'number', 50, 500),
('gist.post_max_len', '280', 'gist', 'Longest gist (characters)',
 'A gist longer than this is refused.', 'number', 20, 1000),
('gist.comment_max_len', '200', 'gist', 'Longest comment (characters)',
 'A comment or reply longer than this is refused.', 'number', 10, 1000),
('gist.message_max_len', '500', 'gist', 'Longest group message (characters)',
 'A group message longer than this is refused.', 'number', 20, 2000),
('gist.min_account_minutes', '30', 'gist', 'New accounts wait before posting (real minutes)',
 'A brand-new Sim must be this old before it can post, comment, like, create or write in groups (slows spam accounts). Reading is always allowed. 0 = no wait.', 'minutes', 0, 10080),
('gist.posts_per_hour', '6', 'gist', 'Posts per hour',
 'Rate limit: the most gists one player can post in any real hour.', 'number', 1, 120),
('gist.comments_per_minute', '6', 'gist', 'Comments per minute',
 'Rate limit: the most comments and replies one player can write in any real minute.', 'number', 1, 60),
('gist.likes_per_minute', '40', 'gist', 'Likes per minute',
 'Rate limit: the most likes one player can give in any real minute.', 'number', 1, 300),
('gist.group_messages_per_minute', '20', 'gist', 'Group messages per minute',
 'Rate limit: the most group messages (text, voice, money) one player can send in any real minute, across all groups.', 'number', 1, 120),
('gist.groups_per_day', '3', 'gist', 'Groups a player can create per day',
 'Rate limit: new groups one player can create in any real 24 hours.', 'number', 1, 50),
('gist.group_member_cap', '200', 'gist', 'Most members in a group',
 'Default cap for every group. A starter group can have its own cap in Admin -> Gist -> Groups. Realtime cost grows with the people who have one group open, so raise slowly.', 'number', 2, 5000),
('gist.max_groups_joined', '50', 'gist', 'Most groups a player can be in',
 'Joining or being added is refused above this.', 'number', 1, 500),
('gist.max_follows', '500', 'gist', 'Most people a player can follow',
 'Upper limit on a player''s Following list.', 'number', 1, 5000),
('gist.add_friends_only', 'true', 'gist', 'Group admins can only add friends',
 'On = an owner or admin can add a player to a group only if they are accepted friends (stops strangers adding people to junk groups). Public groups can always be joined by anyone.', 'bool', null, null),
('gist.feed_page', '20', 'gist', 'Gists per feed page',
 'How many gists the feed loads each time (pull to refresh, then "Load more").', 'number', 5, 50),
('gist.hot_half_life_hours', '12', 'gist', 'For you: half-life (hours)',
 'Time decay of the For you feed. A gist loses half its pull every this many hours. Applies to new activity; old gists keep the ranking they earned until someone likes or comments again.', 'number', 1, 720),
('gist.like_weight', '1', 'gist', 'For you: weight of a like', 'Score = ln(1 + likes x this + comments x the next setting) plus the time term.', 'number', 0, 100),
('gist.comment_weight', '3', 'gist', 'For you: weight of a comment', 'A comment counts this many likes in the For you score.', 'number', 0, 100),
('gist.group_half_life_hours', '12', 'gist', 'Discover: activity half-life (hours)',
 'How fast a group''s "most active" score fades without new messages.', 'number', 1, 720),
('gist.report_hide_count', '3', 'gist', 'Reports that hide a gist, comment or message',
 'It is hidden automatically once this many different players report it. Groups are never hidden by reports: an admin decides (Admin -> Gist).', 'number', 1, 100),
('gist.post_keep_days', '60', 'gist', 'Keep gists for (days)',
 'Older gists (with their comments and likes) are deleted a few at a time. Photo files of deleted gists are removed from Admin -> Gist -> Photo clean-up.', 'number', 1, 3650),
('gist.message_keep_days', '30', 'gist', 'Keep group messages for (days)',
 'Older group messages are deleted a few at a time.', 'number', 1, 3650),
('gist.notify_window_minutes', '30', 'gist', 'Batch likes and comments for (minutes)',
 'Likes, comments, replies and mentions on the same gist inside this window become ONE alert that counts up ("5 people liked your gist").', 'number', 1, 1440),
('gist.places', '"Ring Road, Ugbowo, GRA, Oba Market, Uselu, Ekenwan, Sapele Road, Airport Road, Akpakpava, Aduwawa, New Benin, Ikpoba Hill"', 'gist', 'Place tags',
 'Comma-separated real Benin City places shown as quick #tag chips when someone writes a gist.', 'text', null, null)
on conflict (key) do nothing;

update public.game_config set description = 'E2: players can tip each other. Benin Gist has a Tip button on every gist (docs/GIST.md); off = no tips anywhere.'
 where key = 'tips.enabled' and description like '%no screen yet%';

-- ---------------------------------------------------------------------------------------------
-- 2. Tables (user ids are plain uuid columns; links to profiles are in 20261031000200_gist_links.sql)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.gist_posts (
  id            bigserial primary key,
  user_id       uuid not null,
  body          text not null default '' check (char_length(body) <= 1000),
  photo_path    text,
  tags          text[] not null default '{}',
  like_count    int not null default 0,
  comment_count int not null default 0,
  tip_count     int not null default 0,
  tip_total     bigint not null default 0,
  report_count  int not null default 0,
  hidden        boolean not null default false,
  hidden_reason text,
  rank_key      bigint not null default 0,
  created_at    timestamptz not null default now(),
  check (char_length(body) > 0 or photo_path is not null)
);
create index if not exists gist_posts_rank_idx on public.gist_posts (rank_key desc, id desc) where not hidden;
create index if not exists gist_posts_new_idx  on public.gist_posts (id desc) where not hidden;
create index if not exists gist_posts_user_idx on public.gist_posts (user_id, id desc);
create index if not exists gist_posts_age_idx  on public.gist_posts (created_at);
create index if not exists gist_posts_tags_idx on public.gist_posts using gin (tags) where not hidden;
create unique index if not exists gist_posts_photo_idx on public.gist_posts (photo_path) where photo_path is not null;

create table if not exists public.gist_comments (
  id            bigserial primary key,
  post_id       bigint not null references public.gist_posts(id) on delete cascade,
  parent_id     bigint references public.gist_comments(id) on delete cascade,
  user_id       uuid not null,
  reply_to_user uuid,
  reply_to_name text,
  body          text not null check (char_length(body) between 1 and 1000),
  report_count  int not null default 0,
  hidden        boolean not null default false,
  created_at    timestamptz not null default now()
);
create index if not exists gist_comments_post_idx   on public.gist_comments (post_id, id) where parent_id is null;
create index if not exists gist_comments_parent_idx on public.gist_comments (parent_id, id) where parent_id is not null;
create index if not exists gist_comments_user_idx   on public.gist_comments (user_id, created_at desc);

create table if not exists public.gist_likes (
  post_id    bigint not null references public.gist_posts(id) on delete cascade,
  user_id    uuid not null,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index if not exists gist_likes_user_idx on public.gist_likes (user_id, created_at desc);

create table if not exists public.gist_follows (
  follower   uuid not null,
  followee   uuid not null,
  created_at timestamptz not null default now(),
  primary key (follower, followee),
  check (follower <> followee)
);
create index if not exists gist_follows_followee_idx on public.gist_follows (followee);

create table if not exists public.gist_bans (
  user_id    uuid primary key,
  until_at   timestamptz,
  reason     text,
  banned_by  uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.gist_groups (
  id            bigserial primary key,
  slug          text unique,
  name          text not null check (char_length(name) between 3 and 40),
  emoji         text not null default '💬',
  description   text not null default '' check (char_length(description) <= 300),
  is_public     boolean not null default true,
  system        boolean not null default false,
  owner_id      uuid,
  member_cap    int,
  member_count  int not null default 0,
  pinned_id     bigint,
  last_msg_id   bigint not null default 0,
  last_msg_at   timestamptz,
  last_msg_user text,
  last_msg_text text,
  act_key       double precision,
  hidden        boolean not null default false,
  created_at    timestamptz not null default now()
);
create index if not exists gist_groups_discover_idx on public.gist_groups (act_key desc nulls last, id desc) where is_public and not hidden;
create index if not exists gist_groups_new_idx      on public.gist_groups (id desc) where is_public and not hidden;
create index if not exists gist_groups_big_idx      on public.gist_groups (member_count desc, id desc) where is_public and not hidden;
create index if not exists gist_groups_owner_idx    on public.gist_groups (owner_id, created_at desc) where owner_id is not null;

create table if not exists public.gist_group_members (
  group_id     bigint not null references public.gist_groups(id) on delete cascade,
  user_id      uuid not null,
  role         text not null default 'member' check (role in ('owner', 'admin', 'member')),
  muted_until  timestamptz,
  last_read_id bigint not null default 0,
  joined_at    timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists gist_group_members_user_idx on public.gist_group_members (user_id, group_id);

create table if not exists public.gist_group_bans (
  group_id   bigint not null references public.gist_groups(id) on delete cascade,
  user_id    uuid not null,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.gist_messages (
  id               bigserial primary key,
  group_id         bigint not null references public.gist_groups(id) on delete cascade,
  user_id          uuid not null,
  username         text not null,
  kind             text not null default 'text' check (kind in ('text', 'voice', 'money', 'system')),
  body             text check (body is null or char_length(body) <= 2000),
  audio_path       text,
  audio_mime       text,
  money_amount     bigint check (money_amount is null or money_amount > 0),
  money_to         uuid,
  money_to_username text,
  reply_to         bigint references public.gist_messages(id) on delete set null,
  report_count     int not null default 0,
  hidden           boolean not null default false,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  check (deleted_at is not null
         or (kind = 'text' and body is not null and audio_path is null)
         or (kind = 'voice' and audio_path is not null and audio_mime is not null)
         or (kind = 'money' and money_amount is not null and money_to is not null)
         or kind = 'system')
);
create index if not exists gist_messages_group_idx on public.gist_messages (group_id, id desc);
create index if not exists gist_messages_user_idx  on public.gist_messages (user_id, created_at desc);
create index if not exists gist_messages_age_idx   on public.gist_messages (created_at);
create unique index if not exists gist_messages_audio_idx on public.gist_messages (audio_path) where audio_path is not null;

create table if not exists public.gist_reports (
  id          bigserial primary key,
  kind        text not null check (kind in ('post', 'comment', 'group', 'message')),
  target_id   bigint not null,
  reporter_id uuid not null,
  reason      text,
  status      text not null default 'open' check (status in ('open', 'done')),
  created_at  timestamptz not null default now(),
  unique (kind, target_id, reporter_id)
);
create index if not exists gist_reports_open_idx on public.gist_reports (kind, target_id) where status = 'open';
create index if not exists gist_reports_reporter_idx on public.gist_reports (reporter_id);

-- one alert row per (player, kind, target) inside the batching window: "5 people liked your gist"
create table if not exists public.gist_notify (
  user_id    uuid not null,
  kind       text not null,
  target_id  bigint not null,
  n          int not null default 1,
  event_id   bigint,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, kind, target_id)
);
create index if not exists gist_notify_age_idx on public.gist_notify (updated_at);

-- tiny key/value cache (trending tags, sweep claim)
create table if not exists public.gist_cache (
  key   text primary key,
  value jsonb not null default '{}'::jsonb,
  at    timestamptz not null default now()
);

alter table public.gist_posts         enable row level security;
alter table public.gist_comments      enable row level security;
alter table public.gist_likes         enable row level security;
alter table public.gist_follows       enable row level security;
alter table public.gist_bans          enable row level security;
alter table public.gist_groups        enable row level security;
alter table public.gist_group_members enable row level security;
alter table public.gist_group_bans    enable row level security;
alter table public.gist_messages      enable row level security;
alter table public.gist_reports       enable row level security;
alter table public.gist_notify        enable row level security;
alter table public.gist_cache         enable row level security;

revoke all on public.gist_posts, public.gist_comments, public.gist_likes, public.gist_follows, public.gist_bans, public.gist_groups,
              public.gist_group_members, public.gist_group_bans, public.gist_messages, public.gist_reports, public.gist_notify,
              public.gist_cache from anon, authenticated;
revoke all on sequence public.gist_posts_id_seq, public.gist_comments_id_seq, public.gist_groups_id_seq, public.gist_messages_id_seq,
                       public.gist_reports_id_seq from anon, authenticated;
-- The ONLY direct read: group messages, for the one open group's Realtime channel.
grant select on public.gist_messages to authenticated;

-- membership + not blocked either way. Used by the policy below and by the voice-note storage policy.
create or replace function public.gist_can_read(p_group bigint, p_author uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null
     and exists (select 1 from public.gist_group_members m where m.group_id = p_group and m.user_id = auth.uid())
     and not exists (select 1 from public.chat_blocks b
                      where (b.blocker_id = auth.uid() and b.blocked_id = p_author)
                         or (b.blocker_id = p_author and b.blocked_id = auth.uid()))
$$;
revoke all on function public.gist_can_read(bigint, uuid) from public, anon;
grant execute on function public.gist_can_read(bigint, uuid) to authenticated;

create or replace function public.gist_is_member(p_group bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null
     and exists (select 1 from public.gist_group_members m where m.group_id = p_group and m.user_id = auth.uid())
$$;
revoke all on function public.gist_is_member(bigint) from public, anon;
grant execute on function public.gist_is_member(bigint) to authenticated;

drop policy if exists gist_messages_member on public.gist_messages;
create policy gist_messages_member on public.gist_messages for select to authenticated
  using (not hidden and public.gist_can_read(group_id, user_id));

-- Realtime: INSERT / UPDATE events reach only subscribers who pass the policy (members, not blocked).
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'gist_messages') then
    alter publication supabase_realtime add table public.gist_messages;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. Storage: gist photos (public bucket, tiny files, images only) + group voice notes (reuse player-voice)
-- ---------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('gist-photos', 'gist-photos', true, 524288, array['image/jpeg', 'image/webp', 'image/png']::text[])
on conflict (id) do update set public = true, file_size_limit = 524288, allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.gist_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin and not banned from public.profiles where id = auth.uid()), false)
$$;
revoke all on function public.gist_is_admin() from public, anon;
grant execute on function public.gist_is_admin() to authenticated;

create or replace function public.gist_photos_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from public.game_config where key = 'gist.enabled'), false)
     and coalesce((select (value #>> '{}')::boolean from public.game_config where key = 'gist.photos_enabled'), false)
$$;
revoke all on function public.gist_photos_on() from public, anon;
grant execute on function public.gist_photos_on() to authenticated;

-- is this file used by a gist / a group message? (security definer: the player has no direct access to those tables)
create or replace function public.gist_file_used(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.gist_posts p where p.photo_path = p_name)
      or exists (select 1 from public.gist_messages m where m.audio_path = p_name)
$$;
revoke all on function public.gist_file_used(text) from public, anon;
grant execute on function public.gist_file_used(text) to authenticated;

drop policy if exists gist_photo_read on storage.objects;
create policy gist_photo_read on storage.objects for select to authenticated using (bucket_id = 'gist-photos');
drop policy if exists gist_photo_upload on storage.objects;
create policy gist_photo_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'gist-photos' and (storage.foldername(name))[1] = auth.uid()::text and public.gist_photos_on());
-- delete: your own file while no gist uses it (a failed post), or an admin (photo clean-up)
drop policy if exists gist_photo_cleanup on storage.objects;
create policy gist_photo_cleanup on storage.objects for delete to authenticated using (
  bucket_id = 'gist-photos' and (
    public.gist_is_admin()
    or ((storage.foldername(name))[1] = auth.uid()::text and not public.gist_file_used(name))));

-- group voice notes: player-voice/group/<group id>/<sender id>/<uuid>.<ext>. Extra policies only: the DM / house-chat policies are untouched.
drop policy if exists gist_voice_read on storage.objects;
create policy gist_voice_read on storage.objects for select to authenticated using (
  bucket_id = 'player-voice' and (storage.foldername(name))[1] = 'group' and (storage.foldername(name))[2] ~ '^[0-9]+$'
  and public.gist_is_member(((storage.foldername(name))[2])::bigint));
drop policy if exists gist_voice_upload on storage.objects;
create policy gist_voice_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'player-voice' and (storage.foldername(name))[1] = 'group' and (storage.foldername(name))[2] ~ '^[0-9]+$'
  and (storage.foldername(name))[3] = auth.uid()::text and public.gist_is_member(((storage.foldername(name))[2])::bigint));
drop policy if exists gist_voice_cleanup on storage.objects;
create policy gist_voice_cleanup on storage.objects for delete to authenticated using (
  bucket_id = 'player-voice' and (storage.foldername(name))[1] = 'group' and (storage.foldername(name))[3] = auth.uid()::text
  and not public.gist_file_used(name));

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers (bl_gist_*; revoked from clients at the end)
-- ---------------------------------------------------------------------------------------------
-- The caller for Benin Gist. Reads need an account + the master switch. Writes also need: not muted (profiles.chat_muted_until,
-- the existing chat mute), not banned from Gist, old enough. Writes take a per-player advisory lock (rate limits can't be raced)
-- and never write to profiles (no profile realtime echo).
create or replace function public.bl_gist_me(p_write boolean default false) returns public.profiles
language plpgsql set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v profiles; v_now timestamptz := bl_now(); v_ban gist_bans; v_age numeric;
begin
  select * into v from profiles where id = v_uid;
  if not found then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v.banned then
    raise exception 'This account has been banned. If this is a mistake, contact the admin.' using errcode = 'P0001', hint = 'banned';
  end if;
  if not v.home_chosen then
    raise exception 'Hold on, choose where you will live first.' using errcode = 'P0001', hint = 'no_home';
  end if;
  if not bl_cfg_bool('gist.enabled') then
    raise exception 'Benin Gist is resting for now. Try again later.' using errcode = 'P0001', hint = 'gist_off';
  end if;
  if p_write then
    perform pg_advisory_xact_lock(hashtextextended('gist:' || v_uid::text, 0));
    if v.chat_muted_until is not null and v.chat_muted_until > v_now then
      raise exception 'You can''t post for now (muted by a moderator). Try again in about % min.',
        ceil(extract(epoch from v.chat_muted_until - v_now) / 60) using errcode = 'P0001', hint = 'muted';
    end if;
    select * into v_ban from gist_bans where user_id = v_uid;
    if found and (v_ban.until_at is null or v_ban.until_at > v_now) then
      raise exception 'You are banned from Benin Gist%.', case when v_ban.until_at is null then '' else ' for now' end
        using errcode = 'P0001', hint = 'gist_banned';
    end if;
    v_age := bl_cfg('gist.min_account_minutes');
    if v_age > 0 and v.created_at > v_now - make_interval(secs => (v_age * 60)::double precision) then
      raise exception 'New Sims can join the gist after % minutes. Look around first!', ceil(v_age) using errcode = 'P0001', hint = 'too_new';
    end if;
  end if;
  return v;
end $$;

-- trim, no control characters, mask bad words. Raises when empty (unless allowed) or too long.
create or replace function public.bl_gist_text(p_text text, p_max int, p_allow_empty boolean default false) returns text
language plpgsql stable set search_path = public as $$
declare v text := bl_chat_clean(p_text);
begin
  if v = '' then
    if p_allow_empty then return ''; end if;
    raise exception 'Type something first.' using errcode = 'P0001', hint = 'empty';
  end if;
  if char_length(v) > p_max then
    raise exception 'That is too long. Keep it under % characters.', p_max using errcode = 'P0001', hint = 'too_long';
  end if;
  return bl_chat_mask(v);
end $$;

-- the For you key, in millionths (a bigint cursor round-trips through JSON exactly; floats do not)
create or replace function public.bl_gist_rank(p_likes int, p_comments int, p_created timestamptz) returns bigint
language sql stable set search_path = public as $$
  select round((ln(1 + greatest(0, p_likes) * bl_cfg('gist.like_weight')::float8 + greatest(0, p_comments) * bl_cfg('gist.comment_weight')::float8)
         + extract(epoch from p_created)::float8 / 3600.0 * ln(2.0::float8) / greatest(1, bl_cfg('gist.hot_half_life_hours'))::float8) * 1000000)::bigint
$$;

create or replace function public.bl_gist_lse(a double precision, b double precision) returns double precision
language sql immutable as $$
  select greatest(a, b) + ln(1 + exp(-abs(a - b)))
$$;

create or replace function public.bl_gist_blocked(p_a uuid, p_b uuid) returns boolean
language sql stable set search_path = public as $$
  select exists (select 1 from chat_blocks b where (b.blocker_id = p_a and b.blocked_id = p_b) or (b.blocker_id = p_b and b.blocked_id = p_a))
$$;

create or replace function public.bl_gist_user(p_id uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar)
    from profiles p where p.id = p_id
$$;

create or replace function public.bl_gist_post_json(p public.gist_posts, p_me uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'user', bl_gist_user(p.user_id), 'body', p.body, 'photo_path', p.photo_path, 'tags', to_jsonb(p.tags),
    'likes', p.like_count, 'comments', p.comment_count, 'tips', p.tip_count, 'tip_total', p.tip_total,
    'liked', exists (select 1 from gist_likes l where l.post_id = p.id and l.user_id = p_me),
    'mine', p.user_id = p_me, 'created_at', p.created_at)
$$;

create or replace function public.bl_gist_msg_json(m public.gist_messages, p_me uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', m.id, 'group_id', m.group_id, 'user_id', m.user_id, 'username', m.username,
    'avatar', (select pr.avatar from profiles pr where pr.id = m.user_id),
    'kind', m.kind, 'body', m.body, 'audio_path', m.audio_path, 'audio_mime', m.audio_mime,
    'amount', m.money_amount, 'to_user', m.money_to, 'to_username', m.money_to_username,
    'reply_to', m.reply_to,
    'reply', case when m.reply_to is null then null else (
        select jsonb_build_object('id', r.id, 'username', r.username,
                 'snippet', case when r.deleted_at is not null then null
                                 when r.kind = 'money' then '💸 ₦' || to_char(r.money_amount, 'FM999,999,999,999') || ' to @' || r.money_to_username
                                 else left(r.body, 140) end,
                 'voice', r.kind = 'voice' and r.deleted_at is null, 'deleted', r.deleted_at is not null)
          from gist_messages r where r.id = m.reply_to) end,
    'created_at', m.created_at, 'deleted_at', m.deleted_at, 'mine', m.user_id = p_me)
$$;

-- my role in a group: owner / admin / member, null when not in it. A game admin counts as 'admin' everywhere (even as a plain member).
create or replace function public.bl_gist_role(p_group bigint, p_uid uuid) returns text
language sql stable set search_path = public as $$
  select case when v.role in ('owner', 'admin') then v.role
              when exists (select 1 from profiles where id = p_uid and is_admin and not banned) then 'admin'
              else v.role end
    from (select (select m.role from gist_group_members m where m.group_id = p_group and m.user_id = p_uid) as role) v
$$;

create or replace function public.bl_gist_group_json(g public.gist_groups, p_me uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', g.id, 'name', g.name, 'emoji', g.emoji, 'description', g.description, 'is_public', g.is_public, 'system', g.system,
    'owner_id', g.owner_id, 'members', g.member_count,
    'cap', coalesce(g.member_cap, bl_cfg('gist.group_member_cap')::int), 'hidden', g.hidden,
    'last_msg_at', g.last_msg_at, 'last_msg_user', g.last_msg_user, 'last_msg_text', g.last_msg_text,
    'created_at', g.created_at,
    'role', (select m.role from gist_group_members m where m.group_id = g.id and m.user_id = p_me),
    'muted_until', (select m.muted_until from gist_group_members m where m.group_id = g.id and m.user_id = p_me),
    'unread', coalesce((select case when g.last_msg_id > m.last_read_id then
                          (select count(*) from (select 1 from gist_messages x where x.group_id = g.id and x.id > m.last_read_id
                                                   and x.user_id <> p_me and not x.hidden limit 100) c) else 0 end::int
                          from gist_group_members m where m.group_id = g.id and m.user_id = p_me), 0))
$$;

-- "@name" mentions in a text: up to 5 distinct real, not banned, not the author. p_group: only members of that group.
create or replace function public.bl_gist_mentions(p_body text, p_author uuid, p_group bigint default null) returns setof uuid
language sql stable set search_path = public as $$
  select p.id from (
    select distinct lower(x[1]) as n from regexp_matches(coalesce(p_body, ''), '@([A-Za-z0-9_]{3,20})', 'g') as t(x) limit 5) m
    join profiles p on lower(p.username) = m.n
   where p.id <> p_author and not p.banned
     and (p_group is null or exists (select 1 from gist_group_members gm where gm.group_id = p_group and gm.user_id = p.id))
$$;

-- ONE alert per (player, kind, target) per window. The first one inserts an `events` row (live in Alerts) and queues a push; later ones inside
-- the window count up the same row ("5 people liked your gist") and fold into the pending push. Never raises: a notification problem must
-- never break a post, like or message. p_cat is a push category (messages, friends, events).
create or replace function public.bl_gist_notify(p_user uuid, p_kind text, p_target bigint, p_actor uuid, p_title_one text, p_title_many text,
                                                 p_body text, p_url text, p_cat text, p_data jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_win interval := make_interval(mins => greatest(1, bl_cfg('gist.notify_window_minutes'))::int);
  v_now timestamptz := bl_now();
  ex    gist_notify;
  v_ev  bigint;
begin
  if p_user is null or p_user = p_actor then return; end if;
  if exists (select 1 from profiles where id = p_user and banned) then return; end if;
  if p_actor is not null and bl_gist_blocked(p_user, p_actor) then return; end if;
  select * into ex from gist_notify where user_id = p_user and kind = p_kind and target_id = p_target for update;
  if found and ex.started_at > v_now - v_win and ex.event_id is not null
     and exists (select 1 from events where id = ex.event_id) then
    update gist_notify set n = ex.n + 1, updated_at = v_now where user_id = p_user and kind = p_kind and target_id = p_target;
    update events set title = replace(p_title_many, '{n}', (ex.n + 1)::text), body = coalesce(p_body, ''),
                      data = data || jsonb_build_object('n', ex.n + 1)
     where id = ex.event_id;
  else
    v_ev := bl_event(p_user, p_kind, p_title_one, coalesce(p_body, ''), coalesce(p_data, '{}'::jsonb) || jsonb_build_object('n', 1, 'target', p_target));
    insert into gist_notify (user_id, kind, target_id, n, event_id, started_at, updated_at)
    values (p_user, p_kind, p_target, 1, v_ev, v_now, v_now)
    on conflict (user_id, kind, target_id) do update set n = 1, event_id = v_ev, started_at = v_now, updated_at = v_now;
  end if;
  perform bl_push_enqueue(p_user, p_cat, p_kind, p_title_one, coalesce(p_body, ''), p_url, p_actor, 'gist:' || p_kind || ':' || p_target,
                          null, null, true, p_title_many);
exception when others then
  return;
end $$;

-- a cheap lazy claim (once per window) so housekeeping and the trending cache never run on every request
create or replace function public.bl_gist_claim(p_key text, p_every interval) returns boolean
language plpgsql set search_path = public as $$
declare v_n int;
begin
  insert into gist_cache (key, value, at) values (p_key, '{}'::jsonb, 'epoch') on conflict (key) do nothing;
  update gist_cache set at = now() where key = p_key and at < now() - p_every;
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;

-- lazy housekeeping (claimed once per 30 minutes, small batches): old gists, old group messages, stale alert rows, empty groups
create or replace function public.bl_gist_sweep() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not bl_gist_claim('sweep', interval '30 minutes') then return; end if;
  delete from gist_posts where id in (
    select id from gist_posts where created_at < now() - make_interval(days => bl_cfg('gist.post_keep_days')::int) order by created_at limit 500);
  delete from gist_messages where id in (
    select id from gist_messages where created_at < now() - make_interval(days => bl_cfg('gist.message_keep_days')::int) order by created_at limit 2000);
  delete from gist_notify where updated_at < now() - interval '3 days';
  delete from gist_reports where status = 'done' and created_at < now() - interval '30 days';
  delete from gist_groups g where not g.system and g.member_count <= 0 and g.created_at < now() - interval '1 day'
     and not exists (select 1 from gist_group_members m where m.group_id = g.id);
exception when others then
  return;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Player RPCs: summary, feed, posts
-- ---------------------------------------------------------------------------------------------
-- One call when the app opens: switches, limits, whether I can post (and why not), unread groups.
create or replace function public.gist_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_now timestamptz := bl_now(); v profiles; v_ban gist_bans; v_why text; v_hint text; v_unread int;
  v_groups int;
begin
  select * into v from profiles where id = v_uid;
  if not found then raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile'; end if;
  select * into v_ban from gist_bans where user_id = v_uid;
  if not bl_cfg_bool('gist.enabled') then v_why := 'Benin Gist is resting for now.'; v_hint := 'gist_off';
  elsif v.chat_muted_until is not null and v.chat_muted_until > v_now then v_why := 'You are muted by a moderator for now.'; v_hint := 'muted';
  elsif v_ban.user_id is not null and (v_ban.until_at is null or v_ban.until_at > v_now) then v_why := 'You are banned from Benin Gist.'; v_hint := 'gist_banned';
  elsif bl_cfg('gist.min_account_minutes') > 0 and v.created_at > v_now - make_interval(secs => (bl_cfg('gist.min_account_minutes') * 60)::double precision) then
    v_why := 'New Sims can join the gist after ' || ceil(bl_cfg('gist.min_account_minutes')) || ' minutes.'; v_hint := 'too_new';
  end if;
  select count(*)::int, count(*) filter (where g.last_msg_id > m.last_read_id)::int into v_groups, v_unread
    from gist_group_members m join gist_groups g on g.id = m.group_id where m.user_id = v_uid;
  return jsonb_build_object(
    'enabled', bl_cfg_bool('gist.enabled'), 'photos_enabled', bl_cfg_bool('gist.photos_enabled'),
    'photo_max_kb', bl_cfg('gist.photo_max_kb')::int, 'post_max_len', bl_cfg('gist.post_max_len')::int,
    'comment_max_len', bl_cfg('gist.comment_max_len')::int, 'message_max_len', bl_cfg('gist.message_max_len')::int,
    'feed_page', bl_cfg('gist.feed_page')::int, 'group_cap', bl_cfg('gist.group_member_cap')::int,
    'places', (select coalesce(jsonb_agg(btrim(x)), '[]'::jsonb) from unnest(string_to_array(bl_cfg_text('gist.places'), ',')) x where btrim(x) <> ''),
    'can_post', v_why is null, 'why', v_why, 'why_hint', v_hint,
    'my_groups', v_groups, 'unread_groups', v_unread);
end $$;

-- A gist. Text (cleaned, bad words masked) and optionally one photo already uploaded to gist-photos/<my id>/<uuid>.<ext>.
create or replace function public.gist_post(p_body text, p_photo_path text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_gist_me(true); v_now timestamptz := bl_now(); v_body text; v_tags text[]; v_size bigint; v_n int; p gist_posts; r uuid;
begin
  v_body := bl_gist_text(p_body, bl_cfg('gist.post_max_len')::int, p_photo_path is not null);
  if v_body = '' and p_photo_path is null then
    raise exception 'Type something first.' using errcode = 'P0001', hint = 'empty';
  end if;
  select count(*) into v_n from gist_posts where user_id = v_me.id and created_at > v_now - interval '1 hour';
  if v_n >= bl_cfg('gist.posts_per_hour') then
    raise exception 'You have posted a lot this hour. Take a short break and come back.' using errcode = 'P0001', hint = 'too_fast';
  end if;
  if v_body <> '' and exists (select 1 from gist_posts where user_id = v_me.id and created_at > v_now - interval '10 minutes'
                                 and lower(regexp_replace(body, '\W', '', 'g')) = lower(regexp_replace(v_body, '\W', '', 'g'))) then
    raise exception 'You just posted that. Say something new.' using errcode = 'P0001', hint = 'duplicate';
  end if;
  if p_photo_path is not null then
    if not bl_cfg_bool('gist.photos_enabled') then
      raise exception 'Photos are switched off for now.' using errcode = 'P0001', hint = 'photos_off';
    end if;
    if p_photo_path !~ ('^' || v_me.id::text || '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$') then
      raise exception 'That photo did not upload properly. Try again.' using errcode = 'P0001', hint = 'bad_photo';
    end if;
    select (o.metadata ->> 'size')::bigint into v_size from storage.objects o where o.bucket_id = 'gist-photos' and o.name = p_photo_path;
    if not found then
      raise exception 'That photo did not finish uploading. Try again.' using errcode = 'P0001', hint = 'bad_photo';
    end if;
    if coalesce(v_size, 0) > bl_cfg('gist.photo_max_kb') * 1024 then
      raise exception 'That photo is too big (the limit is % KB).', bl_cfg('gist.photo_max_kb')::int using errcode = 'P0001', hint = 'photo_too_big';
    end if;
    if exists (select 1 from gist_posts where photo_path = p_photo_path) then
      raise exception 'That photo is already used.' using errcode = 'P0001', hint = 'bad_photo';
    end if;
  end if;
  -- up to 3 distinct #tags
  select coalesce(array_agg(t order by first_at), '{}') into v_tags from (
    select lower(x[1]) as t, min(ord) as first_at from regexp_matches(v_body, '#([A-Za-z0-9_]{2,24})', 'g') with ordinality as m(x, ord)
     group by lower(x[1]) order by min(ord) limit 3) s;
  insert into gist_posts (user_id, body, photo_path, tags, rank_key, created_at)
  values (v_me.id, v_body, p_photo_path, v_tags, bl_gist_rank(0, 0, v_now), v_now) returning * into p;
  for r in select * from bl_gist_mentions(v_body, v_me.id) loop
    perform bl_gist_notify(r, 'gist_mention', p.id, v_me.id, '@' || v_me.username || ' mentioned you', '{n} people mentioned you',
                           bl_push_preview(v_body, 80), '/play?go=gist:post:' || p.id, 'messages', jsonb_build_object('post_id', p.id));
  end loop;
  perform bl_gist_sweep();
  return bl_gist_post_json(p, v_me.id);
end $$;

-- The feed. view 'foryou' (cursor = rank_key + id), 'following' (friends + people I follow + me; cursor = id) or 'new' (everyone, newest).
-- p_tag filters one #tag. Blocked pairs and hidden gists never appear. Returns {posts, next}; next is null at the end.
create or replace function public.gist_feed(p_view text default 'foryou', p_key bigint default null, p_id bigint default null,
                                            p_limit int default null, p_tag text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_me profiles := bl_gist_me(false); v_uid uuid := v_me.id;
  v_lim int := least(greatest(coalesce(p_limit, bl_cfg('gist.feed_page')::int), 1), 50);
  v_tag text := nullif(lower(btrim(coalesce(p_tag, ''))), '');
  v_rows gist_posts[]; v_next jsonb := null;
begin
  if p_view = 'following' then
    v_rows := array(
      select p from gist_posts p
       where not p.hidden and (p_id is null or p.id < p_id)
         and (v_tag is null or p.tags @> array[v_tag])
         and (p.user_id = v_uid
              or p.user_id in (select f.followee from gist_follows f where f.follower = v_uid)
              or p.user_id in (select case when fr.user_a = v_uid then fr.user_b else fr.user_a end
                                 from player_friendships fr where fr.status = 'accepted' and v_uid in (fr.user_a, fr.user_b)))
         and not exists (select 1 from chat_blocks b where (b.blocker_id = v_uid and b.blocked_id = p.user_id) or (b.blocker_id = p.user_id and b.blocked_id = v_uid))
       order by p.id desc limit v_lim + 1);
  elsif p_view in ('new', 'tag') then
    v_rows := array(
      select p from gist_posts p
       where not p.hidden and (p_id is null or p.id < p_id) and (v_tag is null or p.tags @> array[v_tag])
         and not exists (select 1 from chat_blocks b where (b.blocker_id = v_uid and b.blocked_id = p.user_id) or (b.blocker_id = p.user_id and b.blocked_id = v_uid))
       order by p.id desc limit v_lim + 1);
  else
    v_rows := array(
      select p from gist_posts p
       where not p.hidden and (p_key is null or (p.rank_key, p.id) < (p_key, p_id))
         and (v_tag is null or p.tags @> array[v_tag])
         and not exists (select 1 from chat_blocks b where (b.blocker_id = v_uid and b.blocked_id = p.user_id) or (b.blocker_id = p.user_id and b.blocked_id = v_uid))
       order by p.rank_key desc, p.id desc limit v_lim + 1);
  end if;
  if coalesce(array_length(v_rows, 1), 0) > v_lim then
    v_rows := v_rows[1:v_lim];
    v_next := jsonb_build_object('key', (v_rows[v_lim]).rank_key, 'id', (v_rows[v_lim]).id);
  end if;
  return jsonb_build_object('posts', coalesce((select jsonb_agg(bl_gist_post_json(v_rows[i], v_uid) order by i) from generate_subscripts(v_rows, 1) i), '[]'::jsonb),
                            'next', v_next);
end $$;

create or replace function public.gist_post_get(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); p gist_posts;
begin
  select * into p from gist_posts where id = p_id and not hidden;
  if not found or bl_gist_blocked(v_me.id, p.user_id) then
    raise exception 'That gist is not there any more.' using errcode = 'P0001', hint = 'not_found';
  end if;
  return bl_gist_post_json(p, v_me.id);
end $$;

create or replace function public.gist_delete_post(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); p gist_posts;
begin
  select * into p from gist_posts where id = p_id and user_id = v_me.id;
  if not found then
    raise exception 'That gist is not yours or is already gone.' using errcode = 'P0001', hint = 'not_found';
  end if;
  delete from gist_posts where id = p.id;
  return jsonb_build_object('message', 'Gist deleted.', 'id', p.id, 'photo_path', p.photo_path);
end $$;

-- like / unlike. Counts are cached on the post; the For you key moves with them.
create or replace function public.gist_like(p_post bigint, p_like boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(true); v_now timestamptz := bl_now(); p gist_posts; v_n int; v_changed int;
begin
  select * into p from gist_posts where id = p_post and not hidden;
  if not found or bl_gist_blocked(v_me.id, p.user_id) then
    raise exception 'That gist is not there any more.' using errcode = 'P0001', hint = 'not_found';
  end if;
  if p_like then
    select count(*) into v_n from gist_likes where user_id = v_me.id and created_at > v_now - interval '1 minute';
    if v_n >= bl_cfg('gist.likes_per_minute') then
      raise exception 'Easy! You are liking too fast.' using errcode = 'P0001', hint = 'too_fast';
    end if;
    insert into gist_likes (post_id, user_id, created_at) values (p.id, v_me.id, v_now) on conflict do nothing;
    get diagnostics v_changed = row_count;
    if v_changed > 0 then
      update gist_posts set like_count = like_count + 1 where id = p.id returning * into p;
      update gist_posts set rank_key = bl_gist_rank(p.like_count, p.comment_count, p.created_at) where id = p.id returning * into p;
      perform bl_gist_notify(p.user_id, 'gist_like', p.id, v_me.id, '@' || v_me.username || ' liked your gist', '{n} people liked your gist',
                             bl_push_preview(p.body, 60), '/play?go=gist:post:' || p.id, 'events', jsonb_build_object('post_id', p.id));
    end if;
  else
    delete from gist_likes where post_id = p.id and user_id = v_me.id;
    get diagnostics v_changed = row_count;
    if v_changed > 0 then
      update gist_posts set like_count = greatest(0, like_count - 1) where id = p.id returning * into p;
      update gist_posts set rank_key = bl_gist_rank(p.like_count, p.comment_count, p.created_at) where id = p.id returning * into p;
    end if;
  end if;
  return jsonb_build_object('liked', p_like, 'likes', p.like_count, 'id', p.id);
end $$;

create or replace function public.gist_follow(p_user uuid, p_follow boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(true); v_n int;
begin
  if p_user = v_me.id then raise exception 'You can''t follow yourself.' using errcode = 'P0001', hint = 'self'; end if;
  if not exists (select 1 from profiles where id = p_user and not banned) or bl_gist_blocked(v_me.id, p_user) then
    raise exception 'That player is not available.' using errcode = 'P0001', hint = 'not_found';
  end if;
  if p_follow then
    select count(*) into v_n from gist_follows where follower = v_me.id;
    if v_n >= bl_cfg('gist.max_follows') then
      raise exception 'You follow a lot of people already. Unfollow someone first.' using errcode = 'P0001', hint = 'limit';
    end if;
    insert into gist_follows (follower, followee) values (v_me.id, p_user) on conflict do nothing;
  else
    delete from gist_follows where follower = v_me.id and followee = p_user;
  end if;
  return jsonb_build_object('following', p_follow, 'id', p_user);
end $$;

create or replace function public.gist_profile(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); pr profiles;
begin
  select * into pr from profiles where id = p_user and not banned and home_chosen;
  if not found or (p_user <> v_me.id and bl_gist_blocked(v_me.id, p_user)) then
    raise exception 'That player is not available.' using errcode = 'P0001', hint = 'not_found';
  end if;
  return jsonb_build_object(
    'id', pr.id, 'username', pr.username, 'avatar', pr.avatar, 'me', pr.id = v_me.id,
    'posts', (select count(*) from gist_posts p where p.user_id = pr.id and not p.hidden),
    'followers', (select count(*) from gist_follows f where f.followee = pr.id),
    'following', (select count(*) from gist_follows f where f.follower = pr.id),
    'i_follow', exists (select 1 from gist_follows f where f.follower = v_me.id and f.followee = pr.id),
    'friend_status', social_friend_status(pr.id),
    'joined', pr.created_at);
end $$;

create or replace function public.gist_user_posts(p_user uuid, p_before bigint default null, p_limit int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_me profiles := bl_gist_me(false);
  v_lim int := least(greatest(coalesce(p_limit, bl_cfg('gist.feed_page')::int), 1), 50);
  v_rows gist_posts[]; v_next jsonb := null;
begin
  if p_user <> v_me.id and bl_gist_blocked(v_me.id, p_user) then
    return jsonb_build_object('posts', '[]'::jsonb, 'next', null);
  end if;
  v_rows := array(select p from gist_posts p where p.user_id = p_user and not p.hidden and (p_before is null or p.id < p_before)
                   order by p.id desc limit v_lim + 1);
  if coalesce(array_length(v_rows, 1), 0) > v_lim then
    v_rows := v_rows[1:v_lim];
    v_next := jsonb_build_object('id', (v_rows[v_lim]).id);
  end if;
  return jsonb_build_object('posts', coalesce((select jsonb_agg(bl_gist_post_json(v_rows[i], v_me.id) order by i) from generate_subscripts(v_rows, 1) i), '[]'::jsonb),
                            'next', v_next);
end $$;

-- trending #tags of the last 24 hours, cached for 10 minutes (the aggregate runs at most once per window for everybody)
create or replace function public.gist_trending() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  perform bl_gist_me(false);
  if bl_gist_claim('trending', interval '10 minutes') then
    update gist_cache set value = coalesce((
      select jsonb_agg(jsonb_build_object('tag', t.tag, 'n', t.n) order by t.n desc, t.tag)
        from (select tag, count(*) as n from gist_posts p, unnest(p.tags) as tag
               where not p.hidden and p.created_at > now() - interval '24 hours' group by tag order by count(*) desc, tag limit 8) t), '[]'::jsonb)
     where key = 'trending';
  end if;
  select value into v from gist_cache where key = 'trending';
  return coalesce(v, '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Comments, tips, reports
-- ---------------------------------------------------------------------------------------------
create or replace function public.gist_comment(p_post bigint, p_body text, p_parent bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_gist_me(true); v_now timestamptz := bl_now(); v_body text; p gist_posts; par gist_comments; c gist_comments;
  v_n int; v_top bigint; r uuid; v_to_user uuid; v_to_name text;
begin
  select * into p from gist_posts where id = p_post and not hidden;
  if not found or bl_gist_blocked(v_me.id, p.user_id) then
    raise exception 'That gist is not there any more.' using errcode = 'P0001', hint = 'not_found';
  end if;
  v_body := bl_gist_text(p_body, bl_cfg('gist.comment_max_len')::int);
  select count(*) into v_n from gist_comments where user_id = v_me.id and created_at > v_now - interval '1 minute';
  if v_n >= bl_cfg('gist.comments_per_minute') then
    raise exception 'You are commenting too fast. Wait a little.' using errcode = 'P0001', hint = 'too_fast';
  end if;
  if p_parent is not null then
    select * into par from gist_comments where id = p_parent and post_id = p.id and not hidden;
    if not found or bl_gist_blocked(v_me.id, par.user_id) then
      raise exception 'That comment is not there any more.' using errcode = 'P0001', hint = 'not_found';
    end if;
    v_top := coalesce(par.parent_id, par.id);            -- one level only: a reply to a reply stays under the same comment
    v_to_user := par.user_id;
    select username into v_to_name from profiles where id = par.user_id;
  end if;
  insert into gist_comments (post_id, parent_id, user_id, reply_to_user, reply_to_name, body, created_at)
  values (p.id, v_top, v_me.id, v_to_user, v_to_name, v_body, v_now) returning * into c;
  update gist_posts set comment_count = comment_count + 1 where id = p.id returning * into p;
  update gist_posts set rank_key = bl_gist_rank(p.like_count, p.comment_count, p.created_at) where id = p.id;
  -- author hears about every comment (batched); the person replied to hears about the reply
  perform bl_gist_notify(p.user_id, 'gist_comment', p.id, v_me.id, '@' || v_me.username || ' commented on your gist', '{n} new comments on your gist',
                         bl_push_preview(v_body, 80), '/play?go=gist:post:' || p.id, 'messages', jsonb_build_object('post_id', p.id, 'comment_id', c.id));
  if v_to_user is not null and v_to_user <> p.user_id then
    perform bl_gist_notify(v_to_user, 'gist_reply', p.id, v_me.id, '@' || v_me.username || ' replied to you', '{n} replies to you',
                           bl_push_preview(v_body, 80), '/play?go=gist:post:' || p.id, 'messages', jsonb_build_object('post_id', p.id, 'comment_id', c.id));
  end if;
  for r in select * from bl_gist_mentions(v_body, v_me.id) loop
    if r <> p.user_id and r is distinct from v_to_user then
      perform bl_gist_notify(r, 'gist_mention', p.id, v_me.id, '@' || v_me.username || ' mentioned you', '{n} people mentioned you',
                             bl_push_preview(v_body, 80), '/play?go=gist:post:' || p.id, 'messages', jsonb_build_object('post_id', p.id, 'comment_id', c.id));
    end if;
  end loop;
  return jsonb_build_object('comment', jsonb_build_object(
      'id', c.id, 'post_id', c.post_id, 'parent_id', c.parent_id, 'user', bl_gist_user(c.user_id), 'body', c.body,
      'reply_to_name', c.reply_to_name, 'mine', true, 'created_at', c.created_at),
    'comments', p.comment_count);
end $$;

-- Comments of a post: top-level comments oldest first (cursor = last id), each with up to 30 replies. Hidden and blocked ones are left out.
create or replace function public.gist_comments(p_post bigint, p_after bigint default 0, p_limit int default 20) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); v_lim int := least(greatest(coalesce(p_limit, 20), 1), 50); v_rows jsonb; v_n int;
begin
  if not exists (select 1 from gist_posts where id = p_post and not hidden) then
    raise exception 'That gist is not there any more.' using errcode = 'P0001', hint = 'not_found';
  end if;
  select coalesce(jsonb_agg(x.j order by x.id), '[]'::jsonb), count(*) into v_rows, v_n from (
    select c.id, jsonb_build_object(
      'id', c.id, 'post_id', c.post_id, 'parent_id', null, 'user', bl_gist_user(c.user_id), 'body', c.body, 'mine', c.user_id = v_me.id,
      'created_at', c.created_at,
      'replies', coalesce((select jsonb_agg(jsonb_build_object(
            'id', r.id, 'post_id', r.post_id, 'parent_id', r.parent_id, 'user', bl_gist_user(r.user_id), 'body', r.body,
            'reply_to_name', r.reply_to_name, 'mine', r.user_id = v_me.id, 'created_at', r.created_at) order by r.id)
          from (select * from gist_comments r where r.parent_id = c.id and not r.hidden and not bl_gist_blocked(v_me.id, r.user_id)
                 order by r.id limit 30) r), '[]'::jsonb)) as j
      from gist_comments c
     where c.post_id = p_post and c.parent_id is null and not c.hidden and c.id > coalesce(p_after, 0)
       and not bl_gist_blocked(v_me.id, c.user_id)
     order by c.id limit v_lim + 1) x;
  return jsonb_build_object('comments', case when v_n > v_lim then v_rows - v_lim else v_rows end, 'has_more', v_n > v_lim);
end $$;

create or replace function public.gist_delete_comment(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); c gist_comments; p gist_posts; v_gone int;
begin
  select * into c from gist_comments where id = p_id;
  if not found then raise exception 'That comment is already gone.' using errcode = 'P0001', hint = 'not_found'; end if;
  select * into p from gist_posts where id = c.post_id;
  if c.user_id <> v_me.id and p.user_id <> v_me.id then
    raise exception 'You can only delete your own comments, or comments on your own gist.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  select 1 + count(*) into v_gone from gist_comments where parent_id = c.id;
  delete from gist_comments where id = c.id;
  update gist_posts set comment_count = greatest(0, comment_count - v_gone) where id = p.id returning * into p;
  update gist_posts set rank_key = bl_gist_rank(p.like_count, p.comment_count, p.created_at) where id = p.id;
  return jsonb_build_object('message', 'Comment deleted.', 'id', c.id, 'comments', p.comment_count);
end $$;

-- Tip the poster. The money moves with tip_player (its limits, fee, daily maximum and new-account wait all apply); this adds the
-- cached totals on the gist and tells the poster which gist it was.
create or replace function public.gist_tip_post(p_post bigint, p_amount bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(true); p gist_posts; v_name text; v jsonb;
begin
  select * into p from gist_posts where id = p_post and not hidden;
  if not found or bl_gist_blocked(v_me.id, p.user_id) then
    raise exception 'That gist is not there any more.' using errcode = 'P0001', hint = 'not_found';
  end if;
  if p.user_id = v_me.id then
    raise exception 'You can''t tip yourself.' using errcode = 'P0001', hint = 'self';
  end if;
  select username into v_name from profiles where id = p.user_id;
  v := tip_player(v_name, p_amount, coalesce(nullif(btrim(p_note), ''), 'Tip on your gist'));
  update gist_posts set tip_count = tip_count + 1, tip_total = tip_total + p_amount where id = p.id returning * into p;
  return v || jsonb_build_object('post_id', p.id, 'tips', p.tip_count, 'tip_total', p.tip_total);
end $$;

-- Report a gist, a comment, a group or a group message. One report per player per target; at gist.report_hide_count different reporters
-- a gist, comment or message is hidden at once. A group is only ever hidden by an admin.
create or replace function public.gist_report(p_kind text, p_id bigint, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_gist_me(false); v_author uuid; v_n int; v_hide boolean := false; v_reason text := nullif(left(bl_chat_clean(p_reason), 120), '');
  v_group bigint;
begin
  if p_kind = 'post' then select user_id into v_author from gist_posts where id = p_id and not hidden;
  elsif p_kind = 'comment' then select user_id into v_author from gist_comments where id = p_id and not hidden;
  elsif p_kind = 'message' then
    select user_id, group_id into v_author, v_group from gist_messages where id = p_id and not hidden and deleted_at is null;
    if found and bl_gist_role(v_group, v_me.id) is null then v_author := null; end if;
  elsif p_kind = 'group' then
    select owner_id into v_author from gist_groups where id = p_id and not hidden and (is_public or gist_is_member(id));
    if not found then v_author := null; else v_author := coalesce(v_author, '00000000-0000-0000-0000-000000000000'::uuid); end if;
  else
    raise exception 'Pick what you are reporting.' using errcode = 'P0001', hint = 'bad_kind';
  end if;
  if v_author is null then
    raise exception 'That is not there any more.' using errcode = 'P0001', hint = 'not_found';
  end if;
  if v_author = v_me.id then
    raise exception 'You can''t report your own content.' using errcode = 'P0001', hint = 'self';
  end if;
  insert into gist_reports (kind, target_id, reporter_id, reason) values (p_kind, p_id, v_me.id, v_reason) on conflict do nothing;
  select count(*) into v_n from gist_reports where kind = p_kind and target_id = p_id and status = 'open';
  if p_kind <> 'group' and v_n >= bl_cfg('gist.report_hide_count') then
    v_hide := true;
    if p_kind = 'post' then update gist_posts set hidden = true, hidden_reason = 'reports', report_count = v_n where id = p_id;
    elsif p_kind = 'comment' then update gist_comments set hidden = true, report_count = v_n where id = p_id;
    else update gist_messages set hidden = true, report_count = v_n where id = p_id; end if;
  elsif p_kind = 'post' then update gist_posts set report_count = v_n where id = p_id;
  elsif p_kind = 'comment' then update gist_comments set report_count = v_n where id = p_id;
  elsif p_kind = 'message' then update gist_messages set report_count = v_n where id = p_id; end if;
  return jsonb_build_object('message', 'Thanks. A moderator will look at it.', 'reports', v_n, 'hidden', v_hide);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Groups
-- ---------------------------------------------------------------------------------------------
create or replace function public.gist_group_create(p_name text, p_emoji text default null, p_description text default null,
                                                    p_public boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_gist_me(true); v_now timestamptz := bl_now(); v_name text := bl_chat_clean(p_name); v_desc text;
  v_emoji text := coalesce(nullif(btrim(p_emoji), ''), '💬'); v_n int; g gist_groups;
begin
  if char_length(v_name) < 3 or char_length(v_name) > 32 then
    raise exception 'A group name needs 3 to 32 characters.' using errcode = 'P0001', hint = 'bad_name';
  end if;
  if bl_chat_mask(v_name) <> v_name then
    raise exception 'Pick a cleaner group name.' using errcode = 'P0001', hint = 'bad_name';
  end if;
  if char_length(v_emoji) > 8 then v_emoji := left(v_emoji, 8); end if;
  v_desc := bl_gist_text(p_description, 200, true);
  if exists (select 1 from gist_groups where system and lower(name) = lower(v_name)) then
    raise exception 'That name belongs to an official group. Pick another.' using errcode = 'P0001', hint = 'name_taken';
  end if;
  select count(*) into v_n from gist_groups where owner_id = v_me.id and created_at > v_now - interval '24 hours';
  if v_n >= bl_cfg('gist.groups_per_day') then
    raise exception 'You can create % groups a day. Try again tomorrow.', bl_cfg('gist.groups_per_day')::int using errcode = 'P0001', hint = 'too_many';
  end if;
  select count(*) into v_n from gist_group_members where user_id = v_me.id;
  if v_n >= bl_cfg('gist.max_groups_joined') then
    raise exception 'You are in too many groups. Leave one first.' using errcode = 'P0001', hint = 'limit';
  end if;
  insert into gist_groups (name, emoji, description, is_public, owner_id, member_count, created_at)
  values (v_name, v_emoji, v_desc, coalesce(p_public, true), v_me.id, 1, v_now) returning * into g;
  insert into gist_group_members (group_id, user_id, role, joined_at) values (g.id, v_me.id, 'owner', v_now);
  return bl_gist_group_json(g, v_me.id);
end $$;

create or replace function public.gist_groups_mine() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false);
begin
  return coalesce((select jsonb_agg(bl_gist_group_json(g, v_me.id) order by coalesce(g.last_msg_at, m.joined_at) desc, g.id desc)
                     from gist_group_members m join gist_groups g on g.id = m.group_id where m.user_id = v_me.id), '[]'::jsonb);
end $$;

-- Public groups. sort: active (default) | new | big. Search is a name match. Pages of 30 (offset up to 300).
create or replace function public.gist_groups_discover(p_query text default null, p_sort text default 'active', p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_me profiles := bl_gist_me(false); v_q text := nullif(btrim(coalesce(p_query, '')), ''); v_pat text := null;
  v_off int := least(greatest(coalesce(p_offset, 0), 0), 300); v_rows gist_groups[];
begin
  if v_q is not null then v_pat := '%' || replace(replace(replace(left(v_q, 40), '\', '\\'), '%', '\%'), '_', '\_') || '%'; end if;
  if p_sort = 'new' then
    v_rows := array(select g from gist_groups g where g.is_public and not g.hidden and (v_pat is null or g.name ilike v_pat or g.description ilike v_pat)
                     order by g.id desc offset v_off limit 30);
  elsif p_sort = 'big' then
    v_rows := array(select g from gist_groups g where g.is_public and not g.hidden and (v_pat is null or g.name ilike v_pat or g.description ilike v_pat)
                     order by g.member_count desc, g.id desc offset v_off limit 30);
  else
    v_rows := array(select g from gist_groups g where g.is_public and not g.hidden and (v_pat is null or g.name ilike v_pat or g.description ilike v_pat)
                     order by g.act_key desc nulls last, g.id desc offset v_off limit 30);
  end if;
  return coalesce((select jsonb_agg(bl_gist_group_json(v_rows[i], v_me.id)
                                    || jsonb_build_object('joined', exists (select 1 from gist_group_members m where m.group_id = (v_rows[i]).id and m.user_id = v_me.id))
                                    order by i)
                     from generate_subscripts(v_rows, 1) i), '[]'::jsonb);
end $$;

create or replace function public.gist_group_get(p_group bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); g gist_groups; v_pin jsonb := null; v_role text;
begin
  select * into g from gist_groups where id = p_group;
  v_role := bl_gist_role(p_group, v_me.id);
  if not found or (not g.is_public and v_role is null) or (g.hidden and v_role is null) then
    raise exception 'That group is not available.' using errcode = 'P0001', hint = 'not_found';
  end if;
  if g.pinned_id is not null then
    select bl_gist_msg_json(m, v_me.id) into v_pin from gist_messages m where m.id = g.pinned_id and not m.hidden and m.deleted_at is null;
  end if;
  return bl_gist_group_json(g, v_me.id) || jsonb_build_object(
    'pinned', v_pin, 'can_manage', v_role in ('owner', 'admin'), 'is_owner', v_role = 'owner',
    'joined', exists (select 1 from gist_group_members m where m.group_id = g.id and m.user_id = v_me.id),
    'banned', exists (select 1 from gist_group_bans b where b.group_id = g.id and b.user_id = v_me.id));
end $$;

create or replace function public.gist_group_join(p_group bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(true); v_now timestamptz := bl_now(); g gist_groups; v_n int; v_cap int;
begin
  select * into g from gist_groups where id = p_group for update;
  if not found or g.hidden or not g.is_public then
    raise exception 'That group is private or not available. Ask a member to add you.' using errcode = 'P0001', hint = 'not_found';
  end if;
  if exists (select 1 from gist_group_members where group_id = g.id and user_id = v_me.id) then
    return bl_gist_group_json(g, v_me.id);
  end if;
  if exists (select 1 from gist_group_bans where group_id = g.id and user_id = v_me.id) then
    raise exception 'You were removed from this group.' using errcode = 'P0001', hint = 'removed';
  end if;
  v_cap := coalesce(g.member_cap, bl_cfg('gist.group_member_cap')::int);
  if g.member_count >= v_cap then
    raise exception 'This group is full (% members).', v_cap using errcode = 'P0001', hint = 'full';
  end if;
  select count(*) into v_n from gist_group_members where user_id = v_me.id;
  if v_n >= bl_cfg('gist.max_groups_joined') then
    raise exception 'You are in too many groups. Leave one first.' using errcode = 'P0001', hint = 'limit';
  end if;
  insert into gist_group_members (group_id, user_id, role, last_read_id, joined_at) values (g.id, v_me.id, 'member', g.last_msg_id, v_now);
  update gist_groups set member_count = member_count + 1 where id = g.id returning * into g;
  return bl_gist_group_json(g, v_me.id);
end $$;

create or replace function public.gist_group_leave(p_group bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); g gist_groups; m gist_group_members; v_next uuid;
begin
  select * into g from gist_groups where id = p_group for update;
  select * into m from gist_group_members where group_id = p_group and user_id = v_me.id;
  if not found then raise exception 'You are not in that group.' using errcode = 'P0001', hint = 'not_member'; end if;
  delete from gist_group_members where group_id = p_group and user_id = v_me.id;
  update gist_groups set member_count = greatest(0, member_count - 1) where id = p_group returning * into g;
  if m.role = 'owner' then
    select user_id into v_next from gist_group_members where group_id = p_group
     order by (role = 'admin') desc, joined_at, user_id limit 1;
    if v_next is null then
      if not g.system then delete from gist_groups where id = p_group; end if;
    else
      update gist_group_members set role = 'owner' where group_id = p_group and user_id = v_next;
      update gist_groups set owner_id = v_next where id = p_group;
    end if;
  end if;
  return jsonb_build_object('message', 'You left the group.', 'id', p_group);
end $$;

create or replace function public.gist_group_members(p_group bigint, p_offset int default 0, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false);
begin
  if bl_gist_role(p_group, v_me.id) is null then
    raise exception 'Only members can see the member list.' using errcode = 'P0001', hint = 'not_member';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'avatar', p.avatar, 'role', x.role,
                                                       'muted_until', case when x.muted_until > bl_now() then x.muted_until end, 'joined_at', x.joined_at)
                                    order by (x.role = 'owner') desc, (x.role = 'admin') desc, lower(p.username))
                     from (select * from gist_group_members m where m.group_id = p_group
                            order by (m.role = 'owner') desc, (m.role = 'admin') desc, m.joined_at
                            offset greatest(coalesce(p_offset, 0), 0) limit least(greatest(coalesce(p_limit, 50), 1), 100)) x
                     join profiles p on p.id = x.user_id), '[]'::jsonb);
end $$;

-- owner or admin adds a player (by username). Friends only unless the admin setting allows anyone. Private groups are invite-only this way.
create or replace function public.gist_group_add(p_group bigint, p_username text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_gist_me(true); v_now timestamptz := bl_now(); g gist_groups; t profiles; v_n int; v_cap int;
begin
  select * into g from gist_groups where id = p_group for update;
  if not found or coalesce(bl_gist_role(p_group, v_me.id), '') not in ('owner', 'admin') then
    raise exception 'Only the owner or an admin can add people.' using errcode = 'P0001', hint = 'not_admin';
  end if;
  t := bl_find_player(p_username);
  if t.id = v_me.id or exists (select 1 from gist_group_members where group_id = p_group and user_id = t.id) then
    raise exception '@% is already in this group.', t.username using errcode = 'P0001', hint = 'already';
  end if;
  if bl_gist_blocked(v_me.id, t.id) then
    raise exception 'You can''t add @% (one of you blocked the other).', t.username using errcode = 'P0001', hint = 'blocked';
  end if;
  if bl_cfg_bool('gist.add_friends_only') and social_friend_status(t.id) <> 'friend' then
    raise exception 'You can only add your friends. Send @% a friend request first.', t.username using errcode = 'P0001', hint = 'not_friend';
  end if;
  v_cap := coalesce(g.member_cap, bl_cfg('gist.group_member_cap')::int);
  if g.member_count >= v_cap then
    raise exception 'This group is full (% members).', v_cap using errcode = 'P0001', hint = 'full';
  end if;
  select count(*) into v_n from gist_group_members where user_id = t.id;
  if v_n >= bl_cfg('gist.max_groups_joined') then
    raise exception '@% is in too many groups already.', t.username using errcode = 'P0001', hint = 'limit';
  end if;
  delete from gist_group_bans where group_id = p_group and user_id = t.id;
  insert into gist_group_members (group_id, user_id, role, last_read_id, joined_at) values (p_group, t.id, 'member', g.last_msg_id, v_now);
  update gist_groups set member_count = member_count + 1 where id = p_group;
  perform bl_gist_notify(t.id, 'gist_group_add', p_group, v_me.id, '@' || v_me.username || ' added you to ' || g.name,
                         '{n} groups added you', 'Tap to open the group.', '/play?go=gist:group:' || p_group, 'friends',
                         jsonb_build_object('group_id', p_group, 'group', g.name));
  return jsonb_build_object('message', '@' || t.username || ' is in the group now.', 'id', t.id);
end $$;

-- Remove a member (admins can't remove other admins; only the owner can). They can't rejoin on their own; adding them again lifts it.
create or replace function public.gist_group_remove(p_group bigint, p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); v_role text := coalesce(bl_gist_role(p_group, v_me.id), ''); t gist_group_members; g gist_groups;
begin
  if v_role not in ('owner', 'admin') then
    raise exception 'Only the owner or an admin can remove people.' using errcode = 'P0001', hint = 'not_admin';
  end if;
  select * into g from gist_groups where id = p_group for update;
  select * into t from gist_group_members where group_id = p_group and user_id = p_user;
  if not found then raise exception 'They are not in this group.' using errcode = 'P0001', hint = 'not_member'; end if;
  if p_user = v_me.id then raise exception 'Use Leave group for yourself.' using errcode = 'P0001', hint = 'self'; end if;
  if t.role = 'owner' or (t.role = 'admin' and v_role <> 'owner' and not bl_is_admin()) then
    raise exception 'You can''t remove %.', case when t.role = 'owner' then 'the owner' else 'another admin' end using errcode = 'P0001', hint = 'not_allowed';
  end if;
  delete from gist_group_members where group_id = p_group and user_id = p_user;
  insert into gist_group_bans (group_id, user_id) values (p_group, p_user) on conflict do nothing;
  update gist_groups set member_count = greatest(0, member_count - 1) where id = p_group;
  return jsonb_build_object('message', 'Removed from the group.', 'id', p_user);
end $$;

create or replace function public.gist_group_set_role(p_group bigint, p_user uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); t gist_group_members;
begin
  if coalesce(bl_gist_role(p_group, v_me.id), '') <> 'owner' and not bl_is_admin() then
    raise exception 'Only the owner can make admins.' using errcode = 'P0001', hint = 'not_admin';
  end if;
  if p_role not in ('admin', 'member') then raise exception 'Pick admin or member.' using errcode = 'P0001', hint = 'bad_role'; end if;
  select * into t from gist_group_members where group_id = p_group and user_id = p_user;
  if not found or t.role = 'owner' then raise exception 'You can''t change that member.' using errcode = 'P0001', hint = 'not_allowed'; end if;
  update gist_group_members set role = p_role where group_id = p_group and user_id = p_user;
  return jsonb_build_object('message', case when p_role = 'admin' then 'Now an admin.' else 'Back to member.' end, 'role', p_role);
end $$;

-- Mute a member for p_minutes (0 = unmute). Muted members can read but not write in this group.
create or replace function public.gist_group_mute(p_group bigint, p_user uuid, p_minutes int default 60) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); v_role text := coalesce(bl_gist_role(p_group, v_me.id), ''); t gist_group_members; v_until timestamptz;
begin
  if v_role not in ('owner', 'admin') then
    raise exception 'Only the owner or an admin can mute people.' using errcode = 'P0001', hint = 'not_admin';
  end if;
  select * into t from gist_group_members where group_id = p_group and user_id = p_user;
  if not found then raise exception 'They are not in this group.' using errcode = 'P0001', hint = 'not_member'; end if;
  if p_user = v_me.id or t.role = 'owner' or (t.role = 'admin' and v_role <> 'owner' and not bl_is_admin()) then
    raise exception 'You can''t mute that member.' using errcode = 'P0001', hint = 'not_allowed';
  end if;
  v_until := case when coalesce(p_minutes, 0) <= 0 then null else bl_now() + make_interval(mins => least(p_minutes, 525600)) end;
  update gist_group_members set muted_until = v_until where group_id = p_group and user_id = p_user;
  return jsonb_build_object('message', case when v_until is null then 'Unmuted.' else 'Muted.' end, 'muted_until', v_until);
end $$;

-- Pin a message (null = unpin).
create or replace function public.gist_group_pin(p_group bigint, p_message bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false);
begin
  if coalesce(bl_gist_role(p_group, v_me.id), '') not in ('owner', 'admin') then
    raise exception 'Only the owner or an admin can pin.' using errcode = 'P0001', hint = 'not_admin';
  end if;
  if p_message is not null and not exists (select 1 from gist_messages where id = p_message and group_id = p_group and deleted_at is null and not hidden and kind <> 'system') then
    raise exception 'That message can''t be pinned.' using errcode = 'P0001', hint = 'not_found';
  end if;
  update gist_groups set pinned_id = p_message where id = p_group;
  return jsonb_build_object('message', case when p_message is null then 'Unpinned.' else 'Pinned.' end, 'pinned_id', p_message);
end $$;

-- Rename / re-icon / describe (owner or admin). Only the owner can flip public / private.
create or replace function public.gist_group_update(p_group bigint, p_name text default null, p_emoji text default null,
                                                    p_description text default null, p_public boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(true); v_role text := coalesce(bl_gist_role(p_group, v_me.id), ''); g gist_groups; v_name text; v_desc text;
begin
  select * into g from gist_groups where id = p_group for update;
  if not found or v_role not in ('owner', 'admin') then
    raise exception 'Only the owner or an admin can change the group.' using errcode = 'P0001', hint = 'not_admin';
  end if;
  v_name := coalesce(nullif(bl_chat_clean(p_name), ''), g.name);
  if char_length(v_name) < 3 or char_length(v_name) > 32 or bl_chat_mask(v_name) <> v_name then
    raise exception 'A group name needs 3 to 32 clean characters.' using errcode = 'P0001', hint = 'bad_name';
  end if;
  if not g.system and lower(v_name) <> lower(g.name) and exists (select 1 from gist_groups where system and lower(name) = lower(v_name)) then
    raise exception 'That name belongs to an official group.' using errcode = 'P0001', hint = 'name_taken';
  end if;
  v_desc := case when p_description is null then g.description else bl_gist_text(p_description, 200, true) end;
  update gist_groups set name = v_name, emoji = left(coalesce(nullif(btrim(p_emoji), ''), g.emoji), 8), description = v_desc,
         is_public = case when p_public is not null and (v_role = 'owner' or bl_is_admin()) then p_public else is_public end
   where id = p_group returning * into g;
  return bl_gist_group_json(g, v_me.id);
end $$;

create or replace function public.gist_group_delete(p_group bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); g gist_groups;
begin
  select * into g from gist_groups where id = p_group;
  if not found or g.system or g.owner_id is distinct from v_me.id then
    raise exception 'Only the owner can delete a group.' using errcode = 'P0001', hint = 'not_admin';
  end if;
  delete from gist_groups where id = p_group;
  return jsonb_build_object('message', 'Group deleted.', 'id', p_group);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Group messages
-- ---------------------------------------------------------------------------------------------
-- caller must be a member, not muted in the group, the group not hidden, under the per-minute limit. Returns the group row (locked).
create or replace function public.bl_gist_send_check(p_group bigint, p_uid uuid) returns public.gist_groups
language plpgsql set search_path = public as $$
declare g gist_groups; m gist_group_members; v_n int; v_now timestamptz := bl_now();
begin
  select * into m from gist_group_members where group_id = p_group and user_id = p_uid;
  if not found then raise exception 'Join the group first.' using errcode = 'P0001', hint = 'not_member'; end if;
  select * into g from gist_groups where id = p_group;
  if g.hidden then raise exception 'This group is paused by a moderator.' using errcode = 'P0001', hint = 'group_hidden'; end if;
  if m.muted_until is not null and m.muted_until > v_now then
    raise exception 'A group admin muted you here for about % more min.', ceil(extract(epoch from m.muted_until - v_now) / 60) using errcode = 'P0001', hint = 'muted_group';
  end if;
  select count(*) into v_n from gist_messages where user_id = p_uid and created_at > v_now - interval '1 minute';
  if v_n >= bl_cfg('gist.group_messages_per_minute') then
    raise exception 'You are sending too many messages. Take a short break.' using errcode = 'P0001', hint = 'too_fast';
  end if;
  return g;
end $$;

-- insert the row, bump the cached last message / activity on the group, move my read pointer, tell the people who were replied to / mentioned
create or replace function public.bl_gist_message_add(p_group public.gist_groups, p_me public.profiles, p_kind text, p_body text, p_audio text, p_mime text,
                                                      p_amount bigint, p_to uuid, p_to_name text, p_reply bigint) returns public.gist_messages
language plpgsql set search_path = public as $$
declare
  v_now timestamptz := bl_now(); m gist_messages; v_c double precision; v_prev uuid; r uuid; v_snip text;
begin
  insert into gist_messages (group_id, user_id, username, kind, body, audio_path, audio_mime, money_amount, money_to, money_to_username, reply_to, created_at)
  values (p_group.id, p_me.id, p_me.username, p_kind, p_body, p_audio, p_mime, p_amount, p_to, p_to_name, p_reply, v_now) returning * into m;
  v_snip := case p_kind when 'voice' then '🎤 Voice note' when 'money' then '💸 ₦' || to_char(p_amount, 'FM999,999,999,999') || ' to @' || p_to_name
                else left(p_body, 80) end;
  v_c := extract(epoch from v_now)::float8 / 3600.0 * ln(2.0::float8) / greatest(1, bl_cfg('gist.group_half_life_hours'))::float8;
  update gist_groups set last_msg_id = m.id, last_msg_at = v_now, last_msg_user = p_me.username, last_msg_text = v_snip,
         act_key = case when act_key is null then v_c else bl_gist_lse(act_key, v_c) end
   where id = p_group.id;
  update gist_group_members set last_read_id = m.id where group_id = p_group.id and user_id = p_me.id;
  if p_reply is not null then
    select user_id into v_prev from gist_messages where id = p_reply;
    if v_prev is not null and v_prev <> p_me.id and exists (select 1 from gist_group_members where group_id = p_group.id and user_id = v_prev) then
      perform bl_gist_notify(v_prev, 'gist_group_reply', p_group.id, p_me.id, '@' || p_me.username || ' replied to you in ' || p_group.name,
                             '{n} replies to you in ' || p_group.name, bl_push_preview(v_snip, 80), '/play?go=gist:group:' || p_group.id, 'messages',
                             jsonb_build_object('group_id', p_group.id, 'group', p_group.name));
    end if;
  end if;
  if p_kind = 'text' then
    for r in select * from bl_gist_mentions(p_body, p_me.id, p_group.id) limit 3 loop
      if r is distinct from v_prev then
        perform bl_gist_notify(r, 'gist_group_reply', p_group.id, p_me.id, '@' || p_me.username || ' mentioned you in ' || p_group.name,
                               '{n} mentions of you in ' || p_group.name, bl_push_preview(p_body, 80), '/play?go=gist:group:' || p_group.id, 'messages',
                               jsonb_build_object('group_id', p_group.id, 'group', p_group.name));
      end if;
    end loop;
  end if;
  return m;
end $$;

-- Text or a voice note (already uploaded to player-voice/group/<group>/<my id>/<uuid>.<ext>). p_reply = the message being answered.
create or replace function public.gist_group_send(p_group bigint, p_body text default null, p_audio_path text default null, p_audio_mime text default null,
                                                  p_reply bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_gist_me(true); g gist_groups; v_body text; v_kind text; v_now timestamptz := bl_now(); m gist_messages;
begin
  g := bl_gist_send_check(p_group, v_me.id);
  if p_reply is not null and not exists (select 1 from gist_messages where id = p_reply and group_id = p_group and deleted_at is null) then
    raise exception 'You can''t reply to that message.' using errcode = 'P0001', hint = 'bad_reply';
  end if;
  if p_audio_path is not null then
    v_kind := 'voice';
    if p_audio_mime is null or p_audio_mime not in ('audio/webm', 'audio/mp4', 'audio/ogg', 'audio/mpeg', 'audio/aac', 'audio/wav') then
      raise exception 'That voice format is not supported.' using errcode = 'P0001', hint = 'bad_audio';
    end if;
    if p_audio_path !~ ('^group/' || p_group::text || '/' || v_me.id::text || '/[0-9a-f-]{36}\.(webm|mp4|ogg|mp3|aac|wav)$') then
      raise exception 'That voice note did not upload properly.' using errcode = 'P0001', hint = 'bad_audio';
    end if;
    if not exists (select 1 from storage.objects where bucket_id = 'player-voice' and name = p_audio_path) then
      raise exception 'Voice upload did not finish.' using errcode = 'P0001', hint = 'audio_missing';
    end if;
    if exists (select 1 from gist_messages where audio_path = p_audio_path) then
      raise exception 'That voice note was already sent.' using errcode = 'P0001', hint = 'bad_audio';
    end if;
  else
    v_kind := 'text';
    v_body := bl_gist_text(p_body, bl_cfg('gist.message_max_len')::int);
    if exists (select 1 from gist_messages where user_id = v_me.id and group_id = p_group and created_at > v_now - interval '30 seconds'
                  and kind = 'text' and lower(regexp_replace(body, '\W', '', 'g')) = lower(regexp_replace(v_body, '\W', '', 'g'))) then
      raise exception 'You just sent that. Say something new.' using errcode = 'P0001', hint = 'duplicate';
    end if;
  end if;
  m := bl_gist_message_add(g, v_me, v_kind, v_body, p_audio_path, case when v_kind = 'voice' then p_audio_mime end, null, null, null, p_reply);
  perform bl_gist_sweep();
  return bl_gist_msg_json(m, v_me.id);
end $$;

-- Send money to a member of this group. The transfer is a normal bank_transfer (fee, daily limit, cooldown, new-account wait all apply);
-- on success a money bubble appears in the group. If the transfer is refused nothing is posted.
create or replace function public.gist_group_send_money(p_group bigint, p_username text, p_amount bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_gist_me(true); g gist_groups; t profiles; v_note text; v jsonb; m gist_messages;
begin
  g := bl_gist_send_check(p_group, v_me.id);
  t := bl_find_player(p_username);
  if t.id = v_me.id then raise exception 'You can''t send money to yourself.' using errcode = 'P0001', hint = 'self'; end if;
  if not exists (select 1 from gist_group_members where group_id = p_group and user_id = t.id) then
    raise exception '@% is not in this group.', t.username using errcode = 'P0001', hint = 'not_member';
  end if;
  if bl_gist_blocked(v_me.id, t.id) then
    raise exception 'You can''t send money to @% (one of you blocked the other).', t.username using errcode = 'P0001', hint = 'blocked';
  end if;
  v_note := nullif(left(bl_chat_mask(bl_chat_clean(p_note)), 80), '');
  v := bank_transfer(t.username, p_amount, v_note);
  m := bl_gist_message_add(g, v_me, 'money', v_note, null, null, p_amount, t.id, t.username, null);
  return jsonb_build_object('message', bl_gist_msg_json(m, v_me.id), 'transfer', v);
end $$;

-- A page of messages, oldest first (p_before = the oldest id I already have). Hidden messages and blocked authors are left out.
create or replace function public.gist_group_history(p_group bigint, p_before bigint default null, p_limit int default 40) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); v_lim int := least(greatest(coalesce(p_limit, 40), 1), 60);
begin
  if bl_gist_role(p_group, v_me.id) is null then
    raise exception 'Only members can read this group.' using errcode = 'P0001', hint = 'not_member';
  end if;
  return coalesce((select jsonb_agg(bl_gist_msg_json(x, v_me.id) order by x.id)
                     from (select m.* from gist_messages m
                            where m.group_id = p_group and not m.hidden and (p_before is null or m.id < p_before)
                              and not bl_gist_blocked(v_me.id, m.user_id)
                            order by m.id desc limit v_lim) x), '[]'::jsonb);
end $$;

-- messages newer than p_after (poll mode, or a catch-up after a Realtime gap)
create or replace function public.gist_group_after(p_group bigint, p_after bigint, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false);
begin
  if bl_gist_role(p_group, v_me.id) is null then
    raise exception 'Only members can read this group.' using errcode = 'P0001', hint = 'not_member';
  end if;
  return coalesce((select jsonb_agg(bl_gist_msg_json(x, v_me.id) order by x.id)
                     from (select m.* from gist_messages m
                            where m.group_id = p_group and not m.hidden and m.id > coalesce(p_after, 0) and not bl_gist_blocked(v_me.id, m.user_id)
                            order by m.id limit least(greatest(coalesce(p_limit, 50), 1), 100)) x), '[]'::jsonb);
end $$;

create or replace function public.gist_group_mark_read(p_group bigint, p_upto bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); v_to bigint;
begin
  select coalesce(p_upto, g.last_msg_id) into v_to from gist_groups g where g.id = p_group;
  update gist_group_members set last_read_id = v_to where group_id = p_group and user_id = v_me.id and last_read_id < v_to;
  return jsonb_build_object('read', v_to);
end $$;

-- Delete a message for everyone: its author (within chat.delete_everyone_hours) or a group admin / owner. Money bubbles stay (they are the receipt).
create or replace function public.gist_group_delete_message(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_gist_me(false); m gist_messages; v_role text;
begin
  select * into m from gist_messages where id = p_id;
  if not found or m.deleted_at is not null then raise exception 'That message is already gone.' using errcode = 'P0001', hint = 'not_found'; end if;
  v_role := bl_gist_role(m.group_id, v_me.id);
  if v_role is null then raise exception 'Not your group.' using errcode = 'P0001', hint = 'not_member'; end if;
  if m.kind = 'money' and not bl_is_admin() then
    raise exception 'Money messages stay as a receipt.' using errcode = 'P0001', hint = 'not_allowed';
  end if;
  if m.user_id <> v_me.id and v_role not in ('owner', 'admin') then
    raise exception 'You can only delete your own messages.' using errcode = 'P0001', hint = 'not_author';
  end if;
  if m.user_id = v_me.id and v_role not in ('owner', 'admin')
     and bl_now() - m.created_at > make_interval(hours => bl_cfg('chat.delete_everyone_hours')::int) then
    raise exception 'It is too late to delete that for everyone.' using errcode = 'P0001', hint = 'too_late';
  end if;
  update gist_messages set body = null, audio_path = null, audio_mime = null, deleted_at = bl_now(),
         kind = case when kind in ('text', 'voice') then kind else 'system' end where id = m.id;
  update gist_groups set pinned_id = null where id = m.group_id and pinned_id = m.id;
  return jsonb_build_object('message', 'Message deleted.', 'id', m.id, 'deleted_at', bl_now(), 'audio_path', m.audio_path);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. Admin (Admin -> Gist). Every function starts with bl_admin_guard() and logs to admin_audit.
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_gist_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'posts', (select count(*) from gist_posts), 'posts_24h', (select count(*) from gist_posts where created_at > now() - interval '24 hours'),
    'comments_24h', (select count(*) from gist_comments where created_at > now() - interval '24 hours'),
    'hidden_posts', (select count(*) from gist_posts where hidden),
    'groups', (select count(*) from gist_groups), 'public_groups', (select count(*) from gist_groups where is_public),
    'messages_24h', (select count(*) from gist_messages where created_at > now() - interval '24 hours'),
    'open_reports', (select count(*) from (select 1 from gist_reports where status = 'open' group by kind, target_id) r),
    'bans', (select count(*) from gist_bans where until_at is null or until_at > now()),
    'photos', (select count(*) from gist_posts where photo_path is not null));
end $$;

-- Reports grouped by target (the thing reported), newest first, with a preview of the content.
create or replace function public.admin_gist_reports(p_status text default 'open') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return coalesce((
    select jsonb_agg(x.j order by x.last_at desc) from (
      select r.last_at, jsonb_build_object(
        'kind', r.kind, 'target_id', r.target_id, 'reports', r.n, 'last_report', r.last_at, 'status', r.status,
        'reasons', r.reasons, 'reporters', r.reporters,
        'content', case r.kind
          when 'post' then (select jsonb_build_object('text', p.body, 'photo_path', p.photo_path, 'author_id', p.user_id, 'author', (select username from profiles where id = p.user_id), 'hidden', p.hidden, 'at', p.created_at) from gist_posts p where p.id = r.target_id)
          when 'comment' then (select jsonb_build_object('text', c.body, 'author_id', c.user_id, 'author', (select username from profiles where id = c.user_id), 'hidden', c.hidden, 'at', c.created_at, 'post_id', c.post_id) from gist_comments c where c.id = r.target_id)
          when 'message' then (select jsonb_build_object('text', coalesce(m.body, case m.kind when 'voice' then '(voice note)' when 'money' then '(money bubble)' else '' end), 'author_id', m.user_id, 'author', m.username, 'hidden', m.hidden, 'at', m.created_at, 'group_id', m.group_id, 'group', (select name from gist_groups where id = m.group_id)) from gist_messages m where m.id = r.target_id)
          else (select jsonb_build_object('text', g.name || ' · ' || g.description, 'author_id', g.owner_id, 'author', (select username from profiles where id = g.owner_id), 'hidden', g.hidden, 'at', g.created_at, 'members', g.member_count, 'is_public', g.is_public) from gist_groups g where g.id = r.target_id) end)
        as j
        from (select kind, target_id, count(*) as n, max(created_at) as last_at, case when bool_or(status = 'open') then 'open' else 'done' end as status,
                     jsonb_agg(distinct reason) filter (where coalesce(reason, '') <> '') as reasons,
                     jsonb_agg((select username from profiles where id = reporter_id)) as reporters
                from gist_reports
               where p_status = 'all' or status = 'open'
               group by kind, target_id order by max(created_at) desc limit 200) r) x
     where x.j is not null), '[]'::jsonb);
end $$;

create or replace function public.admin_gist_hide(p_kind text, p_id bigint, p_hidden boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_target uuid;
begin
  if p_kind = 'post' then update gist_posts set hidden = coalesce(p_hidden, true), hidden_reason = case when coalesce(p_hidden, true) then 'admin' end where id = p_id returning user_id into v_target;
  elsif p_kind = 'comment' then update gist_comments set hidden = coalesce(p_hidden, true) where id = p_id returning user_id into v_target;
  elsif p_kind = 'message' then update gist_messages set hidden = coalesce(p_hidden, true) where id = p_id returning user_id into v_target;
  elsif p_kind = 'group' then update gist_groups set hidden = coalesce(p_hidden, true) where id = p_id returning owner_id into v_target;
  else raise exception 'Unknown kind.' using errcode = 'P0001', hint = 'bad_kind'; end if;
  if not found then raise exception 'That is gone already.' using errcode = 'P0001', hint = 'not_found'; end if;
  if coalesce(p_hidden, true) then update gist_reports set status = 'done' where kind = p_kind and target_id = p_id; end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, case when coalesce(p_hidden, true) then 'gist_hide' else 'gist_unhide' end, v_target, jsonb_build_object('kind', p_kind, 'id', p_id));
  return jsonb_build_object('message', case when coalesce(p_hidden, true) then 'Hidden.' else 'Visible again.' end, 'hidden', coalesce(p_hidden, true));
end $$;

create or replace function public.admin_gist_delete(p_kind text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_target uuid; v_photo text; v_text text; v_post bigint;
begin
  if p_kind = 'post' then
    select user_id, photo_path, left(body, 200) into v_target, v_photo, v_text from gist_posts where id = p_id;
    delete from gist_posts where id = p_id;
  elsif p_kind = 'comment' then
    select user_id, left(body, 200), post_id into v_target, v_text, v_post from gist_comments where id = p_id;
    delete from gist_comments where id = p_id;
    if v_post is not null then perform bl_gist_recount(v_post); end if;
  elsif p_kind = 'message' then
    select user_id, left(body, 200) into v_target, v_text from gist_messages where id = p_id;
    update gist_messages set body = null, audio_path = null, audio_mime = null, deleted_at = bl_now(), hidden = false,
           kind = case when kind in ('text', 'voice') then kind else 'system' end where id = p_id and deleted_at is null;
    update gist_groups set pinned_id = null where pinned_id = p_id;
  elsif p_kind = 'group' then
    select owner_id, name into v_target, v_text from gist_groups where id = p_id and not system;
    delete from gist_groups where id = p_id and not system;
  else raise exception 'Unknown kind.' using errcode = 'P0001', hint = 'bad_kind'; end if;
  if v_text is null and v_target is null then raise exception 'That is gone already (or it is an official group).' using errcode = 'P0001', hint = 'not_found'; end if;
  update gist_reports set status = 'done' where kind = p_kind and target_id = p_id;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'gist_delete', v_target, jsonb_build_object('kind', p_kind, 'id', p_id, 'text', v_text, 'photo_path', v_photo));
  return jsonb_build_object('message', 'Deleted.', 'photo_path', v_photo);
end $$;

-- recount a post's comments after an admin deleted one
create or replace function public.bl_gist_recount(p_post bigint) returns void
language sql set search_path = public as $$
  update gist_posts p set comment_count = (select count(*) from gist_comments c where c.post_id = p.id),
         rank_key = bl_gist_rank(p.like_count, (select count(*)::int from gist_comments c where c.post_id = p.id), p.created_at)
   where p.id = p_post
$$;

create or replace function public.admin_gist_dismiss(p_kind text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard();
begin
  update gist_reports set status = 'done' where kind = p_kind and target_id = p_id;
  insert into admin_audit (admin_id, action, data) values (v_admin, 'gist_dismiss', jsonb_build_object('kind', p_kind, 'id', p_id));
  return jsonb_build_object('message', 'Reports cleared.');
end $$;

-- Ban a player from Benin Gist (p_hours null = for good). p_hide also hides everything they posted. p_banned false lifts the ban.
create or replace function public.admin_gist_ban(p_user uuid, p_banned boolean default true, p_hours int default null, p_reason text default null,
                                                 p_hide boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_until timestamptz;
begin
  if not exists (select 1 from profiles where id = p_user) then raise exception 'No such player.' using errcode = 'P0001', hint = 'not_found'; end if;
  if coalesce(p_banned, true) then
    v_until := case when p_hours is null or p_hours <= 0 then null else bl_now() + make_interval(hours => p_hours) end;
    insert into gist_bans (user_id, until_at, reason, banned_by) values (p_user, v_until, left(p_reason, 200), v_admin)
    on conflict (user_id) do update set until_at = excluded.until_at, reason = excluded.reason, banned_by = excluded.banned_by, created_at = now();
    if p_hide then
      update gist_posts set hidden = true, hidden_reason = 'admin' where user_id = p_user and not hidden;
      update gist_comments set hidden = true where user_id = p_user and not hidden;
    end if;
  else
    delete from gist_bans where user_id = p_user;
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, case when coalesce(p_banned, true) then 'gist_ban' else 'gist_unban' end, p_user,
          jsonb_build_object('hours', p_hours, 'reason', p_reason, 'hide', p_hide));
  return jsonb_build_object('message', case when coalesce(p_banned, true) then 'Banned from Benin Gist.' else 'Ban lifted.' end);
end $$;

create or replace function public.admin_gist_bans() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', b.user_id, 'username', p.username, 'until_at', b.until_at, 'reason', b.reason, 'created_at', b.created_at)
                                    order by b.created_at desc)
                     from gist_bans b left join profiles p on p.id = b.user_id where b.until_at is null or b.until_at > now()), '[]'::jsonb);
end $$;

create or replace function public.admin_gist_groups(p_query text default null, p_limit int default 60) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pat text := case when nullif(btrim(coalesce(p_query, '')), '') is null then null else '%' || btrim(p_query) || '%' end;
begin
  perform bl_admin_guard();
  return coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'emoji', g.emoji, 'description', g.description, 'is_public', g.is_public,
                                                       'system', g.system, 'hidden', g.hidden, 'members', g.member_count, 'member_cap', g.member_cap,
                                                       'owner', (select username from profiles where id = g.owner_id), 'last_msg_at', g.last_msg_at,
                                                       'created_at', g.created_at)
                                    order by g.system desc, g.last_msg_at desc nulls last, g.id desc)
                     from (select * from gist_groups where v_pat is null or name ilike v_pat order by system desc, id desc limit least(greatest(coalesce(p_limit, 60), 1), 200)) g), '[]'::jsonb);
end $$;

-- edit a group as an admin (rename the starter groups here). p_cap 0 = back to the default cap.
create or replace function public.admin_gist_group_set(p_id bigint, p_name text default null, p_emoji text default null, p_description text default null,
                                                       p_cap int default null, p_hidden boolean default null, p_public boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); g gist_groups; v_name text;
begin
  select * into g from gist_groups where id = p_id;
  if not found then raise exception 'No such group.' using errcode = 'P0001', hint = 'not_found'; end if;
  v_name := coalesce(nullif(btrim(p_name), ''), g.name);
  if char_length(v_name) < 3 or char_length(v_name) > 40 then raise exception 'A group name needs 3 to 40 characters.' using errcode = 'P0001', hint = 'bad_name'; end if;
  update gist_groups set name = v_name, emoji = left(coalesce(nullif(btrim(p_emoji), ''), g.emoji), 8),
         description = left(coalesce(p_description, g.description), 300),
         member_cap = case when p_cap is null then member_cap when p_cap <= 0 then null else least(p_cap, 5000) end,
         hidden = coalesce(p_hidden, hidden), is_public = coalesce(p_public, is_public)
   where id = p_id returning * into g;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'gist_group_set', g.owner_id, jsonb_build_object('id', p_id, 'name', g.name, 'cap', g.member_cap, 'hidden', g.hidden));
  return jsonb_build_object('message', 'Group saved.', 'id', g.id);
end $$;

-- photo files no gist uses any more (deleted / expired gists, failed posts). The admin page removes them through Storage.
create or replace function public.admin_gist_orphan_photos(p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public, storage as $$
begin
  perform bl_admin_guard();
  return coalesce((select jsonb_agg(jsonb_build_object('name', o.name, 'bytes', (o.metadata ->> 'size')::bigint, 'created_at', o.created_at))
                     from (select * from storage.objects o where o.bucket_id = 'gist-photos' and o.created_at < now() - interval '1 hour'
                              and not exists (select 1 from public.gist_posts p where p.photo_path = o.name)
                            order by o.created_at limit least(greatest(coalesce(p_limit, 200), 1), 500)) o), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. Starter groups (names and descriptions are editable in Admin -> Gist -> Groups)
-- ---------------------------------------------------------------------------------------------
insert into public.gist_groups (slug, name, emoji, description, is_public, system, member_cap) values
('general',  'Benin Gist General', '🗣️', 'The main gist. Say hello, ask anything, share what is happening around Benin City.', true, true, 500),
('uniben',   'UNIBEN Students',    '🎓', 'Ugbowo gist: lectures, hostel life, school fees and campus hustles.', true, true, null),
('ringroad', 'Ring Road Hustlers', '💼', 'Side hustles, gigs and money talk from Ring Road to Oba Market.', true, true, null),
('owambe',   'Owambe & Clubs',     '🪩', 'Owambe, club nights, music and who is spraying what.', true, true, null),
('buysell',  'Buy & Sell',         '🏷️', 'Selling something or hunting for a deal? Post it here. Stay safe: meet in public places.', true, true, null)
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 11. Privileges: helpers revoked, player RPCs for authenticated only, admin RPCs for authenticated (each re-checks bl_admin_guard)
-- ---------------------------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'bl_gist_me(boolean)', 'bl_gist_text(text, int, boolean)', 'bl_gist_rank(int, int, timestamptz)', 'bl_gist_lse(double precision, double precision)',
    'bl_gist_blocked(uuid, uuid)', 'bl_gist_user(uuid)', 'bl_gist_post_json(public.gist_posts, uuid)', 'bl_gist_msg_json(public.gist_messages, uuid)',
    'bl_gist_role(bigint, uuid)', 'bl_gist_group_json(public.gist_groups, uuid)', 'bl_gist_mentions(text, uuid, bigint)',
    'bl_gist_notify(uuid, text, bigint, uuid, text, text, text, text, text, jsonb)', 'bl_gist_claim(text, interval)', 'bl_gist_sweep()',
    'bl_gist_send_check(bigint, uuid)', 'bl_gist_message_add(public.gist_groups, public.profiles, text, text, text, text, bigint, uuid, text, bigint)',
    'bl_gist_recount(bigint)'
  ] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
  foreach f in array array[
    'gist_summary()', 'gist_post(text, text)', 'gist_feed(text, bigint, bigint, int, text)', 'gist_post_get(bigint)', 'gist_delete_post(bigint)',
    'gist_like(bigint, boolean)', 'gist_follow(uuid, boolean)', 'gist_profile(uuid)', 'gist_user_posts(uuid, bigint, int)', 'gist_trending()',
    'gist_comment(bigint, text, bigint)', 'gist_comments(bigint, bigint, int)', 'gist_delete_comment(bigint)', 'gist_tip_post(bigint, bigint, text)',
    'gist_report(text, bigint, text)',
    'gist_group_create(text, text, text, boolean)', 'gist_groups_mine()', 'gist_groups_discover(text, text, int)', 'gist_group_get(bigint)',
    'gist_group_join(bigint)', 'gist_group_leave(bigint)', 'gist_group_members(bigint, int, int)', 'gist_group_add(bigint, text)',
    'gist_group_remove(bigint, uuid)', 'gist_group_set_role(bigint, uuid, text)', 'gist_group_mute(bigint, uuid, int)', 'gist_group_pin(bigint, bigint)',
    'gist_group_update(bigint, text, text, text, boolean)', 'gist_group_delete(bigint)', 'gist_group_send(bigint, text, text, text, bigint)',
    'gist_group_send_money(bigint, text, bigint, text)', 'gist_group_history(bigint, bigint, int)', 'gist_group_after(bigint, bigint, int)',
    'gist_group_mark_read(bigint, bigint)', 'gist_group_delete_message(bigint)',
    'admin_gist_overview()', 'admin_gist_reports(text)', 'admin_gist_hide(text, bigint, boolean)', 'admin_gist_delete(text, bigint)',
    'admin_gist_dismiss(text, bigint)', 'admin_gist_ban(uuid, boolean, int, text, boolean)', 'admin_gist_bans()', 'admin_gist_groups(text, int)',
    'admin_gist_group_set(bigint, text, text, text, int, boolean, boolean)', 'admin_gist_orphan_photos(int)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
