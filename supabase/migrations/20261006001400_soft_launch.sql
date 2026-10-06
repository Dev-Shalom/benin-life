-- F1: club soft launch (docs/PLACES.md "Soft launch", docs/SHIP_TODAY.md F1).
-- * locations.active (default true). A hidden (inactive) place:
--   - has no map pin and is not in the Ride list / search (client filters on `active`),
--   - can't be travelled to (bl_travel_quote -> travel_quote + travel_start; your own home always can),
--   - can't be acted in: do_activity / shop_buy (via bl_assert_place_open) and work_shift refuse (hint 'inactive').
--   A player already inside can still leave (travel checks the destination only) or go home.
-- * One-shot seed (config flag places.soft_launch_seeded): every club except 360 Signature is switched off
--   the first time this runs; later runs never override the admin's choices.
-- * Admin: locations.active is editable (Content -> Places, audited by admin_row_upsert as before).
-- Idempotent; functions are re-created from their live definitions with the same grants.

alter table public.locations add column if not exists active boolean not null default true;

-- ---------------------------------------------------------------------
-- 1. Config flag + one-shot seed
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('places.soft_launch_seeded', 'false', 'places', 'Soft launch seeded',
 'Set to true once the F1 soft launch hid every club except 360 Signature. Leave it on: switch places on/off in Content -> Places (Active).',
 'bool', null, null)
on conflict (key) do nothing;

do $$
begin
  if not coalesce((select value = 'true'::jsonb from public.game_config where key = 'places.soft_launch_seeded'), false) then
    update public.locations set active = false
     where scene = 'club' and id <> 'club_360'
       and id in ('club_de_medici', 'rome_club', 'cube_nightlife', 'versus_lounge', 'owambe_republic');
    update public.locations set active = true, open_hour = 21, close_hour = 5 where id = 'club_360';
    update public.game_config set value = 'true'::jsonb where key = 'places.soft_launch_seeded';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Helpers: active + open
-- ---------------------------------------------------------------------
create or replace function public.bl_assert_place_active(p_loc public.locations) returns void
language plpgsql stable set search_path = public as $$
begin
  if p_loc.id is not null and not coalesce(p_loc.active, true) then
    raise exception '% is closed for now. Check back soon.', p_loc.name using errcode = 'P0001', hint = 'inactive';
  end if;
end $$;

-- hidden places are never open
create or replace function public.bl_place_open(p_loc public.locations) returns boolean
language plpgsql stable set search_path = public as $$
declare v_clock jsonb; h numeric;
begin
  if p_loc.id is not null and not coalesce(p_loc.active, true) then return false; end if;
  if p_loc.open_hour is null or not bl_cfg_bool('places.hours_enabled') then return true; end if;
  v_clock := bl_game_clock();
  h := (v_clock->>'hour')::numeric + coalesce((v_clock->>'minute')::numeric, 0) / 60.0;
  if p_loc.open_hour = p_loc.close_hour then return true; end if;
  if p_loc.open_hour < p_loc.close_hour then return h >= p_loc.open_hour and h < p_loc.close_hour; end if;
  return h >= p_loc.open_hour or h < p_loc.close_hour;
end $$;

create or replace function public.bl_assert_place_open(p_loc public.locations) returns void
language plpgsql stable set search_path = public as $$
begin
  perform bl_assert_place_active(p_loc);
  if not bl_place_open(p_loc) then
    raise exception '% is closed right now. Opens % (open % to %).', p_loc.name, bl_hour_label(p_loc.open_hour),
      bl_hour_label(p_loc.open_hour), bl_hour_label(p_loc.close_hour)
      using errcode = 'P0001', hint = 'closed';
  end if;
end $$;

revoke execute on function public.bl_assert_place_active(public.locations) from public, anon, authenticated;
revoke execute on function public.bl_place_open(public.locations)          from public, anon, authenticated;
revoke execute on function public.bl_assert_place_open(public.locations)   from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. bl_travel_quote (travel_quote + travel_start), work_shift, place_interior: live definitions + active
-- ---------------------------------------------------------------------
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
end $function$;

CREATE OR REPLACE FUNCTION public.work_shift()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me    profiles := bl_me();
  t       career_tracks;
  cl      career_levels;
  v_today int;
  v_done  int;
  v_perf  int;
  v_pay   bigint;
  v_xp    int;
  v_until timestamptz;
  v_settled jsonb;
  v_from  jsonb;
