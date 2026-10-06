-- =====================================================================
-- Benin Life — L1 fixes on top of 20261006000100_real_time.sql (already applied on the hosted DB,
-- so it is never edited). docs/REAL_LIFE_PLAN.md "Action timing rule": every timed action is seconds.
--
-- * Jail and hospital stays are capped in short mode by action.jail_max_seconds /
--   action.hospital_max_seconds (bl_jail / bl_hospitalize keep their signatures).
-- * bl_travel_quote: restores the R6 English reasons ("Keke can't go there…", "You don't have a car
--   yet…") that 20261006000100 reverted by mistake; keeps the travel cap.
-- * Admin labels: rent grace, allowance and transfer limits are per real day with the real clock.
-- Idempotent and safe on a non-empty DB (config `on conflict do nothing`, create or replace).
-- =====================================================================

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('action.jail_max_seconds', '45', 'action', 'Longest jail stay (real seconds)',
 'A jail sentence never adds more than this many real seconds (short mode). Longer sentences scale down to it.', 'number', 1, 600),
('action.hospital_max_seconds', '30', 'action', 'Longest hospital stay (real seconds)',
 'A hospital stay never adds more than this many real seconds (short mode).', 'number', 1, 600)
on conflict (key) do nothing;

update public.game_config
   set label = 'First rent grace (days)',
       description = 'A new tenant''s first rent day is the first rent weekday at least this many days after moving in.'
 where key = 'rent.first_due_grace_game_days';

-- Admin labels: with the real clock a "game day" is a real day (Benin time).
update public.game_config set label = 'LAPO baby: Dad allowance per day' where key = 'origin.lapo.allowance_daily';
update public.game_config set label = 'Nepo baby: Dad allowance per day' where key = 'origin.nepo.allowance_daily';
update public.game_config set description = 'The most a player can send to other players per day (resets at midnight, Benin time; fees not counted).'
 where key = 'bank.transfer_daily_limit';
update public.game_config set label = 'Transfers per day',
       description = 'How many transfers a player can send per day (resets at midnight, Benin time).'
 where key = 'bank.transfer_daily_count';

-- Jail / hospital stays: game minutes × time.real_seconds_per_game_minute, capped in short mode by
-- action.jail_max_seconds / action.hospital_max_seconds (punishments stay seconds, never minutes).
create or replace function public.bl_status_seconds(p_game_minutes int, p_cap_key text) returns numeric
language sql stable set search_path = public as $$
  select case when public.bl_action_short()
              then least(public.bl_real_seconds(p_game_minutes), greatest(public.bl_cfg(p_cap_key), 1))
              else public.bl_real_seconds(p_game_minutes) end;
$$;

-- Same as core except the capped duration; also clears busy_needs_from.
create or replace function public.bl_jail(p_uid uuid, p_game_minutes int, p_reason text) returns timestamptz
language plpgsql set search_path = public as $$
declare v_until timestamptz; v_loc text := bl_cfg_text('crime.jail_location');
begin
  update profiles set
    jailed_until = greatest(coalesce(jailed_until, bl_now()), bl_now())
                   + make_interval(secs => bl_status_seconds(p_game_minutes, 'action.jail_max_seconds')::double precision),
    jail_reason = p_reason,
    location_id = coalesce((select id from locations where id = v_loc), location_id),
    travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
    busy_until = null, busy_label = null, busy_needs_from = null
  where id = p_uid
  returning jailed_until into v_until;
  return v_until;
end $$;

create or replace function public.bl_hospitalize(p_uid uuid, p_game_minutes int, p_reason text) returns timestamptz
language plpgsql set search_path = public as $$
declare v_until timestamptz; v_loc text := bl_cfg_text('crime.hospital_location');
begin
  update profiles p set
    hospitalized_until = greatest(coalesce(p.hospitalized_until, bl_now()), bl_now())
                         + make_interval(secs => bl_status_seconds(p_game_minutes, 'action.hospital_max_seconds')::double precision),
    location_id = case when (select scene from locations where id = p.location_id) = 'hospital' then p.location_id
                       else coalesce((select id from locations where id = v_loc), p.location_id) end,
    travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
    busy_until = null, busy_label = null, busy_needs_from = null
  where p.id = p_uid
  returning p.hospitalized_until into v_until;
  return v_until;
end $$;


-- Travel quote: same as R6 (r6_fixes, English strings) plus the action.travel_max_seconds cap in short mode.
create or replace function public.bl_travel_quote(p_me public.profiles, p_dest text) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  dst      locations := bl_location(p_dest);
  src      locations := bl_location(p_me.location_id);
  v_km     numeric;
  v_now    timestamptz := bl_now();
  v_traffic_road numeric;
  v_has_car boolean;
  v_opts   jsonb := '[]'::jsonb;
  m        text;
  v_label  text;
  v_speed  numeric; v_cost bigint; v_traffic numeric; v_gm int; v_rs numeric;
  v_allowed boolean; v_reason text;
  v_risk   numeric;
  v_short  boolean := bl_action_short();
  v_minrs  numeric := bl_cfg('travel.min_real_seconds');
begin
  if dst.id = src.id then
    raise exception 'You are already at %.', dst.name using errcode = 'P0001';
  end if;
  v_km := bl_distance_km(src.id, dst.id);
  v_traffic_road := bl_traffic(src.id, dst.id, v_now);
  v_has_car := exists (select 1 from inventory i join items it on it.id = i.item_id
                       where i.user_id = p_me.id and i.qty > 0 and it.category = 'vehicle');

  foreach m in array array['walk','keke','bus','drop','car'] loop
    v_label := case m when 'walk' then 'Walk'
                      when 'keke' then 'Keke Napep'
                      when 'bus'  then 'ECTS Green Bus'
                      when 'drop' then 'Drop (ride-hail)'
                      else 'Your own car' end;
    v_speed := greatest(bl_cfg('travel.' || m || '.speed_kmh'), 0.1);
    v_cost  := (ceil((bl_cfg('travel.' || m || '.base_cost') + bl_cfg('travel.' || m || '.per_km') * v_km) / 10.0) * 10)::bigint;
    v_traffic := case when m = 'walk' then 1 else v_traffic_road end;
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
      'cost', v_cost, 'game_minutes', v_gm, 'real_seconds', v_rs, 'risk_pct', v_risk)));
  end loop;

  return jsonb_build_object('dest', dst.id, 'km', v_km, 'traffic', v_traffic_road, 'options', v_opts);
end $$;


revoke execute on function public.bl_status_seconds(int, text)        from public, anon, authenticated;
revoke execute on function public.bl_jail(uuid, int, text)            from public, anon, authenticated;
revoke execute on function public.bl_hospitalize(uuid, int, text)     from public, anon, authenticated;
revoke execute on function public.bl_travel_quote(public.profiles, text) from public, anon, authenticated;
