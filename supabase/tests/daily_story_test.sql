-- Daily stories with a twist (20261101000100_daily_stories.sql + 20261101000200_daily_story_seeds.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/daily_story_test.sql
-- The clock is pinned to 10:00 Benin time, time moves with bl.test_offset_seconds, randomness is pinned with bl.test_rand
-- (0 = the first outcome, 0.999 = the last one). Groups: 1 grants, RLS, settings, the seeded content · 2 the closed list (bad content is refused) ·
-- 3 eligibility (partner, kids, car, job, ... path) · 4 one story a day, deterministic, no repeat · 5 answering: costs, weighted outcomes,
-- path tilt, cash caps, seeds · 6 the hidden path: nudges, caps, karma, words, whispers, decay, luck, blessing and police ·
-- 7 delayed follow-ups and arcs · 8 the streak · 9 push · 10 switch, admin, RLS, the old weekly story.
update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');
update game_config set value = '0' where key = 'kids.daily_sick_pct';

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

create or replace function pg_temp.advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;
create or replace function pg_temp.minutes(p_m numeric) returns void language sql as $$ select pg_temp.advance(p_m * 60) $$;
create or replace function pg_temp.hours(p_h numeric) returns void language sql as $$ select pg_temp.advance(p_h * 3600) $$;
create or replace function pg_temp.days(p_d numeric) returns void language sql as $$ select pg_temp.advance(p_d * 86400) $$;
create or replace function pg_temp.cfg(p_key text, p_val text) returns void language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;
create or replace function pg_temp.rand(p numeric) returns void language sql as $$ select set_config('bl.test_rand', p::text, true) $$;
create or replace function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('kd.' || p)::uuid $$;
create or replace function pg_temp.cash(p_uid uuid) returns bigint language sql as $$ select cash + bank from profiles where id = p_uid $$;
create or replace function pg_temp.login_as(p text) returns void language sql as $$ select pg_temp.login(pg_temp.u(p)) $$;
create or replace function pg_temp.ledger_n(p_uid uuid, p_label text) returns bigint language sql as $$ select count(*) from ledger where user_id = p_uid and reason = 'life_moment' and meta->>'label' = p_label $$;

create or replace function pg_temp.at(p_uid uuid, p_loc text) returns void
language sql as $$
  update profiles set location_id = p_loc, travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
                      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = bl_now(), rent_due_at = null
   where id = p_uid;
$$;

create or replace function pg_temp.mk(p_name text, p_age interval default interval '30 days') returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@ds.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, protected_until = null, created_at = bl_now() - p_age, cash = 1000000, bank = 0, home_location_id = 'uselu_selfcon',
         energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0 where id = v;
  perform pg_temp.at(v, 'third_east');
  return v;
end $$;

-- a test story (kind daily, chapter or system)
create or replace function pg_temp.mkstory(p_id text, p_choices jsonb, p_cond jsonb default '{}', p_w numeric default 1, p_pw jsonb default '{}', p_kind text default 'daily', p_cd numeric default 0) returns void
language sql as $$
  insert into life_moments (id, title, body, icon, speaker, kind, conditions, path_w, choices, cooldown_days, weight, active)
  values (p_id, 'Test ' || p_id, 'A test story body for ' || p_id || '.', '🧪', 'Tester', p_kind, p_cond, p_pw, p_choices, p_cd, p_w, true)
  on conflict (id) do update set choices = excluded.choices, conditions = excluded.conditions, weight = excluded.weight, path_w = excluded.path_w, kind = excluded.kind, active = true, cooldown_days = excluded.cooldown_days;
$$;
-- a waiting chapter for a user, due now
create or replace function pg_temp.chap(p_user text, p_story text) returns bigint language sql as $$ select bl_story_create(pg_temp.u(p_user), p_story, '{}', bl_now()) $$;
create or replace function pg_temp.answer(p_user text, p_inst bigint, p_choice text) returns jsonb language plpgsql as $$
begin perform pg_temp.login_as(p_user); return story_answer(p_inst, p_choice); end $$;
create or replace function pg_temp.setpath(p_user text, p_key text, p_val int) returns void language plpgsql as $$
begin
  perform bl_path_get(pg_temp.u(p_user));
  execute format('update player_path set %I = %s where user_id = %L', p_key, p_val, pg_temp.u(p_user));
end $$;
create or replace function pg_temp.path(p_user text, p_key text) returns int language sql as $$ select bl_path_value(pg_temp.u(p_user), p_key) $$;
create or replace function pg_temp.today(p_user text) returns jsonb language plpgsql as $$ begin perform pg_temp.login_as(p_user); return story_today(); end $$;

create or replace function pg_temp.arc_step(p_user text, p_story text, p_choice text, p_rand numeric, p_next text) returns void
language plpgsql as $$
declare v uuid := pg_temp.u(p_user); i bigint; r jsonb; v_show timestamptz;
begin
  update life_moments set cooldown_days = 0 where id = p_story;
  perform pg_temp.rand(p_rand);
  select id into i from player_stories where user_id = v and story_id = p_story and status = 'pending' and show_at <= bl_now() order by id desc limit 1;
  if i is null then i := bl_story_create(v, p_story, '{}', bl_now()); end if;
  perform pg_temp.assert(i is not null, 'the chapter ' || p_story || ' is waiting (or can be made)');
  r := pg_temp.answer(p_user, i, p_choice);
  if p_next is null then
    perform pg_temp.assert(not exists (select 1 from player_stories where user_id = v and status = 'pending' and show_at > bl_now()), p_story || ' is the end of the arc');
  else
    select show_at into v_show from player_stories where user_id = v and story_id = p_next and status = 'pending' order by id desc limit 1;
    perform pg_temp.assert(v_show is not null and v_show > bl_now(), p_story || '/' || p_choice || ' (roll ' || p_rand || ') plants ' || p_next || ' for later');
    perform pg_temp.assert((r -> 'reveal' ->> 'seed')::boolean, p_story || ' tells the player something is not over');
    update player_stories set show_at = bl_now() - interval '1 hour' where user_id = v and story_id = p_next and status = 'pending';
  end if;
  delete from player_stories where user_id = v and status = 'pending' and story_id <> coalesce(p_next, '') and show_at > bl_now();
end $$;


-- ---------- setup ----------
do $$
declare
  v_keys text[] := array['adm', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'];
  k text; u uuid;
  v_local timestamp := now() at time zone bl_clock_tz();
  v_target timestamp;
begin
  v_target := date_trunc('day', v_local) + case when v_local::time >= time '10:00' then interval '34 hours' else interval '10 hours' end;
  perform set_config('bl.test_offset_seconds', extract(epoch from (v_target - v_local))::text, true);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  foreach k in array v_keys loop
    u := pg_temp.mk('DS_' || k);
    perform set_config('kd.' || k, u::text, true);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
  update profiles set cash = 1000000, bank = 0 where id <> pg_temp.u('adm');
end $$;

-- ---------- 1. grants, RLS, settings, the seeded content ----------
do $$
declare v text; n int; t text; m life_moments; r record; depth int; v_ids text[]; v_max int := 0; v_e jsonb; v_o jsonb; v_c jsonb;
begin
  foreach v in array array['story_today()', 'story_answer(bigint,text)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || v, 'execute') and has_function_privilege('authenticated', 'public.' || v, 'execute'), v || ' is for signed-in players only');
    perform pg_temp.assert(not has_function_privilege('public', 'public.' || v, 'execute'), v || ' is not public');
  end loop;
  select string_agg(p.proname, ', ') into v from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'bl\_story%' or p.proname like 'bl\_path%')
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'));
  perform pg_temp.assert(v is null, 'the story and path helpers are private: ' || coalesce(v, ''));
  foreach t in array array['player_path', 'path_lines', 'player_stories', 'story_streak'] loop
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || t)::regclass), 'RLS is on for ' || t);
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || t, 'select') and not has_table_privilege('authenticated', 'public.' || t, 'select')
                           and not has_table_privilege('authenticated', 'public.' || t, 'insert') and not has_table_privilege('authenticated', 'public.' || t, 'update')
                           and not has_table_privilege('authenticated', 'public.' || t, 'delete'), 'no direct grants on ' || t);
  end loop;
  -- the path is NOT a column of profiles
  perform pg_temp.assert(not exists (select 1 from information_schema.columns where table_name = 'profiles' and column_name in ('goodwill', 'hustle', 'luck', 'trouble', 'faith', 'family')), 'no path column on profiles');
  perform pg_temp.assert(not exists (select 1 from pg_trigger t join pg_proc f on f.oid = t.tgfoid where t.tgrelid = 'public.profiles'::regclass and f.prosrc ~ 'bl_story|bl_path|player_path|player_stories|story_streak'), 'no trigger of ours on profiles');
  -- settings
  select count(*) into n from game_config where key like 'stories.%' and category = 'stories' and label <> '' and description <> '' and kind is not null and (kind = 'bool' or (min is not null and max is not null));
  perform pg_temp.assert(n >= 30 and n = (select count(*) from game_config where key like 'stories.%'), 'every stories setting has a label, description and limits (' || n || ')');
  perform pg_temp.assert(bl_cfg_bool('stories.daily_enabled') and bl_cfg('stories.per_day') = 1 and bl_cfg('stories.max_nudge') = 6 and bl_cfg('stories.streak_cash_1') = 2000 and bl_cfg('stories.streak_cash_2') = 5000
                         and bl_cfg('stories.streak_cash_3') = 12000 and bl_cfg('stories.streak_days_1') = 3 and bl_cfg('stories.streak_days_2') = 7 and bl_cfg('stories.streak_days_3') = 14
                         and bl_cfg_bool('stories.push_enabled'), 'defaults: 1 a day, nudge 6, streak 3/7/14 for 2k/5k/12k, push on');
  perform pg_temp.assert((select label from game_config where key = 'storyline.enabled') like 'Old weekly story%', 'the old weekly switch is reworded');
  -- content
  perform pg_temp.assert((select count(*) from life_moments where kind = 'daily' and id like 'd\_%') >= 40, 'at least 40 standalone daily stories (' || (select count(*) from life_moments where kind = 'daily' and id like 'd\_%') || ')');
  perform pg_temp.assert(not exists (select 1 from life_moments where kind = 'daily' and (jsonb_array_length(choices) not between 2 and 4 or char_length(body) > 500)), 'every daily has 2 to 4 choices and a body under 500 characters');
  perform pg_temp.assert(not exists (select 1 from life_moments l, jsonb_array_elements(l.choices) ch where l.kind in ('daily', 'chapter') and not (ch ? 'outcomes')), 'every story choice has weighted outcomes');
  perform pg_temp.assert((select count(*) from life_moments l, jsonb_array_elements(l.choices) ch, jsonb_array_elements(ch -> 'outcomes') oc where l.kind = 'daily' and l.id like 'd\_%' and jsonb_array_length(ch -> 'outcomes') >= 2) >= 100, 'many choices have several outcomes (the twist)');
  perform pg_temp.assert(exists (select 1 from life_moments l, jsonb_array_elements(l.choices) ch, jsonb_array_elements(ch -> 'outcomes') oc where oc ->> 'tone' = 'twist') and exists (select 1 from life_moments l, jsonb_array_elements(l.choices) ch, jsonb_array_elements(ch -> 'outcomes') oc where oc ->> 'tone' = 'bad')
                         and exists (select 1 from life_moments l, jsonb_array_elements(l.choices) ch, jsonb_array_elements(ch -> 'outcomes') oc where oc ->> 'tone' = 'funny'), 'good, bad, funny and twist outcomes exist');
  perform pg_temp.assert(not exists (select 1 from life_moments l where l.id ~ '^(d_|a[1-4]_|c_|sys_|path_)' and (l.title || l.body || l.choices::text) ~* 'lagos|shoprite|whatsapp|youtube|tinubu|buhari|obaseki'), 'no wrong city, brand or real politician');
  perform pg_temp.assert(exists (select 1 from life_moments where kind = 'daily' and conditions ? 'partner') and exists (select 1 from life_moments where kind = 'daily' and conditions ? 'kids')
                         and exists (select 1 from life_moments where kind = 'daily' and conditions ? 'car') and exists (select 1 from life_moments where kind = 'daily' and conditions ? 'job')
                         and exists (select 1 from life_moments where kind = 'daily' and conditions ? 'gang') and exists (select 1 from life_moments where kind = 'daily' and conditions ? 'school')
                         and exists (select 1 from life_moments where kind = 'daily' and conditions ? 'business') and exists (select 1 from life_moments where kind = 'daily' and conditions ? 'path'), 'stories use the situation and the path as filters');
  -- every follow-up points at a real story or moment; every chapter can be reached
  for m in select * from life_moments where kind in ('daily', 'chapter', 'system') and id ~ '^(d_|a[1-4]_|c_|sys_|path_)' loop
    for v_c in select * from jsonb_array_elements(m.choices) loop
      for v_e in select x from jsonb_array_elements(coalesce(v_c -> 'effects', '[]'::jsonb) || coalesce((select jsonb_agg(ee) from jsonb_array_elements(coalesce(v_c -> 'outcomes', '[]'::jsonb)) oo, jsonb_array_elements(coalesce(oo -> 'effects', '[]'::jsonb)) ee), '[]'::jsonb)) x loop
        if v_e ->> 't' = 'follow_up' then
          perform pg_temp.assert(exists (select 1 from life_moments where id = v_e ->> 'moment'), m.id || ' follows up a missing story ' || (v_e ->> 'moment'));
          perform pg_temp.assert((v_e ->> 'delay_hours')::numeric between 1 and 168, m.id || ': a seed comes back in 1 to 7 days');
        end if;
      end loop;
    end loop;
  end loop;
  perform pg_temp.assert(not exists (select 1 from life_moments l where l.kind = 'chapter' and l.id ~ '^(a[1-4]_|c_)' and not exists (select 1 from life_moments p where p.choices::text like '%"moment": "' || l.id || '"%')), 'every chapter is reachable from something');
  -- the four arcs: 3 to 5 chapters deep, and the chapters differ by the choices (branching)
  for r in select p from unnest(array['a1_', 'a2_', 'a3_', 'a4_']) p loop
    with recursive walk(id, d) as (
      select l.id, 1 from life_moments l where l.id = r.p || '1'
      union all
      select nx.id, w.d + 1
        from walk w join life_moments l on l.id = w.id
        join lateral (select distinct x ->> 'moment' as id
                        from jsonb_array_elements(l.choices) ch, jsonb_array_elements(ch -> 'outcomes') oc, jsonb_array_elements(coalesce(oc -> 'effects', '[]'::jsonb)) x
                       where x ->> 't' = 'follow_up') nx on true
       where w.d < 8)
    select max(d) into depth from walk;
    perform pg_temp.assert(depth between 3 and 5, 'arc ' || r.p || ' has a longest path of ' || depth || ' chapters (3 to 5)');
    perform pg_temp.assert((select count(distinct x ->> 'moment') from life_moments l, jsonb_array_elements(l.choices) ch, jsonb_array_elements(ch -> 'outcomes') oc, jsonb_array_elements(coalesce(oc -> 'effects', '[]'::jsonb)) x
                             where l.id = r.p || '1' and x ->> 't' = 'follow_up') >= 2, 'arc ' || r.p || ': the first choice sends you to different chapters');
  end loop;
  perform pg_temp.assert((select count(*) from path_lines) = 24 and not exists (select 1 from path_lines where word = '' or whisper = ''), 'the path has 24 words and lines');
  perform pg_temp.assert(exists (select 1 from path_lines where whisper = 'People around Ugbowo are starting to trust you.') and exists (select 1 from path_lines where whisper like 'You have got a reputation for cutting corners%'), 'the sample subtle lines exist');
  perform pg_temp.assert(not exists (select 1 from life_moments where id like 'path\_%' and kind <> 'system') and (select count(*) from life_moments where id like 'path\_blessing%') >= 3 and (select count(*) from life_moments where id like 'path\_police%') >= 1
                         and exists (select 1 from life_moments where id like 'path\_efcc%'), 'blessing and police / EFCC scenes exist as pop-up moments');
  perform pg_temp.assert(not exists (select 1 from life_moments l, jsonb_array_elements(l.choices) ch, jsonb_array_elements(coalesce(ch -> 'effects', '[]'::jsonb)) ef where l.id like 'path\_blessing%' and ef ->> 't' = 'cash' and (ef ->> 'amount')::numeric > bl_cfg('stories.max_cash_gain')), 'a blessing never pays more than the story cap');
  -- they all re-validate
  for m in select * from life_moments loop
    perform bl_moment_check_choices(m.choices); perform bl_moment_check_conditions(m.conditions);
  end loop;
  raise notice 'ok 1: grants, RLS, settings, content';
