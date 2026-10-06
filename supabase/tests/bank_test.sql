-- L1 (20261006000100_real_time.sql): this file pins the pre-L1 behaviour (accelerated clock +
-- game-minute durations); time_test.sql covers the real clock and short actions. Rolled back.
update game_config set value = '"accelerated"' where key = 'clock.mode';
update game_config set value = '"game_minutes"' where key = 'action.mode';

-- Bank tests (V1-5): config + privileges, bank_deposit / bank_withdraw only at the bank and only in
-- banking hours, PoS cash-out / deposit fee math (config-driven), phone transfers (fee, limits,
-- cooldown, new-account wait, self, unknown user, events, both balances), bank_history labels,
-- bank_info, and street robbery still taking cash only. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/bank_test.sql
-- Rolled back at the end. Time with bl.test_offset_seconds, rolls with bl.test_rand.

create or replace function pg_temp.bk_advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;

create or replace function pg_temp.bk_hint(p_sql text, p_hint text) returns text
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

create temp table t_bank_u (name text primary key, id uuid not null) on commit drop;
create or replace function pg_temp.bk_u(p_name text) returns uuid
language sql as $$ select id from t_bank_u where name = p_name $$;

create or replace function pg_temp.bk_make(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@bank.bl');
begin
  insert into t_bank_u values (p_name, v);
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'female', '{"gender":"female"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  -- old enough to send transfers (group 5 tests the new-account wait)
  update profiles set created_at = bl_now() - interval '1 day' where id = v;
  return v;
end $$;

create or replace function pg_temp.bk_at(p_uid uuid, p_loc text, p_cash bigint, p_bank bigint) returns void
language sql as $$
  update profiles set location_id = p_loc, travel_to = null, busy_until = null, busy_label = null,
                      jailed_until = null, hospitalized_until = null, cash = p_cash, bank = p_bank,
                      hunger = 80, energy = 80, hygiene = 80, fun = 80, social = 80, stress = 10, health = 100,
                      bladder = 90, needs_updated_at = bl_now()
   where id = p_uid;
$$;

-- bank open (true) or closed (false) at the current game hour
create or replace function pg_temp.bk_hours(p_open boolean) returns void
language plpgsql as $$
declare h int := (bl_game_clock()->>'hour')::int;
begin
  if p_open then
    update game_config set value = to_jsonb(h) where key = 'bank.open_hour';
    update game_config set value = to_jsonb(h + 1) where key = 'bank.close_hour';
  else
    update game_config set value = to_jsonb((h + 2) % 24) where key = 'bank.open_hour';
    update game_config set value = to_jsonb((h + 2) % 24 + 1) where key = 'bank.close_hour';
  end if;
end $$;

create or replace function pg_temp.bk_money(p_uid uuid) returns text
language sql as $$ select cash || '/' || bank from profiles where id = p_uid $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  -- pin the numbers this file asserts (the live DB may hold admin-tuned values; rolled back anyway)
  update game_config set value = '8' where key = 'bank.open_hour';
  update game_config set value = '16' where key = 'bank.close_hour';
  update game_config set value = '100' where key = 'bank.min_amount';
  update game_config set value = '50' where key = 'bank.transfer_fee';
  update game_config set value = '100' where key = 'bank.transfer_min_amount';
  update game_config set value = '200000' where key = 'bank.transfer_daily_limit';
  update game_config set value = '10' where key = 'bank.transfer_daily_count';
  update game_config set value = '15' where key = 'bank.transfer_cooldown_real_seconds';
  update game_config set value = '30' where key = 'bank.transfer_min_account_real_minutes';
  update game_config set value = '1.5' where key = 'pos.fee_pct';
  update game_config set value = '100' where key = 'pos.fee_min';
  update game_config set value = '100000' where key = 'pos.max_amount';
  update game_config set value = 'false' where key = 'rent.enabled';   -- no rent day surprises while time-travelling
end $$;

-- ---------- 0. config, places, privileges ----------
do $$
declare k text;
begin
  foreach k in array array['bank.open_hour','bank.close_hour','bank.min_amount','bank.transfer_fee','bank.transfer_min_amount',
                           'bank.transfer_daily_limit','bank.transfer_daily_count','bank.transfer_cooldown_real_seconds',
                           'bank.transfer_min_account_real_minutes','bank.tip_cash_threshold','pos.fee_pct','pos.fee_min','pos.max_amount'] loop
    perform pg_temp.assert(exists (select 1 from game_config where key = k and label <> '' and category in ('bank','pos')
                                   and description <> '' and kind <> '' and min is not null and max is not null), 'config ' || k);
  end loop;
  perform pg_temp.assert(exists (select 1 from locations where id = 'bronze_bank' and 'bank' = any (actions)), 'Bronze Bank has the bank action');
  perform pg_temp.assert((select count(*) from locations where 'pos' = any (actions)) >= 3, 'three PoS stands');
  foreach k in array array['bl_pos_fee(bigint)','bl_pos_max(bigint)','bl_bank_open(jsonb)','bl_ledger_label(text,jsonb)',
                           'bl_transfer_stats(uuid)','bl_find_player(text)','bl_check_amount(bigint,bigint,bigint)',
                           'bl_assert_at(profiles,text)','bl_assert_bank_open(text)','bl_places_with(text,integer)',
                           'bl_hour_text(integer)','bl_bank_opens_in(jsonb)','bl_pos_banter()'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', 'public.' || k, 'execute'), 'helper revoked: ' || k);
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || k, 'execute'), 'helper revoked (anon): ' || k);
  end loop;
  foreach k in array array['bank_info()','bank_recipient(text)','bank_history(integer)','bank_deposit(bigint)',
                           'bank_withdraw(bigint)','pos_cashout(bigint)','pos_deposit(bigint)','bank_transfer(text,bigint,text)'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || k, 'execute'), 'rpc granted: ' || k);
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || k, 'execute'), 'rpc not for anon: ' || k);
  end loop;
  -- ledger stays read-only for clients
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.ledger', 'insert'), 'no client ledger insert');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.profiles', 'update'), 'no client profile update');
  raise notice 'ok 0: config, places, privileges';
