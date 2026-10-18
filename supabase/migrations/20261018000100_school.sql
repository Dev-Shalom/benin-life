-- R4 School and certificates (docs/SCHOOL.md, docs/REVIEW_PLAN.md step R4).
-- * `courses` (admin table): UNIBEN short courses, a driving school, a mechanic trade test, a coding bootcamp and a longer UNIBEN BSc with
--   modules. Each has a place (location ids and/or scenes), a fee, a number of classes, class length (in-game minutes + real seconds),
--   a cooldown in game days between classes, an energy cost, XP per class to a skill, a prerequisite (certificate and/or skill level),
--   an optional exam on the final class (pass chance rises with the skill level, a fail means retake that class) and the certificate it awards.
-- * `certificates` (admin table): name, icon, permanent pay bonus % on related careers/hustles. `player_certificates` holds who has what
--   (course graduation or an audited admin grant).
-- * A class runs like a hustle: course_start_class() at the course's place (busy timer, cannot be stopped), course_finish_class() rolls the
--   exam, XP goes through bl_skill_award(uid, 'course', id), progress never resets when days are missed.
-- * Gates: career_levels.req_cert, career_tracks.req_cert, hustles.req_cert, yahoo_jobs.req_cert (nullable; a comma means "any of").
--   Defaults keep today's content open: only four career levels and two NEW hustle variants (Headline DJ slot, Fleet service contract) are gated.
-- * The certificate in school.degree_cert (default 'bsc') counts as a UNIBEN degree for the existing "degree" career requirement.
-- * Live functions are patched with guarded replacements (raise when a marker is missing, skip when already applied), so grants stay.
-- Idempotent and safe on a non-empty DB: tables "if not exists", seeds "on conflict do nothing", columns "if not exists".

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('school.enabled', 'true', 'school', 'School on',
 'R4: courses, classes and certificates. Off = no classes, and certificate gates and pay bonuses stop applying (everything stays open).', 'bool', null, null),
('school.fee_mult', '1', 'school', 'Course fee multiplier',
 'R4: every course fee is multiplied by this (0.5 = half-price term, 0 = free school).', 'number', 0, 100),
('school.cooldown_mult', '1', 'school', 'Class cooldown multiplier',
 'R4: every course''s "game days between classes" is multiplied by this (rounded up). 0 = no wait between classes (testing, events).', 'number', 0, 100),
('school.exam_min_pct', '5', 'school', 'Exam pass chance, lowest %',
 'R4: an exam is never harder than this (before the skill level helps).', 'number', 0, 100),
('school.exam_cap_pct', '95', 'school', 'Exam pass chance, highest %',
 'R4: an exam is never easier than this (even at max skill level).', 'number', 0, 100),
