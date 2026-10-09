-- Let an admitted visitor leave a private home on demand and restore their own home/layout.
create or replace function public.social_leave_house() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_me public.profiles;
  v_host public.profiles;
  v_home text;
begin
  select * into v_me from public.profiles where id = v_uid for update;
  if v_me.home_visit_host_id is null then
    return jsonb_build_object('status', 'not_visiting', 'message', 'You are already at your own home.');
  end if;

  select * into v_host from public.profiles where id = v_me.home_visit_host_id;
  if v_host.id is null or v_me.location_id <> v_host.home_location_id or v_me.travel_to is not null then
    raise exception 'You are no longer inside that house.' using errcode = 'P0001', hint = 'not_house_guest';
  end if;
  v_home := coalesce(v_me.home_visit_original_home_location_id, v_me.home_location_id);
  if v_home is null or not exists (
    select 1 from public.locations where id = v_home and private_home_owner_id = v_uid
  ) then
    raise exception 'Your own home could not be found. Please contact support.' using errcode = 'P0001', hint = 'home_missing';
  end if;

  -- The existing BEFORE UPDATE trigger restores the saved housing and home fields when the
  -- visitor leaves the host's location. The explicit destination makes this available in one tap.
  update public.profiles
     set location_id = v_home,
         travel_to = null,
         travel_mode = null,
         travel_started_at = null,
         travel_arrives_at = null
   where id = v_uid;

  if v_host.id is not null then
    perform public.bl_event(v_host.id, 'house_guest_left', '@' || v_me.username || ' left your home',
      'Your guest has returned to their own home.', jsonb_build_object('guest_id', v_uid));
  end if;
  return jsonb_build_object('status', 'left', 'message', 'You left the house and returned home.', 'home_location_id', v_home);
end $$;

revoke all on function public.social_leave_house() from public, anon;
grant execute on function public.social_leave_house() to authenticated;
