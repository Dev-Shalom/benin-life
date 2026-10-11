-- S1-D feedback box (20261012000900_feedback.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/feedback_test.sql
-- Groups: 1 submit (meta, place, username snapshot, admin notification) · 2 refusals (kind, length, rating,
-- rate limit, disabled) · 3 RLS: own rows only, admins all · 4 admin list + stats + filters · 5 status + reply ->
-- player alert + feedback_mine · 6 grants + cascade on account delete.
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

do $$
declare
  adm uuid := pg_temp.new_user('fb_admin@fb.bl');
  a uuid := pg_temp.new_user('fb_a@fb.bl');
  b uuid := pg_temp.new_user('fb_b@fb.bl');
  r jsonb; v_id bigint; v_id2 bigint; n int; v_notes bigint;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(adm);
  perform create_profile_v2('Fb_Admin', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set is_admin = true where id = adm;
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(a);
  perform create_profile_v2('Fb_Player', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(b);
  perform create_profile_v2('Fb_Other', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '3' where key = 'feedback.per_day';
  update game_config set value = 'true' where key = 'feedback.enabled';
  update profiles set location_id = 'oba_market' where id = a;
  select coalesce(max(id), 0) into v_notes from admin_notifications;

  -- 1. submit
  perform pg_temp.login(a);
  r := feedback_submit('suggestion', '  Add okada rides abeg  ', null,
                       '{"app_version":"abc123","device":"Mozilla/5.0 Android","viewport":"390x844"}');
  v_id := (r->>'id')::bigint;
  perform pg_temp.assert(v_id is not null and (r->>'left_today')::int = 2, 'submitted: ' || r::text);
  perform pg_temp.assert((select username = 'Fb_Player' and body = 'Add okada rides abeg' and status = 'new' and rating is null
                                 and app_version = 'abc123' and viewport = '390x844' and location_id = 'oba_market'
                            from feedback where id = v_id), 'stored with snapshot + meta + place');
  perform pg_temp.assert(exists (select 1 from admin_notifications where id > v_notes and kind = 'feedback'
                                   and title = 'New suggestion from @Fb_Player' and url = '/admin/feedback'), 'admin notified');
  r := feedback_submit('review', 'Sweet game!', 5, '{}');
  v_id2 := (r->>'id')::bigint;
  perform pg_temp.assert((select rating from feedback where id = v_id2) = 5, 'review rating');
  perform pg_temp.assert(exists (select 1 from admin_notifications where kind = 'feedback' and title like 'New review from @Fb_Player (5★)'), 'review title');

  -- 2. refusals
  perform pg_temp.assert(pg_temp.hint_of($q$select feedback_submit('rant', 'hello there', null, '{}')$q$) = 'bad_kind', 'kind');
  perform pg_temp.assert(pg_temp.hint_of($q$select feedback_submit('bug', ' a ', null, '{}')$q$) = 'too_short', 'short');
  perform pg_temp.assert(pg_temp.hint_of(format('select feedback_submit(%L, %L, null, %L)', 'bug', repeat('x', 1001), '{}')) = 'too_long', 'long');
  perform pg_temp.assert(pg_temp.hint_of($q$select feedback_submit('review', 'no stars here', null, '{}')$q$) = 'rating', 'review needs stars');
  perform pg_temp.assert(pg_temp.hint_of($q$select feedback_submit('review', 'six stars!!', 6, '{}')$q$) = 'rating', 'stars 1-5');
  perform feedback_submit('bug', 'Map froze for Ring Road', null, '{}');
  perform pg_temp.assert(pg_temp.hint_of($q$select feedback_submit('bug', 'fourth one today', null, '{}')$q$) = 'rate_limit', 'rate limit');
  perform pg_temp.login(b);
  update game_config set value = 'false' where key = 'feedback.enabled';
  perform pg_temp.assert(pg_temp.hint_of($q$select feedback_submit('bug', 'closed box test', null, '{}')$q$) = 'disabled', 'disabled');
  update game_config set value = 'true' where key = 'feedback.enabled';
  perform feedback_submit('suggestion', 'More clubs in Ugbowo', null, '{}');

  -- 3. RLS: players read only their own, admins read all
  set local role authenticated;
  perform pg_temp.login(b);
  select count(*) into n from feedback;
  perform pg_temp.assert(n = 1, 'B sees only own: ' || n);
  perform pg_temp.login(a);
  select count(*) into n from feedback;
  perform pg_temp.assert(n = 3, 'A sees only own: ' || n);
  perform pg_temp.login(adm);
  select count(*) into n from feedback where username in ('Fb_Player', 'Fb_Other');
  perform pg_temp.assert(n = 4, 'admin sees all: ' || n);
  reset role;

  -- 4. admin list
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of('select admin_feedback_list()') = 'not_admin', 'players cannot list');
  perform pg_temp.login(adm);
  r := admin_feedback_list(null, null, 50);
  perform pg_temp.assert(jsonb_array_length(r->'rows') >= 4 and (r->'rows'->0->>'id')::bigint > (r->'rows'->1->>'id')::bigint, 'newest first');
  perform pg_temp.assert((r->'stats'->>'avg_rating')::numeric = (select round(avg(rating)::numeric, 2) from feedback where kind = 'review') and (r->'stats'->>'reviews')::int >= 1, 'avg rating: ' || (r->'stats')::text);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(admin_feedback_list('bug', null, 50)->'rows') x where x->>'kind' <> 'bug'), 'kind filter');
  perform pg_temp.assert((select bool_and(x->>'location_name' is not null) from jsonb_array_elements(r->'rows') x where (x->>'id')::bigint = v_id), 'place name');

  -- 5. status + reply
  r := admin_feedback_update(v_id, 'planned', 'Okada dey come next update!');
  perform pg_temp.assert(r->>'status' = 'planned' and r->>'reply' = 'Okada dey come next update!', 'updated: ' || r::text);
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'feedback_reply' and body = 'Okada dey come next update!'), 'player alerted');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'feedback_update' and admin_id = adm), 'audited');
  select count(*) into n from events where user_id = a and kind = 'feedback_reply';
  perform admin_feedback_update(v_id, 'done', null);
  perform pg_temp.assert((select count(*) from events where user_id = a and kind = 'feedback_reply') = n, 'status-only change sends no alert');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_feedback_update(%s, %L, null)', v_id, 'maybe')) = 'bad_status', 'bad status');
  perform pg_temp.login(a);
  r := feedback_mine();
  perform pg_temp.assert((r->'rows'->-1->>'reply') = 'Okada dey come next update!' and (r->'rows'->-1->>'status') = 'done', 'feedback_mine shows reply: ' || left(r::text, 300));
  perform pg_temp.assert((r->>'left_today')::int = 0, 'left today 0');

  -- 6. account delete removes the player's feedback
  delete from auth.users where id = a;
  perform pg_temp.assert(not exists (select 1 from feedback where username = 'Fb_Player'), 'feedback cascades');
  raise notice 'ok: feedback';
end $$;

do $$
begin
  perform pg_temp.assert(not has_function_privilege('anon', 'public.feedback_submit(text,text,int,jsonb)', 'execute'), 'anon submit');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.feedback', 'insert'), 'no direct insert');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.feedback', 'update'), 'no direct update');
  raise notice 'ok: feedback grants';
end $$;
