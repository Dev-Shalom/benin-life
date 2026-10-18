-- R3 Skills & progression (docs/SKILLS.md, docs/REVIEW_PLAN.md step R3). Inspired by LagosLife.
-- * Ten skills (Yahoo, Driving, Cooking, Music, Teaching, Fishing, Mechanic, Business, Fitness, Charisma), XP per player in
--   player_skills, levels 1-10 from one admin-editable cumulative XP curve (skill_curve). The level is always derived from the XP
--   (never stored), so an edited curve applies to everybody at once.
-- * skill_sources: the admin table that says which action gives how much XP in which skill: hustle runs, Yahoo jobs, career
--   shifts (by track) and activities. Existing trait multipliers (traits.effects.skill_xp.<key>) are respected through
--   skills.trait_keys (the best matching trait multiplier applies). XP is server-side only: the client never sends XP.
-- * Effects (all editable in Content -> Skills): hustle pay +X % per level above 1 (default 5, the hustle's main skill = the
--   source with the most XP), Yahoo level lowers the EFCC caught chance by Y % relative per level above 1 (default 4, capped at
--   36 %, so level 10 = -36 %). Applied inside bl_yahoo_resolve.
-- * Gates: hustles.min_skill_level / yahoo_jobs.min_skill_level (default 1 = open). Gated by default: Yahoo "Big job" Yahoo lvl 3,
--   "Engine job" Mechanic lvl 2. The DJ set stays open (no controller = warm-up pay, as before).
-- * skills.enabled = master switch (off: no XP, no gates, no effects).
-- * Live functions are patched with guarded replacements (raise when a marker is missing, skip when already applied), so grants stay.
-- Idempotent and safe on a non-empty DB: tables "if not exists", seeds "on conflict do nothing", columns "if not exists".

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('skills.enabled', 'true', 'skills', 'Skills on',
 'R3: players earn skill XP from hustles, Yahoo jobs, career shifts and activities; skill levels boost hustle pay, cut the EFCC chance and unlock gated jobs. Off = no XP, no gates, no effects.', 'bool', null, null),
('skills.xp_mult', '1', 'skills', 'XP multiplier (everyone)',
 'R3: every skill XP award is multiplied by this (1 = normal, 2 = double XP weekend). Trait multipliers (Gym Rat, Musical ...) apply on top.', 'number', 0, 100),
