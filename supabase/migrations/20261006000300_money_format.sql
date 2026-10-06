-- Money format (2026-10-06): real-world short scale everywhere.
-- 1. bl_naira: full comma grouping for ANY size (the old to_char mask broke past ₦999 trillion,
--    printing '#'), and a proper "-₦500" for negatives.
-- 2. bl_naira_short: ₦950 · ₦12.5K · ₦1.2M · ₦3.4B · ₦1.1T · ₦2Q (truncates, never rounds up),
--    same rules as src/lib/format.ts nairaShort.
-- 3. admin_grant_money: the hard ₦1T cap becomes config `admin.grant_max` (default ₦1Q), and no
--    balance may go past ₦9Q (JavaScript shows integers exactly only up to ~9.007e15).

create or replace function public.bl_naira(p_amount numeric) returns text
language sql immutable set search_path = public as $$
  select case when round(coalesce(p_amount, 0)) < 0 then '-' else '' end || '₦'
         || regexp_replace(abs(round(coalesce(p_amount, 0)))::text, '(\d)(?=(\d{3})+$)', '\1,', 'g');
$$;

create or replace function public.bl_naira_short(p_amount numeric) returns text
language plpgsql immutable set search_path = public as $$
declare
  v_neg  boolean := round(coalesce(p_amount, 0)) < 0;
  v_d    text := abs(round(coalesce(p_amount, 0)))::text;
  v_len  int := length(v_d);
  v_exp  int;
  v_suf  text;
  v_whole text;
  v_frac text;
  v_body text;
begin
  if v_len <= 4 then
    return bl_naira(p_amount);
  end if;
  v_exp := case when v_len > 15 then 15 when v_len > 12 then 12 when v_len > 9 then 9 when v_len > 6 then 6 else 3 end;
  v_suf := case v_exp when 15 then 'Q' when 12 then 'T' when 9 then 'B' when 6 then 'M' else 'K' end;
  v_whole := left(v_d, v_len - v_exp);
  v_frac := substr(v_d, v_len - v_exp + 1, 1);
  v_body := case when length(v_whole) >= 3 then regexp_replace(v_whole, '(\d)(?=(\d{3})+$)', '\1,', 'g')
                 when v_frac = '0' then v_whole
                 else v_whole || '.' || v_frac end;
  return case when v_neg then '-' else '' end || '₦' || v_body || v_suf;
end $$;

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('admin.grant_max', '1000000000000000', 'admin', 'Biggest single admin grant',
 'Largest amount one "Give or take money" action may move (default ₦1Q = ₦1,000,000,000,000,000). Balances can never go past ₦9Q.',
 'naira', 1, 9000000000000000)
on conflict (key) do nothing;

create or replace function public.admin_grant_money(p_id uuid, p_account text, p_delta bigint, p_reason text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  v_bal bigint;
  v_cur bigint;
  v_note text := left(trim(coalesce(p_reason, '')), 200);
  v_max numeric := coalesce((select (value #>> '{}')::numeric from game_config where key = 'admin.grant_max'), 1000000000000000);
  v_ceiling constant bigint := 9000000000000000; -- ₦9Q: JS shows integers exactly below ~9.007e15
begin
  if p_account not in ('cash', 'bank') then
    raise exception 'Pick cash or bank.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  if p_delta is null or p_delta = 0 then
    raise exception 'Enter an amount (not zero).' using errcode = 'P0001', hint = 'bad_value';
  end if;
  if abs(p_delta::numeric) > v_max then
    raise exception 'That is more than one grant may move (max %).', bl_naira(v_max) using errcode = 'P0001', hint = 'too_big';
  end if;
  select case when p_account = 'cash' then cash else bank end into v_cur from profiles where id = p_id;
  if not found then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  if p_delta > 0 and v_cur::numeric + p_delta > v_ceiling then
    raise exception 'That would take their % past %, the most a balance can hold.', p_account, bl_naira(v_ceiling)
      using errcode = 'P0001', hint = 'too_big';
  end if;
  begin
    v_bal := bl_add_money(p_id, p_account, p_delta, 'admin_grant', jsonb_build_object('admin', v_admin, 'note', v_note));
  exception when others then
    if sqlerrm like 'Your money no reach%' then
      raise exception 'They don''t have that much in their %.', p_account using errcode = 'P0001', hint = 'insufficient_funds';
    end if;
    raise;
  end;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'grant_money', p_id,
          jsonb_build_object('account', p_account, 'delta', p_delta, 'balance_after', v_bal, 'note', v_note));
  perform bl_event(p_id, 'admin_money', case when p_delta > 0 then 'Money received' else 'Account adjusted' end,
                   case when p_delta > 0 then bl_naira(p_delta) || ' was added to your ' || p_account || '.'
                        else bl_naira(-p_delta) || ' was taken from your ' || p_account || '.' end
                   || case when v_note <> '' then ' Note: ' || v_note else '' end,
                   jsonb_build_object('account', p_account, 'delta', p_delta));
  return jsonb_build_object('message', case when p_delta > 0 then 'Added ' || bl_naira(p_delta) else 'Took ' || bl_naira(-p_delta) end
                                       || ' (' || p_account || '). New balance ' || bl_naira(v_bal)
                                       || case when abs(v_bal) >= 10000 then ' (' || bl_naira_short(v_bal) || ')' else '' end || '.',
                            'account', p_account, 'balance', v_bal);
end $$;

revoke execute on function public.admin_grant_money(uuid, text, bigint, text) from public, anon;
grant execute on function public.admin_grant_money(uuid, text, bigint, text) to authenticated;

-- Internal helper, like bl_naira: not callable by players.
revoke execute on function public.bl_naira_short(numeric) from public, anon, authenticated;

-- Let admins tune these into whale territory (the defaults stay as they are).
update public.game_config set max = 9000000000000000
 where key in ('bank.transfer_daily_limit', 'pos.max_amount') and max < 9000000000000000;
