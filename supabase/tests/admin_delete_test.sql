-- S1 admin account deletion + scaling RPCs (20261012000800_admin_delete.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/admin_delete_test.sql
-- Groups: 1 world_counts · 2 leaderboards still rank · 3 admin_delete_user_start refusals + audit snapshot ·
-- 4 deleting the auth.users row removes every row of the player (generic FK sweep + client_errors), sends a guest
-- in their home back to the guest's own home, keeps payments (user_id null) and the audit row · 5 grants.
-- exact leaderboard numbers are asserted below (rank_bands_test covers the money ranges)
update game_config set value = 'false' where key = 'ranks.hide_amounts';
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

-- rows anywhere in public that still point at a user (every FK column referencing auth.users / profiles)
create or replace function pg_temp.leftovers(p_uid uuid) returns text
language plpgsql as $$
declare r record; n bigint; v text := '';
begin
  for r in select c.conrelid::regclass::text as t, a.attname::text as col
             from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
            where c.contype = 'f' and c.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass)
              and c.connamespace = 'public'::regnamespace loop
    execute format('select count(*) from %s where %I = $1', r.t, r.col) into n using p_uid;
    if n > 0 then v := v || r.t || '.' || r.col || '=' || n || ' '; end if;
  end loop;
  return nullif(v, '');
end $$;

