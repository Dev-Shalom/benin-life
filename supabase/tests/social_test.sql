-- Social features: private friends, direct messages, invitations, knocks and host admission.
-- Run with:
--   bash scripts/sql-test.sh supabase/migrations/20261008000200_chat_new_sims_can_send.sql \
--     supabase/tests/fixtures/social_legacy_home.sql \
--     supabase/migrations/20261008000300_friends_messages_visits.sql -- supabase/tests/social_test.sql

create or replace function pg_temp.s_make(p_name text, p_home text default 'ekenwan_face_me') returns uuid
language plpgsql as $$
declare v_uid uuid := pg_temp.new_user(lower(p_name) || '@social.bl');
begin
  perform pg_temp.login(v_uid);
  update public.game_config set value = '""' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform public.create_profile_v2(p_name, 'female', '{"gender":"female"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform public.choose_start_home(p_home);
  update public.profiles set created_at = bl_now() - interval '1 day' where id = v_uid;
  perform set_config('socialtest.' || lower(p_name), v_uid::text, true);
  return v_uid;
end $$;

create or replace function pg_temp.s_u(p_name text) returns uuid
language sql as $$ select current_setting('socialtest.' || lower(p_name))::uuid $$;

create or replace function pg_temp.s_hint(p_sql text, p_hint text) returns text
language plpgsql as $$
declare v_h text; v_m text;
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
    get stacked diagnostics v_h = pg_exception_hint, v_m = message_text;
    if v_h is distinct from p_hint then
      raise exception 'TEST FAILED: [%] expected hint "%", got "%" (%)', p_sql, p_hint, v_h, sqlerrm;
    end if;
    return v_m;
  end;
  raise exception 'TEST FAILED: [%] expected hint "%" but it succeeded', p_sql, p_hint;
end $$;

do $$
declare
  a uuid := pg_temp.s_make('SocialAda', 'ekenwan_face_me');
  b uuid := pg_temp.s_make('SocialBen', 'uselu_self_contain');
  c uuid := pg_temp.s_make('SocialCy', 'aduwawa_face_me');
  d uuid := pg_temp.s_make('SocialDee', 'uniben_hostel');
  legacy uuid := current_setting('socialtest.legacy_uid')::uuid;
  r jsonb; conv bigint; invite_a bigint; invite_c bigint; invite_d bigint;
  a_home text; b_home text; audio_path text;
begin
  perform pg_temp.assert((select location_id = 'home_' || replace(legacy::text, '-', '')
                                  and home_location_id = location_id
                            from public.profiles where id = legacy),
                         'migration moves existing residents into private home instances');
  -- Every player gets an individual home location, even when using the same home template.
  select home_location_id into a_home from public.profiles where id = a;
  select home_location_id into b_home from public.profiles where id = b;
  perform set_config('socialtest.owner_home', a_home, true);
  perform pg_temp.assert(a_home like 'home_%' and b_home like 'home_%' and a_home <> b_home,
                         'homes are private player-specific locations');
  perform pg_temp.assert((select not active and private_home_owner_id = a from public.locations where id = a_home),
                         'private home is hidden from the public map and owned by its player');
  perform pg_temp.assert((select not active from public.locations where id = 'ekenwan_room'),
                         'shared home template is no longer a public destination');

  -- Friendship must be accepted before messaging or sending house invitations.
  perform pg_temp.login(a);
  r := public.social_add_friend(b);
  perform pg_temp.assert(r->>'status' = 'outgoing', 'friend request sent');
  perform pg_temp.s_hint(format('select social_open_conversation(%L)', b), 'not_friend');
  perform pg_temp.login(b);
  r := public.social_respond_friend(a, true);
  perform pg_temp.assert(r->>'status' = 'friend', 'friend request accepted');

  perform pg_temp.login(a);
  r := public.social_open_conversation(b);
  conv := (r->>'id')::bigint;
  r := public.social_send_message(conv, 'Oya, see you at home later.');
  perform pg_temp.assert(r->>'body' = 'Oya, see you at home later.', 'private text message sends');
  perform pg_temp.login(b);
  r := public.social_message_history(conv, null, 20);
  perform pg_temp.assert(jsonb_array_length(r) = 1 and r->0->>'sender_username' = 'SocialAda',
                         'friend can read conversation history');
  perform pg_temp.assert((select at_home from jsonb_to_recordset(public.social_friends()) as x(id uuid, at_home boolean) where id = a),
                         'friends list reports presence without exposing private home ids');

  -- Voice rows remain private and share the accepted-friend authorization boundary.
  audio_path := conv::text || '/' || a::text || '/voice-test-123.webm';
  insert into storage.objects (bucket_id, name) values ('player-voice', audio_path);
  perform pg_temp.login(a);
  r := public.social_send_message(conv, null, audio_path, 'audio/webm');
  perform pg_temp.login(b);
  r := public.social_message_history(conv, null, 20);
  perform pg_temp.assert(jsonb_array_length(r) = 2 and r->1->>'audio_path' = audio_path,
                         'friend can read a voice message');
  perform pg_temp.login(c);
  perform pg_temp.s_hint(format('select social_message_history(%s, null, 20)', conv), 'not_friend');
  perform pg_temp.assert((select not public from storage.buckets where id = 'player-voice'),
                         'voice bucket is private');
  perform pg_temp.assert((select file_size_limit is null from storage.buckets where id = 'player-voice'),
                         'voice bucket has no application-configured upload size limit');

  -- The invitee first accepts and knocks. The host receives a named event but cannot admit remotely.
  perform pg_temp.login(a);
  update public.profiles set location_id = 'oba_market' where id = a;
  r := public.social_send_house_invite(b); invite_a := (r->>'id')::bigint;
  perform pg_temp.login(b);
  r := public.social_respond_house_invite(invite_a, true);
  perform pg_temp.assert(r->>'status' = 'knocking', 'accepting an invite creates a door knock');
  perform pg_temp.assert(exists (select 1 from public.events where user_id = a and kind = 'house_knock'
                                  and title like '%SocialBen%'), 'host is notified by the guest username');
  perform pg_temp.login(a);
  perform pg_temp.s_hint(format('select social_home_admit(%s, true)', invite_a), 'host_not_home');
  perform pg_temp.assert((select status = 'knocking' from public.player_house_invites where id = invite_a),
                         'failed remote admission leaves the guest waiting outside');

  -- A non-invited player cannot travel to the private address; the owner can host multiple guests.
  perform pg_temp.login(c);
  perform pg_temp.s_hint(format('select travel_quote(%L)', a_home), 'private_home');
  perform pg_temp.s_hint(format('select players_here(%L)', a_home), 'private_home');
  perform pg_temp.login(a);
  update public.profiles set location_id = a_home where id = a;
  r := public.social_home_admit(invite_a, true);
  perform pg_temp.assert(r->>'status' = 'admitted', 'host admits guest while physically home');
  perform pg_temp.assert((select location_id = a_home and housing_id = (select housing_id from public.profiles where id = a)
                           and home_visit_host_id = a from public.profiles where id = b),
                         'guest enters the host home and temporarily uses the host layout');
  perform pg_temp.login(c);
  perform pg_temp.assert(not public.bl_social_can_view_private_home(a_home, a), 'outsiders cannot view the private home record');
  perform pg_temp.login(a);
  perform pg_temp.assert(public.bl_social_can_view_private_home(a_home, a), 'home owner can view the private home record');
  perform pg_temp.login(b);
  perform pg_temp.assert(public.bl_social_can_view_private_home(a_home, a), 'admitted guest can view the private home record');

  perform pg_temp.login(a);
  r := public.social_add_friend(c);
  perform pg_temp.login(c);
  perform public.social_respond_friend(a, true);
  perform pg_temp.login(a);
  r := public.social_add_friend(d);
  perform pg_temp.login(d);
  perform public.social_respond_friend(a, true);
  perform pg_temp.login(a);
  invite_c := (public.social_send_house_invite(c)->>'id')::bigint;
  invite_d := (public.social_send_house_invite(d)->>'id')::bigint;
  perform pg_temp.assert(invite_c <> invite_d and
                         (select count(*) = 2 from public.player_house_invites
                           where host_id = a and status = 'invited'),
                         'host can have multiple guests invited at once');

  -- Leaving the visit restores the guest's own home and housing layout.
  update public.profiles set location_id = 'oba_market' where id = b;
  perform pg_temp.assert((select location_id = 'oba_market' and housing_id = 'self_contain_uselu'
                            and home_visit_host_id is null and home_visit_original_housing_id is null
                           from public.profiles where id = b),
                         'leaving a visit restores the guest home: ' || (select to_jsonb(p)::text from public.profiles p where p.id = b));
end $$;

-- Verify the actual map-location row policy as authenticated players, not only its helper function.
set local role authenticated;
select pg_temp.login(pg_temp.s_u('SocialCy'));
select pg_temp.assert(not exists (select 1 from public.locations where id = current_setting('socialtest.owner_home')),
                      'RLS hides another player home from map queries');
select pg_temp.login(pg_temp.s_u('SocialAda'));
select pg_temp.assert(exists (select 1 from public.locations where id = current_setting('socialtest.owner_home')),
                      'RLS lets the owner load their own map home');
select pg_temp.login(pg_temp.s_u('SocialBen'));
select pg_temp.assert(not exists (select 1 from public.locations where id = current_setting('socialtest.owner_home')),
                      'RLS removes home access after the guest leaves');
reset role;

select pg_temp.assert(not has_table_privilege('authenticated', 'public.player_friendships', 'insert'), 'friendship writes are RPC-only');
select pg_temp.assert(not has_table_privilege('authenticated', 'public.player_messages', 'insert'), 'message writes are RPC-only');
select pg_temp.assert(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'player_messages'),
                      'direct messages are available over Realtime');
select pg_temp.assert(has_function_privilege('authenticated', 'public.social_home_admit(bigint,boolean)', 'execute'),
                      'host admission RPC is available to players');
select pg_temp.assert(not has_function_privilege('anon', 'public.social_home_admit(bigint,boolean)', 'execute'),
                      'anonymous clients cannot admit guests');
