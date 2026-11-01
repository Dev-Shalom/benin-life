-- New-player journey: a short quest line for the first 3 days (docs/JOURNEY.md).
-- * journey_steps     admin-editable ordered steps, grouped by day (title, hint, reward, deep link, the condition kind).
-- * journey_progress  one row per player (keyed by user id, NO foreign key to profiles): anchor time, day reached, small marks.
-- * journey_done      one row per player per step: done_at, claimed_at (the claim is exactly-once).
-- * journey_step_stats  cached funnel counters (bumped once per player per step, so the admin page is a 20-row read).
-- journey_status() evaluates lazily and cheaply (only unlocked, not-yet-done steps, each one an indexed probe); journey_claim(step) pays
-- once (ledger reason 'New player reward': not an earn reason, so no tax garnish, no leaderboard, no challenge progress).
-- Days unlock on the player's own distinct WAT play days (player_days from the growth pack). Only young accounts get it (admin setting).
-- Idempotent. Nothing touches the profiles table (no column, trigger, index or foreign key). No loops over players, no backfill:
-- the migration is a few small tables, seeds and functions.

create or replace function pg_temp.jn_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'journey: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Tables (RLS on, no policies: players never read or write them directly)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.journey_steps (
  id text primary key,
  day smallint not null check (day between 1 and 3),
  sort integer not null default 100,
  kind text not null check (kind in ('tour', 'ate_rest', 'shift', 'buy_home', 'story', 'claim_reward', 'earn', 'friend', 'gist', 'visit',
                                     'day_reached', 'skill', 'bank', 'dream')),
  title text not null,
  hint text not null default '',
  icon text not null default '⭐',
  go text,
  target integer not null default 1 check (target >= 1),
  reward_cash bigint not null default 0 check (reward_cash >= 0),
  reward_item text,
  reward_item_qty integer not null default 1 check (reward_item_qty >= 1),
  active boolean not null default true
);

create table if not exists public.journey_progress (
  user_id uuid primary key,
  anchor timestamptz not null,
  day_n smallint not null default 1,
  last_day date,
  pushed_day smallint not null default 1,
  evaluated_at timestamptz,
  marks jsonb not null default '{}'::jsonb,
  completed_at timestamptz,
  badge text,
  created_at timestamptz not null default now()
);
create index if not exists journey_progress_push_idx on public.journey_progress (last_day) where completed_at is null and day_n < 3;

create table if not exists public.journey_done (
  user_id uuid not null,
  step_id text not null,
  done_at timestamptz not null default now(),
  claimed_at timestamptz,
  cash bigint not null default 0,
  primary key (user_id, step_id)
);

create table if not exists public.journey_step_stats (
  step_id text primary key,
  reached integer not null default 0,
  claimed integer not null default 0
);

create table if not exists public.journey_job (
  id smallint primary key default 1 check (id = 1),
  last_run timestamptz not null default '-infinity'
);
insert into public.journey_job (id) values (1) on conflict (id) do nothing;