end $$;

-- ---------- 1. fee helpers ----------
do $$
begin
  perform pg_temp.assert(bl_pos_fee(1000) = 100, 'min fee 100 for 1,000');
  perform pg_temp.assert(bl_pos_fee(6666) = 100, '1.5% of 6,666 = 99.99 -> min 100');
  perform pg_temp.assert(bl_pos_fee(10000) = 150, '1.5% of 10,000 = 150');
  perform pg_temp.assert(bl_pos_fee(10001) = 160, '150.015 rounds up to 160');
  perform pg_temp.assert(bl_pos_fee(100000) = 1500, '1.5% of 100,000');
  update game_config set value = '2' where key = 'pos.fee_pct';
  update game_config set value = '0' where key = 'pos.fee_min';
  perform pg_temp.assert(bl_pos_fee(1000) = 20 and bl_pos_fee(1001) = 30, 'config-driven: 2%, no min');
  update game_config set value = '1.5' where key = 'pos.fee_pct';
  update game_config set value = '100' where key = 'pos.fee_min';
  -- max: largest a with a + fee(a) <= balance
  perform pg_temp.assert(bl_pos_max(10150) = 10000, 'max of 10,150 is 10,000, got ' || bl_pos_max(10150));
  perform pg_temp.assert(bl_pos_max(1100) = 1000, 'max of 1,100 is 1,000');
  perform pg_temp.assert(bl_pos_max(150) = 0, 'under min + fee: 0');
  perform pg_temp.assert(bl_pos_max(5000000) = 100000, 'capped at pos.max_amount');
  perform pg_temp.assert(bl_pos_max(20000) + bl_pos_fee(bl_pos_max(20000)) <= 20000
                         and (bl_pos_max(20000) + 1) + bl_pos_fee(bl_pos_max(20000) + 1) > 20000, 'max is tight');
  perform pg_temp.assert(bl_hour_text(8) = '8:00 AM' and bl_hour_text(16) = '4:00 PM' and bl_hour_text(0) = '12:00 midnight'
                         and bl_hour_text(24) = '12:00 midnight' and bl_hour_text(12) = '12:00 noon', 'hour text');
  perform pg_temp.assert(bl_bank_open('{"hour": 8, "minute": 0}') and bl_bank_open('{"hour": 15, "minute": 59}')
                         and not bl_bank_open('{"hour": 16, "minute": 0}') and not bl_bank_open('{"hour": 7, "minute": 59}'), '8-16 hours');
  perform pg_temp.assert(bl_bank_opens_in('{"hour": 7, "minute": 30}') = 30 and bl_bank_opens_in('{"hour": 16, "minute": 0}') = 960
                         and bl_bank_opens_in('{"hour": 9, "minute": 0}') = 0, 'opens in');
  raise notice 'ok 1: fee helpers + hours';
