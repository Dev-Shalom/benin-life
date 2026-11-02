-- Benin Life: Admin Grant toolbox, part 1 (docs/ADMIN_GRANTS.md).
-- "I want to grant a player ANYTHING that exists in the game." Part 1: shared helpers, career, needs and stuck states,
-- jail, street cred / wanted / path numbers, debts, Yahoo rank, and the read side (admin_grant_state, admin_grant_catalog).
-- Parts 2 and 3: 20261107000200_admin_grants_things.sql, 20261107000300_admin_grants_assets.sql.
--
-- Every RPC: bl_admin_guard() first, validates ids and ranges, goes through the same tables the game uses, writes an
-- admin_audit row (who, player, what, old, new, reason) and sends the player a normal alert (events row).
-- Nothing here writes the money ledger, so a grant is never counted as "earned" (leaderboard.earn_reasons only lists
-- salary, hustle, business_income ... and admin_grant is not one of them).
-- Idempotent: create or replace only; no table changes; never loops over players; does not touch the profiles table definition.

-- ---------------------------------------------------------------------
-- 1. Helpers (internal: revoked from anon and authenticated)
-- ---------------------------------------------------------------------
create or replace function public.bl_ag_fail(p_msg text, p_hint text) returns void
language plpgsql set search_path = public as $$
begin
  raise exception '%', p_msg using errcode = 'P0001', hint = p_hint;
end $$;

-- The player a grant lands on, locked. Deleted accounts have no profile row; banned accounts are refused
-- (taking something back is still allowed: p_taking = true).
create or replace function public.bl_ag_target(p_user uuid, p_taking boolean default false) returns profiles
language plpgsql security definer set search_path = public as $$
declare p profiles;
begin
  if p_user is null then
    perform bl_ag_fail('Pick a player first.', 'no_player');
  end if;
  select * into p from profiles where id = p_user for update;
  if not found then
    perform bl_ag_fail('That player doesn''t exist (or the account was deleted).', 'no_player');
  end if;
  if p.banned and not coalesce(p_taking, false) then
    perform bl_ag_fail('That account is banned. Unban it first, then grant.', 'banned');
  end if;
  return p;
end $$;

-- Short note for the audit log and the player's alert. Required (3+ letters) for level and money-like grants.
create or replace function public.bl_ag_reason(p_reason text, p_required boolean default false) returns text
language plpgsql immutable set search_path = public as $$
declare v text := left(btrim(coalesce(p_reason, '')), 200);
begin
  if coalesce(p_required, false) and char_length(v) < 3 then
    perform bl_ag_fail('Add a short reason (at least 3 letters). The player sees it.', 'reason_required');
  end if;
  return v;
end $$;

create or replace function public.bl_ag_log(p_admin uuid, p_user uuid, p_action text, p_data jsonb) returns void
language sql security definer set search_path = public as $$
  insert into admin_audit (admin_id, action, target_user, data) values (p_admin, p_action, p_user, coalesce(p_data, '{}'::jsonb));
$$;

