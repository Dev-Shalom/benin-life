-- P1 player push (20261017000300_player_push.sql, docs/NOTIFICATIONS.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/player_push_test.sql
-- Groups: 0 grants + RLS flags · 1 prefs (defaults, set, refused input, anon) · 2 devices (subscribe, cap of 8, unsubscribe) ·
-- 3 DM enqueue (title/body/url, voice, no self-push, no device = nothing) · 4 rate limit + collapse ("3 new messages") ·
-- 5 master off, category off, global off, active player skipped, blocked sender · 6 money (transfer, tip without the note) ·
-- 7 friends + broadcast (admin category, defaults off) · 8 house chat · 9 claim / tick / hourly cap / stuck rows ·
-- 10 RLS (outbox closed, prefs own row only) · 11 admin_push_stats.
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

create or replace function pg_temp.denied(p_sql text) returns boolean
language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then
  return true;
when others then
  return false;
end $$;

create or replace function pg_temp.pp_make(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@pp.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  -- the daily-story push (after 17:00 Benin time) would queue its own rows and skew the counts below
  update game_config set value = 'false' where key = 'stories.push_enabled';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'female', '{"gender":"female"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  update profiles set last_seen = now() - interval '1 hour', transfer_trusted = true, bank = 100000, cash = 5000 where id = v;
  return v;
end $$;

-- a transfer_in ledger row (bank_transfer itself is rate limited to one per 15 s)
create or replace function pg_temp.pay(p_user uuid, p_amount bigint) returns void
language plpgsql as $$
begin
  insert into ledger (user_id, account, delta, balance_after, reason, meta)
  values (p_user, 'bank', p_amount, 1, 'transfer_in', '{"from_username":"PpAda"}');
end $$;

-- push_outbox rows for a user (optionally filtered by an extra SQL condition)
create or replace function pg_temp.cnt(p_user uuid, p_cond text default 'true') returns int
language plpgsql as $$
declare n int;
begin
  execute format('select count(*) from push_outbox where user_id = %L and (%s)', p_user, p_cond) into n;
  return n;
end $$;

create or replace function pg_temp.sub(p_user uuid, p_n int default 1) returns void
language plpgsql as $$
begin
  insert into push_subscriptions (user_id, endpoint, p256dh, auth)
  values (p_user, 'https://push.example.test/' || p_user || '/' || p_n, repeat('A', 87), repeat('B', 22));
end $$;

do $$
declare
  a uuid; b uuid; c uuid; adm uuid;
  conv bigint; r jsonb; v_id bigint;
begin
  a := pg_temp.pp_make('PpAda'); b := pg_temp.pp_make('PpBayo'); c := pg_temp.pp_make('PpChi'); adm := pg_temp.pp_make('PpAdmin');
  update profiles set is_admin = true where id = adm;
  perform set_config('pp.a', a::text, true); perform set_config('pp.b', b::text, true);
  perform set_config('pp.c', c::text, true); perform set_config('pp.adm', adm::text, true);
  perform pg_temp.login(a); perform social_add_friend(b);
  perform pg_temp.login(b); perform social_respond_friend(a, true);
  perform pg_temp.login(a); conv := (social_open_conversation(b)->>'id')::bigint;
  perform set_config('pp.conv', conv::text, true);
  delete from push_outbox;   -- the friend request above may have queued rows for a real DB's pushes: start clean
end $$;

-- ---------- 0. grants + flags ----------
do $$
declare r record; k text;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'bl\_push\_%' loop
    perform pg_temp.assert(not has_function_privilege('authenticated', r.sig, 'execute')
                           and not has_function_privilege('anon', r.sig, 'execute'), 'helper private: ' || r.sig::text);
  end loop;
  foreach k in array array['bl_push_tick()', 'bl_push_claim(integer)'] loop
    perform pg_temp.assert(has_function_privilege('service_role', ('public.' || k)::regprocedure, 'execute'), 'service role runs ' || k);
  end loop;
  foreach k in array array['push_state()', 'push_prefs_set(jsonb)', 'push_subscribe(text,text,text,text)', 'push_unsubscribe(text)', 'admin_push_stats()'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || k)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || k)::regprocedure, 'execute'), 'granted to players only: ' || k);
    perform pg_temp.assert((select prosecdef and proconfig @> array['search_path=public'] from pg_proc
                             where oid = ('public.' || k)::regprocedure), 'definer + search_path ' || k);
  end loop;
  foreach k in array array['push_prefs', 'push_outbox'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || k)::regclass), 'RLS on ' || k);
  end loop;
  perform pg_temp.assert((select count(*) from game_config where category = 'push') >= 12, 'push settings seeded');
  raise notice 'ok 0: grants and flags';
