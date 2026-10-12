-- D2 Link-ups: the dating lifestyle (docs/LINKUPS.md, owner-approved spec docs/LIFESTYLE_PLAN.md section 3).
-- HARD RULES (keep them in any edit): adults only (every NPC is 21-40, enforced by a check); NPC characters ONLY, never
-- another player (no RPC here takes a player id, the target is always a linkup_npcs id); nothing explicit: the hotel
-- actions are fade-to-black ("The night goes on...") and the copy never describes anything intimate.
-- * linkup_npcs: a small pool of adult NPCs (name, age, vibe, likes / hates, look, how picky). A few of them are "out
--   tonight" at each club (a stable pick per club per night), filtered by the player's link-up preference (men / women /
--   anyone, linkup_players.want, Settings on the Sim sheet + the Link-ups app).
-- * linkup_actions (admin-editable, prices EXACT from the spec): Buy drinks N10,000 (clubs, roll yes / no), Dinner date
--   N30,000 (hotel restaurants + mall food court), Short time N15,000, Overnight N45,000, Weekend getaway N350,000
--   (Big Boy+ via bl_yahoo_rank_at_least) at the hotel suites. Dinner and the hotel need a "yes" (a link-up) from that NPC
--   first, or that NPC being your partner.
-- * Drinks yes chance: linkup.drinks_yes_pct (45) + NPC pickiness + attraction charm (bl_charm_value(uid,'attraction'))
--   + Yahoo rank steps + street cred + looks (hygiene) + spark, clamped (5..95), fixed at start, rolled with bl_rand().
-- * Spark (0-100) per NPC. Enough dinner dates and spark with one NPC = you two are an item (linkup_people.steady):
--   the player's "in a relationship" flag (there was no relationship system before).
-- * Morning after a hotel action: 10 % your cash goes missing (a share, capped; ledger "Link-up gone wrong"; never with
--   your own partner), and if you are in a relationship with someone else, a chance they find out: it ends + mood hit.
-- Idempotent and safe on a non-empty DB: seeds use "on conflict do nothing" (admin edits survive a re-run), live functions
-- are patched from pg_get_functiondef with guarded replacements (create or replace keeps the grants).

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (category linkup)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('linkup.enabled', 'true', 'linkup', 'Link-ups on',
 'D2: the dating life with NPCs (clubs, dinner dates, hotels; fade to black). Off = the Link-ups app is hidden and every link-up action is refused.', 'bool', null, null),
('linkup.drinks_yes_pct', '45', 'linkup', 'Buy drinks: base chance of a yes',
 'D2: chance an NPC says yes after you buy them drinks, before pickiness, the attraction charm, Yahoo rank, street cred, looks and spark.', 'percent', 0, 100),
('linkup.yes_floor_pct', '5', 'linkup', 'Lowest yes chance',
 'D2: the yes chance never drops below this.', 'percent', 0, 100),
('linkup.yes_cap_pct', '95', 'linkup', 'Highest yes chance',
 'D2: the yes chance never goes above this (charms included).', 'percent', 0, 100),
('linkup.rank_bonus_pts', '3', 'linkup', 'Yahoo rank: + yes points per rank',
 'D2: each Yahoo rank above Aspirant adds this many points to the yes chance (G-boy 1x, Big Boy 2x, Chairman 3x).', 'number', 0, 100),
('linkup.cred_per_pt', '10', 'linkup', 'Street cred per + 1 yes point',
 'D2: every this-much street cred (hype) adds 1 point to the yes chance, up to linkup.cred_bonus_cap.', 'number', 1, 100000),
('linkup.cred_bonus_cap', '5', 'linkup', 'Street cred: most yes points',
 'D2: the street cred bonus never adds more than this.', 'number', 0, 100),
('linkup.fresh_hygiene', '60', 'linkup', 'Looks: fresh from this hygiene',
 'D2: hygiene at or above this counts as looking fresh (linkup.fresh_pts more yes chance).', 'number', 0, 100),
('linkup.fresh_pts', '5', 'linkup', 'Looks: fresh bonus points',
 'D2: yes chance points for looking fresh.', 'number', 0, 100),
('linkup.smelly_hygiene', '25', 'linkup', 'Looks: rough below this hygiene',
 'D2: hygiene below this counts as looking rough (linkup.smelly_pts less yes chance).', 'number', 0, 100),
('linkup.smelly_pts', '15', 'linkup', 'Looks: rough penalty points',
 'D2: yes chance points lost for looking rough.', 'number', 0, 100),
('linkup.spark_div', '5', 'linkup', 'Spark per + 1 yes point',
 'D2: every this-much spark with that NPC adds 1 point to the yes chance (spark 50 = +10 by default).', 'number', 1, 100),
('linkup.yes_minutes', '120', 'linkup', 'A yes lasts (real minutes)',
 'D2: how long a yes (the link-up) stays open for dinner / hotel. A dinner date starts the clock again.', 'number', 1, 10080),
('linkup.no_cooldown_seconds', '120', 'linkup', 'After a no: wait (seconds)',
 'D2: after an NPC says no, you can buy them drinks again after this many seconds.', 'number', 0, 86400),
('linkup.npcs_per_place', '4', 'linkup', 'People out per club',
 'D2: how many link-up NPCs are out at each club each night (a stable pick per club per night, from the people the player is into).', 'number', 1, 50),
('linkup.getaway_rank', '"big_boy"', 'linkup', 'Weekend getaway: lowest Yahoo rank',
 'D2: the Yahoo rank id needed for actions that have a rank (default: the weekend getaway, Big Boy and up).', 'text', null, null),
('linkup.robbed_pct', '10', 'linkup', 'Morning after: chance your cash is missing',
 'D2: after a hotel link-up (not with your own partner), the chance you wake up and part of your cash is gone.', 'percent', 0, 100),
('linkup.robbed_share_pct', '30', 'linkup', 'Morning after: share of cash missing',
 'D2: how much of your cash goes missing when it happens.', 'percent', 0, 100),
('linkup.robbed_cap', '100000', 'linkup', 'Morning after: most cash missing',
 'D2: the most cash that can go missing in one morning.', 'naira', 0, 1000000000000),
('linkup.steady_dinners', '3', 'linkup', 'Partner: dinner dates needed',
 'D2: dinner dates with the same NPC (and linkup.steady_spark spark) before you become an item. One partner at a time.', 'number', 1, 100),
('linkup.steady_spark', '60', 'linkup', 'Partner: spark needed',
 'D2: spark with that NPC needed before you become an item.', 'number', 0, 100),
('linkup.caught_pct', '35', 'linkup', 'Partner finds out: chance',
 'D2: when you are in a relationship and have a hotel link-up with someone else, the chance your partner finds out (the relationship ends).', 'percent', 0, 100),
('linkup.breakup_fun', '-30', 'linkup', 'Break-up: fun change',
 'D2: what a break-up does to fun (negative = down).', 'number', -100, 100),
('linkup.breakup_social', '-25', 'linkup', 'Break-up: social change',
 'D2: what a break-up does to social.', 'number', -100, 100),
('linkup.breakup_stress', '30', 'linkup', 'Break-up: stress change',
 'D2: what a break-up does to stress (positive = more stress).', 'number', -100, 100),
('linkup.breakup_spark_loss', '50', 'linkup', 'Break-up: spark lost',
 'D2: spark your ex loses with you after they find out.', 'number', 0, 100),
