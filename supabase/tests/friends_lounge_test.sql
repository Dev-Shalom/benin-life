-- R7 Friends tab + Members' Lounge (20261018000400_friends_lounge.sql, docs/LOUNGE.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/friends_lounge_test.sql
-- Groups: 0 grants + RLS · 1 friends_overview (online, last seen, location hidden, pending, order, at home, privacy switch) ·
-- 2 invite to a place (alert + push, cooldown, refusals) · 3 join refused (closed, private, inactive, offline, hidden, same) ·
-- 4 tiers seeded · 5 buy each tier (ledger kind 'lounge', bank first) · 6 entry refused without a membership (travel, activity, shop) ·
-- 7 expiry + renew + upgrade rules · 8 VIP requirement (charisma OR certificate, switch) · 9 discount + free drink voucher ·
-- 10 VIP zone gate · 11 guest pass · 12 admin grant / revoke + audit + tiers editor · 13 gold tag, interior block, hype, music.

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

create temp table t_fl (name text primary key, id uuid not null) on commit drop;
grant select on t_fl to authenticated;
create or replace function pg_temp.u(p_name text) returns uuid language sql as $$ select id from t_fl where name = p_name $$;

create or replace function pg_temp.mk(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@fl.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'female', '{"gender":"female"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, cash = 0, bank = 0, last_seen = bl_now() where id = v;
  insert into t_fl values (p_name, v);
  return v;
end $$;

create or replace function pg_temp.befriend(a uuid, b uuid) returns void
language sql as $$
  insert into player_friendships (user_a, user_b, status, requested_by) values (least(a, b), greatest(a, b), 'accepted', a)
  on conflict do nothing
$$;

create or replace function pg_temp.card(p_viewer uuid, p_friend uuid) returns jsonb
language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.login(p_viewer);
  select c into r from jsonb_array_elements(friends_overview()->'friends') c where c->>'id' = p_friend::text;
  return r;
end $$;

-- put a player at a place without travelling
create or replace function pg_temp.at(p_uid uuid, p_loc text) returns void
language sql as $$ update profiles set location_id = p_loc, travel_to = null, last_seen = bl_now() where id = p_uid $$;

do $$
declare ada uuid; bayo uuid; chi uuid; dee uuid; adm uuid;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  ada := pg_temp.mk('FlAda'); bayo := pg_temp.mk('FlBayo'); chi := pg_temp.mk('FlChi'); dee := pg_temp.mk('FlDee'); adm := pg_temp.mk('FlAdm');
  update profiles set is_admin = true where id = adm;
  perform pg_temp.befriend(ada, bayo);
  perform pg_temp.befriend(ada, dee);
  -- skills / certificates must not interfere with the VIP gate until the test says so
  delete from player_skills where user_id in (ada, bayo, chi, dee, adm);
  raise notice 'fixtures ready';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 0. grants + RLS
-- ---------------------------------------------------------------------------------------------
do $$
declare k text;
begin
  foreach k in array array['friends_overview()', 'friends_set_privacy(boolean)', 'friend_join_check(uuid)', 'friend_invite_place(uuid)',
                           'lounge_status()', 'lounge_buy(text)', 'lounge_bring_guest(uuid)', 'admin_lounge_get(uuid)',
                           'admin_lounge_grant(uuid, text, integer)', 'admin_lounge_revoke(uuid)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || k, 'execute'), 'anon cannot run ' || k);
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || k, 'execute'), 'authenticated can run ' || k);
  end loop;
  foreach k in array array['bl_lounge_on()', 'bl_lounge_member(uuid)', 'bl_lounge_tier(uuid)', 'bl_lounge_access(uuid)', 'bl_lounge_vip(uuid)',
                           'bl_lounge_gold(uuid, text)', 'bl_lounge_hype_on()', 'bl_lounge_req_ok(uuid, public.lounge_tiers)',
                           'bl_lounge_req_text(public.lounge_tiers)', 'bl_lounge_assert_entry(uuid, public.locations)',
                           'bl_lounge_assert(uuid, public.locations, text)', 'bl_lounge_lock(uuid, public.locations, text)',
                           'bl_lounge_price(public.locations, text, bigint)', 'bl_lounge_voucher(uuid, text)',
                           'bl_lounge_card(uuid, public.locations)', 'bl_place_public(public.locations)',
                           'bl_friend_join_state(public.profiles, public.profiles, boolean)',
                           'bl_friend_card(public.profiles, public.profiles, numeric, boolean)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || k, 'execute'), 'anon cannot run private ' || k);
    perform pg_temp.assert(not has_function_privilege('authenticated', 'public.' || k, 'execute'), 'authenticated cannot run private ' || k);
  end loop;
  foreach k in array array['lounge_tiers', 'lounge_members', 'lounge_guests'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || k)::regclass), k || ' has RLS on');
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || k, 'select'), 'anon cannot read ' || k);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || k, 'insert'), 'no client insert into ' || k);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || k, 'update'), 'no client update of ' || k);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || k, 'delete'), 'no client delete from ' || k);
  end loop;
  raise notice 'ok 0: grants + RLS flags';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. friends_overview
-- ---------------------------------------------------------------------------------------------
do $$
declare
  ada uuid := pg_temp.u('FlAda'); bayo uuid := pg_temp.u('FlBayo'); chi uuid := pg_temp.u('FlChi'); dee uuid := pg_temp.u('FlDee');
  o jsonb; c jsonb; v_names text;
