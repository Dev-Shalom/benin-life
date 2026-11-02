-- Daily return pack, part 1: GROWTH measurement (docs/GROWTH.md).
-- * player_days (user_id, day): one row per player per WAT day they were seen. Written lazily by get_my_state (the heartbeat),
--   guarded by player_return_state.last_day so a player writes AT MOST once a day (a primary-key read per heartbeat, no write).
-- * player_sources: how a player heard about the game (self-reported answer) and the channel link they came from (?src=tiktok).
-- * app_day_counts: how many players opened each phone app each day (one write per player per app per day, deduped by
--   player_app_days which is trimmed to 14 days).
-- * admin_growth_overview(): everything the Admin -> Growth page shows, cached for growth.cache_seconds (like world_counts).
-- Idempotent. Nothing here touches the profiles table (no column, trigger, index or foreign key); one cheap backfill (a single
-- insert .. select over profiles, no loop) seeds each player's last-seen day so the charts do not start empty.

create or replace function pg_temp.dr1_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'growth: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Tables (RLS on, no policies: players never read or write them directly)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.player_days (
  user_id uuid not null,
  day date not null,
  primary key (user_id, day)
);
create index if not exists player_days_day_idx on public.player_days (day);

-- per-player memory of the last recorded day (also used by the welcome-back gift in part 2)
create table if not exists public.player_return_state (
  user_id uuid primary key,
  last_day date not null,
  prev_day date,
  updated_at timestamptz not null default now()
);

create table if not exists public.player_sources (
  user_id uuid primary key,
  heard text check (heard is null or heard in ('tiktok', 'whatsapp', 'friend', 'campus', 'instagram', 'x', 'google', 'other')),
  channel text check (channel is null or channel ~ '^[a-z0-9_]{2,24}$'),
  created_at timestamptz not null default now()
);

create table if not exists public.player_app_days (
  user_id uuid not null,
  day date not null,
  app text not null,
  primary key (user_id, day, app)
);
create index if not exists player_app_days_day_idx on public.player_app_days (day);

create table if not exists public.app_day_counts (
  day date not null,
  app text not null,
  players integer not null default 0,
  primary key (day, app)
);

create table if not exists public.growth_cache (
  id smallint primary key default 1 check (id = 1),
  computed_at timestamptz not null default '-infinity',
  for_day date,
  data jsonb
);
insert into public.growth_cache (id) values (1) on conflict (id) do nothing;

