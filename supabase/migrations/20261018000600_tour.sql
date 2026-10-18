-- Guided tour flag (docs/ONBOARDING.md). One column + one tiny RPC.
-- profiles.tour_done_at: when the player finished or skipped the intro tour. Null = not yet (new players and
-- existing players both see the tour once). It rides along in get_my_state (the profile row is spread into json).
-- Idempotent.
alter table public.profiles add column if not exists tour_done_at timestamptz;

create or replace function public.tour_done() returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_at timestamptz;
begin
  update profiles set tour_done_at = coalesce(tour_done_at, now()) where id = v_uid returning tour_done_at into v_at;
  return v_at;
end $$;

revoke all on function public.tour_done() from public, anon;
grant execute on function public.tour_done() to authenticated, service_role;

notify pgrst, 'reload schema';