('skills.caught_skill', '"yahoo"', 'skills', 'Skill that lowers the EFCC chance',
 'R3: the skill id (Content -> Skills) whose level cuts the Yahoo EFCC caught chance. The size of the cut is that skill''s "EFCC cut % per level" and cap.', 'text', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.skills (
  id                   text primary key,
  name                 text not null,
  icon                 text not null default '⭐',
  blurb                text not null default '',
  train_text           text not null default '',
  -- traits.effects.skill_xp keys that speed this skill up (the best multiplier among them applies)
  trait_keys           text[] not null default '{}',
  -- hustle pay: + this % for every level above 1 on hustles whose main skill this is
  pay_pct_per_level    numeric not null default 5 check (pay_pct_per_level >= 0 and pay_pct_per_level <= 100),
  -- Yahoo: the EFCC caught chance is cut by this % (relative) per level above 1 ...
  caught_pct_per_level numeric not null default 0 check (caught_pct_per_level >= 0 and caught_pct_per_level <= 100),
  -- ... but never by more than this %
  caught_cap_pct       numeric not null default 0 check (caught_cap_pct >= 0 and caught_cap_pct <= 100),
  sort                 int not null default 0,
  active               boolean not null default true
);

-- cumulative XP needed to reach each level (level 1 = 0). Max level = the highest row.
create table if not exists public.skill_curve (
  level int primary key check (level >= 1 and level <= 50),
  xp    int not null check (xp >= 0)
);

create table if not exists public.skill_sources (
  id       text primary key,
  kind     text not null check (kind in ('hustle', 'yahoo', 'career', 'activity')),
  ref      text not null,
  skill_id text not null references public.skills (id) on update cascade on delete cascade,
  xp       numeric not null default 5 check (xp >= 0 and xp <= 100000),
  note     text not null default '',
  active   boolean not null default true,
  unique (kind, ref, skill_id)
);
create index if not exists skill_sources_ref_idx on public.skill_sources (kind, ref) where active;

create table if not exists public.player_skills (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  skill_id   text not null references public.skills (id) on update cascade on delete cascade,
  xp         int not null default 0 check (xp >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, skill_id)
);

alter table public.hustles add column if not exists min_skill_level int not null default 1 check (min_skill_level >= 1 and min_skill_level <= 50);
alter table public.yahoo_jobs add column if not exists min_skill_level int not null default 1 check (min_skill_level >= 1 and min_skill_level <= 50);

alter table public.skills enable row level security;
alter table public.skill_curve enable row level security;
alter table public.skill_sources enable row level security;
alter table public.player_skills enable row level security;
revoke all on table public.skills, public.skill_curve, public.skill_sources, public.player_skills from public, anon, authenticated;
grant select on table public.skills, public.skill_curve, public.skill_sources, public.player_skills to authenticated;
drop policy if exists skills_read on public.skills;
create policy skills_read on public.skills for select to authenticated using (true);
drop policy if exists skill_curve_read on public.skill_curve;
create policy skill_curve_read on public.skill_curve for select to authenticated using (true);
drop policy if exists skill_sources_read on public.skill_sources;
create policy skill_sources_read on public.skill_sources for select to authenticated using (true);
drop policy if exists player_skills_own on public.player_skills;
create policy player_skills_own on public.player_skills for select to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------
-- 3. Seeds
-- ---------------------------------------------------------------------------------------------
insert into public.skills (id, name, icon, blurb, train_text, trait_keys, pay_pct_per_level, caught_pct_per_level, caught_cap_pct, sort) values
('yahoo', 'Yahoo', '💻', 'Hustle and IT sense. The higher you go, the less EFCC dey catch you, and the big jobs open up.',
 'Do Yahoo jobs in the Yahoo app (home with MiFi, or a desk at the Ugbowo Wi-Fi Joint). Tech career shifts and side projects help too.',
 '{hustle,coding}', 0, 4, 36, 10),
('driving', 'Driving', '🚗', 'Road sense. Better Bolt drivers collect more per ride.',
 'Do Bolt shifts from any public place with your own car. Transport career shifts count too.', '{hustle}', 5, 0, 0, 20),
('cooking', 'Cooking', '🍲', 'Pots, pepper and timing. Food sellers earn more as the hand gets sweeter.',
 'Cook at home (rice and stew) and sell jollof, puff-puff or fried yam at the Oba Market stall.', '{cooking}', 5, 0, 0, 30),
('music', 'Music', '🎧', 'DJ and MC craft. The crowd pays more when you read the room.',
 'Play DJ sets and MC the night at any open club.', '{music,dance}', 5, 0, 0, 40),
('teaching', 'Teaching', '🎓', 'Explaining things well. Tutors earn more as students improve.',
 'Tutor a student at UNIBEN, sit in on lectures, and do Education career shifts.', '{}', 5, 0, 0, 50),
('fishing', 'Fishing', '🎣', 'Patience and a good hook. Level up for a bigger, more reliable catch.',
 'Go fishing at the Ikpoba River Bank (rod and bait needed).', '{}', 5, 0, 0, 60),
('mechanic', 'Mechanic', '🔧', 'Engines do not scare you. Bigger repair jobs open up.',
 'Quick fixes and engine jobs at the Sapele Rd Mechanic Village. Trade career shifts help.', '{hustle}', 5, 0, 0, 70),
('business', 'Business', '💼', 'Margins, customers, credit. Traders and PoS agents earn more.',
 'PoS agent batches, selling food, Trade and PoS career shifts, and market price checks.', '{hustle}', 5, 0, 0, 80),
('fitness', 'Fitness', '💪', 'Stamina and strength. A fit body is the best investment.',
 'Jog round the stadium track and lead the chant on match days.', '{fitness}', 5, 0, 0, 90),
('charisma', 'Charisma', '😎', 'Gift of the gab. People like you, and the club knows your name.',
 'Socialise at the club, gist with the guys, and MC the night.', '{charisma}', 5, 0, 0, 100)
on conflict (id) do nothing;

insert into public.skill_curve (level, xp) values
(1, 0), (2, 40), (3, 120), (4, 260), (5, 460), (6, 740), (7, 1120), (8, 1640), (9, 2340), (10, 3300)
on conflict (level) do nothing;

insert into public.skill_sources (id, kind, ref, skill_id, xp, note) values
-- hustles
('hustle:bolt_shift:driving',        'hustle', 'bolt_shift',     'driving',  8,  'Bolt driver shift'),
('hustle:pos_agent:business',        'hustle', 'pos_agent',      'business', 6,  'PoS agent batch'),
('hustle:vend_jollof:cooking',       'hustle', 'vend_jollof',    'cooking',  7,  'Sell jollof rice'),
('hustle:vend_jollof:business',      'hustle', 'vend_jollof',    'business', 3,  'Sell jollof rice'),
('hustle:vend_puff:cooking',         'hustle', 'vend_puff',      'cooking',  4,  'Sell puff-puff'),
('hustle:vend_puff:business',        'hustle', 'vend_puff',      'business', 2,  'Sell puff-puff'),
('hustle:vend_fried_yam:cooking',    'hustle', 'vend_fried_yam', 'cooking',  5,  'Sell fried yam and egg'),
('hustle:vend_fried_yam:business',   'hustle', 'vend_fried_yam', 'business', 3,  'Sell fried yam and egg'),
('hustle:dj_set:music',              'hustle', 'dj_set',         'music',    12, 'Play a DJ set'),
('hustle:dj_set:charisma',           'hustle', 'dj_set',         'charisma', 3,  'Play a DJ set'),
('hustle:mc_gig:music',              'hustle', 'mc_gig',         'music',    8,  'MC the night'),
('hustle:mc_gig:charisma',           'hustle', 'mc_gig',         'charisma', 5,  'MC the night'),
('hustle:tutor_session:teaching',    'hustle', 'tutor_session',  'teaching', 8,  'Tutor a student'),
('hustle:fish_cast:fishing',         'hustle', 'fish_cast',      'fishing',  6,  'Go fishing'),
('hustle:mech_quick:mechanic',       'hustle', 'mech_quick',     'mechanic', 6,  'Quick fix'),
('hustle:mech_engine:mechanic',      'hustle', 'mech_engine',    'mechanic', 12, 'Engine job'),
-- Yahoo jobs
('yahoo:chat_client:yahoo',          'yahoo',  'chat_client',    'yahoo',    8,  'Chat a client'),
('yahoo:romance_job:yahoo',          'yahoo',  'romance_job',    'yahoo',    15, 'Romance job'),
('yahoo:big_job:yahoo',              'yahoo',  'big_job',        'yahoo',    30, 'Big job'),
('yahoo:cash_out:yahoo',             'yahoo',  'cash_out',       'yahoo',    4,  'Cash out'),
-- career shifts (by track)
('career:tech:yahoo',                'career', 'tech',           'yahoo',    6,  'Tech career shift (IT)'),
('career:pos:business',              'career', 'pos',            'business', 6,  'PoS & Fintech career shift'),
('career:trade:business',            'career', 'trade',          'business', 6,  'Trade career shift'),
('career:transport:driving',         'career', 'transport',      'driving',  6,  'Transport career shift'),
('career:health:charisma',           'career', 'health',         'charisma', 5,  'Health career shift (bedside manner)'),
('career:education:teaching',        'career', 'education',      'teaching', 6,  'Education career shift'),
-- activities
('activity:cook_home:cooking',       'activity', 'cook_home',      'cooking',  4, 'Cook rice and stew at home'),
('activity:stadium_jog:fitness',     'activity', 'stadium_jog',    'fitness',  4, 'Jog round the track'),
('activity:lead_the_chant:fitness',  'activity', 'lead_the_chant', 'fitness',  2, 'Lead the chant'),
('activity:club_night:charisma',     'activity', 'club_night',     'charisma', 3, 'Night out at the club'),
('activity:club_dance:charisma',     'activity', 'club_dance',     'charisma', 2, 'Dance to the DJ'),
('activity:lounge_chill:charisma',   'activity', 'lounge_chill',   'charisma', 2, 'Chapman and small chops'),
('activity:vip_table:charisma',      'activity', 'vip_table',      'charisma', 4, 'VIP table'),
('activity:hype_shoutout:charisma',  'activity', 'hype_shoutout',  'charisma', 2, 'Hype man shout-out'),
('activity:gist_joint:charisma',     'activity', 'gist_joint',     'charisma', 1, 'Gist with the guys'),
('activity:night_stroll:charisma',   'activity', 'night_stroll',   'charisma', 1, 'Late-night stroll with the boys'),
('activity:attend_lecture:teaching', 'activity', 'attend_lecture', 'teaching', 2, 'Sit in on a lecture'),
('activity:library_read:teaching',   'activity', 'library_read',   'teaching', 2, 'Read in the library'),
('activity:side_project:yahoo',      'activity', 'side_project',   'yahoo',    3, 'Hack on a side project (IT)'),
('activity:tech_meetup:yahoo',       'activity', 'tech_meetup',    'yahoo',    2, 'Join the evening tech meetup'),
('activity:market_stroll:business',  'activity', 'market_stroll',  'business', 1, 'Market stroll and price check')
on conflict (id) do nothing;

-- gated by default (level 1 = open): the Big job, the Engine job. The DJ set stays open.
update public.hustles set min_skill_level = 2 where id = 'mech_engine' and min_skill_level = 1;
update public.yahoo_jobs set min_skill_level = 3 where id = 'big_job' and min_skill_level = 1;

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers (revoked from clients at the end)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_skill_on() returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = 'skills.enabled'), true);
$$;

