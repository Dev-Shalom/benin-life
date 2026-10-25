-- Kids school and university (docs/KIDS_SCHOOL.md, step B of the family plan): enrol a child in a school, one class a day (compressed into the 21 days),
-- grades, promotion or repeating, school requests (the life-moments engine), report cards, WAEC at the end of SSS3, and university after it.
-- Rules for this file:
--   * NOTHING here touches public.profiles (no ALTER, no trigger, no foreign key): a first deploy of kids deadlocked on it (SQLSTATE 40P01).
--     New tables are keyed by child id / user id with no foreign key to profiles.
--   * Idempotent: columns `if not exists`, seeds `on conflict do nothing`, settings `on conflict do nothing`, kids_* functions are ours (create or replace);
--     every live function that was written by an earlier step is patched with a guarded replace against its CURRENT definition
--     (raises when the marker is missing, skips when already applied).
--   * Lazy: the school clock is computed on read and by the kids sweep (bl_push_tick -> bl_kids_alert_sweep, indexed kids_children_due);
--     the next school moment lives in kids_children.next_alert_at. No new cron, no new realtime, no global scan.

create or replace function pg_temp.ks_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'kids_school: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Kids school; the gift tier is under Kids)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('kids_school.enabled', 'true', 'kids_school', 'School and university on',
 'Off = parents cannot enrol, pay or help, and no new class starts or ends. Classes that run out while it is off are marked up when it is back, so switch it off for short breaks only.', 'bool', null, null),
('kids_school.class_hours', '24', 'kids_school', 'One class lasts (real hours)',
 'Real hours one school class takes. 24 = one class a day: Nursery 1-2 on days 5-8, Primary 1-6 on days 8-14, JSS1-SSS3 on days 14-21. A class never starts before its life stage does.', 'number', 1, 720),
('kids_school.pass_mark', '50', 'kids_school', 'Pass mark (0-100)',
 'A child whose average over the subjects is at least this is promoted at the end of the class. Under it the child repeats the class (and may not reach SSS3 before growing up).', 'number', 1, 100),
('kids_school.base_grade', '38', 'kids_school', 'Starting grade for a class',
 'Every subject starts here before the helps below are added. With the fee paid in time and a fairly happy child an average child lands just above the pass mark.', 'number', 0, 90),
('kids_school.fee_on_time_pts', '6', 'kids_school', 'Grade points for fees paid in time',
 'Added to every subject when the class fee was paid within the grace hours below. A fee paid later still lets the child attend, without these points. An unpaid fee = the child misses the class.', 'number', 0, 30),
('kids_school.fee_grace_hours', '12', 'kids_school', 'Fees count as on time within (hours)',
 'Hours after a class starts in which paying still counts as on time.', 'number', 0, 720),
('kids_school.needs_pts', '12', 'kids_school', 'Grade points for a well cared for child (+/-)',
 'A child whose needs stayed above the alert level the whole class gets +this; one who was neglected gets -this (in between, scaled). Well fed, rested and healthy helps.', 'number', 0, 40),
('kids_school.homework_pts', '4', 'kids_school', 'Grade points per homework help',
 'Each parent can help with homework once per class. Every subject gets this many points per help.', 'number', 0, 20),
('kids_school.homework_cooldown_minutes', '60', 'kids_school', 'Wait between homework helps (minutes)',
 'Per child, shared by both parents.', 'minutes', 0, 1440),
('kids_school.books_pts', '5', 'kids_school', 'Grade points for textbooks',
 'Textbooks for the level (Primary or Secondary) are given once and last for the whole level. Bought at Oba Market or the supermarket.', 'number', 0, 30),
('kids_school.uniform_pts', '3', 'kids_school', 'Grade points for a school bag and uniform',
 'Given once per life stage (Nursery, Primary, Secondary).', 'number', 0, 30),
('kids_school.lessons_pts', '8', 'kids_school', 'Grade points for extra lessons',
 'A paid tutor for ONE class. Every subject gets this many points.', 'number', 0, 40),
('kids_school.lessons_cost', '8000', 'kids_school', 'Extra lessons cost per class',
 'Naira a parent pays for a tutor for one class (ledger kid_school_lessons, a sink, never earnings).', 'naira', 0, 10000000),
('kids_school.talent_pts', '8', 'kids_school', 'Talent swing per subject (+/- points)',
 'Each child has a fixed, hidden talent per subject (the same every time). This is the most it can add or take.', 'number', 0, 30),
('kids_school.missed_grade', '22', 'kids_school', 'Grade when the child missed the class',
 'Every subject of a class the child did not attend (fee unpaid) starts from this, so the child repeats the class.', 'number', 0, 100),
('kids_school.missed_fun_hit', '20', 'kids_school', 'Sadness when a class is missed (Fun lost)',
 'Points of Fun (and half as much Love) the child loses when they miss a class because the fee was not paid.', 'number', 0, 100),
('kids_school.request_pct', '60', 'kids_school', 'Chance of a school request in a class (%)',
 'PTA levy, excursion, sports wear or end-of-term party. At most one per child per class, only when both parents are under the daily life-moments cap. The WAEC fee request always comes in SSS3.', 'percent', 0, 100),
('kids_school.ignore_penalty', '4', 'kids_school', 'Grade points lost when a request is ignored',
 'When every parent ignores a school request, every subject of that class loses this many points.', 'number', 0, 30),
('kids_school.ignore_fun_hit', '15', 'kids_school', 'Sadness when a request is ignored (Fun lost)',
 'Points of Fun the child loses when the school request is ignored.', 'number', 0, 100),
('kids_school.waec_credit_mark', '50', 'kids_school', 'WAEC credit mark (0-100)',
 'A WAEC paper at or above this is a credit (like C6 in the real grading: A1 75+, B2 70, B3 65, C4 60, C5 55, C6 50).', 'number', 1, 100),
('kids_school.waec_pass_credits', '5', 'kids_school', 'WAEC credits needed',
 'The child passes WAEC with at least this many credits including Maths and English.', 'number', 1, 9),
('kids_school.uni_enabled', 'true', 'kids_school', 'University on',
 'Off = a child who passed WAEC just moves out at day 21 like before and no university card is sent.', 'bool', null, null),
('kids_school.uni_level_hours', '24', 'kids_school', 'One university level lasts (real hours)',
 '100L, 200L, 300L, 400L: this many real hours each.', 'number', 1, 720),
('kids_school.uni_max_repeats', '2', 'kids_school', 'Repeats allowed in university (total)',
 'After this many repeated levels, the next failed level means the child drops out and moves out ("Didn''t finish university").', 'number', 0, 10),
('kids_school.uni_decision_hours', '36', 'kids_school', 'Parents have to choose university within (hours)',
 'If nobody answers the "Send them to university?" card in this time, the child starts working instead.', 'number', 1, 720),
('kids_school.uni_pocket_cost', '6000', 'kids_school', 'University pocket money per time',
 'Naira a parent pays in cash for "Send pocket money" to a child at university (ledger kid_care, a sink).', 'naira', 0, 1000000),
('kids_school.uni_first_min', '70', 'kids_school', 'Average for First Class',
 'University average over all levels.', 'number', 1, 100),
('kids_school.uni_upper_min', '60', 'kids_school', 'Average for Second Class Upper', 'See First Class.', 'number', 1, 100),
('kids_school.uni_lower_min', '55', 'kids_school', 'Average for Second Class Lower',
 'Below this, a graduate gets Third Class.', 'number', 1, 100),
('kids.gift_graduate', '250000', 'kids', 'Thank-you gift: Graduate (each parent)',
 'The top tier: the child graduated from university. Paid once to each parent (ledger kid_gift, never earnings) and still capped by the share of what the parent spent (school fees, books and lessons count).', 'naira', 0, 100000000)
on conflict (key) do nothing;

update public.game_config set description = 'Real days from birth until the child grows up. With a WAEC pass the parents choose university first (Settings -> Kids school); otherwise the child moves out. The parents get a Proud parent badge (Graduate, Gold, Silver or Bronze) and a thank-you gift. The stages are in Content -> Child stages.'
 where key = 'kids.grow_days';

-- ---------------------------------------------------------------------------------------------
-- 2. Tables and columns (small tables of ours; none touches profiles)
-- ---------------------------------------------------------------------------------------------
alter table public.kids_children add column if not exists outcome text;

do $$
declare cn text;
begin
  select conname into cn from pg_constraint
   where conrelid = 'public.kids_children'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%expecting%with_relatives%' and pg_get_constraintdef(oid) not like '%university%';
  if cn is not null then
    execute format('alter table public.kids_children drop constraint %I', cn);
    alter table public.kids_children add constraint kids_children_status_check check (status in ('expecting', 'home', 'with_relatives', 'grown', 'gone', 'passed', 'university'));
  end if;
  select conname into cn from pg_constraint
   where conrelid = 'public.kids_children'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%gold%silver%bronze%' and pg_get_constraintdef(oid) not like '%graduate%';
  if cn is not null then
    execute format('alter table public.kids_children drop constraint %I', cn);
    alter table public.kids_children add constraint kids_children_tier_check check (tier is null or tier in ('graduate', 'gold', 'silver', 'bronze', 'none'));
  end if;
  select conname into cn from pg_constraint
   where conrelid = 'public.kids_items'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%formula%paracetamol%' and pg_get_constraintdef(oid) not like '%uniform%';
  if cn is not null then
    execute format('alter table public.kids_items drop constraint %I', cn);
    alter table public.kids_items add constraint kids_items_role_check check (role in ('formula', 'cereal', 'diaper', 'paracetamol', 'malaria', 'toy', 'books', 'uniform'));
  end if;
  select conname into cn from pg_constraint
   where conrelid = 'public.life_moments'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%kids_ill%' and pg_get_constraintdef(oid) not like '%kids_school%';
  if cn is not null then
    execute format('alter table public.life_moments drop constraint %I', cn);
    alter table public.life_moments add constraint life_moments_kind_check check (kind in ('random', 'kids_ill', 'kids_school', 'kids_uni', 'system'));
  end if;
end $$;

-- Schools (Content -> Schools). levels: nursery, primary, secondary, university. fee_per_class = naira per class (per level at university).
-- quality = grade boost in percent (a 10 % school multiplies the grades by 1.10, capped at 100). area = a district id (just a label in the app).
create table if not exists public.kids_schools (
  id           text primary key check (id ~ '^[a-z][a-z0-9_]{1,40}$'),
  name         text not null check (char_length(name) between 3 and 60),
  icon         text not null default '🏫' check (char_length(icon) between 1 and 8),
  tier         text not null default 'mid' check (tier in ('budget', 'mid', 'premium', 'public', 'private')),
  levels       text[] not null default '{primary}' check (levels <@ array['nursery', 'primary', 'secondary', 'university'] and cardinality(levels) > 0),
  area         text,
  fee_per_class bigint not null default 20000 check (fee_per_class between 0 and 100000000),
  quality      numeric not null default 0 check (quality between 0 and 50),
  blurb        text not null default '' check (char_length(blurb) <= 160),
  sort         integer not null default 100,
  active       boolean not null default true
);

-- Subjects (Content -> School subjects). level: nursery, primary, secondary, university, or waec (the exam papers; parent = the secondary subject whose grade feeds it).
create table if not exists public.kids_subjects (
  id     text primary key check (id ~ '^[a-z][a-z0-9_]{1,30}$'),
  level  text not null check (level in ('nursery', 'primary', 'secondary', 'university', 'waec')),
  name   text not null check (char_length(name) between 2 and 30),
  parent text,
  sort   integer not null default 100,
  active boolean not null default true
);

-- The 14 classes of school, in order (the university levels are handled apart). grp = which report card the class belongs to.
create table if not exists public.kids_classes (
  seq      integer primary key,
  code     text not null unique,
  name     text not null,
  level    text not null check (level in ('nursery', 'primary', 'secondary')),
  stage_id text not null,
  grp      text not null,
  last_of_grp boolean not null default false
);

-- One row per child that goes to school (child_id = kids_children.id, no foreign keys).
create table if not exists public.kids_school (
  child_id    bigint primary key,
  school_id   text,
  seq         integer not null default 1,
  attempt     integer not null default 1,
  ready_at    timestamptz,
  class_start timestamptz,
  fee_amount  bigint not null default 0,
  fee_paid_at timestamptz,
  fee_paid_by uuid,
  fee_reminded boolean not null default false,
  hw_users    uuid[] not null default '{}',
  hw_last     timestamptz,
  lessons_at  timestamptz,
  books_stage text,
  uniform_stage text,
  good0       numeric not null default 0,
  total0      numeric not null default 0,
  req_type    text,
  req_at      timestamptz,
  req_done    boolean not null default true,
  penalty     numeric not null default 0,
  max_seq     integer not null default 0,
  missed      integer not null default 0,
  state       text not null default 'learning' check (state in ('learning', 'finished')),
  waec        jsonb,
  uni_state   text check (uni_state in ('deciding', 'studying', 'graduated', 'dropped', 'working')),
  uni_level   integer not null default 0 check (uni_level between 0 and 4),
  uni_repeats integer not null default 0,
  uni_deadline timestamptz,
  uni_course  text,
  uni_degree  text,
  uni_avg     numeric,
  created_at  timestamptz not null default now()
);

