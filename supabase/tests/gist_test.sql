-- Benin Gist (20261031000100_benin_gist.sql, 20261031000200_gist_links.sql; docs/GIST.md). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/gist_test.sql
-- Groups: 1 settings + labels, grants, RLS flags · 2 posts (clean, mask, tags, limits, new account, mute, ban, switch) · 3 photos ·
-- 4 likes (one per player) · 5 comments + one level of replies · 6 feed order, paging, following, tags · 7 blocks hide both ways ·
-- 8 tips · 9 reports, auto-hide, admin hide / delete / ban · 10 notifications (batching, mentions, push fold) ·
-- 11 groups (create, join, private, cap, roles, remove, mute, pin, leave) · 12 group messages (reply, delete, history, rate, voice, read state) ·
-- 13 group money · 14 discover + starter groups · 15 realtime RLS for gist_messages · 16 admin guards · 17 sweep + delete a player.

create or replace function pg_temp.gt_advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;

-- run a statement, return the error hint (or 'ok')
create or replace function pg_temp.gt_hint(p_sql text) returns text
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

create or replace function pg_temp.gt_u(p_name text) returns uuid
language sql as $$ select current_setting('gttest.' || lower(p_name))::uuid $$;

create or replace function pg_temp.gt_make(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@gist.bl');
begin
  perform set_config('gttest.' || lower(p_name), v::text, true);
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'female', '{"gender":"female"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  update profiles set created_at = bl_now() - interval '1 day', bank = 1000000, transfer_trusted = true,
                      last_seen = bl_now() - interval '1 hour' where id = v;
  return v;
end $$;

create or replace function pg_temp.gt_friends(a uuid, b uuid) returns void
language plpgsql as $$
begin
  perform pg_temp.login(a); perform social_add_friend(b);
  perform pg_temp.login(b); perform social_respond_friend(a, true);
end $$;

create or replace function pg_temp.gt_events(p_user uuid, p_kind text) returns int
language sql as $$ select count(*)::int from events where user_id = p_user and kind = p_kind $$;

do $$
declare k text;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  update game_config set value = 'false' where key = 'rent.enabled';
  update game_config set value = '0' where key = 'bank.transfer_cooldown_real_seconds';
  update game_config set value = '10000000' where key = 'bank.transfer_daily_limit';
  update game_config set value = '1000' where key = 'bank.transfer_daily_count';
  update game_config set value = 'true' where key = 'tips.enabled';
  update game_config set value = 'true' where key = 'gist.enabled';
  update game_config set value = 'false' where key = 'gist.photos_enabled';
  update game_config set value = '30' where key = 'gist.min_account_minutes';
  update game_config set value = '50' where key = 'gist.posts_per_hour';
  update game_config set value = '50' where key = 'gist.comments_per_minute';
  update game_config set value = '60' where key = 'gist.group_messages_per_minute';
  update game_config set value = '20' where key = 'gist.groups_per_day';
  update game_config set value = '200' where key = 'gist.group_member_cap';
  update game_config set value = 'true' where key = 'gist.add_friends_only';
  update game_config set value = '3' where key = 'gist.report_hide_count';
  update game_config set value = '12' where key = 'gist.hot_half_life_hours';
  update game_config set value = '30' where key = 'gist.notify_window_minutes';
  update game_config set value = '20' where key = 'gist.feed_page';
  update game_config set value = '60' where key = 'push.max_per_user_hour';
  -- start from an empty Gist (rolled back): a dev database may hold seeded demo data
  delete from gist_posts;
  delete from gist_messages;
  delete from gist_reports;
  delete from gist_bans;
  delete from gist_notify;
  delete from gist_cache;
  delete from gist_groups where not system;
  delete from gist_group_members;
  delete from gist_group_bans;
  update gist_groups set member_count = 0, last_msg_id = 0, last_msg_at = null, last_msg_user = null, last_msg_text = null, act_key = null, pinned_id = null, hidden = false;
  -- ---------- 1. settings, grants, RLS ----------
  foreach k in array array['gist.enabled','gist.photos_enabled','gist.photo_max_kb','gist.post_max_len','gist.comment_max_len','gist.message_max_len',
      'gist.min_account_minutes','gist.posts_per_hour','gist.comments_per_minute','gist.likes_per_minute','gist.group_messages_per_minute',
      'gist.groups_per_day','gist.group_member_cap','gist.max_groups_joined','gist.max_follows','gist.add_friends_only','gist.feed_page',
      'gist.hot_half_life_hours','gist.like_weight','gist.comment_weight','gist.group_half_life_hours','gist.report_hide_count','gist.post_keep_days',
      'gist.message_keep_days','gist.notify_window_minutes','gist.places'] loop
    perform pg_temp.assert(exists (select 1 from game_config where key = k and category = 'gist' and label <> '' and description <> '' and kind is not null),
                           'setting with label and description: ' || k);
  end loop;
  perform pg_temp.assert(not exists (select 1 from game_config where category = 'gist' and kind in ('number', 'minutes', 'naira', 'percent') and (min is null or max is null)),
                         'every numeric gist setting has min and max');
  perform pg_temp.assert((select value from game_config where key = 'gist.group_member_cap') = '200'::jsonb, 'default member cap 200');
  perform pg_temp.assert(bl_cfg_text('gist.places') ilike '%Ring Road%' and bl_cfg_text('gist.places') not ilike '%lagos%', 'real Benin places, never Lagos');
  foreach k in array array['gist_posts','gist_comments','gist_likes','gist_follows','gist_bans','gist_groups','gist_group_members','gist_group_bans',
                           'gist_messages','gist_reports','gist_notify','gist_cache'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || k)::regclass), 'RLS on: ' || k);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || k, 'insert'), 'no client insert: ' || k);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || k, 'update'), 'no client update: ' || k);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || k, 'delete'), 'no client delete: ' || k);
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || k, 'select'), 'no anon select: ' || k);
    perform pg_temp.assert(k = 'gist_messages' or not has_table_privilege('authenticated', 'public.' || k, 'select'), 'only messages are readable directly: ' || k);
  end loop;
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.gist_messages', 'select'), 'gist_messages select (the open group channel)');
  perform pg_temp.assert(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'gist_messages'), 'gist_messages in realtime');
  perform pg_temp.assert(not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename in ('gist_posts', 'gist_groups', 'gist_comments', 'gist_likes', 'gist_group_members')),
                         'no all-posts / all-groups realtime');
  foreach k in array array['gist_summary()','gist_post(text,text)','gist_feed(text,bigint,bigint,integer,text)','gist_like(bigint,boolean)',
      'gist_comment(bigint,text,bigint)','gist_tip_post(bigint,bigint,text)','gist_report(text,bigint,text)','gist_group_create(text,text,text,boolean)',
      'gist_group_send(bigint,text,text,text,bigint)','gist_group_send_money(bigint,text,bigint,text)','gist_group_history(bigint,bigint,integer)',
      'admin_gist_overview()','admin_gist_reports(text)','admin_gist_hide(text,bigint,boolean)','admin_gist_ban(uuid,boolean,integer,text,boolean)'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || k, 'execute'), 'authenticated can run ' || k);
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || k, 'execute'), 'anon cannot run ' || k);
  end loop;
  foreach k in array array['bl_gist_me(boolean)','bl_gist_notify(uuid,text,bigint,uuid,text,text,text,text,text,jsonb)','bl_gist_sweep()','bl_gist_rank(integer,integer,timestamptz)',
      'bl_gist_msg_json(public.gist_messages,uuid)','bl_gist_claim(text,interval)','bl_gist_message_add(public.gist_groups,public.profiles,text,text,text,text,bigint,uuid,text,bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', 'public.' || k, 'execute') and not has_function_privilege('anon', 'public.' || k, 'execute'),
                           'helper revoked from clients: ' || k);
  end loop;
  perform pg_temp.assert((select public and file_size_limit = 524288 and allowed_mime_types = array['image/jpeg','image/webp','image/png'] from storage.buckets where id = 'gist-photos'),
                         'gist-photos bucket: 512 KB, images only');
  raise notice 'ok 1: settings, grants, RLS';
end $$;

-- the cast
do $$
declare ada uuid; bayo uuid; chi uuid; dara uuid; efe uuid; femi uuid; adm uuid; newbie uuid;
begin
  ada := pg_temp.gt_make('GtAda'); bayo := pg_temp.gt_make('GtBayo'); chi := pg_temp.gt_make('GtChi'); dara := pg_temp.gt_make('GtDara');
  efe := pg_temp.gt_make('GtEfe'); femi := pg_temp.gt_make('GtFemi'); adm := pg_temp.gt_make('GtAdmin');
  update profiles set is_admin = true where id = adm;
  newbie := pg_temp.gt_make('GtNewbie');
  update profiles set created_at = bl_now() where id = newbie;
  perform pg_temp.gt_friends(ada, bayo);      -- Ada + Bayo are friends
  perform pg_temp.gt_friends(ada, dara);
  perform pg_temp.login(ada);
end $$;

-- ---------- 2. posts ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); newbie uuid := pg_temp.gt_u('gtnewbie'); bayo uuid := pg_temp.gt_u('gtbayo'); adm uuid := pg_temp.gt_u('gtadmin');
  r jsonb; p1 bigint;
