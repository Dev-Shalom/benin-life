-- F1 Realtime fallback (docs/SCALING.md "Realtime fallback").
-- When the Supabase plan's Realtime limits are hit (connections / messages per second) a tab switches to polling
-- (src/lib/realtime.ts). Most features poll tables they already read. Two things are new here:
--   1. game_config realtime.mode = auto | poll_only: the owner can force every tab to polling (Admin → Settings).
--   2. House rooms: avatar movement inside a shared home normally travels only over Realtime broadcast/presence.
--      In poll mode each member posts its position with house_room_move() and reads the others with
--      house_room_state() every ~4 s. Tabs still on Realtime receive those rows as Postgres Changes on the same
--      house channel (RLS: members of that house only) and then post their own moves too ("bridge"), so players in
--      different modes still see each other.
-- Idempotent.

-- ---------------------------------------------------------------------------------------------
-- 1. owner switch
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('realtime.mode', '"auto"', 'admin', 'Live updates (Realtime)',
 'F1: auto = live updates over Supabase Realtime, and a tab falls back to polling by itself when the plan''s Realtime limit is full. poll_only = every player polls (slower chat/movement, fewer moving parts): use it during a spike when Realtime is over its limit. Type auto or poll_only.',
 'text', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. house room positions (poll mode)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.house_room_positions (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  location_id text not null references public.locations(id) on delete cascade,
  username    text not null default '',
  avatar      jsonb,
  x           real not null default 0,
  z           real not null default 0,
  yaw         real not null default 0,
  moving      boolean not null default false,
  activity    text,
  path        jsonb,          -- {"p":[x0,z0,x1,z1,...],"f":faceTo|null,"at":sender ms} of the last walk
  via         text not null default 'poll' check (via in ('poll', 'bridge')),
  left_at     timestamptz,    -- set when the member leaves the house (trigger below): live tabs drop them
  updated_at  timestamptz not null default now()
);
create index if not exists house_room_positions_loc_idx on public.house_room_positions (location_id);
alter table public.house_room_positions enable row level security;
revoke all on table public.house_room_positions from anon, authenticated;
grant select on table public.house_room_positions to authenticated;

-- Is the caller inside this private home right now (owner at home, or an admitted guest)? Same rule as the
-- Realtime house room (bl_social_active_house_topic), with the location as a parameter. An RLS policy helper
-- (bl_social_can_* naming: players may execute it; it only answers about the caller).
create or replace function public.bl_social_can_view_house_room(p_location text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.locations l
      join public.profiles me on me.id = auth.uid()
     where l.id = p_location and l.private_home_owner_id is not null
       and me.location_id = l.id and me.travel_to is null and not me.banned
       and (me.id = l.private_home_owner_id or me.home_visit_host_id = l.private_home_owner_id)
  )
$$;
revoke all on function public.bl_social_can_view_house_room(text) from public, anon;
grant execute on function public.bl_social_can_view_house_room(text) to authenticated;

-- Read: only the rows of the house you are in (Postgres Changes for live tabs use this too).
drop policy if exists house_room_positions_member_read on public.house_room_positions;
create policy house_room_positions_member_read on public.house_room_positions for select to authenticated
  using (public.bl_social_can_view_house_room(location_id));
drop function if exists public.bl_house_room_member(text); -- early local name of the helper above

-- Live tabs get poll-mode members' moves as Postgres Changes.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'house_room_positions') then
    alter publication supabase_realtime add table public.house_room_positions;
  end if;
end $$;

-- Leaving the house (travel, another place, visit ended) marks the row left at once.
create or replace function public.bl_house_room_on_leave() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.house_room_positions set left_at = now(), moving = false, updated_at = now()
   where user_id = new.id and left_at is null;
  return new;
end $$;
revoke all on function public.bl_house_room_on_leave() from public, anon, authenticated;
drop trigger if exists profiles_house_room_leave on public.profiles;
create trigger profiles_house_room_leave
  after update of location_id, travel_to, home_visit_host_id on public.profiles
  for each row
  when (old.location_id is distinct from new.location_id
        or (new.travel_to is not null and old.travel_to is null)
        or old.home_visit_host_id is distinct from new.home_visit_host_id)
  execute function public.bl_house_room_on_leave();

-- Post my position in the house I am in. Small payload, called on walk start / stop / pose change and a
-- keep-alive every ~60 s while polling. p_avatar only when it changed (the outfit shown at home).
create or replace function public.house_room_move(
  p_x real, p_z real, p_yaw real, p_moving boolean default false, p_activity text default null,
  p_path jsonb default null, p_avatar jsonb default null, p_via text default 'poll'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_me  public.profiles;
  v_path jsonb := p_path;
begin
  select * into v_me from public.profiles where id = v_uid;
  if not found or not public.bl_social_can_view_house_room(v_me.location_id) then
    raise exception 'You are not inside a home.' using errcode = 'P0001', hint = 'not_in_house';
  end if;
  if p_x is null or p_z is null or abs(p_x) > 100 or abs(p_z) > 100 then
    raise exception 'Bad position.' using errcode = 'P0001', hint = 'bad_position';
  end if;
  if v_path is not null and (jsonb_typeof(v_path) <> 'object' or jsonb_typeof(v_path -> 'p') <> 'array'
                             or jsonb_array_length(v_path -> 'p') > 96 or length(v_path::text) > 2000) then
    v_path := null;
  end if;
  if p_avatar is not null and length(p_avatar::text) > 6000 then
    raise exception 'Avatar too large.' using errcode = 'P0001', hint = 'too_large';
  end if;
  insert into public.house_room_positions as h (user_id, location_id, username, avatar, x, z, yaw, moving, activity, path, via, left_at, updated_at)
  values (v_uid, v_me.location_id, v_me.username, coalesce(p_avatar, v_me.avatar), p_x, p_z, coalesce(p_yaw, 0),
          coalesce(p_moving, false), left(p_activity, 80), v_path,
          case when p_via = 'bridge' then 'bridge' else 'poll' end, null, now())
  on conflict (user_id) do update
    set location_id = excluded.location_id, username = excluded.username,
        avatar = case when p_avatar is not null or h.location_id <> excluded.location_id then excluded.avatar else h.avatar end,
        x = excluded.x, z = excluded.z, yaw = excluded.yaw, moving = excluded.moving, activity = excluded.activity,
        path = coalesce(excluded.path, case when h.location_id = excluded.location_id and h.left_at is null then h.path end),
        via = excluded.via, left_at = null, updated_at = now();
  -- housekeeping: very old rows go (cheap, ~1 % of calls)
  if random() < 0.01 then
    delete from public.house_room_positions where updated_at < now() - interval '1 day';
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.house_room_move(real, real, real, boolean, text, jsonb, jsonb, text) from public, anon;
grant execute on function public.house_room_move(real, real, real, boolean, text, jsonb, jsonb, text) to authenticated;

-- The other members of the house I am in, with their last posted position. Only members still inside
-- (same rule) and seen recently (tab open). p_with_avatars = false keeps the payload tiny (~120 bytes a member);
-- the client asks for avatars only when someone new shows up.
create or replace function public.house_room_state(p_with_avatars boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_loc text;
  v_owner uuid;
  v_win interval := make_interval(secs => (coalesce(bl_cfg('time.presence_real_minutes'), 3) * 60)::double precision);
begin
  select me.location_id into v_loc from public.profiles me where me.id = v_uid;
  if v_loc is null or not public.bl_social_can_view_house_room(v_loc) then
    raise exception 'You are not inside a home.' using errcode = 'P0001', hint = 'not_in_house';
  end if;
  select private_home_owner_id into v_owner from public.locations where id = v_loc;
  return jsonb_build_object('location', v_loc, 'members', coalesce((
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'id', h.user_id, 'x', round(h.x::numeric, 2), 'z', round(h.z::numeric, 2), 'yaw', round(h.yaw::numeric, 3),
             'moving', h.moving, 'activity', h.activity, 'path', h.path,
             'at', (extract(epoch from h.updated_at) * 1000)::bigint,
             'username', case when p_with_avatars then h.username end,
             'avatar', case when p_with_avatars then h.avatar end)) order by h.user_id)
      from public.house_room_positions h
      join public.profiles p on p.id = h.user_id
     where h.location_id = v_loc and h.user_id <> v_uid and h.left_at is null
       and p.location_id = v_loc and p.travel_to is null and not p.banned
       and (p.id = v_owner or p.home_visit_host_id = v_owner)
       and (p.last_seen > bl_now() - v_win or h.updated_at > now() - v_win)
  ), '[]'::jsonb));
end $$;
revoke all on function public.house_room_state(boolean) from public, anon;
grant execute on function public.house_room_state(boolean) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- 3. players_here_ids: the poll-mode "who is at my place" (ids + last_seen only, ~60 bytes a player instead of
--    a full avatar each). Same rules as players_here (private homes: host / invited only). The people list still
--    loads names + avatars with players_here, but only when this set changes.
-- ---------------------------------------------------------------------------------------------
create or replace function public.players_here_ids(p_location text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_home_owner uuid;
begin
  select private_home_owner_id into v_home_owner from public.locations where id = p_location;
  if v_home_owner is not null and not public.bl_social_can_view_private_home(p_location, v_home_owner) then
    raise exception 'That home is private. Ask the host to invite you.' using errcode = 'P0001', hint = 'private_home';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'last_seen', p.last_seen) order by p.last_seen desc)
      from (select id, last_seen from public.profiles
             where location_id = p_location and id <> v_uid and not banned and travel_to is null and home_chosen
               and last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)
             order by last_seen desc limit 50) p
  ), '[]'::jsonb);
end $$;
revoke all on function public.players_here_ids(text) from public, anon;
grant execute on function public.players_here_ids(text) to authenticated;

notify pgrst, 'reload schema';
