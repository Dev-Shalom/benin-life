-- Benin Life — V1-5 "Bank": deposit / withdraw at Bronze Bank (banking hours), PoS cash-out and
-- deposit with a fee (any hour), player-to-player transfers from the phone, and a money history.
-- docs/BANK.md is the spec. Safe on a non-empty DB and idempotent:
-- * config rows use `on conflict do nothing` (admin values survive a re-run);
-- * functions are `create or replace`; the one index uses `if not exists`.
--
-- Money rules that already hold (DB_CORE): street robbery takes CASH only, so money in the bank is
-- safe; salary is paid to cash (CAREERS); ChopNow and rent pay from the bank first (SHOPS).
--
-- Ledger reasons written here: bank_deposit, bank_withdraw (both accounts, one row each),
-- pos_cashout, pos_deposit, pos_fee, transfer_out, transfer_fee, transfer_in.

-- ---------------------------------------------------------------------
-- 1. Config (categories `bank` and `pos`; all admin-tunable)
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('bank.open_hour', '8', 'bank', 'Bank opens (game hour)',
 'Bronze Bank counter opens at this game hour (0-23). If it equals the closing hour the bank never closes.', 'number', 0, 23),
('bank.close_hour', '16', 'bank', 'Bank closes (game hour)',
 'Bronze Bank counter closes at this game hour (1-24). After hours players use a PoS stand (with a fee).', 'number', 1, 24),
('bank.min_amount', '100', 'bank', 'Smallest deposit / withdrawal',
 'The smallest amount for a deposit, withdrawal, PoS cash-out or PoS deposit.', 'naira', 1, 100000),
('bank.transfer_fee', '50', 'bank', 'Transfer fee',
 'Flat fee taken from the sender''s bank for each phone transfer to another player.', 'naira', 0, 10000),
('bank.transfer_min_amount', '100', 'bank', 'Smallest transfer',
 'The smallest amount a player can send to another player.', 'naira', 1, 100000),
('bank.transfer_daily_limit', '200000', 'bank', 'Daily transfer limit',
 'The most a player can send to other players per game day (fees not counted).', 'naira', 0, 100000000),
('bank.transfer_daily_count', '10', 'bank', 'Transfers per game day',
 'How many transfers a player can send per game day.', 'number', 0, 1000),
('bank.transfer_cooldown_real_seconds', '15', 'bank', 'Wait between transfers (real seconds)',
 'Rate limit: real seconds a player must wait between two transfers.', 'number', 0, 3600),
('bank.transfer_min_account_real_minutes', '30', 'bank', 'New accounts wait before sending (real minutes)',
 'A brand-new Sim can only send transfers after this many real minutes (slows down alt-account money farming). 0 = no wait.', 'minutes', 0, 10080),
('bank.tip_cash_threshold', '20000', 'bank', 'Bank tip: cash on hand',
 'At night, players carrying more cash than this see a "Bank your cash" tip (thieves take a share of cash, never bank money).', 'naira', 0, 10000000),
('pos.fee_pct', '1.5', 'pos', 'PoS charge (percent)',
 'PoS cash-out and deposit charge = this percent of the amount (at least the minimum charge), rounded up to ₦10, paid on top.', 'percent', 0, 20),
('pos.fee_min', '100', 'pos', 'PoS minimum charge',
 'The smallest PoS charge per cash-out or deposit.', 'naira', 0, 10000),
('pos.max_amount', '100000', 'pos', 'PoS max per transaction',
 'The most a PoS stand will pay out or take in one go (the operator only carries so much cash).', 'naira', 100, 100000000)
on conflict (key) do nothing;

-- Transfers per sender per day (rate limits read this).
create index if not exists ledger_transfer_out_idx on public.ledger (user_id, created_at desc) where reason = 'transfer_out';

