-- "Fix it" update (migrations 20261110000100 and up). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/fixit_test.sql
-- One group per item with server logic (the numbers in the headers are the item numbers):
-- 3 club spray alert prefs · 4 beds · 5 gang boss hand-back · 6 land levy · 7 laptops · 8 delete account ·
-- 9 phone banking · 10 primary car · 11 balance guards · 12 money history
create or replace function pg_temp.fx_hint(p_sql text) returns text
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

create or replace function pg_temp.fx_make(p_name text, p_cash bigint default 1000000, p_bank bigint default 1000000) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@fx.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  update game_config set value = 'false' where key = 'stories.push_enabled';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  update profiles set last_seen = now() - interval '1 hour', transfer_trusted = true, bank = p_bank, cash = p_cash,
         protected_until = null where id = v;
  return v;
end $$;

-- ---------- 3. Club spray alerts ----------
do $$
declare a uuid := pg_temp.fx_make('FxAda'); b uuid := pg_temp.fx_make('FxBayo'); r jsonb; v_club text; n int;
begin
  perform pg_temp.login(a);
  r := club_alert_prefs_get();
  perform pg_temp.assert((r->>'toasts')::boolean and not (r->>'strip')::boolean and not (r->>'push')::boolean, 'defaults: toasts on, strip off, push off');
  r := club_alert_prefs_set('{"push": true}');
  perform pg_temp.assert((r->>'push')::boolean and (r->>'toasts')::boolean, 'partial set');
  perform pg_temp.assert(pg_temp.fx_hint($q$select club_alert_prefs_set('{"nope": true}')$q$) = 'bad_value', 'unknown switch refused');
  perform pg_temp.assert(pg_temp.fx_hint($q$select club_alert_prefs_set('{"push": 1}')$q$) = 'bad_value', 'non-boolean refused');
  -- B cannot see A's row
  perform pg_temp.login(b);
  perform pg_temp.assert((club_alert_prefs_get()->>'push')::boolean = false, 'B has own defaults');
  set local role authenticated;
  select count(*) into n from club_alert_prefs;
  reset role;
  perform pg_temp.assert(n = 0, 'RLS: B reads no other row');
  raise notice 'ok 3: club spray alert prefs';
end $$;

-- ---------- 4. Beds: every sleeping piece works, also a second bed in an extension room ----------
-- (the bug was in the client: the Sim always walked to the FIRST bed, not the one tapped; the server never cared where a bed stood)
do $$
declare v uuid := pg_temp.fx_make('FxBedder', 50000000, 0); r record; res jsonb; n int := 0;
begin
  perform pg_temp.login(v);
  insert into player_house_upgrades(user_id, upgrade_id, start_home, done_at, source)
    values (v, 'ext_bedroom', (select start_home from profiles where id = v), now(), 'admin');
  perform bl_furniture_materialize(v);
  for r in select id from furniture where 'sleep' = any(activities) and active order by price loop
    delete from player_furniture where user_id = v and furniture_id = r.id;
    insert into player_furniture(user_id, furniture_id, slot, source, qty) values (v, r.id, null, 'buy', 1);
    perform bl_furniture_materialize(v);
    perform pg_temp.assert((bl_furniture_for(v, 'sleep')->>'owned')::boolean, 'bed ' || r.id || ' hosts sleep');
    perform pg_temp.assert((bl_furniture_for(v, 'nap')->>'owned')::boolean, 'bed ' || r.id || ' hosts nap');
    n := n + 1;
    delete from player_furniture where user_id = v and furniture_id = r.id;
    delete from player_house_furniture where owner_id = v and furniture_key like 'own\_' || r.id || '%';
  end loop;
  perform pg_temp.assert(n >= 8, 'all bed kinds checked');
  -- a second bed standing in the extension room: sleep works and the room's bonus applies
  insert into player_furniture(user_id, furniture_id, slot, source, qty) values (v, 'bed_single', null, 'buy', 1);
  perform bl_furniture_materialize(v);
  res := furniture_place('own_bed_single', 3.2, 7.4, 0);
  perform pg_temp.assert(res->>'stored' = 'false', 'bed placed in the extension room');
  res := do_activity('sleep');
  perform pg_temp.assert((res->'effects'->>'energy')::numeric = 85 and (res->'effects'->>'stress')::numeric < -20, 'sleep works, extension room bonus on');
  raise notice 'ok 4: beds';