create table if not exists public.kids_school_results (
  id         bigserial primary key,
  child_id   bigint not null,
  level      text not null,
  seq        integer not null,
  attempt    integer not null default 1,
  class_name text not null,
  school_id  text,
  attended   boolean not null,
  on_time    boolean not null default false,
  grades     jsonb not null default '[]'::jsonb,
  avg        numeric not null default 0,
  promoted   boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists kids_school_results_child on public.kids_school_results (child_id, id desc);

create table if not exists public.kids_report_cards (
  id          bigserial primary key,
  child_id    bigint not null,
  stage_key   text not null,
  title       text not null,
  school_name text not null default '',
  grades      jsonb not null default '[]'::jsonb,
  avg         numeric not null default 0,
  position    text not null,
  remark      text not null,
  teacher     text not null,
  promoted    boolean not null default true,
  extra       text,
  created_at  timestamptz not null default now(),
  unique (child_id, stage_key)
);

create table if not exists public.kids_school_requests (
  id         bigserial primary key,
  child_id   bigint not null,
  seq        integer not null,
  attempt    integer not null default 1,
  req_type   text not null,
  status     text not null default 'open' check (status in ('open', 'paid', 'ignored')),
  ignores    uuid[] not null default '{}',
  paid_by    uuid,
  created_at timestamptz not null default now(),
  unique (child_id, seq, attempt)
);

do $$
declare t text;
begin
  foreach t in array array['kids_schools', 'kids_subjects', 'kids_classes', 'kids_school', 'kids_school_results', 'kids_report_cards', 'kids_school_requests'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

create or replace function public.bl_kids_text_guard3() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if bl_chat_mask(coalesce(to_jsonb(new) ->> 'name', '')) <> coalesce(to_jsonb(new) ->> 'name', '')
     or bl_chat_mask(coalesce(to_jsonb(new) ->> 'blurb', '')) <> coalesce(to_jsonb(new) ->> 'blurb', '') then
    raise exception 'Keep the words clean: there is a banned word.' using errcode = 'P0001', hint = 'blocked_text';
  end if;
  return new;
end $$;
drop trigger if exists kids_schools_guard on public.kids_schools;
create trigger kids_schools_guard before insert or update of name, blurb on public.kids_schools for each row execute function public.bl_kids_text_guard3();
drop trigger if exists kids_subjects_guard on public.kids_subjects;
create trigger kids_subjects_guard before insert or update of name on public.kids_subjects for each row execute function public.bl_kids_text_guard3();

-- ---------------------------------------------------------------------------------------------
-- 3. Seeds: classes, subjects, schools, university stage, school items
-- ---------------------------------------------------------------------------------------------
insert into public.kids_classes (seq, code, name, level, stage_id, grp, last_of_grp) values
(1,  'n1', 'Nursery 1',  'nursery',   'nursery',   'nursery', false),
(2,  'n2', 'Nursery 2',  'nursery',   'nursery',   'nursery', true),
(3,  'p1', 'Primary 1',  'primary',   'primary',   'primary', false),
(4,  'p2', 'Primary 2',  'primary',   'primary',   'primary', false),
(5,  'p3', 'Primary 3',  'primary',   'primary',   'primary', false),
(6,  'p4', 'Primary 4',  'primary',   'primary',   'primary', false),
(7,  'p5', 'Primary 5',  'primary',   'primary',   'primary', false),
(8,  'p6', 'Primary 6',  'primary',   'primary',   'primary', true),
(9,  'j1', 'JSS 1',      'secondary', 'secondary', 'jss',     false),
(10, 'j2', 'JSS 2',      'secondary', 'secondary', 'jss',     false),
(11, 'j3', 'JSS 3',      'secondary', 'secondary', 'jss',     true),
(12, 's1', 'SSS 1',      'secondary', 'secondary', 'sss',     false),
(13, 's2', 'SSS 2',      'secondary', 'secondary', 'sss',     false),
(14, 's3', 'SSS 3',      'secondary', 'secondary', 'sss',     true)
on conflict (seq) do nothing;

insert into public.kids_subjects (id, level, name, parent, sort) values
('n_numbers', 'nursery', 'Numbers', null, 10), ('n_letters', 'nursery', 'Letters', null, 20), ('n_play', 'nursery', 'Play', null, 30),
('p_maths', 'primary', 'Maths', null, 10), ('p_english', 'primary', 'English', null, 20), ('p_science', 'primary', 'Basic Science', null, 30), ('p_social', 'primary', 'Social Studies', null, 40),
('s_maths', 'secondary', 'Maths', null, 10), ('s_english', 'secondary', 'English', null, 20), ('s_bio', 'secondary', 'Biology/Physics', null, 30),
('s_econ', 'secondary', 'Economics', null, 40), ('s_civic', 'secondary', 'Civic Education', null, 50),
('u_course', 'university', 'Course work', null, 10), ('u_exams', 'university', 'Exams', null, 20),
('w_maths', 'waec', 'Mathematics', 's_maths', 10), ('w_english', 'waec', 'English Language', 's_english', 20), ('w_bio', 'waec', 'Biology', 's_bio', 30),
('w_phys', 'waec', 'Physics', 's_bio', 40), ('w_chem', 'waec', 'Chemistry', 's_bio', 50), ('w_econ', 'waec', 'Economics', 's_econ', 60),
('w_civic', 'waec', 'Civic Education', 's_civic', 70), ('w_gov', 'waec', 'Government', 's_civic', 80), ('w_lit', 'waec', 'Literature in English', 's_english', 90)
on conflict (id) do nothing;

-- All fictional (UNIBEN is the one real university name, already used in the game). Fees: naira per class; per level at university.
insert into public.kids_schools (id, name, icon, tier, levels, area, fee_per_class, quality, blurb, sort) values
('uselu_model',     'Uselu Model Nursery & Primary School',  '🏫', 'budget',  '{nursery,primary}', 'uselu',       20000, 0,  'A friendly neighbourhood school. Big classes, kind teachers, small fees.', 10),
('thirdeast_stars', 'Third East Bright Stars School',        '⭐', 'mid',     '{nursery,primary}', 'third_east',  55000, 5,  'Smaller classes, a library and a good name in the area.', 20),
('gra_royal_kids',  'GRA Royal Kids Academy',                '👑', 'premium', '{nursery,primary}', 'gra',        120000, 12, 'Computers, a school bus and very small classes. The best start money can buy.', 30),
('ugbowo_grammar',  'Ugbowo Grammar School',                 '📘', 'budget',  '{secondary}',       'ugbowo',      25000, 0,  'Solid basics near the campus. Full classrooms, hard-working teachers.', 40),
('ikpoba_hill_college', 'Ikpoba Hill Comprehensive College', '🏛️', 'mid',    '{secondary}',       'ikpoba_hill', 60000, 5,  'Science labs and sports. A well respected mid-range college.', 50),
('sapele_unity',    'Sapele Road Unity Secondary',           '🎓', 'premium', '{secondary}',       'sapele_rd',  150000, 12, 'Top results in WAEC, extra tutors and a strong alumni network.', 60),
('uniben',          'UNIBEN',                                '🎓', 'public',  '{university}',      'ugbowo',      60000, 4,  'The University of Benin, Ugbowo campus. Public, respected and the cheaper way to a degree.', 70),
('edo_royal_university', 'Edo Royal University',             '🏰', 'private', '{university}',      'new_benin',  400000, 14, 'A private campus with small lecture halls, labs and a lot of industry visits.', 80)
on conflict (id) do nothing;

-- the university "stage": after day 21 a child at university only has pocket money (hunger) and attention (love)
insert into public.kids_stages (id, name, emoji, from_days, rate_hunger, rate_sleep, rate_clean, rate_fun, rate_health, rate_love, needs, sort)
select 'university', 'University', '🎓', 21, 1.2, 0, 0, 0, 0, 0.9, '{hunger,love}', 60
where not exists (select 1 from kids_stages where id = 'university')
on conflict (id) do nothing;

-- school things sold with the baby and kids items (Oba Market moves a little each day, the supermarket is dearer and fixed)
insert into public.items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort, tradeable) values
('kid_books_primary', 'Textbooks (primary)', 'kids', 9500, 'A set of textbooks for Primary 1-6. Give them to your child in Family -> Kids -> School. Helps the grades for the whole of primary.', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '📚', 920, false),
('kid_books_secondary', 'Textbooks (secondary)', 'kids', 18000, 'A set of textbooks for JSS and SSS. Give them to your child in Family -> Kids -> School. Helps the grades for the whole of secondary.', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '📖', 921, false),
('kid_uniform', 'School bag & uniform', 'kids', 12000, 'A school bag and a neat uniform. Give them to your child in Family -> Kids -> School. Lasts for one life stage (Nursery, Primary or Secondary).', '{}'::jsonb,
 '{oba_market,edo_fresh_supermarket}', false, 0, '🎒', 922, false)
on conflict (id) do nothing;

insert into public.kids_items (item_id, role, uses, stages, boost_pct, sort) values
('kid_books_primary',   'books',   1, '{primary}',                    0, 50),
('kid_books_secondary', 'books',   1, '{secondary}',                  0, 51),
('kid_uniform',         'uniform', 1, '{nursery,primary,secondary}',  0, 52)
on conflict (item_id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers: switches, talent, timing, grades
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_school_on() returns boolean
language sql stable security definer set search_path = public as $$
  select bl_kids_on() and coalesce(bl_cfg_bool('kids_school.enabled'), true)
$$;

-- a fixed, hidden talent between -1 and 1 for this child and subject (same every time)
create or replace function public.bl_kids_talent(p_child bigint, p_key text) returns numeric
language sql immutable set search_path = public as $$
  select ((('x' || substr(md5(p_child::text || ':talent:' || p_key), 1, 8))::bit(32)::bigint & 2147483647) / 1073741823.5) - 1
$$;

create or replace function public.bl_kids_class_hours() returns numeric
language sql stable security definer set search_path = public as $$
  select greatest(1, bl_love_num('kids_school.class_hours', 24))
$$;

create or replace function public.bl_kids_uni_hours() returns numeric
language sql stable security definer set search_path = public as $$
  select greatest(1, bl_love_num('kids_school.uni_level_hours', 24))
$$;

-- the school level a life stage goes to (null before Nursery and after Secondary)
create or replace function public.bl_kids_stage_level(p_stage text) returns text
language sql immutable set search_path = public as $$
  select case p_stage when 'nursery' then 'nursery' when 'primary' then 'primary' when 'secondary' then 'secondary' end
$$;

-- the day a class may start at the earliest: when its life stage starts
create or replace function public.bl_kids_class_floor(c public.kids_children, p_seq int) returns timestamptz
language sql stable security definer set search_path = public as $$
  select c.born_at + make_interval(days => coalesce((select k.from_days from kids_classes cl join kids_stages k on k.id = cl.stage_id where cl.seq = p_seq), 0))
$$;

create or replace function public.bl_kids_fee_text(p_text text) returns text
language plpgsql stable security definer set search_path = public as $$
declare m text; v_fee bigint; v_out text := p_text;
begin
  if p_text is null or position('{fee:' in p_text) = 0 then return p_text; end if;
  for m in select (regexp_matches(p_text, '\{fee:([a-z0-9_]+)\}', 'g'))[1] loop
    select fee_per_class into v_fee from kids_schools where id = m;
    v_out := replace(v_out, '{fee:' || m || '}', case when v_fee is null then '?' else bl_naira(v_fee) end);
  end loop;
  return v_out;
end $$;

-- Grades of one class (or university level) for each subject, 0-100. Pure: the same inputs always give the same grades.
-- Inputs: the row (homework helps, lessons, books, uniform, fee timing, penalty), the school's quality, whether the child attended and the
-- share of the class the child's needs were fine (0-1). Returns {"grades":[{"id","name","g"}], "avg"}.
create or replace function public.bl_kids_school_calc(p_child bigint, s public.kids_school, p_level text, p_stage text, p_quality numeric, p_attended boolean, p_ratio numeric) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_pts numeric; v_g numeric; sub record; v_arr jsonb := '[]'::jsonb; v_sum numeric := 0; v_n int := 0; v_tal numeric := bl_love_num('kids_school.talent_pts', 8);
  v_on_time boolean := s.fee_paid_at is not null and s.class_start is not null
    and s.fee_paid_at <= s.class_start + make_interval(secs => (bl_love_num('kids_school.fee_grace_hours', 12) * 3600)::double precision);
begin
  v_pts := bl_love_num('kids_school.base_grade', 38)
         + case when v_on_time then bl_love_num('kids_school.fee_on_time_pts', 6) else 0 end
         + (coalesce(p_ratio, 0.5) - 0.5) * 2 * bl_love_num('kids_school.needs_pts', 12)
         + cardinality(s.hw_users) * bl_love_num('kids_school.homework_pts', 4)
         + case when p_level in ('primary', 'secondary') and s.books_stage = p_stage then bl_love_num('kids_school.books_pts', 5) else 0 end
         + case when p_level <> 'university' and s.uniform_stage = p_stage then bl_love_num('kids_school.uniform_pts', 3) else 0 end
         + case when s.lessons_at is not null then bl_love_num('kids_school.lessons_pts', 8) else 0 end
         - s.penalty;
  for sub in select * from kids_subjects k where k.level = p_level and k.active order by k.sort, k.id loop
    v_g := case when p_attended then v_pts else bl_love_num('kids_school.missed_grade', 22) end
           + (bl_kids_talent(p_child, sub.id) + 0.5 * bl_kids_talent(p_child, '*')) * v_tal * case when p_attended then 1 else 0.5 end;
    v_g := least(100, greatest(0, v_g));
    if p_attended then v_g := least(100, v_g * (1 + coalesce(p_quality, 0) / 100.0)); end if;
    v_g := round(v_g);
    v_arr := v_arr || jsonb_build_object('id', sub.id, 'name', sub.name, 'g', v_g);
    v_sum := v_sum + v_g; v_n := v_n + 1;
  end loop;
  return jsonb_build_object('grades', v_arr, 'avg', case when v_n > 0 then round(v_sum / v_n, 1) else 0 end);
end $$;

-- Share (0-1) of the time the child's needs were fine between two score snapshots (care_good/care_total of the child row, minus the class-start snapshot)
create or replace function public.bl_kids_school_ratio(c public.kids_children, s public.kids_school) returns numeric
language sql immutable set search_path = public as $$
  select case when c.care_total - s.total0 > 0 then least(1, greatest(0, (c.care_good - s.good0) / (c.care_total - s.total0))) else 0.4 end
$$;

-- one line for the report card / outcome: the teachers are fictional
create or replace function public.bl_kids_teacher(p_child bigint, p_key text) returns text
language sql immutable set search_path = public as $$
  select (array['Mrs. Efe Aghedo', 'Mr. Osaretin Aigbe', 'Madam Ivie Ekhator', 'Mr. Nosa Okungbowa', 'Mrs. Uyi Edokpayi', 'Madam Joy Orobosa'])
         [1 + (('x' || substr(md5(p_child::text || ':teacher:' || p_key), 1, 8))::bit(32)::bigint & 2147483647) % 6]
$$;

create or replace function public.bl_kids_remark(p_child bigint, p_key text, p_band text) returns text
language sql immutable set search_path = public as $$
  select (case p_band
    when 'Excellent' then array['Ehen! {c} is a real star in my class. Keep it up, we are proud.', '{c} works hard and helps the others. A promising future, God willing.', 'Top of the class. {c} should keep reading and keep asking questions.']
    when 'Very good' then array['{c} is doing very well and gets better each term. Well done.', 'A bright, polite child. A little more reading at home and {c} will fly.', 'Good effort, {c}. The teachers are happy with you.']
    when 'Good' then array['{c} is doing fine. With a little more help at home the grades will climb.', 'A good, steady term. {c} can do even better with some extra reading.', 'Not bad at all, {c}. Keep going and do not give up.']
    else array['{c} needs more help, please. Check the homework and send the child to class every day.', 'A hard term for {c}. Do not worry: with books, lessons and patience {c} will improve.', '{c} is a good child but is behind. Please work with the teachers and visit the school.'] end)
    [1 + (('x' || substr(md5(p_child::text || ':remark:' || p_key), 1, 8))::bit(32)::bigint & 2147483647) % 3]
$$;

create or replace function public.bl_kids_position(p_avg numeric) returns text
language sql immutable set search_path = public as $$
  select case when p_avg >= 75 then 'Excellent' when p_avg >= 60 then 'Very good' when p_avg >= 50 then 'Good' else 'Needs help' end
$$;

-- Hit a child's need (never below 0) at the current time. Used for sadness (a missed class, an ignored request).
create or replace function public.bl_kids_need_hit(c public.kids_children, p_need text, p_delta numeric) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare v_now timestamptz := bl_now(); v_cur numeric; v_new numeric;
begin
  if c.status not in ('home', 'university') or p_delta = 0 then return c; end if;
  if not (p_need = any (bl_kids_stage_needs(c, v_now))) then return c; end if;
  c := bl_kids_score_tick(c, v_now);
  v_cur := bl_kids_val(c, p_need, v_now);
  v_new := greatest(0, least(100, v_cur + p_delta));
  if v_new <> v_cur then
    execute format('update kids_children set %I = %L, %I = %L where id = %s', p_need, v_new, p_need || '_at', v_now, c.id);
  end if;
  select * into c from kids_children where id = c.id;
  return c;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. The school clock: what happens next and when (the same function drives the sweep and the lazy read)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_school_next(c public.kids_children) returns table (kind text, at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare s public.kids_school; v_hours numeric; v_end timestamptz; cl public.kids_classes; sc public.kids_schools;
begin
  if not bl_kids_school_on() or c.status not in ('home', 'university') then return; end if;
  select * into s from kids_school x where x.child_id = c.id;
  if not found then return; end if;
  if s.uni_state = 'deciding' then
    if s.uni_deadline is not null then return query select 'decide'::text, s.uni_deadline; end if;
    return;
  elsif s.uni_state = 'studying' then
    v_hours := bl_kids_uni_hours();
    v_end := s.class_start + make_interval(secs => (v_hours * 3600)::double precision);
    if s.fee_paid_at is null and not s.fee_reminded and s.fee_amount > 0 and s.class_start + make_interval(secs => (v_hours * 1800)::double precision) < v_end then
      return query select 'remind'::text, s.class_start + make_interval(secs => (v_hours * 1800)::double precision);
    end if;
    return query select 'end'::text, v_end;
    return;
  elsif s.uni_state is not null or s.state <> 'learning' then
    return;
  end if;
  v_hours := bl_kids_class_hours();
  if s.class_start is null then
    if s.school_id is null then return; end if;
    select * into cl from kids_classes x where x.seq = s.seq;
    select * into sc from kids_schools x where x.id = s.school_id;
    if not found or not sc.active or cl.seq is null or not (cl.level = any (sc.levels)) then return; end if;
    return query select 'start'::text, greatest(coalesce(s.ready_at, bl_kids_class_floor(c, s.seq)), bl_kids_class_floor(c, s.seq));
    return;
  end if;
  v_end := s.class_start + make_interval(secs => (v_hours * 3600)::double precision);
  if not s.req_done and s.req_at is not null then return query select 'req'::text, s.req_at; end if;
  if s.fee_paid_at is null and not s.fee_reminded and s.fee_amount > 0 then
    return query select 'remind'::text, s.class_start + make_interval(secs => (v_hours * 1800)::double precision);
  end if;
  return query select 'end'::text, v_end;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Report cards, WAEC, outcome
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_report_card(c public.kids_children, p_grp text, p_promoted boolean, p_extra text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_grades jsonb; v_avg numeric; v_band text; v_title text; v_school text; v_nm text := coalesce(c.name, 'Your child');
begin
  if p_grp = 'university' then
    select jsonb_agg(jsonb_build_object('name', q.name, 'g', round(q.a)) order by q.ord), avg(q.a) into v_grades, v_avg
      from (select t.x ->> 'name' as name, avg((t.x ->> 'g')::numeric) as a, min(t.ord) as ord
              from (select distinct on (r.seq) r.* from kids_school_results r where r.child_id = c.id and r.level = 'university' order by r.seq, r.id desc) l,
                   jsonb_array_elements(l.grades) with ordinality as t(x, ord) group by 1) q;
    select sc.name into v_school from kids_school_results r join kids_schools sc on sc.id = r.school_id where r.child_id = c.id and r.level = 'university' order by r.id desc limit 1;
  else
    select jsonb_agg(jsonb_build_object('name', q.name, 'g', round(q.a)) order by q.ord), avg(q.a) into v_grades, v_avg
      from (select t.x ->> 'name' as name, avg((t.x ->> 'g')::numeric) as a, min(t.ord) as ord
              from (select distinct on (r.seq) r.* from kids_school_results r where r.child_id = c.id and r.level <> 'university'
                      and r.seq in (select k.seq from kids_classes k where k.grp = p_grp) order by r.seq, r.id desc) l,
                   jsonb_array_elements(l.grades) with ordinality as t(x, ord) group by 1) q;
    select sc.name into v_school from kids_school_results r join kids_schools sc on sc.id = r.school_id
     where r.child_id = c.id and r.level <> 'university' and r.seq in (select k.seq from kids_classes k where k.grp = p_grp) order by r.id desc limit 1;
  end if;
  if v_grades is null then return; end if;
  v_band := bl_kids_position(v_avg);
  v_title := case p_grp when 'nursery' then 'Nursery report card' when 'primary' then 'Primary school report card' when 'jss' then 'JSS report card'
                        when 'sss' then 'SSS report card' else 'University report card' end;
  insert into kids_report_cards (child_id, stage_key, title, school_name, grades, avg, position, remark, teacher, promoted, extra)
  values (c.id, p_grp, v_title, coalesce(v_school, ''), v_grades, round(v_avg, 1), v_band,
          replace(bl_kids_remark(c.id, p_grp, v_band), '{c}', v_nm), bl_kids_teacher(c.id, p_grp), p_promoted, p_extra)
  on conflict (child_id, stage_key) do nothing;
  perform bl_kids_notify_both(c, 'kids_report', '📋 ' || v_nm || '''s ' || lower(v_title) || ' is ready',
                              v_band || ' with an average of ' || round(v_avg)::int || '. Open Family -> Kids -> Report cards to read it and share it.');
end $$;

create or replace function public.bl_kids_waec(c public.kids_children) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  rr record; w record; v_papers jsonb := '[]'::jsonb; v_parent numeric; v_score numeric; v_mark numeric := bl_love_num('kids_school.waec_credit_mark', 55);
  v_need int := bl_love_num('kids_school.waec_pass_credits', 5)::int; v_credits int := 0; v_pen numeric := 0; v_letter text; v_maths boolean := false; v_eng boolean := false; v_pass boolean; v_txt text;
begin
  select * into rr from kids_school_results r where r.child_id = c.id and r.seq = 14 order by r.id desc limit 1;
  if exists (select 1 from kids_school_requests q where q.child_id = c.id and q.seq = 14 and q.req_type = 'waec' and q.status = 'ignored') then v_pen := 6; end if;
  for w in select * from kids_subjects k where k.level = 'waec' and k.active order by k.sort, k.id loop
    select (x ->> 'g')::numeric into v_parent from jsonb_array_elements(coalesce(rr.grades, '[]'::jsonb)) x where x ->> 'id' = w.parent limit 1;
    v_score := round(least(100, greatest(0, coalesce(v_parent, 40) + bl_kids_talent(c.id, w.id) * 0.75 * bl_love_num('kids_school.talent_pts', 8) - v_pen)));
    v_letter := case when v_score >= v_mark and v_score >= 75 then 'A1' when v_score >= v_mark and v_score >= 70 then 'B2' when v_score >= v_mark and v_score >= 65 then 'B3'
                     when v_score >= v_mark and v_score >= 60 then 'C4' when v_score >= v_mark and v_score >= 55 then 'C5' when v_score >= v_mark then 'C6'
                     when v_score >= 45 then 'D7' when v_score >= 40 then 'E8' else 'F9' end;
    if v_score >= v_mark then
      v_credits := v_credits + 1;
      if w.id = 'w_maths' then v_maths := true; end if;
      if w.id = 'w_english' then v_eng := true; end if;
    end if;
    v_papers := v_papers || jsonb_build_object('id', w.id, 'name', w.name, 'score', v_score, 'letter', v_letter, 'credit', v_score >= v_mark);
  end loop;
  v_pass := v_credits >= v_need and v_maths and v_eng;
  v_txt := case when v_pass then v_credits || ' credits including Maths and English'
                when v_credits < v_need then 'fewer than ' || v_need || ' credits'
                else v_credits || ' credits but no credit in Maths and English' end;
  return jsonb_build_object('papers', v_papers, 'credits', v_credits, 'pass', v_pass, 'text', v_txt, 'need', v_need);
end $$;

create or replace function public.bl_kids_degree(p_avg numeric) returns text
language sql stable security definer set search_path = public as $$
  select case when p_avg >= bl_love_num('kids_school.uni_first_min', 70) then 'First Class'
              when p_avg >= bl_love_num('kids_school.uni_upper_min', 60) then 'Second Class Upper'
              when p_avg >= bl_love_num('kids_school.uni_lower_min', 55) then 'Second Class Lower' else 'Third Class' end
$$;

create or replace function public.bl_kids_course(p_child bigint) returns text
language sql immutable set search_path = public as $$
  select (array['Medicine', 'Law', 'Engineering', 'Accounting', 'Computer Science', 'Mass Communication', 'Agriculture', 'Pharmacy', 'Architecture', 'Economics'])
         [1 + (('x' || substr(md5(p_child::text || ':course'), 1, 8))::bit(32)::bigint & 2147483647) % 10]
$$;

-- "Got 7 credits in WAEC and started work", "Didn't finish secondary school (reached SSS 1)", "Graduated from UNIBEN with Second Class Upper in Medicine"
create or replace function public.bl_kids_outcome(c public.kids_children) returns text
language plpgsql stable security definer set search_path = public as $$
declare s public.kids_school; v_cls text; v_sc text; v_credits int;
begin
  select * into s from kids_school x where x.child_id = c.id;
  if not found or s.max_seq = 0 then
    if s.uni_state is null then return 'Moved out without going to school'; end if;
  end if;
  select name into v_cls from kids_classes where seq = s.max_seq;
  select name into v_sc from kids_schools where id = s.school_id;
  v_credits := coalesce((s.waec ->> 'credits')::int, 0);
  if s.uni_state = 'graduated' then
    return 'Graduated from ' || coalesce(v_sc, 'university') || ' with ' || coalesce(s.uni_degree, 'a degree') || ' in ' || coalesce(s.uni_course, 'their course');
  elsif s.uni_state = 'dropped' then
    return 'Didn''t finish university (' || coalesce(v_sc, 'university') || ', ' || coalesce(s.uni_course, 'their course') || ')';
  elsif coalesce((s.waec ->> 'pass')::boolean, false) then
    return 'Got ' || v_credits || ' credits in WAEC and started work';
  elsif s.waec is not null then
    return 'Sat WAEC but did not get enough credits (' || v_credits || ')';
  elsif s.max_seq >= 9 then
    return 'Didn''t finish secondary school (reached ' || v_cls || ')';
  elsif s.max_seq >= 3 then
    return 'Didn''t finish primary school (reached ' || v_cls || ')';
  elsif s.max_seq >= 1 then
    return 'Only went as far as ' || v_cls;
  end if;
  return 'Moved out without going to school';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. The steps: a class starts, a request comes, a reminder, a class ends (grades, promotion, report card, WAEC), university
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_school_start(c public.kids_children, p_at timestamptz) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare
  s public.kids_school; sc public.kids_schools; cl public.kids_classes; v_hours numeric := bl_kids_class_hours(); v_type text; v_req timestamptz; v_arr text[]; v_nm text := bl_kids_label(c);
begin
  select * into s from kids_school x where x.child_id = c.id for update;
  select * into sc from kids_schools x where x.id = s.school_id;
  select * into cl from kids_classes x where x.seq = s.seq;
  c := bl_kids_score_tick(c, p_at);
  if cl.seq = 14 then
    v_type := 'waec';
  elsif bl_rand() * 100 < bl_love_num('kids_school.request_pct', 60) then
    v_arr := case when cl.level = 'nursery' then array['pta', 'party'] else array['pta', 'excursion', 'sports', 'party'] end;
    v_type := v_arr[1 + floor(bl_rand() * cardinality(v_arr))::int % cardinality(v_arr)];
  end if;
  v_req := p_at + make_interval(secs => (v_hours * 3600 * (0.15 + 0.5 * bl_rand()))::double precision);
  update kids_school set class_start = p_at, fee_amount = sc.fee_per_class, fee_paid_at = case when sc.fee_per_class <= 0 then p_at end, fee_paid_by = null, fee_reminded = false,
         hw_users = '{}', hw_last = null, lessons_at = null, good0 = c.care_good, total0 = c.care_total, penalty = 0, max_seq = greatest(max_seq, seq),
         req_type = v_type, req_at = case when v_type is null then null else v_req end, req_done = v_type is null
   where child_id = c.id;
  if sc.fee_per_class > 0 then
    perform bl_kids_notify_both(c, 'kids_school_fee', '🎒 ' || v_nm || ' starts ' || cl.name,
                                sc.name || ' asks for ' || bl_naira(sc.fee_per_class) || ' in school fees. Pay in Family -> Kids -> School so ' || v_nm || ' can attend.');
  end if;
  select * into c from kids_children where id = c.id;
  return c;
end $$;

-- a school request card (PTA levy, excursion, sports wear, party, WAEC fee) for BOTH parents; the first to pay resolves it
create or replace function public.bl_kids_school_request(c public.kids_children, p_at timestamptz) returns void
language plpgsql security definer set search_path = public as $$
declare
  s public.kids_school; v_hours numeric := bl_kids_class_hours(); v_end timestamptz; u uuid; v_rid bigint; v_cap int := bl_love_num('moments.daily_cap', 3)::int; v_n int;
begin
  select * into s from kids_school x where x.child_id = c.id for update;
  v_end := s.class_start + make_interval(secs => (v_hours * 3600)::double precision);
  if s.req_type is null or bl_now() >= v_end or not bl_moments_on() then
    update kids_school set req_done = true where child_id = c.id;
    return;
  end if;
  -- respect the daily cap of life moments for both parents: try again later in the class
  foreach u in array array[c.parent_a, c.parent_b] loop
    continue when u is null;
    select count(*) into v_n from player_moments x where x.user_id = u and x.counts and x.created_at >= bl_moment_day_start(bl_now());
    if v_n >= v_cap and s.req_type <> 'waec' then
      update kids_school set req_at = greatest(req_at, bl_now()) + interval '3 hours', req_done = (greatest(req_at, bl_now()) + interval '3 hours' >= v_end) where child_id = c.id;
      return;
    end if;
  end loop;
  update kids_school set req_done = true where child_id = c.id;
  insert into kids_school_requests (child_id, seq, attempt, req_type) values (c.id, s.seq, s.attempt, s.req_type) on conflict (child_id, seq, attempt) do nothing returning id into v_rid;
  if v_rid is null then return; end if;
  foreach u in array array[c.parent_a, c.parent_b] loop
    continue when u is null;
    perform bl_moment_create(u, 'school_' || s.req_type, jsonb_build_object('child_id', c.id, 'req_id', v_rid), bl_now(), true);
  end loop;
end $$;

create or replace function public.bl_kids_school_close(c public.kids_children) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare
  s public.kids_school; sc public.kids_schools; cl public.kids_classes; v_end timestamptz; v_r numeric; v_att boolean; j jsonb; v_avg numeric; v_pass boolean; v_nm text := bl_kids_label(c);
  v_on_time boolean; v_next int; v_att_next int; v_waec jsonb; v_extra text; v_cls_name text; v_level text;
begin
  select * into s from kids_school x where x.child_id = c.id for update;
  select * into sc from kids_schools x where x.id = s.school_id;
  select * into cl from kids_classes x where x.seq = s.seq;
  v_end := s.class_start + make_interval(secs => (bl_kids_class_hours() * 3600)::double precision);
  c := bl_kids_score_tick(c, v_end);
  v_r := bl_kids_school_ratio(c, s);
  v_att := s.fee_paid_at is not null;
  v_on_time := v_att and s.fee_paid_at <= s.class_start + make_interval(secs => (bl_love_num('kids_school.fee_grace_hours', 12) * 3600)::double precision);
  j := bl_kids_school_calc(c.id, s, cl.level, cl.stage_id, sc.quality, v_att, v_r);
  v_avg := (j ->> 'avg')::numeric;
  v_pass := v_att and v_avg >= bl_love_num('kids_school.pass_mark', 50);
  insert into kids_school_results (child_id, level, seq, attempt, class_name, school_id, attended, on_time, grades, avg, promoted, created_at)
  values (c.id, cl.level, cl.seq, s.attempt, cl.name, s.school_id, v_att, v_on_time, j -> 'grades', v_avg, v_pass, v_end);
  -- an open request of this class is over (no penalty: nobody ignored it)
  update kids_school_requests set status = 'ignored' where child_id = c.id and seq = s.seq and attempt = s.attempt and status = 'open';
  update player_moments set status = 'expired', answered_at = bl_now(), seen_at = bl_now()
   where context ->> 'child_id' = c.id::text and status in ('pending', 'snoozed', 'scheduled') and moment_id in (select id from life_moments where kind = 'kids_school');
  if not v_att then
    update kids_school set missed = missed + 1 where child_id = c.id;
    c := bl_kids_need_hit(c, 'fun', -bl_love_num('kids_school.missed_fun_hit', 20));
    c := bl_kids_need_hit(c, 'love', -round(bl_love_num('kids_school.missed_fun_hit', 20) / 2));
  end if;
  if v_pass then
    if cl.seq = 14 then
      v_waec := bl_kids_waec(c);
      update kids_school set waec = v_waec, state = 'finished' where child_id = c.id;
      v_extra := 'WAEC: ' || (v_waec ->> 'text');
    end if;
    if cl.last_of_grp then perform bl_kids_report_card(c, cl.grp, true, v_extra); end if;
    v_next := cl.seq + 1;
    update kids_school set seq = case when cl.seq = 14 then 14 else v_next end, attempt = case when cl.seq = 14 then attempt else 1 end,
           class_start = null, ready_at = v_end, fee_paid_at = null, fee_paid_by = null, fee_reminded = false, req_type = null, req_at = null, req_done = true
     where child_id = c.id;
    perform bl_kids_notify_both(c, 'kids_school_result', '✅ ' || v_nm || ' passed ' || cl.name,
                                'Average ' || round(v_avg)::int || '. ' || v_nm || ' is promoted' || case when cl.seq = 14 then ' and sat WAEC: ' || (v_waec ->> 'text') || '.' else '.' end);
    if cl.seq = 14 then
      perform bl_kids_notify_both(c, 'kids_waec', case when (v_waec ->> 'pass')::boolean then '🎓 ' || v_nm || ' passed WAEC!' else '📄 ' || v_nm || '''s WAEC results are out' end,
                                  'WAEC result: ' || (v_waec ->> 'text') || '.');
    else
      select level into v_level from kids_classes where seq = v_next;
      if not (v_level = any (coalesce(sc.levels, '{}'))) then
        perform bl_kids_notify_both(c, 'kids_school_pick', '🏫 Time to pick a ' || v_level || ' school for ' || v_nm,
                                    sc.name || ' does not teach ' || v_level || '. Choose a new school in Family -> Kids -> School.');
      end if;
    end if;
  else
    update kids_school set attempt = attempt + 1, class_start = null, ready_at = v_end, fee_paid_at = null, fee_paid_by = null, fee_reminded = false, req_type = null, req_at = null, req_done = true
     where child_id = c.id;
    perform bl_kids_notify_both(c, 'kids_school_result', '↩️ ' || v_nm || ' repeats ' || cl.name,
                                case when v_att then 'Average ' || round(v_avg)::int || ', the pass mark is ' || bl_love_num('kids_school.pass_mark', 50)::int || '. A little more help and ' || v_nm || ' will make it next time.'
                                     else v_nm || ' missed the class because the fees were not paid, so ' || v_nm || ' repeats it.' end);
  end if;
  select * into c from kids_children where id = c.id;
  return c;
end $$;

-- A university level ends: grades, pass / repeat / drop out, or graduation
create or replace function public.bl_kids_uni_close(c public.kids_children) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare
  s public.kids_school; sc public.kids_schools; v_end timestamptz; v_r numeric; v_att boolean; j jsonb; v_avg numeric; v_pass boolean; v_nm text := bl_kids_label(c); v_all numeric; v_deg text;
  v_hours numeric := bl_kids_uni_hours(); v_on_time boolean; v_name text;
begin
  select * into s from kids_school x where x.child_id = c.id for update;
  select * into sc from kids_schools x where x.id = s.school_id;
  v_end := s.class_start + make_interval(secs => (v_hours * 3600)::double precision);
  c := bl_kids_score_tick(c, v_end);
  v_r := bl_kids_school_ratio(c, s);
  v_att := s.fee_paid_at is not null;
  v_on_time := v_att and s.fee_paid_at <= s.class_start + make_interval(secs => (bl_love_num('kids_school.fee_grace_hours', 12) * 3600)::double precision);
  j := bl_kids_school_calc(c.id, s, 'university', 'university', sc.quality, v_att, v_r);
  v_avg := (j ->> 'avg')::numeric;
  v_pass := v_att and v_avg >= bl_love_num('kids_school.pass_mark', 50);
  v_name := (s.uni_level * 100) || 'L';
  insert into kids_school_results (child_id, level, seq, attempt, class_name, school_id, attended, on_time, grades, avg, promoted, created_at)
  values (c.id, 'university', s.uni_level, s.uni_repeats + 1, v_name, s.school_id, v_att, v_on_time, j -> 'grades', v_avg, v_pass, v_end);
  if not v_att then
    update kids_school set missed = missed + 1 where child_id = c.id;
    c := bl_kids_need_hit(c, 'love', -bl_love_num('kids_school.missed_fun_hit', 20));
  end if;
  if v_pass and s.uni_level >= 4 then
    select avg(q.avg) into v_all from (select distinct on (r.seq) r.avg from kids_school_results r where r.child_id = c.id and r.level = 'university' and r.promoted order by r.seq, r.id desc) q;
    v_deg := bl_kids_degree(v_all);
    update kids_school set uni_state = 'graduated', uni_degree = v_deg, uni_avg = round(v_all, 1), class_start = null, ready_at = v_end where child_id = c.id;
    perform bl_kids_report_card(c, 'university', true, v_deg || ' in ' || coalesce(s.uni_course, 'their course'));
    select * into c from kids_children where id = c.id;
    return bl_kids_finalize(c, v_end, 'graduated');
  elsif v_pass then
    update kids_school set uni_level = uni_level + 1, class_start = v_end, ready_at = v_end, fee_amount = sc.fee_per_class, fee_paid_at = case when sc.fee_per_class <= 0 then v_end end, fee_paid_by = null,
           fee_reminded = false, hw_users = '{}', hw_last = null, lessons_at = null, good0 = c.care_good, total0 = c.care_total, penalty = 0 where child_id = c.id;
    perform bl_kids_notify_both(c, 'kids_uni_result', '✅ ' || v_nm || ' passed ' || v_name, 'Average ' || round(v_avg)::int || '. On to ' || ((s.uni_level + 1) * 100) || 'L. ' || sc.name || ' asks for ' || bl_naira(sc.fee_per_class) || '.');
  elsif s.uni_repeats >= bl_love_num('kids_school.uni_max_repeats', 2)::int then
    update kids_school set uni_state = 'dropped', class_start = null, ready_at = v_end where child_id = c.id;
    perform bl_kids_report_card(c, 'university', false, 'Left university in ' || v_name);
    select * into c from kids_children where id = c.id;
    return bl_kids_finalize(c, v_end, 'dropped');
  else
    update kids_school set uni_repeats = uni_repeats + 1, class_start = v_end, ready_at = v_end, fee_amount = sc.fee_per_class, fee_paid_at = case when sc.fee_per_class <= 0 then v_end end, fee_paid_by = null,
           fee_reminded = false, hw_users = '{}', hw_last = null, lessons_at = null, good0 = c.care_good, total0 = c.care_total, penalty = 0 where child_id = c.id;
    perform bl_kids_notify_both(c, 'kids_uni_result', '↩️ ' || v_nm || ' repeats ' || v_name,
                                case when v_att then 'Average ' || round(v_avg)::int || '. Repeat ' || (s.uni_repeats + 1) || ' of ' || bl_love_num('kids_school.uni_max_repeats', 2)::int || ' allowed.'
                                     else 'The fees were not paid, so the level was missed. Repeat ' || (s.uni_repeats + 1) || ' of ' || bl_love_num('kids_school.uni_max_repeats', 2)::int || ' allowed.' end);
  end if;
  select * into c from kids_children where id = c.id;
  return c;
end $$;

-- the parents choose university (or work). p_school = a university id, or 'work'.
create or replace function public.bl_kids_uni_choose(p_uid uuid, p_child bigint, p_school text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.kids_children; s public.kids_school; sc public.kids_schools; v_now timestamptz := bl_now(); v_nm text; v_who text; v_course text;
begin
  select * into c from kids_children where id = p_child and (parent_a = p_uid or parent_b = p_uid) and status = 'university' for update;
  if not found then return '[]'::jsonb; end if;
  select * into s from kids_school where child_id = c.id for update;
  if not found or s.uni_state is distinct from 'deciding' then return '[]'::jsonb; end if;
  v_nm := bl_kids_label(c);
  select username into v_who from profiles where id = p_uid;
  update player_moments set status = 'answered', handled_by = p_uid, outcome = 'Already handled by @' || coalesce(v_who, 'your partner') || ' 💛', answered_at = v_now
   where moment_id = 'uni_decision' and user_id <> p_uid and status in ('pending', 'snoozed', 'scheduled') and context ->> 'child_id' = c.id::text;
  if p_school = 'work' then
    update kids_school set uni_state = 'working', uni_deadline = null where child_id = c.id;
    perform bl_kids_finalize(c, v_now, 'work');
    return to_jsonb(v_nm || ' will start working');
  end if;
  select * into sc from kids_schools x where x.id = p_school and x.active and 'university' = any (x.levels);
  if not found then
    raise exception 'That university is not taking students right now.' using errcode = 'P0001', hint = 'bad_school';
  end if;
  v_course := bl_kids_course(c.id);
  c := bl_kids_score_tick(c, v_now);
  update kids_school set school_id = sc.id, uni_state = 'studying', uni_level = 1, uni_repeats = 0, uni_deadline = null, uni_course = v_course, class_start = v_now, ready_at = v_now,
         fee_amount = sc.fee_per_class, fee_paid_at = case when sc.fee_per_class <= 0 then v_now end, fee_paid_by = null, fee_reminded = false, hw_users = '{}', hw_last = null, lessons_at = null,
         good0 = c.care_good, total0 = c.care_total, penalty = 0 where child_id = c.id;
  perform bl_kids_notify(case when c.parent_a = p_uid then c.parent_b else c.parent_a end, 'kids_uni_start', '🎓 ' || v_nm || ' goes to ' || sc.name,
                         '@' || coalesce(v_who, 'your partner') || ' chose ' || sc.name || ' (' || v_course || '). Fees: ' || bl_naira(sc.fee_per_class) || ' a level.', c.id);
  return to_jsonb(v_nm || ' starts ' || v_course || ' at ' || sc.name);
end $$;

-- the clock itself: do every step whose time has come, in order
create or replace function public.bl_kids_school_tick(c public.kids_children, p_at timestamptz default null) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare n record; v_i int := 0; v_at timestamptz := coalesce(p_at, bl_now()); s public.kids_school; v_nm text;
begin
  if not bl_kids_school_on() then return c; end if;
  loop
    v_i := v_i + 1;
    exit when v_i > 60;
    select * into c from kids_children where id = c.id;
    select x.kind, x.at into n from bl_kids_school_next(c) x order by x.at limit 1;
    exit when n.kind is null or n.at > v_at;
    if n.kind = 'start' then
      c := bl_kids_school_start(c, n.at);
    elsif n.kind = 'req' then
      perform bl_kids_school_request(c, n.at);
    elsif n.kind = 'remind' then
      update kids_school set fee_reminded = true where child_id = c.id returning * into s;
      perform bl_kids_notify_both(c, 'kids_school_fee', '💸 School fees for ' || bl_kids_label(c) || ' are still due',
                                  bl_naira(s.fee_amount) || ' is waiting. If the fee is not paid before the class ends, ' || bl_kids_label(c) || ' misses it.');
    elsif n.kind = 'end' then
      select * into s from kids_school where child_id = c.id;
      c := case when s.uni_state = 'studying' then bl_kids_uni_close(c) else bl_kids_school_close(c) end;
    elsif n.kind = 'decide' then
      perform bl_kids_uni_choose((select p from unnest(array[c.parent_a, c.parent_b]) p where p is not null limit 1), c.id, 'work');
      update player_moments set status = 'expired', answered_at = bl_now(), seen_at = bl_now()
       where moment_id = 'uni_decision' and context ->> 'child_id' = c.id::text and status in ('pending', 'snoozed', 'scheduled');
      select * into c from kids_children where id = c.id;
    end if;
  end loop;
  select * into c from kids_children where id = c.id;
  return c;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Growing up (day 21), the university decision, and the final "moves out" with the school outcome
-- ---------------------------------------------------------------------------------------------
-- p_path: 'grow' (day 21, no university), 'work' (chose work after WAEC), 'dropped', 'graduated'
create or replace function public.bl_kids_finalize(c public.kids_children, p_at timestamptz, p_path text) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare
  v_share numeric; v_score int; v_tier text; v_gift bigint := 0; v_cap numeric := bl_love_num('kids.gift_max_spend_pct', 25) / 100.0; u uuid; v_paid bigint; v_nm text; v_spent bigint; v_msg text;
  v_out text; g text;
begin
  c := bl_kids_score_tick(c, p_at);
  v_share := case when c.care_total > 0 then c.care_good / c.care_total else 1 end;
  v_score := greatest(0, round(100 * v_share)::int - (bl_love_num('kids.removal_penalty', 25) * c.removals)::int);
  v_tier := case when p_path = 'graduated' then 'graduate'
                 when v_score >= bl_love_num('kids.tier_gold_min', 85) then 'gold' when v_score >= bl_love_num('kids.tier_silver_min', 65) then 'silver'
                 when v_score >= bl_love_num('kids.tier_bronze_min', 40) then 'bronze' else 'none' end;
  v_gift := case v_tier when 'graduate' then bl_love_num('kids.gift_graduate', 250000) when 'gold' then bl_love_num('kids.gift_gold', 100000) when 'silver' then bl_love_num('kids.gift_silver', 50000)
                        when 'bronze' then bl_love_num('kids.gift_bronze', 20000) else 0 end;
  v_nm := bl_kids_label(c);
  -- a stage that was left half way still gets a report card ("left school during this stage")
  for g in select distinct cl.grp from kids_school_results r join kids_classes cl on cl.seq = r.seq
            where r.child_id = c.id and r.level <> 'university' and not exists (select 1 from kids_report_cards k where k.child_id = c.id and k.stage_key = cl.grp) loop
    perform bl_kids_report_card(c, g, false, 'Left school during this stage');
  end loop;
  v_out := bl_kids_outcome(c);
  update kids_children set status = 'grown', grown_at = p_at, sick_since = null, illness_id = null, next_alert_at = null, care_score = v_score, tier = v_tier, gift_a = 0, gift_b = 0, outcome = v_out
   where id = c.id returning * into c;
  foreach u in array array[c.parent_a, c.parent_b] loop
    continue when u is null;
    v_spent := case when u = c.parent_a then c.spent_a else c.spent_b end;
    v_paid := least(v_gift::bigint, floor(v_spent * v_cap)::bigint);
    if v_paid > 0 then
      perform bl_add_money(u, 'cash', v_paid, 'kid_gift', jsonb_build_object('label', 'Thank-you gift from ' || v_nm, 'child', c.id, 'tier', v_tier));
    end if;
    v_msg := v_out || '. ' || v_nm || ' is moving out with a keepsake from you both.'
             || case when v_tier = 'none' then ' You are a Proud parent 🏅'
                     else ' You earned the ' || initcap(v_tier) || ' Proud parent badge 🏅' || case when v_paid > 0 then ' and a thank-you gift of ' || bl_naira(v_paid) || '.' else '.' end end;
    perform bl_kids_notify(u, 'kids_grown', case when p_path = 'graduated' then '🎓 ' || v_nm || ' graduated!' else '🎓 ' || v_nm || ' has grown up!' end, v_msg, c.id,
                           jsonb_build_object('tier', v_tier, 'gift', v_paid, 'score', v_score, 'outcome', v_out));
    if u = c.parent_a then update kids_children set gift_a = v_paid where id = c.id; else update kids_children set gift_b = v_paid where id = c.id; end if;
  end loop;
  select * into c from kids_children where id = c.id;
  return c;
end $$;

create or replace function public.bl_kids_finish(c public.kids_children, p_at timestamptz) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare s public.kids_school; u uuid; v_nm text;
begin
  c := bl_kids_school_tick(c, p_at);
  if c.status <> 'home' then return c; end if;
  select * into s from kids_school x where x.child_id = c.id for update;
  if found and s.uni_state is null and coalesce(bl_cfg_bool('kids_school.uni_enabled'), true) and bl_kids_school_on()
     and coalesce((s.waec ->> 'pass')::boolean, false) and bl_moments_on() then
    -- WAEC passed: the parents decide about university before the child moves out
    c := bl_kids_score_tick(c, p_at);
    v_nm := bl_kids_label(c);
    update kids_children set status = 'university', sick_since = null, illness_id = null, next_alert_at = null where id = c.id returning * into c;
    update kids_school set uni_state = 'deciding', uni_level = 0, uni_deadline = bl_now() + make_interval(secs => (bl_love_num('kids_school.uni_decision_hours', 36) * 3600)::double precision) where child_id = c.id;
    perform bl_kids_close_cards(c.id, null, null);
    foreach u in array array[c.parent_a, c.parent_b] loop
      continue when u is null;
      perform bl_moment_create(u, 'uni_decision', jsonb_build_object('child_id', c.id, 'uni', true), bl_now(), false);
    end loop;
    perform bl_kids_notify_both(c, 'kids_uni_decide', '🎓 Send ' || v_nm || ' to university?', v_nm || ' passed WAEC with ' || (s.waec ->> 'text') || '. Choose a university, or let ' || v_nm || ' start working.');
    return c;
  end if;
  return bl_kids_finalize(c, p_at, 'grow');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. Hooks the life-moments engine calls (effects kid_school_pay, kid_school_ignore, kid_uni; the card must still be open)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_moment_open(p_ctx jsonb) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when p_ctx ? 'req_id' then exists (select 1 from kids_school_requests r where r.id = nullif(p_ctx ->> 'req_id', '')::bigint and r.status = 'open')
    when p_ctx ? 'uni' then exists (select 1 from kids_children k join kids_school s on s.child_id = k.id
                                     where k.id = nullif(p_ctx ->> 'child_id', '')::bigint and k.status = 'university' and s.uni_state = 'deciding')
    else exists (select 1 from kids_children k where k.id = nullif(p_ctx ->> 'child_id', '')::bigint and k.status = 'home' and k.sick_since is not null
                  and k.illness_n::text = coalesce(p_ctx ->> 'ep', k.illness_n::text))
  end
$$;

create or replace function public.bl_kids_school_req_pay(p_uid uuid, p_child bigint, p_ctx jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.kids_school_requests; c public.kids_children; v_who text; v_now timestamptz := bl_now();
begin
  select * into r from kids_school_requests x where x.id = nullif(p_ctx ->> 'req_id', '')::bigint for update;
  if not found or r.status <> 'open' then
    raise exception 'The school request was already handled.' using errcode = 'P0001', hint = 'already_answered';
  end if;
  select * into c from kids_children where id = r.child_id and (parent_a = p_uid or parent_b = p_uid);
  if not found then
    raise exception 'That child is not yours.' using errcode = 'P0001', hint = 'not_parent';
  end if;
  update kids_school_requests set status = 'paid', paid_by = p_uid where id = r.id;
  select username into v_who from profiles where id = p_uid;
  update player_moments set status = 'answered', handled_by = p_uid, outcome = 'Already handled by @' || coalesce(v_who, 'your partner') || ' 💛', answered_at = v_now
   where moment_id like 'school\_%' and user_id <> p_uid and status in ('pending', 'snoozed', 'scheduled') and context ->> 'req_id' = r.id::text;
  return to_jsonb('School request paid'::text);
end $$;

create or replace function public.bl_kids_school_req_ignore(p_uid uuid, p_child bigint, p_ctx jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.kids_school_requests; c public.kids_children; v_all boolean;
begin
  select * into r from kids_school_requests x where x.id = nullif(p_ctx ->> 'req_id', '')::bigint for update;
  if not found or r.status <> 'open' then return '[]'::jsonb; end if;
  select * into c from kids_children where id = r.child_id for update;
  if not found or (c.parent_a is distinct from p_uid and c.parent_b is distinct from p_uid) then return '[]'::jsonb; end if;
  if not (p_uid = any (r.ignores)) then update kids_school_requests set ignores = ignores || p_uid where id = r.id returning * into r; end if;
  v_all := (c.parent_a is null or c.parent_a = any (r.ignores)) and (c.parent_b is null or c.parent_b = any (r.ignores));
  if not v_all then return '[]'::jsonb; end if;
  update kids_school_requests set status = 'ignored' where id = r.id;
  update kids_school set penalty = penalty + bl_love_num('kids_school.ignore_penalty', 4) where child_id = c.id and seq = r.seq and attempt = r.attempt and class_start is not null;
  c := bl_kids_need_hit(c, 'fun', -bl_love_num('kids_school.ignore_fun_hit', 15));
  return to_jsonb(bl_kids_label(c) || ' is a bit sad and the grades may slip');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. The school as the app shows it (one block inside each child of kids_status)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_school_json(c public.kids_children, p_uid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s public.kids_school; sc public.kids_schools; cl public.kids_classes; v_now timestamptz := bl_now(); v_stage text; v_level text; v_state text; v_end timestamptz; v_cards int;
  v_fee jsonb := null; v_grades jsonb := '[]'::jsonb; v_last jsonb := null; v_hw jsonb := null; v_les jsonb := null; v_gear jsonb := '[]'::jsonb; v_hist jsonb; v_req jsonb := null;
  v_ratio numeric; v_hist_r numeric; v_now_r numeric; v_n int := 0; v_ok int := 0; n text; v_low numeric := bl_love_num('kids.alert_below', 30); j jsonb; v_att boolean; v_cd numeric; v_wait numeric;
  v_hours numeric; v_uni jsonb := null; v_lvl_name text; r record; ki public.kids_items; it public.items; v_cls text; v_prev jsonb; v_starts timestamptz; v_cls_stage text; v_cls_level text;
begin
  if not bl_kids_school_on() or c.status not in ('home', 'university', 'with_relatives') then return null; end if;
  select count(*) into v_cards from kids_report_cards x where x.child_id = c.id;
  v_stage := bl_kids_stage_of(c, v_now);
  select * into s from kids_school x where x.child_id = c.id;
  if not found then
    v_level := bl_kids_stage_level(v_stage);
    return jsonb_build_object('enabled', true, 'state', 'none', 'level', v_level, 'can_enrol', c.status = 'home' and v_level is not null,
                              'starts_at', case when v_level is null and c.born_at is not null then bl_kids_class_floor(c, 1) end, 'cards', v_cards,
                              'pass_mark', bl_love_num('kids_school.pass_mark', 50));
  end if;
  select * into sc from kids_schools x where x.id = s.school_id;
  select * into cl from kids_classes x where x.seq = s.seq;
  v_hours := case when s.uni_state is not null then bl_kids_uni_hours() else bl_kids_class_hours() end;
  v_state := case when s.uni_state = 'deciding' then 'deciding' when s.uni_state = 'studying' then 'university' when s.uni_state in ('graduated', 'dropped', 'working') then 'done'
                  when s.state = 'finished' then 'finished' when s.class_start is not null then 'learning'
                  when s.school_id is null or sc.id is null or not sc.active or not (cl.level = any (sc.levels)) then 'need_school' else 'waiting' end;
  v_cls_stage := coalesce(cl.stage_id, 'secondary'); v_cls_level := coalesce(cl.level, 'secondary');
  if v_state in ('learning', 'university') then
    v_end := s.class_start + make_interval(secs => (v_hours * 3600)::double precision);
    v_att := s.fee_paid_at is not null;
    -- forecast of this class's grades if it ended now (the stored share of fine time so far, held down by how the needs are right now)
    foreach n in array bl_kids_stage_needs(c, v_now) loop
      v_n := v_n + 1;
      if bl_kids_val(c, n, v_now) >= v_low then v_ok := v_ok + 1; end if;
    end loop;
    v_now_r := case when v_n > 0 then v_ok::numeric / v_n else 0.5 end;
    v_hist_r := case when c.care_total - s.total0 > 0 then bl_kids_school_ratio(c, s) end;
    v_ratio := case when v_hist_r is null then v_now_r else least(v_hist_r, v_now_r) end;
    j := bl_kids_school_calc(c.id, s, case when v_state = 'university' then 'university' else v_cls_level end, case when v_state = 'university' then 'university' else v_cls_stage end,
                             sc.quality, v_att, v_ratio);
    select r2.grades into v_prev from kids_school_results r2 where r2.child_id = c.id order by r2.id desc limit 1;
    select coalesce(jsonb_agg(jsonb_build_object('name', x ->> 'name', 'g', (x ->> 'g')::int,
             'last', (select (y ->> 'g')::int from jsonb_array_elements(coalesce(v_prev, '[]'::jsonb)) y where y ->> 'name' = x ->> 'name' limit 1))), '[]'::jsonb)
      into v_grades from jsonb_array_elements(j -> 'grades') x;
    v_fee := jsonb_build_object('amount', s.fee_amount, 'paid', v_att, 'paid_at', s.fee_paid_at, 'paid_by_me', s.fee_paid_by = p_uid,
                                'on_time', v_att and s.fee_paid_at <= s.class_start + make_interval(secs => (bl_love_num('kids_school.fee_grace_hours', 12) * 3600)::double precision),
                                'can_pay', c.status in ('home', 'university') and not v_att);
    v_les := jsonb_build_object('bought', s.lessons_at is not null, 'cost', bl_love_num('kids_school.lessons_cost', 8000)::bigint,
                                'can', c.status in ('home', 'university') and s.lessons_at is null);
    if v_state = 'learning' then
      v_cd := bl_love_num('kids_school.homework_cooldown_minutes', 60) * 60;
      v_wait := case when s.hw_last is null then 0 else greatest(0, ceil(extract(epoch from (s.hw_last + make_interval(secs => v_cd::double precision) - v_now)))) end;
      v_hw := jsonb_build_object('count', cardinality(s.hw_users), 'mine_done', p_uid = any (s.hw_users), 'wait', v_wait,
                                 'max', (c.parent_a is not null)::int + (c.parent_b is not null)::int, 'pts', bl_love_num('kids_school.homework_pts', 4),
                                 'can', c.status = 'home' and not (p_uid = any (s.hw_users)) and v_wait <= 0);
      select jsonb_build_object('type', q.req_type, 'status', q.status) into v_req from kids_school_requests q where q.child_id = c.id and q.seq = s.seq and q.attempt = s.attempt;
    end if;
  end if;
  if v_state in ('learning', 'waiting', 'need_school') and c.status = 'home' then
    for ki in select * from kids_items k where k.active and k.role in ('books', 'uniform') and (cardinality(k.stages) = 0 or v_cls_stage = any (k.stages)) order by k.sort loop
      continue when ki.role = 'books' and v_cls_level = 'nursery';
      select * into it from items x where x.id = ki.item_id;
      v_gear := v_gear || jsonb_build_object('kind', ki.role, 'item', ki.item_id, 'name', it.name, 'icon', it.icon,
        'have', bl_kids_left(p_uid, ki.item_id) > 0, 'applied', coalesce(case ki.role when 'books' then s.books_stage = v_cls_stage else s.uniform_stage = v_cls_stage end, false),
        'pts', case ki.role when 'books' then bl_love_num('kids_school.books_pts', 5) else bl_love_num('kids_school.uniform_pts', 3) end,
        'buy', case when bl_kids_left(p_uid, ki.item_id) > 0 then '[]'::jsonb else bl_kids_buy_info(ki.item_id) end);
    end loop;
  end if;
  select jsonb_build_object('class_name', x.class_name, 'avg', x.avg, 'promoted', x.promoted, 'attended', x.attended, 'attempt', x.attempt, 'level', x.level, 'at', x.created_at) into v_last
    from kids_school_results x where x.child_id = c.id order by x.id desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('class_name', h.class_name, 'avg', h.avg, 'promoted', h.promoted, 'attended', h.attended, 'attempt', h.attempt) order by h.id desc), '[]'::jsonb) into v_hist
    from (select * from kids_school_results where child_id = c.id order by id desc limit 8) h;
  if s.uni_state is not null then
    v_uni := jsonb_build_object('state', s.uni_state, 'level', s.uni_level, 'level_name', case when s.uni_level > 0 then (s.uni_level * 100) || 'L' end, 'course', s.uni_course,
                                'repeats', s.uni_repeats, 'max_repeats', bl_love_num('kids_school.uni_max_repeats', 2)::int, 'degree', s.uni_degree, 'avg', s.uni_avg,
                                'deadline', s.uni_deadline, 'ends_at', case when s.uni_state = 'studying' then v_end end);
  end if;
  return jsonb_build_object('enabled', true, 'state', v_state, 'level', v_cls_level, 'attempt', s.attempt, 'missed', s.missed, 'pass_mark', bl_love_num('kids_school.pass_mark', 50),
    'class', case when cl.seq is null then null else jsonb_build_object('seq', cl.seq, 'code', cl.code, 'name', cl.name, 'level', cl.level, 'stage', cl.stage_id) end,
    'school', case when sc.id is null then null else jsonb_build_object('id', sc.id, 'name', sc.name, 'icon', sc.icon, 'tier', sc.tier, 'quality', sc.quality, 'fee', sc.fee_per_class) end,
    'started_at', s.class_start, 'ends_at', v_end,
    'starts_at', case when v_state = 'waiting' then greatest(coalesce(s.ready_at, bl_kids_class_floor(c, s.seq)), bl_kids_class_floor(c, s.seq)) end,
    'fee', v_fee, 'grades', v_grades, 'avg_now', (select round(avg((x ->> 'g')::numeric)) from jsonb_array_elements(v_grades) x),
    'homework', v_hw, 'lessons', v_les, 'gear', v_gear, 'request', v_req, 'last', v_last, 'history', v_hist, 'waec', s.waec, 'uni', v_uni, 'cards', v_cards,
    'can_switch', c.status = 'home' and s.uni_state is null and s.state = 'learning' and s.fee_paid_at is null);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 11. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_school_guard(p_child bigint, p_statuses text[]) returns public.kids_children
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); c public.kids_children;
begin
  if not bl_kids_on() then
    raise exception 'Kids is resting for now.' using errcode = 'P0001', hint = 'off';
  end if;
  if not bl_kids_school_on() then
    raise exception 'School is on a short break.' using errcode = 'P0001', hint = 'school_off';
  end if;
  c := bl_kids_settle(p_child);
  if c.id is null or (c.parent_a is distinct from v_me.id and c.parent_b is distinct from v_me.id) then
    raise exception 'That child is not yours to look after.' using errcode = 'P0001', hint = 'not_parent';
  end if;
  if not (c.status = any (p_statuses)) then
    raise exception '% is not at school right now.', bl_kids_label(c) using errcode = 'P0001', hint = 'not_at_school';
  end if;
  return c;
end $$;

-- the schools a child can go to for the class they are on (or about to start)
create or replace function public.kids_school_schools(p_child bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.kids_children; s public.kids_school; v_level text; v_out jsonb;
begin
  c := bl_kids_school_guard(p_child, array['home']);
  select * into s from kids_school where child_id = c.id;
  if found then
    select level into v_level from kids_classes where seq = s.seq;
    if s.uni_state is not null or s.state <> 'learning' then v_level := null; end if;
  else
    v_level := bl_kids_stage_level(bl_kids_stage_of(c, null));
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'icon', x.icon, 'tier', x.tier, 'levels', to_jsonb(x.levels), 'area', case when char_length(coalesce(x.area, '')) <= 3 then upper(coalesce(x.area, '')) else initcap(replace(coalesce(x.area, ''), '_', ' ')) end,
           'fee', x.fee_per_class, 'quality', x.quality, 'blurb', x.blurb, 'current', x.id = s.school_id) order by x.fee_per_class, x.sort, x.id), '[]'::jsonb) into v_out
    from kids_schools x where x.active and v_level is not null and v_level = any (x.levels);
  return jsonb_build_object('level', v_level, 'schools', v_out);
end $$;

create or replace function public.kids_school_enrol(p_child bigint, p_school text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles := bl_me(); c public.kids_children; s public.kids_school; sc public.kids_schools; v_stage text; v_level text; v_seq int; cl public.kids_classes; v_nm text; v_other uuid; v_now timestamptz := bl_now();
begin
  c := bl_kids_school_guard(p_child, array['home']);
  v_nm := bl_kids_label(c);
  select * into sc from kids_schools x where x.id = p_school and x.active;
  if not found then
    raise exception 'That school is not taking children right now.' using errcode = 'P0001', hint = 'bad_school';
  end if;
  select * into s from kids_school x where x.child_id = c.id for update;
  if not found then
    v_stage := bl_kids_stage_of(c, v_now);
    v_level := bl_kids_stage_level(v_stage);
    if v_level is null then
      raise exception 'School starts at Nursery (day %). % is still too young.', (select from_days from kids_stages where id = 'nursery'), v_nm using errcode = 'P0001', hint = 'too_young';
    end if;
    v_seq := case v_level when 'nursery' then 1 when 'primary' then 3 else 9 end;
    select * into cl from kids_classes where seq = v_seq;
    if not (cl.level = any (sc.levels)) then
      raise exception '% does not teach %. Pick a school with %.', sc.name, cl.level, cl.level using errcode = 'P0001', hint = 'wrong_level';
    end if;
    insert into kids_school (child_id, school_id, seq, ready_at, req_done) values (c.id, sc.id, v_seq, v_now, true);
  else
    if s.uni_state is not null or s.state <> 'learning' then
      raise exception '% has finished school.', v_nm using errcode = 'P0001', hint = 'finished';
    end if;
    select * into cl from kids_classes where seq = s.seq;
    if not (cl.level = any (sc.levels)) then
      raise exception '% does not teach %. Pick a school with %.', sc.name, cl.level, cl.level using errcode = 'P0001', hint = 'wrong_level';
    end if;
    if s.school_id = sc.id then
      raise exception '% already goes to %.', v_nm, sc.name using errcode = 'P0001', hint = 'same_school';
    end if;
    if s.class_start is not null and s.fee_paid_at is not null then
      raise exception 'The fee for this class is paid. You can change school when the class ends.' using errcode = 'P0001', hint = 'class_running';
    end if;
    update kids_school set school_id = sc.id, fee_amount = case when class_start is not null then sc.fee_per_class else fee_amount end where child_id = c.id;
  end if;
  v_other := case when c.parent_a = v_me.id then c.parent_b else c.parent_a end;
  perform bl_kids_notify(v_other, 'kids_school_enrol', '🏫 ' || v_nm || ' goes to ' || sc.name, '@' || v_me.username || ' chose ' || sc.name || '. Fees are ' || bl_naira(sc.fee_per_class) || ' a class.', c.id);
  c := bl_kids_process(c.id, false);
  return jsonb_build_object('message', v_nm || ' goes to ' || sc.name || ' 🏫', 'school', sc.id);
end $$;

create or replace function public.kids_school_pay(p_child bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); c public.kids_children; s public.kids_school; v_nm text; v_cls text; v_other uuid;
begin
  c := bl_kids_school_guard(p_child, array['home', 'university']);
  v_nm := bl_kids_label(c);
  select * into s from kids_school where child_id = c.id for update;
  if not found or s.class_start is null then
    raise exception 'No class is running for % right now.', v_nm using errcode = 'P0001', hint = 'no_class';
  end if;
  if s.fee_paid_at is not null then
    raise exception 'The fee for this class is already paid.' using errcode = 'P0001', hint = 'already_paid';
  end if;
  v_cls := case when s.uni_state = 'studying' then (s.uni_level * 100) || 'L' else (select name from kids_classes where seq = s.seq) end;
  perform bl_sink_pay(v_me.id, s.fee_amount, 'kid_school_fee', jsonb_build_object('label', 'School fees: ' || v_nm || ', ' || v_cls, 'child', c.id));
  update kids_school set fee_paid_at = bl_now(), fee_paid_by = v_me.id where child_id = c.id;
  perform bl_kids_spent(c.id, v_me.id, s.fee_amount);
  v_other := case when c.parent_a = v_me.id then c.parent_b else c.parent_a end;
  perform bl_kids_notify(v_other, 'kids_school_paid', '✅ School fees paid for ' || v_nm, '@' || v_me.username || ' paid ' || bl_naira(s.fee_amount) || ' for ' || v_cls || '.', c.id);
  c := bl_kids_process(c.id, false);
  return jsonb_build_object('message', 'Fees paid for ' || v_cls || '. ' || v_nm || ' can go to class 🎒', 'spent', s.fee_amount, 'child', c.id);
end $$;

create or replace function public.kids_school_homework(p_child bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); c public.kids_children; s public.kids_school; v_nm text; v_cd numeric; v_wait numeric;
begin
  c := bl_kids_school_guard(p_child, array['home']);
  v_nm := bl_kids_label(c);
  select * into s from kids_school where child_id = c.id for update;
  if not found or s.class_start is null or s.uni_state is not null then
    raise exception 'There is no homework right now. Homework comes with a running class.' using errcode = 'P0001', hint = 'no_class';
  end if;
  if v_me.id = any (s.hw_users) then
    raise exception 'You already helped % with the homework in this class. Next class, again.', v_nm using errcode = 'P0001', hint = 'done';
  end if;
  v_cd := bl_love_num('kids_school.homework_cooldown_minutes', 60) * 60;
  v_wait := case when s.hw_last is null then 0 else extract(epoch from (s.hw_last + make_interval(secs => v_cd::double precision) - bl_now())) end;
  if v_wait > 0 then
    raise exception 'Easy. Somebody helped just now. You can help again in %.', bl_love_wait_text(v_wait) using errcode = 'P0001', hint = 'cooldown';
  end if;
  update kids_school set hw_users = hw_users || v_me.id, hw_last = bl_now() where child_id = c.id;
  return jsonb_build_object('message', 'You sat with ' || v_nm || ' and did the homework together 📚 The grades will thank you.', 'helps', cardinality(s.hw_users) + 1, 'child', c.id);
end $$;

create or replace function public.kids_school_lessons(p_child bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); c public.kids_children; s public.kids_school; v_nm text; v_cost bigint := bl_love_num('kids_school.lessons_cost', 8000)::bigint;
begin
  c := bl_kids_school_guard(p_child, array['home', 'university']);
  v_nm := bl_kids_label(c);
  select * into s from kids_school where child_id = c.id for update;
  if not found or s.class_start is null then
    raise exception 'No class is running for % right now.', v_nm using errcode = 'P0001', hint = 'no_class';
  end if;
  if s.lessons_at is not null then
    raise exception '% already has a tutor for this class.', v_nm using errcode = 'P0001', hint = 'done';
  end if;
  perform bl_sink_pay(v_me.id, v_cost, 'kid_school_lessons', jsonb_build_object('label', 'Extra lessons for ' || v_nm, 'child', c.id));
  update kids_school set lessons_at = bl_now() where child_id = c.id;
  perform bl_kids_spent(c.id, v_me.id, v_cost);
  return jsonb_build_object('message', v_nm || ' has a tutor for this class 🧑🏾‍🏫', 'spent', v_cost, 'child', c.id);
end $$;

-- give textbooks or the school bag and uniform (from the bag: buy them at Oba Market or the supermarket first)
create or replace function public.kids_school_gear(p_child bigint, p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me(); c public.kids_children; s public.kids_school; cl public.kids_classes; v_nm text; ki public.kids_items; it public.items;
begin
  if p_kind not in ('books', 'uniform') then
    raise exception 'Pick books or uniform.' using errcode = 'P0001', hint = 'bad_kind';
  end if;
  c := bl_kids_school_guard(p_child, array['home']);
  v_nm := bl_kids_label(c);
  select * into s from kids_school where child_id = c.id for update;
  if not found or s.uni_state is not null or s.state <> 'learning' then
    raise exception '% is not in school.', v_nm using errcode = 'P0001', hint = 'not_at_school';
  end if;
  select * into cl from kids_classes where seq = s.seq;
  if p_kind = 'books' and cl.level = 'nursery' then
    raise exception 'Nursery children do not need textbooks. A school bag and uniform will do.' using errcode = 'P0001', hint = 'na';
  end if;
  if (p_kind = 'books' and s.books_stage = cl.stage_id) or (p_kind = 'uniform' and s.uniform_stage = cl.stage_id) then
    raise exception '% already has this for %.', v_nm, cl.level using errcode = 'P0001', hint = 'done';
  end if;
  select * into ki from kids_items k where k.active and k.role = p_kind and (cardinality(k.stages) = 0 or cl.stage_id = any (k.stages)) order by k.sort limit 1;
  if not found then
    raise exception 'There is nothing to give for this class.' using errcode = 'P0001', hint = 'na';
  end if;
  select * into it from items where id = ki.item_id;
  if bl_kids_left(v_me.id, ki.item_id) < 1 then
    raise exception 'You do not have %. Buy it at Oba Market or the supermarket first.', lower(it.name) using errcode = 'P0001', hint = 'no_item';
  end if;
  perform bl_kids_use(v_me.id, ki.item_id);
  perform bl_kids_spent(c.id, v_me.id, it.price);
  if p_kind = 'books' then update kids_school set books_stage = cl.stage_id where child_id = c.id;
  else update kids_school set uniform_stage = cl.stage_id where child_id = c.id; end if;
  return jsonb_build_object('message', case p_kind when 'books' then v_nm || ' has the ' || cl.level || ' textbooks 📚' else v_nm || ' looks sharp in the new bag and uniform 🎒' end, 'child', c.id);
end $$;

create or replace function public.kids_report_cards(p_child bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c public.kids_children; v_out jsonb;
begin
  select * into c from kids_children where id = p_child and (parent_a = v_uid or parent_b = v_uid);
  if not found then
    raise exception 'That child is not yours.' using errcode = 'P0001', hint = 'not_parent';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'stage', x.stage_key, 'title', x.title, 'school', x.school_name, 'grades', x.grades, 'avg', x.avg, 'position', x.position,
           'remark', x.remark, 'teacher', x.teacher, 'promoted', x.promoted, 'extra', x.extra, 'at', x.created_at) order by x.id desc), '[]'::jsonb) into v_out
    from (select * from kids_report_cards where child_id = c.id order by id desc limit 10) x;
  return jsonb_build_object('child', jsonb_build_object('id', c.id, 'name', c.name, 'gender', c.gender), 'cards', v_out);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 12. Proud parent tier, admin overview
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_kids_proud_tier(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select case when bl_kids_on() and exists (select 1 from profiles p where p.id = p_uid and p.show_relationship)
    then (select k.tier from (select tier from kids_children where parent_a = p_uid and status = 'grown' and tier in ('graduate', 'gold', 'silver', 'bronze')
                              union all select tier from kids_children where parent_b = p_uid and status = 'grown' and tier in ('graduate', 'gold', 'silver', 'bronze')) k
           order by case k.tier when 'graduate' then 0 when 'gold' then 1 when 'silver' then 2 else 3 end limit 1) end
$$;

-- ---------------------------------------------------------------------------------------------
-- 13. Patches on live functions (guarded, written against the CURRENT definitions)
-- ---------------------------------------------------------------------------------------------
create or replace function pg_temp.ks_patch_all(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  if position(p_old in v_def) = 0 then raise exception 'kids_school: % : marker not found: %', p_sig, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- life moments engine: the new effects, the new card kinds, the fee placeholder
select pg_temp.ks_patch('public.bl_moment_check_effect(jsonb)',
  $o$when 'kid_cure', 'kid_ignore' then
      null;$o$,
  $o$when 'kid_cure', 'kid_ignore', 'kid_school_pay', 'kid_school_ignore' then
      null;
    when 'kid_uni' then
      if (e ->> 'school') is null or (e ->> 'school') !~ '^[a-z][a-z0-9_]{1,40}$' then perform bl_moment_bad('kid_uni needs a "school" (a university id, or work)'); end if;$o$,
  $o$'kid_school_pay'$o$);
select pg_temp.ks_patch('public.bl_moment_apply(uuid, player_moments, jsonb, text)',
  $o$elsif t = 'item' then$o$,
  $o$elsif t = 'kid_school_pay' then
      if v_cid is not null then v_out := v_out || coalesce(bl_kids_school_req_pay(p_uid, v_cid, pm.context), '[]'::jsonb); end if;
    elsif t = 'kid_school_ignore' then
      if v_cid is not null then v_out := v_out || coalesce(bl_kids_school_req_ignore(p_uid, v_cid, pm.context), '[]'::jsonb); end if;
    elsif t = 'kid_uni' then
      if v_cid is not null then v_out := v_out || coalesce(bl_kids_uni_choose(p_uid, v_cid, e ->> 'school'), '[]'::jsonb); end if;
    elsif t = 'item' then$o$,
  $o$bl_kids_school_req_pay$o$);
select pg_temp.ks_patch('public.moments_answer(bigint, text)',
  $o$if m.kind = 'kids_ill' and not bl_kids_moment_open(pm.context) then$o$,
  $o$if m.kind in ('kids_ill', 'kids_school', 'kids_uni') and not bl_kids_moment_open(pm.context) then$o$,
  $o$m.kind in ('kids_ill', 'kids_school', 'kids_uni')$o$);
select pg_temp.ks_patch('public.moments_answer(bigint, text)',
  $o$update player_moments set status = 'expired', outcome = 'Already feeling better 💛', answered_at$o$,
  $o$update player_moments set status = 'expired', outcome = case when m.kind = 'kids_ill' then 'Already feeling better 💛' else 'Already handled 💛' end, answered_at$o$,
  $o$else 'Already handled 💛' end, answered_at$o$);
select pg_temp.ks_patch('public.moments_answer(bigint, text)',
  $o$return jsonb_build_object('outcome', 'Already feeling better 💛', 'tone', 'info'$o$,
  $o$return jsonb_build_object('outcome', case when m.kind = 'kids_ill' then 'Already feeling better 💛' else 'Already handled 💛' end, 'tone', 'info'$o$,
  $o$else 'Already handled 💛' end, 'tone', 'info'$o$);
select pg_temp.ks_patch('public.moments_answer(bigint, text)',
  $o$if m.kind = 'kids_ill' then perform bl_kids_moment_paid(v_uid, pm.context, v_cost); end if;$o$,
  $o$if m.kind in ('kids_ill', 'kids_school') then perform bl_kids_moment_paid(v_uid, pm.context, v_cost); end if;$o$,
  $o$m.kind in ('kids_ill', 'kids_school') then perform$o$);
select pg_temp.ks_patch('public.moments_pending()',
  $o$order by (select (l.kind = 'kids_ill') from life_moments l where l.id = x.moment_id) desc, x.show_at, x.id limit v_max$o$,
  $o$order by (select (l.kind in ('kids_ill', 'kids_school', 'kids_uni')) from life_moments l where l.id = x.moment_id) desc, x.show_at, x.id limit v_max$o$,
  $o$'kids_school', 'kids_uni')) from life_moments l$o$);
select pg_temp.ks_patch('public.bl_moment_text(text, uuid, jsonb)',
  E'return replace(replace(replace(p_text, ''{name}'', coalesce(v_name, ''you'')), ''{child}'', coalesce(v_child, ''your child'')),\n                 ''{partner}'', coalesce(v_partner, ''your partner''));',
  E'return bl_kids_fee_text(replace(replace(replace(p_text, ''{name}'', coalesce(v_name, ''you'')), ''{child}'', coalesce(v_child, ''your child'')),\n                 ''{partner}'', coalesce(v_partner, ''your partner'')));',
  $o$bl_kids_fee_text(replace$o$);

-- kids: university status, the school clock
select pg_temp.ks_patch('public.bl_kids_due(kids_children)',
  $o$elsif c.status = 'with_relatives' then$o$,
  $o$return query select 'school'::text, x.at from bl_kids_school_next(c) x order by x.at limit 1;
  elsif c.status = 'university' then
    return query select 'school'::text, x.at from bl_kids_school_next(c) x order by x.at limit 1;
  elsif c.status = 'with_relatives' then$o$,
  $o$bl_kids_school_next(c)$o$);
select pg_temp.ks_patch('public.bl_kids_next(kids_children)',
  $o$if c.status not in ('home', 'with_relatives') then return null; end if;$o$,
  $o$if c.status not in ('home', 'with_relatives', 'university') then return null; end if;$o$,
  $o$'with_relatives', 'university') then return null$o$);
select pg_temp.ks_patch('public.bl_kids_settle(bigint)',
  $o$elsif c.status not in ('home', 'with_relatives') then$o$,
  $o$elsif c.status not in ('home', 'with_relatives', 'university') then$o$,
  $o$'with_relatives', 'university') then$o$);
select pg_temp.ks_patch('public.bl_kids_settle(bigint)',
  $o$elsif v_kind = 'pass' then$o$,
  $o$elsif v_kind = 'school' then
      c := bl_kids_school_tick(c, v_now);
    elsif v_kind = 'pass' then$o$,
  $o$bl_kids_school_tick(c, v_now)$o$);
select pg_temp.ks_patch('public.bl_kids_val(kids_children, text, timestamp with time zone)',
  $o$if c.status not in ('home', 'with_relatives') or t0 is null then return v; end if;$o$,
  $o$if c.status not in ('home', 'with_relatives', 'university') or t0 is null then return v; end if;$o$,
  $o$'with_relatives', 'university') or t0 is null$o$);
select pg_temp.ks_patch('public.bl_kids_score_tick(kids_children, timestamp with time zone)',
  $o$if c.status <> 'home' or v_a is null or p_at <= v_a then return c; end if;$o$,
  $o$if c.status not in ('home', 'university') or v_a is null or p_at <= v_a then return c; end if;$o$,
  $o$not in ('home', 'university') or v_a is null$o$);
select pg_temp.ks_patch('public.bl_kids_can(kids_children, text, timestamp with time zone, uuid)',
  $o$if c.status <> 'home' then$o$,
  $o$if c.status not in ('home', 'university') then$o$,
  $o$c.status not in ('home', 'university')$o$);
select pg_temp.ks_patch('public.bl_kids_can(kids_children, text, timestamp with time zone, uuid)',
  $o$s := bl_kids_stage_row(c, v_now);$o$,
  $o$s := bl_kids_stage_row(c, v_now);
  if c.status = 'university' and p_action not in ('feed', 'cuddle') then
    return jsonb_build_object('ok', false, 'code', 'na', 'wait', 0, 'cost', 0, 'msg', '');
  end if;$o$,
  $o$c.status = 'university' and p_action not in$o$);
select pg_temp.ks_patch('public.bl_kids_can(kids_children, text, timestamp with time zone, uuid)',
  $o$v_cost := bl_love_num('kids.feed_cost', 1500)::bigint;$o$,
  $o$v_cost := case when c.status = 'university' then bl_love_num('kids_school.uni_pocket_cost', 6000)::bigint else bl_love_num('kids.feed_cost', 1500)::bigint end;$o$,
  $o$kids_school.uni_pocket_cost$o$);
select pg_temp.ks_patch('public.bl_kids_child_json(kids_children, uuid)',
  $o$if c.status in ('home', 'with_relatives') and s.id is not null then$o$,
  $o$if c.status in ('home', 'with_relatives', 'university') and s.id is not null then$o$,
  $o$'with_relatives', 'university') and s.id$o$);
select pg_temp.ks_patch('public.bl_kids_child_json(kids_children, uuid)',
  E'if c.status = ''home'' then\n    v_needy := bl_kids_needy(c, v_now);',
  E'if c.status in (''home'', ''university'') then\n    v_needy := bl_kids_needy(c, v_now);',
  $o$if c.status in ('home', 'university') then$o$);
select pg_temp.ks_patch('public.bl_kids_child_json(kids_children, uuid)',
  $o$'log', v_log, 'relatives', v_rel);$o$,
  $o$'log', v_log, 'relatives', v_rel, 'school', bl_kids_school_json(c, p_uid), 'outcome', c.outcome);$o$,
  $o$bl_kids_school_json(c, p_uid)$o$);