create or replace function public.bl_skill_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_skill_max_level() returns int
language sql stable set search_path = public as $$
  select coalesce((select max(level) from skill_curve), 1);
$$;

create or replace function public.bl_skill_level_for_xp(p_xp numeric) returns int
language sql stable set search_path = public as $$
  select coalesce((select max(level) from skill_curve where xp <= coalesce(p_xp, 0)), 1);
$$;

create or replace function public.bl_skill_xp_for_level(p_level int) returns int
language sql stable set search_path = public as $$
  select coalesce((select xp from skill_curve where level = p_level), 0);
$$;

create or replace function public.bl_skill_xp(p_uid uuid, p_skill text) returns int
language sql stable set search_path = public as $$
  select coalesce((select xp from player_skills where user_id = p_uid and skill_id = p_skill), 0);
$$;

-- the level the effects use (1 when skills are switched off)
create or replace function public.bl_skill_level(p_uid uuid, p_skill text) returns int
language sql stable set search_path = public as $$
  select case when bl_skill_on() then bl_skill_level_for_xp(bl_skill_xp(p_uid, p_skill)) else 1 end;
$$;

-- the main skill of a hustle / Yahoo job / ...: the active source with the most XP
create or replace function public.bl_skill_main(p_kind text, p_ref text) returns text
language sql stable set search_path = public as $$
  select s.skill_id from skill_sources s join skills k on k.id = s.skill_id
   where s.active and k.active and s.kind = p_kind and s.ref = p_ref
   order by s.xp desc, s.skill_id limit 1;