end $$;

-- ---------- 2. bank_deposit / bank_withdraw ----------
do $$
declare v uuid := pg_temp.bk_make('Bank_A'); r jsonb; m text;
begin
  perform pg_temp.bk_at(v, 'bronze_bank', 10000, 0);
  perform pg_temp.bk_hours(true);
  r := bank_deposit(4000);
  perform pg_temp.assert(pg_temp.bk_money(v) = '6000/4000', 'deposit 4,000: ' || pg_temp.bk_money(v));
  perform pg_temp.assert((r->>'cash')::int = 6000 and (r->>'bank')::int = 4000 and r->>'message' ilike '%deposited ₦4,000%', 'deposit result: ' || r::text);
  perform pg_temp.assert((select count(*) from ledger where user_id = v and reason = 'bank_deposit') = 2
                         and exists (select 1 from ledger where user_id = v and reason = 'bank_deposit' and account = 'cash' and delta = -4000)
                         and exists (select 1 from ledger where user_id = v and reason = 'bank_deposit' and account = 'bank' and delta = 4000
                                     and meta->>'location' = 'bronze_bank'), 'deposit ledger rows');
  r := bank_withdraw(1500);
  perform pg_temp.assert(pg_temp.bk_money(v) = '7500/2500', 'withdraw 1,500: ' || pg_temp.bk_money(v));
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'bank_withdraw' and account = 'cash' and delta = 1500), 'withdraw ledger');
  -- All
  perform bank_deposit(7500);
  perform pg_temp.assert(pg_temp.bk_money(v) = '0/10000', 'deposit all');
  -- refusals
  perform pg_temp.bk_hint($q$ select bank_deposit(100) $q$, 'not_enough_cash');
  perform pg_temp.bk_hint($q$ select bank_withdraw(10001) $q$, 'not_enough_bank');
  perform pg_temp.bk_hint($q$ select bank_withdraw(0) $q$, 'bad_amount');
  perform pg_temp.bk_hint($q$ select bank_withdraw(99) $q$, 'bad_amount');
  perform pg_temp.bk_hint($q$ select bank_withdraw(-500) $q$, 'bad_amount');
  perform pg_temp.bk_hint($q$ select bank_withdraw(null) $q$, 'bad_amount');
  -- only at the bank
  update profiles set location_id = 'ring_road_pos' where id = v;
  m := pg_temp.bk_hint($q$ select bank_withdraw(500) $q$, 'not_here');
  perform pg_temp.assert(m ilike '%Bronze Bank%PoS%', 'not_here points to the bank and PoS: ' || m);
  update profiles set location_id = 'oba_market' where id = v;
  perform pg_temp.bk_hint($q$ select bank_deposit(500) $q$, 'not_here');
  -- busy / travelling / jailed
  update profiles set location_id = 'bronze_bank', busy_until = bl_now() + interval '1 hour' where id = v;
  perform pg_temp.bk_hint($q$ select bank_withdraw(500) $q$, 'busy');
  update profiles set busy_until = null, travel_to = 'oba_market' where id = v;
  perform pg_temp.bk_hint($q$ select bank_withdraw(500) $q$, 'traveling');
  update profiles set travel_to = null where id = v;
  -- closed hours
  perform pg_temp.bk_hours(false);
  m := pg_temp.bk_hint($q$ select bank_withdraw(500) $q$, 'closed');
  perform pg_temp.assert(m ilike 'Bronze Bank (GRA) is closed%opens in about %hr%PoS%', 'closed message: ' || m);
  perform pg_temp.bk_hint($q$ select bank_deposit(500) $q$, 'closed');
  perform pg_temp.assert(not (bank_info()->'bank_hours'->>'open')::boolean
                         and (bank_info()->'bank_hours'->>'opens_in_game_minutes')::int between 61 and 120, 'bank_info closed');
  -- open == close: never closes
  update game_config set value = '0' where key = 'bank.open_hour';
  update game_config set value = '0' where key = 'bank.close_hour';
  perform bank_withdraw(500);
  perform pg_temp.assert(pg_temp.bk_money(v) = '500/9500', 'always open when open = close');
  perform pg_temp.bk_hours(true);
  perform pg_temp.assert(pg_temp.bk_money(v) = '500/9500', 'refusals changed nothing');
  raise notice 'ok 2: bank_deposit / bank_withdraw';
