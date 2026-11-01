-- Fix it 9: phone banking. Deposit and withdraw from the Bank app anywhere, any time, for a small fee.
--   fee = max(bank.phone_fee_min, bank.phone_fee_pct % of the amount), rounded up to N10, paid ON TOP from the account the money leaves
--   (a deposit pays the fee from cash, a withdrawal from the bank) and gone from the economy (ledger reason phone_bank_fee, a sink).
--   Limits kept from the other cash points: bank.min_amount, and a per-go maximum bank.phone_max_amount (default = the PoS maximum, 0 = none).
--   In person at Bronze Bank in banking hours stays FREE (bank_deposit / bank_withdraw are untouched); PoS stands are untouched.
--   Works while busy or travelling like transfers; refused in a police cell. No profiles change, nothing is looped over players.
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('bank.phone_enabled',   'true',   'bank', 'Phone banking on',
 'Fix it 9: deposit and withdraw from the Bank app anywhere, any time, for a fee. Off = only Bronze Bank counters and PoS stands.', 'bool', null, null),
('bank.phone_fee_pct',   '1',      'bank', 'Phone banking fee (%)',
 'Fix it 9: percent of the amount, paid on top. In person at Bronze Bank in opening hours is free.', 'number', 0, 20),
('bank.phone_fee_min',   '50',     'bank', 'Phone banking fee, minimum (N)',
 'Fix it 9: the fee is never less than this (rounded up to N10).', 'number', 0, 100000),
('bank.phone_max_amount','100000', 'bank', 'Phone banking: most per go (N)',
 'Fix it 9: same as the PoS maximum by default so the phone is not a loophole around the PoS limit. 0 = no limit.', 'number', 0, 1000000000000)
on conflict (key) do nothing;

create or replace function public.bl_phone_fee(p_amount bigint) returns bigint
language sql stable set search_path = public as $$
  select (ceil(greatest(coalesce(bl_cfg('bank.phone_fee_min'), 50), p_amount * coalesce(bl_cfg('bank.phone_fee_pct'), 1) / 100.0) / 10.0) * 10)::bigint
$$;

create or replace function public.bl_phone_bank_check(p_me profiles, p_amount bigint) returns void
language plpgsql stable set search_path = public as $$
declare v_max bigint := coalesce(bl_cfg('bank.phone_max_amount'), 0)::bigint;
begin
  if not coalesce(bl_cfg_bool('bank.phone_enabled'), true) then
    raise exception 'Phone banking is off for now. Use Bronze Bank or a PoS stand.' using errcode = 'P0001', hint = 'phone_off';
  end if;
  if p_me.jailed_until is not null and p_me.jailed_until > bl_now() then
    raise exception 'The police took your phone. Banking can wait until you are out.' using errcode = 'P0001', hint = 'jailed';
  end if;
  perform bl_check_amount(p_amount, bl_cfg('bank.min_amount')::bigint, nullif(v_max, 0));
end $$;

create or replace function public.phone_bank_info() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me profiles := bl_me();
begin
  return jsonb_build_object(
    'enabled', coalesce(bl_cfg_bool('bank.phone_enabled'), true),
    'fee_pct', coalesce(bl_cfg('bank.phone_fee_pct'), 1), 'fee_min', coalesce(bl_cfg('bank.phone_fee_min'), 50),
    'max_amount', coalesce(bl_cfg('bank.phone_max_amount'), 0), 'min_amount', bl_cfg('bank.min_amount'),
    'cash', v_me.cash, 'bank', v_me.bank);
end $$;