$$;

-- null = fine; otherwise {hint, message, short, skill, need, have}
create or replace function public.bl_skill_gate(p_uid uuid, p_kind text, p_ref text, p_min int) returns jsonb
language plpgsql stable set search_path = public as $$
declare v_skill text; k skills; v_lvl int;
begin
  if coalesce(p_min, 1) <= 1 or not bl_skill_on() then return null; end if;
  v_skill := bl_skill_main(p_kind, p_ref);
  if v_skill is null then return null; end if;
  select * into k from skills where id = v_skill;
  v_lvl := bl_skill_level(p_uid, v_skill);
  if v_lvl >= p_min then return null; end if;
  return jsonb_build_object('hint', 'skill_level',
    'message', 'Needs ' || k.name || ' level ' || p_min || ' (you are level ' || v_lvl || '). ' || coalesce(nullif(k.train_text, ''), 'Train the skill to unlock am.'),
    'short', 'Needs ' || k.name || ' lvl ' || p_min, 'skill', k.id, 'need', p_min, 'have', v_lvl);
end $$;

-- pay multiplier from the main skill of a hustle (level 1 = x1)
create or replace function public.bl_skill_pay_mult(p_uid uuid, p_kind text, p_ref text) returns numeric
language plpgsql stable set search_path = public as $$
declare v_skill text; k skills;
begin
  if not bl_skill_on() then return 1; end if;
  v_skill := bl_skill_main(p_kind, p_ref);
  if v_skill is null then return 1; end if;
  select * into k from skills where id = v_skill;
  return 1 + greatest(0, bl_skill_level(p_uid, v_skill) - 1) * k.pay_pct_per_level / 100.0;
end $$;

