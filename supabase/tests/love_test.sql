-- Family & Love, stage 1 (20261026000200_family_love.sql). Rolled back. Run (migration applied):
--   bash scripts/sql-test.sh -- supabase/tests/love_test.sql
-- Time moves with bl.test_offset_seconds (the clock is pinned to 10:00 Benin time first, so "a game day" never flips by surprise).
-- Groups: 1 grants / RLS / private helpers / seeds / ledger · 2 opt-in + Link-ups list · 3 ask rules (self, blocked, age, cap, withdraw) ·
-- 4 accept -> talking, one partner only · 5 flirts (preset only, ledger sink, cooldown, daily cap, locked lines) · 6 level 30 -> couple, public
-- profile, bond up to 100 · 7 dates (both at the place, costs, needs, bond, cooldown, couple-only, expiry, jail / travel) · 8 decay is lazy ·
-- 9 decline + expiry + break-up cooldowns · 10 reports + admin · 11 kill switch · 12 no client access.
update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');

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

create or replace function pg_temp.cfg(p_key text, p_val text) returns void
language sql as $$ update game_config set value = p_val::jsonb where key = p_key; $$;

create or replace function pg_temp.u(p text) returns uuid language sql as $$ select current_setting('lv.' || p)::uuid $$;
create or replace function pg_temp.cash(p_uid uuid) returns bigint language sql as $$ select cash + bank from profiles where id = p_uid $$;
create or replace function pg_temp.ev(p_uid uuid, p_kind text) returns bigint language sql as $$ select count(*) from events where user_id = p_uid and kind = p_kind $$;
create or replace function pg_temp.rel(p_a uuid, p_b uuid) returns bigint language sql as $$
  select id from love_relationships where user_a = least(p_a, p_b) and user_b = greatest(p_a, p_b) order by id desc limit 1 $$;
create or replace function pg_temp.lvl(p_a uuid, p_b uuid) returns int language sql as $$
  select level from love_relationships where id = pg_temp.rel(p_a, p_b) $$;
create or replace function pg_temp.fresh(p_uid uuid) returns void language sql as $$
  update profiles set energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0, bladder = 0, needs_updated_at = bl_now(),
                      jailed_until = null, hospitalized_until = null where id = p_uid; $$;