begin
  perform pg_temp.at(bayo, 'oba_market');                                  -- online at a public place
  update profiles set last_seen = bl_now() - interval '3 hours', location_id = 'oba_market' where id = dee;   -- offline
  perform pg_temp.login(ada);
  o := friends_overview();
  perform pg_temp.assert(jsonb_array_length(o->'friends') = 2, 'two friends listed');
  perform pg_temp.assert(o->'friends'->0->>'username' = 'FlBayo', 'online friend sorted first');
  c := pg_temp.card(ada, bayo);
  perform pg_temp.assert((c->>'online')::boolean, 'bayo online (green dot)');
  perform pg_temp.assert(c->'location'->>'id' = 'oba_market', 'bayo shows where he is');
  perform pg_temp.assert(c->'location'->>'name' = (select name from locations where id = 'oba_market'), 'place name given');
  perform pg_temp.assert((c->>'can_join')::boolean, 'can join a public open place');
  c := pg_temp.card(ada, dee);
  perform pg_temp.assert(not (c->>'online')::boolean, 'dee offline after 3 hours');
  perform pg_temp.assert(c->'location' = 'null'::jsonb or c->'location' is null, 'offline friend shows no stale location');
  perform pg_temp.assert(c->>'last_seen' is not null, 'last seen is returned for "last seen 3h ago"');
  perform pg_temp.assert(c->>'join_hint' = 'offline', 'cannot join an offline friend');
  -- boundary of the online window (default 120 s)
  update profiles set last_seen = bl_now() - interval '90 seconds' where id = dee;
  perform pg_temp.assert((pg_temp.card(ada, dee)->>'online')::boolean, 'still online at 90 seconds');
  update profiles set last_seen = bl_now() - interval '150 seconds' where id = dee;
  perform pg_temp.assert(not (pg_temp.card(ada, dee)->>'online')::boolean, 'offline at 150 seconds');
  update game_config set value = '200' where key = 'friends.online_seconds';
  perform pg_temp.assert((pg_temp.card(ada, dee)->>'online')::boolean, 'the online window is a setting');
  update game_config set value = '120' where key = 'friends.online_seconds';
  update profiles set last_seen = bl_now() - interval '3 hours' where id = dee;

  -- privacy: location hidden
  perform pg_temp.login(bayo);
  perform pg_temp.assert((friends_overview()->'me'->>'share_location')::boolean, 'default: show my location');
  perform friends_set_privacy(false);
  perform pg_temp.assert(not (friends_overview()->'me'->>'share_location')::boolean, 'switch saved');
  c := pg_temp.card(ada, bayo);
  perform pg_temp.assert(c->'location' = 'null'::jsonb or c->'location' is null, 'hidden location not sent');
  perform pg_temp.assert((c->>'location_hidden')::boolean, 'flag says hidden');
  perform pg_temp.assert((c->>'online')::boolean, 'online dot still shows');
  perform pg_temp.assert(c->>'join_hint' = 'hidden' and not (c->>'can_join')::boolean, 'cannot join a hidden friend');
  perform pg_temp.assert(position('oba' in c::text) = 0, 'no place leaks anywhere in the card');
  perform pg_temp.login(bayo);
  perform friends_set_privacy(true);
  perform pg_temp.assert((pg_temp.card(ada, bayo)->'location'->>'id') = 'oba_market', 'visible again');

  -- at home: no place, "At home"
  update profiles set location_id = home_location_id where id = bayo;
  c := pg_temp.card(ada, bayo);
  perform pg_temp.assert(c->'location'->>'name' = 'At home' and c->'location'->>'id' is null, 'a friend at home shows "At home" and no home id');
  perform pg_temp.assert(c->>'join_hint' is null or c->>'join_hint' = 'private', 'home is not joinable');
  perform pg_temp.assert(not (c->>'can_join')::boolean, 'cannot join a home');
  perform pg_temp.at(bayo, 'oba_market');

  -- pending requests: incoming first, with the sender
  insert into player_friendships (user_a, user_b, status, requested_by) values (least(ada, chi), greatest(ada, chi), 'pending', chi);
  perform pg_temp.login(ada);
  o := friends_overview();
  perform pg_temp.assert(jsonb_array_length(o->'requests') = 1, 'one pending request');
  perform pg_temp.assert(o->'requests'->0->>'username' = 'FlChi' and o->'requests'->0->>'direction' = 'incoming', 'incoming request from chi');
  perform pg_temp.assert(jsonb_array_length(o->'friends') = 2, 'pending is not in the friends list');
  -- existing RPC accepts it (no duplicate system)
  perform social_respond_friend(chi, true);
  perform pg_temp.assert(jsonb_array_length(friends_overview()->'friends') = 3 and jsonb_array_length(friends_overview()->'requests') = 0, 'accepted request moves to friends');
  delete from player_friendships where user_a = least(ada, chi) and user_b = greatest(ada, chi);

  -- strangers and blocked players never appear; anon refused
  perform pg_temp.login(chi);
  perform pg_temp.assert(jsonb_array_length(friends_overview()->'friends') = 0, 'a stranger sees no friends');
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_join_check((select id from t_fl where name = 'FlAda')) $q$) = 'not_friend', 'join check needs a friend');
  raise notice 'ok 1: friends_overview';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. invite to a place: alert + push
-- ---------------------------------------------------------------------------------------------
do $$
declare
  ada uuid := pg_temp.u('FlAda'); bayo uuid := pg_temp.u('FlBayo'); chi uuid := pg_temp.u('FlChi'); dee uuid := pg_temp.u('FlDee');
  r jsonb; v_ev events; v_push push_outbox; v_name text;
begin
  insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (bayo, 'https://push.example/bayo', 'k', 'a');
  perform pg_temp.at(ada, 'oba_market');
  update profiles set location_id = 'bronze_bank' where id = bayo;           -- somewhere else
  select name into v_name from locations where id = 'oba_market';
  perform pg_temp.login(ada);
  r := friend_invite_place(bayo);
  perform pg_temp.assert(r->>'place' = v_name, 'result names the place');
  select * into v_ev from events where user_id = bayo and kind = 'place_invite' order by id desc limit 1;
  perform pg_temp.assert(v_ev.id is not null, 'alert written for the friend');
  perform pg_temp.assert(v_ev.title = '@FlAda wants you at ' || v_name, 'alert text: @x wants you at <place>');
  perform pg_temp.assert(v_ev.data->>'location_id' = 'oba_market' and v_ev.data->>'from' = ada::text, 'alert carries the place id and sender');
  select * into v_push from push_outbox where user_id = bayo and kind = 'place_invite' order by id desc limit 1;
  perform pg_temp.assert(v_push.id is not null, 'push enqueued');
  perform pg_temp.assert(v_push.category = 'friends', 'push is in the friends category');
  perform pg_temp.assert(v_push.title = '@FlAda wants you at ' || v_name, 'push title');
  perform pg_temp.assert(v_push.url = '/play?go=place:oba_market', 'tapping opens the place');
  -- cooldown
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_invite_place((select id from t_fl where name = 'FlBayo')) $q$) = 'cooldown', 'second invite refused for a minute');
  perform set_config('bl.test_offset_seconds', '120', true);
  update events set created_at = created_at - interval '5 minutes' where id = v_ev.id;
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_invite_place((select id from t_fl where name = 'FlBayo')) $q$) = 'ok', 'allowed again after the cooldown');
  perform set_config('bl.test_offset_seconds', '', true);
  -- category off: alert still comes, no push
  update push_prefs set friends = false where user_id = dee;
  insert into push_prefs (user_id, friends) values (dee, false) on conflict (user_id) do update set friends = false;
  insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (dee, 'https://push.example/dee', 'k', 'a');
  update profiles set location_id = 'bronze_bank' where id = dee;
  perform pg_temp.login(ada);
  perform friend_invite_place(dee);
  perform pg_temp.assert(exists (select 1 from events where user_id = dee and kind = 'place_invite'), 'alert even when push is off');
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = dee and kind = 'place_invite'), 'no push when the friends category is off');
  -- refusals
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_invite_place((select id from t_fl where name = 'FlChi')) $q$) = 'not_friend', 'only friends');
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_invite_place((select id from t_fl where name = 'FlAda')) $q$) = 'not_friend', 'not yourself');
  update profiles set location_id = home_location_id where id = ada;
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_invite_place((select id from t_fl where name = 'FlDee')) $q$) = 'private', 'from home: use the house invite');
  perform pg_temp.at(ada, 'oba_market');
  update locations set active = false where id = 'oba_market';
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_invite_place((select id from t_fl where name = 'FlBayo')) $q$) = 'closed', 'closed place refused');
  update locations set active = true where id = 'oba_market';
  update profiles set location_id = 'oba_market' where id = bayo;
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_invite_place((select id from t_fl where name = 'FlBayo')) $q$) = 'same', 'friend already there');
  update profiles set location_id = 'bronze_bank' where id = bayo;
  -- the overview tells the client whether I can invite right now
  perform pg_temp.assert((friends_overview()->'me'->'place'->>'can_invite')::boolean, 'overview: can invite at a public place');
  update profiles set location_id = home_location_id where id = ada;
  perform pg_temp.assert(not (friends_overview()->'me'->'place'->>'can_invite')::boolean, 'overview: cannot invite from home');
  perform pg_temp.at(ada, 'oba_market');
  raise notice 'ok 2: invite to a place';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. join refused