-- the relative EFCC cut (%) the player has now
create or replace function public.bl_skill_caught_cut(p_uid uuid) returns numeric
language plpgsql stable set search_path = public as $$
declare k skills; v_id text := coalesce((select value #>> '{}' from game_config where key = 'skills.caught_skill'), 'yahoo');
begin
  if not bl_skill_on() then return 0; end if;
  select * into k from skills where id = v_id;
  if not found then return 0; end if;
  return greatest(0, least(100, least(k.caught_cap_pct, greatest(0, bl_skill_level(p_uid, k.id) - 1) * k.caught_pct_per_level)));
end $$;

create or replace function public.bl_skill_caught_pct(p_uid uuid, p_pct numeric) returns numeric
language sql stable set search_path = public as $$
  select greatest(0, least(100, coalesce(p_pct, 0) * (1 - bl_skill_caught_cut(p_uid) / 100.0)));
$$;

-- small card for hustle / Yahoo job JSON: null when the thing has no skill
create or replace function public.bl_skill_card(p_uid uuid, p_kind text, p_ref text, p_min int) returns jsonb
language plpgsql stable set search_path = public as $$
declare v_skill text; k skills; v_lvl int; v_boost numeric;
begin
  if not bl_skill_on() then return null; end if;
  v_skill := bl_skill_main(p_kind, p_ref);
  if v_skill is null then return null; end if;
  select * into k from skills where id = v_skill;
  v_lvl := bl_skill_level(p_uid, v_skill);
  v_boost := round((case when p_kind = 'hustle' then bl_skill_pay_mult(p_uid, p_kind, p_ref) - 1 else 0 end) * 100, 1);
  return jsonb_build_object('skill', k.id, 'name', k.name, 'icon', k.icon, 'level', v_lvl,
                            'min_level', greatest(1, coalesce(p_min, 1)), 'ok', v_lvl >= greatest(1, coalesce(p_min, 1)),
                            'pay_boost_pct', v_boost,
                            'caught_cut_pct', case when k.id = coalesce((select value #>> '{}' from game_config where key = 'skills.caught_skill'), 'yahoo')
                                                   then bl_skill_caught_cut(p_uid) end);
end $$;

-- what a level gives (text lines): newly open jobs and the effects at that level
create or replace function public.bl_skill_unlocks(p_skill text, p_level int) returns text[]
language plpgsql stable set search_path = public as $$
declare k skills; v_out text[] := '{}'; v_cut numeric; v_names text[];
begin
  select * into k from skills where id = p_skill;
  if not found then return v_out; end if;
  select coalesce(array_agg(n order by n), '{}') into v_names from (
    select h.name n from hustles h where h.active and h.min_skill_level = p_level and bl_skill_main('hustle', h.id) = p_skill
    union all
    select j.name from yahoo_jobs j where j.active and j.min_skill_level = p_level and bl_skill_main('yahoo', j.id) = p_skill) x;
  if cardinality(v_names) > 0 then v_out := v_out || ('Unlocks: ' || array_to_string(v_names, ', ')); end if;
  if p_level > 1 and k.pay_pct_per_level > 0 and exists (select 1 from hustles h where h.active and bl_skill_main('hustle', h.id) = p_skill) then
    v_out := v_out || ('+' || trim(trailing '.' from to_char(k.pay_pct_per_level * (p_level - 1), 'FM990.99')) || '% pay on ' || k.name || ' hustles');
  end if;
  if p_level > 1 and k.caught_pct_per_level > 0 then
    v_cut := least(k.caught_cap_pct, k.caught_pct_per_level * (p_level - 1));
    v_out := v_out || ('EFCC catch chance -' || trim(trailing '.' from to_char(v_cut, 'FM990.99')) || '%');
  end if;
  return v_out;
end $$;

-- the one place XP is given. Returns [{skill, name, icon, gain, xp, level, up}]; a level-up writes a 'skill_up' event (toast + confetti)
create or replace function public.bl_skill_award(p_uid uuid, p_kind text, p_ref text) returns jsonb
language plpgsql set search_path = public as $$
declare
  r      record;
  v_me   profiles;
  v_mult numeric;
  v_gain int;
  v_xp   int;
  v_old  int;
  v_new  int;
  v_ups  text[];
  v_out  jsonb := '[]'::jsonb;
begin
  if not bl_skill_on() then return v_out; end if;
  select * into v_me from profiles where id = p_uid;
  if not found then return v_out; end if;
  for r in select s.skill_id, s.xp as base, k.name, k.icon, k.trait_keys
             from skill_sources s join skills k on k.id = s.skill_id
            where s.active and k.active and s.kind = p_kind and s.ref = p_ref
            order by k.sort, s.skill_id loop
    v_mult := coalesce((select max(bl_trait_mult(v_me, array['skill_xp', tk])) from unnest(r.trait_keys) tk), 1);
    v_gain := case when r.base <= 0 then 0 else greatest(1, round(r.base * v_mult * bl_skill_num('skills.xp_mult', 1))::int) end;
    if v_gain <= 0 then continue; end if;
    v_old := bl_skill_level_for_xp(bl_skill_xp(p_uid, r.skill_id));
    insert into player_skills (user_id, skill_id, xp, updated_at) values (p_uid, r.skill_id, least(v_gain, 1000000000), bl_now())
    on conflict (user_id, skill_id) do update set xp = least(player_skills.xp::bigint + v_gain, 1000000000)::int, updated_at = bl_now()
    returning xp into v_xp;
    v_new := bl_skill_level_for_xp(v_xp);
    if v_new > v_old then
      v_ups := bl_skill_unlocks(r.skill_id, v_new);
      perform bl_event(p_uid, 'skill_up', r.icon || ' ' || r.name || ' level ' || v_new || '!',
        case when cardinality(v_ups) > 0 then array_to_string(v_ups, ' · ') else 'Keep training, e dey show.' end,
        jsonb_build_object('skill', r.skill_id, 'name', r.name, 'icon', r.icon, 'level', v_new, 'unlocks', to_jsonb(v_ups)));
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('skill', r.skill_id, 'name', r.name, 'icon', r.icon,
                                                           'gain', v_gain, 'xp', v_xp, 'level', v_new, 'up', v_new > v_old));
  end loop;
  return v_out;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Player RPC: skills_status() (read-only)
-- ---------------------------------------------------------------------------------------------
create or replace function public.skills_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_max int := bl_skill_max_level();
begin
  return jsonb_build_object(
    'enabled', bl_skill_on(),
    'max_level', v_max,
    'curve', coalesce((select jsonb_agg(jsonb_build_object('level', level, 'xp', xp) order by level) from skill_curve), '[]'::jsonb),
    'skills', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', k.id, 'name', k.name, 'icon', k.icon, 'blurb', k.blurb, 'train_text', k.train_text,
        'xp', x.xp, 'level', x.lvl,
        'level_xp', bl_skill_xp_for_level(x.lvl),
        'next_xp', case when x.lvl < v_max then bl_skill_xp_for_level(x.lvl + 1) end,
        'pct', case when x.lvl >= v_max then 100
                    else round(100.0 * (x.xp - bl_skill_xp_for_level(x.lvl))
                               / greatest(1, bl_skill_xp_for_level(x.lvl + 1) - bl_skill_xp_for_level(x.lvl)), 1) end,
        'pay_pct', case when k.pay_pct_per_level > 0 then round(greatest(0, x.lvl - 1) * k.pay_pct_per_level, 2) end,
        'caught_cut_pct', case when k.caught_pct_per_level > 0 then least(k.caught_cap_pct, greatest(0, x.lvl - 1) * k.caught_pct_per_level) end,
        'next_unlocks', case when x.lvl < v_max then to_jsonb(bl_skill_unlocks(k.id, x.lvl + 1)) else '[]'::jsonb end,
        'train', coalesce((
          select jsonb_agg(jsonb_build_object('kind', t.kind, 'ref', t.ref, 'name', t.name, 'xp', t.xp) order by t.xp desc, t.name)
            from (select s.kind, s.ref, s.xp,
                         case s.kind
                           when 'hustle' then coalesce((select h.name from hustles h where h.id = s.ref), s.ref)
                           when 'yahoo' then coalesce((select j.name from yahoo_jobs j where j.id = s.ref), s.ref)
                           when 'career' then coalesce((select 'Career shift: ' || c.name from career_tracks c where c.id = s.ref), s.ref)
                           else coalesce((select a.name from activities a where a.id = s.ref), s.ref) end as name
                    from skill_sources s where s.skill_id = k.id and s.active order by s.xp desc, s.id limit 8) t), '[]'::jsonb)
      ) order by k.sort, k.id)
      from skills k
      cross join lateral (select bl_skill_xp(v_uid, k.id) as xp, bl_skill_level_for_xp(bl_skill_xp(v_uid, k.id)) as lvl) x
      where k.active), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Admin RPCs: a player's skills (read) and set (audit)
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_player_skills(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'max_level', bl_skill_max_level(),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'skill', k.id, 'name', k.name, 'icon', k.icon, 'xp', bl_skill_xp(p_user, k.id),
        'level', bl_skill_level_for_xp(bl_skill_xp(p_user, k.id)),
        'next_xp', (select c.xp from skill_curve c where c.level = bl_skill_level_for_xp(bl_skill_xp(p_user, k.id)) + 1)) order by k.sort, k.id)
      from skills k), '[]'::jsonb));
