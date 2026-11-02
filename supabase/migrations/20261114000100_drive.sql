-- Drive scene road events (docs/DRIVE.md). Needs core + game_config.
--   * While a player travels (not on foot) the client shows a short 3D drive. Now and then a road event stops the car with a
--     choice card: area boys, a police checkpoint, a go-slow, a beggar or hawker at the window.
--   * Everything is decided here: drive_event_roll() rolls and remembers the event, drive_event_choose() rolls the outcome and
--     applies it (cash, health, stress, fun, the arrival time). The client only shows the cards.
--   * Rate limits: events a day, a cooldown, a gap between rolls, events per trip, how far into the trip. All admin-tunable
--     (game_config category 'drive'), as are the odds, the amounts and the on/off switches.
--   * drive_turn_back() ends a trip that has not arrived yet (no refund).
-- No profiles DDL, no triggers or foreign keys on profiles, no loops over players. Idempotent.

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('drive.enabled', 'true', 'drive', 'Drive scene on', 'Off = travel is the old instant jump for everybody (no 3D drive, no road events).', 'bool', null, null),
('drive.events_enabled', 'true', 'drive', 'Road events on', 'Off = the drive is just a scene: nothing stops the car.', 'bool', null, null),
('drive.presence_on', 'true', 'drive', 'Show other travellers', 'Show other players who are driving the same road (a light Realtime presence channel, no database writes).', 'bool', null, null),
('drive.event_pct', '35', 'drive', 'Chance of an event per check (%)', 'The app checks about every 8 seconds of the drive. This is the chance each check starts an event, once the limits below allow one.', 'percent', 0, 100),
('drive.max_per_day', '12', 'drive', 'Most events per player per day', 'Counted per Benin day. Stops anybody being spammed.', 'number', 0, 200),
('drive.max_per_trip', '1', 'drive', 'Most events per trip', 'One trip never stops more than this many times.', 'number', 0, 10),
('drive.cooldown_s', '90', 'drive', 'Cooldown between events (seconds)', 'After an event, the next one waits at least this long.', 'number', 0, 86400),
('drive.roll_gap_s', '4', 'drive', 'Shortest gap between checks (seconds)', 'A player cannot ask for a road event more often than this.', 'number', 0, 600),
('drive.min_progress_pct', '15', 'drive', 'No events before (% of the trip)', 'The first part of the trip is quiet.', 'percent', 0, 100),
('drive.max_progress_pct', '85', 'drive', 'No events after (% of the trip)', 'The last part of the trip is quiet, so you arrive in peace.', 'percent', 0, 100),
('drive.pending_ttl_s', '240', 'drive', 'How long an unanswered card waits (seconds)', 'After this the event is dropped with no effect.', 'number', 10, 3600),
('drive.min_cash', '2000', 'drive', 'Cash needed for money events', 'A player carrying less than this is not stopped by boys, police or beggars (they only get a go-slow).', 'naira', 0, 100000000),
('drive.max_delay_s', '40', 'drive', 'Most seconds events can add to one trip', 'All delays on one trip together never go over this.', 'number', 0, 600),
('drive.turn_back_on', 'true', 'drive', 'Turn back allowed', 'A player can cancel a trip before arriving (the fare is not refunded).', 'bool', null, null),

('drive.w_ambush', '30', 'drive', 'Event mix: area boys', 'Share (weight) of area boys ambushes among events. 0 = never.', 'number', 0, 1000),
('drive.w_police', '30', 'drive', 'Event mix: police checkpoint', 'Weight of police checkpoints.', 'number', 0, 1000),
('drive.w_goslow', '25', 'drive', 'Event mix: go-slow', 'Weight of traffic jams.', 'number', 0, 1000),
('drive.w_beggar', '15', 'drive', 'Event mix: beggar or hawker', 'Weight of a beggar or hawker at the window.', 'number', 0, 1000),
('drive.ambush_on', 'true', 'drive', 'Area boys on', 'Off = this event never happens.', 'bool', null, null),
('drive.police_on', 'true', 'drive', 'Police checkpoint on', 'Off = this event never happens.', 'bool', null, null),
('drive.goslow_on', 'true', 'drive', 'Go-slow on', 'Off = this event never happens.', 'bool', null, null),
('drive.beggar_on', 'true', 'drive', 'Beggar / hawker on', 'Off = this event never happens.', 'bool', null, null),