('school.degree_cert', '"bsc"', 'school', 'Certificate that counts as a degree',
 'R4: the certificate id (Content -> Certificates) that counts as a UNIBEN degree for career levels that need "a UNIBEN degree" (Senior Dev, nurse and doctor levels). Empty = none.', 'text', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.certificates (
  id            text primary key,
  name          text not null,
  icon          text not null default '🎓',
  blurb         text not null default '',
  -- permanent pay bonus (%) on the careers (track ids) and hustles (hustle ids) listed below
  pay_bonus_pct numeric not null default 0 check (pay_bonus_pct >= 0 and pay_bonus_pct <= 500),
  bonus_tracks  text[] not null default '{}',
  bonus_hustles text[] not null default '{}',
  sort          int not null default 0,
  active        boolean not null default true
);

create table if not exists public.courses (
  id                 text primary key,
  name               text not null,
  icon               text not null default '🎓',
  blurb              text not null default '',
  where_text         text not null default '',
  location_ids       text[] not null default '{}',
  scenes             text[] not null default '{}',
  fee                bigint not null default 0 check (fee >= 0),
  classes            int not null default 4 check (classes >= 1 and classes <= 200),
  class_game_minutes int not null default 120 check (class_game_minutes >= 0 and class_game_minutes <= 1440),
  class_seconds      int not null default 30 check (class_seconds >= 1 and class_seconds <= 3600),
  -- game days between one class and the next (1 = one class per game day, 0 = none)
  cooldown_days      int not null default 1 check (cooldown_days >= 0 and cooldown_days <= 365),
  energy_cost        int not null default 12 check (energy_cost >= 0 and energy_cost <= 100),
  effects            jsonb not null default '{}'::jsonb,
  hour_from          numeric check (hour_from is null or (hour_from >= 0 and hour_from < 24)),
  hour_to            numeric check (hour_to is null or (hour_to >= 0 and hour_to <= 24)),
  skill_id           text references public.skills (id) on update cascade on delete set null,
  xp_per_class       numeric not null default 6 check (xp_per_class >= 0 and xp_per_class <= 100000),
  -- prerequisite: a certificate (comma = any of) and/or a minimum level in a skill
  prereq_cert        text,
  prereq_skill       text references public.skills (id) on update cascade on delete set null,
  prereq_skill_level int not null default 1 check (prereq_skill_level >= 1 and prereq_skill_level <= 50),
  cert_id            text references public.certificates (id) on update cascade on delete set null,
  exam               boolean not null default false,
  exam_base_pct      numeric not null default 50 check (exam_base_pct >= 0 and exam_base_pct <= 100),
  exam_per_level_pct numeric not null default 8 check (exam_per_level_pct >= 0 and exam_per_level_pct <= 100),
  exam_text          text not null default '',
  modules            text[] not null default '{}',
  sort               int not null default 0,
  active             boolean not null default true
);

create table if not exists public.player_certificates (
  user_id   uuid not null references public.profiles (id) on delete cascade,
  cert_id   text not null references public.certificates (id) on update cascade on delete cascade,
  earned_at timestamptz not null default now(),
  source    text not null default 'course' check (source in ('course', 'admin')),
  course_id text,
  primary key (user_id, cert_id)
);

create table if not exists public.course_enrolments (
  user_id        uuid not null references public.profiles (id) on delete cascade,
  course_id      text not null references public.courses (id) on update cascade on delete cascade,
  status         text not null default 'enrolled' check (status in ('enrolled', 'completed')),
  classes_done   int not null default 0 check (classes_done >= 0),
  fee_paid       bigint not null default 0,
  enrolled_at    timestamptz not null default now(),
  completed_at   timestamptz,
  last_class_day bigint,
  last_class_at  timestamptz,
  exam_fails     int not null default 0,
  updated_at     timestamptz not null default now(),
  primary key (user_id, course_id)
);

create table if not exists public.course_runs (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  course_id   text not null references public.courses (id) on update cascade on delete cascade,
  class_no    int not null,
  location_id text,
  started_at  timestamptz not null default now(),
  resolve_at  timestamptz not null,
  resolved_at timestamptz,
  status      text not null default 'running' check (status in ('running', 'done')),
  outcome     text check (outcome in ('ok', 'pass', 'fail')),
  xp          int not null default 0,
  detail      jsonb not null default '{}'::jsonb
);
create index if not exists course_runs_user_idx on public.course_runs (user_id, id desc);
create index if not exists course_runs_running_idx on public.course_runs (user_id) where status = 'running';

alter table public.career_levels add column if not exists req_cert text;
alter table public.career_tracks add column if not exists req_cert text;
alter table public.hustles add column if not exists req_cert text;
alter table public.yahoo_jobs add column if not exists req_cert text;

alter table public.certificates enable row level security;
alter table public.courses enable row level security;
alter table public.player_certificates enable row level security;
alter table public.course_enrolments enable row level security;
alter table public.course_runs enable row level security;
revoke all on table public.certificates, public.courses, public.player_certificates, public.course_enrolments, public.course_runs
  from public, anon, authenticated;
grant select on table public.certificates, public.courses, public.player_certificates, public.course_enrolments, public.course_runs to authenticated;
drop policy if exists certificates_read on public.certificates;
create policy certificates_read on public.certificates for select to authenticated using (true);
drop policy if exists courses_read on public.courses;
create policy courses_read on public.courses for select to authenticated using (true);
drop policy if exists player_certificates_own on public.player_certificates;
create policy player_certificates_own on public.player_certificates for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists course_enrolments_own on public.course_enrolments;
create policy course_enrolments_own on public.course_enrolments for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists course_runs_own on public.course_runs;
create policy course_runs_own on public.course_runs for select to authenticated using (user_id = (select auth.uid()));

-- zone cards for classes ("kind = class", ref = course id)
alter table public.zone_actions drop constraint if exists zone_actions_kind_check;
alter table public.zone_actions add constraint zone_actions_kind_check
  check (kind = any (array['activity', 'job', 'shop', 'panel', 'shrine', 'linkup', 'hustle', 'class']));

-- ---------------------------------------------------------------------------------------------
-- 3. Seeds: certificates, courses
-- ---------------------------------------------------------------------------------------------
insert into public.certificates (id, name, icon, blurb, pay_bonus_pct, bonus_tracks, bonus_hustles, sort) values
('ict', 'ICT', '🖥️', 'Computer basics: typing, Office, email, how the internet really works. Tech employers ask for am.', 5, '{tech}', '{}', 10),
('digital_marketing', 'Digital Marketing', '📣', 'Social ads, WhatsApp status and how to make people see your thing. Food sellers sell more.', 5, '{}', '{vend_jollof,vend_puff,vend_fried_yam,pos_agent}', 20),
('accounting', 'Accounting', '🧾', 'Books, ledgers and reconciliation. Banks and big agents want somebody who can count.', 8, '{pos,trade}', '{}', 30),
('catering', 'Catering & Hospitality', '🍽️', 'Pro kitchen, hygiene and service. Your food stall pays better.', 10, '{}', '{vend_jollof,vend_puff,vend_fried_yam}', 40),
('driving', 'Driving Licence', '🪪', 'Proper driver''s licence from the driving school. Park bosses and Bolt riders trust you.', 8, '{transport}', '{bolt_shift}', 50),
('music_production', 'Music Production', '🎚️', 'Mixing, mastering and reading a crowd. The big clubs book you for the main room.', 10, '{}', '{dj_set,dj_headline,mc_gig}', 60),
('mechanic_trade', 'Mechanic Trade Test', '🔩', 'Government trade test for auto mechanics. Fleet owners only hire certified hands.', 10, '{}', '{mech_quick,mech_engine,mech_fleet}', 70),
('business_mgmt', 'Business Management', '📊', 'Margins, staff, stock and strategy. Wholesalers and market leaders need this.', 5, '{trade,pos}', '{pos_agent}', 80),
('coding_bootcamp', 'Coding Bootcamp', '👨‍💻', 'Eight weeks of real projects at the Tech Hub. Senior roles open up.', 8, '{tech}', '{}', 90),
('bsc', 'BSc Degree', '🎓', 'A full UNIBEN degree. Counts as your degree for the careers that ask for one.', 5, '{education,health,tech}', '{}', 100)
on conflict (id) do nothing;

insert into public.courses (id, name, icon, blurb, where_text, location_ids, scenes, fee, classes, class_game_minutes, class_seconds, cooldown_days,
  energy_cost, effects, hour_from, hour_to, skill_id, xp_per_class, prereq_cert, prereq_skill, prereq_skill_level, cert_id, exam, exam_base_pct,
  exam_per_level_pct, exam_text, modules, sort) values
('ict_basics', 'Computer Basics / ICT', '🖥️', 'Typing, Word, Excel, email and the internet. The first step to a tech career.',
 'UNIBEN Ugbowo Campus (lecture hall)', '{uniben}', '{}', 12000, 4, 120, 30, 1, 10, '{"stress":3}', 8, 17, 'yahoo', 8, null, null, 1, 'ict', false, 50, 8, '', '{}', 10),
('digital_marketing', 'Digital Marketing', '📣', 'Run ads, grow a page, sell online. Needs the ICT basics first.',
 'UNIBEN Ugbowo Campus (library)', '{uniben}', '{}', 18000, 4, 120, 30, 1, 10, '{"stress":3}', 8, 17, 'business', 6, 'ict', null, 1, 'digital_marketing', false, 50, 8, '', '{}', 20),
('accounting', 'Accounting', '🧾', 'Double entry, ledgers and the trial balance. Final class has a written exam.',
 'UNIBEN Ugbowo Campus (lecture hall)', '{uniben}', '{}', 25000, 6, 120, 35, 1, 12, '{"stress":4}', 8, 17, 'business', 8, null, 'business', 2, 'accounting', true, 45, 7,
 'Written exam: the better your Business skill, the better your chance.', '{}', 30),
('catering', 'Catering & Hospitality', '🍽️', 'Pro kitchen, food safety and service. Final class is a practical cook-off.',
 'UNIBEN Ugbowo Campus (the quad)', '{uniben}', '{}', 20000, 5, 150, 35, 1, 14, '{"hunger":-6,"hygiene":-4}', 8, 17, 'cooking', 8, null, null, 1, 'catering', true, 55, 6,
 'Cook-off: the sweeter your hand (Cooking skill), the better your chance.', '{}', 40),
('driving_school', 'Driving School', '🚗', 'Learn the rules, the gears and the roundabout. Final class is the road test with the FRSC examiner.',
 'Any motor park (driving school bench)', '{}', '{motorpark}', 30000, 5, 90, 35, 1, 12, '{"stress":4}', 8, 18, 'driving', 8, null, null, 1, 'driving', true, 50, 8,
 'Road test: more Driving skill, more steady hands.', '{}', 50),
('music_production', 'Music Production', '🎚️', 'Beats, mixing and mastering with UNIBEN''s music department. For people who already play the decks.',
 'UNIBEN Ugbowo Campus (the quad)', '{uniben}', '{}', 35000, 6, 150, 40, 1, 12, '{"fun":6}', 8, 17, 'music', 10, null, 'music', 2, 'music_production', false, 50, 8,
 '', '{}', 60),
('mechanic_trade', 'Auto Mechanic Trade Test', '🔩', 'Apprentice at the Mechanic Village, then sit the trade test.',
 'Sapele Rd Mechanic Village (repair bay)', '{mechanic_village}', '{}', 22000, 5, 180, 35, 1, 14, '{"hygiene":-8}', null, null, 'mechanic', 10, null, null, 1, 'mechanic_trade', true, 40, 9,
 'Trade test: practical, so Mechanic skill counts a lot.', '{}', 70),
('business_mgmt', 'Business Management', '📊', 'Stock, staff, cashflow and strategy. Needs Accounting first.',
 'UNIBEN Ugbowo Campus (lecture hall)', '{uniben}', '{}', 30000, 6, 120, 35, 1, 12, '{"stress":3}', 8, 17, 'business', 8, 'accounting', null, 1, 'business_mgmt', false, 50, 8,
 '', '{}', 80),
('coding_bootcamp', 'Coding Bootcamp', '👨‍💻', 'Eight classes of real projects with the Tech Hub mentors. Needs ICT. Demo day is the exam.',
 'Bronze Tech Hub (hot desks)', '{bronze_tech_hub}', '{}', 80000, 8, 180, 40, 1, 14, '{"stress":5}', 9, 18, 'yahoo', 12, 'ict', null, 1, 'coding_bootcamp', true, 45, 7,
 'Demo day: a better IT sense (Yahoo skill) makes the panel kinder.', '{}', 90),
('uniben_bsc', 'UNIBEN Degree (BSc)', '🎓', 'The full four-year degree in four modules. Final class is the finals. Progress is never lost when you miss days.',
 'UNIBEN Ugbowo Campus (lecture hall)', '{uniben}', '{}', 180000, 12, 120, 40, 1, 14, '{"stress":5}', 8, 17, 'teaching', 5, 'ict', null, 1, 'bsc', true, 40, 6,
 'Finals: study well (Teaching skill) and you will pass.',
 '{"Year 1: Foundations","Year 2: Core courses","Year 3: Specialisation","Year 4: Project and finals"}', 100)
on conflict (id) do nothing;

-- gated by default: four career levels (docs/SCHOOL.md). req_cert text: a comma means "any of".
update public.career_levels set req_cert = 'ict,coding_bootcamp' where track_id = 'tech' and level = 4 and req_cert is null;
update public.career_levels set req_cert = 'accounting' where track_id = 'pos' and level = 4 and req_cert is null;
update public.career_levels set req_cert = 'business_mgmt' where track_id = 'trade' and level = 4 and req_cert is null;
update public.career_levels set req_cert = 'driving' where track_id = 'transport' and level = 2 and req_cert is null;

-- two NEW hustle variants that need a certificate (the open ones stay open)
insert into public.hustles
select (jsonb_populate_record(null::public.hustles, to_jsonb(h) || jsonb_build_object(
  'id', 'dj_headline', 'name', 'Headline DJ slot', 'icon', '🎛️',
  'blurb', 'The main-room slot at the big clubs. Only certified producers get booked. Better pay than the warm-up set.',
  'where_text', 'Any open club (night)', 'req_text', 'Music Production certificate. A DJ controller gives full pay.',
  'pay_min', 30000, 'pay_max', 65000, 'cooldown_seconds', 240, 'daily_cap', 2, 'no_item_pay_mult', 0.6,
  'bonus_pct', 20, 'bonus_min', 20000, 'bonus_max', 50000, 'cred_gain', 5, 'sort', 7,
  'hype_text', '🎛️ Headliner {name} dey the main room. Producer don land!', 'req_cert', 'music_production', 'min_skill_level', 1))).*
  from public.hustles h where h.id = 'dj_set'
on conflict (id) do nothing;

insert into public.hustles
select (jsonb_populate_record(null::public.hustles, to_jsonb(h) || jsonb_build_object(
  'id', 'mech_fleet', 'name', 'Fleet service contract', 'icon', '🚚',
  'blurb', 'A haulage company wants its trucks serviced. Pays well, and only certified mechanics get the contract.',
  'where_text', 'Sapele Rd Mechanic Village', 'req_text', 'Mechanic Trade Test certificate',
  'pay_min', 18000, 'pay_max', 32000, 'cost', 4000, 'seconds', 60, 'cooldown_seconds', 120, 'daily_cap', 2,
  'risk_pct', 8, 'cred_gain', 2, 'sort', 13, 'req_cert', 'mechanic_trade', 'min_skill_level', 1))).*
  from public.hustles h where h.id = 'mech_engine'
on conflict (id) do nothing;

insert into public.skill_sources (id, kind, ref, skill_id, xp, note) values
('hustle:dj_headline:music',    'hustle', 'dj_headline', 'music',    16, 'Headline DJ slot'),
('hustle:dj_headline:charisma', 'hustle', 'dj_headline', 'charisma', 4,  'Headline DJ slot'),
('hustle:mech_fleet:mechanic',  'hustle', 'mech_fleet',  'mechanic', 18, 'Fleet service contract')
on conflict (id) do nothing;

-- place cards (zone actions of kind class), on zones that exist today
insert into public.zone_actions (id, zone_id, kind, ref, label, icon, sort) values
('campus.lecture.class_ict_basics',        'campus.lecture',    'class', 'ict_basics',        null, null, 10),
('campus.lecture.class_accounting',        'campus.lecture',    'class', 'accounting',        null, null, 11),
('campus.lecture.class_business_mgmt',     'campus.lecture',    'class', 'business_mgmt',     null, null, 12),
('campus.lecture.class_uniben_bsc',        'campus.lecture',    'class', 'uniben_bsc',        null, null, 13),
('campus.library.class_digital_marketing', 'campus.library',    'class', 'digital_marketing', null, null, 10),
('campus.quad.class_catering',             'campus.quad',       'class', 'catering',          null, null, 10),
('campus.quad.class_music_production',     'campus.quad',       'class', 'music_production',  null, null, 11),
('motorpark.bench.class_driving_school',   'motorpark.bench',   'class', 'driving_school',    'Driving school', '🚗', 10),
('office.desks.class_coding_bootcamp',     'office.desks',      'class', 'coding_bootcamp',   null, null, 10),
('mechanic_village.bay.class_mechanic_trade', 'mechanic_village.bay', 'class', 'mechanic_trade', 'Apprentice trade test', '🔩', 10),
('club.dj.dj_headline',                    'club.dj',           'hustle', 'dj_headline',      null, null, 1),
('mechanic_village.bay.mech_fleet',        'mechanic_village.bay', 'hustle', 'mech_fleet',    null, null, 4)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers (revoked from clients at the end)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_school_on() returns boolean
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = 'school.enabled'), true);
$$;