end $$;

-- ---------- 2. the closed list: bad content is refused when it is saved ----------
create or replace function pg_temp.try_story(p_choices text, p_kind text default 'daily', p_cond text default '{}', p_pw text default '{}', p_active boolean default true) returns text
language plpgsql as $$
declare v_h text;
begin
  begin
    insert into life_moments (id, title, body, kind, conditions, path_w, choices, active) values ('v_' || substr(md5(random()::text), 1, 8), 'Validator story', 'A test story for the validator.', p_kind, p_cond::jsonb, p_pw::jsonb, p_choices::jsonb, p_active);
    return 'ok';
  exception when others then
    get stacked diagnostics v_h = pg_exception_hint;
    return coalesce(nullif(v_h, ''), sqlerrm) || ' | ' || sqlerrm;
  end;
end $$;

do $$
declare r text; v_two text := '{"id":"b","label":"Two","outcomes":[{"text":"Fine."}]}';
  v_ok text := '[{"id":"a","label":"One","path":{"goodwill":3},"outcomes":[{"id":"yes","w":60,"tone":"good","text":"Good.","effects":[{"t":"cash","amount":500},{"t":"path","delta":{"luck":1}}]},{"id":"no","w":40,"tone":"twist","text":"Twist.","requires":{"partner":false},"path_w":{"trouble":1}}]},{"id":"b","label":"Two","outcomes":[{"text":"Fine."}]}]';
begin
  perform pg_temp.assert(pg_temp.try_story(v_ok) = 'ok', 'a valid daily story with outcomes is saved: ' || pg_temp.try_story(v_ok));
  perform pg_temp.assert(pg_temp.try_story(v_ok, 'chapter') = 'ok', 'and so is a chapter');
  perform pg_temp.assert(pg_temp.try_story(v_ok, 'random') <> 'ok', 'outcomes are refused on a plain pop-up moment');
  foreach r in array array['{"id":"a","label":"One","outcomes":[]}', '{"id":"a","label":"One","outcomes":[{"text":""}]}', '{"id":"a","label":"One","outcomes":[{"text":"x","tone":"purple"}]}',
                           '{"id":"a","label":"One","outcomes":[{"text":"x","w":0}]}', '{"id":"a","label":"One","outcomes":[{"text":"x","w":5000}]}', '{"id":"a","label":"One","outcomes":[{"text":"x","run":"1"}]}',
                           '{"id":"a","label":"One","outcomes":[{"text":"x","effects":[{"t":"sql"}]}]}', '{"id":"a","label":"One","outcomes":[{"text":"x","requires":{"sql":"1"}}]}',
                           '{"id":"a","label":"One","outcomes":[{"text":"x","requires":{"partner":"yes"}}]}', '{"id":"a","label":"One","outcomes":[{"text":"x","path_w":{"money":1}}]}',
                           '{"id":"a","label":"One","outcomes":[{"text":"x","path_w":{"luck":9}}]}', '{"id":"a","label":"One","outcomes":[{"id":"x","text":"x"},{"id":"x","text":"y"}]}',
                           '{"id":"a","label":"One","outcomes":"win"}', '{"id":"a","label":"One","outcomes":[1,2,3,4,5,6,7].map}', '{"id":"a","label":"One","path":{"cash":5},"outcomes":[{"text":"x"}]}',
                           '{"id":"a","label":"One","path":{"luck":99},"outcomes":[{"text":"x"}]}', '{"id":"a","label":"One","path":[1],"outcomes":[{"text":"x"}]}',
                           '{"id":"a","label":"One","outcomes":[{"text":"x","effects":[{"t":"cash","amount":99999}]}]}', '{"id":"a","label":"One","outcomes":[{"text":"x","effects":[{"t":"path","delta":{"karma":1}}]}]}',
                           '{"id":"a","label":"One","outcomes":[{"text":"x","effects":[{"t":"path","delta":{"luck":50}}]}]}', '{"id":"a","label":"One","outcomes":[{"text":"x","effects":[{"t":"path"}]}]}'] loop
    perform pg_temp.assert(pg_temp.try_story('[' || r || ',' || v_two || ']') <> 'ok', 'refused: ' || r);
  end loop;
  -- conditions
  foreach r in array array['{"partner":true}', '{"kids":false}', '{"car":true}', '{"job":false}', '{"gang":true}', '{"school":true}', '{"business":false}', '{"origin":"nepo"}', '{"path":{"trouble":{"min":15},"goodwill":{"max":-5}}}', '{"min_days":2,"partner":false}'] loop
    perform pg_temp.assert(pg_temp.try_story(v_ok, 'daily', r) = 'ok', 'allowed condition: ' || r);
  end loop;
  foreach r in array array['{"partner":"yes"}', '{"kids":1}', '{"origin":"mid"}', '{"path":{"money":{"min":1}}}', '{"path":{"luck":5}}', '{"path":{"luck":{"min":"x"}}}', '{"path":{"luck":{"min":500}}}', '{"path":{"luck":{"avg":5}}}', '{"path":[]}', '{"partner":true,"pet":true}'] loop
    perform pg_temp.assert(pg_temp.try_story(v_ok, 'daily', r) <> 'ok', 'refused condition: ' || r);
  end loop;
  perform pg_temp.assert(pg_temp.try_story(v_ok, 'daily', '{"at":["oba_market"]}') <> 'ok' and pg_temp.try_story(v_ok, 'daily', '{"hours":[8,12]}') <> 'ok', 'a daily story has no place or hour conditions');
  perform pg_temp.assert(pg_temp.try_story('[' || v_two || ']') <> 'ok' and pg_temp.try_story('[' || v_two || ']', 'daily', '{}', '{}', false) = 'ok', 'a daily story that is on needs 2 choices');
  -- path weights on the story
  perform pg_temp.assert(pg_temp.try_story(v_ok, 'daily', '{}', '{"goodwill":1.5,"trouble":-1}') = 'ok' and pg_temp.try_story(v_ok, 'daily', '{}', '{"money":1}') <> 'ok' and pg_temp.try_story(v_ok, 'daily', '{}', '{"luck":10}') <> 'ok', 'story path weights are checked');
  -- the effect also works inside a plain pop-up moment
  perform pg_temp.assert(pg_temp.try_story('[{"id":"a","label":"One","outcome":"ok","effects":[{"t":"path","delta":{"goodwill":2}}]}]', 'random') = 'ok', 'path effect in a plain moment');
  -- cash gain over the story cap
  perform pg_temp.assert(pg_temp.try_story('[{"id":"a","label":"One","outcomes":[{"text":"x","effects":[{"t":"cash","amount":14000}]}]},' || v_two || ']') = 'ok', 'a gain under the cap');
  perform pg_temp.assert(pg_temp.try_story('[{"id":"a","label":"One","outcomes":[{"text":"x","effects":[{"t":"cash","amount":16000}]}]},' || v_two || ']') <> 'ok', 'a gain over stories.max_cash_gain is refused');
  perform pg_temp.assert(pg_temp.try_story('[{"id":"a","label":"One","effects":[{"t":"cash","amount":16000}],"outcome":"x"},' || v_two || ']') <> 'ok', 'also in the older effects style');
  -- words
  insert into chat_banned_words (word, active) values ('zorbo', true) on conflict do nothing; update chat_banned_words set active = true where word = 'zorbo';
  perform pg_temp.assert(pg_temp.try_story('[{"id":"a","label":"One","outcomes":[{"text":"A zorbo day."}]},' || v_two || ']') <> 'ok', 'a banned word in an outcome is refused');
  -- the kind list
  perform pg_temp.assert(pg_temp.hint_of($q$insert into life_moments (id, title, body, kind) values ('badkind2', 'Title', 'Some body text.', 'magic')$q$) <> 'ok', 'a bad kind is still refused');
  raise notice 'ok 2: closed list';