('drive.ambush.pay_pct', '6', 'drive', 'Area boys: demand (% of your cash)', 'What they ask for, as a share of the cash you carry.', 'percent', 0, 100),
('drive.ambush.pay_min', '1000', 'drive', 'Area boys: smallest demand', 'The demand is never below this (or your cash if less).', 'naira', 0, 100000000),
('drive.ambush.pay_max', '30000', 'drive', 'Area boys: largest demand', 'The demand is never above this.', 'naira', 0, 100000000),
('drive.ambush.escape_pct', '55', 'drive', 'Drive off: chance to get away (%)', 'You floor it and slip through. Nothing lost.', 'percent', 0, 100),
('drive.ambush.fail_mult', '2', 'drive', 'Drive off, failed: they take this many times the demand', 'When the escape fails they get more.', 'number', 0, 20),
('drive.ambush.damage_cost', '8000', 'drive', 'Drive off, failed: repair bill', 'A smashed mirror and a scratched door. Capped by your cash.', 'naira', 0, 100000000),
('drive.ambush.fail_health', '4', 'drive', 'Drive off, failed: health lost', 'You are shaken up, not hurt badly.', 'number', 0, 50),
('drive.ambush.police_on', 'true', 'drive', 'Call police: option shown', 'Off = the Call police button is hidden.', 'bool', null, null),
('drive.ambush.police_pct', '45', 'drive', 'Call police: chance they come in time (%)', 'The boys scatter. Nothing lost.', 'percent', 0, 100),
('drive.ambush.police_fail_pct', '50', 'drive', 'Call police, too late: share of the demand taken (%)', 'They still collect part of it, and you lose a little time.', 'percent', 0, 300),
('drive.ambush.police_delay_s', '12', 'drive', 'Call police, too late: seconds lost', 'Statements and waiting add time to the trip.', 'number', 0, 600),
('drive.ambush.stress', '8', 'drive', 'Area boys: stress added (any outcome but a clean escape)', 'Being stopped is stressful.', 'number', 0, 100),

('drive.police.papers_ok_pct', '70', 'drive', 'Checkpoint, show papers: chance all is fine (%)', 'Your papers are in order and you are waved on.', 'percent', 0, 100),
('drive.police.fine', '5000', 'drive', 'Checkpoint: fine when the papers do not pass', 'Also the base for the argue option.', 'naira', 0, 100000000),
('drive.police.settle', '3000', 'drive', 'Checkpoint, settle: what you pay', 'A flat amount, always accepted.', 'naira', 0, 100000000),
('drive.police.argue_pct', '30', 'drive', 'Checkpoint, argue: chance you are waved on (%)', 'Otherwise a bigger fine and lost time.', 'percent', 0, 100),
('drive.police.argue_fine_mult', '2', 'drive', 'Checkpoint, argue lost: fine multiplier', 'Times the normal fine.', 'number', 0, 20),
('drive.police.argue_delay_s', '15', 'drive', 'Checkpoint, argue lost: seconds lost', 'You wait at the roadside.', 'number', 0, 600),
('drive.police.stress', '4', 'drive', 'Checkpoint: stress added when you pay or lose', 'The roadside is tense.', 'number', 0, 100),

('drive.goslow.wait_s', '12', 'drive', 'Go-slow, wait: seconds added', 'You sit in the queue and the trip takes this much longer.', 'number', 0, 600),
('drive.goslow.wait_fun', '-2', 'drive', 'Go-slow, wait: fun change', 'Waiting is dull. Negative = less fun.', 'number', -100, 100),
('drive.goslow.shortcut_pct', '55', 'drive', 'Go-slow, shortcut: chance it works (%)', 'It works: you arrive sooner.', 'percent', 0, 100),
('drive.goslow.shortcut_save_s', '10', 'drive', 'Go-slow, shortcut worked: seconds saved', 'Taken off the trip.', 'number', 0, 600),
('drive.goslow.shortcut_fail_s', '20', 'drive', 'Go-slow, shortcut failed: seconds added', 'A bad road and a dead end.', 'number', 0, 600),
('drive.goslow.shortcut_fail_cost', '4000', 'drive', 'Go-slow, shortcut failed: repair cost', 'Potholes cost something. Capped by your cash.', 'naira', 0, 100000000),
('drive.goslow.stress', '3', 'drive', 'Go-slow: stress added when the shortcut fails', 'Heat and honking.', 'number', 0, 100),