-- ---------------------------------------------------------------------
-- 2. Helpers (internal)
-- ---------------------------------------------------------------------
-- '8:00 AM', '4:00 PM', '12:00 midnight' for whole game hours.
create or replace function public.bl_hour_text(p_hour int) returns text
language sql immutable as $$
  select case
    when ((p_hour % 24) + 24) % 24 = 0 then '12:00 midnight'
    when ((p_hour % 24) + 24) % 24 = 12 then '12:00 noon'
    when ((p_hour % 24) + 24) % 24 < 12 then (((p_hour % 24) + 24) % 24) || ':00 AM'
    else (((p_hour % 24) + 24) % 24 - 12) || ':00 PM' end
$$;

-- Is the bank counter open at this game clock? open == close means always open; open > close wraps midnight.
create or replace function public.bl_bank_open(p_clock jsonb) returns boolean
language plpgsql stable set search_path = public as $$
declare
  o int := bl_cfg('bank.open_hour')::int;
  c int := bl_cfg('bank.close_hour')::int;
  h int := (p_clock->>'hour')::int;
begin
  if o = c or (o = 0 and c >= 24) then return true; end if;
  if o < c then return h >= o and h < c; end if;
  return h >= o or h < c;
end $$;

-- Game minutes until the bank opens (0 when open).
create or replace function public.bl_bank_opens_in(p_clock jsonb) returns int
language plpgsql stable set search_path = public as $$
declare
  o  int := bl_cfg('bank.open_hour')::int;
  gm int := (p_clock->>'hour')::int * 60 + (p_clock->>'minute')::int;
begin
  if bl_bank_open(p_clock) then return 0; end if;
  return ((o * 60 - gm) % 1440 + 1440) % 1440;
end $$;

-- PoS charge for an amount: max(min, pct %) rounded up to ₦10.
create or replace function public.bl_pos_fee(p_amount bigint) returns bigint
language plpgsql stable set search_path = public as $$
begin
  return (ceil(greatest(bl_cfg('pos.fee_min'), p_amount * bl_cfg('pos.fee_pct') / 100.0) / 10.0) * 10)::bigint;
end $$;

-- Largest amount a with a + fee(a) <= balance, capped at pos.max_amount (0 if under the minimum).
create or replace function public.bl_pos_max(p_balance bigint) returns bigint
language plpgsql stable set search_path = public as $$
declare
  v_cap bigint := bl_cfg('pos.max_amount')::bigint;
  v_min bigint := bl_cfg('bank.min_amount')::bigint;
  a     bigint;
  i     int := 0;
begin
  if p_balance <= 0 then return 0; end if;
  a := least(v_cap, p_balance - bl_pos_fee(least(p_balance, v_cap)));
  -- fee is non-decreasing, so a fits; nudge up while the next naira still fits
  while i < 200 and a + 1 <= v_cap and (a + 1) + bl_pos_fee(a + 1) <= p_balance loop
    a := a + 1; i := i + 1;
  end loop;
  return case when a < v_min then 0 else a end;
end $$;

-- Raise bad_amount unless p_amount is a whole number from p_min to p_max.
create or replace function public.bl_check_amount(p_amount bigint, p_min bigint, p_max bigint default null) returns void
language plpgsql stable set search_path = public as $$
begin
  if p_amount is null or p_amount < p_min then
    raise exception 'Enter an amount of at least %.', bl_naira(p_min) using errcode = 'P0001', hint = 'bad_amount';
  end if;
  if p_max is not null and p_amount > p_max then
    raise exception 'That''s too much in one go. The most is % per transaction.', bl_naira(p_max)
      using errcode = 'P0001', hint = 'bad_amount';
  end if;
end $$;

-- 'Ring Road PoS Line, New Benin PoS Junction or Sapele Road PoS Stand' for an action id.
create or replace function public.bl_places_with(p_action text, p_limit int default 3) returns text
language plpgsql stable set search_path = public as $$
declare v text[];
begin
  select array_agg(name order by sort, id) into v
    from (select name, sort, id from locations where p_action = any (actions) order by sort, id limit p_limit) x;
  if v is null then return null; end if;
  if cardinality(v) = 1 then return v[1]; end if;
  return array_to_string(v[1:cardinality(v) - 1], ', ') || ' or ' || v[cardinality(v)];
