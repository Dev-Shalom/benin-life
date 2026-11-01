-- Fix it 12: a clear money history for the Bank app ("money disappeared", "transfer didn't arrive").
-- Investigation result (docs/FIXIT.md item 12): every cash / bank change already goes through bl_add_money and writes a ledger row, so
-- nothing moves without a trace. What was missing was the READING of it: the old History tab showed 40 rows, one admin reason
-- ("Admin Grant") for both gifts and takes, no category, no paging, no in / out filter, no totals, and Yahoo money (a separate
-- balance the EFCC can seize) was not shown at all. So:
--   money_history(limit, before, filter, before_key)   rows newest first: label (the reason in words), detail (note), category, balance after,
--                                          cash / bank / yahoo account; filter all | in | out; paged by time; Yahoo moves included
--   money_history_summary(days)            money in, money out, own moves between cash and bank (not counted), and the biggest
--                                          drains by category, so "where did it go" has an answer in one glance
-- Read-only, own rows only (security definer on the caller's id). No tables, no profiles.
create or replace function public.bl_money_history_label(p_reason text, p_delta bigint, p_meta jsonb, p_src text) returns text
language sql stable set search_path = public as $$
  select case
    when p_src = 'yahoo' then case p_reason when 'job' then 'Yahoo job money' when 'cashout' then 'Yahoo money cashed out'
                                            when 'seized' then 'EFCC seized Yahoo money' when 'admin' then 'Admin changed your Yahoo balance' else 'Yahoo money' end
    when p_reason = 'admin_grant' then case when p_delta < 0 then 'Taken by a Benin Life admin' else 'Added by a Benin Life admin' end
    when p_reason = 'activity' then coalesce(nullif('Activity: ' || coalesce(p_meta->>'name', p_meta->>'activity', ''), 'Activity: '), 'Activity')
    else bl_ledger_label(p_reason, p_meta)
  end
$$;

drop function if exists public.money_history(int, timestamptz, text);
create or replace function public.money_history(p_limit int default 40, p_before timestamptz default null, p_filter text default 'all', p_before_key text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_n int := greatest(1, least(coalesce(p_limit, 40), 100));
  v_f text := case when p_filter in ('in', 'out') then p_filter else 'all' end;
  -- the page cursor is (time, key): several rows share one time (one action writes two), so time alone would skip or repeat rows
  v_src text := case left(coalesce(p_before_key, ''), 1) when 'y' then 'yahoo' else 'ledger' end;
  v_id bigint := coalesce(nullif(substr(coalesce(p_before_key, ''), 2), '')::bigint, 9223372036854775807);
  v_rows jsonb;
begin
  with src as (
    (select 'l' || l.id as key, l.id, l.created_at, l.account, l.delta, l.balance_after, l.reason, l.meta, 'ledger' as src
       from ledger l
      where l.user_id = v_uid
        and (p_before is null or (l.created_at, 'ledger'::text, l.id) < (p_before, v_src, v_id))
        and (v_f = 'all' or (v_f = 'in' and l.delta > 0) or (v_f = 'out' and l.delta < 0))
      order by l.created_at desc, l.id desc limit v_n + 1)
    union all
    (select 'y' || y.id, y.id, y.created_at, 'yahoo', y.delta, y.balance_after, y.reason, y.meta, 'yahoo'
       from yahoo_ledger y
      where y.user_id = v_uid
        and (p_before is null or (y.created_at, 'yahoo'::text, y.id) < (p_before, v_src, v_id))
        and (v_f = 'all' or (v_f = 'in' and y.delta > 0) or (v_f = 'out' and y.delta < 0))
      order by y.created_at desc, y.id desc limit v_n + 1)
  ), page as (select * from src order by created_at desc, src desc, id desc limit v_n + 1)
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', t.key, 'account', t.account, 'delta', t.delta, 'balance_after', t.balance_after, 'reason', t.reason,
           'label', bl_money_history_label(t.reason, t.delta, t.meta, t.src),
           'detail', coalesce(nullif(t.meta->>'note', ''), nullif(t.meta->>'narration', ''), nullif(t.meta->>'reason', '')),
           'category', case when t.src = 'yahoo' then 'Yahoo' else bl_econ_category(t.reason) end,
           'own_move', t.reason in ('bank_deposit', 'bank_withdraw', 'pos_cashout', 'pos_deposit', 'phone_bank_deposit', 'phone_bank_withdraw'),
           'created_at', t.created_at) order by t.created_at desc, t.src desc, t.id desc), '[]'::jsonb)
    into v_rows from page t;
  return jsonb_build_object('rows', (select coalesce(jsonb_agg(x order by i), '[]'::jsonb) from jsonb_array_elements(v_rows) with ordinality a(x, i) where i <= v_n),
                            'more', jsonb_array_length(v_rows) > v_n);
end $$;

create or replace function public.money_history_summary(p_days int default 7) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_days int := greatest(1, least(coalesce(p_days, 7), 90));
  v_since timestamptz := bl_now() - make_interval(days => v_days);
  v_in numeric; v_out numeric; v_moves numeric;
begin
  select coalesce(sum(delta) filter (where delta > 0 and reason not in ('bank_deposit', 'bank_withdraw', 'pos_cashout', 'pos_deposit', 'phone_bank_deposit', 'phone_bank_withdraw')), 0),
         coalesce(-sum(delta) filter (where delta < 0 and reason not in ('bank_deposit', 'bank_withdraw', 'pos_cashout', 'pos_deposit', 'phone_bank_deposit', 'phone_bank_withdraw')), 0),
         coalesce(sum(abs(delta)) filter (where reason in ('bank_deposit', 'bank_withdraw', 'pos_cashout', 'pos_deposit', 'phone_bank_deposit', 'phone_bank_withdraw')) / 2, 0)
    into v_in, v_out, v_moves
    from ledger where user_id = v_uid and created_at >= v_since;
  return jsonb_build_object('days', v_days, 'money_in', v_in, 'money_out', v_out, 'moved_between_accounts', v_moves,
    'top_out', coalesce((select jsonb_agg(jsonb_build_object('category', c, 'amount', s) order by s desc)
                           from (select bl_econ_category(reason) as c, -sum(delta) as s
                                   from ledger
                                  where user_id = v_uid and created_at >= v_since and delta < 0
                                    and reason not in ('bank_deposit', 'bank_withdraw', 'pos_cashout', 'pos_deposit', 'phone_bank_deposit', 'phone_bank_withdraw')
                                  group by 1 order by 2 desc limit 6) z), '[]'::jsonb),
    'yahoo_seized', coalesce((select -sum(delta) from yahoo_ledger where user_id = v_uid and created_at >= v_since and reason = 'seized'), 0));
end $$;

revoke all on function public.bl_money_history_label(text, bigint, jsonb, text) from public, anon, authenticated;
drop function if exists public.money_history(int, timestamptz, text);
revoke all on function public.money_history(int, timestamptz, text, text) from public, anon;
grant execute on function public.money_history(int, timestamptz, text, text) to authenticated;
revoke all on function public.money_history_summary(int) from public, anon;
grant execute on function public.money_history_summary(int) to authenticated;
notify pgrst, 'reload schema';
