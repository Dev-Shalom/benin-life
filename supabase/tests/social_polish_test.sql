-- Social polish (20261009000200_social_polish.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/social_polish_test.sql
-- Groups: 1 English "isn't on the map" error · 2 a host leaving home ends the visit: guests go back to their own
-- home (home restored) with an alert.
do $$
declare h uuid := pg_temp.new_user('sp_host@social.bl'); g uuid := pg_temp.new_user('sp_guest@social.bl');
        inv jsonb; m text; g_home text; h_home text;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(h);
  perform create_profile_v2('Sp_Host', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(g);
  perform create_profile_v2('Sp_Guest', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  select home_location_id into g_home from profiles where id = g;
  select home_location_id into h_home from profiles where id = h;

  -- 1. English error
  begin perform bl_location('nowhere_at_all'); m := null;
  exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m = 'That place isn''t on the map.', 'English map error: ' || coalesce(m, 'none'));

  -- 2. friend -> invite -> knock -> admit
  perform pg_temp.login(h); perform social_add_friend(g);
  perform pg_temp.login(g); perform social_respond_friend(h, true);
  perform pg_temp.login(h); inv := social_send_house_invite(g);
  perform pg_temp.login(g); perform social_respond_house_invite((inv->>'id')::bigint, true);
  perform pg_temp.login(h); perform social_home_admit((inv->>'id')::bigint, true);
  perform pg_temp.assert((select location_id = h_home and home_visit_host_id = h from profiles where id = g), 'guest inside');
  -- host leaves home
  update profiles set location_id = 'oba_market' where id = h;
  perform pg_temp.assert((select location_id = g_home and home_location_id = g_home and home_visit_host_id is null
                            from profiles where id = g), 'guest sent back to own home, home restored');
  perform pg_temp.assert(exists (select 1 from events where user_id = g and kind = 'house_visit_ended'), 'guest alerted');
  raise notice 'ok: social polish';
end $$;
