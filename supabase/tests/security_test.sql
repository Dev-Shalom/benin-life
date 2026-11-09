-- Security fix pack (20261121000100_security_pack.sql, docs/SECURITY.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/security_test.sql
-- Groups: 1 admin_claim (empty list / unconfirmed / an admin exists) · 2 life_restart (zero-arg, wrong name, stale sign-in, ok) ·
-- 3 push_subscribe (host list, no endpoint takeover) · 4 reserved usernames · 5 bl_delete_user_leftovers + storage paths + done rows ·
-- 6 indexes and the audit policy.

-- the outcome of a statement as 'ok' or its hint (or the message when there is no hint)
create or replace function pg_temp.hint_of(p_sql text) returns text
language plpgsql as $$
declare v_h text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  get stacked diagnostics v_h = pg_exception_hint;
  return coalesce(nullif(v_h, ''), sqlerrm);
end $$;

-- a player with a Sim
create or replace function pg_temp.mk(p_email text, p_name text) returns uuid
language plpgsql as $$
declare v uuid;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  v := pg_temp.new_user(p_email);
  perform pg_temp.login(v);
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  return v;
end $$;

-- log in with a JWT whose password sign-in (amr) was p_age_s seconds ago (the token itself is fresh, like after a refresh)
create or replace function pg_temp.login_aged(p uuid, p_age_s int) returns void
language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated',
         'iat', extract(epoch from now())::bigint,
         'amr', json_build_array(json_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint - p_age_s)))::text, true);
  select set_config('request.jwt.claim.sub', p::text, true);
$$;

-- 1. admin_claim ---------------------------------------------------------------------------
do $$
declare boss uuid; unconf uuid; other uuid; r jsonb;
begin
  update profiles set is_admin = false where is_admin;   -- exact counts inside this rolled-back transaction
  boss := pg_temp.mk('sec_boss@sec.bl', 'Sec_Boss');
  unconf := pg_temp.mk('sec_unconf@sec.bl', 'Sec_Unconf');
  other := pg_temp.mk('sec_other@sec.bl', 'Sec_Other');
  update auth.users set email_confirmed_at = null where id = unconf;

  -- (a) empty list: nobody can claim, even with a matching email
  perform pg_temp.login(boss);
  perform pg_temp.assert(pg_temp.hint_of('select admin_claim()') = 'not_listed', 'empty list refuses');
  perform pg_temp.assert(not (select is_admin from profiles where id = boss), 'still not admin');
  update game_config set value = '" , "' where key = 'admin.bootstrap_emails';
  perform pg_temp.assert(pg_temp.hint_of('select admin_claim()') = 'not_listed', 'a list of only commas refuses');

  -- (b) unconfirmed email
  update game_config set value = '"sec_boss@sec.bl, SEC_UNCONF@sec.bl, sec_other@sec.bl"' where key = 'admin.bootstrap_emails';
  perform pg_temp.login(unconf);
  perform pg_temp.assert(pg_temp.hint_of('select admin_claim()') = 'not_confirmed', 'unconfirmed email refuses');
  perform pg_temp.assert(not (select is_admin from profiles where id = unconf), 'unconfirmed stays non-admin');

  -- listed, confirmed, no admin yet: works
  perform pg_temp.login(boss);
  r := admin_claim();
  perform pg_temp.assert((r ->> 'is_admin')::boolean and (select is_admin from profiles where id = boss), 'first claim ok');

  -- (c) an admin exists now: the next listed, confirmed player is refused, and the admin is untouched
  perform pg_temp.login(other);
  perform pg_temp.assert(pg_temp.hint_of('select admin_claim()') = 'admin_exists', 'second claim refused');
  perform pg_temp.assert(not (select is_admin from profiles where id = other), 'other stays non-admin');
  perform pg_temp.assert((select is_admin from profiles where id = boss), 'the existing admin is not demoted');
  perform pg_temp.login(boss);
  perform pg_temp.assert(admin_claim() ->> 'message' like 'You are already%', 'an admin claiming again is a no-op');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.admin_claim()', 'execute'), 'anon cannot claim');
  raise notice 'security 1 OK: admin_claim';
end $$;

