-- Benin Life: security fix pack (docs/SECURITY.md). Idempotent. No change to the profiles table (no ALTER, no trigger, no FK).
--  1. Admin takeover: admin.bootstrap_emails is emptied and admin_claim() also needs a confirmed email and ZERO existing admins.
--  2. life_restart(p_confirm): the player types the Sim name and must have signed in with the password in the last
--     security.reauth_minutes (the app does signInWithPassword first). The old zero-argument life_restart() now fails safe.
--  3. push_subscribe / admin_push_subscribe: only real push-service hosts, and nobody can take over another player's endpoint.
--  4. admin_audit_admin policy: a banned admin no longer reads the audit log.
--  5. Reserved usernames (security.reserved_names), checked in bl_check_new_profile (a function, no trigger on profiles).
--  6. Account deletion: bl_user_storage_paths also covers gist-photos, real-biz and club-music; bl_delete_user_leftovers(uuid)
--     removes the rows of tables that hold a user id without a foreign key; the two "done" audit helpers.
--  7. Indexes for foreign keys that pointed at auth.users / profiles and had none.

-- ---------------------------------------------------------------------
-- 0. Guarded text patch helper (raises when the expected text is not found, skips when already patched)
-- ---------------------------------------------------------------------
create or replace function pg_temp.bl_sec_patch(p_fn regprocedure, p_marker text, p_old text, p_new text) returns void
language plpgsql as $$
declare v_src text;
begin
  v_src := pg_get_functiondef(p_fn);
  if position(p_marker in v_src) > 0 then return; end if;
  if position(p_old in v_src) = 0 then
    raise exception 'security pack: % : expected text not found: %', p_fn, p_old;
  end if;
  execute replace(v_src, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------
-- 1. Config + admin takeover
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('security.reauth_minutes', '15', 'security', 'Password re-check window (minutes)',
 'Dangerous actions (starting a new life) need a sign-in with the password within this many minutes. The app asks the player for the password and signs in again first.',
 'minutes', 1, 120),
('security.reserved_names', '"admin,administrator,support,official,beninlife,moderator,mod,staff,system,owner,shalom"', 'security', 'Reserved usernames',
 'Comma-separated words players cannot use as a new username. Compared in lower case with _ . - and spaces removed. A word of 4 or more letters blocks any name that starts with it; a shorter word blocks only itself and itself plus numbers (so "mod" and "mod2" are blocked but "Modeste" is not). Existing usernames are not touched.',
 'text', null, null)
on conflict (key) do nothing;

-- the owners are admins already; a public email list is a takeover risk (email confirmation is off), so it ships empty
update public.game_config set value = '""'::jsonb where key = 'admin.bootstrap_emails' and value <> '""'::jsonb;

create or replace function public.admin_claim() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
  v_conf  timestamptz;
  v_list  text;
  p       profiles;
begin
  if v_uid is null then
    raise exception 'Please log in first.' using errcode = 'P0001', hint = 'not_logged_in';
  end if;
  select * into p from profiles where id = v_uid for update;
  if not found then
    raise exception 'Create your Sim first, then come back here.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if p.banned then
    raise exception 'This account is banned.' using errcode = 'P0001', hint = 'banned';
  end if;
  if p.is_admin then
    return jsonb_build_object('message', 'You are already an admin.', 'is_admin', true);
  end if;
  select lower(trim(email)), email_confirmed_at into v_email, v_conf from auth.users where id = v_uid;
  select coalesce(value #>> '{}', '') into v_list from game_config where key = 'admin.bootstrap_emails';
  -- (a) the list must be non-empty
  if btrim(coalesce(v_list, '')) = '' or btrim(replace(coalesce(v_list, ''), ',', '')) = '' then
    raise exception 'Admin claiming is switched off.' using errcode = 'P0001', hint = 'not_listed';
  end if;
  if v_email is null or v_email = '' or not exists (
       select 1 from unnest(string_to_array(coalesce(v_list, ''), ',')) e where lower(trim(e)) = v_email) then
    raise exception 'This account''s email isn''t on the owner list, so it can''t claim admin.'
      using errcode = 'P0001', hint = 'not_listed';
  end if;
  -- (b) the email must be confirmed
  if v_conf is null then
    raise exception 'Confirm this account''s email first, so it can claim admin.' using errcode = 'P0001', hint = 'not_confirmed';
  end if;
  -- (c) only while there is no admin at all (one claimer at a time)
  perform pg_advisory_xact_lock(hashtext('bl_admin_claim'));
  if exists (select 1 from profiles where is_admin) then
    raise exception 'The game already has an admin. Ask an existing admin to make you one.' using errcode = 'P0001', hint = 'admin_exists';
  end if;
  update profiles set is_admin = true where id = v_uid;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_uid, 'admin_claim', v_uid, jsonb_build_object('email', v_email));
  return jsonb_build_object('message', 'Welcome, boss. You are now an admin.', 'is_admin', true);
end $$;
revoke all on function public.admin_claim() from public, anon;
grant execute on function public.admin_claim() to authenticated;

-- ---------------------------------------------------------------------
-- 2. life_restart needs the Sim name and a fresh sign-in
-- ---------------------------------------------------------------------
-- Old clients (and anyone calling it without the confirmation) fail safe.
create or replace function public.life_restart()
returns jsonb
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Please confirm with your password.' using errcode = 'P0001', hint = 'reauth_required';
end $$;
revoke execute on function public.life_restart() from public, anon;
grant execute on function public.life_restart() to authenticated;

create or replace function public.life_restart(p_confirm text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me     profiles;
  v_now    timestamptz := bl_now();
  v_cool   numeric;
  v_last   timestamptz;
  v_left   numeric;
  v_life   int;
  v_extra  jsonb;
  v_id     bigint;
  v_iat    bigint;
  v_mins   numeric;
begin
  v_me := bl_me_any();   -- logged in, has a profile, not banned (works before a home is chosen too)

  if not bl_cfg_bool('life.restart_enabled') then
    raise exception 'Starting a new life is switched off right now.' using errcode = 'P0001', hint = 'restart_disabled';
  end if;

  -- 1) the player typed their Sim name
  if lower(btrim(coalesce(p_confirm, ''))) <> lower(btrim(v_me.username)) then
    raise exception 'Type your Sim name exactly to confirm.' using errcode = 'P0001', hint = 'confirm';
  end if;
  -- 2) the sign-in (JWT) is fresh: the app signs in with the password right before this call
  v_mins := greatest(coalesce(bl_cfg('security.reauth_minutes'), 15), 1);
  begin
    v_iat := (auth.jwt() ->> 'iat')::bigint;
  exception when others then
    v_iat := null;
  end;
  if v_iat is null or extract(epoch from now()) - v_iat > v_mins * 60 or v_iat - extract(epoch from now()) > 300 then
    raise exception 'Please confirm with your password.' using errcode = 'P0001', hint = 'reauth_required';
  end if;

  v_cool := greatest(coalesce(bl_cfg('life.restart_cooldown_hours'), 0), 0);
  select max(archived_at), count(*) + 1 into v_last, v_life from profile_archive where user_id = v_me.id;
  if v_cool > 0 and v_last is not null then
    v_left := v_cool * 3600 - extract(epoch from v_now - v_last);
    if v_left > 0 then
      raise exception 'You started a new life recently. You can start another in about %.',
        case when v_left >= 7200 then ceil(v_left / 3600)::text || ' hours'
             when v_left >= 3600 then '1 hour ' || ceil((v_left - 3600) / 60)::text || ' min'
             else ceil(v_left / 60)::text || ' min' end
        using errcode = 'P0001', hint = 'restart_cooldown';
    end if;
  end if;

  v_extra := jsonb_build_object(
    'inventory', coalesce((select jsonb_agg(jsonb_build_object('item_id', i.item_id, 'qty', i.qty) order by i.item_id)
                             from inventory i where i.user_id = v_me.id), '[]'::jsonb),
    'furniture', coalesce((select jsonb_agg(to_jsonb(f) - 'user_id' order by f.furniture_id)
                             from player_furniture f where f.user_id = v_me.id), '[]'::jsonb),
    'ledger_count', (select count(*) from ledger l where l.user_id = v_me.id),
    'ledger_recent', coalesce((select jsonb_agg(to_jsonb(x) - 'user_id' order by x.id desc)
                                 from (select * from ledger l where l.user_id = v_me.id order by l.id desc limit 100) x), '[]'::jsonb),
    'events_count', (select count(*) from events e where e.user_id = v_me.id),
    'chat_messages', (select count(*) from chat_messages c where c.user_id = v_me.id)
  );

  insert into profile_archive (user_id, life_no, username, origin, cash, bank, profile, extra, archived_at)
  values (v_me.id, v_life, v_me.username, v_me.origin, v_me.cash, v_me.bank, to_jsonb(v_me), v_extra, v_now)
  returning id into v_id;

  insert into admin_audit (admin_id, action, target_user, data)
  values (null, 'life_restart', v_me.id,
          jsonb_build_object('archive_id', v_id, 'life_no', v_life, 'username', v_me.username, 'origin', v_me.origin,
                             'cash', v_me.cash, 'bank', v_me.bank, 'reauth', true));

  -- ledger, events, inventory and player_furniture go with the profile (ON DELETE CASCADE);
  -- chat, blocks, reports and audit rows point at the auth account and stay.
  delete from profiles where id = v_me.id;

  return jsonb_build_object(
    'message', 'Your old life is archived. Create your new Sim.',
    'archive_id', v_id,
    'life_no', v_life + 1
  );