end $$;

-- ---------- 1. prefs ----------
do $$
declare a uuid := current_setting('pp.a')::uuid; s jsonb;
begin
  perform pg_temp.login(a);
  s := push_state();
  perform pg_temp.assert((s->>'master')::boolean and (s->>'messages')::boolean and (s->>'money')::boolean and (s->>'friends')::boolean
                         and not (s->>'events')::boolean and not (s->>'admin')::boolean, 'defaults: on / on / on / on / off / off: ' || s::text);
  perform pg_temp.assert((s->'global'->>'enabled')::boolean and (s->>'devices')::int = 0, 'global on, no device yet');
  s := push_prefs_set('{"events": true, "messages": false}');
  perform pg_temp.assert((s->>'events')::boolean and not (s->>'messages')::boolean and (s->>'money')::boolean, 'partial update: ' || s::text);
  perform pg_temp.assert(not (push_prefs_set('{"master": false}')->>'master')::boolean, 'master off saved');
  perform push_prefs_set('{"master": true, "messages": true, "events": false}');
  perform pg_temp.assert(pg_temp.hint_of($q$select push_prefs_set('{"spam": true}')$q$) = 'bad_value', 'unknown key refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select push_prefs_set('{"money": "yes"}')$q$) = 'bad_value', 'non-boolean refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select push_prefs_set('[1]')$q$) = 'bad_value', 'non-object refused');
  raise notice 'ok 1: prefs';
end $$;
set local role anon;
select set_config('request.jwt.claims', '', true), set_config('request.jwt.claim.sub', '', true);
do $$ begin
  perform pg_temp.assert(pg_temp.hint_of('select push_state()') <> 'ok', 'anon cannot read prefs');
  perform pg_temp.assert(pg_temp.hint_of($q$select push_prefs_set('{"master": false}')$q$) <> 'ok', 'anon cannot set prefs');
end $$;
reset role;

-- ---------- 2. devices ----------
do $$
declare a uuid := current_setting('pp.a')::uuid; s jsonb; i int;
begin
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of($q$select push_subscribe('http://insecure.test/x1234567', repeat('A', 87), repeat('B', 22))$q$) = 'bad_value', 'http endpoint refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select push_subscribe('https://push.example.test/abcdefg', 'short', repeat('B', 22))$q$) = 'bad_value', 'bad key refused');
  s := push_subscribe('https://push.example.test/dev-1', repeat('A', 87), repeat('B', 22), 'UA test');
  perform pg_temp.assert((s->>'devices')::int = 1, 'one device');
  s := push_subscribe('https://push.example.test/dev-1', repeat('A', 87), repeat('B', 22), 'UA test');
  perform pg_temp.assert((s->>'devices')::int = 1, 'same endpoint is not doubled');
  for i in 2..10 loop perform push_subscribe('https://push.example.test/dev-' || i, repeat('A', 87), repeat('B', 22), 'UA'); end loop;
  perform pg_temp.assert((push_state()->>'devices')::int = 8, 'at most 8 devices');
  perform pg_temp.assert(not exists (select 1 from push_subscriptions where endpoint = 'https://push.example.test/dev-1'), 'oldest device dropped');
  s := push_unsubscribe('https://push.example.test/dev-10');
  perform pg_temp.assert((s->>'devices')::int = 7, 'unsubscribe removes one');
  -- somebody else's endpoint cannot be removed by me
  perform pg_temp.login(current_setting('pp.b')::uuid);
  perform push_unsubscribe('https://push.example.test/dev-9');
  perform pg_temp.assert(exists (select 1 from push_subscriptions where endpoint = 'https://push.example.test/dev-9'), 'cannot remove another player''s device');
  -- keep one tidy device each for the next groups
  delete from push_subscriptions where user_id = a;
  raise notice 'ok 2: devices';