do $$
declare t text;
begin
  foreach t in array array['journey_steps', 'journey_progress', 'journey_done', 'journey_step_stats', 'journey_job'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. Settings (Admin -> Settings -> New-player journey)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('journey.enabled', 'true', 'journey', 'New-player journey on',
 'The "Your first days" quest line for new players: about 14 small steps over their first 3 play days, each with a small reward. Off = the card disappears and nothing new is evaluated.', 'bool', null, null),
('journey.max_age_days', '7', 'journey', 'Offered to accounts younger than (days)',
 'Only accounts created in the last this-many days are offered the journey, so the players who joined long ago are not flooded. A player who already started keeps going.', 'number', 1, 60),
('journey.offer_existing', 'false', 'journey', 'Also offer to older low-level players',
 'On = an older account is also offered the journey (starting fresh from its first view) while it has done fewer career shifts than the number below.', 'bool', null, null),
('journey.low_level_shifts', '10', 'journey', 'Older players count as low-level below (shifts)',
 'Used only when "Also offer to older low-level players" is on: an older account with fewer career shifts than this is offered the journey.', 'number', 0, 200),
('journey.reward_pct', '100', 'journey', 'Step rewards (percent)',
 '100 = the cash written on each step (Content -> Journey steps). 50 halves every step reward, 200 doubles them. The items are not scaled.', 'percent', 0, 500),
('journey.bonus_cash', '3000', 'journey', 'Finish bonus: money',
 'Paid once, automatically, when the player has claimed every step.', 'naira', 0, 1000000),
('journey.bonus_item', '"kada_chicken"', 'journey', 'Finish bonus: item id', 'An item id from Content -> Items, or empty for none.', 'text', null, null),
('journey.bonus_item_qty', '1', 'journey', 'Finish bonus: item quantity', 'How many of the bonus item.', 'number', 1, 50),
('journey.badge_title', '"Benin Newcomer"', 'journey', 'Finish badge (title)', 'The title shown on the finished journey.', 'text', null, null),
('journey.eval_seconds', '8', 'journey', 'Re-check no more often than (seconds)',
 'journey_status() re-evaluates a player at most this often (it is called when the game opens, on focus and after money moves). 0 = every call.', 'number', 0, 600),
('journey.push_enabled', 'true', 'journey', 'Day 2 / Day 3 push on',
 'One opt-in push the next morning when the next day of the journey is ready ("Day 2 of your Benin life is ready"). Uses the Game events category (off by default for players). At most 2 per player ever.', 'bool', null, null),
('journey.push_hour', '10', 'journey', 'Push: not before this hour (Benin time)', 'The push goes out from this hour until the quiet-hours end (Settings -> Welcome back).', 'number', 0, 23),
('journey.push_batch', '200', 'journey', 'Push: players per minute', 'The most players looked at in one cron minute.', 'number', 10, 2000),
('journey.tick_seconds', '300', 'journey', 'Push job: run every (seconds)', 'The cron calls it each minute; it works at most this often.', 'number', 0, 3600)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. The steps (English with a little Pidgin; all numbers are admin settings in Content -> Journey steps)
-- ---------------------------------------------------------------------------------------------
insert into public.journey_steps (id, day, sort, kind, title, hint, icon, go, target, reward_cash, reward_item, reward_item_qty) values
('j_tour',    1, 10, 'tour',         'Take the quick tour',               'Two minutes. It shows you where everything is.',                                      '🧭', 'tour',   1, 500,  null, 1),
('j_eat',     1, 20, 'ate_rest',     'Eat something or rest at home',     'Your needs drop as time goes. Eat from your Bag, or sleep on your bed.',                '🍲', 'home',   1, 500,  null, 1),
('j_shift',   1, 30, 'shift',        'Get a job and finish one shift',    'Go to a workplace on the map, apply, then work a shift. A hustle counts too.',          '💼', 'map',    1, 1500, 'meat_pie', 1),
('j_buy',     1, 40, 'buy_home',     'Buy something for your home',       'Food from the shop or a piece of furniture. Make the place yours.',                     '🛒', 'food',   1, 1000, null, 1),
('j_story',   1, 50, 'story',        'Read today''s story',               'A small story happens in Benin City every day. Pick what you will do.',                 '📖', 'stories', 1, 500, null, 1),
('j_reward2', 2, 10, 'claim_reward', 'Claim your daily reward',           'Open the Today list and tap the reward. Come back every day for more.',                 '🎁', 'daily',  1, 1000, 'energy_drink', 1),
('j_earn',    2, 20, 'earn',         'Earn ₦15,000 in total',             'Work shifts and hustles. Your pay adds up, so keep going.',                             '💰', 'map',    15000, 1500, null, 1),
('j_friend',  2, 30, 'friend',       'Add a friend or send a message',    'Meet people at a place, send a friend request or say hello in a message.',              '🤝', 'gist:friends', 1, 1000, null, 1),
('j_gist',    2, 40, 'gist',         'Join a Benin Gist group or post',   'Benin Gist is the city''s chat. Join a group or post your first gist.',                 '💬', 'gist:groups', 1, 1000, null, 1),
('j_visit',   2, 50, 'visit',        'Visit 3 places on the map',         'Walk or ride to three different places, like Oba Market, UNIBEN or Ring Road.',         '🗺️', 'map',    3, 1000, null, 1),
('j_day3',    3, 10, 'day_reached',  'Come back for day 3',               'You showed up three days. That is how a Benin life grows. Collect this one.',           '🌅', null,     1, 1000, null, 1),
('j_skill',   3, 20, 'skill',        'Learn a skill or start a course',   'Enrol in a course at school, or practise a skill. It pays off in better jobs.',         '🎓', 'school', 1, 1500, null, 1),
('j_bank',    3, 30, 'bank',         'Save money in the bank',            'Go to the bank and deposit some cash. Street thieves cannot touch it there.',           '🏦', 'bank',   1, 1000, null, 1),
('j_dream',   3, 40, 'dream',        'Check your dream',                  'Open your Sim, then Goals. Your lifetime dream is what all this is for.',               '🌟', 'dream',  1, 500,  null, 1)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Small helpers (called from other functions: never raise)
-- ---------------------------------------------------------------------------------------------
-- A one-word mark on a player's journey ('ate', 'home', 'dream_seen'). One primary-key probe, no write unless it is new.
create or replace function public.bl_journey_note(p_uid uuid, p_key text) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  update journey_progress set marks = marks || jsonb_build_object(p_key, true)
   where user_id = p_uid and not (marks ? p_key);
exception when others then
  null;
end $$;
revoke all on function public.bl_journey_note(uuid, text) from public, anon, authenticated;

-- A public place the player arrived at (homes never count). Called from the profiles location trigger function that already exists.
create or replace function public.bl_journey_visit(p_uid uuid, p_loc text) returns void
language plpgsql volatile security definer set search_path = public as $$
declare v_marks jsonb;
begin
  select marks into v_marks from journey_progress where user_id = p_uid and completed_at is null;
  if not found then return; end if;
  if coalesce(v_marks->'visited', '[]'::jsonb) ? p_loc or jsonb_array_length(coalesce(v_marks->'visited', '[]'::jsonb)) >= 12 then return; end if;
  if not exists (select 1 from locations l where l.id = p_loc and l.private_home_owner_id is null and l.scene not like 'home%' and coalesce(l.active, true)) then return; end if;
  update journey_progress set marks = jsonb_set(marks, '{visited}', coalesce(marks->'visited', '[]'::jsonb) || to_jsonb(p_loc))
   where user_id = p_uid;
exception when others then
  null;
end $$;
revoke all on function public.bl_journey_visit(uuid, text) from public, anon, authenticated;

create or replace function public.bl_journey_stat(p_step text, p_col text) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if p_col = 'reached' then
    insert into journey_step_stats (step_id, reached) values (p_step, 1) on conflict (step_id) do update set reached = journey_step_stats.reached + 1;
  else
    insert into journey_step_stats (step_id, claimed) values (p_step, 1) on conflict (step_id) do update set claimed = journey_step_stats.claimed + 1;
  end if;
end $$;
revoke all on function public.bl_journey_stat(text, text) from public, anon, authenticated;

-- Naira earned (the weekly top-earners rule: salary, hustle...) since the journey began. One range scan of the player's own ledger.
create or replace function public.bl_journey_earned(p_uid uuid, p_since timestamptz) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(sum(delta), 0)::bigint from ledger
   where user_id = p_uid and created_at >= p_since and delta > 0 and reason = any (bl_earn_reasons());
$$;
revoke all on function public.bl_journey_earned(uuid, timestamptz) from public, anon, authenticated;

-- The calendar date of the player's n-th distinct play day since the journey began (today when it is not recorded yet).
create or replace function public.bl_journey_nth_day(p_uid uuid, p_anchor timestamptz, p_n int) returns date
language sql stable security definer set search_path = public as $$
  select coalesce((select day from player_days where user_id = p_uid and day >= bl_wat_date(p_anchor) order by day offset greatest(p_n, 1) - 1 limit 1), bl_wat_date());
$$;
revoke all on function public.bl_journey_nth_day(uuid, timestamptz, int) from public, anon, authenticated;

-- Start (or find) a player's journey. Null = not offered (off, banned, no home yet, or the account is too old).
create or replace function public.bl_journey_start(p_uid uuid) returns public.journey_progress
language plpgsql volatile security definer set search_path = public as $$
declare p journey_progress; me profiles; v_now timestamptz := bl_now(); v_young boolean; v_low boolean; v_n int;
begin
  if not coalesce(bl_cfg_bool('journey.enabled'), false) then return null; end if;
  select * into p from journey_progress where user_id = p_uid;
  if found then return p; end if;
  select * into me from profiles where id = p_uid;
  if not found or me.banned or not me.home_chosen then return null; end if;
  v_young := me.created_at >= v_now - make_interval(days => greatest(1, bl_cfg('journey.max_age_days'))::int);
  v_low := coalesce(bl_cfg_bool('journey.offer_existing'), false) and me.job_total_shifts < greatest(0, bl_cfg('journey.low_level_shifts'))::int;
  if not (v_young or v_low) then return null; end if;
  insert into journey_progress (user_id, anchor) values (p_uid, case when v_young then me.created_at else v_now end)
  on conflict (user_id) do nothing;
  get diagnostics v_n = row_count;
  if v_n > 0 then perform bl_journey_stat('_started', 'reached'); end if;
  select * into p from journey_progress where user_id = p_uid;
  return p;
end $$;
revoke all on function public.bl_journey_start(uuid) from public, anon, authenticated;

-- Is one step's condition true right now? Every branch is one indexed probe.
create or replace function public.bl_journey_check(p_uid uuid, s public.journey_steps, p public.journey_progress, me public.profiles, p_days int) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v_nth date; v_claim date;
begin
  case s.kind
    when 'tour' then return me.tour_done_at is not null;
    when 'ate_rest' then return coalesce(p.marks ? 'ate', false) or coalesce(p.marks ? 'home', false);
    when 'shift' then
      return me.job_total_shifts >= s.target
          or exists (select 1 from hustle_runs h where h.user_id = p_uid and h.status = 'done' and h.started_at >= p.anchor);
    when 'buy_home' then
      return exists (select 1 from ledger l where l.user_id = p_uid and l.created_at >= p.anchor and l.delta < 0
                      and l.reason in ('furniture', 'shop', 'food_delivery'));
    when 'story' then
      return exists (select 1 from player_stories st where st.user_id = p_uid and st.kind = 'daily' and st.status = 'answered' and st.created_at >= p.anchor);
    when 'claim_reward' then
      select last_claim_date into v_claim from daily_reward_state where user_id = p_uid;
      v_nth := bl_journey_nth_day(p_uid, p.anchor, s.day);
      return v_claim is not null and v_claim >= v_nth;
    when 'earn' then return bl_journey_earned(p_uid, p.anchor) >= s.target;
    when 'friend' then
      return exists (select 1 from player_friendships f where f.user_a = p_uid and (f.status = 'accepted' or f.requested_by = p_uid))
          or exists (select 1 from player_friendships f where f.user_b = p_uid and (f.status = 'accepted' or f.requested_by = p_uid))
          or exists (select 1 from player_messages m where m.sender_id = p_uid and m.created_at >= p.anchor);
    when 'gist' then
      return exists (select 1 from gist_posts g where g.user_id = p_uid and g.created_at >= p.anchor)
          or exists (select 1 from gist_group_members gm where gm.user_id = p_uid and gm.joined_at >= p.anchor);
    when 'visit' then return jsonb_array_length(coalesce(p.marks->'visited', '[]'::jsonb)) >= s.target;
    when 'day_reached' then return p_days >= s.day;
    when 'skill' then
      return exists (select 1 from course_enrolments c where c.user_id = p_uid and c.enrolled_at >= p.anchor)
          or exists (select 1 from player_skills k where k.user_id = p_uid and k.xp > 0 and k.updated_at >= p.anchor);
    when 'bank' then
      return exists (select 1 from ledger l where l.user_id = p_uid and l.created_at >= p.anchor and l.reason = 'bank_deposit' and l.account = 'bank' and l.delta > 0);
    when 'dream' then return coalesce(p.marks ? 'dream_seen', false);
    else return false;
  end case;
end $$;
revoke all on function public.bl_journey_check(uuid, public.journey_steps, public.journey_progress, public.profiles, int) from public, anon, authenticated;

-- Work out the day reached and which unlocked steps are now done. Cheap: done steps are never looked at again, locked ones neither,
-- and a player is re-checked at most every journey.eval_seconds. The first look is quiet (no alert for what was already true).
create or replace function public.bl_journey_eval(p_uid uuid, p_force boolean default false) returns public.journey_progress
language plpgsql volatile security definer set search_path = public as $$
declare
  p journey_progress; me profiles; s journey_steps; v_now timestamptz := bl_now(); v_today date := bl_wat_date(v_now);
  v_days int; v_quiet boolean; v_new int := 0; v_cash bigint; v_pct numeric := greatest(0, coalesce(bl_cfg('journey.reward_pct'), 100));
  v_tip int;
begin
  p := bl_journey_start(p_uid);
  if p.user_id is null then return null; end if;
  select * into p from journey_progress where user_id = p_uid for update;
  if not p_force and p.evaluated_at is not null
     and p.evaluated_at > v_now - make_interval(secs => greatest(0, coalesce(bl_cfg('journey.eval_seconds'), 8))::double precision)
     and p.last_day = v_today then
    return p;
  end if;
  select * into me from profiles where id = p_uid;
  v_quiet := p.evaluated_at is null;

  select count(*) into v_days from player_days where user_id = p_uid and day >= bl_wat_date(p.anchor);
  if not exists (select 1 from player_days where user_id = p_uid and day = v_today) then v_days := v_days + 1; end if;
  v_days := least(3, greatest(1, v_days));

  if v_days > p.day_n and not v_quiet then
    select count(*) into v_tip from journey_steps where active and day > p.day_n and day <= v_days;
    perform bl_event(p_uid, 'journey_day', '🌱 Day ' || v_days || ' of your Benin life is ready',
                     v_tip || ' new step' || case when v_tip = 1 then '' else 's' end || ' in Your first days. Come see.',
                     jsonb_build_object('day', v_days));
  end if;

  for s in
    select st.* from journey_steps st
     where st.active and st.day <= v_days
       and not exists (select 1 from journey_done d where d.user_id = p_uid and d.step_id = st.id)
     order by st.day, st.sort, st.id
  loop
    if bl_journey_check(p_uid, s, p, me, v_days) then
      v_cash := round(s.reward_cash * v_pct / 100.0)::bigint;
      insert into journey_done (user_id, step_id, cash) values (p_uid, s.id, v_cash) on conflict do nothing;
      if found then
        perform bl_journey_stat(s.id, 'reached');
        v_new := v_new + 1;
        if not v_quiet then
          perform bl_event(p_uid, 'journey_step', '✅ Step done: ' || s.title,
                           case when v_cash > 0 then 'Claim ' || bl_naira(v_cash) || ' in Your first days.' else 'Claim your reward in Your first days.' end,
                           jsonb_build_object('step', s.id, 'cash', v_cash));
        end if;
      end if;
    end if;
  end loop;

  update journey_progress set day_n = greatest(day_n, v_days), last_day = v_today, evaluated_at = v_now
   where user_id = p_uid returning * into p;
  return p;
end $$;
revoke all on function public.bl_journey_eval(uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 5. Player RPCs (signed-in players only)
-- ---------------------------------------------------------------------------------------------
create or replace function public.journey_status() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); p journey_progress; v_pct numeric := greatest(0, coalesce(bl_cfg('journey.reward_pct'), 100));
  v_steps jsonb; v_total int; v_done int; v_claimed int; v_earned bigint; v_bonus jsonb;
begin
  if not coalesce(bl_cfg_bool('journey.enabled'), false) then return jsonb_build_object('enabled', false); end if;
  p := bl_journey_eval(v_uid);
  if p.user_id is null then return jsonb_build_object('enabled', true, 'eligible', false); end if;

  v_earned := case when exists (select 1 from journey_steps where active and kind = 'earn' and day <= p.day_n
                                  and not exists (select 1 from journey_done d where d.user_id = v_uid and d.step_id = journey_steps.id))
                   then bl_journey_earned(v_uid, p.anchor) else 0 end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'day', s.day, 'title', s.title, 'hint', s.hint, 'icon', s.icon, 'go', s.go,
           'state', case when d.claimed_at is not null then 'claimed' when d.user_id is not null then 'done'
                         when s.day <= p.day_n then 'active' else 'locked' end,
           'reward', jsonb_build_object('cash', coalesce(d.cash, round(s.reward_cash * v_pct / 100.0)::bigint),
                                        'item', s.reward_item, 'item_name', it.name, 'qty', s.reward_item_qty),
           'progress', case when d.user_id is not null then null
                            when s.kind = 'earn' and s.day <= p.day_n then jsonb_build_object('have', least(v_earned, s.target), 'need', s.target, 'money', true)
                            when s.kind = 'visit' then jsonb_build_object('have', least(jsonb_array_length(coalesce(p.marks->'visited', '[]'::jsonb)), s.target), 'need', s.target, 'money', false)
                            else null end
         ) order by s.day, s.sort, s.id), '[]'::jsonb),
         count(*), count(d.user_id), count(d.claimed_at)
    into v_steps, v_total, v_done, v_claimed
    from journey_steps s
    left join journey_done d on d.user_id = v_uid and d.step_id = s.id
    left join items it on it.id = s.reward_item
   where s.active;

  v_bonus := jsonb_build_object('cash', greatest(0, coalesce(bl_cfg('journey.bonus_cash'), 0))::bigint,
                                'item_name', (select name from items where id = nullif(bl_cfg_text('journey.bonus_item'), '')),
                                'badge', bl_cfg_text('journey.badge_title'));
  return jsonb_build_object('enabled', true, 'eligible', true, 'day', p.day_n, 'days', 3, 'total', v_total, 'done', v_done, 'claimed', v_claimed,
                            'claimable', v_done - v_claimed, 'pct', case when v_total = 0 then 100 else round(100.0 * v_claimed / v_total) end,
                            'complete', p.completed_at is not null, 'badge', p.badge, 'bonus', v_bonus, 'steps', v_steps);