select pg_temp.ks_patch_all('public.kids_status()',
  $o$k.status in ('expecting', 'home', 'with_relatives')$o$,
  $o$k.status in ('expecting', 'home', 'with_relatives', 'university')$o$,
  $o$'with_relatives', 'university')$o$);
select pg_temp.ks_patch('public.kids_status()',
  $o$'tier', g.tier, 'score', g.care_score,$o$,
  $o$'tier', g.tier, 'score', g.care_score, 'outcome', g.outcome, 'cards', (select count(*) from kids_report_cards x where x.child_id = g.id),$o$,
  $o$'outcome', g.outcome$o$);
select pg_temp.ks_patch_all('public.bl_kids_parent_left()',
  $o$k.status in ('expecting', 'home', 'with_relatives')$o$,
  $o$k.status in ('expecting', 'home', 'with_relatives', 'university')$o$,
  $o$'with_relatives', 'university')$o$);
select pg_temp.ks_patch('public.bl_kids_switch()',
  $o$update kids_pause set paused_at = null where id = 1;$o$,
  $o$update kids_school set ready_at = ready_at + v_d, class_start = class_start + v_d, fee_paid_at = fee_paid_at + v_d, req_at = req_at + v_d, hw_last = hw_last + v_d,
         lessons_at = lessons_at + v_d, uni_deadline = uni_deadline + v_d
   where child_id in (select id from kids_children where status in ('home', 'university', 'with_relatives'));
  update kids_pause set paused_at = null where id = 1;$o$,
  $o$update kids_school set ready_at$o$);
