-- S1 launch hardening (docs/SCALING.md) + admin account deletion (docs/ADMIN.md "Delete a player").
--  1. Scaling: world_counts() replaces the global Realtime Presence channel for the online pill + map crowds;
--     partial index for "online now"; ledger(created_at) for admin stats; indexes on every FK column that
--     points at a user (cascade deletes and per-user lookups no longer scan); duplicate indexes dropped;
--     leaderboards rank the players ONCE per call (bl_cfg_bool was evaluated per row, 3 rankings per call).
--  2. Account deletion: every user-owned row goes when auth.users is deleted (FK cascades added where missing),
--     a BEFORE DELETE trigger on profiles sends visitors out of the player's private home first, and the
--     edge function admin-delete-user uses admin_delete_user_start() (admin check + audit snapshot) and
--     bl_user_storage_paths() (storage objects to remove) before auth.admin.deleteUser.
-- Idempotent.

-- ---------------------------------------------------------------------------------------------
-- 1a. Indexes
-- ---------------------------------------------------------------------------------------------
create index if not exists profiles_online_idx on public.profiles (last_seen desc) where home_chosen and not banned;
create index if not exists ledger_created_idx on public.ledger (created_at);
create index if not exists admin_audit_admin_idx on public.admin_audit (admin_id);
create index if not exists billboard_reports_user_idx on public.billboard_reports (user_id);
create index if not exists chat_blocks_blocked_idx on public.chat_blocks (blocked_id);
create index if not exists chat_reports_reporter_idx on public.chat_reports (reporter_id);
create index if not exists config_audit_admin_idx on public.config_audit (admin_id);
create index if not exists event_tickets_user_idx on public.event_tickets (user_id);
create index if not exists house_interactions_host_idx on public.house_interactions (host_id);
create index if not exists player_friendships_user_b_idx on public.player_friendships (user_b);
create index if not exists player_messages_sender_idx on public.player_messages (sender_id);
create index if not exists profiles_visit_host_idx on public.profiles (home_visit_host_id) where home_visit_host_id is not null;
create index if not exists social_streak_days_user_b_idx on public.social_streak_days (user_b);
-- exact duplicates of chat_messages_loc_idx / player_messages_conversation_idx (every insert paid twice)
drop index if exists public.chat_messages_loc_id_idx;
drop index if exists public.player_messages_conv_id_idx;

-- ---------------------------------------------------------------------------------------------
-- 1b. world_counts(): players online + other players per place, one cheap query (polled ~1/min/visible tab)
-- ---------------------------------------------------------------------------------------------
create or replace function public.world_counts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_since timestamptz := bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision);
  v_online bigint;
  v_at jsonb;
begin
  with recent as (
    select id, location_id, travel_to from profiles
     where home_chosen and not banned and last_seen > v_since
  )
  select (select count(*) from recent),
         coalesce((select jsonb_object_agg(location_id, n)
                     from (select location_id, count(*) as n from recent
                            where travel_to is null and id <> v_uid
                              and location_id not in (select l.id from locations l where l.private_home_owner_id is not null)
                            group by location_id) c), '{}'::jsonb)
    into v_online, v_at;
  return jsonb_build_object('online', v_online, 'at', v_at,
                            'minutes', bl_cfg('time.presence_real_minutes'), 'server_time', bl_now());
end $$;
revoke all on function public.world_counts() from public, anon;
grant execute on function public.world_counts() to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 1c. Leaderboards: the hide_admins flag once per query, and one ranking per call (was 3)
-- ---------------------------------------------------------------------------------------------
-- plpgsql so the flag is read ONCE (as a SQL function the planner pulled it into the per-row filter: 180 ms at 20k players)
create or replace function public.bl_rich_ranked()
returns table(id uuid, username text, avatar jsonb, origin text, total bigint, rank bigint)
language plpgsql stable security definer set search_path = public as $$
declare v_hide boolean := coalesce(bl_cfg_bool('leaderboard.hide_admins'), true);
begin
  return query
  select p.id, p.username, p.avatar, p.origin, (p.cash + p.bank)::bigint,
         row_number() over (order by p.cash + p.bank desc, p.created_at, p.id)
    from profiles p
   where not p.banned and (not v_hide or not p.is_admin);
