-- M4 Messages v2 (20261010000500_messages_v2.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/messages_v2_test.sql
-- Groups: 1 streak counts consecutive both-sided WAT days, one-sided days don't count, resets after a gap ·
-- 2 a house visit marks both sides · 3 read receipts set when the other player reads · 4 only participants
-- read a pair's streak (outsiders get their own empty pair, the table is closed to clients) · 5 news keys.
do $$
declare a uuid := pg_temp.new_user('m4_a@social.bl'); b uuid := pg_temp.new_user('m4_b@social.bl');
        c uuid := pg_temp.new_user('m4_c@social.bl'); conv bigint; msg jsonb; s jsonb; inv jsonb; m text;
        day_s int := 86400;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(a);
  perform create_profile_v2('M4_Ada', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(b);
  perform create_profile_v2('M4_Bayo', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(c);
  perform create_profile_v2('M4_Chi', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');

  perform pg_temp.login(a); perform social_add_friend(b);
  perform pg_temp.login(b); perform social_respond_friend(a, true);
  perform pg_temp.login(a); conv := (social_open_conversation(b)->>'id')::bigint;

  -- 1. no streak yet
  s := social_streak(b);
  perform pg_temp.assert((s->>'streak')::int = 0, 'no streak yet: ' || s::text);

  -- days -6 and -5 both-sided (old run), -4 nobody (gap), -3 only Ada, -2 / -1 / today both-sided
  perform set_config('bl.test_offset_seconds', (-6 * day_s)::text, true);
  perform pg_temp.login(a); perform social_send_message(conv, 'day -6 a', null, null, null);
  perform pg_temp.login(b); perform social_send_message(conv, 'day -6 b', null, null, null);
  perform set_config('bl.test_offset_seconds', (-5 * day_s)::text, true);
  perform pg_temp.login(a); perform social_send_message(conv, 'day -5 a', null, null, null);
  perform pg_temp.login(b); perform social_send_message(conv, 'day -5 b', null, null, null);
  perform set_config('bl.test_offset_seconds', (-3 * day_s)::text, true);
  perform pg_temp.login(a); perform social_send_message(conv, 'day -3 a only', null, null, null);
  perform set_config('bl.test_offset_seconds', (-2 * day_s)::text, true);
  perform pg_temp.login(a); perform social_send_message(conv, 'day -2 a', null, null, null);
  perform pg_temp.login(b); perform social_send_message(conv, 'day -2 b', null, null, null);
  perform set_config('bl.test_offset_seconds', (-1 * day_s)::text, true);
  perform pg_temp.login(a); perform social_send_message(conv, 'day -1 a', null, null, null);
  perform pg_temp.login(b); perform social_send_message(conv, 'day -1 b', null, null, null);
  perform set_config('bl.test_offset_seconds', '0', true);

  -- ending yesterday still counts: -2, -1 = 2
  perform pg_temp.login(a); s := social_streak(b);
  perform pg_temp.assert((s->>'streak')::int = 2, 'streak ending yesterday = 2: ' || s::text);
  perform pg_temp.assert(not (s->>'today_me')::boolean and not (s->>'today_them')::boolean, 'nothing today yet');

  -- today only Ada: still 2 (one-sided day does not count yet)
  perform social_send_message(conv, 'today a', null, null, null);
  s := social_streak(b);
  perform pg_temp.assert((s->>'streak')::int = 2 and (s->>'today_me')::boolean and not (s->>'today_them')::boolean,
                         'one-sided today keeps 2: ' || s::text);
  -- Bayo replies: 3, and Bayo sees the same streak
  perform pg_temp.login(b); msg := social_send_message(conv, 'today b', null, null, null);
  s := social_streak(a);
  perform pg_temp.assert((s->>'streak')::int = 3, 'both today = 3 for Bayo: ' || s::text);

  -- reset after a gap: two days with no activity -> 0
  perform set_config('bl.test_offset_seconds', (2 * day_s)::text, true);
  s := social_streak(a);
  perform pg_temp.assert((s->>'streak')::int = 0, 'gap resets streak: ' || s::text);
  perform set_config('bl.test_offset_seconds', '0', true);

  -- 2. a house visit marks both sides (Chi and Ada never messaged)
  perform pg_temp.login(c); perform social_add_friend(a);
  perform pg_temp.login(a); perform social_respond_friend(c, true);
  perform pg_temp.login(a); inv := social_send_house_invite(c);
  perform pg_temp.login(c); perform social_respond_house_invite((inv->>'id')::bigint, true);
  perform pg_temp.login(a); perform social_home_admit((inv->>'id')::bigint, true);
  s := social_streak(c);
  perform pg_temp.assert((s->>'streak')::int = 1 and (s->>'today_them')::boolean, 'house visit = 1-day streak: ' || s::text);

  -- 3. read receipts: Bayo's last message is unread until Ada reads
  perform pg_temp.assert((select read_at is null from player_messages where id = (msg->>'id')::bigint), 'unread before');
  perform pg_temp.login(a); perform social_mark_messages_read(conv);
  perform pg_temp.assert((select read_at is not null from player_messages where id = (msg->>'id')::bigint), 'read_at set when Ada reads');
  perform pg_temp.assert((select count(*) = 0 from player_messages where conversation_id = conv and sender_id = a and read_at is not null),
                         'reading does not mark my own messages');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(social_friends()) f
                                  where f->>'id' = b::text and (f->>'unread')::int = 0 and f ? 'last_voice' and f ? 'last_deleted'),
                         'social_friends unread 0 with preview flags');

  -- 4. only participants: Chi asking about Bayo sees her own (empty) pair, not Ada-Bayo's 3 days; table closed
  perform pg_temp.login(c); s := social_streak(b);
  perform pg_temp.assert((s->>'streak')::int = 0, 'outsider sees no streak: ' || s::text);
  begin perform social_streak(c); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m is not null, 'cannot ask about yourself');
  set local role authenticated;
  begin perform count(*) from social_streak_days; m := null; exception when insufficient_privilege then m := 'denied'; end;
  reset role;
  perform pg_temp.assert(m = 'denied', 'streak table is closed to clients');

  -- 5. news keys
  perform pg_temp.assert((select count(*) = 2 from game_config where key in ('news.latest_title', 'news.latest_body') and kind = 'text'), 'news keys');
  raise notice 'ok: messages v2';
end $$;