begin
  perform pg_temp.login(ada);
  r := gist_summary();
  perform pg_temp.assert((r->>'enabled')::boolean and (r->>'can_post')::boolean and jsonb_array_length(r->'places') >= 8, 'summary: enabled, can post, places');
  r := gist_post('Wetin dey happen for #RingRoad today? Traffic is wild #traffic #RingRoad #uniben #extra');
  p1 := (r->>'id')::bigint;
  perform pg_temp.assert((r->'user'->>'username') = 'GtAda' and (r->>'likes')::int = 0 and (r->>'mine')::boolean, 'post json');
  perform pg_temp.assert((select tags from gist_posts where id = p1) = array['ringroad', 'traffic', 'uniben'], 'up to 3 distinct lower-case tags: ' || (select tags::text from gist_posts where id = p1));
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_post('   ')$q$) = 'empty', 'empty refused');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_post(%L)$q$, repeat('a', 281))) = 'too_long', 'too long refused');
  r := gist_post('You are a fucking legend');
  perform pg_temp.assert((r->>'body') not ilike '%fuck%' and (r->>'body') like '%*%', 'bad word masked: ' || (r->>'body'));
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_post('You are a   fucking   legend')$q$) = 'duplicate', 'same gist twice in 10 minutes refused');
  perform pg_temp.gt_advance(700);
  -- rate limit (posts per hour)
  update game_config set value = '3' where key = 'gist.posts_per_hour';
  perform gist_post('Third gist of the hour');
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_post('Fourth gist of the hour')$q$) = 'too_fast', 'posts per hour limit');
  perform pg_temp.gt_advance(3700);
  perform gist_post('A new hour, a new gist');
  update game_config set value = '50' where key = 'gist.posts_per_hour';
  -- new account wait: reading ok, writing refused
  perform pg_temp.login(newbie);
  update profiles set created_at = bl_now() where id = newbie;
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_post('hello world')$q$) = 'too_new', 'new account cannot post yet');
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_feed('foryou')$q$) = 'ok', 'new account can read: ' || pg_temp.gt_hint($q$select gist_feed('foryou')$q$));
  perform pg_temp.assert(not (gist_summary()->>'can_post')::boolean and gist_summary()->>'why_hint' = 'too_new', 'summary says why');
  update game_config set value = '0' where key = 'gist.min_account_minutes';
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_post('hello world, first gist')$q$) = 'ok', 'wait switched off: can post');
  update game_config set value = '30' where key = 'gist.min_account_minutes';
  -- chat mute (profiles.chat_muted_until) stops gist too
  perform pg_temp.login(bayo);
  update profiles set chat_muted_until = bl_now() + interval '10 minutes' where id = bayo;
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_post('muted gist')$q$) = 'muted', 'chat mute blocks posting');
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_group_send(1, 'hi')$q$) in ('muted', 'not_member'), 'chat mute blocks group chat');
  update profiles set chat_muted_until = null where id = bayo;
  -- master switch
  update game_config set value = 'false' where key = 'gist.enabled';
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_post('off gist')$q$) = 'gist_off', 'switch off: post refused');
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_feed('foryou')$q$) = 'gist_off', 'switch off: feed refused');
  perform pg_temp.assert(gist_summary()->>'why_hint' = 'gist_off' and not (gist_summary()->>'can_post')::boolean, 'switch off: summary');
  update game_config set value = 'true' where key = 'gist.enabled';
  -- banned from gist
  perform pg_temp.login(adm);
  perform admin_gist_ban(bayo, true, 2, 'spam', false);
  perform pg_temp.login(bayo);
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_post('banned gist')$q$) = 'gist_banned', 'gist ban blocks posting');
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_like(1)$q$) in ('gist_banned'), 'gist ban blocks liking');
  perform pg_temp.gt_advance(3 * 3600);
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_post('ban over, back again')$q$) = 'ok', 'timed ban expires');
  perform pg_temp.login(adm);
  perform admin_gist_ban(bayo, true, null, 'for good', false);
  perform pg_temp.assert(jsonb_array_length(admin_gist_bans()) = 1, 'ban list');
  perform admin_gist_ban(bayo, false);
  perform pg_temp.assert(jsonb_array_length(admin_gist_bans()) = 0, 'ban lifted');
  raise notice 'ok 2: posts';
end $$;

-- ---------- 3. photos ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); r jsonb; v_ok text; v_big text; v_other text;
begin
  perform pg_temp.login(ada);
  v_ok := ada || '/' || gen_random_uuid() || '.jpg';
  v_big := ada || '/' || gen_random_uuid() || '.jpg';
  v_other := pg_temp.gt_u('gtbayo') || '/' || gen_random_uuid() || '.jpg';
  insert into storage.objects (bucket_id, name, owner, metadata) values ('gist-photos', v_ok, ada, '{"size": 120000}'), ('gist-photos', v_big, ada, '{"size": 450000}'),
                                                                        ('gist-photos', v_other, pg_temp.gt_u('gtbayo'), '{"size": 1000}');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_post('with photo', %L)$q$, v_ok)) = 'photos_off', 'photos switch off by default');
  update game_config set value = 'true' where key = 'gist.photos_enabled';
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_post('x photo', %L)$q$, ada || '/not-a-uuid.jpg')) = 'bad_photo', 'bad path');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_post('x photo', %L)$q$, v_other)) = 'bad_photo', 'someone else''s folder refused');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_post('x photo', %L)$q$, ada || '/' || gen_random_uuid() || '.jpg')) = 'bad_photo', 'file that was never uploaded');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_post('x photo', %L)$q$, v_big)) = 'photo_too_big', 'photo over the size limit');
  r := gist_post('Fresh from Oba Market #obamarket', v_ok);
  perform pg_temp.assert(r->>'photo_path' = v_ok, 'photo post saved');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_post('again', %L)$q$, v_ok)) = 'bad_photo', 'a photo can only be used once');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_post(null, %L)$q$, ada || '/' || gen_random_uuid() || '.png')) = 'bad_photo', 'a photo-only gist still needs a real file');
  update game_config set value = 'false' where key = 'gist.photos_enabled';
  raise notice 'ok 3: photos';
end $$;

-- ---------- 4. likes ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); bayo uuid := pg_temp.gt_u('gtbayo'); chi uuid := pg_temp.gt_u('gtchi'); p bigint; p2 bigint; r jsonb;
begin
  delete from gist_posts; delete from gist_notify;
  perform pg_temp.login(ada);
  p := (gist_post('Likes test gist')->>'id')::bigint;
  perform set_config('gttest.p_like', p::text, true);
  perform pg_temp.login(bayo);
  r := gist_like(p);
  perform pg_temp.assert((r->>'liked')::boolean and (r->>'likes')::int = 1, 'liked once');
  r := gist_like(p);
  perform pg_temp.assert((r->>'likes')::int = 1 and (select count(*) from gist_likes where post_id = p) = 1, 'one like per player (liking twice changes nothing)');
  perform pg_temp.login(chi);
  r := gist_like(p);
  perform pg_temp.assert((r->>'likes')::int = 2, 'second player like');
  perform pg_temp.login(bayo);
  r := gist_like(p, false);
  perform pg_temp.assert(not (r->>'liked')::boolean and (r->>'likes')::int = 1, 'unlike');
  r := gist_like(p, false);
  perform pg_temp.assert((r->>'likes')::int = 1, 'unliking twice changes nothing');
  perform pg_temp.assert((select like_count from gist_posts where id = p) = (select count(*) from gist_likes where post_id = p), 'cached count matches');
  perform pg_temp.assert((select (x->>'liked')::boolean from jsonb_array_elements(gist_feed('new')->'posts') x where (x->>'id')::bigint = p) = false, 'feed shows my like state');
  perform pg_temp.login(chi);
  perform pg_temp.assert((select (x->>'liked')::boolean from jsonb_array_elements(gist_feed('new')->'posts') x where (x->>'id')::bigint = p) = true, 'feed shows liked');
  perform pg_temp.assert(pg_temp.gt_hint('select gist_like(999999)') = 'not_found', 'like a missing gist');
  update game_config set value = '1' where key = 'gist.likes_per_minute';
  perform pg_temp.login(ada);
  p2 := (gist_post('Second gist for the like limit')->>'id')::bigint;
  perform pg_temp.login(bayo);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_like(%s)', p)) = 'ok', 'first like in the minute');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_like(%s)', p2)) = 'too_fast', 'likes per minute limit');
  perform pg_temp.gt_advance(61);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_like(%s)', p2)) = 'ok', 'limit resets after a minute');
  update game_config set value = '40' where key = 'gist.likes_per_minute';
  raise notice 'ok 4: likes';
end $$;

-- ---------- 5. comments and replies ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); bayo uuid := pg_temp.gt_u('gtbayo'); chi uuid := pg_temp.gt_u('gtchi'); p bigint := current_setting('gttest.p_like')::bigint;
  c1 jsonb; c2 jsonb; c3 jsonb; r jsonb;