end $$;

-- ---------- 3. DM enqueue ----------
do $$
declare a uuid := current_setting('pp.a')::uuid; b uuid := current_setting('pp.b')::uuid; conv bigint := current_setting('pp.conv')::bigint;
        row push_outbox;
begin
  -- B has no device: nothing is queued
  perform pg_temp.login(a); perform social_send_message(conv, 'hello with no device', null, null, null);
  perform pg_temp.assert(pg_temp.cnt(b) = 0, 'no device = no row');
  perform pg_temp.sub(a); perform pg_temp.sub(b);
  perform pg_temp.login(a);
  perform social_send_message(conv, E'Oya   come\nchop, I get jollof rice and plenty chicken for house now now now o, hurry before e finish', null, null, null);
  select * into row from push_outbox where user_id = b;
  perform pg_temp.assert(row.id is not null and row.category = 'messages' and row.kind = 'dm', 'B got a messages push');
  perform pg_temp.assert(row.title = '@PpAda', 'title is @sender: ' || row.title);
  perform pg_temp.assert(row.body like 'Oya come chop, I get jollof rice and plenty chicken for h%…' and char_length(row.body) <= 61, 'body is the first 60 chars on one line: ' || row.body);
  perform pg_temp.assert(row.url = '/play?go=dm:' || conv and row.status = 'pending' and row.send_after <= now(), 'deep link to the chat, due now: ' || row.url);
  perform pg_temp.assert(row.group_key = 'dm:' || conv and row.tag = row.group_key, 'tag = chat key (one notification per chat on the phone)');
  -- never push the sender
  perform pg_temp.assert(pg_temp.cnt(a) = 0, 'no self-push (sender has a device too)');
  perform pg_temp.login(b); perform social_send_message(conv, 'reply', null, null, null);
  perform pg_temp.assert(pg_temp.cnt(b) = 1 and pg_temp.cnt(a) = 1, 'the reply pushes A, not B');
  delete from push_outbox;
  -- voice note: no body, no content
  insert into player_messages (conversation_id, sender_id, body, audio_path, audio_mime) values (conv, a, null, 'x/y.webm', 'audio/webm');
  select * into row from push_outbox where user_id = b;
  perform pg_temp.assert(row.body = '🎤 Voice note', 'voice note text: ' || coalesce(row.body, 'null'));
  raise notice 'ok 3: DM enqueue';
end $$;

-- ---------- 4. rate limit + collapse ----------
do $$
declare a uuid := current_setting('pp.a')::uuid; b uuid := current_setting('pp.b')::uuid; conv bigint := current_setting('pp.conv')::bigint;
        row push_outbox; n int;
