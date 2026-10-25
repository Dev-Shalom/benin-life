-- Life moments engine (20261028000100_life_moments.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/life_moments_test.sql
-- The clock is pinned to 10:00 Benin time, time moves with bl.test_offset_seconds, randomness is pinned with bl.test_rand.
-- Groups: 1 grants / RLS / settings / seeds · 2 the closed list of effects and conditions (bad content is refused when saved) ·
-- 3 the lazy roll: first look, gap, daily cap, cooldown, conditions, busy states, max shown, weights · 4 answering: costs all or nothing,
-- chance, every effect, follow-ups · 5 snooze, expiry, Ignore · 6 switch off, editors, no client access, index.
update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');
-- chance illness is tested in kids_v2_test.sql; here it is off so the stage 2 flows are deterministic
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

create or replace function pg_temp.hours(p_h numeric) returns void language sql as $$ select pg_temp.advance(p_h * 3600) $$;

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('kd.' || p)::uuid $$;
create or replace function pg_temp.cash(p_uid uuid) returns bigint language sql as $$ select cash + bank from profiles where id = p_uid $$;
create or replace function pg_temp.ev(p_uid uuid, p_kind text) returns bigint language sql as $$ select count(*) from events where user_id = p_uid and kind = p_kind $$;
create or replace function pg_temp.login_as(p text) returns void language sql as $$ select pg_temp.login(pg_temp.u(p)) $$;
create or replace function pg_temp.ledger_n(p_uid uuid, p_reason text) returns bigint language sql as $$ select count(*) from ledger where user_id = p_uid and reason = p_reason $$;
create or replace function pg_temp.ledger_sum(p_uid uuid, p_reason text) returns bigint language sql as $$ select coalesce(sum(delta), 0) from ledger where user_id = p_uid and reason = p_reason $$;

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
declare v uuid := pg_temp.new_user(lower(p_name) || '@kd.bl');
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

-- A couple (status couple, together for p_days days), without going through flirts.



create or replace function pg_temp.give(p_user text, p_moment text, p_ctx jsonb default '{}'::jsonb, p_due timestamptz default null) returns bigint
language sql as $$ select bl_moment_create(pg_temp.u(p_user), p_moment, p_ctx, p_due, true) $$;
create or replace function pg_temp.need(p_user text, p_need text) returns numeric language plpgsql as $$
declare v numeric;
begin
  execute format('select %I from profiles where id = %L', p_need, pg_temp.u(p_user)) into v;
  return v;
end $$;
create or replace function pg_temp.pending_ids(p_user text) returns bigint[] language plpgsql as $$
declare v jsonb; r bigint[];
begin
  perform pg_temp.login_as(p_user);
  v := moments_pending();
  select coalesce(array_agg((x->>'id')::bigint order by ord), '{}') into r from jsonb_array_elements(v->'moments') with ordinality t(x, ord);
  return r;
end $$;

-- ---------- setup ----------
do $$
declare
  v_keys text[] := array['adm', 'a', 'b', 'c', 'd', 'new'];
  k text; u uuid;
  v_local timestamp := now() at time zone bl_clock_tz();
  v_target timestamp;
begin
  v_target := date_trunc('day', v_local) + case when v_local::time >= time '10:00' then interval '34 hours' else interval '10 hours' end;
  perform set_config('bl.test_offset_seconds', extract(epoch from (v_target - v_local))::text, true);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  foreach k in array v_keys loop
    u := pg_temp.mk('LM_' || k, case when k = 'new' then interval '1 hour' else interval '30 days' end);
    perform set_config('kd.' || k, u::text, true);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
  update profiles set cash = 1000000, bank = 0 where id <> pg_temp.u('adm');
end $$;

-- ---------- 1. grants / RLS / settings / seeds ----------
do $$
declare v text; n int; m life_moments; c jsonb;
begin
  foreach v in array array['moments_pending()', 'moments_answer(bigint,text)', 'moments_snooze(bigint)', 'moments_seen(bigint)', 'moments_open(bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || v, 'execute') and has_function_privilege('authenticated', 'public.' || v, 'execute'), v || ' is for signed-in players only');
  end loop;
  select string_agg(p.proname, ', ') into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'bl\_moment%' and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'));
  perform pg_temp.assert(v is null, 'the engine helpers are private: ' || coalesce(v, ''));
  select count(*) into n from game_config where key like 'moments.%' and category = 'moments' and label <> '' and description <> '';
  perform pg_temp.assert(n = 11 and n = (select count(*) from game_config where key like 'moments.%'), 'every moments setting has a label and description (' || n || ')');
  perform pg_temp.assert(bl_cfg_bool('moments.enabled') and bl_cfg('moments.daily_cap') = 3 and bl_cfg('moments.snooze_hours') = 2 and bl_cfg('moments.max_snoozes') = 3 and bl_cfg('moments.max_shown') = 2, 'defaults: 3 a day, remind me in 2 hours, 3 snoozes');
  perform pg_temp.assert((select count(*) from life_moments) >= 16 and (select count(*) from life_moments where kind = 'random') = 9 and (select count(*) from life_moments where kind = 'kids_ill') = 6 and (select count(*) from life_moments where kind = 'system') >= 1, 'seeds: 9 everyday, 6 doctor, the follow-ups');
  perform pg_temp.assert(not exists (select 1 from life_moments where jsonb_array_length(choices) not between 1 and 4), 'every moment has 1 to 4 choices');
  perform pg_temp.assert(not exists (select 1 from life_moments where kind = 'kids_ill' and (speaker not like 'Dr. Osagie%' or not push)), 'doctor cards: Dr. Osagie, with a push');
  perform pg_temp.assert((select count(*) from life_moments where kind = 'kids_ill' and choices @> '[{"id":"hospital"},{"id":"chemist"},{"id":"ignore"}]'::jsonb) = 6, 'each doctor card: Hospital, Chemist, Ignore');
  perform pg_temp.assert(not exists (select 1 from life_moments l where l.title ~* 'lagos|shoprite' or l.body ~* 'lagos|shoprite' or exists (select 1 from jsonb_array_elements(l.choices) x where x::text ~* 'lagos|shoprite')), 'no real brand, no wrong city');
  -- the seeds re-validate (they went through the guard when inserted)
  for m in select * from life_moments loop
    perform bl_moment_check_choices(m.choices); perform bl_moment_check_conditions(m.conditions);
  end loop;
  perform pg_temp.assert(('life_moment' <> all (bl_earn_reasons())), 'life_moment is never earnings');
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,life_moment"');
  perform pg_temp.assert(('life_moment' <> all (bl_earn_reasons())), 'not even when an admin lists it');
  perform pg_temp.assert(bl_econ_category('life_moment') = 'Life moments' and bl_ledger_label('life_moment', '{"label":"NEPA don take light"}') = 'NEPA don take light', 'category and label');
  raise notice 'ok 1: grants, settings, seeds';
end $$;

-- ---------- 2. the closed list: bad content is refused when it is saved ----------
create or replace function pg_temp.try_moment(p_choices text, p_cond text default '{}', p_active boolean default true, p_title text default 'Test moment') returns text
language plpgsql as $$
declare v_h text;
begin
  begin
    insert into life_moments (id, title, body, kind, conditions, choices, active) values ('t_' || substr(md5(random()::text), 1, 8), p_title, 'A test story for the validator.', 'random', p_cond::jsonb, p_choices::jsonb, p_active);
    return 'ok';
  exception when others then
    get stacked diagnostics v_h = pg_exception_hint;
    return coalesce(nullif(v_h, ''), sqlerrm) || ' | ' || sqlerrm;
  end;
end $$;

do $$
declare r text; v_good text := '[{"id":"a","label":"Fine","outcome":"Good.","effects":[{"t":"needs","delta":{"fun":5}}]}]';
begin
  perform pg_temp.assert(pg_temp.try_moment(v_good) = 'ok', 'a valid moment is saved');
  -- the effect types that exist
  foreach r in array array[
    '{"t":"cash","amount":-500}', '{"t":"cash","amount":500}', '{"t":"cash","amount":-500,"up_to":true}', '{"t":"needs","delta":{"hunger":10,"stress":-5}}', '{"t":"kid_need","need":"clean","delta":10}',
    '{"t":"kid_cure"}', '{"t":"kid_ignore"}', '{"t":"item","id":"pure_water","qty":2}', '{"t":"item","id":"pure_water","qty":-1}', '{"t":"skill_xp","skill":"charisma","xp":5}',
    '{"t":"street_cred","delta":2}', '{"t":"follow_up","moment":"loan_repaid","delay_hours":24,"chance":35}'] loop
    perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"Go","outcome":"Done.","effects":[' || r || ']}]') = 'ok', 'allowed effect: ' || r);
  end loop;
  -- everything else is refused: this is the closed list
  foreach r in array array[
    '{"t":"sql","code":"drop table profiles"}', '{"t":"eval","js":"alert(1)"}', '{"t":"set","table":"profiles","col":"cash","value":99999999}', '{"t":"cash"}', '{"t":"cash","amount":0}',
    '{"t":"cash","amount":"lots"}', '{"t":"cash","amount":99999999}', '{"t":"cash","amount":-99999999}', '{"t":"needs","delta":{"cash":50}}', '{"t":"needs","delta":{"fun":500}}', '{"t":"needs"}',
    '{"t":"kid_need","need":"cash","delta":5}', '{"t":"kid_need","need":"fun","delta":99}', '{"t":"item","id":"no_such_item","qty":1}', '{"t":"item","id":"pure_water","qty":0}', '{"t":"item","id":"pure_water","qty":99}',
    '{"t":"skill_xp","skill":"no_skill","xp":5}', '{"t":"skill_xp","skill":"charisma","xp":9999}', '{"t":"street_cred","delta":0}', '{"t":"street_cred","delta":500}', '{"t":"follow_up"}', '{"t":"follow_up","moment":"Bad Id"}',
    '{"t":"follow_up","moment":"loan_repaid","chance":150}', '{"t":"follow_up","moment":"loan_repaid","delay_hours":99999}', '{}', '"cash"'] loop
    perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"Go","outcome":"Done.","effects":[' || r || ']}]') <> 'ok', 'refused effect: ' || r);
  end loop;
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"Go","outcome":"Done.","effects":"cash"}]') <> 'ok', 'effects must be a list');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"Go","outcome":"Done.","effects":[{"t":"cash","amount":1},{"t":"cash","amount":1},{"t":"cash","amount":1},{"t":"cash","amount":1},{"t":"cash","amount":1},{"t":"cash","amount":1},{"t":"cash","amount":1},{"t":"cash","amount":1},{"t":"cash","amount":1}]}]') <> 'ok', 'at most 8 effects');
  -- choices
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x"},{"id":"b","label":"2","outcome":"x"},{"id":"c","label":"3","outcome":"x"},{"id":"d","label":"4","outcome":"x"}]') = 'ok', 'four choices are fine');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x"},{"id":"b","label":"2","outcome":"x"},{"id":"c","label":"3","outcome":"x"},{"id":"d","label":"4","outcome":"x"},{"id":"e","label":"5","outcome":"x"}]') <> 'ok', 'five choices are not');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x"},{"id":"a","label":"2","outcome":"x"}]') <> 'ok', 'duplicate choice ids');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"A b","label":"1","outcome":"x"}]') <> 'ok', 'bad choice id');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"","outcome":"x"}]') <> 'ok' and pg_temp.try_moment('[{"id":"a","label":"1"}]') <> 'ok', 'label and outcome are needed');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x","run":"select 1"}]') <> 'ok', 'unknown choice fields are refused');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x","cost":-5}]') <> 'ok' and pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x","cost":99999999}]') <> 'ok' and pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x","cost":1.5}]') <> 'ok', 'cost: whole naira, not negative, under the safety limit');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x","chance":101}]') <> 'ok', 'chance is 0 to 100');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x","ignore":true,"cost":500}]') <> 'ok' and pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x","ignore":true}]') = 'ok', 'an Ignore choice must be free');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x","next_moment":"loan_repaid","next_delay_hours":5,"next_chance":50}]') = 'ok' and pg_temp.try_moment('[{"id":"a","label":"1","outcome":"x","next_moment":"Bad Id"}]') <> 'ok', 'next_moment');
  perform pg_temp.assert(pg_temp.try_moment('[]') <> 'ok' and pg_temp.try_moment('[]', '{}', false) = 'ok', 'a moment that is on needs a choice; a draft may be empty');
  perform pg_temp.assert(pg_temp.try_moment('{"a":1}') <> 'ok', 'choices must be a list');
  -- conditions
  foreach r in array array['{"min_days":1}', '{"max_days":30}', '{"has_child":["baby","nursery"]}', '{"has_child":["any"]}', '{"at":["oba_market"]}', '{"need_below":{"fun":40}}', '{"need_above":{"health":50}}',
                           '{"hours":[18,23]}', '{"hours":[22,5]}', '{"min_cash":1000,"max_cash":100000}', '{"has_item":["pure_water"]}'] loop
    perform pg_temp.assert(pg_temp.try_moment(v_good, r) = 'ok', 'allowed condition: ' || r);
  end loop;
  foreach r in array array['{"sql":"1=1"}', '{"min_days":-1}', '{"at":["no_such_place"]}', '{"need_below":{"cash":40}}', '{"need_below":{"fun":400}}', '{"hours":[1]}', '{"hours":[1,99]}', '{"has_item":["nope"]}', '{"has_child":"baby"}', '{"min_cash":"x"}'] loop
    perform pg_temp.assert(pg_temp.try_moment(v_good, r) <> 'ok', 'refused condition: ' || r);
  end loop;
  -- words
  insert into chat_banned_words (word, active) values ('zorbo', true) on conflict do nothing; update chat_banned_words set active = true where word = 'zorbo';
  perform pg_temp.assert(pg_temp.try_moment(v_good, '{}', true, 'A zorbo story') <> 'ok', 'banned words are refused in the title');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"Zorbo","outcome":"Fine."}]') <> 'ok', 'and in a label');
  perform pg_temp.assert(pg_temp.try_moment('[{"id":"a","label":"Fine","outcome":"zorbo"}]') <> 'ok', 'and in an outcome');
  perform pg_temp.assert(pg_temp.hint_of($q$insert into life_moments (id, title, body, kind) values ('BAD ID', 'Title', 'Some body text.', 'random')$q$) <> 'ok', 'a bad id is refused');
  perform pg_temp.assert(pg_temp.hint_of($q$insert into life_moments (id, title, body, kind, choices) values ('badkind', 'Title', 'Some body text.', 'magic', '[]')$q$) <> 'ok', 'a bad kind is refused');
  -- when it runs, the effects are checked again (even if somebody edited the row with a superuser)
  insert into life_moments (id, title, body, kind, choices, active) values ('t_runtime', 'Runtime check', 'A story for the runtime check.', 'random', '[{"id":"a","label":"Go","outcome":"ok","effects":[{"t":"needs","delta":{"fun":1}}]}]', true);
  alter table life_moments disable trigger life_moments_guard;
  update life_moments set choices = '[{"id":"a","label":"Go","outcome":"ok","effects":[{"t":"sql","code":"drop table profiles"}]}]' where id = 't_runtime';
  alter table life_moments enable trigger life_moments_guard;
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', pg_temp.give('a', 't_runtime'), 'a')) = 'bad_value', 'a bad effect that slipped into the table is still refused when the card is answered');
  delete from life_moments where id like 't\_%';
  raise notice 'ok 2: closed list of effects and conditions';