select pg_temp.ks_patch_all('public.bl_kids_switch()',
  $o$where status in ('expecting', 'home', 'with_relatives');$o$,
  $o$where status in ('expecting', 'home', 'with_relatives', 'university');$o$,
  $o$'with_relatives', 'university');$o$);
select pg_temp.ks_patch('public.admin_kids_overview()',
  $o$'passed', (select count(*) from kids_children where status = 'passed'),$o$,
  $o$'passed', (select count(*) from kids_children where status = 'passed'),
    'university', (select count(*) from kids_children where status = 'university'),
    'at_school', (select count(*) from kids_school s join kids_children k on k.id = s.child_id where k.status = 'home' and s.uni_state is null and s.state = 'learning' and s.school_id is not null),
    'waec_passed', (select count(*) from kids_school where coalesce((waec ->> 'pass')::boolean, false)),
    'graduated', (select count(*) from kids_school where uni_state = 'graduated'),
    'dropped_uni', (select count(*) from kids_school where uni_state = 'dropped'),
    'school_enabled', coalesce(bl_cfg_bool('kids_school.enabled'), true),$o$,
  $o$'at_school'$o$);
select pg_temp.ks_patch_all('public.admin_kids_overview()',
  $o$where status in ('expecting', 'home', 'with_relatives') order by id desc limit 50$o$,
  $o$where status in ('expecting', 'home', 'with_relatives', 'university') order by id desc limit 50$o$,
  $o$'with_relatives', 'university') order by id desc$o$);