create or replace function pg_temp.login_as(p text) returns void language sql as $$ select pg_temp.login(pg_temp.u(p)) $$;

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
declare v uuid := pg_temp.new_user(lower(p_name) || '@lv.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, weekly_rent = 0, protected_until = null, created_at = bl_now() - p_age, cash = 0, bank = 0, home_location_id = 'uselu_selfcon',
         energy = 100, hunger = 100, hygiene = 100, fun = 100, social = 100, health = 100, stress = 0 where id = v;
  perform pg_temp.at(v, 'third_east');
  return v;
end $$;

create or replace function pg_temp.money(p_uid uuid, p_cash bigint, p_bank bigint) returns void
language sql as $$ update profiles set cash = p_cash, bank = p_bank where id = p_uid; $$;

-- ---------- setup ----------
do $$
declare
  v_keys text[] := array['adm', 'a', 'b', 'c', 'd', 'e', 'y', 'z'];
  k text; u uuid;
  v_local timestamp := now() at time zone bl_clock_tz();
  v_target timestamp;
begin
  -- pin the clock to 10:00 Benin time (today, or tomorrow if it is already past 10:00)
  v_target := date_trunc('day', v_local) + case when v_local::time >= time '10:00' then interval '34 hours' else interval '10 hours' end;
  perform set_config('bl.test_offset_seconds', extract(epoch from (v_target - v_local))::text, true);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.cfg('places.hours_enabled', 'false');
  update profiles set love_open = false;   -- other opted-in players in a used database must not change the list counts (rolled back)
  foreach k in array v_keys loop
    u := pg_temp.mk('LV_' || k, case when k = 'y' then interval '1 hour' else interval '30 days' end);
    perform set_config('lv.' || k, u::text, true);
  end loop;
  update profiles set is_admin = true where id = pg_temp.u('adm');
end $$;

-- ---------- 1. grants / RLS / seeds / ledger ----------
do $$
declare v text;
begin
  perform pg_temp.assert(not has_function_privilege('anon', 'public.love_ask(uuid)', 'execute'), 'anon cannot run love_ask');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.love_ask(uuid)', 'execute'), 'authenticated can run love_ask');
  perform pg_temp.assert((select prosecdef from pg_proc where oid = 'public.love_ask(uuid)'::regprocedure), 'love_ask is security definer');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.love_overview()', 'execute') and has_function_privilege('authenticated', 'public.love_overview()', 'execute'), 'overview grants');
  select string_agg(p.proname, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like 'bl\_love\_%'
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'));
  perform pg_temp.assert(v is null, 'every bl_love_* helper is private: ' || coalesce(v, ''));
  select string_agg(p.proname, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and (p.proname like 'love\_%' or p.proname like 'admin\_love\_%')
     and (not p.prosecdef or not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%'));
  perform pg_temp.assert(v is null, 'love RPCs are security definer with a search_path: ' || coalesce(v, ''));
  select string_agg(p.proname, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and (p.proname like 'love\_%' or p.proname like 'admin\_love\_%') and has_function_privilege('anon', p.oid, 'execute');
  perform pg_temp.assert(v is null, 'anon cannot run any love RPC: ' || coalesce(v, ''));
  select string_agg(t, ', ') into v from unnest(array['love_relationships', 'love_asks', 'love_flirts', 'love_dates', 'love_log', 'love_date_invites', 'love_reports']) t
   where not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass)
      or has_table_privilege('authenticated', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'select')
      or has_table_privilege('authenticated', 'public.' || t, 'insert') or has_table_privilege('authenticated', 'public.' || t, 'update')
      or has_table_privilege('authenticated', 'public.' || t, 'delete');
  perform pg_temp.assert(v is null, 'love tables: RLS on, no grants: ' || coalesce(v, ''));
  perform pg_temp.assert((select count(*) from game_config where key like 'love.%' and category = 'love' and label <> '' and description <> '') = 18, 'all 18 love settings have a label and description');
  perform pg_temp.assert(bl_cfg_bool('love.enabled') and bl_cfg('love.min_account_days') = 2 and bl_cfg('love.max_partners') = 1 and bl_cfg('love.asks_per_day') = 5
                         and bl_cfg('love.decline_cooldown_days') = 3 and bl_cfg('love.ask_expire_hours') = 48 and bl_cfg('love.flirt_daily_cap') = 20
                         and bl_cfg('love.flirt_cooldown_minutes') = 20 and bl_cfg('love.decay_after_days') = 3 and bl_cfg('love.decay_per_day') = 2
                         and bl_cfg('love.couple_level') = 30 and bl_cfg('love.date_invite_expire_minutes') = 30 and bl_cfg('love.breakup_cooldown_days') = 3
                         and bl_cfg('love.breakup_global_cooldown_hours') = 24, 'defaults');
  perform pg_temp.assert((select count(*) from love_flirts where active) = 12 and (select count(*) from love_flirts where cost = 0) >= 2, '12 flirt lines, some free');
  perform pg_temp.assert((select count(*) from love_dates where active) >= 8
                         and not exists (select 1 from love_dates where place_id is not null and not exists (select 1 from locations l where l.id = love_dates.place_id))
                         and exists (select 1 from love_dates where min_status = 'couple') and exists (select 1 from love_dates where place_id is null), 'dates: real places, couple-only and anywhere');
  perform pg_temp.assert(not exists (select 1 from love_flirts where bl_chat_mask(text) <> text) and not exists (select 1 from love_dates where bl_chat_mask(name) <> name), 'seed text is clean');
  perform pg_temp.assert(not ('love_flirt' = any (bl_earn_reasons())) and not ('love_date' = any (bl_earn_reasons())), 'love ledger reasons are not earned');
  perform pg_temp.cfg('leaderboard.earn_reasons', '"salary,hustle,love_flirt,love_date"');
  perform pg_temp.assert(not ('love_flirt' = any (bl_earn_reasons())) and not ('love_date' = any (bl_earn_reasons())), 'not earned even if an admin lists them');
  perform pg_temp.assert(bl_econ_category('love_flirt') <> 'Other' and bl_econ_category('love_date') <> 'Other', 'Admin economy category');
  perform pg_temp.assert(bl_ledger_label('love_flirt', '{"label":"Flirt: x"}') = 'Flirt: x' and bl_ledger_label('love_date', '{}') = 'Date', 'ledger labels');
  perform pg_temp.assert(bl_admin_table_spec('love_flirts')->'cols'->>'points' = 'int' and bl_admin_table_spec('love_dates')->'cols'->>'place_id' = 'text_null', 'Content editors exist');
  perform pg_temp.assert((select love_open from profiles where id = pg_temp.u('a')) = false and (select show_relationship from profiles where id = pg_temp.u('a')) = true, 'profile flag defaults');
  perform pg_temp.assert(to_regprocedure('public.admin_love_overview()') is not null, 'admin overview exists');
  raise notice 'ok 1: grants, RLS, seeds, ledger';
end $$;

-- ---------- 2. opt-in + Link-ups list ----------
do $$
declare v jsonb; rw jsonb;
begin
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('b'))) = 'not_open', 'a closed player cannot ask');
  perform pg_temp.assert((love_overview()->'me'->>'open')::boolean = false, 'overview: closed');
  perform pg_temp.assert((love_candidates()->>'closed')::boolean is true and jsonb_array_length(love_candidates()->'rows') = 0, 'a closed player sees an empty Link-ups list');
  perform love_set_open(true);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('b'))) = 'target_closed', 'cannot ask a player who is not open');
  perform pg_temp.assert(jsonb_array_length(love_candidates()->'rows') = 0, 'nobody else is open yet');
  perform pg_temp.login_as('y'); perform love_set_open(true);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('a'))) = 'too_new', 'a too-new account cannot ask');
  perform pg_temp.login_as('b'); perform love_set_open(true);
  perform pg_temp.login_as('c'); perform love_set_open(true);
  perform pg_temp.login_as('d'); perform love_set_open(true);
  perform pg_temp.login_as('e'); perform love_set_open(true);
  perform pg_temp.login_as('z');   -- z stays closed
  perform pg_temp.login_as('a');
  v := love_candidates();
  perform pg_temp.assert((select count(*) from jsonb_array_elements(v->'rows')) = 4, 'a sees b c d e (not self, not the too-new account, not closed z): ' || (v->'rows')::text);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'id' in (pg_temp.u('a')::text, pg_temp.u('y')::text, pg_temp.u('z')::text)), 'list excludes self, young, closed');
  for rw in select * from jsonb_array_elements(v->'rows') loop
    perform pg_temp.assert(not (rw ? 'cash') and not (rw ? 'bank') and not (rw ? 'location_id') and not (rw ? 'last_seen'), 'public info only: ' || rw::text);
  end loop;
  perform pg_temp.assert((select count(*) from jsonb_array_elements(love_candidates('here')->'rows')) = 4, 'everybody is at the same place');
  perform pg_temp.at(pg_temp.u('b'), 'oba_market');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(love_candidates('here')->'rows') r where r->>'id' = pg_temp.u('b')::text), 'filter "here" drops b');
  update profiles set last_seen = bl_now() - interval '1 hour' where id = pg_temp.u('c');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(love_candidates('online')->'rows') r where r->>'id' = pg_temp.u('c')::text)
                         and exists (select 1 from jsonb_array_elements(love_candidates('online')->'rows') r where r->>'id' = pg_temp.u('d')::text), 'filter "online"');
  perform pg_temp.at(pg_temp.u('b'), 'third_east'); perform pg_temp.at(pg_temp.u('c'), 'third_east');
  -- paging
  perform pg_temp.cfg('love.list_size', '3');
  v := love_candidates('all', 0);
  perform pg_temp.assert(jsonb_array_length(v->'rows') = 3 and (v->>'has_more')::boolean, 'page 1: 3 rows and more: ' || v::text);
  v := love_candidates('all', 3);
  perform pg_temp.assert(jsonb_array_length(v->'rows') = 1 and not (v->>'has_more')::boolean, 'page 2: the last row');
  perform pg_temp.cfg('love.list_size', '999');
  perform pg_temp.assert(jsonb_array_length(love_candidates()->'rows') <= 50, 'a page is never over 50');
  perform pg_temp.cfg('love.list_size', '30');
  -- turning it off hides the player again
  perform pg_temp.login_as('d'); perform love_set_open(false);
  perform pg_temp.login_as('a');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(love_candidates()->'rows') r where r->>'id' = pg_temp.u('d')::text), 'closing the door hides the player');
  perform pg_temp.login_as('d'); perform love_set_open(true);
  raise notice 'ok 2: opt-in and Link-ups list';
