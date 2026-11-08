-- Free roam, phase 3 (docs/ROAM.md "Live players"): see other real players in the street, walking or driving, with name tags, waves,
-- emotes and short chat bubbles. Designed for identity, privacy, cost and Supabase Realtime limits:
--   * IDENTITY CANNOT BE FORGED (Realtime Authorization). Positions travel on private broadcast channels, ONE PER PLAYER, topic
--     'roam:u:<auth.uid()>'. The INSERT policy on realtime.messages lets a player write only on the topic of his own uid, so nobody can
--     broadcast a position or an emote under another name. Name, look, car and badges never come from a payload: they come from the
--     server (profiles) through roam_live_tick / roam_nearby. Chat bubbles are NOT client-writable at all: roam_say (below) filters the
--     text and the database itself sends it with realtime.send() on the speaker's read-only text topic 'roam:t:<uid>' (no insert policy exists;
--     the read policy is the same as for positions: near, visible, not blocked either way, not banned).
--   * INTEREST MANAGEMENT. roam_presence (user_id pk, cell, mode, updated_at) is upserted by roam_live_tick at most once per
--     roam.live.presence_min_s (rate limited, a refused write is a cheap no-op). roam_nearby returns the N nearest players of your cell
--     and its 8 neighbours, never hidden-location / opted-out / banned / blocked (either way) / stale ones. Clients subscribe only to
--     those players' topics; there is no per-frame database write. The read policy re-checks the same rules when a topic is joined.
--   * Privacy: "Show me to others in free roam" (roam_prefs.show_me, default on) AND the existing friends location privacy
--     (profiles.share_location_friends = false hides you here too). A hidden player has no presence row, may not publish (write policy
--     needs a fresh row), is never listed, and still SEES others.
--   * Bubbles: roam_say applies bl_chat_clean + the banned-word mask, the new-account rule, the chat mute, a rate limit (gap + per minute),
--     keeps a short-lived log (roam.bubble.log_hours, cleaned a few rows per call) for reports, and sends to the cells within the bubble
--     radius of the speaker. roam_report snapshots the reported player's last bubble.
--   * Every number is a setting in category "roam" (Admin -> Settings -> Free roam).
-- No profiles DDL, no triggers, no foreign keys, no loops over players. Live functions are patched by guarded single replace through the
-- unique helper pg_temp.roam3_patch. Idempotent.

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (category roam)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('roam.live.enabled', 'true', 'roam', 'Live players in free roam', 'Master switch for seeing other real players in the street. Off = free roam works alone (players see a small "Live players off" note), presence is not written and the Realtime topics are closed.', 'bool', null, null),
('roam.live.max_shown', '8', 'roam', 'Live players: most shown at once', 'The server returns at most this many of the nearest players (the phone shows fewer on Graphics Low). Every one costs a Realtime channel and about 1 to 3 messages a second.', 'number', 1, 40),
('roam.live.low_max', '5', 'roam', 'Live players: most shown on Graphics Low', 'Weak phones draw and listen to this many players at most.', 'number', 1, 40),
('roam.live.radius_m', '100', 'roam', 'Live players: how far you see them (metres)', 'Nearby players are listed within this distance. Keep it at or below the cell size, or players near a cell edge are missed.', 'number', 30, 400),
('roam.live.cell_m', '100', 'roam', 'Live players: cell size (metres)', 'The map is cut into square cells; you are listed players from your cell and the eight round it. Players save their cell every presence interval. Changing it takes effect within half a minute.', 'number', 40, 500),
('roam.live.presence_s', '9', 'roam', 'Live players: presence interval (seconds)', 'How often a phone tells the server where it is and asks who is near (one call). Never every frame.', 'number', 4, 60),
('roam.live.presence_min_s', '5', 'roam', 'Live players: shortest gap between presence writes (seconds)', 'Rate limit on the server: a presence call sooner than this after the last one only reads the nearby list, it writes nothing.', 'number', 1, 60),
('roam.live.stale_s', '45', 'roam', 'Live players: a player not heard of for this long is gone (seconds)', 'Presence rows older than this are never listed (and are deleted in small batches).', 'number', 10, 300),
('roam.live.move_hz', '2', 'roam', 'Live players: position messages a second while moving (at most)', 'The phone also sends less when you walk straight (the others predict the path). Lower = less data, jerkier far-away players.', 'number', 0.5, 6),
('roam.live.idle_s', '20', 'roam', 'Live players: seconds between messages while standing still', 'A standing player only sends a keep-alive this often. Others also get his place from the server every presence interval, so a long gap costs nothing visible.', 'number', 2, 120),
('roam.live.budget_mps', '3', 'roam', 'Live players: message budget per player (messages a second delivered)', 'Every position message is delivered to each player who listens, so it costs (1 + listeners) Realtime messages. A phone sends at most this many messages a second counting all listeners: with 3 near it may send 1 a second, with 8 near one every 2.7 seconds. This is the main lever on the Realtime message count and the plan limit (Free 100 a second, Pro 500). Keep it low while the Realtime budget is small.', 'number', 1, 100),
('roam.live.buffer_ms', '200', 'roam', 'Live players: smoothing delay (milliseconds)', 'Other players are drawn this far in the past so they glide instead of jump. 150 to 250 is good.', 'number', 80, 600),
('roam.live.emotes', 'true', 'roam', 'Wave and emotes', 'Off = no Wave / emote buttons and other players'' emotes are not shown.', 'bool', null, null),
('roam.bubble.enabled', 'true', 'roam', 'Chat bubbles over heads', 'Off = no bubbles (roam_say is refused). The bubble goes through the same word filter and mute rules as the chat.', 'bool', null, null),
('roam.bubble.len', '80', 'roam', 'Chat bubble: longest text (characters)', 'Longer text is cut.', 'number', 10, 200),
('roam.bubble.radius_m', '25', 'roam', 'Chat bubble: heard within (metres)', 'Only players this close to the speaker get the bubble.', 'number', 5, 100),
('roam.bubble.gap_s', '3', 'roam', 'Chat bubble: shortest gap between two bubbles (seconds)', 'Per player.', 'number', 0, 60),
('roam.bubble.max_min', '10', 'roam', 'Chat bubble: most bubbles a minute', 'Per player.', 'number', 1, 60),
('roam.bubble.log_hours', '24', 'roam', 'Chat bubble: how long the report log is kept (hours)', 'Bubbles are not stored for long: only so a report can show what was said. Old rows are deleted a few at a time.', 'number', 1, 168),
('roam.report.max_hour', '6', 'roam', 'Reports: most player reports an hour', 'Per player.', 'number', 1, 100)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables (own tables, no profiles column, no foreign keys, no triggers; read only through the RPCs)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.roam_prefs (
  user_id    uuid primary key,
  show_me    boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.roam_presence (
  user_id    uuid primary key,
  cx         smallint not null,
  cy         smallint not null,
  x          real not null,
  y          real not null,
  mode       text not null default 'walk',
  veh        text,
  updated_at timestamptz not null default now()
);
alter table public.roam_presence add column if not exists hidden boolean not null default false;
alter table public.roam_presence add column if not exists nearby_at timestamptz;
create index if not exists roam_presence_cell_idx on public.roam_presence (cx, cy);
create index if not exists roam_presence_upd_idx on public.roam_presence (updated_at);

create table if not exists public.roam_bubbles (
  id         bigserial primary key,
  user_id    uuid not null,
  body       text not null,
  x          real,
  y          real,
  created_at timestamptz not null default now()
);
create index if not exists roam_bubbles_user_idx on public.roam_bubbles (user_id, created_at desc);
create index if not exists roam_bubbles_time_idx on public.roam_bubbles (created_at);

create table if not exists public.roam_reports (
  id          bigserial primary key,
  reporter_id uuid not null,
  reported_id uuid not null,
  reason      text,
  bubble      text,
  created_at  timestamptz not null default now()
);
create index if not exists roam_reports_reporter_idx on public.roam_reports (reporter_id, created_at desc);
create index if not exists roam_reports_reported_idx on public.roam_reports (reported_id, created_at desc);

alter table public.roam_prefs enable row level security;
alter table public.roam_presence enable row level security;
alter table public.roam_bubbles enable row level security;
alter table public.roam_reports enable row level security;
revoke all on public.roam_prefs, public.roam_presence, public.roam_bubbles, public.roam_reports from anon, authenticated;
revoke all on sequence public.roam_bubbles_id_seq, public.roam_reports_id_seq from anon, authenticated;

-- signatures of the first draft (idempotent re-runs)
drop policy if exists roam_bubble_read on realtime.messages;
drop function if exists public.bl_roam_nearby(uuid, numeric, numeric, uuid[]);
drop function if exists public.roam_nearby(numeric, numeric, uuid[]);
drop function if exists public.roam_bubble_topic_ok(text);

-- ---------------------------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_roam_live_gate() returns void
language plpgsql stable set search_path = public as $$
begin
  if not bl_cfg_bool('roam.enabled') or not bl_cfg_bool('roam.live.enabled') then
    raise exception 'Live players are switched off for now.' using errcode = 'P0001', hint = 'off';
  end if;
end $$;

-- the caller's profile for live roam: logged in, has a Sim, not banned. No lock and no write (a presence call every few seconds must
-- not touch the profile row: that would push a profile refresh to the client each time).
create or replace function public.bl_roam_light_me() returns public.profiles
language plpgsql stable set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v profiles;
begin
  select * into v from profiles where id = v_uid;
  if not found then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v.banned then
    raise exception 'This account has been banned. If this is a mistake, contact the admin.' using errcode = 'P0001', hint = 'banned';
  end if;
  return v;