end $$;

-- Friendly label for a ledger row (history list).
create or replace function public.bl_ledger_label(p_reason text, p_meta jsonb) returns text
language plpgsql stable set search_path = public as $$
declare v text;
begin
  case p_reason
    when 'salary' then
      select 'Salary · ' || title into v from career_levels
       where track_id = p_meta->>'track' and level = (p_meta->>'level')::int;
      return coalesce(v, 'Salary');
    when 'shop' then
      select name into v from items where id = p_meta->>'item';
      return 'Bought ' || coalesce(v, 'something');
    when 'shop_sell' then
      select name into v from items where id = p_meta->>'item';
      return 'Sold ' || coalesce(v, 'something');
    when 'food_delivery' then
      select name into v from items where id = p_meta->>'item';
      return 'ChopNow · ' || coalesce(v, 'food');
    when 'activity' then
      select name into v from activities where id = p_meta->>'activity';
      return coalesce(v, 'Activity');
    when 'travel' then
      return 'Transport · ' || case p_meta->>'mode' when 'keke' then 'keke' when 'bus' then 'bus'
                                    when 'drop' then 'drop taxi' when 'car' then 'fuel' else 'fare' end;
    when 'rent' then return case when (p_meta->>'settle')::boolean then 'Rent paid (owed)' else 'Rent' end;
    when 'street_robbery' then return 'Robbed on the street';
    when 'start_bonus' then return 'Starting money';
    when 'allowance' then return 'Dad''s allowance';
    when 'admin_origin' then return 'Account adjustment';
    when 'bank_deposit' then
      select name into v from locations where id = p_meta->>'location';
      return 'Deposit · ' || coalesce(v, 'bank');
    when 'bank_withdraw' then
      select name into v from locations where id = p_meta->>'location';
      return 'Withdrawal · ' || coalesce(v, 'bank');
    when 'pos_cashout' then
      select name into v from locations where id = p_meta->>'location';
      return 'PoS cash-out' || coalesce(' · ' || v, '');
    when 'pos_deposit' then
      select name into v from locations where id = p_meta->>'location';
      return 'PoS deposit' || coalesce(' · ' || v, '');
    when 'pos_fee' then return 'PoS charge';
    when 'transfer_out' then return 'Sent to @' || coalesce(p_meta->>'to_username', 'player');
    when 'transfer_in' then return 'From @' || coalesce(p_meta->>'from_username', 'player');
    when 'transfer_fee' then return 'Transfer fee';
    else return initcap(replace(coalesce(p_reason, 'money'), '_', ' '));
  end case;
end $$;