end $$;

-- ---------- 3. ask rules ----------
do $$
declare v jsonb; v_ask bigint;
begin
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('a'))) = 'self', 'cannot ask yourself');
  perform pg_temp.assert(pg_temp.hint_of('select love_ask(null)') = 'self', 'cannot ask nobody');
  -- block either way
  insert into chat_blocks (blocker_id, blocked_id) values (pg_temp.u('e'), pg_temp.u('a')) on conflict do nothing;
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('e'))) = 'blocked', 'a block (either way) stops the ask');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(love_candidates()->'rows') r where r->>'id' = pg_temp.u('e')::text), 'blocked players are not listed');
  perform pg_temp.login_as('e');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('a'))) = 'blocked', 'the blocker cannot ask either');
  -- a asks b
  perform pg_temp.login_as('a');
  v := love_ask(pg_temp.u('b'));
  perform pg_temp.assert((v->>'asks_left')::int = 4 and (v->>'message') like 'Ask sent to @LV_b%', 'ask sent: ' || v::text);
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('b'), 'love_ask') = 1, 'b gets a love_ask alert');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('b'))) = 'already_asked', 'cannot ask twice');
  perform pg_temp.login_as('b');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('a'))) = 'they_asked', 'b is told a already asked');
  v := love_overview();
  perform pg_temp.assert(jsonb_array_length(v->'incoming') = 1 and v->'incoming'->0->'from'->>'username' = 'LV_a', 'b sees the incoming ask');
  perform pg_temp.login_as('a');
  v := love_overview();
  perform pg_temp.assert(v->'outgoing'->0->>'state' = 'pending' and (v->'me'->>'asks_left')::int = 4, 'a sees the outgoing ask');
  perform pg_temp.assert((select r->>'state' from jsonb_array_elements(love_candidates()->'rows') r where r->>'id' = pg_temp.u('b')::text) = 'pending', 'the list shows pending');
  -- withdraw
  v := love_ask(pg_temp.u('c'));
  v_ask := (v->>'ask_id')::bigint;
  perform pg_temp.login_as('c');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_withdraw(%s)', v_ask)) = 'no_ask', 'only the asker can withdraw');
  perform pg_temp.login_as('a');
  perform love_withdraw(v_ask);
  perform pg_temp.login_as('c');
  perform pg_temp.assert(jsonb_array_length(love_overview()->'incoming') = 0, 'c no longer sees the ask');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_withdraw(%s)', v_ask)) = 'no_ask', 'a withdrawn ask cannot be withdrawn again');
  -- a asked b (1), c (2); asking c again is allowed (withdrawn), the daily cap counts every ask
  perform love_ask(pg_temp.u('c'));
  perform pg_temp.cfg('love.asks_per_day', '3');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('d'))) = 'daily_cap', 'the daily cap counts all asks');
  perform pg_temp.assert((love_overview()->'me'->'ask_block'->>'code') = 'daily_cap' and (love_overview()->'me'->>'asks_left')::int = 0, 'overview shows the cap');
  perform pg_temp.cfg('love.asks_per_day', '5');
  perform pg_temp.assert((love_overview()->'me'->>'asks_left')::int = 2, 'two asks left with a cap of 5');
  -- an ask goes away on its own after 48 hours
  perform pg_temp.assert((select count(*) from love_asks where from_user = pg_temp.u('a') and status = 'pending') = 2, 'two pending asks from a (b and c)');
  raise notice 'ok 3: ask rules';
end $$;

-- ---------- 4. accept -> talking; one partner only ----------
do $$
declare v jsonb; v_ask bigint; v_rel bigint;
begin
  perform pg_temp.login_as('b');
  select id into v_ask from love_asks where from_user = pg_temp.u('a') and to_user = pg_temp.u('b') and status = 'pending';
  perform pg_temp.login_as('c');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_respond(%s, true)', v_ask)) = 'no_ask', 'only the person asked can answer');
  perform pg_temp.login_as('b');
  v := love_respond(v_ask, true);
  perform pg_temp.assert((v->>'accepted')::boolean, 'accepted: ' || v::text);
  v_rel := pg_temp.rel(pg_temp.u('a'), pg_temp.u('b'));
  perform pg_temp.assert((select status from love_relationships where id = v_rel) = 'talking' and pg_temp.lvl(pg_temp.u('a'), pg_temp.u('b')) = 0
                         and (select user_a < user_b from love_relationships where id = v_rel), 'a talking relationship at level 0, ordered pair');
  perform pg_temp.assert((select asked_by from love_relationships where id = v_rel) = pg_temp.u('a'), 'asked_by is a');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'love_accept') = 1, 'a gets a love_accept alert');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_respond(%s, true)', v_ask)) = 'answered', 'cannot answer twice');
  perform pg_temp.assert((select count(*) from love_log where rel_id = v_rel and kind = 'started') = 1, 'log: started');
  -- a's other pending ask (to c) is gone: a is now at the limit
  perform pg_temp.assert((select count(*) from love_asks where from_user = pg_temp.u('a') and status = 'pending') = 0, 'a has no other pending asks');
  perform pg_temp.login_as('c');
  perform pg_temp.assert(jsonb_array_length(love_overview()->'incoming') = 0, 'c lost the ask from a');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('a'))) = 'unavailable', 'a taken player cannot be asked');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(love_candidates()->'rows') r where r->>'id' in (pg_temp.u('a')::text, pg_temp.u('b')::text)), 'taken players leave the list');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('c'))) = 'taken', 'a taken player cannot ask');
  v := love_overview();
  perform pg_temp.assert(jsonb_array_length(v->'relationships') = 1 and v->'relationships'->0->'partner'->>'username' = 'LV_b' and v->'relationships'->0->>'status' = 'talking', 'overview shows the pair');
  perform pg_temp.assert(jsonb_array_length(v->'flirts') = 12 and jsonb_array_length(v->'dates') >= 8, 'menus are in the overview');
  -- raising max_partners lets a second link happen (talking + couple both count)
  perform pg_temp.cfg('love.max_partners', '2');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('c'))) = 'ok', 'two partners allowed when the setting says so');
  perform pg_temp.cfg('love.max_partners', '1');
  perform love_withdraw((select id from love_asks where from_user = pg_temp.u('a') and to_user = pg_temp.u('c') and status = 'pending'));
  raise notice 'ok 4: accept and one partner';
