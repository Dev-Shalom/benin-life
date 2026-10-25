-- Company rankings follow the leaderboard rule (docs/RANKS.md): other companies' sales show as a money range, not the exact number,
-- while ranks.hide_amounts is on. Public card, rankings and Discover. The owner's own dashboard keeps the exact numbers.
-- Guarded replaces on the live definitions (raise if the marker is missing, skip if already applied). Idempotent.

create or replace function pg_temp.cb_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'company_bands: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

select pg_temp.cb_patch('public.company_public(bigint)',
  $o$'sales_7d', v_sales, 'rank',$o$,
  $o$'sales_7d', case when bl_ranks_hide() then null else v_sales end, 'sales_band', case when bl_ranks_hide() then bl_money_band(v_sales) end, 'rank',$o$,
  $o$'sales_band'$o$);

select pg_temp.cb_patch('public.company_rankings(int)',
  $o$'sales_7d', x.s, 'owner',$o$,
  $o$'sales_7d', case when bl_ranks_hide() then null else x.s end, 'sales_band', case when bl_ranks_hide() then bl_money_band(x.s) end, 'owner',$o$,
  $o$'sales_band'$o$);

select pg_temp.cb_patch('public.company_discover(text,text,text,text,integer,integer)',
  $o$(select jsonb_agg(to_jsonb(x) - 'created_at') from$o$,
  $o$(select jsonb_agg((to_jsonb(x) - 'created_at') || case when bl_ranks_hide() then jsonb_build_object('sales_7d', null, 'sales_band', bl_money_band(x.sales_7d)) else '{}'::jsonb end) from$o$,
  $o$'sales_band'$o$);

notify pgrst, 'reload schema';
