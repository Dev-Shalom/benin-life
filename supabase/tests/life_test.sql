-- S2 "New life" (20261006001100_life_restart.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/life_test.sql
-- Groups: config + privileges, restart archives + cleans dependents + keeps chat/audit links,
-- creator required afterwards (new origin roll, force_next consumed, admin + mute carried),
-- switch off / cooldown, nobody can restart someone else (no args, RLS on the archive, anon, banned),
-- bank_transfer new-account wait in hours.

create or replace function pg_temp.lf_hint(p_sql text, p_hint text) returns text
language plpgsql as $$
declare v_h text; v_m text;
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
    get stacked diagnostics v_h = pg_exception_hint, v_m = message_text;
    if v_h is distinct from p_hint then
      raise exception 'TEST FAILED: [%] expected hint "%", got "%" (%)', p_sql, p_hint, v_h, sqlerrm;
    end if;
    return v_m;
  end;
  raise exception 'TEST FAILED: [%] expected hint "%" but it succeeded', p_sql, p_hint;
end $$;

create temp table t_lf (name text primary key, id uuid not null) on commit drop;
grant select on t_lf to authenticated;
create or replace function pg_temp.lf(p_name text) returns uuid
language sql as $$ select id from t_lf where name = p_name $$;

-- new user with a v2 profile of the given origin, moved into p_home
create or replace function pg_temp.lf_make(p_name text, p_origin text, p_home text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@life.bl');
begin
  insert into t_lf values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = to_jsonb(p_origin) where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home(p_home);
  update profiles set rent_owed = 0 where id = v;
  return v;
end $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
end $$;

-- ---------- 1. config + privileges ----------
do $$
begin
  perform pg_temp.assert(bl_cfg_bool('life.restart_enabled'), 'life.restart_enabled defaults to true');
  perform pg_temp.assert(bl_cfg('life.restart_cooldown_hours') = 0, 'cooldown defaults to 0');
  perform pg_temp.assert(bl_cfg_bool('life.welcome_enabled'), 'welcome screen on by default');
  perform pg_temp.assert(bl_cfg('life.welcome_after_minutes') = 30, 'welcome after 30 real minutes');
  perform pg_temp.assert((select category from game_config where key = 'life.restart_enabled') = 'life', 'category life');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.life_restart()', 'execute'), 'authenticated may restart');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.life_restart()', 'execute'), 'anon may not restart');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_profiles_carry_life()', 'execute'), 'helper revoked');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.profile_archive', 'insert'), 'no client writes to the archive');
  perform pg_temp.assert((select relrowsecurity from pg_class where oid = 'public.profile_archive'::regclass), 'archive has RLS');
  perform pg_temp.assert(exists (select 1 from pg_constraint where conrelid = 'public.chat_blocks'::regclass and contype = 'f'
                                 and confrelid = 'auth.users'::regclass), 'chat blocks point at the auth account');
  perform pg_temp.assert(not exists (select 1 from pg_constraint where contype = 'f' and confrelid = 'public.profiles'::regclass
                                     and conrelid in ('public.chat_messages'::regclass, 'public.chat_reports'::regclass,
                                                      'public.chat_blocks'::regclass, 'public.admin_audit'::regclass,
                                                      'public.config_audit'::regclass)), 'no chat/audit FK left on profiles');
  raise notice 'ok 1: config + privileges';
end $$;

-- ---------- 2. restart: archive + dependents ----------
do $$
declare
  a uuid := pg_temp.lf_make('Life_Ada', 'nepo', 'gra_duplex');
  b uuid := pg_temp.lf_make('Life_Bisi', 'lapo', 'ekenwan_face_me');
  r jsonb;
  arc profile_archive;
  v_msg bigint;
  v_cash bigint;
  v_bank bigint;