('linkup.ex_cooloff_hours', '24', 'linkup', 'Break-up: ex won''t talk to you (hours)',
 'D2: real hours before your ex will take drinks from you again.', 'number', 0, 8760)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
-- What you can do (prices exact from the spec; every number admin-editable in Content -> Link-up actions).
create table if not exists public.linkup_actions (
  id         text primary key,
  name       text not null,
  icon       text not null default '💞',
  blurb      text not null default '',
  kind       text not null check (kind in ('drinks', 'date', 'hotel')),
  price      bigint not null default 0 check (price >= 0),
  seconds    int not null default 10 check (seconds between 1 and 3600),
  effects    jsonb not null default '{}'::jsonb,
  spark      int not null default 0 check (spark between 0 and 100),
  needs_yes  boolean not null default true,
  scenes     text[] not null default '{}',
  min_rank   text,
  morning    boolean not null default false,
  line       text not null default '',
  sort       int not null default 0,
  active     boolean not null default true
);

insert into public.linkup_actions (id, name, icon, blurb, kind, price, seconds, effects, spark, needs_yes, scenes, min_rank, morning, line, sort) values
('drinks', 'Buy drinks for someone', '🍸', 'Send a drink their way and shoot your shot. They fit say yes… or no.', 'drinks',
 10000, 8, '{"fun": 8, "social": 10, "bladder": -6}', 10, false, '{club}', null, false,
 'You send two chilled glasses over and start the gist…', 1),
('dinner', 'Dinner date', '🍽️', 'Take your link-up out to eat. Good food, better gist. Spark go rise.', 'date',
 30000, 14, '{"fun": 25, "social": 35, "hunger": 40, "stress": -10}', 15, true, '{hotel,mall}', null, false,
 'Candle on the table, jollof on the plate, gist on top gist…', 2),
('short_time', 'Short time', '🌙', 'A quiet room for a couple of hours. Fade to black.', 'hotel',
 15000, 12, '{"fun": 30, "stress": -25}', 8, true, '{hotel}', null, true,
 'The door closes. The night goes on… ☾', 3),
('overnight', 'Overnight', '🛏️', 'Book the room till morning. Bigger boost. Fade to black.', 'hotel',
 45000, 20, '{"fun": 45, "stress": -40, "social": 20, "energy": 35}', 15, true, '{hotel}', null, true,
 'The lights go low. The night goes on… ☾', 4),
('getaway', 'Weekend getaway', '🏝️', 'Big Boy level: suite, pool, room service, the whole weekend. Everybody go hear.', 'hotel',
 350000, 30, '{"fun": 80, "stress": -70, "social": 50, "energy": 40, "street_cred": 6}', 30, true, '{hotel}', 'big_boy', true,
 'Suite booked, phone on silent. The weekend goes on… ☾', 5)
on conflict (id) do nothing;

-- The people you can link up with. Adults only (21-40, enforced).
create table if not exists public.linkup_npcs (
  id         text primary key,
  name       text not null,
  gender     text not null check (gender in ('man', 'woman')),
  age        int not null check (age between 21 and 40),
  vibe       text not null default '',
  likes      text not null default '',
  hates      text not null default '',
  avatar     jsonb not null default '{}'::jsonb,
  pickiness  numeric not null default 0 check (pickiness between -50 and 50),
  scenes     text[] not null default '{club}',
  yes_line   text not null default '',
  no_line    text not null default '',
  sort       int not null default 0,
  active     boolean not null default true
);

insert into public.linkup_npcs (id, name, gender, age, vibe, likes, hates, avatar, pickiness, yes_line, no_line, sort) values
('ivie', 'Ivie', 'woman', 24, 'Fashion student at UNIBEN, always fresh', 'Afrobeats, suya at midnight', 'stingy men',
 '{"v": 2, "top": {"c": "#c74b8a"}, "hair": "bone_straight", "skin": "tone3", "gender": "female", "preset": "glam"}', 0,
 'Okay o, you get sense. Make we link up.', 'Thanks for the drink, but I dey with my girls tonight.', 1),
('osasere', 'Osasere', 'woman', 27, 'Nurse at UBTH, off duty tonight', 'quiet lounges, small chops', 'loud boys wey dey form',
 '{"v": 2, "top": {"c": "#2f6fb3"}, "hair": "bun", "skin": "tone4", "gender": "female", "preset": "corporate"}', -5,
 'You be gentle person. I like that. Let''s talk more.', 'Abeg, I just close from night shift. Another time.', 2),
('eki', 'Eki', 'woman', 22, 'Content creator, 40k followers', 'amapiano, selfies with good light', 'dry texters',
 '{"v": 2, "top": {"c": "#6d4aa0"}, "hair": "braids", "skin": "tone3", "gender": "female", "preset": "glam"}', 5,
 'Ahn ahn, you sabi! Snap me first, then we go.', 'You no even greet me well. Next!', 3),
('adesuwa', 'Adesuwa', 'woman', 29, 'Banker on Akpakpava, big plans', 'good wine, ambitious people', 'men wey no get plan',
 '{"v": 2, "top": {"c": "#1f7a3f"}, "hair": "bantu_knots", "skin": "tone5", "gender": "female", "preset": "corporate"}', -10,
 'Fine. You get vision. I go give you small time.', 'Sorry, I no dey entertain random drinks.', 4),
('imade', 'Imade', 'woman', 31, 'Runs a boutique in GRA', 'Patricia Nightlife, gele on Sundays', 'late comers',
 '{"v": 2, "top": {"c": "#e07a2e"}, "hair": "ponytail", "skin": "tone4", "gender": "female", "preset": "ankara"}', -5,
 'You dey on time, I see am. Okay, let''s go.', 'My driver don come. Thank you sha.', 5),
('tina', 'Tina', 'woman', 25, 'Makeup artist, books every Saturday', 'Davido, hot pepper soup', 'stingy guys',
 '{"v": 2, "top": {"c": "#d2342a"}, "hair": "braids", "skin": "tone2", "gender": "female", "preset": "glam"}', 5,
 'Correct guy! I dey come with you.', 'Hmm. Na only one drink? Try again later.', 6),
('itohan', 'Itohan', 'woman', 33, 'Real estate agent, sells land in Ugbor', 'rooftop drinks, long gist', 'liars',
 '{"v": 2, "top": {"c": "#0b625a"}, "hair": "bun", "skin": "tone5", "gender": "female", "preset": "corporate"}', -10,
 'You talk straight. I like straight talk. Okay.', 'I don hear that line before. No.', 7),
('precious', 'Precious', 'woman', 23, 'Final-year law student', 'Burna Boy, shawarma', 'people wey chew with mouth open',
 '{"v": 2, "top": {"c": "#111111"}, "hair": "ponytail", "skin": "tone3", "gender": "female", "preset": "glam"}', 0,
 'Objection overruled. You fit buy me dinner.', 'I get exam next week. Make I go read.', 8),
('osaro', 'Osaro', 'man', 28, 'Software dev at Bronze Tech Hub', 'Afrobeats, Champions League nights', 'stingy women',
 '{"v": 2, "top": {"c": "#1e3c72"}, "hair": "low_cut", "skin": "tone4", "gender": "male", "preset": "street"}', 0,
 'You get vibes. Make we vibe.', 'Thank you, but my guys dey wait me.', 11),