-- Today's (game day) transfers for a sender: {day, sent, count, last_at}.
create or replace function public.bl_transfer_stats(p_uid uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_day bigint := (bl_game_clock()->>'day')::bigint;
  v     jsonb;
begin
  -- a game day is at most 24 h / clock speed of real time; 2 real days covers any sane speed
  select jsonb_build_object('day', v_day,
           'sent', coalesce(sum(-delta) filter (where (meta->>'day')::bigint = v_day), 0),
           'count', count(*) filter (where (meta->>'day')::bigint = v_day),
           'last_at', max(created_at))
    into v
    from ledger
   where user_id = p_uid and reason = 'transfer_out' and created_at > bl_now() - interval '2 days';
  return v;
end $$;

-- A player by username (case-insensitive, leading @ ignored). Banned players can't receive.
create or replace function public.bl_find_player(p_username text) returns public.profiles
language plpgsql stable set search_path = public as $$
declare
  v_name text := ltrim(btrim(coalesce(p_username, '')), '@');
  r      profiles;
begin
  if v_name = '' then
    raise exception 'Type the username of the player you want to pay.' using errcode = 'P0001', hint = 'unknown_player';
  end if;
  select * into r from profiles where lower(username) = lower(v_name) and not banned;
  if not found then
    raise exception 'There''s no player called @%. Check the spelling of their username.', v_name
      using errcode = 'P0001', hint = 'unknown_player';
  end if;
  return r;
end $$;

-- Shared guard for the counter RPCs: at a place with p_action, free to act.
create or replace function public.bl_assert_at(p_me public.profiles, p_action text) returns public.locations
language plpgsql stable set search_path = public as $$
declare l locations; v_where text;
begin
  perform bl_assert_free(p_me);
  l := bl_location(p_me.location_id);
  if not (p_action = any (l.actions)) then
    v_where := bl_places_with(p_action);
    if p_action = 'bank' then
      raise exception 'You need to be at the bank counter for that. Go to %, or use a PoS stand (small charge).',
        coalesce(v_where, 'Bronze Bank') using errcode = 'P0001', hint = 'not_here';
    end if;
    raise exception 'There''s no PoS stand here. Try %.', coalesce(v_where, 'a PoS stand')
      using errcode = 'P0001', hint = 'not_here';
  end if;
  return l;
end $$;

-- Bank counter open, else a clear "closed" error that points at the PoS stands.
create or replace function public.bl_assert_bank_open(p_name text) returns void
language plpgsql stable set search_path = public as $$
declare
  v_clock jsonb := bl_game_clock();
  v_in    int;
  v_real  numeric;
begin
  if bl_bank_open(v_clock) then return; end if;
  v_in := bl_bank_opens_in(v_clock);
  v_real := v_in * 60.0 / greatest(bl_cfg('clock.game_minutes_per_real_minute'), 0.0001);
  raise exception '% is closed. Banking hours are % to % (game time); it opens in about % (% real). After hours, a PoS stand can help: %.',
    p_name, bl_hour_text(bl_cfg('bank.open_hour')::int), bl_hour_text(bl_cfg('bank.close_hour')::int),
    case when v_in >= 60 then round(v_in / 60.0) || ' hr' || case when round(v_in / 60.0) = 1 then '' else 's' end
         else v_in || ' min' end,
    case when v_real >= 60 then ceil(v_real / 60) || ' min' else ceil(v_real) || ' sec' end,
    coalesce(bl_places_with('pos'), 'any PoS stand')
    using errcode = 'P0001', hint = 'closed';
end $$;

-- ---------------------------------------------------------------------
-- 3. Read RPCs
-- ---------------------------------------------------------------------
-- Everything the Bank / PoS panels and the phone Bank app show. Read-only.
create or replace function public.bank_info() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_me    profiles;
  v_clock jsonb := bl_game_clock();
  v_in    int;
  v_st    jsonb;
  v_limit bigint := bl_cfg('bank.transfer_daily_limit')::bigint;
  v_wait  numeric;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  v_in := bl_bank_opens_in(v_clock);
  v_st := bl_transfer_stats(v_uid);
  v_wait := greatest(0, bl_cfg('bank.transfer_min_account_real_minutes') * 60
                         - extract(epoch from bl_now() - v_me.created_at));
  return jsonb_build_object(
    'cash', v_me.cash, 'bank', v_me.bank,
    'min_amount', bl_cfg('bank.min_amount'),
    'bank_hours', jsonb_build_object(
      'open_hour', bl_cfg('bank.open_hour'), 'close_hour', bl_cfg('bank.close_hour'),
      'open', v_in = 0, 'opens_in_game_minutes', v_in,
      'opens_in_real_seconds', ceil(v_in * 60.0 / greatest(bl_cfg('clock.game_minutes_per_real_minute'), 0.0001))),
    'pos', jsonb_build_object(
      'fee_pct', bl_cfg('pos.fee_pct'), 'fee_min', bl_cfg('pos.fee_min'), 'max_amount', bl_cfg('pos.max_amount'),
      'max_cashout', bl_pos_max(v_me.bank), 'max_deposit', bl_pos_max(v_me.cash)),
    'transfer', jsonb_build_object(
      'fee', bl_cfg('bank.transfer_fee'), 'min_amount', bl_cfg('bank.transfer_min_amount'),
      'daily_limit', v_limit, 'sent_today', (v_st->>'sent')::bigint,
      'left_today', greatest(0, v_limit - (v_st->>'sent')::bigint),
      'count_today', (v_st->>'count')::int, 'daily_count', bl_cfg('bank.transfer_daily_count'),
      'cooldown_real_seconds', bl_cfg('bank.transfer_cooldown_real_seconds'),
      'new_account_wait_real_seconds', ceil(v_wait)),
    'tip_cash_threshold', bl_cfg('bank.tip_cash_threshold'),
    'places', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'district', district,
                                         'kind', case when 'bank' = any (actions) then 'bank' else 'pos' end)
                                         order by ('bank' = any (actions)) desc, sort, id)
                          from locations where 'bank' = any (actions) or 'pos' = any (actions)), '[]'::jsonb));