create or replace function public.bl_school_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from game_config where key = p_key), p_default);
$$;

-- "ict, coding_bootcamp" -> {ict, coding_bootcamp}
create or replace function public.bl_cert_ids(p_req text) returns text[]
language sql immutable as $$
  select coalesce(array_agg(x), '{}') from (select btrim(v) as x from unnest(string_to_array(coalesce(p_req, ''), ',')) v) t where x <> '';
$$;

create or replace function public.bl_cert_has(p_uid uuid, p_req text) returns boolean
language sql stable set search_path = public as $$
  select cardinality(bl_cert_ids(p_req)) = 0
      or exists (select 1 from player_certificates pc where pc.user_id = p_uid and pc.cert_id = any (bl_cert_ids(p_req)));
$$;

-- "ICT certificate" / "ICT or Coding Bootcamp certificate" / "BSc Degree"
create or replace function public.bl_cert_need_text(p_req text) returns text
language sql stable set search_path = public as $$
  select n || case when n ~* '(certificate|degree|licen[cs]e)' then '' else ' certificate' end
    from (select coalesce(string_agg(coalesce(c.name, t.i), ' or ' order by t.o), '') as n
            from unnest(bl_cert_ids(p_req)) with ordinality as t(i, o) left join certificates c on c.id = t.i) q;
$$;

-- null = fine; otherwise {hint, message, short, cert}
create or replace function public.bl_cert_gate(p_uid uuid, p_req text) returns jsonb
language plpgsql stable set search_path = public as $$
begin
  if cardinality(bl_cert_ids(p_req)) = 0 or not bl_school_on() then return null; end if;
  if bl_cert_has(p_uid, p_req) then return null; end if;
  return jsonb_build_object('hint', 'need_cert',
    'message', 'Needs ' || bl_cert_need_text(p_req) || '. Enrol in the School app on your phone.',
    'short', 'Needs ' || bl_cert_need_text(p_req), 'cert', to_jsonb(bl_cert_ids(p_req)));
end $$;

-- the combined pay bonus (%) the player's certificates give on a career track (kind career) or a hustle (kind hustle)
create or replace function public.bl_cert_bonus_pct(p_uid uuid, p_kind text, p_ref text) returns numeric
language sql stable set search_path = public as $$
  select case when not bl_school_on() or p_ref is null then 0 else coalesce((
    select sum(c.pay_bonus_pct) from player_certificates pc join certificates c on c.id = pc.cert_id
     where pc.user_id = p_uid and c.active and c.pay_bonus_pct > 0
       and p_ref = any (case when p_kind = 'career' then c.bonus_tracks else c.bonus_hustles end)), 0) end;
$$;

create or replace function public.bl_cert_pay_mult(p_uid uuid, p_kind text, p_ref text) returns numeric
language sql stable set search_path = public as $$
  select 1 + bl_cert_bonus_pct(p_uid, p_kind, p_ref) / 100.0;
$$;