('ehis', 'Ehis', 'man', 30, 'Car dealer at Ighodalo, always jolly', 'cold Star, highlife', 'drama',
 '{"v": 2, "top": {"c": "#f3f0e8"}, "hair": "bald", "skin": "tone5", "gender": "male", "preset": "senator"}', 0,
 'Ehen! Now we dey talk. Let''s go.', 'I no fit tonight. Monday market dey wait me.', 12),
('uyi', 'Uyi', 'man', 24, 'Up-and-coming DJ', 'amapiano, people who dance', 'people wey no dey dance',
 '{"v": 2, "top": {"c": "#d2342a"}, "hair": "waves", "skin": "tone4", "gender": "male", "preset": "street"}', 5,
 'You dance well! I dey with you tonight.', 'My set dey start now now. Later.', 13),
('kingsley', 'Kingsley', 'man', 35, 'Oil and gas engineer, home for the weekend', 'good food, quiet hotels', 'show-offs',
 '{"v": 2, "top": {"c": "#202020"}, "hair": "low_cut", "skin": "tone5", "gender": "male", "preset": "corporate"}', -10,
 'You get class. Let''s go somewhere quiet and talk.', 'I appreciate am, but no.', 14),
('efosa', 'Efosa', 'man', 26, 'Plays for a local league team', 'pepper soup, football gist', 'fake people',
 '{"v": 2, "top": {"c": "#1f7a3f"}, "hair": "low_cut", "skin": "tone3", "gender": "male", "preset": "street"}', 0,
 'You real. I like am. Make we go.', 'Coach say make I sleep early. Sorry o.', 15),
('osagie', 'Osagie', 'man', 38, 'Lawyer with chambers on Sapele Road', 'jazz, red wine', 'noise',
 '{"v": 2, "top": {"c": "#f3f0e8"}, "hair": "bald", "skin": "tone4", "gender": "male", "preset": "senator"}', -10,
 'Very well. I will clear my evening.', 'Not tonight, my dear.', 16),
('jude', 'Jude', 'man', 22, 'Barber at Fresh Cut Salon', 'Rema, clean sneakers', 'people wey dey form big',
 '{"v": 2, "top": {"c": "#111111"}, "hair": "waves", "skin": "tone3", "gender": "male", "preset": "yahoo"}', 5,
 'Omo, you sweet! Let''s go.', 'I dey with my padi tonight. Next time.', 17),
('nosa', 'Nosa', 'man', 33, 'Businessman, imports phones', 'Club Raptor, suya', 'stingy women',
 '{"v": 2, "top": {"c": "#6d4aa0"}, "hair": "low_cut", "skin": "tone5", "gender": "male", "preset": "senator"}', 0,
 'You don win me. Let''s go.', 'I dey wait my people. Thanks sha.', 18)
on conflict (id) do nothing;

-- Me: who I'm into + counters.
create table if not exists public.linkup_players (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  want       text not null default 'anyone' check (want in ('men', 'women', 'anyone')),
  linkups    int not null default 0,
  nights     int not null default 0,
  breakups   int not null default 0,
  lost       bigint not null default 0,
  updated_at timestamptz not null default now()
);

-- People I've met (one row per NPC): spark, counts, the open yes, the relationship flag.
create table if not exists public.linkup_people (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  npc_id       text not null references public.linkup_npcs(id) on delete cascade,
  spark        int not null default 0 check (spark between 0 and 100),
  drinks       int not null default 0,
  yeses        int not null default 0,
  dinners      int not null default 0,
  nights       int not null default 0,
  met_at       timestamptz not null default now(),
  last_at      timestamptz not null default now(),
  yes_until    timestamptz,
  no_until     timestamptz,
  cold_until   timestamptz,
  steady       boolean not null default false,
  steady_since timestamptz,
  ended_at     timestamptz,
  primary key (user_id, npc_id)
);
create unique index if not exists linkup_people_one_steady_uidx on public.linkup_people (user_id) where steady;

create table if not exists public.linkup_runs (
  id           bigserial primary key,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  npc_id       text not null references public.linkup_npcs(id) on delete cascade,
  action_id    text not null references public.linkup_actions(id) on delete cascade,
  location_id  text,
  started_at   timestamptz not null default now(),
  resolve_at   timestamptz not null,
  resolved_at  timestamptz,
  status       text not null default 'running' check (status in ('running', 'yes', 'no', 'done')),
  price        bigint not null default 0,
  yes_pct      numeric,
  outcome      jsonb not null default '{}'::jsonb,
  morning      jsonb,
  morning_seen boolean not null default false
);
create index if not exists linkup_runs_user_idx on public.linkup_runs (user_id, id desc);
create unique index if not exists linkup_runs_one_running_uidx on public.linkup_runs (user_id) where status = 'running';

alter table public.linkup_actions enable row level security;
alter table public.linkup_npcs enable row level security;
alter table public.linkup_players enable row level security;
alter table public.linkup_people enable row level security;
alter table public.linkup_runs enable row level security;
revoke all on table public.linkup_actions, public.linkup_npcs, public.linkup_players, public.linkup_people, public.linkup_runs
  from public, anon, authenticated;
revoke all on sequence public.linkup_runs_id_seq from public, anon, authenticated;
grant select on table public.linkup_actions, public.linkup_npcs to authenticated;
drop policy if exists linkup_actions_read on public.linkup_actions;
create policy linkup_actions_read on public.linkup_actions for select to authenticated using (true);
drop policy if exists linkup_npcs_read on public.linkup_npcs;
create policy linkup_npcs_read on public.linkup_npcs for select to authenticated using (true);
grant select on table public.linkup_players, public.linkup_people, public.linkup_runs to authenticated;
drop policy if exists linkup_players_own on public.linkup_players;
create policy linkup_players_own on public.linkup_players for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists linkup_people_own on public.linkup_people;
create policy linkup_people_own on public.linkup_people for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists linkup_runs_own on public.linkup_runs;
create policy linkup_runs_own on public.linkup_runs for select to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------
-- 3. Private helpers
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_linkup_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