end $$;

-- may this player be shown to others? (his own setting AND the friends location privacy AND not banned)
create or replace function public.bl_roam_visible(p_uid uuid) returns boolean
language sql stable set search_path = public as $$
  select coalesce((select r.show_me from roam_prefs r where r.user_id = p_uid), true)
     and exists (select 1 from profiles p where p.id = p_uid and not p.banned and p.share_location_friends);
$$;

-- one presence write (rate limited by roam.live.presence_min_s) for a player who has a live street session
create or replace function public.bl_roam_presence_write(p_me public.profiles, p_x numeric, p_y numeric) returns jsonb
language plpgsql volatile set search_path = public as $$
declare
  v_now  timestamptz := bl_now();
  s      roam_sessions;
  pr     roam_presence;
  v_cs   numeric := greatest(20, bl_cfg('roam.live.cell_m'));
  v_x    numeric := least(1000, greatest(0, coalesce(p_x, 0)));
  v_y    numeric := least(1000, greatest(0, coalesce(p_y, 0)));
  v_show boolean;
  v_hide boolean;
  v_why  text;
  v_dt   numeric;
  v_allow numeric;
  v_d    numeric;
begin
  select * into s from roam_sessions where user_id = p_me.id;
  if not found or s.ended or v_now - s.started_at > make_interval(secs => bl_cfg('roam.session_ttl_s')) then
    delete from roam_presence where user_id = p_me.id;
    return jsonb_build_object('visible', false, 'why', 'no_session');
  end if;
  v_show := coalesce((select r.show_me from roam_prefs r where r.user_id = p_me.id), true);
  v_hide := not v_show or not p_me.share_location_friends;
  v_why := case when not v_show then 'off' when not p_me.share_location_friends then 'location' else null end;
  select * into pr from roam_presence where user_id = p_me.id;
  if found and pr.hidden = v_hide and v_now - pr.updated_at < make_interval(secs => bl_cfg('roam.live.presence_min_s')) then
    return jsonb_build_object('visible', not v_hide, 'why', v_why, 'throttled', true);
  end if;
  -- the position is the phone's claim, bounded by what the last one allows (the fastest vehicle plus slack): no jumping across the city
  -- to look at other streets
  if found then
    v_dt := greatest(1, extract(epoch from v_now - pr.updated_at));
    v_allow := bl_cfg('roam.drive.max_speed_mps') * v_dt + 20;
    v_d := sqrt((v_x - pr.x) ^ 2 + (v_y - pr.y) ^ 2);
    if v_d > v_allow then
      v_x := pr.x + (v_x - pr.x) * v_allow / v_d;
      v_y := pr.y + (v_y - pr.y) * v_allow / v_d;
    end if;
  end if;
  -- a hidden player keeps a row (hidden = true): it anchors his own position so he can still see others, and nobody else is ever shown it
  insert into roam_presence (user_id, cx, cy, x, y, mode, veh, hidden, updated_at)
  values (p_me.id, floor(v_x / v_cs)::smallint, floor(v_y / v_cs)::smallint, v_x, v_y,
          case when s.mode = 'car' then 'car' else 'walk' end, case when s.mode = 'car' then s.vehicle end, v_hide, v_now)
  on conflict (user_id) do update
    set cx = excluded.cx, cy = excluded.cy, x = excluded.x, y = excluded.y, mode = excluded.mode, veh = excluded.veh,
        hidden = excluded.hidden, updated_at = excluded.updated_at;
  -- cheap cleanup: at most 25 rows nobody has refreshed for 10 minutes (an index range scan on updated_at, never a table loop)
  delete from roam_presence where user_id in (select d.user_id from roam_presence d where d.updated_at < v_now - interval '10 minutes' order by d.updated_at limit 25);
  return jsonb_build_object('visible', not v_hide, 'why', v_why, 'throttled', false);