end $$;

-- ---------- 3. eligibility: the situation and the path ----------
do $$
declare v_c uuid := pg_temp.u('c'); v_d uuid := pg_temp.u('d'); v_a uuid := pg_temp.u('a'); v_day date := bl_wat_date(bl_now()); v_p public.profiles; m life_moments;
  v_ch text := '[{"id":"a","label":"One","outcomes":[{"text":"Fine."}]},{"id":"b","label":"Two","outcomes":[{"text":"Fine."}]}]';
  v_job text; v_crew bigint; v_ind text;
begin
  perform pg_temp.cfg('stories.no_repeat_days', '0');
  update life_moments set active = false where kind = 'daily';
  -- a couple (c and d), kids, a car, a job, a gang, school, a business belong to c
  insert into love_relationships (user_a, user_b, asked_by, status, level, couple_at) values (least(v_c, v_d), greatest(v_c, v_d), v_c, 'couple', 50, bl_now() - interval '10 days');
  perform pg_temp.mkstory('tx_partner', v_ch::jsonb, '{"partner":true}');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) = 'tx_partner', 'a partner story is for a player with a partner');
  perform pg_temp.assert(bl_story_pick(v_a, v_day, 1) is null, 'and never for a single player (no "your wife" for a single Sim)');
  perform pg_temp.mkstory('tx_partner', v_ch::jsonb, '{"partner":false}');
  perform pg_temp.assert(bl_story_pick(v_a, v_day, 1) = 'tx_partner' and bl_story_pick(v_c, v_day, 1) is null, 'a single-only story is for singles');
  -- {partner} is the real partner's name; with no partner it falls back
  perform pg_temp.assert(bl_story_text('Hello {partner}, {name}', v_c, '{}') = 'Hello ' || (select username from profiles where id = v_d) || ', ' || (select username from profiles where id = v_c), '{partner} and {name} are filled in');
  perform pg_temp.assert(bl_story_text('Hi {partner} and {child}', v_a, '{}') = 'Hi your partner and your child', 'with no partner or child, the words are neutral');
  update life_moments set active = false where id = 'tx_partner';
  -- kids
  perform pg_temp.mkstory('tx_kids', v_ch::jsonb, '{"kids":true}');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) is null, 'a kids story needs a child at home');
  insert into kids_children (parent_a, parent_b, status, name, due_at, born_at) values (v_c, v_d, 'home', 'Efosa', bl_now() - interval '20 days', bl_now() - interval '10 days');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) = 'tx_kids' and bl_story_pick(v_a, v_day, 1) is null, 'a kids story is for parents');
  perform pg_temp.assert(bl_story_text('Hi {child}', v_c, '{}') = 'Hi Efosa', '{child} is the child at home');
  update life_moments set active = false where id = 'tx_kids';
  -- car
  perform pg_temp.mkstory('tx_car', v_ch::jsonb, '{"car":true}');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) is null, 'a car story needs a car');
  insert into player_cars (user_id, item_id, plate) values (v_c, 'tokunbo_car', 'BEN-123-AA');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) = 'tx_car' and bl_story_pick(v_a, v_day, 1) is null, 'a car story is for a car owner');
  update life_moments set active = false where id = 'tx_car';
  perform pg_temp.mkstory('tx_nocar', v_ch::jsonb, '{"car":false}');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) is null and bl_story_pick(v_a, v_day, 1) = 'tx_nocar', 'and the no-car story is for everyone else');
  update life_moments set active = false where id = 'tx_nocar';
  -- job
  perform pg_temp.mkstory('tx_job', v_ch::jsonb, '{"job":true}');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) is null, 'a job story needs a job');
  update profiles set job_id = 'tech' where id = v_c;
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) = 'tx_job' and bl_story_pick(v_a, v_day, 1) is null, 'a job story is for the employed');
  update life_moments set active = false where id = 'tx_job';
  -- gang
  perform pg_temp.mkstory('tx_gang', v_ch::jsonb, '{"gang":true}');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) is null, 'a gang story needs a gang');
  insert into crews (name, tag, created_by) values ('DS Test Crew', 'DST', v_c) returning id into v_crew;
  insert into crew_members (user_id, crew_id, rank) values (v_c, v_crew, 'boss');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) = 'tx_gang' and bl_story_pick(v_a, v_day, 1) is null, 'a gang story is for gang members');
  update life_moments set active = false where id = 'tx_gang';
  -- school
  perform pg_temp.mkstory('tx_school', v_ch::jsonb, '{"school":true}');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) is null, 'a school story needs a course');
  insert into course_enrolments (user_id, course_id, status) values (v_c, 'ict_basics', 'enrolled');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) = 'tx_school' and bl_story_pick(v_a, v_day, 1) is null, 'a school story is for students');
  update life_moments set active = false where id = 'tx_school';
  -- business
  perform pg_temp.mkstory('tx_biz', v_ch::jsonb, '{"business":true}');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) is null, 'a business story needs a business');
  select id into v_ind from company_industries limit 1;
  insert into companies (owner_id, name, industry_id, settled_through) values (v_c, 'DS Test Co', v_ind, current_date);
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) = 'tx_biz' and bl_story_pick(v_a, v_day, 1) is null, 'a business story is for owners');
  update life_moments set active = false where id = 'tx_biz';
  -- origin and account age
  perform pg_temp.mkstory('tx_origin', v_ch::jsonb, '{"origin":"nepo"}');
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) is null, 'a nepo story is not for a lapo player');
  update profiles set origin = 'nepo' where id = v_c;
  perform pg_temp.assert(bl_story_pick(v_c, v_day, 1) = 'tx_origin', 'but it is for a nepo player');
  update profiles set origin = 'lapo' where id = v_c;
  update life_moments set active = false where id = 'tx_origin';
  -- the path as a filter
  perform pg_temp.mkstory('tx_shady', v_ch::jsonb, '{"path":{"trouble":{"min":15}}}');
  perform pg_temp.mkstory('tx_saint', v_ch::jsonb, '{"path":{"goodwill":{"min":15},"trouble":{"max":0}}}');
  perform pg_temp.assert(bl_story_pick(v_a, v_day, 1) is null, 'path stories need a path');
  perform pg_temp.setpath('a', 'trouble', 20);
  perform pg_temp.assert(bl_story_pick(v_a, v_day, 1) = 'tx_shady', 'high trouble: the shady story appears');
  perform pg_temp.setpath('a', 'trouble', 5);
  perform pg_temp.assert(bl_story_pick(v_a, v_day, 1) is null, 'low trouble: it does not');
  perform pg_temp.setpath('a', 'goodwill', 30);
  perform pg_temp.assert(bl_story_pick(v_a, v_day, 1) = 'tx_saint' or bl_story_pick(v_a, v_day, 1) is null, 'goodwill alone is not enough when trouble is above 0');
  perform pg_temp.setpath('a', 'trouble', -3);
  perform pg_temp.assert(bl_story_pick(v_a, v_day, 1) = 'tx_saint', 'goodwill with a clean record: the good-name story');
  update life_moments set active = false where id in ('tx_shady', 'tx_saint');
  -- min_days (account age) still works
  perform pg_temp.mkstory('tx_old', v_ch::jsonb, '{"min_days":100}');
  perform pg_temp.assert(bl_story_pick(v_a, v_day, 1) is null, 'the existing conditions still apply (account age)');
  update life_moments set active = false where id = 'tx_old';
  raise notice 'ok 3: eligibility';
end $$;

-- ---------- 4. one story a day, deterministic, never repeated ----------
do $$
declare v_b uuid := pg_temp.u('b'); v_e uuid := pg_temp.u('e'); v_f uuid := pg_temp.u('f'); v_day date := bl_wat_date(bl_now()); x jsonb; y jsonb; i int; v_first text; v_ids text[] := '{}'; v_seen text; n int; v_cnt int[];
  v_ch text := '[{"id":"a","label":"One","outcomes":[{"text":"Fine."}]},{"id":"b","label":"Two","outcomes":[{"text":"Fine."}]}]';
begin
  update life_moments set active = false where kind = 'daily';
  foreach v_seen in array array['tx_p1', 'tx_p2', 'tx_p3'] loop perform pg_temp.mkstory(v_seen, v_ch::jsonb); end loop;
  perform pg_temp.cfg('stories.no_repeat_days', '30');
  -- one a day
  x := pg_temp.today('b');
  perform pg_temp.assert((x ->> 'enabled')::boolean and jsonb_array_length(x -> 'today') = 1 and (x -> 'today' -> 0 ->> 'story') like 'tx\_p%', 'a player gets one story today');
  y := pg_temp.today('b');
  perform pg_temp.assert((y -> 'today' -> 0 ->> 'id') = (x -> 'today' -> 0 ->> 'id') and jsonb_array_length(y -> 'today') = 1, 'asking again returns the same story, not a second one');
  perform pg_temp.assert((select count(*) from player_stories where user_id = v_b and kind = 'daily' and day = v_day) = 1, 'one row for the day');
  perform pg_temp.assert((x -> 'today' -> 0 ->> 'status') = 'pending' and jsonb_array_length(x -> 'today' -> 0 -> 'choices') = 2 and not (x -> 'today' -> 0 ? 'outcomes'), 'the app gets the scene and choices, never the outcomes');
  perform pg_temp.assert(not ((x -> 'today' -> 0 -> 'choices' -> 0)::text like '%effects%' or (x -> 'today' -> 0 -> 'choices' -> 0)::text like '%path%'), 'no effects, no path in what the client sees');
  -- deterministic: the same player and day always pick the same story
  v_first := bl_story_pick(v_e, v_day, 1);
  for i in 1..5 loop perform pg_temp.assert(bl_story_pick(v_e, v_day, 1) = v_first, 'the pick is deterministic'); end loop;
  perform pg_temp.assert(bl_story_pick(v_e, v_day, 1) = bl_story_pick(v_e, v_day, 1) and bl_story_pick(v_e, v_day, 2) is not null, 'and a second slot has its own pick');
  -- over many days every story shows up, roughly evenly
  v_cnt := array[0, 0, 0];
  for i in 1..90 loop
    v_seen := bl_story_pick(v_f, v_day + i, 1);
    v_cnt[substr(v_seen, 5)::int] := v_cnt[substr(v_seen, 5)::int] + 1;
  end loop;
  perform pg_temp.assert(v_cnt[1] > 15 and v_cnt[2] > 15 and v_cnt[3] > 15, 'the pick spreads over the pool: ' || v_cnt::text);
  -- two stories a day when the setting says so, never the same twice in a day
  perform pg_temp.cfg('stories.per_day', '2');
  x := pg_temp.today('e');
  perform pg_temp.assert(jsonb_array_length(x -> 'today') = 2 and (x -> 'today' -> 0 ->> 'story') <> (x -> 'today' -> 1 ->> 'story'), 'stories.per_day = 2: two different stories');
  perform pg_temp.cfg('stories.per_day', '1');
  -- never repeats: day after day, three different stories, then the one seen longest ago
  for i in 1..3 loop
    x := pg_temp.today('f');
    v_ids := v_ids || (x -> 'today' -> 0 ->> 'story');
    perform pg_temp.days(1);
  end loop;
  perform pg_temp.assert((select count(distinct s) from unnest(v_ids) s) = 3, 'three days, three different stories: ' || v_ids::text);
  x := pg_temp.today('f');
  perform pg_temp.assert((x -> 'today' -> 0 ->> 'story') = v_ids[1], 'when everything was seen, the one seen longest ago returns');
  -- an unanswered story fades at midnight
  perform pg_temp.days(1);
  x := pg_temp.today('f');
  perform pg_temp.assert((select count(*) from player_stories where user_id = v_f and kind = 'daily' and status = 'expired') >= 3, 'yesterday''s unanswered stories fade');
  -- a story's own cooldown is respected too
  perform pg_temp.cfg('stories.no_repeat_days', '0');
  update life_moments set cooldown_days = 100 where id in ('tx_p1', 'tx_p2');
  update life_moments set active = false where id = 'tx_p3';
  perform pg_temp.days(1);
  perform pg_temp.assert(bl_story_pick(v_b, bl_wat_date(bl_now()) + 1, 1) is not null, 'a pool that is exhausted still gives a story');
  update life_moments set cooldown_days = 0 where id like 'tx\_%';
  update life_moments set active = false where kind = 'daily';
  perform pg_temp.cfg('stories.no_repeat_days', '30');
  perform pg_temp.assert(bl_story_pick(pg_temp.u('j'), bl_wat_date(bl_now()), 1) is null and (pg_temp.today('j') -> 'today') = '[]'::jsonb, 'no eligible story: an empty day, no error');
  raise notice 'ok 4: one a day, deterministic, no repeat';
