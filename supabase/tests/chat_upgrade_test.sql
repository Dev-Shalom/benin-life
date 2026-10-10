-- M3 messaging upgrade (20261010000300_chat_upgrade.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/chat_upgrade_test.sql
-- Covers place chat and DMs: reply_to stored + returned with a quote preview; delete for everyone is
-- author-only, inside chat.delete_everyone_hours, and tombstones the body; delete for me hides for me only;
-- history paging (before-id + limit) stops at 14 days.
do $$
declare a uuid := pg_temp.new_user('cu_a@chat.bl'); b uuid := pg_temp.new_user('cu_b@chat.bl');
        r jsonb; m1 bigint; m2 bigint; old_id bigint; conv bigint; d1 bigint; d2 bigint; err text; rows jsonb;
begin
  update game_config set value = '0' where key in ('chat.rate_seconds', 'chat.duplicate_window_seconds', 'chat.min_account_real_minutes');
  update game_config set value = '100' where key = 'chat.burst_per_minute';
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(a);
  perform create_profile_v2('Cu_Alpha', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(b);
  perform create_profile_v2('Cu_Bravo', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set location_id = 'oba_market', travel_to = null where id in (a, b);

  -- 1. reply_to stored and returned (place chat)
  perform pg_temp.login(a);
  m1 := (chat_send('cu hello market')->>'id')::bigint;
  perform pg_temp.login(b);
  r := chat_send('cu hi back', m1);
  m2 := (r->>'id')::bigint;
  perform pg_temp.assert((r->>'reply_to')::bigint = m1, 'reply_to returned by chat_send');
  perform pg_temp.assert(r->'reply'->>'username' = 'Cu_Alpha' and r->'reply'->>'snippet' = 'cu hello market', 'reply preview: ' || (r->'reply')::text);
  perform pg_temp.assert((select reply_to from chat_messages where id = m2) = m1, 'reply_to stored');
  rows := chat_history('oba_market', null, 10);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(rows) e where (e->>'id')::bigint = m2 and (e->>'reply_to')::bigint = m1), 'reply_to in history');
  begin perform chat_send('cu bad reply', -1); err := null; exception when others then err := sqlerrm; end;
  perform pg_temp.assert(err is not null, 'reply to unknown message refused');

  -- 2. only the author can delete for everyone
  begin perform chat_delete_for_everyone('place', m1); err := null; exception when others then err := sqlerrm; end;
  perform pg_temp.assert(err like 'You can only delete your own%', 'non-author refused: ' || coalesce(err, 'none'));

  -- 3. the window (chat.delete_everyone_hours, 48)
  perform pg_temp.login(a);
  update chat_messages set created_at = now() - interval '49 hours' where id = m1;
  begin perform chat_delete_for_everyone('place', m1); err := null; exception when others then err := sqlerrm; end;
  perform pg_temp.assert(err like 'Too late%', 'outside window refused: ' || coalesce(err, 'none'));
  update chat_messages set created_at = now() - interval '1 hour' where id = m1;

  -- 4. tombstone clears the body; replies show a deleted quote
  r := chat_delete_for_everyone('place', m1);
  perform pg_temp.assert((select deleted_at is not null and body is null and audio_path is null from chat_messages where id = m1), 'tombstone');
  rows := chat_history('oba_market', null, 10);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(rows) e where (e->>'id')::bigint = m1 and e->>'deleted_at' is not null and e->'body' = 'null'::jsonb), 'tombstone visible to all');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(rows) e where (e->>'id')::bigint = m2 and (e->'reply'->>'deleted')::boolean), 'quote marked deleted');
  begin perform chat_send('cu reply to deleted', m1); err := null; exception when others then err := sqlerrm; end;
  perform pg_temp.assert(err is not null, 'cannot reply to a deleted message');

  -- 5. delete for me hides for me only
  perform chat_delete_for_me('place', m2);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(chat_history('oba_market', null, 10)) e where (e->>'id')::bigint = m2), 'hidden for me');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(chat_recent('oba_market', 30)) e where (e->>'id')::bigint = m2), 'hidden for me (recent)');
  perform pg_temp.login(b);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(chat_history('oba_market', null, 10)) e where (e->>'id')::bigint = m2), 'still visible to the other player');

  -- 6. place history paging stops at 14 days
  insert into chat_messages (location_id, user_id, username, body, created_at) values ('oba_market', a, 'Cu_Alpha', 'cu ancient', now() - interval '15 days') returning id into old_id;
  insert into chat_messages (location_id, user_id, username, body, created_at) values ('oba_market', a, 'Cu_Alpha', 'cu recent-ish', now() - interval '13 days');
  rows := chat_history('oba_market', null, 60);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(rows) e where e->>'body' = 'cu recent-ish'), '13 days old is in history');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(rows) e where (e->>'id')::bigint = old_id), '15 days old is not');
  perform pg_temp.assert(jsonb_array_length(chat_history('oba_market', m2, 1)) = 1, 'limit respected');

  -- DMs: friends, reply, delete, paging
  perform pg_temp.login(a); perform social_add_friend(b);
  perform pg_temp.login(b); perform social_respond_friend(a, true);
  conv := (social_open_conversation(a)->>'id')::bigint;
  d1 := (social_send_message(conv, 'cu dm one')->>'id')::bigint;
  perform pg_temp.login(a);
  r := social_send_message(conv, 'cu dm reply', null, null, d1);
  d2 := (r->>'id')::bigint;
  perform pg_temp.assert((r->>'reply_to')::bigint = d1 and r->'reply'->>'username' = 'Cu_Bravo', 'dm reply returned: ' || r::text);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(social_message_history(conv, null, 50)) e
                                  where (e->>'id')::bigint = d2 and e->'reply'->>'snippet' = 'cu dm one'), 'dm reply in history');
  begin perform chat_delete_for_everyone('dm', d1); err := null; exception when others then err := sqlerrm; end;
  perform pg_temp.assert(err like 'You can only delete your own%', 'dm non-author refused');
  perform chat_delete_for_everyone('dm', d2);
  perform pg_temp.assert((select deleted_at is not null and body is null from player_messages where id = d2), 'dm tombstone');
  perform chat_delete_for_me('dm', d1);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(social_message_history(conv, null, 50)) e where (e->>'id')::bigint = d1), 'dm hidden for me');
  perform pg_temp.login(b);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(social_message_history(conv, null, 50)) e where (e->>'id')::bigint = d1), 'dm visible to friend');
  update player_messages set created_at = now() - interval '15 days' where id = d1;
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(social_message_history(conv, null, 50)) e where (e->>'id')::bigint = d1), 'dm history stops at 14 days');
  -- a stranger can't hide or delete DMs
  perform pg_temp.login(pg_temp.new_user('cu_c@chat.bl'));
  begin perform chat_delete_for_me('dm', d2); err := null; exception when others then err := sqlerrm; end;
  perform pg_temp.assert(err is not null, 'stranger refused');

  -- retention default is now 14 days
  perform pg_temp.assert((select value::numeric from game_config where key = 'chat.retention_hours') >= 336 or
                         (select value::numeric from game_config where key = 'chat.retention_hours') <> 48, 'retention not the old 48 h default');
  raise notice 'ok: chat upgrade';
end $$;
