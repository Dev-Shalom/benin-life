-- V1-3 Jobs that pay (docs/CAREERS.md, ARCHITECTURE §9b).
-- * career_tracks / career_levels: data-driven ladders (admin-editable rows), launch subset of 6 tracks.
-- * New location bronze_tech_hub (scene office) + 'jobs' on every workplace that needs it.
-- * career.* config (performance weights, multipliers, daily shift cap, head start, rejoin rule).
-- * profiles: shift bookkeeping columns + career_best (best level ever reached per track; "degree").
-- * RPCs: jobs_catalog, job_apply, job_quit, work_shift, work_finish; get_my_state gains a `career` block.
-- Safe on a non-empty DB: create ... if not exists, insert ... on conflict do nothing, guarded updates.

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
create table if not exists public.career_tracks (
  id           text primary key,
  name         text not null,
  emoji        text not null default '💼',
  category     text not null default 'official' check (category in ('official', 'hustle')),
  location_ids text[] not null default '{}',
  description  text not null default '',
  -- trait effects.skill_xp key that boosts XP on this track (e.g. 'coding'); null = none
  skill        text,
  sort         int not null default 0,
  active       boolean not null default true
);

create table if not exists public.career_levels (
  track_id           text not null references public.career_tracks(id) on update cascade on delete cascade,
  level              int  not null check (level >= 1),
  title              text not null,
  pay_per_shift      bigint not null default 0 check (pay_per_shift >= 0),
  shift_game_minutes int  not null default 240 check (shift_game_minutes > 0),
  energy_cost        int  not null default 10 check (energy_cost >= 0),
  -- other need deltas applied when the shift starts, e.g. {"hunger": -6, "stress": 5}
  effects            jsonb not null default '{}'::jsonb,
  xp_per_shift       int  not null default 10 check (xp_per_shift >= 0),
  -- XP needed at this level to be promoted to level+1; null = top of the ladder
  xp_to_next         int  check (xp_to_next is null or xp_to_next > 0),
  -- what it takes to reach THIS level (promotion into it, or a direct hire through head start):
  -- {"min_shifts_in_level": 3, "item": "laptop", "degree": true, "min_level_track": {"education": 2},
  --  "min_street_cred": 0}. min_shifts_in_level counts shifts at the level below (promotion only).
  requirements       jsonb not null default '{}'::jsonb,
  perks              jsonb not null default '{}'::jsonb,
  primary key (track_id, level)
);

alter table public.career_tracks enable row level security;
alter table public.career_levels enable row level security;
revoke all on table public.career_tracks, public.career_levels from anon, authenticated;
grant select on public.career_tracks, public.career_levels to anon, authenticated;
drop policy if exists career_tracks_read on public.career_tracks;
create policy career_tracks_read on public.career_tracks for select to anon, authenticated using (true);
drop policy if exists career_levels_read on public.career_levels;
create policy career_levels_read on public.career_levels for select to anon, authenticated using (true);

-- ---------------------------------------------------------------------
-- 2. Profile columns (job_id, job_level, job_xp are core)
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists job_started_at       timestamptz;
alter table public.profiles add column if not exists job_shifts_in_level  int not null default 0;
alter table public.profiles add column if not exists job_total_shifts     int not null default 0;
alter table public.profiles add column if not exists job_shift_day        int;
alter table public.profiles add column if not exists job_shifts_today     int not null default 0;
-- the running shift: paid by work_finish() once job_shift_ends_at has passed
alter table public.profiles add column if not exists job_shift_ends_at    timestamptz;
alter table public.profiles add column if not exists job_shift_pay        bigint;
alter table public.profiles add column if not exists job_shift_xp         int;
alter table public.profiles add column if not exists job_shift_perf       int;
-- best level ever reached per track, e.g. {"education": 2}; the "degree" reads education here
alter table public.profiles add column if not exists career_best          jsonb not null default '{}'::jsonb;

-- ---------------------------------------------------------------------
-- 3. Location: Bronze Tech Hub (MAP_GEO.md 535,190) + jobs on workplaces
-- ---------------------------------------------------------------------
insert into public.locations (id, name, district, scene, blurb, risk, night_risk_mult, cctv, keke_ok,
                              congestion, remote_km, x, y, actions, sort) values
('bronze_tech_hub', 'Bronze Tech Hub', 'ugbowo', 'office',
 'Glass, solar panels and a generator on standby. Startups, remote devs and UNIBEN grads building the next big app from Ugbowo.',
 0.12, 1.4, true, true, 1.1, 0, 535, 190, '{jobs,activities}', 152)
on conflict (id) do nothing;

update public.locations set actions = array_append(actions, 'jobs')
 where id in ('mercy_clinic', 'ekiosa_market', 'santana_market') and not ('jobs' = any(actions));

-- office activities (scene office) and the restroom there
insert into public.activities (id, name, scenes, home_only, cost, game_minutes, effects, night_only, sort) values
('office_coffee', 'Coffee and small chops in the lounge', '{office}', false, 400, 15,
  '{"energy": 8, "hunger": 6, "fun": 3}', false, 230),
