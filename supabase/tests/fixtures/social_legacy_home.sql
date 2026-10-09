-- Pre-migration player fixture: proves the new migration privatizes an already chosen home.
do $$
declare v_uid uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
  values (v_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          'legacy-home-' || v_uid || '@social.bl', '',
          '{"provider":"email","providers":["email"]}', '{}', now(), now(), now());
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  update public.game_config set value = '""' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform public.create_profile_v2('LegacyHome', 'female', '{"gender":"female"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform public.choose_start_home('ekenwan_face_me');
  perform set_config('socialtest.legacy_uid', v_uid::text, true);
end $$;
