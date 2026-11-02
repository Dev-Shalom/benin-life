-- Benin Airport is not open yet (owner, 2 Nov 2026): no flights for now, so the airport is closed and
-- shows "Under construction". Admin can reopen it from Content > Places (active on).
--   * the place is set inactive (it can't be travelled to) with an "Under construction" blurb
--   * a place whose blurb starts with "Under construction" says so when you try to travel there
-- Idempotent. No profiles DDL, no loops over players.

create or replace function pg_temp.apc_patch(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n <> 1 then raise exception 'airport_construction: % : marker found % times: %', p_sig, v_n, left(p_marker, 90); end if;
  execute replace(v_def, p_marker, p_new);
end $$;

update public.locations
   set active = false,
       blurb  = 'Under construction. No flights yet: the airport opens later. Check back soon.'
 where id = 'benin_airport';

select pg_temp.apc_patch('public.bl_travel_quote(public.profiles, text)', 'is under construction. Check back soon.',
  $m$raise exception '% is closed for now. Check back soon.', dst.name using errcode = 'P0001', hint = 'inactive';$m$,
  $m$raise exception '% %', dst.name, case when dst.blurb ilike 'under construction%' then 'is under construction. Check back soon.' else 'is closed for now. Check back soon.' end using errcode = 'P0001', hint = 'inactive';$m$);
