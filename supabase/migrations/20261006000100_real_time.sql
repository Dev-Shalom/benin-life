-- =====================================================================
-- Benin Life — L1 "Real Benin time" + the action timing rule (docs/REAL_LIFE_PLAN.md, docs/DB_CORE.md).
--
-- 1. Clock. `clock.mode` = 'real' (default) | 'accelerated'.
--    * real: the game clock IS the wall clock in `clock.timezone` (Africa/Lagos = WAT, UTC+1, no DST).
--      day = whole local days since the local date of `clock.epoch` + 1 (launch day 2026-10-05 = Day 1,
--      a Monday); weekday = the real weekday (0 = Monday … 6 = Sunday); hour/minute = local time.
--      game_minutes = (day - 1) × 1440 + hour × 60 + minute (so day = floor(game_minutes / 1440) + 1 still holds).
--    * accelerated: the old formula (clock.game_minutes_per_real_minute, clock.start_hour_offset), unchanged.
--    bl_game_clock keeps its signature and JSON shape and adds `mode` and `date` (local YYYY-MM-DD).
--    Rent ("next rent weekday 00:00") follows the same clock: in real mode it is the next real Saturday
--    midnight WAT.
-- 2. Needs decay. Rates stay "per need-hour" (needs.*_per_hour). Need-hours per real hour:
--    real mode = `needs.decay_speed` (2.5 → hunger 4 × 2.5 = 10/real h, empty in ~10 real hours);
--    accelerated = clock.game_minutes_per_real_minute (the old behaviour, 12). Still path-independent.
-- 3. Action timing ("nobody waits long"). `action.mode` = 'short' (default) | 'game_minutes'.
--    * short: an activity lasts max(min_seconds, max_seconds × missing/100) real seconds, where
--      missing = 100 − the current value of the need it restores most (stress: the current stress),
--      when action.scale_by_need and the activity's scale_by_need are on; otherwise max_seconds.
--      Per-activity activities.max_seconds / min_seconds / scale_by_need (Admin → Content). Sleep: 15 s max,
--      3 s min. A work shift lasts action.shift_seconds. Travel is capped at action.travel_max_seconds.
--    * game_minutes: the old durations (game_minutes × time.real_seconds_per_game_minute, travel uncapped).
--    Effects still apply at the start (server authoritative, nothing to settle). profiles.busy_needs_from
--    keeps the need values from just before the effects so the client can fill the bars live from
--    busy_started_at to busy_until.
--
-- Safe on a non-empty hosted DB and idempotent: new columns `add column if not exists`, config rows
-- `on conflict do nothing`, functions `create or replace` with the same signatures. The one-time
-- re-alignment (block 6) runs only on the first apply (detected by `clock.mode` not existing yet):
--   * rent_due_at → the first real rent day after now + rent.first_due_grace_game_days (never back-charges;
--     an overdue accelerated due date just rolls forward; rent_owed is kept);
--   * ledger meta.day of allowance / transfers → the real day of created_at (old value kept as accel_day),
--     and allowance_claimed_day → the real day of the player's last allowance;
--   * job_shift_day / job_shifts_today → reset (players may work a full set of shifts today: in their favour, once).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------
alter table public.activities add column if not exists max_seconds   numeric not null default 8;
alter table public.activities add column if not exists min_seconds   numeric not null default 3;
alter table public.activities add column if not exists scale_by_need boolean not null default true;
-- need values just before the running action's effects (null when the busy timer has none)
alter table public.profiles add column if not exists busy_needs_from jsonb;

-- ---------------------------------------------------------------------
-- 2. Config (clock.mode itself is inserted at the very end; see block 6)
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('clock.timezone', '"Africa/Lagos"', 'clock', 'Time zone (real mode)',
 'The game clock shows the real time here when clock.mode is real. Africa/Lagos = WAT (UTC+1, no daylight saving), the time in Benin City.',
 'text', null, null),
('needs.decay_speed', '2.5', 'needs', 'Need hours per real hour (real clock)',
 'With the real-time clock, needs drop by their "per hour" rate × this, every real hour. 2.5 = hunger (4/h) empties in about 10 real hours, energy in 13, bladder in 8. Accelerated mode uses the clock speed instead.',
 'number', 0, 48),
('action.mode', '"short"', 'action', 'Action timing',
 'short = every action takes a few real seconds (the per-activity seconds below). game_minutes = the old way: game minutes × time.real_seconds_per_game_minute.',
 'text', null, null),
