-- Q1 quick fixes (20261012000100_quick_fixes.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/quick_fixes_test.sql
-- Groups: 1 shared interactions shortened · 2 needs decay slowed · 3 guest leaving ends an interaction for
-- both · 4 stopping it frees the partner · 5 host travelling away ends it · 6 Go Crazy inactive · 7 helpers private
do $$
begin
  perform pg_temp.assert((select max(seconds) from interaction_types where kind in ('greet', 'dance', 'movie', 'gist', 'cook_meal', 'play_game')) <= 40,
    'interactions are game-length');
  perform pg_temp.assert((select seconds from interaction_types where kind = 'greet') between 4 and 6, 'greet ~5 s');
  perform pg_temp.assert((select seconds from interaction_types where kind = 'dance') between 20 and 25, 'dance ~22 s');
  perform pg_temp.assert((select seconds from interaction_types where kind = 'movie') between 30 and 40, 'movie ~35 s');
  perform pg_temp.assert((select max(max_seconds) from activities) <= 90, 'solo activities stay short');
  perform pg_temp.assert((select (value #>> '{}')::numeric from game_config where key = 'needs.decay_speed') <= 1.25,
    'needs decay at most half the old 2.5');
  raise notice 'ok: durations + decay';
end $$;

do $$
declare h uuid := pg_temp.new_user('qf_host@social.bl'); g uuid := pg_temp.new_user('qf_guest@social.bl');
        inv jsonb; r jsonb; id1 bigint; v_home text;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(h);
  perform create_profile_v2('Qf_Host', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(g);
  perform create_profile_v2('Qf_Guest', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set busy_until = null, busy_label = null where id in (h, g);

  perform pg_temp.login(h);
  perform social_add_friend(g);
  perform pg_temp.login(g); perform social_respond_friend(h, true);
  perform pg_temp.login(h); inv := social_send_house_invite(g);
  perform pg_temp.login(g); perform social_respond_house_invite((inv->>'id')::bigint, true);
  perform pg_temp.login(h); perform social_home_admit((inv->>'id')::bigint, true);

  -- 3. dance together, then the guest leaves the house: both freed, row ended, host told
  r := social_interact_request(g, 'dance');
  id1 := (r->>'id')::bigint;
  perform pg_temp.login(g);
  r := social_interact_respond(id1, true);
  perform pg_temp.assert(r->>'status' = 'accepted', 'dance accepted');
  perform pg_temp.assert((select count(*) from profiles where id in (h, g) and busy_until > now() and busy_label = 'Dance together') = 2, 'both dancing');
  r := social_leave_house();
  perform pg_temp.assert((select count(*) from profiles where id in (h, g) and busy_until > bl_now()) = 0, 'leaving frees both players');
  perform pg_temp.assert((select status from house_interactions where id = id1) = 'ended', 'interaction ended');
  perform pg_temp.assert(exists (select 1 from events where user_id = h and kind = 'house_interact_end' and (data->>'id')::bigint = id1), 'host told');
  raise notice 'ok: leaving the house ends a shared interaction';

  -- back in: invite again
  perform pg_temp.login(h); inv := social_send_house_invite(g);
  perform pg_temp.login(g); perform social_respond_house_invite((inv->>'id')::bigint, true);
  perform pg_temp.login(h); perform social_home_admit((inv->>'id')::bigint, true);

  -- 4. stopping it (activity_stop) frees the partner
  update house_interactions set created_at = now() - interval '1 hour' where requester_id = h;
  r := social_interact_request(g, 'gist');
  id1 := (r->>'id')::bigint;
  perform pg_temp.login(g);
  perform social_interact_respond(id1, true);
  perform set_config('bl.test_offset_seconds', '2', true);
  r := activity_stop();
  perform pg_temp.assert((r->>'stopped')::boolean, 'stopped: ' || r::text);
  perform pg_temp.assert((select count(*) from profiles where id in (h, g) and busy_until > bl_now()) = 0, 'stop frees the partner');
  perform pg_temp.assert((select status from house_interactions where id = id1) = 'ended', 'stopped interaction ended');

  -- 5. the host walks out (location change) mid-greet: both freed
  update house_interactions set created_at = now() - interval '1 hour' where requester_id = h;
  perform pg_temp.login(h);
  r := social_interact_request(g, 'greet');
  id1 := (r->>'id')::bigint;
  perform pg_temp.login(g);
  perform social_interact_respond(id1, true);
  select id into v_home from locations where private_home_owner_id is null and active and id <> (select location_id from profiles where id = h) limit 1;
  update profiles set location_id = v_home where id = h;
  perform pg_temp.assert((select count(*) from profiles where id in (h, g) and busy_until > bl_now()) = 0, 'host leaving frees both');
  perform pg_temp.assert((select status from house_interactions where id = id1) = 'ended', 'host leaving ends it');
  raise notice 'ok: stop + host leave end shared interactions';
end $$;

do $$
begin
  -- 6. Go Crazy off: brand + items inactive, nothing deleted
  perform pg_temp.assert(not (select active from wardrobe_brands where id = 'go_crazy'), 'Go Crazy brand inactive');
  perform pg_temp.assert(not exists (select 1 from wardrobe_items where brand_id = 'go_crazy' and active), 'Go Crazy items inactive');
  perform pg_temp.assert(exists (select 1 from wardrobe_items where brand_id = 'go_crazy'), 'Go Crazy items kept');
  -- 7. helpers private
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_house_interactions_end(uuid,text)', 'execute')
    and not has_function_privilege('anon', 'public.bl_house_interactions_end(uuid,text)', 'execute'), 'end helper private');
  raise notice 'ok: Go Crazy off + grants';
end $$;