create or replace function public.bl_linkup_text(p_key text, p_default text) returns text
language sql stable set search_path = public as $$
  select coalesce(nullif((select value #>> '{}' from game_config where key = p_key), ''), p_default);
$$;

create or replace function public.bl_linkup_on() returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = 'linkup.enabled'), true);
$$;

create or replace function public.bl_linkup_row(p_uid uuid, p_lock boolean default false) returns public.linkup_players
language plpgsql set search_path = public as $$
declare r linkup_players;
begin
  insert into linkup_players (user_id) values (p_uid) on conflict (user_id) do nothing;
  if p_lock then
    select * into r from linkup_players where user_id = p_uid for update;
  else
    select * into r from linkup_players where user_id = p_uid;
  end if;
  return r;
end $$;

create or replace function public.bl_linkup_want(p_uid uuid) returns text
language sql stable set search_path = public as $$
  select coalesce((select want from linkup_players where user_id = p_uid), 'anyone');
$$;

create or replace function public.bl_linkup_wants(p_want text, p_gender text) returns boolean
language sql immutable as $$
  select coalesce(p_want, 'anyone') = 'anyone' or (p_want = 'men' and p_gender = 'man') or (p_want = 'women' and p_gender = 'woman');
$$;

-- "Tonight" for the club crowd: the night runs until noon the next day (Lagos time), so the crowd doesn't reshuffle at midnight.
create or replace function public.bl_linkup_night() returns text
language sql stable set search_path = public as $$
  select ((bl_now() at time zone bl_clock_tz()) - interval '12 hours')::date::text;
$$;

-- Who is out tonight at this place (stable per place per night), among the people this player is into.
create or replace function public.bl_linkup_here(p_uid uuid, p_loc text) returns setof public.linkup_npcs
language sql stable set search_path = public as $$
  select n.* from linkup_npcs n, locations l
   where l.id = p_loc and n.active and l.scene = any (n.scenes)
     and bl_linkup_wants(bl_linkup_want(p_uid), n.gender)
   order by md5(n.id || ':' || l.id || ':' || bl_linkup_night())
   limit greatest(1, bl_linkup_num('linkup.npcs_per_place', 4))::int;
$$;

create or replace function public.bl_linkup_npc_json(n public.linkup_npcs) returns jsonb
language sql stable set search_path = public as $$
  select case when n.id is null then null else jsonb_build_object(
    'id', n.id, 'name', n.name, 'gender', n.gender, 'age', n.age, 'vibe', n.vibe, 'likes', n.likes, 'hates', n.hates,
    'avatar', n.avatar) end;
$$;

-- Yes chance for "Buy drinks" with the breakdown the app shows.
create or replace function public.bl_linkup_yes_pct(p_uid uuid, p_npc text) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  n       linkup_npcs;
  v_me    profiles;
  v_spark int;
  v_base  numeric := bl_linkup_num('linkup.drinks_yes_pct', 45);
  v_charm numeric := coalesce(bl_charm_value(p_uid, 'attraction'), 0);
  v_steps int;
  v_rank  numeric;
  v_cred  numeric;
  v_looks numeric := 0;
  v_sp    numeric;
  v_pct   numeric;
begin
  select * into n from linkup_npcs where id = p_npc;
  select * into v_me from profiles where id = p_uid;
  select coalesce(spark, 0) into v_spark from linkup_people where user_id = p_uid and npc_id = p_npc;
  v_spark := coalesce(v_spark, 0);
  select greatest(0, count(*) - 1)::int into v_steps from yahoo_ranks r
   where r.min_earned <= coalesce((select total_earned from yahoo_players where user_id = p_uid), 0);
  v_rank := coalesce(v_steps, 0) * bl_linkup_num('linkup.rank_bonus_pts', 3);
  v_cred := least(bl_linkup_num('linkup.cred_bonus_cap', 5),
                  floor(greatest(0, coalesce(v_me.street_cred, 0)) / greatest(1, bl_linkup_num('linkup.cred_per_pt', 10))));
  if coalesce(v_me.hygiene, 50) >= bl_linkup_num('linkup.fresh_hygiene', 60) then
    v_looks := bl_linkup_num('linkup.fresh_pts', 5);
  elsif coalesce(v_me.hygiene, 50) < bl_linkup_num('linkup.smelly_hygiene', 25) then
    v_looks := -bl_linkup_num('linkup.smelly_pts', 15);
  end if;
  v_sp := floor(v_spark / greatest(1, bl_linkup_num('linkup.spark_div', 5)));
  v_pct := greatest(bl_linkup_num('linkup.yes_floor_pct', 5), least(bl_linkup_num('linkup.yes_cap_pct', 95),
             v_base + coalesce(n.pickiness, 0) + v_charm + v_rank + v_cred + v_looks + v_sp));
  return jsonb_build_object('pct', round(v_pct, 1), 'base', v_base, 'npc', coalesce(n.pickiness, 0), 'charm', v_charm,
                            'rank', v_rank, 'cred', v_cred, 'looks', v_looks, 'spark', v_sp);
end $$;

-- My partner row (the NPC I'm in a relationship with), or null.
create or replace function public.bl_linkup_partner(p_uid uuid) returns public.linkup_people
language sql stable set search_path = public as $$
  select * from linkup_people where user_id = p_uid and steady limit 1;
$$;

-- Who I'd go on a date / to the hotel with right now: an NPC with an open yes (latest first), else my partner.
create or replace function public.bl_linkup_current(p_uid uuid) returns public.linkup_people
language sql stable set search_path = public as $$
  select * from linkup_people
   where user_id = p_uid and (yes_until > bl_now() or steady)
   order by (yes_until > bl_now()) desc nulls last, yes_until desc nulls last, steady desc
   limit 1;
$$;

-- Zone card details: who it's with now and what's missing.
create or replace function public.bl_linkup_card(p_uid uuid, a public.linkup_actions, p_loc text) returns jsonb
language plpgsql stable set search_path = public as $$
declare c linkup_people; n linkup_npcs; v_rank text := coalesce(a.min_rank, null);
begin
  if a.kind = 'drinks' then
    return jsonb_build_object('here', (select count(*) from bl_linkup_here(p_uid, p_loc)));
  end if;
  c := bl_linkup_current(p_uid);
  if c.npc_id is not null then select * into n from linkup_npcs where id = c.npc_id; end if;
  return jsonb_build_object(
    'with', case when n.id is not null then jsonb_build_object('id', n.id, 'name', n.name, 'age', n.age, 'partner', c.steady) end,
    'needs', case when v_rank is not null and not bl_yahoo_rank_at_least(p_uid, v_rank) then 'rank'
                  when a.needs_yes and n.id is null then 'yes' end,
    'rank_name', case when v_rank is not null then (select name from yahoo_ranks where id = v_rank) end);
end $$;

create or replace function public.bl_linkup_run_json(r public.linkup_runs) returns jsonb
language sql stable set search_path = public as $$
  select case when r.id is null then null else jsonb_build_object(
    'id', r.id, 'action_id', r.action_id, 'npc_id', r.npc_id,
    'name', (select name from linkup_actions where id = r.action_id), 'icon', (select icon from linkup_actions where id = r.action_id),
    'kind', (select kind from linkup_actions where id = r.action_id),
    'npc_name', (select name from linkup_npcs where id = r.npc_id),
    'started_at', r.started_at, 'resolve_at', r.resolve_at, 'status', r.status, 'price', r.price, 'yes_pct', r.yes_pct,
    'line', (select line from linkup_actions where id = r.action_id),
    'place', (select name from locations where id = r.location_id)) end;
$$;

-- Roll / finish one running link-up action. Locks the run, the profile and my rows.
create or replace function public.bl_linkup_resolve(p_id bigint) returns jsonb
language plpgsql set search_path = public as $$
declare
  r        linkup_runs;
  a        linkup_actions;
  n        linkup_npcs;
  pp       linkup_people;
  v_part   linkup_people;
  v_part_name text;
  v_now    timestamptz := bl_now();
  v_status text;
  v_eff    jsonb;
  v_cred   int;
  v_yes_min numeric := greatest(1, bl_linkup_num('linkup.yes_minutes', 120));
  v_line   text;
  v_new_partner boolean := false;
  v_robbed bigint := 0;
  v_caught boolean := false;
  v_cash   bigint;
  v_morning jsonb;
  v_breakup jsonb;
begin
  select * into r from linkup_runs where id = p_id for update;
  if not found then return jsonb_build_object('status', 'none'); end if;
  if r.status <> 'running' then
    return jsonb_build_object('status', r.status, 'already', true, 'run_id', r.id);
  end if;
  perform 1 from profiles where id = r.user_id for update;
  perform bl_linkup_row(r.user_id, true);
  select * into a from linkup_actions where id = r.action_id;
  select * into n from linkup_npcs where id = r.npc_id;
  insert into linkup_people (user_id, npc_id, met_at, last_at) values (r.user_id, r.npc_id, v_now, v_now)
  on conflict (user_id, npc_id) do nothing;
  select * into pp from linkup_people where user_id = r.user_id and npc_id = r.npc_id for update;
  v_eff := coalesce(a.effects, '{}'::jsonb);

  if a.kind = 'drinks' then
    if bl_crime_roll(r.yes_pct) then
      v_status := 'yes';
      update linkup_people set spark = least(100, spark + a.spark), drinks = drinks + 1, yeses = yeses + 1,
             yes_until = v_now + make_interval(mins => v_yes_min::int), no_until = null, last_at = v_now
       where user_id = r.user_id and npc_id = r.npc_id;
      update linkup_players set linkups = linkups + 1, updated_at = v_now where user_id = r.user_id;
      v_line := coalesce(nullif(n.yes_line, ''), 'Okay, let''s link up.');
      perform bl_event(r.user_id, 'linkup_yes', n.name || ' said yes 💞',
        n.name || ' (' || n.age || ') is down. Take them to dinner, or straight to a hotel suite. The yes lasts about '
        || v_yes_min::int || ' min.', jsonb_build_object('npc', n.id, 'run_id', r.id));
    else
      v_status := 'no';
      update linkup_people set drinks = drinks + 1, last_at = v_now,
             no_until = v_now + make_interval(secs => greatest(0, bl_linkup_num('linkup.no_cooldown_seconds', 120))::double precision)
       where user_id = r.user_id and npc_id = r.npc_id;
      v_line := coalesce(nullif(n.no_line, ''), 'Thanks for the drink, but no.');
    end if;
  elsif a.kind = 'date' then
    v_status := 'done';
    update linkup_people set spark = least(100, spark + a.spark), dinners = dinners + 1, last_at = v_now,
           yes_until = case when steady then yes_until else v_now + make_interval(mins => v_yes_min::int) end
     where user_id = r.user_id and npc_id = r.npc_id
     returning * into pp;
    -- enough dates and spark: you two are an item (one partner at a time)
    if not pp.steady and pp.dinners >= greatest(1, bl_linkup_num('linkup.steady_dinners', 3))
       and pp.spark >= bl_linkup_num('linkup.steady_spark', 60)
       and not exists (select 1 from linkup_people where user_id = r.user_id and steady) then
      update linkup_people set steady = true, steady_since = v_now, ended_at = null where user_id = r.user_id and npc_id = r.npc_id;
      v_new_partner := true;
      perform bl_event(r.user_id, 'linkup_partner', 'You and ' || n.name || ' are now an item 💑',
        'After all those dates, ' || n.name || ' is your partner now. Treat them well. And behave yourself o.',
        jsonb_build_object('npc', n.id));
    end if;
    v_line := 'Good food, better gist. ' || n.name || ' is smiling at you across the table.';
  else
    -- hotel: fade to black, then the morning after
    v_status := 'done';
    update linkup_people set spark = least(100, spark + a.spark), nights = nights + 1, last_at = v_now,
           yes_until = case when steady then yes_until else null end
     where user_id = r.user_id and npc_id = r.npc_id
     returning * into pp;
    update linkup_players set nights = nights + 1, updated_at = v_now where user_id = r.user_id;
    v_line := n.name || ' is already up, laughing at your sleeping face. Breakfast is on the way.';
    -- risk 1: phone/cash missing (never with your own partner)
    if not pp.steady and bl_crime_roll(bl_linkup_num('linkup.robbed_pct', 10)) then
      select cash into v_cash from profiles where id = r.user_id;
      v_robbed := least(greatest(0, bl_linkup_num('linkup.robbed_cap', 100000))::bigint,
                        (floor(greatest(0, v_cash) * greatest(0, least(100, bl_linkup_num('linkup.robbed_share_pct', 30))) / 100.0 / 100) * 100)::bigint);
      if v_robbed > 0 then
        perform bl_add_money(r.user_id, 'cash', -v_robbed, 'linkup_gone_wrong', jsonb_build_object('npc', n.id, 'npc_name', n.name, 'run_id', r.id));
        update linkup_players set lost = lost + v_robbed where user_id = r.user_id;
      end if;
      v_line := 'You wake up and ' || n.name || ' don disappear. Your wallet feels light.';
    end if;
    -- risk 2: your partner finds out (only when the night was with someone else)
    v_part := bl_linkup_partner(r.user_id);
    if v_part.npc_id is not null and v_part.npc_id <> r.npc_id and bl_crime_roll(bl_linkup_num('linkup.caught_pct', 35)) then
      v_caught := true;
      select name into v_part_name from linkup_npcs where id = v_part.npc_id;
      update linkup_people set steady = false, ended_at = v_now,
             spark = greatest(0, spark - greatest(0, bl_linkup_num('linkup.breakup_spark_loss', 50))::int),
             yes_until = null,
             cold_until = v_now + make_interval(secs => (greatest(0, bl_linkup_num('linkup.ex_cooloff_hours', 24)) * 3600)::double precision)
       where user_id = r.user_id and npc_id = v_part.npc_id;
      update linkup_players set breakups = breakups + 1 where user_id = r.user_id;
      v_breakup := jsonb_build_object('fun', bl_linkup_num('linkup.breakup_fun', -30), 'social', bl_linkup_num('linkup.breakup_social', -25),
                                      'stress', bl_linkup_num('linkup.breakup_stress', 30));
      perform bl_adjust_needs(r.user_id, v_breakup);
      perform bl_event(r.user_id, 'linkup_breakup', v_part_name || ' found out 💔',
        v_part_name || ' saw everything and it''s over. Your heart don break small.', jsonb_build_object('npc', v_part.npc_id));
    end if;
    v_morning := jsonb_build_object(
      'npc', bl_linkup_npc_json(n), 'action', a.name, 'action_id', a.id, 'line', v_line,
      'robbed', v_robbed > 0, 'robbed_amount', v_robbed, 'caught', v_caught,
      'ex', case when v_caught then jsonb_build_object('id', v_part.npc_id, 'name', v_part_name) end,
      'breakup', v_breakup, 'effects', v_eff, 'with_partner', pp.steady);
  end if;

  -- effects (needs + street cred / hype)
  v_cred := coalesce((v_eff->>'street_cred')::int, 0);
  perform bl_adjust_needs(r.user_id, v_eff - 'street_cred');
  if v_cred <> 0 then
    update profiles set street_cred = greatest(0, street_cred + v_cred) where id = r.user_id;
  end if;
  update profiles set busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
   where id = r.user_id and busy_label like 'Link-up:%';
  update linkup_runs set status = v_status, resolved_at = v_now, morning = v_morning,
         outcome = jsonb_build_object('line', v_line, 'new_partner', v_new_partner, 'robbed', v_robbed, 'caught', v_caught)
   where id = r.id;

  return jsonb_build_object(
    'status', v_status, 'run_id', r.id, 'action_id', a.id, 'kind', a.kind, 'name', a.name, 'icon', a.icon,
    'npc', bl_linkup_npc_json(n), 'line', v_line, 'effects', v_eff, 'spark', pp.spark,
    'new_partner', v_new_partner, 'morning', v_morning,
    'yes_until', (select yes_until from linkup_people where user_id = r.user_id and npc_id = r.npc_id));
end $$;

revoke all on function public.bl_linkup_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_linkup_text(text, text) from public, anon, authenticated;
revoke all on function public.bl_linkup_on() from public, anon, authenticated;
revoke all on function public.bl_linkup_row(uuid, boolean) from public, anon, authenticated;
revoke all on function public.bl_linkup_want(uuid) from public, anon, authenticated;
revoke all on function public.bl_linkup_wants(text, text) from public, anon, authenticated;
revoke all on function public.bl_linkup_night() from public, anon, authenticated;
revoke all on function public.bl_linkup_here(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_linkup_npc_json(public.linkup_npcs) from public, anon, authenticated;
revoke all on function public.bl_linkup_yes_pct(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_linkup_partner(uuid) from public, anon, authenticated;
revoke all on function public.bl_linkup_current(uuid) from public, anon, authenticated;
revoke all on function public.bl_linkup_card(uuid, public.linkup_actions, text) from public, anon, authenticated;
revoke all on function public.bl_linkup_run_json(public.linkup_runs) from public, anon, authenticated;
revoke all on function public.bl_linkup_resolve(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 4. Player RPCs (none takes a player id: the other side is always an NPC id)
-- ---------------------------------------------------------------------------------------------
-- Everything the Link-ups app needs; also finishes an action whose time is up (after a reload).
create or replace function public.linkup_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_me   profiles;
  lp     linkup_players;
  r      linkup_runs;
  v_res  jsonb;
  l      locations;
  v_open boolean;
  v_cur  linkup_people;
  v_part linkup_people;
  v_morn linkup_runs;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    return jsonb_build_object('enabled', false, 'run', null);
  end if;
  select * into r from linkup_runs where user_id = v_uid and status = 'running' order by id desc limit 1;
  if found and r.resolve_at <= bl_now() then
    v_res := bl_linkup_resolve(r.id);
    r := null;
    select * into v_me from profiles where id = v_uid;
  end if;
  lp := bl_linkup_row(v_uid);
  select * into l from locations where id = v_me.location_id;
  v_open := l.id is not null and bl_place_open(l) and v_me.travel_to is null and v_me.home_visit_host_id is null;
  v_cur := bl_linkup_current(v_uid);
  v_part := bl_linkup_partner(v_uid);
  select * into v_morn from linkup_runs where user_id = v_uid and morning is not null and not morning_seen order by id desc limit 1;
  return jsonb_build_object(
    'enabled', bl_linkup_on(),
    'want', lp.want,
    'stats', jsonb_build_object('linkups', lp.linkups, 'nights', lp.nights, 'breakups', lp.breakups, 'lost', lp.lost),
    'cash', v_me.cash, 'bank', v_me.bank,
    'rank', bl_yahoo_rank(v_uid),
    'attraction', bl_charm_value(v_uid, 'attraction'),
    'place', case when l.id is not null then jsonb_build_object('id', l.id, 'name', l.name, 'scene', l.scene, 'open', v_open) end,
    'actions', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', a.id, 'name', a.name, 'icon', a.icon, 'blurb', a.blurb, 'kind', a.kind, 'price', a.price, 'seconds', a.seconds,
                 'effects', a.effects, 'spark', a.spark, 'needs_yes', a.needs_yes, 'scenes', a.scenes, 'morning', a.morning,
                 'min_rank', a.min_rank, 'rank_name', (select name from yahoo_ranks where id = a.min_rank),
                 'rank_ok', a.min_rank is null or bl_yahoo_rank_at_least(v_uid, a.min_rank),
                 'here', v_open and l.scene = any (a.scenes),
                 'places', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name) order by x.sort)
                                       from locations x where x.scene = any (a.scenes) and coalesce(x.active, true)), '[]'::jsonb))
               order by a.sort, a.id) from linkup_actions a where a.active), '[]'::jsonb),
    'here', case when v_open and exists (select 1 from linkup_actions a where a.active and a.kind = 'drinks' and l.scene = any (a.scenes)) then
              coalesce((select jsonb_agg(bl_linkup_npc_json(h) || jsonb_build_object(
                          'yes_pct', bl_linkup_yes_pct(v_uid, h.id),
                          'spark', coalesce(p.spark, 0), 'met', p.npc_id is not null,
                          'yes_until', case when p.yes_until > bl_now() then p.yes_until end,
                          'no_until', case when p.no_until > bl_now() then p.no_until end,
                          'cold_until', case when p.cold_until > bl_now() then p.cold_until end,
                          'partner', coalesce(p.steady, false)))
                          from bl_linkup_here(v_uid, l.id) h
                          left join linkup_people p on p.user_id = v_uid and p.npc_id = h.id), '[]'::jsonb) end,
    'current', case when v_cur.npc_id is not null then
                 (select bl_linkup_npc_json(n) from linkup_npcs n where n.id = v_cur.npc_id)
                 || jsonb_build_object('spark', v_cur.spark, 'partner', v_cur.steady,
                                       'yes_until', case when v_cur.yes_until > bl_now() then v_cur.yes_until end) end,
    'partner', case when v_part.npc_id is not null then
                 (select bl_linkup_npc_json(n) from linkup_npcs n where n.id = v_part.npc_id)
                 || jsonb_build_object('spark', v_part.spark, 'since', v_part.steady_since) end,
    'steady', jsonb_build_object('dinners', bl_linkup_num('linkup.steady_dinners', 3), 'spark', bl_linkup_num('linkup.steady_spark', 60)),
    'people', coalesce((select jsonb_agg(bl_linkup_npc_json(n) || jsonb_build_object(
                          'spark', p.spark, 'drinks', p.drinks, 'yeses', p.yeses, 'dinners', p.dinners, 'nights', p.nights,
                          'met_at', p.met_at, 'last_at', p.last_at, 'partner', p.steady, 'ended_at', p.ended_at,
                          'yes_until', case when p.yes_until > bl_now() then p.yes_until end,
                          'cold_until', case when p.cold_until > bl_now() then p.cold_until end)
                        order by p.steady desc, p.last_at desc)
                         from linkup_people p join linkup_npcs n on n.id = p.npc_id where p.user_id = v_uid), '[]'::jsonb),
    'run', bl_linkup_run_json(r),
    'resolved', v_res,
    'morning', case when v_morn.id is not null then v_morn.morning || jsonb_build_object('run_id', v_morn.id) end,
    'history', coalesce((select jsonb_agg(bl_linkup_run_json(x) order by x.id desc)
                           from (select * from linkup_runs where user_id = v_uid and status <> 'running' order by id desc limit 12) x), '[]'::jsonb));