end $$;

-- ---------- 3. PoS cash-out / deposit ----------
do $$
declare v uuid := pg_temp.bk_u('Bank_A'); r jsonb; i jsonb;
begin
  perform pg_temp.login(v);
  perform pg_temp.bk_at(v, 'sapele_pos', 1000, 30000);
  perform pg_temp.bk_hours(false);    -- PoS works when the bank is closed
  r := pos_cashout(10000);
  perform pg_temp.assert((r->>'fee')::int = 150 and pg_temp.bk_money(v) = '11000/19850', 'cash-out 10,000 fee 150: ' || pg_temp.bk_money(v));
  perform pg_temp.assert(r->>'message' ilike '%₦10,000 cash. Charge: ₦150.', 'cash-out message: ' || (r->>'message'));
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'pos_fee' and account = 'bank' and delta = -150
                                 and meta->>'kind' = 'cashout' and meta->>'location' = 'sapele_pos'), 'pos_fee ledger row (bank)');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'pos_cashout' and account = 'bank' and delta = -10000)
                         and exists (select 1 from ledger where user_id = v and reason = 'pos_cashout' and account = 'cash' and delta = 10000), 'cash-out rows');
  r := pos_deposit(1000);
  perform pg_temp.assert((r->>'fee')::int = 100 and pg_temp.bk_money(v) = '9900/20850', 'deposit 1,000 fee min 100: ' || pg_temp.bk_money(v));
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v and reason = 'pos_fee' and account = 'cash' and delta = -100
                                 and meta->>'kind' = 'deposit'), 'pos_fee ledger row (cash)');
  -- the fee must fit too
  perform pg_temp.bk_hint($q$ select pos_deposit(9900) $q$, 'not_enough_cash');
  i := bank_info();
  perform pg_temp.assert((i->'pos'->>'max_deposit')::int = 9750 and (i->'pos'->>'max_cashout')::int = 20540,
                         'bank_info max: ' || (i->'pos')::text);
  perform pos_deposit((i->'pos'->>'max_deposit')::bigint);
  perform pg_temp.assert(pg_temp.bk_money(v) = '0/30600', 'deposit max leaves 0 cash: ' || pg_temp.bk_money(v));
  perform pg_temp.bk_hint($q$ select pos_cashout(30200) $q$, 'not_enough_bank');
  perform pg_temp.bk_hint($q$ select pos_cashout(100001) $q$, 'bad_amount');
  perform pg_temp.bk_hint($q$ select pos_cashout(50) $q$, 'bad_amount');
  -- config-driven fee
  update game_config set value = '3' where key = 'pos.fee_pct';
  r := pos_cashout(10000);
  perform pg_temp.assert((r->>'fee')::int = 300 and pg_temp.bk_money(v) = '10000/20300', 'fee follows pos.fee_pct');
  update game_config set value = '1.5' where key = 'pos.fee_pct';
  -- only at a PoS stand (the bank counter is not a PoS)
  update profiles set location_id = 'bronze_bank' where id = v;
  perform pg_temp.bk_hint($q$ select pos_cashout(1000) $q$, 'not_here');
  update profiles set location_id = 'oba_market' where id = v;
  perform pg_temp.bk_hint($q$ select pos_deposit(1000) $q$, 'not_here');
  update profiles set location_id = 'ring_road_pos', busy_until = bl_now() + interval '1 hour' where id = v;
  perform pg_temp.bk_hint($q$ select pos_cashout(1000) $q$, 'busy');
  update profiles set busy_until = null where id = v;
  perform pos_cashout(1000);
  perform pg_temp.assert(pg_temp.bk_money(v) = '11000/19200', 'ring road PoS works');
  perform pg_temp.bk_hours(true);
  raise notice 'ok 3: PoS cash-out / deposit';