begin
  v_settled := bl_settle_shift(v_me.id);
  if v_settled is not null then select * into v_me from profiles where id = v_me.id; end if;
  perform bl_assert_free(v_me);
  if v_me.job_id is null then
    raise exception 'You don''t have a job yet. Open the Jobs app on your phone to apply.' using errcode = 'P0001', hint = 'no_job';
  end if;
  select * into t from career_tracks where id = v_me.job_id;
  select * into cl from career_levels where track_id = v_me.job_id and level = v_me.job_level;
  if t.id is null or cl.track_id is null then
    raise exception 'Your job no longer exists. Apply for another one.' using errcode = 'P0001', hint = 'no_job';
  end if;
  if not (v_me.location_id = any(t.location_ids)) then
    raise exception 'You work at %. Go there to start your shift.',
      (select string_agg(name, ' or ' order by array_position(t.location_ids, id)) from locations where id = any(t.location_ids))
      using errcode = 'P0001', hint = 'not_here';
  end if;
  -- F1 soft launch: no shifts at a hidden place
  perform bl_assert_place_active(bl_location(v_me.location_id));
  if v_me.energy < bl_cfg('career.min_energy') then
    raise exception 'You''re too tired to work. Sleep or take a nap first.' using errcode = 'P0001', hint = 'too_tired';
  end if;
  if v_me.hunger < bl_cfg('career.min_hunger') then
    raise exception 'You''re too hungry to work. Eat something first.' using errcode = 'P0001', hint = 'too_hungry';
  end if;
  v_today := (bl_game_clock()->>'day')::int;
  v_done := case when v_me.job_shift_day = v_today then v_me.job_shifts_today else 0 end;
  if v_done >= bl_cfg('career.max_shifts_per_game_day') then
    raise exception 'You''ve done % shifts today. Rest and come back tomorrow.', v_done
      using errcode = 'P0001', hint = 'shift_limit';
  end if;

  v_perf := bl_career_perf(v_me);
  v_pay := (round(cl.pay_per_shift * v_perf / 100.0 * bl_trait_mult(v_me, '{work_pay}') * bl_cfg('career.pay_mult') / 10.0) * 10)::bigint;
  v_xp := round(cl.xp_per_shift * v_perf / 100.0 * bl_cfg('career.xp_mult')
                * case when t.skill is null then 1 else bl_trait_mult(v_me, array['skill_xp', t.skill]) end)::int;

  v_from := bl_needs_snapshot(v_me);
  perform bl_adjust_needs(v_me.id, coalesce(cl.effects, '{}'::jsonb) || jsonb_build_object('energy',
                          -cl.energy_cost + coalesce((cl.effects->>'energy')::numeric, 0)));
  v_until := bl_set_busy_seconds(v_me.id, bl_shift_seconds(cl.shift_game_minutes), 'Working: ' || cl.title);
  update profiles set job_shift_ends_at = v_until, job_shift_pay = v_pay, job_shift_xp = v_xp, job_shift_perf = v_perf,
                      job_shift_day = v_today, job_shifts_today = v_done + 1, busy_needs_from = v_from
   where id = v_me.id;
  return jsonb_build_object(
    'message', 'Shift started as ' || cl.title || '. Performance ' || v_perf || '%: you''ll earn '
               || bl_naira(v_pay) || ' when it ends.',
    'busy_until', v_until, 'pay', v_pay, 'xp', v_xp, 'perf', v_perf, 'settled', v_settled);
end $function$;