begin
  perform pg_temp.login(bayo);
  c1 := gist_comment(p, 'Nice one!')->'comment';
  perform pg_temp.assert((c1->>'parent_id') is null and (c1->'user'->>'username') = 'GtBayo', 'top-level comment');
  perform pg_temp.login(chi);
  c2 := gist_comment(p, 'I agree with Bayo', (c1->>'id')::bigint)->'comment';
  perform pg_temp.assert((c2->>'parent_id')::bigint = (c1->>'id')::bigint and c2->>'reply_to_name' = 'GtBayo', 'reply under the comment');
  perform pg_temp.login(ada);
  c3 := gist_comment(p, 'Thanks both', (c2->>'id')::bigint)->'comment';
  perform pg_temp.assert((c3->>'parent_id')::bigint = (c1->>'id')::bigint and c3->>'reply_to_name' = 'GtChi', 'a reply to a reply stays one level deep');
  perform pg_temp.assert((select comment_count from gist_posts where id = p) = 3, 'comment count cached');
  r := gist_comments(p);
  perform pg_temp.assert(jsonb_array_length(r->'comments') = 1 and jsonb_array_length(r->'comments'->0->'replies') = 2 and not (r->>'has_more')::boolean, 'comments with replies nested');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_comment(%s, '')$q$, p)) = 'empty', 'empty comment');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_comment(%s, %L)$q$, p, repeat('b', 201))) = 'too_long', 'long comment');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_comment(%s, 'hi', 999999)$q$, p)) = 'not_found', 'reply to a missing comment');
  -- paging of top-level comments
  perform pg_temp.login(bayo);
  perform gist_comment(p, 'second top comment'); perform gist_comment(p, 'third top comment');
  r := gist_comments(p, 0, 2);
  perform pg_temp.assert(jsonb_array_length(r->'comments') = 2 and (r->>'has_more')::boolean, 'comment page has more');
  r := gist_comments(p, (r->'comments'->1->>'id')::bigint, 2);
  perform pg_temp.assert(jsonb_array_length(r->'comments') = 1 and not (r->>'has_more')::boolean, 'comment page 2');
  -- rate limit
  update game_config set value = '3' where key = 'gist.comments_per_minute';
  perform pg_temp.login(chi);
  perform gist_comment(p, 'one'); perform gist_comment(p, 'two');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_comment(%s, 'three')$q$, p)) = 'too_fast', 'comments per minute limit');
  update game_config set value = '50' where key = 'gist.comments_per_minute';
  -- delete: author, post owner, nobody else
  perform pg_temp.login(bayo);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_delete_comment(%s)', (c2->>'id'))) = 'not_yours', 'not your comment');
  perform pg_temp.login(chi);
  r := gist_delete_comment((c2->>'id')::bigint);
  perform pg_temp.assert((r->>'comments')::int = (select count(*) from gist_comments where post_id = p), 'recount after delete');
  perform pg_temp.login(ada);
  r := gist_delete_comment((c1->>'id')::bigint);   -- post owner deletes Bayo's comment: its reply (Ada's) goes with it
  perform pg_temp.assert(not exists (select 1 from gist_comments where id = (c1->>'id')::bigint or parent_id = (c1->>'id')::bigint), 'replies go with their comment');
  perform pg_temp.assert((select comment_count from gist_posts where id = p) = (select count(*) from gist_comments where post_id = p), 'count equals rows');
  raise notice 'ok 5: comments';
end $$;

-- ---------- 6. feed order, paging, following, tags ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); bayo uuid := pg_temp.gt_u('gtbayo'); chi uuid := pg_temp.gt_u('gtchi'); dara uuid := pg_temp.gt_u('gtdara');
  efe uuid := pg_temp.gt_u('gtefe'); femi uuid := pg_temp.gt_u('gtfemi'); p1 bigint; p2 bigint; p3 bigint; p4 bigint; r jsonb; ids bigint[] := '{}'; k bigint; i bigint; n int := 0;
begin
  delete from gist_posts; delete from gist_notify;
  perform pg_temp.gt_advance(60);
  perform pg_temp.login(ada);  p1 := (gist_post('Oldest gist, will get likes #oba')->>'id')::bigint;
  perform pg_temp.gt_advance(3600);
  perform pg_temp.login(bayo); p2 := (gist_post('Middle gist, nobody cares')->>'id')::bigint;
  perform pg_temp.gt_advance(3600);
  perform pg_temp.login(chi);  p3 := (gist_post('Newest gist, also quiet #oba')->>'id')::bigint;
  -- 4 players like the oldest gist: ln(5) beats two hours of decay
  perform pg_temp.login(bayo); perform gist_like(p1);
  perform pg_temp.login(chi);  perform gist_like(p1);
  perform pg_temp.login(dara); perform gist_like(p1);
  perform pg_temp.login(efe);  perform gist_like(p1);
  perform pg_temp.login(femi);
  r := gist_feed('foryou');
  perform pg_temp.assert((select array_agg((x->>'id')::bigint order by ord) from jsonb_array_elements(r->'posts') with ordinality t(x, ord)) = array[p1, p3, p2],
                         'For you: liked gist first, then newest, then older');
  perform pg_temp.assert(r->'next' = 'null'::jsonb, 'no next cursor at the end');
  -- a comment counts more than a like and lifts the middle gist above the newest
  perform gist_comment(p2, 'first!'); perform pg_temp.login(efe); perform gist_comment(p2, 'second'); perform pg_temp.login(dara); perform gist_comment(p2, 'third');
  perform pg_temp.login(femi);
  r := gist_feed('foryou');
  perform pg_temp.assert((select array_agg((x->>'id')::bigint order by ord) from jsonb_array_elements(r->'posts') with ordinality t(x, ord)) = array[p2, p1, p3],
                         'three comments (worth 9 likes) lift the middle gist to the top');
  -- paging one by one gives the same order with no repeats
  for i in 1..5 loop
    r := gist_feed('foryou', k, case when i = 1 then null else (ids[array_length(ids, 1)]) end, 1);
    exit when jsonb_array_length(r->'posts') = 0;
    ids := ids || (r->'posts'->0->>'id')::bigint;
    exit when r->'next' = 'null'::jsonb;
    k := (r->'next'->>'key')::bigint;
  end loop;
  perform pg_temp.assert(array_length(ids, 1) = 3 and (select count(distinct x) from unnest(ids) x) = 3, 'paging with limit 1 returns every gist once: ' || ids::text);
  r := gist_feed('foryou', null, null, 2);
  perform pg_temp.assert(jsonb_array_length(r->'posts') = 2 and r->'next' <> 'null'::jsonb, 'page of 2 has a cursor');
  r := gist_feed('foryou', (r->'next'->>'key')::bigint, (r->'next'->>'id')::bigint, 2);
  perform pg_temp.assert(jsonb_array_length(r->'posts') = 1 and r->'next' = 'null'::jsonb, 'second page ends');
  -- newest first
  r := gist_feed('new');
  perform pg_temp.assert((select array_agg((x->>'id')::bigint order by ord) from jsonb_array_elements(r->'posts') with ordinality t(x, ord)) = array[p3, p2, p1], 'new = by id');
  r := gist_feed('new', null, p3);
  perform pg_temp.assert(jsonb_array_length(r->'posts') = 2, 'new: cursor by id');
  -- tags
  r := gist_feed('foryou', null, null, null, 'oba');
  perform pg_temp.assert(jsonb_array_length(r->'posts') = 2 and not exists (select 1 from jsonb_array_elements(r->'posts') x where (x->>'id')::bigint = p2), '#oba filter');
  -- following: me + friends + people I follow
  perform pg_temp.login(dara); p4 := (gist_post('Dara''s own gist')->>'id')::bigint;
  perform pg_temp.login(ada);
  r := gist_feed('following');
  perform pg_temp.assert((select array_agg((x->>'id')::bigint order by ord) from jsonb_array_elements(r->'posts') with ordinality t(x, ord)) = array[p4, p2, p1],
                         'Following = me + friends (Bayo, Dara), not Chi: ' || (select array_agg((x->>'id')::bigint order by ord)::text from jsonb_array_elements(r->'posts') with ordinality t(x, ord)));
  perform gist_follow(chi);
  r := gist_feed('following');
  perform pg_temp.assert(jsonb_array_length(r->'posts') = 4, 'following Chi adds her gist');
  perform gist_follow(chi, false);
  perform pg_temp.assert(jsonb_array_length(gist_feed('following')->'posts') = 3, 'unfollow');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_follow(%L)', ada)) = 'self', 'cannot follow yourself');
  -- profile + a user's posts
  r := gist_profile(chi);
  perform pg_temp.assert((r->>'posts')::int = 1 and (r->>'followers')::int = 0 and r->>'friend_status' = 'none' and not (r->>'i_follow')::boolean, 'profile card');
  perform pg_temp.assert(jsonb_array_length(gist_user_posts(bayo)->'posts') = 1, 'user posts');
  perform pg_temp.assert(gist_profile(bayo)->>'friend_status' = 'friend', 'profile knows friends');
  perform pg_temp.assert(jsonb_array_length(gist_trending()) >= 1 and gist_trending()->0->>'tag' = 'oba', 'trending tag');
  raise notice 'ok 6: feed';
end $$;

-- ---------- 7. blocks hide content both ways ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); bayo uuid := pg_temp.gt_u('gtbayo'); chi uuid := pg_temp.gt_u('gtchi'); pb bigint; pa bigint; cb jsonb; r jsonb;
begin
  delete from gist_posts;
  perform pg_temp.login(ada);  pa := (gist_post('Ada post for block test')->>'id')::bigint;
  perform pg_temp.login(bayo); pb := (gist_post('Bayo post for block test')->>'id')::bigint;
  perform pg_temp.login(chi);  perform gist_comment(pa, 'Chi comment visible to all');
  perform pg_temp.login(bayo); cb := gist_comment(pa, 'Bayo comment on Ada''s post')->'comment';
  perform pg_temp.login(ada);
  perform pg_temp.assert(jsonb_array_length(gist_feed('new')->'posts') = 2, 'before the block Ada sees both');
  perform chat_block(bayo);
  perform pg_temp.assert(jsonb_array_length(gist_feed('new')->'posts') = 1 and jsonb_array_length(gist_feed('foryou')->'posts') = 1, 'Ada blocked Bayo: his gist is gone from her feed');
  perform pg_temp.assert(jsonb_array_length(gist_comments(pa)->'comments') = 1, 'his comment is hidden from Ada');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_post_get(%s)', pb)) = 'not_found', 'cannot open his gist');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_like(%s)', pb)) = 'not_found', 'cannot like his gist');
  perform pg_temp.assert(jsonb_array_length(gist_user_posts(bayo)->'posts') = 0, 'his profile shows no gists');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_profile(%L)', bayo)) = 'not_found', 'his profile is closed');
  perform pg_temp.login(bayo);
  perform pg_temp.assert(jsonb_array_length(gist_feed('new')->'posts') = 1 and (gist_feed('new')->'posts'->0->>'id')::bigint = pb, 'Bayo no longer sees Ada''s gist (hidden both ways)');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_comment(%s, 'hello?')$q$, pa)) = 'not_found', 'Bayo cannot comment on Ada''s gist');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_tip_post(%s, 500)$q$, pa)) = 'not_found', 'Bayo cannot tip her either');
  perform pg_temp.login(ada);
  perform chat_unblock(bayo);
  perform pg_temp.assert(jsonb_array_length(gist_feed('new')->'posts') = 2, 'unblock brings it back');
  raise notice 'ok 7: blocks';