-- ---------------------------------------------------------------------------------------------
do $$
declare
  ada uuid := pg_temp.u('FlAda'); bayo uuid := pg_temp.u('FlBayo'); dee uuid := pg_temp.u('FlDee');
  r jsonb; h int; v_open numeric; v_close numeric;
begin
  perform pg_temp.at(bayo, 'bronze_bank');
  perform pg_temp.login(ada);
  r := friend_join_check(bayo);
  perform pg_temp.assert(r->>'dest' = 'bronze_bank', 'join an open public place');
  -- closed (outside its opening hours)
  h := (bl_game_clock()->>'hour')::int;
  select open_hour, close_hour into v_open, v_close from locations where id = 'bronze_bank';
  update locations set open_hour = (h + 2) % 24, close_hour = (h + 3) % 24 where id = 'bronze_bank';
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_join_check((select id from t_fl where name = 'FlBayo')) $q$) = 'closed', 'closed place refused');
  perform pg_temp.assert(pg_temp.card(ada, bayo)->>'join_hint' = 'closed', 'card says closed');
  update locations set open_hour = v_open, close_hour = v_close where id = 'bronze_bank';
  -- switched off
  update locations set active = false where id = 'bronze_bank';
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_join_check((select id from t_fl where name = 'FlBayo')) $q$) = 'inactive', 'inactive place refused');
  update locations set active = true where id = 'bronze_bank';
  -- private (a home)
  update profiles set location_id = home_location_id where id = bayo;
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_join_check((select id from t_fl where name = 'FlBayo')) $q$) = 'private', 'private home refused');
  perform pg_temp.at(bayo, 'bronze_bank');
  -- hidden, offline, same place, on the road
  update profiles set share_location_friends = false where id = bayo;
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_join_check((select id from t_fl where name = 'FlBayo')) $q$) = 'hidden', 'hidden refused');
  update profiles set share_location_friends = true, last_seen = bl_now() - interval '1 hour' where id = bayo;
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_join_check((select id from t_fl where name = 'FlBayo')) $q$) = 'offline', 'offline refused');
  perform pg_temp.at(bayo, 'bronze_bank');
  perform pg_temp.at(ada, 'bronze_bank');
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_join_check((select id from t_fl where name = 'FlBayo')) $q$) = 'same', 'already there refused');
  perform pg_temp.at(ada, 'oba_market');
  update profiles set travel_to = 'oba_market', travel_started_at = bl_now(), travel_arrives_at = bl_now() + interval '1 hour', travel_mode = 'walk' where id = bayo;
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_join_check((select id from t_fl where name = 'FlBayo')) $q$) = 'travelling', 'on the road refused');
  update profiles set travel_to = null, travel_started_at = null, travel_arrives_at = null, travel_mode = null where id = bayo;
  raise notice 'ok 3: join refused';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. tiers seeded + place seeded
-- ---------------------------------------------------------------------------------------------
do $$
declare t lounge_tiers; l locations;
begin
  select * into t from lounge_tiers where id = 'day_pass';
  perform pg_temp.assert(t.price = 5000 and t.hours = 24 and not t.vip, 'day pass: 5,000 for 24 hours');
  select * into t from lounge_tiers where id = 'monthly';
  perform pg_temp.assert(t.price = 150000 and t.hours = 720 and t.discount_pct = 15 and t.gold_tag and t.vouchers = 1, 'monthly: 150,000 for 30 days, perks');
  select * into t from lounge_tiers where id = 'vip';
  perform pg_temp.assert(t.price = 1000000 and t.hours = 720 and t.vip and t.guests = 1 and t.req_charisma_level = 3 and t.req_any_cert, 'VIP: 1,000,000, guest, requirement');
  select * into l from locations where id = 'members_lounge';
  perform pg_temp.assert(l.scene = 'lounge' and l.open_hour is null and l.close_hour is null and l.active and l.district = 'gra', 'the lounge is open all day, in GRA');
  perform pg_temp.assert((select count(*) from place_zones where scene = 'lounge' and active) = 6, 'six lounge zones');
  perform pg_temp.assert((select count(*) from zone_actions where zone_id like 'lounge.%' and active) = 10, 'ten lounge zone actions');
  perform pg_temp.assert(exists (select 1 from skill_sources where kind = 'activity' and ref = 'lounge_network' and skill_id = 'charisma' and active), 'networking trains charisma');
  perform pg_temp.assert(bl_cfg_bool('lounge.enabled'), 'lounge on by default');
  raise notice 'ok 4: seeds';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. buy each tier
-- ---------------------------------------------------------------------------------------------
do $$
declare
  ada uuid := pg_temp.u('FlAda'); bayo uuid := pg_temp.u('FlBayo'); chi uuid := pg_temp.u('FlChi');
  r jsonb; v_row ledger; m lounge_members;
