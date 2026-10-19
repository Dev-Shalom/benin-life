-- Owner request (19 Oct 2026): players complained, remove the Yahoo daily limits (E3 middle ground).
-- Pay, gates and catch chances are unchanged. The daily_cap column stays (0 = no limit) so admin can set one again.
update public.yahoo_jobs     set daily_cap = 0 where daily_cap <> 0;
update public.group_missions set daily_cap = 0 where daily_cap <> 0;
notify pgrst, 'reload schema';
