-- Daily stories with a twist (docs/DAILY_STORIES.md). Reuses the Life moments engine (docs/MOMENTS.md): the stories are rows of
-- life_moments (kinds 'daily' and 'chapter'), validated by the same closed lists of conditions and effects, edited in the same
-- Admin -> Content editor, and run through the same effect applier (bl_moment_apply). Added on top:
--   * choices may have several WEIGHTED OUTCOMES (the twist), each with a tone, effects, an eligibility filter and path weights;
--   * delayed consequences: follow_up (already in the closed list) now reaches stories ('chapter' rows in player_stories) as well as moments;
--   * the HIDDEN PATH: six scores per player in the new table player_path, never shown as numbers. Choices nudge them; they tilt which
--     stories and outcomes appear and give small, capped effects elsewhere (luck in moments, a blessing, a police scene);
--   * one daily story per player per Benin day, picked on the server (deterministic per player and day), answered once;
--   * a reading streak (3 / 7 / 14 days) that pays a small reward once per step;
--   * a nudge: a badge number in moments_pending() and an optional push (through bl_push_enqueue, so every push cap still applies).
-- Story INSTANCES live in player_stories (not player_moments) so they never pop up, never use up the moment daily cap and never block a
-- random moment. The weekly community story (weekly_storyline_*) is replaced by this; its tables and RPCs stay for old app versions.
-- Idempotent: tables `if not exists`, seeds `on conflict do nothing`, settings only inserted, live functions patched ONLY through guarded
-- replaces (raise when the marker is missing, skip when already applied). Nothing here touches the profiles table.

create or replace function pg_temp.ds_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'daily_stories: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Daily stories)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('stories.daily_enabled', 'true', 'stories', 'Daily stories on',
 'Master switch for the daily story in the Stories app, its follow-ups and arcs, the hidden path and the streak. Off = no new story, nothing is shown.', 'bool', null, null),
('stories.per_day', '1', 'stories', 'Stories per player per day',
 'How many daily stories each player gets every Benin day (1 is the plan: one small moment a day).', 'number', 1, 3),
('stories.no_repeat_days', '30', 'stories', 'A story does not repeat for (days)',
 'The shortest wait before the same daily story can come back for a player. A story''s own cooldown can make it longer. If a player has seen everything, the one seen longest ago returns.', 'number', 0, 365),
('stories.max_nudge', '6', 'stories', 'Biggest path nudge from one choice',
 'A choice or an outcome can move a hidden path score by at most this many points (scores run from -100 to 100). Bigger numbers in a story are cut down to this.', 'number', 0, 20),
('stories.path_strength', '1.5', 'stories', 'How strongly the path tilts the odds',
 'A story or an outcome with path weights is more or less likely by (weight x score / 100 x this). 0 = the path never changes which story or outcome comes.', 'number', 0, 5),
('stories.path_max_mult', '3', 'stories', 'Most the path can multiply a weight',
 'The path never makes a story or an outcome more than this many times likelier, or this many times rarer.', 'number', 1, 10),
('stories.karma_pct', '30', 'stories', 'Karma: how much luck drifts with goodwill and trouble (%)',
 'Every kind choice (goodwill up) nudges luck up and every shady one (trouble up) nudges it down by this share of the change, rounded towards zero.', 'percent', 0, 100),
('stories.path_decay_week', '2', 'stories', 'Path scores drift back to zero (points a week)',
 'Once a week every path score moves this many points towards zero, so an old reputation fades unless it is kept up. 0 = never.', 'number', 0, 20),
('stories.band_1', '12', 'stories', 'Path: first level (points)',
 'At this many points (either way) a path score starts to show in words ("Your path so far") and the first subtle line can appear.', 'number', 1, 99),
('stories.band_2', '35', 'stories', 'Path: strong level (points)',
 'At this many points a path score is strong: stronger words and a second subtle line.', 'number', 2, 100),
('stories.whisper_pct', '15', 'stories', 'Chance of a subtle line after a story (%)',
 'Besides the line shown when a score first crosses a level, this is the chance of a subtle line about the player''s strongest path after any story.', 'percent', 0, 100),
('stories.luck_odds_pct', '20', 'stories', 'Luck tilt on story outcomes (%)',
 'At full luck (100) good outcomes are this % likelier and bad ones this % rarer. At luck 0 nothing changes. Small by design.', 'percent', 0, 100),
('stories.luck_chance_cap', '5', 'stories', 'Luck tilt on moment chances (percentage points)',
 'In the Life moments pop-ups, luck moves a choice''s success chance by at most this many percentage points up or down (never a sure thing, never a sure fail; doctor cards are left fair).', 'number', 0, 15),
('stories.followup_max_chance', '100', 'stories', 'Highest follow-up chance (%)',
 'A seed planted by a story comes back with its own chance, cut down to this. 100 = as written; lower it to make every twist rarer.', 'percent', 0, 100),
('stories.followup_max_pending', '4', 'stories', 'Most waiting follow-ups per player',
 'How many planted seeds (follow-up stories or moments not yet due) one player can have. A new seed is skipped when the player already has this many.', 'number', 0, 20),
('stories.followup_max_days', '7', 'stories', 'Longest wait for a follow-up (days)',
 'A planted seed arrives after at most this many days, whatever the story says.', 'number', 1, 30),
('stories.chapter_expire_days', '7', 'stories', 'A follow-up story fades after (days)',
 'A follow-up or arc chapter nobody answered fades away this many days after it arrived.', 'number', 1, 60),
('stories.max_cash_gain', '15000', 'stories', 'Most cash one story outcome can give',
 'A cash gain in a story outcome is cut down to this, and stories above it are refused when saved in Admin. Never earnings: no wage, no tax.', 'naira', 0, 1000000),
('stories.daily_gain_cap', '25000', 'stories', 'Most cash all stories can give a player per day',
 'Once a player has been given this much cash by stories today, further cash gains are skipped (the rest of the outcome still happens).', 'naira', 0, 1000000),
('stories.special_min_score', '25', 'stories', 'Path score for blessings and police scenes (points)',
 'Goodwill at or above this can bring a blessing; trouble at or above this can bring a police or EFCC scene (they replace a normal Life moment roll).', 'number', 1, 100),
('stories.blessing_pct', '4', 'stories', 'Blessing chance per Life moment roll (%)',
 'A kind player (goodwill high enough) sometimes gets a small blessing instead of a normal moment: a gift, a free plate. 0 = never.', 'percent', 0, 100),
('stories.blessing_cooldown_days', '5', 'stories', 'Days between blessings',
 'The shortest wait before the same player can get another blessing.', 'number', 0, 60),
('stories.police_pct', '4', 'stories', 'Police scene chance per Life moment roll (%)',
 'A player with a lot of trouble sometimes gets a police or EFCC scene instead of a normal moment. 0 = never.', 'percent', 0, 100),
('stories.police_cooldown_days', '6', 'stories', 'Days between police scenes',
 'The shortest wait before the same player can get another police or EFCC scene.', 'number', 0, 60),
('stories.push_enabled', 'true', 'stories', 'Push: "your story is waiting"',
 'Send a push (through the normal push system, Game events category, with all its caps) when today''s story or a follow-up is waiting. Players choose in Settings -> Notifications.', 'bool', null, null),
('stories.push_hour', '17', 'stories', 'Push: not before this Benin hour',
 'The daily story push is only sent after this hour (Benin time) and only to a player who has not read today''s story yet.', 'number', 0, 23),
('stories.push_max_per_tick', '300', 'stories', 'Push: most players queued per minute',
 'A safety limit on how many "story is waiting" pushes one minute of the push job can queue.', 'number', 1, 5000),
('stories.streak_days_1', '3', 'stories', 'Streak reward 1: days in a row', 'Reading (answering) the daily story this many days in a row pays reward 1, once per streak.', 'number', 1, 60),
('stories.streak_cash_1', '2000', 'stories', 'Streak reward 1: cash', 'Cash for the first streak step.', 'naira', 0, 100000),
('stories.streak_days_2', '7', 'stories', 'Streak reward 2: days in a row', 'Days in a row for the second streak step.', 'number', 1, 60),
('stories.streak_cash_2', '5000', 'stories', 'Streak reward 2: cash', 'Cash for the second streak step.', 'naira', 0, 100000),
('stories.streak_days_3', '14', 'stories', 'Streak reward 3: days in a row', 'Days in a row for the third streak step.', 'number', 1, 60),
('stories.streak_cash_3', '12000', 'stories', 'Streak reward 3: cash', 'Cash for the third streak step. A missed day starts a new streak and the steps can be earned again.', 'naira', 0, 100000)
on conflict (key) do nothing;