end $$;

-- Check a transfer recipient before the confirm step. Read-only.
create or replace function public.bank_recipient(p_username text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); r profiles;
begin
  r := bl_find_player(p_username);
  if r.id = v_uid then
    raise exception 'That''s you. Pick another player.' using errcode = 'P0001', hint = 'self';
  end if;
  return jsonb_build_object('id', r.id, 'username', r.username, 'avatar', r.avatar);
end $$;

-- Recent money movements (both accounts), newest first, with friendly labels. Read-only.
create or replace function public.bank_history(p_limit int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', id, 'account', account, 'delta', delta, 'balance_after', balance_after, 'reason', reason,
             'label', bl_ledger_label(reason, meta), 'note', nullif(meta->>'note', ''), 'created_at', created_at)
           order by created_at desc, id desc)
      from (select * from ledger where user_id = v_uid
             order by created_at desc, id desc
             limit greatest(1, least(coalesce(p_limit, 30), 100))) x), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- 4. Counter RPCs: Bronze Bank (banking hours, free) and PoS stands (any hour, fee)
-- ---------------------------------------------------------------------
create or replace function public.bank_deposit(p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  l      locations := bl_assert_at(v_me, 'bank');
  v_bank bigint;
  v_cash bigint;
  v_meta jsonb;
begin
  perform bl_assert_bank_open(l.name);
  perform bl_check_amount(p_amount, bl_cfg('bank.min_amount')::bigint);
  if p_amount > v_me.cash then
    raise exception 'Not enough cash. You want to deposit % but you have % on you.', bl_naira(p_amount), bl_naira(v_me.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_meta := jsonb_build_object('location', l.id);
  v_cash := bl_add_money(v_me.id, 'cash', -p_amount, 'bank_deposit', v_meta);
  v_bank := bl_add_money(v_me.id, 'bank', p_amount, 'bank_deposit', v_meta);
  return jsonb_build_object(
    'message', 'You deposited ' || bl_naira(p_amount) || '. Bank balance: ' || bl_naira(v_bank)
               || '. Street thieves can''t touch it now.',
    'amount', p_amount, 'cash', v_cash, 'bank', v_bank);
end $$;

create or replace function public.bank_withdraw(p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  l      locations := bl_assert_at(v_me, 'bank');
  v_bank bigint;
  v_cash bigint;
  v_meta jsonb;
begin
  perform bl_assert_bank_open(l.name);
  perform bl_check_amount(p_amount, bl_cfg('bank.min_amount')::bigint);
  if p_amount > v_me.bank then
    raise exception 'Not enough money in the bank. You want % but your balance is %.', bl_naira(p_amount), bl_naira(v_me.bank)
      using errcode = 'P0001', hint = 'not_enough_bank';
  end if;
  v_meta := jsonb_build_object('location', l.id);
  v_bank := bl_add_money(v_me.id, 'bank', -p_amount, 'bank_withdraw', v_meta);
  v_cash := bl_add_money(v_me.id, 'cash', p_amount, 'bank_withdraw', v_meta);
  return jsonb_build_object(
    'message', 'You withdrew ' || bl_naira(p_amount) || '. Cash on you: ' || bl_naira(v_cash)
               || '. Careful on the road with it.',
    'amount', p_amount, 'cash', v_cash, 'bank', v_bank);
end $$;

-- Small talk from the PoS operator (deterministic pick, no bl_rand so tests stay stable).
create or replace function public.bl_pos_banter() returns text
language sql stable set search_path = public as $$
  select (array['"Network dey today, thank God."',
                '"Count am well o, no story later."',
                '"Na alert remain. E don land."',
                '"Next customer!"'])[1 + (floor(extract(epoch from bl_now()))::bigint % 4)::int]
$$;

-- PoS cash-out: the bank pays amount + charge, you get amount in cash.
create or replace function public.pos_cashout(p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  l      locations := bl_assert_at(v_me, 'pos');
  v_fee  bigint;
  v_bank bigint;
  v_cash bigint;
  v_meta jsonb;
begin
  perform bl_check_amount(p_amount, bl_cfg('bank.min_amount')::bigint, bl_cfg('pos.max_amount')::bigint);
  v_fee := bl_pos_fee(p_amount);
  if p_amount + v_fee > v_me.bank then
    raise exception 'Not enough in your bank. Cashing out % costs % with the % charge, and your balance is %.',
      bl_naira(p_amount), bl_naira(p_amount + v_fee), bl_naira(v_fee), bl_naira(v_me.bank)
      using errcode = 'P0001', hint = 'not_enough_bank';
  end if;
  v_meta := jsonb_build_object('location', l.id, 'amount', p_amount, 'fee', v_fee);
  perform bl_add_money(v_me.id, 'bank', -p_amount, 'pos_cashout', v_meta);
  v_bank := bl_add_money(v_me.id, 'bank', -v_fee, 'pos_fee', v_meta || jsonb_build_object('kind', 'cashout'));
  v_cash := bl_add_money(v_me.id, 'cash', p_amount, 'pos_cashout', v_meta);
  return jsonb_build_object(
    'message', bl_pos_banter() || ' You got ' || bl_naira(p_amount) || ' cash. Charge: ' || bl_naira(v_fee) || '.',
    'amount', p_amount, 'fee', v_fee, 'cash', v_cash, 'bank', v_bank);
end $$;

-- PoS deposit: you hand over amount + charge in cash, amount lands in your bank.
create or replace function public.pos_deposit(p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  l      locations := bl_assert_at(v_me, 'pos');
  v_fee  bigint;
  v_bank bigint;
  v_cash bigint;
  v_meta jsonb;
begin
  perform bl_check_amount(p_amount, bl_cfg('bank.min_amount')::bigint, bl_cfg('pos.max_amount')::bigint);
  v_fee := bl_pos_fee(p_amount);
  if p_amount + v_fee > v_me.cash then
    raise exception 'Not enough cash. Depositing % costs % with the % charge, and you have % on you.',
      bl_naira(p_amount), bl_naira(p_amount + v_fee), bl_naira(v_fee), bl_naira(v_me.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_meta := jsonb_build_object('location', l.id, 'amount', p_amount, 'fee', v_fee);
  perform bl_add_money(v_me.id, 'cash', -p_amount, 'pos_deposit', v_meta);
  v_cash := bl_add_money(v_me.id, 'cash', -v_fee, 'pos_fee', v_meta || jsonb_build_object('kind', 'deposit'));
  v_bank := bl_add_money(v_me.id, 'bank', p_amount, 'pos_deposit', v_meta);
  return jsonb_build_object(
    'message', bl_pos_banter() || ' ' || bl_naira(p_amount) || ' sent to your bank. Charge: ' || bl_naira(v_fee) || '.',
    'amount', p_amount, 'fee', v_fee, 'cash', v_cash, 'bank', v_bank);
end $$;

-- ---------------------------------------------------------------------
-- 5. Phone transfer to another player (bank to bank)
-- ---------------------------------------------------------------------
create or replace function public.bank_transfer(p_username text, p_amount bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  r       profiles := bl_find_player(p_username);
  v_me    profiles;
  v_now   timestamptz := bl_now();
  v_fee   bigint := bl_cfg('bank.transfer_fee')::bigint;
  v_limit bigint := bl_cfg('bank.transfer_daily_limit')::bigint;
  v_max   int := bl_cfg('bank.transfer_daily_count')::int;
  v_cool  numeric := bl_cfg('bank.transfer_cooldown_real_seconds');
  v_age   numeric := bl_cfg('bank.transfer_min_account_real_minutes') * 60;
  v_st    jsonb;
  v_left  numeric;
  v_note  text;
  v_bank  bigint;
  v_day   bigint;
  v_meta  jsonb;
begin
  if r.id = v_uid then
    raise exception 'You can''t send money to yourself.' using errcode = 'P0001', hint = 'self';
  end if;
  -- lock both rows in a fixed order (no deadlock when two players pay each other at once)
  perform 1 from profiles where id in (v_uid, r.id) order by id for update;
  v_me := bl_me();
  if v_me.jailed_until is not null and v_me.jailed_until > v_now then
    raise exception 'The police took your phone. Transfers can wait until you are out.' using errcode = 'P0001', hint = 'jailed';
  end if;
  v_left := v_age - extract(epoch from v_now - v_me.created_at);
  if v_left > 0 then
    raise exception 'New accounts can send money after % real minutes. About % min to go.',
      round(v_age / 60), ceil(v_left / 60) using errcode = 'P0001', hint = 'limit';
  end if;
  perform bl_check_amount(p_amount, bl_cfg('bank.transfer_min_amount')::bigint);
  v_st := bl_transfer_stats(v_me.id);
  v_day := (v_st->>'day')::bigint;
  if v_st->>'last_at' is not null then
    v_left := v_cool - extract(epoch from v_now - (v_st->>'last_at')::timestamptz);
    if v_left > 0 then
      raise exception 'Slow down a little. You can send another transfer in % sec.', ceil(v_left)
        using errcode = 'P0001', hint = 'limit';
    end if;
  end if;
  if (v_st->>'count')::int >= v_max then
    raise exception 'You have reached today''s limit of % transfers. Try again tomorrow (game time).', v_max
      using errcode = 'P0001', hint = 'limit';
  end if;
  if (v_st->>'sent')::bigint + p_amount > v_limit then
    raise exception 'That''s over your daily transfer limit of %. You can still send % today (game time).',
      bl_naira(v_limit), bl_naira(greatest(0, v_limit - (v_st->>'sent')::bigint))
      using errcode = 'P0001', hint = 'limit';
  end if;
  if p_amount + v_fee > v_me.bank then
    raise exception 'Not enough in your bank. Sending % costs % with the % fee, and your balance is %. Deposit cash at Bronze Bank or a PoS stand first.',
      bl_naira(p_amount), bl_naira(p_amount + v_fee), bl_naira(v_fee), bl_naira(v_me.bank)
      using errcode = 'P0001', hint = 'not_enough_bank';
  end if;

  -- note: one line, printable, at most 80 characters
  v_note := nullif(left(btrim(regexp_replace(coalesce(p_note, ''), '[[:cntrl:][:space:]]+', ' ', 'g')), 80), '');
  v_meta := jsonb_build_object('to', r.id, 'to_username', r.username, 'from', v_me.id,
                               'from_username', v_me.username, 'day', v_day)
            || case when v_note is null then '{}'::jsonb else jsonb_build_object('note', v_note) end;
  perform bl_add_money(v_me.id, 'bank', -p_amount, 'transfer_out', v_meta);
  v_bank := v_me.bank - p_amount;
  if v_fee > 0 then
    v_bank := bl_add_money(v_me.id, 'bank', -v_fee, 'transfer_fee', jsonb_build_object('to_username', r.username, 'amount', p_amount));
  end if;
  perform bl_add_money(r.id, 'bank', p_amount, 'transfer_in', v_meta);

  perform bl_event(r.id, 'transfer_in', 'Money in from @' || v_me.username,
    bl_naira(p_amount) || ' landed in your bank.' || coalesce(' "' || v_note || '"', ''),
    v_meta || jsonb_build_object('amount', p_amount));
  perform bl_event(v_me.id, 'transfer_out', 'Transfer sent',
    'You sent ' || bl_naira(p_amount) || ' to @' || r.username || case when v_fee > 0 then ' (fee ' || bl_naira(v_fee) || ').' else '.' end,
    v_meta || jsonb_build_object('amount', p_amount, 'fee', v_fee));

  return jsonb_build_object(
    'message', 'Sent ' || bl_naira(p_amount) || ' to @' || r.username || '.'
               || case when v_fee > 0 then ' Fee: ' || bl_naira(v_fee) || '.' else '' end
               || ' Bank balance: ' || bl_naira(v_bank) || '.',
    'amount', p_amount, 'fee', v_fee, 'bank', v_bank,
    'to', jsonb_build_object('id', r.id, 'username', r.username),
    'sent_today', (v_st->>'sent')::bigint + p_amount,
    'left_today', greatest(0, v_limit - (v_st->>'sent')::bigint - p_amount));
end $$;

-- ---------------------------------------------------------------------
-- 6. Privileges
-- ---------------------------------------------------------------------
revoke execute on function public.bl_hour_text(int)                         from public, anon, authenticated;
revoke execute on function public.bl_bank_open(jsonb)                       from public, anon, authenticated;
revoke execute on function public.bl_bank_opens_in(jsonb)                   from public, anon, authenticated;
revoke execute on function public.bl_pos_fee(bigint)                        from public, anon, authenticated;
revoke execute on function public.bl_pos_max(bigint)                        from public, anon, authenticated;
revoke execute on function public.bl_check_amount(bigint, bigint, bigint)   from public, anon, authenticated;
revoke execute on function public.bl_places_with(text, int)                 from public, anon, authenticated;
revoke execute on function public.bl_ledger_label(text, jsonb)              from public, anon, authenticated;
revoke execute on function public.bl_transfer_stats(uuid)                   from public, anon, authenticated;
revoke execute on function public.bl_find_player(text)                      from public, anon, authenticated;
revoke execute on function public.bl_assert_at(public.profiles, text)       from public, anon, authenticated;
revoke execute on function public.bl_assert_bank_open(text)                 from public, anon, authenticated;
revoke execute on function public.bl_pos_banter()                           from public, anon, authenticated;

revoke execute on function public.bank_info()                          from public, anon;
revoke execute on function public.bank_recipient(text)                 from public, anon;
revoke execute on function public.bank_history(int)                    from public, anon;
revoke execute on function public.bank_deposit(bigint)                 from public, anon;
revoke execute on function public.bank_withdraw(bigint)                from public, anon;
revoke execute on function public.pos_cashout(bigint)                  from public, anon;
revoke execute on function public.pos_deposit(bigint)                  from public, anon;
revoke execute on function public.bank_transfer(text, bigint, text)    from public, anon;
grant execute on function public.bank_info()                           to authenticated;
grant execute on function public.bank_recipient(text)                  to authenticated;
grant execute on function public.bank_history(int)                     to authenticated;
grant execute on function public.bank_deposit(bigint)                  to authenticated;
grant execute on function public.bank_withdraw(bigint)                 to authenticated;
grant execute on function public.pos_cashout(bigint)                   to authenticated;
grant execute on function public.pos_deposit(bigint)                   to authenticated;
grant execute on function public.bank_transfer(text, bigint, text)     to authenticated;
