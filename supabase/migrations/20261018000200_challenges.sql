-- R5: daily and weekly challenges. docs/CHALLENGES.md
-- Idempotent and safe on a non-empty DB: tables `if not exists`, seeds `on conflict do nothing`, functions `create or replace`, triggers dropped and
-- re-created, live functions patched only through a guarded replace on pg_get_functiondef (raises when the marker is missing).
-- Everything is server-authoritative. Progress is counted by AFTER triggers on the real tables (ledger, hustle_runs, course_runs, yahoo_runs,
-- player_skills, profiles, player_messages, daily_reward_state, player_house_invites) that all call ONE helper, bl_challenge_bump(uid, goal, amount, ref).
-- Money moves only through bl_add_money (ledger reason 'challenge'). That reason is never an earning for the weekly top earners.

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Challenges)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('challenges.enabled', 'true', 'challenges', 'Challenges on',
 'R5: daily and weekly challenges. Off = no new challenges are handed out and claims are refused (progress already made stays).', 'bool', null, null),
('challenges.daily_count', '3', 'challenges', 'Challenges per day',
 'How many daily challenges each player gets (they reset at midnight Benin time). Players who already have today''s set keep it until tomorrow.', 'number', 1, 6),
('challenges.weekly_count', '3', 'challenges', 'Challenges per week',
 'How many weekly challenges each player gets (they reset Monday 00:00 Benin time, the same boundary as the weekly top earners).', 'number', 1, 6),
('challenges.rerolls_per_day', '1', 'challenges', 'Free rerolls per day',
 'How many times a player may swap an unfinished daily challenge for another one each Benin day (progress on the swapped one is lost).', 'number', 0, 6),
('challenges.rerolls_per_week', '0', 'challenges', 'Free rerolls per week',
 'Same for weekly challenges (default 0 = no weekly rerolls).', 'number', 0, 6),
('challenges.reward_mult', '1', 'challenges', 'Cash reward multiplier',
 'Every challenge and chest cash reward is multiplied by this when it is claimed (2 = double cash weekend, 0 = no cash).', 'number', 0, 10),
('challenges.daily_chest_cash', '3000', 'challenges', 'Daily chest: cash',
 'Bonus chest for finishing every daily challenge of the day. Paid once a day.', 'naira', 0, 10000000),
('challenges.daily_chest_xp', '20', 'challenges', 'Daily chest: career XP',
 'Career XP in the daily chest (only counts while the player has a job).', 'number', 0, 100000),
('challenges.daily_chest_item', '"energy_drink"', 'challenges', 'Daily chest: item id',
 'Item id given with the daily chest (empty = none). Must be an item id from Content -> Items.', 'text', null, null),
('challenges.weekly_chest_cash', '20000', 'challenges', 'Weekly chest: cash',
 'Bigger chest for finishing every weekly challenge of the week. Paid once a week.', 'naira', 0, 10000000),
('challenges.weekly_chest_xp', '100', 'challenges', 'Weekly chest: career XP',
 'Career XP in the weekly chest (only counts while the player has a job).', 'number', 0, 100000),
('challenges.weekly_chest_item', '"kada_chicken"', 'challenges', 'Weekly chest: item id',
 'Item id given with the weekly chest (empty = none).', 'text', null, null),
('challenges.push_weekly', 'true', 'challenges', 'Push when the weekly chest is ready',
 'Send one push (events category, skipped while the player is active in the game) when a player finishes every weekly challenge. Needs Settings -> Push on.', 'bool', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
-- A template says what to do (goal + target), what it pays and who may get it. Goals are counted by triggers (section 5).
--   param  : narrows a goal (hustle id for hustle_done / friend_hustle, ledger reason for earn e.g. salary / hustle / invest_income,
--            item id for buy_item, skill id for skill_up). Empty = anything.
--   needs  : the player must have it to be given this challenge: job, laptop, enrolled, friend, or an item id (e.g. fishing_rod).
--   min_skill + min_skill_level, req_cert : the player must meet these to be given it.
create table if not exists public.challenge_templates (
  id              text primary key,
  kind            text not null check (kind in ('daily', 'weekly')),
  goal            text not null check (goal in ('hustle_done', 'earn', 'shift', 'class', 'yahoo_clean', 'visit_place', 'club_spend', 'spray',
                                                'dm_people', 'dm_send', 'fish', 'skill_up', 'buy_item', 'streak',
                                                'friend_hustle', 'friend_house', 'friend_meet')),
  title           text not null,
  blurb           text not null default '',
  icon            text not null default '🎯',
  target          bigint not null default 1 check (target > 0),
  param           text,
  needs           text,
  reward_cash     bigint not null default 0 check (reward_cash >= 0),
  reward_xp       int not null default 0 check (reward_xp >= 0),
  reward_skill    text references public.skills(id) on update cascade on delete set null,
  reward_skill_xp int not null default 0 check (reward_skill_xp >= 0),
  reward_item     text references public.items(id) on update cascade on delete set null,
  reward_item_qty int not null default 1 check (reward_item_qty >= 1),
  weight          numeric not null default 10 check (weight >= 0),
  min_skill       text references public.skills(id) on update cascade on delete set null,
  min_skill_level int not null default 1 check (min_skill_level >= 1),
  req_cert        text references public.certificates(id) on update cascade on delete set null,
  friends         boolean not null default false,
  sort            int not null default 0,
  active          boolean not null default true,
  created_at      timestamptz not null default now()
);

-- One row per player per challenge slot per period. The goal, target and rewards are copied from the template when it is handed out,
-- so an admin edit never changes a challenge that is already running (title, blurb and icon are read live).
create table if not exists public.player_challenges (
  id              bigint generated always as identity primary key,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  kind            text not null check (kind in ('daily', 'weekly')),
  period          date not null,                       -- Benin date (daily) or the Monday (weekly)
  slot            smallint not null check (slot between 1 and 6),
  template_id     text not null references public.challenge_templates(id) on update cascade on delete cascade,
  goal            text not null,
  param           text,
  target          bigint not null check (target > 0),
  progress        bigint not null default 0 check (progress >= 0),
  refs            text[] not null default '{}',        -- the distinct places / players already counted (visit_place, dm_people, friend_*)
  reward_cash     bigint not null default 0,
  reward_xp       int not null default 0,
  reward_skill    text,
  reward_skill_xp int not null default 0,
  reward_item     text,
  reward_item_qty int not null default 1,
  completed_at    timestamptz,
  claimed_at      timestamptz,
  expired         boolean not null default false,      -- set when its period is over and it was never finished (keeps the hot index small)
  created_at      timestamptz not null default now(),
  unique (user_id, kind, period, slot)
);
create index if not exists player_challenges_open_idx on public.player_challenges (user_id, goal) where completed_at is null and not expired;
create index if not exists player_challenges_template_idx on public.player_challenges (template_id);

create table if not exists public.challenge_chests (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('daily', 'weekly')),
  period     date not null,
  cash       bigint not null default 0,
  xp         int not null default 0,
  item       text,
  claimed_at timestamptz not null default now(),
  primary key (user_id, kind, period)
);

create table if not exists public.challenge_rerolls (
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind    text not null check (kind in ('daily', 'weekly')),
  period  date not null,
  used    int not null default 0,
  seen    text[] not null default '{}',                -- templates already swapped out this period (never offered again)
  primary key (user_id, kind, period)
);
alter table public.challenge_rerolls add column if not exists seen text[] not null default '{}';

alter table public.challenge_templates enable row level security;
alter table public.player_challenges   enable row level security;
alter table public.challenge_chests    enable row level security;
alter table public.challenge_rerolls   enable row level security;

drop policy if exists player_challenges_own on public.player_challenges;
create policy player_challenges_own on public.player_challenges for select to authenticated using (user_id = auth.uid());
drop policy if exists challenge_chests_own on public.challenge_chests;
create policy challenge_chests_own on public.challenge_chests for select to authenticated using (user_id = auth.uid());
drop policy if exists challenge_rerolls_own on public.challenge_rerolls;
create policy challenge_rerolls_own on public.challenge_rerolls for select to authenticated using (user_id = auth.uid());

