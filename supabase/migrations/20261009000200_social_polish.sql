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
