-- Own your home: the links from the property tables to profiles (foreign keys), so deleting a player cleans up their homes,
-- builds, past homes and rent. They need a lock on public.profiles, the busiest table in the game, so (like
-- 20261027000200_family_kids_links.sql) they live in their own small migration: take ONE strong lock first, give up after a short
-- lock_timeout, release, sleep a little, try again. Idempotent: a constraint is only created when it is missing.

do $$
declare
  v_try  int := 0;
  v_done boolean := false;
  r      record;
begin
  while not v_done and v_try < 20 loop
    v_try := v_try + 1;
    begin
      set local lock_timeout = '1500ms';
      lock table public.profiles in access exclusive mode;
      for r in select * from (values
          ('properties', 'owner_id', 'cascade'),
          ('property_builds', 'owner_id', 'cascade'),
          ('player_residence', 'user_id', 'cascade'),
          ('player_residence', 'landlord_id', 'set null'),
          ('property_income', 'owner_id', 'cascade'),
          ('property_income', 'tenant_id', 'set null'),
          ('player_past_homes', 'user_id', 'cascade')) as t(tbl, col, act) loop
        if not exists (select 1 from pg_constraint c
                        where c.conrelid = format('public.%I', r.tbl)::regclass and c.contype = 'f' and c.confrelid = 'public.profiles'::regclass
                          and c.conkey = array[(select attnum from pg_attribute where attrelid = format('public.%I', r.tbl)::regclass and attname = r.col)]) then
          execute format('alter table public.%I add constraint %I foreign key (%I) references public.profiles(id) on delete %s',
                         r.tbl, r.tbl || '_' || r.col || '_fkey', r.col, r.act);
        end if;
      end loop;
      v_done := true;
    exception when lock_not_available or deadlock_detected then
      perform pg_sleep(1 + random() * 2);
    end;
  end loop;
  if not v_done then
    raise exception 'property_links: could not lock profiles after % tries; re-run the deploy', v_try;
  end if;
end $$;

notify pgrst, 'reload schema';
