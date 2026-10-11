-- V2 house interactions (20261011000100_house_interactions.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/house_interactions_test.sql
-- Groups: 1 same house only · 2 accept applies effects + busy to both · 3 decline · 4 expiry · 5 cooldown ·
-- 6 missing furniture refused · 7 outsiders can't act · 8 clients can't write the tables · 9 admin spec + grants
do $$
declare h uuid := pg_temp.new_user('hi_host@social.bl'); g uuid := pg_temp.new_user('hi_guest@social.bl');
        o uuid := pg_temp.new_user('hi_out@social.bl');
        inv jsonb; r jsonb; m text; hh numeric; gh numeric; hcash bigint; id1 bigint;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(h);
  perform create_profile_v2('Hi_Host', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(g);
  perform create_profile_v2('Hi_Guest', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(o);
  perform create_profile_v2('Hi_Out', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set hunger = 40, social = 40, fun = 40, busy_until = null where id in (h, g, o);

  -- 1. not in the same house yet: refused
  perform pg_temp.login(h);
  begin perform social_interact_request(g, 'greet'); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%not with you in the house%', 'request needs the same house: ' || coalesce(m, 'none'));

  -- friend -> invite -> knock -> admit
  perform social_add_friend(g);
  perform pg_temp.login(g); perform social_respond_friend(h, true);
  perform pg_temp.login(h); inv := social_send_house_invite(g);
  perform pg_temp.login(g); perform social_respond_house_invite((inv->>'id')::bigint, true);
  perform pg_temp.login(h); perform social_home_admit((inv->>'id')::bigint, true);

  -- 2. cook a meal (needs a cooker: the lapo starter kerosene stove): accept -> both fed + busy, requester pays
  select cash into hcash from profiles where id = h;
  r := social_interact_request(g, 'cook_meal');
  perform pg_temp.assert(r->>'status' = 'pending', 'request pending');
  id1 := (r->>'id')::bigint;
  perform pg_temp.assert(exists (select 1 from events where user_id = g and kind = 'house_interact' and (data->>'id')::bigint = id1), 'target notified');
  begin perform social_interact_request(g, 'greet'); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%already have a request waiting%', 'one pending per pair: ' || coalesce(m, 'none'));
  perform pg_temp.login(g);
  r := social_interact_respond(id1, true);
  perform pg_temp.assert(r->>'status' = 'accepted', 'accepted: ' || r::text);
  select hunger into hh from profiles where id = h;
  select hunger into gh from profiles where id = g;
  perform pg_temp.assert(hh > 60 and gh > 60, format('both fed (host %s, guest %s)', hh, gh));
  perform pg_temp.assert((select count(*) from profiles where id in (h, g) and busy_until > now() and busy_label = 'Cook a meal for them') = 2, 'both busy');
  perform pg_temp.assert((select cash from profiles where id = h) = hcash - 500, 'requester paid the cost');
  perform pg_temp.assert(exists (select 1 from events where user_id = h and kind = 'house_interact_reply' and data->>'status' = 'accepted'), 'requester told');
  begin perform social_interact_respond(id1, true); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%already answered%', 'no double accept: ' || coalesce(m, 'none'));
  update profiles set busy_until = null, busy_label = null where id in (h, g);

  -- 5. cooldown: same pair + kind within social.interact_cooldown_s
  perform pg_temp.login(h);
  begin perform social_interact_request(g, 'cook_meal'); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%moment before asking%', 'cooldown: ' || coalesce(m, 'none'));
  update house_interactions set created_at = now() - interval '2 minutes' where id = id1;
  r := social_interact_request(g, 'cook_meal');
  perform pg_temp.assert(r->>'status' = 'pending', 'allowed after the cooldown');

  -- 3. decline
  perform pg_temp.login(g);
  r := social_interact_respond((r->>'id')::bigint, false);
  perform pg_temp.assert(r->>'status' = 'declined', 'declined');
  perform pg_temp.assert((select busy_until is null from profiles where id = g), 'decline: nobody busy');

  -- 4. expiry (60 s)
  r := social_interact_request(h, 'gist');   -- the guest asks the host
  update house_interactions set expires_at = now() - interval '1 second' where id = (r->>'id')::bigint;
  perform pg_temp.login(h);
  r := social_interact_respond((r->>'id')::bigint, true);
  perform pg_temp.assert(r->>'status' = 'expired', 'expired: ' || r::text);
  perform pg_temp.assert((select social from profiles where id = h) < 60, 'expired: no effects');

  -- 6. missing furniture (lapo host has no TV)
  begin perform social_interact_request(g, 'movie'); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%needs a TV%', 'movie needs a TV: ' || coalesce(m, 'none'));

  -- 7. outsiders can't act
  r := social_interact_request(g, 'dance');
  perform pg_temp.login(o);
  begin perform social_interact_respond((r->>'id')::bigint, true); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%not for you%', 'outsider cannot answer: ' || coalesce(m, 'none'));
  begin perform social_interact_request(h, 'greet'); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%not with you in the house%', 'outsider cannot ask: ' || coalesce(m, 'none'));
  perform pg_temp.login(h);
  begin perform social_interact_respond((r->>'id')::bigint, true); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%not for you%', 'requester cannot accept their own request: ' || coalesce(m, 'none'));
  raise notice 'ok: house interactions';
end $$;

-- 8. clients can't write the tables (RLS + grants), and only see their own requests
set local role authenticated;
do $$
declare m text;
begin
  perform pg_temp.login((select id from profiles where username = 'Hi_Out'));
  begin insert into house_interactions (host_id, location_id, requester_id, target_id, kind)
        select id, location_id, id, id, 'greet' from profiles where username = 'Hi_Out'; m := null;
  exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m is not null, 'client insert into house_interactions refused');
  begin update interaction_types set effects = '{"fun":100}' where kind = 'greet'; m := null;
  exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m is not null, 'client update of interaction_types refused');
  begin update house_interactions set status = 'accepted'; m := null;
  exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m is not null, 'client update of house_interactions refused');
  perform pg_temp.assert((select count(*) from house_interactions) = 0, 'outsider sees no requests');
  perform pg_temp.assert((select count(*) from interaction_types) >= 6, 'catalogue readable');
  raise notice 'ok: house interactions writes locked';
end $$;
reset role;

-- 9. admin editable, helpers private
do $$
begin
  perform pg_temp.assert(bl_admin_table_spec('interaction_types')->'cols' ? 'effects', 'admin spec lists interaction_types');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_house_together(uuid,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.bl_house_has(uuid,text[])', 'execute'), 'bl_house helpers private');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.social_interact_request(uuid,text)', 'execute'), 'anon cannot request');
  perform pg_temp.assert((select value #>> '{}' from game_config where key = 'social.interact_cooldown_s') is not null, 'cooldown key');
  raise notice 'ok: house interactions admin + grants';
end $$;