end $$;

-- ---------- 4. transfers ----------
do $$
declare
  a uuid := pg_temp.bk_make('Bank_Sender');
  b uuid := pg_temp.bk_make('Bank_Friend');
  r jsonb; m text; i jsonb; e events;
begin
  perform pg_temp.bk_at(b, 'ekenwan_room', 500, 1000);
  perform pg_temp.login(a);
  perform pg_temp.bk_at(a, 'uniben', 100, 50000);   -- anywhere: it's the phone
  r := bank_recipient('@bank_friend');
  perform pg_temp.assert(r->>'username' = 'Bank_Friend' and (r->>'id')::uuid = b, 'recipient lookup, case-insensitive, @ ok');
  perform pg_temp.bk_hint($q$ select bank_recipient('Bank_Sender') $q$, 'self');
  perform pg_temp.bk_hint($q$ select bank_recipient('nobody_here_xyz') $q$, 'unknown_player');

  r := bank_transfer('bank_friend', 5000, E'  for   chop\n o  ');
  perform pg_temp.assert(pg_temp.bk_money(a) = '100/44950', 'sender pays 5,000 + 50 fee: ' || pg_temp.bk_money(a));
  perform pg_temp.assert(pg_temp.bk_money(b) = '500/6000', 'friend gets 5,000 in the bank: ' || pg_temp.bk_money(b));
  perform pg_temp.assert((r->>'fee')::int = 50 and (r->>'bank')::int = 44950 and (r->>'sent_today')::int = 5000
                         and (r->>'left_today')::int = 195000 and r->>'message' ilike 'Sent ₦5,000 to @Bank_Friend.%', 'transfer result: ' || r::text);
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'transfer_out' and delta = -5000 and account = 'bank'
                                 and meta->>'to_username' = 'Bank_Friend' and meta->>'note' = 'for chop o'), 'transfer_out row + cleaned note');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = a and reason = 'transfer_fee' and delta = -50), 'transfer_fee row');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = b and reason = 'transfer_in' and delta = 5000 and account = 'bank'
                                 and meta->>'from_username' = 'Bank_Sender'), 'transfer_in row');
  select * into e from events where user_id = b and kind = 'transfer_in' order by id desc limit 1;
  perform pg_temp.assert(e.title = 'Money in from @Bank_Sender' and e.body = '₦5,000 landed in your bank. "for chop o"'
                         and (e.data->>'amount')::int = 5000, 'friend event: ' || coalesce(e.title || ' / ' || e.body, 'none'));
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'transfer_out' and body ilike '%₦5,000 to @Bank_Friend (fee ₦50)%'), 'sender event');

  -- refusals
  perform pg_temp.bk_hint($q$ select bank_transfer('Bank_Sender', 1000) $q$, 'self');
  perform pg_temp.bk_hint($q$ select bank_transfer('nobody_here_xyz', 1000) $q$, 'unknown_player');
  perform pg_temp.bk_hint($q$ select bank_transfer('', 1000) $q$, 'unknown_player');
  m := pg_temp.bk_hint($q$ select bank_transfer('Bank_Friend', 1000) $q$, 'limit');      -- cooldown
  perform pg_temp.assert(m ilike '%in % sec%', 'cooldown message: ' || m);
  perform pg_temp.bk_advance(16);
  perform pg_temp.bk_hint($q$ select bank_transfer('Bank_Friend', 99) $q$, 'bad_amount');
  perform pg_temp.bk_hint($q$ select bank_transfer('Bank_Friend', 44950) $q$, 'not_enough_bank');   -- fee does not fit
  update profiles set banned = true where id = b;
  perform pg_temp.bk_hint($q$ select bank_transfer('Bank_Friend', 1000) $q$, 'unknown_player');
  update profiles set banned = false where id = b;
  -- works while busy or travelling (phone), not from a police cell
  update profiles set busy_until = bl_now() + interval '1 hour', travel_to = 'oba_market' where id = a;
  perform bank_transfer('Bank_Friend', 1000);
  perform pg_temp.assert(pg_temp.bk_money(a) = '100/43900' and pg_temp.bk_money(b) = '500/7000', 'second transfer while busy');
  update profiles set busy_until = null, travel_to = null, jailed_until = bl_now() + interval '1 hour' where id = a;
  perform pg_temp.bk_advance(16);
  perform pg_temp.bk_hint($q$ select bank_transfer('Bank_Friend', 1000) $q$, 'jailed');
  update profiles set jailed_until = null where id = a;

  -- daily amount limit (game day), then a new game day resets it
  update game_config set value = '10000' where key = 'bank.transfer_daily_limit';
  m := pg_temp.bk_hint($q$ select bank_transfer('Bank_Friend', 4001) $q$, 'limit');
  perform pg_temp.assert(m ilike '%still send ₦4,000 today%', 'daily limit message: ' || m);
  i := bank_info();
  perform pg_temp.assert((i->'transfer'->>'sent_today')::int = 6000 and (i->'transfer'->>'left_today')::int = 4000
                         and (i->'transfer'->>'count_today')::int = 2, 'bank_info transfer stats: ' || (i->'transfer')::text);
  perform bank_transfer('Bank_Friend', 4000);
  -- daily count limit
  update game_config set value = '100000' where key = 'bank.transfer_daily_limit';
  update game_config set value = '3' where key = 'bank.transfer_daily_count';
  perform pg_temp.bk_advance(16);
  perform pg_temp.bk_hint($q$ select bank_transfer('Bank_Friend', 100) $q$, 'limit');
  perform pg_temp.bk_advance(2 * 3600);    -- one game day later (2 real hours at 12x)
  perform pg_temp.bk_at(a, 'uniben', 100, 39850);
  perform bank_transfer('Bank_Friend', 100);
  perform pg_temp.assert((bank_info()->'transfer'->>'count_today')::int = 1, 'new game day resets the counters');
  update game_config set value = '10' where key = 'bank.transfer_daily_count';
  -- no fee when the fee is 0
  update game_config set value = '0' where key = 'bank.transfer_fee';
  perform pg_temp.bk_advance(16);
  perform bank_transfer('Bank_Friend', 100);
  perform pg_temp.assert(pg_temp.bk_money(a) = '100/39600', 'fee 0 (and earlier fee 50): ' || pg_temp.bk_money(a));
  update game_config set value = '50' where key = 'bank.transfer_fee';

  -- new accounts wait
  update profiles set created_at = bl_now() - interval '10 minutes' where id = a;
  perform pg_temp.bk_advance(16);
  m := pg_temp.bk_hint($q$ select bank_transfer('Bank_Friend', 100) $q$, 'limit');
  perform pg_temp.assert(m ilike 'New accounts can send money after 30 real minutes. About 20 min to go.', 'new account message: ' || m);
  update game_config set value = '0' where key = 'bank.transfer_min_account_real_minutes';
  perform bank_transfer('Bank_Friend', 100);
  update game_config set value = '30' where key = 'bank.transfer_min_account_real_minutes';
  update profiles set created_at = bl_now() - interval '1 day' where id = a;
  raise notice 'ok 4: transfers';