end $$;

-- ---------- 5. answering ----------
do $$
declare
  v uuid := pg_temp.u('g'); r jsonb; i bigint; i2 bigint; c0 bigint; v_n int; v_row player_stories; v_lbl text;
  v_one text := '[{"id":"kind","label":"The kind thing","cost":500,"path":{"goodwill":4},"outcomes":[
      {"id":"win","w":50,"tone":"good","text":"It worked, {name}.","effects":[{"t":"cash","amount":1000},{"t":"needs","delta":{"fun":5}}]},
      {"id":"flop","w":50,"tone":"bad","text":"It backfired.","effects":[{"t":"needs","delta":{"stress":10}},{"t":"cash","amount":-300,"up_to":true}]}]},
    {"id":"plain","label":"Do nothing","outcomes":[{"text":"Nothing happens.","tone":"info"}]}]';
begin
  perform pg_temp.mkstory('tx_one', v_one::jsonb, '{}', 1, '{}', 'chapter');
  -- the choice looks kind, the outcome is rolled: first outcome at rand 0, last at 0.999
  i := pg_temp.chap('g', 'tx_one'); c0 := pg_temp.cash(v);
  perform pg_temp.rand(0);
  r := pg_temp.answer('g', i, 'kind');
  perform pg_temp.assert(r -> 'reveal' ->> 'tone' = 'good' and r -> 'reveal' ->> 'outcome' = 'win' and (r -> 'reveal' ->> 'text') like 'It worked, DS_g.%', 'rand 0: the first outcome, {name} filled in: ' || r::text);
  perform pg_temp.assert(pg_temp.cash(v) = c0 - 500 + 1000, 'the cost is paid and the gain arrives');
  perform pg_temp.assert(r -> 'reveal' -> 'effects' ? 'Got ₦1,000' or (r -> 'reveal' -> 'effects') @> '"Got ₦1,000"', 'the chips say what happened: ' || (r -> 'reveal' -> 'effects')::text);
  perform pg_temp.assert((r -> 'reveal' ->> 'seed')::boolean = false and (r -> 'reveal' ->> 'spent')::int = 500 and r -> 'story' ->> 'status' = 'answered', 'no seed, spent 500, the story is answered');
  perform pg_temp.assert(pg_temp.path('g', 'goodwill') = 4, 'the choice''s own nudge landed (the intent counts)');
  perform pg_temp.assert(pg_temp.ledger_n(v, 'Test tx_one') >= 1 and not ('life_moment' = any (bl_earn_reasons())), 'in the ledger as a life moment, never earnings');
  i := pg_temp.chap('g', 'tx_one'); c0 := pg_temp.cash(v);
  perform pg_temp.rand(0.999);
  r := pg_temp.answer('g', i, 'kind');
  perform pg_temp.assert(r -> 'reveal' ->> 'tone' = 'bad' and r -> 'reveal' ->> 'outcome' = 'flop', 'rand 0.999: the kind choice backfires (the twist)');
  perform pg_temp.assert(pg_temp.cash(v) = c0 - 500 - 300 and pg_temp.path('g', 'goodwill') = 8, 'it cost 500 + 300 and still counted as kind');
  -- one answer, no replay
  perform pg_temp.assert(pg_temp.hint_of(format('select pg_temp.answer(%L, %s, %L)', 'g', i, 'kind')) = 'already_answered', 'a story is answered once');
  perform pg_temp.assert(pg_temp.cash(v) = c0 - 800, 'a replay costs and pays nothing');
  i2 := pg_temp.chap('g', 'tx_one');
  perform pg_temp.assert(pg_temp.hint_of(format('select pg_temp.answer(%L, %s, %L)', 'g', i2, 'nope')) = 'bad_choice', 'a wrong choice is refused');
  perform pg_temp.assert(pg_temp.hint_of(format('select pg_temp.answer(%L, %s, %L)', 'h', i2, 'kind')) = 'no_story', 'nobody can answer another player''s story');
  perform pg_temp.assert(pg_temp.hint_of(format('select pg_temp.answer(%L, %s, %L)', 'g', 999999999, 'kind')) = 'no_story', 'unknown story');
  -- not enough money: all or nothing, the story stays open, the path does not move
  update profiles set cash = 100, bank = 0 where id = v;
  perform pg_temp.assert(pg_temp.hint_of(format('select pg_temp.answer(%L, %s, %L)', 'g', i2, 'kind')) = 'not_enough_money', 'a choice you cannot pay for is refused');
  perform pg_temp.assert((select status from player_stories where id = i2) = 'pending' and pg_temp.path('g', 'goodwill') = 8 and pg_temp.cash(v) = 100, 'nothing changed: still open, no nudge, no charge');
  perform pg_temp.assert((pg_temp.today('g') -> 'chapters' -> 0 -> 'choices' -> 0 ->> 'affordable')::boolean = false, 'the app is told the choice is not affordable');
  update profiles set cash = 1000000 where id = v;
  r := pg_temp.answer('g', i2, 'plain');
  perform pg_temp.assert(r -> 'reveal' ->> 'tone' = 'info' and r -> 'reveal' ->> 'text' = 'Nothing happens.', 'a free choice with one outcome');
  -- older style choices (effects, chance, fail_effects) still work in a story
  perform pg_temp.mkstory('tx_old', '[{"id":"go","label":"Go","chance":40,"effects":[{"t":"needs","delta":{"fun":5}}],"outcome":"Old win.","fail_effects":[{"t":"needs","delta":{"fun":-5}}],"fail_outcome":"Old fail."},{"id":"no","label":"No","outcome":"Fine."}]'::jsonb, '{}', 1, '{}', 'chapter');
  i := pg_temp.chap('g', 'tx_old'); perform pg_temp.rand(0.1); r := pg_temp.answer('g', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'text' = 'Old win.' and r -> 'reveal' ->> 'tone' = 'good', 'older style: chance succeeds');
  i := pg_temp.chap('g', 'tx_old'); perform pg_temp.rand(0.9); r := pg_temp.answer('g', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'text' = 'Old fail.' and r -> 'reveal' ->> 'tone' = 'bad', 'older style: chance fails');
  -- an outcome's eligibility filter (requires): the partner outcome never shows for a single player
  perform pg_temp.mkstory('tx_req', '[{"id":"go","label":"Go","outcomes":[{"id":"single","w":1,"tone":"good","text":"Single outcome."},{"id":"couple","w":1000,"tone":"twist","text":"Couple outcome.","requires":{"partner":true}}]},{"id":"no","label":"No","outcomes":[{"text":"Fine."}]}]'::jsonb, '{}', 1, '{}', 'chapter');
  i := pg_temp.chap('g', 'tx_req'); perform pg_temp.rand(0.5); r := pg_temp.answer('g', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'outcome' = 'single', 'an outcome that requires a partner never happens for a single player');
  i := pg_temp.chap('c', 'tx_req'); r := pg_temp.answer('c', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'outcome' = 'couple', 'but it does for a player with a partner');
  -- path weights tilt the outcome: kind players get repaid
  perform pg_temp.mkstory('tx_tilt', '[{"id":"go","label":"Go","outcomes":[{"id":"nothing","w":50,"tone":"info","text":"Nothing."},{"id":"repaid","w":50,"tone":"twist","text":"Repaid!","path_w":{"goodwill":1}}]},{"id":"no","label":"No","outcomes":[{"text":"Fine."}]}]'::jsonb, '{}', 1, '{}', 'chapter');
  perform pg_temp.rand(0.5);
  perform pg_temp.setpath('h', 'goodwill', 0);
  i := pg_temp.chap('h', 'tx_tilt'); r := pg_temp.answer('h', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'outcome' = 'repaid', 'rand 0.5, no path: the second outcome');
  perform pg_temp.setpath('h', 'goodwill', 60);
  i := pg_temp.chap('h', 'tx_tilt'); r := pg_temp.answer('h', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'outcome' = 'repaid', 'with goodwill the repaid outcome is likelier (still repaid at rand 0.5)');
  perform pg_temp.setpath('h', 'goodwill', -60);
  i := pg_temp.chap('h', 'tx_tilt'); r := pg_temp.answer('h', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'outcome' = 'nothing' or r -> 'reveal' ->> 'outcome' = 'repaid', 'a selfish player is not repaid as often');
  perform pg_temp.rand(0.55);
  i := pg_temp.chap('h', 'tx_tilt'); r := pg_temp.answer('h', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'outcome' = 'nothing', 'rand 0.55: goodwill -60 flips the same roll to "nothing" (the path tilts the odds)');
  perform pg_temp.setpath('h', 'goodwill', 60);
  i := pg_temp.chap('h', 'tx_tilt'); r := pg_temp.answer('h', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'outcome' = 'repaid', 'and goodwill +60 gives "repaid" at the same roll');
  -- cash caps: an outcome is cut to stories.max_cash_gain, and the day to stories.daily_gain_cap
  perform pg_temp.mkstory('tx_rich', '[{"id":"go","label":"Go","outcomes":[{"id":"big","w":1,"tone":"good","text":"Windfall.","effects":[{"t":"cash","amount":5000}]}]},{"id":"no","label":"No","outcomes":[{"text":"Fine."}]}]'::jsonb, '{}', 1, '{}', 'chapter');
  perform pg_temp.cfg('stories.max_cash_gain', '2000'); perform pg_temp.cfg('stories.daily_gain_cap', '3000');
  update player_stories set answered_at = answered_at - interval '3 days' where user_id = pg_temp.u('i');
  c0 := pg_temp.cash(pg_temp.u('i'));
  i := pg_temp.chap('i', 'tx_rich'); r := pg_temp.answer('i', i, 'go');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('i')) = c0 + 2000 and (r -> 'reveal' ->> 'gain')::int = 2000, 'a 5,000 gain is cut to the 2,000 story cap');
  i := pg_temp.chap('i', 'tx_rich'); r := pg_temp.answer('i', i, 'go');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('i')) = c0 + 3000, 'the day cap (3,000) leaves only 1,000 for the second');
  i := pg_temp.chap('i', 'tx_rich'); r := pg_temp.answer('i', i, 'go');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('i')) = c0 + 3000 and (r -> 'reveal' ->> 'gain')::int = 0 and r -> 'story' ->> 'status' = 'answered', 'then nothing more today, but the story still plays out');
  perform pg_temp.days(1);
  i := pg_temp.chap('i', 'tx_rich'); r := pg_temp.answer('i', i, 'go');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('i')) = c0 + 5000, 'a new Benin day, a new allowance');
  perform pg_temp.cfg('stories.max_cash_gain', '15000'); perform pg_temp.cfg('stories.daily_gain_cap', '25000');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = pg_temp.u('i') and reason = 'life_moment' and delta > 0 and reason = any (bl_earn_reasons())), 'story money is never earnings');
  -- seeds: the planted follow-up is reported ("Something tells you this isn't over") and respects its chance
  perform pg_temp.mkstory('tx_seed', '[{"id":"go","label":"Go","outcomes":[{"id":"plant","w":1,"tone":"twist","text":"Hmm.","effects":[{"t":"follow_up","moment":"tx_later","delay_hours":48,"chance":100}]}]},
                                       {"id":"maybe","label":"Maybe","outcomes":[{"id":"plant","w":1,"tone":"twist","text":"Hmm.","effects":[{"t":"follow_up","moment":"tx_later","delay_hours":48,"chance":50}]}]}]'::jsonb, '{}', 1, '{}', 'chapter');
  perform pg_temp.mkstory('tx_later', '[{"id":"ok","label":"OK","outcomes":[{"text":"Later.","tone":"good"}]}]'::jsonb, '{}', 0, '{}', 'chapter');
  perform pg_temp.rand(0.4);
  i := pg_temp.chap('h', 'tx_seed'); r := pg_temp.answer('h', i, 'go');
  perform pg_temp.assert((r -> 'reveal' ->> 'seed')::boolean, 'a planted seed is reported');
  perform pg_temp.assert(exists (select 1 from player_stories where user_id = pg_temp.u('h') and story_id = 'tx_later' and status = 'pending' and show_at > bl_now() + interval '47 hours' and show_at < bl_now() + interval '49 hours'), 'it comes back in 48 hours');
  perform pg_temp.assert(bl_story_pending_seeds(pg_temp.u('h')) = 1, 'one waiting seed');
  perform pg_temp.rand(0.7);
  i := pg_temp.chap('d', 'tx_seed'); r := pg_temp.answer('d', i, 'maybe');
  perform pg_temp.assert(not (r -> 'reveal' ->> 'seed')::boolean and bl_story_pending_seeds(pg_temp.u('d')) = 0, 'a seed whose chance fails is not planted and not reported');
  -- the global chance cap, the waiting cap and the delay cap
  perform pg_temp.cfg('stories.followup_max_chance', '0'); perform pg_temp.rand(0.4);
  i := pg_temp.chap('d', 'tx_seed'); r := pg_temp.answer('d', i, 'go');
  perform pg_temp.assert(not (r -> 'reveal' ->> 'seed')::boolean, 'stories.followup_max_chance = 0: no seeds at all');
  perform pg_temp.cfg('stories.followup_max_chance', '100'); perform pg_temp.cfg('stories.followup_max_pending', '1');
  perform pg_temp.mkstory('tx_later2', '[{"id":"ok","label":"OK","outcomes":[{"text":"Later.","tone":"good"}]}]'::jsonb, '{}', 0, '{}', 'chapter');
  perform pg_temp.mkstory('tx_seed2', '[{"id":"go","label":"Go","outcomes":[{"id":"plant","w":1,"tone":"twist","text":"Hmm.","effects":[{"t":"follow_up","moment":"tx_later2","delay_hours":24}]}]},{"id":"no","label":"No","outcomes":[{"text":"x"}]}]'::jsonb, '{}', 1, '{}', 'chapter');
  i := pg_temp.chap('d', 'tx_seed2'); r := pg_temp.answer('d', i, 'go');
  perform pg_temp.assert((r -> 'reveal' ->> 'seed')::boolean, 'the first waiting seed is planted');
  perform pg_temp.mkstory('tx_later3', '[{"id":"ok","label":"OK","outcomes":[{"text":"Later.","tone":"good"}]}]'::jsonb, '{}', 0, '{}', 'chapter');
  perform pg_temp.mkstory('tx_seed3', '[{"id":"go","label":"Go","outcomes":[{"id":"plant","w":1,"tone":"twist","text":"Hmm.","effects":[{"t":"follow_up","moment":"tx_later3","delay_hours":24}]}]},{"id":"no","label":"No","outcomes":[{"text":"x"}]}]'::jsonb, '{}', 1, '{}', 'chapter');
  i := pg_temp.chap('d', 'tx_seed3'); r := pg_temp.answer('d', i, 'go');
  perform pg_temp.assert(not (r -> 'reveal' ->> 'seed')::boolean and bl_story_pending_seeds(pg_temp.u('d')) = 1, 'stories.followup_max_pending = 1: a second waiting seed is skipped');
  perform pg_temp.cfg('stories.followup_max_pending', '4');
  perform pg_temp.mkstory('tx_far', '[{"id":"go","label":"Go","outcomes":[{"id":"plant","w":1,"tone":"twist","text":"Hmm.","effects":[{"t":"follow_up","moment":"tx_later","delay_hours":700}]}]},{"id":"no","label":"No","outcomes":[{"text":"x"}]}]'::jsonb, '{}', 1, '{}', 'chapter');
  delete from player_stories where user_id = pg_temp.u('e') ;
  i := pg_temp.chap('e', 'tx_far'); r := pg_temp.answer('e', i, 'go');
  perform pg_temp.assert((select show_at from player_stories where user_id = pg_temp.u('e') and story_id = 'tx_later' and status = 'pending') <= bl_now() + interval '7 days 1 minute', 'a seed never waits more than stories.followup_max_days');
  -- the same chapter is never waiting twice
  i := pg_temp.chap('e', 'tx_far'); r := pg_temp.answer('e', i, 'go');
  perform pg_temp.assert((select count(*) from player_stories where user_id = pg_temp.u('e') and story_id = 'tx_later' and status = 'pending') = 1, 'one waiting copy of a chapter');
  raise notice 'ok 5: answering';
