-- E4 (money sinks): the weekly house bill autopays inside this suite's time travel on some weekdays (-450), so bills and tax are pinned off here.
update game_config set value = 'false'::jsonb where key in ('economy.bills_enabled', 'economy.tax_enabled');
-- Markets close at 8 PM since 20261012001550; this test buys offerings at Oba Market at any hour, so keep markets open here.
update locations set open_hour = null, close_hour = null where scene = 'market';
-- B2 Babalawo shrine (20261012001500_babalawo.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/babalawo_test.sql
-- Time moves with bl.test_offset_seconds; rolls are pinned with bl.test_rand (bl_rand).
-- Groups: 1 grants / anon / helpers private · 2 place + offerings + shop prices · 3 refusals (not here, missing items,
-- cash, switch, busy, duplicate) · 4 a service consumes cash + items, timer, ledger, receipt · 5 fail roll · 6 effects
-- (protection, home guard, vanishing, road opener, luck, fame bath, attraction / EFCC values, bad luck) · 7 durations /
-- uses expire · 8 money charm payout once per 8 h · 9 weekly demand paid / ignored / backfire · 10 cleansing ·
-- 11 RLS · 12 admin list / clear / audit · 13 ledger labels.
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

create or replace function pg_temp.qty(p_uid uuid, p_item text) returns int
language sql as $$ select coalesce((select qty from inventory where user_id = p_uid and item_id = p_item), 0); $$;

-- free, at the shrine, online
create or replace function pg_temp.at_shrine(p_uid uuid) returns void
language sql as $$
  update profiles set location_id = 'babas_shrine', travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
                      busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null,
                      jailed_until = null, jail_reason = null, hospitalized_until = null, home_visit_host_id = null,
                      last_seen = now(), rent_due_at = null
   where id = p_uid;
$$;

-- buy a service with everything it needs (cash + offerings), then finish it (time jumps past the timer)
create or replace function pg_temp.buy(p_uid uuid, p_service text, p_rand text default '0.99') returns jsonb
language plpgsql as $$
declare s shrine_services; o record;
begin
  select * into s from shrine_services where id = p_service;
  perform pg_temp.login(p_uid);
  perform pg_temp.at_shrine(p_uid);
  update profiles set cash = cash + s.price where id = p_uid;
  for o in select key, (value #>> '{}')::int as n from jsonb_each(s.offerings) loop
    perform bl_give_item(p_uid, o.key, o.n);
  end loop;
  perform shrine_start(p_service);
  perform pg_temp.advance(s.seconds + 1);
  perform set_config('bl.test_rand', p_rand, true);
  return shrine_finish();
end $$;

-- ---------- setup ----------
do $$
declare
  adm uuid := pg_temp.new_user('b2_admin@bb.bl');
  a uuid := pg_temp.new_user('b2_a@bb.bl');
  b uuid := pg_temp.new_user('b2_b@bb.bl');
  c uuid := pg_temp.new_user('b2_c@bb.bl');
  u uuid;
  i int := 0;
begin
  perform set_config('b2.adm', adm::text, true); perform set_config('b2.a', a::text, true);
  perform set_config('b2.b', b::text, true); perform set_config('b2.c', c::text, true);
  perform set_config('bl.test_offset_seconds', '0', true);
  perform set_config('bl.test_rand', '', true);
  foreach u in array array[adm, a, b, c] loop
    i := i + 1;
    update game_config set value = '"lapo"' where key = 'origin.force_next';
    perform pg_temp.login(u);
    perform create_profile_v2('B2_P' || i, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
    perform choose_start_home('ekenwan_face_me');
    perform pg_temp.at_shrine(u);
  end loop;
  update profiles set is_admin = true where id = adm;
  update profiles set created_at = now() - interval '30 days', protected_until = null, cash = 0, bank = 0 where id in (adm, a, b, c);
  perform pg_temp.cfg('shrine.enabled', 'true');
  perform pg_temp.cfg('shrine.fail_pct', '10');
  perform pg_temp.cfg('crime.steal_caught_pct', '62');
  perform pg_temp.cfg('crime.escape_caught_pct', '52');
  perform pg_temp.cfg('receipts.enabled', 'true');
  perform pg_temp.cfg('receipts.min_amount', '500000');
  perform pg_temp.cfg('clock.mode', '"real"');
end $$;

-- ---------- 1. grants ----------
do $$
declare v_rpc text;
begin
  foreach v_rpc in array array['shrine_info()', 'shrine_start(text)', 'shrine_finish()', 'shrine_status()', 'shrine_notice_seen(bigint[])',
                               'shrine_demand_pay()', 'shrine_demand_ignore()', 'admin_player_charms(uuid)', 'admin_charm_clear(uuid,bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute'), 'auth may ' || v_rpc);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v_rpc)::regprocedure), 'secdef ' || v_rpc);
  end loop;
  foreach v_rpc in array array['bl_charm_value(uuid,text,text)', 'bl_charm_active(uuid,text)', 'bl_charm_pay(uuid,bigint)',
                               'bl_charm_hype_amount(uuid,bigint)', 'bl_charm_assert_can_work(uuid)', 'bl_escape_pct_peek(uuid)',
                               'bl_escape_pct_use(uuid)', 'bl_money_charm_tick(uuid)', 'bl_shrine_resolve(bigint)', 'bl_shrine_missing(uuid,jsonb)',
                               'bl_steal_caught_pct(uuid,uuid,numeric)', 'bl_shrine_num(text,numeric)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'helper private ' || v_rpc);
  end loop;
  perform pg_temp.assert(not has_table_privilege('anon', 'public.player_charms', 'select'), 'anon no charms');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.player_charms', 'insert')
                         and not has_table_privilege('authenticated', 'public.player_charms', 'update'), 'no charm writes');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.shrine_visits', 'select'), 'visits server-only');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.shrine_notices', 'select'), 'notices server-only');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.shrine_services', 'update'), 'services read-only');
  raise notice 'ok 1: grants / helpers private';