end $$;

create or replace function public.bl_vip_ranked()
returns table(id uuid, username text, avatar jsonb, origin text, kobo bigint, rank bigint)
language plpgsql stable security definer set search_path = public as $$
declare v_hide boolean := coalesce(bl_cfg_bool('leaderboard.hide_admins'), true);
begin
  return query
  with s as (
    select y.user_id, sum(y.amount_kobo)::bigint as kobo, max(y.paid_at) as last_paid
      from payments y where y.status = 'success' and y.user_id is not null group by y.user_id
  )
  select p.id, p.username, p.avatar, p.origin, s.kobo,
         row_number() over (order by s.kobo desc, s.last_paid, p.id)
    from s join profiles p on p.id = s.user_id
   where not p.banned and (not v_hide or not p.is_admin);
end $$;
revoke all on function public.bl_rich_ranked() from public, anon, authenticated;
revoke all on function public.bl_vip_ranked() from public, anon, authenticated;

create or replace function public.leaderboard_rich(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_lim  int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_rows jsonb;
  v_me   jsonb;
  v_n    bigint;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  with r as materialized (select * from bl_rich_ranked())
  select (select count(*) from r),
         (select coalesce(jsonb_agg(jsonb_build_object('rank', r.rank, 'id', r.id, 'username', r.username, 'avatar', r.avatar,
                                                       'origin', r.origin, 'total', r.total,
                                                       'tier', bl_lb_tier('leaderboard.rich_tiers', r.total), 'me', r.id = v_uid)
                                    order by r.rank), '[]'::jsonb)
            from r where r.rank <= v_lim),
         (select jsonb_build_object('rank', r.rank, 'id', p.id, 'username', p.username, 'avatar', p.avatar, 'origin', p.origin,
                                    'total', p.cash + p.bank, 'tier', bl_lb_tier('leaderboard.rich_tiers', p.cash + p.bank))
            from profiles p left join r on r.id = p.id where p.id = v_uid)
    into v_n, v_rows, v_me;
  return jsonb_build_object('rows', v_rows, 'me', v_me, 'players', v_n,
                            'tiers', bl_lb_tiers('leaderboard.rich_tiers'));
end $$;

create or replace function public.leaderboard_vip(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_lim  int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_show boolean := coalesce(bl_cfg_bool('leaderboard.vip_show_amounts'), false);
  v_rows jsonb;
  v_me   jsonb;
  v_n    bigint;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  with r as materialized (select * from bl_vip_ranked())
  select (select count(*) from r),
         (select coalesce(jsonb_agg(jsonb_build_object('rank', r.rank, 'id', r.id, 'username', r.username, 'avatar', r.avatar,
                                                       'origin', r.origin, 'tier', bl_lb_tier('leaderboard.vip_tiers', r.kobo / 100.0),
                                                       'amount', case when v_show then r.kobo / 100 end, 'me', r.id = v_uid)
                                    order by r.rank), '[]'::jsonb)
            from r where r.rank <= v_lim),
         -- your own row: your amount is always shown to you
         (select jsonb_build_object('rank', r.rank, 'id', p.id, 'username', p.username, 'avatar', p.avatar, 'origin', p.origin,
                                    'tier', case when r.id is not null then bl_lb_tier('leaderboard.vip_tiers', r.kobo / 100.0) end,
                                    'amount', coalesce(r.kobo, 0) / 100)
            from profiles p left join r on r.id = p.id where p.id = v_uid)
    into v_n, v_rows, v_me;
  return jsonb_build_object('rows', v_rows, 'me', v_me, 'players', v_n, 'show_amounts', v_show,
                            'tiers', bl_lb_tiers('leaderboard.vip_tiers'));
end $$;
revoke all on function public.leaderboard_rich(int) from public, anon;
revoke all on function public.leaderboard_vip(int) from public, anon;
grant execute on function public.leaderboard_rich(int) to authenticated, service_role;
grant execute on function public.leaderboard_vip(int) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 2a. Every user-owned row goes with the account
-- ---------------------------------------------------------------------------------------------
-- client_errors.user_id had no FK: orphans -> null, then cascade
update public.client_errors e set user_id = null
 where user_id is not null and not exists (select 1 from auth.users u where u.id = e.user_id);
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'client_errors_user_fkey') then
    alter table public.client_errors add constraint client_errors_user_fkey
      foreign key (user_id) references auth.users(id) on delete cascade;
  end if;
end $$;

-- billboard ads belong to the player (their images are removed by admin-delete-user); was SET NULL
do $$
declare c text;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.billboard_ads'::regclass and contype = 'f'
              and confrelid = 'auth.users'::regclass and conkey = array[(select attnum from pg_attribute
                where attrelid = 'public.billboard_ads'::regclass and attname = 'user_id')]::smallint[]
              and confdeltype <> 'c' loop
    execute format('alter table public.billboard_ads drop constraint %I', c);
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'billboard_ads_user_cascade_fkey') then
    alter table public.billboard_ads add constraint billboard_ads_user_cascade_fkey
      foreign key (user_id) references auth.users(id) on delete cascade;
  end if;
