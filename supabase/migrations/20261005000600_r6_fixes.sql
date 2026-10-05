-- R6 full test fixes (V1-2). Copy only: no schema or behaviour changes, safe on a non-empty DB.
-- * Player-facing server strings in plain English (moderate Pidgin, kept for street moments such
--   as the robbery headline): unknown player/place, missing config, username taken, keke/car
--   travel reasons, robbery event body and arrival message.
-- * No real brand names: the Nepo starter car is a "Tokunbo Saloon", not a Toyota Corolla.
-- The functions below are copied verbatim from their latest definitions (20261004000100_core.sql,
-- 20261005000400_creator.sql, 20261005000500_bladder.sql) with only the strings changed.
-- create or replace keeps the existing grants.

update public.items
   set name = 'Tokunbo Saloon',
       description = 'Belgium-used saloon car. It has seen some road, but the engine still sings. Fuel is on you.'
 where id = 'tokunbo_car';

CREATE OR REPLACE FUNCTION public.bl_add_money(p_uid uuid, p_account text, p_delta bigint, p_reason text, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_bal bigint;
begin
  if p_account not in ('cash','bank') then
    raise exception 'Unknown money account %', p_account using errcode = 'P0001';
  end if;
  if p_delta is null then
    raise exception 'Money amount no correct.' using errcode = 'P0001';
  end if;
  if p_account = 'cash' then
    update profiles set cash = cash + p_delta where id = p_uid and cash + p_delta >= 0 returning cash into v_bal;
  else
    update profiles set bank = bank + p_delta where id = p_uid and bank + p_delta >= 0 returning bank into v_bal;
  end if;
  if not found then
    if not exists (select 1 from profiles where id = p_uid) then
      raise exception 'That player doesn''t exist.' using errcode = 'P0001';
    end if;
    raise exception 'Your money no reach, my guy.' using errcode = 'P0001', hint = 'insufficient_funds';
  end if;
  if p_delta <> 0 then
    insert into ledger (user_id, account, delta, balance_after, reason, meta, created_at)
    values (p_uid, p_account, p_delta, v_bal, coalesce(p_reason, 'unknown'), coalesce(p_meta, '{}'::jsonb), bl_now());
  end if;
  return v_bal;
end $function$
;

CREATE OR REPLACE FUNCTION public.get_public_profile(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb;
begin
  perform bl_require_uid();
  select jsonb_build_object('id', id, 'username', username, 'avatar', avatar, 'gender', gender,
                            'street_cred', street_cred, 'job_id', job_id, 'location_id', location_id,
                            'created_at', created_at)
    into v from profiles where id = p_id and not banned;
  if v is null then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001';
  end if;
  return v;
end $function$
;

CREATE OR REPLACE FUNCTION public.bl_cfg(p_key text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare v jsonb;
begin
  select value into v from game_config where key = p_key;
  if not found then
    raise exception 'Missing game setting "%". An admin needs to check the settings.', p_key using errcode = 'P0001';
  end if;
  return (v #>> '{}')::numeric;
end $function$
;

CREATE OR REPLACE FUNCTION public.bl_check_new_profile(p_uid uuid, p_name text, p_gender text, p_avatar jsonb)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
begin
  if exists (select 1 from profiles where id = p_uid) then
    raise exception 'You have already created your Sim. One account, one Sim.' using errcode = 'P0001', hint = 'profile_exists';
  end if;
  if p_name !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'Usernames must be 3 to 20 letters, numbers or underscores (_). No spaces or symbols.'
      using errcode = 'P0001';
  end if;
  if p_gender not in ('male','female') then
    raise exception 'Please pick male or female.' using errcode = 'P0001';
  end if;
  if p_avatar is null or jsonb_typeof(p_avatar) <> 'object' or length(p_avatar::text) > 4000 then
    raise exception 'Your avatar data is not valid. Please try again.' using errcode = 'P0001';
  end if;
  if exists (select 1 from profiles where lower(username) = lower(p_name)) then
    raise exception 'The username "%" is already taken. Try another one.', p_name using errcode = 'P0001';
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.create_profile(p_username text, p_gender text, p_avatar jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := bl_require_uid();
  v_name   text := trim(coalesce(p_username, ''));
  v_gender text := lower(trim(coalesce(p_gender, '')));
  v_avatar jsonb := coalesce(p_avatar, '{}'::jsonb);
  v_now    timestamptz := bl_now();
  v_need   numeric := bl_cfg('start.need_level');
  v_tier   text;
  v_home   locations;
  v_cash   bigint;
  v_bank   bigint;
begin
  perform bl_check_new_profile(v_uid, v_name, v_gender, v_avatar);

  v_tier := bl_roll_origin();
  v_home := bl_location(bl_origin_cfg(v_tier, 'home_location'));
  v_cash := greatest(0, bl_origin_num(v_tier, 'start_cash'))::bigint;
  v_bank := greatest(0, bl_origin_num(v_tier, 'start_bank'))::bigint;

  begin
    insert into profiles (id, username, gender, avatar, cash, bank,
                          hunger, energy, hygiene, fun, social, health, stress, needs_updated_at,
                          location_id, home_location_id, housing_id, origin,
                          protected_until, last_seen, created_at)
    values (v_uid, v_name, v_gender, v_avatar, 0, 0,
            v_need, v_need, v_need, v_need, v_need, bl_cfg('start.health'), bl_cfg('start.stress'), v_now,
            v_home.id, v_home.id, bl_origin_cfg(v_tier, 'housing'), v_tier,
            v_now + make_interval(mins => bl_cfg('start.protection_real_minutes')::int), v_now, v_now);
  exception when unique_violation then
    raise exception 'The username "%" is already taken. Try another one.', v_name using errcode = 'P0001';
  end;

  if v_cash > 0 then perform bl_add_money(v_uid, 'cash', v_cash, 'start_bonus', jsonb_build_object('origin', v_tier)); end if;
  if v_bank > 0 then perform bl_add_money(v_uid, 'bank', v_bank, 'start_bonus', jsonb_build_object('origin', v_tier)); end if;
  perform bl_give_origin_items(v_uid, v_tier);
  perform bl_event(v_uid, 'welcome', 'Welcome to Benin!', bl_welcome_text(v_tier, v_name, v_home.name, v_cash, v_bank),
                   jsonb_build_object('origin', v_tier));
  return get_my_state();
end $function$
;

CREATE OR REPLACE FUNCTION public.create_profile_v2(p_username text, p_gender text, p_avatar jsonb, p_traits text[], p_dream text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := bl_require_uid();
  v_name   text := trim(coalesce(p_username, ''));
  v_gender text := lower(trim(coalesce(p_gender, '')));
  v_avatar jsonb := coalesce(p_avatar, '{}'::jsonb);
  v_now    timestamptz := bl_now();
  v_need   numeric := bl_cfg('start.need_level');
  v_traits text[];
  v_dream  text;
  v_tier   text;
  v_arrive locations;
begin
  perform bl_check_new_profile(v_uid, v_name, v_gender, v_avatar);
  v_traits := bl_check_traits(p_traits);
  v_dream := bl_check_dream(p_dream);
  v_arrive := bl_location(bl_cfg_text('creator.arrival_location'));
  v_tier := bl_roll_origin();

  begin
    insert into profiles (id, username, gender, avatar, cash, bank,
                          hunger, energy, hygiene, fun, social, health, stress, needs_updated_at,
                          location_id, home_location_id, housing_id, origin,
                          traits, dream, home_chosen,
                          protected_until, last_seen, created_at)
    values (v_uid, v_name, v_gender, v_avatar, 0, 0,
            v_need, v_need, v_need, v_need, v_need, bl_cfg('start.health'), bl_cfg('start.stress'), v_now,
            v_arrive.id, v_arrive.id, null, v_tier,
            v_traits, v_dream, false,
            v_now + make_interval(mins => bl_cfg('start.protection_real_minutes')::int), v_now, v_now);
  exception when unique_violation then
    raise exception 'The username "%" is already taken. Try another one.', v_name using errcode = 'P0001';
  end;
  return get_my_state();
end $function$
;

CREATE OR REPLACE FUNCTION public.bl_location(p_id text)
 RETURNS locations
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare v locations;
begin
  select * into v from locations where id = p_id;
  if not found then
    raise exception 'That place isn''t on the map.' using errcode = 'P0001';
  end if;
  return v;
end $function$
;

CREATE OR REPLACE FUNCTION public.bl_roll_street_robbery(p_uid uuid, p_location text, p_mode text, p_traffic numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_p      numeric := bl_street_robbery_chance(p_uid, p_location, p_mode, p_traffic, bl_now());
  v_cash   bigint;
  v_pct    numeric;
  v_amount bigint;
  v_injured boolean := false;
  v_hloss  numeric := 0;
  v_name   text;
  v_body   text;
begin
  if v_p <= 0 or bl_rand() >= v_p then return null; end if;

  select cash into v_cash from profiles where id = p_uid for update;
  v_pct := bl_cfg('crime.loss_min_pct')
           + bl_rand() * (bl_cfg('crime.loss_max_pct') - bl_cfg('crime.loss_min_pct'));
  v_amount := least(v_cash, greatest(1, floor(v_cash * v_pct / 100.0)))::bigint;
  if v_amount <= 0 then return null; end if;

  perform bl_add_money(p_uid, 'cash', -v_amount, 'street_robbery',
                       jsonb_build_object('location', p_location, 'mode', p_mode));

  if bl_rand() < bl_cfg('crime.injury_pct') / 100.0 then
    v_injured := true;
    v_hloss := round(bl_cfg('crime.injury_health_min')
                     + bl_rand() * (bl_cfg('crime.injury_health_max') - bl_cfg('crime.injury_health_min')));
  end if;
  perform bl_adjust_needs(p_uid, jsonb_build_object('health', -v_hloss, 'stress', bl_cfg('crime.robbery_stress')));

  select name into v_name from locations where id = p_location;
  v_body := 'Some boys took ' || bl_naira(v_amount) || ' from you around ' || coalesce(v_name, p_location)
            || '. You can report it at Police HQ.'
            || case when v_injured then ' Dem wound you small — run go UBTH or clinic sharp sharp.' else '' end;
  perform bl_event(p_uid, 'robbed', 'Omo, dem don rob you!', v_body,
                   jsonb_build_object('source', 'street', 'amount', v_amount, 'location', p_location,
                                      'mode', p_mode, 'injured', v_injured, 'health_loss', v_hloss,
                                      'at', bl_now()));
  return jsonb_build_object('amount', v_amount, 'injured', v_injured, 'health_loss', v_hloss,
                            'location', p_location);
end $function$
;

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
    v_rs := round(greatest(bl_cfg('travel.min_real_seconds'),
                           v_gm * bl_cfg('travel.real_seconds_per_game_minute')), 1);
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
end $function$
;

CREATE OR REPLACE FUNCTION public.travel_arrive()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me      profiles := bl_me();
  v_now     timestamptz := bl_now();
  v_from    text;
  v_dest    text;
  v_mode    text;
  v_traffic numeric;
  v_robbed  jsonb;
  v_name    text;
  v_msg     text;
begin
  if v_me.travel_to is null then
    raise exception 'You are not travelling right now.' using errcode = 'P0001';
  end if;
  if v_now < v_me.travel_arrives_at then
    raise exception 'You haven''t arrived yet! About % sec left.',
      ceil(extract(epoch from v_me.travel_arrives_at - v_now)) using errcode = 'P0001';
  end if;
  v_from := v_me.location_id; v_dest := v_me.travel_to; v_mode := v_me.travel_mode;
  v_traffic := case when v_mode = 'walk' then 1 else bl_traffic(v_from, v_dest, v_me.travel_started_at) end;

  update profiles set location_id = v_dest, travel_to = null, travel_mode = null,
                      travel_started_at = null, travel_arrives_at = null, last_seen = v_now
  where id = v_me.id;

  v_robbed := bl_roll_street_robbery(v_me.id, v_dest, v_mode, v_traffic);
  select name into v_name from locations where id = v_dest;

  if v_robbed is null then
    v_msg := 'You have arrived at ' || v_name || '.';
    return jsonb_build_object('message', v_msg, 'location', v_dest);
  end if;
  -- street moment: Pidgin stays
  v_msg := 'Omo! You reached ' || v_name || ' but some boys took '
           || bl_naira((v_robbed->>'amount')::bigint) || ' from you. You can report it to the Police.'
           || case when (v_robbed->>'injured')::boolean
                   then ' Dem wound you small. Go to UBTH or a clinic quick.' else '' end;
  return jsonb_build_object('message', v_msg, 'location', v_dest, 'robbed', v_robbed);
end $function$
;