end $$;

set local role anon;
do $$
begin
  perform pg_temp.assert(pg_temp.hint_of('select shrine_start(''protection'')') like '%permission denied%', 'anon start refused');
  perform pg_temp.assert(pg_temp.hint_of('select shrine_status()') like '%permission denied%', 'anon status refused');
  perform pg_temp.assert(pg_temp.hint_of('select count(*) from player_charms') <> 'ok', 'anon table refused');
end $$;
reset role;

-- ---------- 2. place, offerings, shop prices ----------
do $$
declare
  a uuid := current_setting('b2.a')::uuid;
  r jsonb;
  n int;
begin
  perform pg_temp.assert((select active and scene = 'shrine' and 'babalawo' = any (actions) and name = 'Baba''s Shrine'
                            from locations where id = 'babas_shrine'), 'new shrine is a public place');
  perform pg_temp.assert(not (select active from locations where id = 'baba_shrine'), 'old shrine hidden');
  perform pg_temp.assert((select count(*) from shrine_services where active) = 10, '10 services');
  perform pg_temp.assert((select string_agg(id || '=' || price, ',' order by sort) from items where category = 'offering')
    = 'kola_nut=240,alligator_pepper=600,cowries=2400,white_cloth=3600,palm_oil=4200,schnapps=7800,white_chicken=9600,goat=102000,cow=1440000',
    'offering prices exactly as the plan');
  perform pg_temp.assert((select bool_and(sold_at = '{oba_market}') from items where category = 'offering'), 'sold at Oba Market');
  -- service prices + offerings from the plan
  perform pg_temp.assert((select count(*) from shrine_services s join (values
      ('consultation', 50000, '{"kola_nut": 1}'), ('road_opener', 250000, '{"kola_nut": 2, "palm_oil": 1}'),
      ('protection', 420000, '{"schnapps": 1, "white_chicken": 1}'), ('vanishing', 750000, '{"goat": 2, "cowries": 1}'),
      ('home_guard', 300000, '{"white_cloth": 1, "palm_oil": 1}'), ('attraction', 150000, '{"alligator_pepper": 5}'),
      ('fame_bath', 800000, '{"schnapps": 2}'), ('efcc_blindfold', 1200000, '{"goat": 2}'),
      ('money_charm', 3000000, '{"cow": 2, "schnapps": 1, "white_cloth": 1}'), ('cleansing', 50000, '{"white_chicken": 1}')
    ) v(id, price, offerings) on v.id = s.id and v.price = s.price and v.offerings::jsonb = s.offerings) = 10, 'service prices + offerings');
  -- buying a cow at Oba Market: N1.44M cash, receipt
  perform pg_temp.login(a);
  update profiles set location_id = 'oba_market', cash = 1500000 where id = a;
  r := shop_buy('cow', 1);
  perform pg_temp.assert((select cash from profiles where id = a) = 60000, 'cow costs N1,440,000');
  perform pg_temp.assert(r ? 'receipt', 'cow purchase has a receipt');
  perform pg_temp.assert(pg_temp.qty(a, 'cow') = 1, 'cow in the Bag');
  perform pg_temp.assert((select kind from jsonb_to_recordset(get_my_state()->'inventory') as x(id text, kind text) where id = 'cow') = 'keep',
                         'offerings are kept, not used');
  update profiles set cash = 0 where id = a;
  delete from inventory where user_id = a;
  -- the interior: 10 shrine cards over the zones, Baba's own zones replace the type's
  perform pg_temp.at_shrine(a);
  r := place_interior('babas_shrine');
  select count(*) into n from jsonb_array_elements(r->'zones') z, jsonb_array_elements(z->'actions') x where x->>'kind' = 'shrine';
  perform pg_temp.assert(n = 10, '10 shrine cards: ' || n);
  perform pg_temp.assert((select count(*) from jsonb_array_elements(r->'zones') z where z->>'key' in ('hut', 'altar', 'fire', 'courtyard')) = 4, 'four zones');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r->'zones') z, jsonb_array_elements(z->'actions') x where x->>'ref' = 'shrine_consult'),
                         'the old cheap consult card is not at the new shrine');
  perform pg_temp.assert((select x->>'cost' from jsonb_array_elements(r->'zones') z, jsonb_array_elements(z->'actions') x where x->>'ref' = 'protection') = '420000',
                         'card price');
  r := shrine_info();
  perform pg_temp.assert(jsonb_array_length(r->'services') = 10 and (r->>'here')::boolean, 'shrine_info lists services here');
  raise notice 'ok 2: place / offerings / prices';