end $$;

-- ---------- 6. the hidden path ----------
do $$
declare v uuid := pg_temp.u('d'); r jsonb; d jsonb; i bigint; v_t text; v_ids text[]; n int; s jsonb;
begin
  delete from player_path where user_id = v;
  perform pg_temp.cfg('stories.whisper_pct', '0');
  -- nudges are cut to stories.max_nudge, never beyond the limits
  d := bl_path_nudge(v, '{"goodwill":100,"hustle":-100,"luck":2,"cash":50,"nonsense":1}');
  perform pg_temp.assert(pg_temp.path('d', 'goodwill') = 6 and pg_temp.path('d', 'hustle') = -6, 'a nudge is cut to 6 (stories.max_nudge): ' || d::text);
  perform pg_temp.assert(pg_temp.path('d', 'luck') = 3, 'goodwill +6 drifts luck up by 1 (karma 30 %): luck 2 + 1');
  perform pg_temp.assert(d = '{"goodwill":6,"hustle":-6,"luck":3}'::jsonb, 'unknown scores are ignored');
  d := bl_path_nudge(v, '{"trouble":6}');
  perform pg_temp.assert(pg_temp.path('d', 'trouble') = 6 and pg_temp.path('d', 'luck') = 2, 'a shady choice drifts luck down');
  perform pg_temp.cfg('stories.max_nudge', '0');
  perform pg_temp.assert(bl_path_nudge(v, '{"goodwill":5}') = '{}'::jsonb and pg_temp.path('d', 'goodwill') = 6, 'max nudge 0: the path never moves');
  perform pg_temp.cfg('stories.max_nudge', '6');
  perform pg_temp.cfg('stories.karma_pct', '0');
  d := bl_path_nudge(v, '{"goodwill":3}');
  perform pg_temp.assert(not (d ? 'luck'), 'karma 0: luck does not drift');
  perform pg_temp.cfg('stories.karma_pct', '30');
  perform pg_temp.setpath('d', 'goodwill', 98);
  perform bl_path_nudge(v, '{"goodwill":6}'); perform bl_path_nudge(v, '{"goodwill":6}');
  perform pg_temp.assert(pg_temp.path('d', 'goodwill') = 100, 'scores stop at 100');
  perform pg_temp.setpath('d', 'trouble', -99);
  perform bl_path_nudge(v, '{"trouble":-6}');
  perform pg_temp.assert(pg_temp.path('d', 'trouble') = -100, 'and at -100');
  perform pg_temp.assert(pg_temp.hint_of($q$update player_path set luck = 101 where user_id = (select user_id from player_path limit 1)$q$) <> 'ok', 'the table itself refuses values past 100');
  -- the path effect inside a plain pop-up moment
  perform pg_temp.setpath('d', 'goodwill', 0); perform pg_temp.setpath('d', 'luck', 0); perform pg_temp.setpath('d', 'faith', 0);
  insert into life_moments (id, title, body, kind, choices, weight) values ('tx_pop', 'Pop-up path', 'A pop-up with a path nudge.', 'random', '[{"id":"go","label":"Go","outcome":"Done.","effects":[{"t":"path","delta":{"faith":20}}]}]'::jsonb, 0) on conflict do nothing;
  perform pg_temp.login_as('d');
  r := moments_answer(bl_moment_create(v, 'tx_pop', '{}', bl_now(), true), 'go');
  perform pg_temp.assert(pg_temp.path('d', 'faith') = 6, 'a pop-up moment can nudge the path too (cut to 6)');
  -- the client never sees numbers
  s := pg_temp.today('d') -> 'path';
  perform pg_temp.assert((select array_agg(k order by k) from jsonb_object_keys(s) k) = array['notes', 'title'] and jsonb_typeof(s -> 'title') = 'string', 'the path card is a sentence and notes, no numbers: ' || s::text);
  perform pg_temp.assert(s::text !~ '[0-9]', 'there is not one digit in it');
  -- words: "A kind hustler with a bit of luck"
  perform pg_temp.setpath('d', 'goodwill', 20); perform pg_temp.setpath('d', 'hustle', 20); perform pg_temp.setpath('d', 'luck', 15); perform pg_temp.setpath('d', 'trouble', 0); perform pg_temp.setpath('d', 'faith', 0);
  perform pg_temp.assert(bl_path_describe(v) ->> 'title' = 'A kind hustler with a bit of luck', 'the sample sentence: ' || (bl_path_describe(v) ->> 'title'));
  perform pg_temp.setpath('d', 'trouble', -40);
  perform pg_temp.assert(bl_path_describe(v) ->> 'title' = 'An upright and kind hustler with a bit of luck', 'two adjectives, the strongest first: ' || (bl_path_describe(v) ->> 'title'));
  perform pg_temp.setpath('d', 'hustle', -15); perform pg_temp.setpath('d', 'luck', -40); perform pg_temp.setpath('d', 'trouble', 20);
  perform pg_temp.assert(bl_path_describe(v) ->> 'title' = 'A kind and corner-cutting careful planner walking under a small dark cloud', 'other side: ' || (bl_path_describe(v) ->> 'title'));
  perform pg_temp.assert(jsonb_array_length(bl_path_describe(v) -> 'notes') = 3, 'up to three notes in words');
  update path_lines set word = 'saintly' where id = 'goodwill_up_1';
  perform pg_temp.setpath('d', 'hustle', 0); perform pg_temp.setpath('d', 'luck', 0); perform pg_temp.setpath('d', 'trouble', 0);
  perform pg_temp.assert(bl_path_describe(v) ->> 'title' = 'A saintly soul', 'the words are editable: ' || (bl_path_describe(v) ->> 'title'));
  update path_lines set word = 'kind' where id = 'goodwill_up_1';
  perform pg_temp.setpath('d', 'goodwill', 5);
  perform pg_temp.assert(bl_path_describe(v) ->> 'title' = 'Your story is only starting', 'below the first level: just starting');
  -- the subtle lines: once when a score crosses a level, never twice
  delete from player_path where user_id = v;
  perform pg_temp.setpath('d', 'goodwill', 9);
  perform pg_temp.mkstory('tx_nudge', '[{"id":"go","label":"Go","path":{"goodwill":4},"outcomes":[{"text":"Done.","tone":"good"}]},{"id":"no","label":"No","outcomes":[{"text":"x"}]}]'::jsonb, '{}', 1, '{}', 'chapter');
  i := pg_temp.chap('d', 'tx_nudge'); r := pg_temp.answer('d', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'whisper' = 'People around Ugbowo are starting to trust you.', 'crossing the first level: the subtle line (' || coalesce(r -> 'reveal' ->> 'whisper', 'none') || ')');
  i := pg_temp.chap('d', 'tx_nudge'); r := pg_temp.answer('d', i, 'go');
  perform pg_temp.assert(r -> 'reveal' -> 'whisper' = 'null'::jsonb, 'the same level again: no repeat');
  perform pg_temp.setpath('d', 'goodwill', 33);
  i := pg_temp.chap('d', 'tx_nudge'); r := pg_temp.answer('d', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'whisper' = 'Neighbours greet you like family now. Your name travels before you.', 'crossing the strong level: the second line');
  perform pg_temp.setpath('d', 'goodwill', 20); perform pg_temp.setpath('d', 'goodwill', 33);
  i := pg_temp.chap('d', 'tx_nudge'); r := pg_temp.answer('d', i, 'go');
  perform pg_temp.assert(r -> 'reveal' -> 'whisper' = 'null'::jsonb, 'down and up again: the line is not repeated');
  perform pg_temp.setpath('d', 'trouble', 10);
  perform pg_temp.mkstory('tx_shady_nudge', '[{"id":"go","label":"Go","path":{"trouble":4},"outcomes":[{"text":"Done.","tone":"bad"}]},{"id":"no","label":"No","outcomes":[{"text":"x"}]}]'::jsonb, '{}', 1, '{}', 'chapter');
  i := pg_temp.chap('d', 'tx_shady_nudge'); r := pg_temp.answer('d', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'whisper' like 'You have got a reputation for cutting corners.%', 'a shady choice gets a shady line');
  -- sometimes a line without a crossing (stories.whisper_pct)
  perform pg_temp.cfg('stories.whisper_pct', '100'); perform pg_temp.rand(0.1);
  i := pg_temp.chap('d', 'tx_nudge'); r := pg_temp.answer('d', i, 'go');
  perform pg_temp.assert(r -> 'reveal' ->> 'whisper' is not null, 'whisper chance 100 %: a line about the strongest path');
  perform pg_temp.cfg('stories.whisper_pct', '0');
  -- the scores fade a little every week
  perform pg_temp.setpath('d', 'goodwill', 10); perform pg_temp.setpath('d', 'trouble', -3);
  update player_path set decayed_on = bl_wat_date(bl_now()) - 15 where user_id = v;
  perform bl_path_get(v);
  perform pg_temp.assert(pg_temp.path('d', 'goodwill') = 6 and pg_temp.path('d', 'trouble') = 0, 'two weeks pass: 2 points a week towards zero (10 -> 6, -3 -> 0)');
  perform pg_temp.assert((select decayed_on from player_path where user_id = v) = bl_wat_date(bl_now()) - 1, 'the clock moves by whole weeks');
  -- the path tilts weights, but never beyond stories.path_max_mult
  perform pg_temp.setpath('d', 'goodwill', 100);
  perform pg_temp.assert(bl_path_mult((select p from player_path p where user_id = v), '{"goodwill":3}') = 3, 'a weight is never more than 3 times');
  perform pg_temp.assert(round(bl_path_mult((select p from player_path p where user_id = v), '{"goodwill":-3}'), 4) = round(1 / 3.0, 4), 'nor less than a third');
  perform pg_temp.assert(bl_path_mult((select p from player_path p where user_id = v), '{"goodwill":1}') = 2.5 and bl_path_mult((select p from player_path p where user_id = v), '{}') = 1, 'in between it is 1 + weight x score x strength (2.5)');
  perform pg_temp.cfg('stories.path_strength', '0');
  perform pg_temp.assert(bl_path_mult((select p from player_path p where user_id = v), '{"goodwill":3}') = 1, 'strength 0: the path never tilts anything');
  perform pg_temp.cfg('stories.path_strength', '1.5');
  perform pg_temp.assert(bl_story_luck_mult(100, 'good') = 1.2 and bl_story_luck_mult(100, 'bad') = 0.8 and bl_story_luck_mult(100, 'twist') = 1 and bl_story_luck_mult(0, 'good') = 1 and bl_story_luck_mult(-100, 'good') = 0.8, 'luck: good +20 %, bad -20 % at most');
  -- luck leans a pop-up's chance by at most 5 points, and never makes a certainty
  perform pg_temp.setpath('d', 'luck', 100);
  perform pg_temp.assert(bl_story_luck_chance(v, 50, 'random') = 55 and bl_story_luck_chance(v, 99, 'random') = 99 and bl_story_luck_chance(v, 1, 'random') = 6, 'luck 100: +5 points');
  perform pg_temp.setpath('d', 'luck', -100);
  perform pg_temp.assert(bl_story_luck_chance(v, 50, 'random') = 45 and bl_story_luck_chance(v, 2, 'random') = 1, 'luck -100: -5 points, never to 0');
  perform pg_temp.setpath('d', 'luck', 50);
  perform pg_temp.assert(bl_story_luck_chance(v, 50, 'random') = 52.5, 'in between, in proportion');
  perform pg_temp.assert(bl_story_luck_chance(v, 100, 'random') = 100 and bl_story_luck_chance(v, 0, 'random') = 0 and bl_story_luck_chance(v, 50, 'kids_ill') = 50 and bl_story_luck_chance(v, 50, 'kids_school') = 50, 'sure things and doctor cards are left fair');
  perform pg_temp.cfg('stories.luck_chance_cap', '0');
  perform pg_temp.assert(bl_story_luck_chance(v, 50, 'random') = 50, 'cap 0: no luck effect');
  perform pg_temp.cfg('stories.luck_chance_cap', '5');
  -- and it works in a real pop-up: chance 50, roll 0.52, luck +50 (+2.5 points) flips it
  insert into life_moments (id, title, body, kind, choices, weight) values ('tx_luck', 'Luck check', 'A pop-up with a chance.', 'random',
    '[{"id":"go","label":"Go","chance":50,"outcome":"Lucky.","effects":[{"t":"needs","delta":{"fun":1}}],"fail_outcome":"Unlucky."}]'::jsonb, 0) on conflict do nothing;
  perform pg_temp.login_as('d');
  perform pg_temp.rand(0.52);
  r := moments_answer(bl_moment_create(v, 'tx_luck', '{}', bl_now(), true), 'go');
  perform pg_temp.assert(r ->> 'outcome' = 'Lucky.', 'luck +50 turns a 52 roll into a success at 50 %');
  perform pg_temp.setpath('d', 'luck', -50);
  perform pg_temp.rand(0.49);
  r := moments_answer(bl_moment_create(v, 'tx_luck', '{}', bl_now(), true), 'go');
  perform pg_temp.assert(r ->> 'outcome' = 'Unlucky.', 'and luck -50 turns a 49 roll (a success at 50 %) into a fail');
  raise notice 'ok 6a: nudges, caps, words, whispers, decay, luck';