-- 2. life_restart --------------------------------------------------------------------------
do $$
declare a uuid; r jsonb; n bigint;
begin
  a := pg_temp.mk('sec_life@sec.bl', 'Sec_Life');
  perform pg_temp.assert((select value from game_config where key = 'security.reauth_minutes') = '15'::jsonb, 'reauth minutes seeded');
  -- the old zero-argument call fails safe
  perform pg_temp.assert(pg_temp.hint_of('select life_restart()') = 'reauth_required', 'zero-arg raises');
  perform pg_temp.assert(exists (select 1 from profiles where id = a), 'zero-arg changed nothing');
  -- wrong / empty / other name
  perform pg_temp.assert(pg_temp.hint_of($q$ select life_restart('Somebody_Else') $q$) = 'confirm', 'wrong name raises');
  perform pg_temp.assert(pg_temp.hint_of($q$ select life_restart('') $q$) = 'confirm', 'empty name raises');
  perform pg_temp.assert(pg_temp.hint_of($q$ select life_restart(null) $q$) = 'confirm', 'null name raises');
  perform pg_temp.assert(exists (select 1 from profiles where id = a), 'wrong name changed nothing');
  -- a sign-in older than the window
  perform pg_temp.login_aged(a, 16 * 60);
  perform pg_temp.assert(pg_temp.hint_of($q$ select life_restart(' sec_LIFE ') $q$) = 'reauth_required', 'stale password sign-in raises');
  -- no amr at all, an amr without a password entry, a fresh iat alone
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'iat', extract(epoch from now())::bigint)::text, true);
  perform pg_temp.assert(pg_temp.hint_of($q$ select life_restart('Sec_Life') $q$) = 'reauth_required', 'missing amr raises');
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'iat', extract(epoch from now())::bigint,
    'amr', json_build_array(json_build_object('method', 'otp', 'timestamp', extract(epoch from now())::bigint)))::text, true);
  perform pg_temp.assert(pg_temp.hint_of($q$ select life_restart('Sec_Life') $q$) = 'reauth_required', 'a non-password amr raises');
  perform pg_temp.assert(exists (select 1 from profiles where id = a), 'stale sign-in changed nothing');
  -- the window is a setting
  update game_config set value = '30' where key = 'security.reauth_minutes';
  perform pg_temp.login_aged(a, 20 * 60);
  perform pg_temp.assert(pg_temp.hint_of($q$ select life_restart('sec_life') $q$) = 'ok', 'a wider window accepts a 20 minute old sign-in');
  perform pg_temp.assert(not exists (select 1 from profiles where id = a), 'the Sim is gone after a good restart');
  perform pg_temp.assert(exists (select 1 from profile_archive where user_id = a and username = 'Sec_Life'), 'archived');
  perform pg_temp.assert(exists (select 1 from admin_audit where target_user = a and action = 'life_restart'), 'audit row kept');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.life_restart(text)', 'execute'), 'authenticated may call it');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.life_restart(text)', 'execute'), 'anon may not');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.life_restart()', 'execute'), 'anon may not call the old one');
  raise notice 'security 2 OK: life_restart';
end $$;