end $$;

-- billboard_counter_log.ad_id stays without an FK: billboard_track uses a zero-uuid sentinel row per player as its
-- rate-limit clock. The player's own counter rows go by the user_id cascade.
alter table public.billboard_counter_log drop constraint if exists billboard_counter_log_ad_fkey;

-- Before a profile goes: other players inside / heading to its private home are sent to their own home,
-- and rows that point at that home without a cascade are moved, so the cascade never fails.
create or replace function public.bl_profile_before_delete() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_homes text[];
begin
  select coalesce(array_agg(id), '{}') into v_homes from locations where private_home_owner_id = old.id;
  -- a guest's home_location_id points at the host's home during a visit (the real one is kept in
  -- home_visit_original_home_location_id): restore it, then put the guest there
  update profiles p
     set home_location_id = r.home,
         location_id = case when p.location_id = any(v_homes) or p.home_visit_host_id = old.id then r.home else p.location_id end,
         home_visit_host_id = case when p.home_visit_host_id = old.id then null else p.home_visit_host_id end,
         home_visit_original_home_location_id = case when p.home_visit_host_id = old.id then null
                                                     else p.home_visit_original_home_location_id end,
         travel_to = case when p.travel_to = any(v_homes) then null else p.travel_to end,
         travel_mode = case when p.travel_to = any(v_homes) then null else p.travel_mode end,
         travel_started_at = case when p.travel_to = any(v_homes) then null else p.travel_started_at end,
         travel_arrives_at = case when p.travel_to = any(v_homes) then null else p.travel_arrives_at end
    from (select q.id, coalesce(case when q.home_location_id = any(v_homes) then null else q.home_location_id end,
                                q.home_visit_original_home_location_id,
                                (select s.location_id from start_homes s where s.id = q.start_home)) as home
            from profiles q
           where q.id <> old.id
             and (q.home_visit_host_id = old.id or q.location_id = any(v_homes) or q.travel_to = any(v_homes)
                  or q.home_location_id = any(v_homes))) r
   where p.id = r.id and r.home is not null;
  if cardinality(v_homes) > 0 then
    update police_cases c set location_id = coalesce((select home_location_id from profiles where id = c.user_id), c.location_id)
     where c.location_id = any(v_homes) and c.user_id <> old.id;
    delete from player_house_invites where home_location_id = any(v_homes);
  end if;
  return old;