('drive.beggar.give', '500', 'drive', 'Beggar, give: amount', 'What you hand over.', 'naira', 0, 10000000),
('drive.beggar.give_fun', '3', 'drive', 'Beggar, give: fun gained', 'It feels good to help.', 'number', -100, 100),
('drive.beggar.give_stress', '-2', 'drive', 'Beggar, give: stress change', 'Negative = calmer.', 'number', -100, 100),
('drive.beggar.water_cost', '200', 'drive', 'Hawker, pure water: price', 'A sachet of pure water through the window.', 'naira', 0, 10000000),
('drive.beggar.water_hunger', '2', 'drive', 'Hawker, pure water: hunger gained', 'A small refresh.', 'number', 0, 100),
('drive.beggar.water_fun', '2', 'drive', 'Hawker, pure water: fun gained', 'A cold sachet on a hot road.', 'number', 0, 100),
('drive.beggar.ignore_stress', '1', 'drive', 'Ignore: stress added', 'A small pang.', 'number', 0, 100)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Per-player state: counters and the card waiting for an answer (read only through the RPCs)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.drive_state (
  user_id       uuid primary key,
  day_key       date not null default current_date,
  events_today  int  not null default 0,
  last_event_at timestamptz,
  last_roll_at  timestamptz,
  trip_key      text,
  trip_events   int  not null default 0,
  trip_delay_s  int  not null default 0,
  pending       jsonb,
  pending_at    timestamptz
);
alter table public.drive_state enable row level security;
revoke all on public.drive_state from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 3. The event cards (text)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_drive_card(p_kind text, p_amount bigint) returns jsonb
language plpgsql stable set search_path = public as $$
declare v_police jsonb := '[]'::jsonb;
begin
  if p_kind = 'ambush' then
    if bl_cfg_bool('drive.ambush.police_on') then
      v_police := jsonb_build_array(jsonb_build_object('id', 'police', 'label', 'Call police', 'hint', 'They may not come in time.'));
    end if;
    return jsonb_build_object('kind', 'ambush', 'title', 'Area boys',
      'body', 'A few area boys step into the road and flag you down. "Oga, settle us small for the road."',
      'choices', jsonb_build_array(
        jsonb_build_object('id', 'pay',   'label', 'Pay them ' || bl_naira(p_amount), 'hint', 'Safe, but it costs.'),
        jsonb_build_object('id', 'drive', 'label', 'Drive off', 'hint', 'Risky: you might lose more.')) || v_police);
  elsif p_kind = 'police' then
    return jsonb_build_object('kind', 'police', 'title', 'Police checkpoint',
      'body', 'An officer waves you down at a checkpoint. "Good afternoon. Your particulars, please."',
      'choices', jsonb_build_array(
        jsonb_build_object('id', 'papers', 'label', 'Show papers', 'hint', 'Honest. Usually fine.'),
        jsonb_build_object('id', 'settle', 'label', 'Settle ' || bl_naira(p_amount), 'hint', 'Quick, but you pay.'),
        jsonb_build_object('id', 'argue',  'label', 'Argue', 'hint', 'Could cost you time and money.')));
  elsif p_kind = 'goslow' then
    return jsonb_build_object('kind', 'goslow', 'title', 'Go-slow',
      'body', 'Traffic is stuck bumper to bumper. Horns everywhere and nobody is moving.',
      'choices', jsonb_build_array(
        jsonb_build_object('id', 'wait',     'label', 'Wait', 'hint', 'A little longer, no risk.'),
        jsonb_build_object('id', 'shortcut', 'label', 'Take a shortcut', 'hint', 'Could save time, could go wrong.')));
  end if;
  return jsonb_build_object('kind', 'beggar', 'title', 'At the window',
    'body', 'A hawker taps your window with a tray of pure water. Beside him, an old woman holds out her hand.',
    'choices', jsonb_build_array(
      jsonb_build_object('id', 'give',   'label', 'Give ' || bl_naira(bl_cfg('drive.beggar.give')), 'hint', 'Help the old woman.'),
      jsonb_build_object('id', 'water',  'label', 'Buy pure water ' || bl_naira(bl_cfg('drive.beggar.water_cost')), 'hint', 'Cold and cheap.'),
      jsonb_build_object('id', 'ignore', 'label', 'Ignore', 'hint', 'Keep driving.')));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. drive_event_roll(): maybe start a road event for the trip in progress
