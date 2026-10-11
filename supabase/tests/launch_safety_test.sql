-- L1 launch safety pass (20261012000600_launch.sql + a sweep of the RPCs added since 2026-10-09). Rolled back. Run:
--   bash scripts/sql-test.sh -- supabase/tests/launch_safety_test.sql
-- Groups: 1 schema-wide guards (search_path, anon grants, private bl_*, RLS on, no table write grants) ·
-- 2 client_error_log (anon + player insert, caps, path only, rate limit, no direct read) + admin_client_errors ·
-- 3 RLS: player B cannot read or change player A's rows · 4 negative / huge amounts are refused ·
-- 5 acting on other players' things (furniture keys, cars, ads, interactions) · 6 furniture_sell double-sell guard.
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

-- ---------- 1. schema-wide guards ----------
do $$
declare v text;
begin
  select string_agg(p.proname, ', ') into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  perform pg_temp.assert(v is null, 'security definer functions without search_path: ' || coalesce(v, ''));

  select string_agg(p.proname, ', ') into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
     and p.proname not in ('creator_catalog', 'client_error_log', 'bl_social_can_view_private_home');
  perform pg_temp.assert(v is null, 'anon can execute: ' || coalesce(v, ''));

  select string_agg(p.proname, ', ') into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'bl\_%'
     and has_function_privilege('authenticated', p.oid, 'execute')
     and p.proname not in ('bl_social_active_house_topic', 'bl_social_can_chat_voice', 'bl_social_can_use_conversation',
                           'bl_social_can_view_owner_home', 'bl_social_can_view_private_home'); -- RLS policy helpers
  perform pg_temp.assert(v is null, 'private bl_* callable by players: ' || coalesce(v, ''));

  select string_agg(c.relname, ', ') into v
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  perform pg_temp.assert(v is null, 'tables without RLS: ' || coalesce(v, ''));

  select string_agg(distinct table_name || ':' || grantee || ':' || privilege_type, ', ') into v
    from information_schema.role_table_grants
   where table_schema = 'public' and grantee in ('anon', 'authenticated') and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  perform pg_temp.assert(v is null, 'table write grants to players: ' || coalesce(v, ''));
  raise notice 'ok 1: schema-wide guards';
end $$;