('tech_meetup', 'Join the evening tech meetup', '{office}', false, 0, 90,
  '{"social": 18, "fun": 10, "energy": -5}', false, 231)
on conflict (id) do nothing;
update public.activities set scenes = array_append(scenes, 'office')
 where id = 'ease_yourself' and not ('office' = any(scenes));

-- ---------------------------------------------------------------------
-- 4. Seeds: tracks + levels (launch subset). Admin edits the rows; re-runs never overwrite them.
-- ---------------------------------------------------------------------
insert into public.career_tracks (id, name, emoji, category, location_ids, description, skill, sort) values
('tech', 'Tech', '💻', 'official', '{bronze_tech_hub}',
 'Code your way up from intern to CTO at the Bronze Tech Hub in Ugbowo. A laptop is a must after the internship, and senior roles want a degree.', 'coding', 10),
('pos', 'PoS & Fintech', '🏧', 'official', '{ring_road_pos,new_benin_pos,sapele_pos}',
 'Run a PoS stand: withdrawals, transfers and airtime for the whole street. Grow into a super agent with your own network.', 'hustle', 20),
('trade', 'Trade', '🛒', 'official', '{oba_market,new_benin_market,uselu_market,oregbeni_market,ekiosa_market,santana_market}',
 'Start as a market apprentice, learn the prices, then get your own shop and supply half of Benin.', 'hustle', 30),
('transport', 'Transport', '🛺', 'official', '{uselu_park,oluku_park,ramat_park,aduwawa_park}',
 'Ride keke, drive the bus, then run the park and own the fleet. The motor park never sleeps.', 'hustle', 40),
('health', 'Health', '🩺', 'official', '{ubth,mercy_clinic}',
 'From ward attendant to Chief Medical Director at UBTH or Mercy Clinic. Nursing and doctor roles need a UNIBEN degree.', null, 50),
('education', 'Education', '🎓', 'official', '{uniben}',
 'Study at UNIBEN for a small stipend. Graduate Assistant (level 2) counts as your degree, which opens senior Tech and Health roles.', null, 60)
on conflict (id) do nothing;