begin
  -- not enough money
  perform pg_temp.login(ada);
  update profiles set cash = 1000, bank = 0 where id = ada;
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_buy('day_pass') $q$) = 'not_enough_cash', 'broke player refused');
  perform pg_temp.assert(not exists (select 1 from lounge_members where user_id = ada), 'nothing granted');
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_buy('nope') $q$) = 'no_tier', 'unknown tier');
  -- day pass: bank first, then cash
  update profiles set cash = 3000, bank = 3000 where id = ada;
  r := lounge_buy('day_pass');
  perform pg_temp.assert(r->>'kind' = 'bought' and (r->>'from_bank')::bigint = 3000 and (r->>'from_cash')::bigint = 2000, 'day pass paid bank first');
  select * into m from lounge_members where user_id = ada;
  perform pg_temp.assert(m.tier_id = 'day_pass' and m.expires_at > bl_now() + interval '23 hours 59 minutes' and m.expires_at <= bl_now() + interval '24 hours', 'day pass lasts 24 hours');
  perform pg_temp.assert((select cash from profiles where id = ada) = 1000 and (select bank from profiles where id = ada) = 0, 'balances after the day pass');
  perform pg_temp.assert((select count(*) from ledger where user_id = ada and reason = 'lounge') = 2, 'ledger rows with reason lounge (bank + cash)');
  perform pg_temp.assert((select -sum(delta) from ledger where user_id = ada and reason = 'lounge') = 5000, 'ledger total is the price');
  perform pg_temp.assert(bl_ledger_label('lounge', '{"name":"Day pass"}') = 'The Lounge: Day pass', 'ledger label');
  perform pg_temp.assert(exists (select 1 from events where user_id = ada and kind = 'lounge_member'), 'welcome alert');
  -- monthly
  update profiles set cash = 200000, bank = 0 where id = bayo;
  perform pg_temp.login(bayo);
  r := lounge_buy('monthly');
  select * into m from lounge_members where user_id = bayo;
  perform pg_temp.assert(m.tier_id = 'monthly' and m.expires_at > bl_now() + interval '29 days 23 hours' and m.vouchers_left = 1, 'monthly: 30 days and one voucher');
  perform pg_temp.assert((select cash from profiles where id = bayo) = 50000, 'monthly cost 150,000');
  -- VIP: needs the requirement (group 8 covers the failure), grant a certificate here
  update profiles set cash = 1500000 where id = chi;
  perform pg_temp.login(chi);
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_buy('vip') $q$) = 'requirement', 'VIP refused without the requirement');
  insert into player_certificates (user_id, cert_id) select chi, id from certificates limit 1;
  r := lounge_buy('vip');
  select * into m from lounge_members where user_id = chi;
  perform pg_temp.assert(m.tier_id = 'vip' and m.vouchers_left = 1, 'VIP bought with a certificate');
  perform pg_temp.assert((select cash from profiles where id = chi) = 500000, 'VIP cost 1,000,000');
  perform pg_temp.assert((r->'status'->>'vip')::boolean, 'status says VIP');
  perform pg_temp.assert((r->'status'->'me'->>'guest_slots')::int = 1, 'status shows the guest slot');
  raise notice 'ok 5: buy each tier';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. entry refused without a membership
-- ---------------------------------------------------------------------------------------------
do $$
declare dee uuid := pg_temp.u('FlDee'); ada uuid := pg_temp.u('FlAda'); r jsonb;
begin
  update profiles set cash = 50000, last_seen = bl_now() where id = dee;
  perform pg_temp.login(dee);
  perform pg_temp.assert(pg_temp.hint_of($q$ select travel_quote('members_lounge') $q$) = 'no_membership', 'travel quote refused without a pass');
  perform pg_temp.assert(pg_temp.hint_of($q$ select travel_start('members_lounge', 'walk') $q$) = 'no_membership', 'travel start refused without a pass');
  update profiles set location_id = 'members_lounge', travel_to = null where id = dee;   -- smuggled in
  perform pg_temp.assert(pg_temp.hint_of($q$ select do_activity('lounge_cocktail') $q$) = 'no_membership', 'activity refused without a pass');
  perform pg_temp.assert(pg_temp.hint_of($q$ select shop_buy('star_beer', 1) $q$) = 'no_membership', 'shop refused without a pass');
  perform pg_temp.assert(pg_temp.hint_of($q$ select do_activity('lounge_network') $q$) = 'no_membership', 'networking refused without a pass');
  r := place_interior('members_lounge');
  perform pg_temp.assert(r->'lounge'->>'access' is null, 'interior says no access');
  perform pg_temp.assert((select bool_and(a->>'locked' = 'Members only') from jsonb_array_elements(r->'zones') z, jsonb_array_elements(z->'actions') a
                           where a->>'kind' in ('activity', 'shop') and a->>'ref' <> 'ease_yourself') is true, 'every lounge card locked: Members only');
  update profiles set location_id = home_location_id where id = dee;
  -- a member can travel
  perform pg_temp.login(ada);
  perform pg_temp.assert(pg_temp.hint_of($q$ select travel_quote('members_lounge') $q$) = 'ok', 'a member can ask for a quote');
  -- friends see "no_membership" when joining a friend inside
  update profiles set location_id = 'members_lounge', last_seen = bl_now() where id = ada;
  perform pg_temp.login(dee);
  update profiles set location_id = 'oba_market' where id = dee;
  perform pg_temp.assert(pg_temp.hint_of($q$ select friend_join_check((select id from t_fl where name = 'FlAda')) $q$) = 'no_membership', 'join needs a pass');
  update profiles set location_id = home_location_id where id = ada;
  update profiles set location_id = 'oba_market' where id = ada;
  -- switched off
  update game_config set value = 'false' where key = 'lounge.enabled';
  perform pg_temp.login(ada);
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_buy('day_pass') $q$) = 'inactive', 'buying refused when the lounge is off');
  perform pg_temp.assert(pg_temp.hint_of($q$ select travel_quote('members_lounge') $q$) = 'inactive', 'entry refused when the lounge is off');
  update game_config set value = 'true' where key = 'lounge.enabled';
  raise notice 'ok 6: entry gate';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. expiry, renew, upgrade
-- ---------------------------------------------------------------------------------------------
do $$
declare ada uuid := pg_temp.u('FlAda'); bayo uuid := pg_temp.u('FlBayo'); r jsonb; m lounge_members; v_before timestamptz;
begin
  -- the day pass expires after 24 hours
  perform pg_temp.login(ada);
  update profiles set location_id = 'members_lounge', travel_to = null, cash = 50000 where id = ada;
  perform pg_temp.assert(pg_temp.hint_of($q$ select do_activity('lounge_pool') $q$) = 'ok', 'member can play pool');
  update profiles set busy_until = null, busy_label = null, busy_started_at = null where id = ada;
  perform set_config('bl.test_offset_seconds', (25 * 3600)::text, true);
  perform pg_temp.assert(bl_lounge_access(ada) is null, 'access gone after 25 hours');
  perform pg_temp.assert(pg_temp.hint_of($q$ select do_activity('lounge_pool') $q$) = 'no_membership', 'activity refused after expiry');
  perform pg_temp.assert(pg_temp.hint_of($q$ select travel_quote('members_lounge') $q$) = 'no_membership', 'travel refused after expiry');
  r := lounge_status();
  perform pg_temp.assert(r->'me' = 'null'::jsonb or r->'me' is null, 'status: no active membership');
  perform pg_temp.assert(r->>'expired_tier' = 'Day pass', 'status tells the renew button what expired');
  perform pg_temp.assert((place_interior('members_lounge')->'lounge'->>'expired')::boolean, 'interior says expired');
  perform pg_temp.assert(not exists (select 1 from lounge_members where user_id = ada and expires_at > bl_now()), 'row expired');
  -- renew (buy again) after expiry starts a fresh pass
  update profiles set cash = 9000, bank = 0 where id = ada;
  r := lounge_buy('day_pass');
  perform pg_temp.assert(r->>'kind' = 'bought', 'buying after expiry is a fresh pass');
  perform pg_temp.assert(bl_lounge_access(ada) = 'member', 'access again');
  -- renewing the same tier stacks time
  update profiles set cash = 9000 where id = ada;
  select expires_at into v_before from lounge_members where user_id = ada;
  r := lounge_buy('day_pass');
  select * into m from lounge_members where user_id = ada;
  perform pg_temp.assert(r->>'kind' = 'renewed' and m.expires_at = v_before + interval '24 hours', 'renew adds 24 hours on top');
  -- stack cap: monthly renewals never exceed lounge.max_stack_days
  perform set_config('bl.test_offset_seconds', '', true);
  perform pg_temp.login(bayo);
  update profiles set cash = 1000000 where id = bayo;
  perform lounge_buy('monthly');
  perform lounge_buy('monthly');
  select * into m from lounge_members where user_id = bayo;
  perform pg_temp.assert(m.expires_at <= bl_now() + interval '90 days', 'stack capped at 90 days');
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_buy('monthly') $q$) = 'max_stack', 'renew refused at the cap');
  perform pg_temp.assert(m.vouchers_left = 3, 'vouchers stack to the cap (3)');
  -- a lower tier can't replace a better one
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_buy('day_pass') $q$) = 'have_better', 'cannot buy a lower tier over a better one');
  perform pg_temp.assert((select a->>'action' from jsonb_array_elements(lounge_status()->'tiers') a where a->>'id' = 'day_pass') = 'lower', 'status: lower');
  perform pg_temp.assert((select a->>'action' from jsonb_array_elements(lounge_status()->'tiers') a where a->>'id' = 'monthly') = 'max', 'status: max');
  raise notice 'ok 7: expiry, renew, caps';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. VIP requirement: Charisma level 3 OR any certificate (and the switch)
