-- R2 Club switch (docs/CLUBS.md). The owner can switch each nightclub on or off in Admin, so the few players
-- there are gather in one or two clubs and they feel full.
--   * No new column: locations.active (F1 soft launch) already is the per-place switch. A club with active =
--     false is "Closed for now": bl_place_open() is false, so travel, activities, spray, shop, tickets and
--     shifts are refused with "<club> is closed for now. Check back soon." (hint 'inactive'), and
--     bl_events_now()/events_on_today() skip its events (no banner, no pin badge). All clubs stay ON by default.
--   * admin_club_list() / admin_club_set(id, on): the Content -> Clubs list and its toggles. Every change is
--     written to admin_audit (action 'club_switch'). Switching a club OFF also sends the players who are inside
--     (idle, not travelling) home with a 'place_closed' alert; busy ones are sent home by place_closed_eject()
--     as soon as they are free (the same closed-hours logic the client already runs).
--   * place_closed_eject() patched (guarded replace): the alert and the result say "closed for now" instead of
--     "opens again at ..." when the club is switched off.
--   * locations_read (RLS) is widened by a guarded edit: a switched-off CLUB stays readable, so the map can show
--     its pin as "Closed for now" (other hidden places stay invisible as before). The five clubs hidden by the
--     F1 soft launch therefore show as "Closed for now" pins too.
-- Idempotent and safe on a non-empty DB (no data is changed; grants are kept).

-- ---------------------------------------------------------------------
-- 1. place_closed_eject(): wording for a switched-off club
-- ---------------------------------------------------------------------
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.place_closed_eject()'::regprocedure) into v_def;
  if position('R2 club switch' in v_def) > 0 then
    return;
  end if;
  if position($m$'The bouncers cleared the place. You headed home. It opens again at ' || bl_hour_label(loc.open_hour) || '.'$m$ in v_def) = 0
     or position($m$'opens', bl_hour_label(loc.open_hour));$m$ in v_def) = 0 then
    raise exception 'place_closed_eject marker not found (R2 club switch)';
  end if;
  v_def := replace(v_def, $m$'The bouncers cleared the place. You headed home. It opens again at ' || bl_hour_label(loc.open_hour) || '.'$m$,
    $m$case when coalesce(loc.active, true)
               then 'The bouncers cleared the place. You headed home. It opens again at ' || bl_hour_label(loc.open_hour) || '.'
               else 'The place is closed for now. You headed home. Check back soon.' end /* R2 club switch */$m$);
  v_def := replace(v_def, $m$'opens', bl_hour_label(loc.open_hour));$m$,
    $m$'opens', bl_hour_label(loc.open_hour), 'off', not coalesce(loc.active, true));$m$);
  execute v_def;
end $$;

revoke execute on function public.place_closed_eject() from public, anon;
grant execute on function public.place_closed_eject() to authenticated;

-- ---------------------------------------------------------------------
-- 1b. RLS: a switched-off club is still readable (shown as "Closed for now")
-- ---------------------------------------------------------------------
do $$
declare v_q text;
begin
  select qual into v_q from pg_policies where schemaname = 'public' and tablename = 'locations' and policyname = 'locations_read';
  if v_q is null or position('COALESCE(active, true)' in v_q) = 0 then
    raise exception 'locations_read marker not found (R2 club switch)';
  end if;
  if position('''club''' in v_q) > 0 then
    return;
  end if;
  execute format('alter policy locations_read on public.locations using (%s)',
                 replace(v_q, 'COALESCE(active, true)', '(COALESCE(active, true) OR ((scene)::text = ''club''::text))'));
end $$;

-- ---------------------------------------------------------------------
-- 2. Admin: the club list and the switch
-- ---------------------------------------------------------------------
create or replace function public.admin_club_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', l.id, 'name', l.name, 'district', l.district,
             'on', coalesce(l.active, true),
             'open_hour', l.open_hour, 'close_hour', l.close_hour,
             'open_now', bl_place_open(l),
             'inside', (select count(*) from profiles p where p.location_id = l.id and p.travel_to is null),
             'events', (select count(*) from place_events e where e.location_id = l.id and e.active))
           order by l.sort, l.name)
      from locations l where l.scene = 'club'), '[]'::jsonb);
end $$;

create or replace function public.admin_club_set(p_id text, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  l       locations;
  v_on    boolean := coalesce(p_on, true);
  v_moved int := 0;
begin
  select * into l from locations where id = p_id and scene = 'club' for update;
  if l.id is null then
    raise exception 'That club doesn''t exist.' using errcode = 'P0001', hint = 'no_club';
  end if;
  if coalesce(l.active, true) = v_on then
    return jsonb_build_object('id', l.id, 'on', v_on, 'moved', 0, 'changed', false,
                              'message', l.name || ' is already ' || case when v_on then 'ON.' else 'OFF.' end);
  end if;
  update locations set active = v_on where id = l.id;
  if not v_on then
    -- players inside (not travelling, not busy) head home with an alert; busy ones are cleared by the client
    -- the moment they are free (place_closed_eject)
    with moved as (
      update profiles set location_id = home_location_id
       where location_id = l.id and home_location_id is not null and travel_to is null
         and (busy_until is null or busy_until <= now())
      returning id)
    insert into events (user_id, kind, title, body, data)
    select m.id, 'place_closed', l.name || ' is closed',
           'The place is closed for now. You headed home. Check back soon.',
           jsonb_build_object('location_id', l.id)
      from moved m;
    get diagnostics v_moved = row_count;
  end if;
  insert into admin_audit (admin_id, action, data)
  values (v_admin, 'club_switch',
          jsonb_build_object('location_id', l.id, 'name', l.name, 'on', v_on, 'was', not v_on, 'moved_home', v_moved));
  return jsonb_build_object('id', l.id, 'on', v_on, 'moved', v_moved, 'changed', true,
    'message', l.name || case when v_on then ' is ON. Players can enter now.'
                              else ' is OFF (Closed for now).'
                                   || case when v_moved > 0 then ' ' || v_moved || ' player(s) sent home.' else '' end end);
end $$;

revoke all on function public.admin_club_list() from public, anon;
revoke all on function public.admin_club_set(text, boolean) from public, anon;
grant execute on function public.admin_club_list() to authenticated;
grant execute on function public.admin_club_set(text, boolean) to authenticated;

notify pgrst, 'reload schema';