insert into public.career_levels (track_id, level, title, pay_per_shift, shift_game_minutes, energy_cost, effects, xp_per_shift, xp_to_next, requirements, perks) values
-- Tech (5-hour shifts)
('tech', 1, 'Intern',              3500, 300, 14, '{"hunger": -6, "stress": 4, "fun": -3}', 10, 40,   '{}', '{}'),
('tech', 2, 'Junior Dev',          8000, 300, 15, '{"hunger": -6, "stress": 5, "fun": -3}', 10, 70,   '{"min_shifts_in_level": 3, "item": "laptop"}', '{}'),
('tech', 3, 'Mid-level Dev',      15000, 300, 16, '{"hunger": -6, "stress": 5, "fun": -2}', 10, 110,  '{"min_shifts_in_level": 3, "item": "laptop"}', '{}'),
('tech', 4, 'Senior Dev',         28000, 300, 16, '{"hunger": -6, "stress": 6, "fun": -2}', 10, 160,  '{"min_shifts_in_level": 3, "item": "laptop", "degree": true}', '{}'),
('tech', 5, 'Tech Lead',          45000, 300, 17, '{"hunger": -6, "stress": 7, "fun": -2}', 10, 220,  '{"min_shifts_in_level": 3, "item": "laptop", "degree": true}', '{}'),
('tech', 6, 'Engineering Manager',70000, 300, 17, '{"hunger": -6, "stress": 8, "social": 4}', 10, 300, '{"min_shifts_in_level": 3, "item": "laptop", "degree": true}', '{}'),
('tech', 7, 'CTO',               120000, 300, 18, '{"hunger": -6, "stress": 9, "social": 4}', 10, null, '{"min_shifts_in_level": 3, "item": "laptop", "degree": true}', '{}'),
-- PoS & Fintech (4-hour shifts)
('pos', 1, 'PoS Attendant',  2500, 240, 12, '{"hunger": -5, "stress": 5, "social": 4}', 10, 40,   '{}', '{}'),
('pos', 2, 'PoS Operator',   5000, 240, 12, '{"hunger": -5, "stress": 5, "social": 4}', 10, 70,   '{"min_shifts_in_level": 3}', '{}'),
('pos', 3, 'Super Agent',   12000, 240, 13, '{"hunger": -5, "stress": 6, "social": 5}', 10, 110,  '{"min_shifts_in_level": 3}', '{}'),
('pos', 4, 'Aggregator',    25000, 240, 13, '{"hunger": -5, "stress": 7, "social": 5}', 10, null, '{"min_shifts_in_level": 3}', '{}'),
-- Trade (4-hour shifts)
('trade', 1, 'Market Apprentice', 2000, 240, 14, '{"hunger": -6, "hygiene": -4, "social": 5}', 10, 40,   '{}', '{}'),
('trade', 2, 'Trader',            4500, 240, 14, '{"hunger": -6, "hygiene": -4, "social": 5}', 10, 70,   '{"min_shifts_in_level": 3}', '{}'),
('trade', 3, 'Shop Owner',        9000, 240, 13, '{"hunger": -5, "hygiene": -3, "social": 5}', 10, 110,  '{"min_shifts_in_level": 3}', '{}'),
('trade', 4, 'Wholesaler',       18000, 240, 13, '{"hunger": -5, "stress": 5, "social": 5}', 10, 160,  '{"min_shifts_in_level": 3}', '{}'),
('trade', 5, 'Market Leader',    32000, 240, 12, '{"hunger": -5, "stress": 6, "social": 6}', 10, 220,  '{"min_shifts_in_level": 3}', '{}'),
('trade', 6, 'Distributor',      55000, 240, 12, '{"hunger": -5, "stress": 7, "social": 4}', 10, null, '{"min_shifts_in_level": 3}', '{}'),
-- Transport (5-hour shifts)
('transport', 1, 'Keke Rider',              3000, 300, 16, '{"hunger": -6, "hygiene": -6, "stress": 6}', 10, 40,   '{}', '{}'),
('transport', 2, 'Bus Driver',              6500, 300, 16, '{"hunger": -6, "hygiene": -6, "stress": 7}', 10, 70,   '{"min_shifts_in_level": 3}', '{}'),
('transport', 3, 'Park Supervisor',        14000, 300, 14, '{"hunger": -6, "hygiene": -4, "stress": 6, "social": 4}', 10, 110, '{"min_shifts_in_level": 3}', '{}'),
('transport', 4, 'Transport Company Owner',35000, 300, 12, '{"hunger": -5, "stress": 7, "social": 4}', 10, null, '{"min_shifts_in_level": 3}', '{}'),
-- Health (6-hour shifts)
('health', 1, 'Ward Attendant',           3000, 360, 16, '{"hunger": -7, "hygiene": -5, "stress": 5}', 10, 40,   '{}', '{}'),
('health', 2, 'Student Nurse',            5000, 360, 16, '{"hunger": -7, "hygiene": -5, "stress": 6}', 10, 70,   '{"min_shifts_in_level": 3}', '{}'),
('health', 3, 'Staff Nurse',             12000, 360, 17, '{"hunger": -7, "hygiene": -5, "stress": 7}', 10, 110,  '{"min_shifts_in_level": 3, "degree": true}', '{}'),
('health', 4, 'Senior Nurse',            20000, 360, 17, '{"hunger": -7, "hygiene": -5, "stress": 7}', 10, 160,  '{"min_shifts_in_level": 3, "degree": true}', '{}'),
('health', 5, 'Resident Doctor',         35000, 360, 18, '{"hunger": -7, "hygiene": -5, "stress": 9}', 10, 220,  '{"min_shifts_in_level": 3, "degree": true}', '{}'),
('health', 6, 'Consultant',              60000, 360, 18, '{"hunger": -7, "stress": 9}', 10, 300,  '{"min_shifts_in_level": 3, "degree": true}', '{}'),
('health', 7, 'Chief Medical Director', 100000, 360, 18, '{"hunger": -7, "stress": 10, "social": 4}', 10, null, '{"min_shifts_in_level": 3, "degree": true}', '{}'),
-- Education (4-hour sessions)
('education', 1, 'UNIBEN Student',      1000, 240, 12, '{"hunger": -5, "stress": 4, "social": 4}', 10, 50,   '{}', '{}'),
('education', 2, 'Graduate Assistant',  6000, 240, 12, '{"hunger": -5, "stress": 4}', 10, 70,   '{"min_shifts_in_level": 3}', '{"degree": true}'),
('education', 3, 'Lecturer II',        12000, 240, 12, '{"hunger": -5, "stress": 5}', 10, 110,  '{"min_shifts_in_level": 3}', '{}'),
('education', 4, 'Lecturer I',         18000, 240, 12, '{"hunger": -5, "stress": 5}', 10, 160,  '{"min_shifts_in_level": 3}', '{}'),
('education', 5, 'Senior Lecturer',    28000, 240, 12, '{"hunger": -5, "stress": 6}', 10, 220,  '{"min_shifts_in_level": 3}', '{}'),
('education', 6, 'Professor',          45000, 240, 12, '{"hunger": -5, "stress": 6}', 10, 300,  '{"min_shifts_in_level": 3}', '{}'),
('education', 7, 'Vice-Chancellor',    80000, 240, 13, '{"hunger": -5, "stress": 9, "social": 5}', 10, null, '{"min_shifts_in_level": 3}', '{}')
on conflict (track_id, level) do nothing;

-- ---------------------------------------------------------------------
-- 5. Config
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('career.max_shifts_per_game_day', '3', 'career', 'Shifts per game day',
 'How many shifts a Sim can work in one game day (all jobs together).', 'number', 1, 12),
('career.min_energy', '15', 'career', 'Min energy to start a shift',
 'Below this energy the Sim is too tired to work.', 'number', 0, 100),
('career.min_hunger', '10', 'career', 'Min hunger to start a shift',
 'Below this hunger bar the Sim is too hungry to work.', 'number', 0, 100),
('career.perf_min_pct', '40', 'career', 'Worst performance %',
 'Performance with every need at 0. Pay and XP are multiplied by performance.', 'percent', 0, 200),