end $$;

-- ---------- 3. refusals ----------
do $$
declare a uuid := current_setting('b2.a')::uuid;
begin
  perform pg_temp.login(a);
  perform pg_temp.at_shrine(a);
  update profiles set cash = 1000000 where id = a;
  -- missing offerings: nothing taken
  perform pg_temp.assert(pg_temp.hint_of('select shrine_start(''protection'')') = 'missing_offerings', 'missing items refused');
  perform bl_give_item(a, 'schnapps', 1);
  perform pg_temp.assert(pg_temp.hint_of('select shrine_start(''protection'')') = 'missing_offerings', 'still missing the chicken');
  perform pg_temp.assert((select cash from profiles where id = a) = 1000000 and pg_temp.qty(a, 'schnapps') = 1, 'nothing taken on refusal');
  perform bl_give_item(a, 'white_chicken', 1);
  -- cash
  update profiles set cash = 419999 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select shrine_start(''protection'')') = 'not_enough_cash', 'cash refused');
  perform pg_temp.assert(pg_temp.qty(a, 'white_chicken') = 1, 'items kept when cash short');
  update profiles set cash = 420000 where id = a;
  -- not at the shrine
  update profiles set location_id = 'oba_market' where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select shrine_start(''protection'')') = 'not_here', 'only at the shrine');
  perform pg_temp.at_shrine(a);
  -- switch
  perform pg_temp.cfg('shrine.enabled', 'false');
  perform pg_temp.assert(pg_temp.hint_of('select shrine_start(''protection'')') = 'disabled', 'switch off');
  perform pg_temp.cfg('shrine.enabled', 'true');
  -- busy
  update profiles set busy_until = bl_now() + interval '30 seconds', busy_label = 'Something' where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select shrine_start(''protection'')') = 'busy', 'busy refused');
  perform pg_temp.at_shrine(a);
  perform pg_temp.assert(pg_temp.hint_of('select shrine_start(''nope'')') = 'bad_service', 'unknown service');
  update profiles set cash = 0 where id = a;
  delete from inventory where user_id = a;
  raise notice 'ok 3: refusals';
end $$;

-- ---------- 4. a service consumes cash + offerings ----------
do $$
declare
  a uuid := current_setting('b2.a')::uuid;
  r jsonb;
  v_charm player_charms;
begin
  perform pg_temp.login(a);
  perform pg_temp.at_shrine(a);
  update profiles set cash = 500000 where id = a;
  perform bl_give_item(a, 'schnapps', 2);
  perform bl_give_item(a, 'white_chicken', 1);
  r := shrine_start('protection');
  perform pg_temp.assert((select cash from profiles where id = a) = 80000, 'N420,000 taken from cash');
  perform pg_temp.assert(pg_temp.qty(a, 'schnapps') = 1 and pg_temp.qty(a, 'white_chicken') = 0, 'offerings consumed (1 schnapps + 1 chicken)');
  perform pg_temp.assert(r ? 'receipt' is false, 'no receipt under N500k');
  perform pg_temp.assert((select busy_label from profiles where id = a) = 'With Baba: Protection charm', 'busy label');
  perform pg_temp.assert((select bl_ledger_label(reason, meta) from ledger where user_id = a order by id desc limit 1) = 'Baba: Protection charm', 'ledger label');
  perform pg_temp.assert(pg_temp.hint_of('select shrine_start(''cleansing'')') = 'busy', 'one at a time');
  perform pg_temp.assert(pg_temp.hint_of('select shrine_finish()') = 'not_yet', 'not before the timer');
  perform pg_temp.advance(13);
  perform set_config('bl.test_rand', '0.5', true);
  r := shrine_finish();
  perform pg_temp.assert(r->>'status' = 'done', 'protection works: ' || r::text);
  select * into v_charm from player_charms where user_id = a and kind = 'protection' and status = 'active';
  perform pg_temp.assert(v_charm.id is not null and abs(extract(epoch from v_charm.expires_at - bl_now()) - 259200) < 5, 'lasts 3 days');
  perform pg_temp.assert((select busy_until from profiles where id = a) is null, 'timer cleared');
  perform pg_temp.assert(pg_temp.hint_of('select shrine_finish()') = 'no_visit', 'nothing left to finish');
  -- the same charm twice is refused while it works
  update profiles set cash = 420000 where id = a;
  perform bl_give_item(a, 'white_chicken', 1);
  perform pg_temp.assert(pg_temp.hint_of('select shrine_start(''protection'')') = 'already_active', 'duplicate refused');
  -- big payment gets a receipt (fame bath N800k)
  update profiles set cash = 800000 where id = a;
  perform bl_give_item(a, 'schnapps', 1);
  r := shrine_start('fame_bath');
  perform pg_temp.assert(r ? 'receipt' and r->'receipt'->>'item_name' = 'Baba: Fame bath', 'receipt for N800k');
  perform pg_temp.advance(16);
  perform set_config('bl.test_rand', '0.5', true);
  perform shrine_finish();
  raise notice 'ok 4: service consumes cash + offerings';