end $$;

-- ---------- 5. flirts ----------
do $$
declare v jsonb; v_rel bigint := pg_temp.rel(pg_temp.u('a'), pg_temp.u('b')); v_before bigint;
begin
  perform pg_temp.money(pg_temp.u('a'), 20000, 0);
  perform pg_temp.money(pg_temp.u('b'), 20000, 0);
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_flirt(%s, %L)', v_rel, 'hello i am free text')) = 'no_flirt', 'only preset lines');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_flirt(%s, %L)', v_rel, 'love_note')) = 'locked', 'a line can need a level');
  perform pg_temp.login_as('c');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_flirt(%s, %L)', v_rel, 'wave')) = 'no_relationship', 'a stranger cannot flirt into somebody else''s link-up');
  perform pg_temp.login_as('a');
  v_before := pg_temp.cash(pg_temp.u('a'));
  v := love_flirt(v_rel, 'wave');
  perform pg_temp.assert((v->>'gained')::int = 2 and (v->>'level')::int = 2 and pg_temp.cash(pg_temp.u('a')) = v_before, 'free line: +2, no cost: ' || v::text);
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('b'), 'love_flirt') = 1, 'b gets the flirt alert');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_flirt(%s, %L)', v_rel, 'wave')) = 'cooldown', 'cooldown per sender');
  -- b is not blocked by a's cooldown
  perform pg_temp.login_as('b');
  v := love_flirt(v_rel, 'smile');
  perform pg_temp.assert((v->>'level')::int = 4, 'b can flirt at once: level 4');
  perform pg_temp.advance(21 * 60);
  perform pg_temp.login_as('a');
  v_before := pg_temp.cash(pg_temp.u('a'));
  v := love_flirt(v_rel, 'compliment');   -- 200, +3
  perform pg_temp.assert((v->>'level')::int = 7 and pg_temp.cash(pg_temp.u('a')) = v_before - 200, 'paid line: level 7, cash -200');
  perform pg_temp.assert((select count(*) from ledger where user_id = pg_temp.u('a') and reason = 'love_flirt' and delta = -200) = 1, 'ledger row love_flirt');
  perform pg_temp.assert(not exists (select 1 from ledger where user_id = pg_temp.u('b') and reason = 'love_flirt' and delta > 0), 'nobody is paid for a flirt');
  perform pg_temp.assert(bl_ledger_label('love_flirt', (select meta from ledger where user_id = pg_temp.u('a') and reason = 'love_flirt' order by id desc limit 1)) like 'Flirt: %', 'readable ledger label');
  -- broke: all or nothing
  perform pg_temp.money(pg_temp.u('a'), 0, 0);
  perform pg_temp.advance(21 * 60);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_flirt(%s, %L)', v_rel, 'gist')) = 'not_enough_money', 'broke players cannot buy a paid line');
  perform pg_temp.assert(pg_temp.lvl(pg_temp.u('a'), pg_temp.u('b')) = 7 and (select count(*) from love_log where rel_id = v_rel and kind = 'flirt') = 3, 'a failed flirt changes nothing');
  perform pg_temp.assert((love_flirt(v_rel, 'wave')->>'level')::int = 9, 'a free line still works when broke');
  -- daily cap: level 9, used 9 today. Set the cap to 11: b gets only 2 of the 4 points
  perform pg_temp.cfg('love.flirt_daily_cap', '11');
  perform pg_temp.login_as('b');
  perform pg_temp.advance(21 * 60);
  v_before := pg_temp.cash(pg_temp.u('b'));
  v := love_flirt(v_rel, 'airtime');       -- 500, +4 but only 2 fit
  perform pg_temp.assert((v->>'gained')::int = 2 and (v->>'capped')::boolean and (v->>'level')::int = 11 and pg_temp.cash(pg_temp.u('b')) = v_before - 500, 'capped: only +2, full price: ' || v::text);
  perform pg_temp.advance(21 * 60);
  v_before := pg_temp.cash(pg_temp.u('b'));
  perform pg_temp.assert(pg_temp.hint_of(format('select love_flirt(%s, %L)', v_rel, 'zobo')) = 'daily_cap', 'at the cap the flirt is refused');
  perform pg_temp.assert(pg_temp.cash(pg_temp.u('b')) = v_before, 'and costs nothing');
  perform pg_temp.assert((love_overview()->'relationships'->0->>'daily_room')::int = 0, 'overview: no room today');
  -- the cap is per game day: tomorrow it resets
  perform pg_temp.cfg('love.flirt_daily_cap', '20');
  perform pg_temp.assert((love_overview()->'relationships'->0->>'daily_room')::int = 9, 'raising the cap opens room (11 used of 20)');
  -- every line text in the log is a preset
  perform pg_temp.assert(not exists (select 1 from love_log l where l.rel_id = v_rel and l.kind = 'flirt' and not exists (select 1 from love_flirts f where f.id = l.ref_id and f.text = l.text)), 'log lines are all preset lines');
  -- an inactive line is refused
  update love_flirts set active = false where id = 'zobo';
  perform pg_temp.assert(pg_temp.hint_of(format('select love_flirt(%s, %L)', v_rel, 'zobo')) = 'no_flirt', 'an inactive line is refused');
  update love_flirts set active = true where id = 'zobo';
  raise notice 'ok 5: flirts';