('career.perf_max_pct', '120', 'career', 'Best performance %',
 'Performance with every need full and no stress (above 100 = bonus).', 'percent', 0, 300),
('career.perf_weight_hunger', '30', 'career', 'Performance weight: hunger',
 'How much the hunger bar counts towards performance (relative weight).', 'number', 0, 100),
('career.perf_weight_energy', '35', 'career', 'Performance weight: energy',
 'How much energy counts towards performance (relative weight).', 'number', 0, 100),
('career.perf_weight_hygiene', '15', 'career', 'Performance weight: hygiene',
 'How much hygiene counts towards performance (relative weight).', 'number', 0, 100),
('career.perf_weight_stress', '20', 'career', 'Performance weight: calm',
 'How much low stress counts towards performance (relative weight; uses 100 - stress).', 'number', 0, 100),
('career.pay_mult', '1', 'career', 'Pay multiplier (all jobs)',
 'Multiplies every shift''s pay. 1 = the level table.', 'number', 0, 10),
('career.xp_mult', '1', 'career', 'XP multiplier (all jobs)',
 'Multiplies every shift''s XP. 2 = promotions twice as fast.', 'number', 0, 10),
('career.degree_level', '2', 'career', 'Education level that counts as a degree',
 'Reaching this level on the Education track (ever) gives the degree that senior jobs ask for.', 'number', 1, 7),
('career.head_start_first_job_only', 'true', 'career', 'Origin head start on the first job only',
 'When on, origin.<tier>.career_head_start only applies to a Sim''s first ever hire.', 'bool', null, null),
('career.head_start_max_level', '3', 'career', 'Highest level a head start can give',
 'Caps level 1 + head start. Level requirements (laptop, degree) still apply.', 'number', 1, 10),
('career.rejoin_levels_lost', '1', 'career', 'Levels lost when rejoining a track',
 'Going back to a track you held before starts you at your best level there minus this (never below 1).', 'number', 0, 10)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 6. Helpers (internal)
-- ---------------------------------------------------------------------

-- Has the Sim got a degree? (best Education level >= career.degree_level)
create or replace function public.bl_has_degree(p_me public.profiles) returns boolean
language sql stable set search_path = public as $$
  select coalesce((p_me.career_best->>'education')::int, 0) >= bl_cfg('career.degree_level')::int
      or (p_me.job_id = 'education' and p_me.job_level >= bl_cfg('career.degree_level')::int);
$$;

-- Requirement checklist for a level: [{key, label, met}] (min_shifts_in_level only when p_promotion).
create or replace function public.bl_career_reqs(p_me public.profiles, p_req jsonb, p_promotion boolean) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_out jsonb := '[]'::jsonb;
  v_n   int;
  v_name text;
  k text; v text;
begin
  p_req := coalesce(p_req, '{}'::jsonb);
  if p_promotion and p_req ? 'min_shifts_in_level' then
    v_n := (p_req->>'min_shifts_in_level')::int;
    v_out := v_out || jsonb_build_array(jsonb_build_object('key', 'min_shifts_in_level',
      'label', v_n || ' shifts at your current level (' || least(p_me.job_shifts_in_level, v_n) || '/' || v_n || ')',
      'met', p_me.job_shifts_in_level >= v_n));
  end if;
  if p_req ? 'item' then
    select name into v_name from items where id = p_req->>'item';
    v_out := v_out || jsonb_build_array(jsonb_build_object('key', 'item', 'item', p_req->>'item',
      'label', 'Own a ' || lower(coalesce(v_name, p_req->>'item')),
      'met', exists (select 1 from inventory where user_id = p_me.id and item_id = p_req->>'item' and qty > 0)));
  end if;
  if coalesce((p_req->>'degree')::boolean, false) then
    v_out := v_out || jsonb_build_array(jsonb_build_object('key', 'degree',
      'label', 'A UNIBEN degree', 'met', bl_has_degree(p_me)));
  end if;
  if jsonb_typeof(p_req->'min_level_track') = 'object' then
    for k, v in select * from jsonb_each_text(p_req->'min_level_track') loop
      select name into v_name from career_tracks where id = k;
      v_out := v_out || jsonb_build_array(jsonb_build_object('key', 'min_level_track', 'track', k,
        'label', 'Level ' || v || ' in ' || coalesce(v_name, k),
        'met', greatest(coalesce((p_me.career_best->>k)::int, 0),
                        case when p_me.job_id = k then p_me.job_level else 0 end) >= v::int));
    end loop;
  end if;
  if coalesce((p_req->>'min_street_cred')::int, 0) > 0 then
    v_out := v_out || jsonb_build_array(jsonb_build_object('key', 'min_street_cred',
      'label', 'Street cred ' || (p_req->>'min_street_cred'),
      'met', p_me.street_cred >= (p_req->>'min_street_cred')::int));
  end if;
  return v_out;
end $$;

create or replace function public.bl_career_reqs_met(p_me public.profiles, p_req jsonb, p_promotion boolean) returns boolean
language sql stable set search_path = public as $$
  select coalesce(bool_and((r->>'met')::boolean), true) from jsonb_array_elements(bl_career_reqs(p_me, p_req, p_promotion)) r;
$$;