begin
  delete from push_outbox;
  perform pg_temp.login(a);
  perform social_send_message(conv, 'one', null, null, null);
  perform social_send_message(conv, 'two', null, null, null);
  perform social_send_message(conv, 'three', null, null, null);
  perform pg_temp.assert(pg_temp.cnt(b) = 1, 'three quick messages = one row');
  select * into row from push_outbox where user_id = b;
  perform pg_temp.assert(row.count = 3 and row.title = '3 new messages from @PpAda' and row.body = 'three', 'bundled: ' || row.title || ' / ' || row.body);
  -- send it
  select count(*) into n from bl_push_claim(10);
  perform pg_temp.assert(n = 1, 'claimed once');
  perform pg_temp.assert((select status from push_outbox where id = row.id) = 'sending', 'row is sending');
  perform pg_temp.assert((select count(*) from bl_push_claim(10)) = 0, 'a claimed row is never handed out twice');
  update push_outbox set status = 'sent', sent_at = now() where id = row.id;
  -- a new message inside the 2-minute window waits for the window to end
  perform social_send_message(conv, 'four', null, null, null);
  select * into row from push_outbox where user_id = b and status = 'pending';
  perform pg_temp.assert(row.id is not null and row.send_after > now() + interval '100 seconds' and row.send_after <= now() + interval '121 seconds',
                         'second push waits ~2 min: ' || row.send_after::text);
  perform pg_temp.assert((select count(*) from bl_push_claim(10)) = 0, 'not due yet: nothing to send');
  perform social_send_message(conv, 'five', null, null, null);
  perform social_send_message(conv, 'six', null, null, null);
  select * into row from push_outbox where user_id = b and status = 'pending';
  perform pg_temp.assert(pg_temp.cnt(b, 'status = ''pending''') = 1 and row.count = 3 and row.title = '3 new messages from @PpAda' and row.body = 'six',
                         'later messages join the waiting push');
  -- the window is over: it is sent as one
  update push_outbox set send_after = now() - interval '1 second' where id = row.id;
  perform pg_temp.assert((select count(*) from bl_push_claim(10)) = 1, 'due now');
  -- the window is configurable
  update push_outbox set status = 'sent', sent_at = now() where id = row.id;
  update game_config set value = '0' where key = 'push.convo_window_seconds';
  perform social_send_message(conv, 'seven', null, null, null);
  select * into row from push_outbox where user_id = b and status = 'pending';
  perform pg_temp.assert(row.send_after <= now(), 'window 0 = straight away');
  update game_config set value = '120' where key = 'push.convo_window_seconds';
  raise notice 'ok 4: rate limit and collapse';
end $$;

-- ---------- 5. switches, presence, blocks ----------
do $$
declare a uuid := current_setting('pp.a')::uuid; b uuid := current_setting('pp.b')::uuid; conv bigint := current_setting('pp.conv')::bigint;
        n int;
begin
  delete from push_outbox;
  perform pg_temp.login(b); perform push_prefs_set('{"master": false}');
  perform pg_temp.login(a); perform social_send_message(conv, 'master off', null, null, null);
  perform pg_temp.pay(b, 100);
  perform pg_temp.assert(pg_temp.cnt(b) = 0, 'master off: nothing at all (not even money)');
  perform pg_temp.login(b); perform push_prefs_set('{"master": true, "messages": false}');
  perform pg_temp.login(a); perform social_send_message(conv, 'messages off', null, null, null);
  perform pg_temp.assert(pg_temp.cnt(b, 'category = ''messages''') = 0, 'messages off: no DM push');
  perform pg_temp.pay(b, 100);
  perform pg_temp.assert(pg_temp.cnt(b, 'category = ''money''') = 1, 'money still on');
  perform pg_temp.login(b); perform push_prefs_set('{"messages": true}');
  -- switched off AFTER queueing: skipped at send time, not sent
  delete from push_outbox;
  perform pg_temp.login(a); perform social_send_message(conv, 'queued then switched off', null, null, null);
  perform pg_temp.login(b); perform push_prefs_set('{"master": false}');
  perform pg_temp.assert((select count(*) from bl_push_claim(10)) = 0, 'switched off meanwhile: not handed to the sender');
  perform pg_temp.assert((select status || '/' || error from push_outbox where user_id = b) = 'skipped/switched off', 'marked skipped');
  perform push_prefs_set('{"master": true}');
  -- global switches (admin)
  delete from push_outbox;
  update game_config set value = 'false' where key = 'push.cat_messages';
  perform pg_temp.login(a); perform social_send_message(conv, 'global messages off', null, null, null);
  perform pg_temp.assert(pg_temp.cnt(b) = 0, 'global category off: nothing queued');
  perform pg_temp.assert(not (push_state()->'global'->>'messages')::boolean, 'players can see the category is off');
  update game_config set value = 'true' where key = 'push.cat_messages';
  update game_config set value = 'false' where key = 'push.enabled';
  perform social_send_message(conv, 'global off', null, null, null);
  perform pg_temp.pay(b, 100);
  perform pg_temp.assert(pg_temp.cnt(b) = 0, 'push.enabled off: nothing queued');
  update game_config set value = 'true' where key = 'push.enabled';
  -- an active player already sees it in the game
  update profiles set last_seen = now() where id = b;
  perform social_send_message(conv, 'b is playing right now', null, null, null);
  perform pg_temp.assert(pg_temp.cnt(b) = 0, 'active in the last 20 s: no chat push');
  perform pg_temp.pay(b, 100);
  perform pg_temp.assert(pg_temp.cnt(b, 'category = ''money''') = 1, 'money is still pushed to an active player');
  update game_config set value = '0' where key = 'push.skip_active_seconds';
  perform social_send_message(conv, 'skip off', null, null, null);
  perform pg_temp.assert(pg_temp.cnt(b, 'category = ''messages''') = 1, 'skip_active_seconds = 0: pushed');
  update game_config set value = '20' where key = 'push.skip_active_seconds';
  update profiles set last_seen = now() - interval '1 hour' where id = b;
  -- a player who blocked the sender gets nothing
  delete from push_outbox;
  perform pg_temp.login(b); insert into chat_blocks (blocker_id, blocked_id) values (b, a);
  perform pg_temp.login(a);
  insert into player_messages (conversation_id, sender_id, body) values (conv, a, 'you blocked me');
  perform pg_temp.assert(pg_temp.cnt(b) = 0, 'blocked sender: no push');
  delete from chat_blocks where blocker_id = b;
  raise notice 'ok 5: switches, presence, blocks';