-- does the player hold the certificate that counts as a UNIBEN degree?
create or replace function public.bl_cert_degree(p_uid uuid) returns boolean
language sql stable set search_path = public as $$
  select bl_school_on() and exists (
    select 1 from player_certificates pc
     where pc.user_id = p_uid
       and pc.cert_id = coalesce(nullif((select value #>> '{}' from game_config where key = 'school.degree_cert'), ''), '-'));
$$;

-- [{id, name, icon, earned_at}] (also what the public profile shows)
create or replace function public.bl_cert_list(p_uid uuid) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'icon', c.icon, 'earned_at', pc.earned_at) order by pc.earned_at, c.sort), '[]'::jsonb)
    from player_certificates pc join certificates c on c.id = pc.cert_id where pc.user_id = p_uid;
$$;

-- career requirement JSON + the level's req_cert column
create or replace function public.bl_career_lreq(p_req jsonb, p_cert text) returns jsonb
language sql immutable as $$
  select case when cardinality(bl_cert_ids(p_cert)) = 0 then coalesce(p_req, '{}'::jsonb)
              else coalesce(p_req, '{}'::jsonb) || jsonb_build_object('cert', p_cert) end;
$$;

-- what a certificate opens (text lines), for the course cards
create or replace function public.bl_cert_unlocks(p_cert text) returns text[]
language plpgsql stable set search_path = public as $$
declare v_out text[] := '{}'; k certificates; v_names text[]; v_deg text;
begin
  select * into k from certificates where id = p_cert;
  select coalesce(array_agg(x order by o), '{}') into v_names from (
    select cl.title || ' (' || t.name || ')' as x, t.sort * 100 + cl.level as o
      from career_levels cl join career_tracks t on t.id = cl.track_id
     where t.active and p_cert = any (bl_cert_ids(cl.req_cert))) q;
  if cardinality(v_names) > 0 then v_out := v_out || ('Careers: ' || array_to_string(v_names, ', ')); end if;
  select coalesce(array_agg(t.name order by t.sort), '{}') into v_names from career_tracks t where t.active and p_cert = any (bl_cert_ids(t.req_cert));
  if cardinality(v_names) > 0 then v_out := v_out || ('Career tracks: ' || array_to_string(v_names, ', ')); end if;
  select coalesce(array_agg(x order by o), '{}') into v_names from (
    select h.name as x, h.sort as o from hustles h where h.active and p_cert = any (bl_cert_ids(h.req_cert))
    union all select j.name, j.sort + 1000 from yahoo_jobs j where j.active and p_cert = any (bl_cert_ids(j.req_cert))) q;
  if cardinality(v_names) > 0 then v_out := v_out || ('Hustles and jobs: ' || array_to_string(v_names, ', ')); end if;
  select coalesce(array_agg(c.name order by c.sort), '{}') into v_names from courses c where c.active and p_cert = any (bl_cert_ids(c.prereq_cert));
  if cardinality(v_names) > 0 then v_out := v_out || ('Courses: ' || array_to_string(v_names, ', ')); end if;
  v_deg := nullif((select value #>> '{}' from game_config where key = 'school.degree_cert'), '');
  if v_deg is not null and v_deg = p_cert then v_out := v_out || array['Counts as your UNIBEN degree']; end if;
  if k.id is not null and k.pay_bonus_pct > 0 then
    select coalesce(array_agg(n order by o), '{}') into v_names from (
      select t.name as n, t.sort as o from career_tracks t where t.id = any (k.bonus_tracks)
      union all select h.name, h.sort + 1000 from hustles h where h.id = any (k.bonus_hustles)) q;
    if cardinality(v_names) > 0 then
      v_out := v_out || ('+' || trim(trailing '.' from to_char(k.pay_bonus_pct, 'FM990.99')) || '% pay: ' || array_to_string(v_names, ', '));
    end if;
  end if;
  return v_out;
end $$;

-- seconds until the next game day starts (a game day = a Benin day in real clock mode)
create or replace function public.bl_course_secs_to_next_day() returns int
language sql stable set search_path = public as $$
  select greatest(1, ceil((1440 - (((bl_game_clock()->>'game_minutes')::bigint % 1440 + 1440) % 1440)) * 60.0 / bl_clock_speed()))::int;
$$;

-- seconds to wait before the next class (0 = ready), from the game day of the last one
create or replace function public.bl_course_wait_seconds(p_last_day bigint, p_cooldown_days int) returns int
language plpgsql stable set search_path = public as $$
declare v_today bigint := (bl_game_clock()->>'day')::bigint; v_gap bigint; v_need bigint;
begin
  v_gap := ceil(greatest(0, coalesce(p_cooldown_days, 0)) * greatest(0, bl_school_num('school.cooldown_mult', 1)))::bigint;
  if p_last_day is null or v_gap <= 0 then return 0; end if;
  v_need := p_last_day + v_gap;
  if v_today >= v_need then return 0; end if;
  return bl_course_secs_to_next_day() + ((v_need - v_today - 1) * bl_shrine_game_day_seconds())::int;
end $$;

create or replace function public.bl_course_wait_label(p_secs int) returns text
language sql immutable as $$
  select case when p_secs >= 86400 then 'in ' || (p_secs / 86400) || 'd ' || ((p_secs % 86400) / 3600) || 'h'
              when p_secs >= 3600 then 'in ' || (p_secs / 3600) || 'h ' || ((p_secs % 3600) / 60) || 'm'
              else 'in ' || greatest(1, ceil(p_secs / 60.0)::int) || ' min' end;
$$;

create or replace function public.bl_course_window_label(c courses) returns text
language sql stable set search_path = public as $$
  select case when c.hour_from is null or c.hour_to is null then null else bl_hour_label(c.hour_from) || ' – ' || bl_hour_label(c.hour_to) end;
$$;

create or replace function public.bl_course_fee(c courses) returns bigint
language sql stable set search_path = public as $$
  select greatest(0, round(c.fee * greatest(0, bl_school_num('school.fee_mult', 1))))::bigint;
$$;

create or replace function public.bl_course_at(c courses, l locations) returns boolean
language sql stable set search_path = public as $$
  select l.id is not null and ((l.id = any (c.location_ids)) or (l.scene = any (c.scenes)));
$$;

-- the exam pass chance (%) for the player now: base + per level above 1 of the course skill, clamped. null = no exam
create or replace function public.bl_course_exam_chance(p_uid uuid, c courses) returns numeric
language sql stable set search_path = public as $$
  select case when not c.exam then null else
    greatest(bl_school_num('school.exam_min_pct', 5), least(bl_school_num('school.exam_cap_pct', 95),
      c.exam_base_pct + c.exam_per_level_pct * greatest(0, case when c.skill_id is null then 0 else bl_skill_level(p_uid, c.skill_id) - 1 end))) end;
$$;

-- the module the given class belongs to (courses with modules)
create or replace function public.bl_course_module(c courses, p_class_no int) returns text
language sql immutable as $$
  select case when cardinality(c.modules) = 0 then null
              else c.modules[least(cardinality(c.modules), greatest(1, ceil(greatest(1, p_class_no)::numeric * cardinality(c.modules) / greatest(1, c.classes))::int))] end;
$$;

-- null = may enrol; otherwise {hint, message, short}
create or replace function public.bl_course_enrol_why(p_me profiles, c courses) returns jsonb
language plpgsql stable set search_path = public as $$
declare e course_enrolments; k skills; v_lvl int;
begin
  if not bl_school_on() then
    return jsonb_build_object('hint', 'disabled', 'message', 'School is switched off for now.', 'short', 'Switched off');
  end if;
  select * into e from course_enrolments where user_id = p_me.id and course_id = c.id;
  if found and e.status = 'enrolled' then
    return jsonb_build_object('hint', 'already', 'message', 'You are already enrolled in ' || c.name || '.', 'short', 'Enrolled');
  end if;
  if c.cert_id is not null and exists (select 1 from player_certificates where user_id = p_me.id and cert_id = c.cert_id) then
    return jsonb_build_object('hint', 'have_cert', 'message', 'You already have this certificate.', 'short', 'Completed');
  end if;
  if bl_cert_gate(p_me.id, c.prereq_cert) is not null then
    return jsonb_build_object('hint', 'prereq', 'message', 'You need the ' || bl_cert_need_text(c.prereq_cert) || ' first. ' || c.name || ' builds on am.',
                              'short', 'Needs ' || bl_cert_need_text(c.prereq_cert));
  end if;
  if c.prereq_skill is not null and c.prereq_skill_level > 1 and bl_skill_on() then
    select * into k from skills where id = c.prereq_skill;
    v_lvl := bl_skill_level(p_me.id, c.prereq_skill);
    if k.id is not null and v_lvl < c.prereq_skill_level then
      return jsonb_build_object('hint', 'prereq', 'message', 'Needs ' || k.name || ' level ' || c.prereq_skill_level || ' (you are level ' || v_lvl || '). ' || coalesce(nullif(k.train_text, ''), ''),
                                'short', 'Needs ' || k.name || ' lvl ' || c.prereq_skill_level);
    end if;
  end if;
  return null;
end $$;

-- null = may attend a class now; otherwise {hint, message, short}
create or replace function public.bl_course_why(p_me profiles, c courses, p_loc locations, p_check_place boolean default true) returns jsonb
language plpgsql stable set search_path = public as $$
declare e course_enrolments; v_hour numeric := bl_hustle_hour(); v_wait int;
begin
  if not bl_school_on() then
    return jsonb_build_object('hint', 'disabled', 'message', 'School is switched off for now.', 'short', 'Switched off');
  end if;
  select * into e from course_enrolments where user_id = p_me.id and course_id = c.id;
  if not found or e.status <> 'enrolled' then
    if found and e.status = 'completed' then
      return jsonb_build_object('hint', 'completed', 'message', 'You finished ' || c.name || '. Congrats!', 'short', 'Completed');
    end if;
    return jsonb_build_object('hint', 'not_enrolled', 'message', 'Enrol in ' || c.name || ' first (School app on your phone, or tap the course at its place).', 'short', 'Enrol first');
  end if;
  if p_check_place then
    if not bl_course_at(c, p_loc) then
      return jsonb_build_object('hint', 'wrong_place', 'message', coalesce(nullif(c.where_text, ''), 'Wrong place for this class.') || ' is where this class holds.', 'short', 'Wrong place');
    end if;
    if not bl_place_open(p_loc) then
      return jsonb_build_object('hint', 'closed', 'message', p_loc.name || ' is closed right now. Opens ' || bl_hour_label(p_loc.open_hour) || '.', 'short', 'Opens ' || bl_hour_label(p_loc.open_hour));
    end if;
  end if;
  if c.hour_from is not null and c.hour_to is not null then
    if not ((c.hour_from <= c.hour_to and v_hour >= c.hour_from and v_hour < c.hour_to)
            or (c.hour_from > c.hour_to and (v_hour >= c.hour_from or v_hour < c.hour_to))) then
      return jsonb_build_object('hint', 'wrong_hours', 'message', c.name || ' classes hold between ' || bl_course_window_label(c) || '.', 'short', 'Classes ' || bl_course_window_label(c));
    end if;
  end if;
  if p_me.energy < greatest(1, c.energy_cost) then
    return jsonb_build_object('hint', 'too_tired', 'message', 'You are too tired to learn anything. Sleep or take a nap first.', 'short', 'Too tired');
  end if;
  v_wait := bl_course_wait_seconds(e.last_class_day, c.cooldown_days);
  if v_wait > 0 then
    return jsonb_build_object('hint', 'cooldown', 'message', 'One class at a time. Next ' || c.name || ' class ' || bl_course_wait_label(v_wait) || '. Your progress is safe.',
                              'short', 'Next class ' || bl_course_wait_label(v_wait), 'wait_seconds', v_wait);
  end if;
  return null;
end $$;

create or replace function public.bl_course_run_json(r course_runs) returns jsonb
language sql stable set search_path = public as $$
  select case when r.id is null then null else jsonb_build_object(
    'id', r.id, 'course_id', r.course_id, 'name', (select name from courses where id = r.course_id),
    'icon', (select icon from courses where id = r.course_id), 'class_no', r.class_no, 'started_at', r.started_at, 'resolve_at', r.resolve_at,
    'status', r.status, 'outcome', r.outcome, 'xp', r.xp, 'message', r.detail->>'message') end;
$$;

-- the full card for the School app
create or replace function public.bl_course_json(p_me profiles, c courses, p_loc locations) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  e       course_enrolments;
  k       skills;
  v_state text := 'new';
  v_done  int := 0;
  v_wait  int := 0;
  v_why   jsonb;
  v_here  jsonb;
  v_enrol jsonb;
  v_cert  certificates;
begin
  select * into e from course_enrolments where user_id = p_me.id and course_id = c.id;
  if found then
    v_state := case when e.status = 'completed' and (c.cert_id is null or exists (select 1 from player_certificates where user_id = p_me.id and cert_id = c.cert_id))
                    then 'completed' when e.status = 'completed' then 'new' else 'enrolled' end;
    v_done := case when v_state = 'new' then 0 else e.classes_done end;
  end if;
  if v_state = 'enrolled' then
    v_wait := bl_course_wait_seconds(e.last_class_day, c.cooldown_days);
    v_why := bl_course_why(p_me, c, p_loc, false);
    v_here := bl_course_why(p_me, c, p_loc, true);
  elsif v_state = 'new' then
    v_enrol := bl_course_enrol_why(p_me, c);
  end if;
  if c.skill_id is not null then select * into k from skills where id = c.skill_id; end if;
  if c.cert_id is not null then select * into v_cert from certificates where id = c.cert_id; end if;
  return jsonb_build_object(
    'id', c.id, 'name', c.name, 'icon', c.icon, 'blurb', c.blurb, 'where_text', c.where_text,
    'places', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'open', bl_place_open((select lx from locations lx where lx.id = x.id))) order by x.d)
                          from (select l.id, l.name, ((l.x - coalesce(p_loc.x, 500)) ^ 2 + (l.y - coalesce(p_loc.y, 500)) ^ 2) as d
                                  from locations l where coalesce(l.active, true) and l.private_home_owner_id is null
                                   and (l.id = any (c.location_ids) or l.scene = any (c.scenes)) order by d limit 5) x), '[]'::jsonb),
    'fee', bl_course_fee(c), 'classes', c.classes, 'class_game_minutes', c.class_game_minutes, 'class_seconds', c.class_seconds,
    'cooldown_days', ceil(c.cooldown_days * greatest(0, bl_school_num('school.cooldown_mult', 1)))::int,
    'energy_cost', c.energy_cost, 'hours', bl_course_window_label(c),
    'skill', case when k.id is not null then jsonb_build_object('id', k.id, 'name', k.name, 'icon', k.icon, 'xp_per_class', c.xp_per_class,
                                                               'level', bl_skill_level(p_me.id, k.id)) end,
    'prereq', jsonb_build_object(
        'certs', coalesce((select jsonb_agg(jsonb_build_object('id', i, 'name', coalesce((select name from certificates where id = i), i),
                                                                'ok', exists (select 1 from player_certificates where user_id = p_me.id and cert_id = i)))
                             from unnest(bl_cert_ids(c.prereq_cert)) i), '[]'::jsonb),
        'skill', case when c.prereq_skill is not null and c.prereq_skill_level > 1 then
                      (select jsonb_build_object('id', s.id, 'name', s.name, 'icon', s.icon, 'need', c.prereq_skill_level,
                                                 'have', bl_skill_level(p_me.id, s.id), 'ok', bl_skill_level(p_me.id, s.id) >= c.prereq_skill_level)
                         from skills s where s.id = c.prereq_skill) end),
    'exam', case when c.exam then jsonb_build_object('base_pct', c.exam_base_pct, 'per_level_pct', c.exam_per_level_pct,
                                                     'chance_now', bl_course_exam_chance(p_me.id, c), 'text', c.exam_text,
                                                     'fails', coalesce(e.exam_fails, 0)) end,
    'modules', to_jsonb(c.modules),
    'module_now', bl_course_module(c, v_done + 1),
    'cert', case when v_cert.id is not null then jsonb_build_object('id', v_cert.id, 'name', v_cert.name, 'icon', v_cert.icon,
                                                                    'pay_bonus_pct', v_cert.pay_bonus_pct) end,
    'unlocks', case when c.cert_id is not null then to_jsonb(bl_cert_unlocks(c.cert_id)) else '[]'::jsonb end,
    'state', v_state, 'done', v_done,
    'enrolled_at', case when v_state = 'enrolled' then e.enrolled_at end,
    'wait_seconds', v_wait, 'next_class_at', case when v_wait > 0 then bl_now() + make_interval(secs => v_wait) end,
    'final_next', v_state = 'enrolled' and v_done + 1 >= c.classes,
    -- enrol blockers (null = may enrol) and class blockers (not counting the place)
    'enrol_why', v_enrol,
    'locked', v_why,
    'here', v_state = 'enrolled' and v_here is null,
    'here_why', v_here);