end $$;

create or replace function pg_temp.to_hour(p_h numeric) returns void
language plpgsql as $$
declare v_l timestamp := bl_now() at time zone bl_clock_tz(); v_t timestamp := date_trunc('day', bl_now() at time zone bl_clock_tz()) + make_interval(secs => (p_h * 3600)::double precision);
begin
  if v_t <= v_l then v_t := v_t + interval '1 day'; end if;
  perform pg_temp.advance(extract(epoch from (v_t - v_l)));
end $$;

-- ---------- 3. the lazy roll ----------
do $$
declare
  v jsonb; v_id bigint; st player_moment_state; n int; v_t timestamptz; v_a text; v_ids bigint[]; v_day timestamptz := bl_moment_day_start(bl_now()); i int; v_first text; v_tz text := bl_clock_tz();
begin
  perform pg_temp.cfg('moments.max_shown', '5');
  perform pg_temp.login_as('a');
  -- first look: only a state row, no card, a roll in 5 minutes
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 0 and (v->>'enabled')::boolean and (v->>'poll_seconds')::int = 90, 'the first look creates no card: ' || v::text);
  select * into st from player_moment_state where user_id = pg_temp.u('a');
  perform pg_temp.assert(st.next_roll_at = bl_now() + interval '5 minutes', 'first roll in 5 minutes');
  perform pg_temp.hours(0.05);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0, 'not yet at 3 minutes');
  -- the roll: random pinned to 0 = the first eligible (by sort), then the gap is the shortest (45 minutes)
  perform set_config('bl.test_rand', '0', true);
  perform pg_temp.hours(0.05);
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 1 and v->'moments'->0->>'moment' = 'landlord_levy', 'a card after the wait: ' || (v->'moments')::text);
  select * into st from player_moment_state where user_id = pg_temp.u('a');
  perform pg_temp.assert(st.next_roll_at = bl_now() + interval '45 minutes', 'the next one waits 45 minutes (rand 0)');
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 1, 'the same card again on the next poll, no new one');
  perform pg_temp.assert((select count(*) from player_moments where user_id = pg_temp.u('a')) = 1, 'one row');
  -- the cooldown: the same moment does not come back while its cooldown runs; the next eligible does
  perform pg_temp.hours(0.76);
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 2 and v->'moments'->1->>'moment' = 'friend_loan', 'landlord_levy is on cooldown, so friend_loan: ' || (select string_agg(x->>'moment', ',') from jsonb_array_elements(v->'moments') x));
  -- gap with random 0.999: 180 minutes
  perform set_config('bl.test_rand', '0.9999', true);
  perform pg_temp.hours(0.76);
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 3 and v->'moments'->2->>'moment' = 'church_harvest', 'random 0.9999 picks the last eligible one (the market card needs a market, NEPA needs the evening): ' || (select string_agg(x->>'moment', ',') from jsonb_array_elements(v->'moments') x));
  select * into st from player_moment_state where user_id = pg_temp.u('a');
  perform pg_temp.assert(st.next_roll_at between bl_now() + interval '179 minutes' and bl_now() + interval '181 minutes', 'the longest wait is 180 minutes: ' || (st.next_roll_at - bl_now())::text);
  -- the daily cap (3 a day, kids cards count): 3 so far today. Another at the end of the gap: no.
  perform pg_temp.hours(3.01);
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 3 and (select count(*) from player_moments where user_id = pg_temp.u('a')) = 3, 'capped at 3 a day');
  select * into st from player_moment_state where user_id = pg_temp.u('a');
  perform pg_temp.assert(st.next_roll_at = bl_moment_day_start(bl_now()) + interval '1 day' + interval '5 minutes', 'the next roll waits for tomorrow: ' || (st.next_roll_at at time zone v_tz)::text);
  -- next Benin day: a new card is possible again
  perform pg_temp.advance(extract(epoch from (st.next_roll_at - bl_now())) + 1);
  perform set_config('bl.test_rand', '0', true);
  update player_moments set status = 'answered' where user_id = pg_temp.u('a');
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 1 and (select count(*) from player_moments where user_id = pg_temp.u('a') and created_at >= bl_moment_day_start(bl_now())) = 1, 'a new day, a new card');
  -- kids cards count toward the cap: two doctor cards + one random = 3, so no more
  perform pg_temp.login_as('b');
  perform pg_temp.cfg('moments.first_gap_minutes', '0');
  perform moments_pending();
  perform pg_temp.give('b', 'doc_cough', '{"child_id":0}'::jsonb); perform pg_temp.give('b', 'doc_fever', '{"child_id":0}'::jsonb);
  perform set_config('bl.test_rand', '0', true);
  perform pg_temp.hours(0.01);
  perform moments_pending();
  perform pg_temp.assert((select count(*) from player_moments m join life_moments l on l.id = m.moment_id where m.user_id = pg_temp.u('b') and l.kind = 'random') = 1, 'one random card was still allowed with 2 kid cards');
  perform pg_temp.hours(3.1);
  perform moments_pending();
  perform pg_temp.assert((select count(*) from player_moments m join life_moments l on l.id = m.moment_id where m.user_id = pg_temp.u('b') and l.kind = 'random') = 1, 'and no second: 2 kid cards + 1 random = the cap of 3');
  perform pg_temp.cfg('moments.first_gap_minutes', '5');
  perform pg_temp.cfg('moments.max_shown', '2');
  raise notice 'ok 3a: first look, gap, cooldown, daily cap';