end $$;

-- the nearest players (up to roam.live.max_shown) of the VIEWER's own cell and the 8 round it, from his own presence row (never from a position
-- the phone sends here). Positions go out rounded to 1 m. p_have = ids whose static info (name, avatar,
-- badges) the phone already holds: for those only the moving bits are sent.
create or replace function public.bl_roam_nearby(p_me uuid, p_have uuid[]) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_now  timestamptz := bl_now();
  me     roam_presence;
  v_rad  numeric := bl_cfg('roam.live.radius_m');
  v_n    int := least(40, greatest(1, bl_cfg('roam.live.max_shown')::int));
  v_have uuid[] := coalesce(p_have[1:60], '{}');
begin
  select * into me from roam_presence where user_id = p_me;
  if not found or me.updated_at < v_now - make_interval(secs => bl_cfg('roam.live.stale_s')) then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(q.j order by q.d)
      from (
        select ((p.x - me.x) ^ 2 + (p.y - me.y) ^ 2) as d,
               jsonb_build_object('id', p.user_id, 'm', p.mode, 'v', p.veh, 'x', round(p.x::numeric, 0), 'y', round(p.y::numeric, 0))
               || case when p.user_id = any (v_have) then '{}'::jsonb
                  else jsonb_build_object('n', pr.username, 'av', pr.avatar, 'sc', pr.street_cred, 't', bl_pol_title(p.user_id), 'c', bl_crew_badge(p.user_id)) end as j
          from roam_presence p
          join profiles pr on pr.id = p.user_id
         where p.cx between me.cx - 1 and me.cx + 1 and p.cy between me.cy - 1 and me.cy + 1
           and p.user_id <> p_me
           and not p.hidden
           and p.updated_at > v_now - make_interval(secs => bl_cfg('roam.live.stale_s'))
           and not pr.banned and pr.share_location_friends
           and coalesce((select r.show_me from roam_prefs r where r.user_id = p.user_id), true)
           and not exists (select 1 from chat_blocks b
                            where (b.blocker_id = p_me and b.blocked_id = p.user_id) or (b.blocker_id = p.user_id and b.blocked_id = p_me))
           and (p.x - me.x) ^ 2 + (p.y - me.y) ^ 2 <= v_rad ^ 2
         order by d
         limit v_n) q
  ), '[]'::jsonb);
