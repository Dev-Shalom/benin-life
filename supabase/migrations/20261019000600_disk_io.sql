-- Disk IO fix (docs/DISK_IO.md). Supabase warned that the production project is depleting its Disk IO budget.
-- Measured on a local copy (300 players, 300k ledger rows, 120k events, 30 simulated minutes of polling), the
-- biggest sources were:
--   1. the heartbeat: get_my_state() re-saves profiles.last_seen every ~60 s per player. last_seen was in TWO
--      indexes, so every one of those UPDATEs was a non-HOT update of a wide hot row (new heap tuple + 2 index
--      entries + dead tuple + WAL + Realtime decoding). Fix: index a coarse 5-minute "seen_bucket" instead (a
--      trigger-kept column whose value only changes every 5 minutes), so ~4 of 5 heartbeats become HOT updates with
--      no index writes; the presence readers filter on the bucket first and on the exact last_seen second.
--      The write throttle goes 30 s -> 55 s so action-driven refreshes stop re-writing the row.
--   2. polled "status" RPCs that locked or rewrote rows although nothing was due (business_mine settled every
--      owned business on every poll, yahoo_group_status locked the group row every 5 s).
--   3. billboard_list (every client, every 5 min) ran two DELETEs with no index (full scans of
--      admin_notifications and billboard_counter_log); world_counts() scanned every private-home location row
--      per call. billboard_track wrote a counter log row and every seen ad row once per minute per player.
--   4. unbounded growth with no retention: events, hustle_runs, yahoo_runs, money drops, small logs.
-- Everything here is idempotent; functions are patched with a guarded replace on pg_get_functiondef (it raises
-- when a marker is missing) so grants and owners stay as they are. The ledger and payment history are never deleted.

-- ---------------------------------------------------------------------
-- 0. patch helper (session-scoped)
-- ---------------------------------------------------------------------
create or replace function pg_temp.io_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text;
begin
  v_def := pg_get_functiondef(p_sig::regprocedure);
  if position(p_done in v_def) > 0 then return; end if;          -- already patched
  if position(p_old in v_def) = 0 then
    raise exception 'disk_io: marker not found in % (expected: %)', p_sig, left(p_old, 80);
  end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------
-- 1. profiles: HOT-friendly heartbeat
-- ---------------------------------------------------------------------
-- seen_bucket = last_seen rounded down to 5 minutes (UTC epoch / 300). A plain column kept by a trigger (not a
-- generated column, so `insert into profiles select ...` / jsonb_populate_record fixtures keep working). The trigger
-- only fires when last_seen is in the SET list and assigns the same value 4 times out of 5, so the row stays HOT.
alter table public.profiles add column if not exists seen_bucket bigint;

create or replace function public.bl_profiles_seen_bucket() returns trigger
language plpgsql set search_path = public as $$
begin
  new.seen_bucket := case when new.last_seen is null then null else floor(extract(epoch from new.last_seen) / 300)::bigint end;
  return new;
end $$;
revoke all on function public.bl_profiles_seen_bucket() from public, anon, authenticated;
drop trigger if exists profiles_seen_bucket on public.profiles;
create trigger profiles_seen_bucket before insert or update of last_seen on public.profiles
  for each row execute function public.bl_profiles_seen_bucket();

-- backfill (no index on the column yet, so these updates are HOT); a re-run touches nothing
update public.profiles set seen_bucket = floor(extract(epoch from last_seen) / 300)::bigint
 where last_seen is not null and seen_bucket is distinct from floor(extract(epoch from last_seen) / 300)::bigint;

alter table public.profiles set (fillfactor = 85);   -- room on the page for HOT updates (applies to new pages)

create index if not exists profiles_location_bucket_idx on public.profiles (location_id, seen_bucket desc);
create index if not exists profiles_online_bucket_idx on public.profiles (seen_bucket desc) where home_chosen and not banned;
drop index if exists public.profiles_location_seen_idx;
drop index if exists public.profiles_online_idx;
analyze public.profiles;

-- the heartbeat only re-saves last_seen when it is older than this (it is sent every 60 s; the friends window is 120 s)
update public.game_config set value = '55'::jsonb
 where key = 'time.last_seen_throttle_real_seconds' and value in ('30'::jsonb, '"30"'::jsonb);

-- get_my_state must not leak the new column to the client
select pg_temp.io_patch('public.get_my_state()',
  $o$to_jsonb(v_me) - array['banned','needs_updated_at','last_seen',$o$,
  $o$to_jsonb(v_me) - array['banned','needs_updated_at','last_seen','seen_bucket',$o$,
  $o$'seen_bucket'$o$);

-- readers: filter on the indexed bucket first (the exact last_seen test stays)
select pg_temp.io_patch('public.world_counts()',
  $o$where home_chosen and not banned and last_seen > v_since$o$,
  $o$where home_chosen and not banned and last_seen > v_since
       and seen_bucket >= floor(extract(epoch from v_since) / 300)::bigint$o$,
  $o$seen_bucket$o$);
select pg_temp.io_patch('public.world_counts()',
  $o$and location_id not in (select l.id from locations l where l.private_home_owner_id is not null)$o$,
  $o$and not exists (select 1 from locations l where l.id = recent.location_id and l.private_home_owner_id is not null)$o$,
  $o$recent.location_id$o$);
select pg_temp.io_patch('public.players_online()',
  $o$and last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision);$o$,
  $o$and last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)
     and seen_bucket >= floor(extract(epoch from bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)) / 300)::bigint;$o$,
  $o$seen_bucket$o$);
