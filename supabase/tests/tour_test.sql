-- Tour flag (20261018000600_tour.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/tour_test.sql
-- Groups: 1 new Sim starts with no stamp · 2 tour_done() stamps once · 3 second call keeps the first time · 4 get_my_state shows it.
do $$
declare u uuid := pg_temp.new_user('tour_a@tour.bl'); a timestamptz; b timestamptz; s jsonb;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(u);
  perform create_profile_v2('Tour_Player', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  s := get_my_state();
  perform pg_temp.assert(s->'profile'->>'tour_done_at' is null, '1 new Sim has no tour stamp');
  a := tour_done();
  perform pg_temp.assert(a is not null, '2 tour_done stamps');
  perform pg_temp.assert(get_my_state()->'profile'->>'tour_done_at' is not null, '4 get_my_state shows the stamp');
  perform pg_temp.assert(tour_done() = a, '3 second call keeps the first time');
  raise notice 'tour_test: all groups passed';
end $$;