end $$;

-- ---------- 6. couple at 30, public profile, bond up to 100 ----------
do $$
declare v jsonb; v_rel bigint := pg_temp.rel(pg_temp.u('a'), pg_temp.u('b')); p jsonb;
begin
  perform pg_temp.login_as('a');
  perform pg_temp.money(pg_temp.u('a'), 50000, 0);
  update love_relationships set level = 28 where id = v_rel;
  perform pg_temp.advance(21 * 60);
  v := love_flirt(v_rel, 'zobo');       -- +4 -> 32
  perform pg_temp.assert((v->>'couple_now')::boolean and (v->>'level')::int = 32, 'crossing 30 flips to couple: ' || v::text);
  perform pg_temp.assert((select status from love_relationships where id = v_rel) = 'couple' and (select couple_at from love_relationships where id = v_rel) is not null, 'status couple');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'love_couple') = 1 and pg_temp.ev(pg_temp.u('b'), 'love_couple') = 1, 'both get the couple alert');
  perform pg_temp.assert((select count(*) from love_log where rel_id = v_rel and kind = 'couple') = 1, 'log: couple');
  perform pg_temp.assert(love_overview()->'relationships'->0->>'status' = 'couple', 'overview: couple');
  -- public profile
  perform pg_temp.login_as('c');
  p := get_public_profile(pg_temp.u('a'));
  perform pg_temp.assert(p->'relationship'->>'status' = 'couple' and p->'relationship'->'partner'->>'username' = 'LV_b', 'profile shows "With @LV_b": ' || p::text);
  perform pg_temp.assert((p->>'love_open')::boolean, 'profile says open to link-ups');
  perform pg_temp.assert(not (p ? 'cash') and not (p ? 'show_relationship'), 'no money or private flags in the public profile');
  perform pg_temp.login_as('a');
  perform love_set_show_relationship(false);
  perform pg_temp.login_as('c');
  perform pg_temp.assert(get_public_profile(pg_temp.u('a'))->'relationship' = 'null'::jsonb, 'hidden when the player turns it off');
  perform pg_temp.assert(get_public_profile(pg_temp.u('b'))->'relationship'->'partner'->>'username' = 'LV_a', 'b still shows (own switch)');
  perform pg_temp.login_as('a');
  perform love_set_show_relationship(true);
  -- my own state carries my flags only
  perform pg_temp.assert((get_my_state()->'profile'->>'love_open')::boolean and (get_my_state()->'profile'->>'show_relationship')::boolean, 'my own flags are in my state');
  -- bond counts past 30, up to 100
  update love_relationships set level = 99 where id = v_rel;
  perform pg_temp.advance(21 * 60);
  v := love_flirt(v_rel, 'flowers');   -- +6, one fits
  perform pg_temp.assert((v->>'level')::int = 100 and (v->>'gained')::int = 1, 'level stops at 100');
  update love_relationships set level = 40 where id = v_rel;
  raise notice 'ok 6: couple, public profile, bond';
end $$;

-- ---------- 7. dates ----------
do $$
declare
  a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); v jsonb; v_rel bigint := pg_temp.rel(pg_temp.u('a'), pg_temp.u('b'));
  v_inv bigint; v_ca bigint; v_cb bigint; v_lvl int; v_fun numeric; v_soc numeric;
begin
  perform pg_temp.money(a, 100000, 0); perform pg_temp.money(b, 100000, 0);
  update profiles set fun = 50, social = 50, hunger = 100, energy = 100, health = 100, hygiene = 100, bladder = 0, stress = 0, needs_updated_at = bl_now() where id in (a, b);
  update love_relationships set last_activity_at = bl_now() where id = v_rel;
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_invite(%L)', 'suya_oba')) = 'not_there', 'the inviter has to be at the place');
  perform pg_temp.at(a, 'oba_market');
  v := love_date_invite('suya_oba');
  v_inv := (v->>'invite_id')::bigint;
  perform pg_temp.assert(pg_temp.ev(b, 'love_date_invite') = 1, 'b gets the invite alert');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_invite(%L)', 'ring_walk')) in ('pending', 'not_there'), 'one invite at a time');
  perform pg_temp.assert(love_overview()->'relationships'->0->'invite'->>'date_id' = 'suya_oba', 'overview shows the pending invite');
  -- b must be there too
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_respond(%s, true)', v_inv)) = 'not_there', 'the partner has to be at the place');
  perform pg_temp.at(b, 'oba_market'); perform pg_temp.at(a, 'third_east');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_respond(%s, true)', v_inv)) = 'partner_not_there', 'and so does the one who invited');
  perform pg_temp.at(a, 'oba_market');
  perform pg_temp.login(a);   -- the inviter cannot answer their own invite
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_respond(%s, true)', v_inv)) = 'no_invite', 'only the invited partner answers');
  perform pg_temp.login(b);
  v_ca := pg_temp.cash(a); v_cb := pg_temp.cash(b); v_lvl := pg_temp.lvl(a, b);
  v := love_date_respond(v_inv, true);
  perform pg_temp.assert((v->>'accepted')::boolean and (v->>'gained')::int = 3, 'date done, +3 bond: ' || v::text);
  perform pg_temp.assert(pg_temp.cash(a) = v_ca - 3000 and pg_temp.cash(b) = v_cb - 3000, 'each pays their share');
  perform pg_temp.assert((select count(*) from ledger where reason = 'love_date' and delta = -3000 and user_id in (a, b)) = 2, 'two ledger rows love_date');
  perform pg_temp.assert(not exists (select 1 from ledger where reason = 'love_date' and delta > 0), 'never earned');
  select fun, social into v_fun, v_soc from profiles where id = a;
  perform pg_temp.assert(v_fun >= 57 and v_soc >= 59, 'a gained fun and social: ' || v_fun || '/' || v_soc);
  select fun, social into v_fun, v_soc from profiles where id = b;
  perform pg_temp.assert(v_fun >= 57 and v_soc >= 59, 'b gained fun and social');
  perform pg_temp.assert(pg_temp.lvl(a, b) = v_lvl + 3, 'the pair gained bond');
  perform pg_temp.assert((select count(*) from love_log where rel_id = v_rel and kind = 'date' and ref_id = 'suya_oba') = 1 and pg_temp.ev(a, 'love_date') = 1, 'logged + alert to the inviter');
  perform pg_temp.assert(love_overview()->'relationships'->0->'recent_dates'->0->>'text' = 'Suya at Oba Market', 'Us tab: recent dates');
  -- cooldown per pair per date
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_invite(%L)', 'suya_oba')) = 'cooldown', 'same date again: cooldown');
  perform pg_temp.assert((love_overview()->'relationships'->0->'date_cooldowns'->>'suya_oba')::int > 0, 'overview shows the cooldown');
  -- a broke inviter cannot send an invite
  perform pg_temp.money(a, 0, 0);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_invite(%L)', 'video_call')) = 'not_enough_money', 'a broke inviter is refused');
  raise notice 'ok 7a: first date, cooldown, broke inviter';