end $$;

-- ---------- 6. money ----------
do $$
declare a uuid := current_setting('pp.a')::uuid; b uuid := current_setting('pp.b')::uuid; row push_outbox;
begin
  delete from push_outbox;
  perform pg_temp.login(a);
  perform bank_transfer('PpBayo', 5000, 'for chop');
  select * into row from push_outbox where user_id = b and kind = 'transfer';
  perform pg_temp.assert(row.id is not null and row.category = 'money' and row.title = 'Money don land 💰' and row.body = '₦5,000 from @PpAda',
                         'transfer text: ' || coalesce(row.title || ' / ' || row.body, 'none'));
  perform pg_temp.assert(row.url = '/play?go=bank', 'opens the bank');
  perform pg_temp.assert(pg_temp.cnt(a) = 0, 'sender gets no money push');
  perform tip_player('PpBayo', 1000, 'secret note about you');
  select * into row from push_outbox where user_id = b and kind = 'tip';
  perform pg_temp.assert(row.id is not null and row.body = '₦1,000 from @PpAda' and row.body not like '%secret%', 'tip text has no note: ' || coalesce(row.body, 'none'));
  perform pg_temp.assert(pg_temp.cnt(a) = 0, 'tipper gets no push');
  -- a gift (ledger reason admin_gift) from the admin tools
  insert into ledger (user_id, account, delta, balance_after, reason, meta) values (b, 'bank', 2000, 1, 'admin_gift', '{"narration":"x"}');
  select * into row from push_outbox where user_id = b and kind = 'gift';
  perform pg_temp.assert(row.id is not null and row.title = 'Gift from Benin Life 🎁' and row.body = '₦2,000 don enter your bank', 'gift text: ' || coalesce(row.body, 'none'));
  -- money OUT never pushes
  insert into ledger (user_id, account, delta, balance_after, reason) values (b, 'bank', -500, 1, 'transfer_out');
  perform pg_temp.assert(pg_temp.cnt(b, 'kind = ''transfer''') = 1, 'transfer_out is not a push');
  raise notice 'ok 6: money';
end $$;

-- ---------- 7. friends + broadcast ----------
do $$
declare a uuid := current_setting('pp.a')::uuid; b uuid := current_setting('pp.b')::uuid; c uuid := current_setting('pp.c')::uuid;
        adm uuid := current_setting('pp.adm')::uuid; row push_outbox; id1 bigint;