-- ---------------------------------------------------------------------------------------------
do $$
declare dee uuid := pg_temp.u('FlDee'); r jsonb;
begin
  perform pg_temp.login(dee);
  update profiles set cash = 3000000, bank = 0 where id = dee;
  delete from player_certificates where user_id = dee;
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_buy('vip') $q$) = 'requirement', 'level 1 and no certificate: refused');
  perform pg_temp.assert((select cash from profiles where id = dee) = 3000000, 'nothing charged on refusal');
  perform pg_temp.assert((select a->>'action' from jsonb_array_elements(lounge_status()->'tiers') a where a->>'id' = 'vip') = 'locked', 'status: locked');
  perform pg_temp.assert((select a->>'requirement' from jsonb_array_elements(lounge_status()->'tiers') a where a->>'id' = 'vip') = 'Charisma level 3 or any certificate', 'requirement text');
  -- charisma 3
  insert into player_skills (user_id, skill_id, xp) values (dee, 'charisma', bl_skill_xp_for_level(3))
    on conflict (user_id, skill_id) do update set xp = excluded.xp;
  perform pg_temp.assert(bl_skill_level(dee, 'charisma') >= 3, 'charisma level 3 reached');
  r := lounge_buy('vip');
  perform pg_temp.assert(r->>'tier' = 'vip', 'charisma 3 opens VIP');
  delete from lounge_members where user_id = dee;
  update player_skills set xp = 0 where user_id = dee;
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_buy('vip') $q$) = 'requirement', 'back to level 1: refused');
  -- the requirement is tunable: switch it off
  update game_config set value = 'false' where key = 'lounge.requirements_enabled';
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_buy('vip') $q$) = 'ok', 'switch off: anyone can buy');
  update game_config set value = 'true' where key = 'lounge.requirements_enabled';
  delete from lounge_members where user_id = dee;
  -- per-tier tune: certificate only
  update lounge_tiers set req_charisma_level = 0 where id = 'vip';
  insert into player_skills (user_id, skill_id, xp) values (dee, 'charisma', bl_skill_xp_for_level(5)) on conflict (user_id, skill_id) do update set xp = excluded.xp;
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_buy('vip') $q$) = 'requirement', 'tuned to certificate only: level is not enough');
  update lounge_tiers set req_charisma_level = 3 where id = 'vip';
  update player_skills set xp = 0 where user_id = dee;
  raise notice 'ok 8: VIP requirement';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. discount + voucher
-- ---------------------------------------------------------------------------------------------
do $$
declare
  ada uuid := pg_temp.u('FlAda'); bayo uuid := pg_temp.u('FlBayo'); dee uuid := pg_temp.u('FlDee');
  r jsonb; v_cash bigint; v_price bigint; v_card jsonb;
