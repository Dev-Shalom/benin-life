-- =====================================================================
-- Benin Life — time tuning: shorter busy timers, busy progress ring, game-day epoch
-- (owner: P1-TIME). Reference: docs/DB_CORE.md. Idempotent: safe to re-run.
--
-- * time.real_seconds_per_game_minute 5 -> 0.75: an 8-hour (480 game min) sleep now lasts
--   6 real minutes instead of 40. Busy/jail/hospital timers all use this key (bl_real_seconds).
--   Only rewritten while it still holds the old seed default 5, so an admin's later choice
--   survives a re-run of this migration.
-- * profiles.busy_started_at: set by bl_set_busy, so the client can draw a progress ring from
--   start to busy_until. Exposed through get_my_state's profile automatically (to_jsonb row).
-- * clock.epoch: launch instant the game clock counts from (was hard-coded 2026-01-01Z).
--   Default 2026-10-05T00:00:00Z, so the HUD starts near "Day 1". 2026-01-01 -> 2026-10-05 is
--   exactly 3324 game days at 12x, so the in-game hour of day does not jump; only the day number
--   resets.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Config
-- ---------------------------------------------------------------------
update public.game_config
   set value = '0.75'::jsonb,
       description = 'How long busy/jail/hospital timers last per game minute. 0.75 = an 8-hour sleep in 6 real minutes (timers run faster than the clock on purpose).'
 where key = 'time.real_seconds_per_game_minute'
   and (value #>> '{}')::numeric = 5;
-- keep it admin-tunable; make sure the range allows 0.75 (core seed: 0.1–60)
update public.game_config set min = 0.1
 where key = 'time.real_seconds_per_game_minute' and (min is null or min > 0.1);

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('clock.epoch', '"2026-10-05T00:00:00Z"', 'clock', 'Clock epoch (launch instant)',
 'Real UTC time the game clock counts from: at this instant it is Day 1, 00:00 + start offset. ISO timestamp, e.g. 2026-10-05T00:00:00Z. Changing it renumbers the days (keep it on an even UTC hour so the time of day no jump).',
 'text', null, null)
on conflict (key) do nothing;

-- Reject an epoch the server cannot parse (a bad value would break every bl_game_clock call).
create or replace function public.bl_game_config_validate() returns trigger
language plpgsql set search_path = public as $$
declare v timestamptz;
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
  end if;
  return new;
end $$;

drop trigger if exists game_config_validate on public.game_config;
create trigger game_config_validate before insert or update on public.game_config
  for each row execute function public.bl_game_config_validate();

-- ---------------------------------------------------------------------
-- 2. busy_started_at
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists busy_started_at timestamptz;

-- Same signature as core; also records when the activity started (for the client's progress ring).
create or replace function public.bl_set_busy(p_uid uuid, p_game_minutes int, p_label text) returns timestamptz
language plpgsql set search_path = public as $$
declare v_until timestamptz; v_now timestamptz := bl_now();
begin
  update profiles set
    busy_started_at = v_now,
    busy_until = v_now + make_interval(secs => bl_real_seconds(p_game_minutes)::double precision),
    busy_label = p_label
  where id = p_uid
  returning busy_until into v_until;
  return v_until;
end $$;

-- ---------------------------------------------------------------------
-- 3. Game clock from clock.epoch (same signature as core)
-- ---------------------------------------------------------------------
create or replace function public.bl_game_clock(p_at timestamptz default null) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_at    timestamptz := coalesce(p_at, bl_now());
  v_epoch timestamptz := bl_cfg_text('clock.epoch')::timestamptz;
  v_gm    bigint;
  v_hour  int;
  v_min   int;
  v_ns    int := bl_cfg('clock.night_start_hour')::int;
  v_ne    int := bl_cfg('clock.night_end_hour')::int;
begin
  -- multiply before dividing so whole real seconds map to exact game minutes (no 12.9999 -> 12)
  v_gm := floor(extract(epoch from (v_at - v_epoch))
                * bl_cfg('clock.game_minutes_per_real_minute') / 60.0
                + bl_cfg('clock.start_hour_offset') * 60)::bigint;
  v_hour := ((v_gm % 1440 + 1440) % 1440) / 60;
  v_min  := ((v_gm % 60) + 60) % 60;
  return jsonb_build_object(
    'game_minutes', v_gm,
    'day', floor(v_gm / 1440.0)::bigint + 1,
    'hour', v_hour,
    'minute', v_min,
    'is_night', case when v_ns > v_ne then (v_hour >= v_ns or v_hour < v_ne)
                     else (v_hour >= v_ns and v_hour < v_ne) end
  );
end $$;

-- internal helpers stay off the client API (core revokes bl_* the same way)
revoke execute on function public.bl_set_busy(uuid, int, text) from public, anon, authenticated;
revoke execute on function public.bl_game_clock(timestamptz) from public, anon, authenticated;
revoke execute on function public.bl_game_config_validate() from public, anon, authenticated;