end $$;

do $$
declare
  v jsonb; st player_moment_state; v_n int; ids bigint[]; v_tz text := bl_clock_tz(); v_id bigint; r text;
begin
  perform pg_temp.cfg('moments.daily_cap', '20');
  perform pg_temp.cfg('moments.max_shown', '5');
  perform pg_temp.cfg('moments.first_gap_minutes', '0');
  perform pg_temp.cfg('moments.gap_min_minutes', '1');
  perform pg_temp.cfg('moments.gap_max_minutes', '1');
  perform set_config('bl.test_rand', '0', true);
  -- one player per condition, each with a clean state
  -- (c) age: the brand-new account ('new', 1 hour old) is not eligible for the moments that want a day
  perform pg_temp.login_as('new');
  perform moments_pending(); perform pg_temp.hours(0.03);
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 0 or v->'moments'->0->>'moment' not in ('landlord_levy', 'friend_loan', 'owambe_invite', 'okada_scare', 'money_on_road', 'stranger_job', 'church_harvest'), 'a one hour old account gets no day-one moments: ' || (v->'moments')::text);
  -- (d) place: market_extra only at a market
  perform pg_temp.login_as('c');
  update life_moments set weight = 0 where kind = 'random' and id <> 'market_extra';
  perform moments_pending(); perform pg_temp.hours(0.03);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0, 'only market_extra is on, and c is not at a market');
  perform pg_temp.at(pg_temp.u('c'), 'oba_market');
  perform pg_temp.hours(0.05);
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 1 and v->'moments'->0->>'moment' = 'market_extra', 'at Oba Market, Mama Eki''s gift can come: ' || (v->'moments')::text);
  perform pg_temp.assert(v->'moments'->0->>'speaker' = 'Mama Eki · market woman' and v->'moments'->0->>'icon' = '🍅', 'speaker and icon');
  -- (e) hours: NEPA only in the evening (16:00-24:00)
  update life_moments set weight = 0 where kind = 'random'; update life_moments set weight = 1 where id = 'nepa_light';
  perform pg_temp.login_as('d');
  perform pg_temp.to_hour(10);
  perform moments_pending(); perform pg_temp.hours(0.03);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0, 'NEPA does not take light at 10:00');
  perform pg_temp.to_hour(17);
  perform pg_temp.hours(0.05);
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 1 and v->'moments'->0->>'moment' = 'nepa_light', 'at 17:00 it can: ' || (v->'moments')::text);
  -- (f) cash, needs, items, kids: custom moments with one condition each
  update life_moments set weight = 0 where kind = 'random' and id not like 'c\_%';
  insert into life_moments (id, title, body, kind, conditions, choices, weight, sort, cooldown_days) values
   ('c_rich',   'Rich only',  'Only for the rich.',  'random', '{"min_cash": 5000000}', '[{"id":"a","label":"ok","outcome":"ok"}]', 1, 1, 0),
   ('c_poor',   'Poor only',  'Only for the poor.',  'random', '{"max_cash": 100}',     '[{"id":"a","label":"ok","outcome":"ok"}]', 1, 2, 0),
   ('c_bored',  'Bored only', 'Only when bored.',    'random', '{"need_below": {"fun": 20}}', '[{"id":"a","label":"ok","outcome":"ok"}]', 1, 3, 0),
   ('c_water',  'Water only', 'Only with water.',    'random', '{"has_item": ["pure_water"]}', '[{"id":"a","label":"ok","outcome":"ok"}]', 1, 4, 0),
   ('c_parent', 'Parents',    'Only for a parent of a nursery or primary child.', 'random', '{"has_child": ["nursery","primary"]}', '[{"id":"a","label":"ok","outcome":"ok"}]', 1, 5, 0);
  perform pg_temp.login_as('a');
  update player_moments set status = 'answered' where user_id = pg_temp.u('a');
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('a');
  update profiles set cash = 1000000, bank = 0, fun = 100 where id = pg_temp.u('a');
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0, 'nothing matches a: not rich, not poor, not bored, no water, no child');
  update profiles set cash = 6000000 where id = pg_temp.u('a');
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('a');
  v := moments_pending();
  perform pg_temp.assert(v->'moments'->0->>'moment' = 'c_rich', 'min_cash');
  update player_moments set status = 'answered' where user_id = pg_temp.u('a');
  update profiles set cash = 50, bank = 0 where id = pg_temp.u('a');
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('a');
  v := moments_pending();
  perform pg_temp.assert(v->'moments'->0->>'moment' = 'c_poor', 'max_cash');
  update player_moments set status = 'answered' where user_id = pg_temp.u('a');
  update profiles set cash = 1000000, fun = 5, needs_updated_at = bl_now() where id = pg_temp.u('a');
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('a');
  v := moments_pending();
  perform pg_temp.assert(v->'moments'->0->>'moment' = 'c_bored', 'need_below: fun under 20');
  update player_moments set status = 'answered' where user_id = pg_temp.u('a');
  update profiles set fun = 100, needs_updated_at = bl_now() where id = pg_temp.u('a');
  insert into inventory (user_id, item_id, qty) values (pg_temp.u('a'), 'pure_water', 1) on conflict (user_id, item_id) do update set qty = 1;
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('a');
  v := moments_pending();
  perform pg_temp.assert(v->'moments'->0->>'moment' = 'c_water', 'has_item');
  update player_moments set status = 'answered' where user_id = pg_temp.u('a');
  delete from inventory where user_id = pg_temp.u('a') and item_id = 'pure_water';
  insert into kids_children (rel_id, parent_a, parent_b, status, name, gender, conceived_at, due_at, born_at, hunger_at, sleep_at, fun_at, health_at, love_at, clean_at, last_care_at, score_at)
  values (null, pg_temp.u('a'), null, 'home', 'Ada', 'girl', bl_now() - interval '10 days', bl_now() - interval '7 days', bl_now() - interval '6 days', bl_now(), bl_now(), bl_now(), bl_now(), bl_now(), bl_now(), bl_now(), bl_now());
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('a');
  v := moments_pending();
  perform pg_temp.assert(v->'moments'->0->>'moment' = 'c_parent', 'has_child: a Nursery child at home (day 6)');
  update player_moments set status = 'answered' where user_id = pg_temp.u('a');
  update kids_children set born_at = bl_now() - interval '1 day' where parent_a = pg_temp.u('a');
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('a');
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0, 'a newborn is not in the list of stages');
  delete from kids_children where parent_a = pg_temp.u('a') and name = 'Ada';
  delete from life_moments where id like 'c\_%';
  update life_moments set weight = 1 where kind = 'random';
  -- busy states: never rolled while busy, travelling, in a cell, in a hospital bed, or in a club (spray and money drops), retried in 10 minutes
  perform pg_temp.login_as('b');
  update player_moments set status = 'answered' where user_id = pg_temp.u('b');
  foreach r in array array['busy', 'travel', 'jail', 'hospital', 'club', 'lounge'] loop
    update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('b');
    perform pg_temp.at(pg_temp.u('b'), 'third_east');
    if r = 'busy' then update profiles set busy_until = bl_now() + interval '1 hour', busy_label = 'x' where id = pg_temp.u('b');
    elsif r = 'travel' then update profiles set travel_to = 'oba_market' where id = pg_temp.u('b');
    elsif r = 'jail' then update profiles set jailed_until = bl_now() + interval '1 hour' where id = pg_temp.u('b');
    elsif r = 'hospital' then update profiles set hospitalized_until = bl_now() + interval '1 hour' where id = pg_temp.u('b');
    elsif r = 'club' then update profiles set location_id = (select id from locations where scene = 'club' limit 1) where id = pg_temp.u('b');
    else update profiles set location_id = (select id from locations where scene = 'lounge' limit 1) where id = pg_temp.u('b');
    end if;
    perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0, 'no card while ' || r);
    perform pg_temp.assert((select next_roll_at from player_moment_state where user_id = pg_temp.u('b')) = bl_now() + interval '10 minutes', 'retry in 10 minutes while ' || r);
  end loop;
  perform pg_temp.at(pg_temp.u('b'), 'third_east');
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('b');
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 1, 'free again: a card');
  -- max shown: a player who has not answered 2 cards gets no third
  perform pg_temp.cfg('moments.max_shown', '2');
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('b');
  perform moments_pending();
  perform pg_temp.hours(0.02);
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('b');
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 2 and (select count(*) from player_moments where user_id = pg_temp.u('b') and status = 'pending') = 2, 'two cards waiting');
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('b');
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 2 and (select count(*) from player_moments where user_id = pg_temp.u('b') and status = 'pending') = 2, 'never more than 2 at once, and no new card is rolled on top');
  -- weights: with a lot of weight on one moment and rand 0.5 it is picked
  update player_moments set status = 'answered' where user_id = pg_temp.u('b');
  update life_moments set weight = 0 where kind = 'random'; update life_moments set weight = 100 where id = 'owambe_invite'; update life_moments set weight = 1 where id = 'church_harvest';
  perform set_config('bl.test_rand', '0.5', true);
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('b');
  update player_moments set created_at = bl_now() - interval '100 days' where user_id = pg_temp.u('b');
  v := moments_pending();
  perform pg_temp.assert(v->'moments'->0->>'moment' = 'owambe_invite', 'weighted: 100 vs 1, rand 0.5 -> owambe: ' || (v->'moments')::text);
  update life_moments set weight = 1 where kind = 'random';
  -- a weight of 0 or an inactive moment never rolls
  update life_moments set active = false where id = 'owambe_invite';
  update player_moments set status = 'answered', created_at = bl_now() - interval '100 days' where user_id = pg_temp.u('b');
  update life_moments set weight = 0 where kind = 'random'; update life_moments set weight = 1 where id in ('owambe_invite', 'church_harvest');
  update player_moment_state set next_roll_at = bl_now() - interval '1 minute' where user_id = pg_temp.u('b');
  v := moments_pending();
  perform pg_temp.assert(v->'moments'->0->>'moment' = 'church_harvest', 'an inactive moment is never rolled');
  update life_moments set active = true where id = 'owambe_invite'; update life_moments set weight = 1 where kind = 'random';
  perform pg_temp.cfg('moments.daily_cap', '3'); perform pg_temp.cfg('moments.max_shown', '2'); perform pg_temp.cfg('moments.first_gap_minutes', '5');
  perform pg_temp.cfg('moments.gap_min_minutes', '45'); perform pg_temp.cfg('moments.gap_max_minutes', '180');
  raise notice 'ok 3b: conditions, busy states, max shown, weights';