end $$;

create or replace function public.journey_claim(p_step text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); p journey_progress; s journey_steps; d journey_done; v_item items; v_cash bigint;
  v_msg text; v_finished boolean := false; v_bonus bigint := 0; v_bitem text; v_bname text; v_open int;
begin
  if not coalesce(bl_cfg_bool('journey.enabled'), false) then
    raise exception 'The first-days quest line is switched off right now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  p := bl_journey_eval(v_uid, true);
  if p.user_id is null then
    raise exception 'This quest line is not for your account.' using errcode = 'P0001', hint = 'not_eligible';
  end if;
  select * into s from journey_steps where id = p_step;
  if not found then raise exception 'That step does not exist.' using errcode = 'P0001', hint = 'no_step'; end if;
  select * into d from journey_done where user_id = v_uid and step_id = p_step for update;
  if not found then raise exception 'Finish this step first, then claim.' using errcode = 'P0001', hint = 'not_done'; end if;
  if d.claimed_at is not null then raise exception 'You already claimed this one.' using errcode = 'P0001', hint = 'already_claimed'; end if;
  update journey_done set claimed_at = bl_now() where user_id = v_uid and step_id = p_step and claimed_at is null;
  v_cash := d.cash;
  if v_cash > 0 then
    perform bl_add_money(v_uid, 'cash', v_cash, 'New player reward', jsonb_build_object('journey_step', p_step));
  end if;
  if s.reward_item is not null then
    select * into v_item from items where id = s.reward_item;
    if found then perform bl_give_item(v_uid, v_item.id, s.reward_item_qty); end if;
  end if;
  perform bl_journey_stat(p_step, 'claimed');
  v_msg := 'Step reward: ' || bl_naira(v_cash) || case when v_item.id is not null then ' + ' || v_item.name else '' end;

  -- finished? every active step claimed -> the finish bonus, once
  select count(*) into v_open from journey_steps st
   where st.active and not exists (select 1 from journey_done x where x.user_id = v_uid and x.step_id = st.id and x.claimed_at is not null);
  if v_open = 0 then
    update journey_progress set completed_at = bl_now(), badge = bl_cfg_text('journey.badge_title')
     where user_id = v_uid and completed_at is null;
    if found then
      v_finished := true;
      v_bonus := greatest(0, coalesce(bl_cfg('journey.bonus_cash'), 0))::bigint;
      if v_bonus > 0 then perform bl_add_money(v_uid, 'cash', v_bonus, 'New player reward', jsonb_build_object('journey_step', '_finish')); end if;
      v_bitem := nullif(bl_cfg_text('journey.bonus_item'), '');
      if v_bitem is not null then
        select name into v_bname from items where id = v_bitem;
        if found then perform bl_give_item(v_uid, v_bitem, greatest(1, bl_cfg('journey.bonus_item_qty'))::int); end if;
      end if;
      perform bl_journey_stat('_finished', 'reached');
      v_msg := v_msg || '. Quest line finished! Bonus ' || bl_naira(v_bonus) || case when v_bname is not null then ' + ' || v_bname else '' end || ' and the ' || bl_cfg_text('journey.badge_title') || ' badge.';
    end if;
  end if;
  return jsonb_build_object('message', v_msg, 'step', p_step, 'cash', v_cash, 'item_name', v_item.name, 'finished', v_finished,
                            'bonus', v_bonus, 'bonus_item_name', v_bname, 'badge', case when v_finished then bl_cfg_text('journey.badge_title') end);