-- Performance % from the current needs (and trait work_performance), clamped to [perf_min, perf_max].
create or replace function public.bl_career_perf(p_me public.profiles) returns int
language plpgsql stable set search_path = public as $$
declare
  w_h numeric := bl_cfg('career.perf_weight_hunger');
  w_e numeric := bl_cfg('career.perf_weight_energy');
  w_y numeric := bl_cfg('career.perf_weight_hygiene');
  w_s numeric := bl_cfg('career.perf_weight_stress');
  v_min numeric := bl_cfg('career.perf_min_pct');
  v_max numeric := bl_cfg('career.perf_max_pct');
  v_score numeric;
  v_mult numeric := 1;
begin
  if w_h + w_e + w_y + w_s <= 0 then
    v_score := 100;
  else
    v_score := (w_h * p_me.hunger + w_e * p_me.energy + w_y * p_me.hygiene + w_s * (100 - p_me.stress))
               / (w_h + w_e + w_y + w_s);
  end if;
  select coalesce(exp(sum(ln(greatest((t.effects->>'work_performance')::numeric, 0.01)))), 1) into v_mult
    from traits t where t.id = any(coalesce(p_me.traits, '{}')) and t.effects ? 'work_performance';
  return round(least(v_max, greatest(v_min, (v_min + (v_max - v_min) * v_score / 100) * v_mult)))::int;
end $$;