end $$;

-- ---------- 5. Gang Boss hand-back ----------
do $$
declare a uuid := pg_temp.fx_make('FxBossA'); b uuid := pg_temp.fx_make('FxBossB'); c uuid := pg_temp.fx_make('FxBossC');
        v_crew bigint; r jsonb; v_admin uuid := pg_temp.fx_make('FxBossAdm');
begin
  update profiles set created_at = now() - interval '30 days' where id in (a, b, c, v_admin);
  perform pg_temp.login(a);
  r := crew_create('Fixit Boys', 'FXB', '#aa3322', '🌙');
  select crew_id into v_crew from crew_members where user_id = a;
  perform bl_crew_add_member(v_crew, b, 'member');
  perform bl_crew_add_member(v_crew, c, 'member');
  -- nothing handed over yet
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_handback()') <> 'ok', 'a founder has nothing to hand back');
  perform pg_temp.assert(not (crew_boss_state()->>'can_handback')::boolean, 'state: no handback for the founder');
  -- A hands the gang to B by mistake
  perform crew_transfer(b);
  perform pg_temp.assert((select rank from crew_members where user_id = b) = 'boss' and (select rank from crew_members where user_id = a) = 'lieutenant', 'B is Boss');
  perform pg_temp.assert((crew_boss_state()->>'can_request')::boolean, 'state: A may ask');
  -- C (random member) can do nothing
  perform pg_temp.login(c);
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_request()') = 'not_previous_boss', 'C cannot ask');
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_handback()') <> 'ok', 'C cannot hand back');
  -- A asks, B declines
  perform pg_temp.login(a);
  perform crew_boss_request();
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_request()') = 'pending', 'one request at a time');
  perform pg_temp.login(b);
  perform pg_temp.assert((crew_boss_state()->'request'->>'to_me')::boolean, 'B sees the request');
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_respond(true)') <> 'ok', 'A cannot answer their own request');
  perform pg_temp.login(b);
  perform crew_boss_respond(false);
  perform pg_temp.assert((select rank from crew_members where user_id = b) = 'boss', 'declined: B stays Boss');
  -- A asks again, B accepts
  perform pg_temp.login(a);
  perform crew_boss_request();
  perform pg_temp.login(b);
  perform crew_boss_respond(true);
  perform pg_temp.assert((select rank from crew_members where user_id = a) = 'boss' and (select rank from crew_members where user_id = b) = 'lieutenant', 'accepted: A is Boss again');
  -- late request is refused: hand over again, age the handover past 24 h
  perform pg_temp.login(a);
  perform crew_transfer(b);
  update crew_boss_log set created_at = now() - interval '25 hours' where crew_id = v_crew and kind = 'transfer';
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_request()') = 'too_late', 'after 24 h the request is refused');
  -- but B can hand it back any time
  perform pg_temp.login(b);
  perform pg_temp.assert((crew_boss_state()->>'can_handback')::boolean, 'state: B may hand back');
  perform crew_boss_handback();
  perform pg_temp.assert((select rank from crew_members where user_id = a) = 'boss' and (select rank from crew_members where user_id = b) = 'lieutenant', 'handed back');
  perform pg_temp.assert(pg_temp.fx_hint('select crew_boss_handback()') <> 'ok', 'hand back once');
  perform pg_temp.assert((select count(*) from crew_boss_log where crew_id = v_crew) >= 7, 'every step is in the log');
  -- admin sets the Boss
  update profiles set is_admin = false where is_admin;
  update profiles set is_admin = true where id = v_admin;
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.fx_hint(format('select admin_crew_set_boss(%L, %s, ''x'')', c, v_crew)) <> 'ok', 'a player cannot use the admin RPC');
  perform pg_temp.login(v_admin);
  perform admin_crew_set_boss(c, v_crew, 'Owner request');
  perform pg_temp.assert((select rank from crew_members where user_id = c) = 'boss' and (select count(*) from crew_members where crew_id = v_crew and rank = 'boss') = 1, 'admin made C Boss');
  perform pg_temp.assert((select rank from crew_members where user_id = a) = 'lieutenant', 'old Boss is Lieutenant');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'grant_crew_boss' and target_user = c), 'admin audit row');
  raise notice 'ok 5: gang boss hand-back';