select pg_temp.ks_patch_all('public.admin_kids_remove(bigint, text)',
  $o$status in ('expecting', 'home', 'with_relatives') for update$o$,
  $o$status in ('expecting', 'home', 'with_relatives', 'university') for update$o$,
  $o$'with_relatives', 'university') for update$o$);

-- ledger: school fees and lessons are sinks (labelled, their own category, never earnings)
select pg_temp.ks_patch('public.bl_ledger_label(text, jsonb)',
  $o$when 'kid_reclaim_refund' then return coalesce(nullif(p_meta->>'label', ''), 'Share returned');$o$,
  $o$when 'kid_reclaim_refund' then return coalesce(nullif(p_meta->>'label', ''), 'Share returned');
    when 'kid_school_fee' then return coalesce(nullif(p_meta->>'label', ''), 'School fees');
    when 'kid_school_lessons' then return coalesce(nullif(p_meta->>'label', ''), 'Extra lessons');$o$,
  $o$when 'kid_school_fee' then$o$);
select pg_temp.ks_patch('public.bl_econ_category(text)',
  $o$when p_reason in ('life_moment') then 'Life moments'$o$,
  $o$when p_reason in ('kid_school_fee', 'kid_school_lessons') then 'School fees'
    when p_reason in ('life_moment') then 'Life moments'$o$,
  $o$then 'School fees'$o$);