end $$;

-- ---------- 4. answering: costs, chances, every effect, follow-ups ----------
do $$
declare
  v jsonb; v_i bigint; b0 bigint; s0 numeric; v_xp int; v_sc int; v_n int; v_fu bigint; st text; v_w int;
begin
  perform pg_temp.cfg('moments.daily_cap', '0');
  perform pg_temp.login_as('a');
  update profiles set cash = 100000, bank = 0, stress = 30, fun = 50, social = 50, energy = 50, hunger = 50, needs_updated_at = bl_now() where id = pg_temp.u('a');
  -- a cost is paid first, up front, and always (ledger life_moment, a sink); the needs effect follows
  v_i := pg_temp.give('a', 'landlord_levy');
  b0 := pg_temp.cash(pg_temp.u('a'));
  v := moments_answer(v_i, 'pay');
  perform pg_temp.assert((v->>'spent')::int = 3000 and pg_temp.cash(pg_temp.u('a')) = b0 - 3000 and pg_temp.ledger_sum(pg_temp.u('a'), 'life_moment') = -3000 and (v->>'success')::boolean and v->>'tone' = 'good', 'Pay the levy: ' || v::text);
  perform pg_temp.assert(pg_temp.need('a', 'stress') <= 25.1 and pg_temp.need('a', 'stress') >= 20, 'stress -5: ' || pg_temp.need('a', 'stress'));
  perform pg_temp.assert((select meta->>'label' from ledger where user_id = pg_temp.u('a') and reason = 'life_moment') = 'Landlord wahala' and (select status from player_moments where id = v_i) = 'answered'
                         and (select answered_choice from player_moments where id = v_i) = 'pay', 'ledger label and status');
  perform pg_temp.assert(v->'effects' @> '["Stress -5"]'::jsonb, 'the effect lines for the toast: ' || (v->'effects')::text);
  -- an answered card is over; somebody else's card is not yours
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_i, 'pay')) = 'already_answered', 'cannot answer twice');
  perform pg_temp.login_as('b');
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', pg_temp.give('a', 'landlord_levy'), 'pay')) = 'no_moment', 'not your card');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', (select max(id) from player_moments where user_id = pg_temp.u('a')), 'xx')) = 'bad_choice', 'unknown choice');
  -- ALL OR NOTHING: not enough money for the cost: nothing is paid and nothing else happens; the card stays
  v_i := pg_temp.give('a', 'landlord_levy');
  update profiles set cash = 2000, bank = 500 where id = pg_temp.u('a');
  s0 := pg_temp.need('a', 'stress');
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_i, 'pay')) = 'not_enough_money', 'cannot afford 3,000 with 2,500');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 2500 and pg_temp.need('a', 'stress') = s0 and (select status from player_moments where id = v_i) = 'pending' and pg_temp.ledger_sum(pg_temp.u('a'), 'life_moment') = -3000, 'nothing changed and the card is still open');
  perform pg_temp.assert((moments_pending()->'moments'->0->'choices'->0->>'affordable')::boolean = false, 'the card says it cannot be afforded');
  -- all or nothing across effects: a later effect that fails undoes the earlier ones and the cost
  insert into life_moments (id, title, body, kind, choices, weight) values ('t_atomic', 'Atomic test', 'A story for the atomic test.', 'random',
    '[{"id":"go","label":"Go","cost":100,"outcome":"done","effects":[{"t":"needs","delta":{"fun":20}},{"t":"item","id":"pure_water","qty":3},{"t":"cash","amount":-900000}]}]', 0);
  v_i := pg_temp.give('a', 't_atomic');
  update profiles set cash = 5000, bank = 0, fun = 10, needs_updated_at = bl_now() where id = pg_temp.u('a');
  delete from inventory where user_id = pg_temp.u('a') and item_id = 'pure_water';
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_i, 'go')) = 'not_enough_money', 'the last effect cannot be paid');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 5000 and pg_temp.need('a', 'fun') <= 10 and not exists (select 1 from inventory where user_id = pg_temp.u('a') and item_id = 'pure_water')
                         and (select status from player_moments where id = v_i) = 'pending', 'everything is undone: money, needs, items, the card is open');
  -- an effect "up_to" takes what there is instead of failing (a loss that must not block the story)
  update life_moments set choices = '[{"id":"go","label":"Go","outcome":"done","effects":[{"t":"cash","amount":-900000,"up_to":true}]}]' where id = 't_atomic';
  v := moments_answer(v_i, 'go');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 0 and (v->'effects')::text like '%Paid ₦5,000%', 'up_to takes everything it can: ' || v::text);
  -- CHANCE: landlord "beg": 50 %. A good roll (0.01) and a bad one (0.99)
  update profiles set cash = 100000, stress = 30, needs_updated_at = bl_now() where id = pg_temp.u('a');
  v_i := pg_temp.give('a', 'landlord_levy'); b0 := pg_temp.cash(pg_temp.u('a'));
  perform set_config('bl.test_rand', '0.01', true);
  v := moments_answer(v_i, 'beg');
  perform pg_temp.assert((v->>'success')::boolean and v->>'tone' = 'good' and pg_temp.cash(pg_temp.u('a')) = b0 - 1500 and v->>'outcome' like 'Your sweet mouth works!%', 'the begging worked: ' || v::text);
  v_i := pg_temp.give('a', 'landlord_levy'); b0 := pg_temp.cash(pg_temp.u('a'));
  perform set_config('bl.test_rand', '0.99', true);
  v := moments_answer(v_i, 'beg');
  perform pg_temp.assert(not (v->>'success')::boolean and v->>'tone' = 'bad' and pg_temp.cash(pg_temp.u('a')) = b0 - 4500 and v->>'outcome' like 'He no gree at all.%' and pg_temp.need('a', 'stress') >= 30, 'the begging failed: ' || v::text);
  v_i := pg_temp.give('a', 'landlord_levy'); update profiles set cash = 100, bank = 0 where id = pg_temp.u('a');
  v := moments_answer(v_i, 'beg');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 0, 'a loss "up to" what the player has: 100 gone, no error');
  perform set_config('bl.test_rand', '', true);
  -- GAINS: money on the road, never counted as earnings
  update profiles set cash = 1000, bank = 0, street_cred = 10, social = 50 where id = pg_temp.u('a');
  v_i := pg_temp.give('a', 'money_on_road');
  v := moments_answer(v_i, 'keep');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = 6000 and exists (select 1 from ledger where user_id = pg_temp.u('a') and reason = 'life_moment' and delta = 5000) and v->'effects' @> '["Got ₦5,000"]'::jsonb, 'found ₦5,000: ' || v::text);
  perform pg_temp.assert('life_moment' <> all (bl_earn_reasons()), 'and it is not earnings');
  v_i := pg_temp.give('a', 'money_on_road');
  v := moments_answer(v_i, 'police');
  perform pg_temp.assert((select street_cred from profiles where id = pg_temp.u('a')) = 12 and pg_temp.cash(pg_temp.u('a')) = 6000, 'the police: street cred +2, no money');
  v_i := pg_temp.give('a', 'stranger_job');
  v := moments_answer(v_i, 'decline');
  perform pg_temp.assert((select street_cred from profiles where id = pg_temp.u('a')) = 13, 'declining the scam is the right choice: +1 street cred');
  v_i := pg_temp.give('a', 'stranger_job'); b0 := pg_temp.cash(pg_temp.u('a'));
  v := moments_answer(v_i, 'pay');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = b0 - 3000, 'paying the "registration" costs 3,000');
  -- SKILL XP, items, named placeholders
  v_xp := bl_skill_xp(pg_temp.u('a'), 'charisma');
  v_i := pg_temp.give('a', 'owambe_invite'); update profiles set cash = 100000, fun = 20, needs_updated_at = bl_now() where id = pg_temp.u('a');
  v := moments_answer(v_i, 'go');
  perform pg_temp.assert(bl_skill_xp(pg_temp.u('a'), 'charisma') = v_xp + 5 and pg_temp.need('a', 'fun') >= 40, 'the owambe: +5 Charisma XP, fun +25: ' || v::text);
  insert into life_moments (id, title, body, kind, choices, weight) values ('t_items', 'Items test', 'A story about {name} and items.', 'random',
    '[{"id":"get","label":"Take","outcome":"Hello {name}, you got water.","effects":[{"t":"item","id":"pure_water","qty":2}]},{"id":"use","label":"Use","outcome":"Used one.","effects":[{"t":"item","id":"pure_water","qty":-1}]},{"id":"use5","label":"Use five","outcome":"x","effects":[{"t":"item","id":"pure_water","qty":-5}]}]', 0);
  delete from inventory where user_id = pg_temp.u('a') and item_id = 'pure_water';
  v := moments_answer(pg_temp.give('a', 't_items'), 'get');
  perform pg_temp.assert((select qty from inventory where user_id = pg_temp.u('a') and item_id = 'pure_water') = 2 and v->>'outcome' = 'Hello LM_a, you got water.', 'items granted, {name} filled in: ' || v::text);
  v := moments_answer(pg_temp.give('a', 't_items'), 'use');
  perform pg_temp.assert((select qty from inventory where user_id = pg_temp.u('a') and item_id = 'pure_water') = 1 and v->'effects' @> '["Used 1 x Pure water sachet"]'::jsonb, 'an item used: ' || v::text);
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', pg_temp.give('a', 't_items'), 'use5')) <> 'ok' and (select qty from inventory where user_id = pg_temp.u('a') and item_id = 'pure_water') = 1, 'cannot use more than you have: nothing changes');
  v_n := pg_temp.give('a', 't_items')::int;
  perform moments_answer(v_n, 'get');
  perform pg_temp.assert((select qty from inventory where user_id = pg_temp.u('a') and item_id = 'pure_water') = 3, 'granted on top');
  -- FOLLOW-UP: lending money, 35 % that Efe pays back a day later with a little extra
  update profiles set cash = 100000, bank = 0 where id = pg_temp.u('a');
  v_i := pg_temp.give('a', 'friend_loan'); b0 := pg_temp.cash(pg_temp.u('a'));
  perform set_config('bl.test_rand', '0.99', true);
  v := moments_answer(v_i, 'lend');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = b0 - 5000 and not exists (select 1 from player_moments where user_id = pg_temp.u('a') and moment_id = 'loan_repaid'), 'lent ₦5,000, an unlucky roll: no follow-up');
  v_i := pg_temp.give('a', 'friend_loan'); b0 := pg_temp.cash(pg_temp.u('a'));
  perform set_config('bl.test_rand', '0.01', true);
  v := moments_answer(v_i, 'lend');
  select id into v_fu from player_moments where user_id = pg_temp.u('a') and moment_id = 'loan_repaid' and status = 'scheduled';
  perform pg_temp.assert(v_fu is not null and (select show_at from player_moments where id = v_fu) = bl_now() + interval '24 hours' and not (select counts from player_moments where id = v_fu), 'a lucky roll: Efe comes back in 24 hours, and the card does not count toward the cap');
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_fu, 'take')) = 'not_yet', 'not yet');
  perform set_config('bl.test_rand', '', true);
  update player_moments set status = 'answered' where user_id = pg_temp.u('a') and status in ('pending', 'snoozed');
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0, 'not shown yet');
  perform pg_temp.hours(24.01);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 1 and moments_pending()->'moments'->0->>'moment' = 'loan_repaid', 'shown after a day');
  b0 := pg_temp.cash(pg_temp.u('a'));
  v := moments_answer(v_fu, 'take');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('a')) = b0 + 5500 and v->'effects' @> '["Got ₦5,500"]'::jsonb, 'repaid with a little extra: ' || v::text);
  -- the choice-level next_moment (a second way to chain)
  update life_moments set choices = '[{"id":"go","label":"Go","outcome":"ok","next_moment":"loan_repaid","next_delay_hours":5,"next_chance":100}]' where id = 't_items';
  v := moments_answer(pg_temp.give('a', 't_items'), 'go');
  perform pg_temp.assert(exists (select 1 from player_moments where user_id = pg_temp.u('a') and moment_id = 'loan_repaid' and status = 'scheduled' and show_at > bl_now() + interval '4 hours'), 'next_moment schedules a follow-up');
  -- street cred floors at 0, a needs effect is clamped 0-100
  update profiles set street_cred = 0 where id = pg_temp.u('a');
  update life_moments set choices = '[{"id":"go","label":"Go","outcome":"ok","effects":[{"t":"street_cred","delta":-20},{"t":"needs","delta":{"fun":50}}]}]' where id = 't_items';
  v := moments_answer(pg_temp.give('a', 't_items'), 'go');
  perform pg_temp.assert((select street_cred from profiles where id = pg_temp.u('a')) = 0 and (select fun from profiles where id = pg_temp.u('a')) <= 100, 'street cred never negative, needs never above 100');
  delete from life_moments where id like 't\_%';
  raise notice 'ok 4: answering, costs, chances, effects, follow-ups';