end $$;
revoke execute on function public.life_restart(text) from public, anon;
grant execute on function public.life_restart(text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Push subscriptions: known push services only, no endpoint takeover
-- ---------------------------------------------------------------------
create or replace function public.bl_push_endpoint_ok(p_endpoint text) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(
    length(p_endpoint) <= 1000
    and p_endpoint ~ '^https://[A-Za-z0-9.-]+(:443)?/[^[:space:]]+$'
    and lower(substring(p_endpoint from '^https://([A-Za-z0-9.-]+)')) ~
        '^(fcm\.googleapis\.com|([a-z0-9-]+\.)+push\.services\.mozilla\.com|updates\.push\.services\.mozilla\.com|web\.push\.apple\.com|([a-z0-9-]+\.)+push\.apple\.com|([a-z0-9-]+\.)+notify\.windows\.com)$',
    false)
$$;
revoke all on function public.bl_push_endpoint_ok(text) from public, anon, authenticated;

-- subscriptions that point somewhere else than a push service are removed (they could only ever have been planted)
delete from public.push_subscriptions where not public.bl_push_endpoint_ok(endpoint);

create or replace function public.push_subscribe(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_n int;
begin
  if not public.bl_push_endpoint_ok(p_endpoint)
     or coalesce(p_p256dh, '') !~ '^[A-Za-z0-9_=-]{60,120}$' or coalesce(p_auth, '') !~ '^[A-Za-z0-9_=-]{16,40}$' then
    raise exception 'That push subscription looks wrong.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  insert into push_subscriptions as s (user_id, endpoint, p256dh, auth, user_agent)
  values (v_uid, p_endpoint, p_p256dh, p_auth, left(coalesce(p_user_agent, ''), 200))
  on conflict (endpoint) do update set p256dh = excluded.p256dh, auth = excluded.auth,
                                       user_agent = excluded.user_agent, fail_count = 0
    where s.user_id = excluded.user_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'This device is already linked to another account. Sign out there first.' using errcode = 'P0001', hint = 'endpoint_taken';
  end if;
  -- at most 8 devices per player: the oldest go
  delete from push_subscriptions where user_id = v_uid and id not in
    (select id from push_subscriptions where user_id = v_uid order by id desc limit 8);
  insert into push_prefs (user_id) values (v_uid) on conflict (user_id) do nothing;
  return push_state();
end $$;
revoke all on function public.push_subscribe(text, text, text, text) from public, anon;
grant execute on function public.push_subscribe(text, text, text, text) to authenticated;

create or replace function public.admin_push_subscribe(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_n int;
begin
  if not public.bl_push_endpoint_ok(p_endpoint)
     or coalesce(p_p256dh, '') !~ '^[A-Za-z0-9_=-]{60,120}$' or coalesce(p_auth, '') !~ '^[A-Za-z0-9_=-]{16,40}$' then
    raise exception 'That push subscription looks wrong.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  insert into push_subscriptions as s (user_id, endpoint, p256dh, auth, user_agent)
  values (v_admin, p_endpoint, p_p256dh, p_auth, left(coalesce(p_user_agent, ''), 200))
  on conflict (endpoint) do update set p256dh = excluded.p256dh, auth = excluded.auth,
                                       user_agent = excluded.user_agent, fail_count = 0
    where s.user_id = excluded.user_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'This device is already linked to another account. Sign out there first.' using errcode = 'P0001', hint = 'endpoint_taken';
  end if;
  insert into admin_audit (admin_id, action, data) values (v_admin, 'push_subscribe', jsonb_build_object('ua', left(coalesce(p_user_agent, ''), 120)));
  return jsonb_build_object('message', 'Notifications are on for this device.',
                            'subscriptions', (select count(*) from push_subscriptions where user_id = v_admin));
end $$;
revoke all on function public.admin_push_subscribe(text, text, text, text) from public, anon;
grant execute on function public.admin_push_subscribe(text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. admin_audit_admin: a banned admin reads nothing (same as feedback_admin)
-- ---------------------------------------------------------------------
drop policy if exists admin_audit_admin on public.admin_audit;
create policy admin_audit_admin on public.admin_audit for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin and not p.banned));

-- ---------------------------------------------------------------------
-- 5. Reserved usernames (new profiles only; patched into the live bl_check_new_profile)
-- ---------------------------------------------------------------------
select pg_temp.bl_sec_patch(
  'public.bl_check_new_profile(uuid, text, text, jsonb)'::regprocedure,
  'security.reserved_names',
  $old$  if p_gender not in ('male','female') then$old$,
  $new$  -- reserved words (game_config security.reserved_names); a past admin may keep their old name in a new life
  if not exists (select 1 from profile_archive pa where pa.user_id = p_uid and pa.profile ->> 'is_admin' = 'true')
     and exists (
       select 1
         from (select lower(regexp_replace(p_name, '[_.[:space:]-]', '', 'g')) as v) nm,
              (select lower(regexp_replace(w, '[_.[:space:]-]', '', 'g')) as w
                 from game_config c,
                      lateral (select jsonb_array_elements_text(c.value) as w
                                where jsonb_typeof(c.value) = 'array'
                               union all
                               select unnest(string_to_array(c.value #>> '{}', ',')) as w
                                where jsonb_typeof(c.value) = 'string') x
                where c.key = 'security.reserved_names') r
        where r.w <> '' and (nm.v = r.w
                or (length(r.w) >= 4 and left(nm.v, length(r.w)) = r.w)
                or (length(r.w) < 4 and left(nm.v, length(r.w)) = r.w and substr(nm.v, length(r.w) + 1) ~ '^[0-9]*$'))) then
    raise exception 'That username is reserved. Please pick another one.' using errcode = 'P0001', hint = 'reserved_name';
  end if;
  if p_gender not in ('male','female') then$new$);

-- ---------------------------------------------------------------------
-- 6. Account deletion
-- ---------------------------------------------------------------------
-- 6c. every file a player owns: billboard images, voice notes, gist photos (folder = player id), real-business photos
-- (folder = player id) and club-music files the player uploaded (never a file a track still points at).
create or replace function public.bl_user_storage_paths(p_user uuid) returns jsonb
language sql stable security definer set search_path = public, storage as $$
  select coalesce(jsonb_agg(jsonb_build_object('bucket', o.bucket_id, 'name', o.name)), '[]'::jsonb)
    from storage.objects o
   where (o.bucket_id in ('billboard-ads', 'player-voice')
          and (o.owner_id = p_user::text or o.name like p_user::text || '/%'
               or o.name in (select a.image_path from public.billboard_ads a where a.user_id = p_user)))
      or (o.bucket_id in ('gist-photos', 'real-biz')
          and (o.name like p_user::text || '/%' or o.owner_id = p_user::text))
      or (o.bucket_id = 'club-music' and o.owner_id = p_user::text
          and o.name not in (select t.storage_path from public.music_tracks t where t.storage_path is not null))
$$;
revoke all on function public.bl_user_storage_paths(uuid) from public, anon, authenticated;
grant execute on function public.bl_user_storage_paths(uuid) to service_role;

-- 6d. Rows that hold a user id WITHOUT a foreign key (so the auth.users cascade does not reach them).
-- The (table, column) list is fixed here, built from information_schema (uuid columns with no FK). Choices:
--   delete  : rows that belong to the player (their state, logs, applications, votes) and rows that cannot exist without
--             them (a court case, hire or debt where they are a party; a seat they hold; a report they sent or got).
--   set null: columns that only record WHO did something to a row that matters to somebody else (an admin who reviewed,
--             a judge, an appointer, the other player named on a gist, a crew handover log, ...).
-- It returns how many rows each column touched ({"table.column": n}). Safe to run twice. Service role only.
create or replace function public.bl_delete_user_leftovers(p_uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v jsonb := '{}'::jsonb;
  n bigint;
begin
  if p_uid is null then
    raise exception 'user id needed';
  end if;
  delete from public.business_log where owner_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('business_log.owner_id', n); end if;
  delete from public.company_log where owner_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('company_log.owner_id', n); end if;
  delete from public.cook_daily where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('cook_daily.user_id', n); end if;
  delete from public.court_gallery where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('court_gallery.user_id', n); end if;
  delete from public.court_lawyers where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('court_lawyers.user_id', n); end if;
  delete from public.drive_state where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('drive_state.user_id', n); end if;
  delete from public.drive_trip where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('drive_trip.user_id', n); end if;
  delete from public.home_resize_pending where owner_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('home_resize_pending.owner_id', n); end if;
  delete from public.ind_applications where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('ind_applications.user_id', n); end if;
  delete from public.ind_statements where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('ind_statements.user_id', n); end if;
  delete from public.ind_votes where voter_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('ind_votes.voter_id', n); end if;
  delete from public.journey_done where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('journey_done.user_id', n); end if;
  delete from public.journey_progress where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('journey_progress.user_id', n); end if;
  delete from public.kids_charges where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('kids_charges.user_id', n); end if;
  delete from public.player_app_days where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('player_app_days.user_id', n); end if;
  delete from public.player_days where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('player_days.user_id', n); end if;
  delete from public.player_moment_state where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('player_moment_state.user_id', n); end if;
  delete from public.player_moments where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('player_moments.user_id', n); end if;
  delete from public.player_power where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('player_power.user_id', n); end if;
  delete from public.player_return_state where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('player_return_state.user_id', n); end if;
  delete from public.player_sources where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('player_sources.user_id', n); end if;
  delete from public.return_gifts where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('return_gifts.user_id', n); end if;
  delete from public.return_nudges where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('return_nudges.user_id', n); end if;
  delete from public.roam_bubbles where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('roam_bubbles.user_id', n); end if;
  delete from public.roam_prefs where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('roam_prefs.user_id', n); end if;
  delete from public.roam_presence where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('roam_presence.user_id', n); end if;
  delete from public.roam_sessions where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('roam_sessions.user_id', n); end if;
  delete from public.vehicle_state where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('vehicle_state.user_id', n); end if;
  delete from public.weekly_event_checkins where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('weekly_event_checkins.user_id', n); end if;
  delete from public.weekly_push_log where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('weekly_push_log.user_id', n); end if;
  delete from public.roam_reports where reporter_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('roam_reports.reporter_id', n); end if;
  delete from public.roam_reports where reported_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('roam_reports.reported_id', n); end if;
  delete from public.ind_holders where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('ind_holders.user_id', n); end if;
  delete from public.court_cases where plaintiff_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('court_cases.plaintiff_id', n); end if;
  delete from public.court_cases where defendant_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('court_cases.defendant_id', n); end if;
  delete from public.court_hires where client_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('court_hires.client_id', n); end if;
  delete from public.court_hires where lawyer_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('court_hires.lawyer_id', n); end if;
  delete from public.court_debts where debtor_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('court_debts.debtor_id', n); end if;
  delete from public.court_debts where creditor_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('court_debts.creditor_id', n); end if;
  delete from public.court_statements where author_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('court_statements.author_id', n); end if;
  delete from public.love_relationships where asked_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('love_relationships.asked_by', n); end if;
  update public.billboard_ads set reviewed_by = null where reviewed_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('billboard_ads.reviewed_by', n); end if;
  update public.court_cases set judge_id = null where judge_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('court_cases.judge_id', n); end if;
  update public.crew_boss_log set by_admin = null where by_admin = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('crew_boss_log.by_admin', n); end if;
  update public.crew_boss_log set from_user = null where from_user = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('crew_boss_log.from_user', n); end if;
  update public.crew_boss_log set to_user = null where to_user = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('crew_boss_log.to_user', n); end if;
  update public.game_config set updated_by = null where updated_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('game_config.updated_by', n); end if;
  update public.gist_bans set banned_by = null where banned_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('gist_bans.banned_by', n); end if;
  update public.gist_comments set reply_to_user = null where reply_to_user = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('gist_comments.reply_to_user', n); end if;
  update public.gist_messages set money_to = null where money_to = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('gist_messages.money_to', n); end if;
  update public.ind_applications set decided_by = null where decided_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('ind_applications.decided_by', n); end if;
  update public.ind_changes set user_id = null where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('ind_changes.user_id', n); end if;
  update public.ind_holders set appointed_by = null where appointed_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('ind_holders.appointed_by', n); end if;
  update public.kids_children set named_by = null where named_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('kids_children.named_by', n); end if;
  update public.kids_children set proposed_by = null where proposed_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('kids_children.proposed_by', n); end if;
  update public.kids_school set fee_paid_by = null where fee_paid_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('kids_school.fee_paid_by', n); end if;
  update public.kids_school_requests set paid_by = null where paid_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('kids_school_requests.paid_by', n); end if;
  update public.lounge_members set granted_by = null where granted_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('lounge_members.granted_by', n); end if;
  update public.love_log set actor_id = null where actor_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('love_log.actor_id', n); end if;
  update public.love_relationships set ended_by = null where ended_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('love_relationships.ended_by', n); end if;
  update public.love_reports set handled_by = null where handled_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('love_reports.handled_by', n); end if;
  update public.market_listings set removed_by = null where removed_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('market_listings.removed_by', n); end if;
  update public.player_house_upgrades set granted_by = null where granted_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('player_house_upgrades.granted_by', n); end if;
  update public.player_moments set handled_by = null where handled_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('player_moments.handled_by', n); end if;
  update public.power_events set started_by = null where started_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('power_events.started_by', n); end if;
  update public.property_events set user_id = null where user_id = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('property_events.user_id', n); end if;
  update public.real_businesses set reviewed_by = null where reviewed_by = p_uid;
  get diagnostics n = row_count; if n > 0 then v := v || jsonb_build_object('real_businesses.reviewed_by', n); end if;
  return v;
end $$;
revoke all on function public.bl_delete_user_leftovers(uuid) from public, anon, authenticated;
grant execute on function public.bl_delete_user_leftovers(uuid) to service_role;

-- 6a. The "done" rows: written only after auth.admin.deleteUser succeeded, so target_user stays null (the user is gone;
-- the id is in data). The "started" rows (self_delete_account / delete_user, written before) keep the snapshot.
create or replace function public.bl_self_delete_done(p_user uuid, p_files int, p_leftovers jsonb) returns void
language sql security definer set search_path = public as $$
  insert into admin_audit (admin_id, action, target_user, data)
  values (null, 'self_delete_account_done', null,
          jsonb_build_object('user_id', p_user, 'files_removed', coalesce(p_files, 0), 'leftovers', coalesce(p_leftovers, '{}'::jsonb)));
$$;
revoke all on function public.bl_self_delete_done(uuid, int, jsonb) from public, anon, authenticated;
grant execute on function public.bl_self_delete_done(uuid, int, jsonb) to service_role;

create or replace function public.bl_admin_delete_user_done(p_admin uuid, p_user uuid, p_files int, p_leftovers jsonb) returns void
language sql security definer set search_path = public as $$
  insert into admin_audit (admin_id, action, target_user, data)
  values (p_admin, 'delete_user_done', null,
          jsonb_build_object('user_id', p_user, 'files_removed', coalesce(p_files, 0), 'leftovers', coalesce(p_leftovers, '{}'::jsonb)));
$$;
revoke all on function public.bl_admin_delete_user_done(uuid, uuid, int, jsonb) from public, anon, authenticated;
grant execute on function public.bl_admin_delete_user_done(uuid, uuid, int, jsonb) to service_role;

-- ---------------------------------------------------------------------
-- 7. Indexes for foreign keys (auth.users / profiles) that had none. (profiles itself is left alone.)
-- ---------------------------------------------------------------------
create index if not exists locations_private_home_owner_id_idx on public.locations (private_home_owner_id);
create index if not exists player_friendships_requested_by_idx on public.player_friendships (requested_by);
create index if not exists player_house_invites_guest_id_idx on public.player_house_invites (guest_id);
create index if not exists player_house_invites_host_id_idx on public.player_house_invites (host_id);
create index if not exists chat_hidden_messages_user_id_idx on public.chat_hidden_messages (user_id);
create index if not exists feedback_replied_by_idx on public.feedback (replied_by);
create index if not exists broadcasts_created_by_idx on public.broadcasts (created_by);
create index if not exists jail_cases_released_by_idx on public.jail_cases (released_by);
create index if not exists shrine_notices_user_id_idx on public.shrine_notices (user_id);
create index if not exists money_drops_sprayer_idx on public.money_drops (sprayer);
create index if not exists weekly_earn_winners_user_id_idx on public.weekly_earn_winners (user_id);
create index if not exists music_tracks_created_by_idx on public.music_tracks (created_by);
create index if not exists market_listings_buyer_id_idx on public.market_listings (buyer_id);
create index if not exists market_listings_buyer_only_idx on public.market_listings (buyer_only);
create index if not exists market_trades_buyer_id_idx on public.market_trades (buyer_id);
create index if not exists market_reports_reporter_id_idx on public.market_reports (reporter_id);
create index if not exists crews_created_by_idx on public.crews (created_by);
create index if not exists crew_invites_from_user_idx on public.crew_invites (from_user);
create index if not exists crew_invites_to_user_idx on public.crew_invites (to_user);
create index if not exists crew_bank_log_user_id_idx on public.crew_bank_log (user_id);
create index if not exists crew_reports_reporter_id_idx on public.crew_reports (reporter_id);
create index if not exists crew_runs_started_by_idx on public.crew_runs (started_by);
create index if not exists parties_founder_id_idx on public.parties (founder_id);
create index if not exists election_cycles_created_by_idx on public.election_cycles (created_by);
create index if not exists pol_reports_reporter_id_idx on public.pol_reports (reporter_id);
create index if not exists pol_results_user_id_idx on public.pol_results (user_id);
create index if not exists office_holders_appointed_by_idx on public.office_holders (appointed_by);
create index if not exists office_holders_user_id_idx on public.office_holders (user_id);
create index if not exists city_parties_host_id_idx on public.city_parties (host_id);
create index if not exists city_party_guests_user_id_idx on public.city_party_guests (user_id);
create index if not exists real_biz_reports_user_id_idx on public.real_biz_reports (user_id);
create index if not exists love_relationships_user_a_idx on public.love_relationships (user_a);
create index if not exists love_relationships_user_b_idx on public.love_relationships (user_b);
create index if not exists love_asks_to_user_idx on public.love_asks (to_user);
create index if not exists love_date_invites_from_user_idx on public.love_date_invites (from_user);
create index if not exists love_date_invites_to_user_idx on public.love_date_invites (to_user);
create index if not exists love_reports_reported_id_idx on public.love_reports (reported_id);
create index if not exists kids_care_log_user_id_idx on public.kids_care_log (user_id);
create index if not exists gist_groups_owner_id_idx on public.gist_groups (owner_id);
create index if not exists gist_group_bans_user_id_idx on public.gist_group_bans (user_id);
create index if not exists player_residence_landlord_id_idx on public.player_residence (landlord_id);
create index if not exists property_income_owner_id_idx on public.property_income (owner_id);
create index if not exists property_income_tenant_id_idx on public.property_income (tenant_id);
create index if not exists crew_boss_requests_holder_idx on public.crew_boss_requests (holder);
create index if not exists crew_boss_requests_requester_idx on public.crew_boss_requests (requester);

notify pgrst, 'reload schema';