('action.scale_by_need', 'true', 'action', 'Scale by need',
 'Actions are shorter when the need they fill is less empty (sleep takes the full 15 s only when energy is near 0). Each activity can also turn this off.',
 'bool', null, null),
('action.shift_seconds', '18', 'action', 'Work shift (real seconds)',
 'How long one work shift takes in real seconds (short mode).', 'number', 1, 600),
('action.travel_max_seconds', '20', 'action', 'Longest trip (real seconds)',
 'No trip takes longer than this many real seconds (short mode). travel.min_real_seconds is the shortest.', 'number', 1, 600)
on conflict (key) do nothing;

update public.game_config
   set description = 'Accelerated mode only: game minutes per real minute (12 = one game day every 2 real hours). In real mode the clock is the real time in clock.timezone.'
 where key = 'clock.game_minutes_per_real_minute';
update public.game_config
   set description = 'Accelerated mode only: game hours added to the clock.'
 where key = 'clock.start_hour_offset';
update public.game_config
   set description = 'Launch instant. Day 1 is its local date (real mode) or starts here (accelerated mode). ISO timestamp, e.g. 2026-10-05T00:00:00Z. Changing it renumbers the days.'
 where key = 'clock.epoch';
update public.game_config
   set description = 'Action/jail/hospital time per game minute. Jail and hospital stays always use it; activities, shifts and travel use it only when action.mode is game_minutes.'
 where key = 'time.real_seconds_per_game_minute';
update public.game_config
   set label = 'Rent day (0 = Mon … 6 = Sun)',
       description = 'Weekday rent is due at 00:00 (real calendar in real mode). 5 = Saturday.'
 where key = 'rent.due_weekday';
update public.game_config
   set label = 'Shifts per day', description = 'Most work shifts per day (resets at midnight, Benin time).'
 where key = 'career.max_shifts_per_game_day';

-- Per-activity seconds (only rows still on the column defaults, so admin edits survive a re-run).
update public.activities a set max_seconds = v.mx, min_seconds = v.mn
  from (values
    ('sleep', 15, 3), ('nap', 8, 3), ('bathe', 5, 3), ('use_toilet', 3, 2), ('ease_yourself', 3, 2),
    ('public_toilet', 3, 2), ('cook_home', 5, 3), ('owo_soup', 5, 3), ('banga_starch', 5, 3),
    ('black_soup', 5, 3), ('noodles_egg', 4, 3), ('pepper_soup', 4, 3), ('suya', 4, 3),
    ('watch_tv', 10, 4), ('listen_radio', 8, 3), ('gist_joint', 8, 3), ('watch_football', 12, 5),
    ('club_night', 15, 6), ('lounge_chill', 10, 4), ('museum_tour', 10, 4), ('palace_visit', 10, 4),
    ('campus_stroll', 8, 3), ('bronze_casting', 12, 5), ('market_stroll', 8, 3), ('cyber_browse', 8, 3),
    ('salon_freshen', 8, 3), ('plane_spotting', 8, 3), ('office_coffee', 4, 3), ('tech_meetup', 12, 5)
  ) as v(id, mx, mn)
 where a.id = v.id and a.max_seconds = 8 and a.min_seconds = 3;