end $$;
revoke all on function public.bl_profile_before_delete() from public, anon, authenticated;
drop trigger if exists profiles_before_delete on public.profiles;
create trigger profiles_before_delete before delete on public.profiles
  for each row execute function public.bl_profile_before_delete();

-- ---------------------------------------------------------------------------------------------
-- 2b. Admin delete: start (admin JWT) + storage paths (service role)
-- ---------------------------------------------------------------------------------------------
-- Called by the edge function with the ADMIN's JWT. Checks, then writes the audit row BEFORE the delete.
create or replace function public.admin_delete_user_start(p_user uuid, p_confirm text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  v_admin uuid := bl_admin_guard();
  v_reason text := left(btrim(coalesce(p_reason, '')), 500);
  p profiles;
  v_email text;
begin
  if p_user is null then
    raise exception 'Pick a player.' using errcode = 'P0001', hint = 'bad_user';
  end if;
  if p_user = v_admin then
    raise exception 'You cannot delete your own account here.' using errcode = 'P0001', hint = 'self';
  end if;
  select email into v_email from auth.users where id = p_user;
  select * into p from profiles where id = p_user;
  if v_email is null and p.id is null then
    raise exception 'That account no longer exists.' using errcode = 'P0001', hint = 'not_found';
  end if;
  if coalesce(p.is_admin, false) then
    raise exception 'Admins cannot be deleted. Remove their admin first.' using errcode = 'P0001', hint = 'is_admin';
  end if;
  if p.id is not null and lower(btrim(coalesce(p_confirm, ''))) <> lower(p.username) then
    raise exception 'Type the exact username to confirm.' using errcode = 'P0001', hint = 'confirm';
  end if;
  if p.id is null and lower(btrim(coalesce(p_confirm, ''))) <> lower(v_email) then
    raise exception 'This account has no Sim. Type the exact email to confirm.' using errcode = 'P0001', hint = 'confirm';
  end if;
  if length(v_reason) < 3 then
    raise exception 'Write a short reason.' using errcode = 'P0001', hint = 'reason';
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'delete_user', p_user, jsonb_build_object(
    'user_id', p_user, 'username', p.username, 'email', v_email, 'reason', v_reason,
    'cash', p.cash, 'bank', p.bank, 'created_at', p.created_at, 'origin', p.origin));
  return jsonb_build_object('ok', true, 'user_id', p_user, 'username', p.username, 'email', v_email);
end $$;
revoke all on function public.admin_delete_user_start(uuid, text, text) from public, anon;
grant execute on function public.admin_delete_user_start(uuid, text, text) to authenticated, service_role;

-- Storage objects the player uploaded (billboard images, voice notes): removed through the Storage API
-- by the edge function (direct deletes from storage.objects are not allowed).
create or replace function public.bl_user_storage_paths(p_user uuid) returns jsonb
language sql stable security definer set search_path = public, storage as $$
  select coalesce(jsonb_agg(jsonb_build_object('bucket', o.bucket_id, 'name', o.name)), '[]'::jsonb)
    from storage.objects o
   where o.bucket_id in ('billboard-ads', 'player-voice')
     and (o.owner_id = p_user::text or o.name like p_user::text || '/%'
          or o.name in (select a.image_path from public.billboard_ads a where a.user_id = p_user))
$$;
revoke all on function public.bl_user_storage_paths(uuid) from public, anon, authenticated;
grant execute on function public.bl_user_storage_paths(uuid) to service_role;

-- If the auth delete fails after the audit row, the function records that too.
create or replace function public.bl_admin_delete_user_failed(p_admin uuid, p_user uuid, p_error text) returns void
language sql security definer set search_path = public as $$
  insert into admin_audit (admin_id, action, target_user, data)
  values (p_admin, 'delete_user_failed', p_user, jsonb_build_object('user_id', p_user, 'error', left(coalesce(p_error, ''), 500)));
$$;
revoke all on function public.bl_admin_delete_user_failed(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.bl_admin_delete_user_failed(uuid, uuid, text) to service_role;

notify pgrst, 'reload schema';