-- 3. push_subscribe ------------------------------------------------------------------------
do $$
declare a uuid; b uuid; k text := repeat('A', 87); au text := repeat('B', 22); ep text := 'https://fcm.googleapis.com/fcm/send/sec-test-endpoint-1';
begin
  a := pg_temp.mk('sec_push_a@sec.bl', 'Sec_Push_A');
  b := pg_temp.mk('sec_push_b@sec.bl', 'Sec_Push_B');
  -- the host test itself
  perform pg_temp.assert(bl_push_endpoint_ok('https://fcm.googleapis.com/fcm/send/abc'), 'fcm ok');
  perform pg_temp.assert(bl_push_endpoint_ok('https://updates.push.services.mozilla.com/wpush/v2/abc'), 'mozilla updates ok');
  perform pg_temp.assert(bl_push_endpoint_ok('https://autopush.push.services.mozilla.com/wpush/v2/abc'), 'mozilla subdomain ok');
  perform pg_temp.assert(bl_push_endpoint_ok('https://web.push.apple.com/QAbc'), 'apple ok');
  perform pg_temp.assert(bl_push_endpoint_ok('https://api.push.apple.com/3/device/abc'), 'apple subdomain ok');
  perform pg_temp.assert(bl_push_endpoint_ok('https://wns2-par02p.notify.windows.com/w/?token=abc'), 'windows ok');
  perform pg_temp.assert(bl_push_endpoint_ok('https://db5p.notify.windows.com/w/?token=abc'), 'windows plain subdomain ok');
  perform pg_temp.assert(not bl_push_endpoint_ok('https://example.com/push/abc'), 'other host refused');
  perform pg_temp.assert(not bl_push_endpoint_ok('https://169.254.169.254/latest/meta-data/'), 'ip refused');
  perform pg_temp.assert(not bl_push_endpoint_ok('https://localhost/abc'), 'localhost refused');
  perform pg_temp.assert(not bl_push_endpoint_ok('http://fcm.googleapis.com/fcm/send/abc'), 'plain http refused');
  perform pg_temp.assert(not bl_push_endpoint_ok('https://fcm.googleapis.com.evil.com/fcm/send/abc'), 'lookalike suffix refused');
  perform pg_temp.assert(not bl_push_endpoint_ok('https://evilfcm.googleapis.com/x'), 'other googleapis host refused');
  perform pg_temp.assert(not bl_push_endpoint_ok('https://fcm.googleapis.com@evil.com/fcm/send/abc'), 'userinfo trick refused');
  perform pg_temp.assert(not bl_push_endpoint_ok('https://evil.com/?x=.push.apple.com/'), 'host in the query refused');
  perform pg_temp.assert(not bl_push_endpoint_ok(null), 'null refused');

  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select push_subscribe(%L, %L, %L)', 'https://example.com/push/abc-def-ghi', k, au)) = 'bad_value',
    'a non push-service host is refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select push_subscribe(%L, %L, %L)', 'https://10.0.0.1/abcdefghij', k, au)) = 'bad_value', 'a private ip is refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select push_subscribe(%L, %L, %L)', ep, k, au)) = 'ok', 'a push-service endpoint works');
  perform pg_temp.assert(pg_temp.hint_of(format('select push_subscribe(%L, %L, %L)', ep, k, au)) = 'ok', 'the same player can re-subscribe');
  perform pg_temp.assert((select user_id from push_subscriptions where endpoint = ep) = a, 'owned by a');

  -- b cannot take a's endpoint over
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select push_subscribe(%L, %L, %L)', ep, repeat('C', 87), repeat('D', 22))) = 'endpoint_taken',
    'taking another player''s endpoint is refused');
  perform pg_temp.assert((select user_id from push_subscriptions where endpoint = ep) = a, 'still owned by a');
  perform pg_temp.assert((select p256dh from push_subscriptions where endpoint = ep) = k, 'a''s keys were not replaced');
  perform pg_temp.assert(pg_temp.hint_of(format('select push_subscribe(%L, %L, %L)', 'https://web.push.apple.com/QSecB1', k, au)) = 'ok', 'b can use their own endpoint');
  raise notice 'security 3 OK: push_subscribe';
end $$;

-- 4. reserved usernames --------------------------------------------------------------------
do $$
declare n text; v uuid;
begin
  v := pg_temp.new_user('sec_names@sec.bl');
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  foreach n in array array['Admin', 'Admin_1', 'AdminBoss', 'admin_01', 'ADMINISTRATOR', 'BeninLifeHQ', 'Benin_Life', 'BeninLife99', 'Moderator1', 'ModeratorX',
                           'Sup_port', 'Support', 'Support2', 'Official', 'Official_2', 'Mod', 'MOD_2', 'Staff', 'System', 'Owner', 'Owner_1', 'Shalom', 'Shalom1'] loop
    perform pg_temp.assert(pg_temp.hint_of(format('select create_profile_v2(%L, ''male'', ''{"gender":"male"}'', ''{hustler,foodie}'', ''oga_at_the_top'')', n)) = 'reserved_name',
      'reserved: ' || n);
  end loop;
  perform pg_temp.assert(not exists (select 1 from profiles where id = v), 'no profile was created');
  -- real names that merely start with a plain reserved word stay free
  foreach n in array array['Shalom_Fan', 'Stafford', 'Systems', 'Supporter', 'Owners', 'Officially', 'Modupe', 'Modeste', 'Okoye', 'Ada_Obi'] loop
    perform pg_temp.assert(pg_temp.hint_of(format('select bl_check_new_profile(%L, %L, ''male'', ''{"gender":"male"}'')', v, n)) = 'ok', 'allowed: ' || n);
  end loop;
  -- the list is a setting (text or json array)
  update game_config set value = '["boss_man", "x*"]'::jsonb where key = 'security.reserved_names';
  perform pg_temp.assert(pg_temp.hint_of(format('select bl_check_new_profile(%L, ''Boss_Man_2'', ''male'', ''{"gender":"male"}'')', v)) = 'reserved_name', 'json array setting works');
  perform pg_temp.assert(pg_temp.hint_of(format('select bl_check_new_profile(%L, ''Admin'', ''male'', ''{"gender":"male"}'')', v)) = 'ok', 'removed words are free');
  update game_config set value = '""' where key = 'security.reserved_names';
  perform pg_temp.assert(pg_temp.hint_of(format('select bl_check_new_profile(%L, ''Admin'', ''male'', ''{"gender":"male"}'')', v)) = 'ok', 'an empty list blocks nothing');
  raise notice 'security 4 OK: reserved names';
