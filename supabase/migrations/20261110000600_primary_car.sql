-- Fix it 10: choose which car to drive.
-- Until now every rule that needed "a car" took the most expensive vehicle the player owned (the Bolt hustle's class, the travel
-- quote's ride, the garage list). Now each player can pick one (player_primary_car, keyed by the user id, cascade on delete):
--   * bl_primary_item(uid)  = the picked vehicle while it is still owned and not blocked, else null (callers fall back to the old rule)
--   * bl_hustle_car         the Bolt / service hustle uses it (class, pay, fuel, wear)  -> also hustle_start, bl_chal_can, costs, pay
--   * bl_travel_quote       "Your own car / motorcycle / bicycle" and so the fares, times and the robbery risk of that mode
--   * garage_home           the picked car comes first (it is the one drawn in the garage / on the pad) and every car says primary
--   * car_set_primary(item) / car_primary_get()   the Cars app and the garage sheet
-- Selling the picked car falls back to the old rule by itself. No profiles change; no loops over players.
create table if not exists public.player_primary_car (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  item_id    text not null references public.items(id) on delete cascade,
  updated_at timestamptz not null default now()
);
alter table public.player_primary_car enable row level security;
drop policy if exists player_primary_car_own on public.player_primary_car;
create policy player_primary_car_own on public.player_primary_car for select to authenticated using (user_id = auth.uid());
revoke all on public.player_primary_car from anon, authenticated;
grant select on public.player_primary_car to authenticated;

create or replace function public.bl_primary_item(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select pc.item_id
    from player_primary_car pc
    join inventory i on i.user_id = pc.user_id and i.item_id = pc.item_id and i.qty > 0
    join items it on it.id = pc.item_id and it.category = 'vehicle'
   where pc.user_id = p_uid and not bl_sink_blocked(p_uid, 'car', pc.item_id)
$$;

-- the vehicle the player is driving right now: the pick, else the most expensive one (the old rule)
create or replace function public.bl_driving_item(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(bl_primary_item(p_uid),
    (select i.item_id from inventory i join items it on it.id = i.item_id
      where i.user_id = p_uid and i.qty > 0 and it.category = 'vehicle' and not bl_sink_blocked(p_uid, 'car', i.item_id)
      order by it.price desc, it.id limit 1))
$$;

create or replace function public.car_primary_get() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  return jsonb_build_object('chosen', bl_primary_item(v_uid), 'driving', bl_driving_item(v_uid));
end $$;

create or replace function public.car_set_primary(p_item text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); it items;
begin
  select * into it from items where id = p_item and category = 'vehicle';
  if not found or not exists (select 1 from inventory where user_id = v_uid and item_id = p_item and qty > 0) then
    raise exception 'You do not own that vehicle.' using errcode = 'P0001', hint = 'not_owned';
  end if;
  if bl_sink_blocked(v_uid, 'car', p_item) then
    raise exception 'You cannot drive that one right now.' using errcode = 'P0001', hint = 'blocked';
  end if;
  insert into player_primary_car (user_id, item_id) values (v_uid, p_item)
    on conflict (user_id) do update set item_id = excluded.item_id, updated_at = now();
  return jsonb_build_object('message', 'You are driving your ' || it.name || ' now.', 'driving', p_item);
end $$;

-- guarded single replaces of the live functions
create or replace function pg_temp.fx10_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'fixit10: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

select pg_temp.fx10_patch('public.bl_hustle_car(uuid)',
  E'   order by it.price desc\n   limit 1;',
  E'   order by (it.id = bl_driving_item(p_uid)) desc, it.price desc\n   limit 1;',
  'bl_driving_item');

select pg_temp.fx10_patch('public.bl_travel_quote(profiles,text)',
  E'where i.user_id = p_me.id and i.qty > 0 and it.category = ''vehicle'' and not bl_sink_blocked(p_me.id, ''car'', i.item_id);',
  E'where i.user_id = p_me.id and i.qty > 0 and it.category = ''vehicle'' and not bl_sink_blocked(p_me.id, ''car'', i.item_id)\n     and i.item_id = bl_driving_item(p_me.id);',
  'bl_driving_item');

select pg_temp.fx10_patch('public.garage_home(uuid)',
  E'select coalesce(jsonb_agg(jsonb_build_object(''id'', it.id, ''name'', it.name, ''price'', it.price) order by it.price desc, it.id), ''[]''::jsonb)',
  E'select coalesce(jsonb_agg(jsonb_build_object(''id'', it.id, ''name'', it.name, ''price'', it.price, ''primary'', it.id = bl_driving_item(v_owner))\n                            order by (it.id = bl_driving_item(v_owner)) desc, it.price desc, it.id), ''[]''::jsonb)',
  'bl_driving_item');

revoke all on function public.bl_primary_item(uuid) from public, anon, authenticated;
revoke all on function public.bl_driving_item(uuid) from public, anon, authenticated;
revoke all on function public.car_primary_get() from public, anon;
grant execute on function public.car_primary_get() to authenticated;
revoke all on function public.car_set_primary(text) from public, anon;
grant execute on function public.car_set_primary(text) to authenticated;
notify pgrst, 'reload schema';