end $$;

-- ---------- 8. tips ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); bayo uuid := pg_temp.gt_u('gtbayo'); pa bigint; r jsonb; b0 bigint; a0 bigint;
begin
  delete from gist_posts;
  perform pg_temp.login(ada); pa := (gist_post('Tip me please')->>'id')::bigint;
  perform pg_temp.login(bayo);
  select bank into b0 from profiles where id = bayo; select bank into a0 from profiles where id = ada;
  r := gist_tip_post(pa, 1500, 'Good one');
  perform pg_temp.assert((r->>'tip_total')::bigint = 1500 and (r->>'tips')::int = 1 and (r->>'amount')::bigint = 1500, 'tip result');
  perform pg_temp.assert((select bank from profiles where id = ada) = a0 + 1500, 'poster bank +1500');
  perform pg_temp.assert((select bank from profiles where id = bayo) <= b0 - 1500, 'tipper paid (plus any fee)');
  perform pg_temp.assert((select tip_total from gist_posts where id = pa) = 1500 and (select tip_count from gist_posts where id = pa) = 1, 'cached tip totals');
  perform pg_temp.assert((select count(*) from tips where from_user = bayo and to_user = ada and amount = 1500) = 1, 'tips row (tip_player)');
  perform pg_temp.assert(pg_temp.gt_events(ada, 'tip_in') = 1, 'poster gets the tip event');
  perform pg_temp.assert((gist_feed('new')->'posts'->0->>'tip_total')::bigint = 1500, 'feed shows tip total');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_tip_post(%s, 50)', pa)) = 'too_small', 'tip_player minimum applies');
  perform pg_temp.login(ada);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_tip_post(%s, 500)', pa)) = 'self', 'no self tips');
  perform pg_temp.assert(pg_temp.gt_hint('select gist_tip_post(999999, 500)') = 'not_found', 'tip a missing gist');
  raise notice 'ok 8: tips';
end $$;

-- ---------- 9. reports, auto-hide, admin ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); bayo uuid := pg_temp.gt_u('gtbayo'); chi uuid := pg_temp.gt_u('gtchi'); dara uuid := pg_temp.gt_u('gtdara'); adm uuid := pg_temp.gt_u('gtadmin');
  p bigint; c bigint; r jsonb; v_list jsonb;
begin
  delete from gist_posts;
  perform pg_temp.login(ada); p := (gist_post('Report me')->>'id')::bigint;
  perform pg_temp.login(chi); c := (gist_comment(p, 'rude comment')->'comment'->>'id')::bigint;
  perform pg_temp.login(bayo);
  r := gist_report('post', p, 'spam');
  perform pg_temp.assert((r->>'reports')::int = 1 and not (r->>'hidden')::boolean, 'first report');
  r := gist_report('post', p, 'spam again');
  perform pg_temp.assert((r->>'reports')::int = 1, 'one report per player');
  perform pg_temp.login(ada);
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_report('post', %s, 'x')$q$, p)) = 'self', 'cannot report yourself');
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_report('post', 999999, 'x')$q$) = 'not_found', 'report a missing gist');
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_report('nonsense', 1, 'x')$q$) = 'bad_kind', 'bad kind');
  perform pg_temp.login(chi);  r := gist_report('post', p, 'bad');
  perform pg_temp.assert((r->>'reports')::int = 2 and not (r->>'hidden')::boolean, 'two reports');
  perform pg_temp.login(dara); r := gist_report('post', p, 'bad');
  perform pg_temp.assert((r->>'reports')::int = 3 and (r->>'hidden')::boolean, 'three reports hide the gist');
  perform pg_temp.assert(jsonb_array_length(gist_feed('new')->'posts') = 0, 'hidden gist leaves the feed');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_post_get(%s)', p)) = 'not_found', 'hidden gist cannot be opened');
  -- comment report
  perform pg_temp.login(bayo);
  update game_config set value = '1' where key = 'gist.report_hide_count';
  perform pg_temp.login(adm); p := (gist_post('Admin gist for comments')->>'id')::bigint;
  perform pg_temp.login(chi); c := (gist_comment(p, 'rude comment two')->'comment'->>'id')::bigint;
  perform pg_temp.login(bayo); r := gist_report('comment', c, 'rude');
  perform pg_temp.assert((r->>'hidden')::boolean and jsonb_array_length(gist_comments(p)->'comments') = 0, 'reported comment hidden');
  update game_config set value = '3' where key = 'gist.report_hide_count';
  -- admin list, hide, delete, dismiss
  perform pg_temp.login(adm);
  v_list := admin_gist_reports('open');
  perform pg_temp.assert(jsonb_array_length(v_list) = 2, 'admin sees 2 reported targets: ' || jsonb_array_length(v_list));
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v_list) x where x->>'kind' = 'post' and (x->>'reports')::int = 3 and x->'content'->>'text' = 'Report me'), 'report row has reporters count and preview');
  perform pg_temp.assert((admin_gist_overview()->>'open_reports')::int = 2 and (admin_gist_overview()->>'hidden_posts')::int = 1, 'overview counts');
  r := admin_gist_hide('post', (select (x->>'target_id')::bigint from jsonb_array_elements(v_list) x where x->>'kind' = 'post'), false);
  perform pg_temp.assert(not (r->>'hidden')::boolean and (select not hidden from gist_posts where user_id = ada), 'admin unhide');
  r := admin_gist_hide('post', (select id from gist_posts where user_id = ada), true);
  perform pg_temp.assert((select hidden from gist_posts where user_id = ada) and (select count(*) from gist_reports where status = 'open' and kind = 'post') = 0, 'admin hide closes the reports');
  perform admin_gist_dismiss('comment', c);
  perform pg_temp.assert(jsonb_array_length(admin_gist_reports('open')) = 0, 'dismissed');
  perform pg_temp.assert(jsonb_array_length(admin_gist_reports('all')) = 2, 'all shows done ones');
  perform admin_gist_delete('comment', c);
  perform pg_temp.assert((select comment_count from gist_posts where id = p) = 0 and not exists (select 1 from gist_comments where id = c), 'admin delete comment recounts');
  perform admin_gist_delete('post', (select id from gist_posts where user_id = ada));
  perform pg_temp.assert(not exists (select 1 from gist_posts where user_id = ada), 'admin delete post');
  perform pg_temp.assert(exists (select 1 from admin_audit where action in ('gist_hide', 'gist_delete', 'gist_dismiss', 'gist_ban')), 'admin actions are in the audit log');
  -- ban + hide all
  perform pg_temp.login(chi); perform gist_post('Chi spam one'); perform gist_post('Chi spam two');
  perform pg_temp.login(adm);
  perform admin_gist_ban(chi, true, 24, 'spam', true);
  perform pg_temp.assert(not exists (select 1 from gist_posts where user_id = chi and not hidden), 'ban with hide removes her gists from view');
  perform pg_temp.login(chi);
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_post('still here?')$q$) = 'gist_banned', 'banned can not post');
  perform pg_temp.login(adm); perform admin_gist_ban(chi, false);
  raise notice 'ok 9: reports and admin';
end $$;

-- ---------- 10. notifications ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); bayo uuid := pg_temp.gt_u('gtbayo'); chi uuid := pg_temp.gt_u('gtchi'); dara uuid := pg_temp.gt_u('gtdara');
  efe uuid := pg_temp.gt_u('gtefe'); femi uuid := pg_temp.gt_u('gtfemi'); p bigint; v_title text; v_n int; row_ push_outbox; cm jsonb;
