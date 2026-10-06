-- Money short form starts at ₦100,000 (user rule, 2026-10-06): ₦99,999 · ₦100K · ₦250K · ₦1.2M · ₦3.4B · ₦1.1T.
-- Same rule as src/lib/format.ts nairaShort. Idempotent (create or replace, same signature).
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
  if v_len <= 5 then  -- under ₦100,000 stays in full (user rule)
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
revoke execute on function public.bl_naira_short(numeric) from public, anon, authenticated;