begin
  -- day pass: no discount; price in the interior = list price
  perform pg_temp.login(ada);
  update profiles set location_id = 'members_lounge', travel_to = null, cash = 100000, busy_until = null, busy_label = null, busy_started_at = null where id = ada;
  v_card := (select a from jsonb_array_elements(place_interior('members_lounge')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'lounge_small_chops');
  perform pg_temp.assert((v_card->>'cost')::bigint = 4500, 'day pass pays the list price');
  r := do_activity('lounge_small_chops');
  perform pg_temp.assert((select cash from profiles where id = ada) = 95500, 'day pass paid 4,500 for small chops');
  -- monthly: 15% off, voucher covers the first cocktail
  perform pg_temp.login(bayo);
  update profiles set location_id = 'members_lounge', travel_to = null, cash = 100000, busy_until = null, busy_label = null, busy_started_at = null where id = bayo;
  update lounge_members set vouchers_left = 1 where user_id = bayo;
  v_card := (select a from jsonb_array_elements(place_interior('members_lounge')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'lounge_small_chops');
  perform pg_temp.assert((v_card->>'cost')::bigint = 3850, 'monthly sees 15% off 4,500 = 3,850');
  perform pg_temp.assert((place_interior('members_lounge')->'lounge'->>'vouchers_left')::int = 1, 'interior shows the voucher');
  r := do_activity('lounge_cocktail');
  perform pg_temp.assert((select cash from profiles where id = bayo) = 100000, 'free drink voucher covered the cocktail');
  perform pg_temp.assert(r->>'message' like '%Free drink voucher used%', 'message says the voucher was used');
  perform pg_temp.assert((select vouchers_left from lounge_members where user_id = bayo) = 0, 'voucher spent');
  update profiles set busy_until = null, busy_label = null, busy_started_at = null where id = bayo;
  r := do_activity('lounge_cocktail');
  v_cash := (select cash from profiles where id = bayo);
  perform pg_temp.assert(v_cash = 100000 - 5100, 'second cocktail: 15% off 6,000 = 5,100');
  update profiles set busy_until = null, busy_label = null, busy_started_at = null where id = bayo;
  r := shop_buy('star_beer', 2);
  perform pg_temp.assert((select cash from profiles where id = bayo) = v_cash - 2600, 'shop discount: Star 1,500 -> 1,275, rounded to 1,300 each');
  -- a non-lounge place is unchanged
  perform pg_temp.assert(bl_club_price((select l from locations l where id = 'oba_market'), 'x', 1000) = 1000, 'no discount outside the lounge');
  -- VIP: 30% off
  perform pg_temp.login(dee);
  update profiles set cash = 3000000, bank = 0, location_id = 'members_lounge', travel_to = null where id = dee;
  insert into player_certificates (user_id, cert_id) select dee, id from certificates limit 1 on conflict do nothing;
  perform lounge_buy('vip');
  v_card := (select a from jsonb_array_elements(place_interior('members_lounge')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'lounge_cocktail');
  perform pg_temp.assert((v_card->>'cost')::bigint = 4200, 'VIP sees 30% off 6,000 = 4,200');
  -- the tier's discount is tunable
  update lounge_tiers set discount_pct = 50 where id = 'vip';
  v_card := (select a from jsonb_array_elements(place_interior('members_lounge')->'zones') z, jsonb_array_elements(z->'actions') a where a->>'ref' = 'lounge_cocktail');
  perform pg_temp.assert((v_card->>'cost')::bigint = 3000, 'tuned to 50%: 3,000');
  update lounge_tiers set discount_pct = 30 where id = 'vip';
  raise notice 'ok 9: discount + voucher';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. VIP zone gate
-- ---------------------------------------------------------------------------------------------
do $$
declare bayo uuid := pg_temp.u('FlBayo'); dee uuid := pg_temp.u('FlDee'); r jsonb; v_cash bigint;
begin
  perform pg_temp.login(bayo);
  update profiles set busy_until = null, busy_label = null, busy_started_at = null, cash = 500000 where id = bayo;
  perform pg_temp.assert(pg_temp.hint_of($q$ select do_activity('lounge_vip_suite') $q$) = 'vip_only', 'monthly member refused in the VIP cabana');
  perform pg_temp.assert(pg_temp.hint_of($q$ select do_activity('lounge_vip_network') $q$) = 'vip_only', 'VIP mixer refused too');
  perform pg_temp.assert((select cash from profiles where id = bayo) = 500000, 'nothing charged');
  perform pg_temp.assert((select bool_and(a->>'locked' = 'VIP only') from jsonb_array_elements(place_interior('members_lounge')->'zones') z, jsonb_array_elements(z->'actions') a
                           where z->>'key' = 'vip') is true, 'interior locks the VIP cards for a monthly member: VIP only');
  perform pg_temp.assert((select bool_and(a->>'locked' is null) from jsonb_array_elements(place_interior('members_lounge')->'zones') z, jsonb_array_elements(z->'actions') a
                           where z->>'key' = 'bar') is true, 'bar cards open');
  perform pg_temp.login(dee);
  update profiles set busy_until = null, busy_label = null, busy_started_at = null, cash = 500000 where id = dee;
  r := do_activity('lounge_vip_suite');
  perform pg_temp.assert((select cash from profiles where id = dee) = 500000 - 84000, 'VIP cabana for a VIP: 120,000 less 30% = 84,000');
  perform pg_temp.assert((select bool_and(a->>'locked' is null) from jsonb_array_elements(place_interior('members_lounge')->'zones') z, jsonb_array_elements(z->'actions') a
                           where z->>'key' = 'vip') is true, 'VIP cards open for a VIP');
  -- the VIP list is a setting
  update game_config set value = '"lounge_vip_suite"' where key = 'lounge.vip_activities';
  perform pg_temp.login(bayo);
  update profiles set busy_until = null, busy_label = null, busy_started_at = null where id = bayo;
  perform pg_temp.assert(pg_temp.hint_of($q$ select do_activity('lounge_vip_network') $q$) = 'ok', 'VIP mixer opened to everyone by the setting');
  update game_config set value = '"lounge_vip_suite,lounge_vip_network"' where key = 'lounge.vip_activities';
  -- VIP-only shop items (setting)
  update profiles set busy_until = null, busy_label = null, busy_started_at = null where id = bayo;
  update game_config set value = '"star_beer"' where key = 'lounge.vip_items';
  perform pg_temp.assert(pg_temp.hint_of($q$ select shop_buy('star_beer', 1) $q$) = 'vip_only', 'VIP-only item refused for a member');
  update game_config set value = '""' where key = 'lounge.vip_items';
  -- networking: charisma XP
  perform pg_temp.login(bayo);
  update profiles set busy_until = null, busy_label = null, busy_started_at = null where id = bayo;
  delete from player_skills where user_id = bayo;
  perform do_activity('lounge_network');
  perform pg_temp.assert(bl_skill_xp(bayo, 'charisma') >= 4, 'networking gave charisma XP');
  raise notice 'ok 10: VIP zone';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 11. guest pass
-- ---------------------------------------------------------------------------------------------
do $$
declare
  ada uuid := pg_temp.u('FlAda'); bayo uuid := pg_temp.u('FlBayo'); chi uuid := pg_temp.u('FlChi'); dee uuid := pg_temp.u('FlDee');
  r jsonb; v_ev events; v_push push_outbox;
begin
  -- chi is a VIP (group 5); dee is a VIP too (group 9). Pairs: chi + a fresh friend.
  delete from lounge_members where user_id = ada;
  update profiles set location_id = 'oba_market' where id = ada;
  perform pg_temp.befriend(chi, ada);
  perform pg_temp.login(bayo);
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_bring_guest((select id from t_fl where name = 'FlAda')) $q$) = 'not_vip', 'a monthly member cannot bring a free guest');
  perform pg_temp.login(chi);
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_bring_guest((select id from t_fl where name = 'FlBayo')) $q$) = 'not_friend', 'only friends');
  insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (ada, 'https://push.example/ada', 'k', 'a');
  perform pg_temp.assert(bl_lounge_access(ada) is null, 'ada has no pass');
  perform pg_temp.login(ada);
  perform pg_temp.assert(pg_temp.hint_of($q$ select travel_quote('members_lounge') $q$) = 'no_membership', 'guest cannot enter before the VIP invites');
  perform pg_temp.login(chi);
  r := lounge_bring_guest(ada);
  perform pg_temp.assert(bl_lounge_access(ada) = 'guest', 'ada has a guest pass');
  perform pg_temp.assert((select expires_at from lounge_guests where guest_id = ada) <= bl_now() + interval '12 hours', 'guest pass lasts 12 hours');
  select * into v_ev from events where user_id = ada and kind = 'lounge_guest' order by id desc limit 1;
  perform pg_temp.assert(v_ev.data->>'location_id' = 'members_lounge' and v_ev.title like '@FlChi wants you at The Lounge, GRA', 'guest alert');
  select * into v_push from push_outbox where user_id = ada and kind = 'lounge_guest';
  perform pg_temp.assert(v_push.category = 'friends' and v_push.url = '/play?go=place:members_lounge', 'guest push, friends category');
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_bring_guest((select id from t_fl where name = 'FlAda')) $q$) = 'already_guest', 'no double pass');
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_bring_guest((select id from t_fl where name = 'FlDee')) $q$) = 'not_friend' , 'dee is not chi''s friend');
  perform pg_temp.befriend(chi, dee);
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_bring_guest((select id from t_fl where name = 'FlDee')) $q$) = 'no_slot', 'only 1 free guest at a time');
  -- the guest enters, uses the main lounge, not the VIP cabana
  perform pg_temp.login(ada);
  perform pg_temp.assert(pg_temp.hint_of($q$ select travel_quote('members_lounge') $q$) = 'ok', 'guest can travel in');
  update profiles set location_id = 'members_lounge', travel_to = null, cash = 50000, busy_until = null, busy_label = null, busy_started_at = null where id = ada;
  perform pg_temp.assert(pg_temp.hint_of($q$ select do_activity('lounge_pool') $q$) = 'ok', 'guest can play pool');
  update profiles set busy_until = null, busy_label = null, busy_started_at = null where id = ada;
  perform pg_temp.assert(pg_temp.hint_of($q$ select do_activity('lounge_vip_suite') $q$) = 'vip_only', 'guest has no VIP cabana by default');
  update game_config set value = 'true' where key = 'lounge.guest_vip';
  perform pg_temp.assert(pg_temp.hint_of($q$ select do_activity('lounge_vip_network') $q$) = 'ok', 'setting lets guests into the VIP zone');
  update game_config set value = 'false' where key = 'lounge.guest_vip';
  perform pg_temp.assert((place_interior('members_lounge')->'lounge'->>'access') = 'guest', 'interior says guest');
  -- the guest pass runs out
  perform set_config('bl.test_offset_seconds', (13 * 3600)::text, true);
  perform pg_temp.assert(bl_lounge_access(ada) is null, 'guest pass expired after 12 hours');
  perform set_config('bl.test_offset_seconds', '', true);
  -- ...and then the slot is free again
  perform pg_temp.login(chi);
  update lounge_guests set expires_at = bl_now() - interval '1 minute' where host_id = chi;
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_bring_guest((select id from t_fl where name = 'FlDee')) $q$) = 'ok', 'slot frees after expiry');
  -- RLS: a guest sees their own pass, a stranger sees none
  perform pg_temp.login(bayo);
  set local role authenticated;
  perform pg_temp.assert((select count(*) from lounge_guests) = 0, 'a stranger cannot read guest passes');
  reset role;
  raise notice 'ok 11: guest pass';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 12. admin: grant, revoke, audit, tiers editor, RLS