begin
  delete from gist_posts; delete from gist_notify; delete from events where user_id = ada;
  insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (ada, 'https://push.example.test/gt-ada', repeat('A', 87), repeat('B', 22));
  insert into push_prefs (user_id, master, messages, money, friends, events) values (ada, true, true, true, true, true)
    on conflict (user_id) do update set master = true, messages = true, friends = true, events = true;
  delete from push_outbox where user_id = ada;
  perform pg_temp.login(ada); p := (gist_post('Notify me about this one')->>'id')::bigint;
  perform pg_temp.login(bayo); perform gist_like(p);
  perform pg_temp.assert(pg_temp.gt_events(ada, 'gist_like') = 1, 'first like: one event');
  select title into v_title from events where user_id = ada and kind = 'gist_like';
  perform pg_temp.assert(v_title = '@GtBayo liked your gist', 'first like says who: ' || v_title);
  perform pg_temp.login(chi);  perform gist_like(p);
  perform pg_temp.login(dara); perform gist_like(p);
  perform pg_temp.login(efe);  perform gist_like(p);
  perform pg_temp.login(femi); perform gist_like(p);
  perform pg_temp.assert(pg_temp.gt_events(ada, 'gist_like') = 1, 'five likes inside the window stay ONE event');
  select title, (data->>'n')::int into v_title, v_n from events where user_id = ada and kind = 'gist_like';
  perform pg_temp.assert(v_title = '5 people liked your gist' and v_n = 5, 'batched title: ' || v_title);
  -- push: one pending row that folded
  perform pg_temp.assert((select count(*) from push_outbox where user_id = ada and kind = 'gist_like') = 1, 'one push row for five likes');
  select * into row_ from push_outbox where user_id = ada and kind = 'gist_like';
  perform pg_temp.assert(row_.count = 5 and row_.title = '5 people liked your gist' and row_.category = 'events' and row_.url = '/play?go=gist:post:' || p, 'push folded: ' || row_.title || ' ' || row_.url);
  -- after the window a new like is a new alert
  perform pg_temp.gt_advance(31 * 60);
  perform pg_temp.login(bayo); perform gist_like(p, false); perform gist_like(p);
  perform pg_temp.assert(pg_temp.gt_events(ada, 'gist_like') = 2, 'a like after the window opens a new alert');
  -- liking your own gist tells nobody
  perform pg_temp.login(ada); perform gist_like(p);
  perform pg_temp.assert(pg_temp.gt_events(ada, 'gist_like') = 2, 'own like: no alert');
  -- comments: batched, replies and mentions
  delete from events where user_id in (ada, bayo, dara);
  perform pg_temp.login(bayo); cm := gist_comment(p, 'Nice gist')->'comment';
  perform pg_temp.login(chi);  perform gist_comment(p, 'Totally agree', (cm->>'id')::bigint);
  perform pg_temp.assert(pg_temp.gt_events(ada, 'gist_comment') = 1 and (select title from events where user_id = ada and kind = 'gist_comment') = '2 new comments on your gist',
                         'two comments = one alert that counts up');
  perform pg_temp.assert(pg_temp.gt_events(bayo, 'gist_reply') = 1, 'the person replied to gets an alert');
  perform pg_temp.login(dara); perform gist_comment(p, 'Hey @GtAda and @GtEfe look at this');
  perform pg_temp.assert(pg_temp.gt_events(efe, 'gist_mention') = 1, 'a mention alerts the person');
  perform pg_temp.assert(pg_temp.gt_events(ada, 'gist_mention') = 0 and (select title from events where user_id = ada and kind = 'gist_comment') = '3 new comments on your gist',
                         'the gist owner gets the comment alert, not a second mention alert');
  perform pg_temp.assert(pg_temp.gt_events(dara, 'gist_mention') = 0, 'no alert for yourself');
  perform pg_temp.login(bayo); perform gist_post('Big shout to @GtDara for the help');
  perform pg_temp.assert(pg_temp.gt_events(dara, 'gist_mention') = 1, 'mention in a gist');
  -- blocked: no alert
  perform pg_temp.login(ada); perform chat_block(femi);
  delete from events where user_id = ada;
  perform pg_temp.login(femi); perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_comment(%s, 'hi')$q$, p)) = 'not_found', 'blocked player cannot comment');
  perform pg_temp.login(ada); perform chat_unblock(femi);
  -- push respects the category switch
  delete from push_outbox where user_id = ada;
  update push_prefs set events = false where user_id = ada;
  perform pg_temp.gt_advance(31 * 60);
  perform pg_temp.login(dara); perform gist_like(p, false); perform gist_like(p);
  perform pg_temp.assert((select count(*) from push_outbox where user_id = ada) = 0, 'category off: no push (the alert still shows in the game)');
  perform pg_temp.assert(pg_temp.gt_events(ada, 'gist_like') >= 1, 'alert exists');
  update push_prefs set events = true where user_id = ada;
  -- active players are not pushed (they see it live)
  perform pg_temp.gt_advance(31 * 60);
  update profiles set last_seen = bl_now() where id = ada;
  perform pg_temp.login(efe); perform gist_like(p, false); perform gist_like(p);
  perform pg_temp.assert((select count(*) from push_outbox where user_id = ada) = 0, 'active player: no push');
  update profiles set last_seen = bl_now() - interval '1 hour' where id = ada;
  raise notice 'ok 10: notifications';
end $$;

-- ---------- 11. groups ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); bayo uuid := pg_temp.gt_u('gtbayo'); chi uuid := pg_temp.gt_u('gtchi'); dara uuid := pg_temp.gt_u('gtdara');
  adm uuid := pg_temp.gt_u('gtadmin'); g jsonb; gid bigint; priv bigint; r jsonb; m jsonb;
begin
  perform pg_temp.login(ada);
  g := gist_group_create('Ugbowo Gist Hub', '🎓', 'Campus gist and more', true);
  gid := (g->>'id')::bigint;
  perform set_config('gttest.g_pub', gid::text, true);
  perform pg_temp.assert(g->>'role' = 'owner' and (g->>'members')::int = 1 and (g->>'is_public')::boolean and (g->>'cap')::int = 200, 'owner created a public group');
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_group_create('ab')$q$) = 'bad_name', 'name too short');
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_group_create('Fuck this group')$q$) = 'bad_name', 'bad word in a name');
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_group_create('benin gist general')$q$) = 'name_taken', 'cannot copy an official name');
  update game_config set value = '2' where key = 'gist.groups_per_day';
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_group_create('Second group of the day')$q$) = 'ok', 'second group ok');
  perform pg_temp.assert(pg_temp.gt_hint($q$select gist_group_create('Third group of the day')$q$) = 'too_many', 'groups per day limit');
  update game_config set value = '20' where key = 'gist.groups_per_day';
  g := gist_group_create('Secret Club', '🤫', 'Invite only', false);
  priv := (g->>'id')::bigint;
  perform set_config('gttest.g_priv', priv::text, true);
  -- public join, private is invite-only
  perform pg_temp.login(bayo);
  perform pg_temp.assert(gist_group_join(gid)->>'role' = 'member', 'Bayo joined the public group');
  perform pg_temp.assert(gist_group_join(gid)->>'role' = 'member' and (select member_count from gist_groups where id = gid) = 2, 'joining twice is harmless');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_join(%s)', priv)) = 'not_found', 'private group cannot be joined');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_get(%s)', priv)) = 'not_found', 'private group is invisible to non-members');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_history(%s)', priv)) = 'not_member', 'private history is closed');
  -- add: friends only
  perform pg_temp.login(ada);
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_add(%s, 'GtChi')$q$, priv)) = 'not_friend', 'only friends can be added');
  r := gist_group_add(priv, 'GtBayo');
  perform pg_temp.assert((select member_count from gist_groups where id = priv) = 2, 'friend added to the private group');
  perform pg_temp.assert(pg_temp.gt_events(bayo, 'gist_group_add') = 1, 'added player is told');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_add(%s, 'GtBayo')$q$, priv)) = 'already', 'already in');
  perform pg_temp.login(bayo);
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_add(%s, 'GtDara')$q$, priv)) = 'not_admin', 'members cannot add');
  perform pg_temp.assert(jsonb_array_length(gist_groups_mine()) = 2, 'my groups list');
  -- member cap
  perform pg_temp.login(ada);
  update game_config set value = '2' where key = 'gist.group_member_cap';
  perform pg_temp.login(chi);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_join(%s)', gid)) = 'full', 'member cap');
  perform pg_temp.login(ada);
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_add(%s, 'GtDara')$q$, gid)) = 'full', 'cap applies to add too');
  update game_config set value = '200' where key = 'gist.group_member_cap';
  perform pg_temp.login(chi); perform gist_group_join(gid);
  -- roles
  perform pg_temp.login(ada);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_set_role(%s, %L, %L)', gid, bayo, 'admin')) = 'ok', 'owner makes Bayo admin');
  perform pg_temp.login(bayo);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_set_role(%s, %L, %L)', gid, chi, 'admin')) = 'not_admin', 'admins cannot make admins');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_mute(%s, %L, 60)', gid, ada)) = 'not_allowed', 'cannot mute the owner');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_remove(%s, %L)', gid, ada)) = 'not_allowed', 'cannot remove the owner');
  perform pg_temp.login(chi);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_mute(%s, %L, 60)', gid, bayo)) = 'not_admin', 'member cannot mute');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_remove(%s, %L)', gid, bayo)) = 'not_admin', 'member cannot remove');
  -- mute
  perform pg_temp.login(bayo);
  r := gist_group_mute(gid, chi, 30);
  perform pg_temp.assert(r->>'muted_until' is not null, 'muted');
  perform pg_temp.login(chi);
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, 'can I talk?')$q$, gid)) = 'muted_group', 'muted member cannot send');
  perform pg_temp.assert((select jsonb_array_length(gist_group_history(gid))) >= 0, 'muted member can still read');
  perform pg_temp.gt_advance(31 * 60);
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, 'mute is over')$q$, gid)) = 'ok', 'mute expires by itself');
  perform pg_temp.login(bayo); perform gist_group_mute(gid, chi, 30); perform gist_group_mute(gid, chi, 0);
  perform pg_temp.assert((select muted_until from gist_group_members where group_id = gid and user_id = chi) is null, 'unmute');
  -- update
  r := gist_group_update(gid, 'Ugbowo Gist Hub 2', '📚', 'New description', false);
  perform pg_temp.assert(r->>'name' = 'Ugbowo Gist Hub 2' and (r->>'is_public')::boolean, 'admin can edit but not flip public (owner only)');
  perform pg_temp.login(ada);
  r := gist_group_update(gid, null, null, null, false);
  perform pg_temp.assert(not (r->>'is_public')::boolean, 'owner can make it private');
  r := gist_group_update(gid, null, null, null, true);
  -- remove = out and cannot rejoin
  perform pg_temp.login(bayo);
  r := gist_group_remove(gid, chi);
  perform pg_temp.assert(not exists (select 1 from gist_group_members where group_id = gid and user_id = chi), 'removed');
  perform pg_temp.login(chi);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_join(%s)', gid)) = 'removed', 'removed members cannot rejoin on their own');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_history(%s)', gid)) = 'not_member', 'removed members cannot read');
  perform pg_temp.login(ada);
  update game_config set value = 'false' where key = 'gist.add_friends_only';
  perform gist_group_add(gid, 'GtChi');
  perform pg_temp.assert(exists (select 1 from gist_group_members where group_id = gid and user_id = chi), 'adding lifts the removal');
  update game_config set value = 'true' where key = 'gist.add_friends_only';
  -- leave, owner hand-over, delete
  perform pg_temp.login(ada);
  perform gist_group_leave(gid);
  perform pg_temp.assert((select owner_id from gist_groups where id = gid) = bayo and (select role from gist_group_members where group_id = gid and user_id = bayo) = 'owner',
                         'the owner leaves: the admin becomes owner');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_delete(%s)', gid)) = 'not_admin', 'only the owner deletes');
  perform pg_temp.login(bayo);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_delete(%s)', gid)) = 'ok', 'owner deletes the group');
  perform pg_temp.assert(not exists (select 1 from gist_groups where id = gid), 'group is gone');
  -- re-create the public group for the next sections
  perform pg_temp.login(ada);
  g := gist_group_create('Ugbowo Gist Hub', '🎓', 'Campus gist and more', true); gid := (g->>'id')::bigint;
  perform set_config('gttest.g_pub', gid::text, true);
  perform pg_temp.login(bayo); perform gist_group_join(gid);
  perform pg_temp.login(chi); perform gist_group_join(gid);
  perform pg_temp.login(ada); perform gist_group_set_role(gid, bayo, 'admin');
  raise notice 'ok 11: groups';