-- The player's alert. kind 'admin_grant' toasts green ("grant" in the name), 'admin_take' is plain.
create or replace function public.bl_ag_alert(p_user uuid, p_kind text, p_title text, p_body text, p_reason text, p_data jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform bl_event(p_user, p_kind, p_title,
                   p_body || case when coalesce(p_reason, '') <> '' then ' Reason: ' || p_reason else '' end,
                   coalesce(p_data, '{}'::jsonb) || jsonb_build_object('admin', true, 'reason', coalesce(p_reason, '')));
end $$;

revoke execute on function public.bl_ag_fail(text, text)                                     from public, anon, authenticated;
revoke execute on function public.bl_ag_target(uuid, boolean)                                from public, anon, authenticated;
revoke execute on function public.bl_ag_reason(text, boolean)                                from public, anon, authenticated;
revoke execute on function public.bl_ag_log(uuid, uuid, text, jsonb)                         from public, anon, authenticated;
revoke execute on function public.bl_ag_alert(uuid, text, text, text, text, jsonb)           from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Career: job, level, XP (same columns job_apply and bl_settle_shift write)
-- ---------------------------------------------------------------------
create or replace function public.admin_grant_career(p_user uuid, p_track text, p_level int default null, p_xp int default null,
                                                     p_reset_best boolean default false, p_reason text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  v_reason text := bl_ag_reason(p_reason, true);
  p profiles; t career_tracks; cl career_levels; v_top int; v_lvl int; v_xp int; v_same boolean; v_old_title text; v_best int; v_up boolean;
begin
  p := bl_ag_target(p_user);
  perform bl_settle_shift(p_user);                      -- a shift that already ended is paid the normal way first
  select * into p from profiles where id = p_user;
  if p.job_shift_ends_at is not null then
    perform bl_ag_fail('They are in the middle of a shift. Wait for it to end, or clear the shift under "Stuck states" first.', 'on_shift');
  end if;
  select * into t from career_tracks where id = p_track and active;
  if not found then
    perform bl_ag_fail('That job doesn''t exist.', 'bad_track');
  end if;
  select max(level) into v_top from career_levels where track_id = t.id;
  v_same := p.job_id is not distinct from t.id;
  v_lvl := coalesce(p_level, case when v_same then p.job_level else 1 end);
  if v_lvl < 1 or v_lvl > coalesce(v_top, 0) then
    perform bl_ag_fail('Career level for ' || t.name || ' goes from 1 to ' || coalesce(v_top, 0) || '.', 'bad_value');
  end if;
  select * into cl from career_levels where track_id = t.id and level = v_lvl;
  v_xp := coalesce(p_xp, case when v_same and v_lvl = p.job_level then p.job_xp else 0 end);
  if v_xp < 0 or v_xp > coalesce(cl.xp_to_next, 1000000) then
    perform bl_ag_fail('XP at this level goes from 0 to ' || coalesce(cl.xp_to_next, 1000000) || '.', 'bad_value');
  end if;
  select title into v_old_title from career_levels where track_id = p.job_id and level = p.job_level;
  v_up := not v_same or v_lvl > p.job_level;
  v_best := greatest(coalesce((p.career_best ->> t.id)::int, 0), v_lvl);
  update profiles set job_id = t.id, job_level = v_lvl, job_xp = v_xp,
         job_shifts_in_level = case when not v_same or v_lvl <> p.job_level then 0 else job_shifts_in_level end,
         job_started_at = case when not v_same or job_started_at is null then bl_now() else job_started_at end,
         career_best = career_best || jsonb_build_object(t.id, case when coalesce(p_reset_best, false) then v_lvl else v_best end)
   where id = p_user;
  perform bl_ag_log(v_admin, p_user, 'grant_career', jsonb_build_object(
    'old', jsonb_build_object('track', p.job_id, 'level', p.job_level, 'xp', p.job_xp, 'title', v_old_title),
    'new', jsonb_build_object('track', t.id, 'level', v_lvl, 'xp', v_xp, 'title', cl.title),
    'reset_best', coalesce(p_reset_best, false), 'reason', v_reason));
  perform bl_ag_alert(p_user, case when v_up then 'admin_grant' else 'admin_take' end,
    'Career level ' || v_lvl || ': ' || cl.title,
    case when v_up then 'An admin gave you career level ' else 'An admin set your career to level ' end || v_lvl
      || ' (' || cl.title || ', ' || t.name || '). Pay is ' || bl_naira(cl.pay_per_shift) || ' a shift.',
    v_reason, jsonb_build_object('track', t.id, 'level', v_lvl));
  return jsonb_build_object('message', '@' || p.username || ' is now ' || cl.title || ' (' || t.name || ', level ' || v_lvl || ', ' || v_xp || ' XP).',
                            'track', t.id, 'level', v_lvl, 'xp', v_xp, 'title', cl.title);
end $$;

create or replace function public.admin_career_remove(p_user uuid, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true); p profiles; v_title text;
begin
  p := bl_ag_target(p_user, true);
  perform bl_settle_shift(p_user);
  select * into p from profiles where id = p_user;
  if p.job_id is null then
    perform bl_ag_fail('They don''t have a job.', 'no_job');
  end if;
  if p.job_shift_ends_at is not null then
    perform bl_ag_fail('They are in the middle of a shift. Wait for it to end, or clear the shift under "Stuck states" first.', 'on_shift');
  end if;
  select title into v_title from career_levels where track_id = p.job_id and level = p.job_level;
  update profiles set job_id = null, job_level = 1, job_xp = 0, job_shifts_in_level = 0, job_started_at = null where id = p_user;
  perform bl_ag_log(v_admin, p_user, 'career_remove', jsonb_build_object('track', p.job_id, 'level', p.job_level, 'xp', p.job_xp, 'title', v_title, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_take', 'Job ended', 'An admin ended your job as ' || coalesce(v_title, 'staff') || '. You can apply for another any time.', v_reason);
  return jsonb_build_object('message', 'Job removed from @' || p.username || '.');
end $$;

-- ---------------------------------------------------------------------
-- 3. Needs and stuck states
-- ---------------------------------------------------------------------
create or replace function public.admin_refill_needs(p_user uuid, p_needs text[] default null, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false);
  p profiles; v text[]; k text; v_old jsonb;
begin
  p := bl_ag_target(p_user);
  v := case when p_needs is null or cardinality(p_needs) = 0 then array['hunger', 'energy', 'hygiene', 'fun', 'social', 'health', 'stress', 'bladder'] else p_needs end;
  foreach k in array v loop
    if k <> all (array['hunger', 'energy', 'hygiene', 'fun', 'social', 'health', 'stress', 'bladder']) then
      perform bl_ag_fail('Unknown need "' || k || '".', 'bad_value');
    end if;
  end loop;
  p := bl_apply_needs(p_user);                           -- bring the numbers up to now first, like the game does
  v_old := jsonb_build_object('hunger', p.hunger, 'energy', p.energy, 'hygiene', p.hygiene, 'fun', p.fun, 'social', p.social,
                              'health', p.health, 'stress', p.stress, 'bladder', p.bladder);
  update profiles set
    hunger  = case when 'hunger'  = any (v) then 100 else hunger  end,
    energy  = case when 'energy'  = any (v) then 100 else energy  end,
    hygiene = case when 'hygiene' = any (v) then 100 else hygiene end,
    fun     = case when 'fun'     = any (v) then 100 else fun     end,
    social  = case when 'social'  = any (v) then 100 else social  end,
    health  = case when 'health'  = any (v) then 100 else health  end,
    stress  = case when 'stress'  = any (v) then 0   else stress  end,   -- stress: 0 is calm
    bladder = case when 'bladder' = any (v) then 100 else bladder end
   where id = p_user;
  perform bl_ag_log(v_admin, p_user, 'refill_needs', jsonb_build_object('needs', to_jsonb(v), 'old', v_old, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'Needs topped up', 'An admin refilled your ' || array_to_string(v, ', ') || '.', v_reason);
  return jsonb_build_object('message', 'Refilled ' || array_to_string(v, ', ') || ' for @' || p.username || '.');
end $$;

-- Stuck states: busy timer, road trip, a running shift, hospital stay. (Jail has its own RPC.)
create or replace function public.admin_clear_states(p_user uuid, p_what text[], p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false);
  p profiles; k text; v_done text[] := '{}'; v_old jsonb;
begin
  p := bl_ag_target(p_user, true);
  if p_what is null or cardinality(p_what) = 0 then
    perform bl_ag_fail('Pick what to clear.', 'bad_value');
  end if;
  foreach k in array p_what loop
    if k <> all (array['busy', 'travel', 'shift', 'hospital']) then
      perform bl_ag_fail('Unknown state "' || k || '".', 'bad_value');
    end if;
  end loop;
  v_old := jsonb_build_object('busy_label', p.busy_label, 'busy_until', p.busy_until, 'travel_to', p.travel_to,
                              'shift_ends_at', p.job_shift_ends_at, 'hospitalized_until', p.hospitalized_until);
  if 'shift' = any (p_what) then
    perform bl_settle_shift(p_user);                     -- an ended shift pays out the normal way
    update profiles set job_shift_ends_at = null, job_shift_pay = null, job_shift_xp = null, job_shift_perf = null
     where id = p_user and job_shift_ends_at is not null;
    v_done := array_append(v_done, 'shift'::text);
  end if;
  if 'busy' = any (p_what) then
    update profiles set busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null where id = p_user;
    v_done := array_append(v_done, 'busy timer'::text);
  end if;
  if 'travel' = any (p_what) then
    update profiles set travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null where id = p_user;
    v_done := array_append(v_done, 'road trip'::text);
  end if;
  if 'hospital' = any (p_what) then
    update profiles set hospitalized_until = null where id = p_user;
    v_done := array_append(v_done, 'hospital stay'::text);
  end if;
  perform bl_ag_log(v_admin, p_user, 'clear_states', jsonb_build_object('cleared', to_jsonb(p_what), 'old', v_old, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'You are free to move', 'An admin cleared your ' || array_to_string(v_done, ', ') || '.', v_reason);
  return jsonb_build_object('message', 'Cleared ' || array_to_string(v_done, ', ') || ' for @' || p.username || '.');
end $$;

-- Put in jail (seconds 1 to 3600, a real case like a police arrest) or release (seconds 0).
create or replace function public.admin_jail_set(p_user uuid, p_seconds int, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true);
  p profiles; v_now timestamptz := bl_now(); c jail_cases; v_loc text := bl_cfg_text('crime.jail_location'); v_n int;
begin
  if p_seconds is null or p_seconds < 0 or p_seconds > 3600 then
    perform bl_ag_fail('Jail time goes from 1 to 3600 seconds (0 releases).', 'bad_value');
  end if;
  p := bl_ag_target(p_user, p_seconds = 0);
  if p_seconds = 0 then
    update jail_cases set status = 'released', decided = true, closed_at = v_now, released_by = v_admin where user_id = p_user and status = 'open';
    get diagnostics v_n = row_count;
    update profiles set jailed_until = null, jail_reason = null where id = p_user;
    perform bl_ag_log(v_admin, p_user, 'jail_release', jsonb_build_object('cases_closed', v_n, 'was_jailed_until', p.jailed_until, 'reason', v_reason));
    perform bl_event(p_user, 'police_release', 'You are released', 'An admin let you out of the cell.' || case when v_reason <> '' then ' Reason: ' || v_reason else '' end,
                     jsonb_build_object('admin', true));
    return jsonb_build_object('message', '@' || p.username || ' released.');
  end if;
  if p.jailed_until is not null and p.jailed_until > v_now then
    perform bl_ag_fail('They are already in a cell. Release them first if you want to change the time.', 'already_jailed');
  end if;
  if p.hospitalized_until is not null and p.hospitalized_until > v_now then
    perform bl_ag_fail('They are in hospital right now. Discharge them first, then jail.', 'hospitalized');
  end if;
  insert into jail_cases (user_id, reason, location_id, bail_amount, jail_seconds, jail_until, created_at)
  values (p_user, 'Held by order of the Benin Life team', v_loc, greatest(0, round(bl_crime_num('crime.bail_base', 20000000)))::bigint,
          p_seconds, v_now + make_interval(secs => p_seconds), v_now)
  returning * into c;
  update profiles set jailed_until = c.jail_until, jail_reason = c.reason,
         location_id = coalesce((select id from locations where id = v_loc), location_id),
         travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
         busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
   where id = p_user;
  perform bl_ag_log(v_admin, p_user, 'jail_put', jsonb_build_object('case_id', c.id, 'seconds', p_seconds, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_jail', 'You are in a cell', 'An admin put you in jail for ' || p_seconds || ' seconds.', v_reason, jsonb_build_object('case_id', c.id));
  return jsonb_build_object('message', '@' || p.username || ' is in jail for ' || p_seconds || ' seconds.', 'case_id', c.id);
end $$;

-- ---------------------------------------------------------------------
-- 4. Numbers: street cred, wanted level, path (reputation) numbers, debts, Yahoo rank
-- ---------------------------------------------------------------------
create or replace function public.admin_set_numbers(p_user uuid, p_street_cred int default null, p_wanted int default null,
                                                    p_path jsonb default null, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true);
  p profiles; r player_path; k text; x numeric; v_old jsonb; v_new jsonb; v_msg text[] := '{}';
begin
  if p_street_cred is null and p_wanted is null and (p_path is null or p_path = '{}'::jsonb) then
    perform bl_ag_fail('Nothing to set.', 'bad_value');
  end if;
  if p_street_cred is not null and (p_street_cred < 0 or p_street_cred > 1000000) then
    perform bl_ag_fail('Street cred goes from 0 to 1,000,000.', 'bad_value');
  end if;
  if p_wanted is not null and (p_wanted < 0 or p_wanted > 5) then
    perform bl_ag_fail('Wanted level goes from 0 to 5.', 'bad_value');
  end if;
  if p_path is not null then
    if jsonb_typeof(p_path) <> 'object' then
      perform bl_ag_fail('Path numbers must be an object.', 'bad_value');
    end if;
    for k in select jsonb_object_keys(p_path) loop
      if k <> all (bl_path_keys()) then
        perform bl_ag_fail('Unknown path number "' || k || '".', 'bad_value');
      end if;
      begin
        x := (p_path ->> k)::numeric;
      exception when others then
        perform bl_ag_fail('"' || k || '" must be a number from -100 to 100.', 'bad_value');
      end;
      if x is null or x <> trunc(x) or x < -100 or x > 100 then
        perform bl_ag_fail('"' || k || '" must be a whole number from -100 to 100.', 'bad_value');
      end if;
    end loop;
  end if;
  p := bl_ag_target(p_user);
  r := bl_path_get(p_user);                              -- creates the row and applies the weekly drift first
  v_old := jsonb_build_object('street_cred', p.street_cred, 'wanted', p.wanted, 'path', to_jsonb(r) - 'user_id' - 'bands' - 'last_whisper' - 'decayed_on' - 'updated_at');
  update profiles set street_cred = coalesce(p_street_cred, street_cred), wanted = coalesce(p_wanted, wanted) where id = p_user;
  if p_path is not null and p_path <> '{}'::jsonb then
    update player_path set
      goodwill = coalesce((p_path ->> 'goodwill')::int, goodwill), hustle = coalesce((p_path ->> 'hustle')::int, hustle),
      luck     = coalesce((p_path ->> 'luck')::int, luck),         trouble = coalesce((p_path ->> 'trouble')::int, trouble),
      faith    = coalesce((p_path ->> 'faith')::int, faith),       family  = coalesce((p_path ->> 'family')::int, family),
      updated_at = bl_now()
     where user_id = p_user;
  end if;
  select * into r from player_path where user_id = p_user;
  select * into p from profiles where id = p_user;
  v_new := jsonb_build_object('street_cred', p.street_cred, 'wanted', p.wanted, 'path', to_jsonb(r) - 'user_id' - 'bands' - 'last_whisper' - 'decayed_on' - 'updated_at');
  if p_street_cred is not null then v_msg := array_append(v_msg, ('street cred ' || p.street_cred)::text); end if;
  if p_wanted is not null then v_msg := array_append(v_msg, ('wanted level ' || p.wanted)::text); end if;
  if p_path is not null and p_path <> '{}'::jsonb then v_msg := array_append(v_msg, 'path numbers'::text); end if;
  perform bl_ag_log(v_admin, p_user, 'set_numbers', jsonb_build_object('old', v_old, 'new', v_new, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'Your standing changed', 'An admin set your ' || array_to_string(v_msg, ', ') || '.', v_reason);
  return jsonb_build_object('message', 'Set ' || array_to_string(v_msg, ', ') || ' for @' || p.username || '.');
end $$;

-- Clear what a player owes: unpaid rent and unpaid weekly tax (money-like: reason required, no ledger row, nothing earned).
create or replace function public.admin_clear_debts(p_user uuid, p_rent boolean default true, p_tax boolean default true, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true); p profiles;
begin
  p := bl_ag_target(p_user);
  if not coalesce(p_rent, false) and not coalesce(p_tax, false) then
    perform bl_ag_fail('Pick rent, tax or both.', 'bad_value');
  end if;
  if (not coalesce(p_rent, false) or p.rent_owed = 0) and (not coalesce(p_tax, false) or p.tax_owed = 0) then
    perform bl_ag_fail('They don''t owe anything there.', 'nothing_owed');
  end if;
  update profiles set rent_owed = case when coalesce(p_rent, false) then 0 else rent_owed end,
                      tax_owed  = case when coalesce(p_tax, false) then 0 else tax_owed end
   where id = p_user;
  perform bl_ag_log(v_admin, p_user, 'clear_debts', jsonb_build_object('rent_owed', case when coalesce(p_rent, false) then p.rent_owed end,
                                                                        'tax_owed', case when coalesce(p_tax, false) then p.tax_owed end, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'Debt cleared', 'An admin cleared what you owed'
    || case when coalesce(p_rent, false) and p.rent_owed > 0 then ' in rent (' || bl_naira(p.rent_owed) || ')' else '' end
    || case when coalesce(p_tax, false) and p.tax_owed > 0 then ' in tax (' || bl_naira(p.tax_owed) || ')' else '' end || '.', v_reason);
  return jsonb_build_object('message', 'Cleared the debt for @' || p.username || '.');
end $$;

-- Yahoo rank: the rank follows total dirty money ever earned, so setting a rank sets that total to the rank's entry level.
create or replace function public.admin_set_yahoo_rank(p_user uuid, p_rank text, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true); p profiles; r yahoo_ranks; v_old bigint; v_old_rank text;
begin
  p := bl_ag_target(p_user);
  select * into r from yahoo_ranks where id = p_rank;
  if not found then
    perform bl_ag_fail('That Yahoo rank doesn''t exist.', 'bad_rank');
  end if;
  v_old := coalesce((select total_earned from yahoo_players where user_id = p_user), 0);
  v_old_rank := bl_yahoo_rank(p_user);
  insert into yahoo_players (user_id, total_earned, updated_at) values (p_user, r.min_earned, bl_now())
  on conflict (user_id) do update set total_earned = excluded.total_earned, updated_at = bl_now();
  perform bl_ag_log(v_admin, p_user, 'set_yahoo_rank', jsonb_build_object('old_rank', v_old_rank, 'new_rank', r.id, 'old_total', v_old, 'new_total', r.min_earned, 'reason', v_reason));
  perform bl_ag_alert(p_user, case when r.min_earned >= v_old then 'admin_grant' else 'admin_take' end, 'Yahoo rank: ' || r.name,
    'An admin set your Yahoo rank to ' || r.name || '.', v_reason);
  return jsonb_build_object('message', '@' || p.username || ' is now ' || r.name || ' in Yahoo.');
end $$;

-- ---------------------------------------------------------------------
-- 5. Privileges
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'admin_grant_career(uuid, text, int, int, boolean, text)', 'admin_career_remove(uuid, text)',
    'admin_refill_needs(uuid, text[], text)', 'admin_clear_states(uuid, text[], text)', 'admin_jail_set(uuid, int, text)',
    'admin_set_numbers(uuid, int, int, jsonb, text)', 'admin_clear_debts(uuid, boolean, boolean, text)',
    'admin_set_yahoo_rank(uuid, text, text)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
