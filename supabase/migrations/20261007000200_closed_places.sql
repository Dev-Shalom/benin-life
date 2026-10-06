-- Closed places (user, 2026-10-07): you can't travel to a place outside its opening hours, and anyone
-- still inside when it closes is sent home ("The bouncers are clearing the place").
--   * bl_travel_quote re-created from its live definition (P1) + an opening-hours check (travel_quote and
--     travel_start both go through it). Your own home is always reachable.
--   * place_closed_eject(): the client calls it when the place it is in is closed; the server checks the
--     place really is closed (not home, not busy, not travelling) and moves the Sim home with an alert.
-- Idempotent.

CREATE OR REPLACE FUNCTION public.bl_travel_quote(p_me profiles, p_dest text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  dst      locations := bl_location(p_dest);
  src      locations := bl_location(p_me.location_id);
  v_km     numeric;
  v_now    timestamptz := bl_now();
  v_traffic_road numeric;
  v_has_car boolean;
  v_ride   text;   -- P1: 'car' (any car), 'motorcycle', 'bicycle', or null (no vehicle)
  v_key    text;
  v_opts   jsonb := '[]'::jsonb;
  m        text;
  v_label  text;
  v_speed  numeric; v_cost bigint; v_traffic numeric; v_gm int; v_rs numeric;
  v_allowed boolean; v_reason text;
  v_risk   numeric;
  v_short  boolean := bl_action_short();
  v_minrs  numeric := bl_cfg('travel.min_real_seconds');
begin
  -- F1 soft launch: a hidden place can't be travelled to (your own home always can)
  if not coalesce(dst.active, true) and dst.id is distinct from p_me.home_location_id then
    raise exception '% is closed for now. Check back soon.', dst.name using errcode = 'P0001', hint = 'inactive';
  end if;
  -- Closed places (outside opening hours) can't be travelled to either; your own home always can
  if dst.id is distinct from p_me.home_location_id and not bl_place_open(dst) then
    raise exception '% is closed right now. It opens at %.', dst.name, bl_hour_label(dst.open_hour)
      using errcode = 'P0001', hint = 'closed';
  end if;
  if dst.id = src.id then
    raise exception 'You are already at %.', dst.name using errcode = 'P0001';
  end if;
  v_km := bl_distance_km(src.id, dst.id);
  v_traffic_road := bl_traffic(src.id, dst.id, v_now);
  select case when bool_or(i.item_id not in ('bicycle', 'bajaj_boxer')) then 'car'
              when bool_or(i.item_id = 'bajaj_boxer') then 'motorcycle'
              when bool_or(i.item_id = 'bicycle') then 'bicycle' end
    into v_ride
    from inventory i join items it on it.id = i.item_id
   where i.user_id = p_me.id and i.qty > 0 and it.category = 'vehicle';
  v_has_car := v_ride is not null;

  foreach m in array array['walk','keke','bus','drop','car'] loop
    v_label := case m when 'walk' then 'Walk'
                      when 'keke' then 'Keke Napep'
                      when 'bus'  then 'ECTS Green Bus'
                      when 'drop' then 'Drop (ride-hail)'
                      else case v_ride when 'motorcycle' then 'Your motorcycle'
                                       when 'bicycle' then 'Your bicycle'
                                       else 'Your own car' end end;
    v_key := case when m = 'car' and v_ride in ('motorcycle', 'bicycle') then v_ride else m end;
    v_speed := greatest(bl_cfg('travel.' || v_key || '.speed_kmh'), 0.1);
    v_cost  := (ceil((bl_cfg('travel.' || v_key || '.base_cost') + bl_cfg('travel.' || v_key || '.per_km') * v_km) / 10.0) * 10)::bigint;
    v_traffic := case when m = 'walk' or v_key = 'bicycle' then 1
                      when v_key = 'motorcycle' then 1 + (v_traffic_road - 1) * 0.35
                      else v_traffic_road end;
    v_gm := greatest(1, ceil(v_km / v_speed * 60 * v_traffic))::int;
    v_rs := greatest(v_minrs, v_gm * bl_cfg('travel.real_seconds_per_game_minute'));
    if v_short then
      v_rs := least(v_rs, greatest(bl_cfg('action.travel_max_seconds'), v_minrs));
    end if;
    v_rs := round(v_rs, 1);
    v_allowed := true; v_reason := null;
    if m = 'keke' and not (src.keke_ok and dst.keke_ok) then
      v_allowed := false;
      v_reason := 'Keke can''t go there. Keke is banned on the major roads.';
    elsif m = 'car' and not v_has_car then
      v_allowed := false;
      v_reason := 'You don''t have a car yet. Buy one first.';
    elsif v_cost > p_me.cash then
      v_allowed := false;
      v_reason := 'Your money no reach for this one (' || bl_naira(v_cost) || ').';
    end if;
    v_risk := round(100 * bl_street_robbery_chance(p_me.id, dst.id, m, v_traffic,
                                                   v_now + make_interval(secs => v_rs::double precision)), 1);
    v_opts := v_opts || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'mode', m, 'label', v_label, 'allowed', v_allowed, 'reason', v_reason,
      'cost', v_cost, 'game_minutes', v_gm, 'real_seconds', v_rs, 'risk_pct', v_risk,
      'vehicle', case when m = 'car' then v_ride end)));
  end loop;

  return jsonb_build_object('dest', dst.id, 'km', v_km, 'traffic', v_traffic_road, 'options', v_opts);
end $function$;

revoke execute on function public.bl_travel_quote(public.profiles, text) from public, anon, authenticated;

create or replace function public.place_closed_eject() returns jsonb
language plpgsql security definer set search_path = public as $$
declare me profiles; loc locations; home locations;
begin
  select * into me from profiles where id = auth.uid() for update;
  if me.id is null then raise exception 'No Sim yet.' using errcode = 'P0001'; end if;
  if me.travel_to is not null then return jsonb_build_object('ejected', false, 'reason', 'travelling'); end if;
  if me.location_id is null or me.location_id = me.home_location_id then
    return jsonb_build_object('ejected', false, 'reason', 'home');
  end if;
  if me.busy_until is not null and me.busy_until > now() then
    return jsonb_build_object('ejected', false, 'reason', 'busy');
  end if;
  select * into loc from locations where id = me.location_id;
  if loc.id is null or bl_place_open(loc) then return jsonb_build_object('ejected', false, 'reason', 'open'); end if;
  select * into home from locations where id = me.home_location_id;
  update profiles set location_id = me.home_location_id where id = me.id;
  insert into events (user_id, kind, title, body, data)
  values (me.id, 'place_closed', loc.name || ' is closed',
          'The bouncers cleared the place. You headed home. It opens again at ' || bl_hour_label(loc.open_hour) || '.',
          jsonb_build_object('location_id', loc.id));
  return jsonb_build_object('ejected', true, 'place', loc.name, 'home', coalesce(home.name, 'home'),
                            'opens', bl_hour_label(loc.open_hour));
end $$;

revoke execute on function public.place_closed_eject() from public, anon;
grant execute on function public.place_closed_eject() to authenticated;
