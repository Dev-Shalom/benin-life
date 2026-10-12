-- Admin can let a player send bank transfers before the new-account wait is over.
alter table profiles add column if not exists transfer_trusted boolean not null default false;

do $$
declare v_def text;
begin
  -- bank_transfer: trusted players skip the new-account wait
  select pg_get_functiondef('public.bank_transfer'::regproc) into v_def;
  if position('transfer_trusted' in v_def) = 0 then
    if position('v_left := v_age - extract(epoch from v_now - v_me.created_at);' in v_def) = 0 then
      raise exception 'bank_transfer marker not found';
    end if;
    execute replace(v_def, 'v_left := v_age - extract(epoch from v_now - v_me.created_at);',
      'v_left := case when coalesce(v_me.transfer_trusted, false) then 0 else v_age - extract(epoch from v_now - v_me.created_at) end;');
  end if;
  -- bank_info: show no wait for trusted players
  select pg_get_functiondef('public.bank_info'::regproc) into v_def;
  if position('transfer_trusted' in v_def) = 0 then
    if position('v_wait := greatest(0,' in v_def) = 0 then
      raise exception 'bank_info marker not found';
    end if;
    execute replace(v_def, 'v_wait := greatest(0,',
      'v_wait := case when coalesce(v_me.transfer_trusted, false) then 0 else 1 end * greatest(0,');
  end if;
end $$;

create or replace function public.admin_set_transfer_trusted(p_id uuid, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_name text;
begin
  update profiles set transfer_trusted = coalesce(p_on, false) where id = p_id returning username into v_name;
  if not found then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, case when coalesce(p_on, false) then 'transfer_allow' else 'transfer_disallow' end, p_id, '{}');
  return jsonb_build_object('message', case when coalesce(p_on, false)
                                            then v_name || ' can send money now, even as a new account.'
                                            else v_name || ' waits like other new accounts again.' end,
                            'transfer_trusted', coalesce(p_on, false));
end $$;
revoke all on function public.admin_set_transfer_trusted(uuid, boolean) from public, anon;
grant execute on function public.admin_set_transfer_trusted(uuid, boolean) to authenticated;

notify pgrst, 'reload schema';