end $$;

-- The one thing only the phone can tell us: the player looked at their dream.
create or replace function public.journey_mark(p_key text) returns void
language plpgsql volatile security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  if p_key = 'dream_seen' then perform bl_journey_note(v_uid, p_key); end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. The day 2 / day 3 push (opt-in Game events category, at most one per day unlocked, 2 ever)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_journey_tick() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_now timestamptz := bl_now(); v_today date := bl_wat_date(v_now); v_hour numeric := extract(hour from (v_now at time zone bl_clock_tz()));
  v_batch int := greatest(10, coalesce(bl_cfg('journey.push_batch'), 200))::int; v_last timestamptz; r record; v_n int := 0; v_seen int := 0;
  v_next int; v_cash bigint; v_steps int;
begin
  if not coalesce(bl_cfg_bool('journey.enabled'), false) or not coalesce(bl_cfg_bool('journey.push_enabled'), false)
     or not coalesce(bl_cfg_bool('push.enabled'), false) or not coalesce(bl_cfg_bool('push.cat_events'), false) then
    return jsonb_build_object('skipped', 'off');
  end if;
  if v_hour < bl_cfg('journey.push_hour') or v_hour >= bl_cfg('return.push_to_hour') then return jsonb_build_object('skipped', 'hours'); end if;
  select last_run into v_last from journey_job where id = 1 for update;
  if v_last > v_now - make_interval(secs => greatest(0, bl_cfg('journey.tick_seconds'))::double precision) then return jsonb_build_object('skipped', 'throttled'); end if;
  update journey_job set last_run = v_now where id = 1;

  for r in
    select jp.user_id, jp.day_n from journey_progress jp
     where jp.completed_at is null and jp.day_n < 3 and jp.pushed_day = jp.day_n
       and jp.last_day < v_today and jp.last_day >= v_today - 2
     order by jp.last_day
     limit v_batch
     for update skip locked
  loop
    v_seen := v_seen + 1;
    v_next := r.day_n + 1;
    update journey_progress set pushed_day = v_next where user_id = r.user_id;   -- examined once, device or not
    if exists (select 1 from push_prefs pp where pp.user_id = r.user_id and pp.master and pp.events)
       and exists (select 1 from push_subscriptions ps where ps.user_id = r.user_id) then
      select count(*), coalesce(sum(reward_cash), 0) into v_steps, v_cash from journey_steps where active and day = v_next;
      if v_steps > 0 and bl_push_enqueue(r.user_id, 'events', 'journey_day', '🌱 Day ' || v_next || ' of your Benin life is ready',
                           v_steps || ' small steps, up to ' || bl_naira(v_cash) || ' to collect. Come see.', '/play?go=journey',
                           null, null, null, 'journey:day' || v_next) is not null then
        v_n := v_n + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('pushed', v_n, 'looked_at', v_seen);