end $$;

-- ---------- 5. snooze, expiry, Ignore ----------
do $$
declare v jsonb; v_i bigint; s0 numeric; i int; v_h bigint;
begin
  perform pg_temp.cfg('moments.daily_cap', '0');
  perform pg_temp.login_as('a');
  update profiles set cash = 100000, bank = 0, stress = 10, needs_updated_at = bl_now() where id = pg_temp.u('a');
  update player_moments set status = 'answered' where user_id = pg_temp.u('a') and status in ('pending', 'snoozed', 'scheduled');
  v_i := pg_temp.give('a', 'landlord_levy');
  v := moments_snooze(v_i);
  perform pg_temp.assert(not (v->>'expired')::boolean and (v->>'snoozes_left')::int = 2 and (select status from player_moments where id = v_i) = 'snoozed' and (select show_at from player_moments where id = v_i) = bl_now() + interval '2 hours', 'Remind me later: 2 hours: ' || v::text);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0, 'hidden for 2 hours');
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_i, 'pay')) = 'not_yet' and pg_temp.hint_of(format('select moments_snooze(%s)', v_i)) = 'not_yet', 'cannot act on a hidden card');
  perform pg_temp.hours(1.99);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0, 'still hidden at 1h59');
  perform pg_temp.hours(0.02);
  v := moments_pending();
  perform pg_temp.assert(jsonb_array_length(v->'moments') = 1 and (v->'moments'->0->>'snoozes_left')::int = 2, 'back after 2 hours with 2 snoozes left');
  v := moments_snooze(v_i); perform pg_temp.hours(2.01);
  v := moments_snooze(v_i); perform pg_temp.hours(2.01);
  perform pg_temp.assert((v->>'snoozes_left')::int = 0 and (select snoozes from player_moments where id = v_i) = 3, 'three snoozes used');
  perform pg_temp.assert((moments_pending()->'moments'->0->>'snoozes_left')::int = 0, 'the card says 0 left');
  s0 := pg_temp.need('a', 'stress');
  v := moments_snooze(v_i);
  perform pg_temp.assert((v->>'expired')::boolean and (select status from player_moments where id = v_i) = 'expired' and (select answered_choice from player_moments where id = v_i) = 'later', 'the 4th one is Ignore: expired as the Ignore choice: ' || v::text);
  perform pg_temp.assert(pg_temp.need('a', 'stress') >= s0 + 5 and v->>'outcome' like 'He frowns.%', 'the Ignore effect was applied (stress +6): ' || pg_temp.need('a', 'stress') || ' vs ' || s0);
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_answer(%s, %L)', v_i, 'pay')) = 'already_answered', 'over');
  -- expiry by time: 36 hours without an answer = Ignore
  v_i := pg_temp.give('a', 'nepa_light');
  s0 := pg_temp.need('a', 'stress');
  perform pg_temp.hours(35);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 1, 'still open at 35 hours');
  perform pg_temp.hours(1.5);
  v := moments_pending();
  perform pg_temp.assert((select status from player_moments where id = v_i) = 'expired' and (select answered_choice from player_moments where id = v_i) = 'dark' and jsonb_array_length(v->'moments') = 0, 'a card nobody answered for 36 hours expires as Ignore (sit in the dark)');
  -- a card with no Ignore choice just expires; scheduled follow-ups expire from the day they were due
  insert into life_moments (id, title, body, kind, choices, weight) values ('t_noign', 'No ignore', 'A story with no ignore.', 'random', '[{"id":"go","label":"Go","outcome":"ok"}]', 0);
  v_i := pg_temp.give('a', 't_noign');
  perform pg_temp.hours(37);
  perform moments_pending();
  perform pg_temp.assert((select status from player_moments where id = v_i) = 'expired' and (select outcome from player_moments where id = v_i) is null, 'no Ignore choice: it simply expires');
  v_h := pg_temp.give('a', 't_noign', '{}'::jsonb, bl_now() + interval '48 hours');
  perform pg_temp.hours(50);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 1, 'a follow-up that became due 2 hours ago is still open');
  -- moments_open brings a snoozed card back at once
  v := moments_snooze(v_h);
  perform pg_temp.assert(jsonb_array_length(moments_pending()->'moments') = 0 and (moments_open(v_h)->>'id')::bigint = v_h and jsonb_array_length(moments_pending()->'moments') = 1, 'moments_open');
  perform pg_temp.login_as('b');
  perform pg_temp.assert(pg_temp.hint_of(format('select moments_open(%s)', v_h)) = 'no_moment' and pg_temp.hint_of(format('select moments_snooze(%s)', v_h)) = 'no_moment' and pg_temp.hint_of(format('select moments_seen(%s)', v_h)) = 'ok', 'only my own cards');
  delete from life_moments where id like 't\_%';
  raise notice 'ok 5: snooze, expiry, ignore';