end $$;

do $$
declare v uuid := pg_temp.u('e'); v_pick text; r jsonb; i int; v_n int; v_id bigint; v_amt numeric;
begin
  -- blessings (goodwill) and police / EFCC scenes (trouble) replace a normal roll, rarely, with a cooldown
  delete from player_path where user_id = v; delete from player_moments where user_id = v;
  perform pg_temp.cfg('stories.blessing_pct', '100'); perform pg_temp.cfg('stories.police_pct', '100'); perform pg_temp.rand(0.3);
  perform pg_temp.assert(bl_path_special(v, 'landlord_levy', bl_now()) = 'landlord_levy', 'no path: a normal moment');
  perform pg_temp.setpath('e', 'goodwill', 10);
  perform pg_temp.assert(bl_path_special(v, 'landlord_levy', bl_now()) = 'landlord_levy', 'goodwill below the line: no blessing');
  perform pg_temp.setpath('e', 'goodwill', 40);
  v_pick := bl_path_special(v, 'landlord_levy', bl_now());
  perform pg_temp.assert(v_pick like 'path\_blessing%', 'goodwill 40: a blessing (' || v_pick || ')');
  perform pg_temp.cfg('stories.blessing_pct', '0');
  perform pg_temp.assert(bl_path_special(v, 'landlord_levy', bl_now()) = 'landlord_levy', 'blessing chance 0: never');
  perform pg_temp.cfg('stories.blessing_pct', '100');
  perform pg_temp.assert(bl_path_special(v, null, bl_now()) like 'path\_blessing%', 'it can fill an empty roll too');
  perform bl_moment_create(v, v_pick, '{}', bl_now(), true);
  perform pg_temp.assert(bl_path_special(v, 'landlord_levy', bl_now()) = 'landlord_levy', 'blessing cooldown: not again for 5 days');
  perform pg_temp.hours(24 * 5 + 1);
  perform pg_temp.assert(bl_path_special(v, 'landlord_levy', bl_now()) like 'path\_blessing%', 'after the cooldown, possible again');
  perform pg_temp.rand(0.99);
  perform pg_temp.assert(bl_path_special(v, 'landlord_levy', bl_now()) like 'path\_blessing%', 'any roll value picks a real blessing');
  -- trouble
  perform pg_temp.setpath('e', 'goodwill', 0); perform pg_temp.setpath('e', 'trouble', 40); perform pg_temp.rand(0.3);
  v_pick := bl_path_special(v, 'landlord_levy', bl_now());
  perform pg_temp.assert(v_pick like 'path\_police%' or v_pick like 'path\_efcc%', 'trouble 40: a police or EFCC scene (' || v_pick || ')');
  perform bl_moment_create(v, v_pick, '{}', bl_now(), true);
  perform pg_temp.assert(bl_path_special(v, 'landlord_levy', bl_now()) = 'landlord_levy', 'police cooldown');
  perform pg_temp.setpath('e', 'trouble', -50);
  perform pg_temp.assert(bl_path_special(v, 'landlord_levy', bl_now()) = 'landlord_levy', 'a clean player never gets a police scene');
  -- a rolled blessing goes through the real roll and counts against the daily cap
  delete from player_moments where user_id = v; delete from player_moment_state where user_id = v;
  perform pg_temp.setpath('e', 'trouble', 0); perform pg_temp.setpath('e', 'goodwill', 40);
  perform pg_temp.login_as('e');
  perform moments_pending();
  perform pg_temp.minutes(11);
  perform moments_pending();
  perform pg_temp.assert((select count(*) from player_moments where user_id = v and moment_id like 'path\_blessing%' and counts) = 1, 'the real roll hands out the blessing and it counts against the daily cap');
  -- a blessing is small and pays through the same closed list: take it
  select pm.id into v_id from player_moments pm where pm.user_id = v and pm.moment_id like 'path\_blessing%';
  r := moments_answer(v_id, (select c ->> 'id' from life_moments l, jsonb_array_elements(l.choices) c where l.id = (select moment_id from player_moments where id = v_id) and not coalesce((c ->> 'ignore')::boolean, false) order by (c ->> 'id') limit 1));
  perform pg_temp.assert(r ->> 'tone' = 'good', 'a blessing can be accepted');
  -- farming check: the most a blessing can pay, times how often it can come
  select max((e ->> 'amount')::numeric) into v_amt from life_moments l, jsonb_array_elements(l.choices) c, jsonb_array_elements(coalesce(c -> 'effects', '[]'::jsonb)) e where l.id like 'path\_blessing%' and e ->> 't' = 'cash';
  perform pg_temp.assert(v_amt <= 3000 and bl_cfg('stories.blessing_cooldown_days') >= 1, 'a blessing pays at most 3,000 and can come once every 5 days at best');
  -- switched off by the master switch
  perform pg_temp.cfg('stories.daily_enabled', 'false');
  perform pg_temp.assert(bl_path_special(v, 'landlord_levy', bl_now() + interval '30 days') = 'landlord_levy', 'master switch off: no special scenes');
  perform pg_temp.cfg('stories.daily_enabled', 'true');
  perform pg_temp.cfg('stories.blessing_pct', '4'); perform pg_temp.cfg('stories.police_pct', '4');
  raise notice 'ok 6b: blessing and police scenes';