end $$;

-- ---------- 6. Land levy: the open deal is visible, can be paid / walked away from, and an expired one is released ----------
do $$
declare a uuid := pg_temp.fx_make('FxLand', 0, 500000000); r jsonb; v_deal bigint; v_before bigint;
begin
  perform pg_temp.login(a);
  update game_config set value = '0' where key = 'invest.land_walk_cooldown_seconds';
  perform set_config('bl.test_rand', '0.0', true);
  r := invest_land_buy('land_gra', 1);
  perform pg_temp.assert(r->>'status' = 'levy', 'the buy stops at a levy: ' || r::text);
  v_deal := (r->>'deal_id')::bigint;
  perform pg_temp.assert((invest_overview()->'pending_deal'->>'id')::bigint = v_deal and (invest_overview()->'pending_deal'->>'levy')::bigint > 0, 'overview lists the open deal with its levy');
  perform pg_temp.assert(pg_temp.fx_hint($q$select invest_land_buy('land_gra', 1)$q$) = 'pending', 'an open deal blocks another buy');
  -- walk away: nothing charged, can buy again
  v_before := (select bank from profiles where id = a);
  r := invest_land_levy(v_deal, false);
  perform pg_temp.assert(r->>'status' = 'walked' and (select bank from profiles where id = a) = v_before, 'walking away costs nothing');
  perform pg_temp.assert((invest_overview()->'pending_deal') is null or invest_overview()->>'pending_deal' is null, 'no open deal after walking away');
  -- pay
  r := invest_land_buy('land_gra', 1);
  v_deal := (r->>'deal_id')::bigint;
  r := invest_land_levy(v_deal, true);
  perform pg_temp.assert(r->>'status' = 'done' and (select bank from profiles where id = a) < v_before, 'paying the levy closes the deal and charges');
  -- an expired deal does not block: it is released by the next buy
  r := invest_land_buy('land_gra', 1);
  perform pg_temp.assert(r->>'status' = 'levy', 'new levy deal');
  update invest_land_deals set expires_at = now() - interval '1 minute' where user_id = a and status = 'pending';
  perform pg_temp.assert(invest_overview()->>'pending_deal' is null, 'an expired deal is not shown');
  r := invest_land_buy('land_gra', 1);
  perform pg_temp.assert(r->>'status' in ('levy', 'done'), 'expired deal released: the player can buy again');
  perform pg_temp.assert((select count(*) from invest_land_deals where user_id = a and status = 'expired') = 1, 'the old deal is marked expired');
  perform set_config('bl.test_rand', '', true);
  raise notice 'ok 6: land levy';
end $$;

-- ---------- 7. Laptops: every laptop has a buy card where it is sold, and the buy works ----------
do $$
declare a uuid := pg_temp.fx_make('FxLaptop', 900000000, 0); r record; n int; v_cards jsonb;
begin
  perform pg_temp.login(a);
  for r in select l.id as loc, i.id as item from locations l join items i on l.id = any (i.sold_at)
            where i.category = 'laptop' and l.scene in ('mall', 'office', 'cyber') loop
    update profiles set location_id = r.loc, travel_to = null, busy_until = null where id = a;
    v_cards := place_interior(r.loc)::jsonb;
    select count(*) into n from jsonb_array_elements(v_cards->'zones') z, jsonb_array_elements(z->'actions') c
     where c->>'kind' = 'shop' and c->>'ref' = r.item;
    perform pg_temp.assert(n >= 1 or exists (select 1 from jsonb_array_elements(v_cards->'zones') z, jsonb_array_elements(z->'actions') c where c->>'ref' = 'shop' and c->>'kind' = 'panel'),
      r.item || ' has a buy card at ' || r.loc);
    perform shop_buy(r.item, 1);
    perform pg_temp.assert(exists (select 1 from inventory where user_id = a and item_id = r.item and qty >= 1), r.item || ' bought at ' || r.loc);
  end loop;
  perform pg_temp.assert(exists (select 1 from zone_actions where zone_id = 'mall.shoprite' and ref = 'macbook_pro_m4')
                     and exists (select 1 from zone_actions where zone_id = 'office.desks' and ref = 'dell_xps_13'), 'premium laptops have cards at the mall and the Tech Hub');
  raise notice 'ok 7: laptops';