end $$;

-- ---------- 5. fail roll ----------
do $$
declare
  b uuid := current_setting('b2.b')::uuid;
  r jsonb;
begin
  -- rand 0.05 -> 5 < 10 % -> fails: money + offerings gone, no charm
  r := pg_temp.buy(b, 'road_opener', '0.05');
  perform pg_temp.assert(r->>'status' = 'failed' and length(r->>'line') > 10, 'charm failed with Baba''s line');
  perform pg_temp.assert((select cash from profiles where id = b) = 0 and pg_temp.qty(b, 'kola_nut') = 0 and pg_temp.qty(b, 'palm_oil') = 0,
                         'money + offerings gone');
  perform pg_temp.assert(not bl_charm_active(b, 'road_opener'), 'no charm after a fail');
  perform pg_temp.assert(exists (select 1 from shrine_notices where user_id = b and kind = 'charm_failed'), 'fail notice');
  -- rand 0.10 -> 10 is not < 10 -> works
  r := pg_temp.buy(b, 'road_opener', '0.10');
  perform pg_temp.assert(r->>'status' = 'done', 'rand at the edge works');
  -- the service's own fail chance (consultation 0 %) wins over shrine.fail_pct
  r := pg_temp.buy(b, 'consultation', '0');
  perform pg_temp.assert(r->>'status' = 'done', 'consultation never fails');
  -- shrine.fail_pct 100 -> always fails
  perform pg_temp.cfg('shrine.fail_pct', '100');
  r := pg_temp.buy(b, 'attraction', '0.99');
  perform pg_temp.assert(r->>'status' = 'failed', 'fail_pct 100 always fails');
  perform pg_temp.cfg('shrine.fail_pct', '10');
  perform set_config('bl.test_rand', '', true);
  raise notice 'ok 5: fail roll';
end $$;

-- ---------- 6. effects ----------
do $$
declare
  a uuid := current_setting('b2.a')::uuid;   -- protection + fame bath (group 4)
  b uuid := current_setting('b2.b')::uuid;   -- road opener + luck (group 5)
  c uuid := current_setting('b2.c')::uuid;
  v_case jail_cases;
  r jsonb;
  v_track text;
  v_pay0 bigint;
  v_pay1 bigint;
  v_club text;
  v_kind text;