-- ---------- setup: two players ----------
do $$
declare a uuid := pg_temp.new_user('l1_a@safety.bl'); b uuid := pg_temp.new_user('l1_b@safety.bl'); ad uuid := pg_temp.new_user('l1_admin@safety.bl');
begin
  perform set_config('l1.a', a::text, true); perform set_config('l1.b', b::text, true); perform set_config('l1.admin', ad::text, true);
  update game_config set value = 'true' where key in ('furniture.sell_enabled', 'cars.sell_enabled', 'errors.enabled');
  update game_config set value = '5' where key = 'errors.per_user_per_hour';
  update furniture set price = 6500, max_qty = 6, active = true, buyable = true where id = 'plastic_chair_red';
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(a);
  perform create_profile_v2('L1_Alpha', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(b);
  perform create_profile_v2('L1_Bravo', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(ad);
  perform create_profile_v2('L1_Admin', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set is_admin = true where id = ad;
  update profiles set rent_owed = 0, busy_until = null, travel_to = null, cash = 50000, bank = 0 where id in (a, b, ad);
  delete from client_errors;
end $$;

-- ---------- 2. client errors ----------
do $$ begin perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); end $$;
set local role anon;
do $$
declare r jsonb;
begin
  r := client_error_log('error', 'TypeError: x is undefined', 'at foo (app.js:1:2)', 'https://benin-life.vercel.app/play?token=SECRET#frag', 'abc-123', 'Mozilla/5.0');
  perform pg_temp.assert((r->>'logged')::boolean, 'anon can log an error');
  begin
    perform count(*) from client_errors;
    raise exception 'TEST FAILED: anon can read client_errors';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin perform pg_temp.login(current_setting('l1.a')::uuid); end $$;
set local role authenticated;
do $$
declare r jsonb; i int;
begin
  r := client_error_log('boundary', repeat('M', 2000), repeat('S', 10000), '/play', repeat('b', 200), repeat('u', 1000));
  perform pg_temp.assert((r->>'logged')::boolean, 'player can log an error');
  r := client_error_log('nonsense-kind', '   ', null, null, null, null);
  perform pg_temp.assert(not (r->>'logged')::boolean, 'empty message refused');
  for i in 1..10 loop r := client_error_log('error', 'spam ' || i, null, null, null, null); end loop;
  perform pg_temp.assert(not (r->>'logged')::boolean and r->>'reason' = 'rate', 'per-player rate limit');
  begin
    insert into client_errors (message) values ('direct');
    raise exception 'TEST FAILED: direct insert into client_errors worked';
  exception when insufficient_privilege then null; end;
  begin
    perform admin_client_errors(24);
    raise exception 'TEST FAILED: non-admin read admin_client_errors';
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
  end;
end $$;
reset role;
do $$
declare e client_errors; n int;
begin
  select * into e from client_errors where user_id is null order by id limit 1;
  perform pg_temp.assert(e.url = 'https://benin-life.vercel.app/play', 'query string and hash stripped: ' || coalesce(e.url, 'null'));
  select * into e from client_errors where kind = 'boundary' limit 1;
  perform pg_temp.assert(e.user_id = current_setting('l1.a')::uuid, 'user id comes from the session');
  perform pg_temp.assert(length(e.message) <= 500 and length(e.stack) <= 4000 and length(e.build) <= 80 and length(e.ua) <= 200, 'sizes capped');
  select count(*) into n from client_errors where user_id = current_setting('l1.a')::uuid;
  perform pg_temp.assert(n = 5, 'exactly the per-hour cap stored, got ' || n);
end $$;
do $$ begin perform pg_temp.login(current_setting('l1.admin')::uuid); end $$;
set local role authenticated;
do $$
declare r jsonb;
begin
  r := admin_client_errors(24);
  perform pg_temp.assert((r->>'total')::int = 6, 'admin sees all reports, got ' || (r->>'total'));
  perform pg_temp.assert(jsonb_array_length(r->'groups') = 6, 'grouped by message');
  perform pg_temp.assert((r->'groups'->0) ? 'samples', 'groups carry samples');
  raise notice 'ok 2: client errors';
end $$;
reset role;

-- ---------- 3. RLS between players ----------
do $$
declare a uuid := current_setting('l1.a')::uuid;
begin
  perform pg_temp.login(a);
  perform furniture_buy('plastic_chair_red');
  perform daily_reward_claim();
end $$;
do $$ begin perform pg_temp.login(current_setting('l1.b')::uuid); end $$;
set local role authenticated;
do $$
declare a uuid := current_setting('l1.a')::uuid; n int;
begin
  perform pg_temp.assert((select count(*) from profiles where id = a) = 0, 'B cannot read A''s profile row');
  perform pg_temp.assert((select count(*) from ledger where user_id = a) = 0, 'B cannot read A''s ledger');
  perform pg_temp.assert((select count(*) from player_furniture where user_id = a) = 0, 'B cannot read A''s furniture (not visiting)');
  perform pg_temp.assert((select count(*) from player_house_furniture where owner_id = a) = 0, 'B cannot read A''s layout (not visiting)');
  perform pg_temp.assert((select count(*) from receipts where user_id = a) = 0, 'B cannot read A''s receipts');
  perform pg_temp.assert((select count(*) from daily_reward_state where user_id = a) = 0, 'B cannot read A''s daily state');
  perform pg_temp.assert((select count(*) from inventory where user_id = a) = 0, 'B cannot read A''s bag');
  perform pg_temp.assert((select count(*) from billboard_ads where user_id = a) = 0, 'B cannot read A''s ads');
  begin
    update profiles set cash = 999999999 where id = a;
    raise exception 'TEST FAILED: direct profile update allowed';
  exception when insufficient_privilege then null; end;
  begin
    update profiles set cash = 999999999 where id = current_setting('l1.b')::uuid;
    raise exception 'TEST FAILED: player can set own cash';
  exception when insufficient_privilege then null; end;
  begin
    delete from player_furniture where user_id = a;
    raise exception 'TEST FAILED: direct delete allowed';
  exception when insufficient_privilege then null; end;
  begin
    insert into home_layouts (id) values ('l1_fake');
    raise exception 'TEST FAILED: home_layouts insert allowed';
  exception when insufficient_privilege then null; end;
  raise notice 'ok 3: RLS between players';
end $$;
reset role;

-- ---------- 4. negative / huge amounts ----------
do $$
declare b uuid := current_setting('l1.b')::uuid; c0 bigint; b0 bigint; h text;
begin
  perform pg_temp.login(b);
  select cash, bank into c0, b0 from profiles where id = b;
  h := pg_temp.hint_of('select bank_deposit(-5000)');           perform pg_temp.assert(h <> 'ok', 'negative deposit refused');
  h := pg_temp.hint_of('select bank_withdraw(-5000)');          perform pg_temp.assert(h <> 'ok', 'negative withdraw refused');
  h := pg_temp.hint_of('select bank_deposit(9000000000000000)'); perform pg_temp.assert(h <> 'ok', 'huge deposit refused');
  h := pg_temp.hint_of('select pos_deposit(-100)');             perform pg_temp.assert(h <> 'ok', 'negative PoS refused');
  h := pg_temp.hint_of('select bank_transfer(''L1_Alpha'', -1000)'); perform pg_temp.assert(h <> 'ok', 'negative transfer refused');
  h := pg_temp.hint_of('select shop_buy(''noodles_pack'', -3)'); perform pg_temp.assert(h <> 'ok', 'negative qty refused');
  h := pg_temp.hint_of('select shop_buy(''noodles_pack'', 1000000)'); perform pg_temp.assert(h <> 'ok', 'huge qty refused');
  h := pg_temp.hint_of('select item_sell(''noodles_pack'', -3)'); perform pg_temp.assert(h <> 'ok', 'negative sell refused');
  h := pg_temp.hint_of('select food_order(''jollof_pack'', -2)'); perform pg_temp.assert(h <> 'ok', 'negative food order refused');
  perform pg_temp.assert((select cash = c0 and bank = b0 from profiles where id = b), 'balances unchanged after refused calls');
  -- billboard view counts are capped per call and throttled per player
  perform pg_temp.assert(((billboard_track(jsonb_build_object(gen_random_uuid()::text, 999999)))->>'counted')::int = 0, 'unknown ad counts nothing');
  raise notice 'ok 4: negative / huge amounts';
end $$;

-- ---------- 5. other players' things ----------
do $$
declare a uuid := current_setting('l1.a')::uuid; b uuid := current_setting('l1.b')::uuid; h text; c0 bigint; ad uuid;
begin
  perform pg_temp.login(b);
  select cash into c0 from profiles where id = b;
  h := pg_temp.hint_of('select furniture_sell(''own_plastic_chair_red'')');
  perform pg_temp.assert(h <> 'ok', 'B cannot sell A''s chair: ' || h);
  h := pg_temp.hint_of('select furniture_place(''own_plastic_chair_red'', 0, 0, 0)');
  perform pg_temp.assert(h <> 'ok', 'B cannot place A''s chair');
  h := pg_temp.hint_of('select furniture_store(''own_plastic_chair_red'')');
  perform pg_temp.assert(h <> 'ok', 'B cannot store A''s chair');
  h := pg_temp.hint_of('select car_sell(''tokunbo_car'')');
  perform pg_temp.assert(h = 'not_owned', 'B cannot sell a car B does not own: ' || h);
  -- an ad that belongs to A cannot be cancelled by B
  insert into billboard_ads (board_id, user_id, kind, image_path, link_url, days, price_kobo, status, reference)
  select id, a, 'paid', a::text || '/x.png', 'https://wa.me/1', 1, 100000, 'awaiting_payment', 'BLAD-L1TEST' from billboards limit 1
  returning id into ad;
  perform pg_temp.assert(not ((billboard_ad_cancel(ad))->>'cancelled')::boolean, 'B cannot cancel A''s ad');
  perform pg_temp.assert((select status from billboard_ads where id = ad) = 'awaiting_payment', 'A''s ad untouched');
  h := pg_temp.hint_of(format('select social_interact_request(%L, ''gist'')', a));
  perform pg_temp.assert(h <> 'ok', 'no interaction with someone not in the same house');
  perform pg_temp.assert((select cash from profiles where id = b) = c0, 'B''s money unchanged');
  raise notice 'ok 5: other players'' things';
end $$;

-- ---------- 6. furniture_sell double-sell guard ----------
do $$
declare a uuid := current_setting('l1.a')::uuid; h text; c0 bigint;
begin
  perform pg_temp.assert((select prosrc like '%pf.qty < v_copy%' from pg_proc where proname = 'furniture_sell'), 'furniture_sell has the not-found guard');
  perform pg_temp.login(a);
  select cash into c0 from profiles where id = a;
  perform furniture_sell('own_plastic_chair_red');
  perform pg_temp.assert((select cash from profiles where id = a) = c0 + 2900, 'first sell pays 45%');
  h := pg_temp.hint_of('select furniture_sell(''own_plastic_chair_red'')');
  perform pg_temp.assert(h <> 'ok', 'second sell of the same chair refused: ' || h);
  perform pg_temp.assert((select cash from profiles where id = a) = c0 + 2900, 'paid only once');
  raise notice 'ok 6: furniture_sell double-sell guard';
end $$;
