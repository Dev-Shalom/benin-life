-- More seats (20261025000100_more_seats.sql): Youth Leader, Speaker, Deputy Governor. Rolled back. Run:
--   bash scripts/sql-test.sh -- supabase/tests/more_seats_test.sql
do $$
declare v_def text;
begin
  if (select count(*) from offices where id in ('youth_leader', 'speaker', 'deputy_governor') and active and elected and not ward_scoped and kind = 'chairman') <> 3 then
    raise exception 'TEST FAILED: three new city-wide elected seats';
  end if;
  if (select title from offices where id = 'speaker') <> 'Rt. Hon.' or (select title from offices where id = 'deputy_governor') <> 'Dep. Gov.'
     or (select title from offices where id = 'youth_leader') <> 'Youth Ldr.' then
    raise exception 'TEST FAILED: titles';
  end if;
  if (select ticket_price from offices where id = 'youth_leader') <> 1000000000 or (select ticket_price from offices where id = 'speaker') <> 15000000000
     or (select ticket_price from offices where id = 'deputy_governor') <> 35000000000 then
    raise exception 'TEST FAILED: Godfather ticket prices';
  end if;
  -- no Governor powers: those are keyed on kind = 'governor' and on the office id 'governor'
  if exists (select 1 from offices where id in ('youth_leader', 'speaker', 'deputy_governor') and kind in ('governor', 'councillor', 'commissioner')) then
    raise exception 'TEST FAILED: new seats must not carry Governor / Councillor / Commissioner powers';
  end if;
  -- every elected office is a race on the ballot: pol_ballot builds races from offices where active and elected
  v_def := pg_get_functiondef('public.pol_ballot()'::regprocedure);
  if position('o2.active and o2.elected' in v_def) = 0 then
    raise exception 'TEST FAILED: ballot races come from every active elected office';
  end if;
  raise notice 'ok: more seats';
end $$;