-- ---------------------------------------------------------------------------------------------
do $$
declare
  adm uuid := pg_temp.u('FlAdm'); ada uuid := pg_temp.u('FlAda'); bayo uuid := pg_temp.u('FlBayo'); chi uuid := pg_temp.u('FlChi');
  r jsonb; v_a admin_audit; v_n int;
begin
  perform pg_temp.login(bayo);
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_lounge_grant((select id from t_fl where name = 'FlAda'), 'vip', null) $q$) <> 'ok', 'a player cannot grant');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_lounge_get((select id from t_fl where name = 'FlAda')) $q$) <> 'ok', 'a player cannot read the admin view');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_lounge_revoke((select id from t_fl where name = 'FlAda')) $q$) <> 'ok', 'a player cannot revoke');
  perform pg_temp.login(adm);
  delete from lounge_members where user_id = ada;
  perform pg_temp.assert(admin_lounge_get(ada)->'member' = 'null'::jsonb, 'no membership yet');
  select count(*) into v_n from ledger where user_id = ada and reason = 'lounge';
  r := admin_lounge_grant(ada, 'vip', 48);
  select * into v_a from admin_audit where action = 'lounge_grant' and target_user = ada order by id desc limit 1;
  perform pg_temp.assert(v_a.id is not null and v_a.admin_id = adm and v_a.data->>'tier' = 'vip' and (v_a.data->>'hours')::int = 48, 'grant is audited');
  perform pg_temp.assert(bl_lounge_vip(ada) and bl_lounge_access(ada) = 'member', 'granted VIP works at once');
  perform pg_temp.assert((select expires_at from lounge_members where user_id = ada) between bl_now() + interval '47 hours 59 minutes' and bl_now() + interval '48 hours', 'granted for 48 hours');
  perform pg_temp.assert((select paid_total from lounge_members where user_id = ada) = 0 and (select source from lounge_members where user_id = ada) = 'admin', 'a grant costs nothing and is marked admin');
  perform pg_temp.assert((select count(*) from ledger where user_id = ada and reason = 'lounge') = v_n, 'no ledger row for a grant');
  perform pg_temp.assert(admin_lounge_get(ada)->'member'->>'source' = 'admin', 'admin view shows the membership');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_lounge_grant((select id from t_fl where name = 'FlAda'), 'nope', null) $q$) = 'no_tier', 'unknown tier');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_lounge_grant((select id from t_fl where name = 'FlAda'), 'vip', 0) $q$) = 'bad_value', 'bad hours');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_lounge_grant(gen_random_uuid(), 'vip', null) $q$) = 'no_player', 'unknown player');
  r := admin_lounge_revoke(ada);
  perform pg_temp.assert(bl_lounge_access(ada) is null, 'revoked');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'lounge_revoke' and target_user = ada), 'revoke is audited');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_lounge_revoke((select id from t_fl where name = 'FlAda')) $q$) = 'no_member', 'nothing to revoke');
  -- the Content editor: Lounge tiers
  r := admin_row_upsert('lounge_tiers', '{"id":"day_pass","price":6000,"discount_pct":5}');
  perform pg_temp.assert((select price from lounge_tiers where id = 'day_pass') = 6000 and (select discount_pct from lounge_tiers where id = 'day_pass') = 5, 'admin edits a tier');
  perform pg_temp.assert(exists (select 1 from admin_audit where action like '%upsert%' or action like '%row%' order by id desc limit 1), 'row edit audited');
  r := admin_row_upsert('lounge_tiers', '{"id":"weekend","name":"Weekend pass","icon":"🎉","blurb":"3 days","price":12000,"hours":72,"sort":15,"active":true}');
  perform pg_temp.assert(exists (select 1 from lounge_tiers where id = 'weekend' and hours = 72), 'admin adds a tier');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_row_upsert('lounge_tiers', '{"id":"day_pass","discount_pct":120}') $q$) <> 'ok', 'discount over 100 refused by the table');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_row_upsert('lounge_tiers', '{"id":"day_pass","nonsense":1}') $q$) = 'bad_column', 'unknown column refused');
  perform pg_temp.assert(jsonb_array_length(admin_table_rows('lounge_tiers')->'rows') >= 4 or jsonb_array_length(admin_table_rows('lounge_tiers')) >= 4, 'admin lists the tiers');
  perform pg_temp.login(bayo);
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_row_upsert('lounge_tiers', '{"id":"day_pass","price":1}') $q$) <> 'ok', 'a player cannot edit tiers');
  -- inactive tiers are hidden from the sheet
  perform pg_temp.login(adm);
  update lounge_tiers set active = false where id = 'weekend';
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(lounge_status()->'tiers') a where a->>'id' = 'weekend'), 'inactive tier hidden');
  perform pg_temp.assert(pg_temp.hint_of($q$ select lounge_buy('weekend') $q$) = 'no_tier', 'inactive tier cannot be bought');
  update lounge_tiers set price = 5000, discount_pct = 0 where id = 'day_pass';
  -- RLS: own membership only
  perform pg_temp.login(chi);
  set local role authenticated;
  perform pg_temp.assert((select count(*) from lounge_members) = 1 and (select user_id from lounge_members) = chi, 'a player reads only their own membership');
  perform pg_temp.assert((select count(*) from lounge_tiers) >= 3, 'tiers are readable');
  perform pg_temp.assert(pg_temp.denied($q$ update lounge_members set expires_at = now() + interval '10 years' $q$), 'a player cannot extend a membership');
  perform pg_temp.assert(pg_temp.denied($q$ insert into lounge_members (user_id, tier_id, expires_at) values (gen_random_uuid(), 'vip', now()) $q$), 'a player cannot insert a membership');
  perform pg_temp.assert(pg_temp.denied($q$ update lounge_tiers set price = 0 $q$), 'a player cannot change prices');
  reset role;
  raise notice 'ok 12: admin';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 13. gold tag, interior block, hype, music
