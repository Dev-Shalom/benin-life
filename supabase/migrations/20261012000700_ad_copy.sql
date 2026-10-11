-- Fix the last "coming soon" string in billboard_ad_create (patched from the live definition).
do $$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'billboard_ad_create' limit 1;
  if v_def is null then raise exception 'billboard_ad_create not found'; end if;
  if position('Ad payments are coming soon.' in v_def) > 0 then
    execute replace(v_def, 'Ad payments are coming soon.', 'Ad payments are paused right now. Please try again later.');
  end if;
end $$;

notify pgrst, 'reload schema';