end $$;

-- ---------- 8. Delete my account ----------
create or replace function pg_temp.fx_leftovers(p_uid uuid) returns text
language plpgsql as $$
declare r record; n bigint; out text := '';
begin
  for r in select c.conrelid::regclass::text as tbl, a.attname as col
             from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
            where c.contype = 'f' and c.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass) and array_length(c.conkey, 1) = 1 loop
    execute format('select count(*) from %s where %I = $1', r.tbl, r.col) into n using p_uid;
    if n > 0 then out := out || r.tbl || '.' || r.col || '=' || n || ' '; end if;
  end loop;
  return nullif(out, '');
end $$;

do $$
declare a uuid := pg_temp.fx_make('FxDelMe'); b uuid := pg_temp.fx_make('FxStays'); adm uuid := pg_temp.fx_make('FxDelAdm'); r jsonb;
begin
  -- give A rows in many places
  perform pg_temp.login(a);
  perform club_alert_prefs_set('{"push": true}');
  perform push_prefs_set('{"messages": false}');
  insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (a, 'https://push.example/fx-del', 'k', 'x');
  perform furniture_buy('stool');
  perform pg_temp.assert(pg_temp.fx_leftovers(a) is not null, 'A has rows before');
  -- refusals
  perform pg_temp.assert(pg_temp.fx_hint($q$select self_delete_start('delete')$q$) = 'confirm', 'must type DELETE in capitals');
  perform pg_temp.assert(pg_temp.fx_hint($q$select self_delete_start('')$q$) = 'confirm', 'empty refused');
  update profiles set is_admin = true where id = adm;
  perform pg_temp.login(adm);
  perform pg_temp.assert(pg_temp.fx_hint($q$select self_delete_start('DELETE')$q$) = 'is_admin', 'admins cannot delete themselves here');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.self_delete_start(text)', 'execute'), 'not for anon');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_self_delete_failed(uuid,text)', 'execute'), 'failed-log is private');
  -- the real start: audit row first
  perform pg_temp.login(a);
  r := self_delete_start(' DELETE ');
  perform pg_temp.assert((r->>'ok')::boolean and r->>'username' = 'FxDelMe', 'start ok');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'self_delete_account' and target_user = a and data->>'email' = 'fxdelme@fx.bl'), 'audit snapshot written first');
  -- what auth.admin.deleteUser does: every row goes, nothing is orphaned
  delete from auth.users where id = a;
  perform pg_temp.assert(pg_temp.fx_leftovers(a) is null, 'rows left: ' || coalesce(pg_temp.fx_leftovers(a), ''));
  perform pg_temp.assert(not exists (select 1 from club_alert_prefs where user_id = a) and not exists (select 1 from profiles where id = a), 'profile and prefs gone');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'self_delete_account' and data->>'user_id' = a::text), 'audit row kept');
  perform pg_temp.assert(exists (select 1 from profiles where id = b), 'other players untouched');
  raise notice 'ok 8: delete my account';
end $$;