begin
  -- give Ada some life to lose
  perform pg_temp.login(a);
  perform bl_add_money(a, 'cash', 1234, 'test');
  insert into inventory (user_id, item_id, qty) select a, id, 2 from items order by id limit 1
    on conflict (user_id, item_id) do update set qty = 2;
  insert into chat_messages (location_id, user_id, username, body) values ('gra_duplex', a, 'Life_Ada', 'hello GRA')
    returning id into v_msg;
  insert into chat_blocks (blocker_id, blocked_id) values (b, a);
  insert into admin_audit (admin_id, action, target_user, data) values (b, 'mute', a, '{"minutes":15}');
  update profiles set is_admin = true, chat_muted_until = bl_now() + interval '2 hours' where id = a;
  select cash, bank into v_cash, v_bank from profiles where id = a;
  perform pg_temp.assert(exists (select 1 from player_furniture where user_id = a), 'Ada has furniture');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a), 'Ada has a ledger');
  perform pg_temp.assert(exists (select 1 from events where user_id = a), 'Ada has events');

  r := life_restart();
  perform pg_temp.assert(r->>'message' ilike '%archived%', 'restart message: ' || r::text);
  perform pg_temp.assert((r->>'life_no')::int = 2, 'next life is number 2');

  -- profile gone, account kept
  perform pg_temp.assert(not exists (select 1 from profiles where id = a), 'profile deleted');
  perform pg_temp.assert(exists (select 1 from auth.users where id = a), 'auth account kept');
  -- archive row
  select * into arc from profile_archive where user_id = a;
  perform pg_temp.assert(arc.id is not null and arc.id = (r->>'archive_id')::bigint, 'archive row written');
  perform pg_temp.assert(arc.username = 'Life_Ada' and arc.origin = 'nepo' and arc.life_no = 1, 'archive header');
  perform pg_temp.assert(arc.cash = v_cash and arc.bank = v_bank, 'archive keeps the balances');
  perform pg_temp.assert((arc.profile->>'is_admin')::boolean, 'archive keeps the whole profile row');
  perform pg_temp.assert(jsonb_array_length(arc.extra->'inventory') >= 1, 'archive keeps the Bag');
  perform pg_temp.assert(jsonb_array_length(arc.extra->'furniture') >= 1, 'archive keeps the furniture');
  perform pg_temp.assert((arc.extra->>'ledger_count')::int >= 1 and jsonb_array_length(arc.extra->'ledger_recent') >= 1, 'archive keeps money history');
  -- gameplay dependents cleaned
  perform pg_temp.assert(not exists (select 1 from inventory where user_id = a), 'inventory cleaned');
  perform pg_temp.assert(not exists (select 1 from player_furniture where user_id = a), 'furniture cleaned');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = a), 'ledger cleaned');
  perform pg_temp.assert(not exists (select 1 from events where user_id = a), 'events cleaned');
  -- moderation + audit links kept
  perform pg_temp.assert(exists (select 1 from chat_messages where id = v_msg and user_id = a), 'chat message kept');
  perform pg_temp.assert(exists (select 1 from chat_blocks where blocker_id = b and blocked_id = a), 'block against Ada kept');
  perform pg_temp.assert(exists (select 1 from admin_audit where target_user = a and action = 'mute'), 'admin history kept');
  perform pg_temp.assert(exists (select 1 from admin_audit where target_user = a and action = 'life_restart'
                                  and (data->>'archive_id')::bigint = arc.id), 'restart audited');
  -- the other player is untouched
  perform pg_temp.assert(exists (select 1 from profiles where id = b), 'Bisi untouched');
  perform pg_temp.assert(exists (select 1 from player_furniture where user_id = b), 'Bisi keeps her furniture');
  raise notice 'ok 2: restart archives and cleans';
end $$;

-- ---------- 3. creator required afterwards ----------
do $$
declare
  a uuid := pg_temp.lf('Life_Ada');
  st jsonb;