-- ---------------------------------------------------------------------------------------------
do $$
declare
  ada uuid := pg_temp.u('FlAda'); bayo uuid := pg_temp.u('FlBayo'); chi uuid := pg_temp.u('FlChi'); dee uuid := pg_temp.u('FlDee');
  r jsonb; v_n int; v_pl uuid; adm uuid := pg_temp.u('FlAdm');
begin
  -- gold tag: monthly + VIP have it, the day pass does not, nobody has it outside the lounge
  perform pg_temp.login(ada);
  update profiles set location_id = 'members_lounge', travel_to = null, last_seen = bl_now() where id in (bayo, chi, dee);
  perform pg_temp.login(ada);
  update profiles set location_id = 'members_lounge', travel_to = null, last_seen = bl_now() where id = ada;
  r := players_here('members_lounge');
  perform pg_temp.assert((select (p->>'gold')::boolean from jsonb_array_elements(r) p where p->>'username' = 'FlChi'), 'VIP shows the gold tag');
  perform pg_temp.assert((select (p->>'gold')::boolean from jsonb_array_elements(r) p where p->>'username' = 'FlBayo'), 'monthly shows the gold tag');
  update game_config set value = 'false' where key = 'lounge.gold_tag';
  perform pg_temp.assert(not (select (p->>'gold')::boolean from jsonb_array_elements(players_here('members_lounge')) p where p->>'username' = 'FlChi'), 'the gold tag is a setting');
  update game_config set value = 'true' where key = 'lounge.gold_tag';
  update lounge_tiers set gold_tag = false where id = 'monthly';
  perform pg_temp.assert(not (select (p->>'gold')::boolean from jsonb_array_elements(players_here('members_lounge')) p where p->>'username' = 'FlBayo'), 'tier tunes the gold tag');
  update lounge_tiers set gold_tag = true where id = 'monthly';
  update profiles set location_id = 'oba_market' where id = chi;
  perform pg_temp.assert(bl_lounge_gold(chi, 'oba_market') = false, 'no gold outside the lounge');
  -- interior block
  perform pg_temp.login(dee);
  r := place_interior('members_lounge');
  perform pg_temp.assert(r->'lounge'->>'access' = 'member' and (r->'lounge'->>'vip')::boolean, 'interior: VIP member');
  perform pg_temp.assert((r->'lounge'->'tier'->>'name') = 'VIP', 'interior: tier name');
  perform pg_temp.assert(r->>'open' = 'true' and r->>'hours' is null, 'open all day, no hours');
  perform pg_temp.assert(jsonb_array_length(r->'zones') = 6, 'six zones');
  perform pg_temp.assert(place_interior('oba_market')->'lounge' = 'null'::jsonb or place_interior('oba_market')->'lounge' is null, 'other places have no lounge block');
  -- open at any hour of the day
  perform pg_temp.assert(bl_place_open((select l from locations l where id = 'members_lounge')), 'open now');
  perform set_config('bl.test_offset_seconds', (7 * 3600)::text, true);
  perform pg_temp.assert(bl_place_open((select l from locations l where id = 'members_lounge')), 'open 7 hours later');
  perform set_config('bl.test_offset_seconds', (15 * 3600)::text, true);
  perform pg_temp.assert(bl_place_open((select l from locations l where id = 'members_lounge')), 'open 15 hours later');
  perform set_config('bl.test_offset_seconds', '', true);
  -- crowd + people
  perform pg_temp.assert(bl_crowd_count('lounge', 20, 2) = 9 and bl_crowd_count('lounge', 3, 2) = 3, 'crowd by hour');
  -- hype: a VIP cabana is announced like a club spend (and the switch turns it off)
  perform pg_temp.login(dee);
  update profiles set cash = 2000000, busy_until = null, busy_label = null, busy_started_at = null where id = dee;
  delete from place_announcements where user_id = dee;
  select count(*) into v_n from place_announcements where location_id = 'members_lounge';
  perform do_activity('lounge_vip_suite');
  perform pg_temp.assert((select count(*) from place_announcements where location_id = 'members_lounge') = v_n + 1, 'the VIP cabana is announced in the lounge');
  update game_config set value = 'false' where key = 'lounge.hype';
  update profiles set busy_until = null, busy_label = null, busy_started_at = null where id = dee;
  delete from place_announcements where user_id = dee;
  perform do_activity('lounge_vip_suite');
  perform pg_temp.assert(not exists (select 1 from place_announcements where location_id = 'members_lounge' and user_id = dee), 'hype switch off: no announcement');
  update game_config set value = 'true' where key = 'lounge.hype';
  -- music: a playlist can be assigned to the lounge, and it plays
  perform pg_temp.login(adm);
  insert into music_playlists (id, name) values (gen_random_uuid(), 'Lounge groove') returning id into v_pl;
  r := admin_music_assign('club', 'members_lounge', v_pl);
  perform pg_temp.assert((select playlist_id from locations where id = 'members_lounge') = v_pl, 'a playlist is assigned to the lounge');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(admin_music_overview()->'clubs') c where c->>'id' = 'members_lounge'), 'Admin -> Music lists the lounge');
  perform pg_temp.assert(pg_temp.hint_of($q$ select admin_music_assign('club', 'oba_market', null) $q$) = 'no_club', 'other places still refused');
  -- the map pin data
  perform pg_temp.assert((select x from locations where id = 'members_lounge') between 380 and 560 and (select y from locations where id = 'members_lounge') between 560 and 740, 'the pin sits in GRA');
  raise notice 'ok 13: gold tag, interior, hype, music';
end $$;