end $$;

-- p_level (jumps to that level's XP) or p_xp (exact XP); logged to admin_audit as set_skill
create or replace function public.admin_set_player_skill(p_user uuid, p_skill text, p_level int default null, p_xp int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  k       skills;
  v_old   int;
  v_new   int;
begin
  if not exists (select 1 from profiles where id = p_user) then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  select * into k from skills where id = p_skill;
  if not found then
    raise exception 'That skill doesn''t exist.' using errcode = 'P0001', hint = 'bad_skill';
  end if;
  if p_level is not null then
    if not exists (select 1 from skill_curve where level = p_level) then
      raise exception 'Level must be between 1 and %.', bl_skill_max_level() using errcode = 'P0001', hint = 'bad_value';
    end if;
    v_new := bl_skill_xp_for_level(p_level);
  elsif p_xp is not null then
    if p_xp < 0 then
      raise exception 'XP can''t be negative.' using errcode = 'P0001', hint = 'bad_value';
    end if;
    v_new := least(p_xp, 1000000000);
  else
    raise exception 'Send a level or an XP amount.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  v_old := bl_skill_xp(p_user, p_skill);
  insert into player_skills (user_id, skill_id, xp, updated_at) values (p_user, p_skill, v_new, bl_now())
  on conflict (user_id, skill_id) do update set xp = excluded.xp, updated_at = bl_now();
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'set_skill', p_user, jsonb_build_object('skill', p_skill, 'old_xp', v_old, 'new_xp', v_new,
            'old_level', bl_skill_level_for_xp(v_old), 'new_level', bl_skill_level_for_xp(v_new)));
  return jsonb_build_object('message', k.name || ' set to level ' || bl_skill_level_for_xp(v_new) || ' (' || v_new || ' XP).',
                            'skill', p_skill, 'xp', v_new, 'level', bl_skill_level_for_xp(v_new));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Backfill (once, only while nobody has any skill XP): past hustle runs and Yahoo jobs count
-- ---------------------------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from public.player_skills) then
    insert into public.player_skills (user_id, skill_id, xp)
    select t.user_id, t.skill_id, least(sum(t.xp), 1000000)::int
      from (
        select r.user_id, s.skill_id, s.xp::numeric as xp
          from public.hustle_runs r join public.skill_sources s on s.kind = 'hustle' and s.ref = r.hustle_id and s.active
         where r.status = 'done' and r.outcome is distinct from 'loss'
        union all
        select r.user_id, s.skill_id, s.xp::numeric
          from public.yahoo_runs r join public.skill_sources s on s.kind = 'yahoo' and s.ref = r.job_id and s.active
         where r.status in ('paid', 'cashed')) t
      join public.profiles p on p.id = t.user_id
     group by t.user_id, t.skill_id
    on conflict (user_id, skill_id) do nothing;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Guarded edits of live functions
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