-- ---------- 9. Phone banking ----------
do $$
declare a uuid := pg_temp.fx_make('FxPhone', 1000000, 1000000); r jsonb; v_supply0 bigint; v_supply1 bigint; c0 bigint; b0 bigint;
begin
  perform pg_temp.login(a);
  -- far from any bank, and busy: still works (like transfers)
  update profiles set location_id = 'oba_market', busy_until = now() + interval '5 minutes', busy_label = 'x' where id = a;
  select cash, bank into c0, b0 from profiles where id = a;
  v_supply0 := (select sum(cash + bank) from profiles where id = a);
  r := phone_bank_deposit(10000);
  perform pg_temp.assert((r->>'fee')::bigint = 100 and (r->>'bank')::bigint = b0 + 10000 and (r->>'cash')::bigint = c0 - 10100, '1% of 10,000 = 100 fee, from cash: ' || r::text);
  r := phone_bank_withdraw(2000);
  perform pg_temp.assert((r->>'fee')::bigint = 50, 'minimum fee 50 on a small amount');
  perform pg_temp.assert((select bank from profiles where id = a) = b0 + 10000 - 2050 and (select cash from profiles where id = a) = c0 - 10100 + 2000, 'withdraw: fee from the bank');
  -- the fee is destroyed (a sink), the moves are not
  v_supply1 := (select sum(cash + bank) from profiles where id = a);
  perform pg_temp.assert(v_supply0 - v_supply1 = 150, 'money gone = the two fees only');
  perform pg_temp.assert((select sum(delta) from ledger where user_id = a and reason = 'phone_bank_fee') = -150, 'fee rows in the ledger');
  perform pg_temp.assert(bl_ledger_label('phone_bank_fee', '{}') = 'Phone banking fee' and bl_econ_category('phone_bank_fee') = 'Market and PoS fees', 'label and category');
  -- limits kept
  perform pg_temp.assert(pg_temp.fx_hint('select phone_bank_deposit(50)') = 'bad_amount', 'min amount kept');
  perform pg_temp.assert(pg_temp.fx_hint('select phone_bank_deposit(100001)') = 'bad_amount', 'max per go kept (same as PoS)');
  update profiles set cash = 10050 where id = a;
  perform pg_temp.assert(pg_temp.fx_hint('select phone_bank_deposit(10000)') = 'not_enough_cash', 'fee must fit too: 10,000 + 100 > 10,050');
  update profiles set bank = 10050 where id = a;
  perform pg_temp.assert(pg_temp.fx_hint('select phone_bank_withdraw(10000)') = 'not_enough_bank', 'withdraw fee must fit too');
  -- no exploit: round trips only lose money, never gain
  update profiles set cash = 50000, bank = 50000 where id = a;
  for i in 1..5 loop perform phone_bank_deposit(10000); perform phone_bank_withdraw(10000); end loop;
  perform pg_temp.assert((select cash + bank from profiles where id = a) = 100000 - 5 * 200, 'ten moves cost exactly ten fees');
  -- never earned income
  perform pg_temp.assert(not ('phone_bank_fee' = any (bl_earn_reasons())) and not ('phone_bank_deposit' = any (bl_earn_reasons())), 'not an earn reason');
  -- admin setting: switch off, change fee
  update game_config set value = 'false' where key = 'bank.phone_enabled';
  perform pg_temp.assert(pg_temp.fx_hint('select phone_bank_deposit(1000)') = 'phone_off', 'switch off refuses');
  update game_config set value = 'true' where key = 'bank.phone_enabled';
  update game_config set value = '2' where key = 'bank.phone_fee_pct';
  perform pg_temp.assert((phone_bank_deposit(10000)->>'fee')::bigint = 200, 'admin fee % applies');
  update game_config set value = '1' where key = 'bank.phone_fee_pct';
  -- jailed: refused
  update profiles set jailed_until = now() + interval '1 hour' where id = a;
  perform pg_temp.assert(pg_temp.fx_hint('select phone_bank_deposit(1000)') = 'jailed', 'no banking from a cell');
  update profiles set jailed_until = null where id = a;
  -- in person at the bank stays free
  update profiles set location_id = 'bronze_bank', busy_until = null, busy_label = null, cash = 5000, bank = 5000 where id = a;
  update game_config set value = '0' where key in ('bank.open_hour', 'bank.close_hour');
  r := bank_deposit(1000);
  perform pg_temp.assert((select cash from profiles where id = a) = 4000 and not exists (select 1 from ledger where user_id = a and reason = 'phone_bank_fee' and created_at > now() - interval '1 second' and meta->>'amount' = '1000'), 'bank counter is free');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.phone_bank_deposit(bigint)', 'execute') and not has_function_privilege('authenticated', 'public.bl_phone_fee(bigint)', 'execute'), 'grants');
  raise notice 'ok 9: phone banking';