end $$;

-- Realtime Authorization for the two topic kinds: 'roam:u:<uid>' (positions, written by the player) and 'roam:t:<uid>' (his chat bubbles,
-- written only by roam_say through the database). Write = own position topic only, while visible with a fresh presence row.
-- Read = own topic, or the topic of a visible, fresh, not-blocked (both ways), not-banned player whose presence cell is within 1 cell of the
-- VIEWER's own fresh presence row, while the viewer has a live street session. So a topic can only be read where nearby would list the player. Joins are checked
-- once and cached by Realtime, so this is not run per message.
create or replace function public.roam_topic_ok(p_topic text, p_write boolean) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_me    uuid := auth.uid();
  v_t     uuid;
  v_now   timestamptz := bl_now();
  v_stale numeric := bl_cfg('roam.live.stale_s');
  vr      roam_presence;
  tr      roam_presence;
begin
  if v_me is null or p_topic is null or p_topic !~ '^roam:[ut]:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  if not bl_cfg_bool('roam.enabled') or not bl_cfg_bool('roam.live.enabled') then
    return false;
  end if;
  v_t := substr(p_topic, 8)::uuid;
  select * into vr from roam_presence where user_id = v_me;
  if p_write then
    return substr(p_topic, 6, 1) = 'u' and v_t = v_me and found and not vr.hidden and bl_roam_visible(v_me)
       and vr.updated_at > v_now - make_interval(secs => v_stale);
  end if;
  if v_t = v_me then
    return true;
  end if;
  -- the viewer: a live street session (not ended, not timed out) and a fresh presence row
  if not found or vr.updated_at <= v_now - make_interval(secs => v_stale) then
    return false;
  end if;
  if not exists (select 1 from roam_sessions s where s.user_id = v_me and not s.ended
                  and v_now - s.started_at <= make_interval(secs => bl_cfg('roam.session_ttl_s'))) then
    return false;
  end if;
  select * into tr from roam_presence where user_id = v_t;
  if not found or tr.hidden or tr.updated_at <= v_now - make_interval(secs => v_stale)
     or abs(tr.cx - vr.cx) > 1 or abs(tr.cy - vr.cy) > 1 then
    return false;
  end if;
  return bl_roam_visible(v_t)
     and not exists (select 1 from chat_blocks b
                      where (b.blocker_id = v_me and b.blocked_id = v_t) or (b.blocker_id = v_t and b.blocked_id = v_me));