begin
  -- protection: pickpocket caught 62 -> 45 (thief); skill hook still subtracts
  perform pg_temp.assert(bl_steal_caught_pct(c, b, 0) = 62, 'no charm: 62');
  perform pg_temp.assert(bl_steal_caught_pct(a, b, 0) = 45, 'protection: 45');
  perform pg_temp.assert(bl_steal_caught_pct(a, b, 5) = 40, 'skill hook stays');
  -- home guard on the victim: +50 % relative, capped at 95
  r := pg_temp.buy(c, 'home_guard', '0.5');
  perform pg_temp.assert(r->>'status' = 'done', 'home guard bought');
  perform pg_temp.assert(bl_steal_caught_pct(b, c, 0) = 93, 'thief vs guarded victim: 62 x 1.5 = 93: ' || bl_steal_caught_pct(b, c, 0));
  perform pg_temp.assert(bl_steal_caught_pct(a, c, 0) = 67.5, 'protected thief vs guard: 45 x 1.5');
  perform pg_temp.cfg('crime.steal_caught_pct', '80');
  perform pg_temp.assert(bl_steal_caught_pct(b, c, 0) = 95, 'capped at 95');
  perform pg_temp.cfg('crime.steal_caught_pct', '62');
  -- road opener + Baba's luck: +20 % + 5 % job pay
  perform pg_temp.assert(bl_charm_pay(c, 10000) = 10000, 'no charm: same pay');
  perform pg_temp.assert(bl_charm_pay(b, 10000) = 12500, 'road opener + luck: +25 %: ' || bl_charm_pay(b, 10000));
  perform pg_temp.assert((select data ? 'reading' from player_charms where user_id = b and kind = 'luck' and status = 'active'), 'the reading is kept');
  -- a real shift: c (no charm) vs b (charms), same job and needs
  select id into v_track from career_tracks where id = 'trade';
  update profiles set job_id = v_track, job_level = 1, job_shifts_today = 0, job_shift_day = null, job_shift_ends_at = null,
                      location_id = 'oba_market', hunger = 100, energy = 100, hygiene = 100, stress = 0, busy_until = null
   where id in (b, c);
  perform pg_temp.login(c);
  v_pay0 := (work_shift()->>'pay')::bigint;
  perform pg_temp.login(b);
  v_pay1 := (work_shift()->>'pay')::bigint;
  perform pg_temp.assert(v_pay0 > 0 and v_pay1 = (round(v_pay0 * 1.25 / 10.0) * 10)::bigint, format('shift pay +25 %%: %s -> %s', v_pay0, v_pay1));
  update profiles set job_shift_ends_at = null, busy_until = null, busy_label = null where id in (b, c);
  -- fame bath: club hype amount +50 %
  perform pg_temp.assert(bl_charm_hype_amount(a, 100000) = 150000 and bl_charm_hype_amount(c, 100000) = 100000, 'fame bath +50 %');
  select id into v_club from locations where scene = 'club' and active order by sort limit 1;
  select kind into v_kind from hype_templates where active and kind = 'spray' limit 1;
  r := bl_hype_announce(a, v_club, v_kind, 100000, 1, true);
  perform pg_temp.assert(r is not null and (r->>'amount')::bigint = 150000, 'announced amount x1.5: ' || coalesce(r::text, 'null'));
  -- attraction / EFCC blindfold values for the coming features
  r := pg_temp.buy(c, 'attraction', '0.5');
  r := pg_temp.buy(c, 'efcc_blindfold', '0.5');
  perform pg_temp.assert(bl_charm_value(c, 'attraction') = 20 and bl_charm_value(c, 'efcc_blindfold') = 15, 'stored values readable');
  perform pg_temp.assert(bl_charm_value(a, 'attraction') is null, 'null without the charm');
  -- vanishing: escape caught 52 -> 30 for the next 3 escapes
  r := pg_temp.buy(c, 'vanishing', '0.5');
  perform pg_temp.assert((select uses_left from player_charms where user_id = c and kind = 'vanishing' and status = 'active') = 3, '3 uses');
  insert into jail_cases (user_id, reason, location_id, bail_amount, jail_seconds, jail_until, created_at)
  values (c, 'Test case', 'oba_market', 20000000, 45, bl_now() + interval '45 seconds', bl_now()) returning * into v_case;
  update profiles set jailed_until = v_case.jail_until where id = c;
  perform pg_temp.assert((bl_crime_case_json(v_case)->>'escape_caught_pct')::numeric = 30, 'popup shows 30 %');
  perform pg_temp.login(c);
  perform set_config('bl.test_rand', '0.4', true);   -- 40: caught at 52 %, free at 30 %
  r := jail_case_escape();
  perform pg_temp.assert((r->>'escaped')::boolean, 'escaped thanks to the charm');
  perform pg_temp.assert((select uses_left from player_charms where user_id = c and kind = 'vanishing') = 2, 'one use spent');
  -- two more escapes (one caught at rand 0.1) use the rest
  insert into jail_cases (user_id, reason, bail_amount, jail_seconds, jail_until, created_at)
  values (c, 'Test case 2', 20000000, 45, bl_now() + interval '45 seconds', bl_now());
  update profiles set jailed_until = bl_now() + interval '45 seconds' where id = c;
  perform set_config('bl.test_rand', '0.1', true);
  r := jail_case_escape();
  perform pg_temp.assert(not (r->>'escaped')::boolean, 'caught at 10 < 30');
  perform set_config('bl.test_rand', '0.9', true);
  r := jail_case_escape();
  perform pg_temp.assert((r->>'escaped')::boolean, 'third escape');
  perform pg_temp.assert((select status from player_charms where user_id = c and kind = 'vanishing') = 'used', 'used up after 3 escapes');
  perform pg_temp.assert(bl_escape_pct_peek(c) = 52, 'back to 52');
  perform set_config('bl.test_rand', '', true);
  raise notice 'ok 6: effects';
end $$;

-- ---------- 7. durations / uses expire ----------
do $$
declare
  a uuid := current_setting('b2.a')::uuid;
  b uuid := current_setting('b2.b')::uuid;
  r jsonb;