end $$;

-- the zone card at the course's place: not enrolled = an instant "Enrol" buy, enrolled = a class that queues like any action
create or replace function public.bl_course_card(p_me profiles, c courses, l locations, p_id text, p_name text, p_icon text) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  e       course_enrolments;
  v_state text := 'new';
  v_done  int := 0;
  v_why   jsonb;
  v_cert  boolean;
begin
  select * into e from course_enrolments where user_id = p_me.id and course_id = c.id;
  v_cert := c.cert_id is not null and exists (select 1 from player_certificates where user_id = p_me.id and cert_id = c.cert_id);
  if found and e.status = 'enrolled' then v_state := 'enrolled'; v_done := e.classes_done;
  elsif v_cert then v_state := 'completed'; v_done := c.classes; end if;
  if v_state = 'new' then v_why := bl_course_enrol_why(p_me, c);
  elsif v_state = 'enrolled' then v_why := bl_course_why(p_me, c, l, true);
  else v_why := jsonb_build_object('short', 'Completed'); end if;
  return jsonb_build_object(
    'id', p_id, 'kind', 'class', 'ref', c.id, 'name', p_name, 'icon', p_icon,
    'cost', case when v_state = 'new' then bl_course_fee(c) else 0 end,
    'seconds', c.class_seconds, 'instant', v_state = 'new',
    'class_state', v_state, 'classes', c.classes, 'done', v_done, 'game_minutes', c.class_game_minutes,
    'exam_next', c.exam and v_state = 'enrolled' and v_done + 1 >= c.classes,
    'module', case when v_state = 'enrolled' then bl_course_module(c, v_done + 1) end,
    'cert_name', (select name from certificates where id = c.cert_id),
    'class_skill', case when c.skill_id is not null then (select jsonb_build_object('icon', s.icon, 'name', s.name, 'xp', c.xp_per_class) from skills s where s.id = c.skill_id) end,
    'locked', v_why->>'short');
end $$;

-- hand out a certificate (once). Returns {cert, name, icon, unlocks, new} and writes the 'graduated' event (toast + confetti)
create or replace function public.bl_cert_award(p_uid uuid, p_cert text, p_source text, p_course text) returns jsonb
language plpgsql set search_path = public as $$
declare k certificates; v_n int; v_un text[];
begin
  select * into k from certificates where id = p_cert;
  if not found then return null; end if;
  insert into player_certificates (user_id, cert_id, earned_at, source, course_id)
  values (p_uid, p_cert, bl_now(), p_source, p_course) on conflict (user_id, cert_id) do nothing;
  get diagnostics v_n = row_count;
  v_un := bl_cert_unlocks(p_cert);
  if v_n > 0 then
    perform bl_event(p_uid, 'graduated', k.icon || ' ' || k.name || (case when k.name ~* '(certificate|degree|licen[cs]e)' then '' else ' certificate' end) || '!',
      case when cardinality(v_un) > 0 then array_to_string(v_un, ' · ') else 'Well done. E don show for your profile.' end,
      jsonb_build_object('cert', k.id, 'name', k.name, 'icon', k.icon, 'course', p_course, 'source', p_source, 'unlocks', to_jsonb(v_un)));
  end if;
  return jsonb_build_object('cert', k.id, 'name', k.name, 'icon', k.icon, 'unlocks', to_jsonb(v_un), 'new', v_n > 0);
end $$;

-- finish a class: exam on the final class, progress, XP, graduation. Returns the result JSON.
create or replace function public.bl_course_resolve(p_id bigint) returns jsonb
language plpgsql set search_path = public as $$
declare
  r      course_runs;
  c      courses;
  e      course_enrolments;
  v_now  timestamptz := bl_now();
  v_out  text := 'ok';
  v_chance numeric;
  v_xp   int := 0;
  v_aw   jsonb;
  v_done int;
  v_grad jsonb;
  v_msg  text;
  v_final boolean;
