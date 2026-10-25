-- Kids: the links from the kids tables to profiles (foreign keys) and the "a parent started a new life" trigger.
-- They need a lock on public.profiles, the busiest table in the game. Taking that lock inside the big migration deadlocked with live
-- heartbeat updates (the first live deploy of 20261027000100 failed with SQLSTATE 40P01), so it is its own small migration:
-- take ONE strong lock first (never upgrade a weaker one), give up after a short lock_timeout, release, sleep a little, try again.
-- Idempotent: constraints and the trigger are only created when missing.

do $$
declare
  v_try  int := 0;
  v_done boolean := false;
begin
  while not v_done and v_try < 20 loop
    v_try := v_try + 1;
    begin
      set local lock_timeout = '1500ms';
      lock table public.profiles in access exclusive mode;

      if not exists (select 1 from pg_constraint where conrelid = 'public.kids_children'::regclass and contype = 'f' and confrelid = 'public.profiles'::regclass
                        and conkey = array[(select attnum from pg_attribute where attrelid = 'public.kids_children'::regclass and attname = 'parent_a')]) then
        alter table public.kids_children add constraint kids_children_parent_a_fkey foreign key (parent_a) references public.profiles(id) on delete set null;
      end if;
      if not exists (select 1 from pg_constraint where conrelid = 'public.kids_children'::regclass and contype = 'f' and confrelid = 'public.profiles'::regclass
                        and conkey = array[(select attnum from pg_attribute where attrelid = 'public.kids_children'::regclass and attname = 'parent_b')]) then
        alter table public.kids_children add constraint kids_children_parent_b_fkey foreign key (parent_b) references public.profiles(id) on delete set null;
      end if;
      if not exists (select 1 from pg_constraint where conrelid = 'public.kids_invites'::regclass and contype = 'f' and confrelid = 'public.profiles'::regclass
                        and conkey = array[(select attnum from pg_attribute where attrelid = 'public.kids_invites'::regclass and attname = 'from_user')]) then
        alter table public.kids_invites add constraint kids_invites_from_user_fkey foreign key (from_user) references public.profiles(id) on delete cascade;
      end if;
      if not exists (select 1 from pg_constraint where conrelid = 'public.kids_invites'::regclass and contype = 'f' and confrelid = 'public.profiles'::regclass
                        and conkey = array[(select attnum from pg_attribute where attrelid = 'public.kids_invites'::regclass and attname = 'to_user')]) then
        alter table public.kids_invites add constraint kids_invites_to_user_fkey foreign key (to_user) references public.profiles(id) on delete cascade;
      end if;
      if not exists (select 1 from pg_constraint where conrelid = 'public.kids_care_log'::regclass and contype = 'f' and confrelid = 'public.profiles'::regclass
                        and conkey = array[(select attnum from pg_attribute where attrelid = 'public.kids_care_log'::regclass and attname = 'user_id')]) then
        alter table public.kids_care_log add constraint kids_care_log_user_id_fkey foreign key (user_id) references public.profiles(id) on delete set null;
      end if;

      drop trigger if exists kids_parent_left on public.profiles;
      create trigger kids_parent_left before delete on public.profiles for each row execute function public.bl_kids_parent_left();

      v_done := true;
    exception when lock_not_available or deadlock_detected then
      perform pg_sleep(1 + random() * 2);
    end;
  end loop;
  if not v_done then
    raise exception 'family_kids_links: could not lock profiles after % tries; re-run the deploy', v_try;
  end if;
end $$;

notify pgrst, 'reload schema';