do $$
declare t text;
begin
  foreach t in array array['player_days', 'player_return_state', 'player_sources', 'player_app_days', 'app_day_counts', 'growth_cache'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('growth.cache_seconds', '300', 'growth', 'Growth page cache (seconds)',
 'Admin -> Growth works its numbers out once every this many seconds and shows the saved copy in between. 0 = every time (slow with many players).', 'number', 0, 3600),
('growth.sources_days', '60', 'growth', 'Source breakdown window (days)',
 'Admin -> Growth: sign-ups from this many days back are counted in "Where players came from" (a longer window gives a fairer day-7 number).', 'number', 14, 180)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. The heartbeat hook: at most one insert per player per WAT day
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_growth_touch(p_uid uuid, p_now timestamptz, p_prev_seen timestamptz) returns void
language plpgsql security definer set search_path = public as $$
declare v_day date := bl_wat_date(p_now); v_last date;
begin
  select last_day into v_last from player_return_state where user_id = p_uid;
  if v_last = v_day then return; end if;                 -- already recorded today: no write at all
  if v_last is null and p_prev_seen is not null then v_last := bl_wat_date(p_prev_seen); end if;
  insert into player_days (user_id, day) values (p_uid, v_day) on conflict do nothing;
  insert into player_return_state (user_id, last_day, prev_day) values (p_uid, v_day, v_last)
  on conflict (user_id) do update set last_day = excluded.last_day, prev_day = excluded.prev_day, updated_at = now();
exception when others then
  null;   -- a measuring problem must never break the heartbeat
end $$;
revoke all on function public.bl_growth_touch(uuid, timestamptz, timestamptz) from public, anon, authenticated;

select pg_temp.dr1_patch('public.get_my_state()',
  E'    update profiles set last_seen = v_now where id = v_uid returning * into v_me;',
  E'    perform bl_growth_touch(v_uid, v_now, v_me.last_seen);\n    update profiles set last_seen = v_now where id = v_uid returning * into v_me;',
  'bl_growth_touch(');

-- one cheap seed: each player's last-seen day (one statement, no loop)
insert into public.player_days (user_id, day)
select id, bl_wat_date(last_seen) from public.profiles where last_seen is not null
on conflict do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Player RPCs
-- ---------------------------------------------------------------------------------------------
-- Save where the player came from. First answer wins for each field. heard: the one-tap question; channel: ?src=... link.
create or replace function public.growth_source_set(p_heard text default null, p_channel text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_heard text := nullif(lower(btrim(coalesce(p_heard, ''))), ''); v_chan text := nullif(lower(btrim(coalesce(p_channel, ''))), ''); r player_sources;
begin
  if not exists (select 1 from profiles where id = v_uid) then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v_heard is not null and v_heard not in ('tiktok', 'whatsapp', 'friend', 'campus', 'instagram', 'x', 'google', 'other') then v_heard := null; end if;
  if v_chan is not null and v_chan !~ '^[a-z0-9_]{2,24}$' then v_chan := null; end if;
  if v_heard is not null or v_chan is not null then
    insert into player_sources (user_id, heard, channel) values (v_uid, v_heard, v_chan)
    on conflict (user_id) do update
       set heard = coalesce(player_sources.heard, excluded.heard), channel = coalesce(player_sources.channel, excluded.channel);
  end if;
  select * into r from player_sources where user_id = v_uid;
  return jsonb_build_object('heard', r.heard, 'channel', r.channel);
end $$;

-- Count one phone-app open: at most once per player per app per day, at most 30 apps a day.
create or replace function public.growth_app_open(p_app text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_app text := lower(btrim(coalesce(p_app, ''))); v_day date := bl_wat_date(); v_n int;
begin
  if v_app !~ '^[a-z0-9_-]{1,30}$' then return false; end if;
  if (select count(*) from player_app_days where user_id = v_uid and day = v_day) >= 30 then return false; end if;
  insert into player_app_days (user_id, day, app) values (v_uid, v_day, v_app) on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then return false; end if;
  insert into app_day_counts (day, app, players) values (v_day, v_app, 1)
  on conflict (day, app) do update set players = app_day_counts.players + 1;
  return true;
exception when others then
  return false;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Admin: the Growth page numbers (cached)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_growth_compute() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_today date := bl_wat_date(); v_tz text := bl_clock_tz();
  v_start timestamptz := ((bl_wat_date() - 29)::timestamp at time zone bl_clock_tz());
  v_sdays int := greatest(14, coalesce(bl_cfg('growth.sources_days'), 60))::int;
  v_sstart timestamptz;
  v_dau jsonb; v_sign jsonb; v_coh jsonb; v_src jsonb; v_apps jsonb; v_tot jsonb;
begin
  v_sstart := ((v_today - v_sdays)::timestamp at time zone v_tz);
  select jsonb_agg(jsonb_build_object('day', g.d, 'n', coalesce(x.n, 0)) order by g.d) into v_dau
    from (select v_today - 29 + i as d from generate_series(0, 29) i) g
    left join (select day, count(*) n from player_days where day >= v_today - 29 group by day) x on x.day = g.d;

  select jsonb_agg(jsonb_build_object('day', g.d, 'n', coalesce(x.n, 0)) order by g.d) into v_sign
    from (select v_today - 29 + i as d from generate_series(0, 29) i) g
    left join (select (created_at at time zone v_tz)::date d, count(*) n from profiles where created_at >= v_start group by 1) x on x.d = g.d;

  select coalesce(jsonb_agg(jsonb_build_object('day', d, 'size', size,
           'd1', case when d + 1 < v_today then r1 end, 'd7', case when d + 7 < v_today then r7 end) order by d), '[]'::jsonb) into v_coh
    from (select c.d, count(*) size,
                 count(*) filter (where exists (select 1 from player_days pd where pd.user_id = c.id and pd.day = c.d + 1)) r1,
                 count(*) filter (where exists (select 1 from player_days pd where pd.user_id = c.id and pd.day = c.d + 7)) r7
            from (select id, (created_at at time zone v_tz)::date d from profiles where created_at >= v_start) c
           group by c.d) z;

  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'n', n, 'e1', e1, 'r1', r1, 'e7', e7, 'r7', r7) order by n desc, src), '[]'::jsonb) into v_src
    from (select m.src, count(*) n,
                 count(*) filter (where m.d + 1 < v_today) e1,
                 count(*) filter (where m.d + 1 < v_today and exists (select 1 from player_days pd where pd.user_id = m.id and pd.day = m.d + 1)) r1,
                 count(*) filter (where m.d + 7 < v_today) e7,
                 count(*) filter (where m.d + 7 < v_today and exists (select 1 from player_days pd where pd.user_id = m.id and pd.day = m.d + 7)) r7
            from (select p.id, (p.created_at at time zone v_tz)::date d,
                         coalesce(s.channel, s.heard, case when exists (select 1 from referrals rf where rf.referred_id = p.id) then 'friend' end, 'unknown') src
                    from profiles p left join player_sources s on s.user_id = p.id
                   where p.created_at >= v_sstart) m
           group by m.src) q;

  select coalesce(jsonb_agg(jsonb_build_object('app', app, 'today', today, 'week', week) order by week desc, app), '[]'::jsonb) into v_apps
    from (select app, coalesce(sum(players) filter (where day = v_today), 0) today, sum(players) week
            from app_day_counts where day > v_today - 7 group by app order by sum(players) desc, app limit 15) a;

  v_tot := jsonb_build_object(
    'players', (select count(*) from profiles),
    'today', (select count(*) from player_days where day = v_today),
    'yesterday', (select count(*) from player_days where day = v_today - 1),
    'wau', (select count(distinct user_id) from player_days where day > v_today - 7),
    'wau_prev', (select count(distinct user_id) from player_days where day <= v_today - 7 and day > v_today - 14),
    'mau', (select count(distinct user_id) from player_days where day > v_today - 30));

  return jsonb_build_object('day', v_today, 'totals', v_tot, 'dau', v_dau, 'signups', v_sign, 'cohorts', v_coh,
                            'sources', v_src, 'apps', v_apps, 'sources_days', v_sdays);