end $$;

-- ---------- 5. history + labels ----------
do $$
declare a uuid := pg_temp.bk_u('Bank_Sender'); b uuid := pg_temp.bk_u('Bank_Friend'); h jsonb; x jsonb;
begin
  perform pg_temp.login(a);
  h := bank_history(5);
  perform pg_temp.assert(jsonb_array_length(h) = 5, '5 rows');
  perform pg_temp.assert(h->0->>'label' in ('Sent to @Bank_Friend', 'Transfer fee'), 'newest first: ' || (h->0)::text);
  perform pg_temp.assert(jsonb_array_length(bank_history(1000)) <= 100, 'capped at 100');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(bank_history(100)) y where (y->>'delta')::int = 0), 'no zero rows');
  select y into x from jsonb_array_elements(bank_history(100)) y where y->>'reason' = 'transfer_out' and y->>'note' = 'for chop o';
  perform pg_temp.assert(x is not null and x->>'label' = 'Sent to @Bank_Friend' and x->>'account' = 'bank' and (x->>'delta')::int = -5000, 'transfer_out label + note');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(bank_history(100)) y where y->>'label' = 'Starting money'), 'start label');
  perform pg_temp.login(b);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(bank_history(100)) y where y->>'label' = 'From @Bank_Sender'
                                 and (y->>'delta')::int = 5000), 'friend sees From @Bank_Sender');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(bank_history(100)) y where y->>'reason' = 'transfer_fee'), 'only own rows');
  perform pg_temp.login(pg_temp.bk_u('Bank_A'));
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(bank_history(100)) y where y->>'label' = 'PoS charge'), 'PoS charge label');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(bank_history(100)) y where y->>'label' = 'Deposit · Bronze Bank (GRA)'), 'deposit label');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(bank_history(100)) y where y->>'label' = 'PoS cash-out · Sapele Road PoS Stand'), 'cash-out label');
  perform pg_temp.assert(bl_ledger_label('salary', '{"track":"tech","level":1}') ilike 'Salary · %', 'salary label');
  perform pg_temp.assert(bl_ledger_label('travel', '{"mode":"keke"}') = 'Transport · keke', 'travel label');
  perform pg_temp.assert(bl_ledger_label('mystery_thing', '{}') = 'Mystery Thing', 'fallback label');
  -- bank_info basics
  perform pg_temp.assert((bank_info()->>'tip_cash_threshold')::int > 0 and jsonb_array_length(bank_info()->'places') >= 4
                         and bank_info()->'places'->0->>'kind' = 'bank', 'bank_info places (bank first)');
  raise notice 'ok 5: history + labels';