end $$;

-- ---------- 6. switch, editors, no client access, index ----------
do $$
declare v jsonb; v_i bigint; r jsonb; v_plan text; rec record; t text; ok boolean;
begin
  perform pg_temp.login_as('a');
  perform pg_temp.cfg('moments.enabled', 'false');
  v := moments_pending();
  perform pg_temp.assert(not (v->>'enabled')::boolean and jsonb_array_length(v->'moments') = 0, 'off: no cards');
  perform pg_temp.cfg('moments.enabled', 'true');
  -- an admin writes a moment in Content -> Life moments
  perform pg_temp.login_as('adm');
  r := admin_row_upsert('life_moments', '{"id":"admin_made","title":"Admin made","body":"A story written in Admin for {name}.","icon":"🎁","speaker":"Somebody","kind":"random","weight":2,"cooldown_days":3,
     "conditions":{"min_days":2},"choices":[{"id":"yes","label":"Yes","outcome":"Nice, {name}.","effects":[{"t":"needs","delta":{"fun":5}}]},{"id":"no","label":"No","ignore":true,"outcome":"Fine."}]}');
  perform pg_temp.assert(r->>'message' = 'Added.' and exists (select 1 from life_moments where id = 'admin_made' and jsonb_array_length(choices) = 2), 'an admin adds a moment: ' || r::text);
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('life_moments', '{"id":"admin_bad","title":"Bad","body":"Bad effect here.","icon":"X","speaker":"","kind":"random","weight":1,"cooldown_days":1,"conditions":{},"choices":[{"id":"a","label":"A","outcome":"x","effects":[{"t":"sql"}]}]}')$q$) <> 'ok', 'an admin cannot save a bad effect');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('life_moments', '{"id":"admin_bad2","title":"Bad","body":"Bad choices here.","icon":"X","speaker":"","kind":"random","weight":1,"cooldown_days":1,"conditions":{},"choices":{"a":1}}')$q$) <> 'ok', 'choices must be a list');
  perform admin_row_upsert('life_moments', '{"id":"landlord_levy","weight":3}');
  perform pg_temp.assert((select weight from life_moments where id = 'landlord_levy') = 3, 'an admin tunes a weight');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('life_moments', '{"id":"landlord_levy","title":"x"}')$q$) <> 'ok', 'a too short title is refused by the table');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('life_moments', '{"id":"landlord_levy","weight":3}')$q$) = 'not_admin', 'players cannot edit moments');
  -- no client access to the tables
  perform pg_temp.login_as('a');
  set local role authenticated;
  foreach t in array array['life_moments', 'player_moments', 'player_moment_state'] loop
    begin execute format('select * from public.%I limit 1', t); ok := false; exception when insufficient_privilege then ok := true; end;
    reset role; perform pg_temp.assert(ok, 'clients cannot read ' || t); set local role authenticated;
    begin execute format('delete from public.%I', t); ok := false; exception when insufficient_privilege then ok := true; end;
    reset role; perform pg_temp.assert(ok, 'clients cannot write ' || t); set local role authenticated;
  end loop;
  reset role;
  -- the due lookup is indexed (one player, a handful of rows)
  perform pg_temp.assert(exists (select 1 from pg_indexes where indexname = 'player_moments_due' and indexdef like '%show_at%') and exists (select 1 from pg_indexes where indexname = 'player_moments_user_day')
                         and exists (select 1 from pg_indexes where indexname = 'player_moment_state_pkey'), 'indexes exist');
  set local enable_seqscan = off;
  for rec in execute 'explain select id from player_moments where user_id = ''' || pg_temp.u('a') || ''' and status in (''pending'', ''snoozed'', ''scheduled'') and show_at <= now() order by show_at' loop
    v_plan := coalesce(v_plan, '') || rec."QUERY PLAN" || E'\n';
  end loop;
  reset enable_seqscan;
  perform pg_temp.assert(v_plan ~ 'Index.*player_moments_', 'the due lookup uses an index, not a scan: ' || v_plan);
  raise notice 'ok 6: switch, editors, access, index';
end $$;