begin
  delete from push_outbox;
  perform pg_temp.sub(c); perform pg_temp.sub(adm);
  perform pg_temp.login(a); perform social_add_friend(c);
  select * into row from push_outbox where user_id = c;
  perform pg_temp.assert(row.id is not null and row.category = 'friends' and row.title = 'New friend request 👋' and row.body = '@PpAda wan add you as friend',
                         'friend request text: ' || coalesce(row.body, 'none'));
  perform pg_temp.assert(pg_temp.cnt(a) = 0, 'requester gets no push');
  perform pg_temp.login(c); perform social_respond_friend(a, true);
  perform pg_temp.assert(pg_temp.cnt(a, 'kind = ''friend_accepted''') = 1, 'accepted request pushes the requester');
  -- broadcasts: admin category is OFF by default, on when the player chose it
  delete from push_outbox;
  perform pg_temp.login(b); perform push_prefs_set('{"admin": true}');
  perform pg_temp.login(adm);
  id1 := (admin_broadcast_send('Detty December', E'Club events this week.\nAll clubs open.', 'celebration', 'everyone', null, true, null)->>'id')::bigint;
  select * into row from push_outbox where user_id = b;
  perform pg_temp.assert(row.id is not null and row.category = 'admin' and row.title = 'Detty December' and row.url = '/play?go=alerts',
                         'broadcast reached B (opted in): ' || coalesce(row.title, 'none'));
  perform pg_temp.assert(pg_temp.cnt(c) = 0 and pg_temp.cnt(a) = 0, 'announcements are off by default');
  perform pg_temp.assert(pg_temp.cnt(adm) = 0, 'the sender (admin) does not push himself');
  -- the same broadcast is never queued twice for a player
  perform pg_temp.assert(bl_push_enqueue(b, 'admin', 'broadcast', 'Detty December', 'x', '/play', null, null, null, 'bc:' || id1) is null, 'dedupe key');
  -- weekly prize event (events category, opt in)
  perform pg_temp.login(b); perform push_prefs_set('{"events": true}');
  perform bl_event(b, 'weekly_prize', '🥇 You are the top earner of the week!', 'You earned ₦90,000.', '{}');
  perform pg_temp.assert(pg_temp.cnt(b, 'kind = ''weekly_prize''') = 1, 'weekly prize pushed to an opted-in player');
  perform bl_event(c, 'weekly_prize', '🥇 You are the top earner of the week!', 'You earned ₦90,000.', '{}');
  perform pg_temp.assert(pg_temp.cnt(c, 'kind = ''weekly_prize''') = 0, 'events default off');
  raise notice 'ok 7: friends and broadcast';
end $$;

-- ---------- 8. house chat + hype ----------
do $$
declare a uuid := current_setting('pp.a')::uuid; b uuid := current_setting('pp.b')::uuid; c uuid := current_setting('pp.c')::uuid;
        v_home text; v_club text; row push_outbox;
begin
  delete from push_outbox;
  select id into v_home from locations where scene like 'home\_%' order by id limit 1;
  select id into v_club from locations where scene = 'club' order by id limit 1;
  update profiles set location_id = v_home, travel_to = null where id in (a, b, c);
  insert into chat_messages (location_id, user_id, username, body) values (v_home, a, 'PpAda', 'Anybody for pepper soup tonight, I dey cook for the whole house');
  select * into row from push_outbox where user_id = b;
  perform pg_temp.assert(row.id is not null and row.category = 'messages' and row.kind = 'house_chat' and row.title = 'House chat: @PpAda'
                         and row.url = '/play?go=house' and char_length(row.body) <= 61, 'house chat push: ' || coalesce(row.title || ' / ' || row.body, 'none'));
  perform pg_temp.assert(pg_temp.cnt(a) = 0, 'no push to the house chat sender');
  perform pg_temp.assert(pg_temp.cnt(c, 'kind = ''house_chat''') = 1, 'C is in the house too (device, default on)');
  -- not in the house: nothing
  update profiles set location_id = (select id from locations where id <> v_home and scene = 'market' order by id limit 1) where id = c;
  delete from push_outbox;
  insert into chat_messages (location_id, user_id, username, body) values (v_home, a, 'PpAda', 'another one');
  perform pg_temp.assert(pg_temp.cnt(c) = 0 and pg_temp.cnt(b) = 1, 'only people in that house');
  -- public places never push (market chat is too noisy)
  delete from push_outbox;
  insert into chat_messages (location_id, user_id, username, body)
    select location_id, a, 'PpAda', 'market talk' from profiles where id = c;
  perform pg_temp.assert((select count(*) from push_outbox) = 0, 'public place chat does not push');
  -- hype in the club the player is in (events category)
  update profiles set location_id = v_club where id in (b);
  update profiles set last_seen = now() - interval '1 hour' where id = b;
  delete from push_outbox;
  insert into place_announcements (location_id, user_id, username, kind, amount, qty, text, place)
  values (v_club, a, 'PpAda', 'spray', 50000, 1, '@PpAda just sprayed ₦50,000 at Kingdom. The whole club is shaking.', 'Kingdom');
  select * into row from push_outbox where user_id = b;
  perform pg_temp.assert(row.id is not null and row.category = 'events' and row.kind = 'hype' and row.title = '🔥 Kingdom', 'hype push: ' || coalesce(row.title, 'none'));
  perform pg_temp.assert(pg_temp.cnt(a) = 0, 'the spender gets no hype push');
  insert into place_announcements (location_id, user_id, username, kind, amount, qty, text, place) values (v_club, a, 'PpAda', 'spray', 1, 1, 'again', 'Kingdom');
  perform pg_temp.assert((select title from push_outbox where user_id = b) = '🔥 2 hype moments at Kingdom', 'hype collapses too');
  raise notice 'ok 8: house chat and hype';