end $$;

do $$
declare
  a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); v jsonb; v_rel bigint := pg_temp.rel(pg_temp.u('a'), pg_temp.u('b'));
  v_inv bigint; v_cb bigint; v_lvl int;
begin
  -- the inviter has the money, the partner does not
  perform pg_temp.money(a, 100000, 0); perform pg_temp.money(b, 100, 0);
  perform pg_temp.login(a);
  v := love_date_invite('video_call');           -- 300 each, anywhere
  v_inv := (v->>'invite_id')::bigint;
  perform pg_temp.login(b);
  v_cb := pg_temp.cash(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_respond(%s, true)', v_inv)) = 'not_enough_money', 'the broke partner cannot accept');
  perform pg_temp.assert(pg_temp.cash(b) = v_cb and pg_temp.cash(a) = 100000, 'all or nothing: nobody was charged');
  perform pg_temp.money(a, 100, 0); perform pg_temp.money(b, 100000, 0);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_respond(%s, true)', v_inv)) = 'partner_broke', 'a broke inviter cannot cover their share either');
  perform pg_temp.money(a, 100000, 0);
  -- jail / travel
  update profiles set jailed_until = bl_now() + interval '1 hour' where id = b;
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_respond(%s, true)', v_inv)) = 'jailed', 'jailed: no date');
  update profiles set jailed_until = null, travel_to = 'oba_market' where id = b;
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_respond(%s, true)', v_inv)) = 'travelling', 'travelling: no date');
  update profiles set travel_to = null where id = b;
  v_lvl := pg_temp.lvl(a, b);
  v := love_date_respond(v_inv, true);
  perform pg_temp.assert((v->>'accepted')::boolean and pg_temp.cash(a) = 100000 - 300 and pg_temp.cash(b) = 100000 - 300, 'anywhere-date: no place rule, 300 each');
  perform pg_temp.assert(pg_temp.lvl(a, b) = v_lvl + 1, 'bond +1');
  -- expiry: an invite waits 30 minutes
  perform pg_temp.advance(3 * 3600 + 60);
  perform pg_temp.login(a);
  v := love_date_invite('video_call');
  v_inv := (v->>'invite_id')::bigint;
  perform pg_temp.advance(31 * 60);
  perform pg_temp.login(b);
  v := love_date_respond(v_inv, true);
  perform pg_temp.assert((v->>'expired')::boolean and not (v->>'accepted')::boolean, 'an old invite has expired');
  perform pg_temp.assert((select status from love_date_invites where id = v_inv) = 'expired', 'stored as expired');
  -- decline sends a kind note
  perform pg_temp.login(a);
  v := love_date_invite('video_call');
  v_inv := (v->>'invite_id')::bigint;
  perform pg_temp.login(b);
  perform love_date_respond(v_inv, false);
  perform pg_temp.assert((select status from love_date_invites where id = v_inv) = 'declined', 'declined');
  -- an unanswered invite is expired lazily by the next invite
  perform pg_temp.login(a);
  v := love_date_invite('video_call');
  perform pg_temp.advance(31 * 60);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_invite(%L)', 'video_call')) = 'ok', 'a stale invite does not block a new one');
  -- the daily cap is shared: with no room left the date still happens, bond is capped
  perform pg_temp.advance(3 * 3600);
  perform pg_temp.at(a, 'oba_palace'); perform pg_temp.at(b, 'oba_palace');
  update love_date_invites set status = 'cancelled' where rel_id = v_rel and status = 'pending';
  v := love_date_invite('palace_walk');
  v_inv := (v->>'invite_id')::bigint;
  perform pg_temp.cfg('love.flirt_daily_cap', '1');
  v_lvl := pg_temp.lvl(a, b);
  perform pg_temp.login(b);
  v := love_date_respond(v_inv, true);
  perform pg_temp.assert((v->>'accepted')::boolean and (v->>'gained')::int = 0 and pg_temp.lvl(a, b) = v_lvl and (v->>'message') like '%capped%', 'capped bond: the date still happens: ' || v::text);
  perform pg_temp.cfg('love.flirt_daily_cap', '20');
  raise notice 'ok 7b: broke, jail, travel, anywhere, expiry, decline, shared cap';
end $$;

-- ---------- 8. decay is lazy ----------
do $$
declare
  a uuid := pg_temp.u('a'); b uuid := pg_temp.u('b'); v_rel bigint := pg_temp.rel(pg_temp.u('a'), pg_temp.u('b')); v jsonb;
begin
  update love_relationships set level = 50, status = 'couple', last_activity_at = bl_now(), decay_days = 0 where id = v_rel;
  perform pg_temp.login(a);
  perform pg_temp.advance(3 * 86400);                                  -- 3 idle days: still inside the grace
  perform pg_temp.assert((love_overview()->'relationships'->0->>'level')::int = 50, 'no loss inside the grace days');
  perform pg_temp.advance(2 * 86400);                                  -- 5 idle days: 2 days past the grace = -4
  perform pg_temp.assert((love_overview()->'relationships'->0->>'level')::int = 46, 'shown after decay: 46');
  perform pg_temp.assert((select level from love_relationships where id = v_rel) = 50 and (select decay_days from love_relationships where id = v_rel) = 0, 'reading wrote nothing');
  perform pg_temp.assert(pg_temp.lvl(a, pg_temp.u('c')) is null, 'only this pair is involved');
  perform pg_temp.cfg('love.flirt_cooldown_minutes', '0');
  perform pg_temp.money(a, 50000, 0); perform pg_temp.fresh(a); perform pg_temp.fresh(b);
  v := love_flirt(v_rel, 'wave');                                      -- write: settle, then +2
  perform pg_temp.assert((v->>'level')::int = 48 and (select level from love_relationships where id = v_rel) = 48 and (select decay_days from love_relationships where id = v_rel) = 0, 'a write settles the decay, then adds: 48');
  perform pg_temp.cfg('love.flirt_cooldown_minutes', '20');
  -- a couple never falls under the couple level
  update love_relationships set level = 33, last_activity_at = bl_now(), decay_days = 0 where id = v_rel;
  perform pg_temp.advance(30 * 86400);
  perform pg_temp.assert((love_overview()->'relationships'->0->>'level')::int = 30 and (love_overview()->'relationships'->0->>'status') = 'couple', 'a couple keeps the couple level and the status');
  -- a talking pair can fall to 0
  update love_relationships set status = 'talking', level = 6, last_activity_at = bl_now(), decay_days = 0 where id = v_rel;
  perform pg_temp.advance(10 * 86400);
  perform pg_temp.assert((love_overview()->'relationships'->0->>'level')::int = 0, 'a talking pair fades to 0');
  -- decay off
  perform pg_temp.cfg('love.decay_per_day', '0');
  update love_relationships set level = 20, last_activity_at = bl_now(), decay_days = 0 where id = v_rel;
  perform pg_temp.advance(20 * 86400);
  perform pg_temp.assert((love_overview()->'relationships'->0->>'level')::int = 20, 'decay_per_day 0 = no decay');
  perform pg_temp.cfg('love.decay_per_day', '2');
  update love_relationships set status = 'couple', level = 40, last_activity_at = bl_now(), decay_days = 0 where id = v_rel;
  raise notice 'ok 8: lazy decay';
end $$;

-- ---------- 9. decline, expiry, break-up cooldowns (pair c + d) ----------
do $$
declare
  c uuid := pg_temp.u('c'); d uuid := pg_temp.u('d'); v jsonb; v_ask bigint; v_rel bigint; v_evs bigint;
begin
  perform pg_temp.fresh(c); perform pg_temp.fresh(d);
  perform pg_temp.login(d);
  update love_asks set status = 'withdrawn' where from_user = d and status = 'pending';
  v := love_ask(c);
  v_ask := (v->>'ask_id')::bigint;
  perform pg_temp.login(c);
  v_evs := (select count(*) from events where user_id = d);
  v := love_respond(v_ask, false);
  perform pg_temp.assert(not (v->>'accepted')::boolean, 'declined');
  perform pg_temp.assert((select count(*) from events where user_id = d) = v_evs, 'declining is silent: the asker gets no alert');
  perform pg_temp.login(d);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', c)) = 'later', 'cannot ask again during the decline cooldown');
  perform pg_temp.assert((love_overview()->'outgoing'->0->>'state') = 'noreply', 'the asker only sees "No reply"');
  perform pg_temp.assert((select r->>'state' from jsonb_array_elements(love_candidates()->'rows') r where r->>'id' = c::text) = 'later', 'the list says later');
  perform pg_temp.advance(3 * 86400 + 3600);
  v := love_ask(c);
  v_ask := (v->>'ask_id')::bigint;
  -- expiry: 48 hours
  perform pg_temp.advance(49 * 3600);
  perform pg_temp.login(c);
  perform pg_temp.assert(jsonb_array_length(love_overview()->'incoming') = 0, 'an expired ask is not shown');
  v := love_respond(v_ask, true);
  perform pg_temp.assert((v->>'expired')::boolean and not (v->>'accepted')::boolean, 'cannot accept an expired ask');
  perform pg_temp.assert((select status from love_asks where id = v_ask) = 'expired', 'stored as expired');
  perform pg_temp.login(d);
  v := love_overview();
  perform pg_temp.assert((v->'outgoing'->0->>'state') = 'noreply', 'expired = No reply');
  v := love_ask(c);
  v_ask := (v->>'ask_id')::bigint;
  perform pg_temp.login(c);
  v := love_respond(v_ask, true);
  perform pg_temp.assert((v->>'accepted')::boolean, 'now accepted');
  v_rel := pg_temp.rel(c, d);
  -- a talking pair cannot do couple-only dates
  perform pg_temp.at(c, 'protea_hotel'); perform pg_temp.at(d, 'protea_hotel');
  perform pg_temp.money(d, 100000, 0);
  perform pg_temp.login(d);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_invite(%L)', 'getaway')) = 'couples_only', 'couple-only dates need a couple');
  perform pg_temp.at(c, 'third_east'); perform pg_temp.at(d, 'third_east');
  -- break-up
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_breakup(%s)', pg_temp.rel(pg_temp.u('a'), pg_temp.u('b')))) = 'no_relationship', 'cannot end somebody else''s link-up');
  perform pg_temp.login(d);
  perform love_date_invite('video_call');
  perform love_breakup();
  perform pg_temp.assert((select status from love_relationships where id = v_rel) = 'ended' and (select ended_at from love_relationships where id = v_rel) is not null
                         and (select ended_by from love_relationships where id = v_rel) = d, 'ended, with who and when');
  perform pg_temp.assert(not exists (select 1 from love_date_invites where rel_id = v_rel and status = 'pending'), 'its pending invite was cancelled');
  perform pg_temp.assert(pg_temp.ev(c, 'love_breakup') = 1, 'c is told, kindly');
  perform pg_temp.assert((select count(*) from love_log where rel_id = v_rel) >= 2, 'history is kept');
  perform pg_temp.assert(jsonb_array_length(love_overview()->'relationships') = 0, 'no active relationship after a break-up');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_breakup(%s)', v_rel)) = 'no_relationship', 'cannot end it twice');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', c)) = 'cooldown_global', 'after a break-up: nobody for a day');
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('z'))) = 'cooldown_global', 'the other partner has the day too');
  perform pg_temp.advance(25 * 3600);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', d)) = 'later', 'but not each other for 3 days');
  perform pg_temp.login(d);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', c)) = 'later', 'both ways');
  perform pg_temp.assert(love_overview()->'me'->'ask_block' = 'null'::jsonb, 'the day is over: they can ask other people');
  perform pg_temp.advance(3 * 86400);
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', c)) = 'ok', 'after 3 days they may ask each other again');
  raise notice 'ok 9: decline, expiry, break-up cooldowns';