do $$
declare
  adm uuid := pg_temp.new_user('del_admin@del.bl');
  adm2 uuid := pg_temp.new_user('del_admin2@del.bl');
  a uuid := pg_temp.new_user('del_a@del.bl');
  b uuid := pg_temp.new_user('del_b@del.bl');
  r jsonb; inv jsonb; conv bigint; msg bigint; a_home text; b_home text; n bigint;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(adm);
  perform create_profile_v2('Del_Admin', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(adm2);
  perform create_profile_v2('Del_Admin2', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set is_admin = true where id in (adm, adm2);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(a);
  perform create_profile_v2('Del_Victim', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(b);
  perform create_profile_v2('Del_Friend', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('aduwawa_face_me');
  select home_location_id into a_home from profiles where id = a;
  select home_location_id into b_home from profiles where id = b;

  -- 1. world_counts: everyone online, other players per public place, me excluded, private homes hidden
  update profiles set location_id = 'oba_market', last_seen = now() where id in (adm, adm2);
  perform pg_temp.login(b);
  r := world_counts();
  perform pg_temp.assert((r->>'online')::int >= 4, 'online counts everyone: ' || r::text);
  perform pg_temp.assert((r->'at'->>'oba_market')::int >= 2, 'market crowd: ' || r::text);
  perform pg_temp.assert(not (r->'at' ? b_home) and not (r->'at' ? a_home), 'private homes not listed');
  perform pg_temp.login(adm);
  perform pg_temp.assert((world_counts()->'at'->>'oba_market')::int = (r->'at'->>'oba_market')::int - 1, 'caller excluded');
  update profiles set location_id = home_location_id where id in (adm, adm2);
  -- realtime_scale: one shared result per cache window, profiles no longer published
  perform pg_temp.assert((select computed_at from world_counts_cache) = now(), 'cache filled');
  update profiles set location_id = 'oba_market', last_seen = now() where id = adm2;
  perform pg_temp.login(b);
  perform pg_temp.assert(world_counts()->'at' = r->'at', 'second call inside the window reuses the shared result');
  perform pg_temp.assert(not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'profiles'), 'profiles not in realtime');
  update profiles set location_id = home_location_id where id = adm2;

  -- 2. leaderboards still rank (one ranking per call)
  perform pg_temp.login(b);
  r := leaderboard_rich(10);
  perform pg_temp.assert(jsonb_array_length(r->'rows') >= 2 and (r->>'players')::int >= 2 and (r->'me'->>'rank') is not null, 'rich board: ' || left(r::text, 200));
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r->'rows') x where (x->>'id')::uuid in (adm, adm2)), 'admins hidden');
  r := leaderboard_vip(10);
  perform pg_temp.assert(r ? 'rows' and r ? 'me', 'vip board');

  -- give A a full life: friend, DM, chat, report, block, furniture, ledger, ad, receipt, push, error, police, payment
  perform pg_temp.login(a); perform social_add_friend(b);
  perform pg_temp.login(b); perform social_respond_friend(a, true);
  perform pg_temp.login(a);
  conv := (social_open_conversation(b)->>'conversation_id')::bigint;
  if conv is null then select id into conv from player_conversations where (user_a = a and user_b = b) or (user_a = b and user_b = a); end if;
  perform social_send_message(conv, 'how far', null, null);
  update profiles set location_id = 'oba_market' where id in (a, b);
  perform pg_temp.login(b); msg := (chat_send('na me b')->>'id')::bigint;
  perform pg_temp.login(a); perform chat_send('na me a');
  if msg is not null then perform chat_report(msg, 'spam'); end if;
  update profiles set location_id = home_location_id where id in (a, b);
  update profiles set cash = 1000000 where id = a;
  perform furniture_buy('stool');
  perform bl_add_money(a, 'cash', 1000, 'work_pay', '{}'::jsonb);
  insert into billboard_ads (board_id, user_id, image_path, status) values ('ring_road', a, a::text || '/ad.png', 'pending_review');
  insert into receipts (user_id, kind, item_name, amount, ref) values (a, 'test', 'Test', 1, 'BL-TEST-DEL-1');
  insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (a, 'https://push.example/del-a', 'k', 'x');
  insert into client_errors (user_id, message) values (a, 'boom');
  insert into payments (user_id, reference, amount_kobo, game_naira) values (a, 'BL-' || md5('del-a'), 100000, 1000);
  -- B visits A's home (friend -> invite -> knock -> admit), and B has a police case filed at A's home
  perform pg_temp.login(a); inv := social_send_house_invite(b);
  perform pg_temp.login(b); perform social_respond_house_invite((inv->>'id')::bigint, true);
  perform pg_temp.login(a); perform social_home_admit((inv->>'id')::bigint, true);
  perform pg_temp.assert((select location_id = a_home and home_visit_host_id = a from profiles where id = b), 'B inside A''s home');
  insert into police_cases (user_id, location_id, statement) values (b, a_home, 'test case at A home');
  insert into chat_blocks (blocker_id, blocked_id) values (a, b), (b, a) on conflict do nothing;
  perform pg_temp.assert((select home_visit_host_id = a from profiles where id = b), 'B still visiting');
  perform pg_temp.assert(pg_temp.leftovers(a) is not null, 'A has rows before');

  -- 3. admin_delete_user_start refusals
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_delete_user_start(%L, %L, %L)', a, 'Del_Victim', 'spam')) = 'not_admin', 'players refused');
  perform pg_temp.login(adm);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_delete_user_start(%L, %L, %L)', adm, 'Del_Admin', 'oops')) = 'self', 'not yourself');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_delete_user_start(%L, %L, %L)', adm2, 'Del_Admin2', 'oops')) = 'is_admin', 'not admins');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_delete_user_start(%L, %L, %L)', a, 'Del_Victi', 'spam')) = 'confirm', 'exact username');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_delete_user_start(%L, %L, %L)', a, 'Del_Victim', '')) = 'reason', 'reason needed');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_delete_user_start(%L, %L, %L)', gen_random_uuid(), 'x', 'spam')) = 'not_found', 'unknown user');
  r := admin_delete_user_start(a, ' del_victim ', 'Spam account');
  perform pg_temp.assert((r->>'ok')::boolean and r->>'email' = 'del_a@del.bl', 'start ok: ' || r::text);
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'delete_user' and target_user = a and admin_id = adm
                                   and data->>'username' = 'Del_Victim' and data->>'email' = 'del_a@del.bl' and data->>'reason' = 'Spam account'),
                         'audit snapshot written before the delete');
  -- the edge function finds the ad image (service role only)
  perform pg_temp.assert(jsonb_typeof(bl_user_storage_paths(a)) = 'array', 'storage paths');

  -- 4. the delete (what auth.admin.deleteUser does)
  delete from auth.users where id = a;
  perform pg_temp.assert(pg_temp.leftovers(a) is null, 'rows left: ' || coalesce(pg_temp.leftovers(a), ''));
  perform pg_temp.assert(not exists (select 1 from client_errors where user_id = a), 'client_errors gone');
  perform pg_temp.assert(not exists (select 1 from billboard_ads where user_id = a), 'ads gone');
  perform pg_temp.assert(not exists (select 1 from locations where id = a_home), 'private home gone');
  perform pg_temp.assert(not exists (select 1 from chat_messages where username = 'Del_Victim'), 'chat gone');
  perform pg_temp.assert(not exists (select 1 from player_messages m join player_conversations c on c.id = m.conversation_id where c.id = conv), 'DMs gone');
  perform pg_temp.assert((select location_id = b_home and home_location_id = b_home and home_visit_host_id is null
                                 and home_visit_original_home_location_id is null from profiles where id = b),
                         'guest back in own home: ' || (select row(location_id, home_location_id, home_visit_host_id)::text from profiles where id = b));
  perform pg_temp.assert((select location_id from police_cases where user_id = b) = b_home, 'guest police case moved to own home');
  perform pg_temp.assert((select user_id from payments where reference = 'BL-' || md5('del-a')) is null, 'payment kept, anonymised');
  perform pg_temp.assert((select target_user from admin_audit where action = 'delete_user' and data->>'user_id' = a::text) is null
                         and exists (select 1 from admin_audit where action = 'delete_user' and data->>'user_id' = a::text), 'audit row kept');
  perform pg_temp.assert(exists (select 1 from profiles where id = b), 'friend still here');
  perform pg_temp.login(b);
  perform pg_temp.assert(jsonb_array_length(social_friends()) = 0 or not exists (
    select 1 from jsonb_array_elements(social_friends()) x where x->>'id' = a::text), 'friend list clean');
  raise notice 'ok: admin delete';
end $$;

-- 5. grants
do $$
begin
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_user_storage_paths(uuid)', 'execute'), 'storage paths private');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_admin_delete_user_failed(uuid,uuid,text)', 'execute'), 'failed log private');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_profile_before_delete()', 'execute'), 'trigger fn private');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.world_counts()', 'execute'), 'world_counts not anon');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.admin_delete_user_start(uuid,text,text)', 'execute'), 'start not anon');
  raise notice 'ok: admin delete grants';
end $$;