select pg_temp.ks_patch('public.bl_earn_reasons()',
  $o$'life_moment', 'kid_gift', 'kid_reclaim_refund'])$o$,
  $o$'life_moment', 'kid_gift', 'kid_reclaim_refund', 'kid_school_fee', 'kid_school_lessons'])$o$,
  $o$'kid_school_fee', 'kid_school_lessons'$o$);

-- Admin Content editors: schools and school subjects
select pg_temp.ks_patch('public.bl_admin_table_spec(text)',
  $o$when 'kids_auto_names' then$o$,
  E'when ''kids_schools'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","icon":"text","tier":"text","levels":"arr","area":"text_null","fee_per_class":"int","quality":"num","blurb":"text","sort":"int","active":"bool"}}\'\n    when ''kids_subjects'' then ''{"pk":["id"],"insert":true,"order":"level, sort, id",\n      "cols":{"level":"text","name":"text","parent":"text_null","sort":"int","active":"bool"}}\'\n    when ''kids_auto_names'' then',
  $o$when 'kids_schools' then$o$);

-- ---------------------------------------------------------------------------------------------
-- 14. School cards for the life-moments engine (fictional school, bursar and amounts; edit them in Content -> Life moments)
-- ---------------------------------------------------------------------------------------------
create or replace function pg_temp.school_card(p_id text, p_title text, p_body text, p_icon text, p_cost bigint, p_pay_out text, p_ign_out text, p_fun int, p_sort int) returns void
language plpgsql as $$
declare v_eff jsonb := jsonb_build_array(jsonb_build_object('t', 'kid_school_pay')); v_choices jsonb;
begin
  if p_fun > 0 then v_eff := v_eff || jsonb_build_array(jsonb_build_object('t', 'kid_need', 'need', 'fun', 'delta', p_fun)); end if;
  v_choices := jsonb_build_array(
    jsonb_build_object('id', 'pay', 'label', 'Pay', 'cost', p_cost, 'effects', v_eff, 'outcome', p_pay_out),
    jsonb_build_object('id', 'ignore', 'label', 'Ignore', 'ignore', true, 'effects', jsonb_build_array(jsonb_build_object('t', 'kid_school_ignore')), 'outcome', p_ign_out));
  insert into life_moments (id, title, body, icon, speaker, kind, conditions, choices, cooldown_days, weight, push, sort)
  values (p_id, p_title, p_body, p_icon, 'School bursar · The school office', 'kids_school', '{}'::jsonb, v_choices, 0, 0, false, p_sort)
  on conflict (id) do nothing;
