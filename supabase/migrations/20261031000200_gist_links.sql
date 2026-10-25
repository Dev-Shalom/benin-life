-- Benin Gist: the links from the gist tables to profiles (foreign keys), so deleting a player (Admin -> Players -> Delete) removes their
-- posts, comments, likes, follows, group memberships, messages and reports too. A group whose owner is deleted just loses its owner.
-- They need a lock on public.profiles, the busiest table in the game. Taking that lock inside the big migration deadlocked with live
-- heartbeat updates once (see 20261027000200_family_kids_links.sql), so it is its own small migration: take ONE strong lock first, give
-- up after a short lock_timeout, release, sleep a little, try again. Idempotent: a constraint is only created when missing.

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

      for r in
        select * from (values
          ('gist_posts', 'user_id', 'cascade'), ('gist_comments', 'user_id', 'cascade'), ('gist_likes', 'user_id', 'cascade'),
          ('gist_follows', 'follower', 'cascade'), ('gist_follows', 'followee', 'cascade'), ('gist_bans', 'user_id', 'cascade'),
          ('gist_groups', 'owner_id', 'set null'), ('gist_group_members', 'user_id', 'cascade'), ('gist_group_bans', 'user_id', 'cascade'),
          ('gist_messages', 'user_id', 'cascade'), ('gist_reports', 'reporter_id', 'cascade'), ('gist_notify', 'user_id', 'cascade')
        ) as t(tbl, col, act)
      loop
        if not exists (select 1 from pg_constraint c
                        where c.conrelid = ('public.' || r.tbl)::regclass and c.contype = 'f' and c.confrelid = 'public.profiles'::regclass
                          and c.conkey = array[(select a.attnum from pg_attribute a where a.attrelid = ('public.' || r.tbl)::regclass and a.attname = r.col)]) then
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
    raise exception 'gist_links: could not lock profiles after % tries; re-run the deploy', v_try;
  end if;
end $$;

notify pgrst, 'reload schema';