exception when others then
  return jsonb_build_object('error', sqlerrm);
end $$;
revoke all on function public.bl_journey_tick() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 7. Admin: the funnel (cached counters, a 20-row read)
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_journey_funnel() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_started int; v_finished int; v_steps jsonb;
begin
  perform bl_admin_guard();
  select coalesce(reached, 0) into v_started from journey_step_stats where step_id = '_started';
  select coalesce(reached, 0) into v_finished from journey_step_stats where step_id = '_finished';
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'day', s.day, 'title', s.title, 'icon', s.icon, 'active', s.active,
                                               'reached', coalesce(t.reached, 0), 'claimed', coalesce(t.claimed, 0)) order by s.day, s.sort, s.id), '[]'::jsonb)
    into v_steps from journey_steps s left join journey_step_stats t on t.step_id = s.id;
  return jsonb_build_object('enabled', coalesce(bl_cfg_bool('journey.enabled'), false), 'started', coalesce(v_started, 0), 'finished', coalesce(v_finished, 0), 'steps', v_steps);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Hooks into functions that already exist (guarded single replaces)
-- ---------------------------------------------------------------------------------------------
-- eating: marks the "eat something" step
select pg_temp.jn_patch('public.item_use(text)',
  'v_left := bl_give_item(v_me.id, it.id, -1);',
  E'v_left := bl_give_item(v_me.id, it.id, -1);\n  if it.category in (''food'', ''drink'') then perform bl_journey_note(v_me.id, ''ate''); end if;',
  'bl_journey_note(');
