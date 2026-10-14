-- Player feedback (2026-10-14, @SosaMoney): "EFCC % is too high, I get arrested every time; once the money finishes
-- you can't buy another laptop." Each earning cycle is a job roll + a cash-out roll, so 20 % + 32 % meant ~45 %
-- of cycles ended in EFCC, and every bust took the laptop AND the whole yahoo balance.
-- Fairer defaults (guarded: only rows still at the Y1 defaults change; all editable in Admin):
--   catch chances chat 20->12, romance 25->16, big 35->24, cash out 32->14
--   a bust seizes the laptop only 35 % of the time (yahoo.seize_laptop_pct) and takes 50 % of the yahoo balance
--   (yahoo.confiscate_pct) instead of all of it.
update public.yahoo_jobs set caught_pct = 12 where id = 'chat_client' and caught_pct = 20;
update public.yahoo_jobs set caught_pct = 16 where id = 'romance_job' and caught_pct = 25;
update public.yahoo_jobs set caught_pct = 24 where id = 'big_job'     and caught_pct = 35;
update public.yahoo_jobs set caught_pct = 14 where id = 'cash_out'    and caught_pct = 32;

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('yahoo.seize_laptop_pct', '35', 'yahoo', 'EFCC bust: chance the laptop is seized',
 'When EFCC catches you, the chance they also seize the laptop you used. 100 = always.', 'percent', 0, 100),
('yahoo.confiscate_pct', '50', 'yahoo', 'EFCC bust: share of yahoo balance taken',
 'When EFCC catches you, this percent of your unspent yahoo balance is confiscated. 100 = all of it.', 'percent', 0, 100)
on conflict (key) do nothing;

do $$
declare v_def text;
begin
  select pg_get_functiondef('public.bl_yahoo_resolve(bigint)'::regprocedure) into v_def;
  if position('yahoo.confiscate_pct' in v_def) = 0 then
    if position('v_seized := y.dirty;' in v_def) = 0 then raise exception 'bl_yahoo_resolve: seized marker not found'; end if;
    v_def := replace(v_def, 'v_seized := y.dirty;',
      'v_seized := floor(y.dirty * greatest(0, least(100, bl_yahoo_num(''yahoo.confiscate_pct'', 50))) / 100.0)::bigint;');
  end if;
  if position('yahoo.seize_laptop_pct' in v_def) = 0 then
    if position('if v_lap is not null and exists (' in v_def) = 0 then raise exception 'bl_yahoo_resolve: laptop marker not found'; end if;
    v_def := replace(v_def, 'if v_lap is not null and exists (',
      'if v_lap is not null and bl_crime_roll(bl_yahoo_num(''yahoo.seize_laptop_pct'', 35)) and exists (');
  end if;
  execute v_def;
end $$;
notify pgrst, 'reload schema';
