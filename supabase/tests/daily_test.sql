-- D1 daily reward + gem hunt (20261009000300_daily.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/daily_test.sql
-- Groups: 1 reward claim once per WAT day (ledger label) · 2 streak +1 next day · 3 missed day resets to 1 ·
-- 4 gem pick deterministic, never hidden places / private homes · 5 gem_find must be there · 6 no double find ·
-- 7 all-found bonus + status counts · 8 players cannot write the tables · 9 switches off.
do $$
declare u uuid := pg_temp.new_user('d1_a@daily.bl'); o uuid := pg_temp.new_user('d1_b@daily.bl');
        r jsonb; m text; c0 bigint; c1 bigint; g text; picks text[]; picks2 text[]; d date; i int; n int;
begin
  perform set_config('bl.test_offset_seconds', '', true);
  update game_config set value = 'true' where key in ('daily.reward_enabled', 'daily.gems_enabled');
  update game_config set value = '3' where key = 'daily.gems_per_day';
  update game_config set value = '3000' where key = 'daily.gem_prize';
  update game_config set value = '5000' where key = 'daily.gem_all_bonus';
  update daily_reward_steps set cash = case day when 1 then 1000 when 2 then 1500 else cash end where day in (1, 2);

  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(o);
  perform create_profile_v2('D1_Other', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(u);
  perform create_profile_v2('D1_Player', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');

  -- 1. claim once per day
  r := daily_reward_status();
  perform pg_temp.assert((r->>'ready')::boolean and (r->>'day')::int = 1 and jsonb_array_length(r->'steps') = 7, 'ready, day 1: ' || r::text);
  perform pg_temp.assert(r->'steps'->0->>'state' = 'today' and r->'steps'->1->>'state' = 'upcoming', 'step states');
  select cash into c0 from profiles where id = u;
  r := daily_reward_claim();
  select cash into c1 from profiles where id = u;
  perform pg_temp.assert(c1 - c0 = 1000 and (r->>'day')::int = 1, 'day 1 paid 1000: ' || r::text);
  perform pg_temp.assert(exists (select 1 from ledger where user_id = u and reason = 'Daily reward (day 1)' and delta = 1000), 'ledger label');
  begin perform daily_reward_claim(); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like 'You already claimed%', 'double claim refused: ' || coalesce(m, 'none'));
  r := daily_reward_status();
  perform pg_temp.assert((r->>'claimed')::boolean and (r->>'day')::int = 1 and r->'steps'->0->>'state' = 'claimed'
                         and (r->'next'->>'day')::int = 2, 'claimed status: ' || r::text);

  -- 2. next WAT day: day 2
  perform set_config('bl.test_offset_seconds', '86400', true);
  r := daily_reward_status();
  perform pg_temp.assert((r->>'ready')::boolean and (r->>'day')::int = 2, 'day 2 ready: ' || r::text);
  select cash into c0 from profiles where id = u;
  r := daily_reward_claim();
  select cash into c1 from profiles where id = u;
  perform pg_temp.assert((r->>'day')::int = 2 and c1 - c0 = 1500, 'day 2 paid 1500');
  perform pg_temp.assert((select streak_day from daily_reward_state where user_id = u) = 2, 'streak 2');

  -- 3. miss a day (claim again 2 days later): back to day 1
  perform set_config('bl.test_offset_seconds', (86400 * 3)::text, true);
  r := daily_reward_status();
  perform pg_temp.assert((r->>'day')::int = 1 and (r->>'ready')::boolean, 'missed day resets to 1: ' || r::text);
  r := daily_reward_claim();
  perform pg_temp.assert((r->>'day')::int = 1, 'claimed day 1 again');
  perform set_config('bl.test_offset_seconds', '', true);

  -- 4. deterministic gem pick: same answer twice, never hidden / private homes / home scenes
  d := bl_wat_date();
  select array_agg(location_id order by idx) into picks from bl_gem_places(d);
  select array_agg(location_id order by idx) into picks2 from bl_gem_places(d);
  perform pg_temp.assert(cardinality(picks) = 3 and picks = picks2, 'deterministic 3 picks: ' || picks::text);
  update locations set active = false where id = picks[1];
  update locations set private_home_owner_id = (select pr.id from profiles pr where not exists (select 1 from locations x where x.private_home_owner_id = pr.id) limit 1) where id = picks[2];
  select array_agg(location_id order by idx) into picks2 from bl_gem_places(d);
  perform pg_temp.assert(cardinality(picks2) = 3 and not (picks[1] = any(picks2)) and not (picks[2] = any(picks2)),
                         'hidden place / private home dropped: ' || picks2::text);
  for i in 0..40 loop
    select count(*) into n from bl_gem_places(d + i) g join locations l on l.id = g.location_id
     where not l.active or l.private_home_owner_id is not null or l.scene like 'home%' or l.scene in ('police', 'hospital');
    perform pg_temp.assert(n = 0, 'bad pick on ' || (d + i)::text);
  end loop;
  update locations set active = true where id = picks[1];
  update locations set private_home_owner_id = null where id = picks[2];

  -- 5. gem_find needs you there (and not on the road), and a gem there
  perform pg_temp.login(u);
  r := gem_hunt_status();
  perform pg_temp.assert((r->>'total')::int = 3 and (r->>'found')::int = 0 and (r->>'next_prize')::bigint = 3000
                         and r->'gems'->0->>'location_id' is null and r->'gems'->0->>'district' is not null, 'status hides places: ' || r::text);
  begin perform gem_find(picks[1]); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like 'Go there first%', 'must be there: ' || coalesce(m, 'none'));
  update profiles set location_id = picks[1], travel_to = picks[2] where id = u;
  begin perform gem_find(picks[1]); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like 'Go there first%', 'not while travelling: ' || coalesce(m, 'none'));
  select id into g from locations where active and private_home_owner_id is null and scene = 'market' and not (id = any(picks)) limit 1;
  update profiles set location_id = g, travel_to = null where id = u;
  begin perform gem_find(g); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like 'No gem here%', 'no gem at other place: ' || coalesce(m, 'none'));
  update profiles set location_id = picks[1], travel_to = null where id = u;
  r := gem_hunt_status();
  perform pg_temp.assert(r->>'here' = picks[1], 'status says gem here');
  select cash into c0 from profiles where id = u;
  r := gem_find(picks[1]);
  select cash into c1 from profiles where id = u;
  perform pg_temp.assert(c1 - c0 = 3000 and (r->>'found')::int = 1, 'first gem 3000: ' || r::text);

  -- 6. no double find
  begin perform gem_find(picks[1]); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like 'You already found%', 'double find refused: ' || coalesce(m, 'none'));

  -- 7. all found: last gem pays prize + bonus; counters
  update profiles set location_id = picks[2] where id = u;
  perform gem_find(picks[2]);
  r := gem_hunt_status();
  perform pg_temp.assert((r->>'next_prize')::bigint = 8000, 'last gem shows prize + bonus');
  update profiles set location_id = picks[3] where id = u;
  select cash into c0 from profiles where id = u;
  r := gem_find(picks[3]);
  select cash into c1 from profiles where id = u;
  perform pg_temp.assert(c1 - c0 = 8000 and (r->>'bonus')::bigint = 5000, 'bonus paid: ' || r::text);
  perform pg_temp.assert(exists (select 1 from ledger where user_id = u and reason = 'Daily gem hunt bonus (all found)'), 'bonus ledger');
  r := gem_hunt_status();
  perform pg_temp.assert((r->>'found')::int = 3 and (r->>'next_prize')::bigint = 0 and (r->>'found_all_players')::int >= 3
                         and r->'gems'->0->>'place_name' is not null, 'all found status: ' || r::text);
  perform pg_temp.login(o);
  r := gem_hunt_status();
  perform pg_temp.assert((r->>'found')::int = 0 and (r->>'found_all_players')::int >= 3, 'other player: own 0, global count');

  -- 8. players cannot write the tables directly (and only read their own finds)
  begin
    execute 'set local role authenticated';
    insert into gem_finds (user_id, hunt_date, location_id, prize) values (o, d, picks[1], 999999);
    m := null;
  exception when others then m := sqlerrm; end;
  execute 'reset role';
  perform pg_temp.assert(m is not null, 'player insert gem_finds refused');
  begin
    execute 'set local role authenticated';
    update daily_reward_steps set cash = 99999999 where day = 1;
    m := null;
  exception when others then m := sqlerrm; end;
  execute 'reset role';
  perform pg_temp.assert(m is not null, 'player update daily_reward_steps refused');
  begin
    execute 'set local role authenticated';
    insert into daily_reward_state (user_id, last_claim_date, streak_day) values (o, d - 1, 6);
    m := null;
  exception when others then m := sqlerrm; end;
  execute 'reset role';
  perform pg_temp.assert(m is not null, 'player insert daily_reward_state refused');
  execute 'set local role authenticated';
  select count(*) into n from gem_finds;
  execute 'reset role';
  perform pg_temp.assert(n = 0, 'other player reads none of u''s finds (got ' || n || ')');

  -- 9. switches
  update game_config set value = 'false' where key in ('daily.reward_enabled', 'daily.gems_enabled');
  begin perform daily_reward_claim(); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%switched off%', 'reward off');
  begin perform gem_find(picks[1]); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%switched off%', 'gems off');
  perform pg_temp.assert(not (daily_reward_status()->>'enabled')::boolean and not (gem_hunt_status()->>'enabled')::boolean, 'status shows off');
  raise notice 'ok: daily reward + gem hunt';
end $$;