CREATE OR REPLACE FUNCTION public.place_interior(p_location text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid   uuid := bl_require_uid();
  v_me    profiles;
  l       locations;
  v_open  boolean;
  v_closed_for text;
  v_night boolean := (bl_game_clock()->>'is_night')::boolean;
  v_part  text := bl_day_part();
  v_here  boolean;
  v_home  boolean;
  v_zones jsonb;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  l := bl_location(coalesce(p_location, v_me.location_id));
  v_open := bl_place_open(l);
  v_closed_for := case when not coalesce(l.active, true) then 'Closed for now' else 'Opens ' || bl_hour_label(l.open_hour) end;
  v_here := v_me.location_id = l.id and v_me.travel_to is null;
  v_home := v_me.home_location_id = l.id;

  with z as (
    select distinct on (pz.zone_key) pz.*
      from place_zones pz
     where pz.scene = l.scene or pz.location_id = l.id
     order by pz.zone_key, (pz.location_id is not null) desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', z.id, 'key', z.zone_key, 'label', z.label, 'icon', z.icon, 'prop', z.prop,
           'x', z.x, 'z', z.z, 'w', z.w, 'd', z.d, 'rot', z.rot, 'note', z.note,
           'actions', coalesce((
             select jsonb_agg(act order by s1, s2) from (
               -- activities
               select za.sort as s1, a.sort as s2, jsonb_build_object(
                        'id', za.id, 'kind', 'activity', 'ref', a.id,
                        'name', coalesce(za.label, a.name), 'icon', coalesce(za.icon, a.icon, '✨'),
                        'cost', a.cost, 'effects', a.effects, 'game_minutes', a.game_minutes,
                        'max_seconds', a.max_seconds, 'min_seconds', a.min_seconds, 'scale_by_need', a.scale_by_need,
                        'night_only', a.night_only, 'risky', a.risky, 'home_only', a.home_only,
                        'rush', case when a.rush = '{}'::jsonb then null else a.rush - 'line' end,
                        'locked', case
                          when a.home_only and not v_home then 'Only in your own home'
                          when not a.home_only and not v_open then v_closed_for
                          when a.night_only and not v_night then 'Night only'
                          else null end) as act
                 from zone_actions za join activities a on a.id = za.ref
                where za.zone_id = z.id and za.kind = 'activity' and za.active
                  and l.scene = any (a.scenes)
                  and (cardinality(a.location_ids) = 0 or l.id = any (a.location_ids))
               union all
               -- shop items sold at this place
               select za.sort, it.sort, jsonb_build_object(
                        'id', za.id, 'kind', 'shop', 'ref', it.id,
                        'name', coalesce(za.label, it.name), 'icon', coalesce(za.icon, it.icon, '🛍️'),
                        'cost', it.price, 'effects', it.effects, 'category', it.category,
                        'owned', coalesce((select qty from inventory where user_id = v_uid and item_id = it.id), 0),
                        'locked', case when not v_open then v_closed_for else null end)
                 from zone_actions za join items it on it.id = za.ref
                where za.zone_id = z.id and za.kind = 'shop' and za.active and l.id = any (it.sold_at)
               union all
               -- job tracks that work here
               select za.sort, 0, jsonb_build_object(
                        'id', za.id, 'kind', 'job', 'ref', t.id,
                        'name', coalesce(za.label, case when v_me.job_id = t.id then 'Work a shift' else t.name || ' jobs' end),
                        'icon', coalesce(za.icon, t.emoji),
                        'mine', v_me.job_id = t.id,
                        'title', (select title from career_levels where track_id = t.id
                                   and level = case when v_me.job_id = t.id then v_me.job_level else 1 end),
                        'pay', (select round(pay_per_shift * bl_cfg('career.pay_mult')) from career_levels where track_id = t.id
                                 and level = case when v_me.job_id = t.id then v_me.job_level else 1 end),
                        'locked', null)
                 from zone_actions za join career_tracks t on t.id = za.ref
                where za.zone_id = z.id and za.kind = 'job' and za.active and t.active and l.id = any (t.location_ids)
               union all
               -- open a tab of the place sheet (bank counter, PoS, the whole shop...)
               select za.sort, 0, jsonb_build_object(
                        'id', za.id, 'kind', 'panel', 'ref', za.ref,
                        'name', coalesce(za.label, initcap(za.ref)), 'icon', coalesce(za.icon,
                          case za.ref when 'bank' then '🏦' when 'pos' then '💳' when 'shop' then '🛍️' when 'jobs' then '💼' else '›' end),
                        'locked', null)
                 from zone_actions za
                where za.zone_id = z.id and za.kind = 'panel' and za.active
                  and (za.ref in ('chat', 'inventory', 'activities') or za.ref = any (l.actions))
             ) q), '[]'::jsonb))
         order by z.sort, z.zone_key), '[]'::jsonb)
    into v_zones
    from z where z.active;

  return jsonb_build_object(
    'location', jsonb_build_object('id', l.id, 'name', l.name, 'district', l.district, 'scene', l.scene, 'blurb', l.blurb,
                                   'open_hour', l.open_hour, 'close_hour', l.close_hour),
    'here', v_here, 'home', v_home, 'open', v_open, 'active', coalesce(l.active, true),
    'opens', case when v_open then null else v_closed_for end,
    'hours', case when l.open_hour is null then null
                  else bl_hour_label(l.open_hour) || ' – ' || bl_hour_label(l.close_hour) end,
    'night', v_night, 'part', v_part,
    'moods', coalesce((select jsonb_agg(jsonb_build_object('icon', m.icon, 'line', m.line) order by (m.location_id is null), m.sort)
                         from place_moods m
                        where m.active and (m.scene = l.scene or m.location_id = l.id)
                          and (m.part = 'any' or m.part = v_part)), '[]'::jsonb),
    'zones', v_zones);