end $$;

-- 5. bl_delete_user_leftovers, storage paths, done rows ------------------------------------
do $$
declare
  gone uuid := gen_random_uuid(); keep uuid := gen_random_uuid(); keep2 uuid := gen_random_uuid();
  r jsonb; c1 bigint; c2 bigint; paths jsonb;
begin
  -- rows that hold a user id with no foreign key
  insert into player_sources (user_id, heard) values (gone, 'friend'), (keep, 'friend');
  insert into court_cases (case_no, tier, kind, event_ref, title, plaintiff_id, defendant_id, claim, hearing_at, ruling_deadline)
  values ('SEC-1', 'high', 'pickpocket', 'sec-ev-1', 'gone is the plaintiff', gone, keep, 1000, now(), now() + interval '1 day'),
         ('SEC-2', 'high', 'pickpocket', 'sec-ev-2', 'gone is the defendant', keep, gone, 1000, now(), now() + interval '1 day'),
         ('SEC-3', 'high', 'pickpocket', 'sec-ev-3', 'gone is only the judge', keep, keep2, 1000, now(), now() + interval '1 day');
  update court_cases set judge_id = gone where case_no = 'SEC-3';
  insert into court_statements (case_id, side, author_id, body)
  select id, 'plaintiff', gone, 'hello' from court_cases where case_no in ('SEC-1', 'SEC-3');
  insert into court_debts (case_id, debtor_id, creditor_id, kind, amount, owed)
  select id, keep, gone, 'restitution', 500, 500 from court_cases where case_no = 'SEC-3';

  r := bl_delete_user_leftovers(gone);
  perform pg_temp.assert((r ->> 'player_sources.user_id')::int = 1, 'reports the rows it removed: ' || r::text);
  perform pg_temp.assert(not exists (select 1 from player_sources where user_id = gone), 'player_sources row removed');
  perform pg_temp.assert(exists (select 1 from player_sources where user_id = keep), 'another player''s row is untouched');
  perform pg_temp.assert(not exists (select 1 from court_cases where case_no in ('SEC-1', 'SEC-2')), 'cases where the user was a party are removed');
  perform pg_temp.assert(not exists (select 1 from court_statements s join court_cases c on c.id = s.case_id where c.case_no = 'SEC-1'), 'their statements go with the case');
  perform pg_temp.assert((select judge_id from court_cases where case_no = 'SEC-3') is null, 'judge seat is set to null, the case stays');
  perform pg_temp.assert(exists (select 1 from court_cases where case_no = 'SEC-3'), 'case between two other players stays');
  perform pg_temp.assert(not exists (select 1 from court_statements s join court_cases c on c.id = s.case_id where c.case_no = 'SEC-3' and s.author_id is not null),
    'statements by the user on another case are removed');
  perform pg_temp.assert(not exists (select 1 from court_debts where creditor_id = gone), 'a debt owed to the user is dropped');
  -- twice is fine
  r := bl_delete_user_leftovers(gone);
  perform pg_temp.assert(r = '{}'::jsonb, 'second run finds nothing');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_delete_user_leftovers(uuid)', 'execute'), 'authenticated cannot call it');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.bl_delete_user_leftovers(uuid)', 'execute'), 'anon cannot call it');
  perform pg_temp.assert(has_function_privilege('service_role', 'public.bl_delete_user_leftovers(uuid)', 'execute'), 'service role can');
  perform pg_temp.assert(pg_temp.hint_of('select bl_delete_user_leftovers(null)') <> 'ok', 'null is refused');

  -- storage files: gist-photos, real-biz (folder = player id), club-music (owner) and the old buckets
  if exists (select 1 from storage.buckets where id = 'gist-photos') and exists (select 1 from storage.buckets where id = 'real-biz')
     and exists (select 1 from storage.buckets where id = 'club-music') then
    insert into storage.objects (bucket_id, name, owner_id) values
      ('gist-photos', gone::text || '/a.jpg', gone::text),
      ('gist-photos', keep::text || '/b.jpg', keep::text),
      ('real-biz', gone::text || '/shop.webp', gone::text),
      ('club-music', 'sec-gone-own.mp3', gone::text),
      ('club-music', 'sec-gone-used.mp3', gone::text),
      ('club-music', 'sec-keep.mp3', keep::text);
    insert into music_tracks (title, url, storage_path) values ('Sec track', 'https://example.com/sec.mp3', 'sec-gone-used.mp3');
    paths := bl_user_storage_paths(gone);
    perform pg_temp.assert(jsonb_array_length(paths) = 3, 'three files for the user: ' || paths::text);
    perform pg_temp.assert(paths @> ('[{"bucket":"gist-photos","name":"' || gone || '/a.jpg"}]')::jsonb, 'gist photo found');
    perform pg_temp.assert(paths @> ('[{"bucket":"real-biz","name":"' || gone || '/shop.webp"}]')::jsonb, 'real-biz photo found');
    perform pg_temp.assert(paths @> '[{"bucket":"club-music","name":"sec-gone-own.mp3"}]'::jsonb, 'own club-music file found');
    perform pg_temp.assert(not (paths @> '[{"name":"sec-gone-used.mp3"}]'::jsonb), 'a club-music file a track still uses is kept');
    perform pg_temp.assert(not (paths @> ('[{"name":"' || keep || '/b.jpg"}]')::jsonb), 'other players'' files are not listed');
  end if;

  -- the "done" audit rows keep no dangling user
  perform bl_self_delete_done(gone, 4, '{"x":1}');
  perform bl_admin_delete_user_done(null, gone, 2, '{}');
  perform pg_temp.assert((select count(*) from admin_audit where action in ('self_delete_account_done', 'delete_user_done')
                           and target_user is null and data ->> 'user_id' = gone::text) = 2, 'done rows written with no target');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_self_delete_done(uuid,int,jsonb)', 'execute'), 'done helper is private');
  raise notice 'security 5 OK: leftovers, storage, done rows';