end $$;


-- ---------------------------------------------------------------------------------------------
-- 4. RPCs (security definer; the ones that write are volatile)
-- ---------------------------------------------------------------------------------------------
-- Settings and the caller's own state for the phone: switches, hints, who he blocked. Works while the feature is off (enabled = false).
create or replace function public.roam_live_info() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me profiles := bl_roam_light_me();
begin
  return jsonb_build_object(
    'enabled', bl_cfg_bool('roam.enabled') and bl_cfg_bool('roam.live.enabled'),
    'show_me', coalesce((select r.show_me from roam_prefs r where r.user_id = v_me.id), true),
    'location_hidden', not v_me.share_location_friends,
    'presence_s', bl_cfg('roam.live.presence_s'), 'max_shown', bl_cfg('roam.live.max_shown'), 'low_max', bl_cfg('roam.live.low_max'),
    'radius_m', bl_cfg('roam.live.radius_m'), 'move_hz', bl_cfg('roam.live.move_hz'), 'idle_s', bl_cfg('roam.live.idle_s'), 'budget_mps', bl_cfg('roam.live.budget_mps'),
    'buffer_ms', bl_cfg('roam.live.buffer_ms'), 'emotes', bl_cfg_bool('roam.live.emotes'), 'cell_m', bl_cfg('roam.live.cell_m'),
    'bubble', bl_cfg_bool('roam.bubble.enabled'), 'bubble_len', bl_cfg('roam.bubble.len'), 'bubble_m', bl_cfg('roam.bubble.radius_m'),
    'bubble_gap_s', bl_cfg('roam.bubble.gap_s'),
    'me', v_me.id,
    'blocked', coalesce((select jsonb_agg(b.blocked_id) from (select blocked_id from chat_blocks where blocker_id = v_me.id limit 300) b), '[]'::jsonb));
end $$;