-- the old weekly story is replaced (only reword it while it still has the old text)
update public.game_config set label = 'Old weekly story (replaced by daily stories)',
       description = 'The old one-story-a-week catalogue. The Stories app now shows the daily story (Settings -> Daily stories); this only matters for old app versions.'
 where key = 'storyline.enabled' and label = 'Weekly stories';

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
alter table public.life_moments drop constraint if exists life_moments_kind_check;
alter table public.life_moments add constraint life_moments_kind_check
  check (kind in ('random', 'kids_ill', 'kids_school', 'kids_uni', 'system', 'daily', 'chapter'));
alter table public.life_moments add column if not exists path_w jsonb not null default '{}'::jsonb;
do $$ begin
  alter table public.life_moments add constraint life_moments_path_w_object check (jsonb_typeof(path_w) = 'object');
exception when duplicate_object then null; end $$;

create table if not exists public.player_path (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  goodwill     smallint not null default 0 check (goodwill between -100 and 100),
  hustle       smallint not null default 0 check (hustle between -100 and 100),
  luck         smallint not null default 0 check (luck between -100 and 100),
  trouble      smallint not null default 0 check (trouble between -100 and 100),
  faith        smallint not null default 0 check (faith between -100 and 100),
  family       smallint not null default 0 check (family between -100 and 100),
  bands        jsonb not null default '{}'::jsonb,
  last_whisper text,
  decayed_on   date not null default current_date,
  updated_at   timestamptz not null default now()
);

-- Words for the path: the subtle line (whisper) and the word used in "Your path so far" (word), per score, side and level.
create table if not exists public.path_lines (
  id      text primary key check (id ~ '^[a-z][a-z0-9_]{2,40}$'),
  score   text not null check (score in ('goodwill', 'hustle', 'luck', 'trouble', 'faith', 'family')),
  sign    smallint not null check (sign in (-1, 1)),
  band    smallint not null check (band in (1, 2)),
  word    text not null default '' check (char_length(word) <= 40),
  whisper text not null default '' check (char_length(whisper) <= 160),
  sort    integer not null default 100,
  active  boolean not null default true,
  unique (score, sign, band)
);

create table if not exists public.player_stories (
  id          bigserial primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  story_id    text not null references public.life_moments(id) on delete cascade,
  kind        text not null check (kind in ('daily', 'chapter')),
  day         date not null,
  slot        smallint not null default 1,
  status      text not null default 'pending' check (status in ('pending', 'answered', 'expired')),
  context     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  show_at     timestamptz not null default now(),
  answered_at timestamptz,
  choice_id   text,
  outcome_id  text,
  result      jsonb
);
create unique index if not exists player_stories_daily_slot on public.player_stories (user_id, day, slot) where kind = 'daily';
create index if not exists player_stories_user_status on public.player_stories (user_id, status, show_at);
create index if not exists player_stories_user_story on public.player_stories (user_id, story_id, day desc);
create index if not exists player_stories_chapter_due on public.player_stories (show_at) where kind = 'chapter' and status = 'pending';