begin
  perform pg_temp.advance(86400);        -- luck (1 day) over
  perform pg_temp.assert(bl_charm_pay(b, 10000) = 12000, 'luck gone after a day, road opener stays');
  perform pg_temp.advance(2 * 86400);    -- protection + fame bath (3 days) over
  perform pg_temp.assert(bl_steal_caught_pct(a, b, 0) = 62, 'protection gone after 3 days');
  perform pg_temp.assert(bl_charm_hype_amount(a, 100000) = 100000, 'fame bath gone');
  -- buyable again
  r := pg_temp.buy(a, 'protection', '0.5');
  perform pg_temp.assert(r->>'status' = 'done' and bl_steal_caught_pct(a, b, 0) = 45, 'protection again after expiry');
  perform pg_temp.advance(4 * 86400);    -- road opener (7 days) over
  perform pg_temp.assert(bl_charm_pay(b, 10000) = 10000, 'road opener gone after 7 days');
  perform pg_temp.login(a);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(shrine_status()->'charms') x where x->>'kind' = 'protection'),
                         'expired charms leave the list');
  raise notice 'ok 7: durations / uses expire';
end $$;

-- ---------- 8. money charm payout ----------
do $$
declare
  a uuid := current_setting('b2.a')::uuid;
  r jsonb;
  v_cash bigint;
  v_got bigint;
begin
  update profiles set cash = 0 where id = a;
  r := pg_temp.buy(a, 'money_charm', '0.5');
  perform pg_temp.assert(r->>'status' = 'done', 'money charm bought');
  perform pg_temp.assert((select cash from profiles where id = a) = 0 and pg_temp.qty(a, 'cow') = 0, 'N3M + 2 cows taken');
  perform pg_temp.assert(exists (select 1 from receipts where user_id = a and item_name = 'Baba: Money charm' and amount = 3000000), 'receipt N3M');
  -- only one money charm
  update profiles set cash = 3000000 where id = a;
  perform bl_give_item(a, 'cow', 2); perform bl_give_item(a, 'schnapps', 1); perform bl_give_item(a, 'white_cloth', 1);
  perform pg_temp.assert(pg_temp.hint_of('select shrine_start(''money_charm'')') = 'already_active', 'only one money charm');
  update profiles set cash = 0 where id = a;
  delete from inventory where user_id = a;
  -- 7 h later: nothing yet
  perform pg_temp.advance(7 * 3600);
  r := shrine_status();
  perform pg_temp.assert(jsonb_array_length(r->'notices') = 0 and (select cash from profiles where id = a) = 0, 'no payout before 8 h');
  -- 8 h: one payout between N150k and N300k, once
  perform pg_temp.advance(3600);
  perform set_config('bl.test_rand', '0.5', true);
  r := shrine_status();
  v_got := (select cash from profiles where id = a);
  perform pg_temp.assert(v_got between 150000 and 300000 and v_got % 1000 = 0, 'payout in range: ' || v_got);
  perform pg_temp.assert(jsonb_array_length(r->'notices') = 1 and r->'notices'->0->>'kind' = 'blessing'
                         and (r->'notices'->0->>'amount')::bigint = v_got, 'blessing popup');
  perform pg_temp.assert((select bl_ledger_label(reason, meta) from ledger where user_id = a order by id desc limit 1) = 'Baba''s blessing', 'ledger label');
  r := shrine_status();
  r := shrine_info();
  perform pg_temp.assert((select cash from profiles where id = a) = v_got, 'no double payout in the same 8 h');
  perform shrine_notice_seen(array(select (x->>'id')::bigint from jsonb_array_elements(shrine_status()->'notices') x));
  perform pg_temp.assert(jsonb_array_length(shrine_status()->'notices') = 0, 'popup seen');
  -- payout bounds respected at both ends
  perform pg_temp.advance(8 * 3600);
  perform set_config('bl.test_rand', '0', true);
  perform shrine_status();
  perform pg_temp.assert((select cash from profiles where id = a) = v_got + 150000, 'min payout at rand 0');
  perform pg_temp.advance(8 * 3600);
  perform set_config('bl.test_rand', '0.999999', true);
  perform shrine_status();
  perform pg_temp.assert((select cash from profiles where id = a) = v_got + 450000, 'max payout at rand ~1');
  perform pg_temp.assert(not exists (select 1 from shrine_notices where user_id = a and seen_at is null and kind = 'blessing' and amount <= 0), 'amounts positive');
  perform set_config('bl.test_rand', '', true);
  raise notice 'ok 8: money charm payout once per 8 h';
end $$;

-- ---------- 9. weekly demand: paid, ignored, backfire ----------
do $$
declare
  a uuid := current_setting('b2.a')::uuid;
  b uuid := current_setting('b2.b')::uuid;
  r jsonb;
  m player_charms;
  v_cash bigint;