-- ---------------------------------------------------------------------------------------------
create or replace function public.drive_event_roll() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me     profiles := bl_me();
  v_now    timestamptz := bl_now();
  v_day    date := (bl_now() at time zone 'Africa/Lagos')::date;
  v_key    text;
  s        drive_state;
  v_prog   numeric;
  v_w      numeric[];
  v_kind   text;
  v_sum    numeric;
  v_r      numeric;
  v_amount bigint := 0;
  v_cash   bigint;
begin
  if not bl_cfg_bool('drive.enabled') or not bl_cfg_bool('drive.events_enabled') then
    return jsonb_build_object('event', null, 'reason', 'off');
  end if;
  if v_me.travel_to is null or v_me.travel_mode is null or v_me.travel_mode = 'walk' then
    return jsonb_build_object('event', null, 'reason', 'not_driving');
  end if;
  v_key := v_me.travel_started_at::text;

  insert into drive_state (user_id, day_key) values (v_me.id, v_day) on conflict (user_id) do nothing;
  select * into s from drive_state where user_id = v_me.id for update;
  if s.day_key <> v_day then
    s.day_key := v_day; s.events_today := 0;
  end if;
  if s.trip_key is distinct from v_key then
    s.trip_key := v_key; s.trip_events := 0; s.trip_delay_s := 0; s.pending := null; s.pending_at := null;
  end if;

  -- a card still waiting (a reload): show it again until it expires
  if s.pending is not null then
    if s.pending_at > v_now - make_interval(secs => bl_cfg('drive.pending_ttl_s')::double precision) then
      update drive_state set day_key = s.day_key, events_today = s.events_today, trip_key = s.trip_key, trip_events = s.trip_events,
             trip_delay_s = s.trip_delay_s where user_id = v_me.id;
      return jsonb_build_object('event', bl_drive_card(s.pending->>'kind', coalesce((s.pending->>'amount')::bigint, 0)), 'resumed', true);
    end if;
    s.pending := null; s.pending_at := null;
  end if;

  -- limits: gap between checks, daily cap, trip cap, cooldown, where in the trip we are
  if s.last_roll_at is not null and v_now < s.last_roll_at + make_interval(secs => bl_cfg('drive.roll_gap_s')::double precision) then
    return jsonb_build_object('event', null, 'reason', 'too_soon');
  end if;
  s.last_roll_at := v_now;
  v_prog := greatest(0, least(1, extract(epoch from v_now - v_me.travel_started_at)
                                  / greatest(1, extract(epoch from v_me.travel_arrives_at - v_me.travel_started_at)))) * 100;
  v_cash := v_me.cash;
  v_w := array[
    case when bl_cfg_bool('drive.ambush_on') and v_cash >= bl_cfg('drive.min_cash') then bl_cfg('drive.w_ambush') else 0 end,
    case when bl_cfg_bool('drive.police_on') and v_cash >= bl_cfg('drive.min_cash') then bl_cfg('drive.w_police') else 0 end,
    case when bl_cfg_bool('drive.goslow_on') then bl_cfg('drive.w_goslow') else 0 end,
    case when bl_cfg_bool('drive.beggar_on') and v_cash >= bl_cfg('drive.min_cash') then bl_cfg('drive.w_beggar') else 0 end];
  v_sum := v_w[1] + v_w[2] + v_w[3] + v_w[4];

  if s.events_today >= bl_cfg('drive.max_per_day') or s.trip_events >= bl_cfg('drive.max_per_trip')
     or (s.last_event_at is not null and v_now < s.last_event_at + make_interval(secs => bl_cfg('drive.cooldown_s')::double precision))
     or v_prog < bl_cfg('drive.min_progress_pct') or v_prog > bl_cfg('drive.max_progress_pct')
     or v_sum <= 0 or bl_rand() * 100 >= bl_cfg('drive.event_pct') then
    update drive_state set day_key = s.day_key, events_today = s.events_today, last_roll_at = s.last_roll_at, trip_key = s.trip_key,
           trip_events = s.trip_events, trip_delay_s = s.trip_delay_s, pending = null, pending_at = null where user_id = v_me.id;
    return jsonb_build_object('event', null, 'reason', 'none');
  end if;

  v_r := bl_rand() * v_sum;
  v_kind := case when v_r < v_w[1] then 'ambush' when v_r < v_w[1] + v_w[2] then 'police'
                 when v_r < v_w[1] + v_w[2] + v_w[3] then 'goslow' else 'beggar' end;
  if v_kind = 'ambush' then
    v_amount := least(v_cash, least(bl_cfg('drive.ambush.pay_max')::bigint,
                  greatest(bl_cfg('drive.ambush.pay_min')::bigint, floor(v_cash * bl_cfg('drive.ambush.pay_pct') / 100.0)::bigint)));
  elsif v_kind = 'police' then
    v_amount := least(v_cash, bl_cfg('drive.police.settle')::bigint);
  end if;
  update drive_state set day_key = s.day_key, events_today = s.events_today + 1, last_event_at = v_now, last_roll_at = s.last_roll_at,
         trip_key = s.trip_key, trip_events = s.trip_events + 1, trip_delay_s = s.trip_delay_s,
         pending = jsonb_build_object('kind', v_kind, 'amount', v_amount), pending_at = v_now
   where user_id = v_me.id;
  return jsonb_build_object('event', bl_drive_card(v_kind, v_amount));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. drive_event_choose(choice): roll the outcome and apply it