end $$;

-- 6. indexes and policy --------------------------------------------------------------------
do $$
declare t text; missing text := '';
begin
  foreach t in array array['money_drops_sprayer_idx', 'kids_care_log_user_id_idx', 'market_trades_buyer_id_idx', 'market_listings_buyer_id_idx',
                           'market_listings_buyer_only_idx', 'love_date_invites_from_user_idx', 'love_date_invites_to_user_idx',
                           'player_residence_landlord_id_idx', 'property_income_tenant_id_idx', 'city_party_guests_user_id_idx',
                           'weekly_earn_winners_user_id_idx'] loop
    if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = t) then missing := missing || t || ' '; end if;
  end loop;
  perform pg_temp.assert(missing = '', 'indexes missing: ' || missing);
  -- no other foreign key to auth.users / profiles is left without an index that starts with its column (profiles' own columns excepted)
  select string_agg(k.conrelid::regclass::text || '.' || a.attname, ', ') into missing
    from pg_constraint k
    join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1]
   where k.contype = 'f' and k.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass) and array_length(k.conkey, 1) = 1
     and k.connamespace = 'public'::regnamespace and k.conrelid <> 'public.profiles'::regclass
     and not exists (select 1 from pg_index i where i.indrelid = k.conrelid and i.indkey[0] = k.conkey[1]);
  perform pg_temp.assert(missing is null, 'foreign keys without an index: ' || coalesce(missing, ''));
  -- the audit log is closed to banned admins
  perform pg_temp.assert((select pg_get_expr(polqual, polrelid) from pg_policy where polname = 'admin_audit_admin'
                           and polrelid = 'public.admin_audit'::regclass) like '%banned%', 'admin_audit_admin excludes banned admins');
  raise notice 'security 6 OK: indexes and policy';
end $$;