begin
  perform pg_temp.login(a);
  select * into m from player_charms where user_id = a and kind = 'money_charm' and status = 'active';
  -- jump to the demand (7 days after purchase)
  perform pg_temp.advance(extract(epoch from (m.data->>'demand_due_at')::timestamptz - bl_now()) + 60);
  r := shrine_status();
  perform pg_temp.assert(r->'demand' is not null and r->'demand'->>'cash' = '300000' and r->'demand'->>'goats' = '1', 'Baba is calling');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'baba_calling'), 'calling alert');
  -- payouts stop while the call is open
  v_cash := (select cash from profiles where id = a);
  perform pg_temp.advance(9 * 3600);
  perform shrine_status();
  perform pg_temp.assert((select cash from profiles where id = a) = v_cash, 'no payout while Baba waits');
  -- paying needs the goat + cash
  update profiles set cash = 299999 where id = a;
  perform pg_temp.assert(pg_temp.hint_of('select shrine_demand_pay()') = 'missing_offerings', 'needs a goat');
  perform bl_give_item(a, 'goat', 1);
  perform pg_temp.assert(pg_temp.hint_of('select shrine_demand_pay()') = 'not_enough_cash', 'needs N300k');
  update profiles set cash = 300000 where id = a;
  r := shrine_demand_pay();
  perform pg_temp.assert((select cash from profiles where id = a) = 0 and pg_temp.qty(a, 'goat') = 0, 'goat + N300k taken');
  perform pg_temp.assert(shrine_status()->'demand' = 'null'::jsonb or shrine_status()->'demand' is null, 'call answered');
  perform pg_temp.assert(pg_temp.hint_of('select shrine_demand_pay()') = 'no_demand', 'nothing more to pay');
  perform pg_temp.assert((select bl_ledger_label(reason, meta) from ledger where user_id = a and reason = 'shrine' order by id desc limit 1) = 'Baba: weekly demand', 'ledger label');
  -- next due = day 14 = the charm's end: no second call; the charm ends quietly at day 14
  perform pg_temp.advance(8 * 86400);
  r := shrine_status();
  perform pg_temp.assert((select status from player_charms where id = m.id) = 'expired', 'money charm ends after 14 days');
  perform pg_temp.assert(r->'demand' is null or r->'demand' = 'null'::jsonb, 'no call at the end');

  -- b: a money charm that gets ignored -> backfire
  r := pg_temp.buy(b, 'money_charm', '0.5');
  perform pg_temp.login(b);
  select * into m from player_charms where user_id = b and kind = 'money_charm' and status = 'active';
  perform pg_temp.advance(extract(epoch from (m.data->>'demand_due_at')::timestamptz - bl_now()) + 60);
  r := shrine_status();
  perform pg_temp.assert(r->'demand' is not null, 'b called');
  r := shrine_demand_ignore();
  perform pg_temp.assert((shrine_status()->'demand'->>'ignored')::boolean, 'ignored is remembered');
  update profiles set cash = 1000001 where id = b;
  perform pg_temp.advance(23 * 3600);
  perform shrine_status();
  perform pg_temp.assert((select status from player_charms where id = m.id) = 'active', 'still time at 23 h');
  perform pg_temp.advance(3600);
  r := shrine_status();
  perform pg_temp.assert((select status from player_charms where id = m.id) = 'backfired', 'backfire after 24 h');
  perform pg_temp.assert((select cash from profiles where id = b) = 500001, 'half the cash lost: ' || (select cash from profiles where id = b));
  perform pg_temp.assert((select bl_ledger_label(reason, meta) from ledger where user_id = b and reason = 'shrine_backfire' order by id desc limit 1)
                         = 'Baba: charm backfired', 'backfire ledger');
  perform pg_temp.assert(bl_charm_active(b, 'madness') and bl_charm_active(b, 'bad_luck'), 'madness + bad luck');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(r->'notices') x where x->>'kind' = 'backfire'), 'backfire popup');
  -- idempotent: another tick does nothing more
  perform shrine_status();
  perform pg_temp.assert((select cash from profiles where id = b) = 500001 and (select count(*) from player_charms where user_id = b and kind = 'madness') = 1,
                         'backfire happens once');
  -- madness: no shifts; bad luck: +10 pts caught, -10 % pay
  update profiles set job_id = 'trade', job_level = 1, job_shifts_today = 0, job_shift_day = null, job_shift_ends_at = null, location_id = 'oba_market',
                      hunger = 100, energy = 100, busy_until = null where id = b;
  perform pg_temp.assert(pg_temp.hint_of('select work_shift()') = 'madness', 'madness blocks shifts');
  perform pg_temp.assert(bl_steal_caught_pct(b, a, 0) = 72, 'bad luck +10 pts: ' || bl_steal_caught_pct(b, a, 0));
  perform pg_temp.assert(bl_charm_pay(b, 10000) = 9000, 'bad luck -10 % pay');
  perform pg_temp.assert(bl_escape_pct_peek(b) = 62, 'bad luck escape +10');
  -- madness lasts one game day (24 h on the real clock), bad luck 3 days
  perform pg_temp.assert(abs(extract(epoch from (select expires_at from player_charms where user_id = b and kind = 'madness') - bl_now()) - 86400) < 5, 'madness 1 game day');
  perform pg_temp.assert(abs(extract(epoch from (select expires_at from player_charms where user_id = b and kind = 'bad_luck') - bl_now()) - 3 * 86400) < 5, 'bad luck 3 days');
  -- a new money charm is allowed again after the backfire
  perform pg_temp.assert(not exists (select 1 from player_charms where user_id = b and kind = 'money_charm' and status = 'active'), 'no active money charm');
  raise notice 'ok 9: weekly demand / ignore / backfire';