end $$;

-- ---------- 12. group messages ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); bayo uuid := pg_temp.gt_u('gtbayo'); chi uuid := pg_temp.gt_u('gtchi'); dara uuid := pg_temp.gt_u('gtdara');
  gid bigint := current_setting('gttest.g_pub')::bigint; m1 jsonb; m2 jsonb; m3 jsonb; r jsonb; v_path text; i int; v_first bigint;
begin
  delete from events where user_id in (ada, bayo, chi);
  perform pg_temp.login(ada);
  m1 := gist_group_send(gid, 'Welcome to the hub o');
  perform pg_temp.assert(m1->>'kind' = 'text' and (m1->>'mine')::boolean and m1->>'username' = 'GtAda', 'sent');
  perform pg_temp.login(bayo);
  m2 := gist_group_send(gid, 'Thanks Ada', null, null, (m1->>'id')::bigint);
  perform pg_temp.assert((m2->'reply'->>'username') = 'GtAda' and (m2->'reply'->>'snippet') = 'Welcome to the hub o', 'reply keeps a preview');
  perform pg_temp.assert(pg_temp.gt_events(ada, 'gist_group_reply') = 1, 'a reply alerts the person');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, 'x', null, null, 999999)$q$, gid)) = 'bad_reply', 'reply to a missing message');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, '   ')$q$, gid)) = 'empty', 'empty message');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, %L)$q$, gid, repeat('c', 501))) = 'too_long', 'long message');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, 'Thanks Ada')$q$, gid)) = 'duplicate', 'duplicate within 30 s');
  r := gist_group_send(gid, 'You are a fucking star');
  perform pg_temp.assert(r->>'body' not ilike '%fuck%', 'group messages are masked');
  perform pg_temp.login(dara);
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, 'let me in')$q$, gid)) = 'not_member', 'non-members cannot send');
  -- mention alert (members only)
  perform pg_temp.login(bayo);
  perform gist_group_send(gid, 'Hello @GtChi and @GtDara');
  perform pg_temp.assert(pg_temp.gt_events(chi, 'gist_group_reply') = 1 and pg_temp.gt_events(dara, 'gist_group_reply') = 0, 'mention alerts members only');
  -- plain messages do not alert anybody
  delete from events where user_id = chi; delete from push_outbox where user_id = chi;
  perform pg_temp.gt_advance(40);
  perform gist_group_send(gid, 'Just a normal message');
  perform pg_temp.assert(pg_temp.gt_events(chi, 'gist_group_reply') = 0 and not exists (select 1 from push_outbox where user_id = chi), 'no alert or push for every group message');
  -- history, paging
  for i in 1..8 loop perform pg_temp.gt_advance(40); perform gist_group_send(gid, 'Filler message number ' || i); end loop;
  perform pg_temp.login(chi);
  r := gist_group_history(gid, null, 5);
  perform pg_temp.assert(jsonb_array_length(r) = 5 and (r->4->>'body') = 'Filler message number 8', 'history: latest 5, oldest first');
  v_first := (r->0->>'id')::bigint;
  r := gist_group_history(gid, v_first, 50);
  perform pg_temp.assert(jsonb_array_length(r) = (select count(*) from gist_messages where group_id = gid and id < v_first), 'older page');
  perform pg_temp.assert((r->0->>'id')::bigint < (r->1->>'id')::bigint, 'older page is oldest first');
  perform pg_temp.assert(jsonb_array_length(gist_group_after(gid, v_first - 1)) = (select count(*) from gist_messages where group_id = gid and id >= v_first), 'after = poll catch-up');
  -- read state
  perform pg_temp.login(dara); perform gist_group_join(gid);
  perform pg_temp.login(bayo); perform gist_group_send(gid, 'Dara will have one unread');
  perform pg_temp.login(dara);
  perform pg_temp.assert((gist_summary()->>'unread_groups')::int = 1, 'summary: one unread group');
  perform pg_temp.assert((select (x->>'unread')::int from jsonb_array_elements(gist_groups_mine()) x where (x->>'id')::bigint = gid) = 1, 'group row: 1 unread');
  perform gist_group_mark_read(gid);
  perform pg_temp.assert((gist_summary()->>'unread_groups')::int = 0, 'mark read clears it');
  perform pg_temp.login(bayo); perform gist_group_send(gid, 'one more for Dara');
  perform pg_temp.login(dara);
  perform pg_temp.assert((gist_summary()->>'unread_groups')::int = 1, 'new message = unread again');
  perform pg_temp.login(bayo);
  perform pg_temp.assert((gist_summary()->>'unread_groups')::int = 0, 'my own messages are never unread');
  -- pin (admin), unpin; members cannot
  r := gist_group_send(gid, 'Rules: be kind');
  perform gist_group_pin(gid, (r->>'id')::bigint);
  perform pg_temp.assert((gist_group_get(gid)->'pinned'->>'body') = 'Rules: be kind', 'pinned message shows on the group');
  perform pg_temp.login(chi);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_pin(%s, %s)', gid, (r->>'id'))) = 'not_admin', 'members cannot pin');
  perform pg_temp.login(ada);
  perform gist_group_pin(gid, null);
  perform pg_temp.assert((gist_group_get(gid)->'pinned') = 'null'::jsonb, 'unpin');
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_pin(%s, 999999)', gid)) = 'not_found', 'pin a missing message');
  -- delete for everyone: author / admin, not other members
  perform pg_temp.login(chi);
  m3 := gist_group_send(gid, 'Oops wrong group');
  perform pg_temp.login(dara);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_delete_message(%s)', (m3->>'id'))) = 'not_author', 'a member cannot delete someone else''s message');
  perform pg_temp.login(chi);
  r := gist_group_delete_message((m3->>'id')::bigint);
  perform pg_temp.assert((select deleted_at is not null and body is null from gist_messages where id = (m3->>'id')::bigint), 'tombstone: body cleared');
  perform pg_temp.assert((select (x->>'deleted_at') is not null from jsonb_array_elements(gist_group_history(gid, null, 5)) x where (x->>'id')::bigint = (m3->>'id')::bigint), 'history shows the tombstone');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, 'reply to deleted', null, null, %s)$q$, gid, (m3->>'id'))) = 'bad_reply', 'cannot reply to a deleted message');
  perform pg_temp.login(chi); m3 := gist_group_send(gid, 'Old message');
  update gist_messages set created_at = bl_now() - interval '3 days' where id = (m3->>'id')::bigint;
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_delete_message(%s)', (m3->>'id'))) = 'too_late', 'too late to delete for everyone');
  perform pg_temp.login(bayo);
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_delete_message(%s)', (m3->>'id'))) = 'ok', 'a group admin can delete any message');
  -- voice notes
  perform pg_temp.login(chi);
  v_path := 'group/' || gid || '/' || chi || '/' || gen_random_uuid() || '.webm';
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, null, %L, 'audio/webm')$q$, gid, v_path)) = 'audio_missing', 'voice file must exist');
  insert into storage.objects (bucket_id, name, owner) values ('player-voice', v_path, chi);
  r := gist_group_send(gid, null, v_path, 'audio/webm');
  perform pg_temp.assert(r->>'kind' = 'voice' and r->>'audio_path' = v_path, 'voice note sent');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, null, %L, 'audio/webm')$q$, gid, v_path)) = 'bad_audio', 'a voice file is used once');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, null, %L, 'audio/webm')$q$, gid, 'group/' || gid || '/' || bayo || '/' || gen_random_uuid() || '.webm')) = 'bad_audio', 'voice path must be mine');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, null, %L, 'text/plain')$q$, gid, v_path)) = 'bad_audio', 'voice mime');
  -- rate limit
  update game_config set value = '3' where key = 'gist.group_messages_per_minute';
  perform pg_temp.gt_advance(120);
  perform pg_temp.login(dara);
  perform gist_group_send(gid, 'r1'); perform gist_group_send(gid, 'r2'); perform gist_group_send(gid, 'r3');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, 'r4')$q$, gid)) = 'too_fast', 'group messages per minute limit');
  update game_config set value = '60' where key = 'gist.group_messages_per_minute';
  -- report a message: hides at the threshold
  perform pg_temp.login(bayo); m3 := gist_group_send(gid, 'A reportable message');
  perform pg_temp.login(ada); r := gist_report('message', (m3->>'id')::bigint, 'spam');
  perform pg_temp.login(chi); r := gist_report('message', (m3->>'id')::bigint, 'spam');
  perform pg_temp.login(dara); r := gist_report('message', (m3->>'id')::bigint, 'spam');
  perform pg_temp.assert((r->>'hidden')::boolean and (select hidden from gist_messages where id = (m3->>'id')::bigint), 'three reports hide a message');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(gist_group_history(gid, null, 60)) x where (x->>'id')::bigint = (m3->>'id')::bigint), 'hidden message is not in history');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_report('message', %s, 'x')$q$, (select min(id) from gist_messages where group_id = gid and user_id = bayo and not hidden and deleted_at is null))) = 'ok', 'can report a message in my group');
  raise notice 'ok 12: group messages';
