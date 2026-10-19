-- Scale with many players online (see docs/DISK_IO.md, "Many players online").
-- 1. profiles leaves the Realtime publication. Every heartbeat and every money change was decoded from the WAL and
--    checked by Realtime for all subscribers. The app now refreshes your state from your own events (anything another
--    player does to you inserts one) and the 60 s heartbeat, so nothing listens to profiles any more.
-- 2. world_counts is computed once per world.counts_cache_seconds for everybody instead of once per player per poll.
-- Idempotent.

do $$
begin
  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'profiles') then
    alter publication supabase_realtime drop table public.profiles;
  end if;
end $$;

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('world.counts_cache_seconds', '20', 'admin', 'Online counts cache (seconds)',
 'Speed: the online count and the per-place counts on the map are worked out once every this many seconds and shared by all players. 0 = work them out on every request (slow with many players online).', 'number', 0, 300)
on conflict (key) do nothing;

create table if not exists public.world_counts_cache (
  id smallint primary key default 1 check (id = 1),
  computed_at timestamptz not null default '-infinity',
  online bigint not null default 0,
  at_counts jsonb not null default '{}'::jsonb
);
alter table public.world_counts_cache enable row level security;   -- no policies: only the definer function reads it
revoke all on public.world_counts_cache from anon, authenticated;
insert into public.world_counts_cache (id) values (1) on conflict (id) do nothing;

-- Counts include everybody; the caller's own place is reduced by one here (it used to be left out in the query).
create or replace function public.world_counts() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_ttl double precision := coalesce(bl_cfg('world.counts_cache_seconds'), 20);
  v_since timestamptz := bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision);
  c world_counts_cache;
  v_loc text;
  v_n bigint;
  v_at jsonb;
begin
  select * into c from world_counts_cache where id = 1;
  -- stale: one caller recomputes, the rest get the previous numbers instead of all scanning at once
  if c.computed_at is null or c.computed_at < now() - make_interval(secs => v_ttl) then
    if v_ttl <= 0 or pg_try_advisory_xact_lock(hashtext('world_counts_cache')) then
      with recent as (
        select location_id, travel_to from profiles
         where home_chosen and not banned and last_seen > v_since
           and seen_bucket >= floor(extract(epoch from v_since) / 300)::bigint
      )
      select (select count(*) from recent),
             coalesce((select jsonb_object_agg(location_id, n)
                         from (select location_id, count(*) as n from recent
                                where travel_to is null
                                  and not exists (select 1 from locations l where l.id = recent.location_id and l.private_home_owner_id is not null)
                                group by location_id) x), '{}'::jsonb)
        into c.online, c.at_counts;
      c.computed_at := now();
      if v_ttl > 0 then
        update world_counts_cache set computed_at = c.computed_at, online = c.online, at_counts = c.at_counts where id = 1;
      end if;
    end if;
  end if;

  v_at := coalesce(c.at_counts, '{}'::jsonb);
  select location_id into v_loc from profiles
   where id = v_uid and travel_to is null and last_seen > v_since;
  if v_loc is not null and v_at ? v_loc then
    v_n := (v_at ->> v_loc)::bigint - 1;
    v_at := case when v_n > 0 then jsonb_set(v_at, array[v_loc], to_jsonb(v_n)) else v_at - v_loc end;
  end if;
  return jsonb_build_object('online', coalesce(c.online, 0), 'at', v_at,
                            'minutes', bl_cfg('time.presence_real_minutes'), 'server_time', bl_now());
end $$;
revoke all on function public.world_counts() from public, anon;
grant execute on function public.world_counts() to authenticated;

notify pgrst, 'reload schema';