end $function$;

revoke execute on function public.bl_travel_quote(public.profiles, text) from public, anon, authenticated;
revoke execute on function public.work_shift() from public, anon;
grant execute on function public.work_shift() to authenticated;
revoke execute on function public.place_interior(text) from public, anon;
grant execute on function public.place_interior(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Admin: locations.active editable (Content -> Places)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bl_admin_table_spec(p_table text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_table
    when 'origin_tiers' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","tagline":"text","welcome":"text","sort":"int","perks":"obj"}}'
    when 'traits' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","effects":"obj","sort":"int","active":"bool"}}'
    when 'dreams' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","goal":"obj","sort":"int","active":"bool"}}'
    when 'start_homes' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","location_id":"text","district":"text","tag":"text","description":"text",
              "weekly_rent":"money","start_cash":"obj","allowed_origins":"arr","locked_quip":"text","housing_id":"text",
              "sort":"int","active":"bool"}}'
    when 'career_tracks' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","location_ids":"arr","skill":"text_null","sort":"int","active":"bool"}}'
    when 'career_levels' then '{"pk":["track_id","level"],"insert":true,"order":"track_id, level",
      "cols":{"title":"text","pay_per_shift":"money","shift_game_minutes":"int","energy_cost":"int","effects":"obj",
              "xp_per_shift":"int","xp_to_next":"int_null","requirements":"obj","perks":"obj"}}'
    when 'items' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","category":"text","price":"money","description":"text","effects":"obj","sold_at":"arr",
              "sellable":"bool","resale_pct":"num","icon":"text_null","sort":"int"}}'
    when 'activities' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","scenes":"arr","home_only":"bool","night_only":"bool","cost":"money","game_minutes":"int",
              "max_seconds":"num","min_seconds":"num","scale_by_need":"bool","needs_furniture":"bool","effects":"obj","sort":"int",
              "location_ids":"arr","risky":"bool","rush":"obj","icon":"text_null"}}'
    when 'locations' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","blurb":"text","risk":"num","night_risk_mult":"num","cctv":"bool","keke_ok":"bool",
              "congestion":"num","remote_km":"num","actions":"arr","sort":"int","open_hour":"num_null","close_hour":"num_null","active":"bool"}}'
    when 'chat_banned_words' then '{"pk":["word"],"insert":true,"order":"word","cols":{"active":"bool"}}'
    when 'furniture' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","kind":"text","slot":"text","activities":"arr","rest_pct":"int",
              "color":"text_null","description":"text","sort":"int","active":"bool"}}'
    when 'starter_furniture' then '{"pk":["id"],"insert":true,"order":"origin, sort, id",
      "cols":{"origin":"text","start_home":"text_null","furniture_id":"text","slot":"text_null","sort":"int","active":"bool"}}'
    when 'place_zones' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","zone_key":"text","label":"text","icon":"text","prop":"text",
              "x":"num","z":"num","w":"num","d":"num","rot":"int","note":"text_null","sort":"int","active":"bool"}}'
    when 'zone_actions' then '{"pk":["id"],"insert":true,"order":"zone_id, sort, id",
      "cols":{"zone_id":"text","kind":"text","ref":"text","label":"text_null","icon":"text_null","sort":"int","active":"bool"}}'
    when 'place_moods' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), part, sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","part":"text","icon":"text","line":"text","sort":"int","active":"bool"}}'
  end::jsonb;
$function$;
revoke execute on function public.bl_admin_table_spec(text) from public, anon, authenticated;