-- resting / washing / any activity at home: marks the same step
select pg_temp.jn_patch('public.do_activity(text)',
  'perform bl_skill_award(v_me.id, ''activity'', a.id);',
  E'perform bl_skill_award(v_me.id, ''activity'', a.id);\n  if a.home_only then perform bl_journey_note(v_me.id, ''home''); end if;',
  'bl_journey_note(');
-- arriving at a public place: the "visit 3 places" step (the challenge counter's trigger function already runs on every move)
select pg_temp.jn_patch('public.bl_chal_on_profile()',
  E'  return null;\nexception when others then',
  E'  if new.location_id is distinct from old.location_id and new.travel_to is null then\n    perform bl_journey_visit(new.id, new.location_id);\n  end if;\n  return null;\nexception when others then',
  'bl_journey_visit(');
-- the cron
select pg_temp.jn_patch('public.bl_push_tick()',
  'jsonb_build_object(''weekly'', bl_weekly_tick());',
  E'jsonb_build_object(''weekly'', bl_weekly_tick())\n         || jsonb_build_object(''journey'', bl_journey_tick());',
  'bl_journey_tick(');
-- Admin -> Content editor for the steps
select pg_temp.jn_patch('public.bl_admin_table_spec(text)',
  'when ''challenge_templates'' then',
  E'when ''journey_steps'' then ''{"pk":["id"],"insert":false,"order":"day, sort, id",\n      "cols":{"day":"int","sort":"int","title":"text","hint":"text","icon":"text","go":"text_null","target":"int","reward_cash":"money","reward_item":"text_null","reward_item_qty":"int","active":"bool"}}\'\n    when ''challenge_templates'' then',
  'journey_steps');

-- ---------------------------------------------------------------------------------------------
-- 9. Grants
-- ---------------------------------------------------------------------------------------------
revoke all on function public.journey_status() from public, anon;
grant execute on function public.journey_status() to authenticated;
revoke all on function public.journey_claim(text) from public, anon;
grant execute on function public.journey_claim(text) to authenticated;
revoke all on function public.journey_mark(text) from public, anon;
grant execute on function public.journey_mark(text) to authenticated;
revoke all on function public.admin_journey_funnel() from public, anon;
grant execute on function public.admin_journey_funnel() to authenticated;

notify pgrst, 'reload schema';