select pg_temp.io_patch('public.players_here(text)',
  $o$and last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)$o$,
  $o$and last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)
            and seen_bucket >= floor(extract(epoch from bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)) / 300)::bigint$o$,
  $o$seen_bucket$o$);
select pg_temp.io_patch('public.players_here_ids(text)',
  $o$and last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)$o$,
  $o$and last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)
               and seen_bucket >= floor(extract(epoch from bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)) / 300)::bigint$o$,
  $o$seen_bucket$o$);

-- ---------------------------------------------------------------------
-- 2. polled settles that wrote or locked rows with nothing due
-- ---------------------------------------------------------------------
-- business_mine (phone Business app, polled): businesses accrue per hour, so settle at most every 3 minutes
select pg_temp.io_patch('public.business_mine()',
  $o$b := bl_biz_settle(r.id);$o$,
  $o$select * into b from businesses where id = r.id;
    if not found or b.settled_at <= bl_now() - interval '3 minutes' then b := bl_biz_settle(r.id); end if;$o$,
  $o$interval '3 minutes'$o$);

-- yahoo group tick (yahoo_group_status, polled every few seconds while in a group): lock only when something is due
select pg_temp.io_patch('public.bl_yahoo_group_tick(bigint)',
  $o$select * into g from yahoo_groups where id = p_group for update;
  if not found then return; end if;$o$,
  $o$select * into g from yahoo_groups where id = p_group;
  if not found then return; end if;
  if not ((g.status = 'inviting' and (g.start_at <= bl_now() or not exists (select 1 from yahoo_group_members where group_id = g.id and status = 'invited')))
          or (g.status = 'running' and g.resolve_at <= bl_now())) then
    return;   -- nothing due: no row lock (a lock is a write)
  end if;
  select * into g from yahoo_groups where id = p_group for update;
  if not found then return; end if;$o$,
  $o$nothing due: no row lock$o$);

-- ---------------------------------------------------------------------
-- 3. billboards: the sweep (run by every billboard_list) no longer scans two tables; views are counted less often
-- ---------------------------------------------------------------------
create table if not exists public.io_housekeeping (
  job text primary key,
  last_run timestamptz not null default now(),
  last_deleted bigint not null default 0
);
alter table public.io_housekeeping enable row level security;
revoke all on public.io_housekeeping from anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. retention: hourly, bounded (5,000 rows per table per run), never ledger / payments / receipts / tax / audit
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('io.logs_keep_days', '30', 'admin', 'Keep alerts and small logs (days)',
 'Disk IO: alerts (events), business log, campaign log, house interaction log, shrine notices and settled money drops older than this are deleted, a few thousand rows an hour. The ledger and payments are never deleted.', 'number', 7, 3650),
('io.runs_keep_days', '90', 'admin', 'Keep finished hustle and Yahoo runs (days)',
 'Disk IO: finished hustle_runs / yahoo_runs older than this are deleted, a few thousand rows an hour.', 'number', 30, 3650)
on conflict (key) do nothing;

create or replace function public.bl_io_housekeeping() returns integer
language plpgsql security definer set search_path = public as $$
declare
  c_batch constant int := 5000;
  v_n int;
  v_total int := 0;
  v_full boolean := false;
  v_logs interval := make_interval(days => greatest(7, coalesce(bl_cfg('io.logs_keep_days'), 30))::int);
  v_runs interval := make_interval(days => greatest(30, coalesce(bl_cfg('io.runs_keep_days'), 90))::int);
  v_hype interval := make_interval(hours => greatest(1, coalesce(bl_cfg('hype.retention_hours'), 24))::int);