-- Players read their own rows only; the templates are never read directly (challenge_status() carries what the app needs); no client writes.
revoke all on public.challenge_templates, public.player_challenges, public.challenge_chests, public.challenge_rerolls from anon, authenticated;
grant select on public.player_challenges, public.challenge_chests, public.challenge_rerolls to authenticated;

-- ---------------------------------------------------------------------------------------------
-- 3. Helpers (private)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_chal_on() returns boolean
language sql stable set search_path = public as $$ select coalesce(bl_cfg_bool('challenges.enabled'), true); $$;

create or replace function public.bl_chal_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$ select coalesce(bl_cfg(p_key), p_default); $$;

-- the period a challenge of this kind belongs to right now: today's Benin date, or this week's Monday (the weekly top earners' boundary)
create or replace function public.bl_chal_period(p_kind text) returns date
language sql stable set search_path = public as $$
  select case p_kind when 'weekly' then bl_week_start() else bl_wat_date() end;
$$;

create or replace function public.bl_chal_ends(p_kind text, p_period date) returns timestamptz
language sql stable set search_path = public as $$
  select case p_kind when 'weekly' then bl_week_from(p_period + 7) else ((p_period + 1)::timestamp at time zone bl_clock_tz()) end;
$$;

create or replace function public.bl_chal_count(p_kind text) returns int
language sql stable set search_path = public as $$
  select least(6, greatest(1, round(bl_chal_num(case p_kind when 'weekly' then 'challenges.weekly_count' else 'challenges.daily_count' end, 3))::int));
$$;

create or replace function public.bl_chal_rerolls_max(p_kind text) returns int
language sql stable set search_path = public as $$
  select greatest(0, round(bl_chal_num(case p_kind when 'weekly' then 'challenges.rerolls_per_week' else 'challenges.rerolls_per_day' end,
                                       case p_kind when 'weekly' then 0 else 1 end))::int);
$$;

-- an accepted friend of p_uid who is standing in p_loc right now (not travelling, seen in the last 10 minutes)
create or replace function public.bl_chal_friend_at(p_uid uuid, p_loc text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_loc is not null and exists (
    select 1 from player_friendships f
      join profiles p on p.id = case when f.user_a = p_uid then f.user_b else f.user_a end
     where f.status = 'accepted' and (f.user_a = p_uid or f.user_b = p_uid)
       and p.location_id = p_loc and p.travel_to is null and not p.banned
       and p.last_seen > bl_now() - interval '10 minutes');
$$;

create or replace function public.bl_chal_has_friend(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from player_friendships f where f.status = 'accepted' and (f.user_a = p_uid or f.user_b = p_uid));
$$;

-- Can this player be given this template yet? (skill / certificate gates, "needs", and what the named hustle needs.)
create or replace function public.bl_chal_can(p_uid uuid, t public.challenge_templates) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  h      hustles;
  v_need text := t.needs;
begin
  if t.min_skill is not null and t.min_skill_level > 1 and bl_skill_level(p_uid, t.min_skill) < t.min_skill_level then return false; end if;
  if t.req_cert is not null and bl_school_on() and not bl_cert_has(p_uid, t.req_cert) then return false; end if;
  -- implied needs
  if v_need is null then
    v_need := case t.goal when 'yahoo_clean' then 'laptop' when 'shift' then 'job' when 'class' then 'enrolled'
                          when 'dm_people' then 'friend' when 'dm_send' then 'friend'
                          when 'friend_hustle' then 'friend' when 'friend_house' then 'friend' when 'friend_meet' then 'friend' end;
  end if;
  if v_need is not null then
    if v_need = 'job' then
      if not exists (select 1 from profiles where id = p_uid and job_id is not null) then return false; end if;
    elsif v_need = 'laptop' then
      if bl_yahoo_laptop(p_uid) is null then return false; end if;
    elsif v_need = 'enrolled' then
      if not exists (select 1 from course_enrolments where user_id = p_uid and status = 'enrolled') then return false; end if;
    elsif v_need = 'friend' then
      if not bl_chal_has_friend(p_uid) then return false; end if;
    elsif not exists (select 1 from inventory where user_id = p_uid and item_id = v_need and qty > 0) then
      return false;
    end if;
  end if;
  if t.goal in ('hustle_done', 'friend_hustle') and t.param is not null then
    select * into h from hustles where id = t.param;
    if found then
      if not h.active then return false; end if;
      if bl_skill_gate(p_uid, 'hustle', h.id, h.min_skill_level) is not null then return false; end if;
      if bl_cert_gate(p_uid, h.req_cert) is not null then return false; end if;
      if h.needs_car and bl_hustle_car(p_uid) is null then return false; end if;
      -- a challenge asks for the proper kit even when the hustle can be done badly without it (DJ without a controller pays 40%)
      if h.req_item is not null
         and not exists (select 1 from inventory where user_id = p_uid and item_id = h.req_item and qty > 0) then return false; end if;
      if h.needs_pass is not null and bl_hustle_pass_until(p_uid, h.needs_pass) is null then return false; end if;
    end if;
  end if;
  return true;
end $$;

-- Weighted random order without a random number generator: the same player, kind, period (and reroll number) always gives the same order.
-- key = -ln(u) / weight with u from md5(seed || template id); the lowest keys win (weighted sampling without replacement).
create or replace function public.bl_chal_candidates(p_uid uuid, p_kind text, p_seed text, p_skip text[])
returns setof public.challenge_templates
language sql stable security definer set search_path = public as $$
  select t.* from challenge_templates t
   where t.active and t.kind = p_kind and t.weight > 0 and t.id <> all (p_skip) and bl_chal_can(p_uid, t)
   order by (-ln(greatest((('x' || substr(md5(p_seed || ':' || t.id), 1, 13))::bit(52)::bigint)::numeric / 4503599627370496, 1e-9)) / t.weight), t.id;
$$;

create or replace function public.bl_chal_insert(p_uid uuid, p_t public.challenge_templates, p_period date, p_slot int) returns void
language sql security definer set search_path = public as $$
  insert into player_challenges (user_id, kind, period, slot, template_id, goal, param, target, reward_cash, reward_xp, reward_skill,
                                 reward_skill_xp, reward_item, reward_item_qty, created_at)
  values (p_uid, p_t.kind, p_period, p_slot, p_t.id, p_t.goal, nullif(btrim(coalesce(p_t.param, '')), ''), p_t.target, p_t.reward_cash,
          p_t.reward_xp, p_t.reward_skill, p_t.reward_skill_xp, p_t.reward_item, p_t.reward_item_qty, bl_now())
  on conflict (user_id, kind, period, slot) do nothing;
$$;

-- Hand out the player's challenges for the current day and week (fills only the slots that are empty, so it is safe to call any time).
create or replace function public.bl_challenge_assign(p_uid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_today  date := bl_wat_date();
  v_week   date := bl_week_start();
  k        text;
  v_period date;
  v_n      int;
  v_have   int;
  v_goals  text[];
  v_ids    text[];
  v_slots  int[];
  v_seed   text;
  v_slot   int;
  t        challenge_templates;
  v_pass   int;
begin
  if not bl_chal_on() then return; end if;
  if not exists (select 1 from profiles where id = p_uid) then return; end if;
  perform pg_advisory_xact_lock(hashtextextended('challenges:' || p_uid::text, 0));
  update player_challenges set expired = true
   where user_id = p_uid and completed_at is null and not expired
     and ((kind = 'daily' and period < v_today) or (kind = 'weekly' and period < v_week));
  foreach k in array array['daily', 'weekly'] loop
    v_period := case k when 'weekly' then v_week else v_today end;
    v_n := bl_chal_count(k);
    select count(*)::int, coalesce(array_agg(goal), '{}'), coalesce(array_agg(template_id), '{}'), coalesce(array_agg(slot::int), '{}')
      into v_have, v_goals, v_ids, v_slots
      from player_challenges where user_id = p_uid and kind = k and period = v_period;
    if v_have >= v_n then continue; end if;
    v_seed := p_uid::text || ':' || k || ':' || v_period::text;
    -- pass 1 prefers a goal the player does not have yet (variety); pass 2 takes whatever is left
    for v_pass in 1..2 loop
      for t in select * from bl_chal_candidates(p_uid, k, v_seed, v_ids) loop
        exit when v_have >= v_n;
        if v_pass = 1 and t.goal = any (v_goals) then continue; end if;
        if t.id = any (v_ids) then continue; end if;
        select min(s) into v_slot from generate_series(1, 6) s where s <> all (v_slots);
        if v_slot is null then exit; end if;
        perform bl_chal_insert(p_uid, t, v_period, v_slot);
        v_have := v_have + 1;
        v_goals := v_goals || t.goal;
        v_ids := v_ids || t.id;
        v_slots := v_slots || v_slot;
      end loop;
    end loop;
  end loop;
  -- a streak challenge starts from the streak the player already holds today
  if exists (select 1 from player_challenges where user_id = p_uid and goal = 'streak' and completed_at is null and not expired and progress = 0) then
    perform bl_challenge_bump(p_uid, 'streak', (select streak_day from daily_reward_state where user_id = p_uid and last_claim_date = v_today), null);
  end if;
end $$;

-- Does the player have an unfinished challenge for this goal in the current period? (also hands out today's set the first time the
-- player does anything on a new day, so progress is never lost because the panel was not opened.) The hot path is ONE index probe.
create or replace function public.bl_chal_open(p_uid uuid, p_goal text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_today date := bl_wat_date(); v_week date := bl_week_start();
begin
  if exists (select 1 from player_challenges where user_id = p_uid and goal = p_goal and completed_at is null and not expired
                and ((kind = 'daily' and period = v_today) or (kind = 'weekly' and period = v_week))) then
    return true;
  end if;
  if exists (select 1 from player_challenges where user_id = p_uid and kind = 'daily' and period = v_today) then return false; end if;
  if not bl_chal_on() then return false; end if;
  perform bl_challenge_assign(p_uid);
  return exists (select 1 from player_challenges where user_id = p_uid and goal = p_goal and completed_at is null and not expired
                    and ((kind = 'daily' and period = v_today) or (kind = 'weekly' and period = v_week)));
end $$;

-- A challenge was just finished: toast event, and a push when the whole weekly set is done.
create or replace function public.bl_chal_done(r public.player_challenges) returns void
language plpgsql security definer set search_path = public as $$
declare
  t        challenge_templates;
  v_all    boolean;
  v_cash   bigint;
  v_body   text;
begin
  select * into t from challenge_templates where id = r.template_id;
  v_cash := round(r.reward_cash * bl_chal_num('challenges.reward_mult', 1))::bigint;
  select not exists (select 1 from player_challenges where user_id = r.user_id and kind = r.kind and period = r.period and completed_at is null)
    into v_all;
  v_body := case when v_all then 'All ' || r.kind || ' challenges done! Open Challenges for your chest.'
                 when v_cash > 0 then 'Open Challenges and claim ' || bl_naira(v_cash) || '.'
                 else 'Open Challenges to claim your reward.' end;
  perform bl_event(r.user_id, 'challenge_done', coalesce(t.icon, '🎯') || ' ' || coalesce(t.title, 'Challenge') || ' done!', v_body,
                   jsonb_build_object('id', r.id, 'kind', r.kind, 'template', r.template_id, 'chest_ready', v_all));
  if v_all and r.kind = 'weekly' and bl_cfg_bool('challenges.push_weekly') then
    perform bl_push_enqueue(r.user_id, 'events', 'challenge_chest', 'Your weekly chest is ready',
                            'You finished every weekly challenge. Come collect your chest!', '/play', null, null, null,
                            'challenge_chest:' || r.period::text, true, null);
  end if;
end $$;

-- THE one counter. Adds p_amount to every open challenge of this goal (distinct goals count each p_ref once; streak keeps the highest value).
-- A no-op (one index probe) when the player has no matching open challenge.
create or replace function public.bl_challenge_bump(p_uid uuid, p_goal text, p_amount bigint default 1, p_ref text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_today date := bl_wat_date();
  v_week  date := bl_week_start();
  r       player_challenges;
  v_prog  bigint;
  v_refs  text[];
begin
  if p_uid is null or p_amount is null or p_amount <= 0 then return; end if;
  if not bl_chal_open(p_uid, p_goal) then return; end if;
  for r in select * from player_challenges
            where user_id = p_uid and goal = p_goal and completed_at is null and not expired
              and ((kind = 'daily' and period = v_today) or (kind = 'weekly' and period = v_week))
            order by id for update loop
    if r.param is not null and r.param is distinct from p_ref then continue; end if;
    v_refs := r.refs;
    if p_goal in ('visit_place', 'dm_people', 'friend_meet', 'friend_house') then
      if p_ref is null or p_ref = any (r.refs) then continue; end if;
      v_refs := r.refs || p_ref;
      v_prog := cardinality(v_refs);
    elsif p_goal = 'streak' then
      v_prog := greatest(r.progress, p_amount);
    else
      v_prog := r.progress + p_amount;
    end if;
    v_prog := least(v_prog, r.target);
    if v_prog = r.progress and v_refs = r.refs then continue; end if;
    update player_challenges set progress = v_prog, refs = v_refs, completed_at = case when v_prog >= r.target then bl_now() end
     where id = r.id returning * into r;
    if r.completed_at is not null then perform bl_chal_done(r); end if;
  end loop;
end $$;

-- Skill XP straight into player_skills (no trait multiplier), with the same level-up event as bl_skill_award.
create or replace function public.bl_chal_skill_xp(p_uid uuid, p_skill text, p_xp int) returns void
language plpgsql security definer set search_path = public as $$
declare k skills; v_old int; v_new int; v_xp int; v_ups text[];
begin
  if p_xp <= 0 or p_skill is null then return; end if;
  select * into k from skills where id = p_skill and active;
  if not found then return; end if;
  v_old := bl_skill_level_for_xp(bl_skill_xp(p_uid, p_skill));
  insert into player_skills (user_id, skill_id, xp, updated_at) values (p_uid, p_skill, least(p_xp, 1000000000), bl_now())
  on conflict (user_id, skill_id) do update set xp = least(player_skills.xp::bigint + p_xp, 1000000000)::int, updated_at = bl_now()
  returning xp into v_xp;
  v_new := bl_skill_level_for_xp(v_xp);
  if v_new > v_old then
    v_ups := bl_skill_unlocks(p_skill, v_new);
    perform bl_event(p_uid, 'skill_up', k.icon || ' ' || k.name || ' level ' || v_new || '!',
      case when cardinality(v_ups) > 0 then array_to_string(v_ups, ' · ') else 'Keep training, e dey show.' end,
      jsonb_build_object('skill', p_skill, 'name', k.name, 'icon', k.icon, 'level', v_new, 'unlocks', to_jsonb(v_ups)));
  end if;
end $$;

-- pay a reward bundle (cash through the ledger, career XP, skill XP, item); returns the pieces for the message
create or replace function public.bl_chal_pay(p_uid uuid, p_cash bigint, p_xp int, p_skill text, p_skill_xp int, p_item text, p_qty int, p_meta jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_parts text[] := '{}'; v_xp_paid int := 0; v_item items; v_skill skills;
begin
  if p_cash > 0 then
    perform bl_add_money(p_uid, 'cash', p_cash, 'challenge', p_meta);
    v_parts := v_parts || bl_naira(p_cash);
  end if;
  if p_xp > 0 then
    update profiles set job_xp = least(job_xp + p_xp, 1000000) where id = p_uid and job_id is not null returning p_xp into v_xp_paid;
    if v_xp_paid > 0 then v_parts := v_parts || (p_xp || ' career XP'); end if;
  end if;
  if p_skill is not null and p_skill_xp > 0 then
    select * into v_skill from skills where id = p_skill;
    if found then
      perform bl_chal_skill_xp(p_uid, p_skill, p_skill_xp);
      v_parts := v_parts || ('+' || p_skill_xp || ' ' || v_skill.name || ' XP');
    end if;
  end if;
  if p_item is not null and coalesce(p_qty, 0) > 0 then
    select * into v_item from items where id = p_item;
    if found then
      perform bl_give_item(p_uid, p_item, p_qty);
      v_parts := v_parts || (case when p_qty > 1 then p_qty || ' x ' else '' end || v_item.name);
    end if;
  end if;
  return jsonb_build_object('parts', to_jsonb(v_parts), 'xp_paid', v_xp_paid);
end $$;

-- the app's view of one challenge
create or replace function public.bl_chal_json(r public.player_challenges, p_left int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t challenge_templates; k skills; it items; v_mult numeric := bl_chal_num('challenges.reward_mult', 1);
begin
  select * into t from challenge_templates where id = r.template_id;
  select * into k from skills where id = r.reward_skill;
  select * into it from items where id = r.reward_item;
  return jsonb_build_object(
    'id', r.id, 'slot', r.slot, 'template', r.template_id, 'kind', r.kind,
    'title', t.title, 'blurb', t.blurb, 'icon', t.icon, 'friends', t.friends, 'goal', r.goal,
    'money', r.goal in ('earn', 'club_spend', 'spray'),
    'target', r.target, 'progress', r.progress, 'done', r.completed_at is not null, 'claimed', r.claimed_at is not null,
    'reward', jsonb_build_object(
      'cash', round(r.reward_cash * v_mult)::bigint, 'xp', r.reward_xp,
      'skill', r.reward_skill, 'skill_name', k.name, 'skill_icon', k.icon, 'skill_xp', r.reward_skill_xp,
      'item', r.reward_item, 'item_name', it.name, 'item_icon', it.icon, 'item_qty', r.reward_item_qty),
    'can_reroll', p_left > 0 and r.completed_at is null);
end $$;

create or replace function public.bl_chal_chest_json(p_uid uuid, p_kind text, p_period date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_total int; v_done int; v_claimed boolean;
  v_pre   text := case p_kind when 'weekly' then 'challenges.weekly_chest_' else 'challenges.daily_chest_' end;
  v_item  text := nullif(btrim(coalesce(bl_cfg_text(v_pre || 'item'), '')), '');
  v_name  text; v_icon text;
begin
  select count(*)::int, count(completed_at)::int into v_total, v_done
    from player_challenges where user_id = p_uid and kind = p_kind and period = p_period;
  v_claimed := exists (select 1 from challenge_chests where user_id = p_uid and kind = p_kind and period = p_period);
  select name, icon into v_name, v_icon from items where id = v_item;
  return jsonb_build_object('total', v_total, 'done', v_done, 'ready', v_total > 0 and v_done = v_total and not v_claimed, 'claimed', v_claimed,
    'cash', round(coalesce(bl_cfg(v_pre || 'cash'), 0) * bl_chal_num('challenges.reward_mult', 1))::bigint,
    'xp', round(coalesce(bl_cfg(v_pre || 'xp'), 0))::int,
    'item', case when v_name is not null then v_item end, 'item_name', v_name, 'item_icon', v_icon);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.challenge_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := bl_require_uid();
  k        text;
  v_period date;
  v_used   int;
  v_max    int;
  v_left   int;
  v_out    jsonb := jsonb_build_object('enabled', true, 'now', bl_now());
  v_items  jsonb;
  r        player_challenges;
begin
  if not exists (select 1 from profiles where id = v_uid) then return jsonb_build_object('enabled', false); end if;
  if not bl_chal_on() then return jsonb_build_object('enabled', false); end if;
  perform bl_challenge_assign(v_uid);
  foreach k in array array['daily', 'weekly'] loop
    v_period := bl_chal_period(k);
    v_max := bl_chal_rerolls_max(k);
    select coalesce((select used from challenge_rerolls where user_id = v_uid and kind = k and period = v_period), 0) into v_used;
    v_left := greatest(0, v_max - v_used);
    v_items := '[]'::jsonb;
    for r in select * from player_challenges where user_id = v_uid and kind = k and period = v_period order by slot loop
      v_items := v_items || jsonb_build_array(bl_chal_json(r, v_left));
    end loop;
    v_out := v_out || jsonb_build_object(k, jsonb_build_object(
      'period', v_period, 'ends_at', bl_chal_ends(k, v_period),
      'secs_left', greatest(0, ceil(extract(epoch from bl_chal_ends(k, v_period) - bl_now()))::int),
      'rerolls_left', v_left, 'rerolls_max', v_max,
      'items', v_items, 'chest', bl_chal_chest_json(v_uid, k, v_period)));
  end loop;
  return v_out;
end $$;

-- Claim one finished challenge. Once only (row lock + claimed_at), and only while its period is still running.
create or replace function public.challenge_claim(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  r      player_challenges;
  t      challenge_templates;
  v_cash bigint;
  v_pay  jsonb;
  v_msg  text;
begin
  if not bl_chal_on() then
    raise exception 'Challenges are resting for now. Check back soon.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into r from player_challenges where id = p_id and user_id = v_uid for update;
  if not found then
    raise exception 'That challenge is not on your list.' using errcode = 'P0001', hint = 'not_found';
  end if;
  if r.claimed_at is not null then
    raise exception 'You don already collect this one.' using errcode = 'P0001', hint = 'already_claimed';
  end if;
  if r.completed_at is null then
    raise exception 'E never finish yet: % of %.', r.progress, r.target using errcode = 'P0001', hint = 'not_done';
  end if;
  if r.period <> bl_chal_period(r.kind) then
    raise exception 'Time don pass: this reward expired when the % ended.', case r.kind when 'weekly' then 'week' else 'day' end
      using errcode = 'P0001', hint = 'expired';
  end if;
  select * into t from challenge_templates where id = r.template_id;
  update player_challenges set claimed_at = bl_now() where id = r.id;
  v_cash := round(r.reward_cash * bl_chal_num('challenges.reward_mult', 1))::bigint;
  v_pay := bl_chal_pay(v_uid, v_cash, r.reward_xp, r.reward_skill, r.reward_skill_xp, r.reward_item, r.reward_item_qty,
                       jsonb_build_object('challenge', r.template_id, 'title', t.title, 'kind', r.kind, 'run', r.id, 'period', r.period));
  v_msg := case when jsonb_array_length(v_pay->'parts') > 0
                then t.title || ': ' || (select string_agg(x, ' + ') from jsonb_array_elements_text(v_pay->'parts') x)
                else t.title || ' done.' end;
  return jsonb_build_object('message', v_msg, 'cash', v_cash, 'xp', r.reward_xp, 'skill', r.reward_skill, 'skill_xp', r.reward_skill_xp,
                            'item', r.reward_item, 'id', r.id);
end $$;

-- The bonus chest: every challenge of the current day / week finished. Once per period (primary key).
create or replace function public.challenge_claim_chest(p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := bl_require_uid();
  v_period date;
  v_total  int;
  v_done   int;
  v_pre    text;
  v_cash   bigint;
  v_xp     int;
  v_item   text;
  v_ins    int;
  v_pay    jsonb;
begin
  if p_kind not in ('daily', 'weekly') then
    raise exception 'Pick daily or weekly.' using errcode = 'P0001', hint = 'bad_kind';
  end if;
  if not bl_chal_on() then
    raise exception 'Challenges are resting for now. Check back soon.' using errcode = 'P0001', hint = 'disabled';
  end if;
  perform 1 from profiles where id = v_uid for update;
  v_period := bl_chal_period(p_kind);
  select count(*)::int, count(completed_at)::int into v_total, v_done
    from player_challenges where user_id = v_uid and kind = p_kind and period = v_period;
  if v_total = 0 or v_done < v_total then
    raise exception 'Finish all your % challenges first (% of % done).', p_kind, v_done, v_total using errcode = 'P0001', hint = 'not_done';
  end if;
  v_pre := case p_kind when 'weekly' then 'challenges.weekly_chest_' else 'challenges.daily_chest_' end;
  v_cash := round(coalesce(bl_cfg(v_pre || 'cash'), 0) * bl_chal_num('challenges.reward_mult', 1))::bigint;
  v_xp := round(coalesce(bl_cfg(v_pre || 'xp'), 0))::int;
  v_item := nullif(btrim(coalesce(bl_cfg_text(v_pre || 'item'), '')), '');
  if v_item is not null and not exists (select 1 from items where id = v_item) then v_item := null; end if;
  insert into challenge_chests (user_id, kind, period, cash, xp, item, claimed_at) values (v_uid, p_kind, v_period, v_cash, v_xp, v_item, bl_now())
  on conflict do nothing;
  get diagnostics v_ins = row_count;
  if v_ins = 0 then
    raise exception 'You already opened this chest.' using errcode = 'P0001', hint = 'already_claimed';
  end if;
  v_pay := bl_chal_pay(v_uid, v_cash, v_xp, null, 0, v_item, 1,
                       jsonb_build_object('chest', p_kind, 'title', case p_kind when 'weekly' then 'Weekly chest' else 'Daily chest' end, 'period', v_period));
  return jsonb_build_object('message', case p_kind when 'weekly' then 'Weekly chest: ' else 'Daily chest: ' end ||
                              coalesce((select string_agg(x, ' + ') from jsonb_array_elements_text(v_pay->'parts') x), 'well done'),
                            'cash', v_cash, 'xp', v_xp, 'item', v_item, 'kind', p_kind);
end $$;

-- Swap one unfinished challenge for another (limited per day / week by Settings). Progress on the swapped one is lost.
create or replace function public.challenge_reroll(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := bl_require_uid();
  r        player_challenges;
  t        challenge_templates;
  v_max    int;
  v_used   int;
  v_ids    text[];
  v_goals  text[];
  v_seen   text[];
  v_old    text;
  v_seed   text;
  v_new    challenge_templates;
  v_found  boolean := false;
  v_pass   int;
  v_left   int;
begin
  if not bl_chal_on() then
    raise exception 'Challenges are resting for now. Check back soon.' using errcode = 'P0001', hint = 'disabled';
  end if;
  perform 1 from profiles where id = v_uid for update;
  select * into r from player_challenges where id = p_id and user_id = v_uid for update;
  if not found then
    raise exception 'That challenge is not on your list.' using errcode = 'P0001', hint = 'not_found';
  end if;
  if r.completed_at is not null then
    raise exception 'This one is finished. Claim it instead.' using errcode = 'P0001', hint = 'already_done';
  end if;
  if r.period <> bl_chal_period(r.kind) then
    raise exception 'This challenge don expire.' using errcode = 'P0001', hint = 'expired';
  end if;
  v_max := bl_chal_rerolls_max(r.kind);
  select coalesce((select used from challenge_rerolls where user_id = v_uid and kind = r.kind and period = r.period), 0),
         coalesce((select seen from challenge_rerolls where user_id = v_uid and kind = r.kind and period = r.period), '{}')
    into v_used, v_seen;
  if v_used >= v_max then
    raise exception '%', case when v_max = 0 then 'Rerolls are off for ' || r.kind || ' challenges.'
                              else 'No more free rerolls for this ' || case r.kind when 'weekly' then 'week' else 'day' end || '.' end
      using errcode = 'P0001', hint = 'no_rerolls';
  end if;
  select array_agg(template_id), array_agg(goal) into v_ids, v_goals from player_challenges where user_id = v_uid and kind = r.kind and period = r.period;
  v_seed := v_uid::text || ':' || r.kind || ':' || r.period::text || ':r' || (v_used + 1);
  for v_pass in 1..2 loop
    for t in select * from bl_chal_candidates(v_uid, r.kind, v_seed, v_ids || v_seen) loop
      if v_pass = 1 and t.goal = any (v_goals) then continue; end if;
      v_new := t; v_found := true; exit;
    end loop;
    exit when v_found;
  end loop;
  if not v_found then
    raise exception 'Nothing else to swap in right now. Keep this one!' using errcode = 'P0001', hint = 'no_alternative';
  end if;
  v_old := r.template_id;
  update player_challenges set template_id = v_new.id, goal = v_new.goal, param = nullif(btrim(coalesce(v_new.param, '')), ''), target = v_new.target,
         progress = 0, refs = '{}', reward_cash = v_new.reward_cash, reward_xp = v_new.reward_xp, reward_skill = v_new.reward_skill,
         reward_skill_xp = v_new.reward_skill_xp, reward_item = v_new.reward_item, reward_item_qty = v_new.reward_item_qty
   where id = r.id returning * into r;
  insert into challenge_rerolls (user_id, kind, period, used, seen) values (v_uid, r.kind, r.period, 1, array[v_old])
  on conflict (user_id, kind, period) do update set used = challenge_rerolls.used + 1, seen = challenge_rerolls.seen || v_old;
  v_left := greatest(0, v_max - v_used - 1);
  -- a streak challenge starts from the streak already held
  if r.goal = 'streak' then
    perform bl_challenge_bump(v_uid, 'streak', (select streak_day from daily_reward_state where user_id = v_uid and last_claim_date = bl_wat_date()), null);
    select * into r from player_challenges where id = r.id;
  end if;
  return jsonb_build_object('message', 'New challenge: ' || v_new.title, 'item', bl_chal_json(r, v_left), 'rerolls_left', v_left);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Triggers: real events -> bl_challenge_bump
-- ---------------------------------------------------------------------------------------------
-- ledger: earnings (same rule as the weekly top earners), purchases, spray and club spending
create or replace function public.bl_chal_on_ledger() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.delta > 0 then
    if new.reason = any (bl_earn_reasons()) then
      perform bl_challenge_bump(new.user_id, 'earn', new.delta, new.reason);
    end if;
  elsif new.delta < 0 then
    if new.reason in ('shop', 'furniture', 'car_purchase') then
      perform bl_challenge_bump(new.user_id, 'buy_item', 1, new.meta->>'item');
    elsif new.reason = 'spray' then
      perform bl_challenge_bump(new.user_id, 'spray', -new.delta, null);
      perform bl_challenge_bump(new.user_id, 'club_spend', -new.delta, null);
    elsif new.reason = 'activity' and bl_chal_open(new.user_id, 'club_spend')
          and exists (select 1 from activities a where a.id = new.meta->>'activity' and 'club' = any (a.scenes))
          and exists (select 1 from profiles p join locations l on l.id = p.location_id where p.id = new.user_id and l.scene = 'club') then
      perform bl_challenge_bump(new.user_id, 'club_spend', -new.delta, null);
    end if;
  end if;
  return null;
exception when others then
  -- a challenge counter must never block the real write (money, hustles, messages)
  raise warning 'challenge trigger %: %', tg_name, sqlerrm;
  return null;
end $$;

-- a hustle finished (not a loss): any hustle, that hustle, a fish, a hustle with a friend nearby
create or replace function public.bl_chal_on_hustle() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.outcome is not distinct from 'loss' then return null; end if;
  perform bl_challenge_bump(new.user_id, 'hustle_done', 1, new.hustle_id);
  if bl_chal_open(new.user_id, 'friend_hustle') and bl_chal_friend_at(new.user_id, new.location_id) then
    perform bl_challenge_bump(new.user_id, 'friend_hustle', 1, new.hustle_id);
  end if;
  if jsonb_typeof(new.detail->'fish') = 'object' then
    perform bl_challenge_bump(new.user_id, 'fish', 1, new.hustle_id);
  end if;
  return null;
exception when others then
  -- a challenge counter must never block the real write (money, hustles, messages)
  raise warning 'challenge trigger %: %', tg_name, sqlerrm;
  return null;
end $$;

create or replace function public.bl_chal_on_class() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform bl_challenge_bump(new.user_id, 'class', 1, new.course_id);
  return null;
exception when others then
  -- a challenge counter must never block the real write (money, hustles, messages)
  raise warning 'challenge trigger %: %', tg_name, sqlerrm;
  return null;
end $$;

create or replace function public.bl_chal_on_yahoo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform bl_challenge_bump(new.user_id, 'yahoo_clean', 1, new.job_id);
  return null;
exception when others then
  -- a challenge counter must never block the real write (money, hustles, messages)
  raise warning 'challenge trigger %: %', tg_name, sqlerrm;
  return null;
end $$;

create or replace function public.bl_chal_on_skill() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_gain int;
begin
  if not bl_chal_open(new.user_id, 'skill_up') then return null; end if;
  v_gain := bl_skill_level_for_xp(new.xp) - bl_skill_level_for_xp(case when tg_op = 'UPDATE' then old.xp else 0 end);
  if v_gain > 0 then perform bl_challenge_bump(new.user_id, 'skill_up', v_gain, new.skill_id); end if;
  return null;
exception when others then
  -- a challenge counter must never block the real write (money, hustles, messages)
  raise warning 'challenge trigger %: %', tg_name, sqlerrm;
  return null;
end $$;

-- profiles: a finished career shift (job_total_shifts goes up) and arriving somewhere new
create or replace function public.bl_chal_on_profile() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_public boolean;
begin
  if new.job_total_shifts > old.job_total_shifts then
    perform bl_challenge_bump(new.id, 'shift', 1, new.job_id);
  end if;
  if new.location_id is distinct from old.location_id and new.travel_to is null then
    if bl_chal_open(new.id, 'visit_place') or bl_chal_open(new.id, 'friend_meet') then
      select exists (select 1 from locations l where l.id = new.location_id and l.private_home_owner_id is null and l.scene not like 'home%'
                        and coalesce(l.active, true)) into v_public;
      if v_public then
        perform bl_challenge_bump(new.id, 'visit_place', 1, new.location_id);
        if bl_chal_open(new.id, 'friend_meet') and bl_chal_friend_at(new.id, new.location_id) then
          perform bl_challenge_bump(new.id, 'friend_meet', 1, new.location_id);
        end if;
      end if;
    end if;
  end if;
  return null;
exception when others then
  -- a challenge counter must never block the real write (money, hustles, messages)
  raise warning 'challenge trigger %: %', tg_name, sqlerrm;
  return null;
end $$;

create or replace function public.bl_chal_on_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare c player_conversations;
begin
  perform bl_challenge_bump(new.sender_id, 'dm_send', 1, null);
  if bl_chal_open(new.sender_id, 'dm_people') then
    select * into c from player_conversations where id = new.conversation_id;
    if found then
      perform bl_challenge_bump(new.sender_id, 'dm_people', 1, (case when c.user_a = new.sender_id then c.user_b else c.user_a end)::text);
    end if;
  end if;
  return null;
exception when others then
  -- a challenge counter must never block the real write (money, hustles, messages)
  raise warning 'challenge trigger %: %', tg_name, sqlerrm;
  return null;
end $$;

create or replace function public.bl_chal_on_streak() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform bl_challenge_bump(new.user_id, 'streak', new.streak_day::bigint, null);
  return null;
exception when others then
  -- a challenge counter must never block the real write (money, hustles, messages)
  raise warning 'challenge trigger %: %', tg_name, sqlerrm;
  return null;
end $$;

create or replace function public.bl_chal_on_invite() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform bl_challenge_bump(new.guest_id, 'friend_house', 1, new.host_id::text);
  perform bl_challenge_bump(new.host_id, 'friend_house', 1, new.guest_id::text);
  return null;
exception when others then
  -- a challenge counter must never block the real write (money, hustles, messages)
  raise warning 'challenge trigger %: %', tg_name, sqlerrm;
  return null;
end $$;

drop trigger if exists bl_chal_ledger on public.ledger;
create trigger bl_chal_ledger after insert on public.ledger
  for each row when (new.delta <> 0) execute function public.bl_chal_on_ledger();
drop trigger if exists bl_chal_hustle on public.hustle_runs;
create trigger bl_chal_hustle after update of status on public.hustle_runs
  for each row when (new.status = 'done' and old.status is distinct from 'done') execute function public.bl_chal_on_hustle();
drop trigger if exists bl_chal_class on public.course_runs;
create trigger bl_chal_class after update of status on public.course_runs
  for each row when (new.status = 'done' and old.status is distinct from 'done') execute function public.bl_chal_on_class();
drop trigger if exists bl_chal_yahoo on public.yahoo_runs;
create trigger bl_chal_yahoo after update of status on public.yahoo_runs
  for each row when (new.status in ('paid', 'cashed') and old.status is distinct from new.status) execute function public.bl_chal_on_yahoo();
drop trigger if exists bl_chal_skill on public.player_skills;
create trigger bl_chal_skill after insert or update of xp on public.player_skills
  for each row execute function public.bl_chal_on_skill();
drop trigger if exists bl_chal_profile on public.profiles;
create trigger bl_chal_profile after update of location_id, job_total_shifts on public.profiles
  for each row when (old.location_id is distinct from new.location_id or new.job_total_shifts > old.job_total_shifts) execute function public.bl_chal_on_profile();
drop trigger if exists bl_chal_message on public.player_messages;
create trigger bl_chal_message after insert on public.player_messages
  for each row execute function public.bl_chal_on_message();
drop trigger if exists bl_chal_streak on public.daily_reward_state;
create trigger bl_chal_streak after insert or update of streak_day, last_claim_date on public.daily_reward_state
  for each row when (new.last_claim_date is not null and new.streak_day > 0) execute function public.bl_chal_on_streak();
drop trigger if exists bl_chal_invite on public.player_house_invites;
create trigger bl_chal_invite after update of status on public.player_house_invites
  for each row when (new.status = 'admitted' and old.status is distinct from 'admitted') execute function public.bl_chal_on_invite();

-- ---------------------------------------------------------------------------------------------
-- 6. Stats view (Admin -> Content -> Challenge stats) and seeds
-- ---------------------------------------------------------------------------------------------
create or replace view public.challenge_template_stats as
select t.id, t.kind, t.goal, t.title, t.active,
       count(c.id)::int as assigned,
       count(c.completed_at)::int as completed,
       count(c.claimed_at)::int as claimed,
       case when count(c.id) = 0 then 0 else round(100.0 * count(c.completed_at) / count(c.id), 1) end as completion_pct,
       max(c.completed_at) as last_completed_at
  from public.challenge_templates t
  left join public.player_challenges c on c.template_id = t.id
 group by t.id;
revoke all on public.challenge_template_stats from public, anon, authenticated;

-- columns: id, kind, goal, title, blurb, icon, target, param, needs, reward_cash, reward_xp, reward_skill, reward_skill_xp, weight, friends, sort
-- Daily (about 32). Cash 800 to 4,500 each; a full set is worth about ₦6,000 plus the ₦3,000 chest.
insert into public.challenge_templates (id, kind, goal, title, blurb, icon, target, param, needs, reward_cash, reward_xp, reward_skill, reward_skill_xp, weight, friends, sort) values
('d_claim',        'daily', 'streak',       'Collect your daily reward',   'Claim today''s daily reward. Free money no dey waste.',                              '🎁', 1,  null,            null,      800,  0,  null,       0,  10, false, 10),
('d_hustle_1',     'daily', 'hustle_done',  'Small hustle, big gist',      'Finish 1 hustle. Any hustle, na work.',                                                 '💪', 1,  null,            null,      1500, 0,  null,       0,  14, false, 20),
('d_hustle_2',     'daily', 'hustle_done',  'Double hustle',               'Finish 2 hustles today. Benin no dull.',                                                '💪', 2,  null,            null,      2800, 10, null,       0,  10, false, 21),
('d_hustle_3',     'daily', 'hustle_done',  'Hustle grandmaster',          'Finish 3 hustles in one day. Na so we do am.',                                          '🏅', 3,  null,            null,      4500, 15, null,       0,  5,  false, 22),
('d_bolt',         'daily', 'hustle_done',  'Bolt rush hour',              'Finish 2 Bolt shifts. Ring Road go-slow no go beat you.',                                '🚗', 2,  'bolt_shift',    null,      3000, 0,  'driving',  8,  6,  false, 30),
('d_pos',          'daily', 'hustle_done',  'PoS never sleeps',            'Finish 2 PoS agent batches. Cash out, cash in.',                                         '🏧', 2,  'pos_agent',     null,      2500, 0,  'business',  6, 6,  false, 31),
('d_tutor',        'daily', 'hustle_done',  'Teach somebody',              'Finish 1 tutoring session on campus. Knowledge pays.',                                   '📚', 1,  'tutor_session', null,      2200, 0,  'teaching', 8,  6,  false, 32),
('d_mech',         'daily', 'hustle_done',  'Spanner time',                'Finish 2 quick fixes at Mechanic Village.',                                              '🔧', 2,  'mech_quick',    null,      2800, 0,  'mechanic', 8,  6,  false, 33),
('d_dj',           'daily', 'hustle_done',  'Drop one set',                'Play 1 DJ set at a club. Make the people dance.',                                        '🎧', 1,  'dj_set',        null,      3500, 0,  'music',    10, 5,  false, 34),
('d_mc',           'daily', 'hustle_done',  'Hold the mic',                'MC 1 night at a club. Talk well, collect well.',                                         '🎤', 1,  'mc_gig',        null,      3000, 0,  'charisma', 8,  5,  false, 35),
('d_earn_5k',      'daily', 'earn',         'Fill your pocket',            'Earn ₦5,000 from jobs, hustles or investments.',                                        '💰', 5000,  null,         null,      1500, 0,  null,       0,  12, false, 40),
('d_earn_12k',     'daily', 'earn',         'Big pocket day',              'Earn ₦12,000 from jobs, hustles or investments. Oga at the top!',                       '💰', 12000, null,         null,      3200, 15, null,       0,  6,  false, 41),
('d_earn_hustle',  'daily', 'earn',         'Hustle money only',           'Earn ₦6,000 from hustles.',                                                             '💵', 6000,  'hustle',     null,      1800, 0,  null,       0,  7,  false, 42),
('d_earn_salary',  'daily', 'earn',         'Salary alert',                'Earn ₦3,000 in salary from your job.',                                                  '🏦', 3000,  'salary',     'job',     1500, 0,  null,       0,  7,  false, 43),
('d_shift_1',      'daily', 'shift',        'Clock in, oga',               'Finish 1 career shift at work.',                                                        '💼', 1,  null,            'job',     1500, 0,  null,       0,  12, false, 50),
('d_shift_2',      'daily', 'shift',        'Double shift',                'Finish 2 career shifts today. Your boss go notice.',                                    '💼', 2,  null,            'job',     3000, 20, null,       0,  6,  false, 51),
('d_class_1',      'daily', 'class',        'Show up for class',           'Attend 1 class. Book na better than long story.',                                       '🎓', 1,  null,            'enrolled', 1500, 15, null,      0,  10, false, 55),
('d_class_2',      'daily', 'class',        'Front-row student',           'Attend 2 classes today.',                                                               '🎓', 2,  null,            'enrolled', 3000, 25, null,      0,  5,  false, 56),
('d_yahoo_1',      'daily', 'yahoo_clean',  'Clean run',                   'Finish 1 Yahoo job without EFCC catching you.',                                         '💻', 1,  null,            'laptop',  3000, 0,  'yahoo',    8,  6,  false, 60),
('d_visit_3',      'daily', 'visit_place',  'Waka round town',             'Visit 3 different places in Benin.',                                                    '🗺️', 3,  null,            null,      1200, 0,  null,       0,  12, false, 70),
('d_visit_5',      'daily', 'visit_place',  'Town tour',                   'Visit 5 different places today.',                                                       '🗺️', 5,  null,            null,      2500, 10, null,       0,  6,  false, 71),
('d_club_spend',   'daily', 'club_spend',   'Club night',                  'Spend ₦5,000 at the club. Enjoy yourself, e dey sweet.',                                '🪩', 5000, null,          null,      2000, 0,  'charisma', 5,  7,  false, 75),
('d_spray',        'daily', 'spray',        'Spray something',             'Spray ₦5,000 at the club. Make the DJ shout your name.',                                '💸', 5000, null,          null,      2500, 0,  null,       0,  5,  false, 76),
('d_dm_3',         'daily', 'dm_send',      'Oya, text your people',       'Send 3 DMs to your friends.',                                                           '💬', 3,  null,            'friend',  1000, 0,  null,       0,  10, true,  80),
('d_chat_2',       'daily', 'dm_people',    'Gist with two people',        'Chat with 2 different players in your DMs.',                                            '🗣️', 2,  null,            'friend',  1500, 0,  'charisma', 4,  8,  true,  81),
('d_fish_1',       'daily', 'fish',         'Catch something',             'Catch 1 fish at Ikpoba riverbank. Patience pays.',                                      '🎣', 1,  null,            'fishing_rod', 1800, 0, 'fishing', 8, 7,  false, 85),
('d_fish_2',       'daily', 'fish',         'Fisherman''s luck',           'Catch 2 fish today. Old slippers no count!',                                            '🐟', 2,  null,            'fishing_rod', 3200, 0, 'fishing', 12, 4, false, 86),
('d_skill_up',     'daily', 'skill_up',     'Level up',                    'Gain 1 skill level today.',                                                             '🌟', 1,  null,            null,      3000, 20, null,       0,  3,  false, 90),
('d_buy',          'daily', 'buy_item',     'Buy something nice',          'Buy an item from any shop or market. Treat yourself.',                                  '🛍️', 1,  null,            null,      1000, 0,  null,       0,  12, false, 95),
('d_friend_hustle','daily', 'friend_hustle','Hustle with your padi',       'Finish a hustle at the same place as a friend. Meet up first!',                         '🤝', 1,  null,            'friend',  3000, 15, null,       0,  6,  true,  100),
('d_friend_house', 'daily', 'friend_house', 'Visit a friend''s house',     'Go inside a friend''s house, or open your door for one.',                               '🏠', 1,  null,            'friend',  3000, 0,  null,       0,  4,  true,  101),
('d_friend_meet',  'daily', 'friend_meet',  'Link up',                     'Arrive at a place where a friend is standing right now.',                               '📍', 1,  null,            'friend',  2000, 0,  null,       0,  6,  true,  102)
on conflict (id) do nothing;

-- Weekly (13). Cash 6,000 to 15,000 each; a full set is worth about ₦30,000 plus the ₦20,000 chest.
insert into public.challenge_templates (id, kind, goal, title, blurb, icon, target, param, needs, reward_cash, reward_xp, reward_skill, reward_skill_xp, min_skill, min_skill_level, weight, friends, sort) values
('w_hustle_10',    'weekly', 'hustle_done',  'Hustle week',               'Finish 10 hustles this week. No sleep, na hustle.',                                      '💪', 10, null,         null,      9000,  40, null,       0,  null, 1, 12, false, 10),
('w_bolt_6',       'weekly', 'hustle_done',  'Bolt for the week',         'Finish 6 Bolt shifts. Keep the car moving.',                                              '🚗', 6,  'bolt_shift', null,      10000, 0,  'driving',  25, null, 1, 6,  false, 11),
('w_earn_50k',     'weekly', 'earn',         'Money week',                'Earn ₦50,000 from jobs, hustles or investments this week.',                              '💰', 50000, null,      null,      10000, 50, null,       0,  null, 1, 12, false, 20),
('w_earn_150k',    'weekly', 'earn',         'Chairman in training',      'Earn ₦150,000 from jobs, hustles or investments this week. Big boy mode.',               '🤑', 150000, null,     null,      15000, 80, null,       0,  null, 1, 4,  false, 21),
('w_shift_5',      'weekly', 'shift',        'Show up all week',          'Finish 5 career shifts. Your boss go love you.',                                         '💼', 5,  null,         'job',     9000,  40, null,       0,  null, 1, 10, false, 30),
('w_class_4',      'weekly', 'class',        'Back to school',            'Attend 4 classes this week. Certificate dey wait.',                                      '🎓', 4,  null,         'enrolled', 9000, 60, null,       0,  null, 1, 8,  false, 40),
('w_yahoo_3',      'weekly', 'yahoo_clean',  'Three clean runs',          'Finish 3 Yahoo jobs without EFCC catching you. Stay sharp.',                             '💻', 3,  null,         'laptop',  12000, 0,  'yahoo',    30, 'yahoo', 2, 5, false, 50),
('w_visit_12',     'weekly', 'visit_place',  'Explore Benin',             'Visit 12 different places. Oba Market to Ring Road, see everywhere.',                    '🗺️', 12, null,         null,      7000,  20, null,       0,  null, 1, 10, false, 60),
('w_club_40k',     'weekly', 'club_spend',   'Big weekend',               'Spend ₦40,000 at clubs. You dey fear? Come out!',                                        '🪩', 40000, null,      null,      9000,  0,  'charisma', 15, null, 1, 6,  false, 70),
('w_fish_5',       'weekly', 'fish',         'Fisherman''s week',         'Catch 5 fish. The river dey pay.',                                                       '🎣', 5,  null,         'fishing_rod', 8000, 0,  'fishing',  30, null, 1, 6,  false, 80),
('w_skill_3',      'weekly', 'skill_up',     'Grow your skills',          'Gain 3 skill levels this week.',                                                         '🌟', 3,  null,         null,      10000, 60, null,       0,  null, 1, 6,  false, 90),
('w_streak_5',     'weekly', 'streak',       'Stay consistent',           'Hit a 5-day daily reward streak. Come back every day.',                                  '🔥', 5,  null,         null,      8000,  0,  null,       0,  null, 1, 8,  false, 100),
('w_friend_chat',  'weekly', 'dm_people',    'Catch up with your people', 'Chat with 5 different players in your DMs this week.',                                   '🗣️', 5,  null,         'friend',  6000,  0,  'charisma', 10, null, 1, 7,  true,  110),
('w_friend_hustle','weekly', 'friend_hustle','Hustle squad',              'Finish 3 hustles at the same place as a friend.',                                        '🤝', 3,  null,         'friend',  9000,  30, null,       0,  null, 1, 5,  true,  111)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 7. Guarded edits of live functions
-- ---------------------------------------------------------------------------------------------
-- p_edits: [{done, marker, new}]. An edit is skipped when `done` is already in the definition; it raises when the marker is
-- missing or is not unique. All edits are applied to one definition and executed once (create or replace keeps the grants).
create or replace function pg_temp.bl_patch(p_sig text, p_edits jsonb) returns void
language plpgsql as $$
declare v_def text; e jsonb; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  for e in select * from jsonb_array_elements(p_edits) loop
    if position(e->>'done' in v_def) > 0 then continue; end if;
    v_n := (length(v_def) - length(replace(v_def, e->>'marker', ''))) / length(e->>'marker');
    if v_n = 0 then raise exception '% : marker not found: %', p_sig, e->>'marker'; end if;
    if v_n > 1 then raise exception '% : marker not unique (% times): %', p_sig, v_n, e->>'marker'; end if;
    v_def := replace(v_def, e->>'marker', e->>'new');
  end loop;
  execute v_def;
end $$;

-- challenge rewards are never an earning: even if an admin lists 'challenge' in leaderboard.earn_reasons it is dropped
select pg_temp.bl_patch('public.bl_earn_reasons()', $j$[
 {"done": "<> 'challenge'", "marker": "where btrim(x) <> ''",
  "new": "where btrim(x) <> '' and btrim(x) <> 'challenge'"}
]$j$::jsonb);

-- ledger text: "Challenge: Hustle week" / "Challenge: Daily chest"
select pg_temp.bl_patch('public.bl_ledger_label(text, jsonb)', $j$[
 {"done": "when 'challenge' then", "marker": "when 'topup' then",
  "new": "when 'challenge' then return 'Challenge: ' || coalesce(nullif(p_meta->>'title', ''), 'reward');\n    when 'topup' then"}
]$j$::jsonb);

-- admin Content editor: the templates (editable) and the stats view (read-only)
select pg_temp.bl_patch('public.bl_admin_table_spec(text)', $j$[
 {"done": "when 'challenge_templates' then", "marker": "when 'daily_reward_steps' then",
  "new": "when 'challenge_templates' then '{\"pk\":[\"id\"],\"insert\":true,\"order\":\"kind, sort, id\",\n      \"cols\":{\"kind\":\"text\",\"goal\":\"text\",\"title\":\"text\",\"blurb\":\"text\",\"icon\":\"text\",\"target\":\"int\",\"param\":\"text_null\",\"needs\":\"text_null\",\n              \"reward_cash\":\"money\",\"reward_xp\":\"int\",\"reward_skill\":\"text_null\",\"reward_skill_xp\":\"int\",\"reward_item\":\"text_null\",\"reward_item_qty\":\"int\",\n              \"weight\":\"num\",\"min_skill\":\"text_null\",\"min_skill_level\":\"int\",\"req_cert\":\"text_null\",\"friends\":\"bool\",\"sort\":\"int\",\"active\":\"bool\"}}'\n    when 'challenge_template_stats' then '{\"pk\":[\"id\"],\"insert\":false,\"order\":\"kind, completed desc, id\",\"cols\":{}}'\n    when 'daily_reward_steps' then"}
]$j$::jsonb);

-- ---------------------------------------------------------------------------------------------
-- 8. Grants
-- ---------------------------------------------------------------------------------------------
revoke all on function public.bl_chal_on() from public, anon, authenticated;
revoke all on function public.bl_chal_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_chal_period(text) from public, anon, authenticated;
revoke all on function public.bl_chal_ends(text, date) from public, anon, authenticated;
revoke all on function public.bl_chal_count(text) from public, anon, authenticated;
revoke all on function public.bl_chal_rerolls_max(text) from public, anon, authenticated;
revoke all on function public.bl_chal_friend_at(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_chal_has_friend(uuid) from public, anon, authenticated;
revoke all on function public.bl_chal_can(uuid, public.challenge_templates) from public, anon, authenticated;
revoke all on function public.bl_chal_candidates(uuid, text, text, text[]) from public, anon, authenticated;
revoke all on function public.bl_chal_insert(uuid, public.challenge_templates, date, int) from public, anon, authenticated;
revoke all on function public.bl_challenge_assign(uuid) from public, anon, authenticated;
revoke all on function public.bl_chal_open(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_chal_done(public.player_challenges) from public, anon, authenticated;
revoke all on function public.bl_challenge_bump(uuid, text, bigint, text) from public, anon, authenticated;
revoke all on function public.bl_chal_skill_xp(uuid, text, int) from public, anon, authenticated;
revoke all on function public.bl_chal_pay(uuid, bigint, int, text, int, text, int, jsonb) from public, anon, authenticated;
revoke all on function public.bl_chal_json(public.player_challenges, int) from public, anon, authenticated;
revoke all on function public.bl_chal_chest_json(uuid, text, date) from public, anon, authenticated;
revoke all on function public.bl_chal_on_ledger() from public, anon, authenticated;
revoke all on function public.bl_chal_on_hustle() from public, anon, authenticated;
revoke all on function public.bl_chal_on_class() from public, anon, authenticated;
revoke all on function public.bl_chal_on_yahoo() from public, anon, authenticated;
revoke all on function public.bl_chal_on_skill() from public, anon, authenticated;
revoke all on function public.bl_chal_on_profile() from public, anon, authenticated;
revoke all on function public.bl_chal_on_message() from public, anon, authenticated;
revoke all on function public.bl_chal_on_streak() from public, anon, authenticated;
revoke all on function public.bl_chal_on_invite() from public, anon, authenticated;

revoke all on function public.challenge_status() from public, anon;
grant execute on function public.challenge_status() to authenticated, service_role;
revoke all on function public.challenge_claim(bigint) from public, anon;
grant execute on function public.challenge_claim(bigint) to authenticated, service_role;
revoke all on function public.challenge_claim_chest(text) from public, anon;
grant execute on function public.challenge_claim_chest(text) to authenticated, service_role;
revoke all on function public.challenge_reroll(bigint) from public, anon;
grant execute on function public.challenge_reroll(bigint) to authenticated, service_role;

notify pgrst, 'reload schema';