-- Product of a trait effect key over the Sim's traits. p_path e.g. '{work_pay}' or '{skill_xp,coding}'.
create or replace function public.bl_trait_mult(p_me public.profiles, p_path text[]) returns numeric
language sql stable set search_path = public as $$
  select coalesce(exp(sum(ln(greatest((t.effects #>> p_path)::numeric, 0.01)))), 1)
    from traits t where t.id = any(coalesce(p_me.traits, '{}')) and (t.effects #>> p_path) is not null;
$$;

-- Entry level for a track: rejoin rule or 1 + head start, then walked down until the level's
-- requirements (minus min_shifts) are met.
create or replace function public.bl_career_entry_level(p_me public.profiles, p_track text) returns int
language plpgsql stable set search_path = public as $$
declare
  v_best int := coalesce((p_me.career_best->>p_track)::int, 0);
  v_lvl  int;
  v_top  int;
  v_req  jsonb;
begin
  select max(level) into v_top from career_levels where track_id = p_track;
  if v_top is null then return null; end if;
  if v_best > 0 then
    v_lvl := greatest(1, v_best - bl_cfg('career.rejoin_levels_lost')::int);
  elsif bl_cfg_bool('career.head_start_first_job_only') and p_me.career_best <> '{}'::jsonb then
    v_lvl := 1;
  else
    v_lvl := least(1 + greatest(0, coalesce(bl_origin_num(p_me.origin, 'career_head_start'), 0))::int,
                   bl_cfg('career.head_start_max_level')::int);
  end if;
  v_lvl := least(v_lvl, v_top);
  while v_lvl > 1 loop
    select requirements into v_req from career_levels where track_id = p_track and level = v_lvl;
    exit when v_req is not null and bl_career_reqs_met(p_me, v_req, false);
    v_lvl := v_lvl - 1;
  end loop;
  return v_lvl;
end $$;

-- Pays a finished shift (if any): money, XP, counters, auto-promotion. Returns null when there is
-- nothing to settle, else {pay, xp, perf, promoted?: {level, title}, blocked?: [labels]}.
create or replace function public.bl_settle_shift(p_uid uuid) returns jsonb
language plpgsql set search_path = public as $$
declare
  v_me    profiles;
  t       career_tracks;
  cur     career_levels;
  nxt     career_levels;
  v_xp    int;
  v_out   jsonb;
  v_reqs  jsonb;
  v_best  int;
begin
  select * into v_me from profiles where id = p_uid for update;
  if v_me.job_shift_ends_at is null or v_me.job_shift_ends_at > bl_now() then return null; end if;

  v_out := jsonb_build_object('pay', coalesce(v_me.job_shift_pay, 0), 'xp', coalesce(v_me.job_shift_xp, 0),
                              'perf', v_me.job_shift_perf);
  update profiles set job_shift_ends_at = null, job_shift_pay = null, job_shift_xp = null, job_shift_perf = null
   where id = p_uid;
  if coalesce(v_me.job_shift_pay, 0) > 0 then
    perform bl_add_money(p_uid, 'cash', v_me.job_shift_pay, 'salary',
                         jsonb_build_object('track', v_me.job_id, 'level', v_me.job_level, 'perf', v_me.job_shift_perf));
  end if;
  if v_me.job_id is null then return v_out; end if;

  select * into t from career_tracks where id = v_me.job_id;
  select * into cur from career_levels where track_id = v_me.job_id and level = v_me.job_level;
  v_xp := v_me.job_xp + coalesce(v_me.job_shift_xp, 0);
  if cur.xp_to_next is null then v_xp := least(v_xp, 1000000); end if;
  update profiles set job_xp = v_xp, job_shifts_in_level = job_shifts_in_level + 1,
                      job_total_shifts = job_total_shifts + 1
   where id = p_uid returning * into v_me;

  if cur.xp_to_next is not null and v_xp >= cur.xp_to_next then
    select * into nxt from career_levels where track_id = v_me.job_id and level = v_me.job_level + 1;
    if found then
      v_reqs := bl_career_reqs(v_me, nxt.requirements, true);
      if coalesce((select bool_and((r->>'met')::boolean) from jsonb_array_elements(v_reqs) r), true) then
        v_best := greatest(coalesce((v_me.career_best->>v_me.job_id)::int, 0), nxt.level);
        update profiles set job_level = nxt.level, job_xp = 0, job_shifts_in_level = 0,
                            career_best = career_best || jsonb_build_object(v_me.job_id, v_best)
         where id = p_uid;
        perform bl_event(p_uid, 'promoted', 'Promoted to ' || nxt.title || '!',
          'You are now ' || nxt.title || ' (' || t.name || ', level ' || nxt.level || '). New pay: '
          || bl_naira(nxt.pay_per_shift) || ' a shift.',
          jsonb_build_object('track', t.id, 'level', nxt.level, 'title', nxt.title, 'pay', nxt.pay_per_shift));
        v_out := v_out || jsonb_build_object('promoted', jsonb_build_object('level', nxt.level, 'title', nxt.title,
                                                                            'pay', nxt.pay_per_shift));
      else
        -- ready but blocked: hold XP at the bar
        update profiles set job_xp = cur.xp_to_next where id = p_uid;
        v_out := v_out || jsonb_build_object('blocked', jsonb_build_object('title', nxt.title,
          'missing', (select coalesce(jsonb_agg(r->'label'), '[]'::jsonb) from jsonb_array_elements(v_reqs) r
                      where not (r->>'met')::boolean)));
      end if;
    end if;
  end if;
  return v_out;
end $$;

-- Career block for get_my_state (pure read).
create or replace function public.bl_career_info(p_me public.profiles) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  t    career_tracks;
  cur  career_levels;
  nxt  career_levels;
  v_today int := (bl_game_clock()->>'day')::int;
  v_next jsonb := null;
  v_where jsonb;
begin
  if p_me.job_id is null then
    return jsonb_build_object('job', null, 'degree', bl_has_degree(p_me), 'best', p_me.career_best);
  end if;
  select * into t from career_tracks where id = p_me.job_id;
  select * into cur from career_levels where track_id = p_me.job_id and level = p_me.job_level;
  if t.id is null or cur.track_id is null then
    return jsonb_build_object('job', null, 'degree', bl_has_degree(p_me), 'best', p_me.career_best);
  end if;
  select * into nxt from career_levels where track_id = p_me.job_id and level = p_me.job_level + 1;
  if nxt.track_id is not null then
    v_next := jsonb_build_object('level', nxt.level, 'title', nxt.title, 'pay_per_shift', nxt.pay_per_shift,
                                 'requirements', bl_career_reqs(p_me, nxt.requirements, true));
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name) order by array_position(t.location_ids, l.id)), '[]'::jsonb)
    into v_where from locations l where l.id = any(t.location_ids);
  return jsonb_build_object(
    'degree', bl_has_degree(p_me),
    'best', p_me.career_best,
    'job', jsonb_build_object(
      'track', t.id, 'track_name', t.name, 'emoji', t.emoji, 'skill', t.skill,
      'level', cur.level, 'title', cur.title, 'top_level', (select max(level) from career_levels where track_id = t.id),
      'pay_per_shift', cur.pay_per_shift, 'shift_game_minutes', cur.shift_game_minutes,
      'energy_cost', cur.energy_cost, 'xp', p_me.job_xp, 'xp_to_next', cur.xp_to_next,
      'shifts_in_level', p_me.job_shifts_in_level, 'total_shifts', p_me.job_total_shifts,
      'shifts_today', case when p_me.job_shift_day = v_today then p_me.job_shifts_today else 0 end,
      'max_shifts_per_day', bl_cfg('career.max_shifts_per_game_day')::int,
      'perf_now', bl_career_perf(p_me),
      -- what a shift started now would pay (same formula as work_shift)
      'pay_now', (round(cur.pay_per_shift * bl_career_perf(p_me) / 100.0 * bl_trait_mult(p_me, '{work_pay}')
                        * bl_cfg('career.pay_mult') / 10.0) * 10)::bigint,
      'started_at', p_me.job_started_at,
      'locations', v_where,
      'next', v_next,
      'pending', case when p_me.job_shift_ends_at is null then null
                      else jsonb_build_object('ends_at', p_me.job_shift_ends_at, 'pay', p_me.job_shift_pay,
                                              'xp', p_me.job_shift_xp, 'perf', p_me.job_shift_perf) end));
end $$;

-- ---------------------------------------------------------------------
-- 7. RPCs
-- ---------------------------------------------------------------------

-- Jobs app / Work panel catalog: every active track with its places and levels, plus what the
-- caller would start at (entry level after head start and requirements). Read-only.
create or replace function public.jobs_catalog() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_me  profiles;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  return jsonb_build_object(
    'current', v_me.job_id,
    'degree', bl_has_degree(v_me),
    'tracks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'emoji', t.emoji, 'category', t.category, 'description', t.description,
        'skill', t.skill,
        'locations', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name)
                                                order by array_position(t.location_ids, l.id)), '[]'::jsonb)
                        from locations l where l.id = any(t.location_ids)),
        'entry_level', bl_career_entry_level(v_me, t.id),
        'levels', (select coalesce(jsonb_agg(jsonb_build_object(
                      'level', cl.level, 'title', cl.title, 'pay_per_shift', cl.pay_per_shift,
                      'shift_game_minutes', cl.shift_game_minutes, 'xp_to_next', cl.xp_to_next,
                      'requirements', bl_career_reqs(v_me, cl.requirements, false)) order by cl.level), '[]'::jsonb)
                     from career_levels cl where cl.track_id = t.id))
        order by t.sort, t.id)
      from career_tracks t where t.active), '[]'::jsonb));