end $$;

-- ---------- 9. claim, tick, cap, stuck rows ----------
do $$
declare a uuid := current_setting('pp.a')::uuid; b uuid := current_setting('pp.b')::uuid; r jsonb; v_id bigint; n int; v_ev text;
begin
  delete from push_outbox;
  -- hourly cap
  update game_config set value = '2' where key = 'push.max_per_user_hour';
  perform pg_temp.login(a);
  perform pg_temp.pay(b, 100); perform pg_temp.pay(b, 100); perform pg_temp.pay(b, 100);
  perform pg_temp.assert(pg_temp.cnt(b, 'kind = ''transfer''') = 2, 'hourly cap stops the third push');
  update game_config set value = '20' where key = 'push.max_per_user_hour';
  -- stuck 'sending' rows come back (3 tries) and then fail; old pending rows expire
  update push_outbox set status = 'sending', claimed_at = now() - interval '10 minutes', attempts = 1 where user_id = b;
  r := bl_push_tick();
  perform pg_temp.assert((r->>'recovered')::int = 2 and pg_temp.cnt(b, 'status = ''pending''') = 2, 'stuck rows go back to pending: ' || r::text);
  update push_outbox set status = 'sending', claimed_at = now() - interval '10 minutes', attempts = 3 where user_id = b;
  r := bl_push_tick();
  perform pg_temp.assert(pg_temp.cnt(b, 'status = ''failed''') = 2, 'after 3 tries: failed');
  update push_outbox set status = 'pending', created_at = now() - interval '3 hours' where user_id = b;
  r := bl_push_tick();
  perform pg_temp.assert((r->>'expired')::int = 2 and pg_temp.cnt(b, 'status = ''skipped''') = 2, 'old unsent rows are dropped: ' || r::text);
  update push_outbox set created_at = now() - interval '9 days';
  r := bl_push_tick();
  perform pg_temp.assert((r->>'deleted')::int >= 2 and (select count(*) from push_outbox) = 0, 'log cleanup after push.keep_days');
  -- club event starting: players who opted in to Game events (and ticket holders) hear about it once
  update push_prefs set events = true where user_id = b;
  select id into v_ev from place_events where active limit 1;
  update place_events set recurrence = 'none', starts_at = now() - interval '2 minutes', ends_at = now() + interval '3 hours' where id = v_ev;
  update locations set active = true where id = (select location_id from place_events where id = v_ev);
  r := bl_push_tick();
  perform pg_temp.assert(pg_temp.cnt(b, 'kind = ''club_event''') = 1, 'opted-in player told the event started: ' || r::text);
  perform pg_temp.assert((select url from push_outbox where kind = 'club_event' and user_id = b) like '/play?go=place:%', 'event deep link');
  r := bl_push_tick();
  perform pg_temp.assert(pg_temp.cnt(b, 'kind = ''club_event''') = 1, 'told once, not every minute');
  update game_config set value = 'false' where key = 'push.events_to_all';
  delete from push_outbox;
  r := bl_push_tick();
  perform pg_temp.assert(pg_temp.cnt(b, 'kind = ''club_event''') = 0, 'ticket-only mode: no ticket, no push');
  update game_config set value = 'true' where key = 'push.events_to_all';
  raise notice 'ok 9: claim, tick, cap';