end $$;

-- ---------- 6. street robbery takes cash only ----------
do $$
declare v uuid := pg_temp.bk_u('Bank_A'); r jsonb;
begin
  perform pg_temp.login(v);
  perform pg_temp.bk_at(v, 'third_east', 40000, 300000);
  update profiles set protected_until = null, charm_strength = 0 where id = v;
  perform set_config('bl.test_rand', '0.0001', true);
  r := bl_roll_street_robbery(v, 'third_east', 'walk', 1);
  perform set_config('bl.test_rand', '', true);
  perform pg_temp.assert(r is not null and (r->>'amount')::int > 0, 'robbed: ' || coalesce(r::text, 'null'));
  perform pg_temp.assert((select bank from profiles where id = v) = 300000, 'bank untouched by robbery');
  perform pg_temp.assert((select cash from profiles where id = v) = 40000 - (r->>'amount')::int, 'cash took the hit');
  -- no cash, no robbery (bank does not count)
  update profiles set cash = 0 where id = v;
  perform pg_temp.assert(bl_street_robbery_chance(v, 'third_east', 'walk', 1, bl_now()) = 0, 'zero chance with only bank money');
  raise notice 'ok 6: robbery takes cash only';
end $$;

do $$ begin raise notice 'bank_test: all groups passed'; end $$;

-- L1: back to the shipped defaults (real clock, short actions) for the next test file.
update game_config set value = '"real"' where key = 'clock.mode';
update game_config set value = '"short"' where key = 'action.mode';