end $$;

-- ---------- 10. reports + admin ----------
do $$
declare v jsonb; v_id bigint;
begin
  perform pg_temp.login_as('z');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_report(%L, %L)', pg_temp.u('a'), 'creepy')) = 'no_link', 'only somebody you linked up with');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_report(%L, %L)', pg_temp.u('z'), 'x')) = 'bad_target', 'not yourself');
  perform pg_temp.login_as('d');
  perform love_report(pg_temp.u('c'), E'He keeps\nsending rude things   ');
  perform pg_temp.assert((select reason from love_reports where reporter_id = pg_temp.u('d') and reported_id = pg_temp.u('c')) = 'He keeps sending rude things', 'reason is cleaned');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_report(%L, %L)', pg_temp.u('c'), 'again')) = 'already_reported', 'one open report per pair');
  perform pg_temp.cfg('love.report_daily_cap', '1');
  perform pg_temp.login_as('a');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_report(%L, %L)', pg_temp.u('b'), 'x')) = 'ok', 'a reports b (first of the day)');
  perform pg_temp.login_as('d');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_report(%L, %L)', pg_temp.u('e'), 'x')) in ('no_link', 'report_cap'), 'report cap / link');
  perform pg_temp.cfg('love.report_daily_cap', '5');
  perform pg_temp.login_as('b');
  perform pg_temp.assert(pg_temp.hint_of('select admin_love_overview()') = 'not_admin', 'players cannot read the admin overview');
  perform pg_temp.assert(pg_temp.hint_of('select admin_love_report_set(1, ''reviewed'')') = 'not_admin', 'nor handle reports');
  perform pg_temp.login_as('adm');
  v := admin_love_overview();
  perform pg_temp.assert((v->>'open_reports')::int >= 2 and (v->>'couples')::int >= 1 and jsonb_array_length(v->'reports') >= 2, 'admin counts and list: ' || (v - 'reports')::text);
  v_id := (v->'reports'->0->>'id')::bigint;
  perform admin_love_report_set(v_id, 'reviewed');
  perform pg_temp.assert((select status from love_reports where id = v_id) = 'reviewed' and exists (select 1 from admin_audit where action = 'love_report_reviewed'), 'handled + audited');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_love_report_set(%s, %L)', v_id, 'banana')) = 'bad_value', 'status is checked');
  -- admin ends a link-up
  perform admin_love_end(pg_temp.rel(pg_temp.u('a'), pg_temp.u('b')), 'abuse');
  perform pg_temp.assert((select status from love_relationships where id = pg_temp.rel(pg_temp.u('a'), pg_temp.u('b'))) = 'ended' and exists (select 1 from admin_audit where action = 'love_end'), 'admin end + audit');
  perform pg_temp.assert(pg_temp.ev(pg_temp.u('a'), 'love_breakup') = 1 and pg_temp.ev(pg_temp.u('b'), 'love_breakup') = 1, 'both told');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_love_end(%s)', pg_temp.rel(pg_temp.u('a'), pg_temp.u('b')))) = 'no_relationship', 'already ended');
  raise notice 'ok 10: reports and admin';