-- ---------------------------------------------------------------------------------------------
create or replace function public.drive_event_choose(p_choice text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me     profiles := bl_me();
  v_now    timestamptz := bl_now();
  s        drive_state;
  v_kind   text;
  v_amount bigint;
  v_cash   bigint;
  v_loss   bigint := 0;
  v_repair bigint := 0;
  v_delay  int := 0;
  v_hp     numeric := 0;
  v_stress numeric := 0;
  v_fun    numeric := 0;
  v_hunger numeric := 0;
  v_msg    text;
  v_tone   text := 'neutral';
  v_arr    timestamptz;
  v_room   int;
  v_fine   bigint;
begin
  select * into s from drive_state where user_id = v_me.id for update;
  if not found or s.pending is null then
    raise exception 'There is nothing to decide right now.' using errcode = 'P0001', hint = 'no_event';
  end if;
  if s.pending_at < v_now - make_interval(secs => bl_cfg('drive.pending_ttl_s')::double precision)
     or v_me.travel_to is null or s.trip_key is distinct from v_me.travel_started_at::text then
    update drive_state set pending = null, pending_at = null where user_id = v_me.id;
    raise exception 'That moment has passed.' using errcode = 'P0001', hint = 'expired';
  end if;
  v_kind := s.pending->>'kind';
  v_amount := coalesce((s.pending->>'amount')::bigint, 0);
  v_cash := v_me.cash;

  if v_kind = 'ambush' then
    if p_choice = 'pay' then
      v_loss := least(v_cash, v_amount);
      v_stress := bl_cfg('drive.ambush.stress') / 2;
      v_msg := 'You hand over ' || bl_naira(v_loss) || '. The boys step aside and you drive on.'; v_tone := 'warn';
    elsif p_choice = 'drive' then
      if bl_rand() * 100 < bl_cfg('drive.ambush.escape_pct') then
        v_msg := 'You floor it and squeeze through. The boys shout behind you, but you are gone.'; v_tone := 'good';
      else
        v_loss := least(v_cash, floor(v_amount * bl_cfg('drive.ambush.fail_mult'))::bigint);
        v_repair := least(v_cash - v_loss, bl_cfg('drive.ambush.damage_cost')::bigint);
        v_hp := -bl_cfg('drive.ambush.fail_health'); v_stress := bl_cfg('drive.ambush.stress');
        v_msg := 'They block the road and bang the car. You lose ' || bl_naira(v_loss + v_repair) || ' and your mirror is smashed.'; v_tone := 'bad';
      end if;
    elsif p_choice = 'police' and bl_cfg_bool('drive.ambush.police_on') then
      if bl_rand() * 100 < bl_cfg('drive.ambush.police_pct') then
        v_msg := 'A police van turns up and the boys scatter. You drive on untouched.'; v_tone := 'good';
      else
        v_loss := least(v_cash, floor(v_amount * bl_cfg('drive.ambush.police_fail_pct') / 100.0)::bigint);
        v_delay := bl_cfg('drive.ambush.police_delay_s')::int; v_stress := bl_cfg('drive.ambush.stress');
        v_msg := 'The police come too late. The boys already took ' || bl_naira(v_loss) || ' and you lose some time.'; v_tone := 'bad';
      end if;
    else
      raise exception 'That choice is not on the card.' using errcode = 'P0001', hint = 'bad_choice';
    end if;
  elsif v_kind = 'police' then
    v_fine := least(v_cash, bl_cfg('drive.police.fine')::bigint);
    if p_choice = 'papers' then
      if bl_rand() * 100 < bl_cfg('drive.police.papers_ok_pct') then
        v_msg := 'The officer checks your papers and waves you through. "Safe journey."'; v_tone := 'good';
      else
        v_loss := v_fine; v_stress := bl_cfg('drive.police.stress');
        v_msg := 'Something is not in order. You pay a fine of ' || bl_naira(v_loss) || ' and go on.'; v_tone := 'bad';
      end if;
    elsif p_choice = 'settle' then
      v_loss := least(v_cash, v_amount); v_stress := bl_cfg('drive.police.stress') / 2;
      v_msg := 'You settle the officer with ' || bl_naira(v_loss) || '. He lifts the rope.'; v_tone := 'warn';
    elsif p_choice = 'argue' then
      if bl_rand() * 100 < bl_cfg('drive.police.argue_pct') then
        v_msg := 'You stand your ground and the officer gives up. "Go. Go."'; v_tone := 'good';
      else
        v_loss := least(v_cash, floor(bl_cfg('drive.police.fine') * bl_cfg('drive.police.argue_fine_mult'))::bigint);
        v_delay := bl_cfg('drive.police.argue_delay_s')::int; v_stress := bl_cfg('drive.police.stress');
        v_msg := 'The argument goes nowhere. You pay ' || bl_naira(v_loss) || ' and lose time at the roadside.'; v_tone := 'bad';
      end if;
    else
      raise exception 'That choice is not on the card.' using errcode = 'P0001', hint = 'bad_choice';
    end if;
  elsif v_kind = 'goslow' then
    if p_choice = 'wait' then
      v_delay := bl_cfg('drive.goslow.wait_s')::int; v_fun := bl_cfg('drive.goslow.wait_fun');
      v_msg := 'You sit tight and inch forward. It takes a while, but nothing goes wrong.';
    elsif p_choice = 'shortcut' then
      if bl_rand() * 100 < bl_cfg('drive.goslow.shortcut_pct') then
        v_delay := -bl_cfg('drive.goslow.shortcut_save_s')::int;
        v_msg := 'The back street is empty. You skip the jam and save time.'; v_tone := 'good';
      else
        v_delay := bl_cfg('drive.goslow.shortcut_fail_s')::int;
        v_repair := least(v_cash, bl_cfg('drive.goslow.shortcut_fail_cost')::bigint);
        v_stress := bl_cfg('drive.goslow.stress');
        v_msg := 'Potholes and a dead end. You turn back, lose time and pay ' || bl_naira(v_repair) || ' for a tyre.'; v_tone := 'bad';
      end if;
    else
      raise exception 'That choice is not on the card.' using errcode = 'P0001', hint = 'bad_choice';
    end if;
  elsif v_kind = 'beggar' then
    if p_choice = 'give' then
      v_loss := least(v_cash, bl_cfg('drive.beggar.give')::bigint);
      v_fun := bl_cfg('drive.beggar.give_fun'); v_stress := bl_cfg('drive.beggar.give_stress');
      v_msg := 'You give ' || bl_naira(v_loss) || '. She blesses you and your journey.'; v_tone := 'good';
    elsif p_choice = 'water' then
      v_loss := least(v_cash, bl_cfg('drive.beggar.water_cost')::bigint);
      v_hunger := bl_cfg('drive.beggar.water_hunger'); v_fun := bl_cfg('drive.beggar.water_fun');
      v_msg := 'You buy a cold sachet of pure water and drink it as you go.'; v_tone := 'good';
    elsif p_choice = 'ignore' then
      v_stress := bl_cfg('drive.beggar.ignore_stress');
      v_msg := 'You keep your eyes on the road and drive on.';
    else
      raise exception 'That choice is not on the card.' using errcode = 'P0001', hint = 'bad_choice';
    end if;
  else
    raise exception 'There is nothing to decide right now.' using errcode = 'P0001', hint = 'no_event';
  end if;

  if v_loss > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_loss, 'drive_' || v_kind, jsonb_build_object('kind', v_kind, 'choice', p_choice));
  end if;
  if v_repair > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_repair, 'drive_repair', jsonb_build_object('kind', v_kind, 'choice', p_choice));
  end if;
  if v_hp <> 0 or v_stress <> 0 or v_fun <> 0 or v_hunger <> 0 then
    perform bl_adjust_needs(v_me.id, jsonb_build_object('health', v_hp, 'stress', v_stress, 'fun', v_fun, 'hunger', v_hunger));
  end if;

  -- time: delays are capped for the whole trip, savings never take the arrival below 3 seconds from now
  v_arr := v_me.travel_arrives_at;
  if v_delay > 0 then
    v_room := greatest(0, bl_cfg('drive.max_delay_s')::int - s.trip_delay_s);
    v_delay := least(v_delay, v_room);
    v_arr := greatest(v_arr, v_now) + make_interval(secs => v_delay);   -- a card answered after the clock ran out still costs the full delay
    update drive_state set trip_delay_s = trip_delay_s + v_delay where user_id = v_me.id;
  elsif v_delay < 0 then
    v_arr := greatest(v_now + interval '3 seconds', v_arr + make_interval(secs => v_delay));
    v_delay := -round(extract(epoch from v_me.travel_arrives_at - v_arr))::int;
  end if;
  if v_arr is distinct from v_me.travel_arrives_at then
    update profiles set travel_arrives_at = v_arr where id = v_me.id;
  end if;
  update drive_state set pending = null, pending_at = null where user_id = v_me.id;

  return jsonb_build_object('message', v_msg, 'tone', v_tone, 'kind', v_kind, 'choice', p_choice,
                            'cash_delta', -(v_loss + v_repair), 'delay_s', v_delay, 'arrives_at', v_arr);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. drive_turn_back(): cancel the trip in progress (no refund)
