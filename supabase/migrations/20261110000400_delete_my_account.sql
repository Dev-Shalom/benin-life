-- Fix it 8: "Delete my account" in Settings.
-- The player types DELETE; the edge function delete-my-account calls self_delete_start() with the PLAYER's JWT (it checks the
-- confirmation, refuses admins, writes an admin_audit row with a snapshot BEFORE anything is deleted), removes the storage files
-- (bl_user_storage_paths, already built for the admin delete) and calls auth.admin.deleteUser. Every game row goes by the same
-- auth.users cascade the admin delete uses (docs/ADMIN.md): no orphans (admin_delete_test checks every table that points at a user).
-- life_restart() is different on purpose: it archives the Sim and keeps the login. This one removes the login too.
create or replace function public.self_delete_start(p_confirm text) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  v_uid uuid := auth.uid();
  p profiles;
  v_email text;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'not_signed_in';
  end if;
  if btrim(coalesce(p_confirm, '')) <> 'DELETE' then
    raise exception 'Type DELETE in capital letters to confirm.' using errcode = 'P0001', hint = 'confirm';
  end if;
  select email into v_email from auth.users where id = v_uid;
  select * into p from profiles where id = v_uid;
  if coalesce(p.is_admin, false) then
    raise exception 'Admin accounts cannot delete themselves here. Ask the owner to remove your admin first.' using errcode = 'P0001', hint = 'is_admin';
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (null, 'self_delete_account', v_uid, jsonb_build_object(
    'user_id', v_uid, 'username', p.username, 'email', v_email, 'cash', p.cash, 'bank', p.bank,
    'created_at', p.created_at, 'origin', p.origin, 'had_profile', p.id is not null));
  return jsonb_build_object('ok', true, 'user_id', v_uid, 'username', p.username);
end $$;
revoke all on function public.self_delete_start(text) from public, anon;
grant execute on function public.self_delete_start(text) to authenticated, service_role;

create or replace function public.bl_self_delete_failed(p_user uuid, p_error text) returns void
language sql security definer set search_path = public as $$
  insert into admin_audit (admin_id, action, target_user, data)
  values (null, 'self_delete_account_failed', p_user, jsonb_build_object('user_id', p_user, 'error', left(coalesce(p_error, ''), 500)));
$$;
revoke all on function public.bl_self_delete_failed(uuid, text) from public, anon, authenticated;
grant execute on function public.bl_self_delete_failed(uuid, text) to service_role;
notify pgrst, 'reload schema';