begin
  -- cheap read first (no lock, no write) so the polled caller pays almost nothing
  if exists (select 1 from io_housekeeping where job = 'retention' and last_run > now() - interval '1 hour') then
    return 0;
  end if;
  v_n := null;
  insert into io_housekeeping as h (job, last_run) values ('retention', now())
    on conflict (job) do update set last_run = now() where h.last_run <= now() - interval '1 hour'
    returning 1 into v_n;
  if v_n is null then return 0; end if;   -- another request claimed this hour

  -- Every statement reads only the oldest c_batch ids (ids grow with time), then deletes the ones past retention:
  -- bounded work even when nothing is old, and no index on created_at needed.
  with c as (select id, created_at from events order by id limit c_batch),
       d as (delete from events e using c where e.id = c.id and c.created_at < now() - v_logs returning 1)
  select count(*) into v_n from d;
  v_total := v_total + v_n; v_full := v_full or v_n >= c_batch;

  with c as (select id, started_at, status from hustle_runs order by id limit c_batch),
       d as (delete from hustle_runs e using c where e.id = c.id and c.status <> 'running' and c.started_at < now() - v_runs returning 1)
  select count(*) into v_n from d;
  v_total := v_total + v_n; v_full := v_full or v_n >= c_batch;

  with c as (select id, started_at, status from yahoo_runs order by id limit c_batch),
       d as (delete from yahoo_runs e using c where e.id = c.id and c.status <> 'running' and c.started_at < now() - v_runs returning 1)
  select count(*) into v_n from d;
  v_total := v_total + v_n; v_full := v_full or v_n >= c_batch;

  with c as (select id, created_at, settled from money_drops order by id limit c_batch),   -- picks go with them (cascade)
       d as (delete from money_drops e using c where e.id = c.id and c.settled and c.created_at < now() - v_logs returning 1)
  select count(*) into v_n from d;
  v_total := v_total + v_n; v_full := v_full or v_n >= c_batch;

  with c as (select id, created_at, status from house_interactions order by id limit c_batch),
       d as (delete from house_interactions e using c where e.id = c.id and c.status <> 'pending' and c.created_at < now() - v_logs returning 1)
  select count(*) into v_n from d;
  v_total := v_total + v_n; v_full := v_full or v_n >= c_batch;

  with c as (select id, created_at from shrine_notices order by id limit c_batch),
       d as (delete from shrine_notices e using c where e.id = c.id and c.created_at < now() - v_logs returning 1)
  select count(*) into v_n from d;
  v_total := v_total + v_n; v_full := v_full or v_n >= c_batch;

  with c as (select id, created_at from pol_campaign_log order by id limit c_batch),
       d as (delete from pol_campaign_log e using c where e.id = c.id and c.created_at < now() - v_logs returning 1)
  select count(*) into v_n from d;
  v_total := v_total + v_n; v_full := v_full or v_n >= c_batch;

  with c as (select id, created_at from business_log order by id limit c_batch),
       d as (delete from business_log e using c where e.id = c.id and c.created_at < now() - v_logs returning 1)
  select count(*) into v_n from d;
  v_total := v_total + v_n; v_full := v_full or v_n >= c_batch;

  with c as (select id, created_at from place_announcements order by id limit c_batch),
       d as (delete from place_announcements e using c where e.id = c.id and c.created_at < now() - v_hype returning 1)
  select count(*) into v_n from d;
  v_total := v_total + v_n; v_full := v_full or v_n >= c_batch;

  -- moved here from bl_billboard_sweep (they used to run on every billboard_list, as two full scans)
  with c as (select id, created_at from admin_notifications order by id limit c_batch),
       d as (delete from admin_notifications e using c where e.id = c.id and c.created_at < now() - interval '45 days' returning 1)
  select count(*) into v_n from d;
  v_total := v_total + v_n; v_full := v_full or v_n >= c_batch;

  delete from billboard_counter_log
   where ctid = any (array(select ctid from billboard_counter_log where at < now() - interval '2 days' limit c_batch));
  get diagnostics v_n = row_count;
  v_total := v_total + v_n; v_full := v_full or v_n >= c_batch;

  -- a full batch means there is more to delete: come back in 5 minutes instead of an hour
  update io_housekeeping
     set last_deleted = v_total, last_run = case when v_full then now() - interval '55 minutes' else last_run end
   where job = 'retention';
  return v_total;
end $$;
revoke all on function public.bl_io_housekeeping() from public, anon, authenticated;

select pg_temp.io_patch('public.bl_billboard_sweep()',
  $o$delete from admin_notifications where created_at < now() - interval '45 days';
  delete from billboard_counter_log where at < now() - interval '2 days';$o$,
  $o$perform bl_io_housekeeping();   -- hourly retention (admin_notifications, billboard_counter_log moved there)$o$,
  $o$perform bl_io_housekeeping()$o$);

select pg_temp.io_patch('public.billboard_track(jsonb)',
  $o$least(10, (p_views->>k)::int)$o$,
  $o$least(50, (p_views->>k)::int)$o$,
  $o$least(50, (p_views->>k)::int)$o$);
select pg_temp.io_patch('public.billboard_track(jsonb)',
  $o$billboard_counter_log.at < now() - interval '50 seconds'$o$,
  $o$billboard_counter_log.at < now() - interval '240 seconds'$o$,
  $o$interval '240 seconds'$o$);

-- the push log purge was one unbounded DELETE: batch it
select pg_temp.io_patch('public.bl_push_tick()',
  $o$delete from push_outbox where created_at < now() - make_interval(days => v_keep::int);$o$,
  $o$delete from push_outbox where id in (select id from push_outbox where created_at < now() - make_interval(days => v_keep::int) order by id limit 5000);$o$,
  $o$order by id limit 5000$o$);

notify pgrst, 'reload schema';
