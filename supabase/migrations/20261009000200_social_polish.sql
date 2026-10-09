-- Polish after the social release (2026-10-09):
--   * bl_location: English error again ("That place isn't on the map."). The social migration re-created it
--     from an older definition and brought back the Pidgin text (user rule: English by default; Pidgin only in
--     street moments). Re-created from the live definition with only that string changed.
-- Idempotent.

CREATE OR REPLACE FUNCTION public.bl_location(p_id text)
 RETURNS locations
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare v public.locations;
begin
  select * into v from public.locations where id = p_id;
  if not found then
    raise exception 'That place isn''t on the map.' using errcode = 'P0001';
  end if;
  if v.private_home_owner_id is not null
     and not public.bl_social_can_view_private_home(v.id, v.private_home_owner_id) then
    raise exception 'That home is private. Ask the host to invite you.' using errcode = 'P0001', hint = 'private_home';
  end if;
  return v;
end $function$;

revoke execute on function public.bl_location(text) from public, anon, authenticated;

-- When a host leaves their home (travels, ends the session), admitted guests are sent back to their own
-- home with an alert instead of staying in an empty private house whose "home" points at the host's.
-- Moving each guest's location fires bl_social_restore_home_layout, which restores their own home/housing.
create or replace function public.bl_social_end_visits_on_host_leave() returns trigger
language plpgsql security definer set search_path = public as $$
declare g record;
begin
  if old.location_id is distinct from old.home_location_id
     or new.location_id is not distinct from old.location_id
     or old.home_visit_host_id is not null then
    return new;   -- only a host leaving their own home
  end if;
  for g in select id, home_visit_original_home_location_id as home from public.profiles
            where home_visit_host_id = new.id and location_id = old.location_id loop
    update public.profiles set location_id = coalesce(g.home, home_location_id), travel_to = null where id = g.id;
    insert into public.events (user_id, kind, title, body, data)
    values (g.id, 'house_visit_ended', 'The visit is over',
            '@' || new.username || ' left the house, so you headed home.', jsonb_build_object('host', new.id));
  end loop;
  return new;
end $$;
revoke execute on function public.bl_social_end_visits_on_host_leave() from public, anon, authenticated;

drop trigger if exists profiles_end_visits_on_host_leave on public.profiles;
create trigger profiles_end_visits_on_host_leave after update of location_id on public.profiles
  for each row execute function public.bl_social_end_visits_on_host_leave();