end $$;

select pg_temp.school_card('school_pta', '{child}: PTA levy',
  'The PTA chairman announced this term''s levy for {child}''s class. The school needs it for repairs, chalk and the compound. The bursar asks parents to pay at the office.',
  '🏫', 6000, 'You paid the PTA levy. The class teacher sends her thanks.', 'You let the levy pass. {child} was a little shy in class today.', 0, 400);
select pg_temp.school_card('school_excursion', '{child}: class excursion',
  'The class is going on an excursion to the Benin City museum and the moat. Each child pays for the bus and lunch. {child} is hoping to go.',
  '🚌', 9000, '{child} is on the bus with a lunch pack, singing all the way.', '{child} watched the others board the bus and went quiet.', 20, 410);
select pg_temp.school_card('school_sports', '{child}: sports wear',
  'Inter-house sports is coming. {child} needs a new sports kit and white canvas shoes. The games master wants everything by Friday.',
  '🏃', 7500, '{child} runs onto the field in a bright new kit, proud as a peacock.', '{child} borrowed an old kit and did not feel part of the team.', 15, 420);
select pg_temp.school_card('school_party', '{child}: end-of-term party',
  'The class is having its end-of-term party with jollof rice, small chops and music. Every parent contributes a little for the food.',
  '🎉', 4000, '{child} danced and ate jollof rice until the very last song.', '{child} heard about the party the next day.', 25, 430);