end $$;


-- ---------- 7. delayed follow-ups and arcs ----------
do $$
declare v uuid := pg_temp.u('f'); r jsonb; i bigint; x jsonb; v_show timestamptz; v_n int;
begin
  perform pg_temp.rand(0.4);
  delete from player_stories where user_id = v;
  -- a seed comes back later, not before
  i := pg_temp.chap('f', 'tx_seed'); r := pg_temp.answer('f', i, 'go');
  perform pg_temp.assert((r -> 'reveal' ->> 'seed')::boolean, 'seed planted');
  x := pg_temp.today('f');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(x -> 'chapters') c where c ->> 'story' = 'tx_later'), 'not today');
  perform pg_temp.hours(47);
  x := pg_temp.today('f');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(x -> 'chapters') c where c ->> 'story' = 'tx_later'), 'not after 47 hours');
  perform pg_temp.hours(2);
  x := pg_temp.today('f');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(x -> 'chapters') c where c ->> 'story' = 'tx_later'), 'after 49 hours the follow-up is waiting in the Stories app');
  perform pg_temp.assert((x -> 'badge' ->> 'chapters')::int = 1 and (x -> 'badge' ->> 'waiting')::int >= 1, 'and in the badge');
  perform pg_temp.login_as('f');
  perform pg_temp.assert((moments_pending() -> 'story' ->> 'chapters')::int = 1, 'the badge rides on the one cheap poll (moments_pending)');
  perform pg_temp.assert(jsonb_array_length(moments_pending() -> 'moments') = 0 or not exists (select 1 from jsonb_array_elements(moments_pending() -> 'moments') m where m ->> 'moment' = 'tx_later'), 'a story chapter never pops up as a moment card');
  r := pg_temp.answer('f', (x -> 'chapters' -> 0 ->> 'id')::bigint, 'ok');
  perform pg_temp.assert(r -> 'reveal' ->> 'text' = 'Later.' and (r -> 'badge' ->> 'chapters')::int = 0, 'the follow-up plays and the badge clears');
  -- chapters do not touch the daily streak
  perform pg_temp.assert(not exists (select 1 from story_streak where user_id = v), 'a chapter is not a daily read');
  -- a chapter nobody answers fades after stories.chapter_expire_days
  perform pg_temp.rand(0.4);
  i := pg_temp.chap('f', 'tx_seed'); r := pg_temp.answer('f', i, 'go');
  perform pg_temp.hours(49 + 24 * 8);
  x := pg_temp.today('f');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(x -> 'chapters') c where c ->> 'story' = 'tx_later') and exists (select 1 from player_stories where user_id = v and story_id = 'tx_later' and status = 'expired'), 'an old follow-up fades');
  perform pg_temp.assert(pg_temp.hint_of(format('select pg_temp.answer(%L, %s, %L)', 'f', (select id from player_stories where user_id = v and story_id = 'tx_later' and status = 'expired' limit 1), 'ok')) = 'expired', 'and cannot be answered');
  -- a follow-up can also be a pop-up moment (kind system): it waits as a scheduled card and shows up when due
  perform pg_temp.mkstory('tx_to_moment', '[{"id":"go","label":"Go","outcomes":[{"id":"plant","w":1,"tone":"twist","text":"Hmm.","effects":[{"t":"follow_up","moment":"sys_quiet_knock","delay_hours":24}]}]},{"id":"no","label":"No","outcomes":[{"text":"x"}]}]'::jsonb, '{}', 1, '{}', 'chapter');
  i := pg_temp.chap('f', 'tx_to_moment'); r := pg_temp.answer('f', i, 'go');
  perform pg_temp.assert((r -> 'reveal' ->> 'seed')::boolean and exists (select 1 from player_moments where user_id = v and moment_id = 'sys_quiet_knock' and status = 'scheduled'), 'a seed can come back as a pop-up moment');
  perform pg_temp.login_as('f');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(moments_pending() -> 'moments') m where m ->> 'moment' = 'sys_quiet_knock'), 'not before it is due');
  perform pg_temp.hours(25);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(moments_pending() -> 'moments') m where m ->> 'moment' = 'sys_quiet_knock'), 'then it pops up like any moment');
  -- and a plain moment can plant a story chapter
  insert into life_moments (id, title, body, kind, choices, weight) values ('tx_pop2', 'Pop-up seed', 'A pop-up that plants a chapter.', 'random', '[{"id":"go","label":"Go","outcome":"Done.","effects":[{"t":"follow_up","moment":"tx_later","delay_hours":24}]}]'::jsonb, 0) on conflict do nothing;
  perform moments_answer(bl_moment_create(v, 'tx_pop2', '{}', bl_now(), true), 'go');
  perform pg_temp.assert(exists (select 1 from player_stories where user_id = v and story_id = 'tx_later' and status = 'pending'), 'a pop-up moment can plant a story chapter');
  -- the real arc: a1 branches on the choices (the later chapters change with earlier choices)
  delete from player_stories where user_id = pg_temp.u('g'); delete from player_moments where user_id = pg_temp.u('g');
  perform pg_temp.cfg('stories.followup_max_chance', '100');
  perform pg_temp.arc_step('g', 'a1_1', 'help', 0, 'a1_2_help');
  perform pg_temp.arc_step('g', 'a1_2_help', 'careful', 0, 'a1_3_proud');
  perform pg_temp.arc_step('g', 'a1_3_proud', 'fair', 0, 'a1_4_stall');
  perform pg_temp.arc_step('g', 'a1_4_stall', 'yes', 0, null);
  -- the other road through the same arc
  perform pg_temp.arc_step('g', 'a1_1', 'buy', 0, 'a1_2_buy');
  perform pg_temp.arc_step('g', 'a1_2_buy', 'haggle', 0.999, 'a1_3_mend');
  perform pg_temp.arc_step('g', 'a1_3_mend', 'own', 0, 'a1_4_stall');
  perform pg_temp.arc_step('g', 'a1_1', 'pass', 0, 'a1_2_pass');
  perform pg_temp.arc_step('g', 'a1_2_pass', 'sit', 0, 'a1_end_quiet');
  -- a different arc and a different branch: the tokunbo deal
  perform pg_temp.arc_step('g', 'a2_1', 'papers', 0, 'a2_2_papers');
  perform pg_temp.arc_step('g', 'a2_2_papers', 'verify', 0, 'a2_3_deal');
  perform pg_temp.arc_step('g', 'a2_1', 'deposit', 0, 'a2_2_rush');
  perform pg_temp.arc_step('g', 'a2_2_rush', 'wait', 0.999, 'a2_3_walk');
  raise notice 'ok 7: follow-ups, arcs';
end $$;

-- ---------- 8. the streak ----------
do $$
declare v uuid := pg_temp.u('h'); x jsonb; r jsonb; i int; c0 bigint; v_ch text := '[{"id":"a","label":"One","outcomes":[{"text":"Fine.","tone":"good"}]},{"id":"b","label":"Two","outcomes":[{"text":"Fine.","tone":"good"}]}]';
begin
  update life_moments set active = false where kind = 'daily';
  perform pg_temp.mkstory('tx_streak', v_ch::jsonb);
  perform pg_temp.cfg('stories.no_repeat_days', '0');
  delete from story_streak where user_id = v; delete from player_stories where user_id = v;
  perform pg_temp.days(1);
  c0 := pg_temp.cash(v);
  for i in 1..2 loop
    x := pg_temp.today('h'); r := pg_temp.answer('h', (x -> 'today' -> 0 ->> 'id')::bigint, 'a');
    perform pg_temp.assert((r -> 'streak' ->> 'streak')::int = i and (r -> 'reveal' -> 'streak' ->> 'cash')::int = 0, 'day ' || i || ': streak ' || i || ', nothing yet');
    perform pg_temp.days(1);
  end loop;
  x := pg_temp.today('h');
  perform pg_temp.assert((x -> 'streak' ->> 'streak')::int = 2 and (x -> 'streak' -> 'next' ->> 'days')::int = 3 and (x -> 'streak' -> 'next' ->> 'left')::int = 1, 'the streak shows 2 days and one to go: ' || (x -> 'streak')::text);
  r := pg_temp.answer('h', (x -> 'today' -> 0 ->> 'id')::bigint, 'b');
  perform pg_temp.assert((r -> 'reveal' -> 'streak' ->> 'cash')::int = 2000 and (r -> 'reveal' -> 'streak' -> 'paid' -> 0 ->> 'days')::int = 3, 'day 3: the first reward, 2,000: ' || (r -> 'reveal' -> 'streak')::text);
  perform pg_temp.assert(pg_temp.cash(v) = c0 + 2000 and pg_temp.ledger_n(v, 'Story streak (3 days)') = 1, 'it is paid once and labelled in the ledger');
  perform pg_temp.assert((r -> 'streak' -> 'steps' -> 0 ->> 'claimed')::boolean and not (r -> 'streak' -> 'steps' -> 1 ->> 'reached')::boolean, 'the card marks step 1 as claimed');
  -- the same day again (a second answer or a replay) pays nothing more
  perform pg_temp.assert(bl_story_streak_touch(v, bl_wat_date(bl_now())) ->> 'cash' = '0' and pg_temp.cash(v) = c0 + 2000, 'touching the streak twice on one day pays once');
  for i in 4..7 loop
    perform pg_temp.days(1);
    x := pg_temp.today('h'); r := pg_temp.answer('h', (x -> 'today' -> 0 ->> 'id')::bigint, 'a');
    perform pg_temp.assert((r -> 'reveal' -> 'streak' ->> 'cash')::int = case when i = 7 then 5000 else 0 end, 'day ' || i || ': ' || (r -> 'reveal' -> 'streak')::text);
  end loop;
  perform pg_temp.assert(pg_temp.cash(v) = c0 + 7000 and pg_temp.ledger_n(v, 'Story streak (7 days)') = 1, 'day 7: 5,000 more, once');
  for i in 8..14 loop
    perform pg_temp.days(1);
    x := pg_temp.today('h'); r := pg_temp.answer('h', (x -> 'today' -> 0 ->> 'id')::bigint, 'a');
  end loop;
  perform pg_temp.assert(pg_temp.cash(v) = c0 + 19000 and pg_temp.ledger_n(v, 'Story streak (14 days)') = 1, 'day 14: 12,000 more: 19,000 in all');
  perform pg_temp.days(1);
  x := pg_temp.today('h'); r := pg_temp.answer('h', (x -> 'today' -> 0 ->> 'id')::bigint, 'a');
  perform pg_temp.assert((r -> 'streak' ->> 'streak')::int = 15 and pg_temp.cash(v) = c0 + 19000, 'day 15: the streak goes on, no more rewards in this streak');
  -- a missed day starts a new streak and the steps can be earned again
  perform pg_temp.days(2);
  x := pg_temp.today('h');
  perform pg_temp.assert((x -> 'streak' ->> 'streak')::int = 0 and (x -> 'streak' ->> 'best')::int = 15, 'a missed day: the streak is 0, the best stays 15');
  for i in 1..3 loop
    x := pg_temp.today('h'); r := pg_temp.answer('h', (x -> 'today' -> 0 ->> 'id')::bigint, 'a');
    perform pg_temp.days(1);
  end loop;
  perform pg_temp.assert(pg_temp.cash(v) = c0 + 21000 and pg_temp.ledger_n(v, 'Story streak (3 days)') = 2, 'three days again: the first reward is earned again (a new streak)');
  -- two stories in a day are one day of reading
  perform pg_temp.cfg('stories.per_day', '2');
  perform pg_temp.mkstory('tx_streak2', v_ch::jsonb);
  x := pg_temp.today('h');
  r := pg_temp.answer('h', (x -> 'today' -> 0 ->> 'id')::bigint, 'a');
  perform pg_temp.assert((r -> 'streak' ->> 'streak')::int = 4, 'streak 4');
  r := pg_temp.answer('h', (x -> 'today' -> 1 ->> 'id')::bigint, 'a');
  perform pg_temp.assert((r -> 'streak' ->> 'streak')::int = 4, 'the second story of the day does not add a day');
  perform pg_temp.cfg('stories.per_day', '1');
  -- the rewards are settings
  perform pg_temp.cfg('stories.streak_cash_1', '0');
  perform pg_temp.assert((select count(*) from game_config where key ~ '^stories\.streak_(days|cash)_[123]$') = 6, 'six streak settings');
  raise notice 'ok 8: streak';