end $$;

-- ---------- 10. RLS ----------
do $$
declare a uuid := current_setting('pp.a')::uuid; b uuid := current_setting('pp.b')::uuid;
begin
  perform pg_temp.login(a); perform push_prefs_set('{"messages": true}');
  perform pg_temp.login(b); perform push_prefs_set('{"messages": true}');
  insert into push_outbox (user_id, category, kind, title) values (b, 'messages', 'dm', 'x');
end $$;
set local role authenticated;
do $$
declare a uuid := current_setting('pp.a')::uuid; b uuid := current_setting('pp.b')::uuid; n int;
begin
  perform pg_temp.login(a);
  select count(*) into n from push_prefs;
  perform pg_temp.assert(n = 1, 'a sees only her own prefs row, saw ' || n);
  perform pg_temp.assert((select user_id from push_prefs) = a, 'it is hers');
  perform pg_temp.assert(pg_temp.denied('select count(*) from push_outbox'), 'push_outbox is closed to players');
  perform pg_temp.assert(pg_temp.denied('select count(*) from push_subscriptions'), 'push_subscriptions is closed to players');
  perform pg_temp.assert(pg_temp.denied($q$insert into push_prefs (user_id, master) values (gen_random_uuid(), false)$q$), 'no direct insert into prefs');
  perform pg_temp.assert(pg_temp.denied($q$update push_prefs set master = false$q$), 'no direct update of prefs');
  perform pg_temp.assert(pg_temp.denied($q$insert into push_outbox (user_id, category, kind, title) values (gen_random_uuid(), 'messages', 'dm', 'spoof')$q$), 'no spoofed pushes');
  perform pg_temp.assert(pg_temp.denied('select bl_push_enqueue(null, ''messages'', ''dm'', ''x'', ''y'', ''/play'')'), 'enqueue is private');
  perform pg_temp.assert(pg_temp.denied('select bl_push_claim(5)'), 'claim is private');
  perform pg_temp.login(b);
  perform pg_temp.assert((select count(*) from push_prefs) = 1 and (select user_id from push_prefs) = b, 'b sees only his own');
  raise notice 'ok 10: RLS';
end $$;
reset role;

-- ---------- 11. admin stats ----------
do $$
declare a uuid := current_setting('pp.a')::uuid; adm uuid := current_setting('pp.adm')::uuid; s jsonb;
begin
  delete from push_outbox;
  insert into push_outbox (user_id, category, kind, title, status, sent_at) values (a, 'money', 'transfer', 't', 'sent', now()), (a, 'messages', 'dm', 't', 'sent', now());
  insert into push_outbox (user_id, category, kind, title, status, error) values (a, 'messages', 'dm', 't', 'failed', 'HTTP 500');
  insert into push_outbox (user_id, category, kind, title, status) values (a, 'messages', 'dm', 't', 'pending');
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of('select admin_push_stats()') = 'not_admin', 'players cannot read the stats');
  perform pg_temp.login(adm);
  s := admin_push_stats();
  perform pg_temp.assert((s->>'sent_24h')::int = 2 and (s->>'failed_24h')::int = 1 and (s->>'pending')::int = 1, 'counts: ' || s::text);
  perform pg_temp.assert((s->'by_category'->>'messages')::int = 1 and (s->'by_category'->>'money')::int = 1 and s->>'last_error' = 'HTTP 500', 'by category + last error');
  raise notice 'ok 11: admin stats';
  raise notice 'PLAYER PUSH OK';
end $$;