select pg_temp.bl_patch('public.bl_yahoo_resolve(bigint)', $j$[
 {"done": "bl_skill_caught_pct(", "marker": "if bl_crime_roll(r.caught_pct) then",
  "new": "if bl_crime_roll(bl_skill_caught_pct(r.user_id, r.caught_pct)) then"},
 {"done": "bl_skill_award(", "marker": "v_rank1 := bl_yahoo_rank_row(r.user_id);",
  "new": "if v_status <> 'caught' then perform bl_skill_award(r.user_id, 'yahoo', r.job_id); end if;\n  v_rank1 := bl_yahoo_rank_row(r.user_id);"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_yahoo_run_json(public.yahoo_runs)', $j$[
 {"done": "skill_caught_pct", "marker": "'caught_pct', r.caught_pct,",
  "new": "'caught_pct', r.caught_pct, 'skill_caught_pct', bl_skill_caught_pct(r.user_id, r.caught_pct),"}
]$j$::jsonb);

select pg_temp.bl_patch('public.yahoo_job_start(text, bigint)', $j$[
 {"done": "bl_skill_gate(", "marker": "v_where := bl_yahoo_where(v_me);",
  "new": "if bl_skill_gate(v_me.id, 'yahoo', j.id, j.min_skill_level) is not null then\n    raise exception '%', bl_skill_gate(v_me.id, 'yahoo', j.id, j.min_skill_level)->>'message' using errcode = 'P0001', hint = 'skill_level';\n  end if;\n  v_where := bl_yahoo_where(v_me);"},
 {"done": "skill_caught_pct", "marker": "'caught_pct', v_pct, 'amount', v_amt,",
  "new": "'caught_pct', v_pct, 'skill_caught_pct', bl_skill_caught_pct(v_me.id, v_pct), 'amount', v_amt,"}
]$j$::jsonb);

select pg_temp.bl_patch('public.yahoo_status()', $j$[
 {"done": "skill_caught_pct", "marker": "'caught_pct', bl_yahoo_caught_pct(v_uid, j, v_lap), 'base_caught_pct', j.caught_pct,",
  "new": "'caught_pct', bl_yahoo_caught_pct(v_uid, j, v_lap), 'skill_caught_pct', bl_skill_caught_pct(v_uid, bl_yahoo_caught_pct(v_uid, j, v_lap)), 'base_caught_pct', j.caught_pct,"},
 {"done": "'min_skill_level'", "marker": "'min_tier', j.min_tier,",
  "new": "'min_tier', j.min_tier, 'min_skill_level', j.min_skill_level, 'skill', bl_skill_card(v_uid, 'yahoo', j.id, j.min_skill_level),"},
 {"done": "then 'skill_level'", "marker": "then 'laptop_too_weak' end,",
  "new": "then 'laptop_too_weak'\n                              when bl_skill_gate(v_uid, 'yahoo', j.id, j.min_skill_level) is not null then 'skill_level' end,"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_hustle_resolve(bigint)', $j$[
 {"done": "bl_skill_award(", "marker": "perform bl_referral_check(r.user_id);",
  "new": "if v_out <> 'loss' then perform bl_skill_award(r.user_id, 'hustle', h.id); end if;\n  perform bl_referral_check(r.user_id);"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_hustle_pay_mult(uuid, public.hustles)', $j$[
 {"done": "bl_skill_pay_mult(", "marker": "* bl_hustle_hour_mult(h);",
  "new": "* bl_hustle_hour_mult(h) * bl_skill_pay_mult(p_uid, 'hustle', h.id);"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_hustle_why(public.profiles, public.hustles, public.locations, boolean)', $j$[
 {"done": "bl_skill_gate(", "marker": "if p_check_place then",
  "new": "if bl_skill_gate(p_me.id, 'hustle', h.id, h.min_skill_level) is not null then\n    return bl_skill_gate(p_me.id, 'hustle', h.id, h.min_skill_level);\n  end if;\n  if p_check_place then"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_hustle_json(public.profiles, public.hustles, public.locations)', $j$[
 {"done": "bl_skill_card(", "marker": "'locked', v_why);",
  "new": "'skill', bl_skill_card(p_me.id, 'hustle', h.id, h.min_skill_level),\n    'locked', v_why);"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_hustle_card(public.profiles, public.hustles, public.locations, text, text, text)', $j$[
 {"done": "bl_skill_card(", "marker": "'locked', v_why->>'short');",
  "new": "'skill', bl_skill_card(p_me.id, 'hustle', h.id, h.min_skill_level),\n    'locked', v_why->>'short');"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_settle_shift(uuid)', $j$[
 {"done": "bl_skill_award(", "marker": "v_xp := v_me.job_xp + coalesce(v_me.job_shift_xp, 0);",
  "new": "perform bl_skill_award(p_uid, 'career', v_me.job_id);\n  v_xp := v_me.job_xp + coalesce(v_me.job_shift_xp, 0);"}
]$j$::jsonb);

select pg_temp.bl_patch('public.do_activity(text)', $j$[
 {"done": "bl_skill_award(", "marker": "v_until := bl_set_busy_seconds(v_me.id, v_secs, a.name);",
  "new": "perform bl_skill_award(v_me.id, 'activity', a.id);\n  v_until := bl_set_busy_seconds(v_me.id, v_secs, a.name);"}
]$j$::jsonb);

-- admin Content editor: the three new tables + the new gate columns
select pg_temp.bl_patch('public.bl_admin_table_spec(text)', $j$[
 {"done": "when 'skills' then", "marker": "when 'hustle_car_classes' then",
  "new": "when 'skills' then '{\"pk\":[\"id\"],\"insert\":true,\"order\":\"sort, id\",\n      \"cols\":{\"name\":\"text\",\"icon\":\"text\",\"blurb\":\"text\",\"train_text\":\"text\",\"trait_keys\":\"arr\",\"pay_pct_per_level\":\"num\",\n              \"caught_pct_per_level\":\"num\",\"caught_cap_pct\":\"num\",\"sort\":\"int\",\"active\":\"bool\"}}'\n    when 'skill_curve' then '{\"pk\":[\"level\"],\"insert\":true,\"order\":\"level\",\"cols\":{\"xp\":\"int\"}}'\n    when 'skill_sources' then '{\"pk\":[\"id\"],\"insert\":true,\"order\":\"kind, ref, id\",\n      \"cols\":{\"kind\":\"text\",\"ref\":\"text\",\"skill_id\":\"text\",\"xp\":\"num\",\"note\":\"text\",\"active\":\"bool\"}}'\n    when 'hustle_car_classes' then"},
 {"done": "\"hour_mult\":\"obj\",\"min_skill_level\"", "marker": "\"hype_text\":\"text\",\"hour_mult\":\"obj\",",
  "new": "\"hype_text\":\"text\",\"hour_mult\":\"obj\",\"min_skill_level\":\"int\","},
 {"done": "\"min_tier\":\"int\",\"min_skill_level\"", "marker": "\"cooldown_seconds\":\"int\",\"min_tier\":\"int\",",
  "new": "\"cooldown_seconds\":\"int\",\"min_tier\":\"int\",\"min_skill_level\":\"int\","}
]$j$::jsonb);

-- ---------------------------------------------------------------------------------------------
-- 9. Grants
-- ---------------------------------------------------------------------------------------------
revoke all on function public.bl_skill_on() from public, anon, authenticated;
revoke all on function public.bl_skill_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_skill_max_level() from public, anon, authenticated;
revoke all on function public.bl_skill_level_for_xp(numeric) from public, anon, authenticated;
revoke all on function public.bl_skill_xp_for_level(int) from public, anon, authenticated;
revoke all on function public.bl_skill_xp(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_skill_level(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_skill_main(text, text) from public, anon, authenticated;
revoke all on function public.bl_skill_gate(uuid, text, text, int) from public, anon, authenticated;
revoke all on function public.bl_skill_pay_mult(uuid, text, text) from public, anon, authenticated;
revoke all on function public.bl_skill_caught_cut(uuid) from public, anon, authenticated;
revoke all on function public.bl_skill_caught_pct(uuid, numeric) from public, anon, authenticated;
revoke all on function public.bl_skill_card(uuid, text, text, int) from public, anon, authenticated;
revoke all on function public.bl_skill_unlocks(text, int) from public, anon, authenticated;
revoke all on function public.bl_skill_award(uuid, text, text) from public, anon, authenticated;

revoke all on function public.skills_status() from public, anon;
grant execute on function public.skills_status() to authenticated, service_role;
revoke all on function public.admin_player_skills(uuid) from public, anon;
grant execute on function public.admin_player_skills(uuid) to authenticated, service_role;
revoke all on function public.admin_set_player_skill(uuid, text, int, int) from public, anon;
grant execute on function public.admin_set_player_skill(uuid, text, int, int) to authenticated, service_role;

notify pgrst, 'reload schema';
