-- PAY (20261007000100_payments.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/payments_test.sql
-- Groups: 1 packs (players read active ones, admin-only edits, audited) · 2 payment_init · 3 clients can't
-- credit or write payments, read only their own · 4 bl_payment_credit (amount check, ledger + bank, idempotent)
-- · 5 leaderboards (rich + VIP, your rank, hidden amounts, banned/admins hidden) · 6 VIP arrival announcements.

create temp table t_pay (name text primary key, id uuid not null) on commit drop;
grant select on t_pay to authenticated;
create or replace function pg_temp.pp(p_name text) returns uuid
language sql as $$ select id from t_pay where name = p_name $$;

create or replace function pg_temp.pp_make(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@pay.bl');
begin
  insert into t_pay values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, busy_until = null, cash = 1000, bank = 0 where id = v;
  return v;
end $$;

-- a successful payment of p_kobo for a player (as the service would leave it)
create or replace function pg_temp.pp_paid(p_uid uuid, p_kobo bigint) returns void
language sql as $$
  insert into payments (user_id, pack_id, reference, amount_kobo, game_naira, status, provider, paid_at)
  values (p_uid, 'small', 'T-' || gen_random_uuid(), p_kobo, 1000, 'success', 'paystack', now());
$$;

do $$
declare
  a uuid; b uuid; c uuid; adm uuid;
  r jsonb; ref text; ref2 text; ok boolean; n int; v_bank bigint; v_led record;
begin
  -- keep the binding launch settings untouched by this file (rolled back anyway)
  a := pg_temp.pp_make('Pay_Nosa');
  b := pg_temp.pp_make('Pay_Ada');
  c := pg_temp.pp_make('Pay_Efe');
  adm := pg_temp.pp_make('Pay_Boss');
  update profiles set is_admin = true where id = adm;
  delete from payments;
  delete from place_announcements;
  update game_config set value = 'false' where key = 'payments.enabled';

  -- 1. packs ------------------------------------------------------------
  perform pg_temp.assert((select count(*) from topup_packs where id in ('small','medium','big','oga','odogwu')) = 5, 'seeded packs');
  update topup_packs set active = false where id = 'odogwu';
  perform pg_temp.login(a);
  set local role authenticated;
  select count(*) into n from topup_packs;
  perform pg_temp.assert(n = (select count(*) from topup_packs where active) and not exists (select 1 from topup_packs where id = 'odogwu'),
                         'players see only active packs');
  ok := false;
  begin update topup_packs set price_kobo = 100 where id = 'small'; exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'players cannot edit packs');
  ok := false;
  begin perform admin_row_upsert('topup_packs', '{"id":"small","price_kobo":100}'); exception when others then ok := true; end;
  perform pg_temp.assert(ok, 'non-admin cannot use admin_row_upsert on packs');
  reset role;
  perform pg_temp.login(adm);
  set local role authenticated;
  r := admin_row_upsert('topup_packs', '{"id":"small","price_kobo":30000,"game_naira":25000,"bonus_tag":"Promo"}');
  perform pg_temp.assert(r->>'message' = 'Saved.', 'admin edits a pack');
  r := admin_table_rows('topup_packs');
  perform pg_temp.assert(jsonb_array_length(r) = 5, 'admin lists every pack (inactive too)');
  r := admin_payments(null, null, 50);
  perform pg_temp.assert((r->'totals'->>'all_count')::int = 0, 'admin_payments works for admins');
  reset role;
  perform pg_temp.assert((select price_kobo from topup_packs where id = 'small') = 30000, 'pack saved');
  perform pg_temp.assert(exists (select 1 from admin_audit where admin_id = adm and data->>'table' = 'topup_packs'), 'pack edit audited');
  update topup_packs set price_kobo = 20000, game_naira = 20000, bonus_tag = null, active = true where id in ('small', 'odogwu');
  update topup_packs set price_kobo = 2000000, game_naira = 3500000, bonus_tag = '+75% bonus' where id = 'odogwu';
  perform pg_temp.login(a);
  set local role authenticated;
  ok := false;
  begin perform admin_payments(null, null, 50); exception when others then ok := true; end;
  perform pg_temp.assert(ok, 'players cannot open admin_payments');
  reset role;
  raise notice '1 packs ok';

  -- 2. payment_init ----------------------------------------------------
  perform pg_temp.login(a);
  set local role authenticated;
  ok := false;
  begin perform payment_init('medium'); exception when sqlstate 'P0001' then ok := sqlerrm like '%coming soon%'; end;
  perform pg_temp.assert(ok, 'payment_init refused while payments.enabled is off');
  reset role;
  update game_config set value = 'true' where key = 'payments.enabled';
  perform pg_temp.login(a);
  set local role authenticated;
  r := payment_init('medium');
  ref := r->>'reference';
  perform pg_temp.assert(ref like 'BL-%' and (r->>'amount_kobo')::bigint = 100000 and r->>'email' = 'pay_nosa@pay.bl' and r->>'currency' = 'NGN',
                         'payment_init returns reference, amount and email: ' || r::text);
  ok := false;
  begin perform payment_init('nope'); exception when sqlstate 'P0001' then ok := true; end;
  perform pg_temp.assert(ok, 'unknown pack refused');
  reset role;
  perform pg_temp.assert(exists (select 1 from payments where reference = ref and user_id = a and status = 'pending'
                                   and amount_kobo = 100000 and game_naira = 120000 and pack_id = 'medium'), 'pending row created');
  raise notice '2 payment_init ok';

  -- 3. clients can't credit or write ---------------------------------
  perform pg_temp.login(a);
  set local role authenticated;
  ok := false;
  begin perform bl_payment_credit(ref, 100000, '{}'); exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'authenticated cannot call bl_payment_credit');
  ok := false;
  begin update payments set status = 'success' where reference = ref; exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'authenticated cannot update payments');
  ok := false;
  begin insert into payments (user_id, reference, amount_kobo, game_naira) values (a, 'X-1', 100, 1000000); exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'authenticated cannot insert payments');
  perform pg_temp.assert((select count(*) from payments) = 1, 'own payment visible');
  reset role;
  perform pg_temp.login(b);
  set local role authenticated;
  perform pg_temp.assert((select count(*) from payments) = 0, 'other players'' payments are invisible');
  reset role;
  set local role anon;
  ok := false;
  begin perform bl_payment_credit(ref, 100000, '{}'); exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'anon cannot call bl_payment_credit');
  ok := false;
  begin perform payment_init('small'); exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'anon cannot call payment_init');
  reset role;
  perform pg_temp.assert(has_function_privilege('service_role', 'public.bl_payment_credit(text,bigint,jsonb)', 'execute'), 'service_role may credit');
  raise notice '3 privileges ok';

  -- 4. credit ------------------------------------------------------------
  set local role service_role;
  r := bl_payment_credit(ref, 50000, '{"status":"success"}');
  reset role;
  perform pg_temp.assert(r->>'error' = 'amount_mismatch', 'amount mismatch refused: ' || r::text);
  perform pg_temp.assert((select status from payments where reference = ref) = 'failed', 'mismatch marks the payment failed');
  perform pg_temp.assert((select bank from profiles where id = a) = 0, 'no money on mismatch');
  perform pg_temp.login(a);
  set local role authenticated;
  ref2 := payment_init('medium')->>'reference';
  reset role;
  set local role service_role;
  r := bl_payment_credit(ref2, 100000, '{"status":"success","currency":"NGN"}');
  reset role;
  perform pg_temp.assert((r->>'credited')::boolean and (r->>'bank')::bigint = 120000, 'credited: ' || r::text);
  perform pg_temp.assert((select bank from profiles where id = a) = 120000, 'bank increased by the pack');
  select * into v_led from ledger where user_id = a and reason = 'topup' order by id desc limit 1;
  perform pg_temp.assert(v_led.delta = 120000 and v_led.account = 'bank' and v_led.balance_after = 120000
                         and bl_ledger_label(v_led.reason, v_led.meta) = 'Top-up via Paystack', 'ledger row "Top-up via Paystack"');
  perform pg_temp.assert(exists (select 1 from payments where reference = ref2 and status = 'success' and paid_at is not null), 'marked success');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'topup'), 'player gets an alert');
  set local role service_role;
  r := bl_payment_credit(ref2, 100000, '{}');
  reset role;
  perform pg_temp.assert((r->>'already')::boolean and not (r->>'credited')::boolean, 'second credit is a no-op');
  perform pg_temp.assert((select bank from profiles where id = a) = 120000 and (select count(*) from ledger where user_id = a and reason = 'topup') = 1,
                         'credited only once');
  r := bl_payment_credit(ref, 100000, '{}');
  perform pg_temp.assert(r->>'error' = 'not_pending', 'a failed payment is never credited');
  r := bl_payment_credit('BL-unknown', 100000, '{}');
  perform pg_temp.assert(r->>'error' = 'unknown_reference', 'unknown reference');
  raise notice '4 credit ok';

  -- 5. leaderboards ------------------------------------------------------
  -- VIP: a = ₦1,000 (above), b = ₦25,000, c = ₦6,000; admin pays most but is hidden
  perform pg_temp.pp_paid(b, 2500000);
  perform pg_temp.pp_paid(c, 600000);
  perform pg_temp.pp_paid(adm, 90000000);
  update profiles set cash = 5000000, bank = 10000000 where id = c;   -- ₦15M: Oga
  update profiles set cash = 99000000000 where id = adm;
  perform pg_temp.login(a);
  set local role authenticated;
  r := leaderboard_vip(50);
  perform pg_temp.assert(r->'rows'->0->>'username' = 'Pay_Ada' and r->'rows'->0->>'tier' = 'Gold'
                         and r->'rows'->1->>'username' = 'Pay_Efe' and r->'rows'->1->>'tier' = 'Silver', 'VIP order + tiers: ' || r::text);
  perform pg_temp.assert(not (r::text like '%Pay_Boss%'), 'admins hidden from VIP');
  perform pg_temp.assert((r->'rows'->0->'amount') = 'null'::jsonb and r::text not like '%@pay.bl%', 'amounts and emails hidden');
  perform pg_temp.assert((r->'me'->>'rank')::int = 3 and (r->'me'->>'amount')::bigint = 1000 and r->'me'->>'tier' = 'Bronze', 'your VIP rank');
  reset role;
  update game_config set value = 'true' where key = 'leaderboard.vip_show_amounts';
  perform pg_temp.login(a);
  set local role authenticated;
  r := leaderboard_vip(1);
  perform pg_temp.assert((r->'rows'->0->>'amount')::bigint = 25000 and jsonb_array_length(r->'rows') = 1, 'amounts shown when on; limit works');
  r := leaderboard_rich(50);
  perform pg_temp.assert(r->'rows'->0->>'username' = 'Pay_Efe' and r->'rows'->0->>'tier' = 'Oga' and (r->'rows'->0->>'total')::bigint = 15000000,
                         'rich list top: ' || (r->'rows'->0)::text);
  perform pg_temp.assert(not (r::text like '%Pay_Boss%'), 'admins hidden from rich list');
  perform pg_temp.assert((r->'me'->>'rank')::int >= 2 and (r->'me'->>'total')::bigint = 121000, 'your rich rank');
  reset role;
  perform pg_temp.assert((r->'me'->>'rank')::bigint = (select rank from bl_rich_ranked() where id = a), 'your rich rank matches the board');
  update profiles set banned = true where id = c;
  perform pg_temp.login(a);
  set local role authenticated;
  r := leaderboard_rich(50);
  perform pg_temp.assert(not (r::text like '%Pay_Efe%'), 'banned players hidden');
  reset role;
  update profiles set banned = false where id = c;
  update game_config set value = 'false' where key = 'leaderboard.vip_show_amounts';
  raise notice '5 leaderboards ok';

  -- 6. VIP arrivals -------------------------------------------------------
  perform set_config('bl.test_rand', '0.999', true); -- no street robbery
  update game_config set value = 'true' where key = 'vip.arrivals_enabled';
  update game_config set value = '30' where key = 'vip.arrival_cooldown_min';
  update game_config set value = '3' where key = 'vip.arrival_top';
  update profiles set location_id = 'ekenwan_room', travel_to = 'mama_osas_buka', travel_mode = 'walk',
                      travel_started_at = bl_now() - interval '10 minutes', travel_arrives_at = bl_now() - interval '1 second'
   where id = b;
  perform pg_temp.login(b);
  set local role authenticated;
  r := travel_arrive();
  reset role;
  perform pg_temp.assert(r->>'location' = 'mama_osas_buka', 'arrived');
  perform pg_temp.assert(exists (select 1 from place_announcements where user_id = b and kind = 'vip_arrival' and location_id = 'mama_osas_buka'
                                   and text = 'VIP #1 @Pay_Ada just walked into Mama Osas Buka!' and qty = 1), 'VIP #1 arrival announced');
  -- cooldown
  update profiles set travel_to = 'oba_market', travel_mode = 'walk', travel_started_at = bl_now() - interval '10 minutes',
                      travel_arrives_at = bl_now() - interval '1 second' where id = b;
  perform pg_temp.login(b);
  set local role authenticated;
  perform travel_arrive();
  reset role;
  perform pg_temp.assert((select count(*) from place_announcements where user_id = b and kind = 'vip_arrival') = 1, 'cooldown holds');
  -- home is not announced
  delete from place_announcements;
  update profiles set travel_to = home_location_id, travel_mode = 'walk', travel_started_at = bl_now() - interval '10 minutes',
                      travel_arrives_at = bl_now() - interval '1 second' where id = b;
  perform pg_temp.login(b);
  set local role authenticated;
  perform travel_arrive();
  reset role;
  perform pg_temp.assert(not exists (select 1 from place_announcements where user_id = b), 'arriving home is not announced');
  -- outside the top N: no announcement
  update game_config set value = '1' where key = 'vip.arrival_top';
  update profiles set travel_to = 'oba_market', travel_mode = 'walk', travel_started_at = bl_now() - interval '10 minutes',
                      travel_arrives_at = bl_now() - interval '1 second' where id = c;
  perform pg_temp.login(c);
  set local role authenticated;
  perform travel_arrive();
  reset role;
  perform pg_temp.assert(not exists (select 1 from place_announcements where user_id = c), 'VIP #2 not announced when only the top 1 is');
  -- switched off
  update game_config set value = '3' where key = 'vip.arrival_top';
  update game_config set value = 'false' where key = 'vip.arrivals_enabled';
  update profiles set travel_to = 'mama_osas_buka', travel_mode = 'walk', travel_started_at = bl_now() - interval '10 minutes',
                      travel_arrives_at = bl_now() - interval '1 second' where id = c;
  perform pg_temp.login(c);
  set local role authenticated;
  perform travel_arrive();
  reset role;
  perform pg_temp.assert(not exists (select 1 from place_announcements where user_id = c), 'arrivals off');
  update game_config set value = 'true' where key = 'vip.arrivals_enabled';
  -- a non-payer is never announced
  update profiles set location_id = 'oba_market', travel_to = 'mama_osas_buka', travel_mode = 'walk', travel_started_at = bl_now() - interval '10 minutes',
                      travel_arrives_at = bl_now() - interval '1 second' where id = adm;
  update profiles set is_admin = false where id = adm;
  delete from payments where user_id = adm;
  perform pg_temp.login(adm);
  set local role authenticated;
  perform travel_arrive();
  reset role;
  perform pg_temp.assert(not exists (select 1 from place_announcements where user_id = adm), 'non-payers are not announced');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_vip_arrival(uuid,text)', 'execute'), 'bl_vip_arrival is server-only');
  raise notice '6 vip arrivals ok';
end $$;

-- binding launch config is unchanged
do $$
begin
  perform pg_temp.assert((select value from game_config where key = 'origin.nepo_pct') = '10'::jsonb, 'origin.nepo_pct 10');
  perform pg_temp.assert((select value from game_config where key = 'clock.mode') = '"real"'::jsonb, 'clock.mode real');
end $$;