create table if not exists public.story_streak (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  last_day   date,
  streak     integer not null default 0 check (streak >= 0),
  best       integer not null default 0 check (best >= 0),
  claimed    jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['player_path', 'path_lines', 'player_stories', 'story_streak'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
  revoke all on sequence public.player_stories_id_seq from public, anon, authenticated;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. The hidden path (private helpers)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_path_keys() returns text[]
language sql immutable set search_path = public as $$
  select array['goodwill', 'hustle', 'luck', 'trouble', 'faith', 'family']
$$;

create or replace function public.bl_path_val(r public.player_path, k text) returns integer
language sql immutable set search_path = public as $$
  select coalesce((to_jsonb(r) ->> k)::integer, 0)
$$;

create or replace function public.bl_path_toward0(v integer, d integer) returns integer
language sql immutable set search_path = public as $$
  select case when v > 0 then greatest(0, v - d) else least(0, v + d) end
$$;

-- the player's row (made on first use); old scores fade towards zero once a week
create or replace function public.bl_path_get(p_uid uuid) returns public.player_path
language plpgsql security definer set search_path = public as $$
declare r public.player_path; v_today date := bl_wat_date(bl_now()); v_w integer; v_d integer := greatest(0, bl_love_num('stories.path_decay_week', 2)::integer);
begin
  insert into player_path (user_id, decayed_on) values (p_uid, v_today) on conflict (user_id) do nothing;
  select * into r from player_path where user_id = p_uid for update;
  v_w := (v_today - r.decayed_on) / 7;
  if v_w >= 1 then
    update player_path set goodwill = bl_path_toward0(goodwill, v_w * v_d), hustle = bl_path_toward0(hustle, v_w * v_d),
           luck = bl_path_toward0(luck, v_w * v_d), trouble = bl_path_toward0(trouble, v_w * v_d),
           faith = bl_path_toward0(faith, v_w * v_d), family = bl_path_toward0(family, v_w * v_d),
           decayed_on = r.decayed_on + v_w * 7, updated_at = bl_now()
     where user_id = p_uid returning * into r;
  end if;
  return r;
end $$;

-- 0 = below the first level, 1 = first level, 2 = strong
create or replace function public.bl_path_band(s integer) returns integer
language sql stable set search_path = public as $$
  select case when abs(s) >= bl_love_num('stories.band_2', 35) then 2 when abs(s) >= bl_love_num('stories.band_1', 12) then 1 else 0 end
$$;

-- Nudge the scores ({"goodwill": 3, "trouble": -1}). Every delta is cut to stories.max_nudge, scores stay within -100..100, and luck
-- drifts with goodwill and trouble (karma). Returns the deltas that were applied.
create or replace function public.bl_path_nudge(p_uid uuid, p_delta jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.player_path; v_m integer := greatest(0, bl_love_num('stories.max_nudge', 6)::integer); k text; d integer; dl jsonb := '{}'::jsonb;
  g integer; t integer; kd integer; v_karma numeric := bl_love_num('stories.karma_pct', 30);
begin
  if p_delta is null or jsonb_typeof(p_delta) <> 'object' then return dl; end if;
  for k in select jsonb_object_keys(p_delta) loop
    continue when k <> all (bl_path_keys());
    d := greatest(-v_m, least(v_m, trunc((p_delta ->> k)::numeric)::integer));
    if d <> 0 then dl := dl || jsonb_build_object(k, d); end if;
  end loop;
  g := coalesce((dl ->> 'goodwill')::integer, 0); t := coalesce((dl ->> 'trouble')::integer, 0);
  kd := trunc((g - t) * v_karma / 100)::integer;
  if kd <> 0 then dl := dl || jsonb_build_object('luck', greatest(-v_m, least(v_m, coalesce((dl ->> 'luck')::integer, 0) + kd))); end if;
  if dl = '{}'::jsonb then return dl; end if;
  r := bl_path_get(p_uid);
  update player_path set
    goodwill = greatest(-100, least(100, goodwill + coalesce((dl ->> 'goodwill')::integer, 0))),
    hustle   = greatest(-100, least(100, hustle   + coalesce((dl ->> 'hustle')::integer, 0))),
    luck     = greatest(-100, least(100, luck     + coalesce((dl ->> 'luck')::integer, 0))),
    trouble  = greatest(-100, least(100, trouble  + coalesce((dl ->> 'trouble')::integer, 0))),
    faith    = greatest(-100, least(100, faith    + coalesce((dl ->> 'faith')::integer, 0))),
    family   = greatest(-100, least(100, family   + coalesce((dl ->> 'family')::integer, 0))),
    updated_at = bl_now()
   where user_id = p_uid;
  return dl;
end $$;

-- A player's score without making a row (0 when there is none)
create or replace function public.bl_path_value(p_uid uuid, p_key text) returns integer
language plpgsql stable security definer set search_path = public as $$
declare r public.player_path;
begin
  select * into r from player_path where user_id = p_uid;
  if not found then return 0; end if;
  return bl_path_val(r, p_key);
end $$;

-- How much the path multiplies a weight ({"goodwill": 1, "trouble": -1}); bounded by stories.path_max_mult both ways
create or replace function public.bl_path_mult(r public.player_path, p_w jsonb) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare k text; f numeric; m numeric := 1; v_s numeric := bl_love_num('stories.path_strength', 1.5); v_mx numeric := greatest(1, bl_love_num('stories.path_max_mult', 3));
begin
  if p_w is null or p_w = '{}'::jsonb then return 1; end if;
  for k, f in select x.key, x.value::numeric from jsonb_each_text(p_w) x loop
    continue when k <> all (bl_path_keys());
    m := m * greatest(0.05, 1 + f * (bl_path_val(r, k) / 100.0) * v_s);
  end loop;
  return greatest(1 / v_mx, least(v_mx, m));
end $$;

-- Luck leans good outcomes up and bad ones down, a little (stories.luck_odds_pct at luck 100)
create or replace function public.bl_story_luck_mult(p_luck integer, p_tone text) returns numeric
language sql stable set search_path = public as $$
  select case when p_tone = 'good' then 1 + (p_luck / 100.0) * bl_love_num('stories.luck_odds_pct', 20) / 100
              when p_tone = 'bad' then greatest(0.05, 1 - (p_luck / 100.0) * bl_love_num('stories.luck_odds_pct', 20) / 100)
              else 1 end
$$;

-- The success chance of a Life moment choice, leaned by luck by at most stories.luck_chance_cap points (never 0 or 100)
create or replace function public.bl_story_luck_chance(p_uid uuid, p_chance numeric, p_kind text) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare v_cap numeric := greatest(0, bl_love_num('stories.luck_chance_cap', 5));
begin
  if p_chance is null or p_chance <= 0 or p_chance >= 100 or p_kind in ('kids_ill', 'kids_school', 'kids_uni') or v_cap = 0
     or not coalesce(bl_cfg_bool('stories.daily_enabled'), true) then
    return p_chance;
  end if;
  return greatest(1, least(99, p_chance + greatest(-v_cap, least(v_cap, bl_path_value(p_uid, 'luck') / 100.0 * v_cap))));
end $$;

-- the subtle line: a score just crossed a level (once per score, side and level), or sometimes about the strongest score
create or replace function public.bl_path_whisper(p_uid uuid, b public.player_path) returns text
language plpgsql security definer set search_path = public as $$
declare
  a public.player_path; k text; s0 integer; s1 integer; b0 integer; b1 integer; v_key text; v_line text; v_best integer := -1; v_pick text; v_pick_band integer;
  v_seen jsonb; v_sum numeric := 0; v_r numeric; v_cand text[] := '{}'; v_cb integer[] := '{}'; i integer;
begin
  select * into a from player_path where user_id = p_uid;
  if not found then return null; end if;
  v_seen := a.bands;
  foreach k in array bl_path_keys() loop
    s1 := bl_path_val(a, k); s0 := bl_path_val(b, k);
    b1 := bl_path_band(s1);
    b0 := case when sign(s0) = sign(s1) then bl_path_band(s0) else 0 end;
    if b1 > b0 and b1 >= 1 then
      v_key := k || ':' || sign(s1)::integer || ':' || b1;
      if not (v_seen ? v_key) then
        v_seen := v_seen || jsonb_build_object(v_key, true);
        if abs(s1) > v_best then v_best := abs(s1); v_pick := k; v_pick_band := b1; end if;
      end if;
    end if;
  end loop;
  if v_pick is null and bl_rand() * 100 < bl_love_num('stories.whisper_pct', 15) then
    foreach k in array bl_path_keys() loop
      s1 := bl_path_val(a, k);
      if bl_path_band(s1) >= 1 and k is distinct from a.last_whisper then
        v_cand := v_cand || k; v_cb := v_cb || bl_path_band(s1); v_sum := v_sum + abs(s1);
      end if;
    end loop;
    if v_sum > 0 then
      v_r := bl_rand() * v_sum;
      for i in 1..array_length(v_cand, 1) loop
        v_pick := v_cand[i]; v_pick_band := v_cb[i];
        v_r := v_r - abs(bl_path_val(a, v_cand[i]));
        exit when v_r < 0;
      end loop;
    end if;
  end if;
  update player_path set bands = v_seen where user_id = p_uid and bands is distinct from v_seen;
  if v_pick is null then return null; end if;
  select pl.whisper into v_line from path_lines pl
   where pl.score = v_pick and pl.sign = sign(bl_path_val(a, v_pick)) and pl.band = v_pick_band and pl.active and pl.whisper <> '';
  if v_line is not null then update player_path set last_whisper = v_pick where user_id = p_uid; end if;
  return v_line;
end $$;

-- "Your path so far": a sentence, never numbers. {title, notes[]}
create or replace function public.bl_path_describe(p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r public.player_path; k text; s integer; v_noun text; v_tail text; v_adj text[] := '{}'; v_w text; v_title text; v_notes jsonb := '[]'::jsonb; v_first text;
begin
  select * into r from player_path where user_id = p_uid;
  if not found then return jsonb_build_object('title', 'Your story is only starting', 'notes', '[]'::jsonb); end if;
  select pl.word into v_noun from path_lines pl where pl.score = 'hustle' and pl.sign = sign(r.hustle) and pl.band = bl_path_band(r.hustle) and pl.active and pl.word <> '';
  select pl.word into v_tail from path_lines pl where pl.score = 'luck' and pl.sign = sign(r.luck) and pl.band = bl_path_band(r.luck) and pl.active and pl.word <> '';
  for k, s in select x.k, x.s from (values ('goodwill', r.goodwill::integer), ('trouble', r.trouble::integer), ('faith', r.faith::integer), ('family', r.family::integer)) x(k, s)
              where bl_path_band(x.s) >= 1 order by abs(x.s) desc, x.k limit 2 loop
    select pl.word into v_w from path_lines pl where pl.score = k and pl.sign = sign(s) and pl.band = bl_path_band(s) and pl.active and pl.word <> '';
    if v_w is not null then v_adj := v_adj || v_w; end if;
  end loop;
  if v_noun is null and v_tail is null and array_length(v_adj, 1) is null then
    return jsonb_build_object('title', 'Your story is only starting', 'notes', '[]'::jsonb);
  end if;
  v_noun := coalesce(v_noun, 'soul');
  v_first := coalesce(v_adj[1], v_noun);
  v_title := case when left(lower(v_first), 1) in ('a', 'e', 'i', 'o', 'u') then 'An ' else 'A ' end
             || coalesce(array_to_string(v_adj, ' and ') || ' ', '') || v_noun || coalesce(' ' || v_tail, '');
  for k, s in select x.k, x.s from (values ('goodwill', r.goodwill::integer), ('hustle', r.hustle::integer), ('luck', r.luck::integer), ('trouble', r.trouble::integer),
                                          ('faith', r.faith::integer), ('family', r.family::integer)) x(k, s)
              where bl_path_band(x.s) >= 1 order by abs(x.s) desc, x.k limit 3 loop
    select pl.whisper into v_w from path_lines pl where pl.score = k and pl.sign = sign(s) and pl.band = bl_path_band(s) and pl.active and pl.whisper <> '';
    if v_w is not null then v_notes := v_notes || to_jsonb(v_w); end if;
  end loop;
  return jsonb_build_object('title', v_title, 'notes', v_notes);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. Validation of the new content (called from the patched moment checkers and the row guard)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_story_check_path_delta(d jsonb) returns void
language plpgsql stable set search_path = public as $$
declare k text;
begin
  if jsonb_typeof(d) is distinct from 'object' then perform bl_moment_bad('path must look like {"goodwill": 3}'); end if;
  for k in select jsonb_object_keys(d) loop
    if k <> all (bl_path_keys()) then perform bl_moment_bad('unknown path score ' || k || ' (goodwill, hustle, luck, trouble, faith, family)'); end if;
    if jsonb_typeof(d -> k) is distinct from 'number' or abs((d ->> k)::numeric) > 20 then perform bl_moment_bad('a path nudge is a number from -20 to 20'); end if;
  end loop;
end $$;

create or replace function public.bl_story_check_pathw(w jsonb) returns void
language plpgsql stable set search_path = public as $$
declare k text;
begin
  if jsonb_typeof(w) is distinct from 'object' then perform bl_moment_bad('path_w must look like {"goodwill": 1}'); end if;
  for k in select jsonb_object_keys(w) loop
    if k <> all (bl_path_keys()) then perform bl_moment_bad('unknown path score ' || k); end if;
    if jsonb_typeof(w -> k) is distinct from 'number' or abs((w ->> k)::numeric) > 3 then perform bl_moment_bad('a path weight is a number from -3 to 3'); end if;
  end loop;
end $$;

-- the extra conditions: partner, kids, car, job, gang, school, business (true/false), origin ("lapo"/"nepo"), path ({"trouble": {"min": 20}})
create or replace function public.bl_story_check_cond(k text, v jsonb) returns void
language plpgsql stable set search_path = public as $$
declare s text; b jsonb;
begin
  if k in ('partner', 'kids', 'car', 'job', 'gang', 'school', 'business') then
    if jsonb_typeof(v) is distinct from 'boolean' then perform bl_moment_bad(k || ' must be true or false'); end if;
  elsif k = 'origin' then
    if jsonb_typeof(v) is distinct from 'string' or (v #>> '{}') not in ('lapo', 'nepo') then perform bl_moment_bad('origin must be "lapo" or "nepo"'); end if;
  elsif k = 'path' then
    if jsonb_typeof(v) is distinct from 'object' then perform bl_moment_bad('path must look like {"trouble": {"min": 20}}'); end if;
    for s in select jsonb_object_keys(v) loop
      if s <> all (bl_path_keys()) then perform bl_moment_bad('unknown path score ' || s); end if;
      b := v -> s;
      if jsonb_typeof(b) is distinct from 'object' or exists (select 1 from jsonb_object_keys(b) x where x <> all (array['min', 'max'])) then
        perform bl_moment_bad('path ' || s || ' must look like {"min": 10, "max": 50}');
      end if;
      if (b ? 'min' and (jsonb_typeof(b -> 'min') is distinct from 'number' or (b ->> 'min')::numeric not between -100 and 100))
         or (b ? 'max' and (jsonb_typeof(b -> 'max') is distinct from 'number' or (b ->> 'max')::numeric not between -100 and 100)) then
        perform bl_moment_bad('path min and max are numbers from -100 to 100');
      end if;
    end loop;
  end if;
end $$;

create or replace function public.bl_story_cond_ok(c jsonb, p public.profiles, p_now timestamptz) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare k text; v jsonb; s text; b jsonb; n integer; r public.player_path; want boolean; v_have boolean;
begin
  if c ? 'partner' then
    want := (c ->> 'partner')::boolean;
    if want is distinct from exists (select 1 from love_relationships x where (x.user_a = p.id or x.user_b = p.id) and x.status = 'couple') then return false; end if;
  end if;
  if c ? 'kids' then
    want := (c ->> 'kids')::boolean;
    if want is distinct from exists (select 1 from kids_children kc where (kc.parent_a = p.id or kc.parent_b = p.id) and kc.status in ('home', 'university')) then return false; end if;
  end if;
  if c ? 'car' then
    want := (c ->> 'car')::boolean;
    if want is distinct from exists (select 1 from player_cars pc where pc.user_id = p.id) then return false; end if;
  end if;
  if c ? 'job' then
    want := (c ->> 'job')::boolean;
    if want is distinct from (p.job_id is not null) then return false; end if;
  end if;
  if c ? 'gang' then
    want := (c ->> 'gang')::boolean;
    if want is distinct from exists (select 1 from crew_members cm where cm.user_id = p.id) then return false; end if;
  end if;
  if c ? 'school' then
    want := (c ->> 'school')::boolean;
    if want is distinct from exists (select 1 from course_enrolments ce where ce.user_id = p.id and ce.status = 'enrolled') then return false; end if;
  end if;
  if c ? 'business' then
    want := (c ->> 'business')::boolean;
    if want is distinct from (exists (select 1 from businesses bz where bz.owner_id = p.id) or exists (select 1 from companies cp where cp.owner_id = p.id)) then return false; end if;
  end if;
  if c ? 'origin' and p.origin is distinct from (c ->> 'origin') then return false; end if;
  if c ? 'path' then
    select * into r from player_path where user_id = p.id;
    v_have := found;
    for s, b in select x.key, x.value from jsonb_each(c -> 'path') x loop
      n := case when v_have then bl_path_val(r, s) else 0 end;
      if b ? 'min' and n < (b ->> 'min')::numeric then return false; end if;
      if b ? 'max' and n > (b ->> 'max')::numeric then return false; end if;
    end loop;
  end if;
  return true;
end $$;

create or replace function public.bl_story_check_choice(c jsonb) returns void
language plpgsql stable set search_path = public as $$
declare o jsonb; k text; v_ids text[] := '{}'; i integer := 0;
begin
  if c ? 'path' then perform bl_story_check_path_delta(c -> 'path'); end if;
  if not (c ? 'outcomes') then return; end if;
  if jsonb_typeof(c -> 'outcomes') is distinct from 'array' or jsonb_array_length(c -> 'outcomes') not between 1 and 6 then
    perform bl_moment_bad('outcomes must be a list of 1 to 6');
  end if;
  for o in select * from jsonb_array_elements(c -> 'outcomes') loop
    i := i + 1;
    if jsonb_typeof(o) is distinct from 'object' then perform bl_moment_bad('an outcome must be a JSON object'); end if;
    for k in select jsonb_object_keys(o) loop
      if k <> all (array['id', 'w', 'text', 'tone', 'effects', 'requires', 'path_w']) then perform bl_moment_bad('unknown outcome field "' || k || '"'); end if;
    end loop;
    if o ? 'id' then
      if coalesce(o ->> 'id', '') !~ '^[a-z][a-z0-9_]{0,23}$' then perform bl_moment_bad('an outcome id uses lowercase letters, digits and _'); end if;
      if (o ->> 'id') = any (v_ids) then perform bl_moment_bad('two outcomes share the id ' || (o ->> 'id')); end if;
      v_ids := v_ids || (o ->> 'id');
    end if;
    if o ? 'w' and (jsonb_typeof(o -> 'w') is distinct from 'number' or (o ->> 'w')::numeric <= 0 or (o ->> 'w')::numeric > 1000) then perform bl_moment_bad('an outcome weight w is above 0, up to 1000'); end if;
    if char_length(coalesce(o ->> 'text', '')) not between 1 and 300 then perform bl_moment_bad('an outcome text is 1 to 300 characters'); end if;
    if coalesce(o ->> 'tone', 'good') not in ('good', 'bad', 'twist', 'funny', 'info') then perform bl_moment_bad('an outcome tone is good, bad, twist, funny or info'); end if;
    perform bl_moment_check_effects(o -> 'effects');
    if o ? 'requires' then perform bl_moment_check_conditions(o -> 'requires'); end if;
    if o ? 'path_w' then perform bl_story_check_pathw(o -> 'path_w'); end if;
  end loop;
end $$;

-- the row guard for stories: clean words in outcomes, no place or time conditions on a daily story, small cash gains
create or replace function public.bl_story_guard(m public.life_moments) returns void
language plpgsql stable set search_path = public as $$
declare c jsonb; o jsonb; e jsonb; v_cap numeric := bl_love_num('stories.max_cash_gain', 15000); v_limit boolean := m.kind in ('daily', 'chapter') or m.id like 'path\_%';
begin
  perform bl_story_check_pathw(m.path_w);
  if m.kind = 'daily' and (m.conditions ? 'at' or m.conditions ? 'hours') then
    perform bl_moment_bad('a daily story cannot use the "at" or "hours" conditions (the player can open it anywhere, any time)');
  end if;
  if m.kind = 'daily' and m.active and jsonb_array_length(m.choices) < 2 then
    perform bl_moment_bad('a daily story needs 2 to 4 choices');
  end if;
  for c in select * from jsonb_array_elements(m.choices) loop
    if c ? 'outcomes' and m.kind not in ('daily', 'chapter') then perform bl_moment_bad('outcomes are only for daily stories and chapters'); end if;
    if v_limit then
      for e in select * from jsonb_array_elements(coalesce(c -> 'effects', '[]'::jsonb) || coalesce(c -> 'fail_effects', '[]'::jsonb)) loop
        if e ->> 't' = 'cash' and (e ->> 'amount')::numeric > v_cap then perform bl_moment_bad('a story cash gain is above stories.max_cash_gain'); end if;
      end loop;
    end if;
    if c ? 'outcomes' then
      for o in select * from jsonb_array_elements(c -> 'outcomes') loop
        if bl_chat_mask(coalesce(o ->> 'text', '')) <> coalesce(o ->> 'text', '') then
          raise exception 'Keep the words clean: an outcome has a banned word.' using errcode = 'P0001', hint = 'blocked_text';
        end if;
        if v_limit then
          for e in select * from jsonb_array_elements(coalesce(o -> 'effects', '[]'::jsonb)) loop
            if e ->> 't' = 'cash' and (e ->> 'amount')::numeric > v_cap then perform bl_moment_bad('a story cash gain is above stories.max_cash_gain'); end if;
          end loop;
        end if;
      end loop;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Follow-ups (seeds), text, picking
-- ---------------------------------------------------------------------------------------------
-- seeds waiting for their day: scheduled moments and chapters not yet due
create or replace function public.bl_story_pending_seeds(p_uid uuid) returns integer
language sql stable security definer set search_path = public as $$
  select (select count(*) from player_moments x where x.user_id = p_uid and x.status = 'scheduled' and x.show_at > bl_now())::integer
       + (select count(*) from player_stories s where s.user_id = p_uid and s.kind = 'chapter' and s.status = 'pending' and s.show_at > bl_now())::integer
$$;

-- Does a follow_up effect fire? Its chance is cut to stories.followup_max_chance, and a player with too many waiting seeds gets no new one.
-- Doctor / school cards (kids kinds) are left exactly as written.
create or replace function public.bl_story_follow_ok(p_uid uuid, e jsonb) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_kind text; v_chance numeric := coalesce((e ->> 'chance')::numeric, 100);
begin
  select kind into v_kind from life_moments where id = e ->> 'moment';
  if v_kind is null then return false; end if;
  if v_kind in ('chapter', 'daily', 'system') then
    v_chance := least(v_chance, bl_love_num('stories.followup_max_chance', 100));
    if bl_story_pending_seeds(p_uid) >= bl_love_num('stories.followup_max_pending', 4)::integer then return false; end if;
  end if;
  return v_chance >= 100 or bl_rand() * 100 < v_chance;
end $$;

create or replace function public.bl_story_delay_hours(e jsonb) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare v_h numeric := coalesce((e ->> 'delay_hours')::numeric, 0); v_kind text;
begin
  select kind into v_kind from life_moments where id = e ->> 'moment';
  if v_kind in ('chapter', 'daily', 'system') then v_h := least(v_h, greatest(1, bl_love_num('stories.followup_max_days', 7)) * 24); end if;
  return greatest(0, v_h);
end $$;

-- A chapter (follow-up story) for a player, due at p_due. One waiting copy of the same chapter at a time.
create or replace function public.bl_story_create(p_uid uuid, p_story text, p_ctx jsonb default '{}'::jsonb, p_due timestamptz default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_now timestamptz := bl_now(); v_due timestamptz := coalesce(p_due, bl_now()); v_id bigint;
begin
  if p_uid is null or not exists (select 1 from life_moments where id = p_story) then return null; end if;
  if exists (select 1 from player_stories where user_id = p_uid and story_id = p_story and kind = 'chapter' and status = 'pending') then return null; end if;
  insert into player_stories (user_id, story_id, kind, day, slot, status, context, created_at, show_at)
  values (p_uid, p_story, 'chapter', bl_wat_date(v_due), 1, 'pending', coalesce(p_ctx, '{}'::jsonb), v_now, v_due)
  returning id into v_id;
  return v_id;
end $$;

-- {name}, {partner} (the real partner's name), {child} (the first child at home)
create or replace function public.bl_story_text(p_text text, p_uid uuid, p_ctx jsonb) returns text
language plpgsql stable security definer set search_path = public as $$
declare t text := p_text; v_partner text; v_child text;
begin
  if t is null or position('{' in t) = 0 then return t; end if;
  if position('{partner}' in t) > 0 then
    select pf.username into v_partner
      from love_relationships r join profiles pf on pf.id = case when r.user_a = p_uid then r.user_b else r.user_a end
     where (r.user_a = p_uid or r.user_b = p_uid) and r.status <> 'ended' order by (r.status = 'couple') desc, r.id desc limit 1;
    t := replace(t, '{partner}', coalesce(v_partner, 'your partner'));
  end if;
  if position('{child}' in t) > 0 then
    select k.name into v_child from kids_children k where (k.parent_a = p_uid or k.parent_b = p_uid) and k.status = 'home' and k.name is not null order by k.id limit 1;
    t := replace(t, '{child}', coalesce(v_child, 'your child'));
  end if;
  return bl_moment_text(t, p_uid, coalesce(p_ctx, '{}'::jsonb));
end $$;

create or replace function public.bl_story_frac(p_seed text) returns numeric
language sql immutable set search_path = public as $$
  select (('x' || substr(md5(p_seed), 1, 8))::bit(32)::bigint)::numeric / 4294967296
$$;

-- Today's story for a player: deterministic for the same player, day, slot and situation. Weighted by the story weight and the hidden path,
-- only stories the player qualifies for, never one seen within its cooldown (when everything was seen, the one seen longest ago).
create or replace function public.bl_story_pick(p_uid uuid, p_day date, p_slot integer) returns text
language plpgsql security definer set search_path = public as $$
declare
  p public.profiles; pr public.player_path; v_now timestamptz := bl_now(); m public.life_moments; v_sum numeric := 0; v_r numeric;
  v_min numeric := bl_love_num('stories.no_repeat_days', 30); v_seen date; v_pool text[] := '{}'; v_wts numeric[] := '{}'; v_alt text; v_alt_day date; i integer;
begin
  select * into p from profiles where id = p_uid;
  if not found then return null; end if;
  p := bl_decay_row(p, v_now);
  select * into pr from player_path where user_id = p_uid;
  for m in select * from life_moments l where l.active and l.kind = 'daily' and l.weight > 0 order by l.id loop
    if not bl_moment_ok(m, p, v_now) then continue; end if;
    select max(s.day) into v_seen from player_stories s
     where s.user_id = p_uid and s.story_id = m.id and (s.day < p_day or (s.day = p_day and s.slot <> p_slot));
    if v_seen is not null and p_day - v_seen < greatest(m.cooldown_days, v_min) then
      if v_seen < p_day and (v_alt is null or v_seen < v_alt_day) then v_alt := m.id; v_alt_day := v_seen; end if;
      continue;
    end if;
    v_pool := v_pool || m.id;
    v_wts := v_wts || (m.weight * bl_path_mult(pr, m.path_w));
    v_sum := v_sum + m.weight * bl_path_mult(pr, m.path_w);
  end loop;
  if v_sum > 0 then
    v_r := bl_story_frac(p_uid::text || ':' || p_day::text || ':' || p_slot::text) * v_sum;
    for i in 1..array_length(v_pool, 1) loop
      v_r := v_r - v_wts[i];
      if v_r < 0 then return v_pool[i]; end if;
    end loop;
    return v_pool[array_length(v_pool, 1)];
  end if;
  return v_alt;
end $$;

-- One story as the app shows it (effects, chances and path nudges stay on the server)
create or replace function public.bl_story_json(ps public.player_stories) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m public.life_moments; v_cash bigint; v_ch jsonb := '[]'::jsonb; c jsonb; v_cost bigint;
begin
  select * into m from life_moments where id = ps.story_id;
  select cash + greatest(bank, 0) into v_cash from profiles where id = ps.user_id;
  for c in select * from jsonb_array_elements(m.choices) loop
    v_cost := coalesce((c ->> 'cost')::bigint, 0);
    v_ch := v_ch || jsonb_build_object('id', c ->> 'id', 'label', bl_story_text(c ->> 'label', ps.user_id, ps.context), 'cost', v_cost, 'affordable', coalesce(v_cash, 0) >= v_cost);
  end loop;
  return jsonb_build_object('id', ps.id, 'story', m.id, 'kind', ps.kind, 'title', bl_story_text(m.title, ps.user_id, ps.context),
    'body', bl_story_text(m.body, ps.user_id, ps.context), 'icon', m.icon, 'speaker', m.speaker, 'choices', v_ch, 'status', ps.status,
    'day', ps.day, 'show_at', ps.show_at, 'result', case when ps.status = 'answered' then ps.result else null end);
end $$;

-- the day's stories exist (made on first look), and stale ones fade
create or replace function public.bl_story_ensure(p_uid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_now timestamptz := bl_now(); v_day date := bl_wat_date(v_now); v_per integer := greatest(1, least(3, bl_love_num('stories.per_day', 1)::integer)); v_slot integer; v_pick text;
begin
  update player_stories set status = 'expired' where user_id = p_uid and status = 'pending' and kind = 'daily' and day < v_day;
  update player_stories set status = 'expired'
   where user_id = p_uid and status = 'pending' and kind = 'chapter' and show_at < v_now - make_interval(days => greatest(1, bl_love_num('stories.chapter_expire_days', 7)::integer));
  for v_slot in 1..v_per loop
    continue when exists (select 1 from player_stories where user_id = p_uid and day = v_day and slot = v_slot and kind = 'daily');
    v_pick := bl_story_pick(p_uid, v_day, v_slot);
    if v_pick is not null then
      insert into player_stories (user_id, story_id, kind, day, slot, status, created_at, show_at)
      values (p_uid, v_pick, 'daily', v_day, v_slot, 'pending', v_now, v_now) on conflict do nothing;
    end if;
  end loop;
end $$;

-- the small number the app shows on the Stories icon (also read inside moments_pending)
create or replace function public.bl_story_badge(p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_now timestamptz := bl_now(); v_day date := bl_wat_date(v_now); v_per integer := greatest(1, least(3, bl_love_num('stories.per_day', 1)::integer)); v_done integer; v_ch integer;
begin
  if not coalesce(bl_cfg_bool('stories.daily_enabled'), true) then return jsonb_build_object('waiting', 0, 'daily', false, 'chapters', 0); end if;
  select count(*) into v_done from player_stories where user_id = p_uid and kind = 'daily' and day = v_day and status = 'answered';
  select count(*) into v_ch from player_stories where user_id = p_uid and kind = 'chapter' and status = 'pending' and show_at <= v_now
     and show_at > v_now - make_interval(days => greatest(1, bl_love_num('stories.chapter_expire_days', 7)::integer));
  return jsonb_build_object('waiting', greatest(0, v_per - v_done) + v_ch, 'daily', v_done < v_per, 'chapters', v_ch);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Answering: pay, nudge the path, pick the outcome (the twist), apply the effects, plant seeds, streak
-- ---------------------------------------------------------------------------------------------
-- the outcome of a choice: from its weighted `outcomes`, or (older style) its effects / chance / fail_effects
create or replace function public.bl_story_pick_outcome(p_uid uuid, ch jsonb, p public.profiles, pr public.player_path) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  o jsonb; m2 public.life_moments; v_w numeric; v_sum numeric := 0; v_r numeric; v_n integer := 0; v_ws numeric[] := '{}'; v_os jsonb[] := '{}'; i integer; v_luck integer := bl_path_val(pr, 'luck');
  v_ok boolean;
begin
  if not (ch ? 'outcomes') then
    v_ok := not (ch ? 'chance') or bl_rand() * 100 < (ch ->> 'chance')::numeric;
    return jsonb_build_object('id', case when v_ok then 'ok' else 'fail' end, 'tone', case when v_ok then 'good' else 'bad' end,
      'text', case when v_ok then ch ->> 'outcome' else coalesce(ch ->> 'fail_outcome', ch ->> 'outcome') end,
      'effects', case when v_ok then coalesce(ch -> 'effects', '[]'::jsonb) else coalesce(ch -> 'fail_effects', '[]'::jsonb) end);
  end if;
  for o in select * from jsonb_array_elements(ch -> 'outcomes') loop
    v_n := v_n + 1;
    if o ? 'requires' then
      m2.conditions := o -> 'requires';
      if not bl_moment_ok(m2, p, bl_now()) then continue; end if;
    end if;
    v_w := coalesce((o ->> 'w')::numeric, 1) * bl_path_mult(pr, o -> 'path_w') * bl_story_luck_mult(v_luck, coalesce(o ->> 'tone', 'good'));
    v_ws := v_ws || v_w; v_os := v_os || (o || jsonb_build_object('n', v_n)); v_sum := v_sum + v_w;
  end loop;
  if v_sum <= 0 then
    -- nothing qualified: the first outcome as written
    o := (ch -> 'outcomes') -> 0;
    return jsonb_build_object('id', coalesce(o ->> 'id', 'o1'), 'tone', coalesce(o ->> 'tone', 'good'), 'text', o ->> 'text', 'effects', coalesce(o -> 'effects', '[]'::jsonb));
  end if;
  v_r := bl_rand() * v_sum;
  for i in 1..array_length(v_os, 1) loop
    o := v_os[i];
    v_r := v_r - v_ws[i];
    exit when v_r < 0;
  end loop;
  return jsonb_build_object('id', coalesce(o ->> 'id', 'o' || (o ->> 'n')), 'tone', coalesce(o ->> 'tone', 'good'), 'text', o ->> 'text', 'effects', coalesce(o -> 'effects', '[]'::jsonb));
end $$;

-- Apply an outcome's effects through the SAME applier the pop-ups use. Cash gains are cut to stories.max_cash_gain and to what is left of
-- stories.daily_gain_cap today. Returns the chip lines, whether a seed was planted, and the cash that was given.
create or replace function public.bl_story_apply(p_uid uuid, p_story text, p_ctx jsonb, p_effects jsonb, p_label text,
                                                 out o_lines jsonb, out o_seeded boolean, out o_gain bigint)
language plpgsql security definer set search_path = public as $$
declare
  e jsonb; v_out jsonb := '[]'::jsonb; v_max numeric := bl_love_num('stories.max_cash_gain', 15000); v_left numeric; v_amt numeric; pm public.player_moments; v_before integer;
begin
  o_gain := 0;
  select greatest(0, bl_love_num('stories.daily_gain_cap', 25000) - coalesce(sum((s.result ->> 'gain')::numeric), 0)) into v_left
    from player_stories s where s.user_id = p_uid and s.answered_at >= bl_moment_day_start(bl_now()) and s.status = 'answered';
  for e in select * from jsonb_array_elements(coalesce(p_effects, '[]'::jsonb)) loop
    if e ->> 't' = 'cash' and (e ->> 'amount')::numeric > 0 then
      v_amt := least((e ->> 'amount')::numeric, v_max, v_left - o_gain);
      continue when v_amt <= 0;
      e := jsonb_set(e, '{amount}', to_jsonb(trunc(v_amt)::bigint));
      o_gain := o_gain + trunc(v_amt)::bigint;
    end if;
    v_out := v_out || e;
  end loop;
  pm.user_id := p_uid; pm.moment_id := p_story; pm.context := coalesce(p_ctx, '{}'::jsonb);
  v_before := bl_story_pending_seeds(p_uid);
  o_lines := bl_moment_apply(p_uid, pm, v_out, p_label);
  o_seeded := bl_story_pending_seeds(p_uid) > v_before;
end $$;

-- The reading streak: a day counts when the daily story is answered. Pays each reached step once per streak.
create or replace function public.bl_story_streak_touch(p_uid uuid, p_day date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  st public.story_streak; v_paid jsonb := '[]'::jsonb; i integer; v_days integer; v_cash bigint; v_total bigint := 0;
begin
  insert into story_streak (user_id) values (p_uid) on conflict (user_id) do nothing;
  select * into st from story_streak where user_id = p_uid for update;
  if st.last_day is distinct from p_day then
    if st.last_day = p_day - 1 then st.streak := st.streak + 1; else st.streak := 1; st.claimed := '[]'::jsonb; end if;
    st.last_day := p_day; st.best := greatest(st.best, st.streak);
  end if;
  for i in 1..3 loop
    v_days := bl_love_num('stories.streak_days_' || i, case i when 1 then 3 when 2 then 7 else 14 end)::integer;
    v_cash := greatest(0, bl_love_num('stories.streak_cash_' || i, case i when 1 then 2000 when 2 then 5000 else 12000 end))::bigint;
    if st.streak >= v_days and not (st.claimed @> to_jsonb(v_days)) then
      st.claimed := st.claimed || to_jsonb(v_days);
      if v_cash > 0 then
        perform bl_add_money(p_uid, 'cash', v_cash, 'life_moment', jsonb_build_object('label', 'Story streak (' || v_days || ' days)', 'moment', 'story_streak'));
        v_total := v_total + v_cash;
      end if;
      v_paid := v_paid || jsonb_build_object('days', v_days, 'cash', v_cash);
    end if;
  end loop;
  update story_streak set last_day = st.last_day, streak = st.streak, best = st.best, claimed = st.claimed, updated_at = bl_now() where user_id = p_uid;
  return jsonb_build_object('streak', st.streak, 'best', st.best, 'paid', v_paid, 'cash', v_total);
end $$;

create or replace function public.bl_story_streak_json(p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st public.story_streak; v_day date := bl_wat_date(bl_now()); v_now_streak integer := 0; v_steps jsonb := '[]'::jsonb; i integer; v_days integer; v_cash bigint; v_next jsonb; v_have boolean;
begin
  select * into st from story_streak where user_id = p_uid;
  v_have := found;
  if v_have and st.last_day is not null and st.last_day >= v_day - 1 then v_now_streak := st.streak; end if;
  for i in 1..3 loop
    v_days := bl_love_num('stories.streak_days_' || i, case i when 1 then 3 when 2 then 7 else 14 end)::integer;
    v_cash := greatest(0, bl_love_num('stories.streak_cash_' || i, case i when 1 then 2000 when 2 then 5000 else 12000 end))::bigint;
    v_steps := v_steps || jsonb_build_object('days', v_days, 'cash', v_cash, 'reached', v_now_streak >= v_days,
                                              'claimed', v_have and v_now_streak >= v_days and st.claimed @> to_jsonb(v_days));
    if v_next is null and v_now_streak < v_days then v_next := jsonb_build_object('days', v_days, 'cash', v_cash, 'left', v_days - v_now_streak); end if;
  end loop;
  return jsonb_build_object('streak', v_now_streak, 'best', case when v_have then st.best else 0 end, 'read_today', v_have and st.last_day = v_day,
                            'steps', v_steps, 'next', v_next);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.story_today() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_now timestamptz := bl_now(); v_day date := bl_wat_date(v_now); ps public.player_stories; v_today jsonb := '[]'::jsonb; v_ch jsonb := '[]'::jsonb;
begin
  if not exists (select 1 from profiles where id = v_uid) or not coalesce(bl_cfg_bool('stories.daily_enabled'), true) then
    return jsonb_build_object('enabled', false, 'day', v_day);
  end if;
  perform bl_story_ensure(v_uid);
  for ps in select * from player_stories s where s.user_id = v_uid and s.kind = 'daily' and s.day = v_day order by s.slot loop
    v_today := v_today || bl_story_json(ps);
  end loop;
  for ps in select * from player_stories s where s.user_id = v_uid and s.kind = 'chapter' and s.status = 'pending' and s.show_at <= v_now order by s.show_at, s.id limit 5 loop
    v_ch := v_ch || bl_story_json(ps);
  end loop;
  return jsonb_build_object('enabled', true, 'day', v_day, 'today', v_today, 'chapters', v_ch, 'streak', bl_story_streak_json(v_uid),
                            'path', bl_path_describe(v_uid), 'badge', bl_story_badge(v_uid));
end $$;

create or replace function public.story_answer(p_story bigint, p_choice text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_now timestamptz := bl_now(); v_day date := bl_wat_date(v_now); ps public.player_stories; m public.life_moments; ch jsonb; v_cost bigint;
  p public.profiles; pr public.player_path; b public.player_path; oc jsonb; ap record; v_lines jsonb := '[]'::jsonb; v_text text; v_whisper text; v_streak jsonb := null;
  v_label text; v_result jsonb; v_nudge jsonb;
begin
  if not coalesce(bl_cfg_bool('stories.daily_enabled'), true) then
    raise exception 'Stories are paused for now.' using errcode = 'P0001', hint = 'stories_off';
  end if;
  select * into ps from player_stories where id = p_story and user_id = v_uid for update;
  if not found then raise exception 'That story is gone.' using errcode = 'P0001', hint = 'no_story'; end if;
  if ps.status = 'answered' then raise exception 'You already chose for this one.' using errcode = 'P0001', hint = 'already_answered'; end if;
  if ps.status = 'expired' or (ps.kind = 'daily' and ps.day < v_day) then
    update player_stories set status = 'expired' where id = ps.id and status = 'pending';
    raise exception 'That story has passed. A new one is waiting.' using errcode = 'P0001', hint = 'expired';
  end if;
  if ps.show_at > v_now then raise exception 'It is not time for that yet.' using errcode = 'P0001', hint = 'not_yet'; end if;
  select * into m from life_moments where id = ps.story_id;
  select x into ch from jsonb_array_elements(m.choices) x where x ->> 'id' = p_choice;
  if ch is null then raise exception 'Pick one of the choices.' using errcode = 'P0001', hint = 'bad_choice'; end if;
  select * into p from profiles where id = v_uid;
  v_label := bl_story_text(m.title, v_uid, ps.context);
  v_cost := coalesce((ch ->> 'cost')::bigint, 0);
  if v_cost > 0 then
    perform bl_sink_pay(v_uid, v_cost, 'life_moment', jsonb_build_object('label', v_label, 'moment', m.id, 'choice', p_choice));
  end if;
  b := bl_path_get(v_uid);
  -- the intent counts: the choice's own nudge always lands, whatever the outcome
  v_nudge := bl_path_nudge(v_uid, ch -> 'path');
  select * into pr from player_path where user_id = v_uid;
  oc := bl_story_pick_outcome(v_uid, ch, p, pr);
  select * into ap from bl_story_apply(v_uid, m.id, ps.context, oc -> 'effects', v_label);
  v_lines := ap.o_lines;
  v_text := bl_story_text(oc ->> 'text', v_uid, ps.context);
  v_whisper := bl_path_whisper(v_uid, b);
  if ps.kind = 'daily' then v_streak := bl_story_streak_touch(v_uid, v_day); end if;
  v_result := jsonb_build_object('text', v_text, 'tone', oc ->> 'tone', 'outcome', oc ->> 'id', 'choice', p_choice, 'choice_label', bl_story_text(ch ->> 'label', v_uid, ps.context),
                                 'effects', v_lines, 'seed', ap.o_seeded, 'whisper', v_whisper, 'spent', v_cost, 'gain', ap.o_gain, 'icon', m.icon,
                                 'streak', v_streak);
  update player_stories set status = 'answered', answered_at = v_now, choice_id = p_choice, outcome_id = oc ->> 'id', result = v_result where id = ps.id returning * into ps;
  return jsonb_build_object('story', bl_story_json(ps), 'reveal', v_result, 'streak', bl_story_streak_json(v_uid), 'path', bl_path_describe(v_uid), 'badge', bl_story_badge(v_uid));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Small effects elsewhere: blessing and police scenes replace a normal Life moment roll (patched into bl_moment_roll)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_path_special(p_uid uuid, p_pick text, p_now timestamptz) returns text
language plpgsql security definer set search_path = public as $$
declare
  r public.player_path; v_min integer := greatest(1, bl_love_num('stories.special_min_score', 25)::integer); v_ids text[]; v_prefix text; v_pct numeric; v_cd numeric;
begin
  if not coalesce(bl_cfg_bool('stories.daily_enabled'), true) then return p_pick; end if;
  select * into r from player_path where user_id = p_uid;
  if not found then return p_pick; end if;
  for v_prefix, v_pct, v_cd in
    select * from (values ('path\_blessing%', bl_love_num('stories.blessing_pct', 4), bl_love_num('stories.blessing_cooldown_days', 5)),
                          ('path\_police%',   bl_love_num('stories.police_pct', 4),   bl_love_num('stories.police_cooldown_days', 6))) x(a, b, c)
     order by case when x.a like 'path\_blessing%' then 0 else 1 end
  loop
    continue when v_pct <= 0;
    continue when (v_prefix like 'path\_blessing%' and r.goodwill < v_min) or (v_prefix like 'path\_police%' and r.trouble < v_min);
    continue when exists (select 1 from player_moments x where x.user_id = p_uid and x.moment_id like v_prefix and x.created_at > p_now - make_interval(secs => (v_cd * 86400)::double precision));
    if bl_rand() * 100 < v_pct then
      select array_agg(l.id order by l.id) into v_ids from life_moments l where l.active and l.kind = 'system' and l.id like v_prefix and bl_moment_ok(l, (select pf from profiles pf where pf.id = p_uid), p_now);
      if v_ids is not null then return v_ids[1 + least(array_length(v_ids, 1) - 1, floor(bl_rand() * array_length(v_ids, 1))::integer)]; end if;
    end if;
  end loop;
  return p_pick;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. Push: "your story is waiting" (called from bl_push_tick, the every-minute push job)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_story_push_tick() returns integer
language plpgsql security definer set search_path = public as $$
declare v_n integer := 0; u record; v_now timestamptz := bl_now(); v_today date := bl_wat_date(v_now); v_key text := 'story:' || bl_wat_date(bl_now());
begin
  if not (coalesce(bl_cfg_bool('push.enabled'), false) and coalesce(bl_cfg_bool('push.cat_events'), false)
          and coalesce(bl_cfg_bool('stories.daily_enabled'), true) and coalesce(bl_cfg_bool('stories.push_enabled'), true)) then
    return 0;
  end if;
  if extract(hour from (v_now at time zone bl_clock_tz())) >= bl_love_num('stories.push_hour', 17) then
    for u in
      select pp.user_id from push_prefs pp join profiles pf on pf.id = pp.user_id
       where pp.master and pp.events and not pf.banned and pf.last_seen > v_now - interval '3 days'
         and exists (select 1 from push_subscriptions ps where ps.user_id = pp.user_id)
         and not exists (select 1 from player_stories s where s.user_id = pp.user_id and s.kind = 'daily' and s.day = v_today and s.status = 'answered')
         and not exists (select 1 from push_outbox o where o.user_id = pp.user_id and o.dedupe_key = v_key)
       limit greatest(1, bl_love_num('stories.push_max_per_tick', 300))::integer
    loop
      if bl_push_enqueue(u.user_id, 'events', 'story_daily', '📖 Your story for today is waiting',
                         'Something small is happening in Benin City. What will you do?', '/play?go=stories', null, null, null, v_key) is not null then
        v_n := v_n + 1;
      end if;
    end loop;
  end if;
  for u in
    select s.id, s.user_id from player_stories s
     where s.kind = 'chapter' and s.status = 'pending' and s.show_at <= v_now and s.show_at > v_now - interval '2 days'
       and not exists (select 1 from push_outbox o where o.user_id = s.user_id and o.dedupe_key = 'storych:' || s.id)
     limit 300
  loop
    if bl_push_enqueue(u.user_id, 'events', 'story_chapter', '📖 Your story continues',
                       'Remember what you did a few days ago? It is not over yet.', '/play?go=stories', null, null, null, 'storych:' || u.id) is not null then
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
exception when others then
  return 0;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. Patches on live functions (guarded, written against the CURRENT definitions)
-- ---------------------------------------------------------------------------------------------
-- conditions: partner, kids, car, job, gang, school, business, origin, path
select pg_temp.ds_patch('public.bl_moment_check_conditions(jsonb)',
  E'    else\n      perform bl_moment_bad(''unknown condition "'' || k || ''"'');',
  E'    elsif k in (''partner'', ''kids'', ''car'', ''job'', ''gang'', ''school'', ''business'', ''origin'', ''path'') then\n      perform bl_story_check_cond(k, v);\n    else\n      perform bl_moment_bad(''unknown condition "'' || k || ''"'');',
  'bl_story_check_cond(');
select pg_temp.ds_patch('public.bl_moment_ok(public.life_moments, public.profiles, timestamptz)',
  E'  return true;\nend $function$',
  E'  if not bl_story_cond_ok(c, p, p_now) then return false; end if;\n  return true;\nend $function$',
  'bl_story_cond_ok(');
-- effects: path { delta }
select pg_temp.ds_patch('public.bl_moment_check_effect(jsonb)',
  E'    else\n      perform bl_moment_bad(''unknown effect type "'' || coalesce(t, ''?'') || ''"'');',
  E'    when ''path'' then\n      perform bl_story_check_path_delta(e -> ''delta'');\n    else\n      perform bl_moment_bad(''unknown effect type "'' || coalesce(t, ''?'') || ''"'');',
  'bl_story_check_path_delta(');
select pg_temp.ds_patch('public.bl_moment_apply(uuid, public.player_moments, jsonb, text)',
  E'    elsif t = ''follow_up'' then',
  E'    elsif t = ''path'' then\n      perform bl_path_nudge(p_uid, e -> ''delta'');\n    elsif t = ''follow_up'' then',
  'bl_path_nudge(');
select pg_temp.ds_patch('public.bl_moment_apply(uuid, public.player_moments, jsonb, text)',
  E'      if coalesce((e ->> ''chance'')::numeric, 100) >= 100 or bl_rand() * 100 < (e ->> ''chance'')::numeric then',
  E'      if bl_story_follow_ok(p_uid, e) then',
  'bl_story_follow_ok(');
select pg_temp.ds_patch('public.bl_moment_apply(uuid, public.player_moments, jsonb, text)',
  E'        v_due := bl_now() + make_interval(secs => (coalesce((e ->> ''delay_hours'')::numeric, 0) * 3600)::double precision);',
  E'        v_due := bl_now() + make_interval(secs => (bl_story_delay_hours(e) * 3600)::double precision);',
  'bl_story_delay_hours(');
-- choices: path and outcomes
select pg_temp.ds_patch('public.bl_moment_check_choices(jsonb)',
  E'''next_delay_hours'', ''next_chance'']) then',
  E'''next_delay_hours'', ''next_chance'', ''path'', ''outcomes'']) then',
  '''path'', ''outcomes''])');
select pg_temp.ds_patch('public.bl_moment_check_choices(jsonb)',
  E'    if char_length(coalesce(c ->> ''outcome'', '''')) not between 1 and 300 then',
  E'    if not (c ? ''outcomes'') and char_length(coalesce(c ->> ''outcome'', '''')) not between 1 and 300 then',
  'not (c ? ''outcomes'') and char_length');
select pg_temp.ds_patch('public.bl_moment_check_choices(jsonb)',
  E'    perform bl_moment_check_effects(c -> ''effects'');',
  E'    perform bl_story_check_choice(c);\n    perform bl_moment_check_effects(c -> ''effects'');',
  'bl_story_check_choice(');
select pg_temp.ds_patch('public.bl_moments_guard()',
  E'  perform bl_moment_check_choices(new.choices);',
  E'  perform bl_moment_check_choices(new.choices);\n  perform bl_story_guard(new);',
  'bl_story_guard(');
-- a chapter becomes a story card, not a pop-up
select pg_temp.ds_patch('public.bl_moment_create(uuid, text, jsonb, timestamptz, boolean)',
  E'  if p_uid is null or not exists (select 1 from life_moments where id = p_moment) then return null; end if;',
  E'  if p_uid is null or not exists (select 1 from life_moments where id = p_moment) then return null; end if;\n  if (select kind from life_moments where id = p_moment) in (''chapter'', ''daily'') then return bl_story_create(p_uid, p_moment, p_ctx, p_due); end if;',
  'bl_story_create(');
-- luck leans a pop-up choice's chance, a little
select pg_temp.ds_patch('public.moments_answer(bigint, text)',
  E'  v_ok := not (ch ? ''chance'') or bl_rand() * 100 < (ch ->> ''chance'')::numeric;',
  E'  v_ok := not (ch ? ''chance'') or bl_rand() * 100 < bl_story_luck_chance(v_uid, (ch ->> ''chance'')::numeric, m.kind);',
  'bl_story_luck_chance(');
-- the badge rides on the one cheap poll
select pg_temp.ds_patch('public.moments_pending()',
  E'''snooze_hours'', bl_love_num(''moments.snooze_hours'', 2));',
  E'''snooze_hours'', bl_love_num(''moments.snooze_hours'', 2)) || jsonb_build_object(''story'', bl_story_badge(v_uid));',
  'bl_story_badge(');
-- a blessing or a police scene can replace the rolled moment
select pg_temp.ds_patch('public.bl_moment_roll(uuid)',
  E'  if v_pick is null then return null; end if;',
  E'  v_pick := bl_path_special(p_uid, v_pick, v_now);\n  if v_pick is null then return null; end if;',
  'bl_path_special(');
-- the push job
select pg_temp.ds_patch('public.bl_push_tick()',
  E'jsonb_build_object(''kids_swept'', bl_kids_alert_sweep());',
  E'jsonb_build_object(''kids_swept'', bl_kids_alert_sweep())\n         || jsonb_build_object(''stories_pushed'', bl_story_push_tick());',
  'bl_story_push_tick(');
-- Admin Content editors: the story columns and the path words
select pg_temp.ds_patch('public.bl_admin_table_spec(text)',
  E'"conditions":"obj","choices":"jarr",',
  E'"conditions":"obj","path_w":"obj","choices":"jarr",',
  '"path_w":"obj"');
select pg_temp.ds_patch('public.bl_admin_table_spec(text)',
  E'when ''life_moments'' then',
  E'when ''path_lines'' then ''{"pk":["id"],"insert":true,"order":"score, sign, band",\n      "cols":{"score":"text","sign":"int","band":"int","word":"text","whisper":"text","sort":"int","active":"bool"}}''\n    when ''life_moments'' then',
  '''path_lines''');

-- ---------------------------------------------------------------------------------------------
-- 11. The path words (admin-editable, Content -> Path words)
-- ---------------------------------------------------------------------------------------------
insert into public.path_lines (id, score, sign, band, word, whisper, sort) values
('goodwill_up_1', 'goodwill',  1, 1, 'kind',               'People around Ugbowo are starting to trust you.', 10),
('goodwill_up_2', 'goodwill',  1, 2, 'generous',           'Neighbours greet you like family now. Your name travels before you.', 11),
('goodwill_dn_1', 'goodwill', -1, 1, 'self-first',         'Some people think you only look out for yourself.', 12),
('goodwill_dn_2', 'goodwill', -1, 2, 'cold',               'Word is going round that you take more than you give.', 13),
('hustle_up_1',   'hustle',    1, 1, 'hustler',            'You are getting a name for taking big chances.', 20),
('hustle_up_2',   'hustle',    1, 2, 'fearless hustler',   'Everybody on Ring Road knows you chase every opportunity.', 21),
('hustle_dn_1',   'hustle',   -1, 1, 'careful planner',    'People say you think twice before you move.', 22),
('hustle_dn_2',   'hustle',   -1, 2, 'patient planner',    'They call you the one who never rushes, and never regrets.', 23),
('luck_up_1',     'luck',      1, 1, 'with a bit of luck', 'Lately things just seem to fall your way.', 30),
('luck_up_2',     'luck',      1, 2, 'blessed with luck',  'Even the traffic seems to open for you these days.', 31),
('luck_dn_1',     'luck',     -1, 1, 'who cannot catch a break', 'Lately small things keep going wrong for you.', 32),
('luck_dn_2',     'luck',     -1, 2, 'walking under a small dark cloud', 'It feels like a little cloud follows you around.', 33),
('trouble_up_1',  'trouble',   1, 1, 'corner-cutting',     'You have got a reputation for cutting corners.', 40),
('trouble_up_2',  'trouble',   1, 2, 'shady',              'Some officers around Ring Road seem to know your face.', 41),
('trouble_dn_1',  'trouble',  -1, 1, 'straight',           'You are known as someone who plays by the rules.', 42),
('trouble_dn_2',  'trouble',  -1, 2, 'upright',            'Elders in the area point to you as an example.', 43),
('faith_up_1',    'faith',     1, 1, 'faithful',           'You feel steadier lately. Your prayers feel heard.', 50),
('faith_up_2',    'faith',     1, 2, 'deeply faithful',    'Your faith is the first thing people notice about you.', 51),
('faith_dn_1',    'faith',    -1, 1, 'doubting',           'You have been questioning a lot of things lately.', 52),
('faith_dn_2',    'faith',    -1, 2, 'sceptical',          'People say you believe only what you can see.', 53),
('family_up_1',   'family',    1, 1, 'family-minded',      'Your people lean on you, and you carry them well.', 60),
('family_up_2',   'family',    1, 2, 'family-first',       'The whole family calls you first when anything happens.', 61),
('family_dn_1',   'family',   -1, 1, 'independent',        'Your relatives say they hardly see you these days.', 62),
('family_dn_2',   'family',   -1, 2, 'lone',               'You are fast becoming the relative who never picks up.', 63)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 12. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'bl\_path%' or proname like 'bl\_story%') loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and proname in ('story_today', 'story_answer') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated', p.sig);
  end loop;
end $$;
notify pgrst, 'reload schema';