end $$;
revoke all on function public.bl_growth_compute() from public, anon, authenticated;

create or replace function public.admin_growth_overview(p_refresh boolean default false) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  v_ttl double precision := coalesce(bl_cfg('growth.cache_seconds'), 300);
  v_today date := bl_wat_date();
  c growth_cache; v_since timestamptz; v_online bigint;
begin
  select * into c from growth_cache where id = 1;
  if p_refresh or c.data is null or c.for_day is distinct from v_today or c.computed_at < now() - make_interval(secs => v_ttl) then
    if pg_try_advisory_xact_lock(hashtext('growth_cache')) or c.data is null then
      c.data := bl_growth_compute(); c.computed_at := now(); c.for_day := v_today;
      update growth_cache set data = c.data, computed_at = c.computed_at, for_day = c.for_day where id = 1;
      -- the app-open dedupe rows are only needed for today: keep 14 days
      delete from player_app_days where ctid in (select ctid from player_app_days where day < v_today - 14 limit 5000);
    end if;
  end if;
  v_since := bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision);
  select count(*) into v_online from profiles
   where home_chosen and not banned and last_seen > v_since
     and seen_bucket >= floor(extract(epoch from v_since) / 300)::bigint;
  return c.data || jsonb_build_object('online', v_online, 'computed_at', c.computed_at, 'cache_seconds', v_ttl);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------------------------
revoke all on function public.growth_source_set(text, text) from public, anon;
grant execute on function public.growth_source_set(text, text) to authenticated;
revoke all on function public.growth_app_open(text) from public, anon;
grant execute on function public.growth_app_open(text) to authenticated;
revoke all on function public.admin_growth_overview(boolean) from public, anon;
grant execute on function public.admin_growth_overview(boolean) to authenticated;

notify pgrst, 'reload schema';