end $$;

-- ---------- 13. group money ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); bayo uuid := pg_temp.gt_u('gtbayo'); chi uuid := pg_temp.gt_u('gtchi'); dara uuid := pg_temp.gt_u('gtdara'); efe uuid := pg_temp.gt_u('gtefe');
  gid bigint := current_setting('gttest.g_pub')::bigint; r jsonb; a0 bigint; b0 bigint; m jsonb; v_msgs int;
begin
  perform pg_temp.login(ada);
  select bank into a0 from profiles where id = ada; select bank into b0 from profiles where id = bayo;
  perform pg_temp.gt_advance(30);
  r := gist_group_send_money(gid, 'GtBayo', 2000, 'for chop');
  m := r->'message';
  perform pg_temp.assert(m->>'kind' = 'money' and (m->>'amount')::bigint = 2000 and m->>'to_username' = 'GtBayo' and m->>'body' = 'for chop', 'money bubble message');
  perform pg_temp.assert((select bank from profiles where id = bayo) = b0 + 2000, 'recipient got the money (bank_transfer)');
  perform pg_temp.assert((select bank from profiles where id = ada) < a0 - 2000, 'sender paid the amount plus the transfer fee');
  perform pg_temp.assert((r->'transfer'->>'amount')::bigint = 2000, 'transfer result returned');
  perform pg_temp.assert(pg_temp.gt_events(bayo, 'transfer_in') >= 1 and exists (select 1 from ledger where user_id = bayo and reason = 'transfer_in'), 'money alert + ledger row');
  perform pg_temp.assert((select last_msg_text from gist_groups where id = gid) like '%2,000%', 'group preview says the amount: ' || (select last_msg_text from gist_groups where id = gid));
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send_money(%s, 'GtEfe', 500)$q$, gid)) = 'not_member', 'recipient must be in the group');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send_money(%s, 'GtAda', 500)$q$, gid)) = 'self', 'not to yourself');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send_money(%s, 'GtBayo', 5)$q$, gid)) <> 'ok', 'bank minimum applies');
  v_msgs := (select count(*) from gist_messages where group_id = gid);
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send_money(%s, 'GtBayo', 50000000)$q$, gid)) <> 'ok' and (select count(*) from gist_messages where group_id = gid) = v_msgs,
                         'a refused transfer posts nothing');
  update profiles set transfer_trusted = false, created_at = bl_now() where id = ada;
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send_money(%s, 'GtBayo', 500)$q$, gid)) in ('too_new', 'limit'), 'new accounts: group money follows the bank rule (or the Gist age rule)');
  update profiles set transfer_trusted = true, created_at = bl_now() - interval '1 day' where id = ada;
  -- money bubbles can't be deleted by the sender; muted can't send money
  perform pg_temp.assert(pg_temp.gt_hint(format('select gist_group_delete_message(%s)', (m->>'id'))) = 'not_allowed', 'money bubble stays as the receipt');
  perform pg_temp.login(chi); perform pg_temp.login(bayo);
  perform gist_group_mute(gid, chi, 30);
  perform pg_temp.login(chi);
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send_money(%s, 'GtAda', 500)$q$, gid)) = 'muted_group', 'muted members cannot send money');
  perform pg_temp.login(bayo); perform gist_group_mute(gid, chi, 0);
  -- blocked pair
  perform pg_temp.login(ada); perform chat_block(chi);
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send_money(%s, 'GtChi', 500)$q$, gid)) = 'blocked', 'no money across a block');
  perform chat_unblock(chi);
  raise notice 'ok 13: group money';
end $$;

-- ---------- 14. discover + starter groups ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); dara uuid := pg_temp.gt_u('gtdara'); gid bigint := current_setting('gttest.g_pub')::bigint; priv bigint := current_setting('gttest.g_priv')::bigint;
  r jsonb; adm uuid := pg_temp.gt_u('gtadmin'); other bigint; n int;
begin
  perform pg_temp.assert((select count(*) from gist_groups where system and slug in ('general', 'uniben', 'ringroad', 'owambe', 'buysell')) = 5, '5 starter groups');
  perform pg_temp.assert((select name from gist_groups where slug = 'general') = 'Benin Gist General' and (select name from gist_groups where slug = 'uniben') = 'UNIBEN Students'
                         and (select name from gist_groups where slug = 'ringroad') = 'Ring Road Hustlers' and (select name from gist_groups where slug = 'owambe') = 'Owambe & Clubs'
                         and (select name from gist_groups where slug = 'buysell') = 'Buy & Sell', 'starter names');
  perform pg_temp.assert(not exists (select 1 from gist_groups where system and (name || description) ~* '(lagos|apc|pdp|labour party|tinubu|atiku|obi|peter obi|mtn|glo|dangote)'), 'no real politicians, parties or brands in seeds');
  perform pg_temp.login(dara);
  r := gist_groups_discover();
  perform pg_temp.assert(jsonb_array_length(r) >= 6 and not exists (select 1 from jsonb_array_elements(r) x where (x->>'id')::bigint = priv), 'discover lists public groups, never private ones');
  perform pg_temp.assert((r->0->>'id')::bigint = gid, 'most active group first (it has recent messages)');
  perform pg_temp.assert(jsonb_array_length(gist_groups_discover('gist hub')) = 1, 'search by name');
  perform pg_temp.assert(jsonb_array_length(gist_groups_discover('zzzz-nothing')) = 0, 'search with no match');
  perform pg_temp.assert(jsonb_array_length(gist_groups_discover('100%')) = 0, 'wildcards are escaped');
  perform pg_temp.assert((select (x->>'joined')::boolean from jsonb_array_elements(gist_groups_discover('gist hub')) x limit 1) = true, 'discover shows if I joined');
  perform pg_temp.assert((gist_groups_discover(null, 'new')->0->>'id')::bigint = (select max(id) from gist_groups where is_public), 'sort new');
  perform pg_temp.assert((gist_groups_discover(null, 'big')->0->>'id')::bigint = (select id from gist_groups where is_public order by member_count desc, id desc limit 1), 'sort big');
  perform pg_temp.assert(jsonb_array_length(gist_groups_discover(null, 'new', 1)) = jsonb_array_length(gist_groups_discover(null, 'new', 0)) - 1 or jsonb_array_length(gist_groups_discover(null, 'new', 0)) = 30, 'offset');
  -- join a starter group
  select id into other from gist_groups where slug = 'buysell';
  perform pg_temp.assert(gist_group_join(other)->>'role' = 'member', 'join a starter group');
  perform gist_group_send(other, 'Anybody selling a fridge?');
  -- admin: rename a starter group, cap, hide
  perform pg_temp.login(adm);
  perform admin_gist_group_set(other, 'Buy & Sell Benin', '🛍️', null, 300);
  perform pg_temp.assert((select name from gist_groups where id = other) = 'Buy & Sell Benin' and (select member_cap from gist_groups where id = other) = 300, 'admin renames a starter group and sets its cap');
  perform pg_temp.assert(jsonb_array_length(admin_gist_groups('Buy')) = 1, 'admin group search');
  perform admin_gist_group_set(other, 'Buy & Sell', null, null, 0);
  perform pg_temp.assert((select member_cap from gist_groups where id = other) is null, 'cap 0 = default');
  -- report a group; admin hides it
  perform pg_temp.login(dara); perform gist_report('group', gid, 'scam group');
  perform pg_temp.login(adm);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(admin_gist_reports('open')) x where x->>'kind' = 'group' and (x->>'target_id')::bigint = gid), 'group report in the admin list');
  perform admin_gist_hide('group', gid, true);
  perform pg_temp.login(dara);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(gist_groups_discover()) x where (x->>'id')::bigint = gid), 'hidden group leaves discover');
  perform pg_temp.assert(pg_temp.gt_hint(format($q$select gist_group_send(%s, 'hello?')$q$, gid)) = 'group_hidden', 'hidden group is paused');
  perform pg_temp.login(adm); perform admin_gist_hide('group', gid, false);
  perform pg_temp.assert(pg_temp.gt_hint(format('select admin_gist_delete(%L, %s)', 'group', (select id from gist_groups where slug = 'general'))) = 'not_found', 'official groups cannot be deleted');
  raise notice 'ok 14: discover and starters';
end $$;

-- ---------- 15. realtime RLS on gist_messages (members only, blocked pairs hidden) ----------
do $$ begin perform pg_temp.login(pg_temp.gt_u('gtbayo')); end $$;
set local role authenticated;
do $$
declare gid bigint := current_setting('gttest.g_pub')::bigint;
begin
  perform pg_temp.assert((select count(*) from gist_messages where group_id = gid) > 5, 'RLS: a member reads the group');
  perform pg_temp.assert((select count(*) from gist_messages where group_id = current_setting('gttest.g_priv')::bigint) = 0, 'RLS: nothing from a group I am not in');
end $$;
reset role;
do $$ begin perform pg_temp.login(pg_temp.gt_u('gtefe')); end $$;
set local role authenticated;
do $$
begin
  perform pg_temp.assert((select count(*) from gist_messages where group_id = current_setting('gttest.g_pub')::bigint) = 0, 'RLS: a non-member reads nothing');
  begin
    insert into gist_messages (group_id, user_id, username, kind, body) values (current_setting('gttest.g_pub')::bigint, current_setting('gttest.gtefe')::uuid, 'x', 'text', 'sneaky');
    raise exception 'TEST FAILED: direct insert worked';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from gist_posts limit 1;
    raise exception 'TEST FAILED: posts are readable directly';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$