end $$;

-- Apply for a track. Works from anywhere (the phone's Jobs app) and replaces the current job.
create or replace function public.job_apply(p_track text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  t       career_tracks;
  v_lvl   int;
  cl      career_levels;
  v_old   text;
  v_settled jsonb;
begin
  v_settled := bl_settle_shift(v_me.id);
  select * into v_me from profiles where id = v_me.id;
  if v_me.job_shift_ends_at is not null then
    raise exception 'Finish your current shift first.' using errcode = 'P0001', hint = 'on_shift';
  end if;
  select * into t from career_tracks where id = p_track and active;
  if not found then
    raise exception 'That job isn''t hiring right now.' using errcode = 'P0001', hint = 'bad_track';
  end if;
  if v_me.job_id = t.id then
    raise exception 'You already work in %.', t.name using errcode = 'P0001', hint = 'already_hired';
  end if;
  v_lvl := bl_career_entry_level(v_me, t.id);
  if v_lvl is null then
    raise exception 'That job isn''t hiring right now.' using errcode = 'P0001', hint = 'bad_track';
  end if;
  select * into cl from career_levels where track_id = t.id and level = v_lvl;
  select title into v_old from career_levels where track_id = v_me.job_id and level = v_me.job_level;

  update profiles set job_id = t.id, job_level = v_lvl, job_xp = 0, job_shifts_in_level = 0,
                      job_started_at = bl_now(),
                      career_best = career_best || jsonb_build_object(t.id,
                                      greatest(coalesce((career_best->>t.id)::int, 0), v_lvl))
   where id = v_me.id;
  perform bl_event(v_me.id, 'hired', 'New job: ' || cl.title,
    'You start as ' || cl.title || ' (' || t.name || ', level ' || v_lvl || '). ' || bl_naira(cl.pay_per_shift)
    || ' a shift. Work at ' || (select string_agg(name, ', ' order by array_position(t.location_ids, id))
                                from locations where id = any(t.location_ids)) || '.',
    jsonb_build_object('track', t.id, 'level', v_lvl));
  return jsonb_build_object(
    'message', case when v_old is not null then 'You left your job as ' || v_old || '. ' else '' end
               || 'You''re hired as ' || cl.title || '! ' || bl_naira(cl.pay_per_shift) || ' a shift.',
    'track', t.id, 'level', v_lvl, 'title', cl.title, 'settled', v_settled);
end $$;

create or replace function public.job_quit() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_title text;
begin
  perform bl_settle_shift(v_me.id);
  select * into v_me from profiles where id = v_me.id;
  if v_me.job_id is null then
    raise exception 'You don''t have a job right now.' using errcode = 'P0001', hint = 'no_job';
  end if;
  if v_me.job_shift_ends_at is not null then
    raise exception 'Finish your current shift first.' using errcode = 'P0001', hint = 'on_shift';
  end if;
  select title into v_title from career_levels where track_id = v_me.job_id and level = v_me.job_level;
  update profiles set job_id = null, job_level = 1, job_xp = 0, job_shifts_in_level = 0, job_started_at = null
   where id = v_me.id;
  return jsonb_build_object('message', 'You resigned as ' || coalesce(v_title, 'staff')
                                       || '. You can apply for another job any time.');
end $$;

-- Start a shift at one of the track's places. Needs effects apply now; pay + XP arrive when the
-- shift ends (work_finish). Busy for the shift with label "Working: <title>".
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

  perform bl_adjust_needs(v_me.id, coalesce(cl.effects, '{}'::jsonb) || jsonb_build_object('energy',
                          -cl.energy_cost + coalesce((cl.effects->>'energy')::numeric, 0)));
  v_until := bl_set_busy(v_me.id, cl.shift_game_minutes, 'Working: ' || cl.title);
  update profiles set job_shift_ends_at = v_until, job_shift_pay = v_pay, job_shift_xp = v_xp, job_shift_perf = v_perf,
                      job_shift_day = v_today, job_shifts_today = v_done + 1
   where id = v_me.id;
  return jsonb_build_object(
    'message', 'Shift started as ' || cl.title || '. Performance ' || v_perf || '%: you''ll earn '
               || bl_naira(v_pay) || ' when it ends.',
    'busy_until', v_until, 'pay', v_pay, 'xp', v_xp, 'perf', v_perf, 'settled', v_settled);
end $$;

-- Collect a finished shift (the client calls it when the busy timer ends; also settled by the next
-- work_shift / job_apply / job_quit). Returns {message, pay, xp, perf, promoted?, blocked?} or
-- {message: null} when there is nothing to collect.
create or replace function public.work_finish() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me  profiles := bl_me();
  v_r   jsonb;
  v_msg text;
begin
  if v_me.job_shift_ends_at is not null and v_me.job_shift_ends_at > bl_now() then
    raise exception 'Your shift isn''t over yet. About % sec left.',
      ceil(extract(epoch from v_me.job_shift_ends_at - bl_now())) using errcode = 'P0001', hint = 'on_shift';
  end if;
  v_r := bl_settle_shift(v_me.id);
  if v_r is null then return jsonb_build_object('message', null); end if;
  v_msg := 'Shift done! You earned ' || bl_naira((v_r->>'pay')::bigint) || ' (performance ' || (v_r->>'perf') || '%).';
  if v_r ? 'promoted' then
    v_msg := v_msg || ' Promoted to ' || (v_r->'promoted'->>'title') || '!';
  elsif v_r ? 'blocked' then
    v_msg := v_msg || ' You''re ready for ' || (v_r->'blocked'->>'title') || ', but you still need: '
             || (select string_agg(lower(x #>> '{}'), ', ') from jsonb_array_elements(v_r->'blocked'->'missing') x) || '.';
  end if;
  return v_r || jsonb_build_object('message', v_msg);
end $$;

-- Same as R3a plus the `career` block (keeps origin, creator, rent). Still read-mostly: the only
-- write is the throttled last_seen.
create or replace function public.get_my_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_now   timestamptz := bl_now();
  v_me    profiles;
  v_clock jsonb;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v_me.banned then
    raise exception 'This account has been banned. If this is a mistake, contact the admin.' using errcode = 'P0001', hint = 'banned';
  end if;
  if v_me.last_seen is null
     or v_me.last_seen < v_now - make_interval(secs => bl_cfg('time.last_seen_throttle_real_seconds')::double precision) then
    update profiles set last_seen = v_now where id = v_uid returning * into v_me;
  end if;
  v_me := bl_decay_row(v_me, v_now);
  v_clock := bl_game_clock(v_now);
  return jsonb_build_object(
    'profile', to_jsonb(v_me) - array['banned','needs_updated_at','last_seen',
                                      'travel_to','travel_mode','travel_started_at','travel_arrives_at'],
    'clock', v_clock,
    'location', (select to_jsonb(l) from locations l where l.id = v_me.location_id),
    'travel', case when v_me.travel_to is null then null
                   else jsonb_build_object('to', v_me.travel_to, 'mode', v_me.travel_mode,
                                           'started_at', v_me.travel_started_at,
                                           'arrives_at', v_me.travel_arrives_at) end,
    'origin', bl_origin_info(v_me.origin, v_me.allowance_claimed_day, (v_clock->>'day')::bigint),
    'creator', jsonb_build_object(
      'home_chosen', v_me.home_chosen,
      'traits', to_jsonb(v_me.traits),
      'dream', v_me.dream,
      'start_home', v_me.start_home,
      'homes', case when v_me.home_chosen then null else bl_homes_for(v_me.origin) end),
    'rent', jsonb_build_object(
      'weekly', v_me.weekly_rent,
      'due_at', v_me.rent_due_at,
      'owed', v_me.rent_owed,
      'enabled', bl_cfg_bool('rent.enabled')),
    'career', bl_career_info(v_me),
    'server_time', v_now
  );
end $$;

-- ---------------------------------------------------------------------
-- 8. Privileges
-- ---------------------------------------------------------------------
revoke execute on function public.bl_has_degree(public.profiles)                     from public, anon, authenticated;
revoke execute on function public.bl_career_reqs(public.profiles, jsonb, boolean)     from public, anon, authenticated;
revoke execute on function public.bl_career_reqs_met(public.profiles, jsonb, boolean) from public, anon, authenticated;
revoke execute on function public.bl_career_perf(public.profiles)                    from public, anon, authenticated;
revoke execute on function public.bl_trait_mult(public.profiles, text[])             from public, anon, authenticated;
revoke execute on function public.bl_career_entry_level(public.profiles, text)       from public, anon, authenticated;
revoke execute on function public.bl_settle_shift(uuid)                              from public, anon, authenticated;
revoke execute on function public.bl_career_info(public.profiles)                    from public, anon, authenticated;

revoke execute on function public.jobs_catalog()   from public, anon;
revoke execute on function public.job_apply(text)  from public, anon;
revoke execute on function public.job_quit()       from public, anon;
revoke execute on function public.work_shift()     from public, anon;
revoke execute on function public.work_finish()    from public, anon;
grant execute on function public.jobs_catalog()    to authenticated;
grant execute on function public.job_apply(text)   to authenticated;
grant execute on function public.job_quit()        to authenticated;
grant execute on function public.work_shift()      to authenticated;
grant execute on function public.work_finish()     to authenticated;
grant execute on function public.get_my_state()    to authenticated;