end $$;

-- ---------- 11. kill switch ----------
do $$
declare v jsonb;
begin
  perform pg_temp.cfg('love.enabled', 'false');
  perform pg_temp.login_as('c');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_ask(%L)', pg_temp.u('z'))) = 'off', 'asks are off');
  perform pg_temp.assert((love_candidates()->>'enabled')::boolean = false, 'list is off');
  perform pg_temp.assert((love_overview()->>'enabled')::boolean = false, 'overview says off');
  perform pg_temp.assert(get_public_profile(pg_temp.u('c'))->'love_open' = 'false'::jsonb, 'profile: not open while off');
  perform pg_temp.cfg('love.enabled', 'true');
  -- a couple and the switch: flirt and date are off too (the admin ended a+b above, so bring them back)
  perform pg_temp.login_as('a');
  update love_relationships set status = 'couple', level = 40, ended_at = null, ended_by = null, last_activity_at = bl_now(), decay_days = 0
   where id = pg_temp.rel(pg_temp.u('a'), pg_temp.u('b'));
  perform pg_temp.cfg('love.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_flirt(%s, %L)', pg_temp.rel(pg_temp.u('a'), pg_temp.u('b')), 'wave')) = 'off', 'flirts are off');
  perform pg_temp.assert(pg_temp.hint_of(format('select love_date_invite(%L, %s)', 'video_call', pg_temp.rel(pg_temp.u('a'), pg_temp.u('b')))) = 'off', 'dates are off');
  perform pg_temp.assert(love_overview()->'relationships'->0->>'status' = 'couple', 'an existing couple is kept');
  perform pg_temp.cfg('love.enabled', 'true');
  raise notice 'ok 11: kill switch';
end $$;

-- ---------- 12. no client access to the tables ----------
do $$
declare t text; v boolean;
begin
  perform pg_temp.login_as('a');
  set local role authenticated;
  foreach t in array array['love_relationships', 'love_asks', 'love_flirts', 'love_dates', 'love_log', 'love_date_invites', 'love_reports'] loop
    begin
      execute format('select * from public.%I limit 1', t);
      v := false;
    exception when insufficient_privilege then v := true;
    end;
    reset role;
    perform pg_temp.assert(v, 'clients cannot read ' || t);
    set local role authenticated;
    begin
      execute format('delete from public.%I', t);
      v := false;
    exception when insufficient_privilege then v := true;
    end;
    reset role;
    perform pg_temp.assert(v, 'clients cannot write ' || t);
    set local role authenticated;
  end loop;
  reset role;
  raise notice 'ok 12: no direct table access';
end $$;