-- cash -> bank from anywhere
create or replace function public.phone_bank_deposit(p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); v_fee bigint; v_cash bigint; v_bank bigint; v_meta jsonb;
begin
  perform bl_phone_bank_check(v_me, p_amount);
  v_fee := bl_phone_fee(p_amount);
  if p_amount + v_fee > v_me.cash then
    raise exception 'Not enough cash. Depositing % costs % with the % phone fee, and you have % on you.',
      bl_naira(p_amount), bl_naira(p_amount + v_fee), bl_naira(v_fee), bl_naira(v_me.cash) using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_meta := jsonb_build_object('amount', p_amount, 'fee', v_fee, 'via', 'phone');
  perform bl_add_money(v_me.id, 'cash', -p_amount, 'phone_bank_deposit', v_meta);
  v_cash := bl_add_money(v_me.id, 'cash', -v_fee, 'phone_bank_fee', v_meta || jsonb_build_object('kind', 'deposit'));
  v_bank := bl_add_money(v_me.id, 'bank', p_amount, 'phone_bank_deposit', v_meta);
  return jsonb_build_object('message', bl_naira(p_amount) || ' sent to your bank from your phone. Fee: ' || bl_naira(v_fee) || '.',
                            'amount', p_amount, 'fee', v_fee, 'cash', v_cash, 'bank', v_bank);
end $$;

-- bank -> cash from anywhere
create or replace function public.phone_bank_withdraw(p_amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); v_fee bigint; v_cash bigint; v_bank bigint; v_meta jsonb;
begin
  perform bl_phone_bank_check(v_me, p_amount);
  v_fee := bl_phone_fee(p_amount);
  if p_amount + v_fee > v_me.bank then
    raise exception 'Not enough money in the bank. Withdrawing % costs % with the % phone fee, and your balance is %.',
      bl_naira(p_amount), bl_naira(p_amount + v_fee), bl_naira(v_fee), bl_naira(v_me.bank) using errcode = 'P0001', hint = 'not_enough_bank';
  end if;
  v_meta := jsonb_build_object('amount', p_amount, 'fee', v_fee, 'via', 'phone');
  perform bl_add_money(v_me.id, 'bank', -p_amount, 'phone_bank_withdraw', v_meta);
  v_bank := bl_add_money(v_me.id, 'bank', -v_fee, 'phone_bank_fee', v_meta || jsonb_build_object('kind', 'withdraw'));
  v_cash := bl_add_money(v_me.id, 'cash', p_amount, 'phone_bank_withdraw', v_meta);
  return jsonb_build_object('message', 'You withdrew ' || bl_naira(p_amount) || ' to your pocket. Fee: ' || bl_naira(v_fee) || '. Careful on the road with it.',
                            'amount', p_amount, 'fee', v_fee, 'cash', v_cash, 'bank', v_bank);
end $$;

-- labels and the Admin -> Economy category (guarded single replaces)
create or replace function pg_temp.fx9_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'fixit9: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;
select pg_temp.fx9_patch('public.bl_ledger_label(text,jsonb)',
  E'    when ''pos_fee'' then return ''PoS charge'';',
  E'    when ''pos_fee'' then return ''PoS charge'';\n    when ''phone_bank_deposit'' then return ''Phone deposit'';\n    when ''phone_bank_withdraw'' then return ''Phone withdrawal'';\n    when ''phone_bank_fee'' then return ''Phone banking fee'';',
  'phone_bank_fee');
select pg_temp.fx9_patch('public.bl_econ_category(text)',
  E'when p_reason in (''market_fee'', ''pos_fee'') then',
  E'when p_reason in (''market_fee'', ''pos_fee'', ''phone_bank_fee'') then',
  'phone_bank_fee');
select pg_temp.fx9_patch('public.bl_earn_reasons()',
  E'''legal_fee'']',
  E'''legal_fee'', ''phone_bank_fee'', ''phone_bank_deposit'', ''phone_bank_withdraw'']',
  'phone_bank_fee');

revoke all on function public.bl_phone_fee(bigint) from public, anon, authenticated;
revoke all on function public.bl_phone_bank_check(profiles, bigint) from public, anon, authenticated;
revoke all on function public.phone_bank_info() from public, anon;
grant execute on function public.phone_bank_info() to authenticated;
revoke all on function public.phone_bank_deposit(bigint) from public, anon;
grant execute on function public.phone_bank_deposit(bigint) to authenticated;
revoke all on function public.phone_bank_withdraw(bigint) from public, anon;
grant execute on function public.phone_bank_withdraw(bigint) to authenticated;
notify pgrst, 'reload schema';