end $$;

-- ---------- 9. push ----------
do $$
declare v uuid := pg_temp.u('i'); w uuid := pg_temp.u('j'); r jsonb; n int; x jsonb; i bigint;
begin
  perform pg_temp.cfg('push.enabled', 'true'); perform pg_temp.cfg('push.cat_events', 'true'); perform pg_temp.cfg('stories.push_hour', '17');
  insert into push_prefs (user_id, master, events) values (v, true, true), (w, true, true) on conflict (user_id) do update set master = true, events = true;
  insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (v, 'https://push.example/ds-i', 'k', 'a'), (w, 'https://push.example/ds-j', 'k', 'a');
  update profiles set last_seen = bl_now() where id in (v, w);
  delete from player_stories where user_id in (v, w);
  perform bl_story_push_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id in (v, w) and kind = 'story_daily'), 'it is 10:00: too early for the daily push (stories.push_hour 17)');
  perform pg_temp.cfg('stories.push_hour', '9');
  perform bl_story_push_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = v and kind = 'story_daily') = 1 and (select url from push_outbox where user_id = v and kind = 'story_daily') = '/play?go=stories', 'after the hour: one push, opening the Stories app');
  perform bl_story_push_tick(); perform bl_story_push_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = v and kind = 'story_daily') = 1, 'only once per Benin day');
  perform pg_temp.assert((select category from push_outbox where user_id = v and kind = 'story_daily') = 'events', 'in the Game events category (players choose in Settings)');
  -- a player who already read today's story gets nothing
  update life_moments set active = false where kind = 'daily';
  perform pg_temp.mkstory('tx_push', '[{"id":"a","label":"One","outcomes":[{"text":"Fine."}]},{"id":"b","label":"Two","outcomes":[{"text":"Fine."}]}]'::jsonb);
  perform pg_temp.cfg('stories.no_repeat_days', '0');
  perform pg_temp.days(1); update profiles set last_seen = bl_now() where id in (v, w);
  x := pg_temp.today('j'); perform pg_temp.answer('j', (x -> 'today' -> 0 ->> 'id')::bigint, 'a');
  perform bl_story_push_tick();
  perform pg_temp.assert(exists (select 1 from push_outbox where user_id = v and dedupe_key = 'story:' || bl_wat_date(bl_now())) and not exists (select 1 from push_outbox where user_id = w and dedupe_key = 'story:' || bl_wat_date(bl_now())), 'tomorrow: the player who has not read gets one, the one who has read does not');
  -- the switches
  perform pg_temp.days(1); update profiles set last_seen = bl_now() where id in (v, w);
  perform pg_temp.cfg('stories.push_enabled', 'false'); perform bl_story_push_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = v and dedupe_key = 'story:' || bl_wat_date(bl_now())), 'stories.push_enabled off: nothing');
  perform pg_temp.cfg('stories.push_enabled', 'true'); perform pg_temp.cfg('push.cat_events', 'false'); perform bl_story_push_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = v and dedupe_key = 'story:' || bl_wat_date(bl_now())), 'the Game events category off for everyone: nothing');
  perform pg_temp.cfg('push.cat_events', 'true');
  update push_prefs set events = false where user_id = v; perform bl_story_push_tick();
  perform pg_temp.assert(not exists (select 1 from push_outbox where user_id = v and dedupe_key = 'story:' || bl_wat_date(bl_now())), 'a player who turned Game events off gets nothing');
  update push_prefs set events = true where user_id = v;
  -- a follow-up that is due gets its own push, once
  perform pg_temp.mkstory('tx_later_push', '[{"id":"ok","label":"OK","outcomes":[{"text":"Later.","tone":"good"}]}]'::jsonb, '{}', 0, '{}', 'chapter');
  i := bl_story_create(v, 'tx_later_push', '{}', bl_now() - interval '1 hour');
  perform bl_story_push_tick(); perform bl_story_push_tick();
  perform pg_temp.assert((select count(*) from push_outbox where user_id = v and kind = 'story_chapter') = 1, 'a follow-up that is due: one "your story continues" push');
  -- the push job (bl_push_tick) calls it
  perform pg_temp.assert((bl_push_tick() ? 'stories_pushed'), 'bl_push_tick reports the story pushes');
  perform pg_temp.cfg('stories.push_hour', '17');
  raise notice 'ok 9: push';
end $$;

-- ---------- 10. switch, admin, RLS, the old weekly story ----------
do $$
declare v uuid := pg_temp.u('a'); r jsonb; x jsonb; i bigint; v_h text; t text; ok boolean; n int;
begin
  -- switch off
  i := pg_temp.chap('a', 'tx_later');
  perform pg_temp.cfg('stories.daily_enabled', 'false');
  x := pg_temp.today('a');
  perform pg_temp.assert(not (x ->> 'enabled')::boolean and not (x ? 'today'), 'switched off: the app is told, no stories');
  perform pg_temp.assert(pg_temp.hint_of(format('select pg_temp.answer(%L, %s, %L)', 'a', i, 'ok')) = 'stories_off', 'switched off: nothing can be answered');
  perform pg_temp.assert((bl_story_badge(v) ->> 'waiting')::int = 0 and bl_story_push_tick() = 0, 'and no badge, no push');
  perform pg_temp.cfg('stories.daily_enabled', 'true');
  r := pg_temp.answer('a', i, 'ok');
  perform pg_temp.assert(r -> 'reveal' ->> 'text' = 'Later.', 'switched on again: it plays');
  -- the Admin editors
  perform pg_temp.login_as('adm');
  r := admin_row_upsert('life_moments', '{"id":"admin_story","title":"Admin story","body":"A story written in Admin for {name}.","icon":"🎁","speaker":"Somebody","kind":"daily","weight":2,"cooldown_days":10,
     "conditions":{"partner":false},"path_w":{"trouble":1},"choices":[{"id":"yes","label":"Yes","path":{"goodwill":2},"outcomes":[{"id":"a","w":3,"tone":"good","text":"Nice."},{"id":"b","w":1,"tone":"twist","text":"Twist.","effects":[{"t":"path","delta":{"luck":1}}]}]},{"id":"no","label":"No","outcomes":[{"text":"Fine."}]}]}');
  perform pg_temp.assert(r ->> 'message' = 'Added.' and exists (select 1 from life_moments where id = 'admin_story' and path_w = '{"trouble":1}'::jsonb), 'an admin writes a story with outcomes, conditions and path weights: ' || r::text);
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('life_moments', '{"id":"admin_bad_story","title":"Bad","body":"A bad story here.","icon":"X","speaker":"","kind":"daily","weight":1,"cooldown_days":1,"conditions":{},"choices":[{"id":"a","label":"A","outcomes":[{"text":"x","effects":[{"t":"sql"}]}]},{"id":"b","label":"B","outcomes":[{"text":"y"}]}]}')$q$) <> 'ok', 'an admin cannot save a bad outcome effect');
  perform admin_row_upsert('life_moments', '{"id":"admin_story","path_w":{"goodwill":2}}');
  perform pg_temp.assert((select path_w from life_moments where id = 'admin_story') = '{"goodwill":2}'::jsonb, 'an admin edits the path weights');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('life_moments', '{"id":"admin_story","path_w":{"money":2}}')$q$) <> 'ok', 'but not an unknown path score');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('path_lines', '{"id":"bad_line_x","score":"cash","sign":1,"band":1,"word":"x","whisper":"x"}')$q$) <> 'ok', 'a path word needs a real score');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('path_lines', '{"id":"faith_up_2","word":"changed"}')$q$) = 'ok', 'an admin edits a word');
  perform pg_temp.assert((select word from path_lines where id = 'faith_up_2') = 'changed', 'and it is saved');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('path_lines', '{"id":"faith_up_2","word":"hacked"}')$q$) = 'not_admin', 'players cannot edit the path words');
  -- settings are editable in Admin -> Settings
  perform pg_temp.login_as('adm');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_config_set('stories.max_nudge', '8')$q$) = 'ok', 'an admin tunes a setting');
  perform pg_temp.assert(bl_cfg('stories.max_nudge') = 8, 'and it is saved');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_config_set('stories.max_nudge', '999')$q$) <> 'ok', 'within its limits');
  perform pg_temp.cfg('stories.max_nudge', '6');
  -- no client access to the tables, and nobody reads or writes the path
  perform pg_temp.login_as('a');
  set local role authenticated;
  foreach t in array array['player_path', 'path_lines', 'player_stories', 'story_streak'] loop
    begin execute format('select * from public.%I limit 1', t); ok := false; exception when insufficient_privilege then ok := true; end;
    reset role; perform pg_temp.assert(ok, 'clients cannot read ' || t); set local role authenticated;
    begin execute format('delete from public.%I', t); ok := false; exception when insufficient_privilege then ok := true; end;
    reset role; perform pg_temp.assert(ok, 'clients cannot write ' || t); set local role authenticated;
  end loop;
  begin perform bl_path_nudge(pg_temp.u('a'), '{"goodwill":5}'); ok := false; exception when insufficient_privilege then ok := true; end;
  reset role; perform pg_temp.assert(ok, 'a player cannot call the nudge helper to boost their own path');
  set local role anon;
  begin perform story_today(); ok := false; exception when insufficient_privilege then ok := true; end;
  reset role; perform pg_temp.assert(ok, 'anon cannot call story_today');
  -- a deleted account takes its stories and path with it
  perform pg_temp.assert(exists (select 1 from player_path where user_id = pg_temp.u('d')) and exists (select 1 from player_stories where user_id = pg_temp.u('d')), 'precondition');
  delete from auth.users where id = pg_temp.u('d');
  perform pg_temp.assert(not exists (select 1 from player_path where user_id = pg_temp.u('d')) and not exists (select 1 from player_stories where user_id = pg_temp.u('d')) and not exists (select 1 from story_streak where user_id = pg_temp.u('d')), 'deleting an account removes its path, stories and streak');
  -- the old weekly community story still answers (kept for old app versions)
  perform pg_temp.login_as('b');
  x := storyline_current();
  perform pg_temp.assert((x ->> 'enabled')::boolean and x -> 'episode' ->> 'id' is not null, 'the old weekly story still loads');
  -- the indexes the daily read needs
  perform pg_temp.assert(exists (select 1 from pg_indexes where indexname = 'player_stories_daily_slot' and indexdef like '%UNIQUE%') and exists (select 1 from pg_indexes where indexname = 'player_stories_user_status'), 'indexes exist (one daily per player per day is a unique index)');
  raise notice 'ok 10: switch, admin, RLS';
end $$;