-- ---------------------------------------------------------------------
-- 3. Clock helpers
-- ---------------------------------------------------------------------
-- 'real' or 'accelerated'. Tolerant: 'real' while the key does not exist yet (first apply).
create or replace function public.bl_clock_mode() returns text
language sql stable set search_path = public as $$
  select case when (select value #>> '{}' from game_config where key = 'clock.mode') = 'accelerated'
              then 'accelerated' else 'real' end;
$$;

create or replace function public.bl_clock_tz() returns text
language sql stable set search_path = public as $$
  select coalesce(nullif(btrim((select value #>> '{}' from game_config where key = 'clock.timezone')), ''), 'Africa/Lagos');
$$;

-- Game minutes per real minute: 1 in real mode, clock.game_minutes_per_real_minute when accelerated.
create or replace function public.bl_clock_speed() returns numeric
language sql stable set search_path = public as $$
  select case when public.bl_clock_mode() = 'real' then 1::numeric
              else greatest(public.bl_cfg('clock.game_minutes_per_real_minute'), 0.0001) end;
$$;

-- Reject config values the server cannot use (keeps the epoch / force_next / arrival checks).
create or replace function public.bl_game_config_validate() returns trigger
language plpgsql set search_path = public as $$
declare v timestamptz; v_txt text;
begin
  if new.key = 'clock.epoch' then
    begin
      v := (new.value #>> '{}')::timestamptz;
    exception when others then
      raise exception 'Clock epoch must be a date/time like 2026-10-05T00:00:00Z.' using errcode = 'P0001';
    end;
    if v is null then
      raise exception 'Clock epoch must be a date/time like 2026-10-05T00:00:00Z.' using errcode = 'P0001';
    end if;
  elsif new.key = 'clock.mode' then
    if coalesce(new.value #>> '{}', '') not in ('real', 'accelerated') then
      raise exception 'clock.mode must be real or accelerated.' using errcode = 'P0001';
    end if;
  elsif new.key = 'clock.timezone' then
    begin
      perform now() at time zone (new.value #>> '{}');
    exception when others then
      raise exception 'clock.timezone must be a time zone name like Africa/Lagos.' using errcode = 'P0001';
    end;
    if coalesce(btrim(new.value #>> '{}'), '') = '' then
      raise exception 'clock.timezone must be a time zone name like Africa/Lagos.' using errcode = 'P0001';
    end if;
  elsif new.key = 'action.mode' then
    if coalesce(new.value #>> '{}', '') not in ('short', 'game_minutes') then
      raise exception 'action.mode must be short or game_minutes.' using errcode = 'P0001';
    end if;
  elsif new.key = 'origin.force_next' then
    v_txt := trim(coalesce(new.value #>> '{}', ''));
    if v_txt <> '' and not exists (select 1 from origin_tiers where id = v_txt) then
      raise exception 'origin.force_next must be empty or an origin tier id (e.g. nepo, lapo).' using errcode = 'P0001';
    end if;
  elsif new.key = 'creator.arrival_location' then
    if not exists (select 1 from locations where id = new.value #>> '{}') then
      raise exception 'creator.arrival_location must be a location id.' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;

-- Game clock (same signature, same JSON + `mode` and `date`).
create or replace function public.bl_game_clock(p_at timestamptz default null) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_at    timestamptz := coalesce(p_at, bl_now());
  v_epoch timestamptz := bl_cfg_text('clock.epoch')::timestamptz;
  v_tz    text := bl_clock_tz();
  v_mode  text := bl_clock_mode();
  v_eday  date := (v_epoch at time zone v_tz)::date;
  v_local timestamp;
  v_gm    bigint;
  v_hour  int;
  v_min   int;
  v_day   bigint;
  v_wd    int;
  v_date  date;
  v_ns    int := bl_cfg('clock.night_start_hour')::int;
  v_ne    int := bl_cfg('clock.night_end_hour')::int;
begin
  if v_mode = 'real' then
    v_local := v_at at time zone v_tz;
    v_date := v_local::date;
    v_day  := (v_date - v_eday) + 1;
    v_hour := extract(hour from v_local)::int;
    v_min  := extract(minute from v_local)::int;
    v_wd   := extract(isodow from v_local)::int - 1;
    v_gm   := (v_day - 1) * 1440 + v_hour * 60 + v_min;
  else
    v_gm := floor(extract(epoch from (v_at - v_epoch))
                  * bl_cfg('clock.game_minutes_per_real_minute') / 60.0
                  + bl_cfg('clock.start_hour_offset') * 60)::bigint;
    v_hour := ((v_gm % 1440 + 1440) % 1440) / 60;
    v_min  := ((v_gm % 60) + 60) % 60;
    v_day  := floor(v_gm / 1440.0)::bigint + 1;
    v_wd   := (((v_day - 1) % 7) + 7) % 7;
    v_date := v_eday + (v_day - 1)::int;
  end if;
  return jsonb_build_object(
    'game_minutes', v_gm,
    'day', v_day,
    'weekday', v_wd,
    'hour', v_hour,
    'minute', v_min,
    'is_night', case when v_ns > v_ne then (v_hour >= v_ns or v_hour < v_ne)
                     else (v_hour >= v_ns and v_hour < v_ne) end,
    'mode', v_mode,
    'date', to_char(v_date, 'YYYY-MM-DD')
  );
end $$;

-- First rent day (rent.due_weekday, 00:00 game time) strictly after p_from + p_grace_game_days.
create or replace function public.bl_rent_due_after(p_from timestamptz, p_grace_game_days numeric) returns timestamptz
language plpgsql stable set search_path = public as $$
declare
  v_wd    int := ((bl_cfg('rent.due_weekday')::int % 7) + 7) % 7;
  v_tz    text;
  v_d     date;
  v_speed numeric; v_off numeric; v_epoch timestamptz; v_gm numeric; v_k bigint;
begin
  if bl_clock_mode() = 'real' then
    v_tz := bl_clock_tz();
    v_d := ((p_from at time zone v_tz)
            + make_interval(secs => (greatest(p_grace_game_days, 0) * 86400)::double precision))::date + 1;
    v_d := v_d + ((((v_wd - (extract(isodow from v_d)::int - 1)) % 7) + 7) % 7);
    return v_d::timestamp at time zone v_tz;
  end if;
  v_speed := greatest(bl_cfg('clock.game_minutes_per_real_minute'), 0.0001);
  v_off   := bl_cfg('clock.start_hour_offset') * 60;
  v_epoch := bl_cfg_text('clock.epoch')::timestamptz;
  v_gm := extract(epoch from (p_from - v_epoch)) * v_speed / 60.0 + v_off + greatest(p_grace_game_days, 0) * 1440;
  v_k := floor(v_gm / 1440)::bigint + 1;
  v_k := v_k + (((v_wd - v_k) % 7) + 7) % 7;
  return v_epoch + make_interval(secs => ((v_k * 1440 - v_off) * 60.0 / v_speed)::double precision);
end $$;

-- Switching clock mode / time zone re-aligns rent days (never back-charges) and clears the stored
-- day numbers (they belong to the other clock; clearing only ever lets a player claim/work again).
create or replace function public.bl_clock_switch_trigger() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.value is distinct from new.value then
    update profiles set rent_due_at = bl_rent_due_after(bl_now(), 0) where rent_due_at is not null;
    update profiles set allowance_claimed_day = null where allowance_claimed_day is not null;
    update profiles set job_shift_day = null, job_shifts_today = 0 where job_shift_day is not null;
  end if;
  return new;
end $$;

drop trigger if exists game_config_clock_switch on public.game_config;
create trigger game_config_clock_switch after update on public.game_config
  for each row when (new.key in ('clock.mode', 'clock.timezone')) execute function public.bl_clock_switch_trigger();

-- ---------------------------------------------------------------------
-- 4. Needs decay: need-hours per real hour
-- ---------------------------------------------------------------------
create or replace function public.bl_need_hours_per_real_hour() returns numeric
language sql stable set search_path = public as $$
  select case when public.bl_clock_mode() = 'real' then greatest(public.bl_cfg('needs.decay_speed'), 0)
              else public.bl_cfg('clock.game_minutes_per_real_minute') end;
$$;

-- Same as R4 (bladder) except the elapsed need-hours.
create or replace function public.bl_decay_row(p_row public.profiles, p_at timestamptz) returns public.profiles
language plpgsql stable set search_path = public as $$
declare
  v        profiles := p_row;
  v_hours  numeric;
  r_hun    numeric; r_en numeric; r_hy numeric; r_fun numeric; r_soc numeric; r_str numeric; r_bl numeric;
  r_starve numeric; v_floor numeric; r_acc numeric;
  v_zero   numeric; v_bzero numeric;
  v_health numeric; v_hyg numeric;
begin
  if v.id is null then return v; end if;
  v_hours := extract(epoch from (p_at - v.needs_updated_at))::numeric / 3600.0 * bl_need_hours_per_real_hour();
  if v_hours <= 0 then return v; end if;

  r_hun := bl_cfg('needs.hunger_per_hour')  * bl_trait_mult(v.traits, 'hunger');
  r_en  := bl_cfg('needs.energy_per_hour')  * bl_trait_mult(v.traits, 'energy');
  r_hy  := bl_cfg('needs.hygiene_per_hour') * bl_trait_mult(v.traits, 'hygiene');
  r_fun := bl_cfg('needs.fun_per_hour')     * bl_trait_mult(v.traits, 'fun');
  r_soc := bl_cfg('needs.social_per_hour')  * bl_trait_mult(v.traits, 'social');
  r_str := bl_cfg('needs.stress_per_hour')  * bl_trait_mult(v.traits, 'stress');
  r_bl  := coalesce(bl_cfg('needs.bladder_per_hour'), 0) * bl_trait_mult(v.traits, 'bladder');
  r_acc := greatest(0, coalesce(bl_cfg('needs.bladder_empty_hygiene_per_hour'), 0));
  r_starve := bl_cfg('needs.starve_health_per_hour');
  v_floor  := bl_cfg('needs.starve_health_floor');

  v_zero := least(case when r_hun > 0 then greatest(v.hunger, 0) / r_hun else 1e9 end,
                  case when r_en  > 0 then greatest(v.energy, 0) / r_en  else 1e9 end);
  v_health := v.health - greatest(0, v_hours - v_zero) * r_starve;
  v_health := greatest(v_health, least(v.health, v_floor));

  v_bzero := case when r_bl > 0 then greatest(coalesce(v.bladder, 100), 0) / r_bl else 1e9 end;
  v_hyg := v.hygiene - r_hy * v_hours - greatest(0, v_hours - v_bzero) * r_acc;

  v.hunger  := round(greatest(0, least(100, v.hunger  - r_hun * v_hours)), 4);
  v.energy  := round(greatest(0, least(100, v.energy  - r_en  * v_hours)), 4);
  v.hygiene := round(greatest(0, least(100, v_hyg)), 4);
  v.fun     := round(greatest(0, least(100, v.fun     - r_fun * v_hours)), 4);
  v.social  := round(greatest(0, least(100, v.social  - r_soc * v_hours)), 4);
  v.stress  := round(greatest(0, least(100, v.stress  + r_str * v_hours)), 4);
  v.bladder := round(greatest(0, least(100, coalesce(v.bladder, 100) - r_bl * v_hours)), 4);
  v.health  := round(greatest(0, least(100, v_health)), 4);
  v.needs_updated_at := p_at;
  return v;
end $$;

-- ---------------------------------------------------------------------
-- 5. Action timing
-- ---------------------------------------------------------------------
create or replace function public.bl_action_short() returns boolean
language sql stable set search_path = public as $$
  select coalesce((select value #>> '{}' from game_config where key = 'action.mode'), 'short') <> 'game_minutes';
$$;

-- The need values an action starts from (for the live-filling bars).
create or replace function public.bl_needs_snapshot(p_me public.profiles) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('hunger', p_me.hunger, 'energy', p_me.energy, 'hygiene', p_me.hygiene,
                            'fun', p_me.fun, 'social', p_me.social, 'stress', p_me.stress,
                            'health', p_me.health, 'bladder', p_me.bladder);
$$;

-- Real seconds an activity takes for this player (p_me already decayed; p_eff = the activity's effects).
create or replace function public.bl_activity_seconds(p_me public.profiles, p_act public.activities, p_eff jsonb)
returns numeric
language plpgsql stable set search_path = public as $$
declare
  v_max  numeric;
  v_min  numeric;
  v_key  text;
  v_miss numeric;
  v_cur  jsonb := to_jsonb(p_me);
begin
  if not bl_action_short() then return bl_real_seconds(p_act.game_minutes); end if;
  v_max := greatest(coalesce(p_act.max_seconds, 8), 0.5);
  v_min := least(greatest(coalesce(p_act.min_seconds, 0), 0), v_max);
  if not (bl_cfg_bool('action.scale_by_need') and coalesce(p_act.scale_by_need, true)) then
    return round(v_max, 1);
  end if;
  select k into v_key
    from unnest(array['energy','hunger','hygiene','bladder','fun','social']) with ordinality as t(k, o)
   where coalesce((p_eff->>k)::numeric, 0) > 0
   order by (p_eff->>k)::numeric desc, o
   limit 1;
  if v_key is not null then
    v_miss := 100 - coalesce((v_cur->>v_key)::numeric, 100);
  elsif coalesce((p_eff->>'stress')::numeric, 0) < 0 then
    v_miss := coalesce(p_me.stress, 0);
  else
    return round(v_max, 1);
  end if;
  v_miss := greatest(0, least(100, v_miss));
  return round(greatest(v_min, v_max * v_miss / 100.0), 1);
end $$;

-- Real seconds one work shift takes.
create or replace function public.bl_shift_seconds(p_game_minutes int) returns numeric
language sql stable set search_path = public as $$
  select case when public.bl_action_short() then greatest(public.bl_cfg('action.shift_seconds'), 1)
              else public.bl_real_seconds(p_game_minutes) end;
$$;

-- Busy for p_seconds real seconds (stamps busy_started_at; clears busy_needs_from).
create or replace function public.bl_set_busy_seconds(p_uid uuid, p_seconds numeric, p_label text) returns timestamptz
language plpgsql set search_path = public as $$
declare v_until timestamptz; v_now timestamptz := bl_now();
begin
  update profiles set
    busy_started_at = v_now,
    busy_until = v_now + make_interval(secs => greatest(coalesce(p_seconds, 0), 0)::double precision),
    busy_label = p_label,
    busy_needs_from = null
  where id = p_uid
  returning busy_until into v_until;
  return v_until;
end $$;

-- Same signature as before (jail/hospital/game-minute timers).
create or replace function public.bl_set_busy(p_uid uuid, p_game_minutes int, p_label text) returns timestamptz
language sql set search_path = public as $$
  select public.bl_set_busy_seconds(p_uid, public.bl_real_seconds(p_game_minutes), p_label);
$$;

-- Activity: same checks/effects as V1-3 (shops); the duration now comes from bl_activity_seconds and the
-- starting need values are kept in busy_needs_from.
create or replace function public.do_activity(p_activity text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me     profiles := bl_me();
  a        activities;
  v_scene  text;
  v_until  timestamptz;
  v_eff    jsonb;
  v_used   text[] := '{}';
  r        record;
  v_pct    numeric;
  v_rent   boolean := false;
  v_msg    text;
  v_from   jsonb;
  v_secs   numeric;
begin
  perform bl_assert_free(v_me);
  select * into a from activities where id = p_activity;
  if not found then
    raise exception 'That activity doesn''t exist.' using errcode = 'P0001';
  end if;
  select scene into v_scene from locations where id = v_me.location_id;
  if not (v_scene = any(a.scenes)) then
    raise exception 'You can''t do "%" here. Go where it is offered.', a.name using errcode = 'P0001';
  end if;
  if a.home_only and v_me.location_id <> v_me.home_location_id then
    raise exception 'You can only do "%" in your own home.', a.name using errcode = 'P0001';
  end if;
  if a.night_only and not (bl_game_clock()->>'is_night')::boolean then
    raise exception '"%" is a night-time thing. Come back after dark.', a.name using errcode = 'P0001';
  end if;
  if a.cost > 0 then
    perform bl_add_money(v_me.id, 'cash', -a.cost, 'activity', jsonb_build_object('activity', a.id));
  end if;

  v_eff := a.effects;
  for r in select it.id, it.name, it.effects->'boost'->a.id as bonus
             from inventory i join items it on it.id = i.item_id
            where i.user_id = v_me.id and i.qty > 0 and jsonb_typeof(it.effects->'boost'->a.id) = 'object'
            order by it.sort, it.id loop
    v_eff := v_eff || bl_effects_add(bl_need_effects(v_eff), bl_need_effects(r.bonus));
    perform bl_give_item(v_me.id, r.id, -1);
    v_used := v_used || r.name;
  end loop;
  if v_me.rent_owed > 0 and bl_csv_has(bl_cfg_text('rent.owed_sleep_activities'), a.id)
     and coalesce((v_eff->>'energy')::numeric, 0) > 0 then
    v_pct := greatest(0, least(100, bl_cfg('rent.owed_sleep_energy_pct')));
    if v_pct < 100 then
      v_eff := v_eff || jsonb_build_object('energy', round((v_eff->>'energy')::numeric * v_pct / 100, 1));
      v_rent := true;
    end if;
  end if;

  v_from := bl_needs_snapshot(v_me);
  v_secs := bl_activity_seconds(v_me, a, a.effects);
  perform bl_adjust_needs(v_me.id, v_eff);
  if coalesce((v_eff->>'street_cred')::int, 0) <> 0 then
    update profiles set street_cred = greatest(0, street_cred + (v_eff->>'street_cred')::int) where id = v_me.id;
  end if;
  v_until := bl_set_busy_seconds(v_me.id, v_secs, a.name);
  update profiles set busy_needs_from = v_from where id = v_me.id;
  v_msg := 'You started "' || a.name || '"'
           || case when a.cost > 0 then ' (' || bl_naira(a.cost) || ').' else '. Enjoy!' end;
  if cardinality(v_used) > 0 then
    v_msg := v_msg || ' Used: ' || array_to_string(v_used, ', ') || '.';
  end if;
  if v_rent then
    v_msg := v_msg || ' The landlord keeps knocking: "Where my rent? You owe ' || bl_naira(v_me.rent_owed)
             || '!" You won''t rest well until you pay.';
  end if;
  return jsonb_build_object('message', v_msg, 'busy_until', v_until, 'effects', v_eff,
                            'used', to_jsonb(v_used), 'rent_penalty', v_rent, 'real_seconds', v_secs);
end $$;

-- Work shift: same as V1-2 (careers) except the duration (bl_shift_seconds) and busy_needs_from.
create or replace function public.work_shift() returns jsonb
language plpgsql security definer set search_path = public as $$
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
end $$;

-- Travel quote: same as R3a (creator) plus the action.travel_max_seconds cap in short mode.
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
      v_reason := 'Keke no fit pass there. Keke is banned on the major roads.';
    elsif m = 'car' and not v_has_car then
      v_allowed := false;
      v_reason := 'You don''t have a motor yet. Buy one first.';
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

-- Bank closed message: plain real times in real mode ("It opens at 8:00 AM, in about 9 hr").
create or replace function public.bl_assert_bank_open(p_name text) returns void
language plpgsql stable set search_path = public as $$
declare
  v_clock jsonb := bl_game_clock();
  v_in    int;
  v_real  numeric;
  v_wait  text;
begin
  if bl_bank_open(v_clock) then return; end if;
  v_in := bl_bank_opens_in(v_clock);
  v_wait := case when v_in >= 60 then round(v_in / 60.0) || ' hr' || case when round(v_in / 60.0) = 1 then '' else 's' end
                 else v_in || ' min' end;
  if bl_clock_mode() = 'real' then
    raise exception '% is closed. Banking hours are % to %. It opens at %, in about %. After hours, a PoS stand can help: %.',
      p_name, bl_hour_text(bl_cfg('bank.open_hour')::int), bl_hour_text(bl_cfg('bank.close_hour')::int),
      bl_hour_text(bl_cfg('bank.open_hour')::int), v_wait,
      coalesce(bl_places_with('pos'), 'any PoS stand')
      using errcode = 'P0001', hint = 'closed';
  end if;
  v_real := v_in * 60.0 / bl_clock_speed();
  raise exception '% is closed. Banking hours are % to % (game time); it opens in about % (% real). After hours, a PoS stand can help: %.',
    p_name, bl_hour_text(bl_cfg('bank.open_hour')::int), bl_hour_text(bl_cfg('bank.close_hour')::int), v_wait,
    case when v_real >= 60 then ceil(v_real / 60) || ' min' else ceil(v_real) || ' sec' end,
    coalesce(bl_places_with('pos'), 'any PoS stand')
    using errcode = 'P0001', hint = 'closed';
end $$;

-- bank_info: same as V1-5 except opens_in_real_seconds follows the clock mode.
create or replace function public.bank_info() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_me    profiles;
  v_clock jsonb := bl_game_clock();
  v_in    int;
  v_st    jsonb;
  v_limit bigint := bl_cfg('bank.transfer_daily_limit')::bigint;
  v_wait  numeric;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  v_in := bl_bank_opens_in(v_clock);
  v_st := bl_transfer_stats(v_uid);
  v_wait := greatest(0, bl_cfg('bank.transfer_min_account_real_minutes') * 60
                         - extract(epoch from bl_now() - v_me.created_at));
  return jsonb_build_object(
    'cash', v_me.cash, 'bank', v_me.bank,
    'min_amount', bl_cfg('bank.min_amount'),
    'bank_hours', jsonb_build_object(
      'open_hour', bl_cfg('bank.open_hour'), 'close_hour', bl_cfg('bank.close_hour'),
      'open', v_in = 0, 'opens_in_game_minutes', v_in,
      'opens_in_real_seconds', ceil(v_in * 60.0 / bl_clock_speed())),
    'pos', jsonb_build_object(
      'fee_pct', bl_cfg('pos.fee_pct'), 'fee_min', bl_cfg('pos.fee_min'), 'max_amount', bl_cfg('pos.max_amount'),
      'max_cashout', bl_pos_max(v_me.bank), 'max_deposit', bl_pos_max(v_me.cash)),
    'transfer', jsonb_build_object(
      'fee', bl_cfg('bank.transfer_fee'), 'min_amount', bl_cfg('bank.transfer_min_amount'),
      'daily_limit', v_limit, 'sent_today', (v_st->>'sent')::bigint,
      'left_today', greatest(0, v_limit - (v_st->>'sent')::bigint),
      'count_today', (v_st->>'count')::int, 'daily_count', bl_cfg('bank.transfer_daily_count'),
      'cooldown_real_seconds', bl_cfg('bank.transfer_cooldown_real_seconds'),
      'new_account_wait_real_seconds', ceil(v_wait)),
    'tip_cash_threshold', bl_cfg('bank.tip_cash_threshold'),
    'places', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'district', district,
                                         'kind', case when 'bank' = any (actions) then 'bank' else 'pos' end)
                                         order by ('bank' = any (actions)) desc, sort, id)
                          from locations where 'bank' = any (actions) or 'pos' = any (actions)), '[]'::jsonb));
end $$;

-- Admin table whitelist: same as V1-7 plus the activity timing columns.
create or replace function public.bl_admin_table_spec(p_table text) returns jsonb
language sql immutable as $$
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
              "max_seconds":"num","min_seconds":"num","scale_by_need":"bool","effects":"obj","sort":"int"}}'
    when 'locations' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","blurb":"text","risk":"num","night_risk_mult":"num","cctv":"bool","keke_ok":"bool",
              "congestion":"num","remote_km":"num","actions":"arr","sort":"int"}}'
    when 'chat_banned_words' then '{"pk":["word"],"insert":true,"order":"word","cols":{"active":"bool"}}'
  end::jsonb;
$$;

-- ---------------------------------------------------------------------
-- 6. One-time re-alignment (first apply only), then clock.mode
-- ---------------------------------------------------------------------
do $$
declare
  v_first boolean := not exists (select 1 from public.game_config where key = 'clock.mode');
begin
  if not v_first then return; end if;
  -- bl_clock_mode() reads 'real' while the key is missing, so everything below uses the real clock.
  -- ledger day stamps (allowance, transfers) → the real day each row was written
  update public.ledger l
     set meta = l.meta || jsonb_build_object('day', (public.bl_game_clock(l.created_at)->>'day')::bigint,
                                             'accel_day', l.meta->'day')
   where l.meta ? 'day' and not (l.meta ? 'accel_day')
     and l.reason in ('allowance', 'transfer_out', 'transfer_in');
  -- allowance: the real day of the player's last allowance (null = never claimed)
  update public.profiles p
     set allowance_claimed_day = (select (public.bl_game_clock(max(l.created_at))->>'day')::int
                                    from public.ledger l where l.user_id = p.id and l.reason = 'allowance')
   where p.allowance_claimed_day is not null;
  -- shifts per day: start fresh (in the player's favour, once)
  update public.profiles set job_shift_day = null, job_shifts_today = 0 where job_shift_day is not null;
  -- rent: the first real rent day after now + the new-tenant grace (no back-charge; rent_owed kept)
  update public.profiles
     set rent_due_at = public.bl_rent_due_after(public.bl_now(), public.bl_cfg('rent.first_due_grace_game_days'))
   where rent_due_at is not null;
end $$;

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('clock.mode', '"real"', 'clock', 'Clock mode',
 'real = the game clock is the real time in Benin City (clock.timezone): day/night, rent day, bank hours and daily limits follow the real calendar. accelerated = the old fast clock (clock.game_minutes_per_real_minute).',
 'text', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 7. Privileges (internal helpers)
-- ---------------------------------------------------------------------
revoke execute on function public.bl_clock_mode()                     from public, anon, authenticated;
revoke execute on function public.bl_clock_tz()                       from public, anon, authenticated;
revoke execute on function public.bl_clock_speed()                    from public, anon, authenticated;
revoke execute on function public.bl_clock_switch_trigger()           from public, anon, authenticated;
revoke execute on function public.bl_need_hours_per_real_hour()       from public, anon, authenticated;
revoke execute on function public.bl_action_short()                   from public, anon, authenticated;
revoke execute on function public.bl_needs_snapshot(public.profiles)  from public, anon, authenticated;
revoke execute on function public.bl_activity_seconds(public.profiles, public.activities, jsonb) from public, anon, authenticated;
revoke execute on function public.bl_shift_seconds(int)               from public, anon, authenticated;
revoke execute on function public.bl_set_busy_seconds(uuid, numeric, text) from public, anon, authenticated;
revoke execute on function public.bl_set_busy(uuid, int, text)        from public, anon, authenticated;
revoke execute on function public.bl_game_clock(timestamptz)          from public, anon, authenticated;
revoke execute on function public.bl_rent_due_after(timestamptz, numeric) from public, anon, authenticated;
revoke execute on function public.bl_decay_row(public.profiles, timestamptz) from public, anon, authenticated;
revoke execute on function public.bl_travel_quote(public.profiles, text) from public, anon, authenticated;
revoke execute on function public.bl_assert_bank_open(text)           from public, anon, authenticated;
revoke execute on function public.bl_game_config_validate()           from public, anon, authenticated;
revoke execute on function public.do_activity(text)                   from public, anon;
revoke execute on function public.work_shift()                        from public, anon;
revoke execute on function public.bank_info()                         from public, anon;
grant execute on function public.do_activity(text)                    to authenticated;
grant execute on function public.work_shift()                         to authenticated;
grant execute on function public.bank_info()                          to authenticated;
