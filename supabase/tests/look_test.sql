-- Edit look is identity-only + date activities (20261010000200_look_and_dates.sql). Rolled back.
--   bash scripts/sql-test.sh -- supabase/tests/look_test.sql
do $$
declare u uuid := pg_temp.new_user('lk_ada@look.bl'); a0 jsonb; a1 jsonb;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(u);
  perform create_profile_v2('Lk_Ada', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  select avatar into a0 from profiles where id = u;
  -- try to sneak a new top/shoes/hat in through Edit look, and change the hair
  perform update_avatar(a0 || '{"hair":"locs","top":{"s":"agbada","c":"#111111","f":"lace"},"shoes":{"s":"loafers","c":"#000"},"hat":"fila"}'::jsonb);
  select avatar into a1 from profiles where id = u;
  perform pg_temp.assert(a1->>'hair' = 'locs', 'identity change saved');
  perform pg_temp.assert(a1->'top' is not distinct from a0->'top' and a1->'shoes' is not distinct from a0->'shoes'
                         and a1->'hat' is not distinct from a0->'hat', 'clothes kept (boutique only)');
  perform pg_temp.assert(exists (select 1 from activities where id = 'date_dinner') and exists (select 1 from activities where id = 'movie_date'), 'date activities');
  perform pg_temp.assert(exists (select 1 from zone_actions where ref = 'date_dinner'), 'date dinner on the hotel lounge zone');
  raise notice 'ok: look identity-only + dates';
end $$;