begin
  select * into r from course_runs where id = p_id for update;
  if not found then return jsonb_build_object('status', 'none'); end if;
  if r.status <> 'running' then
    return jsonb_build_object('status', r.status, 'already', true, 'course_id', r.course_id, 'outcome', r.outcome, 'xp', r.xp);
  end if;
  perform 1 from profiles where id = r.user_id for update;
  select * into c from courses where id = r.course_id;
  select * into e from course_enrolments where user_id = r.user_id and course_id = r.course_id for update;
  v_done := coalesce(e.classes_done, 0);
  v_final := r.class_no >= c.classes;
  if v_final and c.exam then
    v_chance := bl_course_exam_chance(r.user_id, c);
    if bl_rand() * 100 < v_chance then v_out := 'pass'; else v_out := 'fail'; end if;
  end if;
  if v_out = 'fail' then
    update course_enrolments set exam_fails = exam_fails + 1, updated_at = v_now where user_id = r.user_id and course_id = r.course_id;
    v_msg := 'You missed the pass mark (' || round(v_chance) || '% chance). Retake the final class. No wahala, your progress dey safe.';
  else
    v_done := least(c.classes, v_done + 1);
    update course_enrolments set classes_done = v_done, updated_at = v_now where user_id = r.user_id and course_id = r.course_id;
    if c.skill_id is not null and c.xp_per_class > 0 then
      v_aw := bl_skill_award(r.user_id, 'course', c.id);
      select coalesce(sum((x->>'gain')::int), 0) into v_xp from jsonb_array_elements(coalesce(v_aw, '[]'::jsonb)) x;
    end if;
    if v_done >= c.classes then
      update course_enrolments set status = 'completed', completed_at = v_now where user_id = r.user_id and course_id = r.course_id;
      if c.cert_id is not null then v_grad := bl_cert_award(r.user_id, c.cert_id, 'course', c.id); end if;
      v_msg := case when v_out = 'pass' then 'You passed the exam! ' else 'Last class done. ' end || 'Graduation time!';
    else
      v_msg := 'Class ' || v_done || ' of ' || c.classes || ' done' || case when v_xp > 0 then '. +' || v_xp || ' XP' else '' end || '.';
    end if;
  end if;
  update course_runs set status = 'done', outcome = v_out, xp = v_xp, resolved_at = v_now,
         detail = jsonb_build_object('message', v_msg, 'chance', v_chance, 'done', v_done)
   where id = r.id;
  update profiles set busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
   where id = r.user_id and busy_label like 'Class:%';
  return jsonb_build_object('status', 'done', 'course_id', c.id, 'name', c.name, 'icon', c.icon, 'class_no', r.class_no, 'classes', c.classes,
                            'done', v_done, 'outcome', v_out, 'xp', v_xp, 'exam_chance', v_chance, 'message', v_msg, 'graduated', v_grad,
                            'skills', v_aw);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.course_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_me  profiles;
  v_loc locations;
  r     course_runs;
  v_res jsonb;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    return jsonb_build_object('enabled', false, 'run', null, 'courses', '[]'::jsonb, 'certificates', '[]'::jsonb);
  end if;
  select * into r from course_runs where user_id = v_uid and status = 'running' order by id desc limit 1;
  if found and r.resolve_at <= bl_now() then
    v_res := bl_course_resolve(r.id);
    r := null;
    select * into v_me from profiles where id = v_uid;
  end if;
  select * into v_loc from locations where id = v_me.location_id;
  return jsonb_build_object(
    'enabled', bl_school_on(),
    'cash', v_me.cash, 'bank', v_me.bank, 'location', v_me.location_id,
    'degree_cert', nullif((select value #>> '{}' from game_config where key = 'school.degree_cert'), ''),
    'courses', coalesce((select jsonb_agg(bl_course_json(v_me, c, v_loc) order by c.sort, c.id) from courses c where c.active), '[]'::jsonb),
    'certificates', bl_cert_list(v_uid),
    'run', bl_course_run_json(r),
    'resolved', v_res,
    'history', coalesce((select jsonb_agg(bl_course_run_json(x) order by x.id desc)
                           from (select * from course_runs where user_id = v_uid and status = 'done' order by id desc limit 6) x), '[]'::jsonb));
end $$;

create or replace function public.course_enrol(p_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me  profiles := bl_me();
  c     courses;
  v_why jsonb;
  v_fee bigint;
begin
  if not bl_school_on() then
    raise exception 'School is switched off for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into c from courses where id = p_id and active;
  if not found then
    raise exception 'No such course.' using errcode = 'P0001', hint = 'bad_course';
  end if;
  perform 1 from profiles where id = v_me.id for update;
  v_me := bl_me();
  v_why := bl_course_enrol_why(v_me, c);
  if v_why is not null then
    raise exception '%', v_why->>'message' using errcode = 'P0001', hint = v_why->>'hint';
  end if;
  v_fee := bl_course_fee(c);
  if v_fee > 0 then
    if v_me.cash + v_me.bank < v_fee then
      raise exception '% costs % to enrol. You have % (cash + bank).', c.name, bl_naira(v_fee), bl_naira(v_me.cash + v_me.bank)
        using errcode = 'P0001', hint = 'not_enough_money';
    end if;
    perform bl_hustle_charge(v_me.id, v_fee, 'course_fee', jsonb_build_object('course', c.id, 'name', c.name));
  end if;
  insert into course_enrolments (user_id, course_id, status, classes_done, fee_paid, enrolled_at, completed_at, last_class_day, last_class_at, exam_fails, updated_at)
  values (v_me.id, c.id, 'enrolled', 0, v_fee, bl_now(), null, null, null, 0, bl_now())
  on conflict (user_id, course_id) do update
    set status = 'enrolled', classes_done = 0, fee_paid = excluded.fee_paid, enrolled_at = excluded.enrolled_at, completed_at = null,
        last_class_day = null, last_class_at = null, exam_fails = 0, updated_at = excluded.updated_at;
  return jsonb_build_object('course_id', c.id, 'name', c.name, 'paid', v_fee, 'classes', c.classes,
    'message', 'You don enrol for ' || c.name || case when v_fee > 0 then ' (' || bl_naira(v_fee) || ')' else '' end || '. ' || c.classes
               || ' classes to go' || case when nullif(c.where_text, '') is not null then ' at ' || c.where_text else '' end || '.');
end $$;

create or replace function public.course_start_class(p_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  c       courses;
  e       course_enrolments;
  l       locations;
  v_why   jsonb;
  v_now   timestamptz := bl_now();
  v_until timestamptz;
  v_id    bigint;
  v_old   course_runs;
  v_no    int;
begin
  if not bl_school_on() then
    raise exception 'School is switched off for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select * into c from courses where id = p_id and active;
  if not found then
    raise exception 'No such course.' using errcode = 'P0001', hint = 'bad_course';
  end if;
  perform 1 from profiles where id = v_me.id for update;
  v_me := bl_me();
  select * into v_old from course_runs where user_id = v_me.id and status = 'running' order by id desc limit 1;
  if found and v_old.resolve_at <= v_now then
    perform bl_course_resolve(v_old.id);
    v_me := bl_me();
  end if;
  perform bl_assert_free(v_me);
  if exists (select 1 from course_runs where user_id = v_me.id and status = 'running') then
    raise exception 'Finish the class you dey attend first.' using errcode = 'P0001', hint = 'busy';
  end if;
  select * into l from locations where id = v_me.location_id;
  v_why := bl_course_why(v_me, c, l, true);
  if v_why is not null then
    raise exception '%', v_why->>'message' using errcode = 'P0001', hint = v_why->>'hint';
  end if;
  select * into e from course_enrolments where user_id = v_me.id and course_id = c.id;
  v_no := e.classes_done + 1;
  perform bl_adjust_needs(v_me.id, coalesce(c.effects, '{}'::jsonb) || jsonb_build_object('energy', -c.energy_cost + coalesce((c.effects->>'energy')::numeric, 0)));
  v_until := v_now + make_interval(secs => c.class_seconds);
  insert into course_runs (user_id, course_id, class_no, location_id, started_at, resolve_at)
  values (v_me.id, c.id, v_no, v_me.location_id, v_now, v_until) returning id into v_id;
  update course_enrolments set last_class_day = (bl_game_clock()->>'day')::bigint, last_class_at = v_now, updated_at = v_now
   where user_id = v_me.id and course_id = c.id;
  -- can't be stopped halfway (busy_needs_from stays null, so activity_stop refuses)
  update profiles set busy_until = v_until, busy_started_at = v_now, busy_label = 'Class: ' || c.name, busy_needs_from = null where id = v_me.id;
  return jsonb_build_object('run_id', v_id, 'busy_until', v_until, 'resolve_at', v_until, 'seconds', c.class_seconds, 'course_id', c.id,
                            'name', c.name, 'icon', c.icon, 'class_no', v_no, 'classes', c.classes, 'started_at', v_now,
                            'exam', c.exam and v_no >= c.classes,
                            'message', c.name || ': class ' || v_no || ' of ' || c.classes || ' don start.' || case when c.exam and v_no >= c.classes then ' Exam day!' else '' end);
end $$;

create or replace function public.course_finish_class() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  r course_runs;
begin
  perform bl_me_any();
  select * into r from course_runs where user_id = v_uid and status = 'running' order by id desc limit 1;
  if not found then
    raise exception 'You are not in any class right now.' using errcode = 'P0001', hint = 'no_run';
  end if;
  if r.resolve_at > bl_now() then
    raise exception 'Hold on, about % sec more.', ceil(extract(epoch from r.resolve_at - bl_now()))::int using errcode = 'P0001', hint = 'not_yet';
  end if;
  return bl_course_resolve(r.id);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Admin RPCs: a player's certificates (read), grant and revoke (audit)
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_player_certs(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'icon', c.icon, 'earned_at', pc.earned_at,
                                                          'source', pc.source, 'course_id', pc.course_id) order by pc.earned_at)
                        from player_certificates pc join certificates c on c.id = pc.cert_id where pc.user_id = p_user), '[]'::jsonb),
    'catalog', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'icon', c.icon,
                                                             'has', exists (select 1 from player_certificates pc where pc.user_id = p_user and pc.cert_id = c.id))
                                          order by c.sort, c.id) from certificates c), '[]'::jsonb),
    'courses', coalesce((select jsonb_agg(jsonb_build_object('course_id', e.course_id, 'name', (select name from courses where id = e.course_id),
                                                             'status', e.status, 'done', e.classes_done,
                                                             'classes', (select classes from courses where id = e.course_id)) order by e.enrolled_at)
                           from course_enrolments e where e.user_id = p_user), '[]'::jsonb));
end $$;

create or replace function public.admin_grant_cert(p_user uuid, p_cert text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  k certificates;
  v_r jsonb;
begin
  if not exists (select 1 from profiles where id = p_user) then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  select * into k from certificates where id = p_cert;
  if not found then
    raise exception 'That certificate doesn''t exist.' using errcode = 'P0001', hint = 'bad_cert';
  end if;
  if exists (select 1 from player_certificates where user_id = p_user and cert_id = p_cert) then
    raise exception 'They already have the % certificate.', k.name using errcode = 'P0001', hint = 'already';
  end if;
  v_r := bl_cert_award(p_user, p_cert, 'admin', null);
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'grant_cert', p_user, jsonb_build_object('cert', p_cert, 'name', k.name, 'note', nullif(btrim(coalesce(p_note, '')), '')));
  return jsonb_build_object('message', k.name || ' certificate granted.', 'cert', p_cert);