end $$;
revoke all on function public.linkup_status() from public, anon;
grant execute on function public.linkup_status() to authenticated, service_role;

-- Who I'm into for link-ups: 'men' / 'women' / 'anyone'.
create or replace function public.linkup_set_pref(p_want text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  perform bl_me_any();
  if p_want is null or p_want not in ('men', 'women', 'anyone') then
    raise exception 'Pick men, women or anyone.' using errcode = 'P0001', hint = 'bad_pref';
  end if;
  perform bl_linkup_row(v_uid);
  update linkup_players set want = p_want, updated_at = bl_now() where user_id = v_uid;
  return jsonb_build_object('want', p_want, 'message', 'Link-ups: ' || case p_want when 'men' then 'men' when 'women' then 'women' else 'anyone' end || ' it is.');
end $$;
revoke all on function public.linkup_set_pref(text) from public, anon;
grant execute on function public.linkup_set_pref(text) to authenticated, service_role;

-- Start a link-up action with an NPC (null = my current link-up / partner for dinner and the hotel).
create or replace function public.linkup_start(p_action text, p_npc text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  a       linkup_actions;
  n       linkup_npcs;
  pp      linkup_people;
  l       locations;
  v_now   timestamptz := bl_now();
  v_npc   text := nullif(btrim(coalesce(p_npc, '')), '');
  v_pct   numeric;
  v_odds  jsonb;
  v_until timestamptz;
  v_id    bigint;
  v_cash  bigint;
  v_bank  bigint;
  v_cur   linkup_people;
begin
  if not bl_linkup_on() then
    raise exception 'Link-ups are switched off for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into a from linkup_actions where id = p_action and active;
  if not found then
    raise exception 'No such link-up action.' using errcode = 'P0001', hint = 'bad_action';
  end if;
  perform 1 from profiles where id = v_me.id for update;
  v_me := bl_me();
  perform bl_crime_close_stale(v_me.id);
  perform bl_assert_free(v_me);
  perform bl_linkup_row(v_me.id, true);
  if exists (select 1 from linkup_runs where user_id = v_me.id and status = 'running') then
    raise exception 'Finish the link-up you dey first.' using errcode = 'P0001', hint = 'busy';
  end if;
  l := bl_location(v_me.location_id);
  if v_me.home_visit_host_id is not null or not (l.scene = any (a.scenes)) then
    raise exception '%', case a.kind when 'drinks' then 'Go to a club first. That''s where the people are.'
                                     when 'date' then 'Dinner dates happen at the hotel restaurants or the mall food court.'
                                     else 'You need a hotel for that. Try Protea or Golden Tulip.' end
      using errcode = 'P0001', hint = 'wrong_place';
  end if;
  perform bl_assert_place_open(l);
  if a.min_rank is not null then
    perform bl_yahoo_assert_rank(v_me.id, a.min_rank);
  end if;

  if a.kind = 'drinks' then
    if v_npc is null then
      raise exception 'Pick who you want to buy drinks for.' using errcode = 'P0001', hint = 'no_npc';
    end if;
    select * into n from linkup_npcs where id = v_npc and active;
    if not found then
      raise exception 'That person isn''t here.' using errcode = 'P0001', hint = 'not_here';
    end if;
    if not exists (select 1 from bl_linkup_here(v_me.id, l.id) h where h.id = n.id) then
      raise exception '% isn''t out at % tonight.', n.name, l.name using errcode = 'P0001', hint = 'not_here';
    end if;
    select * into pp from linkup_people where user_id = v_me.id and npc_id = n.id;
    if pp.steady then
      raise exception '% is already your partner. Take them out!', n.name using errcode = 'P0001', hint = 'already_partner';
    end if;
    if pp.yes_until > v_now then
      raise exception '% already said yes. Take them to dinner or a hotel.', n.name using errcode = 'P0001', hint = 'already_yes';
    end if;
    if pp.cold_until > v_now then
      raise exception '% no wan see your face right now.', n.name using errcode = 'P0001', hint = 'cold';
    end if;
    if pp.no_until > v_now then
      raise exception '% just said no. Give am small time (about % sec).', n.name, ceil(extract(epoch from pp.no_until - v_now))::int
        using errcode = 'P0001', hint = 'cooldown';
    end if;
    v_odds := bl_linkup_yes_pct(v_me.id, n.id);
    v_pct := (v_odds->>'pct')::numeric;
  else
    if v_npc is null then
      v_cur := bl_linkup_current(v_me.id);
      v_npc := v_cur.npc_id;
    end if;
    select * into n from linkup_npcs where id = v_npc;
    if v_npc is null or not found then
      raise exception 'You need a link-up first. Buy someone drinks at a club and get a yes.' using errcode = 'P0001', hint = 'needs_yes';
    end if;
    select * into pp from linkup_people where user_id = v_me.id and npc_id = n.id;
    if a.needs_yes and not (coalesce(pp.steady, false) or coalesce(pp.yes_until > v_now, false)) then
      raise exception '% hasn''t said yes. Buy them drinks at a club first.', n.name using errcode = 'P0001', hint = 'needs_yes';
    end if;
  end if;

  if v_me.cash + v_me.bank < a.price then
    raise exception '% costs %. You have % (cash + bank).', a.name, bl_naira(a.price), bl_naira(v_me.cash + v_me.bank)
      using errcode = 'P0001', hint = 'not_enough_money';
  end if;
  v_cash := least(v_me.cash, a.price);
  v_bank := a.price - v_cash;
  if v_cash > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_cash, 'linkup', jsonb_build_object('action', a.id, 'action_name', a.name, 'npc', n.id, 'npc_name', n.name));
  end if;
  if v_bank > 0 then
    perform bl_add_money(v_me.id, 'bank', -v_bank, 'linkup', jsonb_build_object('action', a.id, 'action_name', a.name, 'npc', n.id, 'npc_name', n.name));
  end if;
  insert into linkup_people (user_id, npc_id, met_at, last_at) values (v_me.id, n.id, v_now, v_now)
  on conflict (user_id, npc_id) do update set last_at = excluded.last_at;
  -- can't be stopped halfway (busy_needs_from stays null, so activity_stop refuses)
  v_until := bl_set_busy_seconds(v_me.id, a.seconds, 'Link-up: ' || a.name);
  insert into linkup_runs (user_id, npc_id, action_id, location_id, started_at, resolve_at, price, yes_pct)
  values (v_me.id, n.id, a.id, l.id, v_now, v_until, a.price, v_pct)
  returning id into v_id;
  return jsonb_build_object('run_id', v_id, 'busy_until', v_until, 'resolve_at', v_until, 'seconds', a.seconds,
                            'action_id', a.id, 'name', a.name, 'icon', a.icon, 'kind', a.kind, 'npc', bl_linkup_npc_json(n),
                            'price', a.price, 'yes_pct', v_pct, 'odds', v_odds, 'line', a.line,
                            'message', case a.kind when 'drinks' then 'You send drinks over to ' || n.name || '…'
                                                   when 'date' then 'Dinner with ' || n.name || '…'
                                                   else 'The night goes on… ☾' end);
end $$;
revoke all on function public.linkup_start(text, text) from public, anon;
grant execute on function public.linkup_start(text, text) to authenticated, service_role;

-- Finish my running link-up action once its timer is over.
create or replace function public.linkup_finish() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  r linkup_runs;
begin
  perform bl_me_any();
  select * into r from linkup_runs where user_id = v_uid and status = 'running' order by id desc limit 1;
  if not found then
    raise exception 'No link-up is running.' using errcode = 'P0001', hint = 'no_run';
  end if;
  if r.resolve_at > bl_now() then
    raise exception 'Hold on, about % sec more.', ceil(extract(epoch from r.resolve_at - bl_now()))::int using errcode = 'P0001', hint = 'not_yet';
  end if;
  return bl_linkup_resolve(r.id);
end $$;
revoke all on function public.linkup_finish() from public, anon;
grant execute on function public.linkup_finish() to authenticated, service_role;

-- I've seen the morning-after popup.
create or replace function public.linkup_morning_seen(p_run bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_n int;
begin
  update linkup_runs set morning_seen = true where id = p_run and user_id = v_uid and morning is not null;
  get diagnostics v_n = row_count;
  return jsonb_build_object('seen', v_n > 0);
end $$;
revoke all on function public.linkup_morning_seen(bigint) from public, anon;
grant execute on function public.linkup_morning_seen(bigint) to authenticated, service_role;

-- Admin: a player's link-up rows + recent runs.
create or replace function public.admin_linkup_player(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'player', (select to_jsonb(x) from linkup_players x where x.user_id = p_user),
    'people', coalesce((select jsonb_agg(to_jsonb(p) order by p.last_at desc) from linkup_people p where p.user_id = p_user), '[]'::jsonb),
    'runs', coalesce((select jsonb_agg(bl_linkup_run_json(x) order by x.id desc)
                        from (select * from linkup_runs where user_id = p_user order by id desc limit 30) x), '[]'::jsonb));
end $$;
revoke all on function public.admin_linkup_player(uuid) from public, anon;
grant execute on function public.admin_linkup_player(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 5. Existing functions (guarded edits of the live definitions)
-- ---------------------------------------------------------------------------------------------
-- zone_actions: a new card kind 'linkup' (ref = linkup_actions.id).
do $$
declare v_con text;
begin
  select pg_get_constraintdef(oid) into v_con from pg_constraint
   where conrelid = 'public.zone_actions'::regclass and conname = 'zone_actions_kind_check';
  if v_con is null or position('linkup' in v_con) = 0 then
    alter table public.zone_actions drop constraint if exists zone_actions_kind_check;
    alter table public.zone_actions add constraint zone_actions_kind_check
      check (kind in ('activity', 'job', 'shop', 'panel', 'shrine', 'linkup'));
  end if;
end $$;

-- bl_zone_action_check(): linkup cards point at a link-up action.
do $$
declare v_def text; v_anchor text := '  elsif new.kind = ''panel''';
begin
  select pg_get_functiondef('public.bl_zone_action_check()'::regprocedure) into v_def;
  if position('linkup_actions' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'D2: bl_zone_action_check() changed; update the linkups migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '  elsif new.kind = ''linkup'' and not exists (select 1 from linkup_actions where id = new.ref) then' || chr(10)
    || '    raise exception ''Zone action %: no link-up action "%".'', new.id, new.ref using errcode = ''P0001'', hint = ''bad_value'';' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

-- place_interior(): link-up cards (price, seconds, effects, who it's with, what's missing).
do $$
declare v_def text; v_anchor text := '               -- open a tab of the place sheet (bank counter, PoS, the whole shop...)';
begin
  select pg_get_functiondef('public.place_interior(text)'::regprocedure) into v_def;
  if position('linkup_actions' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'D2: place_interior() changed; update the linkups migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
'               -- D2 link-up cards (clubs, hotel restaurant + suites, mall food court)
               select za.sort, la.sort, jsonb_build_object(
                        ''id'', za.id, ''kind'', ''linkup'', ''ref'', la.id,
                        ''name'', coalesce(za.label, la.name), ''icon'', coalesce(za.icon, la.icon),
                        ''cost'', la.price, ''seconds'', la.seconds, ''effects'', la.effects - ''street_cred'',
                        ''note'', nullif(la.blurb, ''''), ''linkup'', bl_linkup_card(v_uid, la, l.id),
                        ''locked'', case when not v_open then v_closed_for
                                         when not bl_linkup_on() then ''Switched off'' else null end)
                 from zone_actions za join linkup_actions la on la.id = za.ref
                where za.zone_id = z.id and za.kind = ''linkup'' and za.active and la.active and l.scene = any (la.scenes)
                  and bl_linkup_on()
               union all
' || v_anchor);
  execute v_def;
end $$;

-- bl_ledger_label(): Bank -> History lines.
do $$
declare v_def text; v_anchor text := '    when ''topup'' then';
begin
  select pg_get_functiondef('public.bl_ledger_label(text, jsonb)'::regprocedure) into v_def;
  if position('linkup_gone_wrong' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'D2: bl_ledger_label() changed; update the linkups migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''linkup'' then return ''Link-up: '' || coalesce(nullif(p_meta->>''action_name'', ''''), ''date'')'
    || ' || coalesce('' · '' || nullif(p_meta->>''npc_name'', ''''), '''');' || chr(10)
    || '    when ''linkup_gone_wrong'' then return ''Link-up gone wrong'';' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

-- bl_admin_table_spec(): Admin -> Content -> Link-up actions, Link-up people.
do $$
declare v_def text; v_anchor text := '    when ''interaction_types'' then';
begin
  select pg_get_functiondef('public.bl_admin_table_spec(text)'::regprocedure) into v_def;
  if position('linkup_actions' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'D2: bl_admin_table_spec() changed; update the linkups migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''linkup_actions'' then ''{"pk":["id"],"insert":true,"order":"sort, id",' || chr(10)
    || '      "cols":{"name":"text","icon":"text","blurb":"text","kind":"text","price":"money","seconds":"int","effects":"obj",' || chr(10)
    || '              "spark":"int","needs_yes":"bool","scenes":"arr","min_rank":"text","morning":"bool","line":"text","sort":"int","active":"bool"}}''' || chr(10)
    || '    when ''linkup_npcs'' then ''{"pk":["id"],"insert":true,"order":"sort, id",' || chr(10)
    || '      "cols":{"name":"text","gender":"text","age":"int","vibe":"text","likes":"text","hates":"text","avatar":"obj",' || chr(10)
    || '              "pickiness":"num","scenes":"arr","yes_line":"text","no_line":"text","sort":"int","active":"bool"}}''' || chr(10)
    || v_anchor);
  execute v_def;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Zone cards, mood lines; the attraction charm now works
-- ---------------------------------------------------------------------------------------------
insert into public.zone_actions (id, zone_id, kind, ref, label, icon, sort) values
  ('club.bar.linkup_drinks',            'club.bar',         'linkup', 'drinks',     null, null, 0),
  ('hotel.restaurant.linkup_dinner',    'hotel.restaurant', 'linkup', 'dinner',     null, null, 0),
  ('mall.food.linkup_dinner',           'mall.food',        'linkup', 'dinner',     null, null, 0),
  ('hotel.suites.linkup_short_time',    'hotel.suites',     'linkup', 'short_time', null, null, 1),
  ('hotel.suites.linkup_overnight',     'hotel.suites',     'linkup', 'overnight',  null, null, 2),
  ('hotel.suites.linkup_getaway',       'hotel.suites',     'linkup', 'getaway',    null, null, 3)
on conflict (id) do nothing;

insert into public.place_moods (id, scene, location_id, part, icon, line, sort) values
  ('club.linkup1',  'club',  null, 'night', '💞', 'Somebody dey look you from across the bar. Shoot your shot', 21),
  ('hotel.linkup1', 'hotel', null, 'night', '🗝️', 'A couple walks past reception, laughing, keys in hand', 21)
on conflict (id) do nothing;

update public.shrine_services set note = 'Works on Link-ups: dates say yes more often (+20 points on Buy drinks) while it lasts.'
 where id = 'attraction' and note like '%coming soon%';

notify pgrst, 'reload schema';