-- "Show me to others in free roam" (default on)
create or replace function public.roam_set_show(p_show boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_roam_light_me(); v_show boolean := coalesce(p_show, true);
begin
  insert into roam_prefs (user_id, show_me, updated_at) values (v_me.id, v_show, bl_now())
  on conflict (user_id) do update set show_me = excluded.show_me, updated_at = excluded.updated_at;
  -- hiding takes effect at once: the row stays (it anchors his own position) but is marked hidden
  if not v_show then
    update roam_presence set hidden = true where user_id = v_me.id;
  end if;
  return jsonb_build_object('ok', true, 'show_me', v_show,
    'message', case when v_show then 'Other players can see you in free roam.' else 'You are hidden from other players in free roam.' end);
end $$;

-- write only
create or replace function public.roam_presence_set(p_x numeric, p_y numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles;
begin
  perform bl_roam_live_gate();
  v_me := bl_roam_light_me();
  return bl_roam_presence_write(v_me, p_x, p_y);
end $$;

-- read only
create or replace function public.roam_nearby(p_have uuid[] default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles; v_now timestamptz := bl_now(); pr roam_presence;
begin
  perform bl_roam_live_gate();
  v_me := bl_roam_light_me();
  -- needs a live street session and a presence row (written by roam_live_tick): the position is HIS row, not a number he sends
  if not exists (select 1 from roam_sessions s where s.user_id = v_me.id and not s.ended
                  and v_now - s.started_at <= make_interval(secs => bl_cfg('roam.session_ttl_s'))) then
    raise exception 'Step out into the street first.' using errcode = 'P0001', hint = 'no_session';
  end if;
  select * into pr from roam_presence where user_id = v_me.id for update;
  if not found then
    raise exception 'Say where you are first (roam_live_tick).' using errcode = 'P0001', hint = 'no_presence';
  end if;
  if pr.nearby_at is not null and v_now - pr.nearby_at < make_interval(secs => bl_cfg('roam.live.presence_min_s') / 2) then
    raise exception 'Slow down a little.' using errcode = 'P0001', hint = 'too_fast';
  end if;
  update roam_presence set nearby_at = v_now where user_id = v_me.id;
  return jsonb_build_object('players', bl_roam_nearby(v_me.id, p_have));
end $$;

-- the phone's one call every roam.live.presence_s: tell the server where I am, get who is near
create or replace function public.roam_live_tick(p_x numeric, p_y numeric, p_have uuid[] default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles; w jsonb;
begin
  perform bl_roam_live_gate();
  v_me := bl_roam_light_me();
  w := bl_roam_presence_write(v_me, p_x, p_y);
  -- a throttled call (sooner than presence_min_s) does no query at all and answers players = null ("no change")
  return w || jsonb_build_object('next_s', bl_cfg('roam.live.presence_s'),
    'players', case when w ->> 'why' = 'no_session' then '[]'::jsonb
                    when (w ->> 'throttled')::boolean then null
                    else bl_roam_nearby(v_me.id, p_have) end);
end $$;

-- leaving the street (or switching live off on the phone): gone at once
create or replace function public.roam_live_stop() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  delete from roam_presence where user_id = v_uid;
  return jsonb_build_object('ok', true);
end $$;

-- A chat bubble. Applies the chat rules (switch, mute, new account, word filter, duplicates) and its own rate limit, keeps a short log for
-- reports and sends it from the database on the SPEAKER's read-only text topic 'roam:t:<uid>'. Only players the read policy lets in (near,
-- visible, not blocked either way, not banned) can listen, so blocks are enforced by the server. The sender sees his own bubble from the answer.
create or replace function public.roam_say(p_text text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles;
  v_now  timestamptz := bl_now();
  v_len  int := least(200, greatest(10, bl_cfg('roam.bubble.len')::int));
  v_body text;
  v_mask text;
  v_gap  numeric := bl_cfg('roam.bubble.gap_s');
  v_new  numeric := bl_cfg('chat.min_account_real_minutes');
  v_dup  numeric := bl_cfg('chat.duplicate_window_seconds');
  pr     roam_presence;
  v_last timestamptz;
  v_n    int;
  v_id   bigint;
begin
  perform bl_roam_live_gate();
  if not bl_cfg_bool('roam.bubble.enabled') then
    raise exception 'Chat bubbles are switched off for now.' using errcode = 'P0001', hint = 'off';
  end if;
  if not bl_cfg_bool('chat.enabled') then
    raise exception 'Chat is switched off for now. Try again later.' using errcode = 'P0001', hint = 'chat_off';
  end if;
  v_me := bl_chat_me();
  if v_me.chat_muted_until is not null and v_me.chat_muted_until > v_now then
    raise exception 'You can''t chat for now (muted by a moderator). Try again in about % min.', ceil(extract(epoch from v_me.chat_muted_until - v_now) / 60) using errcode = 'P0001', hint = 'muted';
  end if;
  if coalesce(v_new, 0) > 0 and v_me.created_at > v_now - make_interval(secs => (v_new * 60)::double precision) then
    raise exception 'New Sims can chat after % minutes. Look around first!', ceil(v_new) using errcode = 'P0001', hint = 'too_new';
  end if;
  v_body := left(bl_chat_clean(p_text), v_len);
  if v_body = '' then
    raise exception 'Type a message first.' using errcode = 'P0001', hint = 'empty';
  end if;
  select * into pr from roam_presence where user_id = v_me.id;
  if not found or pr.hidden or pr.updated_at < v_now - make_interval(secs => bl_cfg('roam.live.stale_s')) or not bl_roam_visible(v_me.id) then
    raise exception 'Other players can''t see you right now, so nobody would hear you. Check "Show me to others".' using errcode = 'P0001', hint = 'hidden';
  end if;
  select max(created_at), count(*) filter (where created_at > v_now - interval '60 seconds') into v_last, v_n
    from roam_bubbles where user_id = v_me.id and created_at > v_now - interval '2 minutes';
  if v_last is not null and v_gap > 0 and v_last > v_now - make_interval(secs => v_gap::double precision) then
    raise exception 'Slow down small. Wait a few seconds before the next one.' using errcode = 'P0001', hint = 'too_fast';
  end if;
  if v_n >= bl_cfg('roam.bubble.max_min') then
    raise exception 'You are talking too much. Take a short break.' using errcode = 'P0001', hint = 'too_fast';
  end if;
  v_mask := left(bl_chat_mask(v_body), v_len);
  if v_mask !~ '[A-Za-z0-9]' then
    raise exception 'That word is not allowed here.' using errcode = 'P0001', hint = 'filtered';
  end if;
  -- the same words again within the chat's duplicate window (like chat_send)
  if v_dup > 0 and exists (select 1 from roam_bubbles b where b.user_id = v_me.id and b.created_at > v_now - make_interval(secs => v_dup::double precision)
       and lower(regexp_replace(b.body, '\W', '', 'g')) = lower(regexp_replace(v_mask, '\W', '', 'g'))) then
    raise exception 'You just sent that. Say something new.' using errcode = 'P0001', hint = 'duplicate';
  end if;
  insert into roam_bubbles (user_id, body, x, y, created_at) values (v_me.id, v_mask, pr.x, pr.y, v_now) returning id into v_id;
  delete from roam_bubbles where id in (select d.id from roam_bubbles d where d.created_at < v_now - make_interval(hours => bl_cfg('roam.bubble.log_hours')::int) order by d.created_at limit 50);
  -- from the database: the payload is trusted because no client can write on a text topic (there is no insert policy for it)
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is not null then
    perform realtime.send(jsonb_build_object('i', v_id, 'u', v_me.id, 'n', v_me.username, 't', v_mask, 'x', round(pr.x::numeric, 0), 'y', round(pr.y::numeric, 0)),
                          'b', 'roam:t:' || v_me.id, true);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'text', v_mask, 'masked', v_mask <> v_body);
end $$;

-- Report a player (the existing chat report records a message; this one records the player and the last thing he said in the street).
create or replace function public.roam_report(p_user uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me     profiles := bl_chat_me();
  v_now    timestamptz := bl_now();
  v_bubble text;
  v_cs     numeric := greatest(20, bl_cfg('roam.live.cell_m'));
  rp       roam_presence;
  mp       roam_presence;
  bx       real; byy real;
  v_ok     boolean := false;
begin
  if p_user is null or p_user = v_me.id then
    raise exception 'You can''t report yourself.' using errcode = 'P0001', hint = 'self';
  end if;
  if not exists (select 1 from profiles where id = p_user) then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'unknown_player';
  end if;
  if exists (select 1 from roam_reports r where r.reporter_id = v_me.id and r.reported_id = p_user and r.created_at > v_now - interval '10 minutes') then
    return jsonb_build_object('ok', true, 'message', 'Thanks. A moderator will look at it.', 'dup', true);
  end if;
  -- only somebody you were near in the street in the last 10 minutes: he was in a presence row (not hidden) or spoke recently, and you were
  -- within about 3 cells of where (if you are still in the street), or your own walk started / moved within the 10 minutes
  select * into rp from roam_presence where user_id = p_user and updated_at > v_now - interval '10 minutes';
  select b.x, b.y into bx, byy from roam_bubbles b where b.user_id = p_user and b.created_at > v_now - interval '10 minutes' order by b.id desc limit 1;
  if found or (rp.user_id is not null and not rp.hidden) then
    select * into mp from roam_presence where user_id = v_me.id and updated_at > v_now - interval '10 minutes';
    if mp.user_id is not null then
      v_ok := sqrt((coalesce(rp.x, bx) - mp.x) ^ 2 + (coalesce(rp.y, byy) - mp.y) ^ 2) <= 3 * v_cs;
    else
      v_ok := exists (select 1 from roam_sessions s where s.user_id = v_me.id and s.anchor_at > v_now - interval '10 minutes');
    end if;
  end if;
  if not v_ok then
    raise exception 'You can only report players you were near in the street in the last few minutes.' using errcode = 'P0001', hint = 'not_near';
  end if;
  if (select count(*) from roam_reports r where r.reporter_id = v_me.id and r.created_at > v_now - interval '1 hour') >= bl_cfg('roam.report.max_hour') then
    raise exception 'You are reporting too fast. Try again later.' using errcode = 'P0001', hint = 'too_fast';
  end if;
  select b.body into v_bubble from roam_bubbles b
   where b.user_id = p_user and b.created_at > v_now - make_interval(hours => bl_cfg('roam.bubble.log_hours')::int)
   order by b.created_at desc limit 1;
  insert into roam_reports (reporter_id, reported_id, reason, bubble, created_at)
  values (v_me.id, p_user, left(nullif(bl_chat_clean(p_reason), ''), 200), v_bubble, v_now);
  delete from roam_reports where id in (select d.id from roam_reports d where d.created_at < v_now - interval '30 days' order by d.created_at limit 20);
  return jsonb_build_object('ok', true, 'message', 'Thanks. A moderator will look at it.');
end $$;

-- Admin: the latest player reports from free roam
create or replace function public.admin_roam_reports(p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', r.id, 'reported_id', r.reported_id, 'reported', (select username from profiles where id = r.reported_id),
             'reporter', (select username from profiles where id = r.reporter_id), 'reason', r.reason, 'bubble', r.bubble, 'created_at', r.created_at,
             'reports', (select count(*) from roam_reports x where x.reported_id = r.reported_id)) order by r.id desc)
      from (select * from roam_reports order by id desc limit least(500, greatest(1, coalesce(p_limit, 100)))) r), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Patches to the phase 1 / 2 functions (guarded single replace, unique helper name): leaving the street removes the presence row
-- ---------------------------------------------------------------------------------------------
create or replace function pg_temp.roam3_patch(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n <> 1 then raise exception 'roam3: % : marker found % times: %', p_sig, v_n, left(p_marker, 90); end if;
  execute replace(v_def, p_marker, p_new);
end $$;

select pg_temp.roam3_patch('public.roam_leave()', 'roam_presence',
$m$update roam_sessions set ended = true, mode = 'walk', vehicle = null where user_id = v_me.id;$m$,
$m$update roam_sessions set ended = true, mode = 'walk', vehicle = null where user_id = v_me.id;
  delete from roam_presence where user_id = v_me.id;$m$);
select pg_temp.roam3_patch('public.roam_hail_keke(text)', 'roam_presence',
$m$update roam_sessions set ended = true, mode = 'walk', vehicle = null where user_id = v_me.id;$m$,
$m$update roam_sessions set ended = true, mode = 'walk', vehicle = null where user_id = v_me.id;
  delete from roam_presence where user_id = v_me.id;$m$);
select pg_temp.roam3_patch('public.roam_enter(text)', 'roam_presence',
$m$update roam_sessions set place = p_place, anchor_at = v_now, enters = enters + 1, win_start = v_ws, win_n = v_n,$m$,
$m$delete from roam_presence where user_id = v_me.id;
    update roam_sessions set place = p_place, anchor_at = v_now, enters = enters + 1, win_start = v_ws, win_n = v_n,$m$);

-- ---------------------------------------------------------------------------------------------
-- 6. Realtime Authorization (policies on realtime.messages)
-- ---------------------------------------------------------------------------------------------
drop policy if exists roam_pos_read on realtime.messages;
create policy roam_pos_read on realtime.messages for select to authenticated
  using (realtime.messages.extension = 'broadcast' and realtime.topic() like 'roam:u:%' and public.roam_topic_ok(realtime.topic(), false));
drop policy if exists roam_pos_write on realtime.messages;
create policy roam_pos_write on realtime.messages for insert to authenticated
  with check (realtime.messages.extension = 'broadcast' and realtime.topic() like 'roam:u:%' and public.roam_topic_ok(realtime.topic(), true));
drop policy if exists roam_bubble_read on realtime.messages;
drop policy if exists roam_text_read on realtime.messages;
create policy roam_text_read on realtime.messages for select to authenticated
  using (realtime.messages.extension = 'broadcast' and realtime.topic() like 'roam:t:%' and public.roam_topic_ok(realtime.topic(), false));

-- ---------------------------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------------------------
revoke execute on function public.bl_roam_live_gate() from public, anon, authenticated;
revoke execute on function public.bl_roam_light_me() from public, anon, authenticated;
revoke execute on function public.bl_roam_visible(uuid) from public, anon, authenticated;
revoke execute on function public.bl_roam_presence_write(public.profiles, numeric, numeric) from public, anon, authenticated;
revoke execute on function public.bl_roam_nearby(uuid, uuid[]) from public, anon, authenticated;
revoke execute on function public.roam_topic_ok(text, boolean) from public, anon;
grant execute on function public.roam_topic_ok(text, boolean) to authenticated;
revoke execute on function public.roam_live_info() from public, anon;
revoke execute on function public.roam_set_show(boolean) from public, anon;
revoke execute on function public.roam_presence_set(numeric, numeric) from public, anon;
revoke execute on function public.roam_nearby(uuid[]) from public, anon;
revoke execute on function public.roam_live_tick(numeric, numeric, uuid[]) from public, anon;
revoke execute on function public.roam_live_stop() from public, anon;
revoke execute on function public.roam_say(text) from public, anon;
revoke execute on function public.roam_report(uuid, text) from public, anon;
revoke execute on function public.admin_roam_reports(int) from public, anon;
grant execute on function public.roam_live_info() to authenticated;
grant execute on function public.roam_set_show(boolean) to authenticated;
grant execute on function public.roam_presence_set(numeric, numeric) to authenticated;
grant execute on function public.roam_nearby(uuid[]) to authenticated;
grant execute on function public.roam_live_tick(numeric, numeric, uuid[]) to authenticated;
grant execute on function public.roam_live_stop() to authenticated;
grant execute on function public.roam_say(text) to authenticated;
grant execute on function public.roam_report(uuid, text) to authenticated;
grant execute on function public.admin_roam_reports(int) to authenticated;

notify pgrst, 'reload schema';