end $$;

create or replace function public.admin_revoke_cert(p_user uuid, p_cert text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  k certificates;
  v_src text;
begin
  select * into k from certificates where id = p_cert;
  if not found then
    raise exception 'That certificate doesn''t exist.' using errcode = 'P0001', hint = 'bad_cert';
  end if;
  delete from player_certificates where user_id = p_user and cert_id = p_cert returning source into v_src;
  if not found then
    raise exception 'They don''t have the % certificate.', k.name using errcode = 'P0001', hint = 'not_held';
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'revoke_cert', p_user, jsonb_build_object('cert', p_cert, 'name', k.name, 'was_source', v_src, 'note', nullif(btrim(coalesce(p_note, '')), '')));
  return jsonb_build_object('message', k.name || ' certificate removed.', 'cert', p_cert);
end $$;

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

-- career requirement: "cert" key (the label flips to "Needs ..." while it is missing)
select pg_temp.bl_patch('public.bl_career_reqs(public.profiles, jsonb, boolean)', $j$[
 {"done": "'key', 'cert'", "marker": "if jsonb_typeof(p_req->'min_level_track') = 'object' then",
  "new": "if nullif(p_req->>'cert', '') is not null then\n    v_out := v_out || jsonb_build_array(jsonb_build_object('key', 'cert', 'cert', p_req->>'cert',\n      'label', case when bl_cert_has(p_me.id, p_req->>'cert') or not bl_school_on() then bl_cert_need_text(p_req->>'cert') else 'Needs ' || bl_cert_need_text(p_req->>'cert') end,\n      'met', bl_cert_has(p_me.id, p_req->>'cert') or not bl_school_on()));\n  end if;\n  if jsonb_typeof(p_req->'min_level_track') = 'object' then"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_career_entry_level(public.profiles, text)', $j$[
 {"done": "bl_career_lreq(", "marker": "select requirements into v_req from career_levels where track_id = p_track and level = v_lvl;",
  "new": "select bl_career_lreq(requirements, req_cert) into v_req from career_levels where track_id = p_track and level = v_lvl;"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_career_info(public.profiles)', $j$[
 {"done": "bl_career_lreq(", "marker": "'requirements', bl_career_reqs(p_me, nxt.requirements, true));",
  "new": "'requirements', bl_career_reqs(p_me, bl_career_lreq(nxt.requirements, nxt.req_cert), true));"},
 {"done": "bl_cert_pay_mult(", "marker": "* bl_cfg('career.pay_mult') / 10.0) * 10)::bigint,",
  "new": "* bl_cfg('career.pay_mult') * bl_cert_pay_mult(p_me.id, 'career', p_me.job_id) / 10.0) * 10)::bigint,"},
 {"done": "'cert_bonus_pct'", "marker": "'perf_now', bl_career_perf(p_me),",
  "new": "'perf_now', bl_career_perf(p_me), 'cert_bonus_pct', bl_cert_bonus_pct(p_me.id, 'career', t.id),"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_settle_shift(uuid)', $j$[
 {"done": "bl_career_lreq(", "marker": "v_reqs := bl_career_reqs(v_me, nxt.requirements, true);",
  "new": "v_reqs := bl_career_reqs(v_me, bl_career_lreq(nxt.requirements, nxt.req_cert), true);"}
]$j$::jsonb);

select pg_temp.bl_patch('public.jobs_catalog()', $j$[
 {"done": "bl_career_lreq(", "marker": "bl_career_reqs(v_me, cl.requirements, false)",
  "new": "bl_career_reqs(v_me, bl_career_lreq(cl.requirements, cl.req_cert), false)"},
 {"done": "'req_cert', t.req_cert", "marker": "'entry_level', bl_career_entry_level(v_me, t.id),",
  "new": "'req_cert', t.req_cert, 'cert_gate', bl_cert_gate(v_me.id, t.req_cert),\n        'cert_bonus_pct', bl_cert_bonus_pct(v_me.id, 'career', t.id),\n        'entry_level', bl_career_entry_level(v_me, t.id),"}
]$j$::jsonb);

select pg_temp.bl_patch('public.job_apply(text)', $j$[
 {"done": "bl_cert_gate(", "marker": "v_lvl := bl_career_entry_level(v_me, t.id);",
  "new": "if bl_cert_gate(v_me.id, t.req_cert) is not null then\n    raise exception '%', bl_cert_gate(v_me.id, t.req_cert)->>'message' using errcode = 'P0001', hint = 'need_cert';\n  end if;\n  v_lvl := bl_career_entry_level(v_me, t.id);"}
]$j$::jsonb);

select pg_temp.bl_patch('public.work_shift()', $j$[
 {"done": "bl_cert_pay_mult(", "marker": "v_pay := bl_charm_pay(v_me.id, v_pay);",
  "new": "v_pay := bl_charm_pay(v_me.id, v_pay);\n  v_pay := (round(v_pay * bl_cert_pay_mult(v_me.id, 'career', v_me.job_id) / 10.0) * 10)::bigint;"}
]$j$::jsonb);

-- a BSc (school.degree_cert) counts as the UNIBEN degree
select pg_temp.bl_patch('public.bl_has_degree(public.profiles)', $j$[
 {"done": "bl_cert_degree(", "marker": "or (p_me.job_id = 'education' and p_me.job_level >= bl_cfg('career.degree_level')::int);",
  "new": "or (p_me.job_id = 'education' and p_me.job_level >= bl_cfg('career.degree_level')::int)\n      or bl_cert_degree(p_me.id);"}
]$j$::jsonb);

-- hustles: certificate gate and pay bonus
select pg_temp.bl_patch('public.bl_hustle_why(public.profiles, public.hustles, public.locations, boolean)', $j$[
 {"done": "bl_cert_gate(", "marker": "if p_check_place then",
  "new": "if bl_cert_gate(p_me.id, h.req_cert) is not null then\n    return bl_cert_gate(p_me.id, h.req_cert);\n  end if;\n  if p_check_place then"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_hustle_pay_mult(uuid, public.hustles)', $j$[
 {"done": "bl_cert_pay_mult(", "marker": "* bl_skill_pay_mult(p_uid, 'hustle', h.id);",
  "new": "* bl_skill_pay_mult(p_uid, 'hustle', h.id) * bl_cert_pay_mult(p_uid, 'hustle', h.id);"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_hustle_json(public.profiles, public.hustles, public.locations)', $j$[
 {"done": "'cert_bonus_pct'", "marker": "'locked', v_why);",
  "new": "'req_cert', h.req_cert, 'cert_bonus_pct', bl_cert_bonus_pct(p_me.id, 'hustle', h.id),\n    'locked', v_why);"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_hustle_card(public.profiles, public.hustles, public.locations, text, text, text)', $j$[
 {"done": "'cert_bonus_pct'", "marker": "'locked', v_why->>'short');",
  "new": "'cert_bonus_pct', bl_cert_bonus_pct(p_me.id, 'hustle', h.id),\n    'locked', v_why->>'short');"}
]$j$::jsonb);

-- yahoo jobs: certificate gate
select pg_temp.bl_patch('public.yahoo_job_start(text, bigint)', $j$[
 {"done": "bl_cert_gate(", "marker": "v_where := bl_yahoo_where(v_me);",
  "new": "if bl_cert_gate(v_me.id, j.req_cert) is not null then\n    raise exception '%', bl_cert_gate(v_me.id, j.req_cert)->>'message' using errcode = 'P0001', hint = 'need_cert';\n  end if;\n  v_where := bl_yahoo_where(v_me);"}
]$j$::jsonb);

select pg_temp.bl_patch('public.yahoo_status()', $j$[
 {"done": "then 'cert' end", "marker": "when bl_skill_gate(v_uid, 'yahoo', j.id, j.min_skill_level) is not null then 'skill_level' end,",
  "new": "when bl_skill_gate(v_uid, 'yahoo', j.id, j.min_skill_level) is not null then 'skill_level'\n                              when bl_cert_gate(v_uid, j.req_cert) is not null then 'cert' end,"},
 {"done": "'cert_short'", "marker": "'min_tier', j.min_tier, 'min_skill_level', j.min_skill_level,",
  "new": "'min_tier', j.min_tier, 'min_skill_level', j.min_skill_level, 'req_cert', j.req_cert, 'cert_short', bl_cert_gate(v_uid, j.req_cert)->>'short',"}
]$j$::jsonb);

-- XP: course classes feed bl_skill_award (kind 'course', ref = course id; the course's own skill and xp_per_class)
select pg_temp.bl_patch('public.bl_skill_award(uuid, text, text)', $j$[
 {"done": "from courses c join skills k", "marker": "for r in select s.skill_id, s.xp as base, k.name, k.icon, k.trait_keys",
  "new": "for r in select q.skill_id, q.base, q.name, q.icon, q.trait_keys from (select s.skill_id, s.xp as base, k.name, k.icon, k.trait_keys, k.sort"},
 {"done": "from courses c join skills k", "marker": "where s.active and k.active and s.kind = p_kind and s.ref = p_ref",
  "new": "where s.active and k.active and s.kind = p_kind and s.ref = p_ref\n           union all\n           select c.skill_id, c.xp_per_class, k.name, k.icon, k.trait_keys, k.sort from courses c join skills k on k.id = c.skill_id\n            where p_kind = 'course' and c.id = p_ref and c.skill_id is not null and k.active) q"},
 {"done": "order by q.sort, q.skill_id loop", "marker": "order by k.sort, s.skill_id loop",
  "new": "order by q.sort, q.skill_id loop"}
]$j$::jsonb);

-- the public profile carries the certificates
select pg_temp.bl_patch('public.get_public_profile(uuid)', $j$[
 {"done": "bl_cert_list(", "marker": "'yahoo_rank', bl_yahoo_rank_public(id))",
  "new": "'yahoo_rank', bl_yahoo_rank_public(id), 'certificates', bl_cert_list(id))"}
]$j$::jsonb);

-- ledger text
select pg_temp.bl_patch('public.bl_hustle_ledger_label(text, jsonb)', $j$[
 {"done": "when 'course_fee'", "marker": "when 'referral' then 'Referral bonus'",
  "new": "when 'course_fee' then 'Course fee: ' || coalesce(nullif(p_meta->>'name', ''), 'class')\n    when 'referral' then 'Referral bonus'"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_ledger_label(text, jsonb)', $j$[
 {"done": "when 'course_fee'", "marker": "when 'tip_in' then return bl_hustle_ledger_label(p_reason, p_meta);",
  "new": "when 'tip_in' then return bl_hustle_ledger_label(p_reason, p_meta);\n    when 'course_fee' then return bl_hustle_ledger_label(p_reason, p_meta);"}
]$j$::jsonb);

-- the zone card at the place: class cards
select pg_temp.bl_patch('public.place_interior(text)', $j$[
 {"done": "bl_course_card(", "marker": "-- open a tab of the place sheet (bank counter, PoS, the whole shop...)",
  "new": "-- R4 school: course cards (enrol, attend a class)\n               select za.sort, c.sort, bl_course_card(v_me, c, l, za.id, coalesce(za.label, c.name), coalesce(za.icon, c.icon))\n                 from zone_actions za join courses c on c.id = za.ref\n                where za.zone_id = z.id and za.kind = 'class' and za.active and c.active and bl_school_on()\n               union all\n               -- open a tab of the place sheet (bank counter, PoS, the whole shop...)"}
]$j$::jsonb);

select pg_temp.bl_patch('public.bl_zone_action_check()', $j$[
 {"done": "no course", "marker": "elsif new.kind = 'panel' and new.ref not in",
  "new": "elsif new.kind = 'class' and not exists (select 1 from courses where id = new.ref) then\n    raise exception 'Zone action %: no course \"%\".', new.id, new.ref using errcode = 'P0001', hint = 'bad_value';\n  elsif new.kind = 'panel' and new.ref not in"}
]$j$::jsonb);

-- admin Content editor: the two new tables + the new gate columns
select pg_temp.bl_patch('public.bl_admin_table_spec(text)', $j$[
 {"done": "when 'courses' then", "marker": "when 'skills' then",
  "new": "when 'courses' then '{\"pk\":[\"id\"],\"insert\":true,\"order\":\"sort, id\",\n      \"cols\":{\"name\":\"text\",\"icon\":\"text\",\"blurb\":\"text\",\"where_text\":\"text\",\"location_ids\":\"arr\",\"scenes\":\"arr\",\"fee\":\"money\",\n              \"classes\":\"int\",\"class_game_minutes\":\"int\",\"class_seconds\":\"int\",\"cooldown_days\":\"int\",\"energy_cost\":\"int\",\"effects\":\"obj\",\n              \"hour_from\":\"num_null\",\"hour_to\":\"num_null\",\"skill_id\":\"text_null\",\"xp_per_class\":\"num\",\"prereq_cert\":\"text_null\",\n              \"prereq_skill\":\"text_null\",\"prereq_skill_level\":\"int\",\"cert_id\":\"text_null\",\"exam\":\"bool\",\"exam_base_pct\":\"num\",\n              \"exam_per_level_pct\":\"num\",\"exam_text\":\"text\",\"modules\":\"arr\",\"sort\":\"int\",\"active\":\"bool\"}}'\n    when 'certificates' then '{\"pk\":[\"id\"],\"insert\":true,\"order\":\"sort, id\",\n      \"cols\":{\"name\":\"text\",\"icon\":\"text\",\"blurb\":\"text\",\"pay_bonus_pct\":\"num\",\"bonus_tracks\":\"arr\",\"bonus_hustles\":\"arr\",\"sort\":\"int\",\"active\":\"bool\"}}'\n    when 'skills' then"},
 {"done": "\"min_skill_level\":\"int\",\"req_cert\"", "marker": "\"hour_mult\":\"obj\",\"min_skill_level\":\"int\",",
  "new": "\"hour_mult\":\"obj\",\"min_skill_level\":\"int\",\"req_cert\":\"text_null\","},
 {"done": "\"min_tier\":\"int\",\"min_skill_level\":\"int\",\"req_cert\"", "marker": "\"cooldown_seconds\":\"int\",\"min_tier\":\"int\",\"min_skill_level\":\"int\",",
  "new": "\"cooldown_seconds\":\"int\",\"min_tier\":\"int\",\"min_skill_level\":\"int\",\"req_cert\":\"text_null\","},
 {"done": "\"requirements\":\"obj\",\"perks\":\"obj\",\"req_cert\"", "marker": "\"requirements\":\"obj\",\"perks\":\"obj\"",
  "new": "\"requirements\":\"obj\",\"perks\":\"obj\",\"req_cert\":\"text_null\""},
 {"done": "\"skill\":\"text_null\",\"req_cert\"", "marker": "\"location_ids\":\"arr\",\"skill\":\"text_null\",",
  "new": "\"location_ids\":\"arr\",\"skill\":\"text_null\",\"req_cert\":\"text_null\","}
]$j$::jsonb);

-- ---------------------------------------------------------------------------------------------
-- 8. Grants
-- ---------------------------------------------------------------------------------------------
revoke all on function public.bl_school_on() from public, anon, authenticated;
revoke all on function public.bl_school_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_cert_ids(text) from public, anon, authenticated;
revoke all on function public.bl_cert_has(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_cert_need_text(text) from public, anon, authenticated;
revoke all on function public.bl_cert_gate(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_cert_bonus_pct(uuid, text, text) from public, anon, authenticated;
revoke all on function public.bl_cert_pay_mult(uuid, text, text) from public, anon, authenticated;
revoke all on function public.bl_cert_degree(uuid) from public, anon, authenticated;
revoke all on function public.bl_cert_list(uuid) from public, anon, authenticated;
revoke all on function public.bl_career_lreq(jsonb, text) from public, anon, authenticated;
revoke all on function public.bl_cert_unlocks(text) from public, anon, authenticated;
revoke all on function public.bl_course_secs_to_next_day() from public, anon, authenticated;
revoke all on function public.bl_course_wait_seconds(bigint, int) from public, anon, authenticated;
revoke all on function public.bl_course_wait_label(int) from public, anon, authenticated;
revoke all on function public.bl_course_window_label(public.courses) from public, anon, authenticated;
revoke all on function public.bl_course_fee(public.courses) from public, anon, authenticated;
revoke all on function public.bl_course_at(public.courses, public.locations) from public, anon, authenticated;
revoke all on function public.bl_course_exam_chance(uuid, public.courses) from public, anon, authenticated;
revoke all on function public.bl_course_module(public.courses, int) from public, anon, authenticated;
revoke all on function public.bl_course_enrol_why(public.profiles, public.courses) from public, anon, authenticated;
revoke all on function public.bl_course_why(public.profiles, public.courses, public.locations, boolean) from public, anon, authenticated;
revoke all on function public.bl_course_run_json(public.course_runs) from public, anon, authenticated;
revoke all on function public.bl_course_json(public.profiles, public.courses, public.locations) from public, anon, authenticated;
revoke all on function public.bl_course_card(public.profiles, public.courses, public.locations, text, text, text) from public, anon, authenticated;
revoke all on function public.bl_cert_award(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.bl_course_resolve(bigint) from public, anon, authenticated;

revoke all on function public.course_status() from public, anon;
grant execute on function public.course_status() to authenticated, service_role;
revoke all on function public.course_enrol(text) from public, anon;
grant execute on function public.course_enrol(text) to authenticated, service_role;
revoke all on function public.course_start_class(text) from public, anon;
grant execute on function public.course_start_class(text) to authenticated, service_role;
revoke all on function public.course_finish_class() from public, anon;
grant execute on function public.course_finish_class() to authenticated, service_role;
revoke all on function public.admin_player_certs(uuid) from public, anon;
grant execute on function public.admin_player_certs(uuid) to authenticated, service_role;
revoke all on function public.admin_grant_cert(uuid, text, text) from public, anon;
grant execute on function public.admin_grant_cert(uuid, text, text) to authenticated, service_role;
revoke all on function public.admin_revoke_cert(uuid, text, text) from public, anon;
grant execute on function public.admin_revoke_cert(uuid, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