declare ada uuid := pg_temp.gt_u('gtada'); dara uuid := pg_temp.gt_u('gtdara'); n_all int; n_dara int;
begin
  -- Ada blocks Dara: Dara stops seeing Ada's messages (both ways)
  perform pg_temp.login(ada); perform chat_block(dara);
  select count(*) into n_all from gist_messages where group_id = current_setting('gttest.g_pub')::bigint and user_id = ada and not hidden;
  perform pg_temp.assert(n_all > 0, 'Ada has messages');
  perform pg_temp.login(dara);
end $$;
set local role authenticated;
do $$
begin
  perform pg_temp.assert((select count(*) from gist_messages where group_id = current_setting('gttest.g_pub')::bigint and user_id = current_setting('gttest.gtada')::uuid) = 0, 'RLS: a blocked pair cannot read each other''s messages');
end $$;
reset role;
do $$ begin perform pg_temp.login(pg_temp.gt_u('gtada')); perform chat_unblock(pg_temp.gt_u('gtdara')); raise notice 'ok 15: realtime RLS'; end $$;

-- ---------- 16. admin guards ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada');
begin
  perform pg_temp.login(ada);
  perform pg_temp.assert(pg_temp.gt_hint('select admin_gist_overview()') = 'not_admin', 'non-admin: overview');
  perform pg_temp.assert(pg_temp.gt_hint('select admin_gist_reports()') = 'not_admin', 'non-admin: reports');
  perform pg_temp.assert(pg_temp.gt_hint($q$select admin_gist_hide('post', 1, true)$q$) = 'not_admin', 'non-admin: hide');
  perform pg_temp.assert(pg_temp.gt_hint($q$select admin_gist_delete('post', 1)$q$) = 'not_admin', 'non-admin: delete');
  perform pg_temp.assert(pg_temp.gt_hint(format('select admin_gist_ban(%L, true)', ada)) = 'not_admin', 'non-admin: ban');
  perform pg_temp.assert(pg_temp.gt_hint($q$select admin_gist_group_set(1, 'x')$q$) = 'not_admin', 'non-admin: group set');
  perform pg_temp.assert(pg_temp.gt_hint('select admin_gist_orphan_photos()') = 'not_admin', 'non-admin: orphan photos');
  perform pg_temp.assert(pg_temp.gt_hint('select admin_gist_bans()') = 'not_admin', 'non-admin: bans');
  perform pg_temp.assert(pg_temp.gt_hint('select admin_gist_groups()') = 'not_admin', 'non-admin: groups');
  -- orphan photo list for admins
  insert into storage.objects (bucket_id, name, owner, metadata, created_at) values ('gist-photos', ada || '/' || gen_random_uuid() || '.jpg', ada, '{"size": 5000}', now() - interval '2 hours');
  perform pg_temp.login(pg_temp.gt_u('gtadmin'));
  perform pg_temp.assert(jsonb_array_length(admin_gist_orphan_photos()) >= 1, 'orphan photos listed for admins');
  raise notice 'ok 16: admin guards';
end $$;

-- ---------- 17. sweep, and deleting a player ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); zed uuid; p bigint; gid bigint; n int;
begin
  -- sweep: old gists and messages go, fresh ones stay
  perform pg_temp.login(ada);
  delete from gist_posts;
  p := (gist_post('Ancient gist')->>'id')::bigint;
  perform gist_post('Fresh gist after');
  update gist_posts set created_at = now() - interval '90 days' where id = p;
  update game_config set value = '60' where key = 'gist.post_keep_days';
  update gist_messages set created_at = now() - interval '45 days' where id = (select min(id) from gist_messages);
  update gist_cache set at = 'epoch' where key = 'sweep';
  perform bl_gist_sweep();
  perform pg_temp.assert(not exists (select 1 from gist_posts where id = p) and exists (select 1 from gist_posts where body = 'Fresh gist after'), 'sweep deletes only old gists');
  perform pg_temp.assert((select count(*) from gist_messages where created_at < now() - interval '30 days') = 0, 'sweep deletes old group messages');
  perform bl_gist_sweep();
  -- an empty player group is cleaned up, a starter group never
  insert into gist_groups (name, owner_id, member_count, created_at) values ('Ghost Group', null, 0, now() - interval '3 days');
  update gist_cache set at = 'epoch' where key = 'sweep';
  perform bl_gist_sweep();
  perform pg_temp.assert(not exists (select 1 from gist_groups where name = 'Ghost Group') and (select count(*) from gist_groups where system) = 5, 'empty groups are swept, starters stay');
  -- deleting a player removes their gist rows (links migration)
  zed := pg_temp.gt_make('GtZed');
  perform pg_temp.login(zed);
  p := (gist_post('Zed was here')->>'id')::bigint;
  gid := (gist_group_create('Zed''s Place', '🏠', null, true)->>'id')::bigint;
  perform gist_group_send(gid, 'only me here');
  perform pg_temp.login(ada); perform gist_like(p); perform gist_follow(zed);
  perform pg_temp.login(zed); perform gist_report('post', (select min(id) from gist_posts where user_id = ada), 'x');
  delete from profiles where id = zed;
  select count(*) into n from (
    select 1 from gist_posts where user_id = zed union all select 1 from gist_comments where user_id = zed union all select 1 from gist_likes where user_id = zed
    union all select 1 from gist_follows where followee = zed or follower = zed union all select 1 from gist_group_members where user_id = zed
    union all select 1 from gist_messages where user_id = zed union all select 1 from gist_reports where reporter_id = zed union all select 1 from gist_notify where user_id = zed) x;
  perform pg_temp.assert(n = 0, 'deleting a player removes their gist rows (left: ' || n || ')');
  perform pg_temp.assert((select owner_id from gist_groups where id = gid) is null, 'a group keeps existing, ownerless');
  raise notice 'ok 17: sweep and delete';
end $$;

-- ---------- 18. storage policies (voice notes of a group, gist photos) ----------
do $$
declare ada uuid := pg_temp.gt_u('gtada'); efe uuid := pg_temp.gt_u('gtefe'); gid bigint := current_setting('gttest.g_pub')::bigint;
begin
  perform set_config('gttest.v_ok', 'group/' || gid || '/' || ada || '/' || gen_random_uuid() || '.webm', true);
  perform set_config('gttest.v_other', 'group/' || gid || '/' || efe || '/' || gen_random_uuid() || '.webm', true);
  perform set_config('gttest.v_dm', gid || '/' || ada || '/' || gen_random_uuid() || '.webm', true);
  perform set_config('gttest.ph_ok', ada || '/' || gen_random_uuid() || '.jpg', true);
  perform set_config('gttest.ph_other', efe || '/' || gen_random_uuid() || '.jpg', true);
  perform pg_temp.login(ada);
end $$;
set local role authenticated;
do $$
declare ada uuid := pg_temp.gt_u('gtada'); gid bigint := current_setting('gttest.g_pub')::bigint;
begin
  insert into storage.objects (bucket_id, name, owner) values ('player-voice', current_setting('gttest.v_ok'), ada);
  perform pg_temp.assert(exists (select 1 from storage.objects where name = current_setting('gttest.v_ok')), 'a member can upload and read her group voice note');
  begin
    insert into storage.objects (bucket_id, name, owner) values ('player-voice', 'group/' || gid || '/' || gen_random_uuid() || '/x.webm', ada);
    raise exception 'TEST FAILED: upload into someone else''s folder worked';
  exception when insufficient_privilege or check_violation then null;
  end;
  begin
    -- photos are off: the policy refuses the upload
    insert into storage.objects (bucket_id, name, owner) values ('gist-photos', current_setting('gttest.ph_ok'), ada);
    raise exception 'TEST FAILED: photo upload worked while photos are off';
  exception when insufficient_privilege or check_violation then null;
  end;
end $$;
reset role;
do $$ begin update game_config set value = 'true' where key = 'gist.photos_enabled'; perform pg_temp.login(pg_temp.gt_u('gtada')); end $$;
set local role authenticated;
do $$
declare ada uuid := pg_temp.gt_u('gtada');
begin
  insert into storage.objects (bucket_id, name, owner) values ('gist-photos', current_setting('gttest.ph_ok'), ada);
  begin
    insert into storage.objects (bucket_id, name, owner) values ('gist-photos', current_setting('gttest.ph_other'), ada);
    raise exception 'TEST FAILED: photo into another folder worked';
  exception when insufficient_privilege or check_violation then null;
  end;
  -- (SQL deletes on storage.objects are blocked by Supabase; the client uses the Storage API, whose delete policy asks gist_file_used)
  perform pg_temp.assert(not gist_file_used(current_setting('gttest.ph_ok')), 'an unused photo may be removed');
  perform pg_temp.assert(gist_file_used((select audio_path from gist_messages where audio_path is not null limit 1)) or not exists (select 1 from gist_messages where audio_path is not null), 'a used voice file is protected');
end $$;
reset role;
do $$
declare efe uuid := pg_temp.gt_u('gtefe');
begin
  update game_config set value = 'false' where key = 'gist.photos_enabled';
  insert into storage.objects (bucket_id, name, owner) values ('player-voice', current_setting('gttest.v_other'), efe);   -- (as postgres: she is not a member)
  perform pg_temp.login(efe);
end $$;
set local role authenticated;
do $$
begin
  perform pg_temp.assert(not exists (select 1 from storage.objects where name = current_setting('gttest.v_ok')), 'a non-member cannot read a group voice note');
  perform pg_temp.assert(not exists (select 1 from storage.objects where name = current_setting('gttest.v_other')), 'nor her own file in a group she is not in');
end $$;
reset role;
do $$ begin raise notice 'ok 18: storage policies'; end $$;

do $$ begin raise notice 'GIST TEST OK'; end $$;