begin
  perform pg_temp.login(a);
  perform pg_temp.lf_hint($q$ select get_my_state() $q$, 'no_profile');
  perform pg_temp.lf_hint($q$ select choose_start_home('ekenwan_face_me') $q$, 'no_profile');
  perform pg_temp.lf_hint($q$ select do_activity('use_toilet') $q$, 'no_profile');
  perform pg_temp.lf_hint($q$ select life_restart() $q$, 'no_profile');
  -- the one-shot origin override applies to the new Sim and is consumed
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  st := create_profile_v2('Life_Ada', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform pg_temp.assert(st->'profile'->>'origin' = 'lapo', 'new origin roll: ' || coalesce(st->'profile'->>'origin', 'null'));
  perform pg_temp.assert((select value from game_config where key = 'origin.force_next') = '""'::jsonb, 'force_next consumed');
  perform pg_temp.assert(st->'creator'->>'home_chosen' = 'false', 'home still to choose');
  perform pg_temp.lf_hint($q$ select do_activity('use_toilet') $q$, 'no_home');
  -- carried over: admin rights and the running chat mute; fresh: money, Bag, furniture
  perform pg_temp.assert((select is_admin from profiles where id = a), 'admin rights carried over');
  perform pg_temp.assert((select chat_muted_until > bl_now() + interval '1 hour' from profiles where id = a), 'chat mute carried over');
  perform pg_temp.assert((select cash + bank from profiles where id = a) = 0, 'no money before the home');
  perform choose_start_home('ekenwan_face_me');
  perform pg_temp.assert((select home_chosen from profiles where id = a), 'home chosen');
  perform pg_temp.assert((select count(*) from player_furniture where user_id = a) >= 1, 'fresh starter furniture');
  perform pg_temp.assert(not exists (select 1 from player_furniture where user_id = a and furniture_id = 'tv'), 'LAPO set, not the old Nepo set');
  perform pg_temp.assert(not exists (select 1 from inventory i where i.user_id = a and i.qty = 2), 'old Bag not back');
  -- origin.nepo_pct roll path (no override): roll under 10 % = Nepo
  raise notice 'ok 3: creator again';
end $$;

do $$
declare
  c uuid := pg_temp.lf_make('Life_Chidi', 'lapo', 'ekenwan_face_me');
  st jsonb;
begin
  perform pg_temp.login(c);
  perform life_restart();
  perform set_config('bl.test_rand', '0.05', true);
  st := create_profile_v2('Life_Chidi', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform pg_temp.assert(st->'profile'->>'origin' = 'nepo', 'nepo_pct roll applies to the new life');
  perform set_config('bl.test_rand', '0.5', true);
  perform choose_start_home('gra_duplex');
  perform life_restart();
  st := create_profile_v2('Life_Chidi', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform pg_temp.assert(st->'profile'->>'origin' = 'lapo', 'roll above nepo_pct = LAPO');
  perform pg_temp.assert((select count(*) from profile_archive where user_id = c) = 2, 'two lives archived');
  perform pg_temp.assert((select max(life_no) from profile_archive where user_id = c) = 2, 'life numbers count up');
  perform set_config('bl.test_rand', '', true);
  raise notice 'ok 3b: origin roll on a new life';
end $$;

-- ---------- 4. switch off + cooldown ----------
do $$
declare
  b uuid := pg_temp.lf('Life_Bisi');
  m text;
begin
  perform pg_temp.login(b);
  update game_config set value = 'false' where key = 'life.restart_enabled';
  m := pg_temp.lf_hint($q$ select life_restart() $q$, 'restart_disabled');
  perform pg_temp.assert(exists (select 1 from profiles where id = b), 'disabled: profile kept');
  perform pg_temp.assert(not exists (select 1 from profile_archive where user_id = b), 'disabled: nothing archived');
  update game_config set value = 'true' where key = 'life.restart_enabled';

  update game_config set value = '2' where key = 'life.restart_cooldown_hours';
  perform life_restart();   -- first one is fine
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2('Life_Bisi', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  m := pg_temp.lf_hint($q$ select life_restart() $q$, 'restart_cooldown');
  perform pg_temp.assert(m ilike '%2 hours%', 'cooldown message: ' || m);
  perform set_config('bl.test_offset_seconds', '7300', true);
  perform life_restart();
  perform pg_temp.assert(not exists (select 1 from profiles where id = b), 'after the cooldown: restarted');
  perform set_config('bl.test_offset_seconds', '', true);
  update game_config set value = '0' where key = 'life.restart_cooldown_hours';
  raise notice 'ok 4: switch + cooldown';
end $$;

-- ---------- 5. nobody can restart someone else ----------
do $$
declare
  d uuid := pg_temp.lf_make('Life_Dayo', 'lapo', 'ekenwan_face_me');
  e uuid := pg_temp.lf_make('Life_Efe', 'lapo', 'ekenwan_face_me');
  n int;
begin
  -- life_restart takes no target: Efe restarting only ever touches Efe
  perform pg_temp.login(e);
  perform life_restart();
  perform pg_temp.assert(exists (select 1 from profiles where id = d), 'Dayo untouched by Efe''s restart');
  perform pg_temp.assert(not exists (select 1 from profile_archive where user_id = d), 'nothing archived for Dayo');
  -- not logged in
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform life_restart();
    raise exception 'TEST FAILED: restart without login';
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
  end;
  -- banned players cannot restart (no ban evasion)
  update profiles set banned = true where id = d;
  perform pg_temp.login(d);
  perform pg_temp.lf_hint($q$ select life_restart() $q$, 'banned');
  perform pg_temp.assert(exists (select 1 from profiles where id = d), 'banned: profile kept');
  update profiles set banned = false where id = d;
  -- the archive is private: Dayo sees no one else's lives
  set local role authenticated;
  select count(*) into n from profile_archive;
  perform pg_temp.assert(n = 0, 'Dayo sees no archive rows: ' || n);
  perform pg_temp.login(pg_temp.lf('Life_Efe'));
  select count(*) into n from profile_archive;
  perform pg_temp.assert(n = 1, 'Efe sees her own archived life: ' || n);
  reset role;
  raise notice 'ok 5: only your own life';
end $$;

-- ---------- 6. bank transfer: new-account wait in hours ----------
do $$
declare
  f uuid := pg_temp.lf_make('Life_Femi', 'nepo', 'gra_duplex');
  m text;
begin
  perform pg_temp.login(f);
  update profiles set created_at = bl_now() - interval '10 minutes', busy_until = null where id = f;
  update game_config set value = '1440' where key = 'bank.transfer_min_account_real_minutes';
  m := pg_temp.lf_hint($q$ select bank_transfer('Life_Dayo', 100, null) $q$, 'limit');
  perform pg_temp.assert(m = 'New accounts can send money 24 hours after joining. About 23 h 50 min to go.', 'hours message: ' || m);
  update game_config set value = '150' where key = 'bank.transfer_min_account_real_minutes';
  m := pg_temp.lf_hint($q$ select bank_transfer('Life_Dayo', 100, null) $q$, 'limit');
  perform pg_temp.assert(m = 'New accounts can send money 2 h 30 min after joining. About 2 h 20 min to go.', 'h+min message: ' || m);
  update profiles set created_at = bl_now() - interval '100 minutes' where id = f;
  m := pg_temp.lf_hint($q$ select bank_transfer('Life_Dayo', 100, null) $q$, 'limit');
  perform pg_temp.assert(m = 'New accounts can send money 2 h 30 min after joining. About 50 min to go.', 'min left message: ' || m);
  update game_config set value = '30' where key = 'bank.transfer_min_account_real_minutes';
  update profiles set created_at = bl_now() - interval '10 minutes' where id = f;
  m := pg_temp.lf_hint($q$ select bank_transfer('Life_Dayo', 100, null) $q$, 'limit');
  perform pg_temp.assert(m = 'New accounts can send money after 30 real minutes. About 20 min to go.', 'short wait keeps the minutes message: ' || m);
  raise notice 'ok 6: transfer wait wording';
end $$;