end $$;

-- ---------- 10. Primary car ----------
do $$
declare a uuid := pg_temp.fx_make('FxDrive', 900000000, 0); b uuid := pg_temp.fx_make('FxNoCar'); q jsonb; r jsonb; v_mode jsonb;
begin
  perform pg_temp.login(a);
  update profiles set location_id = 'oba_market', travel_to = null where id = a;
  -- two vehicles in different Bolt classes: the old rule drives the expensive one
  perform bl_give_item(a, 'kia_rio_used', 1);
  perform bl_give_item(a, 'gwagon_g63', 1);
  perform pg_temp.assert(bl_driving_item(a) = 'gwagon_g63' and bl_primary_item(a) is null, 'default = most expensive');
  perform pg_temp.assert((bl_hustle_car(a)->>'item_id') = 'gwagon_g63' and (bl_hustle_car(a)->>'class_id') = 'luxury', 'Bolt uses the G-Wagon by default');
  perform pg_temp.assert(car_primary_get()->>'driving' = 'gwagon_g63' and car_primary_get()->>'chosen' is null, 'car_primary_get default');
  -- pick the small car
  r := car_set_primary('kia_rio_used');
  perform pg_temp.assert(r->>'driving' = 'kia_rio_used', 'set primary');
  perform pg_temp.assert((bl_hustle_car(a)->>'item_id') = 'kia_rio_used' and (bl_hustle_car(a)->>'class_id') = 'economy', 'Bolt now uses the picked car (economy class)');
  perform pg_temp.assert((select label from jsonb_to_recordset(travel_quote('uselu_market')->'options') as m(mode text, label text) where mode = 'car') = 'Your own car', 'travel quote has a car mode');
  -- pick a bicycle: the travel quote becomes the bicycle ride
  perform bl_give_item(a, 'bicycle', 1);
  perform car_set_primary('bicycle');
  v_mode := (select to_jsonb(m) from jsonb_to_recordset(travel_quote('uselu_market')->'options') as m(mode text, label text, vehicle text) where mode = 'car');
  perform pg_temp.assert(v_mode->>'label' = 'Your bicycle', 'travel quote follows the picked vehicle: ' || v_mode::text);
  perform car_set_primary('gwagon_g63');
  perform pg_temp.assert((select label from jsonb_to_recordset(travel_quote('uselu_market')->'options') as m(mode text, label text) where mode = 'car') = 'Your own car', 'back to the car');
  -- garage list: picked first and marked
  perform car_set_primary('kia_rio_used');
  r := garage_home();
  perform pg_temp.assert(r->'cars'->0->>'id' = 'kia_rio_used' and (r->'cars'->0->>'primary')::boolean and not (r->'cars'->1->>'primary')::boolean, 'garage lists the picked car first');
  -- refusals
  perform pg_temp.assert(pg_temp.fx_hint($q$select car_set_primary('lambo_urus')$q$) = 'not_owned', 'not owned');
  perform pg_temp.assert(pg_temp.fx_hint($q$select car_set_primary('soap')$q$) = 'not_owned', 'not a vehicle');
  -- selling the picked car falls back to the old rule
  delete from inventory where user_id = a and item_id = 'kia_rio_used';
  perform pg_temp.assert(bl_primary_item(a) is null and bl_driving_item(a) = 'gwagon_g63', 'sold: falls back to the best car');
  -- another player cannot see or use it, and a player with no car has none
  perform pg_temp.login(b);
  perform pg_temp.assert(bl_driving_item(b) is null and (bl_hustle_car(b)) is null, 'no car, no driving');
  perform pg_temp.assert(pg_temp.fx_hint($q$select car_set_primary('gwagon_g63')$q$) = 'not_owned', 'cannot pick another player''s car');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.car_set_primary(text)', 'execute') and not has_function_privilege('authenticated', 'public.bl_driving_item(uuid)', 'execute'), 'grants');
  raise notice 'ok 10: primary car';
end $$;