select pg_temp.school_card('school_waec', '{child}: WAEC registration',
  'It is the final year. {child} must be registered for WAEC now and the exam body wants the registration fee before the deadline. Late registration brings stress and mistakes.',
  '📝', 25000, '{child} is registered for WAEC. The exam card is in the bag.', '{child} was registered late and the stress shows. The WAEC papers will be harder.', 0, 440);

insert into life_moments (id, title, body, icon, speaker, kind, conditions, choices, cooldown_days, weight, push, sort) values
('uni_decision', 'Send {child} to university?',
 '{child} passed WAEC with good results. A degree opens many doors. UNIBEN is the cheaper, public choice. Edo Royal University is private, dearer and has the better name. Fees are paid every level, four levels in all. Or {child} can start working now.',
 '🎓', 'Family · Graduation', 'kids_uni', '{}'::jsonb,
 jsonb_build_array(
   jsonb_build_object('id', 'uniben', 'label', 'UNIBEN · {fee:uniben}', 'effects', jsonb_build_array(jsonb_build_object('t', 'kid_uni', 'school', 'uniben')),
     'outcome', '{child} is going to UNIBEN. Pack the bags, 100 level starts now.'),
   jsonb_build_object('id', 'edo_royal', 'label', 'Edo Royal · {fee:edo_royal_university}', 'effects', jsonb_build_array(jsonb_build_object('t', 'kid_uni', 'school', 'edo_royal_university')),
     'outcome', '{child} is going to Edo Royal University. A big step for the family.'),
   jsonb_build_object('id', 'work', 'label', 'Let them start working', 'ignore', true, 'effects', jsonb_build_array(jsonb_build_object('t', 'kid_uni', 'school', 'work')),
     'outcome', '{child} starts working and moves out with your blessing.')),
 0, 0, false, 450)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 15. Grants: bl_* helpers are private; the player and admin RPCs are for signed-in users only
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'bl\_kids\_%' or proname = 'bl_shop_price') loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  grant execute on function public.bl_kids_alert_sweep() to service_role;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and (proname like 'kids\_%' or proname like 'admin\_kids\_%') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
end $$;
notify pgrst, 'reload schema';