end $$;

-- ---------- 10. cleansing ----------
do $$
declare
  b uuid := current_setting('b2.b')::uuid;
  r jsonb;
begin
  r := pg_temp.buy(b, 'cleansing', '0');
  perform pg_temp.assert(r->>'status' = 'done' and r->>'line' like '%washed away%', 'cleansing done: ' || r::text);
  perform pg_temp.assert(not bl_charm_active(b, 'madness') and not bl_charm_active(b, 'bad_luck'), 'curses removed');
  perform pg_temp.assert(bl_steal_caught_pct(b, current_setting('b2.a')::uuid, 0) = 62 and bl_charm_pay(b, 10000) = 10000, 'odds + pay normal again');
  perform pg_temp.assert(pg_temp.hint_of('select work_shift()') <> 'madness', 'can work again');
  perform pg_temp.assert(pg_temp.qty(b, 'white_chicken') = 0, 'chicken used');
  update profiles set job_shift_ends_at = null, busy_until = null, busy_label = null where id = b;
  raise notice 'ok 10: cleansing';
end $$;

-- ---------- 11. RLS ----------
do $$
declare
  a uuid := current_setting('b2.a')::uuid;
  c uuid := current_setting('b2.c')::uuid;
  n_a int; n_mine int; n_other int;
begin
  select count(*) into n_a from player_charms where user_id = a;
  perform pg_temp.login(c);
  set local role authenticated;
  select count(*) into n_mine from player_charms;
  select count(*) into n_other from player_charms where user_id <> c;
  reset role;
  perform pg_temp.assert(n_a > 0 and n_other = 0 and n_mine = (select count(*) from player_charms where user_id = c), 'own charms only');
  perform pg_temp.login(c);
  set local role authenticated;
  perform pg_temp.assert(pg_temp.hint_of(format('insert into player_charms (user_id, kind) values (%L, ''protection'')', c)) <> 'ok', 'no inserts');
  perform pg_temp.assert(pg_temp.hint_of('update shrine_services set price = 1') <> 'ok', 'no service edits');
  reset role;
  raise notice 'ok 11: RLS';
end $$;

-- ---------- 12. admin ----------
do $$
declare
  adm uuid := current_setting('b2.adm')::uuid;
  c uuid := current_setting('b2.c')::uuid;
  r jsonb;
  v_id bigint;
begin
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_player_charms(%L::uuid)', c)) <> 'ok', 'players can''t use the admin list');
  perform pg_temp.login(adm);
  r := admin_player_charms(c);
  perform pg_temp.assert(jsonb_array_length(r->'rows') >= 3, 'admin sees the charms');
  select id into v_id from player_charms where user_id = c and kind = 'attraction' and status = 'active';
  r := admin_charm_clear(c, v_id);
  perform pg_temp.assert((r->>'cleared')::int = 1 and not bl_charm_active(c, 'attraction'), 'one charm cleared');
  r := admin_charm_clear(c, null);
  perform pg_temp.assert(not exists (select 1 from player_charms where user_id = c and status = 'active'), 'all cleared');
  perform pg_temp.assert((select count(*) from admin_audit where admin_id = adm and action = 'charm_clear' and target_user = c) = 2, 'audited');
  -- Content -> Shrine services is editable
  r := admin_row_upsert('shrine_services', '{"id": "protection", "price": 430000}');
  perform pg_temp.assert((select price from shrine_services where id = 'protection') = 430000, 'admin edits a service');
  raise notice 'ok 12: admin';
end $$;

-- ---------- 13. labels ----------
do $$
begin
  perform pg_temp.assert(bl_ledger_label('shrine', '{"service_name": "Road opener"}') = 'Baba: Road opener', 'shrine label');
  perform pg_temp.assert(bl_ledger_label('shrine_blessing', '{}') = 'Baba''s blessing', 'blessing label');
  perform pg_temp.assert(bl_ledger_label('steal_gain', '{"place": "Oba Market"}') = 'Pickpocketed · Oba Market', 'older labels intact');
  raise notice 'ok 13: labels';
end $$;