-- ---------------------------------------------------------------------------------------------
create or replace function public.drive_turn_back() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  v_now  timestamptz := bl_now();
  v_name text;
begin
  if not bl_cfg_bool('drive.turn_back_on') then
    raise exception 'You cannot turn back right now.' using errcode = 'P0001', hint = 'off';
  end if;
  if v_me.travel_to is null then
    raise exception 'You are not travelling right now.' using errcode = 'P0001';
  end if;
  if v_now >= v_me.travel_arrives_at then
    raise exception 'You have already arrived.' using errcode = 'P0001', hint = 'arrived';
  end if;
  update profiles set travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null, last_seen = v_now
   where id = v_me.id;
  update drive_state set pending = null, pending_at = null where user_id = v_me.id;
  select name into v_name from locations where id = v_me.location_id;
  return jsonb_build_object('message', 'You turned back to ' || coalesce(v_name, 'where you started') || '. The fare is gone.',
                            'location', v_me.location_id);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------------------------
revoke execute on function public.bl_drive_card(text, bigint) from public, anon, authenticated;
revoke execute on function public.drive_event_roll() from public, anon;
revoke execute on function public.drive_event_choose(text) from public, anon;
revoke execute on function public.drive_turn_back() from public, anon;
grant execute on function public.drive_event_roll() to authenticated;
grant execute on function public.drive_event_choose(text) to authenticated;
grant execute on function public.drive_turn_back() to authenticated;

notify pgrst, 'reload schema';
